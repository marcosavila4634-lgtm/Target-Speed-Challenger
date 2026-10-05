class_name PortaoSelva
extends Node3D
## Portão principal do Serpent's Climb (Recinto "Largada" com tema "selva"), IGUAL à arte do dono
## (assets/selva/portao/portao_principal.png, cópia de assets/MAPA SERPENTE/EXTRUTURAS/PORTÃO PRINCIPAL).
## A primeira versão, montada só com blocos, o dono rejeitou ("muito ruim, faça igual o que eu mandei").
## Agora a própria arte é a pele de uma escultura em relevo, nas duas faces:
## - a silhueta é recortada do fundo (TunelVulcao.texturas_arte) — o vão, os recortes e as folhas soltas;
## - cada pedaço sai da parede o tanto que sai na arte (_fundo: sapatas em degraus, ombreiras, verga,
##   letreiro, taças dos braseiros), a cabeça da serpente salta em volume, o corpo dela é um meio tubo
##   ao longo do desenho, e o entalhe fino vem do claro-escuro da pintura (o que é claro está na frente);
## - paredes laterais fecham a peça até o meio: tem corpo de qualquer ângulo, e colisão;
## - o fogo pintado dos braseiros é recortado e trocado por fogo de verdade, com luz;
## - semáforo pendurado embaixo da verga, do lado de dentro.
## Medidas em px da arte (1198 x 1313): _x/_y passam para metros (o vão, 350 px, é a largura da saída).
## Coordenadas locais: x = lateral do recinto, y = altura acima do piso, z = para dentro (z > 0 = arena).

const ARTE := "res://assets/selva/portao/portao_principal.png"
const LARG_PX := 1198.0
const ALT_PX := 1313.0
const CHAO_PX := 1246.0     # linha do chão na arte
const CELULA := 4.0         # px da arte por célula do relevo
const E0 := 10.0 / 350.0    # escala em que as profundidades de _fundo foram medidas

static var _malha_cache := {}

var _r: Recinto
var _e := E0             # metros por px da arte
var _colisoes: Array[Transform3D] = []
var _fy := -4.0


static func montar(r: Recinto) -> void:
	var p := PortaoSelva.new()
	p.name = "PortaoSelva"
	r.add_child(p)
	p._montar(r)


func _x(px: float, s := 1.0) -> float:
	return s * (px - 600.0) * _e


func _y(py: float) -> float:
	return (CHAO_PX - py) * _e


func _p(px: float, py: float, z: float, s := 1.0) -> Vector3:
	return Vector3(_x(px, s), _y(py), z)


func _montar(r: Recinto) -> void:
	_r = r
	_e = r.saida_largura / 350.0
	transform = Transform3D(Basis.looking_at(r.frente, Vector3.UP), r.pa(r.comprimento + Recinto.PAREDE * 0.5, 0.0, r.piso_y))
	_fy = minf(r.chao_y, r.piso_y - 2.0) - 1.0 - r.piso_y
	var tx := TunelVulcao.texturas_arte(ARTE, [])
	if tx.is_empty():
		return
	var malha := _relevo(tx, _e)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/arte_relevo.gdshader")
	mat.set_shader_parameter("imagem", tx[0])
	mat.set_shader_parameter("brilho", 0.42)   # a arte já vem iluminada pelas tochas: não pode apagar na contraluz
	mat.set_shader_parameter("fogo", 0.6)
	for f: float in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = malha
		mi.material_override = mat   # frente e laterais com a mesma pedra da arte (o shader desenha as duas faces: nada fica aberto)
		mi.transform = Transform3D(Basis.IDENTITY if f > 0.0 else Basis(Vector3.UP, PI), Vector3.ZERO)
		add_child(mi)
	_alicerce()
	for s: float in [1.0, -1.0]:
		_braseiro(s)
	_semaforo()
	_colidir()
	var no_mundo: Array[Transform3D] = []
	for c in _colisoes:
		no_mundo.append(transform * c)
	ComplexoLancamento.adicionar_colisoes(r.corpo, no_mundo)


# ------------------------------------------------------------------ relevo

