class_name VelocimetroDrag
extends Control
## Velocímetro analógico no meio do painel (mesmo estilo do conta-giros): 0 a drag.kmh_mostrador
## km/h, números a cada 40, ponteiro laranja e a velocidade em dígitos embaixo.
## Desenhado numa SubViewport e mostrado no cockpit 3D.

var kmh := 0.0
var _maximo := 320.0
var _fonte: Font
var _fonte_num: Font

const INI := deg_to_rad(140.0)       # ângulo do zero (sentido horário na tela)
const ARCO := deg_to_rad(260.0)


func _ready() -> void:
	_maximo = float(Config.valor("drag.kmh_mostrador", 320))
	_fonte = Estilo.fonte(700)
	_fonte_num = Estilo.fonte_titulo(800)


func atualizar(p_kmh: float) -> void:
	kmh = p_kmh
	queue_redraw()


func _ang(v: float) -> float:
	return INI + ARCO * clampf(v / _maximo, 0.0, 1.0)


func _draw() -> void:
	var centro := size * 0.5
	var raio := size.x * 0.44
	var laranja := Color(1.0, 0.55, 0.15)
	var branco := Color(0.95, 0.95, 0.95)
	# Aro cromado e mostrador preto
	draw_circle(centro, raio * 1.13, Color(0.55, 0.57, 0.6))
	draw_circle(centro, raio * 1.07, Color(0.02, 0.02, 0.025))
	# Marcas e números
	var v := 0.0
	while v <= _maximo + 0.1:
		var a := _ang(v)
		var dir := Vector2(cos(a), sin(a))
		var grande := fmod(v, 40.0) < 0.1
		var meio := fmod(v, 20.0) < 0.1
		var comp := 0.15 if grande else (0.1 if meio else 0.05)
		draw_line(centro + dir * raio * (0.97 - comp), centro + dir * raio * 0.97, branco, 5.0 if grande else 2.5, true)
		if grande:
			var txt := str(int(v))
			var tam := int(raio * 0.15)
			var ts := _fonte.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
			draw_string(_fonte, centro + dir * raio * 0.66 - Vector2(ts.x * 0.5, -ts.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, laranja)
		v += 10.0
	var rotulo := "km/h"
	var ls := _fonte.get_string_size(rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, int(raio * 0.14))
	draw_string(_fonte, centro + Vector2(-ls.x * 0.5, -raio * 0.28), rotulo, HORIZONTAL_ALIGNMENT_LEFT, -1, int(raio * 0.14), laranja)
	# Velocidade em dígitos, numa janelinha embaixo do centro
	var txt := "%d" % roundi(kmh)
	var tam := int(raio * 0.26)
	var ts := _fonte_num.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
	draw_rect(Rect2(centro + Vector2(-raio * 0.3, raio * 0.3), Vector2(raio * 0.6, raio * 0.3)), Color(0.06, 0.06, 0.07))
	draw_string(_fonte_num, centro + Vector2(-ts.x * 0.5, raio * 0.3 + raio * 0.15 + ts.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, branco)
	# Ponteiro laranja com contrapeso
	var a := _ang(kmh)
	var dir := Vector2(cos(a), sin(a))
	draw_line(centro - dir * raio * 0.2, centro + dir * raio * 0.92, laranja, raio * 0.045, true)
	draw_circle(centro, raio * 0.09, Color(0.1, 0.1, 0.11))
	draw_circle(centro, raio * 0.04, Color(0.5, 0.5, 0.52))
