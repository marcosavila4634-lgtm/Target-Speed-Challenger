shader_type spatial;
// Pedra dos templos da selva (Serpent's Climb), em coordenadas do mundo:
// - modo 0 (blocos): fiadas de calcário cinza-amarelado, juntas desencontradas, restos de estuque
//   vermelho, musgo nos topos e escorridos escuros de umidade;
// - modo 1 (estuque): reboco pintado (vermelho, ocre) descascando, mostrando a pedra por baixo;
// - modo 2 (friso): relevo entalhado — greca em degraus (xicalcoliuhqui) e escamas de serpente;
// - modo 3 (pedra redonda): pedra rolante entalhada com raios e anéis (coordenadas do objeto).

uniform int modo = 0;
uniform float fiada = 1.2;
uniform float bloco = 1.9;
uniform vec3 cor_pedra : source_color = vec3(0.62, 0.6, 0.52);
uniform vec3 cor_pedra_b : source_color = vec3(0.48, 0.46, 0.4);
uniform vec3 cor_musgo : source_color = vec3(0.2, 0.32, 0.1);
uniform vec3 cor_estuque : source_color = vec3(0.62, 0.17, 0.1);
uniform float pintura = 0.45;
uniform float musgo = 1.0;
uniform float altura_chao = 6.5;
uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;

varying vec3 pos_mundo;
varying vec3 normal_mundo;
varying vec3 pos_obj;
varying vec3 normal_obj;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	pos_obj = VERTEX;
	normal_obj = NORMAL;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

