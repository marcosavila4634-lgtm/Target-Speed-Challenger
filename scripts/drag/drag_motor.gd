class_name DragMotor
extends RefCounted
## Arrancada de um carro no Drag Racing (dossiê, cap. 6), simulada em uma dimensão ao longo da
## faixa (a direção é automática): motor com curva de torque, neutro + seis marchas sem embreagem,
## limitador, aderência, nitro de descarga única, largada queimada e avaliação das trocas.
## Mesmos passos e entradas = mesmo tempo (reprodutível). Valores em jogo.json → drag.

signal engatou(marcha: int)
## Troca para cima avaliada: perfeita, boa, antecipada, atrasada ou critica.
signal trocou(de: int, para: int, avaliacao: String)
signal reduziu(de: int, para: int, excessiva: bool)
signal nitro_ligou
signal largou(avaliacao: String)
signal chegou_fim

const AVALIACOES := {
	"perfeita": "PERFEITA", "boa": "BOA", "antecipada": "ANTECIPADA", "atrasada": "ATRASADA", "critica": "CRÍTICA",
	"patinou": "PATINOU", "afogou": "AFOGOU", "queimada": "QUEIMADA",
}

# ---- Entradas (preenchidas pelo jogador ou pelo bot a cada passo)
var acelerador := 0.0
var nitro_pedido := false

# ---- Estado
var marcha := 0                  # 0 = neutro
var rpm := 900.0
var velocidade := 0.0            # m/s
var distancia := 0.0             # m percorridos desde a linha de largada
var tempo := 0.0                 # relógio da corrida (s)
var t_verde := INF               # instante planejado da luz verde (o semáforo sorteia antes)
var aderencia_atual := 1.0       # 0..1 (HUD): cai quando as rodas patinam
var patinando := false
var no_limitador := false
var nitro_ativo := false
var nitro_usado := false
var nitro_restante := 0.0
var nitro_total := 0.0
var nitro_marcha := -1           # marcha em que o nitro foi ligado (-1 = não usou)
var chegou := false
var paraquedas := false          # paraquedas de frenagem aberto (depois da chegada)

# ---- Resultado
var t_movimento := -1.0          # quando o carro começou a andar
var t_chegada := -1.0
var velocidade_chegada := 0.0
var queimada := false
var antecipacao := 0.0           # segundos antes da verde (só com queimada)
var largada := ""                # avaliação da largada (perfeita, boa, patinou, afogou)
var rpm_largada := 0.0
var trocas: Array = []           # [{de, para, rpm, avaliacao}]
var reducoes: Array = []         # [{de, para, rpm, excessiva}]
var desgaste_extra := 0.0        # % além do básico
var limitador_penalizado := false
var erros: Array[String] = []

# ---- Parâmetros
var _c: Dictionary = {}
var _marchas: Array = []
var _torque: Array = []
var _a_base := 5.0               # m/s² no pico de torque na marcha de referência
var _a_tracao := 7.0
var _rolamento := 0.15
var _nitro_acel := 3.2
var _arrasto := 0.0008
var _k_rpm: Array[float] = []    # rpm por m/s em cada marcha (índice 1..6)
var _lenta := 900.0
var _limite := 8000.0

# ---- Internos
var _corte := 0.0                # sem tração durante a troca
var _retencao := 1.0
var _retencao_ate := -1.0
var _embreagem_rpm := 0.0
var _embreagem_t := 99.0
var _patinar_ate := -1.0
var _limitador_t := 0.0
var _penalidade := 1.0
var _batida := 0.0               # corte do limitador (rpm cai e volta)


