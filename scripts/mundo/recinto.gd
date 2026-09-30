class_name Recinto
extends Node3D
## Cercado murado no estilo da arena do Canyon Combat (cerca de pedra + grade de ferro enferrujado,
## pontas, braseiros), usado no Climb to Death para a largada (no chão) e para a plataforma a 100 m
## (com buracos da morte com fogo e pontos de aceleração).
##
## Coordenadas locais: x = distância desde o muro do fundo (0) até o muro da frente (comprimento),
## onde fica a saída; lateral = + à direita de quem sai. Aberturas extras (entradas) ficam nas
## laterais. Os bots saem pela frente seguindo um mapa de custo (como na arena).
##
## Tem os mesmos nomes da arena que o PilotoBot usa (local, pa, comprimento, saida_largura,
## piso_y, dentro_da_arena, rumo_saida, buraco_mais_perto, perigo_mais_perto).

const PAREDE := 1.0
const CELULA := 2.0
const IMPULSO_MEIO := Vector2(3.5, 2.0)
const COR_EVENTO := Color(1.0, 0.45, 0.08)

var origem := Vector3.ZERO      # centro do muro do fundo, na altura do piso
var frente := Vector3.RIGHT
var lateral := Vector3.BACK
var comprimento := 70.0
var largura_arena := 90.0
var saida_largura := 10.0
var piso_y := 10.0
var chao_y := 6.0               # até onde o pedestal desce (terreno)
var muro_altura := 2.6
var grade_altura := 7.4
var buracos: Array = []         # [Vector2(x, lateral), raio]
var impulsos: Array = []        # [Vector2(x, lateral), ângulo (0 = frente), segura]
var entradas: Array = []        # [lado (+1/-1), x do centro, largura]
var vagas: Array = []           # [x, lateral, direção em graus (0 = para a saída)]
var nome_placa := ""
var corpo: StaticBody3D

var _nav := PackedFloat32Array()
var _nav_nx := 0
var _nav_nl := 0
var _nav_x_max := 0.0
var _leds_vagas: Array[StandardMaterial3D] = []
var semaforo_lampadas: Array[MeshInstance3D] = []


func montar(p_origem: Vector3, p_frente: Vector3, terreno_y: float) -> void:
	origem = p_origem
	frente = Vector3(p_frente.x, 0.0, p_frente.z).normalized()
	lateral = frente.cross(Vector3.UP).normalized()
	piso_y = origem.y
	chao_y = terreno_y
	corpo = StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	add_child(corpo)
	_montar_piso()
	_montar_pedestal()
	_montar_cerca()
	_montar_buracos()
	_montar_impulsos()
	_montar_vagas()
	_montar_portao()
	_montar_nav()


# ------------------------------------------------------------------ coordenadas

func pa(x: float, lat: float, y: float) -> Vector3:
	var p := origem + frente * x + lateral * lat
	p.y = y
	return p


func local(p: Vector3) -> Vector2:
	var d := p - origem
	return Vector2(d.dot(frente), d.dot(lateral))


func dir_mundo(angulo: float) -> Vector3:
	return frente * cos(angulo) + lateral * sin(angulo)


func dentro_da_arena(p: Vector3) -> bool:
	var l := local(p)
	return l.x > -3.0 and l.x < comprimento + 1.0 and absf(l.y) < largura_arena * 0.5 + 3.0 and absf(p.y - piso_y) < 12.0


func buraco_mortal(p: Vector3) -> bool:
	if p.y > piso_y - 1.2:
		return false
	var l := local(p)
	if l.x < -1.0 or l.x > comprimento + 1.0 or absf(l.y) > largura_arena * 0.5 + 1.0:
		return false
	for b in buracos:
		if l.distance_to(b[0]) < b[1] + 0.6:
			return true
	return p.y < piso_y - 6.0 and p.y > chao_y


func impulso_em(p: Vector3) -> Vector3:
	if absf(p.y - piso_y) > 2.5:
		return Vector3.ZERO
	var l := local(p)
	for im in impulsos:
		var d: Vector2 = l - im[0]
		var f := Vector2(cos(im[1]), sin(im[1]))
		if absf(d.dot(f)) < IMPULSO_MEIO.x and absf(d.dot(Vector2(-f.y, f.x))) < IMPULSO_MEIO.y:
			return dir_mundo(im[1])
	return Vector3.ZERO


