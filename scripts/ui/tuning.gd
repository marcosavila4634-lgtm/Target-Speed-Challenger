class_name Tuning
extends PanelContainer
## Tuning (modo offline): nível e XP do carro, atributos e upgrades por sistema
## (config/upgrades.json). Ao passar o mouse em um nível mostra o "antes → depois" nos atributos.
## Instalar/remover é grátis; os níveis exigem o nível do carro (XP ganho nas partidas).

signal fechar

## [chave em dados, rótulo, formato, unidade]
const ATRIBUTOS := [
	["velocidade_max_kmh", "VELOCIDADE MÁX.", "%.0f", " km/h"],
	["aceleracao", "ACELERAÇÃO", "%.1f", " m/s²"],
	["aderencia", "ADERÊNCIA", "%.2f", ""],
	["paraquedas_sustentacao", "SUSTENTAÇÃO (PARAQUEDAS)", "%.0f", "%"],
	["paraquedas_controle", "CONTROLE (PARAQUEDAS)", "%.0f", "%"],
	["paraquedas_velocidade", "VELOCIDADE DE VOO", "%.0f", "%"],
	["nitro_duracao", "CARGA DO NITRO", "%.1f", " s"],
	["nitro_aceleracao", "FORÇA DO NITRO", "%.1f", " m/s²"],
	["ejetor_impulso", "IMPULSO DO EJETOR", "%.1f", " m/s"],
]
const PERCENTUAIS := ["paraquedas_sustentacao", "paraquedas_controle", "paraquedas_velocidade"]

var veiculo_id := ""
var _nivel: Label
var _xp_texto: Label
var _xp_barra: ProgressBar
var _valores := {}          # chave -> Label
var _linhas: VBoxContainer
var _aviso: Label


func _init() -> void:
	add_theme_stylebox_override("panel", Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.93), Estilo.AZUL_NEON, 0.6, 12))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 26)
	add_child(h)

	# Coluna do carro: nível, XP e atributos
	var esq := VBoxContainer.new()
	esq.custom_minimum_size.x = 470
	esq.add_theme_constant_override("separation", 4)
	h.add_child(esq)
	var topo := HBoxContainer.new()
	topo.add_theme_constant_override("separation", 14)
	esq.add_child(topo)
	_nivel = Estilo.rotulo("", 30, Color.WHITE, 700)
	topo.add_child(_nivel)
	var xp := VBoxContainer.new()
	xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp.add_theme_constant_override("separation", 2)
	topo.add_child(xp)
	_xp_texto = Estilo.rotulo("", 15, Estilo.TEXTO_FRACO, 600)
	xp.add_child(_xp_texto)
	_xp_barra = ProgressBar.new()
	_xp_barra.show_percentage = false
	_xp_barra.custom_minimum_size.y = 10
	var fundo := StyleBoxFlat.new()
	fundo.bg_color = Color(0.2, 0.25, 0.35, 0.7)
	var cheio := StyleBoxFlat.new()
	cheio.bg_color = Estilo.AZUL_NEON
	cheio.shadow_color = Color(Estilo.AZUL_NEON, 0.5)
	cheio.shadow_size = 4
	_xp_barra.add_theme_stylebox_override("background", fundo)
	_xp_barra.add_theme_stylebox_override("fill", cheio)
	xp.add_child(_xp_barra)
	esq.add_child(HSeparator.new())
	for a: Array in ATRIBUTOS:
		var n := Estilo.rotulo(a[1], 15, Estilo.TEXTO_FRACO, 600)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := Estilo.rotulo("", 16, Estilo.TEXTO, 600)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.custom_minimum_size.x = 200
		_valores[a[0]] = val
		var linha := HBoxContainer.new()
		linha.add_child(n)
		linha.add_child(val)
		esq.add_child(linha)

	h.add_child(VSeparator.new())

	# Coluna dos upgrades
	var dir := VBoxContainer.new()
	dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir.add_theme_constant_override("separation", 6)
	h.add_child(dir)
	var cab := HBoxContainer.new()
	var t := Label.new()
	t.text = "TUNING — UPGRADES"
	t.add_theme_font_override("font", Estilo.fonte_titulo(800))
	t.add_theme_font_size_override("font_size", 30)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cab.add_child(t)
	var voltar := Button.new()
	voltar.text = "VOLTAR"
	voltar.custom_minimum_size = Vector2(150, 36)
	voltar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	voltar.pressed.connect(func(): fechar.emit())
	cab.add_child(voltar)
	dir.add_child(cab)
	_linhas = VBoxContainer.new()
	_linhas.add_theme_constant_override("separation", 4)
	dir.add_child(_linhas)
	_aviso = Estilo.rotulo("", 15, Estilo.TEXTO_FRACO)
	dir.add_child(_aviso)


func mostrar(id: String) -> void:
	veiculo_id = id
	_atualizar()


func _atualizar() -> void:
	var nv := Progresso.nivel(veiculo_id)
	_nivel.text = "NÍVEL %d" % nv
	var faixa := Progresso.faixa_xp(veiculo_id)
	if faixa.y > 0:
		_xp_texto.text = "%d / %d XP PARA O NÍVEL %d" % [faixa.x, faixa.y, nv + 1]
		_xp_barra.value = 100.0 * faixa.x / faixa.y
	else:
		_xp_texto.text = "NÍVEL MÁXIMO  —  %d XP" % Progresso.xp(veiculo_id)
		_xp_barra.value = 100.0
	_aviso.text = "Ganhe XP jogando com este carro para liberar níveis. Instalar e remover é grátis; vale na próxima partida."
	_mostrar_atributos({})
	for f in _linhas.get_children():
		f.queue_free()
	for c in Progresso.categorias():
		_linhas.add_child(_linha_categoria(c))


