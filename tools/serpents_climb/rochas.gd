extends SceneTree
## Rochas gigantes do Serpent's Climb pelas artes do dono (assets/MAPA SERPENTE/morro). Cada rocha é um sólido
## de verdade, não uma placa:
## - o fundo de cada vista é recortado (rocha1 = frente, rocha de lado, rocha de cima; a folha de 4 ângulos dá
##   os rochedos cinzentos, um quadro por vista);
## - o volume é o que cabe nas três silhuetas ao mesmo tempo (frente: x,y; lado: z,y; cima: x,z), medido raio a
##   raio a partir do meio e alisado; o relevo das fendas e blocos sai do claro-escuro da arte (a malha anda
##   para dentro nas fendas e para fora nos blocos claros);
## - a pele é a própria arte projetada por cada vista (shaders/rocha_arte.gdshader mistura as três pela
##   direção da face): nenhuma face é a imagem esticada, a de trás é a frente espelhada.
## Saída: assets/selva/rochas/<nome>_frente|_lado|_cima.png (recortadas, sem a luz do estúdio) e <nome>.res.
## Uso: Godot --headless --path . -s tools/serpents_climb/rochas.gd

const ORIGEM := "res://assets/MAPA SERPENTE/morro/"
const PASTA := "res://assets/selva/rochas/"
const N := 48            # divisões de cada face do cubo que vira a esfera da malha
const RELEVO := 0.035    # relevo máximo (fração do tamanho da rocha)

## [nome, [arquivo, região (vazio = toda)] para frente, lado e cima]
const ROCHAS := [
	["laranja", ["rocha1.png", []], ["rocha de lado.png", []], ["rocha de cima.png", []]],
	["penhasco_a", ["rochadiferente angulos.png", [0, 0, 768, 512]], ["rochadiferente angulos.png", [0, 512, 768, 512]], ["rochadiferente angulos.png", [768, 0, 768, 512]]],
	["penhasco_b", ["rochadiferente angulos.png", [768, 512, 768, 512]], ["rochadiferente angulos.png", [0, 0, 768, 512]], ["rochadiferente angulos.png", [768, 0, 768, 512]]],
	["penhasco_c", ["rochadiferente angulos.png", [0, 512, 768, 512]], ["rochadiferente angulos.png", [768, 512, 768, 512]], ["rochadiferente angulos.png", [768, 0, 768, 512]]],
	["laranja_b", ["rocha de lado.png", []], ["rocha1.png", []], ["rocha de cima.png", []]],
	["montanha_armadilha", ["rocha gigante com armadilha/rocah gigante armadilha frente.png", []], ["rocha gigante com armadilha/angulo 2 da rocha gidante da armadilha.png", []], ["rocha gigante com armadilha/angulo de cima da rocha gigante.png", []]],
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PASTA))
	var so := OS.get_environment("ROCHA")
	for r in ROCHAS:
		if so == "" or so == r[0]:
			_rocha(r[0], r[1], r[2], r[3])
	quit()


# ------------------------------------------------------------------ recorte

