class_name ComplexoLancamento
extends Node3D
## Complexo de lançamento de uma equipe: plataforma a 400 m, descida lisa, rampa final,
## treliças metálicas até o terreno, luzes laterais, pórtico com semáforo e a decoração de evento.

const ESPESSURA := 1.6

var indice_equipe := 0
var cor := Color.WHITE
var direcao := Vector3.FORWARD   # do alvo para o complexo
var frente := Vector3.BACK        # sentido de descida (para o alvo)
var lateral := Vector3.RIGHT      # direita de quem desce
var perfil: PerfilRampa
var distancia_saida := 2000.0
var largura := 22.0
var _estruturas: StaticBody3D   # colisão de treliças, pórtico e base
var _semaforo: Array[MeshInstance3D] = []
var _mat_semaforo: Array = []


func montar(p_indice: int, p_perfil: PerfilRampa, terreno: Terreno) -> void:
	indice_equipe = p_indice
	var eq: Dictionary = Config.EQUIPES[p_indice]
	cor = eq.cor
	direcao = eq.direcao
	frente = -direcao
	lateral = frente.cross(Vector3.UP).normalized()
	perfil = p_perfil
	distancia_saida = Config.valor("mapa.distancia_saida_alvo", 2000)
	largura = Config.valor("mapa.pista_largura", 22)
	name = "Complexo_" + eq.nome
	_estruturas = StaticBody3D.new()
	_estruturas.name = "Estruturas"
	_estruturas.collision_layer = 1
	_estruturas.collision_mask = 0
	_estruturas.add_to_group("estrutura")
	add_child(_estruturas)
	_montar_pista()
	_montar_estrutura(terreno)
	_montar_plataforma(terreno)
	_montar_muro()
	_montar_portico()
	var deco := DecoracaoEvento.new()
	deco.name = "Decoracao"
	add_child(deco)
	deco.montar(self, terreno)


## Ponto da linha central da pista na distância horizontal x (desde o início da plataforma).
func ponto(x: float, y: float) -> Vector3:
	var h := direcao * (distancia_saida + perfil.comprimento_horizontal - x)
	return Vector3(h.x, y, h.z)


func ponto_indice(i: int) -> Vector3:
	return ponto(perfil.pontos[i].x, perfil.pontos[i].y)


## Distância horizontal até o alvo em que termina a rampa.
func posicao_saida() -> Vector3:
	return ponto_indice(perfil.pontos.size() - 1)


## Transformações de largada lado a lado, voltadas para a descida.
func vagas_largada(quantidade: int) -> Array[Transform3D]:
	var vagas: Array[Transform3D] = []
	var base := ponto(16.0, perfil.pontos[0].y)
	var b := Basis.looking_at(frente, Vector3.UP)
	var espaco := minf(5.0, (largura - 4.0) / maxf(quantidade - 1, 1))
	for i in quantidade:
		var desloc := (i - (quantidade - 1) * 0.5) * espaco
		vagas.append(Transform3D(b, base + lateral * desloc + Vector3.UP * 0.15))
	return vagas


## Coordenada "x do perfil" de um ponto do mundo (para saber em que trecho da pista o carro está).
func x_perfil(p: Vector3) -> float:
	return distancia_saida + perfil.comprimento_horizontal - Vector2(p.x, p.z).dot(Vector2(direcao.x, direcao.z))


func _base_pista(i: int) -> Dictionary:
	var a := perfil.angulos[i]
	var t := (frente * cos(a) + Vector3.UP * sin(a)).normalized()
	var n := lateral.cross(t).normalized()
	return {"c": ponto_indice(i), "t": t, "n": n}


