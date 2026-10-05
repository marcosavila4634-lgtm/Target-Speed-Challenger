class_name Vegetacao
extends RefCounted
## Plantas do cânion geradas por código (sem arquivos de terceiros):
## - zimbro: tronco torto, galhos e cachos de folhagem (planos cruzados com textura recortada);
## - sálvia: arbusto baixo e arredondado, cinza-esverdeado;
## - capim seco: tufo de lâminas finas.
## As malhas e texturas são criadas uma vez e compartilhadas; `plantar` distribui em blocos
## (MultiMesh por bloco) com alcance de visibilidade, para o custo cair com a distância.

enum Tipo { ZIMBRO, SALVIA, CAPIM, PALMEIRA, SUMAUMA, COPA, PALMEIRA_SELVA, BANANEIRA, SAMAMBAIA, PINHEIRO, SEQUOIA, ARAUCARIA, FETO, CICA, ARAUCARIA_GELO, SEQUOIA_QUEBRADA }

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
				Tipo.PALMEIRA, Tipo.PALMEIRA_SELVA: lista.append(_palmeira(rng))
				Tipo.SUMAUMA: lista.append(_sumauma(rng))
				Tipo.COPA: lista.append(_copa(rng))
				Tipo.BANANEIRA: lista.append(_bananeira(rng))
				Tipo.SAMAMBAIA: lista.append(_samambaia(rng))
				Tipo.PINHEIRO: lista.append(_pinheiro(rng))
				Tipo.SEQUOIA: lista.append(_sequoia(rng))
				Tipo.ARAUCARIA: lista.append(_araucaria(rng))
				Tipo.FETO: lista.append(_feto(rng))
				Tipo.CICA: lista.append(_cica(rng))
				Tipo.ARAUCARIA_GELO: lista.append(_araucaria_gelo(rng))
				Tipo.SEQUOIA_QUEBRADA: lista.append(_sequoia_quebrada(rng, i))
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
			Tipo.PALMEIRA:
				m.set_shader_parameter("folhas", _textura_fronde(Color(0.13, 0.25, 0.08), Color(0.42, 0.5, 0.18), 53))
				m.set_shader_parameter("cor_tronco", Color(0.42, 0.33, 0.22))
				m.set_shader_parameter("rigidez", 9.0)
				m.set_shader_parameter("vento", 0.9)
			Tipo.PALMEIRA_SELVA:
				m.set_shader_parameter("folhas", _textura_fronde(Color(0.06, 0.22, 0.05), Color(0.3, 0.52, 0.12), 59))
				m.set_shader_parameter("cor_tronco", Color(0.4, 0.37, 0.32))
				m.set_shader_parameter("rigidez", 9.0)
				m.set_shader_parameter("vento", 0.7)
			Tipo.SUMAUMA:
				m.set_shader_parameter("folhas", _textura_folhas_largas(Color(0.05, 0.17, 0.04), Color(0.27, 0.46, 0.12), 61))
				m.set_shader_parameter("cor_tronco", Color(0.52, 0.48, 0.42))
				m.set_shader_parameter("rigidez", 30.0)
				m.set_shader_parameter("vento", 0.5)
			Tipo.COPA:
				m.set_shader_parameter("folhas", _textura_folhas_largas(Color(0.07, 0.2, 0.05), Color(0.36, 0.55, 0.16), 67))
				m.set_shader_parameter("cor_tronco", Color(0.36, 0.3, 0.24))
				m.set_shader_parameter("rigidez", 16.0)
				m.set_shader_parameter("vento", 0.5)
			Tipo.BANANEIRA:
				m.set_shader_parameter("folhas", _textura_folha_banana(71))
				m.set_shader_parameter("cor_tronco", Color(0.33, 0.42, 0.18))
				m.set_shader_parameter("rigidez", 4.0)
				m.set_shader_parameter("vento", 0.8)
			Tipo.SAMAMBAIA:
				m.set_shader_parameter("folhas", _textura_fronde(Color(0.08, 0.26, 0.05), Color(0.38, 0.62, 0.16), 73))
				m.set_shader_parameter("rigidez", 1.5)
				m.set_shader_parameter("vento", 0.7)
			Tipo.PINHEIRO:
				m.set_shader_parameter("folhas", _textura_ramo_nevado(83))
				m.set_shader_parameter("cor_tronco", Color(0.3, 0.23, 0.18))
				m.set_shader_parameter("rigidez", 16.0)
				m.set_shader_parameter("vento", 0.45)
			Tipo.SEQUOIA:
				m.set_shader_parameter("folhas", _textura_ramo_verde(89, Color(0.04, 0.12, 0.05), Color(0.16, 0.32, 0.12)))
				m.set_shader_parameter("cor_tronco", Color(0.5, 0.25, 0.14))
				m.set_shader_parameter("casca", 1.0)
				m.set_shader_parameter("rigidez", 70.0)
				m.set_shader_parameter("vento", 0.35)
			Tipo.ARAUCARIA:
				m.set_shader_parameter("folhas", _textura_ramo_verde(97, Color(0.03, 0.1, 0.05), Color(0.13, 0.27, 0.1)))
				m.set_shader_parameter("cor_tronco", Color(0.36, 0.3, 0.25))
				m.set_shader_parameter("casca", 0.6)
				m.set_shader_parameter("rigidez", 45.0)
				m.set_shader_parameter("vento", 0.4)
			Tipo.FETO:
				m.set_shader_parameter("folhas", _textura_fronde(Color(0.05, 0.2, 0.05), Color(0.32, 0.55, 0.15), 101))
				m.set_shader_parameter("cor_tronco", Color(0.2, 0.15, 0.1))
				m.set_shader_parameter("casca", 0.8)
				m.set_shader_parameter("rigidez", 6.0)
				m.set_shader_parameter("vento", 0.7)
			Tipo.CICA:
				m.set_shader_parameter("folhas", _textura_fronde(Color(0.04, 0.16, 0.04), Color(0.22, 0.4, 0.1), 107))
				m.set_shader_parameter("cor_tronco", Color(0.3, 0.24, 0.15))
				m.set_shader_parameter("casca", 1.0)
				m.set_shader_parameter("rigidez", 2.5)
				m.set_shader_parameter("vento", 0.35)
			Tipo.ARAUCARIA_GELO:
				m.set_shader_parameter("folhas", _textura_ramo_nevado(113))
				m.set_shader_parameter("cor_tronco", Color(0.4, 0.36, 0.34))
				m.set_shader_parameter("casca", 0.6)
				m.set_shader_parameter("rigidez", 55.0)
				m.set_shader_parameter("vento", 0.3)
			Tipo.SEQUOIA_QUEBRADA:
				# A mesma casca da sequoia; os ramos que sobraram na copa caída estão secos
				m.set_shader_parameter("folhas", _textura_ramo_verde(127, Color(0.13, 0.09, 0.04), Color(0.36, 0.26, 0.1)))
				m.set_shader_parameter("cor_tronco", Color(0.46, 0.24, 0.14))
				m.set_shader_parameter("casca", 1.0)
				m.set_shader_parameter("rigidez", 200.0)
				m.set_shader_parameter("vento", 0.1)
		_materiais[tipo] = m
	return _materiais[tipo]


