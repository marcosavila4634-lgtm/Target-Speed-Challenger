extends RefCounted
## Yeti do Frozen Peak (armadilha "yetis"): bicho grande e peludo, curvado, braços compridos de gorila.
## Malha lisa só, com esqueleto (quadril, tronco, peito, cabeça, braços, antebraços, coxas, canelas) — a
## pele deforma com os ossos — e tufos de pelo presos nos ombros, na cabeça e nos braços. Pelo branco
## com sombra azulada e mechas em relevo; cara, mãos e pés de couro cinza-azulado; olhos e boca escuros.
## pose(): parado (respira, balança, bate no peito de vez em quando), salto (braços para cima, pernas
## encolhidas) e agarrado (deitado no teto do carro, braços abertos segurando as laterais, pernas
## balançando atrás, socando o teto).
## Coordenadas: de pé, olhando para +Z, pés em y = 0, ~2,6 m.

const FOCA := preload("res://scripts/mundo/foca.gd")

const OSSOS := [
	["quadril", -1, Vector3(0.0, 1.05, 0.0)],
	["tronco", 0, Vector3(0.0, 1.45, 0.02)],
	["peito", 1, Vector3(0.0, 1.9, 0.08)],
	["cabeca", 2, Vector3(0.0, 2.3, 0.2)],
	["braco_e", 2, Vector3(-0.62, 2.02, 0.08)],
	["antebraco_e", 4, Vector3(-0.8, 1.42, 0.18)],
	["braco_d", 2, Vector3(0.62, 2.02, 0.08)],
	["antebraco_d", 6, Vector3(0.8, 1.42, 0.18)],
	["coxa_e", 0, Vector3(-0.3, 1.0, 0.0)],
	["canela_e", 8, Vector3(-0.33, 0.52, 0.04)],
	["coxa_d", 0, Vector3(0.3, 1.0, 0.0)],
	["canela_d", 10, Vector3(0.33, 0.52, 0.04)],
]
# Tronco de baixo para cima: [y, z, meia largura, meia profundidade]
const TRONCO := [[0.78, 0.0, 0.3, 0.26], [0.95, 0.0, 0.44, 0.34], [1.25, 0.02, 0.5, 0.38], [1.6, 0.05, 0.6, 0.43],
	[1.9, 0.07, 0.7, 0.46], [2.1, 0.06, 0.6, 0.42], [2.22, 0.08, 0.38, 0.32], [2.3, 0.12, 0.2, 0.2]]

static var _mats := {}
static var _modelo: Array = []   # [[malha, transformação, material], ...] do yeti pronto (CC-BY sudo-self)

const MODELO := "res://assets/frozen/animais/yeti/yeti_modelo.glb"
const ALTURA := 2.6


## Yeti pronto (assets/frozen/animais/yeti/yeti_modelo.glb, ver creditos.txt): lido direto do .glb. Sem
## esqueleto: a animação é do corpo inteiro (pose). Vazio se o arquivo não está lá.
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
	var pecas := []
	var lo := INF
	var hi := -INF
	for no in cena.find_children("*", "MeshInstance3D", true, false):
		var mi := no as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n and n != cena:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		# Só a escala do nó: o arquivo vem girado 20° em volta de Y (o yeti ficava torto); a malha já olha +Z
		xf = Transform3D(Basis.from_scale(xf.basis.get_scale()), Vector3.ZERO)
		var ab := xf * mi.mesh.get_aabb()
		lo = minf(lo, ab.position.y)
		hi = maxf(hi, ab.end.y)
		var mat := mi.get_active_material(0) as BaseMaterial3D
		pecas.append([mi.mesh, xf, mat.albedo_texture if mat else null, mat.normal_texture if mat and mat.normal_enabled else null])
	cena.free()
	# Pés em y = 0 e ALTURA de altura
	var esc := ALTURA / maxf(hi - lo, 0.01)
	for p: Array in pecas:
		p[1] = Transform3D(Basis.from_scale(Vector3.ONE * esc), Vector3(0.0, -lo * esc, 0.0)) * (p[1] as Transform3D)
	_modelo = pecas
	return _modelo


