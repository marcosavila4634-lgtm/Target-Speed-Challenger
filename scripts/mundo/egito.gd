class_name Egito
extends Node3D
## Pharaoh's Climb (mapa.subida.egito): cenário do Egito em volta do percurso do Climb.
## - Grande Pirâmide em degraus de verdade (a estrada sobe em espiral por fora dela e o Templo de Rá
##   fica no topo achatado), pirâmides das rainhas lisas com a ponta dourada;
## - Nilo: leito cavado no terreno (cavar_nilo), faixa verde de plantações (textura_margem), palmeiras,
##   papiros e barcos à vela (feluccas) descendo o rio;
## - obeliscos de granito com hieróglifos (fixos e os de cada etapa), avenida de estátuas de Anúbis,
##   templos (modelo CC-BY) e, por etapa, o Portal de Anúbis e a tempestade de areia com vento.
## Tudo que é pedra é mortal: entra em altura() (somada em Terreno.altura_em, como os prédios do City
## Rush) e tem colisão no grupo "mortal".

const TEMPLOS := "res://assets/egito/templos/templos.glb"
const PROPS := "res://assets/egito/props/props.glb"

var penhasco := 200.0             # altura dos penhascos de calcário em volta do vale
var _terreno: Terreno
var _cfg: Dictionary = {}
var _chao := 6.5
# Grande Pirâmide (tronco de pirâmide em degraus)
var _pir_c := Vector2(-1300, -250)
var _pir_mb := 150.0
var _pir_mt := 72.0
var _pir_topo := 97.0
var _pir_degrau := 1.8
# Pirâmides menores: [centro, meia-base, altura]
var _menores: Array = []
# Obeliscos: [centro, base, altura total, pé (altura do chão)] — fixos e da etapa
var _obeliscos_fixos: Array = []
var _obeliscos_etapa: Array = []
# Nilo
var _nilo := PackedVector2Array()
var _nilo_meia := 36.0
var _nilo_verde := 170.0
var _nilo_s := PackedFloat32Array()   # comprimento acumulado (para os barcos descerem o rio)
# Etapa
var _etapa_no: Node3D
var _feluccas: Array = []             # [nó, s no rio, velocidade, fase]
var _mat_pedra: ShaderMaterial
var _mat_obelisco: ShaderMaterial
var _malha_obelisco: ArrayMesh
var _tempestade: Node3D
var _vento_cfg: Dictionary = {}
var _t := 0.0
var _env_original := {}


## Lê a configuração antes do terreno ser amostrado (o leito do Nilo entra na malha do chão).
func preparar(terreno: Terreno) -> void:
	_terreno = terreno
	_cfg = Config.valor("mapa.subida.egito", {})
	penhasco = float(_cfg.get("penhasco", 200.0))
	var p: Dictionary = _cfg.get("piramide", {})
	var c: Array = p.get("centro", [-1300, -250])
	_pir_c = Vector2(float(c[0]), float(c[1]))
	_pir_mb = float(p.get("meia_base", 150))
	_pir_mt = float(p.get("meia_topo", 72))
	_pir_topo = float(p.get("topo", 97))
	_pir_degrau = float(p.get("degrau", 1.8))
	for m in _cfg.get("piramides_menores", []):
		_menores.append([Vector2(float(m[0]), float(m[1])), float(m[2]), float(m[3])])
	for o in _cfg.get("obeliscos_fixos", []):
		_obeliscos_fixos.append(_obelisco_dados(o))
	# Obeliscos dourados nos quatro cantos do topo da Grande Pirâmide
	var canto := _pir_mt - 7.0
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_obeliscos_fixos.append([_pir_c + s * canto, 2.4, 22.0, _pir_topo])
	var nilo: Dictionary = _cfg.get("nilo", {})
	for q in nilo.get("pontos", []):
		_nilo.append(Vector2(float(q[0]), float(q[1])))
	_nilo_meia = float(nilo.get("meia_largura", 36))
	_nilo_verde = float(nilo.get("faixa_verde", 170))
	_nilo_s.resize(_nilo.size())
	for i in range(1, _nilo.size()):
		_nilo_s[i] = _nilo_s[i - 1] + _nilo[i].distance_to(_nilo[i - 1])


func _obelisco_dados(o: Array, pe := NAN) -> Array:
	var centro := Vector2(float(o[0]), float(o[1]))
	return [centro, float(o[3]), float(o[2]), pe]


# ------------------------------------------------------------------ alturas (mortais)

## Altura das construções de pedra em (x, z): pirâmides e obeliscos. -INF fora delas.
func altura(x: float, z: float) -> float:
	var h := -INF
	var c := maxf(absf(x - _pir_c.x), absf(z - _pir_c.y))
	if c < _pir_mb:
		h = _pir_topo if c <= _pir_mt else _chao + (_pir_topo - _chao) * (_pir_mb - c) / (_pir_mb - _pir_mt)
	for m: Array in _menores:
		var cm := maxf(absf(x - m[0].x), absf(z - m[0].y))
		if cm < m[1]:
			h = maxf(h, _chao + m[2] * (1.0 - cm / m[1]))
	for lista: Array in [_obeliscos_fixos, _obeliscos_etapa]:
		for o: Array in lista:
			var co := maxf(absf(x - o[0].x), absf(z - o[0].y))
			if co < o[1] * 0.75:
				h = maxf(h, _altura_obelisco(o, co))
	return h


## Superfície do obelisco à distância (de Chebyshev) `c` do eixo: pedestal, fuste afunilando
## (meia-largura 0,5 → 0,33 da base) e a ponta.
func _altura_obelisco(o: Array, c: float) -> float:
	var b: float = o[1]
	var pe := _pe_obelisco(o)
	var pedestal := b * 0.35
	var h := pe + pedestal
	var alto: float = o[2]
	if c <= b * 0.33:
		h += alto * (1.0 - 0.06 * c / (b * 0.33))
	elif c <= b * 0.5:
		h += alto * 0.94 * (b * 0.5 - c) / (b * 0.17)
	return h


func _pe_obelisco(o: Array) -> float:
	return _chao if is_nan(o[3]) else float(o[3])


# ------------------------------------------------------------------ Nilo

