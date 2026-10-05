class_name PiramideSelva
extends Node3D
## Pirâmides do Serpent's Climb IGUAIS à arte do dono (assets/selva/piramide/frente.png e cima.png, cópias de
## assets/MAPA SERPENTE/piramide). Como no portão (PortaoSelva), a própria pintura é a pele de uma escultura
## em relevo — nada de blocos:
## - os níveis da arte (talude com friso, cornija em cima) viram degraus de verdade, com o terraço entre um e
##   outro coberto pelo piso de pedra da vista de cima (cima.png);
## - escadaria, alfardas e as cabeças de serpente saem da parede; o entalhe fino vem do claro-escuro;
## - as quatro faces são a mesma frente da arte (escadaria nas quatro, como a do desenho) e se fecham nas
##   quinas: a peça é fechada de qualquer ângulo; o templo do alto só nas pirâmides com templo (nas outras o
##   topo é a plataforma da etapa ou o alvo);
## - a pirâmide do json é mais larga que a da arte: o miolo (escada, alfardas, cabeças) e a quina ficam como
##   no desenho e o friso entre eles se repete, painel a painel — a pintura nunca é esticada.
## Medidas em px da arte (1448 x 1086); s = metros por px (altura do json / 820 px de pirâmide sem templo).
## Coordenadas da malha de uma face: x = lateral, y = altura acima do chão, z = para fora (0 = eixo).

const FRENTE := "res://assets/selva/piramide/frente.png"
const CIMA := "res://assets/selva/piramide/cima.png"
const LARG_PX := 1448.0
const ALT_PX := 1086.0
const CX := 724.0           # eixo da escadaria na arte
const BASE_PX := 1055.0     # pé da pirâmide na arte
const TOPO_PX := 235.0      # terraço do alto (onde começa o templo)
const CEL := 8.0            # px da arte por célula do relevo
const BORDA := 50.0         # faixa da quina (sempre a quina pintada)
const ENTALHE := 40.0       # px de relevo por unidade de claro-escuro
const ESCADA_SAI := 6.0     # px que a escadaria sai da parede
const ALFARDA_SAI := 10.0   # e a alfarda acima da escada
const SAIA_M := 3.0         # parede abaixo do pé (terreno irregular)
const TERRACO := Rect2(400, 668, 140, 22)   # ladrilho do piso dos terraços na vista de cima
const BASE_PISO := Rect2(400, 1036, 640, 18)   # faixa do pé da arte, para a saia
const VERSAO := 4           # muda quando a malha muda (cache em user://cache)

## Níveis da arte, de cima para baixo: [y de cima, y de baixo, meia largura em cima, embaixo, miolo].
## O miolo é a faixa do meio que fica sempre como na arte (escada, alfardas, cabeças); fora dele o friso se repete.
const NIVEIS := [
	[40.0, 90.0, 112.0, 112.0, 0.0],      # crista do templo
	[90.0, 235.0, 215.0, 215.0, 0.0],     # templo
	[235.0, 290.0, 250.0, 250.0, 95.0],
	[290.0, 420.0, 352.0, 375.0, 150.0],
	[420.0, 575.0, 445.0, 470.0, 175.0],
	[575.0, 750.0, 555.0, 578.0, 200.0],
	[750.0, 960.0, 655.0, 682.0, 235.0],
	[960.0, 1055.0, 690.0, 698.0, 275.0],
]
## Cabeças de serpente na ponta das alfardas: [x a partir do eixo, y, raio, quanto sai] (px).
const CABECAS := [[101.0, 300.0, 38.0, 40.0], [131.0, 430.0, 40.0, 42.0], [158.0, 585.0, 40.0, 44.0],
	[191.0, 765.0, 42.0, 46.0], [211.0, 935.0, 60.0, 55.0]]

enum { FACE, ESCADA, ALFARDA }

static var _lum := PackedFloat32Array()    # claro-escuro menos a média da vizinhança (1/4 da arte)
static var _lum_w := 0
static var _lum_h := 0
static var _mats: Array = []
static var _malhas := {}

