shader_type spatial;
render_mode cull_disabled;
// Tampo do alvo de gelo (Frozen Peak, etapa 2: disco fixo, enorme e escorregadio): gelo polido azul
// com trincas brancas e bolhas presas, os anéis da mosca vistos por baixo do gelo (vermelho apagado),
// geada soprada nas bordas. Laterais e face de baixo de gelo bruto.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float raio = 70.0;
uniform float aneis = 7.0;

varying vec3 pos_local;
varying vec3 normal_local;
varying vec3 normal_mundo;

void vertex() {
	pos_local = VERTEX;
	normal_local = NORMAL;
	normal_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float rn(vec2 uv) {
	return clamp((texture(ruido, uv).r - 0.5) * 2.4 + 0.5, 0.0, 1.0);
}

void fragment() {
	float r = length(pos_local.xz);
	float k = floor(r / raio * aneis);
	float g = rn(pos_local.xz / 60.0);
	float m = rn(pos_local.xz / 11.0);
	float f = rn(pos_local.xz / 2.2);
	vec3 gelo = mix(vec3(0.1, 0.36, 0.62), vec3(0.42, 0.72, 0.9), g * 0.6 + m * 0.4);
	// Anéis da mosca por baixo do gelo
	gelo = mix(gelo, vec3(0.62, 0.1, 0.1), (1.0 - mod(k, 2.0)) * 0.38);
	gelo = mix(gelo, vec3(0.8, 0.1, 0.08), (1.0 - step(raio / aneis * 0.5, r)) * 0.3);
	// Trincas (linhas de nível do ruído) e bolhas
	float trinca = 1.0 - smoothstep(0.0, 0.05, abs(sin(m * 13.0 + g * 9.0)));
	float fina = (1.0 - smoothstep(0.0, 0.08, abs(sin(f * 9.0)))) * 0.4;
	gelo = mix(gelo, vec3(0.9, 0.96, 1.0), clamp(trinca * 0.75 + fina, 0.0, 1.0));
	// Geada soprada pelo vento e na beirada
	float geada = smoothstep(0.6, 0.85, rn(pos_local.xz / 23.0 + 3.0)) * 0.5 + smoothstep(raio * 0.9, raio, r) * 0.6;
	gelo = mix(gelo, vec3(0.93, 0.96, 1.0), clamp(geada, 0.0, 1.0));
	float topo = step(0.5, normal_local.y);
	vec3 bruto = mix(vec3(0.06, 0.24, 0.5), vec3(0.3, 0.6, 0.85), m) * (0.8 + 0.4 * f);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(normal_mundo), 0.0)).xyz);
	ALBEDO = mix(bruto, gelo, topo);
	ROUGHNESS = mix(0.35, mix(0.06, 0.45, clamp(geada + trinca * 0.5, 0.0, 1.0)), topo);
	METALLIC = 0.1;
	SPECULAR = 0.75;
	EMISSION = ALBEDO * 0.06;
}
