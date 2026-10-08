class_name ComplexoSubida
extends ComplexoLancamento
## Climb to Death (desenho do dono visto de cima): largada num cercado no chão, estrada elevada
## em pilares que SÓ SOBE (sem cerca lateral: dá para empurrar rivais para fora), plataforma murada
## a 100 m com buracos da morte, rampa de salto por cima de um vão de 30 m, e a rampa final a
## 230 m que lança os carros para o alvo. Um morro de 300 m entre a subida e o alvo impede pular
## antes da hora. Tocar no chão explode; quem cai e consegue pousar de paraquedas num trecho mais
## baixo da estrada continua.
##
## Progresso no percurso (x_perfil): metros desde o fundo da largada, somando cercado, trechos de
## estrada, plataforma e o vão. A saída da rampa final é perfil.comprimento_horizontal.

const ESPESSURA_ESTRADA := 1.4
const CELULA_GRADE := 24.0

var largada: Recinto
var plataforma: Recinto
var largura_estrada := 10.0

# Amostras da estrada (1 m), de todos os trechos em sequência
var _pts := PackedVector3Array()
var _tan := PackedVector3Array()
var _lat := PackedVector3Array()
var _s := PackedFloat32Array()         # progresso de cada amostra
var _trecho := PackedInt32Array()      # 0 = A (largada → plataforma), 1 = B (→ salto), 2 = C (→ rampa final)
var _curv := PackedFloat32Array()      # curvatura horizontal (1/raio)
var _grade := {}                       # Vector2i → PackedInt32Array de amostras
var _inicio_trecho: Array[int] = []
var _fim_trecho: Array[int] = []
var _impulsos_estrada: Array = []      # [centro, tangente, lateral, normal, velocidade]
var _larg := PackedFloat32Array()      # largura da estrada em cada amostra (zona de pouso do salto mais larga)
## Frozen Peak: vãos na estrada (amostras sem piso: o carro tem de saltar) e aderência do piso em
## cada amostra (1 = normal; menos = gelo vivo). Ver percursos.N.vaos / estreitos / gelo.
var _vao := PackedByteArray()
var _ader := PackedFloat32Array()
var _ilhas_pista: Array = []           # plataformas redondas no lugar da estrada: [{ilhas, rampas, ini, fim, k, cfg}]
var _vaos: Array = []                  # [{i0 (lábio), i1 (pouso), s0, s1, trecho}] em ordem
var _s_largada_fim := 0.0
var _s_plat_ini := 0.0
var _s_plat_fim := 0.0
var s_salto := 0.0                     # progresso da borda da rampa de salto
var s_final := 0.0                     # progresso da borda da rampa final
var borda_salto := Vector3.ZERO        # ponta da rampa de salto (fim do trecho B)
## Pontos de checagem (mapa.subida.checkpoints): [{i, s, pos, tan, lat, mat}] em ordem no percurso
var checkpoints: Array[Dictionary] = []
var fantasma_s := 3.0
var _raio_cp := 6.5
var _altura_cp := 6.0
var _terreno: Terreno
## Bifurcações (Extinction Day, pedido do dono): rotas alternativas que saem da estrada e voltam a ela
## mais adiante, cada uma com um desafio próprio. As amostras de cada desvio entram depois das de
## A/B/C como um trecho a mais (nome em _nomes_trecho); o progresso delas vai de s(de) a s(para).
## tipo "ilhas": colunas de basalto soltas no ar (pula-se de uma para outra pelas rampinhas);
## "catapulta": gêiser que lança o carro para um deque alto (atalho); "estrada": só o traçado.
var desvios: Array[Dictionary] = []
var _nomes_trecho: Array[String] = ["A", "B", "C"]
var _n_principal := 0                   # amostras de A/B/C (o resto são desvios)
var _catapultas: Array[Dictionary] = [] # {pos, dir, raio, periodo, ativo_s, fase, vel_h, vel_v, mats, fogo}
var _relogio_desvios := 0.0
var _cat_estrada: Array = []            # catapultas de madeira na estrada principal (marcadas antes da malha)
const CESTO_MEIO := 4.5                 # meio comprimento do cesto da catapulta (m)
var _loopings: Array[Looping] = []      # loopings do percurso (percursos.N.loopings)
var _res: Array = []                    # aceleradores contrários (jogam para trás): [{i, s, lat, meia}]
var _ejetores: Array = []               # molas que lançam o carro para cima: [{i, s, pos, vy, comp, faixa, meio_passo, prato, molas, t}]
var _mat_pista: ShaderMaterial
var _tunel: TunelAtalho   # túnel-atalho da etapa atual (se a etapa tiver)
var _paredao: ParedaoFino # paredão fino com buraco de atalho da etapa atual (se a etapa tiver)


## Percurso da etapa (Serpent's Climb: cada etapa tem um percurso próprio em mapa.subida.percursos.N,
## que sobrepõe as chaves de mapa.subida — largada, plataforma, trechos, impulsos, armadilhas...).
static var etapa_percurso := 0
var _percurso_montado := -1
var _no: Node3D                         # tudo que é do percurso (refeito quando o percurso muda)
var armadilhas: Armadilhas


## Valor de mapa.subida.<chave>, com o percurso da etapa atual na frente (se o mapa tiver percursos).
static func cfg_sub(chave: String, padrao = null):
	var v = Config.valor("mapa.subida.percursos.%d.%s" % [etapa_percurso + 1, chave], null)
	if v != null:
		return v
	return Config.valor("mapa.subida." + chave, padrao)


static func tem_percursos() -> bool:
	return not (Config.valor("mapa.subida.percursos", {}) as Dictionary).is_empty()


## Pontos de controle de um trecho da estrada (config mapa.subida.trechos), no mundo.
static func pontos_trecho(nome: String) -> PackedVector3Array:
	var lista := PackedVector3Array()
	for p in cfg_sub("trechos." + nome, []):
		lista.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return lista


func montar(p_indice: int, p_perfil: PerfilRampa, terreno: Terreno) -> void:
	indice_equipe = p_indice
	perfil = p_perfil
	_terreno = terreno
	distancia_saida = Config.valor("mapa.distancia_saida_alvo", 800)
	name = "ClimbToDeath"
	cor = Color(1.0, 0.45, 0.08)
	_construir()


## Monta (ou refaz, na troca de etapa de um mapa com percursos) largada, plataforma, estrada,
## checkpoints, pistões e armadilhas do percurso da etapa atual.
func _construir() -> void:
	_percurso_montado = etapa_percurso
	if _no:
		_no.name = "PercursoVelho"
		_no.queue_free()
	_no = Node3D.new()
	_no.name = "Percurso"
	add_child(_no)
	var terreno := _terreno
	_pts = PackedVector3Array()
	_tan = PackedVector3Array()
	_lat = PackedVector3Array()
	_s = PackedFloat32Array()
	_trecho = PackedInt32Array()
	_curv = PackedFloat32Array()
	_larg = PackedFloat32Array()
	_vao = PackedByteArray()
	_ader = PackedFloat32Array()
	_vaos.clear()
	_grade.clear()
	_inicio_trecho.clear()
	_fim_trecho.clear()
	_impulsos_estrada.clear()
	_n_impulsos_base = -1
	checkpoints.clear()
	_pistoes.clear()
	desvios.clear()
	_catapultas.clear()
	_loopings.clear()
	_res.clear()
	_ejetores.clear()
	_nomes_trecho.assign(["A", "B", "C"])
	armadilhas = null
	largura_estrada = float(cfg_sub("largura_estrada", 10))
	largura = largura_estrada
	impulso_velocidade = float(cfg_sub("impulso_velocidade", 22))
	_estruturas = StaticBody3D.new()
	_estruturas.name = "Estruturas"
	_estruturas.collision_layer = 1
	_estruturas.collision_mask = 0
	_estruturas.add_to_group("estrutura")
	_no.add_child(_estruturas)
	if OS.get_environment("TSC_SUB_LOG") != "":
		for q: Vector2 in [Vector2(-1530, -300), Vector2(-1000, -500), Vector2(-600, -300), Vector2(0, -800), Vector2(-300, -200), Vector2(0, 0)]:
			print("[SUB] terreno em ", q, " = ", terreno.altura_em(q.x, q.y))
	_montar_largada(terreno)
	_montar_plataforma_alta(terreno)
	_montar_estrada(terreno)
	# Direções da rampa final (câmera, alvo, partida): do alvo para a rampa e sentido do lançamento
	var n := _pts.size()
	var t_final := _tan[_fim_trecho[2]]
	frente = Vector3(t_final.x, 0.0, t_final.z).normalized()
	direcao = -frente
	lateral = frente.cross(Vector3.UP).normalized()
	x_inicio_pista = 0.0
	perfil.comprimento_horizontal = s_final
	_semaforo.clear()
	_semaforo.append_array(largada.semaforo_lampadas)
	semaforo(0)


# ------------------------------------------------------------------ montagem

## Pharaoh's Climb: estrada de lajes de calcário, pilares de arenito e pistões de granito.
func _egito() -> bool:
	return str(cfg_sub("tema", "")) == "egito"


## Serpent's Climb: calçada de pedra com musgo, pilares de pedra com relevo asteca.
func _selva() -> bool:
	return str(cfg_sub("tema", "")) == "selva"


## Frozen Peak: estrada de neve batida com trechos de gelo vivo, pilares de concreto com geada e aço.
func _gelo() -> bool:
	return str(cfg_sub("tema", "")) == "gelo"


func _shader_pista() -> String:
	if _gelo():
		return "res://shaders/pista_gelo.gdshader"
	if _selva():
		return "res://shaders/pista_selva.gdshader"
	return "res://shaders/pista_egito.gdshader" if _egito() else "res://shaders/pista.gdshader"


## Extinction Day à noite (mapa.subida.percursos.N.asfalto): cor do asfalto [r, g, b] e sem neon nas bordas.
func _ajustar_pista(mat: ShaderMaterial) -> void:
	var c = cfg_sub("asfalto", null)
	if c is Array:
		mat.set_shader_parameter("cor_asfalto", Color(float(c[0]), float(c[1]), float(c[2])))
		mat.set_shader_parameter("neon_borda", 0.0)
		mat.set_shader_parameter("brilho_proprio", float(cfg_sub("asfalto_brilho", 0.22)))


func _shader_lateral() -> String:
	if _gelo():
		return "res://shaders/lateral_gelo.gdshader"
	if _selva():
		return "res://shaders/lateral_selva.gdshader"
	return "res://shaders/lateral_egito.gdshader" if _egito() else "res://shaders/lateral_pista.gdshader"


func _material_pilar() -> Material:
	if str(cfg_sub("tema", "")) == "dino":
		# Extinction Day: concreto escuro, manchado de umidade e musgo (os pilares altos somem na mata)
		var m := material_concreto(0.0)
		m.set_shader_parameter("cor_base", Color(0.22, 0.22, 0.2))
		m.set_shader_parameter("cor_mancha", Color(0.12, 0.15, 0.1))
		m.set_shader_parameter("cor_poeira", Color(0.2, 0.26, 0.12))
		m.set_shader_parameter("altura_poeira", 14.0)
		m.set_shader_parameter("sujeira", 0.85)
		return m
	if _gelo():
		return Gelo.material(Gelo.Mat.CONCRETO)
	if _selva():
		return Selva.material_pedra(0, 1.3)
	return _material_pedra_egito(1.2) if _egito() else material_concreto(0.0)


func _material_viga() -> Material:
	if _gelo():
		return Gelo.material(Gelo.Mat.ACO)
	if _selva():
		return Selva.material_pedra(2, 1.0)
	return _material_pedra_egito(1.0) if _egito() else material_aco(0.0, 0.5)


func _material_pedra_egito(fiada: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pedra_egito.gdshader")
	m.set_shader_parameter("modo", 0)
	m.set_shader_parameter("fiada", fiada)
	m.set_shader_parameter("bloco", 1.6)
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 113))
	m.set_shader_parameter("altura_chao", 6.0)
	return m


func _recinto_cfg(r: Recinto, cfg: Dictionary) -> void:
	r.comprimento = float(cfg.get("comprimento", 70))
	r.largura_arena = float(cfg.get("largura", 90))
	r.saida_largura = float(cfg.get("saida_largura", 12))
	r.muro_altura = float(cfg.get("muro_altura", 2.6))
	r.grade_altura = float(cfg.get("grade_altura", 7.4))
	for b in cfg.get("buracos", []):
		r.buracos.append([Vector2(float(b[0]), float(b[1])), float(b[2])])
	for im in cfg.get("impulsos", []):
		r.impulsos.append([Vector2(float(im[0]), float(im[1])), deg_to_rad(float(im[2])), bool(im[3])])
	r.entradas = cfg.get("entradas", [])
	r.vagas = cfg.get("vagas", [])
	r.nome_placa = str(cfg.get("placa", ""))
	r.placa_imagem = str(cfg.get("placa_imagem", ""))
	r.portico_arte = str(cfg.get("portico_arte", ""))
	r.tema = str(cfg_sub("tema", ""))
	r.aderencia = float(cfg.get("aderencia", 1.0))
	r.sem_piso = bool(cfg.get("sem_piso", false))
	r.entrada_fundo = float(cfg.get("entrada_fundo", 0.0))
	r.buracos_agua = bool(cfg.get("buracos_agua", false))
	for m in cfg.get("molas", []):
		r.molas.append([Vector2(float(m[0]), float(m[1])), float(m[2]) if m.size() > 2 else 9.0])
	r.forrar_portas()


func _montar_largada(terreno: Terreno) -> void:
	var cfg: Dictionary = cfg_sub("largada", {})
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    subida: antes da largada" % Time.get_ticks_msec())
	largada = Recinto.new()
	largada.name = "Largada"
	_recinto_cfg(largada, cfg)
	var o: Array = cfg.get("origem", [-1560, 10, -300])
	var f: Array = cfg.get("frente", [1, 0])
	_no.add_child(largada)
	var origem := Vector3(float(o[0]), float(o[1]), float(o[2]))
	largada.montar(origem, Vector3(float(f[0]), 0.0, float(f[1])), terreno.altura_em(origem.x, origem.z))
	_s_largada_fim = largada.comprimento


func _montar_plataforma_alta(terreno: Terreno) -> void:
	var cfg: Dictionary = cfg_sub("plataforma", {})
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    subida: largada" % Time.get_ticks_msec())
	plataforma = Recinto.new()
	plataforma.name = "Plataforma100"
	_recinto_cfg(plataforma, cfg)
	var o: Array = cfg.get("origem", [-900, 100, -600])
	var f: Array = cfg.get("frente", [0, 1])
	_no.add_child(plataforma)
	var origem := Vector3(float(o[0]), float(o[1]), float(o[2]))
	plataforma.montar(origem, Vector3(float(f[0]), 0.0, float(f[1])), terreno.altura_em(origem.x, origem.z))
	if cfg.get("espinhos") is Dictionary:   # campo de espinhos em volta do recinto (ninguém contorna por fora)
		EspinhosSelva.montar(plataforma, terreno, cfg.espinhos)


## Amostra a curva suave (Catmull-Rom) que passa pelos pontos de controle, a cada ~1 m.
static func _amostrar_curva(ctrl: PackedVector3Array) -> PackedVector3Array:
	var curva := Curve3D.new()
	curva.bake_interval = 1.0
	var n := ctrl.size()
	for i in n:
		var ant := ctrl[maxi(i - 1, 0)]
		var prox := ctrl[mini(i + 1, n - 1)]
		var h := (prox - ant) / 6.0
		curva.add_point(ctrl[i], -h, h)
	return curva.get_baked_points()


