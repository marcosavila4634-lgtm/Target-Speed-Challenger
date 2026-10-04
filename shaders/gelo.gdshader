shader_type spatial;
// Estruturas do Frozen Peak (coordenadas do mundo):
// modo 0 = gelo de geleira / estalactite (agulhas, seracs, lascas, pingentes): estrias verticais de água
//          que escorreu e congelou (seguem o eixo da peça, mesmo inclinada), ranhuras finas, ondas de
//          crescimento na horizontal, rachaduras cheias de geada, bolhas de ar presas, miolo leitoso,
//          pé com geada e ponta mais transparente; cada peça sorteia o tom (não ficam todas iguais);
// modo 1 = blocos de gelo cortados (fortalezas, muralhas): fiadas com juntas de neve, marcas de serra,
//          bolhas e juntas fundas no relevo;
// modo 2 = rocha escura em camadas;
// modo 3 = concreto com geada (pilares da estrada);
// modo 4 = neve batida.
// Em todos, as faces viradas para cima acumulam neve (uniform neve) e a normal ganha relevo pela
// derivada da altura de cada modo. Todas as leituras de textura ficam FORA dos if (RX 5700 XT: texture()
// dentro de ramificação derrubou o driver).

uniform int modo = 0;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_gelo : source_color = vec3(0.34, 0.66, 0.86);
uniform vec3 cor_gelo_fundo : source_color = vec3(0.06, 0.26, 0.48);
uniform vec3 cor_neve : source_color = vec3(0.93, 0.96, 1.0);
uniform vec3 cor_rocha : source_color = vec3(0.3, 0.29, 0.31);
uniform float fiada = 1.6;        // altura do bloco (modo 1)
uniform float bloco = 3.2;        // comprimento do bloco (modo 1)
uniform float neve = 1.0;         // quanto de neve nas faces de cima (0 = nenhuma)
uniform float brilho = 0.18;      // luz "de dentro" do gelo
uniform float relevo = 1.0;       // força do relevo na normal
uniform float sem_pe = 0.0;       // 1 = malha sem "pé e ponta" (maciços e blocos em coordenadas do mundo): sem geada de pé

