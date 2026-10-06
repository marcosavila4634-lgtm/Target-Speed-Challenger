class_name RochasCaindo
extends Node3D
## Rochas que se soltam da montanha e caem na pista (Serpent's Climb, pedido do dono 2026-10-06;
## percursos.N.armadilhas.quedas: [[trecho, m0, m1], ...], ajustes em armadilhas.queda). De tempos em tempos
## (sorteado) uma rocha se solta na encosta do lado mais alto da pista e rola/quica até a estrada. Não mata:
## é um corpo físico pesado e, quando acerta um carro, dá um tranco a mais no ponto da batida, para longe da
## montanha e para cima — o carro é atirado conforme o lugar em que foi pego. Só funciona com carro por perto.
## Item com 4º elemento [mín, máx]: intervalo próprio da zona (mais rochas), com mais rochas no ar ao mesmo tempo.

const POOL := 8
const MODELOS := ["penhasco_a", "penhasco_b", "penhasco_c"]

var _sub: ComplexoSubida
var _terreno: Terreno
var _pontos: Array = []      # [ponto da pista, direção para a montanha, altura do pé na encosta]
var _rochas: Array[RigidBody3D] = []
var _vida: PackedFloat32Array = []
var _proxima := 1.0
var _rng := RandomNumberGenerator.new()
var _intervalo := Vector2(1.2, 3.5)
var _tamanho := Vector2(3.0, 6.0)
var _tranco := 14.0
var _centro := Vector3.ZERO
var _raio_zona := 0.0
var _log := false


