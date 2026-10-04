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
// Casca (árvores gigantes do Extinction Day): fissuras verticais e fibras no tronco, que de perto
// deixam de ser um cilindro liso. 0 = tronco liso (as outras plantas).
uniform float casca = 0.0;
// Onda de choque do impacto final (Extinction Day): tudo o que fica dentro do raio é arrasado
uniform vec3 onda_centro = vec3(0.0);
uniform float onda_raio = -1.0;
varying float queimado;

varying vec3 tinta;
varying float eh_tronco;
varying vec3 pos_local;

void vertex() {
	tinta = INSTANCE_CUSTOM.rgb;
	eh_tronco = UV2.x;
	pos_local = VERTEX;
	vec3 base = MODEL_MATRIX[3].xyz;
	float fase = dot(base.xz, vec2(0.071, 0.113));
	float h = clamp(VERTEX.y / rigidez, 0.0, 1.0);
	float balanco = sin(TIME * 1.3 + fase) * 0.6 + sin(TIME * 2.9 + fase * 1.7) * 0.25;
	float tremor = sin(TIME * 7.0 + VERTEX.x * 3.0 + VERTEX.z * 2.0 + fase) * 0.04 * (1.0 - eh_tronco);
	VERTEX.x += (balanco * 0.12 * h * h + tremor) * vento;
	VERTEX.z += (balanco * 0.07 * h * h + tremor * 0.7) * vento;
	queimado = 0.0;
	if (onda_raio > 0.0) {
		// A árvore tomba para longe do impacto, achatada no chão, e vira carvão em brasa
		vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
		vec2 dv = base.xz - onda_centro.xz;
		float dd = max(length(dv), 1.0);
		queimado = smoothstep(0.0, 160.0, onda_raio - dd);
		vec3 fora = normalize(inverse(mat3(MODEL_MATRIX)) * vec3(dv.x / dd, 0.0, dv.y / dd));
		float alt = VERTEX.y;
		VERTEX.y *= 1.0 - 0.94 * queimado;
		VERTEX += fora * alt * queimado * 0.9;
	}
}

void fragment() {
	if (eh_tronco > 0.5) {
		ALBEDO = cor_tronco * COLOR.rgb;
		ROUGHNESS = 0.95;
		if (casca > 0.0) {
			float ang = atan(pos_local.z, pos_local.x);
			float fio = sin(ang * 34.0 + sin(pos_local.y * 0.35) * 2.0 + sin(pos_local.y * 1.7 + ang * 5.0) * 0.6);
			float fissura = smoothstep(0.55, 0.95, fio);
			float fibra = 0.85 + 0.15 * sin(ang * 140.0 + pos_local.y * 0.8);
			vec3 c = cor_tronco * COLOR.rgb * fibra * (1.0 - 0.55 * fissura * casca);
			c = mix(c, c * vec3(0.7, 0.75, 0.6), smoothstep(6.0, 0.0, pos_local.y) * 0.5 * casca);
			ALBEDO = c;
		}
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
	if (queimado > 0.0) {
		ALBEDO = mix(ALBEDO, vec3(0.02, 0.015, 0.01), queimado);
		// Carvão não brilha nem deixa a luz atravessar (a floresta tombada virava um pontilhado de "purpurina" sob o clarão)
		ROUGHNESS = mix(ROUGHNESS, 1.0, queimado);
		SPECULAR = mix(SPECULAR, 0.0, queimado);
		BACKLIGHT *= 1.0 - queimado;
		EMISSION = vec3(1.0, 0.35, 0.05) * queimado * (1.0 - queimado) * 8.0;
	}
}
