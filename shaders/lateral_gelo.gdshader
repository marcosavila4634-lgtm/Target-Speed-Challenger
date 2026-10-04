shader_type spatial;
// Laterais e fundo da estrada do Frozen Peak: viga de aço escuro com geada, beiral de neve
// transbordando do topo (com pingentes) e um filete de neon azul-gelo.
// UV.x = metros ao longo; UV.y = 0 no topo, 1 embaixo.

uniform vec3 cor_equipe : source_color = vec3(0.25, 0.8, 1.0);
uniform float energia = 1.6;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743);
}

void fragment() {
	float painel = floor(UV.x / 2.4);
	float junta = step(0.97, fract(UV.x / 2.4));
	vec3 cor = mix(vec3(0.14, 0.16, 0.2), vec3(0.2, 0.23, 0.28), h21(vec2(painel, 3.0)));
	cor *= 1.0 - 0.4 * junta;
	// Rebites
	vec2 rb = vec2(fract(UV.x / 0.6) - 0.5, (UV.y - 0.82) * 2.2);
	cor = mix(cor, vec3(0.42, 0.46, 0.52), 1.0 - smoothstep(0.08, 0.11, length(rb)));
	// Geada em manchas
	float geada = smoothstep(0.55, 0.9, h21(floor(vec2(UV.x * 3.0, UV.y * 6.0))) * 0.6 + UV.y * 0.5);
	cor = mix(cor, vec3(0.7, 0.8, 0.9), geada * 0.35);
	// Beiral de neve com pingentes (cada coluna de 0,35 m desce uma altura diferente)
	float col = floor(UV.x / 0.35);
	float alto = 0.1 + 0.42 * pow(h21(vec2(col, 9.0)), 2.0);
	float fx = abs(fract(UV.x / 0.35) - 0.5) * 2.0;
	float pingente = step(UV.y, alto * (1.0 - fx * fx));
	float neve = step(UV.y, 0.1);
	vec3 neon = vec3(0.25, 0.8, 1.0);
	float faixa = step(UV.y, 0.62) * step(0.52, UV.y);
	ALBEDO = mix(mix(cor, neon, faixa), mix(vec3(0.72, 0.88, 1.0), vec3(0.95, 0.97, 1.0), neve), max(pingente, neve));
	EMISSION = neon * energia * faixa * (1.0 - pingente);
	METALLIC = 0.7 * (1.0 - max(pingente, neve)) * (1.0 - faixa);
	ROUGHNESS = mix(0.45, 0.2, pingente);
}
