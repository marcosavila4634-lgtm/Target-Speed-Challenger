shader_type spatial;
// Face superior do alvo: cinco zonas concêntricas com divisórias escuras.
// As cores das zonas não usam azul, amarelo, verde nem roxo (cores das equipes).

uniform float raios[5];            // raio externo das zonas 5, 4, 3, 2, 1
uniform vec3 cor_vermelha : source_color = vec3(0.78, 0.1, 0.09);
uniform vec3 cor_branca : source_color = vec3(0.92, 0.9, 0.86);
uniform vec3 cor_borda : source_color = vec3(0.12, 0.12, 0.14);
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 pos_local;

void vertex() {
	pos_local = VERTEX;
}

void fragment() {
	float r = length(pos_local.xz);
	vec3 cor = cor_borda;
	float linha = 1.0;
	for (int i = 0; i < 5; i++) {
		if (r <= raios[i]) {
			cor = (i % 2 == 0) ? cor_vermelha : cor_branca;
			linha = smoothstep(0.0, 0.12, raios[i] - r);
			if (i > 0) {
				linha = min(linha, smoothstep(0.0, 0.12, r - raios[i - 1]));
			}
			break;
		}
	}
	cor = mix(cor_borda, cor, linha);
	float sujeira = texture(ruido, pos_local.xz / 9.0).r;
	cor *= 0.86 + 0.18 * sujeira;

	// Desgaste: tinta desbotada e lascada, poeira do cânion, marcas de pneu em arco e ferrugem na borda
	float lasca = texture(ruido, pos_local.xz / 2.3).r;
	cor = mix(cor, cor * 0.72 + vec3(0.07, 0.06, 0.05), smoothstep(0.55, 0.8, sujeira));
	cor = mix(cor, vec3(0.36, 0.33, 0.3), smoothstep(0.78, 0.86, lasca) * 0.7);
	float poeira = smoothstep(0.4, 0.8, texture(ruido, pos_local.xz / 17.0 + 3.7).r) * (0.35 + 0.4 * smoothstep(raios[2], raios[4], r));
	cor = mix(cor, vec3(0.64, 0.44, 0.3), poeira * 0.55);
	float ang = atan(pos_local.z, pos_local.x);
	float arco = texture(ruido, vec2(ang * 0.35 + floor(r / 3.0) * 0.21, r * 1.4)).r;
	float pneu = smoothstep(0.66, 0.74, arco) * smoothstep(0.3, 0.7, texture(ruido, vec2(ang * 1.7, r * 0.1)).r);
	cor = mix(cor, vec3(0.08, 0.07, 0.06), pneu * 0.35);
	float borda_ext = smoothstep(raios[4] - 0.2, raios[4] + 0.3, r);
	float oxido = smoothstep(0.45, 0.7, texture(ruido, pos_local.xz / 1.7 + pos_local.y).r);
	cor = mix(cor, mix(vec3(0.4, 0.16, 0.06), vec3(0.6, 0.29, 0.1), lasca), borda_ext * oxido * 0.85);
	ALBEDO = cor;
	ROUGHNESS = mix(0.7, 0.95, max(poeira, borda_ext * oxido));
}
