shader_type spatial;
render_mode cull_disabled;
// Trecho de gelo vivo (Frozen Peak): gelo azul polido, quase um espelho, com rachaduras brancas,
// bolhas presas e riscos de pneu. Faixas de aviso azul-claro piscando nas bordas: aqui o carro
// escorrega. UV.x = 0..1 na largura, UV.y = metros ao longo da estrada.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float largura = 10.0;
uniform vec3 cor_gelo : source_color = vec3(0.16, 0.5, 0.78);
uniform vec3 cor_fundo : source_color = vec3(0.03, 0.17, 0.36);
uniform vec3 cor_aviso : source_color = vec3(0.45, 0.95, 1.0);

varying vec3 normal_mundo;

void vertex() {
	normal_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

// Rachaduras: bordas das células de Voronoi
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
	float u = UV.x;
	float v = UV.y;
	float xm = u * largura;
	float dist = length(VERTEX);
	float perto = smoothstep(260.0, 15.0, dist);
	float n1 = texture(ruido, vec2(xm, v) / 14.0).r;
	float n2 = texture(ruido, vec2(xm, v) / 2.5).r;
	vec3 cor = mix(cor_gelo, cor_fundo, smoothstep(0.3, 0.75, n1));
	// Rachaduras grandes e finas
	float r1 = 1.0 - smoothstep(0.0, 0.035, rachadura(vec2(xm, v) / 3.2));
	float r2 = (1.0 - smoothstep(0.0, 0.05, rachadura(vec2(xm, v) / 0.9 + 7.3))) * perto;
	cor = mix(cor, vec3(0.82, 0.94, 1.0), clamp(r1 * 0.75 + r2 * 0.3, 0.0, 1.0));
	// Bolhas de ar presas
	float bolha = smoothstep(0.78, 0.84, n2) * perto;
	cor = mix(cor, vec3(0.7, 0.88, 1.0), bolha * 0.5);
	// Riscos dos pneus (opacos)
	float trilha = exp(-pow((abs(u - 0.5) * 2.0 - 0.42) / 0.12, 2.0));
	float risco = trilha * (0.5 + 0.5 * sin(v * 9.0 + n1 * 12.0)) * 0.35;
	cor = mix(cor, vec3(0.75, 0.86, 0.95), risco);
	float rug = 0.04 + r1 * 0.3 + risco * 0.5;
	// Bordas: faixa de aviso piscando
	float dentro = min(u, 1.0 - u) * largura;
	float faixa = 1.0 - smoothstep(0.55, 0.6, dentro);
	float lista = step(0.5, fract((v + xm) / 1.6));
	float pulso = 0.55 + 0.45 * sin(TIME * 5.0 - v * 0.35);
	cor = mix(cor, mix(cor_fundo * 0.6, cor_aviso, lista), faixa);
	vec3 nw = normalize(normal_mundo);
	if (nw.y < 0.0) {
		nw = -nw;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = cor;
	EMISSION = cor_aviso * faixa * lista * pulso * 1.6 + cor_gelo * 0.12;
	ROUGHNESS = mix(rug, 0.35, faixa);
	SPECULAR = 0.9;
	METALLIC = 0.15;
}
