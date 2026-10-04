extends RefCounted
## Esmagador do Frozen Peak (armadilha "prensas"), pela arte do dono em
## assets/frozen/extruturas/esmagador.png ("exatamente como está na imagem"). Tudo em geometria:
## - dois pilares de treliça de aço junto da passagem, com miolo de blocos de gelo aceso, cintas,
##   diagonais, grampos amarelos e o trilho cromado por onde o bloco corre;
## - viga alta de aço rebitado com a tela preta (mostrador: arma em ciano, pisca vermelho na queda),
##   duas faixas de luz, suportes laterais, neve grossa, motores e canos por cima, pingentes embaixo;
## - de cada lado, muralha de blocos de gelo em três degraus (cada bloco é uma peça chanfrada, com a
##   luz saindo pelas frestas), colunas de aço, respiros de luz, quadro de aço em X na frente, máquinas
##   no pé, mangueiras sanfonadas pretas com abraçadeiras, neve com pingentes em cada degrau;
## - o bloco que desce: gelo com os dois faróis vermelhos em aro de aço e a faixa amarela e preta;
## - a base: maciço de blocos de gelo em degraus do chão até a estrada, com cintas de aço, pingentes,
##   contrafortes de cristal e montes de neve no pé (nada flutua).
## Coordenadas do nó: x = lateral, y = altura acima do asfalto, z = ao longo da estrada (centrado).

const PORTAO := "res://scripts/mundo/portao_gelo.gd"
const ALTO := 5.5         # altura do bloco que desce
const Y_VIGA := 17.0      # fundo da viga (aberto, o bloco fica de 11 a 16,5 m)
const Y_TOPO := 22.6
const Y_BASE := -1.5      # topo do maciço de gelo (a laje de aço das alas vai daí até o asfalto)
const ACO := Color(0.115, 0.125, 0.145)
const ACO_CLARO := Color(0.27, 0.285, 0.31)
const AMARELO := Color(0.86, 0.58, 0.06)
const UVS := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]

static var _mats := {}

var _rng := RandomNumberGenerator.new()
var _gelo := SurfaceTool.new()
var _gelo_base := SurfaceTool.new()   # maciço da base: o gelo de gotejamento dos maciços dos alvos (pedido do dono)
var _nucleo := SurfaceTool.new()
var _aco := SurfaceTool.new()
var _listras := SurfaceTool.new()
var _luz := SurfaceTool.new()
var _luz_viga := SurfaceTool.new()
var _ambar := SurfaceTool.new()
var _borracha := SurfaceTool.new()
var _geo: Node3D          # PortaoGelo emprestado: neve, pingentes e cristais
var _col: Array[Transform3D] = []
var _col_base: Array[Transform3D] = []
var _picos_base: Array = []


# ------------------------------------------------------------------ entrada

## Monta a estrutura fixa em `pai` (meia largura da estrada `meia`, comprimento `comp` do bloco,
## `fundo` = y local do chão). Devolve {colisao, base (caixas, espaço de `pai`), tela, faixas
## (materiais animados), hastes (nós), luzes, estouro}.
static func montar(pai: Node3D, meia: float, comp: float, fundo: float, semente: int) -> Dictionary:
	var e = load("res://scripts/mundo/esmagador_gelo.gd").new()
	return e._montar(pai, meia, comp, fundo, semente)


## Monta o bloco que desce em `corpo` (origem na face de baixo). Devolve {lampadas, luzes}.
static func bloco(corpo: Node3D, largura: float, comp: float, semente: int) -> Dictionary:
	var e = load("res://scripts/mundo/esmagador_gelo.gd").new()
	return e._bloco(corpo, largura, comp, semente)


# ------------------------------------------------------------------ materiais

static func _material(nome: String) -> Material:
	if _mats.has(nome):
		return _mats[nome]
	var m: Material
	match nome:
		"gelo":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/esmagador_gelo.gdshader")
			s.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 311))
			m = s
		"aco", "listras":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/esmagador_aco.gdshader")
			s.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 311))
			s.set_shader_parameter("listras", 1.0 if nome == "listras" else 0.0)
			s.set_shader_parameter("geada", 0.1 if nome == "listras" else 0.26)
			m = s
		"nucleo":
			m = ComplexoLancamento._material_luz(Color(0.3, 0.8, 1.0), 3.2)
		"luz":
			m = ComplexoLancamento._material_luz(Color(0.5, 0.9, 1.0), 6.0)
		"ambar":
			m = ComplexoLancamento._material_luz(Color(1.0, 0.6, 0.1), 5.0)
		"borracha":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.035, 0.036, 0.04)
			b.roughness = 0.5
			b.metallic = 0.1
			m = b
		"pingente":
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/portao_gelo.gdshader")
			s.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 311))
			s.set_shader_parameter("cor_rasa", Color(0.9, 0.97, 1.0))
			s.set_shader_parameter("cor_funda", Color(0.55, 0.8, 0.98))
			s.set_shader_parameter("brilho", 0.7)
			s.set_shader_parameter("rachadura", 0.0)
			s.set_shader_parameter("relevo", 0.2)
			s.set_shader_parameter("neve", 0.0)
			m = s
		"cromo":
			m = ComplexoLancamento._material_metal(Color(0.78, 0.8, 0.84), 1.0, 0.16)
	_mats[nome] = m
	return m


# ------------------------------------------------------------------ montagem

func _comecar(semente: int) -> void:
	_rng.seed = semente
	for st: SurfaceTool in [_gelo, _gelo_base, _nucleo, _aco, _listras, _luz, _luz_viga, _ambar, _borracha]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_geo = load(PORTAO).new()
	(_geo.get("_rng") as RandomNumberGenerator).seed = semente + 7
	for nome: String in ["_st_cristal", "_st_neve", "_st_pico"]:
		(_geo.get(nome) as SurfaceTool).begin(Mesh.PRIMITIVE_TRIANGLES)


