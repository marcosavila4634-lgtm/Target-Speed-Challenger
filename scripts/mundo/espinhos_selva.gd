class_name EspinhosSelva
extends Node3D
## Espinhos em volta da plataforma da cobra (Serpent's Climb, pedido do dono 2026-10-08): o topo da pirâmide
## deixou de explodir o carro, e dava para contornar a cerca por fora (pelo terraço da pirâmide e pela borda de
## pedra junto à grade) e sair pela ponte sem passar pela cobra. Agora a faixa toda em volta do recinto é um
## campo de espinhos de pedra: encostar explode (grupo "mortal"). Ficam livres só o corredor da pista que chega
## (entradas do recinto) e o da saída.
## Config: percursos.N.plataforma.espinhos = {"passo": 1.5 (m entre espinhos), "folga": 4 (m além da pista)}.

const BORDA := 3.0        # largura da borda de pedra do recinto além da grade (parede + pedestal)
const ALTO_MORTE := 1.8   # altura da caixa que mata, a partir do chão dos espinhos


static func montar(plat: Recinto, terreno: Terreno, cfg: Dictionary) -> void:
	var no := EspinhosSelva.new()
	no.name = "Espinhos"
	plat.add_child(no)
	no._montar(plat, terreno, cfg)


func _montar(plat: Recinto, terreno: Terreno, cfg: Dictionary) -> void:
	var passo := float(cfg.get("passo", 1.5))
	var folga := float(cfg.get("folga", 4.0))
	var meia := plat.largura_arena * 0.5
	var comp := plat.comprimento
	var rng := RandomNumberGenerator.new()
	rng.seed = 90817
	# Até onde vai o terraço em volta do recinto: anda para fora até o chão cair (a beira do topo da pirâmide)
	var alcance := 0.0
	while alcance < 60.0:
		var q := plat.pa(comp * 0.5, -(meia + BORDA + alcance + 1.0), 0.0)
		if terreno.altura_em(q.x, q.z) < plat.piso_y - 12.0:
			break
		alcance += 1.0
	if alcance < 2.0:
		return   # recinto sem terraço em volta (em pilares): nada a fechar
	# Corredores livres: [x mínimo, x máximo, lat mínimo, lat máximo] no referencial do recinto
	var livres: Array[Rect2] = []
	livres.append(Rect2(comp, -(plat.saida_largura * 0.5 + folga), alcance + BORDA + 5.0, plat.saida_largura + folga * 2.0))   # saída (frente)
	for e: Array in plat.entradas:
		var lado := signf(float(e[0]))
		var ex := float(e[1])
		var larg := float(e[2]) + folga * 2.0
		var l0 := meia if lado > 0.0 else -(meia + BORDA + alcance + 5.0)
		livres.append(Rect2(ex - larg * 0.5, l0, larg, BORDA + alcance + 5.0))
	var b := Basis.looking_at(plat.frente, Vector3.UP)
	var xfs: Array[Transform3D] = []
	var cores: Array[Color] = []
	var x0 := -(BORDA + alcance)
	var x1 := comp + BORDA + alcance
	var l1 := meia + BORDA + alcance
	var x := x0
	while x <= x1:
		var lat := -l1
		while lat <= l1:
			var px := x + rng.randf_range(-0.45, 0.45) * passo
			var pl := lat + rng.randf_range(-0.45, 0.45) * passo
			lat += passo
			var dentro := px > -0.6 and px < comp + 0.6 and absf(pl) < meia + 0.6   # o recinto (e a grade)
			if dentro or _em_livre(livres, px, pl):
				continue
			var na_borda := px > -BORDA and px < comp + BORDA and absf(pl) < meia + BORDA
			var p := plat.pa(px, pl, plat.piso_y)
			if not na_borda:
				var h := terreno.altura_em(p.x, p.z)
				if h < plat.piso_y - 12.0:
					continue   # passou da beira do terraço
				p.y = h
			# Mais densos e menores na borda de pedra; no terraço, maiores
			if na_borda and rng.randf() < 0.25:
				continue
			var alto := rng.randf_range(1.0, 1.8) if na_borda else rng.randf_range(1.8, 3.8)
			if rng.randf() < 0.07:
				alto *= 1.6   # um espinho grande de vez em quando
			var grosso := alto * rng.randf_range(0.11, 0.17)
			var tomba := Basis(Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.42))
			var giro := Basis(Vector3.UP, rng.randf() * TAU)
			xfs.append(Transform3D(tomba * giro * Basis.from_scale(Vector3(grosso, alto, grosso)), p - Vector3.UP * 0.15))
			var tom := rng.randf_range(0.75, 1.15)
			cores.append(Color(tom, tom * rng.randf_range(0.92, 1.0), tom * rng.randf_range(0.85, 1.0)))
		x += passo
	_malhas(xfs, cores)
	# Caixas que matam: a borda de pedra (na altura do piso) e o terraço (na altura dele), sem os corredores
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	corpo.add_to_group("mortal")
	add_child(corpo)
	var y_terraco := terreno.altura_em(plat.pa(comp * 0.5, -(meia + BORDA + alcance * 0.5), 0.0).x, plat.pa(comp * 0.5, -(meia + BORDA + alcance * 0.5), 0.0).z)
	var faixas: Array = [
		# [x0, x1, lat0, lat1, chão]
		[x0, -BORDA, -l1, l1, y_terraco], [comp + BORDA, x1, -l1, l1, y_terraco],
		[-BORDA, comp + BORDA, meia + BORDA, l1, y_terraco], [-BORDA, comp + BORDA, -l1, -(meia + BORDA), y_terraco],
		[-BORDA, -0.8, -(meia + BORDA), meia + BORDA, plat.piso_y], [comp + 0.8, comp + BORDA, -(meia + BORDA), meia + BORDA, plat.piso_y],
		[-0.8, comp + 0.8, meia + 0.8, meia + BORDA, plat.piso_y], [-0.8, comp + 0.8, -(meia + BORDA), -(meia + 0.8), plat.piso_y],
	]
	for f: Array in faixas:
		for r: Rect2 in _recortar(Rect2(float(f[0]), float(f[2]), float(f[1]) - float(f[0]), float(f[3]) - float(f[2])), livres):
			if r.size.x < 0.5 or r.size.y < 0.5:
				continue
			var cs := CollisionShape3D.new()
			var caixa := BoxShape3D.new()
			caixa.size = Vector3(r.size.y, ALTO_MORTE, r.size.x)   # (lateral, alto, frente) no referencial de looking_at
			cs.shape = caixa
			cs.transform = Transform3D(b, plat.pa(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5, float(f[4]) + ALTO_MORTE * 0.5))
			corpo.add_child(cs)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[ESPINHOS] %d espinhos em volta de %s, terraço até %.0f m da grade (y %.1f)" % [xfs.size(), plat.name, alcance + BORDA, y_terraco])


