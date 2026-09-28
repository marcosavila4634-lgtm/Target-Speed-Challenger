shader_type spatial;
// Piso do hangar: concreto escuro polido em placas, com juntas, manchas e partes mais brilhantes
// (reflete as luzes e os anéis azuis via SSR).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 pos_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = pos_mundo.xz;
	vec2 f = fract(p / 4.0);
	float junta = 1.0 - step(0.012, f.x) * step(f.x, 0.988) * step(0.012, f.y) * step(f.y, 0.988);
	float n = texture(ruido, p / 9.0).r;
	float mancha = texture(ruido, p / 2.3 + 1.7).r;
	vec3 cor = vec3(0.07, 0.075, 0.085) * (0.75 + 0.5 * n);
	cor *= 1.0 - 0.5 * junta;
	ALBEDO = cor;
	METALLIC = 0.3;
	ROUGHNESS = clamp(0.12 + 0.35 * smoothstep(0.45, 0.8, mancha) + 0.3 * junta, 0.0, 1.0);
}
