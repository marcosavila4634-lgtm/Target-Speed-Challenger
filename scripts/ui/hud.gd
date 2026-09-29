class_name Hud
extends CanvasLayer
## Interface do Target Flight (layout da referência TSC_Target_Flight_HUD):
## placar das equipes, etapa e tempo, pontuação provisória, chat, ejetor, velocidade,
## paraquedas, nitro e marcador de distância do alvo. Também mostra resultados e pausa.

signal pedido_continuar
signal pedido_menu
signal pedido_reiniciar

var raiz: Control
var _linhas_equipes: Array = []
var _etapa: Label
var _tempo: Label
var _box_pontuacao: VBoxContainer
var _linhas_pontuacao: Array = []
var _chat: VBoxContainer
var _ejetor: Label
var _velocidade: Velocimetro
var _paraquedas: Label
var _nitro: Label
var _nitro_barra: ColorRect
var _nitro_fundo: ColorRect
var _marcador: Control
var _marcador_texto: Label
var _mensagem: Label
var _contagem: Label
var _espectador: PanelContainer
var _espectador_texto: Label
var _overlay: Control
var _carregando: Control
var _pausa: Control
var _rotulos_veiculos := {}
var _msg_tempo := 0.0
var _final := false        # resultado final na tela: o resto do HUD fica escondido


class Losango extends Control:
	var cor := Color(0.4, 0.65, 1.0)
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		draw_colored_polygon(pts, Color(0.03, 0.07, 0.15, 0.85))
		pts.append(pts[0])
		draw_polyline(pts, cor, 3.0, true)
		var ri := r * 0.4
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -ri), c + Vector2(ri, 0), c + Vector2(0, ri), c + Vector2(-ri, 0)]), cor)


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	raiz = Control.new()
	raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz.theme = Estilo.tema()
	add_child(raiz)
	_montar_topo()
	_montar_base()
	_montar_centro()


# ------------------------------------------------------------------ montagem

func _ancorar(c: Control, preset: int, margem := 28) -> void:
	raiz.add_child(c)
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE, margem)
	match preset:
		Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_RIGHT:
			c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER:
			c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM:
			c.grow_vertical = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER:
			c.grow_vertical = Control.GROW_DIRECTION_BOTH


func _linha_cor(cor: Color, esquerda: String, direita: String, largura := 230) -> Dictionary:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var barra := ColorRect.new()
	barra.color = cor
	barra.custom_minimum_size = Vector2(5, 26)
	h.add_child(barra)
	var a := Estilo.rotulo(esquerda, 21)
	a.custom_minimum_size.x = largura
	h.add_child(a)
	var b := Estilo.rotulo(direita, 21)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	return {"caixa": h, "barra": barra, "a": a, "b": b}


func _montar_topo() -> void:
	# Placar das equipes
	var p := Estilo.painel()
	var v := VBoxContainer.new()
	p.add_child(v)
	for i in Config.EQUIPES.size():
		var l := _linha_cor(Config.EQUIPES[i].cor, Config.EQUIPES[i].nome, "0", 150)
		v.add_child(l.caixa)
		_linhas_equipes.append(l)
	_ancorar(p, Control.PRESET_TOP_LEFT)

	# Etapa e tempo
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", Estilo.caixa(Estilo.FUNDO, Estilo.BORDA, 0.0))
	var vc := VBoxContainer.new()
	vc.add_theme_constant_override("separation", -6)
	pc.add_child(vc)
	_etapa = Estilo.rotulo("ETAPA 1/4", 22, Estilo.TEXTO_FRACO)
	_etapa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vc.add_child(_etapa)
	_tempo = Estilo.rotulo("03:00", 50, Estilo.TEXTO, 700)
	_tempo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tempo.custom_minimum_size.x = 240
	vc.add_child(_tempo)
	_ancorar(pc, Control.PRESET_CENTER_TOP, 0)

	# Pontuação provisória
	var pr := Estilo.painel()
	_box_pontuacao = VBoxContainer.new()
	pr.add_child(_box_pontuacao)
	_box_pontuacao.add_child(Estilo.rotulo("PONTUAÇÃO", 20, Estilo.TEXTO_FRACO))
	_ancorar(pr, Control.PRESET_TOP_RIGHT)
	# Card 20% menor, preso pelo canto superior direito
	pr.scale = Vector2.ONE * 0.8
	pr.resized.connect(func(): pr.pivot_offset = Vector2(pr.size.x, 0))

	# Chat
	_chat = VBoxContainer.new()
	_chat.add_theme_constant_override("separation", 6)
	raiz.add_child(_chat)
	_chat.position = Vector2(28, 330)