func _montar_pista() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var laterais := SurfaceTool.new()
	laterais.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var meia := largura * 0.5
	var v_ac := 0.0
	var anterior := {}
	for i in perfil.pontos.size():
		var b := _base_pista(i)
		if i > 0:
			v_ac += PerfilRampa.PASSO
			var v0 := v_ac - PerfilRampa.PASSO
			var c0: Vector3 = anterior.c
			var c1: Vector3 = b.c
			var n0: Vector3 = anterior.n
			var n1: Vector3 = b.n
			var e0 := c0 - lateral * meia
			var d0 := c0 + lateral * meia
			var e1 := c1 - lateral * meia
			var d1 := c1 + lateral * meia
			# Face superior (sem guarda-corpo: quem sai pela lateral cai)
			_quad(st, e0, d0, d1, e1, n0, n1, Vector2(0, v0), Vector2(1, v_ac))
			faces.append_array([e0, d0, d1, e0, d1, e1])
			# Laterais (UV.x = metros, UV.y = 0 no topo) e fundo
			_quad_uv(laterais, [e0, e1, e1 - n1 * ESPESSURA, e0 - n0 * ESPESSURA], -lateral,
				[Vector2(v0, 0), Vector2(v_ac, 0), Vector2(v_ac, 1), Vector2(v0, 1)])
			_quad_uv(laterais, [d0, d0 - n0 * ESPESSURA, d1 - n1 * ESPESSURA, d1], lateral,
				[Vector2(v0, 0), Vector2(v0, 1), Vector2(v_ac, 1), Vector2(v_ac, 0)])
			_quad_uv(laterais, [e0 - n0 * ESPESSURA, e1 - n1 * ESPESSURA, d1 - n1 * ESPESSURA, d0 - n0 * ESPESSURA], -n0,
				[Vector2(v0, 0.5), Vector2(v_ac, 0.5), Vector2(v_ac, 0.5), Vector2(v0, 0.5)])
		anterior = b
	var mat_pista := ShaderMaterial.new()
	mat_pista.shader = load("res://shaders/pista.gdshader")
	mat_pista.set_shader_parameter("cor_equipe", cor)
	mat_pista.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 3))
	mat_pista.set_shader_parameter("largura", largura)
	mat_pista.set_shader_parameter("comp_plataforma", perfil.pontos[perfil.indice_borda].x)
	mat_pista.set_shader_parameter("linha_largada", 21.0)
	mat_pista.set_shader_parameter("inicio_rampa", float(perfil.indice_base) * PerfilRampa.PASSO)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat_pista
	add_child(mi)

	var mat_lateral := ShaderMaterial.new()
	mat_lateral.shader = load("res://shaders/lateral_pista.gdshader")
	mat_lateral.set_shader_parameter("cor_equipe", cor)
	var mi_l := MeshInstance3D.new()
	mi_l.mesh = laterais.commit()
	mi_l.material_override = mat_lateral
	add_child(mi_l)

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
	var mat_fisico := PhysicsMaterial.new()
	mat_fisico.friction = 0.6
	corpo.physics_material_override = mat_fisico
	add_child(corpo)

	# Lâmpadas âmbar em sequência nas laterais, "correndo" em direção à saída
	var luzes: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	var i := 2
	while i < perfil.pontos.size():
		var b := _base_pista(i)
		for lado: float in [-1.0, 1.0]:
			var p: Vector3 = b.c + lateral * (meia + 0.12) * lado - b.n * 0.3
			luzes.append(Transform3D(Basis.looking_at(b.t, b.n) * Basis.from_scale(Vector3(0.3, 0.3, 0.7)), p))
			fases.append(i * 0.15)
		i += 4
	var mat_luzes := ShaderMaterial.new()
	mat_luzes.shader = load("res://shaders/luz_sequencial.gdshader")
	mat_luzes.set_shader_parameter("energia", 7.0)
	_multimesh(luzes, mat_luzes, false, fases)
	_marcas_distancia()


## Distância até a saída pintada na pista (400, 300, 200, 100 m), legível para quem desce.
func _marcas_distancia() -> void:
	var ultimo := perfil.pontos.size() - 1
	for d: int in [400, 300, 200, 100]:
		var i := ultimo - int(d / PerfilRampa.PASSO)
		if i <= perfil.indice_borda:
			continue
		var b := _base_pista(i)
		var l := Label3D.new()
		l.text = str(d)
		l.font_size = 256
		l.pixel_size = 0.015
		l.outline_size = 0
		l.modulate = Color(0.95, 0.94, 0.9, 0.9)
		l.double_sided = false
		l.transform = Transform3D(Basis(lateral, b.t, b.n), b.c + b.n * 0.04)
		add_child(l)


