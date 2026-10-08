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
var gravador: Gravador          # grava as etapas jogadas (gravacoes/) para estudar a pilotagem

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
## regras.corrida.sem_tempo (Serpent's Climb): a etapa não tem limite — o relógio conta para cima e para
## quando as vagas se completam. tempo_restante guarda o tempo decorrido.
var _sem_tempo := false
## Extinction Day: tempo total da etapa (o meteoro chega conforme ele passa) e a cena do impacto final.
var _tempo_total_etapa := 1.0
var _impacto: ImpactoMeteoro


func _ready() -> void:
	_rng.randomize()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  partida inicio" % Time.get_ticks_msec())
	# (capturas de conferência com TSC_FOTOS não são partidas: não gravam)
	if bool(Config.valor("partida.gravar", true)) and (not Sessao.teste_automatico or OS.get_environment("TSC_GRAVAR") != "") and OS.get_environment("TSC_FOTOS") == "":
		gravador = Gravador.new()
		add_child(gravador)
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
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  mundo construido" % Time.get_ticks_msec())
	await _criar_participantes()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  participantes" % Time.get_ticks_msec())
	var som_ambiente := SomAmbiente.new()
	add_child(som_ambiente)
	som_ambiente.montar(complexos)
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  som ambiente" % Time.get_ticks_msec())
	_preparar_cenario(_etapa_inicial())
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  cenario da etapa" % Time.get_ticks_msec())
	await _passo_carga(1.0)
	await hud.esconder_carregando()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  tela de carga escondida" % Time.get_ticks_msec())
	if Sessao.teste_automatico:
		Engine.time_scale = float(OS.get_environment("TSC_VELOCIDADE")) if OS.get_environment("TSC_VELOCIDADE") != "" else 4.0
	_iniciar_etapa(_etapa_inicial())
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  etapa iniciada" % Time.get_ticks_msec())
	if OS.get_environment("TSC_MALHAS") != "":
		_censo_malhas()
	# Diagnóstico: TSC_PERTO_DE="x,y,z,raio" lista os nós visuais a menos de raio m do ponto (o que há num lugar)
	if OS.get_environment("TSC_PERTO_DE") != "":
		var pd := OS.get_environment("TSC_PERTO_DE").split_floats(",")
		var centro_pd := Vector3(pd[0], pd[1], pd[2])
		for n_pd in find_children("*", "VisualInstance3D", true, false):
			var vi := n_pd as VisualInstance3D
			var caixa_pd := vi.global_transform * vi.get_aabb()
			if caixa_pd.grow(pd[3]).has_point(centro_pd) and caixa_pd.size.length() < 400.0:
				var mat_pd := ""
				if vi is GeometryInstance3D and (vi as GeometryInstance3D).material_override is ShaderMaterial:
					mat_pd = ((vi as GeometryInstance3D).material_override as ShaderMaterial).shader.resource_path.get_file()
				print("[PERTO] %-22s %-70s tam %5.1f %s %s" % [vi.get_class(), str(get_path_to(vi)).right(70), caixa_pd.size.length(), mat_pd,
					("amount=%d" % (vi as GPUParticles3D).amount) if vi is GPUParticles3D else ""])
	# Diagnóstico: TSC_OCULTAR="Rochas,Plataforma100,tipo:MultiMeshInstance3D" esconde os nós com esses nomes (ou desse
	# tipo) para medir quanto cada parte da cena custa na placa de vídeo ([PLACA] com TSC_TRAVADAS=1)
	for alvo_o in OS.get_environment("TSC_OCULTAR").split(",", false):
		var achados := find_children("*", alvo_o.trim_prefix("tipo:"), true, false) if alvo_o.begins_with("tipo:") else find_children(alvo_o, "", true, false)
		for n_o in achados:
			if n_o is Node3D:
				(n_o as Node3D).visible = false
		print("[OCULTAR] %s: %d nós" % [alvo_o, achados.size()])
	if OS.get_environment("TSC_FOTO_FINAL") != "":
		_foto_final(OS.get_environment("TSC_FOTO_FINAL"))
	elif OS.get_environment("TSC_MEDIR_SUPORTE") != "":
		_medir_suportes()
	elif OS.get_environment("TSC_MEDIR_CABECA") != "":
		_medir_cabecas()
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


## Conferência: folga entre o topo da cabeça de cada piloto e o teto de cada carro (negativa = atravessa).
func _medir_cabecas() -> void:
	for d in Config.veiculos_ativos():
		for a in Config.avatares_ativos():
			var v := Veiculo.new()
			v.dados = d
			v.avatar_dados = a
			v.sem_som = true
			v.freeze = true
			add_child(v)
			await get_tree().process_frame
			var folga: float = v.piloto.folga_teto()
			if folga < 0.02:
				print("CAB %-14s %-12s folga=%+.3f escala=%.2f" % [d.id, a.id, folga, v.piloto.escala_rel()])
			v.queue_free()
	print("CAB fim")
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
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  terreno.gerar" % Time.get_ticks_msec())
	await _passo_carga(0.45)
	equipes_qtd = clampi(int(Config.valor("partida.equipes", 4)), 2, 4)
	if Config.mapa_tipo() == "subida":
		# Climb to Death: largada conjunta num cercado no chão, estrada subindo até a rampa final
		var sub := ComplexoSubida.new()
		add_child(sub)
		var e0 := _primeira_etapa()
		if OS.get_environment("TSC_ETAPA") != "":
			e0 = int(OS.get_environment("TSC_ETAPA")) - 1
		ComplexoSubida.etapa_percurso = maxi(e0, 0)   # Serpent's Climb: cada etapa tem o seu percurso
		sub.montar(0, perfil, terreno)
		if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  complexo subida" % Time.get_ticks_msec())
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
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms  alvo" % Time.get_ticks_msec())
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
			await _passo_carga(0.7 + 0.18 * float(e * por_equipe + k + 1) / (equipes_qtd * por_equipe))
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


## TSC_ETAPA=N: começa direto na etapa N (conferência de etapas)
func _etapa_inicial() -> int:
	return clampi(int(OS.get_environment("TSC_ETAPA")) - 1, 0, total_etapas - 1) if OS.get_environment("TSC_ETAPA") != "" else _primeira_etapa()


func _iniciar_etapa(indice: int) -> void:
	_evento("troca de etapa")
	etapa_idx = indice
	Audio.musica_etapa(Config.mapa_id, indice + 1)
	if _cenario_pronto != indice:
		_preparar_cenario(indice)
	_cenario_pronto = -1
	_semaforos(0)
	_iniciar_etapa_participantes()


## Cenário da etapa: terreno, complexo, mapa temático (selva, gelo, ...) e alvo. Na primeira etapa roda antes
## da tela de carga sumir (no Serpent's Climb são vários segundos: rochas, mata, serpentes); nas trocas, no
## começo de _iniciar_etapa.
var _cenario_pronto := -1

func _preparar_cenario(indice: int) -> void:
	etapa_idx = indice
	_cenario_pronto = indice
	terreno.preparar_etapa(indice)  # Canyon Combat: esporões do vale mudam a cada etapa
	if complexos[0].has_method("preparar_etapa"):
		complexos[0].preparar_etapa(indice)   # Climb to Death: túnel-atalho da etapa
	if terreno.egito:
		terreno.egito.preparar_etapa(indice, _cfg_etapa())   # Pharaoh's Climb: obeliscos, portal, tempestade
	if terreno.selva:
		terreno.selva.preparar_etapa(indice, _cfg_etapa())   # Serpent's Climb: colunas da serpente e vento
	if terreno.gelo:
		terreno.gelo.preparar_etapa(indice, _cfg_etapa())   # Frozen Peak: agulhas, muralhas de gelo e nevasca
	if terreno.dino:
		terreno.dino.preparar_etapa(indice, _cfg_etapa())   # Extinction Day: céu da etapa, aurora, meteoro
		# À noite os carros andam de farol aceso (pedido do dono)
		var noite := float((_cfg_etapa().get("ceu", {}) as Dictionary).get("noite", 0.0)) >= 0.25   # E4 (céu do apocalipse) também
		for pt in participantes:
			if pt.veiculo:
				pt.veiculo.farois(noite)
	alvo.configurar(_cfg_etapa())
	if terreno.selva and complexos[0] is ComplexoSubida:
		terreno.selva.montar_serpente_caminho(indice, complexos[0], alvo)   # Serpent's Climb E1: serpente colossal até o ninho (o alvo)