## `ajustes` = acerto do jogador para o drag (Progresso.ajustes_drag): relação de cada marcha,
## relação final, pressão dos pneus e força do nitro. Vazio = de fábrica.
func _init(dados: Dictionary, ajustes: Dictionary = {}) -> void:
	_c = Config.valor("drag", {})
	var fabrica: Array = _c.get("marchas", [3.1, 2.15, 1.62, 1.28, 1.05, 0.86])
	var final := float(ajustes.get("final", 1.0))
	_marchas = []
	var lista: Array = ajustes.get("marchas", fabrica)
	for i in fabrica.size():
		_marchas.append(float(lista[i] if i < lista.size() else fabrica[i]) * final)
	_torque = _c.get("torque", [[900, 0.3], [8000, 1.0]])
	_lenta = float(_c.get("rpm_lenta", 900))
	_limite = float(_c.get("rpm_limite", 8000))
	rpm = _lenta
	var ref := float(_c.get("marcha_referencia", 1.62))
	# Mesma receita do Target Flight (aceleracao/velocidade do veículo com upgrades), escalada para o drag
	var fator_peso := float(dados.get("massa_fabrica", dados.get("massa", 1000))) / float(dados.get("massa", 1000))
	_a_base = float(dados.get("aceleracao", 5.0)) * fator_peso * float(_c.get("potencia_mult", 1.6))
	var tracao := str(dados.get("tracao", "traseira"))
	_a_tracao = float(dados.get("aderencia", 1.1)) * 9.8 * float(_c.get("tracao_fracao", {}).get(tracao, 0.6)) * float(_c.get("aderencia_mult", 1.0))
	# Pneus: traseiro murcho agarra mais e rola pior; dianteiro cheio rola melhor (efeitos no jogo.json)
	var pneus: Dictionary = _c.get("ajustes", {}).get("pneus", {})
	var p_t := float(ajustes.get("pneu_traseiro", pneus.get("traseiro_padrao", 22)))
	var p_d := float(ajustes.get("pneu_dianteiro", pneus.get("dianteiro_padrao", 32)))
	var menos_ar := float(pneus.get("traseiro_padrao", 22)) - p_t
	_a_tracao *= 1.0 + menos_ar * float(pneus.get("aderencia_por_psi", 0.012))
	_rolamento = float(_c.get("rolamento", 0.15)) + menos_ar * float(pneus.get("rolamento_por_psi", 0.01)) \
		- (p_d - float(pneus.get("dianteiro_padrao", 32))) * float(pneus.get("rolamento_dianteiro_por_psi", 0.004))
	_rolamento = maxf(_rolamento, 0.05)
	# Velocidade no limitador: a 6ª de fábrica leva o carro a vtop; relações mais longas vão além
	var vtop := float(dados.get("velocidade_max_kmh", 160)) / 3.6 * float(_c.get("vmax_mult", 1.3))
	var ultima_fabrica := float(fabrica[fabrica.size() - 1])
	_k_rpm = [0.0]
	for r: float in _marchas:
		_k_rpm.append(_limite * r / (vtop * ultima_fabrica))
	# Arrasto do carro (não muda com o acerto): em 6ª de fábrica quase chega ao limitador
	_arrasto = _a_base * torque(_limite) * (ultima_fabrica / ref) / (vtop * vtop) * 0.97
	_c["_ref"] = ref
	# Nitro: carga e força do carro (upgrades) relativas ao padrão; o acerto troca força por duração
	var forca := float(ajustes.get("nitro", 1.0))
	var f_upgrade := float(dados.get("nitro_aceleracao", Config.valor("fisica.nitro_aceleracao", 9.0))) / float(Config.valor("fisica.nitro_aceleracao", 9.0))
	_nitro_acel = float(_c.get("nitro_aceleracao", 3.2)) * f_upgrade * forca
	nitro_restante = float(dados.get("nitro_duracao", Config.valor("fisica.nitro_duracao", 4.0))) / forca
	nitro_total = nitro_restante


## Fração do torque máximo na rotação (curva do jogo.json).
func torque(r: float) -> float:
	if r <= float(_torque[0][0]):
		return float(_torque[0][1])
	for i in range(1, _torque.size()):
		var a: Array = _torque[i - 1]
		var b: Array = _torque[i]
		if r <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (r - float(a[0])) / (float(b[0]) - float(a[0])))
	return float(_torque[_torque.size() - 1][1])


