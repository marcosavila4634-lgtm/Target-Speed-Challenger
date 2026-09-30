shader_type spatial;
// Dormentes de madeira velha (coordenadas do mundo): veios ao longo do comprimento, rachaduras,
// madeira acinzentada pelo sol com o creosoto escuro nas bordas e manchas de ferrugem dos trilhos.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 eixo_veio = vec3(1.0, 0.0, 0.0);   // direção do comprimento dos dormentes (mundo)

varying vec3 p_mundo;
varying vec3 n_mundo;

void vertex() {
	p_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	n_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 across = normalize(cross(vec3(0.0, 1.0, 0.0), eixo_veio));
	float ao_longo = dot(p_mundo, eixo_veio);
	float transv = dot(p_mundo, across) + p_mundo.y;
	float veio = texture(ruido, vec2(ao_longo * 0.08, transv * 6.0)).r;
	float veio_fino = texture(ruido, vec2(ao_longo * 0.3, transv * 22.0)).r;
	float racha = smoothstep(0.74, 0.8, texture(ruido, vec2(ao_longo * 0.05, transv * 3.5 + 0.3)).r);
	float dormente = floor(transv * 0.9);   // cada dormente um tom
	float tom = fract(sin(dormente * 12.9898) * 43758.5453);
	vec3 madeira = mix(vec3(0.17, 0.11, 0.07), vec3(0.3, 0.26, 0.22), 0.3 + 0.4 * tom);   // parte cinza de sol
	madeira *= 0.75 + 0.35 * veio + 0.15 * veio_fino;
	madeira = mix(madeira, vec3(0.05, 0.04, 0.03), racha);
	// Creosoto escuro nas laterais e ferrugem pingada
	madeira = mix(madeira, vec3(0.09, 0.07, 0.05), (1.0 - smoothstep(0.5, 0.9, n_mundo.y)) * 0.6);
	float ferr = smoothstep(0.7, 0.85, texture(ruido, p_mundo.xz * 0.5).r);
	madeira = mix(madeira, vec3(0.42, 0.18, 0.07), ferr * 0.45);
	ALBEDO = madeira;
	ROUGHNESS = 0.92;
	NORMAL_MAP = normalize(vec3(0.5, 0.5 + (veio_fino - 0.5) * 0.6 - racha * 0.4, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.2;
}
