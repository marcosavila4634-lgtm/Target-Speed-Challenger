shader_type spatial;
// Laterais e fundo da estrada do Serpent's Climb: blocos de calcário com musgo escorrendo e uma faixa
// de jade no topo (brilha de leve). UV.x = metros ao longo; UV.y = 0 no topo, 1 embaixo.

uniform vec3 cor_equipe : source_color = vec3(0.15, 0.85, 0.6);
uniform float energia = 1.4;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	float bloco = floor(UV.x / 1.9);
	float junta = step(0.95, fract(UV.x / 1.9));
	vec3 cor = mix(vec3(0.58, 0.56, 0.48), vec3(0.45, 0.43, 0.37), h21(vec2(bloco, 3.0)));
	cor *= 1.0 - 0.35 * junta;
	// Musgo escorrendo de cima
	float musgo = step(UV.y, 0.25 + 0.5 * h21(vec2(floor(UV.x / 0.6), 5.0))) * step(0.16, UV.y);
	cor = mix(cor, vec3(0.18, 0.28, 0.09), musgo * 0.7);
	float faixa = step(UV.y, 0.16) * step(0.03, UV.y);
	vec3 jade = vec3(0.15, 0.85, 0.6);
	ALBEDO = mix(cor, jade, faixa);
	EMISSION = jade * energia * faixa;
	METALLIC = faixa * 0.3;
	ROUGHNESS = mix(0.85, 0.25, faixa);
}
