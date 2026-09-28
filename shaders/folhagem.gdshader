shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
// Folhagem instanciada (árvores, arbustos, capim): textura com recorte por alfa, cor por instância
// (INSTANCE_CUSTOM.rgb), oclusão pela cor do vértice, vento que aumenta com a altura e luz passando
// pelas folhas (BACKLIGHT). Troncos usam a mesma malha com alfa 1 e sem textura (UV2.x = 1).

uniform sampler2D folhas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 cor_tronco : source_color = vec3(0.24, 0.17, 0.12);
uniform float vento = 1.0;
uniform float rigidez = 3.0;        // altura (m) em que o balanço chega ao máximo
uniform float corte = 0.45;

varying vec3 tinta;
varying float eh_tronco;

void vertex() {
	tinta = INSTANCE_CUSTOM.rgb;
	eh_tronco = UV2.x;
	vec3 base = MODEL_MATRIX[3].xyz;
	float fase = dot(base.xz, vec2(0.071, 0.113));
	float h = clamp(VERTEX.y / rigidez, 0.0, 1.0);
	float balanco = sin(TIME * 1.3 + fase) * 0.6 + sin(TIME * 2.9 + fase * 1.7) * 0.25;
	float tremor = sin(TIME * 7.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0 + fase) * 0.04 * (1.0 - eh_tronco);
	VERTEX.x += (balanco * 0.12 * h * h + tremor) * vento;
	VERTEX.z += (balanco * 0.07 * h * h + tremor * 0.7) * vento;
}

void fragment() {
	if (eh_tronco > 0.5) {
		ALBEDO = cor_tronco * COLOR.rgb;
		ROUGHNESS = 0.95;
	} else {
		vec4 t = texture(folhas, UV);
		if (t.a < corte) {
			discard;
		}
		ALBEDO = t.rgb * tinta * COLOR.rgb;
		ROUGHNESS = 0.85;
		SPECULAR = 0.25;
		BACKLIGHT = t.rgb * tinta * 0.45;
	}
}
