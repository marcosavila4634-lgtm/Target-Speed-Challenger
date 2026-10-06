class_name MontanhaArmadilha
extends RefCounted
## Armadilha da montanha de rocha do Serpent's Climb (pedido do dono, 2026-10-05; artes em
## assets/MAPA SERPENTE/morro/rocha gigante com armadilha). No lugar de uma lâmina (laminas: [trecho, m, fase,
## período, "rocha"]):
## - a MONTANHA: a rocha com o arco, sólida pelas três vistas (tools/serpents_climb/rochas.gd →
##   assets/selva/rochas/montanha_armadilha.res), com a pele da arte na frente e nas costas e rocha da mesma
##   arte em mosaico nos lados (shaders/rocha_arte.gdshader). O túnel é cortado nela seguindo a curva da pista,
##   alinhado com o arco pintado; ela fica em pé em rochas gigantes que descem até o chão do vale;
## - o TÚNEL: tubo em arco por dentro, revestido com a textura interna da arte (interna.png), aro de rocha nas
##   bocas e chão embaixo da estrada; luzes quentes lá dentro;
## - o PORTAL no meio do túnel: a arte (portal.png) em relevo nas duas faces, com o fundo recortado e o vão
##   aberto, olhos vermelhos com luz de verdade (eles avisam: verdes quando dá para passar);
## - o MACHADO: recortado da mesma arte e montado em pedaços (argola, haste repetida pelo friso, lâmina), balança
##   no disco dourado como pêndulo. Só ele mata; montanha, túnel e portal são parede comum.

const ROCHA := "res://assets/selva/rochas/montanha_armadilha"
const PORTAL := "res://assets/selva/armadilha_rocha/portal.png"
const INTERNA := "res://assets/selva/armadilha_rocha/interna.png"
# Na arte do portal (UV): vão entre os pilares, pé dos pilares, disco do pivô e o retângulo do machado
const VAO := 0.406
const PE_V := 0.949
const PIVO_V := 0.187
const MACHADO := Rect2(0.352, 0.255, 0.294, 0.462)
const HASTE := [0.30, 0.55]     # trecho da haste que se repete
const CABECA_V := 0.55          # começo da lâmina (até MACHADO.end.y)
# Na arte da montanha (caixa da rocha): meio do arco em x (-1..1) e a base dele em v
const ARCO_X := 0.14
const ARCO_V := 0.72
const LARGURA := 150.0
const FUNDO := 0.3   # rocha estreita ao longo da pista: uma passagem em arco, não um túnel (ideia do dono)
const FOLGA := 1.0   # a boca na rocha fica esta folga (m) para fora do perfil do túnel
# Estátua que cospe fogo (tools/serpents_climb/estatua_fogo.gd): altura em m e a boca no modelo (x para trás
# da ponta do focinho, y na altura; altura do modelo = 1)
const ESTATUA := "res://assets/selva/gospefogo/estatua"
const ESTATUA_ALT := 12.0          # tamanho pintado pelo dono (2026-10-06): a parte de trás entra na parede do túnel
const ESTATUA_BOCA_Y := 2.0        # a boca fica a esta altura da pista (o pé afunda no chão do túnel)
const ESTATUA_BOCA := Vector2(0.67, 0.54)


## Monta tudo e devolve os dados de cada pêndulo para Armadilhas ([{corpo, l, hp, pivo, meia_lam, lampadas,
## amp, i}, ...]). idxs: amostras da pista dos portais, do primeiro (quem chega encontra antes) ao último; com
## mais de um, a rocha fica mais funda ao longo da pista para caber todos no túnel.
static func montar(arm: Armadilhas, no: Node3D, idxs: Array) -> Array:
	var sub := arm.sub
	var i: int = idxs[0]
	var c := sub.amostra(i)
	var b := arm._base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	# Portal: o vão cabe a pista com folga
	var tx := TunelVulcao.texturas_arte(PORTAL, [MACHADO])
	if tx.is_empty():
		push_warning("MontanhaArmadilha: falta a arte do portal")
		return []
	var larg := (meia * 2.0 + 5.0) / VAO
	var alt := larg / float(tx[3])
	var y0 := -2.5 - (1.0 - PE_V) * alt    # pé dos pilares, abaixo do chão do túnel
	var piso := -ComplexoSubida.ESPESSURA_ESTRADA - 0.1   # chão do túnel: logo embaixo do tabuleiro (mais fundo ficava uma vala dos lados)
	var hw := larg * 0.5 + 2.0             # meia largura do túnel
	var htopo := y0 + alt + 4.0            # alto do arco do túnel
	var vao_tamanho := sub.progresso_amostra(idxs[idxs.size() - 1]) - sub.progresso_amostra(i)
	_montanha(arm, no, i, c, b, lat, hw, htopo, piso, vao_tamanho)
	var lista: Array = []
	for ik: int in idxs:
		var g := _portal(arm, no, sub.amostra(ik), arm._base(ik), tx, larg, alt, y0)
		g["i"] = ik
		lista.append(g)
	return lista


