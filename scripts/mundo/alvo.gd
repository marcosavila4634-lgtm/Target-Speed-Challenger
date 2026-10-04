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
var _angulo := 0.0
var giro := 0.0                 # rad/s em volta do eixo vertical (Serpent's Climb, etapa 4: a Pedra do Sol gira)
## Parado no fim da etapa: os carros são congelados no resultado e, se o vagão seguisse andando,
## quem estava em cima ficaria flutuando no ar.
var parado := false
var em_fuga := false   # Extinction Day: o helicóptero vai embora na cena do impacto (ImpactoMeteoro o leva)
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

## Forma livre (etapas[].forma = disco, cruz, anel, triangulo) e trajeto (etapas[].trajeto) do
## Frozen Peak: ver _montar_livre e _posicao_trajeto.
var forma := ""
var _livre := false
var _trajeto: Dictionary = {}
var raio_externo := 15.0        # raio do círculo que contém a forma
var raio_mira := 0.0            # anel: raio do meio da faixa (os bots miram ali, não no furo)
var _rotores: Array = []        # [nó, "helice" ou "roda", sentido]
## Extinction Day (AlvoDino): estado do titanossauro, do pêndulo e dos pedaços da pegada
var dino_estado := {}
## Meteoro caído: o alvo é uma bacia côncava (raio e profundidade no meio); 0 = tampo plano.
var bacia_raio := 0.0
var bacia_fundo := 0.0
var _omega := Vector3.ZERO      # velocidade angular do pêndulo (rad/s, eixo no mundo)
const FORMAS_DINO := ["ninho", "sela", "jaula", "pegada", "meteoro"]


func configurar(etapa: Dictionary) -> void:
	if has_meta("aderencia"):
		remove_meta("aderencia")
	add_to_group("alvo")
	collision_layer = 1
	collision_mask = 0
	sync_to_physics = true
	forma = str(etapa.get("forma", ""))
	_trajeto = etapa.get("trajeto", {})
	_livre = forma in ["disco", "cruz", "anel", "triangulo"] or forma in FORMAS_DINO
	dino_estado = {}
	_omega = Vector3.ZERO
	raio_mira = 0.0
	var retangulo := forma == "retangulo"
	gravata = (Config.valor("alvo.forma", "circulo") == "gravata" or retangulo) and not _livre
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
	if _livre:
		# Zona única; `raio` = quanto os bots podem errar a mira sem cair fora da forma
		zonas.clear()
		match forma:
			"cruz": raio = float(etapa.get("largura", 10.0)) * 0.5
			"anel": raio = (float(etapa.get("diametro", 36.0)) - float(etapa.get("furo", 14.0))) * 0.25
			"triangulo": raio = float(etapa.get("lado", 28.0)) / sqrt(3.0) * 0.5
			"ninho", "sela", "jaula", "pegada", "meteoro": raio = AlvoDino.raio_mira(forma, etapa)
			_: raio = float(etapa.get("diametro", 28.0)) * 0.5
		var z_livre: Array = Config.valor("alvo.zonas", [[10, 15.0]])[0]
		zonas.append([int(z_livre[0]), 1000.0])
	var desloc: Array = etapa.get("deslocamento", [0, 0])
	centro_base = Vector3(desloc[0], float(etapa.get("altura", Config.valor("mapa.alvo_altura", 30))), desloc[1])
	transform = Transform3D(Basis.IDENTITY, centro_base)   # (rotation = ZERO depois de position zerava a posição)
	giro = deg_to_rad(float(etapa.get("giro", 0.0)))
	_angulo = 0.0
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
	em_fuga = false
	if _livre:
		movel = not _trajeto.is_empty()
		# direção do vaivém/oito em graus (0 = norte, 90 = oeste)
		direcao_mov = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(float(_trajeto.get("direcao", 0.0))))
		if str(_trajeto.get("tipo", "")) in ["circulo", "tita"]:
			# Carrossel: o tampo gira junto com o braço (fica sempre de frente para a torre)
			giro = -TAU / maxf(float(_trajeto.get("periodo", 30.0)), 1.0)
		transform = Transform3D(Basis.IDENTITY, _posicao_em(0.0))
		reset_physics_interpolation()
		_montar_livre(etapa)
		return
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
	if Config.mapa_selva():
		# Serpent's Climb: o disco é a Pedra do Sol entalhada e pintada
		mat = ShaderMaterial.new()
		mat.shader = load("res://shaders/pedra_sol.gdshader")
		mat.set_shader_parameter("raio", raio + BORDA)
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
		if Config.mapa_egito():
			base_y = _montar_barca(float(Config.valor("mapa.nivel_agua", 4)) - centro_base.y)
		else:
			base_y = _montar_trem(_chao_em(centro_base.x, centro_base.z) - centro_base.y)
	if movel and Config.mapa_egito():
		_colunas_barca(base_y)
		return
	if Config.mapa_selva():
		_pilar_selva()
		return
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


## Velocidade da superfície do alvo no ponto p (deslocamento do alvo móvel + giro da Pedra do Sol).
func velocidade_em(p: Vector3) -> Vector3:
	if _omega != Vector3.ZERO and not parado:
		return velocidade_atual + _omega.cross(p - global_position)
	if giro == 0.0 or parado:
		return velocidade_atual
	return velocidade_atual + Vector3(0.0, giro, 0.0).cross(p - global_position)


func _physics_process(delta: float) -> void:
	if em_fuga:
		return
	if forma == "pegada" and terreno and terreno.dino and terreno.dino.ceu:
		AlvoDino.atualizar_pegada(self, terreno.dino.ceu.progresso, delta)
	if dino_estado.has("heli"):
		AlvoDino.atualizar_heli(self, delta)
	if dino_estado.has("ovos"):
		AlvoDino.atualizar_ovos(self, delta)
	if dino_estado.has("tita") and not parado:
		var d: Dictionary = dino_estado.tita
		# Passada pelo chão percorrido, para os pés não patinarem
		DinosParque.andar(d, (d.raiz as Node3D).global_transform, delta, 0.8, 0.1)
	if str(_trajeto.get("tipo", "")) == "pendulo" and movel and not parado:
		_t += delta
		var nova_p := _posicao_em(_t)
		var periodo := maxf(float(_trajeto.get("periodo", 16.0)), 1.0)
		var amp := deg_to_rad(float(_trajeto.get("amplitude_graus", 18.0)))
		var th := amp * sin(TAU * _t / periodo)
		var lado := direcao_mov.cross(Vector3.UP).normalized()
		_omega = lado * amp * TAU / periodo * cos(TAU * _t / periodo)
		velocidade_atual = (nova_p - position) / delta
		transform = Transform3D(Basis(lado, th), nova_p)
		return
	_omega = Vector3.ZERO
	# Giro e posição montados juntos: rotate_y/rotation neste corpo zeravam a posição (Godot 4.7)
	if giro != 0.0 and not parado:
		_angulo += giro * delta
	if not movel or parado:
		velocidade_atual = Vector3.ZERO
		if giro != 0.0:
			transform = Transform3D(Basis(Vector3.UP, _angulo), centro_base)
		return
	_t += delta
	var nova := _posicao_em(_t)
	velocidade_atual = (nova - position) / delta
	if giro != 0.0:
		transform = Transform3D(Basis(Vector3.UP, _angulo), nova)
	else:
		position = nova
	_animar_trem()
	if _livre:
		_animar_livre(delta)


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
			var giro_no := Node3D.new()
			pivo.add_child(giro_no)
			var fora := s * signf(b.x.dot(lado))   # +X ou -X local = para fora do vagão
			for par: Array in [[aro, 0.0, aro_mat], [cubo, 0.1, ferro_local], [pino, 0.28, ferro_local]]:
				var mi := MeshInstance3D.new()
				mi.mesh = par[0]
				mi.material_override = par[2]
				mi.basis = deitado
				mi.position = Vector3(fora * par[1], MANIVELA if par[0] == pino else 0.0, 0.0)
				giro_no.add_child(mi)
			for r in 8:
				var raio_roda := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.07, RODA_R * 1.85, 0.09)
				raio_roda.mesh = bm
				raio_roda.material_override = vermelho_roda
				raio_roda.basis = Basis(Vector3.RIGHT, PI * r / 8.0)
				giro_no.add_child(raio_roda)
			var contrapeso := MeshInstance3D.new()
			var cp := BoxMesh.new()
			cp.size = Vector3(0.16, 0.32, 0.9)
			contrapeso.mesh = cp
			contrapeso.material_override = vermelho_roda
			contrapeso.position = Vector3(fora * 0.02, -RODA_R * 0.6, 0.0)
			giro_no.add_child(contrapeso)
			_rodas.append([giro_no, u, s, pivo, fora])

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
	if _livre:
		return _posicao_trajeto(t)
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


