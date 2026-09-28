class_name Destrocos
extends Node3D
## Destroços de um veículo que explodiu: as peças reais do modelo (capô, portas, para-choques, vidros,
## luzes, rodas...) se soltam e voam girando; a carcaça chamuscada é jogada para cima e cai tombando;
## estilhaços de lataria na cor da equipe completam. Quicam no chão (o terreno não tem colisão física,
## então a batida é feita pela altura), afundam na água e somem depois de alguns segundos.

const DURACAO := 12.0
const MAX_PECAS := 12

var terreno: Terreno
var nivel_agua := 4.0
var _t := 0.0
var _mat_queimado: StandardMaterial3D


static func criar(v: Veiculo) -> Destrocos:
	var d := Destrocos.new()
	d.name = "Destrocos"
	d.terreno = v.terreno
	d.nivel_agua = float(v._cfg.nivel_agua)
	v.get_parent().add_child(d)
	d._montar(v)
	return d


func _montar(v: Veiculo) -> void:
	_mat_queimado = StandardMaterial3D.new()
	_mat_queimado.albedo_color = Color(0.03, 0.025, 0.02, 0.72)
	_mat_queimado.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_queimado.roughness = 1.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var vel_base := v.linear_velocity * 0.45
	var centro := v.global_transform * v.caixa_corpo.get_center()

	# Peças do modelo: a maior (carroceria) fica na carcaça; peças médias/pequenas se soltam.
	var malhas: Array = []
	for n in v.modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var tam := mi.get_aabb().size * mi.global_basis.get_scale()
		malhas.append([mi, tam.x * tam.y * tam.z, maxf(tam.x, maxf(tam.y, tam.z))])
	malhas.sort_custom(func(a, b): return a[1] > b[1])
	var soltas := 0
	var carcaca_malhas: Array[MeshInstance3D] = []
	for i in malhas.size():
		var mi: MeshInstance3D = malhas[i][0]
		var maior: float = malhas[i][2]
		# As 2 maiores (lataria e chassi) ficam na carcaça; o resto pode voar se for de tamanho razoável
		if i >= 2 and soltas < MAX_PECAS and maior > 0.12 and maior < 2.6 and rng.randf() < 0.8:
			soltas += 1
			var fora := (mi.global_transform * mi.get_aabb().get_center() - centro)
			fora.y = 0.0
			fora = fora.normalized() if fora.length() > 0.01 else Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
			var vel := vel_base + fora * rng.randf_range(7.0, 16.0) + Vector3.UP * rng.randf_range(7.0, 15.0)
			_peca([mi], mi.global_transform * mi.get_aabb(), vel, rng, rng.randf() < 0.3, soltas <= 3)
		else:
			carcaca_malhas.append(mi)

	# Rodas: cada uma sai rolando/voando para o seu lado
	for r in v.rodas:
		var partes: Array[MeshInstance3D] = []
		for n in r.pivo.find_children("*", "MeshInstance3D", true, false):
			partes.append(n)
		if partes.is_empty():
			continue
		var lado := (r.pivo.global_position - centro)
		lado.y = 0.0
		var vel := vel_base + lado.normalized() * rng.randf_range(6.0, 12.0) + Vector3.UP * rng.randf_range(5.0, 11.0)
		var caixa := AABB(r.pivo.global_position - Vector3.ONE * r.raio, Vector3.ONE * r.raio * 2.0)
		_peca(partes, caixa, vel, rng, false, false)

	# Carcaça: tudo o que sobrou, chamuscado, subindo pouco e tombando
	if not carcaca_malhas.is_empty():
		var caixa := v.global_transform * v.caixa_corpo
		var vel := vel_base + Vector3.UP * rng.randf_range(5.0, 8.0)
		var corpo := _peca(carcaca_malhas, caixa, vel, rng, true, true, true)
		corpo.mass = 900.0
		corpo.angular_velocity = Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(-1.5, 1.5), rng.randf_range(-2.5, 2.5))

	# Estilhaços de lataria (cor da equipe e metal escuro)
	var cores := [v.cor_equipe, v.cor_equipe.darkened(0.4), Color(0.12, 0.12, 0.13), Color(0.55, 0.55, 0.58)]
	for i in 16:
		var tam := Vector3(rng.randf_range(0.15, 0.7), rng.randf_range(0.03, 0.08), rng.randf_range(0.15, 0.6))
		var m := StandardMaterial3D.new()
		m.albedo_color = cores[rng.randi() % cores.size()]
		m.metallic = 0.6
		m.roughness = 0.5
		var bm := BoxMesh.new()
		bm.size = tam
		bm.material = m
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		var p := centro + dir * 0.8
		_corpo_rigido(mi, p, tam, vel_base + dir * rng.randf_range(10.0, 24.0), rng, false)


