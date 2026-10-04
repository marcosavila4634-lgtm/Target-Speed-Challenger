shader_type spatial;
render_mode unshaded;
// Queda de lava (Extinction Day, túnel): um fio grosso de lava viscosa caindo do teto. A malha é um
// cilindro de raio 1 do teto ao piso; o shader dá a forma: a frente desce como uma gota gorda e redonda,
// o fio afina enquanto cai, tem caroços que descem com a lava e balança de lado. Quando a boca fecha,
// o fio estrangula em cima, solta e a cauda fina cai atrás (não recolhe para o teto).
//   frente = até onde a ponta já desceu (metros abaixo da boca); cauda = de onde o fio já soltou.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float altura = 12.0;      // metros da boca ao piso
uniform float raio = 0.9;
uniform float frente = 0.0;
uniform float cauda = 0.0;
uniform float semente = 0.0;
uniform float velocidade = 5.5;   // m/s com que a lava desce dentro do fio
uniform float energia = 1.15;

varying vec3 pos_mundo;
varying float desce;              // metros abaixo da boca

float perfil(float d) {
	float h = frente - d;
	float k = d - cauda;
	if (h <= 0.0 || k <= 0.0) {
		return 0.0;
	}
	// O fio afina enquanto ganha velocidade; caroços descem com a lava
	float r = raio * mix(1.2, 0.8, clamp(d / altura, 0.0, 1.0));
	r *= 0.7 + 0.6 * textureLod(ruido, vec2(semente, (d - TIME * velocidade) * 0.014), 0.0).r;
	// Frente: gota redonda, mais gorda que o fio
	r *= sqrt(clamp(h / (raio * 1.1), 0.0, 1.0)) * (1.0 + 0.45 * exp(-h / (raio * 1.6)));
	// Boca: a lava se espalha no teto antes de cair (some quando a boca fecha)
	r *= 1.0 + 0.5 * exp(-d / 0.9) * (1.0 - smoothstep(0.0, 1.0, cauda));
	// Cauda: estrangula e estica até virar um fio fino
	if (cauda > 0.0) {
		r *= pow(clamp(k / min(cauda * 1.5, 4.0), 0.0, 1.0), 0.65);
	}
	return r;
}

void vertex() {
	desce = (0.5 - VERTEX.y) * altura;
	VERTEX.xz *= perfil(desce);
	float balanco = textureLod(ruido, vec2(semente + 0.31, (desce - TIME * velocidade * 0.5) * 0.005), 0.0).r - 0.5;
	VERTEX.x += balanco * 0.7 * smoothstep(0.0, 5.0, desce);
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float lado = pos_mundo.x * 0.9 + pos_mundo.z * 0.5 + semente * 40.0;
	float v = desce - TIME * velocidade;
	// Veios largos e compridos, esticados no sentido da queda (lava grossa escorrendo, não um chuvisco)
	float a = texture(ruido, vec2(lado * 0.028, v * 0.0045)).r;
	float b = texture(ruido, vec2(lado * 0.07 + 0.3, (desce - TIME * velocidade * 1.3) * 0.011)).r;
	float calor = smoothstep(0.34, 0.7, a * 0.62 + b * 0.38);
	// Placas de crosta escura descendo mais devagar que o miolo, com a beirada em brasa
	float placa = texture(ruido, vec2(lado * 0.035 + 0.5, (desce - TIME * velocidade * 0.75) * 0.009)).r;
	float crosta = smoothstep(0.6, 0.66, placa);
	float brasa = smoothstep(0.55, 0.6, placa) * (1.0 - crosta);
	vec3 cor = mix(vec3(0.8, 0.1, 0.0), vec3(1.0, 0.3, 0.02), calor);
	cor = mix(cor, vec3(1.0, 0.62, 0.12), smoothstep(0.75, 1.0, calor));
	cor = mix(cor, vec3(0.75, 0.08, 0.0), brasa * 0.7);
	cor = mix(cor, vec3(0.05, 0.01, 0.003), crosta * 0.95);
	// Mais quente na boca e na gota da frente
	float quente = exp(-desce / 2.5) * 0.25 + exp(-max(frente - desce, 0.0) / 1.5) * 0.4;
	cor += vec3(1.0, 0.55, 0.15) * quente * (1.0 - crosta * 0.8);
	// Pele mais fria na silhueta: separa um fio do outro e dá o volume redondo
	float borda = pow(clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.3);
	ALBEDO = cor * energia * mix(0.1, 1.0, borda);
}
