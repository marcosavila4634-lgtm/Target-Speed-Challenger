shader_type spatial;
render_mode cull_disabled;
// Estrada do Pharaoh's Climb: calçada de lajes de calcário (como os caminhos processionais),
// juntas com areia, lajes gastas no rastro dos pneus, faixa de mosaico azul e dourado nas bordas
// (padrão de lótus/escamas) e chevrons dourados no centro a cada 24 m.
// UV.x = 0..1 na largura, UV.y = metros ao longo da estrada (mesmos de pista.gdshader).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float largura = 10.0;
uniform vec3 cor_laje : source_color = vec3(0.8, 0.68, 0.5);
uniform vec3 cor_laje_b : source_color = vec3(0.66, 0.52, 0.36);
uniform vec3 cor_azul : source_color = vec3(0.08, 0.3, 0.55);
uniform vec3 cor_ouro : source_color = vec3(1.0, 0.72, 0.28);
// Para não quebrar quem passa os mesmos parâmetros da pista comum
uniform vec3 cor_equipe : source_color = vec3(1.0, 0.45, 0.08);
uniform float comp_plataforma = -1.0;
uniform float linha_largada = -100.0;
uniform float inicio_rampa = 1.0e9;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float xm = u * largura;
	float dist = length(VERTEX);
	float perto = smoothstep(400.0, 30.0, dist);
	// Lajes: fileiras de 1,6 m ao longo, larguras alternadas e juntas desencontradas
	float fila = floor(v / 1.6);
	float desloc = h21(vec2(fila, 1.0)) * 1.4;
	float lw = 1.8 + 0.8 * h21(vec2(fila, 2.0));
	float col = floor((xm + desloc) / lw);
	vec2 f = vec2(fract((xm + desloc) / lw), fract(v / 1.6));
	float tom = h21(vec2(col, fila));
	vec3 cor = mix(cor_laje, cor_laje_b, tom * 0.7 + texture(ruido, vec2(xm, v) / 9.0).r * 0.4);
	float borda = min(min(f.x, 1.0 - f.x) * lw, min(f.y, 1.0 - f.y) * 1.6);
	float junta = 1.0 - smoothstep(0.02, 0.07, borda);
	cor = mix(cor, vec3(0.62, 0.48, 0.3), junta * 0.8);
	cor *= 0.9 + 0.2 * texture(ruido, vec2(xm, v) * 0.9).r * perto;
	// Rastro dos pneus: laje polida e mais escura (poeira de borracha)
	float trilha = exp(-pow((abs(u - 0.5) * 2.0 - 0.42) / 0.14, 2.0));
	cor *= 1.0 - 0.18 * trilha;
	float rug = 0.75 - 0.2 * trilha;
	vec3 emissao = vec3(0.0);
	// Chevrons dourados no centro a cada 24 m (âmbar forte na rampa final)
	float x = abs(u - 0.5) * 2.0;
	float fase = fract(v / 24.0);
	float seta = step(abs(fase - 0.1 + x * 0.08), 0.02) * step(x, 0.35);
	cor = mix(cor, cor_ouro, seta);
	emissao += cor_ouro * seta * (v > inicio_rampa ? 1.6 : 0.5);
	// Faixa de mosaico nas bordas: escamas azuis e douradas, com friso de ouro por dentro
	float dentro = min(u, 1.0 - u) * largura;
	float faixa = 1.0 - smoothstep(0.75, 0.8, dentro);
	if (faixa > 0.0) {
		vec2 e = vec2(dentro / 0.75, v / 0.75);
		vec2 c = vec2(fract(e.y), e.x);
		float escama = length(vec2(c.x - 0.5, c.y * 0.9)) - 0.45;
		vec3 mosaico = mix(cor_azul, cor_ouro, step(0.0, escama));
		mosaico *= 0.85 + 0.3 * h21(floor(vec2(v / 0.75, dentro / 0.75)));
		cor = mix(cor, mosaico, faixa);
		float friso = smoothstep(0.66, 0.7, dentro) * (1.0 - smoothstep(0.72, 0.76, dentro));
		cor = mix(cor, cor_ouro, friso);
		emissao += cor_ouro * friso * 1.2;
		rug = mix(rug, 0.35, faixa);
	}
	ALBEDO = cor;
	EMISSION = emissao;
	METALLIC = faixa * 0.3;
	ROUGHNESS = rug;
}
