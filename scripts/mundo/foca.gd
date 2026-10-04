extends RefCounted
## Foca-leopardo do Frozen Peak (armadilha "focas"), pela arte do dono em assets/frozen/extruturas/foca.png,
## e a geleira onde ela fica (plataforma de gelo para a foca.png). Tudo em geometria:
## - corpo inteiro numa malha lisa só, com ESQUELETO (Skeleton3D): cauda, quadril, lombo, peito, pescoço,
##   cabeça, mandíbula e as quatro nadadeiras. A pele deforma com os ossos (pedido do dono: "realista,
##   com movimentos"): respira, mexe a cauda e as nadadeiras de trás, olha em volta, levanta o peito e
##   joga a cabeça para trás antes de cuspir, e dá o bote com a boca escancarada ao cuspir;
## - cabeça grande e comprida de foca-leopardo, mandíbula articulada com a boca rosada por dentro,
##   presas, olhos pretos molhados, narinas e bigodes;
## - pele (foca.gdshader): cinza-chumbo nas costas, prata na barriga, pintas escuras, relevo fino e brilho
##   de pelo molhado; a textura fica presa à pele parada (CUSTOM0), não escorrega quando ela se mexe;
## - geleira: bloco de gelo saindo do chão até acima da pista (mesmo gelo do portão: PortaoGelo).
## Coordenadas da foca: cabeça para +Z, barriga em y = 0, ~3,6 m de comprimento.

const PORTAO := "res://scripts/mundo/portao_gelo.gd"

# Ossos: [nome, pai, posição de descanso (global, sem giro)]
const OSSOS := [
	["raiz", -1, Vector3(0.0, 0.35, -0.1)],
	["lombo", 0, Vector3(0.0, 0.45, 0.1)],
	["peito", 1, Vector3(0.0, 0.55, 0.55)],
	["pescoco", 2, Vector3(0.0, 0.72, 0.92)],
	["cabeca", 3, Vector3(0.0, 0.84, 1.2)],
	["queixo", 4, Vector3(0.0, 0.74, 1.2)],
	["quadril", 0, Vector3(0.0, 0.36, -0.55)],
	["cauda", 6, Vector3(0.0, 0.2, -1.15)],
	["nad_fe", 2, Vector3(-0.42, 0.47, 0.62)],
	["nad_fd", 2, Vector3(0.42, 0.47, 0.62)],
	["nad_te", 7, Vector3(-0.06, 0.13, -1.45)],
	["nad_td", 7, Vector3(0.06, 0.13, -1.45)],
]
# Espinha: [z, osso] (o peso de cada anel do corpo é dividido entre os dois ossos vizinhos)
const ESPINHA := [[-1.15, 7], [-0.55, 6], [0.1, 1], [0.55, 2], [0.92, 3], [1.2, 4]]
# Corpo: [z, y do centro, meia largura, meia altura, achatamento da barriga]
const CORPO := [
	[-1.66, 0.12, 0.02, 0.02, 1.0], [-1.5, 0.11, 0.12, 0.085, 0.9], [-1.3, 0.16, 0.26, 0.18, 0.85],
	[-0.95, 0.3, 0.48, 0.33, 0.85], [-0.5, 0.41, 0.64, 0.46, 0.85], [0.0, 0.47, 0.7, 0.52, 0.85],
	[0.45, 0.53, 0.66, 0.51, 0.85], [0.8, 0.66, 0.5, 0.43, 0.85], [1.02, 0.79, 0.38, 0.34, 0.8],
	[1.22, 0.88, 0.4, 0.32, 0.62], [1.42, 0.9, 0.37, 0.28, 0.5], [1.64, 0.875, 0.28, 0.19, 0.5],
	[1.83, 0.86, 0.19, 0.13, 0.6], [1.97, 0.85, 0.09, 0.08, 0.7],
]
const MANDIBULA := [[1.16, 0.72, 0.29, 0.075, 1.0], [1.4, 0.71, 0.27, 0.07, 1.0], [1.62, 0.72, 0.2, 0.06, 1.0], [1.8, 0.745, 0.12, 0.045, 1.0], [1.91, 0.76, 0.05, 0.03, 1.0]]
const BOCA := [[1.22, 0.765, 0.25, 0.05, 1.0], [1.5, 0.765, 0.23, 0.05, 1.0], [1.75, 0.775, 0.13, 0.04, 1.0], [1.86, 0.78, 0.06, 0.025, 1.0]]

