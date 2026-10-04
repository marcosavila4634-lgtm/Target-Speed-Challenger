class_name DragHud
extends CanvasLayer
## HUD do Drag Racing (dossiê cap. 11, "Drag HUD"): pista e tempo, aviso do semáforo, reação,
## rival, aderência, nitro e a avaliação de cada troca (texto e cor, sem sinal sonoro do instante
## perfeito). Tela de carregamento e tela de resultado (vitória/derrota, análise, trocas, veículo).

signal pedido_repetir
signal pedido_menu

const CORES := {
	"perfeita": Color(0.35, 0.75, 1.0), "boa": Color(0.9, 0.94, 1.0), "antecipada": Color(1.0, 0.78, 0.25),
	"atrasada": Color(1.0, 0.6, 0.2), "critica": Color(1.0, 0.3, 0.25), "patinou": Color(1.0, 0.6, 0.2),
	"afogou": Color(1.0, 0.6, 0.2), "queimada": Color(1.0, 0.25, 0.2),
}

var _raiz: Control
var _tempo: Label
var _status: Label
var _reacao: Label
var _rival: Label
var _rival_tempo: Label
var _aderencia: Label
var _aderencia_barra: ProgressBar
var _nitro: Label
var _nitro_barra: ProgressBar
var _aviso: Label
var _aviso_t := 0.0
var _carga: Control
var _barra_carga: ProgressBar
var _resultado: Control
var _dist_barra: Control
var _dist_eu: ColorRect
var _dist_rival: ColorRect


func _ready() -> void:
	layer = 5
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.theme = Estilo.tema()
	add_child(_raiz)
	_montar()
	_raiz.visible = false


func _painel(pos: Vector2, tam: Vector2, preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Estilo.caixa_neon(Estilo.PAINEL_ESCURO, Color(0.3, 0.55, 1.0, 0.75), 0.4, 10))
	p.custom_minimum_size = tam
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(p)
	_fixar(p, preset, pos, tam)
	return p


## Prende `c` num canto/borda da tela: `margem` é a distância até as bordas daquele canto.
func _fixar(c: Control, preset: int, margem: Vector2, tam: Vector2) -> void:
	var ancora := Vector2.ZERO
	var canto := margem
	match preset:
		Control.PRESET_TOP_RIGHT:
			ancora = Vector2(1, 0)
			canto = Vector2(-tam.x - margem.x, margem.y)
		Control.PRESET_BOTTOM_LEFT:
			ancora = Vector2(0, 1)
			canto = Vector2(margem.x, -tam.y - margem.y)
		Control.PRESET_BOTTOM_RIGHT:
			ancora = Vector2(1, 1)
			canto = Vector2(-tam.x - margem.x, -tam.y - margem.y)
		Control.PRESET_CENTER_TOP:
			ancora = Vector2(0.5, 0)
			canto = Vector2(-tam.x * 0.5 + margem.x, margem.y)
	c.anchor_left = ancora.x
	c.anchor_right = ancora.x
	c.anchor_top = ancora.y
	c.anchor_bottom = ancora.y
	c.offset_left = canto.x
	c.offset_top = canto.y
	c.offset_right = canto.x + tam.x
	c.offset_bottom = canto.y + tam.y


func _linha(filhos: Array, sep := 14) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for f in filhos:
		h.add_child(f)
	return h