## Tampo do alvo embaixo do ponto `p` (com o alvo plano e parado, como na comemoração): [ponto na
## superfície, normal]. No disco é a altura do centro_base; na bacia do meteoro acompanha a concavidade.
func tampo_em(p: Vector3) -> Array:
	var q := Vector3(p.x, centro_base.y, p.z)
	if bacia_raio <= 0.0:
		return [q, Vector3.UP]
	var r := Vector2(p.x - centro_base.x, p.z - centro_base.z)
	var d := minf(r.length(), bacia_raio)
	q.y -= bacia_fundo * (1.0 - (d / bacia_raio) * (d / bacia_raio))
	var subida := 2.0 * bacia_fundo * d / (bacia_raio * bacia_raio)   # inclinação para fora do centro
	var fora := r.normalized() if d > 0.01 else Vector2.ZERO
	return [q, Vector3(-fora.x * subida, 1.0, -fora.y * subida).normalized()]


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
	if Config.mapa_egito():
		# Egito: torre pintada de bronze dourado, pouco gasta
		m.set_shader_parameter("ferrugem", 0.12)
		m.set_shader_parameter("cor_tinta", Color(0.62, 0.43, 0.16))
	m.set_shader_parameter("altura_chao", _chao_em(centro_base.x, centro_base.z))
	return m


## Sapatas de concreto nos pés da torre, escada de manutenção e, em volta, pedras e vegetação.
func _arredores() -> void:
	if Config.mapa_selva():
		return   # Serpent's Climb: o pilar de pedra já fica no chão da mata (ou no topo da pirâmide)
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

	if Config.mapa_cidade() or Config.mapa_selva() or (movel and Config.mapa_egito()):
		return   # praça de pedra / barca no Nilo: sem pedras soltas nem mato do deserto
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

# ------------------------------------------------------------------ barca solar (alvo móvel no Nilo)

