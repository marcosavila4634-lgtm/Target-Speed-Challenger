shader_type spatial;
// Chão do City Rush (o terreno plano): ruas em grade alinhadas com os corredores de voo,
// faixas pintadas, faixas de pedestre nos cruzamentos, calçadas, miolo das quadras (estacionamentos
// e jardins), a praça do alvo com piso em anéis e canteiros, e o muro de concreto do rio.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform float quadra = 150.0;
uniform float rua = 24.0;
uniform float calcada = 5.0;
uniform float praca = 60.0;
uniform float nivel_chao = 6.0;

varying vec3 pos_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float faixa(float d, float centro, float meia) {
	return 1.0 - smoothstep(meia * 0.6, meia, abs(d - centro));
}

void fragment() {
	vec2 p = pos_mundo.xz;
	float n = texture(ruido, p * 0.002).r;
	float nf = texture(ruido_fino, p * 0.05).r;
	float distancia = length(VERTEX);
	// Posição relativa ao eixo de rua mais próximo
	vec2 rel = p - round(p / quadra) * quadra;
	vec2 d = abs(rel);
	float meia_rua = rua * 0.5;
	vec3 asfalto = mix(vec3(0.075, 0.075, 0.08), vec3(0.12, 0.115, 0.11), n) * mix(0.85, 1.12, nf);
	vec3 concreto = mix(vec3(0.42, 0.41, 0.39), vec3(0.55, 0.53, 0.5), n) * mix(0.9, 1.08, nf);
	vec3 c;
	float rug = 0.9;
	float r = length(p);
	if (r < praca) {
		{
			// Praça: piso em anéis de pedra clara, canteiros de grama em setores
			float ang = atan(p.y, p.x);
			float anel = fract(r / 9.0);
			c = mix(vec3(0.62, 0.58, 0.52), vec3(0.7, 0.66, 0.6), step(0.5, anel)) * mix(0.9, 1.06, nf);
			c *= mix(0.92, 1.0, step(0.03, fract(ang * 40.0 / 6.2832)));
			float setor = step(0.5, fract(ang * 8.0 / 6.2832 + 0.25));
			float canteiro = setor * step(150.0, r) * step(r, praca - 40.0) * step(0.18, fract(r / 60.0));
			c = mix(c, mix(vec3(0.12, 0.2, 0.07), vec3(0.2, 0.28, 0.1), n), canteiro);
			rug = mix(0.8, 1.0, canteiro);
		}
	} else if (d.x < meia_rua || d.y < meia_rua) {
		c = asfalto;
		bool cruzamento = d.x < meia_rua && d.y < meia_rua;
		if (!cruzamento) {
			// Rua no sentido z (d.x pequeno) ou x (d.y pequeno)
			float dl = d.x < meia_rua ? d.x : d.y;          // distância ao eixo
			float ao_longo = d.x < meia_rua ? p.y : p.x;
			float transv = d.x < meia_rua ? d.y : d.x;      // distância ao cruzamento
			vec3 amarelo = vec3(0.78, 0.6, 0.12);
			c = mix(c, amarelo, max(faixa(dl, 0.25, 0.12), 0.0));
			float tracejada = faixa(dl, meia_rua * 0.5, 0.1) * step(0.5, fract(ao_longo / 9.0));
			c = mix(c, vec3(0.8), tracejada * step(meia_rua + 18.0, transv));
			c = mix(c, vec3(0.82), faixa(dl, meia_rua - 0.6, 0.1));
			// Faixa de pedestre e linha de retenção perto do cruzamento
			float pedestre = step(meia_rua + 1.0, transv) * step(transv, meia_rua + 5.0) * step(0.5, fract(dl / 1.0));
			c = mix(c, vec3(0.85), pedestre * step(dl, meia_rua - 1.0));
			c = mix(c, vec3(0.85), faixa(transv, meia_rua + 6.5, 0.25) * step(dl, meia_rua * 0.5));
		}
		c *= mix(0.92, 1.0, texture(ruido_fino, p * 0.013).r);
	} else if (d.x < meia_rua + calcada || d.y < meia_rua + calcada) {
		// Calçada: placas de concreto, meio-fio claro
		float dl = min(d.x, d.y) - meia_rua;
		vec2 placa = fract(p / 1.5);
		c = concreto * mix(0.86, 1.0, step(0.05, placa.x) * step(0.05, placa.y));
		c = mix(c, vec3(0.68, 0.67, 0.64), step(dl, 0.35));
		rug = 0.85;
	} else {
		// Miolo da quadra: estacionamento (asfalto com vagas) ou jardim
		vec2 q = floor(p / quadra);
		float s = fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453);
		if (s < 0.35) {
			c = mix(vec3(0.14, 0.22, 0.08), vec3(0.24, 0.3, 0.12), n) * mix(0.85, 1.1, nf);
		} else {
			c = asfalto * 1.25;
			float vaga = step(0.93, fract(p.x / 2.7)) * step(0.3, fract(p.y / 12.0));
			c = mix(c, vec3(0.7), vaga * 0.8);
		}
	}
	// Rio/canal: muro de concreto abaixo do nível da rua
	if (pos_mundo.y < nivel_chao - 0.6) {
		c = mix(vec3(0.3, 0.29, 0.27), vec3(0.4, 0.38, 0.35), nf) * mix(0.6, 1.0, smoothstep(0.0, nivel_chao, pos_mundo.y));
	}
	// Longe: cor média da cidade (sem cintilar)
	c = mix(c, vec3(0.2, 0.2, 0.2), smoothstep(1500.0, 5000.0, distancia));
	ALBEDO = c;
	ROUGHNESS = rug;
	SPECULAR = 0.35;
}