## Variante sem portal nem machado (pedido do dono 2026-10-06): a mesma montanha com túnel e, no lugar de cada
## portal, um par de estátuas de serpente (uma de cada lado, assets/selva/gospefogo, CC-BY Aleksandr) que cospem
## fogo atravessando a pista. Devolve [{i, jatos: [GPUParticles3D], luzes: [OmniLight3D], meia}, ...].
static func montar_fogo(arm: Armadilhas, no: Node3D, idxs: Array) -> Array:
	var sub := arm.sub
	var i: int = idxs[0]
	var tx := TunelVulcao.texturas_arte(PORTAL, [MACHADO])
	if tx.is_empty():
		return []
	var meia := sub.largura_em(i) * 0.5
	var larg := (meia * 2.0 + 5.0) / VAO   # o túnel do mesmo tamanho do da montanha com machados
	var alt := larg / float(tx[3])
	var y0 := -2.5 - (1.0 - PE_V) * alt
	var piso := -ComplexoSubida.ESPESSURA_ESTRADA - 0.1
	var hw := larg * 0.5 + 2.0
	var htopo := y0 + alt + 4.0
	var vao_tamanho := sub.progresso_amostra(idxs[idxs.size() - 1]) - sub.progresso_amostra(i)
	_montanha(arm, no, i, sub.amostra(i), arm._base(i), sub.lateral_em(i), hw, htopo, piso, vao_tamanho)
	var malha := load(ESTATUA + ".res") as ArrayMesh
	var mat := StandardMaterial3D.new()
	var img := Recinto.ler_imagem(ESTATUA + "_cor.jpg")
	if img:
		img.generate_mipmaps()
		mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # escaneada: aberta atrás
	mat.roughness = 0.9
	var est := arm._corpo_mortal(no)   # parede comum (só o fogo mata)
	var caixas: Array = []
	var lista: Array = []
	for ik: int in idxs:
		var c := sub.amostra(ik)
		var lat := sub.lateral_em(ik)
		lat = Vector3(lat.x, 0.0, lat.z).normalized()
		var m := sub.largura_em(ik) * 0.5
		var jatos: Array = []
		var luzes: Array = []
		for s: float in [-1.0, 1.0]:
			# Boca da estátua (no modelo: -x, a ESTATUA_BOCA da altura) logo depois da beirada, virada para a pista
			var bx := lat * s
			var bs := Basis(bx, Vector3.UP, bx.cross(Vector3.UP))
			var pe := c + lat * s * (m + 1.0 + ESTATUA_BOCA.x * ESTATUA_ALT) + Vector3.UP * (ESTATUA_BOCA_Y - ESTATUA_BOCA.y * ESTATUA_ALT)
			if malha:
				var mi := MeshInstance3D.new()
				mi.mesh = malha
				mi.material_override = mat
				mi.transform = Transform3D(bs.scaled(Vector3.ONE * ESTATUA_ALT), pe)
				no.add_child(mi)
			var prop: Vector2 = malha.get_meta("proporcao", Vector2(1.5, 0.9)) if malha else Vector2(1.5, 0.9)
			caixas.append(Transform3D(bs * Basis.from_scale(Vector3(prop.x * ESTATUA_ALT - 2.0, ESTATUA_ALT, prop.y * ESTATUA_ALT)), pe + Vector3.UP * ESTATUA_ALT * 0.5 + bx * 1.0))   # recuada da beirada
			var boca := pe + Vector3.UP * ESTATUA_BOCA.y * ESTATUA_ALT - bx * ESTATUA_BOCA.x * ESTATUA_ALT
			# Jato: o fogo dos braseiros deitado, da boca até passar do meio da pista (encontra o do outro lado)
			var j := Fogo.criar(no, Vector3.ZERO, 1.1, m + 2.5, 150, 3.6, false)   # chama grossa (o amarelo pintado pelo dono)
			if j:
				j.transform = Transform3D(Basis((-bx).cross(Vector3.UP), -bx, Vector3.UP), boca)   # o "para cima" do fogo vira a direção da pista
				var pm := j.process_material as ParticleProcessMaterial
				pm.gravity = Vector3.ZERO
				j.lifetime = 0.45   # jato rápido: chega ao meio da pista em menos de meio segundo
				pm.initial_velocity_min = (m + 2.5) / 0.45 * 0.8
				pm.initial_velocity_max = (m + 2.5) / 0.45 * 1.05
				j.preprocess = 0.0
				j.emitting = false
				jatos.append(j)
			var luz := OmniLight3D.new()
			luz.light_color = Color(1.0, 0.5, 0.15)
			luz.light_energy = 0.0
			luz.omni_range = 24.0
			luz.position = boca - bx * 3.0
			no.add_child(luz)
			luzes.append(luz)
		lista.append({"i": ik, "jatos": jatos, "luzes": luzes, "meia": m})
	ComplexoLancamento.adicionar_colisoes(est, caixas)
	return lista