## Cria um corpo rígido com cópias das malhas, na posição atual delas no mundo.
func _peca(malhas: Array, caixa_mundo: AABB, vel: Vector3, rng: RandomNumberGenerator, queimar: bool, rastro: bool, carcaca := false) -> RigidBody3D:
	var corpo := RigidBody3D.new()
	var centro := caixa_mundo.get_center()
	corpo.position = centro
	for n in malhas:
		var mi: MeshInstance3D = n
		var copia := MeshInstance3D.new()
		copia.mesh = mi.mesh
		for s in mi.mesh.get_surface_count():
			copia.set_surface_override_material(s, mi.get_active_material(s))
		copia.transform = Transform3D(mi.global_basis, mi.global_position - centro)
		copia.layers = 1
		if queimar:
			copia.material_overlay = _mat_queimado
		corpo.add_child(copia)
	_configurar(corpo, caixa_mundo.size.clamp(Vector3.ONE * 0.1, Vector3.ONE * 6.0), vel, rng, carcaca)
	if rastro:
		corpo.add_child(_rastro(carcaca))
	return corpo


func _corpo_rigido(mi: MeshInstance3D, pos: Vector3, tam: Vector3, vel: Vector3, rng: RandomNumberGenerator, rastro: bool) -> void:
	var corpo := RigidBody3D.new()
	corpo.position = pos
	corpo.add_child(mi)
	_configurar(corpo, tam, vel, rng, false)
	if rastro:
		corpo.add_child(_rastro(false))


func _configurar(corpo: RigidBody3D, tam: Vector3, vel: Vector3, rng: RandomNumberGenerator, carcaca: bool) -> void:
	var forma := BoxShape3D.new()
	forma.size = tam * (0.8 if carcaca else 1.0)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	corpo.add_child(cs)
	# Só batem nas estruturas/alvo (camada 1); nada detecta os destroços.
	corpo.collision_layer = 0
	corpo.collision_mask = 1
	corpo.mass = maxf(tam.x * tam.y * tam.z * 250.0, 2.0)
	corpo.linear_velocity = vel
	corpo.angular_velocity = Vector3(rng.randf_range(-12, 12), rng.randf_range(-12, 12), rng.randf_range(-12, 12))
	corpo.linear_damp = 0.05
	corpo.continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.25
	pm.friction = 0.8
	corpo.physics_material_override = pm
	corpo.set_meta("meia_altura", tam.length() * 0.3)
	add_child(corpo)


## Rastro de fumaça escura (e fogo na carcaça) que sai da peça enquanto ela voa.
func _rastro(com_fogo: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60 if com_fogo else 30
	p.lifetime = 2.2
	p.local_coords = false
	p.emitting = true
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 0.5
	m.initial_velocity_max = 2.0
	m.gravity = Vector3(0, 1.5, 0)
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.scale_min = 0.8
	m.scale_max = 1.6
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.4))
	curva.add_point(Vector2(1, 2.2))
	var ct := CurveTexture.new()
	ct.curve = curva
	m.scale_curve = ct
	var grad := Gradient.new()
	if com_fogo:
		grad.set_color(0, Color(1.0, 0.6, 0.15, 0.9))
		grad.add_point(0.18, Color(0.25, 0.2, 0.18, 0.7))
	else:
		grad.set_color(0, Color(0.3, 0.27, 0.25, 0.7))
	grad.set_color(grad.get_point_count() - 1, Color(0.35, 0.33, 0.32, 0.0))
	var rampa := GradientTexture1D.new()
	rampa.gradient = grad
	m.color_ramp = rampa
	p.process_material = m
	p.draw_pass_1 = Explosao.quad_fumaca(1.4)
	return p


func _physics_process(delta: float) -> void:
	_t += delta
	for c in get_children():
		var corpo := c as RigidBody3D
		if corpo == null:
			continue
		var p := corpo.global_position
		var meia: float = corpo.get_meta("meia_altura", 0.3)
		# Água: afunda devagar e some
		if p.y < nivel_agua:
			corpo.linear_velocity *= 0.9
			corpo.angular_velocity *= 0.9
			corpo.gravity_scale = 0.15
			if p.y < nivel_agua - 3.0:
				corpo.queue_free()
			continue
		# Chão: quica e perde energia (o terreno não tem colisão física)
		if terreno:
			var chao := terreno.altura_em(p.x, p.z) + meia
			if p.y < chao:
				corpo.global_position = Vector3(p.x, chao, p.z)
				var v := corpo.linear_velocity
				if v.y < 0.0:
					v.y = -v.y * 0.3
				v.x *= 0.6
				v.z *= 0.6
				corpo.linear_velocity = v
				corpo.angular_velocity *= 0.7
				if v.length() < 0.6:
					corpo.freeze = true
	if _t > DURACAO:
		queue_free()
