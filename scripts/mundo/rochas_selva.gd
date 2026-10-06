class_name RochasSelva
extends Node3D
## Rochas gigantes encostadas nos morros do Serpent's Climb e saindo de dentro deles (pedido do dono,
## 2026-10-05; só em alguns trechos, config selva.etapas.N.rochas). Cada rocha é um sólido feito a partir das
## artes dele (tools/serpents_climb/rochas.gd), com a pele das três vistas (shaders/rocha_arte.gdshader).
## Posição: o ponto da config é levado ao pé do paredão mais próximo; a rocha fica de costas para o morro,
## enterrada nele (parte de trás e de baixo somem dentro da encosta) e com o pé abaixo do chão: nunca flutua.
## Colisão de verdade (malha), sem matar: só o chão continua matando.
## Config: [[x, z, largura (m), modelo, giro extra (graus), enterra (0..1), sobe (m pela parede), alto (estica
## na vertical), fundo (profundidade/largura: 0.45 no paredão, 1 = rocha inteira solta no vale), y da base, rumo,
## encosta (m do eixo da estrada da etapa: a rocha desliza até a face ficar ali, sem encolher), [trecho, m0, m1]
## (o pedaço de estrada em que ela encosta; sem ele, a estrada mais perto)], ...]. Com `sobe`, a rocha fica mais acima na parede, apoiada na encosta e com as costas dentro
## do morro (parece sair dele).

const PASTA := "res://assets/selva/rochas/"
const FUNDO := 0.45   # profundidade (entrando no morro) em relação à largura: o paredão do anel é fino

static var _mats := {}


## livres: [[x, z, raio]] onde nenhuma rocha pode chegar (a cachoeira e a toca da cobra).
static var _livres: Array = []

static func montar(pai: Node3D, terreno: Terreno, lista: Array, dentro := Vector2(INF, INF), livres: Array = []) -> void:
	_livres = livres
	if lista.is_empty():
		return
	var no := RochasSelva.new()
	no.name = "Rochas"
	pai.add_child(no)
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	no.add_child(corpo)
	for r: Array in lista:
		var alvo := Vector2(float(r[0]), float(r[1]))
		if dentro.x < INF:
			alvo = _pe_na_direcao(terreno, dentro, alvo)
		no._rocha(corpo, terreno, alvo, float(r[2]), str(r[3]),
			deg_to_rad(float(r[4]) if r.size() > 4 else 0.0), float(r[5]) if r.size() > 5 else 0.3,
			float(r[6]) if r.size() > 6 else 0.0, float(r[7]) if r.size() > 7 else 1.0, float(r[8]) if r.size() > 8 else FUNDO,
			float(r[9]) if r.size() > 9 and r[9] != null else -INF, float(r[10]) if r.size() > 10 and r[10] != null else INF,
			float(r[11]) if r.size() > 11 and r[11] != null else -1.0, r[12] if r.size() > 12 else [])


static func _material(nome: String) -> ShaderMaterial:
	if _mats.has(nome):
		return _mats[nome]
	var malha := load(PASTA + nome + ".res") as ArrayMesh
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rocha_arte.gdshader")
	for v in ["frente", "lado", "cima"]:
		var img := Recinto.ler_imagem(PASTA + nome + "_" + v + ".png")
		if img:
			img.generate_mipmaps()
			mat.set_shader_parameter(v, ImageTexture.create_from_image(img))
	if malha:
		mat.set_shader_parameter("alto_y", float(malha.get_meta("Y", 1.3)))
		mat.set_shader_parameter("fundo_d", float(malha.get_meta("D", 0.9)))
	_mats[nome] = mat
	return mat


## Pé do paredão perto de `p`: onde a encosta fica íngreme ao subir, procurado num círculo de 140 m.
## Chão do morro sem as construções (pirâmides, colunas): a rocha encosta no morro, não numa pirâmide.
static func _chao(terreno: Terreno, x: float, z: float) -> float:
	return terreno._altura_procedural(x, z)


## Do meio do vale (`dentro`) na direção de `para` até o chão do morro passar de 25 m: o pé do paredão.
## Algum ponto das estradas (todas as etapas) dentro da rocha (com 6 m de folga)?
static var _grade_pista := {}   # Vector2i (células de 40 m) -> [Vector3, ...] pontos das estradas de todas as etapas

## Só as estradas deste percurso ("2", "3"...; vazio = todas: a E1 foi arrumada assim). Da E2 em diante cada
## etapa só desvia da própria pista (as outras não existem nela).
static var so_percurso := ""
static var _grade_de := "-"

