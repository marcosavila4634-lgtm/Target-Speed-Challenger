shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Onda de choque do impacto: anel de poeira e terra arrancada que corre pelo chão a partir do ponto
// do impacto, com a frente clara e incandescente e o rastro escuro, desfiado pelo ruído.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float raio = 0.0;        // m
uniform float largura = 120.0;   // m
uniform float alfa = 1.0;

varying vec3 pos_local;

void vertex() {
	pos_local = VERTEX;
}

void fragment() {
	float r = length(pos_local.xz);
	float ang = atan(pos_local.z, pos_local.x);
	float n = texture(ruido, vec2(ang * 1.6, r * 0.004 - TIME * 0.2)).r;
	float d = (raio - r) / largura;        // 0 na frente, cresce para dentro
	float banda = smoothstep(-0.05 - n * 0.1, 0.05, d) * (1.0 - smoothstep(0.3, 1.0 + n * 0.4, d));
	float frente = smoothstep(-0.05, 0.0, d) * (1.0 - smoothstep(0.0, 0.12, d));
	vec3 poeira = mix(vec3(0.38, 0.3, 0.24), vec3(0.16, 0.12, 0.1), smoothstep(0.0, 0.8, d));
	ALBEDO = poeira + vec3(1.0, 0.5, 0.15) * frente * 3.0;
	ALPHA = banda * alfa * (0.55 + 0.45 * n);
}
