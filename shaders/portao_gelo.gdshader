shader_type spatial;
// Portão de gelo do Frozen Peak (PortaoGelo), pela arte do dono: gelo azul saturado partido em blocos
// por rachaduras brancas (células de Voronoi no espaço do mundo), cada bloco com um tom e um brilho
// ciano saindo de dentro; uma segunda rede de rachaduras, mais funda, anda com o olhar (raio
// refratado: parece gelo grosso, não pintura). Borda (fresnel) clara, verniz liso, luz atravessando
// por trás e neve nas faces viradas para cima. Os materiais (cristal, moldura, letras, picos) mudam
// só os uniforms.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform vec3 cor_rasa : source_color = vec3(0.3, 0.74, 1.0);
uniform vec3 cor_funda : source_color = vec3(0.02, 0.12, 0.36);
uniform vec3 cor_neve : source_color = vec3(0.95, 0.98, 1.0);
uniform float celula = 3.4;         // tamanho dos blocos entre as rachaduras (m)
uniform float rachadura = 1.0;      // força das linhas brancas
uniform float brilho = 0.9;         // luz ciano de dentro
uniform float profundidade = 0.7;   // quão fundo fica a segunda rede de rachaduras
uniform float neve = 1.0;
uniform float neve_min = 0.5;       // inclinação a partir da qual a neve gruda
uniform float lados = 0.0;          // escurece as faces paralelas a `eixo` (laterais das letras)
uniform vec3 eixo = vec3(0.0, 0.0, 1.0);
uniform float relevo = 1.0;          // força do relevo lascado
uniform vec3 cor_lado : source_color = vec3(0.02, 0.1, 0.3);   // cor das laterais (letras: contorno escuro)

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize(transpose(inverse(mat3(MODEL_MATRIX))) * NORMAL);
}

vec3 h33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

