shader_type spatial;
// Rocha solta (pedras que caem do pórtico no Extinction Day, pedregulhos do pé dos pilares): textura em
// metros no referencial da pedra (gira e cai junto com ela) — grão fino, manchas claras e escuras,
// estratos inclinados, fendas escuras fundas e musgo na face de cima (pelo mundo: fica sempre em cima).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_clara : source_color = vec3(0.42, 0.39, 0.34);
uniform vec3 cor_escura : source_color = vec3(0.16, 0.15, 0.14);
uniform float musgo = 0.6;

varying vec3 pm;
varying vec3 nl;
varying vec3 n_mundo;

void vertex() {
	vec3 esc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	pm = VERTEX * esc;
	nl = normalize(NORMAL / esc);
	n_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(sampler2D t, vec3 p, vec3 w) {
	float v = texture(t, p.yz).r * w.x + texture(t, p.xz).r * w.y + texture(t, p.xy).r * w.z;
	return clamp((v - 0.5) * 2.4 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 w = pow(abs(nl), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float g = tri(ruido, pm / 34.0, w);
	float m = tri(ruido_fino, pm / 11.0, w);
	float f = tri(ruido_fino, pm / 2.6, w);
	vec3 cor = mix(cor_escura, cor_clara, smoothstep(0.15, 0.85, g * 0.6 + m * 0.4));
	// Estratos inclinados e veios de quartzo
	float camada = fract((pm.y + pm.x * 0.35) / 0.9 + g * 2.2);
	cor *= 0.8 + 0.2 * smoothstep(0.0, 0.18, camada);
	cor = mix(cor, vec3(0.5, 0.48, 0.45), (1.0 - smoothstep(0.0, 0.03, abs(m - 0.5))) * 0.14);
	cor *= 0.86 + 0.28 * f;
	// Fendas
	float fenda = 1.0 - smoothstep(0.0, 0.035, abs(sin(g * 9.0 + m * 3.0)));
	cor = mix(cor, vec3(0.03, 0.028, 0.025), fenda * 0.85);
	// Musgo em cima e nas reentrâncias
	float verde = smoothstep(0.45, 0.85, n_mundo.y + (m - 0.5) * 0.7) * musgo;
	cor = mix(cor, mix(vec3(0.07, 0.13, 0.04), vec3(0.2, 0.27, 0.08), f), verde * 0.85);
	// Relevo do grão
	vec3 nn = normalize(NORMAL + (VIEW_MATRIX * vec4((vec3(f, m, g) - 0.5) * 0.9, 0.0)).xyz * 0.16);
	NORMAL = nn;
	ALBEDO = cor;
	ROUGHNESS = mix(0.92, 0.75, fenda);
	SPECULAR = 0.2;
	AO = 1.0 - fenda * 0.5;
}