func _montar_estrada(terreno: Terreno) -> void:
	var s := 0.0
	for k in 3:
		var nome: String = ["A", "B", "C"][k]
		var amostras := _amostrar_curva(pontos_trecho(nome))
		if k == 0:
			s = _s_largada_fim
		elif k == 1:
			_s_plat_ini = s
			s += plataforma.comprimento * 0.5 + plataforma.largura_arena * 0.5   # entra pela lateral, sai pela frente
			_s_plat_fim = s
		elif k == 2:
			s += amostras[0].distance_to(_pts[_pts.size() - 1])   # o vão do salto
		_inicio_trecho.append(_pts.size())
		for i in amostras.size():
			if i > 0:
				s += amostras[i].distance_to(amostras[i - 1])
			_pts.append(amostras[i])
			_s.append(s)
			_trecho.append(k)
		_fim_trecho.append(_pts.size() - 1)
		if k == 1:
			s_salto = s
			borda_salto = _pts[_pts.size() - 1]
	s_final = s
	_n_principal = _pts.size()
	_amostrar_desvios()
	# Tangentes, laterais e curvatura
	var n := _pts.size()
	_tan.resize(n)
	_lat.resize(n)
	_curv.resize(n)
	for i in n:
		var a := i - 1 if i > 0 and _trecho[i - 1] == _trecho[i] else i
		var b := i + 1 if i < n - 1 and _trecho[i + 1] == _trecho[i] else i
		var t := (_pts[b] - _pts[a]).normalized()
		_tan[i] = t
		_lat[i] = t.cross(Vector3.UP).normalized()
	for i in n:
		var a := maxi(i - 6, _inicio_trecho[_trecho[i]])
		var b := mini(i + 6, _fim_trecho[_trecho[i]])
		var ta := Vector2(_tan[a].x, _tan[a].z).normalized()
		var tb := Vector2(_tan[b].x, _tan[b].z).normalized()
		var dist := maxf(_s[b] - _s[a], 1.0)
		_curv[i] = absf(ta.angle_to(tb)) / dist
	# Zona de pouso depois do vão: mais larga no começo do trecho C, afinando até a largura normal
	var zp: Dictionary = cfg_sub("zona_pouso", {})
	_larg.resize(n)
	for i in n:
		_larg[i] = largura_estrada
		if _trecho[i] == 2 and not zp.is_empty():
			var d := _s[i] - _s[_inicio_trecho[2]]
			var comp := float(zp.get("comprimento", 130))
			var trans := float(zp.get("transicao", 40))
			_larg[i] = lerpf(float(zp.get("largura", 14)), largura_estrada, clampf((d - comp) / trans, 0.0, 1.0))
	# Começo do trecho A mais largo (mapa.subida.largura_inicio): todos saem juntos da largada
	var li: Dictionary = cfg_sub("largura_inicio", {})
	if not li.is_empty():
		for i in range(_inicio_trecho[0], _fim_trecho[0] + 1):
			var d := _s[i] - _s[_inicio_trecho[0]]
			_larg[i] = maxf(_larg[i], lerpf(float(li.get("largura", 16)), largura_estrada, clampf((d - float(li.get("comprimento", 150))) / float(li.get("transicao", 50)), 0.0, 1.0)))
	for d in desvios:
		for i in range(d.ini, d.fim + 1):
			_larg[i] = float(d.largura)
		# Pontas em cunha (pedido do dono: o desvio tem de emendar na estrada, não acabar num corte reto):
		# nos primeiros e nos últimos metros a borda de fora vem fechando até a borda encostada na estrada
		var bico := float((d.cfg as Dictionary).get("bico", 26.0))
		var metros: PackedFloat32Array = d.metros
		for ponta in 2:
			var i_estrada: int = d.i_de if ponta == 0 else d.i_para
			var i_ponta: int = d.ini if ponta == 0 else d.fim
			var lado := signf((_pts[i_estrada] - _pts[i_ponta]).dot(_lat[i_ponta]))
			if lado == 0.0:
				continue
			for i in range(d.ini, d.fim + 1):
				var m := metros[i - int(d.ini)]
				var dist := m if ponta == 0 else float(d.comp) - m
				if dist >= bico:
					continue
				var f := maxf(dist / bico, 0.04)
				var larg_cheia := float(d.largura)
				var borda := _pts[i] + _lat[i] * lado * larg_cheia * 0.5   # a borda do lado da estrada não se mexe
				_larg[i] = larg_cheia * f
				_pts[i] = borda - _lat[i] * lado * _larg[i] * 0.5
	# Plataforma sem chão: começo do B largo (pouso de paraquedas depois do portão)
	if plataforma.sem_piso:
		for i in range(_inicio_trecho[1], _fim_trecho[1] + 1):
			var d := _s[i] - _s[_inicio_trecho[1]]
			_larg[i] = maxf(_larg[i], lerpf(20.0, largura_estrada, clampf((d - 70.0) / 40.0, 0.0, 1.0)))
	_marcar_estreitos_gelo_vaos()
	_marcar_desvios()
	_marcar_loopings()
	for i in n:
		var c := Vector2i(floori(_pts[i].x / CELULA_GRADE), floori(_pts[i].z / CELULA_GRADE))
		var lista: PackedInt32Array = _grade.get(c, PackedInt32Array())
		lista.append(i)   # PackedInt32Array é copiado por valor: precisa guardar de volta
		_grade[c] = lista
	_malha_estrada()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    subida: plataforma e estrada" % Time.get_ticks_msec())
	_pilares(terreno)
	_luzes_bordas()
	_meio_fio()
	_montar_impulsos_estrada()
	for lp in _loopings:
		_no.add_child(lp)
		lp.montar(self, _mat_pista, _impulsos_estrada)
	_montar_checkpoints()
	_montar_pistoes()
	_montar_desvios()
	if not (cfg_sub("armadilhas", {}) as Dictionary).is_empty():
		if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    subida: pilares" % Time.get_ticks_msec())
		armadilhas = ArmadilhasDino.new() if str(cfg_sub("tema", "")) == "dino" else Armadilhas.new()
		armadilhas.name = "Armadilhas"
		armadilhas.gelo = _gelo()
		_no.add_child(armadilhas)
		armadilhas.montar(self, cfg_sub("armadilhas", {}), _terreno)
		_sumico_de_longe()
		if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    subida: armadilhas" % Time.get_ticks_msec())
	if _gelo():
		var enfeites := EnfeitesGelo.new()
		_no.add_child(enfeites)
		enfeites.montar(self, _terreno)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SUB] amostras=", _pts.size(), " trechos=", _inicio_trecho, "..", _fim_trecho, " s_salto=", s_salto, " s_final=", s_final)
		for i in [0, 1, 5, 20, 60, 120]:
			print("[SUB] amostra ", i, " = ", _pts[i], " s=", _s[i])
		# Mapa de metragem: posição de cada trecho a cada 50 m (achar [trecho, m] pelo que se vê na câmera livre)
		for k in _nomes_trecho.size():
			var i := _inicio_trecho[k]
			while i <= _fim_trecho[k]:
				print("[TRECHO] %s %d %s" % [_nomes_trecho[k], roundi(_s[i] - _s[_inicio_trecho[k]]), str(_pts[i].snapped(Vector3.ONE))])
				var alvo_s := _s[i] + 50.0
				while i <= _fim_trecho[k] and _s[i] < alvo_s:
					i += 1
		# Folga entre o asfalto (e as beiradas) e o terreno: o morro encostado não pode atravessar
		var pior := INF
		var perto := 0
		for i in _pts.size():
			for lado: float in [-1.0, 0.0, 1.0]:
				var q: Vector3 = _pts[i] + _lat[i] * lado * _larg[i] * 0.5
				var folga: float = q.y - terreno.altura_em(q.x, q.z)
				pior = minf(pior, folga)
				if lado == 0.0 and folga < 15.0:
					perto += 1
		print("[SUB] folga mínima estrada-terreno = %.2f m; amostras com terreno a menos de 15 m = %d" % [pior, perto])
		# Cristas do caminho ao alvo: altura do terreno no meio de cada ponto da rota (fendas) e ao lado
		for etapa in 4:
			terreno.preparar_etapa(etapa)
			var linha := "[SUB] etapa %d rota:" % (etapa + 1)
			for w in terreno.rota_vale():
				linha += " (%d,%d h=%.0f ao lado=%.0f)" % [w.x, w.z, terreno.altura_em(w.x, w.z), terreno.altura_em(w.x + 45.0, w.z)]
			print(linha)
		terreno.preparar_etapa(0)


## Frozen Peak: estreitos [[trecho, m0, m1, largura]] (a estrada afina, com 14 m de transição),
## gelo [[trecho, m0, m1, aderência]] e vãos [[trecho, x, y, z, comprimento]]: o lábio da rampinha
## é a amostra mais perto do ponto; dali por `comprimento` m não há piso (o carro tem de saltar).
## As amostras do vão continuam existindo (progresso, bots), só não têm asfalto.
func _marcar_estreitos_gelo_vaos() -> void:
	var n := _pts.size()
	_vao.resize(n)
	_vao.fill(0)
	_ader.resize(n)
	_ader.fill(1.0)
	const TRANS := 14.0
	for e in cfg_sub("estreitos", []):
		var k := _nomes_trecho.find(str(e[0]))
		if k < 0:
			continue
		var s0 := _s[_inicio_trecho[k]]
		for i in range(_inicio_trecho[k], _fim_trecho[k] + 1):
			var m := _s[i] - s0
			var w := smoothstep(float(e[1]) - TRANS, float(e[1]), m) * (1.0 - smoothstep(float(e[2]), float(e[2]) + TRANS, m))
			_larg[i] = lerpf(_larg[i], minf(_larg[i], float(e[3])), w)
	for g in cfg_sub("gelo", []):
		var k := _nomes_trecho.find(str(g[0]))
		if k < 0:
			continue
		var s0 := _s[_inicio_trecho[k]]
		for i in range(_inicio_trecho[k], _fim_trecho[k] + 1):
			var m := _s[i] - s0
			if m >= float(g[1]) and m <= float(g[2]):
				_ader[i] = float(g[3])
	for v in cfg_sub("vaos", []):
		var k := _nomes_trecho.find(str(v[0]))
		if k < 0:
			continue
		var p := Vector3(float(v[1]), float(v[2]), float(v[3]))
		var i0 := _inicio_trecho[k]
		for i in range(_inicio_trecho[k], _fim_trecho[k] + 1):
			if _pts[i].distance_squared_to(p) < _pts[i0].distance_squared_to(p):
				i0 = i
		var i1 := i0
		while i1 < _fim_trecho[k] and _s[i1] - _s[i0] < float(v[4]):
			i1 += 1
		for i in range(i0 + 1, i1):
			_vao[i] = 1
		_vaos.append({"i0": i0, "i1": i1, "s0": _s[i0], "s1": _s[i1], "trecho": k})
	_vaos.sort_custom(func(a, b): return a.s0 < b.s0)
	# Gelo fino (armadilhas.placas [[trecho, m0, m1]]): sem laje — o piso são as placas que quebram
	var arm_cfg: Dictionary = cfg_sub("armadilhas", {})
	for pl in arm_cfg.get("placas", []) + arm_cfg.get("lajes", []) + arm_cfg.get("pontes", []):
		var k := _nomes_trecho.find(str(pl[0]))
		if k < 0:
			continue
		var s0 := _s[_inicio_trecho[k]]
		for i in range(_inicio_trecho[k], _fim_trecho[k] + 1):
			var m := _s[i] - s0
			if m > float(pl[1]) + 0.5 and m < float(pl[2]) - 0.5:
				_vao[i] = 2


## Loopings (percursos.N.loopings: [trecho, m da entrada, raio, transição, desvio, aceleradores,
## velocidade mínima, largura da fita, borda]): calcula a fita de cada um e tira a laje da estrada embaixo dele — o traçado
## passa por baixo em "S" só para o progresso e os bots; o piso é a fita (classe Looping).
func _marcar_loopings() -> void:
	# Depois de cada mola ejetora a pista fica mais larga (zona de pouso de quem caiu girando)
	for ej in cfg_sub("ejetores", []):
		var ie := indice_trecho(str(ej[0]), float(ej[1]))
		if ie < 0:
			continue
		var j := ie
		while j < _fim_trecho[_trecho[ie]] and _s[j] - _s[ie] < 170.0:
			var d := _s[j] - _s[ie]
			_larg[j] = maxf(_larg[j], lerpf(largura_estrada, 16.0, smoothstep(12.0, 40.0, d) * (1.0 - smoothstep(130.0, 170.0, d))))
			j += 1
	const CORTE := 12.0   # a fita nasce colada na estrada: a laje só some quando ela já subiu
	for lc in cfg_sub("loopings", []):
		var i0 := indice_trecho(str(lc[0]), float(lc[1]))
		if i0 < 0:
			continue
		var lp := Looping.new()
		lp.n_impulsos = int(lc[5])
		lp.vel_min = float(lc[6])
		if lc.size() > 7:
			lp.largura_laco = float(lc[7])
		if lc.size() > 8:
			lp.borda = bool(lc[8])
		lp.calcular(self, i0, float(lc[2]), float(lc[3]), float(lc[4]))
		for i in range(i0, lp.i_saida + 1):
			if _s[i] - _s[i0] > CORTE and _s[lp.i_saida] - _s[i] > CORTE:
				_vao[i] = 4
		# O "S" embaixo do laço não é curva de verdade: os bots não devem frear por causa dele
		for i in range(maxi(i0 - 12, _inicio_trecho[_trecho[i0]]), mini(lp.i_saida + 12, _fim_trecho[_trecho[i0]]) + 1):
			_curv[i] = 0.0
		_loopings.append(lp)


## Looping em que `p` está (em cima da fita), ou null.
func looping_em(p: Vector3, pontas := false) -> Looping:
	for lp in _loopings:
		if lp.amostra_em(p, pontas) >= 0:
			return lp
	return null


## Para os bots: mira de quem está na reta de chegada de um looping (Looping.mira_chegada); Vector3.INF se não está.
func looping_chegando(p: Vector3) -> Vector3:
	for lp in _loopings:
		var m := lp.mira_chegada(p)
		if m != Vector3.INF:
			return m
	return Vector3.INF


## Há um looping começando até `metros` à frente da amostra i (ou o carro ainda está saindo de um)?
func looping_adiante(i: int, metros: float) -> bool:
	for lp in _loopings:
		if _trecho[lp.i_entrada] == _trecho[i] and _s[lp.i_entrada] - _s[i] < metros and _s[i] - _s[lp.i_saida] < 20.0:
			return true
	return false


