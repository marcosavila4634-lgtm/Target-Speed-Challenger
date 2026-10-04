shader_type spatial;
// Pedra das pirâmides e construções do Egito (Pharaoh's Climb), em coordenadas do mundo:
// - modo 0 (degraus): fiadas de blocos de calcário com juntas desencontradas, cada bloco com tom,
//   arestas gastas e lascas próprias; areia acumulada nos patamares;
// - modo 1 (revestimento): calcário branco polido com juntas finas e escorridos de poeira;
// - modo 2 (arenito com relevo): paredes de templo com colunas de hieróglifos entalhados.
// A base fica mais escura e coberta de areia até `altura_areia` acima de `altura_chao`.

#include "res://shaders/glifos.gdshaderinc"

uniform int modo = 0;
uniform float fiada = 1.8;            // altura de cada fiada (m)
uniform float bloco = 2.6;            // comprimento médio dos blocos (m)
uniform vec3 cor_pedra : source_color = vec3(0.84, 0.7, 0.5);
uniform vec3 cor_pedra_b : source_color = vec3(0.72, 0.56, 0.36);
uniform vec3 cor_areia : source_color = vec3(0.88, 0.69, 0.43);
uniform vec3 cor_tinta_glifo : source_color = vec3(0.16, 0.3, 0.52);
uniform float pintura = 0.35;         // quanto dos hieróglifos ainda tem tinta (azul/vermelho)
uniform float altura_chao = 6.0;
uniform float altura_areia = 3.0;
uniform float coluna_glifos_largura = 3.2;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 n = normalize(normal_mundo);
	float dist = length(p - CAMERA_POSITION_WORLD);
	float perto = smoothstep(900.0, 60.0, dist);
	float aa = max(dist * 0.0015, 0.004);
	float horizontal = smoothstep(0.7, 0.9, n.y);
	// Coordenada ao longo da face (vertical): usa a direção horizontal da face
	vec2 t2 = normalize(vec2(-n.z, n.x) + vec2(1e-5));
	float ao_longo = dot(p.xz, t2);
	float r_grande = texture(ruido, p.xz / 140.0 + p.y / 300.0).r;
	float r_fino = texture(ruido, vec2(ao_longo, p.y) / 6.0).r;

	vec3 cor;
	float rug = 0.85;
	vec3 nn = n;
	if (modo == 1) {
		// Revestimento polido: placas grandes, juntas finas, poeira escorrida
		float fy = fract(p.y / 3.6);
		float fx = fract(ao_longo / 5.5 + floor(p.y / 3.6) * 0.37);
		float junta = 1.0 - smoothstep(0.0, aa * 0.4 + 0.004, min(min(fy, 1.0 - fy) * 3.6, min(fx, 1.0 - fx) * 5.5) - 0.02);
		cor = mix(vec3(0.93, 0.88, 0.78), vec3(0.85, 0.78, 0.66), r_grande);
		cor *= 1.0 - 0.18 * junta * perto;
		float escorre = texture(ruido, vec2(ao_longo / 14.0, p.y / 120.0)).r;
		cor = mix(cor, cor * vec3(0.78, 0.7, 0.6), smoothstep(0.55, 0.8, escorre) * 0.6);
		rug = 0.55;
	} else {
		// Fiadas de blocos
		float id_fiada = floor((p.y + 0.01) / fiada);
		float v = fract((p.y + 0.01) / fiada);
		float desloc = h21(vec2(id_fiada, 3.0)) * bloco;
		float comp = bloco * (0.75 + 0.5 * h21(vec2(id_fiada, 9.0)));
		float id_bloco = floor((ao_longo + desloc) / comp);
		float u = fract((ao_longo + desloc) / comp);
		if (horizontal > 0.5) {
			// Patamar: blocos vistos de cima (grade nas duas direções)
			vec2 g = p.xz / bloco + vec2(id_fiada * 0.37);
			id_bloco = floor(g.x) + floor(g.y) * 17.0;
			u = fract(g.x);
			v = fract(g.y);
		}
		float tom = h21(vec2(id_bloco, id_fiada));
		cor = mix(cor_pedra, cor_pedra_b, tom * 0.8 + r_grande * 0.4);
		cor *= 0.88 + 0.2 * h21(vec2(id_bloco * 3.1, id_fiada + 1.0));
		// Juntas e arestas gastas (escurecem; a normal "arredonda" a borda)
		float bu = min(u, 1.0 - u) * comp;
		float bv = min(v, 1.0 - v) * (horizontal > 0.5 ? bloco : fiada);
		float borda = min(bu, bv);
		float junta = 1.0 - smoothstep(0.02, 0.09 + aa, borda + (r_fino - 0.5) * 0.06);
		cor *= 1.0 - 0.45 * junta;
		// Lascas e erosão dentro do bloco
		float lasca = smoothstep(0.62, 0.8, texture(ruido, vec2(ao_longo, p.y) / 2.3 + tom * 7.0).r);
		cor *= 1.0 - 0.18 * lasca * perto;
		if (perto > 0.01) {
			vec3 lado = vec3(t2.x, 0.0, t2.y);
			float su = (u < 0.5 ? -1.0 : 1.0) * (1.0 - smoothstep(0.0, 0.12, bu));
			float sv = (v < 0.5 ? -1.0 : 1.0) * (1.0 - smoothstep(0.0, 0.12, bv));
			if (horizontal < 0.5) {
				nn += (lado * su + vec3(0.0, 1.0, 0.0) * sv) * 0.35 * perto;
			}
			nn += (vec3(lasca - 0.5, 0.0, r_fino - 0.5)) * 0.25 * perto;
		}
		// Areia nos patamares e na base
		float areia = horizontal * smoothstep(0.45, 0.75, texture(ruido, p.xz / 9.0).r + 0.25);
		cor = mix(cor, cor_areia, areia * 0.75);
		if (modo == 2) {
			// Templo: colunas de hieróglifos entalhados, com restos de pintura
			float larg = coluna_glifos_largura;
			float id_col = floor(ao_longo / (larg * 1.25));
			float x_col = (fract(ao_longo / (larg * 1.25)) - 0.5) * larg * 1.25;
			vec2 g = coluna_glifos(vec2(x_col, p.y), larg, id_col, aa);
			float vertical = 1.0 - horizontal;
			cor *= 1.0 - (0.35 * g.x + 0.25 * g.y) * vertical;
			vec3 tinta = mix(cor_tinta_glifo, vec3(0.62, 0.16, 0.1), step(0.5, h21(vec2(id_col, floor(p.y / larg)))));
			cor = mix(cor, tinta, g.x * pintura * vertical * step(0.4, r_grande));
			nn -= vec3(t2.x, 0.0, t2.y) * g.x * 0.25 * vertical * perto;
		}
	}
	float base = 1.0 - smoothstep(altura_chao, altura_chao + altura_areia, p.y + (r_grande - 0.5) * 2.0);
	cor = mix(cor, cor_areia * 0.95, base * 0.85);
	// Pé das construções mais escuro (oclusão do chão)
	cor *= mix(0.78, 1.0, smoothstep(altura_chao, altura_chao + 14.0, p.y));
	ALBEDO = cor;
	ROUGHNESS = rug;
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
}
