class_name Explosao
extends Node3D
## Explosão: bola de fogo, faíscas, clarão e coluna de fumaça escura.
## Os pedaços do carro voando ficam em Destrocos (pedido do dono, substitui o "sem destroços" do dossiê).
##
## Materiais, gradientes e malhas são montados UMA vez e reaproveitados (_cache): montar tudo a cada
## explosão (textura de ruído gerada na hora, materiais de partícula novos) travava o jogo uns 60 ms
## a cada carro que caía — no Climb to Death, com quedas e ressurgimentos o tempo todo, a subida engasgava.

static var _cache := {}


func _ready() -> void:
	add_child(_particulas(90, 1.1, Vector2(5, 14), Vector3(0, 4, 0), 1.6, true))
	add_child(_particulas(90, 1.4, Vector2(14, 34), Vector3(0, -9.8, 0), 0.18, false))
	add_child(_fumaca())
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.6, 0.25)
	luz.light_energy = 8.0
	luz.omni_range = 40.0
	luz.shadow_enabled = false  # várias explosões com sombra pesam na GPU
	add_child(luz)
	var tw := create_tween()
	tw.tween_property(luz, "light_energy", 0.0, 1.3).set_ease(Tween.EASE_OUT)
	_sons.call_deferred()   # a posição é definida logo depois de entrar na cena
	get_tree().create_timer(7.0).timeout.connect(queue_free)


## Estrondo grave + estalos + corpo da explosão, com variação a cada carro.
func _sons() -> void:
	Audio.tocar("efeitos/explosao_grave_", global_position, 4.0, 0.9, 0.08, "Efeitos", 40.0)
	Audio.tocar("efeitos/explosao_estalo_", global_position, 0.0, 1.0, 0.1, "Efeitos", 30.0)
	Audio.tocar("efeitos/explosao_cc0.ogg", global_position, 2.0, 0.85, 0.1, "Efeitos", 35.0)


func _particulas(qtd: int, vida: float, vel: Vector2, grav: Vector3, tamanho: float, fogo: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = qtd
	p.lifetime = vida
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = true
	var chave := "fogo" if fogo else "faiscas"
	if not _cache.has(chave):
		_cache[chave] = [_material_particulas(vel, grav, fogo), _quad_particulas(tamanho, fogo)]
	p.process_material = _cache[chave][0]
	p.draw_pass_1 = _cache[chave][1]
	return p


static func _material_particulas(vel: Vector2, grav: Vector3, fogo: bool) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 1.4
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = vel.x
	m.initial_velocity_max = vel.y
	m.gravity = grav
	m.damping_min = 2.0 if fogo else 0.5
	m.damping_max = 4.0 if fogo else 1.0
	m.scale_min = 0.6
	m.scale_max = 1.4
	var grad := Gradient.new()
	if fogo:
		grad.set_color(0, Color(1.0, 0.55, 0.1, 1.0))
		grad.add_point(0.25, Color(0.85, 0.22, 0.02, 0.9))
		grad.add_point(0.6, Color(0.35, 0.07, 0.02, 0.6))
		grad.set_color(grad.get_point_count() - 1, Color(0.18, 0.1, 0.08, 0.0))
	else:
		grad.set_color(0, Color(1.0, 0.85, 0.4, 1.0))
		grad.set_color(grad.get_point_count() - 1, Color(1.0, 0.35, 0.05, 0.0))
	var rampa := GradientTexture1D.new()
	rampa.gradient = grad
	m.color_ramp = rampa
	if not fogo:
		m.particle_flag_align_y = true
	return m


static func _quad_particulas(tamanho: float, fogo: bool) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(tamanho, tamanho * (1.0 if fogo else 4.0))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if fogo else BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if fogo else BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	mat.albedo_texture = tex
	mat.emission_enabled = not fogo  # fogo usa só a cor (a luz do clarão dá o brilho)
	mat.emission = Color(1.0, 0.45, 0.12)
	mat.emission_energy_multiplier = 1.6 if fogo else 1.2
	quad.material = mat
	return quad


## Coluna de fumaça escura que sobe e se espalha depois do fogo.
func _fumaca() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 45
	p.lifetime = 5.0
	p.one_shot = true
	p.explosiveness = 0.75
	p.emitting = true
	p.local_coords = false
	if not _cache.has("fumaca"):
		var m := ParticleProcessMaterial.new()
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = 1.8
		m.direction = Vector3.UP
		m.spread = 35.0
		m.initial_velocity_min = 3.0
		m.initial_velocity_max = 9.0
		m.gravity = Vector3(0.6, 2.0, 0.2)
		m.damping_min = 1.5
		m.damping_max = 2.5
		m.scale_min = 1.0
		m.scale_max = 2.0
		m.angle_min = -180.0
		m.angle_max = 180.0
		var curva := Curve.new()
		curva.add_point(Vector2(0, 0.5))
		curva.add_point(Vector2(1, 3.0))
		var ct := CurveTexture.new()
		ct.curve = curva
		m.scale_curve = ct
		var grad := Gradient.new()
		grad.set_color(0, Color(0.9, 0.45, 0.15, 0.0))
		grad.add_point(0.08, Color(0.35, 0.22, 0.15, 0.85))
		grad.add_point(0.4, Color(0.2, 0.19, 0.19, 0.7))
		grad.set_color(grad.get_point_count() - 1, Color(0.4, 0.37, 0.35, 0.0))
		var rampa := GradientTexture1D.new()
		rampa.gradient = grad
		m.color_ramp = rampa
		_cache["fumaca"] = m
	p.process_material = _cache["fumaca"]
	p.draw_pass_1 = quad_fumaca(3.2)
	return p


## Quad de fumaça (borda suave, mistura normal — não aditiva) para partículas. Um por tamanho,
## reaproveitado (a textura de ruído é gerada uma vez só).
static func quad_fumaca(tamanho: float) -> QuadMesh:
	var chave := "fumaca_%.2f" % tamanho
	if _cache.has(chave):
		return _cache[chave]
	var quad := QuadMesh.new()
	quad.size = Vector2(tamanho, tamanho)
	if not _cache.has("mat_fumaca"):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 1.5
		var tex := NoiseTexture2D.new()
		tex.width = 64
		tex.height = 64
		var ruido := FastNoiseLite.new()
		ruido.frequency = 0.08
		tex.noise = ruido
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.add_point(0.55, Color(1, 1, 1, 0.55))
		grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
		g.gradient = grad
		mat.albedo_texture = g
		mat.detail_enabled = true
		mat.detail_mask = tex
		mat.detail_albedo = tex
		mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
		_cache["mat_fumaca"] = mat
	quad.material = _cache["mat_fumaca"]
	_cache[chave] = quad
	return quad
