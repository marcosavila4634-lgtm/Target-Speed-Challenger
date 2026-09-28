class_name Hangar
extends Node3D
## Cenário 3D do menu (arte "Menu Principal" do dossiê): hangar industrial escuro com piso polido,
## plataforma giratória com anéis azuis, teto em treliça com fileiras de luz, portão aberto para o
## pôr do sol do cânion, banners TSC, faixa com o slogan e oficina (armários, pneus, caixas, troféu).

var suporte_carro: Node3D     # o carro fica aqui (gira junto com a plataforma)
var camera: Camera3D
var _aneis: Array[MeshInstance3D] = []
var _mat_aco: StandardMaterial3D


func _ready() -> void:
	_mat_aco = ComplexoLancamento._material_metal(Color(0.07, 0.075, 0.09), 0.8, 0.45)
	_ambiente()
	_piso()
	_plataforma()
	_paredes_e_portao()
	_teto()
	_decoracao()
	_detalhes_parede()
	_luzes()
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.position = Vector3(-1.0, 2.3, 10.5)
	add_child(camera)
	camera.look_at(Vector3(-1.0, 1.1, 0.0))


func _process(delta: float) -> void:
	if suporte_carro:
		suporte_carro.rotate_y(delta * 0.25)
	var t := Time.get_ticks_msec() / 1000.0
	for i in _aneis.size():
		_aneis[i].rotation.y = t * (0.25 if i % 2 == 0 else -0.15)


func _ambiente() -> void:
	var ceu_mat := ShaderMaterial.new()
	ceu_mat.shader = load("res://shaders/ceu.gdshader")
	ceu_mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.012, 4, 77))
	var ceu := Sky.new()
	ceu.sky_material = ceu_mat
	ceu.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	ceu.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = ceu
	# Dentro do hangar a luz vem das lâmpadas; o céu só aparece pelo portão
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.26, 0.4)
	env.ambient_light_energy = 0.18
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssao_enabled = true
	env.ssao_intensity = 2.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = false
	env.fog_light_color = Color(0.12, 0.16, 0.28)
	env.fog_density = 0.018
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# Sol do fim de tarde entrando pelo portão (ilumina o céu do shader e dá contraluz)
	var sol := DirectionalLight3D.new()
	sol.light_color = Color(1.0, 0.7, 0.45)
	sol.light_energy = 0.6
	sol.rotation_degrees = Vector3(-8.0, 20.0, 0.0)
	sol.shadow_enabled = false
	add_child(sol)


func _piso() -> void:
	var piso := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(80, 60)
	piso.mesh = plano
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/piso_hangar.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 5))
	piso.material_override = mat
	add_child(piso)


func _plataforma() -> void:
	var base := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = 4.0
	cil.bottom_radius = 4.15
	cil.height = 0.16
	cil.radial_segments = 96
	base.mesh = cil
	base.position.y = 0.08
	base.material_override = ComplexoLancamento._material_metal(Color(0.09, 0.1, 0.12), 0.85, 0.25)
	add_child(base)
	suporte_carro = Node3D.new()
	suporte_carro.position.y = 0.16
	add_child(suporte_carro)
	# Anel contínuo na borda e arcos quebrados girando por fora (como na arte)
	_anel(4.05, 0.05, 0.17, 1.0, 4.0)
	_anel(4.6, 0.06, 0.02, 0.62, 3.0)
	_anel(5.3, 0.04, 0.02, 0.35, 2.0)


