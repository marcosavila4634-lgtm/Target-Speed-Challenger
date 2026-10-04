shader_type spatial;
// Pelo do yeti do Frozen Peak (Yeti). Textura presa à pele parada (CUSTOM0 = posição de descanso).
// Pelo branco-creme com sombra azulada entre as mechas, mechas em relevo escorrendo para baixo
// (normal pela derivada), geada brilhando; cara, palmas e solas de couro cinza-azulado.
// `tufo` = 1: as mechas soltas (cones), com a ponta mais clara.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float tufo = 0.0;

varying vec3 p_rest;
varying float ponta;

void vertex() {
	p_rest = CUSTOM0.xyz;
	ponta = clamp(VERTEX.y / 0.32 + 0.5, 0.0, 1.0);
	if (tufo > 0.5) {
		p_rest = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz * 3.0;
	}
}

void fragment() {
	vec3 p = p_rest;
	// Mechas: ruído esticado na vertical, deslocado pela posição em volta do corpo
	float ang = atan(p.x, p.z + 0.001);
	float mecha = texture(ruido, vec2(ang * 1.6 + p.x * 3.0, p.y * 0.9)).r;
	float fina = texture(ruido, vec2(ang * 9.0 + p.z * 11.0, p.y * 2.5)).r;
	vec3 claro = vec3(0.8, 0.8, 0.79);
	vec3 sombra = vec3(0.38, 0.44, 0.55);
	float vale = smoothstep(0.35, 0.7, mecha * 0.6 + fina * 0.4);
	vec3 cor = mix(sombra, claro, vale);
	// Couro: cara (frente da cabeça), palmas e solas
	float cara = smoothstep(0.4, 0.5, p.z) * smoothstep(2.1, 2.2, p.y) * smoothstep(0.2, 0.12, abs(p.x));
	float mao = smoothstep(0.62, 0.52, p.y) * smoothstep(0.7, 0.78, abs(p.x));
	float pe = smoothstep(0.12, 0.06, p.y) * step(0.12, p.z);
	float couro = max(cara, max(mao, pe)) * (1.0 - tufo);
	cor = mix(cor, vec3(0.32, 0.38, 0.46) * (0.85 + 0.3 * fina), couro);
	if (tufo > 0.5) {
		cor = mix(sombra * 0.95, claro * 1.03, ponta);
	}
	float geada = step(0.92, texture(ruido, p.xy * 3.1 + p.z).r) * (1.0 - couro);
	cor = mix(cor, vec3(1.0), geada * 0.6);
	// Relevo das mechas
	float h = (mecha * 0.6 + fina * 0.4) * (1.0 - couro);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
	NORMAL = normalize(abs(det) * NORMAL - 0.035 * grad);
	ALBEDO = cor;
	ROUGHNESS = mix(0.85, 0.45, couro);
	SPECULAR = 0.3;
	RIM = 0.25 * (1.0 - couro);
	RIM_TINT = 0.2;
	BACKLIGHT = vec3(0.25, 0.3, 0.35) * (1.0 - couro);
	EMISSION = vec3(geada) * 0.1;
}