func _iniciar_etapa_participantes() -> void:
	var indice := etapa_idx
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
			# Teste: TSC_CP_INICIO=N larga todo mundo do checkpoint N (para conferir um trecho sem refazer o percurso)
			var cp_ini := OS.get_environment("TSC_CP_INICIO")
			if cp_ini != "" and complexos[0] is ComplexoSubida and int(cp_ini) < (complexos[0] as ComplexoSubida).checkpoints.size():
				v.checkpoint = int(cp_ini)
				var t_cp = complexos[0].ressurgimento(v)
				if t_cp is Transform3D:
					v.preparar((t_cp as Transform3D).translated(-(t_cp as Transform3D).basis.z * (-9.0 * participantes.find(membros[k]))))
					v.checkpoint = int(cp_ini)
			var ativo := e in equipes_ativas
			v.visible = ativo
			if not ativo:
				v.eliminado = true
			if membros[k].controle is PilotoBot:
				membros[k].controle.iniciar_etapa(alvo)
			membros[k].controle.ativo = false
	if tempo_modo == "etapa":
		tempo_restante = tempo_etapa * float(_cfg_etapa().get("tempo_mult", 1.0))   # etapa mais longa/difícil: mais tempo
	_tempo_total_etapa = maxf(tempo_restante, 1.0)
	_corrida = Config.valor("regras.corrida", {})
	_sem_tempo = bool(_corrida.get("sem_tempo", false))
	if _sem_tempo:
		tempo_restante = 0.0
		_tempo_total_etapa = 1.0
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
	var r: Vector3 = sub.amostra(sub.total_amostras() - 1) if sub else cx.posicao_saida()
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
	if gravador:
		gravador.comecar(self)
	Audio.bipe(true)
	hud.contagem("JÁ!")
	_semaforos(3, true)
	get_tree().create_timer(0.8).timeout.connect(_limpar_contagem)
	for p in _ativos():
		p.veiculo.congelar(false)
		p.controle.ativo = true
	if not _corrida.is_empty() and _vagas_corrida() == 1:
		hud.mensagem("SÓ O PRIMEIRO A TOCAR O ALVO PONTUA: %d PONTOS!" % _pontos_chegada(0), Color(1.0, 0.85, 0.4), 4.0)
	elif not _corrida.is_empty():
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
var _aud_t := 0.0


var _t_quadro := 0
var _comp_ant := 0
var _t_resumo := 0.0
var _n_resumo := 0
var _fis_resumo := 0.0
var _eventos: Array = []   # [tempo_ms, texto] dos últimos acontecimentos (monitor de travadas)


## Diagnóstico (TSC_MALHAS=1): censo das malhas do mundo — triângulos por grupo (nó de 2º nível) e as
## 30 malhas mais pesadas, com sombra e distância de sumiço. Para achar o que pesa na placa de vídeo.
## Diagnóstico (TSC_NAN=1): a cada meio segundo procura valores impossíveis (NaN, infinito ou enormes) nas
## transformações dos nós 3D e nos ossos dos esqueletos — um osso assim vira triângulos impossíveis na placa de
## vídeo e pode travar o driver. Imprime [NAN] com o caminho do nó (uma vez por nó).
var _nan_t := 0.0
var _nan_vistos := {}
func _varrer_nan(delta: float) -> void:
	_nan_t -= delta
	if _nan_t > 0.0:
		return
	_nan_t = 0.5
	var pilha: Array[Node] = [self]
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		pilha.append_array(n.get_children())
		var ruim := ""
		if n is Node3D and (n as Node3D).is_inside_tree():
			var g := (n as Node3D).global_transform
			if not g.is_finite() or g.origin.length() > 1.0e5 or g.basis.get_scale().length() > 1.0e4:
				ruim = "transformação %s" % str(g)
			elif n is VisualInstance3D and absf(g.basis.determinant()) < 1.0e-12 and (n as Node3D).is_visible_in_tree():
				ruim = "escala zero %s" % str(g.basis.get_scale())
		if ruim == "" and n is Skeleton3D:
			var e := n as Skeleton3D
			for k in e.get_bone_count():
				var b := e.get_bone_global_pose(k)
				if not b.is_finite() or b.origin.length() > 1.0e5 or b.basis.get_scale().length() > 1.0e4:
					ruim = "osso %d %s = %s" % [k, e.get_bone_name(k), str(b)]
					break
		if ruim != "" and not _nan_vistos.has(n.get_instance_id()):
			_nan_vistos[n.get_instance_id()] = true
			print("[NAN] t=%.1f %s: %s" % [_relogio_nan, str(get_path_to(n)).right(90), ruim.left(220)])
var _relogio_nan := 0.0


func _censo_malhas() -> void:
	# Luzes e partículas por grupo (TSC_MALHAS_NIVEL): muitas luzes com sombra ou partículas juntas pesam mais que triângulos
	var nivel_l := int(OS.get_environment("TSC_MALHAS_NIVEL")) if OS.get_environment("TSC_MALHAS_NIVEL") != "" else 2
	var luzes := {}
	var fila: Array[Node] = [self]
	while not fila.is_empty():
		var nl: Node = fila.pop_back()
		fila.append_array(nl.get_children())
		var tipo := ""
		if nl is OmniLight3D or nl is SpotLight3D:
			tipo = "luz_sombra" if (nl as Light3D).shadow_enabled else "luz"
		elif nl is GPUParticles3D:
			tipo = "particulas"
		elif nl is CPUParticles3D:
			tipo = "particulas_cpu"
		elif nl is Skeleton3D:
			tipo = "esqueleto"
		if tipo == "":
			continue
		var ch := "/".join(str(get_path_to(nl)).split("/").slice(0, nivel_l)).rstrip("0123456789@")
		var dl: Dictionary = luzes.get(ch, {})
		dl[tipo] = int(dl.get(tipo, 0)) + 1
		if nl is GPUParticles3D:
			dl["qtd_particulas"] = int(dl.get("qtd_particulas", 0)) + (nl as GPUParticles3D).amount
		if nl is OmniLight3D:
			dl["alcance_max"] = maxf(float(dl.get("alcance_max", 0.0)), (nl as OmniLight3D).omni_range)
		luzes[ch] = dl
	for ch in luzes:
		print("[LUZES] %-50s %s" % [ch, str(luzes[ch])])
	var grupos := {}
	var itens := []
	var pilha: Array[Node] = [self]
	var cache := {}
	while not pilha.is_empty():
		var n: Node = pilha.pop_back()
		pilha.append_array(n.get_children())
		var malha: Mesh = null
		var copias := 1
		if n is MeshInstance3D:
			malha = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			malha = (n as MultiMeshInstance3D).multimesh.mesh
			var mm := (n as MultiMeshInstance3D).multimesh
			copias = mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		if malha == null:
			continue
		if not cache.has(malha):
			var t := 0
			for s in malha.get_surface_count():
				if malha is ArrayMesh:
					var ni := (malha as ArrayMesh).surface_get_array_index_len(s)
					t += (ni if ni > 0 else (malha as ArrayMesh).surface_get_array_len(s)) / 3
				else:
					t += (malha.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			cache[malha] = t
		var tri: int = int(cache[malha]) * copias
		var g := n as GeometryInstance3D
		var caminho := str(get_path_to(n))
		var partes := caminho.split("/")
		var nivel_c := int(OS.get_environment("TSC_MALHAS_NIVEL")) if OS.get_environment("TSC_MALHAS_NIVEL") != "" else 2   # 3 abre um grupo por dentro
		var chave := "/".join(partes.slice(0, nivel_c)).rstrip("0123456789@")
		var d: Dictionary = grupos.get(chave, {"tri": 0, "nos": 0, "sombra": 0, "sem_lod": 0})
		d.tri += tri
		d.nos += 1
		if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			d.sombra += tri
		if g.visibility_range_end <= 0.0:
			d.sem_lod += tri
		grupos[chave] = d
		itens.append([tri, caminho, copias, int(cache[malha]), g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, g.visibility_range_end, g.visible and g.is_visible_in_tree()])
	var total := 0
	for k in grupos:
		total += int(grupos[k].tri)
	print("[MALHAS] total no mundo: %.2f M triângulos em %d malhas" % [total / 1e6, itens.size()])
	# MultiMesh (vegetação): total por malha — triângulos de cada cópia, quantas cópias, alcance e se tem sombra
	var por_malha := {}
	for it_m in itens:
		if int(it_m[2]) > 1 or str(it_m[1]).contains("MultiMesh"):
			var ch_m := "%d tri  alcance %4.0f  sombra %s" % [it_m[3], it_m[5], it_m[4]]
			var d_m: Array = por_malha.get(ch_m, [0, 0, 0])
			por_malha[ch_m] = [int(d_m[0]) + int(it_m[0]), int(d_m[1]) + int(it_m[2]), int(d_m[2]) + 1]
	var ch_ms := por_malha.keys()
	ch_ms.sort_custom(func(x, y): return por_malha[x][0] > por_malha[y][0])
	for ch_m in ch_ms.slice(0, 18):
		print("[MALHAS] multi %7.2f M  %7d cópias em %4d blocos  cada: %s" % [por_malha[ch_m][0] / 1e6, por_malha[ch_m][1], por_malha[ch_m][2], ch_m])
	var chaves := grupos.keys()
	chaves.sort_custom(func(a, b): return grupos[a].tri > grupos[b].tri)
	for k in chaves.slice(0, 25):
		var d: Dictionary = grupos[k]
		print("[MALHAS] grupo %-44s %7.2f M  nós=%-5d com sombra=%.2f M  sem sumiço=%.2f M" % [k, d.tri / 1e6, d.nos, d.sombra / 1e6, d.sem_lod / 1e6])
	itens.sort_custom(func(a, b): return a[0] > b[0])
	for i in itens.slice(0, 30):
		print("[MALHAS] item %8.3f M  %6d x %-7d sombra=%s sumiço=%.0f visível=%s  %s" % [i[0] / 1e6, i[2], i[3], i[4], i[5], i[6], str(i[1]).right(110)])


## Diagnóstico (TSC_TRAVADAS=1): imprime cada quadro lento, o que aconteceu logo antes e quantos
## pipelines de shader o Godot compilou nele (compilação na hora = travada da 1ª vez que algo aparece).
var _perfil_feito := false
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
	# TSC_SEM="dinos_parque,fauna,...": desliga o _process/_physics_process dos nós cujos scripts têm esses nomes
	# (para medir quanto cada sistema custa por quadro). TSC_SEM_FIS: idem só para o _physics_process.
	if fase == Fase.ATIVA and not _perfil_feito and (OS.get_environment("TSC_SEM") != "" or OS.get_environment("TSC_SEM_FIS") != ""):
		_perfil_feito = true
		var nomes := OS.get_environment("TSC_SEM").split(",", false)
		var nomes_f := OS.get_environment("TSC_SEM_FIS").split(",", false)
		var pilha: Array[Node] = [get_tree().root]
		var n := 0
		while not pilha.is_empty():
			var no: Node = pilha.pop_back()
			pilha.append_array(no.get_children())
			var sc := no.get_script() as Script
			if sc == null:
				continue
			var base := sc.resource_path.get_file().get_basename()
			if base in nomes:
				no.set_process(false)
				no.set_physics_process(false)
				n += 1
			elif base in nomes_f:
				no.set_physics_process(false)
				n += 1
		print("[PERFIL] desligados: ", n, " nós")
	if _t_resumo > 2000.0 and fase == Fase.ATIVA:
		print("[RESUMO] %d fps  física pior=%.1f ms  processo=%.1f ms  objetos=%d" % [roundi(_n_resumo * 1000.0 / _t_resumo), _fis_resumo,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		# Placa de vídeo: tempo de GPU do quadro, chamadas de desenho, triângulos, objetos visíveis e memória de vídeo
		var vp := get_viewport().get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vp, true)
		print("[PLACA] gpu=%.1f ms  cpu render=%.1f ms  desenhos=%d  triângulos=%.2f M  visíveis=%d  vram=%d MB (texturas %d, buffers %d)" % [
			RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1e6,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
			int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0), int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0)])
		_t_resumo = 0.0
		_n_resumo = 0
		_fis_resumo = 0.0


