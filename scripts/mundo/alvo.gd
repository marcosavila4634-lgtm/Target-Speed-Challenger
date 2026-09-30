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
## Parado no fim da etapa: os carros são congelados no resultado e, se o vagão seguisse andando,
## quem estava em cima ficaria flutuando no ar.
var parado := false
var _mat_luzes: ShaderMaterial
var _tween_festa: Tween
var terreno: Terreno            # para assentar sapatas, pedras e vegetação no chão

## Forma "gravata" (Canyon Combat Target): hexágono comprido e côncavo, fino no meio (zona 5) e
## largo nas duas pontas (zona 1). Eixo X local do disco = comprimento; as zonas são faixas
## ao longo dele ([pontos, distância do centro até o fim da faixa]).
var gravata := false
var meio_comp := 23.0           # metade do comprimento
var larg_meio := 6.0
var larg_ponta := 22.0
var eixo := Vector3.RIGHT       # direção do comprimento no mundo
var _pernas: Array = []         # pés da torre (no plano do disco)


func configurar(etapa: Dictionary) -> void:
	add_to_group("alvo")
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	var retangulo := str(etapa.get("forma", "")) == "retangulo"
	gravata = Config.valor("alvo.forma", "circulo") == "gravata" or retangulo
	zonas.clear()
	if retangulo:
		# Alvo comprido e fino (Climb to Death, etapa 4): uma gravata de largura igual no meio e
		# nas pontas, de uma zona só (os pontos da zona única do mapa)
		meio_comp = float(etapa.get("comprimento", 50)) * 0.5
		larg_meio = float(etapa.get("largura", 3.2))
		larg_ponta = larg_meio
		var z_unica: Array = Config.valor("alvo.zonas", [[10, 15.0]])[0]
		zonas.append([int(z_unica[0]), meio_comp])
		raio = meio_comp
		var a: Array = Config.valor("arena.direcao", [0, -1])
		var voo := -Vector3(float(a[0]), 0.0, float(a[1])).normalized()
		eixo = voo.rotated(Vector3.UP, deg_to_rad(float(etapa.get("angulo", 0))))
	elif gravata:
		var esc := float(etapa.get("escala", 1.0))
		for z in Config.valor("alvo.faixas", [[5, 2.5], [4, 7.5], [3, 12.5], [2, 17.5], [1, 23.0]]):
			zonas.append([int(z[0]), float(z[1]) * esc])
		meio_comp = zonas.back()[1]
		larg_meio = float(Config.valor("alvo.largura_meio", 6)) * esc
		larg_ponta = float(Config.valor("alvo.largura_ponta", 22)) * esc
		raio = meio_comp
		# Ângulo entre o comprimento e o sentido do voo (0 = no sentido do voo, 90 = atravessado)
		var a: Array = Config.valor("arena.direcao", [0, -1])
		var voo := -Vector3(float(a[0]), 0.0, float(a[1])).normalized()
		eixo = voo.rotated(Vector3.UP, deg_to_rad(float(etapa.get("angulo", 90))))
	else:
		raio = float(etapa.get("diametro", 30)) * 0.5
		var escala := raio / 15.0
		for z in Config.valor("alvo.zonas", [[5, 2.5], [4, 5.0], [3, 8.0], [2, 11.5], [1, 15.0]]):
			zonas.append([int(z[0]), float(z[1]) * escala])
	var desloc: Array = etapa.get("deslocamento", [0, 0])
	centro_base = Vector3(desloc[0], float(etapa.get("altura", Config.valor("mapa.alvo_altura", 30))), desloc[1])
	position = centro_base
	reset_physics_interpolation()   # troca de etapa: o alvo muda de lugar sem "voar" até lá
	movel = etapa.get("movel", false)
	velocidade = etapa.get("velocidade", 5.0)
	percurso = etapa.get("percurso", 120.0)
	direcao_mov = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(etapa.get("direcao_movimento", 0.0)))
	if gravata:
		# Na gravata a direção do movimento é relativa ao voo (90 = de um lado para o outro)
		var a: Array = Config.valor("arena.direcao", [0, -1])
		var voo := -Vector3(float(a[0]), 0.0, float(a[1])).normalized()
		direcao_mov = voo.rotated(Vector3.UP, deg_to_rad(float(etapa.get("direcao_movimento", 90.0))))
	_t = 0.0
	parado = false
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
	_pernas.clear()
	if gravata:
		disco.basis = disco.basis * Basis(Vector3.UP, atan2(-eixo.z, eixo.x))
		_montar_gravata()
		for p: Vector2 in [Vector2(0.62, -0.5), Vector2(0.0, -0.35), Vector2(-0.62, -0.5), Vector2(-0.62, 0.5), Vector2(0.0, 0.35), Vector2(0.62, 0.5)]:
			var u := p.x * meio_comp
			var largura_perna := p.y * 2.0 * _meia_largura(absf(u))
			if movel:
				largura_perna = clampf(largura_perna, -4.2, 4.2)   # pés dentro do deck do vagão
			var w := disco.basis * Vector3(u, 0.0, largura_perna)
			_pernas.append(Vector3(w.x, 0.0, w.z))
		_numeros()
		_luzes_borda()
		_torre()
		_arredores()
		return
	for k in 4:
		var a := PI * 0.25 + k * PI * 0.5
		_pernas.append(Vector3(sin(a), 0.0, cos(a)) * raio * 0.55)
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
	var raios := _faixas_pintura()
	mat.set_shader_parameter("raios", raios)
	mat.set_shader_parameter("divisorias", 0.0 if _liso() else 1.0)
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


