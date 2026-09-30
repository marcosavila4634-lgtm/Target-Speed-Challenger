class_name DragPista
extends Node3D
## Pista de arrancada de duas faixas. Largada em z = 0, chegada em z = -distancia (1/8 de milha),
## área de frenagem depois. Faixa do jogador em x = -largura/2, do rival em x = +largura/2.
## Estilos (jogo.json → drag.pistas):
## - "estadio" (TSC Dragway): pista real de arrancada — muros de concreto com placas de patrocínio,
##   alambrado, arquibancadas lotadas dos dois lados, torres de luz acesas, torre de controle,
##   placares de tempo na chegada, caixa de brita e rede no fim; mesas do cânion bem ao longe.
## - "canyon" (Reta do Canyon): a mesma pista no fundo do cânion, com arquibancada só na largada.

const PATROCINIOS := [
	["TSC", Color(0.08, 0.2, 0.6), Color.WHITE], ["KZULO STUDIOS", Color(0.05, 0.05, 0.07), Color(1.0, 0.75, 0.2)],
	["NITRO MAX", Color(0.75, 0.08, 0.06), Color.WHITE], ["CANYON OIL", Color(0.95, 0.72, 0.1), Color(0.1, 0.08, 0.05)],
	["RAPTOR PNEUS", Color(0.1, 0.1, 0.12), Color(0.9, 0.9, 0.9)], ["BRASA ENERGY", Color(0.95, 0.4, 0.05), Color.WHITE],
	["VELOX PEÇAS", Color(0.9, 0.9, 0.92), Color(0.75, 0.08, 0.06)], ["TURBO FORTE", Color(0.12, 0.45, 0.15), Color.WHITE],
	["FALCÃO SEGUROS", Color(0.04, 0.12, 0.3), Color(0.5, 0.8, 1.0)], ["DESERTO RÁDIO", Color(0.55, 0.12, 0.55), Color.WHITE],
]

var distancia := 201.168
var largura := 5.2
var frenagem := 380.0
var estilo := "estadio"
var nome := "TSC Dragway"
var publico_mat: ShaderMaterial
## Luzes do semáforo por faixa (0 = jogador, 1 = rival)
var _luzes: Array = [{}, {}]
var _placar: Array[Label3D] = []
var _placar_vel: Array[Label3D] = []
var _placar_vence: Array[StandardMaterial3D] = []
var _ruido: NoiseTexture2D
var _mat_concreto: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func montar(p_estilo := "estadio", p_nome := "TSC Dragway") -> void:
	estilo = p_estilo
	nome = p_nome
	_rng.seed = 90210
	var c: Dictionary = Config.valor("drag", {})
	distancia = float(c.get("distancia_m", 201.168))
	largura = float(c.get("largura_faixa", 5.2))
	frenagem = float(c.get("frenagem_m", 380))
	_ruido = Terreno._textura_ruido(0.03, 4, 311)
	_mat_concreto = ShaderMaterial.new()
	_mat_concreto.shader = load("res://shaders/concreto.gdshader")
	_mat_concreto.set_shader_parameter("ruido", _ruido)
	_mat_concreto.set_shader_parameter("placa", Vector2(3.0, 1.1))
	_mat_concreto.set_shader_parameter("altura_poeira", 0.5)
	_mat_concreto.set_shader_parameter("sujeira", 0.25)
	_chao()
	_asfalto()
	_muros()
	_cerca()
	_arvore()
	_linha_de_largada()
	_portico_chegada()
	_placares()
	_torres_luz()
	_fim_da_pista()
	if estilo == "estadio":
		_arquibancadas(30.0, -(distancia + 60.0), 20)
		_torre_controle()
		_paredoes(420.0, 70.0)
	else:
		_arquibancadas(25.0, -35.0, 10)
		_paredoes(40.0, 150.0)


func x_faixa(indice: int) -> float:
	return (-0.5 if indice == 0 else 0.5) * largura


func _x_muro() -> float:
	return largura + 1.6


