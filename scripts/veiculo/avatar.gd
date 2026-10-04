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
var _folga_pegada := Vector2.ZERO   # pulso fora do aro (x) e para o piloto (y): mão fechando no aro
var _giro_maos := {}                  # cockpit: punhos girados, palma de frente para o aro
var _alvo_cambio := Vector3.ZERO     # cockpit: manopla do câmbio (espaço do avatar)
var _mix_cambio := 0.0               # 0 = mão direita no volante, 1 = na alavanca
var _puxao_esq := 0.0                # cockpit: dedos puxando a borboleta (0..1)
var _puxao_dir := 0.0
var _mao_fixa := {}                  # índice do osso da mão -> giro (espaço do avatar) da pose de repouso até a pegada
var _eixo_dedo := {}                 # índice da falange -> eixo local da dobra (fecha para a palma)


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
		# "LeftArm_011" -> "LeftArm"; "_rootJoint" fica de fora; sem o prefixo "mixamorig_"/"mixamorig:"
		var nome := esqueleto.get_bone_name(i).trim_prefix("mixamorig_").trim_prefix("mixamorig:")
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
	_medir_eixos_dedos()


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
	# O teto é conferido de novo com a cabeça já na pose (a nuca fica atrás do ponto testado e
	# muitos tetos caem para trás): se ainda atravessar, afunda mais no banco e encolhe o piloto.
	var inicial := [_vol_centro, modelo.position, modelo.scale, escala]
	var desce_extra := 0.0
	var fator := 1.0
	for i in 6:
		_encaixar(v, desce_extra, fator)
		var folga := folga_teto()
		if folga >= 0.025 or i == 5 or (fator <= 0.7 and desce_extra >= 0.07):
			break
		var falta := 0.025 - folga
		var desce := minf(falta, 0.07 - desce_extra)
		desce_extra += desce
		fator *= clampf(1.0 - (falta - desce) / (0.86 * escala_rel()), 0.6, 1.0)
		fator = maxf(fator, 0.7)
		_vol_centro = inicial[0]
		modelo.position = inicial[1]
		modelo.scale = inicial[2]
		escala = inicial[3]
		_m_esq = _cadeia(esqueleto)


func _encaixar(v: Veiculo, desce_extra: float, fator: float) -> void:
	if fator < 1.0:
		modelo.scale *= fator
		escala *= fator
		_m_esq = _cadeia(esqueleto)
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
	h.y -= desce_extra
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


## Luvas de piloto (tools/luvas/vestir.py): malhas presas aos ossos da mão deste mesmo avatar,
## que passam para o esqueleto dele e fecham junto com os dedos.
func vestir_luvas(arquivo: String) -> void:
	if arquivo == "" or not ResourceLoader.exists(arquivo):
		return
	var cena: Node = (load(arquivo) as PackedScene).instantiate()
	for mi: MeshInstance3D in cena.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null:
			continue
		mi.owner = null
		mi.get_parent().remove_child(mi)
		esqueleto.add_child(mi)
		mi.transform = Transform3D.IDENTITY
		mi.skeleton = NodePath("..")
		mi.layers = 1
		mi.set_meta("luva", true)
	cena.free()
	_tirar_malha(["LeftHand", "RightHand"])