## Fecha as malhas em `pai`. Devolve o material das faixas de luz da viga (próprio de cada esmagador).
func _fechar(pai: Node3D) -> StandardMaterial3D:
	var faixas := ComplexoLancamento._material_luz(Color(0.5, 0.9, 1.0), 6.0)
	var portao = load(PORTAO)
	for par: Array in [[_gelo, _material("gelo")], [_gelo_base, Gelo.material_fenda()], [_nucleo, _material("nucleo")], [_aco, _material("aco")],
			[_listras, _material("listras")], [_luz, _material("luz")], [_luz_viga, faixas], [_ambar, _material("ambar")],
			[_borracha, _material("borracha")], [_geo.get("_st_cristal"), _material("pingente")],
			[_geo.get("_st_neve"), Gelo.material(Gelo.Mat.NEVE)], [_geo.get("_st_pico"), portao._material("geleira")]]:
		var malha: ArrayMesh = (par[0] as SurfaceTool).commit()
		if malha == null or malha.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = malha
		mi.material_override = par[1]
		if par[0] == _nucleo or par[0] == _luz or par[0] == _luz_viga or par[0] == _ambar:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pai.add_child(mi)
	_geo.free()
	return faixas


func _montar(pai: Node3D, meia: float, comp: float, fundo: float, semente: int) -> Dictionary:
	_comecar(semente)
	var g := meia + 0.75
	var zf := comp * 0.5
	for s: float in [-1.0, 1.0]:
		_pilar(s, g, zf, comp)
		_alas(s, g, zf, meia)
		_mangueiras(s, g, zf)
	_viga_alta(g, zf)
	_base(g, zf, fundo)
	var faixas := _fechar(pai)
	var gl := Gelo.new()
	gl.macico(pai, _picos_base, semente + 3)
	gl.free()

	# Tela nas duas faces da viga
	var tela := ShaderMaterial.new()
	tela.shader = load("res://shaders/esmagador_tela.gdshader")
	var hz := zf + 1.15
	var q := QuadMesh.new()
	q.size = _tela_tam(meia)
	for f: float in [1.0, -1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = tela
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis.IDENTITY if f > 0.0 else Basis(Vector3.UP, PI), Vector3(0.0, _tela_y(), f * (hz + 0.03)))
		pai.add_child(mi)
	# Hastes cromadas dos pistões: da viga até o topo do bloco (esticam com ele)
	var hastes: Array = []
	var cil := CylinderMesh.new()
	cil.top_radius = 0.24
	cil.bottom_radius = 0.24
	cil.height = 1.0
	cil.radial_segments = 14
	cil.rings = 1
	for s: float in [-1.0, 1.0]:
		for f: float in [-1.0, 1.0]:
			var h := MeshInstance3D.new()
			h.mesh = cil
			h.material_override = _material("cromo")
			h.position = Vector3(s * (meia + 0.5) * 0.6, Y_VIGA, f * zf * 0.5)
			pai.add_child(h)
			hastes.append(h)
	# Luz ciano das alas e vapor dos motores
	var luzes: Array = []
	for s: float in [-1.0, 1.0]:
		for f: float in [-1.0, 1.0]:
			var l := OmniLight3D.new()
			l.light_color = Color(0.35, 0.8, 1.0)
			l.light_energy = 2.2
			l.omni_range = 15.0
			l.shadow_enabled = false
			l.position = Vector3(s * (g + 9.0), 6.0, f * (zf + 5.5))
			pai.add_child(l)
		pai.add_child(_vapor(Vector3(s * 3.6, Y_TOPO + 2.0, 0.0)))
	return {"colisao": _col, "base": _col_base, "tela": tela, "faixas": faixas, "hastes": hastes, "luzes": luzes,
		"estouro": _estouro(pai, meia, comp), "h_ant": 11.0}


func _tela_tam(meia: float) -> Vector2:
	return Vector2((meia + 0.5) * 1.3, 2.5)


func _tela_y() -> float:
	return (Y_VIGA + 1.6 + Y_TOPO - 0.6) * 0.5


# ------------------------------------------------------------------ peças fixas

## Pilar junto da passagem: miolo de gelo dentro de uma gaiola de aço (montantes, cintas, diagonais em
## zigue-zague na frente e atrás, X por fora, grampos amarelos) e os trilhos cromados do bloco.
func _pilar(s: float, g: float, zf: float, comp: float) -> void:
	var x0 := g
	var x1 := g + 2.8
	var zp := zf + 1.0
	var xm := (x0 + x1) * 0.5
	_gelo_s(s, x0 + 0.3, x1 - 0.3, 0.0, Y_VIGA, -(zp - 0.3), zp - 0.3, 2.1, 1.15)
	for fx: float in [x0 + 0.25, x1 - 0.25]:
		for fz: float in [-1.0, 1.0]:
			_caixa(_aco, Vector3(s * fx, Y_VIGA * 0.5, fz * (zp - 0.25)), Vector3(0.55, Y_VIGA, 0.55), ACO)
	var niveis := [0.4, 4.4, 8.5, 12.6, Y_VIGA - 0.4]
	for k in niveis.size():
		var y: float = niveis[k]
		for fz: float in [-1.0, 1.0]:
			_caixa(_aco, Vector3(s * xm, y, fz * zp), Vector3(3.0, 0.75, 0.32), ACO)
			for fx: float in [x0 + 0.25, x1 - 0.25]:
				_caixa(_aco, Vector3(s * fx, y, fz * (zp + 0.14)), Vector3(0.66, 0.95, 0.3), AMARELO if k % 2 == 1 else ACO_CLARO)
		_caixa(_aco, Vector3(s * x1, y, 0.0), Vector3(0.32, 0.75, zp * 2.0), ACO)
		_caixa(_aco, Vector3(s * (x0 + 0.06), y, 0.0), Vector3(0.14, 0.55, zp * 2.0), ACO)
	for k in niveis.size() - 1:
		var y0: float = niveis[k] + 0.35
		var y1: float = niveis[k + 1] - 0.35
		var xa := x0 + 0.5 if k % 2 == 0 else x1 - 0.5
		var xb := x1 - 0.5 if k % 2 == 0 else x0 + 0.5
		for fz: float in [-1.0, 1.0]:
			_barra(_aco, Vector3(s * xa, y0, fz * zp), Vector3(s * xb, y1, fz * zp), 0.36, 0.18, Vector3.BACK, ACO)
		_barra(_aco, Vector3(s * x1, y0, -zp + 0.5), Vector3(s * x1, y1, zp - 0.5), 0.34, 0.18, Vector3.RIGHT, ACO)
		_barra(_aco, Vector3(s * x1, y0, zp - 0.5), Vector3(s * x1, y1, -zp + 0.5), 0.34, 0.18, Vector3.RIGHT, ACO)
		_caixa(_aco, Vector3(s * (x1 + 0.1), (y0 + y1) * 0.5, 0.0), Vector3(0.22, 0.9, 0.9), ACO_CLARO)
	# Sapata e trilhos-guia
	_caixa(_aco, Vector3(s * xm, 0.5, 0.0), Vector3(3.3, 1.0, zp * 2.0 + 0.5), ACO)
	for fz: float in [-0.35, 0.35]:
		_caixa(_aco, Vector3(s * (g - 0.02), Y_VIGA * 0.5, fz * comp), Vector3(0.22, Y_VIGA, 0.34), ACO_CLARO)
	# Faixa de luz ciano em pé, por dentro da gaiola
	for fz: float in [-1.0, 1.0]:
		_caixa(_luz, Vector3(s * xm, 6.4, fz * (zp - 0.2)), Vector3(0.2, 3.2, 0.12), Color.WHITE)
	_col.append(Transform3D(Basis.from_scale(Vector3(2.8, Y_VIGA, zp * 2.0)), Vector3(s * xm, Y_VIGA * 0.5, 0.0)))


