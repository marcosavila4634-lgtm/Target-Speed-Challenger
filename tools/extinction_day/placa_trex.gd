extends SceneTree
## Prepara a placa TIRANOSSAURO REX dos portões do cercado (arte do dono em
## assets/DINOSSAUROS/extruturas/placa tiranossauroi): tira da arte as chamas pintadas em cima dos dois
## cestos grandes — no jogo o fogo é de verdade (ArmadilhasDino._placa_trex), e chama pintada parada tem
## cara de imagem. Grava assets/dino/portao/placa_tiranossauro_rex.png.
##   Godot --headless --path . -s tools/extinction_day/placa_trex.gd

const ORIGEM := "res://assets/DINOSSAUROS/extruturas/placa tiranossauroi/Imagem do ChatGPT 3 de out. de 2026, 22_04_10.png"
const DESTINO := "res://assets/dino/portao/placa_tiranossauro_rex.png"


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM))
	if img == null:
		print("sem a arte em ", ORIGEM)
		quit()
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var fx := w / 1448.0
	var fy := h / 1086.0
	var apagados := 0
	for y in h:
		for x in w:
			var u := x / fx
			var v := y / fy
			var lado := u if u < 724.0 else 1448.0 - u   # distância até a borda mais perto (a arte é simétrica)
			var apaga := false
			if v < 338.0 and lado < 150.0:
				apaga = true   # a chama inteira, acima da boca do cesto
			elif v < 284.0 and lado < 200.0:
				# a aba de dentro da chama, por cima das folhas do canto: só o que tem cor de fogo
				var c := img.get_pixel(x, y)
				apaga = c.r > 0.45 and c.r > c.g * 1.15 and c.b < c.r * 0.6
			if apaga and img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				apagados += 1
	img.save_png(ProjectSettings.globalize_path(DESTINO))
	print("placa gravada em %s (%d x %d), %d pontos de chama apagados" % [DESTINO, w, h, apagados])
	quit()
