extends Node
## Áudio do jogo: canais de mixagem com volumes separados (salvos em user://audio.cfg),
## música em playlists com transição suave, efeitos 2D/3D sorteados entre variações,
## sons de interface automáticos em todos os botões e bipes da largada gerados por código.
## Créditos e licenças dos arquivos: assets/audio/creditos.txt.

const CANAIS := ["Musica", "Efeitos", "Motor", "Ambiente", "Interface"]
const ARQ_VOLUMES := "user://audio.cfg"
const RAIZ := "res://assets/audio/"
const TRANSICAO_S := 2.5
## Playlists: todo arquivo de áudio em assets/audio/musica/<nome>/ (menu, partida, <mapa>, <mapa>/etapaN) entra sozinho.

## Volumes lineares (0–1) por canal; "Master" é o volume geral.
var volumes := {}
var _musica: Array[AudioStreamPlayer] = []
var _atual := 0
var _playlist: Array = []
var _nome_playlist := ""
var _indice := 0
var _variacoes := {}     # "pasta/prefixo_" -> caminhos que começam assim
var _bipes := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_criar_canais()
	_carregar_volumes()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Musica"
		p.volume_db = -80.0
		p.finished.connect(_fim_da_faixa.bind(i))
		add_child(p)
		_musica.append(p)
	_bipes = {"curto": _gerar_bipe(880.0, 0.16), "longo": _gerar_bipe(1320.0, 0.7)}
	get_tree().node_added.connect(_no_adicionado)


# ------------------------------------------------------------------ canais e volumes

func _criar_canais() -> void:
	for nome: String in CANAIS:
		if AudioServer.get_bus_index(nome) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, nome)
		AudioServer.set_bus_send(i, "Master")
	# Limitador no geral: várias explosões e batidas juntas não estouram
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)


func _carregar_volumes() -> void:
	var padrao := {
		"Master": float(Config.valor("audio.volume_geral", 0.9)),
		"Musica": float(Config.valor("audio.volume_musica", 0.5)),
		"Efeitos": float(Config.valor("audio.volume_efeitos", 0.9)),
		"Motor": float(Config.valor("audio.volume_motor", 0.75)),
		"Ambiente": float(Config.valor("audio.volume_ambiente", 0.7)),
		"Interface": float(Config.valor("audio.volume_interface", 0.6)),
	}
	var cfg := ConfigFile.new()
	var salvo := cfg.load(ARQ_VOLUMES) == OK
	for canal: String in padrao:
		volumes[canal] = float(cfg.get_value("volumes", canal, padrao[canal])) if salvo else padrao[canal]
		_aplicar(canal)


func definir_volume(canal: String, valor: float) -> void:
	volumes[canal] = clampf(valor, 0.0, 1.0)
	_aplicar(canal)
	var cfg := ConfigFile.new()
	for c: String in volumes:
		cfg.set_value("volumes", c, volumes[c])
	cfg.save(ARQ_VOLUMES)


## Grade de controles de volume (Configurações do menu e Pausa).
func painel_volumes() -> GridContainer:
	var grade := GridContainer.new()
	grade.columns = 3
	grade.add_theme_constant_override("h_separation", 18)
	grade.add_theme_constant_override("v_separation", 8)
	var nomes := [["Master", "Volume geral"], ["Musica", "Música"], ["Efeitos", "Efeitos"],
		["Motor", "Motor"], ["Ambiente", "Ambiente"], ["Interface", "Interface"]]
	for par: Array in nomes:
		grade.add_child(Estilo.rotulo(par[1], 20))
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = volumes.get(par[0], 1.0)
		s.custom_minimum_size = Vector2(260, 28)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var pct := Estilo.rotulo("%d%%" % roundi(s.value * 100.0), 18, Estilo.TEXTO_FRACO)
		pct.custom_minimum_size.x = 56
		var canal: String = par[0]
		s.value_changed.connect(func(x: float):
			definir_volume(canal, x)
			pct.text = "%d%%" % roundi(x * 100.0))
		grade.add_child(s)
		grade.add_child(pct)
	return grade


var _efeitos_mudos := false


## Tela de carregamento: nenhum efeito (motor, pneus, batidas, ambiente, interface); só a música.
func silenciar_efeitos(sim: bool) -> void:
	_efeitos_mudos = sim
	for canal: String in CANAIS:
		if canal != "Musica":
			_aplicar(canal)