func _montar_estrutura(terreno: Terreno) -> void:
	var pecas: Array[Transform3D] = []      # colisão (e travessas visíveis)
	var colunas: Array[Transform3D] = []    # visual das colunas em perfil I
	var sapatas: Array[Transform3D] = []
	var b_col := Basis.looking_at(frente, Vector3.UP)
	var meia := largura * 0.5 - 1.2
	var i := perfil.indice_borda + 12
	var pares_anteriores := []
	while i < perfil.pontos.size():
		var b := _base_pista(i)
		var par := []
		for lado: float in [-1.0, 1.0]:
			var topo: Vector3 = b.c + lateral * meia * lado - b.n * ESPESSURA
			var chao := terreno.altura_em(topo.x, topo.z) - 3.0
			if topo.y - chao > 2.0:
				pecas.append(_viga(Vector3(topo.x, chao, topo.z), topo, 1.5))
				par.append([topo, chao])
				# Perfil I: alma + duas mesas, e sapata de concreto no terreno
				var meio := Vector3(topo.x, (topo.y + chao) * 0.5, topo.z)
				var alt := topo.y - chao
				colunas.append(Transform3D(b_col * Basis.from_scale(Vector3(0.22, alt, 1.3)), meio))
				for m: float in [-1.0, 1.0]:
					colunas.append(Transform3D(b_col * Basis.from_scale(Vector3(1.5, alt, 0.2)), meio + frente * 0.7 * m))
				sapatas.append(Transform3D(b_col * Basis.from_scale(Vector3(3.6, 4.0, 3.6)), Vector3(topo.x, chao + 3.6, topo.z)))
				colunas.append(Transform3D(b_col * Basis.from_scale(Vector3(2.2, 0.12, 2.2)), Vector3(topo.x, chao + 5.66, topo.z)))
		if par.size() == 2:
			var altura_min: float = maxf(par[0][1], par[1][1])
			var y: float = minf(par[0][0].y, par[1][0].y) - 4.0
			var nivel := 0
			while y > altura_min + 4.0 and nivel < 20:
				var a := Vector3(par[0][0].x, y, par[0][0].z)
				var c := Vector3(par[1][0].x, y, par[1][0].z)
				pecas.append(_viga(a, c, 0.6))
				if pares_anteriores.size() == 2:
					for k in 2:
						var ant: Array = pares_anteriores[k]
						var cima := Vector3(ant[0].x, y, ant[0].z)
						if y < ant[0].y - 2.0 and y > ant[1] + 2.0:
							pecas.append(_viga(Vector3(par[k][0].x, y, par[k][0].z), cima, 0.5))
				y -= 28.0
				nivel += 1
		pares_anteriores = par
		i += 26
	# Travessas e diagonais (as colunas cheias de pecas só servem de colisão)
	var travessas: Array[Transform3D] = []
	travessas.assign(pecas.filter(func(t: Transform3D): return t.basis.z.length() < 400.0 and absf(t.basis.z.normalized().y) < 0.95))
	var chao_medio := terreno.altura_em(posicao_saida().x, posicao_saida().z)
	var mat := material_aco(chao_medio, 0.28)
	_multimesh(colunas, mat, true)
	_multimesh(travessas, mat, true)
	_multimesh(sapatas, material_concreto(chao_medio), true)
	adicionar_colisoes(_estruturas, pecas)


## Base sob a área de largada, rente à pista (sem beiral: quem sai pela lateral cai na mesa):
## bloco de concreto aparente com cantoneiras de aço nas bordas, nervuras nas laterais, faixa de
## LED da equipe. O bloco fica inteiro em cima da mesa (termina antes do paredão); o trecho da
## pista que avança sobre o precipício é sustentado por vigas em balanço (_montar_balanco).
const RECUO_MESA := 14.0   # o bloco termina esta distância antes da borda da descida

