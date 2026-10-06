class_name TunelPista
extends Node3D
## Túneis da pista do Serpent's Climb (pedido do dono 2026-10-06: "onde uma rocha ou morro fica sobre a pista,
## faça um túnel"). O terreno acha sozinho os pedaços de estrada da etapa que passam dentro de morro e cava uma
## vala ao longo deles (Terreno._achar_tuneis_pista / _cavar_tuneis_pista); aqui, seguindo a curva da estrada:
## - o tubo de pedra em arco (a mesma pedra da montanha-armadilha), com tochas;
## - a capa: a encosta natural refeita por cima da vala, com o recorte diante de cada boca (como TunelAtalho);
## - a placa de rocha de cada boca, com o furo em arco.
## Tubo e capa são parede comum (não matam).

const PASSO := 2.0          # m entre estações ao longo da estrada
const MEIA_CAPA := 34.0     # vala (16) + interpolação da malha (13) + folga
const TOPO := 11.0          # alto da abóbada acima da estrada
const OMBRO := 6.5
const PISO := -3.0
const FORA := 40.0          # a capa continua isto além de cada boca (cobre o corte de chegada)
const INGREME_Y := 0.55     # face da capa com normal.y abaixo disto: parede de rocha com musgo
const MUSGO_M := 80.0       # m de cada repetição do ladrilho de musgo (o bloco maior dele fica com ~30 m)


func montar(terreno: Terreno, sub: ComplexoSubida) -> void:
	name = "TuneisPista"
	var mat_rocha := RochasSelva._material("montanha_armadilha").duplicate() as ShaderMaterial
	mat_rocha.set_shader_parameter("so_mosaico", true)
	mat_rocha.set_shader_parameter("mosaico_m", 30.0)
	mat_rocha.set_shader_parameter("alto_y", 1.0)
	var lad := Recinto.ler_imagem("res://assets/selva/rochas/rocha_ladrilho.png")
	if lad:
		lad.generate_mipmaps()
		mat_rocha.set_shader_parameter("ladrilho", ImageTexture.create_from_image(lad))
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	add_child(corpo)
	for t: Dictionary in terreno.tuneis_pista():
		_um(t, terreno, sub, mat_rocha, corpo)


## Estações (a cada PASSO m) da estrada de verdade entre as pontas do pedaço coberto: [ponto, lateral, meia].
func _estacoes(pts: PackedVector3Array, sub: ComplexoSubida) -> Array:
	var i0 := _mais_perto(sub, pts[0])
	var i1 := _mais_perto(sub, pts[pts.size() - 1])
	if i0 > i1:
		var tmp := i0
		i0 = i1
		i1 = tmp
	var lista: Array = []
	var i := i0
	while i <= i1:
		var fr := sub.tangente_em(i)
		var lat := Vector3(fr.x, 0.0, fr.z).normalized().cross(Vector3.UP)   # direita de quem vai (como TunelAtalho)
		lista.append([sub.amostra(i), lat, sub.largura_em(i) * 0.5 + 4.0])
		var alvo := sub.progresso_amostra(i) + PASSO
		while i <= i1 and sub.progresso_amostra(i) < alvo:
			i += 1
	return lista


func _mais_perto(sub: ComplexoSubida, p: Vector3) -> int:
	var melhor := 0
	var d := INF
	for i in sub.total_amostras():
		var e := sub.amostra(i).distance_squared_to(p)
		if e < d:
			d = e
			melhor = i
	return melhor


