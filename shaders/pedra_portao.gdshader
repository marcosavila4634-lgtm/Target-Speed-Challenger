shader_type spatial;
// Pedra entalhada do portão principal do Serpent's Climb (PortaoSelva), em coordenadas do mundo
// (triplanar, não precisa de UV): calcário dourado com manchas grandes, veios, poros e rachaduras
// finas, relevo de pedra picada (a luz rasante mostra a textura), sujeira escorrida, base mais
// escura e musgo nas faces de cima e em manchas perto do chão.
// juntas = 1: alvenaria (fiadas de blocos com juntas fundas e tom por bloco); 0: pedra inteira.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_clara : source_color = vec3(0.6, 0.53, 0.4);
uniform vec3 cor_escura : source_color = vec3(0.31, 0.26, 0.19);
uniform vec3 cor_musgo : source_color = vec3(0.17, 0.27, 0.07);
uniform float juntas = 0.0;
uniform float fiada = 1.15;
uniform float bloco = 1.9;
uniform float musgo = 1.0;
uniform float relevo = 1.0;
uniform float altura_chao = 6.5;

varying vec3 pm;
varying vec3 nm;

void vertex() {
	pm = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	nm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

float tri(vec3 p, vec3 w, float esc) {
	return texture(ruido, p.zy * esc).r * w.x + texture(ruido, p.xz * esc).r * w.y + texture(ruido, p.xy * esc).r * w.z;
}

void fragment() {
	vec3 n = normalize(nm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	float dist = length(pm - CAMERA_POSITION_WORLD);
	float perto = smoothstep(260.0, 30.0, dist);
	float grande = tri(pm, w, 0.031);
	float medio = tri(pm + vec3(3.7, 1.3, 8.1), w, 0.16);
	float fino = tri(pm + vec3(9.1, 5.2, 2.6), w, 0.83);
	float grao = tri(pm + vec3(1.9, 7.7, 4.4), w, 3.1);
	float tom = grande * 0.5 + medio * 0.34 + fino * 0.16;
	vec3 cor = mix(cor_escura, cor_clara, smoothstep(0.3, 0.72, tom));
	// Veios mais claros e poros escuros
	cor = mix(cor, cor_clara * 1.12, smoothstep(0.035, 0.0, abs(medio - 0.62)) * 0.35);
	float poro = smoothstep(0.68, 0.8, fino) * perto;
	cor *= 1.0 - 0.2 * poro;
	// Rachaduras finas (só onde a mancha grande deixa)
	float racha = smoothstep(0.014, 0.0, abs(medio - 0.47)) * smoothstep(0.5, 0.62, grande) * perto;
	cor *= 1.0 - 0.5 * racha;
	float altura = medio * 0.5 + fino * 0.35 + grao * 0.15 - poro * 0.25 - racha * 0.6;
	float horizontal = smoothstep(0.6, 0.9, n.y);
	if (juntas > 0.5 && horizontal < 0.5) {
		vec2 t2 = normalize(vec2(-n.z, n.x) + vec2(1e-5));
		float ao_longo = dot(pm.xz, t2);
		float id_fiada = floor((pm.y + 0.01) / fiada);
		float v = fract((pm.y + 0.01) / fiada);
		float comp = bloco * (0.7 + 0.6 * h21(vec2(id_fiada, 9.0)));
		float u0 = (ao_longo + h21(vec2(id_fiada, 3.0)) * bloco) / comp;
		float id_bloco = floor(u0);
		float u = fract(u0);
		cor *= 0.84 + 0.3 * h21(vec2(id_bloco, id_fiada));
		float borda = min(min(u, 1.0 - u) * comp, min(v, 1.0 - v) * fiada) + (fino - 0.5) * 0.04;
		float junta = 1.0 - smoothstep(0.015, 0.07, borda);
		cor *= 1.0 - 0.6 * junta;
		altura -= junta * 1.6;
		altura += (1.0 - smoothstep(0.0, 0.16, borda)) * -0.5;
	}
	// Sujeira escorrida das beiradas e base escurecida pela umidade
	float escorre = tri(pm * vec3(1.0, 0.08, 1.0), w, 0.33);
	cor *= 1.0 - 0.28 * smoothstep(0.56, 0.8, escorre) * (1.0 - horizontal);
	cor *= mix(0.74, 1.0, smoothstep(altura_chao + 0.5, altura_chao + 14.0, pm.y));
	// Musgo: faces de cima, juntas e manchas (mais perto do chão)
	float m = horizontal * 0.85 + (1.0 - smoothstep(altura_chao, altura_chao + 30.0, pm.y)) * 0.42 + 0.14;
	m *= smoothstep(0.44, 0.64, tri(pm + vec3(5.0, 2.0, 7.0), w, 0.09) * 0.75 + fino * 0.25) * musgo;
	m = clamp(m, 0.0, 1.0);
	cor = mix(cor, cor_musgo * (0.7 + 0.6 * fino), m * 0.9);
	ALBEDO = cor;
	ROUGHNESS = mix(0.86, 0.97, m);
	// Relevo da pedra picada: a normal segue o gradiente da altura (derivadas na tela)
	altura += m * 0.5;
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	float dhx = dFdx(altura);
	float dhy = dFdy(altura);
	vec3 nv = normalize(NORMAL);
	vec3 r1 = cross(dpy, nv);
	vec3 r2 = cross(nv, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * nv - 0.06 * relevo * perto * grad);
}
