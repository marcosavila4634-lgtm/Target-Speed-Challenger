class_name MuroSerpentes
extends Node3D
## Muro das três cabeças de serpente que cospem água (Serpent's Climb, armadilha "jatos"; pedido do dono
## 2026-10-06), IGUAL às artes dele (assets/MAPA SERPENTE/gospeagua). A escultura em relevo é gerada por
## tools/serpents_climb/muro_serpentes.gd (muro.res, cabeca.res e as texturas alinhadas); aqui ela é posta no
## lugar: o muro de pé numa fundação da mesma pedra que desce até o chão, com a calçada até a beira da pista,
## e as três cabeças saindo dos nichos com a boca virada para a estrada. Muro, cabeças e fundação são parede
## comum (não matam): só a água empurra.
## Local: x ao longo do muro, y para cima (0 = nível da pista), z para a pista (a frente da arte).

const PASTA := "res://assets/selva/muro_serpentes/"
const FOLGA_PISTA := 0.3     # m entre o focinho e a beira da pista
const ALCANCE := 17.0        # m de pista que as três bocas cobrem
const FUNDACAO_MAX := 30.0   # queda até o chão que a fundação maciça cobre; acima, laje e pilares
const LAJE := 3.0
const PILAR := 3.6

static var _muro: ArrayMesh
static var _cabeca: ArrayMesh
static var _mat_muro: ShaderMaterial
static var _mat_cabeca: ShaderMaterial

var bocas: Array[Vector3] = []     # onde a água sai (mundo)
var frente := Vector3.FORWARD      # para a pista (mundo)


static func _carregar() -> bool:
	if _muro:
		return true
	_muro = load(PASTA + "muro.res") as ArrayMesh
	_cabeca = load(PASTA + "cabeca.res") as ArrayMesh
	if _muro == null or _cabeca == null:
		push_warning("MuroSerpentes: falta muro.res/cabeca.res (rodar tools/serpents_climb/muro_serpentes.gd)")
		_muro = null
		return false
	_mat_muro = _material(_muro, "muro_frente_a", "muro_costas_a", "muro_cima_a", "")
	_mat_cabeca = _material(_cabeca, "cabeca_frente_a", "", "cabeca_cima_a", "cabeca_lado_a")
	return true


