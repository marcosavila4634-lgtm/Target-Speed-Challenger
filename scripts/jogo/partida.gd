extends Node3D
## Partida de Target Flight (dossiê, cap. 4):
## Apresentação (só na 1ª etapa) → Contagem → Etapa ativa → Estabilização → Resultado da etapa
## → próxima etapa ou Resultado final (com desempate e morte súbita).

enum Fase { CARREGANDO, APRESENTACAO, CONTAGEM, ATIVA, ESTABILIZACAO, RESULTADO, FINAL }

var fase := Fase.CARREGANDO
var perfil: PerfilRampa
var terreno: Terreno
var complexos: Array[ComplexoLancamento] = []
var alvo: Alvo
var camera: CameraJogo
var hud: Hud

## Cada participante: {nome, equipe, veiculo, controle, pontos: Array[int], zonas5, explosoes, jogador}
var participantes: Array[Dictionary] = []
var jogador: Dictionary = {}

var etapas_cfg: Array = []
var total_etapas := 4
var etapa_idx := 0
var equipes_qtd := 4
var equipes_ativas: Array[int] = []
var morte_subita := false
var tempo_modo := "etapa"
var tempo_etapa := 180.0
var tempo_restante := 0.0
var tempo_fase := 0.0
var estab_t := 0.0
var _zona_jogador := -1
var _espectando := false
var _t_eliminado := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	hud = Hud.new()
	add_child(hud)
	hud.pedido_continuar.connect(_despausar)
	hud.pedido_menu.connect(_ir_menu)
	hud.pedido_reiniciar.connect(_reiniciar)
	hud.carregando("GERANDO O CÂNION...")
	await get_tree().process_frame
	await get_tree().process_frame
	_construir_mundo()
	_criar_participantes()
	var som_ambiente := SomAmbiente.new()
	add_child(som_ambiente)
	som_ambiente.montar(complexos)
	Audio.musica("partida")
	hud.esconder_carregando()
	if Sessao.teste_automatico:
		Engine.time_scale = 4.0
	_iniciar_etapa(0)
	if OS.get_environment("TSC_FOTO_FINAL") != "":
		_foto_final(OS.get_environment("TSC_FOTO_FINAL"))
	elif OS.get_environment("TSC_FOTO_PARAQUEDAS") != "":
		_foto_paraquedas(OS.get_environment("TSC_FOTO_PARAQUEDAS"))


## Sequência de fotos da abertura do paraquedas: carro do jogador parado no ar, câmera de lado.
func _foto_paraquedas(pasta: String) -> void:
	hud.visible = false
	var v: Veiculo = jogador.veiculo
	var f := complexos[0].frente
	var pos := alvo.centro_base + Vector3.UP * 120.0 - f * 250.0
	await get_tree().create_timer(0.5).timeout
	v.preparar(Transform3D(Basis.looking_at(f, Vector3.UP), pos))
	v.rumo = atan2(-f.x, -f.z)
	v.paraquedas_aberto = true
	v.paraquedas.abrir()
	var lado := f.cross(Vector3.UP).normalized()
	camera.podio(pos + Vector3.UP * 5.0, pos + lado * 16.0 + Vector3.UP * 7.0 - f * 6.0)
	for alvo_s: float in [0.1, 0.3, 0.45, 0.6, 0.8, 1.05, 1.4, 2.2]:
		while v.paraquedas._t < alvo_s:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/pq_%04d.png" % [pasta, int(alvo_s * 1000)])
	get_tree().quit()


## Captura da comemoração sem jogar a partida: pontos sorteados, equipe AZUL vence.
func _foto_final(arquivo: String) -> void:
	for p in participantes:
		p.pontos = [_rng.randi_range(0, 5), _rng.randi_range(0, 5), 5 if p.equipe == 0 else 0, 0]
	_mostrar_final(range(equipes_qtd))
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png(arquivo)
	get_tree().quit()


# ------------------------------------------------------------------ montagem

func _construir_mundo() -> void:
	add_child(Ambiente.new())
	perfil = PerfilRampa.new()
	terreno = Terreno.new()
	terreno.name = "Terreno"
	add_child(terreno)
	terreno.gerar(perfil)
	equipes_qtd = clampi(int(Config.valor("partida.equipes", 4)), 2, 4)
	for i in equipes_qtd:
		var c := ComplexoLancamento.new()
		add_child(c)
		c.montar(i, perfil, terreno)
		complexos.append(c)
	alvo = Alvo.new()
	alvo.terreno = terreno
	alvo.name = "Alvo"
	add_child(alvo)
	camera = CameraJogo.new()
	camera.terreno = terreno
	add_child(camera)
	etapas_cfg = Config.valor("etapas", [])
	total_etapas = clampi(mini(int(Config.valor("partida.etapas", 4)), etapas_cfg.size()), 1, 8)
	tempo_modo = Sessao.tempo_modo
	tempo_etapa = float(Sessao.tempo_segundos)
	if tempo_modo == "partida":
		tempo_restante = tempo_etapa


