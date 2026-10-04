shader_type spatial;
// Rocha por dentro do vulcão (túnel da etapa 1 do Extinction Day): basalto escuro com disjunção em
// colunas, veios de obsidiana brilhante, fuligem no teto e fissuras incandescentes que ficam mais
// fortes perto do rio de lava (UV2.y = metros acima da lava). Textura por projeção tripla.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform vec3 c_basalto : source_color = vec3(0.12, 0.11, 0.105);
uniform vec3 c_basalto_claro : source_color = vec3(0.26, 0.23, 0.21);
uniform vec3 c_oxido : source_color = vec3(0.36, 0.14, 0.06);
uniform vec3 c_enxofre : source_color = vec3(0.62, 0.55, 0.2);
uniform vec3 cor_brasa : source_color = vec3(1.0, 0.32, 0.05);
uniform float brasa = 1.0;
// Calor fixo (0..1) para peças sem a altura da lava no UV2 (pilares, lajes, ninho): 0 = rocha fria
uniform float calor_fixo = 0.0;

varying vec3 pos_mundo;
varying vec3 normal_mundo;
varying float acima_lava;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	acima_lava = UV2.y > 0.0 ? UV2.y : 999.0;
}

float tri(sampler2D tex, vec3 p, vec3 w, float escala) {
	return texture(tex, p.yz / escala).r * w.x + texture(tex, p.xz / escala).r * w.y + texture(tex, p.xy / escala).r * w.z;
}

