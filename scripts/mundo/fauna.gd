class_name Fauna
extends Node3D
## Bichos da selva (Serpent's Climb), todos gerados por código e só visuais (sem colisão):
## - bandos de araras-vermelhas e araras-azuis voando em volta das pirâmides, acima da mata;
## - tucanos em bandos pequenos, baixos, com voo ondulado (batem e planam);
## - urubus planando em círculos bem alto, quase sem bater as asas;
## - garças brancas indo e voltando devagar sobre o rio;
## - borboletas-azuis (morpho) nas clareiras dos cercados.
## As asas batem no shader (passaro.gdshader); aqui só a posição e o rumo de cada ave.

var _especies: Array = []   # {mm: MultiMesh, aves: [{bando, desloc, fase}], bandos: [...]}
var _t := 0.0
var _rio := PackedVector2Array()
var _rio_s := PackedFloat32Array()


func montar(selva: Selva, terreno: Terreno, cfg: Dictionary) -> void:
	_rio = selva._rio
	_rio_s.resize(_rio.size())
	for i in range(1, _rio.size()):
		_rio_s[i] = _rio_s[i - 1] + _rio[i].distance_to(_rio[i - 1])
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var centros: Array[Vector2] = []
	for p: Dictionary in selva._piramides:
		centros.append(p.c)
	var sorteia_centro := func() -> Vector2:
		if not centros.is_empty() and rng.randf() < 0.6:
			return centros[rng.randi() % centros.size()] + Vector2(rng.randf_range(-200, 200), rng.randf_range(-200, 200))
		return Vector2(rng.randf_range(float(vale[0]), float(vale[2])), rng.randf_range(float(vale[1]), float(vale[3])))
	# [nome, malha (bico, cauda, envergadura), cores (corpo, peito, asa, ponta, bico), escala, bandos, aves por bando, altura, raio, freq, amp, voo]
	var tipos := [
		["arara", [0.12, 0.9, 1.0], [Color(0.82, 0.08, 0.05), Color(0.8, 0.1, 0.06), Color(1.0, 0.78, 0.08), Color(0.08, 0.28, 0.85), Color(0.92, 0.88, 0.8)], 1.0,
			int(cfg.get("araras", 6)), [4, 7], [45.0, 110.0], [90.0, 220.0], 9.0, 0.75, "circulo"],
		["arara_azul", [0.12, 0.9, 1.0], [Color(0.1, 0.35, 0.85), Color(1.0, 0.78, 0.1), Color(0.1, 0.4, 0.9), Color(0.05, 0.2, 0.6), Color(0.1, 0.1, 0.1)], 1.0,
			int(cfg.get("araras_azuis", 3)), [3, 5], [50.0, 120.0], [120.0, 240.0], 9.0, 0.75, "circulo"],
		["tucano", [0.32, 0.35, 0.7], [Color(0.04, 0.04, 0.05), Color(1.0, 0.92, 0.6), Color(0.04, 0.04, 0.05), Color(0.06, 0.06, 0.06), Color(1.0, 0.5, 0.05)], 0.8,
			int(cfg.get("tucanos", 5)), [2, 4], [22.0, 45.0], [60.0, 140.0], 13.0, 0.9, "ondulado"],
		["urubu", [0.08, 0.35, 1.6], [Color(0.06, 0.05, 0.05), Color(0.08, 0.07, 0.07), Color(0.1, 0.09, 0.09), Color(0.35, 0.33, 0.32), Color(0.75, 0.6, 0.55)], 1.6,
			int(cfg.get("urubus", 9)), [1, 2], [170.0, 330.0], [140.0, 300.0], 3.0, 0.12, "circulo"],
	]
	for tp: Array in tipos:
		var bandos := []
		var aves := []
		for b in tp[4]:
			var c: Vector2 = sorteia_centro.call()
			var bando := {"centro": Vector3(c.x, rng.randf_range(tp[6][0], tp[6][1]), c.y), "raio": rng.randf_range(tp[7][0], tp[7][1]),
				"vel": rng.randf_range(0.045, 0.075) * (1.0 if rng.randf() < 0.5 else -1.0) * (0.45 if tp[0] == "urubu" else 1.0),
				"fase": rng.randf() * TAU, "elipse": rng.randf_range(0.55, 1.0), "voo": tp[10]}
			bandos.append(bando)
			for k in rng.randi_range(tp[5][0], tp[5][1]):
				aves.append({"bando": bandos.size() - 1, "desloc": Vector3(rng.randf_range(-6, 6), rng.randf_range(-3, 3), rng.randf_range(-8, 8)) * (3.0 if tp[0] == "urubu" else 1.0),
					"fase": rng.randf() * TAU, "freq": tp[8] * rng.randf_range(0.85, 1.15), "amp": tp[9], "esc": float(tp[3]) * rng.randf_range(0.9, 1.1)})
		_especies.append(_criar_especie(tp[1], tp[2], bandos, aves))
	# Garças sobre o rio
	if _rio.size() > 1:
		var bandos := []
		var aves := []
		for k in int(cfg.get("garcas", 6)):
			bandos.append({"s": rng.randf() * _rio_s[_rio_s.size() - 1], "vel": rng.randf_range(5.0, 7.0) * (1.0 if rng.randf() < 0.5 else -1.0), "altura": rng.randf_range(9.0, 22.0), "voo": "rio", "lado": rng.randf_range(-15, 15)})
			aves.append({"bando": k, "desloc": Vector3.ZERO, "fase": rng.randf() * TAU, "freq": 5.5, "amp": 0.7, "esc": 1.5})
		_especies.append(_criar_especie([0.22, 0.3, 1.1], [Color(0.95, 0.95, 0.93), Color(0.95, 0.95, 0.93), Color(0.96, 0.96, 0.95), Color(0.9, 0.9, 0.88), Color(0.95, 0.75, 0.2)], bandos, aves))
	_borboletas(terreno, rng)
	set_process(true)


