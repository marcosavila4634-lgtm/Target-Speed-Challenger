extends Node3D
## Corrida de Drag Racing contra bot (offline): 1/8 de milha na Reta do Canyon, jogador na faixa
## da esquerda em visão interna, bot na faixa da direita (pedido do dono; o dossiê previa uma faixa só).
## Carregamento → preparo (motor ligado, neutro) → semáforo (3 amarelas + verde) → arrancada →
## chegada e frenagem → resultado. Sem pausa depois da contagem (ESC duas vezes abandona).
## A física é a DragMotor (1D, passos fixos); os carros do Target Flight são só a parte visual.
##
## Testes: TSC_DRAG_SIM=1 (tabela de tempos de todos os carros), -- --teste (jogador pilotado por
## bot PRO, imprime [DRAG]), TSC_FOTO_DRAG=<pasta> (capturas), TSC_CAM_VISTA=drag_fora (câmera externa).

enum Fase { CARREGANDO, BORRACHAO, PREPARO, CORRIDA, FIM, RESULTADO }

const DT := 1.0 / 120.0
const ARQ_RECORDES := "user://drag.json"

var fase := Fase.CARREGANDO
var pista: DragPista
var hud: DragHud
var cockpit: DragCockpit
var eu: DragMotor
var rival: DragMotor
var bot: DragBot
var bot_jogador: DragBot          # teste automático
var carro_eu: Veiculo
var carro_rival: Veiculo
var som_eu: DragSom
var som_rival: DragSom
var nome_rival := "RIVAL"
var _c: Dictionary
var _rng := RandomNumberGenerator.new()
var _t_amarela := 0.0            # instante da 1ª amarela (relógio da simulação)
var _relogio := 0.0
var _t_fim := 0.0
var _esc_ate := -1.0
var _vel_ant := [0.0, 0.0]
var _acel := [0.0, 0.0]
var _base_modelo: Array[Transform3D] = []
var _z0 := [0.0, 0.0]
var _anunciou_verde := false
var _teste := false
var _torcida := 0.25          # agitação do público (sobe na verde e na chegada)
## Borrachão antes da largada (cena de TV): recuo dos carros na caixa molhada e relógio da cena.
const RECUO_BORRACHAO := 16.0
const QUEIMA_S := 3.4
const ENCOSTA_S := 2.8
var _t_pre := 0.0
var _cam_tv: Camera3D
var pq_eu: DragParaquedas
var pq_rival: DragParaquedas
var _pq_bot_s := 0.7
var _cam_chegada: Camera3D     # depois da chegada: câmera atrás do carro mostrando o paraquedas