func montar(sub: ComplexoSubida, terreno: Terreno, item: Array, cfg: Dictionary) -> void:
	_sub = sub
	_terreno = terreno
	_rng.seed = hash(str(item))
	_log = OS.get_environment("TSC_QUEDA_LOG") != ""
	var iv: Array = cfg.get("intervalo", [1.2, 3.5])
	if item.size() > 3 and item[3] is Array:
		iv = item[3]
	_intervalo = Vector2(float(iv[0]), float(iv[1])) / 0.65   # pedido do dono (2026-10-06): 35% menos rochas em todas as zonas
	var pool := clampi(int(ceil(8.0 / maxf(_intervalo.x / 1.2, 0.25))), POOL, 24)   # chovendo: mais rochas ao mesmo tempo
	var tm: Array = cfg.get("tamanho", [3.0, 6.0])
	_tamanho = Vector2(float(tm[0]), float(tm[1]))
	_tranco = float(cfg.get("tranco", 14.0))
	var i0 := sub.indice_trecho(str(item[0]), float(item[1]))
	var i1 := sub.indice_trecho(str(item[0]), float(item[2]))
	var caixa := AABB(sub.amostra(i0), Vector3.ZERO)
	# Pontos de soltura: a cada ~12 m, do lado em que o terreno sobe (a montanha), na encosta
	var ult := -INF
	for i in range(i0, i1 + 1):
		if sub.progresso_amostra(i) - ult < 12.0:
			continue
		ult = sub.progresso_amostra(i)
		var c := sub.amostra(i)
		var lat := sub.lateral_em(i)
		lat = Vector3(lat.x, 0.0, lat.z).normalized()
		var meia := sub.largura_em(i) * 0.5
		for lado: float in [1.0, -1.0]:
			var q := c + lat * lado * (meia + 35.0)
			var h := terreno.altura_em(q.x, q.z)
			if h > c.y + 18.0:
				_pontos.append([c, lat * lado, meia])
				caixa = caixa.expand(q)
				break
	_centro = caixa.get_center()
	_raio_zona = caixa.size.length() * 0.5 + 250.0
	for k in pool:
		var r := RigidBody3D.new()
		r.mass = 3500.0
		r.collision_layer = 1
		r.collision_mask = 1 | 2
		r.contact_monitor = true
		r.max_contacts_reported = 4
		r.continuous_cd = true
		var fis := PhysicsMaterial.new()
		fis.bounce = 0.25
		fis.friction = 0.8
		r.physics_material_override = fis
		r.add_to_group("estrutura")
		var nome: String = MODELOS[k % MODELOS.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = load(RochasSelva.PASTA + nome + ".res")
		mi.material_override = RochasSelva._material(nome)
		mi.name = "Malha"
		r.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = SphereShape3D.new()
		cs.name = "Forma"
		r.add_child(cs)
		r.body_entered.connect(_bateu.bind(r))
		r.freeze = true
		r.visible = false
		add_child(r)
		_rochas.append(r)
		_vida.append(-1.0)
	if _log:
		print("[QUEDA] zona %s: %d pontos de soltura" % [str(item), _pontos.size()])


func _physics_process(delta: float) -> void:
	if _pontos.is_empty():
		return
	for k in _rochas.size():
		if _vida[k] < 0.0:
			continue
		_vida[k] += delta
		var r := _rochas[k]
		if _vida[k] > 12.0 or r.global_position.y < _terreno.altura_em(r.global_position.x, r.global_position.z) - 20.0:
			_guardar(k)
	_proxima -= delta
	if _proxima > 0.0:
		return
	_proxima = _rng.randf_range(_intervalo.x, _intervalo.y)
	# Só solta rocha perto de quem está passando (cada uma escolhe um carro e cai um pouco à frente dele)
	var carros: Array = []
	for no in get_tree().get_nodes_in_group("veiculo"):
		var v := no as Veiculo
		if v and v.visible and not v.eliminado and v.global_position.distance_to(_centro) < _raio_zona:
			carros.append(v)
	if carros.is_empty():
		return
	var alvo: Veiculo = carros[_rng.randi() % carros.size()]
	var adiante := alvo.global_position + alvo.linear_velocity * _rng.randf_range(2.2, 3.4)   # ~3 s de queda
	var melhor: Array = []
	var melhor_d := INF
	for pt: Array in _pontos:
		var d := (pt[0] as Vector3).distance_squared_to(adiante)
		if d < melhor_d:
			melhor_d = d
			melhor = pt
	if melhor.is_empty() or melhor_d > 90.0 * 90.0:
		return
	var livre := _vida.find(-1.0)
	if livre < 0:
		return
	_soltar(livre, melhor)


func _soltar(k: int, pt: Array) -> void:
	var r := _rochas[k]
	var c: Vector3 = pt[0]
	var para_morro: Vector3 = pt[1]
	var meia: float = pt[2]
	var lado := para_morro.cross(Vector3.UP)
	# Do alto do paredão, logo acima da beira da pista (mais para dentro ela nasceria dentro das rochas do paredão)
	var p := c + para_morro * (meia + _rng.randf_range(2.0, 5.0)) + lado * _rng.randf_range(-6.0, 6.0)
	p.y = c.y + _rng.randf_range(30.0, 55.0)
	var tam := _rng.randf_range(_tamanho.x, _tamanho.y)
	var mi := r.get_node("Malha") as MeshInstance3D
	mi.scale = Vector3.ONE * tam * 0.5
	mi.position = Vector3.UP * -tam * 0.3
	((r.get_node("Forma") as CollisionShape3D).shape as SphereShape3D).radius = tam * 0.45
	r.mass = 400.0 * tam * tam
	r.freeze = false
	r.visible = true
	r.global_transform = Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, 0.0)), p)
	r.linear_velocity = -para_morro * _rng.randf_range(2.0, 6.0) + Vector3.DOWN * 6.0
	r.angular_velocity = lado * _rng.randf_range(2.0, 5.0)
	r.reset_physics_interpolation()
	_vida[k] = 0.0
	if _log:
		print("[QUEDA] rocha %.1f m solta em %s" % [tam, str(p.snapped(Vector3.ONE))])


func _guardar(k: int) -> void:
	var r := _rochas[k]
	r.freeze = true
	r.visible = false
	r.global_position = Vector3(0.0, -500.0, 0.0)
	_vida[k] = -1.0


## Bateu num carro: além do empurrão da física, um tranco no ponto da batida (atira o carro para longe)
func _bateu(corpo: Node, r: RigidBody3D) -> void:
	var v := corpo as Veiculo
	if v == null or v.fantasma() or v.eliminado:
		return
	var rel := v.global_position - r.global_position
	var dir := (r.linear_velocity.normalized() * 0.6 + Vector3(rel.x, 0.0, rel.z).normalized() * 0.4 + Vector3.UP * 0.55).normalized()
	var forca := _tranco * v.mass * clampf(r.linear_velocity.length() / 10.0, 0.6, 1.6)
	v.apply_impulse(dir * forca, r.global_position + rel * 0.5 - v.global_position)
	if _log:
		print("[QUEDA] rocha acertou %s (v rocha %.1f)" % [v.nome_piloto, r.linear_velocity.length()])