## Sentado no cockpit do Drag (visão interna, sem carro por baixo): o volante vem no espaço do
## pai (centro, normal apontando para o piloto e raio do aro) e o olho do piloto fica em `olho`.
## A cabeça some (a câmera está dentro dela); ficam o tronco, os braços e as mãos no aro.
func sentar_cockpit(centro: Vector3, eixo: Vector3, raio: float, olho: Vector3) -> void:
	_vol_eixo = eixo.normalized()
	_vol_raio = raio
	var palma := (_pos_repouso("LeftHandMiddle1") - _pos_repouso("LeftHand")).length()
	_folga_pegada = Vector2(0.02 * escala_rel(), palma * 0.25)   # pulso fora e atrás do aro: a palma encosta nele
	_giro_maos = {"LeftHand": Basis.IDENTITY, "RightHand": Basis.IDENTITY}   # só marca o modo cockpit (a pegada é _mao_fixa)
	modelo.position -= _pos_repouso("Hips")
	_m_esq = _cadeia(esqueleto)
	position = olho + Vector3(0, -0.72, 0.12) * escala_rel()
	var cabeca: int = _ossos["Head"]
	for i in 3:   # acerta o quadril até o olho do modelo cair no olho pedido
		_vol_centro = centro - position
		_pose_sentado()
		var c := _m_esq * esqueleto.get_bone_global_pose(cabeca).origin
		var olho_modelo := c + Vector3(0, 0.08, -0.1) * escala_rel()
		position += olho - (position + olho_modelo)
	# A cabeça fica escondida (a câmera está nela): o corpo pode ir para a frente até os braços
	# alcançarem o aro com o cotovelo dobrado, como um piloto de verdade (banco perto do volante).
	var braco := (_pos_repouso("LeftForeArm") - _pos_repouso("LeftArm")).length() + (_pos_repouso("LeftHand") - _pos_repouso("LeftForeArm")).length()
	for i in 4:
		_vol_centro = centro - position
		_pose_sentado()
		var ombro := _m_esq * esqueleto.get_bone_global_pose(_ossos["LeftArm"]).origin
		var falta := (_pegada(-1.0) - ombro).length() - braco * 0.85
		if falta <= 0.005:
			break
		position += (_pegada(-1.0) - ombro).normalized() * Vector3(0.3, 0.3, 1.0) * falta
	_vol_centro = centro - position
	_pose_sentado()
	_tirar_malha(["Head"])
	if OS.get_environment("TSC_DEBUG_MAO") != "":
		_debug_alcance()


## Some com os triângulos presos a esses ossos e aos filhos deles: a cabeça na visão interna (rosto,
## cabelo e boné na frente da câmera) e as mãos de pele sob as luvas (senão os dedos furam a luva).
func _tirar_malha(raizes: Array) -> void:
	var cab := {}
	var pilha := []
	for r in raizes:
		if _ossos.has(r):
			pilha.append(_ossos[r])
	while not pilha.is_empty():
		var i: int = pilha.pop_back()
		cab[i] = true
		for k in esqueleto.get_bone_count():
			if esqueleto.get_bone_parent(k) == i:
				pilha.append(k)
	for mi: MeshInstance3D in modelo.find_children("*", "MeshInstance3D", true, false):
		if mi.skin == null or mi.mesh == null or mi.has_meta("luva"):
			continue
		var da_cabeca := {}   # índice do bind -> é osso da cabeça
		for b in mi.skin.get_bind_count():
			var osso_b := mi.skin.get_bind_bone(b)
			if osso_b < 0:
				osso_b = esqueleto.find_bone(mi.skin.get_bind_name(b))
			da_cabeca[b] = cab.has(osso_b)
		var nova := ArrayMesh.new()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var fmt: int = mi.mesh.surface_get_format(s)
			var por_v: int = 8 if fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS else 4
			var ossos_v = arr[Mesh.ARRAY_BONES]
			var pesos_v = arr[Mesh.ARRAY_WEIGHTS]
			if ossos_v != null and arr[Mesh.ARRAY_INDEX] != null:
				var fora := PackedByteArray()
				fora.resize(arr[Mesh.ARRAY_VERTEX].size())
				for v in fora.size():
					var p := 0.0
					for j in por_v:
						if da_cabeca.get(ossos_v[v * por_v + j], false):
							p += pesos_v[v * por_v + j]
					fora[v] = 1 if p > 0.25 else 0
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
				var fica := PackedInt32Array()
				for t in range(0, idx.size(), 3):
					if not (fora[idx[t]] or fora[idx[t + 1]] or fora[idx[t + 2]]):
						fica.append_array([idx[t], idx[t + 1], idx[t + 2]])
				arr[Mesh.ARRAY_INDEX] = fica
				if fica.is_empty():
					continue
			nova.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(s), arr, [], {}, fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			nova.surface_set_material(nova.get_surface_count() - 1, mi.mesh.surface_get_material(s))
		mi.mesh = nova


