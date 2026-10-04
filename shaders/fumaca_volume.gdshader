shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;
// Fumaça/poeira em volume para partículas (impacto do meteoro, erupção): cada quadrado vira um novelo
// irregular — contorno roído pelo ruído (cada partícula com um pedaço diferente dele), relevo de
// "couve-flor" iluminado pelo sol de um lado e pela brasa por baixo, e desfiando com a idade.
// Para labaredas, a mesma coisa em blend_add (o código troca o render_mode) com fogo = 1.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 sol_dir = vec3(0.3, 0.8, 0.4);
uniform vec3 cor_luz = vec3(1.0, 0.86, 0.72);
uniform float brasa = 0.0;
uniform float fogo = 0.0;

varying vec3 luz_l;
varying float idade;
varying vec2 semente;

void vertex() {
	float ang = INSTANCE_CUSTOM.x;
	mat4 mw = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	mw = mw * mat4(vec4(cos(ang), -sin(ang), 0.0, 0.0), vec4(sin(ang), cos(ang), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mw;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	// Luz no referencial do quadrado (que gira com a partícula)
	vec3 lv = (VIEW_MATRIX * vec4(normalize(sol_dir), 0.0)).xyz;
	luz_l = vec3(lv.x * cos(ang) - lv.y * sin(ang), lv.x * sin(ang) + lv.y * cos(ang), lv.z);
	idade = INSTANCE_CUSTOM.y;
	semente = vec2(fract(float(INSTANCE_ID) * 0.137), fract(float(INSTANCE_ID) * 0.411));
}

float rn(vec2 uv) {
	return clamp((texture(ruido, uv).r - 0.5) * 2.4 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	c.y = -c.y;
	float r = length(c);
	// Novelos grandes (uns 2 ou 3 por partícula) com um pouco de detalhe: fino demais vira confete
	vec2 uv = UV * 0.16 + semente;
	float n1 = rn(uv);
	float n2 = rn(uv * 2.3 + vec2(0.0, idade * 0.05));
	float n = n1 * 0.7 + n2 * 0.3;
	float dens = 1.0 - smoothstep(0.25, 1.0, r + (0.5 - n) * 0.7);
	dens *= dens * (3.0 - 2.0 * dens);
	dens *= smoothstep(idade * 0.9 - 0.45, idade * 0.9 + 0.25, n + 0.3);
	float e = 0.012;
	float nx = rn(uv + vec2(e, 0.0)) - n1;
	float ny = rn(uv + vec2(0.0, e)) - n1;
	vec3 nn = normalize(vec3(c * 0.9 + vec2(-nx, ny) * 5.0, sqrt(max(1.0 - min(r * r, 1.0), 0.05))));
	float luz = clamp(dot(nn, normalize(luz_l)) * 0.6 + 0.4, 0.0, 1.0);
	vec3 cor = COLOR.rgb * mix(0.6, 1.1, n) * (0.28 + 0.95 * luz) * cor_luz;
	// Brasa por baixo e nos vãos escuros do novelo, enquanto ele é novo
	cor += vec3(1.0, 0.36, 0.07) * brasa * (1.0 - idade) * (1.0 - idade) * (clamp(0.5 - nn.y * 0.7, 0.0, 1.0) + 1.2 * (1.0 - smoothstep(0.15, 0.5, n2)));
	cor = mix(cor, COLOR.rgb * (0.2 + 0.9 * n * n), fogo);
	ALBEDO = cor;
	ALPHA = dens * COLOR.a * mix(1.0, 0.32, fogo);
}
