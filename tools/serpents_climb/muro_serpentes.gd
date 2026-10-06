extends SceneTree
## Muro das cabeças que cospem água do Serpent's Climb (MuroSerpentes), IGUAL às artes do dono
## (assets/MAPA SERPENTE/gospeagua, cópias em assets/selva/muro_serpentes). A própria arte é a pele de uma
## escultura em relevo, não blocos:
## - MURO: sólido fechado. A frente é a arte da frente em relevo (cornijas, friso, pilastras e molduras dos
##   nichos saltam o tanto que saltam no desenho; o entalhe fino sai do claro-escuro); as costas são a arte de
##   costas (alinhada à frente) em relevo; o topo, as pontas e a base pegam a vista que olha para elas
##   (shaders/relevo_vistas.gdshader: cima = a arte de cima, pontas/base = fiadas lisas da própria arte);
## - CABEÇA: placa, discos, olhos, focinho com narinas, presas, boca funda e língua em rampa saindo do plano
##   da arte da frente; o alto da cabeça mostra a arte de cima e os lados a arte de lado; dentro da boca, a
##   pedra avermelhada da língua.
## Saída (assets/selva/muro_serpentes): muro.res e cabeca.res (medidas em metadados) e as texturas recortadas e
## alinhadas (*_a.png, pedra.png, boca.png).
## Uso: Godot --headless --path . -s tools/serpents_climb/muro_serpentes.gd

const PASTA := "res://assets/selva/muro_serpentes/"

# ---- muro (px de muro_frente.png)
const COMPRIMENTO := 22.0               # m do corpo do muro (px M_X0..M_X1)
const M_X0 := 148.0
const M_X1 := 1628.0
const G_X0 := 128.0                     # grade: as cornijas saem além das pontas
const G_X1 := 1648.0
const M_Y0 := 18.0                      # topo das ameias do meio
const M_Y1 := 765.0                     # pé do muro (nível da pista)
const CEL_M := 6.0                      # px da arte por célula
const AMEIAS := [Rect2(178, 62, 104, 78), Rect2(568, 18, 94, 102), Rect2(1108, 18, 97, 102), Rect2(1505, 62, 105, 78)]
const NICHOS := [Rect2(318, 348, 250, 352), Rect2(765, 348, 243, 352), Rect2(1208, 348, 247, 352)]
const MOLDURA := 22.0
const PILARES := [Rect2(588, 300, 64, 280), Rect2(1122, 300, 66, 280)]
# Costas (muro_costas.png) alinhadas à frente: x espelhado, y por trechos (mesmas fiadas)
const C_X0 := 70.0
const C_X1 := 1190.0
const Y_FRENTE := [18.0, 108.0, 140.0, 172.0, 265.0, 300.0, 765.0]
const Y_COSTAS := [232.0, 300.0, 350.0, 378.0, 455.0, 490.0, 900.0]
const C_PILARES := [Rect2(425, 490, 55, 410), Rect2(765, 490, 55, 410)]
const CIMA := Rect2i(75, 268, 1110, 232)     # muro_cima.png: x das pontas; y de trás (268) para a frente (500)
const PEDRA := Rect2i(900, 780, 150, 82)     # muro_costas.png: fiadas de blocos lisos, sem cipó

# ---- cabeça (px de cabeca_frente.png)
const CAB := Rect2(130, 45, 985, 1105)
const CAB_CIMA := Rect2i(240, 100, 780, 760)  # cabeca_cima.png: da placa (em cima) até o focinho
const CAB_LADO := Rect2i(250, 60, 960, 1060)  # cabeca_lado.png: da placa até o focinho
const BOCA := Rect2i(540, 700, 180, 160)      # cabeca_frente.png: a pedra avermelhada da língua
const CEL_C := 7.0
const CAB_LARG := 230.0                       # px do muro que a placa da cabeça ocupa
const FOCINHO := 740.0                        # px da cabeça que o focinho sai da placa
const BOCA_Y := 700.0                         # altura (px) do meio da boca: de onde sai a água


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	_muro()
	_cabeca()
	print("muro_serpentes pronto em %d ms" % (Time.get_ticks_msec() - t0))
	quit()


static func _img(nome: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(PASTA + nome))
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _salvar(img: Image, nome: String) -> void:
	img.save_png(ProjectSettings.globalize_path(PASTA + nome))


