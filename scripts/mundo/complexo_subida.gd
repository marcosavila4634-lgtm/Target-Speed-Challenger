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
var _tunel: TunelAtalho   # túnel-atalho da etapa atual (se a etapa tiver)
var _paredao: ParedaoFino # paredão fino com buraco de atalho da etapa atual (se a etapa tiver)


## Pontos de controle de um trecho da estrada (config mapa.subida.trechos), no mundo.
static func pontos_trecho(nome: String) -> PackedVector3Array:
	var lista := PackedVector3Array()
	for p in Config.valor("mapa.subida.trechos." + nome, []):
		lista.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
	return lista


func montar(p_indice: int, p_perfil: PerfilRampa, terreno: Terreno) -> void:
	indice_equipe = p_indice
	perfil = p_perfil
	_terreno = terreno
	distancia_saida = Config.valor("mapa.distancia_saida_alvo", 800)
	name = "ClimbToDeath"
	cor = Color(1.0, 0.45, 0.08)
	largura_estrada = float(Config.valor("mapa.subida.largura_estrada", 10))
	largura = largura_estrada
	impulso_velocidade = float(Config.valor("mapa.subida.impulso_velocidade", 22))
	_estruturas = StaticBody3D.new()
	_estruturas.name = "Estruturas"
	_estruturas.collision_layer = 1
	_estruturas.collision_mask = 0
	_estruturas.add_to_group("estrutura")
	add_child(_estruturas)
	if OS.get_environment("TSC_SUB_LOG") != "":
		for q: Vector2 in [Vector2(-1530, -300), Vector2(-1000, -500), Vector2(-600, -300), Vector2(0, -800), Vector2(-300, -200), Vector2(0, 0)]:
			print("[SUB] terreno em ", q, " = ", terreno.altura_em(q.x, q.y))
	_montar_largada(terreno)
	_montar_plataforma_alta(terreno)
	_montar_estrada(terreno)
	# Direções da rampa final (câmera, alvo, partida): do alvo para a rampa e sentido do lançamento
	var n := _pts.size()
	var t_final := _tan[n - 1]
	frente = Vector3(t_final.x, 0.0, t_final.z).normalized()
	direcao = -frente
	lateral = frente.cross(Vector3.UP).normalized()
	x_inicio_pista = 0.0
	perfil.comprimento_horizontal = s_final
	_semaforo.clear()
	_semaforo.append_array(largada.semaforo_lampadas)
	semaforo(0)


# ------------------------------------------------------------------ montagem

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


func _montar_largada(terreno: Terreno) -> void:
	var cfg: Dictionary = Config.valor("mapa.subida.largada", {})
	largada = Recinto.new()
	largada.name = "Largada"
	_recinto_cfg(largada, cfg)
	var o: Array = cfg.get("origem", [-1560, 10, -300])
	var f: Array = cfg.get("frente", [1, 0])
	add_child(largada)
	var origem := Vector3(float(o[0]), float(o[1]), float(o[2]))
	largada.montar(origem, Vector3(float(f[0]), 0.0, float(f[1])), terreno.altura_em(origem.x, origem.z))
	_s_largada_fim = largada.comprimento


func _montar_plataforma_alta(terreno: Terreno) -> void:
	var cfg: Dictionary = Config.valor("mapa.subida.plataforma", {})
	plataforma = Recinto.new()
	plataforma.name = "Plataforma100"
	_recinto_cfg(plataforma, cfg)
	var o: Array = cfg.get("origem", [-900, 100, -600])
	var f: Array = cfg.get("frente", [0, 1])
	add_child(plataforma)
	var origem := Vector3(float(o[0]), float(o[1]), float(o[2]))
	plataforma.montar(origem, Vector3(float(f[0]), 0.0, float(f[1])), terreno.altura_em(origem.x, origem.z))


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
	var zp: Dictionary = Config.valor("mapa.subida.zona_pouso", {})
	_larg.resize(n)
	for i in n:
		_larg[i] = largura_estrada
		if _trecho[i] == 2 and not zp.is_empty():
			var d := _s[i] - _s[_inicio_trecho[2]]
			var comp := float(zp.get("comprimento", 130))
			var trans := float(zp.get("transicao", 40))
			_larg[i] = lerpf(float(zp.get("largura", 14)), largura_estrada, clampf((d - comp) / trans, 0.0, 1.0))
	for i in n:
		var c := Vector2i(floori(_pts[i].x / CELULA_GRADE), floori(_pts[i].z / CELULA_GRADE))
		var lista: PackedInt32Array = _grade.get(c, PackedInt32Array())
		lista.append(i)   # PackedInt32Array é copiado por valor: precisa guardar de volta
		_grade[c] = lista
	_malha_estrada()
	_pilares(terreno)
	_luzes_bordas()
	_montar_impulsos_estrada()
	_montar_checkpoints()
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SUB] amostras=", _pts.size(), " trechos=", _inicio_trecho, "..", _fim_trecho, " s_salto=", s_salto, " s_final=", s_final)
		for i in [0, 1, 5, 20, 60, 120]:
			print("[SUB] amostra ", i, " = ", _pts[i], " s=", _s[i])
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