## Mapas com checkpoints (Climb to Death): alvo liso estilo mosca, sem números nem divisórias
## (pedido do dono) — tocar em qualquer parte vale o mesmo.
func _liso() -> bool:
	return not Config.valor("mapa.subida.checkpoints", {}).is_empty()


## Raios (ou fim das faixas, na gravata) das 5 cores pintadas. Alvo liso: 5 anéis iguais,
## vermelho no centro e na borda, como uma mosca; senão as zonas de pontuação.
func _faixas_pintura() -> PackedFloat32Array:
	var r := PackedFloat32Array()
	if _liso():
		var externo: float = zonas.back()[1]
		for i in 5:
			r.append(externo * (i + 1) / 5.0)
		return r
	for z in zonas:
		r.append(z[1])
	while r.size() < 5:   # zona única: o shader espera 5 raios (repete o externo)
		r.append(r[r.size() - 1])
	return r


## Números 1 a 5 pintados nas zonas, repetidos nas quatro direções.
func _numeros() -> void:
	if _liso():
		return
	if gravata:
		_numeros_gravata()
		return
	var r_interno := 0.0
	for z in zonas:
		var r_meio: float = (r_interno + float(z[1])) * 0.5
		var largura_anel: float = float(z[1]) - r_interno
		var centro: bool = z[0] == 5 or zonas.size() == 1   # zona única: um número grande no meio
		var angulos := [0.0] if centro else [0.0, PI * 0.5, PI, PI * 1.5]
		for a: float in angulos:
			var l := Label3D.new()
			l.text = str(z[0])
			l.font_size = 256
			l.outline_size = 0
			l.pixel_size = clampf(largura_anel * 0.75, 1.0, 3.5) / 180.0
			if zonas.size() == 1:
				l.pixel_size = raio * 0.5 / 180.0
			l.modulate = Color(0.95, 0.95, 0.92) if int(z[0]) % 2 == 1 else Color(0.75, 0.1, 0.08)
			if centro:
				l.modulate = Color(0.95, 0.95, 0.92)
			var dir := Vector3.FORWARD.rotated(Vector3.UP, a)
			var p := dir * (0.0 if centro else r_meio)
			# Deitado sobre o disco, com o topo do número apontando para o centro.
			l.basis = Basis.looking_at(Vector3.DOWN, -dir) if not centro else Basis.looking_at(Vector3.DOWN, Vector3.FORWARD)
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
	# [posição na borda, direção para fora, fase da onda]
	var lampadas := []
	if gravata:
		var contorno := _contorno_gravata(BORDA + 0.02)
		var perimetro := 0.0
		for k in contorno.size():
			perimetro += contorno[k].distance_to(contorno[(k + 1) % contorno.size()])
		var s := 0.0
		for k in contorno.size():
			var a: Vector2 = contorno[k]
			var b: Vector2 = contorno[(k + 1) % contorno.size()]
			var d := b - a
			var fora := Vector3(d.y, 0.0, -d.x).normalized()
			if fora.dot(Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)) < 0.0:
				fora = -fora
			var qtd := maxi(int(d.length() / 1.3), 1)
			for i in qtd:
				var q := a + d * ((i + 0.5) / qtd)
				lampadas.append([Vector3(q.x, 0.0, q.y), fora, (s + d.length() * (i + 0.5) / qtd) / perimetro * TAU * 3.0])
			s += d.length()
	else:
		for i in 48:
			var a := TAU * i / 48
			var fora := Vector3(sin(a), 0.0, cos(a))
			lampadas.append([fora * (raio + BORDA + 0.02), fora, a * 3.0])   # três ondas girando em volta
	mm.instance_count = lampadas.size()
	for i in lampadas.size():
		var l: Array = lampadas[i]
		var fora: Vector3 = l[1]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(fora.x, fora.z)), l[0] + Vector3.UP * (-ESPESSURA * 0.5)))
		mm.set_instance_custom_data(i, Color(l[2], 0, 0, 0))
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
	var base_y := -altura - 2.0
	if movel:
		# Alvo móvel: a torre fica em cima de um vagão com rodas de trem sobre trilhos
		base_y = _montar_trem(_chao_em(centro_base.x, centro_base.z) - centro_base.y)
	var cantos := _pernas
	var y_min := INF
	for c: Vector3 in cantos:
		y_min = minf(y_min, _altura_tampo(c))
	for k in cantos.size():
		var c: Vector3 = cantos[k]
		# Cada perna sobe até o tampo acima dela (alvo inclinado: as pernas têm alturas diferentes)
		pecas.append(ComplexoLancamento._viga(Vector3(c.x, base_y, c.z), Vector3(c.x, _altura_tampo(c) - ESPESSURA - 0.2, c.z), 1.4))
		var prox: Vector3 = cantos[(k + 1) % cantos.size()]
		var y := y_min - ESPESSURA - 3.0
		while y > base_y + 3.0:
			pecas.append(ComplexoLancamento._viga(Vector3(c.x, y, c.z), Vector3(prox.x, y, prox.z), 0.6))
			pecas.append(ComplexoLancamento._viga(Vector3(c.x, y, c.z), Vector3(prox.x, y - 8.0, prox.z), 0.4))
			y -= 8.0
	# Tiras de luz presas na face externa de cada perna, do pé até logo abaixo do disco
	var faixas: Array[Transform3D] = []
	for c: Vector3 in cantos:
		var fora := c.normalized() * 0.8
		faixas.append(ComplexoLancamento._viga(Vector3(c.x, base_y + 3.0, c.z) + fora, Vector3(c.x, _altura_tampo(c) - ESPESSURA - 0.6, c.z) + fora, 0.12))
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