func _montar_plataforma(terreno: Terreno) -> void:
	var x_borda := perfil.pontos[perfil.indice_borda].x
	var x_ini := -30.0
	var x_fim := x_borda - RECUO_MESA
	var comp := x_fim - x_ini
	var centro := ponto((x_ini + x_fim) * 0.5, perfil.pontos[0].y - ESPESSURA - 4.0)
	var b := Basis.looking_at(frente, Vector3.UP)   # X = lateral, -Z = frente
	var chao := terreno.altura_em(centro.x, centro.z)
	var bloco := Transform3D(b * Basis.from_scale(Vector3(largura, 8.0, comp)), centro)
	criar_multimesh(self, [bloco], material_concreto(chao))
	adicionar_colisoes(_estruturas, [bloco])

	var aco: Array[Transform3D] = []
	var led: Array[Transform3D] = []
	var topo := centro.y + 4.0
	for lado: float in [-1.0, 1.0]:
		var borda := centro + lateral * (largura * 0.5 + 0.12) * lado
		# Cantoneira no alto da borda e perfil na base do bloco
		aco.append(Transform3D(b * Basis.from_scale(Vector3(0.3, 0.35, comp + 0.3)), Vector3(borda.x, topo - 0.16, borda.z)))
		aco.append(Transform3D(b * Basis.from_scale(Vector3(0.3, 0.45, comp + 0.3)), Vector3(borda.x, centro.y - 3.8, borda.z)))
		led.append(Transform3D(b * Basis.from_scale(Vector3(0.1, 0.16, comp)), Vector3(borda.x, topo - 0.75, borda.z) + lateral * 0.12 * lado))
		# Nervuras verticais a cada 3,5 m
		var n := int(comp / 3.5)
		for k in n + 1:
			var p := borda - frente * (comp * 0.5 - k * comp / n)
			aco.append(Transform3D(b * Basis.from_scale(Vector3(0.28, 7.2, 0.4)), Vector3(p.x, centro.y - 0.1, p.z)))
	_montar_balanco(aco, x_fim, x_borda)
	criar_multimesh(self, aco, material_aco(chao))
	criar_multimesh(self, led, _material_luz(cor, 3.0), false)


## Balanço sobre o precipício: 4 vigas I engastadas no bloco, correndo sob o tabuleiro até a
## primeira coluna da descida, e mãos-francesas saindo de chapas de ancoragem na rocha do
## paredão até a ponta das vigas.
func _montar_balanco(aco: Array[Transform3D], x_fim: float, x_borda: float) -> void:
	var b := Basis.looking_at(frente, Vector3.UP)
	var y_viga := perfil.pontos[0].y - ESPESSURA - 0.45
	var x_ponta := x_borda + 14.0   # passa da primeira coluna (indice_borda + 12)
	var colisao: Array[Transform3D] = []
	for k in 4:
		var d := lerpf(-largura * 0.5 + 2.0, largura * 0.5 - 2.0, k / 3.0)
		var a := ponto(x_fim - 6.0, y_viga) + lateral * d
		var c := ponto(x_ponta, perfil.altura_em(x_ponta) - ESPESSURA - 0.45) + lateral * d
		# Viga I: alma + mesas de cima e de baixo
		aco.append(_viga(a, c, 0.22) * Transform3D(Basis.from_scale(Vector3(1.0, 4.0, 1.0)), Vector3.ZERO))
		for s: float in [-1.0, 1.0]:
			aco.append(_viga(a + Vector3.UP * 0.42 * s, c + Vector3.UP * 0.42 * s, 0.1) * Transform3D(Basis.from_scale(Vector3(7.0, 1.0, 1.0)), Vector3.ZERO))
		colisao.append(_viga(a, c, 0.9))
		# Mão-francesa: da rocha (18 m abaixo, recuada no paredão) até perto da ponta da viga
		var ancora := ponto(x_borda - 6.0, perfil.pontos[0].y - 22.0) + lateral * d
		var apoio := ponto(x_borda + 9.0, perfil.altura_em(x_borda + 9.0) - ESPESSURA - 0.9) + lateral * d
		aco.append(_viga(ancora, apoio, 0.55))
		aco.append(Transform3D(b * Basis.from_scale(Vector3(1.6, 1.6, 0.25)), ancora + frente * 0.2))   # chapa na rocha
		# Tirante intermediário, formando o triângulo
		aco.append(_viga(ancora.lerp(apoio, 0.5), ponto(x_borda + 1.0, y_viga - 0.4) + lateral * d, 0.3))
	# Travessas ligando as vigas por baixo
	for x in [x_fim, x_borda - 4.0, x_borda + 4.0, x_ponta - 1.0]:
		var y := perfil.altura_em(minf(x, x_ponta)) - ESPESSURA - 0.9 if x > x_borda else y_viga - 0.45
		aco.append(_viga(ponto(x, y) - lateral * (largura * 0.5 - 1.5), ponto(x, y) + lateral * (largura * 0.5 - 1.5), 0.25))
	adicionar_colisoes(_estruturas, colisao)


