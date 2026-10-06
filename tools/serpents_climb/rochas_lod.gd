extends SceneTree
## Rochas do Serpent's Climb (assets/selva/rochas/*.res, feitas por rochas.gd): acrescenta os níveis de
## detalhe (LOD, o Godot troca sozinho com a distância) e uma malha leve só para a colisão (meta "col",
## faces em PackedVector3Array). Com ~1100 rochas nos paredões, a colisão com a malha cheia (27 mil
## triângulos cada) levava 30 s na abertura da etapa.
## Rodar depois de rochas.gd: Godot --headless --path . -s tools/serpents_climb/rochas_lod.gd

const PASTA := "res://assets/selva/rochas/"
const TRI_COLISAO := 1500   # alvo de triângulos da malha de colisão


func _initialize() -> void:
	for arq in DirAccess.get_files_at(PASTA):
		if arq.get_extension() != "res":
			continue
		var malha := load(PASTA + arq) as ArrayMesh
		if malha == null or malha.get_surface_count() != 1:
			continue
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, malha.surface_get_arrays(0))
		im.generate_lods(25.0, 60.0, [])
		var nova := im.get_mesh()
		for m in malha.get_meta_list():
			if m != "col":
				nova.set_meta(m, malha.get_meta(m))
		# Colisão: o LOD com o número de triângulos mais perto do alvo
		var arr := im.get_surface_arrays(0)   # os índices dos LODs são desta (generate_lods pode refazer os vértices)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var melhor: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k in im.get_surface_lod_count(0):
			var idx := im.get_surface_lod_indices(0, k)
			if absi(idx.size() / 3 - TRI_COLISAO) < absi(melhor.size() / 3 - TRI_COLISAO):
				melhor = idx
		var faces := PackedVector3Array()
		faces.resize(melhor.size())
		var boas := 0
		for i in melhor.size():
			faces[i] = verts[melhor[i]]
		for i in range(0, faces.size(), 3):
			if (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).length_squared() > 1e-10:
				boas += 1
		nova.set_meta("col", faces)
		ResourceSaver.save(nova, PASTA + arq)
		print("%s: %d triângulos, %d LODs, colisão %d triângulos (%d com área)" % [arq, arr[Mesh.ARRAY_INDEX].size() / 3, im.get_surface_lod_count(0), faces.size() / 3, boas])
	quit()