func buraco_mais_perto(p: Vector3) -> Dictionary:
	var l := local(p)
	var melhor := {}
	for b in buracos:
		var d: float = l.distance_to(b[0]) - float(b[1])
		if melhor.is_empty() or d < melhor.distancia:
			melhor = {"centro": pa(b[0].x, b[0].y, piso_y), "raio": b[1], "distancia": d}
	return melhor


func perigo_mais_perto(p: Vector3) -> Dictionary:
	var melhor := buraco_mais_perto(p)
	var l := local(p)
	for im in impulsos:
		if im[2]:
			continue
		var d: float = l.distance_to(im[0]) - 2.0
		if melhor.is_empty() or d < melhor.distancia:
			melhor = {"centro": pa(im[0].x, im[0].y, piso_y), "raio": 2.0, "distancia": d}
	return melhor


# ------------------------------------------------------------------ vagas

func sortear_vagas(quantidade: int, rng: RandomNumberGenerator) -> Array[int]:
	var total := vagas.size()
	var escolhidas: Array[int] = []
	for i in total:
		escolhidas.append(i)
	for i in range(total - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := escolhidas[i]
		escolhidas[i] = escolhidas[j]
		escolhidas[j] = t
	return escolhidas.slice(0, mini(quantidade, total))


func transform_vaga(i: int) -> Transform3D:
	var v: Array = vagas[i]
	var f := dir_mundo(deg_to_rad(float(v[2])))
	return Transform3D(Basis.looking_at(f, Vector3.UP), pa(float(v[0]), float(v[1]), piso_y + 0.15))


func pintar_vagas(cores: Dictionary) -> void:
	for i in _leds_vagas.size():
		var m := _leds_vagas[i]
		var c: Color = cores.get(i, Color(0.15, 0.15, 0.15))
		m.albedo_color = c
		m.emission = c
		m.emission_energy_multiplier = 4.0 if cores.has(i) else 0.0


# ------------------------------------------------------------------ montagem

func _material_pedra() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/muro_pedra.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 71))
	m.set_shader_parameter("altura_chao", chao_y)
	return m


