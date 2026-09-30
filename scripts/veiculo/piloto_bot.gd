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
var _ultrap_t := 0.0
var _ultrap_decidir := 0.0
var _vontade_ultrapassar := 0.6
var _so_no_caminho := false   # Climb to Death: missão é subir; só empurra quem estiver no caminho

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
	_so_no_caminho = veiculo.complexo is ComplexoSubida
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
	var vel_mult := float(_perso.get("velocidade", 1.0)) * float(meta.get("velocidade", 1.0))
	ACEL_LATERAL *= vel_mult
	VEL_PLATAFORMA *= vel_mult
	_vel_estrada *= vel_mult * rng.randf_range(0.93, 1.07)   # ritmo próprio: uns alcançam os outros
	_erro_volante *= float(_perso.get("erro_volante", 1.0))
	_vontade_ultrapassar = float(_perso.get("ultrapassa", 0.6))
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
	var mira: Array = nivel.get("mira", [0.55, 0.97])
	var bonus := float(_perso.get("mira", 0.0))
	_mira = alvo.erro_mira(clampf(rng.randf_range(float(mira[0]), float(mira[1])) + bonus, 0.05, 1.0), rng)
	_lado_entrada = 1.0 if rng.randf() < 0.5 else -1.0
	_no_eixo = false
	_rota = veiculo.terreno.rota_vale() if veiculo.terreno else ([] as Array[Vector3])
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
	_encerrar_ataque()
	_ultrap_t = 0.0
	_parado_t = 0.0
	_re_t = 0.0
	_girar_t = 0.0
	_tentativa = 0
	_espiral = false


func _physics_process(delta: float) -> void:
	if not ativo or veiculo == null or veiculo.eliminado:
		return
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
	match veiculo.estado:
		Veiculo.Estado.APOIADO:
			_dirigir(e, delta)
		Veiculo.Estado.BALISTICO:
			_balistico(e)
		Veiculo.Estado.PLANEIO:
			_planar(e)


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
		if not meu.is_empty() and meu.distancia < 4.5:
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
	# Freio de emergência: se daqui a 0,8 s o carro estaria na boca de um buraco, tira o pé,
	# dá ré (é o único "freio") e esterça para longe dele
	var previsto := p + veiculo.linear_velocity * 0.8
	var b: Dictionary = arena.buraco_mais_perto(previsto)
	if not b.is_empty() and b.distancia < 1.5 and velocidade > 3.0:
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
	var v := veiculo.linear_velocity.length()
	var falta := sub.progresso_amostra(sub.fim_do_trecho(i)) - sub.progresso_amostra(i)
	var perto_salto := sub.trecho_de(i) == 1 and falta < 130.0
	var perto_final := sub.trecho_de(i) == 2 and falta < 180.0
	var chegando_plataforma := sub.trecho_de(i) == 0 and falta < 70.0
	var meia := sub.largura_em(i) * 0.5 - 1.6
	var alvo_lat := _faixa
	if perto_salto or perto_final:
		alvo_lat = 0.0
		_encerrar_ataque()
	else:
		# Missão principal: subir e chegar ao alvo. Derrubar é secundário: só quem está no caminho,
		# sem ir para a beirada e sem perder velocidade por isso
		var meu_lat := (p - sub.amostra(i)).dot(sub.lateral_em(i))
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
	if perto_salto or perto_final or chegando_plataforma:
		_ultrap_t = 0.0
	else:
		alvo_lat = _ultrapassar(sub, i, alvo_lat)
	# Perto da beirada (empurrado ou abrindo demais): volta para o meio antes de qualquer coisa
	var meu := (p - sub.amostra(i)).dot(sub.lateral_em(i))
	var na_beirada := absf(meu) > meia + 0.4
	if na_beirada:
		alvo_lat = 0.0
		_encerrar_ataque()
	alvo_lat = clampf(alvo_lat, -meia, meia)
	# Chegando no salto: mira bem longe no eixo e segura o volante firme — o tranco do ponto de
	# aceleração vai para onde o carro aponta; torto, ele atravessa o vão de lado e cai
	var olhar := 30.0 if perto_salto else clampf(9.0 + v * 0.6, 9.0, 35.0)
	var k := sub.indice_adiante(i, olhar)
	var erro_antes := _erro_volante
	if perto_salto:
		_erro_volante = 0.0
	_apontar(e, sub.amostra(k) + sub.lateral_em(k) * alvo_lat, 2.6 if na_beirada else 2.2)
	_erro_volante = erro_antes
	e.acelerar = 0.6 if na_beirada else 1.0
	if not perto_salto:
		# Velocidade de curva conservadora: pouca aderência e, rápido, o volante vira menos
		var v_max := sqrt(ACEL_LATERAL / maxf(sub.curvatura_adiante(i, v * 2.5 + 25.0), 0.0005))
		if v > v_max * 1.15:
			e.acelerar = 0.0
			e.re = 1.0
		elif v > v_max:
			e.acelerar = 0.0
	# Carro logo à frente na mesma faixa: tira o pé em vez de bater nele por trás (a pancada
	# joga um dos dois para fora da estrada — e pode ser este)
	if not perto_salto and _ultrap_t <= 0.0 and _carro_na_frente(sub, i, meu):
		e.acelerar = minf(e.acelerar, 0.35)
	# Teto de velocidade na estrada sem cerca (nível do bot): a vida vem primeiro. Ultrapassando,
	# puxa um pouco acima para conseguir passar.
	if not perto_salto and v > _vel_estrada * (1.15 if _ultrap_t > 0.0 else 1.0):
		e.acelerar = 0.0   # só tira o pé: frear de ré em alta velocidade faz o carro atravessar e cair
	if chegando_plataforma and v > VEL_PLATAFORMA * 1.4:
		e.acelerar = 0.0
		e.re = 1.0 if v > VEL_PLATAFORMA * 1.8 else 0.0
	if _usa_nitro and (perto_final or (perto_salto and v < 28.0)):
		e.nitro = true
	if _usa_ejetor and not _ejetou and sub.x_perfil(p) > sub.perfil.comprimento_horizontal - 4.0 and veiculo.ejetor_disponivel():
		_ejetou = true
		veiculo.pedir_ejetor()


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
	var dt := get_physics_process_delta_time()
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
	# Passa pelo lado oposto ao dele (ou pelo que tiver mais espaço)
	var lat_dele := (frente.global_position - sub.amostra(i)).dot(l)
	var lado := -signf(lat_dele) if absf(lat_dele) > 0.4 else (1.0 if rng.randf() < 0.5 else -1.0)
	if _faixa_ocupada(t, l, p, meu, lado * pista, -6.0, 18.0):
		lado = -lado
		if _faixa_ocupada(t, l, p, meu, lado * pista, -6.0, 18.0):
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
	if not veiculo.paraquedas_ja_aberto and depois_da_rampa and veiculo.linear_velocity.y < _abre_com_vy and veiculo.tempo_no_ar > 0.8:
		veiculo.alternar_paraquedas()
		if rng.randf() < 0.25:
			_falar(FRASES_PARAQUEDAS[rng.randi() % FRASES_PARAQUEDAS.size()])
	elif not depois_da_rampa and not veiculo.paraquedas_aberto and cx is ComplexoSubida and _caindo_da_estrada(cx as ComplexoSubida):
		veiculo.alternar_paraquedas()
	elif veiculo.paraquedas_ja_aberto and not veiculo.paraquedas_aberto and veiculo.tempo_no_ar > 0.5 and depois_da_rampa:
		veiculo.alternar_paraquedas()   # velame murcho: reabre assim que o bloqueio deixar


