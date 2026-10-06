class_name PocoNinho
extends Node3D
## Poço do alvo (Serpent's Climb E1, pedido do dono 2026-10-06; terreno: montanhas.etapas.N.poco = [x, z, raio,
## y do fundo]): buraco redondo de ~80 m de largura e ~200 m de fundo, revestido de rocha, com a boca em aba de
## pedra; no fundo uma pirâmide em degraus com o ninho de cobras no topo (o alvo fica nele) e ovos que quebram
## quando um carro bate neles; em volta da pirâmide, muitas cobras rastejando, uma passando por cima da outra.
## A parede e a pirâmide são parede comum; o fundo do poço mata como o chão.

const BASE_PIR := 34.0      # largura da base da pirâmide
const TOPO_PIR := 22.0      # largura do topo (o ninho/alvo cabe nele)
const NIVEIS := 5
const COBRAS := 9

var c := Vector2.ZERO
var raio := 40.0
var y_fundo := -194.0
var y_borda := 6.0
var alto_pir := 28.0
var _ovos: Array = []   # [MeshInstance3D, Area3D, quebrado]
var _env: Environment
var _nevoa_alt := 0.0
var _nevoa := 0.0
var _rng := RandomNumberGenerator.new()


func montar(terreno: Terreno, poco: Array, cfg: Dictionary) -> void:
	c = Vector2(float(poco[0]), float(poco[1]))
	raio = float(poco[2])
	y_fundo = float(poco[3])
	alto_pir = float(cfg.get("altura_piramide", 28.0))
	_rng.seed = 4242
	# Altura da boca: o chão de verdade em volta (fora da área rebaixada)
	var soma := 0.0
	for k in 12:
		var a := TAU * k / 12.0
		soma += terreno.altura_base(c.x + cos(a) * (raio + 30.0), c.y + sin(a) * (raio + 30.0))
	y_borda = soma / 12.0
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	add_child(corpo)
	var mat_rocha := _material_rocha()
	_parede(corpo, mat_rocha)
	_boca(corpo, mat_rocha)
	_fundo()
	_piramide(corpo)
	_ninho()
	if OS.get_environment("TSC_OVOS_QUEBRADOS") != "":   # conferência: o ninho já sujo
		for reg: Array in _ovos:
			reg[2] = true
			(reg[0] as MeshInstance3D).visible = false
			_sujeira((reg[0] as MeshInstance3D).position)
	_cobras()
	_luzes()
	var we := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if not we.is_empty():
		_env = (we[0] as WorldEnvironment).environment
		_nevoa_alt = _env.fog_height_density
		_nevoa = _env.fog_density


func _process(_delta: float) -> void:
	if _env == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := cam.global_position
	# 0 longe; 1 dentro do poço (abaixo da boca) — a névoa de altura e boa parte da névoa comum somem
	var d := Vector2(p.x - c.x, p.z - c.y).length()
	var perto := 1.0 - smoothstep(raio + 20.0, raio + 160.0, d)
	var dentro := perto * smoothstep(y_borda + 40.0, y_borda - 10.0, p.y)
	var olha := perto * clampf(-cam.global_basis.z.y * 1.6, 0.0, 1.0)   # de cima, olhando para dentro
	var k := maxf(dentro, olha)
	_env.fog_height_density = lerpf(_nevoa_alt, 0.0, k)
	_env.fog_density = lerpf(_nevoa, _nevoa * 0.25, k)


func _exit_tree() -> void:
	if _env:
		_env.fog_height_density = _nevoa_alt
		_env.fog_density = _nevoa


## Tochas na parede descendo em espiral e um brilho quente no fundo: lá embaixo a névoa e a sombra apagavam tudo.
func _luzes() -> void:
	var n := 10
	for k in n:
		var a := TAU * k / n * 1.7
		var y := lerpf(y_borda - 20.0, y_fundo + 12.0, float(k) / (n - 1))
		var p := Vector3(c.x + cos(a) * (_r_parede(a, y) - 1.5), y, c.y + sin(a) * (_r_parede(a, y) - 1.5))
		Fogo.criar(self, p, 0.8, 2.2, 16, 1.0, false)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.6, 0.3)
		luz.light_energy = 4.0
		luz.omni_range = 45.0
		luz.position = p + Vector3.UP * 1.5
		add_child(luz)
	var baixo := OmniLight3D.new()
	baixo.light_color = Color(1.0, 0.75, 0.45)
	baixo.light_energy = 6.0
	baixo.omni_range = raio * 2.2
	baixo.position = Vector3(c.x, topo() + 14.0, c.y)
	add_child(baixo)


