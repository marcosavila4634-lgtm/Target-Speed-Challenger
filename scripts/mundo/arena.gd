class_name ComplexoArena
extends ComplexoLancamento
## Canyon Combat Target: plataforma de largada CONJUNTA. Todas as equipes largam juntas de vagas
## junto às paredes de uma arena cercada (muro de pedra com grade de ferro) no alto de um pedestal
## de alvenaria. No piso há buracos da morte (cair = explodir) onde os rivais tentam derrubar uns
## aos outros, e pontos de aceleração (setas) que dão um tranco violento: uns ajudam a chegar
## ao portão, outros apontam para buracos (armadilhas para empurrar rivais). A única saída é o
## portão de 2 carros de largura, que dá direto na descida e na rampa. Fogo no fundo dos buracos
## e nos braseiros da cerca (pedra, grade de ferro e pontas enferrujadas).
##
## Coordenadas locais da arena: x = distância desde o muro do fundo (0) até o portão (comprimento),
## lateral = + à direita de quem sai. A pista (perfil) começa no portão.

const PAREDE := 1.0          # espessura do muro de pedra da cerca
const CELULA := 2.0          # grade de navegação dos bots (m)
const COR_EVENTO := Color(1.0, 0.45, 0.08)

var comprimento := 110.0
var largura_arena := 120.0
var saida_largura := 18.0
var muro_altura := 1.3
var grade_altura := 2.4
var buracos: Array = []      # [Vector2(x, lateral), raio]
var vagas_cfg: Array = []    # [x, lateral, graus]
var impulsos: Array = []     # [Vector2(x, lateral), ângulo (rad), segura]
var piso_y := 400.0
var chao_y := 370.0          # terreno em volta do pedestal
var _terreno: Terreno
var _leds_vagas: Array[StandardMaterial3D] = []

# Navegação: distância (custo) de cada célula até o fim do corredor de saída
var _nav_nx := 0
var _nav_nl := 0
var _nav_x_max := 0.0
var _nav := PackedFloat32Array()


func _identidade() -> void:
	cor = COR_EVENTO
	var a: Array = Config.valor("arena.direcao", [0, -1])
	var d := Vector2(float(a[0]), float(a[1])).normalized()
	direcao = Vector3(d.x, 0.0, d.y)
	name = "Arena"
	comprimento = float(Config.valor("arena.comprimento", 110))
	largura_arena = float(Config.valor("arena.largura", 120))
	saida_largura = float(Config.valor("arena.saida_largura", 18))
	muro_altura = float(Config.valor("arena.muro_altura", 1.3))
	grade_altura = float(Config.valor("arena.grade_altura", 2.4))
	buracos.clear()
	for b in Config.valor("arena.buracos", []):
		buracos.append([Vector2(float(b[0]), float(b[1])), float(b[2])])
	vagas_cfg = Config.valor("arena.vagas", [])
	impulsos.clear()
	for i in Config.valor("arena.impulsos", []):
		impulsos.append([Vector2(float(i[0]), float(i[1])), deg_to_rad(float(i[2])), bool(i[3]) if i.size() > 3 else true])
	impulso_velocidade = float(Config.valor("arena.impulso_velocidade", 25))
	x_inicio_pista = comprimento
	# Túnel do portão até o meio da descida: sem pular a rampa com o ejetor
	tunel_ini = comprimento
	var fracao := clampf(float(Config.valor("arena.tunel_fracao_descida", 0.5)), 0.0, 1.0)
	var i_fim := int(round(lerpf(perfil.indice_borda, perfil.indice_base, fracao)))
	tunel_fim = perfil.pontos[i_fim].x
	linha_largada = -1000.0


func texto_portico() -> String:
	return Config.nome_mapa().to_upper()


# ------------------------------------------------------------------ coordenadas

## Ponto do mundo a partir de coordenadas da arena.
func pa(x: float, lat: float, y: float) -> Vector3:
	return ponto(x, y) + lateral * lat


## Coordenadas da arena (x, lateral) de um ponto do mundo.
func local(p: Vector3) -> Vector2:
	var x := x_perfil(p)
	return Vector2(x, (p - ponto(x, p.y)).dot(lateral))


## Direção do mundo a partir de um ângulo da arena (0 = para o portão, 90° = para a direita).
func dir_mundo(angulo: float) -> Vector3:
	return frente * cos(angulo) + lateral * sin(angulo)