## Distância do ponto ao eixo do Nilo e o índice do trecho mais perto.
func _dist_nilo(p: Vector2) -> Vector2:
	var melhor := INF
	var seg := 0.0
	for i in range(1, _nilo.size()):
		var a := _nilo[i - 1]
		var ab := _nilo[i] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < melhor:
			melhor = d
			seg = i - 1 + t
	return Vector2(melhor, seg)


## Leito do Nilo: fundo a -7 m no meio, margens subindo até o vale (corta penhascos e dunas).
func cavar_nilo(x: float, z: float, h: float) -> float:
	if _nilo.size() < 2:
		return h
	var d := _dist_nilo(Vector2(x, z)).x
	if d > _nilo_meia + 140.0:
		return h
	h = minf(h, lerpf(-7.0, h, smoothstep(_nilo_meia * 0.35, _nilo_meia + 4.0, d)))
	# Barranco: as margens sobem devagar (planície de cheia) e cortam o que for mais alto
	h = minf(h, lerpf(5.2, h, smoothstep(_nilo_meia + 2.0, _nilo_meia + 140.0, d)))
	return h


## Máscara da faixa verde (R: 1 na água, cai a 0 a `faixa_verde` m da margem) para o shader do chão.
func textura_margem(meio: float) -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_R8)
	var passo := meio * 2.0 / n
	for iz in n:
		for ix in n:
			var p := Vector2(-meio + (ix + 0.5) * passo, -meio + (iz + 0.5) * passo)
			var d := _dist_nilo(p).x
			var v := clampf(1.0 - (d - _nilo_meia) / _nilo_verde, 0.0, 1.0)
			# Borda da plantação irregular (lotes avançam mais em uns trechos)
			v *= 0.85 + 0.15 * sin(p.x * 0.013 + p.y * 0.021)
			img.set_pixel(ix, iz, Color(v, 0.0, 0.0))
	return ImageTexture.create_from_image(img)


## Ponto e direção do rio a `s` metros do começo.
func _no_rio(s: float) -> Array:
	var i := 1
	while i < _nilo.size() - 1 and _nilo_s[i] < s:
		i += 1
	var a := _nilo[i - 1]
	var b := _nilo[i]
	var t := clampf((s - _nilo_s[i - 1]) / maxf(_nilo_s[i] - _nilo_s[i - 1], 0.01), 0.0, 1.0)
	return [a.lerp(b, t), (b - a).normalized()]


# ------------------------------------------------------------------ montagem

func montar() -> void:
	_mat_pedra = _material_pedra(0)
	_montar_grande_piramide()
	_montar_piramides_menores()
	_mat_obelisco = ShaderMaterial.new()
	_mat_obelisco.shader = load("res://shaders/obelisco.gdshader")
	_mat_obelisco.set_shader_parameter("ruido", Terreno._textura_ruido(0.06, 4, 97))
	_malha_obelisco = _criar_malha_obelisco()
	var fixos := Node3D.new()
	fixos.name = "ObeliscosFixos"
	add_child(fixos)
	_montar_obeliscos(fixos, _obeliscos_fixos)
	_montar_estatuas()
	_montar_templos()
	_montar_vegetacao()
	_montar_feluccas()
	_etapa_no = Node3D.new()
	_etapa_no.name = "Etapa"
	add_child(_etapa_no)


func _material_pedra(modo: int, fiada := -1.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pedra_egito.gdshader")
	m.set_shader_parameter("modo", modo)
	m.set_shader_parameter("fiada", _pir_degrau if fiada < 0.0 else fiada)
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 113))
	m.set_shader_parameter("altura_chao", _chao)
	return m


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## Triângulo com a face da frente virada para `n` (o Godot desenha a frente em sentido horário:
## o produto vetorial dos lados aponta para dentro).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var ordem := [a, b, c] if (b - a).cross(c - a).dot(n) <= 0.0 else [a, c, b]
	for v: Vector3 in ordem:
		st.set_normal(n)
		st.add_vertex(v)


## Anel quadrado (meia-largura `m`) de faces verticais de y0 a y1, viradas para fora.
static func _anel_vertical(st: SurfaceTool, c: Vector2, m: float, y0: float, y1: float) -> void:
	var cantos := [Vector2(-m, -m), Vector2(m, -m), Vector2(m, m), Vector2(-m, m)]
	for k in 4:
		var a: Vector2 = c + cantos[k]
		var b: Vector2 = c + cantos[(k + 1) % 4]
		var fora := Vector3((a + b).x * 0.5 - c.x, 0.0, (a + b).y * 0.5 - c.y).normalized()
		_quad(st, Vector3(a.x, y1, a.y), Vector3(b.x, y1, b.y), Vector3(b.x, y0, b.y), Vector3(a.x, y0, a.y), fora)


## Anel horizontal (patamar) entre as meias-larguras m0 (dentro) e m1 (fora), na altura y.
static func _anel_horizontal(st: SurfaceTool, c: Vector2, m0: float, m1: float, y: float) -> void:
	var cantos := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in 4:
		var a0: Vector2 = c + cantos[k] * m0
		var b0: Vector2 = c + cantos[(k + 1) % 4] * m0
		var a1: Vector2 = c + cantos[k] * m1
		var b1: Vector2 = c + cantos[(k + 1) % 4] * m1
		_quad(st, Vector3(a0.x, y, a0.y), Vector3(a1.x, y, a1.y), Vector3(b1.x, y, b1.y), Vector3(b0.x, y, b0.y), Vector3.UP)