func _montar_base() -> void:
	var pe := Estilo.painel(-0.25)
	_ejetor = Estilo.rotulo("⏏  EJETOR — PRONTO", 22)
	_ejetor.custom_minimum_size.x = 300
	pe.add_child(_ejetor)
	_ancorar(pe, Control.PRESET_BOTTOM_LEFT)

	# Velocímetro analógico acima do paraquedas e do nitro
	var vd := VBoxContainer.new()
	vd.add_theme_constant_override("separation", 10)
	_velocidade = Velocimetro.new()
	_velocidade.size_flags_horizontal = Control.SIZE_SHRINK_END
	vd.add_child(_velocidade)
	var pp := Estilo.painel(0.25)
	_paraquedas = Estilo.rotulo("☂  PARAQUEDAS — FECHADO", 22)
	_paraquedas.custom_minimum_size.x = 330
	pp.add_child(_paraquedas)
	vd.add_child(pp)
	var pn := Estilo.painel(0.25)
	var vn := VBoxContainer.new()
	pn.add_child(vn)
	_nitro = Estilo.rotulo("⚡  NITRO — PRONTO", 22)
	vn.add_child(_nitro)
	_nitro_fundo = ColorRect.new()
	_nitro_fundo.color = Color(1, 1, 1, 0.12)
	_nitro_fundo.custom_minimum_size = Vector2(330, 10)
	_nitro_barra = ColorRect.new()
	_nitro_barra.color = Estilo.DESTAQUE
	_nitro_barra.size = Vector2(330, 10)
	_nitro_fundo.add_child(_nitro_barra)
	vn.add_child(_nitro_fundo)
	vd.add_child(pn)
	_ancorar(vd, Control.PRESET_BOTTOM_RIGHT)


func _montar_centro() -> void:
	_marcador = Control.new()
	_marcador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var los := Losango.new()
	los.size = Vector2(30, 30)
	los.position = Vector2(-15, -15)
	_marcador.add_child(los)
	_marcador_texto = Estilo.rotulo("", 24, Estilo.TEXTO, 600)
	_marcador_texto.position = Vector2(22, -17)
	_marcador_texto.add_theme_constant_override("outline_size", 6)
	_marcador_texto.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_marcador.add_child(_marcador_texto)
	_marcador.visible = false
	raiz.add_child(_marcador)

	_mensagem = Estilo.rotulo("", 40, Estilo.TEXTO, 700)
	_mensagem.add_theme_constant_override("outline_size", 10)
	_mensagem.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_mensagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ancorar(_mensagem, Control.PRESET_CENTER_TOP, 150)

	_contagem = Estilo.rotulo("", 150, Color.WHITE, 800)
	_contagem.add_theme_constant_override("outline_size", 16)
	_contagem.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_contagem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ancorar(_contagem, Control.PRESET_CENTER, 0)

	_espectador = Estilo.painel()
	_espectador.add_theme_stylebox_override("panel", Estilo.caixa(Color(0.35, 0.05, 0.04, 0.85), Estilo.PERIGO))
	_espectador_texto = Estilo.rotulo("", 24, Color.WHITE, 700)
	_espectador.add_child(_espectador_texto)
	_espectador.visible = false
	_ancorar(_espectador, Control.PRESET_CENTER_TOP, 100)


# ------------------------------------------------------------------ atualização

func definir_participantes(linhas: Array) -> void:
	for l in _linhas_pontuacao:
		l.caixa.queue_free()
	_linhas_pontuacao.clear()
	for info in linhas:
		var l := _linha_cor(info.cor, info.nome, "", 150)
		l.b.custom_minimum_size.x = 170
		_box_pontuacao.add_child(l.caixa)
		_linhas_pontuacao.append(l)


func mostrar_equipes(quantidade: int) -> void:
	for i in _linhas_equipes.size():
		_linhas_equipes[i].caixa.visible = i < quantidade