func _malha_estrada() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var laterais := SurfaceTool.new()
	laterais.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()
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
	mat.shader = load("res://shaders/pista.gdshader")
	mat.set_shader_parameter("cor_equipe", cor)
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 3))
	mat.set_shader_parameter("largura", largura_estrada)
	mat.set_shader_parameter("comp_plataforma", -1.0)
	mat.set_shader_parameter("linha_largada", -100.0)
	mat.set_shader_parameter("inicio_rampa", 1.0e9)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)
	var mat_l := ShaderMaterial.new()
	mat_l.shader = load("res://shaders/lateral_pista.gdshader")
	mat_l.set_shader_parameter("cor_equipe", cor)
	var ml := MeshInstance3D.new()
	ml.mesh = laterais.commit()
	ml.material_override = mat_l
	add_child(ml)
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


## Pilares de concreto até o chão a cada ~22 m, com viga de apoio embaixo da estrada.
func _pilares(terreno: Terreno) -> void:
	var colunas: Array[Transform3D] = []
	var vigas: Array[Transform3D] = []
	var i := 0
	while i < _pts.size():
		var k := _trecho[i]
		if i - _inicio_trecho[k] < 12 or _fim_trecho[k] - i < 8:
			i += 1
			continue
		var p := _pts[i]
		var chao := terreno.altura_em(p.x, p.z)
		var topo := p.y - ESPESSURA_ESTRADA - 0.6
		if topo - chao > 1.0:
			var b := Basis.looking_at(Vector3(_tan[i].x, 0.0, _tan[i].z).normalized(), Vector3.UP)
			var lado := 2.6 if topo - chao < 60.0 else 3.6
			colunas.append(Transform3D(b * Basis.from_scale(Vector3(lado, topo - chao + 2.0, lado)), Vector3(p.x, (topo + chao - 2.0) * 0.5, p.z)))
			vigas.append(Transform3D(b * Basis.from_scale(Vector3(_larg[i] - 1.0, 1.0, 2.2)), Vector3(p.x, topo + 0.3, p.z)))
		i += 22
	var mat := material_concreto(0.0)
	criar_multimesh(self, colunas, mat)
	criar_multimesh(self, vigas, material_aco(0.0, 0.5))
	adicionar_colisoes(_estruturas, colunas)


## Lâmpadas âmbar nas bordas da estrada, "correndo" no sentido da subida (sem guarda-corpo).
func _luzes_bordas() -> void:
	var luzes: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	for i in range(2, _pts.size(), 4):
		var meia := _larg[i] * 0.5
		var n := _lat[i].cross(_tan[i]).normalized()
		for lado: float in [-1.0, 1.0]:
			luzes.append(Transform3D(Basis.looking_at(_tan[i], n) * Basis.from_scale(Vector3(0.3, 0.3, 0.7)), _pts[i] + _lat[i] * (meia + 0.12) * lado - n * 0.3))
			fases.append(i * 0.15)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/luz_sequencial.gdshader")
	mat.set_shader_parameter("energia", 7.0)
	_multimesh(luzes, mat, false, fases)


## Pontos de aceleração na estrada: [trecho, metros desde o começo do trecho] (mapa.subida.impulsos).
## Um deles fica logo antes da rampa de salto (sem ele muita gente não passa o vão).
func _montar_impulsos_estrada() -> void:
	for im in Config.valor("mapa.subida.impulsos", []):
		_impulso_trecho(im, self)


