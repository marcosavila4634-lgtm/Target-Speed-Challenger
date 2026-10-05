class_name Selva
extends Node3D
## Serpent's Climb (mapa.subida.selva): templos astecas/maias no meio da selva fechada.
## - pirâmides em talude-tablero (talude inclinado + painel vertical com friso), escadaria com
##   balaustradas que terminam em cabeças de serpente (como em Chichén Itzá) e templo no topo;
## - rio e lago cavados no terreno (cavar_rio) e a cachoeira que despenca do paredão norte no lago;
## - jogo de bola, estelas, altares, cabeças de jaguar e colunas da serpente (as da etapa são mortais);
## - a serpente gigante rastejando pela mata (SerpenteGigante, só enfeite, nas etapas da config);
## - mata fechada (sumaúmas gigantes com cipós, árvores de copa, palmeiras, bananeiras, samambaias),
##   bandos de araras, tucanos e urubus, garças no rio e borboletas (Fauna).
## Tudo que é pedra é mortal: entra em altura() (somada em Terreno.altura_em) e tem colisão no grupo
## "mortal".

var penhasco := 170.0
var _terreno: Terreno
var _cfg: Dictionary = {}
var _chao := 6.5
var _piramides: Array = []        # {c: Vector2, mb, mt, topo, templo: bool} + perfil (PiramideSelva.perfil)
var _colunas_fixas: Array = []    # [centro Vector2, raio, altura]
var _colunas_etapa: Array = []
var _rio := PackedVector2Array()
var _rio_meia := 30.0
var _lagos: Array = []            # [centro Vector2, raio]
var _etapa_no: Node3D
var _vento_cfg: Dictionary = {}
var _t := 0.0
var _estradas: Array = []         # [PackedVector3Array] pontos de controle de todas as estradas (todas as etapas)
var _grade_estrada := {}          # Vector2i -> [[a, b], ...] segmentos
const CEL := 40.0
var _serpente_cfg: Dictionary = {}
var _trilha_serpente := PackedVector2Array()   # por onde a serpente gigante rasteja (SerpenteGigante.tracar)
var _grade_trilha := {}           # Vector2i (células de CEL_TRILHA m) em cima da trilha: sem mata
const CEL_TRILHA := 4.0

static var _mats := {}


# ------------------------------------------------------------------ materiais (compartilhados)

static func material_pedra(modo: int, fiada := 1.2) -> ShaderMaterial:
	var chave := "%d_%.2f" % [modo, fiada]
	if _mats.has(chave):
		return _mats[chave]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pedra_selva.gdshader")
	m.set_shader_parameter("modo", modo)
	m.set_shader_parameter("fiada", fiada)
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 211))
	_mats[chave] = m
	return m


static func material_ouro() -> StandardMaterial3D:
	if not _mats.has("ouro"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.76, 0.32)
		m.metallic = 1.0
		m.roughness = 0.28
		m.emission_enabled = true
		m.emission = Color(1.0, 0.7, 0.3)
		m.emission_energy_multiplier = 0.12
		_mats["ouro"] = m
	return _mats["ouro"]


static func material_jade() -> StandardMaterial3D:
	if not _mats.has("jade"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.62, 0.42)
		m.metallic = 0.1
		m.roughness = 0.2
		m.rim_enabled = true
		m.rim = 0.3
		m.emission_enabled = true
		m.emission = Color(0.1, 0.7, 0.45)
		m.emission_energy_multiplier = 0.25
		_mats["jade"] = m
	return _mats["jade"]