## Altura (local) do tampo acima do ponto (x, z): o plano do disco, que pode estar inclinado.
func _altura_tampo(p: Vector3) -> float:
	var n := disco.basis.y.normalized()
	return -(n.x * p.x + n.z * p.z) / maxf(n.y, 0.2)


func _physics_process(delta: float) -> void:
	if not movel or parado:
		velocidade_atual = Vector3.ZERO
		return
	_t += delta
	var nova := _posicao_em(_t)
	velocidade_atual = (nova - position) / delta
	position = nova
	_animar_trem()


# ------------------------------------------------------------------ vagão sobre trilhos (alvo móvel)

const RODA_R := 1.25
const BITOLA := 8.0            # entre os trilhos (m)
const MANIVELA := 0.6          # raio do pino da biela na roda
const BIELA := 3.6            # comprimento da biela (cruzeta → pino)
const RODAS_U := [15.0, 12.0, 9.0, -9.0, -12.0, -15.0]   # posição das rodas ao longo do vagão

var _rodas: Array = []         # [giro (Node3D), u, lado]
var _acopla: Array = []        # [MeshInstance3D, truque (+1/-1), lado]
var _bielas: Array = []        # [MeshInstance3D biela, MeshInstance3D haste, truque, lado]
var _y_eixo := 0.0


