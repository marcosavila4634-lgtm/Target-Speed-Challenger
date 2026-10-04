class_name Gelo
extends Node3D
## Frozen Peak (mapa.subida.gelo): vale glacial cercado de montanhas nevadas.
## - lago e rio congelados cavados no terreno (cavar; a superfície é gelo, ver Terreno._criar_agua);
## - fortalezas de blocos de gelo nos quatro cantos de cada plataforma (uma por etapa), com bandeiras
##   e painéis do logo; agulhas de gelo (seracs), rochas, pinheiros nevados, vilas de chalés com
##   fumaça na chaminé, teleférico com cabines andando, outdoors gigantes e balões com o logo;
## - obstáculos do voo por etapa (mapa.subida.gelo.etapas.N): agulhas de gelo (pilares) e muralhas de
##   blocos de gelo com aberturas pequenas para passar. Tudo mortal;
## - neve caindo o tempo todo e, nas etapas com vento, a nevasca: véus de neve soprada, flocos em
##   redemoinho, birutas e bandeiras acompanhando as rajadas (nada de risco branco).

enum Mat { GELO, BLOCOS, ROCHA, CONCRETO, NEVE, ACO, VERMELHO, NEON, MADEIRA }

const LOGO := "res://assets/ui/logo_tsc.png"
const PROP_LOGO := 790.0 / 290.0
const CEL := 40.0

static var _mats := {}
## Vento da etapa para o que balança (bandeiras, birutas): força de 0 a 1 e direção.
static var vento_visual := 0.0
static var vento_dir := Vector3.RIGHT
static var _birutas: Array = []     # [nó, material]

var penhasco := 260.0
var _terreno: Terreno
var _cfg: Dictionary = {}
var _chao := 6.5
var _lagos: Array = []              # [centro Vector2, raio]
var _rio := PackedVector2Array()
var _rio_meia := 26.0
var _pilares_fixos: Array = []      # [centro Vector2, raio, altura]
var _pilares_etapa: Array = []
var _estradas: Array = []           # pontos de controle de todas as estradas (todas as etapas)
var _grade_estrada := {}
var _evitar: Array = []             # [centro Vector2, raio] sem cenário
var _corredores: Array = []         # [a Vector2, b Vector2, meia-largura] voo da rampa final ao alvo
var _fortalezas: Array = []         # {o: Vector3, f: Vector3, comp, larg, etapa}
var _etapa_no: Node3D
var _vento_cfg: Dictionary = {}
var _vento_no: Node3D
var _neve_no: Node3D
var _t := 0.0
var _cabines: Array = []            # [nó, fase 0..1]
var _tele := {}
var _baloes: Array = []             # [nó, base, fase]
var _dirigiveis: Array = []         # {no, c, raio, vel, fase}


# ------------------------------------------------------------------ materiais (compartilhados)

static func material(m: Mat) -> Material:
	if _mats.has(m):
		return _mats[m]
	var r: Material
	match m:
		Mat.ACO:
			r = ComplexoLancamento._material_metal(Color(0.15, 0.17, 0.21), 0.85, 0.4)
		Mat.VERMELHO:
			r = ComplexoLancamento._material_metal(Color(0.72, 0.06, 0.05), 0.55, 0.35)
		Mat.NEON:
			r = ComplexoLancamento._material_luz(Color(0.25, 0.8, 1.0), 5.0)
		Mat.MADEIRA:
			var md := StandardMaterial3D.new()
			md.albedo_color = Color(0.34, 0.22, 0.13)
			md.roughness = 0.85
			r = md
		_:
			var s := ShaderMaterial.new()
			s.shader = load("res://shaders/gelo.gdshader")
			s.set_shader_parameter("modo", int(m))
			s.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 311))
			if m == Mat.GELO:
				# Gelo de geleira maciço (agulhas, seracs, pingentes): azul mais fundo que o dos blocos
				s.set_shader_parameter("cor_gelo", Color(0.17, 0.5, 0.78))
				s.set_shader_parameter("cor_gelo_fundo", Color(0.03, 0.2, 0.46))
				s.set_shader_parameter("brilho", 0.1)
				s.set_shader_parameter("neve", 0.6)
			r = s
	_mats[m] = r
	return r


## Blocos de gelo com fiada/bloco próprios (muralhas grandes usam blocos maiores).
static func material_blocos(fiada: float, bloco: float) -> ShaderMaterial:
	var chave := "blocos_%.1f_%.1f" % [fiada, bloco]
	if not _mats.has(chave):
		var s := (material(Mat.BLOCOS) as ShaderMaterial).duplicate() as ShaderMaterial
		s.set_shader_parameter("fiada", fiada)
		s.set_shader_parameter("bloco", bloco)
		_mats[chave] = s
	return _mats[chave]


static func material_logo() -> StandardMaterial3D:
	if not _mats.has("logo"):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var logo: Texture2D = load(LOGO)
		mat.albedo_texture = logo
		_mats["logo"] = mat
	return _mats["logo"]


## Bandeira com o logo (um material só: a força do vento é atualizada a cada quadro).
static func material_bandeira() -> ShaderMaterial:
	if not _mats.has("bandeira"):
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/bandeira_tsc.gdshader")
		m.set_shader_parameter("logo", load(LOGO))
		_mats["bandeira"] = m
	return _mats["bandeira"]


## Painel do logo do jogo: chapa escura, a arte (uma ou duas faces) e moldura de neon.
## `b` = base com +Z virado para quem lê; `altura` do logo em metros (a largura sai da proporção).
static func painel_logo(pai: Node3D, centro: Vector3, b: Basis, altura: float, duas_faces := false) -> void:
	var larg := altura * PROP_LOGO
	var fundo := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(larg + 0.8, altura + 0.8, 0.5)
	fundo.mesh = bm
	fundo.material_override = material(Mat.ACO)
	fundo.transform = Transform3D(b, centro)
	pai.add_child(fundo)
	for face: float in ([1.0, -1.0] if duas_faces else [1.0]):
		var q := QuadMesh.new()
		q.size = Vector2(larg, altura)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = material_logo()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(b if face > 0.0 else b * Basis(Vector3.UP, PI), centro + b.z * 0.27 * face)
		pai.add_child(mi)
	var neon: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		neon.append(Transform3D(b * Basis.from_scale(Vector3(larg + 1.0, 0.16, 0.62)), centro + b.y * s * (altura * 0.5 + 0.42)))
		neon.append(Transform3D(b * Basis.from_scale(Vector3(0.16, altura + 1.0, 0.62)), centro + b.x * s * (larg * 0.5 + 0.42)))
	ComplexoLancamento.criar_multimesh(pai, neon, material(Mat.NEON), false)


## Bandeira com o logo num mastro (pano de `larg` x `alt` m preso no topo do mastro de `mastro` m).
static func criar_bandeira(pai: Node3D, base: Vector3, mastro: float, larg := 4.2, alt := 2.4, fase := 0.0) -> void:
	ComplexoLancamento.criar_multimesh(pai, [ComplexoLancamento._viga(base, base + Vector3.UP * mastro, 0.14)], material(Mat.ACO))
	var pano := PlaneMesh.new()
	pano.size = Vector2(larg, alt)
	pano.subdivide_width = 14
	pano.subdivide_depth = 4
	pano.orientation = PlaneMesh.FACE_Z
	var mi := MeshInstance3D.new()
	mi.mesh = pano
	mi.material_override = material_bandeira()
	mi.set_instance_shader_parameter("fase", fase)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# O pano sai do mastro na direção do vento (o nó é girado a cada quadro, como as birutas)
	var no := Node3D.new()
	no.position = base + Vector3.UP * (mastro - alt * 0.5 - 0.2)
	mi.position = Vector3(larg * 0.5 + 0.1, 0.0, 0.0)
	no.add_child(mi)
	pai.add_child(no)
	_birutas.append([no, null])