func _criar_participantes() -> void:
	var por_equipe := clampi(Sessao.jogadores_por_equipe, 1, 4)
	var ativos := Config.veiculos_ativos()
	# Bots com nomes fictícios sorteados (jogo.json → bots.nomes), sem repetir nem copiar o do jogador
	var nomes: Array = Config.valor("bots.nomes", []).duplicate()
	nomes.erase(Sessao.nome_jogador.to_upper())
	_rng.randomize()
	for i in range(nomes.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = nomes[i]
		nomes[i] = nomes[j]
		nomes[j] = tmp
	var n_bot := 1
	for e in equipes_qtd:
		for k in por_equipe:
			var eh_jogador := e == 0 and k == 0
			var nome := Sessao.nome_jogador.to_upper()
			if not eh_jogador:
				nome = str(nomes.pop_back()).to_upper() if not nomes.is_empty() else "PILOTO %02d" % n_bot
				n_bot += 1
			var dados: Dictionary = Config.veiculo(Sessao.veiculo_id) if eh_jogador else ativos[_rng.randi() % ativos.size()]
			if dados.is_empty():
				dados = ativos[0]
			# Upgrades da garagem (os bots espelham os níveis do jogador, conforme upgrades.json)
			dados = Progresso.dados_jogador(dados.id) if eh_jogador else Progresso.dados_bot(dados, Sessao.veiculo_id)
			var v := Veiculo.new()
			v.name = "Veiculo_" + nome.replace(" ", "_")
			v.dados = dados
			var pilotos := Config.avatares_ativos()
			if not pilotos.is_empty():
				v.avatar_dados = Config.avatar(Sessao.avatar_id) if eh_jogador else pilotos[_rng.randi() % pilotos.size()]
				if v.avatar_dados.is_empty():
					v.avatar_dados = pilotos[0]
			v.nome_piloto = nome
			v.indice_equipe = e
			v.cor_equipe = Config.EQUIPES[e].cor
			v.eh_jogador = eh_jogador
			v.terreno = terreno
			v.complexo = complexos[e]
			add_child(v)
			var controle: Node
			if eh_jogador and not Sessao.teste_automatico:
				var cj := ControleJogador.new()
				cj.veiculo = v
				controle = cj
			else:
				var bot := PilotoBot.new()
				bot.veiculo = v
				bot.rng.seed = _rng.randi()
				bot.falou.connect(_bot_falou)
				controle = bot
			v.add_child(controle)
			v.tocou_alvo.connect(_ao_tocar_alvo)
			v.foi_eliminado.connect(_ao_eliminar)
			v.ejetor_usado.connect(_ao_ejetor)
			var p := {"nome": nome, "equipe": e, "veiculo": v, "controle": controle, "pontos": [],
				"zonas5": 0, "explosoes": 0, "jogador": eh_jogador}
			participantes.append(p)
			if eh_jogador:
				jogador = p
	hud.mostrar_equipes(equipes_qtd)
	var linhas := []
	for p in participantes:
		linhas.append({"nome": p.nome, "cor": Config.EQUIPES[p.equipe].cor})
	hud.definir_participantes(linhas)
	for i in equipes_qtd:
		equipes_ativas.append(i)


# ------------------------------------------------------------------ etapas

func _cfg_etapa() -> Dictionary:
	return etapas_cfg[mini(etapa_idx, etapas_cfg.size() - 1)]


func _iniciar_etapa(indice: int) -> void:
	etapa_idx = indice
	alvo.configurar(_cfg_etapa())
	_semaforos(0)
	for e in equipes_qtd:
		var membros := participantes.filter(func(p): return p.equipe == e)
		var vagas := complexos[e].vagas_largada(membros.size())
		for k in membros.size():
			var v: Veiculo = membros[k].veiculo
			v.preparar(vagas[k])
			var ativo := e in equipes_ativas
			v.visible = ativo
			if not ativo:
				v.eliminado = true
			if membros[k].controle is PilotoBot:
				membros[k].controle.iniciar_etapa(alvo)
			membros[k].controle.ativo = false
	if tempo_modo == "etapa":
		tempo_restante = tempo_etapa
	_zona_jogador = -1
	_espectando = false
	hud.espectador("")
	hud.esconder_resultado()
	hud.contagem("")
	camera.seguir(jogador.veiculo, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if indice == 0 and not morte_subita:
		fase = Fase.APRESENTACAO
		tempo_fase = float(Config.valor("partida.apresentacao_s", 5))
		camera.cinematica(alvo.centro_base)
		hud.mensagem("CANYON RUSH  —  " + str(_cfg_etapa().nome).to_upper(), Estilo.TEXTO, tempo_fase)
	else:
		_iniciar_contagem()


func _iniciar_contagem() -> void:
	fase = Fase.CONTAGEM
	tempo_fase = float(Config.valor("partida.contagem_s", 3))
	_bipe_contagem = -1
	if not jogador.veiculo.eliminado:
		jogador.veiculo.som.dar_partida()
	camera.seguir(jogador.veiculo, true)
	var nome_etapa := "MORTE SÚBITA" if morte_subita else "ETAPA %d — %s" % [etapa_idx + 1, str(_cfg_etapa().nome).to_upper()]
	hud.mensagem(nome_etapa, Estilo.TEXTO, tempo_fase)


func _comecar() -> void:
	fase = Fase.ATIVA
	Audio.bipe(true)
	hud.contagem("JÁ!")
	_semaforos(3, true)
	get_tree().create_timer(0.8).timeout.connect(_limpar_contagem)
	for p in _ativos():
		p.veiculo.congelar(false)
		p.controle.ativo = true


func _limpar_contagem() -> void:
	if fase == Fase.ATIVA:
		hud.contagem("")
		get_tree().create_timer(2.2).timeout.connect(_apagar_semaforos)


func _apagar_semaforos() -> void:
	if fase != Fase.CONTAGEM:
		_semaforos(0)


## Semáforo de largada nos pórticos de todas as equipes.
func _semaforos(acesas: int, verde := false) -> void:
	for c in complexos:
		c.semaforo(acesas, verde)


func _reiniciar() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _ativos() -> Array:
	return participantes.filter(func(p): return p.equipe in equipes_ativas)


var _fotos: Array = []
var _bipe_contagem := -1
var _t_ativa := 0.0


func _process(delta: float) -> void:
	if fase == Fase.CARREGANDO:
		return
	if not _fotos.is_empty() or OS.get_environment("TSC_FOTOS") != "":
		_capturas(delta)
	match fase:
		Fase.APRESENTACAO:
			tempo_fase -= delta
			if tempo_fase <= 0.0:
				_iniciar_contagem()
		Fase.CONTAGEM:
			tempo_fase -= delta
			var seg := int(ceil(tempo_fase))
			if seg != _bipe_contagem and seg > 0 and seg <= 3:
				_bipe_contagem = seg
				Audio.bipe()
			hud.contagem(str(int(ceil(tempo_fase))) if tempo_fase > 0.0 else "")
			_semaforos(clampi(4 - int(ceil(tempo_fase)), 1, 3))
			if tempo_fase <= 0.0:
				_comecar()
		Fase.ATIVA:
			_contar_tempo(delta)
			if tempo_restante <= 0.0:
				_tempo_esgotado()
			elif _todos_resolvidos():
				fase = Fase.ESTABILIZACAO
				estab_t = float(Config.valor("partida.estabilizacao_s", 5))
		Fase.ESTABILIZACAO:
			_contar_tempo(delta)
			if _alguem_voando():
				estab_t = float(Config.valor("partida.estabilizacao_s", 5))
			estab_t -= delta
			if estab_t <= 0.0:
				_finalizar_etapa()
		Fase.RESULTADO:
			tempo_fase -= delta
			if tempo_fase <= 0.0:
				_proxima()
	_atualizar_zona_jogador()
	_atualizar_espectador(delta)
	_atualizar_hud(delta)
	if Sessao.teste_automatico and OS.get_environment("TSC_RASTRO") != "" and fase == Fase.ATIVA:
		_rastro(delta)
	if Sessao.teste_automatico and OS.get_environment("TSC_POUSO") != "" and fase in [Fase.ATIVA, Fase.ESTABILIZACAO]:
		for p in _ativos():
			var v: Veiculo = p.veiculo
			var dt_toque: float = v.relogio - float(v.telemetria.get("toque_alvo_tempo", 1e9))
			if v.travado and not v.eliminado and dt_toque >= 0.0 and ((dt_toque < 3.0 and int(dt_toque * 60.0) % 6 == 0) or (dt_toque < 25.0 and int(dt_toque * 60.0) % 60 == 0)):
				var c := alvo.centro_superior()
				print("[POUSO] %s t=%.2f dir=%.0f dist=%.1f v=%.1f km/h vy=%.1f rodas=%d corpo=%s estado=%d fr=%.1f cima.y=%.2f alt=%.1f" % [p.nome, dt_toque, float(v.entrada.direcao),
					Vector2(v.global_position.x - c.x, v.global_position.z - c.z).length(), v.velocidade_kmh(), v.linear_velocity.y,
					v.rodas_no_chao, str(v.contato_corpo), v.estado, float(v.entrada.freiar), v.global_transform.basis.y.y, v.global_position.y - c.y])


var _t_rastro := 0.0
func _rastro(delta: float) -> void:
	_t_rastro += delta
	if _t_rastro < 0.5:
		return
	_t_rastro = 0.0
	for p in _ativos():
		var v: Veiculo = p.veiculo
		if v.eliminado or v.saiu_da_rampa:
			continue
		var x := v.complexo.x_perfil(v.global_position)
		if x < 100.0:
			continue
		var comp := []
		for r in v.rodas:
			comp.append(snappedf(r.compressao / v.curso, 0.01))
		var desvio := (v.global_position - v.complexo.ponto(x, v.global_position.y)).dot(v.complexo.lateral)
		print("[RASTRO] %s x=%d v=%d km/h lat=%.1f dir=%.2f ac=%.1f fr=%.1f rodas=%d corpo=%s comp=%s nitro=%s cima.y=%.2f" % [p.nome, int(x), int(v.velocidade_kmh()), desvio, float(v.entrada.direcao), float(v.entrada.acelerar), float(v.entrada.freiar),
			v.rodas_no_chao, str(v.contato_corpo), str(comp), str(v.nitro_ativo), v.global_transform.basis.y.y])


func _contar_tempo(delta: float) -> void:
	tempo_restante -= delta


func _todos_resolvidos() -> bool:
	for p in _ativos():
		var v: Veiculo = p.veiculo
		if not (v.eliminado or v.travado) or v.esta_voando():
			return false
	return true


func _alguem_voando() -> bool:
	for p in _ativos():
		if p.veiculo.esta_voando():
			return true
	return false


func _tempo_esgotado() -> void:
	tempo_restante = 0.0
	# Quem não alcançou o alvo explode.
	for p in _ativos():
		var v: Veiculo = p.veiculo
		if not v.eliminado and not v.travado:
			v.eliminar("tempo")
	hud.mensagem("TEMPO ESGOTADO", Estilo.PERIGO, 3.0)
	fase = Fase.ESTABILIZACAO
	estab_t = float(Config.valor("partida.estabilizacao_s", 5))


func _finalizar_etapa() -> void:
	fase = Fase.RESULTADO
	tempo_fase = float(Config.valor("partida.resultado_etapa_s", 6))
	var jogadores := []
	var melhor := ""
	var melhor_pts := -1
	for p in _ativos():
		var v: Veiculo = p.veiculo
		var pts := 0
		var texto := ""
		if v.eliminado:
			texto = "EXPLODIU — 0 PONTOS"
			p.explosoes += 1
		elif v.travado and v.relogio - v.ultimo_contato_alvo < 1.0:
			pts = alvo.zona_do_veiculo(v)
			texto = ("ZONA %d — %d PONTOS" % [pts, pts]) if pts > 0 else "FORA DO ALVO — 0 PONTOS"
		else:
			texto = "FORA DO ALVO — 0 PONTOS"
		if pts == 5:
			p.zonas5 += 1
		p.veiculo.congelar(true)
		p.controle.ativo = false
		if not morte_subita:
			p.pontos.append(pts)
		p["ultima"] = pts
		if pts > melhor_pts:
			melhor_pts = pts
			melhor = p.nome
		jogadores.append({"nome": p.nome, "cor": Config.EQUIPES[p.equipe].cor, "texto": texto, "pontos": pts})
		if Sessao.teste_automatico:
			_imprimir_telemetria(p, texto)
	var equipes := []
	for e in equipes_ativas:
		var soma := 0
		for p in participantes:
			if p.equipe == e:
				soma += p.ultima
		equipes.append({"nome": Config.EQUIPES[e].nome, "cor": Config.EQUIPES[e].cor, "pontos": soma})
	var proxima := ""
	if not morte_subita and etapa_idx + 1 < total_etapas and not _tempo_partida_acabou():
		var c: Dictionary = etapas_cfg[etapa_idx + 1]
		proxima = "%s — %d m" % [c.nome, int(c.get("diametro", 30))]
	var titulo := "MORTE SÚBITA — RESULTADO" if morte_subita else "RESULTADO — ETAPA %d/%d" % [etapa_idx + 1, total_etapas]
	hud.resultado_etapa({"titulo": titulo, "jogadores": jogadores, "equipes": equipes, "melhor": melhor, "proxima": proxima})


func _tempo_partida_acabou() -> bool:
	return tempo_modo == "partida" and tempo_restante <= 0.0


func _proxima() -> void:
	if morte_subita:
		_decidir_morte_subita()
	elif etapa_idx + 1 < total_etapas and not _tempo_partida_acabou():
		_iniciar_etapa(etapa_idx + 1)
	else:
		_resultado_final()


# ------------------------------------------------------------------ resultado final

func _total_equipe(e: int) -> Dictionary:
	var r := {"pontos": 0, "zonas5": 0, "explosoes": 0, "ultima": 0}
	for p in participantes:
		if p.equipe != e:
			continue
		for x in p.pontos:
			r.pontos += x
		r.zonas5 += p.zonas5
		r.explosoes += p.explosoes
		if not p.pontos.is_empty() and p.pontos.back() > 0:
			r.ultima += 1
	return r


## Desempate: pontos, zonas 5, menos explosões, veículos pontuando na última etapa.
func _comparar(a: int, b: int) -> int:
	var ta := _total_equipe(a)
	var tb := _total_equipe(b)
	for chave in ["pontos", "zonas5", "explosoes", "ultima"]:
		var va: int = ta[chave]
		var vb: int = tb[chave]
		if chave == "explosoes":
			va = -va
			vb = -vb
		if va != vb:
			return 1 if va > vb else -1
	return 0


func _resultado_final() -> void:
	var ordem: Array = range(equipes_qtd)
	ordem.sort_custom(func(a, b): return _comparar(a, b) > 0)
	var empatadas: Array[int] = [ordem[0]]
	for i in range(1, ordem.size()):
		if _comparar(ordem[0], ordem[i]) == 0:
			empatadas.append(ordem[i])
	if empatadas.size() > 1:
		morte_subita = true
		equipes_ativas = empatadas
		hud.mensagem("EMPATE — MORTE SÚBITA!", Color(1.0, 0.85, 0.4), 4.0)
		_iniciar_etapa(total_etapas - 1)
		return
	_mostrar_final(ordem)


func _decidir_morte_subita() -> void:
	var melhor := -1
	var vencedoras: Array[int] = []
	for e in equipes_ativas:
		var soma := 0
		for p in participantes:
			if p.equipe == e:
				soma += p.ultima
		if soma > melhor:
			melhor = soma
			vencedoras = [e]
		elif soma == melhor:
			vencedoras.append(e)
	if vencedoras.size() > 1:
		equipes_ativas = vencedoras
		_iniciar_etapa(etapa_idx)
		return
	var ordem: Array = range(equipes_qtd)
	ordem.sort_custom(func(a, b): return _comparar(a, b) > 0)
	ordem.erase(vencedoras[0])
	ordem.push_front(vencedoras[0])
	_mostrar_final(ordem)


func _mostrar_final(ordem: Array) -> void:
	fase = Fase.FINAL
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var equipes := []
	for e in ordem:
		var t := _total_equipe(e)
		equipes.append({"nome": Config.EQUIPES[e].nome, "cor": Config.EQUIPES[e].cor, "pontos": t.pontos,
			"detalhe": "(%d× zona 5, %d explosões)" % [t.zonas5, t.explosoes]})
	var jogadores := []
	var mvp: Dictionary = {}
	for p in participantes:
		var total := 0
		for x in p.pontos:
			total += x
		p["total"] = total
		jogadores.append({"nome": p.nome, "cor": Config.EQUIPES[p.equipe].cor,
			"etapas": " ".join(p.pontos.map(func(x): return str(x))), "total": total})
		if mvp.is_empty() or total > mvp.total or (total == mvp.total and (p.explosoes < mvp.explosoes \
				or (p.explosoes == mvp.explosoes and p.zonas5 > mvp.zonas5))):
			mvp = p
	jogadores.sort_custom(func(a, b): return a.total > b.total)
	var venceu: bool = ordem[0] == 0
	var titulo: String = "VITÓRIA!" if venceu else "VITÓRIA DA EQUIPE " + Config.EQUIPES[ordem[0]].nome
	# XP da garagem para o carro do jogador (o teste automático não conta)
	var texto_xp := ""
	for p in participantes:
		if p.veiculo.eh_jogador and not Sessao.teste_automatico and OS.get_environment("TSC_FOTO_FINAL") == "":
			var r := Progresso.registrar_partida(Sessao.veiculo_id, p.total, venceu)
			texto_xp = "+%d XP  —  %s" % [r.ganho, str(p.veiculo.dados.nome).to_upper()]
			if r.subiu_nivel:
				texto_xp += "  —  NÍVEL %d! NOVOS UPGRADES NA GARAGEM" % r.nivel
	hud.resultado_final({"titulo": titulo, "subtitulo": "Canyon Rush — resultado final", "equipes": equipes,
		"jogadores": jogadores, "mvp": "%s (%d pts)" % [mvp.nome, mvp.total], "xp": texto_xp})
	_montar_comemoracao(ordem[0], mvp)
	if venceu:
		Audio.tocar("ambiente/publico_vibra_forte.mp3", null, 0.0, 1.0, 0.0, "Ambiente")
	Audio.interface("confirmar" if venceu else "erro", -2.0)
	if Sessao.teste_automatico:
		print("[TESTE] Partida concluída. Vencedora: ", Config.EQUIPES[ordem[0]].nome)
		get_tree().quit()


## Fim da partida: carros da equipe vencedora em cima do alvo (plano e parado), cada piloto em pé
## ao lado do seu carro comemorando. O MVP da partida fica na frente, no centro, com holofote e
## nome em cima (se ele não for da equipe vencedora, entra também, como destaque).
func _montar_comemoracao(equipe_vencedora: int, mvp: Dictionary) -> void:
	alvo.configurar(etapas_cfg[0])
	# Disco recém-montado: a posição global dele só atualiza no próximo quadro; o topo do disco
	# plano é o próprio centro_base
	var c := alvo.centro_base
	# Câmera do lado da rampa da equipe vencedora; carros de frente para ela
	var dir: Vector3 = Config.EQUIPES[equipe_vencedora].direcao
	var para_cam := -dir.normalized()
	var lado := para_cam.cross(Vector3.UP).normalized()
	var fila := participantes.filter(func(p): return p.equipe == equipe_vencedora and p != mvp)
	for p in participantes:
		p.controle.ativo = false
		var v: Veiculo = p.veiculo
		if p != mvp and not p in fila:
			v.visible = false
			v.congelar(true)
			if v.som:
				v.som.silenciar()
	# Fila de trás, levemente virada para o centro
	for i in fila.size():
		var x := (i - (fila.size() - 1) * 0.5) * 6.0
		_posicionar_comemoracao(fila[i], c + lado * x - para_cam * 3.5, para_cam.rotated(Vector3.UP, -x * 0.03), 1.0)
	# MVP na frente
	var avatar_mvp := _posicionar_comemoracao(mvp, c + para_cam * 3.5, para_cam, 1.6)
	var holofote := SpotLight3D.new()
	holofote.light_color = Color(1.0, 0.9, 0.7)
	holofote.light_energy = 12.0
	holofote.spot_range = 30.0
	holofote.spot_angle = 18.0
	holofote.shadow_enabled = true
	add_child(holofote)
	holofote.global_position = c + para_cam * 3.5 + Vector3.UP * 16.0 + para_cam * 4.0
	holofote.look_at(c + para_cam * 3.5, lado)
	var nome := Label3D.new()
	nome.text = "★ MVP ★\n" + str(mvp.nome)
	nome.font = Estilo.fonte_titulo(800)
	nome.font_size = 96
	nome.pixel_size = 0.005
	nome.modulate = Color(1.0, 0.85, 0.4)
	nome.outline_size = 18
	nome.outline_modulate = Color(0, 0, 0, 0.8)
	nome.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nome.no_depth_test = true
	add_child(nome)
	# Em cima do piloto do MVP (acima do carro ficava atrás de caminhões e vans)
	var v_mvp: Veiculo = mvp.veiculo
	nome.global_position = avatar_mvp.global_position + Vector3.UP * 2.5 if avatar_mvp else c + para_cam * 3.5 + Vector3.UP * (v_mvp.caixa_corpo.end.y + 1.2)
	alvo.festejar(Config.EQUIPES[equipe_vencedora].cor, 3600.0)
	# O grupo fica na metade direita da tela (a esquerda é do painel de resultado)
	var pos_cam := c + para_cam * 17.0 + Vector3.UP * 4.2 - lado * 5.0
	var foco := c + Vector3.UP * 1.3 + para_cam * 1.0
	var direita_tela := (foco - pos_cam).normalized().cross(Vector3.UP).normalized()
	camera.podio(foco - direita_tela * 5.0, pos_cam)


func _posicionar_comemoracao(p: Dictionary, pos: Vector3, frente: Vector3, intensidade: float) -> Avatar:
	var v: Veiculo = p.veiculo
	# O carro olha para `frente` (a frente do Veiculo é -Z)
	var b := Basis.looking_at(frente, Vector3.UP)
	v.preparar(Transform3D(b, pos + Vector3.UP * 0.15))
	if v.piloto:
		v.piloto.visible = false   # o piloto sai do carro e fica em pé ao lado
	if v.avatar_dados.is_empty():
		return null
	var a := Avatar.criar(v.avatar_dados)
	add_child(a)
	# Ao lado da porta do motorista, virado para a câmera
	var esquerda := -b.x
	a.global_position = pos + esquerda * (v.caixa_corpo.size.x * 0.5 + 0.9) + frente * 0.6
	a.rotation.y = atan2(-frente.x, -frente.z)
	a.festejar(intensidade)
	return a


# ------------------------------------------------------------------ eventos

func _ao_tocar_alvo(v: Veiculo) -> void:
	alvo.festejar(v.cor_equipe)
	if v == jogador.veiculo:
		_zona_jogador = -1


func _ao_eliminar(v: Veiculo) -> void:
	if v == jogador.veiculo:
		hud.mensagem("EXPLODIU!", Estilo.PERIGO, 3.0)
		hud.espectador("VOCÊ EXPLODIU — 0 PONTOS NESTA ETAPA")
		_t_eliminado = float(Config.valor("partida.espectador_apos_explosao_s", 4))


func _ao_ejetor(_v: Veiculo) -> void:
	if fase == Fase.ESTABILIZACAO:
		estab_t = float(Config.valor("partida.estabilizacao_s", 5))


func _bot_falou(bot: PilotoBot, texto: String) -> void:
	hud.chat(bot.veiculo.nome_piloto, bot.veiculo.cor_equipe, texto)


func _atualizar_zona_jogador() -> void:
	var v: Veiculo = jogador.veiculo
	if not v.travado or v.eliminado or fase not in [Fase.ATIVA, Fase.ESTABILIZACAO]:
		return
	var z := alvo.zona_do_veiculo(v) if v.relogio - v.ultimo_contato_alvo < 0.5 else 0
	if z != _zona_jogador:
		_zona_jogador = z
		if z > 0:
			hud.mensagem("ZONA %d — PROVISÓRIO" % z, Color(1.0, 0.85, 0.4), 3.0)
		else:
			hud.mensagem("FORA DO ALVO", Estilo.PERIGO, 2.0)


func _atualizar_espectador(delta: float) -> void:
	var meu: Veiculo = jogador.veiculo
	if meu.eliminado and _t_eliminado > 0.0:
		_t_eliminado -= delta
		if _t_eliminado <= 0.0:
			_proximo_espectado()
	if _espectando and Input.is_action_just_pressed("proxima_camera"):
		_proximo_espectado()


func _proximo_espectado() -> void:
	var vivos := _ativos().filter(func(p): return not p.veiculo.eliminado).map(func(p): return p.veiculo)
	if vivos.is_empty():
		return
	_espectando = true
	var i := vivos.find(camera.veiculo)
	var proximo: Veiculo = vivos[(i + 1) % vivos.size()]
	camera.seguir(proximo)
	hud.espectador("VOCÊ EXPLODIU — ASSISTINDO: %s   (TAB troca)" % proximo.nome_piloto)


func _status(p: Dictionary) -> Array:
	var v: Veiculo = p.veiculo
	if not (p.equipe in equipes_ativas):
		return ["ESPECTADOR", Estilo.TEXTO_FRACO]
	if v.eliminado:
		return ["ELIMINADO", Estilo.PERIGO]
	if v.travado:
		var z := alvo.zona_do_veiculo(v) if v.relogio - v.ultimo_contato_alvo < 0.5 else 0
		return ["ZONA %d" % z, Color(1.0, 0.85, 0.4)] if z > 0 else ["FORA DO ALVO", Estilo.PERIGO]
	if v.esta_voando():
		return ["VOANDO", Estilo.DESTAQUE]
	var x := v.complexo.x_perfil(v.global_position)
	if x < perfil.pontos[perfil.indice_borda].x:
		return ["NA PLATAFORMA", Estilo.TEXTO_FRACO]
	return ["DESCENDO", Estilo.TEXTO]


func _atualizar_hud(delta: float) -> void:
	if fase == Fase.CARREGANDO:
		return
	var equipes := []
	for e in equipes_qtd:
		equipes.append(_total_equipe(e).pontos)
	var linhas := []
	for p in participantes:
		var s := _status(p)
		linhas.append({"status": s[0], "cor_status": s[1]})
	var etapa_txt := "MORTE SÚBITA" if morte_subita else "ETAPA %d/%d" % [etapa_idx + 1, total_etapas]
	var veiculos := participantes.map(func(p): return p.veiculo)
	hud.atualizar({"etapa_texto": etapa_txt, "tempo": tempo_restante, "equipes": equipes, "linhas": linhas,
		"veiculo": camera.veiculo if camera.veiculo else jogador.veiculo, "camera": camera.cam,
		"alvo_pos": alvo.centro_superior(), "veiculos": veiculos}, delta)


# ------------------------------------------------------------------ pausa e telemetria

func _unhandled_input(evento: InputEvent) -> void:
	if evento.is_action_pressed("pausa") and fase != Fase.FINAL:
		if get_tree().paused:
			_despausar()
		else:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.pausa(true)


func _despausar() -> void:
	get_tree().paused = false
	hud.pausa(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ir_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://cenas/menu.tscn")


## Câmera fixa para conferir estruturas nas capturas (TSC_CAM_VISTA = muro, base ou colunas).
func _vista_debug(vista: String) -> void:
	var cx := complexos[0]
	var y0: float = cx.perfil.pontos[0].y
	var x_borda: float = cx.perfil.pontos[cx.perfil.indice_borda].x
	match vista:
		"muro":
			var f := cx.ponto(0.0, y0 + 1.2)
			camera.podio(f, f + cx.frente * 13.0 + Vector3.UP * 2.5 + cx.lateral * 6.0)
		"base":
			var f := cx.ponto(x_borda * 0.3, y0 - 8.0)
			camera.podio(f, f + cx.lateral * 45.0 + Vector3.UP * 6.0 - cx.frente * 20.0)
		"colunas":
			var i := int(cx.perfil.pontos.size() * 0.75)
			var p := cx.ponto_indice(i)
			var chao := terreno.altura_em(p.x, p.z)
			var f := Vector3(p.x, chao + 12.0, p.z)
			camera.podio(f, f + cx.lateral * 35.0 + Vector3.UP * 4.0 + cx.frente * 25.0)


## Capturas de tela automáticas para conferência visual: TSC_FOTOS="fase:segundos,...", TSC_FOTO_DIR e TSC_SEM_HUD (esconde o HUD).
func _capturas(delta: float) -> void:
	if _fotos.is_empty():
		_fotos = Array(OS.get_environment("TSC_FOTOS").split(","))
		if OS.get_environment("TSC_SEM_HUD") != "":
			hud.visible = false
		OS.set_environment("TSC_FOTOS", "")
		_t_ativa = 0.0
		_vista_debug(OS.get_environment("TSC_CAM_VISTA"))
	_t_ativa += delta
	var alvo_t := float(str(_fotos[0]).split(":")[1])
	if _t_ativa >= alvo_t:
		var nome := str(_fotos.pop_front()).replace(":", "_").replace(".", "_")
		var img := get_viewport().get_texture().get_image()
		var dir := OS.get_environment("TSC_FOTO_DIR")
		img.save_png(dir + "/foto_" + nome + ".png")
		print("[FOTO] ", nome)
		if _fotos.is_empty():
			get_tree().quit()


func _imprimir_telemetria(p: Dictionary, texto: String) -> void:
	var v: Veiculo = p.veiculo
	var t := v.telemetria
	var d := Vector2(v.global_position.x - alvo.global_position.x, v.global_position.z - alvo.global_position.z).length()
	var r := func(k): return str(snappedf(float(t.get(k, -1)), 0.1))
	print("[TESTE] e%d %-9s %-12s | saída %s km/h %s m t=%s | ápice %s | pq t=%s h=%s | alvo t=%s %s km/h | elim %s t=%s | dist %d | %s" % [
		etapa_idx + 1, p.nome, str(v.dados.nome).left(12), r.call("saida_kmh"), r.call("saida_altura"), r.call("saida_tempo"),
		r.call("apice"), r.call("paraquedas_tempo"), r.call("paraquedas_altura"), r.call("toque_alvo_tempo"), r.call("toque_alvo_kmh"),
		t.get("motivo", "-"), r.call("tempo_eliminado"), int(d), texto])
