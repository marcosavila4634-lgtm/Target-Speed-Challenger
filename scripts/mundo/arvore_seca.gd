class_name ArvoreSeca
extends RefCounted
## Árvore seca gigante (Serpent's Climb, pedido do dono 2026-10-06: "mais realista e cheia de texturas" que a
## árvore de exemplo dele). Tudo gerado aqui: tronco grosso e torto com sapopemas (raízes em tábua) e raízes
## expostas que entram no chão, galhos mortos tortos em 3 níveis com as pontas quebradas e lascadas, o topo
## partido, um galho grosso estendido por cima da beira da estrada (o poleiro do jaguar, JaguarArvore),
## orelhas-de-pau, um oco e cipós secos pendurados. Casca em shaders/arvore_seca.gdshader (placas e fissuras
## em relevo, descascados, líquen, musgo); a malha também tem relevo de verdade (sulcos e nós).

const PASSO := 1.6   # m de casca por repetição do UV (o mesmo valor do shader)

static var _shader: Shader
static var _nv := 0   # vértices já postos no SurfaceTool do tronco (índices do próximo tubo)


## pe: pé do tronco (no chão). rumo: direção (horizontal) do tronco para a estrada. poleiro_y: altura (mundo)
## do topo do galho onde o jaguar fica. alcance: distância horizontal do eixo do tronco até a ponta do galho.
## altura: Callable(x, z) -> chão. Devolve {no, poleiro: Transform3D (pés do jaguar, olhando para a estrada)}.
static func criar(pai: Node3D, pe: Vector3, rumo: Vector3, poleiro_y: float, alcance: float, semente: int, altura: Callable) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var ruido := FastNoiseLite.new()
	ruido.seed = semente
	ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ruido.frequency = 1.0
	rumo = Vector3(rumo.x, 0.0, rumo.z).normalized()
	var raiz := Node3D.new()
	raiz.name = "ArvoreSeca"
	pai.add_child(raiz)
	raiz.global_transform = Transform3D(Basis.IDENTITY, pe)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_nv = 0
	var lado := rumo.cross(Vector3.UP).normalized()

	# --- Tronco: sobe grosso e torto até a forquilha (na altura do galho do poleiro), de onde saem os galhos
	# mestres; acima dela o tronco continua mais fino e termina partido
	var h_galho := poleiro_y - pe.y
	var y_f := h_galho - 3.5
	var alto := y_f + rng.randf_range(13.0, 17.0)
	var r0 := clampf(y_f / 15.0, 2.6, 4.2)   # quanto mais alta (estrada em ponte), mais grossa
	var tronco := PackedVector3Array()
	var raios_t := PackedFloat32Array()
	var n_t := int(alto / 1.0)
	for k in n_t + 1:
		var u := float(k) / n_t
		var y := -1.5 + u * (alto + 1.5)
		var uf := clampf(y / y_f, 0.0, 1.0)
		var desvio := -rumo * sin(uf * PI * 0.8) * 2.2 + lado * sin(uf * PI * 1.7 + 0.6) * 1.6
		tronco.append(Vector3(desvio.x, y, desvio.z))
		var r := lerpf(r0, r0 * 0.5, pow(uf, 0.75))
		if y > y_f:
			r = lerpf(r0 * 0.5, r0 * 0.2, clampf((y - y_f) / (alto - y_f), 0.0, 1.0))
		raios_t.append(r * (1.0 + 0.6 * pow(maxf(0.0, 1.0 - y / 3.0), 2.0)))
	var sapopemas := []
	for k in 6:
		sapopemas.append([TAU * k / 6.0 + rng.randf_range(-0.35, 0.35), rng.randf_range(0.9, 1.6)])
	_tubo(st, tronco, raios_t, 40, ruido, rng.randf(), 0.14, sapopemas, 2.2, rng, true)

	# --- Raízes expostas: saem das sapopemas, correm rente ao chão e afundam
	for s: Array in sapopemas:
		var a: float = s[0]
		var d := Vector3(cos(a), 0.0, sin(a))
		var comp := rng.randf_range(8.0, 14.0)
		var pts := PackedVector3Array()
		var rs := PackedFloat32Array()
		var n := 14
		var torce := rng.randf_range(-0.25, 0.25)
		for k in n + 1:
			var u := float(k) / n
			var dir := d.rotated(Vector3.UP, torce * u)
			var q := dir * (r0 * 0.7 + u * comp)
			var chao := float(altura.call(pe.x + q.x, pe.z + q.z)) - pe.y
			var r := lerpf(1.1, 0.18, u) * float(s[1]) * 0.8
			var y := lerpf(1.8, chao + r * 0.35, smoothstep(0.0, 0.35, u)) - smoothstep(0.75, 1.0, u) * r * 1.6
			pts.append(Vector3(q.x, y, q.z))
			rs.append(r)
		_tubo(st, pts, rs, 14, ruido, rng.randf(), 0.1, [], 0.0, rng)

	# --- Galho do poleiro: sai do tronco virado para a estrada, sobe um pouco e fica quase reto por cima da
	# beira da pista; a ponta é quebrada
	var y_ini := y_f
	var base_g := _no_tronco(tronco, y_ini)
	var galho := PackedVector3Array()
	var raios_g := PackedFloat32Array()
	var n_g := int(alcance / 0.8)
	for k in n_g + 1:
		var u := float(k) / n_g
		var x := lerpf(0.0, alcance, u)
		var y := y_ini + 3.0 * smoothstep(0.0, 0.45, u) - 0.4 * smoothstep(0.7, 1.0, u)
		var onda := lado * sin(u * PI * 2.2 + 0.4) * 0.9
		var p := Vector3(base_g.x, 0.0, base_g.z) + rumo * x + onda
		galho.append(Vector3(p.x, y, p.z))
		raios_g.append(lerpf(r0 * 0.38, 0.5, pow(u, 0.8)))
	_tubo(st, galho, raios_g, 22, ruido, rng.randf(), 0.08, [], 0.0, rng, true)
	# Poleiro: ~3,5 m antes da ponta, em cima do galho, olhando para a estrada
	var kp := clampi(int(n_g * (1.0 - 3.5 / alcance)), 1, n_g - 1)
	var p_pol := galho[kp] + Vector3.UP * (raios_g[kp] * 0.9)
	var poleiro := Transform3D(Basis.looking_at(-rumo, Vector3.UP), pe + p_pol)   # o modelo olha para +Z
	# Dois galhinhos saindo do galho do poleiro (longe do lugar do jaguar)
	for f: float in [0.35, 0.55]:
		var kk := int(n_g * f)
		var dir := (rumo * 0.4 + lado * (1.0 if f < 0.5 else -1.0) + Vector3.UP * 0.7).normalized()
		_galho(st, galho[kk], dir, rng.randf_range(4.0, 6.0), raios_g[kk] * 0.45, 2, ruido, rng)

	# --- Galhos mestres: saem da forquilha, abertos e tortos, e se dividem até os gravetos. Os que vão para o
	# lado da estrada sobem bem mais (passam muito acima da pista e não tampam o salto do jaguar)
	var az0 := atan2(rumo.z, rumo.x)
	for k in 6:
		var az := az0 + TAU * (k + 0.5) / 6.0 + rng.randf_range(-0.25, 0.25)
		var d := Vector3(cos(az), 0.0, sin(az))
		var y := y_f + rng.randf_range(-2.0, 6.0)
		var sobe := rng.randf_range(0.25, 0.6)
		if d.dot(rumo) > 0.2:
			sobe = 1.6
		var o := _no_tronco(tronco, y)
		var rt := _raio_tronco(tronco, raios_t, y)
		var comp := clampf(y_f * rng.randf_range(0.5, 0.65), 20.0, 38.0)   # copa larga, do tamanho da árvore
		_galho(st, o, (d + Vector3.UP * sobe).normalized(), comp, rt * rng.randf_range(0.6, 0.75), 0, ruido, rng)
	# Galhos de baixo, mortos e caídos para os lados (quebram a linha do tronco), e tocos dos que já caíram
	for k in 3:
		var y := lerpf(y_f * 0.4, y_f * 0.8, float(k) / 2.0) + rng.randf_range(-2.0, 2.0)
		var az := az0 + PI + rng.randf_range(-2.2, 2.2)
		var d := Vector3(cos(az), 0.0, sin(az))
		var o := _no_tronco(tronco, y)
		_galho(st, o, (d + Vector3.UP * rng.randf_range(-0.1, 0.35)).normalized(), rng.randf_range(8.0, 13.0), _raio_tronco(tronco, raios_t, y) * 0.32, 1, ruido, rng)
	for k in 6:
		var y := rng.randf_range(6.0, y_f * 0.85)
		var az := rng.randf() * TAU
		var o := _no_tronco(tronco, y)
		var dir := (Vector3(cos(az), 0.0, sin(az)) + Vector3.UP * 0.4).normalized()
		_galho(st, o, dir, rng.randf_range(2.0, 3.5) + _raio_tronco(tronco, raios_t, y), rng.randf_range(0.4, 0.7), 1, ruido, rng, false)

	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Casca"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	if _shader == null:
		_shader = load("res://shaders/arvore_seca.gdshader")
	mat.shader = _shader
	mat.set_shader_parameter("chao_y", pe.y)
	mi.material_override = mat
	raiz.add_child(mi)

	_orelhas_de_pau(raiz, tronco, raios_t, rumo, rng)
	_oco(raiz, tronco, raios_t, rumo, rng)
	_cipos(raiz, galho, raios_g, rng)

	# Colisão: tronco (pedaços de cilindro) e o pé com as sapopemas; parede comum, não mata
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	raiz.add_child(corpo)
	var passo := 5
	for k in range(0, tronco.size() - passo, passo):
		var a: Vector3 = tronco[k]
		var b: Vector3 = tronco[k + passo]
		var cs := CollisionShape3D.new()
		var cil := CylinderShape3D.new()
		cil.radius = raios_t[k] * (1.5 if a.y < 3.0 else 0.95)
		cil.height = a.distance_to(b)
		cs.shape = cil
		var eixo := (b - a).normalized()
		cs.transform = Transform3D(Basis(Quaternion(Vector3.UP, eixo)), (a + b) * 0.5)
		corpo.add_child(cs)
	return {"no": raiz, "poleiro": poleiro}