## Topo da pirâmide do fundo (onde fica o alvo).
func topo() -> float:
	return y_fundo + alto_pir


func _material_rocha() -> ShaderMaterial:
	var mat := RochasSelva._material("montanha_armadilha").duplicate() as ShaderMaterial
	mat.set_shader_parameter("so_mosaico", true)
	mat.set_shader_parameter("mosaico_m", 22.0)
	mat.set_shader_parameter("alto_y", 1.0)
	var lad := Recinto.ler_imagem("res://assets/selva/rochas/rocha_ladrilho.png")
	if lad:
		lad.generate_mipmaps()
		mat.set_shader_parameter("ladrilho", ImageTexture.create_from_image(lad))
	return mat


## Raio da parede no ângulo a e altura y: rocha irregular (saliências e reentrâncias de alguns metros).
func _r_parede(a: float, y: float) -> float:
	var n := sin(a * 7.0 + y * 0.05) * 1.6 + sin(a * 13.0 - y * 0.11) * 0.9 + sin(a * 3.0 + y * 0.023) * 1.4
	return raio + n


func _parede(corpo: StaticBody3D, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na := 72
	var ys: Array[float] = []
	var y := y_fundo - 3.0
	while y < y_borda + 1.5:
		ys.append(y)
		y += 6.0
	ys.append(y_borda + 1.5)
	var faces := PackedVector3Array()
	for j in ys.size() - 1:
		for k in na:
			var a0 := TAU * k / na
			var a1 := TAU * (k + 1) / na
			var p := [Vector3(c.x + cos(a0) * _r_parede(a0, ys[j]), ys[j], c.y + sin(a0) * _r_parede(a0, ys[j])),
				Vector3(c.x + cos(a1) * _r_parede(a1, ys[j]), ys[j], c.y + sin(a1) * _r_parede(a1, ys[j])),
				Vector3(c.x + cos(a1) * _r_parede(a1, ys[j + 1]), ys[j + 1], c.y + sin(a1) * _r_parede(a1, ys[j + 1])),
				Vector3(c.x + cos(a0) * _r_parede(a0, ys[j + 1]), ys[j + 1], c.y + sin(a0) * _r_parede(a0, ys[j + 1]))]
			for idx in [0, 2, 1, 0, 3, 2]:   # faces para dentro do poço
				st.add_vertex(p[idx])
				faces.append(p[idx])
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Parede"
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	corpo.add_child(cs)


## Boca: aba de pedra da beirada da parede até 26 m para fora, no nível do chão (cobre a beirada serrilhada
## do terreno rebaixado).
func _boca(corpo: StaticBody3D, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_b := SurfaceTool.new()   # a face de baixo, em outra superfície (juntas, as normais se anulavam)
	st_b.begin(Mesh.PRIMITIVE_TRIANGLES)
	var na := 72
	var faces := PackedVector3Array()
	for k in na:
		var a0 := TAU * k / na
		var a1 := TAU * (k + 1) / na
		var i0 := Vector3(c.x + cos(a0) * _r_parede(a0, y_borda + 1.5), y_borda + 1.5, c.y + sin(a0) * _r_parede(a0, y_borda + 1.5))
		var i1 := Vector3(c.x + cos(a1) * _r_parede(a1, y_borda + 1.5), y_borda + 1.5, c.y + sin(a1) * _r_parede(a1, y_borda + 1.5))
		# vai até onde o chão rebaixado volta à altura normal (células de ~13 m) e termina um pouco enterrada
		var r0 := raio + 36.0 + sin(a0 * 5.0) * 3.0
		var r1 := raio + 36.0 + sin(a1 * 5.0) * 3.0
		var o0 := Vector3(c.x + cos(a0) * r0, y_borda - 2.5, c.y + sin(a0) * r0)
		var o1 := Vector3(c.x + cos(a1) * r1, y_borda - 2.5, c.y + sin(a1) * r1)
		for p: Vector3 in [i0, i1, o1, i0, o1, o0]:
			st.add_vertex(p)
		for p: Vector3 in [i0, o1, i1, i0, o0, o1]:
			st_b.add_vertex(p)
		faces.append_array([i0, i1, o1, i0, o1, o0])
	for stx: SurfaceTool in [st, st_b]:
		stx.index()
		stx.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Boca"
	var malha := st.commit()
	st_b.commit(malha)
	mi.mesh = malha
	mi.material_override = mat
	add_child(mi)
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	corpo.add_child(cs)


## Fundo: terra escura com ossos e pedras; mata como o chão (grupo terreno).
func _fundo() -> void:
	var chao := StaticBody3D.new()
	chao.collision_layer = 1
	chao.collision_mask = 0
	chao.add_to_group("terreno")
	add_child(chao)
	var cs := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = raio + 4.0
	forma.height = 4.0
	cs.shape = forma
	cs.position = Vector3(c.x, y_fundo - 2.0, c.y)
	chao.add_child(cs)
	var disco := CylinderMesh.new()
	disco.top_radius = raio + 4.0
	disco.bottom_radius = raio + 4.0
	disco.height = 0.5
	disco.radial_segments = 64
	var mi := MeshInstance3D.new()
	mi.mesh = disco
	var terra := StandardMaterial3D.new()
	terra.albedo_color = Color(0.16, 0.12, 0.08)
	terra.roughness = 1.0
	mi.material_override = terra
	mi.position = Vector3(c.x, y_fundo - 0.25, c.y)
	add_child(mi)


func _piramide(corpo: StaticBody3D) -> void:
	var pecas: Array[Transform3D] = []
	var faixas_j: Array[Transform3D] = []
	var faixas_o: Array[Transform3D] = []
	var h := alto_pir / NIVEIS
	for k in NIVEIS:
		var w := lerpf(BASE_PIR, TOPO_PIR, float(k) / (NIVEIS - 1))
		var y0 := y_fundo + k * h
		pecas.append(Transform3D(Basis.from_scale(Vector3(w, h, w)), Vector3(c.x, y0 + h * 0.5, c.y)))
		faixas_j.append(Transform3D(Basis.from_scale(Vector3(w + 0.3, h * 0.18, w + 0.3)), Vector3(c.x, y0 + h * 0.7, c.y)))
		faixas_o.append(Transform3D(Basis.from_scale(Vector3(w + 0.4, h * 0.07, w + 0.4)), Vector3(c.x, y0 + h * 0.95, c.y)))
	ComplexoLancamento.criar_multimesh(self, pecas, Selva.material_pedra(0, 1.1))
	ComplexoLancamento.criar_multimesh(self, faixas_j, Selva.material_jade())
	ComplexoLancamento.criar_multimesh(self, faixas_o, Selva.material_ouro())
	ComplexoLancamento.adicionar_colisoes(corpo, pecas)
	# Cabeças de serpente nos quatro cantos da base, olhando para fora
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		var cab := Selva.cabeca_serpente(4.5)
		var p := Vector3(c.x + cos(a) * BASE_PIR * 0.72, y_fundo + 0.2, c.y + sin(a) * BASE_PIR * 0.72)
		cab.transform = Transform3D(Basis(Vector3.UP, -a + PI * 0.5), p)
		add_child(cab)


## Ninho no topo da pirâmide: aro trançado de galhos e capim seco em volta do alvo e ovos de cobra em cima.
func _ninho() -> void:
	var y := topo()
	var galho := StandardMaterial3D.new()
	galho.albedo_color = Color(0.32, 0.22, 0.12)
	galho.roughness = 1.0
	var palha := StandardMaterial3D.new()
	palha.albedo_color = Color(0.55, 0.45, 0.25)
	palha.roughness = 1.0
	var ramos: Array[Transform3D] = []
	var ramos_p: Array[Transform3D] = []
	var r_ninho := TOPO_PIR * 0.5 - 0.2
	for k in 140:
		var a := _rng.randf() * TAU
		var r := r_ninho + _rng.randf_range(-1.6, 0.4)
		var p := Vector3(c.x + cos(a) * r, y + _rng.randf_range(0.2, 1.4), c.y + sin(a) * r)
		var tang := Vector3(-sin(a), _rng.randf_range(-0.3, 0.3), cos(a)).normalized()
		var b := Basis.looking_at(tang, Vector3.UP).rotated(tang, _rng.randf() * TAU)
		(ramos if k % 3 else ramos_p).append(Transform3D(b * Basis.from_scale(Vector3(0.35, 0.35, _rng.randf_range(3.0, 6.0))), p))
	ComplexoLancamento.criar_multimesh(self, ramos, galho)
	ComplexoLancamento.criar_multimesh(self, ramos_p, palha)
	# Ovos (brancos, de casca mole) espalhados no ninho: quebram quando um carro encosta
	var casca := StandardMaterial3D.new()
	casca.albedo_color = Color(0.93, 0.9, 0.82)
	casca.roughness = 0.6
	var esf := SphereMesh.new()
	esf.radius = 0.9
	esf.height = 2.4
	for k in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(2.0, r_ninho - 1.8)
		var p := Vector3(c.x + cos(a) * r, y + 1.0, c.y + sin(a) * r)
		var ovo := MeshInstance3D.new()
		ovo.mesh = esf
		ovo.material_override = casca
		ovo.transform = Transform3D(Basis.from_euler(Vector3(PI * 0.5 + _rng.randf_range(-0.4, 0.4), _rng.randf() * TAU, 0.0)), p)
		add_child(ovo)
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		var cs := CollisionShape3D.new()
		var sf := SphereShape3D.new()
		sf.radius = 1.6
		cs.shape = sf
		area.add_child(cs)
		area.position = p
		add_child(area)
		var reg := [ovo, area, false]
		_ovos.append(reg)
		area.body_entered.connect(_bateu_ovo.bind(reg))


func _bateu_ovo(corpo: Node, reg: Array) -> void:
	if reg[2] or not (corpo is Veiculo):
		return
	reg[2] = true
	var ovo: MeshInstance3D = reg[0]
	var p := ovo.global_position
	ovo.visible = false
	# Casca em pedaços e gema/clara espirrando
	_sujeira(p)
	for par: Array in [[Color(0.95, 0.93, 0.86), 18, 0.22, 7.0], [Color(1.0, 0.62, 0.08), 22, 0.14, 5.0], [Color(0.95, 0.95, 0.85), 18, 0.11, 4.0]]:
		var fx := GPUParticles3D.new()
		fx.amount = int(par[1])
		fx.lifetime = 1.1
		fx.one_shot = true
		fx.explosiveness = 0.95
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 80.0
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = float(par[3])
		pm.gravity = Vector3(0, -9.8, 0)
		pm.angle_max = 360.0
		fx.process_material = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = par[0]
		m.roughness = 0.3
		var caco: PrimitiveMesh = BoxMesh.new() if float(par[2]) > 0.2 else SphereMesh.new()
		if caco is BoxMesh:
			(caco as BoxMesh).size = Vector3(0.5, 0.05, 0.4)
		else:
			(caco as SphereMesh).radius = par[2]
			(caco as SphereMesh).height = par[2] * 2.0
		caco.material = m
		fx.draw_pass_1 = caco
		add_child(fx)
		fx.global_position = p
		fx.emitting = true
		get_tree().create_timer(2.0).timeout.connect(fx.queue_free)


## O ovo quebrado suja o ninho (pedido do dono): poça de clara e mancha de gema projetadas nos galhos (Decal,
## acompanha o relevo do ninho), a gema em volume no meio e as duas metades da casca caídas.
func _sujeira(p: Vector3) -> void:
	var chao := p - Vector3.UP * 0.9
	var giro := Basis(Vector3.UP, _rng.randf() * TAU)
	for camada: Array in [[Color(0.93, 0.92, 0.72, 0.42), 4.6, 0.35], [Color(1.0, 0.6, 0.05, 1.0), 1.9, 0.5]]:
		var d := Decal.new()
		d.texture_albedo = _mancha(camada[0], float(camada[2]))
		d.size = Vector3(float(camada[1]), 2.6, float(camada[1]) * _rng.randf_range(0.75, 1.0))
		d.transform = Transform3D(giro, chao + Vector3.UP * 0.6)
		d.cull_mask = 1
		add_child(d)
	# Gema inteira (meia esfera achatada) e as cascas
	var gema := MeshInstance3D.new()
	var esf := SphereMesh.new()
	esf.radius = 0.5
	esf.height = 0.5
	esf.is_hemisphere = true
	gema.mesh = esf
	var mg := StandardMaterial3D.new()
	mg.albedo_color = Color(1.0, 0.55, 0.04)
	mg.roughness = 0.15
	mg.metallic_specular = 0.8
	gema.material_override = mg
	gema.transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.55, 1.0)), chao + Vector3(_rng.randf_range(-0.3, 0.3), 0.15, _rng.randf_range(-0.3, 0.3)))
	add_child(gema)
	var casca := StandardMaterial3D.new()
	casca.albedo_color = Color(0.93, 0.9, 0.82)
	casca.roughness = 0.6
	casca.cull_mode = BaseMaterial3D.CULL_DISABLED
	var meia := SphereMesh.new()
	meia.radius = 0.9
	meia.height = 1.2
	meia.is_hemisphere = true
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = meia
		mi.material_override = casca
		var a := _rng.randf() * TAU
		var onde := chao + Vector3(cos(a), 0.0, sin(a)) * _rng.randf_range(1.3, 2.2) + Vector3.UP * 0.35
		mi.transform = Transform3D(Basis.from_euler(Vector3(_rng.randf_range(2.2, 3.0) if k == 0 else _rng.randf_range(0.3, 1.0), a, _rng.randf_range(-0.4, 0.4))), onde)
		add_child(mi)


