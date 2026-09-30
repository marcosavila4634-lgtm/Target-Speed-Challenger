extends SceneTree
## Mostra as texturas de um material de um interior extraído. Uso: -- <id> <material> <pasta>
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file("res://assets/cockpit/%s/%s.glb" % [a[0], a[0]], st)
	for m in st.get_materials():
		if m.resource_name.to_lower() != a[1]:
			continue
		for p in m.get_property_list():
			if str(p.name).ends_with("_texture") and m.get(p.name) is Texture2D:
				var img: Image = m.get(p.name).get_image()
				print(p.name, " ", img.get_size())
				img.save_png("%s/%s_%s.png" % [a[2], a[1], p.name])
		print("normal_enabled=", m.normal_enabled, " scale=", m.normal_scale, " ao=", m.ao_enabled, " rough=", m.roughness, " metal=", m.metallic)
		break
	quit()
