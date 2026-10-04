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
var portico_arte := ""       # tema "dino": arte pronta do pórtico inteiro (res://...); entra no lugar do pórtico montado
var placa_imagem := ""       # tema "dino": imagem pronta (res://...) usada como placa do pórtico no lugar do letreiro montado
## "egito" (Pharaoh's Climb): arenito dourado, grade de bronze e luzes douradas.
## "gelo" (Frozen Peak): blocos de gelo azulado, grade de aço com geada e luzes azul-gelo.
var tema := ""
## Piso escorregadio (Frozen Peak: a plataforma dos buracos é de gelo). 1 = normal.
var aderencia := 1.0
## Extinction Day E2 (pedido do dono): plataforma sem chão — um poço de lava entre muralhas. Quem
## entra salta da estrada e tem de atravessar de paraquedas até o portão da saída.
var sem_piso := false
var entrada_fundo := 0.0   # largura de um vão no muro do fundo, no eixo (poço no nível da pista: a estrada entra por ele)
## Entradas forradas de aceleradores (ver forrar_portas): os bots pulam por cima com o ejetor.
var porta_acelerada := false
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
	if sem_piso:
		buracos.clear()
		impulsos.clear()
		_montar_poco()
	else:
		_montar_piso()
	_montar_pedestal()
	_montar_cerca()
	_montar_buracos()
	_montar_impulsos()
	_montar_vagas()
	_montar_portao()
	_montar_nav()


## Pedido do dono (vale para a plataforma dos buracos de TODOS os mapas): cada entrada fica coberta de
## aceleradores — duas fileiras de cinco, da parede até 14 m para dentro e 4 m além de cada lado da porta
## — que jogam quem entra na direção do buraco mais perto em frente (até 30° para o lado; sem buraco no
## cone, reto para dentro). Não dá para contornar: só passa quem pula. Entrada que a config já forrou
## (Extinction Day) fica como está. Chamar antes de montar().
func forrar_portas() -> void:
	if sem_piso or buracos.is_empty():
		return
	var meia := largura_arena * 0.5
	for e in entradas:
		var s := float(e[0])
		var xe := float(e[1])
		var ja := 0
		for im in impulsos:
			if absf((im[0] as Vector2).x - xe) < 9.5 and absf((im[0] as Vector2).y - s * (meia - 7.0)) < 8.0:
				ja += 1
		porta_acelerada = true
		if ja >= 6:
			continue
		var para_dentro := -PI * 0.5 * s
		var ang := para_dentro
		var porta := Vector2(xe, s * meia)
		var melhor := INF
		for b in buracos:
			var d: Vector2 = (b[0] as Vector2) - porta
			var desvio := wrapf(atan2(d.y, d.x) - para_dentro, -PI, PI)
			if absf(desvio) < deg_to_rad(40.0) and d.length() < melhor:
				melhor = d.length()
				ang = para_dentro + clampf(desvio, -deg_to_rad(30.0), deg_to_rad(30.0))
		for fila: float in [3.5, 10.5]:
			for dx: float in [-8.0, -4.0, 0.0, 4.0, 8.0]:
				impulsos.append([Vector2(xe + dx, s * (meia - fila)), ang, false])


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
	return p.y < piso_y - (14.0 if sem_piso else 6.0) and p.y > chao_y


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
	if tema == "selva":
		m.set_shader_parameter("cor_pedra", Color(0.52, 0.52, 0.44))
		m.set_shader_parameter("cor_argamassa", Color(0.24, 0.3, 0.16))
	if tema == "egito":
		m.set_shader_parameter("cor_pedra", Color(0.84, 0.68, 0.46))
		m.set_shader_parameter("cor_argamassa", Color(0.62, 0.52, 0.38))
	if tema == "gelo":
		m.set_shader_parameter("cor_pedra", Color(0.66, 0.8, 0.92))
		m.set_shader_parameter("cor_argamassa", Color(0.9, 0.95, 1.0))
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
	if tema == "selva":
		mat.set_shader_parameter("cor_piso", Color(0.5, 0.49, 0.42))
	if tema == "egito":
		mat.set_shader_parameter("cor_piso", Color(0.74, 0.62, 0.45))
	if tema == "gelo":
		mat.set_shader_parameter("cor_piso", Color(0.62, 0.78, 0.9) if aderencia < 0.99 else Color(0.8, 0.86, 0.92))
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
	if aderencia < 0.99:
		corpo.set_meta("aderencia", aderencia)   # piso de gelo: o Veiculo lê a meta do corpo sob a roda


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
	ComplexoLancamento.criar_multimesh(self, led, ComplexoLancamento._material_luz(_cor_luz(), 3.0), false)