## Atributos com os upgrades instalados; com `previa` (níveis alternativos) mostra "atual → novo".
func _mostrar_atributos(previa: Dictionary) -> void:
	var base := Config.veiculo(veiculo_id)
	var niveis := Progresso.niveis_upgrade(veiculo_id)
	var atual := Progresso.aplicar(base, niveis)
	var novo := {}
	if not previa.is_empty():
		var n2 := niveis.duplicate()
		n2.merge(previa, true)
		novo = Progresso.aplicar(base, n2)
	for a: Array in ATRIBUTOS:
		var l: Label = _valores[a[0]]
		var v := _fmt(a, float(atual.get(a[0], 0.0)))
		if novo.is_empty() or is_equal_approx(float(novo[a[0]]), float(atual[a[0]])):
			l.text = v
			l.add_theme_color_override("font_color", Estilo.TEXTO)
		else:
			var melhor: bool = float(novo[a[0]]) > float(atual[a[0]])
			l.text = "%s  →  %s" % [v, _fmt(a, float(novo[a[0]]))]
			l.add_theme_color_override("font_color", Estilo.OK if melhor else Estilo.PERIGO)


func _fmt(a: Array, x: float) -> String:
	if a[0] in PERCENTUAIS:
		x *= 100.0
	return (a[2] % x) + a[3]


func _linha_categoria(c: Dictionary) -> Control:
	var instalado := Progresso.nivel_upgrade(veiculo_id, c.id)
	var total: int = c.get("niveis", []).size()
	var caixa := PanelContainer.new()
	caixa.add_theme_stylebox_override("panel", Estilo.caixa_neon(Color(0.03, 0.08, 0.18, 0.9), Color(0.3, 0.45, 0.7, 0.45), 0.0, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	caixa.add_child(h)
	var ic := Estilo.icone(c.get("icone", ""), 26, Estilo.AZUL_NEON)
	ic.custom_minimum_size.x = 34
	h.add_child(ic)
	var textos := VBoxContainer.new()
	textos.add_theme_constant_override("separation", 0)
	textos.custom_minimum_size.x = 320
	textos.add_child(Estilo.rotulo(c.nome, 19, Color.WHITE, 700))
	textos.add_child(Estilo.rotulo(c.get("descricao", ""), 14, Estilo.TEXTO_FRACO))
	h.add_child(textos)

	# Um botão por nível: clicar instala até aquele nível; clicar no nível instalado remove ele.
	var niveis := HBoxContainer.new()
	niveis.add_theme_constant_override("separation", 6)
	niveis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(niveis)
	for n in range(1, total + 1):
		niveis.add_child(_botao_nivel(c, n, instalado))
	var estado := Estilo.rotulo("DE FÁBRICA" if instalado == 0 else "NÍVEL %d/%d" % [instalado, total], 15, Estilo.TEXTO_FRACO, 600)
	estado.custom_minimum_size.x = 110
	estado.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(estado)
	return caixa


func _botao_nivel(c: Dictionary, n: int, instalado: int) -> Button:
	var livre := Progresso.liberado(veiculo_id, c.id, n)
	var ativo := n <= instalado
	var b := Button.new()
	b.custom_minimum_size = Vector2(118, 38)
	b.focus_mode = Control.FOCUS_NONE
	var borda := Estilo.AZUL_NEON if ativo else Color(0.3, 0.45, 0.7, 0.6)
	var fundo := Color(0.07, 0.22, 0.55, 0.95) if ativo else Color(0.02, 0.05, 0.12, 0.9)
	b.add_theme_stylebox_override("normal", Estilo.caixa_neon(fundo, borda, 0.6 if ativo else 0.0, 6))
	b.add_theme_stylebox_override("hover", Estilo.caixa_neon(Color(0.1, 0.28, 0.65, 1.0), Color.WHITE, 0.8, 6))
	b.add_theme_stylebox_override("pressed", Estilo.caixa_neon(Color(0.1, 0.28, 0.65, 1.0), Color.WHITE, 0.8, 6))
	b.add_theme_stylebox_override("disabled", Estilo.caixa_neon(Color(0.02, 0.04, 0.08, 0.8), Color(0.3, 0.35, 0.45, 0.4), 0.0, 6))
	b.add_theme_font_size_override("font_size", 16)
	if livre:
		b.text = "NÍVEL %d%s" % [n, "  ✓" if ativo else ""]
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		# Clicar num nível já instalado (o mais alto) volta para o anterior
		var destino := n - 1 if n == instalado else n
		b.tooltip_text = "Remover este nível" if destino < instalado else "Instalar"
		b.mouse_entered.connect(func(): _mostrar_atributos({c.id: destino}))
		b.mouse_exited.connect(func(): _mostrar_atributos({}))
		b.pressed.connect(func():
			Progresso.definir_upgrade(veiculo_id, c.id, destino)
			Audio.interface("confirmar", -4.0)
			_atualizar())
	else:
		b.text = "CARRO NÍV. %d" % Progresso.requisito(c.id, n)
		b.tooltip_text = "Requer o carro no nível %d" % Progresso.requisito(c.id, n)
		b.disabled = true
		b.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.68))
		# Mesmo bloqueado, mostra o que o nível faria
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.mouse_entered.connect(func(): _mostrar_atributos({c.id: n}))
		b.mouse_exited.connect(func(): _mostrar_atributos({}))
	return b
