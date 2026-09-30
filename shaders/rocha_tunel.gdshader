shader_type spatial;
// Rocha escavada por dentro do túnel-atalho: mesmas cores do cânion, mas sem depender da altura
// (no teto a altura quase não muda e as camadas viravam "curvas de nível"). Textura por projeção
// tripla (vale para parede, teto e piso), camadas finas só nas paredes, marcas de escavação
// e relevo forte de perto.

uniform sampler2D ruido : filter_linear_mipmap, repeat_enable;
uniform sampler2D ruido_fino : filter_linear_mipmap, repeat_enable;
uniform vec3 c_vermelho_escuro : source_color = vec3(0.34, 0.12, 0.07);
uniform vec3 c_ferrugem : source_color = vec3(0.56, 0.22, 0.1);
uniform vec3 c_laranja : source_color = vec3(0.74, 0.38, 0.17);
uniform vec3 c_creme : source_color = vec3(0.84, 0.64, 0.44);
uniform vec3 cor_po : source_color = vec3(0.55, 0.36, 0.24);

varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	pos_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float tri(sampler2D tex, vec3 p, vec3 w, float escala) {
	return texture(tex, p.yz / escala).r * w.x + texture(tex, p.xz / escala).r * w.y + texture(tex, p.xy / escala).r * w.z;
}

void fragment() {
	vec3 p = pos_mundo;
	vec3 nw = normalize(normal_mundo);
	vec3 w = pow(abs(nw), vec3(4.0));
	w /= (w.x + w.y + w.z);

	float grande = tri(ruido, p, w, 60.0);
	float medio = tri(ruido_fino, p, w, 9.0);
	float fino = tri(ruido_fino, p, w, 2.2);

	// Camadas finas e onduladas (só onde a face é de pé)
	float de_pe = 1.0 - abs(nw.y);
	float hh = p.y + (grande - 0.5) * 3.0 + (medio - 0.5) * 0.25;
	float faixa = fract(hh / 0.55);
	float id = floor(hh / 0.55);
	float r = fract(sin(id * 127.1 + 311.7) * 43758.5453);
	vec3 camada = r < 0.3 ? c_vermelho_escuro : (r < 0.6 ? c_ferrugem : (r < 0.85 ? c_laranja : c_creme));
	vec3 base = mix(c_ferrugem, c_laranja, smoothstep(0.35, 0.7, grande));
	// Rocha escavada é mais apagada que a parede ao sol: puxa para o marrom acinzentado
	base = mix(base, vec3(0.42, 0.33, 0.27), 0.3);
	base = mix(base, camada, 0.6 * de_pe);
	base = mix(base, c_vermelho_escuro, smoothstep(0.7, 0.95, medio) * 0.2);
	base *= 1.0 - 0.5 * smoothstep(0.12, 0.0, faixa) * de_pe;   // junta escura entre camadas
	base *= 1.0 + 0.15 * smoothstep(0.7, 0.95, faixa) * de_pe;  // topo da camada mais claro
	base *= 0.88 + 0.2 * medio;
	base *= 0.92 + 0.16 * fino;
	// Poeira acumulada no piso
	base = mix(base, cor_po * (0.8 + 0.4 * fino), smoothstep(0.5, 0.9, nw.y));

	// Relevo: rocha lascada (normal perturbada pelos ruídos)
	float e = 0.4;
	vec3 grad = vec3(
		tri(ruido_fino, p + vec3(e, 0.0, 0.0), w, 2.2) - fino,
		tri(ruido_fino, p + vec3(0.0, e, 0.0), w, 2.2) - fino,
		tri(ruido_fino, p + vec3(0.0, 0.0, e), w, 2.2) - fino);
	vec3 grad_m = vec3(
		tri(ruido_fino, p + vec3(e * 3.0, 0.0, 0.0), w, 9.0) - medio,
		tri(ruido_fino, p + vec3(0.0, e * 3.0, 0.0), w, 9.0) - medio,
		tri(ruido_fino, p + vec3(0.0, 0.0, e * 3.0), w, 9.0) - medio);
	vec3 nn = nw - (grad * 2.2 + grad_m * 3.5);
	nn -= nw * dot(nn - nw, nw);   // só inclina, sem esticar para fora
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(nn), 0.0)).xyz);

	ALBEDO = base;
	ROUGHNESS = 0.92;
	SPECULAR = 0.2;
	// Fendas escuras (oclusão falsa)
	AO = 0.55 + 0.45 * smoothstep(0.2, 0.6, medio);
	AO_LIGHT_AFFECT = 0.6;
}
