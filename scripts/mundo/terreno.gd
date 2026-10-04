class_name Terreno
extends Node3D
## Cânion gerado por código: mesas em degraus, rio sinuoso, corredores de voo livres
## e mesas sob as plataformas de lançamento. O terreno é mortal: tocar nele elimina o veículo,
## por isso não há colisão física — a checagem é feita por altura (altura_em).

const MEIO_INTERNO := 3400.0
const N_INTERNO := 513
const MEIO_EXTERNO := 14000.0
const N_EXTERNO := 257
const VERSAO_CACHE := 22

var perfil: PerfilRampa
var distancia_saida: float
var alturas_interno := PackedFloat32Array()
var alturas_externo := PackedFloat32Array()

var _ruido_base := FastNoiseLite.new()
var _ruido_detalhe := FastNoiseLite.new()
var _ruido_planalto := FastNoiseLite.new()
var _direcoes: Array[Vector2] = []   # do alvo para cada complexo de lançamento
var _topo_mesa := 395.0
var _meia_arena := 0.0   # na arena o pedestal é largo: o terreno fica abaixo dele numa faixa maior
var _desvio_rio := 0.0
var _canion_fechado := false
var _canion_altura := 380.0
var _canion_largura_rampa := 55.0
var _vale_largura := [230.0, 320.0, 400.0]   # meia-largura na saída, no meio e no alvo
var _vale_fundo := 380.0                       # até onde o vale vai atrás do alvo
var _esporoes: Array = []                      # [base, ponta, raio na base, raio na ponta] (coordenadas do vale)
var _rota_vale: Array[Vector2] = []
## Altura (m) de cada ponto da rota, 0 = livre (Frozen Peak: janelas das muralhas de gelo)
var _rota_alt := PackedFloat32Array()
## Rotas de voo alternativas da etapa (montanhas.etapas.N.rotas_alt: listas de [x, z, altura]): Vector3(x, altura, z)
var rotas_alt: Array = []
var _etapa_vale := -1
var _malha_interna: MeshInstance3D
var _mat_terreno: ShaderMaterial
var _veg_vale: Node3D
# Climb to Death (mapa tipo "subida"): vale plano quase ao nível do mar, montanhas em volta e o morro
var _modo_subida := false
var _sub_vale := [-1800.0, -1350.0, 450.0, 500.0]
var _sub_morro := {}
var _sub_estrada: Array = []   # trechos da estrada (pontos de controle) para a vegetação não atravessar
## Amostras da estrada ao alcance do morro (mapa.subida.morro.encosta_alcance): o morro cresce até
## elas. Cada uma: [posição xz, altura, tangente xz, distância à crista, metros até a ponta do trecho]
var _sub_encosta: Array = []
## Cristas atravessando o caminho da rampa final ao alvo (mapa.subida.barreiras), sorteadas por etapa:
## cada uma {a: início xz, d: direção, n: normal para o alvo, comp, fendas: [metros desde a]}
var _sub_barreiras: Array = []
var _sub_barreiras_cfg: Dictionary = {}
## Montanhas desenhadas pelo dono (mapa.subida.montanhas): cápsulas [a, b, raio_a, raio_b, altura]
var _sub_fixas: Array = []       # em todas as etapas
var _sub_montanhas: Array = []   # só da etapa atual (no lugar das cristas sorteadas)
## Túnel-atalho da etapa (montanhas.etapas.N.tunel): o terreno é cavado ao longo dele (o túnel em si
## é estrutura, ver TunelAtalho). A malha tem um ponto a cada ~13 m, então a vala é bem mais larga
## que o túnel: a interpolação não pode subir dentro dele (tocar o terreno explode o carro).
var _sub_tunel: Dictionary = {}
const MEIA_VALA_TUNEL := 30.0
## Paredão fino com buraco de atalho da etapa (montanhas.etapas.N.paredao; estrutura, ver
## ParedaoFino) e se a etapa tira o morro (sem_morro: o desenho da etapa 4 ocupa o lugar dele).
var _sub_paredao: Dictionary = {}
var _sub_estrada_extra: Dictionary = {}   # trecho de estrada extra da etapa (ver ComplexoSubida)
var _sem_morro := false
## Sem o morro, a encosta dele continua colada na estrada como uma muralha desta espessura (m,
## medida da beirada da estrada; montanhas.etapas.N.muralha_estrada). 0 = sem muralha.
var _muralha_estrada := 0.0
var _veg_subida: Node3D
## A malha de longe tem um ponto a cada ~110 m: um pináculo nela vira um cone pontudo, então lá não tem
var _amostrando_externo := false
# City Rush (Config.mapa_cidade): chão plano de ruas e prédios no lugar das mesas (ver Cidade)
var _modo_cidade := false
var cidade: Cidade
# Pharaoh's Climb (Config.mapa_egito): deserto, Nilo, pirâmides e obeliscos (ver Egito)
var _modo_egito := false
var egito: Egito
# Serpent's Climb (Config.mapa_selva): selva, templos, rio e cachoeira (ver Selva)
var _modo_selva := false
var selva: Selva
# Frozen Peak (Config.mapa_gelo): montanhas nevadas, lago congelado e estruturas de gelo (ver Gelo)
var _modo_gelo := false
var gelo: Gelo
# Extinction Day (Config.mapa_dino): selva de árvores gigantes, vulcão com túnel e lava (ver Dino)
var _modo_dino := false
var dino: Dino
const CHAO_CIDADE := 6.0


func gerar(p_perfil: PerfilRampa) -> void:
	perfil = p_perfil
	distancia_saida = Config.valor("mapa.distancia_saida_alvo", 2000)
	_direcoes = Terreno.direcoes_lancamento()
	_topo_mesa = float(Config.valor("mapa.plataforma_altura", 400)) - float(Config.valor("mapa.rebaixo_mesa", 5))
	_meia_arena = float(Config.valor("arena.largura", 0)) * 0.5 if Config.mapa_arena() else 0.0
	_desvio_rio = float(Config.valor("mapa.rio_deslocamento", 0.0))
	_canion_fechado = bool(Config.valor("mapa.canion_fechado", false))
	_canion_altura = float(Config.valor("mapa.canion_altura", 380))
	_canion_largura_rampa = float(Config.valor("mapa.canion_meia_largura_rampa", 55))
	var larg: Array = Config.valor("mapa.canion_layout.meia_largura", [230, 320, 400])
	_vale_largura = [float(larg[0]), float(larg[1]), float(larg[2])]
	_vale_fundo = float(Config.valor("mapa.canion_layout.fundo_atras_alvo", 380))
	if _canion_fechado:
		_sortear_vale(0)
	_modo_subida = Config.mapa_tipo() == "subida"
	if _modo_subida:
		var v: Array = Config.valor("mapa.subida.vale", _sub_vale)
		_sub_vale = [float(v[0]), float(v[1]), float(v[2]), float(v[3])]
		_sub_morro = Config.valor("mapa.subida.morro", {})
		for nome in ["A", "B", "C"]:
			_sub_estrada.append(ComplexoSubida.pontos_trecho(nome))
		_preparar_encosta()
		_sub_barreiras_cfg = Config.valor("mapa.subida.barreiras", {})
		_sub_fixas = _capsulas(Config.valor("mapa.subida.montanhas.fixas", []))
		if not _sub_barreiras_cfg.is_empty():
			_sortear_barreiras(0)
	var semente: int = int(Config.valor("mapa.semente_terreno", 1967))
	_ruido_base.seed = semente
	_ruido_base.frequency = 1.0 / 1500.0
	_ruido_base.fractal_octaves = 4
	_ruido_detalhe.seed = semente + 11
	_ruido_detalhe.frequency = 1.0 / 260.0
	_ruido_detalhe.fractal_octaves = 3
	_ruido_planalto.seed = semente + 29
	_ruido_planalto.frequency = 1.0 / 900.0
	_modo_egito = Config.mapa_egito()
	if _modo_egito:
		egito = Egito.new()
		egito.name = "Egito"
		add_child(egito)
		egito.preparar(self)
	_modo_selva = Config.mapa_selva()
	if _modo_selva:
		selva = Selva.new()
		selva.name = "Selva"
		add_child(selva)
		selva.preparar(self)
	_modo_gelo = Config.mapa_gelo()
	if _modo_gelo:
		gelo = Gelo.new()
		gelo.name = "Gelo"
		add_child(gelo)
		gelo.preparar(self)
	_modo_dino = Config.mapa_dino()
	if _modo_dino:
		dino = Dino.new()
		dino.name = "Dino"
		add_child(dino)
		dino.preparar(self)
	_modo_cidade = Config.mapa_cidade()
	if _modo_cidade:
		cidade = Cidade.new()
		add_child(cidade)
		cidade.gerar(self, CHAO_CIDADE)

	if not _carregar_cache():
		alturas_interno = _amostrar(MEIO_INTERNO, N_INTERNO, false)
		alturas_externo = _amostrar(MEIO_EXTERNO, N_EXTERNO, true)
		_salvar_cache()

	# Conferência das passagens da parte final (TSC_MAPA_ASCII=<etapa>): mapa de alturas em texto
	if OS.get_environment("TSC_MAPA_ASCII") != "" and _modo_subida:
		_sortear_barreiras(int(OS.get_environment("TSC_MAPA_ASCII")) - 1)
		print("[MAPA] x de 600 (esq) a -400 (dir); # > 200 m, + > 80 m, T tunel, . livre")
		for z in range(-1000, 320, 20):
			var linha := "%5d " % z
			for x in range(600, -420, -20):
				var h := _altura_procedural(float(x), float(z))
				linha += "#" if h > 200.0 else ("+" if h > 80.0 else ("T" if not _sub_tunel.is_empty() and h < 170.0 and _altura_subida_sem_tunel(float(x), float(z)) > 200.0 else "."))
			print("[MAPA] ", linha)
		_sortear_barreiras(0)
	_mat_terreno = _material_terreno()
	_malha_interna = _criar_malha(alturas_interno, MEIO_INTERNO, N_INTERNO, _mat_terreno)
	add_child(_malha_interna)
	add_child(_criar_malha(alturas_externo, MEIO_EXTERNO, N_EXTERNO, _mat_terreno))
	_criar_agua()
	if _modo_cidade:
		return   # sem vegetação do deserto nem bruma de cânion
	if _modo_selva:
		selva.montar()   # templos, mata, cachoeira e bichos
		return
	if _modo_gelo:
		gelo.montar()   # fortalezas de gelo, vilas, pinheiros nevados, neve caindo
		return
	if _modo_dino:
		dino.montar()   # vulcão, lava, árvores gigantes, parque e dinossauros
		return
	if _modo_egito:
		egito.montar()   # palmeiras, pirâmides, obeliscos, templos (sem zimbros nem bruma de cânion)
		return
	_criar_vegetacao()
	if _canion_fechado:
		_criar_vegetacao_vale()
	if _modo_subida:
		_criar_vegetacao_subida()
	if Config.valor("grafico.bruma", true):
		_criar_bruma()


