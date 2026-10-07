class_name CercaSelva
extends RefCounted
## Cerca dos cercados (largada e plataforma da pirâmide, em todas as etapas) do Serpent's Climb, IGUAL à arte do dono (assets/selva/cerca/cerca.png,
## cópia de assets/MAPA SERPENTE/EXTRUTURAS/PORTÃO PRINCIPAL/CERCA.PNG), no lugar do muro de tijolo com
## grade. A própria arte é a pele de um relevo 3D (como o portão, PortaoSelva):
## - pilar: coluna quadrada com a face do pilar da arte (serpente enrolada, glifos) nas quatro faces,
##   plinto largo embaixo, tampa de pedra e a taça do braseiro torneada com a pintura da taça, com fogo
##   e luz de verdade (as chamas pintadas ficam de fora);
## - painel entre dois pilares: o trecho de grade da arte recortado pelo alfa (vê-se a mata entre os
##   balaústres), com profundidade por parte (mureta com greca, balaústres, travessa com o medalhão,
##   pontas) e o entalhe fino pelo claro-escuro; as laterais repetem a cor da própria peça; nas duas faces;
## - colisão: uma parede por trecho, até o alto dos pilares (ninguém pula para fora).
## Altura: o alto da travessa fica na altura do muro antigo (muro_altura + grade_altura).

const ARTE := "res://assets/selva/cerca/cerca.png"
const CHAO_PX := 826.0
const TRAVESSA_PX := 276.0     # alto da travessa da grade
const CEL := 6.0               # px da arte por célula do relevo (~3 cm). Era 4: cada pilar tinha 66 mil triângulos e a cerca
                               # inteira 5,8 milhões, redesenhados nas passadas de sombra — o ponto mais pesado do mapa
# Regiões da arte (px): fuste e plinto do pilar do meio, taça, painel de grade, pedra lisa para as tampas
const FUSTE := Rect2(765, 205, 150, 530)
const PLINTO := Rect2(732, 735, 208, 91)
const PAINEL := Rect2(228, 205, 514, 621)
const PEDRA := Rect2(806, 560, 68, 60)
const TACA_X := 840.0
const TACA := [[207.0, 52.0], [196.0, 56.0], [186.0, 44.0], [172.0, 62.0], [150.0, 74.0], [131.0, 76.0], [124.0, 71.0], [126.0, 63.0], [142.0, 57.0]]

static var _cache := {}


