class_name JaguarArvore
extends Node3D
## Jaguar na árvore seca (Serpent's Climb, pedido do dono 2026-10-06; percursos.N.armadilhas.jaguares:
## [[trecho, m, lado], ...] com lado 1 = direita da estrada, -1 = esquerda; ajustes em armadilhas.jaguar).
## Uma árvore seca gigante (ArvoreSeca) na beira da estrada com um galho grosso estendido por cima da beira da
## pista. O jaguar espera no galho (de pé olhando em volta; agachado de tocaia quando vem carro) e, quando um
## carro passa por baixo, salta no teto e fica agarrado `segura_s` s, meio agachado com as patas da frente na
## beira do para-brisa: a direção fica invertida no chão e no ar (Veiculo.yeti). Quando acaba o tempo ele pula
## para fora da pista e cai até o chão; some no mato e volta para o galho `descanso_s` s depois. O mesmo carro
## fica `imune_s` s (25) sem ser pego de novo pelo mesmo jaguar.
## Tamanho proporcional ao carro (do focinho ao quadril até `proporcao` × comprimento do carro) e ao TETO dele:
## _perfil() mede a lataria de cada carro (mapa de altura tirado da malha) e o jaguar é posto com as patas de
## trás no fundo do teto, a barriga rente e as da frente na beira do para-brisa, cada pata encostada na lataria.
## Modelo: assets/selva/jaguar/jaguar.glb (CC-BY 4.0, Ear.Rodriguez — ver assets/selva/jaguar/creditos.txt).
## O arquivo tem uma animação só com tudo; os trechos usados estão abaixo (s). O agachado é feito aqui por cima
## da animação (IK de dois ossos em cada perna).

const GLB := "res://assets/selva/jaguar/jaguar.glb"
const PARADO := Vector2(0.3, 4.4)       # de pé, olhando em volta
const TOCAIA := Vector2(11.9, 13.6)     # cabeça baixa, rosnando (no galho com carro vindo)
const ESTICA := Vector2(6.0, 7.1)       # espreguiçada: o corpo estica para a frente (o salto)
const VOO := 0.8                        # s do galho até o teto do carro
const GRAVIDADE := 22.0

const RUGIDO := "res://assets/audio/efeitos/rugido_jaguar.ogg"   # rugido "serrado" de onça de verdade (CC-BY, About Zoos)

static var _modelo: Node3D
static var _som_rugido: AudioStream

var _sub: ComplexoSubida
var _terreno: Terreno
var _cfg: Dictionary
var _rng := RandomNumberGenerator.new()
var _log := false
var _t := 0.0
var _bicho: Node3D          # raiz do jaguar (pés na origem, olhando para +Z; focinho→quadril = 1 m × _esc)
var _esc := 1.7
var _ap: AnimationPlayer
var _anim := ""
var _esq: Skeleton3D
var _up_s := Vector3.UP     # cima e frente do bicho no espaço do esqueleto
var _fr_s := Vector3.BACK
var _alt_quadril := 0.5     # altura do quadril em pé (espaço do esqueleto)
var _i_raiz := -1
var _pernas: Array = []     # [osso de cima, do meio, de baixo, é da frente]
var _poleiro: Transform3D
var _c: Vector3             # estrada embaixo do galho
var _tan: Vector3           # sentido da estrada (para onde os carros vão)
var _lat: Vector3           # do centro da estrada para o lado da árvore
var _meia := 6.0
var _estado := "espera"
var _t0 := 0.0
var _v: Veiculo
var _de: Vector3
var _vel := Vector3.ZERO    # na queda
var _ginga := 0.0
var _ciclo := 0.0           # relógio da animação em laço
var _z_tras := -0.1         # patas de trás e da frente em pé, à frente do quadril (unidades do bicho: focinho→quadril = 1)
var _z_frente := 0.6
var _fila_perfil: Array = []   # carros que ainda não tiveram a lataria medida (um por vez, antes da largada)
var _imune := {}            # carro (id) → até quando este jaguar não pula nele de novo
var _voz: AudioStreamPlayer3D
var _peso := 0.0            # agachado pedido para este quadro (ver _agachar)
var _agarra := 0.0


