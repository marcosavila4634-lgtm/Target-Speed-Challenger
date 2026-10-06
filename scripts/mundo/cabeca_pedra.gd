class_name CabecaPedra
extends Node3D
## Cabeça de pedra da serpente que morde a estrada (Serpent's Climb, armadilha "serpentes"; pedido do dono
## 2026-10-06), igual às artes dele (assets/MAPA SERPENTE/cabeçadepedra). A escultura em relevo é gerada por
## tools/serpents_climb/cabeca_pedra.gd (movel.res = tudo o que morde; base.res = maxilar de baixo); aqui ela
## é posta na estrada: o maxilar de baixo é um pedestal da mesma pedra que desce até o chão (pilares quando a
## pista é alta). A mordida é de mandíbula: só o focinho (com olhos, presas e o penacho) gira em volta do eixo
## dos discos (a junta da boca na arte) até a beira do céu da boca encostar na pista; nuca, discos, corredor e
## bochechas ficam parados (o topo das bochechas acompanha a parte de baixo do focinho: nada atravessa nada).
## Só o focinho e as presas matam.
## Local: origem no pé do focinho, no nível da pista; x = direita, y = cima, z = para quem chega.

const PASTA := "res://assets/selva/cabeca_pedra/"
const PILAR := 4.0

static var _movel: ArrayMesh
static var _base: ArrayMesh
static var _mat: ShaderMaterial

var k := 1.0                 # escala (a boca se ajusta à largura da estrada)
var aberta := 14.45          # beira do céu da boca, aberta (m acima da pista)
var olhos: Array = []        # materiais das lâmpadas dos olhos (verde/vermelho)
var _corpos: Array = []      # o que gira (focinho)
var _xf := Transform3D.IDENTITY


static func carregar() -> bool:
	if _movel:
		return true
	_movel = load(PASTA + "movel.res") as ArrayMesh
	_base = load(PASTA + "base.res") as ArrayMesh
	if _movel == null or _base == null:
		push_warning("CabecaPedra: falta movel.res/base.res (rodar tools/serpents_climb/cabeca_pedra.gd)")
		_movel = null
		return false
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/cabeca_pedra.gdshader")
	for n in ["frente", "lado", "interna", "pena", "presa", "pedra", "blocos"]:
		_mat.set_shader_parameter(n, _textura(n))
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


## Medidas na escala 1: [meia largura do túnel, meia largura do meio-fio, comprimento (até o fim do corredor),
## comprimento do teto (o que esmaga), céu da boca].
static func medidas() -> Array:
	if not carregar():
		return [6.0, 5.2, 32.0, 19.0, 12.0]
	return [float(_movel.get_meta("x_in")), float(_movel.get_meta("x_meio_fio")), -float(_movel.get_meta("z_fim")) + 1.0,
		-float(_movel.get_meta("z_foc")), float(_movel.get_meta("ceu"))]


