class_name AlvoDino
extends RefCounted
## Alvos do Extinction Day (etapas[].forma), montados pelo Alvo (forma livre, zona única):
## - ninho: ninho de dinossauro em cima de um pórtico de pedra em ruína (fixo): bacia côncava pequena de
##   palha (cabem dois carros) cercada de galhos, com ovos gigantes que quebram quando o carro cai neles;
## - sela: plataforma presa nas costas de um titanossauro que anda em círculo (trajeto "tita");
##   pescoço e cauda são obstáculos (matam);
## - jaula: a jaula de contenção (modelo da biblioteca) pendurada num guindaste, balançando como
##   pêndulo (trajeto "pendulo"); só se entra por cima, as grades seguram quem cai dentro;
## - pegada: laje de pedra em forma de pegada de três dedos num pilar de basalto; os pedaços do meteoro
##   quebram os dedos ao longo da etapa (sobra a palma). As rachaduras acendem antes de cada quebra.
## - meteoro: um pedaço grande do meteoro caído no fundo de uma cratera de impacto (Dino.crateras);
##   o pouso é na bacia côncava do topo dele, ainda em brasa (pedido do dono, etapa 4).


## Peças convexas (x, z) e contornos da forma. Devolve [pecas, contornos, raio_externo, raio_mira].
static func forma(alvo: Alvo, etapa: Dictionary) -> Array:
	var pecas: Array = []
	var contornos: Array = []
	var r_ext := 15.0
	match alvo.forma:
		"ninho":
			var r := float(etapa.get("bacia", 12.0)) * 0.5
			var circ := PackedVector2Array()
			for k in 40:
				circ.append(Vector2(cos(TAU * k / 40.0), sin(TAU * k / 40.0)) * r)
			pecas.append(circ)
			contornos.append(circ)
			r_ext = r
		"sela":
			var l := float(etapa.get("comprimento", 20.0)) * 0.5
			var w := float(etapa.get("largura", 15.0)) * 0.5
			var ret := PackedVector2Array()
			for k in 24:
				var a := TAU * k / 24.0
				# retângulo de cantos bem arredondados (superelipse)
				var c := cos(a)
				var s := sin(a)
				ret.append(Vector2(signf(c) * pow(absf(c), 0.45) * w, signf(s) * pow(absf(s), 0.45) * l))
			pecas.append(ret)
			contornos.append(ret)
			r_ext = maxf(l, w)
		"jaula":
			var l := float(etapa.get("comprimento", 28.0)) * 0.5
			var w := float(etapa.get("largura", 16.0)) * 0.5
			var ret := PackedVector2Array([Vector2(-w, -l), Vector2(w, -l), Vector2(w, l), Vector2(-w, l)])
			if etapa.has("raio_rede"):
				# Saco de rede do helicóptero: fundo redondo
				l = float(etapa.raio_rede)
				ret = PackedVector2Array()
				for k in 28:
					ret.append(Vector2(cos(TAU * k / 28.0), sin(TAU * k / 28.0)) * l)
			pecas.append(ret)
			contornos.append(ret)
			r_ext = l
		"pegada":
			# Palma (calcanhar) e três dedos; o do meio aponta para -z (para longe da rampa)
			var esc := float(etapa.get("escala", 1.0))
			var palma := PackedVector2Array()
			for k in 18:
				var a := TAU * k / 18.0
				palma.append(Vector2(cos(a) * 7.5, sin(a) * 6.5 + 2.0) * esc)
			pecas.append(palma)
			contornos.append(palma)
			for ang: float in [-38.0, 0.0, 38.0]:
				var dir := Vector2(0.0, -1.0).rotated(deg_to_rad(ang))
				var lado := Vector2(-dir.y, dir.x)
				var base := dir * 3.0 * esc
				var comp := (15.0 if ang == 0.0 else 12.5) * esc
				var dedo := PackedVector2Array([base - lado * 2.6 * esc, base + lado * 2.6 * esc, base + dir * comp * 0.75 + lado * 2.1 * esc,
					base + dir * comp, base + dir * comp * 0.75 - lado * 2.1 * esc])
				pecas.append(dedo)
				contornos.append(dedo)
			r_ext = 18.0 * esc
			# Giro da pegada (graus, como Basis(UP, giro)): os dedos apontam para onde o voo vai
			var g := deg_to_rad(float(etapa.get("giro_forma", 0.0)))
			for lista: Array in [pecas, contornos]:
				for k in lista.size():
					var pol: PackedVector2Array = lista[k]
					for j in pol.size():
						var v := pol[j]
						pol[j] = Vector2(v.x * cos(g) + v.y * sin(g), -v.x * sin(g) + v.y * cos(g))
					lista[k] = pol
	return [pecas, contornos, r_ext]


## Raio de mira dos bots (quanto podem errar sem cair fora): a palma, o meio da sela, etc.
static func raio_mira(f: String, etapa: Dictionary) -> float:
	match f:
		"ninho": return float(etapa.get("bacia", 12.0)) * 0.3
		"sela": return float(etapa.get("largura", 15.0)) * 0.3
		"jaula": return float(etapa.raio_rede) * 0.45 if etapa.has("raio_rede") else float(etapa.get("largura", 16.0)) * 0.28
		"pegada": return 5.0 * float(etapa.get("escala", 1.0))
		"meteoro": return float(etapa.get("bacia", 28.0)) * 0.3
	return 10.0


## Material do tampo por forma.
static func material(alvo: Alvo) -> Material:
	match alvo.forma:
		"pegada":
			var m := ShaderMaterial.new()
			m.shader = load("res://shaders/rocha_vulcao.gdshader")
			m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 331))
			m.set_shader_parameter("ruido_fino", Terreno._textura_ruido(0.08, 4, 337))
			m.set_shader_parameter("c_basalto", Color(0.5, 0.42, 0.32))
			m.set_shader_parameter("c_basalto_claro", Color(0.75, 0.66, 0.5))
			m.set_shader_parameter("brasa", 0.7)   # pegada em brasa: destaca da mesa de basalto
			m.set_shader_parameter("calor_fixo", 1.0)
			return m
		"jaula":
			if str(alvo._trajeto.get("tipo", "")) == "oito":
				return _material_rede(0.75, true)   # piso de rede de cabos de aço (helicóptero)
			var m := ComplexoLancamento._material_metal(Color(0.25, 0.24, 0.22), 0.7, 0.55)
			return m
		"sela":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.42, 0.28, 0.16)
			m.roughness = 0.8
			return m
	return StandardMaterial3D.new()


## Máquina/bicho que leva o alvo, conforme o trajeto.
static func suporte(alvo: Alvo, etapa: Dictionary) -> void:
	match str(etapa.get("trajeto", {}).get("tipo", "")):
		"tita": _tita(alvo, etapa)
		"pendulo": _guindaste(alvo, etapa)
		"oito": _helicoptero(alvo, etapa)
		_: _pilar_rocha(alvo)


# ------------------------------------------------------------------ ninho no pórtico

static func _rocha_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rocha_vulcao.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 331))
	m.set_shader_parameter("ruido_fino", Terreno._textura_ruido(0.08, 4, 337))
	return m


## Tronco redondo (cilindro de altura 1 e raio 1 na base) de p0 a p1.
static func _tronco(p0: Vector3, p1: Vector3, r: float) -> Transform3D:
	var d := p1 - p0
	var comp := maxf(d.length(), 0.01)
	var dir := d / comp
	var giro := Basis(Quaternion(Vector3.UP, dir)) if dir.y > -0.999 else Basis(Vector3.RIGHT, PI)
	return Transform3D(giro * Basis.from_scale(Vector3(r, comp, r)), (p0 + p1) * 0.5)


