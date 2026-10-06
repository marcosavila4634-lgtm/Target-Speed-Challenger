class_name SerpenteGigante
extends Node3D
## Serpente gigante que rasteja pela mata do Serpent's Climb (mapa.subida.selva.serpente_gigante). Só
## enfeite: não ataca e não tem colisão.
## - modelo: assets/selva/cobra/cobra.glb, a naja marrom da pasta do dono (ver creditos.txt, CC-BY)
##   desenrolada pelos próprios ossos (tools/serpents_climb/endireitar_cobra_ossos.gd) — reta, cabeça em
##   z = 0 olhando para -Z, barriga em y = 0;
## - aqui ela ganha um esqueleto (OSSOS ossos em fila, pele presa aos dois ossos vizinhos) e cada osso
##   segue a MESMA trilha no chão, um atrás do outro: o corpo passa por onde a cabeça passou, como cobra
##   de verdade;
## - a trilha é uma volta fechada pelos pontos de `rota` com o serpenteio somado (tracar); a mata não
##   nasce em cima dela (Selva._na_trilha).
## Todas as cobras do mapa usam este modelo (pedido do dono: todas da mesma cor): as do bote
## (SerpenteBote) e as pequenas dos poços da plataforma montam com montar_pontos (trilha 3D pronta,
## fechada ou aberta).

const MODELO := "res://assets/selva/cobra/cobra.glb"
const OSSOS := 84
const CABECA := 22.0         # até onde vão a cabeça e o capelo no modelo (unidades dele): não esticam com o corpo
const LARGURA_CORPO := 6.2   # largura do corpo no modelo (a cabeça é mais larga): `grossura` é a do corpo

static var _malhas := {}   # "comprimento_grossura" -> [ArrayMesh, altura do corpo]
static var _origem: Mesh   # a malha do .glb como veio

var _esq: Skeleton3D
var _pts := PackedVector3Array()    # trilha, um ponto a cada ~1 m (fechada: o último ponto liga no primeiro)
var _s := PackedFloat32Array()      # metros acumulados até cada ponto
var _total := 0.0
var _comp := 260.0
var _vel := 7.0
var _alto := 4.0
var _gross := 5.0
var _pos := 0.0                     # onde a cabeça está na trilha (m)
var _t := 0.0
var _z := PackedFloat32Array()      # distância de cada osso até o focinho
var _p := PackedVector3Array()
var _ossos := OSSOS
var _fechada := true                # aberta: antes do começo a trilha segue reta para trás; depois do fim, para
## Bote (SerpenteBote): deslocamento da cabeça, que vai sumindo pelo pescoço (_bote_pescoco do corpo)
var _bote := Vector3.ZERO
var _bote_pescoco := 0.25
var _erguer := 1.0                  # quanto a cabeça vai erguida (1 = o de sempre)


static func _v2(q) -> Vector2:
	return Vector2(float(q[0]), float(q[1]))


## Trilha fechada no chão (x, z), um ponto a cada ~1 m: curva suave pelos pontos de `rota` mais o
## serpenteio [amplitude, comprimento de onda], que some perto das estradas (o corpo passa reto por
## baixo delas, entre os pilares).
static func tracar(cfg: Dictionary, selva: Selva) -> PackedVector2Array:
	var ctrl: Array = cfg.get("rota", [])
	var n := ctrl.size()
	var saida := PackedVector2Array()
	if n < 3:
		return saida
	var curva := Curve2D.new()
	curva.bake_interval = 1.0
	for i in n + 1:
		var h := (_v2(ctrl[(i + 1) % n]) - _v2(ctrl[(i - 1 + n) % n])) / 6.0
		curva.add_point(_v2(ctrl[i % n]), -h, h)
	var base := curva.get_baked_points()
	base.remove_at(base.size() - 1)   # igual ao primeiro
	var onda: Array = cfg.get("serpenteio", [7.0, 85.0])
	var ondas := maxi(roundi(curva.get_baked_length() / maxf(float(onda[1]), 10.0)), 1)
	var m := base.size()
	for i in m:
		var t := (base[(i + 1) % m] - base[(i - 1 + m) % m]).normalized()
		var amp := float(onda[0]) * smoothstep(14.0, 30.0, selva.dist_estrada(base[i]))
		saida.append(base[i] + Vector2(-t.y, t.x) * amp * sin(TAU * ondas * float(i) / m))
	return saida


