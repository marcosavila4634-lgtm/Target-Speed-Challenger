extends Control
## Menu principal no estilo das artes do dossiê ("TSC_Menu_Principal"): hangar 3D com o carro na
## plataforma giratória e o piloto escolhido ao lado, menu lateral, logo TSC, placa do veículo, seletor de piloto, cartões de modo de jogo e painel
## de atributos. Recursos online (loja, clãs, passe...) aparecem bloqueados como "EM BREVE".

const BASE := Vector2(1920, 1080)

var _hangar: Hangar
var _veiculos: Array = []
var _indice := 0
var _placa_nome: Label
var _placa_sub: Label
var _atributos: VBoxContainer
var _avatares: Array = []
var _indice_av := 0
var _avatar: Avatar
var _av_nome: Label
var _nome_perfil: Label
var _inicial: Label
var _popup: Control
var _tuning: Tuning
var _abas_garagem: Array[Button] = []
var _nos_inicio: Array[Control] = []   # cartões e painel da tela inicial (somem no tuning)
var _botao_rapida: Button
var _rotulo_etapa: Label   # etapa escolhida para a partida rápida (embaixo do nome do modo)


func _ready() -> void:
	theme = Estilo.tema()
	Audio.musica("menu")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_veiculos = Config.veiculos_ativos()
	for i in _veiculos.size():
		if _veiculos[i].id == Sessao.veiculo_id:
			_indice = i
	_avatares = Config.avatares_ativos()
	for i in _avatares.size():
		if _avatares[i].id == Sessao.avatar_id:
			_indice_av = i
	_montar_hangar()
	_montar_sombras()
	_montar_topo()
	_montar_menu_lateral()
	_montar_placa_e_setas()
	_montar_cartoes()
	_montar_painel_direito()
	_montar_seletor_piloto()
	_selecionar(_indice)
	_selecionar_avatar(_indice_av)
	if OS.get_environment("TSC_FOTO_MENU") != "":
		if OS.get_environment("TSC_FOTO_CONFIG") != "":
			_abrir_configuracao()   # conferência: foto da janela de configuração
		if OS.get_environment("TSC_FOTO_TUNING") != "":
			_abrir_tuning()
			if OS.get_environment("TSC_FOTO_TUNING") == "drag":
				_tuning._abas.drag.emit_signal("pressed")
				_tuning._abas.drag.button_pressed = true
		await get_tree().create_timer(3.0).timeout
		get_viewport().get_texture().get_image().save_png(OS.get_environment("TSC_FOTO_MENU"))
		get_tree().quit()
	elif Sessao.teste_automatico:
		_jogar.call_deferred()


func _unhandled_input(evento: InputEvent) -> void:
	if _popup:
		if evento.is_action_pressed("ui_cancel"):
			_fechar_popup()
		return
	if _tuning_aberto() and evento.is_action_pressed("ui_cancel"):
		_fechar_tuning()
	elif evento.is_action_pressed("ui_accept"):
		_jogar()
	elif evento.is_action_pressed("ui_left"):
		_selecionar(_indice - 1)
	elif evento.is_action_pressed("ui_right"):
		_selecionar(_indice + 1)


# ------------------------------------------------------------------ utilidades de layout

## Posiciona `no` em coordenadas da tela de referência 1920x1080, preso ao canto `ancora` (0..1).
func _colocar(no: Control, ancora: Vector2, pos: Vector2, tamanho: Vector2) -> void:
	no.anchor_left = ancora.x
	no.anchor_right = ancora.x
	no.anchor_top = ancora.y
	no.anchor_bottom = ancora.y
	var desloc := pos - ancora * BASE
	no.offset_left = desloc.x
	no.offset_top = desloc.y
	no.offset_right = desloc.x + tamanho.x
	no.offset_bottom = desloc.y + tamanho.y


