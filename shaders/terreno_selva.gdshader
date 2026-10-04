shader_type spatial;
// Selva (Serpent's Climb):
// - chão da mata: terra escura, folhas secas e manchas de musgo; de longe, onde só se vê o topo das
//   árvores, um "dossel" de copas em tons de verde com sombras entre elas;
// - paredões de calcário úmido em camadas, escuros de umidade, com musgo e plantas nos degraus;
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

void fragment() {
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
	chao *= 0.85 + 0.3 * texture(ruido_fino, p.xz / 2.5).r * bem_perto;
	// De longe: dossel (o chão some embaixo das copas)
	float c = copas(p.xz / 14.0);
	vec3 dossel = mix(cor_dossel_claro, cor_dossel, smoothstep(0.15, 0.75, c));
	dossel = mix(dossel, cor_dossel_claro * 1.15, smoothstep(0.55, 0.85, n_grande) * 0.4);
	dossel *= 0.85 + 0.25 * nm;
	float longe = smoothstep(220.0, 900.0, dist);
	chao = mix(chao, dossel, max(longe, 0.0));

	// ---- Paredões de calcário úmido em camadas, com musgo nos degraus
	float hh = h + (n_grande - 0.5) * 30.0;
	float id_camada = floor(hh / 9.0);
	float u = fract(hh / 9.0);
	vec3 rocha = mix(cor_rocha, cor_rocha_escura, hash(id_camada * 1.7) * 0.7 + 0.15);
	rocha *= 0.9 + 0.2 * ruido_parede(ruido_fino, p, nw, 140.0);
	float junta = smoothstep(0.1, 0.0, u) + smoothstep(0.93, 1.0, u) * 0.6;
	rocha *= 1.0 - 0.3 * junta;
	float along = (p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001);
	float escorre = texture(ruido_fino, vec2(along / 6.0, h / 500.0)).r;
	rocha = mix(rocha, rocha * vec3(0.55, 0.58, 0.5), smoothstep(0.55, 0.8, escorre) * 0.6);
	float musgo_r = smoothstep(0.62, 0.92, u) + smoothstep(0.55, 0.8, ruido_parede(ruido, p, nw, 40.0)) * 0.5;
	rocha = mix(rocha, cor_musgo * 1.1, clamp(musgo_r, 0.0, 1.0) * 0.75);
	rocha *= 0.9 + (ruido_parede(ruido_fino, p, nw, 2.0) - 0.5) * 0.2 * bem_perto;

	// ---- Margem do rio
	vec2 uv_m = (p.xz + meio_mascara) / (2.0 * meio_mascara);
	float margem = texture(mascara_rio, uv_m).r;
	vec3 beira = mix(cor_capim * (0.8 + 0.4 * nf), cor_barro, smoothstep(0.75, 0.95, margem));
	chao = mix(chao, beira, smoothstep(0.25, 0.5, margem + (nf - 0.5) * 0.15) * (1.0 - longe * 0.7));
	float umido = smoothstep(nivel_agua + 2.5, nivel_agua + 0.2, h);

	vec3 cor = mix(chao, rocha, parede);
	cor *= 1.0 - 0.45 * umido;

	vec3 nn = nw;
	if (perto > 0.01) {
		float e = 1.0;
		float b0 = ruido_parede(ruido_fino, p, nw, 6.0);
		float bx = ruido_parede(ruido_fino, p + vec3(e, 0.0, e), nw, 6.0);
		float by = ruido_parede(ruido_fino, p + vec3(0.0, e, 0.0), nw, 6.0);
		vec3 lado = normalize(vec3(-nw.z, 0.0, nw.x) + vec3(0.0001));
		nn += (-(bx - b0) * lado - (by - b0) * vec3(0.0, 1.0, 0.0)) * 1.6 * parede * perto;
		nn.y += (0.25 * smoothstep(0.55, 0.95, u) - 0.3 * junta) * parede * perto;
		// Dossel de longe com relevo (as copas "estufam")
		nn.xz += vec2(dFdx(c), dFdy(c)) * 0.0;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
	ALBEDO = cor;
	ROUGHNESS = mix(0.95, 0.35, umido * 0.8 + parede * 0.15);
	SPECULAR = mix(0.25, 0.5, umido);
}
