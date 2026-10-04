shader_type spatial;
render_mode cull_back;
// Pedaço de chão arrancado pelo impacto do meteoro (lajes do tamanho de prédios voando): rocha em
// camadas com veios, a face de cima ainda com a terra e o mato queimado do chão que ela era, e a face
// de baixo e as fendas em brasa. Textura em metros (não estica com a escala de cada pedaço).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform float calor = 1.0;

varying vec3 pm;
varying vec3 nl;

void vertex() {
	vec3 esc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	pm = VERTEX * esc;
	nl = normalize(NORMAL / esc);
}

float tri(sampler2D t, vec3 p, vec3 w) {
	float v = texture(t, p.yz).r * w.x + texture(t, p.xz).r * w.y + texture(t, p.xy).r * w.z;
	return clamp((v - 0.5) * 2.4 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 w = pow(abs(nl), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float g = tri(ruido, pm / 170.0, w);
	float f = tri(ruido_fino, pm / 36.0, w);
	float fino = tri(ruido_fino, pm / 8.0, w);
	// Rocha em camadas (estratos no eixo de cima da laje, ondulados), com veios claros e escuros
	float camada = fract(pm.y / 5.0 + g * 1.8);
	vec3 rocha = mix(vec3(0.13, 0.105, 0.09), vec3(0.36, 0.3, 0.25), smoothstep(0.2, 0.8, g));
	rocha = mix(rocha, vec3(0.22, 0.13, 0.09), smoothstep(0.55, 0.9, f) * 0.6);
	rocha *= 0.72 + 0.28 * smoothstep(0.0, 0.14, camada);
	rocha *= 0.65 + 0.7 * fino;
	// Face de cima: terra, raízes e mato chamuscado
	float topo = smoothstep(0.45, 0.75, nl.y + (f - 0.5) * 0.3);
	vec3 solo = mix(vec3(0.1, 0.075, 0.045), vec3(0.06, 0.085, 0.035), smoothstep(0.4, 0.7, f));
	solo = mix(solo, vec3(0.02, 0.018, 0.015), smoothstep(0.5, 0.8, fino) * 0.7);
	vec3 cor = mix(rocha, solo, topo);
	// Brasa: fendas finas pela rocha toda, e a face de baixo (arrancada do chão quente) acesa em manchas
	float fenda = 1.0 - smoothstep(0.0, 0.11, abs(sin(g * 15.0 + f * 2.0)));
	float baixo = smoothstep(0.15, -0.55, nl.y);
	float mancha = smoothstep(0.5, 0.8, f) * baixo;
	float pulsa = 0.8 + 0.2 * sin(TIME * 2.3 + g * 30.0);
	cor = mix(cor, vec3(0.03, 0.02, 0.015), fenda * 0.7);
	ALBEDO = cor;
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
	EMISSION = vec3(1.0, 0.33, 0.06) * calor * pulsa * (fenda * (0.5 + 2.6 * baixo) * (1.0 - topo) + mancha * 1.6) * 3.0;
}