func atualizar(info: Dictionary, delta: float) -> void:
	if _final:
		return
	_etapa.text = info.etapa_texto
	var t: float = maxf(info.tempo, 0.0)
	_tempo.text = "%02d:%02d" % [int(t) / 60, int(t) % 60]
	_tempo.add_theme_color_override("font_color", Estilo.PERIGO if t < 20.0 else Estilo.TEXTO)
	for i in _linhas_equipes.size():
		if i < info.equipes.size():
			_linhas_equipes[i].b.text = str(info.equipes[i])
	for i in mini(_linhas_pontuacao.size(), info.linhas.size()):
		_linhas_pontuacao[i].b.text = "—  " + info.linhas[i].status
		_linhas_pontuacao[i].b.add_theme_color_override("font_color", info.linhas[i].get("cor_status", Estilo.TEXTO))

	var v: Veiculo = info.veiculo
	if v:
		_velocidade.velocidade = v.velocidade_kmh() if not v.eliminado else 0.0
		_velocidade.faixa_vermelha = v.vel_max * 3.6
		_atualizar_equipamentos(v)
	_atualizar_marcador(info.camera, info.alvo_pos, v)
	_atualizar_rotulos(info.camera, info.veiculos, v)

	if _msg_tempo > 0.0:
		_msg_tempo -= delta
		if _msg_tempo <= 0.0:
			_mensagem.text = ""


func _atualizar_equipamentos(v: Veiculo) -> void:
	var ej := "PRONTO"
	var cor_ej := Estilo.OK
	if v.eliminado or v.paraquedas_ja_aberto or (v.travado and v._cfg.bloquear_ejetor):
		ej = "BLOQUEADO"
		cor_ej = Estilo.TEXTO_FRACO
	elif v.recarga_ejetor > 0.0:
		ej = "RECARGA"
		cor_ej = Color(1.0, 0.8, 0.3)
	elif v.rodas_no_chao == 0:
		ej = "NO AR"
		cor_ej = Estilo.TEXTO_FRACO
	_ejetor.text = "⏏  EJETOR — " + ej
	_ejetor.add_theme_color_override("font_color", cor_ej)

	var pq := "ABERTO" if v.paraquedas_aberto else "FECHADO"
	_paraquedas.text = "☂  PARAQUEDAS — " + pq
	_paraquedas.add_theme_color_override("font_color", Estilo.OK if v.paraquedas_aberto else Estilo.TEXTO)

	var total: float = v._cfg.nitro_duracao
	var ni := "PRONTO"
	var cor_ni := Estilo.TEXTO
	if not v._cfg.nitro:
		ni = "NÃO INSTALADO"
		cor_ni = Estilo.TEXTO_FRACO
	elif v.travado or v.eliminado:
		ni = "BLOQUEADO"
		cor_ni = Estilo.TEXTO_FRACO
	elif v.nitro_ativo:
		ni = "ATIVO"
		cor_ni = Color(0.5, 0.85, 1.0)
	elif v.carga_nitro <= 0.0:
		ni = "VAZIO"
		cor_ni = Estilo.TEXTO_FRACO
	_nitro.text = "⚡  NITRO — " + ni
	_nitro.add_theme_color_override("font_color", cor_ni)
	_nitro_barra.size = Vector2(_nitro_fundo.size.x * clampf(v.carga_nitro / maxf(total, 0.01), 0.0, 1.0), 10)
	_nitro_barra.color = Estilo.DESTAQUE if ni != "BLOQUEADO" else Color(0.4, 0.45, 0.55)


func _atualizar_marcador(cam: Camera3D, alvo_pos: Vector3, v: Veiculo) -> void:
	if cam == null or cam.is_position_behind(alvo_pos):
		_marcador.visible = false
		return
	_marcador.visible = true
	var tela := cam.unproject_position(alvo_pos + Vector3.UP * 6.0)
	var escala := raiz.get_viewport_rect().size / Vector2(get_viewport().get_visible_rect().size)
	_marcador.position = tela * escala
	var origem := v.global_position if v and not v.eliminado else cam.global_position
	var d := origem.distance_to(alvo_pos)
	_marcador_texto.text = ("%.1f km" % (d / 1000.0)).replace(".", ",") if d >= 1000.0 else "%d m" % int(d)


