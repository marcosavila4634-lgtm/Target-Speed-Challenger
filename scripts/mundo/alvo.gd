class_name Alvo
extends AnimatableBody3D
## Alvo do Target Flight: disco com cinco zonas sobre uma torre metálica.
## Pode ser fixo, deslocado, inclinado ou móvel (vai e volta numa linha a velocidade constante).
## A zona de um veículo é a que contém a maior área projetada da carroceria; em empate vale a menor.

const ESPESSURA := 1.4
const BORDA := 0.8

var raio := 15.0
var zonas: Array = []          # [[pontos, raio externo], ...] da zona 5 para a 1
var movel := false
var velocidade := 5.0
var percurso := 120.0
var direcao_mov := Vector3.RIGHT
var centro_base := Vector3.ZERO
var _t := 0.0
var disco: Node3D
var velocidade_atual := Vector3.ZERO
var _mat_luzes: ShaderMaterial
var _tween_festa: Tween
var terreno: Terreno            # para assentar sapatas, pedras e vegetação no chão


func configurar(etapa: Dictionary) -> void:
	add_to_group("alvo")
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	raio = float(etapa.get("diametro", 30)) * 0.5
	var escala := raio / 15.0
	zonas.clear()
	for z in Config.valor("alvo.zonas", [[5, 2.5], [4, 5.0], [3, 8.0], [2, 11.5], [1, 15.0]]):
		zonas.append([int(z[0]), float(z[1]) * escala])
	var desloc: Array = etapa.get("deslocamento", [0, 0])
	centro_base = Vector3(desloc[0], Config.valor("mapa.alvo_altura", 30), desloc[1])
	position = centro_base
	movel = etapa.get("movel", false)
	velocidade = etapa.get("velocidade", 5.0)
	percurso = etapa.get("percurso", 120.0)
	direcao_mov = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(etapa.get("direcao_movimento", 0.0)))
	_t = 0.0
	_montar(etapa)


func _montar(etapa: Dictionary) -> void:
	for f in get_children():
		f.queue_free()
	var inclinacao := deg_to_rad(etapa.get("inclinacao", 0.0))
	var dir_incl := deg_to_rad(etapa.get("direcao_inclinacao", 0.0))

	# Disco (visual + colisão), possivelmente inclinado
	disco = Node3D.new()
	disco.name = "Disco"
	disco.basis = Basis(Vector3.RIGHT.rotated(Vector3.UP, dir_incl), inclinacao)
	add_child(disco)
	var cil := CylinderMesh.new()
	cil.top_radius = raio + BORDA
	cil.bottom_radius = raio + BORDA
	cil.height = ESPESSURA
	cil.radial_segments = 96
	var mi := MeshInstance3D.new()
	mi.mesh = cil
	mi.position.y = -ESPESSURA * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/alvo.gdshader")
	var raios := PackedFloat32Array()
	for z in zonas:
		raios.append(z[1])
	mat.set_shader_parameter("raios", raios)
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 3, 17))
	mi.material_override = mat
	disco.add_child(mi)
	var forma := CylinderShape3D.new()
	forma.radius = raio + BORDA
	forma.height = ESPESSURA
	var cs := CollisionShape3D.new()
	cs.shape = forma
	cs.position = Vector3(0, -ESPESSURA * 0.5, 0)
	cs.basis = disco.basis
	cs.position = disco.basis * cs.position
	add_child(cs)
	_numeros()
	_luzes_borda()
	_torre()
	_arredores()


## Números 1 a 5 pintados nas zonas, repetidos nas quatro direções.
func _numeros() -> void:
	var r_interno := 0.0
	for z in zonas:
		var r_meio: float = (r_interno + float(z[1])) * 0.5
		var largura_anel: float = float(z[1]) - r_interno
		var angulos := [0.0] if z[0] == 5 else [0.0, PI * 0.5, PI, PI * 1.5]
		for a: float in angulos:
			var l := Label3D.new()
			l.text = str(z[0])
			l.font_size = 256
			l.outline_size = 0
			l.pixel_size = clampf(largura_anel * 0.75, 1.0, 3.5) / 180.0
			l.modulate = Color(0.95, 0.95, 0.92) if int(z[0]) % 2 == 1 else Color(0.75, 0.1, 0.08)
			if z[0] == 5:
				l.modulate = Color(0.95, 0.95, 0.92)
			var dir := Vector3.FORWARD.rotated(Vector3.UP, a)
			var p := dir * (0.0 if z[0] == 5 else r_meio)
			# Deitado sobre o disco, com o topo do número apontando para o centro.
			l.basis = Basis.looking_at(Vector3.DOWN, -dir) if z[0] != 5 else Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
			l.position = p + Vector3.UP * 0.03
			l.double_sided = false
			disco.add_child(l)
		r_interno = z[1]