func _ready() -> void:
	_c = Config.valor("drag", {})
	_rng.randomize()
	if OS.get_environment("TSC_DRAG_SIM") != "":
		_simular_tabela()
		return
	_teste = Sessao.teste_automatico
	Audio.silenciar_efeitos(true)
	hud = DragHud.new()
	add_child(hud)
	hud.pedido_repetir.connect(func(): get_tree().reload_current_scene())
	hud.pedido_menu.connect(_ir_menu)
	var dados_eu := Progresso.dados_jogador(Sessao.veiculo_id)
	if dados_eu.is_empty():
		dados_eu = Progresso.dados_jogador(Config.veiculos_ativos()[0].id)
	hud.carregando(str(dados_eu.get("nome", "")))
	await get_tree().process_frame
	await get_tree().process_frame
	var amb := Ambiente.new()
	add_child(amb)
	var pista_cfg := Sessao.drag_pista()
	var estadio := str(pista_cfg.get("estilo", "estadio")) == "estadio"
	# Fim de tarde: sol baixo à frente e à direita (como nas artes). Olhando para o sol o brilho
	# (glow) e o espalhamento da névoa lavavam a tela inteira: aqui ficam bem mais fracos.
	amb.sol.rotation_degrees = Vector3(-7.0 if estadio else -12.0, 212.0, 0.0)
	amb.sol.light_energy = 1.6 if estadio else 2.0
	amb.sol.light_cull_mask = 0xFFFFF & ~DragCockpit.CAMADA_INTERIOR   # interior do cockpit à sombra do teto
	var we := amb.find_children("*", "WorldEnvironment", false, false)
	if not we.is_empty():
		var env: Environment = (we[0] as WorldEnvironment).environment
		env.glow_bloom = 0.0
		env.glow_intensity = 0.5
		env.glow_hdr_threshold = 1.4
		env.fog_sun_scatter = 0.12
		env.fog_density = 0.00008
		env.fog_height_density = 0.002
		# Pista preparada brilhando: reflexos das luzes e do céu na borracha
		env.ssr_enabled = bool(Config.valor("grafico.drag_reflexos", false))
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.1
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.3
	hud.progresso_carga(0.15)
	await get_tree().process_frame
	pista = DragPista.new()
	add_child(pista)
	pista.montar(str(pista_cfg.get("estilo", "estadio")), str(pista_cfg.get("nome", "TSC Dragway")))
	hud.progresso_carga(0.5)
	await get_tree().process_frame
	# Rival: carro e piloto sorteados, nome fictício dos bots
	var ativos := Config.veiculos_ativos()
	var dados_rival: Dictionary = Progresso.dados_bot(ativos[_rng.randi() % ativos.size()], Sessao.veiculo_id)
	var nomes: Array = Config.valor("bots.nomes", ["RIVAL 01"])
	nome_rival = str(nomes[_rng.randi() % nomes.size()]).to_upper()
	carro_eu = _criar_carro(dados_eu, 0, true)
	hud.progresso_carga(0.75)
	await get_tree().process_frame
	carro_rival = _criar_carro(dados_rival, 1, false)
	hud.progresso_carga(0.95)
	await get_tree().process_frame
	eu = DragMotor.new(dados_eu, Progresso.ajustes_drag(str(dados_eu.get("id", ""))))
	rival = DragMotor.new(dados_rival)
	bot = DragBot.new(rival, Sessao.nivel_bots, _rng.randi())
	if _teste:
		bot_jogador = DragBot.new(eu, "pro", _rng.randi())
		Engine.time_scale = float(OS.get_environment("TSC_VELOCIDADE")) if OS.get_environment("TSC_VELOCIDADE") != "" else 1.0
	# Câmera: cockpit do jogador (ou externa para conferência)
	cockpit = DragCockpit.new()
	cockpit.montar(carro_eu)
	cockpit.camera.current = true
	if OS.get_environment("TSC_CAM_VISTA") == "drag_fora":
		var cam := Camera3D.new()
		DragCockpit.sem_interior(cam)
		add_child(cam)
		cam.global_position = Vector3(-9.0, 3.2, 9.0)
		cam.look_at(Vector3(0, 1.0, -6.0))
		cam.current = true
	som_eu = DragSom.new()
	som_eu.montar(eu, carro_eu, true)
	som_rival = DragSom.new()
	som_rival.montar(rival, carro_rival, false)
	pq_eu = DragParaquedas.new()
	pq_eu.montar(carro_eu)
	pq_rival = DragParaquedas.new()
	pq_rival.montar(carro_rival)
	_pq_bot_s = _rng.randf_range(0.4, 1.0)
	_ligar_sinais()
	hud.definir_rival(nome_rival)
	hud.progresso_carga(1.0)
	Audio.musica("partida")
	await hud.esconder_carregando()
	Audio.silenciar_efeitos(false)
	Audio.tocar("motor/partida.wav", null, -4.0, 1.0, 0.0, "Motor")
	# Borrachão na caixa molhada, visto pela câmera de TV (ESPAÇO/ENTER pula); sem ele vai direto ao preparo
	if OS.get_environment("TSC_SEM_BORRACHAO") == "" and OS.get_environment("TSC_CAM_VISTA") != "drag_fora":
		_iniciar_borrachao()
	else:
		_preparar()
	if OS.get_environment("TSC_FOTO_DRAG") != "":
		_fotos(OS.get_environment("TSC_FOTO_DRAG"))


func _criar_carro(dados: Dictionary, faixa: int, jogador: bool) -> Veiculo:
	var v := Veiculo.new()
	v.name = "Carro_" + ("jogador" if jogador else "rival")
	v.dados = dados
	v.sem_som = true
	v.eh_jogador = jogador
	v.indice_equipe = 0 if jogador else 1
	v.cor_equipe = Config.EQUIPES[0 if jogador else 1].cor
	v.nome_piloto = Sessao.nome_jogador if jogador else nome_rival
	v.freeze = true
	if not jogador:
		# Só o rival tem piloto visível (no cockpit genérico do jogador não há avatar)
		var pilotos := Config.avatares_ativos()
		if not pilotos.is_empty():
			v.avatar_dados = pilotos[_rng.randi() % pilotos.size()]
	add_child(v)
	if v.paraquedas:
		v.paraquedas.remover()   # no Drag não há paraquedas de teto (só o de frenagem, atrás)
	for r in v.rodas:
		r.compressao = v.curso * 0.35     # rodas na altura de repouso (o carro não usa a suspensão aqui)
	# Frente do carro na linha de largada
	_z0[faixa] = -v.caixa_corpo.position.z + 0.05
	v.global_transform = Transform3D(Basis.IDENTITY, Vector3(pista.x_faixa(faixa), 0.0, _z0[faixa]))
	v.reset_physics_interpolation()
	v.na_largada = true
	_base_modelo.append((v.get_node("Modelo") as Node3D).transform)
	return v