## Monta em `xf` (sem escala) com a escala `escala`; `chao_y` = chão mais baixo embaixo do pedestal (mundo).
func montar(xf: Transform3D, escala: float, chao_y: float) -> void:
	if not carregar():
		return
	name = "CabecaPedra"
	_xf = xf
	transform = xf
	k = escala
	aberta = float(_movel.get_meta("labio")) * k
	var xb := float(_movel.get_meta("x_base"))
	var zf := float(_movel.get_meta("z_fim")) - 1.0
	var zl := float(_movel.get_meta("z_labio"))
	var yb := float(_movel.get_meta("y_base"))
	# ---- maxilar de baixo (parado) e o pedestal até o chão
	var base := MeshInstance3D.new()
	base.mesh = _base
	base.material_override = _mat
	base.scale = Vector3.ONE * k
	add_child(base)
	var fundo := -(aberta + 2.5)              # a cabeça fechada cabe inteira dentro do pedestal
	var ped := MeshInstance3D.new()
	ped.mesh = _caixa_malha(Vector3(xb * 2.0, yb - fundo / k, zl - zf) * k)
	ped.material_override = _mat
	ped.position = Vector3(0.0, (yb * k + fundo) * 0.5, (zl + zf) * 0.5 * k)
	add_child(ped)
	var parado := StaticBody3D.new()
	parado.collision_layer = 1
	parado.collision_mask = 0
	parado.add_to_group("estrutura")
	add_child(parado)
	var caixas: Array = []   # [centro, tamanho] na escala 1
	caixas.append([Vector3(0, (yb - 1.0) * 0.5, (zl + zf) * 0.5), Vector3(xb * 2.0, -1.0 - yb, zl - zf)])
	# Corredor, nuca, bloco de trás e discos (parados), bochechas pelo perfil
	var perfil: Array = _movel.get_meta("bochecha")
	for sx: float in [-1.0, 1.0]:
		for c: Array in [[Vector3(7.5, 4.5, -25.5), Vector3(3.0, 9.0, 13.0)], [Vector3(11.5, 11.8, -22.0), Vector3(5.0, 23.6, 6.0)],
				[Vector3(11.2, 4.5, -28.5), Vector3(4.4, 9.0, 7.0)], [Vector3(14.6, 5.0, -27.5), Vector3(2.4, 8.0, 8.0)]]:
			var pc: Vector3 = c[0]
			caixas.append([Vector3(pc.x * sx, pc.y, pc.z), c[1]])
		for q in range(0, perfil.size() - 1, 2):
			var a: Vector2 = perfil[q]
			var b: Vector2 = perfil[mini(q + 2, perfil.size() - 1)]
			var topo := minf(a.y, b.y)
			caixas.append([Vector3(sx * 9.5, topo * 0.5, (a.x + b.x) * 0.5), Vector3(7.0, topo, absf(b.x - a.x))])
		caixas.append([Vector3(sx * 12.2, (yb + 2.0) * 0.5, (zl - 11.0) * 0.5), Vector3(7.6, 2.0 - yb, zl + 11.0)])
		caixas.append([Vector3(sx * 12.2, (yb + 3.7) * 0.5, (-11.0 + zf) * 0.5), Vector3(7.6, 3.7 - yb, -11.0 - zf)])
		caixas.append([Vector3(sx * 6.8, (yb + 0.4) * 0.5, (-4.8 + zf) * 0.5), Vector3(3.2, 0.4 - yb, -4.8 - zf)])
		caixas.append([Vector3(sx * 6.8, (yb + 0.8) * 0.5, (-4.8 + zl) * 0.5), Vector3(3.2, 0.8 - yb, zl + 4.8)])
	for c: Array in caixas:
		_forma(parado, (c[0] as Vector3) * k, (c[1] as Vector3) * k)
	_forma(parado, ped.position, Vector3(xb * 2.0 * k, yb * k - fundo, (zl - zf) * k))
	# Pilares até o chão, quando o pedestal fica no ar
	var no_mundo := xf * Vector3(0.0, fundo, 0.0)
	var vao := no_mundo.y - chao_y
	if vao > 0.5:
		for px: float in [-xb + 2.5, 0.0, xb - 2.5]:
			for pz: float in [zl - 2.5, zf + 2.5]:
				var topo := Vector3(px * k, fundo, pz * k)
				var alto := vao + 2.0
				var pm := MeshInstance3D.new()
				pm.mesh = _caixa_malha(Vector3(PILAR, alto, PILAR))
				pm.material_override = _mat
				pm.position = topo - xf.basis.inverse() * Vector3.UP * alto * 0.5
				pm.basis = xf.basis.inverse() * Basis.IDENTITY   # de pé no mundo
				add_child(pm)
				_forma(parado, pm.position, Vector3(PILAR, alto, PILAR), pm.basis)
	# ---- a parte que morde: o focinho, girando nos discos
	var mortal := _corpo(true)
	var movel := mortal
	var vis := MeshInstance3D.new()
	vis.mesh = _movel
	vis.material_override = _mat
	vis.scale = Vector3.ONE * k
	movel.add_child(vis)
	# Mata: focinho, bloco de cima e as presas grandes
	for c: Array in [[Vector3(0, 18.95, -13.5), Vector3(20.6, 13.9, 11.0)], [Vector3(0, 19.55, -3.9), Vector3(20.6, 12.7, 8.2)],
			[Vector3(-5.0, 12.1, -1.0), Vector3(1.8, 4.6, 1.8)], [Vector3(5.0, 12.1, -1.0), Vector3(1.8, 4.6, 1.8)]]:
		_forma(mortal, (c[0] as Vector3) * k, (c[1] as Vector3) * k)
	# Olhos: lâmpadas de aviso (verdes: dá para passar; vermelhas: vai morder)
	for p: Vector3 in _movel.get_meta("olhos"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.1, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 1.0, 0.3)
		mat.emission_energy_multiplier = 6.0
		var esfera := SphereMesh.new()
		esfera.radius = 1.05 * k
		esfera.height = 2.1 * k
		var mi := MeshInstance3D.new()
		mi.mesh = esfera
		mi.material_override = mat
		mi.position = p * k
		movel.add_child(mi)
		olhos.append(mat)
	# Luz quente dentro do túnel (as lâmpadas da arte; a do fundo fica no corredor parado)
	for p: Vector3 in [Vector3(0, 9.5, -5.0), Vector3(0, 9.0, -14.0), Vector3(0, 7.0, -25.0)]:
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.62, 0.3)
		luz.light_energy = 2.2
		luz.omni_range = 15.0 * k
		luz.position = p * k
		(movel if p.z > -20.0 else self as Node).add_child(luz)
	animar(aberta)


