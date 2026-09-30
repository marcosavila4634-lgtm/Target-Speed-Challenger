class_name Paraquedas
extends Node3D
## Paraquedas tipo asa, na cor da equipe (DEC-05), feito por código.
## - Células infladas com bocas na frente, painéis estabilizadores nas pontas.
## - Linhas em cascata até dois tirantes presos no teto do carro.
## - Abertura em etapas: o velame é disparado do teto como uma faixa de tecido amassada e as
##   linhas esticam; as células enchem do centro para as pontas; o slider desce pelas linhas;
##   a asa dá um tranco, balança e assenta. Sem paraquedinha extrator e sem saco (pedido do dono).
##   A força de sustentação é imediata (dossiê); só o visual é animado.
## - Fechamento: o tecido murcha e fica para trás.
## - A cobertura fica acima do carro, alinhada ao rumo, e inclina menos que ele (pêndulo).

const ENVERGADURA := 10.0
const CORDA := 3.6
const CELULAS := 11
const ABERTURA_S := 1.5
const FECHAMENTO_S := 0.6
# Etapas da abertura (fração de ABERTURA_S)
const FIM_SACO := 0.32        # saco chega à altura da asa (linhas esticadas)
const SAI_VELAME := 0.28      # velame começa a sair do saco
const FIM_CELULAS := 0.8      # todas as células cheias
const INICIO_TRANCO := 0.72

var veiculo: Veiculo
var aberto := false
var altura := 9.0
var _cobertura: Node3D
var _malha: MeshInstance3D
var _mat: ShaderMaterial
var _linhas: ImmediateMesh
var _area: Area3D
var _t := 0.0
var _tempo := 0.0                    # relógio contínuo do tecido (shader + linhas)
var _fixacoes: Array[Vector3] = []   # presilhas no teto, uma de cada lado (espaço do carro)
var _presilhas: Array[MeshInstance3D] = []
var _pontas: Array[Vector3] = []     # na face de baixo da cobertura (espaço da cobertura)
var _inclinacao_suave := Vector2.ZERO
var _saida_topo := Vector3.ZERO      # onde a cobertura ficou ao fechar
var _saida_base := Basis()
var _slider: MeshInstance3D          # retângulo que desce pelas linhas freando a abertura
var _mat_slider: ShaderMaterial
var _p_abertura := 1.0               # progresso da abertura (0..1)
var _pos_saco := Vector3.ZERO           # ponto onde o velame ainda embalado está (as linhas vão até ele)


func montar(v: Veiculo, cor: Color, caixa: AABB) -> void:
	veiculo = v
	name = "Paraquedas"
	top_level = true
	# Posicionado a cada quadro a partir do carro já interpolado (ver _atualizar): fora da interpolação
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	altura = float(Config.valor("fisica.paraquedas.altura_cobertura", 9)) + caixa.end.y
	_cobertura = Node3D.new()
	add_child(_cobertura)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/paraquedas.gdshader")
	_mat.set_shader_parameter("cor", cor)
	_mat.set_shader_parameter("envergadura", ENVERGADURA)
	_malha = MeshInstance3D.new()
	_malha.mesh = _malha_cobertura()
	_malha.material_override = _mat
	_cobertura.add_child(_malha)

	_montar_suporte(v, cor, caixa)
	# Fios presos nas costuras entre as células (ali o tecido não estufa), logo abaixo da face de
	# baixo: na altura fixa de antes a ponta ficava dentro do velame perto da borda de fuga (a face
	# de baixo desce para trás) e aparecia do outro lado do tecido (pedido do dono).
	for i in CELULAS + 1:
		var x := lerpf(-ENVERGADURA * 0.5, ENVERGADURA * 0.5, float(i) / CELULAS)
		for cz: float in [0.2, 0.5, 0.8]:
			_pontas.append(Vector3(x, _y_face_baixo(x, cz) - 0.07, lerpf(-CORDA * 0.5, CORDA * 0.5, cz)))

	_linhas = ImmediateMesh.new()
	var linhas := MeshInstance3D.new()
	linhas.mesh = _linhas
	var mat_l := StandardMaterial3D.new()
	mat_l.albedo_color = Color(0.1, 0.1, 0.12)
	mat_l.roughness = 0.9
	mat_l.cull_mode = BaseMaterial3D.CULL_DISABLED
	linhas.material_override = mat_l
	linhas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(linhas)
	linhas.top_level = true

	_area = Area3D.new()
	# Camada 4 (valor 8): coberturas se detectam entre si
	_area.collision_layer = 8
	_area.collision_mask = 1 | 2 | 8
	_area.monitoring = false
	var cs := CollisionShape3D.new()
	var forma := BoxShape3D.new()
	forma.size = Vector3(ENVERGADURA, 2.5, CORDA)
	cs.shape = forma
	cs.position.y = -0.8
	_area.add_child(cs)
	_area.body_entered.connect(_ao_encostar)
	_area.area_entered.connect(_ao_encostar_cobertura)
	_cobertura.add_child(_area)
	_montar_extras(cor)
	visible = false