static func _malha_biruta() -> ArrayMesh:
	if _mats.has("malha_biruta"):
		return _mats["malha_biruta"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lados := 10
	var aneis := 7
	var comp := 3.4
	for j in aneis:
		for i in lados:
			var q := []
			for par: Array in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var t := float(par[1]) / aneis
				var a: float = TAU * float(par[0]) / lados
				var r := lerpf(0.55, 0.2, t)
				q.append([Vector3(cos(a) * r, sin(a) * r, t * comp), Vector2(float(par[0]) / lados, t), Vector3(cos(a), sin(a), 0.2).normalized()])
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(q[k][2])
				st.set_uv(q[k][1])
				st.add_vertex(q[k][0])
	var m := st.commit()
	_mats["malha_biruta"] = m
	return m


## Biruta (manga de vento) num mastro: mostra para onde e quanto o vento sopra.
static func criar_biruta(pai: Node3D, base: Vector3, altura := 7.0) -> void:
	var pecas: Array[Transform3D] = [ComplexoLancamento._viga(base, base + Vector3.UP * altura, 0.16)]
	ComplexoLancamento.criar_multimesh(pai, pecas, material(Mat.VERMELHO))
	var no := Node3D.new()
	no.position = base + Vector3.UP * altura
	pai.add_child(no)
	var mi := MeshInstance3D.new()
	mi.mesh = _malha_biruta()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/biruta.gdshader")
	mat.set_shader_parameter("fase", base.x * 0.37 + base.z * 0.11)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	no.add_child(mi)
	_birutas.append([no, mat])


static func _caixa(pai: Node3D, tam: Vector3, pos: Vector3, mat: Material, giro := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	mi.mesh = b
	mi.material_override = mat
	mi.transform = Transform3D(giro, pos)
	pai.add_child(mi)
	return mi


static func _instancias(pai: Node, malha: Mesh, xfs: Array, mat: Material, sombra := true, alcance := 0.0) -> MultiMeshInstance3D:
	if xfs.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malha
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if alcance > 0.0:
		mmi.visibility_range_end = alcance
		mmi.visibility_range_end_margin = alcance * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	pai.add_child(mmi)
	return mmi


## Prisma afunilado de `lados` faces (agulha de gelo, pingente): raio 1 embaixo, `topo` em cima, altura 1,
## base em y = 0.
static func malha_prisma(lados: int, topo: float) -> CylinderMesh:
	var chave := "prisma_%d_%.2f" % [lados, topo]
	if not _mats.has(chave):
		var c := CylinderMesh.new()
		c.top_radius = topo
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = lados
		c.rings = 1
		_mats[chave] = c
	return _mats[chave]


static func _textura_floco() -> ImageTexture:
	if _mats.has("floco"):
		return _mats["floco"]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mats["floco"] = tex
	return tex


# ------------------------------------------------------------------ preparação (antes do terreno)

func preparar(terreno: Terreno) -> void:
	_terreno = terreno
	_cfg = Config.valor("mapa.subida.gelo", {})
	penhasco = float(_cfg.get("penhasco", 260.0))
	for l in _cfg.get("lagos", []):
		_lagos.append([Vector2(float(l[0]), float(l[1])), float(l[2])])
	var rio: Dictionary = _cfg.get("rio", {})
	for q in rio.get("pontos", []):
		_rio.append(Vector2(float(q[0]), float(q[1])))
	_rio_meia = float(rio.get("meia_largura", 26))
	for c in _cfg.get("pilares", []):
		_pilares_fixos.append([Vector2(float(c[0]), float(c[1])), float(c[2]), float(c[3])])
	# Estradas, cercados, alvos e corredores de voo de todas as etapas (o cenário não pode atravessar)
	var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
	var etapas: Array = Config.valor("etapas", [])
	for k in percursos:
		var pc: Dictionary = percursos[k]
		var trechos: Dictionary = pc.get("trechos", {})
		for nome in ["A", "B", "C"]:
			var pts := PackedVector3Array()
			for p in trechos.get(nome, []):
				pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			if pts.size() > 1:
				_estradas.append(pts)
		for chave in ["largada", "plataforma"]:
			var r: Dictionary = pc.get(chave, {})
			if r.is_empty():
				continue
			var o: Array = r.get("origem", [0, 0, 0])
			var f: Array = r.get("frente", [0, -1])
			var comp := float(r.get("comprimento", 70))
			var larg := float(r.get("largura", 90))
			var c2 := Vector2(float(o[0]), float(o[2])) + Vector2(float(f[0]), float(f[1])) * comp * 0.5
			_evitar.append([c2, maxf(comp, larg) * 0.75 + 30.0])
			if chave == "plataforma":
				_fortalezas.append({"o": Vector3(float(o[0]), float(o[1]), float(o[2])), "f": Vector3(float(f[0]), 0.0, float(f[1])).normalized(),
					"comp": comp, "larg": larg, "etapa": int(k) - 1})
		var idx := int(k) - 1
		var fim: Array = trechos.get("C", [[0, 0, 0]]).back()
		if idx < etapas.size():
			var d: Array = (etapas[idx] as Dictionary).get("deslocamento", [0, 0])
			var alvo := Vector2(float(d[0]), float(d[1]))
			_evitar.append([alvo, 130.0])
			_corredores.append([Vector2(float(fim[0]), float(fim[2])), alvo, 110.0])
	for pts: PackedVector3Array in _estradas:
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var r := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(40.0)
			for cx in range(floori(r.position.x / CEL), floori(r.end.x / CEL) + 1):
				for cz in range(floori(r.position.y / CEL), floori(r.end.y / CEL) + 1):
					var chave := Vector2i(cx, cz)
					if not _grade_estrada.has(chave):
						_grade_estrada[chave] = []
					_grade_estrada[chave].append([a, b])


# ------------------------------------------------------------------ alturas (mortais)

## Altura das agulhas de gelo em (x, z). -INF fora delas. (As muralhas com janelas não entram aqui:
## são só colisão, senão a janela ficaria fechada.)
func altura(x: float, z: float) -> float:
	var h := -INF
	for lista: Array in [_pilares_fixos, _pilares_etapa]:
		for col: Array in lista:
			if Vector2(x, z).distance_to(col[0]) < float(col[1]) * 0.8:
				h = maxf(h, _chao + float(col[2]))
	return h


func _dist_rio(p: Vector2) -> float:
	var melhor := INF
	for i in range(1, _rio.size()):
		var a := _rio[i - 1]
		var ab := _rio[i] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		melhor = minf(melhor, p.distance_to(a + ab * t))
	return melhor


func _dist_agua(p: Vector2) -> float:
	var d := INF
	if _rio.size() > 1:
		d = _dist_rio(p) - _rio_meia
	for l: Array in _lagos:
		d = minf(d, p.distance_to(l[0]) - float(l[1]))
	return d


## Leito do lago e do rio congelados: fundo a -5 m, margens subindo suave até o chão de neve.
func cavar(x: float, z: float, h: float) -> float:
	var d := _dist_agua(Vector2(x, z))
	if d > 120.0:
		return h
	h = minf(h, lerpf(-5.0, h, smoothstep(-20.0, 3.0, d)))
	h = minf(h, lerpf(5.2, h, smoothstep(2.0, 70.0, d)))
	return h


## Máscara (R = 1 no lago, cai a 0 a 70 m da margem) para o shader do terreno.
func textura_margem(meio: float) -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_R8)
	var passo := meio * 2.0 / n
	for iz in n:
		for ix in n:
			var d := _dist_agua(Vector2(-meio + (ix + 0.5) * passo, -meio + (iz + 0.5) * passo))
			img.set_pixel(ix, iz, Color(clampf(1.0 - d / 70.0, 0.0, 1.0), 0.0, 0.0))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ montagem

func montar() -> void:
	_birutas.clear()
	vento_visual = 0.0
	# TSC_GELO_SEM=<letras>: pula partes do cenário (conferência): f fortalezas, s seracs/rochas, v vilas,
	# t teleférico, o outdoors, b balões, p pinheiros, m bruma, n neve
	var sem := OS.get_environment("TSC_GELO_SEM")
	if not "f" in sem:
		_montar_fortalezas()
	var fixos := Node3D.new()
	fixos.name = "AgulhasFixas"
	add_child(fixos)
	_montar_pilares(fixos, _pilares_fixos)
	if not "s" in sem:
		_montar_seracs_e_rochas()
	if not "v" in sem:
		_montar_vilas()
	if not "t" in sem:
		_montar_teleferico()
	if not "o" in sem:
		for o in _cfg.get("outdoors", []):
			_outdoor(Vector2(float(o[0]), float(o[1])), deg_to_rad(float(o[2])), float(o[3]), float(o[4]))
	if not "b" in sem:
		_montar_baloes()
		_montar_dirigiveis()
	if not "p" in sem:
		_montar_vegetacao()
	if not "m" in sem:
		_montar_bruma()
	if not "n" in sem:
		_montar_neve_ambiente()
	_etapa_no = Node3D.new()
	_etapa_no.name = "Etapa"
	add_child(_etapa_no)


func _corpo(pai: Node, mortal := true) -> StaticBody3D:
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	if mortal:
		corpo.add_to_group("mortal")
	pai.add_child(corpo)
	return corpo


## Livre para cenário: fora da água, dos cercados/alvos, dos corredores de voo (para o que é alto) e
## longe de qualquer estrada que passe mais baixo que o topo do objeto.
func _livre(p: Vector2, alto: float, folga := 0.0) -> bool:
	if _dist_agua(p) < 6.0 + folga:
		return false
	for e: Array in _evitar:
		if p.distance_to(e[0]) < float(e[1]) + folga:
			return false
	if alto > 30.0:
		for c: Array in _corredores:
			var a: Vector2 = c[0]
			var ab: Vector2 = c[1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), -0.1, 1.15)
			if p.distance_to(a + ab * t) < float(c[2]) + folga:
				return false
	return not _estrada_perto(p, _terreno.altura_em(p.x, p.y), alto, folga)


func _estrada_perto(p: Vector2, chao: float, alto: float, folga := 0.0) -> bool:
	var lista: Array = _grade_estrada.get(Vector2i(floori(p.x / CEL), floori(p.y / CEL)), [])
	for seg: Array in lista:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if p.distance_to(a2 + ab * t) < 17.0 + alto * 0.2 + folga and lerpf(a.y, b.y, t) - 5.0 < chao + alto:
			return true
	return false


# ------------------------------------------------------------------ fortalezas de gelo

## Quatro torres de blocos de gelo nos cantos de cada plataforma (as de todas as etapas ficam de pé
## o tempo todo, como marcos do vale): ameias, bandeira do jogo no alto, painel do logo na face de
## fora e filetes de neon nas quinas.
func _montar_fortalezas() -> void:
	var no := Node3D.new()
	no.name = "Fortalezas"
	add_child(no)
	var blocos: Array[Transform3D] = []
	var coroas: Array[Transform3D] = []
	var ameias: Array[Transform3D] = []
	var neon: Array[Transform3D] = []
	var k_fase := 0.0
	for ft: Dictionary in _fortalezas:
		var o: Vector3 = ft.o
		var f: Vector3 = ft.f
		var lat := f.cross(Vector3.UP).normalized()
		var b := Basis.looking_at(f, Vector3.UP)
		var topo := o.y + 24.0
		for cx: float in [-4.0, float(ft.comp) + 4.0]:
			for s: float in [-1.0, 1.0]:
				var c := o + f * cx + lat * s * (float(ft.larg) * 0.5 + 4.0)
				var chao := _terreno.altura_em(c.x, c.z) - 3.0
				var lado := 17.0
				blocos.append(Transform3D(b * Basis.from_scale(Vector3(lado, topo - chao, lado)), Vector3(c.x, (topo + chao) * 0.5, c.z)))
				coroas.append(Transform3D(b * Basis.from_scale(Vector3(lado + 3.0, 3.2, lado + 3.0)), Vector3(c.x, topo + 1.6, c.z)))
				for ax: float in [-1.0, 0.0, 1.0]:
					for az: float in [-1.0, 0.0, 1.0]:
						if ax == 0.0 and az == 0.0:
							continue
						ameias.append(Transform3D(b * Basis.from_scale(Vector3(3.6, 3.4, 3.6)), Vector3(c.x, topo + 4.9, c.z) + f * ax * 8.2 + lat * az * 8.2))
				for qx: float in [-1.0, 1.0]:
					for qz: float in [-1.0, 1.0]:
						neon.append(Transform3D(b * Basis.from_scale(Vector3(0.3, topo - o.y + 30.0, 0.3)), Vector3(c.x, o.y - 15.0 + (topo - o.y) * 0.5, c.z) + f * qx * (lado * 0.5 + 0.1) + lat * qz * (lado * 0.5 + 0.1)))
				# Logo na face de fora (a que não dá para a plataforma) e bandeira no alto
				var fora := lat * s
				painel_logo(no, Vector3(c.x, o.y + 10.0, c.z) + fora * (lado * 0.5 + 0.35), Basis.looking_at(-fora, Vector3.UP), 4.6)
				var fora2 := f * signf(cx)
				painel_logo(no, Vector3(c.x, o.y + 10.0, c.z) + fora2 * (lado * 0.5 + 0.35), Basis.looking_at(-fora2, Vector3.UP), 4.6)
				criar_bandeira(no, Vector3(c.x, topo + 3.2, c.z), 13.0, 7.0, 3.6, k_fase)
				k_fase += 1.3
	ComplexoLancamento.criar_multimesh(no, blocos, material_blocos(2.2, 4.6))
	ComplexoLancamento.criar_multimesh(no, coroas, material_blocos(1.6, 3.2))
	ComplexoLancamento.criar_multimesh(no, ameias, material(Mat.BLOCOS))
	ComplexoLancamento.criar_multimesh(no, neon, material(Mat.NEON), false)
	var corpo := _corpo(no, false)
	ComplexoLancamento.adicionar_colisoes(corpo, blocos)


