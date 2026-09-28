shader_type spatial;
// Painel/banner de evento na cor da equipe (QuadMesh, UV 0..1, v=0 no topo):
// fundo escuro com degradê, moldura em neon e chevrons descendo entre faixa_ini e faixa_fim.

uniform vec3 cor_equipe : source_color = vec3(0.2, 0.45, 1.0);
uniform float proporcao = 0.3;          // largura / altura do painel
uniform float chevrons = 6.0;           // quantidade de chevrons visíveis na faixa
uniform float faixa_ini = 0.0;
uniform float faixa_fim = 1.0;
uniform float velocidade = 0.35;
uniform float energia = 2.5;
uniform float moldura = 0.025;          // espessura da moldura (fração da largura)

void fragment() {
	vec2 uv = UV;
	vec3 fundo = mix(vec3(0.03, 0.035, 0.05), cor_equipe * 0.22, 0.35 + 0.35 * uv.y);
	vec3 cor = fundo;
	vec3 emissao = vec3(0.0);

	// Moldura em neon.
	float dx = min(uv.x, 1.0 - uv.x);
	float dy = min(uv.y, 1.0 - uv.y) * (1.0 / max(proporcao, 0.01));
	float m = 1.0 - step(moldura, min(dx, dy));
	emissao += cor_equipe * energia * m;

	// Chevrons apontando para baixo, descendo com o tempo.
	float altura_faixa = max(faixa_fim - faixa_ini, 0.001);
	float y = (uv.y - faixa_ini) / altura_faixa;
	float x = abs(uv.x - 0.5);
	float dentro = step(0.0, y) * step(y, 1.0) * step(x, 0.36);
	float s = y * chevrons + x * 1.3 * proporcao * chevrons / altura_faixa - TIME * velocidade;
	float chev = step(0.45, fract(s)) * dentro;
	cor = mix(cor, cor_equipe * 0.6, chev);
	emissao += cor_equipe * energia * 0.8 * chev;

	ALBEDO = cor;
	EMISSION = emissao;
	ROUGHNESS = 0.55;
	METALLIC = 0.1;
}