func _titulo(texto: String, tamanho: int, cor := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", Estilo.fonte_titulo(800))
	l.add_theme_font_size_override("font_size", tamanho)
	l.add_theme_color_override("font_color", cor)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _botao_vazio(normal: StyleBox, hover: StyleBox) -> Button:
	var b := Button.new()
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("disabled", normal)
	b.focus_mode = Control.FOCUS_NONE
	return b


func _linha(filhos: Array, separacao := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separacao)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for f in filhos:
		h.add_child(f)
	return h


func _preencher(no: Control) -> Control:
	no.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	no.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return no


# ------------------------------------------------------------------ cenário

func _montar_hangar() -> void:
	var cont := SubViewportContainer.new()
	cont.stretch = true
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(cont)
	var vp := SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_4X
	vp.own_world_3d = true
	cont.add_child(vp)
	_hangar = Hangar.new()
	vp.add_child(_hangar)


func _montar_sombras() -> void:
	# Escurece a esquerda (menu) e a base (cartões) para o texto ficar legível
	for dados: Array in [[Vector2(0, 0.5), Vector2(0.42, 0.5), 0.85], [Vector2(0.5, 1.0), Vector2(0.5, 0.55), 0.8]]:
		var g := Gradient.new()
		g.set_color(0, Color(0.0, 0.02, 0.06, dados[2]))
		g.set_color(1, Color(0.0, 0.02, 0.06, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill_from = dados[0]
		tex.fill_to = dados[1]
		var r := TextureRect.new()
		r.texture = tex
		r.stretch_mode = TextureRect.STRETCH_SCALE
		add_child(_preencher(r))


func _material_logo() -> ShaderMaterial:
	# Arte em fundo preto: alfa = brilho do pixel, mistura pré-multiplicada (preto some, metal fica sólido)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = "shader_type canvas_item;\nrender_mode blend_premul_alpha;\nvoid fragment() {\n\tvec4 c = texture(TEXTURE, UV);\n\tfloat a = clamp(max(c.r, max(c.g, c.b)) * 2.02, 0.0, 1.0);\n\tCOLOR = vec4(c.rgb, a);\n}"
	return m


# ------------------------------------------------------------------ topo

func _montar_topo() -> void:
	# Cartão do piloto (canto superior esquerdo)
	var perfil := _botao_vazio(Estilo.caixa_neon(Estilo.PAINEL_ESCURO, Color(0.3, 0.55, 1.0, 0.6), 0.0, 12, -0.25),
		Estilo.caixa_neon(Color(0.05, 0.12, 0.26, 0.92), Estilo.AZUL_NEON, 0.6, 12, -0.25))
	_colocar(perfil, Vector2(0, 0), Vector2(34, 26), Vector2(420, 92))
	perfil.pressed.connect(_abrir_perfil)
	add_child(perfil)
	var emblema := Panel.new()
	emblema.add_theme_stylebox_override("panel", Estilo.caixa_neon(Color(0.04, 0.08, 0.16), Estilo.AZUL_NEON, 0.5, 6))
	emblema.custom_minimum_size = Vector2(62, 62)
	emblema.position = Vector2(14, 15)
	emblema.size = Vector2(62, 62)
	emblema.mouse_filter = Control.MOUSE_FILTER_IGNORE
	perfil.add_child(emblema)
	_inicial = _titulo("K", 40)
	_inicial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inicial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblema.add_child(_preencher(_inicial))
	var info := VBoxContainer.new()
	info.position = Vector2(96, 12)
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	perfil.add_child(info)
	_nome_perfil = Estilo.rotulo("", 30, Color.WHITE, 700)
	info.add_child(_nome_perfil)
	info.add_child(Estilo.rotulo("PILOTO  •  MODO OFFLINE", 17, Estilo.TEXTO_FRACO, 600))
	var barra := Estilo.barra_segmentos(2, 12, Estilo.AZUL_NEON, 260)
	info.add_child(barra)
	_atualizar_perfil()

	# Logo TSC no centro
	var logo := TextureRect.new()
	logo.texture = load("res://assets/ui/logo_tsc.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.material = _material_logo()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_colocar(logo, Vector2(0.5, 0), Vector2(960 - 270, 14), Vector2(540, 198))
	add_child(logo)

	# Selo KZULO STUDIOS e estado da conexão (canto superior direito)
	var chips := _linha([], 10)
	_colocar(chips, Vector2(1, 0), Vector2(1920 - 560, 30), Vector2(526, 52))
	chips.alignment = BoxContainer.ALIGNMENT_END
	add_child(chips)
	var estado := PanelContainer.new()
	estado.add_theme_stylebox_override("panel", Estilo.caixa_neon(Estilo.PAINEL_ESCURO, Color(0.3, 0.55, 1.0, 0.6), 0.0, 10, -0.25))
	estado.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ponto := Estilo.rotulo("●", 18, Color(1.0, 0.7, 0.2))
	estado.add_child(_linha([ponto, Estilo.rotulo("OFFLINE  —  CONTRA BOTS", 19, Estilo.TEXTO, 600)], 8))
	chips.add_child(estado)
	var kz := TextureRect.new()
	kz.texture = load("res://assets/ui/logo_kzulo.png")
	kz.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kz.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	kz.custom_minimum_size = Vector2(150, 52)
	kz.material = _material_logo()
	kz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_child(kz)


func _atualizar_perfil() -> void:
	_nome_perfil.text = Sessao.nome_jogador.to_upper()
	_inicial.text = Sessao.nome_jogador.left(1).to_upper()


# ------------------------------------------------------------------ menu lateral

func _montar_menu_lateral() -> void:
	var lista := VBoxContainer.new()
	lista.add_theme_constant_override("separation", 0)
	_colocar(lista, Vector2(0, 0), Vector2(26, 168), Vector2(400, 700))
	add_child(lista)
	_montar_abas_garagem(lista)
	var itens := [
		["carrinho", "MARKETPLACE", "breve", Callable()],
		["loja", "LOJA", "breve", Callable()],
		["perfil", "PERFIL", "", _abrir_perfil],
		["cla", "CLÃS", "breve", Callable()],
		["passe", "PASSE", "breve", Callable()],
		["noticias", "NOTÍCIAS E EVENTOS", "breve", Callable()],
		["config", "CONFIGURAÇÕES", "", _abrir_configuracao],
		["sair", "SAIR", "", func(): get_tree().quit()],
	]
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.05, 0.1, 0.55)
	normal.border_color = Color(0.3, 0.45, 0.7, 0.25)
	normal.border_width_bottom = 1
	normal.content_margin_left = 18
	var hover := Estilo.caixa_gradiente(Color(0.1, 0.25, 0.55, 0.85), Color(0.05, 0.12, 0.3, 0.0))
	var ativo := Estilo.caixa_neon(Color(0.07, 0.2, 0.5, 0.95), Estilo.AZUL_NEON, 1.0, 8, -0.3)
	for it: Array in itens:
		var bloqueado: bool = it[2] == "breve"
		var sel: bool = it[2] == "ativo"
		var b := _botao_vazio(ativo if sel else normal, ativo if sel else (normal if bloqueado else hover))
		b.custom_minimum_size = Vector2(420 if sel else 400, 70 if sel else 64)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if bloqueado:
			b.tooltip_text = "Em breve"
			b.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
		else:
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			if (it[3] as Callable).is_valid():
				b.pressed.connect(it[3])
		var cor := Color.WHITE if sel else (Color(0.55, 0.6, 0.7) if bloqueado else Estilo.TEXTO)
		var conteudo := _linha([], 18)
		var ic := Estilo.icone(it[0], 28, cor)
		ic.custom_minimum_size = Vector2(40, 0)
		conteudo.add_child(ic)
		conteudo.add_child(Estilo.rotulo(it[1], 26 if sel else 23, cor, 700 if sel else 600))
		if bloqueado:
			conteudo.add_child(Estilo.rotulo("—  EM BREVE", 16, Color(0.5, 0.55, 0.65), 500))
			conteudo.add_child(Estilo.icone("cadeado", 18, Color(0.55, 0.6, 0.7)))
		b.add_child(conteudo)
		conteudo.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_MINSIZE, 22)
		conteudo.offset_top = 0
		conteudo.offset_bottom = 0
		lista.add_child(b)


## Primeiro item do menu dividido em dois: GARAGEM (escolher o carro) e TUNING (upgrades).
## A aba ativa fica acesa.
func _montar_abas_garagem(lista: VBoxContainer) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lista.add_child(h)
	for aba: Array in [["garagem", "GARAGEM", _fechar_tuning, 236], ["tuning", "TUNING", _abrir_tuning, 178]]:
		var b := _botao_vazio(StyleBoxEmpty.new(), StyleBoxEmpty.new())
		b.custom_minimum_size = Vector2(aba[3], 70)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(aba[2])
		var conteudo := _linha([], 14)
		var ic := Estilo.icone(aba[0], 28)
		ic.custom_minimum_size = Vector2(34, 0)
		conteudo.add_child(ic)
		conteudo.add_child(Estilo.rotulo(aba[1], 25, Estilo.TEXTO, 700))
		b.add_child(conteudo)
		conteudo.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE, Control.PRESET_MODE_MINSIZE, 22)
		conteudo.offset_top = 0
		conteudo.offset_bottom = 0
		h.add_child(b)
		_abas_garagem.append(b)
	_marcar_aba_garagem()


func _marcar_aba_garagem() -> void:
	var ativo := Estilo.caixa_neon(Color(0.07, 0.2, 0.5, 0.95), Estilo.AZUL_NEON, 1.0, 8, -0.3)
	var inativo := Estilo.caixa_neon(Color(0.02, 0.05, 0.1, 0.7), Color(0.3, 0.45, 0.7, 0.45), 0.0, 8, -0.3)
	var hover := Estilo.caixa_neon(Color(0.05, 0.14, 0.34, 0.9), Estilo.AZUL_NEON, 0.4, 8, -0.3)
	var tuning := _tuning_aberto()
	for i in _abas_garagem.size():
		var b: Button = _abas_garagem[i]
		var sel := (i == 1) == tuning
		for estado in ["normal", "disabled"]:
			b.add_theme_stylebox_override(estado, ativo if sel else inativo)
		for estado in ["hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(estado, ativo if sel else hover)
		var conteudo := b.get_child(0)
		for l: Label in conteudo.get_children():
			l.add_theme_color_override("font_color", Color.WHITE if sel else Estilo.TEXTO_FRACO)


# ------------------------------------------------------------------ placa do carro e setas

func _montar_placa_e_setas() -> void:
	var placa := PanelContainer.new()
	placa.add_theme_stylebox_override("panel", Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.82), Color(0.3, 0.55, 1.0, 0.5), 0.0, 4, -0.25))
	placa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_colocar(placa, Vector2(1, 0), Vector2(1370, 290), Vector2(500, 124))
	add_child(placa)
	var faixa := ColorRect.new()
	faixa.color = Estilo.AZUL_NEON
	faixa.custom_minimum_size = Vector2(8, 0)
	faixa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var textos := VBoxContainer.new()
	textos.add_theme_constant_override("separation", 0)
	textos.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placa_nome = _titulo("", 46)
	_placa_sub = Estilo.rotulo("", 18, Estilo.TEXTO_FRACO, 600)
	textos.add_child(_placa_nome)
	textos.add_child(_placa_sub)
	placa.add_child(_linha([faixa, textos], 16))

	# Setas para trocar de veículo, abaixo da plataforma
	for lado: int in [-1, 1]:
		var b := _botao_vazio(Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.7), Color(0.3, 0.55, 1.0, 0.6), 0.0, 24),
			Estilo.caixa_neon(Color(0.07, 0.2, 0.5, 0.95), Estilo.AZUL_NEON, 0.9, 24))
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var ic := Estilo.icone("esquerda" if lado < 0 else "direita", 26, Color.WHITE)
		b.add_child(_preencher(ic))
		_colocar(b, Vector2(0.5, 1), Vector2(1060 + lado * 470 - 26, 560), Vector2(52, 52))
		b.pressed.connect(func(): _selecionar(_indice + lado))
		add_child(b)


