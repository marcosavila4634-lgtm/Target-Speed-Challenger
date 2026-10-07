class_name Ambiente
extends Node3D
## Luz de fim de tarde: céu com nuvens procedurais e sol baixo, névoa atmosférica quente
## e bruma no fundo do cânion.

var sol: DirectionalLight3D
## Extinction Day: o céu e a luz mudam por etapa (CeuDino troca dia, noite e apocalipse por aqui).
static var atual: Ambiente
var env: Environment
var ceu_mat: ShaderMaterial


## Opção gráfica: grafico.<chave> do jogo.json, ou a variável de ambiente `teste` (para medir sem editar o arquivo).
func _grafico(chave: String, teste: String, padrao: float) -> float:
	if OS.get_environment(teste) != "":
		return float(OS.get_environment(teste))
	return float(Config.grafico(chave, padrao))


func _ready() -> void:
	var ceu_mat := ShaderMaterial.new()
	ceu_mat.shader = load("res://shaders/ceu.gdshader")
	ceu_mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.012, 4, 77))
	ceu_mat.set_shader_parameter("cobertura", float(Config.valor("grafico.nuvens_cobertura", 0.5)) * (0.45 if Config.mapa_egito() else 1.0))
	if Config.mapa_egito():
		# Deserto: céu limpo, horizonte dourado e poucas nuvens altas
		ceu_mat.set_shader_parameter("cor_horizonte", Color(1.0, 0.7, 0.4))
		ceu_mat.set_shader_parameter("cor_horizonte_sol", Color(1.0, 0.56, 0.22))
		ceu_mat.set_shader_parameter("cor_chao", Color(0.72, 0.52, 0.32))
	if Config.mapa_selva():
		# Selva: fim de tarde úmido, horizonte dourado-esverdeado e nuvens altas de chuva
		ceu_mat.set_shader_parameter("cor_horizonte", Color(0.95, 0.78, 0.5))
		ceu_mat.set_shader_parameter("cor_horizonte_sol", Color(1.0, 0.62, 0.3))
		ceu_mat.set_shader_parameter("cor_chao", Color(0.2, 0.3, 0.14))
	if Config.mapa_gelo():
		# Frozen Peak: céu frio e limpo de altitude, horizonte rosado do fim de tarde na neve
		ceu_mat.set_shader_parameter("cor_zenite", Color(0.08, 0.2, 0.5))
		ceu_mat.set_shader_parameter("cor_meio", Color(0.45, 0.6, 0.85))
		ceu_mat.set_shader_parameter("cor_horizonte", Color(0.98, 0.82, 0.74))
		ceu_mat.set_shader_parameter("cor_horizonte_sol", Color(1.0, 0.68, 0.45))
		ceu_mat.set_shader_parameter("cor_chao", Color(0.8, 0.86, 0.95))
		ceu_mat.set_shader_parameter("cor_nuvem_luz", Color(1.0, 0.86, 0.76))
		ceu_mat.set_shader_parameter("cor_nuvem_sombra", Color(0.5, 0.56, 0.72))
	if Config.mapa_dino():
		ceu_mat = ShaderMaterial.new()
		ceu_mat.shader = load("res://shaders/ceu_dino.gdshader")
		ceu_mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.012, 4, 77))
	self.ceu_mat = ceu_mat
	atual = self
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
	env.ssao_enabled = bool(_grafico("ssao", "TSC_SSAO", 1))
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
	if Config.mapa_cidade():
		# Cidade: ar mais limpo (a névoa do cânion deixava os prédios todos bege) e sem bruma rasteira
		env.fog_density = 0.00005
		env.fog_height_density = 0.0
		env.fog_aerial_perspective = 0.35
		env.adjustment_saturation = 1.1
	if Config.mapa_egito():
		# Egito: ar seco e dourado, sem bruma rasteira; poeira fina no horizonte
		env.fog_light_color = Color(1.0, 0.78, 0.52)
		env.fog_density = 0.00009
		env.fog_height_density = 0.002
		env.fog_aerial_perspective = 0.45
		env.adjustment_saturation = 1.14
		env.adjustment_contrast = 1.1

	if Config.mapa_selva():
		# Selva: ar úmido e quente, névoa baixa sobre a mata, verdes saturados
		env.fog_light_color = Color(0.82, 0.85, 0.7)
		env.fog_density = 0.00016
		env.fog_height = 30.0
		env.fog_height_density = 0.01
		env.fog_aerial_perspective = 0.5
		env.fog_sun_scatter = 0.6
		env.adjustment_saturation = 1.2
		env.adjustment_contrast = 1.06
		env.ambient_light_energy = 0.85

	if Config.mapa_gelo():
		# Frozen Peak: ar frio e limpo, névoa branco-azulada no fundo do vale, neve sem estourar
		env.fog_light_color = Color(0.86, 0.91, 1.0)
		env.fog_density = 0.00006
		env.fog_height = 30.0
		env.fog_height_density = 0.002
		env.fog_aerial_perspective = 0.3
		env.fog_sun_scatter = 0.35
		env.adjustment_saturation = 1.12
		env.adjustment_contrast = 1.08
		env.ambient_light_energy = 0.9
		env.tonemap_exposure = 0.92
		env.glow_hdr_threshold = 1.25

	if Config.mapa_dino():
		# Extinction Day: selva úmida; a luz de cada etapa (dia, noite, apocalipse) é ajustada pelo CeuDino
		env.fog_light_color = Color(0.8, 0.86, 0.8)
		env.fog_density = 0.00011
		env.fog_height = 40.0
		env.fog_height_density = 0.006
		env.fog_aerial_perspective = 0.5
		env.adjustment_saturation = 1.15
		env.ambient_light_energy = 0.85
	self.env = env
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sol = DirectionalLight3D.new()
	sol.light_color = Color(1.0, 0.76, 0.52)
	sol.light_energy = 2.0
	sol.rotation_degrees = Vector3(-11.0, 205.0, 0.0)
	if Config.mapa_egito():
		sol.light_color = Color(1.0, 0.8, 0.56)
		sol.light_energy = 2.3
		sol.rotation_degrees = Vector3(-14.0, 230.0, 0.0)   # pôr do sol atrás das pirâmides, visto da rampa final
	if Config.mapa_selva():
		sol.light_color = Color(1.0, 0.84, 0.62)
		sol.light_energy = 2.2
		sol.rotation_degrees = Vector3(-22.0, 245.0, 0.0)   # sol de fim de tarde a oeste, raios atravessando a névoa
	if Config.mapa_gelo():
		sol.light_color = Color(1.0, 0.86, 0.72)
		sol.light_energy = 1.9
		sol.rotation_degrees = Vector3(-19.0, 215.0, 0.0)   # sol baixo de inverno: sombras azuis compridas na neve
	sol.shadow_enabled = true
	sol.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Sol baixo: paredões projetam sombras longas; a sombra alcança longe e as divisões favorecem o perto
	sol.directional_shadow_max_distance = _grafico("sombra_distancia", "TSC_SOMBRA_DIST", 1500)
	# Qualidade (grafico.* no jogo.json; os padrões são os de sempre): tamanho do mapa de sombras do sol e
	# escala da imagem 3D (1 = nativa; menos = desenha menor e amplia com FSR — alivia a placa de vídeo).
	# (A suavização de bordas — MSAA — fica no project.godot: trocá-la com o jogo aberto fechou o jogo na RX 5700 XT.)
	var vp := get_viewport()
	# Limiar dos níveis de detalhe (px): acima de 1 as malhas com LOD (rochas) trocam para a versão leve mais cedo
	vp.mesh_lod_threshold = _grafico("lod_limiar", "TSC_LOD", 1.0)
	RenderingServer.directional_shadow_atlas_set_size(int(_grafico("sombra_mapa", "TSC_SOMBRA_MAPA", 8192)), true)
	var escala := _grafico("escala_3d", "TSC_ESCALA", 1.0)
	vp.scaling_3d_scale = escala
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if escala < 0.999 else Viewport.SCALING_3D_MODE_BILINEAR
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