## Trilhos enferrujados no chão (fixos) e o vagão que carrega a torre: chassi, 12 rodas de trem
## com raios, contrapeso e pino; barras de acoplamento ligando as rodas de cada truque; bielas e
## cilindros; motor a diesel embaixo do deck com escapamento soltando fumaça.
## Devolve a altura (local) do deck, onde as pernas da torre se apoiam.
func _montar_trem(chao_local: float) -> float:
	_rodas.clear()
	_acopla.clear()
	_bielas.clear()
	var f := direcao_mov
	var lado := f.cross(Vector3.UP).normalized()
	var b := Basis.looking_at(f, Vector3.UP)   # -Z = sentido do movimento, X = lado
	var y_trilho := chao_local + 0.75
	_y_eixo = y_trilho + RODA_R
	var y_deck := _y_eixo + RODA_R + 0.35
	# Ferro velho: vagão verde-oliva desbotado, rodas e raios vermelhos de locomotiva, trilho com
	# boleto polido pelas rodas, aro com banda de rodagem brilhante
	var ferrugem := _mat_ferro(Color(0.2, 0.24, 0.17), 0.6)
	var escuro := _mat_ferro(Color(0.07, 0.07, 0.075), 0.4)
	var vermelho_roda := _mat_ferro(Color(0.5, 0.07, 0.05), 0.45, true)
	var aro_mat := _mat_ferro(Color(0.08, 0.08, 0.085), 0.5, true, false, true)
	var ferro_local := _mat_ferro(Color(0.1, 0.1, 0.1), 0.6, true)
	var trilho_mat := _mat_ferro(Color(0.12, 0.1, 0.09), 0.95, false, true)
	var batente_mat := _mat_ferro(Color(0.55, 0.1, 0.06), 0.55)

	# --- Via: lastro de brita, dormentes de madeira, trilhos em perfil I e para-choques nas pontas
	var via := Node3D.new()
	via.name = "Via"
	via.top_level = true
	add_child(via)
	var comp_via := percurso + 36.0 + 14.0
	var c0 := Vector3(centro_base.x, centro_base.y + chao_local, centro_base.z)
	var brita := ShaderMaterial.new()
	brita.shader = load("res://shaders/brita.gdshader")
	brita.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 91))
	ComplexoLancamento.criar_multimesh(via, [Transform3D(b * Basis.from_scale(Vector3(BITOLA + 5.0, 0.5, comp_via + 2.0)), c0 + Vector3.UP * 0.1)], brita)
	var madeira := ShaderMaterial.new()
	madeira.shader = load("res://shaders/madeira_via.gdshader")
	madeira.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 93))
	madeira.set_shader_parameter("eixo_veio", lado)
	var dormentes: Array[Transform3D] = []
	var n := int(comp_via / 1.1)
	for k in n:
		var u := -comp_via * 0.5 + (k + 0.5) * comp_via / n
		dormentes.append(Transform3D(b * Basis(Vector3.UP, 0.03 * sin(k * 7.1)) * Basis.from_scale(Vector3(BITOLA + 2.6, 0.22, 0.32)), c0 + f * u + Vector3.UP * 0.46))
	ComplexoLancamento.criar_multimesh(via, dormentes, madeira)
	var trilhos: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var p := c0 + lado * s * BITOLA * 0.5
		trilhos.append(Transform3D(b * Basis.from_scale(Vector3(0.24, 0.04, comp_via)), p + Vector3.UP * 0.6))    # patim
		trilhos.append(Transform3D(b * Basis.from_scale(Vector3(0.05, 0.12, comp_via)), p + Vector3.UP * 0.68))   # alma
		trilhos.append(Transform3D(b * Basis.from_scale(Vector3(0.12, 0.08, comp_via)), p + Vector3.UP * 0.71))   # boleto
	ComplexoLancamento.criar_multimesh(via, trilhos, trilho_mat)
	var batentes: Array[Transform3D] = []
	for e: float in [-1.0, 1.0]:
		var p := c0 + f * e * (comp_via * 0.5 - 0.5)
		batentes.append(Transform3D(b * Basis.from_scale(Vector3(BITOLA + 1.5, 0.6, 0.6)), p + Vector3.UP * 1.5))
		for s: float in [-1.0, 1.0]:
			batentes.append(ComplexoLancamento._viga(p + lado * s * BITOLA * 0.5 + Vector3.UP * 0.6, p + lado * s * BITOLA * 0.5 + Vector3.UP * 1.8 - f * e * 0.2, 0.3))
			batentes.append(ComplexoLancamento._viga(p + lado * s * BITOLA * 0.5 + Vector3.UP * 1.6, p + lado * s * BITOLA * 0.5 + Vector3.UP * 0.6 + f * e * 2.2, 0.25))
	ComplexoLancamento.criar_multimesh(via, batentes, batente_mat)
	var vermelho := ComplexoLancamento._material_luz(Color(0.9, 0.08, 0.05), 0.6)
	for e: float in [-1.0, 1.0]:
		var p := c0 + f * e * (comp_via * 0.5 - 0.85) + Vector3.UP * 1.5
		ComplexoLancamento.criar_multimesh(via, [Transform3D(b * Basis.from_scale(Vector3(BITOLA * 0.5, 0.5, 0.05)), p)], vermelho, false)

	# --- Chassi: longarinas, deck de chapa, travessas e vigas de para-choque
	var chassi: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		chassi.append(Transform3D(b * Basis.from_scale(Vector3(0.4, 0.8, 36.0)), lado * s * (BITOLA * 0.5 - 1.1) + Vector3.UP * (_y_eixo + 0.55)))
	chassi.append(Transform3D(b * Basis.from_scale(Vector3(BITOLA + 1.8, 0.35, 36.0)), Vector3.UP * (y_deck - 0.18)))
	for u: float in [-17.5, -6.0, 0.0, 6.0, 17.5]:
		chassi.append(Transform3D(b * Basis.from_scale(Vector3(BITOLA - 0.8, 0.6, 0.4)), f * u + Vector3.UP * (_y_eixo + 0.3)))
	ComplexoLancamento.criar_multimesh(self, chassi, ferrugem)
	var faixas: Array[Transform3D] = []
	for e: float in [-1.0, 1.0]:
		faixas.append(Transform3D(b * Basis.from_scale(Vector3(BITOLA + 1.9, 0.5, 0.08)), f * e * 18.0 + Vector3.UP * (y_deck - 0.3)))
	var listras := ShaderMaterial.new()
	listras.shader = load("res://shaders/listras_perigo.gdshader")
	listras.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 7))
	ComplexoLancamento.criar_multimesh(self, faixas, listras)
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	add_child(corpo)
	ComplexoLancamento.adicionar_colisoes(corpo, chassi)

	# --- Rodas: aro, cubo, 8 raios, contrapeso e pino da manivela (tudo gira junto)
	var aro := CylinderMesh.new()
	aro.top_radius = RODA_R
	aro.bottom_radius = RODA_R
	aro.height = 0.2
	aro.radial_segments = 28
	var cubo := CylinderMesh.new()
	cubo.top_radius = 0.22
	cubo.bottom_radius = 0.22
	cubo.height = 0.36
	var pino := CylinderMesh.new()
	pino.top_radius = 0.09
	pino.bottom_radius = 0.09
	pino.height = 0.42
	var deitado := Basis(Vector3.BACK, PI * 0.5)   # eixo do cilindro (Y) → X
	for u: float in RODAS_U:
		for s: float in [-1.0, 1.0]:
			var pivo := Node3D.new()
			pivo.basis = b
			pivo.position = f * u + lado * s * BITOLA * 0.5 + Vector3.UP * _y_eixo
			add_child(pivo)
			var giro := Node3D.new()
			pivo.add_child(giro)
			var fora := s * signf(b.x.dot(lado))   # +X ou -X local = para fora do vagão
			for par: Array in [[aro, 0.0, aro_mat], [cubo, 0.1, ferro_local], [pino, 0.28, ferro_local]]:
				var mi := MeshInstance3D.new()
				mi.mesh = par[0]
				mi.material_override = par[2]
				mi.basis = deitado
				mi.position = Vector3(fora * par[1], MANIVELA if par[0] == pino else 0.0, 0.0)
				giro.add_child(mi)
			for r in 8:
				var raio_roda := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.07, RODA_R * 1.85, 0.09)
				raio_roda.mesh = bm
				raio_roda.material_override = vermelho_roda
				raio_roda.basis = Basis(Vector3.RIGHT, PI * r / 8.0)
				giro.add_child(raio_roda)
			var contrapeso := MeshInstance3D.new()
			var cp := BoxMesh.new()
			cp.size = Vector3(0.16, 0.32, 0.9)
			contrapeso.mesh = cp
			contrapeso.material_override = vermelho_roda
			contrapeso.position = Vector3(fora * 0.02, -RODA_R * 0.6, 0.0)
			giro.add_child(contrapeso)
			_rodas.append([giro, u, s, pivo, fora])

	# --- Barras de acoplamento (uma por truque e lado) e bielas com cilindro e haste
	for truque: float in [1.0, -1.0]:
		for s: float in [-1.0, 1.0]:
			var barra := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.1, 0.2, 6.7)
			barra.mesh = bm
			barra.material_override = ferrugem
			add_child(barra)
			_acopla.append([barra, truque, s])
			var biela := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(1.0, 1.0, 1.0)
			biela.mesh = bb
			biela.material_override = ferrugem
			add_child(biela)
			var haste := MeshInstance3D.new()
			haste.mesh = bb
			haste.material_override = escuro
			add_child(haste)
			_bielas.append([biela, haste, truque, s])
			# Cilindro fixo no chassi, alinhado com a haste
			var cil := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.34
			cm.bottom_radius = 0.34
			cm.height = 1.7
			cil.mesh = cm
			cil.material_override = escuro
			cil.basis = b * Basis(Vector3.RIGHT, PI * 0.5)
			cil.position = f * truque * 3.4 + lado * s * (BITOLA * 0.5 + 0.35) + Vector3.UP * _y_eixo
			add_child(cil)

	# --- Motor a diesel embaixo do deck, aletas, volante e escapamento com fumaça
	var motor: Array[Transform3D] = []
	motor.append(Transform3D(b * Basis.from_scale(Vector3(BITOLA - 2.2, 1.5, 4.6)), Vector3.UP * (_y_eixo - 0.05)))
	for k in 9:
		motor.append(Transform3D(b * Basis.from_scale(Vector3(BITOLA - 2.0, 1.2, 0.06)), f * (-2.0 + k * 0.5) + Vector3.UP * (_y_eixo + 0.05)))
	ComplexoLancamento.criar_multimesh(self, motor, escuro)
	var escape_base := f * -1.8 + lado * (BITOLA * 0.5 - 1.4) + Vector3.UP * (_y_eixo + 0.6)
	var escape_topo := escape_base + Vector3.UP * (y_deck - _y_eixo + 5.5)
	ComplexoLancamento.criar_multimesh(self, [ComplexoLancamento._viga(escape_base, escape_topo, 0.45)], ferrugem)
	ComplexoLancamento.criar_multimesh(self, [Transform3D(Basis.from_scale(Vector3(0.7, 0.4, 0.7)), escape_topo)], escuro)
	Fogo.fumaca(self, escape_topo + Vector3.UP * 0.3)
	_animar_trem()
	return y_deck


