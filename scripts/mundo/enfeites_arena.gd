class_name EnfeitesArena
extends Node3D
## Enfeites da arena do Canyon Combat (pedido do dono: "bem enfeitada", placas com o nome do jogo,
## letreiros com o nome da fase, luzes): letreiro gigante com lâmpadas em sequência em cima do muro
## do fundo, outdoors com o logo TSC em cima das laterais, varais de lâmpadas coloridas cruzando a
## arena, neon no alto da cerca e flâmulas penduradas na face de dentro do muro.
## Nada disso tem colisão (fica acima da cerca ou colado no muro).

const LARANJA := Color(1.0, 0.45, 0.08)
const CIANO := Color(0.1, 0.8, 1.0)
const CORES_VARAL := [Color(1.0, 0.2, 0.1), Color(1.0, 0.75, 0.1), Color(0.2, 1.0, 0.3), Color(0.15, 0.5, 1.0), Color(1.0, 0.3, 0.8)]

var a: ComplexoArena
var _aco: Array[Transform3D] = []
var _topo_cerca := 0.0


func montar(arena: ComplexoArena) -> void:
	a = arena
	name = "Enfeites"
	_topo_cerca = a.piso_y + a.muro_altura + a.grade_altura
	_letreiro_fundo()
	for x: float in [30.0, 80.0]:
		for s: float in [-1.0, 1.0]:
			_outdoor(x, s)
	for x: float in [16.0, 38.0, 60.0, 82.0, 100.0]:
		_varal(x)
	_neon_cerca()
	_portao()
	for x: float in [10.0, 45.0, 65.0, 100.0]:
		for s: float in [-1.0, 1.0]:
			_flamula(Vector2(x, s * (a.largura_arena * 0.5 - 0.15)), -a.lateral * s)
	for lat: float in [-44.0, -30.0, 30.0, 44.0]:
		_flamula(Vector2(0.15, lat), a.frente)
	ComplexoLancamento.criar_multimesh(self, _aco, ComplexoLancamento._material_metal(Color(0.13, 0.135, 0.15), 0.8, 0.4))


## Base com +Z virado para `leitor` (Label3D e QuadMesh são vistos pelo +Z).
static func _virada_para(leitor: Vector3) -> Basis:
	return Basis.looking_at(-leitor, Vector3.UP)


func _texto(texto: String, fonte: Font, t: Transform3D, largura_max: float, altura_max: float, cor: Color) -> Label3D:
	var l := Label3D.new()
	l.text = texto
	l.font = fonte
	l.font_size = 200
	l.outline_size = 24
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	var tam := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 200)
	l.pixel_size = minf(largura_max / maxf(tam.x, 1.0), altura_max / maxf(tam.y, 1.0))
	l.modulate = cor
	l.double_sided = false
	l.transform = t
	add_child(l)
	return l


## Lâmpadas em volta de um retângulo (centro, eixos x/y do painel), piscando em sequência.
func _lampadas_moldura(centro: Vector3, b: Basis, tam: Vector2, passo: float, cor: Color, velocidade := 4.0) -> void:
	var lampadas: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	var perimetro := 2.0 * (tam.x + tam.y)
	var n := int(perimetro / passo)
	for i in n:
		var d := float(i) / n * perimetro
		var p: Vector2
		if d < tam.x:
			p = Vector2(-tam.x * 0.5 + d, tam.y * 0.5)
		elif d < tam.x + tam.y:
			p = Vector2(tam.x * 0.5, tam.y * 0.5 - (d - tam.x))
		elif d < 2.0 * tam.x + tam.y:
			p = Vector2(tam.x * 0.5 - (d - tam.x - tam.y), -tam.y * 0.5)
		else:
			p = Vector2(-tam.x * 0.5, -tam.y * 0.5 + (d - 2.0 * tam.x - tam.y))
		lampadas.append(Transform3D(b * Basis.from_scale(Vector3.ONE * 0.95), centro + b.x * p.x + b.y * p.y + b.z * 0.25))
		fases.append(i * 0.55)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/luz_sequencial.gdshader")
	mat.set_shader_parameter("cor", cor)
	mat.set_shader_parameter("energia", 7.0)
	mat.set_shader_parameter("velocidade", velocidade)
	_esferas(lampadas, mat, fases)


