extends RefCounted
## Túnel de gelo do Frozen Peak (armadilha "pingentes"), pela arte do dono em
## assets/frozen/extruturas/entradagelo.png e entradagelo2.png: arco alto de blocos de gelo empilhados
## (pedras de cristal azul, cada uma de um tamanho e virada para fora), neve grossa por cima dos blocos,
## casca de gelo ciano aceso por dentro, cristais pontudos saindo do alto e pingentes pendurados no teto.
## As pernas descem até o chão. Tudo em geometria (PortaoGelo empresta as peças e o gelo).
## Coordenadas do nó: x = lateral, y = cima, z = ao longo da estrada (comprimento `comp`, centrado).

const PORTAO := "res://scripts/mundo/portao_gelo.gd"


## Perfil de dentro do arco: meia largura `w` no chão, altura `h` no meio, topo achatado (p = 3).
static func teto(x: float, w: float, h: float) -> float:
	var q := clampf(absf(x) / w, 0.0, 1.0)
	return h * pow(1.0 - pow(q, 3.0), 1.0 / 3.0)


## Monta o túnel em `pai`. `fundo` = y local do chão (as pernas descem até ele). Devolve as caixas de
## colisão das pernas e do teto (espaço de `pai`).
static func montar(pai: Node3D, w: float, h: float, comp: float, fundo: float, semente: int) -> Array[Transform3D]:
	var geo: Node3D = load(PORTAO).new()
	var rng: RandomNumberGenerator = geo.get("_rng")
	rng.seed = semente
	var st_c: SurfaceTool = geo.get("_st_cristal")
	var st_n: SurfaceTool = geo.get("_st_neve")
	var st_m: SurfaceTool = geo.get("_st_moldura")
	for st: SurfaceTool in [st_c, st_n, st_m]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col: Array[Transform3D] = []
	var esp := 4.5   # espessura do arco
	# Casca de dentro (teto e paredes): faixas ao longo do arco, gelo ciano aceso
	var n := 26
	for k in n:
		var x0 := lerpf(-w, w, float(k) / n)
		var x1 := lerpf(-w, w, float(k + 1) / n)
		var y0 := teto(x0, w, h)
		var y1 := teto(x1, w, h)
		var o0 := Vector2(x0 / w, y0 / h * 1.4).normalized()
		var o1 := Vector2(x1 / w, y1 / h * 1.4).normalized()
		var zz := comp * 0.5 + 0.4
		geo.call("_hexaedro", st_m, [Vector3(x0, y0, -zz), Vector3(x1, y1, -zz), Vector3(x1 + o1.x * 1.6, y1 + o1.y * 1.6, -zz), Vector3(x0 + o0.x * 1.6, y0 + o0.y * 1.6, -zz),
			Vector3(x0, y0, zz), Vector3(x1, y1, zz), Vector3(x1 + o1.x * 1.6, y1 + o1.y * 1.6, zz), Vector3(x0 + o0.x * 1.6, y0 + o0.y * 1.6, zz)])
	# Blocos de gelo empilhados ao longo do arco: duas camadas (a de fora com blocos maiores), quatro
	# fileiras ao longo da estrada; embaixo o monte se espalha para os lados, como na arte
	for camada in 2:
		var filas := 4 if camada == 0 else 3
		for fila in filas:
			var z := lerpf(-comp * 0.5, comp * 0.5, (fila + 0.5) / filas) + rng.randf_range(-0.8, 0.8)
			var passos := 13 if camada == 0 else 9
			for k in passos + 1:
				var x := lerpf(-w - 0.4, w + 0.4, (float(k) + rng.randf_range(-0.3, 0.3)) / passos)
				var y := teto(x, w, h)
				var fora := Vector2(x / w, y / h * 1.4).normalized()
				var grosso := 1.0 + 0.6 * (1.0 - fora.y)   # mais grosso embaixo
				var r := rng.randf_range(2.4, 3.4) * grosso * (1.0 if camada == 0 else 1.25)
				var dist := (esp * 0.45 if camada == 0 else esp * 1.05) * grosso
				var c := Vector3(x + fora.x * dist, y + fora.y * dist, z)
				var eixo := (Vector3(fora.x, fora.y, rng.randf_range(-0.25, 0.25)) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.0, 0.5), 0.0)).normalized()
				_bloco_neve(geo, st_c, st_n, c - eixo * r * 0.55, eixo, r, rng)
	for s: float in [-1.0, 1.0]:
		for k in 7:
			var dx := rng.randf_range(0.5, 8.0)
			var r := rng.randf_range(2.0, 3.6) * (1.0 - dx / 14.0)
			var p := Vector3(s * (w + esp * 0.5 + dx), rng.randf_range(-0.8, 0.2) + (6.0 - dx) * 0.35, rng.randf_range(-comp * 0.6, comp * 0.6))
			_bloco_neve(geo, st_c, st_n, p - Vector3.UP * r * 0.4, Vector3(s * rng.randf_range(0.1, 0.5), 1.0, rng.randf_range(-0.3, 0.3)).normalized(), r, rng)
	for fila in 3:
		var z := lerpf(-comp * 0.5, comp * 0.5, (fila + 0.5) / 3.0)
		# Cristais pontudos saindo do alto
		for k in 3:
			var x := rng.randf_range(-w * 0.8, w * 0.8)
			var y := teto(x, w, h) + esp * 1.4
			var inc := Vector3(rng.randf_range(-0.4, 0.4), 1.0, rng.randf_range(-0.3, 0.3)).normalized()
			var hc := rng.randf_range(2.4, 4.2)
			geo.call("_prisma", st_c, Vector3(x, y, z), inc, 6, [Vector2(0.0, hc * 0.22), Vector2(hc * 0.6, hc * 0.18)], hc * 0.4, 0.12, Vector2.ONE)
	# Pernas até o chão e pedras de gelo com neve no pé, fora da estrada
	for s: float in [-1.0, 1.0]:
		for fila in 3:
			var z := lerpf(-comp * 0.5, comp * 0.5, (fila + 0.5) / 3.0)
			geo.call("_caixa_cristal", Vector3(s * (w + esp * 0.55), fundo - 0.5, z), esp * 0.62, comp / 6.0 + 0.6, -fundo + 2.5)
			var r := rng.randf_range(1.8, 2.6)
			var p := Vector3(s * (w + rng.randf_range(0.6, 1.8)), r * 0.35 - 0.4, z + rng.randf_range(-1.0, 1.0))
			_bloco_neve(geo, st_c, st_n, p - Vector3.UP * r * 0.5, Vector3(s * 0.3, 1.0, 0.0).normalized(), r, rng)
		col.append(Transform3D(Basis.from_scale(Vector3(esp * 1.4, h * 0.75 - fundo, comp + 1.0)), Vector3(s * (w + esp * 0.55), (h * 0.75 + fundo) * 0.5, 0.0)))
	col.append(Transform3D(Basis.from_scale(Vector3(w * 2.0 + esp * 2.0, esp, comp + 1.0)), Vector3(0.0, h + esp * 0.5, 0.0)))
	# Pingentes fixos no teto (sem descer na faixa dos carros: no máximo até 9 m) e nas bocas do túnel
	for face: float in [-1.0, 1.0]:
		var x := -w + 0.4
		while x < w - 0.4:
			x += rng.randf_range(0.22, 0.45)
			var y := teto(x, w, h) - 0.1
			var l := rng.randf_range(0.4, 1.6) if rng.randf() < 0.75 else rng.randf_range(1.8, 3.4)
			l = minf(l, y - 9.0) if absf(x) < w - 0.8 else minf(l, 1.2)
			geo.call("_pingente", Vector3(x, y, face * (comp * 0.5 + rng.randf_range(0.0, 0.5))), l, 0.07 + l * 0.035)
	var z2 := -comp * 0.5
	while z2 < comp * 0.5:
		z2 += rng.randf_range(0.6, 1.2)
		for s: float in [-1.0, 1.0]:
			var x := s * rng.randf_range(w * 0.82, w * 0.97)
			geo.call("_pingente", Vector3(x, teto(x, w, h) - 0.1, z2), rng.randf_range(0.4, 1.4), 0.08)
	var portao = load(PORTAO)
	for par: Array in [[st_c, portao._material("geleira")], [st_n, Gelo.material(Gelo.Mat.NEVE)], [st_m, portao._material("cristal")]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (par[0] as SurfaceTool).commit()
		mi.material_override = par[1]
		pai.add_child(mi)
	# Luz ciano de dentro do gelo
	for z: float in [-comp * 0.3, comp * 0.3]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.35, 0.8, 1.0)
		l.light_energy = 1.6
		l.omni_range = w * 2.2
		l.shadow_enabled = false
		l.position = Vector3(0.0, h * 0.7, z)
		pai.add_child(l)
	geo.free()
	return col


