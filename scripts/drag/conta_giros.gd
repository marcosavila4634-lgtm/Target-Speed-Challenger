class_name ContaGiros
extends Control
## Conta-giros analógico preso na coluna do para-brisa (estilo carro de arrancada), igual em todos
## os carros: 0 a 10 mil rpm, faixa ideal de troca em verde com o centro perfeito marcado, zona
## vermelha, ponteiro laranja. A marcha e a velocidade ficam no display digital (PainelDigital).
## Desenhado numa SubViewport e mostrado no cockpit 3D.

var rpm := 900.0
var marcha := 0
var kmh := 0.0
var limitador := false
var _c: Dictionary = {}
var _fonte: Font
var _fonte_num: Font

const INI := deg_to_rad(140.0)       # ângulo do zero (sentido horário na tela)
const ARCO := deg_to_rad(260.0)


func _ready() -> void:
	_c = Config.valor("drag", {})
	_fonte = Estilo.fonte(700)
	_fonte_num = Estilo.fonte_titulo(800)


func atualizar(p_rpm: float, p_marcha: int, p_kmh: float, p_limitador: bool) -> void:
	rpm = p_rpm
	marcha = p_marcha
	kmh = p_kmh
	limitador = p_limitador
	queue_redraw()


func _ang(r: float) -> float:
	return INI + ARCO * clampf(r / float(_c.get("rpm_mostrador", 10000)), 0.0, 1.0)


## Fatia do mostrador entre duas rotações, de r0 a r1 de raio.
func _leque(c: Vector2, r0: float, r1: float, de: float, ate: float, cor: Color) -> void:
	var a0 := _ang(de)
	var a1 := _ang(ate)
	var pts := PackedVector2Array()
	var n := maxi(3, int(absf(a1 - a0) * 40.0))
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	for i in n + 1:
		var a := lerpf(a1, a0, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r0)
	draw_colored_polygon(pts, cor)


func _draw() -> void:
	var s := size
	var centro := s * 0.5
	var raio := s.x * 0.44
	var maximo := float(_c.get("rpm_mostrador", 10000))
	var faixa: Array = _c.get("faixa_ideal", [6900, 7600])
	var centro_p := float(_c.get("centro_perfeito", 7300))
	var vermelho := float(_c.get("rpm_vermelho", 7600))
	var laranja := Color(1.0, 0.55, 0.15)
	# Aro cromado e mostrador preto
	draw_circle(centro, raio * 1.13, Color(0.55, 0.57, 0.6))
	draw_circle(centro, raio * 1.07, Color(0.02, 0.02, 0.025))
	# Zona vermelha e faixa ideal
	draw_arc(centro, raio * 0.97, _ang(vermelho), _ang(maximo), 48, Color(0.95, 0.12, 0.1), raio * 0.07, true)
	# Faixa BOA: leque verde-azulado do miolo até a borda; PERFEITA: fatia fina e bem clara na ponta
	var tol := float(_c.get("tolerancia_perfeita", 60))
	_leque(centro, raio * 0.2, raio * 0.97, float(faixa[0]), float(faixa[1]), Color(0.0, 0.55, 0.55, 0.55))
	draw_arc(centro, raio * 0.97, _ang(float(faixa[0])), _ang(float(faixa[1])), 32, Color(0.1, 0.8, 0.75), raio * 0.06, true)
	_leque(centro, raio * 0.2, raio * 1.02, centro_p - tol, centro_p + tol, Color(0.45, 1.0, 0.3, 0.95))
	var ap := _ang(centro_p)
	draw_line(centro + Vector2(cos(ap), sin(ap)) * raio * 0.2, centro + Vector2(cos(ap), sin(ap)) * raio * 1.02, Color(0.85, 1.0, 0.7), 2.0, true)
	# Marcas e números (x1000)
	var r := 0.0
	while r <= maximo + 1.0:
		var a := _ang(r)
		var dir := Vector2(cos(a), sin(a))
		var grande := fmod(r, 1000.0) < 1.0
		var meio := fmod(r, 500.0) < 1.0
		var comp := 0.15 if grande else (0.1 if meio else 0.05)
		var cor := Color(1.0, 0.3, 0.25) if r >= vermelho else Color(0.95, 0.95, 0.95)
		draw_line(centro + dir * raio * (0.97 - comp), centro + dir * raio * 0.97, cor, 5.0 if grande else 2.5, true)
		if grande:
			var txt := str(int(r / 1000.0))
			var tam := int(raio * 0.2)
			var ts := _fonte.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam)
			draw_string(_fonte, centro + dir * raio * 0.68 - Vector2(ts.x * 0.5, -ts.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, laranja if r < vermelho else cor)
		r += 250.0
	for t: Array in [["RPM", 0.34, 0.17], ["x1000", 0.5, 0.08]]:
		var ls := _fonte.get_string_size(t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(raio * t[2]))
		draw_string(_fonte, centro + Vector2(-ls.x * 0.5, raio * t[1]), t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(raio * t[2]), laranja)
	# Ponteiro laranja com contrapeso
	var a := _ang(rpm)
	var dir := Vector2(cos(a), sin(a))
	draw_line(centro - dir * raio * 0.2, centro + dir * raio * 0.92, laranja, raio * 0.045, true)
	draw_circle(centro, raio * 0.09, Color(0.1, 0.1, 0.11))
	draw_circle(centro, raio * 0.04, Color(0.5, 0.5, 0.52))
