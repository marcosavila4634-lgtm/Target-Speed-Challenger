class_name Looping
extends Node3D
## Looping na estrada (pedido do dono, Extinction Day E4): a pista sobe, vira de cabeça para baixo e
## volta à estrada, com aceleradores ao longo da volta inteira que seguram a velocidade mínima.
##
## Visto de lado o laço é uma "gota": a curvatura cresce de zero até 1/raio (entrada suave, sem
## tranco), fica constante no alto e volta a zero. Visto de cima é uma hélice: a fita desloca
## `desvio` m de lado ao longo da volta para a perna de saída não bater na de entrada, e o carro
## que entra reto sai reto sem precisar virar o volante. A estrada do percurso passa por baixo em
## "S" da entrada até a saída, sem laje (ComplexoSubida._marcar_loopings): quem cai do laço cai no chão.
## Config (percursos.N.loopings): [trecho, m da entrada, raio, transição, desvio, aceleradores, velocidade mínima].

const ESPESSURA := 0.7
const GUIA_ALTURA := 0.55    # viga de borda: segura o carro que encosta de lado
const GUIA_LARGURA := 0.5

var pts := PackedVector3Array()    # eixo da fita, a cada ~1 m
var tan := PackedVector3Array()
var nrm := PackedVector3Array()    # normal do piso (para dentro do laço)
var lado := PackedVector3Array()   # da borda esquerda para a direita
var largura := 10.0
var altura := 0.0
var rumo := Vector3.FORWARD        # direção horizontal da entrada (e da saída)
var i_entrada := 0                 # amostras da estrada onde a fita começa e termina
var i_saida := 0
var n_impulsos := 10
var vel_min := 26.0
var _centro := Vector3.ZERO
var _raio := 0.0
var _passo := 1.0


## Perfil visto de lado, a cada ~1 m: [posições (x à frente, y para cima), ângulos, comprimento].
## Mesma conta de tools/extinction_day/gen.js (perfil_loop).
static func perfil(r: float, lt: float) -> Array:
	var k := 1.0 / r
	var total := 2.0 * lt + (TAU - k * lt) / k
	var n := int(round(total))
	const SUB := 4
	var passo := total / float(n * SUB)
	var pos := PackedVector2Array([Vector2.ZERO])
	var ang := PackedFloat32Array([0.0])
	var x := 0.0
	var y := 0.0
	var th := 0.0
	for i in n * SUB:
		var um := (float(i) + 0.5) * passo
		var kk := k * um / lt if um < lt else (k * (total - um) / lt if um > total - lt else k)
		th += kk * passo * 0.5
		x += cos(th) * passo
		y += sin(th) * passo
		th += kk * passo * 0.5
		if i % SUB == SUB - 1:
			pos.append(Vector2(x, y))
			ang.append(th)
	return [pos, ang, total]


## Calcula a fita a partir da amostra `i0` da estrada (antes da malha da estrada, que fica sem laje embaixo).
func calcular(sub: ComplexoSubida, i0: int, r: float, lt: float, desvio: float) -> void:
	largura = sub.largura_estrada
	i_entrada = i0
	var p0 := sub.amostra(i0)
	var t0 := sub.tangente_em(i0)
	t0.y = 0.0
	t0 = t0.normalized()
	rumo = t0
	var lat0 := t0.cross(Vector3.UP)
	var pf := perfil(r, lt)
	var pos: PackedVector2Array = pf[0]
	var ang: PackedFloat32Array = pf[1]
	var total: float = pf[2]
	var n := pos.size() - 1
	_passo = total / float(n)
	# Hélice: eixo do cilindro (eixo_a) quase de lado; a entrada aponta exatamente para t0
	var tg := desvio / total
	var c := 1.0 / sqrt(1.0 + tg * tg)
	var eixo_x := t0 * c - lat0 * (tg * c)
	var eixo_a := t0 * (tg * c) + lat0 * c
	pts.resize(n + 1)
	tan.resize(n + 1)
	nrm.resize(n + 1)
	lado.resize(n + 1)
	for j in n + 1:
		var u := _passo * j
		pts[j] = p0 + eixo_x * pos[j].x + Vector3.UP * pos[j].y + eixo_a * (u * tg)
		tan[j] = (eixo_x * cos(ang[j]) + Vector3.UP * sin(ang[j]) + eixo_a * tg).normalized()
		nrm[j] = -eixo_x * sin(ang[j]) + Vector3.UP * cos(ang[j])
		lado[j] = tan[j].cross(nrm[j]).normalized()
		altura = maxf(altura, pos[j].y)
	# A ponta da fita pousa exatamente na amostra da estrada mais perto (o "S" do traçado chega ali)
	i_saida = i0
	var fim := sub.fim_do_trecho(i0)
	for i in range(i0 + 1, fim + 1):
		if sub.amostra(i).distance_squared_to(pts[n]) < sub.amostra(i_saida).distance_squared_to(pts[n]):
			i_saida = i
	var erro := sub.amostra(i_saida) - pts[n]
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SUB] looping em %s: fita %.0f m, altura %.1f m, saída a %.2f m da estrada" % [str(p0.snapped(Vector3.ONE)), total / c, altura, erro.length()])
	for j in n + 1:
		pts[j] += erro * smoothstep(0.5, 1.0, float(j) / n)
	for p in pts:
		_centro += p / float(n + 1)
	for p in pts:
		_raio = maxf(_raio, p.distance_to(_centro))
	_raio += largura


