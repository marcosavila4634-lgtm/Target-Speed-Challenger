class_name DragCockpit
extends Node3D
## Visão interna única do Drag Racing, no estilo de um carro de arrancada de verdade (igual em todos
## os carros): gaiola de proteção de tubos grafite, rede na janela do piloto, painel de fibra de
## carbono com o display digital no centro (marcha, velocidade, barra de giro com a faixa ideal,
## dados do motor) sob uma pala, conta-giros analógico preso na coluna com shift light, painel de
## chaves com capas vermelhas e LEDs, manômetros à direita (combustível e óleo em cima, câmbio
## embaixo), alavanca de câmbio de catraca, chicotes e conexões sob o painel e o
## volante de camurça (faixa da cor da equipe no alto, três raios, emblema no raio de baixo).
##
## Nada disso aparece de fora: as peças ficam numa camada própria (CAMADA_INTERIOR) que só a câmera
## do cockpit enxerga (as câmeras externas usam sem_interior()). A carroceria real do carro do
## jogador fica invisível só para esta câmera (CAMADA_CARRO), sem perder a camada da faixa da
## equipe, e continua projetando sombra na pista: vista de fora o carro é o original.
## O interior não recebe o sol (o teto faz sombra): uma sonda de reflexo escura, só dele, tira o
## brilho do céu, e duas luzes fracas próprias dão o reflexo dos tubos.
## A câmera treme com a aceleração e com o giro alto.

const CAMADA_CARRO := 1 << 19
## Interior do cockpit: o sol não ilumina esta camada (o teto faz sombra), só as luzes próprias.
const CAMADA_INTERIOR := 1 << 18
## Camada que recebe a faixa da equipe (decal do Veiculo): mantida na carroceria do jogador.
const CAMADA_FAIXA := 2
## Inclinação do painel (o alto fica mais longe do piloto).
const INCL_PAINEL := deg_to_rad(-8.0)

var camera: Camera3D
var conta_giros: ContaGiros
var velocimetro: VelocimetroDrag
var painel_digital: PainelDigital
var volante: Node3D
var _manometros: Array[Manometro] = []
var _shift_light: StandardMaterial3D
var _base_cam := Transform3D.IDENTITY
var _tremor := 0.0
var _acel := 0.0
var _rng := RandomNumberGenerator.new()
var _c: Dictionary
var _esq := -0.4     # parede esquerda (lado do piloto) e direita, a partir do olho
var _dir := 1.2
var _teto := 0.36
var _raio_aro := 0.2  # raio do aro do volante (centro do tubo)
var _cambio := Vector3(0.4, -0.31, -0.46)   # manopla do câmbio (espaço do cockpit)
var _marcha_ant := 0
var _t_troca := -1.0
var _lado_troca := 1.0
var _borboletas := {}                 # lado (-1 esquerda, 1 direita) -> pivô da borboleta
var _telas_espelho: Array[SubViewport] = []


## Manômetro pequeno do painel (fundo preto, escala branca, zona vermelha, ponteiro laranja).
class Manometro extends Control:
	var nome := ""
	var valor := 0.5

	func _draw() -> void:
		var f := Estilo.fonte(700)
		var c := size * 0.5
		var r := size.x * 0.47
		draw_circle(c, r, Color(0.015, 0.015, 0.02))
		draw_arc(c, r * 0.97, 0.0, TAU, 48, Color(0.25, 0.26, 0.28), r * 0.05, true)
		var ini := deg_to_rad(135.0)
		var arco := deg_to_rad(270.0)
		for i in 11:
			var a := ini + arco * i / 10.0
			var d := Vector2(cos(a), sin(a))
			var cor := Color(1.0, 0.25, 0.2) if i >= 9 else Color(0.92, 0.92, 0.92)
			draw_line(c + d * r * (0.7 if i % 5 == 0 else 0.78), c + d * r * 0.88, cor, 4.0 if i % 5 == 0 else 2.0, true)
		draw_arc(c, r * 0.9, ini + arco * 0.85, ini + arco, 16, Color(1.0, 0.2, 0.15), r * 0.06, true)
		var w := f.get_string_size(nome, HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 0.26)).x
		draw_string(f, c + Vector2(-w * 0.5, r * 0.62), nome, HORIZONTAL_ALIGNMENT_LEFT, -1, int(r * 0.26), Color(1.0, 0.6, 0.2))
		var a := ini + arco * clampf(valor, 0.0, 1.0)
		var d := Vector2(cos(a), sin(a))
		draw_line(c - d * r * 0.12, c + d * r * 0.82, Color(1.0, 0.5, 0.1), r * 0.06, true)
		draw_circle(c, r * 0.1, Color(0.2, 0.2, 0.22))


## Câmeras de fora (TV, perseguição, conferência) não enxergam o interior do cockpit.
static func sem_interior(cam: Camera3D) -> void:
	cam.cull_mask &= ~CAMADA_INTERIOR


