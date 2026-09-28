shader_type spatial;
render_mode cull_disabled;
// Bandeira ao vento (PlaneMesh subdividido preso no mastro em UV.x = 0).
// Na cor da equipe com um chevron claro; ondula mais longe do mastro.

uniform vec3 cor_equipe : source_color = vec3(0.2, 0.45, 1.0);
uniform float amplitude = 0.35;
uniform float frequencia = 2.2;
uniform float velocidade = 3.5;
uniform float fase = 0.0;

void vertex() {
	float solto = UV.x;
	float onda = sin(UV.x * frequencia * 6.2831 - TIME * velocidade + fase);
	float onda2 = sin(UV.x * 3.1 + UV.y * 2.0 - TIME * velocidade * 0.7 + fase * 1.7);
	VERTEX.y += (onda * 0.8 + onda2 * 0.35) * amplitude * solto;
	VERTEX.z += onda2 * amplitude * 0.25 * solto;
	float d = cos(UV.x * frequencia * 6.2831 - TIME * velocidade + fase) * amplitude * solto;
	NORMAL = normalize(NORMAL + vec3(-d * 0.8, 0.0, 0.0));
}

void fragment() {
	float x = UV.x;
	float y = abs(UV.y - 0.5);
	float chev = step(abs(x - 0.35 - y * 0.6), 0.06);
	vec3 cor = mix(cor_equipe, vec3(0.95), chev);
	float borda = step(UV.y, 0.06) + step(0.94, UV.y);
	cor = mix(cor, cor_equipe * 0.35, clamp(borda, 0.0, 1.0));
	ALBEDO = cor;
	EMISSION = cor * 0.25;
	ROUGHNESS = 0.8;
	BACKLIGHT = cor * 0.4;
}