func _evento(texto: String) -> void:
	if OS.get_environment("TSC_TRAVADAS") != "":
		_eventos.append([Time.get_ticks_msec(), texto])


## TSC_FLUTUANDO=1: varredura de peças sem apoio da etapa (scripts/jogo/auditoria.gd) e fecha.
func _physics_process(delta: float) -> void:
	if _aud_t < 0.0 or fase == Fase.CARREGANDO or OS.get_environment("TSC_FLUTUANDO") == "":
		return
	_aud_t += delta
	if _aud_t > 2.0:
		_aud_t = -1.0
		if OS.get_environment("TSC_FLUTUANDO") == "dinos":
			load("res://scripts/jogo/auditoria.gd").dinos(self, terreno, get_viewport().find_world_3d().direct_space_state, "%s etapa %d" % [Config.mapa_id, etapa_idx + 1])
			get_tree().quit()
			return
		load("res://scripts/jogo/auditoria.gd").rodar(self, terreno, get_viewport().find_world_3d().direct_space_state, float(Config.valor("mapa.nivel_agua", -1000.0)), "%s etapa %d" % [Config.mapa_id, etapa_idx + 1])
		get_tree().quit()


func _process(delta: float) -> void:
	if OS.get_environment("TSC_TRAVADAS") != "":
		_monitor_travadas()
	if OS.get_environment("TSC_NAN") != "":
		_relogio_nan += delta
		_varrer_nan(delta)
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
			_avisar_gelo()
			if terreno.dino and terreno.dino.ceu:
				terreno.dino.ceu.atualizar(1.0 - tempo_restante / _tempo_total_etapa)
			if not _corrida.is_empty() and _chegadas.size() >= _vagas_corrida():
				hud.mensagem("%s CHEGOU PRIMEIRO!" % _chegadas[0].nome_piloto if _vagas_corrida() == 1 else "OS %d PRIMEIROS CHEGARAM!" % _vagas_corrida(), Color(1.0, 0.85, 0.4), 3.0)
				_finalizar_etapa()
			elif not _sem_tempo and tempo_restante <= 0.0:
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
	if CameraJogo.livre:   # câmera livre (F3): o relógio da etapa para
		return
	tempo_restante += delta if _sem_tempo else -delta


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
	if terreno.dino and bool(_cfg_etapa().get("impacto", false)):
		# Extinction Day, etapa 4: ninguém explode por tempo — o meteoro cai e explode tudo
		_finalizar_etapa()
		return
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
				texto = "NÃO CHEGOU PRIMEIRO — 0 PONTOS" if _vagas_corrida() == 1 else "FORA DOS %d PRIMEIROS — 0 PONTOS" % _vagas_corrida()
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
		if gravador:
			gravador.resultado(p, texto, pts)
		jogadores.append({"nome": p.nome, "cor": Config.EQUIPES[p.equipe].cor, "texto": texto, "pontos": pts})
		if Sessao.teste_automatico:
			_imprimir_telemetria(p, texto)
	if gravador:
		gravador.terminar()
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
	var resultado := {"titulo": titulo, "jogadores": jogadores, "equipes": equipes, "melhor": melhor, "proxima": proxima}
	if terreno.dino and bool(_cfg_etapa().get("impacto", false)) and complexos[0] is ComplexoSubida:
		# Extinction Day, etapa 4: o meteoro cai na pista e explode tudo antes do resultado
		# (a pontuação já está feita acima: a explosão é só a cena)
		_cena_impacto(resultado)
		return
	hud.resultado_etapa(resultado)


func _cena_impacto(resultado: Dictionary) -> void:
	tempo_fase = 9999.0
	hud.visible = false
	var sub := complexos[0] as ComplexoSubida
	var i := maxi(sub.total_amostras() - 1 - int(_cfg_etapa().get("impacto_antes_rampa", 380)), 0)
	var ponto := sub.amostra(i)
	ponto.y = terreno.altura_em(ponto.x, ponto.z)
	var met: Dictionary = _cfg_etapa().get("ceu", {}).get("meteoro", {})
	var vinda := CeuDino.direcao(float(met.get("azimute", 0.0)), float(met.get("elevacao_final", met.get("elevacao", 40.0))))
	_impacto = ImpactoMeteoro.new()
	add_child(_impacto)
	var vs: Array = []
	for p in participantes:
		vs.append(p.veiculo)
	_impacto.iniciar(ponto, vinda, vs, camera, terreno, alvo)
	_impacto.terminou.connect(func():
		hud.visible = OS.get_environment("TSC_SEM_HUD") == ""
		hud.resultado_etapa(resultado)
		tempo_fase = float(Config.valor("partida.resultado_etapa_s", 6)))


func _tempo_partida_acabou() -> bool:
	return tempo_modo == "partida" and not _sem_tempo and tempo_restante <= 0.0


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
	if Sessao.teste_automatico and OS.get_environment("TSC_FOTO_FINAL") == "":   # (a foto da comemoração fecha o jogo depois de salvar)
		print("[TESTE] Partida concluída. Vencedora: ", Config.EQUIPES[ordem[0]].nome)
		get_tree().quit()


## Fim da partida: carros da equipe vencedora em cima do alvo (plano e parado), cada piloto em pé
## ao lado do seu carro comemorando. O MVP da partida fica na frente, no centro, com holofote e
## nome em cima (se ele não for da equipe vencedora, entra também, como destaque).
func _montar_comemoracao(equipe_vencedora: int, mvp: Dictionary) -> void:
	alvo.configurar(etapas_cfg[0])
	alvo.parado = true   # alvo móvel (Frozen Peak): fica parado embaixo dos carros da comemoração
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
	var pos_mvp: Vector3 = alvo.tampo_em(c if alvo.gravata else c + para_cam * 3.5)[0]
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
	if alvo.bacia_raio > 0.0:
		# Bacia do meteoro: câmera dentro dela, no alto da parede (de fora, a borda da rocha tapa o grupo lá embaixo)
		pos_cam = alvo.tampo_em(c + para_cam * (alvo.bacia_raio - 2.0) - lado * 3.0)[0] + Vector3.UP * 3.2
	var foco: Vector3 = alvo.tampo_em(c + para_cam * 1.0)[0] + Vector3.UP * 1.3   # na bacia do meteoro o grupo fica abaixo da borda
	var direita_tela := (foco - pos_cam).normalized().cross(Vector3.UP).normalized()
	camera.podio(foco - direita_tela * 5.0, pos_cam)


func _posicionar_comemoracao(p: Dictionary, pos: Vector3, frente: Vector3, intensidade: float) -> Avatar:
	var v: Veiculo = p.veiculo
	# Assenta no tampo do alvo: plano no disco; na bacia do meteoro (Extinction Day) o carro acompanha a
	# concavidade — na altura do centro_base ele ficava flutuando sobre o fundo
	var tampo := alvo.tampo_em(pos)
	pos = tampo[0]
	var cima: Vector3 = tampo[1]
	# O carro olha para `frente` (a frente do Veiculo é -Z)
	var b := Basis.looking_at(frente.slide(cima).normalized(), cima)
	v.preparar(Transform3D(b, pos + cima * 0.15))
	if v.piloto:
		v.piloto.visible = false   # o piloto sai do carro e fica em pé ao lado
	if v.avatar_dados.is_empty():
		return null
	var a := Avatar.criar(v.avatar_dados)
	add_child(a)
	# Ao lado da porta do motorista, virado para a câmera
	var esquerda := frente.cross(Vector3.UP).normalized() * -1.0
	a.global_position = alvo.tampo_em(pos + esquerda * (v.caixa_corpo.size.x * 0.5 + 0.9) + frente * 0.6)[0]
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
	if _corrida.has("vagas"):   # número fixo (Serpent's Climb: 1 = só o primeiro)
		return maxi(1, int(_corrida.vagas))
	return maxi(1, ceili(float(_corrida.get("fracao_pontuam", 0.3)) * _ativos().size()))


