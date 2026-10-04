class_name ImpactoMeteoro
extends Node3D
## Fim da etapa 4 do Extinction Day: o meteoro que estava no céu cai e o mundo acaba.
## 0–3 s:    o próprio meteoro do céu incha e clareia tudo (a câmera olha para ele do chão, tremendo);
## 3–5,8 s:  corte para longe: ele desce de verdade — uma rocha de 840 m envolta em plasma, com o
##           rastro de quilômetros (o do céu some no corte: é o mesmo, agora perto);
## impacto:  clarão que cega, bolas de fogo de até 1,6 km, cratera de lava, e a onda de choque
##           correndo o mapa inteiro a 430 m/s: a floresta tomba para fora e vira carvão em brasa, o
##           chão racha em fendas de lava, a pista e os pilares se desfazem, os carros explodem, tudo
##           o que existe some atrás da parede de poeira; lajes de chão do tamanho de prédios são
##           arrancadas e voam, chove rocha em brasa, o vulcão entra em erupção;
## depois:   a câmera sobe para ver o vale inteiro tomado e o cogumelo; a tela escurece ("EXTINÇÃO");
## ~19 s:    sinal `terminou` (a partida mostra o resultado).
## Antes de tudo (pedido do dono), quando o alvo da etapa é o helicóptero: ele vai embora levando na rede
## os carros que pousaram — sobe, embica e passa pela câmera com o meteoro crescendo no céu atrás dele —
## e continua fugindo durante a cena inteira (os carros da rede não explodem).

signal terminou

const SUSPENSE := 3.0
const QUEDA := 2.8
const T_IMPACTO := SUSPENSE + QUEDA
const VEL_ONDA := 430.0
const DIST_INICIO := 9000.0
const RAIO_METEORO := 420.0
const MAX_BLOCOS := 170

var ponto := Vector3.ZERO
var vinda := Vector3(0.4, 0.6, -0.7)
var veiculos: Array = []
var camera: CameraJogo
var terreno: Terreno
var _t := 0.0
var _meteoro: Meteoro
var _plasma: MeshInstance3D
var _bolas: Array = []          # [MeshInstance3D, material, atraso, raio final]
var _onda_chao: ShaderMaterial
var _parede: MeshInstance3D
var _mat_parede: ShaderMaterial
var _luz: OmniLight3D
var _rochas: Array = []
var _blocos: Array = []
var _n_blocos := 0
var _credito_blocos := 0.0
var _atingidos := {}
var _bateu := false
var _fim := false
var _exp0 := 1.0
var _clarao: ColorRect
var _titulo: Label
var _ruido: NoiseTexture2D
var _mats: Array[ShaderMaterial] = []   # materiais que reagem à onda (floresta, chão, pista, pilares)
var _some: Array = []                    # [distância ao impacto, nó] em ordem: somem quando a onda chega
var _some_i := 0
var _raio_ceu := 0.2
var _brilho_ceu := 1.0
var _vulcao_p := Vector3.INF
var _vulcao_foi := false
var _rng := RandomNumberGenerator.new()
var _uniformes := {}
# Fuga do helicóptero
const FUGA := 4.6
var _heli: Alvo
var _heli_carros: Array = []    # [Veiculo, posição relativa ao alvo]
var _heli_dir := Vector3.FORWARD
var _heli_t := 0.0
var _heli_de := Vector3.ZERO
var _espera := 0.0
var _malhas_bloco: Array[ArrayMesh] = []
static var _mats_fumaca := {}


