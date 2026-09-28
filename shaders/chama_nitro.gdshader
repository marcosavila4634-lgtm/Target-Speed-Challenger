shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Chama do nitro saindo do escapamento. Malha: cilindro de raio 1 e altura 1 (eixo Y = sentido do jato).
// O vértice dá a forma (bojo logo após o cano, afinando até a ponta, com turbulência);
// o fragmento faz o núcleo branco-azulado, o corpo azul, a borda violeta e os "diamantes de choque".

uniform float intensidade : hint_range(0.0, 1.5) = 1.0;   // 0 = apagada; > 1 = estouro da ignição
uniform float comprimento = 1.3;
uniform float raio = 0.095;
uniform float semente = 0.0;
uniform bool nucleo = false;                              // cone interno, mais curto e mais claro
uniform vec3 cor_nucleo : source_color = vec3(0.85, 0.95, 1.0);
uniform vec3 cor_corpo : source_color = vec3(0.15, 0.45, 1.0);
uniform vec3 cor_borda : source_color = vec3(0.35, 0.15, 0.9);

varying float t_len;   // 0 no cano, 1 na ponta
varying float turb;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float ruido(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	t_len = clamp(VERTEX.y + 0.5, 0.0, 1.0);
	float tempo = TIME * 38.0 + semente * 17.0;
	// Tremulação rápida do comprimento e ondulação lateral crescente para a ponta
	float pulso = 0.82 + 0.18 * ruido(vec2(tempo * 0.35, semente)) + 0.08 * sin(tempo * 1.7);
	float len = comprimento * pulso * clamp(intensidade, 0.0, 1.5) * (nucleo ? 0.45 : 1.0);
	float perfil = (0.55 + 1.1 * sin(3.14159 * min(t_len * 1.6, 1.0) * 0.5)) * pow(1.0 - t_len, 0.65);
	float r = raio * perfil * (nucleo ? 0.55 : 1.0) * (0.7 + 0.3 * clamp(intensidade, 0.0, 1.0));
	turb = ruido(vec2(t_len * 6.0 - tempo * 0.9, semente * 3.0 + VERTEX.x * 2.0));
	vec2 desvio = vec2(ruido(vec2(tempo * 0.6 - t_len * 4.0, semente)) - 0.5,
			ruido(vec2(semente + 9.0, tempo * 0.6 - t_len * 4.0)) - 0.5) * raio * 1.6 * t_len * t_len;
	VERTEX = vec3(VERTEX.x * r * (0.85 + 0.3 * turb) + desvio.x, t_len * len, VERTEX.z * r * (0.85 + 0.3 * turb) + desvio.y);
}

void fragment() {
	// Borda macia: quanto mais de lado a superfície é vista, mais transparente (aparência de volume)
	float frente = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float volume = pow(frente, nucleo ? 1.2 : 1.8);
	// Diamantes de choque: faixas claras na primeira metade do jato
	float diamantes = pow(0.5 + 0.5 * cos(t_len * 34.0 - TIME * 6.0), 6.0) * smoothstep(0.62, 0.05, t_len) * 0.9;
	vec3 cor;
	if (nucleo) {
		cor = mix(cor_nucleo, cor_corpo, smoothstep(0.1, 0.9, t_len));
	} else {
		cor = mix(mix(cor_nucleo, cor_corpo, smoothstep(0.0, 0.3, t_len)), cor_borda, smoothstep(0.45, 1.0, t_len));
	}
	cor += cor_nucleo * diamantes * (nucleo ? 0.6 : 0.35);
	// Some na ponta, com a borda "rasgada" pela turbulência
	float fim = smoothstep(1.0, 0.55 - turb * 0.35, t_len);
	float inicio = smoothstep(0.0, 0.04, t_len);
	float a = volume * fim * inicio * (0.65 + 0.5 * turb) * clamp(intensidade, 0.0, 1.5);

	ALBEDO = cor * a * (nucleo ? 3.2 : 2.2);   // unshaded + aditivo: valores > 1 viram brilho (glow)
}
