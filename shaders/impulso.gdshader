shader_type spatial;
render_mode unshaded, cull_disabled;
// Ponto de aceleração no piso da arena. O tranco vai para onde o CARRO aponta, então a placa
// não tem seta: anéis acesos pulsando do centro para fora, raio no meio e moldura zebrada.

uniform vec3 cor : source_color = vec3(0.1, 0.85, 1.0);
uniform float velocidade = 1.6;
uniform float energia = 3.0;
uniform vec2 tamanho = vec2(4.0, 7.0);   // metros (largura, comprimento)

void fragment() {
	vec2 m = (UV - 0.5) * tamanho;                 // metros a partir do centro
	vec2 meio = tamanho * 0.5;
	float borda = min(meio.x - abs(m.x), meio.y - abs(m.y));
	// Distância "retangular arredondada" ao centro, para os anéis seguirem o formato da placa
	float d = length(m / meio);
	float anel = fract(d * 2.5 - TIME * velocidade);
	float aceso = smoothstep(0.0, 0.1, anel) * (1.0 - smoothstep(0.3, 0.42, anel)) * step(0.3, borda);
	// Raio em zigue-zague no meio
	float zig = abs(fract(m.y * 0.9) - 0.5) * 1.2 - 0.3;
	float raio = (1.0 - smoothstep(0.08, 0.16, abs(m.x - zig))) * step(abs(m.y), meio.y - 1.2);
	float pulso = 0.7 + 0.3 * sin(TIME * 10.0);
	vec3 c = vec3(0.03, 0.035, 0.04);
	c = mix(c, cor, max(aceso * 0.8, raio));
	float moldura = 1.0 - step(0.3, borda);
	float zebra = step(0.5, fract((m.x + m.y) * 0.8));
	c = mix(c, mix(vec3(0.95, 0.7, 0.05), vec3(0.03), zebra), moldura);
	ALBEDO = c * (1.0 + max(aceso, raio) * energia * pulso);
}