func rpm_nas_rodas(m: int, v: float) -> float:
	return v * _k_rpm[m] if m >= 1 else 0.0


func velocidade_kmh() -> float:
	return velocidade * 3.6


func marchas_total() -> int:
	return _marchas.size()


# ------------------------------------------------------------------ comandos

func subir_marcha() -> void:
	if chegou or marcha >= _marchas.size():
		return
	if marcha == 0:
		_engatar_primeira()
		return
	var av := avaliar_troca(rpm)
	trocas.append({"de": marcha, "para": marcha + 1, "rpm": rpm, "avaliacao": av})
	if av == "critica":
		desgaste_extra += 0.5
	marcha += 1
	_corte = float(_c.get("tempo_troca", 0.12))
	_retencao = float(_c.get("retencao", {}).get(av, 1.0))
	_retencao_ate = tempo + _corte + float(_c.get("retencao_s", 0.9))
	trocou.emit(marcha - 1, marcha, av)


func reduzir_marcha() -> void:
	if chegou or marcha <= 0:
		return
	var nova := marcha - 1
	var r := rpm_nas_rodas(nova, velocidade)
	var excessiva := nova >= 1 and r > _limite + 150.0
	reducoes.append({"de": marcha, "para": nova, "rpm": r, "excessiva": excessiva})
	if excessiva:
		# Erro grave: desgaste e potência menor até o fim da tentativa
		desgaste_extra += 1.5
		_penalidade *= 0.95
		erros.append("Redução excessiva (%d→%d)" % [marcha, nova])
	marcha = nova
	_corte = float(_c.get("tempo_troca", 0.12))
	reduziu.emit(nova + 1, nova, excessiva)


## Avaliação da troca para cima pela rotação no instante do pedido.
func avaliar_troca(r: float) -> String:
	var faixa: Array = _c.get("faixa_ideal", [6800, 7500])
	if absf(r - float(_c.get("centro_perfeito", 7150))) <= float(_c.get("tolerancia_perfeita", 160)):
		return "perfeita"
	if r >= float(faixa[0]) and r <= float(faixa[1]):
		return "boa"
	if r < float(faixa[0]):
		return "antecipada" if r >= float(faixa[0]) - float(_c.get("antecipada_ate", 1500)) else "critica"
	# Acima da faixa: atrasada; batendo no limitador há um tempo, crítica
	return "critica" if _limitador_t > 0.5 else "atrasada"


func _engatar_primeira() -> void:
	marcha = 1
	_embreagem_rpm = rpm
	_embreagem_t = 0.0
	if t_movimento >= 0.0:
		engatou.emit(1)   # voltou do neutro andando: não é largada
		return
	rpm_largada = rpm
	var ideal: Array = _c.get("largada_ideal", [4200, 5600])
	var lo := float(ideal[0])
	var hi := float(ideal[1])
	if rpm > hi:
		largada = "patinou"
		_patinar_ate = tempo + float(_c.get("embreagem_s", 0.55)) * (1.4 + clampf((rpm - hi) / 1500.0, 0.0, 1.0))
	elif rpm < lo:
		largada = "afogou"
	else:
		var meio := absf(rpm - (lo + hi) * 0.5) / ((hi - lo) * 0.5)
		largada = "perfeita" if meio < 0.4 else "boa"
	engatou.emit(1)


# ------------------------------------------------------------------ simulação