## Gira as rodas pela distância percorrida e move barras de acoplamento e bielas junto.
func _animar_trem() -> void:
	if _rodas.is_empty():
		return
	var d := (position - centro_base).dot(direcao_mov)
	var teta := -d / RODA_R
	var f := direcao_mov
	var lado := f.cross(Vector3.UP).normalized()
	for r: Array in _rodas:
		(r[0] as Node3D).basis = Basis(Vector3.RIGHT, teta)
	# Pino da manivela (mesma fase em todas as rodas): deslocamento a partir do eixo
	var pino_off := Vector3(0.0, cos(teta), 0.0) * MANIVELA
	var fz := sin(teta) * MANIVELA   # componente ao longo de -Z local do pivô = ao longo de f
	for a: Array in _acopla:
		var truque: float = a[1]
		var s: float = a[2]
		var centro := f * truque * 12.0 + lado * s * (BITOLA * 0.5 + 0.32) + Vector3.UP * (_y_eixo + pino_off.y) - f * fz
		(a[0] as MeshInstance3D).transform = Transform3D(Basis.looking_at(f, Vector3.UP), centro)
	for bi: Array in _bielas:
		var truque: float = bi[2]
		var s: float = bi[3]
		var pino := f * (truque * 9.0) + lado * s * (BITOLA * 0.5 + 0.36) + Vector3.UP * (_y_eixo + pino_off.y) - f * fz
		var dy := pino.y - _y_eixo
		var alcance := sqrt(maxf(BIELA * BIELA - dy * dy, 0.01))
		var cruzeta := pino - f * truque * alcance
		cruzeta.y = _y_eixo
		(bi[0] as MeshInstance3D).transform = ComplexoLancamento._viga(cruzeta, pino, 1.0) * Transform3D(Basis.from_scale(Vector3(0.1, 0.24, 1.0)), Vector3.ZERO)
		var cilindro := f * truque * 3.4 + lado * s * (BITOLA * 0.5 + 0.35) + Vector3.UP * _y_eixo
		(bi[1] as MeshInstance3D).transform = ComplexoLancamento._viga(cruzeta, cilindro, 1.0) * Transform3D(Basis.from_scale(Vector3(0.09, 0.09, 1.0)), Vector3.ZERO)


