extends SceneTree
## Salva as texturas de cor (albedo/emissão) de cada interior em PNG para revisão das marcas.
## Uso: godot --headless -s tools/cockpit/texturas.gd -- <id> <pasta>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	var pasta: String = args[1] + "/" + id
	DirAccess.make_dir_recursive_absolute(pasta)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file("res://assets/cockpit/%s/%s.glb" % [id, id], st)
	var vistos := {}
	for i in st.get_materials().size():
		var m = st.get_materials()[i]
		if not m is BaseMaterial3D:
			continue
		for p in ["albedo_texture", "emission_texture"]:
			var t: Texture2D = m.get(p)
			if t == null or vistos.has(t):
				continue
			vistos[t] = true
			var img := t.get_image()
			if img == null:
				continue
			if img.is_compressed():
				img.decompress()
			var nome := "%03d_%s_%s_%dx%d" % [i, m.resource_name.validate_filename(), p.left(3), img.get_width(), img.get_height()]
			if img.get_width() > 1024:
				img.resize(1024, int(1024.0 * img.get_height() / img.get_width()))
			img.save_png(pasta + "/" + nome + ".png")
			print(nome)
	quit()
