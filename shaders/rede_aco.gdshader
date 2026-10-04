shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Rede de carga (alvo da etapa 3 do Extinction Day: o saco de rede pendurado no helicóptero).
// Malha em losango de cabos trançados com um nó em cada cruzamento, recortada (alpha scissor):
// entre os cabos se vê através. Coordenadas em metros: UV (paredes) ou posição local XZ (piso).

uniform float malha = 1.2;          // tamanho do losango (m)
uniform float cabo = 0.13;          // espessura do cabo (m)
uniform bool pelo_piso = false;     // true: usa a posição local XZ em vez do UV
uniform vec3 cor : source_color = vec3(0.72, 0.7, 0.62);

varying vec2 plano;

void vertex() {
	plano = pelo_piso ? VERTEX.xz : UV;
}

void fragment() {
	// Duas famílias de cabos na diagonal
	vec2 d = vec2(plano.x + plano.y, plano.x - plano.y) * 0.7071;
	vec2 f = abs(fract(d / malha) - 0.5) * malha;   // distância (m) até o cabo mais perto de cada família
	float dist = min(f.x, f.y);
	float fio = 1.0 - smoothstep(cabo * 0.5, cabo * 0.5 + 0.02, dist);
	// Trançado: listras inclinadas ao longo do cabo; nó mais grosso nos cruzamentos
	float ao_longo = f.x < f.y ? d.y : d.x;
	float torcido = 0.72 + 0.28 * sin(ao_longo * 55.0 + dist * 90.0);
	float no = 1.0 - smoothstep(cabo * 1.0, cabo * 1.25, length(f));
	float redondo = 1.0 - 0.45 * smoothstep(0.0, cabo * 0.5, dist);   // o cabo escurece nas bordas (volume)
	ALBEDO = cor * torcido * redondo * (1.0 - 0.3 * no);
	EMISSION = cor * 0.28 * redondo;   // aparece à noite
	METALLIC = 0.35;
	ROUGHNESS = 0.6;
	ALPHA = max(fio, no);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