// Colunas de basalto (prismas): células de Voronoi no plano da parede
float colunas(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	float d1 = 9.0;
	float d2 = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = fract(sin(vec2(dot(i + g, vec2(127.1, 311.7)), dot(i + g, vec2(269.5, 183.3)))) * 43758.5453);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;   // 0 na junta entre colunas
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 nw = normalize(normal_mundo);
	vec3 w = pow(abs(nw), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float grande = tri(ruido, p, w, 50.0);
	float medio = tri(ruido_fino, p, w, 7.0);
	float fino = tri(ruido_fino, p, w, 1.8);
	float de_pe = 1.0 - abs(nw.y);

	// Juntas das colunas (verticais nas paredes)
	vec2 plano = vec2((p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001), p.y * 0.25);
	float junta = colunas(plano / 1.6);
	float j = 1.0 - smoothstep(0.0, 0.08, junta);

	vec3 cor = mix(c_basalto, c_basalto_claro, smoothstep(0.35, 0.8, grande) * 0.6 + fino * 0.25);
	cor *= 1.0 - 0.45 * j * de_pe;
	// Óxido e enxofre em manchas (respiros de gás)
	cor = mix(cor, c_oxido, smoothstep(0.62, 0.85, medio) * 0.35);
	cor = mix(cor, c_enxofre, smoothstep(0.82, 0.95, tri(ruido, p, w, 14.0)) * 0.4 * de_pe);
	// Fuligem no teto
	cor *= mix(1.0, 0.55, smoothstep(0.3, 0.9, -nw.y));

	// Lava escorrendo na parede perto do rio (pedido do dono: nada de faixas verticais — as juntas
	// esticadas das colunas acesas viravam listras): crosta preta em placas irregulares que descem
	// devagar e racham, mostrando o miolo derretido. Quanto mais perto da lava, mais largas as
	// rachaduras e mais quente a cor (vermelho → laranja → amarelo); rente ao rio é tudo derretido.
	// Coordenadas da própria parede (túnel: UV.y = metros ao longo, UV2.y = metros acima da lava; a
	// parede da esquerda deslocada para não espelhar a da direita). Peças sem UV2: pela posição.
	vec3 cor_fria = cor;
	vec2 q = vec2(UV.y + step(0.5, UV.x) * 37.0, acima_lava);
	if (acima_lava > 900.0) {
		q = vec2((p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001), p.y);
	}
	float desce = TIME * 0.09;   // m/s parede abaixo
	vec2 torce = vec2(texture(ruido, q / 13.0 + vec2(0.0, desce * 0.04)).r, texture(ruido, q / 13.0 + vec2(0.43, 0.17 + desce * 0.04)).r) - 0.5;
	vec2 qf = q + torce * 1.4 + vec2(0.0, desce);
	// Faixa derretida até perto da estrada (a lava fica 4,6 m abaixo dela), de borda ondulada que
	// escorre junto; acima, só rachaduras que vão apagando até a rocha fria.
	float onda = (texture(ruido, vec2(qf.x / 30.0, qf.y / 8.0)).r - 0.5) * 3.5;
	float perto_lava = max(smoothstep(11.0, 3.5, acima_lava + onda), calor_fixo);
	float aquece = clamp(perto_lava, 0.0, 1.0);
	float borda = colunas(qf / 2.4);           // 0 na rachadura entre placas
	float borda_f = colunas(qf / 0.9 + 7.3);   // trincas finas dentro das placas
	// Longe, as rachaduras alargam o suficiente para não virar chuvisco de pixels
	float aa = fwidth(borda) * 1.5;
	float aa_f = fwidth(borda_f) * 1.5;
	// Bem quente as rachaduras se abrem até sobrar só ilhas de crosta boiando na lava
	float larg = 0.75 * pow(aquece, 2.5);
	float racha = (1.0 - smoothstep(larg * 0.6, larg + 0.02 + aa, borda)) * smoothstep(0.15, 0.4, aquece);
	float racha_f = (1.0 - smoothstep(0.0, 0.01 + 0.05 * aquece + aa_f, borda_f)) * smoothstep(0.45, 0.8, aquece) * 0.6 * (1.0 - smoothstep(0.03, 0.12, aa_f));
	float derretido = clamp(max(racha, racha_f), 0.0, 1.0);
	// Veios mais quentes descendo dentro da lava (ela não brilha por igual)
	float veio = texture(ruido, vec2(qf.x / 3.0, qf.y / 7.0) + vec2(0.0, desce * 0.15)).r;
	float pulso = (0.82 + 0.18 * sin(TIME * 0.6 + grande * 12.0 + medio * 5.0)) * (0.7 + 0.6 * veio);
	float temp = derretido * (0.45 + 0.55 * aquece) * (1.0 - 0.35 * smoothstep(0.0, larg + 0.03, borda)) * pulso;
	vec3 cor_lava = mix(vec3(0.55, 0.04, 0.0), cor_brasa, smoothstep(0.1, 0.65, temp));
	cor_lava = mix(cor_lava, vec3(1.0, 0.7, 0.28), smoothstep(0.75, 1.1, temp));
	// A crosta logo ao lado da rachadura ainda brilha vermelho-escuro
	float crosta_quente = (1.0 - smoothstep(larg, larg + 0.2, borda)) * aquece * (1.0 - derretido);
	EMISSION = (cor_lava * derretido * 1.5 + vec3(0.55, 0.06, 0.0) * crosta_quente * 0.45) * brasa;
	cor = mix(cor, vec3(0.045, 0.038, 0.034), smoothstep(0.1, 0.5, aquece));   // lava esfriada (preta)
	cor = mix(cor, cor_lava * 0.35, derretido);
	if (acima_lava > 900.0) {
		// Peças de calor fixo (pegada, mesa e pedra do alvo, pilares): brasa difusa nas juntas e manchas
		cor = cor_fria;
		aquece = 0.0;
		derretido = 0.0;
		float mancha = smoothstep(0.5, 0.8, tri(ruido, p * vec3(1.0, 0.7, 1.0), w, 9.0));
		float junta_quente = j * smoothstep(0.35, 0.75, medio) * de_pe;
		float fissura = (junta_quente * 0.9 + mancha * 0.45) * calor_fixo + calor_fixo * calor_fixo * 0.25;
		EMISSION = cor_brasa * fissura * 2.6 * brasa * (0.75 + 0.25 * sin(TIME * 0.5 + grande * 9.0));
		cor = mix(cor, cor_brasa * 0.25, clamp(fissura, 0.0, 1.0) * 0.4);
	}

	// Relevo forte de perto
	float e = 0.35;
	vec3 grad = vec3(
		tri(ruido_fino, p + vec3(e, 0.0, 0.0), w, 1.8) - fino,
		tri(ruido_fino, p + vec3(0.0, e, 0.0), w, 1.8) - fino,
		tri(ruido_fino, p + vec3(0.0, 0.0, e), w, 1.8) - fino);
	vec3 nn = nw - grad * 2.6 * (1.0 - derretido);   // o derretido é liso
	nn -= nw * dot(nn - nw, nw);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
	ALBEDO = cor;
	ROUGHNESS = mix(mix(0.9, 0.35, smoothstep(0.85, 0.97, medio)), 0.55, smoothstep(0.1, 0.5, aquece));   // obsidiana brilhante em veios
	ROUGHNESS = mix(ROUGHNESS, 0.2, derretido);   // lava derretida: brilho de coisa molhada
	SPECULAR = 0.35;
	AO = 0.5 + 0.5 * smoothstep(0.15, 0.6, medio);
	AO_LIGHT_AFFECT = 0.6;
}
