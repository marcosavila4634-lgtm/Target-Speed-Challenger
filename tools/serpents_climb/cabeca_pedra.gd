extends SceneTree
## Cabeça de pedra da serpente que morde a estrada (Serpent's Climb, armadilha "serpentes"; pedido do dono
## 2026-10-06), IGUAL às artes dele (assets/MAPA SERPENTE/cabeçadepedra, cópias em assets/selva/cabeca_pedra).
## A própria arte é a pele de uma escultura em relevo, não blocos lisos:
## - FOCINHO: a face da frente em relevo pela arte de frente (coluna do meio, glifos, órbitas com os olhos,
##   sobrancelhas, a beira do maxilar); os lados em relevo pela arte de lado (o olho de lado, os glifos); o céu
##   da boca e as paredes do túnel com a parede interna da arte (blocos e lâmpadas); presas e dentes de osso;
## - BOCHECHAS: as colunas de glifos de cada lado da boca (arte de frente), começando ~10 m atrás do focinho
##   (na arte de lado a boca é aberta dos lados na frente);
## - corredor de trás sem teto, nuca com a arte de lado, os dois discos (arte de lado, de frente para fora) e o
##   penacho: pranchas de pedra pintadas (a pena da arte) em leque, inclinadas para trás;
## - MAXILAR DE BAIXO (parado): lábio com as presas de baixo, rampas de mosaico dos lados, meio-fio com as
##   luzes do túnel e a faixa de glifos da arte de lado nas laterais.
## Medidas pela arte de frente (S m/px; o vão da boca, 415 px, é a largura do túnel: 12 m). Origem = pé do
## focinho no nível da pista, x = direita, y = cima, z = para quem chega. A parte móvel desce (morde) inteira.
## Saída (assets/selva/cabeca_pedra): movel.res, base.res (meta: medidas, olhos, luzes). Shader:
## shaders/cabeca_pedra.gdshader (COLOR.g = qual imagem, COLOR.r = sombra).
## Uso: Godot --headless --path . -s tools/serpents_climb/cabeca_pedra.gd

const PASTA := "res://assets/selva/cabeca_pedra/"
const S := 0.0289            # m por px da arte de frente
const S2 := S * 1.111        # m por px da arte de lado

# Imagens (índice no shader)
const FRENTE := 0
const LADO := 1
const INTERNA := 2
const PENA := 3
const PRESA := 4
const DISCO := 5
const PEDRA := 6
const BLOCOS := 7

# Medidas (m)
const X_IN := 6.0            # meia largura do túnel
const CEU := 12.0            # céu da boca (plano, do meio para trás)
const LABIO := 14.45         # beira do maxilar de cima, na frente
const Z_RAMPA := -8.0        # onde o céu chega a CEU
const X_FOC := 10.3          # meia largura do focinho
const TOPO := 23.6
const TOPO_MEIO := 25.9      # bloco do meio (até x = ±X_MEIO)
const X_MEIO := 6.35
const Z_FOC := -19.0         # fim do focinho (do teto do túnel)
const Z_BOCHECHA := -10.6    # frente das bochechas
const X_BOCHECHA := 13.0
const Z_FIM := -32.0         # fim do corredor de trás
const X_CORREDOR := 9.0
const H_CORREDOR := 9.0
const X_NUCA := 14.0
const Z_NUCA := -25.0
const DISCO_C := Vector3(14.6, 5.0, -27.5)
const DISCO_R := 4.0
const DISCO_X := Vector2(13.4, 15.8)
# Maxilar de baixo (parado)
const Z_LABIO_BAIXO := -1.9
const X_MEIO_FIO := 5.2
const X_RAMPA := 8.4
const X_BASE := 16.0
const Y_BASE := -5.2         # fundo da parte com arte; dali para baixo o pedestal é feito no jogo

var imgs := {}
var lum_cache := {}
var m := {}


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	for n in ["frente", "lado"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path(PASTA + n + ".png"))
		img.convert(Image.FORMAT_RGBA8)
		imgs[n] = img
	_movel()
	_base()
	print("cabeca_pedra pronta em %d ms" % (Time.get_ticks_msec() - t0))
	quit()


# ------------------------------------------------------------------ mapeamento das artes

static func FX(u: float) -> float:
	return (u - 627.0) * S

static func FY(v: float) -> float:
	return (1045.0 - v) * S

static func SZ(u: float) -> float:
	return (90.0 - u) * S2

static func SY(v: float) -> float:
	return (995.0 - v) * S2

static func FU(x: float) -> float:
	return x / S + 627.0

static func FV(y: float) -> float:
	return 1045.0 - y / S

static func SU(z: float) -> float:
	return 90.0 - z / S2

static func SV(y: float) -> float:
	return 995.0 - y / S2


## Altura do céu da boca em z (rampa da beira do maxilar até o céu plano).
static func ceu_em(z: float) -> float:
	return lerpf(LABIO, CEU, clampf(-z / -Z_RAMPA, 0.0, 1.0))


## Topo das rampas do maxilar de baixo em z.
static func rampa_em(z: float) -> float:
	return lerpf(0.8, 3.7, clampf((Z_LABIO_BAIXO - z) / 18.0, 0.0, 1.0))


# ------------------------------------------------------------------ construtor de malha