func _coluna(filhos: Array, sep := 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for f in filhos:
		v.add_child(f)
	return v


func _barra(cor: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(260, 12)
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(0.15, 0.2, 0.3, 0.7)
	fundo.skew = Vector2(0.4, 0)
	var cheio := StyleBoxFlat.new()
	cheio.bg_color = cor
	cheio.skew = Vector2(0.4, 0)
	cheio.shadow_color = Color(cor, 0.5)
	cheio.shadow_size = 4
	b.add_theme_stylebox_override("background", fundo)
	b.add_theme_stylebox_override("fill", cheio)
	b.max_value = 1.0
	b.value = 1.0
	return b


func _montar() -> void:
	# Pista e tempo
	var p1 := _painel(Vector2(28, 24), Vector2(400, 110), Control.PRESET_TOP_LEFT)
	_tempo = Estilo.rotulo("00:00.000", 44, Color.WHITE, 700)
	_tempo.add_theme_font_override("font", Estilo.fonte_titulo(700))
	p1.add_child(_coluna([Estilo.rotulo(str(Sessao.drag_pista().get("nome", "")).to_upper(), 24, Color.WHITE, 700),
		_linha([Estilo.rotulo("TEMPO", 20, Estilo.TEXTO_FRACO, 600), _tempo], 18)]))
	# Aviso do semáforo
	var p2 := _painel(Vector2(0, 12), Vector2(440, 50), Control.PRESET_CENTER_TOP)
	_status = Estilo.rotulo("AGUARDE A LUZ VERDE", 24, Color.WHITE, 600)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p2.add_child(_status)
	# Reação e rival
	var p3 := _painel(Vector2(28, 24), Vector2(380, 110), Control.PRESET_TOP_RIGHT)
	_reacao = Estilo.rotulo("---.---", 30, Color.WHITE, 700)
	_rival = Estilo.rotulo("RIVAL", 20, Estilo.TEXTO_FRACO, 600)
	_rival_tempo = Estilo.rotulo("", 26, Color.WHITE, 700)
	p3.add_child(_coluna([_linha([Estilo.rotulo("REAÇÃO", 20, Estilo.TEXTO_FRACO, 600), _reacao], 22),
		_linha([_rival, _rival_tempo], 16)]))
	# Aderência
	var p4 := _painel(Vector2(28, 28), Vector2(380, 90), Control.PRESET_BOTTOM_LEFT)
	_aderencia = Estilo.rotulo("100%", 26, Color.WHITE, 700)
	_aderencia_barra = _barra(Estilo.AZUL_NEON)
	p4.add_child(_linha([Estilo.icone("pneus", 40, Estilo.AZUL_NEON),
		_coluna([_linha([Estilo.rotulo("ADERÊNCIA", 20, Estilo.TEXTO, 600), _aderencia], 60), _aderencia_barra])], 16))
	# Nitro
	var p5 := _painel(Vector2(28, 28), Vector2(380, 90), Control.PRESET_BOTTOM_RIGHT)
	_nitro = Estilo.rotulo("NITRO — PRONTO", 22, Color.WHITE, 700)
	_nitro_barra = _barra(Estilo.AZUL_NEON)
	p5.add_child(_linha([Estilo.icone("nitro", 40, Estilo.AZUL_NEON), _coluna([_nitro, _nitro_barra])], 16))
	# Avaliação da troca (grande, no alto do centro)
	_aviso = Label.new()
	_aviso.add_theme_font_override("font", Estilo.fonte_titulo(800))
	_aviso.add_theme_font_size_override("font_size", 64)
	_aviso.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_aviso.add_theme_constant_override("outline_size", 14)
	_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_aviso)
	_fixar(_aviso, Control.PRESET_CENTER_TOP, Vector2(0, 190), Vector2(900, 90))
	# Progresso na pista: eu x rival (barra fina embaixo do aviso do semáforo)
	_dist_barra = ColorRect.new()
	_dist_barra.color = Color(0.1, 0.15, 0.25, 0.7)
	_dist_barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_dist_barra)
	_fixar(_dist_barra, Control.PRESET_CENTER_TOP, Vector2(0, 76), Vector2(440, 6))
	_dist_rival = ColorRect.new()
	_dist_rival.color = Color(1.0, 0.45, 0.2)
	_dist_rival.size = Vector2(8, 14)
	_dist_barra.add_child(_dist_rival)
	_dist_eu = ColorRect.new()
	_dist_eu.color = Estilo.AZUL_NEON
	_dist_eu.size = Vector2(8, 14)
	_dist_barra.add_child(_dist_eu)


func mostrar(sim: bool) -> void:
	_raiz.visible = sim


func definir_rival(nome: String) -> void:
	_rival.text = nome.to_upper()


func status(texto: String, cor := Color.WHITE) -> void:
	_status.text = texto
	_status.add_theme_color_override("font_color", cor)


func avaliacao(chave: String, prefixo := "") -> void:
	_aviso.text = (prefixo + "  " if prefixo != "" else "") + DragMotor.AVALIACOES.get(chave, chave.to_upper())
	_aviso.add_theme_color_override("font_color", CORES.get(chave, Color.WHITE))
	_aviso_t = 1.3


static func formatar_tempo(t: float) -> String:
	if t == INF or t < 0.0:
		return "00:00.000"
	var minutos := int(t / 60.0)
	return "%02d:%06.3f" % [minutos, t - minutos * 60.0]


