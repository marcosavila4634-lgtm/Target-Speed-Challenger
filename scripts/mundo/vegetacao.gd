class_name Vegetacao
extends RefCounted
## Plantas do cânion geradas por código (sem arquivos de terceiros):
## - zimbro: tronco torto, galhos e cachos de folhagem (planos cruzados com textura recortada);
## - sálvia: arbusto baixo e arredondado, cinza-esverdeado;
## - capim seco: tufo de lâminas finas.
## As malhas e texturas são criadas uma vez e compartilhadas; `plantar` distribui em blocos
## (MultiMesh por bloco) com alcance de visibilidade, para o custo cair com a distância.

enum Tipo { ZIMBRO, SALVIA, CAPIM }

static var _malhas := {}      # Tipo -> Array[ArrayMesh] (variações)
static var _materiais := {}   # Tipo -> ShaderMaterial


static func malhas(tipo: Tipo) -> Array:
	if not _malhas.has(tipo):
		var lista := []
		var rng := RandomNumberGenerator.new()
		rng.seed = 900 + tipo
		for i in 3:
			match tipo:
				Tipo.ZIMBRO: lista.append(_zimbro(rng))
				Tipo.SALVIA: lista.append(_salvia(rng))
				Tipo.CAPIM: lista.append(_capim(rng))
		_malhas[tipo] = lista
	return _malhas[tipo]


static func material(tipo: Tipo) -> ShaderMaterial:
	if not _materiais.has(tipo):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/folhagem.gdshader")
		match tipo:
			Tipo.ZIMBRO:
				m.set_shader_parameter("folhas", _textura_folhas(Color(0.16, 0.24, 0.12), Color(0.34, 0.42, 0.22), 11, false))
				m.set_shader_parameter("rigidez", 6.0)
				m.set_shader_parameter("vento", 0.6)
			Tipo.SALVIA:
				m.set_shader_parameter("folhas", _textura_folhas(Color(0.36, 0.4, 0.3), Color(0.62, 0.64, 0.5), 23, false))
				m.set_shader_parameter("rigidez", 1.2)
				m.set_shader_parameter("vento", 0.5)
			Tipo.CAPIM:
				m.set_shader_parameter("folhas", _textura_folhas(Color(0.55, 0.47, 0.24), Color(0.8, 0.72, 0.42), 37, true))
				m.set_shader_parameter("rigidez", 0.8)
				m.set_shader_parameter("vento", 1.4)
		_materiais[tipo] = m
	return _materiais[tipo]


## Distribui `pontos` ([posição, escala, rotação, tinta]) em blocos quadrados de `bloco` metros,
## um MultiMeshInstance3D por bloco e variação, visível até `alcance`.
static func plantar(pai: Node, tipo: Tipo, pontos: Array, bloco: float, alcance: float, sombra: bool) -> void:
	var variacoes := malhas(tipo)
	var grupos := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + tipo
	for p: Array in pontos:
		var pos: Vector3 = p[0]
		var chave := Vector3i(floori(pos.x / bloco), rng.randi() % variacoes.size(), floori(pos.z / bloco))
		if not grupos.has(chave):
			grupos[chave] = []
		grupos[chave].append(p)
	var mat := material(tipo)
	for chave: Vector3i in grupos:
		var itens: Array = grupos[chave]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = variacoes[chave.y]
		mm.instance_count = itens.size()
		for i in itens.size():
			var it: Array = itens[i]
			var e: float = it[1]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, it[2]).scaled(Vector3(e, e, e)), it[0]))
			mm.set_instance_custom_data(i, it[3])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = alcance
		mmi.visibility_range_end_margin = alcance * 0.15
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		pai.add_child(mmi)


# ------------------------------------------------------------------ texturas