func _um(t: Dictionary, terreno: Terreno, sub: ComplexoSubida, mat_rocha: ShaderMaterial, corpo: StaticBody3D) -> void:
	var est := _estacoes(t.pts, sub)
	if est.size() < 4:
		return
	var nat := func(k: int, l: float) -> float:
		var q: Vector3 = (est[k][0] as Vector3) + (est[k][1] as Vector3) * l
		return terreno.altura_natural_malha(q.x, q.z)
	# Bocas: primeira/última estação com rocha 3 m acima da abóbada (sem isso, só o corte aberto basta)
	var k_ini := -1
	var k_fim := -1
	for k in est.size():
		if nat.call(k, 0.0) > (est[k][0] as Vector3).y + TOPO + 3.0:
			if k_ini < 0:
				k_ini = k
			k_fim = k
	if k_ini < 0 or k_fim - k_ini < 2:
		return
	var meia: float = est[k_ini][2]
	var sec = TunelAtalho._Secao.new(meia, PISO, OMBRO, TOPO)
	var semente := int(absf((est[0][0] as Vector3).x * 13.0 + (est[0][0] as Vector3).z * 7.0))
	# ---- tubo
	var tubo := _malha_tubo(sec, est, k_ini, k_fim, semente)
	var mi := MeshInstance3D.new()
	mi.mesh = tubo
	mi.material_override = mat_rocha
	add_child(mi)
	var cs := CollisionShape3D.new()
	var forma := tubo.create_trimesh_shape()
	forma.backface_collision = true
	cs.shape = forma
	corpo.add_child(cs)
	# ---- capa (estende para fora das bocas seguindo a direção da estrada)
	var capa := _malha_capa(sec, est, k_ini, k_fim, terreno)
	var mc := MeshInstance3D.new()
	mc.mesh = _separar_ingreme(capa)
	mc.set_surface_override_material(0, terreno._mat_terreno)
	if mc.mesh.get_surface_count() > 1:
		mc.set_surface_override_material(1, _material_musgo(mat_rocha))
	add_child(mc)
	var cs2 := CollisionShape3D.new()
	var f2 := capa.create_trimesh_shape()
	f2.backface_collision = true
	cs2.shape = f2
	corpo.add_child(cs2)
	# ---- placas das bocas
	for k: int in [k_ini, k_fim]:
		var p: Vector3 = est[k][0]
		var lat: Vector3 = est[k][1]
		var frente := lat.cross(Vector3.UP).normalized()
		var viz: Vector3 = est[mini(k + 1, est.size() - 1)][0] if k == k_ini else est[maxi(k - 1, 0)][0]
		if frente.dot(viz - p) > 0.0:
			frente = -frente   # para fora do túnel
		var boca := TunelAtalho._malha_boca(sec, p + frente * 0.4, lat, frente, TOPO + 2.2, PISO - 2.0, semente + k)
		var mb := MeshInstance3D.new()
		mb.mesh = boca
		mb.material_override = mat_rocha
		add_child(mb)
	# ---- tochas a cada ~30 m
	for k in range(k_ini + 7, k_fim - 3, 15):
		for s: float in [-1.0, 1.0]:
			var luz := OmniLight3D.new()
			luz.light_color = Color(1.0, 0.62, 0.3)
			luz.light_energy = 2.5
			luz.omni_range = 26.0
			luz.position = (est[k][0] as Vector3) + (est[k][1] as Vector3) * s * (meia - 1.0) + Vector3.UP * (OMBRO - 0.5)
			add_child(luz)
			Fogo.criar(self, luz.position - Vector3.UP * 0.6, 0.4, 1.4, 12, 0.7, false)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[TUNEL] montado: %d m entre %s e %s" % [int((k_fim - k_ini) * PASSO), str((est[k_ini][0] as Vector3).snapped(Vector3.ONE)), str((est[k_fim][0] as Vector3).snapped(Vector3.ONE))])


## Paredes do tubo: o contorno em arco de TunelAtalho puxado pela curva da estrada, com relevo irregular.
func _malha_tubo(sec, est: Array, k0: int, k1: int, semente: int) -> ArrayMesh:
	var ruido := FastNoiseLite.new()
	ruido.seed = semente
	ruido.frequency = 0.18
	var anel: Array = sec.anel()
	var n := anel.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(k0, k1 + 1):
		var p: Vector3 = est[k][0]
		var lat: Vector3 = est[k][1]
		for j in n:
			var q: Vector2 = anel[j][0]
			var nn: Vector2 = anel[j][1]
			var amp := 0.12 if anel[j][2] else 1.0
			q += nn * (ruido.get_noise_2d(j * 2.3, k * PASSO) * 0.5 + 0.5) * 0.8 * amp
			st.add_vertex(p + lat * q.x + Vector3.UP * q.y)
	for i in k1 - k0:
		for j in n:
			var j2 := (j + 1) % n
			var a := i * n + j
			var c := i * n + j2
			var d := (i + 1) * n + j
			var e := (i + 1) * n + j2
			st.add_index(a); st.add_index(d); st.add_index(c)
			st.add_index(c); st.add_index(d); st.add_index(e)
	st.generate_normals()
	return st.commit()


