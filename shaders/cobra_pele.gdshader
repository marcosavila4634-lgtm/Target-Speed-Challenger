shader_type spatial;
// Pele das cobras de cor do Serpent's Climb (SerpenteGigante, cfg "cor"): a textura e o relevo do modelo
// (escamas de verdade) tingidos, mais o desenho de cada espécie pelo UV2 = (metros ao longo do corpo,
// altura 0..1), que não escorrega quando ela anda.
// desenho: 0 = só tinta (preta, verde), 1 = coral (anéis vermelho/preto/amarelo), 2 = cascavel (losangos
// escuros de borda clara nas costas e chocalho de anéis na cauda).

uniform sampler2D pele : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relevo : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tinta : source_color = vec3(1.0);
uniform int desenho = 0;
uniform float comprimento = 120.0;
uniform float anel = 5.0;

void fragment() {
	vec3 base = texture(pele, UV).rgb;
	float lum = dot(base, vec3(0.3, 0.59, 0.11));
	float detalhe = clamp(lum / 0.35, 0.45, 1.6);   // o claro-escuro das escamas do modelo
	float barriga = smoothstep(0.3, 0.1, UV2.y);
	vec3 cor = base * tinta;
	if (desenho == 1) {
		float f = fract(UV2.x / anel);
		float preto = smoothstep(0.0, 0.02, f - 0.08) * smoothstep(0.0, 0.02, 0.4 - f);
		float filete = smoothstep(0.0, 0.02, f) * smoothstep(0.0, 0.02, 0.48 - f) * (1.0 - preto);
		cor = mix(vec3(0.6, 0.06, 0.03), vec3(0.95, 0.75, 0.15), filete);
		cor = mix(cor, vec3(0.025), preto);
		cor *= detalhe;
		cor = mix(cor, vec3(0.75, 0.6, 0.45) * detalhe, barriga * 0.6);
	} else if (desenho == 2) {
		vec3 fundo = vec3(0.55, 0.45, 0.3);
		float a = fract(UV2.x / anel) - 0.5;
		float lado = (1.0 - UV2.y) * 2.2;
		float d = abs(a) * 2.0 + lado;
		float losango = smoothstep(0.72, 0.62, d);
		float borda = smoothstep(0.86, 0.76, d) * (1.0 - losango);
		cor = fundo;
		cor = mix(cor, vec3(0.86, 0.8, 0.62), borda);
		cor = mix(cor, vec3(0.2, 0.13, 0.08), losango);
		// Cauda: anéis pretos e brancos e o chocalho
		float cauda = smoothstep(comprimento * 0.9, comprimento * 0.92, UV2.x);
		float aneis = step(0.5, fract(UV2.x / (anel * 0.35)));
		cor = mix(cor, mix(vec3(0.85, 0.82, 0.75), vec3(0.04), aneis), cauda);
		cor *= detalhe;
		cor = mix(cor, vec3(0.8, 0.72, 0.55) * detalhe, barriga * 0.7);
	}
	ALBEDO = cor;
	NORMAL_MAP = texture(relevo, UV).rgb;
	NORMAL_MAP_DEPTH = 1.8;
	ROUGHNESS = 0.75;
	SPECULAR = 0.35;
}