## Direções (do alvo para cada complexo) dos corredores de voo: uma por equipe, ou só a da arena.
static func direcoes_lancamento() -> Array[Vector2]:
	var lista: Array[Vector2] = []
	if Config.mapa_tipo() == "subida":
		lista.append(Vector2(0.0, -1.0))   # a rampa final fica ao norte do alvo
		return lista
	if Config.mapa_arena():
		var a: Array = Config.valor("arena.direcao", [0, -1])
		lista.append(Vector2(float(a[0]), float(a[1])).normalized())
		return lista
	for eq in Config.EQUIPES:
		lista.append(Vector2(eq.direcao.x, eq.direcao.z))
	return lista


## Altura do terreno no ponto (x, z) do mundo.
## No City Rush inclui os prédios (telhado = chão; bater na fachada = bater no terreno).
func altura_em(x: float, z: float) -> float:
	var h: float
	if absf(x) < MEIO_INTERNO and absf(z) < MEIO_INTERNO:
		h = _bilinear(alturas_interno, MEIO_INTERNO, N_INTERNO, x, z)
	else:
		h = _bilinear(alturas_externo, MEIO_EXTERNO, N_EXTERNO, x, z)
	if cidade:
		h = maxf(h, cidade.altura(x, z))
	if egito:
		h = maxf(h, egito.altura(x, z))
	if selva:
		h = maxf(h, selva.altura(x, z))
	if gelo:
		h = maxf(h, gelo.altura(x, z))
	if dino:
		h = maxf(h, dino.altura(x, z))
	return h