static func _caixa(pai: Node3D, tam: Vector3, pos: Vector3, mat: Material, giro := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	mi.mesh = b
	mi.material_override = mat
	mi.transform = Transform3D(giro, pos)
	pai.add_child(mi)
	return mi


static func _cone(pai: Node3D, r0: float, r1: float, alt: float, xf: Transform3D, mat: Material, lados := 8) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r0
	c.height = alt
	c.radial_segments = lados
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.transform = xf
	pai.add_child(mi)


## Cabeça de serpente emplumada esculpida (olhando para -Z), com `escala` m de comprimento:
## focinho com a voluta do nariz, boca aberta com presas, olhos de jade e o colar de penas.
static func cabeca_serpente(escala: float) -> Node3D:
	var raiz := Node3D.new()
	var s := escala
	var pedra := material_pedra(2, 0.5 * s)
	var osso := StandardMaterial3D.new()
	osso.albedo_color = Color(0.9, 0.86, 0.76)
	osso.roughness = 0.5
	var vermelho := StandardMaterial3D.new()
	vermelho.albedo_color = Color(0.55, 0.1, 0.07)
	vermelho.roughness = 0.6
	_caixa(raiz, Vector3(0.8, 0.45, 0.85) * s, Vector3(0, 0.38, -0.05) * s, pedra)                 # crânio
	_caixa(raiz, Vector3(0.72, 0.22, 0.55) * s, Vector3(0, 0.3, -0.62) * s, pedra)                 # maxilar
	_caixa(raiz, Vector3(0.7, 0.16, 0.6) * s, Vector3(0, -0.02, -0.5) * s, pedra, Basis(Vector3.RIGHT, -0.25))  # mandíbula aberta
	_caixa(raiz, Vector3(0.5, 0.06, 0.5) * s, Vector3(0, 0.12, -0.55) * s, vermelho)               # língua/boca
	_caixa(raiz, Vector3(0.35, 0.3, 0.22) * s, Vector3(0, 0.62, -0.78) * s, pedra, Basis(Vector3.RIGHT, 0.5))  # voluta do nariz
	for lado: float in [-1.0, 1.0]:
		var olho := MeshInstance3D.new()
		var e := SphereMesh.new()
		e.radius = 0.09 * s
		e.height = 0.18 * s
		olho.mesh = e
		olho.material_override = material_jade()
		olho.position = Vector3(lado * 0.36, 0.55, -0.32) * s
		raiz.add_child(olho)
		_caixa(raiz, Vector3(0.2, 0.08, 0.32) * s, Vector3(lado * 0.36, 0.66, -0.32) * s, pedra)   # sobrancelha
		_cone(raiz, 0.06 * s, 0.0, 0.32 * s, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(lado * 0.27, 0.06, -0.82) * s), osso)
	# Colar de penas (placas em leque atrás da cabeça)
	var n := 9
	for k in n:
		var a := lerpf(-1.4, 1.4, float(k) / (n - 1))
		var pena := _caixa(raiz, Vector3(0.22, 0.75, 0.08) * s, Vector3(sin(a) * 0.55, 0.35 + cos(a) * 0.5, 0.45) * s, pedra, Basis(Vector3.FORWARD, a))
		pena.material_override = material_jade() if k % 2 == 0 else pedra
	return raiz


## Cabeça de jaguar esculpida (olhando para -Z), `escala` m de largura: orelhas, focinho, presas e
## olhos de jade.
static func cabeca_jaguar(escala: float) -> Node3D:
	var raiz := Node3D.new()
	var s := escala
	var pedra := material_pedra(0, 0.25 * s)
	var osso := StandardMaterial3D.new()
	osso.albedo_color = Color(0.9, 0.86, 0.76)
	_caixa(raiz, Vector3(1.0, 0.8, 0.8) * s, Vector3(0, 0.4, 0) * s, pedra)
	_caixa(raiz, Vector3(0.55, 0.35, 0.35) * s, Vector3(0, 0.22, -0.5) * s, pedra)
	_caixa(raiz, Vector3(0.24, 0.14, 0.12) * s, Vector3(0, 0.4, -0.66) * s, material_pedra(1, 0.3))
	for lado: float in [-1.0, 1.0]:
		_caixa(raiz, Vector3(0.24, 0.26, 0.12) * s, Vector3(lado * 0.36, 0.9, 0.05) * s, pedra, Basis(Vector3.FORWARD, lado * 0.3))
		var olho := MeshInstance3D.new()
		var e := SphereMesh.new()
		e.radius = 0.08 * s
		e.height = 0.16 * s
		olho.mesh = e
		olho.material_override = material_jade()
		olho.position = Vector3(lado * 0.24, 0.58, -0.4) * s
		raiz.add_child(olho)
		_cone(raiz, 0.045 * s, 0.0, 0.2 * s, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(lado * 0.13, 0.0, -0.64) * s), osso)
	return raiz


# ------------------------------------------------------------------ preparação (antes do terreno)

func preparar(terreno: Terreno) -> void:
	_terreno = terreno
	_cfg = Config.valor("mapa.subida.selva", {})
	penhasco = float(_cfg.get("penhasco", 170.0))
	for p in _cfg.get("piramides", []):
		_piramides.append({"c": Vector2(float(p[0]), float(p[1])), "mb": float(p[2]), "mt": float(p[3]), "topo": float(p[4]),
			"niveis": int(p[5]) if p.size() > 5 else 6, "escadas": str(p[6]) if p.size() > 6 else "S", "templo": bool(p[7]) if p.size() > 7 else false})
		PiramideSelva.perfil(_piramides[_piramides.size() - 1], _chao)
	for c in _cfg.get("colunas", []):
		_colunas_fixas.append([Vector2(float(c[0]), float(c[1])), float(c[2]), float(c[3])])
	var rio: Dictionary = _cfg.get("rio", {})
	for q in rio.get("pontos", []):
		_rio.append(Vector2(float(q[0]), float(q[1])))
	_rio_meia = float(rio.get("meia_largura", 30))
	for l in _cfg.get("lagos", []):
		_lagos.append([Vector2(float(l[0]), float(l[1])), float(l[2])])
	# Estradas de todas as etapas (a mata não pode atravessar nenhuma)
	var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
	for k in percursos:
		var trechos: Dictionary = (percursos[k] as Dictionary).get("trechos", {})
		for nome in ["A", "B", "C"]:
			var pts := PackedVector3Array()
			for p in trechos.get(nome, []):
				pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			if pts.size() > 1:
				_estradas.append(pts)
	for pts: PackedVector3Array in _estradas:
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var r := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(30.0)
			for cx in range(floori(r.position.x / CEL), floori(r.end.x / CEL) + 1):
				for cz in range(floori(r.position.y / CEL), floori(r.end.y / CEL) + 1):
					var chave := Vector2i(cx, cz)
					if not _grade_estrada.has(chave):
						_grade_estrada[chave] = []
					_grade_estrada[chave].append([a, b])
	# Trilha da serpente gigante: a mata não nasce em cima (o corpo atravessaria os troncos)
	_serpente_cfg = _cfg.get("serpente_gigante", {})
	_trilha_serpente = SerpenteGigante.tracar(_serpente_cfg, self)
	var folga := float(_serpente_cfg.get("grossura", 5.0)) * 0.5 + 5.0
	var nc := ceili(folga / CEL_TRILHA)
	for q in _trilha_serpente:
		var c := Vector2i(floori(q.x / CEL_TRILHA), floori(q.y / CEL_TRILHA))
		for dx in range(-nc, nc + 1):
			for dz in range(-nc, nc + 1):
				if (Vector2(c.x + dx + 0.5, c.y + dz + 0.5) * CEL_TRILHA).distance_to(q) < folga:
					_grade_trilha[c + Vector2i(dx, dz)] = true