static var _mats := {}
static var _modelo: Array = []   # [malha, textura original] da foca escaneada (carregada uma vez)

const MODELO := "res://assets/frozen/animais/foca/foca_escaneada.glb"
const ESCALA := 9.5      # o escaneamento tem 0,38 m
const BOCA_MODELO := Vector3(0.186, 0.146, 0.018)


## Foca escaneada (CC-BY Loïc Norgeot, ver creditos.txt na pasta): lida direto do .glb (GLTFDocument), sem
## depender da importação do editor. Vazio se o arquivo não está lá.
static func _carregar_modelo() -> Array:
	if not _modelo.is_empty():
		return _modelo
	var arq := ProjectSettings.globalize_path(MODELO)
	if not FileAccess.file_exists(arq):
		return []
	var doc := GLTFDocument.new()
	var estado := GLTFState.new()
	if doc.append_from_file(arq, estado) != OK:
		return []
	var cena := doc.generate_scene(estado)
	for no in cena.find_children("*", "MeshInstance3D", true, false):
		var mi := no as MeshInstance3D
		var mat := mi.get_active_material(0) as BaseMaterial3D
		_modelo = [mi.mesh, mat.albedo_texture if mat else null]
		break
	cena.free()
	return _modelo


## Foca pelo modelo escaneado: malha com a pele de foca e as dobras do vertex shader (foca_modelo.gdshader).
static func _criar_modelo(pai: Node3D, semente: int) -> Dictionary:
	var md := _carregar_modelo()
	if md.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var raiz := Node3D.new()
	raiz.name = "Foca"
	pai.add_child(raiz)
	var mi := MeshInstance3D.new()
	mi.mesh = md[0]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foca_modelo.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 517))
	if md[1]:
		mat.set_shader_parameter("original", md[1])
	mi.material_override = mat
	# Cabeça do modelo para +X: gira para +Z (o padrão das focas) e escala para ~3,6 m
	mi.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis.from_scale(Vector3.ONE * ESCALA), Vector3.ZERO)
	raiz.add_child(mi)
	var boca := Node3D.new()
	boca.name = "Boca"
	raiz.add_child(boca)
	return {"raiz": raiz, "malha": mi, "mat": mat, "boca": boca, "t": -1.0, "abre": 0.0, "bote": 0.0, "fase": rng.randf() * TAU}


static func _mat(nome: String) -> Material:
	if _mats.has(nome):
		return _mats[nome]
	var m: Material
	match nome:
		"pele", "boca":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/foca.gdshader")
			s.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 517))
			s.set_shader_parameter("boca", 1.0 if nome == "boca" else 0.0)
			m = s
		"olho":
			var e := StandardMaterial3D.new()
			e.albedo_color = Color(0.015, 0.012, 0.012)
			e.roughness = 0.02
			e.metallic_specular = 1.0
			e.clearcoat_enabled = true
			e.clearcoat_roughness = 0.0
			e.rim_enabled = true
			e.rim = 0.3
			m = e
		"dente":
			var d := StandardMaterial3D.new()
			d.albedo_color = Color(0.93, 0.9, 0.8)
			d.roughness = 0.25
			d.clearcoat_enabled = true
			m = d
		"bigode":
			var w := StandardMaterial3D.new()
			w.albedo_color = Color(0.85, 0.85, 0.8)
			w.roughness = 0.4
			m = w
		"narina":
			var n := StandardMaterial3D.new()
			n.albedo_color = Color(0.02, 0.02, 0.02)
			n.roughness = 0.6
			m = n
	_mats[nome] = m
	return m