## Bloco de gelo com neve assentada no alto quando ele olha para cima (a neve acompanha o topo do bloco).
static func _bloco_neve(geo: Node3D, st_c: SurfaceTool, st_n: SurfaceTool, base: Vector3, eixo: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var alto := _bloco(geo, st_c, base, eixo, r, rng)
	if eixo.y < 0.3:
		return
	var topo := base + eixo * alto * 0.86 - Vector3.UP * r * 0.15
	var rn := r * lerpf(0.6, 0.9, eixo.y)
	geo.call("_prisma", st_n, topo, Vector3.UP, 16,
		[Vector2(0.0, rn), Vector2(r * 0.18, rn * 0.95), Vector2(r * 0.34, rn * 0.7), Vector2(r * 0.45, rn * 0.35)], r * 0.06, 0.14,
		Vector2(1.0, rng.randf_range(0.75, 1.0)), true, true)


## Bloco de gelo arredondado (pedra de cristal) com a base em `base`, crescendo ao longo de `eixo`.
static func _bloco(geo: Node3D, st: SurfaceTool, base: Vector3, eixo: Vector3, r: float, rng: RandomNumberGenerator) -> float:
	var alto := r * rng.randf_range(1.1, 1.6)
	geo.call("_prisma", st, base, eixo, rng.randi_range(6, 8),
		[Vector2(0.0, r * 0.75), Vector2(alto * 0.3, r * 1.05), Vector2(alto * 0.7, r * 0.95), Vector2(alto * 0.92, r * 0.6)], alto * 0.12, 0.2,
		Vector2(1.0, rng.randf_range(0.75, 1.0)))
	return alto


## Estalactites de uma faixa (penduradas em `pai`, ponta para baixo a partir de y = `topo`), numa área
## de `larg` x `comp`. Devolve o nó com elas (para esconder no estouro e crescer de novo).
static func estalactites(pai: Node3D, larg: float, comp: float, topo: float, semente: int) -> Node3D:
	var geo: Node3D = load(PORTAO).new()
	var rng: RandomNumberGenerator = geo.get("_rng")
	rng.seed = semente
	var st: SurfaceTool = geo.get("_st_cristal")
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := maxi(int(larg / 1.25), 2)
	var nz := maxi(int(comp / 1.5), 3)
	for a in nx:
		for k in nz:
			var x := (a - (nx - 1) * 0.5) * (larg / nx) + rng.randf_range(-0.3, 0.3)
			var z := (k - (nz - 1) * 0.5) * (comp / nz) + rng.randf_range(-0.4, 0.4)
			var l := rng.randf_range(2.0, 3.8)
			var r := rng.randf_range(0.28, 0.48)
			geo.call("_prisma", st, Vector3(x, topo + 0.3, z), Vector3.DOWN, rng.randi_range(5, 7),
				[Vector2(0.0, r), Vector2(l * 0.35, r * 0.7), Vector2(l * 0.7, r * 0.35)], l * 0.3 + 0.3, 0.15, Vector2.ONE, false)
	var no := Node3D.new()
	no.name = "Estalactites"
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = load(PORTAO)._material("letra")
	no.add_child(mi)
	pai.add_child(no)
	geo.free()
	return no
