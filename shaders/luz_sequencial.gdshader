shader_type spatial;
// Lâmpadas em sequência (efeito "perseguição"): cada instância do MultiMesh traz a sua fase em INSTANCE_CUSTOM.r.
// cor_flash/flash permitem piscar tudo numa cor (ex.: cor da equipe que pousou no alvo).

uniform vec3 cor : source_color = vec3(1.0, 0.55, 0.15);
uniform float energia = 6.0;
uniform float velocidade = 3.0;
uniform float nitidez = 4.0;
uniform float minimo = 0.25;
uniform vec3 cor_flash : source_color = vec3(1.0);
uniform float flash = 0.0;

varying float fase;

void vertex() {
	fase = INSTANCE_CUSTOM.r;
}

void fragment() {
	float onda = minimo + (1.0 - minimo) * pow(0.5 + 0.5 * sin(fase - TIME * velocidade), nitidez);
	float pisca = step(0.5, fract(TIME * 4.0));
	vec3 c = mix(cor, cor_flash, flash);
	float brilho = mix(onda, 0.6 + 0.4 * pisca, flash);
	ALBEDO = c * 0.25;
	EMISSION = c * energia * brilho;
	ROUGHNESS = 0.35;
}
