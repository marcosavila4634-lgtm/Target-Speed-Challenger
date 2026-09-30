class_name AjusteDrag
extends VBoxContainer
## Aba AJUSTE DRAG do TUNING (arte TSC_Garagem_Aba_Configuracao_Drag): relação de cada marcha,
## relação final, pressão dos pneus e força do nitro, com o DESEMPENHO PREVISTO (arrancada perfeita
## simulada na hora pela DragMotor) comparando o acerto de fábrica com o atual. Os upgrades
## instalados já entram na conta. Salvo por carro em Progresso (vale na próxima corrida).

var veiculo_id := ""
var _ajustes := {}
var _cfg: Dictionary
var _controles := {}          # chave -> [HSlider, Label]
var _previsao := {}           # chave -> Label
var _alterado: Label
var _atualizando := false

const PREVISOES := [
	["zero_cem", "0–100 km/h", "%.2f s", true],
	["oitavo", "1/8 DE MILHA", "%.3f s", true],
	["vel_final", "VELOCIDADE NA CHEGADA", "%.0f km/h", false],
	["vel_max", "VELOCIDADE MÁX. (6ª)", "%.0f km/h", false],
]


func _init() -> void:
	add_theme_constant_override("separation", 10)
	_cfg = Config.valor("drag.ajustes", {})
	var colunas := HBoxContainer.new()
	colunas.add_theme_constant_override("separation", 18)
	add_child(colunas)
	# Marchas e final
	var marchas := _bloco("RELAÇÃO DAS MARCHAS", "motor")
	colunas.add_child(marchas)
	var fabrica: Array = Config.valor("drag.marchas", [3.1, 2.15, 1.62, 1.28, 1.05, 0.86])
	var var_m := float(_cfg.get("marcha_variacao", 0.2))
	for i in fabrica.size():
		var f := float(fabrica[i])
		marchas.get_child(0).add_child(_slider("m%d" % i, "%dª" % (i + 1), f * (1.0 - var_m), f * (1.0 + var_m), 0.01, "%.2f"))
	var fin: Array = _cfg.get("final", [0.85, 1.2])
	marchas.get_child(0).add_child(_slider("final", "FINAL", float(fin[0]), float(fin[1]), 0.01, "%.2fx"))
	# Pneus e nitro
	var meio := VBoxContainer.new()
	meio.add_theme_constant_override("separation", 12)
	colunas.add_child(meio)
	var pneus := _bloco("PRESSÃO DOS PNEUS", "pneus")
	meio.add_child(pneus)
	var p: Dictionary = _cfg.get("pneus", {})
	var pd: Array = p.get("dianteiro", [26, 40])
	var pt: Array = p.get("traseiro", [14, 30])
	pneus.get_child(0).add_child(_slider("pneu_dianteiro", "DIANT.", float(pd[0]), float(pd[1]), 1.0, "%.0f psi"))
	pneus.get_child(0).add_child(_slider("pneu_traseiro", "TRAS.", float(pt[0]), float(pt[1]), 1.0, "%.0f psi"))
	var nitro := _bloco("NITRO", "nitro")
	meio.add_child(nitro)
	var nf: Array = _cfg.get("nitro", [0.7, 1.3])
	nitro.get_child(0).add_child(_slider("nitro", "FORÇA", float(nf[0]), float(nf[1]), 0.05, "%.0f%%", 100.0))
	nitro.get_child(0).add_child(Estilo.rotulo("Mais força = dura menos", 14, Estilo.TEXTO_FRACO))
	# Desempenho previsto
	var prev := _bloco("DESEMPENHO PREVISTO", "tuning")
	prev.custom_minimum_size.x = 380
	colunas.add_child(prev)
	for pr: Array in PREVISOES:
		var n := Estilo.rotulo(pr[1], 15, Estilo.TEXTO_FRACO, 600)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := Estilo.rotulo("", 17, Estilo.TEXTO, 700)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_previsao[pr[0]] = v
		var linha := HBoxContainer.new()
		linha.add_child(n)
		linha.add_child(v)
		prev.get_child(0).add_child(linha)
	prev.get_child(0).add_child(Estilo.rotulo("Arrancada perfeita simulada com o carro\ne os upgrades instalados (fábrica → atual).", 13, Estilo.TEXTO_FRACO))
	# Rodapé
	var rodape := HBoxContainer.new()
	rodape.add_theme_constant_override("separation", 14)
	add_child(rodape)
	var restaurar := Button.new()
	restaurar.text = "RESTAURAR FÁBRICA"
	restaurar.custom_minimum_size = Vector2(240, 34)
	restaurar.pressed.connect(func():
		_ajustes = {}
		Progresso.definir_ajustes_drag(veiculo_id, _ajustes)
		Audio.interface("confirmar", -4.0)
		_carregar())
	rodape.add_child(restaurar)
	_alterado = Estilo.rotulo("", 15, Estilo.OK, 600)
	_alterado.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_alterado.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rodape.add_child(_alterado)