## Miolo de gelo das fortalezas que não são a plataforma da etapa (a da etapa tem o cercado e o
## pedestal dela): um bloco maciço entre as quatro torres, com parapeito e neve em cima.
func _miolos(pai: Node3D, etapa: int) -> void:
	var blocos: Array[Transform3D] = []
	var parapeitos: Array[Transform3D] = []
	for ft: Dictionary in _fortalezas:
		if int(ft.etapa) == etapa:
			continue
		var o: Vector3 = ft.o
		var f: Vector3 = ft.f
		var lat := f.cross(Vector3.UP).normalized()
		var b := Basis.looking_at(f, Vector3.UP)
		var c := o + f * float(ft.comp) * 0.5
		var chao := _terreno.altura_em(c.x, c.z) - 3.0
		blocos.append(Transform3D(b * Basis.from_scale(Vector3(float(ft.larg) + 5.0, o.y - chao, float(ft.comp) + 5.0)), Vector3(c.x, (o.y + chao) * 0.5, c.z)))
		for s: float in [-1.0, 1.0]:
			parapeitos.append(Transform3D(b * Basis.from_scale(Vector3(2.0, 5.0, float(ft.comp) + 5.0)), c + lat * s * (float(ft.larg) * 0.5 + 1.5) + Vector3.UP * 2.5))
			parapeitos.append(Transform3D(b * Basis.from_scale(Vector3(float(ft.larg) + 5.0, 5.0, 2.0)), c + f * s * (float(ft.comp) * 0.5 + 1.5) + Vector3.UP * 2.5))
	ComplexoLancamento.criar_multimesh(pai, blocos, material_blocos(2.2, 4.6))
	ComplexoLancamento.criar_multimesh(pai, parapeitos, material(Mat.BLOCOS))
	var corpo := _corpo(pai, false)
	ComplexoLancamento.adicionar_colisoes(corpo, blocos)


# ------------------------------------------------------------------ agulhas de gelo (pilares)

## Agulha de gelo: prisma de 7 lados afunilado, com base de lascas menores, capa de neve e baliza
## vermelha piscando no alto (para quem vem voando).
func _montar_pilares(pai: Node3D, lista: Array) -> void:
	if lista.is_empty():
		return
	var corpo := _corpo(pai)
	var fustes: Array = []
	var lascas: Array = []
	var capas: Array = []
	var balizas: Array = []
	for col: Array in lista:
		var c: Vector2 = col[0]
		var r: float = col[1]
		var alto: float = col[2]
		var giro := Terreno._hash2(int(c.x), int(c.y)) * TAU
		# Pé no chão do vale (altura_em já inclui a própria agulha: usá-la punha a agulha em cima dela mesma)
		var base := Vector3(c.x, _chao - 3.0, c.y)
		fustes.append(Transform3D(Basis(Vector3.UP, giro) * Basis.from_scale(Vector3(r, alto + 2.0, r)), base + Vector3.UP * (alto + 2.0) * 0.5))
		for k in 5:
			var a := giro + TAU * k / 5.0
			var rk := r * (0.35 + 0.25 * Terreno._hash2(int(c.x) + k, int(c.y)))
			var hk := alto * (0.18 + 0.2 * Terreno._hash2(int(c.x), int(c.y) + k))
			var eixo := (Vector3.UP + Vector3(cos(a), 0.0, sin(a)) * 0.22).normalized()
			var bk := Basis(Quaternion(Vector3.UP, eixo)) * Basis.from_scale(Vector3(rk, hk, rk))
			lascas.append(Transform3D(bk, base + Vector3(cos(a), 0.0, sin(a)) * r * 0.95 + eixo * hk * 0.5))
		capas.append(Transform3D(Basis.from_scale(Vector3(r * 0.6, r * 0.5, r * 0.6)), base + Vector3.UP * (alto + 2.0 + r * 0.25)))
		balizas.append(Transform3D(Basis.from_scale(Vector3.ONE * 2.4), base + Vector3.UP * (alto + 2.0 + r * 0.5 + 1.2)))
		# Colisão em dois andares (o prisma afunila)
		for par: Array in [[0.25, 0.95, 0.5], [0.75, 0.74, 0.5]]:
			var cs := CollisionShape3D.new()
			var forma := CylinderShape3D.new()
			forma.radius = r * float(par[1])
			forma.height = (alto + 2.0) * float(par[2])
			cs.shape = forma
			cs.position = base + Vector3.UP * (alto + 2.0) * float(par[0])
			corpo.add_child(cs)
	var prisma := malha_prisma(7, 0.52)
	# A malha do cilindro é centrada: desloca para a base
	_instancias(pai, prisma, fustes, material(Mat.GELO))
	_instancias(pai, malha_prisma(5, 0.15), lascas, material(Mat.GELO))
	_instancias(pai, malha_prisma(7, 0.05), capas, material(Mat.NEVE))
	var esfera := SphereMesh.new()
	esfera.radius = 0.5
	esfera.height = 1.0
	esfera.radial_segments = 10
	esfera.rings = 5
	var mat_b := ShaderMaterial.new()
	mat_b.shader = load("res://shaders/luz_sequencial.gdshader")
	mat_b.set_shader_parameter("cor", Color(1.0, 0.1, 0.06))
	mat_b.set_shader_parameter("energia", 9.0)
	mat_b.set_shader_parameter("velocidade", 5.0)
	mat_b.set_shader_parameter("minimo", 0.05)
	_instancias(pai, esfera, balizas, mat_b, false)