# ------------------------------------------------------------------ piso

func _chao() -> void:
	var plano := PlaneMesh.new()
	plano.size = Vector2(1800, 3000)
	var mi := MeshInstance3D.new()
	mi.mesh = plano
	mi.position = Vector3(0, -0.03, -500)
	mi.material_override = _material_rocha()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Faixa de serviço de asfalto velho entre o muro e as arquibancadas
	var serv := PlaneMesh.new()
	serv.size = Vector2(28.0, distancia + frenagem + 120.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _ruido
	m.albedo_color = Color(0.3, 0.29, 0.28)
	m.uv1_scale = Vector3(6, 60, 1)
	m.roughness = 0.9
	for lado: float in [-1.0, 1.0]:
		var s := MeshInstance3D.new()
		s.mesh = serv
		s.position = Vector3(lado * (_x_muro() + 14.3), -0.01, 60.0 - serv.size.y * 0.5)
		s.material_override = m
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)


func _asfalto() -> void:
	var comp := distancia + frenagem + 120.0
	var plano := PlaneMesh.new()
	plano.size = Vector2(_x_muro() * 2.0, comp)
	var mi := MeshInstance3D.new()
	mi.mesh = plano
	mi.position = Vector3(0, 0.0, 60.0 - comp * 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/drag_pista.gdshader")
	mat.set_shader_parameter("ruido", _ruido)
	mat.set_shader_parameter("largura_faixa", largura)
	mat.set_shader_parameter("distancia", distancia)
	mat.set_shader_parameter("brilho", 1.0 if estilo == "estadio" else 0.7)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _material_rocha() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terreno.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.004, 5, 7))
	mat.set_shader_parameter("ruido_fino", Terreno._textura_ruido(0.02, 4, 13))
	mat.set_shader_parameter("nivel_agua", -50.0)
	return mat


# ------------------------------------------------------------------ muros, placas e alambrado

func _muros() -> void:
	var z_ini := 55.0
	var z_fim := -(distancia + frenagem)
	var comp := z_ini - z_fim
	var perfil := PackedVector2Array([Vector2(-0.38, 0), Vector2(-0.3, 0.25), Vector2(-0.12, 0.45), Vector2(-0.1, 1.05),
		Vector2(0.1, 1.05), Vector2(0.12, 0.45), Vector2(0.3, 0.25), Vector2(0.38, 0)])
	var branco := _mat_concreto.duplicate() as ShaderMaterial
	branco.set_shader_parameter("cor_base", Vector3(0.8, 0.8, 0.78))
	branco.set_shader_parameter("cor_mancha", Vector3(0.6, 0.6, 0.58))
	for lado: float in [-1.0, 1.0]:
		var x := lado * _x_muro()
		var mi := MeshInstance3D.new()
		mi.mesh = _extrusao(perfil, comp)
		mi.position = Vector3(x, 0, z_ini)
		mi.material_override = branco
		add_child(mi)
		var corpo := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var caixa := BoxShape3D.new()
		caixa.size = Vector3(0.7, 1.05, comp)
		cs.shape = caixa
		corpo.position = Vector3(x, 0.52, z_ini - comp * 0.5)
		corpo.add_child(cs)
		add_child(corpo)
		# Placas de patrocínio pintadas na face interna, lado a lado
		var z := 40.0
		var i := 3 if lado > 0.0 else 0
		while z > z_fim + 10.0:
			_placa_muro(Vector3(x - lado * 0.14, 0.78, z - 5.8), lado, PATROCINIOS[i % PATROCINIOS.size()])
			z -= 11.6
			i += 1