static func _em_livre(livres: Array[Rect2], x: float, lat: float) -> bool:
	for r: Rect2 in livres:
		if r.has_point(Vector2(x, lat)):
			return true
	return false


## O retângulo sem os corredores livres (corta em pedaços).
static func _recortar(r: Rect2, livres: Array[Rect2]) -> Array[Rect2]:
	var pedacos: Array[Rect2] = [r]
	for l: Rect2 in livres:
		var novos: Array[Rect2] = []
		for p: Rect2 in pedacos:
			if not p.intersects(l):
				novos.append(p)
				continue
			var i := p.intersection(l)
			# sobra em x antes e depois do corredor, e em lat acima e abaixo
			if i.position.x > p.position.x:
				novos.append(Rect2(p.position.x, p.position.y, i.position.x - p.position.x, p.size.y))
			if i.end.x < p.end.x:
				novos.append(Rect2(i.end.x, p.position.y, p.end.x - i.end.x, p.size.y))
			if i.position.y > p.position.y:
				novos.append(Rect2(i.position.x, p.position.y, i.size.x, i.position.y - p.position.y))
			if i.end.y < p.end.y:
				novos.append(Rect2(i.position.x, i.end.y, i.size.x, p.end.y - i.end.y))
		pedacos = novos
	return pedacos


## Espinhos de pedra escura com a ponta clara (MultiMesh em blocos, para somirem de longe por bloco).
func _malhas(xfs: Array[Transform3D], cores: Array[Color]) -> void:
	if xfs.is_empty():
		return
	# Cone facetado de 1 m de altura e 1 m de raio na base (a escala de cada cópia dá o tamanho), pé em y = 0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lados := 6
	for k in lados:
		var a0 := TAU * k / lados
		var a1 := TAU * (k + 1) / lados
		var p0 := Vector3(cos(a0), 0.0, sin(a0))
		var p1 := Vector3(cos(a1), 0.0, sin(a1))
		var meio0 := p0 * 0.55 + Vector3.UP * 0.5
		var meio1 := p1 * 0.55 + Vector3.UP * 0.5
		# base escura → meio → ponta clara (cor no vértice)
		for tri: Array in [[p0, meio0, p1, 0.0, 0.5, 0.0], [p1, meio0, meio1, 0.0, 0.5, 0.5], [meio0, Vector3.UP, meio1, 0.5, 1.0, 0.5]]:
			for j in 3:
				var u: float = tri[3 + j]
				st.set_color(Color(0.16, 0.11, 0.08).lerp(Color(0.95, 0.88, 0.68), u))
				st.add_vertex(tri[j])
	st.generate_normals()
	var malha := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var blocos := {}
	for i in xfs.size():
		var ch := Vector2i(floori(xfs[i].origin.x / 40.0), floori(xfs[i].origin.z / 40.0))
		if not blocos.has(ch):
			blocos[ch] = []
		blocos[ch].append(i)
	for ch: Vector2i in blocos:
		var lista: Array = blocos[ch]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = malha
		mm.instance_count = lista.size()
		for k in lista.size():
			mm.set_instance_transform(k, global_transform.affine_inverse() * xfs[lista[k]])
			mm.set_instance_color(k, cores[lista[k]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.visibility_range_end = 700.0
		mmi.visibility_range_end_margin = 80.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mmi)
