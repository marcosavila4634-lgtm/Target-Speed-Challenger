class_name PerfilRampa
extends RefCounted
## Perfil lateral da pista de lançamento (capítulo 5 do dossiê):
## plataforma plana → curva de topo → descida reta → curva de base (descida lisa de 500 m) → rampa final ascendente de 70 m.
## Amostrado a cada metro de superfície. x = distância horizontal desde o início da plataforma; y = altura.

const PASSO := 1.0

var pontos := PackedVector2Array()
var angulos := PackedFloat32Array()   # inclinação da pista em radianos (negativo = descendo)
var indice_borda := 0                 # onde a descida começa
var indice_base := 0                  # onde a rampa final começa
var comprimento_horizontal := 0.0     # do início da plataforma até a saída
var altura_saida := 0.0
var angulo_saida := 0.0


func _init() -> void:
	var altura: float = Config.valor("mapa.plataforma_altura", 400)
	var comp_plataforma: float = Config.valor("mapa.plataforma_comprimento", 70)
	var descida: float = Config.valor("mapa.descida_comprimento", 500)
	var theta := deg_to_rad(Config.valor("mapa.descida_angulo", 45))
	var r_topo: float = Config.valor("mapa.raio_curva_topo", 60)
	var r_base: float = Config.valor("mapa.raio_curva_base", 150)
	var comp_rampa: float = Config.valor("mapa.rampa_comprimento", 70)
	var phi := deg_to_rad(Config.valor("mapa.rampa_angulo_saida", 40))

	var reta := maxf(descida - r_topo * theta - r_base * theta, 0.0)
	# Trechos: [comprimento de superfície, ângulo inicial, ângulo final]
	var trechos := [
		[comp_plataforma, 0.0, 0.0],
		[r_topo * theta, 0.0, -theta],
		[reta, -theta, -theta],
		[r_base * theta, -theta, 0.0],
		[comp_rampa, 0.0, phi],
	]
	var p := Vector2(0.0, altura)
	pontos.append(p)
	angulos.append(0.0)
	for i in trechos.size():
		if i == 1:
			indice_borda = pontos.size() - 1
		if i == 4:
			indice_base = pontos.size() - 1
		var comp: float = trechos[i][0]
		var n := maxi(int(ceil(comp / PASSO)), 1)
		var ds := comp / n
		for k in n:
			var a0: float = lerpf(trechos[i][1], trechos[i][2], float(k) / n)
			var a1: float = lerpf(trechos[i][1], trechos[i][2], float(k + 1) / n)
			var a := (a0 + a1) * 0.5
			p += Vector2(cos(a), sin(a)) * ds
			pontos.append(p)
			angulos.append(a1)
	comprimento_horizontal = p.x
	altura_saida = p.y
	angulo_saida = phi


## Altura da pista na distância horizontal x (desde o início da plataforma). Fora da pista devolve -INF.
func altura_em(x: float) -> float:
	if x < 0.0 or x > comprimento_horizontal:
		return -INF
	var lo := 0
	var hi := pontos.size() - 1
	while hi - lo > 1:
		var m := (lo + hi) / 2
		if pontos[m].x <= x:
			lo = m
		else:
			hi = m
	var t := inverse_lerp(pontos[lo].x, pontos[hi].x, x)
	return lerpf(pontos[lo].y, pontos[hi].y, t)
