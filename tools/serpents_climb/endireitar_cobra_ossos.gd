extends SceneTree
## Desenrola a cobra animada da pasta do dono (assets/MAPA SERPENTE/COBRAS/snake_attack_animations_multiple,
## "Snake attack Animations (Multiple)", CC-BY 4.0 — ver assets/selva/cobra/creditos.txt) numa cobra RETA,
## para SerpenteGigante dar os ossos dela e fazê-la rastejar pela trilha.
## Como: a malha é presa a 20 ossos (cauda → quadril → espinha → pescoço → cabeça). Cada osso vai para a
## linha reta (cabeça em z = 0 olhando para -Z, corpo para +Z) girando em volta da própria junta para a
## direção do corpo virar -Z; a pele vai junto pela mistura de pesos (o mesmo cálculo da animação), então
## nada estica nem amassa. Depois a barriga é posta em y = 0 ao longo do corpo todo.
## Uso: Godot --headless --path . -s tools/serpents_climb/endireitar_cobra_ossos.gd -- <scene.gltf> <saida.glb>
## (a pele marrom é a malha com mais vértices, material 1).

# Cadeia da cabeça para a cauda (nomes sem o sufixo do Sketchfab); pescoço lateral e língua seguem o pai
const CADEIA := ["BN_Mouth_01", "BN_Head_01", "BN__Neck_02", "BN__Neck_01", "BN_Spine_03", "BN_Spine_02", "BN_Spine_01",
	"Hips", "BN_Tail_01", "BN_Tail_02", "BN_Tail_03", "BN_Tail_04", "BN_Tail_05", "BN_Tail_06", "BN_Tail_07"]