## Alas de um lado: três degraus de muralha de blocos de gelo (19,5 m, 14 m e 6,5 m), neve grossa com
## pingentes em cada topo, colunas de aço, respiros e faixas de luz; na frente e atrás, o quadro de aço
## em X com gelo dentro e as máquinas do pé. Tudo apoiado na laje de aço ao lado da estrada.
func _alas(s: float, g: float, zf: float, meia: float) -> void:
	var xa0 := g + 2.8
	var xa1 := g + 8.8
	var xb1 := g + 13.2
	var xc1 := g + 17.2
	var za := zf + 0.4
	var zb := zf - 0.4
	var zc := zf - 1.4
	# Degrau alto
	_gelo_s(s, xa0, xa1, 0.0, 19.5, -za, za, 2.15)
	_geo.call("_almofada", Vector3(s * (xa0 + xa1) * 0.5, 19.5, 0.0), 3.2, za + 0.3, 1.6)
	_col.append(Transform3D(Basis.from_scale(Vector3(xa1 - xa0, 21.0, za * 2.0)), Vector3(s * (xa0 + xa1) * 0.5, 10.5, 0.0)))
	# Degrau do meio
	_gelo_s(s, xa1, xb1, 0.0, 14.0, -zb, zb, 2.2)
	_geo.call("_almofada", Vector3(s * (xa1 + xb1) * 0.5 + s * 0.3, 14.0, 0.0), 2.3, zb + 0.3, 1.5)
	_col.append(Transform3D(Basis.from_scale(Vector3(xb1 - xa1, 15.5, zb * 2.0)), Vector3(s * (xa1 + xb1) * 0.5, 7.75, 0.0)))
	# Degrau baixo
	_gelo_s(s, xb1, xc1, 0.0, 6.5, -zc, zc, 2.1)
	_geo.call("_almofada", Vector3(s * (xb1 + xc1) * 0.5 + s * 0.2, 6.5, 0.0), 2.1, zc + 0.3, 1.3)
	_col.append(Transform3D(Basis.from_scale(Vector3(xc1 - xb1, 7.8, zc * 2.0)), Vector3(s * (xb1 + xc1) * 0.5, 3.9, 0.0)))
	for f: float in [-1.0, 1.0]:
		# Colunas de aço com flanges na quina de cada degrau
		for col: Array in [[xa1 - 0.3, 19.3, za], [xb1 - 0.3, 13.8, zb]]:
			var cx: float = col[0]
			var ch: float = col[1]
			var cz: float = col[2]
			_caixa(_aco, Vector3(s * cx, ch * 0.5, f * (cz + 0.2)), Vector3(1.0, ch, 0.55), ACO)
			var y := 1.2
			var k := 0
			while y < ch - 0.6:
				_caixa(_aco, Vector3(s * cx, y, f * (cz + 0.3)), Vector3(1.35, 0.6, 0.6), AMARELO if k % 3 == 1 else ACO_CLARO)
				y += 3.1
				k += 1
		# Respiros de luz (três barras) e faixas em pé
		_respiro(Vector3(s * (xa0 + 3.4), 16.4, f * (za + 0.12)), f, 2.0, 1.15)
		_respiro(Vector3(s * (xa1 + 2.0), 11.4, f * (zb + 0.12)), f, 1.7, 1.0)
		_caixa(_luz, Vector3(s * (xa0 + 0.55), 13.6, f * (za + 0.1)), Vector3(0.22, 4.2, 0.12), Color.WHITE)
		_caixa(_luz, Vector3(s * (xa1 + 0.9), 5.2, f * (zb + 0.1)), Vector3(0.2, 3.4, 0.12), Color.WHITE)
		_quadro(s, f, g, zf)
		_maquinas(s, f, g, zf)
	# Laje de aço das alas (do maciço de gelo até o nível do asfalto), com faixa de advertência na beira
	var lx0 := meia + 0.45
	var lx1 := g + 19.2
	var lz := zf + 4.6
	_caixa(_aco, Vector3(s * (lx0 + lx1) * 0.5, Y_BASE * 0.5, 0.0), Vector3(lx1 - lx0, -Y_BASE, lz * 2.0), ACO)
	for f: float in [-1.0, 1.0]:
		_caixa(_listras, Vector3(s * (lx0 + lx1) * 0.5, -0.35, f * (lz + 0.04)), Vector3(lx1 - lx0, 0.55, 0.1), Color.WHITE)
	_caixa(_listras, Vector3(s * (lx1 + 0.04), -0.35, 0.0), Vector3(0.1, 0.55, lz * 2.0), Color.WHITE)
	_col.append(Transform3D(Basis.from_scale(Vector3(lx1 - lx0, -Y_BASE, lz * 2.0)), Vector3(s * (lx0 + lx1) * 0.5, Y_BASE * 0.5, 0.0)))