func _na_trilha(p: Vector2) -> bool:
	return _grade_trilha.has(Vector2i(floori(p.x / CEL_TRILHA), floori(p.y / CEL_TRILHA)))


## Distância (no chão) até a estrada mais próxima de qualquer etapa; INF a mais de ~30 m.
func dist_estrada(p: Vector2) -> float:
	var melhor := INF
	for seg: Array in _grade_estrada.get(Vector2i(floori(p.x / CEL), floori(p.y / CEL)), []):
		var a := Vector2(seg[0].x, seg[0].z)
		var ab := Vector2(seg[1].x, seg[1].z) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		melhor = minf(melhor, p.distance_to(a + ab * t))
	return melhor


# ------------------------------------------------------------------ alturas (mortais)

## Altura das construções de pedra em (x, z): pirâmides e colunas. -INF fora delas.
func altura(x: float, z: float) -> float:
	var h := -INF
	for p: Dictionary in _piramides:
		var c: Vector2 = p.c
		var dx := absf(x - c.x)
		var dz := absf(z - c.y)
		var ch := maxf(dx, dz)
		if ch < p.mb:
			h = maxf(h, PiramideSelva.altura(p, ch))
	for lista: Array in [_colunas_fixas, _colunas_etapa]:
		for col: Array in lista:
			var d := Vector2(x, z).distance_to(col[0])
			if d < col[1]:
				h = maxf(h, _chao + float(col[2]))
	return h


# ------------------------------------------------------------------ rio e lago

func _dist_rio(p: Vector2) -> float:
	var melhor := INF
	for i in range(1, _rio.size()):
		var a := _rio[i - 1]
		var ab := _rio[i] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		melhor = minf(melhor, p.distance_to(a + ab * t))
	return melhor


## Leito do rio e do lago: fundo a -6 m, margens de barro subindo até o chão da mata.
func cavar_rio(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	var d := INF
	if _rio.size() > 1:
		d = _dist_rio(p) - _rio_meia
	for l: Array in _lagos:
		d = minf(d, p.distance_to(l[0]) - float(l[1]))
	if d > 120.0:
		return h
	h = minf(h, lerpf(-6.0, h, smoothstep(-_rio_meia * 0.6, 3.0, d)))
	h = minf(h, lerpf(5.0, h, smoothstep(2.0, 90.0, d)))
	return h


## Máscara (R = 1 na água, cai a 0 a 60 m da margem) para o shader do chão: barro e capim na margem.
func textura_margem(meio: float) -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_R8)
	var passo := meio * 2.0 / n
	for iz in n:
		for ix in n:
			var p := Vector2(-meio + (ix + 0.5) * passo, -meio + (iz + 0.5) * passo)
			var d := INF
			if _rio.size() > 1:
				d = _dist_rio(p) - _rio_meia
			for l: Array in _lagos:
				d = minf(d, p.distance_to(l[0]) - float(l[1]))
			img.set_pixel(ix, iz, Color(clampf(1.0 - d / 60.0, 0.0, 1.0), 0.0, 0.0))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ montagem

func montar() -> void:
	for p: Dictionary in _piramides:
		_montar_piramide(p)
	var fixas := Node3D.new()
	fixas.name = "ColunasFixas"
	add_child(fixas)
	_montar_colunas(fixas, _colunas_fixas)
	_montar_cachoeira()
	_montar_ruinas()
	_montar_vegetacao()
	_montar_bruma()
	var fauna := Fauna.new()
	fauna.name = "Fauna"
	add_child(fauna)
	fauna.montar(self, _terreno, _cfg.get("fauna", {}))
	_etapa_no = Node3D.new()
	_etapa_no.name = "Etapa"
	add_child(_etapa_no)


func _corpo_mortal(pai: Node = null) -> StaticBody3D:
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	corpo.add_to_group("mortal")
	(pai if pai else self).add_child(corpo)
	return corpo


