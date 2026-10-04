shader_type spatial;
// Megalodonte congelado do Frozen Peak (TubaraoGelo; modelo CC-BY, ver creditos.txt da pasta). O modelo
// não tem ossos: a mandíbula de baixo abre aqui, girando em volta da articulação (`artic`, espaço da
// malha: +Z = focinho, +Y = dorso). Por cima da pele, geada e gelo azulado (ele está congelado).

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float abre = 0.96;                       // rad
uniform vec3 artic = vec3(0.0, 7.2, 10.0);
uniform float geada = 0.55;

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	vec3 p = VERTEX;
	float w = smoothstep(artic.y + 0.25, artic.y - 0.35, p.y) * smoothstep(artic.z - 2.5, artic.z + 0.3, p.z);
	float a = abre * w;
	float c = cos(a);
	float s = sin(a);
	vec3 d = p - artic;
	VERTEX = artic + vec3(d.x, d.y * c - d.z * s, d.y * s + d.z * c);
	NORMAL = normalize(vec3(NORMAL.x, NORMAL.y * c - NORMAL.z * s, NORMAL.y * s + NORMAL.z * c));
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 cor = texture(tex, UV).rgb;
	vec3 p = pos_mundo;
	vec3 n = normalize(normal_mundo);
	float n1 = texture(ruido, p.xz / 37.0 + p.y / 41.0).r;
	float n2 = texture(ruido, p.xy / 6.0 + p.z / 7.0).r;
	// Geada: mais nas faces de cima e em manchas; escorridos de gelo descendo
	float escorre = texture(ruido, vec2((p.x + p.z) / 9.0, p.y / 90.0)).r;
	float g = smoothstep(0.75 - geada * 0.5, 0.95, n1 * 0.6 + n2 * 0.3 + max(n.y, 0.0) * 0.45 + smoothstep(0.6, 0.85, escorre) * 0.25);
	cor = mix(cor, cor * vec3(0.55, 0.8, 1.05) + vec3(0.03, 0.08, 0.14), 0.45);   // tom de coisa congelada
	cor = mix(cor, vec3(0.86, 0.94, 1.0), g * 0.85);
	float borda = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = cor;
	ROUGHNESS = mix(0.22, 0.8, g);
	SPECULAR = 0.7;
	CLEARCOAT = (1.0 - g) * 0.7;
	CLEARCOAT_ROUGHNESS = 0.08;
	EMISSION = vec3(0.25, 0.6, 1.0) * borda * 0.35;
}
