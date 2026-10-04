extends RefCounted
## Castelo de gelo gigante em volta do alvo (Frozen Peak, etapa 4: mapa.subida.gelo.etapas.N.castelo —
## pedido do dono, 2026-10-04, arte em assets/frozen/extruturas/castelo.png, no lugar da cidadela quadrada
## de tijolos de gelo). Tudo em geometria, com o gelo de gotejamento dos maciços (Gelo.material_fenda):
## - muralha em anel com torres caneladas nos vértices (alturas alternadas), cada torre com coroa de
##   ameias, neve, pingentes, estandarte azul e um feixe de cristais acesos no alto;
## - portão gigante virado para a rampa: duas torres altas, viga com degraus em arco ogival, emblema de
##   cristal e pingentes compridos;
## - torre de menagem no fundo: bloco alto com portal, duas torres, cúpula de cristal e coroa de cristais;
## - quatro torres de dentro; lago congelado no pátio, com o gelo estilhaçado em volta de onde o
##   megalodonte (TubaraoGelo, o alvo) rompe a superfície; maciços de gelo no pé da muralha.
## cfg: {centro: [x, z], frente: [x, z] (para onde o portão olha), raio}. Bater em muralha ou torre explode.

const PORTAO := "res://scripts/mundo/portao_gelo.gd"
const LADOS := 14
const ALT_MURO := 62.0