func _ligar_sinais() -> void:
	eu.trocou.connect(func(de, para, av): hud.avaliacao(av, "%d → %d" % [de, para]))
	eu.largou.connect(func(av):
		if av == "queimada":
			hud.status("QUEIMADA!", DragHud.CORES.queimada)
		hud.avaliacao(av, "LARGADA"))
	eu.reduziu.connect(func(de, para, excessiva):
		if excessiva:
			hud.avaliacao("critica", "REDUÇÃO %d → %d" % [de, para]))
	eu.chegou_fim.connect(func():
		hud.status("CHEGADA", Color(0.55, 0.85, 1.0))
		_torcida = 1.0
		pista.placar(0, eu.tempo_final(), eu.velocidade_chegada * 3.6))
	rival.chegou_fim.connect(func(): pista.placar(1, rival.tempo_final(), rival.velocidade_chegada * 3.6))


func _preparar() -> void:
	fase = Fase.PREPARO
	_relogio = 0.0
	# Preparo com o motor ligado em neutro, depois espera sorteada até a 1ª amarela
	var espera: Array = _c.get("espera_amarela", [1.2, 2.6])
	_t_amarela = 2.5 + _rng.randf_range(float(espera[0]), float(espera[1]))
	var verde := _t_amarela + 2.0 * float(_c.get("intervalo_amarela", 0.5)) + float(_c.get("verde_apos_amarela", 0.5))
	eu.t_verde = verde
	rival.t_verde = verde
	pista.semaforo(0, false, [false, false], false)
	hud.mostrar(true)
	hud.status("PREPARE-SE")



# ------------------------------------------------------------------ borrachão

## Cena de abertura: os dois carros recuados na caixa molhada queimam pneu (fumaça, motor no alto,
## pneus cantando) e depois encostam devagar na linha. Câmera de TV baixa, entre as faixas.
func _iniciar_borrachao() -> void:
	fase = Fase.BORRACHAO
	_t_pre = 0.0
	hud.mostrar(false)
	_cam_tv = Camera3D.new()
	_cam_tv.fov = 55.0
	DragCockpit.sem_interior(_cam_tv)
	add_child(_cam_tv)
	_cam_tv.global_position = Vector3(-5.9, 1.3, -3.0)
	_cam_tv.look_at(Vector3(0.0, 0.8, RECUO_BORRACHAO))
	_cam_tv.current = true
	pista.semaforo(0, false, [false, false], false)


func _passo_borrachao() -> void:
	_t_pre += DT
	var queimando := _t_pre > 0.5 and _t_pre < QUEIMA_S
	var f := clampf((_t_pre - QUEIMA_S) / ENCOSTA_S, 0.0, 1.0)
	var recuo := RECUO_BORRACHAO * (1.0 - f * f * (3.0 - 2.0 * f))
	var vel_encosta := RECUO_BORRACHAO * 6.0 * f * (1.0 - f) / ENCOSTA_S
	for k in 2:
		var v: Veiculo = carro_eu if k == 0 else carro_rival
		var m: DragMotor = eu if k == 0 else rival
		v.global_transform = Transform3D(Basis.IDENTITY, Vector3(pista.x_faixa(k), 0.0, _z0[k] + recuo))
		v.borrachao = queimando
		v.vel_rodas_externa = 38.0 if queimando else vel_encosta
		# Motor e pneus (o som lê o estado da simulação, que ainda não está rodando)
		m.rpm = (6200.0 + sin(_t_pre * (9.0 + k)) * 500.0) if queimando else lerpf(m.rpm, 1500.0, 0.05)
		m.acelerador = 1.0 if queimando else 0.2
		m.patinando = queimando
	# Câmera acompanha de leve os carros chegando
	_cam_tv.look_at(Vector3(0.0, 0.8, _z0[0] + recuo * 0.8))
	if _t_pre >= QUEIMA_S + ENCOSTA_S:
		_fim_borrachao()


