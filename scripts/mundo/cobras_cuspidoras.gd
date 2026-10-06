class_name CobrasCuspidoras
extends Node3D
## Cobras que cospem veneno de buracos na rocha encostada na pista (Serpent's Climb, pedido do dono
## 2026-10-06; percursos.N.armadilhas.cuspidoras: [[trecho, m0, m1, quantas], ...], ajustes em
## armadilhas.cuspidora). Cada cobra mora num buraco irregular na face da rocha, na altura da pista, erguida e
## balançando (modelo animado do dono: assets/MAPA SERPENTE/COBRAS/SerpenteAnimada, CC-BY Imagigoo). De tempos
## em tempos (sorteado), se tem carro perto, ela dá o bote e cospe um jato de veneno verde-claro mirando onde o
## carro vai estar; quem é atingido fica com o veneno (Veiculo.veneno): escorrega como no gelo, direção
## invertida e paraquedas que não abre por `veneno_s` s, com a gosma na lataria.
## Os buracos são achados depois que as rochas da etapa existem (raio da pista para o lado da rocha).

const GLB := "res://assets/MAPA SERPENTE/COBRAS/SerpenteAnimada/assets/snake_attack_animations_multiple.glb"
# Trechos da animação (s): erguida balançando e o bote de cada uma das duas cobras do arquivo
const PARADA := Vector2(2.0, 13.5)
const BOTE := [Vector2(19.0, 21.2), Vector2(15.2, 17.4)]   # [0] = a preta e vermelha, [1] = a clara
const CUSPE_EM := [0.8, 0.75]   # s depois do começo do bote em que o veneno sai da boca
const COR := Color(0.86, 1.0, 0.8)

static var _modelo: Node3D

var _sub: ComplexoSubida
var _item: Array
var _cfg: Dictionary
var _cobras: Array = []      # {no, ap, esq, boca, qual, buraco, frente, t, bote}
var _jatos: Array = []       # {no, de, para, t, dur}
var _pronto := false
var _tentar := 0.0   # as rochas da etapa só existem depois da carga: procura os buracos de novo até achar
var _tentativas := 0
var _rng := RandomNumberGenerator.new()
var _log := false


func montar(sub: ComplexoSubida, item: Array, cfg: Dictionary) -> void:
	_sub = sub
	_item = item
	_cfg = cfg
	_rng.seed = hash(str(item))
	_log = OS.get_environment("TSC_CUSPE_LOG") != ""


static func _carregar() -> Node3D:
	if _modelo == null:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(GLB), st) != OK:
			push_warning("CobrasCuspidoras: não leu %s" % GLB)
			return null
		_modelo = doc.generate_scene(st)
	return _modelo


func _physics_process(delta: float) -> void:
	if not _pronto:
		_tentar -= delta
		if _tentar <= 0.0:
			_tentar = 0.5
			_pronto = _preparar()
		return
	for c: Dictionary in _cobras:
		_animar(c, delta)
	_voar(delta)


# ------------------------------------------------------------------ montagem

func _preparar() -> bool:
	var base := _carregar()
	if base == null:
		return true
	var espaco := get_world_3d().direct_space_state
	var i0 := _sub.indice_trecho(str(_item[0]), float(_item[1]))
	var i1 := _sub.indice_trecho(str(_item[0]), float(_item[2]))
	var qtd := int(_item[3]) if _item.size() > 3 else 5
	var achados: Array = []
	for k in qtd * 3:
		if achados.size() >= qtd:
			break
		var u := (k + 0.5) / float(qtd * 3)
		var i := int(lerpf(i0, i1, u))
		var c := _sub.amostra(i)
		var lat := _sub.lateral_em(i)
		lat = Vector3(lat.x, 0.0, lat.z).normalized()
		for lado: float in [1.0, -1.0]:
			var de := c + lat * lado * 15.5 + Vector3.UP * 1.8
			var q := PhysicsRayQueryParameters3D.create(de, de + lat * lado * 60.0)
			var hit := espaco.intersect_ray(q)
			if hit.is_empty() or not ((hit.collider as Node).get_parent() is RochasSelva or (hit.collider as Node).is_in_group("terreno")):
				continue   # só buraco em rocha ou na encosta do morro (pilares, pirâmides e carros não)
			var p: Vector3 = hit.position
			var longe := true
			for a: Array in achados:
				longe = longe and (a[0] as Vector3).distance_to(p) > 25.0
			if longe:
				achados.append([p, hit.normal, c])
			break
	_tentativas += 1
	if achados.size() < qtd and _tentativas < 60:
		return false   # rochas ainda carregando: tenta de novo (até ~30 s)
	if achados.is_empty():
		return true
	for k in achados.size():
		_cobra(base, achados[k], 1)   # a cobra clara: o bote da preta a deita enrolada fora do buraco
	if _log:
		print("[CUSPE] %d cobras nos buracos de %s: %s" % [_cobras.size(), str(_item), str(achados.map(func(a): return [(a[0] as Vector3).snapped(Vector3.ONE), (a[2] as Vector3).snapped(Vector3.ONE)]))])
	return true