func iniciar(p_ponto: Vector3, p_vinda: Vector3, p_veiculos: Array, p_camera: CameraJogo, p_terreno: Terreno, p_alvo: Alvo = null) -> void:
	if OS.get_environment("TSC_IMPACTO_LOG") != "":
		print("[IMPACTO] começou em ", Time.get_ticks_msec() / 1000.0, " s")
	ponto = p_ponto
	vinda = p_vinda.normalized()
	veiculos = p_veiculos
	camera = p_camera
	terreno = p_terreno
	_rng.seed = 77
	if p_alvo and p_alvo.dino_estado.has("heli"):
		_heli = p_alvo
		_heli.em_fuga = true
		_heli_de = _heli.global_position
		_espera = FUGA
		var fora_h := Vector3(_heli.global_position.x - p_ponto.x, 0.0, _heli.global_position.z - p_ponto.z)
		_heli_dir = fora_h.normalized() if fora_h.length() > 1.0 else -Vector3(vinda.x, 0.0, vinda.z).normalized()
		for v: Veiculo in veiculos:
			if is_instance_valid(v) and not v.eliminado and v.travado and v.global_position.distance_to(_heli.global_position) < 30.0:
				_heli_carros.append([v, v.global_position - _heli.global_position])
	_ruido = Terreno._textura_ruido(0.04, 4, 501)
	var amb := Ambiente.atual
	if amb:
		_exp0 = amb.env.tonemap_exposure
		if amb.ceu_mat:
			_raio_ceu = float(amb.ceu_mat.get_shader_parameter("met_raio"))
			_brilho_ceu = float(amb.ceu_mat.get_shader_parameter("met_brilho"))
	if terreno and terreno.dino:
		var cv: Vector2 = terreno.dino.centro_vulcao
		_vulcao_p = Vector3(cv.x, terreno.altura_em(cv.x, cv.y) + 20.0, cv.y)
	# Tudo o que a onda vai destruir: materiais que reagem a ela e nós que somem quando ela chega
	_coletar(get_parent())
	_some.sort_custom(func(a, b): return a[0] < b[0])
	for m in _mats:
		m.set_shader_parameter("onda_centro", ponto)
	# Clarão e título na tela
	var camada := CanvasLayer.new()
	camada.layer = -1   # por cima do 3D e por baixo do HUD (o resultado aparece em cima do escuro)
	add_child(camada)
	_clarao = ColorRect.new()
	_clarao.color = Color(1.0, 0.97, 0.9, 0.0)
	_clarao.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clarao.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(_clarao)
	_titulo = Label.new()
	_titulo.text = "EXTINÇÃO"
	_titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titulo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_titulo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_titulo.add_theme_font_size_override("font_size", 120)
	if ResourceLoader.exists("res://assets/fontes/RacingSansOne-Regular.ttf"):
		_titulo.add_theme_font_override("font", load("res://assets/fontes/RacingSansOne-Regular.ttf"))
	_titulo.add_theme_color_override("font_color", Color(1.0, 0.42, 0.12))
	_titulo.modulate.a = 0.0
	_titulo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(_titulo)
	# Câmera: do chão olhando o meteoro no céu; corte para longe na queda; recuando da onda; e do alto
	var horiz := Vector3(vinda.x, 0.0, vinda.z).normalized()
	var lado := horiz.cross(Vector3.UP).normalized()
	var olho1 := ponto - horiz * 420.0 + lado * 300.0
	olho1.y = terreno.altura_em(olho1.x, olho1.z) + 30.0
	var olho2 := ponto - horiz * 1500.0 + lado * 2300.0
	olho2.y = terreno.altura_em(olho2.x, olho2.z) + 180.0
	var olho3a := ponto - horiz * 1700.0 + lado * 1100.0
	olho3a.y = terreno.altura_em(olho3a.x, olho3a.z) + 240.0
	var olho3b := ponto - horiz * 2700.0 + lado * 1700.0
	olho3b.y = olho3a.y + 160.0
	var olho4a := ponto - horiz * 4600.0 + lado * 2400.0 + Vector3.UP * 2300.0
	var olho4b := ponto - horiz * 5600.0 + lado * 3000.0 + Vector3.UP * 3000.0
	if camera:
		if camera.cam:
			camera.cam.far = 40000.0
		var planos: Array = []
		if _heli:
			# O helicóptero vindo na direção da câmera, com a rede e os carros pendurados e o meteoro no céu atrás
			var hp := _heli.global_position
			var alt_h := float(_heli.dino_estado.get("altura_heli", 44.0))
			var lado_h := _heli_dir.cross(Vector3.UP).normalized()
			var olho0 := hp + _heli_dir * 135.0 + lado_h * 34.0 + Vector3.UP * (alt_h * 0.3)
			olho0.y = maxf(olho0.y, terreno.altura_em(olho0.x, olho0.z) + 12.0)
			planos.append({"dur": FUGA, "pos": [olho0, olho0 + _heli_dir * 14.0 + Vector3.UP * 4.0], "olhar": [hp + Vector3.UP * alt_h * 0.55, _posicao_heli(hp, FUGA) + Vector3.UP * alt_h * 0.6]})
		planos.append_array([
			{"dur": SUSPENSE, "pos": [olho1, olho1 + Vector3.UP * 6.0], "olhar": [olho1 + vinda * 5000.0 - Vector3.UP * 900.0, olho1 + vinda * 5000.0]},
			{"dur": QUEDA + 0.7, "pos": [olho2, olho2 + Vector3.UP * 30.0], "olhar": [ponto + vinda * 3800.0, ponto + Vector3.UP * 150.0]},
			{"dur": 4.6, "pos": [olho3a, olho3b], "olhar": [ponto + Vector3.UP * 300.0, ponto + Vector3.UP * 500.0]},
			{"dur": 12.0, "pos": [olho4a, olho4b], "olhar": [ponto + Vector3.UP * 500.0, ponto + Vector3.UP * 900.0]},
		])
		camera.drone(planos)