## Ponte de treliça no alto, de uma agulha à outra, marcando o portão por onde se passa voando:
## o logo do jogo em cima (duas faces), lâmpadas verdes em sequência e anéis de neon nas duas
## agulhas do portão (raio `r`). Fica acima da altura do voo; bater nela explode.
func _montar_ponte(pai: Node3D, a: Vector3, b: Vector3, r: float) -> void:
	var aco: Array[Transform3D] = []
	aco.append_array(ComplexoLancamento.trelica(a, b, 6.0, 8.0, 0.7, 0.3))
	ComplexoLancamento.criar_multimesh(pai, aco, material(Mat.VERMELHO))
	var meio := (a + b) * 0.5
	var eixo := (b - a).normalized()
	var frente := eixo.cross(Vector3.UP).normalized()
	var alt := clampf(a.distance_to(b) * 0.16, 7.0, 13.0)
	painel_logo(pai, meio + Vector3.UP * (4.0 + alt * 0.5), Basis.looking_at(-frente, Vector3.UP), alt, true)
	var corpo := _corpo(pai)
	ComplexoLancamento.adicionar_colisoes(corpo, [ComplexoLancamento._viga(a, b, 6.0), Transform3D(Basis.looking_at(-frente, Vector3.UP) * Basis.from_scale(Vector3(alt * PROP_LOGO + 1.0, alt + 1.0, 1.0)), meio + Vector3.UP * (4.0 + alt * 0.5))])
	# Lâmpadas verdes correndo por baixo da ponte e descendo pelas duas agulhas
	var luzes: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	var n := int(a.distance_to(b) / 4.0)
	for k in n:
		luzes.append(Transform3D(Basis.from_scale(Vector3.ONE * 1.6), a.lerp(b, (k + 0.5) / n) + Vector3.DOWN * 3.4))
		fases.append(k * 0.5)
	for ponta: Vector3 in [a, b]:
		var dentro := (meio - ponta).normalized()
		for k in 26:
			var y := ponta.y - 6.0 - k * 6.0
			var raio_y := r * lerpf(0.52, 1.0, clampf((ponta.y - y) / maxf(ponta.y - _chao, 1.0), 0.0, 1.0))
			luzes.append(Transform3D(Basis.from_scale(Vector3.ONE * 1.6), Vector3(ponta.x, y, ponta.z) + dentro * (raio_y + 0.6)))
			fases.append(k * 0.6)
	var mat_l := ShaderMaterial.new()
	mat_l.shader = load("res://shaders/luz_sequencial.gdshader")
	mat_l.set_shader_parameter("cor", Color(0.2, 1.0, 0.35))
	mat_l.set_shader_parameter("energia", 9.0)
	mat_l.set_shader_parameter("velocidade", 5.0)
	var esfera := SphereMesh.new()
	esfera.radius = 0.5
	esfera.height = 1.0
	esfera.radial_segments = 8
	esfera.rings = 4
	esfera.material = mat_l
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = esfera
	mm.instance_count = luzes.size()
	for i in luzes.size():
		mm.set_instance_transform(i, luzes[i])
		mm.set_instance_custom_data(i, Color(fases[i], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(mmi)


# ------------------------------------------------------------------ muralhas de gelo (voo)

## Muralha de blocos de gelo de `a` até `b` (xz), do chão até `altura`, com aberturas para passar
## voando: aberturas [{centro: metros ao longo desde a, largura, y0, y1}]. Moldura de aço vermelho
## com luzes em volta de cada abertura, o logo do jogo em cima dela (nas duas faces), capa de neve
## e ameias no topo. Bater em qualquer parte explode (grupo "mortal"); o velame que encostar murcha.
func _montar_muralha(pai: Node3D, cfg: Dictionary, corpo: StaticBody3D) -> void:
	var a := Vector2(float(cfg.a[0]), float(cfg.a[1]))
	var b := Vector2(float(cfg.b[0]), float(cfg.b[1]))
	var esp := float(cfg.get("espessura", 10.0))
	var topo := float(cfg.get("altura", 270.0))
	var comp := a.distance_to(b)
	var d2 := (b - a) / comp
	var d := Vector3(d2.x, 0.0, d2.y)
	var n := d.cross(Vector3.UP).normalized()
	var bl := Basis(d, Vector3.UP, n)
	var origem := Vector3(a.x, 0.0, a.y)
	var base := float(cfg.get("base", _chao - 4.0))
	var caixa := func(t0: float, t1: float, y0: float, y1: float, e: float, desloc := 0.0) -> Transform3D:
		return Transform3D(bl * Basis.from_scale(Vector3(t1 - t0, y1 - y0, e)), origem + d * ((t0 + t1) * 0.5) + Vector3.UP * ((y0 + y1) * 0.5) + n * desloc)
	var aberturas: Array = []
	for ab: Dictionary in cfg.get("aberturas", []):
		var t := float(ab.centro)
		if ab.has("raio"):
			# Furo redondo {centro, y, raio} (pedido do dono): a muralha abre um quadrado e _furo_redondo fecha os cantos
			var r := float(ab.raio)
			aberturas.append([t - r, t + r, float(ab.y) - r, float(ab.y) + r, true])
			_furo_redondo(pai, corpo, bl, origem + d * t + Vector3.UP * float(ab.y), r, esp)
			continue
		var meia := float(ab.get("largura", 40)) * 0.5
		aberturas.append([t - meia, t + meia, float(ab.y0), minf(float(ab.y1), topo)])
	aberturas.sort_custom(func(p, q): return p[0] < q[0])
	var gelo: Array[Transform3D] = []
	var t_ant := 0.0
	for ab: Array in aberturas:
		gelo.append(caixa.call(t_ant, ab[0], base, topo, esp))
		gelo.append(caixa.call(ab[0], ab[1], base, ab[2], esp))
		if float(ab[3]) < topo - 0.5:
			gelo.append(caixa.call(ab[0], ab[1], ab[3], topo, esp))
		t_ant = ab[1]
	gelo.append(caixa.call(t_ant, comp, base, topo, esp))
	ComplexoLancamento.criar_multimesh(pai, gelo, material_blocos(5.0, 11.0))
	ComplexoLancamento.adicionar_colisoes(corpo, gelo)
	# Capa de neve e ameias (só nos trechos fechados em cima)
	var neve: Array[Transform3D] = []
	var ameias: Array[Transform3D] = []
	t_ant = 0.0
	var fechados: Array = []
	for ab: Array in aberturas:
		fechados.append([t_ant, ab[0]])
		if float(ab[3]) < topo - 0.5:
			fechados.append([ab[0], ab[1]])
		t_ant = ab[1]
	fechados.append([t_ant, comp])
	for fx: Array in fechados:
		if float(fx[1]) - float(fx[0]) < 1.0:
			continue
		neve.append(caixa.call(fx[0], fx[1], topo, topo + 1.6, esp + 2.4))
		var qtd := maxi(int((float(fx[1]) - float(fx[0])) / 14.0), 1)
		for k in qtd:
			var tm: float = lerpf(fx[0], fx[1], (k + 0.5) / qtd)
			ameias.append(caixa.call(tm - 3.5, tm + 3.5, topo + 1.6, topo + 7.0, esp + 1.0))
	ComplexoLancamento.criar_multimesh(pai, neve, material(Mat.NEVE))
	ComplexoLancamento.criar_multimesh(pai, ameias, material(Mat.BLOCOS))
	# Molduras, luzes e logo
	var aco: Array[Transform3D] = []
	var luzes: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	for ab: Array in aberturas:
		if ab.size() > 4:
			continue   # furo redondo: moldura e luzes próprias
		var w := 2.2
		var aberta_em_cima := float(ab[3]) >= topo - 0.5
		for s: float in [-1.0, 1.0]:
			var face := s * (esp * 0.5 + 0.4)
			aco.append(caixa.call(ab[0] - w, ab[0], ab[2] - w, ab[3] + (0.0 if aberta_em_cima else w), 1.0, face))
			aco.append(caixa.call(ab[1], ab[1] + w, ab[2] - w, ab[3] + (0.0 if aberta_em_cima else w), 1.0, face))
			aco.append(caixa.call(ab[0] - w, ab[1] + w, ab[2] - w, ab[2], 1.0, face))
			if not aberta_em_cima:
				aco.append(caixa.call(ab[0] - w, ab[1] + w, ab[3], ab[3] + w, 1.0, face))
			var lx: float = ab[1] - ab[0]
			var ly: float = ab[3] - ab[2]
			var perim := 2.0 * (lx + ly)
			var qtd := int(perim / 3.0)
			for k in qtd:
				var u := float(k) / qtd * perim
				var q: Vector2
				if u < lx:
					q = Vector2(ab[0] + u, ab[2] - w * 0.5)
				elif u < lx + ly:
					q = Vector2(ab[1] + w * 0.5, ab[2] + u - lx)
				elif u < 2.0 * lx + ly:
					q = Vector2(ab[1] - (u - lx - ly), ab[3] + w * 0.5)
					if aberta_em_cima:
						continue
				else:
					q = Vector2(ab[0] - w * 0.5, ab[3] - (u - 2.0 * lx - ly))
				luzes.append(Transform3D(bl * Basis.from_scale(Vector3(0.9, 0.9, 0.5)), origem + d * q.x + Vector3.UP * q.y + n * (face + s * 0.6)))
				fases.append(k * 0.45)
			# Logo em cima da abertura (ou ao lado, se ela vai até o topo)
			var alt_logo := clampf((topo - float(ab[3])) * 0.45, 6.0, 16.0)
			var centro_logo: Vector3
			if aberta_em_cima:
				alt_logo = 12.0
				centro_logo = origem + d * (float(ab[1]) + w + alt_logo * PROP_LOGO * 0.5 + 6.0) + Vector3.UP * (float(ab[2]) + ly * 0.6)
			else:
				centro_logo = origem + d * ((float(ab[0]) + float(ab[1])) * 0.5) + Vector3.UP * (float(ab[3]) + w + 3.0 + alt_logo * 0.5)
			painel_logo(pai, centro_logo + n * (face + s * 0.5), Basis.looking_at(-n * s, Vector3.UP), alt_logo)
	ComplexoLancamento.criar_multimesh(pai, aco, material(Mat.VERMELHO))
	ComplexoLancamento.adicionar_colisoes(corpo, aco)
	# Muralha fechada e comprida: o logo do jogo gigante nas duas faces e torreões nas pontas
	if aberturas.is_empty() and comp > 150.0:
		var alt_g := clampf(comp * 0.06, 14.0, 30.0)
		for s: float in [-1.0, 1.0]:
			painel_logo(pai, origem + d * (comp * 0.5) + Vector3.UP * (base + (topo - base) * 0.66) + n * s * (esp * 0.5 + 0.6), Basis.looking_at(-n * s, Vector3.UP), alt_g)
	var torres: Array[Transform3D] = []
	var coroas: Array[Transform3D] = []
	for t_p: float in ([0.0, comp] if bool(cfg.get("torres", true)) else []):
		torres.append(caixa.call(t_p - esp * 1.3, t_p + esp * 1.3, base, topo + 14.0, esp * 2.6))
		coroas.append(caixa.call(t_p - esp * 1.6, t_p + esp * 1.6, topo + 14.0, topo + 19.0, esp * 3.2))
	ComplexoLancamento.criar_multimesh(pai, torres, material_blocos(5.0, 11.0))
	ComplexoLancamento.criar_multimesh(pai, coroas, material(Mat.NEVE))
	ComplexoLancamento.adicionar_colisoes(corpo, torres)
	var mat_l := ShaderMaterial.new()
	mat_l.shader = load("res://shaders/luz_sequencial.gdshader")
	mat_l.set_shader_parameter("cor", Color(0.3, 0.9, 1.0))
	mat_l.set_shader_parameter("energia", 8.0)
	mat_l.set_shader_parameter("velocidade", 5.0)
	ComplexoLancamento.criar_multimesh(pai, luzes, mat_l, false, fases)


## Furo redondo numa muralha de gelo: fecha os cantos do quadrado de lado 2r aberto em volta de `centro`
## (as duas faces com o furo e o túnel por dentro), com colisão em tiras, aro de aço vermelho e lâmpadas
## em sequência nas duas faces, e o logo em cima. `bl` = base da muralha (x ao longo, z = normal).
func _furo_redondo(pai: Node3D, corpo: StaticBody3D, bl: Basis, centro: Vector3, r: float, esp: float) -> void:
	var d := bl.x
	var n := bl.z
	const SEG := 64
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector3, b: Vector3, c: Vector3, nrm: Vector3) -> void:
		if (b - a).cross(c - a).dot(nrm) > 0.0:   # face da frente = sentido horário
			var troca := b
			b = c
			c = troca
		for v: Vector3 in [a, b, c]:
			st.set_normal(nrm)
			st.add_vertex(v)
	var no_circulo := func(a: float) -> Vector3:
		return centro + (d * cos(a) + Vector3.UP * sin(a)) * r
	var no_quadrado := func(a: float) -> Vector3:
		var m := maxf(absf(cos(a)), absf(sin(a)))
		return centro + (d * cos(a) + Vector3.UP * sin(a)) * (r / m)
	for k in SEG:
		var a0 := TAU * k / SEG
		var a1 := TAU * (k + 1) / SEG
		for s: float in [-1.0, 1.0]:
			var f := n * s * esp * 0.5
			tri.call(no_circulo.call(a0) + f, no_circulo.call(a1) + f, no_quadrado.call(a1) + f, n * s)
			tri.call(no_circulo.call(a0) + f, no_quadrado.call(a1) + f, no_quadrado.call(a0) + f, n * s)
		# Túnel: a parede de dentro do furo, de face a face
		var dentro := -(d * cos((a0 + a1) * 0.5) + Vector3.UP * sin((a0 + a1) * 0.5))
		var fa := n * esp * 0.5
		tri.call(no_circulo.call(a0) - fa, no_circulo.call(a1) - fa, no_circulo.call(a1) + fa, dentro)
		tri.call(no_circulo.call(a0) - fa, no_circulo.call(a1) + fa, no_circulo.call(a0) + fa, dentro)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material_blocos(5.0, 11.0)
	pai.add_child(mi)
	# Colisão: tiras verticais em cima e embaixo do furo (pela corda mais comprida de cada tira: não invade o furo)
	var tiras: Array[Transform3D] = []
	const TIRAS := 16
	for k in TIRAS:
		var x0 := lerpf(-r, r, float(k) / TIRAS)
		var x1 := lerpf(-r, r, float(k + 1) / TIRAS)
		var xm := 0.0 if x0 * x1 < 0.0 else minf(absf(x0), absf(x1))
		var h := sqrt(maxf(r * r - xm * xm, 0.0))
		if r - h < 0.05:
			continue
		for s: float in [-1.0, 1.0]:
			tiras.append(Transform3D(bl * Basis.from_scale(Vector3(x1 - x0, r - h, esp)), centro + d * ((x0 + x1) * 0.5) + Vector3.UP * s * (h + r) * 0.5))
	ComplexoLancamento.adicionar_colisoes(corpo, tiras)
	# Aro de aço e lâmpadas nas duas faces
	var w := clampf(r * 0.09, 0.7, 2.2)
	var luzes: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	for s: float in [-1.0, 1.0]:
		var aro := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r
		tm.outer_radius = r + w
		tm.rings = 64
		tm.ring_segments = 8
		aro.mesh = tm
		aro.material_override = material(Mat.VERMELHO)
		aro.transform = Transform3D(Basis(d, n * s, d.cross(n * s)), centro + n * s * (esp * 0.5 + 0.1))
		pai.add_child(aro)
		var qtd := maxi(int(TAU * r / 3.0), 10)
		for k in qtd:
			var a := TAU * k / qtd
			luzes.append(Transform3D(bl * Basis.from_scale(Vector3(0.9, 0.9, 0.5)), centro + (d * cos(a) + Vector3.UP * sin(a)) * (r + w * 0.5) + n * s * (esp * 0.5 + w * 0.5 + 0.3)))
			fases.append(k * 0.45)
		var alt_logo := clampf(r * 0.45, 5.0, 14.0)
		painel_logo(pai, centro + Vector3.UP * (r + w + 3.0 + alt_logo * 0.5) + n * s * (esp * 0.5 + 0.5), Basis.looking_at(-n * s, Vector3.UP), alt_logo)
	var mat_l := ShaderMaterial.new()
	mat_l.shader = load("res://shaders/luz_sequencial.gdshader")
	mat_l.set_shader_parameter("cor", Color(0.3, 0.9, 1.0) if r > 10.0 else Color(1.0, 0.75, 0.2))
	mat_l.set_shader_parameter("energia", 8.0)
	mat_l.set_shader_parameter("velocidade", 5.0)
	ComplexoLancamento.criar_multimesh(pai, luzes, mat_l, false, fases)


# ------------------------------------------------------------------ seracs e rochas

## Campos de seracs (lascas de gelo de geleira, em grupos) e rochas escuras com neve, espalhados
## pelo vale, longe das estradas, dos alvos e dos corredores de voo. Só visuais.
func _montar_seracs_e_rochas() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1)) + 311
	var vale: Array = Config.valor("mapa.subida.vale", [-2250, -1900, 1300, 1100])
	var seracs: Array = []
	var grupos := int(_cfg.get("seracs", 150))
	var tent := 0
	var feitos := 0
	while feitos < grupos and tent < grupos * 12:
		tent += 1
		var c := Vector2(rng.randf_range(float(vale[0]) - 200.0, float(vale[2]) + 200.0), rng.randf_range(float(vale[1]) - 200.0, float(vale[3]) + 200.0))
		var maior := rng.randf_range(14.0, 46.0)
		if not _livre(c, maior, 16.0):
			continue
		feitos += 1
		var n := rng.randi_range(5, 11)
		for k in n:
			var a := rng.randf() * TAU
			var dist := rng.randf_range(0.0, 15.0) * sqrt(float(k) / n + 0.1)
			var p := c + Vector2(cos(a), sin(a)) * dist
			var h := maior * rng.randf_range(0.3, 1.0) * (1.0 - dist / 40.0)
			var r := h * rng.randf_range(0.14, 0.26)
			var eixo := (Vector3.UP + Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))).normalized()
			var b := Basis(Quaternion(Vector3.UP, eixo)) * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r, h, r))
			var chao := _terreno.altura_em(p.x, p.y)
			seracs.append(Transform3D(b, Vector3(p.x, chao - 1.0, p.y) + eixo * h * 0.5))
	_instancias(self, malha_prisma(5, 0.22), seracs, material(Mat.GELO), true, 3600.0)
	var rochas: Array = []
	var meta := int(_cfg.get("rochas", 900))
	tent = 0
	while rochas.size() < meta and tent < meta * 8:
		tent += 1
		var p := Vector2(rng.randf_range(float(vale[0]) - 500.0, float(vale[2]) + 500.0), rng.randf_range(float(vale[1]) - 500.0, float(vale[3]) + 500.0))
		if not _livre(p, 8.0, 4.0):
			continue
		var e := rng.randf_range(1.2, 6.5)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.4, 0.4))
		var chao := _terreno.altura_em(p.x, p.y)
		rochas.append(Transform3D(b.scaled(Vector3(e * rng.randf_range(0.9, 1.6), e * rng.randf_range(0.5, 1.0), e)), Vector3(p.x, chao + e * 0.1, p.y)))
	var pedra := SphereMesh.new()
	pedra.radius = 1.0
	pedra.height = 2.0
	pedra.radial_segments = 7
	pedra.rings = 4
	_instancias(self, pedra, rochas, material(Mat.ROCHA), true, 2200.0)