func montar(sub: ComplexoSubida, terreno: Terreno, item: Array, cfg: Dictionary) -> void:
	_sub = sub
	_terreno = terreno
	_cfg = cfg
	_rng.seed = hash(str(item))
	_log = OS.get_environment("TSC_JAGUAR_LOG") != ""
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var lado := float(item[2]) if item.size() > 2 else 1.0
	_c = sub.amostra(i)
	var t := sub.tangente_em(i)
	_tan = Vector3(t.x, 0.0, t.z).normalized()
	var l := sub.lateral_em(i)
	_lat = Vector3(l.x, 0.0, l.z).normalized() * signf(lado)
	_meia = sub.largura_em(i) * 0.5
	var afast := float(cfg.get("afastamento", 9.0))   # do eixo do tronco até a beira da pista
	var poleiro_y := _c.y + float(cfg.get("altura", 8.5))
	# Lado pedido tem morro mais alto que a pista (a árvore nasceria dentro da pedra): usa o outro lado
	if _chao(_c + _lat * (_meia + afast)) > _c.y - 4.0 and _chao(_c - _lat * (_meia + afast)) < _c.y - 4.0:
		_lat = -_lat
		if _log:
			print("[JAGUAR] %s %s: morro no lado pedido, árvore do outro lado" % [str(item[0]), str(item[1])])
	# Árvore do tamanho da altura da pista ali: quanto mais alta, mais grossa — e mais longe da beira
	var y_f := poleiro_y - 3.5 - minf(_chao(_c + _lat * (_meia + afast)), _c.y)
	afast = maxf(afast, ArvoreSeca.raio_base(y_f) * 0.5 + 6.0)
	var pe := _c + _lat * (_meia + afast)
	pe.y = minf(_chao(pe), _c.y)
	var arv := ArvoreSeca.criar(self, pe, -_lat, poleiro_y, afast + 2.5, 7331 + i, func(x: float, z: float) -> float: return _chao(Vector3(x, 0.0, z)))
	_poleiro = arv.poleiro
	if _log:
		print("[JAGUAR] %s %s: árvore em %s (pista y %.1f, chão %.1f → %.0f m até o galho, tronco %.1f m de raio), poleiro %s" % [str(item[0]), str(item[1]), str(pe.snapped(Vector3.ONE)), _c.y, pe.y, poleiro_y - pe.y, ArvoreSeca.raio_base(poleiro_y - 3.5 - pe.y), str(_poleiro.origin.snapped(Vector3.ONE * 0.1))])
	_esc = float(cfg.get("proporcao", 0.4)) * float(cfg.get("carro_m", 4.2))
	_criar_bicho()


func _chao(p: Vector3) -> float:
	return _terreno.altura_em(p.x, p.z) if _terreno else _c.y - 1.0


static func _carregar() -> Node3D:
	if _modelo == null:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(GLB), st) != OK:
			push_warning("JaguarArvore: não leu %s" % GLB)
			return null
		_modelo = doc.generate_scene(st)
	return _modelo


