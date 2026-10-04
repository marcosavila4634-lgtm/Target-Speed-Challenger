shader_type spatial;
// Extinction Day: chão da selva pré-histórica (musgo, samambaias rasteiras, folhas e terra; de longe o
// dossel da floresta gigante), paredões de rocha úmida, e o vulcão — cinza e escória preta no alto,
// basalto em lajes, derrames antigos de lava resfriada nas encostas e a rocha em brasa na beira dos
// rios e lagos de lava (máscara: R = perto da lava, G = chão vulcânico).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform sampler2D mascara : filter_linear, repeat_disable;
uniform float meio_mascara = 3400.0;
uniform vec2 centro_vulcao = vec2(-400.0, -1150.0);
uniform float base_vulcao = 1000.0;
uniform vec3 cor_terra : source_color = vec3(0.2, 0.15, 0.1);
uniform vec3 cor_musgo : source_color = vec3(0.16, 0.28, 0.08);
uniform vec3 cor_folhas : source_color = vec3(0.38, 0.27, 0.13);
uniform vec3 cor_dossel : source_color = vec3(0.08, 0.2, 0.06);
uniform vec3 cor_dossel_claro : source_color = vec3(0.22, 0.38, 0.12);
uniform vec3 cor_rocha : source_color = vec3(0.36, 0.34, 0.3);
uniform vec3 cor_cinza : source_color = vec3(0.24, 0.22, 0.21);
uniform vec3 cor_escoria : source_color = vec3(0.07, 0.065, 0.065);
uniform vec3 cor_brasa : source_color = vec3(1.0, 0.33, 0.06);
// Onda de choque do impacto final (Extinction Day): tudo o que fica dentro do raio é arrasado
uniform vec3 onda_centro = vec3(0.0);
uniform float onda_raio = -1.0;


varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

float ruido_parede(sampler2D tex, vec3 p, vec3 n, float escala) {
	float a = texture(tex, vec2(p.x, p.y) / escala).r;
	float b = texture(tex, vec2(p.z, p.y) / escala).r;
	float wx = abs(n.z);
	float wz = abs(n.x);
	return (a * wx + b * wz) / max(wx + wz, 0.001);
}

