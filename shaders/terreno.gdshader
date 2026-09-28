shader_type spatial;
// Rocha do cânion:
// - paredões com estratos de espessura e cor irregulares (vermelho-escuro, ferrugem, laranja, creme, lilás),
//   degraus sombreados entre camadas, rugosidade (normal perturbada) e manchas escuras escorridas ("verniz do deserto");
// - encostas de cascalho mais claras; topos de mesa com areia, rocha de cobertura e vegetação rasteira;
// - margens do rio úmidas e mais verdes.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform float nivel_agua = 4.0;
uniform vec3 c_vermelho_escuro : source_color = vec3(0.34, 0.12, 0.07);
uniform vec3 c_ferrugem : source_color = vec3(0.56, 0.22, 0.1);
uniform vec3 c_laranja : source_color = vec3(0.74, 0.38, 0.17);
uniform vec3 c_creme : source_color = vec3(0.84, 0.64, 0.44);
uniform vec3 c_lilas : source_color = vec3(0.46, 0.3, 0.28);
uniform vec3 cor_cascalho : source_color = vec3(0.7, 0.45, 0.3);
uniform vec3 cor_areia : source_color = vec3(0.82, 0.6, 0.4);
uniform vec3 cor_topo : source_color = vec3(0.72, 0.5, 0.33);
uniform vec3 cor_vegetacao : source_color = vec3(0.24, 0.27, 0.12);
uniform vec3 cor_vegetacao_rio : source_color = vec3(0.16, 0.26, 0.1);

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

vec3 paleta(float r) {
	if (r < 0.22) return c_vermelho_escuro;
	if (r < 0.5) return c_ferrugem;
	if (r < 0.74) return c_laranja;
	if (r < 0.88) return c_creme;
	return c_lilas;
}

// Ruído "de parede": projeções XY e ZY misturadas pela orientação da face.
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
	float perto = smoothstep(2500.0, 300.0, dist);
	float bem_perto = smoothstep(700.0, 120.0, dist);

	float n_grande = texture(ruido, p.xz / 1100.0).r;
	float nf = texture(ruido_fino, p.xz / 41.0).r;
	// Manchas de vegetação em escala grande (dezenas de metros), com borda quebrada só de perto
	float nveg = texture(ruido_fino, p.xz / 220.0).r * 0.8 + texture(ruido_fino, p.xz / 37.0).r * 0.2;
	float inclinacao = 1.0 - clamp(nw.y, 0.0, 1.0);
	float parede = smoothstep(0.28, 0.6, inclinacao);

	// ---- Estratos: a altura é "entortada" pelo ruído para as camadas não ficarem retas
	float hh = h + (n_grande - 0.5) * 60.0 + (texture(ruido, p.xz / 300.0).r - 0.5) * 14.0;
	float id_formacao = floor(hh / 42.0);
	float id_camada = floor(hh / 6.5);
	float u = fract(hh / 6.5);
	vec3 formacao = paleta(hash(id_formacao));
	vec3 camada = paleta(hash(id_camada * 1.37 + 5.0));
	vec3 rocha = mix(formacao, camada, 0.35);
	rocha *= 0.86 + 0.28 * hash(id_camada);
	// Laminações finas dentro de cada camada
	rocha *= 0.92 + 0.08 * sin(hh * 5.3 + nf * 4.0);
	// Degrau entre camadas: linha escura e topo de cada camada levemente mais claro
	float junta = smoothstep(0.1, 0.0, u) + smoothstep(0.93, 1.0, u) * 0.6;
	rocha *= 1.0 - 0.35 * junta * parede;
	rocha *= 0.95 + 0.12 * smoothstep(0.6, 0.95, u) * parede;

	// Verniz do deserto: manchas escuras verticais escorrendo dos topos
	float along = (p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001);
	float escorrido = texture(ruido_fino, vec2(along / 22.0, h / 520.0)).r;
	rocha = mix(rocha, rocha * vec3(0.42, 0.36, 0.34), smoothstep(0.55, 0.78, escorrido) * parede * 0.8);
	// Variação de rocha em escala média
	float rv = ruido_parede(ruido_fino, p, nw, 57.0);
	rocha *= 0.78 + 0.4 * rv;

	// ---- Encostas de cascalho (inclinação intermediária)
	float talude = smoothstep(0.14, 0.3, inclinacao) * (1.0 - parede);
	vec3 cascalho = mix(cor_cascalho, formacao, 0.35) * (1.0 + (texture(ruido_fino, p.xz / 7.0).r - 0.5) * 0.3 * bem_perto);

	// ---- Superfícies planas: topo de mesa, fundo do cânion, margens
	vec3 chao = mix(cor_areia, cor_topo, smoothstep(40.0, 160.0, h));
	chao = mix(chao, c_creme * 0.95, smoothstep(0.6, 0.8, n_grande) * smoothstep(150.0, 260.0, h));
	float moita = smoothstep(0.5, 0.85, nveg + (texture(ruido_fino, p.xz / 9.0).r - 0.5) * 0.12 * bem_perto);
	chao = mix(chao, cor_vegetacao, moita * 0.28 * smoothstep(nivel_agua + 2.0, nivel_agua + 12.0, h));
	chao *= 1.0 + (texture(ruido_fino, p.xz / 5.0).r - 0.5) * 0.18 * bem_perto;
	// Perto do rio: mais verde e úmido
	float margem = smoothstep(nivel_agua + 28.0, nivel_agua + 4.0, h);
	chao = mix(chao, cor_vegetacao_rio, margem * smoothstep(0.35, 0.6, nveg) * 0.8);
	float umido = smoothstep(nivel_agua + 2.5, nivel_agua + 0.3, h);

	vec3 cor = mix(chao, cascalho, talude);
	cor = mix(cor, rocha, parede);
	cor *= 1.0 - 0.45 * umido;
	// Pé dos paredões e fundo mais escuros (luz rebatida some)
	cor *= mix(0.7, 1.0, smoothstep(nivel_agua, nivel_agua + 30.0, h));

	// ---- Relevo: rugosidade nos paredões e degraus inclinando a normal para cima
	vec3 nn = nw;
	if (perto > 0.01) {
		float e = 1.2;
		float b0 = ruido_parede(ruido_fino, p, nw, 23.0);
		float bx = ruido_parede(ruido_fino, p + vec3(e, 0.0, e), nw, 23.0);
		float by = ruido_parede(ruido_fino, p + vec3(0.0, e, 0.0), nw, 23.0);
		vec3 lado = normalize(vec3(-nw.z, 0.0, nw.x) + vec3(0.0001));
		nn += (-(bx - b0) * lado - (by - b0) * vec3(0.0, 1.0, 0.0)) * 5.0 * parede * perto;
		nn.y += (0.25 * smoothstep(0.55, 0.95, u) - 0.35 * junta) * parede * perto;
		float bc = texture(ruido_fino, p.xz / 7.0).r;
		float bcx = texture(ruido_fino, (p.xz + vec2(0.6, 0.0)) / 7.0).r;
		float bcz = texture(ruido_fino, (p.xz + vec2(0.0, 0.6)) / 7.0).r;
		nn += vec3(-(bcx - bc), 0.0, -(bcz - bc)) * 1.2 * (1.0 - parede) * bem_perto;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);

	ALBEDO = cor;
	ROUGHNESS = mix(0.95, 0.35, umido);
	SPECULAR = mix(0.25, 0.5, umido);
}