## Slider (sem paraquedinha extrator: o próprio velame sai do teto amassado).
func _montar_extras(cor: Color) -> void:
	# Slider: tecido subdividido que estufa e bate com o vento (shaders/slider.gdshader)
	var placa := PlaneMesh.new()
	placa.size = Vector2(1.5, 0.6)
	placa.subdivide_width = 10
	placa.subdivide_depth = 8
	_mat_slider = ShaderMaterial.new()
	_mat_slider.shader = load("res://shaders/slider.gdshader")
	_mat_slider.set_shader_parameter("cor", cor.darkened(0.45))
	placa.material = _mat_slider
	_slider = MeshInstance3D.new()
	_slider.mesh = placa
	_slider.top_level = true
	add_child(_slider)


## Placa de reforço do teto: acompanha a curva da lataria (alturas dos vértices reais do modelo),
## quase no nível do teto, com moldura chanfrada, duas nervuras e um olhal em cada ponta.
## Os tirantes saem dos olhais.
const PLACA_ESPESSURA := 0.02
const PLACA_FOLGA := 0.01          # acima da lataria, para não piscar com ela
const OLHAL_RAIO := 0.075
const OLHAL_ALTURA := 0.022

## Sem paraquedas de teto (Drag Racing: o carro usa o de frenagem, atrás): tira a placa de reforço
## e as argolas do teto, e esconde o velame.
func remover() -> void:
	for p in _presilhas:
		if is_instance_valid(p):
			p.queue_free()
	_presilhas.clear()
	_fixacoes.clear()
	visible = false