func _fim_borrachao() -> void:
	for k in 2:
		var v: Veiculo = carro_eu if k == 0 else carro_rival
		var m: DragMotor = eu if k == 0 else rival
		v.borrachao = false
		v.vel_rodas_externa = 0.0
		v.global_transform = Transform3D(Basis.IDENTITY, Vector3(pista.x_faixa(k), 0.0, _z0[k]))
		v.reset_physics_interpolation()
		m.rpm = float(_c.get("rpm_lenta", 900))
		m.acelerador = 0.0
		m.patinando = false
	if _cam_tv:
		_cam_tv.queue_free()
		_cam_tv = null
	cockpit.camera.current = true
	_preparar()


# ------------------------------------------------------------------ simulação

func _physics_process(_delta: float) -> void:
	if eu == null or fase == Fase.CARREGANDO or fase == Fase.RESULTADO:
		return
	if fase == Fase.BORRACHAO:
		_passo_borrachao()
		return
	# Entradas do jogador (o câmbio chega por _unhandled_input)
	if bot_jogador:
		bot_jogador.pilotar(DT)
	elif not eu.chegou:
		eu.acelerador = Input.get_action_strength("acelerar")
		eu.nitro_pedido = Input.is_action_pressed("nitro")
	bot.pilotar(DT)
	eu.passo(DT)
	rival.passo(DT)
	_relogio = eu.tempo
	_atualizar_carro(carro_eu, eu, 0)
	_atualizar_carro(carro_rival, rival, 1)
	_paraquedas()
	cockpit.atualizar(DT, float(_acel[0]), eu.rpm / float(_c.get("rpm_limite", 8000)), eu.velocidade)
	_semaforo()
	# Fim: os dois pararam depois da chegada, ou tempo esgotado (quem não chegou não completou)
	if fase == Fase.PREPARO and _relogio >= eu.t_verde:
		fase = Fase.CORRIDA
	if fase == Fase.CORRIDA:
		var parados := eu.chegou and rival.chegou and eu.velocidade < 12.0
		if parados or _relogio > eu.t_verde + 25.0 or (eu.chegou and _relogio > eu.t_chegada + 12.0):
			fase = Fase.FIM
			_t_fim = _relogio
	elif fase == Fase.FIM and _relogio > _t_fim + 1.2:
		_terminar()


## Paraquedas de frenagem: o jogador abre com E depois da chegada (senão abre sozinho); o bot abre
## logo depois de cruzar.
func _paraquedas() -> void:
	var auto := float(_c.get("paraquedas_auto_s", 1.2))
	if eu.chegou and not eu.paraquedas and (bot_jogador != null or _relogio > eu.t_chegada + auto):
		_abrir_paraquedas(eu, pq_eu)
	if rival.chegou and not rival.paraquedas and _relogio > rival.t_chegada + _pq_bot_s:
		_abrir_paraquedas(rival, pq_rival)
	pq_eu.definir_velocidade(eu.velocidade)
	pq_rival.definir_velocidade(rival.velocidade)
	# Câmera de perseguição: sai do cockpit para mostrar o paraquedas abrindo
	if eu.chegou and _relogio > eu.t_chegada + 1.0 and OS.get_environment("TSC_CAM_VISTA") != "drag_fora":
		if _cam_chegada == null:
			_cam_chegada = Camera3D.new()
			_cam_chegada.fov = 60.0
			DragCockpit.sem_interior(_cam_chegada)
			add_child(_cam_chegada)
			_cam_chegada.current = true
		var alvo := carro_eu.global_position + Vector3(0, 1.2, 0)
		_cam_chegada.global_position = alvo + Vector3(-3.1, 2.3, 13.0)
		_cam_chegada.look_at(alvo + Vector3(0.4, 0.3, 4.0))


func _abrir_paraquedas(m: DragMotor, pq: DragParaquedas) -> void:
	if m.paraquedas or not m.chegou:
		return
	m.paraquedas = true
	pq.abrir()