## Textura de mancha líquida: miolo da cor, borda irregular que some (ruído no raio).
func _mancha(cor: Color, irregular: float) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var ruido := FastNoiseLite.new()
	ruido.seed = _rng.randi()
	ruido.frequency = 3.0
	for y in n:
		for x in n:
			var q := Vector2(x, y) / float(n - 1) * 2.0 - Vector2.ONE
			var borda := 0.78 + ruido.get_noise_1d(atan2(q.y, q.x) / TAU + 0.5) * irregular + ruido.get_noise_2d(x * 0.08, y * 0.08) * 0.08
			var alfa := 1.0 - smoothstep(borda - 0.08, borda, q.length())
			img.set_pixel(x, y, Color(cor.r, cor.g, cor.b, cor.a * alfa))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Cobras no fundo, em volta da pirâmide: voltas fechadas de raios e centros diferentes que se cruzam (uma
## passa por cima da outra), cada uma numa altura um pouco diferente.
func _cobras() -> void:
	var r_min := BASE_PIR * 0.5 * 1.42 + 2.5
	var r_max := raio - 3.0
	for k in COBRAS:
		var pts := PackedVector3Array()
		var r_base := lerpf(r_min, r_max, (k + 0.5) / COBRAS)
		var fase := _rng.randf() * TAU
		var ondas := 3 + k % 3
		var n := 220
		for j in n:
			var a := TAU * j / n
			var r := clampf(r_base + sin(a * ondas + fase) * (r_max - r_min) * 0.45, r_min, r_max)
			pts.append(Vector3(c.x + cos(a) * r, y_fundo + 0.25 + 0.55 * (k % 3), c.y + sin(a) * r))
		if k % 2 == 1:
			pts.reverse()   # metade anda no outro sentido: elas se cruzam
		var cobra := SerpenteGigante.new()
		add_child(cobra)
		cobra.montar_pontos(pts, {"comprimento": _rng.randf_range(34.0, 52.0), "grossura": _rng.randf_range(1.8, 2.8),
			"velocidade": _rng.randf_range(3.5, 6.5), "ossos": 36, "inicio": _rng.randf() * 200.0,
			"alcance_visivel": 900.0})
		cobra.name = "CobraPoco%d" % k
	# Cobra grande dando voltas na boca do poço, em cima da aba de pedra (pedido do dono: em todos os buracos do alvo)
	var borda := PackedVector3Array()
	var rb := raio + 15.0
	for j in 360:
		var a := TAU * j / 360.0
		var rr := rb + sin(a * 6.0) * 2.5   # serpenteia um pouco
		borda.append(Vector3(c.x + cos(a) * rr, y_borda + 1.6, c.y + sin(a) * rr))   # em cima da aba de pedra
	var grande := SerpenteGigante.new()
	add_child(grande)
	grande.montar_pontos(borda, {"comprimento": 120.0, "grossura": 5.0, "velocidade": 8.0, "ossos": 64, "alcance_visivel": 1800.0})
	grande.name = "CobraBorda"