# ------------------------------------------------------------------ piloto

## Placa "‹ PILOTO: NOME ›" logo acima da placa do carro; o piloto fica em pé à direita da plataforma.
func _montar_seletor_piloto() -> void:
	if _avatares.is_empty():
		return
	var placa := PanelContainer.new()
	placa.add_theme_stylebox_override("panel", Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.82), Color(0.3, 0.55, 1.0, 0.5), 0.0, 4, -0.25))
	_colocar(placa, Vector2(1, 0), Vector2(1470, 226), Vector2(400, 52))
	add_child(placa)
	var linha := _linha([], 8)
	placa.add_child(linha)
	for lado: int in [-1, 1]:
		var b := _botao_vazio(StyleBoxEmpty.new(), Estilo.caixa_neon(Color(0.07, 0.2, 0.5, 0.95), Estilo.AZUL_NEON, 0.9, 6))
		b.custom_minimum_size = Vector2(40, 40)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_child(_preencher(Estilo.icone("esquerda" if lado < 0 else "direita", 20, Color.WHITE)))
		b.pressed.connect(func(): _selecionar_avatar(_indice_av + lado))
		if lado < 0:
			linha.add_child(b)
			var rot := Estilo.rotulo("PILOTO", 17, Estilo.TEXTO_FRACO, 600)
			linha.add_child(rot)
			_av_nome = Estilo.rotulo("", 22, Estilo.TEXTO, 700)
			_av_nome.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_av_nome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			linha.add_child(_av_nome)
		else:
			linha.add_child(b)