## Ovo de dinossauro (raio ~1, meia altura 1,5, mais largo embaixo; origem no meio). `quebrado`: só a
## metade de baixo, com a beirada em dentes e a face de dentro também.
static func _malha_ovo(quebrado: bool) -> ArrayMesh:
	const ANEIS := 14
	const SEGS := 20
	var ultimo := 6 if quebrado else ANEIS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pt := func(i: int, k: int) -> Vector3:
		var fi := PI * i / ANEIS   # 0 = base
		if quebrado and i == ultimo:
			fi += 0.3 if (k % SEGS) % 2 == 0 else -0.16
		var te := TAU * k / SEGS
		var r := sin(fi) * (1.0 + 0.2 * cos(fi))
		return Vector3(cos(te) * r, -1.5 * cos(fi), sin(te) * r)
	for i in ultimo:
		for k in SEGS:
			var q: Array = [pt.call(i, k), pt.call(i, k + 1), pt.call(i + 1, k + 1), pt.call(i + 1, k)]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				var p: Vector3 = q[idx]
				st.set_normal(Vector3(p.x, p.y / 2.25, p.z).normalized())
				st.add_vertex(p)
			if quebrado:
				for idx: int in [0, 2, 1, 0, 3, 2]:
					var p: Vector3 = q[idx]
					st.set_normal(-Vector3(p.x, p.y / 2.25, p.z).normalized())
					st.add_vertex(p * 0.97)
	return st.commit()


## Ninho de dinossauro (etapas[].forma = "ninho"; pedido do dono para a etapa 2, pela arte de referência
## "alvo xxx" — tudo em geometria, nada de imagem): pórtico de pedra em ruína (o mesmo das pedras que
## caem: pilares de blocos, lintel com cintas de ferro, forro de pranchas, tochas e cipós) e, em cima do
## lintel, o ninho: bacia côncava de palha de `bacia` m de diâmetro e `fundo` m de profundidade (pequena:
## cabem dois carros) — só ela é o alvo —, cercada por um rolo de palha com galhos tortos trançados,
## samambaias e folhas, e com ovos gigantes dentro, que quebram quando um carro cai neles (casca de baixo
## fica, cacos voam, a gema escorre). A origem do alvo fica no nível da borda da bacia.
static func montar_ninho(alvo: Alvo, etapa: Dictionary) -> void:
	var rb := float(etapa.get("bacia", 12.0)) * 0.5
	var fundo := float(etapa.get("fundo", 1.6))
	const LABIO := 3.0
	const CRISTA := 1.3
	const SOBRE_LINTEL := 5.85   # do alto do vão do pórtico até o topo da capa do lintel
	var y_base := -fundo - 0.6   # fundo do ninho = topo do lintel
	alvo.raio_externo = rb
	var base := alvo.centro_base
	var fixo := alvo._no_fixo()
	# Pórtico: do chão até o ninho, virado para quem chega voando
	var chao := alvo._chao_em(base.x, base.z) - 0.3
	var alto := clampf(base.y + y_base - SOBRE_LINTEL - chao, 9.0, 60.0)
	var b := Basis(Vector3.UP, deg_to_rad(float(etapa.get("giro_forma", 0.0))))
	var pe := Vector3(base.x, base.y + y_base - SOBRE_LINTEL - alto, base.z)
	var est := alvo._corpo_estrutura(fixo)
	ComplexoLancamento.adicionar_colisoes(est, ArmadilhasDino.portico_ruina(fixo, pe, b, rb - 1.0, alto, (rb + LABIO) * 2.0 - 2.0, 77, alvo.terreno))
	var no := Node3D.new()
	no.name = "Ninho"
	no.position = base
	fixo.add_child(no)
	# Bacia (alvo) e rolo de palha em volta (estrutura): uma superfície de revolução só, irregular por fora
	var ruido := FastNoiseLite.new()
	ruido.seed = 515
	ruido.frequency = 0.9
	const ANEIS_B := 10
	const ANEIS_L := 9
	const SEGS := 56
	var verts := PackedVector3Array()
	for i in ANEIS_B + ANEIS_L + 1:
		for k in SEGS:
			var te := TAU * k / SEGS
			var n := ruido.get_noise_2d(cos(te) * 2.0, sin(te) * 2.0)
			var r := rb * i / ANEIS_B
			var y := -fundo * (1.0 - (r / rb) * (r / rb))
			if i > ANEIS_B:
				var t := float(i - ANEIS_B) / ANEIS_L
				r = rb + LABIO * t * (1.0 + 0.14 * n)
				y = lerpf(0.0, y_base, smoothstep(0.45, 1.0, t)) + CRISTA * (0.85 + 0.4 * n) * sin(PI * minf(t * 1.25, 1.0))
			verts.append(Vector3(cos(te) * r, y, sin(te) * r))
	var st_bacia := SurfaceTool.new()
	st_bacia.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_bacia.set_smooth_group(0)
	var st_rolo := SurfaceTool.new()
	st_rolo.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_rolo.set_smooth_group(0)
	var faces_bacia := PackedVector3Array()
	var faces_rolo := PackedVector3Array()
	for i in ANEIS_B + ANEIS_L:
		for k in SEGS:
			var a := i * SEGS + k
			var bb := i * SEGS + (k + 1) % SEGS
			for v: int in [a, bb + SEGS, bb, a, a + SEGS, bb + SEGS]:
				if i < ANEIS_B:
					st_bacia.add_vertex(verts[v])
					faces_bacia.append(verts[v])
				else:
					st_rolo.add_vertex(verts[v])
					faces_rolo.append(verts[v])
	var palha := ShaderMaterial.new()
	palha.shader = load("res://shaders/alvo_ninho.gdshader")
	palha.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 3, 17))
	palha.set_shader_parameter("raio", rb + LABIO)
	palha.set_shader_parameter("luzes", 0.0)
	for par: Array in [[st_bacia, alvo.disco], [st_rolo, no]]:
		var st: SurfaceTool = par[0]
		st.index()
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = palha
		(par[1] as Node3D).add_child(mi)
	var forma_b := ConcavePolygonShape3D.new()
	forma_b.backface_collision = true
	forma_b.set_faces(faces_bacia)
	var cs := CollisionShape3D.new()
	cs.shape = forma_b
	alvo.add_child(cs)
	var forma_r := ConcavePolygonShape3D.new()
	forma_r.backface_collision = true
	forma_r.set_faces(faces_rolo)
	var cs_r := CollisionShape3D.new()
	cs_r.shape = forma_r
	alvo._corpo_estrutura(no).add_child(cs_r)
	# Galhos: troncos tortos deitados em volta do rolo, trançados uns nos outros, com as pontas para fora
	var rng := RandomNumberGenerator.new()
	rng.seed = 2207
	var casca := StandardMaterial3D.new()
	casca.albedo_color = Color(0.4, 0.31, 0.23)
	casca.albedo_texture = Terreno._textura_ruido(0.05, 4, 93)
	casca.uv1_triplanar = true
	casca.uv1_scale = Vector3(0.9, 0.25, 0.9)
	casca.roughness = 0.95
	var tronco := CylinderMesh.new()
	tronco.top_radius = 0.8
	tronco.bottom_radius = 1.0
	tronco.height = 1.0
	tronco.radial_segments = 7
	tronco.rings = 1
	var galhos: Array = []
	for g in 54:
		var ang := TAU * g / 54.0 + rng.randf_range(-0.08, 0.08)
		var sentido := 1.0 if rng.randf() < 0.7 else -1.0
		var rr := rb + rng.randf_range(0.5, 2.6)
		var y := CRISTA * rng.randf_range(0.15, 1.0) * (1.0 - 0.5 * (rr - rb - 1.2) / 1.4)
		var grosso := rng.randf_range(0.2, 0.42)
		# começa espetado para fora e para baixo, dá a volta no ninho e termina espetado para fora e para cima
		var p0 := Vector3(cos(ang), 0.0, sin(ang)) * (rr + rng.randf_range(1.2, 2.4)) + Vector3.UP * (y - rng.randf_range(0.3, 1.2))
		var lances := rng.randi_range(4, 6)
		for l in lances:
			var p1 := Vector3(cos(ang), 0.0, sin(ang)) * rr + Vector3.UP * y
			if l == lances - 1:
				p1 = Vector3(cos(ang), 0.0, sin(ang)) * (rr + rng.randf_range(1.0, 2.6)) + Vector3.UP * (y + rng.randf_range(0.4, 1.9))
				if rng.randf() < 0.5:
					# forquilha na ponta
					var lado_f := Vector3(-sin(ang), 0.0, cos(ang)) * rng.randf_range(-0.9, 0.9)
					galhos.append(_tronco(p0.lerp(p1, 0.5), p1 + lado_f + Vector3.UP * rng.randf_range(0.2, 0.9), grosso * 0.55))
			galhos.append(_tronco(p0, p1, grosso))
			p0 = p1
			grosso *= 0.86
			ang += sentido * rng.randf_range(0.14, 0.26)
			rr = clampf(rr + rng.randf_range(-0.5, 0.5), rb + 0.4, rb + LABIO - 0.2)
			y = clampf(y + rng.randf_range(-0.35, 0.35), 0.1, CRISTA * 1.15)
	Gelo._instancias(no, tronco, galhos, casca)
	# Samambaias e folhas presas no rolo e escorrendo para fora (por cima do lintel)
	var verde := StandardMaterial3D.new()
	verde.albedo_color = Color(0.11, 0.26, 0.07)
	verde.roughness = 0.8
	verde.backlight_enabled = true
	verde.backlight = Color(0.12, 0.2, 0.05)
	var folhas: Array[Transform3D] = []
	for q in 18:
		var ang := rng.randf() * TAU
		var c := Vector3(cos(ang), 0.0, sin(ang)) * (rb + rng.randf_range(1.4, 2.8)) + Vector3.UP * rng.randf_range(0.0, 0.8)
		for fr in 7:
			var dir_f := Basis(Vector3.UP, ang + rng.randf_range(-1.3, 1.3)) * Basis(Vector3.FORWARD, rng.randf_range(-0.1, 0.7))
			var comp_f := rng.randf_range(1.2, 2.2)
			folhas.append(Transform3D(dir_f * Basis.from_scale(Vector3(comp_f, 0.03, rng.randf_range(0.3, 0.5))), c + dir_f.x * comp_f * 0.5))
	for q in 90:
		var ang := rng.randf() * TAU
		var giro := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.9, 0.9))
		folhas.append(Transform3D(giro * Basis.from_scale(Vector3(rng.randf_range(0.35, 0.7), 0.03, rng.randf_range(0.25, 0.45))),
			Vector3(cos(ang), 0.0, sin(ang)) * (rb + rng.randf_range(1.0, 3.1)) + Vector3.UP * rng.randf_range(y_base + 0.3, CRISTA * 0.9)))
	ComplexoLancamento.criar_multimesh(no, folhas, verde, false)
	# Ovos: um grande no meio e quatro em volta, deitados na palha
	var ovo_m := ShaderMaterial.new()
	ovo_m.shader = load("res://shaders/alvo_ninho.gdshader")
	ovo_m.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 3, 17))
	ovo_m.set_shader_parameter("modo_ovo", 1)
	ovo_m.set_shader_parameter("luzes", 0.0)   # pintas bem marcadas
	var inteiro := _malha_ovo(false)
	var casca_q := _malha_ovo(true)
	var ovos: Array = []
	for k in 5:
		var ang := TAU * (k - 1) / 4.0 + 0.5
		var d := 0.0 if k == 0 else rb * 0.45
		var s := 1.15 if k == 0 else rng.randf_range(0.82, 1.0)
		var tomba := Basis(Vector3(-sin(ang), 0.0, cos(ang)), -rng.randf_range(0.15, 0.4)) if k > 0 else Basis(Vector3.RIGHT, 0.08)
		var chao_o := -fundo * (1.0 - (d / rb) * (d / rb))
		var centro := Vector3(cos(ang) * d, chao_o + 1.5 * s - 0.3, sin(ang) * d)
		var xf := Transform3D(tomba * Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * s), centro)
		var mi := MeshInstance3D.new()
		mi.mesh = inteiro
		mi.material_override = ovo_m
		mi.transform = xf
		alvo.disco.add_child(mi)
		var mq := MeshInstance3D.new()
		mq.mesh = casca_q
		mq.material_override = ovo_m
		mq.transform = xf
		mq.visible = false
		alvo.disco.add_child(mq)
		ovos.append({"inteiro": true, "mi": mi, "casca": mq, "centro": centro, "chao": chao_o, "s": s, "cacos": [], "t": 0.0})
	alvo.dino_estado["ovos"] = ovos
	alvo.dino_estado["ovo_mat"] = ovo_m
	# Luz quente em cima do ninho (etapa à noite: acha-se o ninho pelo clarão e pelas tochas do pórtico)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.7, 0.4)
	luz.light_energy = 3.5
	luz.omni_range = rb * 3.5
	luz.shadow_enabled = false
	luz.position = Vector3(0.0, 6.0, 0.0)
	alvo.disco.add_child(luz)