func dentro_da_arena(p: Vector3) -> bool:
	var l := local(p)
	return l.x > -3.0 and l.x < comprimento + 1.0 and absf(l.y) < largura_arena * 0.5 + 3.0


## Cair num buraco (ou abaixo do piso dentro do pedestal) elimina.
func buraco_mortal(p: Vector3) -> bool:
	if p.y > piso_y - 1.2 or not dentro_da_arena(p):
		return false
	var l := local(p)
	for b in buracos:
		if l.distance_to(b[0]) < b[1] + 0.6:
			return true
	return p.y < piso_y - 6.0


const IMPULSO_MEIO := Vector2(3.5, 2.0)   # meio comprimento e meia largura da seta


## Ponto de aceleração sob `p`: direção do tranco no mundo, ou zero.
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


## Perigo mais perto (buraco ou seta-armadilha) para empurrar um rival: {centro, distancia}.
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


## Buraco mais perto de um ponto: {centro (mundo, na altura do piso), raio, distancia (até a boca)}.
func buraco_mais_perto(p: Vector3) -> Dictionary:
	var l := local(p)
	var melhor := {}
	for b in buracos:
		var d: float = l.distance_to(b[0]) - float(b[1])
		if melhor.is_empty() or d < melhor.distancia:
			melhor = {"centro": pa(b[0].x, b[0].y, piso_y), "raio": b[1], "distancia": d}
	return melhor


# ------------------------------------------------------------------ montagem

## Na arena, a "plataforma" é a arena inteira: piso com buracos, pedestal, cerca, portão,
## o bloco sob o corredor até a borda e o balanço sobre o precipício.
func _montar_plataforma(terreno: Terreno) -> void:
	_terreno = terreno
	piso_y = perfil.pontos[0].y
	chao_y = piso_y - float(Config.valor("mapa.rebaixo_mesa", 30))
	_montar_piso()
	_montar_pedestal()
	_montar_cerca()
	_montar_buracos()
	_montar_impulsos()
	_montar_vagas()
	_montar_nav()

	# Bloco sob o corredor de saída (do portão até perto da borda) e balanço sobre o paredão
	var x_borda := perfil.pontos[perfil.indice_borda].x
	var x_fim := x_borda - RECUO_MESA
	var b := Basis.looking_at(frente, Vector3.UP)
	var alto := piso_y - ESPESSURA
	var comp := x_fim - comprimento
	var centro := ponto((comprimento + x_fim) * 0.5, (alto + chao_y - 2.0) * 0.5)
	var bloco := Transform3D(b * Basis.from_scale(Vector3(largura + 2.0, alto - chao_y + 2.0, comp)), centro)
	criar_multimesh(self, [bloco], _material_pedra())
	adicionar_colisoes(_estruturas, [bloco])
	var aco: Array[Transform3D] = []
	_montar_balanco(aco, x_fim, x_borda)
	criar_multimesh(self, aco, material_aco(chao_y))


## Muretas da rampa e túnel de pedra, como a cerca.
func material_muro() -> Material:
	return _material_pedra()


## Sem pórtico sobre a pista: o túnel cobre a saída e o semáforo fica no portão da arena.
func _montar_portico() -> void:
	_semaforo.clear()


## A cerca da arena faz o papel do muro de trás.
func _montar_muro() -> void:
	pass


func _material_pedra() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/muro_pedra.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 71))
	m.set_shader_parameter("altura_chao", chao_y)
	return m


## Piso: malha triangulada com os buracos recortados (colisão com a mesma malha).
func _montar_piso() -> void:
	var meia := largura_arena * 0.5 + PAREDE
	var x0 := -PAREDE
	var x1 := comprimento
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
		var n := 56
		for k in n:
			pts.append(b[0] + Vector2(cos(TAU * k / n), sin(TAU * k / n)) * float(b[1]))
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
		# Mesma ordem de vértices em todos os triângulos (senão metade fica com a face virada)
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
	var arr_b := PackedVector3Array()
	for k in 12:
		arr_b.append(Vector3(buracos[k][0].x, buracos[k][0].y, buracos[k][1]) if k < buracos.size() else Vector3.ZERO)
	mat.set_shader_parameter("buracos", arr_b)
	var arr_v := PackedVector3Array()
	for k in 16:
		if k < vagas_cfg.size():
			arr_v.append(Vector3(float(vagas_cfg[k][0]), float(vagas_cfg[k][1]), deg_to_rad(float(vagas_cfg[k][2]))))
		else:
			arr_v.append(Vector3(-1000.0, 0.0, 0.0))
	mat.set_shader_parameter("vagas", arr_v)
	var mi := MeshInstance3D.new()
	mi.name = "PisoArena"
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

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


