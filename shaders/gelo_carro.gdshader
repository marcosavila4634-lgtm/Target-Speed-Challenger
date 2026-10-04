shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Crosta de gelo no carro atingido pelo cuspe das focas (Frozen Peak, Veiculo.gelo_cuspe): geada branca e
// placas de gelo azulado por cima da própria lataria, mais grossas em cima e no lado virado para a foca,
// com cristais brilhando. Vai numa cópia da malha (como a gosma) e cresce/derrete com `quanto`.

uniform mat4 para_carro;        // da malha para o espaço do carro
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float quanto = 1.0;

varying vec3 p_carro;
varying vec3 n_carro;

void vertex() {
	p_carro = (para_carro * vec4(VERTEX, 1.0)).xyz;
	n_carro = mat3(para_carro) * NORMAL;
	VERTEX += NORMAL * (0.015 / max(length(para_carro[0].xyz), 0.001));
}

void fragment() {
	vec3 n = normalize(n_carro);
	vec3 p = p_carro;
	float m = texture(ruido, p.xz * 0.9 + p.y * 0.3).r * 0.6 + texture(ruido, p.zy * 2.3 + 0.4).r * 0.4;
	float cima = smoothstep(-0.2, 0.6, n.y);
	float e = smoothstep(0.7 - quanto * 0.55 - cima * 0.25, 0.75 - quanto * 0.45 - cima * 0.25, m);
	float agulha = 1.0 - smoothstep(0.0, 0.03, abs(texture(ruido, p.xz * 4.0 + p.y).r - 0.5));
	vec3 cor = mix(vec3(0.55, 0.8, 0.97), vec3(0.94, 0.98, 1.0), smoothstep(0.45, 0.8, m));
	cor = mix(cor, vec3(1.0), agulha * 0.6);
	float beira = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = cor;
	ROUGHNESS = mix(0.1, 0.55, m);
	SPECULAR = 0.9;
	EMISSION = vec3(0.35, 0.65, 0.9) * (0.12 + beira * 0.3 + agulha * 0.3);
	ALPHA = e * 0.92 * smoothstep(0.0, 0.1, quanto);
}