static func _pista_perto(c: Vector3, raio: float) -> Array:
	if _grade_de != so_percurso:
		_grade_pista.clear()
		_grade_de = so_percurso
	if _grade_pista.is_empty():
		var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
		for k in percursos:
			if so_percurso != "" and str(k) != so_percurso:
				continue
			for nome_t in ["A", "B", "C"]:
				var pts: Array = (percursos[k] as Dictionary).get("trechos", {}).get(nome_t, [])
				for i in range(1, pts.size()):
					var a := Vector3(float(pts[i - 1][0]), float(pts[i - 1][1]), float(pts[i - 1][2]))
					var b := Vector3(float(pts[i][0]), float(pts[i][1]), float(pts[i][2]))
					var n := maxi(1, ceili(a.distance_to(b) / 6.0))
					for t in n + 1:
						var q := a.lerp(b, float(t) / n)
						var ch := Vector2i(floori(q.x / 40.0), floori(q.z / 40.0))
						if not _grade_pista.has(ch):
							_grade_pista[ch] = []
						_grade_pista[ch].append(q)
	var lista: Array = []
	var r := ceili(raio / 40.0)
	var c0 := Vector2i(floori(c.x / 40.0), floori(c.z / 40.0))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			lista.append_array(_grade_pista.get(c0 + Vector2i(dx, dz), []))
	return lista


## Algum ponto das estradas (todas as etapas, a cada 6 m) dentro da rocha (com 6 m de folga)?
static func _encosta_na_estrada(malha: ArrayMesh, xf: Transform3D) -> bool:
	var cx := malha.get_aabb().grow(6.0 / maxf(xf.basis.x.length(), 0.1))
	var inv := xf.affine_inverse()
	var raio := (xf.basis * malha.get_aabb().size).length() * 0.6 + 10.0
	for p: Vector3 in _pista_perto(xf.origin, raio):
		if cx.has_point(inv * p):
			return true
	return false


static func _invade_livre(malha: ArrayMesh, xf: Transform3D) -> bool:
	var cx := malha.get_aabb()
	var inv := xf.affine_inverse()
	for l: Array in _livres:
		var c := Vector3(float(l[0]), 0.0, float(l[1]))
		var r := float(l[2])
		for k in 9:
			var a := TAU * k / 8.0
			var q := c + (Vector3(cos(a), 0.0, sin(a)) * r if k < 8 else Vector3.ZERO)
			for y in [xf.origin.y + 20.0, xf.origin.y + 80.0, xf.origin.y + 160.0]:
				q.y = y
				if cx.has_point(inv * q):
					return true
	return false


## Rochas gigantes cobrindo os paredões íngremes do vale (pedido do dono: paredão de rocha de verdade, não
## parede pintada): pontos na encosta íngreme espaçados `passo` m, cada um com uma rocha encostada.
static func paredoes(terreno: Terreno, vale: Array, passo: float, livres: Array) -> Array:
	var a := terreno.alturas_interno
	var n := Terreno.N_INTERNO
	var meio := Terreno.MEIO_INTERNO
	var pg := meio * 2.0 / (n - 1)
	var folga := 300.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3131
	var usados: Array[Vector2] = []
	var lista: Array = []
	var mods := ["penhasco_a", "penhasco_b", "penhasco_c"]
	for iz in range(clampi(floori((float(vale[1]) - folga + meio) / pg), 1, n - 2), clampi(ceili((float(vale[3]) + folga + meio) / pg), 1, n - 2)):
		for ix in range(clampi(floori((float(vale[0]) - folga + meio) / pg), 1, n - 2), clampi(ceili((float(vale[2]) + folga + meio) / pg), 1, n - 2)):
			var h := a[iz * n + ix]
			if h < 25.0 or h > 170.0:
				continue
			var gx := (a[iz * n + ix + 1] - a[iz * n + ix - 1]) / (2.0 * pg)
			var gz := (a[(iz + 1) * n + ix] - a[(iz - 1) * n + ix]) / (2.0 * pg)
			if sqrt(gx * gx + gz * gz) < 1.8:
				continue
			var p := Vector2(-meio + ix * pg, -meio + iz * pg)
			var perto := false
			for u in usados:
				if u.distance_squared_to(p) < passo * passo:
					perto = true
					break
			for l: Array in livres:
				perto = perto or p.distance_to(Vector2(float(l[0]), float(l[1]))) < float(l[2]) + 40.0
			if perto:
				continue
			usados.append(p)
			# Duas fileiras no tamanho natural da arte (esticar deixava a pedra em riscos), a de cima apoiada na parede
			var w0 := rng.randf_range(120.0, 170.0)
			lista.append([p.x, p.y, w0, mods[rng.randi() % 3], rng.randf_range(-25.0, 25.0), 0.3, 0.0, rng.randf_range(1.0, 1.3), 0.45])
			# Fileiras de cima mais para a frente (enterra baixo): mais para dentro do morro, o degrau de terra com mata entre
			# elas aparecia como uma fresta no paredão
			lista.append([p.x, p.y, rng.randf_range(110.0, 160.0), mods[rng.randi() % 3], rng.randf_range(-25.0, 25.0), 0.12, 0.0, rng.randf_range(1.0, 1.3), 0.45, h + w0 * 0.3])
			lista.append([p.x, p.y, rng.randf_range(100.0, 140.0), mods[rng.randi() % 3], rng.randf_range(-25.0, 25.0), 0.3, 0.0, rng.randf_range(1.0, 1.3), 0.45, h + w0 * 0.62])
	return lista