## Vista recortada: {img (RGBA, fundo transparente, luz do estúdio tirada), mask (PackedByteArray), w, h,
## caixa (Rect2i da rocha), alt (altura do relevo -1..1)}.
func _vista(arq: String, reg: Array) -> Dictionary:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ORIGEM + arq))
	img.convert(Image.FORMAT_RGBA8)
	if not reg.is_empty():
		img = img.get_region(Rect2i(reg[0], reg[1], reg[2], reg[3]))
	# Trabalha em até 640 px de largura
	var esc := minf(1.0, float(OS.get_environment("LARGURA_MAX")) / img.get_width() if OS.get_environment("LARGURA_MAX") != "" else 640.0 / img.get_width())
	img.resize(int(img.get_width() * esc), int(img.get_height() * esc), Image.INTERPOLATE_LANCZOS)
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var lum := PackedFloat32Array()
	lum.resize(w * h)
	for i in w * h:
		lum[i] = (0.3 * d[i * 4] + 0.59 * d[i * 4 + 1] + 0.11 * d[i * 4 + 2]) / 255.0
	# Fundo liso (cinza de estúdio ou degradê): pouca variação local e cor perto da das bordas
	var fundo := Color(0, 0, 0)
	var nb := 0
	for x in w:
		for y in [2, h - 3]:
			fundo += img.get_pixel(x, y)
			nb += 1
	for y in h:
		for x in [2, w - 3]:
			fundo += img.get_pixel(x, y)
			nb += 1
	fundo /= nb
	var var_l := PackedFloat32Array()
	var_l.resize(w * h)
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var s := 0.0
			var s2 := 0.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var v := lum[(y + dy) * w + x + dx]
					s += v
					s2 += v * v
			var_l[y * w + x] = sqrt(maxf(s2 / 25.0 - (s / 25.0) * (s / 25.0), 0.0))
	# Fundo em degradê (folha de 4 ângulos): só a textura conta, a cor do fundo muda de canto a canto
	var degrade := 0.0
	for y in [2, h - 3]:
		degrade = maxf(degrade, absf(lum[y * w + 2] - lum[y * w + w / 2]) + absf(lum[y * w + w - 3] - lum[y * w + w / 2]))
	degrade = 1.0 if degrade > 0.12 else 0.0
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			var i := y * w + x
			var c := Color(d[i * 4] / 255.0, d[i * 4 + 1] / 255.0, d[i * 4 + 2] / 255.0)
			var dist := absf(c.r - fundo.r) + absf(c.g - fundo.g) + absf(c.b - fundo.b)
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			mask[i] = 1 if var_l[i] > 0.03 or (dist > 0.12 and degrade < 0.5) else 0
	# Arte já recortada (fundo transparente): o alfa dela é o recorte
	var transparente := 0
	for x in w:
		if d[x * 4 + 3] < 128:
			transparente += 1
	if transparente > w / 4:
		for i in w * h:
			mask[i] = 1 if d[i * 4 + 3] >= 250 and var_l[i] > 0.012 else 0
	mask = _fechar(mask, w, h, 4)
	mask = _abrir(mask, w, h, 4)
	mask = _maior_e_cheio(mask, w, h)
	mask = _abrir(mask, w, h, 2)
	# Caixa
	var x0 := w
	var y0 := h
	var x1 := 0
	var y1 := 0
	for y in h:
		for x in w:
			if mask[y * w + x]:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	# Luz do estúdio tirada (divide pela média grande), relevo pelo claro-escuro fino
	var largo := _borrado(lum, w, h, 24)
	var medio := _borrado(lum, w, h, 5)
	var alt := PackedFloat32Array()
	alt.resize(w * h)
	var saida := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			var k := clampf(pow(0.42 / maxf(largo[i], 0.05), 0.55), 0.7, 1.8)
			var c := Color(d[i * 4] / 255.0 * k, d[i * 4 + 1] / 255.0 * k, d[i * 4 + 2] / 255.0 * k, 1.0 if mask[i] else 0.0)
			saida.set_pixel(x, y, c)
			alt[i] = clampf((medio[i] - largo[i]) * 3.0 + (lum[i] - medio[i]) * 1.5, -1.0, 1.0)
	# Borda: a cor de dentro escorre para fora do recorte (o mipmap não traz o fundo cinza para a borda)
	for passada in 6:
		var copia := saida.duplicate()
		for y in range(1, h - 1):
			for x in range(1, w - 1):
				if copia.get_pixel(x, y).a > 0.5:
					continue
				var soma := Color(0, 0, 0, 0)
				var n := 0
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Color = copia.get_pixel(x + o.x, y + o.y)
					if q.a > 0.5:
						soma += q
						n += 1
				if n > 0:
					saida.set_pixel(x, y, Color(soma.r / n, soma.g / n, soma.b / n, 0.6))
	return {"img": saida, "mask": mask, "w": w, "h": h, "caixa": Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1), "alt": alt}


