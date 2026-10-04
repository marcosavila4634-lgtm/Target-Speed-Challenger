shader_type spatial;
render_mode cull_disabled, unshaded;
// Borboleta-azul (morpho) em partículas: o quad dobra no meio (as asas batem) e a cor muda de azul
// metálico para quase preto conforme o ângulo, como a asa de verdade.

uniform vec3 cor : source_color = vec3(0.15, 0.55, 1.0);

varying float lado;

void vertex() {
	float fase = INSTANCE_CUSTOM.x * 40.0;
	float a = abs(sin(TIME * 14.0 + fase));
	lado = sign(VERTEX.x);
	VERTEX.y += abs(VERTEX.x) * (1.0 - a) * 1.6;
	VERTEX.x *= a * 0.8 + 0.2;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	q.x = abs(q.x);
	// Duas asas arredondadas (de cima maior) e o corpo fino
	float asa_cima = length((q - vec2(0.45, -0.25)) / vec2(0.55, 0.6));
	float asa_baixo = length((q - vec2(0.35, 0.4)) / vec2(0.38, 0.45));
	float corpo = step(q.x, 0.05) * step(abs(q.y), 0.6);
	float forma = max(step(asa_cima, 1.0), step(asa_baixo, 1.0));
	if (forma < 0.5 && corpo < 0.5) {
		discard;
	}
	float borda = smoothstep(0.75, 1.0, min(asa_cima, asa_baixo + 0.1));
	vec3 c = mix(cor, vec3(0.02, 0.03, 0.06), borda);
	c = mix(c, vec3(0.05), corpo);
	ALBEDO = c;
}