func _aplicar(canal: String) -> void:
	var i := AudioServer.get_bus_index(canal)
	if i < 0:
		return
	var v: float = volumes[canal]
	AudioServer.set_bus_mute(i, v <= 0.001 or (_efeitos_mudos and canal != "Musica" and canal != "Master"))
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


# ------------------------------------------------------------------ música

## Toca a playlist ("menu" ou "partida"). Se ela já estiver tocando, não reinicia.
func musica(nome: String) -> void:
	if nome == _nome_playlist and _musica[_atual].playing:
		return
	_nome_playlist = nome
	_playlist = _faixas_da_pasta(nome)
	if _playlist.is_empty():
		parar_musica()
		return
	if nome != "menu":
		_playlist.shuffle()
	_indice = 0
	_tocar_faixa()


## Música da etapa: musica/<mapa>/etapaN/ → musica/<mapa>/ → musica/partida/ (a primeira que tiver faixa).
## Etapas que caem na mesma pasta seguem a playlist sem reiniciar.
func musica_etapa(mapa: String, etapa: int) -> void:
	for nome: String in ["%s/etapa%d" % [mapa, etapa], mapa]:
		if mapa != "" and not _faixas_da_pasta(nome).is_empty():
			musica(nome)
			return
	musica("partida")


func _faixas_da_pasta(nome: String) -> Array:
	var lista: Array = []
	var pasta := RAIZ + "musica/" + nome
	if not DirAccess.dir_exists_absolute(pasta):
		return lista
	for f in ResourceLoader.list_directory(pasta):
		if f.get_extension() in ["ogg", "mp3", "wav"]:
			lista.append("musica/" + nome + "/" + f)
	lista.sort()
	return lista


func parar_musica(duracao := TRANSICAO_S) -> void:
	_nome_playlist = ""
	for p in _musica:
		_desvanecer(p, -60.0, duracao, true)


func _tocar_faixa() -> void:
	var antigo := _musica[_atual]
	_atual = 1 - _atual
	var novo := _musica[_atual]
	novo.stream = load(RAIZ + _playlist[_indice])
	novo.volume_db = -40.0
	novo.play()
	_desvanecer(novo, 0.0, TRANSICAO_S, false)
	if antigo.playing:
		_desvanecer(antigo, -60.0, TRANSICAO_S, true)


func _fim_da_faixa(qual: int) -> void:
	if qual != _atual or _playlist.is_empty():
		return
	_indice = (_indice + 1) % _playlist.size()
	_tocar_faixa()


func _desvanecer(p: AudioStreamPlayer, db: float, duracao: float, parar: bool) -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(p, "volume_db", db, duracao)
	if parar:
		tw.tween_callback(p.stop)


# ------------------------------------------------------------------ efeitos

## Toca um som uma vez. `nome` é relativo a assets/audio: com extensão toca o arquivo;
## sem extensão (ex.: "efeitos/batida_pesada_") sorteia entre os arquivos com esse começo.
## Com `pos` (Vector3) o som é 3D naquele ponto; sem, é 2D.
func tocar(nome: String, pos: Variant = null, volume_db := 0.0, pitch := 1.0, variacao := 0.06,
		canal := "Efeitos", alcance := 20.0) -> Node:
	var st := stream(nome)
	if st == null:
		return null
	var p: Node
	if pos is Vector3:
		var cena := get_tree().current_scene
		if cena == null:
			return null
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = st
		p3.bus = canal
		p3.volume_db = volume_db
		p3.unit_size = alcance
		p3.max_distance = alcance * 40.0
		p3.pitch_scale = pitch * (1.0 + _rng.randf_range(-variacao, variacao))
		cena.add_child(p3)
		p3.global_position = pos
		p3.play()
		p3.finished.connect(p3.queue_free)
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = st
		p2.bus = canal
		p2.volume_db = volume_db
		p2.pitch_scale = pitch * (1.0 + _rng.randf_range(-variacao, variacao))
		add_child(p2)
		p2.play()
		p2.finished.connect(p2.queue_free)
		p = p2
	return p


func stream(nome: String) -> AudioStream:
	if nome.get_extension() != "":
		return load(RAIZ + nome)
	if not _variacoes.has(nome):
		var lista: Array[String] = []
		var pasta := (RAIZ + nome).get_base_dir()
		var prefixo := nome.get_file()
		for f in ResourceLoader.list_directory(pasta):
			if f.begins_with(prefixo) and f.get_extension() in ["ogg", "wav", "mp3"]:
				lista.append(pasta + "/" + f)
		_variacoes[nome] = lista
	var opcoes: Array = _variacoes[nome]
	if opcoes.is_empty():
		push_warning("Som não encontrado: " + nome)
		return null
	return load(opcoes[_rng.randi() % opcoes.size()])


