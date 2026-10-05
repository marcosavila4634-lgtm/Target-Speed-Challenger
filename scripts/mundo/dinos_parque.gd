class_name DinosParque
extends Node3D
## Dinossauros do Extinction Day (só visuais, sem colisão — os que atacam ficam nas Armadilhas):
## manadas de titanossauros, tiranossauros, espinossauros, carnotauros, alossauros e bandos de
## ceratossauros andando em voltas pelo vale, longe das estradas; pterossauros planando em volta do
## vulcão. Os modelos (assets/dino) têm esqueleto: a passada é feita aqui, girando os ossos em volta
## de eixos do próprio bicho (lateral para as pernas, vertical para cauda e pescoço), o que funciona
## qualquer que seja a orientação dos ossos no arquivo. O T-Rex lowpoly usa a animação dele.

## Espécies: [arquivo, comprimento (m), velocidade (m/s), passada (fração do comprimento), quadrúpede]
const ESPECIES := {
	"trex": ["res://assets/dino/trex/trex.glb", 15.0, 4.6, 0.34, false],
	"tiranossauro": ["res://assets/dino/tiranossauro/tiranossauro.glb", 14.5, 4.4, 0.34, false],
	"carnotauro": ["res://assets/dino/carnotauro/carnotauro.glb", 9.0, 5.5, 0.36, false],
	"espinossauro": ["res://assets/dino/espinossauro/espinossauro.glb", 17.0, 3.6, 0.3, false],
	"ceratossauro": ["res://assets/dino/ceratossauro/ceratossauro.glb", 7.5, 5.5, 0.36, false],
	"raptor": ["res://assets/dino/ceratossauro/ceratossauro.glb", 3.8, 7.5, 0.42, false],
	"titanossauro": ["res://assets/dino/titanossauro/titanossauro.glb", 40.0, 2.2, 0.2, true],
}

## Amplitude da passada (rad) com intensidade 1
const AMP := 0.32

static var _cenas := {}

var _bichos: Array = []       # {d: dados do bicho, centro, raio_a, raio_b, giro, fase, vel, sentido}
var _ptero: Dictionary = {}
var _t := 0.0
var _terreno: Terreno


# ------------------------------------------------------------------ bicho animado (usado também pelas armadilhas)