# ------------------------------------------------------------------ montanha e túnel

## vao_tamanho: metros de pista do primeiro ao último portal (0 = um só).
static func _montanha(arm: Armadilhas, no: Node3D, i: int, c: Vector3, b: Basis, lat: Vector3, hw: float, htopo: float, piso: float, vao_tamanho := 0.0) -> void:
	var sub := arm.sub
	var malha := load(ROCHA + ".res") as ArrayMesh
	if malha == null:
		push_warning("MontanhaArmadilha: falta %s.res (rodar tools/serpents_climb/rochas.gd)" % ROCHA)
		return
	var Y := float(malha.get_meta("Y", 1.68))
	var D := float(malha.get_meta("D", 0.83))
	var esc := LARGURA * 0.5
	var H := Y * esc
	# Base: a do arco pintado fica no nível da pista; o meio do arco em cima do eixo da pista
	var base_y := c.y - (1.0 - ARCO_V) * H
	# Um portal: fica logo na boca da frente, o meio da rocha vai um pouco adiante na pista. Vários: o meio da
	# rocha no meio da fila, funda o bastante para todos ficarem 12 m dentro das bocas.
	var fundo := FUNDO if vao_tamanho <= 0.0 else maxf(FUNDO, (vao_tamanho * 0.5 + 12.0) / (D * esc))
	var prof := D * esc * fundo
	var ic := sub.indice_adiante(i, maxf(prof - 6.0, 0.0) if vao_tamanho <= 0.0 else vao_tamanho * 0.5)
	var origem := sub.amostra(ic) - sub.lateral_em(ic) * ARCO_X * esc
	origem.y = c.y
	b = arm._base(ic)
	lat = sub.lateral_em(ic)
	var xf := Transform3D(b * Basis.from_scale(Vector3(esc, esc, esc * fundo)), Vector3(origem.x, base_y, origem.z))
	# Amostras da pista dentro da rocha (ela vai até prof m para cada lado do meio)
	var s0 := sub.progresso_amostra(ic)
	var pista: Array = []   # [ponto, lateral, metro]
	var j := ic
	while j > 0 and sub.trecho_de(j - 1) == sub.trecho_de(ic) and s0 - sub.progresso_amostra(j) < prof + 8.0:
		j -= 1
	while sub.trecho_de(j) == sub.trecho_de(ic) and sub.progresso_amostra(j) - s0 < prof + 8.0:
		pista.append([sub.amostra(j), sub.lateral_em(j), sub.progresso_amostra(j) - s0])
		j += 1
		if j >= sub.total_amostras():
			break
	# Rocha furada pelo túnel (ver o laço mais abaixo). Antes, o contorno alisado: o relevo da malha deixava o
	# recorte da rocha em serra contra o céu.
	var arr := malha.surface_get_arrays(0)
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var pos := _alisar(arr[Mesh.ARRAY_VERTEX], idx, 4)
	# Uma rocha só (pedido do dono): o que fica abaixo da pista estica até o chão do vale e alarga no pé, como
	# um pilar natural da mesma pedra; acima da pista a forma da arte fica como está
	var chao := INF
	for k in 24:
		var a := TAU * k / 24.0
		for rr in [0.0, 0.5, 1.0]:
			var q: Vector3 = origem + (lat * cos(a) * esc + b.z * sin(a) * prof) * rr
			chao = minf(chao, arm._terreno.altura_em(q.x, q.z))
	chao -= 8.0
	var mundo := PackedVector3Array()
	mundo.resize(pos.size())
	for k in pos.size():
		var w := xf * pos[k]
		if w.y < c.y:
			var t := clampf((w.y - base_y) / maxf(c.y - base_y, 1.0), 0.0, 1.0)
			var ny := lerpf(chao, c.y, t)
			var abre := 1.0 + 0.45 * (1.0 - t) * (1.0 - t)
			var hz := Vector3(w.x - origem.x, 0.0, w.z - origem.z) * abre
			w = Vector3(origem.x + hz.x, ny, origem.z + hz.z)
		mundo[k] = w
	# Os vértices que caem dentro do perfil do túnel (com FOLGA) vão para a borda dele: a boca segue o arco
	# certinho (tirar triângulos inteiros deixava a borda em dentes). Embaixo, a rocha sobe até o fundo do
	# tabuleiro da pista (no chão do túnel ficava uma fresta embaixo da boca). Os triângulos com os três vértices dentro
	# (a "porta" de pedra) saem.
	var novo := PackedInt32Array()
	var faces := PackedVector3Array()
	var s_min := INF
	var s_max := -INF
	# Para cada ponto do perfil do túnel, de que metro a que metro da pista a rocha chega ali: o tubo termina
	# rente à pedra em cada ponto da volta (a face da rocha é inclinada e a pista faz curva; cortado reto, o tubo
	# saía da montanha como uma rebarba, e o chão como uma laje)
	var perfil := _perfil(hw, htopo, piso)
	var faixas: Array[Vector2] = []
	for k in perfil.size():
		faixas.append(Vector2(INF, -INF))
	var dentro_v := PackedByteArray()
	dentro_v.resize(mundo.size())
	for k in mundo.size():
		var e := _empurrar(pista, mundo[k], hw + FOLGA, htopo * 0.6, htopo * 0.4 + FOLGA, -ComplexoSubida.ESPESSURA_ESTRADA - 0.1)
		if not e.is_empty():
			mundo[k] = e[0]
			dentro_v[k] = 1
			s_min = minf(s_min, e[1])
			s_max = maxf(s_max, e[1])
			var kp := 0
			for kk in perfil.size():
				if perfil[kk].distance_squared_to(e[2]) < perfil[kp].distance_squared_to(e[2]):
					kp = kk
			faixas[kp] = Vector2(minf(faixas[kp].x, e[1]), maxf(faixas[kp].y, e[1]))
	for t in range(0, idx.size(), 3):
		if dentro_v[idx[t]] + dentro_v[idx[t + 1]] + dentro_v[idx[t + 2]] == 3:
			continue
		novo.append_array([idx[t], idx[t + 1], idx[t + 2]])
		faces.append_array([mundo[idx[t]], mundo[idx[t + 1]], mundo[idx[t + 2]]])
	# Malha em coordenadas do mundo (já esticada e cortada), normais refeitas
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in novo:
		st.add_vertex(mundo[k])
	st.index()
	st.generate_normals()
	var mat := RochasSelva._material("montanha_armadilha").duplicate() as ShaderMaterial
	mat.set_shader_parameter("so_mosaico", true)
	mat.set_shader_parameter("mosaico_m", 30.0)
	mat.set_shader_parameter("alto_y", 1.0)   # a malha está no mundo: sem o musgo "do pé" da rocha solta
	var lad := Recinto.ler_imagem("res://assets/selva/rochas/rocha_ladrilho.png")
	if lad:
		lad.generate_mipmaps()
		mat.set_shader_parameter("ladrilho", ImageTexture.create_from_image(lad))
	var mi := MeshInstance3D.new()
	mi.name = "Montanha"
	mi.mesh = st.commit()
	mi.material_override = mat
	no.add_child(mi)
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	no.add_child(corpo)
	var forma := ConcavePolygonShape3D.new()
	forma.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	corpo.add_child(cs)
	# Túnel: só onde a rocha foi cortada (as bocas ficam rente à pedra)
	var dentro: Array = pista.filter(func(p: Array) -> bool: return float(p[2]) >= s_min - 2.0 and float(p[2]) <= s_max + 2.0)
	_tunel(no, corpo, dentro if dentro.size() > 4 else pista, hw, htopo, piso, mat, faixas)


