extends Node3D
## Dinossauros gigantes caminhando em volta de uma cratera (Extinction Day, alvo da etapa 1; pedido do
## dono): cada um dá a volta num raio próprio, devagar, com os pés no terreno e a passada presa ao chão
## (DinosParque.andar). Enfeite: não têm colisão. O nó fica no centro da cratera, com y = 0.

var _terreno: Terreno
var _bichos: Array = []   # {d, raio, ang, vel (m/s, sinal = sentido), onda}


## lista: [[espécie, comprimento, raio da volta, velocidade (m/s; negativa = sentido contrário)], ...]
func montar(terreno: Terreno, lista: Array) -> void:
	_terreno = terreno
	for k in lista.size():
		var it: Array = lista[k]
		var d := DinosParque.criar(str(it[0]), float(it[1]))
		add_child(d.raiz)
		_bichos.append({"d": d, "raio": float(it[2]), "ang": TAU * k / lista.size() + 0.7 * k, "vel": float(it[3]), "onda": 1.3 * k})
	_mover(0.0)


var _dt := 0.0
var _quadro := 0
func _process(delta: float) -> void:
	# De longe a ronda anda a cada 3 quadros (além de 400 m da câmera) ou para de mexer as patas (além de
	# 1500 m, onde nem aparece): a pose dos ossos destes gigantes custava ~0,6 ms por quadro o tempo todo
	_dt += delta
	_quadro += 1
	var cam := get_viewport().get_camera_3d()
	var dist := cam.global_position.distance_to(global_position) if cam else 0.0
	if dist > 1500.0 or (dist > 400.0 and _quadro % 3 != 0):
		return
	_mover(_dt)
	_dt = 0.0


func _mover(delta: float) -> void:
	for b: Dictionary in _bichos:
		b.ang = float(b.ang) + float(b.vel) / float(b.raio) * delta
		var ang: float = b.ang
		# A volta não é um círculo perfeito: o raio respira devagar
		var r: float = float(b.raio) * (1.0 + 0.08 * sin(ang * 3.0 + float(b.onda)))
		var p := Vector3(cos(ang), 0.0, sin(ang)) * r
		var adiante := Vector3(cos(ang + 0.02 * signf(float(b.vel))), 0.0, sin(ang + 0.02 * signf(float(b.vel)))) * (float(b.raio) * (1.0 + 0.08 * sin((ang + 0.02 * signf(float(b.vel))) * 3.0 + float(b.onda))))
		var g := global_position
		# Chão: o mais baixo entre o meio, a frente e a traseira do bicho (não fica com as patas no ar no declive)
		var comp: float = b.d.comp
		var frente := (adiante - p).normalized()
		var chao := INF
		for u: float in [-0.3, 0.0, 0.3]:
			var q := p + frente * comp * u
			chao = minf(chao, _terreno.altura_em(g.x + q.x, g.z + q.z))
		var raiz: Node3D = b.d.raiz
		raiz.transform = Transform3D(Basis.looking_at(frente, Vector3.UP), Vector3(p.x, chao - g.y - 0.15, p.z))
		DinosParque.andar(b.d, raiz.global_transform, maxf(delta, 0.001), 1.0)