const BLOCO_SOMBRA := 300.0   # lado máximo (m) dos blocos de plantas que projetam sombra

## Distribui `pontos` ([posição, escala, rotação, tinta]) em blocos quadrados de `bloco` metros,
## um MultiMeshInstance3D por bloco e variação, visível até `alcance`. Com `sombra`, só projeta sombra até
## grafico.sombra_vegetacao_distancia da câmera (as sombras da vegetação eram 2/3 dos triângulos do quadro).
static func plantar(pai: Node, tipo: Tipo, pontos: Array, bloco: float, alcance: float, sombra: bool) -> void:
	var d_sombra := float(Config.grafico("sombra_vegetacao_distancia", 450.0))
	# Qualidade gráfica mais baixa planta só uma fração das plantas (sorteio fixo: sempre as mesmas)
	var fracao := float(Config.grafico("vegetacao", 1.0))
	if fracao < 0.999:
		var corte := RandomNumberGenerator.new()
		corte.seed = 4099 + tipo
		pontos = pontos.filter(func(_p): return corte.randf() < fracao)
	if sombra and d_sombra > 0.0:
		bloco = minf(bloco, BLOCO_SOMBRA)   # bloco grande levaria o corte da sombra para longe (mede-se até o meio dele)
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
		if not sombra or d_sombra <= 0.0:
			continue
		# Sombra só de perto: a distância é medida até o meio do bloco, então soma o raio dele (toda planta a
		# menos de d_sombra da câmera continua com sombra). Além disso, o mesmo bloco é desenhado sem sombra.
		var caixa := AABB(itens[0][0], Vector3.ZERO)
		for it: Array in itens:
			caixa = caixa.expand(it[0])
		var corte := d_sombra + caixa.size.length() * 0.5
		if corte >= alcance:
			continue
		mmi.visibility_range_end = corte
		mmi.visibility_range_end_margin = 0.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		var longe := MultiMeshInstance3D.new()
		longe.multimesh = mm
		longe.material_override = mat
		longe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		longe.visibility_range_begin = corte
		longe.visibility_range_end = alcance
		longe.visibility_range_end_margin = alcance * 0.15
		longe.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		pai.add_child(longe)


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