func _malha_estrada() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_gelo := SurfaceTool.new()
	st_gelo.begin(Mesh.PRIMITIVE_TRIANGLES)
	var laterais := SurfaceTool.new()
	laterais.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	var faces_gelo := {}   # aderência → faces (um corpo por valor, com a meta "aderencia")
	for i in range(1, _pts.size()):
		if _trecho[i] != _trecho[i - 1]:
			continue
		var c0 := _pts[i - 1]
		var c1 := _pts[i]
		var l0 := _lat[i - 1]
		var l1 := _lat[i]
		var n0 := l0.cross(_tan[i - 1]).normalized()
		var n1 := l1.cross(_tan[i]).normalized()
		var m0 := _larg[i - 1] * 0.5
		var m1 := _larg[i] * 0.5
		var e0 := c0 - l0 * m0
		var d0 := c0 + l0 * m0
		var e1 := c1 - l1 * m1
		var d1 := c1 + l1 * m1
		if _vao[i] != 0 or _vao[i - 1] != 0:
			# Vão (ou gelo fino, cujas placas são da armadilha): sem piso. Nas duas pontas, a testa da laje (o lábio da rampinha e o começo do pouso)
			if _vao[i - 1] == 0:
				_quad_uv(laterais, [d0, e0, e0 - n0 * ESPESSURA_ESTRADA, d0 - n0 * ESPESSURA_ESTRADA], _tan[i - 1],
					[Vector2(0, 0), Vector2(m0 * 2.0, 0), Vector2(m0 * 2.0, 1), Vector2(0, 1)])
			if _vao[i] == 0:
				_quad_uv(laterais, [e1, d1, d1 - n1 * ESPESSURA_ESTRADA, e1 - n1 * ESPESSURA_ESTRADA], -_tan[i],
					[Vector2(0, 0), Vector2(m1 * 2.0, 0), Vector2(m1 * 2.0, 1), Vector2(0, 1)])
			continue
		var ad := maxf(_ader[i], _ader[i - 1])
		if ad < 0.999:
			_quad(st_gelo, e0, d0, d1, e1, n0, n1, Vector2(0, _s[i - 1]), Vector2(1, _s[i]))
			if not faces_gelo.has(ad):
				faces_gelo[ad] = PackedVector3Array()
			var fg: PackedVector3Array = faces_gelo[ad]
			fg.append_array([e0, d0, d1, e0, d1, e1])
			faces_gelo[ad] = fg
		else:
			_quad(st, e0, d0, d1, e1, n0, n1, Vector2(0, _s[i - 1]), Vector2(1, _s[i]))
			faces.append_array([e0, d0, d1, e0, d1, e1])
		var v0 := _s[i - 1]
		var v1 := _s[i]
		_quad_uv(laterais, [e0, e1, e1 - n1 * ESPESSURA_ESTRADA, e0 - n0 * ESPESSURA_ESTRADA], -l0,
			[Vector2(v0, 0), Vector2(v1, 0), Vector2(v1, 1), Vector2(v0, 1)])
		_quad_uv(laterais, [d0, d0 - n0 * ESPESSURA_ESTRADA, d1 - n1 * ESPESSURA_ESTRADA, d1], l0,
			[Vector2(v0, 0), Vector2(v0, 1), Vector2(v1, 1), Vector2(v1, 0)])
		_quad_uv(laterais, [e0 - n0 * ESPESSURA_ESTRADA, e1 - n1 * ESPESSURA_ESTRADA, d1 - n1 * ESPESSURA_ESTRADA, d0 - n0 * ESPESSURA_ESTRADA], -n0,
			[Vector2(v0, 0.5), Vector2(v1, 0.5), Vector2(v1, 0.5), Vector2(v0, 0.5)])
	var mat := ShaderMaterial.new()
	mat.shader = load(_shader_pista())
	mat.set_shader_parameter("cor_equipe", cor)
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 3))
	mat.set_shader_parameter("largura", largura_estrada)
	mat.set_shader_parameter("comp_plataforma", -1.0)
	mat.set_shader_parameter("linha_largada", -100.0)
	mat.set_shader_parameter("inicio_rampa", 1.0e9)
	_ajustar_pista(mat)
	_mat_pista = mat
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_no.add_child(mi)
	var mat_l := ShaderMaterial.new()
	mat_l.shader = load(_shader_lateral())
	mat_l.set_shader_parameter("cor_equipe", cor)
	var ml := MeshInstance3D.new()
	ml.mesh = laterais.commit()
	ml.material_override = mat_l
	_no.add_child(ml)
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
	_no.add_child(corpo)
	# Gelo vivo (Frozen Peak): malha própria, lisa e azulada, e um corpo por aderência — o Veiculo lê
	# a meta "aderencia" do corpo embaixo de cada roda
	if not faces_gelo.is_empty():
		var mat_g := ShaderMaterial.new()
		mat_g.shader = load("res://shaders/pista_gelo_vivo.gdshader")
		mat_g.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 3))
		mat_g.set_shader_parameter("largura", largura_estrada)
		var mg := MeshInstance3D.new()
		mg.mesh = st_gelo.commit()
		mg.material_override = mat_g
		_no.add_child(mg)
		for ad: float in faces_gelo:
			var cg := StaticBody3D.new()
			cg.collision_layer = 1
			cg.collision_mask = 0
			cg.add_to_group("estrutura")
			cg.set_meta("aderencia", ad)
			var fg := ConcavePolygonShape3D.new()
			fg.backface_collision = true
			fg.set_faces(faces_gelo[ad])
			var csg := CollisionShape3D.new()
			csg.shape = fg
			cg.add_child(csg)
			var pmg := PhysicsMaterial.new()
			pmg.friction = 0.15
			cg.physics_material_override = pmg
			_no.add_child(cg)


## Pilares da estrada principal: [Vector3(x, topo, z), meia largura, amostra] (SerpenteCaminho sobe neles).
var pilares: Array = []
var _tuneis_pista: TunelPista


## Pilares de concreto até o chão a cada ~22 m, com viga de apoio embaixo da estrada.
## Peças pequenas e muito detalhadas param de ser desenhadas de longe (a placa de vídeo desenhava ~9 milhões de
## triângulos delas de qualquer distância): pilares e grades das cercas dos recintos e as peças dos portais das
## armadilhas (a montanha em si continua aparecendo). A 1200 m elas são menores que um pixel.
func _sumico_de_longe() -> void:
	# (Níveis de detalhe gerados em tempo de execução para essas malhas — ImporterMesh.generate_lods — foram testados em
	# 2026-10-07 e NÃO ficaram: em fotos paradas a placa aliviava, mas passando de carro pela plataforma do
	# Serpent's Climb o driver da RX 5700 XT caiu em 6 de 10 passagens com eles e a GPU em movimento não melhorou.)
	for r: Node in [largada, plataforma]:
		if r == null:
			continue
		for mm: MultiMeshInstance3D in r.find_children("*", "MultiMeshInstance3D", true, false):
			if mm.visibility_range_end <= 0.0:
				mm.visibility_range_end = 1200.0
	if armadilhas:
		for filho in armadilhas.get_children():
			if not str(filho.name).begins_with("Lamina"):
				continue
			for mi: MeshInstance3D in filho.find_children("*", "MeshInstance3D", true, false):
				if mi.name != "Montanha" and mi.visibility_range_end <= 0.0 and mi.get_aabb().size.length() < 60.0:
					mi.visibility_range_end = 1200.0


func _pilares(terreno: Terreno) -> void:
	pilares.clear()
	var colunas: Array[Transform3D] = []
	var vigas: Array[Transform3D] = []
	var i := 0
	while i < _pts.size():
		var k := _trecho[i]
		if i - _inicio_trecho[k] < 12 or _fim_trecho[k] - i < 8:
			i += 1
			continue
		var p := _pts[i]
		if _sem_piso(i) or _sem_piso(i - 2) or _sem_piso(i + 2):
			i += 1   # vão do salto: sem pilar no ar (fica logo antes ou depois)
			continue
		if _estrada_embaixo(p, 9.0):
			i += 4   # outro trecho passa por baixo (o pilar cairia no meio dele): tenta um pouco adiante
			continue
		var chao := terreno.altura_em(p.x, p.z)
		var topo := p.y - ESPESSURA_ESTRADA - 0.6
		if topo - chao > 1.0:
			var b := Basis.looking_at(Vector3(_tan[i].x, 0.0, _tan[i].z).normalized(), Vector3.UP)
			var lado := 2.6 if topo - chao < 60.0 else 3.6
			colunas.append(Transform3D(b * Basis.from_scale(Vector3(lado, topo - chao + 2.0, lado)), Vector3(p.x, (topo + chao - 2.0) * 0.5, p.z)))
			pilares.append([Vector3(p.x, topo, p.z), lado * 0.5, i])
			vigas.append(Transform3D(b * Basis.from_scale(Vector3(_larg[i] - 1.0, 1.0, 2.2)), Vector3(p.x, topo + 0.3, p.z)))
		i += 22
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SUB] pilares (x, z): ", colunas.map(func(c: Transform3D): return Vector2(c.origin.x, c.origin.z).snapped(Vector2.ONE * 0.1)))
	var mat := _material_pilar()
	criar_multimesh(_no, colunas, mat)
	criar_multimesh(_no, vigas, _material_viga())
	adicionar_colisoes(_estruturas, colunas)


## Alguma amostra de estrada passa embaixo de p (a menos de `folga` m na horizontal e 4 m ou mais
## abaixo)? Pharaoh's Climb: a estrada que sai do topo da pirâmide cruza por cima da espiral.
func _estrada_embaixo(p: Vector3, folga: float) -> bool:
	var c := Vector2i(floori(p.x / CELULA_GRADE), floori(p.z / CELULA_GRADE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for j in _grade.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var d := _pts[j] - p
				if d.y < -4.0 and Vector2(d.x, d.z).length() < folga:
					return true
	return false


## Meio-fio baixo de pedra só no começo do trecho A (mapa.subida.meio_fio_inicio m): os 16 carros
## saem do cercado juntos, se empurram e, a 3 m do chão, quem escorregava da beirada explodia logo
## na largada. Depois dele a estrada segue sem cerca, como em todo o Climb.
func _meio_fio() -> void:
	var comp := float(cfg_sub("meio_fio_inicio", 0.0))
	if comp <= 0.0:
		return
	var pecas: Array[Transform3D] = []
	var i := _inicio_trecho[0]
	while i < _fim_trecho[0] and _s[i] - _s[_inicio_trecho[0]] < comp:
		var t := _tan[i]
		var n := _lat[i].cross(t).normalized()
		for lado: float in [-1.0, 1.0]:
			var p := _pts[i] + _lat[i] * lado * (_larg[i] * 0.5 - 0.3) + n * 0.3
			pecas.append(Transform3D(Basis.looking_at(t, n) * Basis.from_scale(Vector3(0.6, 0.6, 3.1)), p))
		i += 3
	criar_multimesh(_no, pecas, _material_pilar())
	adicionar_colisoes(_estruturas, pecas)


## Lâmpadas âmbar nas bordas da estrada, "correndo" no sentido da subida (sem guarda-corpo).
func _luzes_bordas() -> void:
	var luzes: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	for i in range(2, _pts.size(), 4):
		if _sem_piso(i) or _junto_de_outro(i):
			continue
		var meia := _larg[i] * 0.5
		var n := _lat[i].cross(_tan[i]).normalized()
		for lado: float in [-1.0, 1.0]:
			luzes.append(Transform3D(Basis.looking_at(_tan[i], n) * Basis.from_scale(Vector3(0.3, 0.3, 0.7)), _pts[i] + _lat[i] * (meia + 0.12) * lado - n * 0.3))
			fases.append(i * 0.15)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/luz_sequencial.gdshader")
	mat.set_shader_parameter("energia", 7.0)
	if _gelo():
		mat.set_shader_parameter("cor", Color(0.25, 0.8, 1.0))   # neon azul-gelo
	var neon = cfg_sub("neon", null)
	if neon is Array:
		mat.set_shader_parameter("cor", Color(float(neon[0]), float(neon[1]), float(neon[2])))
	criar_multimesh(_no, luzes, mat, false, fases)
	if bool(cfg_sub("neon_faixas", false)):
		_faixas_neon()
	if bool(cfg_sub("tochas", false)):
		_tochas()


## Extinction Day (etapas à noite, pedido do dono no lugar do neon): tochas de madeira presas na
## lateral da laje, alternando os lados a cada ~22 m, com braseiro de ferro e a chama (shader
## chama_tocha, uma chamada de desenho para todas). Uma em cada três ilumina a pista de verdade.
func _tochas() -> void:
	var postes: Array[Transform3D] = []
	var cestos: Array[Transform3D] = []
	var brasas: Array[Transform3D] = []
	var chamas: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	var luzes: Array[Vector3] = []
	var lado := 1.0
	var ultimo := -1000.0
	for i in range(_pts.size()):
		if _s[i] - ultimo < 22.0 or _vao[i] != 0 or _vao[maxi(i - 3, 0)] != 0 or _vao[mini(i + 3, _pts.size() - 1)] != 0:
			continue
		if i - _inicio_trecho[_trecho[i]] < 6 or _fim_trecho[_trecho[i]] - i < 6:
			continue
		ultimo = _s[i]
		lado = -lado
		if _junto_de_outro(i, lado):
			continue
		var t := _tan[i]
		var l := _lat[i] * lado
		var base := _pts[i] + l * (_larg[i] * 0.5 + 0.28)
		var b := Basis.looking_at(Vector3(t.x, 0.0, t.z).normalized(), Vector3.UP)
		postes.append(Transform3D(b * Basis.from_scale(Vector3(0.2, 4.6, 0.2)), base + Vector3.UP * 0.9))
		var topo := base + Vector3.UP * 3.25
		cestos.append(Transform3D(b * Basis(Vector3.UP, PI * 0.25) * Basis.from_scale(Vector3(0.55, 0.35, 0.55)), topo))
		brasas.append(Transform3D(b * Basis.from_scale(Vector3(0.38, 0.1, 0.38)), topo + Vector3.UP * 0.17))
		chamas.append(Transform3D(Basis.from_scale(Vector3(1.0, 1.7, 1.0)), topo + Vector3.UP * 0.12))
		fases.append(randf())
		if chamas.size() % 3 == 1:
			luzes.append(topo + Vector3.UP * 0.9 - l * 1.2)
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.2, 0.13, 0.08)
	madeira.roughness = 0.95
	criar_multimesh(_no, postes, madeira)
	var ferro := StandardMaterial3D.new()
	ferro.albedo_color = Color(0.09, 0.08, 0.07)
	ferro.metallic = 0.6
	ferro.roughness = 0.55
	criar_multimesh(_no, cestos, ferro)
	# As tochas têm colisão (pedido do dono: dava para atravessá-las): poste e braseiro, parede comum
	var solido := StaticBody3D.new()
	solido.collision_layer = 1
	solido.collision_mask = 0
	solido.add_to_group("estrutura")
	_no.add_child(solido)
	adicionar_colisoes(solido, postes)
	adicionar_colisoes(solido, cestos)
	criar_multimesh(_no, brasas, _material_luz(Color(1.0, 0.32, 0.05), 5.0), false)
	if chamas.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 1.0)
	q.center_offset = Vector3(0.0, 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/chama_tocha.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 3, 71))
	q.material = mat
	mm.mesh = q
	mm.instance_count = chamas.size()
	for k in chamas.size():
		mm.set_instance_transform(k, chamas[k])
		mm.set_instance_custom_data(k, Color(fases[k], 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3.ONE * -1.0e5, Vector3.ONE * 2.0e5)
	_no.add_child(mmi)
	for p in luzes:
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.52, 0.18)
		luz.light_energy = 2.4
		luz.omni_range = 19.0
		luz.omni_attenuation = 1.3
		luz.shadow_enabled = false
		luz.distance_fade_enabled = true
		luz.distance_fade_begin = 240.0
		luz.distance_fade_length = 60.0
		luz.position = p
		_no.add_child(luz)


## Extinction Day (etapas à noite): tubo de neon contínuo nas duas bordas da estrada (na cor da etapa e
## na cor de contraste alternando por trecho) e arcos de neon por cima da pista a cada ~140 m.
func _faixas_neon() -> void:
	var cores: Array = cfg_sub("neon_cores", [[1.0, 0.1, 0.75], [0.1, 0.85, 1.0]])
	var mats := []
	for c in cores:
		mats.append(_material_luz(Color(float(c[0]), float(c[1]), float(c[2])), 6.0))
	var faixas := [[], []]
	var arcos := [[], []]
	var i := 1
	var ultimo_arco := -1000.0
	while i < _pts.size():
		var j := mini(i + 3, _pts.size() - 1)
		if j <= i:
			break
		if _trecho[j] != _trecho[i] or _vao[i] != 0 or _vao[j] != 0:
			i = j + 1
			continue
		var cor := int(_s[i] / 120.0) % 2
		var meio := (_pts[i] + _pts[j]) * 0.5
		var t := (_pts[j] - _pts[i])
		var comp := t.length()
		var n := _lat[i].cross(_tan[i]).normalized()
		var b := Basis.looking_at(t / maxf(comp, 0.01), n)
		for lado: float in [-1.0, 1.0]:
			faixas[cor].append(Transform3D(b * Basis.from_scale(Vector3(0.14, 0.14, comp + 0.05)), meio + _lat[i] * lado * (_larg[i] * 0.5 + 0.05) + n * 0.12))
		if _s[i] - ultimo_arco > 140.0 and _curv[i] < 1.0 / 120.0:
			ultimo_arco = _s[i]
			var meia := _larg[i] * 0.5 + 0.6
			const GOMOS := 10
			for k in GOMOS:
				var a0 := PI * k / GOMOS
				var a1 := PI * (k + 1) / GOMOS
				var p0 := _pts[i] + _lat[i] * meia * cos(a0) + n * (7.5 * sin(a0) + 0.2)
				var p1 := _pts[i] + _lat[i] * meia * cos(a1) + n * (7.5 * sin(a1) + 0.2)
				arcos[1 - cor].append(_viga(p0, p1, 0.22))
		i = j
	for k in mats.size():
		var f_l: Array[Transform3D] = []
		f_l.assign(faixas[k])
		var a_l: Array[Transform3D] = []
		a_l.assign(arcos[k])
		criar_multimesh(_no, f_l, mats[k], false)
		criar_multimesh(_no, a_l, mats[k], false)