## Onde o helicóptero está `t` s depois de arrancar de `de`: acelera para longe do impacto e sobe.
func _posicao_heli(de: Vector3, t: float) -> Vector3:
	var vmax := 62.0
	var ac := 10.0
	var t_ac := vmax / ac
	var d := 0.5 * ac * t * t if t < t_ac else 0.5 * ac * t_ac * t_ac + vmax * (t - t_ac)
	return de + _heli_dir * d + Vector3.UP * (t * t * 0.9 if t < 5.0 else 22.5 + (t - 5.0) * 9.0)


func _mover_heli(delta: float) -> void:
	if _heli == null or not is_instance_valid(_heli):
		return
	_heli_t += delta
	var p := _posicao_heli(_heli_de, _heli_t)
	_heli.global_position = p
	_heli.visible = true
	var no: Node3D = (_heli.dino_estado.heli as Dictionary).no
	no.rotation.y = lerp_angle(no.rotation.y, atan2(-_heli_dir.x, -_heli_dir.z), clampf(delta * 2.2, 0.0, 1.0))
	no.rotation.x = lerpf(no.rotation.x, -0.24, clampf(delta * 1.2, 0.0, 1.0))
	for par: Array in _heli_carros:
		var v: Veiculo = par[0]
		if is_instance_valid(v):
			v.global_position = p + (par[1] as Vector3)
			v.reset_physics_interpolation()


## Anda pela cena inteira: materiais com `onda_raio` reagem à onda; o resto (estruturas, bichos, luzes,
## enfeites) entra na lista do que some quando ela chega.
func _coletar(no: Node) -> void:
	if no == self or no is Veiculo or no is Camera3D or (_heli != null and no == _heli):
		return
	if no is GeometryInstance3D:
		var gi := no as GeometryInstance3D
		var reage := false
		for m in _materiais(gi):
			if m is ShaderMaterial and (m as ShaderMaterial).shader and _tem_onda((m as ShaderMaterial).shader):
				if not _mats.has(m):
					_mats.append(m)
				reage = true
		if not reage and gi.is_visible_in_tree():
			var caixa := gi.global_transform * gi.get_aabb()
			var c := caixa.get_center()
			var d := Vector2(c.x - ponto.x, c.z - ponto.z).length()
			if caixa.get_longest_axis_size() > 1500.0:
				d = 1400.0   # peça espalhada pelo mapa inteiro (lâmpadas, tochas): some sob a bola de fogo
			_some.append([d, gi])
	elif no is Light3D and not (no is DirectionalLight3D):
		var p := (no as Light3D).global_position
		_some.append([Vector2(p.x - ponto.x, p.z - ponto.z).length(), no])
	for f in no.get_children():
		_coletar(f)


func _materiais(gi: GeometryInstance3D) -> Array:
	var lista := []
	if gi.material_override:
		lista.append(gi.material_override)
	if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
		for s in (gi as MeshInstance3D).mesh.get_surface_count():
			lista.append((gi as MeshInstance3D).get_active_material(s))
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh and (gi as MultiMeshInstance3D).multimesh.mesh:
		var malha := (gi as MultiMeshInstance3D).multimesh.mesh
		for s in malha.get_surface_count():
			lista.append(malha.surface_get_material(s))
	return lista