## Muro de contenção atrás da largada: concreto de 1,2 m com contrafortes atrás, almofadas de
## impacto na cor da equipe na frente, capa de aço com faixa de advertência e LED no topo.
func _montar_muro() -> void:
	var b0 := _base_pista(0)
	var c: Vector3 = b0.c
	var b := Basis.looking_at(frente, Vector3.UP)
	var altura := 3.0
	var base_y := c.y - ESPESSURA
	var larg := largura + 2.0
	var concreto: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var corpo := Transform3D(b * Basis.from_scale(Vector3(larg, altura + ESPESSURA, 1.2)),
		c - frente * 0.6 + Vector3.UP * ((altura - ESPESSURA) * 0.5))
	concreto.append(corpo)
	colisao.append(corpo)
	# Contrafortes inclinados atrás, a cada ~4 m
	var n := int(larg / 4.0)
	for k in n + 1:
		var x := -larg * 0.5 + 0.4 + k * (larg - 0.8) / n
		var pe := c + lateral * x - frente * 3.6 + Vector3.UP * (-ESPESSURA + 0.3)
		var alto := c + lateral * x - frente * 1.1 + Vector3.UP * (altura - 0.4)
		concreto.append(_viga(pe, alto, 0.6))
		concreto.append(Transform3D(b * Basis.from_scale(Vector3(0.8, 0.6, 3.0)), c + lateral * x - frente * 2.4 + Vector3.UP * (-ESPESSURA + 0.3)))
	criar_multimesh(self, concreto, material_concreto(base_y - 400.0))

	# Capa de aço com faixa de advertência
	var capa := Transform3D(b * Basis.from_scale(Vector3(larg + 0.4, 0.28, 1.5)), c - frente * 0.6 + Vector3.UP * (altura + 0.14))
	criar_multimesh(self, [capa], material_listras())
	# Almofadas de impacto (um bloco por vaga) com faixa branca refletiva
	var almofadas: Array[Transform3D] = []
	var faixas: Array[Transform3D] = []
	var qtd := 6
	var passo := largura / qtd
	for k in qtd:
		var x := -largura * 0.5 + passo * (k + 0.5)
		var p := c + lateral * x + frente * 0.25 + Vector3.UP * 0.95
		var t := Transform3D(b * Basis.from_scale(Vector3(passo - 0.18, 1.7, 0.5)), p)
		almofadas.append(t)
		colisao.append(t)
		faixas.append(Transform3D(b * Basis.from_scale(Vector3(passo - 0.18, 0.14, 0.52)), p + Vector3.UP * 0.45))
	var mat_almofada := StandardMaterial3D.new()
	mat_almofada.albedo_color = cor.darkened(0.25)
	mat_almofada.roughness = 0.85
	criar_multimesh(self, almofadas, mat_almofada)
	var mat_faixa := StandardMaterial3D.new()
	mat_faixa.albedo_color = Color(0.92, 0.92, 0.9)
	mat_faixa.roughness = 0.35
	mat_faixa.emission_enabled = true
	mat_faixa.emission = Color(0.9, 0.9, 0.85)
	mat_faixa.emission_energy_multiplier = 0.25
	criar_multimesh(self, faixas, mat_faixa)
	# LED da equipe logo abaixo da capa
	criar_multimesh(self, [Transform3D(b * Basis.from_scale(Vector3(larg, 0.14, 0.08)), c + frente * 0.02 + Vector3.UP * (altura - 0.3))], _material_luz(cor, 4.0), false)
	adicionar_colisoes(_estruturas, colisao)


func material_concreto(chao: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/concreto.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.04, 4, 23 + indice_equipe))
	m.set_shader_parameter("altura_chao", chao)
	return m


