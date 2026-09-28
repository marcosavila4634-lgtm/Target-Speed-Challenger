class_name Terreno
extends Node3D
## Cânion gerado por código: mesas em degraus, rio sinuoso, corredores de voo livres
## e mesas sob as plataformas de lançamento. O terreno é mortal: tocar nele elimina o veículo,
## por isso não há colisão física — a checagem é feita por altura (altura_em).

const MEIO_INTERNO := 3400.0
const N_INTERNO := 513
const MEIO_EXTERNO := 14000.0
const N_EXTERNO := 257
const VERSAO_CACHE := 5

var perfil: PerfilRampa
var distancia_saida: float
var alturas_interno := PackedFloat32Array()
var alturas_externo := PackedFloat32Array()

var _ruido_base := FastNoiseLite.new()
var _ruido_detalhe := FastNoiseLite.new()
var _ruido_planalto := FastNoiseLite.new()


func gerar(p_perfil: PerfilRampa) -> void:
	perfil = p_perfil
	distancia_saida = Config.valor("mapa.distancia_saida_alvo", 2000)
	var semente: int = int(Config.valor("mapa.semente_terreno", 1967))
	_ruido_base.seed = semente
	_ruido_base.frequency = 1.0 / 1500.0
	_ruido_base.fractal_octaves = 4
	_ruido_detalhe.seed = semente + 11
	_ruido_detalhe.frequency = 1.0 / 260.0
	_ruido_detalhe.fractal_octaves = 3
	_ruido_planalto.seed = semente + 29
	_ruido_planalto.frequency = 1.0 / 900.0

	if not _carregar_cache():
		alturas_interno = _amostrar(MEIO_INTERNO, N_INTERNO, false)
		alturas_externo = _amostrar(MEIO_EXTERNO, N_EXTERNO, true)
		_salvar_cache()

	var mat := _material_terreno()
	add_child(_criar_malha(alturas_interno, MEIO_INTERNO, N_INTERNO, mat))
	add_child(_criar_malha(alturas_externo, MEIO_EXTERNO, N_EXTERNO, mat))
	_criar_agua()
	_criar_vegetacao()
	if Config.valor("grafico.bruma", true):
		_criar_bruma()


## Altura do terreno no ponto (x, z) do mundo.
func altura_em(x: float, z: float) -> float:
	if absf(x) < MEIO_INTERNO and absf(z) < MEIO_INTERNO:
		return _bilinear(alturas_interno, MEIO_INTERNO, N_INTERNO, x, z)
	return _bilinear(alturas_externo, MEIO_EXTERNO, N_EXTERNO, x, z)