## Barca do Sol (Pharaoh's Climb, etapa 4: o alvo navega no Nilo), como as barcas solares de Gizé:
## casco longo e esguio pintado em faixas (madeira escura, vermelho, friso creme, lápis-lazúli e borda
## de ouro), proa e popa subindo em curva como feixes de papiro amarrados, com a flor de papiro
## dourada na ponta; convés de tábuas com balaustrada, estrado em degraus, dois pavilhões de colunas,
## remos com pá, lemes grandes na popa e espuma acompanhando o contorno do casco. O disco fica sobre
## colunas douradas no estrado. Sem colisão no casco: quem erra o disco cai no rio.
## Devolve a altura (local) do estrado, onde as colunas do disco se apoiam.
func _montar_barca(agua_local: float) -> float:
	var f := direcao_mov
	var lado := f.cross(Vector3.UP).normalized()
	var b := Basis(lado, Vector3.UP, -f)   # x = lado, -z = proa (sentido do movimento)
	var y_deck := agua_local + 1.8
	var comp := 52.0
	var meia := 8.0
	var ouro := _mat_ouro_barca()
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.46, 0.3, 0.17)
	madeira.roughness = 0.8
	var azul := StandardMaterial3D.new()
	azul.albedo_color = Color(0.07, 0.22, 0.5)
	azul.roughness = 0.5
	var largura := func(u: float) -> float:
		return meia * pow(maxf(1.0 - pow(absf(u), 2.4), 0.0), 0.55)
	var borda_y := func(u: float) -> float:
		return y_deck + 0.8 + 2.6 * pow(absf(u), 3.0)
	var quilha_y := func(u: float) -> float:
		return agua_local - 1.9 * (1.0 - pow(absf(u), 4.0)) + 0.4 * pow(absf(u), 2.0)
	var cor_y := func(y: float, alto: float) -> Color:
		if y < agua_local + 0.15:
			return Color(0.13, 0.09, 0.06)
		if alto > 0.93:
			return Color(1.0, 0.76, 0.32)
		if alto > 0.62:
			return Color(0.08, 0.25, 0.58)
		if alto > 0.56:
			return Color(0.93, 0.86, 0.7)
		return Color(0.52, 0.18, 0.09)
	# Casco: seções em "U" de uma ponta à outra; as pontas afinam até o pé dos postes
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 32
	var m := 10
	var secoes: Array = []
	for i in n + 1:
		var u := lerpf(-1.0, 1.0, float(i) / n)
		var w: float = largura.call(u) + 0.15
		var yb: float = borda_y.call(u)
		var yq: float = quilha_y.call(u)
		var secao: Array = []
		for j in m + 1:
			var a := PI * j / m              # 0 = borda esquerda, PI/2 = quilha, PI = borda direita
			var alto := 1.0 - sin(a)         # 1 na borda, 0 na quilha
			var x := -cos(a) * w * lerpf(0.35, 1.0, pow(alto, 0.5))
			var y := lerpf(yq, yb, pow(alto, 0.8))
			secao.append([Vector3(x, y, u * comp * 0.5), alto])
		secoes.append(secao)
	for i in n:
		for j in m:
			var q := [secoes[i][j], secoes[i][j + 1], secoes[i + 1][j + 1], secoes[i + 1][j]]
			for idx in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = q[idx][0]
				var alto: float = q[idx][1]
				st.set_color(cor_y.call(v.y, alto))
				st.set_normal(b * Vector3(v.x, (v.y - agua_local) * 0.6, 0.0).normalized())
				st.add_vertex(b * v)
	var mat_casco := StandardMaterial3D.new()
	mat_casco.vertex_color_use_as_albedo = true
	mat_casco.roughness = 0.5
	mat_casco.metallic = 0.15
	mat_casco.cull_mode = BaseMaterial3D.CULL_DISABLED
	var casco := MeshInstance3D.new()
	casco.mesh = st.commit()
	casco.material_override = mat_casco
	add_child(casco)
	# Postes de proa e popa: feixe de papiro curvando, amarras de ouro e a flor no alto
	var tubos_madeira: Array[Transform3D] = []
	var tubos_ouro: Array[Transform3D] = []
	for ponta: float in [-1.0, 1.0]:
		var pe := Vector3(0.0, borda_y.call(1.0) - 1.2, ponta * comp * 0.5)
		var pts: Array[Vector3] = []
		for k in 13:
			var s := float(k) / 12.0
			var fora := (4.5 * sin(s * PI * 0.55) - 3.5 * s * s) if ponta < 0.0 else (3.0 * sin(s * PI * 0.5) - 5.5 * s * s * s)
			pts.append(pe + Vector3(0.0, 11.0 * s, ponta * fora))
		for k in 12:
			var r := lerpf(0.95, 0.45, float(k) / 12.0)
			(tubos_ouro if k % 3 == 2 else tubos_madeira).append(_tubo(b * pts[k], b * pts[k + 1], r))
		var dir_t := (pts[12] - pts[11]).normalized()
		var flor := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 1.6
		cone.bottom_radius = 0.35
		cone.height = 2.2
		cone.radial_segments = 16
		flor.mesh = cone
		flor.material_override = ouro
		flor.transform = _tubo(b * (pts[12] - dir_t * 0.1), b * (pts[12] + dir_t * 2.1), 1.0)
		flor.transform.basis = flor.transform.basis.orthonormalized()
		add_child(flor)
	_instancias(_cilindro(), tubos_madeira, madeira, self)
	_instancias(_cilindro(), tubos_ouro, ouro, self)
	# Convés e balaustrada de ouro
	_instancias(BoxMesh.new(), [Transform3D(b * Basis.from_scale(Vector3(meia * 1.8, 0.4, comp * 0.74)), b * Vector3(0.0, y_deck - 0.2, 0.0))], madeira, self)
	var grades: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		for k in 15:
			var u := lerpf(-0.68, 0.68, k / 14.0)
			grades.append(Transform3D(b * Basis.from_scale(Vector3(0.18, 1.1, 0.18)), b * Vector3(s * (largura.call(u) - 0.6), y_deck + 0.55, u * comp * 0.5)))
		for k in 14:
			var u0 := lerpf(-0.68, 0.68, k / 14.0)
			var u1 := lerpf(-0.68, 0.68, (k + 1) / 14.0)
			grades.append(ComplexoLancamento._viga(b * Vector3(s * (largura.call(u0) - 0.6), y_deck + 1.15, u0 * comp * 0.5), b * Vector3(s * (largura.call(u1) - 0.6), y_deck + 1.15, u1 * comp * 0.5), 0.16))
	_instancias(BoxMesh.new(), grades, ouro, self)
	# Estrado em degraus no meio (as colunas do disco ficam em cima)
	var y_estrado := y_deck + 1.2
	_instancias(BoxMesh.new(), [
		Transform3D(b * Basis.from_scale(Vector3(13.0, 0.6, 15.0)), b * Vector3(0.0, y_deck + 0.3, 0.0)),
		Transform3D(b * Basis.from_scale(Vector3(11.0, 0.6, 13.0)), b * Vector3(0.0, y_deck + 0.9, 0.0)),
	], azul, self)
	# Pavilhões na proa e na popa: colunas douradas e teto azul com borda de ouro
	for zc: float in [-comp * 0.3, comp * 0.3]:
		var colunas: Array[Transform3D] = []
		for cx: float in [-2.6, 2.6]:
			for cz: float in [-2.4, 2.4]:
				colunas.append(Transform3D(b * Basis.from_scale(Vector3(0.5, 4.2, 0.5)), b * Vector3(cx, y_deck + 2.1, zc + cz)))
		_instancias(_cilindro(), colunas, ouro, self)
		_instancias(BoxMesh.new(), [Transform3D(b * Basis.from_scale(Vector3(6.8, 0.5, 6.4)), b * Vector3(0.0, y_deck + 4.45, zc))], azul, self)
		_instancias(BoxMesh.new(), [Transform3D(b * Basis.from_scale(Vector3(7.2, 0.25, 6.8)), b * Vector3(0.0, y_deck + 4.8, zc))], ouro, self)
	# Remos com pá e os lemes da popa
	var remos: Array[Transform3D] = []
	var pas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		for k in 10:
			var u := lerpf(-0.55, 0.55, k / 9.0)
			var z := u * comp * 0.5
			var a := b * Vector3(s * (largura.call(u) - 0.3), y_deck + 1.0, z)
			var c := b * Vector3(s * (largura.call(u) + 6.5), agua_local - 0.2, z + 1.2)
			remos.append(ComplexoLancamento._viga(a, c, 0.14))
			pas.append(Transform3D(Basis.looking_at((c - a).normalized(), Vector3.UP) * Basis.from_scale(Vector3(0.12, 0.7, 1.6)), c - (c - a).normalized() * 0.6))
		var poste := b * Vector3(s * 2.2, y_deck + 4.5, comp * 0.4)
		remos.append(ComplexoLancamento._viga(b * Vector3(s * 2.2, y_deck, comp * 0.4), poste, 0.35))
		var pa_leme := b * Vector3(s * 4.2, agua_local - 0.8, comp * 0.5 + 3.0)
		remos.append(ComplexoLancamento._viga(poste, pa_leme, 0.3))
		pas.append(Transform3D(Basis.looking_at((pa_leme - poste).normalized(), Vector3.UP) * Basis.from_scale(Vector3(0.18, 1.4, 3.2)), pa_leme))
	_instancias(BoxMesh.new(), remos, madeira, self)
	_instancias(BoxMesh.new(), pas, azul, self)
	# Espuma em volta da linha d'água (contorno do casco, sumindo para fora)
	var esp := SurfaceTool.new()
	esp.begin(Mesh.PRIMITIVE_TRIANGLES)
	var contorno: Array[Vector3] = []
	for i in 65:
		var ang := TAU * i / 64.0
		var u := sin(ang) * 0.985
		var w: float = largura.call(u) * 0.97 + 0.4
		contorno.append(Vector3(-cos(ang) * w, 0.0, u * comp * 0.5))
	for i in 64:
		var a0 := contorno[i]
		var a1 := contorno[i + 1]
		var o0 := a0 + Vector3(a0.x, 0.0, a0.z * 0.06).normalized() * 1.6
		var o1 := a1 + Vector3(a1.x, 0.0, a1.z * 0.06).normalized() * 1.6
		for par: Array in [[a0, 0.32], [a1, 0.32], [o1, 0.0], [a0, 0.32], [o1, 0.0], [o0, 0.0]]:
			esp.set_color(Color(0.95, 0.97, 1.0, par[1]))
			esp.set_normal(Vector3.UP)
			esp.add_vertex(b * (par[0] as Vector3) + Vector3(0.0, agua_local + 0.06, 0.0))
	var mat_esp := StandardMaterial3D.new()
	mat_esp.vertex_color_use_as_albedo = true
	mat_esp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_esp.cull_mode = BaseMaterial3D.CULL_DISABLED
	var espuma := MeshInstance3D.new()
	espuma.mesh = esp.commit()
	espuma.material_override = mat_esp
	espuma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(espuma)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.7, 0.35)
	luz.light_energy = 3.0
	luz.omni_range = 26.0
	luz.position = Vector3(0.0, y_deck + 6.0, 0.0)
	add_child(luz)
	return y_estrado