func _atualizar_rotulos(cam: Camera3D, veiculos: Array, meu: Veiculo) -> void:
	for v: Veiculo in veiculos:
		var l: Label = _rotulos_veiculos.get(v)
		if l == null:
			l = Estilo.rotulo("▼ " + v.nome_piloto, 16, v.cor_equipe, 700)
			l.add_theme_constant_override("outline_size", 5)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
			raiz.add_child(l)
			_rotulos_veiculos[v] = l
		var pos := v.global_position + Vector3.UP * (v.caixa_corpo.end.y + 1.2)
		if v.paraquedas_aberto:
			pos += Vector3.UP * 11.0
		var visivel := v != meu and not v.eliminado and v.visible and cam and not cam.is_position_behind(pos) \
			and cam.global_position.distance_to(pos) < 2500.0
		l.visible = visivel
		if visivel:
			l.position = cam.unproject_position(pos) - Vector2(l.size.x * 0.5, l.size.y)


# ------------------------------------------------------------------ mensagens

func mensagem(texto: String, cor := Estilo.TEXTO, duracao := 2.5) -> void:
	_mensagem.text = texto
	_mensagem.add_theme_color_override("font_color", cor)
	_msg_tempo = duracao


## Faixa fixa no topo: deixa claro que a câmera está seguindo outro jogador.
func espectador(texto: String, cor := Color.WHITE) -> void:
	_espectador.visible = texto != ""
	_espectador_texto.text = texto
	_espectador_texto.add_theme_color_override("font_color", cor)


func contagem(texto: String) -> void:
	_contagem.text = texto


func chat(nome: String, cor: Color, texto: String) -> void:
	var p := Estilo.painel()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var barra := ColorRect.new()
	barra.color = cor
	barra.custom_minimum_size = Vector2(4, 24)
	h.add_child(barra)
	h.add_child(Estilo.rotulo(nome + ":", 19, cor, 700))
	h.add_child(Estilo.rotulo(texto, 19))
	p.add_child(h)
	_chat.add_child(p)
	while _chat.get_child_count() > 4:
		_chat.get_child(0).free()
	var tw := p.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.8)
	tw.tween_callback(p.queue_free)


func carregando(texto: String) -> void:
	if _carregando == null:
		_carregando = ColorRect.new()
		(_carregando as ColorRect).color = Color(0.01, 0.02, 0.05)
		_carregando.set_anchors_preset(Control.PRESET_FULL_RECT)
		var l := Estilo.rotulo("", 34, Estilo.TEXTO, 600)
		l.name = "Texto"
		l.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.grow_horizontal = Control.GROW_DIRECTION_BOTH
		l.grow_vertical = Control.GROW_DIRECTION_BOTH
		_carregando.add_child(l)
		raiz.add_child(_carregando)
	(_carregando.get_node("Texto") as Label).text = texto
	_carregando.visible = true


func esconder_carregando() -> void:
	if _carregando:
		_carregando.visible = false


# ------------------------------------------------------------------ telas

func _limpar_overlay() -> void:
	if _overlay:
		_overlay.queue_free()
		_overlay = null


func _novo_overlay(titulo: String, subtitulo: String, preset := Control.PRESET_CENTER) -> VBoxContainer:
	_limpar_overlay()
	var p := Estilo.painel()
	p.custom_minimum_size = Vector2(760, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := Estilo.rotulo(titulo, 38, Estilo.TEXTO, 700)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if subtitulo != "":
		var s := Estilo.rotulo(subtitulo, 20, Estilo.TEXTO_FRACO)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(s)
	v.add_child(HSeparator.new())
	_overlay = p
	_ancorar(p, preset, 0 if preset == Control.PRESET_CENTER else 40)
	return v


## dados: {titulo, jogadores: [{nome, cor, texto, pontos}], equipes: [{nome, cor, pontos}], melhor, proxima}
func resultado_etapa(dados: Dictionary) -> void:
	var v := _novo_overlay(dados.titulo, "")
	for j in dados.jogadores:
		var l := _linha_cor(j.cor, j.nome, j.texto, 260)
		l.b.add_theme_color_override("font_color", Estilo.PERIGO if j.pontos == 0 else Estilo.TEXTO)
		v.add_child(l.caixa)
	v.add_child(HSeparator.new())
	for e in dados.equipes:
		var l := _linha_cor(e.cor, "EQUIPE " + e.nome, "%d pts" % e.pontos, 260)
		v.add_child(l.caixa)
	v.add_child(HSeparator.new())
	var m := Estilo.rotulo("★  MELHOR JOGADOR DA ETAPA: " + dados.melhor, 24, Color(1.0, 0.85, 0.4), 700)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m)
	if dados.get("proxima", "") != "":
		var pr := Estilo.rotulo("PRÓXIMA ETAPA: " + dados.proxima, 20, Estilo.TEXTO_FRACO)
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pr)


