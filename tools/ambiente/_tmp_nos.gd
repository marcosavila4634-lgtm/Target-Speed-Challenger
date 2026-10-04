extends SceneTree
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new(); var st := GLTFState.new()
	doc.append_from_file(a[0], st)
	var cena: Node3D = doc.generate_scene(st)
	root.add_child(cena)
	for mi: MeshInstance3D in cena.find_children("*", "MeshInstance3D", true, false):
		var ab := mi.global_transform * mi.get_aabb()
		var tri := 0
		for s in mi.mesh.get_surface_count(): tri += mi.mesh.surface_get_array_index_len(s) / 3
		print(mi.get_path(), " surf=", mi.mesh.get_surface_count(), " tri=", tri, " P=", ab.position.snapped(Vector3.ONE*0.1), " S=", ab.size.snapped(Vector3.ONE*0.1))
	quit()