## Monta a malha, a colisão, a estrutura e os aceleradores. `impulsos` é a lista do ComplexoSubida
## ([centro, tangente, lateral, normal, velocidade, meia largura, looping]).
func montar(sub: ComplexoSubida, mat_pista: Material, impulsos: Array) -> void:
	name = "Looping"
	var n := pts.size() - 1
	var meia := largura * 0.5
	var topo := SurfaceTool.new()
	topo.begin(Mesh.PRIMITIVE_TRIANGLES)
	var aco := SurfaceTool.new()
	aco.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var s0 := sub.progresso_amostra(i_entrada)
	for j in range(1, n + 1):
		var a := j - 1
		var e0 := pts[a] - lado[a] * meia + nrm[a] * 0.03
		var d0 := pts[a] + lado[a] * meia + nrm[a] * 0.03
		var e1 := pts[j] - lado[j] * meia + nrm[j] * 0.03
		var d1 := pts[j] + lado[j] * meia + nrm[j] * 0.03
		_quad(topo, e0, d0, d1, e1, nrm[a], nrm[j], Vector2(0.0, s0 + a * _passo), Vector2(1.0, s0 + j * _passo))
		faces.append_array([e0, d0, d1, e0, d1, e1])
		# Fundo da laje
		var f0 := nrm[a] * ESPESSURA
		var f1 := nrm[j] * ESPESSURA
		_quad(aco, d1 - f1, e1 - f1, e0 - f0, d0 - f0, -nrm[j], -nrm[a], Vector2(0.0, j), Vector2(largura, a))
		faces.append_array([d0 - f0, e0 - f0, e1 - f1, d0 - f0, e1 - f1, d1 - f1])
		# Vigas de borda (do fundo da laje até GUIA_ALTURA acima do piso): face de dentro, topo e face de fora
		for sinal: float in [-1.0, 1.0]:
			var b0 := pts[a] + lado[a] * sinal * meia
			var b1 := pts[j] + lado[j] * sinal * meia
			var fora0 := lado[a] * sinal
			var fora1 := lado[j] * sinal
			var g0 := nrm[a] * GUIA_ALTURA
			var g1 := nrm[j] * GUIA_ALTURA
			var o0 := fora0 * GUIA_LARGURA
			var o1 := fora1 * GUIA_LARGURA
			var dentro := [b0, b0 + g0, b1 + g1, b1]
			var cima := [b0 + g0, b0 + g0 + o0, b1 + g1 + o1, b1 + g1]
			var fora := [b0 + g0 + o0, b0 + o0 - f0, b1 + o1 - f1, b1 + g1 + o1]
			var baixo := [b0 + o0 - f0, b0 - f0, b1 - f1, b1 + o1 - f1]
			var quads := [[dentro, -fora0, -fora1], [cima, nrm[a], nrm[j]], [fora, fora0, fora1], [baixo, -nrm[a], -nrm[j]]]
			for q: Array in quads:
				var v: Array = q[0]
				# (face da frente = sentido horário visto de fora)
				if sinal < 0.0:
					_quad(aco, v[0], v[1], v[2], v[3], q[1], q[2], Vector2(0.0, a), Vector2(1.0, j))
				else:
					_quad(aco, v[3], v[2], v[1], v[0], q[2], q[1], Vector2(0.0, j), Vector2(1.0, a))
			faces.append_array([dentro[0], dentro[1], dentro[2], dentro[0], dentro[2], dentro[3]])
			faces.append_array([cima[0], cima[1], cima[2], cima[0], cima[2], cima[3]])
	var mi := MeshInstance3D.new()
	mi.mesh = topo.commit()
	mi.material_override = mat_pista
	add_child(mi)
	var mat_aco := sub.material_aco(0.0, 0.55)
	var ma := MeshInstance3D.new()
	ma.mesh = aco.commit()
	ma.material_override = mat_aco
	add_child(ma)
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	var forma := ConcavePolygonShape3D.new()
	forma.backface_collision = true
	forma.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = forma
	corpo.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	corpo.physics_material_override = pm
	add_child(corpo)
	_estrutura(sub, mat_aco)
	_aceleradores(impulsos)