## Vértice da rocha dentro do perfil do túnel (paredes retas de meia largura w até a altura parede, arco em
## meia-elipse de altura hy acima dela, chão no piso): [ponto levado à borda mais perto, metro da pista]; fora: [].
static func _empurrar(pista: Array, m: Vector3, w: float, parede: float, hy: float, piso: float) -> Array:
	var melhor := INF
	var q: Array = []
	for p: Array in pista:
		var d := Vector2(m.x - (p[0] as Vector3).x, m.z - (p[0] as Vector3).z).length_squared()
		if d < melhor:
			melhor = d
			q = p
	if q.is_empty() or q == pista[0] or q == pista[pista.size() - 1]:
		return []
	var c: Vector3 = q[0]
	var lat: Vector3 = q[1]
	var lado := (m - c).dot(lat)
	var up := m.y - c.y
	if up <= piso - FOLGA or up >= parede + hy:
		return []
	var meia := w if up <= parede else w * sqrt(maxf(1.0 - pow((up - parede) / hy, 2.0), 0.0))
	if absf(lado) >= meia:
		return []
	# Borda mais perto: parede/arco (radial a partir do meio do arco) ou o chão
	var b_lado := signf(lado) * w if lado != 0.0 else w
	var b_up := up
	if up > parede:
		var v := Vector2(lado / w, (up - parede) / hy).normalized()
		b_lado = v.x * w
		b_up = parede + v.y * hy
	var ate_chao := absf(up - piso)
	if ate_chao < Vector2(b_lado - lado, b_up - up).length():
		b_lado = lado
		b_up = piso
	return [m + lat * (b_lado - lado) + Vector3.UP * (b_up - up), float(q[2]), Vector2(b_lado, b_up)]


