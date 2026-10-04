shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
// Rio no fundo do cânion: transparente no raso, turquesa → verde-escuro com a profundidade,
// espuma nas margens, ondas (dois normal maps correndo rio abaixo) e reflexo do céu/sol.

uniform sampler2D normal_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D tela_prof : hint_depth_texture, filter_linear;
uniform vec3 cor_rasa : source_color = vec3(0.1, 0.55, 0.5);
uniform vec3 cor_funda : source_color = vec3(0.03, 0.27, 0.29);
uniform vec3 cor_espuma : source_color = vec3(0.92, 0.9, 0.84);
uniform float profundidade_cor = 3.0;
uniform float largura_espuma = 0.8;
uniform vec2 correnteza = vec2(0.012, 0.035);

varying vec3 pos_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = pos_mundo.xz;
	float t = TIME;
	// Ondas: duas escalas correndo em direções levemente diferentes
	vec3 na = texture(normal_a, p / 38.0 + correnteza * t).rgb;
	vec3 nb = texture(normal_b, p / 13.0 - correnteza.yx * t * 1.4).rgb;
	vec3 n = normalize(mix(na, nb, 0.45) * 2.0 - 1.0);
	float dist = length(pos_mundo - CAMERA_POSITION_WORLD);
	float suaviza = smoothstep(1500.0, 250.0, dist);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), n * 0.5 + 0.5, 0.55 * suaviza + 0.12);

	// Profundidade da água sob este pixel (profundidade da cena - profundidade da superfície)
	float z = textureLod(tela_prof, SCREEN_UV, 0.0).r;
	vec4 fundo = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, z, 1.0);
	fundo.xyz /= fundo.w;
	float prof = max(length(fundo.xyz) - length(VERTEX), 0.0);
	// Aproximação da profundidade vertical (o raio de visão é inclinado)
	float prof_v = prof * clamp(abs(dot(normalize(-VERTEX), (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz)), 0.05, 1.0);

	float k = 1.0 - exp(-prof_v / profundidade_cor);
	vec3 cor = mix(cor_rasa, cor_funda, k);

	// Espuma nas margens, quebrada por ruído que se move
	float r = texture(ruido, p / 9.0 + correnteza * t * 2.0).r;
	float espuma = smoothstep(largura_espuma, 0.0, prof_v) * smoothstep(0.35, 0.65, r + 0.25 * smoothstep(largura_espuma * 0.5, 0.0, prof_v));
	espuma = max(espuma, smoothstep(0.2, 0.0, prof_v)) * 0.85;
	// Longe (rio no horizonte do City Rush): a profundidade da tela perde precisão e a margem inteira
	// virava espuma, e o sol rasante refletido estourava — faixas brancas na linha do horizonte.
	float longe = smoothstep(1200.0, 3500.0, dist);
	espuma *= 1.0 - longe;
	cor = mix(cor, cor_espuma, espuma);

	ALBEDO = cor;
	ALPHA = clamp(mix(0.6, 1.0, smoothstep(0.0, 1.5, prof_v)) + espuma, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.09, 0.6, espuma), 0.45, longe);
	METALLIC = 0.0;
	SPECULAR = 0.35;
}