func _luzes_borda() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var caixa := BoxMesh.new()
	# Lâmpadas embutidas na lateral da borda do disco: abaixo do piso, não atrapalham quem pousa
	caixa.size = Vector3(0.7, 0.45, 0.12)
	_mat_luzes = ShaderMaterial.new()
	_mat_luzes.shader = load("res://shaders/luz_sequencial.gdshader")
	_mat_luzes.set_shader_parameter("cor", Color(1.0, 0.6, 0.2))
	_mat_luzes.set_shader_parameter("energia", 7.0)
	_mat_luzes.set_shader_parameter("velocidade", 4.0)
	caixa.material = _mat_luzes
	mm.mesh = caixa
	var n := 48
	mm.instance_count = n
	for i in n:
		var a := TAU * i / n
		var fora := Vector3(sin(a), 0.0, cos(a))
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, a), fora * (raio + BORDA + 0.02) + Vector3.UP * (-ESPESSURA * 0.5)))
		mm.set_instance_custom_data(i, Color(a * 3.0, 0, 0, 0))   # três ondas girando em volta
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	disco.add_child(mmi)


## Faz as luzes da borda piscarem na cor da equipe que acabou de tocar o alvo.
func festejar(cor_equipe: Color, duracao := 3.0) -> void:
	if _mat_luzes == null:
		return
	_mat_luzes.set_shader_parameter("cor_flash", cor_equipe)
	if _tween_festa:
		_tween_festa.kill()
	_tween_festa = create_tween()
	_tween_festa.tween_method(func(v: float): _mat_luzes.set_shader_parameter("flash", v), 1.0, 1.0, duracao)
	_tween_festa.tween_method(func(v: float): _mat_luzes.set_shader_parameter("flash", v), 1.0, 0.0, 0.6)