func _bilinear(dados: PackedFloat32Array, meio: float, n: int, x: float, z: float) -> float:
	var passo := meio * 2.0 / (n - 1)
	var fx := clampf((x + meio) / passo, 0.0, n - 1.001)
	var fz := clampf((z + meio) / passo, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(dados[iz * n + ix], dados[iz * n + ix + 1], tx)
	var b := lerpf(dados[(iz + 1) * n + ix], dados[(iz + 1) * n + ix + 1], tx)
	return lerpf(a, b, tz)


func _amostrar(meio: float, n: int, externo: bool) -> PackedFloat32Array:
	var dados := PackedFloat32Array()
	dados.resize(n * n)
	var passo := meio * 2.0 / (n - 1)
	_amostrando_externo = externo
	for iz in n:
		var z := -meio + iz * passo
		for ix in n:
			var x := -meio + ix * passo
			if externo and absf(x) < MEIO_INTERNO - 120.0 and absf(z) < MEIO_INTERNO - 120.0:
				dados[iz * n + ix] = -60.0  # escondido sob o terreno interno
			else:
				dados[iz * n + ix] = _altura_procedural(x, z)
	_amostrando_externo = false
	if externo:
		dados = _abrir(dados, n)
	return dados


## Abertura morfológica 3x3 (erosão e depois dilatação) na malha de longe: com um ponto a cada
## ~110 m, morro menor que 3 pontos virava pirâmide. Some o que é fino e os topos ficam planos.
## Os pontos escondidos sob o terreno interno (-60) não entram na erosão.
static func _abrir(dados: PackedFloat32Array, n: int) -> PackedFloat32Array:
	var erodido := dados.duplicate()
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			if dados[i] <= -60.0:
				continue
			var m := dados[i]
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var jx := ix + dx
					var jz := iz + dz
					if jx >= 0 and jz >= 0 and jx < n and jz < n and dados[jz * n + jx] > -60.0:
						m = minf(m, dados[jz * n + jx])
			erodido[i] = m
	var aberto := erodido.duplicate()
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			if dados[i] <= -60.0:
				continue
			var m := erodido[i]
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var jx := ix + dx
					var jz := iz + dz
					if jx >= 0 and jz >= 0 and jx < n and jz < n and dados[jz * n + jx] > -60.0:
						m = maxf(m, erodido[jz * n + jx])
			aberto[i] = m
	return aberto


func _altura_procedural(x: float, z: float) -> float:
	if _modo_subida:
		return _altura_subida(x, z)
	if _modo_cidade:
		return _altura_cidade(x, z)
	var nb := _ruido_base.get_noise_2d(x, z)
	var nd := _ruido_detalhe.get_noise_2d(x, z)
	# Mesas em degraus: platôs planos separados por paredões.
	var mesa := smoothstep(-0.12, 0.22, nb + nd * 0.3)
	var s := mesa * 3.0
	var f := floorf(s)
	var r := smoothstep(0.55, 1.0, s - f)
	var t := (f + r) / 3.0
	var h_planalto := 320.0 + 55.0 * _ruido_planalto.get_noise_2d(x, z)
	var h := t * h_planalto + 10.0 + 6.0 * nd
	h = maxf(h, _pinaculos(x, z))

	# Rio sinuoso no fundo do cânion.
	var x_rio := -170.0 + _desvio_rio + 260.0 * sin(z / 760.0) + 90.0 * sin(z / 230.0 + 1.3)
	var d_rio := absf(x - x_rio)
	h = minf(h, lerpf(-7.0, h, smoothstep(10.0, 55.0, d_rio)))
	h = minf(h, lerpf(3.0, h, smoothstep(55.0, 230.0, d_rio)))

	# Área aberta ao redor do alvo.
	var r_centro := Vector2(x, z).length()
	h = minf(h, lerpf(8.0, h, smoothstep(420.0, 750.0, r_centro)))

	# Corredores de voo e complexos de lançamento de cada equipe.
	var xe := perfil.comprimento_horizontal
	var x_borda := perfil.pontos[perfil.indice_borda].x
	var p := Vector2(x, z)
	for dir in _direcoes:
		var ao_longo := p.dot(dir)
		if ao_longo < 0.0:
			continue
		var lateral := absf(p.dot(Vector2(-dir.y, dir.x)))
		if ao_longo < distancia_saida:
			var teto := lerpf(15.0, 90.0, ao_longo / distancia_saida)
			h = minf(h, lerpf(teto, h, smoothstep(230.0, 500.0, lateral)))
		# Sob a pista: o terreno fica abaixo do tabuleiro.
		var xp := distancia_saida + xe - ao_longo
		if xp > 0.0 and xp < xe:
			var teto_pista := perfil.altura_em(xp) - 14.0
			if xp < x_borda:
				teto_pista = minf(teto_pista, _topo_mesa)
			h = minf(h, lerpf(teto_pista, h, smoothstep(34.0 + _meia_arena, 120.0 + _meia_arena, lateral)))
		# Mesa sob a plataforma, terminando num paredão na borda da descida.
		if xp < x_borda + 5.0 and xp > -400.0:
			var peso := smoothstep(x_borda + 5.0, x_borda - 12.0, xp)
			peso *= smoothstep(190.0, 130.0, lateral)
			peso *= smoothstep(-400.0, -250.0, xp)
			h = maxf(h, lerpf(h, _topo_mesa, peso))
	if _canion_fechado:
		h = _paredoes(x, z, h, nd)
		h = minf(h, lerpf(-7.0, h, smoothstep(10.0, 55.0, d_rio)))
		h = minf(h, lerpf(3.0, h, smoothstep(55.0, 230.0, d_rio)))
	return h


## City Rush: chão plano no nível da rua; o rio (longe, rio_deslocamento) corre num canal de concreto.
## Os prédios não entram na malha (ficam em Cidade, somados em altura_em).
func _altura_cidade(x: float, z: float) -> float:
	var x_rio := -170.0 + _desvio_rio + 260.0 * sin(z / 760.0) + 90.0 * sin(z / 230.0 + 1.3)
	var d_rio := absf(x - x_rio)
	return lerpf(-6.0, CHAO_CIDADE, smoothstep(70.0, 80.0, d_rio))


## Vale do Canyon Combat (mapa.canion_fechado), como no desenho do dono visto de cima: um vale largo
## da saída da rampa até o alvo, cercado de montanhas quase da altura da plataforma, e esporões
## gigantes saindo de lados opostos. O 1º encosta no meio do vale (dá para sair reto da rampa); o 2º
## cruza o meio — quem voa reto bate nele: é preciso costurar em "S" por trás do 1º. Cada etapa sorteia
## outro arranjo com a mesma lógica (canion_layout). A descida fica num desfiladeiro.
## Coordenadas do vale: u = metros do alvo em direção à rampa; lat = lateral.
func _paredoes(x: float, z: float, h: float, nd: float) -> float:
	var q := _no_vale(x, z)
	var u := q.x
	if u >= _u_borda():
		return h   # a mesa da plataforma fica de fora
	var lat := q.y
	var w := meia_largura_vale(u) + 45.0 * _ruido_planalto.get_noise_2d(u * 1.6, signf(lat) * 4000.0)
	var d := maxf(absf(lat) - w, maxf(u - distancia_saida - 20.0, -u - _vale_fundo))
	if u > distancia_saida - 60.0:
		d = minf(d, absf(lat) - _canion_largura_rampa)   # desfiladeiro da descida
	d += 18.0 * nd
	var altura := minf(_canion_altura + 45.0 * _ruido_planalto.get_noise_2d(x, z), _topo_mesa + 20.0)
	if u > distancia_saida:   # na descida o desfiladeiro sobe até o topo da mesa
		altura = lerpf(altura, _topo_mesa, smoothstep(distancia_saida, distancia_saida + 200.0, u))
	if d > 0.0:
		var nivel := smoothstep(0.0, 150.0, d)
		var alcance := smoothstep(900.0, 500.0, d)
		h = maxf(h, lerpf(h, altura * _degraus(nivel) + 10.0, alcance))
	# Esporões: face mais íngreme, para a ponta também ficar alta
	for e: Array in _esporoes:
		var de := _dentro_esporao(q, e) + 14.0 * nd
		if de > 0.0:
			h = maxf(h, altura * _perfil_esporao(q, e, de, 100.0) + 10.0)
	return h


## Climb to Death: chão plano (≈ nível do mar) no retângulo do vale, montanhas de cânion em
## degraus em volta (somem de volta nas mesas normais longe dali) e o morro de 300 m entre a subida
## e o alvo.
func _altura_subida(x: float, z: float) -> float:
	var nd := _ruido_detalhe.get_noise_2d(x, z)
	var h := 6.5 + 1.2 * nd
	var dx := maxf(maxf(_sub_vale[0] - x, x - _sub_vale[2]), 0.0)
	var dz := maxf(maxf(_sub_vale[1] - z, z - _sub_vale[3]), 0.0)
	var d := Vector2(dx, dz).length()
	if d > 0.0:
		d = maxf(d + 30.0 * _ruido_planalto.get_noise_2d(x * 1.3, z * 1.3) + 12.0 * nd, 0.0)
		var alt := minf(380.0 + 45.0 * _ruido_planalto.get_noise_2d(x, z), 420.0)
		if _modo_selva:
			alt = selva.penhasco + 40.0 * _ruido_planalto.get_noise_2d(x, z)
		if _modo_egito:
			alt = egito.penhasco + 35.0 * _ruido_planalto.get_noise_2d(x, z)   # penhascos de calcário mais baixos
		if _modo_gelo:
			alt = gelo.penhasco + 70.0 * _ruido_planalto.get_noise_2d(x, z)
		if _modo_dino:
			alt = dino.penhasco + 60.0 * _ruido_planalto.get_noise_2d(x, z)
		var parede := alt * _degraus(smoothstep(0.0, 150.0, d)) + 10.0
		# Longe do vale volta às mesas normais do cânion
		var nb := _ruido_base.get_noise_2d(x, z)
		var mesa := smoothstep(-0.12, 0.22, nb + nd * 0.3) * 3.0
		var fm := floorf(mesa)
		var mesas := (fm + smoothstep(0.55, 1.0, mesa - fm)) / 3.0 * (320.0 + 55.0 * _ruido_planalto.get_noise_2d(x, z)) + 10.0 + 6.0 * nd
		mesas = maxf(mesas, _pinaculos(x, z))
		if _modo_selva:
			mesas = _morros(x, z)   # longe do vale: morros cobertos de mata
		if _modo_egito:
			mesas = _dunas(x, z)   # longe do vale: mar de dunas
		if _modo_gelo:
			mesas = _picos(x, z)   # longe do vale: maciços nevados
		if _modo_dino:
			mesas = _morros(x, z) * 1.4   # longe do vale: serras cobertas de mata
		h = maxf(h, lerpf(mesas, parede, smoothstep(1500.0, 900.0, d)))
	# Morro entre a subida e o alvo
	if not _sub_morro.is_empty() and not _sem_morro:
		var p := Vector2(x, z)
		var dm := _dist_crista(p) + 14.0 * nd
		var nivel := smoothstep(float(_sub_morro.raio_base), float(_sub_morro.raio_topo), dm)
		h = maxf(h, float(_sub_morro.altura) * _degraus(nivel) + 6.0)
		if not _sub_encosta.is_empty() and dm < float(_sub_morro.encosta_alcance) + 20.0:
			h = _encosta_ate_estrada(p, dm, h, nd)
	elif _muralha_estrada > 0.0 and not _sub_encosta.is_empty():
		# Etapa sem o morro: só a encosta dele fica, colada na estrada (pedido do dono)
		var p := Vector2(x, z)
		var dm := _dist_crista(p) + 14.0 * nd
		if dm < float(_sub_morro.encosta_alcance) + 20.0:
			h = _encosta_ate_estrada(p, dm, h, nd, _muralha_estrada)
	if not _sub_barreiras.is_empty():
		h = _barreiras(Vector2(x, z), h, nd)
	if not _sub_fixas.is_empty() or not _sub_montanhas.is_empty():
		var face := float(Config.valor("mapa.subida.montanhas.face", 50))
		var p := Vector2(x, z)
		for c: Array in _sub_fixas + _sub_montanhas:
			if c.size() > 5 and c[5]:
				h = maxf(h, _duna(p, c))   # duna: encosta lisa de areia, sem degraus
				continue
			var de := _dentro_esporao(p, c) + 14.0 * nd
			if de > 0.0:
				h = maxf(h, float(c[4]) * _perfil_esporao(p, c, de, face) + 6.0 + 20.0 * _ruido_planalto.get_noise_2d(x * 3.0, z * 3.0))
	if not _sub_tunel.is_empty():
		h = _cavar_tunel(Vector2(x, z), h)
	if _modo_egito:
		h = egito.cavar_nilo(x, z, h)
	if _modo_selva:
		h = selva.cavar_rio(x, z, h)
	if _modo_gelo:
		h = gelo.cavar(x, z, h)
	if _modo_dino:
		h = dino.relevo(x, z, h)   # vulcão, leitos de lava e o corte das estradas
	return h


## Pharaoh's Climb: mar de dunas longe do vale (cristas compridas alinhadas com o vento, de
## 15 a 60 m, sobre ondulações largas).
func _dunas(x: float, z: float) -> float:
	var q := Vector2(x * 0.8 + z * 0.35, z * 1.1 - x * 0.25)   # cristas tortas, na diagonal
	var crista := 1.0 - absf(_ruido_detalhe.get_noise_2d(q.x * 0.55, q.y * 0.18))
	var grande := _ruido_base.get_noise_2d(x * 0.7, z * 0.7)
	return 14.0 + 45.0 * (grande * 0.5 + 0.5) + 42.0 * crista * crista * (0.6 + 0.4 * grande)


## Serpent's Climb: morros arredondados cobertos de mata longe do vale (60 a 260 m), com vales entre eles.
func _morros(x: float, z: float) -> float:
	var grande := _ruido_base.get_noise_2d(x * 0.8, z * 0.8) * 0.5 + 0.5
	var medio := _ruido_detalhe.get_noise_2d(x * 0.45, z * 0.45) * 0.5 + 0.5
	return 40.0 + 170.0 * grande * grande + 70.0 * medio


## Frozen Peak: maciços nevados largos e arredondados longe do vale (150 a 650 m), com cristas
## compridas — nada de pico em cone (a malha de longe tem um ponto a cada ~110 m).
func _picos(x: float, z: float) -> float:
	var grande := _ruido_base.get_noise_2d(x * 0.55, z * 0.55) * 0.5 + 0.5
	var medio := _ruido_detalhe.get_noise_2d(x * 0.22, z * 0.22) * 0.5 + 0.5
	var crista := 1.0 - absf(_ruido_planalto.get_noise_2d(x * 0.6, z * 0.6))
	return 130.0 + 330.0 * grande * grande + 120.0 * medio + 150.0 * crista * crista * grande


## Duna gigante (cápsula com duna = true): perfil liso em sino, crista um pouco ondulada.
func _duna(p: Vector2, c: Array) -> float:
	var de := _dentro_esporao(p, c)
	if de <= 0.0:
		return -INF
	var a: Vector2 = c[0]
	var ab: Vector2 = c[1] - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
	var raio := lerpf(c[2], c[3], t)
	var n := clampf(de / raio, 0.0, 1.0)
	var perfil := n * n * (3.0 - 2.0 * n)
	perfil = lerpf(perfil, sqrt(n), 0.35)   # topo arredondado, pé espalhado
	return float(c[4]) * perfil * (0.92 + 0.08 * _ruido_detalhe.get_noise_2d(p.x * 2.0, p.y * 2.0)) + 6.0


## Altura "natural" da montanha, sem a vala do túnel (a rocha por cima do túnel é desenhada por
## TunelAtalho com esta altura).
func altura_natural(x: float, z: float) -> float:
	if _sub_tunel.is_empty():
		return _altura_procedural(x, z)
	return _altura_subida_sem_tunel(x, z)


## Altura natural interpolada como a malha de perto (pontos a cada ~13 m): a capa de rocha do túnel
## usa esta, para coincidir com o terreno em volta sem degrau.
var _natural_nos := {}
func altura_natural_malha(x: float, z: float) -> float:
	var passo := MEIO_INTERNO * 2.0 / (N_INTERNO - 1)
	var fx := (x + MEIO_INTERNO) / passo
	var fz := (z + MEIO_INTERNO) / passo
	var ix := floori(fx)
	var iz := floori(fz)
	var h := [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		var no := Vector2i(ix + (k & 1), iz + (k >> 1))
		if not _natural_nos.has(no):
			_natural_nos[no] = altura_natural(-MEIO_INTERNO + no.x * passo, -MEIO_INTERNO + no.y * passo)
		h[k] = _natural_nos[no]
	var tx := fx - ix
	var tz := fz - iz
	return lerpf(lerpf(h[0], h[1], tx), lerpf(h[2], h[3], tx), tz)


## Extinction Day: altura natural sem o corte das estradas (a capa de rocha do túnel do vulcão refaz
## a encosta por cima da vala), interpolada como a malha de perto (pontos a cada ~13 m).
var _sem_estrada_nos := {}
func altura_sem_estrada_malha(x: float, z: float) -> float:
	var passo := MEIO_INTERNO * 2.0 / (N_INTERNO - 1)
	var fx := (x + MEIO_INTERNO) / passo
	var fz := (z + MEIO_INTERNO) / passo
	var ix := floori(fx)
	var iz := floori(fz)
	var h := [0.0, 0.0, 0.0, 0.0]
	for k in 4:
		var no := Vector2i(ix + (k & 1), iz + (k >> 1))
		if not _sem_estrada_nos.has(no):
			dino.sem_estrada = true
			_sem_estrada_nos[no] = _altura_procedural(-MEIO_INTERNO + no.x * passo, -MEIO_INTERNO + no.y * passo)
			dino.sem_estrada = false
		h[k] = _sem_estrada_nos[no]
	var tx := fx - ix
	var tz := fz - iz
	return lerpf(lerpf(h[0], h[1], tx), lerpf(h[2], h[3], tx), tz)


func _altura_subida_sem_tunel(x: float, z: float) -> float:
	var tun := _sub_tunel
	_sub_tunel = {}
	var h := _altura_procedural(x, z)
	_sub_tunel = tun
	return h


## Vala do túnel: 4 m abaixo da estrada dele, de uma boca à outra (com 25 m de sobra para fora).
func _cavar_tunel(p: Vector2, h: float) -> float:
	var e := Vector2(float(_sub_tunel.entrada[0]), float(_sub_tunel.entrada[1]))
	var s := Vector2(float(_sub_tunel.saida[0]), float(_sub_tunel.saida[1]))
	var comp := e.distance_to(s)
	var d := (s - e) / comp
	var t := (p - e).dot(d)
	if t < -25.0 or t > comp + 25.0 or absf((p - e).dot(Vector2(-d.y, d.x))) > MEIA_VALA_TUNEL:
		return h
	var estrada := lerpf(float(_sub_tunel.altura_entrada), float(_sub_tunel.altura_saida), clampf(t / comp, 0.0, 1.0))
	return minf(h, estrada - 4.0)


## Cápsulas do json ({a, b, raio: [ra, rb], altura}) no formato de _dentro_esporao + altura.
static func _capsulas(lista: Array) -> Array:
	var r := []
	for c: Dictionary in lista:
		r.append([Vector2(float(c.a[0]), float(c.a[1])), Vector2(float(c.b[0]), float(c.b[1])),
			float(c.raio[0]), float(c.raio[1]), float(c.get("altura", 320)), bool(c.get("duna", false))])
	return r


## Cristas de montanha atravessando o vale entre a rampa final e o alvo (pedido do dono), com fendas
## estreitas de paredes quase verticais para passar. A malha tem um ponto a cada ~13 m: a fenda
## configurada perde uns 10 m de cada lado na interpolação.
func _barreiras(p: Vector2, h: float, nd: float) -> float:
	var cfg := _sub_barreiras_cfg
	var esp := float(cfg.get("espessura", 60))
	var face := float(cfg.get("face", 45))
	var altura := float(cfg.get("altura", 320))
	var meia_fenda := float(cfg.get("fenda", 55)) * 0.5
	var parede := float(cfg.get("parede_fenda", 10))
	for b: Dictionary in _sub_barreiras:
		var q: Vector2 = p - b.a
		var t := q.dot(b.d)
		if t < 0.0 or t > b.comp:
			continue
		var de := esp - absf(q.dot(b.n)) + 12.0 * nd
		if de <= 0.0:
			continue
		var hh := altura * _degraus(smoothstep(0.0, minf(face, esp * 0.6), de)) + 6.0 + 25.0 * _ruido_planalto.get_noise_2d(p.x * 3.0, p.y * 3.0)
		for f: float in b.fendas:
			hh = minf(hh, maxf(absf(t - f) - meia_fenda, 0.0) * parede + 6.0)
		h = maxf(h, hh)
	return h


## Sorteia as cristas da etapa (sempre iguais para a mesma etapa): inclinação, posição e fendas.
## As fendas de uma crista ficam longe das da anterior (obriga a costurar) e a rota dos bots passa
## pela fenda mais perto de onde vêm.
func _sortear_barreiras(etapa: int) -> void:
	# Etapa com arranjo desenhado pelo dono: as montanhas dele no lugar das cristas sorteadas
	var desenho: Dictionary = Config.valor("mapa.subida.montanhas.etapas.%d" % (etapa + 1), {})
	_sub_montanhas = _capsulas(desenho.get("capsulas", []))
	_sub_tunel = desenho.get("tunel", {})
	_sub_paredao = desenho.get("paredao", {})
	_sub_estrada_extra = desenho.get("estrada_extra", {})
	_sem_morro = bool(desenho.get("sem_morro", false))
	_muralha_estrada = float(desenho.get("muralha_estrada", 0.0)) if _sem_morro else 0.0
	_natural_nos.clear()   # as montanhas mudam com a etapa
	if not desenho.is_empty():
		_sub_barreiras.clear()
		_rota_vale.clear()
		_rota_alt.clear()
		rotas_alt.clear()
		for lista in desenho.get("rotas_alt", []):
			var alt_r: Array[Vector3] = []
			for w in lista:
				alt_r.append(Vector3(float(w[0]), float(w[2]) if w.size() > 2 else 0.0, float(w[1])))
			rotas_alt.append(alt_r)
		for w in desenho.get("rota", []):
			_rota_vale.append(Vector2(-float(w[1]), float(w[0])))   # coordenadas do vale: u = -z, lateral = x
			_rota_alt.append(float(w[2]) if w.size() > 2 else 0.0)
		_etapa_vale = etapa
		return
	var cfg := _sub_barreiras_cfg
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) * 17 + etapa * 6007
	var xs: Array = cfg.get("x", [-450, 700])
	var fx: Array = cfg.get("fendas_x", [-60, 360])
	var sep := float(cfg.get("separacao_min", 140))
	var incl := deg_to_rad(float(cfg.get("inclinacao_graus", 12)))
	var esp := float(cfg.get("espessura", 60))
	_sub_barreiras.clear()
	_rota_vale.clear()
	_rota_alt.clear()
	var anteriores: Array[float] = []
	var vindo := 0.0   # x de onde os bots vêm (a rampa final fica em x = 0)
	for fil: Dictionary in cfg.get("fileiras", []):
		var ang := rng.randf_range(-incl, incl)
		var d := Vector2(cos(ang), sin(ang))
		var n := Vector2(-d.y, d.x)
		if n.y < 0.0:
			n = -n   # normal apontando para o alvo (+z)
		var z_meio := float(fil.z) + rng.randf_range(-25.0, 25.0)
		var x0 := float(xs[0])
		var a := Vector2(x0, z_meio - d.y / d.x * (0.0 - x0))   # a crista passa por (0, z_meio)
		var comp := (float(xs[1]) - x0) / d.x
		var cfg_fendas = fil.get("fendas", 1)   # número fixo ou [mín, máx]
		var qtd: int = rng.randi_range(int(cfg_fendas[0]), int(cfg_fendas[1])) if cfg_fendas is Array else int(cfg_fendas)
		# Fendas longe umas das outras e das da crista anterior; se não couber, a posição mais afastada
		# (uma crista nunca fica sem passagem)
		var centros: Array[float] = []
		for k in qtd:
			var melhor_x := 0.0
			var melhor_d := -INF
			for tentativa in 60:
				var x := rng.randf_range(float(fx[0]), float(fx[1]))
				var d_min := INF
				for c in centros + anteriores:
					d_min = minf(d_min, absf(c - x))
				if d_min > sep:
					melhor_x = x
					melhor_d = d_min
					break
				if d_min > melhor_d:
					melhor_x = x
					melhor_d = d_min
			if k > 0 and melhor_d < 70.0:
				break   # a extra só entra se couber sem colar em outra
			centros.append(melhor_x)
		var fendas: Array[float] = []
		for x in centros:
			fendas.append((x - x0) / d.x)
		_sub_barreiras.append({"a": a, "d": d, "n": n, "comp": comp, "fendas": fendas})
		anteriores = centros
		# Rota dos bots: entra reto na fenda mais perto de onde vêm e sai reto do outro lado
		var melhor := 0
		for k in centros.size():
			if absf(centros[k] - vindo) < absf(centros[melhor] - vindo):
				melhor = k
		if not centros.is_empty():
			var c := a + d * fendas[melhor]
			for passo: float in [-(esp + 30.0), 0.0, esp + 20.0]:
				var w := c + n * passo
				_rota_vale.append(Vector2(-w.y, w.x))   # coordenadas do vale: u = -z, lateral = x
			vindo = centros[melhor]
	_etapa_vale = etapa


## Retângulo (no mundo) ocupado pelas cristas, com folga.
func _area_barreiras() -> Array[Rect2]:
	var lista: Array[Rect2] = []
	var esp := float(_sub_barreiras_cfg.get("espessura", 60)) + 40.0
	for b: Dictionary in _sub_barreiras:
		var fim: Vector2 = b.a + b.d * b.comp
		lista.append(Rect2(b.a, Vector2.ZERO).expand(fim).grow(esp))
	for c: Array in _sub_montanhas:
		lista.append(Rect2(c[0], Vector2.ZERO).expand(c[1]).grow(maxf(c[2], c[3]) + 40.0))
	if not _sub_tunel.is_empty():
		var e := Vector2(float(_sub_tunel.entrada[0]), float(_sub_tunel.entrada[1]))
		var s := Vector2(float(_sub_tunel.saida[0]), float(_sub_tunel.saida[1]))
		lista.append(Rect2(e, Vector2.ZERO).expand(s).grow(MEIA_VALA_TUNEL + 40.0))
	return lista


## Túnel-atalho da etapa atual (vazio se não tiver).
func tunel_da_etapa() -> Dictionary:
	return _sub_tunel


## Trecho de estrada extra da etapa atual (vazio se não tiver).
func estrada_extra_da_etapa() -> Dictionary:
	return _sub_estrada_extra


## Paredão fino com buraco da etapa atual (vazio se não tiver).
func paredao_da_etapa() -> Dictionary:
	return _sub_paredao


## Retângulo do morro (com a encosta até a estrada), para refazer o terreno quando ele some/volta.
func _area_morro() -> Rect2:
	var a := Vector2(float(_sub_morro.a[0]), float(_sub_morro.a[1]))
	var b := Vector2(float(_sub_morro.b[0]), float(_sub_morro.b[1]))
	var folga := float(_sub_morro.raio_base) + float(_sub_morro.get("encosta_alcance", 0.0)) + 40.0
	return Rect2(a, Vector2.ZERO).expand(b).grow(folga)


## Distância horizontal até a crista do morro (segmento de a até b).
func _dist_crista(p: Vector2) -> float:
	var a := Vector2(float(_sub_morro.a[0]), float(_sub_morro.a[1]))
	var ab := Vector2(float(_sub_morro.b[0]), float(_sub_morro.b[1])) - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _preparar_encosta() -> void:
	_sub_encosta.clear()
	var alcance := float(_sub_morro.get("encosta_alcance", 0.0))
	if _sub_morro.is_empty() or alcance <= 0.0:
		return
	for ctrl: PackedVector3Array in _sub_estrada:
		var pts := ComplexoSubida._amostrar_curva(ctrl)
		var n := pts.size()
		var s := PackedFloat32Array()
		s.resize(n)
		for i in range(1, n):
			s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
		for i in range(0, n, 3):
			var p2 := Vector2(pts[i].x, pts[i].z)
			var dm := _dist_crista(p2)
			if dm > alcance:
				continue
			var q0 := pts[maxi(i - 2, 0)]
			var q1 := pts[mini(i + 2, n - 1)]
			var t := Vector2(q1.x - q0.x, q1.z - q0.z).normalized()
			_sub_encosta.append([p2, pts[i].y, t, dm, minf(s[i], s[n - 1] - s[i])])


## O morro cresce até a estrada que passa ao lado dele (pedido do dono: quase encostando). A encosta
## passa por baixo da estrada (4 m abaixo) e sobe a ~45° a partir de 1-2 m da beirada. A malha do
## terreno tem um ponto a cada ~13 m, então a subida não pode ser mais íngreme que isso: senão a
## interpolação atravessaria o asfalto (e tocar o terreno explode o carro).
## Só vale ao lado da estrada: não passa das pontas dos trechos (vão do salto, rampa final).
## espessura > 0 (etapa sem o morro): a encosta vira muralha — depois dessa distância da beirada
## desce de novo até o chão, deixando livre o que o desenho da etapa pôs mais para dentro.
func _encosta_ate_estrada(p: Vector2, dm: float, h: float, nd: float, espessura := 0.0) -> float:
	var melhor := INF
	var e: Array = []
	for amostra: Array in _sub_encosta:
		var d := p.distance_squared_to(amostra[0])
		if d < melhor:
			melhor = d
			e = amostra
	var dm_estrada: float = e[3]
	var meia := 7.0
	if dm > dm_estrada + meia + 2.0:
		return h   # do outro lado da estrada: nada muda
	# Só do lado da crista em que a estrada passa (senão enchia o vale do outro lado do morro)
	var a := Vector2(float(_sub_morro.a[0]), float(_sub_morro.a[1]))
	var ab := Vector2(float(_sub_morro.b[0]), float(_sub_morro.b[1])) - a
	# Só ao lado da crista: além das pontas dela a reta não separa lados (a estrada de cima cruza a
	# reta e abria uma fenda estreita até o chão ali — pedido do dono para fechar)
	var t_crista := (p - a).dot(ab) / ab.length_squared()
	if t_crista > 0.0 and t_crista < 1.0 and signf(ab.cross(p - a)) != signf(ab.cross(e[0] - a)):
		return h
	var dr := sqrt(melhor)
	var ao_longo := absf((p - e[0]).dot(e[2]))
	var alcance := float(_sub_morro.encosta_alcance)
	var w := smoothstep(alcance, alcance - 60.0, dm_estrada) * smoothstep(12.0, 3.0, ao_longo) * smoothstep(0.0, 25.0, e[4])
	if w <= 0.0:
		return h
	var teto: float = e[1] - 4.0 + maxf(dr - meia - 1.0, 0.0) * 1.0 + 6.0 * nd * minf(dr / 40.0, 1.0)
	var alvo := minf(float(_sub_morro.altura) + 6.0, teto)
	if espessura > 0.0:
		var face := float(Config.valor("mapa.subida.montanhas.face", 50))
		var fora := dr - meia - espessura + 10.0 * nd
		alvo = minf(alvo, float(_sub_morro.altura) * _degraus(smoothstep(face, 0.0, fora)) + 6.0)
	return maxf(h, lerpf(h, alvo, w))


## Face em degraus (patamares), como os pináculos.
static func _degraus(nivel: float) -> float:
	return lerpf(floorf(nivel * 3.0) / 3.0, nivel, 0.35)


## Meia-largura do vale (do meio até o pé da montanha) a u metros do alvo.
func meia_largura_vale(u: float) -> float:
	if u > 400.0:
		return lerpf(_vale_largura[1], _vale_largura[0], clampf((u - 400.0) / (distancia_saida - 400.0), 0.0, 1.0))
	return lerpf(_vale_largura[2], _vale_largura[1], clampf(u / 400.0, 0.0, 1.0))


func _u_borda() -> float:
	return distancia_saida + perfil.comprimento_horizontal - perfil.pontos[perfil.indice_borda].x


## Ponto do mundo em coordenadas do vale (u, lat) e vice-versa.
func _no_vale(x: float, z: float) -> Vector2:
	var dir := _direcoes[0]
	var p := Vector2(x, z)
	return Vector2(p.dot(dir), p.dot(Vector2(-dir.y, dir.x)))


func _do_vale(q: Vector2) -> Vector2:
	var dir := _direcoes[0]
	return dir * q.x + Vector2(-dir.y, dir.x) * q.y


## Esporão = crista de a (base, dentro da montanha) até b (ponta), raio ra na base e rb na ponta.
## Positivo dentro dele.
static func _dentro_esporao(q: Vector2, e: Array) -> float:
	var a: Vector2 = e[0]
	var ab: Vector2 = e[1] - a
	var l2 := ab.length_squared()
	var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.01 else 0.0   # a = b: montanha redonda
	return lerpf(e[2], e[3], t) - q.distance_to(a + ab * t)


## Perfil (0..1) da encosta de um esporão/cápsula: sobe em `face` metros, mas nunca em mais de 60%
## do raio ali — sobra sempre um topo plano (mesa). Com a face maior que o raio a ponta virava cone.
static func _perfil_esporao(q: Vector2, e: Array, de: float, face: float) -> float:
	var a: Vector2 = e[0]
	var ab: Vector2 = e[1] - a
	var l2 := ab.length_squared()
	var t := clampf((q - a).dot(ab) / l2, 0.0, 1.0) if l2 > 0.01 else 0.0
	var raio := lerpf(e[2], e[3], t)
	return _degraus(smoothstep(0.0, minf(face, raio * 0.6), de))


## Sorteia os esporões da etapa (sempre iguais para a mesma etapa) e a rota que desvia deles.
func _sortear_vale(etapa: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) * 31 + etapa * 7919
	var cfg: Dictionary = Config.valor("mapa.canion_layout", {})
	var lado := 1.0 if rng.randf() < 0.5 else -1.0
	_esporoes.clear()
	_rota_vale.clear()
	_rota_alt.clear()
	# 1º esporão: vem do lado "lado" e para pouco antes do meio (a saída reta passa raspando)
	var u1 := rng.randf_range(float(cfg.get("u1_min", 510)), float(cfg.get("u1_max", 570)))
	var rb1 := rng.randf_range(80.0, 95.0)
	var b1 := Vector2(u1, lado * (rb1 - rng.randf_range(20.0, 40.0)))
	_esporoes.append([Vector2(u1 + rng.randf_range(-60.0, 60.0), lado * (meia_largura_vale(u1) + 80.0)), b1, rng.randf_range(160.0, 200.0), rb1])
	# 2º esporão: vem do outro lado e cruza o meio
	var u2 := rng.randf_range(float(cfg.get("u2_min", 200)), float(cfg.get("u2_max", 250)))
	var rb2 := rng.randf_range(80.0, 95.0)
	var cruza := rng.randf_range(float(cfg.get("cruza_min", 20)), float(cfg.get("cruza_max", 45)))
	var b2 := Vector2(u2, lado * cruza)
	_esporoes.append([Vector2(u2 + rng.randf_range(-60.0, 60.0), -lado * (meia_largura_vale(u2) + 80.0)), b2, rng.randf_range(160.0, 200.0), rb2])
	# Rota: sai reto, passa a ponta do 1º pelo lado de fora, corta por trás dele para o lado "lado"
	# e contorna a ponta do 2º por esse lado
	var passe := lado * (cruza + rb2 + 25.0)
	_rota_vale.append(Vector2(u1, b1.y - lado * (rb1 + 20.0)))
	_rota_vale.append(Vector2(u2 + rb2 + 40.0, passe))
	_rota_vale.append(Vector2(u2, passe))
	_rota_vale.append(Vector2(u2 - rb2 - 15.0, passe))
	_etapa_vale = etapa


## Metros do alvo em direção à rampa (coordenada u do vale) de um ponto do mundo.
func u_no_vale(p: Vector3) -> float:
	if _modo_cidade:
		return Vector2(p.x, p.z).length()   # City Rush: cada corredor vem reto para o alvo
	return _no_vale(p.x, p.z).x


## Rota dos bots pelo vale (pontos no mundo, do mais perto da rampa ao mais perto do alvo).
func rota_vale() -> Array[Vector3]:
	var lista: Array[Vector3] = []
	for k in _rota_vale.size():
		var p := _do_vale(_rota_vale[k])
		lista.append(Vector3(p.x, _rota_alt[k] if k < _rota_alt.size() else 0.0, p.y))
	return lista


## Troca os esporões para a etapa: recalcula só a área deles (a antiga e a nova) e refaz a malha
## de perto, a vegetação do vale e a bruma.
func preparar_etapa(etapa: int) -> void:
	var subida := _modo_subida and not _sub_barreiras_cfg.is_empty()
	if not (_canion_fechado or subida) or etapa == _etapa_vale:
		return
	var areas: Array[Rect2] = _area_barreiras() if subida else _areas_esporoes()
	if subida:
		var sem_morro_antes := _sem_morro
		_sortear_barreiras(etapa)
		areas.append_array(_area_barreiras())
		if _sem_morro != sem_morro_antes and not _sub_morro.is_empty():
			areas.append(_area_morro())   # o morro some (ou volta) nesta etapa
	else:
		_sortear_vale(etapa)
		areas.append_array(_areas_esporoes())
	var n := N_INTERNO
	var passo := MEIO_INTERNO * 2.0 / (n - 1)
	for r in areas:
		var ix0 := clampi(floori((r.position.x + MEIO_INTERNO) / passo), 0, n - 1)
		var ix1 := clampi(ceili((r.end.x + MEIO_INTERNO) / passo), 0, n - 1)
		var iz0 := clampi(floori((r.position.y + MEIO_INTERNO) / passo), 0, n - 1)
		var iz1 := clampi(ceili((r.end.y + MEIO_INTERNO) / passo), 0, n - 1)
		for iz in range(iz0, iz1 + 1):
			for ix in range(ix0, ix1 + 1):
				alturas_interno[iz * n + ix] = _altura_procedural(-MEIO_INTERNO + ix * passo, -MEIO_INTERNO + iz * passo)
	_malha_interna.queue_free()
	_malha_interna = _criar_malha(alturas_interno, MEIO_INTERNO, N_INTERNO, _mat_terreno)
	add_child(_malha_interna)
	if subida:
		_criar_vegetacao_subida()
	else:
		_criar_vegetacao_vale()


## Retângulos (no mundo) que os esporões atuais ocupam, com folga.
func _areas_esporoes() -> Array[Rect2]:
	var lista: Array[Rect2] = []
	for e: Array in _esporoes:
		var folga := maxf(e[2], e[3]) + 40.0
		var a := _do_vale(e[0])
		var b := _do_vale(e[1])
		lista.append(Rect2(a, Vector2.ZERO).expand(b).grow(folga))
	return lista


func _criar_malha(dados: PackedFloat32Array, meio: float, n: int, mat: Material) -> MeshInstance3D:
	var passo := meio * 2.0 / (n - 1)
	var verts := PackedVector3Array()
	var normais := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	normais.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			verts[i] = Vector3(-meio + ix * passo, dados[i], -meio + iz * passo)
			var hl := dados[iz * n + maxi(ix - 1, 0)]
			var hr := dados[iz * n + mini(ix + 1, n - 1)]
			var hd := dados[maxi(iz - 1, 0) * n + ix]
			var hu := dados[mini(iz + 1, n - 1) * n + ix]
			normais[i] = Vector3(hl - hr, 2.0 * passo, hd - hu).normalized()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Corta o quadrado pela diagonal de alturas mais parecidas: com a diagonal sempre igual,
			# as encostas íngremes na diagonal da grade viravam dentes de serra (pedido do dono)
			if absf(dados[a] - dados[d]) < absf(dados[b] - dados[c]):
				indices[k] = a; indices[k + 1] = b; indices[k + 2] = d
				indices[k + 3] = a; indices[k + 4] = d; indices[k + 5] = c
			else:
				indices[k] = a; indices[k + 1] = b; indices[k + 2] = c
				indices[k + 3] = b; indices[k + 4] = d; indices[k + 5] = c
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normais
	arr[Mesh.ARRAY_INDEX] = indices
	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _material_terreno() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if _modo_cidade:
		var cfg: Dictionary = Config.valor("mapa.cidade", {})
		mat.shader = load("res://shaders/cidade_chao.gdshader")
		mat.set_shader_parameter("ruido", _textura_ruido(0.004, 5, 7))
		mat.set_shader_parameter("ruido_fino", _textura_ruido(0.02, 4, 13))
		mat.set_shader_parameter("quadra", float(cfg.get("quadra", 150)))
		mat.set_shader_parameter("rua", float(cfg.get("rua", 24)))
		mat.set_shader_parameter("calcada", float(cfg.get("calcada", 5)))
		mat.set_shader_parameter("praca", float(cfg.get("praca", 430)))
		mat.set_shader_parameter("nivel_chao", CHAO_CIDADE)
		return mat
	if _modo_selva:
		# Chão da mata (folhas e terra), rocha úmida com musgo nos paredões, barro e capim na margem do rio
		mat.shader = load("res://shaders/terreno_selva.gdshader")
		mat.set_shader_parameter("ruido", _textura_ruido(0.004, 5, 7))
		mat.set_shader_parameter("ruido_fino", _textura_ruido(0.02, 4, 13))
		mat.set_shader_parameter("nivel_agua", float(Config.valor("mapa.nivel_agua", 4)))
		mat.set_shader_parameter("mascara_rio", selva.textura_margem(MEIO_INTERNO))
		mat.set_shader_parameter("meio_mascara", MEIO_INTERNO)
		return mat
	if _modo_dino:
		# Chão da mata pré-histórica, basalto e cinza no vulcão, lava acesa nos leitos e na cratera
		mat.shader = load("res://shaders/terreno_dino.gdshader")
		mat.set_shader_parameter("ruido", _textura_ruido(0.004, 5, 7))
		mat.set_shader_parameter("ruido_fino", _textura_ruido(0.02, 4, 13))
		mat.set_shader_parameter("mascara", dino.textura_mascara(MEIO_INTERNO))
		mat.set_shader_parameter("meio_mascara", MEIO_INTERNO)
		mat.set_shader_parameter("centro_vulcao", dino.centro_vulcao)
		mat.set_shader_parameter("base_vulcao", dino.base_vulcao)
		return mat
	if _modo_gelo:
		# Neve com ondas do vento, rocha em camadas nas encostas íngremes e gelo azul na margem do lago
		mat.shader = load("res://shaders/terreno_gelo.gdshader")
		mat.set_shader_parameter("ruido", _textura_ruido(0.004, 5, 7))
		mat.set_shader_parameter("ruido_fino", _textura_ruido(0.02, 4, 13))
		mat.set_shader_parameter("nivel_agua", float(Config.valor("mapa.nivel_agua", 4)))
		mat.set_shader_parameter("mascara_lago", gelo.textura_margem(MEIO_INTERNO))
		mat.set_shader_parameter("meio_mascara", MEIO_INTERNO)
		return mat
	if _modo_egito:
		# Areia com ondulações, calcário em camadas nos penhascos e plantações verdes na margem do Nilo
		mat.shader = load("res://shaders/terreno_egito.gdshader")
		mat.set_shader_parameter("ruido", _textura_ruido(0.004, 5, 7))
		mat.set_shader_parameter("ruido_fino", _textura_ruido(0.02, 4, 13))
		mat.set_shader_parameter("nivel_agua", float(Config.valor("mapa.nivel_agua", 4)))
		mat.set_shader_parameter("mascara_nilo", egito.textura_margem(MEIO_INTERNO))
		mat.set_shader_parameter("meio_mascara", MEIO_INTERNO)
		return mat
	mat.shader = load("res://shaders/terreno.gdshader")
	mat.set_shader_parameter("ruido", _textura_ruido(0.004, 5, 7))
	mat.set_shader_parameter("ruido_fino", _textura_ruido(0.02, 4, 13))
	mat.set_shader_parameter("nivel_agua", float(Config.valor("mapa.nivel_agua", 4)))
	return mat


static func _textura_ruido(freq: float, oitavas: int, semente: int) -> NoiseTexture2D:
	var r := FastNoiseLite.new()
	r.seed = semente
	r.frequency = freq
	r.fractal_octaves = oitavas
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = r
	return tex


func _criar_agua() -> void:
	var plano := PlaneMesh.new()
	plano.size = Vector2(MEIO_EXTERNO * 2.0, MEIO_EXTERNO * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plano
	mi.position.y = Config.valor("mapa.nivel_agua", 4)
	var mat := ShaderMaterial.new()
	if _modo_gelo:
		# Frozen Peak: o lago e o rio são gelo (cair neles elimina do mesmo jeito)
		mat.shader = load("res://shaders/lago_gelo.gdshader")
		mat.set_shader_parameter("ruido", _textura_ruido(0.03, 3, 41))
	else:
		mat.shader = load("res://shaders/agua.gdshader")
		mat.set_shader_parameter("ruido", _textura_ruido(0.03, 3, 41))
		mat.set_shader_parameter("normal_a", _textura_normal(0.02, 4, 43, 6.0))
		mat.set_shader_parameter("normal_b", _textura_normal(0.045, 3, 47, 4.0))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static func _textura_normal(freq: float, oitavas: int, semente: int, relevo: float) -> NoiseTexture2D:
	var tex := _textura_ruido(freq, oitavas, semente)
	tex.as_normal_map = true
	tex.bump_strength = relevo
	return tex


## Pináculos e torres de rocha espalhados (como nas artes do dossiê). Uma candidata por célula de 300 m.
## Os corredores de voo, o rio e a área do alvo cortam o que ficar no caminho (aplicados depois).
func _pinaculos(x: float, z: float) -> float:
	const CELULA := 300.0
	# Fora da área de voo: nada num raio de 1,4 km do alvo nem perto dos corredores das equipes
	var r := Vector2(x, z).length()
	if r < 1400.0 or _amostrando_externo:
		return -INF
	for d in _direcoes:
		if Vector2(x, z).dot(d) > 0.0 and absf(Vector2(x, z).dot(Vector2(-d.y, d.x))) < 450.0:
			return -INF
	var cx := floori(x / CELULA)
	var cz := floori(z / CELULA)
	var h := -INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ix := cx + dx
			var iz := cz + dz
			var s := _hash2(ix, iz)
			if s > 0.42:
				continue
			var centro := Vector2((ix + 0.2 + 0.6 * _hash2(ix + 17, iz)) * CELULA, (iz + 0.2 + 0.6 * _hash2(ix, iz + 29)) * CELULA)
			var raio := 40.0 + 45.0 * _hash2(ix + 3, iz + 7)   # topo largo para a malha de 13 m (menor virava espeto)
			var altura := 80.0 + 230.0 * _hash2(ix + 11, iz + 13)
			# Borda irregular e em degraus: o raio encolhe com a altura (pináculo afunila no topo)
			var ang := atan2(z - centro.y, x - centro.x)
			var borda := raio * (1.0 + 0.18 * sin(ang * 3.0 + s * 20.0) + 0.1 * sin(ang * 7.0 + s * 9.0))
			var d := Vector2(x, z).distance_to(centro)
			if d > borda * 1.5:
				continue
			var nivel := smoothstep(borda * 1.5, borda, d)
			var degraus := floorf(nivel * 3.0) / 3.0
			var perfil := lerpf(degraus, nivel, 0.35)
			h = maxf(h, altura * perfil + 10.0)
	return h


static func _hash2(a: int, b: int) -> float:
	var n := a * 374761393 + b * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0


## Vegetação (ver Vegetacao): zimbros e sálvias nas áreas planas, mais densos e verdes perto do rio;
## capim seco em volta do alvo e nos topos das plataformas, onde a câmera chega perto.
func _criar_vegetacao() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) + 5
	var nivel_agua := float(Config.valor("mapa.nivel_agua", 4))
	var arvores := []
	var arbustos := []
	var capim := []
	var tentativas := 0
	while (arvores.size() < 4200 or arbustos.size() < 11000) and tentativas < 120000:
		tentativas += 1
		var x := rng.randf_range(-MEIO_INTERNO + 50.0, MEIO_INTERNO - 50.0)
		var z := rng.randf_range(-MEIO_INTERNO + 50.0, MEIO_INTERNO - 50.0)
		var h := altura_em(x, z)
		if h < nivel_agua + 1.5 or _dentro_do_vale(x, z, 260.0) or not _plano(x, z, 3.0):
			continue
		var perto_rio := h < nivel_agua + 30.0
		var chance_arvore := 0.45 if perto_rio else (0.28 if h > 150.0 else 0.1)
		if rng.randf() < chance_arvore:
			if arvores.size() < 4200:
				var verde := Color(0.85, 1.0, 0.8) if perto_rio else Color(1.0, 1.0, 0.9)
				arvores.append([Vector3(x, h - 0.2, z), rng.randf_range(0.7, 1.35) * (1.2 if perto_rio else 1.0), rng.randf() * TAU, verde * rng.randf_range(0.8, 1.1)])
		elif arbustos.size() < 11000:
			var tom := Color(0.9, 1.0, 0.85) if perto_rio else Color(1.0, 0.97, 0.92)
			arbustos.append([Vector3(x, h - 0.1, z), rng.randf_range(0.7, 1.6), rng.randf() * TAU, tom * rng.randf_range(0.8, 1.15)])
	# Capim: em volta do alvo e nos topos das plataformas (onde a câmera fica perto do chão)
	var zonas: Array = [[Vector2.ZERO, 750.0, 26000]]
	for d in _direcoes:
		var centro := d * (distancia_saida + perfil.comprimento_horizontal + 60.0)
		zonas.append([centro, 260.0, 7000])
	for zona: Array in zonas:
		var feitos := 0
		var t := 0
		while feitos < int(zona[2]) and t < int(zona[2]) * 3:
			t += 1
			var ang := rng.randf() * TAU
			var r: float = sqrt(rng.randf()) * float(zona[1])
			var x: float = zona[0].x + cos(ang) * r
			var z: float = zona[0].y + sin(ang) * r
			var h := altura_em(x, z)
			if h < nivel_agua + 0.6 or _dentro_do_vale(x, z, 260.0) or not _plano(x, z, 2.0):
				continue
			feitos += 1
			capim.append([Vector3(x, h - 0.05, z), rng.randf_range(0.7, 1.4), rng.randf() * TAU, Color(1, 1, 1) * rng.randf_range(0.75, 1.15)])
	Vegetacao.plantar(self, Vegetacao.Tipo.ZIMBRO, arvores, 700.0, 2800.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.SALVIA, arbustos, 400.0, 1400.0, false)
	Vegetacao.plantar(self, Vegetacao.Tipo.CAPIM, capim, 120.0, 300.0, false)


## Vale do Canyon Combat: vegetação exagerada (pedido do dono) — zimbros grandes e verdes, moitas e
## capim cobrindo o fundo do vale e os patamares dos esporões. Refeita a cada etapa (os esporões mudam).
func _criar_vegetacao_vale() -> void:
	if _veg_vale:
		_veg_vale.queue_free()
	_veg_vale = Node3D.new()
	_veg_vale.name = "VegetacaoVale"
	add_child(_veg_vale)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) + 500 + _etapa_vale
	var nivel_agua := float(Config.valor("mapa.nivel_agua", 4))
	var qtd: Array = Config.valor("mapa.canion_layout.vegetacao", [7000, 14000, 30000])
	var arvores := []
	var arbustos := []
	var capim := []
	var w_max := maxf(_vale_largura[0], maxf(_vale_largura[1], _vale_largura[2])) + 260.0
	var tentativas := 0
	while (arvores.size() < int(qtd[0]) or arbustos.size() < int(qtd[1]) or capim.size() < int(qtd[2])) and tentativas < 400000:
		tentativas += 1
		var q := Vector2(rng.randf_range(-_vale_fundo - 150.0, distancia_saida + 40.0), rng.randf_range(-w_max, w_max))
		if absf(q.y) > meia_largura_vale(q.x) + 260.0:
			continue
		var p := _do_vale(q)
		var h := altura_em(p.x, p.y)
		if h < nivel_agua + 1.0:
			continue
		# Área do alvo e dos trilhos do alvo móvel livres
		var perto_alvo := q.length() < 60.0 or (absf(q.x) < 30.0 and absf(q.y) < 110.0)
		var sorteio := rng.randf()
		if sorteio < 0.3 and arvores.size() < int(qtd[0]) and not perto_alvo and _plano(p.x, p.y, 7.0):
			var verde := Color(0.7, 1.05, 0.65) * rng.randf_range(0.8, 1.1)
			arvores.append([Vector3(p.x, h - 0.3, p.y), rng.randf_range(1.3, 2.8), rng.randf() * TAU, verde])
		elif sorteio < 0.6 and arbustos.size() < int(qtd[1]) and not perto_alvo and _plano(p.x, p.y, 6.0):
			arbustos.append([Vector3(p.x, h - 0.1, p.y), rng.randf_range(1.2, 2.6), rng.randf() * TAU, Color(0.8, 1.05, 0.72) * rng.randf_range(0.8, 1.15)])
		elif capim.size() < int(qtd[2]) and q.length() > 16.0 and _plano(p.x, p.y, 3.0):
			capim.append([Vector3(p.x, h - 0.05, p.y), rng.randf_range(1.0, 1.9), rng.randf() * TAU, Color(0.9, 1.05, 0.8) * rng.randf_range(0.75, 1.15)])
	Vegetacao.plantar(_veg_vale, Vegetacao.Tipo.ZIMBRO, arvores, 400.0, 2400.0, true)
	Vegetacao.plantar(_veg_vale, Vegetacao.Tipo.SALVIA, arbustos, 300.0, 1400.0, false)
	Vegetacao.plantar(_veg_vale, Vegetacao.Tipo.CAPIM, capim, 120.0, 350.0, false)


