shader_type spatial;
// Foca escaneada (assets/frozen/animais/foca/foca_escaneada.glb, CC-BY Loïc Norgeot): só a forma; a pintura
// da estatueta é trocada pela pele de foca-leopardo (mesma de foca.gdshader). Os olhos pretos vêm da
// textura original. Sem ossos: o vertex() dobra a malha — cabeça e pescoço giram em torno do pescoço
// (olhar, preparo, bote), o peito respira e a frente do corpo dá o bote. Coordenadas do modelo: cabeça
// para +X, ~0,38 m (o nó escala); a pele usa as coordenadas convertidas para as da foca de 3,6 m.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float boca = 0.0;
uniform sampler2D original : source_color, filter_linear_mipmap;
uniform vec3 pivo = vec3(0.105, 0.085, 0.0);   // pescoço, no espaço do modelo
uniform float cab_pitch = 0.0;   // + = cabeça para cima
uniform float cab_yaw = 0.0;
uniform float peito_pitch = 0.0;
uniform float respira = 0.0;
uniform vec3 cor_costas : source_color = vec3(0.12, 0.13, 0.15);
uniform vec3 cor_flanco : source_color = vec3(0.36, 0.38, 0.41);
uniform vec3 cor_barriga : source_color = vec3(0.66, 0.67, 0.68);

varying vec3 p_rest;
varying vec3 n_rest;

mat3 rot_y(float a) { return mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a))); }
mat3 rot_z(float a) { return mat3(vec3(cos(a), sin(a), 0.0), vec3(-sin(a), cos(a), 0.0), vec3(0.0, 0.0, 1.0)); }

void vertex() {
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	p_rest = vec3(-v.z, v.y, v.x) * 9.5;
	n_rest = vec3(-n.z, n.y, n.x);
	// Respiração: o meio do corpo incha
	float meio = smoothstep(-0.16, 0.0, v.x) * smoothstep(0.12, 0.0, v.x);
	v.yz *= 1.0 + respira * meio;
	// Frente do corpo (peito) inclina em torno do meio
	float w_p = smoothstep(-0.02, 0.1, v.x);
	vec3 piv_p = vec3(0.0, 0.0, 0.0);
	mat3 rp = rot_z(peito_pitch);
	v = mix(v, piv_p + rp * (v - piv_p), w_p);
	n = normalize(mix(n, rp * n, w_p));
	// Cabeça e pescoço em torno do pescoço (que já acompanhou o peito)
	float w_c = smoothstep(0.075, 0.135, VERTEX.x);
	vec3 piv_c = rp * pivo;
	mat3 rc = rot_y(cab_yaw) * rot_z(cab_pitch);
	v = mix(v, piv_c + rc * (v - piv_c), w_c);
	n = normalize(mix(n, rc * n, w_c));
	VERTEX = v;
	NORMAL = n;
}

float tri(vec3 p, vec3 n, float escala) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(ruido, p.zy / escala).r * w.x + texture(ruido, p.xz / escala).r * w.y + texture(ruido, p.xy / escala).r * w.z;
}

void fragment() {
	vec3 p = p_rest;
	vec3 n_mod = normalize(n_rest);
	vec3 orig = texture(original, UV).rgb;
	float olho = smoothstep(0.16, 0.08, dot(orig, vec3(0.33))) * step(p_rest.z, 2.0) * step(1.0, p_rest.z);
	if (boca > 0.5) {
		float m = texture(ruido, p.xz * 6.0).r;
		vec3 cor_b = mix(vec3(0.55, 0.16, 0.2), vec3(0.32, 0.06, 0.09), smoothstep(0.3, 0.8, m));
		ALBEDO = cor_b;
		ROUGHNESS = 0.18;
		SPECULAR = 0.7;
		CLEARCOAT = 0.6;
	} else {
		// Altura do ponto em relação ao centro do corpo: costas x barriga (independente da pose)
		float dorso = smoothstep(-0.15, 0.55, n_mod.y + (p.y - 0.45) * 0.4);
		vec3 cor = mix(cor_barriga, cor_flanco, smoothstep(0.0, 0.45, dorso));
		cor = mix(cor, cor_costas, smoothstep(0.4, 0.9, dorso));
		// Garganta mais clara
		cor = mix(cor, cor_barriga * 1.08, smoothstep(0.75, 1.1, p.z) * (1.0 - dorso) * 0.6);
		// Pintas: manchas irregulares com borda suja
		float m1 = tri(p * vec3(1.0, 1.0, 0.75), n_mod, 0.26);
		float m2 = tri(p + 3.7, n_mod, 0.11);
		float pinta = smoothstep(0.56, 0.62, m1 + (m2 - 0.5) * 0.3);
		cor = mix(cor, vec3(0.05, 0.05, 0.06), pinta * mix(0.85, 0.35, dorso));
		float clara = smoothstep(0.66, 0.72, tri(p + 9.1, n_mod, 0.2)) * dorso;
		cor = mix(cor, cor_flanco * 1.3, clara * 0.5);
		// Pelo curto: variação fina
		float pelo = tri(p, n_mod, 0.018);
		cor *= 0.86 + 0.28 * pelo;
		// Geada nas costas em pontinhos
		float geada = step(0.86, tri(p * 5.0, n_mod, 0.4)) * smoothstep(0.6, 1.0, dorso);
		cor = mix(cor, vec3(0.9, 0.95, 1.0), geada * 0.8);
		// Relevo: pelo e dobras do pescoço viram normal (derivada da altura na tela)
		float dobra = sin(p.z * 70.0 + tri(p, n_mod, 0.3) * 6.0) * smoothstep(0.75, 0.95, p.z) * smoothstep(1.2, 1.02, p.z);
		float h = pelo * 0.35 + m2 * 0.25 + dobra * 0.5;
		vec3 dpx = dFdx(VERTEX);
		vec3 dpy = dFdy(VERTEX);
		vec3 r1 = cross(dpy, NORMAL);
		vec3 r2 = cross(NORMAL, dpx);
		float det = dot(dpx, r1);
		vec3 grad = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
		NORMAL = normalize(abs(det) * NORMAL - 0.006 * grad);
		cor = mix(cor, vec3(0.01), olho);
		ALBEDO = cor;
		ROUGHNESS = mix(mix(0.32, 0.7, geada), 0.02, olho);
		SPECULAR = 0.55;
		CLEARCOAT = mix(0.45 * (1.0 - geada), 1.0, olho);
		CLEARCOAT_ROUGHNESS = 0.25;
		RIM = 0.25;
		RIM_TINT = 0.6;
	}
}
