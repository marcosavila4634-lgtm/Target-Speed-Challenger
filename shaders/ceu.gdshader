shader_type sky;
// Céu de fim de tarde: degradê quente no horizonte (mais forte do lado do sol), disco solar com halo
// e duas camadas de nuvens procedurais que se movem devagar, iluminadas por trás pelo sol.

uniform vec3 cor_zenite : source_color = vec3(0.13, 0.23, 0.46);
uniform vec3 cor_meio : source_color = vec3(0.42, 0.47, 0.64);
uniform vec3 cor_horizonte : source_color = vec3(1.0, 0.63, 0.36);
uniform vec3 cor_horizonte_sol : source_color = vec3(1.0, 0.5, 0.2);
uniform vec3 cor_chao : source_color = vec3(0.55, 0.33, 0.22);
uniform vec3 cor_nuvem_luz : source_color = vec3(1.0, 0.72, 0.45);
uniform vec3 cor_nuvem_sombra : source_color = vec3(0.36, 0.3, 0.42);
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float cobertura : hint_range(0.0, 1.0) = 0.5;
uniform float vento = 0.004;
uniform float tamanho_sol = 0.9995;
uniform float halo_sol = 6.0;

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * texture(ruido, p).r;
		p = p * 2.03 + vec2(0.17, 0.31);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sol = normalize(LIGHT0_DIRECTION);
	float cos_sol = dot(d, sol);
	float lado_sol = pow(max(dot(normalize(vec2(d.x, d.z)), normalize(vec2(sol.x, sol.z))), 0.0), 3.0);

	// Degradê
	float y = max(d.y, 0.0);
	vec3 horiz = mix(cor_horizonte, cor_horizonte_sol, lado_sol);
	vec3 cor = mix(horiz, cor_meio, smoothstep(0.0, 0.18, y));
	cor = mix(cor, cor_zenite, smoothstep(0.15, 0.75, y));
	// Brilho difuso em volta do sol
	cor += LIGHT0_COLOR * (pow(max(cos_sol, 0.0), halo_sol) * 0.35 + pow(max(cos_sol, 0.0), 60.0) * 0.8) * LIGHT0_ENERGY * 0.35;

	// Nuvens (projeção num plano alto)
	if (d.y > 0.0) {
		vec2 p = d.xz / (d.y + 0.08);
		float t = TIME * vento;
		float n1 = fbm(p * 0.09 + vec2(t, t * 0.4));
		float n2 = fbm(p * 0.035 - vec2(t * 0.6, 0.0) + 3.1);
		float dens = smoothstep(1.0 - cobertura, 1.05 - cobertura * 0.55, n1 * 0.65 + n2 * 0.55);
		dens *= smoothstep(0.0, 0.1, d.y);
		// "Espessura" para sombrear o miolo e iluminar as bordas voltadas para o sol
		float miolo = smoothstep(0.55, 0.95, n1 * 0.6 + n2 * 0.6);
		vec3 luz = mix(cor_nuvem_luz, vec3(1.0, 0.9, 0.78), smoothstep(0.3, 0.8, y));
		vec3 cn = mix(luz, cor_nuvem_sombra, miolo * 0.75);
		cn += LIGHT0_COLOR * pow(max(cos_sol, 0.0), 8.0) * (1.0 - miolo) * 0.9;
		cor = mix(cor, cn, dens * 0.9);
	}

	// Disco do sol por cima de tudo
	float disco = smoothstep(tamanho_sol, tamanho_sol + 0.0002, cos_sol);
	cor += LIGHT0_COLOR * disco * 6.0;

	// Abaixo do horizonte: bruma que se funde com o terreno distante
	if (d.y < 0.0) {
		cor = mix(horiz, cor_chao, smoothstep(0.0, -0.25, d.y));
	}
	COLOR = cor;
}