## Ovos do ninho: quebram quando um carro encosta (o inteiro some, fica a casca de baixo, os cacos voam e
## caem na palha e a gema escorre).
static func atualizar_ovos(alvo: Alvo, delta: float) -> void:
	var rb := alvo.bacia_raio
	# Conferência por foto: TSC_OVO_TESTE=1 quebra dois ovos aos 3 s, sem carro
	if OS.get_environment("TSC_OVO_TESTE") != "":
		alvo.dino_estado["t_teste"] = float(alvo.dino_estado.get("t_teste", 0.0)) + delta
		if float(alvo.dino_estado.t_teste) > 3.0:
			for k: int in [1, 3]:
				if alvo.dino_estado.ovos[k].inteiro:
					_quebrar_ovo(alvo, alvo.dino_estado.ovos[k], Vector3(4, 0, 0))
	for o: Dictionary in alvo.dino_estado.ovos:
		if o.inteiro:
			var c: Vector3 = alvo.disco.global_transform * (o.centro as Vector3)
			var s: float = o.s
			for no_v in alvo.get_tree().get_nodes_in_group("veiculo"):
				var v := no_v as RigidBody3D
				if v == null:
					continue
				var p := v.global_position
				if Vector2(p.x - c.x, p.z - c.z).length() < s + 2.1 and absf(p.y + 0.7 - c.y) < 1.5 * s + 1.3:
					_quebrar_ovo(alvo, o, v.linear_velocity)
					break
			continue
		o.t = float(o.t) + delta
		if o.has("gema"):
			var cresce := 1.0 - pow(1.0 - clampf(float(o.t) / 1.4, 0.0, 1.0), 3.0)
			(o.gema as MeshInstance3D).scale = Vector3(cresce, 1.0, cresce)
		for caco: Dictionary in o.cacos:
			if caco.parado:
				continue
			var mi: MeshInstance3D = caco.mi
			caco.v = (caco.v as Vector3) + Vector3.DOWN * 22.0 * delta
			var p := mi.position + (caco.v as Vector3) * delta
			var d := Vector2(p.x, p.z).length()
			if d > rb - 0.5:
				# bate no rolo de palha e volta para dentro
				p.x *= (rb - 0.5) / d
				p.z *= (rb - 0.5) / d
				caco.v = Vector3(-(caco.v as Vector3).x * 0.3, (caco.v as Vector3).y, -(caco.v as Vector3).z * 0.3)
				d = rb - 0.5
			var piso := -alvo.bacia_fundo * (1.0 - (d / rb) * (d / rb)) + 0.1
			if p.y <= piso and (caco.v as Vector3).y < 0.0:
				p.y = piso
				caco.parado = true
				mi.basis = Basis(Vector3.UP, float(caco.giro)) * Basis.from_scale(mi.basis.get_scale())
			else:
				mi.rotate_object_local(caco.eixo, float(caco.giro) * delta)
			mi.position = p