## Quadro de aço em X encostado na face do degrau alto, com blocos de gelo dentro, faixa de luz, e neve
## com pingentes em cima.
func _quadro(s: float, f: float, g: float, zf: float) -> void:
	var x0 := g + 3.3
	var x1 := g + 8.3
	var xm := (x0 + x1) * 0.5
	var z0 := zf + 0.4
	var z1 := zf + 2.6
	_gelo_s(s, x0 + 0.4, x1 - 0.4, 0.0, 9.2, minf(f * z0, f * (z1 - 0.4)), maxf(f * z0, f * (z1 - 0.4)), 1.9, 1.1)
	for fx: float in [x0 + 0.25, x1 - 0.25]:
		_caixa(_aco, Vector3(s * fx, 5.0, f * (z1 - 0.25)), Vector3(0.55, 10.0, 0.55), ACO)
		for y: float in [1.3, 5.0, 8.6]:
			_caixa(_aco, Vector3(s * fx, y, f * (z1 - 0.1)), Vector3(0.75, 0.7, 0.4), AMARELO if y == 5.0 else ACO_CLARO)
	_caixa(_aco, Vector3(s * xm, 9.6, f * (z0 + z1) * 0.5), Vector3(x1 - x0 + 0.3, 0.8, z1 - z0 + 0.2), ACO)
	_caixa(_aco, Vector3(s * xm, 0.45, f * (z1 - 0.2)), Vector3(x1 - x0, 0.9, 0.45), ACO)
	_barra(_aco, Vector3(s * (x0 + 0.5), 0.9, f * (z1 - 0.12)), Vector3(s * (x1 - 0.5), 9.2, f * (z1 - 0.12)), 0.44, 0.2, Vector3.BACK, ACO)
	_barra(_aco, Vector3(s * (x1 - 0.5), 0.9, f * (z1 - 0.06)), Vector3(s * (x0 + 0.5), 9.2, f * (z1 - 0.06)), 0.44, 0.2, Vector3.BACK, ACO)
	_caixa(_aco, Vector3(s * xm, 5.05, f * (z1 + 0.02)), Vector3(1.0, 1.0, 0.3), ACO_CLARO)
	_caixa(_luz, Vector3(s * (x0 + 0.95), 6.2, f * (z1 - 0.32)), Vector3(0.2, 3.6, 0.12), Color.WHITE)
	_geo.call("_almofada", Vector3(s * xm, 10.0, f * (z0 + z1) * 0.5), 2.85, 1.35, 1.4)
	_col.append(Transform3D(Basis.from_scale(Vector3(x1 - x0, 11.0, z1 - z0)), Vector3(s * xm, 5.5, f * (z0 + z1) * 0.5)))


## Máquinas do pé: dois geradores de aço com respiro de luz, chapa de advertência, luz âmbar e neve em
## cima, e um caixote.
func _maquinas(s: float, f: float, g: float, zf: float) -> void:
	for m: Array in [[g + 10.9, zf + 1.1, 3.2, 3.8, 2.8], [g + 15.2, zf + 0.2, 2.8, 3.2, 2.6]]:
		var x: float = m[0]
		var z: float = m[1]
		var t := Vector3(m[2], m[3], m[4])
		var frente := f * (z + t.z * 0.5)
		_caixa(_aco, Vector3(s * x, t.y * 0.5, f * z), t, ACO)
		_caixa(_aco, Vector3(s * x, 0.3, f * z), t + Vector3(0.3, -t.y + 0.6, 0.3), ACO)
		_caixa(_aco, Vector3(s * x, t.y - 0.25, f * z), t + Vector3(0.2, -t.y + 0.5, 0.2), ACO_CLARO)
		_respiro(Vector3(s * (x + 0.35), t.y * 0.52, frente + f * 0.05), f, 1.5, 1.0)
		_caixa(_listras, Vector3(s * (x - t.x * 0.5 + 0.38), t.y * 0.45, frente + f * 0.03), Vector3(0.45, t.y * 0.5, 0.08), Color.WHITE)
		_caixa(_ambar, Vector3(s * (x - t.x * 0.5 + 0.38), t.y * 0.82, frente + f * 0.04), Vector3(0.36, 0.13, 0.08), Color.WHITE)
		_geo.call("_almofada", Vector3(s * x, t.y, f * z), t.x * 0.5 + 0.1, t.z * 0.5 + 0.1, 1.0)
		_col.append(Transform3D(Basis.from_scale(t), Vector3(s * x, t.y * 0.5, f * z)))
	var cx := g + 13.1
	var cz := zf + 1.6
	_caixa(_aco, Vector3(s * cx, 0.9, f * cz), Vector3(1.7, 1.8, 1.7), ACO)
	_geo.call("_almofada", Vector3(s * cx, 1.8, f * cz), 0.95, 0.95, 0.8)
	_col.append(Transform3D(Basis.from_scale(Vector3(1.7, 1.8, 1.7)), Vector3(s * cx, 0.9, f * cz)))


## Mangueiras sanfonadas pretas: da viga por cima até o degrau alto, do degrau alto por fora até o
## baixo, do degrau do meio dando a volta até a máquina de fora e do quadro até a máquina de dentro.
func _mangueiras(s: float, g: float, zf: float) -> void:
	var hx := g + 3.6
	for z: float in [-2.0, 2.0]:
		_mangueira([Vector3(s * (hx - 2.0), Y_TOPO + 0.2, z), Vector3(s * (hx - 0.6), Y_TOPO + 2.6, z), Vector3(s * (hx + 1.6), Y_TOPO + 3.4, z),
			Vector3(s * (g + 7.2), Y_TOPO + 1.8, z), Vector3(s * (g + 7.6), 21.6, z), Vector3(s * (g + 7.2), 20.2, z)], 0.5)
	for f: float in [-1.0, 1.0]:
		var z1 := f * (zf + 0.45)
		_mangueira([Vector3(s * (g + 9.4), 17.6, z1), Vector3(s * (g + 11.6), 18.0, z1), Vector3(s * (g + 13.9), 16.2, z1),
			Vector3(s * (g + 14.6), 12.5, z1), Vector3(s * (g + 14.4), 9.0, z1), Vector3(s * (g + 14.0), 7.0, f * (zf - 1.0))], 0.6)
		var z2 := f * (zf - 2.0)
		_mangueira([Vector3(s * (g + 13.3), 10.8, z2), Vector3(s * (g + 16.2), 11.0, z2), Vector3(s * (g + 18.3), 8.6, z2),
			Vector3(s * (g + 18.5), 5.0, z2), Vector3(s * (g + 17.9), 2.6, f * (zf - 1.2)), Vector3(s * (g + 16.7), 1.9, f * (zf - 0.2))], 0.6)
		var z3 := f * (zf + 1.6)
		_mangueira([Vector3(s * (g + 8.4), 8.4, z3), Vector3(s * (g + 9.9), 8.6, z3), Vector3(s * (g + 10.9), 7.0, z3),
			Vector3(s * (g + 10.9), 4.4, z3)], 0.42)