## Pirâmide igual à arte do dono (PiramideSelva): a pintura é a pele de um relevo nas quatro faces.
func _montar_piramide(p: Dictionary) -> void:
	var no := Node3D.new()
	no.name = "Piramide"
	add_child(no)
	PiramideSelva.montar(no, _corpo_mortal(no), p)


## Colunas da serpente: fuste cilíndrico entalhado com escamas, anéis de jade e a cabeça no alto.
func _montar_colunas(pai: Node3D, lista: Array) -> void:
	if lista.is_empty():
		return
	var corpo := _corpo_mortal(pai)
	for col: Array in lista:
		var c: Vector2 = col[0]
		var r: float = col[1]
		var alto: float = col[2]
		var fuste := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = r * 0.8
		cil.bottom_radius = r * 0.92
		cil.height = alto
		cil.radial_segments = 32
		fuste.mesh = cil
		fuste.material_override = material_pedra(2, r * 0.12)
		fuste.position = Vector3(c.x, _chao + alto * 0.5, c.y)
		pai.add_child(fuste)
		for k in 4:
			var anel := MeshInstance3D.new()
			var ca := CylinderMesh.new()
			var ra := lerpf(r * 0.92, r * 0.8, (k + 0.5) / 4.0) + 0.6
			ca.top_radius = ra
			ca.bottom_radius = ra
			ca.height = 2.4
			ca.radial_segments = 32
			anel.mesh = ca
			anel.material_override = material_jade() if k % 2 == 0 else material_ouro()
			anel.position = Vector3(c.x, _chao + alto * (k + 0.5) / 4.0, c.y)
			pai.add_child(anel)
		_caixa(pai, Vector3(r * 2.4, 4.0, r * 2.4), Vector3(c.x, _chao + 1.0, c.y), material_pedra(0, 1.0))
		var cab := cabeca_serpente(r * 2.2)
		cab.transform = Transform3D(Basis(Vector3.UP, Terreno._hash2(int(c.x), int(c.y)) * TAU), Vector3(c.x, _chao + alto - 0.5, c.y))
		pai.add_child(cab)
		var cs := CollisionShape3D.new()
		var forma := CylinderShape3D.new()
		forma.radius = r * 0.92
		forma.height = alto + 4.0
		cs.shape = forma
		cs.position = Vector3(c.x, _chao + alto * 0.5, c.y)
		corpo.add_child(cs)


# ------------------------------------------------------------------ cachoeira

## Cachoeira do paredão norte: lâmina d'água (shader com fios descendo) do alto do paredão até o
## lago, espuma e névoa na base, e o rio de cima chegando pelo canal.
func _montar_cachoeira() -> void:
	var cfg: Dictionary = _cfg.get("cachoeira", {})
	if cfg.is_empty():
		return
	var x := float(cfg.get("x", -700))
	var z_pe := float(cfg.get("z_pe", -1735))
	var z_topo := float(cfg.get("z_topo", -1800))
	var larg := float(cfg.get("largura", 60))
	var y_topo := _terreno.altura_em(x, z_topo - 10.0)
	var nivel := float(Config.valor("mapa.nivel_agua", 4))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		# Perfil: sai na horizontal do lábio e cai em parábola, afastando do paredão
		var p0 := _ponto_queda(x, z_topo, z_pe, y_topo, nivel, t0)
		var p1 := _ponto_queda(x, z_topo, z_pe, y_topo, nivel, t1)
		for s in 6:
			var u0 := lerpf(-0.5, 0.5, float(s) / 6.0)
			var u1 := lerpf(-0.5, 0.5, float(s + 1) / 6.0)
			var w0 := larg * (1.0 + t0 * 0.25)
			var w1 := larg * (1.0 + t1 * 0.25)
			var q := [p0 + Vector3(u0 * w0, 0, 0), p0 + Vector3(u1 * w0, 0, 0), p1 + Vector3(u1 * w1, 0, 0), p1 + Vector3(u0 * w1, 0, 0)]
			var uv := [Vector2(u0 + 0.5, t0), Vector2(u1 + 0.5, t0), Vector2(u1 + 0.5, t1), Vector2(u0 + 0.5, t1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(0, 0.2, 1).normalized())
				st.set_uv(uv[idx])
				st.add_vertex(q[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cachoeira.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.04, 3, 333))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Névoa e espuma na base
	var base := Vector3(x, nivel + 2.0, z_pe + 12.0)
	var part := GPUParticles3D.new()
	part.amount = 260
	part.lifetime = 5.0
	part.preprocess = 4.0
	part.visibility_aabb = AABB(Vector3(-120, -10, -120), Vector3(240, 140, 240))
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(larg * 0.6, 2.0, 8.0)
	proc.direction = Vector3(0, 1, 0.6)
	proc.spread = 35.0
	proc.initial_velocity_min = 4.0
	proc.initial_velocity_max = 10.0
	proc.gravity = Vector3(0, 0.4, 0)
	proc.scale_min = 8.0
	proc.scale_max = 18.0
	proc.color = Color(1, 1, 1, 0.35)
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.2))
	curva.add_point(Vector2(0.4, 1.0))
	curva.add_point(Vector2(1, 0.0))
	var tc := CurveTexture.new()
	tc.curve = curva
	proc.alpha_curve = tc
	part.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mq := StandardMaterial3D.new()
	mq.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mq.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mq.albedo_color = Color(0.92, 0.96, 1.0, 0.22)
	mq.albedo_texture = _textura_nuvem()
	mq.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mq.vertex_color_use_as_albedo = true
	quad.material = mq
	part.draw_pass_1 = quad
	part.position = base
	add_child(part)
	# Arco de espuma branca no lago
	var espuma := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = larg * 0.75
	disco.bottom_radius = larg * 0.75
	disco.height = 0.2
	espuma.mesh = disco
	var me := ShaderMaterial.new()
	me.shader = load("res://shaders/espuma.gdshader")
	me.set_shader_parameter("ruido", Terreno._textura_ruido(0.06, 3, 334))
	espuma.material_override = me
	espuma.position = Vector3(x, nivel + 0.12, z_pe + larg * 0.4)
	espuma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(espuma)