static func _quebrar_ovo(alvo: Alvo, o: Dictionary, vel: Vector3) -> void:
	o.inteiro = false
	o.t = 0.0
	(o.mi as MeshInstance3D).visible = false
	(o.casca as MeshInstance3D).visible = true
	var s: float = o.s
	var centro: Vector3 = o.centro
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centro.x * 31.0 + centro.z * 17.0) + 5
	# Cacos da casca: lascas abauladas que voam para os lados (e um pouco para onde o carro ia)
	var lasca := SphereMesh.new()
	lasca.radius = 0.5
	lasca.height = 0.22
	lasca.is_hemisphere = true
	lasca.radial_segments = 5
	lasca.rings = 2
	var empurra := Vector3(vel.x, 0.0, vel.z).limit_length(6.0) * 0.5
	for k in 12:
		var ang := TAU * k / 12.0 + rng.randf_range(-0.2, 0.2)
		var mi := MeshInstance3D.new()
		mi.mesh = lasca
		mi.material_override = alvo.dino_estado.ovo_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = centro + Vector3(cos(ang) * 0.6, rng.randf_range(0.0, 1.2), sin(ang) * 0.6) * s
		mi.basis = Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf() * TAU) * Basis.from_scale(Vector3(rng.randf_range(0.5, 1.5), 1.0, rng.randf_range(0.5, 1.5)) * s)
		alvo.disco.add_child(mi)
		(o.cacos as Array).append({"mi": mi, "parado": false, "giro": rng.randf_range(4.0, 11.0),
			"eixo": Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
			"v": Vector3(cos(ang), 0.0, sin(ang)) * rng.randf_range(2.5, 6.5) + Vector3.UP * rng.randf_range(4.0, 9.0) + empurra})
	# Gema: poça de contorno irregular que acompanha a curva da bacia e cresce em 1,4 s
	var rb := alvo.bacia_raio
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var borda := PackedVector3Array()
	for k in 20:
		var ang := TAU * k / 20.0
		var r := (1.9 + 0.5 * sin(ang * 3.0 + centro.x) + rng.randf_range(-0.25, 0.25)) * s
		var q := Vector2(centro.x + cos(ang) * r, centro.z + sin(ang) * r).limit_length(rb - 0.3)
		borda.append(Vector3(q.x - centro.x, -alvo.bacia_fundo * (1.0 - q.length_squared() / (rb * rb)) + 0.05 - float(o.chao), q.y - centro.z))
	for k in 20:
		for p: Vector3 in [Vector3(0.0, 0.06, 0.0), borda[(k + 1) % 20], borda[k]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	var gema_m := StandardMaterial3D.new()
	gema_m.albedo_color = Color(0.9, 0.62, 0.08)
	gema_m.roughness = 0.3
	gema_m.emission_enabled = true   # (à noite a poça lisa só refletia o céu escuro)
	gema_m.emission = Color(0.9, 0.55, 0.05)
	gema_m.emission_energy_multiplier = 0.35
	gema_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var gema := MeshInstance3D.new()
	gema.mesh = st.commit()
	gema.material_override = gema_m
	gema.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gema.position = Vector3(centro.x, float(o.chao), centro.z)
	gema.scale = Vector3(0.05, 1.0, 0.05)
	alvo.disco.add_child(gema)
	o.gema = gema


# ------------------------------------------------------------------ sela no titanossauro

static func _tita(alvo: Alvo, etapa: Dictionary) -> void:
	var comp := float(etapa.get("comprimento_tita", 40.0))
	var d := DinosParque.criar("titanossauro", comp)
	var alt: float = float(d.get("altura", 15.0))
	# O tampo fica no dorso: o bicho fica embaixo dele (frente = -Z local, o sentido do passo)
	var raiz: Node3D = d.raiz
	# O alvo gira com o trajeto de modo que +Z local é o sentido do passo: o bicho olha para +Z
	raiz.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0, -alt * 0.62, -comp * 0.04))
	alvo.add_child(raiz)
	alvo.dino_estado["tita"] = d
	if OS.get_environment("TSC_DINO_LOG") != "":
		print("[DINO] tita alt=%.1f comp=%.1f raiz=%s giro=%s filhos=%d" % [alt, comp, str(raiz.position), str((d.giro as Node3D).transform) if d.has("giro") else "-", raiz.get_child_count()])
	alvo.dino_estado["tita_passo"] = 0.0
	# Arreio: cintas de couro por baixo da barriga e a armação de madeira da sela
	var couro := StandardMaterial3D.new()
	couro.albedo_color = Color(0.26, 0.15, 0.08)
	couro.roughness = 0.7
	var cintas: Array[Transform3D] = []
	for z: float in [-5.0, 0.0, 5.0]:
		for s: float in [-1.0, 1.0]:
			cintas.append(ComplexoLancamento._viga(Vector3(s * 7.4, -Alvo.ESPESSURA, z), Vector3(s * 3.2, -alt * 0.45, z), 0.35))
		cintas.append(ComplexoLancamento._viga(Vector3(-3.4, -alt * 0.47, z), Vector3(3.4, -alt * 0.47, z), 0.35))
	ComplexoLancamento.criar_multimesh(alvo, cintas, couro)
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.3, 0.2, 0.12)
	var armacao: Array[Transform3D] = []
	for z: float in [-8.0, -2.7, 2.7, 8.0]:
		armacao.append(Transform3D(Basis.from_scale(Vector3(14.0, 1.2, 0.8)), Vector3(0, -Alvo.ESPESSURA - 0.6, z)))
	ComplexoLancamento.criar_multimesh(alvo, armacao, madeira)
	# Pescoço e cauda matam (quem pousa torto bate neles); o tampo é o dorso
	var mortal := StaticBody3D.new()
	mortal.collision_layer = 1
	mortal.collision_mask = 0
	mortal.add_to_group("estrutura")
	mortal.add_to_group("mortal")
	alvo.add_child(mortal)
	ComplexoLancamento.adicionar_colisoes(mortal, [
		ComplexoLancamento._viga(Vector3(0, -2.0, comp * 0.22), Vector3(0, alt * 0.35, comp * 0.46), 2.6),
		ComplexoLancamento._viga(Vector3(0, -3.0, -comp * 0.22), Vector3(0, -alt * 0.3, -comp * 0.55), 2.2)])
	# Tochas nos quatro cantos da sela (iluminam o bicho à noite; pedido do dono: tochas no lugar do neon)
	var cx := float(etapa.get("largura", 15.0)) * 0.5 + 0.6
	var cz := float(etapa.get("comprimento", 20.0)) * 0.5 + 0.6
	var hastes: Array[Transform3D] = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			hastes.append(Transform3D(Basis.from_scale(Vector3(0.25, 3.0, 0.25)), Vector3(sx * cx, 0.6, sz * cz)))
			var chama := Dino._chama(Vector3(sx * cx, 2.3, sz * cz), 0.9)
			for luz in chama.find_children("*", "OmniLight3D", true, false):
				(luz as OmniLight3D).omni_range = 34.0
				(luz as OmniLight3D).light_energy = 3.0
			alvo.add_child(chama)
	ComplexoLancamento.criar_multimesh(alvo, hastes, madeira)


# ------------------------------------------------------------------ jaula no guindaste