func _bloco(titulo: String, icone: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Estilo.caixa_neon(Color(0.03, 0.08, 0.18, 0.9), Color(0.3, 0.45, 0.7, 0.45), 0.0, 6))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var cab := HBoxContainer.new()
	cab.add_theme_constant_override("separation", 10)
	cab.add_child(Estilo.icone(icone, 22, Estilo.AZUL_NEON))
	cab.add_child(Estilo.rotulo(titulo, 18, Color.WHITE, 700))
	v.add_child(cab)
	return p


func _slider(chave: String, rotulo: String, minimo: float, maximo: float, passo: float, fmt: String, escala := 1.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var n := Estilo.rotulo(rotulo, 15, Estilo.TEXTO, 600)
	n.custom_minimum_size.x = 58
	h.add_child(n)
	var s := HSlider.new()
	s.min_value = minimo
	s.max_value = maximo
	s.step = passo
	s.custom_minimum_size = Vector2(150, 24)
	s.focus_mode = Control.FOCUS_NONE
	var val := Estilo.rotulo("", 15, Color.WHITE, 700)
	val.custom_minimum_size.x = 70
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for sinal: float in [-1.0, 1.0]:
		var b := Button.new()
		b.text = "−" if sinal < 0.0 else "+"
		b.custom_minimum_size = Vector2(28, 24)
		b.focus_mode = Control.FOCUS_NONE
		for estado in ["normal", "hover", "pressed"]:
			var st := Estilo.caixa_neon(Color(0.04, 0.1, 0.24, 0.95) if estado == "normal" else Color(0.1, 0.28, 0.65, 1.0),
				Color(0.3, 0.5, 0.85, 0.7), 0.0, 4)
			st.content_margin_top = 0
			st.content_margin_bottom = 0
			st.content_margin_left = 4
			st.content_margin_right = 4
			b.add_theme_stylebox_override(estado, st)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func(): s.value += sinal * passo)
		if sinal < 0.0:
			h.add_child(b)
			h.add_child(s)
		else:
			h.add_child(val)
			h.add_child(b)
	s.value_changed.connect(func(x: float):
		val.text = fmt % (x * escala)
		_mudou(chave, x))
	_controles[chave] = [s, val, fmt, escala]
	return h


func mostrar(id: String) -> void:
	veiculo_id = id
	_ajustes = Progresso.ajustes_drag(id)
	_carregar()


## Põe os controles nos valores do acerto salvo (ou de fábrica).
func _carregar() -> void:
	_atualizando = true
	var fabrica: Array = Config.valor("drag.marchas", [3.1, 2.15, 1.62, 1.28, 1.05, 0.86])
	var marchas: Array = _ajustes.get("marchas", fabrica)
	var p: Dictionary = _cfg.get("pneus", {})
	var valores := {
		"final": float(_ajustes.get("final", 1.0)),
		"pneu_dianteiro": float(_ajustes.get("pneu_dianteiro", p.get("dianteiro_padrao", 32))),
		"pneu_traseiro": float(_ajustes.get("pneu_traseiro", p.get("traseiro_padrao", 22))),
		"nitro": float(_ajustes.get("nitro", 1.0)),
	}
	for i in fabrica.size():
		valores["m%d" % i] = float(marchas[i] if i < marchas.size() else fabrica[i])
	for k in valores:
		var c: Array = _controles[k]
		(c[0] as HSlider).value = valores[k]
		(c[1] as Label).text = str(c[2]) % (float(valores[k]) * float(c[3]))
	_atualizando = false
	_alterado.text = ""
	_prever()


func _mudou(chave: String, x: float) -> void:
	if _atualizando:
		return
	if chave.begins_with("m") and chave.length() == 2:
		var fabrica: Array = Config.valor("drag.marchas", [3.1, 2.15, 1.62, 1.28, 1.05, 0.86])
		var marchas: Array = _ajustes.get("marchas", fabrica.duplicate())
		marchas[int(chave.substr(1))] = x
		_ajustes["marchas"] = marchas
	else:
		_ajustes[chave] = x
	# Salva na hora (grátis e instantâneo): vale na próxima corrida
	Progresso.definir_ajustes_drag(veiculo_id, _ajustes)
	_alterado.text = "✓ Acerto salvo — vale na próxima corrida de Drag"
	_prever()


func _prever() -> void:
	var dados := Progresso.dados_jogador(veiculo_id)
	if dados.is_empty():
		return
	var base := DragMotor.prever(dados, {})
	var atual := DragMotor.prever(dados, _ajustes)
	for pr: Array in PREVISOES:
		var l: Label = _previsao[pr[0]]
		var a := float(base[pr[0]])
		var b := float(atual[pr[0]])
		var fmt: String = pr[2]
		if absf(a - b) < 0.0005:
			l.text = fmt % b
			l.add_theme_color_override("font_color", Estilo.TEXTO)
		else:
			var melhor: bool = (b < a) if pr[3] else (b > a)
			l.text = "%s  →  %s %s" % [fmt % a, fmt % b, "▲" if melhor else "▼"]
			l.add_theme_color_override("font_color", Estilo.OK if melhor else Estilo.PERIGO)
