class_name PilotoBot
extends Node
## Piloto automático dos rivais: espera um pouco na plataforma, desce acelerando,
## pode usar nitro e ejetor na saída, abre o paraquedas perto do ápice e plana até o alvo
## controlando a razão de planeio. Cada etapa sorteia habilidade, mira e agressividade, moldadas
## pela personalidade do bot (fixa na partida) e pela meta do mapa.
##
## Agressividade (jogo.json → bots.agressividade, por fase): o bot caça carros de OUTRAS equipes.
## - Na arena: empurra rivais que estão perto de um buraco na direção dele (sem cair junto) e
##   dá trombadas no caminho até o portão.
## - Na descida (sem guarda-corpo): encosta de lado em quem está perto para jogar para fora.
## - No ar: mergulha em cima do velame de um rival mais baixo (o velame murcha).
## - Na chegada: mira em cima de quem já está parado numa zona boa do alvo, para tirá-lo de lá.

signal falou(bot: PilotoBot, texto: String)

var veiculo: Veiculo
var alvo: Alvo
var ativo := false
var rng := RandomNumberGenerator.new()
## Todos os veículos da partida (os de outras equipes são os alvos da agressividade).
var outros: Array = []

var _t := 0.0
var _espera := 0.0
var _usa_nitro := false
var _usa_ejetor := false
var _ejetou := false
var _mira := Vector3.ZERO
var _abre_com_vy := 0.0
var _falou_pouso := false
var _espiral := false
var _mergulho := false       # fechou o paraquedas de propósito para perder altura (reabre sozinho)
var _mergulho_pronto := 0.0  # próximo mergulho só depois deste instante (_t)
var _razao_abrir := 4.2      # razão distância/altura em que abre o paraquedas (varia por bot)
var agressividade := 0.0
var _lado_entrada := 1.0       # gravata: por qual ponta entrar quando chega bem de frente para o meio
var _no_eixo := false           # gravata: já está descendo pela linha do comprimento
var _rota: Array[Vector3] = []  # Canyon Combat: pontos de passagem pelo "S" entre os esporões do vale
var _rota_i := 0

# Ataque em andamento
var _vitima: Veiculo
var _ataque_t := 0.0          # tempo restante do ataque
var _pausa_ataque := 0.0      # descanso entre ataques
var _decidir_t := 0.0
# Carro preso (encostado na parede ou em outro carro): dá ré um pouco
var _parado_t := 0.0
var _re_t := 0.0
var _re_lado := 1.0
var _girar_t := 0.0          # cavalo de pau em andamento (tempo máximo restante)
var _tentativa := 0          # alterna giro no lugar e ré quando continua preso
var _faixa := 0.0             # Climb to Death: deslocamento lateral preferido na estrada (m)
# Ultrapassagem na estrada (Climb to Death): de que lado passa e por quanto tempo ainda tenta
var _ultrap_lado := 0.0
var _pistao_s := -1.0       # portão de granito em que o bot já escolheu o lado (Pharaoh's Climb)
var _pistao_lado := 1.0
var _pistao_vai := false
var _arm_id := -1           # armadilha (Serpent's Climb) em que o bot já escolheu a faixa
var _arm_lado := -1
const PASSOS_IA := 2
var _passo_ia := randi() % PASSOS_IA
var _dt_acum := 0.0
var _dt_ia := 1.0 / 60.0      # tempo entre duas rodadas do cérebro (no lugar do passo de física)
var _arm_plano_t := 0.0     # o plano de chegada na armadilha é refeito a cada ARM_PLANO_S (a busca é cara)
var _arm_vel_plano := -1.0
## Chegada na armadilha (bots.meta do mapa): armadilha_vel_max = velocidade máxima de passagem (m/s);
## armadilha_folga multiplica as folgas de tempo antes/depois (1 = prudente; menor = corajoso).
var _arm_vel_max := 19.0
var _arm_folga := 1.0
const ARM_PLANO_S := 0.12
var _vel_porta_v := -1.0     # velocidade de chegada na porta acelerada (calculada uma vez por etapa)
var _porta_lado := 1.0       # lado para onde o pulo da porta sai em diagonal (desvia do buraco da frente)
var _porta_mira := Vector3.ZERO
const TEMPO_PULO := 2.7        # s no ar depois do ejetor
const RE_VEL := 10.0           # m/s para costurar as placas de ré (uma de cada lado)
const ARM_VEL_MIN := 7.0
const ARM_ACEL := 5.0          # m/s² que o carro ganha até a armadilha (janela que não alcança não serve)
var _manobra_re := 0.0     # manobrando de ré para desvirar (de costas para a subida)
var _tem_freio := false     # regras.freios_instalados (S freia em vez de dar ré)
var _ultrap_t := 0.0
var _ultrap_decidir := 0.0
var _vontade_ultrapassar := 0.6
var _so_no_caminho := false   # Climb to Death: missão é subir; só empurra quem estiver no caminho
## Frozen Peak (mapa.subida.rota_pela_rampa): os pontos da rota de voo são seguidos no sentido do
## lançamento da rampa final (qualquer direção) e podem ter altura (janela de muralha).
## Bifurcações (Extinction Day): rota escolhida em cada uma (amostra da bifurcação → trecho do desvio; -1 = estrada)
var _rota_desvio := {}
## Defesa (pedido do dono): rival vindo de lado para me jogar para fora → pula com o ejetor (ele passa
## reto por baixo) ou freia para ele passar; quem me bate vira alvo do revide. bots.meta.defesa / revide.
var _defesa := 0.7
## Pouso devagar (bots.meta.pouso_lento, pedido do dono): no voo final o bot vem mais alto, segura a
## velocidade com S e chega no alvo devagar (rápido ele tocava e escorregava para fora).
var _pouso_lento := false
var _revide := 0.0
var _defesa_t := 0.0
var _freia_defesa := 0.0
var _rota_pela_rampa := false
## Esperteza (bots.niveis.<nível>.esperteza, 0 a 1; pedido do dono): chance de o bot resolver um desafio pelo
## jeito esperto em vez do prudente — pular com o ejetor por cima das placas de ré, pular um carro lento que
## fecha as duas faixas, esperar o ejetor recarregar antes de uma plataforma mais alta. Cai com o nível.
var _esperteza := 0.75
var _pulo_re_s := -1.0      # zona de placas de ré em que já decidiu (pula ou costura)
var _pulo_re := false
var _pulo_carro_t := 0.0    # descanso entre pulos por cima de carro
var _desistiu_pouso := false   # caiu da estrada e não alcança nenhum trecho: fecha o paraquedas e volta logo ao checkpoint

## Personalidade (sorteada uma vez por partida, jogo.json → bots.personalidades) e meta do mapa
## (bots.meta, cada mapa sobrepõe): juntas decidem quanto o bot ataca em cada momento, a pressa,
## o nitro/ejetor, a mira e quanto arrisca na velocidade.
var personalidade := ""
var _perso: Dictionary = {}
var _ataque_ctx := {"chao": 1.0, "ar": 1.0, "alvo": 1.0}

## Razão de planeio (distância / altura): abaixo de PLANEIO_ALVO desce mais (W); acima de
## PLANEIO_MAX estica com nitro.
## Nível do bot (Sessao.nivel_bots → jogo.json bots.niveis): aceleração lateral aceita nas curvas
## da estrada (m/s²), velocidade na plataforma dos buracos (m/s) e erro de volante.
var ACEL_LATERAL := 4.0
var VEL_PLATAFORMA := 10.0
var _erro_volante := 0.1
var _vel_estrada := 28.0
var _fase_erro := 0.0
const PLANEIO_ALVO := 6.0
const PLANEIO_MAX := 8.5
## Aprendido com as partidas gravadas do dono (gravacoes/): jogadores abrem o paraquedas já
## descendo, com razão distância/altura ~4-5 (os bots abriam no ápice, com ~3, e passavam do alvo);
## perto do alvo e alto demais, fecham e reabrem o paraquedas para perder altura (mergulho).
const RAZAO_ABRIR := 4.2
const ALTURA_ABRIR_MIN := 90.0
const RAZAO_MERGULHO := 2.6
const FINAL_DIST := 120.0       # alvo redondo: daqui para dentro é o final (S e mergulhos curtos)
const RAZAO_FINAL := 5.0        # no final, abaixo desta razão está alto demais (S anda ~5:1)

const FRASES_LARGADA := ["Vou no alvo 5!", "Bora, equipe!", "Hoje é zona 5.", "Segura essa!"]
const FRASES_PARAQUEDAS := ["Paraquedas aberto!", "Planando...", "Vento bom hoje."]
const FRASES_ATAQUE := ["Sai da frente!", "Vai pro buraco!", "Abre caminho!", "Essa é minha!"]
const FRASES_AR := ["Cortei teu paraquedas!", "Lá vou eu por cima!", "Tchau, velame!"]
const FRASES_ALVO := ["Desce daí!", "Esse lugar é meu!", "Vou te tirar do 5!"]


## Sorteia a personalidade da partida (peso = chance relativa). TSC_PERSONALIDADE=<id> força uma.
func escolher_personalidade() -> void:
	var lista: Dictionary = Config.valor("bots.personalidades", {})
	if lista.is_empty():
		return
	var forcada := OS.get_environment("TSC_PERSONALIDADE")
	if lista.has(forcada):
		personalidade = forcada
	else:
		var total := 0.0
		for id in lista:
			total += float(lista[id].get("peso", 1.0))
		var sorte := rng.randf() * total
		for id in lista:
			personalidade = id
			sorte -= float(lista[id].get("peso", 1.0))
			if sorte <= 0.0:
				break
	_perso = lista[personalidade]


func iniciar_etapa(p_alvo: Alvo) -> void:
	alvo = p_alvo
	_t = 0.0
	_ejetou = false
	_falou_pouso = false
	_espiral = false
	_vitima = null
	_ataque_t = 0.0
	_pausa_ataque = 0.0
	_parado_t = 0.0
	_re_t = 0.0
	_girar_t = 0.0
	_tentativa = 0
	_faixa = rng.randf_range(-2.6, 2.6)   # cada um prefere um lado da estrada (não andam todos no meio)
	_ultrap_t = 0.0
	_ultrap_lado = 0.0
	_desistiu_pouso = false
	_so_no_caminho = veiculo.complexo is ComplexoSubida
	_rota_desvio.clear()
	_defesa_t = 0.0
	_freia_defesa = 0.0
	_tem_freio = bool(Config.valor("regras.freios_instalados", false))
	var nivel: Dictionary = Config.valor("bots.niveis." + Sessao.nivel_bots, {})
	ACEL_LATERAL = float(nivel.get("acel_lateral", 4.0))
	VEL_PLATAFORMA = float(nivel.get("vel_plataforma", 10.0))
	_erro_volante = float(nivel.get("erro_volante", 0.1))
	_vel_estrada = float(nivel.get("vel_estrada", 28.0))
	_fase_erro = rng.randf() * TAU
	var meta: Dictionary = Config.valor("bots.meta", {})
	var at_p: Dictionary = _perso.get("ataques", {})
	var at_m: Dictionary = meta.get("ataques", {})
	for k in _ataque_ctx:
		_ataque_ctx[k] = float(at_p.get(k, 1.0)) * float(at_m.get(k, 1.0))
		_ataque_ctx[k] *= float(nivel.get("ataque_mult", 1.0))
	_defesa = float(meta.get("defesa", 0.7)) * float(nivel.get("defesa", 1.0))
	_revide = float(meta.get("revide", 0.0)) * float(nivel.get("revide_mult", 1.0))
	_esperteza = clampf(float(nivel.get("esperteza", 0.75)) * float(_perso.get("esperteza", 1.0)), 0.0, 1.0)
	_pulo_re_s = -1.0
	_pulo_carro_t = 0.0
	_pouso_lento = bool(meta.get("pouso_lento", false))
	_arm_vel_max = float(meta.get("armadilha_vel_max", 19.0))
	_arm_folga = float(meta.get("armadilha_folga", 1.0))
	_vel_porta_v = -1.0
	var vel_mult := float(_perso.get("velocidade", 1.0)) * float(meta.get("velocidade", 1.0))
	ACEL_LATERAL *= vel_mult
	VEL_PLATAFORMA *= vel_mult
	_vel_estrada *= vel_mult * rng.randf_range(0.93, 1.07)   # ritmo próprio: uns alcançam os outros
	_erro_volante *= float(_perso.get("erro_volante", 1.0))
	_vontade_ultrapassar = clampf(float(_perso.get("ultrapassa", 0.6)) * float(nivel.get("ultrapassa_mult", 1.0)), 0.0, 1.0)
	var faixa: Array = Config.valor("bots.agressividade", [0.1, 0.35])
	agressividade = clampf(rng.randf_range(float(faixa[0]), float(faixa[1])) * float(nivel.get("agressividade_mult", 1.0)), 0.0, 1.0)
	if OS.get_environment("TSC_AGRESSIVIDADE") != "":
		agressividade = float(OS.get_environment("TSC_AGRESSIVIDADE"))
	_espera = rng.randf_range(0.0, 0.8) if _arena() else (rng.randf_range(0.0, 6.0) if veiculo.complexo is ComplexoSubida else rng.randf_range(0.3, 5.0))
	_espera += float(nivel.get("espera_extra", 0.0)) * rng.randf_range(0.6, 1.4)
	_espera *= float(_perso.get("espera", 1.0)) * float(meta.get("espera", 1.0))
	_usa_nitro = rng.randf() < float(nivel.get("nitro", 0.65)) * float(_perso.get("nitro", 1.0))
	_usa_ejetor = rng.randf() < float(nivel.get("ejetor", 0.55)) * float(_perso.get("ejetor", 1.0))
	if OS.get_environment("TSC_EJETOR") != "":
		_usa_ejetor = OS.get_environment("TSC_EJETOR") == "1"
		_usa_nitro = false
	_abre_com_vy = rng.randf_range(-6.0, 6.0)
	_razao_abrir = RAZAO_ABRIR * rng.randf_range(0.9, 1.15)
	_mergulho = false
	var mira: Array = nivel.get("mira", [0.55, 0.97])
	var bonus := float(_perso.get("mira", 0.0))
	_mira = alvo.erro_mira(clampf(rng.randf_range(float(mira[0]), float(mira[1])) + bonus, 0.05, 1.0), rng)
	if alvo.raio_mira > 0.0 and veiculo.complexo:
		# Alvo em anel: mira no meio da faixa, de um dos lados de quem chega (o centro é o furo)
		_mira += veiculo.complexo.lateral * alvo.raio_mira * (1.0 if rng.randf() < 0.5 else -1.0)
	_rota_pela_rampa = bool(Config.valor("mapa.subida.rota_pela_rampa", false))
	_lado_entrada = 1.0 if rng.randf() < 0.5 else -1.0
	_no_eixo = false
	_rota = veiculo.terreno.rota_vale() if veiculo.terreno else ([] as Array[Vector3])
	# Rotas de voo alternativas da etapa (Frozen Peak E2: os dois furos grandes da muralha): cada bot sorteia uma
	if veiculo.terreno and not veiculo.terreno.rotas_alt.is_empty():
		var qual := rng.randi() % (veiculo.terreno.rotas_alt.size() + 1)
		if qual > 0:
			_rota.assign(veiculo.terreno.rotas_alt[qual - 1])
	if veiculo.terreno and veiculo.terreno.cidade and veiculo.complexo:
		# City Rush: costura as chicanes do corredor da equipe
		_rota = veiculo.terreno.cidade.rota(Vector2(veiculo.complexo.direcao.x, veiculo.complexo.direcao.z))
	_rota_i = 0
	if rng.randf() < 0.3:
		var frases: Array = _perso.get("frases", FRASES_LARGADA)
		_falar(frases[rng.randi() % frases.size()])


