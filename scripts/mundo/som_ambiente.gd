class_name SomAmbiente
extends Node3D
## Som ambiente da partida: o público da arena em cada complexo de largada.
## (Sem som de rio/ondas nem torcida no alvo — pedido do dono.)


func montar(complexos: Array[ComplexoLancamento]) -> void:
	name = "SomAmbiente"
	for c in complexos:
		_publico(c.ponto_indice(0) + Vector3.UP * 3.0, -4.0)


func _publico(pos: Vector3, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = Audio.loop("ambiente/publico_ambiente.mp3")
	p.bus = "Ambiente"
	p.volume_db = db
	p.unit_size = 45.0
	p.max_distance = 900.0
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(p)
	p.global_position = pos
	p.play(randf() * 20.0)
