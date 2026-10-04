shader_type spatial;
// Placa de impacto dos pingentes de gelo (Frozen Peak): chapa de aço xadrez coberta de gelo
// estilhaçado, moldura de listras de perigo e, por faixa, o aviso vermelho pulsando antes de os
// pingentes caírem. UV.x atravessa a estrada (0 = esquerda), UV.y ao longo.

uniform float aviso_esq = 0.0;
uniform float aviso_dir = 0.0;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	vec2 uv = UV;
	// Chapa xadrez
	vec2 g = fract(uv * vec2(18.0, 24.0));
	float xadrez = step(0.5, fract((floor(uv.x * 18.0) + floor(uv.y * 24.0)) * 0.5));
	float relevo = smoothstep(0.42, 0.3, abs(g.x - 0.5)) * smoothstep(0.12, 0.05, abs(g.y - 0.5));
	vec3 cor = vec3(0.2, 0.22, 0.26) + relevo * 0.12 * mix(1.0, 0.6, xadrez);
	// Estilhaços de gelo: manchas claras
	float gelo = smoothstep(0.6, 0.9, h21(floor(uv * vec2(7.0, 9.0))) * 0.7 + h21(floor(uv * vec2(23.0, 31.0))) * 0.4);
	cor = mix(cor, vec3(0.72, 0.88, 1.0), gelo * 0.6);
	// Moldura de listras de perigo
	float borda = min(min(uv.x, 1.0 - uv.x) * 9.0, min(uv.y, 1.0 - uv.y) * 12.0);
	float moldura = 1.0 - step(0.5, borda);
	float lista = step(0.5, fract((uv.x * 9.0 + uv.y * 12.0) * 1.2));
	cor = mix(cor, mix(vec3(0.05), vec3(0.95, 0.75, 0.1), lista), moldura);
	// Linha do meio (divide as duas faixas)
	float meio = 1.0 - step(0.012, abs(uv.x - 0.5));
	cor = mix(cor, vec3(0.9), meio);
	float pulso = 0.55 + 0.45 * sin(TIME * 18.0);
	float lado = uv.x < 0.5 ? aviso_esq : aviso_dir;
	vec3 emis = vec3(1.0, 0.08, 0.03) * lado * pulso * (0.7 + moldura * 1.5);
	ALBEDO = cor;
	EMISSION = emis;
	ROUGHNESS = mix(0.5, 0.2, gelo);
	METALLIC = 0.7 * (1.0 - gelo) * (1.0 - moldura);
}