## Na barca o disco fica sobre quatro colunas papiriformes douradas (fuste, anéis e capitel em flor)
## que saem do estrado — sem treliça de aço nem tiras de luz.
func _colunas_barca(base_y: float) -> void:
	var ouro := _mat_ouro_barca()
	var fustes: Array[Transform3D] = []
	var aneis: Array[Transform3D] = []
	var capiteis: Array[Transform3D] = []
	for c: Vector3 in _pernas:
		var topo := _altura_tampo(c) - ESPESSURA - 0.1
		fustes.append(Transform3D(Basis.from_scale(Vector3(1.5, topo - base_y, 1.5)), Vector3(c.x, (topo + base_y) * 0.5, c.z)))
		for k in 3:
			aneis.append(Transform3D(Basis.from_scale(Vector3(1.8, 0.3, 1.8)), Vector3(c.x, lerpf(base_y + 1.0, topo - 1.6, k / 2.0), c.z)))
		capiteis.append(Transform3D(Basis.IDENTITY, Vector3(c.x, topo - 0.7, c.z)))
	_instancias(_cilindro(), fustes, ouro, self)
	var azul := StandardMaterial3D.new()
	azul.albedo_color = Color(0.07, 0.22, 0.5)
	_instancias(_cilindro(), aneis, azul, self)
	var flor := CylinderMesh.new()
	flor.top_radius = 1.5
	flor.bottom_radius = 0.75
	flor.height = 1.4
	flor.radial_segments = 16
	_instancias(flor, capiteis, ouro, self)
	var torre := StaticBody3D.new()
	torre.collision_layer = 1
	torre.collision_mask = 0
	torre.add_to_group("estrutura")
	add_child(torre)
	ComplexoLancamento.adicionar_colisoes(torre, fustes)


## Serpent's Climb: o disco (a Pedra do Sol) fica num pilar de pedra entalhado que sobe do chão (ou
## do topo da pirâmide), com base em degraus, anéis de jade e capitel largo embaixo do disco.
func _pilar_selva() -> void:
	var chao := _chao_em(centro_base.x, centro_base.z) - centro_base.y
	var topo := -ESPESSURA - 0.1
	var alto := topo - chao
	var r := clampf(raio * 0.34, 3.0, 6.0)
	var fuste := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = r * 0.85
	cil.bottom_radius = r
	cil.height = alto
	cil.radial_segments = 32
	fuste.mesh = cil
	fuste.material_override = Selva.material_pedra(2, 1.2)
	fuste.position = Vector3(0.0, chao + alto * 0.5, 0.0)
	add_child(fuste)
	var pecas: Array[Transform3D] = []
	for k in 3:
		var w := r * (3.2 - k * 0.55)
		pecas.append(Transform3D(Basis.from_scale(Vector3(w, 1.6, w)), Vector3(0.0, chao + 0.3 + k * 1.6, 0.0)))
	pecas.append(Transform3D(Basis.from_scale(Vector3(r * 2.6, 1.6, r * 2.6)), Vector3(0.0, topo - 0.8, 0.0)))
	pecas.append(Transform3D(Basis.from_scale(Vector3(r * 2.1, 1.2, r * 2.1)), Vector3(0.0, topo - 2.2, 0.0)))
	ComplexoLancamento.criar_multimesh(self, pecas, Selva.material_pedra(0, 0.8))
	var aneis: Array[Transform3D] = []
	var n := maxi(int(alto / 14.0), 1)
	for k in n:
		var y := chao + 6.0 + (alto - 10.0) * (k + 0.5) / n
		var ra := lerpf(r, r * 0.85, (y - chao) / maxf(alto, 1.0)) + 0.35
		aneis.append(Transform3D(Basis.from_scale(Vector3(ra * 2.0, 1.4, ra * 2.0)), Vector3(0.0, y, 0.0)))
	_instancias(_cilindro(), aneis, Selva.material_jade(), self)
	var torre := StaticBody3D.new()
	torre.collision_layer = 1
	torre.collision_mask = 0
	torre.add_to_group("estrutura")
	add_child(torre)
	var cs := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = r
	forma.height = alto
	cs.shape = forma
	cs.position = fuste.position
	torre.add_child(cs)


func _mat_ouro_barca() -> StandardMaterial3D:
	var ouro := StandardMaterial3D.new()
	ouro.albedo_color = Color(1.0, 0.76, 0.32)
	ouro.metallic = 1.0
	ouro.roughness = 0.25
	ouro.emission_enabled = true
	ouro.emission = Color(1.0, 0.7, 0.3)
	ouro.emission_energy_multiplier = 0.2
	return ouro


static func _cilindro() -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.5
	c.bottom_radius = 0.5
	c.height = 1.0
	c.radial_segments = 12
	c.rings = 1
	return c


## Cilindro unitário (eixo y) de `a` até `b` com o raio `r`.
static func _tubo(a: Vector3, b: Vector3, r: float) -> Transform3D:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * r * 2.0, d, z * r * 2.0), (a + b) * 0.5)


# ====================================================================== alvos de forma livre (Frozen Peak)