## Grande Pirâmide: fiadas de `degrau` m, cada uma recuando para a face ideal passar pelas quinas
## de cima dos degraus (a altura mortal de altura() fica sempre por fora da pedra). Topo achatado
## com friso dourado na borda; colisão por fiada (caixas) no grupo "mortal".
func _montar_grande_piramide() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var meia := func(y: float) -> float:
		return _pir_mb - (_pir_mb - _pir_mt) * clampf((y - _chao) / (_pir_topo - _chao), 0.0, 1.0)
	var y := _chao - 3.0
	var caixas: Array[Transform3D] = []
	var k := 0
	while y < _pir_topo - 0.01:
		var y1 := minf(_chao + (k + 1) * _pir_degrau, _pir_topo)
		var m1: float = meia.call(y1)
		_anel_vertical(st, _pir_c, m1, y, y1)
		var m2: float = meia.call(minf(y1 + _pir_degrau, _pir_topo)) if y1 < _pir_topo else 0.0
		if y1 < _pir_topo - 0.01:
			_anel_horizontal(st, _pir_c, m2, m1, y1)
		caixas.append(Transform3D(Basis.from_scale(Vector3(m1 * 2.0, y1 - y, m1 * 2.0)), Vector3(_pir_c.x, (y + y1) * 0.5, _pir_c.y)))
		y = y1
		k += 1
	# Topo achatado (o templo fica em cima)
	var mt := _pir_mt
	_quad(st, Vector3(_pir_c.x - mt, _pir_topo, _pir_c.y - mt), Vector3(_pir_c.x + mt, _pir_topo, _pir_c.y - mt),
		Vector3(_pir_c.x + mt, _pir_topo, _pir_c.y + mt), Vector3(_pir_c.x - mt, _pir_topo, _pir_c.y + mt), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "GrandePiramide"
	mi.mesh = st.commit()
	mi.material_override = _mat_pedra
	add_child(mi)
	# Friso dourado em volta do topo e faixa de revestimento branco nas fiadas de cima
	var friso: Array[Transform3D] = []
	for s: Vector2 in [Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		var centro := _pir_c + s * (mt - 0.4)
		var tam := Vector3(mt * 2.0, 0.7, 0.8) if s.x == 0.0 else Vector3(0.8, 0.7, mt * 2.0)
		friso.append(Transform3D(Basis.from_scale(tam), Vector3(centro.x, _pir_topo + 0.35, centro.y)))
	ComplexoLancamento.criar_multimesh(self, friso, _material_ouro())
	var corpo := _corpo_mortal()
	ComplexoLancamento.adicionar_colisoes(corpo, caixas)


func _material_ouro(emissao := 0.15) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.74, 0.3)
	m.metallic = 1.0
	m.roughness = 0.25
	m.emission_enabled = emissao > 0.0
	m.emission = Color(1.0, 0.7, 0.3)
	m.emission_energy_multiplier = emissao
	return m


func _corpo_mortal(pai: Node = null) -> StaticBody3D:
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	corpo.add_to_group("mortal")
	(pai if pai else self).add_child(corpo)
	return corpo


## Pirâmides das rainhas: revestimento liso de calcário branco e ponta (piramídio) de ouro.
func _montar_piramides_menores() -> void:
	var mat := _material_pedra(1)
	var ouro := _material_ouro(0.25)
	for m: Array in _menores:
		var c: Vector2 = m[0]
		var mb: float = m[1]
		var alt: float = m[2]
		var topo := Vector3(c.x, _chao + alt, c.y)
		var corte := 0.88   # fração da altura onde começa a ponta dourada
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var st_o := SurfaceTool.new()
		st_o.begin(Mesh.PRIMITIVE_TRIANGLES)
		var cantos := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for k in 4:
			var a: Vector2 = cantos[k]
			var b: Vector2 = cantos[(k + 1) % 4]
			var pa := Vector3(c.x + a.x * mb, _chao - 2.0, c.y + a.y * mb)
			var pb := Vector3(c.x + b.x * mb, _chao - 2.0, c.y + b.y * mb)
			var qa := pa.lerp(topo, corte)
			var qb := pb.lerp(topo, corte)
			var n := (pb - pa).cross(topo - pa).normalized()
			if n.dot(Vector3((a + b).x, 0.0, (a + b).y)) < 0.0:
				n = -n
			_quad(st, qa, qb, pb, pa, n)
			_tri(st_o, qa, topo, qb, n)
		for par: Array in [[st, mat], [st_o, ouro]]:
			var mi := MeshInstance3D.new()
			mi.mesh = (par[0] as SurfaceTool).commit()
			mi.material_override = par[1]
			add_child(mi)
		# Colisão: três caixas em degrau por dentro das faces
		var caixas: Array[Transform3D] = []
		for f in 3:
			var y0 := _chao - 2.0 + alt * f / 3.0
			var y1 := _chao + alt * (f + 1) / 3.0
			var meia := mb * (1.0 - (f + 1) / 3.0) + 0.5
			caixas.append(Transform3D(Basis.from_scale(Vector3(meia * 2.0, y1 - y0, meia * 2.0)), Vector3(c.x, (y0 + y1) * 0.5, c.y)))
		ComplexoLancamento.adicionar_colisoes(_corpo_mortal(), caixas)


## Malha unitária do obelisco: base 1 x 1 em y = 0, afunila até 0,66 em y = 0,94 e a ponta até y = 1.
func _criar_malha_obelisco() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cantos := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var y_p := 0.94
	for k in 4:
		var a: Vector2 = cantos[k]
		var b: Vector2 = cantos[(k + 1) % 4]
		var a0 := Vector3(a.x * 0.5, 0.0, a.y * 0.5)
		var b0 := Vector3(b.x * 0.5, 0.0, b.y * 0.5)
		var a1 := Vector3(a.x * 0.33, y_p, a.y * 0.33)
		var b1 := Vector3(b.x * 0.33, y_p, b.y * 0.33)
		var fora := Vector3((a + b).x, 0.0, (a + b).y).normalized()
		_quad(st, a1, b1, b0, a0, fora)
		var topo := Vector3(0.0, 1.0, 0.0)
		var n := (b1 - a1).cross(topo - a1).normalized()
		if n.dot(fora) < 0.0:
			n = -n
		_tri(st, a1, topo, b1, n)
	return st.commit()


## Obeliscos: fuste de granito (malha unitária escalada), pedestal de arenito em degraus e
## colisão mortal com a forma exata (tronco + ponta).
func _montar_obeliscos(pai: Node3D, lista: Array) -> void:
	var fustes: Array[Transform3D] = []
	var pedestais: Array[Transform3D] = []
	var corpo := _corpo_mortal(pai)
	for o: Array in lista:
		var c: Vector2 = o[0]
		var b: float = o[1]
		var alto: float = o[2]
		var pe := _pe_obelisco(o)
		var y0 := pe + b * 0.35
		fustes.append(Transform3D(Basis.from_scale(Vector3(b, alto, b)), Vector3(c.x, y0, c.y)))
		pedestais.append(Transform3D(Basis.from_scale(Vector3(b * 1.5, b * 0.2 + 2.0, b * 1.5)), Vector3(c.x, pe + b * 0.1 - 1.0, c.y)))
		pedestais.append(Transform3D(Basis.from_scale(Vector3(b * 1.22, b * 0.16, b * 1.22)), Vector3(c.x, pe + b * 0.27, c.y)))
		var pts := PackedVector3Array()
		for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			pts.append(Vector3(c.x + s.x * b * 0.5, y0, c.y + s.y * b * 0.5))
			pts.append(Vector3(c.x + s.x * b * 0.33, y0 + alto * 0.94, c.y + s.y * b * 0.33))
		pts.append(Vector3(c.x, y0 + alto, c.y))
		var forma := ConvexPolygonShape3D.new()
		forma.points = pts
		var cs := CollisionShape3D.new()
		cs.shape = forma
		corpo.add_child(cs)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _malha_obelisco
	mm.instance_count = fustes.size()
	for i in fustes.size():
		mm.set_instance_transform(i, fustes[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _mat_obelisco
	pai.add_child(mmi)
	ComplexoLancamento.criar_multimesh(pai, pedestais, _material_pedra(0, 0.7))
	ComplexoLancamento.adicionar_colisoes(corpo, pedestais)


# ------------------------------------------------------------------ estátuas e templos

## Procura no modelo o primeiro MeshInstance3D cujo nome (ou o do pai) contém `parte`.
static func _malha_do_modelo(caminho: String, parte: String) -> MeshInstance3D:
	if not ResourceLoader.exists(caminho):
		return null
	var cena: Node = (load(caminho) as PackedScene).instantiate()
	for mi: MeshInstance3D in cena.find_children("*", "MeshInstance3D", true, false):
		if str(mi.name).to_lower().contains(parte) or str(mi.get_parent().name).to_lower().contains(parte):
			var copia := mi.duplicate() as MeshInstance3D
			# Transformação acumulada do modelo (Sketchfab gira e escala nos nós de cima)
			var t := Transform3D.IDENTITY
			var no: Node = mi
			while no and no != cena:
				if no is Node3D:
					t = (no as Node3D).transform * t
				no = no.get_parent()
			copia.transform = t
			cena.free()
			return copia
	cena.free()
	return null


## Estátua de Anúbis (chacal deitado, modelo CC-BY) normalizada: base no chão (y = 0), de frente
## para -Z, com `comprimento` m. Devolve um Node3D (ou null se o modelo não estiver importado).
func _estatua_anubis(comprimento: float) -> Node3D:
	var mi := _malha_do_modelo(PROPS, "jackal")
	if mi == null:
		return null
	var caixa := mi.transform * mi.get_aabb()
	var maior := maxf(caixa.size.x, caixa.size.z)
	var esc := comprimento / maxf(maior, 0.001)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[EGITO] estátua %s caixa=%s esc=%.3f" % [mi.name, str(caixa), esc])
	var raiz := Node3D.new()
	var meio := caixa.get_center()
	var ajuste := Transform3D(Basis.from_scale(Vector3.ONE * esc), Vector3(-meio.x * esc, -caixa.position.y * esc, -meio.z * esc))
	if caixa.size.x > caixa.size.z:
		ajuste = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * ajuste
	# A cabeça do chacal fica em +X depois do ajuste: gira para ela apontar para -Z (frente do nó)
	mi.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO) * ajuste * mi.transform
	raiz.add_child(mi)
	return raiz


## Avenida de estátuas de Anúbis ao longo da reta da largada (como as avenidas de esfinges de
## Karnak), em pedestais de arenito, e o colosso de Anúbis guardando a largada.
func _montar_estatuas() -> void:
	var cfg: Dictionary = _cfg.get("esfinges", {})
	var pedestais: Array[Transform3D] = []
	if not cfg.is_empty():
		var x := float(cfg.get("x", 0.0))
		var z := float(cfg.get("z0", 0.0))
		var z1 := float(cfg.get("z1", -200.0))
		var passo := float(cfg.get("passo", 25.0))
		var lado := float(cfg.get("lado", 13.0))
		while z >= z1:
			for s: float in [-1.0, 1.0]:
				var base := Vector3(x + s * lado, _chao, z)
				pedestais.append(Transform3D(Basis.from_scale(Vector3(4.2, 2.4, 7.0)), base + Vector3.UP * 0.6))
				var est := _estatua_anubis(6.2)
				if est:
					est.position = base + Vector3.UP * 1.8
					est.rotation.y = -s * PI * 0.5   # olhando para a estrada
					add_child(est)
			z -= passo
	ComplexoLancamento.criar_multimesh(self, pedestais, _material_pedra(2, 0.8))
	var g: Array = _cfg.get("grande_esfinge", [])
	if g.size() >= 4:
		var colosso := _estatua_anubis(float(g[3]))
		var base := Vector3(float(g[0]), _chao, float(g[1]))
		var largura := float(g[3]) * 0.45
		var ped := Transform3D(Basis(Vector3.UP, deg_to_rad(-float(g[2]))) * Basis.from_scale(Vector3(largura, 6.0, float(g[3]) * 1.08)), base + Vector3.UP * 1.0)
		ComplexoLancamento.criar_multimesh(self, [ped], _material_pedra(2, 1.2))
		if colosso:
			colosso.position = base + Vector3.UP * 4.0
			colosso.rotation.y = -deg_to_rad(float(g[2]))
			add_child(colosso)


## Templos (modelo CC-BY "Egyptian Temples"): assentados no chão, sem colisão (longe do percurso).
func _montar_templos() -> void:
	if not ResourceLoader.exists(TEMPLOS):
		return
	var cena := load(TEMPLOS) as PackedScene
	for t in _cfg.get("templos", []):
		var no := cena.instantiate() as Node3D
		no.scale = Vector3.ONE * float(t[3])
		no.rotation.y = deg_to_rad(float(t[2]))
		no.position = Vector3(float(t[0]), _terreno.altura_em(float(t[0]), float(t[1])) - 0.5, float(t[1]))
		add_child(no)


# ------------------------------------------------------------------ Nilo: vegetação e barcos

## Tamareiras na faixa verde do Nilo e em oásis perto da largada, papiros na beira d'água e
## arbustos secos espalhados pelo deserto do vale.
func _montar_vegetacao() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1)) + 31
	var palmeiras := []
	var papiros := []
	var secos := []
	var vale: Array = Config.valor("mapa.subida.vale", [-1900, -1450, 760, 700])
	var tentativas := 0
	while (palmeiras.size() < 2600 or papiros.size() < 9000) and tentativas < 300000:
		tentativas += 1
		# Sorteia perto do rio: ponto do eixo + afastamento
		var s := rng.randf() * _nilo_s[_nilo_s.size() - 1]
		var r := _no_rio(s)
		var eixo: Vector2 = r[0]
		var d: Vector2 = r[1]
		var lado := 1.0 if rng.randf() < 0.5 else -1.0
		var afast := _nilo_meia + pow(rng.randf(), 1.6) * _nilo_verde
		var p: Vector2 = eixo + Vector2(-d.y, d.x) * lado * afast
		if absf(p.x) > Terreno.MEIO_INTERNO - 100.0 or absf(p.y) > Terreno.MEIO_INTERNO - 100.0:
			continue
		var h := _terreno.altura_em(p.x, p.y)
		if h < 4.6 or h > 18.0 or _perto_do_percurso(p, h):
			continue
		var dr := _dist_nilo(p).x
		if dr < _nilo_meia + 9.0:
			if papiros.size() < 9000:
				papiros.append([Vector3(p.x, h - 0.1, p.y), rng.randf_range(2.2, 3.6), rng.randf() * TAU, Color(0.55, 1.2, 0.45) * rng.randf_range(0.8, 1.1)])
		elif palmeiras.size() < 2600 and rng.randf() < 0.6:
			palmeiras.append([Vector3(p.x, h - 0.3, p.y), rng.randf_range(0.8, 1.25), rng.randf() * TAU, Color(1, 1, 1) * rng.randf_range(0.8, 1.1)])
	# Oásis de palmeiras em volta da largada e da Grande Pirâmide
	for i in 260:
		var ang := rng.randf() * TAU
		var raio := rng.randf_range(_pir_mb + 60.0, _pir_mb + 380.0)
		var p := _pir_c + Vector2(cos(ang), sin(ang)) * raio
		var h := _terreno.altura_em(p.x, p.y)
		if h > 12.0 or h < 4.6 or _perto_do_percurso(p, h):
			continue
		palmeiras.append([Vector3(p.x, h - 0.3, p.y), rng.randf_range(0.8, 1.2), rng.randf() * TAU, Color(1, 1, 1) * rng.randf_range(0.85, 1.1)])
	# Arbustos secos e capim do deserto espalhados no vale
	tentativas = 0
	while secos.size() < 7000 and tentativas < 60000:
		tentativas += 1
		var x := rng.randf_range(float(vale[0]), float(vale[2]))
		var z := rng.randf_range(float(vale[1]), float(vale[3]))
		var h := _terreno.altura_em(x, z)
		if h > 12.0 or h < 4.6 or _perto_do_percurso(Vector2(x, z), h):
			continue
		secos.append([Vector3(x, h - 0.05, z), rng.randf_range(0.8, 1.6), rng.randf() * TAU, Color(1.05, 0.95, 0.75) * rng.randf_range(0.8, 1.1)])
	Vegetacao.plantar(self, Vegetacao.Tipo.PALMEIRA, palmeiras, 400.0, 3000.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.CAPIM, papiros, 160.0, 700.0, false)
	Vegetacao.plantar(self, Vegetacao.Tipo.SALVIA, secos, 300.0, 1200.0, false)