func _selecionar_avatar(indice: int) -> void:
	if _avatares.is_empty():
		return
	_indice_av = wrapi(indice, 0, _avatares.size())
	var d: Dictionary = _avatares[_indice_av]
	Sessao.avatar_id = d.id
	_av_nome.text = str(d.nome).to_upper()
	if _avatar:
		_avatar.queue_free()
	_avatar = Avatar.criar(d)
	_hangar.add_child(_avatar)
	# Em cima do tampo da plataforma (dentro do raio dela; no chão os pés ficavam enterrados no disco)
	_avatar.position = Vector3(3.75, _hangar.suporte_carro.position.y, 0.2)
	# Virado para a câmera, levemente voltado para o carro
	var para_cam := _hangar.camera.global_position - _avatar.global_position
	_avatar.rotation.y = atan2(-para_cam.x, -para_cam.z) + deg_to_rad(-15.0)
	_avatar.em_pe()


# ------------------------------------------------------------------ cartões de modo

func _montar_cartoes() -> void:
	var y := 785.0   # rente à borda de baixo: não cobrir o carro
	# JOGAR TARGET FLIGHT
	var jogar := _botao_vazio(Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.9), Estilo.AZUL_NEON, 0.7, 10),
		Estilo.caixa_neon(Color(0.04, 0.1, 0.24, 0.95), Color(0.6, 0.8, 1.0), 1.3, 10))
	jogar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_colocar(jogar, Vector2(0.5, 1), Vector2(440, y), Vector2(560, 206))
	jogar.pressed.connect(_jogar)
	_nos_inicio.append(jogar)
	add_child(jogar)
	# Foto do mapa escolhido (muda junto com o mapa)
	var img := TextureRect.new()
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.position = Vector2(4, 4)
	img.size = Vector2(552, 128)
	jogar.add_child(img)
	var rodape := _linha([Estilo.icone("play", 34, Color.WHITE), _titulo("JOGAR TARGET FLIGHT", 36)], 18)
	rodape.position = Vector2(30, 138)
	jogar.add_child(rodape)
	# Mapa: nome grande direto sobre a foto (sem caixa), letra de corrida, e setas grandes dos lados
	var nome_mapa := Label.new()
	nome_mapa.add_theme_font_override("font", load("res://assets/fontes/RacingSansOne-Regular.ttf"))
	nome_mapa.add_theme_font_size_override("font_size", 48)
	nome_mapa.add_theme_color_override("font_color", Color.WHITE)
	nome_mapa.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	nome_mapa.add_theme_constant_override("outline_size", 12)
	nome_mapa.add_theme_color_override("font_shadow_color", Color(1.0, 0.45, 0.1, 0.6))
	nome_mapa.add_theme_constant_override("shadow_offset_x", 0)
	nome_mapa.add_theme_constant_override("shadow_offset_y", 4)
	nome_mapa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nome_mapa.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nome_mapa.position = Vector2(64, 4)
	nome_mapa.size = Vector2(432, 128)
	nome_mapa.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jogar.add_child(nome_mapa)
	var mostrar_mapa := func():
		nome_mapa.text = Config.nome_mapa().to_upper()
		# Nome comprido encolhe até caber entre as setas
		var fonte: Font = nome_mapa.get_theme_font("font")
		var tam := 48
		while tam > 22 and fonte.get_string_size(nome_mapa.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tam).x > nome_mapa.size.x - 16.0:
			tam -= 2
		nome_mapa.add_theme_font_size_override("font_size", tam)
		var caminho_img := str(Config.mapa_atual().get("imagem", "res://assets/ui/cartao_target_flight.jpg"))
		if ResourceLoader.exists(caminho_img):
			img.texture = load(caminho_img)
		else:
			# Foto nova ainda não importada pelo editor: lê o arquivo direto
			var foto := Image.load_from_file(ProjectSettings.globalize_path(caminho_img)) if FileAccess.file_exists(caminho_img) else null
			img.texture = ImageTexture.create_from_image(foto) if foto else load("res://assets/ui/cartao_target_flight.jpg")
	mostrar_mapa.call()
	var trocar_mapa := func(passo: int):
		var lista := Config.mapas()
		var i := lista.find(Config.mapa_atual())
		Sessao.escolher_mapa(str(lista[posmod(i + passo, lista.size())].get("id", "")))
		Sessao.salvar()
		Audio.interface("confirmar", -6.0)
		mostrar_mapa.call()
		_atualizar_etapa_rapida()   # outro mapa, outras etapas
	for lado: int in [-1, 1]:
		var seta := _botao_vazio(StyleBoxEmpty.new(), StyleBoxEmpty.new())
		seta.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		seta.tooltip_text = "Mapa anterior" if lado < 0 else "Próximo mapa"
		seta.position = Vector2(4 if lado < 0 else 492, 4)
		seta.size = Vector2(64, 128)
		var icone := Estilo.icone("esquerda" if lado < 0 else "direita", 72, Color.WHITE)
		icone.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		icone.add_theme_constant_override("outline_size", 10)
		icone.set_anchors_preset(Control.PRESET_FULL_RECT)
		seta.add_child(icone)
		seta.mouse_entered.connect(func(): icone.add_theme_color_override("font_color", Color(1.0, 0.72, 0.3)))
		seta.mouse_exited.connect(func(): icone.add_theme_color_override("font_color", Color.WHITE))
		seta.pressed.connect(trocar_mapa.bind(lado))
		jogar.add_child(seta)

	# JOGAR DRAG RACING — offline contra bot (1/8 de milha na pista escolhida)
	var drag := _botao_vazio(Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.9), Estilo.AZUL_NEON, 0.7, 10),
		Estilo.caixa_neon(Color(0.04, 0.1, 0.24, 0.95), Color(0.6, 0.8, 1.0), 1.3, 10))
	drag.tooltip_text = "Arrancada de 1/8 de milha contra bot"
	drag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_colocar(drag, Vector2(0.5, 1), Vector2(1016, y), Vector2(470, 206))
	drag.pressed.connect(_jogar_drag)
	add_child(drag)
	_nos_inicio.append(drag)
	var img2 := TextureRect.new()
	var foto_pista := func() -> Texture2D:   # foto da pista escolhida (ou a arte antiga)
		var f := DragHud.fotos_pista(Sessao.drag_fotos_id(), "arrancada")
		return f[0] if not f.is_empty() else load("res://assets/ui/cartao_drag_racing.jpg")
	img2.texture = foto_pista.call()
	img2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img2.position = Vector2(4, 4)
	img2.size = Vector2(462, 128)
	drag.add_child(img2)
	var rod2 := _linha([Estilo.icone("play", 30, Color.WHITE), _titulo("JOGAR DRAG RACING", 30)], 16)
	rod2.position = Vector2(30, 142)
	drag.add_child(rod2)
	# Pista do Drag: nome sobre a foto e setas dos lados (TSC Dragway, Reta do Canyon...)
	var nome_pista := Label.new()
	nome_pista.add_theme_font_override("font", load("res://assets/fontes/RacingSansOne-Regular.ttf"))
	nome_pista.add_theme_font_size_override("font_size", 42)
	nome_pista.add_theme_color_override("font_color", Color.WHITE)
	nome_pista.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	nome_pista.add_theme_constant_override("outline_size", 12)
	nome_pista.add_theme_color_override("font_shadow_color", Color(0.2, 0.5, 1.0, 0.6))
	nome_pista.add_theme_constant_override("shadow_offset_x", 0)
	nome_pista.add_theme_constant_override("shadow_offset_y", 4)
	nome_pista.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nome_pista.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nome_pista.position = Vector2(64, 4)
	nome_pista.size = Vector2(342, 128)
	nome_pista.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nome_pista.text = str(Sessao.drag_pista().get("nome", "")).to_upper()
	drag.add_child(nome_pista)
	var trocar_pista := func(passo: int):
		var lista: Array = Config.valor("drag.pistas", [])
		if lista.is_empty():
			return
		var i := lista.find(Sessao.drag_pista())
		Sessao.drag_pista_id = str(lista[posmod(i + passo, lista.size())].get("id", ""))
		Sessao.salvar()
		Audio.interface("confirmar", -6.0)
		nome_pista.text = str(Sessao.drag_pista().get("nome", "")).to_upper()
		img2.texture = foto_pista.call()
	for lado: int in [-1, 1]:
		var seta := _botao_vazio(StyleBoxEmpty.new(), StyleBoxEmpty.new())
		seta.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		seta.tooltip_text = "Pista anterior" if lado < 0 else "Próxima pista"
		seta.position = Vector2(4 if lado < 0 else 402, 4)
		seta.size = Vector2(64, 128)
		var icone := Estilo.icone("esquerda" if lado < 0 else "direita", 64, Color.WHITE)
		icone.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
		icone.add_theme_constant_override("outline_size", 10)
		icone.set_anchors_preset(Control.PRESET_FULL_RECT)
		seta.add_child(icone)
		seta.mouse_entered.connect(func(): icone.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0)))
		seta.mouse_exited.connect(func(): icone.add_theme_color_override("font_color", Color.WHITE))
		seta.pressed.connect(trocar_pista.bind(lado))
		drag.add_child(seta)

	# Modos
	var modos := _linha([], 10)
	_colocar(modos, Vector2(0.5, 1), Vector2(440, y + 222), Vector2(1046, 50))
	add_child(modos)
	_nos_inicio.append(modos)
	var grupo := ButtonGroup.new()
	for m: Array in [["PARTIDA RÁPIDA", false], ["CASUAL", true], ["RANQUEADA", true], ["PRIVADA", true], ["CONTRA BOTS", false]]:
		var b := _botao_vazio(Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.85), Color(0.3, 0.45, 0.7, 0.5), 0.0, 6),
			Estilo.caixa_neon(Color(0.05, 0.16, 0.4, 0.95), Estilo.AZUL_NEON, 0.8, 6))
		b.add_theme_stylebox_override("pressed", Estilo.caixa_neon(Color(0.05, 0.16, 0.4, 0.95), Estilo.AZUL_NEON, 0.8, 6))
		b.toggle_mode = true
		b.button_group = grupo
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cor := Color(0.55, 0.6, 0.68) if m[1] else Color.WHITE
		var conteudo := _linha([], 8)
		conteudo.alignment = BoxContainer.ALIGNMENT_CENTER
		if m[1]:
			conteudo.add_child(Estilo.icone("cadeado", 16, cor))
			b.disabled = true
			b.tooltip_text = "Em breve (online)"
		if m[0] == "PARTIDA RÁPIDA":
			# Nome do modo e, embaixo, a etapa escolhida (a partida rápida joga só ela)
			var textos := VBoxContainer.new()
			textos.alignment = BoxContainer.ALIGNMENT_CENTER
			textos.add_theme_constant_override("separation", -4)
			textos.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var titulo := Estilo.rotulo(m[0], 17, cor, 600)
			titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			textos.add_child(titulo)
			_rotulo_etapa = Estilo.rotulo("", 13, Color(1.0, 0.72, 0.3), 600)
			_rotulo_etapa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			textos.add_child(_rotulo_etapa)
			conteudo.add_child(textos)
			_botao_rapida = b
			_atualizar_etapa_rapida()
			b.button_pressed = Sessao.modo_jogo == "rapida"
			b.pressed.connect(_escolher_etapa)
		else:
			conteudo.add_child(Estilo.rotulo(m[0], 18, cor, 600))
		b.add_child(_preencher(conteudo))
		if m[0] == "CONTRA BOTS":
			b.button_pressed = Sessao.modo_jogo != "rapida"
			b.pressed.connect(func():
				Sessao.modo_jogo = "bots"
				Sessao.salvar())
		modos.add_child(b)