// Voronoi 3D: x = distância à borda (F2 - F1), y = sorteio do bloco, z = distância ao centro do bloco
vec3 voronoi(vec3 p) {
	vec3 b = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int k = -1; k <= 1; k++) {
		for (int j = -1; j <= 1; j++) {
			for (int i = -1; i <= 1; i++) {
				vec3 g = vec3(float(i), float(j), float(k));
				vec3 o = h33(b + g);
				vec3 r = g + o * 0.85 - f;
				float d = dot(r, r);
				float menor = step(d, d1);
				d2 = mix(min(d2, d), d1, menor);
				id = mix(id, o.x, menor);
				d1 = min(d1, d);
			}
		}
	}
	return vec3(sqrt(d2) - sqrt(d1), id, sqrt(d1));
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 nw = normalize(normal_mundo);
	vec3 olho = normalize(CAMERA_POSITION_WORLD - p);
	float dist = length(CAMERA_POSITION_WORLD - p);
	float perto = smoothstep(260.0, 20.0, dist);
	float ndv = clamp(dot(nw, olho), 0.0, 1.0);
	float n1 = texture(ruido, p.xz / 19.0 + p.y / 23.0).r;
	float n2 = texture(ruido, p.xy / 3.7 + p.z / 5.3).r;
	// Blocos e rachaduras da superfície (as células esticam na vertical: gelo de pilar)
	vec3 v1 = voronoi(p / celula * vec3(1.0, 0.7, 1.0));
	// Rede funda: ao longo do raio refratado
	vec3 r = refract(-olho, nw, 0.76);
	vec3 v2 = voronoi((p + r * profundidade) / (celula * 0.8) + 17.3);
	// Só parte das bordas vira rachadura (as outras somem no gelo): fraturas, não azulejo
	// Poucas fraturas, finas e só de perto (as linhas brancas por toda parte pareciam vidro trincado)
	float mascara = smoothstep(0.56, 0.7, texture(ruido, p.xy / 9.0 + p.z / 11.0).r);
	float mascara2 = smoothstep(0.5, 0.7, texture(ruido, p.zy / 6.0 + p.x / 8.0 + 0.37).r);
	float linha = (1.0 - smoothstep(0.006, 0.022, v1.x)) * mascara * perto;
	float linha_funda = (1.0 - smoothstep(0.01, 0.06, v2.x)) * 0.6 * mascara2;
	// Tom do bloco: cada um mais claro ou mais fundo, com o miolo aceso
	float tom = clamp(0.12 + v1.y * 0.4 + (n1 - 0.5) * 0.9 + (n2 - 0.5) * 0.3, 0.0, 1.0);
	tom = tom * tom * (3.0 - 2.0 * tom);
	vec3 cor = mix(cor_funda, cor_rasa, tom);
	float miolo = 1.0 - smoothstep(0.0, 0.75, v1.z);
	cor = mix(cor, cor_rasa * 1.1, miolo * 0.15);
	// Rachaduras: brancas na superfície, azul-claras por dentro
	cor = mix(cor, cor_rasa * 1.25 + 0.08, linha_funda * rachadura);
	cor = mix(cor, vec3(0.88, 0.97, 1.0), linha * 0.55 * rachadura);
	// Bolhas de ar presas e nuvens leitosas de dentro (gelo de verdade)
	float leite = smoothstep(0.45, 0.85, texture(ruido, (p.xz + r.xz * profundidade * 2.5) / 5.0 + p.y / 7.0).r);
	cor = mix(cor, vec3(0.78, 0.9, 0.98), leite * 0.3);
	float bolha = step(0.975, texture(ruido, (p.xy + r.xy * profundidade) * 1.3 + p.z * 0.7).r) * perto;
	cor = mix(cor, vec3(0.95, 1.0, 1.0), bolha * 0.6);
	// Laterais (extrusão das letras): azul mais fundo
	float lateral = (1.0 - abs(dot(nw, normalize(eixo)))) * lados;
	cor = mix(cor, cor_lado, lateral * (1.0 - linha * 0.6));
	cor *= 0.96 + 0.08 * n2;
	float borda = pow(1.0 - ndv, 3.0);
	cor = mix(cor, cor_rasa * 1.3, borda * 0.45);
	vec3 emis = cor_rasa * brilho * (0.04 + 0.4 * miolo * tom * tom + 0.3 * linha_funda) + vec3(0.6, 0.85, 1.0) * linha * 0.3 * rachadura;
	emis += cor_rasa * borda * 0.6 * brilho;
	emis *= 1.0 - lateral * 0.85;
	float rug = mix(0.05, 0.5, linha);
	// Neve nas faces de cima (borda irregular) com brilhinho de perto
	float cima = smoothstep(neve_min, neve_min + 0.25, nw.y + (n2 - 0.5) * 0.35) * neve;
	cor = mix(cor, cor_neve * (0.9 + 0.12 * n2), cima);
	rug = mix(rug, 0.85, cima);
	emis *= 1.0 - cima;
	float faisca = step(0.982, texture(ruido, p.xz * 1.9 + p.y * 0.7).r) * cima * perto;
	// Relevo: superfície lascada e ondulada, sulco nas fraturas (normal pela derivada da altura)
	float alt = texture(ruido, p.xz / 3.5 + p.y / 4.1).r * 0.8 + texture(ruido, p.zy / 1.6 + p.x * 0.3).r * 0.2 - linha * 0.4;
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, nv);
	vec3 r2 = cross(nv, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(alt) * r1 + dFdy(alt) * r2);
	NORMAL = normalize(abs(det) * nv - 0.03 * relevo * (1.0 - cima) * grad);
	ALBEDO = cor;
	ROUGHNESS = rug;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	CLEARCOAT = (1.0 - cima) * 0.6;
	CLEARCOAT_ROUGHNESS = 0.04;
	BACKLIGHT = cor_rasa * 0.5 * (1.0 - cima);
	EMISSION = emis + vec3(faisca) * 0.7;
}