float copas(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	float d = 9.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(dot(i + g, vec2(1.0, 57.0))), hash(dot(i + g, vec2(13.0, 7.0))));
			d = min(d, length(g + o - f));
		}
	}
	return d;
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 nw = normalize(normal_mundo);
	float h = p.y;
	float dist = length(p - CAMERA_POSITION_WORLD);
	float perto = smoothstep(2000.0, 200.0, dist);
	float bem_perto = smoothstep(400.0, 40.0, dist);
	float inclinacao = 1.0 - clamp(nw.y, 0.0, 1.0);
	float parede = smoothstep(0.32, 0.62, inclinacao);
	float n_grande = texture(ruido, p.xz / 1100.0).r;
	float nm = texture(ruido, p.xz / 180.0).r;
	float nf = texture(ruido_fino, p.xz / 23.0).r;
	vec2 uv_m = (p.xz + meio_mascara) / (2.0 * meio_mascara);
	vec2 m = texture(mascara, uv_m).rg;
	float vulc = m.g;
	float lava = m.r;

	// ---- Chão da mata
	vec3 chao = mix(cor_musgo * 1.1, cor_dossel_claro * 0.85, smoothstep(0.3, 0.7, nm));
	chao = mix(chao, cor_folhas * 0.85, smoothstep(0.58, 0.8, nf) * 0.55);
	chao = mix(chao, cor_terra, smoothstep(0.68, 0.85, texture(ruido, p.xz / 60.0).r) * 0.7);
	chao *= 0.85 + 0.3 * texture(ruido_fino, p.xz / 2.5).r * bem_perto;
	float c = copas(p.xz / 18.0);
	vec3 dossel = mix(cor_dossel_claro, cor_dossel, smoothstep(0.15, 0.75, c));
	dossel *= 0.85 + 0.25 * nm;
	float longe = smoothstep(240.0, 950.0, dist);
	chao = mix(chao, dossel, longe * (1.0 - vulc));

	// ---- Vulcão: cinza fina, escória e derrames antigos (faixas escuras descendo a encosta)
	vec2 dv = p.xz - centro_vulcao;
	float ang = atan(dv.y, dv.x);
	float derrame = smoothstep(0.55, 0.75, texture(ruido, vec2(ang * 3.2, length(dv) / 900.0)).r);
	vec3 vulcanico = mix(cor_cinza * (0.85 + 0.3 * nf), cor_escoria * (0.8 + 0.4 * nm), derrame);
	vulcanico = mix(vulcanico, cor_cinza * 1.3, smoothstep(380.0, 520.0, h) * 0.5);   // topo coberto de cinza clara
	chao = mix(chao, vulcanico, smoothstep(0.15, 0.6, vulc + (nm - 0.5) * 0.3));

	// ---- Paredões e cortes de estrada: rocha em camadas (basalto escuro no vulcão)
	float hh = h + (n_grande - 0.5) * 30.0;
	float id_camada = floor(hh / 8.0);
	float u = fract(hh / 8.0);
	vec3 rocha = mix(cor_rocha, cor_rocha * 0.6, hash(id_camada * 1.7) * 0.7 + 0.15);
	rocha = mix(rocha, cor_escoria * 1.6, vulc);
	rocha *= 0.9 + 0.2 * ruido_parede(ruido_fino, p, nw, 140.0);
	float junta = smoothstep(0.1, 0.0, u) + smoothstep(0.93, 1.0, u) * 0.6;
	rocha *= 1.0 - 0.3 * junta;
	rocha = mix(rocha, cor_musgo, smoothstep(0.62, 0.92, u) * 0.5 * (1.0 - vulc));
	rocha *= 0.9 + (ruido_parede(ruido_fino, p, nw, 2.0) - 0.5) * 0.2 * bem_perto;
	vec3 cor = mix(chao, rocha, parede);

	// ---- Beira da lava: rocha queimada com fissuras em brasa
	float fissura = smoothstep(0.62, 0.8, texture(ruido_fino, p.xz / 9.0).r) * lava;
	cor = mix(cor, cor_escoria, lava * 0.85);
	EMISSION = cor_brasa * fissura * (2.5 + 1.5 * sin(TIME * 0.6 + nm * 10.0)) * smoothstep(0.3, 1.0, lava);

	vec3 nn = nw;
	if (perto > 0.01) {
		float e = 1.0;
		float b0 = ruido_parede(ruido_fino, p, nw, 6.0);
		float bx = ruido_parede(ruido_fino, p + vec3(e, 0.0, e), nw, 6.0);
		float by = ruido_parede(ruido_fino, p + vec3(0.0, e, 0.0), nw, 6.0);
		vec3 lado = normalize(vec3(-nw.z, 0.0, nw.x) + vec3(0.0001));
		nn += (-(bx - b0) * lado - (by - b0) * vec3(0.0, 1.0, 0.0)) * 1.6 * parede * perto;
		nn.y += (0.25 * smoothstep(0.55, 0.95, u) - 0.3 * junta) * parede * perto;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
	float queimado_t = 0.0;
	if (onda_raio > 0.0) {
		// Terra arrasada: carvão, a frente da onda em brasa e fendas de lava abrindo no chão
		float dd_o = distance(pos_mundo.xz, onda_centro.xz);
		float k_o = smoothstep(0.0, 220.0, onda_raio - dd_o);
		float r1 = texture(ruido, pos_mundo.xz / 330.0).r;
		float r2 = clamp((texture(ruido_fino, pos_mundo.xz / 61.0).r - 0.5) * 2.4 + 0.5, 0.0, 1.0);
		float r3 = clamp((texture(ruido_fino, pos_mundo.xz / 7.0).r - 0.5) * 2.4 + 0.5, 0.0, 1.0);
		float r4 = clamp((texture(ruido, pos_mundo.xz / 1400.0 + 0.37).r - 0.5) * 2.4 + 0.5, 0.0, 1.0);
		float longe_o = length(pos_mundo - CAMERA_POSITION_WORLD);
		// Chão arrasado: carvão e cinza em manchas (não uma tinta preta lisa), raios claros de ejeção saindo
		// do impacto e a terra revirada em volta dele
		vec2 rel_o = pos_mundo.xz - onda_centro.xz;
		float ang_o = atan(rel_o.y, rel_o.x);
		float raios = smoothstep(0.52, 0.6, texture(ruido, vec2(ang_o * 1.9, dd_o / 5200.0)).r) * (1.0 - smoothstep(1200.0, 3600.0, dd_o));
		vec3 carvao = mix(vec3(0.012, 0.01, 0.008), vec3(0.04, 0.034, 0.03), r2);
		carvao = mix(carvao, vec3(0.1, 0.09, 0.082), clamp(raios * 0.7 + 0.35 * smoothstep(0.55, 0.85, r4), 0.0, 1.0));
		carvao *= 0.7 + 0.6 * r3 * (1.0 - smoothstep(300.0, 1500.0, longe_o));
		// Fendas de lava: linhas de nível do ruído grosso (o ruído fica quase todo perto de 0,5, então um
		// limiar em volta de 0,5 acendia o chão inteiro); mais largas perto do impacto. As linhas finas que
		// havia aqui viravam um pontilhado de "purpurina" visto de longe — agora só aparecem de perto.
		float perto_i = 1.0 - smoothstep(500.0, 3800.0, dd_o);
		// Fendas GRANDES (rios de lava de dezenas de metros, que se leem de longe) + a rede média só de perto: a
		// rede média vista a quilômetros virava um pontilhado de areia brilhante no chão inteiro
		float rg = texture(ruido, pos_mundo.xz / 2900.0 + 0.11).r;
		// Uma linha de nível só de cada ruído (em volta de 0,5): poucas fendas compridas e tortas — várias linhas
		// do mesmo ruído desenhavam um mapa de curvas de nível
		float rg2 = texture(ruido, pos_mundo.zx / 2300.0 + 0.63).r;
		float lg = min(abs(rg - 0.5), abs(rg2 - 0.5)) * 14.0;
		float larg_g = mix(0.02, 0.07, perto_i);
		float nucleo_g = 1.0 - smoothstep(0.0, larg_g, lg);
		float halo_g = 1.0 - smoothstep(0.0, larg_g * 4.0, lg);
		float perto_cam = 1.0 - smoothstep(350.0, 1300.0, longe_o);
		float larg_f = mix(0.035, 0.1, perto_i);
		float nucleo = (1.0 - smoothstep(0.0, larg_f, abs(sin(r1 * 45.0)))) * perto_cam;
		float halo_f = (1.0 - smoothstep(0.0, larg_f * 3.5, abs(sin(r1 * 45.0)))) * perto_cam;
		float fina = (1.0 - smoothstep(0.0, 0.07, abs(sin(r2 * 9.0 + r1 * 20.0)))) * smoothstep(0.5, 0.56, r1) * (1.0 - smoothstep(150.0, 600.0, longe_o));
		float pulsa_o = 0.8 + 0.2 * sin(TIME * 1.6 + rg * 40.0);
		// Mato ainda em brasa: manchas grandes e suaves (focos de centenas de metros), não pontos
		float foco = smoothstep(0.62, 0.92, r4) * (1.0 - raios) * (0.6 + 0.4 * smoothstep(0.3, 0.7, rg));
		cor = mix(cor, carvao, k_o * 0.985);
		cor = mix(cor, vec3(0.006, 0.005, 0.004), max(halo_f, halo_g) * k_o * 0.7);
		EMISSION += (vec3(1.0, 0.62, 0.2) * (nucleo_g * nucleo_g * 6.0 + nucleo * nucleo * 4.0) + vec3(1.0, 0.24, 0.03) * (halo_g * 1.6 + halo_f * 1.2 + fina * 2.0 + foco * 0.5)) * pulsa_o * k_o
			+ vec3(1.0, 0.3, 0.04) * k_o * (1.0 - k_o) * 5.0;
		queimado_t = k_o;
	}
	ALBEDO = cor;
	// Carvão e cinza não brilham (com o clarão do impacto o relevo fino cintilava)
	ROUGHNESS = mix(mix(0.95, 0.8, vulc), 1.0, queimado_t);
	SPECULAR = mix(0.25, 0.02, queimado_t);
}