# ------------------------------------------------------------------ painel de atributos (direita)

func _montar_painel_direito() -> void:
	var painel := PanelContainer.new()
	painel.add_theme_stylebox_override("panel", Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.88), Estilo.AZUL_NEON, 0.6, 12))
	_colocar(painel, Vector2(1, 1), Vector2(1516, 757), Vector2(376, 272))
	add_child(painel)
	_nos_inicio.append(painel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	painel.add_child(v)
	_atributos = VBoxContainer.new()
	_atributos.add_theme_constant_override("separation", 6)
	v.add_child(_atributos)
	v.add_child(HSeparator.new())
	var cfg := _botao_vazio(StyleBoxEmpty.new(), Estilo.caixa_gradiente(Color(0.1, 0.25, 0.55, 0.7), Color(0.05, 0.12, 0.3, 0.0)))
	cfg.custom_minimum_size.y = 40
	cfg.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var linha_cfg := _linha([Estilo.icone("config", 22), Estilo.rotulo("CONFIGURAÇÃO TARGET FLIGHT", 19, Estilo.TEXTO, 600)], 12)
	var seta := Estilo.icone("direita", 18)
	seta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	linha_cfg.add_child(seta)
	cfg.add_child(_preencher(linha_cfg))
	cfg.pressed.connect(_abrir_configuracao)
	v.add_child(cfg)
	var botoes := _linha([], 10)
	for b_dados: Array in [["perfil", "PERFIL", _abrir_perfil]]:   # créditos ficam dentro de Configurações
		var b := _botao_vazio(Estilo.caixa_neon(Color(0.03, 0.08, 0.18, 0.9), Estilo.AZUL_NEON, 0.3, 8),
			Estilo.caixa_neon(Color(0.07, 0.2, 0.5, 0.95), Estilo.AZUL_NEON, 0.9, 8))
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var c := _linha([Estilo.icone(b_dados[0], 20), Estilo.rotulo(b_dados[1], 19, Estilo.TEXTO, 600)], 10)
		c.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(_preencher(c))
		b.pressed.connect(b_dados[2])
		botoes.add_child(b)
	v.add_child(botoes)


func _preencher_atributos(d: Dictionary) -> void:
	for f in _atributos.get_children():
		f.queue_free()
	# Notas calculadas dos valores reais, com os upgrades instalados (sobem conforme o tuning)
	for b in Progresso.barras(Progresso.dados_jogador(d.id)):
		var n := Estilo.rotulo(b.nome, 17, Estilo.TEXTO, 600)
		n.custom_minimum_size.x = 118
		var valor: int = b.nota
		var num := Estilo.rotulo("%d/5" % valor, 17, Estilo.TEXTO_FRACO, 600)
		# Peso é ao contrário (menos é melhor): barra em âmbar para não confundir com as outras
		var cor := Color(1.0, 0.62, 0.2) if b.inverso else Estilo.AZUL_NEON
		_atributos.add_child(_linha([n, Estilo.barra_segmentos(valor, 5, cor, 170), num], 10))


# ------------------------------------------------------------------ seleção e ações

func _selecionar(indice: int) -> void:
	if _veiculos.is_empty():
		return
	_indice = wrapi(indice, 0, _veiculos.size())
	var d: Dictionary = _veiculos[_indice]
	Sessao.veiculo_id = d.id
	_placa_nome.text = str(d.nome).to_upper()
	# Nomes longos: a fonte encolhe para caber na placa
	_placa_nome.add_theme_font_size_override("font_size", clampi(int(46.0 * 17.0 / maxf(_placa_nome.text.length(), 17.0)), 30, 46))
	var tracao := {"4x4": "TRAÇÃO 4X4", "dianteira": "TRAÇÃO DIANTEIRA", "traseira": "TRAÇÃO TRASEIRA"}
	_placa_sub.text = "%s  —  %d KG  —  %d KM/H\nVEÍCULO %d DE %d  —  NÍVEL %d" % [tracao.get(d.get("tracao", "4x4"), ""), int(Progresso.dados_jogador(d.id).get("massa", 0)), int(Progresso.dados_jogador(d.id).get("velocidade_max_kmh", 0)), _indice + 1, _veiculos.size(), Progresso.nivel(d.id)]
	_preencher_atributos(d)
	if _tuning_aberto():
		_tuning.mostrar(d.id)
	# Carro na plataforma giratória
	for f in _hangar.suporte_carro.get_children():
		f.queue_free()
	var modelo: Node3D = (load(d.modelo) as PackedScene).instantiate()
	modelo.scale = Vector3.ONE * float(d.get("escala", 1.0))
	_hangar.suporte_carro.add_child(modelo)
	Placa.aplicar(modelo)
	Placa.aplicar_extras(modelo, d.get("placas", []), float(d.get("escala", 1.0)))
	# Centraliza pela caixa no espaço do suporte (que está girando), com os pneus no piso
	var inv := _hangar.suporte_carro.global_transform.affine_inverse()
	var total := AABB()
	var primeiro := true
	for mi: MeshInstance3D in modelo.find_children("*", "MeshInstance3D", true, false):
		var a := (inv * mi.global_transform) * mi.get_aabb()
		total = a if primeiro else total.merge(a)
		primeiro = false
	var c := total.get_center()
	modelo.position -= Vector3(c.x, total.position.y, c.z)


func _abrir_tuning() -> void:
	_fechar_popup()
	if _tuning == null:
		_tuning = Tuning.new()
		_colocar(_tuning, Vector2(0.5, 1), Vector2(440, 605), Vector2(1452, 450))
		_tuning.fechar.connect(_fechar_tuning)
		add_child(_tuning)
	for n in _nos_inicio:
		n.visible = false
	_tuning.visible = true
	_tuning.mostrar(Sessao.veiculo_id)
	_marcar_aba_garagem()


func _fechar_tuning() -> void:
	if _tuning:
		_tuning.visible = false
	for n in _nos_inicio:
		n.visible = true
	_marcar_aba_garagem()
	if not _veiculos.is_empty():
		_preencher_atributos(_veiculos[_indice])   # barras com os upgrades novos


func _tuning_aberto() -> bool:
	return _tuning != null and _tuning.visible


func _jogar() -> void:
	Sessao.salvar()
	get_tree().change_scene_to_file("res://cenas/partida.tscn")


## Etapa da partida rápida no botão do modo (com o nome dela na dica).
func _atualizar_etapa_rapida() -> void:
	if _rotulo_etapa == null:
		return
	var etapas := Sessao.etapas_do_mapa()
	if etapas.is_empty():
		_rotulo_etapa.text = ""
		return
	var i := clampi(Sessao.etapa_rapida, 0, etapas.size() - 1)
	_rotulo_etapa.text = "ETAPA %d/%d" % [i + 1, etapas.size()]
	_botao_rapida.tooltip_text = "Joga só a etapa escolhida: %s (clique para trocar)" % str(etapas[i].get("nome", ""))


## Partida rápida: janela para escolher a etapa do mapa atual; a partida joga só ela.
func _escolher_etapa() -> void:
	Sessao.modo_jogo = "rapida"
	Sessao.salvar()
	var etapas := Sessao.etapas_do_mapa()
	if etapas.is_empty():
		return
	Sessao.etapa_rapida = clampi(Sessao.etapa_rapida, 0, etapas.size() - 1)
	var v := _janela("PARTIDA RÁPIDA", 640)
	v.add_child(Estilo.rotulo("Escolha a etapa de " + Config.nome_mapa() + " — a partida joga só ela.", 19, Estilo.TEXTO_FRACO))
	var grupo := ButtonGroup.new()
	for i in etapas.size():
		var b := Button.new()
		b.text = "ETAPA %d  —  %s" % [i + 1, str(etapas[i].get("nome", "")).to_upper()]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 52
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_stylebox_override("normal", Estilo.caixa_neon(Color(0.03, 0.08, 0.18, 0.9), Estilo.AZUL_NEON, 0.3, 8))
		b.add_theme_stylebox_override("hover", Estilo.caixa_neon(Color(0.07, 0.2, 0.5, 0.95), Estilo.AZUL_NEON, 0.9, 8))
		b.add_theme_stylebox_override("pressed", Estilo.caixa_neon(Color(0.1, 0.26, 0.6, 1.0), Color(1.0, 0.72, 0.3), 1.0, 8))
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.toggle_mode = true
		b.button_group = grupo
		b.button_pressed = i == Sessao.etapa_rapida
		b.pressed.connect(func():
			Sessao.etapa_rapida = i
			Sessao.salvar()
			_atualizar_etapa_rapida()
			Audio.interface("confirmar", -6.0))
		v.add_child(b)
	var jogar := Button.new()
	jogar.text = "JOGAR ETAPA"
	jogar.custom_minimum_size.y = 56
	jogar.add_theme_font_size_override("font_size", 22)
	jogar.add_theme_stylebox_override("normal", Estilo.caixa_neon(Color(0.35, 0.2, 0.02, 0.95), Color(1.0, 0.72, 0.3), 0.8, 8))
	jogar.add_theme_stylebox_override("hover", Estilo.caixa_neon(Color(0.55, 0.32, 0.04, 1.0), Color.WHITE, 1.0, 8))
	jogar.pressed.connect(_jogar)
	v.add_child(jogar)
	_botao_fechar(v)


func _jogar_drag() -> void:
	Sessao.salvar()
	get_tree().change_scene_to_file("res://cenas/drag.tscn")


# ------------------------------------------------------------------ janelas

func _janela(titulo: String, largura := 720.0) -> VBoxContainer:
	_fechar_popup()
	var fundo := ColorRect.new()
	fundo.color = Color(0, 0.01, 0.04, 0.72)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fundo)
	_popup = fundo
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Estilo.caixa_neon(Color(0.02, 0.05, 0.12, 0.96), Estilo.AZUL_NEON, 1.0, 14))
	p.custom_minimum_size.x = largura
	fundo.add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(_titulo(titulo, 36))
	return v


