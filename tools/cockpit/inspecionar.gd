extends SceneTree
## Lista as malhas de um .glb (nome, pais, AABB global, triângulos, materiais e texturas).
## Uso: godot --headless -s tools/cockpit/inspecionar.gd -- <arquivo.glb>

func _init() -> void:
	var arq: String = OS.get_cmdline_user_args()[0]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(arq, st) != OK:
		print("falhou"); quit(); return
	var raiz: Node = doc.generate_scene(st)
	get_root().add_child(raiz)
	var total := 0
	var tudo := AABB()
	for mi: MeshInstance3D in raiz.find_children("*", "MeshInstance3D", true, false):
		var ab: AABB = _glob(mi, raiz) * mi.get_aabb()
		tudo = ab if tudo.size == Vector3.ZERO else tudo.merge(ab)
		var tri := 0
		var mats := []
		for s in mi.mesh.get_surface_count():
			tri += mi.mesh.surface_get_array_len(s) if mi.mesh.surface_get_format(s) & Mesh.ARRAY_FORMAT_INDEX == 0 else mi.mesh.surface_get_array_index_len(s)
			var m := mi.mesh.surface_get_material(s)
			var t := ""
			if m is BaseMaterial3D and m.albedo_texture:
				t = m.albedo_texture.resource_name
			mats.append("%s[%s]" % [m.resource_name if m else "-", t])
		tri /= 3
		total += tri
		var caminho := str(raiz.get_path_to(mi))
		print("%s | c=%s t=%s | %d | %s" % [caminho, _v(ab.get_center()), _v(ab.size), tri, ", ".join(mats)])
	print("TOTAL tri=%d aabb pos=%s tam=%s" % [total, _v(tudo.position), _v(tudo.size)])
	quit()

func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]

## Transformação acumulada até a raiz (a cena não está na árvore).
static func _glob(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != raiz.get_parent():
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t