## Um ponto de aceleração [trecho, metros (negativo = antes do fim), tranco opcional] com a placa em `pai`.
func _impulso_trecho(im: Array, pai: Node) -> void:
	var k := ["A", "B", "C"].find(str(im[0]))
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
	# Nunca antes de curva: o tranco jogaria o carro para fora
	while i < i1 - 10 and curvatura_adiante(i, 150.0) > 1.0 / 350.0 and _s[i1] - _s[i] > 160.0:
		i += 1
	var t := _tan[i]
	var l := _lat[i]
	var nrm := l.cross(t).normalized()
	_impulsos_estrada.append([_pts[i], t, l, nrm, float(im[2]) if im.size() > 2 else impulso_velocidade])
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
	var cfg: Dictionary = Config.valor("mapa.subida.checkpoints", {})
	if cfg.is_empty():
		return
	fantasma_s = float(cfg.get("fantasma_s", 3.0))
	_raio_cp = float(cfg.get("raio", 6.5))
	_altura_cp = float(cfg.get("altura", 6.0))
	for f in cfg.get("fracoes", []):
		var alvo_s := float(f) * s_final
		var i := 0
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
		add_child(mi)
		# Sem legenda no cilindro (pedido do dono): o número só aparece no aviso da tela ao pegar
		checkpoints.append({"i": i, "s": _s[i], "pos": _pts[i], "tan": _tan[i], "lat": _lat[i], "mat": mat, "no": mi})


## Troca o que muda por etapa (depois do Terreno.preparar_etapa): o túnel-atalho e o paredão fino.
func preparar_etapa(_indice: int) -> void:
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
	mat.shader = load("res://shaders/pista.gdshader")
	mat.set_shader_parameter("cor_equipe", cor)
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 3))
	mat.set_shader_parameter("largura", largura_estrada)
	mat.set_shader_parameter("comp_plataforma", -1.0)
	mat.set_shader_parameter("linha_largada", -100.0)
	mat.set_shader_parameter("inicio_rampa", 1.0e9)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	_extra.add_child(mi)
	var mat_l := ShaderMaterial.new()
	mat_l.shader = load("res://shaders/lateral_pista.gdshader")
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
	criar_multimesh(_extra, colunas, material_concreto(0.0))
	criar_multimesh(_extra, vigas, material_aco(0.0, 0.5))
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


func amostra(i: int) -> Vector3:
	return _pts[clampi(i, 0, _pts.size() - 1)]


func lateral_em(i: int) -> Vector3:
	return _lat[clampi(i, 0, _lat.size() - 1)]


func tangente_em(i: int) -> Vector3:
	return _tan[clampi(i, 0, _tan.size() - 1)]


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
	var i := indice_estrada(p, 40.0)
	if i >= 0:
		return _s[i]
	# No ar sobre a rampa final (saída): continua contando pela reta da rampa
	var fim := _pts[_pts.size() - 1]
	var d := p - fim
	if Vector2(d.x, d.z).length() < 200.0 and d.dot(frente) > -5.0:
		return s_final + d.dot(frente)
	return -1.0


## Só vale quem passou pela PONTA da rampa final: cair pela lateral perto do fim (depois do último
## checkpoint) ainda volta no checkpoint. Antes, qualquer carro no ar a até 40 m dos últimos 20 m
## da estrada contava como saída — e quem caía ali ficava fora da etapa.
func saltou_da_rampa(p: Vector3) -> bool:
	var fim := _pts[_pts.size() - 1]
	var d := p - fim
	var lado := frente.cross(Vector3.UP).normalized()
	return d.dot(frente) > -3.0 and absf(d.dot(lado)) < largura_estrada * 0.5 + 3.0 and d.y > -15.0


func direcao_pista(p: Vector3) -> Vector3:
	if recinto_em(p) != null:
		return Vector3.ZERO
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
		if absf(q.dot(im[1])) < Recinto.IMPULSO_MEIO.x and absf(q.dot(im[2])) < Recinto.IMPULSO_MEIO.y + 0.5 and absf(q.dot(im[3])) < 2.5:
			return im[1]
	return Vector3.ZERO


func impulso_segue_carro(p: Vector3) -> bool:
	return recinto_em(p) != null   # na estrada: na direção da placa


func velocidade_impulso(p: Vector3) -> float:
	for im in _impulsos_estrada:
		if (p - im[0]).length() < 8.0:
			return im[4]
	return impulso_velocidade


func largura_em(i: int) -> float:
	return _larg[clampi(i, 0, _larg.size() - 1)]


func buraco_mortal(p: Vector3) -> bool:
	return plataforma.buraco_mortal(p)


## Ponto da estrada para pousar de paraquedas depois de cair: o mais adiantado no percurso que
## esteja abaixo do carro e ao alcance do planeio (~4:1).
func ponto_pouso(p: Vector3) -> Vector3:
	var melhor := Vector3.INF
	var melhor_s := -INF
	for i in range(0, _pts.size(), 5):
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