func _ponto_queda(x: float, z_topo: float, z_pe: float, y_topo: float, nivel: float, t: float) -> Vector3:
	var y := lerpf(y_topo + 0.5, nivel - 0.5, t)
	var avanco := (z_pe - z_topo) * (1.0 - (1.0 - t) * (1.0 - t)) + 6.0 * t
	return Vector3(x, y, z_topo + avanco + 2.0)


static func _textura_nuvem() -> ImageTexture:
	if _mats.has("nuvem"):
		return _mats["nuvem"]
	# Bola de fumaça/poeira: borda macia e "couve-flor" (ruído fractal), sem contorno de disco
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var ruido := FastNoiseLite.new()
	ruido.seed = 5
	ruido.frequency = 0.045
	ruido.fractal_octaves = 4
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
			var r := ruido.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(1.0 - d * (0.8 + 0.5 * (1.0 - r)), 0.0, 1.0)
			a = smoothstep(0.0, 1.0, a) * (0.55 + 0.45 * r)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mats["nuvem"] = tex
	return tex


# ------------------------------------------------------------------ ruínas e esculturas

## Jogo de bola (dois muros inclinados com os anéis), estelas, altares e cabeças de jaguar
## espalhados pela mata (sem colisão: longe da estrada e do voo).
func _montar_ruinas() -> void:
	var pedra := material_pedra(0, 0.9)
	var friso := material_pedra(2, 0.8)
	for jb in _cfg.get("jogo_de_bola", []):
		var c := Vector3(float(jb[0]), 0.0, float(jb[1]))
		c.y = _terreno.altura_base(c.x, c.z)
		var giro := Basis(Vector3.UP, deg_to_rad(float(jb[2])))
		for s: float in [-1.0, 1.0]:
			_caixa(self, Vector3(14.0, 5.0, 90.0), c + giro * Vector3(s * 22.0, 2.0, 0), pedra, giro)
			_caixa(self, Vector3(6.0, 9.0, 90.0), c + giro * Vector3(s * 28.0, 4.0, 0), friso, giro)
			var anel := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.9
			tor.outer_radius = 1.6
			anel.mesh = tor
			anel.material_override = friso
			# Engastado na face do muro alto (a 15,4 m ficava solto no ar, acima da banqueta)
			anel.transform = Transform3D(giro * Basis(Vector3.FORWARD, PI * 0.5), c + giro * Vector3(s * 24.3, 6.4, 0))
			add_child(anel)
		_caixa(self, Vector3(30.0, 0.4, 110.0), c + Vector3.UP * 0.1, material_pedra(1, 2.0), giro)
	var estelas: Array[Transform3D] = []
	for e in _cfg.get("estelas", []):
		var q := Vector3(float(e[0]), 0.0, float(e[1]))
		q.y = _terreno.altura_base(q.x, q.z)
		estelas.append(Transform3D(Basis(Vector3.UP, float(e[2])) * Basis.from_scale(Vector3(3.0, 9.0, 1.2)), q + Vector3.UP * 4.0))
	ComplexoLancamento.criar_multimesh(self, estelas, friso)
	for j in _cfg.get("jaguares", []):
		var cab := cabeca_jaguar(float(j[3]))
		var q := Vector3(float(j[0]), 0.0, float(j[1]))
		q.y = _terreno.altura_base(q.x, q.z) - 0.4
		cab.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(j[2]))), q)
		add_child(cab)


# ------------------------------------------------------------------ vegetação

