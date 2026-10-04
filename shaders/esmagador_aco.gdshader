shader_type spatial;
// Aço do esmagador do Frozen Peak (EsmagadorGelo): chapa grossa cinza-chumbo com rebites em fila
// junto das bordas, quinas gastas mostrando o metal, riscos, manchas de ferrugem escura e geada —
// neve nas faces de cima. COLOR = cor da tinta (cinza do aço, amarelo dos grampos); com `listras`,
// faixa de advertência amarela e preta em diagonal, lascada.
// UV = 0..1 na face, UV2 = tamanho da face em metros.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform float listras = 0.0;
uniform float largura_listra = 0.42;
uniform float geada = 0.5;

varying vec3 pos_local;
varying float cima_mundo;

void vertex() {
	pos_local = VERTEX;
	cima_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	vec2 q = UV * UV2;
	vec2 a = min(q, UV2 - q);
	float borda = min(a.x, a.y);
	float perto = smoothstep(150.0, 30.0, length(VERTEX));
	vec2 uvn = q + vec2(pos_local.x + pos_local.z, pos_local.y) * 0.37;
	float n_g = texture(ruido, uvn / 7.0).r;
	float n_f = texture(ruido, uvn / 0.9).r;
	float n_r = texture(ruido, vec2(uvn.x * 0.5, uvn.y * 4.0)).r;

	vec3 cor = COLOR.rgb * (0.78 + 0.45 * n_g);
	float pintado = smoothstep(0.12, 0.35, max(COLOR.r, COLOR.g) - COLOR.b);
	float l = step(0.5, fract((q.x + q.y) / (largura_listra * 2.0)));
	vec3 cor_l = mix(vec3(0.93, 0.66, 0.05), vec3(0.03, 0.03, 0.035), l) * (0.8 + 0.3 * n_g);
	cor = mix(cor, cor_l, listras);
	pintado = max(pintado, listras);
	vec3 metal_nu = vec3(0.56, 0.58, 0.61);
	// Tinta lascada, quinas gastas e riscos
	float lasca = smoothstep(0.66, 0.74, n_f * 0.6 + n_g * 0.5) * pintado;
	cor = mix(cor, vec3(0.2, 0.2, 0.21), lasca);
	float gasto = (1.0 - smoothstep(0.0, 0.05 + 0.07 * n_f, borda)) * (0.45 + 0.55 * n_f);
	float risco = smoothstep(0.86, 0.96, n_r) * 0.45;
	float nu = max(gasto, risco);
	cor = mix(cor, metal_nu, nu * 0.75);
	// Ferrugem escura em manchas
	float suja = smoothstep(0.52, 0.8, n_g) * (1.0 - nu);
	cor = mix(cor, cor * vec3(0.52, 0.4, 0.32), suja * 0.55);
	// Rebites em fila junto das bordas (só em chapa grande, só de perto)
	float grande = step(0.9, min(UV2.x, UV2.y));
	float passo = 0.5;
	float d1 = length(vec2((fract(q.x / passo) - 0.5) * passo, a.y - 0.17));
	float d2 = length(vec2((fract(q.y / passo) - 0.5) * passo, a.x - 0.17));
	float dr = min(d1, d2);
	float rebite = (1.0 - smoothstep(0.035, 0.06, dr)) * grande * perto;
	float sombra_r = (1.0 - smoothstep(0.06, 0.11, dr)) * grande * perto;
	cor = mix(cor, cor * 0.5, sombra_r * (1.0 - rebite));
	cor = mix(cor, metal_nu * 0.85, rebite * 0.55);
	// Geada e neve
	float cima = smoothstep(0.55, 0.85, cima_mundo + (n_f - 0.5) * 0.3);
	float gelada = smoothstep(0.66 - geada * 0.22, 0.86, n_g * 0.6 + n_f * 0.45) * geada;
	gelada = max(gelada, cima);
	cor = mix(cor, vec3(0.86, 0.93, 0.98), gelada * mix(0.5, 1.0, cima));

	float alt = rebite * 0.9 + n_f * 0.12 - risco * 0.2 + gelada * 0.3 * n_f;
	vec3 nv = normalize(NORMAL);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, nv);
	vec3 r2 = cross(nv, dpx);
	float det = dot(dpx, r1);
	vec3 grad = sign(det) * (dFdx(alt) * r1 + dFdy(alt) * r2);
	NORMAL = normalize(abs(det) * nv - 0.03 * grad);
	ALBEDO = cor;
	ROUGHNESS = mix(mix(0.36, 0.62, n_f), 0.9, max(gelada, suja * 0.6));
	METALLIC = mix(0.88, 0.3, pintado * (1.0 - nu)) * (1.0 - gelada);
	SPECULAR = 0.5;
}
