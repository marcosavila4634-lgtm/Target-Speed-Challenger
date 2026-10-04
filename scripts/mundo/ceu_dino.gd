class_name CeuDino
extends Node3D
## Céu e luz de cada etapa do Extinction Day (etapas[].ceu):
## - noite (0..1), aurora (0..1), apocalipse (0..1), cinzas (0..1: cinza caindo em volta da câmera);
## - meteoro: {azimute, elevacao (graus), tamanho (raio angular em graus), cauda (graus de giro da cauda
##   no céu, 0 = subindo), comprimento (graus do fogo)}; na etapa com "aproxima" o meteoro cresce e
##   desce com o tempo da etapa (até tamanho_final/elevacao_final) e ilumina o vale cada vez mais;
## - bolas_de_fogo: quantas bolas de fogo riscam o céu ao mesmo tempo (etapa 4).
## A luz do sol vira lua à noite e, no apocalipse, a luz vem do próprio meteoro.

var _dino: Dino
var _terreno: Terreno
var _c: Dictionary = {}
var _met: Dictionary = {}
var progresso := 0.0              # fração do tempo da etapa (0 no começo, 1 no fim)
var _cinzas: Node3D
var _bolas: Array = []            # {no, ini, fim, t0, dur}
var _bolas_no: Node3D
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func montar(dino: Dino, terreno: Terreno, _cfg: Dictionary) -> void:
	_dino = dino
	_terreno = terreno
	_rng.seed = 911
	_bolas_no = Node3D.new()
	_bolas_no.name = "BolasDeFogo"
	add_child(_bolas_no)


## Direção no céu a partir de azimute (0 = norte, 90 = leste) e elevação, em graus.
static func direcao(azimute: float, elevacao: float) -> Vector3:
	var a := deg_to_rad(azimute)
	var e := deg_to_rad(elevacao)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e)).normalized()


func preparar_etapa(_indice: int, cfg_etapa: Dictionary) -> void:
	_c = cfg_etapa.get("ceu", {})
	_met = _c.get("meteoro", {})
	progresso = 0.0
	var amb := Ambiente.atual
	if amb == null or amb.ceu_mat == null:
		return
	var noite := float(_c.get("noite", 0.0))
	var apoc := float(_c.get("apocalipse", 0.0))
	var m := amb.ceu_mat
	m.set_shader_parameter("noite", noite)
	m.set_shader_parameter("aurora", float(_c.get("aurora", 0.0)))
	m.set_shader_parameter("apocalipse", apoc)
	m.set_shader_parameter("cobertura", float(_c.get("nuvens", 0.45)))
	var env := amb.env
	var sol := amb.sol
	# Dia: sol alto de manhã, ar úmido da selva
	var luz_cor := Color(1.0, 0.94, 0.84)
	var luz_energia := 2.1
	var luz_rot := Vector3(-38.0, 150.0, 0.0)
	var ambiente := 0.85
	var neblina := Color(0.8, 0.86, 0.8)
	var exposicao := 1.0
	var brilho := 0.6
	if noite > 0.5:
		# Lua: luz fria e fraca; o resto vem da lava, do neon e da aurora
		luz_cor = Color(0.55, 0.66, 1.0)
		luz_energia = 0.32
		luz_rot = Vector3(-34.0, 60.0, 0.0)
		ambiente = 0.32
		neblina = Color(0.06, 0.09, 0.15)
		exposicao = 1.35
		brilho = 0.95
	if apoc > 0.5:
		luz_cor = Color(1.0, 0.5, 0.22)
		luz_energia = 1.1
		ambiente = 0.55
		neblina = Color(0.45, 0.2, 0.1)
		exposicao = 1.1
		brilho = 0.9
	sol.light_color = luz_cor
	sol.light_energy = luz_energia
	sol.rotation_degrees = luz_rot
	env.ambient_light_energy = ambiente
	env.fog_light_color = neblina
	env.fog_density = float(_c.get("neblina", 0.00005 if noite < 0.5 else 0.00012))
	env.fog_height_density = 0.0015 if noite < 0.5 and apoc < 0.5 else 0.004
	env.tonemap_exposure = exposicao
	env.glow_intensity = brilho
	env.glow_hdr_threshold = 1.0 if noite > 0.5 or apoc > 0.5 else 1.1
	_aplicar_meteoro()
	if apoc > 0.5:
		# A luz vem do meteoro (direção dele no céu)
		var d := direcao(float(_met.get("azimute", 0.0)), maxf(float(_met.get("elevacao", 20.0)), 8.0))
		sol.basis = Basis.looking_at(-d, Vector3.UP)
	_montar_cinzas(float(_c.get("cinzas", 0.0)))
	for b: Dictionary in _bolas:
		(b.no as Node3D).queue_free()
	_bolas.clear()