## Erro de volante do nível do bot: oscilação lenta (bots fáceis erram mais a direção).
func _oscilacao() -> float:
	return _erro_volante * (sin(_t * 0.9 + _fase_erro) + 0.5 * sin(_t * 2.3 + _fase_erro * 1.7))


func _falar(texto: String) -> void:
	falou.emit(self, texto)


func _arena() -> ComplexoArena:
	return veiculo.complexo as ComplexoArena if veiculo else null


func _rivais() -> Array:
	return outros.filter(func(o: Veiculo): return o != veiculo and o.indice_equipe != veiculo.indice_equipe and not o.eliminado and o.visible and not o.fantasma())


## Voltou num checkpoint (Climb to Death): recomeça a pilotagem do zero dali.
func ao_ressurgir() -> void:
	_desistiu_pouso = false
	_freia_defesa = 0.0
	_encerrar_ataque()
	_mergulho = false
	_ultrap_t = 0.0
	_parado_t = 0.0
	_re_t = 0.0
	_girar_t = 0.0
	_tentativa = 0
	_espiral = false


func _physics_process(delta: float) -> void:
	if not ativo or veiculo == null or veiculo.eliminado:
		return
	# O cérebro roda a cada PASSOS_IA passos de física (60 vezes por segundo), cada bot num passo diferente;
	# entre um e outro o carro mantém os comandos. A 120 por segundo era o script mais caro do jogo.
	_dt_acum += delta
	_passo_ia += 1
	if _passo_ia % PASSOS_IA != 0:
		return
	delta = _dt_acum
	_dt_acum = 0.0
	_dt_ia = delta
	_t += delta
	_ataque_t -= delta
	_pausa_ataque -= delta
	_decidir_t -= delta
	if _vitima and (_vitima.eliminado or _ataque_t <= 0.0):
		_encerrar_ataque()
	var e := veiculo.entrada
	e.acelerar = 0.0
	e.freiar = 0.0
	e.re = 0.0
	e.direcao = 0.0
	e.nitro = false
	# Looping: pé embaixo seguindo o eixo da fita, mesmo se as rodas descolarem um instante
	var sub_lp := veiculo.complexo as ComplexoSubida
	var lp := sub_lp.looping_em(veiculo.global_position, true) if sub_lp and not veiculo.paraquedas_aberto else null
	if lp:
		_dirigir_looping(e, lp)
		return
	match veiculo.estado:
		Veiculo.Estado.APOIADO:
			_dirigir(e, delta)
		Veiculo.Estado.BALISTICO:
			_balistico(e)
		Veiculo.Estado.PLANEIO:
			_planar(e)
	# Yeti no teto (Frozen Peak): a direção chega invertida; o bot leva um instante para perceber e
	# compensar (até lá o volante dele sai trocado, como o do jogador)
	if veiculo.direcao_invertida() and veiculo.tempo_invertido() > 0.7:
		e.direcao = -float(e.direcao)


func _encerrar_ataque() -> void:
	_vitima = null
	_ataque_t = 0.0
	_pausa_ataque = rng.randf_range(2.5, 5.0) * (1.5 - agressividade)


## Começa um ataque se a sorte deixar: agressividade x personalidade x meta do mapa naquele
## momento (`contexto` = "chao", "ar" ou "alvo"). `duracao` em segundos.
func _tentar_atacar(candidato: Veiculo, duracao: float, frases: Array, contexto: String) -> void:
	if candidato == null or _vitima or _pausa_ataque > 0.0 or _decidir_t > 0.0:
		return
	_decidir_t = 0.4
	if rng.randf() > clampf(agressividade * float(_ataque_ctx.get(contexto, 1.0)), 0.0, 1.0):
		return
	_vitima = candidato
	_ataque_t = duracao
	if rng.randf() < 0.35:
		_falar(frases[rng.randi() % frases.size()])


## Volante para apontar o carro para `destino` (positivo = direita). Devolve o erro de ângulo.
func _apontar(e: Dictionary, destino: Vector3, ganho := 2.2) -> float:
	var frente := -veiculo.global_transform.basis.z
	var para := destino - veiculo.global_position
	frente.y = 0.0
	para.y = 0.0
	if para.length() < 0.1:
		return 0.0
	var ang := atan2(frente.cross(para).y, frente.dot(para))
	e.direcao = clampf(-ang * ganho + _oscilacao(), -1.0, 1.0)
	return ang


# ------------------------------------------------------------------ no chão

## No looping o "para cima" é o do carro: mira o eixo da fita uns metros à frente e não tira o pé.
func _dirigir_looping(e: Dictionary, lp: Looping) -> void:
	var xf := veiculo.global_transform
	var j := lp.amostra_em(xf.origin, true)
	var frente := -xf.basis.z
	var para := lp.adiante(j, 14.0) - xf.origin
	var ang := atan2(frente.cross(para).dot(xf.basis.y), frente.dot(para))
	e.direcao = clampf(-ang * 2.2, -1.0, 1.0)
	e.acelerar = 1.0
	_parado_t = 0.0
	_encerrar_ataque()
	if OS.get_environment("TSC_LOOP_LOG") != "" and fmod(_t, 0.25) < _dt_ia:
		print("[LOOP] %-12s j=%3d v=%4.1f lat=%+.1f rodas=%d cima=%+.2f" % [veiculo.nome_piloto, j, veiculo.linear_velocity.length(),
			(xf.origin - lp.pts[j]).dot(lp.lado[j]), veiculo.rodas_no_chao, xf.basis.y.dot(lp.nrm[j])])


func _dirigir(e: Dictionary, delta: float) -> void:
	if veiculo.travado:
		# Sem freio: alterna o volante rapidamente para segurar o carro no alvo. Não para ao
		# quase parar: o zigue-zague demora a pegar força e o desnível do alvo faria o carro
		# voltar a escorregar; mantido o tempo todo, funciona como um freio de estacionamento.
		if veiculo.rodas_no_chao > 0:
			e.direcao = 1.0 if fmod(_t, 0.28) < 0.14 else -1.0
			# Puxa um pouco para o meio do alvo enquanto freia (senão escorrega para a borda e cai)
			if not alvo.gravata:
				var ang_c := _angulo_para(alvo.centro_superior())
				e.direcao = clampf(e.direcao - signf(ang_c) * clampf(absf(ang_c), 0.0, 1.0) * 0.35, -1.0, 1.0)
		if not _falou_pouso and rng.randf() < 0.02:
			_falou_pouso = true
		return
	if _t < _espera:
		e.freiar = 1.0
		return
	if _destravar(e, delta):
		return
	var sub := veiculo.complexo as ComplexoSubida
	if sub:
		_dirigir_subida(e, sub)
		return
	var arena := _arena()
	if arena and arena.local(veiculo.global_position).x < arena.comprimento + 24.0:
		_dirigir_arena(e, arena)
		return
	e.acelerar = 1.0
	var cx := veiculo.complexo
	var p := veiculo.global_position
	var xp := cx.x_perfil(p)
	var eixo := cx.ponto(xp, p.y)
	var desvio := (p - eixo).dot(cx.lateral)
	var erro_rumo := (-veiculo.global_transform.basis.z).dot(cx.lateral)
	var desvio_alvo := 0.0
	# Na descida: encosta de lado num rival próximo para jogá-lo para fora da pista
	if xp > cx.perfil.pontos[cx.perfil.indice_borda].x and xp < cx.perfil.pontos[cx.perfil.indice_base].x:
		if _vitima == null:
			var perto: Veiculo = null
			for r: Veiculo in _rivais():
				if r.complexo == cx and r.estado == Veiculo.Estado.APOIADO and r.global_position.distance_to(p) < 14.0:
					perto = r
			_tentar_atacar(perto, 3.0, FRASES_ATAQUE, "chao")
		if _vitima and _vitima.complexo == cx:
			var lat_v := (_vitima.global_position - cx.ponto(cx.x_perfil(_vitima.global_position), p.y)).dot(cx.lateral)
			desvio_alvo = clampf(lat_v, -cx.largura * 0.5 + 2.5, cx.largura * 0.5 - 2.5)
	e.direcao = clampf(-(desvio - desvio_alvo) * 0.12 - erro_rumo * 2.5, -1.0, 1.0)
	if _usa_nitro and xp > cx.perfil.pontos[cx.perfil.indice_base].x - 60.0:
		e.nitro = true
	if _usa_ejetor and not _ejetou and xp > cx.perfil.comprimento_horizontal - 4.0 and veiculo.ejetor_disponivel():
		_ejetou = true
		veiculo.pedir_ejetor()


## Arena: segue o mapa de custo até o portão; no caminho, caça rivais perto dos buracos.
func _dirigir_arena(e: Dictionary, arena) -> void:   # ComplexoArena ou Recinto
	var p := veiculo.global_position
	var destino: Vector3 = arena.rumo_saida(p)
	var velocidade := veiculo.linear_velocity.length()
	if _vitima == null:
		_tentar_atacar(_escolher_vitima_arena(arena), rng.randf_range(1.5, 3.0), FRASES_ATAQUE, "chao")
	var atacando := false
	if _vitima and arena.dentro_da_arena(_vitima.global_position):
		# Empurra a vítima na direção do perigo (buraco ou seta-armadilha) mais perto dela: mira um pouco além dela,
		# do lado do buraco. Aborta se o próprio carro estiver chegando na boca.
		var b: Dictionary = arena.perigo_mais_perto(_vitima.global_position)
		var alvo_p := _vitima.global_position + _vitima.linear_velocity * 0.3
		if not b.is_empty() and b.distancia < 14.0:
			var para_buraco: Vector3 = (b.centro - _vitima.global_position)
			para_buraco.y = 0.0
			alvo_p += para_buraco.normalized() * 2.5
		var meu: Dictionary = arena.buraco_mais_perto(p)
		if not meu.is_empty() and meu.distancia < 6.5:
			_encerrar_ataque()
		else:
			destino = alvo_p
			atacando = true
	var ang := _apontar(e, destino, 2.4)
	e.acelerar = 1.0
	# Curva fechada devagar (sem freio: só tira o pé)
	if absf(ang) > 1.1 and velocidade > 7.0 and not atacando:
		e.acelerar = 0.25
	# Quase parado e virado para o lado errado (ex.: largando de vaga de frente para a parede):
	# cavalo de pau em vez de uma curva aberta
	elif absf(ang) > 1.3 and velocidade < 5.0:
		_cavalo_de_pau(e, ang)
	# Climb to Death: carro colado na frente = tira o pé (na saída do cercado todo mundo se embola)
	if _so_no_caminho and _colado_na_frente():
		e.acelerar = minf(e.acelerar, 0.35)
	# Fila no portão: perto da saída, se já tem carro passando logo à frente, espera a vez
	if _so_no_caminho and arena.local(p).x > arena.comprimento - 28.0 and _fila_no_portao(arena):
		e.acelerar = minf(e.acelerar, 0.15)
	# Climb to Death: dentro de cercado com buracos, anda devagar (a vida vem primeiro)
	if _so_no_caminho and not arena.buracos.is_empty():
		if velocidade > VEL_PLATAFORMA * 1.3:
			e.acelerar = 0.0
			e.re = 1.0
		elif velocidade > VEL_PLATAFORMA:
			e.acelerar = 0.0
	# Canyon Combat: buraco no caminho dos próximos ~1,2 s em velocidade alta tira o pé (os jogadores
	# cruzam a plataforma sem pressa; os bots de pé embaixo caíam em ~1 de cada 4 etapas)
	elif not arena.buracos.is_empty() and velocidade > VEL_PLATAFORMA * 1.4:
		var adiante: Dictionary = arena.buraco_mais_perto(p + veiculo.linear_velocity * 1.2)
		if not adiante.is_empty() and adiante.distancia < 5.0:
			e.acelerar = 0.0
	# Freio de emergência: se daqui a 1 s o carro estaria na boca de um buraco, tira o pé,
	# dá ré (é o único "freio") e esterça para longe dele
	var previsto := p + veiculo.linear_velocity * 1.0
	var b: Dictionary = arena.buraco_mais_perto(previsto)
	if not b.is_empty() and b.distancia < 2.5 and velocidade > 3.0:
		e.acelerar = 0.0
		e.re = 1.0
		var frente := -veiculo.global_transform.basis.z
		var para_buraco: Vector3 = b.centro - p
		e.direcao = 1.0 if frente.cross(para_buraco).y > 0.0 else -1.0   # buraco à esquerda: vira à direita