func _montar_suporte(v: Veiculo, cor: Color, caixa: AABB) -> void:
	var h_teto := func(x: float, z: float) -> float:
		var h := v.altura_real(x, z)
		return h if h > -INF else v.altura_superficie(x, z)
	var teto := _achar_teto(v, caixa, h_teto)
	# Até onde o teto continua plano a partir do centro (para cada direção), para a placa não cair pelas bordas
	var h0: float = h_teto.call(teto.x, teto.z)
	var alcance := func(dir: Vector3, limite: float) -> float:
		var s := 0.0
		while s < limite:
			var p := teto + dir * (s + 0.02)
			if h_teto.call(p.x, p.z) < h0 - 0.06:
				break
			s += 0.02
		return s
	var teto_x := minf(alcance.call(Vector3.RIGHT, caixa.size.x * 0.5), alcance.call(Vector3.LEFT, caixa.size.x * 0.5))
	var teto_z := minf(alcance.call(Vector3.FORWARD, 1.0), alcance.call(Vector3.BACK, 1.0))
	var meia_largura := minf(caixa.size.x * 0.27, teto_x - OLHAL_RAIO - 0.06)   # centro dos olhais
	var comp := meia_largura + OLHAL_RAIO + 0.05        # meia envergadura da placa
	var fundo := clampf(minf(caixa.size.z * 0.055, teto_z - 0.04), 0.12, 0.24)   # meia profundidade no centro
	var chanfro := 0.022

	# Meia profundidade ao longo de x: afina nas pontas, formando o apoio de cada olhal
	var prof := func(x: float) -> float:
		return fundo * lerpf(1.0, 0.6, smoothstep(0.45, 1.0, absf(x) / comp))
	# Parâmetros agrupados perto das bordas (chanfro) com uma volta extra de saia descendo na lataria
	var amostras := func(n: int) -> PackedFloat32Array:
		var a := PackedFloat32Array([-1.0])
		for i in n + 1:
			a.append(-cos(PI * i / n))
		a.append(1.0)
		return a
	var xs: PackedFloat32Array = amostras.call(72)
	var ss: PackedFloat32Array = amostras.call(24)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := xs.size()
	var ns := ss.size()
	for j in ns:
		for i in nx:
			var x: float = xs[i] * comp
			var d: float = prof.call(x)
			var z: float = ss[j] * d
			var saia := i == 0 or i == nx - 1 or j == 0 or j == ns - 1
			var borda_ponta := comp - absf(x)
			var borda_lado := d - absf(z)
			var borda := minf(borda_ponta, borda_lado)
			var d_olhal := Vector2(absf(x) - meia_largura, z).length()
			var y: float = h_teto.call(teto.x + x, teto.z + z)
			if saia:
				y -= 0.03
			else:
				y += PLACA_FOLGA + PLACA_ESPESSURA * _suave(clampf(borda / chanfro, 0.0, 1.0))
				# Nervuras de reforço ao longo da placa, só no miolo
				var miolo := clampf((borda - 0.06) / 0.02, 0.0, 1.0) * clampf((d_olhal - OLHAL_RAIO - 0.03) / 0.02, 0.0, 1.0)
				var d_nerv := absf(absf(z) - d * 0.45)
				y += 0.005 * (1.0 - _suave(clampf((d_nerv - 0.008) / 0.01, 0.0, 1.0))) * miolo
				# Olhal: ressalto usinado com topo plano
				y += OLHAL_ALTURA * (1.0 - _suave(clampf((d_olhal - OLHAL_RAIO + 0.012) / 0.014, 0.0, 1.0)))
			st.set_color(Color(0, 1.0 if borda_ponta < borda_lado else 0.0, 0))
			st.set_uv(Vector2(x, z))
			st.set_uv2(Vector2(maxf(borda, 0.0), d_olhal))
			st.add_vertex(Vector3(teto.x + x, y, teto.z + z))
	for j in ns - 1:
		for i in nx - 1:
			var a := j * nx + i
			for idx in [a, a + 1, a + nx + 1, a, a + nx + 1, a + nx]:
				st.add_index(idx)
	st.generate_normals()
	st.generate_tangents()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/suporte_teto.gdshader")
	mat.set_shader_parameter("cor_equipe", cor)
	mat.set_shader_parameter("meia_largura", meia_largura)
	mat.set_shader_parameter("raio_olhal", OLHAL_RAIO)
	var placa := MeshInstance3D.new()
	placa.name = "SuporteParaquedas"
	placa.mesh = st.commit()
	placa.material_override = mat
	placa.layers = 1
	v.add_child(placa)
	_presilhas.append(placa)

	# Argola cromada deitada em cada olhal (os tirantes saem dela)
	var cromo := StandardMaterial3D.new()
	cromo.albedo_color = Color(0.8, 0.8, 0.82)
	cromo.metallic = 1.0
	cromo.roughness = 0.15
	for sinal: float in [-1.0, 1.0]:
		var x := teto.x + sinal * meia_largura
		var y: float = h_teto.call(x, teto.z) + PLACA_FOLGA + PLACA_ESPESSURA + OLHAL_ALTURA
		var argola := TorusMesh.new()
		argola.inner_radius = 0.026
		argola.outer_radius = 0.04
		argola.rings = 20
		argola.ring_segments = 8
		argola.material = cromo
		var mi := MeshInstance3D.new()
		mi.mesh = argola
		mi.transform = Transform3D(Basis.from_scale(Vector3(1.0, 0.7, 1.0)), Vector3(x, y + 0.004, teto.z))
		mi.layers = 1
		v.add_child(mi)
		_presilhas.append(mi)
		_fixacoes.append(Vector3(x, y + 0.01, teto.z))


