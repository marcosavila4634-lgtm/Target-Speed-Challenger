shader_type spatial;
render_mode cull_disabled;
// Pórticos esculpidos a partir de uma arte pronta (TunelVulcao.relevo_arte): a imagem é a cor da malha em
// relevo, iluminada pela luz da cena (sol, tochas) — não um painel aceso. Só o que é fogo no desenho
// (chamas, brasas das letras) brilha por conta própria, tremendo. COLOR = sombra das paredes laterais.

uniform sampler2D imagem : source_color, filter_linear_mipmap_anisotropic;
uniform float brilho = 0.22;     // um mínimo de luz própria (as etapas à noite)
uniform float fogo = 1.5;

void fragment() {
	vec3 t = texture(imagem, UV).rgb;
	float lum = dot(t, vec3(0.3, 0.59, 0.11));
	// Chama: muito claro e bem mais vermelho que azul
	float chama = smoothstep(0.55, 0.85, lum) * smoothstep(0.25, 0.6, (t.r - t.b));
	float tremor = 0.85 + 0.15 * sin(TIME * 9.0 + UV.x * 40.0) * sin(TIME * 5.3 + UV.y * 25.0);
	ALBEDO = t * COLOR.r;
	EMISSION = t * COLOR.r * (brilho + chama * fogo * tremor);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}
