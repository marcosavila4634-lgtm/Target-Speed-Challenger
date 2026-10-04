class_name CameraJogo
extends Node3D
## Câmera em terceira pessoa (DEC-06): o mouse gira a visão na horizontal e na vertical
## sem segurar botão. Afasta-se no voo para enquadrar carro e paraquedas e continua afastada
## na aproximação do alvo. Também faz a apresentação cinematográfica e o modo espectador.

enum Modo { SEGUIR, CINEMATICA, PODIO, DRONE }

## Abertura da partida (pedido do dono): drone filmando o mapa em planos, com faixas de cinema.
## Cada plano: {"pos": [pontos], "olhar": [pontos], "dur": s}. A câmera percorre uma curva suave
## pelos pontos, com balanço de drone e inclinação nas curvas; entre os planos, corte com fade.
## O último plano termina na posição da câmera de jogo (sem pulo quando a contagem começa).
var _planos: Array = []
var _plano_i := 0
var _t_plano := 0.0
var _curva_pos: Curve3D
var _curva_olhar: Curve3D
var _rolagem := 0.0
var _rumo_ant := 0.0
var _cinema: CanvasLayer
var _faixa_cima: ColorRect
var _faixa_baixo: ColorRect
var _fade: ColorRect

const ARFAGEM_PADRAO := -0.2

## Câmera livre (pedido do dono: percorrer o mapa sem jogar, procurando falhas). F3 liga e desliga.
## Mouse olha; setas ou WASD andam na direção do olhar; E/ESPAÇO sobe, Q/C desce; SHIFT corre, CTRL vai
## devagar; a rodinha muda a velocidade. Atravessa tudo. Enquanto está ligada, o carro do jogador não
## recebe comandos e o relógio da etapa para (Partida e ControleJogador leem `livre`).
static var livre := false
var _livre_vel := 60.0
var _livre_yaw := 0.0
var _livre_arf := 0.0
var _livre_aviso: Label

var modo := Modo.SEGUIR
var veiculo: Veiculo
var terreno: Terreno
var cam: Camera3D
var sensibilidade := 0.0025

var _yaw_base := 0.0
var _yaw_extra := 0.0
var _arfagem := ARFAGEM_PADRAO
var _distancia := 9.0
var _ocioso := 10.0
var _centro_cine := Vector3.ZERO
var _t_cine := 0.0
var _foco := Vector3.ZERO
var _arfagem_veiculo := 0.0
var zoom := 1.0   # rodinha do mouse
var _dist_livre := 999.0   # até onde a câmera pode ficar sem entrar em parede/teto
var _olhando_tras := false


func _ready() -> void:
	# A câmera anda no _process (a cada quadro): fica fora da interpolação de física e segue a
	# posição JÁ interpolada do carro (senão o carro desenhado suave e a câmera aos trancos se desencontram)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam = Camera3D.new()
	cam.near = 0.15
	cam.far = 20000.0
	cam.fov = 70.0
	add_child(cam)
	cam.current = true
	if OS.get_environment("TSC_ZOOM") != "":
		zoom = float(OS.get_environment("TSC_ZOOM"))


func seguir(v: Veiculo, instantaneo := false) -> void:
	veiculo = v
	if modo == Modo.DRONE:
		_mostrar_cinema(false)
	modo = Modo.SEGUIR
	cam.rotation.z = 0.0
	if instantaneo and v:
		_yaw_base = _rumo_de(v)
		_yaw_extra = 0.0
		_arfagem = ARFAGEM_PADRAO
		_distancia = _distancia_desejada(v)
		_foco = v.global_position + Vector3.UP * 1.6
		_dist_livre = 999.0


func cinematica(centro: Vector3) -> void:
	modo = Modo.CINEMATICA
	_centro_cine = centro
	_t_cine = 0.0


## Comemoração do fim da partida: câmera parada em `posicao`, balançando devagar, olhando `foco`.
func podio(foco: Vector3, posicao: Vector3) -> void:
	modo = Modo.PODIO
	_centro_cine = foco
	_foco = posicao
	_t_cine = 0.0
	cam.fov = 55.0