## Mata fechada no vale e nos morros em volta, longe das construções, dos alvos, dos cercados e de
## onde alguma estrada passa baixa (a copa atravessaria o asfalto).
func _montar_vegetacao() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1)) + 77
	var nivel := float(Config.valor("mapa.nivel_agua", 4))
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var qtd: Dictionary = _cfg.get("vegetacao", {})
	var listas := {"gigante": [], "copa": [], "palmeira": [], "bananeira": [], "samambaia": []}
	var metas := {"gigante": int(qtd.get("gigantes", 1400)), "copa": int(qtd.get("copas", 9000)), "palmeira": int(qtd.get("palmeiras", 2600)),
		"bananeira": int(qtd.get("bananeiras", 9000)), "samambaia": int(qtd.get("samambaias", 12000))}
	var alturas := {"gigante": 46.0, "copa": 24.0, "palmeira": 16.0, "bananeira": 6.0, "samambaia": 2.5}
	var evitar := _areas_livres()
	var x0 := float(vale[0]) - 900.0
	var x1 := float(vale[2]) + 900.0
	var z0 := float(vale[1]) - 900.0
	var z1 := float(vale[3]) + 900.0
	var tentativas := 0
	var faltam := true
	while faltam and tentativas < 700000:
		tentativas += 1
		var x := rng.randf_range(x0, x1)
		var z := rng.randf_range(z0, z1)
		if absf(x) > Terreno.MEIO_INTERNO - 60.0 or absf(z) > Terreno.MEIO_INTERNO - 60.0:
			continue
		var p := Vector2(x, z)
		var h := _terreno.altura_base(x, z)
		if h < nivel + 1.2 or altura(x, z) > -INF:
			continue
		var dentro := x > float(vale[0]) and x < float(vale[2]) and z > float(vale[1]) and z < float(vale[3])
		var livre := true
		for e: Array in evitar:
			if p.distance_to(e[0]) < e[1]:
				livre = false
				break
		if not livre:
			continue
		var sorteio := rng.randf()
		var tipo := ""
		if not dentro:
			tipo = "copa" if sorteio < 0.75 else ("gigante" if sorteio < 0.85 else "palmeira")
		elif sorteio < 0.06:
			tipo = "gigante"
		elif sorteio < 0.36:
			tipo = "copa"
		elif sorteio < 0.46:
			tipo = "palmeira"
		elif sorteio < 0.72:
			tipo = "bananeira"
		else:
			tipo = "samambaia"
		var lista: Array = listas[tipo]
		if lista.size() >= int(metas[tipo]):
			faltam = false
			for k in listas:
				if (listas[k] as Array).size() < int(metas[k]):
					faltam = true
			continue
		var esc := rng.randf_range(0.75, 1.25)
		if tipo in ["gigante", "copa", "palmeira"] and not _plano(x, z, 9.0):
			continue
		if _estrada_perto(p, h, float(alturas[tipo]) * esc):
			continue
		var tinta := Color(1, 1, 1) * rng.randf_range(0.8, 1.12)
		tinta.g *= rng.randf_range(0.95, 1.1)
		var giro := rng.randf() * TAU
		if _na_trilha(p):
			continue   # depois dos sorteios: o resto da mata fica onde sempre esteve
		lista.append([Vector3(x, h - 0.3, z), esc, giro, tinta])
	# Sub-bosque: moitas densas (a copa em miniatura) cobrindo o chão do vale
	var moitas := []
	var n_moitas := int(qtd.get("moitas", 26000))
	tentativas = 0
	while moitas.size() < n_moitas and tentativas < n_moitas * 4:
		tentativas += 1
		var x := rng.randf_range(float(vale[0]), float(vale[2]))
		var z := rng.randf_range(float(vale[1]), float(vale[3]))
		var h := _terreno.altura_base(x, z)
		if h < nivel + 1.2 or h > 20.0 or altura(x, z) > -INF:
			continue
		var p := Vector2(x, z)
		var livre := true
		for e: Array in evitar:
			if p.distance_to(e[0]) < e[1]:
				livre = false
				break
		if not livre or _estrada_perto(p, h, 6.0):
			continue
		var moita := [Vector3(x, h - 0.6, z), rng.randf_range(0.18, 0.34), rng.randf() * TAU, Color(0.85, 1.0, 0.8) * rng.randf_range(0.75, 1.1)]
		if not _na_trilha(p):
			moitas.append(moita)
	var antes := get_child_count()
	Vegetacao.plantar(self, Vegetacao.Tipo.COPA, moitas, 220.0, 950.0, false)
	Vegetacao.plantar(self, Vegetacao.Tipo.SUMAUMA, listas.gigante, 500.0, 4200.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.COPA, listas.copa, 400.0, 3000.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.PALMEIRA_SELVA, listas.palmeira, 400.0, 2400.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.BANANEIRA, listas.bananeira, 250.0, 900.0, false)
	Vegetacao.plantar(self, Vegetacao.Tipo.SAMAMBAIA, listas.samambaia, 200.0, 500.0, false)
	for k in range(antes, get_child_count()):
		if get_child(k) is MultiMeshInstance3D:
			_mata.append(get_child(k))
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SELVA] vegetação: ", {"gigante": listas.gigante.size(), "copa": listas.copa.size(), "palmeira": listas.palmeira.size(), "bananeira": listas.bananeira.size(), "samambaia": listas.samambaia.size()}, " tentativas ", tentativas)