func _borrado(v: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var a := v.duplicate()
	for eixo in 2:
		var b := a.duplicate()
		var n_lin := w if eixo == 0 else h
		var n_out := h if eixo == 0 else w
		for o in n_out:
			var soma := 0.0
			var conta := 0
			for t in range(-r, n_lin + r):
				var ent := t + r
				if ent < n_lin:
					soma += b[(o * w + ent) if eixo == 0 else (ent * w + o)]
					conta += 1
				var sai := t - r - 1
				if sai >= 0:
					soma -= b[(o * w + sai) if eixo == 0 else (sai * w + o)]
					conta -= 1
				if t >= 0 and t < n_lin:
					a[(o * w + t) if eixo == 0 else (t * w + o)] = soma / maxi(conta, 1)
	return a


func _dilatar(m: PackedByteArray, w: int, h: int, r: int, valor: int) -> PackedByteArray:
	var s := m.duplicate()
	for y in h:
		for x in w:
			if m[y * w + x] == valor:
				continue
			var achou := false
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var xx := x + dx
					var yy := y + dy
					if xx >= 0 and xx < w and yy >= 0 and yy < h and m[yy * w + xx] == valor:
						achou = true
						break
				if achou:
					break
			if achou:
				s[y * w + x] = valor
	return s


func _fechar(m: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	return _dilatar(_dilatar(m, w, h, r, 1), w, h, r, 0)


func _abrir(m: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	return _dilatar(_dilatar(m, w, h, r, 0), w, h, r, 1)


## Só o maior pedaço, com os buracos de dentro preenchidos.
func _maior_e_cheio(m: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var rot := PackedInt32Array()
	rot.resize(w * h)
	rot.fill(-1)
	var melhor := -1
	var melhor_n := 0
	var id := 0
	for i in w * h:
		if m[i] == 0 or rot[i] >= 0:
			continue
		var pilha := [i]
		rot[i] = id
		var n := 0
		while not pilha.is_empty():
			var j: int = pilha.pop_back()
			n += 1
			var x := j % w
			var y := j / w
			for o in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var xx: int = x + o[0]
				var yy: int = y + o[1]
				if xx >= 0 and xx < w and yy >= 0 and yy < h:
					var k := yy * w + xx
					if m[k] and rot[k] < 0:
						rot[k] = id
						pilha.append(k)
		if n > melhor_n:
			melhor_n = n
			melhor = id
		id += 1
	# Fundo alcançável pela borda
	var fora := PackedByteArray()
	fora.resize(w * h)
	var pilha2: Array = []
	for x in w:
		pilha2.append(x)
		pilha2.append((h - 1) * w + x)
	for y in h:
		pilha2.append(y * w)
		pilha2.append(y * w + w - 1)
	while not pilha2.is_empty():
		var j: int = pilha2.pop_back()
		if fora[j] or rot[j] == melhor:
			continue
		fora[j] = 1
		var x := j % w
		var y := j / w
		if x > 0: pilha2.append(j - 1)
		if x < w - 1: pilha2.append(j + 1)
		if y > 0: pilha2.append(j - w)
		if y < h - 1: pilha2.append(j + w)
	var s := PackedByteArray()
	s.resize(w * h)
	for i in w * h:
		s[i] = 0 if fora[i] else 1
	return s


# ------------------------------------------------------------------ volume

## Ponto (u, v) normalizado na caixa da vista (u, v em -1..1 / 0..1) está na rocha?
func _dentro(vista: Dictionary, u: float, v: float) -> bool:
	var c: Rect2i = vista.caixa
	var x := int(c.position.x + (u * 0.5 + 0.5) * (c.size.x - 1))
	var y := int(c.position.y + v * (c.size.y - 1))
	if x < 0 or y < 0 or x >= int(vista.w) or y >= int(vista.h):
		return false
	return (vista.mask as PackedByteArray)[y * int(vista.w) + x] == 1


func _alt(vista: Dictionary, u: float, v: float) -> float:
	var c: Rect2i = vista.caixa
	var x := clampi(int(c.position.x + (u * 0.5 + 0.5) * (c.size.x - 1)), 0, int(vista.w) - 1)
	var y := clampi(int(c.position.y + v * (c.size.y - 1)), 0, int(vista.h) - 1)
	return (vista.alt as PackedFloat32Array)[y * int(vista.w) + x]


func _rocha(nome: String, a_f: Array, a_l: Array, a_c: Array) -> void:
	var f := _vista(a_f[0], a_f[1])
	var l := _vista(a_l[0], a_l[1])
	var c := _vista(a_c[0], a_c[1])
	for par in [["frente", f], ["lado", l], ["cima", c]]:
		var v: Dictionary = par[1]
		var cx: Rect2i = v.caixa
		(v.img as Image).get_region(cx).save_png(ProjectSettings.globalize_path(PASTA + nome + "_" + par[0] + ".png"))
	# Medidas: x em -1..1 (largura da frente); altura Y pela proporção da frente; z em -D..D pela proporção do lado
	var cf: Rect2i = f.caixa
	var cl: Rect2i = l.caixa
	var Y := 2.0 * float(cf.size.y) / cf.size.x
	var D := Y * float(cl.size.x) / cl.size.y * 0.5
	# Coordenadas normalizadas de cada vista para um ponto (x, y, z): frente (x, 1 - y/Y), lado (z/D, 1 - y/Y),
	# cima (x, z/D) — o alto da imagem de cima é o fundo (-z)
	var dentro := func(p: Vector3) -> bool:
		if p.y < 0.0 or p.y > Y:
			return false
		var vv := 1.0 - p.y / Y
		return _dentro(f, p.x, vv) and _dentro(l, p.z / D, vv) and _dentro(c, p.x, (p.z / D) * 0.5 + 0.5)
	var centro := Vector3(0.0, Y * 0.42, 0.0)
	# Esfera de cubo: raio até a borda do volume em cada direção (busca binária), depois alisado
	var dirs := PackedVector3Array()
	var raios := PackedFloat32Array()
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD], [Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT], [Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for fc in faces:
		var nrm: Vector3 = fc[0]
		var a: Vector3 = fc[1]
		var b: Vector3 = fc[2]
		for i in N + 1:
			for j in N + 1:
				var s := float(i) / N * 2.0 - 1.0
				var t := float(j) / N * 2.0 - 1.0
				var d := (nrm + a * s + b * t).normalized()
				dirs.append(d)
				var lo := 0.0
				var hi := 3.0 * maxf(Y, maxf(1.0, D))
				for k in 22:
					var m := (lo + hi) * 0.5
					if dentro.call(centro + d * m):
						lo = m
					else:
						hi = m
				raios.append(lo)
	# Alisa os raios entre vizinhos da mesma face (tira o serrilhado do recorte)
	var por_face := (N + 1) * (N + 1)
	for passada in 3:
		var r2 := raios.duplicate()
		for fi in 6:
			for i in range(1, N):
				for j in range(1, N):
					var k := fi * por_face + i * (N + 1) + j
					r2[k] = raios[k] * 0.4 + (raios[k - 1] + raios[k + 1] + raios[k - N - 1] + raios[k + N + 1]) * 0.15
		raios = r2
	# Relevo pela arte: frente/lado/cima pela direção (o mesmo jeito que a pele é posta)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pos := PackedVector3Array()
	pos.resize(dirs.size())
	for k in dirs.size():
		var d := dirs[k]
		var p := centro + d * raios[k]
		var w := Vector3(pow(absf(d.x), 3.0), pow(absf(d.y), 3.0), pow(absf(d.z), 3.0))
		w /= (w.x + w.y + w.z)
		var vv := clampf(1.0 - p.y / Y, 0.0, 1.0)
		var hgt := _alt(f, p.x * (1.0 if d.z >= 0.0 else -1.0), vv) * w.z + _alt(l, p.z / D * (1.0 if d.x >= 0.0 else -1.0), vv) * w.x + _alt(c, p.x, (p.z / D) * 0.5 + 0.5) * w.y
		pos[k] = p + d * hgt * RELEVO * maxf(Y, 2.0)
	for fi in 6:
		for i in N:
			for j in N:
				var k0 := fi * por_face + i * (N + 1) + j
				var q: Array = [k0, k0 + 1, k0 + N + 2, k0 + N + 1]
				var tri: Array = [[0, 1, 2], [0, 2, 3]]
				for t3 in tri:
					var ia: int = q[t3[0]]
					var ib: int = q[t3[1]]
					var ic: int = q[t3[2]]
					var nn := (pos[ib] - pos[ia]).cross(pos[ic] - pos[ia])
					var fora := (pos[ia] + pos[ib] + pos[ic]) / 3.0 - centro
					if nn.dot(fora) > 0.0:   # frente do Godot: produto vetorial para dentro
						var tmp := ib
						ib = ic
						ic = tmp
					for idx in [ia, ib, ic]:
						st.add_vertex(pos[idx])
	st.index()
	st.generate_normals()
	var malha := st.commit()
	malha.set_meta("Y", Y)
	malha.set_meta("D", D)
	ResourceSaver.save(malha, PASTA + nome + ".res")
	print("pronto %s  Y %.2f  D %.2f  verts %d" % [nome, Y, D, malha.surface_get_array_len(0)])
	print("  (depois: rodar tools/serpents_climb/rochas_lod.gd para os LODs e a colisão leve)")