## Quanto cada ponto da arte sai do meio da parede (m, na escala E0), sem o entalhe fino: sapatas em
## três degraus, ombreiras, verga, parede da faixa, letreiro, coroa, taças dos braseiros e a cabeça.
static func _fundo(px: float, py: float) -> float:
	var q := px if px < 600.0 else 1200.0 - px   # a arte é simétrica
	var z := 2.2
	if py > 1178.0:
		z = 3.5
	elif py > 1090.0:
		z = 3.25
	elif py > 1040.0:
		z = 3.0
	elif py > 520.0 and q > 262.0:
		z = 2.75
	if py > 520.0 and py < 636.0 and q > 392.0:
		z = 2.95
	if py >= 150.0 and py < 300.0 and q > 262.0:
		z = 2.5
	if py < 150.0:
		z = 2.0
	if py < 200.0 and q < 262.0:
		# Taça do braseiro: meia taça redonda
		var dx := (q - 182.0) / 72.0
		z = 1.0 + 1.5 * sqrt(maxf(1.0 - dx * dx, 0.0))
	# Cabeça da serpente: volume grande, o focinho mais para fora; leque de penas em volta
	var hx := (px - 600.0) / 96.0
	var hy := (py - 385.0) / 120.0
	var rho := hx * hx + hy * hy
	if rho < 1.0:
		z += 1.9 * pow(1.0 - rho, 0.6)
		var fx := (px - 600.0) / 62.0
		var fz := (py - 372.0) / 48.0
		z += 0.7 * maxf(1.0 - fx * fx - fz * fz, 0.0)
	elif rho < 2.4 and py > 235.0 and py < 505.0:
		z += 0.35 * (1.0 - (rho - 1.0) / 1.4)
	return z