## Ponto do eixo do tronco na altura y (local).
static func _no_tronco(tronco: PackedVector3Array, y: float) -> Vector3:
	for k in range(1, tronco.size()):
		if tronco[k].y >= y:
			var a := tronco[k - 1]
			var b := tronco[k]
			return a.lerp(b, clampf((y - a.y) / maxf(b.y - a.y, 0.001), 0.0, 1.0))
	return tronco[tronco.size() - 1]


## Raio do tronco na altura y (local).
static func _raio_tronco(tronco: PackedVector3Array, rs: PackedFloat32Array, y: float) -> float:
	for k in range(1, tronco.size()):
		if tronco[k].y >= y:
			return rs[k]
	return rs[rs.size() - 1]


## Galho torto: anda em pedaços de ~1 m mudando de rumo aos trancos (como galho seco), afina até a ponta
## quebrada e solta filhos (nível 0 → 1 → 2 → 3, os gravetos). com_filhos = false: toco curto.
static func _galho(st: SurfaceTool, o: Vector3, dir: Vector3, comp: float, r: float, nivel: int, ruido: FastNoiseLite, rng: RandomNumberGenerator, com_filhos := true) -> void:
	var pts := PackedVector3Array([o])
	var rs := PackedFloat32Array([r])
	var passo := clampf(r * 1.6, 0.35, 1.0)
	var n := maxi(int(comp / passo), 3)
	var p := o
	var d := dir
	var tranco := 0.0
	for k in n:
		tranco -= passo
		if tranco <= 0.0:
			tranco = rng.randf_range(1.5, 4.0) * (0.5 if nivel >= 2 else 1.0)
			var torto := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.6, 0.6), rng.randf_range(-1.0, 1.0)) * (0.3 if nivel == 0 else 0.5)
			d = (d + torto - d * torto.dot(d)).normalized()
			# Galho seco pesa: os compridos vão deitando
			d = (d + Vector3.DOWN * 0.04 * float(nivel + 1)).normalized()
		p += d * passo
		pts.append(p)
		var u := float(k + 1) / n
		rs.append(r * lerpf(1.0, 0.3, pow(u, 0.85)))
	var lados: int = [18, 11, 7, 5][mini(nivel, 3)]
	if not com_filhos:
		lados = 12
	_tubo(st, pts, rs, lados, ruido, rng.randf(), 0.09 if nivel < 2 else 0.05, [], 0.0, rng, true)
	if nivel >= 3 or not com_filhos:
		return
	var filhos: int = [5, 3, 2][nivel]
	for k in filhos:
		var u := rng.randf_range(0.25, 0.85)
		var i := clampi(int(u * (pts.size() - 1)), 1, pts.size() - 2)
		var t := (pts[i + 1] - pts[i - 1]).normalized()
		var eixo := t.cross(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))).normalized()
		if eixo.length_squared() < 0.5:
			eixo = t.cross(Vector3.UP).normalized()
		var dd := t.rotated(eixo, rng.randf_range(0.5, 1.0))
		dd = (dd + Vector3.UP * 0.25).normalized()
		_galho(st, pts[i], dd, comp * rng.randf_range(0.35, 0.55), rs[i] * rng.randf_range(0.5, 0.7), nivel + 1, ruido, rng)


