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
## Partida rápida: joga só esta etapa (índice real no mapa); -1 = todas.
var etapa_unica := -1
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
## Corrida (regras.corrida, Climb to Death): só os primeiros a tocar o alvo pontuam; quando todas
## as vagas estão preenchidas a etapa acaba. _chegadas em ordem de chegada (vivos).
var _corrida: Dictionary = {}
var _chegadas: Array[Veiculo] = []


func _ready() -> void:
	_rng.randomize()
	hud = Hud.new()
	add_child(hud)
	hud.pedido_continuar.connect(_despausar)
	hud.pedido_menu.connect(_ir_menu)
	hud.pedido_reiniciar.connect(_reiniciar)
	Audio.silenciar_efeitos(true)   # carregamento e abertura: nenhum efeito sonoro até a contagem
	etapa_unica = Sessao.etapa_unica()
	var lista: Array = Config.valor("etapas", [{}])
	var primeira: Dictionary = lista[clampi(_primeira_etapa(), 0, lista.size() - 1)]
	hud.carregando(Config.nome_mapa().to_upper(), "ETAPA %d  —  %s" % [_primeira_etapa() + 1, str(primeira.get("nome", "")).to_upper()])
	if OS.get_environment("TSC_FOTO_CARGA") != "":
		hud.progresso_carga(0.55)
		for i in 90:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TSC_FOTO_CARGA"))
		get_tree().quit()
		return
	await get_tree().process_frame
	await get_tree().process_frame
	await _construir_mundo()
	await _criar_participantes()
	var som_ambiente := SomAmbiente.new()
	add_child(som_ambiente)
	som_ambiente.montar(complexos)
	Audio.musica("partida")
	await hud.esconder_carregando()
	if Sessao.teste_automatico:
		Engine.time_scale = float(OS.get_environment("TSC_VELOCIDADE")) if OS.get_environment("TSC_VELOCIDADE") != "" else 4.0
	# TSC_ETAPA=N: começa direto na etapa N (conferência de etapas)
	_iniciar_etapa(clampi(int(OS.get_environment("TSC_ETAPA")) - 1, 0, total_etapas - 1) if OS.get_environment("TSC_ETAPA") != "" else _primeira_etapa())
	if OS.get_environment("TSC_FOTO_FINAL") != "":
		_foto_final(OS.get_environment("TSC_FOTO_FINAL"))
	elif OS.get_environment("TSC_MEDIR_SUPORTE") != "":
		_medir_suportes()
	elif OS.get_environment("TSC_FOTO_PARAQUEDAS") != "":
		_foto_paraquedas(OS.get_environment("TSC_FOTO_PARAQUEDAS"))


## Conferência: onde fica o suporte do paraquedas em cada carro (posição relativa ao comprimento).
func _medir_suportes() -> void:
	for d in Config.veiculos_ativos():
		var v := Veiculo.new()
		v.dados = d
		v.freeze = true
		add_child(v)
		await get_tree().process_frame
		var c: AABB = v.caixa_corpo
		var z: float = v.paraquedas._fixacoes[0].z
		print("MED %-14s rel=%+.2f y=%.2f topo=%.2f" % [d.id, (z - c.get_center().z) / c.size.z, v.paraquedas._fixacoes[0].y, c.end.y])
		v.queue_free()
	get_tree().quit()


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
	for alvo_s: float in [0.15, 0.3, 0.45, 0.6, 0.8, 1.05, 1.6]:
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
	# Progresso: 0,05 ambiente → 0,45 terreno → 0,65 complexos → 0,7 alvo (carros até 1,0)
	add_child(Ambiente.new())
	await _passo_carga(0.05)
	perfil = PerfilRampa.new()
	terreno = Terreno.new()
	terreno.name = "Terreno"
	add_child(terreno)
	terreno.gerar(perfil)
	await _passo_carga(0.45)
	equipes_qtd = clampi(int(Config.valor("partida.equipes", 4)), 2, 4)
	if Config.mapa_tipo() == "subida":
		# Climb to Death: largada conjunta num cercado no chão, estrada subindo até a rampa final
		var sub := ComplexoSubida.new()
		add_child(sub)
		sub.montar(0, perfil, terreno)
		complexos.append(sub)
		await _passo_carga(0.65)
	elif Config.mapa_arena():
		# Canyon Combat Target: uma só plataforma, todas as equipes juntas
		var arena := ComplexoArena.new()
		add_child(arena)
		arena.montar(0, perfil, terreno)
		complexos.append(arena)
		await _passo_carga(0.65)
	else:
		for i in equipes_qtd:
			var c := ComplexoLancamento.new()
			add_child(c)
			c.montar(i, perfil, terreno)
			complexos.append(c)
			await _passo_carga(0.45 + 0.2 * float(i + 1) / equipes_qtd)
	alvo = Alvo.new()
	alvo.terreno = terreno
	alvo.name = "Alvo"
	add_child(alvo)
	await _passo_carga(0.7)
	camera = CameraJogo.new()
	camera.terreno = terreno
	add_child(camera)
	etapas_cfg = Config.valor("etapas", [])
	total_etapas = clampi(mini(int(Config.valor("partida.etapas", 4)), etapas_cfg.size()), 1, 8)
	tempo_modo = Sessao.tempo_modo
	tempo_etapa = float(Sessao.tempo_do_mapa())
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
			v.complexo = complexos[mini(e, complexos.size() - 1)]
			v.freeze = true   # parado até preparar() na largada (a tela desenha entre os passos da carga)
			add_child(v)
			await _passo_carga(0.7 + 0.28 * float(e * por_equipe + k + 1) / (equipes_qtd * por_equipe))
			var controle: Node
			if eh_jogador and not Sessao.teste_automatico:
				var cj := ControleJogador.new()
				cj.veiculo = v
				controle = cj
			else:
				var bot := PilotoBot.new()
				bot.veiculo = v
				bot.rng.seed = _rng.randi()
				bot.escolher_personalidade()
				bot.falou.connect(_bot_falou)
				controle = bot
			v.add_child(controle)
			v.tocou_alvo.connect(_ao_tocar_alvo)
			v.foi_eliminado.connect(_ao_eliminar)
			v.ejetor_usado.connect(_ao_ejetor)
			v.velame_murchou.connect(_ao_murchar_velame)
			v.ressurgiu.connect(_ao_ressurgir)
			var p := {"nome": nome, "equipe": e, "veiculo": v, "controle": controle, "pontos": [],
				"zonas5": 0, "explosoes": 0, "jogador": eh_jogador}
			participantes.append(p)
			if eh_jogador:
				jogador = p
	var todos := participantes.map(func(p): return p.veiculo)
	for p in participantes:
		if p.controle is PilotoBot:
			p.controle.outros = todos
	hud.mostrar_equipes(equipes_qtd)
	var linhas := []
	for p in participantes:
		linhas.append({"nome": p.nome, "cor": Config.EQUIPES[p.equipe].cor})
	hud.definir_participantes(linhas)
	for i in equipes_qtd:
		equipes_ativas.append(i)


