class_name AlivioZona
extends Node
## Alívio da placa de vídeo num trecho pesado do mapa (grafico.alivio_zonas.<mapa>.<etapa> no jogo.json; pedido
## do dono 2026-10-07: na chegada à plataforma da cobra do Serpent's Climb a câmera vê o vale inteiro, é o ponto
## mais pesado do mapa e o driver da RX 5700 XT caía ali). Enquanto a câmera está a menos de `raio` m do centro:
## a sombra do sol alcança só `sombra_distancia` m e as árvores distantes somem a `arvores` × o alcance normal.
## A mudança é gradual entre raio e raio + borda; fora da zona o mapa fica como sempre foi.
## As árvores são os MultiMesh do grupo "veg_longe" (Vegetacao.plantar, com o alcance normal na meta "alcance").

var _centro := Vector3.ZERO
var _raio := 550.0
var _borda := 350.0
var _sombra_zona := 700.0
var _arvores_zona := 0.6
var _sombra_normal := 1500.0
var _f_arvores := -1.0   # último fator aplicado nas árvores (em passos de 0,05)


func montar(cfg: Dictionary) -> void:
	var c: Array = cfg.get("centro", [0, 0, 0])
	_centro = Vector3(float(c[0]), float(c[1]), float(c[2]))
	_raio = float(cfg.get("raio", 550.0))
	_borda = float(cfg.get("borda", 350.0))
	_sombra_zona = float(cfg.get("sombra_distancia", 700.0))
	_arvores_zona = float(cfg.get("arvores", 0.6))
	if Ambiente.atual and Ambiente.atual.sol:
		_sombra_normal = Ambiente.atual.sol.directional_shadow_max_distance


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# 1 dentro da zona, 0 fora, suave na borda
	var f := 1.0 - smoothstep(_raio, _raio + _borda, cam.global_position.distance_to(_centro))
	if OS.get_environment("TSC_SEM_ALIVIO") != "":
		f = 0.0
	if Ambiente.atual and Ambiente.atual.sol:
		var alvo := minf(lerpf(_sombra_normal, _sombra_zona, f), _sombra_normal)
		if absf(Ambiente.atual.sol.directional_shadow_max_distance - alvo) > 1.0:
			Ambiente.atual.sol.directional_shadow_max_distance = alvo
	var fa := snappedf(lerpf(1.0, _arvores_zona, f), 0.05)
	if not is_equal_approx(fa, _f_arvores):
		_f_arvores = fa
		_aplicar_arvores(fa)


func _aplicar_arvores(fator: float) -> void:
	for no in get_tree().get_nodes_in_group("veg_longe"):
		var mmi := no as MultiMeshInstance3D
		if mmi == null:
			continue
		var alcance := float(mmi.get_meta("alcance", mmi.visibility_range_end))
		# nunca abaixo de onde o bloco começa a aparecer (visibility_range_begin do bloco sem sombra)
		mmi.visibility_range_end = maxf(alcance * fator, mmi.visibility_range_begin + 50.0)
		mmi.visibility_range_end_margin = mmi.visibility_range_end * 0.15


func _exit_tree() -> void:
	# A etapa acabou: tudo volta ao normal (as árvores do vale são as mesmas nas outras etapas)
	if Ambiente.atual and Ambiente.atual.sol:
		Ambiente.atual.sol.directional_shadow_max_distance = _sombra_normal
	if is_inside_tree():
		_aplicar_arvores(1.0)