func _novo() -> void:
	m = {"pos": PackedVector3Array(), "nor": PackedVector3Array(), "uv": PackedVector2Array(), "cor": PackedColorArray(), "idx": PackedInt32Array()}


func _v(p: Vector3, n: Vector3, uv: Vector2, tex: int, sombra := 1.0) -> int:
	m.pos.append(p)
	m.nor.append(n)
	m.uv.append(uv)
	m.cor.append(Color(sombra, (tex + 0.5) / 10.0, 0.0))
	return m.pos.size() - 1


## Triângulo com a frente para `n` (Godot: horário visto de fora).
func _tri(a: int, b: int, c: int, n: Vector3) -> void:
	var pa: Vector3 = m.pos[a]
	var pb: Vector3 = m.pos[b]
	var pc: Vector3 = m.pos[c]
	if (pb - pa).cross(pc - pa).dot(n) > 0.0:
		m.idx.append_array([a, c, b])
	else:
		m.idx.append_array([a, b, c])


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, tex: int, n: Vector3, sombra := 1.0) -> void:
	var ia := _v(a, n, ua, tex, sombra)
	var ib := _v(b, n, ub, tex, sombra)
	var ic := _v(c, n, uc, tex, sombra)
	var id := _v(d, n, ud, tex, sombra)
	_tri(ia, ib, ic, n)
	_tri(ia, ic, id, n)


## Face plana com a imagem em mosaico: `ladrilho` m por repetição (u, v) a partir de eixos do mundo.
func _face_tile(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, tex: int, ladrilho: Vector2, sombra := 1.0) -> void:
	var eu := (b - a).normalized()
	var ev := n.cross(eu).normalized()
	var f := func(p: Vector3) -> Vector2:
		return Vector2((p - a).dot(eu) / ladrilho.x, -(p - a).dot(ev) / ladrilho.y)
	_quad(a, b, c, d, f.call(a), f.call(b), f.call(c), f.call(d), tex, n, sombra)


## Caixa com uma imagem em mosaico por face ("+x", "-x", "+y", "-y", "+z", "-z"; ausente = sem face).
func _caixa(lo: Vector3, hi: Vector3, faces: Dictionary, ladrilho := Vector2(4.0, 4.0)) -> void:
	var c := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	var defs := {"+x": [1, 5, 6, 2, Vector3.RIGHT], "-x": [4, 0, 3, 7, Vector3.LEFT], "+y": [3, 2, 6, 7, Vector3.UP],
		"-y": [0, 4, 5, 1, Vector3.DOWN], "+z": [5, 4, 7, 6, Vector3.BACK], "-z": [0, 1, 2, 3, Vector3.FORWARD]}
	for k in faces:
		var d: Array = defs[k]
		var t: int = faces[k]
		var lad := ladrilho if t != INTERNA else Vector2(9.0, 12.3)
		_face_tile(c[d[0]], c[d[1]], c[d[2]], c[d[3]], d[4], t, lad, 0.9 if k == "-y" else 1.0)


