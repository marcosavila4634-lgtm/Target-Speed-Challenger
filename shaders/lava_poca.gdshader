shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
// Poça onde a queda de lava do túnel bate no piso: acesa enquanto a lava cai; quando a queda para,
// a crosta escura vai fechando por cima até sobrar só rachadura em brasa, e some.
//   quente: 0 = fria (invisível), 1 = lava caindo em cima

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float quente = 0.0;
uniform float energia = 1.5;

varying vec3 pos_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// UV.x = de uma beirada à outra da pista, UV.y = ao longo da pista
	float longe = abs(UV.y * 2.0 - 1.0);
	float recorte = texture(ruido, pos_mundo.xz * 0.06).r - 0.5;
	float mascara = 1.0 - smoothstep(0.3, 0.9, longe + recorte * 0.5);
	float placas = texture(ruido, pos_mundo.xz * 0.17 + vec2(TIME * 0.012, 0.0)).r;
	float fino = texture(ruido, pos_mundo.xz * 0.6 - vec2(0.0, TIME * 0.05)).r;
	float limiar = mix(0.12, 0.7, quente) + (1.0 - longe) * 0.2 * quente;
	float valor = placas + fino * 0.15;
	float crosta = smoothstep(limiar - 0.05, limiar + 0.08, valor);
	float racha = 1.0 - smoothstep(0.0, 0.06, abs(valor - limiar));
	vec3 miolo = mix(vec3(1.0, 0.3, 0.02), vec3(1.0, 0.75, 0.25), fino * quente);
	vec3 cor = mix(miolo * energia, vec3(0.05, 0.015, 0.01), crosta);
	cor += vec3(1.0, 0.3, 0.03) * racha * crosta * 0.8 * quente;
	ALBEDO = cor;
	ALPHA = mascara * smoothstep(0.0, 0.25, quente);
}
