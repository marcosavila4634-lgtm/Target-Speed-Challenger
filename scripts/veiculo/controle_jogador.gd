class_name ControleJogador
extends Node
## Teclado → comandos do veículo.
## W acelerar, S ré (não há freio; no alvo, A/D alternando segura o carro) (no ar: inclinar; no paraquedas: acelerar/sustentar), A/D direção,
## ESPAÇO ejetor, E paraquedas, SHIFT nitro.

var veiculo: Veiculo
var ativo := false


func _physics_process(_delta: float) -> void:
	if veiculo == null or not ativo:
		return
	if CameraJogo.livre:   # câmera livre (F3): as teclas andam com a câmera, o carro fica parado
		veiculo.entrada.acelerar = 0.0
		veiculo.entrada.re = 0.0
		veiculo.entrada.freiar = 0.0
		veiculo.entrada.direcao = 0.0
		veiculo.entrada.nitro = false
		return
	veiculo.entrada.acelerar = Input.get_action_strength("acelerar")
	# O carro não tem freio: no chão, S é ré (andando para a frente, a ré é que segura o carro).
	# No ar e no paraquedas, S continua inclinando/sustentando.
	var s := Input.get_action_strength("freiar")
	veiculo.entrada.re = s if veiculo.rodas_no_chao > 0 else 0.0
	veiculo.entrada.freiar = s
	veiculo.entrada.direcao = Input.get_axis("esquerda", "direita")
	veiculo.entrada.nitro = Input.is_action_pressed("nitro")


func _unhandled_input(evento: InputEvent) -> void:
	if veiculo == null or not ativo or CameraJogo.livre:
		return
	if evento.is_action_pressed("ejetor"):
		veiculo.pedir_ejetor()
	elif evento.is_action_pressed("paraquedas"):
		veiculo.alternar_paraquedas()
