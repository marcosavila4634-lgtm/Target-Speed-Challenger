extends SceneTree
## Prepara as texturas do Drag a partir das do modelo Race Track (licença Sketchfab Standard):
## - asfalto: miolo da textura da estrada (sem as faixas brancas das bordas), emendado nas laterais
##   para repetir sem costura, e o relevo (normal map) tirado do brilho dele;
## - brita: areia/brita da caixa de contenção, com relevo;
## - pneus: só a metade de cima (duas fileiras de pneus) da textura da barreira.
## Uso: godot --headless -s tools/ambiente/texturas_drag.gd

const ORIGEM := "res://assets/dragracing ambiente/race_track_23mb_glb (1)/race_track_23mb_glb.zip"
const PASTA := "res://assets/drag"


func _init() -> void:
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path(ORIGEM)) != OK:
		push_error("não abriu " + ORIGEM)
		quit(1)
		return
	var estrada := _png(zip, "textures/road_mat_baseColor.png")
	var asfalto := estrada.get_region(Rect2i(28, 0, estrada.get_width() - 56, estrada.get_height()))
	_emendar_laterais(asfalto, 48)
	asfalto.resize(512, 512, Image.INTERPOLATE_CUBIC)
	_salvar(asfalto, "asfalto")
	_salvar(_relevo(asfalto, 6.0), "asfalto_normal")
	var brita := _png(zip, "textures/sand1_mat_baseColor.png")
	_salvar(brita, "brita")
	_salvar(_relevo(brita, 8.0), "brita_normal")
	var pneus := _png(zip, "textures/tirebump_mat_baseColor.png")
	_salvar(pneus.get_region(Rect2i(0, 0, pneus.get_width(), pneus.get_height() / 2)), "pneus")
	zip.close()
	quit()


func _png(zip: ZIPReader, caminho: String) -> Image:
	var img := Image.new()
	img.load_png_from_buffer(zip.read_file(caminho))
	img.convert(Image.FORMAT_RGBA8)
	return img


## Mistura as `faixa` colunas de cada borda com as da outra (a textura passa a repetir em X).
func _emendar_laterais(img: Image, faixa: int) -> void:
	var w := img.get_width()
	var copia := img.duplicate() as Image
	for y in img.get_height():
		for i in faixa:
			var t := 0.5 * (1.0 - float(i) / faixa)   # 0,5 na borda, 0 no fim da faixa
			var esq := copia.get_pixel(i, y)
			var dir := copia.get_pixel(w - 1 - i, y)
			img.set_pixel(i, y, esq.lerp(dir, t))
			img.set_pixel(w - 1 - i, y, dir.lerp(esq, t))


## Normal map a partir do brilho (buracos e rachaduras escuras ficam fundos).
func _relevo(cor: Image, forca: float) -> Image:
	var n := cor.duplicate() as Image
	n.bump_map_to_normal_map(forca)
	return n


func _salvar(img: Image, nome: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA))
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [PASTA, nome]))
	print("[TEXTURA] %s (%dx%d)" % [nome, img.get_width(), img.get_height()])