func atualizar(delta: float, m: DragMotor, rival: DragMotor, tempo_corrida: float) -> void:
	_tempo.text = formatar_tempo(tempo_corrida)
	if m.t_movimento >= 0.0:
		var r := m.reacao()
		_reacao.text = "%.3f" % r
		_reacao.add_theme_color_override("font_color", CORES.get(DragMotor.avaliar_reacao(r), Color.WHITE))
	else:
		_reacao.text = "---.---"
	if rival.chegou:
		_rival_tempo.text = "%.3f s" % rival.tempo_final()
	_aderencia.text = "%d%%" % roundi(m.aderencia_atual * 100.0)
	_aderencia_barra.value = m.aderencia_atual
	if m.nitro_ativo:
		_nitro.text = "NITRO — ATIVO"
	elif m.nitro_usado:
		_nitro.text = "NITRO — USADO"
	else:
		_nitro.text = "NITRO — PRONTO"
	_nitro_barra.value = m.nitro_restante / maxf(m.nitro_total, 0.001) if m.nitro_ativo or not m.nitro_usado else 0.0
	var fim := Sessao.drag_distancia()
	_dist_eu.position = Vector2(clampf(m.distancia / fim, 0.0, 1.0) * 432.0, -4)
	_dist_rival.position = Vector2(clampf(rival.distancia / fim, 0.0, 1.0) * 432.0, -4)
	_aviso_t -= delta
	_aviso.modulate.a = clampf(_aviso_t / 0.35, 0.0, 1.0)


# ------------------------------------------------------------------ carregamento

func carregando(nome_carro: String) -> void:
	_carga = ColorRect.new()
	(_carga as ColorRect).color = Color(0.0, 0.01, 0.03)
	_carga.set_anchors_preset(Control.PRESET_FULL_RECT)
	_carga.theme = Estilo.tema()
	add_child(_carga)
	var fotos := fotos_pista(Sessao.drag_fotos_id())
	fotos.shuffle()
	var img := TextureRect.new()
	img.texture = fotos[0] if not fotos.is_empty() else load("res://assets/ui/cartao_drag_racing.jpg")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.modulate = Color(0.62, 0.62, 0.66)
	_carga.add_child(img)
	var col := _coluna([], 16)
	col.set_anchors_preset(Control.PRESET_CENTER)
	col.position = Vector2(-460, -200)
	col.size = Vector2(920, 400)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_carga.add_child(col)
	var titulo := Label.new()
	titulo.text = "DRAG RACING"
	titulo.add_theme_font_override("font", load("res://assets/fontes/RacingSansOne-Regular.ttf"))
	titulo.add_theme_font_size_override("font_size", 96)
	titulo.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	titulo.add_theme_constant_override("outline_size", 16)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(titulo)
	var sub := Estilo.rotulo("%s  —  %s  —  %s" % [str(Sessao.drag_pista().get("nome", "")).to_upper(), "1/4 DE MILHA" if Sessao.drag_distancia() > 300.0 else "1/8 DE MILHA", nome_carro.to_upper()], 26, Color(0.8, 0.88, 1.0), 600)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	# Comandos só aqui, antes da corrida (na pista não há instruções na tela)
	var dica := Estilo.rotulo("W acelerar   •   E / D sobe marcha   •   Q / A reduz   •   SHIFT nitro\nComeça em NEUTRO: segure o giro na faixa de largada e engate a 1ª na luz verde.", 20, Estilo.TEXTO_FRACO, 500)
	dica.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(dica)
	_barra_carga = _barra(Estilo.AZUL_NEON)
	_barra_carga.custom_minimum_size = Vector2(700, 12)
	_barra_carga.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_barra_carga.value = 0.0
	col.add_child(_barra_carga)
	# Textos de arrancada (curiosidades e dicas) e as fotos da pista trocando enquanto carrega
	var textos: Array = (Config.valor("drag.textos_carga", []) as Array).duplicate()
	textos.shuffle()
	var texto := Estilo.rotulo(str(textos[0]) if not textos.is_empty() else "", 24, Color(1.0, 0.8, 0.35), 600)
	texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	texto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texto.custom_minimum_size = Vector2(900, 70)
	col.add_child(texto)
	var relogio := Timer.new()
	relogio.wait_time = 3.5
	relogio.autostart = true
	_carga.add_child(relogio)
	var vez := [0]
	relogio.timeout.connect(func():
		vez[0] += 1
		if not fotos.is_empty():
			img.texture = fotos[vez[0] % fotos.size()]
		if not textos.is_empty():
			texto.text = str(textos[vez[0] % textos.size()]))