## Monta a foca dentro de `pai`. Devolve {raiz, esq, boca, ossos (nome -> índice), t, abre, bote}.
static func criar(pai: Node3D, semente: int) -> Dictionary:
	var escaneada := _criar_modelo(pai, semente)
	if not escaneada.is_empty():
		return escaneada
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var raiz := Node3D.new()
	raiz.name = "Foca"
	pai.add_child(raiz)
	var esq := Skeleton3D.new()
	esq.name = "Esqueleto"
	raiz.add_child(esq)
	var ids := {}
	for k in OSSOS.size():
		var o: Array = OSSOS[k]
		esq.add_bone(o[0])
		ids[o[0]] = k
		if int(o[1]) >= 0:
			esq.set_bone_parent(k, int(o[1]))
		var pos_pai: Vector3 = OSSOS[int(o[1])][2] if int(o[1]) >= 0 else Vector3.ZERO
		esq.set_bone_rest(k, Transform3D(Basis.IDENTITY, (o[2] as Vector3) - pos_pai))
	esq.reset_bone_poses()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
	var esp_peso := func(p: Vector3) -> Array:
		var z := p.z
		if z <= float(ESPINHA[0][0]):
			return [[int(ESPINHA[0][1])], [1.0]]
		for k in ESPINHA.size() - 1:
			var z0 := float(ESPINHA[k][0])
			var z1 := float(ESPINHA[k + 1][0])
			if z <= z1:
				var u := smoothstep(z0, z1, z)
				return [[int(ESPINHA[k][1]), int(ESPINHA[k + 1][1])], [1.0 - u, u]]
		return [[4], [1.0]]
	_tubo(st, _secoes(CORPO, 7), 28, Vector3.RIGHT, esp_peso)
	# Nadadeiras da frente: do ombro até o chão, para a frente e para fora, a palma deitada no fim
	for s: float in [-1.0, 1.0]:
		var osso: int = ids["nad_fd" if s > 0.0 else "nad_fe"]
		var cam := [[Vector3(s * 0.36, 0.52, 0.6), 0.17, 0.09], [Vector3(s * 0.56, 0.32, 0.74), 0.16, 0.07],
			[Vector3(s * 0.68, 0.12, 0.9), 0.14, 0.045], [Vector3(s * 0.74, 0.04, 1.06), 0.11, 0.03], [Vector3(s * 0.76, 0.03, 1.16), 0.05, 0.02]]
		_tubo(st, _secoes_caminho(cam, 4), 14, Vector3.BACK, func(_p: Vector3) -> Array: return [[osso], [1.0]])
	# Nadadeiras de trás: leque deitado, apontando para trás
	for s: float in [-1.0, 1.0]:
		var osso: int = ids["nad_td" if s > 0.0 else "nad_te"]
		var cam := [[Vector3(s * 0.05, 0.13, -1.38), 0.1, 0.07], [Vector3(s * 0.15, 0.1, -1.55), 0.17, 0.045],
			[Vector3(s * 0.25, 0.08, -1.72), 0.26, 0.03], [Vector3(s * 0.3, 0.07, -1.8), 0.24, 0.025]]
		_tubo(st, _secoes_caminho(cam, 4), 14, Vector3.RIGHT, func(_p: Vector3) -> Array: return [[osso], [1.0]])
	# Mandíbula
	var q: int = ids["queixo"]
	_tubo(st, _secoes(MANDIBULA, 5), 20, Vector3.RIGHT, func(_p: Vector3) -> Array: return [[q], [1.0]])
	st.generate_normals()
	var pele := MeshInstance3D.new()
	pele.mesh = st.commit()
	pele.material_override = _mat("pele")
	esq.add_child(pele)
	pele.skeleton = NodePath("..")
	# Boca por dentro: metade presa na cabeça, metade na mandíbula (estica quando abre)
	var sb := SurfaceTool.new()
	sb.begin(Mesh.PRIMITIVE_TRIANGLES)
	sb.set_custom_format(0, SurfaceTool.CUSTOM_RGB_FLOAT)
	var cab: int = ids["cabeca"]
	_tubo(sb, _secoes(BOCA, 4), 16, Vector3.RIGHT, func(p: Vector3) -> Array:
		return [[cab, q], [1.0, 0.0] if p.y > 0.765 else [0.0, 1.0]])
	sb.generate_normals()
	var boca_mi := MeshInstance3D.new()
	boca_mi.mesh = sb.commit()
	boca_mi.material_override = _mat("boca")
	esq.add_child(boca_mi)
	boca_mi.skeleton = NodePath("..")

	# Peças presas na cabeça e na mandíbula
	var na_cabeca := _presa(esq, "cabeca")
	var no_queixo := _presa(esq, "queixo")
	var o_cab: Vector3 = OSSOS[cab][2]
	var o_q: Vector3 = OSSOS[q][2]
	var olho := SphereMesh.new()
	olho.radius = 0.052
	olho.height = 0.09
	var narina := SphereMesh.new()
	narina.radius = 0.016
	narina.height = 0.022
	var dente := CylinderMesh.new()
	dente.top_radius = 0.0
	dente.bottom_radius = 0.016
	dente.height = 0.075
	dente.radial_segments = 6
	dente.rings = 1
	for s: float in [-1.0, 1.0]:
		_peca(na_cabeca, olho, _mat("olho"), Transform3D(Basis.from_scale(Vector3(0.8, 1.0, 1.15)), Vector3(s * 0.255, 0.965, 1.37) - o_cab))
		_peca(na_cabeca, narina, _mat("narina"), Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.6)), Vector3(s * 0.035, 0.905, 1.95) - o_cab))
		# Presas: de cima para baixo na beira do focinho, de baixo para cima na mandíbula
		for k in 5:
			var z := lerpf(1.45, 1.86, k / 4.0)
			var x := s * (0.2 - k * 0.032)
			_peca(na_cabeca, dente, _mat("dente"), Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3.ONE * (1.4 if k == 3 else 1.0)), Vector3(x, 0.765, z) - o_cab))
			_peca(no_queixo, dente, _mat("dente"), Transform3D(Basis.IDENTITY, Vector3(x * 0.95, 0.775, z - 0.03) - o_q))
		# Bigodes: fios finos e compridos saindo dos dois lados do focinho
		for k in 9:
			var b := CylinderMesh.new()
			b.top_radius = 0.0015
			b.bottom_radius = 0.005
			b.height = rng.randf_range(0.22, 0.38)
			b.radial_segments = 4
			b.rings = 1
			var dir := Vector3(s, rng.randf_range(-0.45, 0.1), rng.randf_range(0.05, 0.55)).normalized()
			var base := Vector3(s * (0.11 - k * 0.004), 0.83 + 0.012 * (k % 3), 1.76 + 0.025 * (k / 3))
			var mi := _peca(na_cabeca, b, _mat("bigode"), Transform3D(Basis(Quaternion(Vector3.UP, dir)), base + dir * b.height * 0.5 - o_cab))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var boca := Node3D.new()
	boca.name = "Boca"
	boca.position = Vector3(0.0, 0.78, 1.96) - o_cab
	na_cabeca.add_child(boca)
	return {"raiz": raiz, "esq": esq, "boca": boca, "ossos": ids, "t": -1.0, "abre": 0.0, "bote": 0.0, "fase": rng.randf() * TAU}