func material_aco(chao: float, ferrugem := 0.4) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/metal_gasto.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 61 + indice_equipe))
	m.set_shader_parameter("ferrugem", ferrugem)
	m.set_shader_parameter("cor_tinta", Color(0.2, 0.21, 0.23))
	m.set_shader_parameter("altura_chao", chao)
	return m


func material_listras() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/listras_perigo.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 7))
	return m


## Pórtico em treliça sobre a pista, com painel da equipe e semáforo de largada.
func _montar_portico() -> void:
	var x := perfil.pontos[perfil.indice_borda].x - 4.0
	var base := ponto(x, perfil.pontos[0].y)
	var meia := largura * 0.5 + 1.5
	var visual: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	for lado: float in [-1.0, 1.0]:
		var p := base + lateral * meia * lado
		visual.append_array(trelica(p, p + Vector3.UP * 12.0, 1.3, 1.5, 0.2, 0.08))
		colisao.append(_viga(p, p + Vector3.UP * 12.0, 1.3))
	var e := base - lateral * (meia + 0.65) + Vector3.UP * 11.3
	var d := base + lateral * (meia + 0.65) + Vector3.UP * 11.3
	visual.append_array(trelica(e, d, 1.3, 1.5, 0.2, 0.08))
	colisao.append(_viga(e, d, 1.3))
	_multimesh(visual, _material_metal(Color(0.13, 0.135, 0.15), 0.8, 0.4))
	adicionar_colisoes(_estruturas, colisao)

	var olhando := Basis.looking_at(frente, Vector3.UP)
	var painel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(largura * 0.8, 2.2, 0.3)
	painel.mesh = bm
	painel.transform = Transform3D(olhando, base + Vector3.UP * 13.2)
	painel.material_override = _material_luz(cor, 2.0)
	add_child(painel)
	adicionar_colisoes(_estruturas, [painel.transform * Transform3D(Basis.from_scale(bm.size), Vector3.ZERO)])
	var texto := Label3D.new()
	texto.text = "EQUIPE " + Config.EQUIPES[indice_equipe].nome
	texto.font_size = 180
	texto.pixel_size = 0.009
	texto.outline_size = 24
	texto.modulate = Color.WHITE
	texto.transform = Transform3D(olhando, base + Vector3.UP * 13.2 - frente * 0.25)
	add_child(texto)

	# Semáforo: três lâmpadas voltadas para quem larga
	var caixa := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(6.4, 1.8, 0.7)
	caixa.mesh = cm
	caixa.material_override = _material_metal(Color(0.03, 0.03, 0.035), 0.3, 0.6)
	caixa.transform = Transform3D(olhando, base + Vector3.UP * 9.8)
	add_child(caixa)
	var lampada := CylinderMesh.new()
	lampada.top_radius = 0.62
	lampada.bottom_radius = 0.62
	lampada.height = 0.25
	lampada.radial_segments = 24
	_semaforo.clear()
	for k in 3:
		var l := MeshInstance3D.new()
		l.mesh = lampada
		var p := base + Vector3.UP * 9.8 + lateral * (k - 1) * 2.0 - frente * 0.45
		l.transform = Transform3D(olhando * Basis(Vector3.RIGHT, PI * 0.5), p)
		add_child(l)
		_semaforo.append(l)
	semaforo(0)


## Acende `acesas` lâmpadas vermelhas (0 a 3) ou todas verdes.
func semaforo(acesas: int, verde := false) -> void:
	if _mat_semaforo.is_empty():
		_mat_semaforo = [_material_metal(Color(0.12, 0.02, 0.02), 0.2, 0.3),
			_material_luz(Color(1.0, 0.08, 0.05), 9.0), _material_luz(Color(0.2, 1.0, 0.3), 9.0)]
	for k in _semaforo.size():
		var m: Material = _mat_semaforo[2] if verde else (_mat_semaforo[1] if k < acesas else _mat_semaforo[0])
		_semaforo[k].material_override = m


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n0: Vector3, n1: Vector3, uv0: Vector2, uv1: Vector2) -> void:
	st.set_normal(n0); st.set_uv(Vector2(uv0.x, uv0.y)); st.add_vertex(a)
	st.set_normal(n0); st.set_uv(Vector2(uv1.x, uv0.y)); st.add_vertex(b)
	st.set_normal(n1); st.set_uv(Vector2(uv1.x, uv1.y)); st.add_vertex(c)
	st.set_normal(n0); st.set_uv(Vector2(uv0.x, uv0.y)); st.add_vertex(a)
	st.set_normal(n1); st.set_uv(Vector2(uv1.x, uv1.y)); st.add_vertex(c)
	st.set_normal(n1); st.set_uv(Vector2(uv0.x, uv1.y)); st.add_vertex(d)