## Longe das construções, do alvo e de onde a estrada passa baixa (a planta atravessaria).
func _perto_do_percurso(p: Vector2, chao: float) -> bool:
	if altura(p.x, p.y) > -INF or maxf(absf(p.x - _pir_c.x), absf(p.y - _pir_c.y)) < _pir_mb + 20.0:
		return true
	if p.length() < 70.0:
		return true
	for t in _cfg.get("templos", []):
		if p.distance_to(Vector2(float(t[0]), float(t[1]))) < 260.0:
			return true
	var largada: Array = Config.valor("mapa.subida.largada.origem", [0, 0, 0])
	if p.distance_to(Vector2(float(largada[0]), float(largada[2]) - 35.0)) < 90.0:
		return true
	return _terreno._estrada_baixa_perto(p, chao)


## Feluccas: barcos de madeira com vela latina branca, descendo o Nilo devagar e balançando.
func _montar_feluccas() -> void:
	var qtd := int(_cfg.get("feluccas", 0))
	if qtd <= 0 or _nilo.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var casco := _malha_casco()
	var vela := _malha_vela()
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.36, 0.22, 0.13)
	madeira.roughness = 0.8
	madeira.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pano := StandardMaterial3D.new()
	pano.albedo_color = Color(0.95, 0.92, 0.84)
	pano.roughness = 0.9
	pano.cull_mode = BaseMaterial3D.CULL_DISABLED
	pano.backlight_enabled = true
	pano.backlight = Color(0.5, 0.45, 0.35)
	var total := _nilo_s[_nilo_s.size() - 1]
	for i in qtd:
		var barco := Node3D.new()
		var mc := MeshInstance3D.new()
		mc.mesh = casco
		mc.material_override = madeira
		barco.add_child(mc)
		var mastro := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = 0.07
		cil.bottom_radius = 0.12
		cil.height = 8.5
		mastro.mesh = cil
		mastro.material_override = madeira
		mastro.position = Vector3(0.0, 4.6, -1.2)
		barco.add_child(mastro)
		var mv := MeshInstance3D.new()
		mv.mesh = vela
		mv.material_override = pano
		mv.position = Vector3(0.0, 1.0, -1.2)
		mv.rotation.y = rng.randf_range(-0.5, 0.5)
		barco.add_child(mv)
		var esc := rng.randf_range(0.9, 1.4)
		barco.scale = Vector3.ONE * esc
		add_child(barco)
		# Longe da parte do rio sob o salto (os barcos não ficam no caminho da câmera)
		_feluccas.append([barco, rng.randf_range(0.1, 0.9) * total, rng.randf_range(1.2, 2.4) * (1.0 if rng.randf() < 0.7 else -1.0), rng.randf() * TAU, rng.randf_range(-14.0, 14.0)])
	set_process(true)