## Ferro de trem (shaders/ferro_trem.gdshader). `local` para peças que giram (rodas).
func _mat_ferro(cor: Color, desgaste: float, local := false, topo := false, banda := false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ferro_trem.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.012, 5, 97))
	m.set_shader_parameter("cor_tinta", cor)
	m.set_shader_parameter("desgaste", desgaste)
	m.set_shader_parameter("local", local)
	m.set_shader_parameter("topo_brilha", topo)
	m.set_shader_parameter("banda_brilha", banda)
	return m


func _material_ferrugem() -> ShaderMaterial:
	var m := _material_torre()
	m.set_shader_parameter("ferrugem", 0.9)
	m.set_shader_parameter("cor_tinta", Color(0.18, 0.11, 0.07))
	return m


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
		if gravata:
			# Faixa pela distância ao longo do comprimento; fora do contorno não conta
			r = absf(local.x)
			if absf(local.z) > _meia_largura(r):
				continue
		for z in zonas:
			if r <= z[1]:
				contagem[z[0]] = contagem.get(z[0], 0) + 1
				break
	var melhor := 0
	var melhor_qtd := 0
	var chaves := contagem.keys()
	chaves.sort()
	for pontos in chaves:
		var q: int = contagem.get(pontos, 0)
		if q > melhor_qtd:
			melhor = pontos
			melhor_qtd = q
	return melhor