static func _pe_na_direcao(terreno: Terreno, dentro: Vector2, para: Vector2) -> Vector2:
	var d := (para - dentro).normalized()
	var h0 := _chao(terreno, dentro.x, dentro.y)
	var t := 0.0
	while t < 900.0 and _chao(terreno, dentro.x + d.x * t, dentro.y + d.y * t) < h0 + 25.0:
		t += 3.0
	return dentro + d * maxf(t - 6.0, 0.0)


static func _pe_do_morro(terreno: Terreno, p: Vector2) -> Array:
	var melhor := p
	var melhor_v := -INF
	for raio in [0.0]:   # o ponto da config já é no morro (desenho do dono): só a orientação sai daqui
		var n := 1 if raio == 0.0 else 16
		for k in n:
			var a := TAU * k / n
			var q: Vector2 = p + Vector2(cos(a), sin(a)) * raio
			var e := 6.0
			var g := Vector2(_chao(terreno, q.x + e, q.y) - _chao(terreno, q.x - e, q.y), _chao(terreno, q.x, q.y + e) - _chao(terreno, q.x, q.y - e)) / (2.0 * e)
			# Íngreme e baixo (o pé, não o alto do morro); perto do ponto pedido vale mais
			var nota: float = minf(g.length(), 2.5) - _chao(terreno, q.x, q.y) / 40.0 - raio / 150.0
			if nota > melhor_v:
				melhor_v = nota
				melhor = q
	var e2 := 10.0
	var gm := Vector2(_chao(terreno, melhor.x + e2, melhor.y) - _chao(terreno, melhor.x - e2, melhor.y), _chao(terreno, melhor.x, melhor.y + e2) - _chao(terreno, melhor.x, melhor.y - e2))
	var para_morro := gm.normalized() if gm.length() > 0.01 else Vector2.UP
	return [melhor, para_morro]


func _rocha(corpo: StaticBody3D, terreno: Terreno, p: Vector2, larg: float, nome: String, giro: float, enterra: float, sobe: float, alto: float, fundo: float, y_base := -INF, rumo := INF, encosta := -1.0, onde: Array = []) -> void:
	var malha := load(PASTA + nome + ".res") as ArrayMesh
	if malha == null:
		push_warning("RochasSelva: falta %s (rodar tools/serpents_climb/rochas.gd)" % nome)
		return
	var pe: Array = _pe_do_morro(terreno, p)
	var c: Vector2 = pe[0]
	var morro: Vector2 = pe[1]
	if rumo < INF:
		morro = Vector2(cos(deg_to_rad(rumo)), sin(deg_to_rad(rumo)))   # direção do morro dada pela config
	# Encolhe até não encostar em nenhuma estrada (nunca em cima da pista)
	for fator in ([1.0] if encosta > 0.0 else [1.0, 0.85, 0.7, 0.55, 0.42]):
		var xf := _xf(terreno, malha, c, morro, larg * fator, giro, enterra, sobe, alto, fundo)
		if y_base > -INF:
			xf.origin.y = maxf(xf.origin.y, y_base)   # apoiada na parede do morro (as costas dentro dele)
		if encosta > 0.0:
			xf = _encostar(malha, xf, encosta, onde)
		elif _encosta_na_estrada(malha, xf) or _invade_livre(malha, xf):
			continue
		if OS.get_environment("TSC_SUB_LOG") != "":
			print("[ROCHA] %s em %s, %.0f m (fator %.2f), pé y %.0f" % [nome, str(Vector2(xf.origin.x, xf.origin.z).round()), larg * fator, fator, xf.origin.y])
		var mi := MeshInstance3D.new()
		mi.mesh = malha
		mi.material_override = _material(nome)
		mi.transform = xf
		mi.visibility_range_end = 3500.0
		add_child(mi)
		# Colisão com a escala já nas faces (forma escalada não colide direito no Godot). Malha leve de colisão
		# (meta "col", tools/serpents_climb/rochas_lod.gd): com a cheia, as ~1100 rochas levavam 30 s na abertura.
		var esc3 := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
		var faces: PackedVector3Array = (malha.get_meta("col", PackedVector3Array()) as PackedVector3Array).duplicate()   # cópia: o array da meta é compartilhado
		if faces.is_empty():
			faces = malha.get_faces()
		for i in faces.size():
			faces[i] = faces[i] * esc3
		var forma_c := ConcavePolygonShape3D.new()
		forma_c.set_faces(faces)
		var forma := CollisionShape3D.new()
		forma.shape = forma_c
		forma.transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
		corpo.add_child(forma)
		return