## Meteoro no céu conforme o progresso da etapa (etapas com "aproxima" crescem e descem).
func _aplicar_meteoro() -> void:
	var amb := Ambiente.atual
	if amb == null or amb.ceu_mat == null:
		return
	var m := amb.ceu_mat
	if _met.is_empty():
		m.set_shader_parameter("met_brilho", 0.0)
		return
	var f := 0.0
	if bool(_met.get("aproxima", false)):
		f = pow(progresso, 1.6)
	var az := float(_met.get("azimute", 0.0))
	var el := lerpf(float(_met.get("elevacao", 12.0)), float(_met.get("elevacao_final", _met.get("elevacao", 12.0))), f)
	var tam := lerpf(float(_met.get("tamanho", 0.4)), float(_met.get("tamanho_final", _met.get("tamanho", 0.4))), f)
	var d := direcao(az, el)
	# Cauda: no plano do céu, girada `cauda` graus a partir da direção "para cima"
	var cima := (Vector3.UP - d * d.y).normalized()
	var lado := d.cross(cima).normalized()
	var giro := deg_to_rad(float(_met.get("cauda", 30.0)))
	var cauda := (cima * cos(giro) + lado * sin(giro)).normalized()
	m.set_shader_parameter("met_dir", d)
	m.set_shader_parameter("met_cauda", cauda)
	m.set_shader_parameter("met_raio", deg_to_rad(tam))
	m.set_shader_parameter("met_comp", deg_to_rad(float(_met.get("comprimento", tam * 9.0)) * (1.0 + f * 0.6)))
	m.set_shader_parameter("met_brilho", float(_met.get("brilho", 1.0)) * (1.0 + f * 1.5))
	if float(_c.get("apocalipse", 0.0)) > 0.5:
		amb.sol.light_energy = lerpf(1.1, 2.6, f)


## Chamado pela partida a cada quadro com a fração do tempo da etapa.
func atualizar(fracao: float) -> void:
	progresso = clampf(fracao, 0.0, 1.0)
	if bool(_met.get("aproxima", false)):
		_aplicar_meteoro()


## Cinza caindo em volta da câmera (flocos escuros que giram devagar; nada de risco).
func _montar_cinzas(quanto: float) -> void:
	if _cinzas:
		_cinzas.queue_free()
		_cinzas = null
	if quanto <= 0.0:
		return
	_cinzas = Node3D.new()
	_cinzas.name = "Cinzas"
	_cinzas.top_level = true
	add_child(_cinzas)
	var part := GPUParticles3D.new()
	part.amount = int(500 + 900 * quanto)
	part.lifetime = 6.0
	part.preprocess = 6.0
	part.local_coords = false
	part.visibility_aabb = AABB(Vector3(-200, -100, -200), Vector3(400, 200, 400))
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(45, 22, 45)
	proc.direction = Vector3(0.2, -1.0, 0.1)
	proc.spread = 18.0
	proc.initial_velocity_min = 1.2
	proc.initial_velocity_max = 2.6
	proc.gravity = Vector3(0.0, -0.4, 0.0)
	proc.turbulence_enabled = true
	proc.turbulence_noise_strength = 1.5
	proc.turbulence_noise_scale = 3.0
	proc.scale_min = 0.06
	proc.scale_max = 0.16
	proc.angle_min = 0.0
	proc.angle_max = 360.0
	proc.angular_velocity_min = -60.0
	proc.angular_velocity_max = 60.0
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 0.0))
	curva.add_point(Vector2(0.2, 1.0))
	curva.add_point(Vector2(0.8, 1.0))
	curva.add_point(Vector2(1.0, 0.0))
	var tc := CurveTexture.new()
	tc.curve = curva
	proc.alpha_curve = tc
	part.process_material = proc
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.2, 0.18, 0.17, 0.8)
	mat.albedo_texture = Gelo._textura_floco()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	quad.material = mat
	part.draw_pass_1 = quad
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cinzas.add_child(part)
	# Algumas brasas misturadas (acesas, sobem e caem com o vento)
	if float(_c.get("apocalipse", 0.0)) > 0.5:
		var br := part.duplicate() as GPUParticles3D
		br.amount = 160
		var pm := (proc.duplicate() as ParticleProcessMaterial)
		pm.scale_min = 0.08
		pm.scale_max = 0.18
		br.process_material = pm
		var q2 := quad.duplicate() as QuadMesh
		var m2 := mat.duplicate() as StandardMaterial3D
		m2.albedo_color = Color(1.0, 0.5, 0.12, 1.0)
		q2.material = m2
		br.draw_pass_1 = q2
		_cinzas.add_child(br)


## Bola de fogo riscando o céu bem longe (etapa 4): rocha incandescente com rastro de fumaça.
func _nova_bola() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var centro := cam.global_position
	var az := _rng.randf() * TAU
	var dist := _rng.randf_range(1500.0, 3500.0)
	var ini := centro + Vector3(cos(az), 0.0, sin(az)) * dist + Vector3.UP * _rng.randf_range(900.0, 1600.0)
	var desvio := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)).normalized() * _rng.randf_range(400.0, 900.0)
	var fim := Vector3(ini.x + desvio.x, _rng.randf_range(0.0, 80.0), ini.z + desvio.z)
	var no := Meteoro.new()
	no.tamanho = _rng.randf_range(6.0, 14.0)
	_bolas_no.add_child(no)
	no.global_position = ini
	_bolas.append({"no": no, "ini": ini, "fim": fim, "t0": _t, "dur": _rng.randf_range(3.5, 6.0)})


func _process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	if _cinzas and cam:
		_cinzas.global_position = cam.global_position
	var qtd := int(_c.get("bolas_de_fogo", 0))
	if qtd > 0 and _bolas.size() < qtd and _rng.randf() < delta * 0.8:
		_nova_bola()
	var k := 0
	while k < _bolas.size():
		var b: Dictionary = _bolas[k]
		var f := (_t - float(b.t0)) / float(b.dur)
		var no: Meteoro = b.no
		if f >= 1.0:
			no.queue_free()
			_bolas.remove_at(k)
			continue
		var p := (b.ini as Vector3).lerp(b.fim, f * f * 0.3 + f * 0.7)
		no.mover_para(p)
		k += 1