## Tubo pelo caminho com anéis de `lados` vértices (quadro de transporte paralelo). Relevo de verdade na malha:
## sulcos ao longo do comprimento e nós (ruído no círculo, sem emenda). sapopemas = [[ângulo, força], ...]
## alargam o pé em tábuas até `alto_sap` m. quebrado: a ponta termina em lascas (madeira clara).
static func _tubo(st: SurfaceTool, pts: PackedVector3Array, rs: PackedFloat32Array, lados: int, ruido: FastNoiseLite,
		sorteio: float, sulco: float, sapopemas: Array, alto_sap: float, rng: RandomNumberGenerator, quebrado := false) -> void:
	var n := pts.size()
	if n < 2:
		return
	var i0 := _nv
	# Quadros
	var t0 := (pts[1] - pts[0]).normalized()
	var nrm := t0.cross(Vector3.UP if absf(t0.y) < 0.95 else Vector3.RIGHT).normalized()
	# Voltas inteiras de textura em volta do galho: o shader repete o ruído nesse período (sem emenda)
	var reps := maxf(1.0, round(TAU * rs[0] / PASSO))
	var s := 0.0
	var fim_anel := PackedVector3Array()
	for k in n:
		var t: Vector3
		if k == 0:
			t = t0
		elif k == n - 1:
			t = (pts[k] - pts[k - 1]).normalized()
		else:
			t = (pts[k + 1] - pts[k - 1]).normalized()
		if k > 0:
			s += pts[k].distance_to(pts[k - 1])
			nrm = (nrm - t * nrm.dot(t)).normalized()
		var bi := t.cross(nrm).normalized()
		var r: float = rs[k]
		for j in lados + 1:
			var a := TAU * float(j % lados) / lados
			var dir := nrm * cos(a) + bi * sin(a)
			var c := Vector2(cos(a), sin(a)) * r
			var sul := ruido.get_noise_3d(c.x * 2.2, c.y * 2.2, s * 0.35 + sorteio * 50.0)
			var no := ruido.get_noise_3d(c.x * 0.6 + 40.0, c.y * 0.6, s * 0.12 + sorteio * 20.0)
			var f := 1.0 + sul * sulco * 2.0 + maxf(0.0, no - 0.35) * 0.5
			if not sapopemas.is_empty() and pts[k].y < alto_sap + 2.0:
				var ang := atan2(dir.z, dir.x)
				var hfat := pow(clampf(1.0 - (pts[k].y + 1.5) / (alto_sap + 3.5), 0.0, 1.0), 1.6)
				for sp: Array in sapopemas:
					var da := wrapf(ang - float(sp[0]), -PI, PI)
					f += float(sp[1]) * exp(-pow(da / 0.2, 2.0)) * hfat * 1.4
			var v := pts[k] + dir * r * f
			var ao := clampf(0.75 + sul * 1.5, 0.35, 1.0)
			st.set_color(Color(ao, 0.0, sorteio))
			st.set_uv(Vector2(float(j) / lados * reps, s / PASSO))
			st.set_uv2(Vector2(reps, 0.0))
			st.add_vertex(v)
			if k == n - 1 and j < lados:
				fim_anel.append(v)
	for k in n - 1:
		for j in lados:
			var a := i0 + k * (lados + 1) + j
			var b := a + lados + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	# Ponta: lascas (cada vértice da borda sobe um pouco ao longo do galho e entra) fechando no meio
	var tf := (pts[n - 1] - pts[n - 2]).normalized()
	var r_f: float = rs[n - 1]
	var c_f := pts[n - 1] + tf * r_f * (0.3 if quebrado else 0.15)
	_nv += n * (lados + 1)
	var i_lasca := _nv
	for j in lados:
		var v: Vector3 = fim_anel[j]
		var ponta := v.lerp(pts[n - 1], 0.35) + tf * (rng.randf_range(0.0, r_f * 2.2) if quebrado and j % 2 == 0 else rng.randf_range(0.0, r_f * 0.5))
		st.set_color(Color(0.8, 1.0, sorteio))
		st.set_uv(Vector2(float(j) / lados, 0.0))
		st.set_uv2(Vector2(reps, 0.0))
		st.add_vertex(ponta)
	st.set_color(Color(0.6, 1.0, sorteio))
	st.set_uv(Vector2(0.5, 0.5))
	st.set_uv2(Vector2(reps, 0.0))
	st.add_vertex(c_f)
	_nv += lados + 1
	var i_c := i_lasca + lados
	var i_borda := i0 + (n - 1) * (lados + 1)
	for j in lados:
		var j2 := (j + 1) % lados
		# borda da casca → lasca
		st.add_index(i_borda + j)
		st.add_index(i_lasca + j)
		st.add_index(i_borda + j2)
		st.add_index(i_borda + j2)
		st.add_index(i_lasca + j)
		st.add_index(i_lasca + j2)
		# lasca → miolo
		st.add_index(i_lasca + j)
		st.add_index(i_c)
		st.add_index(i_lasca + j2)


