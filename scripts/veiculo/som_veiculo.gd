class_name SomVeiculo
extends Node3D
## Sons do carro, tirados do estado do veículo a cada quadro (a física não sabe do áudio):
## motor com timbre próprio de cada modelo e rotação por marchas simuladas e carga, assobio do
## turbo, rolagem e canto dos pneus (derrapagem e zigue-zague no alvo — no lugar da fumaça),
## vento, nitro, pouso/suspensão, batidas, troca de marcha, ejetor, paraquedas e água.
## Carros longe da câmera ficam mudos para poupar vozes.

const MARCHAS := [0.0, 0.18, 0.36, 0.55, 0.76, 1.05]   # limites de velocidade (fração da máxima)
const DIST_MUDO := 320.0
const TIMBRES := 6                                       # assets/audio/motor/loop_0..5

var v: Veiculo
var _motor: AudioStreamPlayer3D
var _turbo: AudioStreamPlayer3D
var _rolagem: AudioStreamPlayer3D
var _pneu: AudioStreamPlayer3D
var _nitro: AudioStreamPlayer3D
var _vento: AudioStreamPlayer          # só no carro do jogador: é o vento "no ouvido"
var _loops: Array[Node] = []
var _rpm := 0.15
var _marcha := 1
var _no_ar_ant := 0.0
var _vy_ant := 0.0
var _nitro_ant := false
var _vel_ant := Vector3.ZERO
var _espera_batida := 0.0
var _ativo := true


func montar(veiculo: Veiculo) -> void:
	v = veiculo
	name = "Som"
	var id := str(v.dados.get("id", v.dados.get("nome", "")))
	var timbre := int(v.dados.get("som_motor", absi(id.hash()) % TIMBRES))
	var jogador := 3.0 if v.eh_jogador else 0.0
	_motor = _loop("motor/loop_%d.wav" % timbre, "Motor", 16.0, jogador)
	_turbo = _loop_stream(Audio.turbo(), "Motor", 8.0, jogador)
	_rolagem = _loop("efeitos/rolagem.ogg", "Efeitos", 10.0, jogador)
	_pneu = _loop("efeitos/pneu_loop.wav", "Efeitos", 14.0, jogador)
	_nitro = _loop("efeitos/nitro_0.ogg", "Efeitos", 14.0, jogador)
	if v.eh_jogador:
		_vento = AudioStreamPlayer.new()
		_vento.stream = Audio.loop("efeitos/vento_forte.mp3")
		_vento.bus = "Efeitos"
		_vento.volume_db = -80.0
		add_child(_vento)
		_vento.play()
		_loops.append(_vento)
	v.ejetor_usado.connect(_ao_ejetor)
	v.paraquedas_mudou.connect(_ao_paraquedas)
	v.foi_eliminado.connect(_ao_eliminado)


## Partida do motor (carro do jogador, antes da contagem).
func dar_partida() -> void:
	Audio.tocar("motor/partida.wav", v.global_position, -2.0, 1.0, 0.0, "Motor", 12.0)
	_rpm = 0.6


func _loop(nome: String, canal: String, alcance: float, ganho_db: float) -> AudioStreamPlayer3D:
	return _loop_stream(Audio.loop(nome), canal, alcance, ganho_db)