## Pontos de aceleração na estrada: [trecho, metros desde o começo do trecho] (mapa.subida.impulsos).
## Um deles fica logo antes da rampa de salto (sem ele muita gente não passa o vão).
func _montar_impulsos_estrada() -> void:
	for im in cfg_sub("impulsos", []):
		_impulso_trecho(im, _no)   # no percurso: some junto quando a etapa troca de traçado
	for r in cfg_sub("impulsos_re", []):
		_impulso_re(r)
	for e in cfg_sub("ejetores", []):
		_montar_ejetor(e)


## Acelerador contrário (percursos.N.impulsos_re: [trecho, m, lateral, meia largura, velocidade]): placa
## vermelha que joga o carro para TRÁS. Ocupa só parte da largura — passa quem desvia pelo lado livre.
func _impulso_re(r: Array) -> void:
	var i := indice_trecho(str(r[0]), float(r[1]))
	if i < 0:
		return
	var t := _tan[i]
	var l := _lat[i]
	var nrm := l.cross(t).normalized()
	var meia := float(r[3])
	var centro := _pts[i] + l * float(r[2])
	_impulsos_estrada.append([centro, -t, l, nrm, float(r[4]), meia])
	_res.append({"i": i, "s": _s[i], "lat": float(r[2]), "meia": meia})
	var placa := PlaneMesh.new()
	placa.size = Vector2(meia * 2.0, Recinto.IMPULSO_MEIO.x * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = placa
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/impulso.gdshader")
	mat.set_shader_parameter("cor", Color(1.0, 0.08, 0.05))
	mat.set_shader_parameter("tamanho", placa.size)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis.looking_at(-t, nrm), centro + nrm * 0.04)
	_no.add_child(mi)


## Para os bots: acelerador contrário até `alcance` m à frente. {falta, livre: lateral do meio do lado livre,
## borda: lateral onde a placa acaba (vale o centro do carro: passando dela, a placa não pega)}.
func re_adiante(i: int, alcance: float) -> Dictionary:
	for r: Dictionary in _res:
		if _trecho[r.i] != _trecho[i]:
			continue
		var falta: float = float(r.s) - _s[i]
		if falta > -(Recinto.IMPULSO_MEIO.x + 1.0) and falta < alcance:
			var meia_e := _larg[r.i] * 0.5
			var borda: float = float(r.lat) - float(r.meia) if float(r.lat) > 0.0 else float(r.lat) + float(r.meia)
			var livre: float = (-meia_e + float(r.lat) - float(r.meia)) * 0.5 if float(r.lat) > 0.0 else (meia_e + float(r.lat) + float(r.meia)) * 0.5
			return {"falta": falta, "livre": livre, "borda": borda}
	return {}


## Mola ejetora (percursos.N.ejetores: [trecho, m do meio, altura, comprimento (padrão 5 m), frente (fração da
## velocidade que o carro guarda, padrão 0,6; > 1 joga para a frente), descontrolado (gira também os bots)]): prato de aço
## na largura toda da pista, rente ao asfalto e acompanhando a curva e a rampa dela, em cima de molas.
## Quem passa por cima é lançado a ~`altura` m, girando sem controle (Veiculo.girando); no ar dá para
## abrir o paraquedas e tentar seguir. Pedido do dono, no lugar da catapulta; a gigante da E1 vai até
## depois de o desvio se separar da pista (a de 5 m dava para contornar pelo desvio e voltar).
func _montar_ejetor(e: Array) -> void:
	var i := indice_trecho(str(e[0]), float(e[1]))
	if i < 0:
		return
	var comp := float(e[3]) if e.size() > 3 else 5.0
	var tr := _trecho[i]
	var ia := i
	while ia > _inicio_trecho[tr] and _s[i] - _s[ia - 1] <= comp * 0.5:
		ia -= 1
	var ib := i
	while ib < _fim_trecho[tr] and _s[ib + 1] - _s[i] <= comp * 0.5:
		ib += 1
	if ib - ia < 2:
		ia = maxi(i - 1, _inicio_trecho[tr])
		ib = mini(i + 1, _fim_trecho[tr])
	comp = _s[ib] - _s[ia]
	var no := Node3D.new()
	_no.add_child(no)
	# O prato que sobe com a mola: uma faixa que segue a pista de borda a borda
	var prato := Node3D.new()
	no.add_child(prato)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faixa := []
	var larg_media := 0.0
	for j in range(ia, ib + 1):
		var nrm := _lat[j].cross(_tan[j]).normalized()
		var meia := _larg[j] * 0.5
		larg_media += _larg[j] / (ib - ia + 1)
		faixa.append([_pts[j], _tan[j], _lat[j], meia])
		for lado: float in [-1.0, 1.0]:
			st.set_normal(nrm)
			st.set_uv(Vector2(lado * 0.5 + 0.5, (_s[j] - _s[ia]) / maxf(comp, 0.01)))
			st.add_vertex(_pts[j] + _lat[j] * lado * (meia - 0.15) + nrm * 0.05)
	for j in ib - ia:
		var v0 := j * 2
		st.add_index(v0); st.add_index(v0 + 2); st.add_index(v0 + 1)
		st.add_index(v0 + 1); st.add_index(v0 + 2); st.add_index(v0 + 3)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/impulso.gdshader")
	mat.set_shader_parameter("cor", Color(1.0, 0.8, 0.05))
	mat.set_shader_parameter("tamanho", Vector2(larg_media - 0.3, comp))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prato.add_child(mi)
	# Moldura fixa no piso (barras acesas) no começo e no fim
	var moldura: Array[Transform3D] = []
	for par: Array in [[ia, -1.0], [ib, 1.0]]:
		var j: int = par[0]
		var nrm_m := _lat[j].cross(_tan[j]).normalized()
		moldura.append(Transform3D(Basis(_lat[j], nrm_m, _lat[j].cross(nrm_m)) * Basis.from_scale(Vector3(_larg[j], 0.06, 0.5)), _pts[j] + _tan[j] * float(par[1]) * 0.25 + nrm_m * 0.03))
	criar_multimesh(no, moldura, _material_luz(Color(1.0, 0.75, 0.05), 2.5), false)
	# Molas (espiras de aço embaixo do prato: só aparecem quando ele sobe), um par a cada 8 m
	var espira := TorusMesh.new()
	espira.inner_radius = 0.75
	espira.outer_radius = 1.0
	espira.rings = 14
	espira.ring_segments = 6
	var molas := Node3D.new()
	no.add_child(molas)
	var mat_mola := material_aco(0.0, 0.2)
	var prox := _s[ia] + minf(comp * 0.5, 4.0)
	for j in range(ia, ib + 1):
		if _s[j] < prox:
			continue
		prox = _s[j] + 8.0
		for x: float in [-0.25, 0.25]:
			for k in 5:
				var anel := MeshInstance3D.new()
				anel.mesh = espira
				anel.material_override = mat_mola
				anel.position = _pts[j] + _lat[j] * _larg[j] * x
				anel.set_meta("k", k)
				anel.set_meta("base", anel.position)
				molas.add_child(anel)
	molas.visible = false
	_ejetores.append({"i": i, "s": _s[i], "pos": _pts[i], "vy": sqrt(2.0 * 9.8 * float(e[2])), "comp": comp, "faixa": faixa,
		"frente": float(e[4]) if e.size() > 4 else 0.6, "louco": bool(e[5]) if e.size() > 5 else false,
		"meio_passo": comp / (ib - ia) * 0.5 + 0.4, "prato": prato, "molas": molas, "t": -100.0})


## Mola do último ejetor_em que acertou: quanto da velocidade o carro guarda e se gira os bots também.
var ejetor_frente := 0.6
var ejetor_louco := false

## Velocidade para cima que a mola dá a quem está em cima dela (0 fora). Dispara a animação do prato.
func ejetor_em(p: Vector3) -> float:
	ejetor_frente = 0.6
	ejetor_louco = false
	for e: Dictionary in _ejetores:
		if p.distance_squared_to(e.pos) > pow(float(e.comp) * 0.5 + 20.0, 2.0):
			continue
		for f: Array in e.faixa:
			var q: Vector3 = p - (f[0] as Vector3)
			if absf(q.y) < 2.5 and absf(q.dot(f[1])) < float(e.meio_passo) and absf(q.dot(f[2])) < float(f[3]) + 0.3:
				e.t = _relogio_desvios
				ejetor_frente = float(e.frente)
				ejetor_louco = bool(e.louco)
				return float(e.vy)
	if plataforma:
		return plataforma.mola_em(p, _relogio_desvios)
	return 0.0


## Para os bots: mola até `alcance` m à frente (ou embaixo do carro). {falta: metros até o começo do prato}.
func ejetor_adiante(i: int, alcance: float) -> Dictionary:
	for e: Dictionary in _ejetores:
		if _trecho[e.i] != _trecho[i]:
			continue
		var falta: float = float(e.s) - float(e.comp) * 0.5 - _s[i]
		if falta > -float(e.comp) - 1.5 and falta < alcance:
			return {"falta": falta}
	return {}


func _atualizar_ejetores() -> void:
	if plataforma:
		plataforma.animar_molas(_relogio_desvios)
	for e: Dictionary in _ejetores:
		var dt: float = _relogio_desvios - float(e.t)
		# O prato estala para cima (0,08 s) e desce devagar
		var alt := 3.2 * clampf(dt / 0.08, 0.0, 1.0) * exp(-maxf(dt - 0.08, 0.0) * 1.8) if dt < 4.0 else 0.0
		(e.prato as Node3D).position.y = alt
		var molas: Node3D = e.molas
		molas.visible = alt > 0.15
		if molas.visible:
			for anel in molas.get_children():
				(anel as Node3D).position = (anel.get_meta("base") as Vector3) + Vector3.UP * (alt * (float(anel.get_meta("k")) + 0.5) / 5.0 - 0.1)


## Um ponto de aceleração [trecho, metros (negativo = antes do fim), tranco opcional, "fixo"] com a placa em `pai`.
func _impulso_trecho(im: Array, pai: Node) -> void:
	var k := _nomes_trecho.find(str(im[0]))
	if k < 0:
		return
	var m := float(im[1])
	var i0 := _inicio_trecho[k]
	var i1 := _fim_trecho[k]
	var i := i0
	if m < 0.0:   # negativo = metros antes do fim do trecho
		while i < i1 and _s[i1] - _s[i] > -m:
			i += 1
	else:
		while i < i1 and _s[i] - _s[i0] < m:
			i += 1
	# Nunca antes de curva: o tranco jogaria o carro para fora (4º item "fixo": fica onde foi pedido)
	var fixo := im.size() > 3 and str(im[3]) == "fixo"
	while not fixo and i < i1 - 10 and curvatura_adiante(i, 150.0) > 1.0 / 350.0 and _s[i1] - _s[i] > 160.0:
		i += 1
	# Nunca em cima de vão ou gelo fino (a placa ficaria no ar): recua até ter piso sob ela toda
	while i > i0 + 4 and (_vao[i] != 0 or _vao[i - 4] != 0 or _vao[mini(i + 4, i1)] != 0):
		i -= 1
	var t := _tan[i]
	var l := _lat[i]
	var nrm := l.cross(t).normalized()
	_impulsos_estrada.append([_pts[i], t, l, nrm, float(im[2]) if im.size() > 2 else impulso_velocidade])
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SUB] impulso %s em %s" % [str(im), str(_pts[i].snapped(Vector3.ONE))])
	var placa := PlaneMesh.new()
	placa.size = Vector2(Recinto.IMPULSO_MEIO.y * 2.0, Recinto.IMPULSO_MEIO.x * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = placa
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/impulso.gdshader")
	mat.set_shader_parameter("cor", Color(0.1, 0.85, 1.0))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis.looking_at(t, nrm), _pts[i] + nrm * 0.04)
	pai.add_child(mi)


## Pontos de checagem a cada fração do percurso até a rampa final. Se a fração cai na plataforma
## ou no vão do salto, o ponto vai para a primeira amostra de estrada depois dele.
func _montar_checkpoints() -> void:
	var cfg: Dictionary = cfg_sub("checkpoints", {})
	if cfg.is_empty():
		return
	fantasma_s = float(cfg.get("fantasma_s", 3.0))
	_raio_cp = float(cfg.get("raio", 6.5))
	_altura_cp = float(cfg.get("altura", 6.0))
	# Serpent's Climb: pontos fixos [trecho, metros] (logo depois de cada armadilha) em vez de frações
	var lista: Array = cfg.get("pontos", cfg.get("fracoes", []))
	for f in lista:
		var i := 0
		if f is Array:
			i = indice_trecho(str(f[0]), float(f[1]))
		else:
			var alvo_s := float(f) * s_final
			while i < _pts.size() - 1 and _s[i] < alvo_s:
				i += 1
		# Longe da ponta dos trechos (rampa de salto, zona de pouso): quem ressurge precisa de estrada à frente
		i = clampi(i, _inicio_trecho[_trecho[i]] + 15, _fim_trecho[_trecho[i]] - 40)
		var cil := CylinderMesh.new()
		cil.top_radius = _raio_cp
		cil.bottom_radius = _raio_cp
		cil.height = _altura_cp
		cil.radial_segments = 48
		cil.rings = 1
		cil.cap_top = false
		cil.cap_bottom = false
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/checkpoint.gdshader")
		mat.set_shader_parameter("altura", _altura_cp)
		var mi := MeshInstance3D.new()
		mi.mesh = cil
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = _pts[i] + Vector3.UP * (_altura_cp * 0.5 - 0.05)
		_no.add_child(mi)
		# Sem legenda no cilindro (pedido do dono): o número só aparece no aviso da tela ao pegar
		checkpoints.append({"i": i, "s": _s[i], "pos": _pts[i], "tan": _tan[i], "lat": _lat[i], "mat": mat, "no": mi})
		if OS.get_environment("TSC_SUB_LOG") != "":
			print("[SUB] checkpoint %d em %s (trecho %d)" % [checkpoints.size(), str(_pts[i].snapped(Vector3.ONE)), _trecho[i]])


## Troca o que muda por etapa (depois do Terreno.preparar_etapa): o túnel-atalho e o paredão fino.
func preparar_etapa(_indice: int) -> void:
	if tem_percursos() and _indice != _percurso_montado:
		etapa_percurso = _indice
		_construir()
	mostrar_checkpoints()
	_montar_estrada_extra(_terreno.estrada_extra_da_etapa())
	if _paredao:
		_paredao.queue_free()
		_paredao = null
	var cfg_paredao := _terreno.paredao_da_etapa()
	if not cfg_paredao.is_empty():
		_paredao = ParedaoFino.new()
		add_child(_paredao)
		_paredao.montar(cfg_paredao, _terreno)
	if _tunel:
		_tunel.queue_free()
		_tunel = null
	if _tuneis_pista:
		_tuneis_pista.queue_free()
		_tuneis_pista = null
	if not _terreno.tuneis_pista().is_empty():   # morro em cima da pista da etapa: túnel (TunelPista)
		_tuneis_pista = TunelPista.new()
		add_child(_tuneis_pista)
		_tuneis_pista.montar(_terreno, self)
	var cfg := _terreno.tunel_da_etapa()
	if cfg.is_empty():
		return
	_tunel = TunelAtalho.new()
	add_child(_tunel)
	_tunel.montar(cfg, _terreno, self)


## Trecho de estrada extra da etapa (montanhas.etapas.N.estrada_extra, pedido do dono): depois da
## rampa final, encostado nas montanhas, para pousar de paraquedas, pegar impulso e sair por outra
## rampa no fim. Estrutura própria (fora do percurso, dos checkpoints e da rota dos bots), refeita
## a cada etapa: asfalto com colisão, laterais, pilares até o chão, luzes nas bordas e impulsos.
## cfg: pontos [[x, altura, z], ...] (a curva passa por eles; o fim sobe como rampa), impulsos
## [metros desde o começo, ...] e velocidade do tranco (m/s).
var _extra: Node3D
var _n_impulsos_base := -1