## Trechos (x, lat) dos muros, deixando o vão da saída na frente e as entradas nas laterais.
func _trechos_muro() -> Array:
	var meia := largura_arena * 0.5 + PAREDE * 0.5
	var xf := -PAREDE * 0.5
	var xp := comprimento + PAREDE * 0.5
	var g := saida_largura * 0.5 + 1.6
	var trechos := [
		[Vector2(xp, -meia), Vector2(xp, -g)],
		[Vector2(xp, g), Vector2(xp, meia)],
	]
	if entrada_fundo > 0.0:
		var gf := entrada_fundo * 0.5 + 1.6
		trechos.append([Vector2(xf, -meia), Vector2(xf, -gf)])
		trechos.append([Vector2(xf, gf), Vector2(xf, meia)])
	else:
		trechos.append([Vector2(xf, -meia), Vector2(xf, meia)])
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
	mat_capa.set_shader_parameter("cor_pedra", Color(0.95, 0.97, 1.0) if tema == "gelo" else Color(0.7, 0.58, 0.47))   # gelo: capa de neve
	ComplexoLancamento.criar_multimesh(self, capa, mat_capa)
	ComplexoLancamento.criar_multimesh(self, ferro, ComplexoLancamento._material_metal(Color(0.55, 0.36, 0.14) if tema == "egito" else (Color(0.2, 0.32, 0.22) if tema == "selva" else (Color(0.45, 0.52, 0.6) if tema == "gelo" else Color(0.07, 0.065, 0.06))), 0.85, 0.4 if tema == "egito" else 0.55))
	ComplexoLancamento.adicionar_colisoes(corpo, colisao)
	var ferrugem := ComplexoLancamento._material_metal(Color(0.85, 0.6, 0.22), 1.0, 0.3) if tema == "egito" or tema == "selva" else (ComplexoLancamento._material_metal(Color(0.6, 0.7, 0.8), 0.9, 0.3) if tema == "gelo" else ComplexoLancamento._material_metal(Color(0.3, 0.14, 0.07), 0.6, 0.8))
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


## Sem piso: lava no fundo do poço (o pedestal vira a muralha de dentro), brilho subindo pelas
## paredes, luzes vermelhas e brasas. Cair aqui é morte (buraco_mortal).
func _montar_poco() -> void:
	var fundo := chao_y + 2.0
	var meia := largura_arena * 0.5 + PAREDE
	var plano := PlaneMesh.new()
	plano.size = Vector2(meia * 2.0, comprimento + PAREDE * 2.0)
	plano.subdivide_width = 8
	plano.subdivide_depth = 8
	var mi := MeshInstance3D.new()
	mi.mesh = plano
	mi.material_override = Dino.material_lava(0, 0.06, 0.85, 14.0, 5.5, 20.0, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis.looking_at(frente, Vector3.UP), pa(comprimento * 0.5, 0.0, fundo))
	add_child(mi)
	for k in 6:
		var q := pa(comprimento * (0.2 + 0.3 * (k % 3)), (largura_arena * 0.28) * (1.0 if k < 3 else -1.0), fundo + 12.0)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.3, 0.08)
		luz.light_energy = 9.0
		luz.omni_range = piso_y - fundo + 10.0
		luz.omni_attenuation = 1.1
		luz.position = q
		add_child(luz)
		Fogo.criar(self, Vector3(q.x, fundo + 0.5, q.z), 6.0, 10.0, 40, 7.0)


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