## Capa em duas superfícies: 0 = o chão da selva (encosta suave, emenda no terreno em volta), 1 = as paredes
## íngremes (os cortes de ~30 m diante das bocas), que com o material do terreno ficavam verdes e riscadas.
func _separar_ingreme(capa: ArrayMesh) -> ArrayMesh:
	var arr := capa.surface_get_arrays(0)
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var sts: Array[SurfaceTool] = []
	var usadas := [false, false]
	for k in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	for t in range(0, idx.size(), 3):
		var a := pos[idx[t]]
		var b := pos[idx[t + 1]]
		var c := pos[idx[t + 2]]
		var k := 1 if absf((c - a).cross(b - a).normalized().y) < INGREME_Y else 0
		sts[k].add_vertex(a)
		sts[k].add_vertex(b)
		sts[k].add_vertex(c)
		usadas[k] = true
	var malha := ArrayMesh.new()
	for k in 2:
		if usadas[k]:
			sts[k].index()
			sts[k].generate_normals()
			sts[k].commit(malha)
	return malha


## Rocha com musgo da arte do dono (rochacommusgo1varios angulos → rocha_musgo_ladrilho.png, gerada por
## tools/serpents_climb/rocha_ladrilho.gd -- musgo) em mosaico no espaço do mundo, blocos de ~30 m.
func _material_musgo(mat_rocha: ShaderMaterial) -> ShaderMaterial:
	var m := mat_rocha.duplicate() as ShaderMaterial
	m.set_shader_parameter("mosaico_m", MUSGO_M)
	var img := Recinto.ler_imagem("res://assets/selva/rochas/rocha_musgo_ladrilho.png")
	if img:
		img.generate_mipmaps()
		m.set_shader_parameter("ladrilho", ImageTexture.create_from_image(img))
	return m


## Capa: a encosta natural por cima da vala, com o teto de rocha sobre a abóbada entre as bocas e o recorte
## diante de cada boca (a encosta desce até abaixo do piso). Fora das estações, segue reto na direção da estrada.
func _malha_capa(sec, est: Array, k0: int, k1: int, terreno: Terreno) -> ArrayMesh:
	var linhas: Array = []   # [ponto, lateral, estado: 0 fora, 1 dentro, 2 boca]
	var extra := int(FORA / PASSO)
	for k in range(k0 - extra, k1 + extra + 1):
		var kk := clampi(k, 0, est.size() - 1)
		var p: Vector3 = est[kk][0]
		var lat: Vector3 = est[kk][1]
		if k != kk:   # além das estações: reto na direção da estrada
			var outro: Vector3 = est[kk + (1 if k < 0 else -1)][0]
			var dir := (p - outro)
			dir.y = 0.0
			p += dir.normalized() * absf(k - kk) * PASSO
		linhas.append([p, lat, 1 if k >= k0 and k <= k1 else 0, k == k0 or k == k1])
	var ls: Array[float] = []
	var l := -MEIA_CAPA
	while l <= MEIA_CAPA + 0.01:
		ls.append(l)
		l += PASSO
	for s: float in [-1.0, 1.0]:
		ls.append(s * (sec.meia + 1.5))
	ls.sort()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for li: Array in linhas:
		var p: Vector3 = li[0]
		var lat: Vector3 = li[1]
		for ll in ls:
			var q := p + lat * ll
			var h := terreno.altura_natural_malha(q.x, q.z)
			var al := absf(ll)
			if li[2] == 1:
				var teto := p.y + TOPO + 1.5
				if al <= sec.meia + 1.51 and li[3]:
					h = teto
				elif al < sec.meia + 4.0:
					h = maxf(h, teto)
			elif al <= sec.meia + 1.51:
				h = minf(h, p.y + PISO - 1.0)
			h -= 2.5 * smoothstep(MEIA_CAPA - 6.0, MEIA_CAPA, al)
			st.add_vertex(Vector3(q.x, h, q.z))
	var nl := ls.size()
	for i in linhas.size() - 1:
		var boca: bool = linhas[i][2] != linhas[i + 1][2]
		for j in nl - 1:
			if boca and absf(ls[j]) <= sec.meia + 1.51 and absf(ls[j + 1]) <= sec.meia + 1.51:
				continue
			var a := i * nl + j
			var c := a + nl
			st.add_index(a); st.add_index(c); st.add_index(a + 1)
			st.add_index(a + 1); st.add_index(c); st.add_index(c + 1)
	st.generate_normals()
	return st.commit()