## Costelas embaixo da fita, pilares de concreto sob as pernas, e um pórtico de dois mastros com
## tirantes segurando a parte alta (nada flutua).
func _estrutura(sub: ComplexoSubida, mat_aco: Material) -> void:
	var n := pts.size() - 1
	var meia := largura * 0.5
	var costelas: Array[Transform3D] = []
	for j in range(4, n - 3, 5):
		var b := Basis(lado[j], nrm[j], -tan[j]) * Basis.from_scale(Vector3(largura + GUIA_LARGURA * 2.0 + 0.5, 0.5, 0.6))
		costelas.append(Transform3D(b, pts[j] - nrm[j] * (ESPESSURA + 0.25)))
	# Pilares: onde o fundo da fita olha para baixo e não há outra perna do laço embaixo
	var terreno := sub._terreno
	var colunas: Array[Transform3D] = []
	var bh := Basis.looking_at(rumo, Vector3.UP)
	var ultimo := -100
	for j in range(14, n - 13):
		if nrm[j].y < 0.55 or j - ultimo < 14 or _perna_embaixo(j):
			continue
		ultimo = j
		var p := pts[j] - nrm[j] * (ESPESSURA + 0.5)
		var chao := terreno.altura_em(p.x, p.z)
		if p.y - chao > 1.0:
			colunas.append(Transform3D(bh * Basis.from_scale(Vector3(2.6, p.y - chao + 2.0, 2.6)), Vector3(p.x, (p.y + chao - 2.0) * 0.5, p.z)))
	# Pórtico: um mastro de cada lado, travessa por cima do topo do laço
	var eixo := rumo.cross(Vector3.UP)
	var j_topo := n / 2
	var meio := pts[j_topo]
	var desvio := (pts[n] - pts[0]).dot(eixo)
	var y_topo := meio.y + 5.0
	var pes: Array[Vector3] = []
	for sinal: float in [-1.0, 1.0]:
		var pe := meio + eixo * sinal * (absf(desvio) * 0.5 + meia + 5.0)
		var chao := terreno.altura_em(pe.x, pe.z)
		colunas.append(Transform3D(bh * Basis.from_scale(Vector3(3.4, y_topo - chao + 2.0, 3.4)), Vector3(pe.x, (y_topo + chao - 2.0) * 0.5, pe.z)))
		pes.append(Vector3(pe.x, y_topo, pe.z))
	var trelicas: Array[Transform3D] = ComplexoLancamento.trelica(pes[0], pes[1], 2.2, 3.0, 0.28, 0.12)
	# Pendurais da travessa até as bordas da fita no alto
	var cabos: Array[Transform3D] = []
	for dj: int in [-10, -5, 0, 5, 10]:
		var j := j_topo + dj
		for sinal: float in [-1.0, 1.0]:
			var borda := pts[j] + lado[j] * sinal * (meia + GUIA_LARGURA * 0.5) - nrm[j] * ESPESSURA
			var em_cima := pes[0] + (pes[1] - pes[0]) * clampf((borda - pes[0]).dot(pes[1] - pes[0]) / (pes[1] - pes[0]).length_squared(), 0.0, 1.0)
			cabos.append(ComplexoLancamento._viga(borda, em_cima, 0.22))
	# Tirantes: do topo de cada mastro às bordas da meia-volta do lado dele (por fora da pista)
	for f: float in [0.14, 0.22, 0.3, 0.38]:
		for k in 2:
			var j := int(round((f if k == 0 else 1.0 - f) * n))
			var sinal := -1.0 if k == 0 else 1.0
			if (pts[j] + lado[j] * sinal - pes[k]).length() > (pts[j] - lado[j] * sinal - pes[k]).length():
				sinal = -sinal
			cabos.append(ComplexoLancamento._viga(pts[j] + lado[j] * sinal * (meia + GUIA_LARGURA) - nrm[j] * 0.3, pes[k], 0.16))
	ComplexoLancamento.criar_multimesh(self, costelas, mat_aco)
	ComplexoLancamento.criar_multimesh(self, trelicas, mat_aco)
	ComplexoLancamento.criar_multimesh(self, cabos, mat_aco, false)
	ComplexoLancamento.criar_multimesh(self, colunas, sub._material_pilar())
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	add_child(corpo)
	ComplexoLancamento.adicionar_colisoes(corpo, colunas)