## Monta um dinossauro da espécie com o comprimento pedido. Devolve {raiz (Node3D, frente = -Z, pés
## em y = 0), esq (Skeleton3D ou null), anim (AnimationPlayer ou null), pernas, cauda, pescoco,
## cabeca, mandibula, quad, comp, passada}.
static func criar(especie: String, comprimento := 0.0) -> Dictionary:
	var e: Array = ESPECIES.get(especie, ESPECIES["carnotauro"])
	if not _cenas.has(e[0]):
		_cenas[e[0]] = load(e[0]) if ResourceLoader.exists(e[0]) else null
	var raiz := Node3D.new()
	raiz.name = especie
	var d := {"raiz": raiz, "esq": null, "anim": null, "pernas": [], "cauda": [], "pescoco": [], "cabeca": -1, "mandibula": -1,
		"quad": bool(e[4]), "comp": comprimento if comprimento > 0.0 else float(e[1]), "passada": float(e[3]), "especie": especie,
		"quadril": 0.0, "passo": 0.0, "anda": 0.0, "xf_ant": null, "pes_ossos": PackedInt32Array()}
	d.quadril = float(d.comp) * 0.2
	if _cenas[e[0]] == null:
		return d
	var modelo: Node3D = (_cenas[e[0]] as PackedScene).instantiate()
	var giro := Node3D.new()   # gira e escala o modelo para a frente ficar em -Z e os pés no chão
	giro.add_child(modelo)
	raiz.add_child(giro)
	var esq: Skeleton3D = modelo.find_child("*", true, false) as Skeleton3D
	for s in modelo.find_children("*", "Skeleton3D", true, false):
		esq = s
		break
	d.esq = esq
	# A animação do arquivo começa sozinha ao entrar na cena e tira o bicho do lugar (o titanossauro do
	# alvo sumia): sai fora — a passada de todos é feita por código (pose)
	for a in modelo.find_children("*", "AnimationPlayer", true, false):
		a.get_parent().remove_child(a)
		a.free()
	# Medidas no espaço do modelo (pose de repouso). Malha com pele: o motor aplica os ossos (osso em
	# repouso x pose de ligação) e depois a transformação da PRÓPRIA MeshInstance — então ossos e
	# malha são medidos no referencial da malha (xf_r), não no do esqueleto (que pode estar girado).
	var aabb := AABB()
	var primeira := true
	var com_pele: Array = []   # [malha, transformação até o modelo]
	var xf_r := Transform3D.IDENTITY
	var tem_r := false
	for mi in modelo.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := _xf_ate(m, modelo)
		var xf_inst := xf
		if m.skin and esq:
			com_pele.append([m, xf_inst])
		if m.skin and esq:
			if not tem_r:
				xf_r = xf
				tem_r = true
			var b0 := m.skin.get_bind_bone(0)
			if b0 < 0:
				b0 = esq.find_bone(m.skin.get_bind_name(0))
			if b0 >= 0:
				xf = xf * esq.get_bone_global_rest(b0) * m.skin.get_bind_pose(0)
		var caixa := xf * m.get_aabb()
		aabb = caixa if primeira else aabb.merge(caixa)
		primeira = false
		m.visibility_range_end = 1600.0 if d.comp > 20.0 else 1000.0
		m.visibility_range_end_margin = 150.0
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# Orientação pela anatomia: frente = da ponta da cauda para a cabeça, cima = dos pés para o quadril
	# (alguns modelos vêm com o esqueleto "em pé" no arquivo). Sem esqueleto: o lado maior da caixa.
	var frente := Vector3.ZERO
	var cima := Vector3.UP
	var juntas: Array[Vector3] = []
	var pes_idx := PackedInt32Array()   # ossos de pé, tornozelo e dedos (ver pose: o mais baixo fica no chão)
	if esq:
		var xf_e := xf_r if tem_r else _xf_ate(esq, modelo)
		var cab := Vector3.INF
		var cauda := Vector3.INF
		var quadril := Vector3.INF
		var pes := Vector3.ZERO
		var n_pes := 0
		var pes_lista: Array[Vector3] = []   # pés, tornozelos e dedos: o chão é onde ELES pisam
		var pes_frente: Array[Vector3] = []   # quadrúpede: patas da frente e de trás em separado
		var pes_tras: Array[Vector3] = []
		for b in esq.get_bone_count():
			var nome := esq.get_bone_name(b).to_lower()
			var q := xf_e * esq.get_bone_global_rest(b).origin
			# Raízes do esqueleto podem ficar longe do bicho (origem do arquivo): fora da medida
			# (ossos "_end" de vários modelos caem todos num ponto só, fora do bicho: também não medem nada)
			if not ("root" in nome or "center" in nome or "end" in nome or esq.get_bone_parent(b) < 0):
				juntas.append(q)
			if cab == Vector3.INF and "head" in nome:
				cab = q
			if "tail" in nome and not "end" in nome:
				cauda = q   # o último osso da cauda (na ordem do esqueleto) é a ponta
			if quadril == Vector3.INF and ("pelvis" in nome or "hip" in nome):
				quadril = q
			if ("foot" in nome or "ankle" in nome) and not "end" in nome:
				pes += q
				n_pes += 1
			if ("foot" in nome or "ankle" in nome or "toe" in nome) and not "end" in nome:
				pes_lista.append(q)
				pes_idx.append(b)
				if "_fl_" in nome or "_fr_" in nome:
					pes_frente.append(q)
				else:
					pes_tras.append(q)
		if cab != Vector3.INF and cauda != Vector3.INF:
			frente = (cab - cauda).normalized()
		elif juntas.size() > 4:
			# Ossos sem nome (alossauro): o eixo mais comprido da nuvem de juntas é a coluna; a cabeça
			# fica do lado em que as juntas estão mais altas (pescoço e crânio acima da ponta da cauda)
			var c0 := Vector3.ZERO
			for q in juntas:
				c0 += q
			c0 /= juntas.size()
			var melhor := Vector3.ZERO
			var ext := -1.0
			for eixo: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1, 1, 0).normalized(), Vector3(0, 1, 1).normalized(), Vector3(1, 0, 1).normalized(), Vector3(1, -1, 0).normalized(), Vector3(0, 1, -1).normalized(), Vector3(1, 0, -1).normalized()]:
				var a := INF
				var bmax := -INF
				for q in juntas:
					a = minf(a, (q - c0).dot(eixo))
					bmax = maxf(bmax, (q - c0).dot(eixo))
				if bmax - a > ext:
					ext = bmax - a
					melhor = eixo
			frente = melhor
			if OS.get_environment("TSC_DINO_LOG") != "":
				print("[DINO] %s sem nomes: eixo %s extensão %.1f" % [especie, str(melhor), ext])
		if quadril != Vector3.INF and n_pes > 0:
			cima = quadril - pes / n_pes
		d["_pes"] = pes_lista
		d["_pes_frente"] = pes_frente
		d["_pes_tras"] = pes_tras
	# Caixa de descarte das malhas com pele: a do arquivo pode ficar longe de onde os ossos põem o bicho
	# (titanossauro: 459 m — ele sumia conforme o ângulo da câmera). Caixa própria, em volta das juntas.
	if juntas.size() > 4:
		var cj := AABB(juntas[0], Vector3.ZERO)
		for q in juntas:
			cj = cj.expand(q)
		cj = cj.grow(cj.get_longest_axis_size() * 0.3)
		for par: Array in com_pele:
			(par[0] as MeshInstance3D).custom_aabb = (par[1] as Transform3D).affine_inverse() * cj
	if frente == Vector3.ZERO:
		frente = Vector3(0, 0, 1) if aabb.size.z >= aabb.size.x else Vector3(1, 0, 0)
	# Cima (pés → quadril) manda; a frente é a direção cauda → cabeça deitada nesse plano (pescoço
	# erguido do titanossauro não pode inclinar o corpo)
	cima = cima.normalized()
	# "Pés → quadril" só diz para que lado fica o alto: nos bípedes o osso do quadril fica ATRÁS dos pés
	# (tiranossauro 13°, carnotauro 17°, T-Rex 6°) e, com essa linha como vertical, eles andavam de focinho
	# para baixo e cauda para o alto, com os pés fora do chão (reclamação do dono: "caminhando errado,
	# flutuando"). O arquivo vem alinhado a um eixo: vale o eixo do modelo mais perto dessa linha.
	for eixo: Vector3 in [Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		if cima.dot(eixo) > 0.9:
			cima = eixo
	frente = (frente - cima * frente.dot(cima))
	if frente.length() < 0.01:
		frente = Vector3.FORWARD - cima * cima.z
	frente = frente.normalized()
	var lado := frente.cross(cima).normalized()
	cima = lado.cross(frente).normalized()
	# Quadrúpede: o chão é a linha das patas de trás às da frente. Só com "pés → quadril" (o quadril fica lá
	# atrás e os pés, no meio) o titanossauro saía empinado 17°: cauda para o alto e patas da frente no ar.
	var pf: Array = d.get("_pes_frente", [])
	var pt: Array = d.get("_pes_tras", [])
	if not pf.is_empty() and not pt.is_empty():
		var mais_baixo := func(lista: Array) -> Vector3:
			var m: Vector3 = lista[0]
			for q: Vector3 in lista:
				if q.dot(cima) < m.dot(cima):
					m = q
			return m
		var solo: Vector3 = mais_baixo.call(pf) - mais_baixo.call(pt)
		solo -= lado * solo.dot(lado)
		if solo.length() > 0.01 and solo.dot(frente) > 0.0:
			frente = solo.normalized()
			cima = lado.cross(frente).normalized()
	d.erase("_pes_frente")
	d.erase("_pes_tras")
	# Base: frente do modelo → -Z do giro, cima → +Y
	var b_modelo := Basis(lado, cima, -frente).inverse()
	var mn := Vector3.INF
	var mx := -Vector3.INF
	if not juntas.is_empty():
		for q in juntas:
			var g := b_modelo * q
			mn = mn.min(g)
			mx = mx.max(g)
	else:
		for k in 8:
			var g := b_modelo * aabb.get_endpoint(k)
			mn = mn.min(g)
			mx = mx.max(g)
	# As juntas ficam por dentro do bicho: focinho e ponta da cauda passam um pouco delas
	var comp_modelo := (mx.z - mn.z) * (1.1 if not juntas.is_empty() else 1.0)
	var esc := float(d.comp) / maxf(comp_modelo, 0.01)
	giro.transform = Transform3D(Basis.from_scale(Vector3.ONE * esc) * b_modelo, Vector3.ZERO)
	# Chão: pela junta mais baixa dos PÉS (o tiranossauro tem ossos de controle bem abaixo deles e ficava
	# flutuando uns 4 m — reclamação do dono); a sola fica um pouco abaixo da junta
	var chao_y := mn.y
	# Meio do bicho de lado a lado: entre os pés. Pela caixa das juntas não serve — o ceratossauro tem a junta-raiz
	# a 9 m do corpo, e o bicho ficava 4,5 m fora do lugar (os cuspidores em pé no ar, ao lado da laje deles)
	var meio_x := (mn.x + mx.x) * 0.5
	var pes_m: Array = d.get("_pes", [])
	if not pes_m.is_empty():
		chao_y = INF
		meio_x = 0.0
		for q: Vector3 in pes_m:
			chao_y = minf(chao_y, (b_modelo * q).y)
			meio_x += (b_modelo * q).x / pes_m.size()
		chao_y -= (mx.z - mn.z) * 0.012
	d.erase("_pes")
	giro.position = -Vector3(meio_x, chao_y, (mn.z + mx.z) * 0.5) * esc
	# Para a passada (pose): a cada quadro o pé mais baixo volta para o chão — do osso até o referencial da raiz
	if esq and not pes_idx.is_empty():
		d.pes_ossos = pes_idx
		d["pes_xf"] = giro.transform * (xf_r if tem_r else _xf_ate(esq, modelo))
		d["pes_folga"] = (mx.z - mn.z) * 0.012 * esc   # a sola fica um pouco abaixo da junta
		d["giro_y0"] = giro.position.y
		# Onde os pés ficam ao longo do corpo (z na raiz): é em volta deles que o corpo inclina (ver Armadilhas)
		var z_pes := 0.0
		for b in pes_idx:
			z_pes += (d.pes_xf * esq.get_bone_global_rest(b).origin).z / pes_idx.size()
		d["pes_z"] = z_pes
	aabb = AABB(mn, mx - mn)
	d["altura"] = aabb.size.y * esc
	d["giro"] = giro
	if OS.get_environment("TSC_DINO_LOG") != "":
		print("[DINO] %s comp=%.1f modelo=%.2f esc=%.3f altura=%.1f frente=%s ossos=%d chão: junta mais baixa %.2f, pés %.2f" % [especie, d.comp, comp_modelo, esc, d.altura, str(frente), esq.get_bone_count() if esq else 0, mn.y * esc, chao_y * esc])
	if esq == null:
		return d
	# Ossos, com o eixo de giro (lateral e vertical do bicho) já convertido para o espaço de cada osso
	var xf_e := xf_r if tem_r else _xf_ate(esq, modelo)
	var lado_m := lado
	var cima_m := cima
	var conv := func(b: int, eixo: Vector3) -> Vector3:
		var g: Basis = (xf_e.basis * esq.get_bone_global_rest(b).basis).orthonormalized()
		return (g.inverse() * eixo).normalized()
	for b in esq.get_bone_count():
		var nome := esq.get_bone_name(b)
		var n := nome.to_lower()
		if "end" in n or "toe" in n or "fat" in n or "digit" in n or "collar" in n:
			continue
		var lado_l := ""
		if n.begins_with("l") and nome.length() > 1 and nome[1] == nome[1].to_upper() and nome[1] != "_" or "_l" in n or "lleg" in n or "_fl_" in n or "_bl_" in n:
			lado_l = "e"
		if n.begins_with("r") and nome.length() > 1 and nome[1] == nome[1].to_upper() and nome[1] != "_" or "rleg" in n or "_fr_" in n or "_br_" in n:
			lado_l = "d"
		var frente_tras := "t"
		if "_fl_" in n or "_fr_" in n:
			frente_tras = "f"
		var nivel := -1
		if "ankle" in n:
			nivel = 2
		elif "foot" in n:
			nivel = 3   # pé depois do tornozelo: fica como está (se a perna não tiver tornozelo, vira 2 logo abaixo)
		elif "upleg" in n or "thigh" in n or "leg1" in n:
			nivel = 0
		elif "shin" in n or "leg2" in n or ("leg" in n and lado_l != ""):
			nivel = 1
		if nivel >= 0 and lado_l != "" and not "arm" in n:
			d.pernas.append({"b": b, "lado": lado_l, "ft": frente_tras, "nivel": nivel, "rest": esq.get_bone_rest(b).basis.get_rotation_quaternion(), "eixo": conv.call(b, lado_m)})
		elif "tail" in n:
			d.cauda.append({"b": b, "rest": esq.get_bone_rest(b).basis.get_rotation_quaternion(), "eixo": conv.call(b, cima_m), "eixo_l": conv.call(b, lado_m)})
		elif "neck" in n:
			d.pescoco.append({"b": b, "rest": esq.get_bone_rest(b).basis.get_rotation_quaternion(), "eixo": conv.call(b, cima_m), "eixo_l": conv.call(b, lado_m)})
		elif "head" in n and d.cabeca < 0:
			d.cabeca = b
			d["cabeca_eixo_l"] = conv.call(b, lado_m)
			d["cabeca_rest"] = esq.get_bone_rest(b).basis.get_rotation_quaternion()
		elif ("jaw" in n or "jew" in n) and d.mandibula < 0:
			d.mandibula = b
			d["mand_eixo"] = conv.call(b, lado_m)
			d["mand_rest"] = esq.get_bone_rest(b).basis.get_rotation_quaternion()
	for p: Dictionary in d.pernas:
		if int(p.nivel) == 3 and not d.pernas.any(func(o: Dictionary) -> bool: return int(o.nivel) == 2 and o.lado == p.lado and o.ft == p.ft):
			p.nivel = 2
	# Altura do quadril (m): dela sai quanto chão o bicho cobre a cada ciclo da passada (ver andar)
	var hq := 0.0
	var nq := 0
	for p: Dictionary in d.pernas:
		if int(p.nivel) == 0:
			hq += ((b_modelo * (xf_e * esq.get_bone_global_rest(p.b).origin)).y - chao_y) * esc   # do chão (pés), não da junta mais baixa
			nq += 1
	if nq > 0 and hq / nq > 0.1:
		d.quadril = hq / nq
	if OS.get_environment("TSC_DINO_LOG") != "":
		print("[DINO] %s quadril=%.1f pernas=%d ciclo=%.1f" % [especie, d.quadril, d.pernas.size(), 4.0 * float(d.quadril) * sin(AMP)])
	return d


## Transformação acumulada do nó até `ate` (exclusive).
static func _xf_ate(no: Node3D, ate: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = no
	while n and n != ate:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Pose da passada na fase `fase` (rad): pernas balançando (diagonais no quadrúpede), cauda e pescoço
## acompanhando, cabeça baixando no ataque. `intensidade` 0 = parado, 1 = andando, 2 = correndo.
## `boca` 0..1 abre a mandíbula; `bote` 0..1 estica pescoço e cabeça para a frente e para baixo.
static func pose(d: Dictionary, fase: float, intensidade := 1.0, boca := 0.0, bote := 0.0) -> void:
	var esq: Skeleton3D = d.esq
	if esq == null:
		return
	var amp := AMP * intensidade
	for p: Dictionary in d.pernas:
		var f := fase + (PI if p.lado == "d" else 0.0)
		if d.quad and p.ft == "f":
			f += PI   # quadrúpede: diagonais juntas
		var ang := 0.0
		var coxa := sin(f) * amp
		# O joelho só dobra com o pé no ar (perna indo para a frente); no chão a perna fica esticada
		var joelho := -maxf(0.0, cos(f)) * amp * 1.2
		match int(p.nivel):
			0: ang = coxa
			1: ang = joelho
			# O tornozelo desfaz o giro da perna: o pé de apoio fica CHATO no chão a passada inteira (antes ele
			# girava junto e pisava de ponta, enrolado); no ar, a ponta cai um pouco
			2: ang = -(coxa + joelho) * (1.0 - 0.4 * maxf(0.0, cos(f)))
		esq.set_bone_pose_rotation(p.b, p.rest * Quaternion(p.eixo, ang))
	var k := 0
	for c: Dictionary in d.cauda:
		var ang := sin(fase * 0.5 + k * 0.45) * 0.05 * (0.6 + intensidade * 0.4)
		esq.set_bone_pose_rotation(c.b, c.rest * Quaternion(c.eixo, ang) * Quaternion(c.eixo_l, sin(fase + k * 0.3) * 0.015 * intensidade))
		k += 1
	k = 0
	for c: Dictionary in d.pescoco:
		var ang := sin(fase * 0.5 + 1.0 + k * 0.3) * 0.04
		esq.set_bone_pose_rotation(c.b, c.rest * Quaternion(c.eixo, ang) * Quaternion(c.eixo_l, bote * 0.12))
		k += 1
	if d.cabeca >= 0:
		esq.set_bone_pose_rotation(d.cabeca, d.cabeca_rest * Quaternion(d.cabeca_eixo_l, bote * 0.25 + sin(fase) * 0.03 * intensidade))
	if d.mandibula >= 0:
		esq.set_bone_pose_rotation(d.mandibula, d.mand_rest * Quaternion(d.mand_eixo, -boca * 0.55))
	# Pés no chão (pedido do dono: "precisa caminhar perfeitamente no chão"): a perna balança em volta do quadril
	# e, com o corpo sempre na mesma altura, o pé de apoio saía do chão nas pontas da passada. O corpo desce
	# (e sobe) o que falta para a junta mais baixa dos pés ficar onde fica com o bicho parado.
	var ossos: PackedInt32Array = d.pes_ossos
	if not ossos.is_empty():
		var xf_p: Transform3D = d.pes_xf
		var baixo := INF
		for b in ossos:
			baixo = minf(baixo, (xf_p * esq.get_bone_global_pose(b).origin).y)
		(d.giro as Node3D).position.y = float(d.giro_y0) - (baixo - float(d.pes_folga))


## Passada presa ao chão: a fase avança pelo que o bicho andou (e girou) desde a última chamada, e não
## pelo relógio — os pés não patinam, seja qual for a velocidade. Parado, as pernas voltam ao repouso.
## `xf` é a transformação global do bicho neste quadro; `forca` é a intensidade da passada andando.
static func andar(d: Dictionary, xf: Transform3D, delta: float, forca := 1.0, boca := 0.0, bote := 0.0) -> void:
	var avanco := 0.0
	if d.xf_ant != null:
		var ant: Transform3D = d.xf_ant
		var dp := xf.origin - ant.origin
		dp.y = 0.0
		# Girando no lugar, os pés dão a volta em torno do meio do corpo
		avanco = dp.length() + absf(ant.basis.z.signed_angle_to(xf.basis.z, Vector3.UP)) * float(d.comp) * 0.2
		if avanco > float(d.comp):
			avanco = 0.0   # foi reposicionado, não andou
	d.xf_ant = xf
	var andando := avanco > 0.2 * delta
	d.anda = move_toward(float(d.anda), 1.0 if andando else 0.0, delta * 2.5)
	# Com o pé no chão metade do ciclo, a perna varre 2·quadril·sen(amplitude): o ciclo cobre o dobro
	var ciclo := 4.0 * float(d.quadril) * sin(AMP * forca)
	var freq := avanco / maxf(delta, 0.0001) / maxf(ciclo, 0.3)
	# Rápido demais para andar (perna curta não acompanha): corre — passada mais aberta, no ritmo
	# natural do tamanho do bicho, em vez de pernas frenéticas
	var freq_max := 1.9 / sqrt(maxf(float(d.quadril), 0.3))
	var corre := 0.0
	if freq > freq_max:
		corre = clampf(freq / freq_max - 1.0, 0.0, 1.0)
		freq = freq_max
	d.passo = float(d.passo) + freq * delta * TAU + delta * 1.2 * (1.0 - float(d.anda))
	pose(d, float(d.passo), lerpf(0.12, forca * (1.0 + corre), float(d.anda)), boca, bote)


# ------------------------------------------------------------------ vale

func montar(dino: Dino, terreno: Terreno, cfg: Dictionary) -> void:
	_terreno = terreno
	# Os bichos são movidos a cada quadro (_process): com a interpolação da física ligada eles tremiam
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var rng := RandomNumberGenerator.new()
	rng.seed = 6620
	var vale: Array = Config.valor("mapa.subida.vale", [-2800, -2500, 1900, 1700])
	# [espécie, grupos, bichos por grupo, raio mín, raio máx]
	var grupos := [
		["titanossauro", int(cfg.get("titanossauros", 5)), [2, 4], 140.0, 260.0],
		["trex", int(cfg.get("trex", 3)), [1, 1], 80.0, 180.0],
		["tiranossauro", int(cfg.get("tiranossauros", 2)), [1, 2], 80.0, 160.0],
		["espinossauro", int(cfg.get("espinossauros", 3)), [1, 2], 70.0, 150.0],
		["carnotauro", int(cfg.get("carnotauros", 3)), [1, 3], 60.0, 140.0],
		["ceratossauro", int(cfg.get("ceratossauros", 3)), [2, 4], 50.0, 120.0],
		["raptor", int(cfg.get("raptores", 4)), [3, 5], 40.0, 90.0],
	]
	for g: Array in grupos:
		for n in int(g[1]):
			# Volta livre: elipse inteira em chão firme, longe das estradas e da lava
			var achou := false
			var centro := Vector2.ZERO
			var ra := 0.0
			var rb := 0.0
			var giro := 0.0
			for tentativa in 80:
				centro = Vector2(rng.randf_range(float(vale[0]) + 150.0, float(vale[2]) - 150.0), rng.randf_range(float(vale[1]) + 150.0, float(vale[3]) - 150.0))
				if tentativa < 60 and not dino._estradas.is_empty():
					# De preferência ao lado de uma estrada baixa (quem passa vê os bichos de perto)
					var pts: PackedVector3Array = dino._estradas[rng.randi() % dino._estradas.size()]
					var q := pts[rng.randi() % pts.size()]
					if q.y > 120.0:
						continue
					var ang := rng.randf() * TAU
					centro = Vector2(q.x, q.z) + Vector2(cos(ang), sin(ang)) * rng.randf_range(g[3] + 70.0, g[4] + 160.0)
				ra = rng.randf_range(g[3], g[4])
				rb = ra * rng.randf_range(0.5, 0.9)
				giro = rng.randf() * TAU
				achou = true
				for k in 16:
					var a := TAU * k / 16.0
					var p := centro + Vector2(cos(a) * ra, sin(a) * rb).rotated(giro)
					var h := terreno.altura_em(p.x, p.y)
					if h > 60.0 or dino.dist_estrada(p) < 45.0 or dino.estrada_perto(p, h, 40.0) or not dino.livre(p, 5.0, 10.0):
						achou = false
						break
				if achou:
					break
			if not achou:
				continue
			var qtd := rng.randi_range(g[2][0], g[2][1])
			var sentido := 1.0 if rng.randf() < 0.5 else -1.0
			var fase0 := rng.randf() * TAU
			for k in qtd:
				var esp: String = g[0]
				var comp: float = ESPECIES[esp][1] * rng.randf_range(0.85, 1.1)
				var d := criar(esp, comp)
				add_child(d.raiz)
				d.passo = rng.randf() * TAU
				var fase := fase0 - k * (comp * 1.4) / ra
				_bichos.append({"d": d, "centro": centro, "ra": ra, "rb": rb, "giro": giro, "fase": fase, "ang": fase,
					"vel": float(ESPECIES[esp][2]) * rng.randf_range(0.85, 1.1), "sentido": sentido, "lado": rng.randf_range(-1.0, 1.0) * comp * 0.5})
	_montar_pterossauros(dino, rng, int(cfg.get("pterossauros", 26)))
	if OS.get_environment("TSC_DINO_ZOO") != "":
		# Conferência de tamanho: as espécies em fila ao lado de postes de 10 m (perto de 1700, 1500)
		var k := 0
		var poste := BoxMesh.new()
		poste.size = Vector3(0.6, 10.0, 0.6)
		var vermelho := StandardMaterial3D.new()
		vermelho.albedo_color = Color(1, 0.1, 0.1)
		for esp in ESPECIES:
			var d := criar(esp)
			add_child(d.raiz)
			var p := Vector3(1450.0 + k * 40.0, 0.0, 1450.0)
			p.y = 600.0
			var chao_z := MeshInstance3D.new()
			var bz := BoxMesh.new()
			bz.size = Vector3(40, 1, 60)
			chao_z.mesh = bz
			chao_z.position = p + Vector3.DOWN * 0.5
			add_child(chao_z)
			d.raiz.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), p)
			var mi := MeshInstance3D.new()
			mi.mesh = poste
			mi.material_override = vermelho
			mi.position = p + Vector3(0, 5.0, 12.0)
			add_child(mi)
			k += 1
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[DINO] dinossauros andando: ", _bichos.size())


