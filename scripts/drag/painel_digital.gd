class_name PainelDigital
extends Control
## Display digital do painel do carro de arrancada (estilo "data logger"): barra de giro em
## segmentos com a faixa ideal marcada, marcha grande, velocidade e dados do motor (pressão de
## óleo, temperaturas, bateria, nitro). Desenhado numa SubViewport e mostrado no painel 3D.

var rpm := 900.0
var marcha := 0
var kmh := 0.0
var limitador := false
var nitro := "PRONTO"
var tempo := 0.0
var _c: Dictionary
var _fonte: Font
var _fonte_num: Font
var _agua := 82.0
var _trans := 70.0


func _ready() -> void:
	_c = Config.valor("drag", {})
	_fonte = Estilo.fonte(700)
	_fonte_num = Estilo.fonte_titulo(800)


func atualizar(m: DragMotor, delta: float) -> void:
	rpm = m.rpm
	marcha = m.marcha
	kmh = m.velocidade_kmh()
	limitador = m.no_limitador
	nitro = "ATIVO" if m.nitro_ativo else ("USADO" if m.nitro_usado else "PRONTO")
	# Temperaturas sobem devagar com o giro (só informação de clima)
	var giro := rpm / float(_c.get("rpm_limite", 8000))
	_agua = move_toward(_agua, 82.0 + giro * 14.0, delta * 1.5)
	_trans = move_toward(_trans, 70.0 + giro * 12.0, delta * 1.0)
	queue_redraw()


func _draw() -> void:
	var s := size
	var limite := float(_c.get("rpm_limite", 8000))
	var faixa: Array = _c.get("faixa_ideal", [6900, 7600])
	var centro := float(_c.get("centro_perfeito", 7300))
	# Moldura e fundo
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.012, 0.018))
	draw_rect(Rect2(Vector2(6, 6), s - Vector2(12, 12)), Color(0.02, 0.03, 0.05))
	# Barra de giro: 40 segmentos subindo em rampa, verde → faixa ideal → vermelho
	var n := 40
	var x0 := 20.0
	var larg := s.x - 40.0
	var topo := 16.0
	for i in n:
		var r := (i + 0.5) / n * limite
		var aceso := rpm >= r
		var cor := Color(0.2, 0.75, 1.0)
		if r >= float(faixa[0]) and r <= float(faixa[1]):
			cor = Color(0.25, 1.0, 0.4)
		elif r > float(faixa[1]):
			cor = Color(1.0, 0.2, 0.15)
		if limitador and fmod(Time.get_ticks_msec() / 60.0, 2.0) < 1.0:
			cor = Color(1.0, 1.0, 1.0)
		var h := lerpf(10.0, 34.0, float(i) / n)
		var rect := Rect2(x0 + i * larg / n + 1.0, topo + 34.0 - h, larg / n - 3.0, h)
		draw_rect(rect, cor if aceso else Color(cor, 0.12))
	# Marca do centro perfeito
	var xc := x0 + centro / limite * larg
	draw_line(Vector2(xc, topo - 4.0), Vector2(xc, topo + 38.0), Color.WHITE, 2.0)
	# Marcha
	var caixa := Rect2(20, 66, 150, s.y - 84)
	draw_rect(caixa, Color(0.9, 0.92, 0.95) if not limitador else Color(1.0, 0.3, 0.25))
	var m := "N" if marcha == 0 else str(marcha)
	var tam := int(caixa.size.y * 0.78)
	var ms := _fonte_num.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
	draw_string(_fonte_num, caixa.get_center() + Vector2(-ms.x * 0.5, tam * 0.36), m, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, Color(0.02, 0.03, 0.05))
	# Velocidade e rpm
	_texto("%d" % roundi(kmh), Vector2(s.x - 24, 100), 56, Color.WHITE, true)
	_texto("km/h", Vector2(s.x - 24, 124), 18, Color(0.6, 0.7, 0.85), true)
	_texto("%d rpm" % roundi(rpm), Vector2(190, 92), 26, Color(0.7, 0.85, 1.0))
	# Dados do motor (tabela)
	var giro := rpm / limite
	var dados := [
		["Óleo", "%.1f" % lerpf(1.2, 6.5, giro), Color(0.4, 1.0, 0.5)],
		["Água", "%d°" % roundi(_agua), Color(1.0, 0.85, 0.3)],
		["Câmbio", "%d°" % roundi(_trans), Color(1.0, 0.85, 0.3)],
		["Bateria", "%.1f" % lerpf(13.8, 13.2, giro), Color(0.4, 1.0, 0.5)],
		["Nitro", nitro, Color(0.4, 0.75, 1.0)],
	]
	for i in dados.size():
		var col := i % 3
		var lin := i / 3
		var p := Vector2(190 + col * 140, 130 + lin * 50)
		_texto(dados[i][0], p, 16, Color(0.55, 0.62, 0.75))
		_texto(dados[i][1], p + Vector2(0, 26), 24, dados[i][2])


func _texto(t: String, p: Vector2, tam: int, cor: Color, direita := false) -> void:
	var w := _fonte.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(_fonte, p - Vector2(w if direita else 0.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
