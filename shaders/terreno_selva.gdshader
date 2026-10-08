shader_type spatial;
// Selva (Serpent's Climb):
// - chão da mata: terra escura, folhas secas e manchas de musgo; de longe, onde só se vê o topo das
//   árvores, um "dossel" de copas em tons de verde com sombras entre elas;
// - encostas de mata virgem: a folhagem cobre quase tudo (tufos de folhas claras e escuras com sombra entre
//   eles), cipós escorrendo do alto, musgo, e a rocha molhada só aparece em manchas;
// - margem do rio: barro molhado e capim verde-claro (máscara mascara_rio de Selva.textura_margem).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform sampler2D mascara_rio : filter_linear, repeat_disable;
uniform float meio_mascara = 3400.0;
uniform float nivel_agua = 4.0;
uniform vec3 cor_terra : source_color = vec3(0.22, 0.16, 0.1);
uniform vec3 cor_folhas : source_color = vec3(0.42, 0.28, 0.13);
uniform vec3 cor_musgo : source_color = vec3(0.18, 0.3, 0.08);
uniform vec3 cor_rocha : source_color = vec3(0.46, 0.44, 0.38);
uniform vec3 cor_rocha_escura : source_color = vec3(0.26, 0.25, 0.22);
uniform vec3 cor_capim : source_color = vec3(0.36, 0.5, 0.14);
uniform vec3 cor_barro : source_color = vec3(0.27, 0.2, 0.13);
uniform vec3 cor_dossel : source_color = vec3(0.12, 0.26, 0.07);
uniform vec3 cor_dossel_claro : source_color = vec3(0.3, 0.45, 0.13);
// Etapa com encostas de mata virgem (Selva.preparar_etapa liga só na etapa 1, pedido do dono)
uniform bool mata_virgem = false;
// Paredões quase verticais da E1: rocha da arte do dono (rocha_ladrilho.png) em vez de folhagem
uniform sampler2D rocha_lad : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool com_rocha_lad = false;

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

// Copas vistas de cima: células (Voronoi barato) com o miolo claro e a borda escura
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

// Tufos de folhagem projetados nos três eixos (sem esticar em nenhuma face): x = célula, y = id do tufo
vec2 tufos(vec3 p, vec3 n, float escala, vec2 desl) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float a = copas(p.zy / escala + desl);
	float b = copas(p.xz / escala + desl);
	float c = copas(p.xy / escala + desl);
	float ia = hash(dot(floor(p.zy / escala + desl), vec2(1.0, 57.0)));
	float ib = hash(dot(floor(p.xz / escala + desl), vec2(1.0, 57.0)));
	float ic = hash(dot(floor(p.xy / escala + desl), vec2(1.0, 57.0)));
	return vec2(a * w.x + b * w.y + c * w.z, ia * w.x + ib * w.y + ic * w.z);
}