## Rival mais "empurrável": na minha frente e perto de um buraco (ou de uma seta-armadilha, que
## joga o carro no buraco), ou colado na minha frente.
## Quem está chegando no portão não se distrai (senão todo mundo embola na saída).
func _escolher_vitima_arena(arena) -> Veiculo:
	var p := veiculo.global_position
	if arena.local(p).x > arena.comprimento - 14.0:
		return null
	var frente := -veiculo.global_transform.basis.z
	var melhor: Veiculo = null
	var melhor_nota := -INF
	if _so_no_caminho:
		return null   # Climb to Death: a meta é chegar vivo ao alvo; derrubar é só consequência do trajeto
	for r: Veiculo in _rivais():
		if r.estado != Veiculo.Estado.APOIADO or not arena.dentro_da_arena(r.global_position):
			continue
		var d := r.global_position - p
		var dist := d.length()
		var mira := frente.dot(d.normalized())
		var b: Dictionary = arena.perigo_mais_perto(r.global_position)
		var perto_buraco: bool = not b.is_empty() and b.distancia < 9.0
		if dist > 22.0 or mira < 0.5 or not (perto_buraco or (dist < 10.0 and mira > 0.8)):
			continue
		var nota := -dist
		if perto_buraco:
			nota += (9.0 - b.distancia) * 3.0
		if r.eh_jogador:
			nota += 4.0   # o jogador humano é o rival mais cobiçado
		if nota > melhor_nota:
			melhor_nota = nota
			melhor = r
	return melhor


## Carro preso contra parede/carro. Se o caminho está para o lado, gira no lugar com cavalo de pau
## (borrachão W+S com o volante para o destino) até apontar para ele; se está de frente para o
## obstáculo, dá ré com o volante virado e depois gira. Continuando preso, alterna as duas manobras.
func _destravar(e: Dictionary, delta: float) -> bool:
	if _girar_t > 0.0:
		_girar_t -= delta
		var ang_g := _angulo_para(_destino_chao())
		if absf(ang_g) > 0.2:
			_cavalo_de_pau(e, ang_g)
			return true
		_girar_t = 0.0
	if _re_t > 0.0:
		_re_t -= delta
		e.re = 1.0
		e.direcao = _re_lado
		if _re_t <= 0.0 and absf(_angulo_para(_destino_chao())) > 0.4:
			_girar_t = 2.0   # saiu da parede de ré: agora aponta para o caminho
		return true
	if veiculo.linear_velocity.length() < 1.2 and _t > _espera + 1.5:
		_parado_t += delta
		if _parado_t > 1.2:
			_parado_t = 0.0
			_tentativa += 1
			_encerrar_ataque()
			var ang := _angulo_para(_destino_chao())
			var arena_m = _recinto()
			if arena_m and _no_muro_do_portao(arena_m):
				_tentativa = 0   # colado no muro ao lado do portão: primeiro sai de ré
			if absf(ang) > 0.5 and _tentativa % 3 != 0:
				_girar_t = 2.5
			else:
				_re_t = rng.randf_range(0.8, 1.4)
				# De ré, volante para a direita gira o bico para a esquerda: vira o bico para o destino
				_re_lado = 1.0 if ang > 0.0 else -1.0
				if absf(ang) < 0.3:
					_re_lado = -1.0 if rng.randf() < 0.5 else 1.0
	else:
		_parado_t = 0.0
	return false


## Encostado no muro ao lado do portão (o portão só passa 2 carros): tentar ir direto para a saída
## só empurra o muro.
func _no_muro_do_portao(arena) -> bool:
	var l: Vector2 = arena.local(veiculo.global_position)
	return l.x > arena.comprimento - 10.0 and l.x < arena.comprimento + 1.0 and absf(l.y) > arena.saida_largura * 0.5 + 1.5


## Borrachão com o volante para o lado do destino: o carro gira no próprio eixo.
func _cavalo_de_pau(e: Dictionary, ang: float) -> void:
	e.acelerar = 1.0
	e.re = 1.0
	e.direcao = -1.0 if ang > 0.0 else 1.0


## Para onde o carro quer ir no chão: saída da arena ou pista à frente.
func _destino_chao() -> Vector3:
	var p := veiculo.global_position
	var arena = _recinto()
	if arena:
		if _no_muro_do_portao(arena):
			return arena.pa(arena.comprimento - 18.0, 0.0, arena.piso_y)   # recua para entrar alinhado
		return arena.rumo_saida(p)
	var sub := veiculo.complexo as ComplexoSubida
	if sub:
		var i := sub.indice_estrada(p)
		return sub.amostra(sub.indice_adiante(i, 20.0)) if i >= 0 else p - veiculo.global_transform.basis.z * 10.0
	var cx := veiculo.complexo
	if cx:
		return cx.ponto(cx.x_perfil(p) + 20.0, p.y)
	return p - veiculo.global_transform.basis.z * 10.0


## Cercado onde o carro está (arena do Canyon Combat, largada ou plataforma do Climb to Death), ou null.
func _recinto():
	var a := _arena()
	if a:
		return a if a.local(veiculo.global_position).x < a.comprimento + 24.0 else null
	var sub := veiculo.complexo as ComplexoSubida
	return sub.recinto_em(veiculo.global_position) if sub else null


