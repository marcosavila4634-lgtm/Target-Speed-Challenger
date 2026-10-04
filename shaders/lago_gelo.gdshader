shader_type spatial;
// Lago e rio congelados do Frozen Peak: gelo escuro e liso (reflete o céu) com rachaduras brancas
// em rede, bolhas presas e bancos de neve soprada por cima.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_gelo : source_color = vec3(0.3, 0.62, 0.8);
uniform vec3 cor_fundo : source_color = vec3(0.1, 0.34, 0.56);
uniform vec3 cor_neve : source_color = vec3(0.92, 0.95, 1.0);

varying vec3 pos_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float rachadura(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.0)) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

void fragment() {
	vec2 p = pos_mundo.xz;
	float dist = length(pos_mundo - CAMERA_POSITION_WORLD);
	float perto = smoothstep(900.0, 60.0, dist);
	float n1 = texture(ruido, p / 160.0).r;
	float n2 = texture(ruido, p / 31.0).r;
	vec3 cor = mix(cor_gelo, cor_fundo, smoothstep(0.3, 0.8, n1));
	float r1 = 1.0 - smoothstep(0.0, 0.02, rachadura(p / 26.0));
	float r2 = (1.0 - smoothstep(0.0, 0.03, rachadura(p / 6.0 + 3.1))) * perto;
	cor = mix(cor, vec3(0.8, 0.93, 1.0), clamp(r1 * 0.7 + r2 * 0.35, 0.0, 1.0));
	// Bancos de neve soprada
	float banco = smoothstep(0.62, 0.74, texture(ruido, p / 210.0 + 1.9).r * 0.75 + n2 * 0.25);
	cor = mix(cor, cor_neve * (0.92 + 0.1 * n2), banco);
	ALBEDO = cor;
	ROUGHNESS = mix(0.06 + r1 * 0.3, 0.85, banco);
	SPECULAR = mix(0.8, 0.4, banco);
	METALLIC = 0.1 * (1.0 - banco);
}