## Frozen Peak: avisa o jogador quando as rodas entram no gelo vivo (o carro passa a escorregar).
var _no_gelo := false
var _gelado := false   # atingido pelo cuspe de gelo das focas
var _invertido := false   # yeti pendurado no teto
func _avisar_gelo() -> void:
	var v: Veiculo = jogador.veiculo
	var agora := not v.eliminado and v.aderencia_piso < 0.9
	if agora and not _no_gelo and not v.gelado() and not v.com_ovo():
		hud.mensagem("GELO — O CARRO ESCORREGA", Color(0.55, 0.9, 1.0), 1.8)
	_no_gelo = agora
	var gelado := not v.eliminado and v.gelado()
	if gelado and not _gelado:
		hud.mensagem("CONGELADO — SEM DIREÇÃO E SEM FREIO!", Color(0.55, 0.9, 1.0), 2.5)
	_gelado = gelado
	var inv := not v.eliminado and v.direcao_invertida()
	if inv and not _invertido:
		if v.com_veneno():
			hud.mensagem("VENENO — DIREÇÃO INVERTIDA!", Color(0.8, 1.0, 0.6), 2.5)
		elif v.com_ovo():
			hud.mensagem("OVO NO CARRO — ESCORREGANDO E DIREÇÃO INVERTIDA!", Color(1.0, 0.85, 0.3), 2.5)
		elif v.has_meta("jaguar"):
			hud.mensagem("JAGUAR NO TETO — DIREÇÃO INVERTIDA!", Color(1.0, 0.75, 0.3), 2.5)
		else:
			hud.mensagem("YETI NO TETO — DIREÇÃO INVERTIDA!", Color(0.75, 0.9, 1.0), 2.5)
	_invertido = inv


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
		print("[CP] %s ressurgiu no checkpoint %d (quedas %d) t=%.1f motivo=%s em %s" % [v.nome_piloto, v.checkpoint + 1, int(v.telemetria.get("quedas", 0)), v.relogio, str(v.telemetria.get("motivo", "-")), str(v.telemetria.get("pos_eliminado", "-"))])
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
	hud.atualizar({"etapa_texto": etapa_txt, "tempo": tempo_restante, "cronometro": _sem_tempo, "equipes": equipes, "linhas": linhas,
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
	if vista == "piloto":   # de perto, ao lado e um pouco acima do carro do jogador (cabeça x teto)
		var v: Veiculo = jogador.veiculo
		var b := v.global_transform.basis
		camera.podio(v.global_position + b.y * 1.0, v.global_position + b.x * -3.2 + b.y * 1.9 + b.z * 0.6)
		return
	if sub and vista.begins_with("selva"):
		# Serpent's Climb: conferência do cenário e das armadilhas (TSC_MAPA=serpents_climb)
		camera.cam.far = 20000.0
		var sv := {
			"selva_mapa": [Vector3(-500, 0, -380), Vector3(-490, 3600, -330)],
			"selva_sol": [Vector3(-1250, 50, -350), Vector3(-950, 150, 30)],
			"selva_serpentes": [Vector3(700, 50, -350), Vector3(1000, 140, 0)],
			"selva_cachoeira": [Vector3(-700, 90, -1720), Vector3(-640, 80, -1300)],
			"selva_mata": [Vector3(-300, 20, 0), Vector3(-150, 60, 300)],
			"selva_alvo": [alvo.centro_base, alvo.centro_base + Vector3(45, 18, -50)],
			"selva_rampa": [sub.amostra(sub.total_amostras() - 1), sub.amostra(sub.total_amostras() - 1) - sub.frente * 60.0 + sub.lateral * 25.0 + Vector3.UP * 12.0],
			"selva_largada": [sub.largada.pa(35.0, 0.0, sub.largada.piso_y), sub.largada.pa(-40.0, -60.0, sub.largada.piso_y + 45.0)],
			"selva_plataforma": [sub.plataforma.pa(50.0, 0.0, sub.plataforma.piso_y), sub.plataforma.pa(130.0, -90.0, sub.plataforma.piso_y + 60.0)],
			"selva_capa": [Vector3(-1250, 70, -350), Vector3(-820, 120, -80)],
			# Portão principal (PortaoSelva): de dentro, de fora, de lado e detalhes de perto
			"selva_portao": [sub.largada.pa(70.0, 0.0, sub.largada.piso_y + 17.0), sub.largada.pa(22.0, 0.0, sub.largada.piso_y + 10.0)],
			"selva_portao_fora": [sub.largada.pa(70.0, 0.0, sub.largada.piso_y + 17.0), sub.largada.pa(116.0, 0.0, sub.largada.piso_y + 9.0)],
			"selva_cerca": [sub.largada.pa(35.0, -45.0, sub.largada.piso_y + 6.0), sub.largada.pa(20.0, -16.0, sub.largada.piso_y + 6.0)],
			"selva_cerca_fora": [sub.largada.pa(35.0, -45.0, sub.largada.piso_y + 6.0), sub.largada.pa(30.0, -85.0, sub.largada.piso_y + 12.0)],
			"selva_cerca_perto": [sub.largada.pa(40.0, -45.0, sub.largada.piso_y + 6.0), sub.largada.pa(38.0, -32.0, sub.largada.piso_y + 5.0)],
			"selva_portao_vao": [sub.largada.pa(70.5, 5.5, sub.largada.piso_y + 9.0), sub.largada.pa(60.0, -3.5, sub.largada.piso_y + 3.0)],
			"selva_portao_lado": [sub.largada.pa(70.0, 0.0, sub.largada.piso_y + 16.0), sub.largada.pa(104.0, 34.0, sub.largada.piso_y + 14.0)],
			"selva_portao_cabeca": [sub.largada.pa(70.0, 0.0, sub.largada.piso_y + 24.5), sub.largada.pa(90.0, 6.0, sub.largada.piso_y + 22.0)],
			"selva_portao_guerreiro": [sub.largada.pa(70.0, -12.0, sub.largada.piso_y + 12.0), sub.largada.pa(88.0, -9.0, sub.largada.piso_y + 11.0)],
			"selva_portao_letreiro": [sub.largada.pa(70.0, 0.0, sub.largada.piso_y + 29.0), sub.largada.pa(96.0, -4.0, sub.largada.piso_y + 27.0)],
		}
		if vista == "selva_aves" and terreno.selva and terreno.selva.has_node("Fauna"):
			# Perto do primeiro bando de araras, acompanhando o voo
			var fauna: Fauna = terreno.selva.get_node("Fauna")
			var xf: Transform3D = (fauna._especies[0].mm as MultiMesh).get_instance_transform(0)
			var c := xf.origin
			camera.podio(c, c + xf.basis.z.normalized() * 9.0 + xf.basis.x.normalized() * 5.0 + Vector3.UP * 2.5)
			return
		if vista.begins_with("selva_caminho"):
			# Serpente colossal da E1 (SerpenteCaminho): selva_caminho = a cabeça de perto; _alto = a curva do trecho A
			# de cima; _lado = a ponte de lado; _pista = de trás da cabeça; _ninho = o alvo. TSC_SERPENTE_S põe a
			# cabeça num ponto do roteiro.
			var sc := terreno.selva.get_node_or_null("Etapa/SerpenteCaminho") as SerpenteCaminho
			if sc:
				var cb := sc.cabeca()
				var pc: Vector3 = cb[0]
				var rc: Vector3 = cb[1]
				var lc := Vector3(-rc.z, 0.0, rc.x).normalized()
				match vista:
					"selva_caminho_alto": camera.podio(Vector3(-1380, 20, 560), Vector3(-1385, 560, 600))
					"selva_caminho_lado": camera.podio(Vector3(-1330, 30, 560), Vector3(-1080, 120, 760))
					"selva_caminho_pista": camera.podio(pc + Vector3.UP * 2.0, pc - rc * 45.0 + Vector3.UP * 16.0 + lc * 8.0)
					"selva_caminho_travessia":
						var pt := sc.ponto(sc.marca_s("travessia%s" % OS.get_environment("TSC_TRAVESSIA") if OS.get_environment("TSC_TRAVESSIA") != "" else "travessia3"))
						if OS.get_environment("TSC_PILOTO") != "":
							camera.podio(Vector3(-1250.0, pt.y + 1.0, pt.z), Vector3(-1250.0, pt.y + 3.5, pt.z + 38.0))   # na pista, chegando (os carros andam para -z)
						else:
							camera.podio(pt, pt + Vector3(55, 22, -35))
					"selva_caminho_ninho": camera.podio(alvo.centro_base, alvo.centro_base + Vector3(70, 35, -60))
					_: camera.podio(pc + Vector3.UP * 2.0, pc + rc * 30.0 + lc * 18.0 + Vector3.UP * 10.0)
			return
		if vista.begins_with("selva_livre"):
			# Qualquer ponto: TSC_CAM_DE="x,y,z" (câmera) e TSC_CAM_PARA_N="x,y,z" (alvo da foto selva_livreN)
			var de := OS.get_environment("TSC_CAM_DE").split(",")
			var para := OS.get_environment("TSC_CAM_PARA_" + vista.trim_prefix("selva_livre")).split(",")
			if de.size() == 3 and para.size() == 3:
				camera.podio(Vector3(float(para[0]), float(para[1]), float(para[2])), Vector3(float(de[0]), float(de[1]), float(de[2])))
			return
		if vista.begins_with("selva_montanha"):
			# Montanha da armadilha (MontanhaArmadilha): _frente/_costas = de fora em cada boca, _dentro = dentro do túnel,
			# _alto = de cima e de lado
			var mts := get_tree().get_nodes_in_group("montanha_armadilha")   # TSC_MONTANHA=N escolhe (1 = a primeira)
			var mt := mts[clampi(int(OS.get_environment("TSC_MONTANHA")) - 1, 0, mts.size() - 1)] as Node3D if not mts.is_empty() else null
			if mt:
				var bocas: Array = mt.get_meta("bocas")
				var bk: Array = bocas[1] if vista.contains("costas") else bocas[0]
				var pb: Vector3 = bk[0]
				var dd := Vector3(bk[1].x, 0.0, bk[1].z).normalized()
				var ld := dd.cross(Vector3.UP)
				if vista.ends_with("_dentro"):
					camera.podio(pb + dd * 40.0 + Vector3.UP * 6.0, pb - dd * 6.0 + Vector3.UP * 5.0)
				if vista.contains("_ponto"):   # TSC_CAM_PONTO="x,y,z": daquele ponto, olhando o pé da boca mais perto
					var xyz := OS.get_environment("TSC_CAM_PONTO").split(",")
					var cp := Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2]))
					var perto: Array = bocas[0] if cp.distance_to(bocas[0][0]) < cp.distance_to(bocas[1][0]) else bocas[1]
					camera.podio((perto[0] as Vector3) + Vector3.DOWN * 1.5, cp)
				elif vista.ends_with("_tunel"):   # na pista, já dentro do túnel, olhando a fila de machados
					camera.podio(pb + dd * 70.0 + Vector3.UP * 6.0, pb + dd * 4.0 + Vector3.UP * 3.5)
				elif vista.ends_with("_baixo"):   # embaixo da boca, olhando a junta do chão do túnel com a rocha
					camera.podio(pb + Vector3.DOWN * 2.0, pb - dd * 22.0 + ld * 8.0 + Vector3.DOWN * 9.0)
				elif vista.ends_with("_alto"):
					camera.podio(pb + dd * 15.0 + Vector3.UP * 40.0, pb - dd * 160.0 + ld * 140.0 + Vector3.UP * 110.0)
				else:
					camera.podio(pb + dd * 10.0 + Vector3.UP * 30.0, pb - dd * 110.0 + ld * 25.0 + Vector3.UP * 25.0)
			return
		if vista.begins_with("selva_cachoeira_toca"):
			# Cachoeira na frente da toca da cobra 3 (E1): da pista (selva_cachoeira_toca) ou de perto (_perto)
			for c: SerpenteBote in SerpenteBote.ativas:
				var cq := c.get_node_or_null("Cachoeira") as Node3D
				if cq:
					var o := Vector3(cq.global_position.x, c._c_toca.y, cq.global_position.z)
					var f := cq.global_basis.z
					var l := cq.global_basis.x
					if vista.ends_with("_perto"):
						camera.podio(o + f * 12.0 + Vector3.UP * 10.0, o + f * 50.0 + l * 14.0 + Vector3.UP * 5.0)
					else:
						camera.podio(o + f * 10.0 + Vector3.UP * 25.0, o + f * 120.0 + l * 60.0 + Vector3.UP * 25.0)
			return
		if vista.begins_with("selva_cobra"):
			# Serpente gigante da etapa: de perto, pela frente (selva_cobra), de lado (selva_cobra_lado)
			# ou a trilha toda de cima (selva_cobra_alto). TSC_SERPENTE_S escolhe onde ela começa.
			var cobra := terreno.selva.get_node_or_null("Etapa/SerpenteGigante") as SerpenteGigante
			if vista.begins_with("selva_cobra_arena"):   # a cobra 2 (plataforma dos buracos)
				cobra = null
				for c: SerpenteBote in SerpenteBote.ativas:
					if c.modo == SerpenteBote.Modo.ARENA:
						cobra = c
				vista = vista.replace("_arena", "")
			if cobra:
				var cb := cobra.cabeca()
				var p0: Vector3 = cb[0]
				var rumo: Vector3 = cb[1]
				var lado_c := Vector3(-rumo.z, 0.0, rumo.x)
				if vista == "selva_cobra_alto":
					camera.podio(Vector3(-1570, 6, 660), Vector3(-1570, 520, 700))
				elif vista == "selva_cobra_lado":
					camera.podio(p0 - rumo * 45.0, p0 - rumo * 30.0 + lado_c * 95.0 + Vector3.UP * 38.0)
				else:
					camera.podio(p0 + Vector3.UP * 3.0, p0 + rumo * 34.0 + lado_c * 16.0 + Vector3.UP * 9.0)
			return
		if vista.begins_with("selva_armadilha"):
			# TSC_CAM_VISTA=selva_armadilhaN: de lado, perto da N-ésima armadilha do percurso (1 = primeira)
			var n := maxi(int(vista.trim_prefix("selva_armadilha")), 1) - 1
			var alvos_a: Array = sub.armadilhas.posicoes() if sub.armadilhas else []
			if n < alvos_a.size():
				var g: Array = alvos_a[n]
				camera.podio(g[0] + Vector3.UP * 3.0, g[0] + g[1] * 28.0 - g[2] * 22.0 + Vector3.UP * 9.0)
			return
		var par: Array = sv.get(vista, sv.selva_mapa)
		camera.podio(par[0], par[1])
		return
	if sub and vista.begins_with("dino"):
		_vista_dino(vista, sub)
		return
	if sub and vista.begins_with("gelo"):
		# Frozen Peak: conferência do cenário, dos saltos e das armadilhas (TSC_MAPA=frozen_peak)
		camera.cam.far = 20000.0
		var fim_g := sub.amostra(sub.total_amostras() - 1)
		var a_g := alvo.centro_base
		var meio_g := (fim_g + a_g) * 0.5
		var gv := {
			"gelo_mapa": [Vector3(-480, 0, -380), Vector3(-470, 3900, -330)],
			"gelo_alvo": [a_g, a_g + sub.lateral * 60.0 - sub.frente * 55.0 + Vector3.UP * 22.0],
			"gelo_alvo_longe": [a_g, a_g - sub.frente * 330.0 + sub.lateral * 120.0 + Vector3.UP * 150.0],
			"gelo_voo": [a_g + Vector3.UP * 60.0, fim_g - sub.frente * 30.0 + Vector3.UP * 28.0 + sub.lateral * 14.0],
			"gelo_voo_lado": [meio_g + Vector3.UP * 60.0, meio_g + sub.lateral * 620.0 + Vector3.UP * 330.0],
			"gelo_rampa": [fim_g, fim_g - sub.frente * 70.0 + sub.lateral * 26.0 + Vector3.UP * 14.0],
			"gelo_largada": [sub.largada.pa(35.0, 0.0, sub.largada.piso_y), sub.largada.pa(-40.0, -60.0, sub.largada.piso_y + 45.0)],
			# Portal de gelo (PortaoGelo): de dentro como o jogador vê, de perto, de fora e o da plataforma
			"gelo_portao": [sub.largada.pa(sub.largada.comprimento, 0.0, sub.largada.piso_y + 15.0), sub.largada.pa(sub.largada.comprimento - 40.0, 0.0, sub.largada.piso_y + 9.0)],
			"gelo_portao_perto": [sub.largada.pa(sub.largada.comprimento, 0.0, sub.largada.piso_y + 18.0), sub.largada.pa(sub.largada.comprimento - 13.0, 7.0, sub.largada.piso_y + 11.0)],
			"gelo_portao_fora": [sub.largada.pa(sub.largada.comprimento, 0.0, sub.largada.piso_y + 15.0), sub.largada.pa(sub.largada.comprimento + 40.0, -12.0, sub.largada.piso_y + 6.0)],
			"gelo_portao_plat": [sub.plataforma.pa(sub.plataforma.comprimento, 0.0, sub.plataforma.piso_y + 15.0), sub.plataforma.pa(sub.plataforma.comprimento - 45.0, 8.0, sub.plataforma.piso_y + 5.0)],
			# Focas (armadilha "focas", E1 em A+285): da estrada, chegando, e de lado, perto de uma delas
			"gelo_focas": [sub.amostra(sub.indice_trecho("A", 292.0)) + Vector3.UP * 2.5, sub.amostra(sub.indice_trecho("A", 255.0)) + Vector3.UP * 4.0],
			"gelo_foca_perto": [sub.amostra(sub.indice_trecho("A", 285.0)) + sub.lateral_em(sub.indice_trecho("A", 285.0)) * 13.0 + Vector3.UP * 3.0, sub.amostra(sub.indice_trecho("A", 275.0)) + sub.lateral_em(sub.indice_trecho("A", 285.0)) * 3.0 + Vector3.UP * 5.0],
			# Túnel de gelo (pingentes; E1 em A+937)
			"gelo_tunel": [sub.amostra(sub.indice_trecho("A", 945.0)) + Vector3.UP * 6.0, sub.amostra(sub.indice_trecho("A", 905.0)) + Vector3.UP * 4.0],
			"gelo_tunel_dentro": [sub.amostra(sub.indice_trecho("A", 950.0)) + Vector3.UP * 3.0, sub.amostra(sub.indice_trecho("A", 933.0)) + Vector3.UP * 2.5],
			# Portal das bolas de neve (E2: topo da espiral em A+1098), visto de quem sobe
			"gelo_bolas": [sub.amostra(sub.indice_trecho("A", 1098.0)) + Vector3.UP * 6.0, sub.amostra(sub.indice_trecho("A", 1050.0)) + Vector3.UP * 5.0],
			"gelo_portao_plat_baixo": [sub.plataforma.pa(sub.plataforma.comprimento, 0.0, sub.plataforma.piso_y + 15.0), sub.plataforma.pa(sub.plataforma.comprimento - 16.0, -2.0, sub.plataforma.piso_y + 1.5)],
			"gelo_foca_rosto": [sub.amostra(sub.indice_trecho("A", 285.0)) + sub.lateral_em(sub.indice_trecho("A", 285.0)) * 11.0 + Vector3.UP * 5.0, sub.amostra(sub.indice_trecho("A", 279.0)) + sub.lateral_em(sub.indice_trecho("A", 285.0)) * 5.0 + Vector3.UP * 6.0],
			"gelo_yeti": [sub.amostra(sub.indice_trecho("A", 450.0)) + Vector3.UP * 2.0, sub.amostra(sub.indice_trecho("A", 432.0)) + sub.lateral_em(sub.indice_trecho("A", 450.0)) * 9.0 + Vector3.UP * 5.0],
			"gelo_yeti_carro": [sub.amostra(sub.indice_trecho("A", 468.0)) + Vector3.UP * 1.5, sub.amostra(sub.indice_trecho("A", 490.0)) + sub.lateral_em(sub.indice_trecho("A", 468.0)) * 7.0 + Vector3.UP * 4.0],
			"gelo_yeti_rosto": [sub.amostra(sub.indice_trecho("A", 450.0)) + sub.lateral_em(sub.indice_trecho("A", 450.0)) * 11.5 + Vector3.UP * 5.5, sub.amostra(sub.indice_trecho("A", 443.0)) + sub.lateral_em(sub.indice_trecho("A", 450.0)) * 4.0 + Vector3.UP * 5.0],
			"gelo_yeti_joga": [sub.plataforma.pa(sub.plataforma.comprimento * 0.25, -(sub.plataforma.largura_arena * 0.5 - 4.0) * (float(sub.plataforma.entradas[0][0]) if not sub.plataforma.entradas.is_empty() else 1.0), sub.plataforma.piso_y + 5.0), sub.plataforma.pa(sub.plataforma.comprimento * 0.25 + 9.0, -(sub.plataforma.largura_arena * 0.5 - 15.0) * (float(sub.plataforma.entradas[0][0]) if not sub.plataforma.entradas.is_empty() else 1.0), sub.plataforma.piso_y + 5.5)],
			"gelo_plat_yetis": [sub.plataforma.pa(sub.plataforma.comprimento * 0.5, 0.0, sub.plataforma.piso_y), sub.plataforma.pa(-10.0, 0.0, sub.plataforma.piso_y + 22.0)],
			"gelo_yeti_seguir": ([Armadilhas.ultimo_agarrado.global_position + Vector3.UP * 1.0, Armadilhas.ultimo_agarrado.global_position + Armadilhas.ultimo_agarrado.global_transform.basis.x * 3.5 - Armadilhas.ultimo_agarrado.global_transform.basis.z * 4.0 + Vector3.UP * 2.2] if is_instance_valid(Armadilhas.ultimo_agarrado) else [a_g, a_g + Vector3.UP * 50.0]),
			"gelo_yeti_tras": ([Armadilhas.ultimo_agarrado.global_position + Vector3.UP * 1.0, Armadilhas.ultimo_agarrado.global_position + Armadilhas.ultimo_agarrado.global_transform.basis.z * 4.8 + Vector3.UP * 3.4] if is_instance_valid(Armadilhas.ultimo_agarrado) else [a_g, a_g + Vector3.UP * 50.0]),
			"gelo_yeti_cima": ([Armadilhas.ultimo_agarrado.global_position, Armadilhas.ultimo_agarrado.global_position + Vector3.UP * 7.0 + Armadilhas.ultimo_agarrado.global_transform.basis.z * 0.01] if is_instance_valid(Armadilhas.ultimo_agarrado) else [a_g, a_g + Vector3.UP * 50.0]),
			"gelo_yeti_lado": ([Armadilhas.ultimo_agarrado.global_position + Vector3.UP * 1.2, Armadilhas.ultimo_agarrado.global_position - Armadilhas.ultimo_agarrado.global_transform.basis.x * 6.0 + Vector3.UP * 1.4] if is_instance_valid(Armadilhas.ultimo_agarrado) else [a_g, a_g + Vector3.UP * 50.0]),
			"gelo_yeti_frente": ([Armadilhas.ultimo_agarrado.global_position + Vector3.UP * 1.2, Armadilhas.ultimo_agarrado.global_position - Armadilhas.ultimo_agarrado.global_transform.basis.z * 6.0 + Vector3.UP * 1.6] if is_instance_valid(Armadilhas.ultimo_agarrado) else [a_g, a_g + Vector3.UP * 50.0]),
			"gelo_saida": [sub.amostra(60), sub.amostra(0) - sub.tangente_em(0) * 26.0 + Vector3.UP * 7.0],
			"gelo_plataforma": [sub.plataforma.pa(50.0, 0.0, sub.plataforma.piso_y), sub.plataforma.pa(130.0, -90.0, sub.plataforma.piso_y + 60.0)],
			"gelo_fortaleza": [sub.plataforma.pa(50.0, 0.0, sub.plataforma.piso_y - 30.0), sub.plataforma.pa(-150.0, 190.0, sub.plataforma.piso_y + 20.0)],
			"gelo_capa": [sub.plataforma.pa(50.0, 0.0, sub.plataforma.piso_y - 10.0), sub.plataforma.pa(-230.0, 250.0, sub.plataforma.piso_y + 70.0)],
			"gelo_lago": [Vector3(-700, 5, 420), Vector3(-380, 70, 720)],
			"gelo_vila": [Vector3(-1100, 12, 620), Vector3(-960, 40, 740)],
		}
		if vista.begins_with("gelo_frente"):
			# gelo_frenteN: da estrada, chegando na N-ésima armadilha (como o piloto vê); TSC_CAM_RECUO = metros antes
			var n_f := maxi(int(vista.trim_prefix("gelo_frente")), 1) - 1
			var lista_f: Array = sub.armadilhas.posicoes() if sub.armadilhas else []
			if n_f < lista_f.size():
				var gf: Array = lista_f[n_f]
				var recuo := float(OS.get_environment("TSC_CAM_RECUO")) if OS.get_environment("TSC_CAM_RECUO") != "" else 42.0
				camera.podio(gf[0] + Vector3.UP * 11.0, gf[0] - gf[2] * recuo + Vector3.UP * 5.0)
			return
		if vista.begins_with("gelo_armadilha"):
			# gelo_armadilhaN: de lado, perto da N-ésima armadilha do percurso (1 = primeira)
			var n_a := maxi(int(vista.trim_prefix("gelo_armadilha")), 1) - 1
			var lista_a: Array = sub.armadilhas.posicoes() if sub.armadilhas else []
			if n_a < lista_a.size():
				var g: Array = lista_a[n_a]
				camera.podio(g[0] + Vector3.UP * 3.0, g[0] + g[1] * 26.0 - g[2] * 24.0 + Vector3.UP * 9.0)
			return
		if vista.begins_with("gelo_vao"):
			# gelo_vaoN: o N-ésimo salto do percurso visto de lado, de quem chega
			var n_v := maxi(int(vista.trim_prefix("gelo_vao")), 1) - 1
			if n_v < sub.vaos().size():
				var vv: Dictionary = sub.vaos()[n_v]
				var p0 := sub.amostra(int(vv.i0))
				camera.podio(p0 + sub.tangente_em(int(vv.i0)) * 5.0, p0 - sub.tangente_em(int(vv.i0)) * 34.0 + sub.lateral_em(int(vv.i0)) * 20.0 + Vector3.UP * 8.0)
			return
		if vista.begins_with("gelo_estrada"):
			# gelo_estradaN: na estrada, a N x 100 m do começo, olhando para a frente (como o piloto vê)
			var m_e := float(int(vista.trim_prefix("gelo_estrada"))) * 100.0
			var i_e := 0
			while i_e < sub.total_amostras() - 40 and sub.progresso_amostra(i_e) < m_e:
				i_e += 1
			var j_e := mini(i_e + 40, sub.total_amostras() - 1)
			camera.podio(sub.amostra(j_e) + Vector3.UP * 1.0, sub.amostra(i_e) - sub.tangente_em(i_e) * 9.0 + Vector3.UP * 4.0)
			return
		if vista == "gelo_livre":   # TSC_CAM_POS="x,y,z" e TSC_CAM_ALVO="x,y,z"
			var pos_g := OS.get_environment("TSC_CAM_POS").split_floats(",")
			var mira_g := OS.get_environment("TSC_CAM_ALVO").split_floats(",")
			camera.podio(Vector3(mira_g[0], mira_g[1], mira_g[2]), Vector3(pos_g[0], pos_g[1], pos_g[2]))
			return
		var par_g: Array = gv.get(vista, gv.gelo_mapa)
		camera.podio(par_g[0], par_g[1])
		return
	if sub and vista.begins_with("egito"):
		# Pharaoh's Climb: conferência do cenário (TSC_MAPA=pharaohs_climb)
		camera.cam.far = 20000.0
		var vistas := {
			"egito_mapa": [Vector3(-650, 0, -380), Vector3(-640, 3300, -330)],
			"egito_piramide": [Vector3(-1300, 45, -250), Vector3(-900, 150, 130)],
			"egito_espiral": [Vector3(-1165, 45, -260), Vector3(-1040, 75, -140)],
			"egito_templo": [Vector3(-1300, 100, -250), Vector3(-1150, 190, -390)],
			"egito_largada": [Vector3(-1472, 10, -120), Vector3(-1440, 22, 40)],
			"egito_salto": [Vector3(-765, 140, -765), Vector3(-690, 170, -650)],
			"egito_pistao": [Vector3(-1035, 115, -490), Vector3(-1012, 124, -445)],
			"egito_vale": [Vector3(0, 90, -380), Vector3(260, 470, -1000)],
			"egito_portal": [Vector3(150, 140, -330), Vector3(40, 190, -620)],
			"egito_nilo": [Vector3(-200, 10, 150), Vector3(-420, 60, 0)],
			"egito_alvo": [alvo.centro_base, alvo.centro_base + Vector3(55, 20, -60)],
			"egito_capa": [Vector3(-1290, 55, -255), Vector3(-720, 135, -40)],   # foto do menu
		}
		if vista == "egito_rampa":
			var fim := sub.amostra(sub.total_amostras() - 1)
			camera.podio(alvo.centro_base, fim + Vector3(20.0, 25.0, -50.0))
		elif vistas.has(vista):
			camera.podio(vistas[vista][0], vistas[vista][1])
		return
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
				if OS.get_environment("TSC_CAM_FOV") != "":
					camera.cam.fov = float(OS.get_environment("TSC_CAM_FOV"))   # a câmera livre (F3) usa 70
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
				var fim := sub.amostra(sub.total_amostras() - 1)
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
	if vista.begins_with("cidade"):
		# City Rush: cidade_geral (do alto), cidade_torre (torre da plataforma vista da rua),
		# cidade_rampa (do telhado olhando o alvo), cidade_rua (no chão, perto da praça)
		camera.cam.far = 20000.0
		var topo := cx.ponto(0.0, cx.perfil.pontos[0].y)
		match vista:
			"cidade_torre":
				var b := cx.ponto(cx.perfil.pontos[cx.perfil.indice_borda].x, 0.0)
				camera.podio(Vector3(b.x, 200.0, b.z), b + cx.frente * 330.0 + cx.lateral * 260.0 + Vector3.UP * 30.0)
			"cidade_rampa":
				camera.podio(alvo.centro_base, topo - cx.frente * 25.0 + cx.lateral * 30.0 + Vector3.UP * 25.0)
			"cidade_voo":   # no meio do voo, olhando as chicanes e o alvo
				var p := cx.frente * -820.0 + Vector3.UP * 230.0
				camera.podio(Vector3(0.0, 40.0, 0.0), p)
			"cidade_alvo":   # chegada ao alvo, como o jogador vê de paraquedas
				var p := cx.frente * -150.0 + cx.lateral * 20.0 + Vector3.UP * 95.0
				camera.podio(alvo.centro_base, p)
			"cidade_perto":   # fachadas e telhados de perto (conferir detalhe dos prédios)
				var p := cx.frente * -330.0 + cx.lateral * 60.0 + Vector3.UP * 75.0
				camera.podio(cx.frente * -200.0 + cx.lateral * 120.0 + Vector3.UP * 50.0, p)
			"cidade_rua":
				var p := cx.frente * -520.0 + cx.lateral * 40.0
				camera.podio(Vector3(0.0, 60.0, 0.0), Vector3(p.x, 9.0, p.z))
			"cidade_livre":   # TSC_CAM_POS="x,y,z" e TSC_CAM_ALVO="x,y,z"
				var pos := OS.get_environment("TSC_CAM_POS").split_floats(",")
				var mira := OS.get_environment("TSC_CAM_ALVO").split_floats(",")
				camera.podio(Vector3(mira[0], mira[1], mira[2]), Vector3(pos[0], pos[1], pos[2]))
			_:
				camera.podio(Vector3.ZERO, Vector3(900.0, 1300.0, 1500.0))
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


