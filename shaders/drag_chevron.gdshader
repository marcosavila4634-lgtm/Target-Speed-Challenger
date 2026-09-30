shader_type spatial;
// Painel de chevrons (muretas e banners da pista de arrancada): fundo azul-marinho,
// setas brancas e filete neon na cor do evento. UV.x ao longo, UV.y de baixo para cima.

uniform vec3 cor_fundo : source_color = vec3(0.03, 0.06, 0.16);
uniform vec3 cor_seta : source_color = vec3(0.92, 0.94, 1.0);
uniform vec3 cor_neon : source_color = vec3(0.2, 0.45, 1.0);
uniform float repeticoes = 3.0;
uniform bool vertical = false;     // true = setas apontando para baixo (banner em pé)
uniform float brilho = 1.5;

void fragment() {
	vec2 uv = UV;
	if (vertical) {
		uv = vec2(1.0 - UV.y, UV.x);
	}
	float f = fract(uv.x * repeticoes + abs(uv.y - 0.5) * 1.1);
	float seta = step(f, 0.28) * step(0.12, uv.y) * step(uv.y, 0.88);
	float borda = step(uv.y, 0.05) + step(0.95, uv.y);
	vec3 cor = mix(cor_fundo, cor_seta, seta);
	ALBEDO = mix(cor, cor_neon, clamp(borda, 0.0, 1.0));
	EMISSION = cor_neon * clamp(borda, 0.0, 1.0) * brilho + cor_seta * seta * 0.25;
	ROUGHNESS = 0.5;
}