func montar(v: Veiculo) -> void:
	name = "Cockpit"
	_c = Config.valor("drag", {})
	_rng.seed = 7
	var c := v.caixa_corpo
	# Olho do piloto: lado esquerdo, um pouco atrás do meio, abaixo do teto
	var olho := Vector3(c.position.x + c.size.x * 0.29, c.end.y - 0.4, c.get_center().z + c.size.z * 0.06)
	olho.y = clampf(olho.y, 1.0, 2.4)
	position = olho
	_esq = minf(c.position.x - olho.x + 0.14, -0.3)
	_dir = maxf(c.end.x - olho.x - 0.14, 1.0)
	v.add_child(self)
	# Carro do jogador fora da câmera do cockpit (mas com sombra e com a faixa da equipe)
	for n in v.find_children("*", "VisualInstance3D", true, false):
		if not is_ancestor_of(n):
			var vi := n as VisualInstance3D
			vi.layers = CAMADA_CARRO | (vi.layers & CAMADA_FAIXA)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.near = 0.03
	camera.far = 4000.0
	camera.cull_mask = 0xFFFFF & ~CAMADA_CARRO & ~CAMADA_FAIXA
	camera.rotation.x = deg_to_rad(-8.0)
	add_child(camera)
	_base_cam = camera.transform
	_montar_luz()
	# Interior próprio do carro (modelo recortado em assets/cockpit/), senão o genérico de arrancada
	var id_int := str(_c.get("interior_por_carro", {}).get(str(v.dados.get("id", "")), ""))
	var info: Dictionary = _c.get("interiores", {}).get(id_int, {})
	var arq := "res://assets/cockpit/%s/%s.glb" % [id_int, id_int]
	if not info.is_empty() and ResourceLoader.exists(arq):
		_montar_interior(load(arq), info, v.cor_equipe)
		return
	_montar_painel()
	_montar_gaiola()
	_montar_volante(v.cor_equipe)
	_montar_cambio()


## Interior de um carro de verdade (painel, volante, bancos, portas) com o olho do piloto do modelo
## na posição do olho do cockpit. Por cima, os instrumentos de arrancada (conta-giros com shift
## light na coluna e display digital no painel).
func _montar_interior(cena: PackedScene, info: Dictionary, cor: Color) -> void:
	var s := float(info.get("escala", 1.0))
	var o := _vetor(info.olho)
	var no: Node3D = cena.instantiate()
	no.scale = Vector3.ONE * s
	no.position = -o * s
	add_child(no)
	for gi: GeometryInstance3D in no.find_children("*", "GeometryInstance3D", true, false):
		gi.layers = CAMADA_INTERIOR
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mi := gi as MeshInstance3D
		if mi and mi.mesh:
			for k in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(k) as BaseMaterial3D
				if m:
					m.disable_fog = true   # a névoa de altura da pista não entra no carro
	for nome: String in info.get("ocultar", []):   # peças cortadas pelo recorte ou trocadas aqui
		var peca := no.find_child(nome, true, false) as Node3D
		if peca:
			peca.visible = false
	var vol: Dictionary = info.get("volante", {})
	var centro := (_vetor(vol.get("centro", [o.x, o.y - 0.25, o.z - 0.45])) - o) * s
	var cb: Array = info.get("cambio", [])   # manopla do câmbio; sem ela, à direita e abaixo do volante
	_cambio = (_vetor(cb) - o) * s if not cb.is_empty() else centro + Vector3(0.34, -0.2, 0.18)
	_montar_volante(cor, centro, float(vol.get("incl", 22.0)), float(vol.get("raio", 0.19)) * s, true)
	if bool(info.get("borboletas", false)):
		_montar_borboletas(float(vol.get("raio", 0.19)) * s)
	# Conta-giros na coluna (acima e à esquerda do volante) e display digital no alto do painel
	var cg: Array = info.get("conta_giros", [])
	var pos_cg := (_vetor(cg) - o) * s if not cg.is_empty() else centro + Vector3(-0.14, 0.2, -0.22)
	_montar_conta_giros(pos_cg, pos_cg + Vector3(0.03, -0.12, -0.06), float(info.get("conta_giros_escala", _c.get("conta_giros_escala", 1.25))))
	# Velocímetro no meio do painel, com a haste descendo até ele
	var vm: Array = info.get("velocimetro", [])
	if not vm.is_empty():
		var pos_v := (_vetor(vm) - o) * s
		velocimetro = VelocimetroDrag.new()
		_copo_mostrador(velocimetro, pos_v, pos_v + Vector3(0.0, -0.1, -0.05), float(_c.get("velocimetro_escala", 1.0)))
	# Retrovisores com a imagem de trás (câmeras próprias)
	for e: Dictionary in info.get("espelhos", []):
		_espelho(e, no)
	var dp: Array = info.get("display", [])
	var pos_d := (_vetor(dp) - o) * s if not dp.is_empty() else centro + Vector3(0.33, 0.12, -0.34)
	if bool(info.get("display_tela", false)):   # na tela do próprio painel do carro, sem moldura
		painel_digital = PainelDigital.new()
		_tela(painel_digital, Vector2i(640, 340), Vector2(0.19, 0.101) * s, pos_d, deg_to_rad(float(info.get("display_giro", 0.0))), 1.15)
	else:
		_montar_display(pos_d, deg_to_rad(float(info.get("display_giro", -10.0))), float(info.get("display_escala", 0.7)))


