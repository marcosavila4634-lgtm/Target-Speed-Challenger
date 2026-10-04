shader_type spatial;
render_mode cull_disabled;
// Envelope de balão de ar quente (malha de revolução de DragPista._malha_balao: UV.x = volta,
// UV.y = altura de 0 na boca a 1 no topo): 16 gomos alternando duas cores, faixa de uma terceira
// perto do bojo, costuras escuras entre os gomos e, com `com_logo`, dois painéis pretos com a logo.

uniform vec3 cor_a : source_color = vec3(0.85, 0.1, 0.08);
uniform vec3 cor_b : source_color = vec3(0.95, 0.9, 0.85);
uniform vec3 cor_c : source_color = vec3(0.1, 0.25, 0.7);
uniform sampler2D logo : source_color, filter_linear_mipmap, repeat_disable;
uniform float com_logo = 0.0;

void fragment() {
	float gomo = floor(UV.x * 16.0);
	vec3 c = mod(gomo, 2.0) < 1.0 ? cor_a : cor_b;
	c = mix(c, cor_c, step(0.7, UV.y) * step(UV.y, 0.76) + step(UV.y, 0.1));
	float costura = 1.0 - smoothstep(0.0, 0.03, 0.5 - abs(fract(UV.x * 16.0) - 0.5));
	// Painéis da logo (fundo preto da própria imagem), dos dois lados do balão
	float k = fract(UV.x * 2.0);
	if (com_logo > 0.5 && k < 0.5 && UV.y > 0.4 && UV.y < 0.66) {
		c = texture(logo, vec2(1.0 - k / 0.5, 1.0 - (UV.y - 0.4) / 0.26)).rgb;
		costura = 0.0;
	}
	ALBEDO = c * (1.0 - 0.35 * costura);
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	BACKLIGHT = c * 0.25;   // tecido fino: o sol atravessa um pouco
}
