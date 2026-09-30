extends SceneTree
## Lista peças de um interior extraído perto de um ponto. Uso: -- <id> x y z raio
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file("res://assets/cockpit/%s/%s.glb" % [a[0], a[0]], st)
	var r: Node = doc.generate_scene(st)
	var p := Vector3(float(a[1]), float(a[2]), float(a[3]))
	for mi: MeshInstance3D in r.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != r.get_parent():
			if n is Node3D: t = (n as Node3D).transform * t
			n = n.get_parent()
		var ab := t * mi.get_aabb()
		if ab.get_center().distance_to(p) < float(a[4]):
			var mats := []
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s)
				var tx := ""
				if m is BaseMaterial3D:
					tx = "alb=%s nor=%s cor=%s" % [m.albedo_texture != null, m.normal_texture != null, m.albedo_color]
				mats.append("%s(%s)" % [m.resource_name if m else "-", tx])
			print(mi.name, " c=", ab.get_center(), " t=", ab.size, " ", mats)
	quit()
