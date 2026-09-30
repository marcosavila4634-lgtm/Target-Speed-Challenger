class_name Fogo
extends RefCounted
## Fogo contínuo por partículas (buracos da arena, braseiros da cerca): labaredas somadas
## (brilho aditivo) que sobem, crescem e somem do amarelo ao vermelho, e fagulhas soltas.

static var _mat_chama: StandardMaterial3D
static var _textura: GradientTexture2D


## `raio` = área de onde as chamas saem; `altura` = até onde sobem; `tamanho` = tamanho da labareda.
static func criar(pai: Node, pos: Vector3, raio: float, altura: float, quantidade: int, tamanho: float, fagulhas := true) -> GPUParticles3D:
	if OS.get_environment("TSC_SEM_FOGO") != "":
		return null
	var p := _emissor(raio, altura, quantidade, tamanho, 1.1, Color(1.0, 0.85, 0.45))
	p.position = pos
	pai.add_child(p)
	if fagulhas:
		var f := _emissor(raio * 0.8, altura * 2.0, maxi(quantidade / 3, 4), tamanho * 0.12, 2.2, Color(1.0, 0.6, 0.2))
		f.position = pos
		pai.add_child(f)
	return p


## Fumaça escura de escapamento (motor a diesel do vagão): nuvens que sobem, crescem e somem.
## As partículas ficam no mundo, então o rastro fica para trás quando o vagão anda.
static func fumaca(pai: Node, pos: Vector3) -> GPUParticles3D:
	if OS.get_environment("TSC_SEM_FOGO") != "":
		return null
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 4.0
	p.preprocess = 4.0
	p.position = pos
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-20, -2, -20), Vector3(40, 30, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.2
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0.6, 0.8, 0.3)   # sobe e deriva com o vento
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -20.0
	pm.angular_velocity_max = 20.0
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 0.25))
	curva.add_point(Vector2(1.0, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curva
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, Color(0.12, 0.11, 0.1, 0.85))
	g.set_color(1, Color(0.35, 0.33, 0.31, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2.6, 2.6)
	var m := _material().duplicate() as StandardMaterial3D
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	q.material = m
	p.draw_pass_1 = q
	pai.add_child(p)
	return p


static func _emissor(raio: float, altura: float, quantidade: int, tamanho: float, vida: float, cor: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = quantidade
	p.lifetime = vida
	p.preprocess = vida
	p.randomness = 0.5
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-raio - tamanho * 2.0, -1.0, -raio - tamanho * 2.0), Vector3((raio + tamanho * 2.0) * 2.0, altura + tamanho * 3.0, (raio + tamanho * 2.0) * 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = raio
	pm.direction = Vector3.UP
	pm.spread = 10.0
	var v := altura / vida
	pm.initial_velocity_min = v * 0.5
	pm.initial_velocity_max = v * 0.9
	pm.gravity = Vector3(0.0, v * 0.3, 0.0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 0.3))
	curva.add_point(Vector2(0.25, 1.0))
	curva.add_point(Vector2(1.0, 0.1))
	var ct := CurveTexture.new()
	ct.curve = curva
	pm.scale_curve = ct
	var g := Gradient.new()
	g.set_color(0, cor)
	g.set_color(1, Color(0.2, 0.03, 0.01, 0.0))
	g.add_point(0.35, Color(1.0, 0.45, 0.08, 0.9))
	g.add_point(0.7, Color(0.7, 0.12, 0.03, 0.5))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(tamanho, tamanho)
	q.material = _material()
	p.draw_pass_1 = q
	return p


static func _material() -> StandardMaterial3D:
	if _mat_chama:
		return _mat_chama
	_textura = GradientTexture2D.new()
	_textura.fill = GradientTexture2D.FILL_RADIAL
	_textura.fill_from = Vector2(0.5, 0.5)
	_textura.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.6))
	_textura.gradient = g
	_textura.width = 64
	_textura.height = 64
	_mat_chama = StandardMaterial3D.new()
	_mat_chama.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_chama.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_chama.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_chama.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat_chama.vertex_color_use_as_albedo = true
	_mat_chama.albedo_texture = _textura
	_mat_chama.albedo_color = Color(2.6, 1.7, 1.0)   # acima de 1: brilha (HDR) como fogo de verdade
	_mat_chama.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return _mat_chama