func _unhandled_input(evento: InputEvent) -> void:
	if evento is InputEventKey and evento.pressed and not evento.echo and evento.physical_keycode == KEY_F3:
		_alternar_livre()
		return
	if livre:
		if evento is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_livre_yaw -= evento.relative.x * sensibilidade
			_livre_arf = clampf(_livre_arf - evento.relative.y * sensibilidade, -1.55, 1.55)
		elif evento is InputEventMouseButton and evento.pressed:
			if evento.button_index == MOUSE_BUTTON_WHEEL_UP:
				_livre_vel = minf(_livre_vel * 1.25, 1500.0)
			elif evento.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_livre_vel = maxf(_livre_vel / 1.25, 4.0)
		return
	if evento is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw_extra -= evento.relative.x * sensibilidade
		_arfagem = clampf(_arfagem - evento.relative.y * sensibilidade, -1.25, 0.45)
		_ocioso = 0.0
	elif evento is InputEventMouseButton and evento.pressed:
		if evento.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, 0.55, 1.8)
		elif evento.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 0.9, 0.55, 1.8)


## Começa a filmagem do drone (ver _planos). Devolve a duração total.
func drone(planos: Array) -> float:
	_planos = planos
	_plano_i = 0
	_t_plano = 0.0
	_rolagem = 0.0
	modo = Modo.DRONE
	cam.fov = 60.0
	_preparar_plano()
	_mostrar_cinema(true)
	var total := 0.0
	for p: Dictionary in planos:
		total += float(p.dur)
	return total


## Onde a câmera de jogo fica atrás de `v` (posição e foco), para o drone terminar ali.
func pose_seguir(v: Veiculo) -> Array:
	var foco := v.global_position + Vector3.UP * 1.6
	var b := Basis.from_euler(Vector3(ARFAGEM_PADRAO, _rumo_de(v), 0.0))
	var pos := foco + b * Vector3(0.0, 0.0, _distancia_desejada(v))
	# Como no jogo: não atravessa muro/grade (vaga encostada no muro da largada)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(foco, pos, 1))
	if not hit.is_empty():
		pos = foco + (pos - foco).normalized() * maxf(foco.distance_to(hit.position) - 0.6, 1.2)
	return [pos, foco]


func _preparar_plano() -> void:
	var p: Dictionary = _planos[_plano_i]
	_curva_pos = _curva_suave(p.pos)
	_curva_olhar = _curva_suave(p.olhar)
	_t_plano = 0.0


static func _curva_suave(lista: Array) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 0.5
	# Pontos repetidos seguidos (o olhar parado no carro) fazem trechos de comprimento zero:
	# a curva dava erro e podia devolver NaN
	var pontos: Array[Vector3] = []
	for q: Vector3 in lista:
		if pontos.is_empty() or pontos[-1].distance_to(q) > 0.05:
			pontos.append(q)
	var n := pontos.size()
	for i in n:
		var ant: Vector3 = pontos[maxi(i - 1, 0)]
		var prox: Vector3 = pontos[mini(i + 1, n - 1)]
		var h := (prox - ant) / 6.0
		c.add_point(pontos[i], -h, h)
	return c


## Ponto da curva do drone na fração s (curva de comprimento zero: o primeiro ponto).
static func _amostra(c: Curve3D, s: float) -> Vector3:
	var comp := c.get_baked_length()
	if comp < 0.01:
		return c.get_point_position(0) if c.point_count > 0 else Vector3.ZERO
	return c.sample_baked(s * comp, true)