## Jaguar: cópia do modelo dentro de uma raiz com os pés na origem, olhando para +Z, 1 m do focinho ao quadril
## (a raiz é escalada por _esc).
func _criar_bicho() -> void:
	var base := _carregar()
	_bicho = Node3D.new()
	_bicho.name = "Jaguar"
	add_child(_bicho)
	if base == null:
		return
	var no := base.duplicate() as Node3D
	_bicho.add_child(no)
	_ap = no.find_children("*", "AnimationPlayer", true, false)[0]
	_anim = _ap.get_animation_list()[0]
	_ap.play(_anim)
	_ap.pause()
	_ap.seek(PARADO.x, true)
	_esq = no.find_children("*", "Skeleton3D", true, false)[0]
	var cab := _pos_bicho(_osso("Head_M"))
	var quadril := _pos_bicho(_osso("Root_M"))
	var pe_y := INF
	for nome in ["Toes2_R_end", "Toes2_L_end", "Fingers1_R", "Fingers1_L"]:
		pe_y = minf(pe_y, _pos_bicho(_osso(nome)).y)
	var frente := Vector3(cab.x - quadril.x, 0.0, cab.z - quadril.z)
	var giro := Basis(Vector3.UP, frente.normalized().signed_angle_to(Vector3.BACK, Vector3.UP))
	var b := giro.scaled(Vector3.ONE / maxf(frente.length(), 0.01))
	var pivo := Vector3(quadril.x, pe_y, quadril.z)
	no.transform = Transform3D(b, -(b * pivo)) * no.transform
	for mi: MeshInstance3D in no.find_children("*", "MeshInstance3D", true, false):
		mi.extra_cull_margin = 2.0   # a caixa da malha em repouso é bem menor que o bicho animado
	# Referências do esqueleto para o agachado: cima/frente do bicho e as quatro pernas
	var bs := _esq.global_transform.basis.inverse() * _bicho.global_transform.basis
	_up_s = (bs * Vector3.UP).normalized()
	_fr_s = (bs * Vector3.BACK).normalized()
	_i_raiz = _osso("Root_M")
	_z_tras = (_pos_bicho(_osso("Ankle_R")).z + _pos_bicho(_osso("Ankle_L")).z) * 0.5
	_z_frente = (_pos_bicho(_osso("Wrist_R")).z + _pos_bicho(_osso("Wrist_L")).z) * 0.5
	_alt_quadril = (_esq.get_bone_global_pose(_i_raiz).origin - _esq.get_bone_global_pose(_osso("Ankle_R")).origin).dot(_up_s)
	for s in ["R", "L"]:
		_pernas.append([_osso("Hip_" + s), _osso("Knee_" + s), _osso("Ankle_" + s), false])
		_pernas.append([_osso("Shoulder_" + s), _osso("Elbow_" + s), _osso("Wrist_" + s), true])
	# Voz: o rugido sai do próprio bicho (lido direto do .ogg, sem depender da importação)
	if _som_rugido == null and FileAccess.file_exists(RUGIDO):
		_som_rugido = AudioStreamOggVorbis.load_from_file(RUGIDO)
	_voz = AudioStreamPlayer3D.new()
	_voz.stream = _som_rugido
	_voz.bus = "Efeitos"
	_voz.unit_size = 35.0
	_voz.max_distance = 600.0
	_voz.volume_db = 6.0
	_bicho.add_child(_voz)
	# O agachado entra como modificador do esqueleto: roda depois da animação a cada quadro (mexer nos ossos
	# direto era desfeito no quadro seguinte)
	var mod := Agacho.new()
	mod.dono = self
	_esq.add_child(mod)
	_colocar(_poleiro)


class Agacho extends SkeletonModifier3D:
	var dono: Node

	func _process_modification() -> void:
		dono._aplicar_agacho()


func _osso(prefixo: String) -> int:
	for k in _esq.get_bone_count():
		if _esq.get_bone_name(k).begins_with(prefixo):
			return k
	return 0


func _pos_bicho(i: int) -> Vector3:
	return _bicho.to_local(_esq.global_transform * _esq.get_bone_global_pose(i).origin)


## Põe o bicho no lugar (pés em xf.origin) com o tamanho atual.
func _colocar(xf: Transform3D) -> void:
	_bicho.global_transform = Transform3D(xf.basis.orthonormalized().scaled_local(Vector3.ONE * _esc), xf.origin)