## Alisamento de Taubin (sem encolher) com os vértices de mesma posição soldados: tira o serrilhado do relevo.
static func _alisar(pos: PackedVector3Array, idx: PackedInt32Array, passadas: int) -> PackedVector3Array:
	var chave := {}
	var grupo := PackedInt32Array()
	grupo.resize(pos.size())
	var unicos := PackedVector3Array()
	for k in pos.size():
		var ch := pos[k].snapped(Vector3.ONE * 0.0001)
		if not chave.has(ch):
			chave[ch] = unicos.size()
			unicos.append(pos[k])
		grupo[k] = chave[ch]
	var viz: Array[PackedInt32Array] = []
	viz.resize(unicos.size())
	for t in range(0, idx.size(), 3):
		for a in 3:
			var u := grupo[idx[t + a]]
			var v := grupo[idx[t + (a + 1) % 3]]
			if u != v and not viz[u].has(v):
				viz[u].append(v)
				viz[v].append(u)
	for passada in passadas * 2:
		var fator := 0.5 if passada % 2 == 0 else -0.53
		var nova := unicos.duplicate()
		for u in unicos.size():
			if viz[u].is_empty():
				continue
			var media := Vector3.ZERO
			for v in viz[u]:
				media += unicos[v]
			nova[u] = unicos[u] + (media / viz[u].size() - unicos[u]) * fator
		unicos = nova
	var saida := PackedVector3Array()
	saida.resize(pos.size())
	for k in pos.size():
		saida[k] = unicos[grupo[k]]
	return saida


## Se o ponto m está dentro do perfil do túnel (meia largura hw, de piso até htopo, em arco em cima), o metro da
## pista ali; senão -INF.
static func _no_tunel(pista: Array, m: Vector3, hw: float, htopo: float, piso: float) -> float:
	var melhor := INF
	var q: Array = []
	for p: Array in pista:
		var pp: Vector3 = p[0]
		var d := Vector2(m.x - pp.x, m.z - pp.z).length_squared()
		if d < melhor:
			melhor = d
			q = p
	if q.is_empty() or q == pista[0] or q == pista[pista.size() - 1]:
		return -INF
	var lado: float = (m - (q[0] as Vector3)).dot(q[1] as Vector3)
	var up: float = m.y - q[0].y
	if up < piso or up > htopo or absf(lado) > hw:
		return -INF
	return float(q[2]) if absf(lado) <= _meia_em(hw, htopo, up) else -INF