## Fotos da pista do Drag para o carregamento e o menu (assets/ui/drag_carga, tiradas pela própria
## corrida com TSC_FOTOS_CARGA). `tomada` filtra uma só (borrachao, alinhados, arrancada, chegada).
static func fotos_pista(id: String, tomada := "") -> Array[Texture2D]:
	var lista: Array[Texture2D] = []
	for t: String in (["borrachao", "alinhados", "arrancada", "chegada"] if tomada == "" else [tomada]):
		var arq := "res://assets/ui/drag_carga/%s_%s.jpg" % [id, t]
		if ResourceLoader.exists(arq):
			lista.append(load(arq))
	return lista


func progresso_carga(v: float) -> void:
	if _barra_carga:
		_barra_carga.value = v


func esconder_carregando() -> void:
	if _carga == null:
		return
	var tw := create_tween()
	tw.tween_property(_carga, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_carga.queue_free)
	await tw.finished
	_carga = null


# ------------------------------------------------------------------ resultado

func _cartao(titulo: String, linhas: Array, largura := 440.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Estilo.caixa_neon(Estilo.PAINEL_ESCURO, Color(0.3, 0.55, 1.0, 0.8), 0.5, 10))
	p.custom_minimum_size = Vector2(largura, 0)
	var col := _coluna([Estilo.rotulo(titulo, 26, Color.WHITE, 700)], 6)
	var sep := HSeparator.new()
	col.add_child(sep)
	for l: Array in linhas:
		var nome := Estilo.rotulo(str(l[0]), 20, Estilo.TEXTO, 500)
		nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var valor := Estilo.rotulo(str(l[1]), 20, l[2] if l.size() > 2 else Color.WHITE, 700)
		col.add_child(_linha([nome, valor], 12))
	p.add_child(col)
	return p


func _cartao_tempo(nome: String, tempo: float, vencedor: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var borda := Color(0.45, 0.75, 1.0) if vencedor else Color(0.3, 0.45, 0.7, 0.7)
	p.add_theme_stylebox_override("panel", Estilo.caixa_neon(Estilo.PAINEL_ESCURO, borda, 1.2 if vencedor else 0.2, 12))
	p.custom_minimum_size = Vector2(420, 120)
	var t := Label.new()
	t.text = ("%.3f s" % tempo) if tempo < INF else "NÃO COMPLETOU"
	t.add_theme_font_override("font", Estilo.fonte_titulo(800))
	t.add_theme_font_size_override("font_size", 52)
	t.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0) if vencedor else Color.WHITE)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var n := Estilo.rotulo(("♛  " if vencedor else "") + nome.to_upper(), 28, Color.WHITE, 700)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(_coluna([n, t], 0))
	return p


