shader_type spatial;
render_mode cull_disabled;
// Biruta (manga de vento): cone de tecido em faixas laranja e brancas. O Gelo aponta o nó para onde
// o vento vai; aqui o tecido cai com vento fraco e treme com as rajadas.
// Malha: cone ao longo de +Z local (boca em z = 0), UV.y = 0 na boca, 1 na ponta.

uniform float forca = 1.0;      // 0 = sem vento (caída), 1 = cheia
uniform float fase = 0.0;

void vertex() {
	float t = UV.y;
	// Vento fraco: a manga dobra para baixo a partir da boca
	float queda = (1.0 - clamp(forca, 0.0, 1.0)) * t * t * 2.6;
	VERTEX.y -= queda;
	VERTEX.z -= queda * 0.5;
	float tremor = sin(TIME * (7.0 + 5.0 * forca) + t * 9.0 + fase) * 0.09 * t * (0.4 + forca);
	VERTEX.x += tremor;
	VERTEX.y += cos(TIME * 9.0 + t * 7.0 + fase) * 0.05 * t * forca;
}

void fragment() {
	float lista = step(0.5, fract(UV.y * 2.5));
	vec3 cor = mix(vec3(0.95, 0.4, 0.08), vec3(0.96, 0.96, 0.95), lista);
	ALBEDO = cor;
	EMISSION = cor * 0.25;
	ROUGHNESS = 0.85;
	BACKLIGHT = cor * 0.4;
}