static func _guindaste(alvo: Alvo, etapa: Dictionary) -> void:
	var tj := alvo._trajeto
	var raio := float(tj.get("raio", 70.0))
	var dir := alvo.direcao_mov
	var lado := dir.cross(Vector3.UP).normalized()
	var piv := alvo.centro_base + Vector3.UP * raio
	var fixo := alvo._no_fixo()
	# Torre de treliça ao lado e a lança até em cima do pivô, com contrapeso
	var torre_p := Vector3(piv.x, 0.0, piv.z) + lado * 46.0
	var chao := alvo._chao_em(torre_p.x, torre_p.z) - 1.0
	var aco: Array[Transform3D] = []
	aco.append_array(ComplexoLancamento.trelica(Vector3(torre_p.x, chao, torre_p.z), Vector3(torre_p.x, piv.y + 6.0, torre_p.z), 6.0, 5.0, 0.5, 0.2))
	aco.append_array(ComplexoLancamento.trelica(Vector3(torre_p.x, piv.y + 6.0, torre_p.z) - lado * 2.0, piv + Vector3.UP * 6.0 - lado * 2.0, 4.0, 4.0, 0.4, 0.16))
	aco.append_array(ComplexoLancamento.trelica(Vector3(torre_p.x, piv.y + 6.0, torre_p.z) + lado * 2.0, Vector3(torre_p.x, piv.y + 6.0, torre_p.z) + lado * 24.0, 4.0, 4.0, 0.4, 0.16))
	ComplexoLancamento.criar_multimesh(fixo, aco, Gelo.material(Gelo.Mat.VERMELHO))
	ComplexoLancamento.criar_multimesh(fixo, [Transform3D(Basis.from_scale(Vector3(8.0, 7.0, 8.0)), Vector3(torre_p.x, piv.y + 3.0, torre_p.z) + lado * 24.0)], Gelo.material(Gelo.Mat.CONCRETO))
	var est := alvo._corpo_estrutura(fixo)
	ComplexoLancamento.adicionar_colisoes(est, [Transform3D(Basis.from_scale(Vector3(6.0, piv.y + 6.0 - chao, 6.0)), Vector3(torre_p.x, (piv.y + 6.0 + chao) * 0.5, torre_p.z))])
	Gelo.painel_logo(fixo, Vector3(torre_p.x, piv.y - 14.0, torre_p.z) - lado * 3.4, Basis.looking_at(lado, Vector3.UP), 3.4, true)
	# Jaula (modelo), presa no tampo: grades de 8 m em volta (seguram quem cai dentro)
	var l := float(etapa.get("comprimento", 28.0)) * 0.5
	var w := float(etapa.get("largura", 16.0)) * 0.5
	var alto := float(etapa.get("altura_grade", 8.0))
	if ResourceLoader.exists("res://assets/dino/jaula/jaula.glb"):
		var jaula: Node3D = (load("res://assets/dino/jaula/jaula.glb") as PackedScene).instantiate()
		alvo.add_child(jaula)
		# Ajusta o modelo à caixa da jaula (o comprimento dele é o eixo maior)
		var caixa := AABB()
		var primeira := true
		for mi in jaula.find_children("*", "MeshInstance3D", true, false):
			var xf := DinosParque._xf_ate(mi as MeshInstance3D, jaula)
			var c := xf * (mi as MeshInstance3D).get_aabb()
			caixa = c if primeira else caixa.merge(c)
			primeira = false
		var gira := caixa.size.x > caixa.size.z
		var sx := (w * 2.0) / (caixa.size.z if gira else caixa.size.x)
		var sz := (l * 2.0) / (caixa.size.x if gira else caixa.size.z)
		var sy := alto / maxf(caixa.size.y, 0.01)
		var b := Basis(Vector3.UP, PI * 0.5 if gira else 0.0) * Basis.from_scale(Vector3(sz if gira else sx, sy, sx if gira else sz))
		jaula.transform = Transform3D(b, -(b * Vector3(caixa.get_center().x, caixa.position.y, caixa.get_center().z)) + Vector3.DOWN * Alvo.ESPESSURA * 0.5)
	var grades := alvo._corpo_estrutura(alvo)
	var paredes: Array[Transform3D] = [
		Transform3D(Basis.from_scale(Vector3(w * 2.0, alto, 0.6)), Vector3(0, alto * 0.5, -l)),
		Transform3D(Basis.from_scale(Vector3(w * 2.0, alto, 0.6)), Vector3(0, alto * 0.5, l)),
		Transform3D(Basis.from_scale(Vector3(0.6, alto, l * 2.0)), Vector3(-w, alto * 0.5, 0)),
		Transform3D(Basis.from_scale(Vector3(0.6, alto, l * 2.0)), Vector3(w, alto * 0.5, 0))]
	ComplexoLancamento.adicionar_colisoes(grades, paredes)
	# Cabo principal (do gancho ao pivô, em coordenadas da jaula: sempre "para cima") e as quatro lingas
	var cabos: Array[Transform3D] = []
	var gancho := Vector3(0, alto + 14.0, 0)
	cabos.append(ComplexoLancamento._viga(gancho, Vector3(0, raio + 4.0, 0), 0.35))
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			cabos.append(ComplexoLancamento._viga(Vector3(sx2 * w, alto, sz2 * l), gancho, 0.2))
	ComplexoLancamento.criar_multimesh(alvo, cabos, Gelo.material(Gelo.Mat.ACO))
	var bloco := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 3.2, 2.4)
	bloco.mesh = bm
	bloco.material_override = Gelo.material(Gelo.Mat.VERMELHO)
	bloco.position = gancho
	alvo.add_child(bloco)
	alvo.dino_estado["pendulo"] = {"piv": piv, "raio": raio, "eixo": lado}


# ------------------------------------------------------------------ saco de rede no helicóptero

