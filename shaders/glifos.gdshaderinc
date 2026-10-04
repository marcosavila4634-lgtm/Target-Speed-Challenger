// Hieróglifos procedurais (Pharaoh's Climb): cada célula sorteia um sinal desenhado por formas
// simples (sol, olho, água, ankh, pássaro, cobra, cesto, pilar djed, cartucho...). Usado nos obeliscos,
// no portal de Anúbis e nos pilones dos pistões. glifo() devolve a "tinta" (0..1) em uv (0..1).

float glifo_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float glifo_seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t) - r;
}

float glifo_caixa(vec2 p, vec2 c, vec2 m) {
	vec2 d = abs(p - c) - m;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Distância (negativa dentro) do sinal `id` (0..1) na célula uv (0..1).
float glifo_sdf(vec2 uv, float id) {
	vec2 p = uv;
	float t = 0.045;   // espessura do traço
	float d = 1e3;
	if (id < 0.1) {          // sol: disco com ponto
		d = abs(length(p - vec2(0.5)) - 0.26) - t;
		d = min(d, length(p - vec2(0.5)) - 0.06);
	} else if (id < 0.2) {   // água: zigue-zague
		float x = p.x * 6.0;
		float y = 0.5 + 0.08 * (abs(fract(x) - 0.5) * 4.0 - 1.0);
		d = (abs(p.y - y) - t) ;
		d = max(d, abs(p.x - 0.5) - 0.4);
	} else if (id < 0.3) {   // ankh: laço em cima e cruz
		d = abs(length((p - vec2(0.5, 0.72)) * vec2(1.0, 1.3)) - 0.13) - t;
		d = min(d, glifo_seg(p, vec2(0.5, 0.58), vec2(0.5, 0.1), t));
		d = min(d, glifo_seg(p, vec2(0.28, 0.5), vec2(0.72, 0.5), t));
	} else if (id < 0.4) {   // olho de Hórus
		d = abs(length((p - vec2(0.5, 0.58)) * vec2(1.0, 2.4)) - 0.3) - t * 1.2;
		d = min(d, length(p - vec2(0.5, 0.58)) - 0.08);
		d = min(d, glifo_seg(p, vec2(0.45, 0.46), vec2(0.4, 0.18), t));
		d = min(d, glifo_seg(p, vec2(0.6, 0.46), vec2(0.72, 0.22), t));
	} else if (id < 0.5) {   // pássaro (falcão): corpo, cabeça, cauda e pés
		d = length((p - vec2(0.5, 0.5)) * vec2(1.0, 1.6)) - 0.2;
		d = min(d, length(p - vec2(0.68, 0.7)) - 0.09);
		d = min(d, glifo_seg(p, vec2(0.35, 0.45), vec2(0.18, 0.25), t * 1.4));
		d = min(d, glifo_seg(p, vec2(0.48, 0.36), vec2(0.45, 0.1), t * 0.8));
		d = min(d, glifo_seg(p, vec2(0.58, 0.36), vec2(0.6, 0.1), t * 0.8));
	} else if (id < 0.6) {   // cobra: onda deitada com cabeça
		float y = 0.4 + 0.1 * sin(p.x * 14.0);
		d = max(abs(p.y - y) - t, abs(p.x - 0.48) - 0.34);
		d = min(d, glifo_seg(p, vec2(0.82, 0.42), vec2(0.82, 0.68), t * 1.2));
	} else if (id < 0.7) {   // pilar djed: coluna com travessas
		d = glifo_seg(p, vec2(0.5, 0.1), vec2(0.5, 0.88), t * 1.6);
		for (int k = 0; k < 4; k++) {
			float y = 0.62 + float(k) * 0.07;
			d = min(d, glifo_seg(p, vec2(0.3, y), vec2(0.7, y), t * 0.8));
		}
	} else if (id < 0.8) {   // cesto (meia-lua) e pão (semicírculo)
		d = max(abs(length((p - vec2(0.5, 0.62)) * vec2(1.0, 1.4)) - 0.28) - t, p.y - 0.62);
		d = min(d, max(length((p - vec2(0.5, 0.18)) * vec2(1.0, 1.6)) - 0.2, 0.18 - p.y));
	} else if (id < 0.9) {   // pena de Maat e duas barras
		d = length((p - vec2(0.36, 0.55)) * vec2(2.6, 1.0)) - 0.32;
		d = max(d, -(length((p - vec2(0.45, 0.55)) * vec2(2.6, 1.0)) - 0.22));
		d = min(d, glifo_caixa(p, vec2(0.7, 0.62), vec2(0.06, 0.25)));
		d = min(d, glifo_caixa(p, vec2(0.86, 0.62), vec2(0.06, 0.25)));
	} else {                 // cartucho com nome do faraó (oval com sinais pequenos)
		d = abs(glifo_caixa(p, vec2(0.5), vec2(0.28, 0.4)) - 0.04) - t * 0.8;
		d = min(d, length(p - vec2(0.5, 0.7)) - 0.08);
		d = min(d, glifo_seg(p, vec2(0.38, 0.5), vec2(0.62, 0.5), t * 0.8));
		d = min(d, abs(length(p - vec2(0.5, 0.3)) - 0.07) - t * 0.6);
		d = min(d, glifo_seg(p, vec2(0.3, 0.06), vec2(0.7, 0.06), t));
	}
	return d;
}

// Tinta do sinal (borda suavizada pela distância de tela: `aa` ~ fwidth em uv).
float glifo(vec2 uv, float id, float aa) {
	return 1.0 - smoothstep(-aa, aa, glifo_sdf(uv, id));
}

// Faixa vertical de hieróglifos: coluna de largura `largura`, células quadradas, `pos` em metros
// (x = do meio da coluna, y = altura). Devolve a tinta (0 fora da coluna) e a moldura da coluna.
vec2 coluna_glifos(vec2 pos, float largura, float semente, float aa_m) {
	float meia = largura * 0.5;
	float moldura = 1.0 - smoothstep(0.0, aa_m * 2.0, abs(abs(pos.x) - meia) - largura * 0.04);
	if (abs(pos.x) > meia * 0.9) {
		return vec2(0.0, moldura);
	}
	float alto = largura * 0.95;
	float linha = floor(pos.y / alto);
	vec2 uv = vec2((pos.x + meia * 0.9) / (largura * 0.9), fract(pos.y / alto));
	uv = (uv - 0.5) * 1.12 + 0.5;
	float id = glifo_hash(vec2(linha, semente));
	float tinta = 0.0;
	if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0) {
		tinta = glifo(uv, id, aa_m / largura * 1.5);
	}
	return vec2(tinta, moldura);
}