## Relevo de uma arte num plano. mapa(u, v, h) = ponto no mundo (h para fora); mascara(u, v); altura(u, v) em m
## sem o entalhe; o entalhe vem do claro-escuro (o que é mais claro que a vizinhança fica na frente). Paredes
## fecham até h = 0 com a mesma pedra da arte, mais escura. uv = (u, v) / tamanho da imagem.
func _relevo(nome: String, tex: int, rect: Rect2, cel: float, mapa: Callable, n: Vector3, mascara: Callable, altura: Callable, ganho := 0.55, lim := 0.22) -> void:
	var img: Image = imgs[nome]
	var w := float(img.get_width())
	var h := float(img.get_height())
	var nx := int(ceil(rect.size.x / cel))
	var ny := int(ceil(rect.size.y / cel))
	var dentro := PackedByteArray()
	dentro.resize(nx * ny)
	var lum := PackedFloat32Array()
	lum.resize(nx * ny)
	var alt := PackedFloat32Array()
	alt.resize(nx * ny)
	for j in ny:
		for i in nx:
			var u := rect.position.x + (i + 0.5) * cel
			var v := rect.position.y + (j + 0.5) * cel
			var c := img.get_pixel(clampi(int(u), 0, int(w) - 1), clampi(int(v), 0, int(h) - 1))
			lum[j * nx + i] = c.get_luminance()
			var branco := c.r > 0.9 and c.g > 0.9 and c.b > 0.88
			if mascara.call(u, v) and not branco:
				dentro[j * nx + i] = 1
				alt[j * nx + i] = altura.call(u, v)
	# Entalhe: diferença para a média da vizinhança (borrão em caixa)
	var media := lum.duplicate()
	for eixo in 2:
		var o := media.duplicate()
		for j in ny:
			for i in nx:
				var s := 0.0
				var q := 0
				for d in range(-4, 5):
					var ii := i + (d if eixo == 0 else 0)
					var jj := j + (d if eixo == 1 else 0)
					if ii >= 0 and ii < nx and jj >= 0 and jj < ny:
						s += o[jj * nx + ii]
						q += 1
				media[j * nx + i] = s / q
	# Volume alisado (pedra talhada, sem escada célula a célula), depois o entalhe
	for passada in 2:
		var liso := alt.duplicate()
		for j in range(1, ny - 1):
			for i in range(1, nx - 1):
				var k := j * nx + i
				if dentro[k] == 0:
					continue
				var s := alt[k] * 2.0
				var p := 2.0
				for vz: int in [k - 1, k + 1, k - nx, k + nx]:
					if dentro[vz] == 1:
						s += alt[vz]
						p += 1.0
				liso[k] = s / p
		alt = liso
	for k in nx * ny:
		if dentro[k] == 1:
			alt[k] = maxf(alt[k] + clampf((lum[k] - media[k]) * ganho * 4.0, -lim, lim), 0.04)
	# Vértices nos cantos das células
	var vw := nx + 1
	var base: int = m.pos.size()
	var usado := PackedByteArray()
	usado.resize(vw * (ny + 1))
	var ps := PackedVector3Array()
	ps.resize(vw * (ny + 1))
	for j in ny + 1:
		for i in vw:
			var s := 0.0
			var q := 0
			for dj: int in [-1, 0]:
				for di: int in [-1, 0]:
					var ci := i + di
					var cj := j + dj
					if ci >= 0 and ci < nx and cj >= 0 and cj < ny and dentro[cj * nx + ci] == 1:
						s += alt[cj * nx + ci]
						q += 1
			usado[j * vw + i] = 1 if q > 0 else 0
			var u := rect.position.x + i * cel
			var v := rect.position.y + j * cel
			ps[j * vw + i] = mapa.call(u, v, s / maxi(q, 1))
	for j in ny + 1:
		for i in vw:
			var k := j * vw + i
			var nn := n
			if usado[k] == 1:
				var ka := j * vw + mini(i + 1, nx)
				var kb := j * vw + maxi(i - 1, 0)
				var kc := maxi(j - 1, 0) * vw + i
				var kd := mini(j + 1, ny) * vw + i
				var a := ps[ka if usado[ka] == 1 else k] - ps[kb if usado[kb] == 1 else k]
				var b := ps[kc if usado[kc] == 1 else k] - ps[kd if usado[kd] == 1 else k]
				var cr := a.cross(b)
				if cr.length_squared() > 1e-12:
					nn = cr.normalized()
					if nn.dot(n) < 0.0:
						nn = -nn
			var u := rect.position.x + i * cel
			var v := rect.position.y + j * cel
			_v(ps[k], nn, Vector2(u / w, v / h), tex)
	for j in ny:
		for i in nx:
			if dentro[j * nx + i] == 0:
				continue
			var c := [base + j * vw + i, base + j * vw + i + 1, base + (j + 1) * vw + i + 1, base + (j + 1) * vw + i]
			_tri(c[0], c[1], c[2], n)
			_tri(c[0], c[2], c[3], n)
			# Paredes onde o vizinho está fora, até o plano (h = 0)
			for lado: Array in [[0, 1, 0, -1], [1, 2, 1, 0], [2, 3, 0, 1], [3, 0, -1, 0]]:
				var vi: int = i + lado[2]
				var vj: int = j + lado[3]
				if vi >= 0 and vi < nx and vj >= 0 and vj < ny and dentro[vj * nx + vi] == 1:
					continue
				var p0: Vector3 = m.pos[c[lado[0]]]
				var p1: Vector3 = m.pos[c[lado[1]]]
				var u0 := rect.position.x + (i + (1 if lado[0] in [1, 2] else 0)) * cel
				var v0 := rect.position.y + (j + (1 if lado[0] in [2, 3] else 0)) * cel
				var u1 := rect.position.x + (i + (1 if lado[1] in [1, 2] else 0)) * cel
				var v1 := rect.position.y + (j + (1 if lado[1] in [2, 3] else 0)) * cel
				var q0: Vector3 = mapa.call(u0, v0, 0.0)
				var q1: Vector3 = mapa.call(u1, v1, 0.0)
				var nw := (p1 - p0).cross(n).normalized()
				var meio := (p0 + p1) * 0.5
				var centro: Vector3 = mapa.call(rect.position.x + (i + 0.5) * cel, rect.position.y + (j + 0.5) * cel, 0.0)
				if nw.dot(meio - centro) < 0.0:
					nw = -nw
				var uva := Vector2(u0 / w, v0 / h)
				var uvb := Vector2(u1 / w, v1 / h)
				var ia := _v(p0, nw, uva, tex, 0.82)
				var ib := _v(p1, nw, uvb, tex, 0.82)
				var ic := _v(q1, nw, uvb, tex, 0.62)
				var id := _v(q0, nw, uva, tex, 0.62)
				_tri(ia, ib, ic, nw)
				_tri(ia, ic, id, nw)


## Cone de osso (presa): da raiz `p` na direção `d`, comprimento `l`, raio `r`. A pele é a presa da arte
## enrolada (só a faixa do meio do recorte, sem o fundo).
func _cone(p: Vector3, d: Vector3, l: float, r: float, segs := 10) -> void:
	d = d.normalized()
	var a := d.cross(Vector3.FORWARD if absf(d.z) < 0.9 else Vector3.RIGHT).normalized()
	var b := d.cross(a)
	var ponta := p + d * l
	var anel: Array[int] = []
	var pontas: Array[int] = []
	for k in segs + 1:
		var t := TAU * k / segs
		var dir := a * cos(t) + b * sin(t)
		var nn := (dir * l + d * r).normalized()
		var u := 0.32 + 0.36 * absf(fmod(float(k) / segs * 2.0, 2.0) - 1.0)
		anel.append(_v(p + dir * r, nn, Vector2(u, 0.02), PRESA))
		pontas.append(_v(ponta, nn, Vector2(u, 0.97), PRESA))
	for k in segs:
		var nn: Vector3 = m.nor[anel[k]]
		_tri(anel[k], anel[k + 1], pontas[k], nn)