static func _presa(esq: Skeleton3D, osso: String) -> BoneAttachment3D:
	var a := BoneAttachment3D.new()
	a.bone_name = osso
	esq.add_child(a)
	return a


static func _peca(pai: Node3D, malha: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.material_override = mat
	mi.transform = xf
	pai.add_child(mi)
	return mi


## Pose do quadro: `preparo` 0..1 = levanta o peito e joga a cabeça para trás antes do cuspe; `cuspindo` =
## bote para a frente com a boca escancarada. Fora disso respira, abana a cauda e olha em volta.
static func pose(f: Dictionary, t: float, preparo: float, cuspindo: bool) -> void:
	var dt := clampf(t - float(f.t), 0.0, 0.1) if float(f.t) >= 0.0 else 0.0
	f.t = t
	f.abre = move_toward(float(f.abre), 1.0 if cuspindo else 0.08 + 0.2 * preparo, dt * (7.0 if cuspindo else 2.5))
	f.bote = move_toward(float(f.bote), 1.0 if cuspindo else 0.0, dt * (6.0 if cuspindo else 1.6))
	if f.has("mat"):
		_pose_modelo(f, t, preparo)
		return
	var esq: Skeleton3D = f.esq
	var o: Dictionary = f.ossos
	var ph: float = t + float(f.fase)
	var resp := sin(ph * 1.7)
	var bote: float = f.bote
	var calma := (1.0 - preparo) * (1.0 - bote)
	var treme := sin(t * 38.0) * 0.03 * bote
	esq.set_bone_pose_scale(o.lombo, Vector3(1.0 + 0.025 * resp, 1.0 + 0.035 * resp, 1.0))
	esq.set_bone_pose_rotation(o.lombo, Quaternion(Vector3.UP, 0.05 * sin(ph * 0.6) * calma))
	# Peito: sobe apoiado nas nadadeiras no preparo, desce no bote
	esq.set_bone_pose_rotation(o.peito, Quaternion(Vector3.RIGHT, -0.22 * preparo + 0.02 * bote - 0.02 * resp))
	esq.set_bone_pose_rotation(o.pescoco, Quaternion(Vector3.UP, 0.22 * sin(ph * 0.45) * calma) * Quaternion(Vector3.RIGHT, -0.28 * preparo + 0.18 * bote + 0.04 * sin(ph * 0.9) * calma))
	esq.set_bone_pose_rotation(o.cabeca, Quaternion(Vector3.UP, 0.18 * sin(ph * 0.7 + 1.0) * calma + treme) * Quaternion(Vector3.RIGHT, -0.32 * preparo + 0.06 * bote + treme)
		* Quaternion(Vector3.BACK, 0.12 * sin(ph * 0.33) * calma))
	esq.set_bone_pose_rotation(o.queixo, Quaternion(Vector3.RIGHT, 0.04 + 0.72 * float(f.abre)))
	# Cauda e nadadeiras de trás abanando; nadadeiras da frente empurram no preparo
	esq.set_bone_pose_rotation(o.quadril, Quaternion(Vector3.UP, 0.08 * sin(ph * 1.1)))
	esq.set_bone_pose_rotation(o.cauda, Quaternion(Vector3.UP, 0.22 * sin(ph * 1.1 - 0.8)) * Quaternion(Vector3.RIGHT, -0.12 - 0.08 * sin(ph * 0.8) - 0.15 * preparo))
	for s: float in [-1.0, 1.0]:
		var nt: int = o.nad_td if s > 0.0 else o.nad_te
		esq.set_bone_pose_rotation(nt, Quaternion(Vector3.UP, s * (0.25 + 0.2 * sin(ph * 2.2 + s))) * Quaternion(Vector3.BACK, s * 0.1 * sin(ph * 1.6)))
		var nf: int = o.nad_fd if s > 0.0 else o.nad_fe
		esq.set_bone_pose_rotation(nf, Quaternion(Vector3.BACK, s * (0.1 * preparo - 0.05 * bote + 0.03 * resp)) * Quaternion(Vector3.UP, s * 0.06 * sin(ph * 0.5)))


## Foca escaneada: olha em volta e respira; no preparo levanta o peito e joga a cabeça para trás; no bote
## estica a cabeça para a frente e para baixo, tremendo. A boca (ponto de saída do cuspe) segue a cabeça.
static func _pose_modelo(f: Dictionary, t: float, preparo: float) -> void:
	var ph: float = t + float(f.fase)
	var bote: float = f.bote
	var calma := (1.0 - preparo) * (1.0 - bote)
	var treme := sin(t * 38.0) * 0.03 * bote
	var pitch := 0.06 * sin(ph * 0.8) * calma + 0.35 * preparo - 0.28 * bote + treme
	var yaw := 0.4 * sin(ph * 0.45) * calma + treme
	var peito := 0.03 * sin(ph * 1.7) * calma + 0.12 * preparo - 0.12 * bote
	var mat: ShaderMaterial = f.mat
	mat.set_shader_parameter("cab_pitch", pitch)
	mat.set_shader_parameter("cab_yaw", yaw)
	mat.set_shader_parameter("peito_pitch", peito)
	mat.set_shader_parameter("respira", 0.025 * sin(ph * 1.7))
	# Mesma conta do shader para a ponta do focinho (espaço do modelo), depois para o nó
	var rp := Basis(Vector3.BACK, peito)
	var piv := rp * Vector3(0.105, 0.085, 0.0)
	var b := rp * BOCA_MODELO
	b = piv + Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, pitch) * (b - piv)
	(f.boca as Node3D).position = (f.malha as MeshInstance3D).transform * b