## Círculos [centro, raio] sem vegetação: cercados de todas as etapas, alvos e pés da cachoeira.
func _areas_livres() -> Array:
	var lista := []
	var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
	for k in percursos:
		var pc: Dictionary = percursos[k]
		for chave in ["largada", "plataforma"]:
			var r: Dictionary = pc.get(chave, {})
			if r.is_empty():
				continue
			var o: Array = r.get("origem", [0, 0, 0])
			var f: Array = r.get("frente", [0, -1])
			var comp := float(r.get("comprimento", 70))
			var c := Vector2(float(o[0]), float(o[2])) + Vector2(float(f[0]), float(f[1])) * comp * 0.5
			lista.append([c, maxf(comp, float(r.get("largura", 90))) * 0.75 + 15.0])
	for e in Config.valor("etapas", []):
		var d: Array = (e as Dictionary).get("deslocamento", [0, 0])
		lista.append([Vector2(float(d[0]), float(d[1])), 45.0])
	for jb in _cfg.get("jogo_de_bola", []):
		lista.append([Vector2(float(jb[0]), float(jb[1])), 70.0])
	return lista


## Alguma estrada (de qualquer etapa) passa a menos de 16 m daqui com o fundo abaixo do topo da planta?
func _estrada_perto(p: Vector2, chao: float, alto: float) -> bool:
	var lista: Array = _grade_estrada.get(Vector2i(floori(p.x / CEL), floori(p.y / CEL)), [])
	for seg: Array in lista:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if p.distance_to(a2 + ab * t) < 16.0 + alto * 0.25 and lerpf(a.y, b.y, t) - 4.0 < chao + alto:
			return true
	return false


func _plano(x: float, z: float, limite: float) -> bool:
	var dx := _terreno.altura_base(x + 6.0, z) - _terreno.altura_base(x - 6.0, z)
	var dz := _terreno.altura_base(x, z + 6.0) - _terreno.altura_base(x, z - 6.0)
	return absf(dx) + absf(dz) <= limite


## Bancos de neblina baixa sobre a mata e o lago (a selva "fuma" de umidade).
func _montar_bruma() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var xf: Array[Transform3D] = []
	var sementes := PackedFloat32Array()
	for k in 260:
		var x := rng.randf_range(float(vale[0]) - 1500.0, float(vale[2]) + 1500.0)
		var z := rng.randf_range(float(vale[1]) - 1500.0, float(vale[3]) + 1500.0)
		var h := _terreno.altura_em(x, z)
		var esc := rng.randf_range(110.0, 260.0)
		xf.append(Transform3D(Basis.from_scale(Vector3.ONE * esc), Vector3(x, h + rng.randf_range(18.0, 45.0), z)))
		sementes.append(rng.randf() * 10.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bruma.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.02, 4, 97))
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


# ------------------------------------------------------------------ etapas

## Troca o que muda por etapa: colunas da serpente no caminho do voo, a serpente gigante e o vento.
func preparar_etapa(indice: int, cfg_etapa: Dictionary) -> void:
	for f in _etapa_no.get_children():
		f.queue_free()
	_restaurar_mata()
	_colunas_etapa.clear()
	var e: Dictionary = _cfg.get("etapas", {}).get(str(indice + 1), {})
	for c in e.get("colunas", []):
		_colunas_etapa.append([Vector2(float(c[0]), float(c[1])), float(c[2]), float(c[3])])
	_montar_colunas(_etapa_no, _colunas_etapa)
	if (indice + 1) in Array(_serpente_cfg.get("etapas", [])).map(func(n): return int(n)) and not _trilha_serpente.is_empty():
		var serpente := SerpenteGigante.new()
		_etapa_no.add_child(serpente)
		serpente.montar(_trilha_serpente, _terreno, _serpente_cfg)
	_mata_da_etapa()
	_vento_cfg = cfg_etapa.get("vento", {})
	if _vento_cfg.is_empty():
		Veiculo.vento = Vector3.ZERO


## Mata em cima do chão que a etapa levantou (terra preenchida e montanhas de montanhas.etapas.N): a mata
## do vale é plantada uma vez só, no chão (Terreno.altura_base), e ali fica enterrada.
func _mata_da_etapa() -> void:
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501
	var listas := {"gigante": [], "copa": [], "palmeira": [], "moita": []}
	var metas := {"gigante": 900, "copa": 5200, "palmeira": 900, "moita": 9000}
	var tentativas := 0
	var faltam := true
	while faltam and tentativas < 160000:
		tentativas += 1
		var x := rng.randf_range(float(vale[0]), float(vale[2]))
		var z := rng.randf_range(float(vale[1]), float(vale[3]))
		if not _terreno.elevado_na_etapa(x, z):
			if tentativas > 4000 and listas.copa.is_empty():
				return   # etapa sem chão levantado
			continue
		var h := _terreno.altura_em(x, z)
		var sorteio := rng.randf()
		var tipo := "moita" if sorteio < 0.5 else ("copa" if sorteio < 0.82 else ("gigante" if sorteio < 0.91 else "palmeira"))
		var lista: Array = listas[tipo]
		if lista.size() >= int(metas[tipo]):
			faltam = false
			for k in listas:
				faltam = faltam or (listas[k] as Array).size() < int(metas[k])
			continue
		var dx := _terreno.altura_em(x + 6.0, z) - _terreno.altura_em(x - 6.0, z)
		var dz := _terreno.altura_em(x, z + 6.0) - _terreno.altura_em(x, z - 6.0)
		if absf(dx) + absf(dz) > (14.0 if tipo == "moita" else 9.0) or _estrada_perto(Vector2(x, z), h, 30.0):
			continue
		var esc := rng.randf_range(0.18, 0.34) if tipo == "moita" else rng.randf_range(0.75, 1.25)
		var tinta := Color(1, 1, 1) * rng.randf_range(0.8, 1.12)
		lista.append([Vector3(x, h - (0.6 if tipo == "moita" else 0.3), z), esc, rng.randf() * TAU, tinta])
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.COPA, listas.moita, 220.0, 950.0, false)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.SUMAUMA, listas.gigante, 500.0, 4200.0, true)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.COPA, listas.copa, 400.0, 3000.0, true)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.PALMEIRA_SELVA, listas.palmeira, 400.0, 2400.0, true)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SELVA] mata da etapa: ", {"gigante": listas.gigante.size(), "copa": listas.copa.size(), "palmeira": listas.palmeira.size(), "moita": listas.moita.size()})