# ------------------------------------------------------------------ vilas de chalés

static func _malha_telhado() -> ArrayMesh:
	# Prisma triangular (duas águas): largura 1 (x), altura 1 (y), comprimento 1 (z), base em y = 0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5, 0.0, -0.5)
	var b := Vector3(0.5, 0.0, -0.5)
	var c := Vector3(0.0, 1.0, -0.5)
	var a2 := Vector3(-0.5, 0.0, 0.5)
	var b2 := Vector3(0.5, 0.0, 0.5)
	var c2 := Vector3(0.0, 1.0, 0.5)
	Egito._quad(st, a, c, c2, a2, Vector3(-1.0, 0.5, 0.0).normalized())
	Egito._quad(st, c, b, b2, c2, Vector3(1.0, 0.5, 0.0).normalized())
	Egito._tri(st, a, b, c, Vector3.FORWARD)
	Egito._tri(st, b2, a2, c2, Vector3.BACK)
	return st.commit()


## Vilas alpinas (mapa.subida.gelo.vilas: [x, z, quantidade, raio]): chalés de madeira com telhado
## carregado de neve, janelas acesas, chaminé com fumaça, pilhas de lenha e postes de luz.
func _montar_vilas() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var corpos: Array[Transform3D] = []
	var bases: Array[Transform3D] = []
	var telhados: Array = []
	var janelas: Array[Transform3D] = []
	var chamines: Array[Transform3D] = []
	var postes: Array[Transform3D] = []
	var lampadas: Array[Transform3D] = []
	var n_fumaca := 0
	for v in _cfg.get("vilas", []):
		var centro := Vector2(float(v[0]), float(v[1]))
		var qtd := int(v[2])
		var raio := float(v[3])
		var feitos: Array = []
		var tent := 0
		while feitos.size() < qtd and tent < qtd * 30:
			tent += 1
			var ang := rng.randf() * TAU
			var p := centro + Vector2(cos(ang), sin(ang)) * sqrt(rng.randf()) * raio
			if not _livre(p, 12.0, 6.0):
				continue
			var perto := false
			for q: Vector2 in feitos:
				if q.distance_to(p) < 22.0:
					perto = true
			if perto:
				continue
			feitos.append(p)
			var chao := _terreno.altura_em(p.x, p.y)
			var giro := rng.randf() * TAU
			var b := Basis(Vector3.UP, giro)
			var w := rng.randf_range(8.0, 11.0)
			var l := rng.randf_range(10.0, 15.0)
			var h := rng.randf_range(4.2, 5.6)
			var base := Vector3(p.x, chao, p.y)
			bases.append(Transform3D(b * Basis.from_scale(Vector3(w + 1.0, 1.6, l + 1.0)), base + Vector3.UP * 0.2))
			corpos.append(Transform3D(b * Basis.from_scale(Vector3(w, h, l)), base + Vector3.UP * (1.0 + h * 0.5)))
			telhados.append(Transform3D(b * Basis.from_scale(Vector3(w + 2.6, w * 0.55, l + 2.4)), base + Vector3.UP * (1.0 + h)))
			chamines.append(Transform3D(b * Basis.from_scale(Vector3(1.1, 3.4, 1.1)), base + Vector3.UP * (1.0 + h + w * 0.3) + b * Vector3(w * 0.22, 0.0, l * 0.2)))
			if n_fumaca < 10:
				n_fumaca += 1
				Fogo.fumaca(self, base + Vector3.UP * (1.0 + h + w * 0.3 + 1.9) + b * Vector3(w * 0.22, 0.0, l * 0.2))
			for s: float in [-1.0, 1.0]:
				for k in 3:
					janelas.append(Transform3D(b * Basis.from_scale(Vector3(0.12, 1.3, 1.5)), base + Vector3.UP * (1.0 + h * 0.55) + b * Vector3(s * (w * 0.5 + 0.02), 0.0, (k - 1) * l * 0.3)))
				janelas.append(Transform3D(b * Basis.from_scale(Vector3(1.4, 1.3, 0.12)), base + Vector3.UP * (1.0 + h * 0.55) + b * Vector3(w * 0.22, 0.0, s * (l * 0.5 + 0.02))))
			var pp := base + b * Vector3(w * 0.5 + 4.0, 0.0, l * 0.5 + 3.0)
			pp.y = _terreno.altura_em(pp.x, pp.z)
			postes.append(ComplexoLancamento._viga(pp, pp + Vector3.UP * 5.5, 0.18))
			lampadas.append(Transform3D(Basis.from_scale(Vector3(0.7, 0.7, 0.7)), pp + Vector3.UP * 5.7))
	ComplexoLancamento.criar_multimesh(self, corpos, material(Mat.MADEIRA))
	ComplexoLancamento.criar_multimesh(self, bases, material(Mat.ROCHA))
	_instancias(self, _malha_telhado(), telhados, material(Mat.NEVE))
	ComplexoLancamento.criar_multimesh(self, chamines, material(Mat.ROCHA))
	ComplexoLancamento.criar_multimesh(self, janelas, ComplexoLancamento._material_luz(Color(1.0, 0.72, 0.35), 3.5), false)
	ComplexoLancamento.criar_multimesh(self, postes, material(Mat.ACO))
	ComplexoLancamento.criar_multimesh(self, lampadas, ComplexoLancamento._material_luz(Color(1.0, 0.8, 0.5), 6.0), false)


# ------------------------------------------------------------------ teleférico

