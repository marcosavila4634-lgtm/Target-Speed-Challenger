shader_type spatial;
// Ferro de trem velho (vagão, rodas, bielas, trilhos): tinta desbotada e lascada, manchas e
// escorridos de ferrugem, graxa escura embaixo, aço nu brilhante onde há atrito (boleto do
// trilho, banda de rodagem da roda).
// Coordenadas: `local` = do próprio modelo (peças que giram, como as rodas); senão, do mundo
// relativas ao nó (a textura não "escorrega" quando o vagão anda).

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_tinta : source_color = vec3(0.16, 0.17, 0.18);
uniform float desgaste = 0.5;          // 0 = tinta inteira, 1 = só ferrugem
uniform bool local = false;
uniform bool topo_brilha = false;      // faces viradas para cima em aço nu (boleto do trilho)
uniform bool banda_brilha = false;     // banda de rodagem (lado do cilindro, eixo Y do modelo) em aço nu
uniform float escala = 1.0;

varying vec3 p_tex;
varying vec3 n_mod;
varying vec3 n_mundo;

void vertex() {
	p_tex = local ? VERTEX : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - NODE_POSITION_WORLD;
	n_mod = NORMAL;
	n_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(vec3 p, vec3 n, float s) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return texture(ruido, p.yz / s).r * w.x + texture(ruido, p.xz / s).r * w.y + texture(ruido, p.xy / s).r * w.z;
}

void fragment() {
	vec3 p = p_tex * escala;
	vec3 n = local ? n_mod : n_mundo;
	float grande = tri(p, n, 4.5);
	float medio = tri(p, n, 1.6);
	float fino = tri(p, n, 0.35);

	// Tinta com variação e lascas
	vec3 tinta = cor_tinta * (0.85 + 0.25 * grande);
	float lasca = smoothstep(0.7, 0.74, medio + (1.0 - desgaste) * -0.25 + desgaste * 0.1) * 0.7;
	// Ferrugem: manchas grandes + escorrido vertical
	float manchas = smoothstep(0.3, 0.8, grande + medio * 0.25 + (desgaste - 0.6) * 0.8);
	float escorre = smoothstep(0.6, 0.8, texture(ruido, vec2(p.x * 2.1 + p.z * 1.7, p.y * 0.25)).r) * (1.0 - abs(n.y));
	float ferrugem = clamp(max(manchas, escorre * desgaste) + lasca * 0.6, 0.0, 1.0);
	vec3 cor_ferrugem = mix(vec3(0.16, 0.07, 0.035), vec3(0.34, 0.14, 0.05), medio) * (0.9 + 0.15 * fino);
	vec3 cor = mix(tinta, cor_ferrugem, ferrugem);
	float metal = mix(0.35, 0.0, ferrugem);
	float rug = mix(0.55, 0.95, ferrugem);

	// Aço nu brilhante onde roda/raspa
	float nu = 0.0;
	if (topo_brilha) nu = smoothstep(0.75, 0.9, n.y);
	if (banda_brilha) nu = 1.0 - smoothstep(0.3, 0.5, abs(n_mod.y));
	vec3 aco = vec3(0.62, 0.62, 0.64) * (0.85 + 0.2 * fino);
	cor = mix(cor, aco, nu);
	metal = mix(metal, 0.95, nu);
	rug = mix(rug, 0.28 + 0.15 * fino, nu);

	// Graxa e sujeira nas faces de baixo
	float baixo = smoothstep(-0.2, -0.8, n.y);
	cor *= 1.0 - 0.45 * baixo * (0.6 + 0.4 * grande);

	ALBEDO = cor;
	METALLIC = metal;
	ROUGHNESS = rug;
	NORMAL_MAP = normalize(vec3(0.5 + (fino - 0.5) * 0.5 * (ferrugem + 0.3), 0.5 + (medio - 0.5) * 0.3, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.8;
}
