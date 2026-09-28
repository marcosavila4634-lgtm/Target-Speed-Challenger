shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Bancos de bruma no fundo do cânion: quads sempre virados para a câmera (MultiMesh),
// borda suave por ruído, somem ao encostar no terreno (profundidade) e quando a câmera chega perto.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D tela_prof : hint_depth_texture, filter_linear;
uniform vec3 cor_luz : source_color = vec3(1.0, 0.82, 0.66);
uniform vec3 cor_sombra : source_color = vec3(0.62, 0.5, 0.52);
uniform float opacidade = 0.55;
uniform float suavidade_chao = 25.0;

varying float v_semente;
varying float v_dist;
varying float v_de_cima;

void vertex() {
	v_semente = INSTANCE_CUSTOM.r;
	float escala = length(MODEL_MATRIX[0].xyz);
	vec3 centro = MODEL_MATRIX[3].xyz;
	vec3 dir_x = INV_VIEW_MATRIX[0].xyz;
	vec3 dir_y = vec3(0.0, 1.0, 0.0);
	vec3 mundo = centro + (dir_x * VERTEX.x + dir_y * VERTEX.y * 0.45) * escala;
	v_dist = length(centro - CAMERA_POSITION_WORLD);
	// Vista de cima o quad vira uma "mancha" no chão: some quando a câmera olha muito para baixo
	v_de_cima = abs(normalize(centro - CAMERA_POSITION_WORLD).y);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(mundo, 1.0);
}

void fragment() {
	vec2 uv = UV - 0.5;
	float r = length(uv * vec2(1.0, 1.6)) * 2.0;
	float n = texture(ruido, UV * 0.8 + vec2(v_semente, TIME * 0.004)).r;
	float n2 = texture(ruido, UV * 2.1 - vec2(TIME * 0.006, v_semente * 2.0)).r;
	float forma = smoothstep(1.0, 0.25, r + (n - 0.5) * 0.9 + (n2 - 0.5) * 0.35);

	// Some onde encosta na rocha/água
	float z = textureLod(tela_prof, SCREEN_UV, 0.0).r;
	vec4 fundo = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	fundo.xyz /= fundo.w;
	float folga = length(fundo.xyz) - length(VERTEX);
	float toque = clamp(folga / suavidade_chao, 0.0, 1.0);
	float perto = smoothstep(60.0, 260.0, v_dist);

	ALBEDO = mix(cor_sombra, cor_luz, clamp(0.35 + UV.y * -0.3 + n * 0.6, 0.0, 1.0));
	ALPHA = forma * toque * perto * opacidade * smoothstep(0.55, 0.25, v_de_cima);
}
