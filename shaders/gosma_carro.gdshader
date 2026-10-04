shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;
// Gosma grudada no carro (cuspe dos dinossauros do Extinction Day; o dono achou as placas soltas "bolas"):
// uma película por cima da própria lataria, que acompanha a forma do carro — poças
// grossas no teto, no capô e na tampa, um lençol na parte alta das laterais e fios que escorrem dele
// para baixo, cada um com um comprimento, engrossando na ponta. Tudo no espaço do carro (para_carro),
// para a meleca não nadar quando ele anda ou vira. Vai numa cópia da malha fora da camada da faixa da
// equipe (Veiculo.gosma): por cima da própria malha, a faixa era pintada em cima da gosma.

uniform mat4 para_carro;          // da malha para o espaço do carro
uniform vec3 caixa_centro;        // caixa da carroceria (espaço do carro)
uniform vec3 caixa_meia = vec3(1.0);
uniform float avanco = 1.0;       // 0 = acabou de ser atingido, 1 = já escorreu tudo
uniform float some = 0.0;         // 0..1: a gosma afina e vai embora no fim do efeito
uniform float luz = 0.3;          // um mínimo de luz própria (as etapas são à noite)

varying vec3 p_carro;
varying vec3 n_carro;

float sorteio(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

float ruido(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(sorteio(i), sorteio(i + vec3(1, 0, 0)), f.x), mix(sorteio(i + vec3(0, 1, 0)), sorteio(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(sorteio(i + vec3(0, 0, 1)), sorteio(i + vec3(1, 0, 1)), f.x), mix(sorteio(i + vec3(0, 1, 1)), sorteio(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Espessura da gosma (0 = lataria limpa) no ponto p do carro, com a normal n
float espessura(vec3 p, vec3 n) {
	vec3 q = (p - caixa_centro) / caixa_meia;   // -1..1 na caixa da carroceria
	float cima = smoothstep(0.2, 0.7, n.y);
	float lado = 1.0 - smoothstep(0.45, 0.85, abs(n.y));
	// Poças em cima: manchas grandes de borda irregular, que se arrastam devagar
	float m = ruido(p * 3.1 + vec3(0.0, TIME * 0.04, TIME * 0.02)) * 0.7 + ruido(p * 7.0 + 9.0) * 0.3;
	float poca = smoothstep(0.52, 0.66, m + 0.08 * avanco);
	// Fios nas laterais: o sorteio só depende de onde se está ao longo da lataria (não da altura)
	vec3 col = vec3(p.x, 0.0, p.z) * 9.0;
	float fio = clamp((ruido(col) - 0.56) * 7.0, 0.0, 1.0);
	float comp = (0.25 + 1.55 * ruido(col * 0.45 + 17.0)) * avanco;
	float d = q.y - (1.0 - comp);   // acima da ponta do fio
	float pinga = fio * smoothstep(-0.02, 0.1, d) * (0.6 + 0.4 * smoothstep(0.4, 0.0, d));
	float lencol = smoothstep(0.78, 1.0, q.y + (ruido(col * 0.35 + 5.0) - 0.5) * 0.6) * avanco;
	float e = max(poca * cima, max(pinga, lencol) * lado);
	e *= smoothstep(-0.55, -0.2, n.y);   // nada por baixo do carro
	return clamp(e * (1.0 + some) - some * 1.6, 0.0, 1.0);
}

void vertex() {
	p_carro = (para_carro * vec4(VERTEX, 1.0)).xyz;
	n_carro = mat3(para_carro) * NORMAL;
	// Um nada para fora da lataria (em metros, qualquer que seja a escala da malha)
	VERTEX += NORMAL * (0.012 / max(length(para_carro[0].xyz), 0.001));
}

void fragment() {
	float e = espessura(p_carro, normalize(n_carro));
	// Relevo: a normal inclina na borda de cada poça e de cada fio (meleca grossa, não tinta)
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(e) * r1 + dFdy(e) * r2);
	NORMAL = normalize(abs(det) * NORMAL - 0.09 * grad);
	float beira = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	vec3 cor = mix(vec3(0.36, 0.6, 0.05), vec3(0.08, 0.24, 0.01), smoothstep(0.15, 0.8, e));
	cor = mix(cor, vec3(0.55, 0.88, 0.15), beira * 0.6);
	ALBEDO = cor;
	ROUGHNESS = 0.07;
	SPECULAR = 0.9;
	EMISSION = cor * luz;
	ALPHA = smoothstep(0.05, 0.3, e) * 0.97;
}