func _anel(raio: float, espessura: float, y: float, fracao: float, energia: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 160
	var arco := TAU * fracao
	# Dois arcos opostos quando não é o anel completo
	var partes := 1 if fracao >= 1.0 else 2
	for p in partes:
		var a0 := p * PI
		var n := int(segs * fracao / partes)
		for i in n:
			var t0 := a0 + arco / partes * i / n
			var t1 := a0 + arco / partes * (i + 1) / n
			var q := [Vector3(cos(t0), 0, sin(t0)) * (raio - espessura), Vector3(cos(t0), 0, sin(t0)) * (raio + espessura),
				Vector3(cos(t1), 0, sin(t1)) * (raio + espessura), Vector3(cos(t1), 0, sin(t1)) * (raio - espessura)]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.add_vertex(q[k] + Vector3.UP * y)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = ComplexoLancamento._material_luz(Estilo.AZUL_NEON, energia)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if fracao < 1.0:
		_aneis.append(mi)


func _caixa(tamanho: Vector3, pos: Vector3, mat: Material, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = tamanho
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	return mi


func _paredes_e_portao() -> void:
	var parede := ComplexoLancamento._material_metal(Color(0.035, 0.04, 0.05), 0.6, 0.55)
	# Parede do fundo com portão aberto (largura 16 m, altura 9 m) atrás do carro, à direita
	var z := -16.0
	_caixa(Vector3(22, 20, 0.6), Vector3(-15, 10, z), parede)
	_caixa(Vector3(14, 20, 0.6), Vector3(18, 10, z), parede)
	_caixa(Vector3(16, 11, 0.6), Vector3(3, 14.5, z), parede)
	# Batentes do portão com faixa de luz
	for x: float in [-5.0, 11.0]:
		_caixa(Vector3(0.6, 9, 1.0), Vector3(x, 4.5, z + 0.2), _mat_aco)
		_caixa(Vector3(0.12, 8.6, 0.12), Vector3(x + (0.36 if x < 0 else -0.36), 4.5, z + 0.75), ComplexoLancamento._material_luz(Estilo.AZUL_NEON, 3.0))
	_caixa(Vector3(16.6, 0.6, 1.0), Vector3(3, 9.2, z + 0.2), _mat_aco)
	# Paredes laterais
	_caixa(Vector3(0.6, 20, 40), Vector3(-26, 10, 2), parede)
	_caixa(Vector3(0.6, 20, 40), Vector3(26, 10, 2), parede)
	# Cânion lá fora: vista panorâmica (captura do próprio jogo) além do portão
	var vista := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(72, 40.5)
	vista.mesh = q
	var mv := StandardMaterial3D.new()
	mv.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mv.albedo_texture = load("res://assets/ui/fundo_canion.jpg")
	mv.albedo_color = Color(0.82, 0.74, 0.74)
	vista.material_override = mv
	vista.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vista.position = Vector3(4, 1.5, -70)
	add_child(vista)


func _teto() -> void:
	var y := 14.0
	var trelicas: Array[Transform3D] = []
	for z: float in [-12.0, -4.0, 4.0]:
		trelicas.append_array(ComplexoLancamento.trelica(Vector3(-26, y, z), Vector3(26, y, z), 1.2, 2.0, 0.14, 0.06))
	ComplexoLancamento.criar_multimesh(self, trelicas, _mat_aco, false)
	# Fileiras de luminárias compridas
	var luminarias: Array[Transform3D] = []
	for z: float in [-10.0, -6.0, -2.0, 2.0]:
		for x in range(-20, 21, 5):
			luminarias.append(Transform3D(Basis.from_scale(Vector3(2.6, 0.08, 0.25)), Vector3(x, y - 1.2, z)))
	ComplexoLancamento.criar_multimesh(self, luminarias, ComplexoLancamento._material_luz(Color(0.85, 0.9, 1.0), 6.0), false)
	# Teto escuro
	_caixa(Vector3(54, 0.5, 40), Vector3(0, y + 1.5, 2), ComplexoLancamento._material_metal(Color(0.03, 0.03, 0.04), 0.3, 0.8))


func _banner(pos: Vector3, tamanho: Vector2, texto: String, rot_y := 0.0) -> void:
	var q := QuadMesh.new()
	q.size = tamanho
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/painel_equipe.gdshader")
	mat.set_shader_parameter("cor_equipe", Color(0.16, 0.36, 0.9))
	mat.set_shader_parameter("proporcao", tamanho.x / tamanho.y)
	mat.set_shader_parameter("faixa_ini", 0.7)
	mat.set_shader_parameter("faixa_fim", 0.93)
	mat.set_shader_parameter("chevrons", 3.0)
	mat.set_shader_parameter("energia", 1.6)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	add_child(mi)
	var l := Label3D.new()
	l.text = texto
	l.font_size = 200
	l.pixel_size = tamanho.x / 900.0
	l.outline_size = 0
	l.modulate = Color(0.9, 0.93, 1.0, 0.95)
	l.position = Vector3(0, tamanho.y * 0.22, 0.02)
	mi.add_child(l)


func _decoracao() -> void:
	_banner(Vector3(-12, 8.5, -15.6), Vector2(3.4, 9.0), "TSC")
	_banner(Vector3(20, 8.5, -15.6), Vector2(3.4, 9.0), "TSC")
	# Faixa do slogan
	var faixa := _caixa(Vector3(9.5, 3.6, 0.1), Vector3(17.5, 11.5, -15.5), ComplexoLancamento._material_metal(Color(0.05, 0.05, 0.07), 0.2, 0.7))
	var slogan := Label3D.new()
	slogan.text = "CONSTRUA SUA MÁQUINA.\nDOMINE QUALQUER DESAFIO."
	slogan.font_size = 120
	slogan.pixel_size = 0.012
	slogan.modulate = Color(0.85, 0.88, 0.95)
	slogan.outline_size = 0
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	slogan.position = Vector3(0, 0.3, 0.06)
	faixa.add_child(slogan)
	var risco := _caixa(Vector3(2.4, 0.18, 0.02), Vector3.ZERO, ComplexoLancamento._material_luz(Color(0.9, 0.12, 0.1), 2.5))
	remove_child(risco)
	faixa.add_child(risco)
	risco.position = Vector3(-3.2, -1.25, 0.06)
	# "BAY 01" pintado na parede lateral
	var bay := Label3D.new()
	bay.text = "BAY 01"
	bay.font_size = 256
	bay.pixel_size = 0.012
	bay.modulate = Color(0.5, 0.55, 0.65, 0.6)
	bay.outline_size = 0
	bay.position = Vector3(-25.6, 6.5, -4)
	bay.rotation.y = PI * 0.5
	add_child(bay)
	# Oficina: armários, pneus empilhados, caixas de transporte e troféu
	var vermelho := ComplexoLancamento._material_metal(Color(0.45, 0.05, 0.05), 0.5, 0.35)
	var preto := ComplexoLancamento._material_metal(Color(0.04, 0.04, 0.045), 0.2, 0.55)
	for i in 4:
		_caixa(Vector3(1.8, 1.4, 0.7), Vector3(-17 + i * 2.0, 0.7, -14.8), vermelho)
		_caixa(Vector3(1.7, 0.05, 0.02), Vector3(-17 + i * 2.0, 1.2, -14.44), ComplexoLancamento._material_metal(Color(0.7, 0.7, 0.72), 0.9, 0.2))
	for i in 3:
		var caixa := _caixa(Vector3(2.4, 1.2, 1.4), Vector3(14 + i * 2.7, 0.6, -10 + i * 0.3), preto, 0.1)
		var l := Label3D.new()
		l.text = "TSC"
		l.font_size = 120
		l.pixel_size = 0.006
		l.modulate = Color(0.75, 0.78, 0.85)
		l.outline_size = 0
		l.position = Vector3(0, 0.1, 0.72)
		caixa.add_child(l)
	var pneu := CylinderMesh.new()
	pneu.top_radius = 0.4
	pneu.bottom_radius = 0.4
	pneu.height = 0.28
	var borracha := ComplexoLancamento._material_metal(Color(0.03, 0.03, 0.03), 0.0, 0.85)
	for pilha: Vector2 in [Vector2(20, -6), Vector2(21, -5), Vector2(-20, -8)]:
		for k in 5:
			var mi := MeshInstance3D.new()
			mi.mesh = pneu
			mi.material_override = borracha
			mi.position = Vector3(pilha.x, 0.14 + k * 0.29, pilha.y)
			add_child(mi)
	var trofeu := MeshInstance3D.new()
	var taca := CylinderMesh.new()
	taca.top_radius = 0.28
	taca.bottom_radius = 0.08
	taca.height = 0.5
	trofeu.mesh = taca
	trofeu.material_override = ComplexoLancamento._material_metal(Color(0.95, 0.72, 0.3), 1.0, 0.2)
	trofeu.position = Vector3(15, 1.5, -10)
	add_child(trofeu)


func _luzes() -> void:
	# Luz principal sobre o carro, recortes azuis por trás e preenchimento suave
	var chave := SpotLight3D.new()
	chave.light_energy = 18.0
	chave.light_color = Color(1.0, 0.96, 0.9)
	chave.spot_range = 22.0
	chave.spot_angle = 34.0
	chave.shadow_enabled = true
	chave.position = Vector3(1.5, 10, 6)
	add_child(chave)
	chave.look_at(Vector3(0, 0.5, 0))
	for x: float in [-7.0, 7.0]:
		var recorte := SpotLight3D.new()
		recorte.light_energy = 14.0
		recorte.light_color = Color(0.35, 0.55, 1.0)
		recorte.spot_range = 20.0
		recorte.spot_angle = 30.0
		recorte.position = Vector3(x, 5, -7)
		add_child(recorte)
		recorte.look_at(Vector3(0, 0.8, 0))
	var preenche := OmniLight3D.new()
	preenche.light_energy = 1.5
	preenche.light_color = Color(0.5, 0.65, 1.0)
	preenche.omni_range = 14.0
	preenche.position = Vector3(-4, 3, 5)
	add_child(preenche)


## Nervuras metálicas nas paredes, arandelas e luminárias pendentes (dão escala e "cara" de hangar).
func _detalhes_parede() -> void:
	var nervuras: Array[Transform3D] = []
	for x in range(-25, 26, 3):
		if x > -6 and x < 12:
			continue   # vão do portão
		nervuras.append(Transform3D(Basis.from_scale(Vector3(0.35, 20, 0.5)), Vector3(x, 10, -15.5)))
	for z in range(-14, 20, 3):
		for lado: float in [-1.0, 1.0]:
			nervuras.append(Transform3D(Basis.from_scale(Vector3(0.5, 20, 0.35)), Vector3(lado * 25.5, 10, z)))
	# Passarela no alto da parede do fundo
	nervuras.append(Transform3D(Basis.from_scale(Vector3(50, 0.3, 1.6)), Vector3(0, 10.5, -14.6)))
	for x in range(-24, 25, 2):
		nervuras.append(Transform3D(Basis.from_scale(Vector3(0.06, 1.1, 0.06)), Vector3(x, 11.1, -13.9)))
	nervuras.append(Transform3D(Basis.from_scale(Vector3(50, 0.06, 0.06)), Vector3(0, 11.65, -13.9)))
	ComplexoLancamento.criar_multimesh(self, nervuras, _mat_aco, false)
	# Arandelas quentes ao longo das paredes
	var arandelas: Array[Transform3D] = []
	for x in range(-23, 24, 6):
		if x > -6 and x < 12:
			continue
		arandelas.append(Transform3D(Basis.from_scale(Vector3(0.9, 0.25, 0.3)), Vector3(x, 6.0, -15.1)))
	for z in range(-12, 16, 6):
		for lado: float in [-1.0, 1.0]:
			arandelas.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.25, 0.9)), Vector3(lado * 25.1, 6.0, z)))
	ComplexoLancamento.criar_multimesh(self, arandelas, ComplexoLancamento._material_luz(Color(1.0, 0.75, 0.45), 7.0), false)
	# Luminárias pendentes (cabo + cúpula acesa)
	var cabos: Array[Transform3D] = []
	var lampadas: Array[Transform3D] = []
	for p: Vector2 in [Vector2(-9, -6), Vector2(-3, -9), Vector2(4, -7), Vector2(10, -4), Vector2(-14, -2), Vector2(15, -11)]:
		var topo := Vector3(p.x, 14.0, p.y)
		var fim := Vector3(p.x, 8.5, p.y)
		cabos.append(ComplexoLancamento._viga(topo, fim, 0.03))
		lampadas.append(Transform3D(Basis.from_scale(Vector3(0.7, 0.2, 0.7)), fim))
	ComplexoLancamento.criar_multimesh(self, cabos, _mat_aco, false)
	ComplexoLancamento.criar_multimesh(self, lampadas, ComplexoLancamento._material_luz(Color(1.0, 0.95, 0.85), 10.0), false)
