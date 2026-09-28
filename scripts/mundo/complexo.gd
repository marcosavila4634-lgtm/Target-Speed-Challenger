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
	_montar_plataforma()
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
	# Parede atrás da largada
	var paredes := SurfaceTool.new()
	paredes.begin(Mesh.PRIMITIVE_TRIANGLES)
	var b0 := _base_pista(0)
	var tras_e: Vector3 = b0.c - lateral * meia
	var tras_d: Vector3 = b0.c + lateral * meia
	_quad(paredes, tras_e, tras_d, tras_d + Vector3.UP * 2.5, tras_e + Vector3.UP * 2.5, frente, frente, Vector2.ZERO, Vector2.ZERO)
	faces.append_array([tras_e, tras_d, tras_d + Vector3.UP * 2.5, tras_e, tras_d + Vector3.UP * 2.5, tras_e + Vector3.UP * 2.5])

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

	var mi_p := MeshInstance3D.new()
	mi_p.mesh = paredes.commit()
	mi_p.material_override = _material_metal(Color(0.32, 0.33, 0.36))
	add_child(mi_p)

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
	var pecas: Array[Transform3D] = []
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
	_multimesh(pecas, _material_metal(Color(0.2, 0.21, 0.23)), true)
	adicionar_colisoes(_estruturas, pecas)


func _montar_plataforma() -> void:
	# Base sob a área de largada, rente à pista (sem beiral: quem sai pela lateral cai na mesa)
	var x_borda := perfil.pontos[perfil.indice_borda].x
	var comp := x_borda + 30.0
	var centro := ponto(x_borda * 0.5 - 15.0, perfil.pontos[0].y - ESPESSURA - 4.0)
	var caixa := BoxMesh.new()
	caixa.size = Vector3(largura, 8.0, comp)
	var mi := MeshInstance3D.new()
	mi.mesh = caixa
	mi.transform = Transform3D(Basis.looking_at(frente, Vector3.UP), centro)
	mi.material_override = _material_metal(Color(0.16, 0.165, 0.18), 0.6, 0.5)
	add_child(mi)
	adicionar_colisoes(_estruturas, [mi.transform * Transform3D(Basis.from_scale(caixa.size), Vector3.ZERO)])


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
