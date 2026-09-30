extends SceneTree
## Junta várias imagens numa folha (grade) com o nome embaixo, para revisar de uma vez.
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var saida: String = args[0]
	var arqs := args.slice(1)
	var lado := 400
	var cols := 3
	var linhas := ceili(arqs.size() / float(cols))
	var folha := Image.create(cols * lado, linhas * lado, false, Image.FORMAT_RGB8)
	folha.fill(Color(1, 0, 1))
	for i in arqs.size():
		var img := Image.load_from_file(arqs[i])
		img.convert(Image.FORMAT_RGB8)
		var f := float(lado - 8) / maxi(img.get_width(), img.get_height())
		img.resize(maxi(1, int(img.get_width() * f)), maxi(1, int(img.get_height() * f)))
		folha.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % cols) * lado + 4, (i / cols) * lado + 4))
	folha.save_png(saida)
	quit()