## Textura de folhagem com fundo transparente: muitos raminhos/folhas pequenas (ou lâminas de capim)
## em dois tons, mais densos no centro para o cacho parecer volumoso.
static func _textura_folhas(escura: Color, clara: Color, semente: int, laminas: bool) -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(escura.r, escura.g, escura.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	if laminas:
		for i in 40:
			var x0 := rng.randf_range(0.3, 0.7) * n
			var topo := rng.randf_range(0.05, 0.6) * n
			var curva := rng.randf_range(-0.3, 0.3) * n
			var largura := rng.randf_range(1.2, 2.6)
			var c := escura.lerp(clara, rng.randf())
			for y in range(int(topo), n):
				var t := (y - topo) / (n - topo)   # 0 no topo, 1 na base
				var x := x0 + curva * (1.0 - t) * (1.0 - t)
				var w := largura * (0.25 + 0.75 * t)
				var sombra := lerpf(1.0, 0.55, t)
				for dx in range(int(-w), int(w) + 1):
					var px := int(x) + dx
					if px >= 0 and px < n:
						img.set_pixel(px, y, Color(c.r * sombra, c.g * sombra, c.b * sombra, 1.0))
	else:
		for i in 900:
			var ang := rng.randf() * TAU
			var raio := pow(rng.randf(), 0.7) * 0.46 * n
			var cx := n * 0.5 + cos(ang) * raio
			var cy := n * 0.5 + sin(ang) * raio * 0.85
			var borda := raio / (0.46 * n)
			var c := escura.lerp(clara, clampf(rng.randf() * 0.7 + (1.0 - cy / n) * 0.4, 0.0, 1.0))
			c = c.darkened(0.25 * (1.0 - borda))   # miolo do cacho mais escuro
			var rx := rng.randf_range(2.0, 5.0)
			var ry := rng.randf_range(4.0, 9.0)
			var giro := rng.randf() * PI
			var co := cos(giro)
			var si := sin(giro)
			var lim := int(maxf(rx, ry)) + 1
			for dy in range(-lim, lim + 1):
				for dx in range(-lim, lim + 1):
					var u := (dx * co + dy * si) / rx
					var v := (-dx * si + dy * co) / ry
					if u * u + v * v <= 1.0:
						var px := int(cx) + dx
						var py := int(cy) + dy
						if px >= 0 and px < n and py >= 0 and py < n:
							img.set_pixel(px, py, Color(c.r, c.g, c.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ malhas

## Plano de folhagem (quad) com UV completa, normal "esférica" (para o cacho ter volume) e oclusão por altura.
static func _cartao(st: SurfaceTool, centro: Vector3, direita: Vector3, cima: Vector3, centro_planta: Vector3, oclusao := 1.0) -> void:
	var cantos := [centro - direita + cima, centro + direita + cima, centro + direita - cima, centro - direita - cima]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for k in [0, 1, 2, 0, 2, 3]:
		var p: Vector3 = cantos[k]
		var nrm := (p - centro_planta + Vector3.UP * 0.5).normalized()
		var ao := clampf(oclusao * (0.65 + 0.35 * clampf((p.y - centro_planta.y) / maxf(cima.length() * 2.0, 0.5) + 0.5, 0.0, 1.0)), 0.3, 1.0)
		st.set_normal(nrm)
		st.set_color(Color(ao, ao, ao))
		st.set_uv(uvs[k])
		st.set_uv2(Vector2(0, 0))
		st.add_vertex(p)


## Cacho: três planos cruzados (60°) de tamanho `tam`, levemente inclinados.
static func _cacho(st: SurfaceTool, centro: Vector3, tam: float, rng: RandomNumberGenerator, centro_planta: Vector3, oclusao := 1.0) -> void:
	var giro := rng.randf() * PI
	for k in 3:
		var a := giro + k * PI / 3.0
		var dir := Vector3(cos(a), 0.0, sin(a)) * tam * 0.5
		var cima := Vector3(rng.randf_range(-0.15, 0.15), 1.0, rng.randf_range(-0.15, 0.15)).normalized() * tam * 0.42
		_cartao(st, centro, dir, cima, centro_planta, oclusao)
	# Plano horizontal para o cacho não "sumir" visto de cima
	var d1 := Vector3(cos(giro), 0.0, sin(giro)) * tam * 0.45
	var d2 := Vector3(-sin(giro), 0.0, cos(giro)) * tam * 0.45
	_cartao(st, centro + Vector3.UP * tam * 0.05, d1, d2, centro_planta, oclusao)


## Galho/tronco: cilindro afunilado de a até b (6 lados), marcado como tronco (UV2.x = 1).
static func _galho(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var eixo := (b - a).normalized()
	var ref := Vector3.RIGHT if absf(eixo.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var u := eixo.cross(ref).normalized()
	var w := eixo.cross(u).normalized()
	var lados := 6
	for i in lados:
		var t0 := TAU * i / lados
		var t1 := TAU * (i + 1) / lados
		var n0 := u * cos(t0) + w * sin(t0)
		var n1 := u * cos(t1) + w * sin(t1)
		var q := [[a + n0 * r0, n0, 0.55], [a + n1 * r0, n1, 0.55], [b + n1 * r1, n1, 0.9], [b + n0 * r1, n0, 0.9]]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(q[k][1])
			var ao: float = q[k][2]
			st.set_color(Color(ao, ao, ao))
			st.set_uv(Vector2.ZERO)
			st.set_uv2(Vector2(1, 0))
			st.add_vertex(q[k][0])


## Zimbro (juniper) de ~5 m: tronco torto que se divide em galhos, cachos nas pontas e na copa.
static func _zimbro(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(3.8, 5.2)
	var topo_tronco := Vector3(rng.randf_range(-0.4, 0.4), altura * 0.45, rng.randf_range(-0.4, 0.4))
	var meio := Vector3(topo_tronco.x * 0.4 + rng.randf_range(-0.2, 0.2), altura * 0.22, topo_tronco.z * 0.4)
	_galho(st, Vector3.ZERO, meio, 0.26, 0.2)
	_galho(st, meio, topo_tronco, 0.2, 0.14)
	var centro_copa := Vector3(topo_tronco.x, altura * 0.62, topo_tronco.z)
	var pontas: Array[Vector3] = []
	var n_galhos := rng.randi_range(4, 6)
	for g in n_galhos:
		var a := TAU * g / n_galhos + rng.randf_range(-0.4, 0.4)
		var alcance := rng.randf_range(0.9, 1.7)
		var fim := topo_tronco + Vector3(cos(a) * alcance, rng.randf_range(0.5, 1.6), sin(a) * alcance)
		_galho(st, topo_tronco, fim, 0.12, 0.05)
		pontas.append(fim)
	# Cachos: um por ponta de galho + alguns preenchendo a copa (mais escuros por dentro)
	for p in pontas:
		_cacho(st, p + Vector3.UP * 0.2, rng.randf_range(1.5, 2.2), rng, centro_copa)
	for i in 5:
		var q := centro_copa + Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(-0.6, 1.1), rng.randf_range(-0.9, 0.9))
		_cacho(st, q, rng.randf_range(1.4, 2.0), rng, centro_copa, 0.8)
	_cacho(st, centro_copa + Vector3.UP * rng.randf_range(1.2, 1.6), 1.4, rng, centro_copa)
	return st.commit()


## Sálvia: 5–8 cachos baixos formando um arbusto arredondado de ~1 m.
static func _salvia(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centro := Vector3(0, 0.45, 0)
	for i in rng.randi_range(2, 3):
		var a := rng.randf() * TAU
		_galho(st, Vector3.ZERO, Vector3(cos(a) * 0.3, 0.45, sin(a) * 0.3), 0.04, 0.02)
	for i in rng.randi_range(5, 8):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.45)
		var p := Vector3(cos(a) * r, rng.randf_range(0.3, 0.7), sin(a) * r)
		_cacho(st, p, rng.randf_range(0.7, 1.05), rng, centro, 0.9)
	return st.commit()


## Capim: 3–4 planos cruzados com a textura de lâminas, base no chão.
static func _capim(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(0.5, 0.8)
	var giro := rng.randf() * PI
	var n := rng.randi_range(3, 4)
	for k in n:
		var a := giro + k * PI / n
		var dir := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.35, 0.5)
		var inclinado := Vector3(rng.randf_range(-0.1, 0.1), 1.0, rng.randf_range(-0.1, 0.1)).normalized() * altura * 0.5
		_cartao(st, inclinado, dir, inclinado, Vector3.ZERO)
	return st.commit()