## Placa pintada de 11 m x 0,55 m na face interna do muro (fundo colorido + nome).
func _placa_muro(pos: Vector3, lado: float, pat: Array) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(11.2, 0.56)
	var p := MeshInstance3D.new()
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.albedo_color = pat[1]
	m.roughness = 0.55
	p.material_override = m
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.basis = Basis(Vector3.UP, -lado * PI * 0.5)
	p.position = pos
	add_child(p)
	var t := Label3D.new()
	t.text = pat[0]
	t.font = load("res://assets/fontes/RacingSansOne-Regular.ttf")
	t.font_size = 64
	t.pixel_size = 0.0065
	t.modulate = pat[2]
	t.outline_size = 0
	t.shaded = true
	t.double_sided = false
	t.basis = p.basis
	t.position = pos - Vector3(lado * 0.01, 0, 0)
	add_child(t)


## Alambrado em cima dos muros, com postes a cada 4 m e cabo no alto.
func _cerca() -> void:
	var z_ini := 55.0
	var z_fim := -(distancia + frenagem)
	var comp := z_ini - z_fim
	var altura := 3.2
	var mat := ShaderMaterial.new()
	mat.shader = _shader_cerca_metros(comp, altura)
	var poste := BoxMesh.new()
	poste.size = Vector3(0.08, altura + 0.2, 0.08)
	var mat_poste := StandardMaterial3D.new()
	mat_poste.albedo_color = Color(0.42, 0.43, 0.45)
	mat_poste.metallic = 0.8
	mat_poste.roughness = 0.4
	for lado: float in [-1.0, 1.0]:
		var x := lado * _x_muro()
		var q := QuadMesh.new()
		q.size = Vector2(comp, altura)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.basis = Basis(Vector3.UP, PI * 0.5)
		mi.position = Vector3(x, 1.05 + altura * 0.5, z_ini - comp * 0.5)
		add_child(mi)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = poste
		var n := int(comp / 4.0)
		mm.instance_count = n
		for k in n:
			mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(x, 1.05 + (altura + 0.2) * 0.5, z_ini - k * 4.0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat_poste
		add_child(mmi)
		var cabo := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.05, comp)
		cabo.mesh = bm
		cabo.material_override = mat_poste
		cabo.position = Vector3(x, 1.05 + altura, z_ini - comp * 0.5)
		add_child(cabo)


## Alambrado com o losango medido em metros (o quad tem comp x altura e UV de 0 a 1).
func _shader_cerca_metros(comp: float, altura: float) -> Shader:
	var s := Shader.new()
	s.code = (load("res://shaders/drag_cerca.gdshader") as Shader).code.replace(
		"vec2 q = vec2(UV.x + UV.y, UV.x - UV.y) / malha;",
		"vec2 m = UV * vec2(%.3f, %.3f);\n\tvec2 q = vec2(m.x + m.y, m.x - m.y) / malha;" % [comp, altura])
	return s


## Extrusão de um perfil (x, y) ao longo de -Z por `comp` metros.
func _extrusao(perfil: PackedVector2Array, comp: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in perfil.size() - 1:
		var a := perfil[i]
		var b := perfil[i + 1]
		var v0 := Vector3(a.x, a.y, 0)
		var v1 := Vector3(b.x, b.y, 0)
		var v2 := Vector3(b.x, b.y, -comp)
		var v3 := Vector3(a.x, a.y, -comp)
		st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v1)
		st.add_vertex(v0); st.add_vertex(v3); st.add_vertex(v2)
	st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ arquibancadas e público