static func montar(r: Recinto) -> void:
	var img := Recinto.ler_imagem(ARTE)
	if img == null:
		return
	var e := (r.muro_altura + r.grade_altura) / (CHAO_PX - TRAVESSA_PX)
	var pecas: Array = _pecas(img, e)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/arte_relevo.gdshader")
	mat.set_shader_parameter("imagem", pecas[3])
	mat.set_shader_parameter("brilho", 0.3)
	mat.set_shader_parameter("fogo", 0.0)
	var meia_col := FUSTE.size.x * 0.5 * e
	var larg_painel := PAINEL.size.x * e
	var passo := 705.0 * e   # de pilar a pilar, como na arte
	var portao := (600.0 - 8.0) * r.saida_largura / 350.0 + 0.6   # meia largura do portão principal (PortaoSelva)
	var xp := r.comprimento + Recinto.PAREDE * 0.5
	var colunas: Array[Transform3D] = []
	var paineis: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var vistos := {}
	var alto := (CHAO_PX - FUSTE.position.y) * e
	for t: Array in r._trechos_muro():
		var a: Vector2 = t[0]
		var c: Vector2 = t[1]
		# Muro da frente: começa no pé do portão principal (ele é mais largo que a saída)
		if r.name == "Largada" and is_equal_approx(a.x, xp) and is_equal_approx(c.x, xp):
			if absf(a.y) < absf(c.y):
				a.y = signf(a.y) * maxf(absf(a.y), portao)
			else:
				c.y = signf(c.y) * maxf(absf(c.y), portao)
		var d := c - a
		var comp := d.length()
		if comp < 1.0:
			continue
		var eixo := (r.frente * d.x + r.lateral * d.y).normalized()
		var b := Basis.looking_at(eixo, Vector3.UP) * Basis(Vector3.UP, PI * 0.5)   # x local ao longo do muro
		var n := maxi(int(round(comp / passo)), 1)
		var l := comp / n
		for k in n + 1:
			var q := a + d * (float(k) / n)
			var chave := Vector2i(roundi(q.x * 2.0), roundi(q.y * 2.0))
			if vistos.has(chave):
				continue
			vistos[chave] = true
			colunas.append(Transform3D(b, r.pa(q.x, q.y, r.piso_y)))
		var esticar := (l - meia_col * 2.0 + 0.5) / larg_painel
		for k in n:
			var q := a + d * ((k + 0.5) / n)
			paineis.append(Transform3D(b * Basis.from_scale(Vector3(esticar, 1.0, 1.0)), r.pa(q.x, q.y, r.piso_y)))
		var meio := (a + c) * 0.5
		colisao.append(Transform3D(b * Basis.from_scale(Vector3(comp + meia_col * 2.0, alto, meia_col * 2.0)), r.pa(meio.x, meio.y, r.piso_y + alto * 0.5)))
	r._instancias(pecas[0], colunas, mat)
	r._instancias(pecas[1], paineis, mat)
	ComplexoLancamento.adicionar_colisoes(r.corpo, colisao)
	# Brasa e fogo de verdade em cada taça, luz a cada três
	var brasa := StandardMaterial3D.new()
	brasa.albedo_color = Color(0.2, 0.06, 0.02)
	brasa.emission_enabled = true
	brasa.emission = Color(1.0, 0.42, 0.08)
	brasa.emission_energy_multiplier = 3.0
	var y_brasa := (CHAO_PX - 140.0) * e
	var topos: Array[Transform3D] = []
	for i in colunas.size():
		var p := colunas[i].origin + Vector3.UP * y_brasa
		topos.append(Transform3D(Basis.IDENTITY, p))
		Fogo.criar(r, p + Vector3.UP * 0.2, 0.7, 3.2, 18, 1.2)
		if i % 3 == 0:
			var luz := OmniLight3D.new()
			luz.light_color = Color(1.0, 0.55, 0.2)
			luz.light_energy = 2.6
			luz.omni_range = 18.0
			luz.shadow_enabled = false
			luz.position = p + Vector3.UP * 1.5
			r.add_child(luz)
	r._instancias(pecas[2], topos, brasa)


## [pilar, painel, brasa, textura da arte] (uma vez por escala).
static func _pecas(img: Image, e: float) -> Array:
	var chave := "%.5f" % e
	if _cache.has(chave):
		return _cache[chave]
	var w := float(img.get_width())
	var h := float(img.get_height())
	var media := _media(img)
	# Pilar: quatro faces do fuste e do plinto, tampas e a taça
	var pilar := SurfaceTool.new()
	pilar.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mf := FUSTE.size.x * 0.5 * e
	var mp := PLINTO.size.x * 0.5 * e
	for k in 4:
		var giro := Basis(Vector3.UP, k * PI * 0.5)
		_juntar(pilar, _relevo(img, media, FUSTE, e, func(_x, _y): return 0.0, false, 0.9), Transform3D(giro, giro * Vector3(0, 0, mf)))
		_juntar(pilar, _relevo(img, media, PLINTO, e, func(_x, _y): return 0.0, false, 0.9), Transform3D(giro, giro * Vector3(0, 0, mp)))
	_tampa(pilar, (CHAO_PX - FUSTE.position.y) * e, mf, w, h)
	_tampa(pilar, (CHAO_PX - PLINTO.position.y) * e, mp, w, h)
	_taca(pilar, e, w, h)
	# Painel de grade: as duas faces
	var painel := SurfaceTool.new()
	painel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var face := _relevo(img, media, PAINEL, e, _fundo_painel, true, 1.3)
	_juntar(painel, face, Transform3D.IDENTITY)
	_juntar(painel, face, Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO))
	var disco := CylinderMesh.new()
	disco.top_radius = 57.0 * e
	disco.bottom_radius = 57.0 * e
	disco.height = 0.25
	disco.radial_segments = 16
	var tex := img.duplicate() as Image
	tex.generate_mipmaps()
	_cache[chave] = [pilar.commit(), painel.commit(), disco, ImageTexture.create_from_image(tex)]
	return _cache[chave]


## Quanto cada parte do painel sai do meio (m): mureta, balaústres, blocos, travessa, medalhão, pontas.
static func _fundo_painel(px: float, py: float) -> float:
	if py >= 735.0:
		return 0.7
	if py >= 640.0:
		return 0.55
	if py < 262.0:
		return 0.2
	if py < 365.0:
		var z := 0.36
		var dm := Vector2(px - 485.0, py - 305.0).length() / 48.0
		if dm < 1.0:
			z += 0.22 * sqrt(1.0 - dm * dm)
		return z
	if py > 470.0 and py < 525.0:
		return 0.34
	return 0.26


