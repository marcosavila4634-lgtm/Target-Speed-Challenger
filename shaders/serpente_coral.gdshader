shader_type spatial;
// Pele de cobra-coral da serpente colossal da etapa 1 (SerpenteCaminho): anéis largos vermelhos e pretos
// separados por um filete amarelo, barriga clara e escamas em telha desenhadas aqui (o corpo tem quilômetros:
// a textura do modelo esticaria). UV2 = (metros ao longo do corpo, altura 0..1), gravado na malha antes dos
// ossos (SerpenteGigante._malha): anéis e escamas não escorregam quando ela se mexe.

uniform sampler2D pele : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relevo : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 cor_a : source_color = vec3(0.62, 0.05, 0.03);
uniform vec3 cor_b : source_color = vec3(0.03, 0.03, 0.035);
uniform vec3 cor_filete : source_color = vec3(0.95, 0.72, 0.12);
uniform vec3 cor_barriga : source_color = vec3(0.86, 0.76, 0.5);
uniform float anel = 26.0;
uniform float escama = 1.6;        // m de cada escama ao longo do corpo
uniform float volta = 22.0;        // m da altura do corpo (para as escamas serem quase quadradas)

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	// Escamas em telha: fileiras desencontradas, cada escama clara no meio e escura na borda de trás
	vec2 e = vec2(UV2.x / escama, UV2.y * volta / escama);
	float fila = floor(e.y);
	e.x += mod(fila, 2.0) * 0.5;
	vec2 c = fract(e) - vec2(0.5, 0.5);
	float d = length(c * vec2(1.0, 1.25));
	float borda = smoothstep(0.32, 0.5, d);
	float tom = h21(floor(e) + fila * 7.0);
	float barriga = smoothstep(0.26, 0.08, UV2.y);
	float f = fract(UV2.x / anel);
	float preto = smoothstep(0.0, 0.015, f - 0.06) * smoothstep(0.0, 0.015, 0.36 - f);
	float filete = smoothstep(0.0, 0.012, f) * smoothstep(0.0, 0.012, 0.42 - f) * (1.0 - preto);
	vec3 cor = mix(cor_a, cor_filete, filete);
	cor = mix(cor, cor_b, preto);
	cor = mix(cor, cor_barriga, barriga * 0.85);
	cor *= (0.82 + 0.25 * tom) * (1.0 - 0.45 * borda);
	// Escudos largos da barriga: faixas atravessadas em vez de escamas
	float placa = smoothstep(0.42, 0.5, abs(fract(UV2.x / (escama * 1.4)) - 0.5) * 2.0 * 0.5 + 0.25);
	cor = mix(cor, cor * (1.0 - 0.35 * placa), barriga);
	ALBEDO = cor;
	// Relevo: cada escama abaulada (inclina a normal do centro para a borda)
	vec2 inc = c * borda * 1.6 * (1.0 - barriga);
	NORMAL = normalize(NORMAL + (TANGENT * inc.x + BINORMAL * inc.y) * 0.6);
	ROUGHNESS = mix(0.28, 0.5, borda);
	SPECULAR = 0.6;
}