static func montar(g: Gelo, pai: Node3D, cfg: Dictionary) -> void:
	var portao = load(PORTAO)
	var c2 := Vector2(float(cfg.centro[0]), float(cfg.centro[1]))
	var chao: float = g._chao
	var c := Vector3(c2.x, chao, c2.y)
	var fr: Array = cfg.get("frente", [-1, 0])
	var f := Vector3(float(fr[0]), 0.0, float(fr[1])).normalized()
	var lat := f.cross(Vector3.UP).normalized()
	var raio := float(cfg.get("raio", 235.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9917
	var no := Node3D.new()
	no.name = "Castelo"
	pai.add_child(no)
	var corpo := g._corpo(no)
	var gelo_m := Gelo.material_fenda()
	var neve_m := Gelo.material(Gelo.Mat.NEVE)
	var cristal_m: Material = portao._material("espinho")
	var azul := StandardMaterial3D.new()
	azul.albedo_color = Color(0.04, 0.1, 0.42)
	azul.roughness = 0.6
	azul.emission_enabled = true
	azul.emission = Color(0.05, 0.16, 0.6)
	azul.emission_energy_multiplier = 0.5
	var muros: Array[Transform3D] = []      # com colisão
	var enfeites: Array[Transform3D] = []   # ameias (sem colisão)
	var neves: Array[Transform3D] = []
	var panos: Array[Transform3D] = []
	var picos: Array = []                   # [base, altura, raio, ponta, cortes] para Gelo.macico
	var discos: Array = []
	var cones: Array = []
	var pingentes: Array = []
	# Estandarte: pano azul com "TSC" em pé (pedido do dono)
	var letreiro := func(centro: Vector3, fora: Vector3, larg: float, alt: float, texto: String) -> void:
		var lb := Label3D.new()
		lb.text = texto
		lb.font = portao._fonte()
		lb.font_size = 96
		lb.outline_size = 10
		lb.modulate = Color(0.92, 0.98, 1.0)
		lb.outline_modulate = Color(0.3, 0.75, 1.0)
		lb.line_spacing = -18.0
		var linhas := texto.count("
") + 1
		lb.pixel_size = minf(larg / (96.0 * (0.85 if linhas > 1 else 2.3)), alt / (96.0 * 1.15 * linhas))
		lb.transform = Transform3D(Basis.looking_at(-fora, Vector3.UP), centro + fora * 0.9)
		no.add_child(lb)
	var dir := func(ang: float) -> Vector3: return f * cos(ang) + lat * sin(ang)
	# Caixa de `a` até `b` (pontos no chão), de y0 a y1 acima do chão, espessura `esp`
	var caixa := func(a: Vector3, b: Vector3, y0: float, y1: float, esp: float) -> Transform3D:
		var d := b - a
		var comp := d.length()
		var dn := d / comp
		return Transform3D(Basis(dn, Vector3.UP, dn.cross(Vector3.UP)) * Basis.from_scale(Vector3(comp, y1 - y0, esp)), (a + b) * 0.5 + Vector3.UP * ((y0 + y1) * 0.5))
	var cone := func(base: Vector3, eixo: Vector3, r: float, h: float) -> void:
		eixo = eixo.normalized()
		cones.append(Transform3D(Basis(Quaternion(Vector3.UP, eixo)) * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r, h, r)), base + eixo * h * 0.5))
	var pingente := func(topo: Vector3, l: float) -> void:
		var rad := clampf(l * 0.06, 0.25, 0.9)
		pingentes.append(Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(rad, l, rad)), topo - Vector3.UP * l * 0.5))
	# Torre canelada com coroa, neve, pingentes, estandarte (virado para `fora`) e feixe de cristais
	var torre := func(p: Vector3, r: float, h: float, fora: Vector3) -> void:
		# Fuste: coluna de gelo de gotejamento (caneluras, bojos, escorridos, pingentes), não um cilindro liso
		picos.append([p - Vector3.UP * 3.0, (h + 3.0) / 0.93, r * 1.3, 4.0, []])
		for k in rng.randi_range(2, 4):
			var ak := rng.randf() * TAU
			picos.append([p + Vector3(cos(ak), 0.0, sin(ak)) * r * 1.1 - Vector3.UP * 3.0, h * rng.randf_range(0.2, 0.55), r * rng.randf_range(0.45, 0.7), 0.6, []])
		var cs := CollisionShape3D.new()
		var forma := CylinderShape3D.new()
		forma.radius = r * 0.92
		forma.height = h + 6.0
		cs.shape = forma
		cs.position = p + Vector3.UP * ((h + 6.0) * 0.5 - 6.0)
		corpo.add_child(cs)
		# Coroa: anel saliente, ameias e neve
		discos.append([Transform3D(Basis.from_scale(Vector3(r * 1.12, r * 0.5, r * 1.12)), p + Vector3.UP * (h - r * 0.1)), 0])
		discos.append([Transform3D(Basis.from_scale(Vector3(r * 1.0, r * 0.22, r * 1.0)), p + Vector3.UP * (h + r * 0.26)), 1])
		for k in 10:
			var a := TAU * k / 10.0
			var o := Vector3(cos(a), 0.0, sin(a))
			enfeites.append(Transform3D(Basis.looking_at(o, Vector3.UP) * Basis.from_scale(Vector3(r * 0.34, r * 0.42, r * 0.2)), p + o * r * 1.0 + Vector3.UP * (h + r * 0.36)))
		for k in 16:
			var a := rng.randf() * TAU
			pingente.call(p + Vector3(cos(a), 0.0, sin(a)) * r * 1.1 + Vector3.UP * (h - r * 0.34), rng.randf_range(r * 0.25, r * 0.9))
		panos.append(Transform3D(Basis.looking_at(fora, Vector3.UP) * Basis.from_scale(Vector3(r * 0.62, h * 0.26, 0.8)), p + fora * (r * 1.12) + Vector3.UP * (h * 0.62)))
		letreiro.call(p + fora * (r * 1.12) + Vector3.UP * (h * 0.62), fora, r * 0.62, h * 0.26, "T
S
C")
		cone.call(p + Vector3.UP * (h + r * 0.3), Vector3.UP, r * 0.5, r * 2.8)
		for k in 6:
			var a := TAU * k / 6.0 + rng.randf_range(-0.2, 0.2)
			var o := Vector3(cos(a), 0.0, sin(a))
			cone.call(p + o * r * 0.42 + Vector3.UP * (h + r * 0.3), Vector3.UP + o * rng.randf_range(0.18, 0.4), r * rng.randf_range(0.18, 0.28), r * rng.randf_range(1.0, 1.7))

	# ---- Muralha em anel e torres dos vértices (o portão fica entre a última e a primeira)
	var vert: Array[Vector3] = []
	for i in LADOS:
		vert.append(c + (dir.call((i + 0.5) * TAU / LADOS) as Vector3) * raio)
	for i in LADOS:
		var portao_t := i == 0 or i == LADOS - 1
		var fora := (vert[i] - c).normalized()
		torre.call(vert[i], 20.0 if portao_t else 15.0, 190.0 if portao_t else (150.0 if i % 2 == 0 else 118.0), fora)
		if i == LADOS - 1:
			break
		var a := vert[i]
		var b := vert[i + 1]
		# Muralha: fileira de colunas de gelo de alturas e grossuras diferentes, fundidas (um miolo fino e
		# mais baixo fecha as frestas e dá a colisão que mata)
		muros.append(caixa.call(a, b, -4.0, ALT_MURO - 14.0, 6.0))
		var normal := ((a + b) * 0.5 - c).normalized()
		var comp := a.distance_to(b)
		var qtd := int(comp / 9.5)
		for k in qtd:
			var m := a.lerp(b, (k + 0.5 + rng.randf_range(-0.25, 0.25)) / qtd) + normal * rng.randf_range(-2.5, 2.5)
			picos.append([m - Vector3.UP * 3.0, ALT_MURO + rng.randf_range(-10.0, 22.0), rng.randf_range(7.0, 10.5), rng.randf_range(1.2, 3.0), []])

	# ---- Portão: viga alta, degraus em arco ogival, emblema de cristal e pingentes compridos
	var pa := vert[LADOS - 1]
	var pb := vert[0]
	var y_arco := 132.0
	muros.append(caixa.call(pa, pb, y_arco, y_arco + 30.0, 16.0))
	neves.append(caixa.call(pa, pb, y_arco + 30.0, y_arco + 33.0, 19.0))
	var vao := pa.distance_to(pb)
	for k in int(vao / 13.0):
		enfeites.append(Transform3D(Basis.looking_at(f, Vector3.UP) * Basis.from_scale(Vector3(6.0, 8.0, 17.5)), pa.lerp(pb, (k + 0.5) / int(vao / 13.0)) + Vector3.UP * (y_arco + 37.0)))
	for s in range(1, 6):
		var alcance := (20.0 + (6 - s) * 5.5) / vao
		for ponta: Array in [[pa, pb], [pb, pa]]:
			var de: Vector3 = ponta[0]
			var ate: Vector3 = (ponta[0] as Vector3).lerp(ponta[1], alcance)
			muros.append(caixa.call(de, ate, y_arco - s * 11.0, y_arco - (s - 1) * 11.0, 14.0))
			for k in 3:
				pingente.call(ate + f * rng.randf_range(-5.0, 5.0) + Vector3.UP * (y_arco - s * 11.0), rng.randf_range(4.0, 12.0))
	var meio_p := (pa + pb) * 0.5
	for k in 46:
		pingente.call(meio_p + lat * rng.randf_range(-16.0, 16.0) + f * rng.randf_range(-7.0, 7.0) + Vector3.UP * y_arco, rng.randf_range(4.0, 12.0) if rng.randf() < 0.6 else rng.randf_range(14.0, 30.0))
	for face: float in [-1.0, 1.0]:
		var e := meio_p + f * face * 10.0 + Vector3.UP * (y_arco + 15.0)
		cone.call(e, Vector3.UP, 8.0, 24.0)
		cone.call(e, Vector3.DOWN, 8.0, 24.0)

	# ---- Torre de menagem no fundo: bloco com portal, duas torres, cúpula e coroa de cristais
	var k0 := c - f * (raio - 62.0)
	muros.append(caixa.call(k0 - lat * 56.0, k0 + lat * 56.0, -4.0, 150.0, 70.0))
	muros.append(caixa.call(k0 - lat * 38.0, k0 + lat * 38.0, 150.0, 176.0, 50.0))
	neves.append(caixa.call(k0 - lat * 57.5, k0 + lat * 57.5, 150.0, 152.5, 73.0))
	panos.append(Transform3D(Basis.looking_at(f, Vector3.UP) * Basis.from_scale(Vector3(40.0, 100.0, 1.2)), k0 + f * 47.0 + Vector3.UP * 50.0))
	letreiro.call(k0 + f * 47.0 + Vector3.UP * 78.0, f, 36.0, 30.0, "TSC")
	for k in 8:
		enfeites.append(Transform3D(Basis.looking_at(f, Vector3.UP) * Basis.from_scale(Vector3(7.0, 8.0, 6.0)), k0 + lat * (-49.0 + 14.0 * k) + f * 33.0 + Vector3.UP * 156.0))
	for k in 60:
		pingente.call(k0 + lat * rng.randf_range(-55.0, 55.0) + f * 36.0 + Vector3.UP * 150.0, rng.randf_range(3.0, 10.0) if rng.randf() < 0.7 else rng.randf_range(12.0, 28.0))
	for s: float in [-1.0, 1.0]:
		torre.call(k0 + lat * s * 64.0 + f * 22.0, 18.0, 215.0, f)
	# Colunas de gelo cobrindo as faces do bloco (menos o portal)
	for k in 11:
		var u := -55.0 + 11.0 * k
		if absf(u) < 21.0:
			continue
		picos.append([k0 + lat * u + f * 35.0 - Vector3.UP * 3.0, 150.0 + rng.randf_range(-14.0, 24.0), rng.randf_range(8.0, 11.0), rng.randf_range(2.0, 3.5), []])
	for s: float in [-1.0, 1.0]:
		for k in 6:
			picos.append([k0 + lat * s * 56.0 + f * (30.0 - 12.0 * k) - Vector3.UP * 3.0, 150.0 + rng.randf_range(-14.0, 24.0), rng.randf_range(8.0, 11.0), rng.randf_range(2.0, 3.5), []])
	var cupula := MeshInstance3D.new()
	var esf := SphereMesh.new()
	esf.radius = 40.0
	esf.height = 80.0
	esf.radial_segments = 40
	esf.rings = 20
	cupula.mesh = esf
	cupula.material_override = portao._material("bola")
	cupula.position = k0 + Vector3.UP * 176.0
	no.add_child(cupula)
	var cs_c := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 40.0
	cs_c.shape = sp
	cs_c.position = k0 + Vector3.UP * 176.0
	corpo.add_child(cs_c)
	cone.call(k0 + Vector3.UP * 212.0, Vector3.UP, 9.0, 78.0)
	for k in 8:
		var a := TAU * k / 8.0
		var o := Vector3(cos(a), 0.0, sin(a))
		cone.call(k0 + o * 26.0 + Vector3.UP * 204.0, Vector3.UP + o * 0.3, 5.0, rng.randf_range(30.0, 46.0))

	# ---- Torres de dentro (dos lados, fora do caminho do voo)
	for ang: float in [1.25, -1.25, 2.2, -2.2]:
		var p := c + (dir.call(ang) as Vector3) * (raio - 52.0)
		torre.call(p, 13.0, 200.0 if absf(ang) > 2.0 else 172.0, (c - p).normalized())

	# ---- Lago congelado no pátio
	# (pedido do dono: "não tem cara de água e é perfeitamente redondo") — margem irregular, com enseadas
	# e pontas; gelo escuro e liso que reflete o céu, rachaduras e neve soprada (o mesmo gelo do lago do
	# vale); bancos de neve na margem
	var margem := func(a: float) -> float:
		return 106.0 * (1.0 + 0.17 * sin(2.0 * a + 1.3) + 0.11 * sin(3.0 * a + 0.4) + 0.07 * sin(5.0 * a + 2.1) + 0.035 * sin(9.0 * a + 0.7) + 0.02 * sin(17.0 * a))
	var st_l := SurfaceTool.new()
	st_l.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg_l := 160
	for k in seg_l:
		var a0 := TAU * k / seg_l
		var a1 := TAU * (k + 1) / seg_l
		for v: Vector3 in [Vector3.ZERO, Vector3(cos(a0), 0.0, sin(a0)) * (margem.call(a0) as float), Vector3(cos(a1), 0.0, sin(a1)) * (margem.call(a1) as float)]:   # face para cima
			st_l.set_normal(Vector3.UP)
			st_l.add_vertex(v)
	var lago := MeshInstance3D.new()
	lago.mesh = st_l.commit()
	var mat_l := ShaderMaterial.new()
	mat_l.shader = load("res://shaders/lago_gelo.gdshader")
	mat_l.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 3, 41))
	mat_l.set_shader_parameter("cor_gelo", Color(0.1, 0.4, 0.62))
	mat_l.set_shader_parameter("cor_fundo", Color(0.015, 0.13, 0.3))
	lago.material_override = mat_l
	# O chão de neve ondula: o gelo fica rente ao ponto mais alto do terreno dentro da margem
	var y_lago := c.y
	if g._terreno:
		for k in 120:
			var al := TAU * k / 24.0
			var pl := c + Vector3(cos(al), 0.0, sin(al)) * (margem.call(al) as float) * (0.2 + 0.2 * float(k / 24))
			y_lago = maxf(y_lago, g._terreno.altura_em(pl.x, pl.z))
	lago.position = Vector3(c.x, y_lago + 0.35, c.z)
	lago.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	no.add_child(lago)
	var bancos: Array = []
	for k in 90:
		var a := rng.randf() * TAU
		var rb := rng.randf_range(5.0, 13.0)
		var pb2 := c + Vector3(cos(a), 0.0, sin(a)) * ((margem.call(a) as float) + rb * rng.randf_range(-0.1, 0.6))
		bancos.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(rb, rb * rng.randf_range(0.12, 0.3), rb * rng.randf_range(0.5, 0.9))), Vector3(pb2.x, y_lago + 0.2, pb2.z)))
	var monte := SphereMesh.new()
	monte.radius = 1.0
	monte.height = 2.0
	monte.radial_segments = 14
	monte.rings = 7
	Gelo._instancias(no, monte, bancos, neve_m, false)

	# ---- Malhas
	ComplexoLancamento.criar_multimesh(no, muros, gelo_m)
	ComplexoLancamento.criar_multimesh(no, enfeites, gelo_m)
	ComplexoLancamento.criar_multimesh(no, neves, neve_m)
	ComplexoLancamento.criar_multimesh(no, panos, azul, false)
	ComplexoLancamento.adicionar_colisoes(corpo, muros)
	var cil := CylinderMesh.new()
	cil.top_radius = 1.0
	cil.bottom_radius = 0.9
	cil.height = 1.0
	cil.radial_segments = 20
	cil.rings = 1
	var d_gelo: Array = []
	var d_neve: Array = []
	for d: Array in discos:
		(d_gelo if int(d[1]) == 0 else d_neve).append(d[0])
	Gelo._instancias(no, cil, d_gelo, gelo_m)
	Gelo._instancias(no, cil, d_neve, neve_m)
	var ponta := CylinderMesh.new()
	ponta.top_radius = 0.0
	ponta.bottom_radius = 1.0
	ponta.height = 1.0
	ponta.radial_segments = 6
	ponta.rings = 1
	Gelo._instancias(no, ponta, cones, cristal_m, false)
	Gelo.instancias_gelo(no, pingentes, 0.0, 0, false, 1400.0)

	# ---- Maciços de gelo: no pé da muralha (por fora, menos na frente do portão), e o gelo do lago
	# estilhaçado em volta de onde o tubarão rompe a superfície
	for k in 46:
		var ang := rng.randf_range(0.42, TAU - 0.42)
		var o: Vector3 = dir.call(ang)
		picos.append([c + o * (raio + rng.randf_range(12.0, 30.0)) - Vector3.UP * 3.0, rng.randf_range(16.0, 52.0), rng.randf_range(5.0, 9.5), 0.3, []])
	for s: float in [-1.0, 1.0]:
		for k in 5:
			picos.append([(pa if s < 0.0 else pb) + f * rng.randf_range(14.0, 34.0) - lat * s * rng.randf_range(-6.0, 26.0) - Vector3.UP * 3.0, rng.randf_range(18.0, 60.0), rng.randf_range(5.0, 9.0), 0.3, []])
	var furo := c - f * 46.0
	for k in 18:
		var a := TAU * (k + rng.randf_range(-0.3, 0.3)) / 18.0
		var o := Vector3(cos(a), 0.0, sin(a))
		if o.dot(f) > 0.55:
			continue   # a frente da boca fica livre
		picos.append([furo + o * rng.randf_range(44.0, 58.0) - Vector3.UP * 3.0, rng.randf_range(10.0, 26.0), rng.randf_range(3.5, 7.0), 0.2, []])
	g.macico(no, picos, 5531)

	# ---- Luz ciano no portão e na torre de menagem
	for p: Vector3 in [pa + f * 24.0 + Vector3.UP * 40.0, pb + f * 24.0 + Vector3.UP * 40.0, k0 + f * 50.0 + Vector3.UP * 60.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.35, 0.8, 1.0)
		l.light_energy = 4.0
		l.omni_range = 110.0
		l.shadow_enabled = false
		l.position = p
		no.add_child(l)