## Orelhas-de-pau: prateleiras de fungo em meia-lua presas no tronco, em grupos, beges com anéis.
static func _orelhas_de_pau(raiz: Node3D, tronco: PackedVector3Array, rs: PackedFloat32Array, rumo: Vector3, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for g in 3:
		var y0 := rng.randf_range(4.0, 14.0)
		var az0 := rng.randf() * TAU
		for k in rng.randi_range(3, 6):
			var y := y0 + k * rng.randf_range(0.35, 0.7)
			var az := az0 + rng.randf_range(-0.35, 0.35)
			var d := Vector3(cos(az), 0.0, sin(az))
			var i := clampi(int(y + 1.5), 0, tronco.size() - 1)
			var c := tronco[i] + d * rs[i] * 0.92
			var larg := rng.randf_range(0.35, 0.8)
			var fundo := larg * rng.randf_range(0.6, 0.85)
			var esp := larg * 0.28
			var lat := d.cross(Vector3.UP).normalized()
			var n := 12
			for j in n:
				for camada in 2:
					var a0 := PI * float(j) / n
					var a1 := PI * float(j + 1) / n
					var y_c := 0.0 if camada == 0 else -esp
					var p0 := c + lat * cos(a0) * larg + d * sin(a0) * fundo + Vector3.UP * (y_c + (esp * 0.6 if camada == 0 else 0.0))
					var p1 := c + lat * cos(a1) * larg + d * sin(a1) * fundo + Vector3.UP * (y_c + (esp * 0.6 if camada == 0 else 0.0))
					var cc := c + Vector3.UP * (esp * 0.9 if camada == 0 else -esp * 0.5)
					var tom := Color(0.5, 0.38, 0.24) if camada == 0 else Color(0.62, 0.54, 0.42)
					for tri: Array in ([[cc, p1, p0]] if camada == 0 else [[cc, p0, p1]]):
						for q: Vector3 in tri:
							var anel := 0.5 + 0.5 * sin(q.distance_to(c) / larg * 18.0)
							st.set_color(tom.darkened(0.35 * anel * (1.0 - float(camada)) + (0.35 if q.distance_to(c) > larg * 0.9 else 0.0)))
							st.add_vertex(q)
				# Beirada (liga as duas camadas)
				var a0 := PI * float(j) / n
				var a1 := PI * float(j + 1) / n
				var e0 := c + lat * cos(a0) * larg + d * sin(a0) * fundo
				var e1 := c + lat * cos(a1) * larg + d * sin(a1) * fundo
				var quad := [e0 + Vector3.UP * esp * 0.6, e1 + Vector3.UP * esp * 0.6, e1 - Vector3.UP * esp, e0 - Vector3.UP * esp]
				st.set_color(Color(0.42, 0.3, 0.18))
				for q: int in [0, 2, 1, 0, 3, 2]:
					st.add_vertex(quad[q])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "OrelhasDePau"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	raiz.add_child(mi)


## Oco no tronco: boca escura e funda com borda de casca enrolada, do lado da estrada.
static func _oco(raiz: Node3D, tronco: PackedVector3Array, rs: PackedFloat32Array, rumo: Vector3, rng: RandomNumberGenerator) -> void:
	var y := rng.randf_range(4.5, 7.0)
	var i := clampi(int(y + 1.5), 0, tronco.size() - 1)
	var d := rumo.rotated(Vector3.UP, rng.randf_range(-0.9, 0.9))
	var c := tronco[i] + d * rs[i] * 0.9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lat := d.cross(Vector3.UP).normalized()
	var n := 20
	var larg := rs[i] * 0.42
	var alt := rs[i] * 0.85
	var anel := []
	var dentro := []
	for k in n:
		var a := TAU * k / n
		var w := 1.0 + rng.randf_range(-0.12, 0.12)
		var q := lat * cos(a) * larg * w + Vector3.UP * sin(a) * alt * w
		anel.append(c + q + d * 0.25)
		dentro.append(c + q * 0.7 - d * 0.6)
	var fundo := c - d * 1.6
	for k in n:
		var k2 := (k + 1) % n
		# lábio (casca enrolada, escuro por dentro)
		for tri: Array in [[anel[k], dentro[k], anel[k2]], [anel[k2], dentro[k], dentro[k2]]]:
			for q: Vector3 in tri:
				st.set_color(Color(0.16, 0.12, 0.09) if q.distance_to(c) < larg * 0.8 else Color(0.3, 0.25, 0.2))
				st.add_vertex(q)
		for q: Vector3 in [dentro[k], fundo, dentro[k2]]:
			st.set_color(Color(0.015, 0.01, 0.008))
			st.add_vertex(q)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Oco"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	raiz.add_child(mi)


## Cipós secos pendurados do galho do poleiro e enrolados nele (fora do lugar do jaguar).
static func _cipos(raiz: Node3D, galho: PackedVector3Array, rs: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_g := galho.size()
	for k in 6:
		var i := clampi(int(n_g * rng.randf_range(0.12, 0.7)), 0, n_g - 1)
		var topo := galho[i] + Vector3.DOWN * rs[i] * 0.8
		var queda := rng.randf_range(4.0, 11.0)
		var balanco := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)) * 0.8
		var pts := PackedVector3Array()
		for j in 16:
			var u := float(j) / 15.0
			pts.append(topo + Vector3.DOWN * queda * u + balanco * sin(u * PI) + Vector3(sin(u * 9.0 + k), 0.0, cos(u * 7.0 + k)) * 0.12)
		var r := rng.randf_range(0.04, 0.08)
		for j in 15:
			var a: Vector3 = pts[j]
			var b: Vector3 = pts[j + 1]
			var t := (b - a).normalized()
			var e1 := t.cross(Vector3.RIGHT if absf(t.x) < 0.9 else Vector3.FORWARD).normalized()
			var e2 := t.cross(e1)
			for l in 5:
				var a0 := TAU * l / 5.0
				var a1 := TAU * (l + 1) / 5.0
				var o0 := (e1 * cos(a0) + e2 * sin(a0)) * r
				var o1 := (e1 * cos(a1) + e2 * sin(a1)) * r
				for q: Vector3 in [a + o0, b + o0, a + o1, a + o1, b + o0, b + o1]:
					st.set_color(Color(0.22, 0.17, 0.11).lerp(Color(0.33, 0.28, 0.17), rng.randf()))
					st.add_vertex(q)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Cipos"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.95
	mi.material_override = m
	raiz.add_child(mi)
