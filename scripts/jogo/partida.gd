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
	var n_rival := 1
	var n_aliado := 1
	for e in equipes_qtd:
		for k in por_equipe:
			var eh_jogador := e == 0 and k == 0
			var nome := Sessao.nome_jogador.to_upper()
			if not eh_jogador:
				if e == 0:
					nome = "ALIADO %02d" % n_aliado
					n_aliado += 1
				else:
					nome = "RIVAL %02d" % n_rival
					n_rival += 1
			var dados: Dictionary = Config.veiculo(Sessao.veiculo_id) if eh_jogador else ativos[_rng.randi() % ativos.size()]
			if dados.is_empty():
				dados = ativos[0]
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
	hud.resultado_final({"titulo": titulo, "subtitulo": "Canyon Rush — resultado final", "equipes": equipes,
		"jogadores": jogadores, "mvp": "%s (%d pts)" % [mvp.nome, mvp.total]})
	if venceu:
		Audio.tocar("ambiente/publico_vibra_forte.mp3", null, 0.0, 1.0, 0.0, "Ambiente")
	Audio.interface("confirmar" if venceu else "erro", -2.0)
	if Sessao.teste_automatico:
		print("[TESTE] Partida concluída. Vencedora: ", Config.EQUIPES[ordem[0]].nome)
		get_tree().quit()


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


## Capturas de tela automáticas para conferência visual: TSC_FOTOS="fase:segundos,...", TSC_FOTO_DIR e TSC_SEM_HUD (esconde o HUD).
func _capturas(delta: float) -> void:
	if _fotos.is_empty():
		_fotos = Array(OS.get_environment("TSC_FOTOS").split(","))
		if OS.get_environment("TSC_SEM_HUD") != "":
			hud.visible = false
		OS.set_environment("TSC_FOTOS", "")
		_t_ativa = 0.0
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