## Prancha do penacho: raiz `p`, direção `d`, largura na direção `wv`; afina e termina em ponta arredondada.
## Seção com uma crista no meio (não é placa). Pele: a pena da arte, ao comprido.
func _prancha(p: Vector3, d: Vector3, wv: Vector3, l: float, w: float, esp: float) -> void:
	d = d.normalized()
	wv = (wv - d * wv.dot(d)).normalized()
	var t := d.cross(wv).normalized()
	var n_seg := 8
	# Seção (lateral -1..1, espessura): 6 pontos em volta
	var secao := [Vector2(-1.0, 0.0), Vector2(-0.45, 0.5), Vector2(0.45, 0.5), Vector2(1.0, 0.0), Vector2(0.45, -0.5), Vector2(-0.45, -0.5)]
	var vs := secao.size()
	var linhas: Array = []
	for s in n_seg + 1:
		var f := float(s) / n_seg
		var larg := w * 0.5 * (1.0 - 0.25 * f) * (sqrt(maxf(1.0 - pow((f - 0.82) / 0.18, 2.0), 0.0)) if f > 0.82 else 1.0)
		var e := esp * (1.0 - 0.35 * f)
		var centro := p + d * l * f
		var linha := []
		for q: Vector2 in secao:
			linha.append(centro + wv * q.x * maxf(larg, 0.02) + t * q.y * e)
		linhas.append(linha)
	for s in n_seg:
		for k in vs:
			var k2 := (k + 1) % vs
			var a: Vector3 = linhas[s][k]
			var b: Vector3 = linhas[s][k2]
			var c: Vector3 = linhas[s + 1][k2]
			var dd: Vector3 = linhas[s + 1][k]
			var meio := (a + b + c + dd) * 0.25
			var eixo := p + d * d.dot(meio - p)
			var nn := (meio - eixo).normalized()
			var face := k <= 2   # de cima: a pena inteira; de baixo: idem, espelhada
			var v0 := float(k) / 3.0 if face else float(k - 3) / 3.0
			var v1 := float(k + 1) / 3.0 if face else float(k - 2) / 3.0
			v0 = clampf(v0, 0.03, 0.97)
			v1 = clampf(v1, 0.03, 0.97)
			var f0 := float(s) / n_seg * 0.96 + 0.02
			var f1 := float(s + 1) / n_seg * 0.96 + 0.02
			_quad(a, b, c, dd, Vector2(f0, v0), Vector2(f0, v1), Vector2(f1, v1), Vector2(f1, v0), PENA, nn, 1.0 if face else 0.8)
	# Tampa da raiz (fica dentro da cabeça, mas fecha)
	var c0 := _v(p, -d, Vector2(0.03, 0.5), PENA, 0.6)
	var ids: Array[int] = []
	for k in vs:
		ids.append(_v(linhas[0][k], -d, Vector2(0.03, 0.5), PENA, 0.6))
	for k in vs:
		_tri(c0, ids[k], ids[(k + 1) % vs], -d)


## Disco de pedra (eixo x) com a face de fora em relevo pela arte (a roda de glifos da arte de lado).
func _disco(lado: float) -> void:
	var c := Vector3(DISCO_C.x * lado, DISCO_C.y, DISCO_C.z)
	var fora := DISCO_X.y * lado
	var dentro := DISCO_X.x * lado
	var aneis := 26
	var segs := 64
	var img: Image = imgs["lado"]
	var ids := []
	var n := Vector3(lado, 0, 0)
	for a in aneis + 1:
		var rr := DISCO_R * float(a) / aneis
		var linha := []
		for k in segs + 1:
			var t := TAU * k / segs
			var yz := Vector2(cos(t), sin(t)) * rr
			# Na arte de lado: centro (950, 900), raio 125 px; z para trás = u maior
			var u := 950.0 - yz.y / DISCO_R * 125.0
			var v := 900.0 - yz.x / DISCO_R * 125.0
			var px := img.get_pixel(clampi(int(u), 0, img.get_width() - 1), clampi(int(v), 0, img.get_height() - 1))
			var h := 0.35 * (1.0 - pow(float(a) / aneis, 6.0)) + (px.get_luminance() - 0.5) * 0.35
			var p := Vector3(fora + lado * h, c.y + yz.x, c.z + yz.y)
			linha.append(_v(p, n, Vector2(u / img.get_width(), v / img.get_height()), LADO))
		ids.append(linha)
	for a in aneis:
		for k in segs:
			_tri(ids[a][k], ids[a + 1][k], ids[a + 1][k + 1], n)
			_tri(ids[a][k], ids[a + 1][k + 1], ids[a][k + 1], n)
	# Borda (pedra em mosaico) e a face de dentro (encostada na nuca)
	for k in segs:
		var t0 := TAU * k / segs
		var t1 := TAU * (k + 1) / segs
		var a0 := Vector3(0, cos(t0), sin(t0)) * DISCO_R
		var a1 := Vector3(0, cos(t1), sin(t1)) * DISCO_R
		var nn := ((a0 + a1) * 0.5).normalized()
		var arco := DISCO_R * TAU / segs
		var u0 := float(k) * arco / 3.0
		_quad(Vector3(fora, c.y, c.z) + a0, Vector3(fora, c.y, c.z) + a1, Vector3(dentro, c.y, c.z) + a1, Vector3(dentro, c.y, c.z) + a0,
			Vector2(u0, 0.0), Vector2(u0 + arco / 3.0, 0.0), Vector2(u0 + arco / 3.0, 0.8), Vector2(u0, 0.8), PEDRA, nn, 0.9)


