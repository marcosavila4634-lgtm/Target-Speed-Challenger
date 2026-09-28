shader_type spatial;
render_mode cull_disabled;
// Tabuleiro da pista. UV.x = 0..1 na largura, UV.y = metros ao longo da pista.
// Plataforma: chapas de aço, linha de largada quadriculada e faixa zebrada antes da descida.
// Descida: asfalto escuro com setas na cor da equipe. Bordas com neon da equipe (não há guarda-corpo).

uniform vec3 cor_equipe : source_color = vec3(0.2, 0.4, 1.0);
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float largura = 22.0;
uniform float comp_plataforma = 70.0;
uniform float linha_largada = 21.0;
uniform float inicio_rampa = 560.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float xm = u * largura;
	float n = texture(ruido, vec2(u * 4.0, v / 6.0)).r;
	vec3 cor;
	float rugosidade = 0.85;
	float metal = 0.0;
	vec3 emissao = vec3(0.0);

	if (v < comp_plataforma) {
		// Chapas de aço 2,75 x 2 m com juntas escuras e textura de piso antiderrapante.
		vec2 c = vec2(xm / 2.75, v / 2.0);
		vec2 f = fract(c);
		float junta = 1.0 - step(0.03, f.x) * step(f.x, 0.97) * step(0.04, f.y) * step(f.y, 0.96);
		float variacao = texture(ruido, floor(c) * 0.37).r;
		float relevo = step(0.7, fract((xm + v) * 3.0)) * 0.06;
		cor = vec3(0.3, 0.31, 0.33) * (0.8 + 0.35 * variacao + relevo) * (1.0 - 0.55 * junta);
		metal = 0.6;
		rugosidade = 0.5 + 0.2 * n;
		// Linha de largada quadriculada.
		if (v > linha_largada && v < linha_largada + 1.6) {
			float q = mod(floor(xm / 0.8) + floor((v - linha_largada) / 0.8), 2.0);
			cor = mix(vec3(0.05), vec3(0.9), q);
			metal = 0.0;
		}
		// Faixa zebrada amarela/preta antes da borda.
		if (v > comp_plataforma - 4.0 && v < comp_plataforma - 1.0) {
			float z = step(0.5, fract((xm + v) / 2.0));
			cor = mix(vec3(0.06), vec3(0.95, 0.72, 0.08), z);
			metal = 0.0;
			rugosidade = 0.7;
		}
	} else {
		cor = vec3(0.23, 0.23, 0.25) * (0.8 + 0.4 * n);
		// Setas (chevrons) no centro a cada 24 m; na rampa final ficam âmbar e brilham.
		float x = abs(u - 0.5) * 2.0;
		float fase = fract(v / 24.0);
		float seta = step(abs(fase - 0.1 - x * 0.08), 0.02) * step(x, 0.35);
		vec3 cor_seta = v > inicio_rampa ? vec3(1.0, 0.6, 0.15) : cor_equipe * 0.9;
		cor = mix(cor, cor_seta, seta);
		emissao += cor_seta * seta * (v > inicio_rampa ? 1.5 : 0.4);
		// Marcas de pneu escurecendo a rampa final.
		float pneu = step(0.62, texture(ruido, vec2(u * 1.5, v / 40.0)).r) * step(inicio_rampa - 60.0, v);
		cor *= 1.0 - 0.3 * pneu;
	}

	// Faixas brancas e neon da equipe nas bordas.
	float borda = step(u, 0.035) + step(0.965, u);
	cor = mix(cor, vec3(0.85, 0.83, 0.78), clamp(borda, 0.0, 1.0));
	float neon = step(u, 0.012) + step(0.988, u);
	emissao += cor_equipe * 3.0 * clamp(neon, 0.0, 1.0);
	cor = mix(cor, cor_equipe, clamp(neon, 0.0, 1.0));

	ALBEDO = cor;
	EMISSION = emissao;
	METALLIC = metal;
	ROUGHNESS = rugosidade;
}
