class_name Gravador
extends Node
## Grava as partidas do Target Flight para estudar a pilotagem (e ajustar os bots): um arquivo
## JSON Lines por etapa em gravacoes/ na pasta do projeto (user://gravacoes no jogo exportado).
## 1ª linha: cabeçalho (mapa, etapa, alvo, participantes). Depois uma linha por amostra: o jogador
## a cada AMOSTRA_JOGADOR quadros de física, os bots a cada AMOSTRA_BOT. Eventos (paraquedas,
## ejetor, toque no alvo, eliminação, checkpoint) entram na hora. Última linha: resultado de todos.
## Liga/desliga em jogo.json → partida.gravar.

const AMOSTRA_JOGADOR := 3   # 20 por segundo
const AMOSTRA_BOT := 12      # 5 por segundo

var _arq: FileAccess
var _partida: Node
var _t := 0.0
var _quadro := 0
var _resultados := []
var _conexoes := []   # [sinal, callable] para desligar no fim da etapa


static func pasta() -> String:
	return ProjectSettings.globalize_path("res://gravacoes" if not OS.has_feature("template") else "user://gravacoes")


## Abre o arquivo da etapa no "JÁ!" e escreve o cabeçalho.
func comecar(partida: Node) -> void:
	terminar()
	_partida = partida
	_t = 0.0
	_quadro = 0
	_resultados.clear()
	DirAccess.make_dir_recursive_absolute(pasta())
	var hora := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var mapa := str(Sessao.mapa_id)
	var nome := "%s/%s_%s_etapa%d.jsonl" % [pasta(), hora, mapa, int(partida.etapa_idx) + 1]
	_arq = FileAccess.open(nome, FileAccess.WRITE)
	if _arq == null:
		push_warning("gravador: não abriu " + nome)
		return
	var gente := []
	for p in partida.participantes:
		var v: Veiculo = p.veiculo
		var bot := p.controle is PilotoBot
		gente.append({"nome": p.nome, "equipe": p.equipe, "jogador": p.jogador, "carro": str(v.dados.get("id", "")),
			"bot_nivel": Sessao.nivel_bots if bot else "", "personalidade": str((p.controle.get("_perso") as Dictionary).get("nome", "")) if bot else "",
			"ativo": v.visible})
	_linha({"tipo": "cabecalho", "mapa": mapa, "etapa": int(partida.etapa_idx) + 1, "cfg_etapa": partida._cfg_etapa(),
		"alvo": _v(partida.alvo.centro_base), "participantes": gente, "arquivo": nome.get_file()})
	for p in partida.participantes:
		var v: Veiculo = p.veiculo
		for par: Array in [[v.paraquedas_mudou, _evento_pq.bind(p.nome)], [v.ejetor_usado, _evento_simples.bind("ejetor", p.nome)],
				[v.tocou_alvo, _evento_alvo.bind(p.nome)], [v.foi_eliminado, _evento_simples.bind("eliminado", p.nome)],
				[v.ressurgiu, _evento_simples.bind("ressurgiu", p.nome)]]:
			(par[0] as Signal).connect(par[1])
			_conexoes.append(par)
	print("[GRAVADOR] gravando ", nome)


## Resultado de um participante (chamado no fim da etapa, antes de terminar()).
func resultado(p: Dictionary, texto: String, pts: int) -> void:
	var v: Veiculo = p.veiculo
	_resultados.append({"nome": p.nome, "jogador": p.jogador, "texto": texto, "pontos": pts,
		"eliminado": v.eliminado, "telemetria": _limpo(v.telemetria)})


func terminar() -> void:
	if _arq == null:
		return
	_linha({"tipo": "resultado", "t": snappedf(_t, 0.01), "participantes": _resultados})
	for par: Array in _conexoes:
		var s := par[0] as Signal
		if is_instance_valid(s.get_object()) and s.is_connected(par[1]):
			(par[0] as Signal).disconnect(par[1])
	_conexoes.clear()
	_arq.close()
	_arq = null
	print("[GRAVADOR] etapa gravada")


func _physics_process(delta: float) -> void:
	if _arq == null or _partida == null or _partida.fase != 3:   # Fase.ATIVA
		return
	_t += delta
	_quadro += 1
	for p in _partida.participantes:
		var v: Veiculo = p.veiculo
		if not v.visible:
			continue
		if _quadro % (AMOSTRA_JOGADOR if p.jogador else AMOSTRA_BOT) != 0:
			continue
		var xf := v.global_transform
		var ate_alvo: Vector3 = _partida.alvo.centro_base - xf.origin
		var e := v.entrada
		_linha({"t": snappedf(_t, 0.01), "q": p.nome, "p": _v(xf.origin), "vel": _v(v.linear_velocity),
			"frente": _v(-xf.basis.z), "cima": _v(xf.basis.y), "rumo": snappedf(v.rumo, 0.001),
			"estado": v.estado, "rodas": v.rodas_no_chao, "pq": v.paraquedas_aberto, "nitro": v.nitro_ativo,
			"carga": snappedf(v.carga_nitro, 0.01), "cp": v.checkpoint, "fant": v.fantasma(), "travado": v.travado,
			"elim": v.eliminado, "alvo_h": snappedf(Vector2(ate_alvo.x, ate_alvo.z).length(), 0.1), "alvo_dy": snappedf(ate_alvo.y, 0.1),
			"in": {"ac": snappedf(float(e.acelerar), 0.01), "fr": snappedf(float(e.freiar), 0.01), "re": snappedf(float(e.re), 0.01),
				"dir": snappedf(float(e.direcao), 0.01), "ni": bool(e.nitro)}})


func _evento_pq(v: Veiculo, aberto: bool, nome: String) -> void:
	_linha({"t": snappedf(_t, 0.01), "q": nome, "evento": "paraquedas_" + ("abriu" if aberto else "fechou"),
		"p": _v(v.global_position), "vel": _v(v.linear_velocity)})


func _evento_simples(v: Veiculo, tipo: String, nome: String) -> void:
	_linha({"t": snappedf(_t, 0.01), "q": nome, "evento": tipo, "p": _v(v.global_position), "vel": _v(v.linear_velocity)})


func _evento_alvo(v: Veiculo, nome: String) -> void:
	_linha({"t": snappedf(_t, 0.01), "q": nome, "evento": "tocou_alvo", "p": _v(v.global_position), "vel": _v(v.linear_velocity),
		"zona": _partida.alvo.zona_do_veiculo(v)})


func _linha(d: Dictionary) -> void:
	if _arq:
		_arq.store_line(JSON.stringify(d))


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


## Telemetria com vetores viram listas (JSON não tem Vector3).
static func _limpo(d: Dictionary) -> Dictionary:
	var r := {}
	for k in d:
		r[k] = _v(d[k]) if d[k] is Vector3 else d[k]
	return r


func _exit_tree() -> void:
	terminar()   # saiu da partida no meio da etapa: fecha o arquivo com o que tiver