// Greca em degraus: 1 no relevo alto, 0 no fundo. x ao longo, y na altura da faixa (0..1).
float greca(vec2 q) {
	float x = fract(q.x);
	float y = q.y;
	float caixa = step(0.12, y) * step(y, 0.88);
	// Gancho em degraus: escada subindo e espiral quadrada
	float degraus = step(y, 0.25 + floor(x * 4.0) * 0.17);
	float espiral = step(0.55, x) * step(abs(y - 0.55), 0.18) * (1.0 - step(0.7, x) * step(abs(y - 0.55), 0.06));
	return caixa * clamp(degraus + espiral, 0.0, 1.0);
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 n = normalize(normal_mundo);
	float dist = length(p - CAMERA_POSITION_WORLD);
	float perto = smoothstep(900.0, 50.0, dist);
	float aa = max(dist * 0.0015, 0.004);
	float horizontal = smoothstep(0.65, 0.9, n.y);
	vec2 t2 = normalize(vec2(-n.z, n.x) + vec2(1e-5));
	float ao_longo = dot(p.xz, t2);
	float r_grande = texture(ruido, p.xz / 120.0 + p.y / 260.0).r;
	float r_fino = texture(ruido, vec2(ao_longo, p.y) / 5.0).r;
	vec3 cor;
	float rug = 0.88;
	vec3 nn = n;

	if (modo == 3) {
		// Pedra redonda entalhada (temalácatl): anéis e raios em volta do eixo lateral do objeto
		vec3 q = pos_obj;
		float r = length(q.yz);
		float ang = atan(q.z, q.y);
		float faixa = abs(q.x) / 2.0;
		cor = mix(vec3(0.55, 0.53, 0.47), vec3(0.42, 0.4, 0.35), texture(ruido, q.xy * 0.3 + q.z * 0.2).r);
		float aneis = step(0.5, fract(faixa * 4.0)) * step(faixa, 0.75);
		float raios = step(0.75, fract(ang / 6.2831 * 16.0)) * step(0.75, faixa);
		float relevo = max(aneis * 0.5, raios);
		cor *= 1.0 - 0.3 * relevo;
		cor = mix(cor, vec3(0.6, 0.18, 0.1), step(0.82, fract(ang / 6.2831 * 8.0)) * step(faixa, 0.3) * 0.7);
		ALBEDO = cor;
		ROUGHNESS = 0.9;
	} else {
		if (modo == 1) {
			float id = floor(p.y / 3.0) + floor(ao_longo / 7.0) * 3.0;
			cor = mix(cor_estuque, vec3(0.78, 0.5, 0.25), step(0.7, h21(vec2(id, 4.0))));
			cor *= 0.85 + 0.25 * r_grande;
			// Descascado: aparece a pedra
			float descasca = smoothstep(0.55, 0.62, texture(ruido, vec2(ao_longo, p.y) / 11.0).r + (1.0 - pintura) * 0.4);
			cor = mix(cor, cor_pedra * 0.9, descasca);
			rug = 0.7;
		} else {
			float id_fiada = floor((p.y + 0.01) / fiada);
			float v = fract((p.y + 0.01) / fiada);
			float desloc = h21(vec2(id_fiada, 3.0)) * bloco;
			float comp = bloco * (0.7 + 0.6 * h21(vec2(id_fiada, 9.0)));
			float id_bloco = floor((ao_longo + desloc) / comp);
			float u = fract((ao_longo + desloc) / comp);
			if (horizontal > 0.5) {
				vec2 g = p.xz / bloco + vec2(id_fiada * 0.37);
				id_bloco = floor(g.x) + floor(g.y) * 17.0;
				u = fract(g.x);
				v = fract(g.y);
			}
			float tom = h21(vec2(id_bloco, id_fiada));
			cor = mix(cor_pedra, cor_pedra_b, tom * 0.8 + r_grande * 0.4);
			cor *= 0.86 + 0.22 * h21(vec2(id_bloco * 3.1, id_fiada + 1.0));
			float bu = min(u, 1.0 - u) * comp;
			float bv = min(v, 1.0 - v) * (horizontal > 0.5 ? bloco : fiada);
			float junta = 1.0 - smoothstep(0.02, 0.08 + aa, min(bu, bv) + (r_fino - 0.5) * 0.05);
			cor *= 1.0 - 0.5 * junta;
			float lasca = smoothstep(0.6, 0.8, texture(ruido, vec2(ao_longo, p.y) / 2.1 + tom * 7.0).r);
			cor *= 1.0 - 0.2 * lasca * perto;
			// Restos de estuque vermelho nos blocos (os templos eram pintados)
			float tinta = step(0.62, texture(ruido, vec2(ao_longo, p.y) / 17.0).r) * pintura * (1.0 - horizontal);
			cor = mix(cor, cor_estuque * (0.8 + 0.3 * tom), tinta * 0.8);
			if (perto > 0.01 && horizontal < 0.5) {
				vec3 lado = vec3(t2.x, 0.0, t2.y);
				float su = (u < 0.5 ? -1.0 : 1.0) * (1.0 - smoothstep(0.0, 0.1, bu));
				float sv = (v < 0.5 ? -1.0 : 1.0) * (1.0 - smoothstep(0.0, 0.1, bv));
				nn += (lado * su + vec3(0.0, 1.0, 0.0) * sv) * 0.35 * perto;
			}
			if (modo == 2) {
				// Friso: greca entalhada nas faixas e escamas nas outras
				float banda = fract(p.y / (fiada * 2.0));
				float id_banda = floor(p.y / (fiada * 2.0));
				float relevo;
				if (mod(id_banda, 2.0) < 0.5) {
					relevo = greca(vec2(ao_longo / (fiada * 2.4), banda));
				} else {
					vec2 e = vec2(ao_longo / 0.9, p.y / 0.7);
					e.x += step(0.5, fract(e.y * 0.5)) * 0.5;
					relevo = smoothstep(0.42, 0.38, length(fract(e) - vec2(0.5, 0.2)));
				}
				float vertical = 1.0 - horizontal;
				cor *= 1.0 - 0.32 * (1.0 - relevo) * vertical;
				cor = mix(cor, mix(cor_estuque, vec3(0.1, 0.42, 0.4), step(0.5, mod(id_banda, 4.0) / 4.0)), relevo * pintura * 0.6 * vertical);
				nn += vec3(t2.x, 0.0, t2.y) * (relevo - 0.5) * 0.3 * vertical * perto;
			}
		}
		// Musgo: nos topos, nas juntas e mais perto do chão; escorridos escuros de umidade
		float m_ruido = texture(ruido, p.xz / 13.0 + p.y / 40.0).r;
		float m = clamp(horizontal * 0.9 + (1.0 - smoothstep(altura_chao, altura_chao + 25.0, p.y)) * 0.55, 0.0, 1.0);
		m *= smoothstep(0.35, 0.6, m_ruido + r_fino * 0.25) * musgo;
		cor = mix(cor, cor_musgo * (0.8 + 0.4 * r_fino), m * 0.85);
		float escorre = texture(ruido, vec2(ao_longo / 3.0, p.y / 70.0)).r;
		cor *= 1.0 - 0.3 * smoothstep(0.62, 0.85, escorre) * (1.0 - horizontal);
		cor *= mix(0.72, 1.0, smoothstep(altura_chao, altura_chao + 10.0, p.y));
		ALBEDO = cor;
		ROUGHNESS = mix(rug, 0.95, m);
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);
	}
}
