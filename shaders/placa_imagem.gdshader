shader_type spatial;
render_mode cull_back, depth_draw_opaque;
// Placa pintada (pórtico do Extinction Day): uma imagem pronta recortada pela máscara (o fundo escuro em
// volta do desenho some) e acesa como se o fogo das tochas batesse nela, com um tremor leve de chama.

uniform sampler2D imagem : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D mascara : filter_linear;
uniform float brilho = 0.85;
uniform vec4 recorte = vec4(0.0, 0.0, 1.0, 1.0);   // pedaço da imagem: u0, v0, largura, altura (largura negativa espelha)

void fragment() {
	vec2 uv = recorte.xy + UV * recorte.zw;
	vec4 t = texture(imagem, uv);
	float tremor = 0.92 + 0.08 * sin(TIME * 9.0) * sin(TIME * 5.3 + UV.x * 6.0);
	ALBEDO = t.rgb * 0.55;
	EMISSION = t.rgb * brilho * tremor;
	ROUGHNESS = 0.9;
	ALPHA = t.a * texture(mascara, uv).r;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