## Climb to Death na estrada: segue o eixo na sua faixa, tira o pé (e dá ré) antes das curvas
## fechadas, alinha e vai com tudo na rampa de salto, e tenta jogar rivais para fora da estrada
## (não tem cerca). Nos cercados usa a mesma lógica da arena.
func _dirigir_subida(e: Dictionary, sub: ComplexoSubida) -> void:
	var p := veiculo.global_position
	var r = sub.recinto_em(p)
	if r != null:
		_so_no_caminho = true
		_dirigir_arena(e, r)
		return
	var i := sub.indice_estrada(p)
	if i < 0:
		e.acelerar = 1.0
		return
	i = _indice_com_desvio(sub, p, i)
	var v := veiculo.linear_velocity.length()
	# TSC_BOT_LOG=1: onde cada bot está (trecho e metro), a cada 5 s — para conferir se passam de um desafio
	if OS.get_environment("TSC_BOT_LOG") != "" and fmod(_t, 5.0) < _dt_ia:
		print("[BOT] t=%3.0f %-12s %s m=%5.0f v=%4.1f ej=%.1f" % [_t, veiculo.nome_piloto, sub.nome_trecho(sub.trecho_de(i)), sub.progresso_amostra(i) - sub.progresso_amostra(sub.inicio_trecho_de(i)), v, veiculo.recarga_ejetor])
	var falta := sub.progresso_amostra(sub.fim_do_trecho(i)) - sub.progresso_amostra(i)
	if OS.get_environment("TSC_SALTO_LOG") != "" and fmod(_t, 0.25) < _dt_ia \
			and ((sub.trecho_de(i) == 1 and falta < 150.0) or (sub.trecho_de(i) == 2 and sub.progresso_amostra(i) - sub.progresso_amostra(0) < 99999.0 and sub.progresso_amostra(i) < sub.s_salto + 350.0)):
		var fr := -veiculo.global_transform.basis.z
		print("[SALTO] %-12s trecho=%d falta=%5.0f v=%4.1f lat=%+.1f rumo_err=%+.2f rodas=%d vy=%+.1f ac=%.1f fr=%.1f re=%.1f dir=%+.2f" % [veiculo.nome_piloto, sub.trecho_de(i), falta, v,
			(p - sub.amostra(i)).dot(sub.lateral_em(i)), atan2(fr.cross(sub.tangente_em(i)).y, fr.dot(sub.tangente_em(i))), veiculo.rodas_no_chao, veiculo.linear_velocity.y,
			float(e.acelerar), float(e.freiar), float(e.re), float(e.direcao)])
	# Plataforma sem chão (Extinction Day E2): o fim do A é um salto — chega rápido e alinhado
	var salto_plat := sub.plataforma.sem_piso and sub.trecho_de(i) == 0 and falta < 130.0
	var perto_salto := (sub.trecho_de(i) == 1 and falta < 130.0) or salto_plat
	var perto_final := sub.trecho_de(i) == 2 and falta < 180.0
	var chegando_plataforma := sub.trecho_de(i) == 0 and falta < 70.0 and not sub.plataforma.sem_piso
	var porta_acel := sub.trecho_de(i) == 0 and not sub.plataforma.sem_piso and sub.plataforma.porta_acelerada
	var v_porta := _vel_porta(sub, i) if porta_acel else 0.0
	# Aceleradores na porta da plataforma (jogam o carro na direção dos buracos): pula por cima com o ejetor
	if chegando_plataforma and falta < 5.0 and sub.plataforma.porta_acelerada:
		veiculo.sem_impulso_ate = veiculo.relogio + 3.0
		if veiculo.ejetor_disponivel():
			veiculo.pedir_ejetor()
	# Poço no nível da pista (Extinction Day E2, pedido do dono): o píer acaba e o portão fica 70 m adiante,
	# na mesma altura — pula com o ejetor rente à ponta (no ar, _planar leva até o portão)
	if salto_plat and sub.plataforma.entrada_fundo > 0.0 and falta < 3.5 + v * 0.1 and veiculo.ejetor_disponivel():
		veiculo.pedir_ejetor()
	# Frozen Peak: vão (salto) logo à frente, trecho estreito e gelo vivo
	var vao := sub.vao_adiante(i, 110.0)
	var perto_vao := not vao.is_empty() and float(vao.falta) < 95.0
	var ilhas := perto_vao and vao.has("vel")   # ilhas de basalto: vãos curtos em sequência, velocidade certa
	var estreito := sub.largura_adiante(i, v * 1.6 + 22.0) < sub.largura_estrada - 2.5
	var perto_loop := sub.looping_adiante(i, 90.0) or not sub.ejetor_adiante(i, 45.0).is_empty()   # entra no looping (ou na mola) pelo meio, sem disputa
	var ader := sub.aderencia_adiante(i, v * 1.8 + 18.0)
	var meia := sub.largura_em(i) * 0.5 - 1.6
	var alvo_lat := _faixa
	if perto_salto or perto_final or perto_vao or estreito or perto_loop:
		alvo_lat = 0.0
		_encerrar_ataque()
	else:
		# Missão principal: subir e chegar ao alvo. Derrubar é secundário: só quem está no caminho,
		# sem ir para a beirada e sem perder velocidade por isso
		var meu_lat := (p - sub.amostra(i)).dot(sub.lateral_em(i))
		# Rival logo à frente no caminho: tenta jogá-lo para fora (a sorte depende da agressividade e da meta do mapa)
		if _vitima == null and absf(meu_lat) < meia - 1.2:
			_tentar_atacar(_rival_na_estrada(sub, i), 3.5, FRASES_ATAQUE, "chao")
		if _vitima and (absf(meu_lat) > meia - 0.3 or veiculo.linear_velocity.dot(sub.tangente_em(i)) < 6.0):
			_encerrar_ataque()
		if _vitima:
			var j := sub.indice_estrada(_vitima.global_position)
			if j < 0 or absi(j - i) > 30 or _vitima.estado != Veiculo.Estado.APOIADO:
				_encerrar_ataque()
			else:
				# Mira um pouco além do lado dele: a pancada o empurra para a beirada
				var lat_v := (_vitima.global_position - sub.amostra(j)).dot(sub.lateral_em(j))
				alvo_lat = lat_v + signf(lat_v if absf(lat_v) > 0.3 else _faixa) * 1.2
	# Ultrapassagem: quer vencer, mas sem arriscar cair (só em reta, com a outra faixa livre)
	if perto_salto or perto_final or chegando_plataforma or perto_vao or estreito or perto_loop or ader < 0.9:
		_ultrap_t = 0.0
	else:
		alvo_lat = _ultrapassar(sub, i, alvo_lat)
	# Pharaoh's Climb: portão de granito à frente. Chega a ~16 m/s e, a 35 m, escolhe a faixa que vai
	# ficar livre durante a passagem inteira (chegada até sair do outro lado do bloco); a 10 m segura a
	# escolha. Sem faixa livre (troca de lado dos blocos), tira o pé um pouco — sem parar: carro parado
	# no portão virava fila e quem estava atrás empurrava todo mundo para fora.
	var pistao := sub.pistao_adiante(i)
	var pistao_acao := ""
	if not pistao.is_empty():
		var falta_p: float = pistao.falta
		if pistao.s != _pistao_s:
			_pistao_s = pistao.s
			_pistao_lado = 1.0 if pistao.livre[1] >= pistao.livre[0] else -1.0
		var vv := maxf(v, 8.0)
		var t0 := maxf(falta_p - 4.0, 0.0) / vv
		var t1 := (falta_p + 11.0) / vv + 0.2
		var livres := [sub.pistao_livre_entre(pistao.s, 0, t0, t1), sub.pistao_livre_entre(pistao.s, 1, t0, t1)]
		var meu := 1 if _pistao_lado > 0.0 else 0   # bloco direito (1) fecha a lateral positiva
		if falta_p > 10.0 and falta_p < 35.0 and not livres[meu] and livres[1 - meu]:
			_pistao_lado = -_pistao_lado
			meu = 1 - meu
		if falta_p > 35.0:
			pistao_acao = "aproxima"
		elif livres[meu] or falta_p < 3.0:
			pistao_acao = "vai"
		else:
			pistao_acao = "devagar"
		if OS.get_environment("TSC_PISTAO_LOG") != "" and fmod(_t, 0.25) < _dt_ia:
			print("[PISTAO] %-12s falta=%5.1f v=%4.1f lado=%+.0f livres=%s %s" % [veiculo.nome_piloto, falta_p, v, _pistao_lado, str(livres), pistao_acao])
		alvo_lat = _pistao_lado * float(pistao.lat)
		_ultrap_t = 0.0
		_encerrar_ataque()
	# Acelerador contrário (placa vermelha que joga para trás): passa pelo lado livre
	var re_a := sub.re_adiante(i, 90.0)
	var re_vel := -1.0
	if not re_a.is_empty():
		# Rente à placa (não lá na beirada): a seguinte fica do outro lado, 20 m adiante, e é preciso costurar.
		# Rápido não dá tempo de trocar de lado — batia na placa, era jogado para trás e caía da estrada.
		alvo_lat = float(re_a.borda) + signf(float(re_a.livre)) * 1.0
		re_vel = sqrt(RE_VEL * RE_VEL + 2.0 * 4.5 * maxf(float(re_a.falta) - 8.0, 0.0))
		_ultrap_t = 0.0
		_encerrar_ataque()
		# Alternativa esperta (pedido do dono): em vez de costurar devagar, pula as placas com o ejetor — vem
		# pelo meio, rápido e reto, e salta uns metros antes da primeira (o voo de ~2,7 s passa por cima das duas).
		# Só em reta, sem armadilha, vão ou estreito na zona do pouso, e com o ejetor carregado.
		var s_re := sub.progresso_amostra(i) + float(re_a.falta)
		if absf(s_re - _pulo_re_s) > 60.0 and float(re_a.falta) > 20.0:
			_pulo_re_s = s_re
			_pulo_re = rng.randf() < _esperteza
		var pouso_livre := sub.curvatura_adiante(i, float(re_a.falta) + 75.0) < 1.0 / 260.0 and sub.vao_adiante(i, float(re_a.falta) + 80.0).is_empty() \
				and sub.largura_adiante(i, float(re_a.falta) + 75.0) >= sub.largura_estrada - 0.5 and sub.fim_do_trecho(i) - i > 90 \
				and (sub.armadilhas == null or sub.armadilhas.portao_adiante(i, float(re_a.falta) + 75.0).is_empty())
		if _pulo_re and absf(s_re - _pulo_re_s) <= 60.0 and pouso_livre and float(re_a.falta) > 3.0 and (veiculo.ejetor_disponivel() or veiculo.recarga_ejetor < float(re_a.falta) / maxf(v, 8.0) - 0.4):
			alvo_lat = 0.0
			re_vel = 17.0
			if float(re_a.falta) < 5.5 + v * 0.12 and veiculo.ejetor_disponivel() and v > 11.0 and absf((p - sub.amostra(i)).dot(sub.lateral_em(i))) < 2.5:
				veiculo.sem_impulso_ate = veiculo.relogio + 3.0
				veiculo.pedir_ejetor()
				if rng.randf() < 0.3:
					_falar(["Por cima!", "Placa de ré? Pulei.", "Voando baixo!"][rng.randi() % 3])
	# Serpent's Climb: armadilhas do templo. Para lâmina, lanças, boca da serpente e jatos, escolhe a
	# menor chegada (entre 7 e 19 m/s) em que a faixa fica livre do bico entrar até a traseira sair e
	# ajusta a velocidade para chegar nessa hora (sem parar na frente: fila na armadilha derruba gente).
	# Nas ladeiras de pedras rolando, fica na faixa onde a próxima pedra está mais longe.
	var arm_vel := -1.0
	var arm := sub.armadilhas
	if arm:
		var g := arm.portao_adiante(i, 130.0)
		if not g.is_empty():
			var falta_g: float = g.falta
			var comp_g: float = g.comp
			if int(g.id) != _arm_id:
				_arm_id = int(g.id)
				_arm_lado = -1
				_arm_plano_t = 0.0
			_arm_plano_t -= _dt_ia
			if falta_g <= 1.0:
				arm_vel = maxf(22.0, _arm_vel_max)   # já está dentro: sai depressa
			elif _arm_plano_t > 0.0:
				arm_vel = _arm_vel_plano
			else:
				var melhor_t := INF
				var melhor_lado := maxi(_arm_lado, 0)
				var lados := [0] if bool(g.total) else ([_arm_lado] if _arm_lado >= 0 and falta_g < 22.0 else [0, 1])
				for lado: int in lados:
					var t := falta_g / _arm_vel_max
					var t_max := falta_g / ARM_VEL_MIN
					while t <= t_max:
						var vv := falta_g / maxf(t, 0.05)
						# Só a janela que o carro alcança (velocidade média possível acelerando daqui) e livre
						# do bico entrar até a traseira sair, com folga curta
						if vv <= v + ARM_ACEL * 0.5 * t + 1.0 and arm.livre_entre(int(g.id), lado, t - 0.35 * _arm_folga, t + (comp_g + 3.0 + 3.0 * _arm_folga) / maxf(vv, 6.0) + 0.25 * _arm_folga):
							break
						t += 0.1
					if t <= t_max and t < melhor_t:
						melhor_t = t
						melhor_lado = lado
				if melhor_t < INF:
					# Mira a velocidade de CHEGADA (acelerando até lá), não a média: chega mais rápido e sai logo
					arm_vel = clampf(2.0 * falta_g / melhor_t - v, falta_g / melhor_t, _arm_vel_max) if falta_g / melhor_t > v else clampf(falta_g / melhor_t, ARM_VEL_MIN, _arm_vel_max)
					if not bool(g.total):
						_arm_lado = melhor_lado
				else:
					arm_vel = 0.0 if falta_g < 14.0 else ARM_VEL_MIN   # nenhuma janela: segura antes de entrar
				_arm_vel_plano = arm_vel
				_arm_plano_t = ARM_PLANO_S
			if not bool(g.total) and _arm_lado >= 0:
				alvo_lat = (1.0 if _arm_lado == 1 else -1.0) * Armadilhas.FAIXA
			_ultrap_t = 0.0
			_encerrar_ataque()
			if OS.get_environment("TSC_ARMADILHA_LOG") != "" and fmod(_t, 0.25) < _dt_ia:
				print("[ARM] %-12s %s falta=%5.1f v=%4.1f quer=%4.1f lado=%d" % [veiculo.nome_piloto, g.tipo, falta_g, v, arm_vel, _arm_lado])
		var pedras := arm.pedras_adiante(i, 230.0)
		# No gelo vivo não troca de faixa por causa de pedra/bola longe: a guinada faz o carro rodar
		if not pedras.is_empty() and ader >= 0.9:
			var perto := [INF, INF]
			for pd: Array in pedras:
				perto[int(pd[1])] = minf(perto[int(pd[1])], float(pd[0]))
			var meu_l := (p - sub.amostra(i)).dot(sub.lateral_em(i))
			var faixa_atual := 1 if meu_l > 0.0 else 0
			var outra := 1 - faixa_atual
			# Troca de faixa se a pedra da minha faixa está perto e a da outra mais longe
			var lado_p := faixa_atual
			if perto[faixa_atual] < 150.0 and perto[outra] > perto[faixa_atual] + 25.0:
				lado_p = outra
			alvo_lat = (1.0 if lado_p == 1 else -1.0) * Armadilhas.FAIXA
			_ultrap_t = 0.0
			_encerrar_ataque()
	# Desvio da catapulta: chega devagar, para em cima da boca do gêiser e espera a erupção
	var cat := sub.catapulta_adiante(i)
	var segurar := false
	if not cat.is_empty() and float(cat.falta) < 70.0:
		alvo_lat = 0.0
		_ultrap_t = 0.0
		_encerrar_ataque()
		arm_vel = clampf(sqrt(maxf(float(cat.falta) - 1.0, 0.0) * 5.0), 0.0, 13.0)
		segurar = float(cat.falta) < 2.2
	# Perto da beirada (empurrado ou abrindo demais): volta para o meio antes de qualquer coisa
	var meu := (p - sub.amostra(i)).dot(sub.lateral_em(i))
	var na_beirada := absf(meu) > meia + 0.4
	if na_beirada:
		alvo_lat = 0.0
		_encerrar_ataque()
	# Porta acelerada: vem pelo lado oposto ao da diagonal do pulo
	if porta_acel and falta < 75.0:
		alvo_lat = -_porta_lado * 3.0
		_ultrap_t = 0.0
		_encerrar_ataque()
	alvo_lat = clampf(alvo_lat, -meia, meia)
	# Chegando no salto: mira bem longe no eixo e segura o volante firme — o tranco do ponto de
	# aceleração vai para onde o carro aponta; torto, ele atravessa o vão de lado e cai
	var olhar := (14.0 if ilhas else 30.0) if perto_salto or perto_vao else clampf(9.0 + v * 0.6, 9.0, 35.0)
	if estreito and not perto_vao:
		olhar = clampf(3.0 + v * 0.4, 4.5, 9.0)   # estreito: olha bem perto, senão corta a curva por dentro e sai da laje
	if not re_a.is_empty() and float(re_a.falta) < 30.0:
		olhar = 6.0   # costurando as placas de ré: olha perto para trocar de lado a tempo
	var k := sub.indice_adiante(i, olhar)
	var erro_antes := _erro_volante
	if perto_salto or perto_vao:
		_erro_volante = 0.0
	elif estreito:
		_erro_volante *= 0.3
	# No gelo: volante mais leve (corrigir forte faz o carro rodar)
	var destino_e := sub.amostra(k) + sub.lateral_em(k) * alvo_lat
	if not cat.is_empty() and float(cat.falta) < 30.0 and float(cat.falta) > 2.2:
		destino_e = cat.pos
	if porta_acel and falta < 26.0:
		destino_e = _porta_mira   # pula na diagonal: o pouso (e o quique) passam ao lado do buraco da linha da porta
	_apontar(e, destino_e, 2.6 if na_beirada else (1.5 if ader < 0.9 else 2.2))
	if ader < 0.9 and not na_beirada:
		e.direcao = clampf(float(e.direcao), -0.4, 0.4)
	_erro_volante = erro_antes
	e.acelerar = 0.6 if na_beirada else 1.0
	# De costas para a subida (rodou no pouso ou numa pancada): manobra de ré com o volante ao
	# contrário até apontar para a frente — dar a volta de frente fazia um círculo que passava da
	# beirada (a estrada não tem cerca)
	var fr_c := -veiculo.global_transform.basis.z
	var t_c := sub.tangente_em(i)
	var err_c := atan2(Vector3(fr_c.x, 0, fr_c.z).cross(Vector3(t_c.x, 0, t_c.z)).y, Vector3(fr_c.x, 0, fr_c.z).dot(Vector3(t_c.x, 0, t_c.z)))
	if absf(err_c) > 1.6 and v < 10.0 and veiculo.rodas_no_chao > 0:
		_manobra_re = 1.2
	if _manobra_re > 0.0:
		_manobra_re -= _dt_ia
		if absf(err_c) < 0.9 or v > 12.0:
			_manobra_re = 0.0
		else:
			var anda := veiculo.linear_velocity.dot(fr_c)
			e.acelerar = 0.0
			e.freiar = 1.0 if anda > 1.5 else 0.0
			e.re = 0.0 if anda > 1.5 else 0.8
			e.direcao = signf(err_c)
			if absf(meu) > meia - 0.5:
				e.re = 0.0
				e.acelerar = 0.7   # de ré iria para fora: anda de frente um pouco
				e.direcao = -signf(err_c)
			return
	if not perto_salto and not perto_vao:
		# Velocidade de curva conservadora: pouca aderência e, rápido, o volante vira menos
		# (no gelo vivo, proporcional à aderência; no estreito e no gelo, com um teto)
		var v_max := sqrt(ACEL_LATERAL * clampf(ader * 1.1, 0.3, 1.0) / maxf(sub.curvatura_adiante(i, v * 2.5 + 25.0), 0.0005))
		if estreito:
			v_max = minf(v_max * 0.9, 9.5)
		if ader < 0.9:
			v_max = minf(v_max, _vel_estrada * 0.8)
		if v > v_max * 1.15:
			e.acelerar = 0.0
			# Com freio instalado, freia de verdade: a ré em alta velocidade (depois do pouso do salto,
			# a 40 m/s) fazia o carro atravessar e cair
			if _tem_freio:
				e.freiar = 1.0
			else:
				e.re = 1.0
		elif v > v_max:
			e.acelerar = 0.0
	match pistao_acao:
		"aproxima", "vai":
			if v > 17.0 and veiculo.linear_velocity.dot(sub.tangente_em(i)) > 0.0:
				e.acelerar = 0.0
				e.freiar = 1.0 if v > 20.0 else 0.0
		"devagar":
			e.acelerar = 0.0 if v > 7.0 else 0.6
			e.freiar = 1.0 if v > 12.0 else 0.0
	if re_vel >= 0.0 and v > re_vel:
		e.acelerar = 0.0
		if v > re_vel + 2.0:
			if _tem_freio:
				e.freiar = 1.0
			else:
				e.re = 1.0
	if arm_vel >= 0.0 and veiculo.linear_velocity.dot(sub.tangente_em(i)) > -1.0:
		if v > arm_vel + 1.2:
			e.acelerar = 0.0
			e.freiar = 1.0 if v > arm_vel + 2.5 else 0.0
		elif v < arm_vel - 1.0:
			e.acelerar = maxf(float(e.acelerar), 0.9)
		else:
			e.acelerar = minf(float(e.acelerar), 0.45)
	# Carro logo à frente na mesma faixa: tira o pé em vez de bater nele por trás (a pancada
	# joga um dos dois para fora da estrada — e pode ser este)
	# Vão à frente: pé embaixo e reto (devagar o carro não alcança o outro lado); se chegar lento, nitro
	# (rápido demais também não: o carro voa por cima do pouso e cai na curva seguinte)
	if perto_vao and bool(vao.get("ejetor", false)):
		# Plataformas redondas desniveladas: a próxima fica mais alta — só se chega com o ejetor. Chega devagar,
		# espera a recarga parado em cima da plataforma (cabe: são largas) e pula já perto da beirada.
		var falta_v := float(vao.falta)
		var pronto := veiculo.ejetor_disponivel()
		var v_alvo := float(vao.vel) if falta_v < 20.0 else 12.0   # só reduz para a velocidade do pulo perto da beirada
		e.re = 0.0
		e.nitro = false
		# Sem o ejetor pronto (5 s de recarga): freia logo que pousa e espera parado — chegando rápido na beirada não parava mais
		if not pronto and not veiculo.ejetor_bloqueado() and falta_v < 17.0:
			segurar = true
		elif v > v_alvo + 0.3:
			e.acelerar = 0.0
			e.freiar = 1.0 if v > v_alvo + 0.9 else 0.0
		else:
			e.acelerar = 1.0 if v < v_alvo - 0.5 else 0.3
			e.freiar = 0.0
		# Pula rente à beirada, na velocidade calculada para o vão (o voo do ejetor dura ~2,4 s: rápido demais,
		# pousava no fim da plataforma seguinte e caía do outro lado)
		if pronto and falta_v < 1.1 and falta_v > -1.0 and v > v_alvo - 1.2:
			veiculo.pedir_ejetor()
		if OS.get_environment("TSC_ILHA_LOG") != "" and falta_v < 4.0 and fmod(_t, 0.3) < _dt_ia:
			print("[ILHA] %s t=%.1f falta=%.1f v=%.1f va=%.1f vy=%.1f pronto=%s seg=%s rodas=%d y=%.1f sobe=%s" % [veiculo.nome_piloto.left(4), _t, falta_v, v, v_alvo, veiculo.linear_velocity.y, pronto, segurar, veiculo.rodas_no_chao, p.y, str(vao.get("sobe", "?"))])
	elif perto_vao:
		var v_vao := float(vao.get("vel", 19.0 + float(vao.comp) * 0.5))
		e.re = 0.0
		if v > v_vao + 5.0 and float(vao.falta) > 14.0:
			e.acelerar = 0.0
			e.freiar = 1.0
		elif v > v_vao + 2.0:
			e.acelerar = 0.0
			e.freiar = 0.0
		else:
			e.acelerar = 1.0
			e.freiar = 0.0
		if not ilhas and float(vao.falta) < 60.0 and float(vao.falta) > 0.0 and v < 16.0 + float(vao.comp) * 0.25:
			e.nitro = true
	if not perto_salto and not perto_vao and _ultrap_t <= 0.0 and _carro_na_frente(sub, i, meu):
		e.acelerar = minf(e.acelerar, 0.35)
	# Teto de velocidade na estrada sem cerca (nível do bot): a vida vem primeiro. Ultrapassando,
	# puxa um pouco acima para conseguir passar.
	if not perto_salto and v > _vel_estrada * (1.15 if _ultrap_t > 0.0 else 1.0):
		e.acelerar = 0.0   # só tira o pé: frear de ré em alta velocidade faz o carro atravessar e cair
	# Chegada na plataforma: freia a tempo (a distância cresce com a velocidade — a 70 m fixos, vindo a
	# 120 km/h, entrava a 80). Porta com aceleradores: entra mais devagar, porque pula por cima deles com o
	# ejetor e, rápido, o voo terminava no meio dos buracos.
	var v_plat := v_porta if porta_acel else VEL_PLATAFORMA * 1.4
	if sub.trecho_de(i) == 0 and not sub.plataforma.sem_piso and falta < maxf(70.0, (v * v - v_plat * v_plat) / 9.0 + 25.0) and v > v_plat:
		e.acelerar = 0.0
		if chegando_plataforma:
			e.re = 1.0 if v > (v_plat + 0.8 if porta_acel else v_plat * 1.3) else 0.0
		elif v * v > v_plat * v_plat + 9.0 * maxf(falta - 25.0, 0.0):
			e.re = 1.0
	# TSC_GELO_LOG=1: bots em salto, gelo ou estreito; TSC_GELO_LOG="T:m0:m1": todos os bots entre m0 e m1 do trecho T (A, B ou C)
	var log_g := OS.get_environment("TSC_GELO_LOG")
	var no_trecho := false
	if log_g.contains(":"):
		var pg := log_g.split(":")
		var m_g := sub.progresso_amostra(i) - sub.progresso_amostra(sub.inicio_trecho_de(i))
		no_trecho = sub.trecho_de(i) == ["A", "B", "C"].find(pg[0]) and m_g >= float(pg[1]) and m_g <= float(pg[2])
	if log_g != "" and (no_trecho or (not log_g.contains(":") and (estreito or ader < 0.9 or perto_vao))) and fmod(_t, 0.2) < _dt_ia:
		print("[GELO] %-12s m=%5.0f v=%4.1f lat=%+.2f alvo=%+.2f larg=%4.1f ader=%.2f vao=%s estr=%s curv=%.3f ac=%.1f fr=%.1f dir=%+.2f rodas=%d arm=%.1f" % [veiculo.nome_piloto, sub.progresso_amostra(i) - sub.progresso_amostra(sub.inicio_trecho_de(i)), v, meu, alvo_lat, sub.largura_em(i), ader,
			str(snappedf(float(vao.falta), 1.0)) if perto_vao else "-", str(estreito), sub.curvatura_adiante(i, 20.0), float(e.acelerar), float(e.freiar), float(e.direcao), veiculo.rodas_no_chao, arm_vel])
	if segurar:
		e.acelerar = 0.0
		e.re = 0.0
		e.freiar = 1.0
	else:
		_defender(sub, i, meu, meia, v, e, perto_salto or perto_final or perto_vao or estreito or arm_vel >= 0.0 or ader < 0.9)
	if _usa_nitro and (perto_final or (perto_salto and v < 28.0)):
		e.nitro = true
	if _usa_ejetor and not _ejetou and sub.x_perfil(p) > sub.perfil.comprimento_horizontal - 4.0 and veiculo.ejetor_disponivel():
		_ejetou = true
		veiculo.pedir_ejetor()