func _physics_process(delta: float) -> void:
	if _ap == null:
		return
	_t += delta
	_ciclo += delta
	_medir_carros()
	var dur := _t - _t0
	match _estado:
		"espera":
			_colocar(_poleiro)
			var perto := _carro_vindo(70.0)
			_laco(PARADO)
			_agachar(0.6 if perto else 0.0, 0.0)   # de tocaia quando vem carro
			if dur < float(_cfg.get("descanso_s", 3.0)):
				return
			var v := _alvo()
			if v:
				_v = v
				_estado = "ida"
				_t0 = _t
				_de = _bicho.global_position
				_v.set_meta("jaguar", true)
				Armadilhas.ultimo_agarrado = _v   # conferência: as vistas gelo_yeti_lado/_frente/_seguir seguem este carro
				Audio.tocar("efeitos/whoosh.wav", _de, -2.0, 0.8)
				_rugir()
				if _log:
					print("[JAGUAR] saltou em %s (%.1f s)" % [_v.name, _t])
		"ida":
			if not _valido(_v):
				_soltar()
				return
			var u := clampf(dur / VOO, 0.0, 1.0)
			# No ar ele vai tomando o tamanho proporcional ao carro em que vai cair
			var esc0 := float(_cfg.get("proporcao", 0.4)) * float(_cfg.get("carro_m", 4.2))
			_esc = lerpf(esc0, _tamanho_no(_v), u)
			var alvo := _teto(_v)
			var p := _de.lerp(alvo.origin, u) + Vector3.UP * 2.5 * 4.0 * u * (1.0 - u)
			# Olha para onde voa (inclinado para baixo na descida) e chega já virado como o carro
			var rumo := (alvo.origin - _de)
			var b_voo := Basis.looking_at(-Vector3(rumo.x, rumo.y * (2.0 * u - 0.6), rumo.z).normalized(), Vector3.UP) if rumo.length() > 0.5 else _poleiro.basis
			_colocar(Transform3D(b_voo.slerp(alvo.basis.orthonormalized(), smoothstep(0.55, 1.0, u)), p))
			_pose(lerpf(ESTICA.x, ESTICA.y, u))
			_agachar(0.0, 0.0)
			if u >= 1.0:
				_estado = "agarrado"
				_t0 = _t
				_ciclo = 0.0
				_v.yeti(float(_cfg.get("segura_s", 4.0)))
				# O mesmo carro fica um tempo imune a este jaguar (quem cai da ponte renasce antes da árvore e seria
				# pego de novo, sem fim)
				_imune[_v.get_instance_id()] = _t + float(_cfg.get("imune_s", 25.0))
				Audio.tocar("efeitos/batida_leve_", alvo.origin, -4.0, 0.7)
				if _log:
					print("[JAGUAR] pegou %s em %.1f s (tamanho %.2f, carro %.1f m)" % [_v.name, _t, _esc, _comprimento(_v)])
					var pf_log := _perfil(_v)
					print("[JAGUAR] teto de %s: z %.2f..%.2f (%.2f m), y %.2f" % [_v.name, pf_log.z_frente, pf_log.z_tras, float(pf_log.z_tras) - float(pf_log.z_frente), pf_log.y_teto])
		"agarrado":
			if not _valido(_v) or not _v.direcao_invertida() or dur >= float(_cfg.get("segura_s", 4.0)):
				_soltar()
				return
			_ginga = lerpf(_ginga, clampf(_v.angular_velocity.y * 0.6, -1.0, 1.0), delta * 5.0)
			_colocar(_teto(_v) * Transform3D(Basis(Vector3.BACK, _ginga * 0.22), Vector3.ZERO))
			_laco(PARADO)
			# Meio agachado, barriga perto do teto, patas da frente agarradas na beira do para-brisa
			var u := smoothstep(0.0, 0.25, dur)
			_agachar(u, u)
		"pulo":
			# Pula para fora da pista e cai até o chão (lá embaixo, se a estrada é ponte)
			_vel.y -= GRAVIDADE * delta
			var p := _bicho.global_position + _vel * delta
			var chao := _chao(p)
			var b := Basis.looking_at(-Vector3(_vel.x, 0.0, _vel.z).normalized(), Vector3.UP) if Vector2(_vel.x, _vel.z).length() > 0.3 else _bicho.global_transform.basis
			var b_atual := _bicho.global_transform.basis.orthonormalized()
			var inclina := clampf(_vel.y / 30.0, -0.6, 0.3)
			var b_alvo := b * Basis(Vector3.RIGHT, -inclina)
			if p.y <= chao:
				p.y = chao
				_estado = "caiu"
				_t0 = _t
				_ciclo = 0.0
				b_alvo = b
				Audio.tocar("efeitos/pouso_", p, -6.0, 0.8)
				if _log:
					print("[JAGUAR] caiu no chão em %s (%.1f s)" % [str(p.snapped(Vector3.ONE)), _t])
			_colocar(Transform3D(b_atual.slerp(b_alvo, minf(delta * 6.0, 1.0)), p))
			_pose(lerpf(ESTICA.x, ESTICA.y, clampf(dur / 0.6, 0.0, 1.0)))
			_agachar(0.0, 0.0)
		"caiu":
			# Aterrissa agachado e fica um instante antes de sumir no mato
			_laco(PARADO)
			_agachar(1.0 - smoothstep(0.3, 1.2, dur), 0.0)
			if dur >= 1.6:
				_bicho.visible = false
				_estado = "sumido"
				_t0 = _t
		"sumido":
			if dur >= float(_cfg.get("descanso_s", 3.0)):
				_esc = float(_cfg.get("proporcao", 0.4)) * float(_cfg.get("carro_m", 4.2))
				_colocar(_poleiro)
				_bicho.visible = true
				_estado = "espera"
				_t0 = _t