func _planar(e: Dictionary) -> void:
	var p := veiculo.global_position
	# Climb to Death: caiu da estrada antes da rampa final — plana até um trecho mais baixo dela
	var sub := veiculo.complexo as ComplexoSubida
	if sub and not veiculo.saiu_da_rampa:
		var q := sub.ponto_pouso(p)
		if q != Vector3.INF:
			_apontar_ar(e, q)
			var dh := Vector2(q.x - p.x, q.z - p.z).length()
			if dh < 25.0:
				e.freiar = 1.0
			elif dh < (p.y - q.y) * 2.0:
				e.acelerar = 1.0
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
	var altura := p.y - destino.y
	var razao := dist_h / maxf(altura, 0.5)

	# Ataques no ar: velame de um rival abaixo, ou quem está parado numa zona boa do alvo
	if _vitima == null and altura > 25.0:
		_tentar_atacar(_escolher_vitima_ar(p, altura, dist_h), 6.0, FRASES_AR, "ar")
	if _vitima == null and dist_h < 160.0:
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
	if OS.get_environment("TSC_BOT_LOG") != "" and dist_h < 300.0 and fmod(_t, 0.5) < get_physics_process_delta_time():
		var c := alvo.centro_superior()
		var rel := p - c
		var lado := alvo.eixo.cross(Vector3.UP).normalized()
		print("[BOT] %-12s u=%6.1f w=%6.1f alt=%5.1f razao=%4.1f esp=%s v=%4.1f vy=%5.1f" % [veiculo.nome_piloto, rel.dot(alvo.eixo), rel.dot(lado), altura, razao, str(_espiral),
			Vector2(veiculo.linear_velocity.x, veiculo.linear_velocity.z).length(), veiculo.linear_velocity.y])
	if _espiral:
		# Perdendo altura em círculos até a rota voltar a fechar
		e.direcao = 1.0
		e.acelerar = 1.0
		if razao > 6.0 or altura < 10.0:
			_espiral = false
	elif razao < 3.0 and altura > 10.0:
		_espiral = true
	elif dist_h < 80.0:
		e.freiar = 1.0  # aproximação final devagar
	elif razao > PLANEIO_MAX:
		e.nitro = not veiculo.travado
	else:
		e.acelerar = clampf((7.0 - razao) / 2.5, 0.0, 1.0)   # alvo redondo: planeio original


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
	if razao < 3.2 and altura > 15.0:
		_espiral = true
	_apontar_ar(e, destino)
	if OS.get_environment("TSC_BOT_LOG") != "" and dist < 300.0 and fmod(_t, 0.5) < get_physics_process_delta_time():
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
	var erro := wrapf(desejado - veiculo.rumo, -PI, PI)
	e.direcao = clampf(-erro * 2.2 + _oscilacao(), -1.0, 1.0)


## Próximo ponto da rota do vale ainda não passado (Vector3.INF = rota acabou, vai direto ao alvo).
func _ponto_rota(p: Vector3) -> Vector3:
	while _rota_i < _rota.size():
		var w := _rota[_rota_i]
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
