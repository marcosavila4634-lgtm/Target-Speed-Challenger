shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Slider do paraquedas: retângulo de tecido preso às linhas pelos cantos. Estufa no centro com o
// ar que passa e as bordas batem com o vento (os cantos, presos nos ilhoses, quase não mexem).
// UV = 0..1 no plano (PlaneMesh subdividido).

uniform vec3 cor : source_color = vec3(0.1, 0.2, 0.5);
uniform float vento = 1.0;

void vertex() {
	vec2 q = UV * 2.0 - 1.0;                       // -1..1
	float borda = max(abs(q.x), abs(q.y));
	float canto = abs(q.x) * abs(q.y);             // 1 nos cantos presos
	float solto = 1.0 - canto;
	// Bojo: o centro sobe empurrado pelo ar
	VERTEX.y += (1.0 - dot(q, q) * 0.5) * 0.12 * vento;
	// Ondas correndo de frente para trás e tremor rápido nas bordas
	float onda = sin(TIME * 11.0 + q.y * 5.0 + q.x * 2.0) * 0.06 + sin(TIME * 17.0 - q.x * 7.0) * 0.03;
	float bate = sin(TIME * 23.0 + q.x * 9.0 + q.y * 4.0) * 0.05 * smoothstep(0.55, 1.0, borda);
	VERTEX.y += (onda + bate) * solto * vento;
	VERTEX.x += sin(TIME * 13.0 + q.y * 6.0) * 0.02 * solto * vento;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	// Bainha mais escura e reforço em X entre os ilhoses
	float bainha = step(0.9, max(abs(q.x), abs(q.y)));
	float reforco = smoothstep(0.06, 0.0, abs(abs(q.x) - abs(q.y))) * 0.5;
	vec3 c = cor * (1.0 - 0.35 * bainha) * (1.0 - reforco * 0.4);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = cor * 0.3;
}
