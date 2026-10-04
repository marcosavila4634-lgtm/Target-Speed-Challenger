shader_type spatial;
render_mode cull_back;
// Envelope de dirigível (malha de revolução de Gelo._montar_dirigiveis: UV.x = 0 no nariz a 1 na cauda,
// UV.y = volta): lona prateada em gomos com costuras, nariz e cauda na cor da faixa, duas faixas ao
// longo do corpo, e a geada do frio na parte de cima.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_faixa : source_color = vec3(0.75, 0.06, 0.05);
uniform vec3 cor_lona : source_color = vec3(0.8, 0.82, 0.85);

varying vec3 normal_mundo;

void vertex() {
	normal_mundo = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	float n = texture(ruido, UV * vec2(9.0, 5.0)).r;
	float gomo = fract(UV.y * 20.0);
	float costura = 1.0 - smoothstep(0.0, 0.035, 0.5 - abs(gomo - 0.5));
	float anel = 1.0 - smoothstep(0.0, 0.006, abs(fract(UV.x * 9.0) - 0.5) - 0.494);
	vec3 c = cor_lona * (0.9 + 0.2 * n);
	// Nariz e cauda pintados, e duas faixas correndo pelos lados
	float ponta = step(UV.x, 0.09) + step(0.9, UV.x);
	float lado = abs(fract(UV.y * 2.0 + 0.25) - 0.5);   // 0 nas laterais
	float faixa = step(lado, 0.035) * step(0.09, UV.x) * step(UV.x, 0.9);
	c = mix(c, cor_faixa, clamp(ponta + faixa, 0.0, 1.0));
	c *= 1.0 - 0.3 * max(costura, anel * 0.6);
	// Geada em cima
	float cima = smoothstep(0.55, 0.95, normalize(normal_mundo).y + (n - 0.5) * 0.3);
	c = mix(c, vec3(0.93, 0.96, 1.0), cima * 0.55);
	ALBEDO = c;
	ROUGHNESS = 0.55;
	METALLIC = 0.25;
	SPECULAR = 0.5;
}
