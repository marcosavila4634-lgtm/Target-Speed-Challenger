class_name DragParaquedas
extends Node3D
## Paraquedas de frenagem do Drag Racing (diferente da asa do Target Flight): sai de um pacote na
## traseira do carro depois da chegada, as linhas esticam e o velame redondo (gomos brancos e na cor
## da equipe) enche atrás do carro, balançando com o vento. Só visual: a frenagem é da DragMotor.

const ABRIR_S := 0.6
const LINHAS := 8

var aberto := false
var _t := 0.0
var _carro: Veiculo
var _velame: MeshInstance3D
var _linhas: ImmediateMesh
var _mat_linha: StandardMaterial3D
var _ancora := Vector3.ZERO     # ponto de saída na traseira (espaço do carro)
var _vel := 0.0


func montar(v: Veiculo) -> void:
	_carro = v
	name = "ParaquedasFrenagem"
	v.add_child(self)
	var c := v.caixa_corpo
	_ancora = Vector3(c.get_center().x, c.position.y + c.size.y * 0.55, c.end.z + 0.05)
	# Pacote do paraquedas na traseira
	var pacote := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.2, 0.18)
	pacote.mesh = bm
	var mp := StandardMaterial3D.new()
	mp.albedo_color = v.cor_equipe.darkened(0.3)
	mp.roughness = 0.8
	pacote.material_override = mp
	pacote.position = _ancora + Vector3(0, 0, -0.05)
	add_child(pacote)
	# Velame: meia esfera virada para trás (a boca para o carro)
	var esf := SphereMesh.new()
	esf.radius = 0.9
	esf.height = 0.75
	esf.is_hemisphere = true
	esf.radial_segments = 24
	esf.rings = 8
	_velame = MeshInstance3D.new()
	_velame.mesh = esf
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec3 cor_equipe : source_color;
uniform float tempo = 0.0;
varying vec3 p;
void vertex() {
	p = VERTEX;
	// Tecido tremulando
	VERTEX += NORMAL * sin(tempo * 17.0 + atan(VERTEX.x, VERTEX.z) * 6.0 + VERTEX.y * 5.0) * 0.03;
}
void fragment() {
	float gomo = mod(floor((atan(p.x, p.z) / 6.2832 + 0.5) * 8.0), 2.0);
	float furo = step(length(p.xz), 0.18);   // furo do topo (respiro)
	ALBEDO = mix(vec3(0.92), cor_equipe, gomo);
	ALPHA = 1.0 - furo;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.8;
}"""
	mat.set_shader_parameter("cor_equipe", v.cor_equipe)
	_velame.material_override = mat
	_velame.visible = false
	add_child(_velame)
	_linhas = ImmediateMesh.new()
	var ml := MeshInstance3D.new()
	ml.mesh = _linhas
	_mat_linha = StandardMaterial3D.new()
	_mat_linha.albedo_color = Color(0.9, 0.9, 0.9)
	_mat_linha.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ml.material_override = _mat_linha
	ml.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ml)
	set_process(false)


func abrir() -> void:
	if aberto:
		return
	aberto = true
	_t = 0.0
	_velame.visible = true
	set_process(true)
	Audio.tocar("efeitos/paraquedas_abrir_", global_position + global_basis.z * 4.0, 2.0, 1.1, 0.05, "Efeitos", 20.0)


## Velocidade do carro (m/s): o velame fica mais esticado e balança mais rápido.
func definir_velocidade(v: float) -> void:
	_vel = v


func _process(delta: float) -> void:
	_t += delta
	var p := clampf(_t / ABRIR_S, 0.0, 1.0)
	var e := p * p * (3.0 - 2.0 * p)
	# Distância atrás do carro e balanço (em espaço do carro: atrás = +Z)
	var dist := lerpf(0.5, 6.5, e)
	var bal := Vector3(sin(_t * 2.3) * 0.35, 0.6 * e + sin(_t * 3.1) * 0.15, 0.0)
	var centro := _ancora + Vector3(0, 0, dist) + bal * e
	var tam := lerpf(0.15, 1.0, e) * (1.0 + sin(_t * 9.0) * 0.03 * e)
	# Boca virada para o carro: o topo da meia esfera aponta para trás (+Z)
	var para_tras := (centro - _ancora).normalized()
	var b := Basis.looking_at(-para_tras, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	_velame.transform = Transform3D(b * Basis.from_scale(Vector3(tam, tam * lerpf(0.3, 0.62, e), tam)), centro)
	(_velame.material_override as ShaderMaterial).set_shader_parameter("tempo", _t)
	# Linhas: da borda do velame até o pacote
	_linhas.clear_surfaces()
	_linhas.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in LINHAS:
		var a := TAU * i / LINHAS
		var borda := _velame.transform * Vector3(cos(a) * 0.9, 0.0, sin(a) * 0.9)
		_linhas.surface_add_vertex(_ancora)
		_linhas.surface_add_vertex(borda)
	_linhas.surface_end()
