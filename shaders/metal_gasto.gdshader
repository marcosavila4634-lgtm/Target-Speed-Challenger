shader_type spatial;
// Aço pintado e envelhecido (coordenadas do mundo, serve para peças instanciadas):
// tinta desbotada com lascas, manchas de ferrugem, escorridos de ferrugem descendo,
// poeira alaranjada subindo do chão e arranhões claros.

uniform vec3 cor_tinta : source_color = vec3(0.3, 0.31, 0.3);
uniform vec3 cor_ferrugem : source_color = vec3(0.42, 0.17, 0.06);
uniform vec3 cor_ferrugem_clara : source_color = vec3(0.62, 0.3, 0.1);
uniform vec3 cor_poeira : source_color = vec3(0.66, 0.42, 0.26);
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float ferrugem = 0.45;          // 0 = nova, 1 = muito enferrujada
uniform float altura_chao = 0.0;        // y do chão no mundo (poeira)
uniform float altura_poeira = 6.0;

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(vec3 p, vec3 n, float escala) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return texture(ruido, p.yz / escala).r * w.x + texture(ruido, p.xz / escala).r * w.y + texture(ruido, p.xy / escala).r * w.z;
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 n = normal_mundo;
	float grande = tri(p, n, 9.0);
	float fino = tri(p, n, 1.3);

	vec3 cor = cor_tinta * (0.85 + 0.25 * grande);
	float rug = 0.55;
	float metal = 0.35;

	// Manchas de ferrugem onde a tinta lascou
	float mancha = smoothstep(1.0 - ferrugem * 0.8, 1.05 - ferrugem * 0.55, grande * 0.7 + fino * 0.45);
	vec3 oxido = mix(cor_ferrugem, cor_ferrugem_clara, fino);
	cor = mix(cor, oxido, mancha);
	rug = mix(rug, 0.95, mancha);
	metal = mix(metal, 0.1, mancha);

	// Escorridos de ferrugem descendo nas faces verticais
	float vertical = 1.0 - abs(n.y);
	float corrido = texture(ruido, vec2((p.x + p.z) / 1.1, p.y / 14.0)).r;
	float escorre = smoothstep(0.62, 0.8, corrido) * vertical * ferrugem;
	cor = mix(cor, cor_ferrugem * 0.8, escorre * 0.7);

	// Arranhões e lascas claras (metal exposto)
	float risco = smoothstep(0.9, 0.97, texture(ruido, vec2(p.x * 0.7 + p.y * 3.0, p.z * 0.7) / 0.6).r);
	cor = mix(cor, vec3(0.62, 0.6, 0.57), risco * (1.0 - mancha) * 0.6);
	metal = mix(metal, 0.9, risco * (1.0 - mancha));

	// Poeira do chão e sujeira acumulada em faces de cima
	float poeira = smoothstep(altura_poeira, 0.0, p.y - altura_chao) * (0.6 + 0.4 * fino);
	poeira = max(poeira, smoothstep(0.7, 1.0, n.y) * 0.35 * grande);
	cor = mix(cor, cor_poeira, poeira * 0.75);
	rug = mix(rug, 1.0, poeira);

	ALBEDO = cor;
	ROUGHNESS = rug;
	METALLIC = metal;
}
