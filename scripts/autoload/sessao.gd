extends Node
## Escolhas do jogador (nome, veículo, piloto, opções da sala). Salvas em user://perfil.json.

const ARQUIVO := "user://perfil.json"

var nome_jogador := "KZULO"
var veiculo_id := ""
var avatar_id := ""
var tempo_modo := "etapa"
var tempo_segundos := 180
## Tempo escolhido por mapa (id → segundos). Sem escolha, vale o padrão do mapa (sobrepor.partida) ou o geral.
var tempo_por_mapa := {}
var jogadores_por_equipe := 1
## Nível dos bots: facil, medio, alto ou pro (jogo.json bots.niveis).
var nivel_bots := "medio"
var mapa_id := ""
## Pista do Drag Racing (jogo.json → drag.pistas).
var drag_pista_id := ""
## Modo do Target Flight: "bots" (todas as etapas) ou "rapida" (só a etapa escolhida).
var modo_jogo := "bots"
## Etapa da partida rápida (índice a partir de 0; conferida contra o mapa em etapa_unica()).
var etapa_rapida := 0

## Teste automático: o carro do jogador é pilotado por bot e a telemetria vai para o console.
## Ativado com: godot -- --teste
var teste_automatico := false


func _ready() -> void:
	tempo_modo = Config.valor("partida.tempo_modo", "etapa")
	tempo_segundos = int(Config.valor("partida.tempo_segundos", 180))
	jogadores_por_equipe = int(Config.valor("partida.jogadores_por_equipe", 1))
	carregar()
	if OS.get_environment("TSC_NIVEL_BOTS") != "":
		nivel_bots = OS.get_environment("TSC_NIVEL_BOTS")   # teste: forçar o nível dos bots
	if OS.get_environment("TSC_MAPA") != "":
		mapa_id = OS.get_environment("TSC_MAPA")
	escolher_mapa(mapa_id)
	if OS.get_environment("TSC_RAPIDA") != "":
		modo_jogo = "rapida"   # teste: partida rápida só na etapa N
		etapa_rapida = int(OS.get_environment("TSC_RAPIDA")) - 1
	teste_automatico = "--teste" in OS.get_cmdline_user_args()
	if OS.get_environment("TSC_VEICULO") != "":
		veiculo_id = OS.get_environment("TSC_VEICULO")   # teste: forçar o carro do jogador
	var ativos := Config.veiculos_ativos()
	if Config.veiculo(veiculo_id).is_empty() and not ativos.is_empty():
		veiculo_id = ativos[0].id
	if OS.get_environment("TSC_AVATAR") != "":
		avatar_id = OS.get_environment("TSC_AVATAR")   # teste: forçar o piloto do jogador
	var pilotos := Config.avatares_ativos()
	if Config.avatar(avatar_id).is_empty() and not pilotos.is_empty():
		avatar_id = pilotos[0].id


## Tempo (s) do mapa escolhido: o que o jogador ajustou para ele, senão o padrão do mapa
## (Climb to Death = 5 min), senão o geral.
func tempo_do_mapa() -> int:
	if tempo_por_mapa.has(mapa_id):
		return int(tempo_por_mapa[mapa_id])
	var padrao = Config.mapa_atual().get("sobrepor", {}).get("partida", {}).get("tempo_segundos", null)
	return int(padrao) if padrao != null else tempo_segundos


## Etapas jogáveis do mapa escolhido (as primeiras partida.etapas da lista).
func etapas_do_mapa() -> Array:
	var lista: Array = Config.valor("etapas", [])
	return lista.slice(0, clampi(int(Config.valor("partida.etapas", 4)), 1, 8))


## Etapa única da partida (índice) na partida rápida, ou -1 quando se jogam todas.
func etapa_unica() -> int:
	if modo_jogo != "rapida":
		return -1
	return clampi(etapa_rapida, 0, maxi(etapas_do_mapa().size() - 1, 0))


func definir_tempo_do_mapa(segundos: int) -> void:
	tempo_por_mapa[mapa_id] = segundos


## Fase da próxima partida (Canyon Rush, Canyon Combat Target...).
func escolher_mapa(id: String) -> void:
	Config.escolher_mapa(id)
	mapa_id = Config.mapa_id


func carregar() -> void:
	if not FileAccess.file_exists(ARQUIVO):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	if d is Dictionary:
		nome_jogador = d.get("nome_jogador", nome_jogador)
		veiculo_id = d.get("veiculo_id", veiculo_id)
		avatar_id = d.get("avatar_id", avatar_id)
		tempo_modo = d.get("tempo_modo", tempo_modo)
		tempo_segundos = int(d.get("tempo_segundos", tempo_segundos))
		jogadores_por_equipe = int(d.get("jogadores_por_equipe", jogadores_por_equipe))
		nivel_bots = str(d.get("nivel_bots", nivel_bots))
		mapa_id = d.get("mapa_id", mapa_id)
		drag_pista_id = str(d.get("drag_pista_id", drag_pista_id))
		modo_jogo = str(d.get("modo_jogo", modo_jogo))
		etapa_rapida = int(d.get("etapa_rapida", etapa_rapida))
		var t = d.get("tempo_por_mapa", {})
		if t is Dictionary:
			tempo_por_mapa = t


func salvar() -> void:
	var f := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"nome_jogador": nome_jogador,
			"veiculo_id": veiculo_id,
			"avatar_id": avatar_id,
			"tempo_modo": tempo_modo,
			"tempo_segundos": tempo_segundos,
			"jogadores_por_equipe": jogadores_por_equipe,
			"nivel_bots": nivel_bots,
			"mapa_id": mapa_id,
			"drag_pista_id": drag_pista_id,
			"modo_jogo": modo_jogo,
			"etapa_rapida": etapa_rapida,
			"tempo_por_mapa": tempo_por_mapa,
		}, "\t"))


## Pista do Drag escolhida (a primeira da lista se não houver escolha válida).
func drag_pista() -> Dictionary:
	var lista: Array = Config.valor("drag.pistas", [{"id": "tsc_dragway", "nome": "TSC Dragway", "estilo": "estadio"}])
	var id := OS.get_environment("TSC_PISTA") if OS.get_environment("TSC_PISTA") != "" else drag_pista_id
	for p in lista:
		if p.get("id") == id:
			return p
	return lista[0]
