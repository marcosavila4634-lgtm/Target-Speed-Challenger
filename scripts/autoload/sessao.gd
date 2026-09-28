extends Node
## Escolhas do jogador (nome, veículo, piloto, opções da sala). Salvas em user://perfil.json.

const ARQUIVO := "user://perfil.json"

var nome_jogador := "KZULO"
var veiculo_id := ""
var avatar_id := ""
var tempo_modo := "etapa"
var tempo_segundos := 180
var jogadores_por_equipe := 1

## Teste automático: o carro do jogador é pilotado por bot e a telemetria vai para o console.
## Ativado com: godot -- --teste
var teste_automatico := false


func _ready() -> void:
	tempo_modo = Config.valor("partida.tempo_modo", "etapa")
	tempo_segundos = int(Config.valor("partida.tempo_segundos", 180))
	jogadores_por_equipe = int(Config.valor("partida.jogadores_por_equipe", 1))
	carregar()
	teste_automatico = "--teste" in OS.get_cmdline_user_args()
	var ativos := Config.veiculos_ativos()
	if Config.veiculo(veiculo_id).is_empty() and not ativos.is_empty():
		veiculo_id = ativos[0].id
	var pilotos := Config.avatares_ativos()
	if Config.avatar(avatar_id).is_empty() and not pilotos.is_empty():
		avatar_id = pilotos[0].id


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
		}, "\t"))
