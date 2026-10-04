shader_type spatial;
// Alvo do Serpent's Climb: a Pedra do Sol (calendário asteca) entalhada e pintada no disco.
// Do centro para fora: rosto do sol, os quatro painéis do "movimento" (ollin), o anel dos 20 dias,
// a faixa de pontos, os 8 raios solares e as duas serpentes de fogo na borda. Laterais em pedra.
// Coordenadas locais do disco (cilindro com o topo em y = 0).

uniform float raio = 15.0;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_pedra : source_color = vec3(0.6, 0.55, 0.45);
uniform vec3 cor_vermelho : source_color = vec3(0.68, 0.14, 0.08);
uniform vec3 cor_turquesa : source_color = vec3(0.1, 0.55, 0.55);
uniform vec3 cor_ocre : source_color = vec3(0.86, 0.62, 0.2);

varying vec3 local;
varying vec3 nrm_local;

void vertex() {
	local = VERTEX;
	nrm_local = NORMAL;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	vec2 q = local.xz / raio;
	float r = length(q);
	float a = atan(q.y, q.x);
	float a01 = a / 6.28318 + 0.5;
	float rug = texture(ruido, local.xz / 9.0).r;
	vec3 cor = cor_pedra * (0.85 + 0.25 * rug);
	float relevo = 0.0;      // 1 = alto-relevo (claro), -1 = sulco (escuro)
	vec3 tinta = vec3(0.0);
	float pinta = 0.0;
	if (nrm_local.y > 0.5) {
		if (r < 0.16) {
			// Rosto do sol: olhos, boca com a língua de faca, brincos
			vec2 f = q / 0.16;
			float olho = step(length((f - vec2(-0.35, -0.2)) / vec2(0.22, 0.12)), 1.0) + step(length((f - vec2(0.35, -0.2)) / vec2(0.22, 0.12)), 1.0);
			float boca = step(abs(f.x), 0.28) * step(abs(f.y - 0.38), 0.08);
			float lingua = step(abs(f.x), 0.1 - (f.y - 0.42) * 0.18) * step(0.42, f.y) * step(f.y, 0.92);
			relevo = 0.5 - olho - boca * 0.8;
			tinta = cor_ocre;
			pinta = 0.8;
			if (lingua > 0.5) { tinta = cor_vermelho; pinta = 1.0; relevo = 1.0; }
			if (olho > 0.5) { tinta = cor_turquesa; }
		} else if (r < 0.31) {
			// Ollin: quatro painéis nas diagonais, o resto em sulcos
			float ad = mod(a + 0.785, 1.5708) - 0.785;
			float painel = step(abs(ad), 0.36) * step(0.19, r) * step(r, 0.29);
			relevo = painel > 0.5 ? 1.0 : -0.3;
			tinta = painel > 0.5 ? cor_turquesa : cor_vermelho;
			pinta = painel > 0.5 ? 0.7 : 0.3;
		} else if (r < 0.43) {
			// Os 20 dias: caixas com um glifo (desenho sorteado) em cada
			float id = floor(a01 * 20.0);
			float u = fract(a01 * 20.0);
			float v = (r - 0.31) / 0.12;
			float caixa = step(0.08, u) * step(u, 0.92) * step(0.1, v) * step(v, 0.9);
			float glifo = step(h21(vec2(id, floor(u * 3.0) + floor(v * 3.0) * 3.0)), 0.55) * caixa;
			relevo = caixa * (0.3 + glifo * 0.7) - (1.0 - caixa) * 0.6;
			tinta = mix(cor_ocre, cor_turquesa, step(0.5, h21(vec2(id, 7.0))));
			pinta = glifo * 0.7;
		} else if (r < 0.5) {
			// Faixa de pontos (quincunces)
			float u = fract(a01 * 60.0);
			float ponto = step(length(vec2(u - 0.5, ((r - 0.43) / 0.07 - 0.5) * 0.45)), 0.28);
			relevo = ponto - 0.2;
			tinta = cor_vermelho;
			pinta = ponto * 0.6;
		} else if (r < 0.76) {
			// Raios solares: 8 grandes triângulos e 8 menores entre eles
			float u = fract(a01 * 8.0);
			float t = (r - 0.5) / 0.26;
			float grande = step(abs(u - 0.5), 0.22 * (1.0 - t));
			float pequeno = step(abs(abs(u - 0.5) - 0.5), 0.07 * (1.0 - t));
			float raio_s = max(grande, pequeno);
			relevo = raio_s * 1.0 - (1.0 - raio_s) * 0.15;
			tinta = grande > 0.5 ? cor_ocre : cor_turquesa;
			pinta = raio_s * 0.85;
		} else if (r < 0.98) {
			// Serpentes de fogo: corpo em segmentos com chamas, cabeças embaixo
			float u = fract(a01 * 44.0);
			float t = (r - 0.76) / 0.22;
			float segmento = step(0.1, u) * step(u, 0.9) * step(0.18, t) * step(t, 0.82);
			float chama = step(0.82, t) * step(abs(u - 0.5), 0.3 * (1.0 - (t - 0.82) / 0.18));
			relevo = max(segmento, chama) - 0.25;
			tinta = chama > 0.5 ? cor_ocre : cor_vermelho;
			pinta = max(segmento, chama) * 0.75;
		} else {
			relevo = 0.4;
		}
		// Sulcos finos separando os anéis
		float sulco = min(min(abs(r - 0.16), abs(r - 0.31)), min(min(abs(r - 0.43), abs(r - 0.5)), min(abs(r - 0.76), abs(r - 0.98))));
		relevo -= (1.0 - smoothstep(0.0, 0.006, sulco)) * 1.5;
		float gasto = smoothstep(0.35, 0.75, texture(ruido, local.xz / 4.0).r);
		cor *= 0.78 + 0.22 * clamp(relevo, -1.0, 1.0) + 0.12;
		cor = mix(cor, tinta, pinta * (1.0 - gasto * 0.6));
	} else {
		cor *= 0.75;
	}
	ALBEDO = cor;
	ROUGHNESS = 0.85;
}
