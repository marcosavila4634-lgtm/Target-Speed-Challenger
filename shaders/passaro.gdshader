shader_type spatial;
render_mode cull_disabled;
// Aves da selva (Serpent's Climb) instanciadas: as asas batem no vértice (ombro e cotovelo), com
// fase, frequência e amplitude por ave (INSTANCE_CUSTOM.xyz). A cor sai da região marcada no vértice
// (COLOR.r: 0 corpo, 0.25 peito, 0.5 asa, 0.75 ponta da asa/cauda, 1 bico).

uniform vec3 cor_corpo : source_color = vec3(0.8, 0.1, 0.06);
uniform vec3 cor_peito : source_color = vec3(0.8, 0.1, 0.06);
uniform vec3 cor_asa : source_color = vec3(1.0, 0.8, 0.1);
uniform vec3 cor_ponta : source_color = vec3(0.1, 0.25, 0.8);
uniform vec3 cor_bico : source_color = vec3(0.9, 0.85, 0.75);

varying float regiao;

void vertex() {
	regiao = COLOR.r;
	float fase = INSTANCE_CUSTOM.x;
	float freq = INSTANCE_CUSTOM.y;
	float amp = INSTANCE_CUSTOM.z;
	float d = abs(VERTEX.x);
	if (COLOR.g > 0.5 && d > 0.1) {
		float a = sin(TIME * freq + fase) * amp + amp * 0.25;
		float s = sign(VERTEX.x);
		float y = VERTEX.y;
		vec2 p;
		if (d <= 0.55) {
			p = vec2(0.1 + (d - 0.1) * cos(a), y + (d - 0.1) * sin(a));
		} else {
			vec2 cot = vec2(0.1 + 0.45 * cos(a), y + 0.45 * sin(a));
			float b = a * 1.6 - amp * 0.2;
			p = cot + vec2((d - 0.55) * cos(b), (d - 0.55) * sin(b));
		}
		VERTEX.x = p.x * s;
		VERTEX.y = p.y;
	}
}

void fragment() {
	vec3 c = cor_corpo;
	if (regiao > 0.9) {
		c = cor_bico;
	} else if (regiao > 0.65) {
		c = cor_ponta;
	} else if (regiao > 0.4) {
		c = cor_asa;
	} else if (regiao > 0.15) {
		c = cor_peito;
	}
	ALBEDO = c;
	ROUGHNESS = 0.6;
	SPECULAR = 0.35;
	BACKLIGHT = c * 0.3;
}
