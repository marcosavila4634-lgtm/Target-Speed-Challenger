class_name Avatar
extends Node3D
## Piloto (avatar) com esqueleto padrão Mixamo, sem animações no arquivo: as poses são montadas
## por código apontando os ossos para direções no espaço do avatar (frente = -Z, cima = +Y).
## - em_pe(): parado, braços relaxados (hangar do menu).
## - festejar(): comemoração do fim da partida (pulos e braços para o alto).
## - sentar_em(veiculo): no banco do motorista, mãos no volante (IK de dois ossos), pés nos pedais.
##   A cada quadro o volante do carro gira com a direção, as mãos acompanham e a cabeça olha a curva.

const ROTACAO_MAX_VOLANTE := deg_to_rad(95.0)
const _EIXO_DEDO := Vector3.RIGHT   # eixo local em que as falanges do Mixamo dobram

var dados: Dictionary = {}
var modelo: Node3D
var esqueleto: Skeleton3D
var escala := 1.0
var veiculo: Veiculo

var _m_esq := Transform3D.IDENTITY     # espaço do esqueleto -> espaço do avatar
var _ossos := {}                        # nome curto ("LeftArm") -> índice
var _filho := {}                        # índice -> primeiro filho (define a direção do osso)
var _volante: Node3D                    # pivô do volante do carro (gira com a direção)
var _vol_centro := Vector3.ZERO         # centro do volante no espaço do avatar
var _vol_eixo := Vector3.BACK           # normal do volante, apontando para o piloto
var _vol_raio := 0.18
var _dobra_dedo := {}                  # índice do osso da falange -> fração da dobra
var _chao_pes := -INF                  # altura do assoalho sob os pés (espaço do avatar)
var _giro_volante := 0.0             # rotação do volante; positivo = horário (curva à direita)
var _festa := 0.0                      # > 0: comemorando (intensidade)
var _t_festa := 0.0


static func criar(d: Dictionary) -> Avatar:
	var a := Avatar.new()
	a.name = "Avatar"
	a.dados = d
	a.modelo = (load(d.modelo) as PackedScene).instantiate()
	a.add_child(a.modelo)
	a.modelo.rotation.y = PI   # os modelos olham para +Z; no jogo a frente é -Z
	a.esqueleto = a.modelo.find_children("*", "Skeleton3D", true, false)[0]
	for mi in a.modelo.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).layers = 1   # a faixa da equipe não pinta o piloto
	a._indexar()
	a._medir_escala(float(d.get("altura", 1.75)))
	return a


func _indexar() -> void:
	for i in esqueleto.get_bone_count():
		# "LeftArm_011" -> "LeftArm"; "_rootJoint" fica de fora
		var nome := esqueleto.get_bone_name(i)
		var curto := nome.get_slice("_", 0) if not nome.begins_with("_") else nome
		if not _ossos.has(curto):
			_ossos[curto] = i
		var p := esqueleto.get_bone_parent(i)
		for dedo in ["Index", "Middle", "Ring", "Pinky"]:
			for f in 3:
				if curto.ends_with("Hand%s%d" % [dedo, f + 1]):
					_dobra_dedo[i] = [1.0, 1.15, 0.8][f]
		if curto.ends_with("HandThumb2") or curto.ends_with("HandThumb3"):
			_dobra_dedo[i] = 0.35
		if p >= 0 and not _filho.has(p):
			_filho[p] = i


## Escala o modelo para a altura pedida (topo da cabeça no repouso).
func _medir_escala(altura: float) -> void:
	_m_esq = _cadeia(esqueleto)
	var topo := _pos_repouso("HeadTop")
	var pe := _pos_repouso("LeftToeBase")
	var h := topo.y - minf(pe.y, 0.0)
	escala = altura / maxf(h, 0.5)
	modelo.scale = Vector3.ONE * escala
	_m_esq = _cadeia(esqueleto)


