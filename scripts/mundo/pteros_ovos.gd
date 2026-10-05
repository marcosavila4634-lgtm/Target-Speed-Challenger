extends Node3D
## Pterossauros da plataforma dos buracos do Extinction Day (pedido do dono, 2026-10-04): um bando voa
## em voltas por cima da plataforma soltando ovos. Ninguém mira: cada bicho solta o ovo de tempos em
## tempos, onde estiver, e o ovo cai onde cair. Ovo que acerta um carro (no chão ou no ar — na etapa do
## poço de lava pega quem está atravessando) deixa o carro `efeito_s` segundos escorregando como no gelo
## e com a direção invertida (Veiculo.ovo). No piso, o ovo estoura e respinga em quem estiver a `raio` m.
## A sombra do ovo no piso avisa onde ele vai cair.
##
## O modelo (assets/dino/pterossauro, CC-BY, ver creditos.txt) tem esqueleto e a animação de voo do
## autor: três batidas de asa e um planeio, em ciclo. Aqui o bicho ganha altura enquanto bate as asas
## e perde planando, inclina nas curvas e põe o ovo (sai de baixo do corpo, desce até as garras e cai).
##
## cfg (percursos.N.armadilhas.pteros_plataforma) = {quantidade, intervalo_s, efeito_s, envergadura,
## raio, sem_mira (ovos ao acaso entre dois mirados; pedido do dono: 4), altura [mín, máx] acima do piso}.
##
## O mesmo bando serve para um pedaço de ESTRADA (pedido do dono, 2026-10-04, por captura da E2):
## percursos.N.armadilhas.pteros_estrada = [{trecho, de, ate (metros no trecho), ...os mesmos campos}] →
## montar_estrada. Ali eles voam em voltas compridas ao longo da pista, a altura conta da pista embaixo
## deles, a sombra e a poça deitam na rampa, e o ovo que erra a pista estoura no chão lá embaixo. Com a
## câmera longe e nenhum carro por perto o bando da estrada dorme (some e para a animação).
## Conferência: TSC_PTERO_LOG=1 (registra ovos e acertos), TSC_PTERO_FIXO=1 (o primeiro fica parado no
## ar a 7 m do piso, no meio da plataforma, para foto de perto), TSC_OVO_CARRO=1 (todos os carros melados).

const CENA := "res://assets/dino/pterossauro/pterossauro.glb"
const G_OVO := 12.0
const ESC_OVO := 0.5        # o ovo do ninho (AlvoDino._malha_ovo) tem raio 1 e meia altura 1,5
const PREPARO := 0.9        # segundos entre o ovo aparecer embaixo do corpo e cair
const SOBE := 1.8           # metros que o bicho ganha batendo as asas e perde planando
const BATE := [0.16, 0.58]  # trecho do ciclo da animação em que as asas batem (o resto é planeio)
const ALCANCE_MIRA := 24.0  # m/s: o mais forte que um bicho joga o ovo de lado para acertar um carro

var _r: Recinto             # plataforma (bando da plataforma) — ou
var _sub: ComplexoSubida    # estrada (bando de um pedaço de pista): amostras _i0.._i1
var _terreno: Terreno
var _i0 := 0
var _i1 := 0
var _zs := PackedFloat32Array()   # metros de cada amostra desde o começo do pedaço
var _comp := 100.0          # comprimento da área (plataforma ou pedaço de estrada)
var _ult_i := 0             # amostra da estrada achada pelo último _local
var _dorme := false
var _qtd := 10
var _bichos: Array = []
var _ovos: Array = []       # caindo: {mi, p, v, eixo, giro, sombra, t0, dur}
var _restos: Array = []     # cacos voando e gema no piso: {no, t, dur, v, eixo, giro, mat}
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _intervalo := 4.5
var _efeito := 5.0
var _raio := 4.0
var _malha_ovo: ArrayMesh
var _malha_caco: SphereMesh
var _mat_ovo: ShaderMaterial
var _mat_gema: StandardMaterial3D
var _log := false
var _custo := [0, 0, 0]
var _ruido_poca: NoiseTexture2D
var _sombra_sh: Shader
var _poca_sh: Shader
var _gente := true          # há carro perto da plataforma? (sem ninguém por perto os bichos só voam, não soltam ovos)
var _gente_t := 0.0
var _sem_ovos := OS.get_environment("TSC_PTERO_SEM_OVOS") != ""   # medição: só os bichos voando
var _sem_mira := 9          # ovos ao acaso entre um ovo mirado e o seguinte (0 = todos mirados; negativo = nunca mira)
var _ao_acaso := 0          # ovos ao acaso soltos desde o último mirado
var _gotas: Array[GPUParticles3D] = []
var _gota_i := 0