## Climb to Death: vegetação exagerada no vale (zimbros grandes e verdes, moitas e capim), longe
## da largada, da plataforma, do alvo e de onde a estrada passa baixa (a árvore atravessaria).
func _criar_vegetacao_subida() -> void:
	# Refeita a cada etapa (as cristas do caminho ao alvo mudam): num nó próprio para trocar inteira
	if _veg_subida:
		_veg_subida.queue_free()
	_veg_subida = Node3D.new()
	_veg_subida.name = "VegetacaoSubida"
	add_child(_veg_subida)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) + 700
	var nivel_agua := float(Config.valor("mapa.nivel_agua", 4))
	var qtd: Array = Config.valor("mapa.subida.vegetacao", [9000, 16000, 30000])
	var largada: Array = Config.valor("mapa.subida.largada.origem", [0, 0, 0])
	var plataforma: Array = Config.valor("mapa.subida.plataforma.origem", [0, 0, 0])
	var evitar := [
		[Vector2(float(largada[0]) + 35.0, float(largada[2])), 80.0],
		[Vector2(float(plataforma[0]), float(plataforma[2]) + 50.0), 95.0],
		[Vector2.ZERO, 60.0],
	]
	var arvores := []
	var arbustos := []
	var capim := []
	var tentativas := 0
	while (arvores.size() < int(qtd[0]) or arbustos.size() < int(qtd[1]) or capim.size() < int(qtd[2])) and tentativas < 500000:
		tentativas += 1
		var x := rng.randf_range(_sub_vale[0] - 120.0, _sub_vale[2] + 120.0)
		var z := rng.randf_range(_sub_vale[1] - 120.0, _sub_vale[3] + 120.0)
		var p := Vector2(x, z)
		var fora := false
		for e in evitar:
			if p.distance_to(e[0]) < e[1]:
				fora = true
		if fora:
			continue
		var h := altura_em(x, z)
		if h < nivel_agua + 1.0:
			continue
		if not _sub_tunel.is_empty() and _cavar_tunel(p, INF) < INF:
			continue   # vala do túnel: a planta atravessaria o piso dele
		var baixa := _estrada_baixa_perto(p, h)
		var sorteio := rng.randf()
		if sorteio < 0.32 and arvores.size() < int(qtd[0]) and not baixa and _plano(x, z, 7.0):
			arvores.append([Vector3(x, h - 0.3, z), rng.randf_range(1.3, 2.8), rng.randf() * TAU, Color(0.7, 1.05, 0.65) * rng.randf_range(0.8, 1.1)])
		elif sorteio < 0.62 and arbustos.size() < int(qtd[1]) and _plano(x, z, 6.0):
			arbustos.append([Vector3(x, h - 0.1, z), rng.randf_range(1.2, 2.6), rng.randf() * TAU, Color(0.8, 1.05, 0.72) * rng.randf_range(0.8, 1.15)])
		elif capim.size() < int(qtd[2]) and _plano(x, z, 3.0):
			capim.append([Vector3(x, h - 0.05, z), rng.randf_range(1.0, 1.9), rng.randf() * TAU, Color(0.9, 1.05, 0.8) * rng.randf_range(0.75, 1.15)])
	Vegetacao.plantar(_veg_subida, Vegetacao.Tipo.ZIMBRO, arvores, 400.0, 2400.0, true)
	Vegetacao.plantar(_veg_subida, Vegetacao.Tipo.SALVIA, arbustos, 300.0, 1400.0, false)
	Vegetacao.plantar(_veg_subida, Vegetacao.Tipo.CAPIM, capim, 120.0, 350.0, false)