## Pedestal de alvenaria sob a arena: paredões de pedra com contrafortes e cornija de aço.
## Por dentro é oco (os buracos atravessam até o fundo).
func _montar_pedestal() -> void:
	var b := Basis.looking_at(frente, Vector3.UP)   # X = lateral, -Z = frente
	var meia := largura_arena * 0.5 + PAREDE
	var topo := piso_y - 0.05
	var fundo := chao_y - 3.0
	var alt := topo - fundo
	var ym := (topo + fundo) * 0.5
	var pedra: Array[Transform3D] = []
	var esp := 2.0
	# Fundo, laterais e frente (a frente tem o vão do corredor)
	pedra.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + esp * 2.0, alt, esp)), pa(-PAREDE - esp * 0.5, 0.0, ym)))
	for s: float in [-1.0, 1.0]:
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(esp, alt, comprimento + PAREDE + esp)), pa((comprimento - PAREDE - esp) * 0.5, (meia + esp * 0.5) * s, ym)))
		var l0 := largura * 0.5 + 1.0
		var l1 := meia + esp
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(l1 - l0, alt, esp)), pa(comprimento - esp * 0.5, (l0 + l1) * 0.5 * s, ym)))
	# Contrafortes a cada ~12 m nas faces de fora
	var contrafortes: Array[Transform3D] = []
	var n := int(comprimento / 12.0)
	for k in n + 1:
		var x := lerpf(4.0, comprimento - 4.0, float(k) / n)
		for s: float in [-1.0, 1.0]:
			contrafortes.append(Transform3D(b * Basis.from_scale(Vector3(2.4, alt - 1.5, 2.2)), pa(x, (meia + esp + 1.2) * s, ym - 0.75)))
	var nf := int(largura_arena / 12.0)
	for k in nf + 1:
		var lat := lerpf(-meia + 4.0, meia - 4.0, float(k) / nf)
		contrafortes.append(Transform3D(b * Basis.from_scale(Vector3(2.2, alt - 1.5, 2.4)), pa(-PAREDE - esp - 1.2, lat, ym - 0.75)))
	criar_multimesh(self, pedra, _material_pedra())
	criar_multimesh(self, contrafortes, _material_pedra())
	adicionar_colisoes(_estruturas, pedra)
	# Cornija de aço com faixa de LED laranja logo abaixo do piso, em volta do pedestal
	var aco: Array[Transform3D] = []
	var led: Array[Transform3D] = []
	var y_c := piso_y - 0.8
	aco.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + esp * 2.0 + 1.0, 1.2, 0.5)), pa(-PAREDE - esp - 0.25, 0.0, y_c)))
	led.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + esp * 2.0, 0.14, 0.1)), pa(-PAREDE - esp - 0.55, 0.0, y_c - 0.9)))
	for s: float in [-1.0, 1.0]:
		aco.append(Transform3D(b * Basis.from_scale(Vector3(0.5, 1.2, comprimento + PAREDE + esp * 2.0 + 0.5)), pa((comprimento - PAREDE - esp) * 0.5, (meia + esp + 0.25) * s, y_c)))
		led.append(Transform3D(b * Basis.from_scale(Vector3(0.1, 0.14, comprimento + PAREDE + esp)), pa((comprimento - PAREDE - esp) * 0.5, (meia + esp + 0.55) * s, y_c - 0.9)))
	criar_multimesh(self, aco, material_aco(chao_y, 0.5))
	criar_multimesh(self, led, _material_luz(COR_EVENTO, 3.0), false)