## Pórtico pela arte pronta do dono (`portico_arte`: pilares de pedra com tochas, placa EXTINCTION DAY com o
## medalhão, cipós e portões de madeira): a arte de pé nas duas faces (TunelVulcao.montar_arte), com as
## folhas abertas para dentro, em relevo (tem corpo de qualquer ângulo), colisão nos pilares e na viga e o
## semáforo pendurado embaixo da viga. false se a arte não está na pasta.
func _montar_portao_arte() -> bool:
	const FOLHAS: Array[Rect2] = [Rect2(0.238, 0.565, 0.14, 0.425), Rect2(0.626, 0.565, 0.14, 0.425)]
	const TOCHAS: Array[Vector2] = [Vector2(0.205, 0.05), Vector2(0.805, 0.05), Vector2(0.135, 0.4), Vector2(0.87, 0.41), Vector2(0.09, 0.74), Vector2(0.915, 0.73)]
	var x := comprimento + PAREDE * 0.5
	var larg := (saida_largura + 4.5) / 0.52   # o vão entre os pilares da arte é 52% da largura dela
	var alt := TunelVulcao.montar_arte(self, portico_arte, FOLHAS, TOCHAS, pa(x, 0.0, piso_y), -frente, larg, -0.3, true, 1.3)
	if alt <= 0.0:
		return false
	var b := Basis.looking_at(frente, Vector3.UP)
	var pedra: Array[Transform3D] = []
	# Sapatas de pedra embaixo dos pilares, até o chão (na plataforma o lado de fora do pórtico passa da
	# beirada: sem elas ficaria no ar)
	var sapatas: Array[Transform3D] = []
	var fundo_s := minf(chao_y, piso_y - 2.0) - 1.0
	for s: float in [-1.0, 1.0]:
		sapatas.append(Transform3D(b * Basis.from_scale(Vector3(larg * 0.2, piso_y - fundo_s, 4.6)), pa(x, s * larg * 0.37, (piso_y + fundo_s) * 0.5)))
	ComplexoLancamento.criar_multimesh(self, sapatas, _material_pedra())
	for s: float in [-1.0, 1.0]:
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(larg * 0.11, alt * 0.74, 2.2)), pa(x, s * larg * 0.36, piso_y + alt * 0.37)))
	pedra.append(Transform3D(b * Basis.from_scale(Vector3(larg * 0.6, alt * 0.16, 2.2)), pa(x, 0.0, piso_y + alt * 0.63)))
	ComplexoLancamento.adicionar_colisoes(corpo, pedra)
	# Semáforo pendurado embaixo da viga, virado para dentro
	var para_dentro := Basis.looking_at(-frente, Vector3.UP)
	var y_s := piso_y + alt * 0.47 - 1.4
	var caixa := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(7.6, 2.1, 0.7)
	caixa.mesh = cm
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.16, 0.1, 0.06)
	madeira.roughness = 0.9
	caixa.material_override = madeira
	caixa.transform = Transform3D(para_dentro, pa(x - 2.6, 0.0, y_s))
	add_child(caixa)
	var lampada := CylinderMesh.new()
	lampada.top_radius = 0.75
	lampada.bottom_radius = 0.75
	lampada.height = 0.25
	lampada.radial_segments = 24
	for k in 3:
		var l := MeshInstance3D.new()
		l.mesh = lampada
		l.transform = Transform3D(para_dentro * Basis(Vector3.RIGHT, PI * 0.5), pa(x - 3.02, (k - 1) * 2.3, y_s))
		add_child(l)
		semaforo_lampadas.append(l)
	return true


