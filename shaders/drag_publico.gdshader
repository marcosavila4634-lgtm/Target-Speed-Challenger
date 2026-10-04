shader_type spatial;
render_mode world_vertex_coords, cull_disabled;
// Público nas arquibancadas (MultiMesh de cartões): cada pessoa é um quadrado sempre virado para a
// câmera (só gira em Y) com uma das pessoas do atlas (tools/ambiente/torcida_atlas.gd) em 3 poses:
// em pé, um braço erguido e os dois erguidos. INSTANCE_CUSTOM: r = pessoa, g = quanto de `animacao`
// ela precisa para se empolgar, b = espelhada (> 0,5), a = fase do balanço. `animacao` sobe quando a
// corrida esquenta (largada e chegada): a torcida ergue os braços e pula.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform float animacao = 0.3;
uniform float pessoas = 18.0;
uniform float poses = 3.0;
uniform vec2 tamanho = vec2(1.2, 2.4);   // metros, igual à célula do atlas
uniform float brilho = 1.25;

varying vec2 uv_atlas;

void vertex() {
	vec3 origem = MODEL_MATRIX[3].xyz;
	float escala = length(MODEL_MATRIX[1].xyz);
	vec3 para_cam = CAMERA_POSITION_WORLD - origem;
	para_cam.y = 0.0;
	para_cam = normalize(para_cam + vec3(0.0001, 0.0, 0.0));
	vec3 direita = cross(vec3(0.0, 1.0, 0.0), para_cam);
	// Calmos: de vez em quando um braço sobe; empolgados: alternam um e dois braços e pulam
	float fase = INSTANCE_CUSTOM.a * 6.2831;
	float onda = sin(TIME * (3.0 + 2.5 * INSTANCE_CUSTOM.g) + fase);
	float empolgado = step(INSTANCE_CUSTOM.g, animacao);
	float pose = empolgado > 0.5 ? (onda > 0.0 ? 2.0 : 1.0) : step(0.985 - animacao * 0.1, sin(TIME * 0.4 + fase * 3.0));
	float pulo = max(onda, 0.0) * 0.14 * empolgado * animacao;
	vec2 q = vec2(UV.x - 0.5, 1.0 - UV.y) * tamanho * escala;
	VERTEX = origem + direita * q.x + vec3(0.0, q.y + pulo, 0.0);
	NORMAL = para_cam;
	float u = INSTANCE_CUSTOM.b > 0.5 ? 1.0 - UV.x : UV.x;
	uv_atlas = (vec2(floor(INSTANCE_CUSTOM.r * pessoas), pose) + vec2(u, UV.y)) / vec2(pessoas, poses);
}

void fragment() {
	vec4 c = texture(atlas, uv_atlas);
	ALBEDO = c.rgb * brilho;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