## Arquibancadas em degraus dos dois lados, de z_ini a z_fim, com `fileiras` degraus lotados.
func _arquibancadas(z_ini: float, z_fim: float, fileiras: int) -> void:
	var comp := z_ini - z_fim
	var x0 := _x_muro() + 7.0
	var prof := 0.85
	var sobe := 0.42
	var pessoa := _malha_pessoa()
	publico_mat = ShaderMaterial.new()
	publico_mat.shader = load("res://shaders/drag_publico.gdshader")
	var cores := [Color(0.1, 0.25, 0.7), Color(0.85, 0.1, 0.08), Color(0.95, 0.95, 0.95), Color(0.08, 0.08, 0.1),
		Color(1.0, 0.75, 0.1), Color(0.2, 0.55, 0.25), Color(0.95, 0.45, 0.1), Color(0.5, 0.5, 0.55), Color(0.35, 0.2, 0.6)]
	for lado: float in [-1.0, 1.0]:
		# Degraus (uma caixa por fileira)
		for f in fileiras:
			var b := BoxMesh.new()
			b.size = Vector3(prof, sobe * (f + 1), comp)
			var mi := MeshInstance3D.new()
			mi.mesh = b
			mi.material_override = _mat_concreto
			mi.position = Vector3(lado * (x0 + prof * (f + 0.5)), sobe * (f + 1) * 0.5, z_ini - comp * 0.5)
			add_child(mi)
		# Parede de fundo
		var fundo := BoxMesh.new()
		fundo.size = Vector3(0.4, sobe * fileiras + 3.0, comp)
		var mf := MeshInstance3D.new()
		mf.mesh = fundo
		mf.material_override = _mat_concreto
		mf.position = Vector3(lado * (x0 + prof * fileiras + 0.2), (sobe * fileiras + 3.0) * 0.5, z_ini - comp * 0.5)
		add_child(mf)
		# Público: uma pessoa a cada ~0,55 m, 85% de ocupação
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = pessoa
		var por_fila := int(comp / 0.55)
		var lista: Array[Transform3D] = []
		var dados: Array[Color] = []
		for f in fileiras:
			for k in por_fila:
				if _rng.randf() > 0.85:
					continue
				var pos := Vector3(lado * (x0 + prof * (f + 0.5) + _rng.randf_range(-0.12, 0.12)), sobe * (f + 1),
					z_ini - (k + _rng.randf_range(0.1, 0.9)) * 0.55)
				var giro := Basis(Vector3.UP, (-PI * 0.5 if lado < 0.0 else PI * 0.5) + _rng.randf_range(-0.5, 0.5))
				lista.append(Transform3D(giro.scaled(Vector3.ONE * _rng.randf_range(0.9, 1.08)), pos))
				var cor: Color = cores[_rng.randi() % cores.size()]
				cor = cor.lerp(Color(_rng.randf(), _rng.randf(), _rng.randf()), 0.25)
				dados.append(Color(cor.r, cor.g, cor.b, _rng.randf()))
		mm.instance_count = lista.size()
		for k in lista.size():
			mm.set_instance_transform(k, lista[k])
			mm.set_instance_custom_data(k, dados[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = publico_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Pessoa bem simples (vista de longe): pernas, tronco, braços e cabeça.
func _malha_pessoa() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var partes := [
		[Vector3(0, 0.45, 0), Vector3(0.3, 0.9, 0.2)],       # pernas
		[Vector3(0, 1.1, 0), Vector3(0.42, 0.5, 0.24)],      # tronco
		[Vector3(-0.25, 1.05, 0), Vector3(0.1, 0.5, 0.12)],  # braços
		[Vector3(0.25, 1.05, 0), Vector3(0.1, 0.5, 0.12)],
		[Vector3(0, 1.48, 0), Vector3(0.2, 0.24, 0.22)],     # cabeça (y > 1,35: cor de pele)
	]
	for pt: Array in partes:
		var b := BoxMesh.new()
		b.size = pt[1]
		var arr := b.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var normais: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			st.set_normal(normais[i])
			st.add_vertex(verts[i] + (pt[0] as Vector3))
	return st.commit()


## Torcida agitada (0..1): pulos e balanço.
func animar_publico(nivel: float) -> void:
	if publico_mat:
		publico_mat.set_shader_parameter("animacao", nivel)


func _torre_controle() -> void:
	var x := -(_x_muro() + 7.0 + 0.85 * 20 + 9.0)
	var base := Vector3(x, 0, -8.0)
	_caixa(Vector3(9.0, 14.0, 12.0), base + Vector3(0, 7.0, 0), Color(0.75, 0.76, 0.78), null, 0.2)
	var vidro := _caixa(Vector3(10.0, 4.0, 13.0), base + Vector3(0.5, 16.0, 0), Color(0.08, 0.12, 0.18), null, 0.9)
	(vidro.material_override as StandardMaterial3D).roughness = 0.05
	_caixa(Vector3(11.0, 0.5, 14.0), base + Vector3(0.5, 18.25, 0), Color(0.2, 0.2, 0.22), null, 0.4)
	var t := Label3D.new()
	t.text = nome.to_upper()
	t.font = load("res://assets/fontes/RacingSansOne-Regular.ttf")
	t.font_size = 200
	t.pixel_size = 0.012
	t.modulate = Color(0.3, 0.6, 1.0)
	t.outline_size = 0
	t.position = base + Vector3(4.6, 11.0, 0)
	t.rotation.y = PI * 0.5
	add_child(t)


# ------------------------------------------------------------------ cânion

## Paredões dos dois lados: chão plano até `recuo_base` metros, talude e paredão em degraus.
func _paredoes(recuo_base: float, alto_base: float) -> void:
	var ruido := FastNoiseLite.new()
	ruido.seed = 4417
	ruido.frequency = 0.004
	ruido.fractal_octaves = 4
	var mat := _material_rocha()
	var nx := 56
	var nz := 150
	var z0 := 500.0
	var z1 := -1700.0
	for lado: float in [-1.0, 1.0]:
		var pontos := PackedVector3Array()
		for iz in nz + 1:
			var z := lerpf(z0, z1, float(iz) / nz)
			var recuo := recuo_base + 15.0 + ruido.get_noise_2d(lado * 300.0, z * 0.6) * 35.0
			var alto := alto_base + ruido.get_noise_2d(z * 0.3, lado * 900.0) * alto_base * 0.6
			for ix in nx + 1:
				var u := float(ix) / nx
				var dx := u * u * 900.0
				var x := lado * (14.0 + dx)
				var t := clampf((dx - recuo) / 70.0, 0.0, 1.0)
				var h := smoothstep(0.0, 1.0, t) * alto
				h = lerpf(h, floorf(h / 28.0) * 28.0 + smoothstep(0.55, 1.0, fmod(h, 28.0) / 28.0) * 28.0, 0.6 * t)
				h += ruido.get_noise_2d(x * 3.0, z * 3.0) * 6.0 * t
				pontos.append(Vector3(x, maxf(h, 0.0) - 0.05, z))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for iz in nz:
			for ix in nx:
				var a := iz * (nx + 1) + ix
				var b := a + 1
				var c := a + nx + 1
				var d := c + 1
				if lado < 0.0:
					st.add_vertex(pontos[a]); st.add_vertex(pontos[b]); st.add_vertex(pontos[c])
					st.add_vertex(pontos[b]); st.add_vertex(pontos[d]); st.add_vertex(pontos[c])
				else:
					st.add_vertex(pontos[a]); st.add_vertex(pontos[c]); st.add_vertex(pontos[b])
					st.add_vertex(pontos[b]); st.add_vertex(pontos[c]); st.add_vertex(pontos[d])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		add_child(mi)


# ------------------------------------------------------------------ semáforo e largada

func _material_luz(cor: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = cor.darkened(0.8)
	m.emission_enabled = true
	m.emission = cor
	m.emission_energy_multiplier = 0.0
	m.roughness = 0.15
	return m


func _caixa(tamanho: Vector3, pos: Vector3, cor: Color, pai: Node3D = null, metal := 0.6) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = tamanho
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = cor
	m.metallic = metal
	m.roughness = 0.45
	mi.material_override = m
	(pai if pai else self).add_child(mi)
	return mi


## Árvore de natal entre as faixas, 7 m depois da largada, virada para os carros: coluna de aço,
## caixa preta com pré-estágio/estágio, 3 amarelas, verde e vermelha por faixa, câmera de TV no alto.
func _arvore() -> void:
	var arv := Node3D.new()
	arv.name = "Arvore"
	arv.position = Vector3(0, 0, -7.0)
	add_child(arv)
	var escuro := Color(0.04, 0.045, 0.05)
	_caixa(Vector3(1.2, 0.35, 1.2), Vector3(0, 0.17, 0), Color(0.55, 0.55, 0.57), arv, 0.1)
	_caixa(Vector3(0.18, 3.0, 0.18), Vector3(0, 1.5, 0), Color(0.3, 0.31, 0.33), arv)
	_caixa(Vector3(1.05, 2.7, 0.36), Vector3(0, 2.85, 0), escuro, arv)
	_caixa(Vector3(0.14, 0.9, 0.14), Vector3(0, 4.6, 0), Color(0.3, 0.31, 0.33), arv)
	_caixa(Vector3(0.5, 0.3, 0.3), Vector3(0, 5.1, 0), Color(0.12, 0.12, 0.13), arv)
	var esfera := SphereMesh.new()
	esfera.radius = 0.12
	esfera.height = 0.24
	var pequena := SphereMesh.new()
	pequena.radius = 0.065
	pequena.height = 0.13
	for f in 2:
		var x := -0.25 if f == 0 else 0.25
		var luzes := {"amarela": [], "pre": [], "stage": []}
		var y := 4.02
		for chave in ["pre", "stage"]:
			for k in 2:
				var mi := MeshInstance3D.new()
				mi.mesh = pequena
				mi.material_override = _material_luz(Color(1.0, 0.85, 0.5))
				mi.position = Vector3(x + (k - 0.5) * 0.15, y, 0.19)
				arv.add_child(mi)
				luzes[chave].append(mi.material_override)
			y -= 0.19
		y -= 0.14
		for i in 5:
			var cor := Color(1.0, 0.62, 0.05)
			if i == 3:
				cor = Color(0.15, 1.0, 0.25)
			elif i == 4:
				cor = Color(1.0, 0.1, 0.06)
			var mi := MeshInstance3D.new()
			mi.mesh = esfera
			mi.material_override = _material_luz(cor)
			mi.position = Vector3(x, y, 0.2)
			arv.add_child(mi)
			_caixa(Vector3(0.3, 0.03, 0.18), Vector3(x, y + 0.15, 0.27), escuro, arv)
			if i < 3:
				luzes.amarela.append(mi.material_override)
			elif i == 3:
				luzes["verde"] = mi.material_override
			else:
				luzes["vermelha"] = mi.material_override
			y -= 0.36
		_luzes[f] = luzes


## Liga as luzes do semáforo das duas faixas: amarelas acesas (0..3), verde, e vermelha por faixa.
func semaforo(amarelas: int, verde: bool, vermelha: Array = [false, false], estagiado := true) -> void:
	for f in 2:
		var l: Dictionary = _luzes[f]
		for m: StandardMaterial3D in l.pre + l.stage:
			m.emission_energy_multiplier = 3.0 if estagiado else 0.0
		for i in 3:
			(l.amarela[i] as StandardMaterial3D).emission_energy_multiplier = 7.0 if i < amarelas and not verde else 0.0
		(l.verde as StandardMaterial3D).emission_energy_multiplier = 9.0 if verde and not vermelha[f] else 0.0
		(l.vermelha as StandardMaterial3D).emission_energy_multiplier = 9.0 if vermelha[f] else 0.0


## Sensores de estágio (postes baixos amarelos) e pórtico de largada com o nome da pista.
func _linha_de_largada() -> void:
	for f in 2:
		for lado: float in [-1.0, 1.0]:
			var x := x_faixa(f) + lado * (largura * 0.5 - 0.12)
			if absf(x) < 0.4:
				continue
			_caixa(Vector3(0.09, 0.3, 0.09), Vector3(x, 0.15, 0.4), Color(0.9, 0.75, 0.1), null, 0.3)
			_caixa(Vector3(0.09, 0.3, 0.09), Vector3(x, 0.15, -0.4), Color(0.9, 0.75, 0.1), null, 0.3)
	var aco := Color(0.14, 0.15, 0.17)
	var larg := _x_muro() * 2.0 + 1.0
	for lado: float in [-1.0, 1.0]:
		_caixa(Vector3(0.5, 8.0, 0.5), Vector3(lado * larg * 0.5, 4.0, 22.0), aco)
	_caixa(Vector3(larg + 0.5, 1.6, 0.4), Vector3(0, 7.6, 22.0), Color(0.03, 0.05, 0.12), null, 0.3)
	var t := Label3D.new()
	t.text = nome.to_upper()
	t.font = load("res://assets/fontes/RacingSansOne-Regular.ttf")
	t.font_size = 160
	t.pixel_size = 0.006
	t.modulate = Color(0.35, 0.65, 1.0)
	t.outline_size = 0
	t.position = Vector3(0, 7.6, 21.78)
	t.rotation.y = PI
	add_child(t)


# ------------------------------------------------------------------ chegada e placares

func _portico_chegada() -> void:
	var z := -distancia
	var aco := Color(0.12, 0.13, 0.15)
	var larg := _x_muro() * 2.0 + 1.0
	for lado: float in [-1.0, 1.0]:
		_caixa(Vector3(0.5, 7.5, 0.5), Vector3(lado * larg * 0.5, 3.75, z), aco)
	_caixa(Vector3(larg + 0.5, 1.4, 0.4), Vector3(0, 7.2, z), Color(0.03, 0.05, 0.12), null, 0.3)
	var titulo := Label3D.new()
	titulo.text = "CHEGADA"
	titulo.font = load("res://assets/fontes/RacingSansOne-Regular.ttf")
	titulo.font_size = 150
	titulo.pixel_size = 0.006
	titulo.modulate = Color(1.0, 0.95, 0.9)
	titulo.outline_size = 0
	titulo.position = Vector3(0, 7.2, z + 0.22)
	add_child(titulo)
	var neon := _caixa(Vector3(larg, 0.08, 0.1), Vector3(0, 6.45, z + 0.22), Color(0.2, 0.45, 1.0), null, 0.0)
	var mn := neon.material_override as StandardMaterial3D
	mn.emission_enabled = true
	mn.emission = Color(0.25, 0.5, 1.0)
	mn.emission_energy_multiplier = 4.0


## Placares grandes de LED fora do alambrado, um por faixa: tempo, velocidade e luz de vencedor.
func _placares() -> void:
	var z := -distancia + 35.0
	for f in 2:
		var lado := -1.0 if f == 0 else 1.0
		var base := Vector3(lado * (_x_muro() + 3.5), 0, z)
		_caixa(Vector3(0.35, 7.0, 0.35), base + Vector3(0, 3.5, 0), Color(0.2, 0.2, 0.22))
		_caixa(Vector3(0.3, 3.2, 6.0), base + Vector3(0, 8.4, 0), Color(0.02, 0.02, 0.025), null, 0.2)
		var giro := Basis(Vector3.UP, -lado * PI * 0.5)
		var face := base + Vector3(-lado * 0.17, 0, 0)
		var tempo := Label3D.new()
		tempo.text = "0.000"
		tempo.font_size = 150
		tempo.pixel_size = 0.009
		tempo.modulate = Color(1.0, 0.55, 0.1)
		tempo.outline_size = 0
		tempo.basis = giro
		tempo.position = face + Vector3(0, 9.0, 0)
		add_child(tempo)
		_placar.append(tempo)
		var vel := Label3D.new()
		vel.text = "0 km/h"
		vel.font_size = 90
		vel.pixel_size = 0.009
		vel.modulate = Color(1.0, 0.55, 0.1)
		vel.outline_size = 0
		vel.basis = giro
		vel.position = face + Vector3(0, 7.6, 0)
		add_child(vel)
		_placar_vel.append(vel)
		var luz := _caixa(Vector3(0.1, 0.5, 0.5), face + Vector3(0, 9.0, lado * 2.4), Color(0.1, 0.3, 0.1), null, 0.0)
		var ml := luz.material_override as StandardMaterial3D
		ml.emission_enabled = true
		ml.emission = Color(0.2, 1.0, 0.3)
		ml.emission_energy_multiplier = 0.0
		_placar_vence.append(ml)


func placar(faixa: int, tempo: float, kmh: float, venceu := false) -> void:
	_placar[faixa].text = ("%.3f" % tempo) if tempo < INF else "--.---"
	_placar_vel[faixa].text = "%d km/h" % roundi(kmh)
	_placar_vence[faixa].emission_energy_multiplier = 8.0 if venceu else 0.0


## Fim da área de frenagem: caixa de brita e rede de contenção.
func _fim_da_pista() -> void:
	var z := -(distancia + frenagem)
	var brita := PlaneMesh.new()
	brita.size = Vector2(_x_muro() * 2.0, 60.0)
	var mi := MeshInstance3D.new()
	mi.mesh = brita
	mi.position = Vector3(0, 0.01, z - 30.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.62, 0.5, 0.38)
	m.albedo_texture = _ruido
	m.uv1_scale = Vector3(8, 8, 1)
	m.roughness = 1.0
	mi.material_override = m
	add_child(mi)
	for lado: float in [-1.0, 1.0]:
		_caixa(Vector3(0.3, 5.0, 0.3), Vector3(lado * _x_muro(), 2.5, z - 58.0), Color(0.9, 0.75, 0.1))
	var rede := QuadMesh.new()
	rede.size = Vector2(_x_muro() * 2.0, 4.5)
	var r := MeshInstance3D.new()
	r.mesh = rede
	var mr := ShaderMaterial.new()
	mr.shader = _shader_cerca_metros(_x_muro() * 2.0, 4.5)
	mr.set_shader_parameter("cor_arame", Color(0.9, 0.9, 0.9))
	mr.set_shader_parameter("malha", 0.25)
	r.material_override = mr
	r.position = Vector3(0, 2.4, z - 58.0)
	add_child(r)


# ------------------------------------------------------------------ luzes

## Torres de iluminação acesas entre o muro e as arquibancadas.
func _torres_luz() -> void:
	var z := 20.0
	var i := 0
	var fim := -(distancia + frenagem - 30.0)
	while z > fim:
		for lado: float in [-1.0, 1.0]:
			_torre_luz(Vector3(lado * (_x_muro() + 3.2), 0, z + (16.0 if lado > 0.0 else 0.0)), lado, i < 3)
		z -= 36.0
		i += 1


func _torre_luz(p: Vector3, lado: float, com_luz: bool) -> void:
	_caixa(Vector3(0.35, 18.0, 0.35), p + Vector3(0, 9.0, 0), Color(0.35, 0.36, 0.38))
	_caixa(Vector3(0.4, 1.6, 3.2), p + Vector3(-lado * 0.3, 18.6, 0), Color(0.15, 0.15, 0.16))
	var lampada := BoxMesh.new()
	lampada.size = Vector3(0.12, 0.5, 0.6)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 0.97, 0.9)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.94, 0.82)
	m.emission_energy_multiplier = 6.0
	for k in 8:
		var l := MeshInstance3D.new()
		l.mesh = lampada
		l.material_override = m
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.position = p + Vector3(-lado * 0.52, 18.2 + (k / 4) * 0.7, -1.1 + (k % 4) * 0.73)
		add_child(l)
	if com_luz:
		# Algumas torres perto da largada iluminam de verdade (sem sombra, para não pesar)
		var s := SpotLight3D.new()
		s.light_color = Color(1.0, 0.93, 0.82)
		s.light_energy = 6.0
		s.spot_range = 60.0
		s.spot_angle = 40.0
		s.shadow_enabled = false
		s.light_cull_mask = 0xFFFFF & ~DragCockpit.CAMADA_INTERIOR   # sem sombra: o teto não taparia o cockpit
		add_child(s)
		s.position = p + Vector3(-lado * 0.8, 18.0, 0)
		s.look_at(Vector3(0, 0, p.z - 12.0))