varying vec3 pos_mundo;
varying vec3 normal_mundo;
varying vec3 eixo_mundo;          // "cima" da peça: as estrias escorrem ao longo dele
varying float semente;            // sorteio por peça (posição da instância)
varying float alt_rel;            // altura na peça, 0 = pé, 1 = ponta (malhas de altura 1 centradas)
varying float luz_vert;           // COLOR.r das estalactites: fundo das caneluras escuro (outras malhas: 1)

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Agulhas e seracs são malhas muito esticadas por instância (escala não uniforme): a normal certa
	// é a da inversa transposta (a do motor, nesse caso, sai torta e a agulha virava "neve")
	normal_mundo = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);
	eixo_mundo = normalize(MODEL_MATRIX[1].xyz);
	vec3 o = MODEL_MATRIX[3].xyz;
	semente = fract(sin(dot(floor(o * 3.0), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	alt_rel = mix(clamp(VERTEX.y + 0.5, 0.0, 1.0), 0.6, sem_pe);
	luz_vert = COLOR.r;
}

float h11(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

float tri(vec3 p, vec3 n, float escala) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return texture(ruido, p.zy / escala).r * w.x + texture(ruido, p.xz / escala).r * w.y + texture(ruido, p.xy / escala).r * w.z;
}

// Ruído esticado ao longo do eixo (estrias): `atravessa` e `desce` = metros por volta da textura (o
// ruído tem ~25 ciclos por volta: o traço sai com 1/25 disso) na volta e ao longo do eixo;
// duas projeções em volta do eixo misturadas pela normal (sem costura).
float estria(vec3 p, vec3 nw, vec3 e, vec3 t1, vec3 t2, float atravessa, float desce, float desloc) {
	float v = dot(p, e) / desce + desloc;
	float a = texture(ruido, vec2(dot(p, t2) / atravessa, v)).r;
	float b = texture(ruido, vec2(dot(p, t1) / atravessa + 0.37, v + 0.21)).r;
	float wa = dot(nw, t1);
	float wb = dot(nw, t2);
	wa *= wa;
	wb *= wb;
	return (a * wa + b * wb) / max(wa + wb, 0.0001);
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 nw = normalize(normal_mundo);
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float dist = length(p - CAMERA_POSITION_WORLD);
	float perto = smoothstep(260.0, 20.0, dist);
	float bem_perto = smoothstep(140.0, 15.0, dist);
	// Referencial da peça
	vec3 e = normalize(eixo_mundo);
	vec3 ref = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), step(0.95, abs(e.y)));
	vec3 t1 = normalize(cross(e, ref));
	vec3 t2 = cross(e, t1);
	float ao_longo = dot(p, e);
	// Leituras de textura (todas aqui, fora de ramificação)
	float n1 = tri(p, nw, 23.0);
	float n2 = tri(p, nw, 5.0);
	float n3 = tri(p, nw, 0.9);
	float e1 = estria(p, nw, e, t1, t2, 70.0, 900.0, semente * 7.0);       // escorridos largos (~2,5 m)
	float e2 = estria(p, nw, e, t1, t2, 14.0, 220.0, semente * 3.0 + 0.5);  // ranhuras finas (~0,5 m)
	float e3 = estria(p, nw, e, t1, t2, 3.0, 60.0, semente * 5.0 + 0.2);    // riscos de perto (~0,1 m)
	float mancha = texture(ruido, vec2(dot(p, t1) + dot(p, t2), ao_longo) / 320.0 + semente).r;
	float bolhas = texture(ruido, p.xz * 1.3 + p.y * 0.9).r;
	float bolhas2 = texture(ruido, p.zy * 0.45 + p.x * 0.3 + 0.61).r;
	float faisca_r = texture(ruido, p.xz * 1.7 + p.y).r;

	vec3 cor;
	float rug;
	float espec = 0.5;
	float verniz = 0.0;
	float atras = 0.0;
	float alt = 0.0;                  // altura para o relevo (0..1, em "metros de relevo" via relevo)
	vec3 emis = vec3(0.0);
	float borda = pow(1.0 - clamp(dot(nv, normalize(VIEW)), 0.0, 1.0), 2.5);
	// Coordenada ao longo da face vertical (para fiadas de blocos)
	float along = (p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001);
	if (modo == 0) {
		// Tom da peça: umas mais ciano e claras, outras azul-marinho, umas leitosas (gelo velho)
		vec3 rasa = mix(cor_gelo, vec3(0.42, 0.8, 0.95), semente * 0.6);
		vec3 funda = cor_gelo_fundo * (0.7 + 0.6 * fract(semente * 7.31));
		float leitosa = smoothstep(0.65, 1.0, fract(semente * 13.7));
		// Ondas de crescimento (anéis horizontais que a estalactite faz ao engrossar), tortas pelas estrias
		float onda = 0.5 + 0.5 * sin(ao_longo * (2.2 + semente * 1.4) + e1 * 9.0 + e2 * 3.0);
		float onda_m = smoothstep(0.35, 0.7, n2) * 0.8 + 0.2;
		// Rachaduras longas, cheias de geada branca (só parte delas aparece)
		float rach = (1.0 - smoothstep(0.0, 0.03, abs(e2 - 0.5))) * smoothstep(0.45, 0.7, mancha);
		float rach_fina = (1.0 - smoothstep(0.0, 0.05, abs(e3 - 0.5))) * smoothstep(0.55, 0.75, n2) * bem_perto;
		// Corpo do gelo: claro nas cristas dos escorridos, fundo e transparente nos sulcos
		float tom = clamp(0.2 + e1 * 0.8 + (mancha - 0.5) * 0.8 + (n1 - 0.5) * 0.12, 0.0, 1.0);
		tom = tom * tom * (3.0 - 2.0 * tom);
		cor = mix(funda, rasa, tom);
		// Fios de bolhas descendo junto com a água (estrias brancas)
		cor = mix(cor, vec3(0.8, 0.92, 1.0), smoothstep(0.66, 0.86, e2) * 0.4);
		cor = mix(cor, vec3(0.86, 0.95, 1.0), smoothstep(0.7, 0.9, e3) * 0.22 * bem_perto);
		// Nuvem leitosa de dentro
		cor = mix(cor, vec3(0.74, 0.86, 0.95), smoothstep(0.55, 0.85, mancha + (e1 - 0.5) * 0.4) * (0.15 + 0.4 * leitosa));
		cor *= 0.92 + 0.08 * mix(1.0, onda, onda_m * (0.4 + 0.6 * perto));
		cor = mix(cor, vec3(0.9, 0.97, 1.0), max(rach * 0.7, rach_fina * 0.45));
		// Bolhas presas
		float bolha = step(0.972, bolhas) * perto + step(0.985, bolhas2) * 0.6;
		cor = mix(cor, vec3(0.95, 1.0, 1.0), clamp(bolha, 0.0, 1.0) * 0.55);
		// Pé com geada (neve soprada grudada) e ponta mais clara e transparente
		float geada = (1.0 - smoothstep(0.0, 0.16 + 0.1 * semente, alt_rel + (n2 - 0.5) * 0.12)) * smoothstep(0.25, 0.55, n3 + n2 * 0.5);
		cor = mix(cor, cor_neve * 0.92, geada * 0.75);
		cor = mix(cor, rasa * 1.12, smoothstep(0.7, 1.0, alt_rel) * 0.25);
		cor *= 0.97 + 0.05 * n3 * bem_perto;
		// Fundo das caneluras: gelo grosso, azul-marinho, quase sem luz
		float sulco = 1.0 - luz_vert;
		cor = mix(cor, funda * 0.7, sulco * 0.7);
		rug = mix(0.04, 0.25, smoothstep(0.6, 0.9, e2)) + rach * 0.4 + geada * 0.6 + leitosa * 0.08;
		espec = 0.8;
		verniz = (1.0 - geada) * 0.8;
		atras = 1.0 - geada;
		emis = rasa * (brilho * (0.5 + 0.9 * (1.0 - tom)) + borda * 0.35) * (1.0 - geada);
		emis += vec3(0.6, 0.85, 1.0) * rach * 0.06;
		// Relevo: escorridos (largos e finos), ondas, sulco nas rachaduras, geada granulada
		alt = e1 * 0.7 + e2 * 0.3 * perto + e3 * 0.05 * bem_perto + onda * onda_m * 0.18 - rach * 0.35 + geada * n3 * 0.3;
	} else if (modo == 1) {
		float linha = floor(p.y / fiada);
		float u = fract(p.y / fiada);
		float desloc = h11(linha) * bloco;
		float v = fract((along + desloc) / bloco);
		float id = floor((along + desloc) / bloco) + linha * 17.0;
		float junta = max(smoothstep(0.06, 0.0, min(u, 1.0 - u)), smoothstep(0.03, 0.0, min(v, 1.0 - v)));
		junta *= step(abs(nw.y), 0.7);
		// Cada bloco de um tom; uns mais leitosos, outros cristalinos
		float sorte = h11(id);
		cor = mix(cor_gelo * 1.12, cor_gelo_fundo * 1.4, sorte * 0.55 + n1 * 0.3);
		float veio = 1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5));
		cor = mix(cor, vec3(0.86, 0.95, 1.0), veio * 0.3 * perto);
		// Marcas de serra: riscos paralelos, cada bloco num ângulo
		float ang = h11(id + 3.1) * 0.6 - 0.3;
		float serra = 0.5 + 0.5 * sin((u * fiada + v * bloco * ang) * 18.0 + e3 * 4.0);
		cor *= 0.93 + 0.07 * serra * bem_perto;
		cor = mix(cor, vec3(0.8, 0.9, 0.98), smoothstep(0.55, 0.9, bolhas2) * 0.25 * step(0.6, h11(id + 7.7)));
		float bolha = step(0.975, bolhas) * perto;
		cor = mix(cor, vec3(0.95, 1.0, 1.0), bolha * 0.5);
		// Miolo do bloco aceso, beiradas mais fundas
		float miolo = smoothstep(0.0, 0.3, min(min(u, 1.0 - u), min(v, 1.0 - v)));
		cor = mix(cor, cor_gelo_fundo * 1.2, (1.0 - miolo) * 0.2 * (1.0 - junta));
		cor = mix(cor, cor_neve, junta * 0.85);
		rug = mix(0.1, 0.7, junta) + (1.0 - serra) * 0.08;
		espec = 0.7;
		verniz = (1.0 - junta) * 0.5;
		atras = (1.0 - junta) * 0.6;
		emis = cor_gelo * (brilho * (0.5 + 0.5 * miolo) + borda * 0.35) * (1.0 - junta);
		alt = miolo * 0.5 - junta * 0.6 + serra * 0.05 * bem_perto + e2 * 0.15;
	} else if (modo == 2) {
		float hh = p.y + (n1 - 0.5) * 14.0;
		float camada = floor(hh / 5.0);
		cor = mix(cor_rocha, cor_rocha * 0.62, h11(camada) * 0.8);
		cor *= 0.8 + 0.4 * n2;
		cor *= 0.9 + 0.2 * n3 * perto;
		float junta = smoothstep(0.12, 0.0, fract(hh / 5.0));
		cor *= 1.0 - 0.35 * junta;
		// Neve presa nos degraus das camadas
		cor = mix(cor, cor_neve, smoothstep(0.82, 0.97, fract(hh / 5.0)) * 0.7 * neve);
		rug = 0.9;
		espec = 0.3;
		alt = n2 * 0.6 + n3 * 0.3 - junta * 0.5;
	} else if (modo == 3) {
		cor = vec3(0.52, 0.55, 0.6) * (0.82 + 0.3 * n2);
		cor *= 0.92 + 0.16 * n3 * perto;
		// Geada subindo do pé e escorrendo do topo, em manchas
		float geada = smoothstep(0.45, 0.75, n1 + n2 * 0.4);
		cor = mix(cor, vec3(0.82, 0.9, 0.97), geada * 0.6);
		// Marcas das formas (juntas horizontais a cada 3 m)
		float forma = smoothstep(0.04, 0.0, abs(fract(p.y / 3.0) - 0.5) - 0.46) * step(abs(nw.y), 0.7);
		cor *= 1.0 - 0.18 * forma;
		rug = mix(0.85, 0.5, geada);
		espec = 0.35;
		alt = n3 * 0.2 - forma * 0.2;
	} else {
		cor = cor_neve * (0.9 + 0.12 * n2);
		cor = mix(cor, vec3(0.78, 0.86, 0.97), smoothstep(0.55, 0.8, n1) * 0.4);
		rug = 0.85;
		espec = 0.4;
		alt = n2 * 0.3 + n3 * 0.15;
	}
	// Neve acumulada nas faces viradas para cima (borda irregular)
	float cima = smoothstep(0.55, 0.85, nw.y + (n2 - 0.5) * 0.35) * neve;
	if (modo != 4) {
		cor = mix(cor, cor_neve * (0.92 + 0.1 * n3), cima);
		rug = mix(rug, 0.85, cima);
		emis *= 1.0 - cima;
		verniz *= 1.0 - cima;
		atras *= 1.0 - cima;
		alt = mix(alt, n3 * 0.25, cima);
	}
	// Brilhinho da neve de perto
	float faisca = step(0.985, faisca_r) * cima * perto;
	// Relevo pela derivada da altura na tela (longe some, para não chuviscar)
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, nv);
	vec3 r2 = cross(nv, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(alt) * r1 + dFdy(alt) * r2);
	float forca = 0.32 * relevo * mix(0.3, 1.0, perto);
	NORMAL = normalize(abs(det) * nv - forca * grad);
	ALBEDO = cor;
	AO = mix(1.0, luz_vert, step(float(modo), 0.5));
	AO_LIGHT_AFFECT = 0.4;
	ROUGHNESS = clamp(rug, 0.02, 1.0);
	SPECULAR = espec;
	CLEARCOAT = verniz;
	CLEARCOAT_ROUGHNESS = 0.06;
	BACKLIGHT = cor_gelo * 0.35 * atras;
	EMISSION = emis + vec3(faisca) * 0.6;
}