## Malha do relevo de uma face: x = direita de quem olha, y = altura, z = para quem olha (0 = meio da
## parede). Cor do vértice = sombra das paredes laterais (arte_relevo.gdshader).
static func _relevo(tx: Array, e: float) -> ArrayMesh:
	var chave := "%.5f" % e
	if _malha_cache.has(chave):
		return _malha_cache[chave]
	var masc: Image = tx[5]
	var peq: Image = tx[6]
	var mw := masc.get_width()
	var mh := masc.get_height()
	var nx := int(LARG_PX / CELULA)
	var ny := int(ALT_PX / CELULA)
	var k_e := e / E0
	# Dentro/fora e claro-escuro de cada célula
	var dentro := PackedByteArray()
	dentro.resize(nx * ny)
	var lum := PackedFloat32Array()
	lum.resize(nx * ny)
	for j in ny:
		var py := (j + 0.5) * CELULA
		for i in nx:
			var px := (i + 0.5) * CELULA
			var mx := clampi(int(px / LARG_PX * mw), 0, mw - 1)
			var my := clampi(int(py / ALT_PX * mh), 0, mh - 1)
			var q := px if px < 600.0 else 1200.0 - px
			var chama := py < 142.0 and q > 100.0 and q < 262.0   # o fogo pintado sai: entra fogo de verdade
			# O vão sai inteiro, num retângulo limpo (o cinza do fundo fica cercado pela pedra e o recorte pelas
			# bordas não chega nele; os cipós pintados lá dentro virariam lascas atravessadas na passagem)
			var vao := q > 427.0 and py > 638.0
			dentro[j * nx + i] = 1 if masc.get_pixel(mx, my).r > 0.5 and py < CHAO_PX and not chama and not vao else 0
			lum[j * nx + i] = peq.get_pixel(mx, my).get_luminance()
	# Claro-escuro médio da vizinhança (borrão em caixa nos dois eixos): o entalhe é a diferença para ele
	var media := lum.duplicate()
	var raio := 6
	for eixo in 2:
		var origem := media.duplicate()
		var passo := 1 if eixo == 0 else nx
		var n_linha := nx if eixo == 0 else ny
		var n_outro := ny if eixo == 0 else nx
		for o in n_outro:
			var base := o * nx if eixo == 0 else o
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
	# Corpo da serpente: meio tubo ao longo do desenho (os dois lados da cabeça)
	var corpo := PackedVector2Array([Vector2(520, 398), Vector2(486, 392), Vector2(430, 404), Vector2(382, 432), Vector2(332, 452),
		Vector2(282, 452), Vector2(244, 436), Vector2(228, 404), Vector2(246, 378), Vector2(278, 376), Vector2(296, 398), Vector2(290, 420), Vector2(272, 426)])
	var curva := Curve2D.new()
	curva.bake_interval = 6.0
	for i in corpo.size():
		var h := (corpo[mini(i + 1, corpo.size() - 1)] - corpo[maxi(i - 1, 0)]) / 6.0
		curva.add_point(corpo[i], -h, h)
	var tubo := curva.get_baked_points()
	# Altura de cada célula
	var hc := PackedFloat32Array()
	hc.resize(nx * ny)
	for j in ny:
		var py := (j + 0.5) * CELULA
		for i in nx:
			var k := j * nx + i
			if dentro[k] == 0:
				continue
			var px := (i + 0.5) * CELULA
			var q := px if px < 600.0 else 1200.0 - px
			var z := _fundo(px, py)
			if py > 340.0 and py < 490.0 and q > 195.0 and q < 540.0:
				var melhor := INF
				var onde := 0
				for t in tubo.size():
					var d := Vector2(q, py).distance_squared_to(tubo[t])
					if d < melhor:
						melhor = d
						onde = t
				var rt := lerpf(33.0, 12.0, float(onde) / (tubo.size() - 1))
				if melhor < rt * rt:
					z += sqrt(rt * rt - melhor) * E0 * 0.85
			# Entalhe: o que é mais claro que a vizinhança está na frente. Letras de ouro e relevos grandes saem mais
			var ganho := 1.5
			if py >= 150.0 and py < 300.0 and q > 262.0:
				ganho = 1.1   # letreiro: mais que isso as letras se desmancham vistas de lado
			elif q < 262.0 and py > 540.0 and py < 1040.0:
				ganho = 2.2
			z += clampf((lum[k] - media[k]) * ganho, -0.4, 0.5)
			hc[k] = maxf(z, 0.4) * k_e
	# Alisa de leve (tira o serrilhado célula a célula sem apagar os degraus)
	var liso := hc.duplicate()
	for j in range(1, ny - 1):
		for i in range(1, nx - 1):
			var k := j * nx + i
			if dentro[k] == 0:
				continue
			var soma := hc[k] * 2.0
			var peso := 2.0
			for viz: int in [k - 1, k + 1, k - nx, k + nx]:
				if dentro[viz] == 1:
					soma += hc[viz]
					peso += 1.0
			liso[k] = soma / peso
	hc = liso
	# Vértices: cantos das células, altura = média das células de dentro em volta
	var vw := nx + 1
	var pos := PackedVector3Array()
	pos.resize(vw * (ny + 1))
	var usado := PackedByteArray()
	usado.resize(vw * (ny + 1))
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
			pos[j * vw + i] = Vector3((i * CELULA - 600.0) * e, (CHAO_PX - j * CELULA) * e, soma / maxi(conta, 1))
	var nor := PackedVector3Array()
	nor.resize(pos.size())
	var uv := PackedVector2Array()
	uv.resize(pos.size())
	var cor := PackedColorArray()
	cor.resize(pos.size())
	for j in ny + 1:
		for i in vw:
			var k := j * vw + i
			uv[k] = Vector2(i * CELULA / LARG_PX, j * CELULA / ALT_PX)
			cor[k] = Color.WHITE
			if usado[k] == 0:
				nor[k] = Vector3.BACK
				continue
			var ka := j * vw + mini(i + 1, nx)
			var kb := j * vw + maxi(i - 1, 0)
			var kc := maxi(j - 1, 0) * vw + i
			var kd := mini(j + 1, ny) * vw + i
			var a := (pos[ka] if usado[ka] == 1 else pos[k]) - (pos[kb] if usado[kb] == 1 else pos[k])
			var b := (pos[kc] if usado[kc] == 1 else pos[k]) - (pos[kd] if usado[kd] == 1 else pos[k])
			var nn := a.cross(b)
			nor[k] = nn.normalized() if nn.length_squared() > 1e-10 else Vector3.BACK
	var idx := PackedInt32Array()
	for j in ny:
		for i in nx:
			if dentro[j * nx + i] == 0:
				continue
			var c := [j * vw + i, j * vw + i + 1, (j + 1) * vw + i + 1, (j + 1) * vw + i]
			idx.append_array([c[0], c[1], c[2], c[0], c[2], c[3]])
			# Paredes laterais onde o vizinho está fora, até o meio da parede
			for lado: Array in [[0, 1, 0, -1, Vector3.UP], [1, 2, 1, 0, Vector3.RIGHT], [2, 3, 0, 1, Vector3.DOWN], [3, 0, -1, 0, Vector3.LEFT]]:
				var vi: int = i + lado[2]
				var vj: int = j + lado[3]
				if vi >= 0 and vi < nx and vj >= 0 and vj < ny and dentro[vj * nx + vi] == 1:
					continue
				# A parede leva a MESMA pedra da arte (pedido do dono): a faixa lisa de blocos da ombreira
				# (px 270–298, py 530–1030), deitada na espessura e repetida em espelho na altura e ao longo
				var base := pos.size()
				for ponta: int in [lado[0], lado[1]]:
					var pf := pos[c[ponta]]
					var corre := uv[c[ponta]].y * ALT_PX if (lado[4] as Vector3).y == 0.0 else uv[c[ponta]].x * LARG_PX
					var v_px := 530.0 + pingpong(corre - 530.0, 500.0)
					for tras in 2:
						pos.append(pf if tras == 0 else Vector3(pf.x, pf.y, 0.0))
						nor.append(lado[4])
						uv.append(Vector2((296.0 if tras == 0 else 272.0) / LARG_PX, v_px / ALT_PX))
						cor.append(Color(0.85, 0.85, 0.85) if tras == 0 else Color(0.6, 0.6, 0.6))
				idx.append_array([base, base + 2, base + 3, base, base + 3, base + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = cor
	arr[Mesh.ARRAY_INDEX] = idx
	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_malha_cache[chave] = malha
	return malha


# ------------------------------------------------------------------ peças de verdade

## Alicerce de pedra embaixo das sapatas até o chão (a largada fica num pedestal: sem ele o lado de fora
## do portão ficava no ar).
func _alicerce() -> void:
	var pedra: Array[Transform3D] = []
	for s: float in [1.0, -1.0]:
		var a := _p(8, CHAO_PX, 0.0, s)
		var b := _p(425, CHAO_PX, 0.0, s)
		pedra.append(Transform3D(Basis.from_scale(Vector3(absf(b.x - a.x), -_fy, 7.0 * _e / E0)), Vector3((a.x + b.x) * 0.5, _fy * 0.5, 0.0)))
	ComplexoLancamento.criar_multimesh(self, pedra, Selva.material_pedra(0, 1.1))
	_colisoes.append_array(pedra)


## Fogo de verdade na taça do braseiro (a chama pintada foi recortada), brasa e luz.
func _braseiro(s: float) -> void:
	var base := _p(182, 150, 0.0, s)
	var brasa := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = 62.0 * _e
	disco.bottom_radius = 62.0 * _e
	disco.height = 0.3
	brasa.mesh = disco
	var mb := StandardMaterial3D.new()
	mb.albedo_color = Color(0.2, 0.06, 0.02)
	mb.emission_enabled = true
	mb.emission = Color(1.0, 0.42, 0.08)
	mb.emission_energy_multiplier = 3.0
	brasa.material_override = mb
	brasa.scale = Vector3(1.0, 1.0, 0.75)
	brasa.position = base
	add_child(brasa)
	Fogo.criar(self, base + Vector3.UP * 0.3, 1.3, 5.0, 34, 2.0)
	for f: float in [1.0, -1.0]:
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.6, 0.26)
		luz.light_energy = 3.2
		luz.omni_range = 30.0
		luz.shadow_enabled = false
		luz.position = base + Vector3(0.0, 2.0, f * 6.0)
		add_child(luz)


## Semáforo pendurado embaixo da verga, virado para dentro: caixa de pedra escura com as três luzes.
func _semaforo() -> void:
	var y := _y(636) - 1.25
	var z := 1.6
	var caixa := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(7.6, 2.1, 0.7)
	caixa.mesh = cm
	var pedra := StandardMaterial3D.new()
	pedra.albedo_color = Color(0.17, 0.14, 0.1)
	pedra.roughness = 0.9
	caixa.material_override = pedra
	caixa.position = Vector3(0.0, y, z)
	add_child(caixa)
	var lampada := CylinderMesh.new()
	lampada.top_radius = 0.75
	lampada.bottom_radius = 0.75
	lampada.height = 0.25
	lampada.radial_segments = 24
	for k in 3:
		var l := MeshInstance3D.new()
		l.mesh = lampada
		l.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3((k - 1) * 2.3, y, z + 0.42))
		add_child(l)
		_r.semaforo_lampadas.append(l)
	_colisoes.append(Transform3D(Basis.from_scale(Vector3(7.6, 2.1, 0.8)), Vector3(0.0, y, z)))


## Colisão: sapatas, torres com as ombreiras, tudo acima do vão, a cabeça da serpente e os braseiros.
func _colidir() -> void:
	for s: float in [1.0, -1.0]:
		_colide(8, 425, 1040, CHAO_PX, 3.5, s)
		_colide(85, 425, 195, 1040, 2.9, s)
		_colide(108, 256, 132, 195, 2.6, s)
	_colide(262, 938, 150, 636, 3.0)
	_colide(395, 805, 30, 150, 2.4)
	_colide(500, 700, 262, 505, 5.0)


func _colide(px0: float, px1: float, py0: float, py1: float, meia: float, s := 1.0) -> void:
	var a := _p(px0, py0, -meia * _e / E0, s)
	var b := _p(px1, py1, meia * _e / E0, s)
	_colisoes.append(Transform3D(Basis.from_scale((b - a).abs()), (a + b) * 0.5))