func _criar_especie(forma: Array, cores: Array, bandos: Array, aves: Array) -> Dictionary:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _malha_passaro(forma[0], forma[1], forma[2])
	mm.instance_count = aves.size()
	for i in aves.size():
		var a: Dictionary = aves[i]
		mm.set_instance_custom_data(i, Color(a.fase, a.freq, a.amp, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/passaro.gdshader")
	for k in 5:
		mat.set_shader_parameter(["cor_corpo", "cor_peito", "cor_asa", "cor_ponta", "cor_bico"][k], cores[k])
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 800, 10000))
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # posições atualizadas a cada quadro em _process
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return {"mm": mm, "bandos": bandos, "aves": aves}


## Ave de ~1 m de envergadura (frente = -Z): corpo em losango, cabeça, bico de `bico` m, cauda de
## `cauda` m e asas em dois segmentos (ombro e cotovelo, marcados em COLOR.g para baterem).
static func _malha_passaro(bico: float, cauda: float, envergadura: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector3, b: Vector3, c: Vector3, regiao: float, asa: float) -> void:
		var n := (b - a).cross(c - a).normalized()
		for v: Vector3 in [a, b, c]:
			st.set_color(Color(regiao, asa, 0.0))
			st.set_normal(n)
			st.add_vertex(v)
	# Corpo: losango do peito à cauda
	var frente := Vector3(0, 0.02, -0.32)
	var tras := Vector3(0, 0.0, 0.32)
	var cima := Vector3(0, 0.08, 0.0)
	var baixo := Vector3(0, -0.08, 0.0)
	var esq := Vector3(-0.09, 0.0, 0.0)
	var dir := Vector3(0.09, 0.0, 0.0)
	for par: Array in [[cima, esq, 0.0], [esq, baixo, 0.25], [baixo, dir, 0.25], [dir, cima, 0.0]]:
		tri.call(frente, par[0], par[1], par[2], 0.0)
		tri.call(tras, par[1], par[0], par[2], 0.0)
	# Cabeça e bico
	var cab := Vector3(0, 0.07, -0.38)
	for k in 4:
		var a := TAU * k / 4.0
		var b := TAU * (k + 1) / 4.0
		tri.call(cab + Vector3(0, 0, -0.1), cab + Vector3(cos(a), sin(a), 0) * 0.07, cab + Vector3(cos(b), sin(b), 0) * 0.07, 0.0, 0.0)
		tri.call(frente, cab + Vector3(cos(b), sin(b), 0) * 0.07, cab + Vector3(cos(a), sin(a), 0) * 0.07, 0.0, 0.0)
		tri.call(cab + Vector3(0, -0.01, -0.08 - bico), cab + Vector3(cos(a), sin(a) * 0.8 - 0.01, -0.08) * Vector3(0.045, 0.045, 1), cab + Vector3(cos(b), sin(b) * 0.8 - 0.01, -0.08) * Vector3(0.045, 0.045, 1), 1.0, 0.0)
	# Cauda em leque
	tri.call(Vector3(-0.03, 0, 0.28), Vector3(0.03, 0, 0.28), Vector3(0.0, -0.01, 0.3 + cauda), 0.75, 0.0)
	tri.call(Vector3(-0.03, 0, 0.28), Vector3(-0.07, -0.01, 0.22 + cauda * 0.85), Vector3(0.0, -0.01, 0.3 + cauda), 0.75, 0.0)
	tri.call(Vector3(0.03, 0, 0.28), Vector3(0.07, -0.01, 0.22 + cauda * 0.85), Vector3(0.0, -0.01, 0.3 + cauda), 0.75, 0.0)
	# Asas: ombro (0,1) → cotovelo (0,55) → ponta (até envergadura/2 + 0,4)
	var ponta := 0.55 + envergadura * 0.45
	for s: float in [-1.0, 1.0]:
		var o0 := Vector3(0.1 * s, 0.03, -0.12)
		var o1 := Vector3(0.1 * s, 0.03, 0.14)
		var c0 := Vector3(0.55 * s, 0.03, -0.1)
		var c1 := Vector3(0.55 * s, 0.03, 0.2)
		var p0 := Vector3(ponta * s, 0.03, 0.02)
		var p1 := Vector3(ponta * 0.92 * s, 0.03, 0.2)
		tri.call(o0, c0, c1, 0.5, 1.0)
		tri.call(o0, c1, o1, 0.5, 1.0)
		tri.call(c0, p0, p1, 0.75, 1.0)
		tri.call(c0, p1, c1, 0.75, 1.0)
	return st.commit()