## Casco: seção em "U" afinando na proa e na popa (levantadas), 10 m de comprimento.
static func _malha_casco() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 10
	var secoes: Array = []
	for i in n + 1:
		var t := float(i) / n
		var z := lerpf(-5.0, 5.0, t)
		var larg := 1.4 * sin(PI * clampf(t, 0.02, 0.98)) + 0.05
		var fundo := -0.7 * sin(PI * t)
		var borda := 0.5 + 0.9 * pow(absf(t - 0.5) * 2.0, 3.0)
		secoes.append([Vector3(-larg, borda, z), Vector3(-larg * 0.7, fundo * 0.6, z), Vector3(0.0, fundo, z), Vector3(larg * 0.7, fundo * 0.6, z), Vector3(larg, borda, z)])
	for i in n:
		for k in 4:
			var a: Vector3 = secoes[i][k]
			var b: Vector3 = secoes[i][k + 1]
			var c: Vector3 = secoes[i + 1][k + 1]
			var d: Vector3 = secoes[i + 1][k]
			var nrm := (b - a).cross(d - a).normalized()
			# Normal para fora do casco (o meio da seção fica acima do fundo)
			var meio := (a + c) * 0.5
			if nrm.dot(Vector3(meio.x, meio.y - 0.3, 0.0)) < 0.0:
				nrm = -nrm
			_quad(st, a, b, c, d, nrm)
	return st.commit()