func _bilinear(dados: PackedFloat32Array, meio: float, n: int, x: float, z: float) -> float:
	var passo := meio * 2.0 / (n - 1)
	var fx := clampf((x + meio) / passo, 0.0, n - 1.001)
	var fz := clampf((z + meio) / passo, 0.0, n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(dados[iz * n + ix], dados[iz * n + ix + 1], tx)
	var b := lerpf(dados[(iz + 1) * n + ix], dados[(iz + 1) * n + ix + 1], tx)
	return lerpf(a, b, tz)


func _amostrar(meio: float, n: int, externo: bool) -> PackedFloat32Array:
	var dados := PackedFloat32Array()
	dados.resize(n * n)
	var passo := meio * 2.0 / (n - 1)
	for iz in n:
		var z := -meio + iz * passo
		for ix in n:
			var x := -meio + ix * passo
			if externo and absf(x) < MEIO_INTERNO - 120.0 and absf(z) < MEIO_INTERNO - 120.0:
				dados[iz * n + ix] = -60.0  # escondido sob o terreno interno
			else:
				dados[iz * n + ix] = _altura_procedural(x, z)
	return dados


func _altura_procedural(x: float, z: float) -> float:
	var nb := _ruido_base.get_noise_2d(x, z)
	var nd := _ruido_detalhe.get_noise_2d(x, z)
	# Mesas em degraus: platôs planos separados por paredões.
	var mesa := smoothstep(-0.12, 0.22, nb + nd * 0.3)
	var s := mesa * 3.0
	var f := floorf(s)
	var r := smoothstep(0.55, 1.0, s - f)
	var t := (f + r) / 3.0
	var h_planalto := 320.0 + 55.0 * _ruido_planalto.get_noise_2d(x, z)
	var h := t * h_planalto + 10.0 + 6.0 * nd
	h = maxf(h, _pinaculos(x, z))

	# Rio sinuoso no fundo do cânion.
	var x_rio := -170.0 + 260.0 * sin(z / 760.0) + 90.0 * sin(z / 230.0 + 1.3)
	var d_rio := absf(x - x_rio)
	h = minf(h, lerpf(-7.0, h, smoothstep(10.0, 55.0, d_rio)))
	h = minf(h, lerpf(3.0, h, smoothstep(55.0, 230.0, d_rio)))

	# Área aberta ao redor do alvo.
	var r_centro := Vector2(x, z).length()
	h = minf(h, lerpf(8.0, h, smoothstep(420.0, 750.0, r_centro)))

	# Corredores de voo e complexos de lançamento de cada equipe.
	var xe := perfil.comprimento_horizontal
	var x_borda := perfil.pontos[perfil.indice_borda].x
	var altura_plataforma: float = Config.valor("mapa.plataforma_altura", 400)
	var p := Vector2(x, z)
	for eq in Config.EQUIPES:
		var d: Vector3 = eq.direcao
		var dir := Vector2(d.x, d.z)
		var ao_longo := p.dot(dir)
		if ao_longo < 0.0:
			continue
		var lateral := absf(p.dot(Vector2(-dir.y, dir.x)))
		if ao_longo < distancia_saida:
			var teto := lerpf(15.0, 90.0, ao_longo / distancia_saida)
			h = minf(h, lerpf(teto, h, smoothstep(230.0, 500.0, lateral)))
		# Sob a pista: o terreno fica abaixo do tabuleiro.
		var xp := distancia_saida + xe - ao_longo
		if xp > 0.0 and xp < xe:
			var teto_pista := perfil.altura_em(xp) - 14.0
			h = minf(h, lerpf(teto_pista, h, smoothstep(34.0, 120.0, lateral)))
		# Mesa sob a plataforma, terminando num paredão na borda da descida.
		if xp < x_borda + 5.0 and xp > -400.0:
			var peso := smoothstep(x_borda + 5.0, x_borda - 12.0, xp)
			peso *= smoothstep(190.0, 130.0, lateral)
			peso *= smoothstep(-400.0, -250.0, xp)
			h = maxf(h, lerpf(h, altura_plataforma - 5.0, peso))
	return h


func _criar_malha(dados: PackedFloat32Array, meio: float, n: int, mat: Material) -> MeshInstance3D:
	var passo := meio * 2.0 / (n - 1)
	var verts := PackedVector3Array()
	var normais := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.resize(n * n)
	normais.resize(n * n)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			verts[i] = Vector3(-meio + ix * passo, dados[i], -meio + iz * passo)
			var hl := dados[iz * n + maxi(ix - 1, 0)]
			var hr := dados[iz * n + mini(ix + 1, n - 1)]
			var hd := dados[maxi(iz - 1, 0) * n + ix]
			var hu := dados[mini(iz + 1, n - 1) * n + ix]
			normais[i] = Vector3(hl - hr, 2.0 * passo, hd - hu).normalized()
	indices.resize((n - 1) * (n - 1) * 6)
	var k := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			indices[k] = a; indices[k + 1] = b; indices[k + 2] = c
			indices[k + 3] = b; indices[k + 4] = d; indices[k + 5] = c
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normais
	arr[Mesh.ARRAY_INDEX] = indices
	var malha := ArrayMesh.new()
	malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _material_terreno() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terreno.gdshader")
	mat.set_shader_parameter("ruido", _textura_ruido(0.004, 5, 7))
	mat.set_shader_parameter("ruido_fino", _textura_ruido(0.02, 4, 13))
	mat.set_shader_parameter("nivel_agua", float(Config.valor("mapa.nivel_agua", 4)))
	return mat


static func _textura_ruido(freq: float, oitavas: int, semente: int) -> NoiseTexture2D:
	var r := FastNoiseLite.new()
	r.seed = semente
	r.frequency = freq
	r.fractal_octaves = oitavas
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = r
	return tex


func _criar_agua() -> void:
	var plano := PlaneMesh.new()
	plano.size = Vector2(MEIO_EXTERNO * 2.0, MEIO_EXTERNO * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = plano
	mi.position.y = Config.valor("mapa.nivel_agua", 4)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/agua.gdshader")
	mat.set_shader_parameter("ruido", _textura_ruido(0.03, 3, 41))
	mat.set_shader_parameter("normal_a", _textura_normal(0.02, 4, 43, 6.0))
	mat.set_shader_parameter("normal_b", _textura_normal(0.045, 3, 47, 4.0))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


static func _textura_normal(freq: float, oitavas: int, semente: int, relevo: float) -> NoiseTexture2D:
	var tex := _textura_ruido(freq, oitavas, semente)
	tex.as_normal_map = true
	tex.bump_strength = relevo
	return tex


## Pináculos e torres de rocha espalhados (como nas artes do dossiê). Uma candidata por célula de 300 m.
## Os corredores de voo, o rio e a área do alvo cortam o que ficar no caminho (aplicados depois).
func _pinaculos(x: float, z: float) -> float:
	const CELULA := 300.0
	# Fora da área de voo: nada num raio de 1,4 km do alvo nem perto dos corredores das equipes
	var r := Vector2(x, z).length()
	if r < 1400.0:
		return -INF
	for eq in Config.EQUIPES:
		var d: Vector3 = eq.direcao
		if Vector2(x, z).dot(Vector2(d.x, d.z)) > 0.0 and absf(Vector2(x, z).dot(Vector2(-d.z, d.x))) < 450.0:
			return -INF
	var cx := floori(x / CELULA)
	var cz := floori(z / CELULA)
	var h := -INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ix := cx + dx
			var iz := cz + dz
			var s := _hash2(ix, iz)
			if s > 0.42:
				continue
			var centro := Vector2((ix + 0.2 + 0.6 * _hash2(ix + 17, iz)) * CELULA, (iz + 0.2 + 0.6 * _hash2(ix, iz + 29)) * CELULA)
			var raio := 28.0 + 50.0 * _hash2(ix + 3, iz + 7)
			var altura := 80.0 + 230.0 * _hash2(ix + 11, iz + 13)
			# Borda irregular e em degraus: o raio encolhe com a altura (pináculo afunila no topo)
			var ang := atan2(z - centro.y, x - centro.x)
			var borda := raio * (1.0 + 0.18 * sin(ang * 3.0 + s * 20.0) + 0.1 * sin(ang * 7.0 + s * 9.0))
			var d := Vector2(x, z).distance_to(centro)
			if d > borda * 1.5:
				continue
			var nivel := smoothstep(borda * 1.5, borda, d)
			var degraus := floorf(nivel * 3.0) / 3.0
			var perfil := lerpf(degraus, nivel, 0.35)
			h = maxf(h, altura * perfil + 10.0)
	return h


static func _hash2(a: int, b: int) -> float:
	var n := a * 374761393 + b * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0


## Vegetação (ver Vegetacao): zimbros e sálvias nas áreas planas, mais densos e verdes perto do rio;
## capim seco em volta do alvo e nos topos das plataformas, onde a câmera chega perto.
func _criar_vegetacao() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) + 5
	var nivel_agua := float(Config.valor("mapa.nivel_agua", 4))
	var arvores := []
	var arbustos := []
	var capim := []
	var tentativas := 0
	while (arvores.size() < 4200 or arbustos.size() < 11000) and tentativas < 120000:
		tentativas += 1
		var x := rng.randf_range(-MEIO_INTERNO + 50.0, MEIO_INTERNO - 50.0)
		var z := rng.randf_range(-MEIO_INTERNO + 50.0, MEIO_INTERNO - 50.0)
		var h := altura_em(x, z)
		if h < nivel_agua + 1.5 or not _plano(x, z, 3.0):
			continue
		var perto_rio := h < nivel_agua + 30.0
		var chance_arvore := 0.45 if perto_rio else (0.28 if h > 150.0 else 0.1)
		if rng.randf() < chance_arvore:
			if arvores.size() < 4200:
				var verde := Color(0.85, 1.0, 0.8) if perto_rio else Color(1.0, 1.0, 0.9)
				arvores.append([Vector3(x, h - 0.2, z), rng.randf_range(0.7, 1.35) * (1.2 if perto_rio else 1.0), rng.randf() * TAU, verde * rng.randf_range(0.8, 1.1)])
		elif arbustos.size() < 11000:
			var tom := Color(0.9, 1.0, 0.85) if perto_rio else Color(1.0, 0.97, 0.92)
			arbustos.append([Vector3(x, h - 0.1, z), rng.randf_range(0.7, 1.6), rng.randf() * TAU, tom * rng.randf_range(0.8, 1.15)])
	# Capim: em volta do alvo e nos topos das plataformas (onde a câmera fica perto do chão)
	var zonas: Array = [[Vector2.ZERO, 750.0, 26000]]
	for eq in Config.EQUIPES:
		var d: Vector3 = eq.direcao
		var centro := Vector2(d.x, d.z) * (distancia_saida + perfil.comprimento_horizontal + 60.0)
		zonas.append([centro, 260.0, 7000])
	for zona: Array in zonas:
		var feitos := 0
		var t := 0
		while feitos < int(zona[2]) and t < int(zona[2]) * 3:
			t += 1
			var ang := rng.randf() * TAU
			var r: float = sqrt(rng.randf()) * float(zona[1])
			var x: float = zona[0].x + cos(ang) * r
			var z: float = zona[0].y + sin(ang) * r
			var h := altura_em(x, z)
			if h < nivel_agua + 0.6 or not _plano(x, z, 2.0):
				continue
			feitos += 1
			capim.append([Vector3(x, h - 0.05, z), rng.randf_range(0.7, 1.4), rng.randf() * TAU, Color(1, 1, 1) * rng.randf_range(0.75, 1.15)])
	Vegetacao.plantar(self, Vegetacao.Tipo.ZIMBRO, arvores, 700.0, 2800.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.SALVIA, arbustos, 400.0, 1400.0, false)
	Vegetacao.plantar(self, Vegetacao.Tipo.CAPIM, capim, 120.0, 300.0, false)


func _plano(x: float, z: float, limite: float) -> bool:
	var dx := altura_em(x + 6.0, z) - altura_em(x - 6.0, z)
	var dz := altura_em(x, z + 6.0) - altura_em(x, z - 6.0)
	return absf(dx) + absf(dz) <= limite


## Bancos de bruma baixos nos vales (só visual; não colidem).
func _criar_bruma() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) + 91
	var nivel_agua := float(Config.valor("mapa.nivel_agua", 4))
	var transformacoes: Array[Transform3D] = []
	var sementes := PackedFloat32Array()
	var tentativas := 0
	while transformacoes.size() < 320 and tentativas < 20000:
		tentativas += 1
		var x := rng.randf_range(-MEIO_INTERNO * 1.6, MEIO_INTERNO * 1.6)
		var z := rng.randf_range(-MEIO_INTERNO * 1.6, MEIO_INTERNO * 1.6)
		if Vector2(x, z).length() < 600.0:
			continue  # deixa a área do alvo limpa
		var h := altura_em(x, z)
		if h > 70.0:
			continue  # só nos vales
		var esc := rng.randf_range(90.0, 220.0)
		var y := maxf(h, nivel_agua) + rng.randf_range(12.0, 40.0)
		transformacoes.append(Transform3D(Basis.from_scale(Vector3.ONE * esc), Vector3(x, y, z)))
		sementes.append(rng.randf() * 10.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bruma.gdshader")
	mat.set_shader_parameter("ruido", _textura_ruido(0.02, 4, 97))
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = transformacoes.size()
	for i in transformacoes.size():
		mm.set_instance_transform(i, transformacoes[i])
		mm.set_instance_custom_data(i, Color(sementes[i], 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-MEIO_INTERNO * 2.0, -50.0, -MEIO_INTERNO * 2.0), Vector3(MEIO_INTERNO * 4.0, 400.0, MEIO_INTERNO * 4.0))
	add_child(mmi)


func _chave_cache() -> String:
	var partes := [VERSAO_CACHE, Config.valor("mapa", {}), perfil.comprimento_horizontal]
	return "user://cache/terreno_%s.bin" % str(partes).md5_text().substr(0, 12)


func _carregar_cache() -> bool:
	var caminho := _chave_cache()
	if not FileAccess.file_exists(caminho):
		return false
	var f := FileAccess.open(caminho, FileAccess.READ)
	if f == null:
		return false
	var a = f.get_var()
	var b = f.get_var()
	if a is PackedFloat32Array and b is PackedFloat32Array and a.size() == N_INTERNO * N_INTERNO and b.size() == N_EXTERNO * N_EXTERNO:
		alturas_interno = a
		alturas_externo = b
		return true
	return false


func _salvar_cache() -> void:
	DirAccess.make_dir_recursive_absolute("user://cache")
	var f := FileAccess.open(_chave_cache(), FileAccess.WRITE)
	if f:
		f.store_var(alturas_interno)
		f.store_var(alturas_externo)