func _salvar(nome: String, meta: Dictionary) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = m.pos
	arr[Mesh.ARRAY_NORMAL] = m.nor
	arr[Mesh.ARRAY_TEX_UV] = m.uv
	arr[Mesh.ARRAY_COLOR] = m.cor
	arr[Mesh.ARRAY_INDEX] = m.idx
	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	for k in meta:
		malha.set_meta(k, meta[k])
	ResourceSaver.save(malha, PASTA + nome + ".res")
	print("%s: %d vértices, %d triângulos" % [nome, m.pos.size(), m.idx.size() / 3])
	return malha


# ------------------------------------------------------------------ parte que morde

## Altura do relevo da face do focinho (arte de frente, px).
static func _alt_face(u: float, v: float) -> float:
	var q := u if u < 627.0 else 1254.0 - u   # a face é simétrica (meio em 627)
	var h := 0.15
	if v < 235.0:
		h = 0.45                               # bloco de cima
	if q >= 565.0 and v >= 205.0 and v < 440.0:
		h = 0.95                               # coluna do meio
	elif q >= 420.0 and q < 545.0 and v >= 270.0 and v < 385.0:
		h = 0.6                                # glifos
	elif q < 470.0 and v >= 245.0 and v < 300.0:
		h = 0.75                               # sobrancelha
	if v >= 440.0:
		h = maxf(h, lerpf(0.65, 0.25, (v - 440.0) / 105.0))   # beira do maxilar, chanfrada
	var r := Vector2(q, v).distance_to(Vector2(365.0, 358.0)) / 72.0
	if r < 1.0:
		h = maxf(h, 1.15 * smoothstep(1.0, 0.55, r) if r > 0.55 else 1.15 - 0.3 * (1.0 - r / 0.55))   # órbita e olho
	return h


static func _alt_lado(u: float, v: float) -> float:
	var h := 0.15
	if u >= 220.0 and u < 365.0 and v >= 330.0 and v < 445.0:
		h = 0.6
	if u < 170.0:
		h = 0.35
	if v >= 455.0:
		h = maxf(h, 0.5)
	if u >= 610.0 and u < 700.0 and v >= 330.0 and v < 450.0:
		h = 0.55
	var r := Vector2(u, v).distance_to(Vector2(480.0, 400.0)) / 98.0
	if r < 1.0:
		h = maxf(h, 1.2 * smoothstep(1.0, 0.55, r) if r > 0.55 else 1.2 - 0.3 * (1.0 - r / 0.55))
	return h


