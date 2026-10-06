shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Lâmina d'água da cachoeira (Serpent's Climb): fios brancos descendo depressa, água verde-azulada
// translúcida entre eles, bordas desfiadas e espuma mais densa embaixo. UV.x atravessa, UV.y desce.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_agua : source_color = vec3(0.32, 0.55, 0.52);
uniform float velocidade = 0.55;
uniform float opaco = 0.0;   // >0: cortina densa (não se vê o que tem atrás)

void fragment() {
	vec2 uv = UV;
	float t = TIME * velocidade;
	float fios = texture(ruido, vec2(uv.x * 6.0, uv.y * 0.6 - t)).r;
	float fios2 = texture(ruido, vec2(uv.x * 14.0 + 3.1, uv.y * 1.4 - t * 1.6)).r;
	float espuma = smoothstep(0.45, 0.8, fios * 0.6 + fios2 * 0.6);
	float borda = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	borda *= smoothstep(0.0, 0.03, uv.y);
	float base = smoothstep(0.75, 1.0, uv.y);
	vec3 cor = mix(cor_agua, vec3(0.95, 0.98, 1.0), clamp(espuma + base * 0.7, 0.0, 1.0));
	float a = clamp(max(0.55 + espuma * 0.45, opaco), 0.0, 1.0) * borda;
	cor = mix(cor, vec3(0.88, 0.93, 0.95), opaco * 0.55);
	a *= 0.8 + 0.2 * texture(ruido, vec2(uv.x * 3.0, uv.y * 2.0 - t * 0.7)).r;
	ALBEDO = cor;
	ALPHA = a;
	ROUGHNESS = 0.2;
	SPECULAR = 0.6;
	EMISSION = vec3(0.9, 0.95, 1.0) * espuma * 0.15;
}
