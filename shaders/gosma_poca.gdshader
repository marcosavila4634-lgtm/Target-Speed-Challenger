shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
// Poça de gosma na pista: mancha de contorno irregular e arredondado (não um retângulo), abaulada — o
// relevo vem do próprio contorno — escura no meio, clara na borda e com brilho molhado.
//   quanto: 0 = sumida, 1 = cheia (a mancha cresce e encolhe pelas bordas)

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float quanto = 0.0;
uniform float semente = 0.0;

float campo(vec2 uv) {
	vec2 p = (uv - 0.5) * 2.0;
	float f = 1.0 - length(p);
	f += (texture(ruido, uv * 0.9 + semente).r - 0.5) * 1.1;
	f += (texture(ruido, uv * 2.6 + semente * 3.0).r - 0.5) * 0.45;
	return f;
}

void fragment() {
	float limiar = mix(0.95, 0.22, quanto);
	float f = campo(UV) - limiar;
	float d = 0.012;
	vec3 n = normalize(vec3(campo(UV - vec2(d, 0.0)) - campo(UV + vec2(d, 0.0)), campo(UV - vec2(0.0, d)) - campo(UV + vec2(0.0, d)), 0.16));
	float alto = smoothstep(0.0, 0.3, f);
	ALBEDO = mix(vec3(0.5, 0.82, 0.12), vec3(0.09, 0.28, 0.02), alto);
	NORMAL_MAP = mix(n, vec3(0.0, 0.0, 1.0), alto * 0.6) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.6;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	EMISSION = ALBEDO * 0.3;
	ALPHA = smoothstep(0.0, 0.035, f) * smoothstep(0.0, 0.15, quanto) * 0.94;
}
