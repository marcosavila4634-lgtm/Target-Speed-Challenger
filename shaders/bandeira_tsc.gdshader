shader_type spatial;
render_mode cull_disabled;
// Bandeira com o logo do jogo ao vento (PlaneMesh subdividido preso no mastro em UV.x = 0).
// A força do vento (uniform global-like `forca`, atualizada pelo Gelo) aumenta a ondulação.

uniform sampler2D logo : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 cor_fundo : source_color = vec3(0.04, 0.04, 0.05);
uniform vec3 cor_borda : source_color = vec3(0.8, 0.07, 0.06);
uniform float amplitude = 0.3;
uniform float frequencia = 1.6;
uniform float velocidade = 4.0;
instance uniform float fase = 0.0;
uniform float forca = 1.0;

void vertex() {
	float solto = UV.x;
	float t = TIME * velocidade;
	float onda = sin(UV.x * frequencia * 6.2831 - t + fase);
	float onda2 = sin(UV.x * 3.1 + UV.y * 2.0 - t * 0.7 + fase * 1.7);
	float a = amplitude * (0.5 + 0.5 * forca);
	VERTEX.z += (onda * 0.8 + onda2 * 0.35) * a * solto;
	VERTEX.y += onda2 * a * 0.2 * solto;
	float d = cos(UV.x * frequencia * 6.2831 - t + fase) * a * solto;
	NORMAL = normalize(NORMAL + vec3(-d * 0.8, 0.0, 0.0));
}

void fragment() {
	vec2 uv = UV;
	if (!FRONT_FACING) {
		uv.x = 1.0 - uv.x;   // verso: o logo não fica espelhado
	}
	vec3 cor = cor_fundo;
	// Logo no meio (arte em fundo preto: soma sobre o fundo escuro)
	vec2 q = (uv - vec2(0.5, 0.5)) / vec2(0.86, 0.72) + 0.5;
	if (q.x > 0.0 && q.x < 1.0 && q.y > 0.0 && q.y < 1.0) {
		cor = max(cor, texture(logo, q).rgb);
	}
	float borda = step(UV.y, 0.07) + step(0.93, UV.y);
	cor = mix(cor, cor_borda, clamp(borda, 0.0, 1.0));
	ALBEDO = cor;
	EMISSION = cor * 0.35;
	ROUGHNESS = 0.8;
	BACKLIGHT = cor * 0.3;
}