## Viga alta: barra de baixo com as duas faixas de luz, caixa de aço com a moldura da tela, suportes
## laterais com grampos amarelos, aba de cima; neve grossa, motores e canos por cima; pingentes embaixo.
func _viga_alta(g: float, zf: float) -> void:
	var hx := g + 3.6
	var hz := zf + 1.4
	var meia := g - 0.75
	_caixa(_aco, Vector3(0.0, Y_VIGA + 0.8, 0.0), Vector3(hx * 2.0, 1.6, hz * 2.0), ACO)
	_caixa(_aco, Vector3(0.0, (Y_VIGA + 1.6 + Y_TOPO) * 0.5, 0.0), Vector3(hx * 2.0 - 0.6, Y_TOPO - Y_VIGA - 1.6, hz * 2.0 - 0.5), ACO)
	_caixa(_aco, Vector3(0.0, Y_TOPO - 0.3, 0.0), Vector3(hx * 2.0 + 0.3, 0.6, hz * 2.0 + 0.3), ACO)
	var tt := _tela_tam(meia)
	var ty := _tela_y()
	for f: float in [-1.0, 1.0]:
		var zface := f * (hz - 0.25)
		for sx: float in [-1.0, 1.0]:
			# Faixas de luz da barra de baixo, em moldura
			_caixa(_aco, Vector3(sx * 2.5, Y_VIGA + 0.85, f * (hz + 0.03)), Vector3(3.6, 0.85, 0.12), ACO_CLARO)
			_caixa(_luz_viga, Vector3(sx * 2.5, Y_VIGA + 0.85, f * (hz + 0.1)), Vector3(3.0, 0.38, 0.1), Color.WHITE)
			# Moldura da tela (laterais) e suportes grossos com grampos
			_caixa(_aco, Vector3(sx * (tt.x * 0.5 + 0.2), ty, zface + f * 0.2), Vector3(0.4, tt.y + 0.8, 0.5), ACO)
			var xs := g + 1.5
			_caixa(_aco, Vector3(sx * xs, (Y_VIGA + Y_TOPO) * 0.5, f * (hz + 0.05)), Vector3(1.7, Y_TOPO - Y_VIGA + 0.3, 0.6), ACO)
			_caixa(_aco, Vector3(sx * xs, Y_VIGA + 1.2, f * (hz + 0.2)), Vector3(2.1, 1.1, 0.6), AMARELO)
			_caixa(_aco, Vector3(sx * xs, Y_TOPO - 1.3, f * (hz + 0.2)), Vector3(2.1, 0.9, 0.6), ACO_CLARO)
			_barra(_aco, Vector3(sx * (xs - 0.6), Y_VIGA + 2.0, f * (hz + 0.3)), Vector3(sx * (xs + 0.6), Y_TOPO - 2.0, f * (hz + 0.3)), 0.3, 0.16, Vector3.BACK, ACO)
			# Chapas de canto da tela, com parafusão
			for sy: float in [-1.0, 1.0]:
				var canto := Vector3(sx * (tt.x * 0.5 - 0.1), ty + sy * (tt.y * 0.5 + 0.1), zface + f * 0.3)
				_caixa(_aco, canto, Vector3(0.9, 0.6, 0.3), ACO_CLARO)
				_cilindro(_aco, canto + Vector3(0.0, 0.0, f * 0.1), canto + Vector3(0.0, 0.0, f * 0.26), 0.16, 8, ACO_CLARO)
		_caixa(_aco, Vector3(0.0, ty + tt.y * 0.5 + 0.2, zface + f * 0.2), Vector3(tt.x + 0.8, 0.4, 0.5), ACO)
		_caixa(_aco, Vector3(0.0, ty - tt.y * 0.5 - 0.2, zface + f * 0.2), Vector3(tt.x + 0.8, 0.4, 0.5), ACO)
		# Pingentes embaixo da viga
		var x := -hx + 0.2
		while x < hx - 0.2:
			x += _rng.randf_range(0.22, 0.5)
			var l := _rng.randf_range(0.35, 1.3) if _rng.randf() < 0.72 else _rng.randf_range(1.5, 2.6)
			_geo.call("_pingente", Vector3(x, Y_VIGA + 0.05, f * (hz + _rng.randf_range(-0.05, 0.25))), l, 0.07 + l * 0.04)
	# Neve grossa, motores e cano por cima
	_geo.call("_faixa_neve", -hx + 0.3, hx - 0.3, Y_TOPO - 0.05, hz + 0.5, 1.25)
	for sx: float in [-1.0, 1.0]:
		_cilindro(_aco, Vector3(sx * 3.6, Y_TOPO + 1.0, -1.9), Vector3(sx * 3.6, Y_TOPO + 1.0, 1.9), 1.0, 14, ACO)
		for z: float in [-2.0, 2.0]:
			_cilindro(_aco, Vector3(sx * 3.6, Y_TOPO + 1.0, z - 0.2), Vector3(sx * 3.6, Y_TOPO + 1.0, z + 0.2), 1.2, 14, ACO_CLARO)
		_caixa(_aco, Vector3(sx * 3.6, Y_TOPO + 0.7, 0.0), Vector3(1.4, 1.4, 5.2), ACO)
		_cilindro(_aco, Vector3(sx * 3.6, Y_TOPO + 1.6, 0.0), Vector3(sx * 3.6, Y_TOPO + 2.5, 0.0), 0.34, 10, ACO_CLARO)
	_cilindro(_aco, Vector3(-3.6, Y_TOPO + 2.2, 0.0), Vector3(3.6, Y_TOPO + 2.2, 0.0), 0.26, 10, ACO_CLARO)
	_col.append(Transform3D(Basis.from_scale(Vector3(hx * 2.0, Y_TOPO - Y_VIGA + 2.4, hz * 2.0)), Vector3(0.0, (Y_VIGA + Y_TOPO + 2.4) * 0.5, 0.0)))


