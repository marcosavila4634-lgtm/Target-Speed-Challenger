class_name Ambiente
extends Node3D
## Luz de fim de tarde: céu com nuvens procedurais e sol baixo, névoa atmosférica quente
## e bruma no fundo do cânion.

var sol: DirectionalLight3D


func _ready() -> void:
	var ceu_mat := ShaderMaterial.new()
	ceu_mat.shader = load("res://shaders/ceu.gdshader")
	ceu_mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.012, 4, 77))
	ceu_mat.set_shader_parameter("cobertura", float(Config.valor("grafico.nuvens_cobertura", 0.5)))
	var ceu := Sky.new()
	ceu.sky_material = ceu_mat
	# As nuvens se movem: o reflexo/luz ambiente do céu é recalculado aos poucos
	ceu.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	ceu.radiance_size = Sky.RADIANCE_SIZE_128

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = ceu
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 1.8
	env.ssao_detail = 0.8
	# Luz rebatida: o paredão iluminado tinge de vermelho o que está à sua frente
	env.ssil_enabled = bool(Config.valor("grafico.luz_rebatida", false))
	env.ssil_radius = 8.0
	env.ssil_intensity = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.96, 0.7, 0.5)
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.45
	env.fog_density = 0.00012
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.15
	env.fog_height = 35.0
	env.fog_height_density = 0.006
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.08

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sol = DirectionalLight3D.new()
	sol.light_color = Color(1.0, 0.76, 0.52)
	sol.light_energy = 2.0
	sol.rotation_degrees = Vector3(-11.0, 205.0, 0.0)
	sol.shadow_enabled = true
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Sol baixo: paredões projetam sombras longas; a sombra alcança longe e as divisões favorecem o perto
	sol.directional_shadow_max_distance = float(Config.valor("grafico.sombra_distancia", 1500))
	sol.directional_shadow_split_1 = 0.04
	sol.directional_shadow_split_2 = 0.14
	sol.directional_shadow_split_3 = 0.4
	sol.directional_shadow_fade_start = 0.9
	sol.directional_shadow_pancake_size = 60.0
	# Penumbra realista: nítida junto ao objeto, borrada longe dele (tamanho aparente do sol)
	sol.light_angular_distance = float(Config.valor("grafico.sombra_suavidade_graus", 0.0))
	sol.shadow_normal_bias = 1.2
	sol.directional_shadow_blend_splits = true
	sol.shadow_bias = 0.05
	add_child(sol)