## Lâmpadas redondas (esfera de 0,5 m de diâmetro na escala 1) instanciadas.
func _esferas(transformacoes: Array[Transform3D], mat: Material, fases := PackedFloat32Array()) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not fases.is_empty()
	var esfera := SphereMesh.new()
	esfera.radius = 0.25
	esfera.height = 0.5
	esfera.radial_segments = 10
	esfera.rings = 5
	esfera.material = mat
	mm.mesh = esfera
	mm.instance_count = transformacoes.size()
	for i in transformacoes.size():
		mm.set_instance_transform(i, transformacoes[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, Color(fases[i], 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _painel_escuro(centro: Vector3, b: Basis, tam: Vector2) -> void:
	_aco.append(Transform3D(b * Basis.from_scale(Vector3(tam.x + 0.6, tam.y + 0.6, 0.5)), centro - b.z * 0.3))


## Letreiro gigante em cima do muro do fundo, virado para o portão: nome da fase em letra de
## corrida, "TARGET SPEED CHALLENGER" embaixo, moldura de lâmpadas em sequência e neon.
func _letreiro_fundo() -> void:
	var b := _virada_para(a.frente)
	var tam := Vector2(66.0, 11.0)
	var centro := a.pa(-1.2, 0.0, _topo_cerca + 3.5 + tam.y * 0.5)
	_painel_escuro(centro, b, tam)
	# Pernas de treliça saindo do alto do muro
	for lat: float in [-26.0, -9.0, 9.0, 26.0]:
		var pe := a.pa(-1.8, lat, _topo_cerca)
		_aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * (3.5 + tam.y), 1.0, 1.6, 0.16, 0.07))
	var racing: Font = load("res://assets/fontes/RacingSansOne-Regular.ttf")
	_texto(Config.nome_mapa().to_upper(), racing, Transform3D(b, centro + b.y * 1.6 + b.z * 0.05), tam.x - 5.0, 6.0, Color(2.2, 1.1, 0.35))
	_texto("TARGET SPEED CHALLENGER", Estilo.fonte_titulo(800), Transform3D(b, centro - b.y * 3.4 + b.z * 0.05), tam.x * 0.6, 2.2, Color(1.6, 1.8, 2.2))
	_lampadas_moldura(centro, b, tam, 1.1, Color(1.0, 0.7, 0.25))
	# Filetes de neon em cima e embaixo
	var neon := ComplexoLancamento._material_luz(CIANO, 5.0)
	var filetes: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		filetes.append(Transform3D(b * Basis.from_scale(Vector3(tam.x + 2.0, 0.18, 0.18)), centro + b.y * (tam.y * 0.5 + 0.9) * s + b.z * 0.1))
	ComplexoLancamento.criar_multimesh(self, filetes, neon, false)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.7, 0.35)
	luz.light_energy = 3.0
	luz.omni_range = 45.0
	luz.shadow_enabled = false
	luz.position = centro + b.z * 8.0
	add_child(luz)


## Outdoor com o logo TSC em cima da cerca lateral (`lado` = -1 ou +1), virado para dentro.
func _outdoor(x: float, lado: float) -> void:
	var b := _virada_para(-a.lateral * lado)
	var tam := Vector2(17.0, 7.0)
	var lat := lado * (a.largura_arena * 0.5 + 1.2)
	var centro := a.pa(x, lat, _topo_cerca + 2.5 + tam.y * 0.5)
	_painel_escuro(centro, b, tam)
	for dx: float in [-5.5, 5.5]:
		var pe := a.pa(x + dx, lat + lado * 0.6, _topo_cerca)
		_aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * (2.5 + tam.y), 0.8, 1.4, 0.14, 0.06))
	# Logo (arte em fundo preto: o preto vira o fundo do outdoor)
	var q := QuadMesh.new()
	q.size = Vector2(tam.y * 0.78 * 790.0 / 290.0, tam.y * 0.78)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var logo: Texture2D = load("res://assets/ui/logo_tsc.png")
	mat.albedo_texture = logo
	mat.emission_enabled = true
	mat.emission_texture = logo
	mat.emission_energy_multiplier = 0.6
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(b, centro + b.x * -2.5 + b.z * 0.02)
	add_child(mi)
	_texto("A MIRA É\nO ALVO", Estilo.fonte_titulo(800), Transform3D(b, centro + b.x * 6.0 + b.z * 0.05), 4.2, 4.0, Color(1.6, 0.9, 0.3))
	_lampadas_moldura(centro, b, tam, 0.9, CIANO if x < 50.0 else LARANJA, 5.0)