# Pirâmide em montagem
var _s := 0.1
var _xb := 0.0
var _xt := 0.0
var _templo := false


## Prepara o perfil da pirâmide do json ({c, mb, mt, topo, templo}) — usado pela altura e pela montagem.
static func perfil(p: Dictionary, chao: float) -> void:
	var s := (float(p.topo) - chao) / (BASE_PX - TOPO_PX)
	p.s = s
	p.chao = chao
	p.xb = float(p.mb) / s - NIVEIS[NIVEIS.size() - 1][3]
	p.xt = float(p.mt) / s - NIVEIS[2][2]


static func _niveis(templo: bool) -> Array:
	return NIVEIS if templo else NIVEIS.slice(2)


static func _x_extra(xt: float, xb: float, y: float) -> float:
	return lerpf(xt, xb, clampf((y - TOPO_PX) / (BASE_PX - TOPO_PX), 0.0, 1.0))


static func _a_nivel(n: Array, y: float) -> float:
	return lerpf(n[2], n[3], clampf((y - n[0]) / (n[1] - n[0]), 0.0, 1.0))


## Altura da pirâmide a `ch` m do eixo (distância de Chebyshev). -INF fora dela.
static func altura(p: Dictionary, ch: float) -> float:
	var s: float = p.s
	var u := ch / s
	for n: Array in _niveis(p.templo):
		var nt := float(n[2]) + _x_extra(p.xt, p.xb, n[0])
		var nb := float(n[3]) + _x_extra(p.xt, p.xb, n[1])
		var y := INF
		if u <= nt:
			y = n[0]
		elif u <= nb:
			y = lerpf(n[0], n[1], (u - nt) / maxf(nb - nt, 0.01))
		if y < INF:
			return float(p.chao) + (BASE_PX - y) * s
	return -INF


## Monta a pirâmide `p` (já com perfil) em `no`; colisão em `corpo`.
static func montar(no: Node3D, corpo: StaticBody3D, p: Dictionary) -> void:
	var m := PiramideSelva.new()
	m.name = "Relevo"
	m.position = Vector3(p.c.x, p.chao, p.c.y)
	no.add_child(m)
	m._s = p.s
	m._xb = p.xb
	m._xt = p.xt
	m._templo = p.templo
	if not _materiais():
		return
	var chave := "%d|%.5f|%.2f|%.2f|%s" % [VERSAO, m._s, m._xb, m._xt, m._templo]
	if not _malhas.has(chave):
		# Montar a malha leva ~1 s por pirâmide: fica guardada em disco, como o terreno
		var arq := "user://cache/piramide_%s.res" % chave.md5_text().substr(0, 12)
		var malha: ArrayMesh = load(arq) as ArrayMesh if FileAccess.file_exists(arq) else null
		if malha == null or malha.get_surface_count() != 2:
			_preparar_entalhe()
			malha = m._malha()
			DirAccess.make_dir_recursive_absolute("user://cache")
			ResourceSaver.save(malha, arq)
		_malhas[chave] = malha
	for k in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = _malhas[chave]
		mi.rotation.y = k * PI * 0.5
		for i in 2:
			mi.set_surface_override_material(i, _mats[i])
		m.add_child(mi)
	var caixas: Array = []
	for c: Transform3D in m._colisoes():
		caixas.append(m.transform * c)
	ComplexoLancamento.adicionar_colisoes(corpo, caixas)


# ------------------------------------------------------------------ arte