## Alvo de forma livre (etapas[].forma = disco, cruz, anel ou triangulo) sempre em movimento
## (etapas[].trajeto): o tampo é montado de peças convexas, pintado como uma mosca (anéis vermelhos e
## brancos medidos do centro) e levado por uma máquina que faz sentido para o movimento —
## carrinho sobre cabos (linha), braço de carrossel (circulo), elevador numa torre que passa pelo
## furo do anel (vertical) ou drone de carga (oito).
func _montar_livre(etapa: Dictionary) -> void:
	for f in get_children():
		f.queue_free()
	_rotores.clear()
	disco = Node3D.new()
	disco.name = "Disco"
	add_child(disco)
	var pecas: Array = []        # PackedVector2Array convexos (x, z)
	var contornos: Array = []    # laços fechados para as luzes da borda
	bacia_raio = 0.0
	var dino_f := forma in FORMAS_DINO
	if dino_f:
		var fd := AlvoDino.forma(self, etapa)
		pecas = fd[0]
		contornos = fd[1]
		raio_externo = fd[2]
		dino_estado["quebras"] = etapa.get("quebras", [0.3, 0.55, 0.8])
	if forma == "meteoro":
		bacia_raio = float(etapa.get("bacia", 28.0)) * 0.5
		bacia_fundo = float(etapa.get("fundo", 3.6))
		AlvoDino.montar_meteoro(self, etapa)   # malha e colisão próprias (bacia côncava), sem tampo plano
		return
	if forma == "ninho":
		bacia_raio = float(etapa.get("bacia", 12.0)) * 0.5
		bacia_fundo = float(etapa.get("fundo", 1.6))
		AlvoDino.montar_ninho(self, etapa)     # idem: bacia de palha em cima do pórtico de pedra
		return
	match (forma if not dino_f else "__dino"):
		"__dino":
			pass
		"cruz":
			var l := float(etapa.get("comprimento", 44.0)) * 0.5
			var w := float(etapa.get("largura", 10.0)) * 0.5
			pecas.append(PackedVector2Array([Vector2(-l, -w), Vector2(l, -w), Vector2(l, w), Vector2(-l, w)]))
			pecas.append(PackedVector2Array([Vector2(-w, w), Vector2(w, w), Vector2(w, l), Vector2(-w, l)]))
			pecas.append(PackedVector2Array([Vector2(-w, -l), Vector2(w, -l), Vector2(w, -w), Vector2(-w, -w)]))
			contornos.append(PackedVector2Array([Vector2(-l, -w), Vector2(-w, -w), Vector2(-w, -l), Vector2(w, -l), Vector2(w, -w), Vector2(l, -w),
				Vector2(l, w), Vector2(w, w), Vector2(w, l), Vector2(-w, l), Vector2(-w, w), Vector2(-l, w)]))
			raio_externo = l
		"anel":
			var r1 := float(etapa.get("diametro", 36.0)) * 0.5
			var r0 := float(etapa.get("furo", 14.0)) * 0.5
			var n := 24
			var fora := PackedVector2Array()
			var dentro := PackedVector2Array()
			for k in n:
				var a0 := TAU * k / n
				var a1 := TAU * (k + 1) / n
				pecas.append(PackedVector2Array([Vector2(cos(a0), sin(a0)) * r0, Vector2(cos(a0), sin(a0)) * r1, Vector2(cos(a1), sin(a1)) * r1, Vector2(cos(a1), sin(a1)) * r0]))
				fora.append(Vector2(cos(a0), sin(a0)) * r1)
				dentro.append(Vector2(cos(a0), sin(a0)) * r0)
			contornos.append(fora)
			contornos.append(dentro)
			raio_externo = r1
			raio_mira = (r0 + r1) * 0.5
		"triangulo":
			var r := float(etapa.get("lado", 28.0)) / sqrt(3.0)   # raio do círculo que passa pelas pontas
			var tri := PackedVector2Array()
			for k in 3:
				var a := TAU * k / 3.0
				tri.append(Vector2(cos(a), sin(a)) * r)
			pecas.append(tri)
			contornos.append(tri)
			raio_externo = r
		_:
			var r := float(etapa.get("diametro", 28.0)) * 0.5
			var n := 40 if r < 30.0 else 80
			var circ := PackedVector2Array()
			for k in n:
				circ.append(Vector2(cos(TAU * k / n), sin(TAU * k / n)) * r)
			pecas.append(circ)
			contornos.append(circ)
			raio_externo = r
	# Tampo: face de cima, de baixo e laterais de cada peça + colisão convexa
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var em := Vector3.DOWN * ESPESSURA
	var pedacos: Array = []
	for pol: PackedVector2Array in pecas:
		if forma == "pegada":
			# Pegada: cada pedaço com malha e material próprios (os dedos quebram um a um)
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := pol.size()
		var pts3 := PackedVector3Array()
		for k in n:
			pts3.append(Vector3(pol[k].x, 0.0, pol[k].y))
			pts3.append(Vector3(pol[k].x, 0.0, pol[k].y) + em)
		for k in range(1, n - 1):
			for v: Vector2 in [pol[0], pol[k + 1], pol[k]]:
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(v.x, 0.0, v.y))
			for v: Vector2 in [pol[0], pol[k], pol[k + 1]]:
				st.set_normal(Vector3.DOWN)
				st.add_vertex(Vector3(v.x, 0.0, v.y) + em)
		for k in n:
			var a := Vector3(pol[k].x, 0.0, pol[k].y)
			var b := Vector3(pol[(k + 1) % n].x, 0.0, pol[(k + 1) % n].y)
			var nrm := (b - a).cross(Vector3.UP).normalized()
			var meio := Vector3((pol[0] + pol[n / 2]).x * 0.5, 0.0, (pol[0] + pol[n / 2]).y * 0.5)
			if nrm.dot((a + b) * 0.5 - meio) < 0.0:
				nrm = -nrm
			for v: Vector3 in [a, b, b + em, a, b + em, a + em]:
				st.set_normal(nrm)
				st.add_vertex(v)
		var forma_c := ConvexPolygonShape3D.new()
		forma_c.points = pts3
		var cs := CollisionShape3D.new()
		cs.shape = forma_c
		add_child(cs)
		if forma == "pegada":
			var mp := AlvoDino.material(self) as ShaderMaterial
			var mip := MeshInstance3D.new()
			mip.mesh = st.commit()
			mip.material_override = mp
			disco.add_child(mip)
			var centro := Vector3.ZERO
			for v: Vector2 in pol:
				centro += Vector3(v.x, 0.0, v.y)
			pedacos.append({"mi": mip, "cs": cs, "mat": mp, "centro": centro / pol.size()})
	if forma == "pegada":
		dino_estado["pedacos"] = pedacos
		_luzes_contornos([contornos[0]])
		AlvoDino.suporte(self, etapa)
		return
	var mat: Material
	if dino_f:
		mat = AlvoDino.material(self)
	else:
		var ms := ShaderMaterial.new()
		ms.shader = load("res://shaders/alvo_gelo.gdshader" if bool(etapa.get("gelo", false)) else "res://shaders/alvo_formas.gdshader")
		ms.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 3, 17))
		ms.set_shader_parameter("raio", raio_externo)
		mat = ms
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.set_layer_mask_value(1, true)
	disco.add_child(mi)
	_luzes_contornos(contornos)
	if dino_f:
		AlvoDino.suporte(self, etapa)
		return
	if etapa.has("tubarao"):
		# Frozen Peak, etapa 4 (pedido do dono): o tampo é a língua do megalodonte congelado
		set_meta("aderencia", float(etapa.get("aderencia", 0.3)))
		load("res://scripts/mundo/tubarao_gelo.gd").montar(self, etapa)
		return
	if bool(etapa.get("gelo", false)):
		# Tampo de gelo (pedido do dono): escorrega — o pneu lê a meta "aderencia" do corpo embaixo da roda
		set_meta("aderencia", float(etapa.get("aderencia", 0.15)))
		_suporte_gelo()
		return
	match str(_trajeto.get("tipo", "")):
		"linha": _suporte_cabos()
		"circulo": _suporte_carrossel()
		"vertical": _suporte_elevador()
		"oito": _suporte_drone()
		_: _suporte_elevador()