## Pórtico do parque (Extinction Day; o dono mandou um desenho de referência e pediu "igual"): dois
## pilares de pedra gasta com fogo no alto e lanternas de ferro, placa de pranchas escuras com o nome em
## duas linhas de letras de madeira acesas, medalhão com a silhueta do tiranossauro em cima, marcas de
## garra, portões de madeira abertos para fora e cipós pendurados. O semáforo fica pendurado embaixo da viga.
## Com `placa_imagem` (arte pronta do dono), a imagem entra no lugar do letreiro e do medalhão montados.
## Pedra com musgo e rachaduras, cunhais nas quinas, cintas de ferro com rebites e presas de osso na viga.
func _montar_portao_dino() -> void:
	if portico_arte != "" and _montar_portao_arte():
		return
	var g := saida_largura * 0.5 + 3.6            # meio de cada pilar
	var vao := muro_altura + grade_altura + 3.4   # altura livre embaixo da viga
	var placa := _textura_placa()
	var com_imagem := not placa.is_empty()
	var alt_p := vao + (11.0 if com_imagem else 7.4)
	var b := Basis.looking_at(frente, Vector3.UP)
	var lat_d := b.x
	var x := comprimento + PAREDE * 0.5
	var leitura := Basis.looking_at(frente, Vector3.UP)   # Label3D é lido pelo +Z: virado para dentro
	var rng := RandomNumberGenerator.new()
	rng.seed = 4107
	var pedra_m := _material_pedra()
	pedra_m.set_shader_parameter("cor_pedra", Color(0.6, 0.5, 0.37))
	pedra_m.set_shader_parameter("cor_argamassa", Color(0.27, 0.23, 0.17))
	pedra_m.set_shader_parameter("fiada", 1.15)
	pedra_m.set_shader_parameter("musgo", 0.85)
	pedra_m.set_shader_parameter("rachaduras", 0.8)
	var rebites: Array[Transform3D] = []
	var madeira := ShaderMaterial.new()
	madeira.shader = load("res://shaders/madeira_via.gdshader")
	madeira.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 91))
	madeira.set_shader_parameter("eixo_veio", lat_d)
	var ferro_m := ComplexoLancamento._material_metal(Color(0.06, 0.055, 0.05), 0.8, 0.6)
	var pedra: Array[Transform3D] = []
	var tabuas: Array[Transform3D] = []
	var ferro: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	# Pilares: base larga, fuste, dois degraus no alto e o fogo
	for s: float in [-1.0, 1.0]:
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(5.2, 1.6, 5.2)), pa(x, g * s, piso_y + 0.8)))
		var fuste := Transform3D(b * Basis.from_scale(Vector3(4.2, alt_p, 4.2)), pa(x, g * s, piso_y + alt_p * 0.5))
		pedra.append(fuste)
		colisao.append(fuste)
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(4.9, 0.8, 4.9)), pa(x, g * s, piso_y + alt_p * 0.62)))
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(4.9, 0.7, 4.9)), pa(x, g * s, piso_y + alt_p + 0.35)))
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(3.4, 0.8, 3.4)), pa(x, g * s, piso_y + alt_p + 1.1)))
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(6.0, 0.7, 6.0)), pa(x, g * s, piso_y + 0.35)))
		# Cunhais: blocos maiores e salientes nas quatro quinas, alternando o lado comprido
		var fiadas := int((alt_p - 2.2) / 1.15)
		for k in fiadas:
			var comprido := k % 2 == 0
			var tam := Vector3(1.4 if comprido else 0.75, 1.0, 0.75 if comprido else 1.4)
			for ql: float in [-1.0, 1.0]:
				for qx: float in [-1.0, 1.0]:
					pedra.append(Transform3D(b * Basis.from_scale(tam), pa(x + qx * (2.24 - tam.z * 0.5), g * s + ql * (2.24 - tam.x * 0.5), piso_y + 2.2 + k * 1.15)))
		# Cintas de ferro com rebites
		for fy: float in [0.2, 0.42, 0.86]:
			var yb := piso_y + alt_p * fy
			ferro.append(Transform3D(b * Basis.from_scale(Vector3(4.62, 0.4, 4.62)), pa(x, g * s, yb)))
			for d: float in [-1.6, -0.55, 0.55, 1.6]:
				for face: float in [-1.0, 1.0]:
					rebites.append(Transform3D(b * Basis.from_scale(Vector3(0.2, 0.2, 0.2)), pa(x + face * 2.34, g * s + d, yb)))
					rebites.append(Transform3D(b * Basis.from_scale(Vector3(0.2, 0.2, 0.2)), pa(x + d, g * s + face * 2.34, yb)))
		var topo := pa(x, g * s, piso_y + alt_p + 1.5)
		Fogo.criar(self, topo, 1.0, 4.2, 46, 1.9)
		var luz_t := OmniLight3D.new()
		luz_t.light_color = Color(1.0, 0.55, 0.2)
		luz_t.light_energy = 4.0
		luz_t.omni_range = 26.0
		luz_t.shadow_enabled = false
		luz_t.position = topo + Vector3.UP * 1.5
		add_child(luz_t)
		# Lanterna de ferro na face de dentro: braço, cesto com grades e o fogo
		var lan := pa(x - 2.9, g * s, piso_y + vao - 1.6)
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.14, 0.14, 1.0)), lan + frente * 0.4 + Vector3.UP * 0.9))
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(1.1, 0.12, 1.1)), lan))
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(1.1, 0.12, 1.1)), lan + Vector3.UP * 1.0))
		for cx: float in [-0.5, 0.5]:
			for cz: float in [-0.5, 0.5]:
				ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.09, 1.0, 0.09)), lan + lat_d * cx + frente * cz + Vector3.UP * 0.5))
		Fogo.criar(self, lan + Vector3.UP * 0.15, 0.3, 1.3, 16, 0.7, false)
		var luz_l := OmniLight3D.new()
		luz_l.light_color = Color(1.0, 0.6, 0.25)
		luz_l.light_energy = 3.0
		luz_l.omni_range = 16.0
		luz_l.shadow_enabled = false
		luz_l.position = lan - frente * 1.5 + Vector3.UP * 0.6
		add_child(luz_l)
	# Placa: cinco pranchas deitadas entre os pilares (passam um pouco por cima deles), viga embaixo,
	# arco de madeira em cima e ferragens nas pontas
	var larg := g * 2.0 + 1.2
	var alto := 9.5 if com_imagem else 5.5
	var cy := vao + 0.9 + alto * 0.5
	var xp := x - 2.4   # meio da espessura da placa (face de dentro em x - 2,65)
	for k in 5:
		var hy := alto / 5.0
		tabuas.append(Transform3D(b * Basis.from_scale(Vector3(larg - 0.25 * fmod(k * 1.7, 1.0), hy - 0.07, 0.5)), pa(xp, 0.12 * sin(k * 2.1), piso_y + cy - alto * 0.5 + hy * (k + 0.5))))
	var viga := Transform3D(b * Basis.from_scale(Vector3(larg + 1.4, 0.95, 1.1)), pa(xp, 0.0, piso_y + vao + 0.45))
	tabuas.append(viga)
	colisao.append(viga)
	const GOMOS := 10
	if not com_imagem:
		for k in GOMOS:
			var u0 := lerpf(-1.0, 1.0, float(k) / GOMOS)
			var u1 := lerpf(-1.0, 1.0, float(k + 1) / GOMOS)
			var p0 := Vector2(u0 * larg * 0.5, cy + alto * 0.5 + 0.25 + 1.5 * (1.0 - u0 * u0))
			var p1 := Vector2(u1 * larg * 0.5, cy + alto * 0.5 + 0.25 + 1.5 * (1.0 - u1 * u1))
			var m := (p0 + p1) * 0.5
			tabuas.append(Transform3D(b * Basis(Vector3.BACK, -atan2(p1.y - p0.y, p1.x - p0.x)) * Basis.from_scale(Vector3(p0.distance_to(p1) + 0.2, 0.7, 0.8)), pa(xp, m.x, piso_y + m.y)))
	for s: float in [-1.0, 1.0]:
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(0.4, alto + 0.3, 0.62)), pa(xp, s * (larg * 0.5 - 0.9), piso_y + cy)))
		ferro.append(Transform3D(b * Basis.from_scale(Vector3(1.6, 0.5, 1.2)), pa(xp, s * (larg * 0.5 - 0.6), piso_y + vao + 0.45)))
	if com_imagem:
		# Placa pintada (imagem do dono): um painel virado para dentro e outro para fora, na frente das pranchas
		var larg_i := larg + 3.0
		var alt_i := larg_i / float(placa[2])
		var mat_i := ShaderMaterial.new()
		mat_i.shader = load("res://shaders/placa_imagem.gdshader")
		mat_i.set_shader_parameter("imagem", placa[0])
		mat_i.set_shader_parameter("mascara", placa[1])
		var quadro := QuadMesh.new()
		quadro.size = Vector2(larg_i, alt_i)
		for par: Array in [[leitura, x - 2.78], [Basis.looking_at(-frente, Vector3.UP), x - 2.02]]:
			var mi_i := MeshInstance3D.new()
			mi_i.mesh = quadro
			mi_i.material_override = mat_i
			mi_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi_i.transform = Transform3D(par[0], pa(float(par[1]), 0.0, piso_y + vao - 0.4 + alt_i * 0.5))
			add_child(mi_i)
	else:
		# Marcas de garra por cima do nome
		for k in 3:
			ferro.append(Transform3D(leitura * Basis(Vector3.BACK, -0.62) * Basis.from_scale(Vector3(0.2, 1.7 - 0.25 * k, 0.1)), pa(x - 2.68, -0.6 + 0.55 * k, piso_y + cy + alto * 0.5 - 0.55 - 0.12 * k)))
		# Medalhão: disco de madeira clara com aro escuro e a silhueta do tiranossauro
		var raio := 3.5
		var c_med := pa(x - 2.1, 0.0, piso_y + cy + alto * 0.5 + 2.7)
		for par: Array in [[raio + 0.4, 0.5, 0.0, Color(0.1, 0.07, 0.045), 0.0], [raio, 0.5, -0.12, Color(0.78, 0.5, 0.2), 0.35]]:
			var disco := CylinderMesh.new()
			disco.top_radius = float(par[0])
			disco.bottom_radius = float(par[0])
			disco.height = float(par[1])
			disco.radial_segments = 40
			var mi_d := MeshInstance3D.new()
			mi_d.mesh = disco
			var mat_d := StandardMaterial3D.new()
			mat_d.albedo_color = par[3]
			mat_d.roughness = 0.9
			mat_d.emission_enabled = float(par[4]) > 0.0
			mat_d.emission = par[3]
			mat_d.emission_energy_multiplier = float(par[4])
			mi_d.material_override = mat_d
			mi_d.transform = Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), c_med + frente * float(par[2]))
			add_child(mi_d)
		var rex := DinosParque.criar("tiranossauro", 6.0)
		var escuro := StandardMaterial3D.new()
		escuro.albedo_color = Color(0.07, 0.045, 0.03)
		escuro.roughness = 1.0
		var pilha: Array[Node] = [rex.raiz]
		while not pilha.is_empty():
			var n: Node = pilha.pop_back()
			if n is MeshInstance3D:
				(n as MeshInstance3D).material_override = escuro
				(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			pilha.append_array(n.get_children())
		add_child(rex.raiz)
		(rex.raiz as Node3D).transform = Transform3D(Basis.looking_at(lat_d, Vector3.UP) * Basis.from_scale(Vector3(0.05, 1.0, 1.0)), c_med - frente * 0.42 + Vector3.DOWN * 1.0)
		# Nome em duas linhas (a última palavra embaixo), letras "de madeira" com espessura, acesas pelo fogo
		if nome_placa != "":
			var fonte := SystemFont.new()
			fonte.font_names = PackedStringArray(["Rockwell Extra Bold", "Rockwell", "Impact", "Arial Black"])
			fonte.font_weight = 900
			var corte := nome_placa.rfind(" ")
			var linhas: Array = [nome_placa, ""] if corte < 0 else [nome_placa.substr(0, corte), nome_placa.substr(corte + 1)]
			var alt_l: Array[float] = [2.3, 1.9]
			var y_l: Array[float] = [cy + 1.05, cy - 1.45]
			if corte < 0:
				y_l[0] = cy
			for j in 2:
				var txt := str(linhas[j])
				if txt == "":
					continue
				var px := minf(alt_l[j] / 150.0, larg * 0.84 / (txt.length() * 190.0 * 0.72))
				for k in 5:
					var l := Label3D.new()
					l.text = txt
					l.font = fonte
					l.font_size = 190
					l.pixel_size = px
					l.outline_size = 28
					l.shaded = false
					l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
					l.modulate = Color(1.7, 0.95, 0.42) if k == 0 else Color(0.5, 0.22, 0.05)
					l.outline_modulate = Color(0.55, 0.2, 0.03) if k == 0 else Color(0.2, 0.08, 0.02)
					l.transform = Transform3D(leitura, pa(x - 2.95 + 0.055 * k, 0.0, piso_y + y_l[j]))
					add_child(l)
				# Lascas de madeira dos dois lados da linha de baixo
				if j == 1:
					var meia_t := txt.length() * 190.0 * 0.72 * px * 0.5
					for s: float in [-1.0, 1.0]:
						var comp_l := maxf(larg * 0.5 - meia_t - 2.6, 1.0)
						tabuas.append(Transform3D(leitura * Basis(Vector3.BACK, 0.07 * s) * Basis.from_scale(Vector3(comp_l, 0.3, 0.14)), pa(x - 2.7, s * (meia_t + 0.8 + comp_l * 0.5), piso_y + y_l[j] - 0.1)))
	# Portões de madeira abertos para fora, com travessas e dobradiças de ferro
	var folha := minf(saida_largura * 0.5, 7.5)
	var alt_f := vao - 0.3
	for s: float in [-1.0, 1.0]:
		var dir := (frente * cos(0.2) + lat_d * s * sin(0.2)).normalized()
		var bf := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
		var eixo := pa(x + 2.4, 0.0, piso_y) + lat_d * s * (saida_largura * 0.5 + 0.25)
		const TABUAS := 6
		for k in TABUAS:
			var lt := folha / TABUAS
			tabuas.append(Transform3D(bf * Basis.from_scale(Vector3(lt - 0.06, alt_f - 0.35 * fmod(k * 0.61, 1.0), 0.3)), eixo + dir * (lt * (k + 0.5)) + Vector3.UP * (alt_f * 0.5)))
		for fy: float in [0.16, 0.5, 0.84]:
			ferro.append(Transform3D(bf * Basis.from_scale(Vector3(folha + 0.1, 0.32, 0.4)), eixo + dir * (folha * 0.5) + Vector3.UP * (alt_f * fy)))
			for k in int(folha / 0.9):
				rebites.append(Transform3D(bf * Basis.from_scale(Vector3(0.16, 0.16, 0.52)), eixo + dir * (0.5 + k * 0.9) + Vector3.UP * (alt_f * fy)))
		tabuas.append(Transform3D(bf * Basis(Vector3.BACK, atan2(alt_f * 0.34, folha) * s) * Basis.from_scale(Vector3(Vector2(folha, alt_f * 0.34).length(), 0.3, 0.36)), eixo + dir * (folha * 0.5) + Vector3.UP * (alt_f * 0.33)))
	ComplexoLancamento.criar_multimesh(self, pedra, pedra_m)
	ComplexoLancamento.criar_multimesh(self, tabuas, madeira)
	ComplexoLancamento.criar_multimesh(self, ferro, ferro_m)
	ComplexoLancamento.criar_multimesh(self, rebites, ComplexoLancamento._material_metal(Color(0.42, 0.27, 0.14), 0.9, 0.45))
	ComplexoLancamento.adicionar_colisoes(corpo, colisao)
	# Presas de osso penduradas embaixo da viga, dos pilares para o meio (o meio fica livre para o semáforo)
	var presa := CylinderMesh.new()
	presa.top_radius = 0.26
	presa.bottom_radius = 0.0
	presa.height = 1.0
	presa.radial_segments = 7
	presa.rings = 1
	var mm_p := MultiMesh.new()
	mm_p.transform_format = MultiMesh.TRANSFORM_3D
	mm_p.mesh = presa
	mm_p.instance_count = 12
	for k in 12:
		var s_p := -1.0 if k % 2 == 0 else 1.0
		var comp_p := 1.5 - 0.17 * float(k / 2)
		mm_p.set_instance_transform(k, Transform3D(Basis(Vector3.BACK, 0.12 * s_p) * Basis.from_scale(Vector3(1.0, comp_p, 1.0)), pa(xp, s_p * (larg * 0.5 - 2.0 - 0.95 * float(k / 2)), piso_y + vao - comp_p * 0.5)))
	var mmi_p := MultiMeshInstance3D.new()
	mmi_p.multimesh = mm_p
	var osso := StandardMaterial3D.new()
	osso.albedo_color = Color(0.86, 0.8, 0.64)
	osso.roughness = 0.7
	mmi_p.material_override = osso
	add_child(mmi_p)
	# Cipós: pendurados da viga (perto dos pilares, o meio fica livre para o semáforo) e das cabeças dos pilares
	var talos: Array[Transform3D] = []
	var folhas: Array[Transform3D] = []
	var pontos: Array = []
	for k in 16:
		var s := -1.0 if k % 2 == 0 else 1.0
		pontos.append([pa(xp - 0.6, s * rng.randf_range(larg * 0.24, larg * 0.5 - 2.4), piso_y + vao), rng.randf_range(0.8, 3.2)])
	for k in 14:
		var s := -1.0 if k % 2 == 0 else 1.0
		pontos.append([pa(x - 2.2, s * (g + rng.randf_range(-2.0, 2.0)), piso_y + alt_p + 0.1), rng.randf_range(1.5, 5.0)])
		pontos.append([pa(x - 2.75, s * rng.randf_range(larg * 0.2, larg * 0.5), piso_y + cy + alto * 0.5 + 0.2), rng.randf_range(0.6, 2.0)])
	for pt: Array in pontos:
		var topo_c: Vector3 = pt[0]
		var comp_c: float = pt[1]
		talos.append(Transform3D(Basis.from_scale(Vector3(0.07, comp_c, 0.07)), topo_c + Vector3.DOWN * comp_c * 0.5))
		for k in int(comp_c * 3.0) + 2:
			var giro := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.7, 0.7))
			folhas.append(Transform3D(giro * Basis.from_scale(Vector3(rng.randf_range(0.35, 0.6), 0.04, rng.randf_range(0.25, 0.4))), topo_c + Vector3.DOWN * rng.randf_range(0.0, comp_c) + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))))
	var verde := StandardMaterial3D.new()
	verde.albedo_color = Color(0.13, 0.3, 0.09)
	verde.roughness = 1.0
	var verde_talo := StandardMaterial3D.new()
	verde_talo.albedo_color = Color(0.09, 0.15, 0.06)
	verde_talo.roughness = 1.0
	ComplexoLancamento.criar_multimesh(self, talos, verde_talo, false)
	ComplexoLancamento.criar_multimesh(self, folhas, verde, false)
	# Semáforo numa caixa de madeira pendurada embaixo da viga, virado para dentro
	var para_dentro := Basis.looking_at(-frente, Vector3.UP)
	var caixa := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(7.6, 2.1, 0.7)
	caixa.mesh = cm
	caixa.material_override = madeira
	caixa.transform = Transform3D(para_dentro, pa(x - 2.4, 0.0, piso_y + vao - 1.05))
	add_child(caixa)
	var lampada := CylinderMesh.new()
	lampada.top_radius = 0.75
	lampada.bottom_radius = 0.75
	lampada.height = 0.25
	lampada.radial_segments = 24
	for k in 3:
		var l := MeshInstance3D.new()
		l.mesh = lampada
		l.transform = Transform3D(para_dentro * Basis(Vector3.RIGHT, PI * 0.5), pa(x - 2.82, (k - 1) * 2.3, piso_y + vao - 1.05))
		add_child(l)
		semaforo_lampadas.append(l)