## Extinction Day: vistas de conferência (TSC_MAPA=extinction_day TSC_FOTOS="dino_...:seg,...").
## dino_mapa, _vulcao, _cratera, _largada, _portao, _portico (pórtico da largada visto de dentro), _saida, _plataforma, _rampa, _voo, _voo_lado, _alvo,
## _alvo_longe, _bocaN (boca do N-ésimo túnel; _bocafN = de frente), _dentroN (dentro do túnel da etapa, N/10 do caminho),
## _armadilhaN, _estradaN (N x 100 m), _bichoN (N-ésimo dinossauro andando), _livre (TSC_CAM_POS/ALVO).
func _vista_dino(vista: String, sub: ComplexoSubida) -> void:
	camera.cam.far = 20000.0
	var fim := sub.amostra(sub.total_amostras() - 1)
	var a := alvo.centro_superior()
	var meio := (fim + a) * 0.5
	var dino := terreno.dino
	var cv := Vector3(dino.centro_vulcao.x, 0.0, dino.centro_vulcao.y)
	var dv := {
		"dino_mapa": [Vector3(-450, 0, -400), Vector3(-440, 5400, -330)],
		"dino_vulcao": [cv + Vector3.UP * 300.0, cv + Vector3(1300, 420, 1200)],
		"dino_cratera": [cv + Vector3.UP * 440.0, cv + Vector3(260, 720, 240)],
		"dino_alvo": [a, a + sub.lateral * 70.0 - sub.frente * 60.0 + Vector3.UP * 28.0],
		"dino_heli": [a + Vector3.UP * 40.0, a + sub.lateral * 42.0 - sub.frente * 30.0 + Vector3.UP * 34.0],   # helicóptero do alvo de perto
		"dino_alvo_longe": [a, a - sub.frente * 330.0 + sub.lateral * 120.0 + Vector3.UP * 150.0],
		"dino_voo": [a + Vector3.UP * 20.0, fim - sub.frente * 30.0 + Vector3.UP * 28.0 + sub.lateral * 14.0],
		"dino_voo_lado": [meio, meio + sub.lateral * 620.0 + Vector3.UP * 330.0],
		"dino_rampa": [fim, fim - sub.frente * 70.0 + sub.lateral * 26.0 + Vector3.UP * 14.0],
		"dino_largada": [sub.largada.pa(35.0, 0.0, sub.largada.piso_y), sub.largada.pa(-40.0, -60.0, sub.largada.piso_y + 45.0)],
		"dino_portao": [sub.amostra(60) + Vector3.UP * 20.0, sub.amostra(0) - sub.tangente_em(0) * 60.0 + sub.lateral_em(0) * 25.0 + Vector3.UP * 14.0],
		"dino_saida": [sub.amostra(60), sub.amostra(0) - sub.tangente_em(0) * 26.0 + Vector3.UP * 7.0],
		"dino_ilhas": [sub.amostra(sub.indice_trecho("A", 360.0)) - Vector3.UP * 2.0, sub.amostra(sub.indice_trecho("A", 250.0)) + Vector3.UP * 16.0],
		"dino_portao_arm2": [sub.amostra(sub.indice_trecho("A", 895.0)) + Vector3.UP * 6.0, sub.amostra(sub.indice_trecho("A", 866.0)) + Vector3.UP * 9.0 + sub.lateral_em(sub.indice_trecho("A", 866.0)) * 24.0],
		"dino_portao_arm": [sub.amostra(sub.indice_trecho("A", 890.0)) + Vector3.UP * 6.0, sub.amostra(sub.indice_trecho("A", 862.0)) + Vector3.UP * 4.0 + sub.lateral_em(sub.indice_trecho("A", 862.0)) * 3.0],
		"dino_portico_plat": [sub.plataforma.pa(sub.plataforma.comprimento, 0.0, sub.plataforma.piso_y + 7.0), sub.plataforma.pa(sub.plataforma.comprimento + 34.0, 5.0, sub.plataforma.piso_y + 6.0)],
		"dino_portico": [sub.largada.pa(sub.largada.comprimento, 0.0, sub.largada.piso_y + 9.5), sub.largada.pa(sub.largada.comprimento - 30.0, 7.0, sub.largada.piso_y + 3.0)],
		# Pterossauros da plataforma: o bando visto do piso, e um de perto (TSC_PTERO_FIXO=1 deixa o primeiro parado no meio)
		"dino_pteros": [sub.plataforma.pa(55.0, 0.0, sub.plataforma.piso_y + 20.0), sub.plataforma.pa(6.0, -34.0, sub.plataforma.piso_y + 3.0)],
		"dino_ptero_perto": [sub.plataforma.pa(50.0, 0.0, sub.plataforma.piso_y + 7.0), sub.plataforma.pa(63.0, 9.0, sub.plataforma.piso_y + 9.5)],
		"dino_ptero_frente": [sub.plataforma.pa(50.0, 0.0, sub.plataforma.piso_y + 7.0), sub.plataforma.pa(51.0, 16.0, sub.plataforma.piso_y + 6.0)],
		# Pterossauros da estrada (E2, reta do trecho C): da pista olhando a subida, e de cima
		"dino_pteros_estrada": [sub.amostra(sub.indice_trecho("C", 800.0)) + Vector3.UP * 11.0, sub.amostra(sub.indice_trecho("C", 705.0)) + Vector3.UP * 3.0 + sub.lateral_em(sub.indice_trecho("C", 705.0)) * 3.0],
		"dino_pteros_estrada_alto": [sub.amostra(sub.indice_trecho("C", 790.0)), sub.amostra(sub.indice_trecho("C", 660.0)) + Vector3.UP * 60.0 + sub.lateral_em(sub.indice_trecho("C", 660.0)) * 40.0],
		"dino_plataforma": [sub.plataforma.pa(50.0, 0.0, sub.plataforma.piso_y), sub.plataforma.pa(130.0, -90.0, sub.plataforma.piso_y + 60.0)],
		# Cercado do tiranossauro (travessia da E4, C 435): de cima em 3/4, da estrada e de perto do portão
		"dino_cercado": [sub.amostra(maxi(sub.indice_trecho("C", 435.0), 0)) + Vector3.UP * 3.0, sub.amostra(maxi(sub.indice_trecho("C", 435.0), 0)) - sub.tangente_em(maxi(sub.indice_trecho("C", 435.0), 0)) * 46.0 + sub.lateral_em(maxi(sub.indice_trecho("C", 435.0), 0)) * 44.0 + Vector3.UP * 30.0],
		"dino_placa": [sub.amostra(maxi(sub.indice_trecho("C", 421.0), 0)) + Vector3.UP * 13.5, sub.amostra(maxi(sub.indice_trecho("C", 407.0), 0)) + Vector3.UP * 9.0 - sub.lateral_em(maxi(sub.indice_trecho("C", 407.0), 0)) * 2.0],
		"dino_cercado_pista": [sub.amostra(maxi(sub.indice_trecho("C", 435.0), 0)) + Vector3.UP * 5.0, sub.amostra(maxi(sub.indice_trecho("C", 385.0), 0)) + Vector3.UP * 3.2],
		"dino_cercado_perto": [sub.amostra(maxi(sub.indice_trecho("C", 421.0), 0)) + Vector3.UP * 6.0 + sub.lateral_em(maxi(sub.indice_trecho("C", 421.0), 0)) * 7.0, sub.amostra(maxi(sub.indice_trecho("C", 404.0), 0)) + Vector3.UP * 4.0 - sub.lateral_em(maxi(sub.indice_trecho("C", 404.0), 0)) * 3.0],
	}
	if vista.begins_with("dino_boca") and not dino.tuneis.is_empty():
		var n_b := maxi(int(vista.trim_prefix("dino_bocaf").trim_prefix("dino_boca")), 1) - 1
		var bocas: Array = []
		for tun: TunelVulcao in dino.tuneis:
			bocas.append_array(tun.bocas)
		if n_b < bocas.size():
			var bc: Array = bocas[n_b]
			var c: Vector3 = bc[0]
			var para_dentro: Vector3 = bc[2]
			if vista.begins_with("dino_bocaf"):   # de frente, como quem chega pela estrada
				camera.podio(c + Vector3.UP * 9.0, c - para_dentro * 46.0 + (bc[1] as Vector3) * 2.0 + Vector3.UP * 4.0)
				return
			camera.podio(c + Vector3.UP * 4.0, c - para_dentro * 70.0 + (bc[1] as Vector3) * 30.0 + Vector3.UP * 22.0)
		return
	if vista.begins_with("dino_dentro"):
		var tuneis: Array = ComplexoSubida.cfg_sub("tuneis", [])
		if not tuneis.is_empty():
			var f := float(int(vista.trim_prefix("dino_dentro"))) / 10.0
			var tu: Array = tuneis[0] if f < 0.5 or tuneis.size() < 2 else tuneis[1]
			var m := lerpf(float(tu[1]), float(tu[2]), fposmod(f * 2.0, 1.0) if tuneis.size() > 1 else f)
			var i := sub.indice_trecho(str(tu[0]), m)
			var j := sub.indice_adiante(i, 45.0)
			camera.podio(sub.amostra(j) + Vector3.UP * 1.5, sub.amostra(i) - sub.tangente_em(i) * 8.0 + Vector3.UP * 3.5)
		return
	if vista.begins_with("dino_armadilha"):
		var n_a := maxi(int(vista.trim_prefix("dino_armadilha")), 1) - 1
		var lista_a: Array = sub.armadilhas.posicoes() if sub.armadilhas else []
		if n_a < lista_a.size():
			var g: Array = lista_a[n_a]
			camera.podio(g[0] + Vector3.UP * 3.0, g[0] + g[1] * 22.0 - g[2] * 24.0 + Vector3.UP * 8.0)
		return
	if vista.begins_with("dino_estrada"):
		var m_e := float(int(vista.trim_prefix("dino_estrada"))) * 100.0
		var i_e := 0
		while i_e < sub.total_amostras() - 40 and sub.progresso_amostra(i_e) < m_e:
			i_e += 1
		var j_e := mini(i_e + 40, sub.total_amostras() - 1)
		camera.podio(sub.amostra(j_e) + Vector3.UP * 1.0, sub.amostra(i_e) - sub.tangente_em(i_e) * 9.0 + Vector3.UP * 4.0)
		return
	if vista.begins_with("dino_bicho") and dino.parque:
		var n_d := maxi(int(vista.trim_prefix("dino_bicho")), 1) - 1
		if n_d < dino.parque._bichos.size():
			var raiz: Node3D = dino.parque._bichos[n_d].d.raiz
			var p := raiz.global_position
			var fr := -raiz.global_transform.basis.z
			var comp: float = dino.parque._bichos[n_d].d.comp
			camera.podio(p + Vector3.UP * comp * 0.2, p + fr * comp * 1.1 + fr.cross(Vector3.UP) * comp * 0.9 + Vector3.UP * comp * 0.35)
		return
	if vista.begins_with("dino_carro"):
		# Carro do jogador de perto: dino_carro_frente (faróis) e dino_carro_tras (lanternas)
		for no_v in get_tree().get_nodes_in_group("veiculo"):
			var vj := no_v as Veiculo
			if vj and vj.eh_jogador:
				var bj := vj.global_transform.basis
				var lado_c := -1.0 if vista.ends_with("frente") else 1.0
				camera.podio(vj.global_position + Vector3.UP * 0.9, vj.global_position + bj.z * lado_c * 6.0 + bj.x * 2.6 + Vector3.UP * 1.7)
		return
	if vista.begins_with("dino_livre"):
		# TSC_CAM_POS / TSC_CAM_ALVO: "x,y,z" ou vários separados por ";" (dino_livre2 usa o segundo...)
		var n_l := maxi(int(vista.trim_prefix("dino_livre")), 1) - 1
		var l_pos := OS.get_environment("TSC_CAM_POS").split(";")
		var l_mira := OS.get_environment("TSC_CAM_ALVO").split(";")
		var pos := l_pos[mini(n_l, l_pos.size() - 1)].split_floats(",")
		var mira := l_mira[mini(n_l, l_mira.size() - 1)].split_floats(",")
		camera.podio(Vector3(mira[0], mira[1], mira[2]), Vector3(pos[0], pos[1], pos[2]))
		return
	var par: Array = dv.get(vista, dv.dino_mapa)
	camera.podio(par[0], par[1])


