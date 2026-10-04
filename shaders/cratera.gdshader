shader_type spatial;
// Cratera de impacto (Extinction Day, alvo da etapa 4): chão queimado e vitrificado no fundo, terra
// revirada nas paredes, manto de ejeção mais claro com raios para fora da borda e brasas nas
// rachaduras perto do meteoro. A beirada de fora se desfaz em pontilhado sobre o terreno.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform float raio = 78.0;
uniform float fora = 1.75;          // até onde vai a malha (em raios)
uniform vec3 c_queimado : source_color = vec3(0.03, 0.027, 0.025);
uniform vec3 c_terra : source_color = vec3(0.2, 0.135, 0.085);
uniform vec3 c_ejecao : source_color = vec3(0.34, 0.26, 0.17);
uniform vec3 cor_brasa : source_color = vec3(1.0, 0.3, 0.04);
uniform float brasa = 1.4;

varying vec3 pos_l;

void vertex() {
	pos_l = VERTEX;
}

void fragment() {
	float u = length(pos_l.xz) / raio;
	float ang = atan(pos_l.z, pos_l.x);
	float grande = texture(ruido, pos_l.xz / 60.0).r;
	float medio = texture(ruido_fino, pos_l.xz / 9.0).r;
	float fino = texture(ruido_fino, pos_l.xz / 2.2).r;
	// Estrias radiais (terra jogada para fora) e faixas concêntricas (desmoronamento da parede)
	float estria = texture(ruido, vec2(ang * 1.9, u * 0.12)).r;
	float faixa = sin(u * 26.0 + grande * 6.0) * 0.5 + 0.5;

	float f = smoothstep(0.22, 0.95, u + (grande - 0.5) * 0.35);
	vec3 cor = mix(c_queimado, c_terra, f);
	cor *= mix(1.0, 0.78 + 0.3 * faixa, smoothstep(0.4, 0.8, u) * (1.0 - smoothstep(0.95, 1.1, u)));
	// Borda e manto de ejeção: mais claro, com os raios
	float manto = smoothstep(0.9, 1.08, u);
	cor = mix(cor, mix(c_terra, c_ejecao, smoothstep(0.3, 0.7, estria)), manto * 0.85);
	cor *= 0.62 + 0.5 * medio + 0.25 * fino;
	// Fuligem soprada para fora nos raios escuros
	cor *= mix(1.0, 0.6, manto * smoothstep(0.55, 0.3, estria) * (1.0 - smoothstep(1.2, 1.6, u)));
	ALBEDO = cor;
	// Fundo vitrificado pelo calor: um pouco brilhante
	ROUGHNESS = mix(0.5, 0.96, smoothstep(0.15, 0.6, u));
	SPECULAR = 0.3;

	// Rachaduras em brasa no fundo, mais fortes perto do meteoro
	float rach = 1.0 - smoothstep(0.0, 0.035, abs(medio - 0.5));
	float perto = 1.0 - smoothstep(0.3, 0.72, u);
	float pulso = 0.75 + 0.25 * sin(TIME * 1.3 + grande * 12.0);
	EMISSION = cor_brasa * rach * perto * brasa * pulso;

	// Beirada de fora: pontilhado até sumir no terreno
	float some = smoothstep(fora - 0.42, fora - 0.04, u + (medio - 0.5) * 0.12);
	float pont = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (some > pont) {
		discard;
	}
}