func _cadeia(n: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var a := n
	while a != null and a != self:
		if a is Node3D:
			t = (a as Node3D).transform * t
		a = a.get_parent()
	return t


func _pos_repouso(curto: String) -> Vector3:
	return _m_esq * esqueleto.get_bone_global_rest(_ossos[curto]).origin


# ------------------------------------------------------------------ poses

## Parado em pé: braços caídos ao lado do corpo com o cotovelo levemente dobrado.
func em_pe() -> void:
	modelo.position = Vector3.ZERO
	_posar({
		"LeftArm": Vector3(-0.12, -1.0, 0.02), "RightArm": Vector3(0.12, -1.0, 0.02),
		"LeftForeArm": Vector3(-0.06, -1.0, -0.22), "RightForeArm": Vector3(0.06, -1.0, -0.22),
	}, {}, Basis.IDENTITY, {})


## Comemoração (fim da partida): pula e sacode os braços para o alto. `intensidade` > 1 para o
## melhor da partida (pula mais alto). Animada em _process.
func festejar(intensidade := 1.0) -> void:
	veiculo = null
	_festa = intensidade
	_t_festa = randf() * 3.0   # cada piloto num ritmo diferente
	modelo.position = Vector3.ZERO
	set_process(true)


func _pose_festa(delta: float) -> void:
	_t_festa += delta
	var ritmo := _t_festa * 5.2
	var pulo := absf(sin(ritmo)) * 0.16 * _festa * escala_rel()
	modelo.position.y = pulo
	# Braços em "V" que sobem e descem com o pulo; a cada ~3 s um soco no ar alternado
	var soco := sin(_t_festa * 2.1)
	var sobe_e := 0.75 + 0.25 * sin(ritmo) + (0.35 if soco > 0.6 else 0.0)
	var sobe_d := 0.75 + 0.25 * sin(ritmo) + (0.35 if soco < -0.6 else 0.0)
	var abre := 0.55 - 0.15 * sin(ritmo)
	_posar({
		"LeftArm": Vector3(-abre, sobe_e, -0.1), "RightArm": Vector3(abre, sobe_d, -0.1),
		"LeftForeArm": Vector3(-abre * 0.3, 1.0, -0.15), "RightForeArm": Vector3(abre * 0.3, 1.0, -0.15),
		"Head": Vector3(0, 1, 0.12 * sin(ritmo)),
		"LeftUpLeg": Vector3(-0.08, -1, -0.12 * absf(sin(ritmo))), "RightUpLeg": Vector3(0.08, -1, -0.12 * absf(sin(ritmo))),
	}, {}, Basis(Vector3.RIGHT, deg_to_rad(-6.0)), {}, 1.0)


## Senta no banco do motorista do veículo, com as mãos no volante.
func sentar_em(v: Veiculo) -> void:
	veiculo = v
	_achar_volante()
	# Quadril (ponto H) atrás e abaixo do volante
	var h := _vol_centro + Vector3(0, -0.36, 0.40) * escala_rel()
	# Quadril apoiado no banco/assoalho (carros baixos deixavam o quadril abaixo do fundo)
	var banco: float = v.superficie_abaixo(h.x, h.y + 0.35, h.z)
	var piso_min := banco + 0.1 * escala_rel() if banco > -INF else -INF
	h.y = maxf(h.y, piso_min)
	# Cabeça não pode atravessar o teto: desce o banco até 12 cm e, se ainda faltar, encolhe o piloto
	var alt_sentado := 0.86 * escala_rel()
	var teto: float = v.altura_real(h.x, h.z + 0.08) - 0.07
	if teto > h.y and h.y + alt_sentado > teto:
		var falta := h.y + alt_sentado - teto
		var desce := clampf(minf(falta, 0.12), 0.0, h.y - piso_min)   # sem afundar no banco
		h.y -= desce
		falta -= desce
		if falta > 0.0:
			var f := clampf((alt_sentado - falta) / alt_sentado, 0.82, 1.0)
			modelo.scale *= f
			escala *= f
			_m_esq = _cadeia(esqueleto)
	position = h
	_vol_centro -= h
	# Assoalho na região dos pés: os pés não descem abaixo dele
	var pe_z := h.z - 0.62 * escala_rel()
	var chao := -INF
	for dx in [-0.12, 0.12]:
		chao = maxf(chao, v.superficie_abaixo(h.x + dx, h.y, pe_z))
	if chao > -INF:
		_chao_pes = chao - h.y + 0.07
	# O quadril do modelo vai para a origem do avatar
	var quadril := _pos_repouso("Hips")
	modelo.position -= quadril
	_m_esq = _cadeia(esqueleto)
	_pose_sentado()


func escala_rel() -> float:
	return escala * _altura_repouso() / 1.75


func _altura_repouso() -> float:
	return (esqueleto.get_bone_global_rest(_ossos["HeadTop"]).origin - esqueleto.get_bone_global_rest(_ossos["LeftToeBase"]).origin).length()


func _pose_sentado() -> void:
	var s := escala_rel()
	var dirs := {
		"Neck": Vector3(0, 1, -0.12), "Head": Vector3(0, 1, -0.05),
		"LeftFoot": Vector3(0, -0.45, -1), "RightFoot": Vector3(0, -0.45, -1),
	}
	# Pés nos pedais (IK), joelhos para cima e um pouco para fora
	var ik := {
		"LeftUpLeg": {"alvo_rel": Vector3(-0.07, -0.36, -0.62) * s, "polo": Vector3(-0.25, 1, -0.3), "chao": _chao_pes},
		"RightUpLeg": {"alvo_rel": Vector3(0.07, -0.36, -0.62) * s, "polo": Vector3(0.25, 1, -0.3), "chao": _chao_pes},
		"LeftArm": {"alvo": _pegada(-1.0), "polo": Vector3(-0.7, -1, 0.35)},
		"RightArm": {"alvo": _pegada(1.0), "polo": Vector3(0.7, -1, 0.35)},
	}
	var olhar := Basis(Vector3.UP, -_giro_volante * 0.25)
	_posar(dirs, ik, Basis(Vector3.RIGHT, deg_to_rad(6.0)), {"Head": olhar}, 1.2)


## Ponto da mão no aro (lado -1 = esquerda, 1 = direita), girado junto com o volante.
func _pegada(lado: float) -> Vector3:
	var direita := (Vector3.RIGHT - _vol_eixo * _vol_eixo.dot(Vector3.RIGHT)).normalized()
	var ponto := direita * lado * _vol_raio * 0.95
	return _vol_centro + ponto.rotated(_vol_eixo, -_giro_volante)


## Aplica a pose: "dirs" dá a direção (espaço do avatar) de cada osso até o filho; "ik" resolve
## coxa/canela ou braço/antebraço até um alvo; "incl" inclina o quadril; "extra" gira ossos no fim.
## Ossos sem pedido seguem o pai rigidamente, como na pose de repouso.
func _posar(dirs: Dictionary, ik: Dictionary, incl: Basis, extra: Dictionary, dedos := 0.0) -> void:
	var inv := _m_esq.affine_inverse()
	var globais := {}
	var pedidos := dirs.duplicate()
	var por_indice := {}
	for k in pedidos:
		if _ossos.has(k):
			por_indice[_ossos[k]] = pedidos[k]
	var extra_i := {}
	for k in extra:
		if _ossos.has(k):
			extra_i[_ossos[k]] = extra[k]
	var ik_i := {}
	for k in ik:
		if _ossos.has(k):
			ik_i[_ossos[k]] = ik[k]
	var quadril: int = _ossos.get("Hips", -1)
	for i in esqueleto.get_bone_count():
		var p := esqueleto.get_bone_parent(i)
		var g: Transform3D = (globais[p] * esqueleto.get_bone_rest(i)) if p >= 0 else esqueleto.get_bone_rest(i)
		if i == quadril:
			g.basis = (inv.basis * incl * _m_esq.basis).orthonormalized() * g.basis
		if ik_i.has(i):
			# Dois ossos: este (i), o filho (meio) e o neto (ponta)
			var meio: int = _filho.get(i, -1)
			var ponta: int = _filho.get(meio, -1)
			if meio >= 0 and ponta >= 0:
				var o := _m_esq * g.origin
				var l1 := (_m_esq.basis * esqueleto.get_bone_rest(meio).origin).length()
				var l2 := (_m_esq.basis * esqueleto.get_bone_rest(ponta).origin).length()
				var alvo: Vector3 = ik_i[i].alvo if ik_i[i].has("alvo") else o + ik_i[i].alvo_rel
				if ik_i[i].has("chao"):
					alvo.y = maxf(alvo.y, ik_i[i].chao)
				var cot := _ik(o, alvo, l1, l2, ik_i[i].polo)
				por_indice[i] = cot - o
				por_indice[meio] = alvo - cot
		if por_indice.has(i) and _filho.has(i):
			var atual := (g.basis * esqueleto.get_bone_rest(_filho[i]).origin).normalized()
			var desejada := (inv.basis * (por_indice[i] as Vector3)).normalized()
			if atual.cross(desejada).length() > 0.0001 or atual.dot(desejada) < 0.0:
				g.basis = Basis(Quaternion(atual, desejada)) * g.basis
		if _dobra_dedo.has(i):
			g.basis = g.basis * Basis(_EIXO_DEDO, _dobra_dedo[i] * dedos)
		if extra_i.has(i):
			g.basis = (inv.basis * (extra_i[i] as Basis) * _m_esq.basis).orthonormalized() * g.basis
		globais[i] = g
		var local: Transform3D = (globais[p].affine_inverse() * g) if p >= 0 else g
		esqueleto.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())