## A estrada passa a menos de 12 m daqui e a menos de 25 m do chão (árvore atravessaria).
func _estrada_baixa_perto(p: Vector2, chao: float) -> bool:
	for pts: PackedVector3Array in _sub_estrada:
		for i in range(1, pts.size()):
			var a := Vector2(pts[i - 1].x, pts[i - 1].z)
			var b := Vector2(pts[i].x, pts[i].z)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
			if p.distance_to(a + ab * t) < 14.0 and lerpf(pts[i - 1].y, pts[i].y, t) - chao < 25.0:
				return true
	return false


## Dentro do vale do Canyon Combat (com folga para os lados), onde a vegetação e o relevo mudam por etapa.
func _dentro_do_vale(x: float, z: float, folga: float) -> bool:
	if _modo_subida:
		return x > _sub_vale[0] - folga and x < _sub_vale[2] + folga and z > _sub_vale[1] - folga and z < _sub_vale[3] + folga
	if not _canion_fechado:
		return false
	var q := _no_vale(x, z)
	return q.x > -_vale_fundo - folga and q.x < distancia_saida + 60.0 and absf(q.y) < meia_largura_vale(q.x) + folga


func _plano(x: float, z: float, limite: float) -> bool:
	var dx := altura_em(x + 6.0, z) - altura_em(x - 6.0, z)
	var dz := altura_em(x, z + 6.0) - altura_em(x, z - 6.0)
	return absf(dx) + absf(dz) <= limite


