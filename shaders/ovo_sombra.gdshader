shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
// Sombra do ovo de pterossauro que vem caindo (plataforma dos buracos do Extinction Day): mancha escura
// de borda macia no piso, que fecha e escurece conforme o ovo chega — é o aviso de onde ele vai cair.
//   quanto: 0 = ovo lá em cima (sombra larga e fraca), 1 = ovo no chão (sombra pequena e escura)

uniform float quanto = 0.0;

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float raio = mix(1.0, 0.45, quanto);
	ALBEDO = vec3(0.02, 0.015, 0.01);
	ALPHA = (1.0 - smoothstep(raio * 0.35, raio, d)) * mix(0.22, 0.72, quanto);
}