## Pterossauros (ave do Fauna em tamanho de pterossauro: bico comprido, crista, quase sem cauda e
## asas enormes de couro): planam em círculos largos em volta do vulcão e sobre a mata.
func _montar_pterossauros(dino: Dino, rng: RandomNumberGenerator, qtd: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = Fauna._malha_passaro(0.55, 0.12, 2.3)
	mm.instance_count = qtd
	var aves := []
	for i in qtd:
		var perto_vulcao := rng.randf() < 0.55
		var c := dino.centro_vulcao + Vector2(rng.randf_range(-500, 500), rng.randf_range(-500, 500)) if perto_vulcao else Vector2(rng.randf_range(-2400, 1600), rng.randf_range(-2200, 1400))
		aves.append({"c": Vector3(c.x, rng.randf_range(260.0, 520.0) if perto_vulcao else rng.randf_range(120.0, 300.0), c.y), "r": rng.randf_range(120.0, 380.0),
			"vel": rng.randf_range(0.025, 0.05) * (1.0 if rng.randf() < 0.5 else -1.0), "fase": rng.randf() * TAU, "esc": rng.randf_range(3.2, 4.6)})
		mm.set_instance_custom_data(i, Color(rng.randf() * TAU, 2.2, 0.35, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/passaro.gdshader")
	var cores := [Color(0.28, 0.18, 0.12), Color(0.45, 0.32, 0.22), Color(0.36, 0.2, 0.12), Color(0.55, 0.12, 0.06), Color(0.75, 0.62, 0.42)]
	for k in 5:
		mat.set_shader_parameter(["cor_corpo", "cor_peito", "cor_asa", "cor_ponta", "cor_bico"][k], cores[k])
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 1200, 10000))
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_ptero = {"mm": mm, "aves": aves}


func preparar_etapa(_indice: int) -> void:
	pass


var _quadro := 0
func _process(delta: float) -> void:
	_t += delta
	_quadro += 1
	var cam := get_viewport().get_camera_3d()
	var pc := cam.global_position if cam else Vector3.ZERO
	for b: Dictionary in _bichos:
		var d: Dictionary = b.d
		# Velocidade constante no chão: na elipse, o ângulo anda mais devagar onde a curva é mais larga
		var ang: float = b.ang
		ang += delta * float(b.vel) / maxf(Vector2(sin(ang) * float(b.ra), cos(ang) * float(b.rb)).length(), 1.0) * float(b.sentido)
		b.ang = ang
		var c: Vector2 = b.centro
		var q := Vector2(cos(ang) * float(b.ra), sin(ang) * float(b.rb)).rotated(float(b.giro))
		var dq := Vector2(-sin(ang) * float(b.ra), cos(ang) * float(b.rb)).rotated(float(b.giro)) * float(b.sentido)
		var dir := Vector3(dq.x, 0.0, dq.y).normalized()
		var lado := dir.cross(Vector3.UP)
		var p := Vector3(c.x + q.x, 0.0, c.y + q.y) + lado * float(b.lado)
		var raiz: Node3D = d.raiz
		var longe := p.distance_to(Vector3(pc.x, p.y, pc.z)) > 1700.0
		raiz.visible = not longe
		if longe:
			continue
		# O corpo acompanha a ladeira: chão medido na frente e atrás (antes era só no meio e, no morro,
		# as patas de uma ponta ficavam no ar e as da outra enterradas)
		var meia: float = float(d.comp) * 0.3
		var hf := _terreno.altura_em(p.x + dir.x * meia, p.z + dir.z * meia)
		var ht := _terreno.altura_em(p.x - dir.x * meia, p.z - dir.z * meia)
		p.y = (hf + ht) * 0.5 - 0.15
		var xf := Transform3D(Basis.looking_at(Vector3(dir.x * meia * 2.0, hf - ht, dir.z * meia * 2.0).normalized(), Vector3.UP), p)
		raiz.transform = xf
		# A passada (pose de dezenas de ossos) custa caro: de perto a cada quadro, de 350 a 900 m a cada 3
		# quadros (cada bicho num quadro diferente) e além disso o bicho só desliza — não dá para ver as patas
		var dist := p.distance_to(pc)
		b.dt = float(b.get("dt", 0.0)) + delta
		if dist > 900.0 or (dist > 350.0 and (_quadro + int(float(b.fase) * 100.0)) % 3 != 0):
			continue
		andar(d, xf, float(b.dt), 1.0, 0.15 + 0.15 * sin(_t * 0.7 + float(b.fase)))
		b.dt = 0.0
	if not _ptero.is_empty():
		var mm: MultiMesh = _ptero.mm
		var aves: Array = _ptero.aves
		for i in aves.size():
			var a: Dictionary = aves[i]
			var ang: float = float(a.fase) + _t * float(a.vel)
			var c3: Vector3 = a.c
			var p := c3 + Vector3(cos(ang), 0.0, sin(ang)) * float(a.r) + Vector3.UP * sin(_t * 0.2 + float(a.fase)) * 12.0
			var dir := Vector3(-sin(ang), 0.0, cos(ang)) * signf(float(a.vel))
			var b3 := Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.FORWARD, -0.25 * signf(float(a.vel)))
			mm.set_instance_transform(i, Transform3D(b3.scaled(Vector3.ONE * float(a.esc)), p))
