shader_type spatial;
// Público nas arquibancadas (MultiMesh): cada pessoa tem a cor da roupa em INSTANCE_CUSTOM.rgb e
// um balanço próprio (INSTANCE_CUSTOM.a = fase). `animacao` sobe quando a corrida esquenta
// (largada e chegada): a torcida pula e agita os braços.

uniform float animacao = 0.3;
uniform vec3 cor_pele_a : source_color = vec3(0.85, 0.66, 0.52);
uniform vec3 cor_pele_b : source_color = vec3(0.36, 0.23, 0.15);

varying vec3 roupa;
varying float cabeca;
varying float pele;

void vertex() {
	float fase = INSTANCE_CUSTOM.a * 6.2831;
	roupa = INSTANCE_CUSTOM.rgb;
	pele = fract(INSTANCE_CUSTOM.a * 7.13);
	cabeca = step(1.35, VERTEX.y);
	// Pulinhos e balanço (mais forte com a animação)
	float pulo = max(sin(TIME * (5.0 + 3.0 * pele) + fase), 0.0) * 0.12 * animacao;
	VERTEX.y += pulo;
	VERTEX.x += sin(TIME * 1.3 + fase) * 0.03 * VERTEX.y * (0.3 + animacao);
}

void fragment() {
	vec3 c = mix(roupa, mix(cor_pele_a, cor_pele_b, pele), cabeca);
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
