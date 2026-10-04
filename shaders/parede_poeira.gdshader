shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
// Parede de poeira e terra arrancada da onda de choque (anel vertical que cresce a partir do impacto):
// densa e incandescente na base, desfiada e escura em cima, ondulando com o ruído.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float alfa = 1.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;   // 0 em cima, 1 embaixo
	float n = texture(ruido, vec2(u * 9.0, v * 1.4 - TIME * 0.25)).r;
	float n2 = texture(ruido, vec2(u * 23.0 + 0.3, v * 3.0 - TIME * 0.4)).r;
	float altura = 0.35 + 0.55 * n;               // topo irregular
	float corpo = smoothstep(1.0 - altura - 0.12, 1.0 - altura + 0.15, v);
	vec3 poeira = mix(vec3(0.2, 0.16, 0.13), vec3(0.5, 0.4, 0.32), n2);
	vec3 brasa = vec3(1.0, 0.42, 0.1) * smoothstep(0.75, 1.0, v) * (0.6 + 0.8 * n2) * 2.5;
	ALBEDO = poeira + brasa;
	ALPHA = corpo * alfa * (0.55 + 0.45 * n2);
}