static func _mat(nome: String) -> Material:
	if _mats.has(nome):
		return _mats[nome]
	var m: Material
	match nome:
		"pelo", "tufo":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/yeti.gdshader")
			s.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 619))
			s.set_shader_parameter("tufo", 1.0 if nome == "tufo" else 0.0)
			m = s
		"olho":
			var e := StandardMaterial3D.new()
			e.albedo_color = Color(0.02, 0.03, 0.05)
			e.emission_enabled = true
			e.emission = Color(0.25, 0.7, 1.0)
			e.emission_energy_multiplier = 1.5
			e.roughness = 0.05
			m = e
		"boca":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.12, 0.04, 0.06)
			b.roughness = 0.4
			m = b
		"dente":
			var d := StandardMaterial3D.new()
			d.albedo_color = Color(0.92, 0.9, 0.82)
			d.roughness = 0.3
			m = d
	_mats[nome] = m
	return m


static func criar(pai: Node3D, semente: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var md := _carregar_modelo()
	if not md.is_empty():
		var r := Node3D.new()
		r.name = "Yeti"
		pai.add_child(r)
		var corpo := Node3D.new()
		r.add_child(corpo)
		var mats := []
		for p: Array in md:
			var mi := MeshInstance3D.new()
			mi.mesh = p[0]
			mi.transform = p[1]
			# Material próprio por yeti: braços e pernas dobram no shader (cada um com a sua pose)
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/yeti_modelo.gdshader")
			sm.set_shader_parameter("tex_cor", p[2])
			if p[3]:
				sm.set_shader_parameter("tex_normal", p[3])
				sm.set_shader_parameter("tem_normal", true)
			mi.material_override = sm
			corpo.add_child(mi)
			mats.append(sm)
		return {"raiz": r, "corpo": corpo, "mats": mats, "esc": (md[0][1] as Transform3D).basis.get_scale().y, "fase": rng.randf() * TAU}
	var raiz := Node3D.new()
	raiz.name = "Yeti"
	pai.add_child(raiz)
	var esq := Skeleton3D.new()
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
	# Tronco: peso dividido entre quadril, tronco e peito pela altura
	var cam := []
	for s: Array in TRONCO:
		cam.append([Vector3(0.0, float(s[0]), float(s[1])), float(s[2]), float(s[3]), 1.0])
	var i_q: int = ids.quadril
	var i_t: int = ids.tronco
	var i_p: int = ids.peito
	var i_c: int = ids.cabeca
	FOCA._tubo(st, FOCA._secoes_caminho(cam, 5), 24, Vector3.RIGHT, func(p: Vector3) -> Array:
		if p.y < 1.25:
			var u := smoothstep(1.0, 1.25, p.y)
			return [[i_q, i_t], [1.0 - u, u]]
		if p.y < 1.9:
			var u := smoothstep(1.5, 1.85, p.y)
			return [[i_t, i_p], [1.0 - u, u]]
		var u := smoothstep(2.15, 2.3, p.y)
		return [[i_p, i_c], [1.0 - u, u]])
	# Cabeça: do alto das costas para a frente (crânio alto, testa, focinho achatado)
	var cab := [[Vector3(0.0, 2.36, 0.0), 0.24, 0.27, 0.9], [Vector3(0.0, 2.4, 0.2), 0.28, 0.3, 0.85], [Vector3(0.0, 2.36, 0.38), 0.26, 0.26, 0.85],
		[Vector3(0.0, 2.3, 0.5), 0.2, 0.19, 0.9], [Vector3(0.0, 2.27, 0.56), 0.12, 0.12, 1.0]]
	FOCA._tubo(st, FOCA._secoes_caminho(cab, 4), 20, Vector3.RIGHT, func(_p: Vector3) -> Array: return [[i_c], [1.0]])
	# Braços compridos (até perto do chão) e pernas curtas e grossas
	for s: float in [-1.0, 1.0]:
		var ib: int = ids["braco_d" if s > 0.0 else "braco_e"]
		var ia: int = ids["antebraco_d" if s > 0.0 else "antebraco_e"]
		var braco := [[Vector3(s * 0.5, 2.06, 0.06), 0.24, 0.24], [Vector3(s * 0.66, 1.85, 0.1), 0.23, 0.22], [Vector3(s * 0.8, 1.42, 0.18), 0.19, 0.18],
			[Vector3(s * 0.84, 1.0, 0.26), 0.17, 0.16], [Vector3(s * 0.86, 0.72, 0.3), 0.2, 0.15], [Vector3(s * 0.86, 0.56, 0.33), 0.16, 0.12], [Vector3(s * 0.85, 0.48, 0.34), 0.08, 0.07]]
		FOCA._tubo(st, FOCA._secoes_caminho(braco, 4), 16, Vector3.BACK, func(p: Vector3) -> Array:
			var u := smoothstep(1.62, 1.28, p.y)
			return [[ib, ia], [1.0 - u, u]])
		var ic: int = ids["coxa_d" if s > 0.0 else "coxa_e"]
		var ik: int = ids["canela_d" if s > 0.0 else "canela_e"]
		var perna := [[Vector3(s * 0.27, 1.08, 0.0), 0.27, 0.27], [Vector3(s * 0.31, 0.78, 0.02), 0.25, 0.25], [Vector3(s * 0.33, 0.5, 0.04), 0.2, 0.2],
			[Vector3(s * 0.34, 0.2, 0.06), 0.19, 0.19], [Vector3(s * 0.34, 0.07, 0.16), 0.17, 0.1], [Vector3(s * 0.34, 0.05, 0.36), 0.15, 0.06], [Vector3(s * 0.34, 0.05, 0.42), 0.08, 0.04]]
		FOCA._tubo(st, FOCA._secoes_caminho(perna, 4), 16, Vector3.RIGHT, func(p: Vector3) -> Array:
			var u := smoothstep(0.75, 0.45, p.y)
			return [[ic, ik], [1.0 - u, u]])
	st.generate_normals()
	var pele := MeshInstance3D.new()
	pele.mesh = st.commit()
	pele.material_override = _mat("pelo")
	esq.add_child(pele)
	pele.skeleton = NodePath("..")
	# Tufos de pelo (mechas pontudas) presos nos ossos: ombros, nuca, cabeça, braços, costas
	var tufo := CylinderMesh.new()
	tufo.top_radius = 0.0
	tufo.bottom_radius = 0.09
	tufo.height = 0.32
	tufo.radial_segments = 5
	tufo.rings = 1
	for osso: String in ["peito", "cabeca", "braco_e", "braco_d", "antebraco_e", "antebraco_d", "tronco", "coxa_e", "coxa_d"]:
		var a := BoneAttachment3D.new()
		a.bone_name = osso
		esq.add_child(a)
		var o: Vector3 = OSSOS[ids[osso]][2]
		var xfs: Array = []
		var qtd := 26 if osso in ["peito", "cabeca"] else 14
		for k in qtd:
			# Ponto na superfície aproximada em volta do osso, mecha apontando para fora e para baixo
			var ang := rng.randf() * TAU
			var dir := Vector3(cos(ang), rng.randf_range(-0.6, 0.8), sin(ang)).normalized()
			var r := 0.5 if osso == "peito" else (0.27 if osso == "cabeca" else (0.38 if osso == "tronco" else 0.2))
			if osso == "cabeca" and dir.z > 0.5:
				continue   # a cara fica limpa
			var pos := dir * r * Vector3(1.0, 0.9 if osso != "peito" else 0.5, 0.85) + (Vector3(0, 0.08, 0.15) if osso == "cabeca" else Vector3.ZERO)
			var aponta := (dir + Vector3.DOWN * 0.9).normalized()
			var esc := rng.randf_range(0.7, 1.4)
			xfs.append(Transform3D(Basis(Quaternion(Vector3.UP, aponta)) * Basis.from_scale(Vector3(esc, esc * rng.randf_range(0.8, 1.5), esc)), pos + aponta * 0.12))
		Gelo._instancias(a, tufo, xfs, _mat("tufo"), true)
		ids["_at_" + osso] = a
	# Cara: olhos fundos com brilho azul, boca larga com presas
	var na_cab: BoneAttachment3D = ids["_at_cabeca"]
	var o_c: Vector3 = OSSOS[i_c][2]
	var olho := SphereMesh.new()
	olho.radius = 0.035
	olho.height = 0.06
	var dente := CylinderMesh.new()
	dente.top_radius = 0.0
	dente.bottom_radius = 0.022
	dente.height = 0.09
	dente.radial_segments = 6
	dente.rings = 1
	for s: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = olho
		mi.material_override = _mat("olho")
		mi.position = Vector3(s * 0.1, 2.45, 0.49) - o_c
		na_cab.add_child(mi)
		var d := MeshInstance3D.new()
		d.mesh = dente
		d.material_override = _mat("dente")
		d.transform = Transform3D(Basis(Vector3.RIGHT, PI), Vector3(s * 0.07, 2.25, 0.55) - o_c)
		na_cab.add_child(d)
	var boca := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.2, 0.05, 0.05)
	boca.mesh = bm
	boca.material_override = _mat("boca")
	boca.position = Vector3(0.0, 2.27, 0.555) - o_c
	na_cab.add_child(boca)
	return {"raiz": raiz, "esq": esq, "ossos": ids, "fase": rng.randf() * TAU}