func _tem_onda(sh: Shader) -> bool:
	if not _uniformes.has(sh):
		var tem := false
		for u in sh.get_shader_uniform_list():
			if str(u.name) == "onda_raio":
				tem = true
		_uniformes[sh] = tem
	return _uniformes[sh]


func _process(delta: float) -> void:
	_mover_heli(delta)
	if _espera > 0.0:
		_espera -= delta
		_tremer(0.12)
		return
	_t += delta
	var amb := Ambiente.atual
	if _t < SUSPENSE:
		# O meteoro do céu incha e o mundo clareia
		var u := _t / SUSPENSE
		var e := u * u
		if amb and amb.ceu_mat:
			amb.ceu_mat.set_shader_parameter("met_raio", _raio_ceu * (1.0 + 0.9 * e))
			amb.ceu_mat.set_shader_parameter("met_brilho", _brilho_ceu * (1.0 + 2.5 * e))
			amb.sol.light_energy = lerpf(2.6, 5.0, e)
			amb.env.tonemap_exposure = _exp0 + e * 0.6
		_tremer(0.25 + e * 0.9)
		return
	if _t < T_IMPACTO:
		if _meteoro == null:
			_criar_meteoro()
		var u := (_t - SUSPENSE) / QUEDA
		var p := ponto + vinda * DIST_INICIO * (1.0 - u)
		_meteoro.mover_para(p)
		_plasma.global_position = p - vinda * RAIO_METEORO * 0.5
		if amb:
			amb.sol.light_energy = lerpf(5.0, 9.0, u)
			amb.env.tonemap_exposure = _exp0 + 0.6 + u * u * 1.4
		_tremer(1.0 + u * 1.6)
		return
	if not _bateu:
		_bater()
	var dt := _t - T_IMPACTO
	# Clarão branco que cega e some; no fim a tela escurece com o título
	var escuro := smoothstep(10.0, 12.6, dt)
	_clarao.color = Color(1.0, 0.97, 0.9).lerp(Color(0.05, 0.0, 0.0), smoothstep(1.5, 9.0, dt))
	_clarao.color.a = maxf(clampf(1.0 - dt / 1.6, 0.0, 1.0), escuro * (0.55 if _fim else 0.9))
	_titulo.modulate.a = smoothstep(11.0, 12.6, dt) * (0.0 if _fim else 1.0)
	# Bolas de fogo: crescem rápido, sobem, escurecem em fumaça
	for b: Array in _bolas:
		var mi: MeshInstance3D = b[0]
		var m: ShaderMaterial = b[1]
		var t := maxf(dt - float(b[2]), 0.0)
		var r := float(b[3]) * (1.0 - exp(-t * 1.1))
		mi.scale = Vector3(r, r * 0.82, r)
		mi.global_position = ponto + Vector3.UP * (r * 0.36 + t * t * 7.0)
		m.set_shader_parameter("vida", clampf(t / 11.0, 0.0, 1.0))
	# Onda de choque: materiais reagem, o que não reage some quando ela passa
	var ro := dt * VEL_ONDA
	for m in _mats:
		m.set_shader_parameter("onda_raio", ro)
	while _some_i < _some.size() and float(_some[_some_i][0]) < ro - 40.0:
		var alvo_n = _some[_some_i][1]
		if is_instance_valid(alvo_n):
			(alvo_n as Node3D).visible = false
		_some_i += 1
	_onda_chao.set_shader_parameter("raio", ro)
	_onda_chao.set_shader_parameter("alfa", 1.0 - smoothstep(11.0, 15.0, dt))
	_parede.scale = Vector3(maxf(ro, 1.0), 1.0 + dt * 0.5, maxf(ro, 1.0))
	_mat_parede.set_shader_parameter("alfa", (1.0 - smoothstep(10.0, 15.0, dt)) * smoothstep(0.0, 0.3, dt))
	_luz.light_energy = 120.0 * exp(-dt * 0.9) + 8.0
	if amb:
		amb.env.tonemap_exposure = _exp0 + 7.0 * exp(-dt * 2.0) + 0.5
	# A onda passa pela câmera uns 4–5 s depois: novo tranco
	var d_cam := 0.0
	if camera and camera.cam:
		d_cam = Vector2(camera.cam.global_position.x - ponto.x, camera.cam.global_position.z - ponto.z).length()
	_tremer(3.6 * exp(-dt * 0.5) + 2.6 * exp(-absf(ro - d_cam) / 260.0))
	# Carros: explodem quando a parede chega
	for v: Veiculo in veiculos:
		if _atingidos.has(v) or not is_instance_valid(v) or not v.visible:
			continue
		if _heli_carros.any(func(par): return par[0] == v):
			continue   # salvo pelo helicóptero
		if Vector2(v.global_position.x - ponto.x, v.global_position.z - ponto.z).length() < ro:
			_atingidos[v] = true
			var ex := Explosao.new()
			get_parent().add_child(ex)
			ex.global_position = v.global_position + Vector3.UP
			Destrocos.criar(v)
			v.visible = false
	# Lajes de chão arrancadas na frente da onda (o mundo se despedaçando)
	if ro < 6500.0 and _n_blocos < MAX_BLOCOS:
		_credito_blocos += delta * 16.0
		while _credito_blocos >= 1.0 and _n_blocos < MAX_BLOCOS:
			_credito_blocos -= 1.0
			var a := _rng.randf() * TAU
			var r_b := maxf(ro - _rng.randf_range(20.0, 160.0), 60.0)
			var fora := Vector3(cos(a), 0.0, sin(a))
			var p_b := ponto + fora * r_b
			p_b.y = terreno.altura_em(p_b.x, p_b.z)
			_lancar_bloco(p_b, fora * _rng.randf_range(60.0, 190.0) + Vector3.UP * _rng.randf_range(70.0, 190.0), _rng.randf_range(18.0, 70.0))
	for lista: Array in [_rochas, _blocos]:
		for rc: Dictionary in lista:
			if rc.get("parou", false):
				continue
			var no: Node3D = rc.no
			rc.v = (rc.v as Vector3) + Vector3.DOWN * 9.8 * 3.0 * delta   # gravidade "de cinema": peças enormes caem pesadas
			no.global_position += (rc.v as Vector3) * delta
			if rc.has("giro"):
				no.rotate_object_local((rc.giro as Vector3).normalized(), (rc.giro as Vector3).length() * delta)
			if (rc.v as Vector3).y < 0.0 and no.global_position.y < terreno.altura_em(no.global_position.x, no.global_position.z) - float(rc.get("afunda", 0.0)):
				rc.parou = true
	# O vulcão explode quando a onda chega nele
	if not _vulcao_foi and _vulcao_p != Vector3.INF and ro > Vector2(_vulcao_p.x - ponto.x, _vulcao_p.z - ponto.z).length():
		_vulcao_foi = true
		_erupcao()
	if dt > 13.0 and not _fim:
		_fim = true
		_tremer(0.0)
		terminou.emit()


