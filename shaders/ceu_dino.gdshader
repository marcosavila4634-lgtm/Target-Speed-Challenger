shader_type sky;
// Céu do Extinction Day: dia (azul com nuvens), noite (estrelas, lua e aurora boreal) e apocalipse
// (céu vermelho de fumaça iluminado por baixo). O meteoro é desenhado aqui: cabeça escura de rocha com
// a borda incandescente, a coma de fogo em volta e a cauda — fogo branco-amarelo junto da cabeça,
// laranja e vermelho, e depois um rastro de fumaça cinza que se desfaz. Ele cresce de etapa em etapa.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float noite : hint_range(0.0, 1.0) = 0.0;
uniform float aurora : hint_range(0.0, 1.0) = 0.0;
uniform float apocalipse : hint_range(0.0, 1.0) = 0.0;
uniform float cobertura : hint_range(0.0, 1.0) = 0.45;
uniform vec3 cor_zenite : source_color = vec3(0.12, 0.28, 0.62);
uniform vec3 cor_meio : source_color = vec3(0.42, 0.6, 0.85);
uniform vec3 cor_horizonte : source_color = vec3(0.86, 0.88, 0.85);
uniform vec3 cor_chao : source_color = vec3(0.3, 0.33, 0.25);
// Meteoro
uniform vec3 met_dir = vec3(0.6, 0.12, -0.78);
uniform vec3 met_cauda = vec3(0.0, 1.0, 0.0);   // sentido da cauda no céu (tangente)
uniform float met_raio = 0.006;                  // raio angular da cabeça (rad)
uniform float met_comp = 0.08;                   // comprimento característico do fogo (rad)
uniform float met_brilho = 1.0;

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * texture(ruido, p).r;
		p = p * 2.03 + vec2(0.17, 0.31);
		a *= 0.5;
	}
	return v;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 estrelas(vec3 d) {
	vec3 q = d * 260.0;
	vec3 c = floor(q);
	float h = hash3(c);
	if (h < 0.965) {
		return vec3(0.0);
	}
	vec3 f = fract(q) - 0.5;
	float r = length(f);
	float brilho = (h - 0.965) / 0.035;
	float pisca = 0.7 + 0.3 * sin(TIME * (1.5 + h * 4.0) + h * 40.0);
	vec3 tom = mix(vec3(0.8, 0.85, 1.0), vec3(1.0, 0.9, 0.75), fract(h * 91.0));
	return tom * smoothstep(0.35, 0.0, r) * brilho * pisca * 2.2;
}

// Aurora boreal: cortinas verticais que ondulam devagar, verde embaixo e roxo no alto
vec3 cortinas(vec3 d) {
	if (d.y < 0.02) {
		return vec3(0.0);
	}
	vec3 soma = vec3(0.0);
	for (int k = 0; k < 3; k++) {
		float h = 0.22 + float(k) * 0.06;
		vec2 p = d.xz / (d.y + h);
		float t = TIME * (0.008 + float(k) * 0.003);
		float onda = fbm(vec2(p.x * 0.05 + t, p.y * 0.02 + float(k) * 3.7));
		float faixa = 1.0 - abs(p.y * 0.06 + (onda - 0.5) * 3.2 - 0.6 + float(k) * 0.35);
		faixa = smoothstep(0.55, 1.0, faixa);
		float raios = 0.55 + 0.45 * texture(ruido, vec2(p.x * 0.35 + t * 3.0, 0.3 + float(k))).r;
		float alt = smoothstep(0.02, 0.12, d.y) * smoothstep(0.75, 0.25, d.y);
		vec3 verde = vec3(0.15, 1.0, 0.45);
		vec3 roxo = vec3(0.55, 0.2, 0.95);
		vec3 cor = mix(verde, roxo, smoothstep(0.12, 0.5, d.y) * 0.8 + float(k) * 0.12);
		soma += cor * faixa * raios * alt * (0.75 - float(k) * 0.15);
	}
	return soma;
}

