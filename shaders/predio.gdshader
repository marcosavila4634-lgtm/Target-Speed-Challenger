shader_type spatial;
// Fachadas dos prédios do City Rush (caixa unitária escalada por instância, ver Cidade):
// - janelas com SALA DE VERDADE atrás do vidro (interior mapping: parede do fundo, laterais, piso e
//   forro com luminária), persianas meio baixadas, cortinas; o vidro reflete o céu (motor) e as
//   peles de vidro espelham com a cor do vidro;
// - caixilho e montantes em relevo (normal), peitoril/viga entre andares, pilares a cada N janelas,
//   tijolo aparente, concreto com manchas leves;
// - térreo com vitrines iluminadas e faixa de letreiro colorida;
// - luzes acesas agrupadas por andar/ala (escritório que ficou até tarde), não chuvisco;
// - longe, a grade vira a cor média (sem cintilar).
// INSTANCE_CUSTOM: r = semente, g = estilo / 8, b = fração de janelas acesas. COLOR = tom da fachada.
// Estilos: 0 pele de vidro, 1 escritório em faixas, 2 tijolo, 3 vidro escuro, 4 branco moderno,
//          5 torre da plataforma, 6 maciço (platibanda, cornija, casa de máquinas), 7 metal (equipamentos),
//          8 heliponto, 9 art déco (pilastras), 10 concreto aparente. Nas peles de vidro (0, 3) COLOR é a cor do vidro.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 lp;
varying vec3 ln;
varying vec3 escala;
varying vec4 dados;
varying vec3 tinta;
varying vec3 pos_mundo;
varying vec3 normal_mundo;
varying vec3 tangente_mundo;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	escala = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	dados = INSTANCE_CUSTOM;
	tinta = COLOR.rgb;
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// u cresce com z local nas faces ±x e com x local nas faces ±z
	tangente_mundo = abs(NORMAL.x) > 0.5 ? normalize(MODEL_MATRIX[2].xyz) : normalize(MODEL_MATRIX[0].xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Sala atrás da janela. q = ponto no vidro (m, 0..largura x 0..pe_direito), v = direção do olhar
// no espaço da sala (x = ao longo da fachada, y = cima, z = para dentro). Devolve a cor e, em w,
// quanto do que se vê é o forro perto da luminária (para acender).
vec4 sala(vec2 q, vec3 v, float largura, float pe, float fundo, vec3 c_parede, vec3 c_piso, float semente) {
	// Olhar quase paralelo ao piso/parede (v.y ou v.x ~ 0, na altura da câmera) dava divisão por
	// ~zero → infinito/NaN, que o bloom espalhava numa faixa branca na linha do horizonte.
	v.z = max(v.z, 0.02);
	v.x = abs(v.x) < 1e-3 ? 1e-3 : v.x;
	v.y = abs(v.y) < 1e-3 ? 1e-3 : v.y;
	q = clamp(q, vec2(0.0), vec2(largura, pe));
	float tx = v.x > 0.0 ? (largura - q.x) / v.x : -q.x / v.x;
	float ty = v.y > 0.0 ? (pe - q.y) / v.y : -q.y / v.y;
	float tz = fundo / v.z;
	float t = clamp(min(tx, min(ty, tz)), 0.0, 100.0);
	vec3 h = vec3(q, 0.0) + v * t;
	vec3 c;
	float forro = 0.0;
	if (t == tz) {
		c = c_parede;
		// quadro/estante na parede do fundo
		float m = step(0.25, fract(h.x / largura + semente)) * step(fract(h.x / largura + semente), 0.55) * step(0.35 * pe, h.y) * step(h.y, 0.7 * pe);
		c = mix(c, c_parede * vec3(0.55, 0.6, 0.7), m);
	} else if (t == ty) {
		if (v.y > 0.0) {
			c = vec3(0.82, 0.8, 0.76);
			forro = 1.0 - smoothstep(0.3, 1.2, length(vec2(h.x - largura * 0.5, h.z - fundo * 0.45)));
			c += forro * 0.6;
		} else {
			c = c_piso;
		}
	} else {
		c = c_parede * 0.82;
	}
	// mesas: faixa escura na altura do tampo, perto da janela
	float mesa = step(0.7, h.y) * step(h.y, 0.78) * step(h.z, fundo * 0.6) * step(t, tz - 0.01);
	c = mix(c, vec3(0.12, 0.1, 0.09), mesa * 0.7);
	c *= exp(-t * 0.06);
	return vec4(c, forro);
}

void fragment() {
	int estilo = int(dados.g * 8.0);
	// Face vista quase de lado (telhado na altura da câmera): o brilho do sol nesse ângulo estourava
	// numa linha branca no horizonte (com bloom). Sem especular quando o olhar é rasante.
	float rasante = smoothstep(0.02, 0.15, abs(dot(normalize(NORMAL), VIEW)));
	float semente = dados.r;
	float acesas = dados.b;
	float n = texture(ruido, vec2(pos_mundo.x + pos_mundo.z, pos_mundo.y) * 0.004 + semente).r;
	float nf = texture(ruido, pos_mundo.xz * 0.21 + pos_mundo.y * 0.17).r;

	if (abs(ln.y) > 0.5) {
		// Telhado: laje com manta, placas e manchas de água empoçada
		vec2 t = pos_mundo.xz;
		float placas = step(0.03, fract(t.x / 4.0)) * step(0.03, fract(t.y / 4.0));
		vec3 c = mix(vec3(0.3, 0.3, 0.31), vec3(0.42, 0.41, 0.4), n);
		c *= mix(0.88, 1.0, placas);
		c = mix(c, vec3(0.2, 0.21, 0.23), smoothstep(0.62, 0.7, n) * 0.6);
		if (estilo == 7) c = vec3(0.55, 0.56, 0.57) * mix(0.8, 1.05, nf);
		if (estilo == 8) {
			// Heliponto: círculo amarelo e "H" branco
			vec2 h = lp.xz * escala.xz;
			float r = length(h);
			c = vec3(0.16, 0.17, 0.18) * mix(0.9, 1.05, nf);
			c = mix(c, vec3(0.85, 0.65, 0.1), step(6.6, r) * step(r, 7.4));
			float barra = step(abs(h.x), 2.6) * step(2.0, abs(h.x)) * step(abs(h.y), 3.5);
			float traco = step(abs(h.x), 2.0) * step(abs(h.y), 0.35);
			c = mix(c, vec3(0.9), max(barra, traco));
			c = mix(c, vec3(0.9), step(8.6, max(abs(h.x), abs(h.y))));
		}
		ALBEDO = c * mix(vec3(1.0), tinta, 0.25);
		ROUGHNESS = 0.9;
		SPECULAR = 0.4 * rasante;
	} else {

	float u = (abs(ln.x) > 0.5 ? lp.z * escala.z : lp.x * escala.x) + (abs(ln.x) > 0.5 ? escala.z : escala.x) * 0.5;
	float v = (lp.y + 0.5) * escala.y;   // metros desde a base da caixa
	float largura_face = abs(ln.x) > 0.5 ? escala.z : escala.x;
	vec3 nw = normalize(normal_mundo);
	vec3 tw = normalize(tangente_mundo);
	vec3 bw = vec3(0.0, 1.0, 0.0);

	if (estilo >= 6 && estilo <= 8) {
		// Maciço (platibanda, cornija, casa de máquinas) ou equipamento metálico: sem janelas
		vec3 c = estilo == 6 ? tinta * mix(0.85, 1.02, n) : vec3(0.5, 0.52, 0.54) * mix(0.75, 1.05, nf);
		if (estilo == 7) {
			// aletas de ventilação
			float aleta = step(0.5, fract(v / 0.12));
			c *= mix(0.8, 1.0, aleta);
		}
		ALBEDO = c;
		ROUGHNESS = estilo == 7 ? 0.5 : 0.88;
		SPECULAR = 0.5 * rasante;
		METALLIC = (estilo == 7 ? 0.6 : 0.0) * rasante;
	} else {

	// ------------------------------------------------------------------ parâmetros do estilo
	float andar = 3.6;
	float col = 3.0;
	vec2 jan_min = vec2(0.12, 0.28);
	vec2 jan_max = vec2(0.88, 0.92);
	float pilar_cada = 0.0;            // pilar saliente a cada N colunas (0 = sem)
	vec3 parede = tinta;
	vec3 vidro = vec3(0.16, 0.22, 0.28);
	vec3 caixilho = vec3(0.2, 0.2, 0.21);
	float espelho = 0.0;               // 1 = pele de vidro espelhada
	float tijolo = 0.0;
	vec3 sala_parede = vec3(0.78, 0.75, 0.7);
	if (estilo == 0) {          // pele de vidro (cor do vidro = COLOR), montantes finos, viga escura por andar
		col = 1.5; jan_min = vec2(0.04, 0.12); jan_max = vec2(0.96, 0.97);
		parede = tinta * 0.38;
		vidro = tinta;
		caixilho = mix(vec3(0.55, 0.58, 0.6), vec3(0.12, 0.13, 0.14), step(0.5, fract(semente * 5.3)));
		espelho = 0.85;
	} else if (estilo == 1) {   // escritório: faixas de janela em fita, peitoril de concreto
		col = 1.8; jan_min = vec2(0.0, 0.34); jan_max = vec2(1.0, 0.9);
		parede = vec3(0.76, 0.72, 0.64) * tinta;
		caixilho = vec3(0.3, 0.31, 0.32);
		pilar_cada = 5.0;
	} else if (estilo == 2) {   // tijolo, janelas pequenas com verga
		col = 3.2; jan_min = vec2(0.26, 0.26); jan_max = vec2(0.74, 0.82);
		parede = mix(vec3(0.45, 0.2, 0.13), vec3(0.58, 0.32, 0.22), semente) * mix(vec3(1.0), tinta, 0.35);
		caixilho = vec3(0.86, 0.84, 0.8);
		tijolo = 1.0;
		sala_parede = vec3(0.85, 0.78, 0.66);
	} else if (estilo == 3) {   // vidro escuro / bronze
		col = 1.8; jan_min = vec2(0.05, 0.1); jan_max = vec2(0.95, 0.96);
		parede = tinta * 0.45;
		vidro = tinta;
		caixilho = vec3(0.1, 0.1, 0.1);
		espelho = 0.8;
	} else if (estilo == 4) {   // branco moderno, janelas largas, pilares
		col = 4.2; jan_min = vec2(0.08, 0.22); jan_max = vec2(0.92, 0.92);
		parede = vec3(0.9, 0.9, 0.88) * tinta;
		caixilho = vec3(0.15, 0.15, 0.16);
		pilar_cada = 3.0;
	} else if (estilo == 9) {   // art déco: pedra clara, pilastras contínuas entre janelas estreitas
		col = 2.4; jan_min = vec2(0.42, 0.18); jan_max = vec2(0.84, 0.88);
		parede = vec3(0.86, 0.8, 0.7) * tinta;
		vidro = vec3(0.14, 0.16, 0.18);
		caixilho = vec3(0.32, 0.24, 0.16);
		pilar_cada = 1.0;
		sala_parede = vec3(0.88, 0.8, 0.68);
	} else if (estilo == 10) {  // concreto aparente: faixas horizontais pesadas e fitas de janela
		col = 6.0; jan_min = vec2(0.0, 0.42); jan_max = vec2(1.0, 0.86);
		parede = vec3(0.62, 0.62, 0.6) * tinta;
		vidro = vec3(0.12, 0.14, 0.16);
		caixilho = vec3(0.08, 0.08, 0.09);
		pilar_cada = 2.0;
	} else {                    // torre da plataforma: vidro grafite com montantes metálicos
		col = 2.0; jan_min = vec2(0.06, 0.1); jan_max = vec2(0.94, 0.95);
		parede = vec3(0.26, 0.28, 0.3);
		vidro = vec3(0.3, 0.36, 0.42);
		caixilho = vec3(0.6, 0.62, 0.64);
		espelho = 0.9;
	}

	// Cada prédio com o seu ritmo: largura da coluna e altura da janela variam pela semente
	if (estilo != 5) {
		col *= mix(0.82, 1.3, fract(semente * 13.7));
		float alto = mix(-0.08, 0.06, fract(semente * 7.1));
		jan_min.y = clamp(jan_min.y - alto, 0.04, 0.6);
	}
	vec2 g = vec2(u / col, v / andar);
	vec2 id = floor(g);
	vec2 f = fract(g);
	vec2 dist_px = max(fwidth(g), vec2(1e-4));
	float aa = clamp(max(dist_px.x, dist_px.y) * 1.6 - 0.35, 0.0, 1.0);   // 1 = longe

	// Pilar saliente (faixa de parede cheia) a cada N colunas
	float pilar = 0.0;
	if (pilar_cada > 0.0) {
		float k = fract(u / (col * pilar_cada));
		pilar = step(k, 0.9 / (col * pilar_cada)) ;
	}
	float topo = step(escala.y - 1.0, v);
	float terreo = step(v, 4.6) * step(2.0, escala.y - v) * (estilo == 5 ? 0.0 : 1.0);

	// Máscara da janela com borda de caixilho
	vec2 d_borda = min(f - jan_min, jan_max - f) * vec2(col, andar);   // m até a borda do vão
	float dentro = step(0.0, min(d_borda.x, d_borda.y));
	float jan = dentro * (1.0 - pilar) * (1.0 - topo);
	float cobertura = (jan_max.x - jan_min.x) * (jan_max.y - jan_min.y) * (1.0 - topo);
	float caixa = jan * (1.0 - step(0.07, min(d_borda.x, d_borda.y)));     // caixilho de 7 cm
	// montante do meio nas janelas largas
	float largura_jan = (jan_max.x - jan_min.x) * col;
	if (largura_jan > 2.2) {
		float meio = abs(f.x - (jan_min.x + jan_max.x) * 0.5) * col;
		caixa = max(caixa, jan * (1.0 - step(0.04, meio)));
	}
	float vidro_m = jan * (1.0 - caixa);

	// ------------------------------------------------------------------ parede
	vec3 c_parede = parede * mix(0.9, 1.05, n);
	if (tijolo > 0.0) {
		vec2 b = vec2(u / 0.24 + step(0.5, fract(v / 0.13)) * 0.5, v / 0.065);
		vec2 fb = fract(b);
		float junta = step(0.06, fb.x) * step(0.14, fb.y);
		float var_t = hash(floor(b));
		vec3 c_tij = c_parede * mix(0.82, 1.12, var_t);
		float aa_t = clamp(max(fwidth(b.x), fwidth(b.y)) * 1.5 - 0.3, 0.0, 1.0);
		c_parede = mix(mix(vec3(0.62, 0.6, 0.56), c_tij, junta), c_parede * 0.96, aa_t);
		// verga de concreto em cima de cada janela
		float verga = step(jan_min.x - 0.04, f.x) * step(f.x, jan_max.x + 0.04) * step(jan_max.y, f.y) * step(f.y, jan_max.y + 0.06);
		c_parede = mix(c_parede, vec3(0.75, 0.72, 0.66), verga * (1.0 - aa));
	}
	// viga/peitoril escuro na pele de vidro (laje atrás do vidro)
	if (espelho > 0.0) {
		c_parede = parede * mix(0.85, 1.1, nf);
	}
	// manchas suaves de chuva abaixo dos peitoris (curtas, não listras de madeira)
	float mancha = texture(ruido, vec2(u * 0.04, v * 0.03) + semente * 7.0).r;
	c_parede *= mix(0.93, 1.0, smoothstep(0.3, 0.6, mancha));
	c_parede *= mix(0.72, 1.0, smoothstep(0.0, 9.0, v));   // base mais escura
	c_parede = mix(c_parede, c_parede * 0.85, pilar * 0.4);

	// ------------------------------------------------------------------ relevo (normal)
	// Vão da janela recuado: as bordas do vão viram faces inclinadas; pilares saem da fachada.
	vec3 nrel = nw;
	if (aa < 0.95) {
		float e = 0.1;
		vec2 grad = vec2(0.0);
		if (jan > 0.5) {
			// reveal: perto da borda a normal aponta para dentro do vão
			grad.x = (1.0 - smoothstep(0.0, e, d_borda.x)) * (f.x < 0.5 * (jan_min.x + jan_max.x) ? 1.0 : -1.0);
			grad.y = (1.0 - smoothstep(0.0, e, d_borda.y)) * (f.y < 0.5 * (jan_min.y + jan_max.y) ? 1.0 : -1.0);
		}
		if (pilar_cada > 0.0) {
			float k = fract(u / (col * pilar_cada)) * col * pilar_cada;
			grad.x += (1.0 - smoothstep(0.0, 0.06, k)) - (1.0 - smoothstep(0.0, 0.06, 0.9 - k));
		}
		grad *= 0.8 * (1.0 - aa);
		nrel = normalize(nw + tw * grad.x + bw * grad.y);
	}

	// ------------------------------------------------------------------ vidro: sala atrás
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 olhar = normalize(pos_mundo - cam);
	vec3 v_sala = vec3(dot(olhar, tw), dot(olhar, bw), dot(olhar, -nw));
	// Luzes acesas agrupadas: ala (4 colunas) x andar, depois janela a janela dentro da ala
	vec2 ala = vec2(floor(id.x / 4.0), id.y);
	float ala_acesa = step(hash(ala + semente * 37.0 + floor(ln.x * 2.0 + ln.z * 3.0) * 11.0), acesas * 1.6);
	float acesa = ala_acesa * step(hash(id + semente * 91.0), 0.85);
	float persiana = step(0.55, hash(id * 1.31 + semente)) * hash(id * 2.7 + 5.0) * 0.7;   // quanto desceu
	vec2 q = vec2((f.x - jan_min.x) * col, (f.y - jan_min.y) * andar);
	float largura_sala = (jan_max.x - jan_min.x) * col;
	float pe = (jan_max.y - jan_min.y) * andar;
	vec3 c_piso = mix(vec3(0.16, 0.14, 0.12), vec3(0.3, 0.24, 0.18), hash(id + 2.0));
	// longe (aa ~ 1) a sala não aparece: pula o cálculo
	vec4 s = aa > 0.97 ? vec4(0.0) : sala(q, v_sala, largura_sala, pe, 5.5, sala_parede * mix(0.8, 1.05, hash(id + 9.0)), c_piso, hash(id));
	vec3 luz_dia = vec3(0.16, 0.155, 0.15);                       // sala clara de dia, sem luz própria
	vec3 cor_luz = mix(vec3(1.0, 0.78, 0.52), vec3(0.85, 0.92, 1.0), step(0.6, hash(ala + 3.1)));
	vec3 interior = s.rgb * (luz_dia + acesa * cor_luz * 0.9) + acesa * s.w * cor_luz * 1.5;
	// persiana na parte de cima do vão
	float na_persiana = step(pe * (1.0 - persiana), q.y);
	interior = mix(interior, vec3(0.6, 0.58, 0.54) * (0.35 + acesa * 0.5), na_persiana);
	// sombra do vão no alto do vidro
	interior *= mix(0.55, 1.0, smoothstep(0.0, 0.35, pe - q.y));
	// longe: média
	vec3 interior_medio = vec3(0.1, 0.095, 0.09) + acesas * vec3(0.35, 0.28, 0.2);
	interior = mix(clamp(interior, vec3(0.0), vec3(4.0)), interior_medio, aa);

	// ------------------------------------------------------------------ térreo: vitrines e letreiro
	vec3 emissao_extra = vec3(0.0);
	if (terreo > 0.5) {
		float loja = floor(u / 7.0);
		float fl = fract(u / 7.0);
		float vitrine = step(0.05, fl) * step(fl, 0.95) * step(0.3, v) * step(v, 3.5);
		float letreiro = step(0.15, fl) * step(fl, 0.85) * step(3.75, v) * step(v, 4.4);
		vec3 hue = 0.5 + 0.5 * cos(6.2831 * (hash(vec2(loja, semente * 5.0)) + vec3(0.0, 0.33, 0.67)));
		vec2 qv = vec2(fl * 7.0, v - 0.3);
		vec4 sv = length(pos_mundo - cam) > 900.0 ? vec4(0.3, 0.29, 0.27, 0.0) : sala(qv, v_sala, 7.0, 3.2, 9.0, vec3(0.85, 0.82, 0.78), vec3(0.4, 0.38, 0.35), hash(vec2(loja, 1.0)));
		float loja_acesa = step(0.3, hash(vec2(loja, semente * 13.0)));
		vec3 int_loja = sv.rgb * (vec3(0.35) + loja_acesa * vec3(1.0, 0.85, 0.65) * 0.8);
		c_parede = mix(c_parede * 0.55, vec3(0.08), vitrine);
		c_parede = mix(c_parede, hue * 0.6, letreiro);
		emissao_extra = int_loja * vitrine * 0.8 + hue * letreiro * 1.2 * loja_acesa;
		jan = vitrine; vidro_m = vitrine; caixa = 0.0;
		interior = int_loja;
	}

	// ------------------------------------------------------------------ composição
	float m_vidro = mix(vidro_m, cobertura, aa * (1.0 - terreo));
	float m_caixa = caixa * (1.0 - aa);
	vec3 alb_vidro = mix(vec3(0.02), vidro * 0.6, espelho);
	vec3 c = mix(c_parede, caixilho, m_caixa);
	c = mix(c, alb_vidro, m_vidro);
	ALBEDO = c;
	METALLIC = mix(m_caixa * 0.5, espelho, m_vidro) * rasante;
	// Vidro não é espelho perfeito: com rugosidade 0.04 o sol baixo refletido nas fachadas virava
	// faixas brancas estouradas (bloom) na altura dos olhos, atravessando a tela inteira.
	ROUGHNESS = mix(mix(0.88, 0.4, m_caixa), mix(0.16, 0.26, fract(semente * 3.7)), m_vidro);
	SPECULAR = mix(0.35, 0.5, m_vidro) * rasante;
	// a sala aparece através do vidro (menos nas peles espelhadas)
	EMISSION = interior * m_vidro * (1.0 - espelho * 0.75) + emissao_extra;
	NORMAL = normalize((VIEW_MATRIX * vec4(nrel, 0.0)).xyz);
	}
	}
}
