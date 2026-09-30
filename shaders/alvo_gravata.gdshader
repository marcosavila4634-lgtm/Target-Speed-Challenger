shader_type spatial;
render_mode cull_disabled;
// Alvo em gravata (Canyon Combat Target): hexágono comprido, fino no meio e largo nas pontas.
// Faixas ao longo do comprimento (x local): 5 no meio, 4-3-2-1 até as duas pontas, alternando
// vermelho e branco, com divisórias escuras. Fora do contorno e nas laterais: borda de aço gasta.
// Mesmo desgaste do alvo redondo (poeira, lascas, marcas de pneu, ferrugem na borda).

uniform float faixas[5];           // fim das faixas 5, 4, 3, 2, 1 (distância do centro ao longo do x)
uniform float larg_meio = 6.0;
uniform float larg_ponta = 22.0;
uniform vec3 cor_vermelha : source_color = vec3(0.78, 0.1, 0.09);
uniform vec3 cor_branca : source_color = vec3(0.92, 0.9, 0.86);
uniform vec3 cor_borda : source_color = vec3(0.12, 0.12, 0.14);
uniform float divisorias = 1.0;     // 0 = alvo liso (mosca sem as linhas escuras entre as zonas)
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 pos_local;

void vertex() {
	pos_local = VERTEX;
}

void fragment() {
	float u = abs(pos_local.x);
	float v = abs(pos_local.z);
	float comp = faixas[4];
	float meia = mix(larg_meio, larg_ponta, clamp(u / comp, 0.0, 1.0)) * 0.5;
	vec3 cor = cor_borda;
	float dentro = 0.0;
	if (pos_local.y > -0.05 && u <= comp && v <= meia) {
		dentro = 1.0;
		float linha = smoothstep(0.0, 0.12, meia - v);
		linha = min(linha, smoothstep(0.0, 0.12, comp - u));
		for (int i = 0; i < 5; i++) {
			if (u <= faixas[i]) {
				cor = (i % 2 == 0) ? cor_vermelha : cor_branca;
				linha = min(linha, smoothstep(0.0, 0.12, faixas[i] - u));
				if (i > 0) {
					linha = min(linha, smoothstep(0.0, 0.12, u - faixas[i - 1]));
				}
				break;
			}
		}
		cor = mix(cor_borda, cor, mix(1.0, linha, divisorias));
	}
	vec2 p = pos_local.xz;
	float sujeira = texture(ruido, p / 9.0).r;
	cor *= 0.86 + 0.18 * sujeira;
	float lasca = texture(ruido, p / 2.3).r;
	cor = mix(cor, cor * 0.72 + vec3(0.07, 0.06, 0.05), smoothstep(0.55, 0.8, sujeira));
	cor = mix(cor, vec3(0.36, 0.33, 0.3), smoothstep(0.78, 0.86, lasca) * 0.7 * dentro);
	float poeira = smoothstep(0.4, 0.8, texture(ruido, p / 17.0 + 3.7).r) * (0.35 + 0.4 * clamp(u / comp, 0.0, 1.0));
	cor = mix(cor, vec3(0.64, 0.44, 0.3), poeira * 0.55);
	// Marcas de pneu atravessadas (quem freia em zigue-zague no meio)
	float marca = texture(ruido, vec2(p.x * 0.25, p.y * 1.3)).r;
	float pneu = smoothstep(0.66, 0.74, marca) * smoothstep(0.3, 0.7, texture(ruido, p * 0.1).r);
	cor = mix(cor, vec3(0.08, 0.07, 0.06), pneu * 0.35);
	float oxido = smoothstep(0.45, 0.7, texture(ruido, p / 1.7 + pos_local.y).r);
	cor = mix(cor, mix(vec3(0.4, 0.16, 0.06), vec3(0.6, 0.29, 0.1), lasca), (1.0 - dentro) * oxido * 0.85);
	ALBEDO = cor;
	ROUGHNESS = mix(0.7, 0.95, max(poeira, (1.0 - dentro) * oxido));
}