func montar(r: Recinto, cfg: Dictionary) -> void:
	_r = r
	_comp = r.comprimento
	_rng.seed = 9041 + int(r.origem.x) * 7 + int(r.origem.z)
	_montar(cfg)
	if _log:
		print("[PTERO] %d pterossauros sobre a plataforma em %s" % [_bichos.size(), str(r.pa(r.comprimento * 0.5, 0.0, r.piso_y).snapped(Vector3.ONE))])


## Bando por cima de um pedaço de estrada: cfg.trecho, cfg.de e cfg.ate (metros no trecho).
func montar_estrada(sub: ComplexoSubida, terreno: Terreno, cfg: Dictionary) -> void:
	_i0 = sub.indice_trecho(str(cfg.get("trecho", "A")), float(cfg.get("de", 0.0)))
	_i1 = sub.indice_trecho(str(cfg.get("trecho", "A")), float(cfg.get("ate", 0.0)))
	if _i0 < 0 or _i1 - _i0 < 8:
		push_warning("Pterossauros da estrada: pedaço inválido %s" % str(cfg))
		return
	_sub = sub
	_terreno = terreno
	for i in range(_i0, _i1 + 1):
		_zs.append(sub.progresso_amostra(i) - sub.progresso_amostra(_i0))
	_comp = _zs[_zs.size() - 1]
	_rng.seed = 5113 + _i0 * 13 + _i1
	_montar(cfg)
	if _log:
		print("[PTERO] %d pterossauros sobre a estrada, trecho %s de %s a %s (%.0f m), meio em %s" % [_bichos.size(), str(cfg.get("trecho")), str(cfg.get("de")), str(cfg.get("ate")), _comp, str(_ponto(_comp * 0.5, 0.0, 0.0).snapped(Vector3.ONE))])