## Cotovelo/joelho de uma cadeia de dois ossos (o -> meio -> alvo) dobrando para o lado do polo.
static func _ik(o: Vector3, alvo: Vector3, l1: float, l2: float, polo: Vector3) -> Vector3:
	var v := alvo - o
	var d := clampf(v.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var n := v.normalized()
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var p := (polo - n * n.dot(polo)).normalized()
	return o + n * a + p * h


# ------------------------------------------------------------------ volante

## Volante do carro: nó com "steer" no nome. Centro, raio e inclinação vêm da caixa dele;
## o nó passa para um pivô que gira em torno do eixo do volante. Sem volante no modelo,
## estima a posição do motorista pelo teto (lado esquerdo, um pouco à frente do meio do teto);
## "volante": [x, y, z] no veiculos.json fixa o centro na mão.
func _achar_volante() -> void:
	var v := veiculo
	var no: Node3D = null
	# Prefere "steering wheel" (a coluna de direção também tem "steer" no nome)
	var nota := -1
	for n in v.modelo.find_children("*", "Node3D", true, false):
		var nome := String(n.name).to_lower()
		if not "steer" in nome:
			continue
		var pontos := (2 if "wheel" in nome else 0) + (1 if n is MeshInstance3D else 0)
		if pontos > nota:
			nota = pontos
			no = n
	var manual: Array = v.dados.get("volante", [])
	if manual.size() == 3:   # veiculos.json: centro do volante no espaço do carro
		_vol_centro = Vector3(manual[0], manual[1], manual[2])
		_vol_raio = 0.18
		_vol_eixo = Vector3(0, sin(0.45), cos(0.45))
		_volante_proprio()
		return
	var caixa := AABB()
	if no:
		caixa = v._aabb_local(no)
	if no and caixa.size.x > 0.2 and caixa.size.x < 0.6:
		_vol_centro = caixa.get_center()
		_vol_raio = caixa.size.x * 0.5
		var incl := atan2(maxf(caixa.size.z - 0.05, 0.0), maxf(caixa.size.y - 0.03, 0.05))
		incl = clampf(incl, deg_to_rad(10.0), deg_to_rad(50.0))
		_vol_eixo = Vector3(0, sin(incl), cos(incl))
		_volante = Node3D.new()
		_volante.name = "PivoVolante"
		v.add_child(_volante)
		_volante.position = _vol_centro
		no.reparent(_volante, true)
	else:
		var teto := v.centro_teto()
		var x := -v.caixa_corpo.size.x * 0.2
		var z := teto.z - 0.1
		var y := v.altura_real(x, z)
		if y == -INF:
			y = teto.y
		_vol_centro = Vector3(x, y - 0.42, z - 0.45)
		_vol_raio = 0.18
		_vol_eixo = Vector3(0, sin(0.45), cos(0.45))
		_volante_proprio()


## Volante para modelos que não têm um: aro, cubo e três raios, escuros e foscos.
func _volante_proprio() -> void:
	_volante = Node3D.new()
	_volante.name = "PivoVolante"
	veiculo.add_child(_volante)
	_volante.position = _vol_centro
	var peca := Node3D.new()
	# Malhas em pé no plano XY; o eixo do volante (Z local) aponta para o piloto
	peca.basis = Basis(Vector3.RIGHT, -atan2(_vol_eixo.y, _vol_eixo.z))
	_volante.add_child(peca)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.07)
	mat.roughness = 0.55
	var aro := MeshInstance3D.new()
	var toro := TorusMesh.new()
	toro.inner_radius = _vol_raio - 0.016
	toro.outer_radius = _vol_raio + 0.016
	aro.mesh = toro
	aro.rotation.x = PI * 0.5
	peca.add_child(aro)
	var cubo := MeshInstance3D.new()
	var cil := CylinderMesh.new()
	cil.top_radius = 0.045
	cil.bottom_radius = 0.05
	cil.height = 0.05
	cubo.mesh = cil
	cubo.rotation.x = PI * 0.5
	peca.add_child(cubo)
	for k in 3:
		var raio := MeshInstance3D.new()
		var caixa := BoxMesh.new()
		caixa.size = Vector3(_vol_raio, 0.022, 0.012)
		raio.mesh = caixa
		var ang := PI * 0.5 + k * TAU / 3.0 + PI
		raio.position = Vector3(cos(ang), sin(ang), 0) * _vol_raio * 0.5
		raio.rotation.z = ang
		peca.add_child(raio)
	for mi in peca.get_children():
		(mi as MeshInstance3D).material_override = mat
		(mi as MeshInstance3D).layers = 1


func _process(delta: float) -> void:
	if _festa > 0.0:
		_pose_festa(delta)
		return
	if veiculo == null or not veiculo.visible:
		return
	var alvo := clampf(float(veiculo.get("_direcao_suave")) * ROTACAO_MAX_VOLANTE, -ROTACAO_MAX_VOLANTE, ROTACAO_MAX_VOLANTE)
	if veiculo.travado:
		alvo = clampf(float(veiculo.entrada.direcao) * ROTACAO_MAX_VOLANTE, -ROTACAO_MAX_VOLANTE, ROTACAO_MAX_VOLANTE)
	var novo := move_toward(_giro_volante, alvo, delta * 6.0)
	if absf(novo - _giro_volante) < 0.002:
		return
	_giro_volante = novo
	if _volante:
		_volante.basis = Basis(_vol_eixo, -_giro_volante)
	_pose_sentado()
