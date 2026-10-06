extends SceneTree
## Estátua que cospe fogo do Serpent's Climb (pedido do dono 2026-10-06; modelo da pasta
## assets/MAPA SERPENTE/GOSPEFOGO, "Statue 3D textured mesh model" de Aleksandr, CC-BY 4.0).
## Junta as malhas do .glb numa só, de pé (y para cima), base em y = 0, centrada em x/z e com altura 1;
## troca a malha cheia (~260 mil triângulos) por um nível de ~TRI_BASE e gera os LODs dele. Grava
## assets/selva/gospefogo/estatua.res + estatua_cor.jpg e três fotos de conferência no scratchpad (FOTOS=pasta).
## Rodar COM vídeo (as fotos precisam): Godot --path . -s tools/serpents_climb/estatua_fogo.gd

const GLB := "res://assets/MAPA SERPENTE/GOSPEFOGO/statue_3d_textured_mesh_model.glb"
const SAIDA := "res://assets/selva/gospefogo/"
const TRI_BASE := 40000


func _initialize() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(GLB), st) != OK:
		push_error("não leu " + GLB)
		quit(1)
		return
	var cena := doc.generate_scene(st)
	root.add_child(cena)
	var verts := PackedVector3Array()
	var normais := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var textura: Texture2D
	for mi: MeshInstance3D in cena.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.transform   # (fora da árvore ainda: soma as transformações dos pais à mão)
		var pai := mi.get_parent()
		while pai is Node3D:
			xf = (pai as Node3D).transform * xf
			pai = pai.get_parent()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var base := verts.size()
			for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
				verts.append(xf * v)
			for n: Vector3 in arr[Mesh.ARRAY_NORMAL]:
				normais.append((xf.basis * n).normalized())
			uvs.append_array(arr[Mesh.ARRAY_TEX_UV])
			for k: int in arr[Mesh.ARRAY_INDEX]:
				idx.append(base + k)
			var mat := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mat and mat.albedo_texture and textura == null:
				textura = mat.albedo_texture
	var caixa := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		caixa = caixa.expand(v)
	print("caixa original ", caixa)
	var esc := 1.0 / caixa.size.y
	var centro := caixa.get_center()
	for i in verts.size():
		var v := verts[i] - Vector3(centro.x, caixa.position.y, centro.z)
		verts[i] = v * esc
	var arr2 := []
	arr2.resize(Mesh.ARRAY_MAX)
	arr2[Mesh.ARRAY_VERTEX] = verts
	arr2[Mesh.ARRAY_NORMAL] = normais
	arr2[Mesh.ARRAY_TEX_UV] = uvs
	arr2[Mesh.ARRAY_INDEX] = idx
	# Nível base mais leve: o LOD mais perto de TRI_BASE vira a malha principal (com LODs próprios)
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr2)
	im.generate_lods(25.0, 60.0, [])
	var a3 := im.get_surface_arrays(0)
	var melhor: PackedInt32Array = a3[Mesh.ARRAY_INDEX]
	for k in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, k)
		if absi(li.size() / 3 - TRI_BASE) < absi(melhor.size() / 3 - TRI_BASE):
			melhor = li
	a3[Mesh.ARRAY_INDEX] = melhor
	var im2 := ImporterMesh.new()
	im2.add_surface(Mesh.PRIMITIVE_TRIANGLES, a3)
	im2.generate_lods(25.0, 60.0, [])
	var malha := im2.get_mesh()
	malha.set_meta("proporcao", Vector2(caixa.size.x, caixa.size.z) / caixa.size.y)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAIDA))
	ResourceSaver.save(malha, SAIDA + "estatua.res")
	var img := textura.get_image() if textura else null
	if img:
		if img.is_compressed():
			img.decompress()
		if img.get_width() > 2048:
			img.resize(2048, 2048 * img.get_height() / img.get_width(), Image.INTERPOLATE_LANCZOS)
		img.save_jpg(ProjectSettings.globalize_path(SAIDA + "estatua_cor.jpg"), 0.9)
	print("estatua.res: %d triângulos (de %d), %d LODs, proporção %s" % [melhor.size() / 3, idx.size() / 3, im2.get_surface_lod_count(0), str(malha.get_meta("proporcao"))])
	cena.queue_free()
	# Fotos de conferência: frente, lado e 3/4
	var fotos := OS.get_environment("FOTOS")
	if fotos == "":
		quit()
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(800, 800)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var no := MeshInstance3D.new()
	no.mesh = malha
	var m := StandardMaterial3D.new()
	if img:
		m.albedo_texture = ImageTexture.create_from_image(img)
	no.material_override = m
	vp.add_child(no)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(luz)
	var amb := WorldEnvironment.new()
	amb.environment = Environment.new()
	amb.environment.background_mode = Environment.BG_COLOR
	amb.environment.background_color = Color(0.3, 0.35, 0.4)
	amb.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	amb.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	vp.add_child(amb)
	var cam := Camera3D.new()
	vp.add_child(cam)
	for k in 4:
		var ang := 90.0 * k
		var d := Vector3(sin(deg_to_rad(ang)), 0.15, cos(deg_to_rad(ang))).normalized() * 1.6
		cam.look_at_from_position(Vector3(0, 0.5, 0) + d, Vector3(0, 0.5, 0))
		for q in 4:
			await process_frame
		vp.get_texture().get_image().save_png(fotos + "/estatua_%d.png" % int(ang))
	quit()