func _torre() -> void:
	var altura := centro_base.y
	var pecas: Array[Transform3D] = []
	var r := raio * 0.55
	var base_y := -altura - 2.0
	var cantos := []
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		cantos.append(Vector3(sin(a) * r, 0.0, cos(a) * r))
	for k in 4:
		var c: Vector3 = cantos[k]
		pecas.append(ComplexoLancamento._viga(Vector3(c.x, base_y, c.z), Vector3(c.x, -ESPESSURA - 0.2, c.z), 1.4))
		var prox: Vector3 = cantos[(k + 1) % 4]
		var y := -ESPESSURA - 3.0
		while y > base_y + 3.0:
			pecas.append(ComplexoLancamento._viga(Vector3(c.x, y, c.z), Vector3(prox.x, y, prox.z), 0.6))
			pecas.append(ComplexoLancamento._viga(Vector3(c.x, y, c.z), Vector3(prox.x, y - 8.0, prox.z), 0.4))
			y -= 8.0
	# Tiras de luz presas na face externa de cada perna, do pé até logo abaixo do disco
	var faixas: Array[Transform3D] = []
	for c: Vector3 in cantos:
		var fora := c.normalized() * 0.8
		faixas.append(ComplexoLancamento._viga(Vector3(c.x, base_y + 3.0, c.z) + fora, Vector3(c.x, -ESPESSURA - 0.6, c.z) + fora, 0.12))
	ComplexoLancamento.criar_multimesh(self, faixas, ComplexoLancamento._material_luz(Color(1.0, 0.6, 0.2), 6.0), false)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var caixa := BoxMesh.new()
	caixa.material = _material_torre()
	mm.mesh = caixa
	mm.instance_count = pecas.size()
	for i in pecas.size():
		mm.set_instance_transform(i, pecas[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	# A torre é estrutura comum: bater nela não conta como tocar o alvo.
	var torre := StaticBody3D.new()
	torre.name = "Torre"
	torre.collision_layer = 1
	torre.collision_mask = 0
	torre.add_to_group("estrutura")
	add_child(torre)
	ComplexoLancamento.adicionar_colisoes(torre, pecas)
	if movel:
		# Trilho no chão por onde a torre desliza
		var trilho := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(raio * 1.5, 1.0, percurso + raio * 1.5)
		trilho.mesh = bm
		trilho.material_override = ComplexoLancamento._material_metal(Color(0.3, 0.3, 0.32), 0.3, 0.7)
		trilho.top_level = true
		trilho.transform = Transform3D(Basis.looking_at(direcao_mov, Vector3.UP), Vector3(centro_base.x, 1.5, centro_base.z))
		add_child(trilho)


func _physics_process(delta: float) -> void:
	if not movel:
		return
	_t += delta
	var nova := _posicao_em(_t)
	velocidade_atual = (nova - position) / delta
	position = nova


## Vai e volta numa linha a velocidade constante.
func _posicao_em(t: float) -> Vector3:
	if not movel:
		return centro_base
	var periodo := 2.0 * percurso / maxf(velocidade, 0.01)
	var fase := fmod(t, periodo) / periodo
	var s := (fase * 2.0 if fase < 0.5 else 2.0 - fase * 2.0) - 0.5
	return centro_base + direcao_mov * s * percurso


## Centro da face superior daqui a alguns segundos (usado pelos bots no alvo móvel).
func centro_futuro(segundos: float) -> Vector3:
	return centro_superior() + _posicao_em(_t + segundos) - _posicao_em(_t)


## Centro da face superior no mundo (para o marcador de distância).
func centro_superior() -> Vector3:
	return disco.global_position


## Zona (pontos) de um veículo apoiado no alvo; 0 se nenhuma parte da carroceria estiver sobre o alvo.
func zona_do_veiculo(v: Veiculo) -> int:
	var inv := disco.global_transform.affine_inverse()
	var contagem := {}
	for p in v.pontos_projecao():
		var local := inv * (v.global_transform * p)
		var r := Vector2(local.x, local.z).length()
		for z in zonas:
			if r <= z[1]:
				contagem[z[0]] = contagem.get(z[0], 0) + 1
				break
	var melhor := 0
	var melhor_qtd := 0
	for pontos in [1, 2, 3, 4, 5]:
		var q: int = contagem.get(pontos, 0)
		if q > melhor_qtd:
			melhor = pontos
			melhor_qtd = q
	return melhor


# ------------------------------------------------------------------ aspecto gasto e arredores

func _chao_em(x: float, z: float) -> float:
	return terreno.altura_em(x, z) if terreno else 8.0


func _material_torre() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/metal_gasto.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 61))
	m.set_shader_parameter("ferrugem", 0.32)
	m.set_shader_parameter("cor_tinta", Color(0.22, 0.24, 0.25))
	m.set_shader_parameter("altura_chao", _chao_em(centro_base.x, centro_base.z))
	return m