## Desliza a rocha (no plano) até o ponto dela mais perto da estrada desta etapa ficar a `dist` m do eixo.
## Só conta a parte da rocha da altura da pista para cima (o pé enterrado pode passar embaixo dela).
func _encostar(malha: ArrayMesh, xf: Transform3D, dist: float, onde: Array = []) -> Transform3D:
	var pts: Array = []
	var trechos: Dictionary = (Config.valor("mapa.subida.percursos", {}) as Dictionary).get(str(ComplexoSubida.etapa_percurso + 1), {}).get("trechos", {})
	for nome_t in trechos:
		if not onde.is_empty() and str(onde[0]) != str(nome_t):
			continue
		pts.append(null)   # um trecho não emenda no outro
		var m := 0.0
		var ant = null
		for q in trechos[nome_t]:
			var pq := Vector3(float(q[0]), float(q[1]), float(q[2]))
			if ant != null:
				m += Vector2(pq.x - ant.x, pq.z - ant.z).length()
			ant = pq
			var dentro := onde.is_empty() or (m >= float(onde[1]) and m <= float(onde[2]))
			# só a estrada perto da rocha (e no pedaço pedido); um ponto de fora corta a sequência
			pts.append(pq if dentro and Vector2(pq.x - xf.origin.x, pq.z - xf.origin.z).length() < 450.0 else null)
	if pts.size() < 2:
		return xf
	var verts: PackedVector3Array = malha.get_meta("col", malha.get_faces())
	for passo in 4:
		var menor := INF
		var dir := Vector3.ZERO
		for k in range(0, verts.size(), 3):
			var w := xf * verts[k]
			for j in range(1, pts.size()):
				if pts[j - 1] == null or pts[j] == null:
					continue
				var a: Vector3 = pts[j - 1]
				var b: Vector3 = pts[j]
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var t := clampf(Vector2(w.x - a.x, w.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
				var q := a.lerp(b, t)
				if w.y < q.y - 2.0:
					continue
				var d := Vector2(w.x - q.x, w.z - q.z)
				if d.length() < menor:
					menor = d.length()
					dir = Vector3(-d.x, 0.0, -d.y).normalized()
		if menor == INF or absf(menor - dist) < 0.5:
			break
		xf.origin += dir * (menor - dist)
	return xf


## Transformação da rocha: de costas para o morro (ou girada livre no plano), com o pé enterrado abaixo do
## chão mais baixo embaixo dela (nada flutua).
func _xf(terreno: Terreno, malha: ArrayMesh, c: Vector2, morro: Vector2, larg: float, giro: float, enterra: float, sobe: float, alto: float, fundo: float) -> Transform3D:
	var esc := larg * 0.5   # a malha tem 2 de largura
	var D := float(malha.get_meta("D", 0.9)) * esc * fundo
	var fora := Vector3(-morro.x, 0.0, -morro.y)
	var b := Basis.looking_at(-fora, Vector3.UP).rotated(Vector3.UP, giro)
	var h_pe := _chao(terreno, c.x, c.y)
	var subida := 0.0
	while sobe > 0.0 and subida < 400.0 and _chao(terreno, c.x + morro.x * subida, c.y + morro.y * subida) < h_pe + sobe:
		subida += 2.0
	var centro := c + morro * (subida + D * (0.25 + enterra))
	var baixo := INF
	for k in 16:
		var a := TAU * k / 16.0
		for r in [0.0, 0.35, 0.7, 1.0]:
			var l3 := b * Vector3(cos(a) * esc * r, 0.0, sin(a) * D * r)
			var q: Vector2 = centro + Vector2(l3.x, l3.z)
			baixo = minf(baixo, _chao(terreno, q.x, q.y))
	var y := baixo - float(malha.get_meta("Y", 1.3)) * esc * alto * 0.12   # o pé fica enterrado
	return Transform3D(b * Basis.from_scale(Vector3(esc, esc * alto, esc * fundo)), Vector3(centro.x, y, centro.y))