## Onde um bot mira (deslocamento no mundo a partir do centro), conforme a habilidade.
## Na gravata o erro é quase todo ao longo do comprimento (a largura no meio é pequena).
func erro_mira(habilidade: float, rng: RandomNumberGenerator) -> Vector3:
	if gravata:
		var e := (1.0 - habilidade) * meio_comp * 0.7
		var lado := eixo.cross(Vector3.UP).normalized()
		return eixo * rng.randf_range(-e, e) + lado * rng.randf_range(-0.4, 0.4) * larg_meio * 0.3
	var erro := (1.0 - habilidade) * raio * 0.8
	return Vector3(rng.randf_range(-erro, erro), 0.0, rng.randf_range(-erro, erro))


# ------------------------------------------------------------------ gravata

## Meia largura da gravata a `u` metros do centro (ao longo do comprimento).
func _meia_largura(u: float) -> float:
	return lerpf(larg_meio, larg_ponta, clampf(u / meio_comp, 0.0, 1.0)) * 0.5


## Contorno (hexágono côncavo) no plano do disco, afastado `margem` para fora.
func _contorno_gravata(margem: float) -> PackedVector2Array:
	var l := meio_comp + margem
	var p := larg_ponta * 0.5 + margem
	var m := larg_meio * 0.5 + margem
	return PackedVector2Array([Vector2(l, p), Vector2(0, m), Vector2(-l, p), Vector2(-l, -p), Vector2(0, -m), Vector2(l, -p)])