## Mesmo arquivo, mas repetindo sem fim (motor, vento, pneus, ambiente).
func loop(nome: String) -> AudioStream:
	var st: AudioStream = stream(nome)
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	return st


# ------------------------------------------------------------------ interface e largada

func _no_adicionado(n: Node) -> void:
	if n is BaseButton and not n.has_meta("sem_som"):
		var b := n as BaseButton
		b.pressed.connect(func(): tocar("interface/clique.ogg", null, -3.0, 1.0, 0.03, "Interface"))
		b.mouse_entered.connect(func():
			if not b.disabled:
				tocar("interface/passar.ogg", null, -14.0, 1.0, 0.05, "Interface"))


func interface(nome: String, volume_db := -3.0) -> void:
	tocar("interface/" + nome + ".ogg", null, volume_db, 1.0, 0.0, "Interface")


## Bipe do semáforo: curto nos segundos da contagem, longo na largada.
func bipe(longo := false) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = _bipes["longo" if longo else "curto"]
	p.bus = "Efeitos"
	p.volume_db = -6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Blip de checkpoint: dois tons curtos subindo (gerado uma vez).
var _blip_checkpoint: AudioStreamWAV
func checkpoint() -> void:
	if _blip_checkpoint == null:
		var taxa := 44100
		var dados := PackedByteArray()
		for tom: Vector2 in [Vector2(1175.0, 0.07), Vector2(1760.0, 0.12)]:   # (Hz, duração)
			var n := int(taxa * tom.y)
			var ini := dados.size()
			dados.resize(ini + n * 2)
			for i in n:
				var t := float(i) / taxa
				var env := minf(t / 0.004, 1.0) * minf((tom.y - t) / 0.03, 1.0)
				var s := sin(TAU * tom.x * t) + sin(TAU * tom.x * 2.0 * t) * 0.25
				dados.encode_s16(ini + i * 2, int(clampf(s * env * 0.4, -1.0, 1.0) * 32767.0))
		_blip_checkpoint = AudioStreamWAV.new()
		_blip_checkpoint.format = AudioStreamWAV.FORMAT_16_BITS
		_blip_checkpoint.mix_rate = taxa
		_blip_checkpoint.data = dados
	var p := AudioStreamPlayer.new()
	p.stream = _blip_checkpoint
	p.bus = "Efeitos"
	p.volume_db = -4.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Bipe eletrônico de largada: onda quadrada suavizada com ataque e queda curtos.
func _gerar_bipe(freq: float, duracao: float) -> AudioStreamWAV:
	var taxa := 44100
	var n := int(taxa * duracao)
	var dados := PackedByteArray()
	dados.resize(n * 2)
	for i in n:
		var t := float(i) / taxa
		var env := minf(t / 0.005, 1.0) * minf((duracao - t) / 0.04, 1.0)
		var s := sin(TAU * freq * t) + sin(TAU * freq * 3.0 * t) / 3.0 * 0.6 + sin(TAU * freq * 5.0 * t) / 5.0 * 0.3
		dados.encode_s16(i * 2, int(clampf(s * env * 0.45, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = taxa
	w.data = dados
	return w


## Assobio do turbo: tom agudo com um pouco de chiado, em loop (gerado uma vez).
var _turbo: AudioStreamWAV
func turbo() -> AudioStreamWAV:
	if _turbo:
		return _turbo
	var taxa := 44100
	var n := taxa   # 1 s, frequência inteira: o loop fecha sem estalo
	var dados := PackedByteArray()
	dados.resize(n * 2)
	var ruido := 0.0
	for i in n:
		var t := float(i) / taxa
		ruido = lerpf(ruido, _rng.randf_range(-1.0, 1.0), 0.3)
		var s := sin(TAU * 2400.0 * t) * 0.5 + sin(TAU * 4800.0 * t) * 0.12 + ruido * 0.25
		dados.encode_s16(i * 2, int(s * 0.5 * 32767.0))
	_turbo = AudioStreamWAV.new()
	_turbo.format = AudioStreamWAV.FORMAT_16_BITS
	_turbo.mix_rate = taxa
	_turbo.data = dados
	_turbo.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_turbo.loop_end = n
	return _turbo
