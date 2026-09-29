shader_type spatial;
// Faixa de advertência amarela e preta em diagonal (coordenadas do mundo), pintura gasta
// com lascas mostrando o aço por baixo.

uniform vec3 cor_a : source_color = vec3(0.95, 0.72, 0.08);
uniform vec3 cor_b : source_color = vec3(0.04, 0.04, 0.045);
uniform float largura_listra = 0.35;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 an = abs(normal_mundo);
	float h = an.x > an.z ? p.z : p.x;
	float listra = step(0.5, fract((h + p.y) / (largura_listra * 2.0)));
	vec3 cor = mix(cor_a, cor_b, listra);
	float r = texture(ruido, vec2(h, p.y) / 1.7).r;
	float lasca = smoothstep(0.72, 0.8, r + texture(ruido, vec2(h, p.y) / 0.25).r * 0.25);
	cor = mix(cor, vec3(0.35, 0.33, 0.31), lasca);
	cor *= 0.85 + 0.25 * r;
	ALBEDO = cor;
	ROUGHNESS = mix(0.5, 0.8, lasca);
	METALLIC = mix(0.1, 0.7, lasca);
}