func _montar_piso() -> void:
	var meia := largura_arena * 0.5 + PAREDE
	var x0 := -PAREDE
	var x1 := comprimento + PAREDE
	var passo := 3.0
	var nx := int(ceil((x1 - x0) / passo))
	var nl := int(ceil(meia * 2.0 / passo))
	var pts := PackedVector2Array()
	for i in nx + 1:
		for j in nl + 1:
			var q := Vector2(lerpf(x0, x1, float(i) / nx), lerpf(-meia, meia, float(j) / nl))
			var livre := true
			for b in buracos:
				if q.distance_to(b[0]) < float(b[1]) + 1.2:
					livre = false
			if livre:
				pts.append(q)
	for b in buracos:
		for k in 48:
			pts.append(b[0] + Vector2(cos(TAU * k / 48.0), sin(TAU * k / 48.0)) * float(b[1]))
	var tri := Geometry2D.triangulate_delaunay(pts)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for t in range(0, tri.size(), 3):
		var a := pts[tri[t]]
		var bq := pts[tri[t + 1]]
		var c := pts[tri[t + 2]]
		var cen := (a + bq + c) / 3.0
		var no_buraco := false
		for b in buracos:
			if cen.distance_to(b[0]) < float(b[1]):
				no_buraco = true
		if no_buraco:
			continue
		var ordem: Array = [a, bq, c]
		if (pa(bq.x, bq.y, 0.0) - pa(a.x, a.y, 0.0)).cross(pa(c.x, c.y, 0.0) - pa(a.x, a.y, 0.0)).y > 0.0:
			ordem = [a, c, bq]
		for q: Vector2 in ordem:
			var v := pa(q.x, q.y, piso_y)
			st.set_normal(Vector3.UP)
			st.set_uv(q)
			st.add_vertex(v)
			faces.append(v)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/piso_arena.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 83))
	mat.set_shader_parameter("comprimento", comprimento)
	mat.set_shader_parameter("saida_largura", saida_largura)
	var arr_b := PackedVector3Array()
	for k in 12:
		arr_b.append(Vector3(buracos[k][0].x, buracos[k][0].y, buracos[k][1]) if k < buracos.size() else Vector3.ZERO)
	mat.set_shader_parameter("buracos", arr_b)
	var arr_v := PackedVector3Array()
	for k in 16:
		if k < vagas.size():
			arr_v.append(Vector3(float(vagas[k][0]), float(vagas[k][1]), deg_to_rad(float(vagas[k][2]))))
		else:
			arr_v.append(Vector3(-1000.0, 0.0, 0.0))
	mat.set_shader_parameter("vagas", arr_v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	corpo.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	corpo.physics_material_override = pm


## Pedestal de pedra do piso até o chão, com contrafortes e cornija de aço com LED.
func _montar_pedestal() -> void:
	var b := Basis.looking_at(frente, Vector3.UP)
	var meia := largura_arena * 0.5 + PAREDE
	var topo := piso_y - 0.05
	var fundo := chao_y - 3.0
	var alt := topo - fundo
	var ym := (topo + fundo) * 0.5
	var esp := 2.0
	var pedra: Array[Transform3D] = []
	pedra.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + esp * 2.0, alt, esp)), pa(-PAREDE - esp * 0.5, 0.0, ym)))
	pedra.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + esp * 2.0, alt, esp)), pa(comprimento + PAREDE + esp * 0.5, 0.0, ym)))
	for s: float in [-1.0, 1.0]:
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(esp, alt, comprimento + PAREDE * 2.0 + esp * 2.0)), pa(comprimento * 0.5, (meia + esp * 0.5) * s, ym)))
	var contrafortes: Array[Transform3D] = []
	if alt > 20.0:
		for k in int(comprimento / 14.0) + 1:
			var x := lerpf(4.0, comprimento - 4.0, float(k) / maxf(int(comprimento / 14.0), 1))
			for s: float in [-1.0, 1.0]:
				contrafortes.append(Transform3D(b * Basis.from_scale(Vector3(3.0, alt - 1.5, 2.6)), pa(x, (meia + esp + 1.5) * s, ym - 0.75)))
		for k in int(largura_arena / 14.0) + 1:
			var lat := lerpf(-meia + 4.0, meia - 4.0, float(k) / maxf(int(largura_arena / 14.0), 1))
			for sx: float in [-1.0, 1.0]:
				var x := -PAREDE - esp - 1.5 if sx < 0.0 else comprimento + PAREDE + esp + 1.5
				contrafortes.append(Transform3D(b * Basis.from_scale(Vector3(2.6, alt - 1.5, 3.0)), pa(x, lat, ym - 0.75)))
	var mat := _material_pedra()
	ComplexoLancamento.criar_multimesh(self, pedra, mat)
	ComplexoLancamento.criar_multimesh(self, contrafortes, mat)
	ComplexoLancamento.adicionar_colisoes(corpo, pedra)
	var led: Array[Transform3D] = []
	var y_c := piso_y - 1.4
	led.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + esp * 2.0, 0.16, 0.12)), pa(-PAREDE - esp - 0.1, 0.0, y_c)))
	led.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + esp * 2.0, 0.16, 0.12)), pa(comprimento + PAREDE + esp + 0.1, 0.0, y_c)))
	for s: float in [-1.0, 1.0]:
		led.append(Transform3D(b * Basis.from_scale(Vector3(0.12, 0.16, comprimento + PAREDE * 2.0 + esp * 2.0)), pa(comprimento * 0.5, (meia + esp + 0.1) * s, y_c)))
	ComplexoLancamento.criar_multimesh(self, led, ComplexoLancamento._material_luz(COR_EVENTO, 3.0), false)