## modo: "parado", "salto" (u 0..1 do pulo) ou "agarrado" (balanço do carro em `ginga`).
static func pose(y: Dictionary, t: float, modo: String, u := 0.0, ginga := 0.0) -> void:
	if y.has("corpo"):
		_pose_modelo(y, t, modo, u, ginga)
		return
	var esq: Skeleton3D = y.esq
	var o: Dictionary = y.ossos
	var ph: float = t + float(y.fase)
	var resp := sin(ph * 1.4)
	var q := func(eixo: Vector3, ang: float) -> Quaternion: return Quaternion(eixo, ang)
	match modo:
		"parado":
			# Curvado, olhando a estrada; de vez em quando bate no peito
			var bate := clampf(sin(ph * 0.35) * 4.0 - 3.0, 0.0, 1.0)
			esq.set_bone_pose_rotation(o.quadril, q.call(Vector3.UP, 0.08 * sin(ph * 0.5)))
			esq.set_bone_pose_rotation(o.tronco, q.call(Vector3.RIGHT, 0.22 + 0.03 * resp))
			esq.set_bone_pose_rotation(o.peito, q.call(Vector3.RIGHT, 0.12 - 0.15 * bate) * q.call(Vector3.BACK, 0.04 * sin(ph * 0.7)))
			esq.set_bone_pose_rotation(o.cabeca, q.call(Vector3.UP, 0.35 * sin(ph * 0.4)) * q.call(Vector3.RIGHT, -0.3 + 0.05 * resp - 0.25 * bate))
			for s: float in [-1.0, 1.0]:
				var soco := bate * (0.5 + 0.5 * sin(ph * 12.0 + (0.0 if s > 0.0 else PI)))
				esq.set_bone_pose_rotation(o["braco_d" if s > 0.0 else "braco_e"], q.call(Vector3.RIGHT, -0.15 - 1.1 * soco) * q.call(Vector3.BACK, s * (0.12 + 0.04 * resp) - s * 0.4 * soco))
				esq.set_bone_pose_rotation(o["antebraco_d" if s > 0.0 else "antebraco_e"], q.call(Vector3.RIGHT, -0.2 - 1.2 * soco))
				esq.set_bone_pose_rotation(o["coxa_d" if s > 0.0 else "coxa_e"], q.call(Vector3.RIGHT, -0.45))
				esq.set_bone_pose_rotation(o["canela_d" if s > 0.0 else "canela_e"], q.call(Vector3.RIGHT, 0.6))
		"salto":
			var abre := sin(u * PI)
			esq.set_bone_pose_rotation(o.quadril, Quaternion.IDENTITY)
			esq.set_bone_pose_rotation(o.tronco, q.call(Vector3.RIGHT, 0.4 * abre))
			esq.set_bone_pose_rotation(o.peito, q.call(Vector3.RIGHT, 0.2 * abre))
			esq.set_bone_pose_rotation(o.cabeca, q.call(Vector3.RIGHT, -0.4))
			for s: float in [-1.0, 1.0]:
				esq.set_bone_pose_rotation(o["braco_d" if s > 0.0 else "braco_e"], q.call(Vector3.RIGHT, -2.6 * abre) * q.call(Vector3.BACK, s * 0.5))
				esq.set_bone_pose_rotation(o["antebraco_d" if s > 0.0 else "antebraco_e"], q.call(Vector3.RIGHT, -0.4))
				esq.set_bone_pose_rotation(o["coxa_d" if s > 0.0 else "coxa_e"], q.call(Vector3.RIGHT, -1.1 * abre))
				esq.set_bone_pose_rotation(o["canela_d" if s > 0.0 else "canela_e"], q.call(Vector3.RIGHT, 1.4 * abre))
		"arremesso":
			# Braço direito vai para trás (u até 1) com a bola e joga por cima do ombro
			esq.set_bone_pose_rotation(o.tronco, q.call(Vector3.RIGHT, 0.15) * q.call(Vector3.UP, -0.4 * u))
			esq.set_bone_pose_rotation(o.peito, q.call(Vector3.RIGHT, -0.1 * u))
			esq.set_bone_pose_rotation(o.cabeca, q.call(Vector3.RIGHT, -0.2))
			esq.set_bone_pose_rotation(o.braco_d, q.call(Vector3.RIGHT, -2.8 * u) * q.call(Vector3.BACK, 0.3))
			esq.set_bone_pose_rotation(o.antebraco_d, q.call(Vector3.RIGHT, -0.8 * u))
			esq.set_bone_pose_rotation(o.braco_e, q.call(Vector3.RIGHT, -0.6) * q.call(Vector3.BACK, -0.3))
			esq.set_bone_pose_rotation(o.antebraco_e, q.call(Vector3.RIGHT, -0.3))
			for s: float in [-1.0, 1.0]:
				esq.set_bone_pose_rotation(o["coxa_d" if s > 0.0 else "coxa_e"], q.call(Vector3.RIGHT, -0.4))
				esq.set_bone_pose_rotation(o["canela_d" if s > 0.0 else "canela_e"], q.call(Vector3.RIGHT, 0.5))
		"agarrado":
			# Deitado de bruços no teto (o nó já vem inclinado), braços abertos descendo pelas laterais,
			# pernas balançando para trás, socando o teto e urrando
			var soco := 0.5 + 0.5 * sin(ph * 9.0)
			esq.set_bone_pose_rotation(o.quadril, q.call(Vector3.UP, 0.15 * ginga))
			esq.set_bone_pose_rotation(o.tronco, q.call(Vector3.RIGHT, 0.05) * q.call(Vector3.BACK, 0.1 * ginga))
			esq.set_bone_pose_rotation(o.peito, q.call(Vector3.RIGHT, -0.15 + 0.06 * soco))
			esq.set_bone_pose_rotation(o.cabeca, q.call(Vector3.RIGHT, -0.9 + 0.2 * sin(ph * 6.0)) * q.call(Vector3.UP, 0.3 * sin(ph * 2.3)))
			for s: float in [-1.0, 1.0]:
				var lado_soco := soco if s > 0.0 else 1.0 - soco
				esq.set_bone_pose_rotation(o["braco_d" if s > 0.0 else "braco_e"], q.call(Vector3.BACK, s * (1.2 - 0.25 * lado_soco)) * q.call(Vector3.RIGHT, -0.5))
				esq.set_bone_pose_rotation(o["antebraco_d" if s > 0.0 else "antebraco_e"], q.call(Vector3.BACK, -s * (0.9 + 0.3 * lado_soco)))
				var chute := sin(ph * 5.0 + (0.0 if s > 0.0 else PI))
				esq.set_bone_pose_rotation(o["coxa_d" if s > 0.0 else "coxa_e"], q.call(Vector3.RIGHT, 0.3 + 0.35 * chute - 0.3 * ginga * s))
				esq.set_bone_pose_rotation(o["canela_d" if s > 0.0 else "canela_e"], q.call(Vector3.RIGHT, 0.5 + 0.4 * chute))