## Tampo em gravata: face de cima, de baixo e laterais; colisão em duas metades convexas.
func _montar_gravata() -> void:
	var c := _contorno_gravata(BORDA)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var em := Vector3.UP * -ESPESSURA
	# Metades: [ponta+, meio+, meio-, ponta-] de cada lado (índices do contorno)
	var metades := [[0, 1, 4, 5], [1, 2, 3, 4]]
	for mt: Array in metades:
		var q: Array = mt.map(func(i): return Vector3(c[i].x, 0.0, c[i].y))
		for tri: Array in [[0, 1, 2], [0, 2, 3]]:
			for k: int in tri:
				st.set_normal(Vector3.UP)
				st.add_vertex(q[k])
			for k: int in [tri[0], tri[2], tri[1]]:
				st.set_normal(Vector3.DOWN)
				st.add_vertex(q[k] + em)
		var pontos := PackedVector3Array()
		for v: Vector3 in q:
			pontos.append(v)
			pontos.append(v + em)
		var forma := ConvexPolygonShape3D.new()
		forma.points = pontos
		var cs := CollisionShape3D.new()
		cs.shape = forma
		cs.transform = disco.transform
		add_child(cs)
	for k in c.size():
		var a := Vector3(c[k].x, 0.0, c[k].y)
		var b := Vector3(c[(k + 1) % c.size()].x, 0.0, c[(k + 1) % c.size()].y)
		var n := (b - a).cross(Vector3.UP).normalized()
		if n.dot((a + b) * 0.5) < 0.0:
			n = -n
		for v: Vector3 in [a, b, b + em, a, b + em, a + em]:
			st.set_normal(n)
			st.add_vertex(v)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/alvo_gravata.gdshader")
	mat.set_shader_parameter("faixas", _faixas_pintura())
	mat.set_shader_parameter("divisorias", 0.0 if _liso() else 1.0)
	mat.set_shader_parameter("larg_meio", larg_meio)
	mat.set_shader_parameter("larg_ponta", larg_ponta)
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 3, 17))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	disco.add_child(mi)


## Números pintados no meio de cada faixa, nas duas metades, com o topo virado para o centro.
func _numeros_gravata() -> void:
	var u0 := 0.0
	for z in zonas:
		var u1: float = z[1]
		var meio := 0.0 if z[0] == 5 else (u0 + u1) * 0.5
		var tamanho := minf(u1 - u0 if z[0] != 5 else u1 * 2.0, _meia_largura(meio) * 1.6)
		for s: float in ([1.0] if z[0] == 5 else [1.0, -1.0]):
			var l := Label3D.new()
			l.text = str(z[0])
			l.font_size = 256
			l.outline_size = 0
			l.pixel_size = clampf(tamanho * 0.75, 1.0, 3.5) / 180.0
			l.modulate = Color(0.95, 0.95, 0.92) if int(z[0]) % 2 == 1 else Color(0.75, 0.1, 0.08)
			var dir := Vector3(s, 0.0, 0.0)
			l.basis = Basis.looking_at(Vector3.DOWN, -dir)
			l.position = dir * meio + Vector3.UP * 0.03
			l.double_sided = false
			disco.add_child(l)
		u0 = u1


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
	var metal := _material_torre()
	var concreto := ComplexoLancamento._material_metal(Color(0.5, 0.47, 0.43), 0.0, 0.95)
	var sapatas: Array[Transform3D] = []
	var escada: Array[Transform3D] = []
	for pe: Vector3 in _pernas:
		var c := Vector3(pe.x, chao_local + 0.5, pe.z)
		if not movel:  # no alvo móvel a torre corre sobre o trilho
			sapatas.append(Transform3D(Basis.from_scale(Vector3(3.4, 1.4, 3.4)), c))
	# Escada vertical colada a uma perna, do chão até a borda do disco
	var perna: Vector3 = _pernas[0]
	var fora := Vector3(perna.x, 0.0, perna.z).normalized()
	var lado := fora.cross(Vector3.UP)
	var base := perna + fora * 1.3
	var topo_y := _altura_tampo(base) - ESPESSURA - 0.3
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
		for pe: Vector3 in _pernas:
			if Vector2(local.x - pe.x, local.z - pe.z).length() < 3.0:
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
