shader_type spatial;
// Yeti pronto (assets/frozen/animais/yeti/yeti_modelo.glb, CC-BY sudo-self) — o modelo não tem esqueleto,
// então os braços e as pernas são dobrados aqui (Yeti._pose_modelo manda os ângulos). Espaço da malha
// original: de frente para +Z, X = lado esquerdo do yeti, Y = cima, ~1,9 m, centro na origem.
// Cada braço: cotovelo dobra o antebraço; depois o ombro gira o braço inteiro (para a frente e para fora).
// Cada perna gira no quadril. Os pesos saem da posição de descanso (as regiões do corpo do modelo).

uniform sampler2D tex_cor : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool tem_normal = false;
// x = braço para a frente (rad), y = braço para fora, z = cotovelo (dobra para a frente)
uniform vec3 braco_e = vec3(0.0);   // braço do lado +X
uniform vec3 braco_d = vec3(0.0);   // braço do lado -X
uniform vec2 pernas = vec2(0.0);    // perna +X, perna -X: para a frente (rad)
uniform float maos = 0.0;           // 0..1: fecha as mãos (garra), encolhendo os dedos para dentro

// "Ossos" (segmentos) no espaço da malha, lado +X; cada vértice vai para o osso mais perto (com a grossura)
const vec3 OMBRO = vec3(0.43, 0.38, 0.0);
const vec3 COTOVELO = vec3(0.62, 0.08, 0.05);
const vec3 PULSO = vec3(0.6, -0.2, 0.1);
const vec3 DEDOS = vec3(0.58, -0.44, 0.12);
const vec3 QUADRIL = vec3(0.27, -0.3, 0.0);
const vec3 PE = vec3(0.27, -0.92, 0.05);
const float R_BRACO = 0.13;
const float R_TRONCO = 0.33;
const float R_PERNA = 0.15;

mat3 rx(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, c, s), vec3(0.0, -s, c)); }
mat3 rz(float a) { float c = cos(a); float s = sin(a); return mat3(vec3(c, s, 0.0), vec3(-s, c, 0.0), vec3(0.0, 0.0, 1.0)); }

float seg(vec3 p, vec3 a, vec3 b) {
	vec3 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return length(p - (a + ab * t));
}

void vertex() {
	vec3 p = VERTEX;
	float lado = p.x >= 0.0 ? 1.0 : -1.0;
	vec3 q = vec3(abs(p.x), p.y, p.z);   // tudo do lado +X
	float d_cima = seg(q, OMBRO, COTOVELO) - R_BRACO;
	float d_ante = min(seg(q, COTOVELO, PULSO), seg(q, PULSO, DEDOS)) - R_BRACO * 0.85;
	float d_braco = min(d_cima, d_ante);
	float d_tronco = seg(vec3(p.x, p.y, p.z), vec3(0.0, 0.6, 0.0), vec3(0.0, -0.3, 0.05)) - R_TRONCO;
	float d_perna = seg(q, QUADRIL, PE) - R_PERNA;
	float w_braco = smoothstep(0.05, -0.05, d_braco - min(d_tronco, d_perna));
	float w_ante = w_braco * smoothstep(0.03, -0.03, d_ante - d_cima);
	float w_mao = w_braco * smoothstep(-0.16, -0.3, p.y);
	float w_perna = smoothstep(0.05, -0.05, d_perna - min(d_tronco, d_braco)) * smoothstep(-0.2, -0.4, p.y);
	vec3 ang = lado > 0.0 ? braco_e : braco_d;
	vec3 om = vec3(OMBRO.x * lado, OMBRO.y, OMBRO.z);
	vec3 co = vec3(COTOVELO.x * lado, COTOVELO.y, COTOVELO.z);
	mat3 r_cot = rx(-ang.z);
	mat3 r_omb = rz(lado * ang.y) * rx(-ang.x);
	vec3 v = p;
	vec3 n = NORMAL;
	// Garra: a ponta da mão encolhe para a palma (para dentro e para a frente)
	v += vec3(-lado * 0.04, 0.05, 0.05) * w_mao * maos;
	v = mix(v, co + r_cot * (v - co), w_ante);
	n = mix(n, r_cot * n, w_ante);
	v = mix(v, om + r_omb * (v - om), w_braco);
	n = mix(n, r_omb * n, w_braco);
	float pa = lado > 0.0 ? pernas.x : pernas.y;
	vec3 qd = vec3(QUADRIL.x * lado, QUADRIL.y, QUADRIL.z);
	mat3 r_q = rx(-pa);
	v = mix(v, qd + r_q * (v - qd), w_perna);
	n = mix(n, r_q * n, w_perna);
	VERTEX = v;
	NORMAL = normalize(n);
}

void fragment() {
	vec4 c = texture(tex_cor, UV);
	ALBEDO = c.rgb;
	if (tem_normal) {
		NORMAL_MAP = texture(tex_normal, UV).rgb;
	}
	ROUGHNESS = 0.8;
	SPECULAR = 0.35;
	RIM = 0.3;
	RIM_TINT = 0.3;
}