## Imagem RGBA de um arquivo do projeto; lê o arquivo direto se o motor ainda não o importou. null se não há.
static func ler_imagem(caminho: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(caminho):
		var tex := load(caminho) as Texture2D
		if tex:
			img = tex.get_image()
	if img == null:
		var arq := ProjectSettings.globalize_path(caminho)
		if not FileAccess.file_exists(arq):
			return null
		img = Image.load_from_file(arq)
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## Imagem da placa do pórtico (`placa_imagem`): [textura, máscara, largura / altura], ou vazio se não há
## arquivo. Sem transparência no arquivo, o fundo escuro em volta do desenho é recortado: preenchimento a
## partir das bordas pelos pixels escuros, numa cópia pequena (a máscara).
func _textura_placa() -> Array:
	if placa_imagem == "":
		return []
	var img := ler_imagem(placa_imagem)
	if img == null:
		return []
	var razao := float(img.get_width()) / float(img.get_height())
	var w := 280
	var h := maxi(int(round(w / razao)), 8)
	var peq: Image = img.duplicate()
	peq.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var fora := PackedByteArray()
	fora.resize(w * h)
	var escuro := PackedByteArray()
	escuro.resize(w * h)
	for y in h:
		for xq in w:
			var c := peq.get_pixel(xq, y)
			escuro[y * w + xq] = 1 if c.a < 0.5 or c.get_luminance() < 0.085 else 0
	var pilha: Array[int] = []
	for xq in w:
		pilha.append(xq)
		pilha.append((h - 1) * w + xq)
	for y in h:
		pilha.append(y * w)
		pilha.append(y * w + w - 1)
	while not pilha.is_empty():
		var k: int = pilha.pop_back()
		if fora[k] == 1 or escuro[k] == 0:
			continue
		fora[k] = 1
		var kx := k % w
		if kx > 0:
			pilha.append(k - 1)
		if kx < w - 1:
			pilha.append(k + 1)
		if k >= w:
			pilha.append(k - w)
		if k < w * (h - 1):
			pilha.append(k + w)
	var masc := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for xq in w:
			masc.set_pixel(xq, y, Color.BLACK if fora[y * w + xq] == 1 else Color.WHITE)
	img.generate_mipmaps()
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(masc), razao]


