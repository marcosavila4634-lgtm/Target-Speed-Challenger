extends SceneTree
## Foto de conferência das luvas: avatar parado (pose do arquivo) com a câmera na mão direita.
## Uso: godot -s tools/luvas/ver.gd -- <id_avatar> <saida_prefixo>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	root.size = Vector2i(900, 900)
	var av: Node3D = (load("res://assets/avatar/%s/%s.glb" % [a[0], a[0]]) as PackedScene).instantiate()
	root.add_child(av)
	var esq: Skeleton3D = av.find_children("*", "Skeleton3D", true, false)[0]
	var luvas: Node = (load("res://assets/avatar/%s/luvas.glb" % a[0]) as PackedScene).instantiate()
	for mi: MeshInstance3D in luvas.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		mi.owner = null
		mi.get_parent().remove_child(mi)
		esq.add_child(mi)
		mi.transform = Transform3D.IDENTITY
		mi.skeleton = NodePath("..")
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(luz)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.4, 0.5, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root.add_child(env)
	await process_frame
	var idx := -1
	for i in esq.get_bone_count():
		if esq.get_bone_name(i).begins_with("RightHand_") or esq.get_bone_name(i) == "RightHand":
			idx = i
	var mao := esq.global_transform * esq.get_bone_global_pose(idx).origin
	var cam := Camera3D.new()
	cam.fov = 40
	cam.near = 0.01
	root.add_child(cam)
	cam.current = true
	for v in [["frente", Vector3(0, 0, 0.6)], ["lado", Vector3(-0.6, 0, 0)], ["tras", Vector3(0, 0, -0.6)]]:
		cam.global_position = mao + v[1]
		cam.look_at(mao)
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s_%s.png" % [a[1], v[0]])
	quit()
