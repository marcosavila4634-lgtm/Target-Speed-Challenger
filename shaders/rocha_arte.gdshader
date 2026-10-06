shader_type spatial;
// Rochas gigantes do Serpent's Climb (RochasSelva): a pele é a própria arte do dono projetada por três vistas
// (frente no plano XY, lado no ZY, cima no XZ) e misturada pela direção da face — cada face mostra a vista
// que olha para ela, nada esticado. Coordenadas da malha: x -1..1, y 0..Y, z -D..D (tools/serpents_climb/rochas.gd).
// De perto entram o grão da pedra no espaço do mundo e o relevo pelo claro-escuro da arte; musgo onde a face
// olha para cima e no pé (a rocha "nasce" do morro coberto de mata).

uniform sampler2D frente : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D lado : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D cima : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float alto_y = 1.3;
uniform float fundo_d = 0.9;
uniform vec3 cor_musgo : source_color = vec3(0.16, 0.26, 0.08);
uniform float musgo = 0.55;
// Montanha da armadilha: só frente e costas mostram a arte (com o arco); laterais e topo usam um pedaço
// de rocha da própria frente (mosaico_rect, em UV) repetido em espelho no espaço do mundo (mosaico_m metros).
uniform bool lados_mosaico = false;
uniform vec4 mosaico_rect = vec4(0.05, 0.45, 0.3, 0.45);
uniform float mosaico_m = 40.0;
uniform bool so_mosaico = false;
uniform sampler2D ladrilho : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // rocha sem emenda (rocha_ladrilho.png)   // todas as faces em mosaico (aro das bocas do túnel)

vec2 espelho(vec2 u) {
	return abs(fract(u * 0.5) * 2.0 - 1.0);
}

varying vec3 local;
varying vec3 nrm_local;
varying vec3 mundo;
varying mat3 modelo_v;

void vertex() {
	local = VERTEX;
	nrm_local = NORMAL;
	mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	modelo_v = mat3(MODEL_MATRIX);
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float ruido(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Mosaico nos três eixos do mundo (cada face pega a projeção que olha para ela: nada esticado)
vec3 mosaico3(vec3 n_local) {
	vec3 nm = normalize(modelo_v * n_local);
	vec3 w = pow(abs(nm), vec3(4.0));
	w /= (w.x + w.y + w.z + 0.0001);
	// Duas escalas misturadas (a repetição some) e cada eixo deslocado
	vec3 cx = mix(texture(ladrilho, vec2(mundo.z, -mundo.y) / mosaico_m).rgb, texture(ladrilho, vec2(mundo.z, -mundo.y) / (mosaico_m * 2.7) + 0.37).rgb, 0.35);
	vec3 cz = mix(texture(ladrilho, vec2(mundo.x, -mundo.y) / mosaico_m + 0.5).rgb, texture(ladrilho, vec2(mundo.x, -mundo.y) / (mosaico_m * 2.7) + 0.11).rgb, 0.35);
	vec3 cy = mix(texture(ladrilho, mundo.xz / mosaico_m + 0.23).rgb, texture(ladrilho, mundo.xz / (mosaico_m * 2.7) + 0.71).rgb, 0.35);
	return cx * w.x + cy * w.y + cz * w.z;
}

vec3 vistas(vec3 p, vec3 n) {
	float v = clamp(1.0 - p.y / alto_y, 0.002, 0.998);
	// Frente vista de +z; a face de trás é a mesma arte espelhada (u invertido)
	vec2 uf = vec2(clamp((p.x * sign(n.z + 0.0001)) * 0.5 + 0.5, 0.002, 0.998), v);
	vec2 ul = vec2(clamp((-p.z / fundo_d * sign(n.x + 0.0001)) * 0.5 + 0.5, 0.002, 0.998), v);
	vec2 uc = vec2(clamp(p.x * 0.5 + 0.5, 0.002, 0.998), clamp(p.z / fundo_d * 0.5 + 0.5, 0.002, 0.998));
	vec3 w = pow(abs(n), vec3(4.0));
	w.y = n.y > 0.0 ? w.y : w.y * 0.15;   // por baixo não há vista: frente e lado cobrem
	w /= (w.x + w.y + w.z + 0.0001);
	if (so_mosaico) {
		return mosaico3(n);
	}
	if (lados_mosaico) {
		return texture(frente, uf).rgb * w.z + mosaico3(n) * (w.x + w.y);
	}
	return texture(frente, uf).rgb * w.z + texture(lado, ul).rgb * w.x + texture(cima, uc).rgb * w.y;
}

float lum(vec3 c) {
	return dot(c, vec3(0.3, 0.59, 0.11));
}

void fragment() {
	vec3 n = normalize(nrm_local);
	vec3 c = vistas(local, n);
	// Tom da arte do dono (cinza-marrom): a correção de luz deixava a pedra clara e laranja
	c = mix(c, vec3(dot(c, vec3(0.3, 0.59, 0.11))), 0.3) * vec3(0.78, 0.76, 0.74);
	float dist = length(mundo - CAMERA_POSITION_WORLD);
	float perto = 1.0 - smoothstep(60.0, 260.0, dist);
	// Grão de perto e manchas de umidade grandes
	float g = ruido(mundo * 1.7) * 0.6 + ruido(mundo * 5.3) * 0.4;
	c *= 1.0 + (g - 0.5) * 0.25 * perto;
	c *= mix(0.78, 1.08, ruido(mundo * 0.03));
	// Musgo: em cima e no pé, mais nas fendas escuras
	float cobre = smoothstep(0.35, 0.8, n.y) * 0.8 + smoothstep(alto_y * 0.18, 0.0, local.y);
	cobre *= smoothstep(0.35, 0.7, ruido(mundo * 0.12) + (0.45 - lum(c)) * 0.6);
	c = mix(c, cor_musgo * (0.7 + 0.6 * g), clamp(cobre, 0.0, 1.0) * musgo);
	ALBEDO = c;
	// Relevo da arte: inclina a normal pelo gradiente do claro-escuro na tela (blocos e fendas pegam luz)
	float l0 = lum(c);
	vec3 dn = vec3(dFdx(l0), dFdy(l0), 0.0) * 2.2;
	NORMAL = normalize(NORMAL - dn.x * TANGENT * 0.0 + vec3(-dn.x, -dn.y, 0.0) * 0.6);
	ROUGHNESS = mix(0.86, 0.97, cobre);
	SPECULAR = 0.25;
}
