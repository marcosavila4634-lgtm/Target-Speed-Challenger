shader_type spatial;
// Placa das lanças (Serpent's Climb): basalto escuro com a grade de furos de onde saem as lanças,
// moldura com o padrão de degraus (greca) e, por faixa, o aviso vermelho pulsando antes de subir.
// UV.x atravessa a estrada (0 = esquerda), UV.y ao longo.

uniform float aviso_esq = 0.0;
uniform float aviso_dir = 0.0;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	vec2 uv = UV;
	vec3 cor = mix(vec3(0.11, 0.1, 0.1), vec3(0.17, 0.15, 0.14), h21(floor(uv * vec2(6.0, 8.0))));
	// Furos: grade de 0,9 m (a placa tem ~9 x 12 m)
	vec2 g = fract(uv * vec2(10.0, 13.0) + vec2(0.0, step(0.5, fract(uv.x * 5.0)) * 0.5));
	float furo = 1.0 - smoothstep(0.16, 0.22, length(g - 0.5));
	cor = mix(cor, vec3(0.01), furo);
	// Moldura de greca (degraus) nas bordas
	float borda = min(min(uv.x, 1.0 - uv.x) * 9.0, min(uv.y, 1.0 - uv.y) * 12.0);
	float moldura = 1.0 - step(0.45, borda);
	float ao_longo = (uv.x < 0.05 || uv.x > 0.95) ? uv.y * 12.0 : uv.x * 9.0;
	float degrau = step(0.5, fract(ao_longo * 1.6 + step(0.22, borda) * 0.5));
	vec3 ouro = vec3(0.75, 0.55, 0.22);
	cor = mix(cor, mix(vec3(0.3, 0.26, 0.22), ouro, degrau), moldura);
	// Aviso: a metade da faixa que vai subir brilha vermelho, pulsando
	float pulso = 0.55 + 0.45 * sin(TIME * 18.0);
	float lado = uv.x < 0.5 ? aviso_esq : aviso_dir;
	vec3 emis = vec3(1.0, 0.08, 0.03) * lado * pulso * (furo * 6.0 + moldura * 1.5 + 0.25);
	ALBEDO = cor;
	EMISSION = emis;
	ROUGHNESS = mix(0.55, 0.3, moldura);
	METALLIC = moldura * 0.6;
}