## Por trechos: o y da frente no y das costas.
static func _y_costas(fy: float) -> float:
	for k in range(1, Y_FRENTE.size()):
		if fy <= Y_FRENTE[k] or k == Y_FRENTE.size() - 1:
			var t: float = (fy - Y_FRENTE[k - 1]) / (Y_FRENTE[k] - Y_FRENTE[k - 1])
			return lerpf(Y_COSTAS[k - 1], Y_COSTAS[k], t)
	return Y_COSTAS[-1]


static func _x_costas(fx: float) -> float:
	return C_X1 - (fx - M_X0) * (C_X1 - C_X0) / (M_X1 - M_X0)


## Claro-escuro de cada célula e a média da vizinhança (o entalhe é a diferença).
static func _luz(img: Image, nx: int, ny: int, raio: int) -> Array:
	var p: Image = img.duplicate()
	p.resize(nx, ny, Image.INTERPOLATE_LANCZOS)
	var lum := PackedFloat32Array()
	lum.resize(nx * ny)
	for j in ny:
		for i in nx:
			lum[j * nx + i] = p.get_pixel(i, j).get_luminance()
	var media := lum.duplicate()
	for eixo in 2:
		var origem := media.duplicate()
		for j in ny:
			for i in nx:
				var s := 0.0
				var n := 0
				for d in range(-raio, raio + 1):
					var ii := i + (d if eixo == 0 else 0)
					var jj := j + (d if eixo == 1 else 0)
					if ii >= 0 and ii < nx and jj >= 0 and jj < ny:
						s += origem[jj * nx + ii]
						n += 1
				media[j * nx + i] = s / n
	return [lum, media]


# ------------------------------------------------------------------ sólido em relevo

## Acrescenta em `m` (pos, nor, cor, idx) a superfície em relevo de uma grade e as paredes das bordas até
## z = z_base. Vértice (i, j): x = x0 + i * cel, y = y0 - j * cel. alt = z da superfície por célula (já com o
## sinal: costas para -z). marca (Color por célula): g = pedra lisa, b = boca.
static func _relevo(m: Dictionary, nx: int, ny: int, cel: float, x0: float, y0: float, dentro: PackedByteArray,
		alt: PackedFloat32Array, marca: PackedColorArray, z_base: float, sinal: float) -> void:
	var pos: PackedVector3Array = m.pos
	var nor: PackedVector3Array = m.nor
	var cor: PackedColorArray = m.cor
	var idx: PackedInt32Array = m.idx
	var vw := nx + 1
	var base := pos.size()
	var vz := PackedFloat32Array()
	vz.resize(vw * (ny + 1))
	var usado := PackedByteArray()
	usado.resize(vw * (ny + 1))
	var vc := PackedColorArray()
	vc.resize(vw * (ny + 1))
	for j in ny + 1:
		for i in vw:
			var soma := 0.0
			var conta := 0
			var c := Color(1, 0, 0)
			for dj: int in [-1, 0]:
				for di: int in [-1, 0]:
					var ci := i + di
					var cj := j + dj
					if ci >= 0 and ci < nx and cj >= 0 and cj < ny and dentro[cj * nx + ci] == 1:
						soma += alt[cj * nx + ci]
						conta += 1
						var mc := marca[cj * nx + ci]
						c.g = maxf(c.g, mc.g)
						c.b = maxf(c.b, mc.b)
			usado[j * vw + i] = 1 if conta > 0 else 0
			vz[j * vw + i] = soma / maxi(conta, 1)
			vc[j * vw + i] = c
	for j in ny + 1:
		for i in vw:
			var k := j * vw + i
			pos.append(Vector3(x0 + i * cel, y0 - j * cel, vz[k]))
			cor.append(vc[k])
	for j in ny + 1:
		for i in vw:
			var k := j * vw + i
			if usado[k] == 0:
				nor.append(Vector3(0, 0, sinal))
				continue
			var ka := j * vw + mini(i + 1, nx)
			var kb := j * vw + maxi(i - 1, 0)
			var kc := maxi(j - 1, 0) * vw + i
			var kd := mini(j + 1, ny) * vw + i
			var a := (pos[base + (ka if usado[ka] == 1 else k)]) - (pos[base + (kb if usado[kb] == 1 else k)])
			var b := (pos[base + (kc if usado[kc] == 1 else k)]) - (pos[base + (kd if usado[kd] == 1 else k)])
			var nn := a.cross(b)
			if nn.length_squared() < 1e-12:
				nn = Vector3(0, 0, 1)
			nn = nn.normalized()
			if nn.z * sinal < 0.0:
				nn = -nn
			nor.append(nn)
	for j in ny:
		for i in nx:
			if dentro[j * nx + i] == 0:
				continue
			var c := [base + j * vw + i, base + j * vw + i + 1, base + (j + 1) * vw + i + 1, base + (j + 1) * vw + i]
			if sinal > 0.0:
				idx.append_array([c[0], c[1], c[2], c[0], c[2], c[3]])
			else:
				idx.append_array([c[0], c[2], c[1], c[0], c[3], c[2]])
			# Paredes onde o vizinho está fora, até z_base
			for lado: Array in [[0, 1, 0, -1, Vector3.UP], [1, 2, 1, 0, Vector3.RIGHT], [2, 3, 0, 1, Vector3.DOWN], [3, 0, -1, 0, Vector3.LEFT]]:
				var vi: int = i + lado[2]
				var vj: int = j + lado[3]
				if vi >= 0 and vi < nx and vj >= 0 and vj < ny and dentro[vj * nx + vi] == 1:
					continue
				var b0 := pos.size()
				var mc := marca[j * nx + i]
				for ponta: int in [lado[0], lado[1]]:
					var pf := pos[c[ponta]]
					for tras in 2:
						pos.append(pf if tras == 0 else Vector3(pf.x, pf.y, z_base))
						nor.append(lado[4])
						cor.append(Color(0.88 if tras == 0 else 0.7, mc.g, mc.b))
				if sinal > 0.0:
					idx.append_array([b0, b0 + 2, b0 + 3, b0, b0 + 3, b0 + 1])
				else:
					idx.append_array([b0, b0 + 3, b0 + 2, b0, b0 + 1, b0 + 3])
	m.pos = pos
	m.nor = nor
	m.cor = cor
	m.idx = idx


