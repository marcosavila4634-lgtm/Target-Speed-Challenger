class_name DragSom
extends Node3D
## Som de um carro no Drag Racing, tirado da simulação (DragMotor): motor pelo giro real e carga,
## corte do limitador, estalo das trocas, turbo, pneus patinando, nitro e vento. O do jogador toca
## "dentro da cabine" (2D); o do rival é 3D, preso ao carro dele.

var m: DragMotor
var _jogador := false
var _motor: Node
var _turbo: Node
var _pneu: Node
var _nitro: Node
var _vento: Node
var _loops: Array[Node] = []
var _limite := 8000.0


func montar(motor: DragMotor, v: Veiculo, jogador: bool) -> void:
	m = motor
	_jogador = jogador
	name = "SomDrag"
	v.add_child(self)
	_limite = float(Config.valor("drag.rpm_limite", 8000))
	var id := str(v.dados.get("id", ""))
	var timbre := int(v.dados.get("som_motor", absi(id.hash()) % SomVeiculo.TIMBRES))
	_motor = _loop(Audio.loop("motor/loop_%d.wav" % timbre), "Motor", 3.0 if jogador else 4.0)
	_turbo = _loop(Audio.turbo(), "Motor", 0.0)
	_pneu = _loop(Audio.loop("efeitos/pneu_loop.wav"), "Efeitos", 0.0)
	_nitro = _loop(Audio.loop("efeitos/nitro_0.ogg"), "Efeitos", 0.0)
	if jogador:
		_vento = _loop(Audio.loop("efeitos/vento_forte.mp3"), "Efeitos", -4.0)
	m.trocou.connect(_ao_trocar)
	m.engatou.connect(func(_x): _estalo(-10.0))
	m.reduziu.connect(func(_a, _b, _e): _estalo(-8.0))
	m.nitro_ligou.connect(func(): _efeito("efeitos/whoosh.wav", -4.0, 1.3))


func _loop(st: AudioStream, canal: String, ganho: float) -> Node:
	var p: Node
	if _jogador:
		p = AudioStreamPlayer.new()
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 14.0
		p3.max_distance = 600.0
		p3.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		p = p3
	p.set("stream", st)
	p.set("bus", canal)
	p.set("volume_db", -80.0)
	p.set_meta("ganho", ganho)
	add_child(p)
	p.call("play", randf() * maxf(st.get_length() - 0.05, 0.0))
	_loops.append(p)
	return p


func _nivel(p: Node, linear: float) -> void:
	var db := linear_to_db(maxf(linear, 0.0001)) + float(p.get_meta("ganho", 0.0))
	p.set("volume_db", lerpf(float(p.get("volume_db")), db, 0.4))


func _efeito(nome: String, db: float, pitch := 1.0) -> void:
	Audio.tocar(nome, null if _jogador else global_position, db, pitch, 0.05, "Efeitos", 14.0)


func _estalo(db: float) -> void:
	_efeito("efeitos/batida_leve_", db, 0.75)


func _ao_trocar(_de: int, _para: int, _av: String) -> void:
	_estalo(-12.0)
	# Alívio do turbo na troca (assobio curto que cai)
	_turbo.set("volume_db", -6.0 + float(_turbo.get_meta("ganho")))


func silenciar() -> void:
	for p in _loops:
		p.call("stop")
	set_process(false)


func _process(_delta: float) -> void:
	if m == null:
		return
	var giro := clampf(m.rpm / _limite, 0.0, 1.05)
	var carga := m.acelerador
	_motor.set("pitch_scale", lerpf(0.5, 2.05, giro))
	var vol := lerpf(0.3, 0.8, giro) * lerpf(0.65, 1.0, carga)
	if m.no_limitador:
		vol *= 0.55 + 0.45 * float(fmod(Time.get_ticks_msec() / 45.0, 2.0) < 1.0)   # corte do limitador
	_nivel(_motor, vol)
	_turbo.set("pitch_scale", lerpf(0.5, 1.2, giro))
	_nivel(_turbo, clampf((giro - 0.45) * 2.0, 0.0, 1.0) * carga * 0.12)
	_nivel(_pneu, 0.6 if m.patinando else 0.0)
	_nivel(_nitro, 0.75 if m.nitro_ativo else 0.0)
	if _vento:
		_nivel(_vento, clampf((m.velocidade - 8.0) / 50.0, 0.0, 1.0) * 0.5)
		_vento.set("pitch_scale", lerpf(0.85, 1.25, clampf(m.velocidade / 60.0, 0.0, 1.0)))
