shader_type spatial;
// Blocos de gelo do esmagador do Frozen Peak (EsmagadorGelo), pela arte do dono em
// assets/frozen/extruturas/esmagador.png: cada bloco é uma peça de verdade (caixa chanfrada), azul
// fundo no miolo e ciano aceso junto das quinas, com fraturas brancas presas lá dentro (andam com o
// olhar: raio refratado), nuvens leitosas, geada nas arestas e neve nas faces de cima.
// UV = 0..1 na face, UV2 = tamanho da face em metros (distância até a aresta), COLOR.r = sorteio do
// bloco, COLOR.g = quanto ele brilha. Tudo no espaço da peça: o bloco que desce leva o desenho junto.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_rasa : source_color = vec3(0.16, 0.62, 1.0);
uniform vec3 cor_funda : source_color = vec3(0.01, 0.09, 0.38);
uniform vec3 cor_luz : source_color = vec3(0.72, 0.95, 1.0);
uniform float brilho = 1.0;

varying vec3 pos_local;
varying vec3 normal_local;
varying vec3 olho_local;
varying float cima_mundo;

void vertex() {
	pos_local = VERTEX;
	normal_local = NORMAL;
	olho_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	cima_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	vec2 q = UV * UV2;
	vec2 a = min(q, UV2 - q);
	float borda = min(a.x, a.y);
	vec3 p = pos_local;
	vec3 n = normalize(normal_local);
	vec3 para_olho = olho_local - p;
	float dist = length(para_olho);
	vec3 olho = para_olho / dist;
	float perto = smoothstep(220.0, 30.0, dist);
	float ndv = clamp(dot(n, olho), 0.0, 1.0);
	vec3 r = refract(-olho, n, 0.75);
	float sorteio = COLOR.r;

	float n1 = texture(ruido, p.xy / 13.0 + p.z / 17.0 + sorteio).r;
	float n2 = texture(ruido, p.zy / 2.9 + p.x / 3.7).r;
	// Fraturas de dentro: linhas onde o ruído cruza o meio, em duas profundidades
	vec3 p1 = p + r * 0.35;
	vec3 p2 = p + r * 1.1;
	float f1 = texture(ruido, p1.xy / 4.3 + p1.z / 3.1 + sorteio * 3.0).r;
	float f2 = texture(ruido, p2.zy / 6.1 + p2.x / 4.7 + sorteio * 7.0).r;
	float m1 = smoothstep(0.42, 0.62, texture(ruido, p1.xz / 5.0 + p1.y / 6.3).r);
	float racha = (1.0 - smoothstep(0.0, 0.035, abs(f1 - 0.5))) * m1;
	float racha_funda = (1.0 - smoothstep(0.0, 0.08, abs(f2 - 0.5))) * 0.6;
	float leite = smoothstep(0.5, 0.85, texture(ruido, p2.xy / 3.3 + p2.z / 2.7).r);

	float tom = clamp(0.08 + sorteio * 0.42 + (n1 - 0.5) * 0.8 + (n2 - 0.5) * 0.3, 0.0, 1.0);
	tom = tom * tom * (3.0 - 2.0 * tom);
	vec3 cor = mix(cor_funda, cor_rasa, tom);
	// A luz de dentro escapa pelas quinas do bloco
	float quina = exp(-borda / 0.22);
	cor = mix(cor, cor_luz, quina * 0.45);
	cor = mix(cor, cor_rasa * 1.2 + 0.06, racha_funda * 0.6);
	cor = mix(cor, vec3(0.8, 0.95, 1.0), racha * 0.45);
	cor = mix(cor, vec3(0.6, 0.85, 0.98), leite * 0.12);
	float bolha = step(0.975, texture(ruido, (p.xy + r.xy * 0.5) * 1.4 + p.z * 0.8).r) * perto;
	cor = mix(cor, vec3(0.95, 1.0, 1.0), bolha * 0.6);
	// Geada nas arestas
	float geada = (1.0 - smoothstep(0.0, 0.02 + 0.05 * n2, borda)) * (0.3 + 0.7 * n2);
	cor = mix(cor, vec3(0.85, 0.95, 1.0), geada * 0.5);
	float fres = pow(1.0 - ndv, 3.0);
	cor = mix(cor, cor_rasa * 1.3, fres * 0.3);

	float luz = brilho * COLOR.g;
	vec3 emis = cor_rasa * luz * (0.05 + 0.22 * tom * tom + 0.75 * quina + 0.3 * racha_funda)
		+ cor_luz * luz * (0.5 * racha + 0.35 * fres);
	float rug = mix(0.05, 0.55, max(geada, racha * 0.6));
	// Neve assentada nas faces de cima
	float cima = smoothstep(0.86, 0.97, cima_mundo + (n2 - 0.5) * 0.12);
	cor = mix(cor, vec3(0.94, 0.97, 1.0) * (0.9 + 0.12 * n2), cima);
	rug = mix(rug, 0.88, cima);
	emis *= 1.0 - cima;
	// Relevo: superfície ondulada de gelo cortado (normal pela derivada da altura)
	float alt = texture(ruido, p.xy / 2.6 + p.z / 3.3).r * 0.8 + n2 * 0.25 - racha * 0.3;
	vec3 nv = normalize(NORMAL);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, nv);
	vec3 r2 = cross(nv, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(alt) * r1 + dFdy(alt) * r2);
	NORMAL = normalize(abs(det) * nv - 0.035 * (1.0 - cima) * grad);
	ALBEDO = cor;
	ROUGHNESS = rug;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	CLEARCOAT = (1.0 - cima) * 0.7;
	CLEARCOAT_ROUGHNESS = 0.04;
	BACKLIGHT = cor_rasa * 0.4 * (1.0 - cima);
	EMISSION = emis;
}