static func _material_rede(malha: float, piso: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/rede_aco.gdshader")
	m.set_shader_parameter("malha", malha)
	m.set_shader_parameter("pelo_piso", piso)
	return m


## Raio do saco de rede na altura y (0 = fundo): barriga no meio, mais fechado na boca.
static func _raio_rede(raio: float, alto: float, y: float) -> float:
	return raio * (1.0 + 0.24 * sin(PI * 0.85 * clampf(y / alto, 0.0, 1.0)))


## Etapa 3 (pedido do dono, no lugar da jaula do guindaste): um helicóptero de carga sobrevoa a área
## (trajeto "oito") levando no gancho um saco de rede — fundo redondo de rede, a barriga de rede até a
## boca e, dali para cima, só os cabos convergindo para o gancho. Entra-se pelos vãos entre os cabos
## (ou por cima da boca); quem cai dentro não sai (a barriga tem colisão). Bater no helicóptero ou no
## rotor explode o carro. O helicóptero vira para onde voa; o holofote aponta para a rede.
static func _helicoptero(alvo: Alvo, etapa: Dictionary) -> void:
	var raio := float(etapa.get("raio_rede", 11.0))
	var alto := float(etapa.get("altura_grade", 9.0))
	var altura_heli := float(etapa.get("altura_helicoptero", 44.0))
	var corda := StandardMaterial3D.new()
	corda.albedo_color = Color(0.62, 0.6, 0.52)
	corda.roughness = 0.7
	corda.emission_enabled = true
	corda.emission = Color(0.62, 0.6, 0.52)
	corda.emission_energy_multiplier = 0.25
	# Barriga de rede (superfície de revolução; UV em metros para a malha não esticar)
	const GOMOS := 36
	const ANEIS := 9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in ANEIS:
		var y0 := alto * j / ANEIS
		var y1 := alto * (j + 1) / ANEIS
		var r0 := _raio_rede(raio, alto, y0)
		var r1 := _raio_rede(raio, alto, y1)
		for k in GOMOS:
			var a0 := TAU * k / GOMOS
			var a1 := TAU * (k + 1) / GOMOS
			var v := [Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
				Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a0) * r1, y1, sin(a0) * r1)]
			var uv := [Vector2(a0 * raio * 1.15, y0), Vector2(a1 * raio * 1.15, y0), Vector2(a1 * raio * 1.15, y1), Vector2(a0 * raio * 1.15, y1)]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(v[idx].x, 0.0, v[idx].z).normalized())
				st.set_uv(uv[idx])
				st.add_vertex(v[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _material_rede(1.25, false)
	alvo.add_child(mi)
	# Colisão da barriga: 18 painéis em volta
	var grades := alvo._corpo_estrutura(alvo)
	var paineis: Array[Transform3D] = []
	var r_col := _raio_rede(raio, alto, alto * 0.5)
	for k in 18:
		var a := TAU * (k + 0.5) / 18.0
		var fora := Vector3(cos(a), 0.0, sin(a))
		paineis.append(Transform3D(Basis.looking_at(fora, Vector3.UP) * Basis.from_scale(Vector3(TAU * r_col / 18.0 * 1.1, alto, 0.6)), fora * r_col + Vector3.UP * alto * 0.5))
	ComplexoLancamento.adicionar_colisoes(grades, paineis)
	# ... e a própria rede, na forma dela (pedido do dono: quem acerta não pode cair de dentro). Os painéis ficam
	# na barriga, a 13,6 m; o fundo tem 11 m de raio — entre um e outro a rede desce inclinada e ali não havia
	# nada: o carro escorregava pelo vão em volta do fundo e caía
	var forma_rede := (mi.mesh as ArrayMesh).create_trimesh_shape()
	forma_rede.backface_collision = true
	var cs_rede := CollisionShape3D.new()
	cs_rede.shape = forma_rede
	grades.add_child(cs_rede)
	# Corda grossa na boca e no fundo, e os cabos da boca até o gancho do helicóptero
	var cordas: Array[Transform3D] = []
	var r_boca := _raio_rede(raio, alto, alto)
	for k in GOMOS:
		var a0 := TAU * k / GOMOS
		var a1 := TAU * (k + 1) / GOMOS
		cordas.append(ComplexoLancamento._viga(Vector3(cos(a0) * r_boca, alto, sin(a0) * r_boca), Vector3(cos(a1) * r_boca, alto, sin(a1) * r_boca), 0.4))
		cordas.append(ComplexoLancamento._viga(Vector3(cos(a0) * raio, 0.0, sin(a0) * raio), Vector3(cos(a1) * raio, 0.0, sin(a1) * raio), 0.3))
	var gancho := Vector3(0, altura_heli - 3.6, 0)
	var cabos_col: Array[Transform3D] = []
	for k in 10:
		var a := TAU * k / 10.0
		var p := Vector3(cos(a) * r_boca, alto, sin(a) * r_boca)
		# cabo com uma leve barriga (dois trechos)
		var meio := p.lerp(gancho, 0.45) + Vector3(cos(a), 0.0, sin(a)) * 1.6
		cordas.append(ComplexoLancamento._viga(p, meio, 0.2))
		cordas.append(ComplexoLancamento._viga(meio, gancho, 0.2))
		# Os cabos têm colisão (pedido do dono): quem bate neles não entra — só passa quem acerta o vão entre dois
		# (7,7 m na boca, fechando para cima até o gancho)
		cabos_col.append(ComplexoLancamento._viga(p, meio, 0.55))
		cabos_col.append(ComplexoLancamento._viga(meio, gancho, 0.55))
	ComplexoLancamento.adicionar_colisoes(grades, cabos_col)
	ComplexoLancamento.criar_multimesh(alvo, cordas, corda)
	# Helicóptero (não gira com a rede: vira para onde voa — ver atualizar_heli)
	var heli := Node3D.new()
	heli.name = "Helicoptero"
	heli.position = Vector3(0, altura_heli, 0)
	alvo.add_child(heli)
	# O helicóptero é o CH-47 Chinook que o dono pôs na pasta (pedido dele, 2026-10-04); sem o arquivo, o de caixas
	var raio_rotor := _chinook(heli)
	var com_modelo := raio_rotor > 0.0
	if com_modelo:
		# Gancho de carga embaixo da barriga, onde os cabos da rede prendem
		ComplexoLancamento.criar_multimesh(heli, [Transform3D(Basis.from_scale(Vector3(1.4, 1.2, 1.4)), Vector3(0, -3.0, 0))] as Array[Transform3D], ComplexoLancamento._material_metal(Color(0.03, 0.03, 0.035), 0.3, 0.3))
	if not com_modelo:
		var casco := ComplexoLancamento._material_metal(Color(0.3, 0.42, 0.28), 0.3, 0.5)   # verde militar
		var escuro := ComplexoLancamento._material_metal(Color(0.03, 0.03, 0.035), 0.3, 0.3)
		var corpo := MeshInstance3D.new()
		var esf := SphereMesh.new()
		esf.radius = 1.0
		esf.height = 2.0
		corpo.mesh = esf
		corpo.material_override = casco
		corpo.scale = Vector3(2.6, 2.5, 7.0)
		heli.add_child(corpo)
		var vidro := MeshInstance3D.new()
		vidro.mesh = esf
		vidro.material_override = escuro
		vidro.scale = Vector3(2.3, 1.7, 2.6)
		vidro.position = Vector3(0, 0.5, -4.6)
		heli.add_child(vidro)
		var pecas: Array[Transform3D] = []
		pecas.append(ComplexoLancamento._viga(Vector3(0, 1.0, 4.5), Vector3(0, 2.2, 15.0), 1.1))          # cauda
		pecas.append(Transform3D(Basis.from_scale(Vector3(0.3, 4.2, 2.0)), Vector3(0, 3.6, 15.2)))        # deriva
		pecas.append(Transform3D(Basis.from_scale(Vector3(4.6, 0.25, 1.4)), Vector3(0, 2.0, 13.0)))       # estabilizador
		pecas.append(Transform3D(Basis.from_scale(Vector3(1.6, 1.5, 3.4)), Vector3(0, 2.8, 0.3)))         # carenagem do motor
		pecas.append(Transform3D(Basis.from_scale(Vector3(0.5, 1.6, 0.5)), Vector3(0, 3.9, 0.0)))         # mastro
		ComplexoLancamento.criar_multimesh(heli, pecas, casco)
		var esquis: Array[Transform3D] = []
		for sx: float in [-1.0, 1.0]:
			esquis.append(ComplexoLancamento._viga(Vector3(sx * 2.4, -3.4, -4.5), Vector3(sx * 2.4, -3.4, 4.0), 0.3))
			for z: float in [-2.6, 2.2]:
				esquis.append(ComplexoLancamento._viga(Vector3(sx * 1.6, -2.0, z), Vector3(sx * 2.4, -3.4, z), 0.22))
		esquis.append(Transform3D(Basis.from_scale(Vector3(1.4, 1.2, 1.4)), Vector3(0, -3.0, 0)))          # gancho de carga
		ComplexoLancamento.criar_multimesh(heli, esquis, escuro)
		# Rotores: giram a cada quadro desenhado (girador.gd), com um disco translúcido de "borrão" por cima
		var girador: Script = load("res://scripts/efeitos/girador.gd")
		var borrao := StandardMaterial3D.new()
		borrao.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		borrao.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		borrao.albedo_color = Color(0.05, 0.05, 0.06, 0.22)
		borrao.cull_mode = BaseMaterial3D.CULL_DISABLED
		var rotor := Node3D.new()
		rotor.set_script(girador)
		rotor.set("velocidade", 34.0)
		rotor.position = Vector3(0, 4.8, 0)
		heli.add_child(rotor)
		var pas: Array[Transform3D] = []
		for k in 4:
			pas.append(Transform3D(Basis(Vector3.UP, TAU * k / 4.0) * Basis.from_scale(Vector3(0.9, 0.12, 12.5)), Basis(Vector3.UP, TAU * k / 4.0) * Vector3(0, 0, 6.6)))
		ComplexoLancamento.criar_multimesh(rotor, pas, escuro, false)
		var disco_r := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = 12.9
		cil.bottom_radius = 12.9
		cil.height = 0.05
		cil.radial_segments = 48
		disco_r.mesh = cil
		disco_r.material_override = borrao
		disco_r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rotor.add_child(disco_r)
		var rotor_cauda := Node3D.new()
		rotor_cauda.set_script(girador)
		rotor_cauda.set("eixo", Vector3.RIGHT)
		rotor_cauda.set("velocidade", 60.0)
		rotor_cauda.position = Vector3(0.45, 3.8, 15.3)
		heli.add_child(rotor_cauda)
		var pas_c: Array[Transform3D] = []
		for k in 2:
			pas_c.append(Transform3D(Basis(Vector3.RIGHT, PI * k / 2.0) * Basis.from_scale(Vector3(0.08, 4.4, 0.4)), Vector3.ZERO))
		ComplexoLancamento.criar_multimesh(rotor_cauda, pas_c, escuro, false)
	# Bater no helicóptero ou no rotor explode o carro (cilindro do tamanho do disco do rotor + a cauda)
	var mortal := StaticBody3D.new()
	mortal.collision_layer = 1
	mortal.collision_mask = 0
	mortal.add_to_group("estrutura")
	mortal.add_to_group("mortal")
	alvo.add_child(mortal)
	var cs := CollisionShape3D.new()
	var forma_h := CylinderShape3D.new()
	forma_h.radius = 13.0
	forma_h.height = 9.5
	cs.shape = forma_h
	cs.position = Vector3(0, altura_heli + 1.0, 0)
	mortal.add_child(cs)
	var cs_c := CollisionShape3D.new()
	var forma_c := CylinderShape3D.new()
	forma_c.radius = 17.5   # a cauda gira com o helicóptero: disco baixo que cobre qualquer rumo
	forma_c.height = 4.0
	cs_c.shape = forma_c
	cs_c.position = Vector3(0, altura_heli + 2.5, 0)
	if com_modelo:
		# Chinook: dois rotores, um em cada ponta — o disco cobre os dois em qualquer rumo, na altura deles
		forma_c.radius = CHINOOK_COMP * 0.42 + raio_rotor
		forma_c.height = 3.5
		cs_c.position = Vector3(0, altura_heli + 3.4, 0)
	mortal.add_child(cs_c)
	# Luzes de navegação, luz no casco e o holofote na barriga apontado para a rede
	var luzes: Array[Transform3D] = [Transform3D(Basis.from_scale(Vector3.ONE * 0.5), Vector3(-2.7, 0, 0))]
	ComplexoLancamento.criar_multimesh(heli, luzes, ComplexoLancamento._material_luz(Color(1, 0.05, 0.05), 6.0), false)
	luzes = [Transform3D(Basis.from_scale(Vector3.ONE * 0.5), Vector3(2.7, 0, 0))]
	ComplexoLancamento.criar_multimesh(heli, luzes, ComplexoLancamento._material_luz(Color(0.1, 1.0, 0.2), 6.0), false)
	for p_l: Vector3 in [Vector3(0, 7.5, -3.0), Vector3(0, -6.0, 3.0)]:
		var luz_h := OmniLight3D.new()
		luz_h.light_color = Color(1.0, 0.9, 0.75)
		luz_h.light_energy = 2.5
		luz_h.omni_range = 22.0
		luz_h.position = p_l
		heli.add_child(luz_h)
	var holofote := SpotLight3D.new()
	holofote.light_color = Color(1.0, 0.96, 0.85)
	holofote.light_energy = 30.0
	holofote.spot_range = altura_heli + 30.0
	holofote.spot_angle = 26.0
	holofote.shadow_enabled = false
	holofote.position = Vector3(0, altura_heli - 3.6, 0)
	holofote.rotation = Vector3(-PI * 0.5, 0, 0)
	alvo.add_child(holofote)
	alvo.dino_estado["heli"] = {"no": heli}
	alvo.dino_estado["altura_heli"] = altura_heli


const CHINOOK := "res://assets/dino/helicoptero/chinook.glb"
const CHINOOK_COMP := 24.0   # comprimento da fuselagem (m)

## Monta em `heli` (frente = -Z) o CH-47 Chinook de assets/dino/helicoptero (CC-BY, ver creditos.txt): mede o
## modelo, põe a fuselagem com CHINOOK_COMP m centrada no nó e a barriga logo acima do gancho, e solta os dois
## rotores (as peças chatas) em pivôs que giram em sentidos contrários, cada um com o seu disco de borrão.
## Devolve o raio do rotor em metros (0 = o arquivo não está no projeto).
static func _chinook(heli: Node3D) -> float:
	if not ResourceLoader.exists(CHINOOK):
		return 0.0
	var modelo: Node3D = (load(CHINOOK) as PackedScene).instantiate()
	var giro := Node3D.new()
	giro.name = "Chinook"
	giro.add_child(modelo)
	heli.add_child(giro)
	var corpo := AABB()
	var tem_corpo := false
	var chatas: Array = []   # [malha, transformação até o modelo, caixa]
	for no in modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := no as MeshInstance3D
		var xf := DinosParque._xf_ate(mi, modelo)
		var cx := xf * mi.get_aabb()
		if cx.size.y < 0.08 * maxf(cx.size.x, cx.size.z):
			chatas.append([mi, xf, cx])
		else:
			corpo = cx if not tem_corpo else corpo.merge(cx)
			tem_corpo = true
	if not tem_corpo or corpo.size.z < 0.01:
		return 0.0
	var esc := CHINOOK_COMP / corpo.size.z
	var meio_z := corpo.get_center().z
	# Os dois rotores: o da frente e o de trás (o da frente é o mais baixo)
	var grupos := [[], []]
	for c: Array in chatas:
		grupos[0 if (c[2] as AABB).get_center().z < meio_z else 1].append(c)
	var y_rotor := [0.0, 0.0]
	var raio := 0.0
	var girador: Script = load("res://scripts/efeitos/girador.gd")
	var borrao := StandardMaterial3D.new()
	borrao.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	borrao.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	borrao.albedo_color = Color(0.05, 0.05, 0.06, 0.2)
	borrao.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 2:
		var grupo: Array = grupos[k]
		if grupo.is_empty():
			continue
		# Eixo do rotor: o meio dos vértices das pás (são iguais e espalhadas em volta do cubo)
		var soma := Vector3.ZERO
		var qtd := 0
		var cx_g: AABB = grupo[0][2]
		for c: Array in grupo:
			cx_g = cx_g.merge(c[2])
			var malha := (c[0] as MeshInstance3D).mesh
			for sup in malha.get_surface_count():
				var vs: PackedVector3Array = malha.surface_get_arrays(sup)[Mesh.ARRAY_VERTEX]
				for v in vs:
					soma += (c[1] as Transform3D) * v
				qtd += vs.size()
		var cubo := soma / maxf(qtd, 1.0)
		cubo.y = cx_g.get_center().y
		y_rotor[k] = cubo.y
		var r_modelo := maxf(maxf(cx_g.end.x - cubo.x, cubo.x - cx_g.position.x), maxf(cx_g.end.z - cubo.z, cubo.z - cx_g.position.z))
		raio = maxf(raio, r_modelo * esc)
		var pivo := Node3D.new()
		pivo.name = "Rotor%d" % k
		pivo.set_script(girador)
		pivo.set("velocidade", 30.0 if k == 0 else -30.0)
		pivo.position = cubo
		modelo.add_child(pivo)
		for c: Array in grupo:
			var mi := c[0] as MeshInstance3D
			mi.get_parent().remove_child(mi)
			pivo.add_child(mi)
			mi.transform = Transform3D(Basis.IDENTITY, -cubo) * (c[1] as Transform3D)
		var disco := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = r_modelo
		cil.bottom_radius = r_modelo
		cil.height = 0.05 / esc
		cil.radial_segments = 48
		disco.mesh = cil
		disco.material_override = borrao
		disco.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivo.add_child(disco)
	# Frente para -Z: o rotor da frente é o mais baixo dos dois
	var vira := 0.0
	if not (grupos[0] as Array).is_empty() and not (grupos[1] as Array).is_empty() and float(y_rotor[1]) < float(y_rotor[0]):
		vira = PI   # o mais baixo está do lado +Z
	var base := Basis(Vector3.UP, vira) * Basis.from_scale(Vector3.ONE * esc)
	# Fuselagem centrada no nó; as rodas ficam 4,4 m abaixo dele (a barriga logo acima do gancho da rede)
	giro.transform = Transform3D(base, -(base * Vector3(corpo.get_center().x, corpo.position.y, meio_z)) + Vector3(0.0, -4.4, 0.0))
	return raio


## Helicóptero: vira o nariz para onde está voando, com uma inclinação à frente.
static func atualizar_heli(alvo: Alvo, delta: float) -> void:
	var h: Dictionary = alvo.dino_estado.heli
	var v := alvo.velocidade_atual
	var vh := Vector2(v.x, v.z).length()
	var no: Node3D = h.no
	if vh > 0.4:
		no.rotation.y = lerp_angle(no.rotation.y, atan2(-v.x, -v.z), clampf(delta * 1.6, 0.0, 1.0))
	no.rotation.x = lerpf(no.rotation.x, -0.16 * clampf(vh / 8.0, 0.0, 1.0), clampf(delta * 1.5, 0.0, 1.0))


# ------------------------------------------------------------------ meteoro caído

## Meteoro caído (etapas[].forma = "meteoro"): rocha irregular de `raio_meteoro` m meio enterrada no
## fundo da cratera, com uma bacia côncava no topo (diâmetro `bacia`, `fundo` m de profundidade) —
## o alvo é a bacia (colisão côncava no próprio Alvo: quem pousa escorrega para o meio); o resto da
## rocha é estrutura comum. A origem do alvo fica no nível da borda da bacia.
static func montar_meteoro(alvo: Alvo, etapa: Dictionary) -> void:
	var rb := float(etapa.get("bacia", 28.0)) * 0.5
	var fundo := float(etapa.get("fundo", 3.6))
	var raio := float(etapa.get("raio_meteoro", 27.0))
	const LABIO := 5.0
	var yc := -sqrt(maxf(raio * raio - (rb + LABIO) * (rb + LABIO), 1.0)) + 1.0   # centro da rocha, abaixo da borda da bacia
	alvo.raio_externo = rb
	var n1 := FastNoiseLite.new()
	n1.seed = 4242
	n1.frequency = 0.035
	n1.fractal_octaves = 3
	var n2 := FastNoiseLite.new()
	n2.seed = 99
	n2.frequency = 0.16
	n2.fractal_octaves = 2
	const ANEIS := 46
	const SEGS := 72
	var verts := PackedVector3Array()
	for i in ANEIS + 1:
		var fi := PI * float(i) / ANEIS
		for k in SEGS:
			var te := TAU * k / SEGS
			var dir := Vector3(sin(fi) * cos(te), cos(fi), sin(fi) * sin(te))
			var q := dir * raio
			# Relevo da rocha: calombos grandes, covas pequenas (regmaglitos) e arestas
			var rr := raio * (1.0 + 0.11 * n1.get_noise_3dv(q) + 0.035 * n2.get_noise_3dv(q) - 0.05 * maxf(n2.get_noise_3dv(q * 0.45 + Vector3(40, 0, 0)), 0.0))
			var p := Vector3(0.0, yc, 0.0) + dir * rr
			var d := Vector2(p.x, p.z).length()
			if dir.y > 0.0 and d < rb + LABIO:
				var bacia := -fundo * (1.0 - (d / rb) * (d / rb)) if d < rb else 0.0
				p.y = lerpf(bacia, p.y, smoothstep(rb, rb + LABIO, d))
				# Borda em crista (sem patamar): o carro não fica apoiado nela — escorrega para dentro ou para fora
				if d > rb:
					p.y += 1.6 * sin(PI * clampf((d - rb) / LABIO, 0.0, 1.0))
			verts.append(p)
	var st_bacia := SurfaceTool.new()
	st_bacia.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_bacia.set_smooth_group(0)
	var st_rocha := SurfaceTool.new()
	st_rocha.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_rocha.set_smooth_group(0)
	var faces_bacia := PackedVector3Array()
	var faces_rocha := PackedVector3Array()
	var base := alvo.centro_base
	for i in ANEIS:
		for k in SEGS:
			var a := i * SEGS + k
			var b := i * SEGS + (k + 1) % SEGS
			var c := b + SEGS
			var dd := a + SEGS
			for tri: Array in [[a, c, b], [a, dd, c]]:
				var na_bacia := true
				for v: int in tri:
					if verts[v].y > 0.35 or Vector2(verts[v].x, verts[v].z).length() > rb + 0.6 or v >= SEGS * (ANEIS / 2):
						na_bacia = false
				for v: int in tri:
					if na_bacia:
						st_bacia.add_vertex(verts[v])
						faces_bacia.append(verts[v])
					else:
						st_rocha.add_vertex(verts[v] + base)
						faces_rocha.append(verts[v] + base)
	st_bacia.index()
	st_bacia.generate_normals()
	st_rocha.index()
	st_rocha.generate_normals()
	# Bacia de pouso: parte do alvo (em brasa, para se ver de longe onde pousar)
	var mi := MeshInstance3D.new()
	mi.mesh = st_bacia.commit()
	var mb := _rocha_mat()
	mb.set_shader_parameter("c_basalto", Color(0.34, 0.25, 0.18))
	mb.set_shader_parameter("c_basalto_claro", Color(0.62, 0.5, 0.36))
	mb.set_shader_parameter("brasa", 0.8)
	mb.set_shader_parameter("calor_fixo", 1.0)
	mi.material_override = mb
	alvo.disco.add_child(mi)
	var forma_b := ConcavePolygonShape3D.new()
	forma_b.backface_collision = true
	forma_b.set_faces(faces_bacia)
	var cs := CollisionShape3D.new()
	cs.shape = forma_b
	alvo.add_child(cs)
	# O corpo do meteoro: fixo no mundo, rocha escura com poucas fissuras ainda quentes
	var fixo := alvo._no_fixo()
	var mr := MeshInstance3D.new()
	mr.mesh = st_rocha.commit()
	var mm := _rocha_mat()
	mm.set_shader_parameter("c_basalto", Color(0.15, 0.135, 0.13))
	mm.set_shader_parameter("c_basalto_claro", Color(0.36, 0.31, 0.27))
	mm.set_shader_parameter("brasa", 0.8)
	mm.set_shader_parameter("calor_fixo", 0.4)
	mr.material_override = mm
	fixo.add_child(mr)
	var est := alvo._corpo_estrutura(fixo)
	var forma_r := ConcavePolygonShape3D.new()
	forma_r.backface_collision = true
	forma_r.set_faces(faces_rocha)
	var cs_r := CollisionShape3D.new()
	cs_r.shape = forma_r
	est.add_child(cs_r)
	var liso := PhysicsMaterial.new()
	liso.friction = 0.03   # rocha vitrificada: a carroceria não agarra na borda
	est.physics_material_override = liso
	# Calor subindo da bacia: luz alaranjada
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.45, 0.15)
	luz.light_energy = 3.0
	luz.omni_range = rb * 2.2
	luz.shadow_enabled = false
	luz.position = Vector3(0.0, 4.0, 0.0)
	alvo.disco.add_child(luz)


# ------------------------------------------------------------------ pegada no pilar de rocha

static func _pilar_rocha(alvo: Alvo) -> void:
	var fixo := alvo._no_fixo()
	var chao := alvo._chao_em(alvo.centro_base.x, alvo.centro_base.z) - 2.0
	var topo := alvo.centro_base.y - Alvo.ESPESSURA - 1.0
	var prisma := CylinderMesh.new()
	prisma.radial_segments = 6
	prisma.rings = 1
	prisma.top_radius = 1.0
	prisma.bottom_radius = 1.0
	prisma.height = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var colunas: Array[Transform3D] = []
	# A mesa de basalto cobre a pegada inteira (antes só a palma tinha apoio e os dedos ficavam soltos no ar)
	var meio := Vector3.ZERO
	var raio_mesa := 6.0
	var pedacos: Array = alvo.dino_estado.get("pedacos", [])
	if not pedacos.is_empty():
		for pd: Dictionary in pedacos:
			meio += pd.centro
		meio /= pedacos.size()
		for pd: Dictionary in pedacos:
			raio_mesa = maxf(raio_mesa, Vector2(pd.centro.x - meio.x, pd.centro.z - meio.z).length() + 9.0)
	var cx := alvo.centro_base.x + meio.x
	var cz := alvo.centro_base.z + meio.z
	for k in int(22.0 * raio_mesa * raio_mesa / 36.0):
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * raio_mesa
		var rr := rng.randf_range(1.8, 3.2)
		var t := topo - rng.randf_range(0.0, 5.0) * pow(d / raio_mesa, 2.0)
		colunas.append(Transform3D(Basis.from_scale(Vector3(rr, t - chao, rr)), Vector3(cx + cos(a) * d, (t + chao) * 0.5, cz + sin(a) * d)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = prisma
	mm.instance_count = colunas.size()
	for k in colunas.size():
		mm.set_instance_transform(k, colunas[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _rocha_mat()
	fixo.add_child(mmi)
	var est := alvo._corpo_estrutura(fixo)
	var lado_c := raio_mesa * 1.6
	ComplexoLancamento.adicionar_colisoes(est, [Transform3D(Basis.from_scale(Vector3(lado_c, topo - 1.5 - chao, lado_c)), Vector3(cx, (topo - 1.5 + chao) * 0.5, cz))])


## Pegada: os dedos quebram nos instantes (fração do tempo da etapa) de etapas[].quebras, cada um
## atingido por um pedaço do meteoro. `pedacos` = [{mi, cs, mat}] na ordem palma, dedos.
static func atualizar_pegada(alvo: Alvo, fracao: float, delta: float) -> void:
	var est: Dictionary = alvo.dino_estado
	if not est.has("pedacos"):
		return
	var quebras: Array = est.get("quebras", [0.3, 0.55, 0.8])
	var pedacos: Array = est.pedacos
	for k in range(1, pedacos.size()):
		var p: Dictionary = pedacos[k]
		var q := float(quebras[mini(k - 1, quebras.size() - 1)]) if k - 1 < quebras.size() else 2.0
		var mat: ShaderMaterial = p.mat
		# Rachadura acende nos últimos 25% antes da quebra
		mat.set_shader_parameter("brasa", 0.7 + clampf((fracao - (q - 0.12)) / 0.12, 0.0, 1.0) * 2.3)
		if p.get("caiu", false):
			var mi: MeshInstance3D = p.mi
			p.vy = float(p.get("vy", 0.0)) - 9.8 * delta
			mi.position.y += p.vy * delta
			mi.rotate_object_local(Vector3.RIGHT, delta * 0.6)
			if mi.position.y < -300.0:
				mi.visible = false
			continue
		# O pedaço do meteoro cai 2 s antes da quebra
		if fracao >= q - 0.012 and not p.get("vindo", false):
			p.vindo = true
			var m := Meteoro.new()
			m.tamanho = 3.0
			alvo.get_parent().add_child(m)
			p.meteoro = m
			p.t_met = 0.0
		if p.get("vindo", false) and p.has("meteoro"):
			p.t_met = float(p.t_met) + delta
			var alvo_p: Vector3 = alvo.disco.global_transform * (p.centro as Vector3)
			var u := clampf(float(p.t_met) / 1.8, 0.0, 1.0)
			var m: Meteoro = p.meteoro
			m.mover_para(alvo_p + Vector3(0.4, 1.0, 0.25).normalized() * 380.0 * (1.0 - u))
			if u >= 1.0:
				var ex := Explosao.new()
				alvo.get_parent().add_child(ex)
				ex.global_position = alvo_p
				m.queue_free()
				p.erase("meteoro")
				p.caiu = true
				(p.cs as CollisionShape3D).disabled = true