# ------------------------------------------------------------------ malha com pesos

## Seções [z, y, w, h, barriga] interpoladas (curva suave) em `sub` passos por trecho, como caminho.
static func _secoes(lista: Array, sub: int) -> Array:
	var cam := []
	for s: Array in lista:
		cam.append([Vector3(0.0, float(s[1]), float(s[0])), float(s[2]), float(s[3]), float(s[4])])
	return _secoes_caminho(cam, sub)


## Caminho [[centro, w, h, (barriga)], ...] interpolado por Catmull-Rom.
static func _secoes_caminho(cam: Array, sub: int) -> Array:
	var out := []
	var n := cam.size()
	for i in n - 1:
		var p0: Array = cam[maxi(i - 1, 0)]
		var p1: Array = cam[i]
		var p2: Array = cam[i + 1]
		var p3: Array = cam[mini(i + 2, n - 1)]
		var passos := sub if i < n - 2 else sub + 1
		for k in passos:
			var u := float(k) / sub
			var c := (p1[0] as Vector3).cubic_interpolate(p2[0], p0[0], p3[0], u)
			var w := cubic_interpolate(float(p1[1]), float(p2[1]), float(p0[1]), float(p3[1]), u)
			var h := cubic_interpolate(float(p1[2]), float(p2[2]), float(p0[2]), float(p3[2]), u)
			var b := lerpf(float(p1[3]) if p1.size() > 3 else 1.0, float(p2[3]) if p2.size() > 3 else 1.0, u)
			out.append([c, maxf(w, 0.005), maxf(h, 0.005), b])
	return out


