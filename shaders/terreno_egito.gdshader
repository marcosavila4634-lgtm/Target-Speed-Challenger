shader_type spatial;
// Deserto do Egito (Pharaoh's Climb):
// - areia dourada com ondulações do vento (marcas finas de perto, cristas de duna escuras/claras de longe);
// - penhascos de calcário em camadas claras (creme, ocre, branco) com degraus e manchas de erosão;
// - faixa verde do Nilo (plantações em lotes, tamareiras na textura de longe) e margem de lama úmida.
// A máscara mascara_nilo (R = proximidade do rio, 1 na água e 0 longe) vem de Egito.textura_margem.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform sampler2D mascara_nilo : filter_linear, repeat_disable;
uniform float meio_mascara = 3400.0;
uniform float nivel_agua = 4.0;
uniform vec3 cor_areia : source_color = vec3(0.86, 0.66, 0.4);
uniform vec3 cor_areia_clara : source_color = vec3(0.95, 0.8, 0.55);
uniform vec3 cor_areia_escura : source_color = vec3(0.7, 0.48, 0.27);
uniform vec3 cor_calcario : source_color = vec3(0.86, 0.76, 0.6);
uniform vec3 cor_calcario_ocre : source_color = vec3(0.78, 0.58, 0.36);
uniform vec3 cor_calcario_branco : source_color = vec3(0.93, 0.89, 0.8);
uniform vec3 cor_plantacao : source_color = vec3(0.22, 0.36, 0.1);
uniform vec3 cor_plantacao_clara : source_color = vec3(0.45, 0.52, 0.16);
uniform vec3 cor_lama : source_color = vec3(0.3, 0.24, 0.16);

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float ruido_parede(sampler2D tex, vec3 p, vec3 n, float escala) {
	float a = texture(tex, vec2(p.x, p.y) / escala).r;
	float b = texture(tex, vec2(p.z, p.y) / escala).r;
	float wx = abs(n.z);
	float wz = abs(n.x);
	return (a * wx + b * wz) / max(wx + wz, 0.001);
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 nw = normalize(normal_mundo);
	float h = p.y;
	float dist = length(p - CAMERA_POSITION_WORLD);
	float perto = smoothstep(2200.0, 250.0, dist);
	float bem_perto = smoothstep(500.0, 60.0, dist);
	float inclinacao = 1.0 - clamp(nw.y, 0.0, 1.0);
	// Areia segura encostas bem mais íngremes que a rocha do cânion (dunas)
	float parede = smoothstep(0.42, 0.68, inclinacao);

	float n_grande = texture(ruido, p.xz / 1300.0).r;
	float nm = texture(ruido, p.xz / 260.0).r;
	float nf = texture(ruido_fino, p.xz / 31.0).r;

	// ---- Areia: tons em manchas grandes, cristas (luz rasante) e ondulações do vento
	vec3 areia = mix(cor_areia, cor_areia_clara, smoothstep(0.35, 0.75, n_grande));
	areia = mix(areia, cor_areia_escura, smoothstep(0.55, 0.85, nm) * 0.45);
	// Ondulações: listras finas tortas, alinhadas na diagonal (o vento vem de noroeste)
	vec2 q = vec2(p.x * 0.8 + p.z * 0.6, p.z * 0.8 - p.x * 0.6);
	float torce = (texture(ruido_fino, p.xz / 23.0).r - 0.5) * 6.0;
	float onda = sin((q.x + torce) * 2.1);
	float marcas = smoothstep(0.6, 1.0, onda) * bem_perto;
	areia *= 1.0 - 0.09 * marcas;
	areia *= 1.0 + (texture(ruido_fino, p.xz / 3.0).r - 0.5) * 0.12 * bem_perto;
	// Cascalho e pedrinhas escuras espalhadas (reg do deserto) nas partes planas mais baixas
	float reg = smoothstep(0.62, 0.8, texture(ruido_fino, p.xz / 90.0).r) * (1.0 - smoothstep(30.0, 90.0, h));
	areia = mix(areia, cor_areia_escura * 0.8, reg * 0.35);

	// ---- Calcário em camadas (penhascos do Vale dos Reis)
	float hh = h + (n_grande - 0.5) * 40.0 + (texture(ruido, p.xz / 230.0).r - 0.5) * 10.0;
	float id_camada = floor(hh / 7.5);
	float u = fract(hh / 7.5);
	float sorteio = hash(id_camada * 1.73 + 2.0);
	vec3 rocha = sorteio < 0.45 ? cor_calcario : (sorteio < 0.75 ? cor_calcario_branco : cor_calcario_ocre);
	rocha *= 0.88 + 0.22 * hash(id_camada + 9.0);
	rocha *= 0.94 + 0.06 * sin(hh * 4.1 + nf * 3.0);
	float junta = smoothstep(0.1, 0.0, u) + smoothstep(0.92, 1.0, u) * 0.6;
	rocha *= 1.0 - 0.32 * junta;
	// Erosão: manchas verticais acinzentadas e areia acumulada nos degraus
	float along = (p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001);
	float escorrido = texture(ruido_fino, vec2(along / 7.0, h / 650.0)).r;
	rocha = mix(rocha, rocha * vec3(0.76, 0.72, 0.68), smoothstep(0.6, 0.82, escorrido) * 0.5);
	rocha *= 0.9 + 0.16 * ruido_parede(ruido_fino, p, nw, 150.0) + (ruido_parede(ruido_fino, p, nw, 2.5) - 0.5) * 0.12 * bem_perto;
	rocha = mix(rocha, areia, smoothstep(0.75, 0.97, u) * 0.4);

	// ---- Faixa verde do Nilo: lotes de plantação, canais e margem de lama
	vec2 uv_m = (p.xz + meio_mascara) / (2.0 * meio_mascara);
	float margem = texture(mascara_nilo, uv_m).r;
	vec2 lote = floor(vec2(p.x * 0.95 + p.z * 0.3, p.z * 0.95 - p.x * 0.3) / vec2(38.0, 26.0));
	float tipo_lote = hash2(lote);
	vec3 verde = mix(cor_plantacao, cor_plantacao_clara, tipo_lote);
	verde = mix(verde, cor_areia_escura * 0.9, step(0.86, tipo_lote));   // lote arado / em pousio
	verde *= 0.85 + 0.3 * nf;
	// Linhas de plantio e divisas dos lotes (de perto)
	vec2 f = fract(vec2(p.x * 0.95 + p.z * 0.3, p.z * 0.95 - p.x * 0.3) / vec2(38.0, 26.0));
	float divisa = (1.0 - smoothstep(0.0, 0.035, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)))) * perto;
	verde = mix(verde, cor_lama * 1.3, divisa * 0.6);
	verde *= 1.0 - 0.12 * smoothstep(0.3, 1.0, sin(f.x * 120.0)) * bem_perto;
	float faixa = smoothstep(0.18, 0.42, margem + (nf - 0.5) * 0.12) * (1.0 - smoothstep(20.0, 34.0, h));
	vec3 chao = mix(areia, verde, faixa);
	float lama = smoothstep(0.82, 0.93, margem);
	chao = mix(chao, cor_lama, lama);
	float umido = smoothstep(nivel_agua + 2.5, nivel_agua + 0.2, h);

	vec3 cor = mix(chao, rocha, parede);
	cor *= 1.0 - 0.4 * umido;

	// ---- Relevo da normal: ondulações da areia e rugosidade da rocha
	vec3 nn = nw;
	if (perto > 0.01) {
		float e = 1.0;
		float b0 = ruido_parede(ruido_fino, p, nw, 7.0);
		float bx = ruido_parede(ruido_fino, p + vec3(e, 0.0, e), nw, 7.0);
		float by = ruido_parede(ruido_fino, p + vec3(0.0, e, 0.0), nw, 7.0);
		vec3 lado = normalize(vec3(-nw.z, 0.0, nw.x) + vec3(0.0001));
		nn += (-(bx - b0) * lado - (by - b0) * vec3(0.0, 1.0, 0.0)) * 1.4 * parede * perto;
		nn.y += (0.25 * smoothstep(0.55, 0.95, u) - 0.3 * junta) * parede * perto;
		// Ondulações da areia: a derivada da onda inclina a normal (luz rasante do pôr do sol)
		float donda = cos((q.x + torce) * 2.1);
		nn.xz += vec2(0.8, 0.6) * donda * 0.08 * bem_perto * (1.0 - parede) * (1.0 - faixa);
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);

	ALBEDO = cor;
	ROUGHNESS = mix(mix(0.92, 0.8, faixa), 0.4, umido);
	SPECULAR = mix(0.3, 0.5, umido);
}
