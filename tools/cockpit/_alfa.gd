extends SceneTree
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var img := Image.load_from_file(a)
		img.convert(Image.FORMAT_RGBA8)
		var out := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8)
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				out.set_pixel(x, y, Color(c.a, c.a, c.a))
		out.save_png(a.replace(".png", "_A.png"))
	quit()