## Tubo indexado e liso pelos anéis (seção elíptica, barriga achatada), pontas fechadas. `largo` = direção
## da largura do anel; `peso.call(p)` = [[ossos], [pesos]].
static func _tubo(st: SurfaceTool, aneis: Array, n: int, largo: Vector3, peso: Callable) -> void:
	var base := _contar(st)
	var pos: Array[Vector3] = []
	var centros: Array[Vector3] = []
	for i in aneis.size():
		var c: Vector3 = aneis[i][0]
		var t := ((aneis[mini(i + 1, aneis.size() - 1)][0] as Vector3) - (aneis[maxi(i - 1, 0)][0] as Vector3)).normalized()
		var e1 := (largo - t * largo.dot(t)).normalized()
		var e2 := t.cross(e1).normalized()
		if e2.y < 0.0 and absf(e2.y) > 0.2:
			e2 = -e2
		centros.append(c)
		for k in n:
			var a := TAU * float(k) / n
			var h: float = float(aneis[i][2]) * (float(aneis[i][3]) if sin(a) < 0.0 else 1.0)
			var p := c + e1 * cos(a) * float(aneis[i][1]) + e2 * sin(a) * h
			_vertice(st, p, peso)
			pos.append(p)
	for i in aneis.size() - 1:
		for k in n:
			var k2 := (k + 1) % n
			var a := i * n + k
			var b := i * n + k2
			var c := (i + 1) * n + k2
			var d := (i + 1) * n + k
			var meio := (centros[i] + centros[i + 1]) * 0.5
			_tri(st, pos, base, a, b, c, meio)
			_tri(st, pos, base, a, c, d, meio)
	# Pontas: um vértice no centro de cada ponta
	for ponta: int in [0, aneis.size() - 1]:
		var outro: int = 1 if ponta == 0 else aneis.size() - 2
		var dir := (centros[ponta] - centros[outro]).normalized()
		var tampa := centros[ponta] + dir * minf(float(aneis[ponta][1]), float(aneis[ponta][2])) * 0.5
		_vertice(st, tampa, peso)
		pos.append(tampa)
		var ic := pos.size() - 1
		for k in n:
			_tri(st, pos, base, ponta * n + k, ponta * n + (k + 1) % n, ic, centros[ponta] - dir)


static func _contar(st: SurfaceTool) -> int:
	return st.get_meta("n", 0)


static func _vertice(st: SurfaceTool, p: Vector3, peso: Callable) -> void:
	var r: Array = peso.call(p)
	var ossos := PackedInt32Array([0, 0, 0, 0])
	var pesos := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for j in (r[0] as Array).size():
		ossos[j] = int(r[0][j])
		pesos[j] = float(r[1][j])
	st.set_bones(ossos)
	st.set_weights(pesos)
	st.set_custom(0, Color(p.x, p.y, p.z))
	st.add_vertex(p)
	st.set_meta("n", int(st.get_meta("n", 0)) + 1)


## Triângulo por índices, virado para fora de `dentro` (Godot: frente em sentido horário).
static func _tri(st: SurfaceTool, pos: Array[Vector3], base: int, a: int, b: int, c: int, dentro: Vector3) -> void:
	var n := (pos[b] - pos[a]).cross(pos[c] - pos[a])
	if n.length_squared() < 1e-14:
		return
	if n.dot((pos[a] + pos[b] + pos[c]) / 3.0 - dentro) < 0.0:
		var t := b
		b = c
		c = t
	st.add_index(base + a)
	st.add_index(base + c)
	st.add_index(base + b)


