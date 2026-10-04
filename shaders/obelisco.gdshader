shader_type spatial;
// Obelisco de granito rosa de Assuã (Pharaoh's Climb): malha unitária (base 1 x 1, altura 1, ponta
// dourada em cima) escalada por instância. Três colunas de hieróglifos entalhados em cada face,
// granito salpicado (feldspato rosa, quartzo, mica preta), base gasta e a ponta de electro dourada.

#include "res://shaders/glifos.gdshaderinc"

uniform float inicio_ponta = 0.94;   // y local onde começa a ponta (pirâmide dourada)
uniform vec3 cor_granito : source_color = vec3(0.62, 0.38, 0.32);
uniform vec3 cor_granito_b : source_color = vec3(0.45, 0.26, 0.23);
uniform vec3 cor_ouro : source_color = vec3(1.0, 0.76, 0.33);
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 local;
varying vec3 escala;
varying vec3 normal_local;
varying vec3 pos_mundo;
varying vec3 n_mundo;
varying vec3 lado_mundo;

void vertex() {
	escala = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	local = VERTEX;
	normal_local = NORMAL;
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	n_mundo = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 lado = abs(NORMAL.x) > abs(NORMAL.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
	lado_mundo = normalize((MODEL_MATRIX * vec4(lado, 0.0)).xyz);
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	vec3 m = local * escala;   // metros no corpo do obelisco
	vec3 nl = normalize(normal_local);
	float dist = length(pos_mundo - CAMERA_POSITION_WORLD);
	float perto = smoothstep(1500.0, 40.0, dist);
	float aa = max(dist * 0.0012, 0.003);
	// Face: x ao longo dela (metros do eixo), y = altura
	bool face_x = abs(nl.x) > abs(nl.z);
	float u = face_x ? m.z * sign(nl.x) : -m.x * sign(nl.z);
	float face_id = face_x ? (nl.x > 0.0 ? 0.0 : 1.0) : (nl.z > 0.0 ? 2.0 : 3.0);
	bool ponta = local.y > inicio_ponta - 0.0005;
	// Granito salpicado
	vec2 q = vec2(u, m.y);
	float g1 = texture(ruido, q / 0.9 + face_id * 3.1).r;
	float g2 = texture(ruido, q / 0.23 + face_id * 7.7).r;
	vec3 cor = mix(cor_granito, cor_granito_b, smoothstep(0.35, 0.7, g1));
	cor = mix(cor, vec3(0.1, 0.08, 0.08), smoothstep(0.7, 0.78, g2) * 0.8 * perto);   // mica preta
	cor = mix(cor, vec3(0.86, 0.8, 0.76), smoothstep(0.24, 0.16, g2) * 0.6 * perto);  // quartzo
	// Largura da face nesta altura (o obelisco afina): 3 colunas de hieróglifos
	float meia = 0.5 * escala.x * mix(1.0, 0.66, clamp(local.y / inicio_ponta, 0.0, 1.0));
	float larg_col = meia * 2.0 * 0.24;
	float glifos = 0.0;
	float moldura = 0.0;
	for (int k = -1; k <= 1; k++) {
		float centro = float(k) * meia * 0.62;
		vec2 g = coluna_glifos(vec2(u - centro, m.y - escala.x * 0.6), larg_col, face_id * 11.0 + float(k) + 5.0, aa);
		float alto = 1.0 - smoothstep(escala.y * inicio_ponta - meia * 1.4, escala.y * inicio_ponta - meia * 1.2, m.y);
		float baixo = smoothstep(escala.x * 0.5, escala.x * 0.6, m.y);
		glifos = max(glifos, g.x * alto * baixo);
		moldura = max(moldura, g.y * alto * baixo);
	}
	cor *= 1.0 - 0.42 * glifos - 0.2 * moldura;
	// Gasto: base mais clara de areia, escorridos escuros
	float esc = texture(ruido, vec2(u / 4.0, m.y / 60.0) + face_id).r;
	cor = mix(cor, cor * 0.7, smoothstep(0.6, 0.85, esc) * 0.6);
	cor = mix(cor, vec3(0.82, 0.65, 0.44), (1.0 - smoothstep(0.0, 3.0 + escala.x * 0.2, m.y)) * 0.6);
	vec3 nn = normalize(n_mundo);
	nn += (lado_mundo * (g1 - 0.5) + vec3(0.0, g2 - 0.5, 0.0)) * 0.12 * perto;
	nn += vec3(0.0, 1.0, 0.0) * glifos * 0.3 * perto;   // entalhe pega luz por cima
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
	ALBEDO = cor;
	ROUGHNESS = 0.5 - 0.15 * g1;
	SPECULAR = 0.45;
	if (ponta) {
		// Ponta de electro: ouro polido com marcas leves
		float r = texture(ruido, m.xy / 3.0 + m.zy / 3.0).r;
		ALBEDO = cor_ouro * (0.85 + 0.25 * r);
		METALLIC = 1.0;
		ROUGHNESS = 0.32 + 0.15 * r;
		EMISSION = cor_ouro * 0.4;   // brilha ao pôr do sol (o reflexo do céu deixava o ouro esverdeado)
		SPECULAR = 0.6;
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(n_mundo), 0.0)).xyz);
	}
}
