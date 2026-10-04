extends SceneTree
## Converte uma captura (.png) em .jpg no tamanho pedido (ex.: foto do mapa para o menu).
## Uso: godot --headless -s tools/ambiente/png_para_jpg.gd -- <entrada.png> <saida.jpg> [largura altura] [corte_y0 corte_y1]
## corte_y0/corte_y1 (0..1) tiram as faixas pretas de cinema de cima e de baixo.

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	if a.size() > 5:
		var y0 := int(float(a[4]) * img.get_height())
		var y1 := int(float(a[5]) * img.get_height())
		# Mantém 16:9 cortando também as laterais
		var w := mini(img.get_width(), int((y1 - y0) * 16.0 / 9.0))
		img = img.get_region(Rect2i((img.get_width() - w) / 2, y0, w, y1 - y0))
	if a.size() > 3:
		img.resize(int(a[2]), int(a[3]), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	img.save_jpg(a[1], 0.9)
	print("salvo ", a[1], " ", img.get_size())
	quit()