## Trechos (x, lat) dos muros, deixando o vão da saída na frente e as entradas nas laterais.
func _trechos_muro() -> Array:
	var meia := largura_arena * 0.5 + PAREDE * 0.5
	var xf := -PAREDE * 0.5
	var xp := comprimento + PAREDE * 0.5
	var g := saida_largura * 0.5 + 1.6
	var trechos := [
		[Vector2(xf, -meia), Vector2(xf, meia)],
		[Vector2(xp, -meia), Vector2(xp, -g)],
		[Vector2(xp, g), Vector2(xp, meia)],
	]
	for s: float in [-1.0, 1.0]:
		var cortes: Array = []
		for e in entradas:
			if signf(float(e[0])) == s:
				cortes.append([float(e[1]) - float(e[2]) * 0.5 - 1.6, float(e[1]) + float(e[2]) * 0.5 + 1.6])
		cortes.sort_custom(func(a, b): return a[0] < b[0])
		var x0 := xf
		for c in cortes:
			trechos.append([Vector2(x0, meia * s), Vector2(c[0], meia * s)])
			x0 = c[1]
		trechos.append([Vector2(x0, meia * s), Vector2(xp, meia * s)])
	return trechos


func _montar_cerca() -> void:
	var pedra: Array[Transform3D] = []
	var capa: Array[Transform3D] = []
	var ferro: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var pontas: Array[Transform3D] = []
	var braseiros: Array[Vector3] = []
	var altura_total := muro_altura + grade_altura
	var centro := pa(comprimento * 0.5, 0.0, 0.0)
	for t: Array in _trechos_muro():
		var a: Vector2 = t[0]
		var c: Vector2 = t[1]
		var d := c - a
		var comp := d.length()
		if comp < 0.5:
			continue
		var eixo := (frente * d.x + lateral * d.y).normalized()
		var bb := Basis.looking_at(eixo, Vector3.UP)
		var meio := (a + c) * 0.5
		pedra.append(Transform3D(bb * Basis.from_scale(Vector3(PAREDE, muro_altura, comp)), pa(meio.x, meio.y, piso_y + muro_altura * 0.5)))
		capa.append(Transform3D(bb * Basis.from_scale(Vector3(PAREDE + 0.25, 0.16, comp)), pa(meio.x, meio.y, piso_y + muro_altura + 0.08)))
		colisao.append(Transform3D(bb * Basis.from_scale(Vector3(PAREDE, altura_total, comp)), pa(meio.x, meio.y, piso_y + altura_total * 0.5)))
		var n := maxi(int(round(comp / 7.0)), 1)
		for k in n + 1:
			var q := a + d * (float(k) / n)
			pedra.append(Transform3D(bb * Basis.from_scale(Vector3(1.4, altura_total + 0.3, 1.4)), pa(q.x, q.y, piso_y + (altura_total + 0.3) * 0.5)))
			capa.append(Transform3D(bb * Basis.from_scale(Vector3(1.7, 0.25, 1.7)), pa(q.x, q.y, piso_y + altura_total + 0.42)))
			var topo := pa(q.x, q.y, piso_y + altura_total + 0.55)
			if k % 3 == 1:
				braseiros.append(topo)
			else:
				pontas.append(Transform3D(Basis.from_scale(Vector3(2.2, 1.3, 2.2)), topo + Vector3.UP * 0.65))
		var y0 := piso_y + muro_altura + 0.16
		for trilho: float in [0.15, grade_altura * 0.5, grade_altura - 0.35]:
			ferro.append(Transform3D(bb * Basis.from_scale(Vector3(0.1, 0.14, comp)), pa(meio.x, meio.y, y0 + trilho)))
		var barras := int(comp / 0.3)
		for k in barras:
			var q := a + d * ((k + 0.5) / barras)
			ferro.append(Transform3D(bb * Basis.from_scale(Vector3(0.06, grade_altura, 0.06)), pa(q.x, q.y, y0 + grade_altura * 0.5)))
			var alt_p := 0.35 + 0.2 * fmod(k * 0.618, 1.0)
			pontas.append(Transform3D(Basis.from_scale(Vector3(0.9, alt_p, 0.9)), pa(q.x, q.y, y0 + grade_altura + alt_p * 0.5)))
		# Pontas tortas viradas para dentro, cravadas na capa do muro
		var dentro := (centro - pa(meio.x, meio.y, 0.0)).normalized()
		var ne := int(comp / 0.7)
		for k in ne:
			var q := a + d * ((k + 0.5) / ne)
			var inclina := 0.55 + 0.25 * fmod(k * 0.377, 1.0)
			var eixo_p := (Vector3.UP * cos(inclina) + dentro * sin(inclina)).normalized()
			var comp_p := 0.7 + 0.5 * fmod(k * 0.713, 1.0)
			var base_p := pa(q.x, q.y, piso_y + muro_altura + 0.12) + dentro * (PAREDE * 0.4)
			pontas.append(Transform3D(ComplexoArena._base_eixo(eixo_p) * Basis.from_scale(Vector3(1.3, comp_p, 1.3)), base_p + eixo_p * comp_p * 0.5))
	var mat := _material_pedra()
	ComplexoLancamento.criar_multimesh(self, pedra, mat)
	var mat_capa := _material_pedra()
	mat_capa.set_shader_parameter("cor_pedra", Color(0.7, 0.58, 0.47))
	ComplexoLancamento.criar_multimesh(self, capa, mat_capa)
	ComplexoLancamento.criar_multimesh(self, ferro, ComplexoLancamento._material_metal(Color(0.07, 0.065, 0.06), 0.85, 0.55))
	ComplexoLancamento.adicionar_colisoes(corpo, colisao)
	var ferrugem := ComplexoLancamento._material_metal(Color(0.3, 0.14, 0.07), 0.6, 0.8)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.05
	cone.height = 1.0
	cone.radial_segments = 5
	cone.rings = 1
	_instancias(cone, pontas, ferrugem)
	var cesto := CylinderMesh.new()
	cesto.top_radius = 0.6
	cesto.bottom_radius = 0.32
	cesto.height = 0.55
	cesto.radial_segments = 10
	cesto.cap_top = false
	var cestos: Array[Transform3D] = []
	for i in braseiros.size():
		var p: Vector3 = braseiros[i]
		cestos.append(Transform3D(Basis.IDENTITY, p + Vector3.UP * 0.05))
		Fogo.criar(self, p + Vector3.UP * 0.25, 0.4, 2.2, 22, 0.9)
		if i % 3 == 0:
			var luz := OmniLight3D.new()
			luz.light_color = Color(1.0, 0.5, 0.18)
			luz.light_energy = 2.5
			luz.omni_range = 14.0
			luz.shadow_enabled = false
			luz.position = p + Vector3.UP * 1.2
			add_child(luz)
	_instancias(cesto, cestos, ferrugem)


