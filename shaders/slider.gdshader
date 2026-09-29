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
	// Bojo leve: o centro sobe um pouco empurrado pelo ar (cantos presos nos ilhoses = zero)
	VERTEX.y += (1.0 - abs(q.x)) * (1.0 - abs(q.y)) * 0.05;
	// Ondulação suave e lenta; as bordas soltas mexem um pouco mais
	float onda = sin(TIME * 3.2 + q.y * 2.5 + q.x * 1.2) * 0.012 + sin(TIME * 4.7 - q.x * 3.0) * 0.006;
	float bate = sin(TIME * 6.5 + q.x * 4.0 + q.y * 2.0) * 0.008 * smoothstep(0.6, 1.0, borda);
	VERTEX.y += (onda + bate) * solto * vento;
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
