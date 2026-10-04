shader_type spatial;
render_mode cull_disabled;
// Piso da arena de largada conjunta. UV = (x, lateral) em metros: x = distância desde o muro do
// fundo até o portão, lateral = + à direita de quem sai.
// Placas de concreto com juntas, poeira, marcas de pneu, vagas pintadas, setas para a saída e
// faixas de perigo (amarelo/preto) com borda vermelha em volta dos buracos da morte.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 buracos[12];          // (x, lateral, raio); raio 0 = sem buraco
uniform vec3 vagas[16];           // (x, lateral, direção em radianos); x < -100 = sem vaga
uniform float comprimento = 110.0;
uniform float saida_largura = 18.0;
uniform vec3 cor_seta : source_color = vec3(1.0, 0.45, 0.08);
uniform vec3 cor_piso : source_color = vec3(0.47, 0.43, 0.39);   // Egito: lajes de arenito

float caixa(vec2 p, vec2 meio) {
	vec2 d = abs(p) - meio;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 q = UV;
	float grande = texture(ruido, q / 23.0).r;
	float medio = texture(ruido, q / 4.1).r;
	float fino = texture(ruido, q / 0.6).r;

	// Placas de concreto 6 x 6 m com juntas serradas e tom próprio
	vec2 id = floor(q / 6.0);
	float tom = fract(sin(dot(id, vec2(12.9898, 78.233))) * 43758.5453);
	vec3 cor = cor_piso * (0.84 + 0.26 * grande) * (0.93 + 0.1 * fino) * (0.93 + 0.1 * tom);
	vec2 f = fract(q / 6.0);
	vec2 db = min(f, 1.0 - f) * 6.0;
	float junta = 1.0 - smoothstep(0.02, 0.06, min(db.x, db.y));
	cor *= 1.0 - 0.4 * junta;

	// Marcas de pneu (arcos de derrapagem) e poeira avermelhada do cânion
	float arco = texture(ruido, vec2(q.x / 9.0 + sin(q.y / 7.0), q.y / 1.2)).r;
	cor = mix(cor, vec3(0.08, 0.075, 0.07), smoothstep(0.7, 0.78, arco) * smoothstep(0.35, 0.75, medio) * 0.4);
	float poeira = smoothstep(0.45, 0.85, grande * 0.6 + medio * 0.5);
	cor = mix(cor, vec3(0.66, 0.44, 0.3), poeira * 0.45);

	float rug = 0.88;
	vec3 emissao = vec3(0.0);

	// Setas (chevrons) apontando para o portão, no corredor central
	float lat = abs(q.y);
	if (q.x > comprimento - 34.0 && lat < saida_largura * 0.5 - 1.0) {
		// Ponta no centro mais perto do portão (x cresce para a saída), braços para trás
		float s = fract((q.x + lat * 0.6) / 5.0);
		float seta = step(0.62, s) * (1.0 - step(0.9, s));
		cor = mix(cor, cor_seta * 0.9, seta * 0.8);
		emissao += cor_seta * seta * 0.25;
	}

	// Vagas de largada: contorno branco de 3,2 x 6 m (aberto na frente) e faixa na traseira
	for (int i = 0; i < 16; i++) {
		vec3 v = vagas[i];
		if (v.x < -100.0) continue;
		vec2 d = q - v.xy;
		vec2 fr = vec2(cos(v.z), sin(v.z));      // frente da vaga (x, lateral)
		vec2 lo = vec2(dot(d, fr), dot(d, vec2(-fr.y, fr.x)));
		float borda = abs(caixa(lo, vec2(3.0, 1.6)));
		float linha = 1.0 - smoothstep(0.08, 0.14, borda);
		linha *= 1.0 - step(2.9, lo.x);           // sem a linha da frente
		float traseira = step(-3.0, lo.x) * (1.0 - step(-2.4, lo.x)) * step(abs(lo.y), 1.6);
		cor = mix(cor, vec3(0.9, 0.89, 0.85), max(linha, traseira * 0.6) * (0.75 + 0.25 * fino));
	}

	// Buracos: faixa zebrada amarela/preta e filete vermelho aceso junto à boca
	for (int i = 0; i < 12; i++) {
		vec3 b = buracos[i];
		if (b.z <= 0.0) continue;
		vec2 d = q - b.xy;
		float r = length(d);
		float faixa = step(b.z, r) * (1.0 - step(b.z + 1.6, r));
		float zebra = step(0.5, fract(atan(d.y, d.x) / 6.2831853 * floor(b.z * 3.0)));
		vec3 listra = mix(vec3(0.95, 0.72, 0.08), vec3(0.05, 0.05, 0.05), zebra);
		cor = mix(cor, listra * (0.8 + 0.25 * fino), faixa * 0.92);
		float filete = step(b.z, r) * (1.0 - step(b.z + 0.25, r));
		cor = mix(cor, vec3(0.9, 0.08, 0.04), filete);
		emissao += vec3(1.0, 0.1, 0.03) * filete * 2.5;
		// Aviso: anel vermelho desbotado mais afastado
		float aviso = 1.0 - smoothstep(0.1, 0.25, abs(r - (b.z + 4.0)));
		cor = mix(cor, vec3(0.62, 0.1, 0.07), aviso * 0.55);
		rug = mix(rug, 0.6, faixa);
	}

	ALBEDO = cor;
	ROUGHNESS = rug;
	EMISSION = emissao;
	NORMAL_MAP = normalize(vec3(0.5 + (fino - 0.5) * 0.25, 0.5 + (medio - 0.5) * 0.15, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.5;
}