func _cobra(base: Node3D, achado: Array, qual: int) -> void:
	var p: Vector3 = achado[0]
	var n: Vector3 = achado[1]
	var c: Vector3 = achado[2]
	var para_pista := Vector3(c.x - p.x, 0.0, c.z - p.z).normalized()
	# Buraco: boca escura e irregular rente à face da rocha, um pouco saliente (cobre a pedra)
	var buraco := _buraco(_rng.randf_range(5.5, 7.0), _rng.randf_range(4.2, 5.2))
	# (o ponto achado é na colisão simplificada da rocha; a pedra que se vê fica até ~2 m mais para fora)
	p += n * 2.0
	buraco.transform = Transform3D(Basis.looking_at(-n, Vector3.UP), p + Vector3.UP * 0.6)
	add_child(buraco)
	# Cobra: a do arquivo pedida (qual), a outra escondida; pés no fundo do buraco, de frente para a pista
	var no := base.duplicate() as Node3D
	add_child(no)
	var meshes := no.find_children("*", "MeshInstance3D", true, false)
	for k in meshes.size():
		(meshes[k] as MeshInstance3D).visible = k == qual
	var esqs := no.find_children("*", "Skeleton3D", true, false)
	var esq: Skeleton3D = esqs[mini(qual, esqs.size() - 1)]
	var ap: AnimationPlayer = no.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play("Animation")
	ap.seek(5.0, true)
	ap.pause()
	var quadril := esq.global_transform * esq.get_bone_global_pose(_osso(esq, "Hips")).origin
	var cabeca := esq.global_transform * esq.get_bone_global_pose(_osso(esq, "BN_Head")).origin
	var frente := Vector3(cabeca.x - quadril.x, 0.0, cabeca.z - quadril.z).normalized()
	var alto := maxf(cabeca.y - quadril.y, 0.1)
	var esc := float(_cfg.get("altura_cabeca", 3.6)) / alto
	var giro := Basis(Vector3.UP, frente.signed_angle_to(para_pista, Vector3.UP))
	var b := giro.scaled(Vector3.ONE * esc)
	var centro := p - para_pista * 1.2 + Vector3.UP * 0.2
	no.transform = Transform3D(b, centro - b * quadril) * no.transform   # compõe com a raiz do arquivo (escala/giro do glTF)
	ap.seek(_rng.randf_range(PARADA.x, PARADA.y), true)
	ap.play("Animation")
	_cobras.append({"no": no, "ap": ap, "esq": esq, "boca": _osso(esq, "BN_Mouth"), "qual": qual, "buraco": p,
		"frente": para_pista, "t": _rng.randf_range(0.5, 3.0), "bote": -1.0, "cuspiu": false})


func _osso(esq: Skeleton3D, prefixo: String) -> int:
	for k in esq.get_bone_count():
		if esq.get_bone_name(k).begins_with(prefixo):
			return k
	return 0


