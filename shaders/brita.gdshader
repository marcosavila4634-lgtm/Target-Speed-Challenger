shader_type spatial;
// Lastro de brita da ferrovia (coordenadas do mundo): pedrinhas cinzentas e ocres com sombra
// entre elas (células), poeira avermelhada do cânion e manchas de ferrugem e óleo.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 p_mundo;

void vertex() {
	p_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec2 hash2(vec2 p) {
	return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

void fragment() {
	vec2 q = p_mundo.xz * 14.0 + vec2(p_mundo.y * 6.0);
	vec2 c = floor(q);
	float d1 = 9.0;
	float d2 = 9.0;
	vec2 id = vec2(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(c + g);
			float d = length(g + o - fract(q));
			if (d < d1) { d2 = d1; d1 = d; id = c + g; }
			else if (d < d2) { d2 = d; }
		}
	}
	float borda = smoothstep(0.0, 0.18, d2 - d1);     // sombra entre as pedras
	float tom = hash2(id).x;
	vec3 pedra = mix(vec3(0.2, 0.19, 0.18), vec3(0.34, 0.28, 0.22), tom) * (0.85 + 0.3 * hash2(id + 7.0).y);
	vec3 cor = pedra * mix(0.55, 1.0, borda);
	float poeira = smoothstep(0.4, 0.8, texture(ruido, p_mundo.xz * 0.06).r);
	cor = mix(cor, vec3(0.62, 0.42, 0.29), poeira * 0.45);
	float oleo = smoothstep(0.72, 0.85, texture(ruido, p_mundo.xz * 0.15 + 3.1).r);
	cor = mix(cor, vec3(0.1, 0.07, 0.05), oleo * 0.5);
	ALBEDO = cor;
	ROUGHNESS = 0.95;
	NORMAL_MAP = normalize(vec3(0.5 + (hash2(id).x - 0.5) * 0.4, 0.5 + (hash2(id).y - 0.5) * 0.4, 0.6 + 0.4 * borda)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.5;
}