## Teto de verdade: o trecho plano mais comprido perto do alto do carro (barras de faróis,
## santantônios e bordas curtas ficam de fora). Retorna o meio desse trecho.
func _achar_teto(v: Veiculo, caixa: AABB, h_teto: Callable) -> Vector3:
	var cx := caixa.get_center().x
	var passo := 0.05
	var zs: Array[float] = []
	var hs: Array[float] = []
	var z := caixa.position.z + passo
	while z < caixa.end.z:
		# Mínimo numa faixa de 40% da largura: só conta o que é largo como um teto
		var h := INF
		for j in 5:
			h = minf(h, h_teto.call(cx + lerpf(-0.2, 0.2, j / 4.0) * caixa.size.x, z))
		zs.append(z)
		hs.append(h)
		z += passo
	var topo := -INF
	for h in hs:
		topo = maxf(topo, h)
	var melhor := [0, 0]
	var i := 0
	while i < hs.size():
		if hs[i] < topo - 0.35:
			i += 1
			continue
		var k := i
		while k + 1 < hs.size() and absf(hs[k + 1] - hs[k]) < 0.03 and absf(hs[k + 1] - hs[i]) < 0.12:
			k += 1
		if k - i > melhor[1] - melhor[0]:
			melhor = [i, k]
		i = k + 1
	if hs.is_empty() or hs[melhor[0]] == INF:
		return v.centro_teto()
	# O paraquedas puxa pelo meio do carro (pedido do dono): no trecho plano, o ponto mais perto
	# do centro; se o trecho fica longe (conversível, tampa traseira, perua), vai para o centro.
	var centro_z := caixa.get_center().z
	var zc := clampf(centro_z, zs[melhor[0]], zs[melhor[1]])
	if absf(zc - centro_z) > caixa.size.z * 0.08:
		# No centro pode haver um buraco (banco de conversível, cockpit): procura, a partir do
		# centro para os dois lados, o ponto mais próximo que ainda esteja na altura da carroceria
		var ref: float = h_teto.call(cx, zc)
		zc = centro_z
		var passo_z := 0.05
		var dz := 0.0
		while dz < caixa.size.z * 0.5:
			var achou := false
			for z_teste: float in [centro_z - dz, centro_z + dz]:
				if h_teto.call(cx, z_teste) >= ref - 0.3:
					zc = z_teste
					achou = true
					break
			if achou:
				break
			dz += passo_z
	return Vector3(cx, h_teto.call(cx, zc), zc)


func abrir() -> void:
	aberto = true
	visible = true
	_t = 0.0
	_p_abertura = 0.0
	_inclinacao_suave = Vector2.ZERO
	_slider.visible = true
	_area.set_deferred("monitoring", true)
	_atualizar(0.0)


func fechar(imediato := false) -> void:
	if aberto and not imediato and _cobertura:
		_saida_topo = global_position
		_saida_base = global_basis
		_t = 0.0
	aberto = false
	if _mat:
		_mat.set_shader_parameter("abertura", 1.0)
	for extra in [_slider]:
		if extra:
			extra.visible = false
	if _area:
		_area.set_deferred("monitoring", false)
	if imediato or _cobertura == null:
		visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_tempo += delta
	_mat.set_shader_parameter("tempo", _tempo)
	if not aberto and _t >= FECHAMENTO_S:
		visible = false
		return
	_atualizar(delta)


