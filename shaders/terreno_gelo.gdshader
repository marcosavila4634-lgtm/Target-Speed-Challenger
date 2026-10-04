shader_type spatial;
// Frozen Peak:
// - neve: branca com sombra azulada, ondas esculpidas pelo vento (sastrugi) e brilhos de perto;
// - encostas íngremes: rocha escura em camadas com neve presa nos degraus e gelo azul escorrido;
// - geleira: manchas de gelo azul onde a neve foi varrida;
// - margem do lago congelado (mascara_lago de Gelo.textura_margem): gelo azulado sob a neve fina.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform sampler2D mascara_lago : filter_linear, repeat_disable;
uniform float meio_mascara = 3400.0;
uniform float nivel_agua = 4.0;
uniform vec3 cor_neve : source_color = vec3(0.93, 0.95, 0.99);
uniform vec3 cor_neve_sombra : source_color = vec3(0.84, 0.89, 0.97);
uniform vec3 cor_rocha : source_color = vec3(0.3, 0.29, 0.31);
uniform vec3 cor_rocha_escura : source_color = vec3(0.16, 0.16, 0.19);
uniform vec3 cor_gelo : source_color = vec3(0.4, 0.7, 0.88);
uniform vec2 dir_vento = vec2(1.0, 0.0);

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
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
	float perto = smoothstep(1800.0, 150.0, dist);
	float bem_perto = smoothstep(350.0, 30.0, dist);
	float inclinacao = 1.0 - clamp(nw.y, 0.0, 1.0);

	float n_grande = texture(ruido, p.xz / 1300.0).r;
	float nm = texture(ruido, p.xz / 210.0).r;
	float nf = texture(ruido_fino, p.xz / 27.0).r;

	// ---- Neve
	// Sastrugi: cristas compridas atravessadas ao vento
	vec2 dv = normalize(dir_vento);
	vec2 q = vec2(dot(p.xz, dv), dot(p.xz, vec2(-dv.y, dv.x)));
	float onda = texture(ruido_fino, vec2(q.x / 9.0, q.y / 55.0)).r;
	// Neve lisa: só variações largas e suaves (as ondas do vento aparecem pelo relevo, não pela cor)
	vec3 neve = mix(cor_neve_sombra, cor_neve, smoothstep(0.25, 0.75, nm));
	neve = mix(neve, cor_neve * 1.02, smoothstep(0.5, 0.9, n_grande) * 0.5);
	neve *= 0.975 + 0.035 * onda * bem_perto;
	// Geleira: gelo azul onde o vento varreu a neve (áreas quase planas)
	float varrido = smoothstep(0.7, 0.86, texture(ruido, p.xz / 640.0 + 3.7).r * 0.7 + nm * 0.3) * (1.0 - smoothstep(0.05, 0.2, inclinacao));
	float veio = 1.0 - smoothstep(0.0, 0.08, abs(texture(ruido_fino, p.xz / 31.0).r - 0.5));
	vec3 gelo = mix(cor_gelo, vec3(0.86, 0.95, 1.0), veio * 0.5 * perto);
	neve = mix(neve, gelo, varrido * 0.55);

	// ---- Rocha nas encostas íngremes, em camadas, com neve nos degraus
	float limiar = 0.34 + (nm - 0.5) * 0.16;
	float parede = smoothstep(limiar, limiar + 0.2, inclinacao);
	float hh = h + (n_grande - 0.5) * 40.0;
	float id_camada = floor(hh / 11.0);
	float u = fract(hh / 11.0);
	vec3 rocha = mix(cor_rocha, cor_rocha_escura, hash(id_camada * 1.7) * 0.7 + 0.15);
	rocha *= 0.85 + 0.3 * ruido_parede(ruido_fino, p, nw, 120.0);
	float junta = smoothstep(0.1, 0.0, u) + smoothstep(0.93, 1.0, u) * 0.6;
	rocha *= 1.0 - 0.3 * junta;
	rocha *= 0.9 + (ruido_parede(ruido_fino, p, nw, 2.0) - 0.5) * 0.25 * bem_perto;
	// Neve presa nos degraus e em manchas; gelo azul escorrendo em colunas
	float presa = smoothstep(0.62, 0.9, u) * 0.8 + smoothstep(0.5, 0.75, ruido_parede(ruido, p, nw, 46.0)) * 0.55;
	rocha = mix(rocha, cor_neve * 0.96, clamp(presa, 0.0, 1.0) * 0.8);
	float along = (p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001);
	float escorre = texture(ruido_fino, vec2(along / 7.0, h / 420.0)).r;
	rocha = mix(rocha, cor_gelo * 0.9, smoothstep(0.62, 0.8, escorre) * 0.55);

	// ---- Margem do lago: gelo azulado sob a neve fina
	vec2 uv_m = (p.xz + meio_mascara) / (2.0 * meio_mascara);
	float margem = texture(mascara_lago, uv_m).r;
	neve = mix(neve, mix(cor_gelo * 0.95, cor_neve, nf * 0.6), smoothstep(0.3, 0.8, margem + (nf - 0.5) * 0.2) * 0.7);

	vec3 cor = mix(neve, rocha, parede);
	// Sombra azul nas faces que não olham para cima (a neve reflete o céu)
	cor = mix(cor, cor * vec3(0.88, 0.93, 1.04), smoothstep(0.1, 0.5, inclinacao) * (1.0 - parede));

	// Relevo: ondas de neve (de perto) e rugosidade/degraus da rocha nas encostas. Sem ramificação:
	// as amostras ficam fora de qualquer if (o driver da RX 5700 XT travava com elas dentro de um).
	vec3 nn = nw;
	float onda_x = texture(ruido_fino, vec2((q.x + 1.0) / 9.0, q.y / 55.0)).r;
	nn.xz -= dv * (onda_x - onda) * 2.2 * (1.0 - parede) * bem_perto;
	float b0 = ruido_parede(ruido_fino, p, nw, 6.0);
	float bx = ruido_parede(ruido_fino, p + vec3(1.0, 0.0, 1.0), nw, 6.0);
	float by = ruido_parede(ruido_fino, p + vec3(0.0, 1.0, 0.0), nw, 6.0);
	vec3 lado = normalize(vec3(-nw.z, 0.0, nw.x) + vec3(0.0001));
	nn += (-(bx - b0) * lado - (by - b0) * vec3(0.0, 1.0, 0.0)) * 1.6 * parede * perto;
	nn.y += (0.25 * smoothstep(0.55, 0.95, u) - 0.3 * junta) * parede * perto;
	float faisca = step(0.992, texture(ruido_fino, p.xz * 1.9).r) * bem_perto * (1.0 - parede);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
	ALBEDO = cor;
	EMISSION = vec3(faisca) * 0.5;
	ROUGHNESS = mix(mix(0.8, 0.2, varrido), 0.9, parede);
	SPECULAR = mix(0.45, 0.3, parede);
}
