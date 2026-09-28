shader_type spatial;
// Placa de reforço do teto onde o paraquedas se prende (malha em paraquedas.gd).
// UV = posição em metros no plano da placa (x = envergadura, y = frente/trás);
// UV2.x = distância até a borda (m), UV2.y = distância até o centro do olhal mais próximo (m);
// COLOR.g = 1 quando a borda mais próxima é a das pontas (rebites contados ao longo de y).
// Centro de fibra de carbono com verniz, moldura de titânio escovado rebitada, filete e setas
// na cor da equipe apontando para os olhais usinados, e desgaste leve.

uniform vec3 cor_equipe : source_color = vec3(0.9, 0.2, 0.1);
uniform float meia_largura = 0.5;      // x do centro dos olhais
uniform float moldura = 0.055;         // largura da moldura de titânio
uniform float raio_olhal = 0.075;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV;
	float borda = UV2.x;
	float d_olhal = UV2.y;
	float aa = fwidth(borda) + 0.0005;

	// ---- Fibra de carbono (sarja 2x2) com verniz
	vec2 q = p * 90.0;
	vec2 c = floor(q);
	float fio = mod(c.x + c.y, 4.0) < 2.0 ? 1.0 : 0.0;       // qual direção do fio aparece
	vec2 f = fract(q);
	float brilho_fio = fio > 0.5 ? sin(f.y * PI) : sin(f.x * PI);
	vec3 cor = mix(vec3(0.028, 0.03, 0.034), vec3(0.075, 0.078, 0.085), brilho_fio * 0.8);
	float rug = 0.22;
	float met = 0.25;
	float verniz = 1.0;
	vec3 n_det = vec3((fio > 0.5 ? 0.0 : cos(f.x * PI)) * 0.25, (fio > 0.5 ? cos(f.y * PI) : 0.0) * 0.25, 1.0);

	// ---- Setas na cor da equipe apontando para os olhais
	float ax = abs(p.x);
	float faixa_setas = step(meia_largura * 0.38, ax) * step(ax, meia_largura * 0.68) * step(abs(p.y), 0.07);
	float seta = step(fract((ax - abs(p.y) * 0.9) / 0.055), 0.38) * faixa_setas;
	cor = mix(cor, cor_equipe * 0.85, seta);
	rug = mix(rug, 0.3, seta);

	// ---- Anel da equipe em volta dos olhais
	float anel = smoothstep(raio_olhal + 0.004, raio_olhal + 0.004 + aa, d_olhal) * (1.0 - smoothstep(raio_olhal + 0.014, raio_olhal + 0.014 + aa, d_olhal));
	cor = mix(cor, cor_equipe, anel);

	// ---- Moldura de titânio escovado
	float na_moldura = 1.0 - smoothstep(moldura - aa, moldura + aa, borda);
	float escova = ruido(vec2(p.x * 3.0 + p.y * 3.0, (COLOR.g > 0.5 ? p.x : p.y) * 900.0));
	vec3 titanio = vec3(0.26, 0.265, 0.28) * (0.85 + 0.3 * escova);
	cor = mix(cor, titanio, na_moldura);
	rug = mix(rug, 0.3 + 0.15 * escova, na_moldura);
	met = mix(met, 0.95, na_moldura);
	verniz = mix(verniz, 0.0, na_moldura);
	n_det = mix(n_det, vec3(0.0, 0.0, 1.0), na_moldura);

	// Rebites ao longo da moldura
	float ao_longo = COLOR.g > 0.5 ? p.y : p.x;
	vec2 r = vec2((fract(ao_longo / 0.075) - 0.5) * 0.075, borda - moldura * 0.5);
	float d_reb = length(r);
	float rebite = (1.0 - smoothstep(0.0075, 0.0075 + aa, d_reb)) * na_moldura;
	cor = mix(cor, vec3(0.5, 0.5, 0.52) * (0.8 + 0.4 * (0.5 - r.y / 0.015)), rebite);
	rug = mix(rug, 0.2, rebite);
	n_det = mix(n_det, normalize(vec3(r / 0.0075 * 0.7, 1.0)), rebite);

	// Filete na cor da equipe separando moldura e carbono (leve brilho)
	float filete = smoothstep(moldura, moldura + aa, borda) * (1.0 - smoothstep(moldura + 0.007, moldura + 0.007 + aa, borda));
	cor = mix(cor, cor_equipe, filete);
	rug = mix(rug, 0.35, filete);
	met = mix(met, 0.3, filete);
	EMISSION = cor_equipe * filete * 0.6;

	// Chanfro externo mais escuro (sombra de contato com a lataria)
	cor *= mix(0.55, 1.0, smoothstep(0.0, 0.012, borda));

	// ---- Olhais de aço usinado (anéis de torno concêntricos)
	float no_olhal = 1.0 - smoothstep(raio_olhal - aa, raio_olhal + aa, d_olhal);
	float torno = 0.5 + 0.5 * sin(d_olhal * 900.0);
	vec3 aco = vec3(0.55, 0.56, 0.58) * (0.8 + 0.25 * torno);
	aco *= mix(0.35, 1.0, smoothstep(0.03, 0.036, d_olhal));   // furo escuro no centro
	cor = mix(cor, aco, no_olhal);
	rug = mix(rug, 0.18 + 0.1 * torno, no_olhal);
	met = mix(met, 1.0, no_olhal);
	verniz = mix(verniz, 0.0, no_olhal);
	n_det = mix(n_det, vec3(0.0, 0.0, 1.0), no_olhal);

	// ---- Desgaste: arranhões claros e poeira nas frestas
	float risco = smoothstep(0.93, 0.99, ruido(vec2(p.x * 8.0 + p.y * 30.0, p.y * 6.0) * 4.0));
	cor = mix(cor, vec3(0.45, 0.45, 0.47), risco * 0.35 * (1.0 - no_olhal));
	float poeira = ruido(p * 14.0) * (1.0 - smoothstep(0.0, 0.03, borda)) * 0.5;
	cor = mix(cor, vec3(0.45, 0.36, 0.28), poeira);
	rug = mix(rug, 0.8, poeira);

	ALBEDO = cor;
	ROUGHNESS = rug;
	METALLIC = met;
	CLEARCOAT = verniz;
	CLEARCOAT_ROUGHNESS = 0.08;
	NORMAL_MAP = normalize(n_det) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