const SEGUE := {"BN__Neck_R_01": "BN__Neck_02", "BN__Neck_L_01": "BN__Neck_02", "BN_Tongue_01": "BN_Mouth_01", "BN_Tongue_02": "BN_Mouth_01",
	"rootJoint": "Hips"}


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(a[0], st) != OK:
		push_error("não abriu " + a[0])
		quit(1)
		return
	var cena: Node3D = doc.generate_scene(st)
	root.add_child(cena)
	await process_frame
	var mi: MeshInstance3D = null
	for m: MeshInstance3D in cena.find_children("*", "MeshInstance3D", true, false):
		if mi == null or m.mesh.surface_get_array_len(0) > mi.mesh.surface_get_array_len(0):
			mi = m
	var sk := mi.get_node(mi.skeleton) as Skeleton3D
	var skin := mi.skin
	# Osso do esqueleto por nome curto
	var por_nome := {}
	for b in sk.get_bone_count():
		var nome := sk.get_bone_name(b)
		for chave in CADEIA + SEGUE.keys():
			if nome.begins_with(chave + ".") or nome == chave or nome.ends_with(chave):
				por_nome[chave] = b
	# Juntas (espaço do esqueleto) e a reta: s acumulado no chão a partir da boca
	var juntas: Array[Vector3] = []
	for nome in CADEIA:
		juntas.append(sk.get_bone_global_rest(por_nome[nome]).origin)
	var n := juntas.size()
	var s := PackedFloat32Array()
	s.resize(n)
	for k in range(1, n):
		var d := juntas[k] - juntas[k - 1]
		s[k] = s[k - 1] + Vector2(d.x, d.z).length()
	# Transformação de cada osso: gira em volta da junta (rumo da cabeça vira -Z, cima continua cima) e
	# leva a junta para (0, altura, s)
	var giro := {}
	var quadril := CADEIA.find("Hips")
	for k in n:
		# Direção do próprio osso: da quadril para a frente o osso aponta para a cabeça (junta k-1); da
		# quadril para trás, para a cauda (junta k+1)
		var t: Vector3
		if k == 0:
			t = juntas[0] - juntas[1]
		elif k < quadril:
			t = juntas[k - 1] - juntas[k]
		elif k < n - 1:
			t = juntas[k] - juntas[k + 1]
		else:
			t = -sk.get_bone_global_rest(por_nome[CADEIA[k]]).basis.y   # ponta da cauda: o eixo do osso (aponta para a ponta)
		t.y = 0.0
		t = t.normalized()
		var tras := -t
		var direita := Vector3.UP.cross(tras).normalized()
		var f := Basis(direita, Vector3.UP, tras)   # leva os eixos da reta para os do repouso
		var b: int = por_nome[CADEIA[k]]
		giro[b] = Transform3D(f.inverse(), Vector3(0.0, juntas[k].y, s[k])) * Transform3D(Basis.IDENTITY, -juntas[k])
	for filho in SEGUE:
		if por_nome.has(filho):
			giro[por_nome[filho]] = giro[por_nome[SEGUE[filho]]]
	# Pele: espaço da malha → esqueleto (bind) → reta
	var arr := mi.mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var tan: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var ossos: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var pesos: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var por_vert := ossos.size() / pos.size()
	var bind_osso := {}
	for i in skin.get_bind_count():
		var bb := skin.get_bind_bone(i)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(i))
		bind_osso[i] = bb
	for v in pos.size():
		var p := Vector3.ZERO
		var nn := Vector3.ZERO
		var tt := Vector3.ZERO
		var soma := 0.0
		for k in por_vert:
			var w := pesos[v * por_vert + k]
			if w <= 0.0:
				continue
			var bi: int = ossos[v * por_vert + k]
			var bone: int = bind_osso.get(bi, bi)
			var g: Transform3D = giro.get(bone, giro[por_nome["Hips"]])
			var m := g * sk.get_bone_global_rest(bone) * skin.get_bind_pose(bi)
			p += (m * pos[v]) * w
			nn += (m.basis * nor[v]) * w
			if not tan.is_empty():
				tt += (m.basis * Vector3(tan[v * 4], tan[v * 4 + 1], tan[v * 4 + 2])) * w
			soma += w
		pos[v] = p / maxf(soma, 1e-6)
		nor[v] = nn.normalized()
		if not tan.is_empty():
			tt = tt.normalized()
			tan[v * 4] = tt.x
			tan[v * 4 + 1] = tt.y
			tan[v * 4 + 2] = tt.z
	# Focinho em z = 0; barriga em y = 0 ao longo do corpo (o ponto mais baixo de cada fatia, alisado)
	var z0 := INF
	var z1 := -INF
	for q in pos:
		z0 = minf(z0, q.z)
		z1 = maxf(z1, q.z)
	var fatias := 120
	var baixo := PackedFloat32Array()
	baixo.resize(fatias)
	baixo.fill(INF)
	for q in pos:
		var k := mini(int((q.z - z0) / (z1 - z0) * fatias), fatias - 1)
		baixo[k] = minf(baixo[k], q.y)
	for k in range(1, fatias):
		if baixo[k] == INF:
			baixo[k] = baixo[k - 1]
	for passada in 6:
		var b2 := baixo.duplicate()
		for k in range(1, fatias - 1):
			b2[k] = (baixo[k - 1] + 2.0 * baixo[k] + baixo[k + 1]) / 4.0
		baixo = b2
	var larg := 0.0
	for i in pos.size():
		var q := pos[i]
		var f := clampf((q.z - z0) / (z1 - z0) * fatias - 0.5, 0.0, fatias - 1.001)
		var k := int(f)
		var chao := lerpf(baixo[k], baixo[mini(k + 1, fatias - 1)], f - k)
		pos[i] = Vector3(q.x, q.y - chao, q.z - z0)
		larg = maxf(larg, absf(q.x))
	var limpo := []
	limpo.resize(Mesh.ARRAY_MAX)
	limpo[Mesh.ARRAY_VERTEX] = pos
	limpo[Mesh.ARRAY_NORMAL] = nor
	if not tan.is_empty():
		limpo[Mesh.ARRAY_TANGENT] = tan
	limpo[Mesh.ARRAY_TEX_UV] = arr[Mesh.ARRAY_TEX_UV]
	limpo[Mesh.ARRAY_INDEX] = arr[Mesh.ARRAY_INDEX]
	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, limpo)
	malha.surface_set_material(0, mi.get_active_material(0))
	var reta := MeshInstance3D.new()
	reta.name = "CobraReta"
	reta.mesh = malha
	var raiz := Node3D.new()
	raiz.name = "Cobra"
	raiz.add_child(reta)
	reta.owner = raiz
	var saida := GLTFDocument.new()
	var est := GLTFState.new()
	saida.append_from_scene(raiz, est)
	saida.write_to_filesystem(est, a[1])
	print("comprimento %.2f  meia-largura %.2f  proporção %.1f" % [z1 - z0, larg, (z1 - z0) / (larg * 2.0)])
	quit()