## Boca escura do buraco: um leque com borda irregular, escuro no meio e pedra úmida na borda.
func _buraco(larg: float, alt: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
	var ruido := FastNoiseLite.new()
	ruido.seed = _rng.randi()
	ruido.frequency = 0.9
	var anel := PackedVector3Array()
	for k in n:
		var a := TAU * k / n
		var r := 1.0 + ruido.get_noise_1d(k * 1.3) * 0.35
		anel.append(Vector3(cos(a) * larg * 0.5 * r, sin(a) * alt * 0.5 * r, 0.0))
	for k in n:
		var a: Vector3 = anel[k]
		var b: Vector3 = anel[(k + 1) % n]
		st.set_color(Color(0.0, 0.0, 0.0))
		st.add_vertex(Vector3(0.0, 0.0, -0.8))   # o meio afunda na pedra
		st.set_color(Color(0.018, 0.013, 0.009))   # (cor linear: 0,09 aparecia cinza-claro)
		st.add_vertex(b)
		st.set_color(Color(0.018, 0.013, 0.009))
		st.add_vertex(a)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # escuro de verdade (iluminado, ficava marrom)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------ comportamento

func _animar(c: Dictionary, delta: float) -> void:
	var ap: AnimationPlayer = c.ap
	var qual: int = c.qual
	var bote: Vector2 = BOTE[qual]
	if c.bote >= 0.0:
		c.bote += delta
		if not c.cuspiu and c.bote >= CUSPE_EM[qual]:
			c.cuspiu = true
			_cuspir(c)
		if ap.current_animation_position >= bote.y:
			c.bote = -1.0
			ap.seek(_rng.randf_range(PARADA.x, PARADA.x + 3.0), true)
		return
	# Parada: balança no trecho erguido (volta ao começo dele em vez de seguir para os outros botes)
	if ap.current_animation_position >= PARADA.y or ap.current_animation_position < PARADA.x:
		ap.seek(PARADA.x + _rng.randf() * 1.5, true)
	c.t -= delta
	if c.t > 0.0:
		return
	var iv: Array = _cfg.get("intervalo", [2.0, 5.0])
	c.t = _rng.randf_range(float(iv[0]), float(iv[1]))
	if _alvo(c) == null:
		return
	c.bote = 0.0
	c.cuspiu = false
	ap.seek(bote.x, true)


## Carro mais perto, na frente do buraco e ao alcance.
func _alvo(c: Dictionary) -> Veiculo:
	var melhor: Veiculo = null
	var melhor_d := float(_cfg.get("alcance", 45.0))
	for no in get_tree().get_nodes_in_group("veiculo"):
		var v := no as Veiculo
		if v == null or v.eliminado or v.fantasma() or not v.visible:
			continue
		var d := v.global_position - (c.buraco as Vector3)
		if Vector3(d.x, 0.0, d.z).normalized().dot(c.frente) < 0.15 or absf(d.y) > 25.0:
			continue
		if d.length() < melhor_d:
			melhor_d = d.length()
			melhor = v
	return melhor


func _cuspir(c: Dictionary) -> void:
	var v := _alvo(c)
	if v == null:
		return
	var esq: Skeleton3D = c.esq
	var boca := esq.global_transform * esq.get_bone_global_pose(int(c.boca)).origin
	var dur := clampf(boca.distance_to(v.global_position) / 55.0, 0.25, 0.8)
	var para := v.global_position + v.linear_velocity * dur + Vector3.UP * 0.6
	# Mira imperfeita: às vezes acerta em cheio, às vezes cai do lado (aleatório, pedido do dono)
	var erro := float(_cfg.get("erro_m", 3.5))
	para += Vector3(_rng.randf_range(-erro, erro), 0.0, _rng.randf_range(-erro, erro))
	var gota := MeshInstance3D.new()
	var esf := SphereMesh.new()
	esf.radius = 0.35
	esf.height = 0.9
	gota.mesh = esf
	var m := StandardMaterial3D.new()
	m.albedo_color = COR
	m.emission_enabled = true
	m.emission = COR
	m.emission_energy_multiplier = 0.6
	m.roughness = 0.1
	gota.material_override = m
	add_child(gota)
	gota.global_position = boca
	var rastro := GPUParticles3D.new()
	rastro.amount = 60
	rastro.lifetime = 0.45
	rastro.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.ZERO
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -3.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	rastro.process_material = pm
	var pingo := SphereMesh.new()
	pingo.radius = 0.12
	pingo.height = 0.24
	pingo.material = m
	rastro.draw_pass_1 = pingo
	gota.add_child(rastro)
	_jatos.append({"no": gota, "de": boca, "para": para, "t": 0.0, "dur": dur})
	if _log:
		print("[CUSPE] cobra cuspiu em %s (%.1f m)" % [v.nome_piloto, boca.distance_to(v.global_position)])


func _voar(delta: float) -> void:
	for k in range(_jatos.size() - 1, -1, -1):
		var j: Dictionary = _jatos[k]
		j.t += delta
		var u := clampf(float(j.t) / float(j.dur), 0.0, 1.0)
		var p := (j.de as Vector3).lerp(j.para, u) + Vector3.UP * 3.0 * sin(PI * u)
		var gota: MeshInstance3D = j.no
		gota.global_position = p
		if u < 1.0:
			continue
		# Chegou: quem está ali leva o veneno; respingo no lugar
		var segundos := float(_cfg.get("veneno_s", 3.0))
		for no in get_tree().get_nodes_in_group("veiculo"):
			var v := no as Veiculo
			if v and not v.eliminado and not v.fantasma() and v.global_position.distance_to(p) < 3.6:
				v.veneno(segundos)
				if _log:
					print("[CUSPE] veneno em %s" % v.nome_piloto)
		_respingo(p)
		gota.queue_free()
		_jatos.remove_at(k)


func _respingo(p: Vector3) -> void:
	var fx := GPUParticles3D.new()
	fx.amount = 40
	fx.lifetime = 0.7
	fx.one_shot = true
	fx.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	fx.process_material = pm
	var pingo := SphereMesh.new()
	pingo.radius = 0.1
	pingo.height = 0.2
	var m := StandardMaterial3D.new()
	m.albedo_color = COR
	m.emission_enabled = true
	m.emission = COR
	m.emission_energy_multiplier = 0.4
	pingo.material = m
	fx.draw_pass_1 = pingo
	add_child(fx)
	fx.global_position = p
	fx.emitting = true
	get_tree().create_timer(1.5).timeout.connect(fx.queue_free)