## Yeti pronto: o corpo inteiro respira, balança e se inclina, e o shader (yeti_modelo.gdshader) dobra ombros,
## cotovelos, mãos e quadris. Ângulos dos braços: [para a frente, para fora, cotovelo]; braco_e = lado +X
## da malha (mão esquerda do yeti), braco_d = mão direita.
## - parado: braços soltos balançando; de vez em quando bate no peito, um punho de cada vez, pulando;
## - salto: braços para cima e para fora, pernas encolhidas;
## - arremesso: a mão direita vai para trás por cima do ombro (u até 1) e o corpo torce;
## - agarrado: deitado de bruços no teto (o nó já vem deitado), braços abertos por cima do teto e os
##   antebraços descendo pelas laterais com as mãos fechadas na lataria; os braços puxam e soltam um de
##   cada vez (escorrega e se segura) e acompanham o balanço da curva; as pernas pendem e chutam.
static func _pose_modelo(y: Dictionary, t: float, modo: String, u: float, ginga: float) -> void:
	var c: Node3D = y.corpo
	var ph: float = t + float(y.fase)
	var resp := sin(ph * 1.4)
	var be := Vector3.ZERO
	var bd := Vector3.ZERO
	var pe := Vector2.ZERO
	var maos := 0.3
	match modo:
		"parado":
			var bate := clampf(sin(ph * 0.35) * 4.0 - 3.0, 0.0, 1.0)
			var soco_e := 0.5 + 0.5 * sin(ph * 10.0)
			c.position = Vector3(0.0, absf(sin(ph * 10.0)) * 0.12 * bate, 0.0)
			c.basis = Basis(Vector3.UP, 0.4 * sin(ph * 0.4)) * Basis(Vector3.RIGHT, 0.08 + 0.03 * resp - 0.1 * bate) 				* Basis.from_scale(Vector3(1.0 + 0.02 * resp, 1.0 - 0.015 * resp, 1.0 + 0.02 * resp))
			var solto := Vector3(0.12 * sin(ph * 0.9), 0.08 + 0.04 * resp, 0.15)
			be = solto.lerp(Vector3(1.1 + 0.35 * soco_e, -0.35, 1.6), bate)
			bd = Vector3(0.12 * sin(ph * 0.9 + 1.3), 0.08 + 0.04 * resp, 0.15).lerp(Vector3(1.1 + 0.35 * (1.0 - soco_e), -0.35, 1.6), bate)
			maos = 0.3 + 0.7 * bate
		"salto":
			var e := sin(u * PI)
			c.position = Vector3.ZERO
			c.basis = Basis(Vector3.RIGHT, 0.4 * e) * Basis.from_scale(Vector3(1.0 + 0.05 * e, 1.0 - 0.1 * e, 1.0 + 0.05 * e))
			be = Vector3(2.3 * e, 0.7 * e, 0.4)
			bd = be
			pe = Vector2(1.0, 1.0) * 1.0 * e
			maos = 0.0
		"arremesso":
			c.position = Vector3.ZERO
			c.basis = Basis(Vector3.UP, -0.5 * u) * Basis(Vector3.RIGHT, -0.2 * u)
			bd = Vector3(2.7 * u, 0.25, 1.3 * u)
			be = Vector3(0.7 * u, 0.3, 0.4)
			pe = Vector2(0.25, -0.15) * u
			maos = 0.8
		"agarrado":
			# Peito em cima do meio do teto, barriga encostada na lataria
			var esc: float = y.get("esc", 1.37)
			const NO_TETO := 0.95   # um pouco menor no teto: o carro tem ~2 m de largura
			c.position = Vector3(0.0, -1.28 * esc * NO_TETO, -0.15)
			c.basis = Basis(Vector3.BACK, 0.15 * ginga + 0.05 * sin(ph * 6.0)) * Basis(Vector3.RIGHT, 0.04 * sin(ph * 9.0)) * Basis.from_scale(Vector3.ONE * NO_TETO)
			# Um braço puxa enquanto o outro afrouxa; na curva o de fora estica e o de dentro encolhe
			var puxa := sin(ph * 4.5)
			be = Vector3(0.3 + 0.12 * puxa, 1.85 - 0.15 * ginga, 0.7 + 0.25 * puxa)
			bd = Vector3(0.3 - 0.12 * puxa, 1.85 + 0.15 * ginga, 0.7 - 0.25 * puxa)
			pe = Vector2(0.55 + 0.4 * sin(ph * 5.0), 0.55 + 0.4 * sin(ph * 5.0 + PI))
			maos = 1.0
	for m: ShaderMaterial in y.mats:
		m.set_shader_parameter("braco_e", be)
		m.set_shader_parameter("braco_d", bd)
		m.set_shader_parameter("pernas", pe)
		m.set_shader_parameter("maos", maos)
