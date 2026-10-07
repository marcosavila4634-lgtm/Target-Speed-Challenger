shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Casca da árvore seca gigante (ArvoreSeca, Serpent's Climb). Tudo procedural, no UV da malha
// (x = em volta do galho, y = ao longo; 1 unidade = ArvoreSeca.PASSO m):
// - placas de casca compridas separadas por fissuras fundas, fibras e trincas em relevo (mapa de normais
//   calculado aqui da própria altura);
// - partes descascadas mostrando a madeira morta, desbotada e cinza, com veios e rachas;
// - líquen (cinza-esverdeado e manchas laranja) nas placas, musgo onde a casca olha para cima e no pé;
// - pontas quebradas (COLOR.g = 1): madeira lascada clara.
// COLOR.r = sombra dos sulcos da malha, COLOR.b = sorteio por galho (varia o tom). UV2.x = voltas inteiras
// de UV em volta do galho: o ruído em x repete nesse período (sem emenda na costura do tubo).

uniform float chao_y = 0.0;          // pé da árvore no mundo: musgo e casca molhada perto do chão
uniform float relevo = 1.6;          // força do mapa de normais

varying vec3 w_pos;
varying vec3 w_nrm;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, hash21(p + n + 17.1));
}

// Ruído de valor que repete em x a cada `px` (inteiro)
float ruido_p(vec2 p, float px) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, px);
	float x1 = mod(i.x + 1.0, px);
	return mix(mix(hash21(vec2(x0, i.y)), hash21(vec2(x1, i.y)), u.x),
		mix(hash21(vec2(x0, i.y + 1.0)), hash21(vec2(x1, i.y + 1.0)), u.x), u.y);
}

float ruido(vec2 p) {
	return ruido_p(p, 65536.0);
}

float fbm_p(vec2 p, float px) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += a * ruido_p(p, px);
		p = p * 2.0 + vec2(0.0, 11.7);
		px *= 2.0;
		a *= 0.5;
	}
	return s;
}

float fbm(vec2 p) {
	return fbm_p(p, 65536.0);
}

// Voronoi: x = distância até a borda da célula, y = sorteio da célula
vec2 voronoi(vec2 p, float px) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 c = vec2(mod(i.x + g.x, px), i.y + g.y);
			vec2 o = hash22(c);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = c;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec2(sqrt(d2) - sqrt(d1), hash21(id));
}

// Altura da casca no ponto (0 = fundo da fissura, ~1 = topo da placa) e, em `info`:
// x = máscara descascado, y = sorteio da placa, z = fissura
float casca(vec2 uv, float sorteio, float per, out vec3 info) {
	vec2 w = vec2(fbm_p(uv * vec2(2.0, 0.7) + vec2(0.0, sorteio * 7.0), per * 2.0), fbm_p(uv * vec2(2.0, 0.7) + vec2(0.0, 5.3), per * 2.0)) - 0.5;
	vec2 p = uv * vec2(6.0, 1.5) + w * vec2(0.9, 0.5);
	vec2 v = voronoi(p, per * 6.0);
	float fiss = 1.0 - smoothstep(0.02, 0.2, v.x);
	float placa = smoothstep(0.0, 0.32, v.x) * (0.75 + 0.25 * v.y);
	// fibras ao longo do galho e trincas atravessadas nas placas
	float fibra = ruido_p(vec2(uv.x * 70.0, uv.y * 5.0), per * 70.0) * 0.18 + ruido_p(vec2(uv.x * 160.0, uv.y * 11.0), per * 160.0) * 0.08;
	float trinca = smoothstep(0.82, 0.9, ruido_p(vec2(uv.x * 9.0, uv.y * 34.0 + v.y * 13.0), per * 9.0)) * placa;
	float h = placa * 0.8 + fibra * placa - trinca * 0.35;
	// Descascado: manchas grandes onde a casca caiu (borda com degrau) e a madeira fica lisa com veios
	float m = fbm_p(uv * vec2(1.0, 0.32) + vec2(0.0, sorteio * 3.1), per);
	float desc = smoothstep(0.62, 0.66, m);
	float veio = ruido_p(vec2(uv.x * 46.0 + fbm_p(uv * vec2(3.0, 0.4), per * 3.0) * 6.0, uv.y * 2.2), per * 46.0);
	float racha = smoothstep(0.88, 0.95, ruido_p(vec2(uv.x * 14.0, uv.y * 1.2), per * 14.0));
	float h_madeira = 0.3 + veio * 0.07 - racha * 0.25;
	info = vec3(desc, v.y, fiss);
	return mix(h, h_madeira, desc);
}