func _montar_estrada_extra(cfg: Dictionary) -> void:
	if _n_impulsos_base < 0:
		_n_impulsos_base = _impulsos_estrada.size()
	_impulsos_estrada.resize(_n_impulsos_base)   # tira os impulsos da estrada extra anterior
	if _extra:
		_extra.queue_free()
		_extra = null
	if cfg.is_empty():
		return
	_extra = Node3D.new()
	_extra.name = "EstradaExtra"
	add_child(_extra)
	# Impulsos a mais na estrada principal só nesta etapa (ex.: antes da rampa final)
	for im in cfg.get("impulsos_estrada", []):
		_impulso_trecho(im, _extra)
	var ctrl := PackedVector3Array()
	for p in cfg.get("pontos", []):
		ctrl.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	if ctrl.size() < 2:
		return
	var pts := _amostrar_curva(ctrl)
	var n := pts.size()
	var tan := PackedVector3Array()
	var lat := PackedVector3Array()
	var s := PackedFloat32Array()
	tan.resize(n)
	lat.resize(n)
	s.resize(n)
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		tan[i] = t
		lat[i] = t.cross(Vector3.UP).normalized()
		if i > 0:
			s[i] = s[i - 1] + pts[i].distance_to(pts[i - 1])
	var meia := largura_estrada * 0.5
	# Asfalto, laterais e colisão (como _malha_estrada)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var laterais := SurfaceTool.new()
	laterais.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
	for i in range(1, n):
		var n0 := lat[i - 1].cross(tan[i - 1]).normalized()
		var n1 := lat[i].cross(tan[i]).normalized()
		var e0 := pts[i - 1] - lat[i - 1] * meia
		var d0 := pts[i - 1] + lat[i - 1] * meia
		var e1 := pts[i] - lat[i] * meia
		var d1 := pts[i] + lat[i] * meia
		_quad(st, e0, d0, d1, e1, n0, n1, Vector2(0, s[i - 1]), Vector2(1, s[i]))
		faces.append_array([e0, d0, d1, e0, d1, e1])
		var v0 := s[i - 1]
		var v1 := s[i]
		var esp0 := n0 * ESPESSURA_ESTRADA
		var esp1 := n1 * ESPESSURA_ESTRADA
		_quad_uv(laterais, [e0, e1, e1 - esp1, e0 - esp0], -lat[i - 1], [Vector2(v0, 0), Vector2(v1, 0), Vector2(v1, 1), Vector2(v0, 1)])
		_quad_uv(laterais, [d0, d0 - esp0, d1 - esp1, d1], lat[i - 1], [Vector2(v0, 0), Vector2(v0, 1), Vector2(v1, 1), Vector2(v1, 0)])
		_quad_uv(laterais, [e0 - esp0, e1 - esp1, d1 - esp1, d0 - esp0], -n0, [Vector2(v0, 0.5), Vector2(v1, 0.5), Vector2(v1, 0.5), Vector2(v0, 0.5)])
	var mat := ShaderMaterial.new()
	mat.shader = load(_shader_pista())
	mat.set_shader_parameter("cor_equipe", cor)
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 3))
	mat.set_shader_parameter("largura", largura_estrada)
	mat.set_shader_parameter("comp_plataforma", -1.0)
	mat.set_shader_parameter("linha_largada", -100.0)
	mat.set_shader_parameter("inicio_rampa", 1.0e9)
	_ajustar_pista(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_extra.add_child(mi)
	var mat_l := ShaderMaterial.new()
	mat_l.shader = load(_shader_lateral())
	mat_l.set_shader_parameter("cor_equipe", cor)
	var ml := MeshInstance3D.new()
	ml.mesh = laterais.commit()
	ml.material_override = mat_l
	_extra.add_child(ml)
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
	_extra.add_child(corpo)
	# Pilares até o chão a cada ~22 m (como _pilares)
	var colunas: Array[Transform3D] = []
	var vigas: Array[Transform3D] = []
	for i in range(6, n - 4, 22):
		var p := pts[i]
		var chao := _terreno.altura_em(p.x, p.z)
		var topo := p.y - ESPESSURA_ESTRADA - 0.6
		if topo - chao > 1.0:
			var b := Basis.looking_at(Vector3(tan[i].x, 0.0, tan[i].z).normalized(), Vector3.UP)
			var lado := 2.6 if topo - chao < 60.0 else 3.6
			colunas.append(Transform3D(b * Basis.from_scale(Vector3(lado, topo - chao + 2.0, lado)), Vector3(p.x, (topo + chao - 2.0) * 0.5, p.z)))
			vigas.append(Transform3D(b * Basis.from_scale(Vector3(largura_estrada - 1.0, 1.0, 2.2)), Vector3(p.x, topo + 0.3, p.z)))
	criar_multimesh(_extra, colunas, _material_pilar())
	criar_multimesh(_extra, vigas, _material_viga())
	adicionar_colisoes(corpo, colunas)
	# Luzes âmbar nas bordas (mesmo efeito "correndo" da estrada)
	var luzes: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	for i in range(2, n, 4):
		var nrm := lat[i].cross(tan[i]).normalized()
		for lado: float in [-1.0, 1.0]:
			luzes.append(Transform3D(Basis.looking_at(tan[i], nrm) * Basis.from_scale(Vector3(0.3, 0.3, 0.7)), pts[i] + lat[i] * (meia + 0.12) * lado - nrm * 0.3))
			fases.append(i * 0.15)
	var mat_luz := ShaderMaterial.new()
	mat_luz.shader = load("res://shaders/luz_sequencial.gdshader")
	mat_luz.set_shader_parameter("energia", 7.0)
	criar_multimesh(_extra, luzes, mat_luz, false, fases)
	# Impulsos (placas de aceleração)
	var vel := float(cfg.get("velocidade_impulso", impulso_velocidade))
	for m in cfg.get("impulsos", []):
		var i := 0
		while i < n - 1 and s[i] < float(m):
			i += 1
		var nrm := lat[i].cross(tan[i]).normalized()
		_impulsos_estrada.append([pts[i], tan[i], lat[i], nrm, vel])
		var placa := PlaneMesh.new()
		placa.size = Vector2(Recinto.IMPULSO_MEIO.y * 2.0, Recinto.IMPULSO_MEIO.x * 2.0)
		var mp := MeshInstance3D.new()
		mp.mesh = placa
		var mat_p := ShaderMaterial.new()
		mat_p.shader = load("res://shaders/impulso.gdshader")
		mat_p.set_shader_parameter("cor", Color(0.1, 0.85, 1.0))
		mp.material_override = mat_p
		mp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mp.transform = Transform3D(Basis.looking_at(tan[i], nrm), pts[i] + nrm * 0.04)
		_extra.add_child(mp)



# ------------------------------------------------------------------ bifurcações (desvios)

## Amostras dos desvios (mapa.subida.percursos.N.desvios: [{nome, tipo, de: [trecho, m], para: [trecho, m],
## pontos: [[x, y, z]...], largura, peso_bots, ...}]): cada um vira um trecho a mais depois do C.
func _amostrar_desvios() -> void:
	for d in cfg_sub("desvios", []):
		var ctrl := PackedVector3Array()
		for p in d.get("pontos", []):
			ctrl.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		if ctrl.size() < 2:
			continue
		var am := _amostrar_curva(ctrl)
		var de: Array = d.get("de", ["C", 0])
		var para: Array = d.get("para", ["C", 0])
		var i_de := indice_trecho(str(de[0]), float(de[1]))
		var i_para := indice_trecho(str(para[0]), float(para[1]))
		var cum := PackedFloat32Array()
		cum.resize(am.size())
		for i in range(1, am.size()):
			cum[i] = cum[i - 1] + am[i].distance_to(am[i - 1])
		var total := maxf(cum[am.size() - 1], 1.0)
		var k := _nomes_trecho.size()
		var nome := str(d.get("nome", "D%d" % k))
		_nomes_trecho.append(nome)
		var ini := _pts.size()
		_inicio_trecho.append(ini)
		for i in am.size():
			_pts.append(am[i])
			_s.append(lerpf(_s[i_de], _s[i_para], cum[i] / total))
			_trecho.append(k)
		_fim_trecho.append(_pts.size() - 1)
		desvios.append({"k": k, "nome": nome, "tipo": str(d.get("tipo", "estrada")), "cfg": d, "ini": ini, "fim": _pts.size() - 1,
			"i_de": i_de, "i_para": i_para, "s_de": _s[i_de], "s_para": _s[i_para], "comp": total, "metros": cum,
			"largura": float(d.get("largura", largura_estrada)), "peso": float(d.get("peso_bots", 1.0))})


## Amostra do desvio mais perto do ponto [x, y, z] da config.
func _amostra_cfg(d: Dictionary, q: Array) -> int:
	return amostra_no_trecho(Vector3(float(q[0]), float(q[1]), float(q[2])), int(d.k))


## Metros desde o começo do desvio até a amostra i.
func _metros_desvio(d: Dictionary, i: int) -> float:
	return (d.metros as PackedFloat32Array)[clampi(i - int(d.ini), 0, int(d.fim) - int(d.ini))]


func _ilha_em(ilhas: Array, p: Vector3, folga := 0.4) -> int:
	for k in ilhas.size():
		var q: Vector4 = ilhas[k]
		if Vector2(p.x - q.x, p.z - q.z).length() < q.w - folga:
			return k
	return -1


## Plataformas redondas no lugar da estrada principal (percursos.N.ilhas_pista: [[trecho, m0, m1], ...];
## pedido e desenho do dono): entre m0 e m1 a laje some e ficam só colunas redondas, SEM rampa, em
## zigue-zague — uma para a esquerda, a seguinte para a direita — e desniveladas, umas mais baixas, outras
## mais altas. Pula-se de uma em uma (para as mais altas, com o ejetor) até a estrada voltar.
func _marcar_ilhas_pista() -> void:
	_ilhas_pista.clear()
	const LADO := 4.4
	const DESNIVEL: Array[float] = [-0.8, -1.5, -0.7, -1.7, -1.1, -0.4, -1.3, -1.8, -0.9, -0.3, -1.2, -0.6]
	for it in cfg_sub("ilhas_pista", []):
		var k := _nomes_trecho.find(str(it[0]))
		if k < 0:
			continue
		# 4º e 5º itens: raio e passo das plataformas (o dono pediu menos e maiores)
		var RAIO := float(it[3]) if it.size() > 3 else 6.0
		var PASSO_ILHA := float(it[4]) if it.size() > 4 else 13.0
		var s0 := _s[_inicio_trecho[k]]
		var ia := _inicio_trecho[k]
		while ia < _fim_trecho[k] and _s[ia] - s0 < float(it[1]):
			ia += 1
		var ib := ia
		while ib < _fim_trecho[k] and _s[ib] - s0 < float(it[2]):
			ib += 1
		var util := _s[ib] - _s[ia] - (RAIO + 3.0) * 2.0
		var n := maxi(int(util / PASSO_ILHA) + 1, 2)
		var ilhas: Array = []
		var j := ia
		for q in n:
			var alvo_s := _s[ia] + RAIO + 3.0 + util * q / (n - 1)
			while j < ib and _s[j] < alvo_s:
				j += 1
			var p := _pts[j] + _lat[j] * LADO * (1.0 if q % 2 == 0 else -1.0)
			ilhas.append(Vector4(p.x, _pts[j].y + DESNIVEL[q % DESNIVEL.size()], p.z, RAIO))
		for i in range(ia, ib):
			_vao[i] = 3 if _ilha_em(ilhas, _pts[i]) >= 0 else 1
		var i := ia - 1
		while i < ib:
			if _vao[i] != 1 and _vao[i + 1] == 1:
				var f := i + 1
				while f < ib and _vao[f] == 1:
					f += 1
				# Para os bots: quanto a próxima plataforma (ou a estrada) fica acima desta; subindo, só com o ejetor
				var q0 := _ilha_em(ilhas, _pts[i], 0.0)
				var q1 := _ilha_em(ilhas, _pts[mini(f + 1, ib)], 0.0)
				var sobe: float = ((ilhas[q1] as Vector4).y if q1 >= 0 else _pts[f].y) - ((ilhas[q0] as Vector4).y if q0 >= 0 else _pts[i].y)
				# Velocidade de decolagem: o voo do ejetor (12 m/s para cima) tem de cobrir o vão e pousar ~4,5 m adentro
				var t_voo := (12.0 + sqrt(maxf(144.0 - 19.6 * sobe, 0.0))) / 9.8
				var v_pulo := (_s[f] - _s[i] + 3.4) / t_voo   # pousa logo depois da beirada: o carro quica e precisa do resto da plataforma para parar
				_vaos.append({"i0": i, "i1": f, "s0": _s[i], "s1": _s[f], "trecho": k, "vel": v_pulo if sobe > -0.5 else 11.0, "ejetor": sobe > -0.5, "sobe": sobe})
				i = f
			else:
				i += 1
		# Rampinha de cada ilha: sobe o que falta para a próxima (ou para a estrada, na última)
		var rampas: Array = []
		for q in n:
			var prox: float = (ilhas[q + 1] as Vector4).y if q < n - 1 else _pts[ib].y
			rampas.append(0.0 * prox)   # sem rampa (o dono pediu só as plataformas)
		_ilhas_pista.append({"ilhas": ilhas, "rampas": rampas, "ini": ia, "fim": ib, "k": k, "cfg": {}})


## Ilhas: amostras em cima de uma ilha = 3 (sem laje, o piso é a coluna), entre elas = vão (1), e um
## vão na lista para cada travessia (os bots chegam na velocidade "vel"). Catapulta: o voo
## [m0, m1] do gêiser até o deque alto não tem piso.
func _marcar_desvios() -> void:
	_marcar_ilhas_pista()
	# Catapultas na própria estrada (percursos.N.catapultas [[trecho, m, vão, fase]]): depois do cesto
	# não há pista por `vão` metros; o pouso do outro lado é mais largo
	_cat_estrada.clear()
	for item in cfg_sub("catapultas", []):
		var k := _nomes_trecho.find(str(item[0]))
		if k < 0:
			continue
		var i0 := indice_trecho(str(item[0]), float(item[1]))
		var vao := float(item[2])
		var i := i0
		while i < _fim_trecho[k] and _s[i] - _s[i0] < CESTO_MEIO + 1.0:
			i += 1
		var i_vao := i
		while i < _fim_trecho[k] and _s[i] - _s[i0] < CESTO_MEIO + 1.0 + vao:
			_vao[i] = 1
			i += 1
		var i_pouso := i
		while i < _fim_trecho[k] and _s[i] - _s[i_pouso] < 70.0:
			_larg[i] = maxf(_larg[i], lerpf(15.0, largura_estrada, clampf((_s[i] - _s[i_pouso] - 40.0) / 30.0, 0.0, 1.0)))
			i += 1
		_cat_estrada.append({"k": k, "i": i0, "i_vao": i_vao, "i_pouso": i_pouso, "fase": float(item[3]) if item.size() > 3 else 0.0})
	for d in desvios:
		var cfg: Dictionary = d.cfg
		if d.tipo == "ilhas":
			var ilhas: Array = []
			for q in cfg.get("ilhas", []):
				ilhas.append(Vector4(float(q[0]), float(q[1]), float(q[2]), float(q[3])))
			d["ilhas"] = ilhas
			var primeira := -1
			var ultima := -1
			for i in range(d.ini, d.fim + 1):
				if _ilha_em(ilhas, _pts[i]) >= 0:
					_vao[i] = 3
					if primeira < 0:
						primeira = i
					ultima = i
			if primeira < 0:
				continue
			for i in range(primeira, ultima):
				if _vao[i] == 0:
					_vao[i] = 1
			var i := primeira
			while i < ultima:
				if _vao[i] == 3 and _vao[i + 1] == 1:
					var j := i + 1
					while j < ultima and _vao[j] == 1:
						j += 1
					_vaos.append({"i0": i, "i1": j, "s0": _s[i], "s1": _s[j], "trecho": d.k, "vel": float(cfg.get("vel", 17.0))})
					i = j
				else:
					i += 1
		elif d.tipo == "catapulta":
			var c: Dictionary = cfg.get("catapulta", {})
			var i_boca := _amostra_cfg(d, c.get("pos", [0, 0, 0]))
			var i_deck := _amostra_cfg(d, c.get("deck", [0, 0, 0]))
			var raio := float(c.get("raio", 5.0))
			for i in range(i_boca, i_deck):
				if _pts[i].distance_to(_pts[i_boca]) > raio + 1.5:
					_vao[i] = 1
	_vaos.sort_custom(func(a, b): return a.s0 < b.s0)


func _sem_piso(i: int) -> bool:
	var v := _vao[clampi(i, 0, _vao.size() - 1)]
	return v == 1 or v == 3 or v == 4   # 4 = embaixo de um looping


## Outro trecho encostado (bifurcação: a estrada e o desvio correm lado a lado na saída e na volta).
## lado 0: qualquer amostra de outro trecho a menos de 14 m; ±1: só do lado da borda indicada.
func _junto_de_outro(i: int, lado := 0.0) -> bool:
	var p := _pts[i]
	if lado != 0.0:
		p += _lat[i] * lado * (_larg[i] * 0.5 + 1.5)
	var c := Vector2i(floori(p.x / CELULA_GRADE), floori(p.z / CELULA_GRADE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for j in _grade.get(c + Vector2i(dx, dz), PackedInt32Array()):
				if _trecho[j] == _trecho[i] or absf(_pts[j].y - p.y) > 5.0:
					continue
				var dh := Vector2(_pts[j].x - p.x, _pts[j].z - p.z).length()
				if dh < (14.0 if lado == 0.0 else _larg[j] * 0.5 + 2.0):
					return true
	return false


## Estruturas dos desvios: colunas de basalto das ilhas com a rampinha de saída, o anel de luz
## na borda e uma luz; o gêiser da catapulta; e o pórtico com o nome de cada rota na bifurcação.
func _montar_desvios() -> void:
	for ce: Dictionary in _cat_estrada:
		_montar_catapulta_madeira(ce, cfg_sub("catapulta", {}))
	for ip: Dictionary in _ilhas_pista:
		_montar_ilhas(ip)
	for d in desvios:
		var cfg: Dictionary = d.cfg
		if d.tipo == "ilhas":
			_montar_ilhas(d)
		elif d.tipo == "catapulta":
			_montar_catapulta(d, cfg.get("catapulta", {}))
		var placa := str(cfg.get("placa", ""))
		if placa != "":
			var i := mini(int(d.ini) + int(cfg.get("placa_m", 45)), int(d.fim))
			var t := _tan[i]
			var nrm := _lat[i].cross(t).normalized()
			var base := _pts[i] + nrm * 0.2
			var meia := _larg[i] * 0.5
			var b := Basis.looking_at(Vector3(t.x, 0.0, t.z).normalized(), Vector3.UP)
			var trave: Array[Transform3D] = []
			for lado: float in [-1.0, 1.0]:
				trave.append(Transform3D(b * Basis.from_scale(Vector3(0.35, 8.4, 0.35)), base + _lat[i] * lado * (meia + 0.4) + Vector3.UP * 3.0))
			trave.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + 1.5, 1.8, 0.3)), base + Vector3.UP * 6.4))
			var madeira := StandardMaterial3D.new()
			madeira.albedo_color = Color(0.22, 0.15, 0.09)
			madeira.roughness = 0.95
			criar_multimesh(_no, trave, madeira)
			adicionar_colisoes(_estruturas, trave)
			var rotulo := Label3D.new()
			rotulo.text = placa
			rotulo.font_size = 150
			rotulo.pixel_size = 0.0085
			rotulo.outline_size = 22
			rotulo.modulate = Color(1.0, 0.72, 0.3)
			rotulo.outline_modulate = Color(0.08, 0.03, 0.0)
			rotulo.double_sided = false
			rotulo.shaded = false
			rotulo.transform = Transform3D(b, base + Vector3.UP * 6.4 + b.z * 0.2)
			_no.add_child(rotulo)
			for lado: float in [-1.0, 1.0]:
				_no.add_child(Dino._chama(base + _lat[i] * lado * (meia + 0.4) + Vector3.UP * 7.3, 0.7))


