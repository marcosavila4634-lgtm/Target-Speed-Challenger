shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_never;
// Espuma no pé da cachoeira: manchas brancas borbulhando, mais densas no meio, sumindo na borda.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float r = length(local.xz) / max(length(vec2(1.0)), 1.0);
	vec2 q = local.xz * 0.06;
	float n = texture(ruido, q + vec2(TIME * 0.05, -TIME * 0.08)).r;
	float n2 = texture(ruido, q * 2.3 - vec2(TIME * 0.11, 0.0)).r;
	float d = length(local.xz);
	float fade = 1.0 - smoothstep(0.0, 1.0, d / 45.0);
	float espuma = smoothstep(0.45, 0.75, n * 0.6 + n2 * 0.5) * fade;
	ALBEDO = vec3(0.95, 0.98, 1.0);
	ALPHA = espuma * 0.85 * step(0.001, 1.0 - local.y);
}