func _processar_drone(delta: float) -> void:
	_t_plano += delta
	var p: Dictionary = _planos[_plano_i]
	var dur := float(p.dur)
	if _t_plano >= dur and _plano_i < _planos.size() - 1:
		_plano_i += 1
		_preparar_plano()
		p = _planos[_plano_i]
		dur = float(p.dur)
	var u := clampf(_t_plano / dur, 0.0, 1.0)
	# Movimento de câmera de cinema: sai e chega devagar (o último plano pousa suave atrás do carro)
	var s := lerpf(u, u * u * (3.0 - 2.0 * u), 0.55 if _plano_i < _planos.size() - 1 else 1.0)
	var pos := _amostra(_curva_pos, s)
	var olhar := _amostra(_curva_olhar, s)
	if not (pos.is_finite() and olhar.is_finite()):
		return   # a câmera é o "ouvido" dos sons 3D: posição NaN emudece motor, pneus e batidas
	# Balanço de drone, que some no fim do último plano
	var tt := Time.get_ticks_msec() / 1000.0
	var balanco := 1.0 if _plano_i < _planos.size() - 1 else 1.0 - s
	pos += Vector3(sin(tt * 1.3), sin(tt * 1.9) * 0.5, cos(tt * 1.1)) * 0.35 * balanco
	global_position = pos
	if pos.distance_to(olhar) > 0.1:
		look_at(olhar)
	# Inclina para dentro da curva, como um drone de filmagem
	var rumo := rotation.y
	var giro := wrapf(rumo - _rumo_ant, -PI, PI) / maxf(delta, 0.001)
	_rumo_ant = rumo
	_rolagem = lerpf(_rolagem, clampf(giro * 0.12, -0.18, 0.18) * balanco, 1.0 - exp(-delta * 3.0))
	cam.rotation.z = _rolagem
	# Corte entre planos: escurece no fim de um e clareia no começo do outro (não no fim do último)
	var a := 0.0
	if _plano_i > 0:
		a = maxf(a, 1.0 - clampf(_t_plano / 0.35, 0.0, 1.0))
	if _plano_i < _planos.size() - 1:
		a = maxf(a, 1.0 - clampf((dur - _t_plano) / 0.35, 0.0, 1.0))
	_fade.color.a = a


func _mostrar_cinema(sim: bool) -> void:
	if _cinema == null:
		_cinema = CanvasLayer.new()
		_cinema.layer = 20
		add_child(_cinema)
		_faixa_cima = ColorRect.new()
		_faixa_baixo = ColorRect.new()
		_fade = ColorRect.new()
		for r: ColorRect in [_faixa_cima, _faixa_baixo, _fade]:
			r.color = Color.BLACK
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_cinema.add_child(r)
		_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		_faixa_cima.anchor_right = 1.0
		_faixa_baixo.anchor_right = 1.0
		_faixa_baixo.anchor_top = 1.0
		_faixa_baixo.anchor_bottom = 1.0
	_fade.color.a = 0.0
	# Faixas presas no topo e no pé da tela: a altura vem dos offsets (âncoras fixas na borda)
	var altura := get_viewport().get_visible_rect().size.y * 0.11
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_faixa_cima, "offset_bottom", altura if sim else 0.0, 0.8)
	tw.tween_property(_faixa_baixo, "offset_top", -altura if sim else 0.0, 0.8)


func _alternar_livre() -> void:
	livre = not livre
	if livre:
		# Parte de onde a câmera está, olhando para onde ela olha
		var b := cam.global_transform.basis
		var frente := -b.z
		_livre_yaw = atan2(-frente.x, -frente.z)
		_livre_arf = asin(clampf(frente.y, -1.0, 1.0))
		var onde := cam.global_position
		cam.transform = Transform3D.IDENTITY
		global_position = onde
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if _livre_aviso == null:
			var camada := CanvasLayer.new()
			camada.layer = 60
			add_child(camada)
			_livre_aviso = Label.new()
			_livre_aviso.position = Vector2(24.0, 120.0)
			_livre_aviso.add_theme_font_size_override("font_size", 18)
			_livre_aviso.add_theme_color_override("font_outline_color", Color.BLACK)
			_livre_aviso.add_theme_constant_override("outline_size", 6)
			camada.add_child(_livre_aviso)
	else:
		cam.transform = Transform3D.IDENTITY
		cam.fov = 70.0
	if _livre_aviso:
		_livre_aviso.visible = livre


func _exit_tree() -> void:
	livre = false


func _processar_livre(delta: float) -> void:
	var b := Basis(Vector3.UP, _livre_yaw) * Basis(Vector3.RIGHT, _livre_arf)
	var anda := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W):
		anda -= b.z
	if Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S):
		anda += b.z
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
		anda += b.x
	if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
		anda -= b.x
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		anda += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_C):
		anda -= Vector3.UP
	var vel := _livre_vel
	if Input.is_physical_key_pressed(KEY_SHIFT):
		vel *= 4.0
	if Input.is_physical_key_pressed(KEY_CTRL):
		vel *= 0.2
	if anda.length_squared() > 0.0:
		global_position += anda.normalized() * vel * delta
	global_transform = Transform3D(b, global_position)
	cam.transform = Transform3D.IDENTITY
	cam.fov = 70.0
	var p := global_position
	_livre_aviso.text = "CÂMERA LIVRE (F3 sai)   x %.0f   y %.0f   z %.0f   vel %.0f m/s\nmouse olha · setas/WASD andam · E sobe · Q desce · SHIFT corre · CTRL devagar · rodinha = velocidade" % [p.x, p.y, p.z, vel]