static func _vetor(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Sombra do teto: sonda de reflexo escura só para o interior (sem céu no brilho do carbono e da
## camurça), uma luz de frente vinda do para-brisa e outra fria da janela para o reflexo dos tubos.
func _montar_luz() -> void:
	var sonda := ReflectionProbe.new()
	sonda.size = Vector3(_dir - _esq + 0.6, 1.8, 2.4)
	sonda.position = Vector3((_esq + _dir) * 0.5, -0.2, -0.4)
	sonda.interior = true
	sonda.box_projection = true
	sonda.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	sonda.ambient_color = Color(0.1, 0.095, 0.09)
	sonda.ambient_color_energy = 1.0
	sonda.intensity = 0.35
	sonda.cull_mask = 0xFFFFF & ~CAMADA_CARRO & ~CAMADA_INTERIOR
	sonda.reflection_mask = CAMADA_INTERIOR
	sonda.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(sonda)
	var frente := OmniLight3D.new()
	frente.light_cull_mask = CAMADA_INTERIOR
	frente.light_energy = 1.1
	frente.light_color = Color(1.0, 0.88, 0.75)
	frente.omni_range = 1.8
	frente.omni_attenuation = 1.4
	frente.position = Vector3(0.15, 0.3, -0.75)
	add_child(frente)
	var janela := OmniLight3D.new()
	janela.light_cull_mask = CAMADA_INTERIOR
	janela.light_energy = 0.5
	janela.light_color = Color(0.75, 0.85, 1.0)
	janela.omni_range = 1.4
	janela.position = Vector3(_esq - 0.25, 0.1, -0.3)
	add_child(janela)


# ------------------------------------------------------------------ peças

func _mat(cor: Color, rug := 0.75, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.roughness = rug
	m.metallic = metal
	m.metallic_specular = 0.2 if metal < 0.5 else 0.5
	m.disable_fog = true   # a névoa de altura da pista não entra no carro (clareava o preto)
	return m


func _brilho(cor: Color, energia: float) -> StandardMaterial3D:
	var m := _mat(cor * 0.4, 0.3)
	m.emission_enabled = true
	m.emission = cor
	m.emission_energy_multiplier = energia
	return m


func _peca(malha: Mesh, pos: Vector3, mat: Material, pai: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = CAMADA_INTERIOR
	(pai if pai else self).add_child(mi)
	return mi


func _caixa(tam: Vector3, pos: Vector3, mat: Material, pai: Node3D = null) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = tam
	return _peca(b, pos, mat, pai)


func _esfera(raio: float, pos: Vector3, mat: Material, pai: Node3D = null) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = raio
	s.height = raio * 2.0
	s.radial_segments = 16
	s.rings = 8
	return _peca(s, pos, mat, pai)


## Base com o eixo Y ao longo de `eixo` (para cilindros e cápsulas entre dois pontos).
func _base_eixo(eixo: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(eixo.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := eixo.cross(ref).normalized()
	return Basis(x, eixo, x.cross(eixo))


## Tubo cilíndrico entre dois pontos (gaiola, barras, fios).
func _tubo(a: Vector3, b: Vector3, raio: float, mat: Material, pai: Node3D = null, raio_b := -1.0) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = raio if raio_b < 0.0 else raio_b
	cm.bottom_radius = raio
	cm.height = a.distance_to(b)
	cm.radial_segments = 16
	cm.rings = 1
	var mi := _peca(cm, (a + b) * 0.5, mat, pai)
	mi.basis = _base_eixo((b - a).normalized())
	return mi


## Cápsula entre dois pontos (dedos, mangas).
func _capsula(a: Vector3, b: Vector3, raio: float, mat: Material, pai: Node3D = null) -> MeshInstance3D:
	var cm := CapsuleMesh.new()
	cm.radius = raio
	cm.height = a.distance_to(b) + raio * 2.0
	cm.radial_segments = 16
	cm.rings = 4
	var mi := _peca(cm, (a + b) * 0.5, mat, pai)
	mi.basis = _base_eixo((b - a).normalized())
	return mi


func _rotulo(texto: String, pos: Vector3, tam: int, cor: Color, pai: Node3D = null, pixel := 0.0007) -> Label3D:
	var r := Label3D.new()
	r.text = texto
	r.font = Estilo.fonte(700)
	r.font_size = tam
	r.pixel_size = pixel
	r.modulate = cor
	r.outline_size = 0
	r.layers = CAMADA_INTERIOR
	r.position = pos
	(pai if pai else self).add_child(r)
	return r


## Quadro 3D com o conteúdo de uma SubViewport (mostradores desenhados em 2D).
func _tela(no: Control, px: Vector2i, tam: Vector2, pos: Vector3, giro_x: float, brilho := 1.0, pai: Node3D = null) -> MeshInstance3D:
	var sv := SubViewport.new()
	sv.size = px
	sv.transparent_bg = true
	sv.msaa_2d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	no.size = Vector2(px)
	sv.add_child(no)
	var q := QuadMesh.new()
	q.size = tam
	var m := StandardMaterial3D.new()
	m.albedo_texture = sv.get_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(brilho, brilho, brilho)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.disable_fog = true
	var mi := _peca(q, pos, m, pai)
	mi.rotation.x = giro_x
	return mi


func _material_carbono(escala := 60.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """shader_type spatial;
render_mode fog_disabled;
// Fibra de carbono: trama em sarja 2x2 com brilho que muda com o ângulo.
uniform float escala = 60.0;
varying vec3 p;
void vertex() { p = VERTEX; }
void fragment() {
	vec2 uv = vec2(p.x + p.z, p.y + p.z) * escala;
	vec2 c = floor(uv);
	float sarja = mod(c.x + floor(c.y / 2.0) * 2.0 + c.y, 4.0) < 2.0 ? 1.0 : 0.0;
	vec2 f = fract(uv);
	float fio = sarja > 0.5 ? f.x : f.y;
	float brilho = 0.5 + 0.5 * sin(fio * 3.1416);
	ALBEDO = vec3(0.012, 0.013, 0.015) + vec3(0.028) * brilho;
	ROUGHNESS = mix(0.5, 0.3, brilho);
	SPECULAR = 0.15;
	CLEARCOAT = 0.25;
	CLEARCOAT_ROUGHNESS = 0.2;
}"""
	mat.set_shader_parameter("escala", escala)
	return mat


## Ponto na face inclinada do painel (x, altura y), `frente` metros à frente dela (para o piloto).
func _na_face(x: float, y: float, frente := 0.0) -> Vector3:
	return Vector3(x, y, -0.81 + (y + 0.32) * tan(INCL_PAINEL) + 0.016 + frente)


# ------------------------------------------------------------------ painel

func _montar_painel() -> void:
	var carbono := _material_carbono()
	var preto := _mat(Color(0.01, 0.011, 0.013), 0.95)
	var anod := _mat(Color(0.04, 0.042, 0.048), 0.35, 0.8)
	var larg := _dir - _esq + 0.1
	var meio := (_esq + _dir) * 0.5
	# Painel: face de carbono inclinada, tampo preto fosco (antirreflexo) e prateleira de baixo
	var face := _caixa(Vector3(larg, 0.5, 0.03), Vector3(meio, -0.32, -0.81), carbono)
	face.rotation.x = INCL_PAINEL
	var topo := _caixa(Vector3(larg, 0.02, 0.36), Vector3(meio, -0.075, -1.0), preto)
	topo.rotation.x = deg_to_rad(3)
	_caixa(Vector3(larg, 0.025, 0.05), _na_face(meio, -0.078, -0.01), _mat(Color(0.02, 0.02, 0.022), 0.6, 0.5))  # friso
	_caixa(Vector3(larg, 0.2, 0.45), Vector3(meio, -0.68, -0.82), preto)
	# Display digital no centro, atrás do volante
	_montar_display(_na_face(0.0, -0.245, 0.0), INCL_PAINEL)
	_montar_conta_giros()
	_montar_chaves()
	_montar_manometros()
	_montar_fiacao()


## Display digital (data logger) com moldura de alumínio escuro, pala e etiqueta, virado para o
## piloto. No interior de um carro de rua fica num suporte em cima do painel.
func _montar_display(pos: Vector3, giro_x: float, escala := 1.0) -> void:
	var preto := _mat(Color(0.01, 0.011, 0.013), 0.95)
	var anod := _mat(Color(0.04, 0.042, 0.048), 0.35, 0.8)
	var base := Node3D.new()
	base.position = pos
	base.rotation.x = giro_x
	base.scale = Vector3.ONE * escala
	add_child(base)
	painel_digital = PainelDigital.new()
	_caixa(Vector3(0.335, 0.19, 0.03), Vector3.ZERO, preto, base)
	_caixa(Vector3(0.345, 0.2, 0.012), Vector3(0, 0, -0.012), anod, base)
	_tela(painel_digital, Vector2i(640, 340), Vector2(0.30, 0.16), Vector3(0, 0, 0.017), 0.0, 1.15, base)
	var pala := _caixa(Vector3(0.36, 0.01, 0.05), Vector3(0, 0.104, 0.018), _material_carbono(90.0), base)
	pala.rotation.x = deg_to_rad(6)
	_rotulo("TSC DATA", Vector3(0, -0.09, 0.018), 20, Color(1.0, 0.75, 0.2), base)


## Conta-giros analógico preso por uma haste na coluna esquerda, com copo e shift light em cima.
func _montar_conta_giros(pos_cg := Vector3.INF, fim := Vector3.INF, escala := -1.0) -> void:
	var cromo := _mat(Color(0.75, 0.77, 0.8), 0.15, 1.0)
	conta_giros = ContaGiros.new()
	if pos_cg == Vector3.INF:
		pos_cg = Vector3(maxf(-0.3, _esq + 0.13), -0.05, -0.76)
	if fim == Vector3.INF:
		fim = Vector3(_esq + 0.03, -0.04, -0.86)
	# Mostrador, copo e shift light num conjunto só (escala em drag.conta_giros_escala ou no interior)
	var g := _copo_mostrador(conta_giros, pos_cg, fim, escala if escala > 0.0 else float(_c.get("conta_giros_escala", 1.25)))
	# Shift light: copo cromado apontado para o piloto, acima e à esquerda do conta-giros
	var pos_sl := Vector3(-0.055, 0.075, -0.02)
	var sl := CylinderMesh.new()
	sl.top_radius = 0.021
	sl.bottom_radius = 0.024
	sl.height = 0.07
	_peca(sl, pos_sl, cromo, g).rotation.x = PI * 0.5
	_shift_light = _brilho(Color(1.0, 0.55, 0.1), 0.0)
	var lente := CylinderMesh.new()
	lente.top_radius = 0.018
	lente.bottom_radius = 0.018
	lente.height = 0.004
	_peca(lente, pos_sl + Vector3(0, 0, 0.036), _shift_light, g).rotation.x = PI * 0.5
	_tubo(pos_sl + Vector3(0.01, -0.015, -0.02), Vector3(-0.02, 0.05, -0.05), 0.006, cromo, g)


## Retrovisor com a imagem de trás: o vidro do próprio modelo (`malha`, aceita "*") vira a tela de
## uma câmera no espelho, desenhada numa SubViewport e projetada no vidro, espelhada, pelo plano
## dele (o contorno é o da carcaça do modelo). A câmera olha para o reflexo do olhar do piloto no
## vidro, ou para `olhar` quando dado; fov vertical em graus.
func _espelho(e: Dictionary, modelo: Node3D) -> void:
	var mi := modelo.find_child(str(e.malha), true, false) as MeshInstance3D
	if mi == null:
		return
	var t := Transform3D.IDENTITY   # espaço da malha -> espaço do cockpit
	var n: Node = mi
	while n != self:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	# Normal média do vidro, virada para o piloto (na origem)
	var normal := Vector3.ZERO
	for k in mi.mesh.get_surface_count():
		for v: Vector3 in mi.mesh.surface_get_arrays(k)[Mesh.ARRAY_NORMAL]:
			normal += v
	var ab := mi.get_aabb()
	var centro := t * ab.get_center()
	normal = (t.basis * normal).normalized()
	if normal.dot(-centro) < 0.0:
		normal = -normal
	var lado := Vector3.UP.cross(normal).normalized()
	var cima := normal.cross(lado)
	# Tamanho do vidro no plano dele (lado, cima)
	var u0 := INF
	var u1 := -INF
	var v0 := INF
	var v1 := -INF
	for i in 8:
		var p := t * ab.get_endpoint(i)
		u0 = minf(u0, p.dot(lado))
		u1 = maxf(u1, p.dot(lado))
		v0 = minf(v0, p.dot(cima))
		v1 = maxf(v1, p.dot(cima))
	var w := u1 - u0
	var h := v1 - v0
	# Espaço da malha -> UV da tela (u da esquerda para a direita do piloto, v de cima para baixo)
	var para_uv := Transform3D(Basis(lado / w, -cima / h, normal).transposed(), Vector3(-u0 / w, v1 / h, 0.0)) * t
	var alt := int(e.get("px", 200))
	var sv := SubViewport.new()
	sv.size = Vector2i(roundi(alt * w / h), alt)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	_telas_espelho.append(sv)
	var cam := Camera3D.new()
	cam.fov = float(e.get("fov", 15.0))
	cam.near = 0.2
	cam.far = 1500.0
	cam.cull_mask = camera.cull_mask & ~CAMADA_INTERIOR
	var env := get_world_3d().environment if get_world_3d() else null
	if env:   # sem os efeitos caros de tela na imagem pequena
		env = env.duplicate()
		env.ssr_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.volumetric_fog_enabled = false
		cam.environment = env
	sv.add_child(cam)
	cam.current = true
	# A câmera fica fora da árvore 3D do carro (dentro da SubViewport): segue o espelho por aqui
	var d := centro.normalized()
	var olhar := _vetor(e.olhar).normalized() if e.has("olhar") else d - 2.0 * d.dot(normal) * normal
	var guia := RemoteTransform3D.new()
	guia.position = centro
	guia.basis = Basis.looking_at(olhar)
	guia.update_scale = false
	add_child(guia)
	guia.remote_path = guia.get_path_to(cam)
	var vidro := ShaderMaterial.new()
	vidro.shader = Shader.new()
	vidro.shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled;
uniform sampler2D tela : source_color, filter_linear;
uniform mat4 para_uv;
varying vec2 uv_tela;
void vertex() {
	uv_tela = (para_uv * vec4(VERTEX, 1.0)).xy;
}
void fragment() {
	ALBEDO = texture(tela, vec2(1.0 - uv_tela.x, uv_tela.y)).rgb * 0.8 + vec3(0.015);
}"""
	vidro.set_shader_parameter("tela", sv.get_texture())
	vidro.set_shader_parameter("para_uv", para_uv)
	mi.material_override = vidro


## Mostrador redondo (desenhado em `no`) num copo cromado virado para o olho do piloto, com haste
## e braçadeira até `fim` (coluna A, coluna de direção ou o painel). Devolve o conjunto.
func _copo_mostrador(no: Control, pos: Vector3, fim: Vector3, escala: float) -> Node3D:
	var cromo := _mat(Color(0.75, 0.77, 0.8), 0.15, 1.0)
	var g := Node3D.new()
	g.position = pos
	g.basis = Basis.looking_at(pos).scaled(Vector3.ONE * escala)   # frente (+Z) para o olho, na origem
	add_child(g)
	var copo := CylinderMesh.new()
	copo.top_radius = 0.066
	copo.bottom_radius = 0.058
	copo.height = 0.06
	copo.radial_segments = 32
	var c := _peca(copo, Vector3(0, 0, -0.032), cromo, g)
	c.rotation.x = PI * 0.5 - deg_to_rad(4)
	var fundo := _esfera(0.052, Vector3(0, 0, -0.06), _mat(Color(0.03, 0.03, 0.035), 0.5, 0.6), g)
	fundo.scale = Vector3(1, 1, 0.6)
	_tela(no, Vector2i(640, 640), Vector2(0.125, 0.125), Vector3(0, 0, 0.001), deg_to_rad(-4), 1.0, g)
	_tubo(g.transform * Vector3(-0.02, -0.02, -0.07), fim, 0.009, cromo)
	_tubo(fim + Vector3(0, -0.02, 0), fim + Vector3(0, 0.02, 0), 0.03, _mat(Color(0.05, 0.05, 0.06), 0.4, 0.8))
	return g


## Painel de chaves: placa de alumínio escuro, cinco chaves alavanca com capas vermelhas levantadas,
## LED de cada circuito em cima e etiqueta embaixo.
func _montar_chaves() -> void:
	var nomes := ["IGN", "COMB.", "VENT.", "BOMBA", "CÂMBIO"]
	var placa := _caixa(Vector3(0.31, 0.13, 0.012), _na_face(0.5, -0.215, 0.004), _mat(Color(0.05, 0.05, 0.06), 0.35, 0.7))
	placa.rotation.x = INCL_PAINEL
	var cromo := _mat(Color(0.8, 0.8, 0.82), 0.2, 1.0)
	var vermelho := _mat(Color(0.8, 0.05, 0.04), 0.25)
	vermelho.clearcoat_enabled = true
	vermelho.clearcoat = 0.8
	for i in nomes.size():
		var x := 0.39 + i * 0.055
		var base := _na_face(x, -0.215, 0.012)
		_tubo(base, base + Vector3(0, 0.012, 0.025), 0.004, cromo)   # alavanca
		var capa := _caixa(Vector3(0.03, 0.044, 0.01), base + Vector3(0, 0.026, 0.016), vermelho)
		capa.rotation.x = deg_to_rad(-40)   # capa levantada, articulada no alto
		_caixa(Vector3(0.034, 0.01, 0.014), base + Vector3(0, 0.026, 0.003), vermelho)
		var led := _brilho(Color(0.2, 1.0, 0.3) if i == 0 else Color(1.0, 0.15, 0.1), 3.0 if i < 2 else 0.4)
		_esfera(0.005, _na_face(x, -0.163, 0.012), led)
		_rotulo(nomes[i], _na_face(x, -0.262, 0.012), 22, Color(0.92, 0.92, 0.92), null, 0.00065).rotation.x = INCL_PAINEL


## Manômetros com aro cromado: combustível e óleo em cima, câmbio embaixo (lado do carona).
func _montar_manometros() -> void:
	var cromo := _mat(Color(0.72, 0.74, 0.77), 0.18, 1.0)
	var lugares := [["COMB.", 0.73, -0.2], ["ÓLEO", 0.87, -0.2], ["CÂMBIO", 0.8, -0.355]]
	for l: Array in lugares:
		var p := _na_face(float(l[1]) * minf(1.0, (_dir + 0.05) / 1.0), float(l[2]), 0.0)
		var aro := CylinderMesh.new()
		aro.top_radius = 0.058
		aro.bottom_radius = 0.06
		aro.height = 0.022
		aro.radial_segments = 32
		_peca(aro, p + Vector3(0, 0, 0.004), cromo).rotation.x = PI * 0.5 + INCL_PAINEL
		var m := Manometro.new()
		m.nome = l[0]
		_manometros.append(m)
		_tela(m, Vector2i(256, 256), Vector2(0.104, 0.104), p + Vector3(0, 0, 0.0155), INCL_PAINEL)


## Embaixo do painel: chicotes, conexões coloridas (AN) e caixas de relé, entre o volante e o câmbio.
func _montar_fiacao() -> void:
	var fio := _mat(Color(0.02, 0.02, 0.02), 0.7)
	var malha := _mat(Color(0.05, 0.05, 0.055), 0.55, 0.4)
	var an_azul := _mat(Color(0.1, 0.25, 0.75), 0.25, 0.9)
	var an_verm := _mat(Color(0.75, 0.08, 0.06), 0.25, 0.9)
	var aluminio := _mat(Color(0.6, 0.62, 0.65), 0.3, 1.0)
	for i in 9:
		var x := lerpf(-0.22, 0.62, i / 8.0) + _rng.randf_range(-0.03, 0.03)
		var a := _na_face(x, -0.44 + _rng.randf_range(-0.03, 0.03), 0.0)
		var b := Vector3(x + _rng.randf_range(-0.15, 0.15), -0.66, a.z + _rng.randf_range(0.05, 0.2))
		_tubo(a, b, _rng.randf_range(0.005, 0.009), malha if i % 3 == 0 else fio)
		if i % 2 == 0:
			var an := _tubo(a + Vector3(0, 0, -0.005), a + Vector3(0, 0, 0.03), 0.011, an_azul if i % 4 == 0 else an_verm)
			an.mesh.radial_segments = 6
	# Caixas de relé e fusíveis, e a barra de alumínio que as segura
	for i in 3:
		var p := _na_face(-0.12 + i * 0.1, -0.5, 0.02)
		_caixa(Vector3(0.07, 0.045, 0.04), p, _mat(Color(0.03, 0.03, 0.035), 0.6)).rotation.x = INCL_PAINEL
		_esfera(0.004, p + Vector3(0.025, 0.012, 0.022), _brilho(Color(1.0, 0.2, 0.1), 1.5))
	_tubo(_na_face(-0.25, -0.54, 0.03), _na_face(0.25, -0.54, 0.03), 0.008, aluminio)


# ------------------------------------------------------------------ gaiola e rede

func _montar_gaiola() -> void:
	var tubo := _mat(Color(0.3, 0.31, 0.33), 0.28, 0.85)
	var preto := _mat(Color(0.03, 0.03, 0.035), 0.4, 0.5)
	var esq := _esq
	var dir := _dir
	var teto := _teto
	var r := 0.022
	# Colunas A (seguem o para-brisa), arco da frente do teto e barra sob o painel
	var pontos := [
		[Vector3(esq, -0.09, -0.93), Vector3(esq + 0.03, teto, -0.28)],
		[Vector3(dir, -0.09, -1.02), Vector3(dir - 0.03, teto, -0.3)],
		[Vector3(esq + 0.03, teto, -0.28), Vector3(dir - 0.03, teto, -0.3)],
		[Vector3(esq, -0.52, -0.7), Vector3(dir, -0.52, -0.72)],
		# Barras de porta em "X" e trilho do teto do lado do piloto
		[Vector3(esq, -0.62, -0.9), Vector3(esq - 0.02, -0.12, 0.3)],
		[Vector3(esq, -0.14, -0.95), Vector3(esq - 0.02, -0.64, 0.3)],
		[Vector3(esq + 0.03, teto, -0.28), Vector3(esq, teto, 0.45)],
		# Lado do carona: barra de porta e diagonal do teto
		[Vector3(dir, -0.46, -0.95), Vector3(dir, -0.28, 0.3)],
		[Vector3(dir - 0.03, teto, -0.3), Vector3(dir - 0.05, teto - 0.05, 0.45)],
	]
	for p: Array in pontos:
		_tubo(p[0], p[1], r, tubo)
	# Nós soldados (reforço) onde os tubos se encontram
	for p: Vector3 in [Vector3(esq + 0.03, teto, -0.28), Vector3(dir - 0.03, teto, -0.3), Vector3(esq, -0.52, -0.7), Vector3(dir, -0.52, -0.72)]:
		_esfera(r * 1.35, p, tubo)
	var cruz := Vector3(esq - 0.01, -0.38, -0.3)
	_esfera(r * 1.3, cruz, tubo)
	# Espuma de proteção preta na barra de porta de cima, na altura do ombro
	_tubo(Vector3(esq - 0.012, -0.24, 0.05), Vector3(esq - 0.018, -0.15, 0.3), 0.036, _mat(Color(0.02, 0.02, 0.022), 0.95))
	# Suporte central do para-brisa (fino, escuro) e borracha do para-brisa no alto
	_tubo(Vector3(0.55, -0.08, -1.0), Vector3(0.58, teto - 0.02, -0.34), 0.008, preto)
	_caixa(Vector3(dir - esq, 0.05, 0.05), Vector3((esq + dir) * 0.5, teto - 0.035, -0.33), _mat(Color(0.01, 0.01, 0.012), 0.9))
	# Rede da janela do piloto, presa por fitas no alto
	var q := QuadMesh.new()
	q.size = Vector2(0.95, 0.62)
	var rede := ShaderMaterial.new()
	rede.shader = Shader.new()
	rede.shader.code = """shader_type spatial;
render_mode cull_disabled, fog_disabled;
// Rede de janela: fitas pretas trançadas em losango (45°), com borda de cinta grossa.
void fragment() {
	vec2 d = vec2(UV.x * 0.95 + UV.y * 0.62, UV.x * 0.95 - UV.y * 0.62) * 9.0;
	vec2 f = abs(fract(d) - 0.5);
	float fita = step(0.36, max(f.x, f.y));
	float borda = step(UV.x, 0.035) + step(0.965, UV.x) + step(UV.y, 0.05) + step(0.95, UV.y);
	ALPHA = clamp(fita + borda, 0.0, 1.0);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	float trama = 0.8 + 0.2 * sin((d.x + d.y) * 25.0);
	ALBEDO = vec3(0.022) * trama + vec3(0.02) * borda;
	ROUGHNESS = 1.0;
	SPECULAR = 0.02;
}"""
	var rd := _peca(q, Vector3(esq + 0.035, -0.03, -0.12), rede)
	rd.rotation.y = PI * 0.5
	for z: float in [-0.5, 0.25]:
		_tubo(Vector3(esq + 0.035, 0.28, z), Vector3(esq + 0.03, teto, z), 0.006, _mat(Color(0.02, 0.02, 0.02), 0.9))


# ------------------------------------------------------------------ volante

func _montar_volante(cor: Color, pos := Vector3(0.0, -0.29, -0.42), incl := 18.0, raio := 0.2, do_interior := false) -> void:
	volante = Node3D.new()
	volante.position = pos
	volante.rotation.x = deg_to_rad(-incl)   # coluna subindo para o piloto: o alto do aro fica mais à frente
	add_child(volante)
	_raio_aro = raio
	if do_interior:   # o volante é o do próprio interior
		return
	var camurca := _mat(Color(0.022, 0.022, 0.024), 1.0)
	camurca.rim_enabled = true
	camurca.rim = 0.35
	camurca.rim_tint = 0.2
	var aro := TorusMesh.new()
	aro.inner_radius = 0.181
	aro.outer_radius = 0.219
	aro.rings = 96
	aro.ring_segments = 16
	_peca(aro, Vector3.ZERO, camurca, volante).rotation.x = PI * 0.5
	# Faixa de centro no alto (cor da equipe)
	var fita := CylinderMesh.new()   # faixa enrolada no aro: cilindro deitado ao longo do aro
	fita.top_radius = 0.0205
	fita.bottom_radius = 0.0205
	fita.height = 0.024
	fita.radial_segments = 16
	var marca := _peca(fita, Vector3(0, 0.2, 0), _mat(cor, 0.8), volante)
	marca.rotation.z = PI * 0.5
	marca.name = "Marca"
	# Prato de três raios em alumínio anodizado preto, com furos de alívio
	var anod := _mat(Color(0.035, 0.035, 0.04), 0.3, 0.9)
	for lado: float in [-1.0, 1.0]:
		_caixa(Vector3(0.15, 0.05, 0.008), Vector3(lado * 0.11, -0.005, -0.004), anod, volante)
		for k in 2:
			_tubo(Vector3(lado * (0.075 + k * 0.045), -0.005, -0.009), Vector3(lado * (0.075 + k * 0.045), -0.005, 0.001), 0.012, _mat(Color(0.005, 0.005, 0.005), 1.0), volante)
	var baixo := _caixa(Vector3(0.075, 0.15, 0.008), Vector3(0, -0.105, -0.004), anod, volante)
	baixo.name = "RaioBaixo"
	var emblema := _rotulo("TSC", Vector3(0, -0.12, 0.002), 64, Color(1.0, 0.8, 0.2), volante, 0.0005)
	emblema.font = load("res://assets/fontes/RacingSansOne-Regular.ttf")
	# Cubo com engate rápido (anel cromado) e coluna de direção indo para o painel
	var cromo := _mat(Color(0.75, 0.77, 0.8), 0.15, 1.0)
	var cubo := CylinderMesh.new()
	cubo.top_radius = 0.042
	cubo.bottom_radius = 0.048
	cubo.height = 0.035
	cubo.radial_segments = 32
	_peca(cubo, Vector3(0, 0, 0.012), _mat(Color(0.03, 0.03, 0.035), 0.4, 0.6), volante).rotation.x = PI * 0.5
	var anel := TorusMesh.new()
	anel.inner_radius = 0.028
	anel.outer_radius = 0.036
	_peca(anel, Vector3(0, 0, 0.03), cromo, volante).rotation.x = PI * 0.5
	_tubo(Vector3(0, 0, -0.02), Vector3(0, 0, -0.34), 0.03, _mat(Color(0.06, 0.06, 0.065), 0.4, 0.8), volante)


## Alavanca de câmbio de catraca à direita do piloto: base de alumínio, trilho, haste cromada e
## manopla em "T" com o botão do nitro.
func _montar_cambio() -> void:
	var aluminio := _mat(Color(0.55, 0.57, 0.6), 0.3, 1.0)
	var cromo := _mat(Color(0.8, 0.82, 0.85), 0.12, 1.0)
	var preto := _mat(Color(0.02, 0.02, 0.022), 0.6)
	var base := Vector3(0.39, -0.66, -0.52)
	_caixa(Vector3(0.08, 0.06, 0.22), base, aluminio)
	_caixa(Vector3(0.012, 0.012, 0.18), base + Vector3(0.0, 0.036, 0.0), preto)
	for i in 5:
		_caixa(Vector3(0.03, 0.006, 0.006), base + Vector3(0.025, 0.034, -0.07 + i * 0.035), preto)
	var topo := Vector3(0.4, -0.33, -0.46)
	_tubo(base + Vector3(0, 0.03, 0.02), topo, 0.009, cromo)
	_capsula(topo + Vector3(-0.045, 0.012, 0), topo + Vector3(0.045, 0.012, 0), 0.016, preto)
	_tubo(topo + Vector3(0, 0.026, 0), topo + Vector3(0, 0.036, 0), 0.008, _brilho(Color(1.0, 0.15, 0.1), 0.8))
	_tubo(topo + Vector3(0, -0.05, 0.01), topo + Vector3(-0.008, -0.08, 0.05), 0.004, cromo)   # gatilho da trava


# ------------------------------------------------------------------ atualização

## Instrumentos do painel a partir da simulação.
func instrumentos(m: DragMotor, delta: float) -> void:
	conta_giros.atualizar(m.rpm, m.marcha, m.velocidade_kmh(), m.no_limitador)
	if velocimetro:
		velocimetro.atualizar(m.velocidade_kmh())
	painel_digital.atualizar(m, delta)
	var faixa: Array = _c.get("faixa_ideal", [6900, 7600])
	# Shift light: acende na faixa ideal, pisca no limitador (só visual, sem sinal sonoro)
	var aceso := m.marcha >= 1 and m.rpm >= float(faixa[0])
	if m.no_limitador:
		aceso = fmod(Time.get_ticks_msec() / 60.0, 2.0) < 1.0
	_shift_light.emission_energy_multiplier = 8.0 if aceso else 0.0
	var giro := m.rpm / float(_c.get("rpm_limite", 8000))
	var valores := [0.78 - m.distancia / 4000.0, lerpf(0.2, 0.85, giro), lerpf(0.35, 0.6, giro)]
	for i in _manometros.size():
		_manometros[i].valor = valores[i]
		_manometros[i].queue_redraw()
	_troca_de_marcha(m.marcha, delta)


## Troca nas borboletas atrás do volante: a borboleta é puxada e volta
## (direita sobe, esquerda reduz). Um toque curto: puxa, segura e solta.
const PUXAO_S := 0.22

func _troca_de_marcha(marcha: int, delta: float) -> void:
	if _borboletas.is_empty():
		return
	if marcha != _marcha_ant:
		_lado_troca = 1.0 if marcha > _marcha_ant else -1.0
		_marcha_ant = marcha
		_t_troca = 0.0
	if _t_troca < 0.0:
		return
	_t_troca += delta
	var f := clampf(_t_troca / PUXAO_S, 0.0, 1.0)
	var forca := sin(f * PI)   # sobe e volta
	if _borboletas.has(_lado_troca):
		(_borboletas[_lado_troca] as Node3D).rotation.x = -deg_to_rad(10.0) * forca
	if f >= 1.0:
		_t_troca = -1.0


## Tremor e balanço da cabeça: aceleração (m/s²), giro (0..1) e velocidade (m/s).
func atualizar(delta: float, acel: float, giro: float, vel: float, direcao := 0.0) -> void:
	_acel = lerpf(_acel, acel, 1.0 - exp(-delta * 4.0))
	_tremor = clampf(giro * giro * 0.6 + vel / 90.0 * 0.4, 0.0, 1.0)
	var t := _base_cam
	# Aceleração empurra a cabeça para trás e levanta o olhar um pouco
	t.origin += Vector3(0, 0, _acel * 0.006)
	t.basis = _base_cam.basis * Basis(Vector3.RIGHT, deg_to_rad(_acel * 0.25))
	var amp := 0.0025 * _tremor
	t.origin += Vector3(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp), 0)
	camera.transform = t
	# Espelhos só renderizam com a visão interna na tela
	var modo := SubViewport.UPDATE_ALWAYS if camera.current else SubViewport.UPDATE_DISABLED
	for sv in _telas_espelho:
		sv.render_target_update_mode = modo
	if volante:
		volante.rotation.z = lerpf(volante.rotation.z, -direcao * 0.3, 1.0 - exp(-delta * 6.0))


## Borboletas de câmbio de fibra de carbono atrás do aro (volantes de interiores que não têm):
## a direita sobe marcha, a esquerda reduz. Giram junto com o volante; o pivô fica perto do cubo.
func _montar_borboletas(raio: float) -> void:
	var carbono := _material_carbono(120.0)
	for lado: float in [-1.0, 1.0]:
		var pivo := Node3D.new()
		pivo.position = Vector3(lado * raio * 0.5, 0.045, -0.075)
		volante.add_child(pivo)
		var p := _caixa(Vector3(raio * 0.42, 0.05, 0.005), Vector3(lado * raio * 0.21, 0.0, 0.0), carbono, pivo)
		p.rotation.z = lado * deg_to_rad(-8.0)
		_rotulo("+" if lado > 0.0 else "−", Vector3(lado * raio * 0.34, 0.0, 0.004), 40, Color(1, 1, 1), pivo, 0.0006)
		_borboletas[lado] = pivo