## Vela latina: triângulo grande preso numa verga inclinada, com barriga (curvada pelo vento).
static func _malha_vela() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var topo := Vector3(0.0, 11.0, 4.5)
	var pe_frente := Vector3(0.0, 1.0, -4.0)
	var pe_tras := Vector3(0.0, 1.2, 3.5)
	var n := 6
	for i in n:
		for j in n - i:
			var f := func(u: float, v: float) -> Vector3:
				var p := pe_frente + (pe_tras - pe_frente) * u + (topo - pe_frente) * v
				var w := 1.0 - u - v
				p.x += 1.2 * 4.0 * u * v * 2.0 + 0.8 * u * w * 4.0 * 0.5
				return p
			var u0 := float(i) / n
			var v0 := float(j) / n
			var d := 1.0 / n
			var a: Vector3 = f.call(u0, v0)
			var b: Vector3 = f.call(u0 + d, v0)
			var c: Vector3 = f.call(u0, v0 + d)
			var nrm := (b - a).cross(c - a).normalized()
			for v: Vector3 in [a, b, c]:
				st.set_normal(nrm)
				st.add_vertex(v)
			if i + j < n - 1:
				var e: Vector3 = f.call(u0 + d, v0 + d)
				for v: Vector3 in [b, e, c]:
					st.set_normal(nrm)
					st.add_vertex(v)
	return st.commit()


func _process(delta: float) -> void:
	_t += delta
	if _feluccas.is_empty():
		return
	var total := _nilo_s[_nilo_s.size() - 1]
	for f: Array in _feluccas:
		f[1] = fposmod(f[1] + f[2] * delta, total)
		var r := _no_rio(f[1])
		var p: Vector2 = r[0]
		var d: Vector2 = r[1] * signf(f[2])
		var lado: Vector2 = Vector2(-d.y, d.x) * f[4]
		var barco: Node3D = f[0]
		barco.position = Vector3(p.x + lado.x, float(Config.valor("mapa.nivel_agua", 4)) + 0.15 + sin(_t * 1.3 + f[3]) * 0.08, p.y + lado.y)
		barco.rotation = Vector3(sin(_t * 0.9 + f[3]) * 0.03, atan2(-d.x, -d.y), sin(_t * 1.1 + f[3]) * 0.05)


# ------------------------------------------------------------------ etapas

## Troca o que muda por etapa: obeliscos, Portal de Anúbis e a tempestade de areia (vento).
func preparar_etapa(indice: int, cfg_etapa: Dictionary) -> void:
	for f in _etapa_no.get_children():
		f.queue_free()
	_obeliscos_etapa.clear()
	var e: Dictionary = _cfg.get("etapas", {}).get(str(indice + 1), {})
	for o in e.get("obeliscos", []):
		_obeliscos_etapa.append(_obelisco_dados(o))
	if not _obeliscos_etapa.is_empty():
		_montar_obeliscos(_etapa_no, _obeliscos_etapa)
	var portal: Dictionary = e.get("portal", {})
	if not portal.is_empty():
		_montar_portal(portal)
	_vento_cfg = cfg_etapa.get("vento", {})
	_tempestade_visual(bool(e.get("tempestade", false)))
	if _vento_cfg.is_empty():
		Veiculo.vento = Vector3.ZERO


func _physics_process(_delta: float) -> void:
	if _vento_cfg.is_empty():
		return
	var ang := deg_to_rad(float(_vento_cfg.get("direcao", 90)))
	var dir := Vector3(sin(ang), 0.0, -cos(ang))   # 0 = norte (-z), 90 = leste (+x)
	var periodo := maxf(float(_vento_cfg.get("periodo", 6.0)), 0.5)
	var rajada := float(_vento_cfg.get("rajada", 0.0)) * (0.5 + 0.5 * sin(_t * TAU / periodo)) * (0.7 + 0.3 * sin(_t * 2.3))
	Veiculo.vento = dir * (float(_vento_cfg.get("forca", 0.0)) + rajada)
	if _tempestade:
		var cam := get_viewport().get_camera_3d()
		if cam:
			_tempestade.global_position = cam.global_position


func _exit_tree() -> void:
	Veiculo.vento = Vector3.ZERO