## Base (pedido do dono, 2026-10-04, com desenho: "pedaços de gelo, não esses tijolos"): maciço de gelo de
## gotejamento do chão até a estrada — três colunas gordas embaixo da máquina, que chegam até a laje, e
## picos mais baixos em volta, abrindo para baixo como uma montanha; montes de neve no pé. Os picos vão
## para _picos_base (Gelo.macico monta, em _montar).
func _base(g: float, zf: float, fundo: float) -> void:
	var hx0 := g + 19.6
	var hz0 := zf + 5.0
	var alt := Y_BASE - fundo
	# Colar de gelo embaixo da laje: os picos se fundem nele
	_caixa(_gelo_base, Vector3(0.0, Y_BASE - 2.0, 0.0), Vector3(hx0 * 2.0, 4.0, hz0 * 2.0), Color.WHITE, 0.9)
	_col_base.append(Transform3D(Basis.from_scale(Vector3(hx0 * 2.0, 4.0, hz0 * 2.0)), Vector3(0.0, Y_BASE - 2.0, 0.0)))
	var pe := fundo - 2.0
	for fx: float in [-0.62, 0.0, 0.62]:
		_picos_base.append([Vector3(fx * hx0, pe, _rng.randf_range(-1.0, 1.0)), Y_BASE - 1.0 - pe, hz0 * 1.7, 3.0, []])
	for k in 18:
		var ang := TAU * (k + _rng.randf_range(-0.3, 0.3)) / 18.0
		var fr := _rng.randf_range(0.15, 0.85)
		var h := minf(alt * fr, alt - 3.0)
		if h < 4.0:
			continue
		var r := clampf(alt * 0.11, 5.0, 24.0) * _rng.randf_range(0.7, 1.1)
		var longe := 1.0 + (1.0 - fr) * clampf(alt / 90.0, 0.0, 1.6)   # os baixos mais para fora: a base abre como montanha
		_picos_base.append([Vector3(cos(ang) * (hx0 + 4.0) * longe, pe, sin(ang) * (hz0 + 7.0) * longe * 1.5), h + 2.0, r, 0.3, []])
	var neve: SurfaceTool = _geo.get("_st_neve")
	for k in 26:
		var t := _rng.randf() * TAU
		var p := Vector3(cos(t) * (hx0 + 14.0), fundo - 0.6, sin(t) * (hz0 + 18.0))
		var r := _rng.randf_range(2.2, 4.4)
		_geo.call("_prisma", neve, p, Vector3.UP, 14, [Vector2(0.0, r), Vector2(r * 0.22, r * 0.8), Vector2(r * 0.4, r * 0.45)], r * 0.08, 0.1,
			Vector2(1.0, _rng.randf_range(0.6, 0.9)), true, true)


# ------------------------------------------------------------------ bloco que desce

func _bloco(corpo: Node3D, largura: float, comp: float, semente: int) -> Dictionary:
	_comecar(semente)
	var zf := comp * 0.5
	var hl := largura * 0.5
	_parede_gelo(Vector3(-hl, 1.0, -zf), Vector3(hl, ALTO, zf), 2.3, 1.2, true)
	# Sapata com a faixa de advertência, chapa de cima e patins dos trilhos
	_caixa(_listras, Vector3(0.0, 0.5, 0.0), Vector3(largura + 0.3, 1.0, comp + 0.3), Color.WHITE)
	_caixa(_aco, Vector3(0.0, 1.08, 0.0), Vector3(largura + 0.36, 0.2, comp + 0.36), ACO)
	_caixa(_aco, Vector3(0.0, ALTO + 0.05, 0.0), Vector3(largura + 0.2, 0.3, comp + 0.2), ACO)
	for s: float in [-1.0, 1.0]:
		for fz: float in [-0.35, 0.35]:
			_caixa(_aco, Vector3(s * hl, ALTO * 0.5 + 0.5, fz * comp), Vector3(0.3, ALTO - 1.2, 0.9), ACO_CLARO)
		for f: float in [-1.0, 1.0]:
			_caixa(_aco, Vector3(s * (hl - 0.2), ALTO * 0.5 + 0.5, f * (zf + 0.02)), Vector3(0.5, ALTO - 1.0, 0.2), ACO)
			_cilindro(_aco, Vector3(s * hl * 0.6, ALTO + 0.2, f * zf * 0.5), Vector3(s * hl * 0.6, ALTO + 0.5, f * zf * 0.5), 0.5, 12, ACO_CLARO)
	# Faróis vermelhos em aro de aço
	var lampadas: Array = []
	var lente := SphereMesh.new()
	lente.radius = 0.74
	lente.height = 1.48
	lente.radial_segments = 24
	lente.rings = 12
	var luzes: Array = []
	for f: float in [-1.0, 1.0]:
		for s: float in [-1.0, 1.0]:
			var c := Vector3(s * largura * 0.27, 3.3, f * zf)
			_caixa(_aco, c + Vector3(0.0, 0.0, f * 0.04), Vector3(2.4, 2.4, 0.16), ACO)
			_cilindro(_aco, c, c + Vector3(0.0, 0.0, f * 0.36), 1.05, 20, ACO)
			_cilindro(_aco, c + Vector3(0.0, 0.0, f * 0.3), c + Vector3(0.0, 0.0, f * 0.42), 0.9, 20, ACO_CLARO)
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.35, 0.02, 0.01)
			m.roughness = 0.15
			m.emission_enabled = true
			m.emission = Color(1.0, 0.07, 0.03)
			m.emission_energy_multiplier = 3.0
			var mi := MeshInstance3D.new()
			mi.mesh = lente
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.transform = Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.42)), c + Vector3(0.0, 0.0, f * 0.4))
			corpo.add_child(mi)
			lampadas.append(m)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.12, 0.05)
		l.light_energy = 1.5
		l.omni_range = 13.0
		l.shadow_enabled = false
		l.position = Vector3(0.0, 3.0, f * (zf + 2.2))
		corpo.add_child(l)
		luzes.append(l)
		# Pingentes curtos na beira da sapata
		var x := -hl
		while x < hl:
			x += _rng.randf_range(0.4, 1.0)
			_geo.call("_pingente", Vector3(x, 1.0, f * (zf + 0.2)), _rng.randf_range(0.2, 0.55), 0.06)
	_fechar(corpo)
	return {"lampadas": lampadas, "luzes": luzes}


# ------------------------------------------------------------------ efeitos

