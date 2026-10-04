shader_type spatial;
// Laterais e fundo da estrada do Pharaoh's Climb: arenito em blocos com uma faixa dourada no
// topo (friso que brilha de leve ao pôr do sol). UV.x = metros ao longo; UV.y = 0 no topo, 1 embaixo.

uniform vec3 cor_equipe : source_color = vec3(1.0, 0.7, 0.28);
uniform float energia = 1.6;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	float bloco = floor(UV.x / 2.2);
	float junta = step(0.96, fract(UV.x / 2.2));
	vec3 cor = mix(vec3(0.78, 0.63, 0.43), vec3(0.66, 0.5, 0.32), h21(vec2(bloco, 3.0)));
	cor *= 1.0 - 0.35 * junta;
	float faixa = step(UV.y, 0.16) * step(0.03, UV.y);
	ALBEDO = mix(cor, cor_equipe, faixa);
	EMISSION = cor_equipe * energia * faixa;
	METALLIC = faixa * 0.9;
	ROUGHNESS = mix(0.8, 0.3, faixa);
}
