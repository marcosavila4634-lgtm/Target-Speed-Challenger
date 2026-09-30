class_name DragBot
extends RefCounted
## Piloto automático do Drag Racing: segura o giro de largada em neutro, engata na verde depois
## do seu tempo de reação, troca perto da faixa ideal (com erro conforme o nível) e solta o nitro
## numa marcha sorteada. Nível = o mesmo dos bots do Target Flight (Configurações).

var motor: DragMotor
var rng := RandomNumberGenerator.new()
var nivel := {}
var _reacao := 0.25
var _queimar := false
var _rpm_largada := 5000.0
var _rpm_troca := 7150.0
var _nitro_marcha := 3
var _espera_troca := 0.0


func _init(p_motor: DragMotor, id_nivel: String, semente: int) -> void:
	motor = p_motor
	rng.seed = semente
	var niveis: Dictionary = Config.valor("drag.bots", {})
	nivel = niveis.get(id_nivel, niveis.get("medio", {}))
	var c: Dictionary = Config.valor("drag", {})
	var r: Array = nivel.get("reacao", [0.2, 0.35])
	_reacao = rng.randf_range(float(r[0]), float(r[1]))
	_queimar = rng.randf() < float(nivel.get("queimada", 0.0))
	var ideal: Array = c.get("largada_ideal", [4200, 5600])
	_rpm_largada = (float(ideal[0]) + float(ideal[1])) * 0.5 + rng.randfn(0.0, float(nivel.get("erro_largada", 600)))
	var nm: Array = nivel.get("nitro_marcha", [3, 4])
	_nitro_marcha = rng.randi_range(int(nm[0]), int(nm[1]))
	_sortear_troca()


func _sortear_troca() -> void:
	var c: Dictionary = Config.valor("drag", {})
	_rpm_troca = float(c.get("centro_perfeito", 7150)) + rng.randfn(0.0, float(nivel.get("erro_troca", 400)))
	_espera_troca = 0.0


## Decide as entradas antes de cada passo da simulação.
func pilotar(dt: float) -> void:
	var m := motor
	if m.chegou:
		return
	if m.marcha == 0:
		# Segura o giro de largada (em neutro o motor vai até lenta + faixa × acelerador)
		var c: Dictionary = Config.valor("drag", {})
		var lenta := float(c.get("rpm_lenta", 900))
		var limite := float(c.get("rpm_limite", 8000))
		m.acelerador = clampf((_rpm_largada - lenta) / (limite + 400.0 - lenta) + (_rpm_largada - m.rpm) / 4000.0, 0.0, 1.0)
		var engate := m.t_verde + _reacao
		if _queimar:
			engate = m.t_verde - 0.08
		if m.tempo >= engate and m.t_verde < INF:
			m.subir_marcha()
			m.acelerador = 1.0
		return
	m.acelerador = 1.0
	if m.marcha == _nitro_marcha:
		m.nitro_pedido = true
	if m.marcha < m.marchas_total() and m.velocidade > 2.0:
		# Passou do giro sem trocar (alvo acima do limitador): troca depois de um instante
		if m.rpm >= minf(_rpm_troca, 7950.0) or m.no_limitador:
			_espera_troca += dt
			if m.rpm >= _rpm_troca or _espera_troca > 0.15:
				m.subir_marcha()
				_sortear_troca()
