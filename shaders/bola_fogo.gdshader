shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never;
// Bola de fogo do impacto do meteoro: turbulência de fogo (ruído em projeção tripla que sobe e se
// revolve), miolo branco-amarelo, laranja e vermelho por fora, manchas de fumaça escura que crescem
// com a idade e a borda transparente (fresnel). `vida` 0 = acabou de explodir, 1 = virou fumaça.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float vida : hint_range(0.0, 1.0) = 0.0;
uniform float energia = 6.0;
uniform float alfa = 1.0;

varying vec3 pos_local;
varying vec3 normal_local;

void vertex() {
	pos_local = VERTEX;
	normal_local = NORMAL;
	// Superfície fervendo (o fogo não é uma esfera lisa)
	float n = texture(ruido, VERTEX.xz * 0.35 + vec2(0.0, TIME * 0.05)).r + texture(ruido, VERTEX.xy * 0.3 - vec2(TIME * 0.04, 0.0)).r;
	VERTEX += NORMAL * (n - 1.0) * 0.07;
}

float tri(vec3 p, vec3 w) {
	return texture(ruido, p.yz).r * w.x + texture(ruido, p.xz).r * w.y + texture(ruido, p.xy).r * w.z;
}

void fragment() {
	vec3 w = pow(abs(normal_local), vec3(3.0));
	w /= (w.x + w.y + w.z);
	vec3 p = pos_local * 0.55 + vec3(0.0, -TIME * 0.06, 0.0);
	float n1 = tri(p, w);
	float n2 = tri(p * 2.1 + vec3(TIME * 0.03, 0.0, 0.0), w);
	float turb = n1 * 0.65 + n2 * 0.35;
	float fres = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float calor = clamp(turb * 1.4 - vida * 0.9 + fres * 0.35, 0.0, 1.0);
	vec3 fogo = mix(vec3(0.5, 0.06, 0.01), vec3(1.0, 0.45, 0.08), smoothstep(0.2, 0.55, calor));
	fogo = mix(fogo, vec3(1.0, 0.92, 0.7), smoothstep(0.6, 0.95, calor));
	float fumaca = smoothstep(0.35, 0.8, vida + (0.5 - turb) * 0.6);
	vec3 cor = mix(fogo * energia * (1.0 - vida * 0.6), vec3(0.32, 0.12, 0.05) * energia * 0.3, fumaca);
	ALBEDO = cor;
	// A bola some em fumaça (as nuvens de partículas continuam o cogumelo)
	ALPHA = alfa * smoothstep(0.0, 0.35, fres) * (1.0 - smoothstep(0.3, 0.55, vida));
}