## Tempestade de areia: céu e névoa alaranjados e densos, e rajadas de areia passando pela câmera.
func _tempestade_visual(ligar: bool) -> void:
	var we: WorldEnvironment = null
	var lista := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if not lista.is_empty():
		we = lista[0]
	if we and _env_original.is_empty():
		var env := we.environment
		_env_original = {"fog_density": env.fog_density, "fog_light_color": env.fog_light_color, "fog_sky_affect": env.fog_sky_affect,
			"fog_aerial_perspective": env.fog_aerial_perspective}
	if we:
		var env := we.environment
		env.fog_density = 0.0016 if ligar else _env_original.fog_density
		env.fog_light_color = Color(0.85, 0.55, 0.28) if ligar else _env_original.fog_light_color
		env.fog_sky_affect = 0.75 if ligar else _env_original.fog_sky_affect
		env.fog_aerial_perspective = 0.2 if ligar else _env_original.fog_aerial_perspective
	if _tempestade:
		_tempestade.queue_free()
		_tempestade = null
	if not ligar:
		return
	_tempestade = Node3D.new()
	_tempestade.name = "Tempestade"
	_tempestade.top_level = true
	add_child(_tempestade)
	var ang := deg_to_rad(float(_vento_cfg.get("direcao", 90)))
	var dir := Vector3(sin(ang), -0.04, -cos(ang))
	# Nuvens de poeira: bolas grandes e translúcidas de areia rolando com o vento (aparecem e somem
	# devagar), e grãos pequenos passando rápido perto da câmera. Nada de risco comprido.
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 0.0))
	curva.add_point(Vector2(0.3, 1.0))
	curva.add_point(Vector2(0.7, 1.0))
	curva.add_point(Vector2(1.0, 0.0))
	var tc := CurveTexture.new()
	tc.curve = curva
	for camada: Array in [
			# [quantidade, vida, caixa, vel. mín, vel. máx, tamanho mín, máx, quad, cor, textura macia]
			[110, 6.0, Vector3(170, 45, 170), 16.0, 26.0, 22.0, 55.0, 1.0, Color(0.55, 0.36, 0.2, 0.55), true],
			[70, 4.0, Vector3(60, 18, 60), 20.0, 30.0, 8.0, 16.0, 1.0, Color(0.6, 0.4, 0.22, 0.4), true],
			[900, 1.6, Vector3(35, 14, 35), 30.0, 44.0, 0.05, 0.11, 1.0, Color(0.62, 0.45, 0.28, 0.7), false]]:
		var part := GPUParticles3D.new()
		part.amount = camada[0]
		part.lifetime = camada[1]
		part.preprocess = camada[1]
		part.visibility_aabb = AABB(Vector3(-260, -90, -260), Vector3(520, 180, 520))
		part.local_coords = false
		var proc := ParticleProcessMaterial.new()
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		proc.emission_box_extents = camada[2]
		proc.direction = dir
		proc.spread = 10.0
		proc.initial_velocity_min = camada[3]
		proc.initial_velocity_max = camada[4]
		proc.gravity = Vector3.ZERO
		proc.scale_min = camada[5]
		proc.scale_max = camada[6]
		proc.angle_min = 0.0
		proc.angle_max = 360.0
		proc.angular_velocity_min = -12.0
		proc.angular_velocity_max = 12.0
		proc.alpha_curve = tc
		part.process_material = proc
		var quad := QuadMesh.new()
		quad.size = Vector2(camada[7], camada[7])
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = camada[8]
		mat.vertex_color_use_as_albedo = true
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.albedo_texture = Selva._textura_nuvem() if camada[9] else null
		if camada[9]:
			mat.proximity_fade_enabled = true
			mat.proximity_fade_distance = 6.0
		quad.material = mat
		part.draw_pass_1 = quad
		_tempestade.add_child(part)


# ------------------------------------------------------------------ Portal de Anúbis (etapa 2)