## Transformação de uma viga (caixa unitária) ligando a até b.
static func _viga(a: Vector3, b: Vector3, espessura: float) -> Transform3D:
	var d := b - a
	var comprimento := d.length()
	var cima := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var base := Basis.looking_at(d / comprimento, cima) * Basis.from_scale(Vector3(espessura, espessura, comprimento))
	return Transform3D(base, (a + b) * 0.5)


## Uma caixa de colisão para cada peça (transformação de caixa unitária com escala).
static func adicionar_colisoes(corpo: CollisionObject3D, transformacoes: Array) -> void:
	for t: Transform3D in transformacoes:
		var tamanho := Vector3(t.basis.x.length(), t.basis.y.length(), t.basis.z.length())
		if tamanho.x < 0.01 or tamanho.y < 0.01 or tamanho.z < 0.01:
			continue
		var forma := BoxShape3D.new()
		forma.size = tamanho
		var cs := CollisionShape3D.new()
		cs.shape = forma
		cs.transform = Transform3D(t.basis.orthonormalized(), t.origin)
		corpo.add_child(cs)


func _multimesh(transformacoes: Array[Transform3D], mat: Material, sombra := true, fases := PackedFloat32Array()) -> void:
	criar_multimesh(self, transformacoes, mat, sombra, fases)


## Caixas unitárias instanciadas; `fases` (opcional) vai para INSTANCE_CUSTOM.r de cada instância.
static func criar_multimesh(pai: Node, transformacoes: Array[Transform3D], mat: Material, sombra := true, fases := PackedFloat32Array()) -> MultiMeshInstance3D:
	if transformacoes.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not fases.is_empty()
	var caixa := BoxMesh.new()
	caixa.material = mat
	mm.mesh = caixa
	mm.instance_count = transformacoes.size()
	for i in transformacoes.size():
		mm.set_instance_transform(i, transformacoes[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, Color(fases[i], 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(mmi)
	return mmi


## Treliça de quatro banzos entre a e b (seção quadrada de lado `lado`), com travessas e diagonais a cada `passo`.
static func trelica(a: Vector3, b: Vector3, lado: float, passo: float, banzo := 0.2, travessa := 0.08) -> Array[Transform3D]:
	var pecas: Array[Transform3D] = []
	var d := b - a
	var comprimento := d.length()
	if comprimento < 0.01:
		return pecas
	var eixo := d / comprimento
	var ref := Vector3.UP if absf(eixo.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var p1 := eixo.cross(ref).normalized() * lado * 0.5
	var p2 := eixo.cross(p1).normalized() * lado * 0.5
	var cantos := [p1 + p2, p1 - p2, -p1 - p2, -p1 + p2]
	for c: Vector3 in cantos:
		pecas.append(_viga(a + c, b + c, banzo))
	var n := maxi(int(round(comprimento / passo)), 1)
	for s in n + 1:
		var p := a + d * (float(s) / n)
		var q := a + d * (float(s + 1) / n)
		for k in 4:
			var c0: Vector3 = cantos[k]
			var c1: Vector3 = cantos[(k + 1) % 4]
			pecas.append(_viga(p + c0, p + c1, travessa))
			if s < n:
				if (s + k) % 2 == 0:
					pecas.append(_viga(p + c0, q + c1, travessa))
				else:
					pecas.append(_viga(p + c1, q + c0, travessa))
	return pecas


## Quadrilátero com UV por vértice (a, b, c, d em sentido de face) e normal única.
func _quad_uv(st: SurfaceTool, v: Array, n: Vector3, uv: Array) -> void:
	for k: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uv[k])
		st.add_vertex(v[k])


static func _material_metal(c: Color, metal := 0.75, rugosidade := 0.45) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rugosidade
	return m


static func _material_luz(c: Color, energia: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energia
	return m