func montar(trilha: PackedVector2Array, terreno: Terreno, cfg: Dictionary) -> void:
	name = "SerpenteGigante"
	if trilha.size() < 8:
		return
	var md := _malha(float(cfg.get("comprimento", 260.0)), float(cfg.get("grossura", 5.0)), int(cfg.get("ossos", OSSOS)))
	if md.is_empty():
		return
	# Trilha no chão: altura do terreno alisada (o corpo não treme nos degraus da malha do terreno); no
	# rio ela nada com as costas de fora
	var agua := float(Config.valor("mapa.nivel_agua", 4)) - float(md[1]) * 0.6
	var m := trilha.size()
	var h := PackedFloat32Array()
	for q in trilha:
		h.append(maxf(terreno.altura_em(q.x, q.y), agua))
	var pts := PackedVector3Array()
	for i in m:
		var soma := 0.0
		for k in range(-4, 5):
			soma += h[(i + k + m) % m]
		pts.append(Vector3(trilha[i].x, soma / 9.0, trilha[i].y))
	montar_pontos(pts, cfg)
	if OS.get_environment("TSC_SERPENTE_S") != "":
		_pos = float(OS.get_environment("TSC_SERPENTE_S"))   # conferência: onde a cabeça começa (m da trilha)
		_posar()
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SERPENTE] trilha %.0f m, corpo %.0f m x %.1f m de altura, chão %.1f a %.1f" % [_total, _comp, _alto, Array(h).min(), Array(h).max()])


## Trilha 3D pronta (um ponto a cada ~1 m). cfg: comprimento, grossura, velocidade, inicio (m da trilha
## onde a cabeça começa), ossos, alcance_visivel.
func montar_pontos(pts: PackedVector3Array, cfg: Dictionary, fechada := true) -> void:
	_comp = float(cfg.get("comprimento", 260.0))
	_vel = float(cfg.get("velocidade", 7.0))
	_gross = float(cfg.get("grossura", 5.0))
	_ossos = int(cfg.get("ossos", OSSOS))
	_fechada = fechada
	var md := _malha(_comp, _gross, _ossos)
	if md.is_empty() or pts.size() < 3:
		return
	_alto = md[1]
	_gross = md[2]
	_pts = pts
	var m := pts.size()
	var n := m + 1 if fechada else m
	_s.clear()
	_s.append(0.0)
	for i in range(1, n):
		_s.append(_s[i - 1] + _pts[i % m].distance_to(_pts[i - 1]))
	_total = _s[n - 1]
	_pos = float(cfg.get("inicio", 0.0))
	_esq = Skeleton3D.new()
	add_child(_esq)
	for i in _ossos:
		_z.append(_comp * i / (_ossos - 1))
		_esq.add_bone("o%d" % i)
		_esq.set_bone_rest(i, Transform3D(Basis.IDENTITY, Vector3(0, 0, _z[i])))
	_p.resize(_ossos)
	var mi := MeshInstance3D.new()
	mi.mesh = md[0]
	var caixa := AABB(_pts[0], Vector3.ZERO)
	for q in _pts:
		caixa = caixa.expand(q)
	mi.custom_aabb = caixa.grow(_alto * 3.0 + (0.0 if fechada else _comp))   # a pele anda com os ossos: a caixa é a da trilha toda
	mi.visibility_range_end = float(cfg.get("alcance_visivel", 2600.0))
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # ossos atualizados a cada quadro
	_esq.add_child(mi)
	mi.skeleton = NodePath("..")   # sem isto a pele não acha os ossos e não é desenhada
	_pintar(mi, cfg)
	_posar()