## Lâmpadas em sequência ao longo dos contornos do tampo (como _luzes_borda, para qualquer forma).
func _luzes_contornos(contornos: Array) -> void:
	var lampadas := []
	for laco: PackedVector2Array in contornos:
		var n := laco.size()
		var perimetro := 0.0
		for k in n:
			perimetro += laco[k].distance_to(laco[(k + 1) % n])
		var s := 0.0
		for k in n:
			var a := laco[k]
			var d := laco[(k + 1) % n] - a
			var fora := Vector3(d.y, 0.0, -d.x).normalized()
			var qtd := maxi(int(d.length() / 1.3), 1)
			for i in qtd:
				var q := a + d * ((i + 0.5) / qtd)
				lampadas.append([Vector3(q.x, 0.0, q.y), fora, (s + d.length() * (i + 0.5) / qtd) / perimetro * TAU * 3.0])
			s += d.length()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var caixa := BoxMesh.new()
	caixa.size = Vector3(0.7, 0.45, 0.24)
	_mat_luzes = ShaderMaterial.new()
	_mat_luzes.shader = load("res://shaders/luz_sequencial.gdshader")
	_mat_luzes.set_shader_parameter("cor", Color(0.3, 0.85, 1.0))
	_mat_luzes.set_shader_parameter("energia", 7.0)
	_mat_luzes.set_shader_parameter("velocidade", 4.0)
	caixa.material = _mat_luzes
	mm.mesh = caixa
	mm.instance_count = lampadas.size()
	for i in lampadas.size():
		var l: Array = lampadas[i]
		var fora: Vector3 = l[1]
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, atan2(fora.x, fora.z)), (l[0] as Vector3) + Vector3.UP * (-ESPESSURA * 0.5)))
		mm.set_instance_custom_data(i, Color(l[2], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	disco.add_child(mmi)


## Alvo de gelo fixo: uma mesa de gelo maciço — o tampo assenta num cogumelo de gelo (bojo largo embaixo
## da borda afinando para uma coluna grossa que desce até o chão), com contrafortes de gelo em volta da
## coluna e pingentes pendurados na beirada. Tudo com colisão.
func _suporte_gelo() -> void:
	var r := raio_externo
	var chao := _chao_em(centro_base.x, centro_base.z) - 3.0
	var y_topo := -ESPESSURA
	var alt := centro_base.y + y_topo - chao
	var bojo_h := minf(alt * 0.45, r * 0.4)
	var gelo_m := Gelo.material(Gelo.Mat.GELO)
	var corpo := _corpo_estrutura(self)
	var pecas := [[r * 0.96, r * 0.34, bojo_h, y_topo - bojo_h * 0.5], [r * 0.34, r * 0.46, alt - bojo_h, y_topo - bojo_h - (alt - bojo_h) * 0.5]]
	for pc: Array in pecas:
		var cil := CylinderMesh.new()
		cil.top_radius = pc[0]
		cil.bottom_radius = pc[1]
		cil.height = pc[2]
		cil.radial_segments = 40
		cil.rings = 3
		var mi := MeshInstance3D.new()
		mi.mesh = cil
		mi.material_override = gelo_m
		mi.position = Vector3(0.0, pc[3], 0.0)
		add_child(mi)
		var cs := CollisionShape3D.new()
		var fc := CylinderShape3D.new()
		fc.radius = minf(pc[0], pc[1]) + absf(float(pc[0]) - float(pc[1])) * 0.35
		fc.height = pc[2]
		cs.shape = fc
		cs.position = Vector3(0.0, pc[3], 0.0)
		corpo.add_child(cs)
	# Contrafortes: lascas de gelo encostadas na coluna, do chão até o bojo
	var lascas: Array = []
	for k in 9:
		var a := TAU * k / 9.0 + 0.3 * sin(k * 2.1)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var h_l := (alt - bojo_h) * (0.55 + 0.35 * absf(sin(k * 1.7)))
		var pe := dir * (r * 0.52) + Vector3.UP * (y_topo - alt)
		var b := Basis(Quaternion(Vector3.UP, (Vector3.UP * h_l - dir * r * 0.16).normalized())) * Basis.from_scale(Vector3(r * 0.13, h_l, r * 0.13))
		lascas.append(Transform3D(b, pe + (Vector3.UP * h_l - dir * r * 0.16) * 0.5))
	Gelo.instancias_gelo(self, lascas, 0.25, 1)
	# Pingentes pendurados na beirada do tampo
	var pingentes: Array = []
	var qtd := int(TAU * r / 3.2)
	for k in qtd:
		var a := TAU * k / qtd
		var h_p := 1.2 + 3.2 * absf(sin(k * 12.9898)) * absf(cos(k * 4.1))
		pingentes.append(Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.5, h_p, 0.5)), Vector3(cos(a), 0.0, sin(a)) * (r - 0.6) + Vector3.UP * (y_topo - h_p * 0.5)))
	Gelo.instancias_gelo(self, pingentes, 0.05, 0, false)


## Nó fixo no mundo (não acompanha o alvo): torres, cabos, pilares.
func _no_fixo() -> Node3D:
	var no := Node3D.new()
	no.name = "Fixo"
	no.top_level = true
	add_child(no)
	no.global_transform = Transform3D.IDENTITY
	return no


func _corpo_estrutura(pai: Node) -> StaticBody3D:
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	pai.add_child(corpo)
	return corpo


## Linha: o tampo vai e volta num carrinho de quatro rodas sobre dois cabos de aço esticados entre
## dois cavaletes de treliça (com o logo do jogo na travessa de cada um).
func _suporte_cabos() -> void:
	var fixo := _no_fixo()
	var f := direcao_mov
	var lado := f.cross(Vector3.UP).normalized()
	var comp := float(_trajeto.get("comprimento", 70.0))
	var meio_vao := comp * 0.5 + raio_externo + 9.0
	var chao := _chao_em(centro_base.x, centro_base.z)
	var y_cabo := centro_base.y - ESPESSURA - 2.4
	var bitola := minf(raio_externo * 0.9, 9.0)
	var aco: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var c0 := Vector3(centro_base.x, 0.0, centro_base.z)
	for e: float in [-1.0, 1.0]:
		var p := c0 + f * e * meio_vao
		var chao_p := _chao_em(p.x, p.z) - 1.0
		for s: float in [-1.0, 1.0]:
			# Cavalete em "A": duas pernas inclinadas por lado
			var topo := Vector3(p.x, y_cabo + 1.2, p.z) + lado * s * bitola
			for perna: float in [-1.0, 1.0]:
				var pe := Vector3(p.x, chao_p, p.z) + lado * s * (bitola + 3.0) + f * perna * 7.0
				aco.append_array(ComplexoLancamento.trelica(pe, topo, 1.6, 4.0, 0.3, 0.12))
				colisao.append(ComplexoLancamento._viga(pe, topo, 1.6))
		var ta := Vector3(p.x, y_cabo + 1.4, p.z) - lado * (bitola + 1.5)
		var tb := Vector3(p.x, y_cabo + 1.4, p.z) + lado * (bitola + 1.5)
		aco.append_array(ComplexoLancamento.trelica(ta, tb, 1.6, 3.0, 0.3, 0.12))
		Gelo.painel_logo(fixo, Vector3(p.x, y_cabo + 5.0, p.z), Basis.looking_at(f * e, Vector3.UP), 3.0, true)
		aco.append(ComplexoLancamento._viga(Vector3(p.x, y_cabo + 2.0, p.z) - lado * bitola * 0.6, Vector3(p.x, y_cabo + 3.4, p.z) - lado * bitola * 0.6, 0.3))
		aco.append(ComplexoLancamento._viga(Vector3(p.x, y_cabo + 2.0, p.z) + lado * bitola * 0.6, Vector3(p.x, y_cabo + 3.4, p.z) + lado * bitola * 0.6, 0.3))
	for s: float in [-1.0, 1.0]:
		var a := c0 - f * meio_vao + lado * s * bitola + Vector3.UP * y_cabo
		var b := c0 + f * meio_vao + lado * s * bitola + Vector3.UP * y_cabo
		aco.append(ComplexoLancamento._viga(a, b, 0.32))
	ComplexoLancamento.criar_multimesh(fixo, aco, Gelo.material(Gelo.Mat.ACO))
	ComplexoLancamento.adicionar_colisoes(_corpo_estrutura(fixo), colisao)
	# Carrinho (acompanha o tampo): chassi, quatro rodas de polia e escoras até o tampo
	var b := Basis(lado, Vector3.UP, -f)
	var y_local := -ESPESSURA - 2.4
	var chassi: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		chassi.append(Transform3D(b * Basis.from_scale(Vector3(0.5, 0.7, raio_externo * 1.3)), lado * s * bitola + Vector3.UP * (y_local + 1.1)))
		for e: float in [-1.0, 1.0]:
			var roda := MeshInstance3D.new()
			var cil := CylinderMesh.new()
			cil.top_radius = 0.75
			cil.bottom_radius = 0.75
			cil.height = 0.4
			cil.radial_segments = 20
			roda.mesh = cil
			roda.material_override = Gelo.material(Gelo.Mat.VERMELHO)
			var pivo := Node3D.new()
			pivo.transform = Transform3D(b, lado * s * bitola + f * e * raio_externo * 0.5 + Vector3.UP * (y_local + 0.75 + 0.16))
			roda.basis = Basis(Vector3.BACK, PI * 0.5)
			pivo.add_child(roda)
			# Raio pintado (dá para ver a roda girando)
			var marca := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.44, 1.3, 0.16)
			marca.mesh = bm
			marca.material_override = Gelo.material(Gelo.Mat.ACO)
			pivo.add_child(marca)
			add_child(pivo)
			_rotores.append([pivo, "roda"])
			chassi.append(ComplexoLancamento._viga(lado * s * bitola + f * e * raio_externo * 0.5 + Vector3.UP * (y_local + 1.4), lado * s * bitola * 0.8 + f * e * raio_externo * 0.4 + Vector3.UP * (-ESPESSURA), 0.4))
	for e: float in [-1.0, 0.0, 1.0]:
		chassi.append(Transform3D(b * Basis.from_scale(Vector3(bitola * 2.0, 0.5, 0.5)), f * e * raio_externo * 0.5 + Vector3.UP * (y_local + 1.1)))
	ComplexoLancamento.criar_multimesh(self, chassi, Gelo.material(Gelo.Mat.ACO))
	# Pilar de referência no chão embaixo do meio do vão (com neon), só visual
	ComplexoLancamento.criar_multimesh(fixo, [Transform3D(Basis.from_scale(Vector3(3.0, 2.0, 3.0)), Vector3(c0.x, chao + 0.5, c0.z))], Gelo.material(Gelo.Mat.BLOCOS))


