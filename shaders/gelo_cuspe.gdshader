shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
// Gelo que a foca cospe na faixa (Frozen Peak, armadilha "focas"): mancha de geada e cristais que se
// espalha do meio para fora enquanto ela cospe (`quanto` 0..1) e some devagar depois. Coordenadas do
// plano (x, z em metros, centro no meio da mancha).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float quanto = 0.0;
uniform vec2 meia = vec2(2.8, 4.5);
uniform float semente = 0.0;

varying vec3 p_local;

void vertex() {
	p_local = VERTEX;
}

void fragment() {
	vec2 q = p_local.xz / meia;
	float n = texture(ruido, p_local.xz / 3.0 + semente).r;
	float n2 = texture(ruido, p_local.xz / 0.7 + semente * 2.0).r;
	float r = length(q) + (n - 0.5) * 0.7;
	float cobre = smoothstep(quanto * 1.1 + 0.02, quanto * 1.1 - 0.25, r) * smoothstep(0.0, 0.15, quanto);
	// Cristais: cristas finas do ruído (agulhas de gelo) por cima da geada
	float agulha = 1.0 - smoothstep(0.0, 0.035, abs(n2 - 0.5));
	vec3 cor = mix(vec3(0.62, 0.84, 0.98), vec3(0.95, 0.98, 1.0), smoothstep(0.4, 0.75, n));
	cor = mix(cor, vec3(1.0), agulha * 0.7);
	ALBEDO = cor;
	ROUGHNESS = mix(0.15, 0.6, n);
	SPECULAR = 0.8;
	EMISSION = vec3(0.3, 0.6, 0.85) * (0.15 + agulha * 0.4) * cobre;
	ALPHA = cobre * (0.7 + 0.3 * agulha);
}