## Teleférico de enfeite (mapa.subida.gelo.teleferico: a, b = [x, y, z] das estações, cabines):
## torres de treliça, dois cabos, estações nas pontas com o logo e cabines vermelhas indo por um
## cabo e voltando pelo outro.
func _montar_teleferico() -> void:
	var cfg: Dictionary = _cfg.get("teleferico", {})
	if cfg.is_empty():
		return
	var a := Vector3(float(cfg.a[0]), float(cfg.a[1]), float(cfg.a[2]))
	var b := Vector3(float(cfg.b[0]), float(cfg.b[1]), float(cfg.b[2]))
	var no := Node3D.new()
	no.name = "Teleferico"
	add_child(no)
	var eixo := b - a
	var comp := eixo.length()
	var dh := Vector3(eixo.x, 0.0, eixo.z).normalized()
	var lado := dh.cross(Vector3.UP).normalized()
	var aco: Array[Transform3D] = []
	var n := maxi(int(comp / 170.0), 2)
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		var chao := _terreno.altura_em(p.x, p.z) - 1.0
		aco.append_array(ComplexoLancamento.trelica(Vector3(p.x, chao, p.z), p + Vector3.UP * 3.0, 3.0, 5.0, 0.35, 0.16))
		aco.append(ComplexoLancamento._viga(p + Vector3.UP * 2.6 - lado * 5.0, p + Vector3.UP * 2.6 + lado * 5.0, 0.6))
	for s: float in [-1.0, 1.0]:
		aco.append(ComplexoLancamento._viga(a + lado * s * 4.0 + Vector3.UP * 2.2, b + lado * s * 4.0 + Vector3.UP * 2.2, 0.12))
	ComplexoLancamento.criar_multimesh(no, aco, material(Mat.ACO))
	# Estações: galpão de madeira com telhado de neve e o logo
	for ponta: Array in [[a, -dh], [b, dh]]:
		var p: Vector3 = ponta[0]
		var chao := _terreno.altura_em(p.x, p.z)
		var bb := Basis.looking_at(ponta[1], Vector3.UP)
		# Cabana de madeira no alto de uma torre de blocos de gelo (a estação de cima fica a quase 200 m)
		var centro_e := Vector3(p.x, 0.0, p.z) + (ponta[1] as Vector3) * 9.0
		_caixa(no, Vector3(16.0, 9.0, 14.0), centro_e + Vector3.UP * (p.y - 0.5), material(Mat.MADEIRA), bb)
		if p.y - 5.0 - chao > 1.0:
			_caixa(no, Vector3(13.0, p.y - 5.0 - chao + 2.0, 11.0), centro_e + Vector3.UP * ((p.y - 5.0 + chao - 2.0) * 0.5), material_blocos(2.2, 4.6), bb)
		var telhado := MeshInstance3D.new()
		telhado.mesh = _malha_telhado()
		telhado.material_override = material(Mat.NEVE)
		telhado.transform = Transform3D(bb * Basis.from_scale(Vector3(19.0, 6.0, 17.0)), Vector3(p.x, p.y + 4.0, p.z) + (ponta[1] as Vector3) * 9.0)
		no.add_child(telhado)
		painel_logo(no, Vector3(p.x, p.y - 2.0, p.z) + (ponta[1] as Vector3) * 9.0 + lado * 8.3, Basis.looking_at(-lado, Vector3.UP), 3.2)
		painel_logo(no, Vector3(p.x, p.y - 2.0, p.z) + (ponta[1] as Vector3) * 9.0 - lado * 8.3, Basis.looking_at(lado, Vector3.UP), 3.2)
	_tele = {"a": a, "b": b, "lado": lado, "dh": dh}
	var qtd := int(cfg.get("cabines", 8))
	for k in qtd:
		var cab := Node3D.new()
		no.add_child(cab)
		_caixa(cab, Vector3(2.6, 2.6, 3.6), Vector3(0.0, -2.6, 0.0), material(Mat.VERMELHO))
		_caixa(cab, Vector3(2.7, 0.9, 3.7), Vector3(0.0, -2.2, 0.0), ComplexoLancamento._material_luz(Color(0.75, 0.9, 1.0), 0.8))
		_caixa(cab, Vector3(0.14, 2.4, 0.14), Vector3(0.0, -0.1, 0.0), material(Mat.ACO))
		_caixa(cab, Vector3(2.9, 0.3, 3.9), Vector3(0.0, -1.2, 0.0), material(Mat.NEVE))
		_cabines.append([cab, float(k) / qtd])
	_mover_cabines()


func _mover_cabines() -> void:
	if _cabines.is_empty():
		return
	var a: Vector3 = _tele.a
	var b: Vector3 = _tele.b
	var lado: Vector3 = _tele.lado
	var dh: Vector3 = _tele.dh
	var volta := a.distance_to(b) * 2.0 / 6.0   # segundos por volta (6 m/s)
	for c: Array in _cabines:
		var u := fposmod(float(c[1]) + _t / volta, 1.0)
		var ida := u < 0.5
		var t := u * 2.0 if ida else 2.0 - u * 2.0
		var no: Node3D = c[0]
		no.position = a.lerp(b, t) + lado * (4.0 if ida else -4.0) + Vector3.UP * 2.2
		no.basis = Basis.looking_at(dh if ida else -dh, Vector3.UP) * Basis(Vector3.FORWARD, sin(_t * 0.8 + float(c[1]) * 20.0) * 0.04)


# ------------------------------------------------------------------ outdoors e balões

## Outdoor gigante com o logo, em pé no chão sobre duas pernas de treliça (duas faces).
func _outdoor(p: Vector2, giro: float, alt_painel: float, alt_pes: float) -> void:
	var chao := _terreno.altura_em(p.x, p.y) - 1.0
	var b := Basis(Vector3.UP, giro)
	var larg := alt_painel * PROP_LOGO
	var centro := Vector3(p.x, chao + alt_pes + alt_painel * 0.5, p.y)
	var aco: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var pe := Vector3(p.x, chao, p.y) + b.x * s * larg * 0.36
		aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * (alt_pes + alt_painel + 0.5), 2.0, 3.2, 0.3, 0.12))
		# Mão-francesa para trás
		aco.append(ComplexoLancamento._viga(pe + Vector3.UP * (alt_pes * 0.7), pe - b.z * alt_pes * 0.45, 0.35))
	ComplexoLancamento.criar_multimesh(self, aco, material(Mat.ACO))
	painel_logo(self, centro, b, alt_painel, true)
	# Holofotes embaixo (só o corpo aceso: sem luz de verdade)
	var focos: Array[Transform3D] = []
	for k in 4:
		focos.append(Transform3D(b * Basis.from_scale(Vector3(1.2, 0.5, 0.8)), centro + b.x * lerpf(-larg * 0.4, larg * 0.4, k / 3.0) - b.y * (alt_painel * 0.5 + 1.1) + b.z * 1.6))
		focos.append(Transform3D(b * Basis.from_scale(Vector3(1.2, 0.5, 0.8)), centro + b.x * lerpf(-larg * 0.4, larg * 0.4, k / 3.0) - b.y * (alt_painel * 0.5 + 1.1) - b.z * 1.6))
	ComplexoLancamento.criar_multimesh(self, focos, ComplexoLancamento._material_luz(Color(1.0, 0.95, 0.85), 5.0), false)
	# Braço de cada holofote até a borda de baixo do painel (ficavam soltos no ar, a 1,6 m dele)
	var bracos: Array[Transform3D] = []
	for f: Transform3D in focos:
		var lado_f := signf((f.origin - centro).dot(b.z))
		bracos.append(ComplexoLancamento._viga(f.origin, f.origin - b.z * lado_f * 1.6 + b.y * 1.2, 0.16))
	ComplexoLancamento.criar_multimesh(self, bracos, material(Mat.ACO))


## Balões de ar quente com o logo do jogo, bem acima do voo (mapa.subida.gelo.baloes: [x, y, z]).
func _montar_baloes() -> void:
	var lista: Array = _cfg.get("baloes", [])
	if lista.is_empty():
		return
	var malha := DragPista._malha_balao(8.0)
	var paletas := [[Color(0.75, 0.06, 0.05), Color(0.94, 0.95, 0.97), Color(0.05, 0.05, 0.06)], [Color(0.1, 0.45, 0.85), Color(0.94, 0.95, 0.97), Color(0.75, 0.06, 0.05)],
		[Color(0.05, 0.05, 0.06), Color(0.75, 0.06, 0.05), Color(0.8, 0.82, 0.86)]]
	for i in lista.size():
		var p := Vector3(float(lista[i][0]), float(lista[i][1]), float(lista[i][2]))
		var no := Node3D.new()
		no.name = "Balao"
		no.position = p
		no.rotation.y = i * 1.7
		no.scale = Vector3.ONE * (float(lista[i][3]) if (lista[i] as Array).size() > 3 else 2.2)
		add_child(no)
		var env := MeshInstance3D.new()
		env.mesh = malha
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/balao.gdshader")
		var pal: Array = paletas[i % paletas.size()]
		mat.set_shader_parameter("cor_a", pal[0])
		mat.set_shader_parameter("cor_b", pal[1])
		mat.set_shader_parameter("cor_c", pal[2])
		mat.set_shader_parameter("logo", load(LOGO))
		mat.set_shader_parameter("com_logo", 1.0)
		env.material_override = mat
		env.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no.add_child(env)
		_caixa(no, Vector3(1.4, 1.1, 1.4), Vector3(0, -3.55, 0), material(Mat.MADEIRA))
		for c: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3.ONE
			mi.mesh = bm
			mi.material_override = material(Mat.ACO)
			mi.transform = ComplexoLancamento._viga(Vector3(c.x * 1.1, 0.1, c.y * 1.1), Vector3(c.x * 0.65, -3.0, c.y * 0.65), 0.05)
			no.add_child(mi)
		_caixa(no, Vector3(0.5, 1.4, 0.5), Vector3(0, -1.1, 0), ComplexoLancamento._material_luz(Color(1.0, 0.55, 0.15), 6.0))
		_baloes.append([no, p, i * 2.1])