## Círculo: torre de blocos de gelo no centro e um braço de treliça que gira com o tampo na ponta
## (o tampo fica sempre de frente para a torre), com tirantes do topo da torre e contrapeso.
func _suporte_carrossel() -> void:
	var fixo := _no_fixo()
	var r := float(_trajeto.get("raio", 30.0))
	var chao := _chao_em(centro_base.x, centro_base.z) - 2.0
	var topo := centro_base.y + 16.0
	var c0 := Vector3(centro_base.x, 0.0, centro_base.z)
	var torre: Array[Transform3D] = [Transform3D(Basis.from_scale(Vector3(9.0, topo - chao, 9.0)), c0 + Vector3.UP * (topo + chao) * 0.5)]
	ComplexoLancamento.criar_multimesh(fixo, torre, Gelo.material_blocos(2.0, 4.2))
	ComplexoLancamento.criar_multimesh(fixo, [Transform3D(Basis.from_scale(Vector3(11.0, 2.4, 11.0)), c0 + Vector3.UP * (topo + 1.2))], Gelo.material(Gelo.Mat.NEVE))
	ComplexoLancamento.adicionar_colisoes(_corpo_estrutura(fixo), torre)
	for k in 4:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
		Gelo.painel_logo(fixo, c0 + Vector3.UP * (centro_base.y * 0.55) + dir * 4.75, Basis.looking_at(-dir, Vector3.UP), 2.6)
	# Braço (local: a torre fica em -X a r metros): treliça embaixo do tampo, contrapeso do outro lado
	var y := -ESPESSURA - 1.6
	var aco: Array[Transform3D] = []
	aco.append_array(ComplexoLancamento.trelica(Vector3(-r + 4.5, y, 0.0), Vector3(raio_externo * 0.6, y, 0.0), 2.6, 3.0, 0.3, 0.12))
	aco.append_array(ComplexoLancamento.trelica(Vector3(-r - 4.5, y, 0.0), Vector3(-r - 16.0, y, 0.0), 2.2, 3.0, 0.28, 0.12))
	# Anel de giro em volta da torre e tirantes do alto da torre até o braço
	for s: float in [-1.0, 1.0]:
		aco.append(Transform3D(Basis.from_scale(Vector3(11.0, 2.6, 1.0)), Vector3(-r, y, s * 5.0)))
		aco.append(Transform3D(Basis.from_scale(Vector3(1.0, 2.6, 11.0)), Vector3(-r + s * 5.0, y, 0.0)))
		aco.append(ComplexoLancamento._viga(Vector3(-r + s * 0.01, topo - centro_base.y - 1.0, 0.0), Vector3(-r * 0.25 if s > 0.0 else -r - 15.0, y + 1.3, 0.0), 0.22))
	for z: float in [-1.0, 1.0]:
		aco.append(ComplexoLancamento._viga(Vector3(-raio_externo * 0.2, y + 1.2, 0.0), Vector3(0.0, -ESPESSURA, z * raio_externo * 0.45), 0.4))
	ComplexoLancamento.criar_multimesh(self, aco, Gelo.material(Gelo.Mat.ACO))
	ComplexoLancamento.criar_multimesh(self, [Transform3D(Basis.from_scale(Vector3(5.0, 4.0, 5.0)), Vector3(-r - 17.0, y - 0.6, 0.0))], Gelo.material(Gelo.Mat.VERMELHO))


## Vertical: torre de treliça que passa pelo furo do anel; o tampo sobe e desce por ela preso a uma
## gola com roletes e quatro escoras. Baliza e o logo no alto da torre.
func _suporte_elevador() -> void:
	var fixo := _no_fixo()
	var amp := float(_trajeto.get("amplitude", 0.0))
	var chao := _chao_em(centro_base.x, centro_base.z) - 2.0
	var topo := centro_base.y + amp * 0.5 + 16.0
	var c0 := Vector3(centro_base.x, 0.0, centro_base.z)
	var lado_t := 6.0
	var aco: Array[Transform3D] = []
	aco.append_array(ComplexoLancamento.trelica(c0 + Vector3.UP * chao, c0 + Vector3.UP * topo, lado_t, 5.0, 0.5, 0.2))
	ComplexoLancamento.criar_multimesh(fixo, aco, Gelo.material(Gelo.Mat.ACO))
	ComplexoLancamento.criar_multimesh(fixo, [Transform3D(Basis.from_scale(Vector3(lado_t + 5.0, 3.0, lado_t + 5.0)), c0 + Vector3.UP * (chao + 2.5))], Gelo.material(Gelo.Mat.BLOCOS))
	ComplexoLancamento.criar_multimesh(fixo, [Transform3D(Basis.from_scale(Vector3(lado_t + 1.0, 5.0, lado_t + 1.0)), c0 + Vector3.UP * (topo + 2.5))], Gelo.material(Gelo.Mat.VERMELHO))
	for k in 4:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
		Gelo.painel_logo(fixo, c0 + Vector3.UP * (topo + 2.5) + dir * (lado_t * 0.5 + 0.8), Basis.looking_at(-dir, Vector3.UP), 1.7)
	# Cremalheira iluminada nas quatro quinas
	var neon: Array[Transform3D] = []
	for qx: float in [-1.0, 1.0]:
		for qz: float in [-1.0, 1.0]:
			neon.append(Transform3D(Basis.from_scale(Vector3(0.25, topo - chao, 0.25)), c0 + Vector3(qx, 0.0, qz) * (lado_t * 0.5 + 0.3) + Vector3.UP * (topo + chao) * 0.5))
	ComplexoLancamento.criar_multimesh(fixo, neon, Gelo.material(Gelo.Mat.NEON), false)
	var corpo := _corpo_estrutura(fixo)
	ComplexoLancamento.adicionar_colisoes(corpo, [Transform3D(Basis.from_scale(Vector3(lado_t, topo - chao + 5.0, lado_t)), c0 + Vector3.UP * (topo + chao + 5.0) * 0.5)])
	# Gola (acompanha o tampo): quadro em volta da torre, roletes e escoras até o tampo
	var gola: Array[Transform3D] = []
	var y := -ESPESSURA - 5.0
	var m := lado_t * 0.5 + 1.2
	for s: float in [-1.0, 1.0]:
		gola.append(Transform3D(Basis.from_scale(Vector3(m * 2.0 + 0.8, 1.0, 0.8)), Vector3(0.0, y, s * m)))
		gola.append(Transform3D(Basis.from_scale(Vector3(0.8, 1.0, m * 2.0 + 0.8)), Vector3(s * m, y, 0.0)))
		gola.append(Transform3D(Basis.from_scale(Vector3(m * 2.0 + 0.8, 0.8, 0.8)), Vector3(0.0, -ESPESSURA - 0.5, s * m)))
		gola.append(Transform3D(Basis.from_scale(Vector3(0.8, 0.8, m * 2.0 + 0.8)), Vector3(s * m, -ESPESSURA - 0.5, 0.0)))
	var r_apoio := maxf(raio_mira, raio_externo * 0.6)
	for k in 8:
		var a := TAU * k / 8.0 + PI / 8.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		gola.append(ComplexoLancamento._viga(dir * (m + 0.3) + Vector3.UP * y, dir * r_apoio + Vector3.UP * (-ESPESSURA), 0.45))
	ComplexoLancamento.criar_multimesh(self, gola, Gelo.material(Gelo.Mat.ACO))
	for k in 4:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * PI * 0.5)
		var rolete := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = 0.6
		cil.bottom_radius = 0.6
		cil.height = 1.6
		rolete.mesh = cil
		rolete.material_override = Gelo.material(Gelo.Mat.VERMELHO)
		rolete.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir.cross(Vector3.UP).normalized())), dir * (lado_t * 0.5 + 0.65) + Vector3.UP * y)
		add_child(rolete)


