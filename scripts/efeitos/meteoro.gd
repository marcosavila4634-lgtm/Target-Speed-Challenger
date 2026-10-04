class_name Meteoro
extends Node3D
## Meteoro em chamas (Extinction Day): a rocha do modelo (assets/dino/meteoro, com os veios acesos),
## um envelope de fogo grudado na frente, rastro de fogo que vira fumaça atrás e a luz laranja que ele
## joga no chão. `tamanho` = raio da rocha em metros. Mover com mover_para() (o rastro se forma sozinho).

var tamanho := 8.0
var giro := Vector3(0.3, 0.7, 0.2)
## Rocha arremessada pela explosão (impacto, erupção): brasa escura com rastro de fumaça — com o clarão
## branco e o rastro de fogo do meteoro, dezenas delas juntas pareciam fogos de artifício.
var ejecta := false
var _fogo: GPUParticles3D
var _fumaca: GPUParticles3D
var _rocha: Node3D
var _ultima := Vector3.INF
static var _cena: PackedScene


func _ready() -> void:
	if _cena == null and ResourceLoader.exists("res://assets/dino/meteoro/meteoro.glb"):
		_cena = load("res://assets/dino/meteoro/meteoro.glb")
	_rocha = Node3D.new()
	add_child(_rocha)
	if _cena:
		var m: Node3D = _cena.instantiate()
		m.scale = Vector3.ONE * tamanho / 0.95
		_rocha.add_child(m)
		for gi in m.find_children("*", "GeometryInstance3D", true, false):
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var esf := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = tamanho
		sm.height = tamanho * 2.0
		esf.mesh = sm
		esf.material_override = ComplexoLancamento._material_luz(Color(1.0, 0.4, 0.1), 3.0)
		_rocha.add_child(esf)
	_rocha.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	# Envelope de fogo em volta da rocha (brilho aditivo)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(tamanho * 4.2, tamanho * 4.2) * (0.6 if ejecta else 1.0)
	halo.mesh = q
	var mh := StandardMaterial3D.new()
	mh.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mh.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mh.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mh.albedo_texture = Gelo._textura_floco()
	mh.albedo_color = Color(1.0, 0.5, 0.15, 0.9) if not ejecta else Color(1.0, 0.32, 0.06, 0.45)
	mh.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mh.no_depth_test = false
	halo.material_override = mh
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)
	_fogo = _rastro(true)
	_fumaca = _rastro(false)
	if tamanho >= 6.0:   # pedaços pequenos não precisam de luz própria (muitos juntos pesam)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.5, 0.18)
		luz.light_energy = 6.0
		luz.omni_range = tamanho * 26.0
		luz.omni_attenuation = 1.5
		add_child(luz)


## Rastro: fogo (aditivo, vida curta, encolhe) ou fumaça (cinza, vida longa, cresce).
func _rastro(fogo: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90 if fogo else 70
	p.lifetime = (0.9 if fogo else 6.0) * (0.5 if ejecta and fogo else 1.0)
	p.local_coords = false
	p.fixed_fps = 0
	p.visibility_aabb = AABB(Vector3.ONE * -2000.0, Vector3.ONE * 4000.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = tamanho * (0.7 if fogo else 0.9)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = tamanho * 0.2
	pm.initial_velocity_max = tamanho * 0.8
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = tamanho * (1.6 if fogo else 2.0)
	pm.scale_max = tamanho * (2.6 if fogo else 3.4)
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var curva := Curve.new()
	if fogo:
		curva.add_point(Vector2(0.0, 1.0))
		curva.add_point(Vector2(1.0, 0.25))
	else:
		curva.add_point(Vector2(0.0, 0.4))
		curva.add_point(Vector2(1.0, 2.4))
	var tc := CurveTexture.new()
	tc.curve = curva
	pm.scale_curve = tc
	var grad := Gradient.new()
	if fogo:
		grad.set_color(0, Color(1.0, 0.92, 0.6, 1.0) if not ejecta else Color(1.0, 0.5, 0.14, 0.8))
		grad.add_point(0.3, Color(1.0, 0.5, 0.1, 0.9) if not ejecta else Color(0.8, 0.22, 0.04, 0.6))
		grad.set_color(grad.get_point_count() - 1, Color(0.4, 0.06, 0.0, 0.0))
	else:
		grad.set_color(0, Color(0.35, 0.22, 0.16, 0.0))
		grad.add_point(0.08, Color(0.28, 0.24, 0.22, 0.75) if not ejecta else Color(0.13, 0.11, 0.1, 0.9))
		grad.set_color(grad.get_point_count() - 1, Color(0.45, 0.44, 0.43, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	if ejecta and not fogo:
		quad.material = ImpactoMeteoro.material_fumaca(false, 0.6)
		p.draw_pass_1 = quad
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		return p
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if fogo else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if fogo:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Selva._textura_nuvem()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.roughness = 1.0
	quad.material = m
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func mover_para(p: Vector3) -> void:
	global_position = p
	_ultima = p


func _process(delta: float) -> void:
	if _rocha:
		_rocha.rotate_object_local(giro.normalized(), delta * 0.8)
