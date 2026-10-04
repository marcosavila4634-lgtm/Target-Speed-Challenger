shader_type spatial;
// Ninho gigante (alvo da etapa 1 do Extinction Day): galhos e palha trançados em voltas, penugem e
// cascas de ovo quebradas, com três anéis de luzes de pouso que o parque pregou nos galhos (para os
// pilotos acharem o centro). modo_ovo = 1: casca de ovo de dinossauro (creme com pintas marrons).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float raio = 13.0;
uniform int modo_ovo = 0;
uniform float luzes = 1.0;   // 0 = sem os anéis de luzes de pouso (ninho do pórtico, etapa 2)

varying vec3 pos_local;

void vertex() {
	pos_local = VERTEX;
}

void fragment() {
	if (modo_ovo == 1) {
		vec3 p = pos_local;
		float pintas = texture(ruido, p.xy * 0.9 + p.z * 0.4).r;
		float pinta = smoothstep(0.62, 0.7, pintas);
		if (luzes < 0.5) {
			// ovos do ninho do pórtico: pintas e manchas escuras bem marcadas (vistas de cima, à noite)
			pinta = max(smoothstep(0.52, 0.58, pintas), smoothstep(0.6, 0.66, texture(ruido, p.zy * 2.3 + p.x * 1.1 + 3.7).r));
		}
		vec3 casca = mix(vec3(0.86, 0.76, 0.58), vec3(0.3, 0.19, 0.11), pinta);
		casca *= 0.9 + 0.1 * texture(ruido, p.xz * 3.0).r;
		ALBEDO = casca;
		ROUGHNESS = 0.55;
		SPECULAR = 0.4;
	} else {
		vec2 q = pos_local.xz;
		float r = length(q);
		float ang = atan(q.y, q.x);
		// Galhos trançados: faixas em espiral que se cruzam, com nós e falhas
		float f1 = sin(ang * 26.0 + r * 1.1);
		float f2 = sin(ang * -21.0 + r * 1.35 + 1.7);
		float galho = smoothstep(0.25, 0.85, max(f1, f2));
		if (luzes < 0.5) {
			// ninho do pórtico: palha solta deitada em voltas (fios compridos ao redor), sem o trançado regular
			float fio = texture(ruido, vec2(ang * 1.3 + r * 0.21, r * 1.7)).r;
			float fio2 = texture(ruido, vec2(ang * 2.9 - r * 0.33 + 5.0, r * 3.1)).r;
			galho = smoothstep(0.42, 0.62, fio) * 0.7 + smoothstep(0.5, 0.7, fio2) * 0.3;
		}
		float n = texture(ruido, q * 0.11).r;
		float fino = texture(ruido, q * 0.9).r;
		vec3 madeira = mix(vec3(0.24, 0.16, 0.09), vec3(0.46, 0.33, 0.19), galho * (0.6 + 0.4 * fino));
		vec3 palha = vec3(0.62, 0.52, 0.3) * (0.8 + 0.3 * fino);
		vec3 cor = mix(madeira, palha, smoothstep(0.55, 0.75, n) * (1.0 - galho * 0.6));
		// Penugem clara e cascas de ovo espalhadas no miolo
		float casca = smoothstep(0.86, 0.9, texture(ruido, q * 0.35 + 7.3).r) * smoothstep(raio * 0.7, raio * 0.3, r);
		cor = mix(cor, vec3(0.85, 0.8, 0.68), casca);
		cor *= 0.75 + 0.25 * smoothstep(raio, raio * 0.4, r);   // borda mais escura (galhos grossos)
		// Anéis de luzes de pouso (LEDs vermelhos e brancos alternando, piscando em onda)
		float em = 0.0;
		vec3 cor_luz = vec3(0.0);
		for (int k = 1; k <= 3; k++) {
			float rr = raio * float(k) / 3.6;
			float anel = smoothstep(0.35, 0.0, abs(r - rr));
			float led = smoothstep(0.55, 0.9, sin(ang * 36.0 * float(k) / 3.0));
			float onda = 0.55 + 0.45 * sin(TIME * 3.0 - float(k) * 1.2 + ang * 2.0);
			vec3 c = (k % 2 == 1) ? vec3(1.0, 0.12, 0.05) : vec3(1.0, 0.95, 0.85);
			cor_luz += c * anel * led * onda;
		}
		// Centro marcado
		cor_luz += vec3(1.0, 0.3, 0.05) * smoothstep(1.2, 0.0, r) * (0.6 + 0.4 * sin(TIME * 5.0));
		ALBEDO = cor;
		EMISSION = cor_luz * 4.0 * luzes;
		ROUGHNESS = 0.92;
		SPECULAR = 0.2;
	}
}