func _atualizar(delta: float) -> void:
	var xf_carro := veiculo.get_global_transform_interpolated()   # onde o carro está desenhado
	var topo_carro := xf_carro * Vector3(0, veiculo.caixa_corpo.end.y, 0)
	if aberto:
		var euler := xf_carro.basis.get_euler()
		var alvo := Vector2(euler.x, euler.z) * 0.35
		_inclinacao_suave = alvo if delta == 0.0 else _inclinacao_suave.lerp(alvo, 1.0 - exp(-delta * 4.0))
		var p := clampf(_t / ABERTURA_S, 0.0, 1.0)
		_p_abertura = p
		# Tranco no fim do enchimento: a asa passa à frente do carro e volta, amortecendo
		var tt := maxf(_t - ABERTURA_S * INICIO_TRANCO, 0.0)
		var tranco := sin(tt * 7.5) * exp(-tt * 3.2) * 0.3 if _t > ABERTURA_S * INICIO_TRANCO else 0.0
		var base := Basis.from_euler(Vector3(_inclinacao_suave.x - tranco, veiculo.rumo, _inclinacao_suave.y))
		var h_final := altura - veiculo.caixa_corpo.end.y
		var pos_final := topo_carro + base.y * h_final
		# 1) Extração: o saco é disparado do teto e sobe, ficando um pouco para trás
		var e := _suave(clampf(p / FIM_SACO, 0.0, 1.0))
		var ref_teto := xf_carro * ((_fixacoes[0] + _fixacoes[1]) * 0.5)
		_pos_saco = ref_teto.lerp(pos_final, e) + base.z * sin(e * PI) * 2.2
		# 2) Velame: sai do saco estreito e comprido, alarga com um pequeno repique
		var sai := clampf((p - SAI_VELAME) / (FIM_CELULAS - SAI_VELAME), 0.0, 1.0)
		_malha.visible = true   # desde o início: sai do teto como uma faixa de tecido amassada
		var largura := lerpf(0.1, 1.0, _elastico(sai))
		var comprimento := lerpf(0.3, 1.0, _suave(clampf(sai * 1.8, 0.0, 1.0)))
		global_transform = Transform3D(base, _pos_saco.lerp(pos_final, _suave(clampf(sai * 2.0, 0.0, 1.0))))
		_cobertura.scale = Vector3(largura, lerpf(0.5, 1.0, sai), comprimento)
		_mat.set_shader_parameter("abertura", sai)
		_mat.set_shader_parameter("inflacao", lerpf(0.85, 1.0, _suave(clampf(sai * 1.5, 0.0, 1.0))))
		_mat.set_shader_parameter("vento", 1.0 + clampf(veiculo.linear_velocity.length() / 25.0, 0.0, 1.5))
		_mat_slider.set_shader_parameter("vento", 1.0 + clampf(veiculo.linear_velocity.length() / 25.0, 0.0, 1.5))
	else:
		# Fechando: murcha, estreita e fica para trás subindo um pouco
		var p := clampf(_t / FECHAMENTO_S, 0.0, 1.0)
		var vel := veiculo.linear_velocity
		var pos := _saida_topo - vel * _t * 0.6 + Vector3.UP * _t * 3.0
		global_transform = Transform3D(_saida_base.rotated(_saida_base.x, p * 0.8), pos)
		_cobertura.scale = Vector3(lerpf(1.0, 0.25, p), lerpf(1.0, 0.5, p), lerpf(1.0, 0.7, p))
		_mat.set_shader_parameter("inflacao", 1.0 - _suave(p))
	_desenhar_linhas(xf_carro)


