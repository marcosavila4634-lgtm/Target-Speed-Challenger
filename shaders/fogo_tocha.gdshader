shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
// Fogo dos cestos da placa TIRANOSSAURO REX (pedido do dono: fogo mais realista, como o da arte dele):
// labareda alta e rasgada — a coluna inteira entorta com o vento, as línguas sobem em três escalas de
// ruído e se soltam em cima, o miolo é quase branco embaixo e passa por amarelo, laranja e vermelho
// escuro até a ponta, e fagulhas sobem por fora. Quad que gira em volta do eixo vertical para a câmera
// (base em y = 0). `fase` (por instância) faz cada cesto queimar diferente.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float energia = 1.6;

// O ruído da textura fica quase todo perto de 0,5: abre o contraste (sem isso a labareda saía um cone liso)
float rd(vec2 uv) {
	return clamp((texture(ruido, uv).r - 0.5) * 2.6 + 0.5, 0.0, 1.0);
}
instance uniform float fase = 0.0;

void vertex() {
	vec3 origem = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 para = CAMERA_POSITION_WORLD - origem;
	para.y = 0.0;
	para = length(para) > 0.001 ? normalize(para) : vec3(0.0, 0.0, 1.0);
	vec3 lado = normalize(cross(vec3(0.0, 1.0, 0.0), para));
	float esc_x = length(MODEL_MATRIX[0].xyz);
	float esc_y = length(MODEL_MATRIX[1].xyz);
	vec3 mundo = origem + lado * VERTEX.x * esc_x + vec3(0.0, 1.0, 0.0) * VERTEX.y * esc_y;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(mundo, 1.0);
}

void fragment() {
	vec2 p = vec2(UV.x - 0.5, 1.0 - UV.y);   // y: 0 na base, 1 no topo
	float t = TIME * 1.25 + fase * 7.3;
	// Vento e turbulência: a coluna entorta inteira, mais em cima
	float w1 = rd(vec2(p.y * 0.45 - t * 0.33, fase)) - 0.5;
	float w2 = rd(vec2(p.x * 1.1 + fase * 3.0, p.y * 0.9 - t * 0.85)) - 0.5;
	float x = p.x + w1 * 0.34 * p.y * p.y + w2 * 0.3 * p.y;
	// Envelope: bojo logo acima da base, afinando até a ponta
	float env = 0.44 * pow(max(1.0 - p.y, 0.0), 0.55) * smoothstep(-0.02, 0.08, p.y);
	float dentro = 1.0 - smoothstep(env * 0.15, env + 0.001, abs(x));
	// Línguas: ruído em três escalas subindo; quanto mais alto, mais rasgado e solto
	float n1 = rd(vec2(x * 1.5 + fase * 5.0, p.y * 0.8 - t * 1.25));
	float n2 = rd(vec2(x * 3.6 - fase, p.y * 1.9 - t * 2.4));
	float n3 = rd(vec2(x * 8.0 + 0.37, p.y * 4.2 - t * 4.1));
	float f = n1 * 0.55 + n2 * 0.3 + n3 * 0.15;
	float corte = mix(0.22, 0.7, pow(p.y, 0.7));
	float chama = smoothstep(corte - 0.08, corte + 0.14, f * 0.75 + dentro * 0.5) * smoothstep(0.0, 0.25, dentro);
	// Calor: miolo quente embaixo e no eixo, esfriando para cima e para fora
	float eixo = 1.0 - smoothstep(0.0, env * 0.8 + 0.001, abs(x));
	float calor = chama * (1.0 - p.y * 0.85) * (0.35 + 0.65 * eixo) * (0.55 + 0.9 * n2);
	vec3 cor = mix(vec3(0.35, 0.02, 0.0), vec3(0.95, 0.2, 0.02), smoothstep(0.05, 0.3, calor));
	cor = mix(cor, vec3(1.0, 0.5, 0.06), smoothstep(0.3, 0.6, calor));
	cor = mix(cor, vec3(1.0, 0.82, 0.3), smoothstep(0.6, 0.95, calor));
	cor = mix(cor, vec3(1.0, 0.97, 0.8), smoothstep(0.95, 1.3, calor));
	// Fagulhas: pontos acesos que sobem serpenteando por fora da labareda
	vec2 gr = vec2(p.x * 9.0 + sin(p.y * 6.0 + t) * 0.6, p.y * 5.0 - t * 1.7);
	vec2 cel = floor(gr);
	vec2 fr = fract(gr) - 0.5;
	float h = fract(sin(dot(cel, vec2(12.9898, 78.233)) + fase) * 43758.5453);
	float fag = step(0.9, h) * (1.0 - smoothstep(0.0, 0.11, length(fr + (vec2(h, fract(h * 7.0)) - 0.5) * 0.5)));
	fag *= smoothstep(0.25, 0.5, p.y) * (1.0 - smoothstep(0.75, 1.0, p.y)) * (1.0 - smoothstep(0.2, 0.42, abs(p.x)));
	float tremor = 0.9 + 0.1 * sin(t * 11.0) * sin(t * 6.3);
	// (mistura normal, não soma: contra o céu claro a soma lavava a chama para branco)
	ALBEDO = mix(cor * energia * tremor, vec3(1.0, 0.75, 0.3) * 2.0, clamp(fag, 0.0, 1.0));
	ALPHA = clamp(chama * (0.5 + 0.7 * smoothstep(0.0, 0.5, calor)) + fag, 0.0, 1.0);
}