func _montar(cfg: Dictionary) -> void:
	_log = OS.get_environment("TSC_PTERO_LOG") != ""
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not ResourceLoader.exists(CENA):
		push_warning("Pterossauros: falta %s (rodar tools/extinction_day/processar_modelos.py -- pterossauro e importar)" % CENA)
		return
	var cena: PackedScene = load(CENA)
	_intervalo = float(cfg.get("intervalo_s", 4.5))
	_efeito = float(cfg.get("efeito_s", 5.0))
	_raio = float(cfg.get("raio", 4.0))
	_sem_mira = int(cfg.get("sem_mira", 9))
	_malha_ovo = AlvoDino._malha_ovo(false)
	_mat_ovo = ShaderMaterial.new()
	_mat_ovo.shader = load("res://shaders/alvo_ninho.gdshader")
	_mat_ovo.set_shader_parameter("ruido", Terreno._textura_ruido(0.08, 3, 17))
	_mat_ovo.set_shader_parameter("modo_ovo", 1)
	_mat_ovo.set_shader_parameter("luzes", 0.0)
	# UMA textura de ruído para todas as poças (o mesmo ruído largo da poça de gosma). Terreno._textura_ruido
	# gera uma textura nova de 512 px a cada chamada: feita a cada ovo, derrubava o jogo de ~35 para ~10 fps
	_ruido_poca = Terreno._textura_ruido(0.02, 3, 431)
	_sombra_sh = load("res://shaders/ovo_sombra.gdshader")
	_poca_sh = load("res://shaders/gosma_poca.gdshader")
	_malha_caco = SphereMesh.new()
	_malha_caco.radius = 0.5
	_malha_caco.height = 0.22
	_malha_caco.is_hemisphere = true
	_malha_caco.radial_segments = 5
	_malha_caco.rings = 2
	_mat_gema = StandardMaterial3D.new()
	_mat_gema.albedo_color = Color(0.96, 0.66, 0.08)
	_mat_gema.roughness = 0.1
	_mat_gema.emission_enabled = true
	_mat_gema.emission = Color(0.96, 0.66, 0.08)
	_mat_gema.emission_energy_multiplier = 0.25
	var qtd := int(cfg.get("quantidade", 10))
	_qtd = qtd
	var env := float(cfg.get("envergadura", 11.0))
	var alt: Array = cfg.get("altura", [15.0, 27.0])
	# Cada um na sua altura (não se atravessam), sorteadas entre os bichos
	var niveis: Array = []
	for k in qtd:
		niveis.append(lerpf(float(alt[0]), float(alt[1]), (k + 0.5) / qtd))
	for k in range(qtd - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var tmp: float = niveis[k]
		niveis[k] = niveis[j]
		niveis[j] = tmp
	for k in qtd:
		_criar(cena, k, env, float(niveis[k]))


# ------------------------------------------------------------------ a área (plataforma ou pedaço de estrada)

## Ponto a `x` m do começo da área, `lat` m para o lado e `alt` m acima do piso dali.
func _ponto(x: float, lat: float, alt: float) -> Vector3:
	if _sub == null:
		return _r.pa(x, lat, _r.piso_y + alt)
	var j := clampi(_zs.bsearch(x) - 1, 0, _zs.size() - 2)
	var u := (x - _zs[j]) / maxf(_zs[j + 1] - _zs[j], 0.01)   # fora das pontas segue reto
	var p := _sub.amostra(_i0 + j).lerp(_sub.amostra(_i0 + j + 1), u)
	return p + _sub.lateral_em(_i0 + j + (1 if u > 0.5 else 0)) * lat + Vector3.UP * alt


## Rumo no mundo de um passo (ao longo, de lado) dado no ponto `x` da área.
func _rumo(x: float, dq: Vector2) -> Vector3:
	if _sub == null:
		return (_r.frente * dq.x + _r.lateral * dq.y).normalized()
	var i := _i0 + clampi(_zs.bsearch(x), 0, _zs.size() - 1)
	var t := _sub.tangente_em(i)
	var l := _sub.lateral_em(i)
	return (Vector3(t.x, 0.0, t.z).normalized() * dq.x + Vector3(l.x, 0.0, l.z).normalized() * dq.y).normalized()


## `p` nas medidas da área: (metros ao longo, metros de lado, altura do piso ali).
func _local(p: Vector3) -> Vector3:
	if _sub == null:
		var l: Vector2 = _r.local(p)
		return Vector3(l.x, l.y, _r.piso_y)
	# Amostra mais perto: de 8 em 8 e depois uma a uma em volta
	var ph := Vector2(p.x, p.z)
	var melhor := 0
	var menor := INF
	var n := _zs.size()
	for j in range(0, n, 8):
		var a := _sub.amostra(_i0 + j)
		var d := ph.distance_squared_to(Vector2(a.x, a.z))
		if d < menor:
			menor = d
			melhor = j
	for j in range(maxi(melhor - 7, 0), mini(melhor + 8, n)):
		var a := _sub.amostra(_i0 + j)
		var d := ph.distance_squared_to(Vector2(a.x, a.z))
		if d < menor:
			menor = d
			melhor = j
	_ult_i = _i0 + melhor
	var q := p - _sub.amostra(_ult_i)
	var t := _sub.tangente_em(_ult_i)
	var ao_longo := q.x * t.x + q.z * t.z
	return Vector3(_zs[melhor] + ao_longo, q.dot(_sub.lateral_em(_ult_i)), _sub.amostra(_ult_i).y + t.y * ao_longo)


## Meia largura da área onde o ovo cai (a plataforma, ou a pista no ponto do último _local).
func _meia() -> float:
	return _r.largura_arena * 0.5 if _sub == null else _sub.largura_em(_ult_i) * 0.5


## `l` (de _local) está por cima da área, com `folga` m para dentro das bordas?
func _sobre_piso(l: Vector3, folga: float) -> bool:
	if _sub != null:
		folga = minf(folga, 1.0)   # a pista é estreita: com a folga da plataforma só valeria o miolo dela
	return l.x > folga and l.x < _comp - folga and absf(l.y) < _meia() - folga


## Metros de piso em volta de `p` (até a beira de um buraco, ou da pista); <= 0 = sem piso embaixo.
func _folga_piso(p: Vector3) -> float:
	if _sub == null:
		return -1.0 if _r.sem_piso else float(_r.buraco_mais_perto(p).get("distancia", 100.0))
	var l := _local(p)
	return -1.0 if _sub.em_vao(_ult_i) or l.x < 0.0 or l.x > _comp else _meia() - absf(l.y)


## Como deitar no piso uma coisa chata (sombra, poça): na estrada, acompanha a rampa.
func _base_piso(p: Vector3) -> Basis:
	if _sub == null:
		return Basis.IDENTITY
	_local(p)
	var n := _sub.normal_em(_ult_i)
	var l := _sub.lateral_em(_ult_i)
	return Basis(l, n, l.cross(n)).orthonormalized()


# ------------------------------------------------------------------ montagem do bicho

static func _osso(esq: Skeleton3D, comeco: String) -> int:
	for b in esq.get_bone_count():
		if esq.get_bone_name(b).to_lower().begins_with(comeco):
			return b
	return -1


## Deixa a animação do arquivo em ciclo e só com os ossos (as trilhas de nó tirariam o bicho do lugar).
static func _preparar_anim(anim: AnimationPlayer) -> String:
	for n in anim.get_animation_list():
		if n == "RESET":
			continue
		var a := anim.get_animation(n)
		if not a.has_meta("tsc"):
			a.loop_mode = Animation.LOOP_LINEAR
			# Das 375 trilhas ficam as de rotação e a de posição da bacia (o sobe-e-desce do corpo): escala e as
			# outras posições não mudam na animação e só custavam tempo a cada quadro, em cada um dos bichos
			for i in range(a.get_track_count() - 1, -1, -1):
				var caminho := a.track_get_path(i)
				var tipo := a.track_get_type(i)
				var fica := caminho.get_subname_count() > 0 and (tipo == Animation.TYPE_ROTATION_3D
					or (tipo == Animation.TYPE_POSITION_3D and str(caminho.get_subname(0)).to_lower().begins_with("center")))
				if not fica:
					a.remove_track(i)
			a.set_meta("tsc", true)
		return n
	return ""


func _criar(cena: PackedScene, k: int, env: float, nivel: float) -> void:
	var raiz := Node3D.new()   # frente = -Z, corpo na origem
	raiz.name = "Ptero%d" % k
	add_child(raiz)
	var giro := Node3D.new()
	raiz.add_child(giro)
	var modelo: Node3D = cena.instantiate()
	giro.add_child(modelo)
	var esq: Skeleton3D = null
	for s in modelo.find_children("*", "Skeleton3D", true, false):
		esq = s
		break
	var anim: AnimationPlayer = null
	for a in modelo.find_children("*", "AnimationPlayer", true, false):
		anim = a
		break
	if esq == null or anim == null:
		push_warning("Pterossauros: o modelo veio sem esqueleto ou sem animação")
		raiz.queue_free()
		return
	for mi in modelo.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 900.0
		(mi as MeshInstance3D).visibility_range_end_margin = 100.0
		(mi as MeshInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		(mi as MeshInstance3D).extra_cull_margin = 40.0   # as asas saem longe da caixa da pose de repouso
		# Sem sombra no chão (teste do dono, 2026-10-04: aliviar a placa); TSC_PTERO_SOMBRA=1 liga de volta para comparar
		if OS.get_environment("TSC_PTERO_SOMBRA") == "":
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var nome := _preparar_anim(anim)
	var dur := anim.get_animation(nome).length
	anim.playback_default_blend_time = 0.0
	anim.play(nome)
	anim.seek(0.0, true)
	# Orientação pela anatomia (qualquer que seja a do arquivo): frente = da bacia para o peito,
	# esquerda = da ponta da asa direita para a da esquerda. Tamanho pela envergadura.
	var o_centro := _osso(esq, "center")
	var o_peito := _osso(esq, "chest")
	var o_pe := _osso(esq, "lwing03")
	var o_pd := _osso(esq, "rwing03")
	var xf_e := DinosParque._xf_ate(esq, modelo)
	var p_centro := xf_e * esq.get_bone_global_rest(o_centro).origin
	var esquerda := xf_e * esq.get_bone_global_rest(o_pe).origin - xf_e * esq.get_bone_global_rest(o_pd).origin
	var env_modelo := maxf(esquerda.length(), 0.001)
	esquerda = esquerda.normalized()
	var frente := xf_e * esq.get_bone_global_rest(o_peito).origin - p_centro
	frente = (frente - esquerda * frente.dot(esquerda)).normalized()
	var cima := frente.cross(esquerda).normalized()
	var esc := env / env_modelo
	giro.basis = Basis(-esquerda, cima, -frente).transposed().scaled(Vector3.ONE * esc)
	# O corpo na animação fica longe da origem do esqueleto: centra pelo osso da bacia no começo do ciclo
	var corpo := xf_e * esq.get_bone_global_pose(o_centro).origin
	giro.position = -(giro.basis * corpo)
	anim.speed_scale = 0.0 if OS.get_environment("TSC_PTERO_SEM_ANIM") != "" else _rng.randf_range(0.9, 1.15)
	if OS.get_environment("TSC_PTERO_SEM_ANIM") == "2":
		anim.active = false
	anim.seek(_rng.randf() * dur, true)
	var ovo := MeshInstance3D.new()
	ovo.mesh = _malha_ovo
	ovo.material_override = _mat_ovo
	ovo.visible = false
	add_child(ovo)
	# Volta em elipse por cima da plataforma, cada um com a sua (centro, tamanho, rumo e sentido)
	# Na estrada: espalhados pelo pedaço inteiro, em voltas compridas ao longo da pista e pouco para os lados
	var na_estrada := _sub != null
	var lado := 0.0 if na_estrada else minf(_r.comprimento, _r.largura_arena)
	var centro := Vector2(_comp * (k + _rng.randf_range(0.2, 0.8)) / maxf(_qtd, 1.0), _rng.randf_range(-3.0, 3.0)) if na_estrada \
		else Vector2(_r.comprimento * _rng.randf_range(0.3, 0.7), _r.largura_arena * 0.5 * _rng.randf_range(-0.3, 0.3))
	var b := {"raiz": raiz, "esq": esq, "anim": anim, "dur": dur, "ovo": ovo, "esc": esc,
		"bacia": _osso(esq, "pelvis"), "pes": [_osso(esq, "lankle"), _osso(esq, "rankle")],
		"c": centro,
		"a": minf(_comp * 0.4, _rng.randf_range(28.0, 60.0)) if na_estrada else lado * _rng.randf_range(0.22, 0.42),
		"b": _rng.randf_range(5.0, 11.0) if na_estrada else lado * _rng.randf_range(0.13, 0.26),
		"giro": _rng.randf_range(-0.12, 0.12) if na_estrada else _rng.randf() * TAU, "sentido": 1.0 if _rng.randf() < 0.5 else -1.0, "vel": _rng.randf_range(13.0, 18.0),
		"ang": _rng.randf() * TAU, "y0": nivel, "rol": 0.0, "dir": Vector3.ZERO, "y": 0.0,
		"prox": 2.0 + _rng.randf() * _intervalo, "fixo": k == 0 and OS.get_environment("TSC_PTERO_FIXO") != ""}
	_bichos.append(b)
	if _log and k == 0:
		print("[PTERO] envergadura no arquivo %.2f → escala %.3f; corpo em %s; ossos bacia %d pés %s; animação '%s' %.2f s" % [env_modelo, esc, str(corpo), int(b.bacia), str(b.pes), nome, dur])


# ------------------------------------------------------------------ voo

## Altura dentro do ciclo da animação (0..1): sobe enquanto as asas batem, desce no planeio.
func _subida(fase: float) -> float:
	var a: float = BATE[0]
	var f: float = BATE[1]
	if fase >= a and fase <= f:
		return smoothstep(a, f, fase)
	var u := (fase - f) / (1.0 - f + a) if fase > f else (fase + 1.0 - f) / (1.0 - f + a)
	return 1.0 - smoothstep(0.0, 1.0, u)


func _voar(b: Dictionary, delta: float) -> void:
	var raiz: Node3D = b.raiz
	var anim: AnimationPlayer = b.anim
	var vel: float = b.vel
	var p: Vector3
	var dir: Vector3
	if bool(b.fixo):
		p = _ponto(_comp * 0.5, 0.0, 7.0)
		dir = _rumo(_comp * 0.5, Vector2(0.0, 1.0))
	else:
		var ang: float = b.ang
		var a: float = b.a
		var bb: float = b.b
		ang += delta * vel / maxf(Vector2(-sin(ang) * a, cos(ang) * bb).length(), 1.0) * float(b.sentido)
		b.ang = ang
		var q: Vector2 = (b.c as Vector2) + Vector2(cos(ang) * a, sin(ang) * bb).rotated(float(b.giro))
		var dq := (Vector2(-sin(ang) * a, cos(ang) * bb).rotated(float(b.giro)) * float(b.sentido)).normalized()
		p = _ponto(q.x, q.y, float(b.y0) + SOBE * _subida(fmod(anim.current_animation_position / float(b.dur), 1.0)))
		dir = _rumo(q.x, dq)
	# Inclina para dentro da curva (o quanto a curva pede nessa velocidade) e acompanha a subida e a descida
	var dir_ant: Vector3 = b.dir
	var rol_alvo := 0.0
	var vy := 0.0
	if dir_ant != Vector3.ZERO and delta > 0.0:
		rol_alvo = clampf(atan((dir - dir_ant).dot(dir.cross(Vector3.UP)) / delta * vel / 9.8), -0.7, 0.7)
		vy = clampf((p.y - float(b.y)) / delta, -4.0, 4.0)
	b.dir = dir
	b.y = p.y
	b.rol = lerpf(float(b.rol), rol_alvo, clampf(delta * 2.5, 0.0, 1.0))
	raiz.global_transform = Transform3D(Basis.looking_at(Vector3(dir.x * vel, vy, dir.z * vel).normalized(), Vector3.UP) * Basis(Vector3.FORWARD, float(b.rol)), p)
	# Ovo: aparece embaixo do corpo, desce até as garras e cai. Só solta com piso (ou poço) embaixo de onde ele vai cair
	var ovo: MeshInstance3D = b.ovo
	if not _gente or _sem_ovos:
		b.prox = maxf(float(b.prox), _t + PREPARO + 0.2)
	var tau := _t - float(b.prox)
	if tau < -PREPARO:
		ovo.visible = false
		return
	var esq: Skeleton3D = b.esq
	var bacia := esq.global_transform * esq.get_bone_global_pose(int(b.bacia)).origin
	var pes := (esq.global_transform * esq.get_bone_global_pose(int(b.pes[0])).origin + esq.global_transform * esq.get_bone_global_pose(int(b.pes[1])).origin) * 0.5
	var u := smoothstep(0.0, 1.0, clampf((tau + PREPARO) / (PREPARO * 0.75), 0.0, 1.0))
	var cima := raiz.global_transform.basis.y
	var p_ovo := bacia.lerp(pes, u) - cima * (0.25 + 0.75 * u) * ESC_OVO * 1.5
	ovo.visible = true
	ovo.global_transform = Transform3D(raiz.global_transform.basis.orthonormalized().scaled(Vector3.ONE * ESC_OVO * lerpf(0.25, 1.0, u)), p_ovo)
	if tau < 0.0:
		return
	var v_ovo := Vector3(dir.x, 0.0, dir.z) * (0.0 if bool(b.fixo) else vel * 0.25) + Vector3.UP * (vy - 1.0)
	# Pedido do dono: a cada `sem_mira` ovos soltos ao acaso (4), o seguinte vai MIRADO num carro. Se na
	# hora não há carro ao alcance deste bicho, o ovo sai ao acaso e a vez do mirado fica para o próximo
	var mirado := false
	if _sem_mira >= 0 and _ao_acaso >= _sem_mira and not bool(b.fixo):
		var m := _mirar(p_ovo, v_ovo.y)
		if not m.is_empty():
			v_ovo = m.v
			mirado = true
			if _log:
				print("[PTERO] ovo MIRADO em %s em %.1f s (depois de %d ao acaso)" % [(m.carro as Veiculo).name, _t, _ao_acaso])
	var cai := _queda(p_ovo, v_ovo)
	if not mirado and not _sobre_piso(_local(p_ovo + Vector3(v_ovo.x, 0.0, v_ovo.z) * cai), 3.0):
		b.prox = _t + 0.25   # segura o ovo até estar por cima da plataforma
		return
	_ao_acaso = 0 if mirado else _ao_acaso + 1
	b.prox = _t + PREPARO + _intervalo * _rng.randf_range(0.7, 1.35)
	ovo.visible = false
	_soltar(p_ovo, v_ovo, ovo.global_transform.basis, cai)


## Ovo mirado: escolhe o carro da plataforma (no piso ou no ar por cima dela) que este bicho alcança com
## o arremesso mais fraco e devolve {v: velocidade do ovo para cair onde o carro VAI estar, carro}.
## Vazio se nenhum está ao alcance (o ovo sai de lado a no máximo ALCANCE_MIRA m/s).
func _mirar(p: Vector3, vy: float) -> Dictionary:
	var melhor := {}
	var menor := ALCANCE_MIRA
	for no_v in get_tree().get_nodes_in_group("veiculo"):
		var c := no_v as Veiculo
		if c == null or c.eliminado or c.fantasma():
			continue
		var pc := c.global_position
		var lc := _local(pc)
		if not _sobre_piso(lc, -2.0) or pc.y < lc.z - 6.0 or pc.y > p.y - 4.0:
			continue
		# Tempo de queda até a altura do carro e onde ele vai estar nesse instante
		var t := (vy + sqrt(vy * vy + 2.0 * G_OVO * (p.y - pc.y - 0.7))) / G_OVO
		var vc := c.linear_velocity
		var onde := pc + Vector3(vc.x, 0.0, vc.z) * t
		var vh := Vector3(onde.x - p.x, 0.0, onde.z - p.z) / maxf(t, 0.1)
		if vh.length() < menor:
			menor = vh.length()
			melhor = {"v": vh + Vector3.UP * vy, "carro": c}
	return melhor


## Segundos até o ovo chegar à altura do piso (na estrada, o piso de onde ele vai cair: a pista sobe).
func _queda(p: Vector3, v: Vector3) -> float:
	var t := (v.y + sqrt(v.y * v.y + 2.0 * G_OVO * maxf(p.y - _local(p).z, 0.0))) / G_OVO
	if _sub != null:
		t = (v.y + sqrt(v.y * v.y + 2.0 * G_OVO * maxf(p.y - _local(p + Vector3(v.x, 0.0, v.z) * t).z, 0.0))) / G_OVO
	return t


# ------------------------------------------------------------------ ovos

func _soltar(p: Vector3, v: Vector3, base: Basis, cai: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _malha_ovo
	mi.material_override = _mat_ovo
	add_child(mi)
	mi.global_transform = Transform3D(base, p)
	var sombra: MeshInstance3D = null
	var chao := p + Vector3(v.x, 0.0, v.z) * cai
	var folga := _folga_piso(chao)
	if folga > 0.0:
		sombra = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		# (na estrada a sombra não passa da beira da pista: nada no ar)
		pm.size = Vector2.ONE * (_raio if _sub == null else clampf(folga, 1.0, _raio)) * 2.0
		sombra.mesh = pm
		var ms := ShaderMaterial.new()
		ms.shader = _sombra_sh
		sombra.material_override = ms
		sombra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sombra)
		sombra.global_transform = Transform3D(_base_piso(chao), Vector3(chao.x, _local(chao).z + 0.05, chao.z))
	_ovos.append({"mi": mi, "p": p, "v": v, "sombra": sombra, "t0": _t, "dur": maxf(cai, 0.1), "giro": _rng.randf_range(1.5, 4.0),
		"eixo": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1)).normalized()})
	if _log:
		print("[PTERO] ovo solto em %.1f s, de %.0f m de altura" % [_t, p.y - _local(p).z])


