shader_type spatial;
render_mode cull_disabled;
// Alvenaria de pedra (arenito do cânion) em coordenadas do mundo, para peças instanciadas:
// fiadas de blocos irregulares com argamassa funda, tom por bloco, arestas lascadas,
// manchas escuras de chuva e poeira na base.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_pedra : source_color = vec3(0.58, 0.4, 0.29);
uniform vec3 cor_argamassa : source_color = vec3(0.36, 0.33, 0.3);
uniform float fiada = 0.55;       // altura de cada fiada (m)
uniform float altura_chao = 0.0;
uniform float musgo = 0.0;        // 0..1: musgo nas juntas, no alto dos blocos e em manchas
uniform float rachaduras = 0.0;   // 0..1: fendas finas cortando os blocos

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 an = abs(normal_mundo);
	vec2 q = an.x > an.z ? vec2(p.z, p.y) : vec2(p.x, p.y);
	if (an.y > 0.7) q = p.xz;

	// Fiadas com blocos de comprimento variado, deslocadas a cada linha
	float linha = floor(q.y / fiada);
	float comp = 0.9 + 0.7 * hash(vec2(linha, 3.1));
	float x = q.x / comp + hash(vec2(linha, 7.7)) * 3.0;
	vec2 id = vec2(floor(x), linha);
	vec2 f = vec2(fract(x) * comp, fract(q.y / fiada) * fiada);
	vec2 borda = min(f, vec2(comp, fiada) - f);
	float ruido_borda = texture(ruido, q * 1.7).r * 0.05;
	float argamassa = 1.0 - smoothstep(0.02, 0.05 + ruido_borda, min(borda.x, borda.y));
	if (an.y > 0.7) argamassa *= 0.4;   // topo (capa) quase liso

	float tom = hash(id);
	float grande = texture(ruido, q / 9.0).r;
	float fino = texture(ruido, q / 0.4).r;
	vec3 cor = cor_pedra * (0.78 + 0.3 * tom) * (0.85 + 0.25 * grande) * (0.92 + 0.12 * fino);
	cor = mix(cor, cor * vec3(1.05, 0.92, 0.85), step(0.7, tom) * 0.5);    // blocos mais vermelhos
	cor = mix(cor, cor_argamassa * (0.8 + 0.3 * fino), argamassa);
	// Chuva escorrida e poeira na base
	float escorre = smoothstep(0.62, 0.8, texture(ruido, vec2(q.x / 0.7, q.y / 8.0)).r);
	cor *= 1.0 - 0.25 * escorre;
	float poeira = smoothstep(2.5, 0.0, p.y - altura_chao);
	cor = mix(cor, vec3(0.66, 0.46, 0.32), poeira * 0.5);

	float fenda = (1.0 - smoothstep(0.0, 0.012, abs(texture(ruido, q / 2.6).r - 0.5))) * rachaduras;
	cor = mix(cor, cor * 0.22, fenda);
	float verde = smoothstep(0.52, 0.7, texture(ruido, q / 3.3 + 0.37).r + argamassa * 0.22 + max(normal_mundo.y, 0.0) * 0.3) * musgo;
	cor = mix(cor, vec3(0.15, 0.23, 0.07) * (0.6 + 0.8 * fino), verde);

	ALBEDO = cor;
	ROUGHNESS = 0.9;
	NORMAL_MAP = normalize(vec3(0.5 + (fino - 0.5) * 0.4, 0.5 - argamassa * 0.35, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