func _loop_stream(st: AudioStream, canal: String, alcance: float, ganho_db: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = canal
	p.unit_size = alcance
	p.max_distance = DIST_MUDO + 40.0
	p.volume_db = -80.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.set_meta("ganho", ganho_db)
	add_child(p)
	# Começa num ponto qualquer do loop: carros iguais lado a lado não soam em uníssono
	p.play(randf() * maxf(st.get_length() - 0.05, 0.0))
	_loops.append(p)
	return p


func _nivel(p: Node, linear: float, base_db := 0.0) -> void:
	var db := linear_to_db(maxf(linear, 0.0001)) + base_db + float(p.get_meta("ganho", 0.0))
	p.set("volume_db", lerpf(float(p.get("volume_db")), db, 0.35))


func _process(delta: float) -> void:
	if v == null or v.eliminado:
		return
	var cam := get_viewport().get_camera_3d()
	var perto := v.eh_jogador or cam == null or cam.global_position.distance_to(v.global_position) < DIST_MUDO
	if perto != _ativo:
		_ativo = perto
		for p in _loops:
			p.set("stream_paused", not perto)
	if not perto:
		return

	var vel := v.linear_velocity
	var base := v.global_transform.basis
	var v_frente := absf(vel.dot(-base.z))
	var no_chao := v.rodas_no_chao > 0
	# No ar o "pra frente" controla o voo, não o motor: sem acelerar o som (pedido do dono)
	var voando := not no_chao and v.tempo_no_ar >= 0.3
	var acel := 0.0 if v.travado or voando else float(v.entrada.acelerar)
	var re := 0.0 if v.travado or voando else float(v.entrada.re)
	var carga := maxf(acel, re)

	# ---- Rotação: marchas no chão, marcha lenta no ar, só marcha lenta depois do alvo (motor bloqueado)
	var alvo_rpm := 0.14
	if v.travado:
		alvo_rpm = 0.1
	elif no_chao or v.tempo_no_ar < 0.3:
		var f := v_frente / maxf(v.vel_max, 1.0)
		var m := _marcha
		while m < MARCHAS.size() - 1 and f > MARCHAS[m]:
			m += 1
		while m > 1 and f < MARCHAS[m - 1] * 0.9:
			m -= 1
		if m > _marcha and acel > 0.5:
			_rpm -= 0.28   # troca de marcha: o giro cai e volta a subir
			if v.eh_jogador:
				Audio.tocar("efeitos/batida_leve_", v.global_position, -26.0, 0.7, 0.05, "Motor", 6.0)
		_marcha = m
		var lo: float = MARCHAS[m - 1]
		var hi: float = MARCHAS[m]
		alvo_rpm = lerpf(0.3 if m > 1 else 0.14, 1.0, clampf((f - lo) / (hi - lo), 0.0, 1.0))
		if re > 0.1:
			alvo_rpm = lerpf(0.25, 0.6, re)
		elif acel < 0.1:
			alvo_rpm = maxf(alvo_rpm * 0.85, 0.14)
	else:
		alvo_rpm = 0.18   # voando: marcha lenta
	_rpm = move_toward(_rpm, alvo_rpm, delta * (2.6 if alvo_rpm > _rpm else 1.6))
	_motor.pitch_scale = lerpf(0.55, 1.9, _rpm)
	var vol_motor := lerpf(0.35, 0.75, _rpm) * lerpf(0.7, 1.0, carga)
	if v.travado:
		vol_motor = 0.18
	_nivel(_motor, vol_motor)

	# ---- Turbo: assobio que sobe com giro e carga
	_turbo.pitch_scale = lerpf(0.5, 1.15, _rpm)
	_nivel(_turbo, clampf((_rpm - 0.45) * 2.0, 0.0, 1.0) * carga * 0.12)

	# ---- Pneus: rolagem com a velocidade; canto quando derrapam ou no zigue-zague do alvo
	var v_chao := v_frente if no_chao else 0.0
	_rolagem.pitch_scale = lerpf(0.7, 1.4, clampf(v_chao / 45.0, 0.0, 1.0))
	_nivel(_rolagem, clampf(v_chao / 25.0, 0.0, 1.0) * 0.35)
	var derrapa := 0.0
	if no_chao:
		var lateral := absf(vel.dot(base.x))
		derrapa = clampf((lateral - 2.0) / 6.0, 0.0, 1.0)
		if v.travado:
			derrapa = maxf(derrapa, clampf(vel.length() / 3.0, 0.0, 1.0) * clampf(v.atividade_volante() / 8.0, 0.0, 1.0))
	_pneu.pitch_scale = lerpf(0.9, 1.1, derrapa)
	_nivel(_pneu, derrapa * 0.55)

	# ---- Vento: cresce com a velocidade, mais forte no ar
	if _vento:
		var rapidez := vel.length()
		var ar := 1.0 if not no_chao else 0.45
		_nivel(_vento, clampf((rapidez - 8.0) / 55.0, 0.0, 1.0) * ar * 0.7)
		_vento.pitch_scale = lerpf(0.85, 1.25, clampf(rapidez / 70.0, 0.0, 1.0))

	# ---- Nitro: rajada de ar (whoosh) ao ligar e o som contínuo enquanto ele está ativo
	if v.nitro_ativo and not _nitro_ant:
		Audio.tocar("efeitos/whoosh.wav", v.global_position, -4.0, 1.3, 0.05, "Efeitos", 14.0)
	_nitro_ant = v.nitro_ativo
	_nivel(_nitro, 0.8 if v.nitro_ativo else 0.0)

	# ---- Pouso: batida da carroceria e mola da suspensão, pela velocidade de queda
	if _no_ar_ant > 0.35 and v.tempo_no_ar == 0.0:
		var forca := clampf(-_vy_ant / 14.0, 0.0, 1.0)
		if forca > 0.08:
			Audio.tocar("efeitos/pouso_", v.global_position, lerpf(-16.0, 2.0, forca), lerpf(1.1, 0.8, forca), 0.05, "Efeitos", 14.0)
			Audio.tocar("efeitos/mola_", v.global_position, lerpf(-18.0, -4.0, forca), 0.8, 0.1, "Efeitos", 8.0)
			_espera_batida = 0.3
	_no_ar_ant = v.tempo_no_ar
	_vy_ant = vel.y

	# ---- Batidas (outros carros, estruturas): mudança brusca de velocidade com contato
	_espera_batida -= delta
	var dv := (vel - _vel_ant).length()
	if v.contato_corpo and dv > 3.5 and _espera_batida <= 0.0:
		var tipo := "pesada" if dv > 9.0 else ("media" if dv > 5.5 else "leve")
		Audio.tocar("efeitos/batida_%s_" % tipo, v.global_position, clampf(-10.0 + dv, -10.0, 4.0), 1.0, 0.08, "Efeitos", 14.0)
		_espera_batida = 0.25
	_vel_ant = vel


## Para todos os sons contínuos (carros que saem de cena na comemoração final).
func silenciar() -> void:
	for p in _loops:
		p.call("stop")
	set_process(false)


func _ao_ejetor(_v: Veiculo) -> void:
	# Disparo pneumático: estalo metálico e estrondo grave curto
	Audio.tocar("efeitos/pouso_", v.global_position, 2.0, 0.7, 0.05, "Efeitos", 18.0)
	Audio.tocar("efeitos/explosao_grave_", v.global_position, -8.0, 1.6, 0.05, "Efeitos", 16.0)


func _ao_paraquedas(_v: Veiculo, aberto: bool) -> void:
	# Abrir: uma das duas gravações de paraquedas abrindo (2create, Freesound CC0), sorteada.
	# Fechar: o mesmo tecido, mais agudo e baixo (recolhendo/soltando).
	if aberto:
		Audio.tocar("efeitos/paraquedas_abrir_", v.global_position + Vector3.UP * 4.0, 1.0, 1.0, 0.05, "Efeitos", 18.0)
	else:
		Audio.tocar("efeitos/paraquedas_abrir_", v.global_position + Vector3.UP * 4.0, -7.0, 1.3, 0.05, "Efeitos", 12.0)


func _ao_eliminado(_v: Veiculo) -> void:
	for p in _loops:
		p.call("stop")
	if str(v.telemetria.get("motivo", "")) == "agua":
		Audio.tocar("efeitos/agua_splash_", v.global_position, 4.0, 0.7, 0.05, "Efeitos", 30.0)
