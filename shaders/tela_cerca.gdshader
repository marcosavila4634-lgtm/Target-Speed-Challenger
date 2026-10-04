shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Tela de arame em losango (alambrado) dos painéis do cercado do tiranossauro. De perto se vê cada fio,
// com o trançado e a ferrugem; de longe, onde o fio fica mais fino que um ponto da tela, vira um véu
// cinza meio transparente (sem isso a tela cintilava). Num quadrado de 1 x 1 esticado: `tamanho` (m)
// é o tamanho do painel, por instância.

instance uniform vec2 tamanho = vec2(1.0);
uniform float malha = 0.2;      // tamanho do losango (m)
uniform float fio = 0.026;      // espessura do arame (m)
uniform vec3 cor : source_color = vec3(0.5, 0.52, 0.53);
uniform vec3 cor_ferrugem : source_color = vec3(0.34, 0.18, 0.08);

varying vec2 plano;

float sorteio(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	plano = UV * tamanho;
}

void fragment() {
	vec2 d = vec2(plano.x + plano.y, plano.x - plano.y) * 0.7071;
	vec2 f = abs(fract(d / malha) - 0.5) * malha;
	float dist = min(f.x, f.y);
	float arame = 1.0 - smoothstep(fio * 0.5, fio * 0.5 + 0.004, dist);
	float ponto = max(fwidth(plano.x), fwidth(plano.y));
	float longe = smoothstep(fio * 0.6, fio * 2.5, ponto);
	float redondo = 1.0 - 0.5 * smoothstep(0.0, fio * 0.5, dist);
	// Ferrugem em manchas grandes, mais forte embaixo (onde a água escorre e para)
	vec2 cel = floor(plano / 0.45);
	vec2 fr = fract(plano / 0.45);
	fr = fr * fr * (3.0 - 2.0 * fr);
	float n = mix(mix(sorteio(cel), sorteio(cel + vec2(1.0, 0.0)), fr.x), mix(sorteio(cel + vec2(0.0, 1.0)), sorteio(cel + vec2(1.0)), fr.x), fr.y);
	float ferr = smoothstep(0.45, 0.8, n + 0.25 * (UV.y - 0.5));
	vec3 c = mix(cor, cor_ferrugem, ferr * 0.7);
	ALBEDO = c * mix(redondo, 0.8, longe);
	METALLIC = 0.55 * (1.0 - ferr);
	ROUGHNESS = mix(0.45, 0.9, ferr);
	EMISSION = c * 0.06;   // aparece nas etapas à noite
	ALPHA = mix(arame, 0.3, longe);
}