func _instancias(malha: Mesh, transformacoes: Array[Transform3D], mat: Material) -> void:
	if transformacoes.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malha
	mm.instance_count = transformacoes.size()
	for i in transformacoes.size():
		mm.set_instance_transform(i, transformacoes[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


## Buracos da morte: poço de pedra de 22 m com fogo alto no fundo, brasa e luz vermelha.
func _montar_buracos() -> void:
	var fundo := maxf(piso_y - 22.0, chao_y + 1.0)
	for b in buracos:
		var r: float = b[1]
		var c := pa(b[0].x, b[0].y, piso_y)
		var poco := CylinderMesh.new()
		poco.top_radius = r
		poco.bottom_radius = r
		poco.height = piso_y - fundo
		poco.radial_segments = 40
		poco.rings = 1
		poco.cap_top = false
		var mi := MeshInstance3D.new()
		mi.mesh = poco
		mi.material_override = _material_pedra()
		mi.position = Vector3(c.x, (piso_y + fundo) * 0.5, c.z)
		add_child(mi)
		var brasa := CylinderMesh.new()
		brasa.top_radius = r
		brasa.bottom_radius = r
		brasa.height = 0.4
		var mb := MeshInstance3D.new()
		mb.mesh = brasa
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.08, 0.03, 0.02)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.28, 0.05)
		mat.emission_energy_multiplier = 2.2
		mb.material_override = mat
		mb.position = Vector3(c.x, fundo + 0.2, c.z)
		add_child(mb)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.25, 0.08)
		luz.light_energy = 12.0
		luz.omni_range = piso_y - fundo + 8.0
		luz.shadow_enabled = false
		luz.position = Vector3(c.x, fundo + 8.0, c.z)
		add_child(luz)
		Fogo.criar(self, Vector3(c.x, fundo + 0.5, c.z), r * 0.75, 16.0, 90, r * 1.1)