## Ilhas de basalto: coluna até o chão (colisão de cilindro), rampinha na saída de cada uma (menos a
## última), anel âmbar marcando a borda e uma luz em cima.
func _montar_ilhas(d: Dictionary) -> void:
	var ilhas: Array = d.ilhas
	var mat := _material_pilar()
	# Selva: borda de ouro aceso, faixa de jade logo abaixo do topo e a laje de cima entalhada (Pedra do Sol)
	var anel_mat := _material_luz(Color(1.0, 0.72, 0.25), 2.2) if _selva() else _material_luz(Color(1.0, 0.45, 0.1), 3.5)
	var rampa_mat := ShaderMaterial.new()
	rampa_mat.shader = load(_shader_pista())
	rampa_mat.set_shader_parameter("cor_equipe", cor)
	rampa_mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 3))
	rampa_mat.set_shader_parameter("largura", 8.0)
	rampa_mat.set_shader_parameter("comp_plataforma", -1.0)
	rampa_mat.set_shader_parameter("linha_largada", -100.0)
	rampa_mat.set_shader_parameter("inicio_rampa", -1.0)
	var cfg: Dictionary = d.cfg
	var rampa_alt := float(cfg.get("rampa_altura", 0.9))
	var rampa_comp := float(cfg.get("rampa_comp", 6.0))
	for k in ilhas.size():
		var q: Vector4 = ilhas[k]
		var topo := Vector3(q.x, q.y, q.z)
		var chao := _terreno.altura_em(q.x, q.z) - 3.0
		var alt := topo.y - chao
		var col := CylinderMesh.new()
		col.top_radius = q.w
		col.bottom_radius = q.w * 1.25
		col.height = alt
		col.radial_segments = 24
		col.rings = 4
		var mi := MeshInstance3D.new()
		mi.mesh = col
		mi.material_override = mat
		mi.position = Vector3(q.x, (topo.y + chao) * 0.5, q.z)
		_no.add_child(mi)
		var cs := CollisionShape3D.new()
		var forma := CylinderShape3D.new()
		forma.radius = q.w
		forma.height = 2.0
		cs.shape = forma
		cs.position = topo - Vector3.UP * 1.0
		_estruturas.add_child(cs)
		var corpo_col := CollisionShape3D.new()
		var forma_c := CylinderShape3D.new()
		forma_c.radius = q.w * 0.95
		forma_c.height = maxf(alt - 2.0, 1.0)
		corpo_col.shape = forma_c
		corpo_col.position = Vector3(q.x, (topo.y - 2.0 + chao) * 0.5, q.z)
		_estruturas.add_child(corpo_col)
		var anel := TorusMesh.new()
		anel.inner_radius = q.w - 0.3
		anel.outer_radius = q.w
		anel.rings = 48
		anel.ring_segments = 6
		var ma := MeshInstance3D.new()
		ma.mesh = anel
		ma.material_override = anel_mat
		ma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ma.position = topo + Vector3.UP * 0.02
		ma.scale = Vector3(1.0, 0.25, 1.0)
		_no.add_child(ma)
		if _selva():
			for faixa: Array in [[1.2, Selva.material_jade(), 1.1], [2.6, Selva.material_ouro(), 0.35], [3.4, Selva.material_jade(), 0.5]]:
				var cinta := CylinderMesh.new()
				cinta.top_radius = q.w + 0.18
				cinta.bottom_radius = q.w + 0.22
				cinta.height = float(faixa[2])
				cinta.radial_segments = 32
				var mc := MeshInstance3D.new()
				mc.mesh = cinta
				mc.material_override = faixa[1]
				mc.position = topo - Vector3.UP * float(faixa[0])
				_no.add_child(mc)
			# Tampo entalhado: a mesma pedra do sol do alvo, rente ao piso (só textura, a colisão é a do cilindro)
			var tampo := CylinderMesh.new()
			tampo.top_radius = q.w - 0.3
			tampo.bottom_radius = q.w - 0.3
			tampo.height = 0.06
			tampo.radial_segments = 40
			var mt := MeshInstance3D.new()
			mt.mesh = tampo
			var ms := ShaderMaterial.new()
			ms.shader = load("res://shaders/pedra_sol.gdshader")
			ms.set_shader_parameter("raio", q.w - 0.3)
			ms.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 77))
			mt.material_override = ms
			mt.position = topo + Vector3.UP * 0.01
			mt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_no.add_child(mt)
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.7, 0.35) if _selva() else Color(1.0, 0.55, 0.2)
		luz.light_energy = 2.5
		luz.omni_range = q.w * 2.4
		luz.position = topo + Vector3.UP * 7.0
		_no.add_child(luz)
		if d.has("rampas"):
			rampa_alt = float(d.rampas[k])   # plataformas da pista: 0 = sem rampa
			if rampa_alt <= 0.0:
				continue
		elif k == ilhas.size() - 1 or rampa_alt <= 0.0:
			continue
		# Rampinha: na amostra em que a estrada sai desta ilha, alinhada com a estrada
		var sai := -1
		for i in range(d.ini, d.fim + 1):
			if _ilha_em(ilhas, _pts[i]) == k:
				sai = i
		if sai < 0:
			continue
		var t := Vector3(_tan[sai].x, 0.0, _tan[sai].z).normalized()
		var labio := Vector3(q.x, topo.y, q.z) + t * (q.w - 0.3)
		_cunha(labio, t, 8.0, rampa_comp, rampa_alt, rampa_mat)


## Rampinha em cunha (convexa, com colisão): a ponta alta no lábio, subindo no sentido `t`.
func _cunha(labio: Vector3, t: Vector3, larg: float, comp: float, alt: float, mat: Material) -> void:
	var l := t.cross(Vector3.UP).normalized() * larg * 0.5
	var tras := labio - t * comp
	var v: Array[Vector3] = [tras - l, tras + l, labio + l + Vector3.UP * alt, labio - l + Vector3.UP * alt, labio + l, labio - l]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [[0, 1, 2], [0, 2, 3], [3, 2, 4], [3, 4, 5], [1, 4, 2], [0, 3, 5]]
	var centro := (v[0] + v[1] + v[2] + v[3] + v[4] + v[5]) / 6.0
	for tr: Array in tris:
		var a: Vector3 = v[tr[0]]
		var b: Vector3 = v[tr[1]]
		var c: Vector3 = v[tr[2]]
		var nrm := (b - a).cross(c - a).normalized()
		if nrm.dot((a + b + c) / 3.0 - centro) < 0.0:   # normal sempre para fora
			nrm = -nrm
			var troca := b
			b = c
			c = troca
		for q: Vector3 in [a, c, b]:
			st.set_normal(nrm)
			st.set_uv(Vector2(0.5 + (q - labio).dot(l.normalized()) / larg, (q - tras).dot(t)))
			st.add_vertex(q)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_no.add_child(mi)
	var cs := CollisionShape3D.new()
	var forma := ConvexPolygonShape3D.new()
	forma.points = PackedVector3Array(v)
	cs.shape = forma
	_estruturas.add_child(cs)


## Gêiser da catapulta: boca de rocha com brasa no fundo; de tempos em tempos explode em fogo e quem
## estiver em cima é lançado para o deque alto. Antes de explodir a boca ronca (o brilho cresce).
func _montar_catapulta(d: Dictionary, c: Dictionary) -> void:
	var i := _amostra_cfg(d, c.get("pos", [0, 0, 0]))
	var pos := _pts[i]
	var t := Vector3(_tan[i].x, 0.0, _tan[i].z).normalized()
	var raio := float(c.get("raio", 5.0))
	var no := Node3D.new()
	no.position = pos
	_no.add_child(no)
	var boca := CylinderMesh.new()
	boca.top_radius = raio
	boca.bottom_radius = raio
	boca.height = 0.06
	boca.radial_segments = 32
	var brilho := _material_luz(Color(1.0, 0.35, 0.06), 1.0)
	var mb := MeshInstance3D.new()
	mb.mesh = boca
	mb.material_override = brilho
	mb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mb.position = Vector3.UP * 0.05
	no.add_child(mb)
	var jato := Fogo.criar(no, Vector3.ZERO, raio * 0.6, 30.0, 160, raio * 1.4)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.45, 0.12)
	luz.light_energy = 0.5
	luz.omni_range = 40.0
	luz.position = Vector3.UP * 6.0
	no.add_child(luz)
	_catapultas.append({"pos": pos, "dir": t, "raio": raio, "periodo": float(c.get("periodo", 4.5)), "ativo_s": float(c.get("ativo_s", 0.8)),
		"fase": float(c.get("fase", 0.0)), "vel_h": float(c.get("vel_h", 16.0)), "vel_v": float(c.get("vel_v", 22.0)),
		"brilho": brilho, "jato": jato, "luz": luz, "ativo": false, "trecho": d.k, "i": i})


## Catapulta de madeira na estrada (Extinction Day E2, no lugar da cerca elétrica — pedido do dono): o
## cesto é um estrado no fim da pista, preso por dois braços a cavaletes dos dois lados, com
## contrapesos de pedra. Dispara em ciclos: quem está no cesto na hora é lançado por cima do vão.
## Um batente na frente do cesto segura quem espera (o disparo passa por cima dele).
## Abaixado, o estrado fica rente ao asfalto (sem degrau na entrada). Cavaletes, braços e bordas do
## cesto têm colisão (ninguém atravessa a madeira); a dos braços e bordas some enquanto o braço está no alto.
func _montar_catapulta_madeira(ce: Dictionary, c: Dictionary) -> void:
	var i: int = ce.i
	var pos := _pts[i]
	var t := Vector3(_tan[i].x, 0.0, _tan[i].z).normalized()
	var l := t.cross(Vector3.UP).normalized()
	var meia := _larg[i] * 0.5
	var b := Basis(l, Vector3.UP, -t)   # x = lateral, z = para trás
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.3, 0.2, 0.11)
	madeira.roughness = 0.9
	var madeira_clara := StandardMaterial3D.new()
	madeira_clara.albedo_color = Color(0.45, 0.32, 0.18)
	madeira_clara.roughness = 0.85
	var no := Node3D.new()
	no.transform = Transform3D(b, pos)
	_no.add_child(no)
	# Cavaletes (dois "A" de toras de cada lado, 7 m à frente do cesto) com o eixo de cada braço
	var eixo_z := -7.0
	var eixo_y := 5.0
	var fixas: Array[Transform3D] = []
	for lado: float in [-1.0, 1.0]:
		var x := lado * (meia + 1.6)
		var topo := Vector3(x, eixo_y, eixo_z)
		for dz: float in [-3.2, 3.2]:
			fixas.append(_viga(Vector3(x, -3.0, eixo_z + dz), topo, 0.45))
		fixas.append(_viga(Vector3(x, 1.0, eixo_z - 2.0), Vector3(x, 1.0, eixo_z + 2.0), 0.3))
		fixas.append(_viga(Vector3(x - lado * 0.7, eixo_y, eixo_z), Vector3(x + lado * 0.2, eixo_y, eixo_z), 0.6))
		# viga que prende o cavalete embaixo da laje
		fixas.append(_viga(Vector3(lado * (meia - 1.0), -1.0, eixo_z + 6.5), Vector3(x, -3.0, eixo_z + 3.2), 0.4))
		fixas.append(_viga(Vector3(lado * (meia - 1.0), -1.0, eixo_z + 6.5), Vector3(x, -3.0, eixo_z - 3.2), 0.4))
	criar_multimesh(no, fixas, madeira)
	var fixas_mundo: Array[Transform3D] = []
	for f in fixas:
		fixas_mundo.append(no.transform * f)
	adicionar_colisoes(_estruturas, fixas_mundo)
	# Parte que gira: os dois braços, o cesto (estrado + bordas) e os contrapesos de pedra
	var giro := Node3D.new()
	giro.position = Vector3(0.0, eixo_y, eixo_z)
	no.add_child(giro)
	var moveis: Array[Transform3D] = []
	var estrado: Array[Transform3D] = []
	var pedras: Array[Transform3D] = []
	var cesto := Vector3(0.0, -eixo_y - 0.04, -eixo_z)   # centro do cesto visto do eixo (o topo do estrado fica rente ao asfalto)
	var lados_mundo: Array[Transform3D] = []
	for lado: float in [-1.0, 1.0]:
		var x := lado * (meia + 0.75)
		var ponta := Vector3(x, cesto.y + 0.3, cesto.z + CESTO_MEIO - 0.5)
		var tras := Vector3(x, 0.0, 0.0) + (Vector3(x, 0.0, 0.0) - ponta).normalized() * 4.2
		moveis.append(_viga(ponta, tras, 0.5))
		pedras.append(Transform3D(Basis.from_scale(Vector3(1.8, 2.2, 2.0)), tras + Vector3.DOWN * 0.9))
		moveis.append(Transform3D(Basis.from_scale(Vector3(0.3, 0.9, CESTO_MEIO * 2.0)), Vector3(lado * (meia + 0.3), cesto.y + 0.5, cesto.z)))
		for k in [moveis.size() - 2, moveis.size() - 1]:
			lados_mundo.append(no.transform * giro.transform * moveis[k])
		lados_mundo.append(no.transform * giro.transform * pedras[pedras.size() - 1])
	for k in 9:
		estrado.append(Transform3D(Basis.from_scale(Vector3(meia * 2.0 + 0.6, 0.14, 0.92)), Vector3(0.0, cesto.y, cesto.z - CESTO_MEIO + 0.5 + k * 1.0)))
	moveis.append(Transform3D(Basis.from_scale(Vector3(meia * 2.0 + 0.9, 0.5, 0.4)), Vector3(0.0, cesto.y + 0.3, cesto.z - CESTO_MEIO)))
	criar_multimesh(giro, moveis, madeira)
	var corpo_lados := StaticBody3D.new()
	corpo_lados.collision_layer = 1
	corpo_lados.collision_mask = 0
	corpo_lados.add_to_group("estrutura")
	_no.add_child(corpo_lados)
	adicionar_colisoes(corpo_lados, lados_mundo)
	criar_multimesh(giro, estrado, madeira_clara)
	criar_multimesh(giro, pedras, _material_pilar())
	# Batente fixo na frente do cesto (colisão): segura quem espera o disparo
	var batente: Array[Transform3D] = [Transform3D(b * Basis.from_scale(Vector3(meia * 2.0, 1.0, 0.5)), pos + t * (CESTO_MEIO + 0.4) + Vector3.UP * 0.35)]
	criar_multimesh(_no, batente, madeira)
	adicionar_colisoes(_estruturas, batente)
	# Aviso: duas lanternas nos cavaletes (vermelhas armando, verdes na hora do disparo)
	var brilho := _material_luz(Color(1.0, 0.2, 0.05), 3.0)
	var lampadas: Array[Transform3D] = []
	for lado: float in [-1.0, 1.0]:
		lampadas.append(Transform3D(Basis.from_scale(Vector3(0.5, 0.5, 0.5)), Vector3(lado * (meia + 1.6), eixo_y + 0.9, eixo_z)))
		no.add_child(Dino._chama(Vector3(lado * (meia + 1.6), 1.6, eixo_z + 6.5), 0.6))
	criar_multimesh(no, lampadas, brilho, false)
	_catapultas.append({"pos": pos, "dir": t, "raio": float(c.get("raio", 4.3)), "periodo": float(c.get("periodo", 4.0)), "ativo_s": float(c.get("ativo_s", 0.7)),
		"fase": float(ce.fase), "vel_h": float(c.get("vel_h", 20.0)), "vel_v": float(c.get("vel_v", 16.0)),
		"brilho": brilho, "jato": null, "luz": null, "braco": giro, "lados": corpo_lados, "ativo": false, "trecho": ce.k, "i": i})