func _rugir() -> void:
	if _voz and _voz.stream:
		_voz.pitch_scale = _rng.randf_range(0.92, 1.06)
		_voz.play()


## Toca a animação em laço dentro do trecho.
func _laco(trecho: Vector2) -> void:
	_pose(trecho.x + fposmod(_ciclo, trecho.y - trecho.x))


func _pose(t: float) -> void:
	_ap.seek(t, true)


func _valido(v: Veiculo) -> bool:
	return v != null and is_instance_valid(v) and not v.eliminado


func _comprimento(v: Veiculo) -> float:
	return clampf(v.caixa_corpo.size.z, 3.0, 6.0) if v.caixa_corpo.size.z > 0.1 else 4.2


## Larga o carro (ou desiste do salto) e pula para fora da pista, do lado mais perto, com o embalo do carro.
func _soltar() -> void:
	var embalo := Vector3.ZERO
	if _v != null and is_instance_valid(_v):
		_v.remove_meta("jaguar")
		embalo = _v.linear_velocity * 0.6
	var de := _bicho.global_position
	var ip := _sub.indice_estrada(de, 30.0)
	var centro: Vector3 = _sub.amostra(ip) if ip >= 0 else _c
	var lat: Vector3 = _sub.lateral_em(ip) if ip >= 0 else _lat
	lat = Vector3(lat.x, 0.0, lat.z).normalized()
	if lat.dot(de - centro) < 0.0:
		lat = -lat
	var meia := _sub.largura_em(ip) * 0.5 if ip >= 0 else _meia
	# Passa da beira em ~0,55 s, subindo um pouco antes de cair
	var falta := maxf(meia + 3.0 - (de - centro).dot(lat), 2.0)
	_vel = Vector3(embalo.x, 0.0, embalo.z) + lat * (falta / 0.55) + Vector3.UP * 6.0
	_v = null
	_estado = "pulo"
	_t0 = _t
	if _log:
		print("[JAGUAR] pulou para fora em %.1f s" % _t)


## Tamanho do jaguar em cima deste carro: as quatro patas cabem no teto (as de trás no fundo, as da frente
## chegando na beira do para-brisa), sem passar da proporção com o carro inteiro.
func _tamanho_no(v: Veiculo) -> float:
	var pf := _perfil(v)
	var teto := float(pf.z_tras) - float(pf.z_frente)
	var comp := _comprimento(v)
	return clampf(0.8 * teto / maxf(_z_frente - _z_tras, 0.2), 0.24 * comp, float(_cfg.get("proporcao", 0.4)) * comp)


## Lugar do jaguar no carro (pés): no meio do teto de lado a lado, com as patas de trás a ~12% do fundo do
## teto, olhando para a frente do carro (o modelo olha para +Z; o carro anda para -Z, então o z do carro
## cresce para trás).
func _teto(v: Veiculo) -> Transform3D:
	var pf := _perfil(v)
	var xf := v.global_transform
	var z_patas := float(pf.z_tras) - 0.12 * (float(pf.z_tras) - float(pf.z_frente))
	var z0 := z_patas + _esc * _z_tras
	var topo := Vector3(pf.x_meio, _topo(pf, pf.x_meio, z_patas), z0)
	return Transform3D(xf.basis.orthonormalized() * Basis(Vector3.UP, PI), xf * topo)