## Dirigíveis (gelo.dirigiveis: [x do centro, altura, z do centro, raio da volta, velocidade em m/s,
## comprimento]; pedido do dono): charuto prateado com faixas vermelhas e o logo do jogo nos dois lados,
## quatro lemes na cauda, gôndola com janelas acesas, dois motores com hélice girando e luzes de
## navegação. Dão voltas lentas sobre o vale (ver _process). Enfeite, sem colisão.
func _montar_dirigiveis() -> void:
	var girador: Script = load("res://scripts/efeitos/girador.gd")
	var lista: Array = _cfg.get("dirigiveis", [])
	for i in lista.size():
		var it: Array = lista[i]
		var comp := float(it[5]) if it.size() > 5 else 90.0
		var raio := comp * 0.14
		var no := Node3D.new()
		no.name = "Dirigivel"
		add_child(no)
		# Envelope: revolução em volta do eixo z (nariz em -z), mais cheio na frente e afinando para a cauda
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		const NU := 28
		const NV := 24
		var perfil := func(u: float) -> float:
			return raio * pow(sin(PI * pow(u, 0.72)), 0.62)
		for iu in NU:
			for iv in NV:
				var quad := []
				for q: Array in [[0, 0], [1, 0], [1, 1], [0, 1]]:
					var u := float(iu + int(q[0])) / NU
					var a := TAU * float(iv + int(q[1])) / NV
					var rr: float = perfil.call(u)
					quad.append([Vector3(cos(a) * rr, sin(a) * rr, (u - 0.5) * comp), Vector2(u, float(iv + int(q[1])) / NV)])
				for idx: int in [0, 1, 2, 0, 2, 3]:
					st.set_uv(quad[idx][1])
					st.add_vertex(quad[idx][0])
		st.generate_normals()
		var env := MeshInstance3D.new()
		env.mesh = st.commit()
		var me := ShaderMaterial.new()
		me.shader = load("res://shaders/dirigivel.gdshader")
		me.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 411))
		me.set_shader_parameter("cor_faixa", [Color(0.75, 0.06, 0.05), Color(0.1, 0.4, 0.8), Color(0.05, 0.05, 0.06)][i % 3])
		env.material_override = me
		env.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no.add_child(env)
		# Logo dos dois lados
		for s: float in [-1.0, 1.0]:
			painel_logo(no, Vector3(s * (raio * 0.99 + 0.15), raio * 0.12, -comp * 0.06), Basis.looking_at(Vector3(-s, 0.0, 0.0), Vector3.UP), raio * 0.62)
		# Lemes (quatro, em cruz) na cauda
		for k in 4:
			var b := Basis(Vector3.BACK, PI * 0.25 + PI * 0.5 * k)
			_caixa(no, Vector3(0.35, raio * 0.95, comp * 0.13), b * Vector3(0.0, raio * 0.62, 0.0) + Vector3(0, 0, comp * 0.4), material(Mat.VERMELHO), b)
		# Gôndola pendurada por montantes, com janelas acesas
		var g_y := -raio - 2.0
		_caixa(no, Vector3(raio * 0.42, 2.6, comp * 0.2), Vector3(0, g_y, -comp * 0.08), material(Mat.ACO))
		_caixa(no, Vector3(raio * 0.42 + 0.1, 0.9, comp * 0.17), Vector3(0, g_y + 0.35, -comp * 0.08), ComplexoLancamento._material_luz(Color(1.0, 0.85, 0.55), 2.5))
		for z: float in [-comp * 0.16, -comp * 0.08, 0.0]:
			for s: float in [-1.0, 1.0]:
				var mi_m := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3.ONE
				mi_m.mesh = bm
				mi_m.material_override = material(Mat.ACO)
				mi_m.transform = ComplexoLancamento._viga(Vector3(s * raio * 0.18, g_y + 1.3, z), Vector3(s * raio * 0.3, -raio * 0.9, z), 0.22)
				no.add_child(mi_m)
		# Motores com hélice nos dois lados da gôndola
		for s: float in [-1.0, 1.0]:
			var pm := Vector3(s * (raio * 0.21 + 2.6), g_y, comp * 0.02)
			_caixa(no, Vector3(1.5, 1.5, 3.6), pm, material(Mat.VERMELHO))
			_caixa(no, Vector3(2.4, 0.3, 0.6), pm - Vector3(s * 1.6, 0, 0), material(Mat.ACO))
			var helice := Node3D.new()
			helice.set_script(girador)
			helice.set("eixo", Vector3.BACK)
			helice.set("velocidade", 26.0)
			helice.position = pm + Vector3(0, 0, 2.0)
			no.add_child(helice)
			_caixa(helice, Vector3(0.3, 4.4, 0.12), Vector3.ZERO, material(Mat.ACO))
			_caixa(helice, Vector3(4.4, 0.3, 0.12), Vector3.ZERO, material(Mat.ACO))
		# Luzes de navegação e a do nariz
		_caixa(no, Vector3(0.8, 0.8, 0.8), Vector3(-raio, 0, 0), ComplexoLancamento._material_luz(Color(1, 0.05, 0.05), 6.0))
		_caixa(no, Vector3(0.8, 0.8, 0.8), Vector3(raio, 0, 0), ComplexoLancamento._material_luz(Color(0.1, 1.0, 0.2), 6.0))
		_caixa(no, Vector3(0.9, 0.9, 0.9), Vector3(0, 0, -comp * 0.5 - 0.3), ComplexoLancamento._material_luz(Color(1.0, 0.95, 0.8), 8.0))
		_dirigiveis.append({"no": no, "c": Vector3(float(it[0]), float(it[1]), float(it[2])), "raio": float(it[3]), "vel": float(it[4]), "fase": i * 2.3})
	_mover_dirigiveis()


func _mover_dirigiveis() -> void:
	for dg: Dictionary in _dirigiveis:
		var r: float = dg.raio
		var ang: float = float(dg.fase) + _t * float(dg.vel) / r
		var p: Vector3 = (dg.c as Vector3) + Vector3(cos(ang) * r, sin(_t * 0.11 + float(dg.fase)) * 6.0, sin(ang) * r)
		var frente := Vector3(-sin(ang), 0.0, cos(ang)) * signf(float(dg.vel))
		(dg.no as Node3D).transform = Transform3D(Basis.looking_at(frente, Vector3.UP), p)


# ------------------------------------------------------------------ vegetação

## Pinheiros nevados no vale e nas encostas (em bosques: mais densos onde o ruído manda), longe das
## estradas, dos cercados, dos alvos e dos corredores de voo.
func _montar_vegetacao() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1)) + 77
	var vale: Array = Config.valor("mapa.subida.vale", [-2250, -1900, 1300, 1100])
	var meta := int(_cfg.get("pinheiros", 9000))
	var bosque := FastNoiseLite.new()
	bosque.seed = 99
	bosque.frequency = 1.0 / 420.0
	var lista := []
	var tent := 0
	while lista.size() < meta and tent < meta * 14:
		tent += 1
		var x := rng.randf_range(float(vale[0]) - 1100.0, float(vale[2]) + 1100.0)
		var z := rng.randf_range(float(vale[1]) - 1100.0, float(vale[3]) + 1100.0)
		if absf(x) > Terreno.MEIO_INTERNO - 60.0 or absf(z) > Terreno.MEIO_INTERNO - 60.0:
			continue
		if bosque.get_noise_2d(x, z) < rng.randf_range(-0.25, 0.3):
			continue
		var h := _terreno.altura_em(x, z)
		if h > 330.0 or altura(x, z) > -INF:
			continue
		var esc := rng.randf_range(0.7, 1.5)
		if not _livre(Vector2(x, z), 17.0 * esc) or not _plano(x, z, 7.0):
			continue
		var tinta := Color(1, 1, 1) * rng.randf_range(0.85, 1.12)
		lista.append([Vector3(x, h - 0.4, z), esc, rng.randf() * TAU, tinta])
	Vegetacao.plantar(self, Vegetacao.Tipo.PINHEIRO, lista, 420.0, 2200.0, true)
	# Araucárias gigantes cobertas de gelo (pedido do dono: os pinheiros sozinhos não embelezavam a paisagem):
	# 50 a 95 m, em bosques próprios e soltas pelo vale, sempre longe das estradas e dos voos (são altas)
	var meta_a := int(_cfg.get("araucarias", 0))
	var bosque_a := FastNoiseLite.new()
	bosque_a.seed = 171
	bosque_a.frequency = 1.0 / 520.0
	var lista_a := []
	tent = 0
	# Fora dos obstáculos de voo de TODAS as etapas (muralhas, agulhas e o miolo das cidadelas): a árvore é
	# plantada uma vez só e ficaria atravessada numa muralha que só existe em outra etapa
	var muros: Array = []     # [a, b]
	var agulhas: Array = []   # [centro, raio]
	var alvos_e: Array = []
	for ek in _cfg.get("etapas", {}):
		var ee: Dictionary = _cfg.etapas[ek]
		for mm_c: Dictionary in ee.get("muralhas", []):
			muros.append([Vector2(float(mm_c.a[0]), float(mm_c.a[1])), Vector2(float(mm_c.b[0]), float(mm_c.b[1]))])
		for pc in ee.get("pilares", []):
			agulhas.append([Vector2(float(pc[0]), float(pc[1])), float(pc[2])])
	for et in Config.valor("etapas", []):
		var de: Array = (et as Dictionary).get("deslocamento", [0, 0])
		alvos_e.append(Vector2(float(de[0]), float(de[1])))
	while lista_a.size() < meta_a and tent < meta_a * 30:
		tent += 1
		var x := rng.randf_range(float(vale[0]) - 700.0, float(vale[2]) + 700.0)
		var z := rng.randf_range(float(vale[1]) - 700.0, float(vale[3]) + 700.0)
		if absf(x) > Terreno.MEIO_INTERNO - 60.0 or absf(z) > Terreno.MEIO_INTERNO - 60.0:
			continue
		if bosque_a.get_noise_2d(x, z) < rng.randf_range(-0.35, 0.25):
			continue
		var h := _terreno.altura_em(x, z)
		if h > 300.0 or altura(x, z) > -INF:
			continue
		var esc := rng.randf_range(1.15, 1.9)
		# Folga = a copa inteira (até 17 m x escala) e mais um pouco: nenhum galho por cima da pista
		if not _livre(Vector2(x, z), 54.0 * esc, 19.0 * esc + 6.0) or not _plano(x, z, 9.0):
			continue
		var q2 := Vector2(x, z)
		var barrado := false
		for al: Vector2 in alvos_e:
			if q2.distance_to(al) < 430.0:
				barrado = true
		for mu: Array in muros:
			if not barrado and Geometry2D.get_closest_point_to_segment(q2, mu[0], mu[1]).distance_to(q2) < 46.0:
				barrado = true
		for ag: Array in agulhas:
			if not barrado and q2.distance_to(ag[0]) < float(ag[1]) + 36.0:
				barrado = true
		if barrado:
			continue
		lista_a.append([Vector3(x, h - 0.6, z), esc, rng.randf() * TAU, Color(1, 1, 1) * rng.randf_range(0.9, 1.1)])
	Vegetacao.plantar(self, Vegetacao.Tipo.ARAUCARIA_GELO, lista_a, 600.0, 3600.0, true)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[GELO] araucárias: ", lista_a.size(), " tentativas ", tent)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[GELO] pinheiros: ", lista.size(), " tentativas ", tent)


