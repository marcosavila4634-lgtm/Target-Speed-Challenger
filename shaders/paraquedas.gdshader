shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Tecido do paraquedas: células infladas, ondulação do vento, borda de fuga tremulando
// e padrão de chevrons em dois tons da cor da equipe.
// UV  = (posição na célula 0..1, posição na corda 0..1 da frente para trás)
// UV2 = (índice da célula / total, 1 = face de cima, 0 = de baixo, 0.5 = boca/painel)

uniform vec3 cor : source_color = vec3(0.2, 0.4, 1.0);
uniform float inflacao = 1.0;      // 0 = murcho, 1 = cheio
uniform float abertura = 1.0;      // abertura: as células enchem do centro para as pontas (0 → 1)
uniform float vento = 1.0;         // intensidade da ondulação
uniform float envergadura = 10.0;
uniform float tempo = 0.0;         // relógio do script (as linhas dos estabilizadores usam o mesmo cálculo)

varying float v_face;
varying vec2 v_uv;
varying float v_x;

void vertex() {
	v_uv = UV;
	v_face = UV2.y;
	v_x = VERTEX.x;
	if (UV2.x < -0.5) {
		// Estabilizador (UV.y = 0 preso na asa, 1 na ponta de baixo): tremula com o vento e
		// recolhe quando a asa murcha. Mesmo cálculo de Paraquedas._desloc_estabilizador().
		float w = UV.y;
		VERTEX.x += sin(tempo * 9.0 + w * 2.0 + VERTEX.z * 1.3) * 0.16 * w * vento;
		VERTEX.z += sin(tempo * 6.3 + w * 3.0) * 0.1 * w * vento;
		VERTEX.y += (1.0 - inflacao) * w * 1.1;
	} else {
	float u = UV.x;
	float c = UV.y;
	// Enchimento por célula na abertura: centro primeiro, pontas por último. Célula ainda vazia
	// fica pendurada (cai e pende para trás) e tremula forte.
	// Pela posição contínua na envergadura (pelo índice da célula as bordas vizinhas se separavam)
	float dist_centro = clamp(abs(VERTEX.x) / (envergadura * 0.5), 0.0, 1.0);
	float cel = smoothstep(dist_centro * 0.6, dist_centro * 0.6 + 0.4, abertura);
	float cheio = inflacao * cel;
	float vazio = 1.0 - cel;
	VERTEX.y -= vazio * (0.9 + c * 0.9);
	VERTEX.z += vazio * c * 0.6;
	VERTEX.y += vazio * sin(TIME * 20.0 + VERTEX.x * 2.0 + c * 4.0) * 0.1;
	// Célula inflada: a face de cima estufa, a de baixo afunda um pouco
	float bojo = sin(PI * u) * pow(sin(PI * clamp(c * 0.9 + 0.08, 0.0, 1.0)), 0.6);
	float sinal = v_face > 0.75 ? 1.0 : (v_face < 0.25 ? -0.35 : 0.3);
	VERTEX.y += bojo * 0.26 * cheio * sinal;
	// Vento: ondas ao longo da envergadura, mais fortes na borda de fuga
	float onda = sin(TIME * 7.0 + VERTEX.x * 0.9 + c * 2.0) * 0.5 + sin(TIME * 13.0 - VERTEX.x * 1.7) * 0.25;
	VERTEX.y += onda * 0.07 * c * c * vento;
	// Murcho: o tecido amassa e tremula muito
	float amasso = (1.0 - inflacao);
	VERTEX.y += amasso * (sin(VERTEX.x * 5.0 + TIME * 22.0) * 0.35 + sin(c * 9.0 + TIME * 17.0) * 0.25);
	VERTEX.z += amasso * sin(VERTEX.x * 3.0 + TIME * 15.0) * 0.3;
	}
}

void fragment() {
	float lado = abs(v_x) / (envergadura * 0.5);
	float chevron = step(0.5, fract((lado * 1.6 - v_uv.y * 0.9) * 2.0));
	vec3 base = mix(cor, mix(cor, vec3(1.0), 0.45), chevron);
	// Costuras entre as células
	float costura = smoothstep(0.035, 0.0, min(v_uv.x, 1.0 - v_uv.x));
	base = mix(base, base * 0.6, costura);
	// Boca das células (frente) e face de baixo mais escuras
	if (v_face > 0.25 && v_face < 0.75) {
		base *= 0.35;
	} else if (v_face < 0.25) {
		base *= 0.72;
	}
	ALBEDO = base;
	ROUGHNESS = 0.82;
	SPECULAR = 0.2;
	BACKLIGHT = cor * 0.35;
}
