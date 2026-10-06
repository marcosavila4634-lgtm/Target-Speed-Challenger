shader_type spatial;
render_mode cull_disabled;
// Cabeça de pedra da serpente (CabecaPedra; malhas de tools/serpents_climb/cabeca_pedra.gd): a cor é a própria
// arte do dono. COLOR.g = qual imagem (0 frente, 1 lado, 2 parede interna, 3 pena, 4 presa, 5 disco, 6 pedra,
// 7 blocos), COLOR.r = sombra das paredes do relevo. Imagens em mosaico (interna, pena nas rampas, pedra,
// blocos) repetem em espelho: sem emenda. O que é luz na arte (olhos, lâmpadas do túnel) brilha sozinho.

uniform sampler2D frente : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D lado : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D interna : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D pena : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D presa : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D pedra : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D blocos : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float brilho = 0.14;
uniform float luzes = 2.2;

vec2 espelho(vec2 u) {
	return abs(fract(u * 0.5) * 2.0 - 1.0);
}

void fragment() {
	int qual = int(COLOR.g * 10.0);
	vec3 c;
	float acesa = 0.0;
	if (qual == 0) {
		c = texture(frente, UV).rgb;
		acesa = 1.0;
	} else if (qual == 1 || qual == 5) {
		c = texture(lado, UV).rgb;
		acesa = 1.0;
	} else if (qual == 2) {
		c = texture(interna, espelho(UV)).rgb;
		acesa = 1.0;
	} else if (qual == 3) {
		c = texture(pena, espelho(UV)).rgb;
	} else if (qual == 4) {
		c = texture(presa, UV).rgb;
	} else if (qual == 6) {
		c = texture(pedra, espelho(UV)).rgb;
	} else {
		c = texture(blocos, espelho(UV)).rgb;
	}
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float luz = acesa * smoothstep(0.7, 0.92, lum) * smoothstep(0.2, 0.45, c.r - c.b);
	ALBEDO = c * COLOR.r;
	EMISSION = c * (COLOR.r * brilho + luz * luzes);
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
