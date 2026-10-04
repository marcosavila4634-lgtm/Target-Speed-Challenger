extends Node3D
## Gira o nó sem parar em volta de um eixo local, a cada quadro desenhado (rotor de helicóptero: no
## passo da física o giro ficava aos trancos).

var eixo := Vector3.UP
var velocidade := 30.0   # rad/s


func _process(delta: float) -> void:
	rotate_object_local(eixo, velocidade * delta)