## Mede a lataria dos carros um por vez (cada medida varre a malha do carro), logo no começo, para não pesar
## na hora do salto.
func _medir_carros() -> void:
	if _t < 0.5:
		return
	if _fila_perfil.is_empty() and not has_meta("medido"):
		set_meta("medido", true)
		_fila_perfil = get_tree().get_nodes_in_group("veiculo")
	if _fila_perfil.is_empty() or Engine.get_physics_frames() % 6 != 0:
		return
	var v := _fila_perfil.pop_back() as Veiculo
	if v != null and is_instance_valid(v):
		_perfil(v)


## Lataria do carro vista de cima: mapa de altura (no espaço do carro) tirado dos triângulos da malha, e onde
## fica o teto (z_frente..z_tras, y_teto). Guardado no próprio carro.
func _perfil(v: Veiculo) -> Dictionary:
	if v.has_meta("perfil_lataria"):
		return v.get_meta("perfil_lataria")
	var cx := v.caixa_corpo
	var passo := 0.08
	var nx := int(ceil(cx.size.x / passo)) + 1
	var nz := int(ceil(cx.size.z / passo)) + 1
	var tops := PackedFloat32Array()
	tops.resize(nx * nz)
	tops.fill(-INF)
	var y_min := cx.position.y + cx.size.y * 0.35
	var inv := v.global_transform.affine_inverse()
	var raiz_malhas: Node = v.modelo if v.modelo else v
	for no in raiz_malhas.find_children("*", "MeshInstance3D", true, false):
		var mi := no as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var xm := inv * mi.global_transform
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size() - 2, 3):
			var a := xm * faces[i]
			var b := xm * faces[i + 1]
			var c := xm * faces[i + 2]
			if maxf(a.y, maxf(b.y, c.y)) < y_min:
				continue
			var ix0 := clampi(int((minf(a.x, minf(b.x, c.x)) - cx.position.x) / passo), 0, nx - 1)
			var ix1 := clampi(int((maxf(a.x, maxf(b.x, c.x)) - cx.position.x) / passo), 0, nx - 1)
			var iz0 := clampi(int((minf(a.z, minf(b.z, c.z)) - cx.position.z) / passo), 0, nz - 1)
			var iz1 := clampi(int((maxf(a.z, maxf(b.z, c.z)) - cx.position.z) / passo), 0, nz - 1)
			var det := (b.z - c.z) * (a.x - c.x) + (c.x - b.x) * (a.z - c.z)
			if (ix0 == ix1 and iz0 == iz1) or absf(det) < 0.000001:
				# pequeno (ou de pé): só os cantos
				for q: Vector3 in [a, b, c]:
					var kq := clampi(int((q.z - cx.position.z) / passo), 0, nz - 1) * nx + clampi(int((q.x - cx.position.x) / passo), 0, nx - 1)
					tops[kq] = maxf(tops[kq], q.y)
				continue
			for iz in range(iz0, iz1 + 1):
				var pz := cx.position.z + (iz + 0.5) * passo
				for ix in range(ix0, ix1 + 1):
					var px := cx.position.x + (ix + 0.5) * passo
					var w1 := ((b.z - c.z) * (px - c.x) + (c.x - b.x) * (pz - c.z)) / det
					var w2 := ((c.z - a.z) * (px - c.x) + (a.x - c.x) * (pz - c.z)) / det
					var w3 := 1.0 - w1 - w2
					if w1 < -0.02 or w2 < -0.02 or w3 < -0.02:
						continue
					var k := iz * nx + ix
					tops[k] = maxf(tops[k], a.y * w1 + b.y * w2 + c.y * w3)
	# Teto: na faixa do meio do carro, o trecho contínuo em volta do ponto mais alto (até 18 cm abaixo dele)
	var x_meio := cx.get_center().x
	var faixa := PackedFloat32Array()
	faixa.resize(nz)
	var y_teto := -INF
	var iz_alto := nz / 2
	var ixa := clampi(int((x_meio - 0.2 - cx.position.x) / passo), 0, nx - 1)
	var ixb := clampi(int((x_meio + 0.2 - cx.position.x) / passo), 0, nx - 1)
	for iz in nz:
		var m := -INF
		for ix in range(ixa, ixb + 1):
			m = maxf(m, tops[iz * nx + ix])
		faixa[iz] = m
		if m > y_teto:
			y_teto = m
			iz_alto = iz
	var i_f := iz_alto
	var i_t := iz_alto
	while i_f > 0 and faixa[i_f - 1] >= y_teto - 0.18:
		i_f -= 1
	while i_t < nz - 1 and faixa[i_t + 1] >= y_teto - 0.18:
		i_t += 1
	var z_frente := cx.position.z + i_f * passo
	var z_tras := cx.position.z + (i_t + 1) * passo
	if y_teto == -INF or z_tras - z_frente < 0.6 or z_tras - z_frente > cx.size.z * 0.8:
		# malha estranha (conversível, caminhonete...): teto presumido no meio do carro
		y_teto = cx.end.y if y_teto == -INF else y_teto
		z_frente = cx.get_center().z - cx.size.z * 0.12
		z_tras = cx.get_center().z + cx.size.z * 0.22
	var pf := {"tops": tops, "nx": nx, "nz": nz, "passo": passo, "x0": cx.position.x, "z0": cx.position.z,
		"x_meio": x_meio, "y_teto": y_teto, "z_frente": z_frente, "z_tras": z_tras, "y_min": y_min}
	v.set_meta("perfil_lataria", pf)
	return pf