func _montar_impulsos() -> void:
	for im in impulsos:
		var f := dir_mundo(im[1])
		var placa := PlaneMesh.new()
		placa.size = Vector2(IMPULSO_MEIO.y * 2.0, IMPULSO_MEIO.x * 2.0)
		var mi := MeshInstance3D.new()
		mi.mesh = placa
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/impulso.gdshader")
		mat.set_shader_parameter("cor", Color(0.1, 0.85, 1.0) if im[2] else Color(1.0, 0.12, 0.05))
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis.looking_at(f, Vector3.UP), pa(im[0].x, im[0].y, piso_y + 0.03))
		add_child(mi)


func _montar_vagas() -> void:
	for v in vagas:
		var f := dir_mundo(deg_to_rad(float(v[2])))
		var lado := f.cross(Vector3.UP).normalized()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.0, 0.06, 0.22)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		var mat := ComplexoLancamento._material_luz(Color(0.2, 0.2, 0.2), 0.0)
		mi.material_override = mat
		mi.transform = Transform3D(Basis(lado, Vector3.UP, -f), pa(float(v[0]), float(v[1]), piso_y + 0.03) - f * 3.15)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_leds_vagas.append(mat)


## Portão da saída: torres de pedra com LED, placa com o nome e semáforo virado para dentro.
func _montar_portao() -> void:
	var g := saida_largura * 0.5 + 1.6
	var altura := muro_altura + grade_altura + 4.0
	var b := Basis.looking_at(frente, Vector3.UP)
	var x := comprimento + PAREDE * 0.5
	var pedra: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(3.2, altura, 3.2)), pa(x, g * s, piso_y + altura * 0.5)))
		ComplexoLancamento.criar_multimesh(self, [Transform3D(b * Basis.from_scale(Vector3(0.12, altura - 2.0, 0.12)), pa(x - 1.62, (g - 1.62) * s, piso_y + altura * 0.5))], ComplexoLancamento._material_luz(COR_EVENTO, 5.0), false)
	ComplexoLancamento.criar_multimesh(self, pedra, _material_pedra())
	ComplexoLancamento.adicionar_colisoes(corpo, pedra)
	var para_dentro := Basis.looking_at(-frente, Vector3.UP)
	var leitura := Basis.looking_at(frente, Vector3.UP)
	var placa := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(g * 2.0 + 3.2, 2.4, 0.3)
	placa.mesh = bm
	placa.material_override = ComplexoLancamento._material_metal(Color(0.03, 0.03, 0.035), 0.4, 0.5)
	placa.transform = Transform3D(para_dentro, pa(x - 2.0, 0.0, piso_y + altura + 0.2))
	add_child(placa)
	if nome_placa != "":
		var texto := Label3D.new()
		texto.text = nome_placa
		texto.font = load("res://assets/fontes/RacingSansOne-Regular.ttf")
		texto.font_size = 150
		texto.pixel_size = minf(0.009, bm.size.x * 0.9 / (texto.text.length() * 150.0 * 0.6))
		texto.outline_size = 20
		texto.modulate = Color(1.6, 0.8, 0.25)
		texto.transform = Transform3D(leitura, pa(x - 2.18, 0.0, piso_y + altura + 0.2))
		add_child(texto)
	var caixa := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(7.6, 2.1, 0.7)
	caixa.mesh = cm
	caixa.material_override = ComplexoLancamento._material_metal(Color(0.03, 0.03, 0.035), 0.3, 0.6)
	caixa.transform = Transform3D(para_dentro, pa(x - 2.2, 0.0, piso_y + altura - 2.6))
	add_child(caixa)
	var lampada := CylinderMesh.new()
	lampada.top_radius = 0.75
	lampada.bottom_radius = 0.75
	lampada.height = 0.25
	lampada.radial_segments = 24
	for k in 3:
		var l := MeshInstance3D.new()
		l.mesh = lampada
		l.transform = Transform3D(para_dentro * Basis(Vector3.RIGHT, PI * 0.5), pa(x - 2.62, (k - 1) * 2.3, piso_y + altura - 2.6))
		add_child(l)
		semaforo_lampadas.append(l)


# ------------------------------------------------------------------ navegação dos bots