## Claro-escuro médio em volta de cada pixel (cópia pequena da arte borrada): o entalhe é a diferença.
static func _media(img: Image) -> Image:
	var m := img.duplicate() as Image
	m.convert(Image.FORMAT_RGBA8)
	m.resize(img.get_width() / 12, img.get_height() / 12, Image.INTERPOLATE_BILINEAR)
	m.resize(img.get_width() / 4, img.get_height() / 4, Image.INTERPOLATE_BILINEAR)
	return m


## Relevo de um retângulo da arte: x = ao longo (centro do retângulo em 0), y = altura acima do chão
## da arte, z = para fora. `mascara`: recorta pelo alfa e fecha as beiradas com paredes até z = 0;
## sem ela o retângulo é cheio e as bordas ficam rentes (z = 0), para encostar nas faces vizinhas.
static func _relevo(img: Image, media: Image, r: Rect2, e: float, fundo: Callable, mascara: bool, ganho: float) -> Array:
	var w := float(img.get_width())
	var h := float(img.get_height())
	var nx := int(r.size.x / CEL)
	var ny := int(r.size.y / CEL)
	var dentro := PackedByteArray()
	dentro.resize(nx * ny)
	var hc := PackedFloat32Array()
	hc.resize(nx * ny)
	for j in ny:
		for i in nx:
			var px := r.position.x + (i + 0.5) * r.size.x / nx
			var py := r.position.y + (j + 0.5) * r.size.y / ny
			var c := img.get_pixel(int(px), int(py))
			if mascara and c.a < 0.55:
				continue
			dentro[j * nx + i] = 1
			var mc := media.get_pixel(clampi(int(px / 4.0), 0, media.get_width() - 1), clampi(int(py / 4.0), 0, media.get_height() - 1))
			hc[j * nx + i] = float(fundo.call(px, py)) + clampf((c.get_luminance() - mc.get_luminance()) * ganho * e / 0.018, -0.2, 0.22)
	var vw := nx + 1
	var pos := PackedVector3Array()
	pos.resize(vw * (ny + 1))
	var usado := PackedByteArray()
	usado.resize(pos.size())
	var cx := r.position.x + r.size.x * 0.5
	for j in ny + 1:
		for i in vw:
			var soma := 0.0
			var conta := 0
			for dj: int in [-1, 0]:
				for di: int in [-1, 0]:
					var ci := i + di
					var cj := j + dj
					if ci >= 0 and ci < nx and cj >= 0 and cj < ny and dentro[cj * nx + ci] == 1:
						soma += hc[cj * nx + ci]
						conta += 1
			usado[j * vw + i] = 1 if conta > 0 else 0
			var z := soma / maxi(conta, 1)
			if not mascara and (i == 0 or i == nx or j == 0):
				z = 0.0
			elif not mascara:
				z = maxf(z, 0.0)
			var px := r.position.x + i * r.size.x / nx
			var py := r.position.y + j * r.size.y / ny
			pos[j * vw + i] = Vector3((px - cx) * e, (CHAO_PX - py) * e, z)
	var nor := PackedVector3Array()
	nor.resize(pos.size())
	var uv := PackedVector2Array()
	uv.resize(pos.size())
	var cor := PackedColorArray()
	cor.resize(pos.size())
	for j in ny + 1:
		for i in vw:
			var k := j * vw + i
			uv[k] = Vector2((r.position.x + i * r.size.x / nx) / w, (r.position.y + j * r.size.y / ny) / h)
			cor[k] = Color.WHITE
			var ka := j * vw + mini(i + 1, nx)
			var kb := j * vw + maxi(i - 1, 0)
			var kc := maxi(j - 1, 0) * vw + i
			var kd := mini(j + 1, ny) * vw + i
			var a := (pos[ka] if usado[ka] == 1 else pos[k]) - (pos[kb] if usado[kb] == 1 else pos[k])
			var b := (pos[kc] if usado[kc] == 1 else pos[k]) - (pos[kd] if usado[kd] == 1 else pos[k])
			var nn := a.cross(b)
			nor[k] = nn.normalized() if nn.length_squared() > 1e-12 else Vector3.BACK
	var idx := PackedInt32Array()
	for j in ny:
		for i in nx:
			if dentro[j * nx + i] == 0:
				continue
			var c := [j * vw + i, j * vw + i + 1, (j + 1) * vw + i + 1, (j + 1) * vw + i]
			idx.append_array([c[0], c[1], c[2], c[0], c[2], c[3]])
			if not mascara:
				continue
			# Paredes onde o vizinho está fora: a cor da própria peça (balaústre, ponta, folha) puxada para trás
			var meio_uv := Vector2((r.position.x + (i + 0.5) * r.size.x / nx) / w, (r.position.y + (j + 0.5) * r.size.y / ny) / h)
			for lado: Array in [[0, 1, 0, -1, Vector3.UP], [1, 2, 1, 0, Vector3.RIGHT], [2, 3, 0, 1, Vector3.DOWN], [3, 0, -1, 0, Vector3.LEFT]]:
				var vi: int = i + lado[2]
				var vj: int = j + lado[3]
				if vi >= 0 and vi < nx and vj >= 0 and vj < ny and dentro[vj * nx + vi] == 1:
					continue
				var base := pos.size()
				for ponta: int in [lado[0], lado[1]]:
					var pf := pos[c[ponta]]
					for tras in 2:
						pos.append(pf if tras == 0 else Vector3(pf.x, pf.y, 0.0))
						nor.append(lado[4])
						uv.append(meio_uv)
						cor.append(Color(0.8, 0.8, 0.8) if tras == 0 else Color(0.55, 0.55, 0.55))
				idx.append_array([base, base + 2, base + 3, base, base + 3, base + 1])
	return [pos, nor, uv, cor, idx]