static func _malha(m: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = m.pos
	arr[Mesh.ARRAY_NORMAL] = m.nor
	arr[Mesh.ARRAY_COLOR] = m.cor
	arr[Mesh.ARRAY_INDEX] = m.idx
	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return malha


static func _vazio() -> Dictionary:
	return {"pos": PackedVector3Array(), "nor": PackedVector3Array(), "cor": PackedColorArray(), "idx": PackedInt32Array()}


# ------------------------------------------------------------------ muro

static func _dentro_muro(fx: float, fy: float) -> bool:
	if fy > M_Y1:
		return false
	for a: Rect2 in AMEIAS:
		if a.has_point(Vector2(fx, fy)):
			return true
	if (fy >= 140.0 and fy < 172.0) or (fy >= 265.0 and fy < 300.0):
		return fx >= 132.0 and fx <= 1645.0
	if fy >= 140.0:
		return fx >= M_X0 and fx <= M_X1
	if fy >= 108.0:
		return fx >= 175.0 and fx <= 1610.0
	return false


static func _no_nicho(fx: float, fy: float) -> int:
	for k in NICHOS.size():
		if (NICHOS[k] as Rect2).has_point(Vector2(fx, fy)):
			return k
	return -1


## Quanto o ponto da frente sai do plano da face (m, muro de 22 m), sem o entalhe fino.
static func _fundo_frente(fx: float, fy: float) -> float:
	for a: Rect2 in AMEIAS:
		if a.has_point(Vector2(fx, fy)):
			return 0.25
	if fy < 140.0:
		return 0.22
	if fy < 172.0:
		return 0.5
	if fy < 265.0:
		return 0.2
	if fy < 300.0:
		return 0.55
	var nk := _no_nicho(fx, fy)
	if nk >= 0:
		var r: Rect2 = NICHOS[nk]
		if r.grow(-MOLDURA).has_point(Vector2(fx, fy)):
			return -0.6
		return 0.3
	for p: Rect2 in PILARES:
		if p.has_point(Vector2(fx, fy)):
			return 0.25
	if fx < 200.0 or fx > 1575.0:
		return 0.18
	if fy >= 575.0 and fy < 600.0:
		return 0.35
	if fy >= 700.0:
		return 0.3
	return 0.05


static func _fundo_costas(bx: float, by: float) -> float:
	if by < 345.0:
		return 0.22
	if by < 378.0:
		return 0.5
	if by < 455.0:
		return 0.2
	if by < 490.0:
		return 0.55
	for p: Rect2 in C_PILARES:
		if p.has_point(Vector2(bx, by)):
			return 0.25
	if by >= 738.0 and by < 778.0:
		return 0.35
	if by >= 865.0:
		return 0.3
	if bx < 110.0 or bx > 1150.0:
		return 0.18
	return 0.05


func _muro() -> void:
	var frente := _img("muro_frente.png")
	var costas := _img("muro_costas.png")
	var cima := _img("muro_cima.png")
	var e := COMPRIMENTO / (M_X1 - M_X0)
	var espessura := COMPRIMENTO * float(CIMA.size.y) / float(CIMA.size.x)
	var meio_px := (M_X0 + M_X1) * 0.5
	var gw := int(G_X1 - G_X0)
	var gh := int(M_Y1 - M_Y0)
	# Texturas alinhadas à caixa da grade (x G_X0..G_X1, y M_Y0..M_Y1)
	var tf := frente.get_region(Rect2i(int(G_X0), int(M_Y0), gw, gh))
	var tc := Image.create(gw / 2, gh / 2, false, Image.FORMAT_RGBA8)
	for y in tc.get_height():
		var by := _y_costas(M_Y0 + y * 2.0 + 1.0)
		for x in tc.get_width():
			var bx := _x_costas(G_X0 + x * 2.0 + 1.0)
			tc.set_pixel(x, y, costas.get_pixel(clampi(int(bx), 0, costas.get_width() - 1), clampi(int(by), 0, costas.get_height() - 1)))
	var tcima := cima.get_region(CIMA)
	_salvar(tf, "muro_frente_a.png")
	_salvar(tc, "muro_costas_a.png")
	_salvar(tcima, "muro_cima_a.png")
	_salvar(costas.get_region(PEDRA), "pedra.png")
	# Grade
	var nx := int(gw / CEL_M)
	var ny := int(ceil(gh / CEL_M))
	var cel := CEL_M * e
	var x0 := (G_X0 - meio_px) * e
	var y0 := (M_Y1 - M_Y0) * e
	var dentro := PackedByteArray()
	dentro.resize(nx * ny)
	var luz_f := _luz(tf, nx, ny, 4)
	var luz_c := _luz(tc, nx, ny, 4)
	var alt_f := PackedFloat32Array()
	alt_f.resize(nx * ny)
	var alt_c := PackedFloat32Array()
	alt_c.resize(nx * ny)
	var marca := PackedColorArray()
	marca.resize(nx * ny)
	var marca_c := PackedColorArray()
	marca_c.resize(nx * ny)
	for j in ny:
		var fy := M_Y0 + (j + 0.5) * CEL_M
		for i in nx:
			var fx := G_X0 + (i + 0.5) * CEL_M
			var k := j * nx + i
			marca[k] = Color(1, 0, 0)
			marca_c[k] = Color(1, 0, 0)
			if not _dentro_muro(fx, fy):
				continue
			dentro[k] = 1
			var nk := _no_nicho(fx, fy)
			var fundo_nicho := nk >= 0 and (NICHOS[nk] as Rect2).grow(-MOLDURA).has_point(Vector2(fx, fy))
			var entalhe := clampf((luz_f[0][k] - luz_f[1][k]) * 0.7, -0.1, 0.1)
			if fundo_nicho:
				marca[k] = Color(1, 1, 0)
				entalhe = 0.0
			alt_f[k] = espessura * 0.5 + _fundo_frente(fx, fy) + entalhe
			var bx := _x_costas(fx)
			var by := _y_costas(fy)
			alt_c[k] = -(espessura * 0.5 + _fundo_costas(bx, by) + clampf((luz_c[0][k] - luz_c[1][k]) * 0.7, -0.1, 0.1))
	var m := _vazio()
	_relevo(m, nx, ny, cel, x0, y0, dentro, alt_f, marca, 0.0, 1.0)
	_relevo(m, nx, ny, cel, x0, y0, dentro, alt_c, marca_c, 0.0, -1.0)
	var malha := _malha(m)
	malha.set_meta("comprimento", COMPRIMENTO)
	malha.set_meta("espessura", espessura)
	malha.set_meta("altura", y0)
	malha.set_meta("caixa_xy", Vector4(x0, 0.0, (G_X1 - meio_px) * e, y0))
	malha.set_meta("caixa_z", Vector2(-espessura * 0.5, espessura * 0.5))
	# Cabeças: meio de cada nicho (x local, y local) e a largura da placa
	var nichos: Array = []
	for r: Rect2 in NICHOS:
		nichos.append(Vector2((r.get_center().x - meio_px) * e, (M_Y1 - r.get_center().y) * e))
	malha.set_meta("nichos", nichos)
	malha.set_meta("placa", CAB_LARG * e)
	ResourceSaver.save(malha, PASTA + "muro.res")
	print("muro: %d x %d células, %d vértices, %.1f x %.1f x %.1f m" % [nx, ny, m.pos.size(), COMPRIMENTO, y0, espessura])


# ------------------------------------------------------------------ cabeça

static func _no_triangulo(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p - b).cross(a - b)
	var d2 := (p - c).cross(b - c)
	var d3 := (p - a).cross(c - a)
	return not (((d1 < 0) or (d2 < 0) or (d3 < 0)) and ((d1 > 0) or (d2 > 0) or (d3 > 0)))


## [quanto sai da placa (px da cabeça; < 0 = fora), boca (0/1)] do ponto (x, y) da arte da frente.
static func _fundo_cabeca(x: float, y: float) -> Array:
	var q := Vector2(x, y)
	var espelho := Vector2(1245.0 - x, y)   # a cabeça é simétrica (meio em x ≈ 622)
	var dentro_placa := x >= 130.0 and x <= 1115.0 and y >= 45.0 and y <= 1120.0
	var d := -1.0
	if dentro_placa:
		d = 100.0 if (x < 245.0 or x > 1000.0 or y < 100.0) else 70.0
	# Discos das orelhas: tampo chato com a borda arredondada
	for cx: float in [265.0, 990.0]:
		var r := q.distance_to(Vector2(cx, 560.0)) / 165.0
		if r < 1.0:
			d = maxf(d, 250.0 - 70.0 * smoothstep(0.75, 1.0, r))
	var na_cabeca := (x >= 270.0 and x <= 985.0 and y >= 130.0 and y <= 800.0) or (x >= 320.0 and x <= 935.0 and y >= 800.0 and y <= 1150.0)
	if not na_cabeca:
		return [d, 0]
	# Testa: sobe da placa até a sobrancelha
	var h := lerpf(360.0, 600.0, smoothstep(130.0, 290.0, y))
	# Olhos: bulbos sob a sobrancelha
	for ex: float in [415.0, 840.0]:
		var re := q.distance_to(Vector2(ex, 322.0)) / 52.0
		if re < 1.0:
			h = maxf(h, 560.0 + 50.0 * sqrt(1.0 - re * re))
	if y >= 290.0 and y < 400.0:
		h = 560.0
		for ex: float in [415.0, 840.0]:
			var re := q.distance_to(Vector2(ex, 322.0)) / 52.0
			if re < 1.0:
				h = 560.0 + 55.0 * sqrt(1.0 - re * re)
	# Focinho com as narinas
	if x >= 455.0 and x <= 800.0 and y >= 268.0 and y < 400.0:
		h = 720.0
		for nx: float in [500.0, 755.0]:
			var rn := q.distance_to(Vector2(nx, 365.0)) / 34.0
			if rn < 1.0:
				h -= 170.0 * (1.0 - rn * rn)
	# Faixa do lábio de cima (glifos)
	if y >= 400.0 and y < 540.0:
		h = 700.0 if x >= 350.0 and x <= 905.0 else 540.0
	var boca := 0
	# Bochechas por fora da boca
	if y >= 540.0 and y < 800.0:
		h = 520.0 if (x < 350.0 or x > 905.0) else h
		if x >= 350.0 and x <= 905.0:
			# Dentro da boca: fundo, paredes de dentro, língua em rampa até a frente
			h = 250.0
			boca = 1
			if x < 420.0 or x > 840.0:
				h = 430.0
			if x >= 520.0 and x <= 730.0 and y >= 670.0:
				h = lerpf(300.0, 560.0, (y - 670.0) / 220.0)
			# Dentinhos de cima e as presas
			if y < 600.0 and x >= 500.0 and x <= 760.0:
				h = 650.0
				boca = 0
			for f: Array in [[Vector2(395, 540), Vector2(470, 540), Vector2(440, 712)], [Vector2(775, 540), Vector2(865, 540), Vector2(818, 712)]]:
				if _no_triangulo(q, f[0], f[1], f[2]):
					h = 690.0 - 60.0 * (y - 540.0) / 172.0
					boca = 0
	if y >= 800.0:
		# Mandíbula: o chão dela atrás dos dentes, presas e dentinhos, e a frente com os glifos
		h = 520.0
		boca = 0
		if x >= 520.0 and x <= 730.0 and y < 890.0:
			h = lerpf(300.0, 560.0, (y - 670.0) / 220.0)
			boca = 1
		if y >= 890.0 and y < 940.0 and x >= 520.0 and x <= 720.0:
			h = 640.0
		for f: Array in [[Vector2(370, 950), Vector2(470, 950), Vector2(420, 800)], [Vector2(785, 950), Vector2(885, 950), Vector2(835, 800)]]:
			if _no_triangulo(q, f[0], f[1], f[2]):
				h = 670.0 - 50.0 * (950.0 - y) / 150.0
		if y >= 940.0:
			h = 690.0
	return [maxf(d, h), boca]


func _cabeca() -> void:
	var frente := _img("cabeca_frente.png")
	var e_muro := COMPRIMENTO / (M_X1 - M_X0)
	var s := CAB_LARG * e_muro / CAB.size.x   # m por px da cabeça
	var tf := frente.get_region(Rect2i(CAB.position, CAB.size))
	_salvar(tf, "cabeca_frente_a.png")
	_salvar(_img("cabeca_cima.png").get_region(CAB_CIMA), "cabeca_cima_a.png")
	_salvar(_img("cabeca_lado.png").get_region(CAB_LADO), "cabeca_lado_a.png")
	_salvar(frente.get_region(BOCA), "boca.png")
	var nx := int(CAB.size.x / CEL_C)
	var ny := int(ceil(CAB.size.y / CEL_C))
	var luz := _luz(tf, nx, ny, 3)
	var dentro := PackedByteArray()
	dentro.resize(nx * ny)
	var alt := PackedFloat32Array()
	alt.resize(nx * ny)
	var marca := PackedColorArray()
	marca.resize(nx * ny)
	for j in ny:
		var y := CAB.position.y + (j + 0.5) * CEL_C
		for i in nx:
			var x := CAB.position.x + (i + 0.5) * CEL_C
			var k := j * nx + i
			marca[k] = Color(1, 0, 0)
			var f := _fundo_cabeca(x, y)
			if float(f[0]) < 0.0:
				continue
			dentro[k] = 1
			marca[k] = Color(1, 0, float(f[1]))
			alt[k] = float(f[0])
	# Volume alisado (a escultura é de pedra talhada: sem a escada célula a célula nas curvas), depois o entalhe
	for passada in 3:
		var liso := alt.duplicate()
		for j in range(1, ny - 1):
			for i in range(1, nx - 1):
				var k := j * nx + i
				if dentro[k] == 0:
					continue
				var soma := alt[k] * 2.0
				var peso := 2.0
				for v: int in [k - 1, k + 1, k - nx, k + nx, k - nx - 1, k - nx + 1, k + nx - 1, k + nx + 1]:
					if dentro[v] == 1:
						soma += alt[v]
						peso += 1.0
				liso[k] = soma / peso
		alt = liso
	for k in nx * ny:
		if dentro[k] == 1:
			alt[k] = (alt[k] + clampf((luz[0][k] - luz[1][k]) * 120.0, -18.0, 18.0)) * s
	var m := _vazio()
	var x0 := -CAB.size.x * 0.5 * s
	var y0 := CAB.size.y * s
	_relevo(m, nx, ny, CEL_C * s, x0, y0, dentro, alt, marca, 0.0, 1.0)
	var malha := _malha(m)
	malha.set_meta("largura", CAB.size.x * s)
	malha.set_meta("altura", y0)
	malha.set_meta("caixa_xy", Vector4(x0, 0.0, -x0, y0))
	malha.set_meta("caixa_z", Vector2(0.0, FOCINHO * s))
	malha.set_meta("boca", Vector3(0.0, (CAB.end.y - BOCA_Y) * s, 600.0 * s))
	ResourceSaver.save(malha, PASTA + "cabeca.res")
	print("cabeça: %d x %d células, %d vértices, %.2f x %.2f m, focinho %.2f m" % [nx, ny, m.pos.size(), CAB.size.x * s, y0, FOCINHO * s])