func _atualizar_catapultas() -> void:
	for c in _catapultas:
		var t := fmod(_relogio_desvios + float(c.fase), float(c.periodo))
		var ativo := t < float(c.ativo_s)
		var falta := float(c.periodo) - t   # segundos até a próxima erupção
		c.ativo = ativo
		var ronco := clampf(1.0 - falta / 1.5, 0.0, 1.0)
		(c.brilho as StandardMaterial3D).emission_energy_multiplier = 1.0 + ronco * 5.0 + (10.0 if ativo else 0.0)
		if c.get("braco") != null:
			# Braço: sobe num tranco no disparo (0,18 s), fica um instante no alto e volta devagar
			var sobe := clampf(t / 0.18, 0.0, 1.0)
			var volta := clampf((t - float(c.ativo_s) - 0.3) / 1.6, 0.0, 1.0)
			(c.braco as Node3D).rotation.x = -deg_to_rad(68.0) * sobe * (1.0 - volta * volta * (3.0 - 2.0 * volta))
			if c.get("lados") != null:
				(c.lados as StaticBody3D).collision_layer = 1 if volta >= 0.97 or sobe <= 0.0 else 0   # no alto, os braços não barram ninguém
			var m_b := c.brilho as StandardMaterial3D
			m_b.albedo_color = Color(0.2, 1.0, 0.3) if falta < 0.6 or ativo else Color(1.0, 0.2, 0.05)
			m_b.emission = m_b.albedo_color
		if c.luz:
			(c.luz as OmniLight3D).light_energy = 0.5 + ronco * 3.0 + (14.0 if ativo else 0.0)
		if c.jato:
			(c.jato as GPUParticles3D).emitting = ativo or t < float(c.ativo_s) + 0.6


## Velocidade que o gêiser dá a quem está em cima dele agora (ZERO fora da erupção).
func catapulta_em(p: Vector3) -> Vector3:
	for c in _catapultas:
		if not c.ativo:
			continue
		var d: Vector3 = p - c.pos
		if Vector2(d.x, d.z).length() < float(c.raio) + 0.5 and d.y > -1.5 and d.y < 3.5:
			return (c.dir as Vector3) * float(c.vel_h) + Vector3.UP * float(c.vel_v)
	return Vector3.ZERO


## Para os bots: o gêiser do desvio em que a amostra i está. {pos, falta (m até o centro da boca, na
## horizontal), espera (s até a próxima erupção), ativo}. Vazio fora de desvio de catapulta.
func catapulta_adiante(i: int) -> Dictionary:
	var melhor := {}
	for c in _catapultas:
		if int(c.trecho) != trecho_de(i) or i > int(c.i) + 3:
			continue
		if not melhor.is_empty() and int(c.i) > int(melhor.i):
			continue
		var t := fmod(_relogio_desvios + float(c.fase), float(c.periodo))
		var d: Vector3 = c.pos - _pts[i]
		melhor = {"pos": c.pos, "i": c.i, "falta": Vector2(d.x, d.z).length(), "espera": float(c.periodo) - t, "ativo": bool(c.ativo), "raio": c.raio}
	return melhor


## Bifurcação à frente na estrada principal (até `alcance` m; ou logo atrás, até 20 m): os desvios
## que saem dela (vazia se não houver).
func desvios_adiante(i: int, alcance := 110.0) -> Array:
	var lista := []
	for d in desvios:
		if _trecho[d.i_de] != trecho_de(i):
			continue
		var falta: float = float(d.s_de) - _s[clampi(i, 0, _s.size() - 1)]
		if falta > -20.0 and falta < alcance:
			lista.append(d)
	return lista


func desvio_de(k: int) -> Dictionary:
	for d in desvios:
		if int(d.k) == k:
			return d
	return {}


## Amostra do trecho k mais perto de p (entre as amostras a e b; -1 = o trecho todo).
func amostra_no_trecho(p: Vector3, k: int, a := -1, b := -1) -> int:
	var i0 := _inicio_trecho[k] if a < 0 else maxi(a, _inicio_trecho[k])
	var i1 := _fim_trecho[k] if b < 0 else mini(b, _fim_trecho[k])
	var melhor := i0
	var melhor_d := INF
	for i in range(i0, i1 + 1):
		var d := p.distance_squared_to(_pts[i])
		if d < melhor_d:
			melhor_d = d
			melhor = i
	return melhor


# ------------------------------------------------------------------ pistões de granito

## Portões de granito na estrada (mapa.subida.pistoes, Pharaoh's Climb): um par de pilones com
## lintel e disco solar alado; de cada pilone sai um bloco de granito que fecha meia estrada. Os
## dois lados se alternam (periodo s): sempre sobra um lado livre. O bloco é AnimatableBody3D — a
## pancada empurra o carro para o outro lado (e a estrada não tem cerca). Lâmpadas no pilone ficam
## vermelhas com o bloco fora (ou saindo em menos de 0,7 s) e verdes com o caminho livre.
var _pistoes: Array = []        # {i, s, fase, blocos: [esq, dir], lampadas: [mat esq, mat dir], base, centro, lat, meia}
var _pist_periodo := 4.0
var _pist_mover := 0.5
var _pist_t := 0.0

func _montar_pistoes() -> void:
	var cfg: Dictionary = cfg_sub("pistoes", {})
	if cfg.is_empty():
		return
	_pist_periodo = float(cfg.get("periodo", 4.0))
	_pist_mover = float(cfg.get("mover_s", 0.5))
	var alto := float(cfg.get("altura", 4.2))
	var comp := float(cfg.get("comprimento", 6.0))
	var meia := largura_estrada * 0.5
	var mat_pedra := _material_pedra_egito(1.4)
	mat_pedra.set_shader_parameter("modo", 2)
	mat_pedra.set_shader_parameter("coluna_glifos_largura", 1.6)
	var granito := ShaderMaterial.new()
	granito.shader = load("res://shaders/pedra_egito.gdshader")
	granito.set_shader_parameter("modo", 0)
	granito.set_shader_parameter("fiada", alto)
	granito.set_shader_parameter("bloco", comp)
	granito.set_shader_parameter("cor_pedra", Color(0.36, 0.3, 0.3))
	granito.set_shader_parameter("cor_pedra_b", Color(0.22, 0.19, 0.2))
	granito.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 4, 131))
	granito.set_shader_parameter("altura_chao", -100.0)
	var ouro := _material_metal(Color(1.0, 0.74, 0.3), 1.0, 0.25)
	for item in cfg.get("lista", []):
		var k := _nomes_trecho.find(str(item[0]))
		if k < 0:
			continue
		var i := _inicio_trecho[k]
		while i < _fim_trecho[k] and _s[i] - _s[_inicio_trecho[k]] < float(item[1]):
			i += 1
		var c := _pts[i]
		var t := Vector3(_tan[i].x, 0.0, _tan[i].z).normalized()
		var l := _lat[i]
		var b := Basis(l, Vector3.UP, -t)   # x = lateral, z = para trás
		var no := Node3D.new()
		no.name = "Pistao%d" % _pistoes.size()
		_no.add_child(no)
		var pecas: Array[Transform3D] = []
		var cornijas: Array[Transform3D] = []
		var ap: Array[Transform3D] = []
		var caixa := func(lat: float, y0: float, y1: float, larg: float, prof: float) -> Transform3D:
			return Transform3D(b * Basis.from_scale(Vector3(larg, y1 - y0, prof)), c + l * lat + Vector3.UP * ((y0 + y1) * 0.5))
		# Laje mais larga embaixo do portão (apoio dos pilones), com coluna até o chão de cada lado
		pecas.append(caixa.call(0.0, -ESPESSURA_ESTRADA - 1.2, -ESPESSURA_ESTRADA + 0.02, largura_estrada + 17.0, comp + 8.0))
		for s: float in [-1.0, 1.0]:
			var pe := c + l * s * (meia + 4.5)
			var chao := _terreno.altura_em(pe.x, pe.z)
			if c.y - chao > 3.0:
				ap.append(Transform3D(b * Basis.from_scale(Vector3(4.0, c.y - chao, 4.0)), Vector3(pe.x, (c.y + chao) * 0.5 - 1.5, pe.z)))
			# Pilone: tronco afinando em degraus (3 caixas) e cornija
			for f in 3:
				var y0 := f * 4.4
				var larg := 7.4 - f * 0.9
				pecas.append(caixa.call(s * (meia + 0.6 + larg * 0.5), y0, y0 + 4.4, larg, comp + 3.0 - f * 0.8))
			cornijas.append(caixa.call(s * (meia + 3.6), 13.2, 14.6, 7.2, comp + 2.6))
		# Lintel por cima da estrada e disco solar alado
		pecas.append(caixa.call(0.0, 10.6, 13.2, largura_estrada + 2.0, comp + 1.0))
		cornijas.append(caixa.call(0.0, 13.2, 14.6, largura_estrada + 4.0, comp + 2.0))
		criar_multimesh(no, pecas, mat_pedra)
		var mat_c := _material_pedra_egito(1.4)
		mat_c.set_shader_parameter("cor_pedra", Color(0.9, 0.78, 0.58))
		criar_multimesh(no, cornijas, mat_c)
		criar_multimesh(no, ap, _material_pedra_egito(1.2))
		var asas: Array[Transform3D] = []
		for face: float in [-1.0, 1.0]:
			var centro := c + Vector3.UP * 11.9 - t * face * (comp * 0.5 + 0.55)
			var disco := MeshInstance3D.new()
			var cil := CylinderMesh.new()
			cil.top_radius = 1.1
			cil.bottom_radius = 1.1
			cil.height = 0.3
			disco.mesh = cil
			disco.material_override = ouro
			disco.transform = Transform3D(Basis(l, t, Vector3.UP), centro)
			no.add_child(disco)
			for s: float in [-1.0, 1.0]:
				for pena in 3:
					var y := 0.5 - pena * 0.5
					var larg := 4.2 - pena * 0.9
					asas.append(Transform3D(b * Basis.from_scale(Vector3(larg, 0.32, 0.15)), centro + l * s * (1.2 + larg * 0.5) + Vector3.UP * y))
		criar_multimesh(no, asas, ouro)
		var estrutura := StaticBody3D.new()
		estrutura.collision_layer = 1
		estrutura.collision_mask = 0
		estrutura.add_to_group("estrutura")
		no.add_child(estrutura)
		adicionar_colisoes(estrutura, pecas.slice(1))   # a laje fica abaixo do asfalto (sem colisão)
		adicionar_colisoes(estrutura, ap)
		# Blocos de granito e lâmpadas de aviso (uma por lado, viradas para quem chega)
		var blocos: Array = []
		var lampadas: Array = []
		for s: float in [-1.0, 1.0]:
			var corpo := AnimatableBody3D.new()
			corpo.sync_to_physics = true
			corpo.collision_layer = 1
			corpo.collision_mask = 0
			corpo.add_to_group("estrutura")
			var cs := CollisionShape3D.new()
			var forma := BoxShape3D.new()
			forma.size = Vector3(meia, alto, comp)   # fora, o bloco fecha da beirada até o meio da estrada
			cs.shape = forma
			corpo.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = forma.size
			mi.mesh = bm
			mi.material_override = granito
			corpo.add_child(mi)
			# Faixa dourada na cara do bloco (o lado que avança)
			var friso := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.12, alto * 0.8, comp * 0.9)
			friso.mesh = fm
			friso.material_override = ouro
			friso.position = Vector3(-s * (forma.size.x * 0.5 + 0.03), 0.0, 0.0)
			corpo.add_child(friso)
			no.add_child(corpo)
			blocos.append(corpo)
			var lamp := StandardMaterial3D.new()
			lamp.emission_enabled = true
			lamp.albedo_color = Color(0.1, 0.1, 0.1)
			var lm := MeshInstance3D.new()
			var esfera := SphereMesh.new()
			esfera.radius = 0.55
			esfera.height = 1.1
			lm.mesh = esfera
			lm.material_override = lamp
			lm.position = c + l * s * (meia + 1.1) + Vector3.UP * 9.0 - t * (comp * 0.5 + 1.6)
			no.add_child(lm)
			lampadas.append(lamp)
		_pistoes.append({"i": i, "s": _s[i], "fase": float(item[2]) if item.size() > 2 else 0.0, "blocos": blocos,
			"lampadas": lampadas, "base": Basis(l, Vector3.UP, -t), "centro": c + Vector3.UP * (alto * 0.5 + 0.02), "lat": l, "meia": meia})
	_atualizar_pistoes()


## Quanto o bloco de um lado (0 = esquerdo, 1 = direito) está para fora (0..1) no instante t.
func _extensao_pistao(p: Dictionary, lado: int, t: float) -> float:
	var f := fposmod(t + float(p.fase) + (_pist_periodo * 0.5 if lado == 1 else 0.0), _pist_periodo)
	var meio := _pist_periodo * 0.5
	if f < _pist_mover:
		return smoothstep(0.0, _pist_mover, f)
	if f < meio:
		return 1.0
	if f < meio + _pist_mover:
		return 1.0 - smoothstep(meio, meio + _pist_mover, f)
	return 0.0


