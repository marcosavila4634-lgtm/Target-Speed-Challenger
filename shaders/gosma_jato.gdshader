shader_type spatial;
render_mode cull_back;
// Jato de meleca dos dinossauros cuspidores (Extinction Day): cada partícula é um naco esticado no
// sentido do voo (o emissor alinha o eixo Y com a velocidade) — o vértice amassa o naco com caroços que
// mudam de partícula para partícula e afina a ponta de trás num fio, de modo que os nacos se emendam
// num jorro grosso e irregular, com pingos e fios, em vez de bolas. Verde-oliva escuro e turvo no
// miolo, amarelado e translúcido nas bordas, molhado (brilho forte) e com pouca luz própria.

uniform float luz = 0.14;

varying float semente;
varying vec3 pl;

void vertex() {
	semente = fract(float(INSTANCE_ID) * 0.6180339);
	pl = VERTEX;
	float a = atan(VERTEX.z, VERTEX.x);
	float h = VERTEX.y;   // -1 (atrás) a +1 (frente), na malha de raio 1
	// Caroços: três ondas em volta e ao longo, diferentes em cada naco e fervendo devagar
	float caroco = sin(a * 3.0 + semente * 40.0 + TIME * 5.0) * 0.22 + sin(a * 5.0 - h * 4.0 + semente * 17.0) * 0.14 + sin(h * 7.0 + semente * 9.0 + TIME * 7.0) * 0.12;
	// A frente é um bojo; para trás afina e vira fio
	float perfil = mix(0.16, 1.0, smoothstep(-1.0, 0.35, h)) * (1.0 + caroco);
	VERTEX.xz *= perfil;
	VERTEX.y += caroco * 0.25;
}

void fragment() {
	float beira = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 1.6);
	float mancha = sin(pl.y * 9.0 + semente * 30.0) * sin(atan(pl.z, pl.x) * 4.0 + semente * 11.0);
	vec3 miolo = mix(vec3(0.05, 0.13, 0.015), vec3(0.16, 0.26, 0.03), 0.5 + 0.5 * mancha);
	vec3 borda = vec3(0.5, 0.62, 0.1);
	vec3 cor = mix(miolo, borda, beira * 0.75);
	// Bolhas claras presas na meleca
	float bolha = smoothstep(0.86, 0.97, sin(pl.x * 23.0 + semente * 50.0) * sin(pl.y * 19.0) * sin(pl.z * 21.0 + semente * 13.0));
	cor = mix(cor, vec3(0.7, 0.8, 0.35), bolha * 0.6);
	ALBEDO = cor;
	ROUGHNESS = 0.04;
	SPECULAR = 1.0;
	METALLIC = 0.0;
	EMISSION = cor * luz;
	BACKLIGHT = vec3(0.25, 0.4, 0.05);
}
