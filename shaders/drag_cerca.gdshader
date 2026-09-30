shader_type spatial;
render_mode cull_disabled;
// Alambrado (tela de arame em losango) com recorte por alpha. Coordenadas do mundo para o
// losango não esticar: UV.x = metros ao longo, UV.y = metros na altura.

uniform vec3 cor_arame : source_color = vec3(0.55, 0.56, 0.58);
uniform float malha = 0.07;       // lado do losango (m)
uniform float fio = 0.12;         // espessura do fio (fração do losango)

void fragment() {
	vec2 q = vec2(UV.x + UV.y, UV.x - UV.y) / malha;
	vec2 f = abs(fract(q) - 0.5);
	float arame = max(step(0.5 - fio, f.x), step(0.5 - fio, f.y));
	// De longe a tela vira um véu cinza (evita cintilar)
	float dist = length(VERTEX);
	float veu = smoothstep(25.0, 80.0, dist);
	ALPHA = mix(arame * 0.9, 0.16, veu);
	ALBEDO = cor_arame;
	METALLIC = 0.7;
	ROUGHNESS = 0.45;
}