## Varal de lâmpadas coloridas atravessando a arena de um lado ao outro, com barriga no meio.
func _varal(x: float) -> void:
	var meia := a.largura_arena * 0.5
	var y0 := _topo_cerca + 0.6
	var barriga := 3.2
	var n := 48
	var fio: Array[Transform3D] = []
	var por_cor := []
	for c in CORES_VARAL:
		por_cor.append([] as Array[Transform3D])
	var ant := Vector3.ZERO
	for i in n + 1:
		var t := float(i) / n
		var p := a.pa(x, lerpf(-meia, meia, t), y0 - barriga * 4.0 * t * (1.0 - t))
		if i > 0:
			fio.append(ComplexoLancamento._viga(ant, p, 0.05))
			var bulbo := (ant + p) * 0.5 + Vector3.DOWN * 0.3
			(por_cor[i % CORES_VARAL.size()] as Array[Transform3D]).append(Transform3D(Basis.from_scale(Vector3(0.9, 1.15, 0.9)), bulbo))
		ant = p
	_aco.append_array(fio)
	for k in CORES_VARAL.size():
		_esferas(por_cor[k], ComplexoLancamento._material_luz(CORES_VARAL[k], 6.0))


## Portão: moldura de lâmpadas em sequência na placa com o nome da fase e fileiras de lâmpadas
## subindo pelas quinas internas das torres (mesmas medidas de ComplexoArena._montar_portao).
func _portao() -> void:
	var g := a.saida_largura * 0.5 + 1.6
	var altura := a.muro_altura + a.grade_altura + 4.0
	var x := a.comprimento + ComplexoArena.PAREDE * 0.5
	var b := _virada_para(-a.frente)
	var centro := a.pa(x - 2.0, 0.0, a.piso_y + altura + 0.2)
	_lampadas_moldura(centro, b, Vector2(g * 2.0 + 3.6, 2.8), 0.7, Color(1.0, 0.75, 0.3), 6.0)
	var lampadas: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	for s: float in [-1.0, 1.0]:
		var n := int((altura - 1.0) / 0.8)
		for i in n:
			lampadas.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.8), a.pa(x - 1.75, (g - 1.75) * s, a.piso_y + 0.6 + i * 0.8)))
			fases.append(-i * 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/luz_sequencial.gdshader")
	mat.set_shader_parameter("cor", CIANO)
	mat.set_shader_parameter("energia", 7.0)
	mat.set_shader_parameter("velocidade", 6.0)
	_esferas(lampadas, mat, fases)


## Fita de neon laranja correndo no alto da cerca, na face de dentro.
func _neon_cerca() -> void:
	var meia := a.largura_arena * 0.5
	var y := _topo_cerca + 0.55
	var fitas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var p := a.pa(a.comprimento * 0.5, s * (meia + 0.05), y)
		fitas.append(Transform3D(Basis.looking_at(a.frente, Vector3.UP) * Basis.from_scale(Vector3(0.14, 0.14, a.comprimento)), p))
	fitas.append(Transform3D(Basis.looking_at(a.lateral, Vector3.UP) * Basis.from_scale(Vector3(0.14, 0.14, meia * 2.0)), a.pa(0.05, 0.0, y)))
	ComplexoLancamento.criar_multimesh(self, fitas, ComplexoLancamento._material_luz(LARANJA, 6.0), false)


## Flâmula vertical pendurada na face de dentro do muro: preta com faixa laranja, "TSC" em cima
## e "TARGET SPEED" na vertical. `para_dentro` = direção do centro da arena.
func _flamula(q: Vector2, para_dentro: Vector3) -> void:
	var b := _virada_para(para_dentro)
	var tam := Vector2(3.2, 7.5)
	var centro := a.pa(q.x, q.y, a.piso_y + a.muro_altura + 1.0 + tam.y * 0.5) + para_dentro * 0.25
	var pano := QuadMesh.new()
	pano.size = tam
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.06)
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = pano
	mi.material_override = mat
	mi.transform = Transform3D(b, centro)
	add_child(mi)
	var faixas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		faixas.append(Transform3D(b * Basis.from_scale(Vector3(0.35, tam.y, 0.05)), centro + b.x * (tam.x * 0.5 - 0.3) * s + b.z * 0.03))
	ComplexoLancamento.criar_multimesh(self, faixas, ComplexoLancamento._material_luz(LARANJA, 2.5), false)
	# Barra de cima (onde a flâmula pendura)
	_aco.append(Transform3D(b * Basis.from_scale(Vector3(tam.x + 0.6, 0.18, 0.18)), centro + b.y * (tam.y * 0.5 + 0.1)))
	_texto("TSC", load("res://assets/fontes/RacingSansOne-Regular.ttf"), Transform3D(b, centro + b.y * 2.6 + b.z * 0.05), tam.x - 0.8, 1.6, Color(1.8, 0.85, 0.25))
	var vertical := b * Basis(Vector3.BACK, PI * 0.5)
	_texto("TARGET SPEED", Estilo.fonte_titulo(800), Transform3D(vertical, centro - b.y * 1.0 + b.z * 0.05), tam.y * 0.62, tam.x * 0.45, Color(0.95, 0.95, 1.0))