func _desenhar_linhas(xf_carro: Transform3D) -> void:
	_linhas.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var olho := cam.global_position
	var xf_cob := _cobertura.global_transform
	var tirantes: Array[Vector3] = []
	var fixacoes: Array[Vector3] = []
	for f in _fixacoes:
		fixacoes.append(xf_carro * f)
	if not aberto:
		# Soltas: as linhas só aparecem no primeiro instante do fechamento
		if _t > 0.12:
			return
	_linhas.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	if aberto:
		if _p_abertura < SAI_VELAME:
			# Linhas ainda dentro do saco: um feixe esticado de cada presilha até ele
			for f in fixacoes:
				_fita(f, _pos_saco, 0.06, olho)
			_slider.visible = false
			_linhas.surface_end()
			return
	# Tirantes: um de cada lado, saindo da presilha em direção ao seu lado da asa
	var ancoras: Array[Vector3] = []
	for lado in 2:
		var sinal := -1.0 if lado == 0 else 1.0
		var ancora_asa := xf_cob * Vector3(sinal * ENVERGADURA * 0.22, _perfil(ENVERGADURA * 0.22) - 0.4, 0.0)
		ancoras.append(ancora_asa)
		var topo := fixacoes[lado] + (ancora_asa - fixacoes[lado]).normalized() * 1.8
		tirantes.append(topo)
		_fita(fixacoes[lado], topo, 0.07, olho)
	# Slider: desce pelos feixes de linhas de logo abaixo da asa até perto dos tirantes. Os 4 cantos
	# (ilhoses) ficam em cima dos feixes: as linhas passam por eles.
	var ilhoses := []   # [lado][frente/trás]
	if aberto:
		var desce := _suave(clampf((_p_abertura - SAI_VELAME) / (1.0 - SAI_VELAME), 0.0, 1.0))
		# Só aparece perto dos tirantes, onde os feixes estão juntos (no alto ele virava uma barra enorme)
		var s := lerpf(0.8, 0.95, desce)
		var c0 := ancoras[0].lerp(tirantes[0], s)
		var c1 := ancoras[1].lerp(tirantes[1], s)
		var b_s := xf_cob.basis.orthonormalized()
		var eixo_x := c1 - c0
		var fundo := lerpf(1.0, 0.35, desce)   # perto dos tirantes as linhas de frente/trás se juntam
		var b_final := Basis(eixo_x / 1.5, b_s.y, b_s.z * fundo)
		_slider.visible = desce > 0.25
		_slider.global_transform = Transform3D(b_final, (c0 + c1) * 0.5)
		for lado in 2:
			var c := c0 if lado == 0 else c1
			ilhoses.append([c - b_s.z * 0.3 * fundo, c + b_s.z * 0.3 * fundo])
			for k in 2:
				_fita(ilhoses[lado][k], tirantes[lado], 0.035, olho)
	# Linhas em cascata: pontas da cobertura → ilhós do slider → tirante do mesmo lado
	var destino := func(lado: int, z: float) -> Vector3:
		return tirantes[lado] if ilhoses.is_empty() else ilhoses[lado][0 if z < 0.0 else 1]
	for p in _pontas:
		var lado := 0 if p.x < 0.0 else 1
		_fita(xf_cob * p, destino.call(lado, p.z), 0.022, olho)
	# Estabilizadores: linhas da ponta e das bordas de baixo até o mesmo lado
	for lado in 2:
		var e := _estabilizador(-1.0 if lado == 0 else 1.0)
		var pontos := [[e.ponta, 1.0], [e.frente.lerp(e.ponta, 0.6), 0.6], [e.tras.lerp(e.ponta, 0.6), 0.6]]
		for q: Array in pontos:
			var pq: Vector3 = q[0]
			_fita(xf_cob * _desloc_estabilizador(q[0], q[1]), destino.call(lado, pq.z), 0.022, olho)
	_linhas.surface_end()


## Linha fina desenhada como fita virada para a câmera.
func _fita(a: Vector3, b: Vector3, largura: float, olho: Vector3) -> void:
	var dir := b - a
	var lado := dir.cross(olho - a).normalized() * largura * 0.5
	var v := [a - lado, a + lado, b + lado, b - lado]
	for i in [0, 1, 2, 0, 2, 3]:
		_linhas.surface_add_vertex(v[i])


func _ao_encostar(corpo: Node) -> void:
	if aberto and corpo != veiculo:
		veiculo.murchar_velame()


## Duas coberturas se enroscando: as duas fecham.
func _ao_encostar_cobertura(outra: Area3D) -> void:
	if aberto and outra != _area:
		veiculo.murchar_velame()