func _tremer(forca: float) -> void:
	if camera and camera.cam:
		camera.cam.h_offset = sin(_t * 47.0) * forca * 0.6 + sin(_t * 13.0) * forca * 0.3
		camera.cam.v_offset = cos(_t * 39.0) * forca * 0.4 + cos(_t * 11.0) * forca * 0.25


## Corte: o meteoro do céu some e entra a rocha de verdade, no mesmo rumo.
func _criar_meteoro() -> void:
	if Ambiente.atual and Ambiente.atual.ceu_mat:
		Ambiente.atual.ceu_mat.set_shader_parameter("met_brilho", 0.0)
	_meteoro = Meteoro.new()
	_meteoro.tamanho = RAIO_METEORO
	add_child(_meteoro)
	_meteoro.mover_para(ponto + vinda * DIST_INICIO)
	# Plasma em volta da rocha (o ar incandescente na frente dela)
	_plasma = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(RAIO_METEORO * 8.0, RAIO_METEORO * 8.0)
	_plasma.mesh = q
	var mp := StandardMaterial3D.new()
	mp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mp.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mp.albedo_texture = Gelo._textura_floco()
	mp.albedo_color = Color(1.0, 0.62, 0.3, 1.0)
	mp.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_plasma.material_override = mp
	_plasma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plasma)