## Junta um relevo (arrays de _relevo) no SurfaceTool, transformado.
static func _juntar(st: SurfaceTool, a: Array, xf: Transform3D) -> void:
	var pos: PackedVector3Array = a[0]
	var nor: PackedVector3Array = a[1]
	var uv: PackedVector2Array = a[2]
	var cor: PackedColorArray = a[3]
	var idx: PackedInt32Array = a[4]
	for k in idx.size():
		var v := idx[k]
		st.set_color(cor[v])
		st.set_uv(uv[v])
		st.set_normal((xf.basis * nor[v]).normalized())
		st.add_vertex(xf * pos[v])


## Tampa quadrada de pedra (meia largura `m`) na altura y, com a pedra lisa da arte.
static func _tampa(st: SurfaceTool, y: float, m: float, w: float, h: float) -> void:
	var q := [Vector3(-m, y, -m), Vector3(m, y, -m), Vector3(m, y, m), Vector3(-m, y, m)]
	var u := [Vector2(PEDRA.position.x, PEDRA.position.y), Vector2(PEDRA.end.x, PEDRA.position.y), Vector2(PEDRA.end.x, PEDRA.end.y), Vector2(PEDRA.position.x, PEDRA.end.y)]
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color.WHITE)
		st.set_uv(Vector2(u[k].x / w, u[k].y / h))
		st.set_normal(Vector3.UP)
		st.add_vertex(q[k])


## Taça do braseiro torneada pelo perfil da arte, com a pintura da taça projetada de frente (por dentro e
## por fora), apoiada no alto do fuste.
static func _taca(st: SurfaceTool, e: float, w: float, h: float) -> void:
	var n := 28
	for i in TACA.size() - 1:
		var a: Array = TACA[i]
		var b: Array = TACA[i + 1]
		for k in n:
			var t0 := TAU * k / n
			var t1 := TAU * (k + 1) / n
			var q := []
			for par: Array in [[a, t0], [a, t1], [b, t1], [b, t0]]:
				var p: Array = par[0]
				var t: float = par[1]
				var rr := float(p[1]) * e
				q.append([Vector3(sin(t) * rr, (CHAO_PX - float(p[0])) * e, cos(t) * rr), Vector2((TACA_X + sin(t) * float(p[1])) / w, float(p[0]) / h), Vector3(sin(t), 0.0, cos(t))])
			var fora := i < 6   # os dois últimos anéis são o lado de dentro da borda
			var ordem := [0, 1, 2, 0, 2, 3] if fora else [0, 2, 1, 0, 3, 2]
			for kk: int in ordem:
				st.set_color(Color.WHITE if fora else Color(0.6, 0.6, 0.6))
				st.set_uv(q[kk][1])
				st.set_normal(q[kk][2] if fora else -(q[kk][2] as Vector3))
				st.add_vertex(q[kk][0])
