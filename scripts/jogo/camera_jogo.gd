class_name CameraJogo
extends Node3D
## Câmera em terceira pessoa (DEC-06): o mouse gira a visão na horizontal e na vertical
## sem segurar botão. Afasta-se no voo para enquadrar carro e paraquedas e continua afastada
## na aproximação do alvo. Também faz a apresentação cinematográfica e o modo espectador.

enum Modo { SEGUIR, CINEMATICA, PODIO }

const ARFAGEM_PADRAO := -0.2

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


func _ready() -> void:
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
	modo = Modo.SEGUIR
	if instantaneo and v:
		_yaw_base = _rumo_de(v)
		_yaw_extra = 0.0
		_arfagem = ARFAGEM_PADRAO
		_distancia = _distancia_desejada(v)
		_foco = v.global_position + Vector3.UP * 1.6


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
	if evento is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw_extra -= evento.relative.x * sensibilidade
		_arfagem = clampf(_arfagem - evento.relative.y * sensibilidade, -1.25, 0.45)
		_ocioso = 0.0
	elif evento is InputEventMouseButton and evento.pressed:
		if evento.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom * 0.9, 0.55, 1.8)
		elif evento.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom / 0.9, 0.55, 1.8)


func _process(delta: float) -> void:
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
	var foco_alvo := v.global_position + Vector3.UP * 1.6
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
	# Na pista, a câmera acompanha a inclinação do carro (descida e rampa).
	var alvo_arf := 0.0
	if not v.eliminado and v.estado == Veiculo.Estado.APOIADO:
		alvo_arf = asin(clampf(-v.global_transform.basis.z.y, -1.0, 1.0))
	_arfagem_veiculo = lerpf(_arfagem_veiculo, alvo_arf, 1.0 - exp(-delta * 4.0))
	var b := Basis.from_euler(Vector3(_arfagem + _arfagem_veiculo, _yaw_base + _yaw_extra, 0.0))
	var pos := _foco + b * Vector3(0.0, 0.0, _distancia)
	var chao := terreno.altura_em(pos.x, pos.z) + 3.0 if terreno else -INF
	pos.y = maxf(pos.y, chao)
	# Não atravessa pista, plataforma nem alvo
	var q := PhysicsRayQueryParameters3D.create(_foco, pos, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = hit.position + (_foco - pos).normalized() * 0.6
	global_position = pos
	look_at(_foco)
	var vel := v.linear_velocity.length() if not v.eliminado else 0.0
	cam.fov = lerpf(cam.fov, 70.0 + clampf((vel - 20.0) * 0.25, 0.0, 12.0), 1.0 - exp(-delta * 2.0))


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
	ref.y = 0.0
	if ref.length() < 4.0:
		ref = -v.global_transform.basis.z
		ref.y = 0.0
	if ref.length() < 0.01:
		return _yaw_base
	return atan2(-ref.x, -ref.z)