func _bater() -> void:
	_bateu = true
	_meteoro.queue_free()
	_plasma.queue_free()
	if Ambiente.atual and Ambiente.atual.ceu_mat:
		Ambiente.atual.ceu_mat.set_shader_parameter("met_brilho", 0.0)
		Ambiente.atual.ceu_mat.set_shader_parameter("apocalipse", 1.0)
		Ambiente.atual.sol.light_energy = 1.2
	var chao_y := terreno.altura_em(ponto.x, ponto.z)
	_luz = OmniLight3D.new()
	_luz.light_color = Color(1.0, 0.72, 0.42)
	_luz.omni_range = 12000.0
	_luz.omni_attenuation = 0.6
	_luz.light_energy = 120.0
	_luz.position = ponto + Vector3.UP * 500.0
	add_child(_luz)
	# Bolas de fogo em camadas (tamanhos, atrasos e ruídos diferentes: o fogo se revolve)
	for camada: Array in [[1600.0, 0.0, 501], [1200.0, 0.18, 503], [800.0, 0.06, 507], [520.0, 0.3, 509]]:
		var mi := MeshInstance3D.new()
		var esf := SphereMesh.new()
		esf.radius = 1.0
		esf.height = 2.0
		esf.radial_segments = 64
		esf.rings = 32
		mi.mesh = esf
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/bola_fogo.gdshader")
		m.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, int(camada[2])))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * 0.1
		add_child(mi)
		_bolas.append([mi, m, camada[1], camada[0]])
	# Cratera: lago de lava onde ele caiu
	var cratera := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = 900.0
	disco.bottom_radius = 900.0
	disco.height = 1.0
	disco.radial_segments = 64
	cratera.mesh = disco
	cratera.material_override = Dino.material_lava(0, 0.08, 1.0, 60.0, 8.0, 20.0, true)
	cratera.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cratera.position = Vector3(ponto.x, chao_y + 6.0, ponto.z)
	add_child(cratera)
	# Onda no chão e a parede de poeira (anel vertical que cresce)
	var plano := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(16000, 16000)
	pl.subdivide_width = 32
	pl.subdivide_depth = 32
	plano.mesh = pl
	_onda_chao = ShaderMaterial.new()
	_onda_chao.shader = load("res://shaders/onda_choque.gdshader")
	_onda_chao.set_shader_parameter("ruido", _ruido)
	_onda_chao.set_shader_parameter("largura", 320.0)
	plano.material_override = _onda_chao
	plano.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plano.position = Vector3(ponto.x, chao_y + 10.0, ponto.z)
	add_child(plano)
	_parede = MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = 1.0
	cil.bottom_radius = 1.0
	cil.height = 340.0
	cil.radial_segments = 128
	cil.rings = 4
	cil.cap_top = false
	cil.cap_bottom = false
	_parede.mesh = cil
	_mat_parede = ShaderMaterial.new()
	_mat_parede.shader = load("res://shaders/parede_poeira.gdshader")
	_mat_parede.set_shader_parameter("ruido", _ruido)
	_parede.material_override = _mat_parede
	_parede.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parede.position = Vector3(ponto.x, chao_y + 150.0, ponto.z)
	add_child(_parede)
	# Labaredas (fogo em volume em volta da bola), cogumelo e poeira baixa
	_nuvem(160, 4.5, Vector3.UP, Vector2(120.0, 420.0), Vector2(260.0, 560.0), 380.0, Color(1.0, 0.5, 0.12, 0.9), true, 0.0, Vector3(0, 10, 0))
	var haste := _nuvem(200, 18.0, Vector3.UP, Vector2(140.0, 240.0), Vector2(520.0, 900.0), 260.0, Color(0.34, 0.24, 0.19, 0.95), false, 0.5, Vector3(0, 2, 0))
	(haste.process_material as ParticleProcessMaterial).spread = 7.0
	var chapeu := _nuvem(240, 16.0, Vector3.UP, Vector2(30.0, 110.0), Vector2(1000.0, 1700.0), 900.0, Color(0.38, 0.27, 0.22, 0.95), false, 2.6, Vector3(0, 0.5, 0))
	chapeu.position = ponto + Vector3.UP * 2300.0
	(chapeu.process_material as ParticleProcessMaterial).flatness = 0.7
	(chapeu.process_material as ParticleProcessMaterial).spread = 90.0
	var baixa := _nuvem(200, 13.0, Vector3.UP, Vector2(300.0, 620.0), Vector2(180.0, 420.0), 500.0, Color(0.45, 0.36, 0.3, 0.85), false, 0.0, Vector3.ZERO)
	(baixa.process_material as ParticleProcessMaterial).spread = 90.0
	(baixa.process_material as ParticleProcessMaterial).flatness = 0.9
	# Rochas em brasa arremessadas para todo lado
	for k in 60:
		var m := Meteoro.new()
		m.tamanho = _rng.randf_range(5.0, 22.0)
		m.ejecta = true
		add_child(m)
		m.mover_para(ponto + Vector3.UP * 60.0)
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 1.6), _rng.randf_range(-1, 1)).normalized()
		_rochas.append({"no": m, "v": dir * _rng.randf_range(260.0, 720.0), "afunda": 0.0})
	# Lajes de chão arrancadas em volta da cratera
	# (eram caixas lisas: agora são pedaços de rocha quebrada, com textura de estratos, terra em cima e brasa embaixo)
	var mat_laje := ShaderMaterial.new()
	mat_laje.shader = load("res://shaders/laje_voando.gdshader")
	mat_laje.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 331))
	mat_laje.set_shader_parameter("ruido_fino", Terreno._textura_ruido(0.08, 4, 337))
	for k in 5:
		var mb := _malha_pedaco(900 + k * 17)
		mb.surface_set_material(0, mat_laje)
		_malhas_bloco.append(mb)
	for k in 46:
		var a := _rng.randf() * TAU
		var fora := Vector3(cos(a), 0.0, sin(a))
		var p_b := ponto + fora * _rng.randf_range(250.0, 1000.0)
		p_b.y = chao_y
		_lancar_bloco(p_b, fora * _rng.randf_range(120.0, 380.0) + Vector3.UP * _rng.randf_range(180.0, 460.0), _rng.randf_range(40.0, 150.0))