## Cerca: muro baixo de pedra com capa, pilares de pedra e grade de ferro. Assustadora: pontas de
## ferro enferrujado na grade, pontas tortas viradas para dentro cravadas na capa entre pedras
## brutas, pontas grandes nos pilares e braseiros com fogo. Contorna a arena, menos o portão.
func _montar_cerca() -> void:
	var meia := largura_arena * 0.5 + PAREDE * 0.5
	var xf := -PAREDE * 0.5
	var xp := comprimento + PAREDE * 0.5
	var g := saida_largura * 0.5 + 1.6   # metade do vão do portão, contando as torres
	var trechos := [
		[Vector2(xf, -meia), Vector2(xf, meia)],
		[Vector2(xf, -meia), Vector2(xp, -meia)],
		[Vector2(xf, meia), Vector2(xp, meia)],
		[Vector2(xp, -meia), Vector2(xp, -g)],
		[Vector2(xp, g), Vector2(xp, meia)],
	]
	var pedra: Array[Transform3D] = []
	var capa: Array[Transform3D] = []
	var ferro: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var pontas: Array[Transform3D] = []
	var pedras: Array[Transform3D] = []
	var braseiros: Array[Vector3] = []
	var chapas: Array[Transform3D] = []
	var chapas_pintadas: Array[Transform3D] = []
	var altura_total := muro_altura + grade_altura
	for t: Array in trechos:
		var a: Vector2 = t[0]
		var c: Vector2 = t[1]
		var d := c - a
		var comp := d.length()
		var eixo := (frente * d.x + lateral * d.y).normalized()
		var bb := Basis.looking_at(eixo, Vector3.UP)   # -Z ao longo do trecho, X = espessura
		var meio := (a + c) * 0.5
		pedra.append(Transform3D(bb * Basis.from_scale(Vector3(PAREDE, muro_altura, comp)), pa(meio.x, meio.y, piso_y + muro_altura * 0.5)))
		capa.append(Transform3D(bb * Basis.from_scale(Vector3(PAREDE + 0.25, 0.16, comp)), pa(meio.x, meio.y, piso_y + muro_altura + 0.08)))
		colisao.append(Transform3D(bb * Basis.from_scale(Vector3(PAREDE, altura_total, comp)), pa(meio.x, meio.y, piso_y + altura_total * 0.5)))
		# Pilares a cada ~7 m e grade entre eles
		var n := maxi(int(round(comp / 7.0)), 1)
		for k in n + 1:
			var q := a + d * (float(k) / n)
			pedra.append(Transform3D(bb * Basis.from_scale(Vector3(1.4, altura_total + 0.3, 1.4)), pa(q.x, q.y, piso_y + (altura_total + 0.3) * 0.5)))
			capa.append(Transform3D(bb * Basis.from_scale(Vector3(1.7, 0.25, 1.7)), pa(q.x, q.y, piso_y + altura_total + 0.42)))
		var y0 := piso_y + muro_altura + 0.16
		for trilho: float in [0.15, grade_altura * 0.36, grade_altura * 0.68, grade_altura - 0.35]:
			ferro.append(Transform3D(bb * Basis.from_scale(Vector3(0.1, 0.14, comp)), pa(meio.x, meio.y, y0 + trilho)))
		# Remendos de chapa de ferro-velho presos na grade (estilo Mad Max), uns pintados, outros só ferrugem
		var nc := int(comp / 2.2)
		for k in nc:
			var h1 := fmod(k * 0.6180 + meio.x * 0.013 + meio.y * 0.029, 1.0)
			var h2 := fmod(k * 0.7549 + h1 * 3.1, 1.0)
			if h1 < 0.3:
				continue
			var q := a + d * ((k + 0.5) / nc)
			var wc := 1.4 + 1.3 * h2
			var hc := 1.2 + 2.2 * fmod(h1 * 7.3, 1.0)
			var yc := y0 + hc * 0.5 + (grade_altura - hc) * fmod(h2 * 5.7, 1.0)
			var giro := Basis(Vector3(1, 0, 0), (h2 - 0.5) * 0.35)   # torto no plano da grade
			var t_ch := Transform3D(bb * giro * Basis.from_scale(Vector3(0.05, hc, wc)), pa(q.x, q.y, yc) + (pa(comprimento * 0.5, 0.0, 0.0) - pa(meio.x, meio.y, 0.0)).normalized() * (0.09 if k % 2 == 0 else -0.09))
			if h2 < 0.35:
				chapas_pintadas.append(t_ch)
			else:
				chapas.append(t_ch)
		var barras := int(comp / 0.24)
		for k in barras:
			var q := a + d * ((k + 0.5) / barras)
			ferro.append(Transform3D(bb * Basis.from_scale(Vector3(0.06, grade_altura, 0.06)), pa(q.x, q.y, y0 + grade_altura * 0.5)))
			# Ponta de ferro enferrujada em cima de cada barra
			var alt_p := 0.35 + 0.2 * fmod(k * 0.618, 1.0)
			pontas.append(Transform3D(Basis.from_scale(Vector3(0.9, alt_p, 0.9)), pa(q.x, q.y, y0 + grade_altura + alt_p * 0.5)))
		# Pontas tortas viradas para dentro da arena, cravadas na capa do muro
		var dentro := (pa(comprimento * 0.5, 0.0, 0.0) - pa(meio.x, meio.y, 0.0)).normalized()
		var ne := int(comp / 0.55)
		for k in ne:
			var q := a + d * ((k + 0.5) / ne)
			var inclina := 0.55 + 0.25 * fmod(k * 0.377, 1.0)
			var eixo_p := (Vector3.UP * cos(inclina) + dentro * sin(inclina)).normalized()
			var comp_p := 0.7 + 0.5 * fmod(k * 0.713, 1.0)
			var base_p := pa(q.x, q.y, piso_y + muro_altura + 0.12) + dentro * (PAREDE * 0.4)
			pontas.append(Transform3D(_base_eixo(eixo_p) * Basis.from_scale(Vector3(1.3, comp_p, 1.3)), base_p + eixo_p * comp_p * 0.5))
			# Pedras brutas encaixadas na capa, entre as pontas
			if k % 3 == 1:
				var e := 0.3 + 0.25 * fmod(k * 0.531, 1.0)
				pedras.append(Transform3D(Basis(Vector3.UP, k * 1.7) * Basis.from_scale(Vector3(e * 1.4, e, e * 1.1)), pa(q.x, q.y, piso_y + muro_altura + 0.1) - dentro * 0.1))
		# Pilares: três pontas grandes e, a cada três, um braseiro com fogo
		for k in n + 1:
			var q := a + d * (float(k) / n)
			var topo := pa(q.x, q.y, piso_y + altura_total + 0.55)
			if k % 3 == 1:
				braseiros.append(topo)
				continue
			pontas.append(Transform3D(Basis.from_scale(Vector3(2.2, 1.3, 2.2)), topo + Vector3.UP * 0.65))
			for s: float in [-1.0, 1.0]:
				var ei := (Vector3.UP + eixo * 0.6 * s).normalized()
				pontas.append(Transform3D(_base_eixo(ei) * Basis.from_scale(Vector3(1.5, 0.85, 1.5)), topo + ei * 0.43))
	criar_multimesh(self, pedra, _material_pedra())
	var mat_capa := _material_pedra()
	mat_capa.set_shader_parameter("cor_pedra", Color(0.7, 0.58, 0.47))
	criar_multimesh(self, capa, mat_capa)
	criar_multimesh(self, ferro, _material_metal(Color(0.07, 0.065, 0.06), 0.85, 0.55))
	adicionar_colisoes(_estruturas, colisao)
	criar_multimesh(self, chapas, ferro_velho(Color(0.2, 0.16, 0.12), 0.9))
	criar_multimesh(self, chapas_pintadas, ferro_velho(Color(0.55, 0.42, 0.1), 0.6))
	var ferrugem := material_aco(piso_y, 0.95)
	ferrugem.set_shader_parameter("cor_tinta", Color(0.16, 0.1, 0.07))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.05
	cone.height = 1.0
	cone.radial_segments = 5
	cone.rings = 1
	_instancias(cone, pontas, ferrugem)
	var rocha := SphereMesh.new()
	rocha.radial_segments = 6
	rocha.rings = 3
	rocha.radius = 0.5
	rocha.height = 1.0
	_instancias(rocha, pedras, _material_pedra())
	# Braseiros: cesto de ferro no alto do pilar com fogo; luz em alguns (pesa pouco)
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


