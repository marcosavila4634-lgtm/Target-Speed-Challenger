shader_type spatial;
render_mode cull_disabled;
// Esculturas montadas a partir das artes do dono vistas de vários lados (MuroSerpentes: o muro das cabeças que
// cospem água e as cabeças). Cada face pega a vista que olha para ela, pela direção da própria face: frente
// (plano XY, +z), costas (XY, -z), cima (XZ) e lado (ZY). Nenhuma face é a imagem esticada.
// As imagens já vêm recortadas e alinhadas à caixa da peça: uv = posição local dentro de cada retângulo.
// COLOR.r = sombra; COLOR.g = 1 → pedra lisa da própria arte em mosaico (fundo dos nichos, base, fundação);
// COLOR.b = 1 → dentro da boca (pedra avermelhada escura).

uniform sampler2D frente : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D tras : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D cima : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D lado : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D pedra : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D boca : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 caixa_xy;         // x0, y0 (embaixo), x1, y1 (em cima): frente e costas
uniform vec2 caixa_z;          // z0 (atrás), z1 (na frente): cima e lado
uniform bool tem_tras = true;  // costas já alinhadas à frente (mesmo u); sem costas: a frente
uniform bool tem_lado = false; // sem arte de lado: pedra em mosaico
uniform vec2 pedra_m = vec2(3.6, 2.0);   // m de cada repetição da pedra lisa (o retalho é mais largo que alto)
uniform float pedra_luz = 1.3;
uniform float brilho = 0.16;

varying vec3 lp;
varying vec3 nl;

void vertex() {
	lp = VERTEX;
	nl = NORMAL;
}

vec2 espelho(vec2 u) {
	return abs(fract(u * 0.5) * 2.0 - 1.0);
}

vec3 mosaico(sampler2D t, vec3 p, vec3 w) {
	vec3 cx = texture(t, espelho(vec2(p.z, -p.y) / pedra_m)).rgb;
	vec3 cy = texture(t, espelho(p.xz / pedra_m + 0.37)).rgb;
	vec3 cz = texture(t, espelho(vec2(p.x, -p.y) / pedra_m + 0.61)).rgb;
	return (cx * w.x + cy * w.y + cz * w.z) * pedra_luz;
}

void fragment() {
	// Direção da face (não a normal suavizada): degraus e quinas escolhem a vista certa
	// Normal suavizada da malha: a vista muda devagar nas curvas, sem trocar de textura a cada triângulo
	vec3 nf = normalize(nl);
	vec3 w = pow(abs(nf), vec3(4.0));
	w /= (w.x + w.y + w.z + 0.0001);
	float u = (lp.x - caixa_xy.x) / (caixa_xy.z - caixa_xy.x);
	float v = 1.0 - (lp.y - caixa_xy.y) / (caixa_xy.w - caixa_xy.y);
	float zz = (lp.z - caixa_z.x) / (caixa_z.y - caixa_z.x);
	vec2 uf = clamp(vec2(u, v), vec2(0.001), vec2(0.999));
	vec3 c_frente = nf.z >= 0.0 || !tem_tras ? texture(frente, uf).rgb : texture(tras, uf).rgb;
	// Fora da caixa da vista (cornijas e saliências além da face): a pedra da arte, não a beirada esticada
	bool na_caixa = zz > -0.02 && zz < 1.02;
	vec3 c_cima = nf.y >= 0.0 && na_caixa ? texture(cima, clamp(vec2(u, zz), vec2(0.001), vec2(0.999))).rgb : mosaico(pedra, lp, vec3(0.0, 1.0, 0.0));
	vec3 c_lado = tem_lado && na_caixa ? texture(lado, clamp(vec2(zz, v), vec2(0.001), vec2(0.999))).rgb : mosaico(pedra, lp, vec3(1.0, 0.0, 0.0));
	vec3 cor = c_frente * w.z + c_cima * w.y + c_lado * w.x;
	if (COLOR.g > 0.5) {
		cor = mosaico(pedra, lp, w);
	}
	if (COLOR.b > 0.5) {
		cor = mosaico(boca, lp * 1.6, w) * 0.5;
	}
	ALBEDO = cor * COLOR.r;
	EMISSION = cor * COLOR.r * brilho;
	ROUGHNESS = 0.86;
	SPECULAR = 0.2;
}
