shader_type spatial;
// Laterais e fundo do tabuleiro: aço escuro com uma faixa de neon da equipe no topo.
// UV.x = metros ao longo da pista; UV.y = 0 no topo da lateral, 1 embaixo (fundo usa UV.y = 0.5).

uniform vec3 cor_equipe : source_color = vec3(0.2, 0.45, 1.0);
uniform float energia = 3.5;

void fragment() {
	float faixa = step(UV.y, 0.14) * step(0.03, UV.y);
	float juntas = step(0.97, fract(UV.x / 6.0));
	vec3 cor = vec3(0.12, 0.125, 0.14) * (1.0 - 0.4 * juntas);
	ALBEDO = mix(cor, cor_equipe * 0.5, faixa);
	EMISSION = cor_equipe * energia * faixa;
	METALLIC = 0.7;
	ROUGHNESS = 0.45;
}