## Porta da plataforma com aceleradores (Extinction Day): o bot pula por cima deles com o ejetor e voa
## TEMPO_PULO s reto. A velocidade de chegada decide onde pousa: escolhe a maior (até VEL_PLATAFORMA) em
## que o pouso passa dos aceleradores e ainda sobra chão para frear antes do buraco da morte que fica na
## linha da porta (a 50 km/h o voo terminava dentro dele; a 80, dentro do seguinte).
func _vel_porta(sub: ComplexoSubida, i: int) -> float:
	if _vel_porta_v > 0.0:
		return _vel_porta_v
	var k := sub.fim_do_trecho(i)
	var dir := sub.tangente_em(k)
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var salto := sub.amostra(k) - dir * 4.5
	var plat := sub.plataforma
	var melhor := 8.0
	var melhor_folga := -INF
	var vv := VEL_PLATAFORMA
	while vv >= 7.0:
		var pouso := salto + dir * vv * TEMPO_PULO
		pouso.y = plat.piso_y
		var limpo := plat.impulso_em(pouso) == Vector3.ZERO and plat.impulso_em(pouso - dir * 3.0) == Vector3.ZERO
		# Chão livre adiante do pouso (na direção do voo) até a beirada do primeiro buraco
		var folga := 40.0
		var d := 0.0
		while d < 40.0:
			var b := plat.buraco_mais_perto(pouso + dir * d)
			if not b.is_empty() and float(b.distancia) < 1.5:
				folga = d
				break
			d += 1.0
		if limpo and folga >= vv * vv / 12.0 + 4.0:
			melhor = vv
			break
		if limpo and folga > melhor_folga:
			melhor_folga = folga
			melhor = vv
		vv -= 0.5
	_vel_porta_v = melhor
	# Diagonal do pulo: o lado em que o pouso e o quique (até ~14 m adiante) ficam mais longe dos buracos
	var lat := sub.lateral_em(k)
	var melhor_dist := -INF
	for s: float in [-1.0, 1.0]:
		var perto := INF
		for adiante: float in [0.0, 7.0, 14.0]:
			var q := salto + dir * (melhor * TEMPO_PULO + adiante) + lat * s * (7.0 + adiante * 0.25)
			var b := plat.buraco_mais_perto(q)
			if not b.is_empty():
				perto = minf(perto, float(b.distancia))
		if perto > melhor_dist:
			melhor_dist = perto
			_porta_lado = s
	_porta_mira = salto + dir * 40.0 + lat * _porta_lado * 13.0
	return melhor


## Bifurcação: escolhe uma rota (uma vez por bifurcação, pelo peso de cada desvio; a estrada vale 1,2) e
## devolve a amostra que o bot deve seguir — a do desvio escolhido a partir de ~22 m antes da saída, e de
## volta a da estrada principal nos últimos metros do desvio (os dois correm lado a lado ali).
func _indice_com_desvio(sub: ComplexoSubida, p: Vector3, i: int) -> int:
	if sub.desvios.is_empty():
		return i
	var k := sub.trecho_de(i)
	if k > 2:
		var d := sub.desvio_de(k)
		if not d.is_empty() and int(d.fim) - i < 46:
			return sub.amostra_no_trecho(p, sub.trecho_de(int(d.i_para)), int(d.i_para) - 70, int(d.i_para) + 30)
		return i
	var lista := sub.desvios_adiante(i, 120.0)
	if lista.is_empty():
		return i
	var chave := int(lista[0].i_de)
	if not _rota_desvio.has(chave):
		var total := 1.2
		for d: Dictionary in lista:
			if int(d.i_de) == chave:
				total += float(d.peso)
		var sorte := rng.randf() * total - 1.2
		var escolha := -1
		if sorte > 0.0:
			for d: Dictionary in lista:
				if int(d.i_de) != chave:
					continue
				escolha = int(d.k)
				sorte -= float(d.peso)
				if sorte <= 0.0:
					break
		var forcado := OS.get_environment("TSC_DESVIO")   # teste: todos os bots pelo desvio com este nome ("-" = estrada)
		if forcado != "":
			escolha = -1
			for d: Dictionary in lista:
				if str(d.nome) == forcado:
					escolha = int(d.k)
		_rota_desvio[chave] = escolha
	var esc: int = _rota_desvio[chave]
	if esc < 0:
		return i
	var dv := sub.desvio_de(esc)
	if float(dv.s_de) - sub.progresso_amostra(i) < 3.0:   # só depois que o desvio começa (ele corre 40 m ao lado da estrada)
		return sub.amostra_no_trecho(p, esc, int(dv.ini), int(dv.ini) + 80)
	return i