void fragment() {
	float rocha_lad_lum = -1.0;
	vec3 p = pos_mundo;
	vec3 nw = normalize(normal_mundo);
	float h = p.y;
	float dist = length(p - CAMERA_POSITION_WORLD);
	float perto = smoothstep(2000.0, 200.0, dist);
	float bem_perto = smoothstep(400.0, 40.0, dist);
	float inclinacao = 1.0 - clamp(nw.y, 0.0, 1.0);
	float parede = smoothstep(0.32, 0.6, inclinacao);

	float n_grande = texture(ruido, p.xz / 1100.0).r;
	float nm = texture(ruido, p.xz / 180.0).r;
	float nf = texture(ruido_fino, p.xz / 23.0).r;

	// ---- Chão da mata
	// Sub-bosque verde (ervas, musgo) com manchas de folhas secas e terra
	vec3 chao = mix(cor_musgo * 1.15, cor_dossel_claro * 0.9, smoothstep(0.3, 0.7, nm));
	chao = mix(chao, cor_folhas * 0.85, smoothstep(0.58, 0.8, nf) * 0.6);
	chao = mix(chao, cor_terra, smoothstep(0.68, 0.85, texture(ruido, p.xz / 60.0).r) * 0.7);
	chao *= 0.92 + 0.14 * texture(ruido_fino, p.xz / 2.5).r * bem_perto;
	// De longe: dossel (o chão some embaixo das copas)
	float c = copas(p.xz / 14.0);
	vec3 dossel = mix(cor_dossel_claro, cor_dossel, smoothstep(0.15, 0.75, c));
	dossel = mix(dossel, cor_dossel_claro * 1.15, smoothstep(0.55, 0.85, n_grande) * 0.4);
	dossel *= 0.85 + 0.25 * nm;
	float longe = smoothstep(220.0, 900.0, dist);
	chao = mix(chao, dossel, max(longe, 0.0));

	// ---- Paredões das outras etapas: calcário úmido em camadas, com musgo nos degraus
	float hh0 = h + (n_grande - 0.5) * 30.0;
	float id_camada = floor(hh0 / 9.0);
	float u = fract(hh0 / 9.0);
	vec3 rocha0 = mix(cor_rocha, cor_rocha_escura, hash(id_camada * 1.7) * 0.7 + 0.15);
	rocha0 *= 0.9 + 0.2 * ruido_parede(ruido_fino, p, nw, 140.0);
	float junta = smoothstep(0.1, 0.0, u) + smoothstep(0.93, 1.0, u) * 0.6;
	rocha0 *= 1.0 - 0.3 * junta;
	float along0 = (p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001);
	float escorre0 = texture(ruido_fino, vec2(along0 / 6.0, h / 500.0)).r;
	rocha0 = mix(rocha0, rocha0 * vec3(0.55, 0.58, 0.5), smoothstep(0.55, 0.8, escorre0) * 0.6);
	float musgo_r = smoothstep(0.62, 0.92, u) + smoothstep(0.55, 0.8, ruido_parede(ruido, p, nw, 40.0)) * 0.5;
	rocha0 = mix(rocha0, cor_musgo * 1.1, clamp(musgo_r, 0.0, 1.0) * 0.75);
	rocha0 *= 0.9 + (ruido_parede(ruido_fino, p, nw, 2.0) - 0.5) * 0.2 * bem_perto;


	// ---- Encosta de mata virgem
	float along = (p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001);
	// Rocha molhada (só onde a mata abre): camadas tortas e fracas, escorrido escuro
	float hh = h + (n_grande - 0.5) * 40.0 + (texture(ruido, vec2(along, h) / 90.0).r - 0.5) * 18.0;
	vec3 rocha = mix(cor_rocha * vec3(0.6, 0.66, 0.52), cor_rocha_escura * vec3(0.6, 0.68, 0.5), 0.55 + 0.4 * texture(ruido, vec2(floor(hh / 11.0) * 0.37, 0.5)).r);
	rocha *= 0.75 + 0.35 * ruido_parede(ruido_fino, p, nw, 9.0);
	float escorre = texture(ruido_fino, vec2(along / 5.0, h / 400.0)).r;
	rocha = mix(rocha, rocha * vec3(0.45, 0.48, 0.4), smoothstep(0.5, 0.8, escorre) * 0.7);
	rocha = mix(rocha, cor_musgo * 0.9, smoothstep(0.45, 0.75, ruido_parede(ruido, p, nw, 25.0)) * 0.55);
	// Folhagem: tufos (células) em dois tamanhos, miolo claro e borda escura, verdes variados
	vec2 tt = tufos(p, nw, 3.2, vec2(13.0, 7.0));
	float t1 = tt.x;
	float id = tt.y;
	float t2 = tufos(p, nw, 1.1, vec2(3.0, 41.0)).x;
	vec3 folha = mix(cor_dossel * 0.3, cor_dossel_claro * 0.7, smoothstep(0.85, 0.12, t1));
	folha = mix(folha, mix(cor_musgo * 0.8, cor_dossel_claro * 0.8, id) * vec3(1.0, 1.0, 0.85), 0.2 + 0.25 * id);
	folha *= 0.55 + 0.55 * smoothstep(0.9, 0.2, t2);
	folha *= vec3(0.82, 0.9, 0.7);   // verde de mata fechada, não de gramado
	// Folhas largas mais claras (bananeiras, taiobas) de vez em quando
	folha = mix(folha, cor_dossel_claro * 1.5, smoothstep(0.3, 0.1, t1) * step(0.82, id) * 0.6);
	// Onde a mata cobre a encosta (quase tudo; de longe ainda mais)
	float cobre = smoothstep(0.08, 0.26, n_grande * 0.5 + nm * 0.5 + (ruido_parede(ruido_fino, p, nw, 40.0) - 0.5) * 0.35 + 0.08 * longe);
	// Cipós: fios verticais que escorrem do alto, mais densos onde a mata cobre
	float fio = texture(ruido_fino, vec2(along / 2.2, h / 160.0)).r;
	float cipo = smoothstep(0.62, 0.7, fio) * smoothstep(0.3, 0.6, texture(ruido, vec2(along / 30.0, h / 70.0)).r);
	vec3 parede_cor = mix(rocha, folha, cobre);
	parede_cor = mix(parede_cor, cor_dossel * vec3(0.8, 1.05, 0.7) * (0.8 + 0.4 * t2), cipo * 0.85);
	vec3 rocha_final = mata_virgem ? parede_cor : rocha0;
	float ingreme = smoothstep(0.55, 0.3, nw.y);
	if (com_rocha_lad) {
		vec3 wl = pow(abs(nw), vec3(4.0));
		wl /= (wl.x + wl.y + wl.z + 0.0001);
		vec3 rl = texture(rocha_lad, vec2(p.z, -p.y) / 60.0).rgb * wl.x + texture(rocha_lad, p.xz / 60.0).rgb * wl.y + texture(rocha_lad, vec2(p.x, -p.y) / 60.0 + 0.5).rgb * wl.z;
		// Manchas claras/escuras para o ladrilho não repetir igual. (Antes era uma 2ª camada pela coordenada
		// "along", que muda com a normal: em paredão curvo a rocha virava riscos escorridos.)
		rl *= 0.8 + 0.4 * ruido_parede(ruido, p, nw, 130.0);
		rl = mix(rl, vec3(dot(rl, vec3(0.3, 0.59, 0.11))), 0.25) * 0.85;
		rocha_lad_lum = dot(rl, vec3(0.3, 0.59, 0.11));
		if (!mata_virgem) {
			// Paredão liso e grande: musgo em manchas quebra a face toda igual
			float musgo_l = smoothstep(0.5, 0.74, ruido_parede(ruido, p + 71.0, nw, 55.0));
			rl = mix(rl, cor_musgo * (0.7 + 1.6 * rocha_lad_lum), musgo_l * 0.45);
		}
		// Paredão de qualquer etapa: só a rocha da arte do dono (rochadiferente angulos), nunca o calcário antigo
		rocha_final = mix(mata_virgem ? rocha_final : rl, rl * (0.85 + 0.3 * n_grande), ingreme);
		if (!mata_virgem) { rocha_final = rl * (0.85 + 0.3 * n_grande); }
		cobre *= 1.0 - ingreme;
	}

	// ---- Margem do rio
	vec2 uv_m = (p.xz + meio_mascara) / (2.0 * meio_mascara);
	float margem = texture(mascara_rio, uv_m).r;
	vec3 beira = mix(cor_capim * (0.8 + 0.4 * nf), cor_barro, smoothstep(0.75, 0.95, margem));
	chao = mix(chao, beira, smoothstep(0.25, 0.5, margem + (nf - 0.5) * 0.15) * (1.0 - longe * 0.7));
	float umido = smoothstep(nivel_agua + 2.5, nivel_agua + 0.2, h);

	vec3 cor = mix(chao, rocha_final, parede);
	cor *= 1.0 - 0.45 * umido;

	vec3 nn = nw;
	if (perto > 0.01) {
		float e = 1.0;
		float b0 = ruido_parede(ruido_fino, p, nw, 6.0);
		float bx = ruido_parede(ruido_fino, p + vec3(e, 0.0, e), nw, 6.0);
		float by = ruido_parede(ruido_fino, p + vec3(0.0, e, 0.0), nw, 6.0);
		vec3 lado = normalize(vec3(-nw.z, 0.0, nw.x) + vec3(0.0001));
		nn += (-(bx - b0) * lado - (by - b0) * vec3(0.0, 1.0, 0.0)) * 1.6 * parede * perto;
		// Tufos de folha "estufam" a encosta (sombra na borda de cada tufo)
		float bx2 = tufos(p + lado * 0.4, nw, 3.2, vec2(13.0, 7.0)).x;
		float by2 = tufos(p + vec3(0.0, 0.4, 0.0), nw, 3.2, vec2(13.0, 7.0)).x;
		if (mata_virgem) {
			nn += ((bx2 - t1) * lado + (by2 - t1) * vec3(0.0, 1.0, 0.0)) * 2.2 * cobre * parede * perto;
		} else {
			nn.y += (0.25 * smoothstep(0.55, 0.95, u) - 0.3 * junta) * parede * perto;
		}
		// Dossel de longe com relevo (as copas "estufam")
		nn.xz += vec2(dFdx(c), dFdy(c)) * 0.0;
	}
	// Chão: torrões, raízes e folhas caídas em relevo miúdo (de perto), não um piso liso
	if (bem_perto > 0.01) {
		float e2 = 0.35;
		float g0 = texture(ruido_fino, p.xz / 3.0).r * 0.6 + texture(ruido_fino, p.xz / 0.9).r * 0.4;
		float gx = texture(ruido_fino, (p.xz + vec2(e2, 0.0)) / 3.0).r * 0.6 + texture(ruido_fino, (p.xz + vec2(e2, 0.0)) / 0.9).r * 0.4;
		float gz = texture(ruido_fino, (p.xz + vec2(0.0, e2)) / 3.0).r * 0.6 + texture(ruido_fino, (p.xz + vec2(0.0, e2)) / 0.9).r * 0.4;
		nn += vec3(-(gx - g0), 0.0, -(gz - g0)) * 5.0 * (1.0 - parede) * bem_perto * (1.0 - umido);
		cor *= 0.94 + 0.12 * g0 * bem_perto * (1.0 - parede);
	}
	ALBEDO = cor;
	if (rocha_lad_lum >= 0.0) {
		// Blocos e fendas da arte pegam luz (relevo pelo claro-escuro)
		vec2 dl = vec2(dFdx(rocha_lad_lum), dFdy(rocha_lad_lum));
		nn = normalize(nn + (mat3(INV_VIEW_MATRIX) * vec3(-dl.x, -dl.y, 0.0)) * 1.5 * parede);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
	ROUGHNESS = mix(0.95, 0.35, umido * 0.8 + parede * 0.15 * (mata_virgem ? 1.0 - cobre : 1.0));
	SPECULAR = mix(0.25, 0.5, umido);
}
