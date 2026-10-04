shader_type spatial;
render_mode cull_disabled;
// Estrada do Serpent's Climb: calçada maia (sacbé) de lajes irregulares de calcário com musgo nas
// juntas, rastro escuro dos pneus, bordas de pedra pintada de vermelho com a greca em degraus e
// chevrons de jade no centro a cada 24 m (acesos na rampa final).
// UV.x = 0..1 na largura, UV.y = metros ao longo da estrada (mesmos de pista.gdshader).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float largura = 10.0;
uniform vec3 cor_laje : source_color = vec3(0.72, 0.69, 0.6);
uniform vec3 cor_laje_b : source_color = vec3(0.58, 0.55, 0.47);
uniform vec3 cor_musgo : source_color = vec3(0.2, 0.3, 0.1);
uniform vec3 cor_vermelho : source_color = vec3(0.55, 0.13, 0.08);
uniform vec3 cor_jade : source_color = vec3(0.15, 0.85, 0.6);
uniform vec3 cor_equipe : source_color = vec3(1.0, 0.45, 0.08);
uniform float comp_plataforma = -1.0;
uniform float linha_largada = -100.0;
uniform float inicio_rampa = 1.0e9;

varying vec3 normal_mundo;

void vertex() {
	normal_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

// Lajes irregulares (Voronoi): distância à borda da laje e o id dela
vec3 lajes(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	float d1 = 8.0;
	float d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(h21(i + g), h21(i + g + 17.0)) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = i + g;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(d2 - d1, id);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float xm = u * largura;
	float dist = length(VERTEX);
	float perto = smoothstep(400.0, 30.0, dist);
	vec3 l = lajes(vec2(xm, v) / 1.4);
	float tom = h21(l.yz);
	vec3 cor = mix(cor_laje, cor_laje_b, tom * 0.7 + texture(ruido, vec2(xm, v) / 9.0).r * 0.4);
	float junta = 1.0 - smoothstep(0.015, 0.05, l.x);
	cor = mix(cor, cor_musgo * 0.9, junta * 0.7);
	cor *= 0.9 + 0.2 * texture(ruido, vec2(xm, v) * 0.9).r * perto;
	// Manchas de musgo e folhas nas beiradas
	float beirada = 1.0 - smoothstep(0.6, 2.2, min(xm, largura - xm));
	cor = mix(cor, cor_musgo, beirada * smoothstep(0.55, 0.75, texture(ruido, vec2(xm, v) / 4.0).r) * 0.45);
	float trilha = exp(-pow((abs(u - 0.5) * 2.0 - 0.42) / 0.14, 2.0));
	cor *= 1.0 - 0.2 * trilha;
	float rug = 0.8 - 0.15 * trilha;
	vec3 emissao = vec3(0.0);
	// Chevrons de jade no centro
	float x = abs(u - 0.5) * 2.0;
	float fase = fract(v / 24.0);
	float seta = step(abs(fase - 0.1 + x * 0.08), 0.02) * step(x, 0.35);
	cor = mix(cor, cor_jade, seta);
	emissao += cor_jade * seta * (v > inicio_rampa ? 1.8 : 0.45);
	// Borda pintada com a greca
	float dentro = min(u, 1.0 - u) * largura;
	float faixa = 1.0 - smoothstep(0.75, 0.8, dentro);
	if (faixa > 0.0) {
		float g = fract(v / 1.5);
		float y = dentro / 0.75;
		float degrau = step(y, 0.2 + floor(g * 4.0) * 0.2);
		vec3 borda = mix(cor_vermelho, vec3(0.82, 0.7, 0.45), degrau);
		borda *= 0.85 + 0.25 * texture(ruido, vec2(xm, v) / 3.0).r;
		cor = mix(cor, borda, faixa);
		float friso = smoothstep(0.66, 0.7, dentro) * (1.0 - smoothstep(0.72, 0.76, dentro));
		cor = mix(cor, cor_jade, friso);
		emissao += cor_jade * friso * 1.0;
	}
	// A face de cima da malha é a de trás (cull_disabled): a normal vinha invertida e a estrada era
	// iluminada por baixo (escura e verde). Sempre para cima.
	vec3 nw = normalize(normal_mundo);
	if (nw.y < 0.0) {
		nw = -nw;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = cor;
	EMISSION = emissao;
	ROUGHNESS = rug;
}