## Folga (m) entre o crânio do piloto já sentado e o teto do carro, conferida no topo da cabeça e
## em volta dele (testa, nuca, laterais). Negativa = a cabeça atravessa. INF em carro sem teto.
func folga_teto() -> float:
	var topo := position + _m_esq * esqueleto.get_bone_global_pose(_ossos["HeadTop"]).origin
	var r := 0.09 * escala_rel()
	var folga := INF
	for o: Vector3 in [Vector3.ZERO, Vector3(r, -0.03, 0), Vector3(-r, -0.03, 0), Vector3(0, -0.03, r), Vector3(0, -0.03, -r), Vector3(0, -0.08, r * 1.3)]:
		var p := topo + o * Vector3(1, escala_rel(), 1)
		var teto: float = veiculo.altura_real(p.x, p.z)
		if teto > position.y + 0.4 * escala_rel():   # sem teto o raio acha o banco/assoalho
			folga = minf(folga, teto - p.y)
	return folga


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
		"RightArm": {"alvo": _pegada(1.0).lerp(_alvo_cambio, _mix_cambio), "polo": Vector3(0.7, -1, 0.35)},
	}
	if not _giro_maos.is_empty():
		for lado: float in [-1.0, 1.0]:
			_calcular_pegada(lado)
	var olhar := Basis(Vector3.UP, -_giro_volante * 0.25)
	var extra := {"Head": olhar}
	extra.merge(_giro_maos)
	if _mix_cambio > 0.0 and extra.has("RightHand"):   # na alavanca: palma para baixo, por cima da manopla
		extra["RightHand"] = Basis(Vector3.RIGHT, deg_to_rad(90.0 * (1.0 - _mix_cambio)))
	_posar(dirs, ik, Basis(Vector3.RIGHT, deg_to_rad(6.0)), extra, 1.2 if _giro_maos.is_empty() else 1.3)


## Pegada do cockpit: dedos apontando para a frente (longe do piloto) e um pouco para dentro do
## aro, polegar por cima (ao longo do aro), palma encostada no lado de fora do aro. O giro leva
## os eixos da mão em repouso (pulso -> dedo médio, mindinho -> indicador) até esses.
func _calcular_pegada(lado: float) -> void:
	var nome := "LeftHand" if lado < 0.0 else "RightHand"
	var pre := "Left" if lado < 0.0 else "Right"
	var lr := (_pos_repouso(pre + "HandMiddle1") - _pos_repouso(nome)).normalized()
	var tr := _pos_repouso(pre + "HandIndex1") - _pos_repouso(pre + "HandPinky1")
	tr = (tr - lr * tr.dot(lr)).normalized()
	var e := _vol_eixo
	var fora := (Vector3.RIGHT - e * e.dot(Vector3.RIGHT)).normalized().rotated(e, -_giro_volante) * lado
	var cima := e.cross(fora * lado).normalized()   # tangente do aro (para cima nas 9h/3h)
	var puxa: float = _puxao_esq if lado < 0.0 else _puxao_dir
	var l := (-e - fora * (0.12 + puxa * 0.25)).normalized()
	var t := (cima - l * cima.dot(l)).normalized()
	var rep := Basis(lr, tr, lr.cross(tr))
	var des := Basis(l, t, l.cross(t))
	_mao_fixa[_ossos[nome]] = des * rep.inverse()