func _atualizar_pistoes() -> void:
	for p: Dictionary in _pistoes:
		for lado in 2:
			var s := -1.0 if lado == 0 else 1.0
			var e := _extensao_pistao(p, lado, _pist_t)
			var larg: float = p.meia
			# Recolhido: inteiro dentro do pilone; fora: da beirada até o meio
			var dentro: float = p.meia + larg * 0.5 + 0.8
			var fora: float = p.meia - larg * 0.5
			var lat := lerpf(dentro, fora, e) * s
			var corpo: AnimatableBody3D = p.blocos[lado]
			corpo.global_transform = Transform3D(p.base, p.centro + p.lat * lat)
			var perigo := maxf(e, _extensao_pistao(p, lado, _pist_t + 0.7))
			var m: StandardMaterial3D = p.lampadas[lado]
			m.emission = Color(1.0, 0.1, 0.05) if perigo > 0.05 else Color(0.2, 1.0, 0.3)
			m.emission_energy_multiplier = 6.0


func _physics_process(delta: float) -> void:
	_relogio_desvios += delta
	if not _catapultas.is_empty():
		_atualizar_catapultas()
	if not _ejetores.is_empty():
		_atualizar_ejetores()
	if _pistoes.is_empty():
		return
	_pist_t += delta
	_atualizar_pistoes()


## Para os bots: o próximo portão de granito (até 90 m à frente, no mesmo trecho). Vazio se não
## houver. {s: progresso do portão (identifica), falta: metros até ele, livre: [esq, dir] = por quantos
## segundos, a partir de agora, o bloco de cada lado continua recolhido (0 = está fora), lat: lateral do
## meio de cada faixa}.
func pistao_adiante(i: int) -> Dictionary:
	for p: Dictionary in _pistoes:
		var falta: float = p.s - _s[i]
		if falta < -4.0 or falta > 90.0 or _trecho[p.i] != _trecho[i]:
			continue
		var livre := [0.0, 0.0]
		for lado in 2:
			var t := 0.0
			while t < _pist_periodo and _extensao_pistao(p, lado, _pist_t + t) < 0.05:
				t += 0.05
			livre[lado] = t
		return {"s": p.s, "falta": falta, "livre": livre, "lat": largura_estrada * 0.5 - 2.4}
	return {}


## O bloco do lado `lado` do portão de progresso `s_pistao` fica recolhido (livre) do instante
## agora+t0 até agora+t1?
func pistao_livre_entre(s_pistao: float, lado: int, t0: float, t1: float) -> bool:
	for p: Dictionary in _pistoes:
		if absf(float(p.s) - s_pistao) < 0.5:
			var t := t0
			while t <= t1:
				if _extensao_pistao(p, lado, _pist_t + t) > 0.02:
					return false
				t += 0.05
			return true
	return true


## Índice do checkpoint mais adiantado (acima de `atual`) em que `p` está dentro; -1 se nenhum.
func checkpoint_em(p: Vector3, atual: int) -> int:
	var achou := -1
	for k in range(atual + 1, checkpoints.size()):
		var c: Vector3 = checkpoints[k].pos
		if Vector2(p.x - c.x, p.z - c.z).length() < _raio_cp + 1.0 and p.y > c.y - 2.0 and p.y < c.y + _altura_cp + 2.0:
			achou = k
	return achou


## Quem passou foi o jogador: o cilindro acende forte, apaga e some (pedido do dono);
## os anteriores que ainda estiverem à vista somem junto. Voltam na próxima etapa.
func piscar_checkpoint(k: int) -> void:
	for j in k + 1:
		var c: Dictionary = checkpoints[j]
		if c.get("pego", false):
			continue
		c["pego"] = true
		var mat: ShaderMaterial = c.mat
		var tw := create_tween()
		if j == k:
			tw.tween_method(func(b: float): mat.set_shader_parameter("brilho", b), 3.5, 1.0, 0.3)
		tw.tween_method(func(b: float): mat.set_shader_parameter("brilho", b), 1.0, 0.0, 0.5)
		tw.tween_callback(func(): c.no.visible = false)


## Etapa nova: os checkpoints aparecem de novo.
func mostrar_checkpoints() -> void:
	for c in checkpoints:
		c["pego"] = false
		(c.mat as ShaderMaterial).set_shader_parameter("brilho", 1.0)
		c.no.visible = true


## Onde um carro que caiu volta: no último checkpoint que passou (ou numa vaga da largada),
## com um desvio lateral para não empilhar todo mundo no mesmo ponto. Regra do dono: em mapa
## com checkpoint ninguém é eliminado por queda — nem depois de saltar da rampa final, nem
## depois de tocar o alvo (perde a vaga e tenta de novo). Só o tempo ou as vagas cheias encerram.
func ressurgimento(v: Veiculo):
	if checkpoints.is_empty():
		return null
	if v.checkpoint < 0:
		return largada.transform_vaga(randi() % largada.vagas.size())
	var c: Dictionary = checkpoints[v.checkpoint]
	var t: Vector3 = c.tan
	var lateral := randf_range(-1.0, 1.0) * (largura_estrada * 0.5 - 2.5)
	var pos: Vector3 = c.pos + c.lat * lateral + Vector3.UP * 0.6
	return Transform3D(Basis.looking_at(t, Vector3.UP), pos)


# ------------------------------------------------------------------ consultas

## Amostra da estrada mais perto de `p` (até ~14 m do eixo e 6 m de altura); -1 fora da estrada.
func indice_estrada(p: Vector3, folga_lateral := 14.0) -> int:
	var c := Vector2i(floori(p.x / CELULA_GRADE), floori(p.z / CELULA_GRADE))
	var melhor := -1
	var melhor_d := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var lista: PackedInt32Array = _grade.get(c + Vector2i(dx, dz), PackedInt32Array())
			for i in lista:
				var d := _pts[i] - p
				var dh := Vector2(d.x, d.z).length()
				if dh > folga_lateral or absf(d.y) > 8.0:
					continue
				var dd := dh + absf(d.y) * 2.0
				if dd < melhor_d:
					melhor_d = dd
					melhor = i
	return melhor


## Índice da amostra a `metros` do começo do trecho (A, B ou C); negativo = metros antes do fim.
func indice_trecho(nome: String, metros: float) -> int:
	var k := _nomes_trecho.find(nome)
	if k < 0:
		return -1
	var i0 := _inicio_trecho[k]
	var i1 := _fim_trecho[k]
	var i := i0
	if metros < 0.0:
		while i < i1 and _s[i1] - _s[i] > -metros:
			i += 1
	else:
		while i < i1 and _s[i] - _s[i0] < metros:
			i += 1
	return i


func inicio_trecho_de(i: int) -> int:
	return _inicio_trecho[trecho_de(i)]


func normal_em(i: int) -> Vector3:
	return lateral_em(i).cross(tangente_em(i)).normalized()


func total_amostras() -> int:
	return _n_principal


func amostra(i: int) -> Vector3:
	return _pts[clampi(i, 0, _pts.size() - 1)]


func lateral_em(i: int) -> Vector3:
	return _lat[clampi(i, 0, _lat.size() - 1)]


func tangente_em(i: int) -> Vector3:
	return _tan[clampi(i, 0, _tan.size() - 1)]


## Nome do trecho k (A, B, C ou o nome do desvio).
func nome_trecho(k: int) -> String:
	return str(_nomes_trecho[k]) if k >= 0 and k < _nomes_trecho.size() else "?"


func trecho_de(i: int) -> int:
	return _trecho[clampi(i, 0, _trecho.size() - 1)]


func fim_do_trecho(i: int) -> int:
	return _fim_trecho[trecho_de(i)]


func progresso_amostra(i: int) -> float:
	return _s[clampi(i, 0, _s.size() - 1)]


## Índice `metros` à frente de `i` no mesmo trecho.
func indice_adiante(i: int, metros: float) -> int:
	var fim := fim_do_trecho(i)
	var j := i
	while j < fim and _s[j] - _s[i] < metros:
		j += 1
	return j


## Maior curvatura (1/raio) entre `i` e `metros` à frente.
func curvatura_adiante(i: int, metros: float) -> float:
	var fim := indice_adiante(i, metros)
	var k := 0.0
	for j in range(i, fim + 1, 2):
		k = maxf(k, _curv[j])
	return k


## Recinto (largada ou plataforma) em que o carro está, ou null na estrada.
func recinto_em(p: Vector3):
	for r: Recinto in [largada, plataforma]:
		if r.sem_piso:
			continue
		var l := r.local(p)
		# Depois do portão, 25 m de corredor ainda guiados pelo cercado (o carro sai alinhado)
		var alem := r == plataforma and l.x > r.comprimento and absf(l.y) < r.saida_largura * 0.5 + 2.0
		if l.x > -3.0 and (l.x < r.comprimento + 1.0 or (alem and l.x < r.comprimento + 25.0)) and absf(l.y) < r.largura_arena * 0.5 + 4.0 and absf(p.y - r.piso_y) < 8.0:
			return r
	return null


func x_perfil(p: Vector3) -> float:
	var r = recinto_em(p)
	if r == largada:
		return clampf(largada.local(p).x, 0.0, _s_largada_fim)
	if r == plataforma:
		return _s_plat_ini + clampf(plataforma.local(p).x, 0.0, plataforma.comprimento) * (_s_plat_fim - _s_plat_ini) / plataforma.comprimento
	if plataforma.sem_piso:
		var lp := plataforma.local(p)
		if lp.x > -30.0 and lp.x < plataforma.comprimento + 2.0 and absf(lp.y) < plataforma.largura_arena * 0.5 + 30.0 and p.y > plataforma.chao_y and p.y < plataforma.piso_y + 60.0:
			return _s_plat_ini + clampf(lp.x, 0.0, plataforma.comprimento) * (_s_plat_fim - _s_plat_ini) / plataforma.comprimento
	var i := indice_estrada(p, 40.0)
	if i >= 0:
		return _s[i]
	# No ar sobre a rampa final (saída): continua contando pela reta da rampa
	var fim := _pts[_fim_trecho[2]]
	var d := p - fim
	if Vector2(d.x, d.z).length() < 200.0 and d.dot(frente) > -5.0:
		return s_final + d.dot(frente)
	return -1.0


## Só vale quem passou pela PONTA da rampa final: cair pela lateral perto do fim (depois do último
## checkpoint) ainda volta no checkpoint. Antes, qualquer carro no ar a até 40 m dos últimos 20 m
## da estrada contava como saída — e quem caía ali ficava fora da etapa.
func saltou_da_rampa(p: Vector3) -> bool:
	var fim := _pts[_fim_trecho[2]]
	var d := p - fim
	var lado := frente.cross(Vector3.UP).normalized()
	return d.dot(frente) > -3.0 and absf(d.dot(lado)) < largura_estrada * 0.5 + 3.0 and d.y > -15.0


func direcao_pista(p: Vector3) -> Vector3:
	if recinto_em(p) != null:
		return Vector3.ZERO
	var lp := looping_em(p)
	if lp:
		return lp.rumo
	var i := indice_estrada(p)
	return _tan[i] if i >= 0 else Vector3.ZERO


func impulso_em(p: Vector3) -> Vector3:
	var d := largada.impulso_em(p)
	if d != Vector3.ZERO:
		return d
	d = plataforma.impulso_em(p)
	if d != Vector3.ZERO:
		return d
	for im in _impulsos_estrada:
		var q: Vector3 = p - im[0]
		if absf(q.dot(im[1])) < Recinto.IMPULSO_MEIO.x and absf(q.dot(im[2])) < (float(im[5]) if im.size() > 5 else Recinto.IMPULSO_MEIO.y + 0.5) and absf(q.dot(im[3])) < 2.5:
			return im[1]
	return Vector3.ZERO


## Acelerador de looping em `p`: velocidade mínima que ele garante ao longo da pista (0 = não é um).
## Diferente do tranco comum, vale em qualquer inclinação (até de cabeça para baixo) e não soma velocidade.
func impulso_piso(p: Vector3) -> float:
	for im in _impulsos_estrada:
		if im.size() > 6:
			var q: Vector3 = p - im[0]
			if absf(q.dot(im[1])) < Recinto.IMPULSO_MEIO.x and absf(q.dot(im[2])) < float(im[5]) and absf(q.dot(im[3])) < 2.5:
				return float(im[4])
	return 0.0


func impulso_segue_carro(p: Vector3) -> bool:
	return recinto_em(p) != null   # na estrada: na direção da placa


func velocidade_impulso(p: Vector3) -> float:
	for im in _impulsos_estrada:
		if (p - im[0]).length() < 8.0:
			return im[4]
	return impulso_velocidade


func largura_em(i: int) -> float:
	return _larg[clampi(i, 0, _larg.size() - 1)]


## Menor largura da estrada entre `i` e `metros` à frente (trechos estreitos do Frozen Peak).
func largura_adiante(i: int, metros: float) -> float:
	var fim := indice_adiante(i, metros)
	var w := INF
	for j in range(i, fim + 1, 2):
		w = minf(w, _larg[j])
	return w


## Aderência do piso na amostra (1 = normal; menos = gelo vivo) e a menor até `metros` à frente.
func aderencia_em(i: int) -> float:
	return _ader[clampi(i, 0, _ader.size() - 1)]


func aderencia_adiante(i: int, metros: float) -> float:
	var fim := indice_adiante(i, metros)
	var a := 1.0
	for j in range(i, fim + 1, 2):
		a = minf(a, _ader[j])
	return a


func em_vao(i: int) -> bool:
	return _vao[clampi(i, 0, _vao.size() - 1)] == 1


## O próximo vão (salto) do trecho, até `alcance` m à frente: {falta: metros até o lábio (negativo =
## já está no ar sobre o vão), comp: comprimento do vão, i0/i1: amostras do lábio e do pouso}. Vazio se não houver.
func vao_adiante(i: int, alcance := 120.0) -> Dictionary:
	var s := _s[i]
	var k := _trecho[i]
	for v: Dictionary in _vaos:
		if int(v.trecho) != k or float(v.s1) < s - 2.0:
			continue
		var falta: float = float(v.s0) - s
		if falta > alcance:
			return {}
		var r := {"falta": falta, "comp": float(v.s1) - float(v.s0), "i0": v.i0, "i1": v.i1}
		if v.has("vel"):
			r["vel"] = v.vel
		if v.has("ejetor"):
			r["ejetor"] = v.ejetor
			r["sobe"] = v.sobe
		return r
	return {}


## Lista dos vãos do percurso (para sinalização e câmeras de conferência).
func vaos() -> Array:
	return _vaos


func buraco_mortal(p: Vector3) -> bool:
	return plataforma.buraco_mortal(p)


## Ponto da estrada para pousar de paraquedas depois de cair: o mais adiantado no percurso que
## esteja abaixo do carro e ao alcance do planeio (~4:1).
func ponto_pouso(p: Vector3) -> Vector3:
	var melhor := Vector3.INF
	var melhor_s := -INF
	for i in range(0, _pts.size(), 5):
		if _vao[i] == 1 or _vao[i] == 4:
			continue
		var q := _pts[i]
		var desnivel := p.y - q.y
		if desnivel < 6.0:
			continue
		var dh := Vector2(q.x - p.x, q.z - p.z).length()
		if dh > desnivel * 4.0:
			continue
		if _s[i] > melhor_s:
			melhor_s = _s[i]
			melhor = q
	return melhor


func status_texto(p: Vector3) -> String:
	var r = recinto_em(p)
	if r == largada:
		return "NA LARGADA"
	if r == plataforma:
		return "NA PLATAFORMA"
	return "SUBINDO"


# ------------------------------------------------------------------ largada (vagas e semáforo)

func sortear_vagas(quantidade: int, rng: RandomNumberGenerator) -> Array[int]:
	return largada.sortear_vagas(quantidade, rng)


func transform_vaga(i: int) -> Transform3D:
	return largada.transform_vaga(i)


func pintar_vagas(cores: Dictionary) -> void:
	largada.pintar_vagas(cores)


func vagas_largada(quantidade: int) -> Array[Transform3D]:
	var lista: Array[Transform3D] = []
	for i in mini(quantidade, largada.vagas.size()):
		lista.append(largada.transform_vaga(i))
	return lista
