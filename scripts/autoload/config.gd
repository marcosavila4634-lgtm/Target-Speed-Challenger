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
	"olhar_tras": [KEY_C],
	"pausa": [KEY_ESCAPE],
	# Drag Racing (direção automática: A/D ficam livres para o câmbio)
	"subir_marcha": [KEY_E, KEY_D],
	"reduzir_marcha": [KEY_Q, KEY_A],
}

## Controle (joystick; nomes no padrão Xbox, valem para qualquer controle que o Windows reconheça).
## Botões: JOY_BUTTON_*; eixos: [eixo, sentido]. Gatilhos e alavanca são analógicos (acelera e vira aos poucos).
##   RT acelerar • LT ré / freio • alavanca esquerda ou setas: direção • A ejetor • Y paraquedas
##   X ou B nitro • RB / LB câmbio (Drag) • LB olhar para trás • seta para cima: próxima câmera • START pausa
const CONTROLES_JOY := {
	"acelerar": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"freiar": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"esquerda": [[JOY_AXIS_LEFT_X, -1.0], JOY_BUTTON_DPAD_LEFT],
	"direita": [[JOY_AXIS_LEFT_X, 1.0], JOY_BUTTON_DPAD_RIGHT],
	"ejetor": [JOY_BUTTON_A],
	"paraquedas": [JOY_BUTTON_Y],
	"nitro": [JOY_BUTTON_X, JOY_BUTTON_B],
	"proxima_camera": [JOY_BUTTON_DPAD_UP],
	"olhar_tras": [JOY_BUTTON_LEFT_SHOULDER],
	"pausa": [JOY_BUTTON_START],
	"subir_marcha": [JOY_BUTTON_RIGHT_SHOULDER],
	"reduzir_marcha": [JOY_BUTTON_LEFT_SHOULDER],
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
## Fase escolhida (jogo.json → mapas). Os valores em "sobrepor" da fase têm prioridade em valor().
var mapa_id := ""
var _sobrepor: Dictionary = {}


func _ready() -> void:
	jogo = _ler_json(CAMINHO_JOGO)
	veiculos = _ler_json(CAMINHO_VEICULOS).get("veiculos", [])
	avatares = _ler_json(CAMINHO_AVATARES).get("avatares", [])
	upgrades = _ler_json(CAMINHO_UPGRADES)
	_registrar_controles()
	escolher_mapa(OS.get_environment("TSC_MAPA"))


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
## Primeiro procura nos valores próprios da fase escolhida ("sobrepor"), depois no jogo.json.
func valor(caminho: String, padrao = null):
	var partes := caminho.split(".")
	var achou := [false]
	var v = _buscar(_sobrepor, partes, achou)
	if achou[0]:
		return v
	v = _buscar(jogo, partes, achou)
	return v if achou[0] else padrao


func _buscar(raiz: Dictionary, partes: PackedStringArray, achou: Array):
	var atual = raiz
	for parte in partes:
		if atual is Dictionary and atual.has(parte):
			atual = atual[parte]
		else:
			return null
	achou[0] = true
	return atual


func mapas() -> Array:
	return jogo.get("mapas", [{"id": "canyon_rush", "nome": "Canyon Rush"}])


func mapa_atual() -> Dictionary:
	for m in mapas():
		if m.get("id") == mapa_id:
			return m
	return mapas()[0]


## Troca a fase ativa (id vazio ou desconhecido = a primeira da lista).
func escolher_mapa(id: String) -> void:
	var m: Dictionary = mapas()[0]
	for c in mapas():
		if c.get("id") == id:
			m = c
	mapa_id = m.get("id", "")
	_sobrepor = m.get("sobrepor", {})


## Opção gráfica: o valor do nível de qualidade escolhido no menu (grafico.qualidades.<nível>.<chave>) ou, se o
## nível não muda essa opção, o de grafico.<chave>.
func grafico(chave: String, padrao):
	var nivel: Dictionary = (jogo.get("grafico", {}) as Dictionary).get("qualidades", {}).get(
		OS.get_environment("TSC_QUALIDADE") if OS.get_environment("TSC_QUALIDADE") != "" else Sessao.qualidade, {})   # TSC_QUALIDADE: teste, sem gravar na preferência do jogador
	if nivel.has(chave):
		return nivel[chave]
	return valor("grafico." + chave, padrao)


## Plataforma conjunta: todas as equipes largam juntas da mesma arena.
func mapa_arena() -> bool:
	return mapa_atual().get("tipo", "") == "arena"


## Tipo de mapa: "" (Canyon Rush, uma rampa por equipe), "arena" ou "subida" (Climb to Death).
func mapa_tipo() -> String:
	return str(mapa_atual().get("tipo", ""))


## Ambientação urbana (City Rush): prédios no lugar das mesas e pináculos do cânion.
func mapa_cidade() -> bool:
	return mapa_atual().get("ambiente", "") == "cidade"


## Ambientação do Egito (Pharaoh's Climb): deserto com o Nilo, pirâmides, obeliscos e templos.
func mapa_egito() -> bool:
	return mapa_atual().get("ambiente", "") == "egito"


func mapa_selva() -> bool:
	return mapa_atual().get("ambiente", "") == "selva"


## Ambientação de gelo (Frozen Peak): montanhas nevadas, lago congelado e estruturas de gelo e aço.
func mapa_gelo() -> bool:
	return mapa_atual().get("ambiente", "") == "gelo"


## Ambientação do parque dos dinossauros (Extinction Day): selva de árvores gigantes, vulcão com túnel,
## dinossauros andando e o meteoro chegando etapa a etapa.
func mapa_dino() -> bool:
	return mapa_atual().get("ambiente", "") == "dino"


func nome_mapa() -> String:
	return str(mapa_atual().get("nome", "Canyon Rush"))


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
		# Controle: device -1 = qualquer controle ligado
		for item in CONTROLES_JOY.get(acao, []):
			if item is Array:
				var eixo := InputEventJoypadMotion.new()
				eixo.device = -1
				eixo.axis = item[0]
				eixo.axis_value = item[1]
				InputMap.action_add_event(acao, eixo)
			else:
				var botao := InputEventJoypadButton.new()
				botao.device = -1
				botao.button_index = item
				InputMap.action_add_event(acao, botao)
		InputMap.action_set_deadzone(acao, 0.2)
	Input.joy_connection_changed.connect(_controle_mudou)
	for id in Input.get_connected_joypads():
		print("[CONTROLE] ligado: ", Input.get_joy_name(id))


## Há um controle ligado? (o HUD mostra a ajuda dos botões)
func tem_controle() -> bool:
	return not Input.get_connected_joypads().is_empty()


func _controle_mudou(id: int, ligado: bool) -> void:
	print("[CONTROLE] %s: %s" % ["ligado" if ligado else "desligado", Input.get_joy_name(id) if ligado else str(id)])