## Defesa na estrada: um rival vem de lado (fechando em menos de ~0,7 s) e a pancada me levaria para
## a beirada. Em reta e alinhado, pula com o ejetor — o agressor passa por baixo e é ele quem sai da
## estrada; sem ejetor (ou em curva), freia forte para ele passar reto. Quem acabou de me bater vira
## alvo do revide (bots.meta.revide). `ocupado` = armadilha, salto ou estreito à frente: só freia.
func _defender(sub: ComplexoSubida, i: int, meu: float, meia: float, v: float, e: Dictionary, ocupado: bool) -> void:
	var dt := _dt_ia
	_defesa_t -= dt
	if _freia_defesa > 0.0:
		_freia_defesa -= dt
		e.acelerar = 0.0
		e.nitro = false
		if v > 6.0:
			if _tem_freio:
				e.freiar = 1.0
			else:
				e.re = 1.0
		return
	var bateu := veiculo.contato_veiculo
	if _revide > 0.0 and bateu and _vitima == null and not ocupado and bateu.indice_equipe != veiculo.indice_equipe \
			and not bateu.eliminado and absf(meu) < meia - 1.0 and rng.randf() < (0.25 + agressividade) * _revide * dt * 8.0:
		_vitima = bateu
		_ataque_t = 4.0
		_pausa_ataque = 0.0
		if rng.randf() < 0.4:
			_falar(["Agora é a minha vez!", "Vai ter troco!", "Bateu, levou!"][rng.randi() % 3])
	if _defesa_t > 0.0 or _defesa <= 0.0:
		return
	var p := veiculo.global_position
	var t := sub.tangente_em(i)
	var l := sub.lateral_em(i)
	for r: Veiculo in _rivais():
		if r.estado != Veiculo.Estado.APOIADO:
			continue
		var d := r.global_position - p
		if absf(d.y) > 3.0 or d.length() > 11.0:
			continue
		var lat_r := d.dot(l)
		if absf(d.dot(t)) > 5.5 or absf(lat_r) < 1.2:
			continue
		var fechando := -(r.linear_velocity - veiculo.linear_velocity).dot(l) * signf(lat_r)
		if fechando < 1.5 or (absf(lat_r) - 2.0) / fechando > 0.7:
			continue
		# A pancada me empurra para o lado oposto ao dele: só reage se a beirada estiver perto desse lado
		if absf(meu - signf(lat_r) * 3.5) < meia - 0.3:
			continue
		_defesa_t = 1.5
		if rng.randf() > _defesa:
			return
		var fr := -veiculo.global_transform.basis.z
		var alinhado := absf(atan2(Vector3(fr.x, 0, fr.z).cross(Vector3(t.x, 0, t.z)).y, Vector3(fr.x, 0, fr.z).dot(Vector3(t.x, 0, t.z)))) < 0.12
		var reta := sub.curvatura_adiante(i, v * 3.0 + 12.0) < 1.0 / 400.0 and sub.fim_do_trecho(i) - i > int(v * 3.0) + 40
		if not ocupado and alinhado and reta and absf(meu) < meia - 0.4 and veiculo.ejetor_disponivel():
			veiculo.pedir_ejetor()
			if rng.randf() < 0.5:
				_falar(["Passou reto!", "Errou!", "Por baixo não vale!"][rng.randi() % 3])
		else:
			_freia_defesa = 0.55
		return


## Algum carro entre mim e o portão (até 16 m à frente, no corredor da saída).
func _fila_no_portao(arena) -> bool:
	var meu: Vector2 = arena.local(veiculo.global_position)
	for o: Veiculo in outros:
		if o == veiculo or o.eliminado or not o.visible:
			continue
		var l: Vector2 = arena.local(o.global_position)
		if l.x > meu.x + 2.0 and l.x < meu.x + 16.0 and absf(l.y) < arena.saida_largura * 0.5 + 6.0 and absf(o.global_position.y - veiculo.global_position.y) < 3.0:
			return true
	return false


## Outro carro logo à frente do bico (até 8 m, na mesma linha) e mais devagar.
func _colado_na_frente() -> bool:
	var f := -veiculo.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var l := f.cross(Vector3.UP)
	var p := veiculo.global_position
	var v := veiculo.linear_velocity.dot(f)
	for o: Veiculo in outros:
		if o == veiculo or o.eliminado or not o.visible:
			continue
		var d := o.global_position - p
		var adiante := d.dot(f)
		if adiante > 2.0 and adiante < 8.0 and absf(d.dot(l)) < 2.4 and absf(d.y) < 3.0 and o.linear_velocity.dot(f) < v - 0.5:
			return true
	return false


## Ultrapassagem na estrada do Climb to Death. Alcançou alguém na mesma faixa numa reta: passa pela
## outra faixa, se estiver livre, acelerando um pouco acima do teto. Desiste se vier curva, se a
## faixa fechar ou se não conseguir em 6 s. Devolve a posição lateral desejada.
func _ultrapassar(sub: ComplexoSubida, i: int, alvo_lat: float) -> float:
	var dt := _dt_ia
	_ultrap_decidir -= dt
	var p := veiculo.global_position
	var t := sub.tangente_em(i)
	var l := sub.lateral_em(i)
	var meu := (p - sub.amostra(i)).dot(l)
	var pista := sub.largura_em(i) * 0.5 - 2.2   # faixa de passagem: longe da beirada
	var reta := sub.curvatura_adiante(i, 140.0) < 1.0 / 320.0
	if _ultrap_t > 0.0:
		_ultrap_t -= dt
		var alvo := _ultrap_lado * pista
		if not reta or _faixa_ocupada(t, l, p, meu, alvo, -6.0, 18.0):
			_ultrap_t = 0.0   # curva chegando ou alguém na faixa: volta para a fila
			return alvo_lat
		# Já passou: ninguém mais colado à frente na faixa antiga, volta para a própria faixa
		if not _faixa_ocupada(t, l, p, meu, -_ultrap_lado * 1.5, -9.0, 4.0) and _ultrap_t < 4.0:
			_ultrap_t = minf(_ultrap_t, 0.8)
		return alvo
	if _ultrap_decidir > 0.0 or not reta:
		return alvo_lat
	_ultrap_decidir = 0.5
	# Alguém logo à frente na minha faixa (até 28 m)?
	var frente: Veiculo = null
	for o: Veiculo in outros:
		if o == veiculo or o.eliminado or not o.visible or o.fantasma():
			continue
		var d := o.global_position - p
		var adiante := d.dot(t)
		if adiante > 3.0 and adiante < 28.0 and absf(d.y) < 3.0 and absf(d.dot(l) - meu) < 2.6:
			frente = o
	if frente == null or rng.randf() > _vontade_ultrapassar:
		return alvo_lat
	_pulo_carro_t -= 0.5
	# Passa pelo lado oposto ao dele (ou pelo que tiver mais espaço)
	var lat_dele := (frente.global_position - sub.amostra(i)).dot(l)
	var lado := -signf(lat_dele) if absf(lat_dele) > 0.4 else (1.0 if rng.randf() < 0.5 else -1.0)
	if _faixa_ocupada(t, l, p, meu, lado * pista, -6.0, 18.0):
		lado = -lado
		if _faixa_ocupada(t, l, p, meu, lado * pista, -6.0, 18.0):
			# As duas faixas fechadas: o esperto pula por cima com o ejetor (pedido do dono), se vem bem mais
			# rápido que o da frente, em reta longa e sem desafio na zona do pouso
			var d_f := (frente.global_position - p).dot(t)
			var fecha := (veiculo.linear_velocity - frente.linear_velocity).dot(t)
			if _pulo_carro_t <= 0.0 and d_f < 14.0 and fecha > 4.5 and absf(meu) < pista and veiculo.ejetor_disponivel() and rng.randf() < _esperteza \
					and sub.curvatura_adiante(i, 110.0) < 1.0 / 400.0 and sub.vao_adiante(i, 110.0).is_empty() and sub.re_adiante(i, 110.0).is_empty() \
					and sub.largura_adiante(i, 100.0) >= sub.largura_estrada - 0.5 and sub.ejetor_adiante(i, 110.0).is_empty() and not sub.looping_adiante(i, 130.0) and sub.fim_do_trecho(i) - i > 130 \
					and sub.aderencia_adiante(i, 100.0) >= 0.9 and (sub.armadilhas == null or sub.armadilhas.portao_adiante(i, 110.0).is_empty()):
				_pulo_carro_t = 8.0
				veiculo.pedir_ejetor()
				if rng.randf() < 0.4:
					_falar(["Com licença, por cima!", "Fechou? Eu pulo.", "Olha o salto!"][rng.randi() % 3])
			return alvo_lat
	_ultrap_lado = lado
	_ultrap_t = 6.0
	if OS.get_environment("TSC_ULTRAP_LOG") != "":
		print("[ULTRAP] %s passando %s pela %s" % [veiculo.nome_piloto, frente.nome_piloto, "direita" if lado > 0.0 else "esquerda"])
	return lado * pista


## Há carro na faixa lateral `lat` entre `de` e `ate` metros (atrás/à frente de mim)?
func _faixa_ocupada(t: Vector3, l: Vector3, p: Vector3, meu: float, lat: float, de: float, ate: float) -> bool:
	for o: Veiculo in outros:
		if o == veiculo or o.eliminado or not o.visible or o.fantasma():
			continue
		var d := o.global_position - p
		var adiante := d.dot(t)
		# Lateral do outro na estrada = a minha + a diferença entre nós
		if adiante > de and adiante < ate and absf(d.y) < 3.0 and absf(meu + d.dot(l) - lat) < 2.4:
			return true
	return false


func _carro_na_frente(sub: ComplexoSubida, i: int, meu_lat: float) -> bool:
	var t := sub.tangente_em(i)
	var l := sub.lateral_em(i)
	var p := veiculo.global_position
	var v := veiculo.linear_velocity.dot(t)
	for o: Veiculo in outros:
		if o == veiculo or o.eliminado or not o.visible:
			continue
		var d := o.global_position - p
		var adiante := d.dot(t)
		if adiante < 2.0 or adiante > 9.0 or absf(d.y) > 3.0:
			continue
		if absf(d.dot(l)) < 2.4 and o.linear_velocity.dot(t) < v - 0.5:
			return true
	return false


## No ar sem estrada para pousar logo adiante e bem acima do chão: caiu da estrada (não é o salto).
func _caindo_da_estrada(sub: ComplexoSubida) -> bool:
	var v := veiculo.linear_velocity
	if v.y > -5.0 or veiculo.tempo_no_ar < 0.5:
		return false
	var p := veiculo.global_position
	if p.y - veiculo.terreno.altura_em(p.x, p.z) < 22.0:
		return false
	# Saltando o vão (perto da borda da rampa de salto): é salto, não queda
	if Vector2(p.x - sub.borda_salto.x, p.z - sub.borda_salto.z).length() < 260.0 and p.y > sub.borda_salto.y - 14.0:
		return false
	for t: float in [0.4, 0.8, 1.2, 1.6]:
		var q := p + v * t + Vector3.DOWN * 4.9 * t * t
		if sub.indice_estrada(q, 9.0) >= 0:
			return false
	return true


## Rival parado na estrada logo à frente (ou do lado), bom para empurrar para fora.
func _rival_na_estrada(sub: ComplexoSubida, i: int) -> Veiculo:
	var melhor: Veiculo = null
	var melhor_d := 16.0
	for r: Veiculo in _rivais():
		if r.estado != Veiculo.Estado.APOIADO:
			continue
		var d := r.global_position.distance_to(veiculo.global_position)
		if d > melhor_d:
			continue
		var j := sub.indice_estrada(r.global_position)
		if j < i or j > i + 12:
			continue   # só quem está logo à frente, no caminho
		melhor_d = d
		melhor = r
	return melhor


## Ângulo (rad) entre a frente do carro e o destino; positivo = destino à esquerda.
func _angulo_para(destino: Vector3) -> float:
	var frente := -veiculo.global_transform.basis.z
	var para := destino - veiculo.global_position
	frente.y = 0.0
	para.y = 0.0
	if para.length() < 0.1:
		return 0.0
	return atan2(frente.cross(para).y, frente.dot(para))


# ------------------------------------------------------------------ no ar