func passo(dt: float) -> void:
	tempo += dt
	if chegou:
		# Depois da chegada: tira o pé e freia até parar
		nitro_ativo = false
		acelerador = 0.0
		var freio := float(_c.get("frenagem_desacel", 4.5))
		if paraquedas:
			freio += float(_c.get("paraquedas_desacel", 5.0)) * clampf(velocidade / 30.0, 0.3, 1.5)
		velocidade = maxf(velocidade - freio * dt, 0.0)
		distancia += velocidade * dt
		var alvo := maxf(rpm_nas_rodas(marcha, velocidade), _lenta)
		rpm = move_toward(rpm, alvo, 5000.0 * dt)
		no_limitador = false
		patinando = false
		return

	# ---- Nitro: descarga única, não desliga depois de aberto
	if nitro_pedido and not nitro_usado and nitro_restante > 0.0:
		nitro_usado = true
		nitro_ativo = true
		nitro_marcha = marcha
		if marcha == 0 or tempo < t_verde:
			desgaste_extra += 1.0
			erros.append("Nitro em neutro" if marcha == 0 else "Nitro antes da verde")
		nitro_ligou.emit()
	if nitro_ativo:
		nitro_restante -= dt
		if nitro_restante <= 0.0:
			nitro_restante = 0.0
			nitro_ativo = false

	var a := 0.0
	patinando = false
	aderencia_atual = 1.0
	if marcha == 0:
		# Neutro: motor livre, o carro só rola (acelerar em neutro é permitido)
		var alvo := _lenta + (_limite + 400.0 - _lenta) * acelerador
		var taxa := float(_c.get("subida_neutro_rpm_s", 9000)) if alvo > rpm else float(_c.get("queda_neutro_rpm_s", 4000))
		rpm = move_toward(rpm, alvo, taxa * dt)
		no_limitador = rpm >= _limite
		if no_limitador:
			rpm = _limite - 300.0   # corte: bate e volta
		a = -_rolamento if velocidade > 0.0 else 0.0
	else:
		var r_rodas := rpm_nas_rodas(marcha, velocidade)
		var r := maxf(r_rodas, _lenta)
		if _embreagem_t < float(_c.get("embreagem_s", 0.55)):
			# Largada: a rotação cai do giro de engate até a das rodas enquanto os pneus "mordem"
			_embreagem_t += dt
			var f := clampf(_embreagem_t / float(_c.get("embreagem_s", 0.55)), 0.0, 1.0)
			r = maxf(r, lerpf(_embreagem_rpm, r_rodas, f * f))
		no_limitador = r >= _limite
		r = minf(r, _limite)
		var ref := float(_c["_ref"])
		var a_motor := _a_base * torque(r) * (float(_marchas[marcha - 1]) / ref) * acelerador
		a_motor *= _penalidade
		if tempo < _retencao_ate:
			a_motor *= _retencao
		if no_limitador and acelerador > 0.5:
			# Limitador cortando a ignição; muito tempo nele reduz a potência até o fim
			_limitador_t += dt
			a_motor *= 0.3
			_batida = fmod(_batida + dt * 11.0, 1.0)
			r -= 280.0 * (1.0 - _batida)
			if _limitador_t > float(_c.get("limitador_s", 2.0)) and not limitador_penalizado:
				limitador_penalizado = true
				_penalidade *= float(_c.get("limitador_penalidade", 0.9))
				desgaste_extra += 1.0
				erros.append("Limitador por mais de %.0f s" % float(_c.get("limitador_s", 2.0)))
		else:
			_limitador_t = 0.0
		if _corte > 0.0:
			_corte -= dt
			a_motor = 0.0
		if nitro_ativo and acelerador > 0.1:
			a_motor += _nitro_acel
		var util := minf(a_motor, _a_tracao)
		if tempo < _patinar_ate and a_motor > 0.1:
			# Largada alta demais: as rodas giram em falso e a força entregue cai
			util *= float(_c.get("patinada_fator", 0.8))
			aderencia_atual = float(_c.get("patinada_fator", 0.8))
			patinando = true
		elif a_motor > _a_tracao * 1.1:
			# Força demais para o pneu (nitro em marcha baixa): patina um pouco
			util *= 0.84
			aderencia_atual = 0.84
			patinando = true
		a = util - _rolamento - _arrasto * velocidade * velocidade
		if patinando:
			r = minf(r + 900.0, _limite)   # rodas girando em falso: o giro sobe
		rpm = move_toward(rpm, r, 30000.0 * dt)

	var antes := distancia
	velocidade = maxf(velocidade + a * dt, 0.0)
	distancia += velocidade * dt
	if t_movimento < 0.0 and distancia >= float(_c.get("movimento_queimada_m", 0.15)):
		t_movimento = tempo
		if t_movimento < t_verde:
			queimada = true
			antecipacao = t_verde - t_movimento
			largada = "queimada"
		largou.emit(largada)
	var fim := float(_c.get("distancia_m", 201.168))
	if distancia >= fim and antes < fim:
		# Instante exato em que cruzou a linha (entre dois passos)
		t_chegada = tempo - dt * (distancia - fim) / maxf(distancia - antes, 0.0001)
		velocidade_chegada = velocidade
		chegou = true
		nitro_ativo = false
		chegou_fim.emit()