func _montar_nav() -> void:
	_nav_x_max = comprimento + 30.0
	_nav_nx = int(ceil(_nav_x_max / CELULA)) + 1
	_nav_nl = int(ceil(largura_arena / CELULA)) + 1
	var n := _nav_nx * _nav_nl
	_nav.resize(n)
	var custo := PackedFloat32Array()
	custo.resize(n)
	var fila: Array[int] = []
	var na_fila := PackedByteArray()
	na_fila.resize(n)
	for i in _nav_nx:
		for j in _nav_nl:
			var k := i * _nav_nl + j
			var q := _nav_q(i, j)
			custo[k] = _custo_celula(q)
			_nav[k] = INF
			if custo[k] < INF and q.x >= _nav_x_max - 3.0:
				_nav[k] = 0.0
				fila.append(k)
				na_fila[k] = 1
	var viz := [[1, 0, 1.0], [-1, 0, 1.0], [0, 1, 1.0], [0, -1, 1.0], [1, 1, 1.414], [1, -1, 1.414], [-1, 1, 1.414], [-1, -1, 1.414]]
	var cab := 0
	while cab < fila.size():
		var k: int = fila[cab]
		cab += 1
		na_fila[k] = 0
		var i := k / _nav_nl
		var j := k % _nav_nl
		for v: Array in viz:
			var i2: int = i + v[0]
			var j2: int = j + v[1]
			if i2 < 0 or j2 < 0 or i2 >= _nav_nx or j2 >= _nav_nl:
				continue
			var k2 := i2 * _nav_nl + j2
			if custo[k2] == INF:
				continue
			var nd: float = _nav[k] + float(v[2]) * CELULA * custo[k2]
			if nd < _nav[k2]:
				_nav[k2] = nd
				if na_fila[k2] == 0:
					na_fila[k2] = 1
					fila.append(k2)


func _nav_q(i: int, j: int) -> Vector2:
	return Vector2(i * CELULA, -largura_arena * 0.5 + j * CELULA)


func _custo_celula(q: Vector2) -> float:
	if q.x > comprimento - 1.0:
		if absf(q.y) > saida_largura * 0.5 - 2.0:
			return INF
	elif q.x < 1.5 or absf(q.y) > largura_arena * 0.5 - 1.8:
		return INF
	var c := 1.0
	var fora_vao := absf(q.y) - (saida_largura * 0.5 - 2.5)
	if q.x < comprimento and fora_vao > 0.0:
		var d_frente := comprimento - q.x
		if d_frente < 4.0:
			return INF
		if d_frente < 16.0:
			c += (16.0 - d_frente) * 0.35 * minf(fora_vao / 4.0, 1.0)
	for b in buracos:
		var d: float = q.distance_to(b[0]) - float(b[1])
		if d < 3.5:
			return INF
		if d < 10.0:
			c += (10.0 - d) * 0.5
	for im in impulsos:
		var dq: Vector2 = q - im[0]
		var f := Vector2(cos(im[1]), sin(im[1]))
		if absf(dq.dot(f)) < IMPULSO_MEIO.x + 1.5 and absf(dq.dot(Vector2(-f.y, f.x))) < IMPULSO_MEIO.y + 1.5:
			c = c + 12.0 if not im[2] else c * 0.5
	return c


func _nav_valor(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= _nav_nx or j >= _nav_nl:
		return INF
	return _nav[i * _nav_nl + j]


func rumo_saida(p: Vector3, passos := 5) -> Vector3:
	var l := local(p)
	var i := clampi(int(round(l.x / CELULA)), 0, _nav_nx - 1)
	var j := clampi(int(round((l.y + largura_arena * 0.5) / CELULA)), 0, _nav_nl - 1)
	if _nav_valor(i, j) == INF:
		var melhor := Vector2i(i, j)
		var melhor_d := INF
		for di in range(-4, 5):
			for dj in range(-4, 5):
				if _nav_valor(i + di, j + dj) < INF and di * di + dj * dj < melhor_d:
					melhor_d = di * di + dj * dj
					melhor = Vector2i(i + di, j + dj)
		i = melhor.x
		j = melhor.y
	for s in passos:
		var atual := _nav_valor(i, j)
		var bi := i
		var bj := j
		for di in range(-1, 2):
			for dj in range(-1, 2):
				var v := _nav_valor(i + di, j + dj)
				if v < atual:
					atual = v
					bi = i + di
					bj = j + dj
		if bi == i and bj == j:
			break
		i = bi
		j = bj
	var q := _nav_q(i, j)
	return pa(q.x, q.y, p.y)