func _balistico(e: Dictionary) -> void:
	if veiculo.travado:
		return
	if veiculo.girando:
		# Lançado pela mola: gira sem controle; perto do alto abre o paraquedas e plana até a estrada
		if veiculo.linear_velocity.y < 4.0 and not veiculo.paraquedas_aberto:
			veiculo.alternar_paraquedas()
		return
	if OS.get_environment("TSC_SALTO_LOG") != "" and veiculo.complexo is ComplexoSubida and fmod(_t, 0.1) < _dt_ia:
		var bs: Vector3 = (veiculo.complexo as ComplexoSubida).borda_salto
		if veiculo.global_position.distance_to(bs) < 200.0:
			print("[VOO] %-12s pos=%s v=%s" % [veiculo.nome_piloto, str(veiculo.global_position.snapped(Vector3.ONE * 0.1)), str(veiculo.linear_velocity.snapped(Vector3.ONE * 0.1))])
	# Mantém o carro nivelado durante o salto
	var frente := -veiculo.global_transform.basis.z
	var inclinacao := asin(clampf(frente.y, -1.0, 1.0))
	if inclinacao > 0.3:
		e.acelerar = 1.0
	elif inclinacao < -0.3:
		e.freiar = 1.0
	# Pulo na crista da descida não conta: o paraquedas só abre depois de sair da rampa
	var cx := veiculo.complexo
	var depois_da_rampa := veiculo.saiu_da_rampa or (cx and cx.x_perfil(veiculo.global_position) > cx.perfil.comprimento_horizontal - 5.0)
	if not veiculo.paraquedas_ja_aberto and depois_da_rampa and veiculo.linear_velocity.y < _abre_com_vy and veiculo.tempo_no_ar > 0.8 \
			and _hora_de_abrir():
		veiculo.alternar_paraquedas()
		if rng.randf() < 0.25:
			_falar(FRASES_PARAQUEDAS[rng.randi() % FRASES_PARAQUEDAS.size()])
	elif not depois_da_rampa and not veiculo.paraquedas_aberto and not _desistiu_pouso and cx is ComplexoSubida and _caindo_da_estrada(cx as ComplexoSubida) and not _pulo_do_poco_basta(cx as ComplexoSubida):
		veiculo.alternar_paraquedas()
		if OS.get_environment("TSC_QUEDAS") != "":
			print("[SAIU] %s caiu da estrada em %s" % [veiculo.nome_piloto, str(veiculo.global_position.snapped(Vector3.ONE))])
	elif veiculo.paraquedas_ja_aberto and not veiculo.paraquedas_aberto and veiculo.tempo_no_ar > 0.5 and depois_da_rampa \
			and (not _mergulho or _fim_do_mergulho()):
		_mergulho = false
		_mergulho_pronto = _t + 1.5
		veiculo.alternar_paraquedas()   # velame murcho (ou fim do mergulho): reabre assim que der


## Poço no nível da pista (Extinction Day E2): o pulo do ejetor sozinho já leva até depois do portão? Então
## não abre o paraquedas — com ele aberto o bot passava alto por cima do começo do B e caía fora da estrada.
func _pulo_do_poco_basta(sub: ComplexoSubida) -> bool:
	var pl := sub.plataforma
	if not pl.sem_piso or pl.entrada_fundo <= 0.0:
		return false
	var p := veiculo.global_position
	var lp := pl.local(p)
	if lp.x < -8.0 or lp.x > pl.comprimento + 30.0 or absf(lp.y) > pl.largura_arena * 0.5:
		return false
	var vel := veiculo.linear_velocity
	var h := p.y - pl.piso_y
	var t_queda := (vel.y + sqrt(maxf(vel.y * vel.y + 19.6 * h, 0.0))) / 9.8
	return lp.x + vel.dot(pl.frente) * t_queda > pl.comprimento + 8.0


## Abre o paraquedas como os jogadores: depois do ápice, quando a razão distância/altura até o
## alvo chega a RAZAO_ABRIR (aberto no ápice, perto e alto demais, o carro passava por cima do alvo).
## Abre antes se estiver caindo rápido demais ou baixo (sobre o alvo ou sobre o terreno). Vale só com
## o alvo em linha reta (Climb to Death, Canyon Rush).
func _hora_de_abrir() -> bool:
	if _rota_i < _rota.size():
		return true   # Canyon Combat: o caminho é pelo vale, com curvas; abre cedo para poder virar (como o dono)
	var p := veiculo.global_position
	var c := alvo.centro_superior()
	var altura := p.y - c.y
	var caminho := _caminho_ao_alvo(p)
	if veiculo.linear_velocity.y < -26.0 or altura < ALTURA_ABRIR_MIN or caminho / maxf(altura, 0.5) >= _razao_abrir:
		return true
	return veiculo.terreno != null and p.y - veiculo.terreno.altura_em(p.x, p.z) < ALTURA_ABRIR_MIN


## Distância horizontal que falta até o alvo: pela rota do vale (Canyon Combat) ou em linha reta.
func _caminho_ao_alvo(p: Vector3) -> float:
	var c := alvo.centro_superior()
	if _rota_i >= _rota.size():
		return Vector2(c.x - p.x, c.z - p.z).length()
	var caminho := 0.0
	var ant := Vector3(p.x, 0.0, p.z)
	for k in range(_rota_i, _rota.size()):
		caminho += Vector2(_rota[k].x - ant.x, _rota[k].z - ant.z).length()
		ant = _rota[k]
	return caminho + Vector2(c.x - ant.x, c.z - ant.z).length()


## Mergulho (técnica dos jogadores): alto demais perto do alvo, fecha o paraquedas por um instante
## para despencar e reabre quando já caiu o bastante (ou está ficando baixo).
## Perto do alvo o mergulho é mais curto (reabre com menos queda e mais alto).
func _fim_do_mergulho() -> bool:
	var p := veiculo.global_position
	# Janela de muralha à frente (ponto da rota com altura): reabre a tempo de passar por ela
	var w := _ponto_rota(p)
	if w != Vector3.INF and w.y > 1.0:
		var sobra := p.y - w.y
		return sobra < 14.0 or Vector2(w.x - p.x, w.z - p.z).length() / maxf(sobra, 0.5) > 7.2 or veiculo.linear_velocity.y < -24.0
	var altura := p.y - alvo.centro_superior().y
	var dist := _caminho_ao_alvo(p)
	var perto := dist < FINAL_DIST
	return veiculo.linear_velocity.y < -(6.0 + minf(dist, 100.0) * 0.05) or altura < minf(30.0, 5.0 + dist * 0.25) \
		or dist / maxf(altura, 0.5) > (RAZAO_FINAL + 0.5 if perto else 3.4)


## Mergulho no meio do caminho (FINAL_DIST..320 m), um de cada vez.
func _quer_mergulhar(e: Dictionary, razao: float, altura: float, dist: float) -> bool:
	if razao >= RAZAO_MERGULHO or altura < 30.0 or dist < FINAL_DIST or dist > 320.0 or _t < _mergulho_pronto:
		return false
	_espiral = false
	_mergulhar_freando(e)
	return true


## Primeiro freia (S) até ~12 m/s, como o dono faz, e então fecha o paraquedas.
func _mergulhar_freando(e: Dictionary) -> void:
	if Vector2(veiculo.linear_velocity.x, veiculo.linear_velocity.z).length() > 12.0:
		e.freiar = 1.0
		return
	_mergulho = true
	veiculo.alternar_paraquedas()


## Final no alvo redondo como o dono pousa: vem sustentando (S) na medida para chegar em cima do
## alvo e, alto demais, freia e dá mergulhos curtos (fecha e reabre) até a altura bater. Nada de
## rodear em cima do alvo (era lento e o carro perdia altura demais e passava por baixo da borda).
func _final_redondo(e: Dictionary, razao: float, altura: float) -> void:
	_espiral = false
	if razao < RAZAO_FINAL and altura > 6.0:
		if _t >= _mergulho_pronto:
			_mergulhar_freando(e)
		else:
			e.freiar = 1.0
		return
	# Com S o carro anda ~5 m por metro de descida; neutro ~7,5 (o que mais estica)
	e.freiar = clampf((7.5 - razao) / 2.5, 0.0, 1.0)


func _planar(e: Dictionary) -> void:
	var p := veiculo.global_position
	# Climb to Death: caiu da estrada antes da rampa final — plana até um trecho mais baixo dela
	var sub := veiculo.complexo as ComplexoSubida
	if sub and not veiculo.saiu_da_rampa:
		# Plataforma sem chão: atravessa o poço mirando o vão do portão da saída, na altura de passar por ele
		if sub.plataforma.sem_piso:
			var pl := sub.plataforma
			var lp := pl.local(p)
			if lp.x < pl.comprimento + 70.0 and lp.x > -160.0 and absf(lp.y) < pl.largura_arena * 0.5 + 160.0 and p.y > pl.piso_y - 12.0:
				var portao := pl.pa(pl.comprimento + 14.0, 0.0, pl.piso_y + 1.0)
				# Primeiro alinha com o eixo do portão (senão entra de lado e bate na torre)
				if absf(lp.y) > pl.saida_largura * 0.3 and lp.x > pl.comprimento - 30.0:
					portao = pl.pa(lp.x + 6.0, 0.0, pl.piso_y + 1.0)
				var dist := Vector2(portao.x - p.x, portao.z - p.z).length()
				var sobra := p.y - (pl.piso_y + 3.0)
				if lp.x > pl.comprimento - 6.0:
					# Passou o portão: desce até o começo do trecho B (largo ali) e pousa
					var ib := sub.amostra_no_trecho(p, 1, -1, sub.indice_trecho("B", 130.0))
					portao = sub.amostra(sub.indice_adiante(ib, 30.0))
					dist = 0.0
					sobra = p.y - sub.amostra(ib).y - 1.5
				_apontar_ar(e, portao)
				if OS.get_environment("TSC_POCO_LOG") != "" and fmod(_t, 0.3) < _dt_ia:
					print("[POCO] %-12s local=%s y=%.1f sobra=%.1f dist=%.0f v=%s" % [veiculo.nome_piloto, str(lp.snapped(Vector2.ONE)), p.y, sobra, dist, str(veiculo.linear_velocity.snapped(Vector3.ONE))])
				if sobra > dist / 6.0 + 2.0:
					e.acelerar = 1.0   # alto demais: desce mais
				elif sobra < dist / 7.5:
					e.freiar = 1.0     # baixo: sustenta
				return
		var q := sub.ponto_pouso(p)
		if q != Vector3.INF:
			_apontar_ar(e, q)
			var dh := Vector2(q.x - p.x, q.z - p.z).length()
			if dh < 25.0:
				e.freiar = 1.0
			elif dh < (p.y - q.y) * 2.0:
				e.acelerar = 1.0
		elif not _desistiu_pouso and not sub.checkpoints.is_empty():
			# Nenhum trecho ao alcance: planar até o chão só perde tempo — fecha e volta ao checkpoint
			_desistiu_pouso = true
			veiculo.alternar_paraquedas()
		return
	var ponto := _ponto_rota(p)
	if ponto != Vector3.INF:
		_voar_rota(e, p, ponto)
		return
	var destino := alvo.centro_superior() + _mira
	var d := destino - p
	var dist_h := Vector2(d.x, d.z).length()
	if alvo.movel:
		# Antecipa o movimento do alvo pelo tempo estimado até a chegada
		destino = alvo.centro_futuro(dist_h / maxf(Vector2(veiculo.linear_velocity.x, veiculo.linear_velocity.z).length(), 8.0)) + _mira
		d = destino - p
		dist_h = Vector2(d.x, d.z).length()
	# Chegando: mira antes do centro, na direção em que vem — depois de tocar o carro ainda
	# escorrega uns metros (com a mira no centro ele parava na borda e caía)
	var vh3 := Vector3(veiculo.linear_velocity.x, 0.0, veiculo.linear_velocity.z)
	if dist_h < 120.0 and vh3.length() > 2.0 and not alvo.gravata:
		destino -= vh3.normalized() * minf(vh3.length() * 0.7, 9.0)
		d = destino - p
		dist_h = Vector2(d.x, d.z).length()
	# Alvo cercado (rede/jaula: só se entra por cima): mira por cima da borda até estar em cima dele;
	# lá dentro fecha o paraquedas e cai
	var cercado := alvo.forma == "jaula"
	if cercado:
		if dist_h > 5.0:
			destino.y += 11.0
		elif veiculo.paraquedas_aberto and p.y > alvo.centro_superior().y + 2.0 and vh3.length() < 12.0:
			_mergulho = true
			_mergulho_pronto = _t + 6.0
			veiculo.alternar_paraquedas()
			return
	var altura := p.y - destino.y
	var razao := dist_h / maxf(altura, 0.5)

	# Ataques no ar: velame de um rival abaixo, ou quem está parado numa zona boa do alvo.
	# Climb to Death não: lá a meta é chegar vivo (derrubar velames no salto final matava quase todos).
	if _vitima == null and altura > 25.0 and not _so_no_caminho:
		_tentar_atacar(_escolher_vitima_ar(p, altura, dist_h), 6.0, FRASES_AR, "ar")
	if _vitima == null and dist_h < 160.0 and not _so_no_caminho:
		_tentar_atacar(_escolher_vitima_alvo(), 12.0, FRASES_ALVO, "alvo")
	if _vitima:
		if _vitima.travado:
			# Pousar em cima de quem já está no alvo (tira ele da zona)
			destino = _vitima.global_position
		elif _vitima.paraquedas_aberto and altura > 20.0 and razao < 6.5:
			# Mergulha no velame: mira em cima da cobertura dele
			var cobertura := _vitima.paraquedas.global_position
			var dh := Vector2(cobertura.x - p.x, cobertura.z - p.z).length()
			_apontar_ar(e, cobertura)
			if p.y > cobertura.y + 1.0:
				e.acelerar = 1.0   # desce mais depressa (W)
				e.nitro = dh > 25.0 and not veiculo.travado
			else:
				_encerrar_ataque()   # passou por baixo: desiste
			return
		else:
			_encerrar_ataque()
		d = destino - p
		dist_h = Vector2(d.x, d.z).length()
		razao = dist_h / maxf(p.y - destino.y, 0.5)
	elif alvo.gravata:
		_planar_gravata(e, p)
		return

	_apontar_ar(e, destino)
	if OS.get_environment("TSC_BOT_LOG") != "" and dist_h < 300.0 and fmod(_t, 0.5) < _dt_ia:
		var c := alvo.centro_superior()
		var rel := p - c
		var lado := alvo.eixo.cross(Vector3.UP).normalized()
		print("[BOT] %-12s u=%6.1f w=%6.1f alt=%5.1f razao=%4.1f esp=%s v=%4.1f vy=%5.1f" % [veiculo.nome_piloto, rel.dot(alvo.eixo), rel.dot(lado), altura, razao, str(_espiral),
			Vector2(veiculo.linear_velocity.x, veiculo.linear_velocity.z).length(), veiculo.linear_velocity.y])
	if _pouso_lento and dist_h < 260.0:
		# Chegada devagar: quanto mais perto, menor a velocidade — S freia e sustenta. Só solta o freio
		# se estiver ficando baixo demais para alcançar o alvo
		var v_h := vh3.length()
		var v_quer := clampf(5.0 + dist_h * 0.09, 6.0, 26.0)
		if altura > 6.0 and razao < 4.2 and dist_h > 30.0 and _t >= _mergulho_pronto and not cercado:
			_mergulhar_freando(e)   # alto demais: mergulho curto
		elif v_h > v_quer and razao < 6.8:
			e.freiar = 1.0
		elif razao > 7.2:
			e.nitro = dist_h > 60.0 and not veiculo.travado
		elif razao < 4.8:
			e.acelerar = 0.6 if v_h < v_quer else 0.0
			e.freiar = 1.0 if v_h > v_quer else 0.0
		return
	if dist_h < FINAL_DIST:
		_final_redondo(e, razao, altura)
		return
	if _quer_mergulhar(e, razao, altura, dist_h):
		return   # alto demais para o que falta: freia, despenca um pouco e reabre
	if _espiral:
		# Perdendo altura em círculos até a rota voltar a fechar
		e.direcao = 1.0
		e.acelerar = 1.0
		if razao > 6.0 or altura < 10.0:
			_espiral = false
	elif razao < 3.0 and altura > 10.0 and dist_h > 320.0:
		_espiral = true   # perto do alvo quem perde altura é o mergulho (rodear era lento e errava)
	elif dist_h < 80.0:
		e.freiar = 1.0  # aproximação final devagar
	elif razao > PLANEIO_MAX:
		e.nitro = not veiculo.travado
	else:
		e.acelerar = clampf(((5.6 if _pouso_lento else 7.0) - razao) / 2.5, 0.0, 1.0)   # alvo redondo: planeio original (pouso lento: vem mais alto)


