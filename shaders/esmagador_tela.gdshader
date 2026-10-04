shader_type spatial;
// Tela da viga do esmagador do Frozen Peak: vidro preto (como na arte do dono) com um mostrador
// discreto — a barra de segmentos enche enquanto o bloco arma (ciano, depois âmbar) e, na hora de
// cair, a tela inteira pisca em setas vermelhas descendo.

uniform float carga = 0.0;    // 0 = acabou de subir, 1 = vai cair
uniform float perigo = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 a = min(uv, 1.0 - uv);
	float moldura = smoothstep(0.0, 0.03, min(a.x * 2.9, a.y));
	float linhas = 0.75 + 0.25 * sin(uv.y * 240.0);
	// Barra de segmentos
	float n = 18.0;
	float u = (uv.x - 0.08) / 0.84;
	float seg = floor(u * n);
	float dentro = step(0.0, u) * step(u, 1.0) * step(0.14, fract(u * n)) * step(0.4, uv.y) * step(uv.y, 0.6);
	float aceso = step((seg + 0.5) / n, carga);
	vec3 cor_barra = mix(vec3(0.2, 0.85, 1.0), vec3(1.0, 0.55, 0.05), smoothstep(0.6, 0.9, (seg + 0.5) / n));
	vec3 mostrador = cor_barra * dentro * mix(0.05, 1.0, aceso);
	// Setas vermelhas descendo
	float v = fract(uv.y * 2.0 - abs(uv.x - 0.5) * 2.2 + TIME * 2.4);
	float seta = step(0.5, v);
	float pisca = 0.55 + 0.45 * sin(TIME * 22.0);
	vec3 alerta = vec3(1.0, 0.06, 0.03) * seta * pisca;
	vec3 luz = mix(mostrador * 1.6, alerta * 3.2, perigo) * linhas * moldura;
	ALBEDO = vec3(0.012, 0.014, 0.018);
	ROUGHNESS = 0.09;
	METALLIC = 0.2;
	SPECULAR = 0.8;
	EMISSION = luz;
}
