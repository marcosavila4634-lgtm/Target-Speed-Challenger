shader_type spatial;
// Pele da foca-leopardo do Frozen Peak (Foca). A textura fica presa à pele parada (CUSTOM0 = posição de
// descanso), então não escorrega quando os ossos mexem o corpo.
// - costas cinza-chumbo, flancos e barriga prateados, garganta clara; pintas escuras irregulares (mais
//   na garganta e nos flancos) e algumas claras nas costas;
// - relevo: pelo curto (granulado fino) e dobras de pele no pescoço; brilho de pelo molhado (verniz);
// - geada branca grudada em pontinhos nas costas;
// - `boca` = 1: dentro da boca (rosa úmido, céu da boca mais escuro).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float boca = 0.0;
uniform vec3 cor_costas : source_color = vec3(0.12, 0.13, 0.15);
uniform vec3 cor_flanco : source_color = vec3(0.36, 0.38, 0.41);
uniform vec3 cor_barriga : source_color = vec3(0.66, 0.67, 0.68);

varying vec3 p_rest;

void vertex() {
	p_rest = CUSTOM0.xyz;
}

float tri(vec3 p, vec3 n, float escala) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(ruido, p.zy / escala).r * w.x + texture(ruido, p.xz / escala).r * w.y + texture(ruido, p.xy / escala).r * w.z;
}

void fragment() {
	vec3 p = p_rest;
	vec3 n_mod = normalize((inverse(MODEL_MATRIX) * vec4((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz, 0.0)).xyz);
	if (boca > 0.5) {
		float m = texture(ruido, p.xz * 6.0).r;
		vec3 cor_b = mix(vec3(0.55, 0.16, 0.2), vec3(0.32, 0.06, 0.09), smoothstep(0.3, 0.8, m));
		ALBEDO = cor_b;
		ROUGHNESS = 0.18;
		SPECULAR = 0.7;
		CLEARCOAT = 0.6;
	} else {
		// Altura do ponto em relação ao centro do corpo: costas x barriga (independente da pose)
		float dorso = smoothstep(-0.15, 0.55, n_mod.y + (p.y - 0.45) * 0.4);
		vec3 cor = mix(cor_barriga, cor_flanco, smoothstep(0.0, 0.45, dorso));
		cor = mix(cor, cor_costas, smoothstep(0.4, 0.9, dorso));
		// Garganta mais clara
		cor = mix(cor, cor_barriga * 1.08, smoothstep(0.75, 1.1, p.z) * (1.0 - dorso) * 0.6);
		// Pintas: manchas irregulares com borda suja
		float m1 = tri(p * vec3(1.0, 1.0, 0.75), n_mod, 0.26);
		float m2 = tri(p + 3.7, n_mod, 0.11);
		float pinta = smoothstep(0.56, 0.62, m1 + (m2 - 0.5) * 0.3);
		cor = mix(cor, vec3(0.05, 0.05, 0.06), pinta * mix(0.85, 0.35, dorso));
		float clara = smoothstep(0.66, 0.72, tri(p + 9.1, n_mod, 0.2)) * dorso;
		cor = mix(cor, cor_flanco * 1.3, clara * 0.5);
		// Pelo curto: variação fina
		float pelo = tri(p, n_mod, 0.018);
		cor *= 0.86 + 0.28 * pelo;
		// Geada nas costas em pontinhos
		float geada = step(0.86, tri(p * 5.0, n_mod, 0.4)) * smoothstep(0.6, 1.0, dorso);
		cor = mix(cor, vec3(0.9, 0.95, 1.0), geada * 0.8);
		// Relevo: pelo e dobras do pescoço viram normal (derivada da altura na tela)
		float dobra = sin(p.z * 70.0 + tri(p, n_mod, 0.3) * 6.0) * smoothstep(0.75, 0.95, p.z) * smoothstep(1.2, 1.02, p.z);
		float h = pelo * 0.35 + m2 * 0.25 + dobra * 0.5;
		vec3 dpx = dFdx(VERTEX);
		vec3 dpy = dFdy(VERTEX);
		vec3 r1 = cross(dpy, NORMAL);
		vec3 r2 = cross(NORMAL, dpx);
		float det = dot(dpx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * NORMAL - 0.006 * grad);
		ALBEDO = cor;
		ROUGHNESS = mix(0.32, 0.7, geada);
		SPECULAR = 0.55;
		CLEARCOAT = 0.45 * (1.0 - geada);
		CLEARCOAT_ROUGHNESS = 0.25;
		RIM = 0.25;
		RIM_TINT = 0.6;
	}
}