## Gravata: o meio é fino demais para chegar atravessado. O bot vai até um ponto de entrada na
## linha do comprimento (ponta mais perto) e desce ao longo dela seguindo uma "cenoura" que
## anda pelo eixo à frente dele (curva suave). Errar a distância assim cai nas faixas 4-3-2.
## Alto demais: orbita em volta do alvo perdendo altura, em vez de se afastar.
func _planar_gravata(e: Dictionary, p: Vector3) -> void:
	const ENTRADA := 60.0
	const CENOURA := 30.0
	var c := alvo.centro_superior()
	if alvo.movel:
		# Alvo sobre trilhos: mira onde ele vai estar quando o carro chegar
		var vh := maxf(Vector2(veiculo.linear_velocity.x, veiculo.linear_velocity.z).length(), 8.0)
		c = alvo.centro_futuro(Vector2(c.x - p.x, c.z - p.z).length() / vh)
	var rel := p - c
	rel.y = 0.0
	var dist := rel.length()
	var u := rel.dot(alvo.eixo)
	var lado := alvo.eixo.cross(Vector3.UP).normalized()
	var w := rel.dot(lado)
	var mira_u := _mira.dot(alvo.eixo)
	var altura := p.y - c.y
	if dist > 250.0 and absf(u) > 8.0:
		_lado_entrada = signf(u)
	_no_eixo = absf(w) < (45.0 if _no_eixo else 30.0)
	var destino: Vector3
	var caminho: float
	if _no_eixo:
		var cu := move_toward(u, mira_u, CENOURA)
		destino = c + alvo.eixo * cu
		caminho = p.distance_to(destino) + absf(cu - mira_u)
	else:
		# Quanto mais de lado, mais longe no eixo fica a entrada: a curva para cair na linha do
		# comprimento sai suave, em vez de 90° em cima da ponta (passava do eixo e caía do alvo)
		var entrada := ENTRADA + absf(w) * 0.7
		destino = c + alvo.eixo * _lado_entrada * entrada
		caminho = Vector2(destino.x - p.x, destino.z - p.z).length() + absf(entrada - mira_u * _lado_entrada)
	var razao := caminho / maxf(altura, 0.5)
	if _espiral:
		# Órbita de ~45 m em volta do alvo: mira um ponto do círculo um pouco à frente
		var radial := rel.normalized() if dist > 1.0 else lado
		var tangente := Vector3.UP.cross(radial)
		destino = c + (radial * 45.0 + tangente * 25.0).normalized() * 45.0
		_apontar_ar(e, destino)
		e.acelerar = 1.0
		if razao > 5.5 or altura < 12.0:
			_espiral = false
		return
	# Gravata sem mergulho: nas simulações a órbita pela linha do alvo pousava mais (mergulhar fazia
	# o carro chegar atravessado e escorregar da borda estreita)
	if razao < 3.2 and altura > 15.0:
		_espiral = true
	_apontar_ar(e, destino)
	if OS.get_environment("TSC_BOT_LOG") != "" and dist < 300.0 and fmod(_t, 0.5) < _dt_ia:
		print("[BOT] %-12s u=%6.1f w=%6.1f alt=%5.1f razao=%4.1f eixo=%s orb=%s v=%4.1f" % [veiculo.nome_piloto, u, w, altura, razao, str(_no_eixo), str(_espiral),
			Vector2(veiculo.linear_velocity.x, veiculo.linear_velocity.z).length()])
	if caminho < 55.0 and _no_eixo:
		e.freiar = 1.0   # final devagar
	elif razao > PLANEIO_MAX:
		e.nitro = not veiculo.travado
	else:
		e.acelerar = clampf((PLANEIO_ALVO - razao) / 2.5, 0.0, 1.0)


func _apontar_ar(e: Dictionary, destino: Vector3) -> void:
	var d := destino - veiculo.global_position
	var desejado := _rumo_seguro(atan2(-d.x, -d.z), Vector2(d.x, d.z).length())
	if _rota_pela_rampa and Veiculo.vento != Vector3.ZERO:
		# Vento de lado: aponta um pouco contra ele (caranguejando) para o caminho no chão ir reto ao destino
		var esq := Vector3(-cos(desejado), 0.0, sin(desejado))
		var vh := maxf(Vector2(veiculo.linear_velocity.x, veiculo.linear_velocity.z).length(), 12.0)
		desejado += asin(clampf(-Veiculo.vento.dot(esq) / vh, -0.5, 0.5))
	var erro := wrapf(desejado - veiculo.rumo, -PI, PI)
	e.direcao = clampf(-erro * 2.2 + _oscilacao(), -1.0, 1.0)


## Próximo ponto da rota do vale ainda não passado (Vector3.INF = rota acabou, vai direto ao alvo).
func _ponto_rota(p: Vector3) -> Vector3:
	var sub := veiculo.complexo as ComplexoSubida
	while _rota_i < _rota.size():
		var w := _rota[_rota_i]
		if _rota_pela_rampa and sub:
			# À frente no sentido do lançamento (a rampa final pode apontar para qualquer lado)
			if Vector3(w.x - p.x, 0.0, w.z - p.z).dot(sub.frente) > (4.0 if w.y > 1.0 else 30.0):
				return w
			_rota_i += 1
			continue
		var u_carro := veiculo.terreno.u_no_vale(p)
		if u_carro > veiculo.terreno.u_no_vale(w) + 8.0 and Vector2(w.x - p.x, w.z - p.z).length() > 35.0:
			return w
		_rota_i += 1
	return Vector3.INF


## Voo pela rota do vale: mira o próximo ponto e dosa a descida pelo caminho que ainda falta
## (ponto a ponto até o alvo), não pela linha reta — que atravessa as montanhas.
func _voar_rota(e: Dictionary, p: Vector3, ponto: Vector3) -> void:
	var c := alvo.centro_superior()
	var caminho := Vector2(ponto.x - p.x, ponto.z - p.z).length()
	var ant := ponto
	for k in range(_rota_i + 1, _rota.size()):
		caminho += Vector2(_rota[k].x - ant.x, _rota[k].z - ant.z).length()
		ant = _rota[k]
	caminho += Vector2(c.x - ant.x, c.z - ant.z).length()
	var razao := caminho / maxf(p.y - c.y, 0.5)
	_espiral = false
	_apontar_ar(e, ponto)
	if ponto.y > 1.0:
		# Ponto com altura (janela de muralha de gelo): dosa a descida para chegar nele nessa altura
		var d_h := Vector2(ponto.x - p.x, ponto.z - p.z).length()
		var sobra := p.y - ponto.y
		var r_j := d_h / maxf(sobra, 0.5)
		if sobra > 25.0 and r_j < 5.4 and d_h > 90.0 and _t >= _mergulho_pronto:
			_mergulhar_freando(e)   # alto demais até para descer com W: fecha, despenca e reabre
		elif sobra <= 0.5:
			e.freiar = 1.0   # já na altura (ou abaixo): sustenta o máximo
		elif r_j <= 13.75:
			# W desce mais (razão ~6,8 com tudo); solta à medida que a razão pedida se aproxima da neutra (~13,7)
			e.acelerar = 1.0 if r_j < 6.9 else clampf((22.0 - 1.6 * r_j) / (3.4 * r_j - 12.0), 0.0, 1.0)
		else:
			e.freiar = clampf((22.0 - 1.6 * r_j) / (9.0 - 0.8 * r_j), 0.0, 1.0)
		return
	if razao > PLANEIO_MAX:
		e.nitro = not veiculo.travado
	else:
		e.acelerar = clampf((PLANEIO_ALVO - razao) / 2.5, 0.0, 1.0)


## Olha o terreno à frente: se o rumo desejado bate numa montanha nos próximos segundos, abre
## o rumo para o lado (alternando, cada vez mais) até achar um caminho livre.
func _rumo_seguro(desejado: float, dist_destino: float) -> float:
	if veiculo.terreno == null or dist_destino < 70.0:
		return desejado   # chegada ao alvo: nada a desviar
	if _rumo_livre(desejado):
		return desejado
	for k in range(1, 8):
		for s: float in [1.0, -1.0]:
			var a := desejado + s * k * deg_to_rad(18.0)
			if _rumo_livre(a):
				return a
	return desejado


func _rumo_livre(rumo_a: float) -> bool:
	var p := veiculo.global_position
	var v := veiculo.linear_velocity
	var vh := maxf(Vector2(v.x, v.z).length(), 14.0)
	var f := Vector3(-sin(rumo_a), 0.0, -cos(rumo_a))
	# Só montanha conta: o chão do vale fica abaixo do topo do alvo e chegar baixo nele é
	# problema de dosar a descida, não de desviar
	var topo_alvo := alvo.centro_superior().y
	for t: float in [1.0, 2.0, 3.5, 5.0]:
		var q := p + f * vh * t
		var chao := veiculo.terreno.altura_em(q.x, q.z)
		if chao > topo_alvo and chao + 10.0 > p.y + minf(v.y, 0.0) * t:
			return false
	return true


## Rival de paraquedas aberto mais abaixo e por perto, sem me desviar demais do alvo.
func _escolher_vitima_ar(p: Vector3, altura: float, dist_h: float) -> Veiculo:
	var melhor: Veiculo = null
	var melhor_d := 70.0
	for r: Veiculo in _rivais():
		if not r.paraquedas_aberto:
			continue
		var c := r.paraquedas.global_position
		var desnivel := p.y - c.y
		var dh := Vector2(c.x - p.x, c.z - p.z).length()
		# Precisa dar para chegar em cima dele (planeio ~ 5:1) e ainda ter altura para o alvo
		if desnivel < 3.0 or dh > desnivel * 5.0 or dh > melhor_d:
			continue
		if (altura - desnivel) < 20.0 or dist_h / maxf(altura - desnivel, 1.0) > 7.5:
			continue
		melhor_d = dh
		melhor = r
	return melhor


## Rival parado numa zona de 3 pontos ou mais (o melhor deles).
func _escolher_vitima_alvo() -> Veiculo:
	var melhor: Veiculo = null
	var melhor_z := 2
	for r: Veiculo in _rivais():
		if not r.travado or r.relogio - r.ultimo_contato_alvo > 0.5:
			continue
		var z := alvo.zona_do_veiculo(r)
		if z > melhor_z:
			melhor_z = z
			melhor = r
	return melhor