static func _materiais() -> bool:
	if not _mats.is_empty():
		return true
	var frente := Recinto.ler_imagem(FRENTE)
	var cima := Recinto.ler_imagem(CIMA)
	if frente == null or cima == null:
		push_warning("PiramideSelva: arte não encontrada")
		return false
	for img: Image in [frente, cima]:
		img = img.duplicate()
		img.generate_mipmaps()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/arte_relevo.gdshader")
		mat.set_shader_parameter("imagem", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("brilho", 0.3)
		mat.set_shader_parameter("fogo", 0.8)
		_mats.append(mat)
	return true


static func _preparar_entalhe() -> void:
	if not _lum.is_empty():
		return
	var frente := Recinto.ler_imagem(FRENTE)
	# Claro-escuro da arte em 1/4 e a média da vizinhança (borrão em caixa nos dois eixos)
	var peq: Image = frente.duplicate()
	_lum_w = int(LARG_PX / 4.0)
	_lum_h = int(ALT_PX / 4.0)
	peq.resize(_lum_w, _lum_h, Image.INTERPOLATE_BILINEAR)
	var lum := PackedFloat32Array()
	lum.resize(_lum_w * _lum_h)
	for j in _lum_h:
		for i in _lum_w:
			lum[j * _lum_w + i] = peq.get_pixel(i, j).get_luminance()
	var media := lum.duplicate()
	var raio := 6
	for eixo in 2:
		var origem := media.duplicate()
		var passo := 1 if eixo == 0 else _lum_w
		var n_linha := _lum_w if eixo == 0 else _lum_h
		var n_outro := _lum_h if eixo == 0 else _lum_w
		for o in n_outro:
			var base := o * _lum_w if eixo == 0 else o
			var soma := 0.0
			var conta := 0
			for t in range(-raio, n_linha + raio):
				var entra := t + raio
				if entra < n_linha:
					soma += origem[base + entra * passo]
					conta += 1
				var sai := t - raio - 1
				if sai >= 0:
					soma -= origem[base + sai * passo]
					conta -= 1
				if t >= 0 and t < n_linha:
					media[base + t * passo] = soma / maxi(conta, 1)
	_lum = PackedFloat32Array()
	_lum.resize(lum.size())
	for k in lum.size():
		_lum[k] = lum[k] - media[k]


static func _entalhe(xtex: float, y: float) -> float:
	var i := clampi(int(xtex / 4.0), 0, _lum_w - 1)
	var j := clampi(int(y / 4.0), 0, _lum_h - 1)
	return clampf(_lum[j * _lum_w + i] * ENTALHE, -8.0, 10.0)


# ------------------------------------------------------------------ perfil de uma face

func _n(n: Array, y: float) -> float:
	return _a_nivel(n, y) + _x_extra(_xt, _xb, y)


## Linha da escadaria: do pé (um pouco à frente da base) ao terraço do alto.
func _linha_escada(y: float) -> float:
	var n_topo: float = NIVEIS[2][2] + _xt
	var n_base: float = NIVEIS[NIVEIS.size() - 1][3] + _xb + 15.0
	return n_topo + (y - TOPO_PX) / (BASE_PX - TOPO_PX) * (n_base - n_topo)


func _nivel_de(y: float) -> Array:
	for n: Array in NIVEIS:
		if y <= n[1]:
			return n
	return NIVEIS[NIVEIS.size() - 1]


func _escada_d(y: float) -> float:
	return maxf(_n(_nivel_de(y), y), _linha_escada(y)) + ESCADA_SAI


static func _meia_escada(y: float) -> float:
	return lerpf(58.0, 125.0, clampf((y - TOPO_PX) / (BASE_PX - TOPO_PX), 0.0, 1.0))


static func _meia_alfarda(y: float) -> float:
	return _meia_escada(y) + lerpf(22.0, 32.0, clampf((y - TOPO_PX) / (BASE_PX - TOPO_PX), 0.0, 1.0))


## Dados de um nível para a montagem: modo (repete o friso ou estica de leve), cortes da faixa.
func _dados_nivel(n: Array) -> Dictionary:
	var ya: float = n[0]
	var yb: float = n[1]
	var ym := (ya + yb) * 0.5
	var escada := ya >= TOPO_PX - 0.5
	var c: float = n[4]
	var periodo: float = n[2] - BORDA - c
	var x_min := minf(_x_extra(_xt, _xb, ya), _x_extra(_xt, _xb, yb))
	var repete := escada and x_min >= 0.0 and periodo >= 40.0
	var f := 1.0 if repete else _n(n, ym) / _a_nivel(n, ym)
	var d := {"n": n, "ya": ya, "yb": yb, "escada": escada, "c": c, "p": periodo, "repete": repete,
		"u_esc": (_meia_escada(ym) * f) if escada else 0.0, "u_alf": (_meia_alfarda(ym) * f) if escada else 0.0,
		"u_quina": _n(n, ya) - BORDA}
	var cortes := PackedFloat32Array()
	if repete:
		var u := c
		while u < d.u_quina - 1.0:
			cortes.append(u)
			u += periodo
		cortes.append(d.u_quina)
	d.cortes = cortes
	return d


## Pedaço da faixa onde fica |u|: -1 miolo, 0.. bloco repetido do friso, 9999 quina.
func _pedaco(d: Dictionary, ua: float) -> int:
	if not d.repete or ua < d.c:
		return -1
	if ua >= d.u_quina:
		return 9999
	return int((ua - d.c) / d.p)


## x da arte (a partir do eixo) para |u| no pedaço `ped`.
func _arte_x(d: Dictionary, ua: float, y: float, ped: int) -> float:
	var n: Array = d.n
	if not d.repete:
		return ua * _a_nivel(n, y) / _n(n, y)
	if ped == -1:
		return ua
	if ped == 9999:
		return maxf(_a_nivel(n, y) - 8.0 - (_n(n, y) - ua), 0.0)
	return ua - ped * float(d.p)


## Profundidade (px) de um ponto da face.
func _prof(d: Dictionary, reg: int, ped: int, ua: float, y: float, ax: float, xtex: float) -> float:
	var nn := _n(d.n, y)
	var base := nn
	var ent := _entalhe(xtex, y) * smoothstep(0.0, 12.0, nn - ua) * smoothstep(0.0, 6.0, y - d.ya) * smoothstep(0.0, 6.0, d.yb - y)
	if d.escada:
		if reg == ESCADA:
			base = _escada_d(y)
		elif reg == ALFARDA:
			base = _escada_d(y) + ALFARDA_SAI
			ent *= 0.6
	var z := base + ent
	if d.escada and ped == -1 and ax < 280.0:   # cabeças só no miolo (nos painéis repetidos não)
		for h: Array in CABECAS:
			var dx: float = ax - h[0]
			var dy: float = y - h[1]
			var rr: float = (dx * dx + dy * dy) / (h[2] * h[2])
			if rr < 1.0:
				z = maxf(z, _escada_d(h[1]) + ALFARDA_SAI + h[3] * sqrt(1.0 - rr))
	return z


# ------------------------------------------------------------------ malha

class _Sup:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	var cor := PackedColorArray()
	var idx := PackedInt32Array()

	func quad(p: Array, n: Array, t: Array, c: float) -> void:
		var b := pos.size()
		for k in 4:
			pos.append(p[k])
			nor.append(n[k])
			uv.append(t[k])
			cor.append(Color(c, c, c))
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_COLOR] = cor
		arr[Mesh.ARRAY_INDEX] = idx
		return arr