## dados: {titulo, subtitulo, equipes: [{nome, cor, pontos, detalhe}], jogadores: [{nome, cor, etapas, total}], mvp, xp}
func resultado_final(dados: Dictionary) -> void:
	# À esquerda: o centro da tela fica para a comemoração no alvo
	var v := _novo_overlay(dados.titulo, dados.subtitulo, Control.PRESET_CENTER_LEFT)
	var pos := 1
	for e in dados.equipes:
		var l := _linha_cor(e.cor, "%dº  EQUIPE %s" % [pos, e.nome], "%d pts   %s" % [e.pontos, e.detalhe], 300)
		v.add_child(l.caixa)
		pos += 1
	v.add_child(HSeparator.new())
	for j in dados.jogadores:
		var l := _linha_cor(j.cor, j.nome, "%s   =  %d" % [j.etapas, j.total], 260)
		v.add_child(l.caixa)
	v.add_child(HSeparator.new())
	var m := Estilo.rotulo("★  MVP DA PARTIDA: " + dados.mvp, 26, Color(1.0, 0.85, 0.4), 700)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m)
	if dados.get("xp", "") != "":
		var x := Estilo.rotulo(dados.xp, 21, Estilo.OK, 600)
		x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(x)
	var botoes := HBoxContainer.new()
	botoes.alignment = BoxContainer.ALIGNMENT_CENTER
	botoes.add_theme_constant_override("separation", 20)
	var b1 := Button.new()
	b1.text = "JOGAR NOVAMENTE"
	b1.pressed.connect(func(): pedido_reiniciar.emit())
	var b2 := Button.new()
	b2.text = "MENU PRINCIPAL"
	b2.pressed.connect(func(): pedido_menu.emit())
	botoes.add_child(b1)
	botoes.add_child(b2)
	v.add_child(botoes)
	b1.grab_focus()
	# Card compacto encostado à esquerda (80%): a comemoração no alvo fica livre à direita
	var card := _overlay
	card.scale = Vector2.ONE * 0.8
	card.resized.connect(func(): card.pivot_offset = Vector2(0.0, card.size.y * 0.5))
	card.pivot_offset = Vector2(0.0, card.size.y * 0.5)
	card.offset_left = 24.0
	# Só o resultado fica na tela: placar, tempo, velocímetro etc. saem da frente da comemoração
	_final = true
	for c in raiz.get_children():
		if c != _overlay:
			(c as CanvasItem).visible = false


func esconder_resultado() -> void:
	_limpar_overlay()


func pausa(mostrar: bool) -> void:
	if not mostrar:
		if _pausa:
			_pausa.queue_free()
			_pausa = null
		return
	var fundo := ColorRect.new()
	fundo.color = Color(0, 0, 0, 0.55)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz.add_child(fundo)
	_pausa = fundo
	var p := Estilo.painel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var t := Estilo.rotulo("PAUSA", 40, Estilo.TEXTO, 700)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var ajuda := Estilo.rotulo("W / S — acelerar e ré (não há freio: a ré segura o carro)  (no ar: inclinar • no paraquedas: acelerar e sustentar)\nA / D — direção  (no alvo: alterne A e D rapidamente para frear)\nESPAÇO — ejetor (com roda apoiada, antes de abrir o paraquedas)\nE — abrir / fechar paraquedas\nSHIFT — nitro (uma carga por etapa)\nMOUSE — câmera (rodinha: zoom)   •   TAB — trocar câmera de espectador", 19, Estilo.TEXTO_FRACO)
	v.add_child(ajuda)
	for par in [["CONTINUAR", pedido_continuar], ["MENU PRINCIPAL", pedido_menu]]:
		var b := Button.new()
		b.text = par[0]
		var sinal: Signal = par[1]
		b.pressed.connect(func(): sinal.emit())
		v.add_child(b)
	v.add_child(HSeparator.new())
	v.add_child(Audio.painel_volumes())
	fundo.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	(v.get_child(2) as Button).grab_focus()