vec3 meteoro(vec3 d, inout float fumaca) {
	vec3 m = normalize(met_dir);
	float cm = dot(d, m);
	if (cm < 0.0) {
		return vec3(0.0);
	}
	float ang = acos(clamp(cm, -1.0, 1.0));
	vec3 v = d - m * cm;
	vec3 tg = normalize(met_cauda - m * dot(met_cauda, m));
	float ao_longo = dot(v, tg);
	float lado = length(v - tg * ao_longo);
	vec3 cor = vec3(0.0);
	// Cauda: fogo que se abre e esfria, depois fumaça
	if (ao_longo > 0.0) {
		float larg = met_raio * (0.95 + ao_longo / max(met_raio, 0.0001) * 0.09);
		float turb = texture(ruido, vec2(ao_longo / met_comp * 1.6 - TIME * 0.35, lado / larg * 0.4)).r;
		float perfil = exp(-pow(lado / (larg * (0.8 + 0.5 * turb)), 2.0));
		float x = ao_longo / met_comp;
		vec3 fogo = mix(vec3(1.0, 0.95, 0.75), vec3(1.0, 0.55, 0.12), smoothstep(0.0, 0.5, x));
		fogo = mix(fogo, vec3(0.7, 0.15, 0.04), smoothstep(0.5, 1.6, x));
		cor += fogo * perfil * exp(-x * 1.4) * (0.7 + 0.6 * turb) * 3.5;
		// Fumaça: mais larga e comprida que o fogo, só escurece o céu atrás
		float larg_f = larg * 1.8;
		float pf = exp(-pow(lado / (larg_f * (0.7 + 0.6 * turb)), 2.0));
		fumaca = max(fumaca, pf * smoothstep(0.2, 1.0, x) * exp(-x * 0.35) * 0.75);
	}
	// Coma de fogo em volta da cabeça
	float coma = exp(-max(ang - met_raio * 0.9, 0.0) / (met_raio * 1.3));
	cor += vec3(1.0, 0.62, 0.22) * coma * 2.2;
	// Cabeça: rocha escura com a borda em brasa
	float cabeca = smoothstep(met_raio, met_raio * 0.9, ang);
	vec2 uvc = vec2(dot(v, tg), dot(v, cross(m, tg))) / max(met_raio, 0.0001);
	float rocha = texture(ruido, uvc * 0.6 + vec2(TIME * 0.01, 0.0)).r;
	vec3 cor_cab = mix(vec3(0.07, 0.05, 0.045), vec3(1.0, 0.45, 0.1) * 2.5, smoothstep(0.55, 1.0, ang / met_raio) + smoothstep(0.7, 0.9, rocha) * 0.6);
	return mix(cor, cor_cab, cabeca) * met_brilho;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sol = normalize(LIGHT0_DIRECTION);
	float cos_sol = dot(d, sol);
	float y = max(d.y, 0.0);

	// Dia
	vec3 dia = mix(cor_horizonte, cor_meio, smoothstep(0.0, 0.2, y));
	dia = mix(dia, cor_zenite, smoothstep(0.15, 0.8, y));
	dia += LIGHT0_COLOR * (pow(max(cos_sol, 0.0), 8.0) * 0.25 + pow(max(cos_sol, 0.0), 120.0) * 0.8) * LIGHT0_ENERGY * 0.3 * (1.0 - noite);
	// Noite: azul profundo, horizonte um pouco mais claro
	vec3 ceu_noite = mix(vec3(0.03, 0.05, 0.1), vec3(0.008, 0.012, 0.03), smoothstep(0.0, 0.6, y));
	vec3 cor = mix(dia, ceu_noite, noite);
	// Apocalipse: céu vermelho-escuro carregado
	vec3 fim = mix(vec3(0.75, 0.28, 0.08), vec3(0.18, 0.05, 0.03), smoothstep(0.0, 0.55, y));
	cor = mix(cor, fim, apocalipse);

	if (d.y > 0.0) {
		cor += estrelas(d) * noite * (1.0 - apocalipse) * smoothstep(0.02, 0.15, d.y);
		cor += cortinas(d) * aurora * 1.6;
		// Nuvens: brancas de dia; à noite escuras e azuladas; no apocalipse fumaça grossa acesa por baixo
		vec2 p = d.xz / (d.y + 0.08);
		float t = TIME * 0.004;
		float n1 = fbm(p * 0.09 + vec2(t, t * 0.4));
		float n2 = fbm(p * 0.035 - vec2(t * 0.6, 0.0) + 3.1);
		float cob = mix(cobertura, 0.95, apocalipse);
		float dens = smoothstep(1.0 - cob, 1.05 - cob * 0.55, n1 * 0.65 + n2 * 0.55) * smoothstep(0.0, 0.1, d.y);
		float miolo = smoothstep(0.55, 0.95, n1 * 0.6 + n2 * 0.6);
		vec3 nuvem_dia = mix(vec3(1.0, 0.98, 0.95), vec3(0.55, 0.6, 0.7), miolo * 0.7);
		nuvem_dia += LIGHT0_COLOR * pow(max(cos_sol, 0.0), 6.0) * (1.0 - miolo) * 0.6;
		vec3 nuvem_noite = mix(vec3(0.05, 0.06, 0.09), vec3(0.015, 0.02, 0.03), miolo);
		vec3 nuvem_fim = mix(vec3(0.95, 0.35, 0.08), vec3(0.12, 0.06, 0.05), smoothstep(0.2, 0.9, miolo + y * 0.6));
		vec3 cn = mix(nuvem_dia, nuvem_noite, noite);
		cn = mix(cn, nuvem_fim, apocalipse);
		cor = mix(cor, cn, dens * mix(0.85, 0.6, noite));
		// Disco do sol (de dia) ou da lua (à noite)
		float disco = smoothstep(0.9995, 0.99965, cos_sol);
		cor += LIGHT0_COLOR * disco * mix(6.0, 1.8, noite) * (1.0 - apocalipse);
		// Meteoro (por cima de tudo, menos da própria fumaça)
		float fumaca = 0.0;
		vec3 met = meteoro(d, fumaca);
		cor = mix(cor, mix(vec3(0.16, 0.15, 0.15), vec3(0.06, 0.05, 0.05), noite), fumaca * (1.0 - apocalipse * 0.5));
		cor += met;
	} else {
		cor = mix(cor, mix(cor_chao, vec3(0.02, 0.025, 0.03), noite), smoothstep(0.0, -0.25, d.y));
	}
	COLOR = cor;
}
