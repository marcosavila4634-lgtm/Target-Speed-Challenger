shader_type spatial;
render_mode cull_disabled;
// Tampo dos alvos de forma livre do Frozen Peak (disco, cruz, anel, triângulo): anéis vermelhos e
// brancos como uma mosca, medidos do centro do alvo (a forma recorta os anéis), tinta gasta e geada
// nas bordas. As faces laterais e de baixo são de aço escuro.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float raio = 15.0;         // raio do círculo que contém a forma
uniform float aneis = 5.0;
uniform vec3 cor_vermelho : source_color = vec3(0.8, 0.07, 0.06);
uniform vec3 cor_branco : source_color = vec3(0.93, 0.94, 0.95);

varying vec3 pos_local;
varying vec3 normal_local;
varying vec3 normal_mundo;

void vertex() {
	pos_local = VERTEX;
	normal_local = NORMAL;
	normal_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float r = length(pos_local.xz);
	float k = floor(r / raio * aneis);
	vec3 cor = mix(cor_vermelho, cor_branco, mod(k, 2.0));
	float n = texture(ruido, pos_local.xz / 7.0).r;
	float fino = texture(ruido, pos_local.xz / 1.3).r;
	// Tinta gasta e riscos de pneu
	cor = mix(cor, vec3(0.3, 0.32, 0.35), smoothstep(0.62, 0.85, n) * 0.45);
	cor *= 0.9 + 0.2 * fino;
	// Geada soprada
	cor = mix(cor, vec3(0.9, 0.95, 1.0), smoothstep(0.55, 0.8, texture(ruido, pos_local.xz / 17.0 + 4.0).r) * 0.35);
	float topo = step(0.5, normal_local.y);
	vec3 aco = vec3(0.13, 0.15, 0.19) * (0.8 + 0.4 * fino);
	// Normal sempre a que a malha deu (cull_disabled inverteria a das faces de trás)
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(normal_mundo), 0.0)).xyz);
	ALBEDO = mix(aco, cor, topo);
	ROUGHNESS = mix(0.4, 0.7, topo);
	METALLIC = mix(0.8, 0.05, topo);
}