## Outra parte da fita passa embaixo da amostra j (a perna de entrada cruza por cima da de saída)?
func _perna_embaixo(j: int) -> bool:
	for k in range(0, pts.size(), 3):
		if absi(k - j) < 20:
			continue
		var d := pts[k] - pts[j]
		if d.y < -1.0 and Vector2(d.x, d.z).length() < largura * 0.5 + 2.5:
			return true
	return false


## Aceleradores na largura toda da pista, espalhados pela volta inteira.
func _aceleradores(impulsos: Array) -> void:
	var n := pts.size() - 1
	const MEIO_COMP := 3.0
	var meia := largura * 0.5 - 0.6
	for k in n_impulsos:
		var j := int(round((float(k) + 0.5) / n_impulsos * n))
		impulsos.append([pts[j], tan[j], lado[j], nrm[j], vel_min, meia, true])
		var placa := PlaneMesh.new()
		placa.size = Vector2(meia * 2.0, MEIO_COMP * 2.0)
		var mi := MeshInstance3D.new()
		mi.mesh = placa
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/impulso.gdshader")
		mat.set_shader_parameter("cor", Color(1.0, 0.55, 0.1))
		mat.set_shader_parameter("tamanho", placa.size)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis.looking_at(tan[j], nrm[j]), pts[j] + nrm[j] * 0.08)
		add_child(mi)


## Amostra da fita em que `p` está (em cima do piso, entre as bordas); -1 fora do looping.
## `pontas`: conta também o começo e o fim, onde a fita ainda está colada na estrada (os bots seguem
## o eixo da fita da entrada até depois da saída).
func amostra_em(p: Vector3, pontas := false) -> int:
	if p.distance_squared_to(_centro) > _raio * _raio:
		return -1
	var melhor := -1
	var melhor_d := 36.0
	for j in pts.size():
		var d := p.distance_squared_to(pts[j])
		if d < melhor_d:
			var q := p - pts[j]
			var h := q.dot(nrm[j])
			if h > -1.0 and h < 5.0 and absf(q.dot(lado[j])) < largura * 0.5 + 1.0:
				melhor_d = d
				melhor = j
	# As pontas ainda são estrada comum (a fita está colada nela): só conta depois de subir um pouco
	if melhor >= 0 and ((melhor < 10 or melhor > pts.size() - 11) if not pontas else melhor < 3):
		return -1
	return melhor


## Ponto do eixo `metros` à frente da amostra j (para os bots mirarem).
func adiante(j: int, metros: float) -> Vector3:
	var k := j + int(round(metros / _passo))
	if k <= pts.size() - 1:
		return pts[k]
	return pts[pts.size() - 1] + rumo * ((k - pts.size() + 1) * _passo)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n0: Vector3, n1: Vector3, uv0: Vector2, uv1: Vector2) -> void:
	st.set_normal(n0); st.set_uv(Vector2(uv0.x, uv0.y)); st.add_vertex(a)
	st.set_normal(n0); st.set_uv(Vector2(uv1.x, uv0.y)); st.add_vertex(b)
	st.set_normal(n1); st.set_uv(Vector2(uv1.x, uv1.y)); st.add_vertex(c)
	st.set_normal(n0); st.set_uv(Vector2(uv0.x, uv0.y)); st.add_vertex(a)
	st.set_normal(n1); st.set_uv(Vector2(uv1.x, uv1.y)); st.add_vertex(c)
	st.set_normal(n1); st.set_uv(Vector2(uv0.x, uv1.y)); st.add_vertex(d)