## Cobras de cor (cfg "cor": preta, verde, coral, cascavel): a pele do modelo tingida/desenhada
## (shaders/cobra_pele.gdshader). Sem "cor", a cor natural do modelo.
const CORES := {"preta": [Color(0.13, 0.13, 0.15), 0], "verde": [Color(0.75, 1.7, 0.45), 0], "coral": [Color.WHITE, 1], "cascavel": [Color.WHITE, 2]}

func _pintar(mi: MeshInstance3D, cfg: Dictionary) -> void:
	var cor := str(cfg.get("cor", ""))
	if not CORES.has(cor):
		return
	var orig := mi.mesh.surface_get_material(0) as StandardMaterial3D
	if orig == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cobra_pele.gdshader")
	mat.set_shader_parameter("pele", orig.albedo_texture)
	mat.set_shader_parameter("relevo", orig.normal_texture)
	mat.set_shader_parameter("tinta", CORES[cor][0])
	mat.set_shader_parameter("desenho", CORES[cor][1])
	mat.set_shader_parameter("comprimento", _comp)
	mat.set_shader_parameter("anel", maxf(_gross * 1.6, 1.0))
	mi.material_override = mat


## Ponto da trilha a `s` m do começo (fechada: dá a volta; aberta: para no fim e segue reta antes do começo).
func _na_trilha(s: float) -> Vector3:
	if not _fechada:
		if s < 0.0:
			return _pts[0] + (_pts[0] - _pts[1]).normalized() * -s
		s = minf(s, _total)
	else:
		s = fposmod(s, _total)
	var a := 0
	var b := _s.size() - 1
	while b - a > 1:
		var meio := (a + b) >> 1
		if _s[meio] <= s:
			a = meio
		else:
			b = meio
	var t := (s - _s[a]) / maxf(_s[b] - _s[a], 0.001)
	return _pts[a].lerp(_pts[b % _pts.size()], t)


func _process(delta: float) -> void:
	if _esq == null:
		return
	_t += delta
	_avancar(delta)
	_posar()


## Anda a cabeça pela trilha (SerpenteBote troca: ronda com bote, ou sai e volta da toca).
func _avancar(delta: float) -> void:
	_pos += _vel * delta


func _posar() -> void:
	# Pescoço: a cabeça vai um pouco erguida e balança de leve para os lados, procurando o caminho
	var pescoco := _comp * 0.09
	var bote_l := maxf(_comp * _bote_pescoco, 1.0)
	for i in _ossos:
		var q := _na_trilha(_pos - _z[i])
		var f := maxf(1.0 - _z[i] / pescoco, 0.0)
		if f > 0.0:
			var adiante := _na_trilha(_pos - _z[i] + 2.0) - q
			var lado := Vector3(-adiante.z, 0.0, adiante.x).normalized()
			q += Vector3.UP * (_alto * 0.75 * _erguer * f * f * (0.8 + 0.2 * sin(_t * 0.5))) + lado * (_alto * 0.45 * f * f * sin(_t * 0.9))
		if _bote != Vector3.ZERO:
			var fb := maxf(1.0 - _z[i] / bote_l, 0.0)
			q += _bote * fb * fb * (3.0 - 2.0 * fb)
		_p[i] = q
	for i in _ossos:
		var frente := (_p[maxi(i - 1, 0)] - _p[mini(i + 1, _ossos - 1)]).normalized()
		if frente.length_squared() < 0.5:
			frente = Vector3.FORWARD
		elif absf(frente.y) > 0.999:
			frente = (frente + Vector3(0.002, 0.0, 0.002)).normalized()
		_esq.set_bone_pose(i, Transform3D(Basis.looking_at(frente, Vector3.UP), _p[i]))


## Focinho e rumo da cabeça (vistas de conferência).
func cabeca() -> Array:
	return [_p[0], (_p[0] - _p[2]).normalized()] if _esq else [Vector3.ZERO, Vector3.FORWARD]