func _corpo(mata: bool) -> AnimatableBody3D:
	var a := AnimatableBody3D.new()
	a.sync_to_physics = true
	a.collision_layer = 1
	a.collision_mask = 0
	a.add_to_group("estrutura")
	if mata:
		a.add_to_group("mortal")
	add_child(a)
	_corpos.append(a)
	return a


## Beira do céu da boca a `h` m da pista (aberta = `aberta`): o focinho gira em volta do eixo dos discos.
func animar(h: float) -> void:
	var pv: Vector2 = _movel.get_meta("pivo")   # (y, z)
	var dy := float(_movel.get_meta("labio")) - pv.x
	var dz := -pv.y
	var th := acos(clampf((h / k - pv.x) / Vector2(dy, dz).length(), -1.0, 1.0)) - atan2(dz, dy)
	var b := Basis(Vector3.RIGHT, maxf(th, 0.0))
	var piv := Vector3(0.0, pv.x, pv.y) * k
	for c: AnimatableBody3D in _corpos:
		c.transform = Transform3D(b, piv - b * piv)


static func _forma(corpo: Node, centro: Vector3, tam: Vector3, b := Basis.IDENTITY) -> void:
	var forma := BoxShape3D.new()
	forma.size = tam
	var cs := CollisionShape3D.new()
	cs.shape = forma
	cs.transform = Transform3D(b, centro)
	corpo.add_child(cs)


## Caixa com os blocos da arte em mosaico (COLOR.g = 7 no cabeca_pedra.gdshader), UV em metros.
static func _caixa_malha(tam: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.92, 0.75, 0.0))
	var h := tam * 0.5
	for eixo in 3:
		for s: float in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[eixo] = s
			var a := Vector3.ZERO
			a[(eixo + 1) % 3] = 1.0
			var b := n.cross(a)
			var c := n * h
			st.set_normal(n)
			var vs := [c - a * h - b * h, c + a * h - b * h, c + a * h + b * h, c - a * h + b * h]
			var uvs: Array[Vector2] = []
			for v: Vector3 in vs:
				uvs.append(Vector2(v.dot(a), v.dot(b)) / 5.0)
			for i: int in [0, 1, 2, 0, 2, 3]:
				st.set_uv(uvs[i])
				st.add_vertex(vs[i])
	return st.commit()