# ------------------------------------------------------------------ geleira

## Geleira em `pai` (local: +Z = para a estrada, topo em y = `topo`, chão em y = `chao`). Devolve as
## caixas de colisão (no espaço de `pai`).
static func geleira(pai: Node3D, chao: float, topo: float, semente: int) -> Array[Transform3D]:
	var geo: Node3D = load(PORTAO).new()
	(geo.get("_rng") as RandomNumberGenerator).seed = semente
	var st_c: SurfaceTool = geo.get("_st_cristal")
	var st_n: SurfaceTool = geo.get("_st_neve")
	st_c.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_n.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng: RandomNumberGenerator = geo.get("_rng")
	var pe := chao - 0.8
	var col: Array[Transform3D] = []
	# Bloco principal, aba na frente (passa por cima do pé, como na arte) e degraus atrás
	geo.call("_caixa_cristal", Vector3(0.0, pe, -0.2), 2.9, 2.3, topo - pe)
	geo.call("_caixa_cristal", Vector3(0.0, topo - 2.4, 1.5), 2.7, 1.25, 2.4)
	geo.call("_caixa_cristal", Vector3(-1.6, pe, -1.9), 1.7, 1.4, topo - pe - 1.3)
	geo.call("_caixa_cristal", Vector3(1.7, pe, -1.6), 1.5, 1.5, topo - pe - 2.2)
	geo.call("_caixa_cristal", Vector3(rng.randf_range(-0.5, 0.5), pe, 1.0), 2.3, 1.1, topo - pe - 3.0)
	# Lascas grandes encostadas nos lados (a geleira da arte é toda quebrada em blocos)
	for k in 4:
		var sx := -1.0 if k % 2 == 0 else 1.0
		geo.call("_caixa_cristal", Vector3(sx * rng.randf_range(2.4, 3.0), pe, rng.randf_range(-2.2, 1.4)), rng.randf_range(0.8, 1.3), rng.randf_range(0.8, 1.3), topo - pe - rng.randf_range(0.8, 3.2))
	col.append(Transform3D(Basis.from_scale(Vector3(5.8, topo - pe, 5.6)), Vector3(0.0, (topo + pe) * 0.5, -0.2)))
	col.append(Transform3D(Basis.from_scale(Vector3(5.4, 2.4, 2.6)), Vector3(0.0, topo - 1.2, 1.5)))
	# Neve em cima e nos degraus, pingentes embaixo da aba
	geo.call("_almofada", Vector3(0.0, topo, 0.35), 2.85, 2.75, 0.55)
	geo.call("_almofada", Vector3(-1.6, topo - 1.3, -1.9), 1.75, 1.45, 0.6)
	geo.call("_almofada", Vector3(1.7, topo - 2.2, -1.6), 1.55, 1.55, 0.6)
	var x := -2.5
	while x < 2.5:
		x += rng.randf_range(0.18, 0.4)
		var l := rng.randf_range(0.3, 1.3) if rng.randf() < 0.8 else rng.randf_range(1.6, 2.6)
		geo.call("_pingente", Vector3(x, topo - 2.35, 2.65 + rng.randf_range(-0.1, 0.1)), l, 0.07 + l * 0.03)
	# Lascas e neve amontoada no pé
	for k in 6:
		var a := rng.randf() * TAU
		var p := Vector3(cos(a) * 3.2, chao - 0.2, sin(a) * 3.0 - 0.2)
		var h := rng.randf_range(1.0, 2.6)
		geo.call("_prisma", st_c, p, (Vector3(cos(a), 2.5, sin(a))).normalized(), 5, [Vector2(0.0, h * 0.22)], h, 0.15, Vector2.ONE)
		geo.call("_prisma", st_n, p + Vector3(cos(a), 0.0, sin(a)) * 0.6, Vector3.UP, 12,
			[Vector2(0.0, rng.randf_range(1.2, 2.0)), Vector2(0.35, 1.0), Vector2(0.6, 0.5)], 0.1, 0.08, Vector2(1.0, 0.7), true, true)
	var portao = load(PORTAO)
	for par: Array in [[st_c, portao._material("geleira")], [st_n, Gelo.material(Gelo.Mat.NEVE)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (par[0] as SurfaceTool).commit()
		mi.material_override = par[1]
		pai.add_child(mi)
	geo.free()
	return col
