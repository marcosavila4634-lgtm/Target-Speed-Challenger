shader_type spatial;
// Pista de arrancada "preparada" em coordenadas do mundo (largada em z = 0, chegada em z = -distancia).
// - Placa de concreto nos primeiros metros, asfalto depois.
// - Borracha: duas trilhas escuras e brilhantes por faixa (cola/VHT + pneu), marcas de pneu em riscos
//   ao longo da pista, mais pesada na largada e na caixa de borrachão (molhada).
// - Brilho: onde há borracha a pista fica quase espelhada (reflexos do céu e das luzes, com SSR).
// - Linhas brancas, linha de largada, chegada quadriculada, marcas de distância.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float largura_faixa = 5.2;
uniform float distancia = 201.168;
uniform float concreto_ate = 100.0;
uniform float brilho = 1.0;          // quanto a borracha espelha (0..1)
// Textura fotográfica do asfalto (assets/drag/asfalto*.png, de tools/ambiente/texturas_drag.gd):
// duas amostras em escalas e ângulos diferentes misturadas pelo ruído, para não repetir à vista.
uniform sampler2D asfalto : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asfalto_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float metros_textura = 3.0;  // tamanho de uma repetição da textura

varying vec3 p;

void vertex() {
	p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float x = p.x;
	float d = -p.z;
	float lw = largura_faixa;
	float n = texture(ruido, p.xz / 9.0).r;
	float n2 = texture(ruido, p.xz / 37.0).r;
	float nf = texture(ruido, p.xz * 0.8).r;
	// Riscos de pneu ao longo da pista (esticados em z)
	float riscos = texture(ruido, vec2(x * 3.1, d * 0.012)).r;
	float riscos_finos = texture(ruido, vec2(x * 11.0, d * 0.03)).r;

	// Textura do asfalto (grão, agregado e rachaduras) e o relevo dela
	vec2 uv1 = p.xz / metros_textura;
	vec2 uv2 = vec2(p.x + p.z, p.x - p.z) * 0.7071 / (metros_textura * 2.7);
	float mistura = smoothstep(0.3, 0.7, n2);
	vec3 tex = mix(texture(asfalto, uv1).rgb, texture(asfalto, uv2).rgb, mistura);
	vec3 relevo = mix(texture(asfalto_normal, uv1).rgb, texture(asfalto_normal, uv2).rgb, mistura);
	float lum = dot(tex, vec3(0.3333));
	tex = mix(vec3(lum), tex, 0.45);   // tira o esverdeado da foto

	// Base: asfalto com agregado claro; concreto na largada
	vec3 cor = tex * 0.4 * (0.82 + 0.3 * n) + (nf - 0.5) * 0.03;
	float rug = 0.78 + (0.45 - lum) * 0.3;
	float fundo = 1.0;   // força do relevo
	if (d > -40.0 && d < concreto_ate) {
		cor = vec3(0.47, 0.46, 0.44) * (0.82 + 0.28 * n2) * (0.7 + 0.65 * lum) + (nf - 0.5) * 0.04;
		fundo = 0.3;
		float junta = step(0.985, fract(d / 6.0)) + step(0.99, fract((x + 50.0) / (lw * 0.5)));
		cor *= 1.0 - 0.4 * clamp(junta, 0.0, 1.0);
		rug = 0.85;
	}

	// Borracha: trilhas das rodas (bitola ~1,6 m) em cada faixa + véu escuro no meio da faixa
	float c = abs(abs(x) - lw * 0.5);                       // distância ao centro da faixa
	float trilha = smoothstep(0.75, 0.25, abs(c - 0.8));
	float meio = smoothstep(1.9, 0.4, c);
	float peso = mix(1.0, 0.45, smoothstep(0.0, 180.0, d)) * step(-30.0, d) * step(d, distancia + 250.0);
	float caixa = step(-30.0, d) * step(d, -3.0) * step(abs(x), lw);   // caixa de borrachão
	float borracha = trilha * peso * (0.65 + 0.5 * riscos) + meio * peso * 0.35 * riscos_finos;
	borracha = max(borracha, caixa * (0.5 + 0.5 * trilha) * riscos);
	borracha = clamp(borracha * (0.85 + 0.3 * n), 0.0, 1.0);
	cor = mix(cor, vec3(0.018, 0.018, 0.02), borracha * 0.92);
	rug = mix(rug, mix(0.3, 0.1, brilho), borracha);
	// Caixa de borrachão molhada: poças espelhadas
	float poca = caixa * smoothstep(0.45, 0.65, n2);
	rug = mix(rug, 0.03, poca);
	cor *= 1.0 - 0.3 * poca;

	// Linhas: divisória central, laterais e as de largada/borrachão
	float linha = step(abs(x), 0.08) * step(0.0, d) + step(abs(abs(x) - lw), 0.1);
	linha += step(abs(d), 0.15) * step(abs(x), lw);
	linha += step(abs(d + 30.0), 0.1) * step(abs(x), lw);
	// Marcas de distância (60 pés, 330 pés, 1/8) nas bordas
	for (int i = 0; i < 3; i++) {
		float m = i == 0 ? 18.29 : (i == 1 ? 100.58 : distancia);
		linha += step(abs(d - m), 0.12) * step(lw - 0.8, abs(x)) * step(abs(x), lw);
	}
	cor = mix(cor, vec3(0.88, 0.88, 0.85) * (0.85 + 0.15 * n), clamp(linha, 0.0, 1.0) * (1.0 - borracha * 0.5));

	// Chegada quadriculada
	float dc = d - distancia;
	if (dc > -0.8 && dc < 0.8 && abs(x) < lw) {
		float q = mod(floor((x + 20.0) / 0.4) + floor((dc + 0.8) / 0.4), 2.0);
		cor = mix(vec3(0.03), vec3(0.9), q);
		rug = 0.6;
	}
	ALBEDO = cor;
	NORMAL_MAP = relevo;
	NORMAL_MAP_DEPTH = fundo * mix(1.0, 0.2, borracha) * (1.0 - poca) * (1.0 - clamp(linha, 0.0, 1.0) * 0.5);
	ROUGHNESS = rug;
	SPECULAR = mix(0.45, 0.7, borracha);
}