## Oito: drone de carga — corpo de aço embaixo do tampo, braços até rotores com aro (hélices
## girando e brilho azul dos propulsores), luzes de navegação e o logo nas laterais do corpo.
func _suporte_drone() -> void:
	var y := -ESPESSURA - 1.6
	var aco: Array[Transform3D] = []
	aco.append(Transform3D(Basis.from_scale(Vector3(raio_externo * 0.7, 2.6, raio_externo * 0.7)), Vector3(0.0, y, 0.0)))
	var n_rot := 3 if forma == "triangulo" else 4
	var aro := TorusMesh.new()
	aro.inner_radius = 3.0
	aro.outer_radius = 3.5
	var brilho := CylinderMesh.new()
	brilho.top_radius = 2.9
	brilho.bottom_radius = 2.2
	brilho.height = 0.5
	for k in n_rot:
		var a := TAU * k / n_rot + (PI / 3.0 if forma == "triangulo" else PI * 0.25)   # no triângulo: no meio dos lados
		var dir := Vector3(cos(a), 0.0, sin(a))
		var alcance := (raio_externo * 0.5 + 5.2) if forma == "triangulo" else raio_externo + 4.5
		var centro := dir * alcance + Vector3.UP * (y - 0.4)
		aco.append_array(ComplexoLancamento.trelica(dir * raio_externo * 0.3 + Vector3.UP * y, centro - dir * 3.2, 1.4, 2.4, 0.2, 0.09))
		var mi := MeshInstance3D.new()
		mi.mesh = aro
		mi.material_override = Gelo.material(Gelo.Mat.VERMELHO)
		mi.position = centro
		add_child(mi)
		var helice := Node3D.new()
		helice.position = centro
		add_child(helice)
		for p in 3:
			var pa := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(5.6, 0.1, 0.55)
			pa.mesh = bm
			pa.material_override = Gelo.material(Gelo.Mat.ACO)
			pa.basis = Basis(Vector3.UP, TAU * p / 3.0 * 0.5)
			helice.add_child(pa)
		_rotores.append([helice, "helice", 1.0 if k % 2 == 0 else -1.0])
		var jato := MeshInstance3D.new()
		jato.mesh = brilho
		jato.material_override = ComplexoLancamento._material_luz(Color(0.3, 0.8, 1.0), 4.0)
		jato.position = centro + Vector3.DOWN * 0.9
		jato.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(jato)
		# Luz de navegação na ponta de cada braço (vermelha/verde)
		var nav := MeshInstance3D.new()
		var esf := SphereMesh.new()
		esf.radius = 0.4
		esf.height = 0.8
		nav.mesh = esf
		nav.material_override = ComplexoLancamento._material_luz(Color(1.0, 0.1, 0.05) if k % 2 == 0 else Color(0.15, 1.0, 0.3), 8.0)
		nav.position = centro + dir * 3.6
		add_child(nav)
	ComplexoLancamento.criar_multimesh(self, aco, Gelo.material(Gelo.Mat.ACO))
	for k in 2:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, k * PI)
		Gelo.painel_logo(self, dir * (raio_externo * 0.35 + 0.3) + Vector3.UP * y, Basis.looking_at(-dir, Vector3.UP), 1.7)
	# Trem de pouso (só enfeite) e antena
	var pes: Array[Transform3D] = []
	for k in 4:
		var a := TAU * k / 4.0 + PI * 0.25
		var dir := Vector3(cos(a), 0.0, sin(a))
		pes.append(ComplexoLancamento._viga(dir * raio_externo * 0.3 + Vector3.UP * (y - 1.0), dir * raio_externo * 0.42 + Vector3.UP * (y - 4.0), 0.3))
	ComplexoLancamento.criar_multimesh(self, pes, Gelo.material(Gelo.Mat.VERMELHO))


## Gira hélices do drone e rodas do carrinho dos cabos.
func _animar_livre(delta: float) -> void:
	for r: Array in _rotores:
		var no: Node3D = r[0]
		if r[1] == "helice":
			no.rotate_y(delta * 26.0 * float(r[2]))
		else:
			no.rotate_object_local(Vector3.RIGHT, -velocidade_atual.dot(direcao_mov) / 0.75 * delta)


## Posição do alvo de forma livre no instante t, conforme o trajeto da etapa.
func _posicao_trajeto(t: float) -> Vector3:
	var periodo := maxf(float(_trajeto.get("periodo", 30.0)), 1.0)
	var a := TAU * t / periodo
	match str(_trajeto.get("tipo", "")):
		"linha":
			return centro_base + direcao_mov * float(_trajeto.get("comprimento", 70.0)) * 0.5 * sin(a)
		"circulo":
			var r := float(_trajeto.get("raio", 30.0))
			return centro_base + Vector3(cos(a), 0.0, sin(a)) * r
		"vertical":
			return centro_base + Vector3.UP * float(_trajeto.get("amplitude", 40.0)) * 0.5 * sin(a)
		"geiser":
			# Gêiser: sobe e desce irregular (empurrões da lava)
			return centro_base + Vector3.UP * float(_trajeto.get("amplitude", 30.0)) * 0.5 * (0.75 * sin(a) + 0.25 * sin(3.0 * a + 1.3))
		"tita":
			var rt := float(_trajeto.get("raio", 40.0))
			return centro_base + Vector3(cos(a), 0.0, sin(a)) * rt
		"pendulo":
			var rp := float(_trajeto.get("raio", 70.0))
			var th := deg_to_rad(float(_trajeto.get("amplitude_graus", 18.0))) * sin(a)
			return centro_base + Vector3.UP * rp + (direcao_mov * sin(th) - Vector3.UP * cos(th)) * rp
		"oito":
			var lado := direcao_mov.cross(Vector3.UP).normalized()
			return centro_base + direcao_mov * float(_trajeto.get("comprimento", 80.0)) * 0.5 * sin(a) + lado * float(_trajeto.get("largura", 36.0)) * 0.5 * sin(2.0 * a)
	return centro_base