## Um pedaço de chão do tamanho de um prédio, girando no ar.
func _lancar_bloco(p: Vector3, v: Vector3, tam: float) -> void:
	_n_blocos += 1
	var mi := MeshInstance3D.new()
	mi.mesh = _malhas_bloco[_n_blocos % _malhas_bloco.size()]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_transform = Transform3D(Basis.from_euler(Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)) * Basis.from_scale(Vector3(tam, tam * _rng.randf_range(0.25, 0.6), tam * _rng.randf_range(0.6, 1.2))), p)
	_blocos.append({"no": mi, "v": v, "giro": Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _rng.randf_range(0.4, 1.6), "afunda": tam * 0.3})


## Pedaço de rocha quebrada (cabe numa caixa de ~1 m; a escala de cada laje é dada na hora de lançar):
## uma esfera amassada pelo ruído e cortada por planos ao acaso, de faces chapadas como pedra lascada.
func _malha_pedaco(semente: int) -> ArrayMesh:
	var esf := SphereMesh.new()
	esf.radius = 0.5
	esf.height = 1.0
	esf.radial_segments = 14
	esf.rings = 7
	var arr := esf.get_mesh_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var rng := RandomNumberGenerator.new()
	rng.seed = semente
	var ruido := FastNoiseLite.new()
	ruido.seed = semente
	ruido.frequency = 1.4
	var planos: Array = []
	for k in 8:
		planos.append([Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.24, 0.42)])
	for i in vs.size():
		var v := vs[i] * (1.0 + 0.55 * ruido.get_noise_3dv(vs[i] * 2.0))
		for pl: Array in planos:
			var d := v.dot(pl[0]) - float(pl[1])
			if d > 0.0:
				v -= (pl[0] as Vector3) * d
		vs[i] = v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	for i in idx:
		st.add_vertex(vs[i])
	st.generate_normals()
	return st.commit()


## Material das nuvens de partículas (shaders/fumaca_volume.gdshader): fumaça iluminada ou labareda aditiva.
static func material_fumaca(fogo: bool, brasa := 0.0) -> ShaderMaterial:
	var chave := "%s %.2f" % [fogo, brasa]
	if _mats_fumaca.has(chave) and is_instance_valid(_mats_fumaca[chave]):
		return _mats_fumaca[chave]
	var sh: Shader = load("res://shaders/fumaca_volume.gdshader")
	if fogo:
		var ad := Shader.new()
		ad.code = sh.code.replace("render_mode blend_mix", "render_mode blend_add")
		sh = ad
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.012, 3, 613))
	m.set_shader_parameter("fogo", 1.0 if fogo else 0.0)
	m.set_shader_parameter("brasa", brasa)
	if Ambiente.atual and Ambiente.atual.sol:
		m.set_shader_parameter("sol_dir", Ambiente.atual.sol.global_transform.basis.z)
	_mats_fumaca[chave] = m
	return m


