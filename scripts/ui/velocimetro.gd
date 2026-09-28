class_name Velocimetro
extends Control
## Velocímetro de arco neon (cores do jogo): arco grosso que enche até a velocidade com ponta
## brilhante, resto do arco escuro, marcas e números por dentro, agulha branca com cubo e
## velocidade grande embaixo. Acima da velocidade máxima do carro o arco fica vermelho.

const ESCALA_MAX := 240.0
const INICIO := deg_to_rad(135.0)    # 0 km/h embaixo à esquerda
const VARREDURA := deg_to_rad(270.0)
const RAIO := 128.0
const ESPESSURA := 16.0

var velocidade := 0.0                # km/h que o ponteiro deve mostrar
var faixa_vermelha := 200.0          # km/h a partir do qual o arco fica vermelho
var _ponteiro := 0.0
var _fonte: Font


func _init() -> void:
	custom_minimum_size = Vector2(RAIO * 2.0 + 44.0, RAIO * 1.95 + 30.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fonte = Estilo.fonte(700)


func _process(delta: float) -> void:
	# Ponteiro com um pouco de inércia, como o de verdade
	var alvo := clampf(velocidade, 0.0, ESCALA_MAX)
	var novo := lerpf(_ponteiro, alvo, 1.0 - exp(-delta * 9.0))
	if absf(novo - _ponteiro) > 0.01:
		_ponteiro = novo
		queue_redraw()


func _angulo(kmh: float) -> float:
	return INICIO + VARREDURA * kmh / ESCALA_MAX


func _polar(c: Vector2, a: float, r: float) -> Vector2:
	return c + Vector2(cos(a), sin(a)) * r


func _texto_centro(pos: Vector2, txt: String, tam: int, cor: Color, fonte := _fonte) -> float:
	var w := fonte.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x
	draw_string(fonte, pos + Vector2(-w * 0.5, tam * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, cor)
	return w


func _draw() -> void:
	var c := Vector2(size.x * 0.5, RAIO + 22.0)
	var neon := Color(0.3, 0.66, 1.0)
	var perigo := Estilo.PERIGO
	var acima := _ponteiro >= faixa_vermelha
	var cor_arco := perigo if acima else neon

	# Fundo escuro translúcido para ler sobre qualquer paisagem
	for i in 8:
		draw_circle(c, RAIO + 20.0 - i * 3.0, Color(Estilo.PAINEL_ESCURO, 0.08 + i * 0.05))

	# Trilho do arco (parte ainda não alcançada)
	var fim := _angulo(ESCALA_MAX)
	draw_arc(c, RAIO, INICIO, fim, 96, Color(0.3, 0.34, 0.42, 0.55), ESPESSURA, true)
	# Trecho acima da velocidade máxima do carro, marcado discretamente no trilho
	if faixa_vermelha < ESCALA_MAX:
		draw_arc(c, RAIO + ESPESSURA * 0.5 + 3.0, _angulo(faixa_vermelha), fim, 32, Color(perigo, 0.8), 3.0, true)

	# Arco cheio até a velocidade, com brilho
	var a_p := _angulo(_ponteiro)
	if _ponteiro > 0.3:
		for g in 3:
			draw_arc(c, RAIO, INICIO, a_p, 96, Color(cor_arco, 0.12), ESPESSURA + 10.0 - g * 3.0, true)
		draw_arc(c, RAIO, INICIO, a_p, 96, cor_arco, ESPESSURA, true)
		draw_arc(c, RAIO + ESPESSURA * 0.25, INICIO, a_p, 96, Color(cor_arco.lightened(0.5), 0.6), 2.0, true)
	# Ponta brilhante
	var ponta_arco := _polar(c, a_p, RAIO)
	for g in 4:
		draw_circle(ponta_arco, ESPESSURA * (1.3 - g * 0.2), Color(cor_arco.lightened(0.3), 0.14 + g * 0.08))
	draw_circle(ponta_arco, ESPESSURA * 0.55, Color(0.92, 0.97, 1.0))

	# Marcas e números por dentro do arco
	var passos := int(ESCALA_MAX / 10.0)
	for k in passos + 1:
		var kmh := k * 10.0
		var a := _angulo(kmh)
		var longa := k % 2 == 0
		var r0 := RAIO - ESPESSURA * 0.5 - 6.0
		var comp := 12.0 if longa else 6.0
		draw_line(_polar(c, a, r0), _polar(c, a, r0 - comp), Color(1, 1, 1, 0.95 if longa else 0.6), 3.0 if longa else 2.0, true)
		if longa:
			var cor_n := perigo.lightened(0.2) if kmh >= faixa_vermelha else Color(0.55, 0.8, 1.0)
			_texto_centro(_polar(c, a, r0 - 30.0), str(int(kmh)), 17, cor_n)

	# Agulha branca afinada com sombra, saindo do cubo
	var dir := Vector2(cos(a_p), sin(a_p))
	var lado := Vector2(-dir.y, dir.x)
	var base := c + dir * 14.0
	var ponta := c + dir * (RAIO - ESPESSURA - 22.0)
	var agulha := PackedVector2Array([base + lado * 6.0, ponta + lado * 1.0, ponta - lado * 1.0, base - lado * 6.0])
	var sombra := PackedVector2Array()
	for p in agulha:
		sombra.append(p + Vector2(2, 3))
	draw_colored_polygon(sombra, Color(0, 0, 0, 0.35))
	draw_colored_polygon(agulha, Color(0.96, 0.97, 1.0))
	# Cubo: anel branco com miolo escuro
	draw_circle(c + Vector2(2, 3), 20.0, Color(0, 0, 0, 0.3))
	draw_circle(c, 20.0, Color(0.96, 0.97, 1.0))
	draw_circle(c, 12.0, Color(0.1, 0.12, 0.16))
	draw_arc(c, 12.0, 0.0, TAU, 32, Color(cor_arco, 0.8), 2.0, true)

	# Velocidade grande embaixo, entre as pontas do arco
	var num := str(int(round(velocidade)))
	var y_num := c.y + RAIO * 0.62
	var w := _texto_centro(Vector2(c.x - 10.0, y_num), num, 52, cor_arco.lightened(0.15))
	draw_string(_fonte, Vector2(c.x - 10.0 + w * 0.5 + 5.0, y_num + 18.0), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.78, 0.9))