func _atualizar_carro(v: Veiculo, m: DragMotor, faixa: int) -> void:
	v.global_transform = Transform3D(Basis.IDENTITY, Vector3(pista.x_faixa(faixa), 0.0, _z0[faixa] - m.distancia))
	var a := (m.velocidade - float(_vel_ant[faixa])) / DT
	_vel_ant[faixa] = m.velocidade
	_acel[faixa] = lerpf(float(_acel[faixa]), a, 1.0 - exp(-DT * 6.0))
	# Carroceria: levanta o nariz acelerando e abaixa freando (só o corpo, as rodas ficam no chão)
	var arfagem := clampf(float(_acel[faixa]) * 0.0045, -0.035, 0.05)
	var modelo := v.get_node("Modelo") as Node3D
	modelo.transform = Transform3D(Basis(Vector3.RIGHT, arfagem), Vector3(0, arfagem * 0.6, 0)) * _base_modelo[faixa]
	v.vel_rodas_externa = m.velocidade + (9.0 if m.patinando else 0.0)
	v.nitro_ativo = m.nitro_ativo


func _semaforo() -> void:
	var amarelas := 0
	if _relogio >= _t_amarela:
		amarelas = mini(1 + int((_relogio - _t_amarela) / float(_c.get("intervalo_amarela", 0.5))), 3)
	var verde := _relogio >= eu.t_verde
	var vermelha := [eu.queimada, rival.queimada]
	pista.semaforo(amarelas, verde, vermelha, _relogio > 1.0)
	if fase == Fase.PREPARO and _relogio > 1.0 and not eu.queimada:
		hud.status("AGUARDE A LUZ VERDE")
	if verde and not _anunciou_verde:
		_anunciou_verde = true
		_torcida = 1.0
		if not eu.queimada:
			hud.status("VAI!", Color(0.3, 1.0, 0.45))


func _process(delta: float) -> void:
	if eu == null or cockpit == null:
		return
	var tempo_corrida := 0.0
	if _relogio >= eu.t_verde:
		tempo_corrida = (eu.t_chegada if eu.chegou else _relogio) - eu.t_verde
	if fase != Fase.RESULTADO:
		hud.atualizar(delta, eu, rival, tempo_corrida)
	cockpit.instrumentos(eu, delta)
	_torcida = move_toward(_torcida, 0.25, delta * 0.15)
	pista.animar_publico(_torcida)


func _unhandled_input(evento: InputEvent) -> void:
	if eu == null or fase == Fase.CARREGANDO:
		return
	if evento.is_action_pressed("pausa"):
		# Sem pausa no drag: ESC duas vezes abandona a corrida
		if fase == Fase.RESULTADO:
			return
		var agora := Time.get_ticks_msec() / 1000.0
		if agora < _esc_ate:
			_ir_menu()
		else:
			_esc_ate = agora + 2.0
			hud.avaliacao("boa", "ESC DE NOVO PARA SAIR")
		return
	if fase == Fase.BORRACHAO and (evento.is_action_pressed("ejetor") or evento.is_action_pressed("ui_accept")):
		_fim_borrachao()
		return
	if evento.is_action_pressed("paraquedas") and eu.chegou:
		_abrir_paraquedas(eu, pq_eu)
		return
	if bot_jogador or fase == Fase.RESULTADO:
		return
	if evento.is_action_pressed("subir_marcha") and not evento.is_echo():
		eu.subir_marcha()
	elif evento.is_action_pressed("reduzir_marcha") and not evento.is_echo():
		eu.reduzir_marcha()


# ------------------------------------------------------------------ resultado

func _terminar() -> void:
	fase = Fase.RESULTADO
	var te := eu.tempo_final()
	var tr := rival.tempo_final()
	var empate := te < INF and absf(te - tr) < 0.0005
	var vitoria := not empate and te < tr
	pista.placar(0, te, eu.velocidade_chegada * 3.6, vitoria or empate)
	pista.placar(1, tr, rival.velocidade_chegada * 3.6, not vitoria)
	var recordes := _ler_recordes()
	var id := str(carro_eu.dados.get("id", ""))
	var anterior := float(recordes.get(id, INF))
	var recorde := te < INF and te < anterior
	if recorde:
		recordes[id] = te
		_salvar_recordes(recordes)
	if _teste or OS.get_environment("TSC_FOTO_DRAG") != "":
		print("[DRAG] %s %.3f (reação %.3f, largada %s, trocas %s, nitro %d) x %s %.3f -> %s" % [id, te, eu.reacao(), eu.largada,
			str(eu.trocas.map(func(t): return t.avaliacao)), eu.nitro_marcha, nome_rival, tr, "VITÓRIA" if vitoria else ("EMPATE" if empate else "DERROTA")])
	# XP para o carro (não no teste automático nem nas capturas)
	var xp := {}
	if not _teste and OS.get_environment("TSC_FOTO_DRAG") == "":
		var tab: Dictionary = _c.get("xp", {})
		var ganho := int(tab.get("corrida", 20))
		if vitoria and not eu.queimada:
			ganho += int(tab.get("vitoria", 30))
		if recorde:
			ganho += int(tab.get("recorde", 15))
		ganho += eu.trocas.filter(func(t): return t.avaliacao == "perfeita").size() * int(tab.get("troca_perfeita", 2))
		if eu.largada == "perfeita":
			ganho += int(tab.get("largada_perfeita", 5))
		xp = Progresso.ganhar_xp(id, ganho)
	Audio.interface("confirmar", -4.0)
	hud.resultado({"vitoria": vitoria, "empate": empate, "nome": Sessao.nome_jogador, "rival": nome_rival,
		"meu": eu, "dele": rival, "recorde": recorde, "recorde_anterior": anterior, "xp": xp})
	if _teste and OS.get_environment("TSC_FOTO_DRAG") == "":
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()


