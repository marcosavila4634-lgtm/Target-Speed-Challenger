shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Chama de tocha (Extinction Day, beira da estrada): quad que gira só em volta do eixo vertical para
// a câmera, com a língua de fogo desenhada por ruído subindo — sem partículas, então centenas de
// tochas custam uma única chamada de desenho. INSTANCE_CUSTOM.r = fase (cada tocha tremula diferente).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float energia = 2.6;

varying float fase;

void vertex() {
	fase = INSTANCE_CUSTOM.r;
	vec3 origem = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 para = CAMERA_POSITION_WORLD - origem;
	para.y = 0.0;
	para = length(para) > 0.001 ? normalize(para) : vec3(0.0, 0.0, 1.0);
	vec3 lado = normalize(cross(vec3(0.0, 1.0, 0.0), para));
	float esc_x = length(MODEL_MATRIX[0].xyz);
	float esc_y = length(MODEL_MATRIX[1].xyz);
	vec3 mundo = origem + lado * VERTEX.x * esc_x + vec3(0.0, 1.0, 0.0) * VERTEX.y * esc_y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(mundo, 1.0);
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);   // y: 0 na base, 1 no topo
	float t = TIME + fase * 7.3;
	float n = texture(ruido, vec2(p.x * 1.3 + fase, p.y * 0.9 - t * 1.4)).r;
	float n2 = texture(ruido, vec2(p.x * 2.7 - fase * 2.0, p.y * 2.1 - t * 2.6)).r;
	// Língua de fogo: larga embaixo, afinando e ondulando em cima
	float larg = 0.34 * pow(1.0 - p.y, 0.8) * smoothstep(0.0, 0.12, p.y) + 0.015;
	float x = p.x + (n - 0.5) * 0.32 * p.y + sin(t * 3.1 + p.y * 5.0) * 0.03 * p.y;
	float forma = 1.0 - smoothstep(larg * 0.45, larg, abs(x));
	forma *= 1.0 - smoothstep(0.45, 0.95, p.y + (n2 - 0.5) * 0.45);
	float nucleo = (1.0 - smoothstep(0.0, larg * 0.55, abs(x))) * (1.0 - smoothstep(0.08, 0.42, p.y + (n - 0.5) * 0.15));
	vec3 cor = mix(vec3(0.9, 0.18, 0.02), vec3(1.0, 0.55, 0.12), clamp(forma * 1.3, 0.0, 1.0));
	cor = mix(cor, vec3(1.0, 0.88, 0.55), nucleo);
	float tremor = 0.85 + 0.15 * sin(t * 13.0) * sin(t * 7.7);
	ALBEDO = cor * forma * energia * tremor;
	ALPHA = forma;
}