## Portão da saída: torres de pedra com LED, placa com o nome e semáforo virado para dentro.
func _montar_portao() -> void:
	if tema == "dino":
		_montar_portao_dino()
		return
	if tema == "gelo":
		preload("res://scripts/mundo/portao_gelo.gd").montar(self)   # portal de cristal com o nome em letras de gelo (arte do dono)
		return
	var g := saida_largura * 0.5 + 1.6
	var altura := muro_altura + grade_altura + 4.0
	var b := Basis.looking_at(frente, Vector3.UP)
	var x := comprimento + PAREDE * 0.5
	var pedra: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(3.2, altura, 3.2)), pa(x, g * s, piso_y + altura * 0.5)))
		ComplexoLancamento.criar_multimesh(self, [Transform3D(b * Basis.from_scale(Vector3(0.12, altura - 2.0, 0.12)), pa(x - 1.62, (g - 1.62) * s, piso_y + altura * 0.5))], ComplexoLancamento._material_luz(_cor_luz(), 5.0), false)
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


func _cor_luz() -> Color:
	if tema == "selva":
		return Color(0.3, 1.0, 0.65)   # jade
	if tema == "gelo":
		return Color(0.3, 0.85, 1.0)   # azul-gelo
	return Color(1.0, 0.68, 0.22) if tema == "egito" else COR_EVENTO
