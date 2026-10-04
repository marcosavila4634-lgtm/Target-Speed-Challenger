shader_type spatial;
// Gosma verde (cuspe dos dinossauros do Extinction Day): meleca grossa e molhada — verde-escura no miolo,
// mais clara e translúcida na beirada, com brilho de coisa molhada. Usada nas gotas do jato e nas placas
// que ficam grudadas no carro.

uniform float luz = 0.35;   // um mínimo de luz própria (as etapas são à noite)

void fragment() {
	float beira = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 cor = mix(vec3(0.1, 0.3, 0.02), vec3(0.5, 0.85, 0.12), beira * 0.7 + 0.15);
	ALBEDO = cor;
	ROUGHNESS = 0.06;
	SPECULAR = 0.9;
	EMISSION = cor * luz;
}
