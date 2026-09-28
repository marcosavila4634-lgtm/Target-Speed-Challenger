extends Node
## Carrega config/jogo.json, config/veiculos.json, config/avatares.json e config/upgrades.json e registra os controles.
## Um arquivo com o mesmo nome em user://config/ tem prioridade (útil para testar ajustes).

const CAMINHO_JOGO := "res://config/jogo.json"
const CAMINHO_VEICULOS := "res://config/veiculos.json"
const CAMINHO_AVATARES := "res://config/avatares.json"
const CAMINHO_UPGRADES := "res://config/upgrades.json"

const CONTROLES := {
	"acelerar": [KEY_W, KEY_UP],
	"freiar": [KEY_S, KEY_DOWN],
	"esquerda": [KEY_A, KEY_LEFT],
	"direita": [KEY_D, KEY_RIGHT],
	"ejetor": [KEY_SPACE],
	"paraquedas": [KEY_E],
	"nitro": [KEY_SHIFT],
	"proxima_camera": [KEY_TAB],
	"pausa": [KEY_ESCAPE],
}

const EQUIPES := [
	{"nome": "AZUL", "cor": Color(0.16, 0.42, 1.0), "direcao": Vector3(0, 0, -1)},
	{"nome": "AMARELO", "cor": Color(1.0, 0.8, 0.12), "direcao": Vector3(1, 0, 0)},
	{"nome": "VERDE", "cor": Color(0.2, 0.82, 0.32), "direcao": Vector3(-1, 0, 0)},
	{"nome": "ROXO", "cor": Color(0.62, 0.34, 0.95), "direcao": Vector3(0, 0, 1)},
]

var jogo: Dictionary = {}
var veiculos: Array = []
var avatares: Array = []
var upgrades: Dictionary = {}


func _ready() -> void:
	jogo = _ler_json(CAMINHO_JOGO)
	veiculos = _ler_json(CAMINHO_VEICULOS).get("veiculos", [])
	avatares = _ler_json(CAMINHO_AVATARES).get("avatares", [])
	upgrades = _ler_json(CAMINHO_UPGRADES)
	_registrar_controles()


func _ler_json(caminho: String) -> Dictionary:
	for c in ["user://config/" + caminho.get_file(), caminho]:
		if not FileAccess.file_exists(c):
			continue
		var dados = JSON.parse_string(FileAccess.get_file_as_string(c))
		if dados is Dictionary:
			return dados
		push_error("JSON inválido: " + c)
	return {}


## Lê um valor pelo caminho "secao.chave", por exemplo valor("fisica.ejetor_impulso", 12).
func valor(caminho: String, padrao = null):
	var atual = jogo
	for parte in caminho.split("."):
		if atual is Dictionary and atual.has(parte):
			atual = atual[parte]
		else:
			return padrao
	return atual


func veiculos_ativos() -> Array:
	return veiculos.filter(func(v): return v.get("ativo", false) and ResourceLoader.exists(v.get("modelo", "")))


func veiculo(id: String) -> Dictionary:
	for v in veiculos:
		if v.get("id") == id:
			return v
	return {}


func avatares_ativos() -> Array:
	return avatares.filter(func(a): return a.get("ativo", false) and ResourceLoader.exists(a.get("modelo", "")))


func avatar(id: String) -> Dictionary:
	for a in avatares:
		if a.get("id") == id:
			return a
	return {}


func _registrar_controles() -> void:
	for acao in CONTROLES:
		if not InputMap.has_action(acao):
			InputMap.add_action(acao)
		for tecla in CONTROLES[acao]:
			var ev := InputEventKey.new()
			ev.physical_keycode = tecla
			InputMap.action_add_event(acao, ev)
