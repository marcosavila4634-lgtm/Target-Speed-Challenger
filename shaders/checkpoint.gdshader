shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// Ponto de checagem do Climb to Death: cilindro de luz transparente saindo da estrada.
// Mais forte embaixo e sumindo para cima, faixas subindo e borda (fresnel) acesa.
// `brilho` sobe por um instante quando alguém passa por ele.

uniform vec3 cor : source_color = vec3(1.0, 0.85, 0.35);
uniform float altura = 6.0;
uniform float brilho = 1.0;

varying float h;

void vertex() {
	h = VERTEX.y / altura + 0.5;   // 0 no chão, 1 no topo
}

void fragment() {
	float hh = clamp(h, 0.0, 1.0);
	float some = pow(1.0 - hh, 1.6);
	float faixas = smoothstep(0.7, 1.0, fract(hh * 5.0 - TIME * 0.7));
	float base = smoothstep(0.1, 0.0, hh);
	float borda = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float a = some * (0.1 + 0.45 * faixas + 0.5 * borda) + base * 0.8;
	ALBEDO = cor * brilho;
	ALPHA = clamp(a * brilho, 0.0, 1.0);
}
