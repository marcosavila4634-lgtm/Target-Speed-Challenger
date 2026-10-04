shader_type spatial;
// Concreto aparente (coordenadas do mundo, serve para peças instanciadas): placas de fôrma com
// juntas, furos dos tirantes, variação de tom, manchas de água escorrendo, sujeira na base
// e bordas lascadas mais claras.

uniform vec3 cor_base : source_color = vec3(0.44, 0.41, 0.38);
uniform vec3 cor_mancha : source_color = vec3(0.32, 0.29, 0.26);
uniform vec3 cor_poeira : source_color = vec3(0.66, 0.44, 0.28);
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec2 placa = vec2(2.4, 1.2);    // tamanho da placa de fôrma (largura, altura) em metros
uniform float altura_chao = 0.0;
uniform float altura_poeira = 5.0;
uniform float sujeira = 0.5;

// Onda de choque do impacto final (Extinction Day): tudo o que fica dentro do raio é arrasado
uniform vec3 onda_centro = vec3(0.0);
uniform float onda_raio = -1.0;
varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(vec3 p, vec3 n, float escala) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return texture(ruido, p.yz / escala).r * w.x + texture(ruido, p.xz / escala).r * w.y + texture(ruido, p.xy / escala).r * w.z;
}

void fragment() {
	if (onda_raio > 0.0 && distance(pos_mundo.xz, onda_centro.xz) < onda_raio - 30.0 - 90.0 * texture(ruido, pos_mundo.xz / 43.0).r) {
		discard;   // os pilares somem na onda de choque
	}
	vec3 p = pos_mundo;
	vec3 n = normal_mundo;
	float grande = tri(p, n, 11.0);
	float medio = tri(p, n, 2.5);
	float fino = tri(p, n, 0.35);

	// Coordenada no plano da face: horizontal ao longo da face, vertical = y
	vec3 an = abs(n);
	vec2 q = an.x > an.z ? vec2(p.z, p.y) : vec2(p.x, p.y);
	if (an.y > 0.7) q = p.xz;

	vec3 cor = cor_base * (0.82 + 0.3 * grande) * (0.93 + 0.12 * fino);
	// Cada placa de fôrma com um tom levemente diferente
	vec2 id = floor(q / placa);
	float tom = fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
	cor *= 0.94 + 0.1 * tom;

	// Juntas entre placas e furos dos tirantes (só nas faces verticais)
	float vertical = 1.0 - smoothstep(0.6, 0.8, an.y);
	vec2 f = fract(q / placa);
	vec2 dist_borda = min(f, 1.0 - f) * placa;
	float junta = 1.0 - smoothstep(0.0, 0.025, min(dist_borda.x, dist_borda.y));
	vec2 furo_c = (fract(q / (placa * 0.5)) - 0.5) * placa * 0.5;
	float furo = 1.0 - smoothstep(0.03, 0.045, length(furo_c));
	cor *= 1.0 - 0.35 * junta * vertical - 0.5 * furo * vertical;

	// Manchas de água escorrendo das juntas horizontais
	float corrido = texture(ruido, vec2(q.x / 0.9, q.y / 10.0)).r;
	float escorre = smoothstep(0.6, 0.78, corrido) * smoothstep(0.35, 0.9, fract(q.y / placa.y)) * vertical;
	cor = mix(cor, cor_mancha, escorre * 0.45 * sujeira);

	// Manchas grandes de umidade e bolor
	float umidade = smoothstep(0.55, 0.8, grande * 0.7 + medio * 0.5);
	cor = mix(cor, cor_mancha * 0.9, umidade * 0.35 * sujeira);

	// Poeira do cânion subindo do chão e acumulada em cima
	float poeira = smoothstep(altura_poeira, 0.0, p.y - altura_chao) * (0.6 + 0.4 * medio);
	poeira = max(poeira, smoothstep(0.7, 1.0, n.y) * 0.4 * grande);
	cor = mix(cor, cor_poeira, poeira * 0.6);

	ALBEDO = cor;
	ROUGHNESS = 0.88 + 0.1 * fino;
	METALLIC = 0.0;
	// Relevo: juntas e furos afundados, poros finos
	NORMAL_MAP = normalize(vec3(0.5 + (fino - 0.5) * 0.25, 0.5 + (medio - 0.5) * 0.15, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
}