## Capturas de tela automáticas para conferência visual: TSC_FOTOS="fase:segundos,...", TSC_FOTO_DIR e TSC_SEM_HUD (esconde o HUD).
func _capturas(delta: float) -> void:
	if _fotos.is_empty():
		_fotos = Array(OS.get_environment("TSC_FOTOS").split(","))
		if OS.get_environment("TSC_SEM_HUD") != "":
			hud.visible = false
		OS.set_environment("TSC_FOTOS", "")
		_t_ativa = 0.0
		# Fotos com nome de vista do Frozen Peak (gelo_...): cada foto usa a própria vista
		var primeira := str(_fotos[0]).split(":")[0]
		_vista_debug(primeira if primeira.begins_with("gelo") or primeira.begins_with("dino") or primeira.begins_with("selva") else OS.get_environment("TSC_CAM_VISTA"))
	if str(_fotos[0]).begins_with("gelo") or str(_fotos[0]).begins_with("dino") or str(_fotos[0]).begins_with("selva"):
		_vista_debug(str(_fotos[0]).split(":")[0])   # reaplica a cada quadro (a contagem troca a câmera)
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
		elif str(_fotos[0]).begins_with("gelo") or str(_fotos[0]).begins_with("dino") or str(_fotos[0]).begins_with("selva"):
			_vista_debug(str(_fotos[0]).split(":")[0])


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
