extends SceneTree
## Recorta uma região (0..1) de uma imagem e amplia para conferir. Uso: -- <entrada> <saida> x0 y0 x1 y1 [largura]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var img := Image.load_from_file(a[0])
	var w := img.get_width()
	var h := img.get_height()
	var r := Rect2i(int(float(a[2]) * w), int(float(a[3]) * h), int((float(a[4]) - float(a[2])) * w), int((float(a[5]) - float(a[3])) * h))
	var out := img.get_region(r)
	var larg := int(a[6]) if a.size() > 6 else 800
	out.resize(larg, int(larg * float(r.size.y) / r.size.x), Image.INTERPOLATE_NEAREST)
	out.save_png(a[1])
	quit()