## Borboletas-azuis nas clareiras dos cercados de largada (onde a câmera fica perto do chão).
func _borboletas(terreno: Terreno, rng: RandomNumberGenerator) -> void:
	var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.14)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/borboleta.gdshader")
	quad.material = mat
	for k in percursos:
		var o: Array = (percursos[k] as Dictionary).get("largada", {}).get("origem", [0, 0, 0])
		for lado: float in [-1.0, 1.0]:
			var p := GPUParticles3D.new()
			p.amount = 40
			p.lifetime = 8.0
			p.preprocess = 6.0
			p.visibility_aabb = AABB(Vector3(-60, -5, -60), Vector3(120, 30, 120))
			var proc := ParticleProcessMaterial.new()
			proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			proc.emission_box_extents = Vector3(20, 2, 30)
			proc.direction = Vector3(rng.randf_range(-1, 1), 0.2, rng.randf_range(-1, 1))
			proc.spread = 180.0
			proc.initial_velocity_min = 0.8
			proc.initial_velocity_max = 2.0
			proc.gravity = Vector3.ZERO
			proc.turbulence_enabled = true
			proc.turbulence_noise_strength = 2.0
			proc.turbulence_noise_scale = 3.0
			proc.turbulence_influence_min = 0.4
			proc.turbulence_influence_max = 0.8
			p.process_material = proc
			p.draw_pass_1 = quad
			var x := float(o[0]) + lado * 70.0
			var z := float(o[2]) - 35.0
			p.position = Vector3(x, terreno.altura_em(x, z) + 2.5, z)
			add_child(p)


func _process(delta: float) -> void:
	if OS.get_environment("TSC_FAUNA_PARADA") == "" or _t == 0.0:
		_t += delta   # TSC_FAUNA_PARADA: as aves param no ar (conferência de perto), as asas continuam
	if OS.get_environment("TSC_FAUNA_LOG") != "" and fmod(_t, 2.0) < delta:
		var mm0: MultiMesh = _especies[0].mm
		print("[FAUNA] especies=", _especies.size(), " aves0=", mm0.instance_count, " ave0=", mm0.get_instance_transform(0).origin, " cam=", get_viewport().get_camera_3d().global_position if get_viewport().get_camera_3d() else Vector3.ZERO, " visivel=", is_visible_in_tree())
	for esp: Dictionary in _especies:
		var mm: MultiMesh = esp.mm
		var bandos: Array = esp.bandos
		var aves: Array = esp.aves
		for i in aves.size():
			var a: Dictionary = aves[i]
			var b: Dictionary = bandos[a.bando]
			var pos: Vector3
			var rumo: Vector3
			if b.voo == "rio":
				var total := _rio_s[_rio_s.size() - 1]
				var s := fposmod(float(b.s) + float(b.vel) * _t, total * 2.0)
				var volta := s > total
				if volta:
					s = total * 2.0 - s
				var r := _no_rio(s)
				var dir: Vector2 = r[1] * (-1.0 if volta != (float(b.vel) < 0.0) else 1.0)
				var q: Vector2 = r[0] + Vector2(-dir.y, dir.x) * float(b.lado)
				pos = Vector3(q.x, 4.0 + float(b.altura) + sin(_t * 0.7 + a.fase) * 1.5, q.y)
				rumo = Vector3(dir.x, 0.0, dir.y)
			else:
				var ang := float(b.fase) + float(b.vel) * _t
				var r: float = b.raio
				var e: float = b.elipse
				var c: Vector3 = b.centro
				var onda := sin(_t * 1.3 + a.fase) * (3.0 if b.voo == "ondulado" else 1.0)
				pos = c + Vector3(cos(ang) * r, onda + sin(ang * 2.0) * 6.0, sin(ang) * r * e)
				rumo = Vector3(-sin(ang) * r, 0.0, cos(ang) * r * e) * signf(float(b.vel))
				# Cada ave com seu lugar no bando (o bando vira junto)
				var base_b := Basis.looking_at(rumo.normalized(), Vector3.UP)
				pos += base_b * (a.desloc as Vector3)
			var giro := -0.35 * signf(float(b.get("vel", 1.0))) if b.voo != "rio" else 0.0
			var bs := Basis.looking_at(rumo.normalized(), Vector3.UP) * Basis(Vector3.FORWARD, giro)
			mm.set_instance_transform(i, Transform3D(bs.scaled_local(Vector3.ONE * float(a.esc)), pos))


func _no_rio(s: float) -> Array:
	var i := 1
	while i < _rio.size() - 1 and _rio_s[i] < s:
		i += 1
	var a := _rio[i - 1]
	var b := _rio[i]
	var t := clampf((s - _rio_s[i - 1]) / maxf(_rio_s[i] - _rio_s[i - 1], 0.01), 0.0, 1.0)
	return [a.lerp(b, t), (b - a).normalized()]