func _fechar_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null


func _botao_fechar(v: VBoxContainer) -> void:
	var fechar := Button.new()
	fechar.text = "FECHAR"
	fechar.custom_minimum_size.y = 48
	fechar.add_theme_stylebox_override("normal", Estilo.caixa_neon(Color(0.05, 0.14, 0.34, 0.95), Estilo.AZUL_NEON, 0.5, 8))
	fechar.add_theme_stylebox_override("hover", Estilo.caixa_neon(Color(0.1, 0.26, 0.6, 1.0), Color.WHITE, 1.0, 8))
	fechar.pressed.connect(_fechar_popup)
	v.add_child(fechar)
	fechar.grab_focus()


func _abrir_perfil() -> void:
	var v := _janela("PERFIL", 620)
	v.add_child(Estilo.rotulo("Nome do piloto", 20, Estilo.TEXTO_FRACO))
	var nome := LineEdit.new()
	nome.text = Sessao.nome_jogador
	nome.max_length = 14
	nome.text_changed.connect(func(t):
		Sessao.nome_jogador = t.strip_edges() if t.strip_edges() != "" else "PILOTO"
		_atualizar_perfil())
	v.add_child(nome)
	v.add_child(Estilo.rotulo("Nível, créditos e amigos chegam com o modo online.", 17, Estilo.TEXTO_FRACO))
	_botao_fechar(v)