func _movel() -> void:
	_novo()
	# ---- focinho: núcleo (fecha tudo atrás dos relevos)
	var lados := [-1.0, 1.0]
	for sx: float in lados:
		# lado do núcleo (polígono com o céu em rampa)
		var x := sx * (X_FOC - 0.02)
		var nl := Vector3(sx, 0, 0)
		_face_tile(Vector3(x, LABIO, 0), Vector3(x, CEU, Z_RAMPA), Vector3(x, TOPO, Z_RAMPA), Vector3(x, TOPO, 0), nl, PEDRA, Vector2(4.6, 2.3))
		_face_tile(Vector3(x, CEU, Z_RAMPA), Vector3(x, CEU, Z_FOC), Vector3(x, TOPO, Z_FOC), Vector3(x, TOPO, Z_RAMPA), nl, PEDRA, Vector2(4.6, 2.3))
	_face_tile(Vector3(-X_FOC, LABIO, -0.02), Vector3(X_FOC, LABIO, -0.02), Vector3(X_FOC, TOPO, -0.02), Vector3(-X_FOC, TOPO, -0.02), Vector3.BACK, PEDRA, Vector2(4.6, 2.3))
	_face_tile(Vector3(-X_FOC, TOPO, 0), Vector3(X_FOC, TOPO, 0), Vector3(X_FOC, TOPO, Z_FOC), Vector3(-X_FOC, TOPO, Z_FOC), Vector3.UP, PEDRA, Vector2(4.6, 2.3))
	_face_tile(Vector3(-X_FOC, CEU, Z_FOC), Vector3(X_FOC, CEU, Z_FOC), Vector3(X_FOC, TOPO, Z_FOC), Vector3(-X_FOC, TOPO, Z_FOC), Vector3.FORWARD, BLOCOS, Vector2(5.0, 6.0))
	# céu da boca: a parede interna da arte (blocos e lâmpadas), rampa da beira e o plano
	_quad(Vector3(-X_FOC, LABIO, 0), Vector3(X_FOC, LABIO, 0), Vector3(X_FOC, CEU, Z_RAMPA), Vector3(-X_FOC, CEU, Z_RAMPA),
		Vector2(0.0, 0.0), Vector2(2.3, 0.0), Vector2(2.3, 0.9), Vector2(0.0, 0.9), INTERNA, Vector3.DOWN, 0.85)
	_quad(Vector3(-X_FOC, CEU, Z_RAMPA), Vector3(X_FOC, CEU, Z_RAMPA), Vector3(X_FOC, CEU, Z_FOC), Vector3(-X_FOC, CEU, Z_FOC),
		Vector2(0.0, 0.9), Vector2(2.3, 0.9), Vector2(2.3, 2.1), Vector2(0.0, 2.1), INTERNA, Vector3.DOWN, 0.85)
	# bloco do meio em cima
	_caixa(Vector3(-X_MEIO, TOPO - 0.05, Z_FOC), Vector3(X_MEIO, TOPO_MEIO, -0.03), {"+y": PEDRA, "+x": BLOCOS, "-x": BLOCOS, "-z": BLOCOS}, Vector2(4.0, 2.3))
	# ---- relevo da face (arte de frente)
	var mapa_f := func(u: float, v: float, h: float) -> Vector3:
		return Vector3(FX(u), FY(v), h)
	var masc_f := func(u: float, v: float) -> bool:
		return v >= 150.0 and v <= 545.0 and (v >= 235.0 or (u >= 410.0 and u <= 850.0)) and u >= 258.0 and u <= 997.0
	_relevo("frente", FRENTE, Rect2(255, 150, 745, 396), 4.0, mapa_f, Vector3.BACK, masc_f, _alt_face)
	# ---- relevo dos lados do focinho (arte de lado)
	for sx: float in lados:
		var mapa_l := func(u: float, v: float, h: float) -> Vector3:
			return Vector3(sx * (X_FOC + h), SY(v), SZ(u))
		var masc_l := func(u: float, v: float) -> bool:
			var z := SZ(u)
			var y := SY(v)
			return z <= 0.0 and z >= Z_FOC and y >= ceu_em(z) + 0.05 and y <= TOPO
		_relevo("lado", LADO, Rect2(90, 258, SU(Z_FOC) - 90.0, 400), 4.0, mapa_l, Vector3(sx, 0, 0), masc_l, _alt_lado)
	# ---- presas e dentes
	for sx: float in lados:
		_cone(Vector3(sx * 5.0, ceu_em(-1.2) + 0.35, -1.2), Vector3(0, -1, 0.1), 4.6, 1.1)
		_cone(Vector3(sx * 7.3, ceu_em(-1.7) + 0.3, -1.7), Vector3(-sx * 0.05, -1, 0.1), 2.7, 0.65)
		for k in 5:
			var z := -3.2 - k * 1.6
			_cone(Vector3(sx * 5.5, ceu_em(z) + 0.2, z), Vector3(0, -1, 0.05), 1.5, 0.42, 8)
	# ---- bochechas (colunas de glifos dos lados da boca)
	for sx: float in lados:
		var x0 := sx * X_IN
		var x1 := sx * X_BOCHECHA
		var lo := Vector3(minf(x0, x1), 0.0, Z_FOC)
		var hi := Vector3(maxf(x0, x1), CEU, Z_BOCHECHA - 0.02)
		_caixa(lo, hi, {("+x" if sx < 0 else "-x"): INTERNA, ("-x" if sx < 0 else "+x"): BLOCOS, "+z": PEDRA, "-z": BLOCOS}, Vector2(5.0, 6.0))   # -z: a saída do túnel, acima das paredes do corredor
		_caixa(Vector3(minf(sx * X_FOC, x1), CEU, Z_FOC), Vector3(maxf(sx * X_FOC, x1), CEU + 0.02, Z_BOCHECHA), {"+y": PEDRA}, Vector2(3.0, 3.0))
		var mapa_b := func(u: float, v: float, h: float) -> Vector3:
			return Vector3(FX(u), FY(v), Z_BOCHECHA + h)
		var u0 := FU(minf(x0, x1))
		var masc_b := func(u: float, v: float) -> bool:
			return v >= FV(CEU) and v <= 1045.0
		var alt_b := func(u: float, v: float) -> float:
			var q := u if u < 627.0 else 1254.0 - u
			return 0.25 + (0.4 if q >= 330.0 else 0.0) + (0.35 if v >= 690.0 and v < 800.0 and q >= 300.0 else 0.0)
		_relevo("frente", FRENTE, Rect2(u0, FV(CEU), (X_BOCHECHA - X_IN) / S, FV(0.0) - FV(CEU)), 4.0, mapa_b, Vector3.BACK, masc_b, alt_b)
	# ---- corredor de trás (sem teto), nuca e o bloco atrás dela
	for sx: float in lados:
		var a := Vector3(minf(sx * X_IN, sx * X_CORREDOR), 0.0, Z_FIM)
		var b := Vector3(maxf(sx * X_IN, sx * X_CORREDOR), H_CORREDOR, Z_FOC)
		_caixa(a, b, {("+x" if sx < 0 else "-x"): INTERNA, "+y": PEDRA, "-z": BLOCOS}, Vector2(5.0, 6.0))
		_caixa(Vector3(minf(sx * X_CORREDOR, sx * DISCO_X.x), 0.0, Z_FIM), Vector3(maxf(sx * X_CORREDOR, sx * DISCO_X.x), H_CORREDOR, Z_NUCA),
			{("-x" if sx < 0 else "+x"): BLOCOS, "+y": PEDRA, "-z": BLOCOS}, Vector2(5.0, 6.0))
		# nuca
		var na := Vector3(minf(sx * X_CORREDOR, sx * X_NUCA), 0.0, Z_NUCA)
		var nb := Vector3(maxf(sx * X_CORREDOR, sx * X_NUCA), TOPO, Z_FOC)
		_caixa(na, nb, {("+x" if sx < 0 else "-x"): BLOCOS, "+y": PEDRA, "-z": BLOCOS, "+z": BLOCOS, ("-x" if sx < 0 else "+x"): PEDRA}, Vector2(5.0, 6.0))
		var mapa_n := func(u: float, v: float, h: float) -> Vector3:
			return Vector3(sx * (X_NUCA + h), SY(v), SZ(u))
		var masc_n := func(u: float, v: float) -> bool:
			var z := SZ(u)
			return z <= Z_FOC and z >= Z_NUCA and SY(v) <= TOPO and SY(v) >= 7.4
		var alt_n := func(u: float, v: float) -> float:
			return 0.2 + (0.45 if u >= 780.0 and u < 880.0 and v >= 560.0 and v < 680.0 else 0.0)
		_relevo("lado", LADO, Rect2(SU(Z_FOC), 258, SU(Z_NUCA) - SU(Z_FOC), 505), 4.0, mapa_n, Vector3(sx, 0, 0), masc_n, alt_n)
		_disco(sx)
	# ---- penacho: duas fileiras de pranchas em leque, inclinadas para trás
	# Na arte de frente o leque cerca a cara (pranchas largas e grossas, ~9 de cada lado, a de baixo quase
	# deitada); de lado elas vão para trás. Fileira da frente mais curta, a de trás entre elas e mais longa.
	for fileira in 2:
		var n_p := 10 if fileira == 0 else 9
		var a0 := -14.0 if fileira == 0 else -2.5
		var passo := 23.1
		var incl := deg_to_rad(30.0 if fileira == 0 else 40.0)
		for k in n_p:
			var a := deg_to_rad(a0 + passo * k)
			var radial := Vector3(cos(a), sin(a), 0.0)
			var cima := clampf(sin(a), 0.0, 1.0)
			var raiz := Vector3(cos(a) * 8.6, 17.2 + sin(a) * 7.4, lerpf(-15.0, -8.0, cima) - fileira * 3.2)
			var d := radial * cos(incl) + Vector3.FORWARD * sin(incl)
			var l := (12.0 if fileira == 0 else 14.0) + 1.5
			_prancha(raiz - d * 1.5, d, Vector3(-sin(a), cos(a), 0.0), l, 4.3 if fileira == 0 else 4.7, 1.5)
	var olhos := [Vector3(FX(365.0), FY(358.0), 0.85), Vector3(FX(889.0), FY(358.0), 0.85),
		Vector3(-(X_FOC + 0.95), SY(400.0), SZ(480.0)), Vector3(X_FOC + 0.95, SY(400.0), SZ(480.0))]
	_salvar("movel", {"olhos": olhos, "ceu": CEU, "x_in": X_IN, "z_foc": Z_FOC, "z_fim": Z_FIM, "x_base": X_BASE,
		"z_labio": Z_LABIO_BAIXO, "y_base": Y_BASE, "x_meio_fio": X_MEIO_FIO})