static func _textura(nome: String) -> ImageTexture:
	var caminho := PASTA + nome + ".png"
	var img: Image = null
	if ResourceLoader.exists(caminho):
		var tex := load(caminho) as Texture2D
		if tex:
			img = tex.get_image()
	if img == null:
		img = Image.load_from_file(ProjectSettings.globalize_path(caminho))
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _material(malha: ArrayMesh, frente_t: String, tras_t: String, cima_t: String, lado_t: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/relevo_vistas.gdshader")
	mat.set_shader_parameter("frente", _textura(frente_t))
	mat.set_shader_parameter("tem_tras", tras_t != "")
	if tras_t != "":
		mat.set_shader_parameter("tras", _textura(tras_t))
	mat.set_shader_parameter("cima", _textura(cima_t))
	mat.set_shader_parameter("tem_lado", lado_t != "")
	if lado_t != "":
		mat.set_shader_parameter("lado", _textura(lado_t))
	mat.set_shader_parameter("pedra", _textura("pedra"))
	mat.set_shader_parameter("boca", _textura("boca"))
	mat.set_shader_parameter("caixa_xy", malha.get_meta("caixa_xy"))
	mat.set_shader_parameter("caixa_z", malha.get_meta("caixa_z"))
	return mat


## Medidas do muro: [comprimento, espessura, quanto o focinho sai da face].
static func medidas() -> Array:
	if not _carregar():
		return [22.0, 4.6, 2.9]
	return [float(_muro.get_meta("comprimento")), float(_muro.get_meta("espessura")), float(_cabeca.get_meta("caixa_z").y) + 0.3]


## Põe o muro em `xf` (origem = meio do muro no nível da pista; +z local = para a pista) com a fundação até
## `chao_y` (mundo) e a calçada de `calcada` m na frente da face. Colisões em `corpo`.
func montar(xf: Transform3D, chao_y: float, calcada: float, corpo: StaticBody3D) -> void:
	if not _carregar():
		return
	name = "MuroSerpentes"
	transform = xf
	frente = xf.basis.z.normalized()
	var comp := float(_muro.get_meta("comprimento"))
	var esp := float(_muro.get_meta("espessura"))
	var alt := float(_muro.get_meta("altura"))
	var mi := MeshInstance3D.new()
	mi.mesh = _muro
	mi.material_override = _mat_muro
	add_child(mi)
	# Fundação e calçada: o mesmo bloco de pedra lisa da arte, do chão até logo abaixo da pista. Pista alta
	# (queda maior que FUNDACAO_MAX): laje grossa sobre pilares de pedra até o chão, como os da estrada
	var fundo := maxf(xf.origin.y - chao_y + 2.0, 3.0)
	var laje := fundo if fundo <= FUNDACAO_MAX else LAJE
	var fund := MeshInstance3D.new()
	fund.mesh = _caixa(Vector3(comp + 0.6, laje, esp + calcada))
	fund.material_override = _mat_muro
	fund.position = Vector3(0.0, -0.03 - laje * 0.5, (calcada) * 0.5)
	add_child(fund)
	var pilares: Array[Transform3D] = []
	if fundo > FUNDACAO_MAX:
		var alto := fundo - laje
		for px: float in [-comp * 0.36, 0.0, comp * 0.36]:
			var t := Transform3D(Basis.from_scale(Vector3(PILAR, alto, PILAR)), Vector3(px, -laje - alto * 0.5, calcada * 0.25))
			var pm := MeshInstance3D.new()
			pm.mesh = _caixa(Vector3(PILAR, alto, PILAR))   # no tamanho de verdade: a pedra não estica
			pm.material_override = _mat_muro
			pm.position = t.origin
			add_child(pm)
			pilares.append(t)
	# Cabeças nos nichos, com a placa encostada na moldura
	var placa := float(_muro.get_meta("placa"))
	var h_cab := float(_cabeca.get_meta("altura"))
	var boca_l: Vector3 = _cabeca.get_meta("boca")
	var cz: Vector2 = _cabeca.get_meta("caixa_z")
	var formas: Array[Transform3D] = []
	formas.append(Transform3D(Basis.from_scale(Vector3(comp, alt * 0.88, esp)), Vector3(0.0, alt * 0.44, 0.0)))
	formas.append(Transform3D(Basis.from_scale(Vector3(comp + 0.6, laje, esp + calcada)), fund.position))
	formas.append_array(pilares)
	for n: Vector2 in _muro.get_meta("nichos"):
		var cab := MeshInstance3D.new()
		cab.mesh = _cabeca
		cab.material_override = _mat_cabeca
		cab.position = Vector3(n.x, n.y - h_cab * 0.5, esp * 0.5 + 0.3)
		add_child(cab)
		bocas.append(xf * (cab.position + boca_l))
		formas.append(Transform3D(Basis.from_scale(Vector3(placa * 0.62, h_cab * 0.8, cz.y)), cab.position + Vector3(0.0, h_cab * 0.48, cz.y * 0.5)))
	for f in formas:
		var t := xf * f
		var forma := BoxShape3D.new()
		forma.size = Vector3(t.basis.x.length(), t.basis.y.length(), t.basis.z.length())
		var cs := CollisionShape3D.new()
		cs.shape = forma
		cs.transform = Transform3D(t.basis.orthonormalized(), t.origin)
		corpo.add_child(cs)


## Caixa com a cor de vértice da pedra lisa (COLOR.g = 1 no relevo_vistas).
static func _caixa(tam: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.9, 1.0, 0.0))
	var h := tam * 0.5
	for eixo in 3:
		for s: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[eixo] = s
			var a := Vector3.ZERO
			a[(eixo + 1) % 3] = 1.0
			var b := n.cross(a)
			var c := n * h
			var pa := a * h
			var pb := b * h
			st.set_normal(n)
			for v: Vector3 in [c - pa - pb, c + pa - pb, c + pa + pb, c - pa - pb, c + pa + pb, c - pa + pb]:
				st.add_vertex(v)
	return st.commit()