## Muralha de templo (pilone) de um paredão ao outro do vale, com o portão no alto (o caminho) e a
## "janela do sol" estreita (atalho: passar de paraquedas aberto murcha o velame). Arenito com
## hieróglifos, cornija egípcia no topo, batentes dourados com luzes, disco solar alado sobre o
## portão, braseiros e dois colossos de Anúbis aos pés. Tudo mortal.
func _montar_portal(cfg: Dictionary) -> void:
	var a := Vector2(float(cfg.a[0]), float(cfg.a[1]))
	var b := Vector2(float(cfg.b[0]), float(cfg.b[1]))
	var esp := float(cfg.get("espessura", 14.0))
	var topo := float(cfg.get("altura", 235.0))
	var comp := a.distance_to(b)
	var d2 := (b - a) / comp
	var d := Vector3(d2.x, 0.0, d2.y)
	var n := d.cross(Vector3.UP).normalized()
	var bl := Basis(d, Vector3.UP, n)
	var origem := Vector3(a.x, 0.0, a.y)
	var base := _chao - 4.0
	var caixa := func(t0: float, t1: float, y0: float, y1: float, e: float, desloc := 0.0) -> Transform3D:
		return Transform3D(bl * Basis.from_scale(Vector3(t1 - t0, y1 - y0, e)), origem + d * ((t0 + t1) * 0.5) + Vector3.UP * ((y0 + y1) * 0.5) + n * desloc)
	# Aberturas: [t0, t1, y0, y1, é a janela]
	var aberturas: Array = []
	for chave in ["portao", "janela"]:
		var ab: Dictionary = cfg.get(chave, {})
		if ab.is_empty():
			continue
		var t := (Vector2(float(ab.x), a.y + d2.y * (float(ab.x) - a.x) / maxf(absf(d2.x), 0.001)) - a).dot(d2)
		var meia := float(ab.get("largura", 30)) * 0.5
		aberturas.append([t - meia, t + meia, float(ab.y0), float(ab.y1), chave == "janela"])
	aberturas.sort_custom(func(p, q): return p[0] < q[0])
	var pedra: Array[Transform3D] = []
	var t_ant := 0.0
	for ab: Array in aberturas:
		pedra.append(caixa.call(t_ant, ab[0], base, topo, esp))
		pedra.append(caixa.call(ab[0], ab[1], base, ab[2], esp))
		pedra.append(caixa.call(ab[0], ab[1], ab[3], topo, esp))
		t_ant = ab[1]
	pedra.append(caixa.call(t_ant, comp, base, topo, esp))
	var mat := _material_pedra(2, 2.4)
	mat.set_shader_parameter("bloco", 4.5)
	mat.set_shader_parameter("coluna_glifos_largura", 7.0)
	mat.set_shader_parameter("pintura", 0.55)
	ComplexoLancamento.criar_multimesh(_etapa_no, pedra, mat)
	# Cornija (gola egípcia) e toro no topo, nas duas faces
	var cornija: Array[Transform3D] = []
	cornija.append(caixa.call(0.0, comp, topo - 2.0, topo + 5.0, esp + 5.0))
	cornija.append(caixa.call(0.0, comp, topo - 4.5, topo - 2.0, esp + 2.4))
	var mat_c := _material_pedra(0, 2.5)
	mat_c.set_shader_parameter("cor_pedra", Color(0.88, 0.76, 0.56))
	ComplexoLancamento.criar_multimesh(_etapa_no, cornija, mat_c)
	# Batentes dourados com lâmpadas em volta do portão e da janela, nas duas faces
	var ouro: Array[Transform3D] = []
	var luzes: Array[Transform3D] = []
	for ab: Array in aberturas:
		var w := 1.2 if not ab[4] else 0.8
		for s: float in [-1.0, 1.0]:
			var face := s * (esp * 0.5 + 0.3)
			ouro.append(caixa.call(ab[0] - w, ab[0], ab[2] - w, ab[3] + w, 0.6, face))
			ouro.append(caixa.call(ab[1], ab[1] + w, ab[2] - w, ab[3] + w, 0.6, face))
			ouro.append(caixa.call(ab[0] - w, ab[1] + w, ab[3], ab[3] + w, 0.6, face))
			ouro.append(caixa.call(ab[0] - w, ab[1] + w, ab[2] - w, ab[2], 0.6, face))
			var perim: float = 2.0 * ((ab[1] - ab[0]) + (ab[3] - ab[2]))
			var qtd := int(perim / 2.5)
			for k in qtd:
				var u: float = float(k) / qtd * perim
				var q: Vector2
				var lx: float = ab[1] - ab[0]
				var ly: float = ab[3] - ab[2]
				if u < lx:
					q = Vector2(ab[0] + u, ab[2] - w * 0.5)
				elif u < lx + ly:
					q = Vector2(ab[1] + w * 0.5, ab[2] + u - lx)
				elif u < 2.0 * lx + ly:
					q = Vector2(ab[1] - (u - lx - ly), ab[3] + w * 0.5)
				else:
					q = Vector2(ab[0] - w * 0.5, ab[3] - (u - 2.0 * lx - ly))
				luzes.append(Transform3D(bl * Basis.from_scale(Vector3(0.45, 0.45, 0.3)), origem + d * q.x + Vector3.UP * q.y + n * (face + s * 0.35)))
	ComplexoLancamento.criar_multimesh(_etapa_no, ouro, _material_ouro(0.3))
	ComplexoLancamento.criar_multimesh(_etapa_no, luzes, ComplexoLancamento._material_luz(Color(1.0, 0.68, 0.28), 7.0), false)
	# Disco solar alado sobre o portão (as duas faces)
	for ab: Array in aberturas:
		if ab[4]:
			continue
		var meio_t: float = (ab[0] + ab[1]) * 0.5
		var y_disco: float = ab[3] + 14.0
		for s: float in [-1.0, 1.0]:
			var face := s * (esp * 0.5 + 0.8)
			var centro := origem + d * meio_t + Vector3.UP * y_disco + n * face
			var disco := MeshInstance3D.new()
			var cil := CylinderMesh.new()
			cil.top_radius = 6.5
			cil.bottom_radius = 6.5
			cil.height = 1.2
			cil.radial_segments = 40
			disco.mesh = cil
			disco.material_override = _material_ouro(0.6)
			disco.transform = Transform3D(Basis(d, n, -Vector3.UP), centro)
			_etapa_no.add_child(disco)
			var asas: Array[Transform3D] = []
			for lado: float in [-1.0, 1.0]:
				for pena in 5:
					var comp_a := 26.0 - pena * 3.5
					var y_a := y_disco + 2.5 - pena * 1.6
					var t0 := meio_t + lado * 7.0
					var t1 := meio_t + lado * (7.0 + comp_a)
					asas.append(caixa.call(minf(t0, t1), maxf(t0, t1), y_a - 0.7, y_a + 0.7, 0.5, face))
			var mat_asa := StandardMaterial3D.new()
			mat_asa.albedo_color = Color(0.12, 0.3, 0.62)
			mat_asa.metallic = 0.4
			mat_asa.roughness = 0.4
			ComplexoLancamento.criar_multimesh(_etapa_no, asas, mat_asa)
		# Braseiros com fogo dos dois lados do portão, embaixo
		for s: float in [-1.0, 1.0]:
			for lado: float in [-1.0, 1.0]:
				var p: Vector3 = origem + d * (meio_t + lado * ((ab[1] - ab[0]) * 0.5 + 8.0)) + n * s * (esp * 0.5 + 6.0)
				p.y = ab[2] - 0.5
				Fogo.criar(_etapa_no, p, 1.2, 6.0, 40, 2.0)
				var luz := OmniLight3D.new()
				luz.light_color = Color(1.0, 0.55, 0.2)
				luz.light_energy = 6.0
				luz.omni_range = 40.0
				luz.position = p + Vector3.UP * 3.0
				_etapa_no.add_child(luz)
	# Colossos de Anúbis aos pés da muralha, dos dois lados do portão (de frente para a rampa)
	for ab: Array in aberturas:
		if ab[4]:
			continue
		for lado: float in [-1.0, 1.0]:
			var est := _estatua_anubis(150.0)   # Anúbis deitado de ~43 m de altura
			if est == null:
				break
			# Do lado de quem chega (a rampa fica ao norte, -Z), olhando para ela
			var para_rampa := -n if n.z > 0.0 else n
			var p: Vector3 = origem + d * ((ab[0] + ab[1]) * 0.5 + lado * ((ab[1] - ab[0]) * 0.5 + 30.0)) + para_rampa * (esp * 0.5 + 88.0)
			p.y = _terreno.altura_em(p.x, p.z) - 0.5
			est.position = p
			est.rotation.y = atan2(-para_rampa.x, -para_rampa.z)
			_etapa_no.add_child(est)
	# Colisão mortal e a janela que murcha o velame
	var corpo := _corpo_mortal(_etapa_no)
	ComplexoLancamento.adicionar_colisoes(corpo, pedra)
	ComplexoLancamento.adicionar_colisoes(corpo, cornija)
	for ab: Array in aberturas:
		if not ab[4]:
			continue
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitorable = false
		var cs := CollisionShape3D.new()
		var forma := BoxShape3D.new()
		forma.size = Vector3(ab[1] - ab[0], ab[3] - ab[2], esp + 3.0)
		cs.shape = forma
		area.add_child(cs)
		area.transform = Transform3D(bl, origem + d * ((ab[0] + ab[1]) * 0.5) + Vector3.UP * ((ab[2] + ab[3]) * 0.5))
		area.body_entered.connect(_passou_na_janela)
		_etapa_no.add_child(area)


func _passou_na_janela(corpo: Node3D) -> void:
	var v := corpo as Veiculo
	if v and v.paraquedas_aberto:
		v.murchar_velame()