func _plano(x: float, z: float, limite: float) -> bool:
	var dx := _terreno.altura_em(x + 6.0, z) - _terreno.altura_em(x - 6.0, z)
	var dz := _terreno.altura_em(x, z + 6.0) - _terreno.altura_em(x, z - 6.0)
	return absf(dx) + absf(dz) <= limite


## Bancos de neblina fria baixa sobre o vale e o lago.
func _montar_bruma() -> void:
	if not bool(Config.valor("grafico.bruma", true)):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	var vale: Array = Config.valor("mapa.subida.vale", [-2250, -1900, 1300, 1100])
	var xf: Array[Transform3D] = []
	var sementes := PackedFloat32Array()
	for k in 170:
		var x := rng.randf_range(float(vale[0]) - 1500.0, float(vale[2]) + 1500.0)
		var z := rng.randf_range(float(vale[1]) - 1500.0, float(vale[3]) + 1500.0)
		var h := _terreno.altura_em(x, z)
		if h > 120.0:
			continue
		var esc := rng.randf_range(120.0, 280.0)
		xf.append(Transform3D(Basis.from_scale(Vector3.ONE * esc), Vector3(x, h + rng.randf_range(14.0, 38.0), z)))
		sementes.append(rng.randf() * 10.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bruma.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.02, 4, 97))
	mat.set_shader_parameter("cor_luz", Color(0.95, 0.97, 1.0))
	mat.set_shader_parameter("cor_sombra", Color(0.62, 0.72, 0.88))
	mat.set_shader_parameter("opacidade", 0.4)
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, Color(sementes[i], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-6000, -50, -6000), Vector3(12000, 600, 12000))
	add_child(mmi)


# ------------------------------------------------------------------ neve e vento

## Camada de partículas que acompanha a câmera. `macia` = bola de neve soprada (textura de nuvem);
## senão, floco (ponto redondo de borda suave). Nunca esticada: nada de risco.
func _camada(pai: Node3D, qtd: int, vida: float, caixa: Vector3, dir: Vector3, vel: Vector2, tam: Vector2, cor: Color, macia: bool, turbulencia := 0.0, gravidade := Vector3.ZERO) -> GPUParticles3D:
	var part := GPUParticles3D.new()
	part.amount = qtd
	part.lifetime = vida
	part.preprocess = vida
	part.visibility_aabb = AABB(Vector3(-280, -100, -280), Vector3(560, 200, 560))
	part.local_coords = false
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = caixa
	proc.direction = dir
	proc.spread = 12.0
	proc.initial_velocity_min = vel.x
	proc.initial_velocity_max = vel.y
	proc.gravity = gravidade
	proc.scale_min = tam.x
	proc.scale_max = tam.y
	proc.angle_min = 0.0
	proc.angle_max = 360.0
	if macia:
		proc.angular_velocity_min = -14.0
		proc.angular_velocity_max = 14.0
	if turbulencia > 0.0:
		proc.turbulence_enabled = true
		proc.turbulence_noise_strength = turbulencia
		proc.turbulence_noise_scale = 3.5
		proc.turbulence_noise_speed_random = 0.6
		proc.turbulence_influence_min = 0.06
		proc.turbulence_influence_max = 0.22
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 0.0))
	curva.add_point(Vector2(0.25, 1.0))
	curva.add_point(Vector2(0.75, 1.0))
	curva.add_point(Vector2(1.0, 0.0))
	var tc := CurveTexture.new()
	tc.curve = curva
	proc.alpha_curve = tc
	part.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = cor
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.albedo_texture = Selva._textura_nuvem() if macia else _textura_floco()
	if macia:
		mat.proximity_fade_enabled = true
		mat.proximity_fade_distance = 8.0
	quad.material = mat
	part.draw_pass_1 = quad
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(part)
	return part


## Neve fina caindo o tempo todo em volta da câmera (flocos pequenos, em redemoinho leve).
func _montar_neve_ambiente() -> void:
	_neve_no = Node3D.new()
	_neve_no.name = "Neve"
	_neve_no.top_level = true
	add_child(_neve_no)
	_camada(_neve_no, 900, 5.0, Vector3(45, 22, 45), Vector3(0.15, -1.0, 0.05), Vector2(2.2, 4.0), Vector2(0.05, 0.11), Color(1, 1, 1, 0.85), false, 1.6)


## Nevasca da etapa com vento: véus grandes de neve soprada rolando com o vento, bolas menores
## perto e muitos flocos em redemoinho. A velocidade de tudo acompanha as rajadas (_physics_process).
func _vento_visual() -> void:
	if _vento_no:
		_vento_no.queue_free()
		_vento_no = null
	if _vento_cfg.is_empty():
		return
	_vento_no = Node3D.new()
	_vento_no.name = "Nevasca"
	_vento_no.top_level = true
	add_child(_vento_no)
	var ang := deg_to_rad(float(_vento_cfg.get("direcao", 90)))
	var dir := Vector3(sin(ang), -0.05, -cos(ang))
	var f := clampf((float(_vento_cfg.get("forca", 0.0)) + float(_vento_cfg.get("rajada", 0.0))) / 8.0, 0.2, 1.0)
	_camada(_vento_no, int(60 + 60 * f), 7.0, Vector3(190, 40, 190), dir, Vector2(14.0, 24.0), Vector2(26.0, 62.0), Color(0.93, 0.96, 1.0, 0.1 + 0.1 * f), true)
	_camada(_vento_no, int(40 + 50 * f), 4.5, Vector3(70, 16, 70), dir, Vector2(18.0, 28.0), Vector2(8.0, 18.0), Color(0.95, 0.97, 1.0, 0.12 + 0.12 * f), true)
	_camada(_vento_no, int(700 + 900 * f), 2.4, Vector3(42, 16, 42), dir, Vector2(16.0, 30.0), Vector2(0.05, 0.12), Color(1, 1, 1, 0.9), false, 4.0, Vector3(0, -1.5, 0))


# ------------------------------------------------------------------ etapas

## Troca o que muda por etapa: agulhas e muralhas no caminho do voo, os miolos das outras
## fortalezas e o vento (força do voo + nevasca).
func preparar_etapa(indice: int, cfg_etapa: Dictionary) -> void:
	for f in _etapa_no.get_children():
		f.queue_free()
	_pilares_etapa.clear()
	var e: Dictionary = _cfg.get("etapas", {}).get(str(indice + 1), {})
	for c in e.get("pilares", []):
		_pilares_etapa.append([Vector2(float(c[0]), float(c[1])), float(c[2]), float(c[3])])
	_montar_pilares(_etapa_no, _pilares_etapa)
	for pt in e.get("pontes", []):
		_montar_ponte(_etapa_no, Vector3(float(pt[0]), float(pt[4]), float(pt[1])), Vector3(float(pt[2]), float(pt[4]), float(pt[3])), float(pt[5]) if pt.size() > 5 else 20.0)
	var muralhas: Array = e.get("muralhas", [])
	if not muralhas.is_empty():
		var corpo := _corpo(_etapa_no)
		for m: Dictionary in muralhas:
			_montar_muralha(_etapa_no, m, corpo)
	_miolos(_etapa_no, indice)
	_vento_cfg = cfg_etapa.get("vento", {})
	_vento_visual()
	if _vento_cfg.is_empty():
		Veiculo.vento = Vector3.ZERO
		vento_visual = 0.0
	else:
		var ang := deg_to_rad(float(_vento_cfg.get("direcao", 90)))
		vento_dir = Vector3(sin(ang), 0.0, -cos(ang))
	(_terreno._mat_terreno as ShaderMaterial).set_shader_parameter("dir_vento", Vector2(vento_dir.x, vento_dir.z))
	# Biruta ao lado do alvo (num mastro do chão), fora do caminho de quem chega
	var d: Array = cfg_etapa.get("deslocamento", [0, 0])
	var lado := vento_dir.cross(Vector3.UP).normalized() if not _vento_cfg.is_empty() else Vector3.RIGHT
	var pb := Vector3(float(d[0]), 0.0, float(d[1])) + lado * 70.0
	pb.y = _terreno.altura_em(pb.x, pb.z) - 0.5
	criar_biruta(_etapa_no, pb, float(cfg_etapa.get("altura", 60)) + 16.0)


func _physics_process(delta: float) -> void:
	_t += delta
	var cam := get_viewport().get_camera_3d()
	if cam:
		if _neve_no:
			_neve_no.global_position = cam.global_position
		if _vento_no:
			_vento_no.global_position = cam.global_position
	if _vento_cfg.is_empty():
		return
	var periodo := maxf(float(_vento_cfg.get("periodo", 6.0)), 0.5)
	var forca := float(_vento_cfg.get("forca", 0.0))
	var rajada_max := float(_vento_cfg.get("rajada", 0.0))
	var onda := (0.5 + 0.5 * sin(_t * TAU / periodo)) * (0.7 + 0.3 * sin(_t * 2.3))
	Veiculo.vento = vento_dir * (forca + rajada_max * onda)
	vento_visual = clampf((forca + rajada_max * onda) / 7.0, 0.0, 1.0)
	if _vento_no:
		var ritmo := clampf((forca + rajada_max * onda) / maxf(forca + rajada_max, 0.1), 0.35, 1.0)
		for p in _vento_no.get_children():
			(p as GPUParticles3D).speed_scale = 0.55 + 0.75 * ritmo


func _process(_delta: float) -> void:
	_mover_cabines()
	_mover_dirigiveis()
	for b: Array in _baloes:
		var no: Node3D = b[0]
		var base: Vector3 = b[1]
		no.position = base + Vector3(sin(_t * 0.05 + float(b[2])) * 30.0, sin(_t * 0.31 + float(b[2])) * 4.0, cos(_t * 0.04 + float(b[2])) * 30.0)
	# Bandeiras e birutas viram para onde o vento vai e enchem com a força dele
	material_bandeira().set_shader_parameter("forca", 0.25 + vento_visual)
	var k := 0
	while k < _birutas.size():
		var par: Array = _birutas[k]
		if not is_instance_valid(par[0]):
			_birutas.remove_at(k)
			continue
		var no: Node3D = par[0]
		if par[1] == null:
			# Bandeira: o pano sai do mastro (+X local) na direção do vento
			no.basis = Basis(vento_dir, Vector3.UP, vento_dir.cross(Vector3.UP).normalized())
		else:
			no.basis = Basis.looking_at(-vento_dir, Vector3.UP)
			(par[1] as ShaderMaterial).set_shader_parameter("forca", vento_visual * 1.3)
		k += 1


func _exit_tree() -> void:
	Veiculo.vento = Vector3.ZERO
	vento_visual = 0.0
	_birutas.clear()