# ------------------------------------------------------------------ resultado

func reacao() -> float:
	return t_movimento - t_verde if t_movimento >= 0.0 else INF


## Tempo medido: da luz verde até cruzar a chegada (a reação faz parte).
func tempo_medido() -> float:
	return t_chegada - t_verde if chegou else INF


func tempo_percurso() -> float:
	return t_chegada - t_movimento if chegou else INF


func penalidade() -> float:
	if not queimada or not chegou:
		return 0.0
	return tempo_medido() * (float(_c.get("queimada_base", 0.2)) + float(_c.get("queimada_por_segundo", 0.1)) * antecipacao)


func tempo_final() -> float:
	return tempo_medido() + penalidade() if chegou else INF


func desgaste_total() -> float:
	return float(_c.get("desgaste_basico", 1.0)) + minf(desgaste_extra, float(_c.get("desgaste_extra_max", 5.0)))


## Avaliação da reação (sem sinal sonoro do instante perfeito; só texto e cor).
static func avaliar_reacao(r: float) -> String:
	if r < 0.0:
		return "queimada"
	if r <= 0.2:
		return "perfeita"
	if r <= 0.35:
		return "boa"
	return "atrasada"


## Desempenho previsto (garagem): arrancada perfeita — largada no meio da janela, reação 0,15 s,
## trocas no centro perfeito e nitro na `nitro_marcha`. {zero_cem, oitavo, vel_final, vel_max} (s, km/h).
static func prever(dados: Dictionary, ajustes: Dictionary = {}, nitro_marcha := 2) -> Dictionary:
	var c: Dictionary = Config.valor("drag", {})
	var m := DragMotor.new(dados, ajustes)
	m.t_verde = 0.5
	var ideal: Array = c.get("largada_ideal", [4200, 5600])
	var larg := (float(ideal[0]) + float(ideal[1])) * 0.5
	var troca := float(c.get("centro_perfeito", 7300))
	var lenta := float(c.get("rpm_lenta", 900))
	var limite := float(c.get("rpm_limite", 8000))
	var dt := 1.0 / 120.0
	var zero_cem := INF
	while not m.chegou and m.tempo < 30.0:
		if m.marcha == 0:
			m.acelerador = clampf((larg - lenta) / (limite + 400.0 - lenta), 0.0, 1.0)
			if m.tempo >= m.t_verde + 0.15:
				m.subir_marcha()
		else:
			m.acelerador = 1.0
			m.nitro_pedido = m.marcha == nitro_marcha
			if m.marcha < m.marchas_total() and m.rpm >= troca and m.velocidade > 2.0:
				m.subir_marcha()
		m.passo(dt)
		if zero_cem == INF and m.velocidade >= 100.0 / 3.6:
			zero_cem = m.tempo - m.t_movimento
	return {"zero_cem": zero_cem, "oitavo": m.tempo_percurso(), "vel_final": m.velocidade_chegada * 3.6,
		"vel_max": limite / m._k_rpm[m.marchas_total()] * 3.6}