# ------------------------------------------------------------------ maxilar de baixo (parado)

func _base() -> void:
	_novo()
	var lados := [-1.0, 1.0]
	for sx: float in lados:
		# rampas de mosaico dos lados (topo sobe para trás), com a faixa de glifos da arte de lado por fora
		var passos := 12
		for k in passos:
			var z0 := lerpf(Z_LABIO_BAIXO, Z_FIM - 1.0, float(k) / passos)
			var z1 := lerpf(Z_LABIO_BAIXO, Z_FIM - 1.0, float(k + 1) / passos)
			var xa := sx * X_RAMPA
			var xb := sx * X_BASE
			var ya := rampa_em(z0)
			var yb := rampa_em(z1)
			_quad(Vector3(xa, ya, z0), Vector3(xb, ya, z0), Vector3(xb, yb, z1), Vector3(xa, yb, z1),
				Vector2(0.0, -z0 / 3.4), Vector2((X_BASE - X_RAMPA) / 3.4, -z0 / 3.4), Vector2((X_BASE - X_RAMPA) / 3.4, -z1 / 3.4), Vector2(0.0, -z1 / 3.4), PENA, Vector3.UP)
			# face de dentro da rampa (do meio-fio até o topo)
			_quad(Vector3(xa, 0.4, z0), Vector3(xa, 0.4, z1), Vector3(xa, yb, z1), Vector3(xa, ya, z0),
				Vector2(-z0 / 4.0, 0.0), Vector2(-z1 / 4.0, 0.0), Vector2(-z1 / 4.0, (yb - 0.4) / 4.0), Vector2(-z0 / 4.0, (ya - 0.4) / 4.0), BLOCOS, Vector3(-sx, 0, 0), 0.9)
			# face de fora: núcleo liso (o relevo da arte vem por cima)
			_quad(Vector3(xb - sx * 0.02, Y_BASE, z0), Vector3(xb - sx * 0.02, Y_BASE, z1), Vector3(xb - sx * 0.02, yb, z1), Vector3(xb - sx * 0.02, ya, z0),
				Vector2(-z0 / 4.0, 0.0), Vector2(-z1 / 4.0, 0.0), Vector2(-z1 / 4.0, 1.0), Vector2(-z0 / 4.0, 1.0), PEDRA, Vector3(sx, 0, 0))
		var mapa_l := func(u: float, v: float, h: float) -> Vector3:
			return Vector3(sx * (X_BASE + h), SY(v), SZ(u))
		var masc_l := func(u: float, v: float) -> bool:
			var z := SZ(u)
			var y := SY(v)
			return z <= Z_LABIO_BAIXO and y <= rampa_em(z) and y >= -4.4   # abaixo disso a arte é o chão branco
		var alt_l := func(u: float, v: float) -> float:
			return 0.2 + (0.25 if v >= 1080.0 and v < 1125.0 else 0.0)
		_relevo("lado", LADO, Rect2(SU(Z_LABIO_BAIXO), SV(3.8), SU(-27.5) - SU(Z_LABIO_BAIXO), SV(Y_BASE) - SV(3.8)), 4.0, mapa_l, Vector3(sx, 0, 0), masc_l, alt_l)
		# fim de trás do pedestal da rampa (depois da arte) e frente
		_caixa(Vector3(minf(sx * X_RAMPA, sx * X_BASE), Y_BASE, Z_FIM - 1.0), Vector3(maxf(sx * X_RAMPA, sx * X_BASE), rampa_em(Z_FIM - 1.0), Z_FIM - 0.99), {"-z": BLOCOS}, Vector2(4.0, 4.0))
		_caixa(Vector3(minf(sx * X_RAMPA, sx * X_BASE), Y_BASE, Z_LABIO_BAIXO - 0.01), Vector3(maxf(sx * X_RAMPA, sx * X_BASE), rampa_em(Z_LABIO_BAIXO), Z_LABIO_BAIXO), {"+z": BLOCOS}, Vector2(4.0, 4.0))
		# meio-fio aceso (as luzes do chão da arte) e o bloco do lábio de baixo com a presa
		var xm := sx * X_MEIO_FIO
		_caixa(Vector3(minf(xm, sx * X_RAMPA), Y_BASE, Z_FIM - 1.0), Vector3(maxf(xm, sx * X_RAMPA), 0.4, -4.8), {"+y": PEDRA, "-z": BLOCOS}, Vector2(3.0, 3.0))
		for k in 10:
			var z0 := lerpf(-4.8, Z_FIM - 1.0, k / 10.0)
			var z1 := lerpf(-4.8, Z_FIM - 1.0, (k + 1) / 10.0)
			_quad(Vector3(xm, -0.35, z0), Vector3(xm, -0.35, z1), Vector3(xm, 0.4, z1), Vector3(xm, 0.4, z0),
				Vector2(-z0 / 9.0, 0.93), Vector2(-z1 / 9.0, 0.93), Vector2(-z1 / 9.0, 0.79), Vector2(-z0 / 9.0, 0.79), INTERNA, Vector3(-sx, 0, 0))
		var la := Vector3(minf(xm, sx * X_RAMPA), Y_BASE, -4.8)
		var lb := Vector3(maxf(xm, sx * X_RAMPA), 0.8, Z_LABIO_BAIXO)
		_caixa(la, lb, {"+y": PEDRA, ("+x" if sx < 0 else "-x"): BLOCOS}, Vector2(3.0, 3.0))
		# frente do bloco: a arte de frente (o bloco da presa de baixo)
		var u0 := FU(minf(xm, sx * X_RAMPA))
		var mapa_f := func(u: float, v: float, h: float) -> Vector3:
			return Vector3(FX(u), FY(v), Z_LABIO_BAIXO + h)
		var masc_f := func(u: float, v: float) -> bool:
			return true
		var alt_f := func(u: float, v: float) -> float:
			return 0.15
		_relevo("frente", FRENTE, Rect2(u0, FV(0.8), (X_RAMPA - X_MEIO_FIO) / S, FV(-3.0) - FV(0.8)), 4.0, mapa_f, Vector3.BACK, masc_f, alt_f)
		_caixa(Vector3(minf(xm, sx * X_RAMPA), Y_BASE, Z_LABIO_BAIXO - 0.02), Vector3(maxf(xm, sx * X_RAMPA), -3.0, Z_LABIO_BAIXO), {"+z": BLOCOS}, Vector2(3.0, 3.0))
		_cone(Vector3(sx * 6.8, 0.6, -3.35), Vector3(0, 1, 0.05), 3.3, 1.0)
	# meio, embaixo da pista: frente com a arte (o lábio de baixo) e o topo logo abaixo do asfalto
	_caixa(Vector3(-X_MEIO_FIO, Y_BASE, Z_FIM - 1.0), Vector3(X_MEIO_FIO, -0.35, Z_LABIO_BAIXO), {"+y": PEDRA, "+z": BLOCOS, "-z": BLOCOS}, Vector2(3.0, 3.0))
	_salvar("base", {})