## Serpente colossal da etapa (SerpenteCaminho): depende do percurso e do alvo da etapa, por isso é
## montada depois deles (Partida._iniciar_etapa). A mata por onde ela passa some enquanto a etapa durar.
func montar_serpente_caminho(indice: int, sub: ComplexoSubida, alvo: Alvo) -> void:
	_montar_cobras_bote(indice, sub)
	var cfg: Dictionary = _cfg.get("serpente_caminho", {})
	if not (indice + 1) in Array(cfg.get("etapas", [])).map(func(n): return int(n)):
		return
	var cobra := SerpenteCaminho.new()
	_etapa_no.add_child(cobra)
	cobra.montar(sub, alvo, _terreno, cfg)
	_abrir_mata(cobra.roteiro(), cobra.largura * 0.5 + 9.0)


## Cobras que dão o bote (SerpenteBote, pedido do dono 2026-10-05): a da plataforma dos buracos
## (cobra_arena) e a da toca na montanha colada na pista (cobra_toca), nas etapas da config.
func _montar_cobras_bote(indice: int, sub: ComplexoSubida) -> void:
	var na_etapa := func(cfg: Dictionary) -> bool: return (indice + 1) in Array(cfg.get("etapas", [])).map(func(n): return int(n))
	var arena: Dictionary = _cfg.get("cobra_arena", {})
	if na_etapa.call(arena) and sub.plataforma:
		var cobra := SerpenteBote.new()
		_etapa_no.add_child(cobra)
		cobra.montar_arena(sub.plataforma, arena)
	var toca: Dictionary = _cfg.get("cobra_toca", {})
	if na_etapa.call(toca):
		var cobra := SerpenteBote.new()
		_etapa_no.add_child(cobra)
		cobra.montar_toca(sub, _terreno, toca)


var _mata: Array = []          # MultiMeshInstance3D da vegetação
var _mata_tirada: Array = []   # [MultiMesh, índice, Transform3D] escondidas pela serpente da etapa


func _abrir_mata(pontos: PackedVector3Array, raio: float) -> void:
	var grade := {}
	for k in range(0, pontos.size(), 3):
		var q := pontos[k]
		grade[Vector2i(floori(q.x / 20.0), floori(q.z / 20.0))] = true
	var zero := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO)
	for mmi: MultiMeshInstance3D in _mata:
		var mm := mmi.multimesh
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var c := Vector2i(floori(xf.origin.x / 20.0), floori(xf.origin.z / 20.0))
			var perto := false
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					perto = perto or grade.has(c + Vector2i(dx, dz))
			if not perto:
				continue
			for k in range(0, pontos.size(), 2):
				var q := pontos[k]
				if Vector2(q.x - xf.origin.x, q.z - xf.origin.z).length_squared() < raio * raio and xf.origin.y < q.y + 4.0:
					_mata_tirada.append([mm, i, xf])
					mm.set_instance_transform(i, zero)
					break


func _restaurar_mata() -> void:
	for t: Array in _mata_tirada:
		(t[0] as MultiMesh).set_instance_transform(t[1], t[2])
	_mata_tirada.clear()


func _physics_process(delta: float) -> void:
	_t += delta
	if _vento_cfg.is_empty():
		return
	var ang := deg_to_rad(float(_vento_cfg.get("direcao", 90)))
	var dir := Vector3(sin(ang), 0.0, -cos(ang))
	var periodo := maxf(float(_vento_cfg.get("periodo", 6.0)), 0.5)
	var rajada := float(_vento_cfg.get("rajada", 0.0)) * (0.5 + 0.5 * sin(_t * TAU / periodo)) * (0.7 + 0.3 * sin(_t * 2.3))
	Veiculo.vento = dir * (float(_vento_cfg.get("forca", 0.0)) + rajada)


func _exit_tree() -> void:
	Veiculo.vento = Vector3.ZERO
