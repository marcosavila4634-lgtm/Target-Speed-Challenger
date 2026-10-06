extends SceneTree
## Ladrilho de rocha sem emenda a partir da arte da montanha da armadilha (assets/MAPA SERPENTE/morro/rocha
## gigante com armadilha): um pedaço só de pedra (fora do arco pintado), sem a luz pintada, com as bordas
## misturadas para repetir sem costura. Saída: assets/selva/rochas/rocha_ladrilho.png
## Com "-- musgo": a rocha com musgo (rochacommusgo1varios angulos, o miolo da vista de cima) para as paredes
## do morro sobre os túneis da pista (TunelPista). Saída: assets/selva/rochas/rocha_musgo_ladrilho.png
## Uso: Godot --headless --path . -s tools/serpents_climb/rocha_ladrilho.gd [-- musgo]

const ARTE := "res://assets/MAPA SERPENTE/morro/rochadiferente angulos.png"
const REGIAO := Rect2i(250, 150, 300, 300)
const SAIDA := "res://assets/selva/rochas/rocha_ladrilho.png"
const MUSGO_ARTE := "res://assets/MAPA SERPENTE/morro/rochacommusgo1varios angulos.png"
const MUSGO_REGIAO := Rect2i(920, 110, 320, 320)
const MUSGO_SAIDA := "res://assets/selva/rochas/rocha_musgo_ladrilho.png"


func _initialize() -> void:
	var musgo := "musgo" in OS.get_cmdline_user_args()
	var img := Image.load_from_file(ProjectSettings.globalize_path(MUSGO_ARTE if musgo else ARTE))
	img.convert(Image.FORMAT_RGBA8)
	var r := img.get_region(MUSGO_REGIAO if musgo else REGIAO)
	var w := r.get_width()
	# Luz pintada: divide pela média grande
	var largo: Image = r.duplicate()
	largo.resize(w / 24, w / 24, Image.INTERPOLATE_BILINEAR)
	largo.resize(w, w, Image.INTERPOLATE_CUBIC)
	for y in w:
		for x in w:
			var c := r.get_pixel(x, y)
			var k := clampf(pow(0.45 / maxf(largo.get_pixel(x, y).get_luminance(), 0.05), 0.6), 0.7, 1.7)
			r.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	# Emenda: os últimos B px misturam com os primeiros (nos dois eixos)
	var b := int(w * 0.2)
	var n := w - b
	var s := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c := r.get_pixel(x, y)
			if x < b:
				c = r.get_pixel(n + x, y).lerp(c, smoothstep(0.0, 1.0, float(x) / b))
			s.set_pixel(x, y, c)
	var t := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var c := s.get_pixel(x, y)
			if y < b:
				var de := s.get_pixel(x, mini(n - b + y, n - 1)) if n - b + y < n else c
				# linha de baixo da imagem já emendada na horizontal: refaz pela original
				var o := r.get_pixel(x if x >= b else x, n + y)
				if x < b:
					o = r.get_pixel(n + x, n + y).lerp(r.get_pixel(x, n + y), smoothstep(0.0, 1.0, float(x) / b))
				c = o.lerp(c, smoothstep(0.0, 1.0, float(y) / b))
			t.set_pixel(x, y, c)
	t.save_png(ProjectSettings.globalize_path(MUSGO_SAIDA if musgo else SAIDA))
	print("pronto ladrilho %d px" % n)
	quit()