## d: {vitoria, empate, nome, rival, meu: DragMotor, dele: DragMotor, recorde, recorde_anterior, xp}
func resultado(d: Dictionary) -> void:
	_raiz.visible = false
	_resultado = ColorRect.new()
	(_resultado as ColorRect).color = Color(0.0, 0.01, 0.04, 0.55)
	_resultado.set_anchors_preset(Control.PRESET_FULL_RECT)
	_resultado.theme = Estilo.tema()
	add_child(_resultado)
	var col := _coluna([], 18)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_resultado.add_child(col)
	var m: DragMotor = d.meu
	var r: DragMotor = d.dele
	var titulo := Label.new()
	titulo.text = "EMPATE" if d.empate else ("VITÓRIA" if d.vitoria else "DERROTA")
	titulo.add_theme_font_override("font", Estilo.fonte_titulo(900))
	titulo.add_theme_font_size_override("font_size", 110)
	titulo.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0) if d.vitoria or d.empate else Color(1.0, 0.45, 0.4))
	titulo.add_theme_color_override("font_shadow_color", Color(0.2, 0.45, 1.0, 0.7) if d.vitoria else Color(0.6, 0.1, 0.1, 0.6))
	titulo.add_theme_constant_override("shadow_outline_size", 18)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(titulo)
	var sub := Estilo.rotulo("CONTRA BOT  —  " + str(Sessao.drag_pista().get("nome", "")).to_upper(), 26, Color(0.7, 0.8, 1.0), 600)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	var tempos := _linha([_cartao_tempo(d.nome, m.tempo_final(), d.vitoria), _cartao_tempo(d.rival, r.tempo_final(), not d.vitoria and not d.empate)], 30)
	tempos.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tempos)

	# Análise da corrida
	var reac := m.reacao()
	var av_reac := DragMotor.avaliar_reacao(reac)
	var analise := [
		["REAÇÃO", ("%.3f s — %s" % [reac, DragMotor.AVALIACOES.get(av_reac)]) if reac < INF else "—", CORES.get(av_reac, Color.WHITE)],
		["PERCURSO", ("%.3f s" % m.tempo_percurso()) if m.chegou else "—"],
		["PENALIDADE", "+%.3f s" % m.penalidade(), CORES.queimada if m.queimada else Color.WHITE],
		["TEMPO FINAL", ("%.3f s" % m.tempo_final()) if m.chegou else "—", Color(0.55, 0.85, 1.0)],
		["VELOCIDADE FINAL", "%d km/h" % roundi(m.velocidade_chegada * 3.6)],
		["LARGADA", DragMotor.AVALIACOES.get(m.largada, "—"), CORES.get(m.largada, Color.WHITE)],
	]
	var trocas := []
	for t: Dictionary in m.trocas:
		trocas.append(["%d → %d   (%d rpm)" % [t.de, t.para, roundi(t.rpm)], DragMotor.AVALIACOES.get(t.avaliacao), CORES.get(t.avaliacao, Color.WHITE)])
	if trocas.is_empty():
		trocas.append(["Nenhuma troca", ""])
	var nitro := "NÃO USADO"
	if m.nitro_marcha == 0:
		nitro = "EM NEUTRO"
	elif m.nitro_marcha > 0:
		nitro = "ATIVADO NA %dª MARCHA" % m.nitro_marcha
	var veiculo := [
		["NITRO", nitro, Color(0.55, 0.85, 1.0)],
		["DANO MECÂNICO EXTRA", "%.1f%%" % minf(m.desgaste_extra, float(Config.valor("drag.desgaste_extra_max", 5.0)))],
		["DESGASTE BÁSICO", "%.0f%%" % float(Config.valor("drag.desgaste_basico", 1.0))],
		["DESGASTE TOTAL", "%.1f%%" % m.desgaste_total()],
	]
	for e in m.erros:
		veiculo.append([e, "", CORES.critica])
	var cartoes := _linha([_cartao("ANÁLISE DA CORRIDA", analise, 470), _cartao("TROCAS DE MARCHA", trocas, 420), _cartao("VEÍCULO", veiculo, 470)], 22)
	cartoes.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(cartoes)
	# Recorde pessoal e XP
	var extra := ""
	if d.get("recorde", false):
		extra = "🏆  NOVO RECORDE PESSOAL"
	elif float(d.get("recorde_anterior", INF)) < INF:
		extra = "RECORDE PESSOAL: %.3f s" % float(d.recorde_anterior)
	var xp: Dictionary = d.get("xp", {})
	var linha_rec := _linha([], 40)
	linha_rec.alignment = BoxContainer.ALIGNMENT_CENTER
	if extra != "":
		linha_rec.add_child(Estilo.rotulo(extra, 30, Color(0.55, 0.85, 1.0) if d.get("recorde", false) else Estilo.TEXTO_FRACO, 700))
	if not xp.is_empty():
		var t := "+%d XP" % int(xp.ganho)
		if xp.get("subiu_nivel", false):
			t += "   —   NÍVEL %d!" % int(xp.nivel)
		linha_rec.add_child(Estilo.rotulo(t, 30, Estilo.OK, 700))
	col.add_child(linha_rec)
	var botoes := _linha([], 24)
	botoes.alignment = BoxContainer.ALIGNMENT_CENTER
	for b: Array in [["MENU", pedido_menu], ["CORRER DE NOVO", pedido_repetir]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.custom_minimum_size = Vector2(300, 64)
		bt.add_theme_font_size_override("font_size", 26)
		var principal: bool = b[0] != "MENU"
		bt.add_theme_stylebox_override("normal", Estilo.caixa_neon(Color(0.05, 0.2, 0.55, 0.95) if principal else Estilo.PAINEL_ESCURO, Estilo.AZUL_NEON, 0.8 if principal else 0.2, 10))
		bt.add_theme_stylebox_override("hover", Estilo.caixa_neon(Color(0.1, 0.3, 0.7, 0.98), Color(0.6, 0.8, 1.0), 1.2, 10))
		bt.pressed.connect((b[1] as Signal).emit)
		botoes.add_child(bt)
		if principal:
			bt.call_deferred("grab_focus")
	col.add_child(botoes)
	_resultado.modulate.a = 0.0
	create_tween().tween_property(_resultado, "modulate:a", 1.0, 0.5)