## Folha de palmeira (tamareira): nervura no meio (v = comprimento) e folíolos finos saindo dos dois
## lados em ângulo, mais curtos nas pontas; alguns secos (amarelados).
static func _textura_fronde(escura: Color, clara: Color, semente: int) -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(escura.r, escura.g, escura.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var meio := n * 0.5
	for y in n:
		for dx in range(-2, 3):
			img.set_pixel(int(meio) + dx, y, Color(0.5, 0.45, 0.22, 1.0))
	var y := 4.0
	while y < n - 2:
		var t := y / n   # 0 = base da folha, 1 = ponta
		var comp := meio * 0.95 * sin(PI * clampf(t * 0.9 + 0.08, 0.0, 1.0))
		for lado: float in [-1.0, 1.0]:
			var c := escura.lerp(clara, rng.randf() * 0.8 + t * 0.2)
			if rng.randf() < 0.07:
				c = Color(0.62, 0.52, 0.25)   # folíolo seco
			var ang := deg_to_rad(rng.randf_range(28.0, 40.0))
			var l := comp * rng.randf_range(0.85, 1.0)
			var k := 0.0
			while k < l:
				var px := meio + lado * (3.0 + k * cos(ang))
				var py := y + k * sin(ang)
				var w := 1.6 * (1.0 - k / l) + 0.6
				for d in range(int(-w), int(w) + 1):
					var qy := int(py) + d
					if px >= 0 and px < n and qy >= 0 and qy < n:
						img.set_pixel(int(px), qy, Color(c.r, c.g, c.b, 1.0))
				k += 0.7
		y += rng.randf_range(4.5, 6.5)
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


## Tamareira de 8–14 m: tronco anelado levemente curvo (afunila pouco) e coroa de 14 folhas
## compridas arqueando para baixo, as de baixo mais caídas e as do meio apontando para cima.
static func _palmeira(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(8.0, 13.0)
	var curva := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.6, 1.8)
	var ant := Vector3.ZERO
	var segs := 7
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := Vector3.UP * altura * t + curva * t * t
		_galho(st, ant, p, lerpf(0.34, 0.24, float(i - 1) / segs), lerpf(0.34, 0.24, t))
		ant = p
	var topo := ant
	var n_folhas := 14
	for f in n_folhas:
		var a := TAU * f / n_folhas + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var camada := f % 3   # 0 = caídas, 1 = horizontais, 2 = para cima
		var sobe: float = [0.15, 0.55, 1.1][camada] + rng.randf_range(-0.1, 0.1)
		var cai: float = [1.5, 1.0, 0.6][camada]
		_fronde(st, topo, dir, rng.randf_range(4.2, 5.6), rng.randf_range(1.0, 1.3), sobe, cai)
	# Tufo central (folhas novas apontando para cima)
	for k in 3:
		var a := rng.randf() * TAU
		_fronde(st, topo, Vector3(cos(a), 0.0, sin(a)), 2.4, 0.7, 2.2, 0.3)
	return st.commit()


## Uma folha: faixa arqueada de `comp` m saindo de `base` na direção `dir`, subindo `sobe` m/m no
## começo e caindo com `cai`; a largura afunila nas pontas. UV: u atravessa a folha, v vai da base à ponta.
static func _fronde(st: SurfaceTool, base: Vector3, dir: Vector3, comp: float, larg: float, sobe: float, cai: float) -> void:
	var lado := dir.cross(Vector3.UP).normalized()
	var segs := 6
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(base + dir * comp * t + Vector3.UP * comp * (sobe * t - cai * t * t * 0.55))
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var w0 := larg * (0.35 + 0.65 * sin(PI * minf(t0 * 1.1 + 0.05, 1.0)))
		var w1 := larg * (0.35 + 0.65 * sin(PI * minf(t1 * 1.1 + 0.05, 1.0)))
		# Dobra em "V": as bordas um pouco abaixo da nervura
		var q := [pts[i] - lado * w0 - Vector3.UP * w0 * 0.25, pts[i] + lado * w0 - Vector3.UP * w0 * 0.25,
			pts[i + 1] + lado * w1 - Vector3.UP * w1 * 0.25, pts[i + 1] - lado * w1 - Vector3.UP * w1 * 0.25]
		var uv := [Vector2(0, t0), Vector2(1, t0), Vector2(1, t1), Vector2(0, t1)]
		var nrm := (pts[i + 1] - pts[i]).cross(lado).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		for k in [0, 1, 2, 0, 2, 3]:
			var ao := lerpf(0.55, 1.0, uv[k].y)
			st.set_normal((nrm + Vector3.UP * 0.4).normalized())
			st.set_color(Color(ao, ao, ao))
			st.set_uv(uv[k])
			st.set_uv2(Vector2(0, 0))
			st.add_vertex(q[k])


# ------------------------------------------------------------------ selva (Serpent's Climb)

## Folhagem de folhas largas (sumaúma, árvores de copa): folhas grandes elípticas brilhantes, com a
## nervura clara, mais densas no centro do cacho.
static func _textura_folhas_largas(escura: Color, clara: Color, semente: int) -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(escura.r, escura.g, escura.b, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	for i in 230:
		var ang := rng.randf() * TAU
		var raio := pow(rng.randf(), 0.65) * 0.44 * n
		var cx := n * 0.5 + cos(ang) * raio
		var cy := n * 0.5 + sin(ang) * raio * 0.8
		var borda := raio / (0.44 * n)
		var c := escura.lerp(clara, clampf(rng.randf() * 0.6 + (1.0 - cy / n) * 0.45, 0.0, 1.0))
		c = c.darkened(0.3 * (1.0 - borda))
		var rx := rng.randf_range(5.0, 8.0)
		var ry := rng.randf_range(11.0, 17.0)
		var giro := ang + rng.randf_range(-0.6, 0.6) + PI * 0.5
		var co := cos(giro)
		var si := sin(giro)
		var lim := int(ry) + 1
		for dy in range(-lim, lim + 1):
			for dx in range(-lim, lim + 1):
				var u := (dx * co + dy * si) / rx
				var v := (-dx * si + dy * co) / ry
				var d := u * u + v * v
				if d <= 1.0:
					var px := int(cx) + dx
					var py := int(cy) + dy
					if px >= 0 and px < n and py >= 0 and py < n:
						var k := c.lightened(0.18 * (1.0 - absf(u))) if absf(u) < 0.12 else c
						k = k.darkened(0.15 * d)
						img.set_pixel(px, py, Color(k.r, k.g, k.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Folha de bananeira inteira (u atravessa, v da base à ponta): lâmina larga com nervura central,
## nervuras paralelas e rasgos nas bordas.
static func _textura_folha_banana(semente: int) -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.25, 0.05, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var rasgos: Array[float] = []
	for k in 9:
		rasgos.append(rng.randf_range(0.15, 0.95))
	for y in n:
		var t := float(y) / n
		var meia := 0.47 * sin(PI * clampf(t * 0.95 + 0.04, 0.0, 1.0))
		for x in n:
			var u := float(x) / n - 0.5
			if absf(u) > meia:
				continue
			var rasgado := false
			for r in rasgos:
				if absf(t - r - absf(u) * 0.35) < 0.006 and absf(u) > 0.08:
					rasgado = true
			if rasgado:
				continue
			var c := Color(0.16, 0.4, 0.08).lerp(Color(0.38, 0.6, 0.14), 0.5 + 0.5 * sin(u * 9.0 + t * 3.0) * 0.4 + t * 0.3)
			if absf(u) < 0.012:
				c = Color(0.55, 0.62, 0.28)
			elif fmod(absf(u) * 120.0 + t * 30.0, 4.0) < 0.6:
				c = c.darkened(0.12)
			if absf(u) > meia - 0.02:
				c = c.lerp(Color(0.45, 0.4, 0.15), 0.5)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Sumaúma (árvore emergente da selva) de 34–46 m: tronco reto com raízes tabulares, galhos abertos
## no alto formando uma copa larga e achatada, e cipós pendurados.
static func _sumauma(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(34.0, 46.0)
	for k in 5:
		var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
		var pe := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(2.6, 3.6)
		_galho(st, pe, Vector3(cos(a) * 0.5, rng.randf_range(4.5, 6.5), sin(a) * 0.5), 0.5, 0.35)
	var topo := Vector3(rng.randf_range(-0.6, 0.6), altura * 0.74, rng.randf_range(-0.6, 0.6))
	var ant := Vector3.ZERO
	for i in range(1, 5):
		var t := float(i) / 4.0
		var p := topo * t
		_galho(st, ant, p, lerpf(1.35, 0.75, float(i - 1) / 4.0), lerpf(1.35, 0.75, t))
		ant = p
	var centro := Vector3(topo.x, altura * 0.88, topo.z)
	var pontas: Array[Vector3] = []
	var n_g := rng.randi_range(5, 7)
	for g in n_g:
		var a := TAU * g / n_g + rng.randf_range(-0.3, 0.3)
		var alcance := rng.randf_range(9.0, 14.0)
		var meio := topo + Vector3(cos(a) * alcance * 0.5, altura * 0.08, sin(a) * alcance * 0.5)
		var fim := topo + Vector3(cos(a) * alcance, altura * 0.14 + rng.randf_range(-1.0, 1.5), sin(a) * alcance)
		_galho(st, topo, meio, 0.55, 0.35)
		_galho(st, meio, fim, 0.35, 0.15)
		pontas.append(fim)
		pontas.append(meio + Vector3(0, 1.5, 0))
		# Cipós caindo do galho
		if rng.randf() < 0.8:
			var pend := meio.lerp(fim, rng.randf_range(0.2, 0.9))
			var queda := rng.randf_range(10.0, 22.0)
			_galho(st, pend, pend + Vector3(rng.randf_range(-0.8, 0.8), -queda, rng.randf_range(-0.8, 0.8)), 0.07, 0.05)
	for p in pontas:
		_cacho(st, p + Vector3.UP * 0.8, rng.randf_range(6.5, 8.5), rng, centro)
	for i in 6:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 7.0)
		_cacho(st, centro + Vector3(cos(a) * r, rng.randf_range(0.0, 2.5), sin(a) * r), rng.randf_range(6.0, 8.0), rng, centro, 0.85)
	return st.commit()


## Árvore de copa (16–24 m): tronco que se divide em 3–4 galhos e copa arredondada densa.
static func _copa(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(17.0, 25.0)
	var garfo := Vector3(rng.randf_range(-0.5, 0.5), altura * 0.42, rng.randf_range(-0.5, 0.5))
	_galho(st, Vector3.ZERO, garfo, 0.6, 0.45)
	var centro := Vector3(garfo.x, altura * 0.74, garfo.z)
	var n_g := rng.randi_range(4, 5)
	var pontas: Array[Vector3] = []
	for g in n_g:
		var a := TAU * g / n_g + rng.randf_range(-0.4, 0.4)
		var alcance := rng.randf_range(5.5, 8.5)
		var fim := garfo + Vector3(cos(a) * alcance, altura * rng.randf_range(0.26, 0.36), sin(a) * alcance)
		_galho(st, garfo, fim, 0.34, 0.14)
		pontas.append(fim)
	# Copa larga e cheia (a mata vista de cima vira um tapete de copas)
	for p in pontas:
		_cacho(st, p + Vector3.UP * 0.8, rng.randf_range(7.0, 9.0), rng, centro)
	for i in 9:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 6.5)
		var q := centro + Vector3(cos(a) * r, rng.randf_range(-1.5, 3.0), sin(a) * r)
		_cacho(st, q, rng.randf_range(6.0, 8.0), rng, centro, 0.82)
	if rng.randf() < 0.5:
		var p := pontas[0]
		_galho(st, p, p + Vector3(0.3, -rng.randf_range(6.0, 12.0), -0.2), 0.05, 0.04)
	return st.commit()


## Bananeira (~4 m): pseudocaule e 7–9 folhas enormes arqueando.
static func _bananeira(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var alto := rng.randf_range(2.2, 3.4)
	var topo := Vector3(rng.randf_range(-0.2, 0.2), alto, rng.randf_range(-0.2, 0.2))
	_galho(st, Vector3.ZERO, topo, 0.22, 0.16)
	var n_f := rng.randi_range(7, 9)
	for f in n_f:
		var a := TAU * f / n_f + rng.randf_range(-0.3, 0.3)
		_fronde(st, topo, Vector3(cos(a), 0.0, sin(a)), rng.randf_range(2.6, 3.6), rng.randf_range(0.55, 0.75), rng.randf_range(0.5, 1.1), rng.randf_range(0.8, 1.3))
	return st.commit()


## Samambaia (~1,5 m): roseta de 10–14 frondes arqueadas saindo do chão.
static func _samambaia(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_f := rng.randi_range(10, 14)
	for f in n_f:
		var a := TAU * f / n_f + rng.randf_range(-0.25, 0.25)
		_fronde(st, Vector3(0, 0.1, 0), Vector3(cos(a), 0.0, sin(a)), rng.randf_range(1.2, 1.9), rng.randf_range(0.3, 0.42), rng.randf_range(1.0, 1.6), rng.randf_range(1.3, 1.9))
	return st.commit()


# ------------------------------------------------------------------ gelo (Frozen Peak)

## Ramo de abeto carregado de neve: silhueta cheia (larga perto do tronco, afinando até a ponta,
## borda serrilhada de agulhas), verde-escuro com riscas de agulhas e um colchão de neve por cima.
static func _textura_ramo_nevado(semente: int) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.14, 0.09, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var ruido := FastNoiseLite.new()
	ruido.seed = semente
	ruido.frequency = 0.09
	var meio := n * 0.5
	for y in n:
		var t := float(y) / n   # 0 = junto do tronco, 1 = ponta
		var w := meio * 0.96 * (1.0 - pow(t, 1.6)) * minf(0.45 + t * 4.0, 1.0)
		var dente := 0.78 + 0.22 * absf(fmod(y, 7.0) / 3.5 - 1.0)   # serrilhado das agulhas
		for x in n:
			var d := absf(x + 0.5 - meio)
			if d > w * dente:
				continue
			var r := ruido.get_noise_2d(x, y) * 0.5 + 0.5
			var risca := 0.82 + 0.18 * sin((x + y * 0.6 * signf(x - meio)) * 1.3)
			var verde := Color(0.035, 0.11, 0.07).lerp(Color(0.1, 0.27, 0.15), r) * risca
			# Neve no miolo, com a borda irregular; some perto da ponta e das beiradas
			var neve := d < w * (0.5 + 0.28 * r) and t < 0.93
			if neve:
				var tom := 0.86 + 0.14 * r
				img.set_pixel(x, y, Color(tom * 0.93, tom * 0.96, tom, 1.0))
			else:
				img.set_pixel(x, y, Color(verde.r, verde.g, verde.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Ramo de conífera: faixa de 3 gomos saindo do tronco, caindo com o peso da neve.
## `rolagem` (rad) inclina a faixa em volta do próprio eixo: duas faixas roladas para lados opostos
## formam um "telhado" e o ramo tem volume visto de lado (uma faixa só, deitada, sumia de perfil).
static func _ramo(st: SurfaceTool, base: Vector3, dir: Vector3, comp: float, larg: float, cai: float, rolagem := 0.0) -> void:
	var lado := dir.cross(Vector3.UP).normalized()
	if rolagem != 0.0:
		lado = (lado * cos(rolagem) + lado.cross(dir).normalized() * sin(rolagem)).normalized()
	var segs := 3
	var pts: Array[Vector3] = []
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(base + dir * comp * t + Vector3.UP * comp * (0.12 * t - cai * t * t))
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var w0 := larg * (0.45 + 0.55 * sin(PI * minf(t0 * 0.9 + 0.12, 1.0)))
		var w1 := larg * (0.45 + 0.55 * sin(PI * minf(t1 * 0.9 + 0.12, 1.0)))
		var q := [pts[i] - lado * w0, pts[i] + lado * w0, pts[i + 1] + lado * w1, pts[i + 1] - lado * w1]
		var uv := [Vector2(0, t0), Vector2(1, t0), Vector2(1, t1), Vector2(0, t1)]
		for k in [0, 1, 2, 0, 2, 3]:
			var ao := lerpf(0.6, 1.0, uv[k].y)
			st.set_normal((Vector3.UP + dir * 0.5).normalized())
			st.set_color(Color(ao, ao, ao))
			st.set_uv(uv[k])
			st.set_uv2(Vector2(0, 0))
			st.add_vertex(q[k])


## Pinheiro (abeto) nevado de 9–17 m: tronco reto e andares de ramos largos caindo com a neve,
## cada vez mais curtos até a ponta — a copa fecha num cone.
static func _pinheiro(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(9.0, 17.0)
	_galho(st, Vector3.ZERO, Vector3.UP * altura, 0.32, 0.05)
	var andares := 8
	for a in andares:
		var t := float(a) / (andares - 1)
		var y := altura * lerpf(0.13, 0.9, t)
		var comp := altura * lerpf(0.34, 0.06, pow(t, 0.85)) * rng.randf_range(0.92, 1.08)
		var giro := rng.randf() * TAU
		var n := 5
		for k in n:
			var ang := giro + TAU * k / n + rng.randf_range(-0.12, 0.12)
			for rolagem: float in [-0.75, 0.75]:
				_ramo(st, Vector3(0.0, y, 0.0), Vector3(cos(ang), 0.0, sin(ang)), comp, comp * 0.5, lerpf(0.42, 0.22, t), rolagem)
	# Ponta: quatro raminhos para cima
	for k in 4:
		var ang := TAU * k / 4.0
		_ramo(st, Vector3(0.0, altura * 0.88, 0.0), (Vector3(cos(ang), 2.6, sin(ang))).normalized(), altura * 0.13, altura * 0.035, 0.0)
	return st.commit()


# ------------------------------------------------------------------ parque pré-histórico (Extinction Day)

## Ramo de conífera verde (sequoia, araucária): silhueta cheia afinando até a ponta, agulhas em riscas.
static func _textura_ramo_verde(semente: int, escura: Color, clara: Color) -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(escura.r, escura.g, escura.b, 0.0))
	var ruido := FastNoiseLite.new()
	ruido.seed = semente
	ruido.frequency = 0.09
	var meio := n * 0.5
	for y in n:
		var t := float(y) / n
		var w := meio * 0.95 * (1.0 - pow(t, 1.5)) * minf(0.4 + t * 4.0, 1.0)
		var dente := 0.74 + 0.26 * absf(fmod(y, 6.0) / 3.0 - 1.0)
		for x in n:
			var d := absf(x + 0.5 - meio)
			if d > w * dente:
				continue
			var r := ruido.get_noise_2d(x, y) * 0.5 + 0.5
			var risca := 0.8 + 0.2 * sin((x + y * 0.7 * signf(x - meio)) * 1.25)
			var c := escura.lerp(clara, r * (1.0 - d / maxf(w, 1.0) * 0.5)) * risca
			img.set_pixel(x, y, Color(c.r, c.g, c.b, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Tronco grosso (12 lados) afunilado de a até b, com sapopemas: o raio na base abre em gomos.
static func _tronco(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, sapopema := 0.0) -> void:
	var eixo := (b - a).normalized()
	var ref := Vector3.RIGHT if absf(eixo.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var u := eixo.cross(ref).normalized()
	var w := eixo.cross(u).normalized()
	var lados := 12
	var aneis := 6 if sapopema > 0.0 else 2
	for j in aneis - 1:
		var t0 := float(j) / (aneis - 1)
		var t1 := float(j + 1) / (aneis - 1)
		for i in lados:
			var q := []
			for par: Array in [[i, t0], [i + 1, t0], [i + 1, t1], [i, t1]]:
				var ang := TAU * float(par[0]) / lados
				var t: float = par[1]
				var n := u * cos(ang) + w * sin(ang)
				var r := lerpf(r0, r1, t)
				if sapopema > 0.0:
					var gomo := pow(absf(cos(ang * 2.5)), 3.0)
					r += sapopema * gomo * pow(1.0 - t, 3.0) * r0
				q.append([a.lerp(b, t) + n * r, n, lerpf(0.5, 0.9, t)])
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(q[k][1])
				st.set_color(Color(q[k][2], q[k][2], q[k][2]))
				st.set_uv(Vector2.ZERO)
				st.set_uv2(Vector2(1, 0))
				st.add_vertex(q[k][0])


## Sequoia gigante de 72–96 m: tronco vermelho colossal com sapopemas, sem galhos embaixo, e a copa
## alta e estreita de andares de ramos curtos caindo (silhueta de coluna arredondada no topo).
static func _sequoia(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(72.0, 96.0)
	var r_base := rng.randf_range(3.6, 4.6)
	_tronco(st, Vector3.ZERO, Vector3.UP * altura * 0.35, r_base, r_base * 0.62, 0.55)
	_tronco(st, Vector3.UP * altura * 0.35, Vector3.UP * altura * 0.75, r_base * 0.62, r_base * 0.3)
	_galho(st, Vector3.UP * altura * 0.75, Vector3.UP * altura, r_base * 0.3, 0.2)
	var andares := 16
	for a in andares:
		var t := float(a) / (andares - 1)
		var y := altura * lerpf(0.46, 0.97, t)
		var comp := altura * lerpf(0.13, 0.05, pow(t, 1.3)) * rng.randf_range(0.8, 1.2)
		var giro := rng.randf() * TAU
		var n := 6
		var r_tronco := lerpf(r_base * 0.5, 0.3, t)
		for k in n:
			var ang := giro + TAU * k / n + rng.randf_range(-0.15, 0.15)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var base := Vector3(0.0, y, 0.0) + dir * r_tronco * 0.8
			if rng.randf() < 0.4:
				_galho(st, base, base + dir * comp * 0.6 + Vector3.UP * comp * 0.05, 0.35, 0.12)
			for rolagem: float in [-0.7, 0.7]:
				_ramo(st, base, dir, comp, comp * 0.55, lerpf(0.35, 0.2, t), rolagem)
	# Topo arredondado: tufos de ramos para cima
	for k in 5:
		var ang := TAU * k / 5.0
		_ramo(st, Vector3(0.0, altura * 0.95, 0.0), Vector3(cos(ang), 1.8, sin(ang)).normalized(), altura * 0.07, altura * 0.035, 0.05)
	return st.commit()


## Comprimento (na horizontal, a partir do pé) do tronco caído da sequoia quebrada mais comprida: quem
## planta confere o chão até aí (a ponta fica enterrada; não pode ficar no ar nem cair numa estrada).
const QUEBRADA_ALCANCE := 58.0

## Sequoia gigante QUEBRADA (pedido do dono para o Extinction Day): o toco de pé, com as sapopemas e a
## quebra em lascas pontudas, e o resto da árvore tombado — ainda preso no alto do toco, descendo até
## enterrar a ponta no chão (cai para o +X da planta), com tocos de galho e uns ramos secos na copa.
## A variação 2 é só o toco, alto, com lascas compridas (a árvore foi embora).
static func _sequoia_quebrada(rng: RandomNumberGenerator, variacao: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var so_toco := variacao == 2
	var h := rng.randf_range(26.0, 40.0) if so_toco else rng.randf_range(13.0, 24.0)
	var r_base := rng.randf_range(3.8, 4.8)
	var r_q := r_base * 0.68
	_tronco(st, Vector3.ZERO, Vector3.UP * h, r_base, r_q, 0.55)
	# Lascas da quebra: pontas de madeira em volta da borda, mais altas de um lado (o lado que rasgou por último)
	var lascas := 13
	var giro := rng.randf() * TAU
	for k in lascas:
		var ang := TAU * k / lascas + rng.randf_range(-0.15, 0.15)
		var n := Vector3(cos(ang), 0.0, sin(ang))
		var alta := 0.5 + 0.5 * cos(ang - giro)
		var comp := (rng.randf_range(1.5, 4.0) + alta * rng.randf_range(3.0, 8.0)) * (1.6 if so_toco else 1.0)
		var r_l := r_q * rng.randf_range(0.2, 0.34)
		_galho(st, Vector3.UP * (h - 1.5) + n * (r_q - r_l * 0.9), Vector3.UP * (h + comp) + n * (r_q - r_l * 0.4) * rng.randf_range(0.7, 1.15), r_l, 0.04)
	# Miolo da quebra, mais baixo e irregular
	for k in 5:
		var ang := rng.randf() * TAU
		var n := Vector3(cos(ang), 0.0, sin(ang)) * r_q * rng.randf_range(0.1, 0.5)
		_galho(st, Vector3.UP * (h - 1.0) + n, Vector3.UP * (h + rng.randf_range(0.8, 3.0)) + n * 1.1, r_q * 0.3, 0.05)
	if so_toco:
		return st.commit()
	# O tronco tombado: do alto do toco até o chão, com a ponta enterrada
	var alcance := rng.randf_range(42.0, QUEBRADA_ALCANCE)
	var a := Vector3(r_q * 0.35, h - 0.8, 0.0)
	var b := Vector3(alcance, -3.5, rng.randf_range(-3.0, 3.0))
	var meio := a.lerp(b, 0.55)
	_tronco(st, a, meio, r_q * 0.95, r_q * 0.62)
	_tronco(st, meio, b, r_q * 0.62, r_q * 0.3)
	var eixo := (b - a).normalized()
	var lado := eixo.cross(Vector3.UP).normalized()
	# Lascas na ponta de cima do tronco tombado (a outra metade da quebra)
	for k in 7:
		var ang := TAU * k / 7.0
		var n := (lado * cos(ang) + lado.cross(eixo) * sin(ang)) * r_q * 0.6
		_galho(st, a + n + eixo * 1.0, a + n * 0.8 - eixo * rng.randf_range(2.0, 6.0), r_q * 0.25, 0.04)
	# Tocos de galho quebrado ao longo dele e, perto da ponta, os ramos secos que sobraram da copa
	for k in 9:
		var t := rng.randf_range(0.3, 0.95)
		var p := a.lerp(b, t)
		var ang := rng.randf_range(-1.3, 1.3)
		var dir := (lado * sin(ang) * (1.0 if rng.randf() < 0.5 else -1.0) + Vector3.UP * cos(ang)).normalized()
		var r_g := lerpf(r_q * 0.62, r_q * 0.3, t)
		var comp := rng.randf_range(3.0, 9.0)
		_galho(st, p + dir * r_g * 0.6, p + dir * (r_g + comp), rng.randf_range(0.35, 0.6), 0.14)
		if t > 0.55:
			for rolagem: float in [-0.7, 0.7]:
				_ramo(st, p + dir * (r_g + comp * 0.5), (dir + eixo * 0.6).normalized(), comp * 1.3, comp * 0.6, 0.3, rolagem)
	return st.commit()


## Araucária de 38–52 m: tronco reto e liso, galhos só no alto em verticilos horizontais que sobem nas
## pontas, cada um com tufos de agulhas — a copa em guarda-chuva, típica das florestas jurássicas.
static func _araucaria(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(38.0, 52.0)
	_tronco(st, Vector3.ZERO, Vector3.UP * altura * 0.7, 1.1, 0.55, 0.3)
	_galho(st, Vector3.UP * altura * 0.7, Vector3.UP * altura, 0.55, 0.15)
	var verticilos := 7
	for v in verticilos:
		var t := float(v) / (verticilos - 1)
		var y := altura * lerpf(0.66, 0.97, t)
		var comp := lerpf(11.0, 3.5, t) * rng.randf_range(0.85, 1.15)
		var giro := rng.randf() * TAU
		for k in 6:
			var ang := giro + TAU * k / 6.0
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var meio := Vector3(0.0, y, 0.0) + dir * comp * 0.6 + Vector3.UP * comp * 0.02
			var fim := Vector3(0.0, y, 0.0) + dir * comp + Vector3.UP * comp * 0.22
			_galho(st, Vector3(0.0, y, 0.0), meio, 0.3, 0.18)
			_galho(st, meio, fim, 0.18, 0.08)
			for rolagem: float in [-0.8, 0.0, 0.8]:
				_ramo(st, meio - dir * comp * 0.15, (dir + Vector3.UP * 0.25).normalized(), comp * 0.55, comp * 0.22, 0.05, rolagem)
	return st.commit()


## Araucária gigante coberta de gelo (Frozen Peak; pedido do dono): tronco alto, reto e nu, e a copa em
## taça lá em cima — andares de galhos compridos que saem quase na horizontal e viram para cima na ponta
## (candelabro), cada ponta com um tufo cheio de ramos carregados de neve; em cima, a copa fecha chata.
static func _araucaria_gelo(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(42.0, 54.0)
	_tronco(st, Vector3.ZERO, Vector3.UP * altura * 0.62, 1.5, 0.8, 0.35)
	_galho(st, Vector3.UP * altura * 0.62, Vector3.UP * altura * 0.97, 0.8, 0.3)
	var andares := 6
	for v in andares:
		var t := float(v) / (andares - 1)
		var y := altura * lerpf(0.58, 0.95, t)
		var comp := lerpf(15.0, 6.5, pow(t, 1.4)) * rng.randf_range(0.88, 1.12)
		var giro := rng.randf() * TAU
		var n := 7 if v < andares - 1 else 5
		for k in n:
			var ang := giro + TAU * k / n + rng.randf_range(-0.12, 0.12)
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			var base := Vector3(0.0, y, 0.0)
			var meio := base + dir * comp * 0.62 - Vector3.UP * comp * 0.04
			var fim := base + dir * comp + Vector3.UP * comp * lerpf(0.2, 0.34, t)
			_galho(st, base, meio, 0.36, 0.22)
			_galho(st, meio, fim, 0.22, 0.1)
			# Ramos ao longo do galho (o peso da neve os deixa caídos) e o tufo da ponta
			for rolagem: float in [-0.8, 0.8]:
				_ramo(st, base + dir * comp * 0.3, dir, comp * 0.5, comp * 0.2, 0.12, rolagem)
			for j in 5:
				var a2 := TAU * j / 5.0 + ang
				var d2 := (Vector3(cos(a2), 0.55, sin(a2))).normalized()
				_ramo(st, fim - Vector3.UP * 0.2, d2, comp * 0.42, comp * 0.2, 0.3, 0.5 if j % 2 == 0 else -0.5)
			_ramo(st, fim, Vector3.UP, comp * 0.28, comp * 0.13, 0.0)
	# Topo: tufo final
	for j in 6:
		var a3 := TAU * j / 6.0
		_ramo(st, Vector3.UP * altura * 0.96, (Vector3(cos(a3), 0.5, sin(a3))).normalized(), 4.2, 1.7, 0.25, 0.4)
	return st.commit()


## Feto arborescente de 4–7 m: tronco fino e fibroso e uma coroa de frondes enormes arqueando.
static func _feto(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(4.0, 7.0)
	var curva := Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
	var topo := Vector3.UP * altura + curva
	_galho(st, Vector3.ZERO, topo * 0.5 + curva * 0.2, 0.32, 0.26)
	_galho(st, topo * 0.5 + curva * 0.2, topo, 0.26, 0.22)
	var n_f := rng.randi_range(11, 15)
	for f in n_f:
		var a := TAU * f / n_f + rng.randf_range(-0.2, 0.2)
		_fronde(st, topo, Vector3(cos(a), 0.0, sin(a)), rng.randf_range(3.2, 4.4), rng.randf_range(0.7, 0.95), rng.randf_range(0.5, 1.0), rng.randf_range(1.2, 1.7))
	for k in 3:
		var a := rng.randf() * TAU
		_fronde(st, topo, Vector3(cos(a), 0.0, sin(a)), 1.8, 0.5, 2.0, 0.3)
	return st.commit()


## Cica (cicadácea) de 1,5–3 m: tronco curto e grosso com escamas e uma roseta de folhas duras.
static func _cica(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var altura := rng.randf_range(0.8, 2.2)
	var topo := Vector3(0.0, altura, 0.0)
	_tronco(st, Vector3.ZERO, topo, 0.55, 0.45)
	var n_f := rng.randi_range(14, 18)
	for f in n_f:
		var a := TAU * f / n_f + rng.randf_range(-0.15, 0.15)
		_fronde(st, topo, Vector3(cos(a), 0.0, sin(a)), rng.randf_range(1.8, 2.6), rng.randf_range(0.42, 0.55), rng.randf_range(0.7, 1.2), rng.randf_range(0.7, 1.0))
	return st.commit()