## Meia largura do perfil em arco a `up` m acima da pista: paredes retas até 60% da altura, depois meia-elipse.
static func _meia_em(hw: float, htopo: float, up: float) -> float:
	var parede := htopo * 0.6
	if up <= parede:
		return hw
	var t := (up - parede) / (htopo - parede)
	return hw * sqrt(maxf(1.0 - t * t, 0.0))


## Perfil do túnel (lateral, altura), da beira esquerda do chão, subindo pela parede, pelo arco e descendo.
static func _perfil(hw: float, htopo: float, piso: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	var parede := htopo * 0.6
	for k in 5:   # parede esquerda, do chão até o arco
		p.append(Vector2(-hw, lerpf(piso, parede, k / 5.0)))
	for k in 25:
		var a := PI - PI * k / 24.0
		p.append(Vector2(hw * cos(a), parede + (htopo - parede) * sin(a)))
	for k in range(4, -1, -1):   # parede direita, descendo
		p.append(Vector2(hw, lerpf(piso, parede, k / 5.0)))
	return p


## faixas: por ponto do perfil, [de, até] (metros da pista) onde a rocha chega; o tubo só existe ali (vazio = todo).
static func _tunel(no: Node3D, corpo: StaticBody3D, pista: Array, hw: float, htopo: float, piso: float, mat_rocha: ShaderMaterial, faixas: Array[Vector2] = []) -> void:
	var perfil := _perfil(hw, htopo, piso)
	var n := perfil.size()
	# Faixa de cada quadrado do perfil (k a k+1): a dos pontos vizinhos juntas; ponto sem rocha usa a de todos
	var geral := Vector2(INF, -INF)
	for fx: Vector2 in faixas:
		if fx.x <= fx.y:
			geral = Vector2(minf(geral.x, fx.x), maxf(geral.y, fx.y))
	var faixa_q: Array[Vector2] = []
	for k in n:
		var fq := Vector2(INF, -INF)
		for d in [-1, 0, 1, 2]:
			var fx: Vector2 = faixas[(k + d + n) % n] if faixas.size() == n else Vector2(-INF, INF)
			if fx.x <= fx.y:
				fq = Vector2(minf(fq.x, fx.x), maxf(fq.y, fx.y))
		faixa_q.append(fq if fq.x <= fq.y else geral)
	var per := PackedFloat32Array()   # comprimento acumulado do perfil (UV)
	per.append(0.0)
	for k in range(1, n):
		per.append(per[k - 1] + perfil[k].distance_to(perfil[k - 1]))
	var dentro := SurfaceTool.new()
	dentro.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dentro_b := SurfaceTool.new()   # a outra face
	dentro_b.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var ladrilho := 14.0   # m de cada repetição da textura interna
	# Paredes de rocha: ondulação suave pelo metro da pista e pela volta do perfil (sorteada a cada anel virava
	# faixas, um "corredor de molduras"); fica entre a borda da boca na rocha e 1 m atrás dela. Chão liso.
	var parede := htopo * 0.6
	var bruto := func(a: int, k: int) -> float:
		var m := float(pista[a][2])
		var o := 0.5 + 0.3 * sin(m * 0.09 + k * 0.35) * cos(m * 0.05 - k * 0.21) + 0.2 * sin(m * 0.17 + k * 0.6)
		return FOLGA - 0.2 + o * 1.2
	var anel := func(p: Array, k: int, extra: float) -> Vector3:
		var v: Vector2 = perfil[k]
		var dir := Vector2(signf(v.x), 0.0) if v.y <= parede + 0.01 else Vector2(v.x / hw, (v.y - parede) / (htopo - parede)).normalized()
		var off := dir * extra
		return (p[0] as Vector3) + (p[1] as Vector3) * (v.x + off.x) + Vector3.UP * (v.y + off.y)
	for a in pista.size() - 1:
		var pa: Array = pista[a]
		var pb: Array = pista[a + 1]
		for k in n:
			var k2 := (k + 1) % n
			if float(pb[2]) < faixa_q[k].x - 0.7 or float(pa[2]) > faixa_q[k].y + 0.7:
				continue
			var va: Vector3 = anel.call(pa, k, bruto.call(a, k))
			var vb: Vector3 = anel.call(pb, k, bruto.call(a + 1, k))
			var vc: Vector3 = anel.call(pb, k2, bruto.call(a + 1, k2))
			var vd: Vector3 = anel.call(pa, k2, bruto.call(a, k2))
			var ua := float(pa[2]) / ladrilho
			var ub := float(pb[2]) / ladrilho
			var pk := per[k] / ladrilho
			var pk2 := (per[k2] if k2 > 0 else per[n - 1] + perfil[n - 1].distance_to(perfil[0])) / ladrilho
			for q: Array in [[va, Vector2(ua, pk)], [vc, Vector2(ub, pk2)], [vb, Vector2(ub, pk)], [va, Vector2(ua, pk)], [vd, Vector2(ua, pk2)], [vc, Vector2(ub, pk2)]]:
				dentro.set_uv(q[1])
				dentro.add_vertex(q[0])
			for q: Array in [[va, Vector2(ua, pk)], [vb, Vector2(ub, pk)], [vc, Vector2(ub, pk2)], [va, Vector2(ua, pk)], [vc, Vector2(ub, pk2)], [vd, Vector2(ua, pk2)]]:
				dentro_b.set_uv(q[1])
				dentro_b.add_vertex(q[0])
			faces.append_array([va, vc, vb, va, vd, vc])
	no.add_to_group("montanha_armadilha")
	no.set_meta("bocas", [[pista[0][0], (pista[1][0] as Vector3) - (pista[0][0] as Vector3)], [pista[pista.size() - 1][0], (pista[pista.size() - 2][0] as Vector3) - (pista[pista.size() - 1][0] as Vector3)]])
	for st_d: SurfaceTool in [dentro, dentro_b]:
		st_d.index()
		st_d.generate_normals()
		st_d.generate_tangents()
	# Dentro e bocas: a mesma rocha da montanha (pedido do dono: paredes de pedra, não de friso)
	var mr := mat_rocha   # a mesma pedra de fora
	var mi := MeshInstance3D.new()
	mi.name = "PassagemDentro"
	var md := dentro.commit()
	dentro_b.commit(md)
	mi.mesh = md
	mi.material_override = mr
	no.add_child(mi)
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	corpo.add_child(cs)
	# Luz lá dentro: tochas quentes nas paredes, a cada ~28 m
	var passo := maxi(int(pista.size()), 1)
	for a in range(passo / 2, pista.size(), passo):
		var p: Array = pista[a]
		for s: float in [-1.0, 1.0]:
			var luz := OmniLight3D.new()
			luz.light_color = Color(1.0, 0.62, 0.3)
			luz.light_energy = 3.0
			luz.omni_range = 34.0
			luz.position = (p[0] as Vector3) + (p[1] as Vector3) * s * (hw - 2.0) + Vector3.UP * 9.0
			no.add_child(luz)
			Fogo.criar(no, luz.position - Vector3.UP * 0.6, 0.5, 1.6, 14, 0.8, false)


# ------------------------------------------------------------------ portal e machado

static func _portal(arm: Armadilhas, no: Node3D, c: Vector3, b: Basis, tx: Array, larg: float, alt: float, y0: float) -> Dictionary:
	var para_fora := b.z   # para quem chega
	var olhar := Basis.looking_at(-para_fora, Vector3.UP)
	var centro := c + Vector3.UP * (y0 + alt * 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/arte_relevo.gdshader")
	mat.set_shader_parameter("imagem", tx[0])
	mat.set_shader_parameter("brilho", 0.12)
	mat.set_shader_parameter("fogo", 0.0)
	var esp := larg * 0.07
	var fachada := TunelVulcao.relevo_arte(PORTAL, tx, Rect2(0, 0, 1, 1), tx[4], larg, alt, esp, larg * 0.03, larg * 0.016)
	for face in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = fachada
		mi.material_override = mat
		mi.transform = Transform3D(olhar if face == 0 else olhar * Basis(Vector3.UP, PI), centro + para_fora * esp * (1.0 if face == 0 else -1.0))
		no.add_child(mi)
	# Colisão (parede comum): pilares e lintel
	var est := arm._corpo_mortal(no)
	var dir := olhar.x
	var caixas: Array = []
	for r: Rect2 in [Rect2(0.04, 0.27, 0.26, PE_V - 0.27), Rect2(0.70, 0.27, 0.26, PE_V - 0.27), Rect2(0.05, 0.10, 0.90, 0.17)]:
		var meio := centro + dir * ((r.get_center().x - 0.5) * larg) + Vector3.UP * ((0.5 - r.get_center().y) * alt)
		caixas.append(Transform3D(olhar * Basis.from_scale(Vector3(r.size.x * larg, r.size.y * alt, esp * 2.0)), meio))
	ComplexoLancamento.adicionar_colisoes(est, caixas)
	# Olhos: luz vermelha de verdade e as lâmpadas de aviso dos bots/jogador no lugar deles
	var lampadas: Array = []
	for u: float in [0.18, 0.815]:
		var olho := centro + dir * ((u - 0.5) * larg) + Vector3.UP * ((0.5 - 0.49) * alt)
		for face: float in [1.0, -1.0]:
			var p := olho + para_fora * (esp + larg * 0.03) * face
			var luz := OmniLight3D.new()
			luz.light_color = Color(1.0, 0.15, 0.08)
			luz.light_energy = 4.0
			luz.omni_range = 16.0
			luz.position = p + para_fora * 1.5 * face
			no.add_child(luz)
			var m := arm._lampada(no, p, larg * 0.016)
			if face > 0.0:
				lampadas.append(m)
	# Machado: argola, haste repetida e lâmina, presos no pivô (o disco dourado)
	var hp := y0 + alt * (1.0 - PIVO_V)
	var l := hp - 0.6
	var corpo := arm._corpo_mortal(no, true)
	var pedacos: Array = []   # [rect UV, y do meio abaixo do pivô, escala vertical]
	var topo_h := (HASTE[0] - MACHADO.position.y) * alt
	var y := (MACHADO.position.y - PIVO_V) * alt
	pedacos.append([Rect2(MACHADO.position.x, MACHADO.position.y, MACHADO.size.x, HASTE[0] - MACHADO.position.y), y + topo_h * 0.5, 1.0])
	y += topo_h
	var cab_h := (MACHADO.end.y - CABECA_V) * alt
	var haste_total := l - y - cab_h
	var tile := (float(HASTE[1]) - float(HASTE[0])) * alt
	var n_tiles := maxi(1, roundi(haste_total / tile))
	var esc_t := haste_total / (n_tiles * tile)
	for k in n_tiles:
		pedacos.append([Rect2(MACHADO.position.x, HASTE[0], MACHADO.size.x, HASTE[1] - HASTE[0]), y + tile * esc_t * 0.5, esc_t])
		y += tile * esc_t
	pedacos.append([Rect2(MACHADO.position.x, CABECA_V, MACHADO.size.x, MACHADO.end.y - CABECA_V), y + cab_h * 0.5, 1.0])
	var esp_m := larg * 0.012
	for pd: Array in pedacos:
		var r: Rect2 = pd[0]
		var malha := TunelVulcao.relevo_arte(PORTAL, tx, r, tx[5], larg, alt, esp_m, larg * 0.008, larg * 0.006)
		for face in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = malha
			mi.material_override = mat
			var giro := Basis.IDENTITY if face == 0 else Basis(Vector3.UP, PI)
			mi.transform = Transform3D(giro * Basis.from_scale(Vector3(1.0, float(pd[2]), 1.0)), Vector3((r.get_center().x - 0.5) * larg, -float(pd[1]), esp_m * (1.0 if face == 0 else -1.0)))
			corpo.add_child(mi)
	var meia_lam := (0.646 - 0.355) * 0.5 * larg
	# Balanço máximo: o canto mais de fora da lâmina chega só até a parede de pedra do túnel (passava dela)
	var limite := larg * 0.5 + 2.0 - 0.3
	var amp := 0.0
	while amp < deg_to_rad(85.0):
		var prox := amp + deg_to_rad(0.5)
		var maior := 0.0
		for canto: Vector2 in [Vector2(meia_lam, l), Vector2(meia_lam, l - cab_h), Vector2(larg * 0.03, 0.0)]:
			maior = maxf(maior, canto.x * cos(prox) + canto.y * sin(prox))
		if maior > limite:
			break
		amp = prox
	arm._forma_caixa(corpo, Vector3(larg * 0.06, l - cab_h, esp_m * 4.0), Transform3D(Basis.IDENTITY, Vector3(0, -(l - cab_h) * 0.5, 0)))
	arm._forma_caixa(corpo, Vector3(meia_lam * 2.0, cab_h * 0.8, esp_m * 4.0), Transform3D(Basis.IDENTITY, Vector3(0, -l + cab_h * 0.4, 0)))
	return {"corpo": corpo, "l": l, "hp": hp, "pivo": c + Vector3.UP * hp, "meia_lam": meia_lam, "lampadas": lampadas, "amp": amp,
		"base": Basis.looking_at(-para_fora, Vector3.UP)}