func _cair(delta: float) -> void:
	if _ovos.is_empty():
		return
	var carros := get_tree().get_nodes_in_group("veiculo")
	for i in range(_ovos.size() - 1, -1, -1):
		var o: Dictionary = _ovos[i]
		var v: Vector3 = o.v
		v.y -= G_OVO * delta
		var p: Vector3 = (o.p as Vector3) + v * delta
		o.v = v
		o.p = p
		var mi: MeshInstance3D = o.mi
		mi.global_position = p
		mi.rotate(o.eixo, float(o.giro) * delta)
		if o.sombra:
			((o.sombra as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("quanto", clampf((_t - float(o.t0)) / float(o.dur), 0.0, 1.0))
		# Em cheio num carro (no chão ou no ar)
		var acertou: Veiculo = null
		for no_v in carros:
			var c := no_v as Veiculo
			if c == null or c.eliminado or c.fantasma():
				continue
			if (c.global_position + Vector3.UP * 0.7).distance_to(p) < 2.3 + ESC_OVO:
				acertou = c
				break
		var l := _local(p)
		# (na estrada, ovo que já passou 6 m para baixo da pista não estoura mais nela: caiu por fora)
		var no_piso: bool = p.y <= l.z + ESC_OVO * 1.2 and (_sub == null or p.y > l.z - 6.0) and _sobre_piso(l, 0.0) and _folga_piso(p) > 0.0
		if acertou:
			_melar(acertou, "em cheio")
			_estourar(o, p, false)
		elif no_piso:
			# Estoura no piso e respinga em quem está perto
			for no_v in carros:
				var c := no_v as Veiculo
				if c == null or c.eliminado or c.fantasma():
					continue
				var d := c.global_position - p
				if Vector2(d.x, d.z).length() < _raio and absf(d.y) < 3.0:
					_melar(c, "respingo")
			_estourar(o, Vector3(p.x, l.z, p.z), true)
		elif _sub != null and _terreno != null and p.y <= _terreno.altura_em(p.x, p.z) + ESC_OVO:
			_estourar(o, p, false)   # errou a pista: estoura no chão lá embaixo
		elif p.y > l.z - (16.0 if _sub == null else 150.0):
			continue
		# Acabou (estourou, ou sumiu num buraco / no poço de lava)
		mi.queue_free()
		if o.sombra:
			(o.sombra as Node).queue_free()
		_ovos.remove_at(i)


func _melar(c: Veiculo, como: String) -> void:
	c.ovo(_efeito)
	if _log:
		print("[PTERO] ovo acertou %s (%s) em %.1f s" % [c.name, como, _t])


## Casca em cacos, gema espirrando e, no piso, a poça de gema (some sozinha).
func _estourar(o: Dictionary, p: Vector3, no_piso: bool) -> void:
	var v0: Vector3 = o.v
	for k in 6:
		var ang := TAU * k / 6.0 + _rng.randf_range(-0.25, 0.25)
		var mi := MeshInstance3D.new()
		mi.mesh = _malha_caco
		mi.material_override = _mat_ovo
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_transform = Transform3D(Basis(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(), _rng.randf() * TAU).scaled(Vector3(_rng.randf_range(0.5, 1.3), 1.0, _rng.randf_range(0.5, 1.3)) * ESC_OVO),
			p + Vector3(cos(ang) * 0.4, 0.3 + _rng.randf() * 0.5, sin(ang) * 0.4) * ESC_OVO)
		_restos.append({"no": mi, "t": 0.0, "dur": _rng.randf_range(1.2, 1.8), "giro": _rng.randf_range(4.0, 11.0), "chao": p.y + 0.06 if no_piso else -1.0e9,
			"eixo": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized(),
			"v": Vector3(cos(ang), 0.0, sin(ang)) * _rng.randf_range(2.5, 6.5) + Vector3.UP * _rng.randf_range(3.0, 7.5) + Vector3(v0.x, 0.0, v0.z) * 0.5})
	# Gema espirrando: meia dúzia de emissores que se revezam (criar um a cada ovo custava caro)
	if _gotas.size() < 6:
		var nova := GPUParticles3D.new()
		nova.amount = 34
		nova.lifetime = 0.9
		nova.one_shot = true
		nova.explosiveness = 0.95
		nova.local_coords = false
		nova.emitting = false
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3.UP
		pm.spread = 75.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 8.5
		pm.gravity = Vector3(0.0, -14.0, 0.0)
		pm.scale_min = 0.6
		pm.scale_max = 1.6
		nova.process_material = pm
		var gota := SphereMesh.new()
		gota.radius = 0.09
		gota.height = 0.3
		gota.radial_segments = 8
		gota.rings = 4
		gota.material = _mat_gema
		nova.draw_pass_1 = gota
		add_child(nova)
		_gotas.append(nova)
	var gotas: GPUParticles3D = _gotas[_gota_i % _gotas.size()]
	_gota_i += 1
	gotas.global_position = p + Vector3.UP * 0.3
	gotas.restart()
	Audio.tocar("efeitos/agua_splash_", p, -2.0, 1.5, 0.1, "Efeitos", 45.0)
	if not no_piso:
		return
	# A poça não pode ficar por cima de um buraco (nada flutuando): perto da beira ela é menor
	var folga := _folga_piso(p)
	if folga < 0.8:
		return
	var poca := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2.ONE * minf(_raio * 2.3, folga * 2.0)
	poca.mesh = plano
	var mat := ShaderMaterial.new()
	mat.shader = _poca_sh
	mat.set_shader_parameter("ruido", _ruido_poca)
	mat.set_shader_parameter("semente", _rng.randf() * 10.0)
	mat.set_shader_parameter("cor_borda", Color(0.97, 0.96, 0.9))   # clara
	mat.set_shader_parameter("cor_meio", Color(0.98, 0.68, 0.06))   # gema
	poca.material_override = mat
	poca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(poca)
	poca.global_transform = Transform3D(_base_piso(p) * Basis(Vector3.UP, _rng.randf() * TAU), p + Vector3.UP * 0.045)
	_restos.append({"no": poca, "t": 0.0, "dur": 5.0, "mat": mat})


func _atualizar_restos(delta: float) -> void:
	for i in range(_restos.size() - 1, -1, -1):
		var r: Dictionary = _restos[i]
		r.t = float(r.t) + delta
		var no: Node3D = r.no
		if float(r.t) >= float(r.dur):
			no.queue_free()
			_restos.remove_at(i)
			continue
		if r.has("mat"):
			# Poça de gema: abre depressa, fica e encolhe pelas bordas no fim
			(r.mat as ShaderMaterial).set_shader_parameter("quanto", minf(smoothstep(0.0, 0.45, float(r.t)), smoothstep(0.0, 1.3, float(r.dur) - float(r.t))))
			continue
		var v: Vector3 = r.v
		if no.global_position.y <= float(r.chao) and v.y <= 0.0:
			continue   # caco parado no piso
		v.y -= 14.0 * delta
		r.v = v
		no.global_position += v * delta
		no.rotate(r.eixo, float(r.giro) * delta)
		no.scale = no.scale * (1.0 if float(r.dur) - float(r.t) > 0.4 else 0.9)


func _process(delta: float) -> void:
	if (_r == null and _sub == null) or _bichos.is_empty():
		return
	_t += delta
	# Duas vezes por segundo: há algum carro a menos de 220 m da plataforma? Sem ninguém, não cai ovo
	if _t >= _gente_t:
		_gente_t = _t + 0.5
		var meio := _ponto(_comp * 0.5, 0.0, 0.0)
		var alcance := 220.0 if _sub == null else _comp * 0.5 + 180.0
		_gente = false
		for no_v in get_tree().get_nodes_in_group("veiculo"):
			var c := no_v as Veiculo
			if c and not c.eliminado and Vector2(c.global_position.x - meio.x, c.global_position.z - meio.z).length() < alcance:
				_gente = true
				break
		# O bando da estrada dorme (some, animação parada) com a câmera longe e ninguém por perto: são
		# esqueletos a mais animando o tempo todo, além dos da plataforma
		if _sub != null:
			var cam := get_viewport().get_camera_3d()
			var dorme: bool = not _gente and _ovos.is_empty() and cam != null and cam.global_position.distance_to(meio) > _comp * 0.5 + 520.0
			if dorme != _dorme:
				_dorme = dorme
				for b: Dictionary in _bichos:
					(b.raiz as Node3D).visible = not dorme
					if dorme:
						(b.anim as AnimationPlayer).pause()
					else:
						(b.anim as AnimationPlayer).play()
	if _dorme:
		_atualizar_restos(delta)
		return
	var t0 := Time.get_ticks_usec()
	for b: Dictionary in _bichos:
		_voar(b, delta)
	var t1 := Time.get_ticks_usec()
	_cair(delta)
	_atualizar_restos(delta)
	if _log:
		_custo[0] += t1 - t0
		_custo[1] += Time.get_ticks_usec() - t1
		_custo[2] += 1
		if _custo[2] >= 60:
			print("[PTERO] custo por quadro: voo %.2f ms, ovos %.2f ms; ovos caindo %d, restos %d" % [_custo[0] / 60000.0, _custo[1] / 60000.0, _ovos.size(), _restos.size()])
			_custo = [0, 0, 0]