## Altura da lataria (espaço do carro) no ponto (x, z): o mais alto da célula e das vizinhas (cobre furos da
## malha e frestas).
func _topo(pf: Dictionary, x: float, z: float) -> float:
	var nx: int = pf.nx
	var nz: int = pf.nz
	var ix := clampi(int((x - float(pf.x0)) / float(pf.passo)), 0, nx - 1)
	var iz := clampi(int((z - float(pf.z0)) / float(pf.passo)), 0, nz - 1)
	var tops: PackedFloat32Array = pf.tops
	var m := -INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			m = maxf(m, tops[clampi(iz + dz, 0, nz - 1) * nx + clampi(ix + dx, 0, nx - 1)])
	return m if m > -INF else float(pf.y_min)


## Agachado por cima da pose da animação: o corpo desce (`peso` 0..1 → até ~45% da altura do quadril) com os
## pés no lugar; `agarra` 0..1 leva as patas da frente para a frente e para baixo (beira do para-brisa).
func _agachar(peso: float, agarra: float) -> void:
	_peso = peso
	_agarra = agarra


func _aplicar_agacho() -> void:
	var peso := _peso
	var agarra := _agarra
	if peso <= 0.001 or _esq == null:
		return
	var alvos := []
	var pes := []
	# No carro: cada pata vai para a lataria de verdade (as da frente, para a beira do para-brisa)
	var no_carro := _estado == "agarrado" and _valido(_v)
	var pf := _perfil(_v) if no_carro else {}
	var e_c := (_v.global_transform.affine_inverse() * _esq.global_transform) if no_carro else Transform3D.IDENTITY   # esqueleto → carro
	for perna: Array in _pernas:
		var g := _esq.get_bone_global_pose(perna[2])
		var t := g.origin
		if no_carro:
			var pc := e_c * t
			if perna[3]:
				# até 8 cm além da beira da frente do teto, sem esticar mais que 0,3 do corpo
				pc.z = lerpf(pc.z, clampf(float(pf.z_frente) - 0.08, pc.z - 0.3 * _esc, pc.z), agarra)
			var dx := pc.x - float(pf.x_meio)
			pc.x = float(pf.x_meio) + signf(dx) * minf(absf(dx), _v.caixa_corpo.size.x * 0.3)
			pc.y = lerpf(pc.y, _topo(pf, pc.x, pc.z) + 0.05 * _esc, agarra)
			t = e_c.affine_inverse() * pc
		elif perna[3]:
			t += _fr_s * _alt_quadril * 0.45 * agarra - _up_s * _alt_quadril * 0.12 * agarra
		alvos.append(t)
		pes.append(g.basis)
	var raiz := _esq.get_bone_global_pose(_i_raiz)
	raiz.origin -= _up_s * _alt_quadril * (0.58 if no_carro else 0.45) * peso
	_esq.set_bone_global_pose(_i_raiz, raiz)
	for k in _pernas.size():
		var perna: Array = _pernas[k]
		_ik(perna[0], perna[1], perna[2], alvos[k])
		var g := _esq.get_bone_global_pose(perna[2])
		g.basis = pes[k]   # o pé (pata) continua apoiado como estava
		_esq.set_bone_global_pose(perna[2], g)


