extends Node
## Progresso offline por carro: XP, nível e upgrades instalados (config/upgrades.json).
## Salvo em user://progresso.json. Créditos e loja ficam com o modo online.

const ARQUIVO := "user://progresso.json"

## Atributos que moram em jogo.json (valem para todos os carros) e que os upgrades podem alterar.
const GLOBAIS := {
	"nitro_duracao": "fisica.nitro_duracao",
	"nitro_aceleracao": "fisica.nitro_aceleracao",
	"ejetor_impulso": "fisica.ejetor_impulso",
}

## {veiculo_id: {"xp": int, "upgrades": {categoria: nivel}}}
var carros: Dictionary = {}


func _ready() -> void:
	carregar()


func carregar() -> void:
	if not FileAccess.file_exists(ARQUIVO):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(ARQUIVO))
	if d is Dictionary:
		carros = d.get("carros", {})


func salvar() -> void:
	var f := FileAccess.open(ARQUIVO, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"carros": carros}, "\t"))


func _carro(id: String) -> Dictionary:
	if not carros.has(id):
		carros[id] = {"xp": 0, "upgrades": {}}
	return carros[id]


func _prog(chave: String, padrao):
	return Config.upgrades.get("progressao", {}).get(chave, padrao)


func categorias() -> Array:
	return Config.upgrades.get("categorias", [])


func categoria(cat_id: String) -> Dictionary:
	for c in categorias():
		if c.id == cat_id:
			return c
	return {}


# ------------------------------------------------------------------ XP e nível

func xp(id: String) -> int:
	return int(_carro(id).get("xp", 0))


func nivel(id: String) -> int:
	var tabela: Array = _prog("xp_niveis", [0])
	var n := 1
	for i in tabela.size():
		if xp(id) >= int(tabela[i]):
			n = i + 1
	return n


func nivel_maximo() -> int:
	return (_prog("xp_niveis", [0]) as Array).size()


## [xp dentro do nível atual, xp necessário para o próximo] (próximo = 0 no nível máximo).
func faixa_xp(id: String) -> Vector2i:
	var tabela: Array = _prog("xp_niveis", [0])
	var n := nivel(id)
	if n >= tabela.size():
		return Vector2i(0, 0)
	var ini := int(tabela[n - 1])
	return Vector2i(xp(id) - ini, int(tabela[n]) - ini)


## XP da partida para o carro usado. Devolve {ganho, subiu_nivel, nivel}.
func registrar_partida(id: String, pontos: int, venceu: bool) -> Dictionary:
	var antes := nivel(id)
	var ganho := int(_prog("xp_partida", 40)) + pontos * int(_prog("xp_por_ponto", 10))
	if venceu:
		ganho += int(_prog("xp_vitoria", 60))
	_carro(id).xp = xp(id) + ganho
	salvar()
	return {"ganho": ganho, "subiu_nivel": nivel(id) > antes, "nivel": nivel(id)}


# ------------------------------------------------------------------ upgrades

func nivel_upgrade(id: String, cat_id: String) -> int:
	return int(_carro(id).upgrades.get(cat_id, 0))


func niveis_upgrade(id: String) -> Dictionary:
	var r := {}
	for c in categorias():
		r[c.id] = nivel_upgrade(id, c.id)
	return r


## Nível do carro exigido para o nível `n` (1..) da categoria.
func requisito(cat_id: String, n: int) -> int:
	var niveis: Array = categoria(cat_id).get("niveis", [])
	if n < 1 or n > niveis.size():
		return 999
	return int(niveis[n - 1].get("nivel_veiculo", 1))


func liberado(id: String, cat_id: String, n: int) -> bool:
	return bool(_prog("liberar_tudo", false)) or nivel(id) >= requisito(cat_id, n)


func definir_upgrade(id: String, cat_id: String, n: int) -> bool:
	var total: int = categoria(cat_id).get("niveis", []).size()
	n = clampi(n, 0, total)
	if n > 0 and not liberado(id, cat_id, n):
		return false
	_carro(id).upgrades[cat_id] = n
	salvar()
	return true


## Cópia de `dados` (bloco do veiculos.json) com os upgrades aplicados. Os atributos globais
## (nitro, ejetor) entram no dicionário com o valor de fábrica do jogo.json antes do efeito.
func aplicar(dados: Dictionary, niveis: Dictionary) -> Dictionary:
	var r := dados.duplicate(true)
	for chave in GLOBAIS:
		if not r.has(chave):
			r[chave] = float(Config.valor(GLOBAIS[chave], 0.0))
	for c in categorias():
		var n := int(niveis.get(c.id, 0))
		var lista: Array = c.get("niveis", [])
		if n < 1 or lista.is_empty():
			continue
		var efeito: Dictionary = lista[mini(n, lista.size()) - 1].get("efeito", {})
		for atr in efeito:
			var base := float(r.get(atr, 1.0))
			r[atr] = base * float(efeito[atr].get("mult", 1.0)) + float(efeito[atr].get("soma", 0.0))
	return r


## Carro do jogador pronto para a partida (upgrades instalados).
func dados_jogador(id: String) -> Dictionary:
	return aplicar(Config.veiculo(id), niveis_upgrade(id))


## Carro de um bot: mesmos níveis do jogador ou de fábrica, conforme upgrades.json.
func dados_bot(dados: Dictionary, id_jogador: String) -> Dictionary:
	var niveis := niveis_upgrade(id_jogador) if _prog("bots", "espelhar") == "espelhar" else {}
	return aplicar(dados, niveis)