# ------------------------------------------------------------------ etapas

func _primeira_etapa() -> int:
	return etapa_unica if etapa_unica >= 0 else 0


func _ultima_etapa() -> int:
	return mini(etapa_unica, total_etapas - 1) if etapa_unica >= 0 else total_etapas - 1


## "ETAPA 2/4", ou só "ETAPA 2" na partida rápida (etapa única).
func _texto_etapa() -> String:
	return "ETAPA %d" % (etapa_idx + 1) if etapa_unica >= 0 else "ETAPA %d/%d" % [etapa_idx + 1, total_etapas]


func _cfg_etapa() -> Dictionary:
	return etapas_cfg[mini(etapa_idx, etapas_cfg.size() - 1)]


func _iniciar_etapa(indice: int) -> void:
	_evento("troca de etapa")
	etapa_idx = indice
	terreno.preparar_etapa(indice)   # Canyon Combat: esporões do vale mudam a cada etapa
	if complexos[0].has_method("preparar_etapa"):
		complexos[0].preparar_etapa(indice)   # Climb to Death: túnel-atalho da etapa
	alvo.configurar(_cfg_etapa())
	_semaforos(0)
	# Arena e Climb to Death: vagas sorteadas a cada etapa entre todos, equipes misturadas
	var vagas_arena := {}
	var arena = complexos[0] if complexos[0].has_method("sortear_vagas") else null
	if arena:
		var ordem: Array[int] = arena.sortear_vagas(participantes.size(), _rng)
		var cores := {}
		for k in participantes.size():
			vagas_arena[participantes[k]] = arena.transform_vaga(ordem[k])
			if participantes[k].equipe in equipes_ativas:
				cores[ordem[k]] = Config.EQUIPES[participantes[k].equipe].cor
		arena.pintar_vagas(cores)
	for e in equipes_qtd:
		var membros := participantes.filter(func(p): return p.equipe == e)
		var vagas := complexos[mini(e, complexos.size() - 1)].vagas_largada(membros.size())
		for k in membros.size():
			var v: Veiculo = membros[k].veiculo
			v.preparar(vagas_arena[membros[k]] if arena else vagas[k])
			var ativo := e in equipes_ativas
			v.visible = ativo
			if not ativo:
				v.eliminado = true
			if membros[k].controle is PilotoBot:
				membros[k].controle.iniciar_etapa(alvo)
			membros[k].controle.ativo = false
	if tempo_modo == "etapa":
		tempo_restante = tempo_etapa
	_corrida = Config.valor("regras.corrida", {})
	_chegadas.clear()
	_zona_jogador = -1
	_espectando = false
	hud.espectador("")
	hud.esconder_resultado()
	hud.contagem("")
	camera.seguir(jogador.veiculo, true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if indice == _primeira_etapa() and not morte_subita:
		fase = Fase.APRESENTACAO
		tempo_fase = camera.drone(_planos_drone())
		hud.mensagem(Config.nome_mapa().to_upper() + "  —  " + str(_cfg_etapa().nome).to_upper(), Estilo.TEXTO, tempo_fase)
	else:
		_iniciar_contagem()


## Filmagem de abertura (drone): o alvo, a rampa final, o meio do percurso e a chegada nos carros,
## terminando atrás do carro do jogador na posição da câmera de jogo.
func _planos_drone() -> Array:
	var planos := []
	var cx := complexos[0]
	var sub := cx as ComplexoSubida
	var a := alvo.centro_superior()
	var r: Vector3 = sub.amostra(99999) if sub else cx.posicao_saida()
	var dv := Vector3(a.x - r.x, 0.0, a.z - r.z).normalized()   # da rampa para o alvo
	var ld := dv.cross(Vector3.UP)
	var up := Vector3.UP
	# 1. O alvo: aproximação rasante, passa por cima e vira olhando para a rampa
	planos.append({"dur": 5.0,
		"pos": [a + dv * 300.0 + ld * 120.0 + up * 90.0, a + dv * 110.0 + ld * 40.0 + up * 30.0, a + ld * 10.0 + up * 22.0, a - dv * 60.0 - ld * 25.0 + up * 30.0],
		"olhar": [a, a, a, a - dv * 250.0 + up * 20.0]})
	# 2. A rampa final: vem de frente e sobe por ela, olhando o caminho de volta
	planos.append({"dur": 4.5,
		"pos": [r + dv * 140.0 - ld * 50.0 + up * 25.0, r + dv * 35.0 - ld * 18.0 + up * 10.0, r - dv * 60.0 - ld * 12.0 + up * 16.0],
		"olhar": [r, r, r - dv * 260.0]})
	# 3. O meio do percurso: plataforma dos buracos (Climb to Death) ou a descida
	if sub:
		var pl := sub.plataforma
		var c := pl.pa(pl.comprimento * 0.5, 0.0, pl.piso_y)
		planos.append({"dur": 4.5,
			"pos": [c - pl.frente * 90.0 + pl.lateral * 80.0 + up * 60.0, c + pl.lateral * 60.0 + up * 32.0, c + pl.frente * 70.0 + pl.lateral * 20.0 + up * 40.0],
			"olhar": [c, c, c - pl.frente * 20.0]})
	else:
		var borda := cx.ponto_indice(cx.perfil.indice_borda)
		var base := cx.ponto_indice(cx.perfil.indice_base)
		planos.append({"dur": 4.5,
			"pos": [base + cx.lateral * 60.0 + up * 25.0, base.lerp(borda, 0.5) + cx.lateral * 45.0 + up * 20.0, borda + cx.lateral * 30.0 + up * 25.0],
			"olhar": [base.lerp(borda, 0.3), borda, borda - cx.frente * 40.0]})
	# 4. A chegada nos carros: desce na largada, passa na frente do carro do jogador e pousa atrás dele
	var v: Veiculo = jogador.veiculo
	var p := v.global_position
	var fv := -v.global_transform.basis.z
	fv = Vector3(fv.x, 0.0, fv.z).normalized()
	var lv := fv.cross(Vector3.UP)
	var fim := camera.pose_seguir(v)
	planos.append({"dur": 6.5,
		"pos": [p + fv * 110.0 + lv * 60.0 + up * 55.0, p + fv * 30.0 + lv * 8.0 + up * 9.0, p + fv * 12.0 + up * 3.0, p + up * 7.0, fim[0]],
		"olhar": [p, p + up, p + up, p + up, fim[1]]})
	return planos


func _iniciar_contagem() -> void:
	Audio.silenciar_efeitos(false)   # carregamento e abertura da fase: só música (pedido do dono)
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
	if not _corrida.is_empty():
		hud.mensagem("SÓ OS %d PRIMEIROS A TOCAR O ALVO PONTUAM!" % _vagas_corrida(), Color(1.0, 0.85, 0.4), 4.0)


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
	Audio.silenciar_efeitos(false)
	get_tree().paused = false
	get_tree().reload_current_scene()


func _ativos() -> Array:
	return participantes.filter(func(p): return p.equipe in equipes_ativas)


var _fotos: Array = []
var _bipe_contagem := -1
var _t_ativa := 0.0


var _t_quadro := 0
var _comp_ant := 0
var _t_resumo := 0.0
var _n_resumo := 0
var _fis_resumo := 0.0
var _eventos: Array = []   # [tempo_ms, texto] dos últimos acontecimentos (monitor de travadas)


## Diagnóstico (TSC_TRAVADAS=1): imprime cada quadro lento, o que aconteceu logo antes e quantos
## pipelines de shader o Godot compilou nele (compilação na hora = travada da 1ª vez que algo aparece).
func _monitor_travadas() -> void:
	var agora := Time.get_ticks_usec()
	var ms := (agora - _t_quadro) / 1000.0
	_t_quadro = agora
	var comp := 0
	for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE,
			Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		comp += int(Performance.get_monitor(m))
	if ms > 40.0 and _comp_ant > 0:
		var recentes := _eventos.filter(func(e): return agora / 1000 - int(e[0]) < 400).map(func(e): return e[1])
		print("[TRAVADA] %4.0f ms  fase=%d  shaders compilados=+%d  física=%.1f ms  eventos=%s" % [ms, fase, comp - _comp_ant,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, ", ".join(recentes)])
	_comp_ant = comp
	_eventos = _eventos.filter(func(e): return agora / 1000 - int(e[0]) < 2000)
	# A cada 2 s: FPS e quanto a física (carros + bots) e o resto do jogo gastam por quadro
	_t_resumo += ms
	_n_resumo += 1
	_fis_resumo = maxf(_fis_resumo, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	if _t_resumo > 2000.0 and fase == Fase.ATIVA:
		print("[RESUMO] %d fps  física pior=%.1f ms  processo=%.1f ms  objetos=%d" % [roundi(_n_resumo * 1000.0 / _t_resumo), _fis_resumo,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		_t_resumo = 0.0
		_n_resumo = 0
		_fis_resumo = 0.0


func _evento(texto: String) -> void:
	if OS.get_environment("TSC_TRAVADAS") != "":
		_eventos.append([Time.get_ticks_msec(), texto])


func _process(delta: float) -> void:
	if OS.get_environment("TSC_TRAVADAS") != "":
		_monitor_travadas()
	if fase == Fase.CARREGANDO:
		return
	if not _fotos.is_empty() or OS.get_environment("TSC_FOTOS") != "":
		_capturas(delta)
	match fase:
		Fase.APRESENTACAO:
			tempo_fase -= delta
			# Pular a filmagem de abertura
			if Input.is_action_just_pressed("ejetor") or Input.is_action_just_pressed("ui_accept"):
				tempo_fase = 0.0
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
			_checar_checkpoints()
			if not _corrida.is_empty() and _chegadas.size() >= _vagas_corrida():
				hud.mensagem("OS %d PRIMEIROS CHEGARAM!" % _vagas_corrida(), Color(1.0, 0.85, 0.4), 3.0)
				_finalizar_etapa()
			elif tempo_restante <= 0.0:
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
	if Sessao.teste_automatico and OS.get_environment("TSC_CAM_LOG") != "" and fase == Fase.ATIVA:
		_log_camera()
	if Sessao.teste_automatico and OS.get_environment("TSC_TESTE_BORRACHAO") != "" and fase == Fase.ATIVA:
		_teste_borrachao(delta)
	if Sessao.teste_automatico and OS.get_environment("TSC_TESTE_CURVA") != "" and fase == Fase.ATIVA:
		_teste_curva(delta)
	if Sessao.teste_automatico and OS.get_environment("TSC_RASTRO") != "" and fase == Fase.ATIVA:
		_rastro(delta)
	if Sessao.teste_automatico and OS.get_environment("TSC_ARENA_LOG") != "" and fase == Fase.ATIVA and complexos[0] is ComplexoArena:
		_log_arena(delta)
	if Sessao.teste_automatico and OS.get_environment("TSC_POUSO") != "" and fase in [Fase.ATIVA, Fase.ESTABILIZACAO]:
		for p in _ativos():
			var v: Veiculo = p.veiculo
			var dt_toque: float = v.relogio - float(v.telemetria.get("toque_alvo_tempo", 1e9))
			if v.travado and not v.eliminado and dt_toque >= 0.0 and ((dt_toque < 3.0 and int(dt_toque * 60.0) % 6 == 0) or (dt_toque < 25.0 and int(dt_toque * 60.0) % 60 == 0)):
				var c := alvo.centro_superior()
				print("[POUSO] %s t=%.2f dir=%.0f dist=%.1f v=%.1f km/h vy=%.1f rodas=%d corpo=%s estado=%d fr=%.1f cima.y=%.2f alt=%.1f" % [p.nome, dt_toque, float(v.entrada.direcao),
					Vector2(v.global_position.x - c.x, v.global_position.z - c.z).length(), v.velocidade_kmh(), v.linear_velocity.y,
					v.rodas_no_chao, str(v.contato_corpo), v.estado, float(v.entrada.freiar), v.global_transform.basis.y.y, v.global_position.y - c.y])


var _t_log_arena := 0.0
## Teste: posição dos carros na arena (TSC_ARENA_LOG=1), a cada segundo de jogo.
func _log_arena(delta: float) -> void:
	_t_log_arena += delta
	if _t_log_arena < 1.0:
		return
	_t_log_arena = 0.0
	var arena := complexos[0] as ComplexoArena
	for p in _ativos():
		var v: Veiculo = p.veiculo
		if v.eliminado:
			continue
		var l := arena.local(v.global_position)
		if l.x > arena.comprimento + 30.0:
			continue
		var bot = p.controle
		print("[ARENA] %-12s x=%5.1f lat=%6.1f v=%4.1f y=%5.1f est=%d ac=%.1f re=%.1f dir=%+.1f vit=%s" % [p.nome, l.x, l.y, v.linear_velocity.length(), v.global_position.y - arena.piso_y, v.estado,
			float(v.entrada.acelerar), float(v.entrada.re), float(v.entrada.direcao), bot._vitima.nome_piloto if bot is PilotoBot and bot._vitima else "-"])


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
	alvo.parado = true   # alvo móvel para junto com os carros congelados
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
		elif not _corrida.is_empty():
			var lugar := _chegadas.find(v)
			if lugar >= 0:
				pts = _pontos_chegada(lugar)
				texto = "%dº A CHEGAR — %d PONTOS" % [lugar + 1, pts]
			else:
				texto = "FORA DOS %d PRIMEIROS — 0 PONTOS" % _vagas_corrida()
		elif v.travado and v.relogio - v.ultimo_contato_alvo < 1.0:
			pts = alvo.zona_do_veiculo(v)
			texto = ("ZONA %d — %d PONTOS" % [pts, pts]) if pts > 0 else "FORA DO ALVO — 0 PONTOS"
		else:
			texto = "FORA DO ALVO — 0 PONTOS"
		if pts == 5 and _corrida.is_empty():   # na corrida 5 pontos é o 2º lugar, não a zona 5
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
	if not morte_subita and etapa_idx < _ultima_etapa() and not _tempo_partida_acabou():
		var c: Dictionary = etapas_cfg[etapa_idx + 1]
		proxima = "%s — %d m" % [c.nome, int(c.get("diametro", 30))]
	var titulo := "MORTE SÚBITA — RESULTADO" if morte_subita else "RESULTADO — " + _texto_etapa()
	hud.resultado_etapa({"titulo": titulo, "jogadores": jogadores, "equipes": equipes, "melhor": melhor, "proxima": proxima})


func _tempo_partida_acabou() -> bool:
	return tempo_modo == "partida" and tempo_restante <= 0.0


func _proxima() -> void:
	if morte_subita:
		_decidir_morte_subita()
	elif etapa_idx < _ultima_etapa() and not _tempo_partida_acabou():
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
		_iniciar_etapa(_ultima_etapa())
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
	hud.resultado_final({"titulo": titulo, "subtitulo": Config.nome_mapa() + " — resultado final", "equipes": equipes,
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
	if alvo.gravata:
		# Gravata: câmera de frente para o comprimento (o meio é fino demais para duas filas)
		para_cam = alvo.eixo.cross(Vector3.UP).normalized()
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
		if alvo.gravata:
			# Ao longo do comprimento, dos dois lados do MVP (no meio)
			x = (6.5 + 6.5 * (i / 2)) * (1.0 if i % 2 == 0 else -1.0)
			_posicionar_comemoracao(fila[i], c + lado * x, para_cam.rotated(Vector3.UP, -x * 0.03), 1.0)
			continue
		_posicionar_comemoracao(fila[i], c + lado * x - para_cam * 3.5, para_cam.rotated(Vector3.UP, -x * 0.03), 1.0)
	# MVP na frente (na gravata, no meio)
	var pos_mvp := c if alvo.gravata else c + para_cam * 3.5
	var avatar_mvp := _posicionar_comemoracao(mvp, pos_mvp, para_cam, 1.6)
	var holofote := SpotLight3D.new()
	holofote.light_color = Color(1.0, 0.9, 0.7)
	holofote.light_energy = 12.0
	holofote.spot_range = 30.0
	holofote.spot_angle = 18.0
	holofote.shadow_enabled = true
	add_child(holofote)
	holofote.global_position = pos_mvp + Vector3.UP * 16.0 + para_cam * 4.0
	holofote.look_at(pos_mvp, lado)
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
	nome.global_position = avatar_mvp.global_position + Vector3.UP * 2.5 if avatar_mvp else pos_mvp + Vector3.UP * (v_mvp.caixa_corpo.end.y + 1.2)
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
	if not _corrida.is_empty() and fase == Fase.ATIVA and not v.eliminado and not _chegadas.has(v):
		_chegadas.append(v)
		if v == jogador.veiculo:
			hud.mensagem("VOCÊ CHEGOU EM %dº!" % _chegadas.size(), Color(1.0, 0.85, 0.4), 3.0)


## Corrida: quantos pontuam (fração dos participantes da etapa, arredondado para cima).
## Pontos pela ordem de chegada (regras.corrida.pontos): [1º, 2º, ..., demais]. O último valor
## vale para todos dali em diante, até completar as vagas. Número único = todos iguais.
func _pontos_chegada(lugar: int) -> int:
	var tabela = _corrida.get("pontos", 10)
	if tabela is Array and not tabela.is_empty():
		return int(tabela[mini(lugar, tabela.size() - 1)])
	return int(tabela)


func _vagas_corrida() -> int:
	return maxi(1, ceili(float(_corrida.get("fracao_pontuam", 0.3)) * _ativos().size()))


## Climb to Death: registra a passagem pelos pontos de checagem (blip e aviso para o jogador).
func _checar_checkpoints() -> void:
	var sub := complexos[0] as ComplexoSubida
	if sub == null or sub.checkpoints.is_empty():
		return
	for p in _ativos():
		var v: Veiculo = p.veiculo
		if v.eliminado or v.travado:
			continue
		var k := sub.checkpoint_em(v.global_position, v.checkpoint)
		if k < 0:
			continue
		v.checkpoint = k
		if Sessao.teste_automatico and OS.get_environment("TSC_CP_LOG") != "":
			print("[CP] %s passou no checkpoint %d t=%.1f" % [v.nome_piloto, k + 1, v.relogio])
		if v == jogador.veiculo:
			Audio.checkpoint()
			sub.piscar_checkpoint(k)
			hud.mensagem("CHECKPOINT %d/%d" % [k + 1, sub.checkpoints.size()], Color(1.0, 0.88, 0.45), 2.0)


func _ao_ressurgir(v: Veiculo) -> void:
	_evento("ressurgiu(fantasma) " + v.nome_piloto)
	var perdeu_vaga := _chegadas.has(v)
	_chegadas.erase(v)   # tocou o alvo mas explodiu depois: perde a vaga (e tenta de novo)
	var controle = participantes.filter(func(p): return p.veiculo == v).front().controle
	if controle is PilotoBot:
		controle.ao_ressurgir()
	if Sessao.teste_automatico:
		print("[CP] %s ressurgiu no checkpoint %d (quedas %d) t=%.1f" % [v.nome_piloto, v.checkpoint + 1, int(v.telemetria.get("quedas", 0)), v.relogio])
	if v == jogador.veiculo:
		camera.seguir(v, true)
		var onde := "DE VOLTA NO CHECKPOINT %d" % (v.checkpoint + 1) if v.checkpoint >= 0 else "DE VOLTA NA LARGADA"
		if perdeu_vaga:
			hud.mensagem("PERDEU A VAGA — " + onde, Estilo.PERIGO, 3.0)
		else:
			hud.mensagem(onde, Color(1.0, 0.88, 0.45), 2.5)


func _ao_murchar_velame(v: Veiculo) -> void:
	if v == jogador.veiculo and fase == Fase.ATIVA:
		hud.mensagem("VELAME MURCHO!", Estilo.PERIGO, 2.0)


func _ao_eliminar(v: Veiculo) -> void:
	_evento("explodiu " + v.nome_piloto)
	_chegadas.erase(v)   # tocou o alvo mas explodiu depois: perde a vaga
	if v == jogador.veiculo:
		hud.mensagem("CAIU NO BURACO!" if v.telemetria.get("motivo", "") == "buraco" else "EXPLODIU!", Estilo.PERIGO, 3.0)
		hud.espectador("VOCÊ EXPLODIU — 0 PONTOS NESTA ETAPA")
		_t_eliminado = float(Config.valor("partida.espectador_apos_explosao_s", 4))


func _ao_ejetor(_v: Veiculo) -> void:
	_evento("ejetor")
	if fase == Fase.ESTABILIZACAO:
		estab_t = float(Config.valor("partida.estabilizacao_s", 5))


func _bot_falou(bot: PilotoBot, texto: String) -> void:
	hud.chat(bot.veiculo.nome_piloto, bot.veiculo.cor_equipe, texto)


func _atualizar_zona_jogador() -> void:
	var v: Veiculo = jogador.veiculo
	if not v.travado or v.eliminado or fase not in [Fase.ATIVA, Fase.ESTABILIZACAO] or not _corrida.is_empty():
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
	if not _corrida.is_empty() and v in _chegadas:
		return ["%dº A CHEGAR" % (_chegadas.find(v) + 1), Color(1.0, 0.85, 0.4)]
	if v.travado:
		var z := alvo.zona_do_veiculo(v) if v.relogio - v.ultimo_contato_alvo < 0.5 else 0
		return ["ZONA %d" % z, Color(1.0, 0.85, 0.4)] if z > 0 else ["FORA DO ALVO", Estilo.PERIGO]
	if v.esta_voando():
		return ["VOANDO", Estilo.DESTAQUE]
	if v.complexo is ComplexoSubida:
		var st: String = (v.complexo as ComplexoSubida).status_texto(v.global_position)
		return [st, Estilo.TEXTO if st == "SUBINDO" else Estilo.TEXTO_FRACO]
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
	var etapa_txt := "MORTE SÚBITA" if morte_subita else _texto_etapa()
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
	Audio.silenciar_efeitos(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://cenas/menu.tscn")


## Câmera fixa para conferir estruturas nas capturas (TSC_CAM_VISTA = muro, base ou colunas).
func _vista_debug(vista: String) -> void:
	var cx := complexos[0]
	var sub := cx as ComplexoSubida
	if sub and vista.begins_with("subida"):
		camera.cam.far = 20000.0
		match vista:
			"subida_mapa":   # percurso inteiro visto de cima
				camera.podio(Vector3(-700.0, 0.0, -450.0), Vector3(-700.0, 2600.0, -250.0))
			"subida_final":   # parte final vista de cima como no desenho do dono: leste para cima, alvo à direita
				camera.podio(Vector3(-100.0, 0.0, -430.0), Vector3(-125.0, 1150.0, -430.0))
			"subida_tunel":   # boca do túnel-atalho vista de quem chega pela estrada de pouso
				var tc := terreno.tunel_da_etapa()
				if not tc.is_empty():
					var e := Vector3(float(tc.entrada[0]), float(tc.altura_entrada), float(tc.entrada[1]))
					var s := Vector3(float(tc.saida[0]), float(tc.altura_saida), float(tc.saida[1]))
					var dh := Vector3(s.x - e.x, 0.0, s.z - e.z).normalized()
					var perto := OS.get_environment("TSC_TUNEL_PERTO")
					if perto == "costas":   # lado da saída de longe (a encosta toda em volta da boca)
						camera.podio(s, s + dh * 170.0 + dh.cross(Vector3.UP) * 110.0 + Vector3.UP * 25.0)
					elif perto == "frente":   # lado da entrada de longe
						camera.podio(e, e - dh * 170.0 - dh.cross(Vector3.UP) * 90.0 + Vector3.UP * 20.0)
					elif perto == "saida":   # rampa da saída vista de fora, de lado
						camera.podio(s + dh * 12.0, s + dh * 70.0 + dh.cross(Vector3.UP) * 40.0 + Vector3.UP * 18.0)
					elif perto == "dentro":
						camera.podio(e + (s - e) * 0.5, e + dh * 3.0 + Vector3.UP * 1.8)
					elif perto != "":
						camera.podio(e + Vector3.UP * 3.0, e - dh * 35.0 + Vector3.UP * 5.0)
					else:
						camera.podio(e + Vector3.UP * 3.0, e - dh * 190.0 + Vector3.UP * 45.0 + dh.cross(Vector3.UP) * 30.0)
			"subida_paredao":   # buraco do paredão fino visto da baía (TSC_TUNEL_PERTO=longe: de longe)
				var pc := terreno.paredao_da_etapa()
				if not pc.is_empty():
					var pa := Vector3(float(pc.a[0]), 0.0, float(pc.a[1]))
					var pb := Vector3(float(pc.b[0]), 0.0, float(pc.b[1]))
					var dw := (pb - pa).normalized()
					var nw := dw.cross(Vector3.UP)
					var cc: Array = pc.buraco.centro
					var cb := pa + dw * (Vector3(float(cc[0]), 0.0, float(cc[1])) - pa).dot(dw)
					cb.y = float(pc.buraco.get("altura_centro", 140.0))
					var longe := OS.get_environment("TSC_TUNEL_PERTO") == "longe"
					camera.podio(cb, cb + nw * (150.0 if longe else 30.0) + dw * (60.0 if longe else 12.0) + Vector3.UP * (40.0 if longe else 4.0))
			"subida_extra":   # estrada extra da etapa vista de logo depois da rampa final (como no voo)
				camera.podio(Vector3(40.0, 185.0, -600.0), Vector3(0.0, 245.0, -840.0))
			"subida_estrada":   # no trecho de cima da estrada, olhando para leste (parede de um lado, muralha do outro)
				camera.podio(Vector3(-150.0, 225.0, -1095.0), Vector3(-560.0, 212.0, -1092.0))
			"subida_livre":   # TSC_CAM_POS="x,y,z" e TSC_CAM_ALVO="x,y,z" (conferir fotos do dono)
				var pos := OS.get_environment("TSC_CAM_POS").split_floats(",")
				var mira := OS.get_environment("TSC_CAM_ALVO").split_floats(",")
				camera.podio(Vector3(mira[0], mira[1], mira[2]), Vector3(pos[0], pos[1], pos[2]))
			"subida_alvo":   # alvo de lado
				camera.podio(alvo.centro_base, alvo.centro_base + Vector3(70.0, 12.0, -25.0))
			"subida_largada":
				camera.podio(sub.largada.pa(35.0, 0.0, sub.largada.piso_y), sub.largada.pa(-40.0, -60.0, sub.largada.piso_y + 45.0))
			"subida_plataforma":
				camera.podio(sub.plataforma.pa(50.0, 0.0, sub.plataforma.piso_y), sub.plataforma.pa(130.0, -90.0, sub.plataforma.piso_y + 60.0))
			"subida_salto":
				var borda := sub.amostra(sub.fim_do_trecho(sub.indice_estrada(Vector3(-600.0, 150.0, -300.0))))
				camera.podio(borda + Vector3(0.0, -10.0, -15.0), borda + Vector3(70.0, 10.0, 20.0))
			_:   # "subida": da rampa final olhando o alvo
				var fim := sub.amostra(99999)
				camera.podio(alvo.centro_base, fim + Vector3(25.0, 30.0, -60.0))
		return
	var y0: float = cx.perfil.pontos[0].y
	var x_borda: float = cx.perfil.pontos[cx.perfil.indice_borda].x
	if vista.begins_with("geral") or vista.begins_with("borda"):
		# geralN / bordaN: complexo da equipe N visto de lado (inteiro / só a borda da plataforma)
		var c2 := complexos[int(vista.right(1))]
		var xb: float = c2.perfil.pontos[c2.perfil.indice_borda].x
		var alvo_v := c2.ponto(xb + (200.0 if vista.begins_with("geral") else 10.0), c2.perfil.pontos[0].y - (120.0 if vista.begins_with("geral") else 25.0))
		var dist := 520.0 if vista.begins_with("geral") else 120.0
		camera.podio(alvo_v, alvo_v + c2.lateral * dist + Vector3.UP * dist * 0.15)
		camera.cam.far = 20000.0
		return
	var arena := cx as ComplexoArena
	if arena and vista.begins_with("arena"):
		# arena: vista geral de cima; arena_portao: de dentro, olhando a saída; arena_lado: pedestal de fora
		var meio := arena.pa(arena.comprimento * 0.5, 0.0, arena.piso_y)
		camera.cam.far = 20000.0
		match vista:
			"arena_portao":
				var f := arena.pa(arena.comprimento, 0.0, arena.piso_y + 4.0)
				camera.podio(f, arena.pa(arena.comprimento - 45.0, -12.0, arena.piso_y + 9.0))
			"arena_lado":
				camera.podio(meio + Vector3.DOWN * 12.0, meio + arena.lateral * 150.0 - arena.frente * 60.0 + Vector3.UP * 20.0)
			"arena_descida":
				var xb: float = arena.perfil.pontos[arena.perfil.indice_borda].x
				var f := arena.ponto(xb + 60.0, arena.perfil.altura_em(xb + 60.0))
				camera.podio(f, f + arena.lateral * 45.0 - arena.frente * 30.0 + Vector3.UP * 25.0)
			"arena_buraco":
				var h: Array = arena.buracos[2]
				var f := arena.pa(h[0].x, h[0].y, arena.piso_y - 10.0)
				camera.podio(f, arena.pa(h[0].x - 14.0, h[0].y + 6.0, arena.piso_y + 12.0))
			"arena_trem":
				var c := alvo.position
				var lado := alvo.direcao_mov.cross(Vector3.UP)
				camera.podio(c + Vector3.DOWN * 24.0 + alvo.direcao_mov * 8.0, c + Vector3.DOWN * 18.0 + lado * 16.0 + alvo.direcao_mov * 2.0)
			"arena_alvo":
				var c := alvo.centro_base
				camera.podio(c, c - arena.frente * 20.0 + arena.lateral * 45.0 + Vector3.UP * 38.0)
			"arena_canion":   # de cima da borda da descida, olhando o cânion até o alvo
				var xb: float = arena.perfil.pontos[arena.perfil.indice_borda].x
				camera.podio(alvo.centro_base, arena.ponto(xb - 40.0, arena.piso_y + 90.0))
			"arena_fundo":   # de dentro, olhando o letreiro do muro do fundo
				camera.podio(arena.pa(0.0, 0.0, arena.piso_y + 16.0), arena.pa(arena.comprimento - 25.0, 8.0, arena.piso_y + 7.0))
			"arena_mapa":   # vale inteiro visto de cima (rampa → alvo)
				var s := arena.ponto(arena.perfil.comprimento_horizontal, arena.perfil.altura_saida)
				var meio_v := (s + alvo.centro_base) * 0.5
				camera.podio(meio_v, Vector3(meio_v.x, 0.0, meio_v.z) + Vector3.UP * 1900.0 + arena.frente * 250.0)
			"arena_canion_alvo":   # de cima do alvo, olhando de volta para a rampa
				var s := arena.ponto(arena.perfil.comprimento_horizontal, arena.perfil.altura_saida)
				camera.podio(s, alvo.centro_base + (alvo.centro_base - s).normalized() * 250.0 + Vector3.UP * 160.0)
			_:
				camera.podio(meio, meio - arena.frente * 95.0 + arena.lateral * 55.0 + Vector3.UP * 85.0)
		return
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
		# Calibração de desenhos feitos sobre a foto: onde pontos do mundo (chão) caem na imagem
		if OS.get_environment("TSC_MARCAS") != "":
			var cam3 := get_viewport().get_camera_3d()
			for w: Vector3 in [Vector3(0, 0, 0), Vector3(0, 0, -800), Vector3(-500, 0, -800), Vector3(0, 0, 200), Vector3(300, 0, -400), alvo.global_position * Vector3(1, 0, 1)]:
				var px := cam3.unproject_position(w)
				print("[MARCA] x=%.0f z=%.0f -> px %.1f %.1f" % [w.x, w.z, px.x, px.y])
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
	var sub_t := complexos[0] as ComplexoSubida
	if sub_t and t.has("pos_eliminado"):
		var pe0: Vector3 = t.pos_eliminado
		var ie := sub_t.indice_estrada(pe0, 40.0)
		if t.has("paraquedas_pos"):
			var pp: Vector3 = t.paraquedas_pos
			var ip := sub_t.indice_estrada(pp, 60.0)
			print("        paraquedas em: %s  estrada perto=%s progresso=%.0f recinto=%s" % [str(pp.snapped(Vector3.ONE * 0.1)), str(sub_t.amostra(ip).snapped(Vector3.ONE * 0.1)) if ip >= 0 else "-", sub_t.progresso_amostra(ip) if ip >= 0 else -1.0, str(sub_t.recinto_em(pp + Vector3.UP * 3.0))])
		print("        onde: %s terreno=%.1f amostra=%d eixo=%s progresso=%.0f" % [str(pe0.snapped(Vector3.ONE * 0.1)), terreno.altura_em(pe0.x, pe0.z), ie, str(sub_t.amostra(ie).snapped(Vector3.ONE * 0.1)) if ie >= 0 else "-", sub_t.x_perfil(pe0)])
	var arena := complexos[0] as ComplexoArena
	if arena and t.has("pos_eliminado"):
		var pe: Vector3 = t.pos_eliminado
		var l := arena.local(pe)
		print("        onde: x=%.1f lat=%.1f y=%.1f (piso %.0f, terreno %.1f)" % [l.x, l.y, pe.y, arena.piso_y, terreno.altura_em(pe.x, pe.z)])


## Avança a barra de carregamento e deixa a tela desenhar antes do próximo passo pesado.
func _passo_carga(valor: float) -> void:
	hud.progresso_carga(valor)
	await get_tree().process_frame
	await get_tree().process_frame


## Conferência do borrachão (TSC_TESTE_BORRACHAO=1): o carro do jogador segura W+S+A na arena e
## imprime o giro e quanto saiu do lugar.
var _borr_t := 0.0
var _borr_ini := Vector3.ZERO
func _teste_borrachao(delta: float) -> void:
	var v: Veiculo = jogador.veiculo
	jogador.controle.ativo = false
	if _borr_t == 0.0:
		_borr_ini = v.global_position
	_borr_t += delta
	v.entrada.acelerar = 1.0
	v.entrada.re = 1.0 if _borr_t < 6.0 else 0.0
	v.entrada.direcao = -1.0 if _borr_t > 1.5 and _borr_t < 6.0 else 0.0
	if fmod(_borr_t, 0.5) < delta:
		print("[BORR] t=%.1f borrachao=%s giro=%.0f°/s deslocou=%.1f m vel=%.1f" % [_borr_t, str(v.borrachao),
			rad_to_deg(v.angular_velocity.y), Vector2(v.global_position.x - _borr_ini.x, v.global_position.z - _borr_ini.z).length(), v.linear_velocity.length()])
	if _borr_t > 7.5:
		get_tree().quit()


## Pista de provas da direção (TSC_TESTE_CURVA=1): plataforma plana gigante no céu, só o carro do
## jogador. Para cada velocidade: acelera reto até ela e esterça tudo por 3 s (com W segurado ou,
## com TSC_CURVA_SEM_W, tirando o pé). Imprime derrapagem da carroceria (graus), giro real x giro
## que o volante pede e quanto cada eixo está no limite de aderência (1 = no limite).
var _cv := {}
func _teste_curva(delta: float) -> void:
	var v: Veiculo = jogador.veiculo
	if _cv.is_empty():
		var chao := StaticBody3D.new()
		chao.collision_layer = 1
		chao.add_to_group("estrutura")
		var cs := CollisionShape3D.new()
		var caixa := BoxShape3D.new()
		caixa.size = Vector3(4000.0, 2.0, 4000.0)
		cs.shape = caixa
		chao.add_child(cs)
		add_child(chao)
		chao.global_position = Vector3(0.0, 1499.0, 0.0)
		for p in participantes:
			p.controle.ativo = false
			if p != jogador:
				p.veiculo.congelar(true)
		var vels: Array = []
		for s in OS.get_environment("TSC_CURVA_VELS").split(",", false):
			vels.append(float(s))
		if vels.is_empty():
			vels = [15.0, 25.0, 35.0, 45.0]
		_cv = {"vels": vels, "i": -1, "fase": "reset", "t": 0.0, "log": 0.0}
	match _cv.fase:
		"reset":
			_cv.i += 1
			if _cv.i >= _cv.vels.size():
				get_tree().quit()
				return
			v.preparar(Transform3D(Basis(), Vector3(-1500.0, 1500.8, 1500.0)))
			v.congelar(false)
			_cv.fase = "acelera"
			_cv.t = 0.0
		"acelera":
			_cv.t += delta
			v.entrada.acelerar = 1.0
			v.entrada.direcao = 0.0
			if v.linear_velocity.length() >= float(_cv.vels[_cv.i]) or _cv.t > 40.0:
				_cv.fase = "curva"
				_cv.t = 0.0
				_cv.log = 0.0
				print("[CURVA] ---- %.0f m/s (%.0f km/h)%s" % [_cv.vels[_cv.i], float(_cv.vels[_cv.i]) * 3.6, " sem W" if OS.get_environment("TSC_CURVA_SEM_W") != "" else ""])
		"curva":
			_cv.t += delta
			v.entrada.acelerar = 0.0 if OS.get_environment("TSC_CURVA_SEM_W") != "" else 1.0
			v.entrada.direcao = 1.0
			_cv.log -= delta
			if _cv.log <= 0.0 and not v.diag.is_empty():
				_cv.log = 0.25
				var b := v.global_transform.basis
				var lv := v.linear_velocity
				var v_long := lv.dot(-b.z)
				var v_lat := lv.dot(b.x)
				print("[CURVA] t=%.2f v=%.1f derrapa=%.1f° giro=%.0f°/s pedido=%.0f°/s satF=%.2f satT=%.2f cargaF=%.0f cargaT=%.0f rodas=%d" % [
					_cv.t, lv.length(), rad_to_deg(atan2(v_lat, maxf(absf(v_long), 0.5))), rad_to_deg(-v.angular_velocity.dot(b.y)),
					rad_to_deg(-float(v.diag.w_pedido)), v.diag.sat_f, v.diag.sat_t, v.diag.carga_f, v.diag.carga_t, v.rodas_no_chao])
			if _cv.t > 3.0 or v.eliminado:
				_cv.fase = "reset"


## Conferência da câmera (TSC_CAM_LOG=1): conta os "pulos" (mais de 0,8 m num quadro, em relação
## ao carro) enquanto o carro do jogador está na pista, da saída da arena até a rampa.
var _cam_ant := Vector3.INF
var _cam_pulos := 0
var _cam_quadros := 0
func _log_camera() -> void:
	var v: Veiculo = jogador.veiculo
	var cx := v.complexo
	var xp := cx.x_perfil(v.global_position)
	if v.eliminado or xp < cx.x_inicio_pista or xp > cx.perfil.comprimento_horizontal:
		if _cam_quadros > 0 and _cam_ant != Vector3.INF:
			print("[CAM] quadros na pista=%d pulos=%d" % [_cam_quadros, _cam_pulos])
		_cam_ant = Vector3.INF
		_cam_quadros = 0
		_cam_pulos = 0
		return
	var rel := camera.global_position - v.global_position
	if _cam_ant != Vector3.INF and rel.distance_to(_cam_ant) > 0.8:
		_cam_pulos += 1
	_cam_ant = rel
	_cam_quadros += 1
