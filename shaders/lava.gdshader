shader_type spatial;
render_mode cull_disabled;
// Lava (Extinction Day): rios, lagos, cratera e cascatas nas paredes do túnel do vulcão.
// Nada de textura deslizando: o fluxo usa dois tempos defasados (flow map) que se misturam, e a lava
// é feita de placas de crosta escura que se formam enquanto ela anda e racham deixando ver o miolo
// incandescente. Onde corre mais rápido (cascata) a crosta não chega a se formar; nas margens e no fim
// do caminho ela engrossa. O brilho pulsa devagar (o calor não é uniforme).
//   modo 0: lago/rio deitado — UV.y = metros ao longo do fluxo, UV.x = 0..1 de margem a margem
//   modo 1: cascata na parede — UV.y = metros descendo, UV.x = 0..1 de lado a lado (borda recortada)

uniform int modo = 0;
uniform sampler2D tex_base : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_brilho : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float velocidade = 0.35;       // m/s ao longo do fluxo
uniform float escala = 9.0;            // metros por repetição da textura
uniform float calor = 1.0;             // 0 = quase toda crosta, 1 = muito miolo exposto
uniform float energia = 5.5;
uniform float largura = 20.0;          // metros de margem a margem (faixas: UV.x vai de 0 a 1)
uniform bool mundo = false;            // lagos e cratera: textura pela posição no mundo
uniform vec3 cor_quente : source_color = vec3(1.0, 0.36, 0.05);
uniform vec3 cor_miolo : source_color = vec3(1.0, 0.72, 0.28);
uniform vec3 cor_crosta : source_color = vec3(0.045, 0.035, 0.03);

varying vec3 pos_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (modo == 0) {
		// Superfície que estufa devagar (bolhas grandes de lava viscosa), sem ondinhas
		float b = texture(ruido, pos_mundo.xz / 70.0 + vec2(TIME * 0.004, 0.0)).r;
		VERTEX.y += (b - 0.5) * 0.6;
	}
}

// Amostra a lava com o fluxo: dois tempos defasados de meio ciclo, misturados em triângulo
vec4 fluxo(sampler2D t, vec2 uv, vec2 dir, float tempo, float ciclo) {
	float f0 = fract(tempo / ciclo);
	float f1 = fract(tempo / ciclo + 0.5);
	float w = abs(f0 - 0.5) * 2.0;
	vec4 a = texture(t, uv - dir * f0 * ciclo);
	vec4 b = texture(t, uv - dir * f1 * ciclo + vec2(0.37, 0.71));
	return mix(a, b, w);
}

void fragment() {
	float ao_longo = UV.y;
	float lado = UV.x;
	float margem = 1.0 - abs(lado * 2.0 - 1.0);   // 0 nas margens, 1 no meio
	float vel = velocidade;
	float esticar = 1.0;
	if (modo == 1) {
		// Cascata: estica a textura no sentido da queda (fios de lava), mais rápida no meio
		vel *= 0.6 + 0.8 * margem;
		esticar = 0.35;
	}
	vec2 uv = vec2(lado * largura, ao_longo * esticar) / escala;
	vec2 dir = vec2(0.0, 1.0);
	if (mundo) {
		uv = pos_mundo.xz / escala;
		dir = normalize(vec2(0.6, 0.8));
	}
	float tempo = TIME * vel / escala;
	// Deriva lenta de lado (a lava não anda em trilhos)
	float deriva = texture(ruido, vec2(ao_longo * 0.004, TIME * 0.003)).r - 0.5;
	uv.x += deriva * 0.25;
	vec3 base = fluxo(tex_base, uv, dir, tempo, 1.0).rgb;
	vec3 brilho = fluxo(tex_brilho, uv * 1.0, dir, tempo, 1.0).rgb;
	// Placas de crosta: ruido grande que "esfria" com a distância percorrida e nas margens
	float placas = fluxo(ruido, uv * 2.2, dir, tempo * 0.8, 1.0).r;
	float fino = fluxo(ruido, uv * 9.0, dir, tempo, 1.0).r;
	float pulso = texture(ruido, pos_mundo.xz / 140.0 + vec2(TIME * 0.006, -TIME * 0.004)).r;
	float esfria = mix(0.62, 0.35, calor) + (1.0 - margem) * 0.22 + (pulso - 0.5) * 0.25;
	if (modo == 1) {
		esfria += 0.3 * margem;   // cascata: o meio corre depressa e não forma crosta (com o sinal trocado o meio ficava um retângulo preto)
	}
	float crosta = smoothstep(esfria - 0.06, esfria + 0.08, placas + fino * 0.18);
	// Rachaduras entre as placas: faixa fina no limiar
	float racha = 1.0 - smoothstep(0.0, 0.07, abs(placas + fino * 0.18 - esfria));
	float miolo = (1.0 - crosta);
	vec3 quente = mix(cor_quente, cor_miolo, smoothstep(0.35, 0.9, brilho.r * miolo + fino * 0.3));
	vec3 cor_c = cor_crosta * (0.7 + 0.6 * base);
	ALBEDO = mix(quente * 0.4, cor_c, crosta);
	ROUGHNESS = mix(0.35, 0.92, crosta);
	SPECULAR = 0.3;
	float e = miolo * (0.75 + 0.5 * brilho.r) + racha * crosta * 0.55;
	e *= 0.75 + 0.5 * pulso;
	EMISSION = quente * e * energia;
	if (modo == 1) {
		// Borda irregular da cascata (a lava escorre em línguas, não em faixa reta)
		float borda = texture(ruido, vec2(ao_longo * 0.03, lado * 0.2 + TIME * 0.002)).r;
		float larg = 0.32 + 0.18 * borda;
		if (abs(lado - 0.5) > larg) {
			discard;
		}
		// Esfria (e escurece) perto da borda das línguas
		EMISSION *= smoothstep(larg, larg - 0.12, abs(lado - 0.5));
	}
}
