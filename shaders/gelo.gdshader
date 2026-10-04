shader_type spatial;
// Estruturas do Frozen Peak (coordenadas do mundo, triplanar):
// modo 0 = gelo de geleira (azul fundo com veios brancos, liso, brilho de borda);
// modo 1 = blocos de gelo cortados (fortalezas, muralhas): fiadas com juntas de neve;
// modo 2 = rocha escura em camadas;
// modo 3 = concreto com geada (pilares da estrada);
// modo 4 = neve batida.
// Em todos, as faces viradas para cima acumulam neve (uniform neve).

uniform int modo = 0;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_gelo : source_color = vec3(0.34, 0.66, 0.86);
uniform vec3 cor_gelo_fundo : source_color = vec3(0.06, 0.26, 0.48);
uniform vec3 cor_neve : source_color = vec3(0.93, 0.96, 1.0);
uniform vec3 cor_rocha : source_color = vec3(0.3, 0.29, 0.31);
uniform float fiada = 1.6;        // altura do bloco (modo 1)
uniform float bloco = 3.2;        // comprimento do bloco (modo 1)
uniform float neve = 1.0;         // quanto de neve nas faces de cima (0 = nenhuma)
uniform float brilho = 0.18;      // luz "de dentro" do gelo

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Agulhas e seracs são prismas muito esticados por instância (escala não uniforme): a normal certa
	// é a da inversa transposta (a do motor, nesse caso, sai torta e a agulha virava "neve")
	normal_mundo = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);
}

float h11(float x) {
	return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

float tri(vec3 p, vec3 n, float escala) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return texture(ruido, p.zy / escala).r * w.x + texture(ruido, p.xz / escala).r * w.y + texture(ruido, p.xy / escala).r * w.z;
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 nw = normalize(normal_mundo);
	vec3 n_vista = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	float dist = length(p - CAMERA_POSITION_WORLD);
	float perto = smoothstep(260.0, 20.0, dist);
	float n1 = tri(p, nw, 23.0);
	float n2 = tri(p, nw, 5.0);
	float n3 = tri(p, nw, 0.9);
	vec3 cor;
	float rug;
	float espec = 0.5;
	vec3 emis = vec3(0.0);
	// Coordenada ao longo da face vertical (para fiadas de blocos)
	float along = (p.x * abs(nw.z) + p.z * abs(nw.x)) / max(abs(nw.x) + abs(nw.z), 0.001);
	if (modo == 0) {
		// Veios e fraturas: cristas do ruído
		float veio = 1.0 - smoothstep(0.0, 0.06, abs(n2 - 0.5));
		float fundo = smoothstep(0.3, 0.75, n1);
		cor = mix(cor_gelo, cor_gelo_fundo, fundo * 0.75);
		cor = mix(cor, vec3(0.85, 0.95, 1.0), veio * 0.45 * (0.4 + 0.6 * perto));
		cor *= 0.92 + 0.16 * n3 * perto;
		rug = mix(0.1, 0.3, veio);
		espec = 0.75;
		float borda = pow(1.0 - clamp(dot(n_vista, normalize(VIEW)), 0.0, 1.0), 2.5);
		emis = cor_gelo * (brilho * (0.6 + 0.8 * (1.0 - fundo)) + borda * 0.3);
	} else if (modo == 1) {
		float linha = floor(p.y / fiada);
		float u = fract(p.y / fiada);
		float desloc = h11(linha) * bloco;
		float v = fract((along + desloc) / bloco);
		float id = floor((along + desloc) / bloco) + linha * 17.0;
		float junta = max(smoothstep(0.06, 0.0, min(u, 1.0 - u)), smoothstep(0.03, 0.0, min(v, 1.0 - v)));
		junta *= step(abs(nw.y), 0.7);
		cor = mix(cor_gelo * 1.12, cor_gelo_fundo * 1.4, h11(id) * 0.55 + n1 * 0.3);
		float veio = 1.0 - smoothstep(0.0, 0.05, abs(n2 - 0.5));
		cor = mix(cor, vec3(0.86, 0.95, 1.0), veio * 0.3 * perto);
		cor = mix(cor, cor_neve, junta * 0.85);
		rug = mix(0.14, 0.7, junta);
		espec = 0.7;
		float borda = pow(1.0 - clamp(dot(n_vista, normalize(VIEW)), 0.0, 1.0), 2.5);
		emis = cor_gelo * (brilho * 0.7 + borda * 0.35) * (1.0 - junta);
	} else if (modo == 2) {
		float hh = p.y + (n1 - 0.5) * 14.0;
		float camada = floor(hh / 5.0);
		cor = mix(cor_rocha, cor_rocha * 0.62, h11(camada) * 0.8);
		cor *= 0.8 + 0.4 * n2;
		cor *= 0.9 + 0.2 * n3 * perto;
		float junta = smoothstep(0.12, 0.0, fract(hh / 5.0));
		cor *= 1.0 - 0.35 * junta;
		// Neve presa nos degraus das camadas
		cor = mix(cor, cor_neve, smoothstep(0.82, 0.97, fract(hh / 5.0)) * 0.7 * neve);
		rug = 0.9;
		espec = 0.3;
	} else if (modo == 3) {
		cor = vec3(0.52, 0.55, 0.6) * (0.82 + 0.3 * n2);
		cor *= 0.92 + 0.16 * n3 * perto;
		// Geada subindo do pé e escorrendo do topo, em manchas
		float geada = smoothstep(0.45, 0.75, n1 + n2 * 0.4);
		cor = mix(cor, vec3(0.82, 0.9, 0.97), geada * 0.6);
		// Marcas das formas (juntas horizontais a cada 3 m)
		cor *= 1.0 - 0.18 * smoothstep(0.04, 0.0, abs(fract(p.y / 3.0) - 0.5) - 0.46) * step(abs(nw.y), 0.7);
		rug = mix(0.85, 0.5, geada);
		espec = 0.35;
	} else {
		cor = cor_neve * (0.9 + 0.12 * n2);
		cor = mix(cor, vec3(0.78, 0.86, 0.97), smoothstep(0.55, 0.8, n1) * 0.4);
		rug = 0.85;
		espec = 0.4;
	}
	// Neve acumulada nas faces viradas para cima (borda irregular)
	float cima = smoothstep(0.55, 0.85, nw.y + (n2 - 0.5) * 0.35) * neve;
	if (modo != 4) {
		cor = mix(cor, cor_neve * (0.92 + 0.1 * n3), cima);
		rug = mix(rug, 0.85, cima);
		emis *= 1.0 - cima;
	}
	// Brilhinho da neve de perto
	float faisca = step(0.985, texture(ruido, p.xz * 1.7 + p.y).r) * cima * perto;
	NORMAL = n_vista;
	ALBEDO = cor;
	ROUGHNESS = rug;
	SPECULAR = espec;
	EMISSION = emis + vec3(faisca) * 0.6;
}