func _abrir_configuracao() -> void:
	var v := _janela("CONFIGURAÇÃO TARGET FLIGHT", 680)
	var grade := GridContainer.new()
	grade.columns = 2
	grade.add_theme_constant_override("h_separation", 24)
	grade.add_theme_constant_override("v_separation", 12)
	v.add_child(grade)
	grade.add_child(Estilo.rotulo("Tempo", 21))
	var modo := OptionButton.new()
	modo.add_item("Por etapa")
	modo.add_item("Por partida")
	modo.selected = 1 if Sessao.tempo_modo == "partida" else 0
	modo.item_selected.connect(func(i): Sessao.tempo_modo = "partida" if i == 1 else "etapa")
	modo.custom_minimum_size.x = 260
	grade.add_child(modo)
	grade.add_child(Estilo.rotulo("Segundos (" + Config.nome_mapa() + ")", 21))
	var seg := SpinBox.new()
	seg.min_value = 30
	seg.max_value = 900
	seg.step = 15
	seg.value = Sessao.tempo_do_mapa()
	seg.value_changed.connect(func(x): Sessao.definir_tempo_do_mapa(int(x)))
	grade.add_child(seg)
	grade.add_child(Estilo.rotulo("Jogadores por equipe", 21))
	var jpe := SpinBox.new()
	jpe.min_value = 1
	jpe.max_value = 4
	jpe.value = Sessao.jogadores_por_equipe
	jpe.value_changed.connect(func(x): Sessao.jogadores_por_equipe = int(x))
	grade.add_child(jpe)
	grade.add_child(Estilo.rotulo("Nível dos bots", 21))
	var nivel := OptionButton.new()
	var ids := ["facil", "medio", "alto", "pro"]
	for id in ids:
		nivel.add_item(str(Config.valor("bots.niveis." + id + ".nome", id.to_upper())))
	nivel.selected = maxi(ids.find(Sessao.nivel_bots), 0)
	nivel.item_selected.connect(func(i): Sessao.nivel_bots = ids[i])
	grade.add_child(nivel)
	# Qualidade gráfica (pedido do dono): BAIXO, MÉDIO, ALTO ou ULTRA — vale a partir da próxima partida
	grade.add_child(Estilo.rotulo("Qualidade gráfica", 21))
	var qual := OptionButton.new()
	var ids_q := ["baixo", "medio", "alto", "ultra"]
	for id in ids_q:
		qual.add_item(str(Config.valor("grafico.qualidades." + id + ".nome", id.to_upper())))
	qual.selected = maxi(ids_q.find(Sessao.qualidade), 0)
	qual.item_selected.connect(func(i):
		Sessao.qualidade = ids_q[i]
		Sessao.salvar())
	grade.add_child(qual)
	v.add_child(HSeparator.new())
	v.add_child(Estilo.rotulo("ÁUDIO", 22, Estilo.TEXTO_FRACO, 600))
	v.add_child(Audio.painel_volumes())
	# Créditos só aqui dentro (pedido do dono)
	v.add_child(HSeparator.new())
	var creditos := _botao_vazio(Estilo.caixa_neon(Color(0.03, 0.08, 0.18, 0.9), Estilo.AZUL_NEON, 0.3, 8),
		Estilo.caixa_neon(Color(0.07, 0.2, 0.5, 0.95), Estilo.AZUL_NEON, 0.9, 8))
	creditos.custom_minimum_size = Vector2(0, 48)
	creditos.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var linha_c := _linha([Estilo.icone("info", 20), Estilo.rotulo("CRÉDITOS", 19, Estilo.TEXTO, 600)], 10)
	linha_c.alignment = BoxContainer.ALIGNMENT_CENTER
	creditos.add_child(_preencher(linha_c))
	creditos.pressed.connect(func():
		_fechar_popup()
		_mostrar_creditos())
	v.add_child(creditos)
	_botao_fechar(v)