func _v(u: float, y: float, z: float) -> Vector3:
	return Vector3(u * _s, (BASE_PX - y) * _s, z * _s)


func _uv_arte(xtex: float, y: float) -> Vector2:
	return Vector2(xtex / LARG_PX, y / ALT_PX)


func _uv_cima(px: float, py: float) -> Vector2:
	return Vector2(px / LARG_PX, py / ALT_PX)


## Uma face (as outras três são ela girada): níveis em relevo, paredes entre células de alturas
## diferentes (bordas da escada, emendas do friso), terraços, tampa e saia.
func _malha() -> ArrayMesh:
	var arte := _Sup.new()
	var piso := _Sup.new()
	var niveis := _niveis(_templo)
	for ni in niveis.size():
		var n: Array = niveis[ni]
		var d := _dados_nivel(n)
		var ya: float = d.ya
		var yb: float = d.yb
		var u_max := _n(n, yb)
		# Colunas: grade, eixo, bordas da escada e da alfarda, emendas do friso
		var col: Array[float] = [0.0, u_max, -u_max]
		var g := CEL
		while g < u_max - 0.5:
			col.append(g)
			col.append(-g)
			g += CEL
		var extra: Array[float] = []
		if d.escada:
			extra.append_array([float(d.u_esc), float(d.u_alf)])
		for c: float in d.cortes:
			extra.append(c)
		for e in extra:
			if e > 0.5 and e < u_max - 0.5:
				col.append(e)
				col.append(-e)
		col.sort()
		var cols: Array[float] = []
		for c in col:
			if cols.is_empty() or c - cols[cols.size() - 1] > 0.5:
				cols.append(c)
		var nc := cols.size() - 1
		var linhas := maxi(1, ceili((yb - ya) / CEL))
		var ys: Array[float] = []
		for r in linhas + 1:
			ys.append(lerpf(ya, yb, float(r) / linhas))
		# Região e pedaço de cada coluna de células
		var reg := PackedInt32Array()
		var ped := PackedInt32Array()
		var lado := PackedFloat32Array()
		for i in nc:
			var um := (cols[i] + cols[i + 1]) * 0.5
			var ua := absf(um)
			lado.append(signf(um))
			ped.append(_pedaco(d, ua))
			var rg := FACE
			if d.escada and ua < d.u_esc:
				rg = ESCADA
			elif d.escada and ua < d.u_alf:
				rg = ALFARDA
			reg.append(rg)
		# Vértices de cada célula (cada uma com os seus: a pintura e a altura mudam nas emendas)
		var vp: Array = []   # [linha][célula] -> [4 Vector3]
		var vt: Array = []   # idem, uv
		for r in linhas:
			var lp: Array = []
			var lt: Array = []
			for i in nc:
				var ps: Array = []
				var ts: Array = []
				for canto in 4:
					var u: float = cols[i + (1 if canto == 1 or canto == 2 else 0)]
					var y: float = ys[r + (1 if canto >= 2 else 0)]
					var nn := _n(n, y)
					var uc := clampf(u, -nn, nn)
					var ua := absf(uc)
					var ax := _arte_x(d, ua, y, ped[i])
					var xtex := CX + lado[i] * ax
					ps.append(_v(uc, y, _prof(d, reg[i], ped[i], ua, y, ax, xtex)))
					ts.append(_uv_arte(xtex, y))
				lp.append(ps)
				lt.append(ts)
			vp.append(lp)
			vt.append(lt)
		# Normal lisa: média das células vizinhas da mesma região e pedaço
		var fn: Array = []
		for r in linhas:
			var l: Array = []
			for i in nc:
				var q: Array = vp[r][i]
				var q0: Vector3 = q[0]
				var q1: Vector3 = q[1]
				var q2: Vector3 = q[2]
				var q3: Vector3 = q[3]
				var nn := (q2 - q0).cross(q3 - q1)
				l.append(-nn.normalized() if nn.length_squared() > 1e-12 else Vector3.BACK)
			fn.append(l)
		for r in linhas:
			for i in nc:
				var ns: Array = []
				for canto in 4:
					var rr := r + (1 if canto >= 2 else 0)
					var ii := i + (1 if canto == 1 or canto == 2 else 0)
					var soma := Vector3.ZERO
					for r2 in [rr - 1, rr]:
						if r2 < 0 or r2 >= linhas:
							continue
						for i2 in [ii - 1, ii]:
							if i2 < 0 or i2 >= nc or reg[i2] != reg[i] or ped[i2] != ped[i]:
								continue
							soma += fn[r2][i2]
					ns.append(soma.normalized() if soma.length_squared() > 1e-12 else fn[r][i])
				arte.quad(vp[r][i], ns, vt[r][i], 1.0)
				# Parede até a célula da direita, se as duas não se encontram
				if i + 1 < nc:
					var a: Array = vp[r][i]
					var b: Array = vp[r][i + 1]
					if absf(a[1].z - b[0].z) > 0.02 or absf(a[2].z - b[3].z) > 0.02:
						var fora := Vector3.RIGHT if a[1].z > b[0].z else Vector3.LEFT
						arte.quad([a[1], b[0], b[3], a[2]], [fora, fora, fora, fora], [vt[r][i][1], vt[r][i][1], vt[r][i][2], vt[r][i][2]], 0.8)
		# Terraço em cima do nível (até a parede do nível de cima; no último, a tampa até o eixo)
		var n_cima := 0.0
		if ni > 0:
			n_cima = _n(niveis[ni - 1], ya)
		for i in nc:
			var q: Array = vp[0][i]
			var f0: Vector3 = q[0]
			var f1: Vector3 = q[1]
			if absf(f1.x - f0.x) < 1e-4:
				continue
			var t0 := maxf(n_cima * _s, absf(f0.x))
			var t1 := maxf(n_cima * _s, absf(f1.x))
			var fundo := (maxf(f0.z, f1.z) - n_cima * _s)
			if fundo < 0.01:
				continue
			# Em faixas da altura do ladrilho, espelhadas uma sim outra não: o piso fica no tamanho da arte
			var b0 := Vector3(f0.x, f0.y, t0)
			var b1 := Vector3(f1.x, f0.y, t1)
			var faixas := maxi(1, roundi(fundo / _s / TERRACO.size.y))
			var u0 := TERRACO.position.x + pingpong(f0.x / _s + 4000.0, TERRACO.size.x)
			var u1 := TERRACO.position.x + pingpong(f1.x / _s + 4000.0, TERRACO.size.x)
			for j in faixas:
				var a := float(j) / faixas
				var b := float(j + 1) / faixas
				var va := TERRACO.position.y + (TERRACO.size.y if j % 2 == 1 else 0.0)
				var vb := TERRACO.position.y + (0.0 if j % 2 == 1 else TERRACO.size.y)
				piso.quad([f0.lerp(b0, a), f1.lerp(b1, a), f1.lerp(b1, b), f0.lerp(b0, b)], [Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP],
					[_uv_cima(u0, va), _uv_cima(u1, va), _uv_cima(u1, vb), _uv_cima(u0, vb)], 1.0)
		# Saia: do pé da arte até abaixo do chão
		if ni == niveis.size() - 1:
			var r := linhas - 1
			for i in nc:
				var q: Array = vp[r][i]
				var b0: Vector3 = q[3]
				var b1: Vector3 = q[2]
				if absf(b1.x - b0.x) < 1e-4:
					continue
				var baixo := Vector3.DOWN * SAIA_M
				var tex: Array = []
				for pt: Vector3 in [b0, b1, b1 + baixo, b0 + baixo]:
					var px := BASE_PISO.position.x + pingpong(pt.x / _s + 4000.0, BASE_PISO.size.x)
					tex.append(_uv_arte(px, BASE_PISO.position.y + (BASE_PISO.size.y if pt.y < b0.y - 0.1 else 0.0)))
				arte.quad([b0, b1, b1 + baixo, b0 + baixo], [Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK], tex, 0.9)
	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arte.arrays())
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, piso.arrays())
	return malha


## Caixas de colisão (locais): cada nível pela parede de cima dele, e a escadaria das quatro faces.
func _colisoes() -> Array[Transform3D]:
	var cx: Array[Transform3D] = []
	var niveis := _niveis(_templo)
	for ni in niveis.size():
		var n: Array = niveis[ni]
		var m := _n(n, n[0]) * _s * 2.0
		var y0 := (BASE_PX - float(n[1])) * _s - (SAIA_M if ni == niveis.size() - 1 else 0.0)
		var y1 := (BASE_PX - float(n[0])) * _s
		cx.append(Transform3D(Basis.from_scale(Vector3(m, y1 - y0, m)), Vector3(0.0, (y0 + y1) * 0.5, 0.0)))
		if float(n[0]) >= TOPO_PX - 0.5:
			var fundo := _escada_d(n[0]) * _s
			var larg := _meia_alfarda(n[1]) * _s * 2.0
			for k in 4:
				var giro := Basis(Vector3.UP, k * PI * 0.5)
				cx.append(Transform3D(giro * Basis.from_scale(Vector3(larg, y1 - y0, fundo)), giro * Vector3(0.0, (y0 + y1) * 0.5, fundo * 0.5)))
	return cx
