shader_type spatial;
render_mode cull_disabled;
// Estrada do Frozen Peak: neve batida pela máquina (estrias finas ao longo), dois trilhos de pneu
// onde aparece o gelo cinza-azulado, zebras vermelhas e brancas nas bordas, filete de neon azul e
// chevrons azul-gelo no centro a cada 24 m (acesos na rampa final).
// UV.x = 0..1 na largura, UV.y = metros ao longo da estrada (mesmos de pista.gdshader).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float largura = 10.0;
uniform vec3 cor_neve : source_color = vec3(0.9, 0.93, 0.97);
uniform vec3 cor_trilho : source_color = vec3(0.56, 0.64, 0.74);
uniform vec3 cor_vermelho : source_color = vec3(0.78, 0.07, 0.06);
uniform vec3 cor_neon : source_color = vec3(0.25, 0.8, 1.0);
uniform vec3 cor_equipe : source_color = vec3(1.0, 0.45, 0.08);
uniform float comp_plataforma = -1.0;
uniform float linha_largada = -100.0;
uniform float inicio_rampa = 1.0e9;

varying vec3 normal_mundo;

void vertex() {
	normal_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float xm = u * largura;
	float dist = length(VERTEX);
	float perto = smoothstep(300.0, 20.0, dist);
	float n1 = texture(ruido, vec2(xm, v) / 11.0).r;
	float n2 = texture(ruido, vec2(xm, v) * 0.8).r;
	vec3 cor = cor_neve * (0.93 + 0.1 * n1);
	// Estrias da máquina de neve (ao longo da estrada), só de perto
	float estria = 0.5 + 0.5 * sin(xm * 42.0);
	cor *= 1.0 - 0.07 * estria * perto;
	// Trilhos dos pneus: neve gasta até o gelo
	float trilha = exp(-pow((abs(u - 0.5) * 2.0 - 0.42) / 0.15, 2.0));
	float gasto = trilha * smoothstep(0.3, 0.7, n1 + n2 * 0.3);
	cor = mix(cor, cor_trilho * (0.9 + 0.2 * n2), gasto * 0.8);
	float rug = mix(0.82, 0.35, gasto);
	// Montinhos de neve solta
	cor = mix(cor, vec3(0.97, 0.98, 1.0), smoothstep(0.62, 0.8, texture(ruido, vec2(xm, v) / 3.3).r) * 0.5 * (1.0 - gasto));
	vec3 emissao = vec3(0.0);
	// Chevrons no centro
	float x = abs(u - 0.5) * 2.0;
	float fase = fract(v / 24.0);
	float seta = step(abs(fase - 0.1 + x * 0.08), 0.02) * step(x, 0.35);
	cor = mix(cor, cor_neon * 0.8, seta);
	emissao += cor_neon * seta * (v > inicio_rampa ? 2.0 : 0.5);
	// Zebra nas bordas e filete de neon
	float dentro = min(u, 1.0 - u) * largura;
	float faixa = 1.0 - smoothstep(0.7, 0.75, dentro);
	if (faixa > 0.0) {
		float z = step(0.5, fract(v / 3.0));
		vec3 zebra = mix(vec3(0.94, 0.95, 0.97), cor_vermelho, z);
		zebra = mix(zebra, cor_neve, smoothstep(0.5, 0.78, n2) * 0.55);   // neve por cima da pintura
		cor = mix(cor, zebra, faixa);
		rug = mix(rug, 0.6, faixa);
	}
	float filete = smoothstep(0.76, 0.8, dentro) * (1.0 - smoothstep(0.86, 0.9, dentro));
	cor = mix(cor, cor_neon, filete);
	emissao += cor_neon * filete * 1.3;
	float faisca = step(0.988, texture(ruido, vec2(xm, v) * 2.3).r) * perto * (1.0 - gasto);
	// A face de cima da malha é a de trás (cull_disabled): normal sempre para cima
	vec3 nw = normalize(normal_mundo);
	if (nw.y < 0.0) {
		nw = -nw;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ALBEDO = cor;
	EMISSION = emissao + vec3(faisca) * 0.5;
	ROUGHNESS = rug;
	SPECULAR = 0.45;
}