func _mostrar_creditos() -> void:
	var v := _janela("CRÉDITOS", 940)
	v.add_child(Estilo.rotulo("TARGET SPEED CHALLENGER — KZULO STUDIOS", 22))
	v.add_child(Estilo.rotulo("Feito com Godot Engine (licença MIT) — godotengine.org/license", 18, Estilo.TEXTO_FRACO))
	v.add_child(Estilo.rotulo("Fonte Exo 2 — Copyright 2013 The Exo 2 Project Authors — SIL Open Font License 1.1", 18, Estilo.TEXTO_FRACO))
	v.add_child(Estilo.rotulo("Fonte Racing Sans One — Copyright (c) 2012 Pablo Impallari, Rodrigo Fuenzalida — SIL Open Font License 1.1", 18, Estilo.TEXTO_FRACO))
	v.add_child(HSeparator.new())
	v.add_child(Estilo.rotulo("Modelos 3D (carros e pilotos)", 22, Estilo.TEXTO_FRACO, 600))
	var arquivos := []   # [creditos.txt, nome de reserva]: carros, pilotos (com as luvas) e interiores do cockpit
	for d in _veiculos + _avatares:
		arquivos.append([d.modelo.get_base_dir() + "/creditos.txt", d.nome])
	for pasta in DirAccess.get_directories_at("res://assets/cockpit"):
		arquivos.append(["res://assets/cockpit/%s/creditos.txt" % pasta, pasta])
	arquivos.append(["res://assets/egito/creditos.txt", "Pharaoh's Climb"])   # templos e estátua de Anúbis
	for a: Array in arquivos:
		# Uma linha por obra do arquivo (o texto de crédito pronto; senão a linha "Modelo:")
		var obras: Array[String] = []
		var modelos: Array[String] = []
		if FileAccess.file_exists(a[0]):
			for l in FileAccess.get_file_as_string(a[0]).split("\n"):
				if l.begins_with("\"") or l.begins_with("This work is based"):
					obras.append(l)
				elif l.begins_with("Crédito: "):
					obras.append(l.trim_prefix("Crédito: "))
				elif l.begins_with("Modelo:"):
					modelos.append(l)
		var texto := "\n".join(obras if not obras.is_empty() else modelos)
		var rot := Estilo.rotulo(texto if texto != "" else a[1], 17)
		rot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rot.custom_minimum_size.x = 900
		v.add_child(rot)
	v.add_child(HSeparator.new())
	v.add_child(Estilo.rotulo("Música e sons (lista completa em assets/audio/creditos.txt)", 22, Estilo.TEXTO_FRACO, 600))
	var sons := Estilo.rotulo(_creditos_audio(), 15, Estilo.TEXTO_FRACO)
	sons.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sons.custom_minimum_size.x = 900
	v.add_child(sons)
	_botao_fechar(v)


## Uma linha por obra (título, autor e licença), tirada de assets/audio/creditos.txt.
func _creditos_audio() -> String:
	var linhas: Array[String] = []
	for l in FileAccess.get_file_as_string("res://assets/audio/creditos.txt").split("\n"):
		if l.begins_with("- ") and " — " in l:
			var partes := l.substr(2).split(" — ")
			linhas.append(" — ".join(partes.slice(1)))
	return "\n".join(linhas)
