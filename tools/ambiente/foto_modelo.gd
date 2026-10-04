extends SceneTree
## Foto em perspectiva de um .glb (enquadra tudo), com a 1ª animação tocando se houver.
## Uso: godot -s tools/ambiente/foto_modelo.gd -- <arquivo.glb> <saida.png> [tempo_anim] [dir_x dir_y dir_z] [zoom]

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var cena: Node3D = (load(a[0]) as PackedScene).instantiate()
	root.size = Vector2i(1600, 900)
	root.add_child(cena)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-45, 35, 0)
	root.add_child(luz)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	root.add_child(env)
	var ap := cena.find_children("*", "AnimationPlayer", true, false)
	var t := float(a[2]) if a.size() > 2 else 0.0
	if not ap.is_empty():
		var p := ap[0] as AnimationPlayer
		print("animações: ", p.get_animation_list())
		p.play(p.get_animation_list()[0])
		p.seek(t, true)
		p.pause()
	await process_frame
	var caixa := AABB()
	var primeiro := true
	for vi: VisualInstance3D in cena.find_children("*", "VisualInstance3D", true, false):
		var ab := vi.global_transform * vi.get_aabb()
		caixa = ab if primeiro else caixa.merge(ab)
		primeiro = false
	print("caixa: ", caixa)
	var dir := Vector3(1, 0.6, 1.2) if a.size() < 6 else Vector3(float(a[3]), float(a[4]), float(a[5]))
	var zoom := float(a[6]) if a.size() > 6 else 1.0
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.far = 20000.0
	cam.position = caixa.get_center() + dir.normalized() * caixa.size.length() * 0.9 / zoom
	var foco := caixa.get_center()
	if OS.get_environment("FOCO") != "":   # "x,y,z,dist": enquadra um ponto em vez do modelo todo
		var fz := OS.get_environment("FOCO").split_floats(",")
		foco = Vector3(fz[0], fz[1], fz[2])
		cam.position = foco + dir.normalized() * fz[3]
	cam.look_at(foco)
	cam.current = true
	for i in 4:
		await process_frame
	root.get_texture().get_image().save_png(a[1])
	quit()