## Sapatas de concreto nos pés da torre, escada de manutenção e, em volta, pedras e vegetação.
func _arredores() -> void:
	var chao_local := _chao_em(centro_base.x, centro_base.z) - centro_base.y
	var r := raio * 0.55
	var metal := _material_torre()
	var concreto := ComplexoLancamento._material_metal(Color(0.5, 0.47, 0.43), 0.0, 0.95)
	var sapatas: Array[Transform3D] = []
	var escada: Array[Transform3D] = []
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		var c := Vector3(sin(a) * r, chao_local + 0.5, cos(a) * r)
		if not movel:  # no alvo móvel a torre corre sobre o trilho
			sapatas.append(Transform3D(Basis.from_scale(Vector3(3.4, 1.4, 3.4)), c))
	# Escada vertical colada a uma perna, do chão até a borda do disco
	var perna := Vector3(sin(PI * 0.25) * r, 0.0, cos(PI * 0.25) * r)
	var fora := Vector3(perna.x, 0.0, perna.z).normalized()
	var lado := fora.cross(Vector3.UP)
	var base := perna + fora * 1.3
	var topo_y := -ESPESSURA - 0.3
	for s: float in [-0.35, 0.35]:
		var p := base + lado * s
		escada.append(ComplexoLancamento._viga(Vector3(p.x, chao_local, p.z), Vector3(p.x, topo_y, p.z), 0.07))
	var y := chao_local + 0.4
	while y < topo_y:
		escada.append(ComplexoLancamento._viga(Vector3(base.x, y, base.z) - lado * 0.35, Vector3(base.x, y, base.z) + lado * 0.35, 0.05))
		y += 0.35
	# Gaiola de proteção a partir de 3 m
	y = chao_local + 3.0
	while y < topo_y:
		for i in 6:
			var a0 := PI * i / 6.0
			var a1 := PI * (i + 1) / 6.0
			var q0 := base + (lado * cos(a0) + fora * sin(a0)) * 0.55
			var q1 := base + (lado * cos(a1) + fora * sin(a1)) * 0.55
			escada.append(ComplexoLancamento._viga(Vector3(q0.x, y, q0.z), Vector3(q1.x, y, q1.z), 0.04))
		y += 1.4
	_instancias(BoxMesh.new(), sapatas, concreto, self)
	_instancias(BoxMesh.new(), escada, metal, self)

	# Pedras e vegetação ficam no chão (não acompanham o alvo móvel)
	var chao := Node3D.new()
	chao.name = "Arredores"
	chao.top_level = true
	add_child(chao)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(centro_base.x * 13.0 + centro_base.z * 7.0) + 1234
	var nivel_agua := float(Config.valor("mapa.nivel_agua", 4))
	var pedras: Array[Transform3D] = []
	var cores_pedras: Array[Color] = []
	var arbustos := []
	var arvores := []
	var capim := []
	var tentativas := 0
	while tentativas < 1600:
		tentativas += 1
		var ang := rng.randf() * TAU
		var dist := raio * rng.randf_range(1.15, 2.8)   # fora do disco: não atrapalha quem chega
		var local := Vector3(cos(ang), 0.0, sin(ang)) * dist
		# Longe das pernas e fora do trilho do alvo móvel
		var perto_perna := false
		for k in 4:
			var a := PI * 0.25 + k * PI * 0.5
			if Vector2(local.x - sin(a) * r, local.z - cos(a) * r).length() < 3.0:
				perto_perna = true
		if perto_perna or (movel and absf(local.dot(direcao_mov.cross(Vector3.UP))) < raio * 0.85):
			continue
		var mundo := Vector3(centro_base.x, 0.0, centro_base.z) + local
		var h := _chao_em(mundo.x, mundo.z)
		if h < nivel_agua + 0.8:
			continue
		mundo.y = h
		var sorteio := rng.randf()
		if sorteio < 0.12 and pedras.size() < 40:
			var e := rng.randf_range(0.5, 2.6)
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.3, 0.3))
			pedras.append(Transform3D(b.scaled(Vector3(e * rng.randf_range(0.9, 1.5), e * rng.randf_range(0.5, 0.9), e)), mundo + Vector3.UP * e * 0.15))
			cores_pedras.append(Color(0.2, 0.1, 0.06).lerp(Color(0.32, 0.18, 0.11), rng.randf()))
		elif sorteio < 0.4 and arbustos.size() < 110:
			arbustos.append([mundo - Vector3.UP * 0.1, rng.randf_range(0.8, 1.7), rng.randf() * TAU, Color(1, 1, 1) * rng.randf_range(0.8, 1.1)])
		elif sorteio < 0.47 and arvores.size() < 14 and dist > raio * 1.5:
			arvores.append([mundo - Vector3.UP * 0.2, rng.randf_range(0.8, 1.3), rng.randf() * TAU, Color(0.9, 1.0, 0.85) * rng.randf_range(0.85, 1.1)])
		elif capim.size() < 700:
			capim.append([mundo, rng.randf_range(0.7, 1.4), rng.randf() * TAU, Color(1, 1, 1) * rng.randf_range(0.8, 1.15)])
	var rocha := SphereMesh.new()
	rocha.radial_segments = 6
	rocha.rings = 3
	var cor_vertice := StandardMaterial3D.new()
	cor_vertice.vertex_color_use_as_albedo = true
	cor_vertice.roughness = 1.0
	_instancias(rocha, pedras, cor_vertice, chao, cores_pedras)
	Vegetacao.plantar(chao, Vegetacao.Tipo.SALVIA, arbustos, 1000.0, 1400.0, true)
	Vegetacao.plantar(chao, Vegetacao.Tipo.ZIMBRO, arvores, 1000.0, 2800.0, true)
	Vegetacao.plantar(chao, Vegetacao.Tipo.CAPIM, capim, 1000.0, 300.0, false)


func _instancias(malha: Mesh, transformacoes: Array[Transform3D], mat: Material, pai: Node, cores: Array[Color] = [], sombra := true) -> void:
	if transformacoes.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cores.is_empty()
	mm.mesh = malha
	mm.instance_count = transformacoes.size()
	for i in transformacoes.size():
		mm.set_instance_transform(i, transformacoes[i])
		if mm.use_colors:
			mm.set_instance_color(i, cores[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(mmi)