static func _suave(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


## Enchimento com pequeno tranco: passa um pouco do tamanho final e volta.
static func _elastico(x: float) -> float:
	if x >= 1.0:
		return 1.0
	if x <= 0.0:
		return 0.0
	return 1.0 + pow(2.0, -9.0 * x) * sin((x * 9.0 - 0.75) * TAU / 3.0)


func _perfil(x: float) -> float:
	# Arco da envergadura: pontas mais baixas que o centro.
	var r := ENVERGADURA * 0.6
	return sqrt(maxf(r * r - x * x, 0.0)) - r


## Altura da face de baixo da cobertura em x e na fração cz da corda (mesma conta de _malha_cobertura).
func _y_face_baixo(x: float, cz: float) -> float:
	return _perfil(x) + sin(PI * pow(cz, 0.7)) * 0.1 - 0.42 - cz * 0.25


## Cobertura: faces de cima e de baixo por célula, bocas na frente e estabilizadores nas pontas.
func _malha_cobertura() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg_x := 4
	var seg_z := 8
	var espessura := 0.42
	for c in CELULAS:
		var x0 := lerpf(-ENVERGADURA * 0.5, ENVERGADURA * 0.5, float(c) / CELULAS)
		var x1 := lerpf(-ENVERGADURA * 0.5, ENVERGADURA * 0.5, float(c + 1) / CELULAS)
		for face in 2:
			var f_uv := 1.0 if face == 0 else 0.0
			for i in seg_x:
				for k in seg_z:
					var quad := []
					for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
						var u := float(i + d[0]) / seg_x
						var cz := float(k + d[1]) / seg_z
						var x := lerpf(x0, x1, u)
						var perfil_asa := sin(PI * pow(cz, 0.7)) * (0.42 if face == 0 else 0.1)
						var y := _perfil(x) + perfil_asa - (0.0 if face == 0 else espessura) - cz * 0.25
						quad.append([Vector3(x, y, lerpf(-CORDA * 0.5, CORDA * 0.5, cz)), Vector2(u, cz)])
					for idx in [0, 1, 2, 0, 2, 3]:
						st.set_uv(quad[idx][1])
						st.set_uv2(Vector2(float(c) / CELULAS, f_uv))
						st.add_vertex(quad[idx][0])
		# Boca da célula (frente aberta, escura por dentro)
		for i in seg_x:
			var xa := lerpf(x0, x1, float(i) / seg_x)
			var xb := lerpf(x0, x1, float(i + 1) / seg_x)
			var z := -CORDA * 0.5
			var pts := [Vector3(xa, _perfil(xa), z), Vector3(xb, _perfil(xb), z),
				Vector3(xb, _perfil(xb) - espessura, z), Vector3(xa, _perfil(xa) - espessura, z)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(float(i) / seg_x, 0.0))
				st.set_uv2(Vector2(float(c) / CELULAS, 0.5))
				st.add_vertex(pts[idx])
	# Estabilizadores: painéis de tecido pendurados nas pontas, subdivididos para tremular.
	# UV.y = 0 na asa, 1 na ponta de baixo; UV2.x = -1 marca o painel para o shader.
	for sinal: float in [-1.0, 1.0]:
		var e := _estabilizador(sinal)
		var linhas_n := 6
		for k in linhas_n:
			var w0 := float(k) / linhas_n
			var w1 := float(k + 1) / linhas_n
			var a0: Vector3 = e.frente.lerp(e.ponta, w0)
			var b0: Vector3 = e.tras.lerp(e.ponta, w0)
			var a1: Vector3 = e.frente.lerp(e.ponta, w1)
			var b1: Vector3 = e.tras.lerp(e.ponta, w1)
			var quad := [[a0, w0], [b0, w0], [b1, w1], [a1, w1]]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(0.5, quad[idx][1]))
				st.set_uv2(Vector2(-1.0, 0.0))
				st.add_vertex(quad[idx][0])
	st.generate_normals()
	return st.commit()


## Cantos do estabilizador de um lado (espaço da cobertura): borda presa (frente/trás) e ponta de baixo.
func _estabilizador(sinal: float) -> Dictionary:
	var x := sinal * ENVERGADURA * 0.5
	var y := _perfil(x) - 0.42
	return {
		"frente": Vector3(x, y, -CORDA * 0.45),
		"tras": Vector3(x, y, CORDA * 0.45),
		"ponta": Vector3(x - sinal * 0.3, y - 1.3, CORDA * 0.05),
	}


## Mesmo deslocamento que o shader aplica ao estabilizador (para as linhas acompanharem o tecido).
func _desloc_estabilizador(p: Vector3, w: float) -> Vector3:
	var vento := float(_mat.get_shader_parameter("vento"))
	var inflacao := float(_mat.get_shader_parameter("inflacao"))
	return p + Vector3(
		sin(_tempo * 9.0 + w * 2.0 + p.z * 1.3) * 0.16 * w * vento,
		(1.0 - inflacao) * w * 1.1,
		sin(_tempo * 6.3 + w * 3.0) * 0.1 * w * vento)