## O vulcão explode: coluna de lava e cinza saindo da cratera, com luz.
func _erupcao() -> void:
	var fogo := _nuvem(220, 7.0, Vector3.UP, Vector2(260.0, 620.0), Vector2(120.0, 300.0), 200.0, Color(1.0, 0.45, 0.1, 0.95), true, 0.0, Vector3(0, -60, 0), _vulcao_p)
	(fogo.process_material as ParticleProcessMaterial).spread = 24.0
	var cinza := _nuvem(200, 16.0, Vector3.UP, Vector2(160.0, 320.0), Vector2(400.0, 800.0), 240.0, Color(0.2, 0.17, 0.16, 0.95), false, 0.3, Vector3(0, 3, 0), _vulcao_p)
	(cinza.process_material as ParticleProcessMaterial).spread = 14.0
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.4, 0.1)
	luz.light_energy = 60.0
	luz.omni_range = 5000.0
	luz.omni_attenuation = 0.7
	luz.position = _vulcao_p + Vector3.UP * 300.0
	add_child(luz)
	for k in 30:
		var m := Meteoro.new()
		m.tamanho = _rng.randf_range(4.0, 14.0)
		m.ejecta = true
		add_child(m)
		m.mover_para(_vulcao_p + Vector3.UP * 30.0)
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(1.0, 2.4), _rng.randf_range(-1, 1)).normalized()
		_rochas.append({"no": m, "v": dir * _rng.randf_range(220.0, 520.0), "afunda": 0.0})


func _nuvem(qtd: int, vida: float, dir: Vector3, vel: Vector2, tam: Vector2, raio: float, cor: Color, fogo: bool, atraso: float, grav: Vector3, onde := Vector3.INF) -> GPUParticles3D:
	var part := GPUParticles3D.new()
	part.amount = qtd
	part.lifetime = vida
	part.one_shot = true
	part.explosiveness = 0.85
	part.local_coords = false
	part.visibility_aabb = AABB(Vector3(-9000, -500, -9000), Vector3(18000, 9000, 18000))
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = raio
	proc.direction = dir
	proc.spread = 30.0
	proc.initial_velocity_min = vel.x
	proc.initial_velocity_max = vel.y
	proc.damping_min = 6.0
	proc.damping_max = 14.0
	proc.gravity = grav
	proc.scale_min = tam.x
	proc.scale_max = tam.y
	proc.angle_min = 0.0
	proc.angle_max = 360.0
	proc.angular_velocity_min = -6.0
	proc.angular_velocity_max = 6.0
	var cresce := Curve.new()
	cresce.add_point(Vector2(0.0, 0.35))
	cresce.add_point(Vector2(1.0, 2.2))
	var tc := CurveTexture.new()
	tc.curve = cresce
	proc.scale_curve = tc
	var grad := Gradient.new()
	if fogo:
		grad.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
		grad.add_point(0.3, Color(1.0, 0.45, 0.1, 0.85))
		grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.06, 0.02, 0.0))
	else:
		grad.set_color(0, Color(1.0, 0.55, 0.18, 0.0))
		grad.add_point(0.05, Color(0.95, 0.42, 0.14, 0.9))
		grad.add_point(0.22, cor)
		grad.set_color(grad.get_point_count() - 1, Color(cor.r, cor.g, cor.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	proc.color_ramp = gt
	part.process_material = proc
	var quad := QuadMesh.new()
	quad.material = material_fumaca(fogo, 0.0 if fogo else 1.0)
	part.draw_pass_1 = quad
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
	part.global_position = ponto if onde == Vector3.INF else onde
	if atraso > 0.0:
		part.emitting = false
		get_tree().create_timer(atraso).timeout.connect(func(): part.emitting = true)
	else:
		part.emitting = true
	return part