## Malha do modelo já no tamanho do jogo e presa aos ossos. A cobra cresce POR IGUAL até `comp` m: a
## grossura sai da proporção do modelo (pedido do dono: grossa demais dobrava nas curvas e esticava as
## escamas). `gross` só vale para a SerpenteCaminho (achatar != 1). Devolve [malha, altura, grossura].
## Vazio se o modelo não está lá.
static func _malha(comp: float, gross: float, n_ossos := OSSOS, achatar := 1.0) -> Array:
	var chave := "%.1f_%.2f_%d_%.2f" % [comp, gross, n_ossos, achatar]
	if _malhas.has(chave):
		return _malhas[chave]
	# Lido direto do .glb (GLTFDocument), sem depender da importação do editor; uma vez só por partida
	if _origem == null:
		var arq := ProjectSettings.globalize_path(MODELO)
		var doc := GLTFDocument.new()
		var estado := GLTFState.new()
		if not FileAccess.file_exists(arq) or doc.append_from_file(arq, estado) != OK:
			return []
		var cena := doc.generate_scene(estado)
		for no in cena.find_children("*", "MeshInstance3D", true, false):
			_origem = (no as MeshInstance3D).mesh
			break
		cena.free()
	var origem := _origem
	if origem == null:
		return []
	var caixa := origem.get_aabb()
	var k := comp / caixa.size.z
	if achatar != 1.0:
		k = gross / LARGURA_CORPO
	var kz := k if achatar == 1.0 else (comp - CABECA * k) / (caixa.size.z - CABECA)
	var malha := ArrayMesh.new()
	for s in origem.get_surface_count():
		var arr := origem.surface_get_arrays(s)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var tem_tan: bool = arr[Mesh.ARRAY_TANGENT] != null
		var tan := PackedFloat32Array(arr[Mesh.ARRAY_TANGENT]) if tem_tan else PackedFloat32Array()
		var uv2 := PackedVector2Array()   # (metros ao longo do corpo, altura 0..1): desenho da pele que não escorrega
		uv2.resize(pos.size())
		var ossos := PackedInt32Array()
		var pesos := PackedFloat32Array()
		ossos.resize(pos.size() * 4)
		pesos.resize(pos.size() * 4)
		for i in pos.size():
			var v := pos[i]
			var na_cabeca := v.z < CABECA
			var z := v.z * k if na_cabeca else CABECA * k + (v.z - CABECA) * kz
			var e := Vector3(k, k * achatar, k if na_cabeca else kz)
			pos[i] = Vector3(v.x * k, v.y * k * achatar, z)
			uv2[i] = Vector2(z, clampf(v.y / caixa.size.y, 0.0, 1.0))
			nor[i] = (nor[i] / e).normalized()
			if tem_tan:
				var tg := (Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2]) * e).normalized()
				tan[i * 4] = tg.x
				tan[i * 4 + 1] = tg.y
				tan[i * 4 + 2] = tg.z
			var f := clampf(z / comp, 0.0, 1.0) * (n_ossos - 1)
			var o := mini(int(f), n_ossos - 2)
			ossos[i * 4] = o
			ossos[i * 4 + 1] = o + 1
			pesos[i * 4] = 1.0 - (f - o)
			pesos[i * 4 + 1] = f - o
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		if tem_tan:
			arr[Mesh.ARRAY_TANGENT] = tan
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_BONES] = ossos
		arr[Mesh.ARRAY_WEIGHTS] = pesos
		malha.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := origem.surface_get_material(s)
		if mat is StandardMaterial3D:
			# Escamas bem marcadas: relevo mais forte e brilho de pele seca (não de plástico molhado)
			mat = (mat as StandardMaterial3D).duplicate()
			mat.normal_scale = 1.8
			mat.roughness = 1.0
			mat.metallic_specular = 0.35
		malha.surface_set_material(s, mat)
	_malhas[chave] = [malha, caixa.size.y * k * achatar, LARGURA_CORPO * k]
	return _malhas[chave]
