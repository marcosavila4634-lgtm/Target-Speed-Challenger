class_name DragPista
extends Node3D
## Pista de arrancada de duas faixas. Largada em z = 0, chegada em z = -distancia (1/8 de milha),
## área de frenagem depois. Faixa do jogador em x = -largura/2, do rival em x = +largura/2.
## Estilos (jogo.json → drag.pistas):
## - "estadio" (TSC Dragway): pista real de arrancada — muros de concreto com placas de patrocínio,
##   alambrado, arquibancadas lotadas dos dois lados (torcida em cartões), torres de luz acesas, torre de controle,
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
## Torcida: 18 pessoas em 3 poses (gerado por tools/ambiente/torcida_atlas.gd).
const ATLAS_TORCIDA := "res://assets/drag/torcida_atlas.png"
const PESSOAS_ATLAS := 18
const GRADE_CONTENCAO := "res://assets/drag/grade_contencao.glb"
## Texturas do asfalto, da brita e dos pneus (tools/ambiente/texturas_drag.gd).
const TEX := "res://assets/drag/"
const LOGO := "res://assets/ui/logo_tsc.png"
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
	distancia = Sessao.drag_distancia()
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
	_baloes_no_ceu()
	if estilo == "estadio":
		_arquibancadas(30.0, -(distancia + 60.0), 20)
		_torre_controle()
		_paredoes(420.0, 70.0)
		_montanhas()
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
	var m := StandardMaterial3D.new()   # asfalto velho, gasto e mais claro que o da pista
	m.albedo_texture = load(TEX + "asfalto.png")
	m.albedo_color = Color(0.62, 0.6, 0.57)
	m.normal_enabled = true
	m.normal_texture = load(TEX + "asfalto_normal.png")
	m.uv1_scale = Vector3(serv.size.x / 3.5, serv.size.y / 3.5, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
	mat.set_shader_parameter("asfalto", load(TEX + "asfalto.png"))
	mat.set_shader_parameter("asfalto_normal", load(TEX + "asfalto_normal.png"))
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
			var pos_placa := Vector3(x - lado * 0.14, 0.78, z - 5.8)
			if i % 4 == 1:   # uma a cada quatro é da logo do jogo
				_placa_logo(pos_placa, lado)
			else:
				_placa_muro(pos_placa, lado, PATROCINIOS[i % PATROCINIOS.size()])
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
	# Pessoa = cartão virado para a câmera (o shader monta o quadrado; a malha só dá a caixa de corte)
	var pessoa := QuadMesh.new()
	pessoa.size = Vector2(1.2, 2.4)
	pessoa.center_offset = Vector3(0, 1.2, 0)
	publico_mat = ShaderMaterial.new()
	publico_mat.shader = load("res://shaders/drag_publico.gdshader")
	publico_mat.set_shader_parameter("atlas", load(ATLAS_TORCIDA))
	publico_mat.set_shader_parameter("pessoas", float(PESSOAS_ATLAS))
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
		# Painéis gigantes de LED com a logo do jogo no alto do fundo
		var paineis := maxi(1, int(comp / 95.0))
		for k in paineis:
			_painel_gigante(lado * (x0 + prof * fileiras + 0.2), sobe * fileiras + 3.0, z_ini - comp * (k + 0.5) / paineis, lado)
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
				# Pessoa do atlas, empolgação, espelhada e fase (ver shaders/drag_publico.gdshader)
				var quem := (_rng.randi() % PESSOAS_ATLAS + 0.5) / PESSOAS_ATLAS
				dados.append(Color(quem, _rng.randf_range(0.2, 0.9), float(_rng.randf() < 0.5), _rng.randf()))
		mm.instance_count = lista.size()
		for k in lista.size():
			mm.set_instance_transform(k, lista[k])
			mm.set_instance_custom_data(k, dados[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = publico_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	_grades_contencao(x0 - 0.6, z_ini, maxf(z_fim, z_ini - 100.0))


## Grades de contenção de metal (modelo Grade de Contenção) enfileiradas na frente das
## arquibancadas, dos dois lados, de z_ini a z_fim; só no trecho da largada (a peça é detalhada).
func _grades_contencao(x: float, z_ini: float, z_fim: float) -> void:
	if not ResourceLoader.exists(GRADE_CONTENCAO):
		return
	var cena: Node = (load(GRADE_CONTENCAO) as PackedScene).instantiate()
	var peca := cena.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var passo := 2.1   # comprimento da grade (2,08 m) com a folga do engate
	var n := int((z_ini - z_fim) / passo)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = peca.mesh
	mm.instance_count = n * 2
	var base := Basis.IDENTITY   # escala e giro do modelo (a cena não está na árvore)
	var no: Node = peca
	while no != cena.get_parent():
		if no is Node3D:
			base = (no as Node3D).basis * base
		no = no.get_parent()
	var giro := Basis(Vector3.UP, PI * 0.5) * base   # comprimento ao longo de Z
	for k in n:
		for i in 2:
			var lado := -1.0 if i == 0 else 1.0
			var pos := Vector3(lado * x, 0.0, z_ini - (k + 0.5) * passo)
			mm.set_instance_transform(k * 2 + i, Transform3D(giro.rotated(Vector3.UP, _rng.randf_range(-0.02, 0.02)), pos))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	cena.free()


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
	# Banner gigante da logo na face da torre virada para a pista
	_quadro_logo(Vector2(11.0, 11.0 / 2.72), base + Vector3(4.52, 5.5, 0), -1.0, _mat_logo(1.2))


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


## Montanhas avulsas do cânion no deserto entre a pista e os paredões (pedido do dono), de rocha
## em degraus como os paredões. [x, z, raio da base, altura, 1 = pico / 0 = mesa]; longe dos balões.
func _montanhas() -> void:
	var lista := [
		[-150.0, -60.0, 70.0, 140.0, 1.0], [-235.0, -330.0, 95.0, 170.0, 0.0], [-125.0, -540.0, 55.0, 110.0, 1.0],
		[150.0, -110.0, 65.0, 130.0, 0.0], [255.0, -390.0, 95.0, 165.0, 1.0], [210.0, 110.0, 55.0, 115.0, 1.0],
	]
	var ruido := FastNoiseLite.new()
	ruido.seed = 5521
	ruido.frequency = 0.02
	ruido.fractal_octaves = 4
	var mat := _material_rocha()
	var na := 64
	var nr := 28
	for k in lista.size():
		var m: Array = lista[k]
		var centro := Vector3(m[0], 0, m[1])
		var raio: float = m[2]
		var alto: float = m[3]
		var pico: float = m[4]
		var pontos := PackedVector3Array()
		for ir in nr + 1:
			var s := float(ir) / nr * 1.15   # passa um pouco da base para enterrar a borda
			for ia in na:
				var ang := TAU * ia / na
				var dir := Vector3(cos(ang), 0, sin(ang))
				# Contorno irregular: o raio varia com o ângulo
				var r := raio * (1.0 + ruido.get_noise_2d(cos(ang) * 40.0 + k * 97.0, sin(ang) * 40.0) * 0.45)
				var p := centro + dir * r * s
				# Pico: encosta côncava até a ponta; mesa: paredão íngreme e topo quase plano
				var h := pow(clampf(1.0 - s, 0.0, 1.0), 1.4) if pico > 0.5 else smoothstep(1.0, 0.7, s)
				h *= alto
				h = lerpf(h, floorf(h / 24.0) * 24.0 + smoothstep(0.55, 1.0, fmod(h, 24.0) / 24.0) * 24.0, 0.6)
				h += ruido.get_noise_2d(p.x * 2.0, p.z * 2.0) * 8.0 * clampf(1.0 - s, 0.0, 1.0)
				p.y = h if s < 1.0 else -0.5 - (s - 1.0) * 10.0
				pontos.append(p)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for ir in nr:
			for ia in na:
				var a := ir * na + ia
				var b := ir * na + (ia + 1) % na
				var c := a + na
				var d := b + na
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
	# Logo do jogo bem grande na viga (pedido do dono), no lugar do nome da pista
	var logo_larg := larg - 1.6
	var logo_alt := logo_larg / 2.72
	var viga_alt := logo_alt + 0.5
	var viga_y := 6.4 + viga_alt * 0.5
	for lado: float in [-1.0, 1.0]:
		_caixa(Vector3(0.5, viga_y + viga_alt * 0.5, 0.5), Vector3(lado * larg * 0.5, (viga_y + viga_alt * 0.5) * 0.5, 22.0), aco)
	_caixa(Vector3(larg + 0.5, viga_alt, 0.4), Vector3(0, viga_y, 22.0), Color(0.01, 0.01, 0.012), null, 0.3)
	var q := QuadMesh.new()
	q.size = Vector2(logo_larg, logo_alt)
	var logo := MeshInstance3D.new()
	logo.mesh = q
	logo.material_override = _mat_logo(1.4)
	logo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	logo.position = Vector3(0, viga_y, 21.78)
	logo.rotation.y = PI   # virada para a pista, como era o nome
	add_child(logo)


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
	m.albedo_texture = load(TEX + "brita.png")
	m.normal_enabled = true
	m.normal_texture = load(TEX + "brita_normal.png")
	m.uv1_scale = Vector3(brita.size.x / 2.5, brita.size.y / 2.5, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
	_barreira_pneus(z - 57.0, _x_muro() * 2.0)


## Barreira de pneus empilhados na frente da rede do fim da pista: face com a textura de duas
## fileiras de pneus (2,4 m x 1,2 m por repetição) e o corpo preto atrás.
func _barreira_pneus(z: float, largura: float) -> void:
	var alt := 1.2
	var face := QuadMesh.new()
	face.size = Vector2(largura, alt)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "pneus.png")
	m.uv1_scale = Vector3(largura / 2.4, 1, 1)
	m.roughness = 0.95
	var mi := MeshInstance3D.new()
	mi.mesh = face
	mi.material_override = m
	mi.position = Vector3(0, alt * 0.5, z + 0.451)
	add_child(mi)
	_caixa(Vector3(largura, alt, 0.9), Vector3(0, alt * 0.5, z), Color(0.03, 0.03, 0.035), null, 0.0)


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


# ------------------------------------------------------------------ logo do jogo

## Material da logo TSC (fundo preto da própria imagem); `led` > 0 faz brilhar como painel de LED.
func _mat_logo(led := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(LOGO)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness = 0.5
	if led > 0.0:
		m.emission_enabled = true
		m.emission_texture = m.albedo_texture
		m.emission_energy_multiplier = led
	return m


## Quadro com a logo virado para a pista (o lado `lado` fica à direita/esquerda da pista).
func _quadro_logo(tam: Vector2, pos: Vector3, lado: float, mat: Material) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = tam
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.basis = Basis(Vector3.UP, -lado * PI * 0.5)
	mi.position = pos
	add_child(mi)
	return mi


## Placa de muro preta com a logo repetida quatro vezes.
func _placa_logo(pos: Vector3, lado: float) -> void:
	_placa_muro(pos, lado, ["", Color(0.01, 0.01, 0.012), Color.WHITE])
	var mat := _mat_logo()
	for k in 4:
		_quadro_logo(Vector2(1.5, 0.55), pos + Vector3(-lado * 0.012, 0, -4.2 + k * 2.8), lado, mat)


## Painel gigante de LED com a logo em cima do fundo da arquibancada, com moldura e pernas.
func _painel_gigante(x: float, topo: float, z: float, lado: float) -> void:
	var larg := 22.0
	var alt := larg / 2.72
	var y := topo + 1.2 + alt * 0.5
	_caixa(Vector3(0.6, alt + 0.8, larg + 0.8), Vector3(x + lado * 0.35, y, z), Color(0.03, 0.03, 0.035), null, 0.3)
	for k: float in [-1.0, 1.0]:
		_caixa(Vector3(0.35, 1.4, 0.35), Vector3(x + lado * 0.35, topo + 0.6, z + k * larg * 0.35), Color(0.12, 0.13, 0.15))
	_quadro_logo(Vector2(larg, alt), Vector3(x + lado * 0.02, y, z), lado, _mat_logo(1.6))


# ------------------------------------------------------------------ balões no céu

## Balões de ar quente tripulados ao longe: derivam com o vento, sobem e descem devagar e o
## maçarico solta labaredas de vez em quando. Dois levam a logo TSC.
const PALETAS_BALAO := [
	[Color(0.85, 0.1, 0.08), Color(0.95, 0.85, 0.2), Color(0.1, 0.25, 0.7)],
	[Color(0.1, 0.3, 0.8), Color(0.95, 0.95, 0.95), Color(0.85, 0.1, 0.08)],
	[Color(0.95, 0.5, 0.05), Color(0.2, 0.1, 0.35), Color(0.95, 0.85, 0.2)],
	[Color(0.15, 0.6, 0.25), Color(0.95, 0.9, 0.2), Color(0.1, 0.1, 0.12)],
	[Color(0.6, 0.1, 0.55), Color(0.2, 0.75, 0.9), Color(0.95, 0.95, 0.95)],
	[Color(0.85, 0.1, 0.08), Color(0.08, 0.08, 0.1), Color(0.95, 0.95, 0.95)],
	[Color(0.95, 0.75, 0.1), Color(0.85, 0.2, 0.1), Color(0.1, 0.3, 0.8)],
]
const VENTO := Vector3(0.35, 0.0, 0.1)   # m/s (fraco: os balões do fundo não saem da vista na corrida)

var _baloes: Array[Dictionary] = []
var _t_ceu := 0.0


func _baloes_no_ceu() -> void:
	# Os quatro primeiros ficam no fundo da pista, logo acima do horizonte, à vista do piloto pelo
	# para-brisa (pedido do dono); os outros, dos lados e atrás, aparecem no voo do drone.
	var lugares := [Vector3(-70, 58, -340), Vector3(-22, 82, -430), Vector3(6, 46, -560), Vector3(48, 68, -390),
		Vector3(180, 95, -210), Vector3(-210, 130, -120), Vector3(135, 120, 60)]
	var malha := _malha_balao(8.0)
	var logo: Texture2D = load(LOGO)
	for i in lugares.size():
		var p: Vector3 = lugares[i] + Vector3(_rng.randf_range(-8, 8), _rng.randf_range(-5, 5), _rng.randf_range(-15, 15))
		if estilo != "estadio":   # no cânion: entre os paredões
			p.x = clampf(p.x, -30.0, 30.0)
		var no := Node3D.new()
		no.position = p
		# Os da logo viram o painel para a largada; os outros, para qualquer lado
		no.rotation.y = -PI * 0.25 + _rng.randf_range(-0.3, 0.3) if i == 1 or i == 5 else _rng.randf_range(0.0, TAU)
		no.scale = Vector3.ONE * 1.5   # envelope de 12 m de raio, ~27 m de altura
		add_child(no)
		var env := MeshInstance3D.new()
		env.mesh = malha
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/balao.gdshader")
		var pal: Array = PALETAS_BALAO[i % PALETAS_BALAO.size()]
		mat.set_shader_parameter("cor_a", pal[0])
		mat.set_shader_parameter("cor_b", pal[1])
		mat.set_shader_parameter("cor_c", pal[2])
		mat.set_shader_parameter("logo", logo)
		mat.set_shader_parameter("com_logo", 1.0 if i == 1 or i == 5 else 0.0)
		env.material_override = mat
		env.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no.add_child(env)
		# Cesto de vime, cordas até a boca, dois tripulantes e o maçarico
		var vime := Color(0.42, 0.28, 0.14)
		_caixa(Vector3(1.4, 1.1, 1.4), Vector3(0, -3.55, 0), vime, no, 0.0)
		for c: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var a := Vector3(c.x * 1.1, 0.1, c.y * 1.1)
			var b := Vector3(c.x * 0.65, -3.0, c.y * 0.65)
			var corda := _caixa(Vector3(0.05, a.distance_to(b), 0.05), (a + b) * 0.5, Color(0.15, 0.12, 0.1), no, 0.0)
			corda.basis = Basis(Quaternion(Vector3.UP, (a - b).normalized()))
		for k: float in [-0.35, 0.35]:
			_caixa(Vector3(0.4, 0.55, 0.3), Vector3(k, -2.75, 0.1), Color(0.1, 0.15, 0.3) if k < 0.0 else Color(0.6, 0.1, 0.08), no, 0.0)
			_caixa(Vector3(0.24, 0.26, 0.24), Vector3(k, -2.33, 0.1), Color(0.8, 0.62, 0.48), no, 0.0)
		var chama := _caixa(Vector3(0.5, 1.4, 0.5), Vector3(0, -1.1, 0), Color(1.0, 0.5, 0.1), no, 0.0)
		var mc := chama.material_override as StandardMaterial3D
		mc.emission_enabled = true
		mc.emission = Color(1.0, 0.55, 0.15)
		mc.emission_energy_multiplier = 6.0
		for n: GeometryInstance3D in no.find_children("*", "GeometryInstance3D", true, false):
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_baloes.append({"no": no, "base": p, "fase": _rng.randf_range(0.0, TAU), "chama": chama})


## Envelope por revolução: boca estreita embaixo, bojo arredondado e cúpula no alto (altura 2,25 R).
## UV.x dá a volta e UV.y vai de 0 na boca a 1 no topo.
static func _malha_balao(r: float) -> ArrayMesh:
	var voltas := 32
	var perfil: Array[Vector2] = []   # (raio, altura)
	var h_bojo := r * 1.25
	for i in 25:
		var u := float(i) / 24.0
		perfil.append(Vector2(lerpf(r * 0.2, r, sin(u * PI * 0.5)), u * h_bojo))
	for i in range(1, 17):
		var a := float(i) / 16.0 * PI * 0.5
		perfil.append(Vector2(r * cos(a), h_bojo + r * sin(a)))
	var topo := h_bojo + r
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in perfil.size():
		for i in voltas + 1:
			var ang := float(i) / voltas * TAU
			st.set_uv(Vector2(float(i) / voltas, perfil[j].y / topo))
			st.add_vertex(Vector3(cos(ang) * perfil[j].x, perfil[j].y, sin(ang) * perfil[j].x))
	for j in perfil.size() - 1:
		for i in voltas:
			var a := j * (voltas + 1) + i
			var b := a + voltas + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.generate_normals()
	return st.commit()


func _process(delta: float) -> void:
	_t_ceu += delta
	for b in _baloes:
		var no := b.no as Node3D
		var f: float = b.fase
		no.position = (b.base as Vector3) + VENTO * _t_ceu + Vector3(0, sin(_t_ceu * 0.15 + f) * 3.0, 0)
		no.rotation.z = sin(_t_ceu * 0.4 + f) * 0.02
		# Labaredas: rajadas de ~1,5 s a cada ~9 s, tremendo
		var ligado := fmod(_t_ceu + f * 3.0, 9.0) < 1.5
		(b.chama as Node3D).scale = Vector3.ONE * ((0.9 + 0.2 * sin(_t_ceu * 40.0 + f)) if ligado else 0.05)