## IK de dois ossos: dobra a perna (a → b → c) para c chegar em `alvo`, mantendo o lado para onde ela já dobra.
func _ik(ia: int, ib: int, ic: int, alvo: Vector3) -> void:
	var a := _esq.get_bone_global_pose(ia).origin
	var b := _esq.get_bone_global_pose(ib).origin
	var c := _esq.get_bone_global_pose(ic).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 0.0001 or l2 < 0.0001:
		return
	var at := alvo - a
	var d := clampf(at.length(), absf(l1 - l2) + 0.001, (l1 + l2) * 0.999)
	var dir := at.normalized()
	var ac := (c - a).normalized()
	var polo := (b - a) - ac * (b - a).dot(ac)
	if polo.length() < 0.0001:
		polo = _fr_s
	polo = (polo - dir * polo.dot(dir)).normalized()
	var ca := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var b2 := a + dir * l1 * ca + polo * l1 * sqrt(1.0 - ca * ca)
	_girar(ia, b - a, b2 - a)
	var b3 := _esq.get_bone_global_pose(ib).origin
	var c3 := _esq.get_bone_global_pose(ic).origin
	_girar(ib, c3 - b3, a + dir * d - b3)


func _girar(i: int, de: Vector3, para: Vector3) -> void:
	if de.length() < 0.0001 or para.length() < 0.0001:
		return
	var g := _esq.get_bone_global_pose(i)
	g.basis = Basis(Quaternion(de.normalized(), para.normalized())) * g.basis
	_esq.set_bone_global_pose(i, g)


## Algum carro vindo pela estrada a menos de `dist` m do galho (o jaguar se abaixa de tocaia).
func _carro_vindo(dist: float) -> bool:
	for no in get_tree().get_nodes_in_group("veiculo"):
		var v := no as Veiculo
		if v == null or v.eliminado or v.fantasma():
			continue
		var q := v.global_position - _c
		var ao_longo := q.dot(_tan)
		if ao_longo > -dist and ao_longo < 5.0 and absf(q.dot(_lat)) < _meia + 10.0 and absf(q.y) < 25.0:
			return true
	return false


## Carro que vai estar embaixo do galho quando o salto chegar: pula na hora em que o carro, na velocidade
## dele, leva ~VOO s até ali (o salto persegue o teto, então pega mesmo se ele frear ou virar).
func _alvo() -> Veiculo:
	var melhor: Veiculo = null
	var melhor_t := INF
	for no in get_tree().get_nodes_in_group("veiculo"):
		var v := no as Veiculo
		if v == null or v.eliminado or v.fantasma() or not v.visible or v.direcao_invertida() or v.has_meta("jaguar"):
			continue
		if _t < float(_imune.get(v.get_instance_id(), 0.0)):
			continue
		var q := v.global_position - _c
		if absf(q.dot(_lat)) > _meia + 2.0 or absf(q.y) > 15.0:
			continue
		var ao_longo := q.dot(_tan)   # < 0: ainda vem
		var vel := maxf(v.linear_velocity.dot(_tan), 0.0)
		var chega := -ao_longo / maxf(vel, 1.0)
		var pronto := (ao_longo < 0.0 and chega <= VOO + 0.05) or absf(ao_longo) < 4.0
		if pronto and ao_longo > -90.0 and chega < melhor_t:
			melhor_t = chega
			melhor = v
	return melhor