## Bancos de bruma baixos nos vales (só visual; não colidem).
func _criar_bruma() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) + 91
	var nivel_agua := float(Config.valor("mapa.nivel_agua", 4))
	var transformacoes: Array[Transform3D] = []
	var sementes := PackedFloat32Array()
	var tentativas := 0
	while transformacoes.size() < 320 and tentativas < 20000:
		tentativas += 1
		var x := rng.randf_range(-MEIO_INTERNO * 1.6, MEIO_INTERNO * 1.6)
		var z := rng.randf_range(-MEIO_INTERNO * 1.6, MEIO_INTERNO * 1.6)
		if Vector2(x, z).length() < 600.0 or _dentro_do_vale(x, z, 300.0):
			continue  # deixa a área do alvo limpa
		var h := altura_em(x, z)
		if h > 70.0:
			continue  # só nos vales
		var esc := rng.randf_range(90.0, 220.0)
		var y := maxf(h, nivel_agua) + rng.randf_range(12.0, 40.0)
		transformacoes.append(Transform3D(Basis.from_scale(Vector3.ONE * esc), Vector3(x, y, z)))
		sementes.append(rng.randf() * 10.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bruma.gdshader")
	mat.set_shader_parameter("ruido", _textura_ruido(0.02, 4, 97))
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = transformacoes.size()
	for i in transformacoes.size():
		mm.set_instance_transform(i, transformacoes[i])
		mm.set_instance_custom_data(i, Color(sementes[i], 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-MEIO_INTERNO * 2.0, -50.0, -MEIO_INTERNO * 2.0), Vector3(MEIO_INTERNO * 4.0, 400.0, MEIO_INTERNO * 4.0))
	add_child(mmi)


func _chave_cache() -> String:
	var partes := [VERSAO_CACHE, Config.mapa_id, Config.valor("mapa", {}), perfil.comprimento_horizontal]
	return "user://cache/terreno_%s.bin" % str(partes).md5_text().substr(0, 12)


func _carregar_cache() -> bool:
	var caminho := _chave_cache()
	if not FileAccess.file_exists(caminho):
		return false
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return false
	var a = f.get_var()
	var b = f.get_var()
	if a is PackedFloat32Array and b is PackedFloat32Array and a.size() == N_INTERNO * N_INTERNO and b.size() == N_EXTERNO * N_EXTERNO:
		alturas_interno = a
		alturas_externo = b
		return true
	return false


func _salvar_cache() -> void:
	DirAccess.make_dir_recursive_absolute("user://cache")
	var f := FileAccess.open(_chave_cache(), FileAccess.WRITE)
	if f:
		f.store_var(alturas_interno)
		f.store_var(alturas_externo)