## Ponto da mão no aro (lado -1 = esquerda, 1 = direita), girado junto com o volante.
func _pegada(lado: float) -> Vector3:
	var direita := (Vector3.RIGHT - _vol_eixo * _vol_eixo.dot(Vector3.RIGHT)).normalized()
	var puxa: float = _puxao_esq if lado < 0.0 else _puxao_dir
	var ponto := direita * lado * (_vol_raio * 0.95 + _folga_pegada.x - puxa * 0.025) + _vol_eixo * (_folga_pegada.y + puxa * 0.02)
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
			g.basis = g.basis * Basis(_eixo_dedo.get(i, _EIXO_DEDO) if not _giro_maos.is_empty() else _EIXO_DEDO, _dobra_dedo[i] * dedos)
		if extra_i.has(i):
			g.basis = (inv.basis * (extra_i[i] as Basis) * _m_esq.basis).orthonormalized() * g.basis
		if _mao_fixa.has(i):   # cockpit: mão com orientação completa (palma no aro, polegar por cima)
			g.basis = (inv.basis * (_mao_fixa[i] as Basis) * _m_esq.basis * esqueleto.get_bone_global_rest(i).basis).orthonormalized()
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


## Troca de marcha (cockpit): leva a mão direita do aro até a manopla (`alvo` no espaço do pai do
## avatar) na fração `mistura` (0 = volante, 1 = alavanca).
func mao_no_cambio(alvo: Vector3, mistura: float) -> void:
	_alvo_cambio = alvo - position
	_mix_cambio = clampf(mistura, 0.0, 1.0)
	_pose_sentado()


## Borboleta do câmbio (cockpit): `lado` 1 = direita (sobe), -1 = esquerda (reduz); `forca` 0..1.
## A mão fica no aro, desliza um pouco para dentro e os dedos fecham puxando.
func puxar_borboleta(lado: float, forca: float) -> void:
	if lado > 0.0:
		_puxao_dir = forca
	else:
		_puxao_esq = forca
	_pose_sentado()


## Eixo em que cada falange fecha para a palma, medido na mão em repouso: a linha dos nós
## (mindinho -> indicador). Na mão esquerda a dobra positiva é em torno de -T, na direita de +T.
## O eixo fixo do Mixamo (X local) em alguns modelos dobrava os dedos para o lado.
func _medir_eixos_dedos() -> void:
	for pre in ["Left", "Right"]:
		if not (_ossos.has(pre + "Hand") and _ossos.has(pre + "HandIndex1") and _ossos.has(pre + "HandPinky1") and _ossos.has(pre + "HandMiddle1")):
			continue
		var r := func(n: String) -> Vector3: return esqueleto.get_bone_global_rest(_ossos[n]).origin
		var l: Vector3 = (r.call(pre + "HandMiddle1") - r.call(pre + "Hand")).normalized()
		var t: Vector3 = r.call(pre + "HandIndex1") - r.call(pre + "HandPinky1")
		t = (t - l * t.dot(l)).normalized()
		var eixo := -t if pre == "Left" else t
		for i: int in _dobra_dedo:
			var nome := esqueleto.get_bone_name(i)
			if not nome.begins_with(pre) or "Thumb" in nome:
				continue
			var b := esqueleto.get_bone_global_rest(i).basis.orthonormalized()
			_eixo_dedo[i] = (b.inverse() * eixo).normalized()


func _debug_alcance() -> void:
	for pre in ["Left", "Right"]:
		var alvo := _pegada(-1.0 if pre == "Left" else 1.0)
		var tem := _m_esq * esqueleto.get_bone_global_pose(_ossos[pre + "Hand"]).origin
		var ombro := _m_esq * esqueleto.get_bone_global_pose(_ossos[pre + "Arm"]).origin
		var braco := (_pos_repouso(pre + "ForeArm") - _pos_repouso(pre + "Arm")).length() + (_pos_repouso(pre + "Hand") - _pos_repouso(pre + "ForeArm")).length()
		print("[ALCANCE] ", pre, " erro ", snappedf((tem - alvo).length(), 0.001), " ombro->alvo ", snappedf((alvo - ombro).length(), 0.001), " braço ", snappedf(braco, 0.001))