func _process(delta: float) -> void:
	if livre:
		_processar_livre(delta)
		return
	if modo == Modo.DRONE:
		_processar_drone(delta)
		return
	if modo == Modo.CINEMATICA:
		_t_cine += delta
		var a := _t_cine * 0.22 + 0.6
		var pos := _centro_cine + Vector3(sin(a) * 260.0, 110.0 - _t_cine * 6.0, cos(a) * 260.0)
		global_position = pos
		look_at(_centro_cine + Vector3.UP * 10.0)
		return
	if modo == Modo.PODIO:
		# Aproxima nos primeiros segundos e depois oscila de leve de um lado para o outro
		_t_cine += delta
		var lado := (_foco - _centro_cine).cross(Vector3.UP).normalized()
		var perto := lerpf(1.35, 1.0, 1.0 - exp(-_t_cine * 0.9))
		global_position = _centro_cine + (_foco - _centro_cine) * perto + lado * sin(_t_cine * 0.35) * 3.0
		look_at(_centro_cine)
		return
	if veiculo == null:
		return
	var v := veiculo
	if _camera_looping(v, delta):
		return
	var foco_alvo := v.get_global_transform_interpolated().origin + Vector3.UP * 1.6
	if v.paraquedas_aberto:
		foco_alvo += Vector3.UP * 3.5
	_foco = _foco.lerp(foco_alvo, 1.0 - exp(-delta * 12.0)) if _foco.distance_to(foco_alvo) < 50.0 else foco_alvo
	_distancia = lerpf(_distancia, _distancia_desejada(v), 1.0 - exp(-delta * 1.5))
	if not v.eliminado:
		_yaw_base = lerp_angle(_yaw_base, _rumo_de(v), 1.0 - exp(-delta * 2.5))
	_ocioso += delta
	if _ocioso > 2.5:
		_yaw_extra = lerp_angle(_yaw_extra, 0.0, 1.0 - exp(-delta * 1.2))
		_arfagem = lerpf(_arfagem, ARFAGEM_PADRAO, 1.0 - exp(-delta * 1.2))
	# Na pista, a câmera acompanha a inclinação da PISTA (descida e rampa), não a da carroceria:
	# numa batida o carro empina e sacode, e a câmera sacudia junto
	var alvo_arf := 0.0
	if not v.eliminado and v.estado == Veiculo.Estado.APOIADO:
		var dp := _dir_pista(v)
		if dp != Vector3.ZERO:
			alvo_arf = asin(clampf(dp.y, -1.0, 1.0))
		else:
			alvo_arf = asin(clampf(-v.global_transform.basis.z.y, -1.0, 1.0))
	_arfagem_veiculo = lerpf(_arfagem_veiculo, alvo_arf, 1.0 - exp(-delta * 4.0))
	# C segurado: visão traseira — câmera na frente do carro olhando para trás (sem o giro do mouse)
	var olhando_tras := Input.is_action_pressed("olhar_tras") and modo == Modo.SEGUIR and not v.eliminado
	var yaw := _yaw_base + PI if olhando_tras else _yaw_base + _yaw_extra
	var arf := ARFAGEM_PADRAO if olhando_tras else _arfagem
	if olhando_tras != _olhando_tras:
		_olhando_tras = olhando_tras
		_dist_livre = 999.0   # troca na hora, sem aproximar devagar
	var b := Basis.from_euler(Vector3(arf - _arfagem_veiculo if olhando_tras else arf + _arfagem_veiculo, yaw, 0.0))
	var pos := _foco + b * Vector3(0.0, 0.0, _distancia)
	var chao := terreno.altura_em(pos.x, pos.z) + 3.0 if terreno else -INF
	pos.y = maxf(pos.y, chao)
	# Não atravessa pista, túnel, muretas, plataforma nem alvo. Encosta na hora, mas volta devagar:
	# sem isso, com o carro sacudindo numa batida dentro do túnel, o raio batia/não batia a cada
	# quadro e a câmera ficava pulando entre colada no carro e longe.
	var q := PhysicsRayQueryParameters3D.create(_foco, pos, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var para_cam := pos - _foco
	var livre := para_cam.length()
	if not hit.is_empty():
		livre = maxf(_foco.distance_to(hit.position) - 0.6, 1.2)
	_dist_livre = livre if livre < _dist_livre else lerpf(_dist_livre, livre, 1.0 - exp(-delta * 2.5))
	pos = _foco + para_cam.normalized() * minf(para_cam.length(), _dist_livre)
	if not (pos.is_finite() and _foco.is_finite()):
		_foco = foco_alvo if foco_alvo.is_finite() else global_position
		return   # posição NaN emudeceria todos os sons 3D (a câmera é o "ouvido")
	global_position = pos
	look_at(_foco)
	var vel := v.linear_velocity.length() if not v.eliminado else 0.0
	cam.fov = lerpf(cam.fov, 70.0 + clampf((vel - 20.0) * 0.25, 0.0, 12.0), 1.0 - exp(-delta * 2.0))


## Looping: a câmera gira junto com a pista, atrás do carro — o "para cima" dela é a normal do piso
## (com o céu fixo ela ficaria do lado de fora da fita, tapada, quando o carro está de cabeça para baixo).
var _loop_n := Vector3.UP
var _loop_t := Vector3.FORWARD
var _no_loop := false

func _camera_looping(v: Veiculo, delta: float) -> bool:
	var sub := v.complexo as ComplexoSubida
	var lp := sub.looping_em(v.global_position) if sub and not v.eliminado and not v.paraquedas_aberto else null
	if lp == null:
		_no_loop = false
		return false
	var j := lp.amostra_em(v.global_position)
	if not _no_loop:
		_no_loop = true
		_loop_n = Vector3.UP
		_loop_t = lp.rumo
	var k := 1.0 - exp(-delta * 9.0)
	_loop_n = _loop_n.lerp(lp.nrm[j], k).normalized()
	_loop_t = _loop_t.lerp(lp.tan[j], k).normalized()
	_distancia = lerpf(_distancia, _distancia_desejada(v), 1.0 - exp(-delta * 1.5))
	_foco = v.get_global_transform_interpolated().origin + _loop_n * 1.6
	_yaw_base = atan2(-lp.rumo.x, -lp.rumo.z)
	_arfagem_veiculo = 0.0
	var pos := _foco - _loop_t * _distancia * 0.95 + _loop_n * _distancia * 0.3
	if not (pos.is_finite() and _foco.is_finite()):
		return true
	global_position = pos
	look_at(_foco + _loop_t * 2.0, _loop_n)
	return true


func _distancia_desejada(v: Veiculo) -> float:
	var base := (v.caixa_corpo.size.z * 1.05 + 2.6) * zoom
	if v.eliminado:
		return base * 2.5
	if v.paraquedas_aberto:
		return 15.0 * zoom
	if v.estado == Veiculo.Estado.BALISTICO:
		return base * 1.5
	return base


func _rumo_de(v: Veiculo) -> float:
	if v.paraquedas_aberto:
		return v.rumo
	var ref := v.linear_velocity
	# Na pista (reta até a saída): olha para onde a pista vai. Só segue a velocidade se o carro sair
	# muito do rumo (rodou numa batida e está indo de lado/para trás de verdade)
	var dp := _dir_pista(v) if not v.eliminado and v.estado == Veiculo.Estado.APOIADO else Vector3.ZERO
	if dp != Vector3.ZERO:
		var f := dp
		var rumo_pista := atan2(-f.x, -f.z)
		var h := Vector2(ref.x, ref.z)
		if h.length() < 4.0 or absf(wrapf(atan2(-h.x, -h.y) - rumo_pista, -PI, PI)) < 1.0:
			return rumo_pista
	ref.y = 0.0
	if ref.length() < 4.0:
		ref = -v.global_transform.basis.z
		ref.y = 0.0
	if ref.length() < 0.01:
		return _yaw_base
	return atan2(-ref.x, -ref.z)


## Direção 3D da pista sob o carro (descida, rampa ou a estrada do Climb to Death); zero fora dela.
func _dir_pista(v: Veiculo) -> Vector3:
	if v.complexo == null:
		return Vector3.ZERO
	return v.complexo.direcao_pista(v.global_position)