vec3 lin(vec3 c) {
	return pow(c, vec3(2.2));
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float sorteio = COLOR.b;
	float per = max(UV2.x, 1.0);
	vec2 uv = UV;
	vec3 info;
	float h = casca(uv, sorteio, per, info);
	vec3 i2;
	float e = 0.004;
	float hx = casca(uv + vec2(e, 0.0), sorteio, per, i2);
	float hy = casca(uv + vec2(0.0, e * 3.0), sorteio, per, i2);
	vec2 dh = vec2(hx - h, (hy - h) / 3.0) / e;
	float desc = info.x;

	// Casca: cinza-marrom de árvore morta, placas de tons diferentes, fundo das fissuras escuro
	vec3 topo = mix(vec3(0.36, 0.31, 0.26), vec3(0.47, 0.43, 0.38), info.y);
	topo = mix(topo, vec3(0.29, 0.22, 0.16), sorteio * 0.5);
	vec3 cor = mix(vec3(0.06, 0.045, 0.035), topo, smoothstep(0.05, 0.55, h));
	// Madeira descascada: desbotada pelo sol, cinza-prateada, veios mais escuros, rachas pretas
	vec3 madeira = mix(vec3(0.4, 0.37, 0.33), vec3(0.54, 0.5, 0.45), ruido_p(uv * vec2(30.0, 1.5), per * 30.0));
	madeira *= mix(0.25, 1.0, smoothstep(0.05, 0.28, h));
	cor = mix(cor, madeira, desc);
	// Borda da casca que sobrou em volta do descascado: escura e saliente
	float borda = smoothstep(0.52, 0.62, fbm_p(uv * vec2(1.0, 0.32) + vec2(0.0, sorteio * 3.1), per)) * (1.0 - desc);
	cor *= 1.0 - borda * 0.35;

	// Líquen em placas: cinza-esverdeado em manchas e pontinhos laranja (só na casca)
	float liq = smoothstep(0.62, 0.7, fbm_p(uv * vec2(4.0, 2.2) + vec2(0.0, 31.0), per * 4.0)) * smoothstep(0.35, 0.6, h) * (1.0 - desc);
	cor = mix(cor, vec3(0.56, 0.6, 0.47) * (0.85 + 0.3 * ruido_p(uv * 90.0, per * 90.0)), liq * 0.85);
	float laranja = smoothstep(0.86, 0.9, ruido_p(uv * vec2(22.0, 9.0) + vec2(0.0, 7.0), per * 22.0)) * smoothstep(0.4, 0.7, h) * (1.0 - desc);
	cor = mix(cor, vec3(0.72, 0.42, 0.14), laranja * 0.8);

	// Musgo: onde a superfície olha para cima e no pé da árvore (o pé também escurece de umidade)
	float alto_chao = w_pos.y - chao_y;
	float pe = 1.0 - smoothstep(0.5, 4.5, alto_chao);
	float m_cima = smoothstep(0.35, 0.85, w_nrm.y);
	float m_ruido = fbm(w_pos.xz * 0.9 + w_pos.y * 0.3);
	float musgo = clamp(smoothstep(0.5, 0.7, m_ruido + m_cima * 0.3 + pe * 0.15) * max(m_cima, pe * 0.7), 0.0, 1.0);
	musgo *= mix(1.0, 0.7, desc);
	vec3 cor_musgo = mix(vec3(0.13, 0.17, 0.06), vec3(0.24, 0.28, 0.1), ruido(w_pos.xz * 6.0 + w_pos.y));
	cor *= 1.0 - pe * 0.3;
	cor = mix(cor, cor_musgo, musgo);

	// Ponta quebrada: madeira lascada clara por dentro, fibrosa
	float lasca = COLOR.g;
	vec3 cor_lasca = mix(vec3(0.62, 0.5, 0.36), vec3(0.75, 0.66, 0.52), ruido(w_pos.xz * 12.0 + w_pos.y * 5.0));
	cor_lasca *= 0.75 + 0.25 * ruido(vec2(dot(w_pos, vec3(1.0, 0.3, 0.7)) * 40.0, w_pos.y * 3.0));
	cor = mix(cor, cor_lasca, lasca);

	// (alguns pixels soltos davam NaN e o glow virava bolas brancas na árvore)
	cor = any(isnan(cor)) || any(isinf(cor)) ? vec3(0.3, 0.26, 0.22) : clamp(cor, vec3(0.0), vec3(1.0));
	ALBEDO = lin(cor);
	ROUGHNESS = mix(0.88, 1.0, musgo);
	SPECULAR = 0.3;
	float ao_sulco = mix(0.3, 1.0, smoothstep(0.0, 0.45, h));
	AO = ao_sulco * COLOR.r;
	AO_LIGHT_AFFECT = 0.6;
	float k = relevo * (1.0 - musgo * 0.7) * (1.0 - lasca);
	NORMAL_MAP = normalize(vec3(-dh.x * k * 0.06, -dh.y * k * 0.06, 1.0)) * 0.5 + 0.5;
}