func _ler_recordes() -> Dictionary:
	if not FileAccess.file_exists(ARQ_RECORDES):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(ARQ_RECORDES))
	return d.get("recordes", {}) if d is Dictionary else {}


func _salvar_recordes(r: Dictionary) -> void:
	var f := FileAccess.open(ARQ_RECORDES, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"recordes": r}, "\t"))


func _ir_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://cenas/menu.tscn")


# ------------------------------------------------------------------ testes

## Capturas: preparo, amarelas, arrancada, meio da pista, chegada e resultado.
func _fotos(pasta: String) -> void:
	DirAccess.make_dir_recursive_absolute(pasta)
	var marcos := [["0_borrachao", func(): return fase == Fase.BORRACHAO and _t_pre > 2.2], ["1_preparo", func(): return _relogio > 1.6], ["2_amarela", func(): return _relogio > _t_amarela + 1.05],
		["3_verde", func(): return _relogio > eu.t_verde + 0.25], ["4_meio", func(): return eu.distancia > 90.0],
		["5_chegada", func(): return eu.distancia > 195.0], ["6_paraquedas", func(): return eu.chegou and _relogio > eu.t_chegada + 2.2],
		["7_resultado", func(): return fase == Fase.RESULTADO]]
	for mc: Array in marcos:
		if mc[0] == "0_borrachao" and fase != Fase.BORRACHAO:
			continue   # sem a cena de borrachão (TSC_SEM_BORRACHAO / vista de fora)
		while not (mc[1] as Callable).call():
			await get_tree().process_frame
		if mc[0] == "7_resultado":
			await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("%s/drag_%s.png" % [pasta, mc[0]])
	get_tree().quit()


## Tabela de tempos: corrida perfeita e bots de cada nível em todos os carros.
func _simular_tabela() -> void:
	if OS.get_environment("TSC_DRAG_SIM") == "ajustes":
		var d := Progresso.dados_jogador("asti89")
		for aj: Dictionary in [{}, {"final": 1.15}, {"final": 0.88}, {"pneu_traseiro": 16}, {"pneu_traseiro": 28}, {"nitro": 1.3}, {"nitro": 0.7}, {"marchas": [3.4, 2.3, 1.7, 1.3, 1.05, 0.86]}]:
			print(aj, " ", DragMotor.prever(d, aj))
		get_tree().quit()
		return
	for d in Config.veiculos_ativos():
		var linha := "%-14s" % d.id
		for nivel in ["perfeito", "facil", "medio", "alto", "pro"]:
			var m := DragMotor.new(Progresso.dados_jogador(d.id))
			m.t_verde = 2.0
			var b := DragBot.new(m, "pro" if nivel == "perfeito" else nivel, 7)
			if nivel == "perfeito":
				b._reacao = 0.15
				b._queimar = false
				b._rpm_largada = 4900.0
				b._nitro_marcha = int(OS.get_environment("TSC_NM")) if OS.get_environment("TSC_NM") != "" else 3
			while not m.chegou and m.tempo < 40.0:
				if nivel == "perfeito":
					b._rpm_troca = float(_c.get("centro_perfeito", 7300))
				b.pilotar(DT)
				m.passo(DT)
			linha += "  %s %.3f(%3.0f)" % [nivel.substr(0, 3), m.tempo_final(), m.velocidade_chegada * 3.6]
		print(linha)
	get_tree().quit()