## Base com o Y apontando para `eixo` (para pontas e cones instanciados).
static func _base_eixo(eixo: Vector3) -> Basis:
	var ref := Vector3.RIGHT if absf(eixo.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(eixo).normalized()
	return Basis(x, eixo, x.cross(eixo).normalized())


func _instancias(malha: Mesh, transformacoes: Array[Transform3D], mat: Material, sombra := true) -> void:
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
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Buracos da morte: poço de pedra até o fundo do pedestal, fogo alto no fundo (labaredas e
## fagulhas subindo pelo poço), brasa e luz vermelha.
func _montar_buracos() -> void:
	var fundo := chao_y - 1.0
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
		poco.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = poco
		mi.material_override = _material_pedra()
		mi.position = Vector3(c.x, (piso_y + fundo) * 0.5, c.z)
		add_child(mi)
		var brasa := CylinderMesh.new()
		brasa.top_radius = r
		brasa.bottom_radius = r
		brasa.height = 0.4
		brasa.radial_segments = 40
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
		luz.light_energy = 14.0
		luz.omni_range = piso_y - fundo + 8.0
		luz.shadow_enabled = false
		luz.position = Vector3(c.x, fundo + 12.0, c.z)
		add_child(luz)
		# Labaredas grandes no fundo e um fogo mais baixo que lambe as paredes até perto da boca
		Fogo.criar(self, Vector3(c.x, fundo + 0.5, c.z), r * 0.75, 20.0, 110, r * 1.1)
		Fogo.criar(self, Vector3(c.x, fundo + 12.0, c.z), r * 0.8, 16.0, 60, r * 0.8, false)


## Portão: duas torres de pedra com LED, viga de aço com o nome da fase e semáforo virado
## para dentro da arena (acende junto com o do pórtico da descida).
func _montar_portao() -> void:
	var g := saida_largura * 0.5 + 1.6
	var altura := muro_altura + grade_altura + 4.0   # torres passam do alto da cerca
	var pedra: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var b := Basis.looking_at(frente, Vector3.UP)
	var x := comprimento + PAREDE * 0.5
	for s: float in [-1.0, 1.0]:
		var t := Transform3D(b * Basis.from_scale(Vector3(3.2, altura, 3.2)), pa(x, g * s, piso_y + altura * 0.5))
		pedra.append(t)
		colisao.append(t)
		pedra.append(Transform3D(b * Basis.from_scale(Vector3(3.8, 0.5, 3.8)), pa(x, g * s, piso_y + altura + 0.25)))
		# Fita de LED na face interna das torres
		criar_multimesh(self, [Transform3D(b * Basis.from_scale(Vector3(0.12, altura - 2.0, 0.12)), pa(x - 1.62, (g - 1.62) * s, piso_y + altura * 0.5))], _material_luz(COR_EVENTO, 5.0), false)
	criar_multimesh(self, pedra, _material_pedra())
	var viga_a := pa(x, -g, piso_y + altura - 1.4)
	var viga_b := pa(x, g, piso_y + altura - 1.4)
	var trel := trelica(viga_a, viga_b, 1.4, 1.5, 0.2, 0.08)
	_multimesh(trel, _material_metal(Color(0.13, 0.135, 0.15), 0.8, 0.4))
	colisao.append(_viga(viga_a, viga_b, 1.4))
	adicionar_colisoes(_estruturas, colisao)

	# Placa com o nome, virada para dentro da arena
	var para_dentro := Basis.looking_at(-frente, Vector3.UP)
	var leitura := Basis.looking_at(frente, Vector3.UP)   # Label3D é lido pelo +Z: virado para dentro da arena
	var placa := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(g * 2.0 + 3.2, 2.4, 0.3)   # cobre as duas torres
	placa.mesh = bm
	placa.material_override = _material_metal(Color(0.03, 0.03, 0.035), 0.4, 0.5)
	placa.transform = Transform3D(para_dentro, pa(x - 2.0, 0.0, piso_y + altura + 0.2))
	add_child(placa)
	var texto := Label3D.new()
	texto.text = texto_portico()
	texto.font = Estilo.fonte_titulo(800)
	texto.font_size = 150
	texto.pixel_size = minf(0.009, bm.size.x * 0.92 / (texto.text.length() * 150.0 * 0.62))
	texto.outline_size = 20
	texto.modulate = Color(1.0, 0.62, 0.25)
	texto.transform = Transform3D(leitura, pa(x - 2.18, 0.0, piso_y + altura + 0.2))
	add_child(texto)
	var saida := Label3D.new()
	saida.text = "SAÍDA"
	saida.font = Estilo.fonte_titulo(800)
	saida.font_size = 110
	saida.pixel_size = 0.008
	saida.outline_size = 16
	saida.modulate = Color(0.95, 0.95, 0.9)
	saida.transform = Transform3D(leitura, pa(x - 2.18, 0.0, piso_y + altura - 1.4))
	add_child(saida)

	# Semáforo da arena (3 lâmpadas grandes, viradas para dentro)
	var caixa := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(7.6, 2.1, 0.7)
	caixa.mesh = cm
	caixa.material_override = _material_metal(Color(0.03, 0.03, 0.035), 0.3, 0.6)
	caixa.transform = Transform3D(para_dentro, pa(x - 2.2, 0.0, piso_y + altura - 3.6))
	add_child(caixa)
	var lampada := CylinderMesh.new()
	lampada.top_radius = 0.75
	lampada.bottom_radius = 0.75
	lampada.height = 0.25
	lampada.radial_segments = 24
	for k in 3:
		var l := MeshInstance3D.new()
		l.mesh = lampada
		l.transform = Transform3D(para_dentro * Basis(Vector3.RIGHT, PI * 0.5), pa(x - 2.62, (k - 1) * 2.3, piso_y + altura - 3.6))
		add_child(l)
		_semaforo.append(l)
	semaforo(0)


## Pontos de aceleração: placa rente ao piso com anéis pulsando (ciano = segura, vermelho = perto
## de buraco). O tranco vai para onde o carro aponta (Veiculo), a placa só diz onde é.
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
		var luz := OmniLight3D.new()
		luz.light_color = Color(0.2, 0.8, 1.0) if im[2] else Color(1.0, 0.2, 0.08)
		luz.light_energy = 1.5
		luz.omni_range = 7.0
		luz.shadow_enabled = false
		luz.position = pa(im[0].x, im[0].y, piso_y + 1.2)
		add_child(luz)


## Faixa de LED no chão, atrás de cada vaga: acende na cor da equipe de quem larga ali.
func _montar_vagas() -> void:
	for v in vagas_cfg:
		var a := deg_to_rad(float(v[2]))
		var f := dir_mundo(a)
		var lado := f.cross(Vector3.UP).normalized()
		var p := pa(float(v[0]), float(v[1]), piso_y + 0.03) - f * 3.15
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(3.0, 0.06, 0.22)
		mi.mesh = bm
		var mat := _material_luz(Color(0.2, 0.2, 0.2), 0.0)
		mi.material_override = mat
		mi.transform = Transform3D(Basis(lado, Vector3.UP, -f), p)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_leds_vagas.append(mat)


## Torres de holofotes nos quatro cantos, de pé no chão ao lado do pedestal, com a cabeça acima
## da cerca e mirando o centro da arena.
func _montar_decoracao(_terreno_: Terreno) -> void:
	_montar_portao()   # depois do pórtico: o semáforo do portão entra na mesma lista
	var aco: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var lampadas: Array[Transform3D] = []
	var meia := largura_arena * 0.5 + 8.0
	var centro := pa(comprimento * 0.5, 0.0, piso_y)
	for q: Vector2 in [Vector2(-8.0, -meia), Vector2(-8.0, meia), Vector2(comprimento - 6.0, -meia), Vector2(comprimento - 6.0, meia)]:
		var base := pa(q.x, q.y, 0.0)
		base.y = _terreno.altura_em(base.x, base.z) - 1.0
		var topo := Vector3(base.x, piso_y + 24.0, base.z)
		aco.append_array(trelica(base, topo, 2.2, 2.5, 0.28, 0.1))
		colisao.append(_viga(base, topo, 2.2))
		var mira := centro - topo
		var bh := Basis.looking_at(Vector3(mira.x, 0.0, mira.z).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -0.4)
		var cabeca := topo + Vector3.UP * 2.0
		aco.append(Transform3D(bh * Basis.from_scale(Vector3(7.0, 4.4, 0.5)), cabeca + bh.z * 0.35))
		aco.append(_viga(topo, cabeca + bh.z * 0.6, 0.5))
		for i in 3:
			for j in 2:
				lampadas.append(Transform3D(bh * Basis.from_scale(Vector3(1.8, 1.6, 0.25)), cabeca + bh.x * (i - 1) * 2.2 + bh.y * (j - 0.5) * 2.0 - bh.z * 0.05))
		var luz := SpotLight3D.new()
		luz.light_color = Color(1.0, 0.9, 0.75)
		luz.light_energy = 4.0
		luz.spot_range = 160.0
		luz.spot_angle = 35.0
		luz.shadow_enabled = false
		add_child(luz)
		luz.global_transform = Transform3D(Basis.looking_at(mira.normalized(), Vector3.UP), cabeca - bh.z * 0.5)
		# Sapata de concreto
		criar_multimesh(self, [Transform3D(Basis.from_scale(Vector3(4.5, 2.0, 4.5)), base + Vector3.UP * 1.0)], material_concreto(base.y))
	criar_multimesh(self, aco, _material_metal(Color(0.13, 0.135, 0.15), 0.8, 0.4))
	criar_multimesh(self, lampadas, _material_luz(Color(1.0, 0.93, 0.8), 9.0), false)
	adicionar_colisoes(_estruturas, colisao)
	# Letreiro, outdoors, varais de lâmpadas, neon e flâmulas
	var enfeites := EnfeitesArena.new()
	add_child(enfeites)
	enfeites.montar(self)


# ------------------------------------------------------------------ vagas

## Índices das vagas para `quantidade` carros, espalhados pela arena (fundo e laterais).
func sortear_vagas(quantidade: int, rng: RandomNumberGenerator) -> Array[int]:
	var total := vagas_cfg.size()
	var escolhidas: Array[int] = []
	if quantidade >= total:
		for i in total:
			escolhidas.append(i)
		for i in range(total - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t := escolhidas[i]
			escolhidas[i] = escolhidas[j]
			escolhidas[j] = t
		return escolhidas
	# Passo fixo a partir de um início sorteado: fica espalhado; a ordem de quem vai onde é sorteada
	var passo := float(total) / quantidade
	var inicio := rng.randf() * passo
	for k in quantidade:
		escolhidas.append(int(inicio + k * passo) % total)
	for i in range(escolhidas.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := escolhidas[i]
		escolhidas[i] = escolhidas[j]
		escolhidas[j] = t
	return escolhidas


func transform_vaga(i: int) -> Transform3D:
	var v: Array = vagas_cfg[i]
	var f := dir_mundo(deg_to_rad(float(v[2])))
	return Transform3D(Basis.looking_at(f, Vector3.UP), pa(float(v[0]), float(v[1]), piso_y + 0.15))


## Acende a faixa de cada vaga na cor da equipe de quem larga nela (as outras apagam).
func pintar_vagas(cores: Dictionary) -> void:
	for i in _leds_vagas.size():
		var m := _leds_vagas[i]
		var c: Color = cores.get(i, Color(0.15, 0.15, 0.15))
		m.albedo_color = c
		m.emission = c
		m.emission_energy_multiplier = 4.0 if cores.has(i) else 0.0


# ------------------------------------------------------------------ navegação dos bots

## Mapa de custo até o fim do corredor de saída, desviando dos buracos (com folga) e das paredes.
func _montar_nav() -> void:
	_nav_x_max = comprimento + 40.0
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
			var c := _custo_celula(q)
			custo[k] = c
			_nav[k] = INF
			if c < INF and q.x >= _nav_x_max - 3.0:
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
		if cab > 4096 and cab * 2 > fila.size():
			fila = fila.slice(cab)
			cab = 0


func _nav_q(i: int, j: int) -> Vector2:
	return Vector2(i * CELULA, -largura_arena * 0.5 + j * CELULA)


## INF = parede ou buraco; > 1 = perto de buraco (evitar, mas dá para passar).
func _custo_celula(q: Vector2) -> float:
	if q.x > comprimento - 1.0:
		if absf(q.y) > (saida_largura * 0.5 if q.x < comprimento + 2.0 else largura * 0.5) - 2.2:
			return INF
	elif q.x < 1.5 or absf(q.y) > largura_arena * 0.5 - 1.8:
		return INF
	var c := 1.0
	# Parede da frente fora do vão do portão: chegar de frente para a saída, não pelo canto
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
	# Setas: armadilha = evitar (com folga); rota = atalho
	for im in impulsos:
		var dq: Vector2 = q - im[0]
		var f := Vector2(cos(im[1]), sin(im[1]))
		var dentro_seta := absf(dq.dot(f)) < IMPULSO_MEIO.x + 1.5 and absf(dq.dot(Vector2(-f.y, f.x))) < IMPULSO_MEIO.y + 1.5
		if dentro_seta:
			c = c + 12.0 if not im[2] else c * 0.5
	return c


func _nav_valor(i: int, j: int) -> float:
	if i < 0 or j < 0 or i >= _nav_nx or j >= _nav_nl:
		return INF
	return _nav[i * _nav_nl + j]


## Ponto (mundo) para onde um bot na posição `p` deve mirar para chegar à saída: segue as
## células de menor custo por `passos` células à frente.
func rumo_saida(p: Vector3, passos := 5) -> Vector3:
	var l := local(p)
	var i := clampi(int(round(l.x / CELULA)), 0, _nav_nx - 1)
	var j := clampi(int(round((l.y + largura_arena * 0.5) / CELULA)), 0, _nav_nl - 1)
	if _nav_valor(i, j) == INF:
		# Célula bloqueada (encostado na parede ou na boca do buraco): vai para a livre mais perto
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
