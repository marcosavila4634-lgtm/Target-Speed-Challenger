extends SceneTree
## Fotos ortográficas (cima, lado e frente) de um .glb com grade de 0,5 m, para medir a cabine.
## Uso: godot -s tools/cockpit/vistas.gd -- <arquivo.glb> <pasta_saida> [escala]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var arq: String = args[0]
	var saida: String = args[1]
	var escala := float(args[2]) if args.size() > 2 else 1.0
	DirAccess.make_dir_recursive_absolute(saida)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(arq, st)
	var raiz: Node3D = doc.generate_scene(st)
	raiz.scale = Vector3.ONE * escala
	root.size = Vector2i(1400, 1400)
	var mundo := Node3D.new()
	root.add_child(mundo)
	mundo.add_child(raiz)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-50, 30, 0)
	mundo.add_child(luz)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.3, 0.35)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	mundo.add_child(env)
	# Grade de 0,5 m (linhas finas) e eixos: X vermelho, Z azul
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(-8, 9):
		var f := i * 0.5
		var c := Color(1, 1, 1, 1) if i == 0 else Color(0.6, 0.6, 0.6)
		for par in [[Vector3(f, 0, -4), Vector3(f, 0, 4)], [Vector3(-4, 0, f), Vector3(4, 0, f)], [Vector3(f, -4, 0), Vector3(f, 4, 0)], [Vector3(-4, f, 0), Vector3(4, f, 0)], [Vector3(0, f, -4), Vector3(0, f, 4)], [Vector3(0, -4, f), Vector3(0, 4, f)]]:
			im.surface_set_color(c)
			im.surface_add_vertex(par[0])
			im.surface_add_vertex(par[1])
	im.surface_end()
	var grade := MeshInstance3D.new()
	grade.mesh = im
	mundo.add_child(grade)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 7.0
	mundo.add_child(cam)
	cam.current = true
	var vistas := {"cima": [Vector3(0, 20, 0), Vector3(-90, 0, 0)], "lado": [Vector3(20, 0, 0), Vector3(0, 90, 0)], "frente": [Vector3(0, 0, -20), Vector3(0, 180, 0)]}
	for nome: String in vistas:
		cam.position = vistas[nome][0]
		cam.rotation_degrees = vistas[nome][1]
		for i in 4:
			await process_frame
		root.get_texture().get_image().save_png("%s/%s.png" % [saida, nome])
	quit()