## Nuvem de neve e lascas de gelo quando o bloco bate no asfalto.
func _estouro(pai: Node3D, meia: float, comp: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 110
	p.lifetime = 1.2
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(meia + 0.5, 0.2, comp * 0.5 + 0.4)
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 8.0
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.scale_min = 0.8
	pm.scale_max = 2.4
	p.process_material = pm
	p.draw_pass_1 = _floco(0.9, 0.7)
	p.position = Vector3(0.0, 0.4, 0.0)
	pai.add_child(p)
	return p


## Vapor saindo dos motores de cima.
func _vapor(pos: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 2.6
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.4
	pm.gravity = Vector3(0.6, 0.5, 0.0)
	pm.scale_min = 0.8
	pm.scale_max = 2.2
	p.process_material = pm
	p.draw_pass_1 = _floco(1.4, 0.28)
	p.position = pos
	return p


func _floco(tam: float, alfa: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(tam, tam)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = Gelo._textura_floco()
	m.albedo_color = Color(0.93, 0.97, 1.0, alfa)
	q.material = m
	return q


# ------------------------------------------------------------------ geometria

func _v(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, uv2: Vector2, cor: Color) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.set_uv2(uv2)
	st.set_color(cor)
	st.add_vertex(p)


## Face plana de 3 ou 4 pontos (em volta), virada para `fora` (Godot: frente em sentido horário).
func _face(st: SurfaceTool, p: Array, uv: Array, uv2: Vector2, cor: Color, fora: Vector3) -> void:
	var p0: Vector3 = p[0]
	var p1: Vector3 = p[1]
	var pu: Vector3 = p[p.size() - 1]
	var n := (p1 - p0).cross(pu - p0)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var ordem: Array
	if n.dot(fora) < 0.0:
		n = -n
		ordem = [0, 1, 2] if p.size() == 3 else [0, 1, 2, 0, 2, 3]
	else:
		ordem = [0, 2, 1] if p.size() == 3 else [0, 2, 1, 0, 3, 2]
	for k: int in ordem:
		_v(st, p[k], n, uv[k], uv2, cor)


## Triângulo de normais lisas (cilindros e mangueiras), virado para o lado das normais.
func _tri_liso(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, va: float, vb: float, vc: float, uv2: Vector2, cor: Color) -> void:
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		_v(st, a, na, Vector2(0.5, va), uv2, cor)
		_v(st, c, nc, Vector2(0.5, vc), uv2, cor)
		_v(st, b, nb, Vector2(0.5, vb), uv2, cor)
	else:
		_v(st, a, na, Vector2(0.5, va), uv2, cor)
		_v(st, b, nb, Vector2(0.5, vb), uv2, cor)
		_v(st, c, nc, Vector2(0.5, vc), uv2, cor)


## Caixa de centro `c` e tamanho `t`, com as arestas chanfradas em `ch` m (0 = quina viva) e girada por
## `giro`. Cada face leva UV 0..1 e o tamanho em metros (UV2); os chanfros contam como aresta.
func _caixa(st: SurfaceTool, c: Vector3, t: Vector3, cor: Color, ch := 0.0, giro := Basis.IDENTITY) -> void:
	var h := t * 0.5
	ch = minf(ch, minf(h.x, minf(h.y, h.z)) * 0.45)
	for a in 3:
		var u := (a + 1) % 3
		var w := (a + 2) % 3
		for s: float in [-1.0, 1.0]:
			var pts := []
			for par: Vector2 in UVS:
				var p := Vector3.ZERO
				p[a] = s * h[a]
				p[u] = (par.x * 2.0 - 1.0) * (h[u] - ch)
				p[w] = (par.y * 2.0 - 1.0) * (h[w] - ch)
				pts.append(c + giro * p)
			var n := Vector3.ZERO
			n[a] = s
			_face(st, pts, UVS, Vector2(h[u] - ch, h[w] - ch) * 2.0, cor, giro * n)
	if ch <= 0.0:
		return
	var uv0 := [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var fino := Vector2(0.01, 0.01)
	# Chanfro das 12 arestas (aresta ao longo de `a`, entre as faces `u` e `w`)
	for a in 3:
		var u := (a + 1) % 3
		var w := (a + 2) % 3
		for su: float in [-1.0, 1.0]:
			for sw: float in [-1.0, 1.0]:
				var pts := []
				for item: Array in [[true, -1.0], [true, 1.0], [false, 1.0], [false, -1.0]]:
					var p := Vector3.ZERO
					p[a] = float(item[1]) * (h[a] - ch)
					p[u] = su * (h[u] - (0.0 if item[0] else ch))
					p[w] = sw * (h[w] - (ch if item[0] else 0.0))
					pts.append(c + giro * p)
				var n := Vector3.ZERO
				n[u] = su
				n[w] = sw
				_face(st, pts, uv0, fino, cor, giro * n)
	# Os 8 cantos
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var sg := Vector3(sx, sy, sz)
				var pts := []
				for a in 3:
					var p := Vector3(sg.x * (h.x - ch), sg.y * (h.y - ch), sg.z * (h.z - ch))
					p[a] = sg[a] * h[a]
					pts.append(c + giro * p)
				_face(st, pts, uv0, fino, cor, giro * sg)


## Barra chata de `a` até `b`: `larg` no plano, `esp` na direção `fino`.
func _barra(st: SurfaceTool, a: Vector3, b: Vector3, larg: float, esp: float, fino: Vector3, cor: Color) -> void:
	var zb := (b - a).normalized()
	var xb := fino.cross(zb).normalized()
	var yb := zb.cross(xb)
	_caixa(st, (a + b) * 0.5, Vector3(larg, esp, (b - a).length()), cor, 0.0, Basis(xb, yb, zb))


## Cilindro de `a` até `b` com tampas, normais lisas.
func _cilindro(st: SurfaceTool, a: Vector3, b: Vector3, r: float, lados: int, cor: Color) -> void:
	var eixo := (b - a).normalized()
	var e1 := (Vector3.UP if absf(eixo.y) < 0.9 else Vector3.RIGHT).cross(eixo).normalized()
	var e2 := eixo.cross(e1)
	var uv2 := Vector2(100.0, (b - a).length())
	var tampa := Vector2(100.0, 100.0)
	for k in lados:
		var t0 := TAU * float(k) / lados
		var t1 := TAU * float(k + 1) / lados
		var n0 := e1 * cos(t0) + e2 * sin(t0)
		var n1 := e1 * cos(t1) + e2 * sin(t1)
		_tri_liso(st, a + n0 * r, a + n1 * r, b + n1 * r, n0, n1, n1, 0.0, 0.0, 1.0, uv2, cor)
		_tri_liso(st, a + n0 * r, b + n1 * r, b + n0 * r, n0, n1, n0, 0.0, 1.0, 1.0, uv2, cor)
		_tri_liso(st, a + n0 * r, a + n1 * r, a, -eixo, -eixo, -eixo, 0.5, 0.5, 0.5, tampa, cor)
		_tri_liso(st, b + n0 * r, b + n1 * r, b, eixo, eixo, eixo, 0.5, 0.5, 0.5, tampa, cor)


## Muralha de blocos de gelo ocupando a caixa de `a` a `b`: cada bloco é uma caixa chanfrada (só os da
## casca; com `tampas`, também os de cima e de baixo), um pouco fora de prumo, com um miolo aceso atrás
## — a luz sai pelas frestas.
func _parede_gelo(a: Vector3, b: Vector3, bloco: float, brilho := 1.0, tampas := true) -> void:
	var t := b - a
	var nx := maxi(roundi(t.x / bloco), 1)
	var ny := maxi(roundi(t.y / bloco), 1)
	var nz := maxi(roundi(t.z / bloco), 1)
	var cel := Vector3(t.x / nx, t.y / ny, t.z / nz)
	var ch := minf(cel.x, minf(cel.y, cel.z)) * 0.07
	for j in ny:
		for i in nx:
			for k in nz:
				var dentro_xz := i > 0 and i < nx - 1 and k > 0 and k < nz - 1
				if dentro_xz and (not tampas or (j > 0 and j < ny - 1)):
					continue
				var c := a + Vector3((i + 0.5) * cel.x, (j + 0.5) * cel.y, (k + 0.5) * cel.z)
				var fora := Vector3.ZERO
				if nx > 1:
					fora.x = -1.0 if i == 0 else (1.0 if i == nx - 1 else 0.0)
				if nz > 1:
					fora.z = -1.0 if k == 0 else (1.0 if k == nz - 1 else 0.0)
				c += fora * _rng.randf_range(-0.05, 0.14)
				_caixa(_gelo, c, cel - Vector3.ONE * 0.07, Color(_rng.randf(), brilho, 0.0), ch)
	var miolo := Vector3(maxf(t.x - 0.6, 0.1), maxf(t.y - 0.3, 0.1), maxf(t.z - 0.6, 0.1))
	_caixa(_nucleo, (a + b) * 0.5, miolo, Color.WHITE)


## Muralha de gelo do lado `s` (espelha em x).
func _gelo_s(s: float, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, bloco: float, brilho := 1.0) -> void:
	_parede_gelo(Vector3(minf(s * x0, s * x1), y0, z0), Vector3(maxf(s * x0, s * x1), y1, z1), bloco, brilho)


## Respiro de luz: caixilho de aço com três barras ciano acesas, na face `f` (±z).
func _respiro(c: Vector3, f: float, larg: float, alt: float) -> void:
	_caixa(_aco, c, Vector3(larg + 0.4, alt + 0.4, 0.24), ACO)
	_caixa(_aco, c + Vector3(0.0, 0.0, f * 0.1), Vector3(larg + 0.1, alt + 0.1, 0.1), Color(0.05, 0.055, 0.06))
	for k in 3:
		_caixa(_luz, c + Vector3(0.0, (k - 1) * alt * 0.32, f * 0.16), Vector3(larg * 0.82, alt * 0.17, 0.08), Color.WHITE)


## Mangueira sanfonada pelos pontos (curva suave), com abraçadeiras de aço e flanges nas pontas.
func _mangueira(pts: Array, r: float) -> void:
	var caminho := PackedVector3Array()
	for i in pts.size() - 1:
		var p0: Vector3 = pts[maxi(i - 1, 0)]
		var p1: Vector3 = pts[i]
		var p2: Vector3 = pts[i + 1]
		var p3: Vector3 = pts[mini(i + 2, pts.size() - 1)]
		var passos := maxi(int(p1.distance_to(p2) / 0.17), 2)
		for k in passos:
			caminho.append(p1.cubic_interpolate(p2, p0, p3, float(k) / passos))
	caminho.append(pts[pts.size() - 1])
	var lados := 10
	var tg := (caminho[1] - caminho[0]).normalized()
	var u := (Vector3.UP if absf(tg.y) < 0.9 else Vector3.RIGHT).cross(tg).normalized()
	var anel_ant := PackedVector3Array()
	var norm_ant := PackedVector3Array()
	var uv2 := Vector2(100.0, 100.0)
	var cor := Color.WHITE
	var andado := 0.0
	var prox_abracadeira := 1.4
	for i in caminho.size():
		var p := caminho[i]
		if i < caminho.size() - 1:
			tg = (caminho[i + 1] - p).normalized()
		u = (u - tg * u.dot(tg)).normalized()
		var w := tg.cross(u)
		var rr := r * (1.0 if i % 2 == 0 else 0.84)
		var anel := PackedVector3Array()
		var norm := PackedVector3Array()
		for k in lados:
			var t := TAU * float(k) / lados
			var n := u * cos(t) + w * sin(t)
			anel.append(p + n * rr)
			norm.append(n)
		if i > 0:
			for k in lados:
				var k2 := (k + 1) % lados
				_tri_liso(_borracha, anel_ant[k], anel_ant[k2], anel[k2], norm_ant[k], norm_ant[k2], norm[k2], 0.5, 0.5, 0.5, uv2, cor)
				_tri_liso(_borracha, anel_ant[k], anel[k2], anel[k], norm_ant[k], norm[k2], norm[k], 0.5, 0.5, 0.5, uv2, cor)
			andado += p.distance_to(caminho[i - 1])
		anel_ant = anel
		norm_ant = norm
		if andado >= prox_abracadeira and i < caminho.size() - 6:
			prox_abracadeira = andado + 2.9
			_cilindro(_aco, p - tg * 0.3, p + tg * 0.3, r * 1.16, 12, ACO_CLARO)
			_cilindro(_aco, p - tg * 0.09, p + tg * 0.09, r * 1.24, 12, AMARELO)
	for ponta: int in [0, caminho.size() - 1]:
		var p := caminho[ponta]
		var d := (caminho[1] - caminho[0]).normalized() if ponta == 0 else (caminho[ponta] - caminho[ponta - 1]).normalized()
		_cilindro(_aco, p - d * 0.35, p + d * 0.35, r * 1.3, 12, ACO)
