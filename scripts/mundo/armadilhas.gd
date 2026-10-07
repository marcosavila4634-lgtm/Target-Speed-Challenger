class_name Armadilhas
extends Node3D
## Armadilhas do templo na estrada do percurso da etapa (Serpent's Climb, mapa.subida.percursos.N.armadilhas).
## Todas têm ritmo fixo (dá para aprender e cronometrar) e avisam antes com luz vermelha:
## - lâminas: pêndulo de obsidiana preso num pórtico de pedra, varrendo a estrada de um lado ao outro;
## - lanças: placa no piso de onde saem lanças de obsidiana, numa faixa de cada vez;
## - serpentes: cabeça de serpente emplumada por cima da estrada — o carro passa pela boca e a mandíbula
##   de cima desce e fecha a estrada inteira;
## - pedras: pedras redondas entalhadas rolando ladeira abaixo (contra quem sobe), numa faixa de cada vez;
## - jatos: bocas de serpente na beirada soltando jatos d'água que empurram o carro para fora.
## Lâmina, lança, mandíbula e pedra são mortais (grupo "mortal"); o jato só empurra. As estruturas paradas
## das armadilhas (pilares, molduras, pórticos) NÃO explodem o carro: são parede comum (ver _corpo_mortal).
## Para os bots: portao_adiante/livre_entre (quando cada faixa fica livre) e pedras_adiante.

const FAIXA := 2.6          # meio de cada faixa (m do eixo)
const MEIA_CARRO := 1.25

var sub: ComplexoSubida
## Frozen Peak: as mesmas armadilhas em versão de gelo e aço (martelo de gelo, pingentes que caem,
## prensa de gelo, bolas de neve, turbinas de vento) e as placas de gelo fino que quebram.
var gelo := false
var _log_placa := OS.get_environment("TSC_PLACA_LOG") != ""
var _placas: Array = []      # zonas de gelo fino: {corpos, xf, meias, estado, t_ev, centro, raio, p0, tan, passo, tempo, volta}
var _terreno: Terreno
var _t := 0.0
var _passo := 0
var _dt_passo := 0.0
var _portoes: Array = []     # {id, tipo, i, s, comp, fase, periodo, ...}
var _zonas_pedra: Array = []
var _jatos: Array = []
var _mat_obsidiana: StandardMaterial3D
var _mat_ouro: StandardMaterial3D
var _mat_jade: StandardMaterial3D


func montar(p_sub: ComplexoSubida, cfg: Dictionary, terreno: Terreno) -> void:
	sub = p_sub
	_terreno = terreno
	_mat_obsidiana = StandardMaterial3D.new()
	_mat_obsidiana.albedo_color = Color(0.05, 0.045, 0.06)
	_mat_obsidiana.metallic = 0.3
	_mat_obsidiana.roughness = 0.12
	_mat_obsidiana.rim_enabled = true
	_mat_obsidiana.rim = 0.4
	_mat_ouro = Selva.material_ouro()
	_mat_jade = Selva.material_jade()
	if gelo:
		_montar_gelo(cfg)
		return
	for item in cfg.get("laminas", []):
		_montar_lamina(item, cfg.get("lamina", {}))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms      armadilhas: laminas" % Time.get_ticks_msec())
	for item in cfg.get("lancas", []):
		_montar_lancas(item, cfg.get("lanca", {}))
	for item in cfg.get("serpentes", []):
		_montar_serpente(item, cfg.get("serpente", {}))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms      armadilhas: lancas e serpentes" % Time.get_ticks_msec())
	for item in cfg.get("pedras", []):
		_montar_pedras(item, cfg.get("pedra", {}))
	for item in cfg.get("placas", []):   # pedaços de pista que desabam depois que o carro passa (o mesmo gelo fino, em pedra)
		_montar_placas(item, cfg.get("placa", {}))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms      armadilhas: pedras e placas" % Time.get_ticks_msec())
	for item in cfg.get("cuspidoras", []):   # cobras cuspindo veneno de buracos na rocha (CobrasCuspidoras)
		var cc := CobrasCuspidoras.new()
		cc.name = "Cuspidoras%d" % get_child_count()
		add_child(cc)
		cc.montar(sub, item, cfg.get("cuspidora", {}))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms      armadilhas: cuspidoras" % Time.get_ticks_msec())
	for item in cfg.get("quedas", []):   # rochas caindo da montanha (RochasCaindo)
		var rq := RochasCaindo.new()
		rq.name = "Quedas%d" % get_child_count()
		add_child(rq)
		rq.montar(sub, _terreno, item, cfg.get("queda", {}))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms      armadilhas: quedas" % Time.get_ticks_msec())
	for item in cfg.get("jatos", []):
		_montar_jato(item, cfg.get("jato", {}))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms      armadilhas: jatos" % Time.get_ticks_msec())
	for item in cfg.get("jaguares", []):   # jaguar na árvore seca que pula no teto do carro (JaguarArvore)
		var ja := JaguarArvore.new()
		ja.name = "Jaguar%d" % get_child_count()
		add_child(ja)
		ja.montar(sub, _terreno, item, cfg.get("jaguar", {}))
	_portoes.sort_custom(func(a, b): return a.s < b.s)
	for k in _portoes.size():
		_portoes[k].id = k
	_atualizar()
	if OS.get_environment("TSC_SUB_LOG") != "":
		for g: Dictionary in _portoes:
			print("[ARMADILHA] %s em s=%.0f %s" % [g.tipo, g.s, str(sub.amostra(g.i).snapped(Vector3.ONE))])


# ------------------------------------------------------------------ comum

## Referencial da estrada na amostra i: x = lateral (direita), y = cima, z = para trás.
func _base(i: int) -> Basis:
	var t := sub.tangente_em(i)
	var th := Vector3(t.x, 0.0, t.z).normalized()
	return Basis(sub.lateral_em(i), Vector3.UP, -th)


## Corpo de colisão de uma armadilha. Pedido do dono (2026-10-04): só a peça que se MEXE explode o carro
## (a que cai, balança, esmaga, morde — `animado`); pilares, molduras e pórticos (corpo parado) são
## parede comum: o carro bate e fica.
func _corpo_mortal(pai: Node, animado := false) -> PhysicsBody3D:
	var corpo: PhysicsBody3D
	if animado:
		var a := AnimatableBody3D.new()
		a.sync_to_physics = true
		corpo = a
	else:
		corpo = StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	if animado:
		corpo.add_to_group("mortal")
	pai.add_child(corpo)
	return corpo


func _forma_caixa(corpo: Node, tam: Vector3, xf := Transform3D.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = tam
	cs.shape = b
	cs.transform = xf
	corpo.add_child(cs)


func _malha(pai: Node, mesh: Mesh, mat: Material, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	pai.add_child(mi)
	return mi


static func _caixa(tam: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = tam
	return b


func _lampada(pai: Node, pos: Vector3, raio := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.1, 0.1)
	m.emission_enabled = true
	m.emission = Color(0.2, 1.0, 0.3)
	m.emission_energy_multiplier = 6.0
	var e := SphereMesh.new()
	e.radius = raio
	e.height = raio * 2.0
	_malha(pai, e, m, Transform3D(Basis.IDENTITY, pos))
	return m


## Laje larga embaixo do pórtico e colunas de pedra até o chão nas duas pontas (nada flutua).
func _apoios(pai: Node3D, i: int, meia_lado: float, prof: float) -> void:
	var c := sub.amostra(i)
	var b := _base(i)
	var pecas: Array[Transform3D] = []
	pecas.append(Transform3D(b * Basis.from_scale(Vector3(meia_lado * 2.0 + 4.0, 1.2, prof + 4.0)), c + Vector3.UP * (-ComplexoSubida.ESPESSURA_ESTRADA - 0.6)))
	var colunas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var pe := c + sub.lateral_em(i) * s * meia_lado
		var chao := _terreno.altura_em(pe.x, pe.z)
		if c.y - chao > 3.0:
			colunas.append(Transform3D(b * Basis.from_scale(Vector3(3.6, c.y - chao, 3.6)), Vector3(pe.x, (c.y + chao) * 0.5 - 1.5, pe.z)))
	ComplexoLancamento.criar_multimesh(pai, pecas, Selva.material_pedra(0, 1.2))
	ComplexoLancamento.criar_multimesh(pai, colunas, Selva.material_pedra(0, 1.4))
	var est := StaticBody3D.new()
	est.collision_layer = 1
	est.collision_mask = 0
	est.add_to_group("estrutura")
	pai.add_child(est)
	ComplexoLancamento.adicionar_colisoes(est, colunas)


## Extensão (0..1) de algo que sai em `mover` s, fica fora até `fora` s e volta, no ciclo `periodo`.
static func _ciclo(f: float, mover: float, fora: float) -> float:
	if f < mover:
		return smoothstep(0.0, mover, f)
	if f < fora:
		return 1.0
	if f < fora + mover:
		return 1.0 - smoothstep(fora, fora + mover, f)
	return 0.0


# ------------------------------------------------------------------ lâminas (pêndulo)

func _montar_lamina(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(item[3]) if item.size() > 3 else float(cfg.get("periodo", 4.0))
	var comp := float(cfg.get("comprimento", 9.5))
	var amp := deg_to_rad(float(cfg.get("amplitude", 62.0)))
	var c := sub.amostra(i)
	var b := _base(i)
	var meia := sub.largura_em(i) * 0.5
	var no := Node3D.new()
	no.name = "Lamina%d" % _portoes.size()
	add_child(no)
	var hp := comp + 0.6   # pivô acima do asfalto
	if item.size() > 4 and str(item[4]) == "rocha":
		# Montanha de rocha com túnel, portais e machados pela arte do dono (MontanhaArmadilha). [trecho, m, fase,
		# período, "rocha", portais extras, passo m, escada s]: os extras ficam antes (passo m cada) e cada machado
		# balança um pouco antes do seguinte (escadinha, pedido do dono; escada < 0: a onda anda no sentido do
		# carro, dá para passar a fila toda numa velocidade só).
		var extras := int(item[5]) if item.size() > 5 else 0
		var passo := float(item[6]) if item.size() > 6 else 14.0
		var escada := float(item[7]) if item.size() > 7 else -0.6
		var idxs: Array = []
		for k in range(extras, -1, -1):
			idxs.append(sub.indice_trecho(str(item[0]), float(item[1]) - k * passo))
		var lista := MontanhaArmadilha.montar(self, no, idxs)
		for k in lista.size():
			var m: Dictionary = lista[k]
			_portoes.append({"tipo": "lamina", "i": m.i, "s": sub.progresso_amostra(m.i), "comp": 1.0, "fase": float(item[2]) + k * escada, "periodo": periodo,
				"amp": minf(amp, float(m.amp)), "l": m.l, "hp": m.hp, "corpo": m.corpo, "pivo": m.pivo, "base": m.base, "lampadas": m.lampadas, "total": false,
				"meia_lam": m.meia_lam})
		if not lista.is_empty():
			return
	if item.size() > 4 and str(item[4]) == "fogo":
		# A mesma montanha com túnel, sem portal nem machado: pares de estátuas que cospem fogo atravessando a
		# pista (MontanhaArmadilha.montar_fogo), na mesma escadinha dos machados. Só o fogo mata.
		var extras_f := int(item[5]) if item.size() > 5 else 0
		var passo_f := float(item[6]) if item.size() > 6 else 14.0
		var escada_f := float(item[7]) if item.size() > 7 else -0.6
		var idxs_f: Array = []
		for k in range(extras_f, -1, -1):
			idxs_f.append(sub.indice_trecho(str(item[0]), float(item[1]) - k * passo_f))
		var lista_f := MontanhaArmadilha.montar_fogo(self, no, idxs_f)
		for k in lista_f.size():
			var m: Dictionary = lista_f[k]
			_portoes.append({"tipo": "fogo", "i": m.i, "s": sub.progresso_amostra(m.i) - 2.5, "comp": 5.0, "fase": float(item[2]) + k * escada_f,
				"periodo": periodo, "ligado": float(cfg.get("fogo_s", 1.3)), "jatos": m.jatos, "luzes": m.luzes, "meia": m.meia,
				"c": sub.amostra(m.i), "tan": sub.tangente_em(m.i), "lat": sub.lateral_em(m.i), "total": true})
		if not lista_f.is_empty():
			return
	_apoios(no, i, meia + 3.2, 4.0)
	# Pórtico: dois pilares com friso entalhado, lintel com ameias e discos de ouro e jade
	var pecas: Array[Transform3D] = []
	var friso: Array[Transform3D] = []
	var lat := sub.lateral_em(i)
	for s: float in [-1.0, 1.0]:
		var x := s * (meia + 2.6)
		pecas.append(Transform3D(b * Basis.from_scale(Vector3(3.4, hp + 1.2, 3.4)), c + lat * x + Vector3.UP * ((hp + 1.2) * 0.5)))
		pecas.append(Transform3D(b * Basis.from_scale(Vector3(4.4, 1.2, 4.4)), c + lat * x + Vector3.UP * 0.6))
		friso.append(Transform3D(b * Basis.from_scale(Vector3(3.6, 2.2, 3.6)), c + lat * x + Vector3.UP * (hp * 0.55)))
	pecas.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + 10.0, 2.4, 3.6)), c + Vector3.UP * (hp + 2.4)))
	friso.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + 10.6, 1.0, 4.0)), c + Vector3.UP * (hp + 3.9)))
	var ameias: Array[Transform3D] = []
	var n_am := 7
	for k in n_am:
		var x := lerpf(-(meia + 4.2), meia + 4.2, float(k) / (n_am - 1))
		ameias.append(Transform3D(b * Basis.from_scale(Vector3(1.4, 1.8, 1.4)), c + lat * x + Vector3.UP * (hp + 5.3)))
	ComplexoLancamento.criar_multimesh(no, pecas, Selva.material_pedra(0, 1.2))
	ComplexoLancamento.criar_multimesh(no, friso, Selva.material_pedra(2, 1.1))
	ComplexoLancamento.criar_multimesh(no, ameias, Selva.material_pedra(1, 0.9))
	var discos: Array[Transform3D] = []
	for face: float in [-1.0, 1.0]:
		var centro := c + Vector3.UP * (hp + 2.4) - b.z * face * 1.85
		discos.append(Transform3D(Basis(lat, b.z * face, Vector3.UP) * Basis.from_scale(Vector3(2.2, 0.3, 2.2)), centro))
	var cil := CylinderMesh.new()
	cil.top_radius = 0.5
	cil.bottom_radius = 0.5
	cil.height = 1.0
	cil.radial_segments = 24
	for d in discos:
		_malha(no, cil, _mat_ouro, d)
	var est := _corpo_mortal(no)
	ComplexoLancamento.adicionar_colisoes(est, pecas)
	var lampadas: Array = []
	for s: float in [-1.0, 1.0]:
		lampadas.append(_lampada(no, c + lat * s * (meia + 2.6) + Vector3.UP * (hp * 0.8) + b.z * 1.85, 0.45))
	# O pêndulo: haste de bronze, contrapeso de jade e a lâmina de obsidiana em meia-lua
	var corpo := _corpo_mortal(no, true)
	var haste := comp - 1.3
	_malha(corpo, _caixa(Vector3(0.75, haste, 0.75)), _mat_ouro, Transform3D(Basis.IDENTITY, Vector3(0, -haste * 0.5, 0)))
	_forma_caixa(corpo, Vector3(0.5, haste, 0.5), Transform3D(Basis.IDENTITY, Vector3(0, -haste * 0.5, 0)))
	var esfera := SphereMesh.new()
	esfera.radius = 0.9
	esfera.height = 1.8
	_malha(corpo, esfera, _mat_jade, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	_malha(corpo, _lamina_mesh(), _mat_obsidiana, Transform3D(Basis.from_scale(Vector3(1.4, 1.4, 1.4)), Vector3(0, -comp, 0)))
	_malha(corpo, _caixa(Vector3(1.6, 0.6, 0.7)), _mat_ouro, Transform3D(Basis.IDENTITY, Vector3(0, -haste - 0.1, 0)))
	_forma_caixa(corpo, Vector3(5.3, 1.8, 0.5), Transform3D(Basis.IDENTITY, Vector3(0, -comp + 0.9, 0)))
	_portoes.append({"tipo": "lamina", "i": i, "s": sub.progresso_amostra(i), "comp": 1.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "amp": amp, "l": comp, "hp": hp, "corpo": corpo, "pivo": c + Vector3.UP * hp, "base": b, "lampadas": lampadas, "total": false})


## Lâmina em meia-lua (3,8 m de corda, 0,4 de espessura), com o gume para baixo. Origem no gume.
static func _lamina_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Gume (embaixo) e dorso (em cima) se encontram nas pontas; o dorso é grosso e o gume fino
	var n := 16
	var gume: Array[Vector3] = []
	var dorso_f: Array[Vector3] = []
	var dorso_t: Array[Vector3] = []
	for k in n + 1:
		var a := lerpf(-1.0, 1.0, float(k) / n)
		var x := a * 1.9
		var y_g := 0.9 * a * a
		var y_d := 0.9 * a * a + 1.3 * (1.0 - a * a)
		var esp := 0.2 * (1.0 - a * a) + 0.02
		gume.append(Vector3(x, y_g, 0.0))
		dorso_f.append(Vector3(x, y_d, esp))
		dorso_t.append(Vector3(x, y_d, -esp))
	for k in n:
		for par: Array in [[dorso_f, 1.0], [dorso_t, -1.0]]:
			var d: Array[Vector3] = par[0]
			var nz: float = par[1]
			var nrm := Vector3(0.0, -0.25, nz).normalized()
			Egito._quad(st, gume[k], gume[k + 1], d[k + 1], d[k], nrm)
		Egito._quad(st, dorso_f[k], dorso_f[k + 1], dorso_t[k + 1], dorso_t[k], Vector3.UP)
	return st.commit()


func _angulo_lamina(g: Dictionary, t: float) -> float:
	return float(g.amp) * sin(TAU * (t + float(g.fase)) / float(g.periodo))


func _perigo_lamina(g: Dictionary, lado: int, t: float) -> bool:
	var th := _angulo_lamina(g, t)
	var l: float = g.l
	var xb := l * sin(th)
	var ml: float = g.get("meia_lam", 2.65)
	var baixo := 0.6 + l * (1.0 - cos(th)) - absf(sin(th)) * ml   # ponta mais baixa da meia-lua inclinada
	if baixo > 2.3:
		return false
	var xl := FAIXA * (1.0 if lado == 1 else -1.0)
	return absf(xb - xl) < ml + MEIA_CARRO + 0.3


# ------------------------------------------------------------------ lanças

func _montar_lancas(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(item[3]) if item.size() > 3 else float(cfg.get("periodo", 5.0))
	var comp := float(cfg.get("comprimento", 12.0))
	var i_meio := sub.indice_adiante(i, comp * 0.5)
	var c := sub.amostra(i_meio)
	var t := sub.tangente_em(i_meio)
	var lat := sub.lateral_em(i_meio)
	var nrm := lat.cross(t).normalized()
	var b := Basis(lat, nrm, -t)
	var meia := sub.largura_em(i_meio) * 0.5
	var no := Node3D.new()
	no.name = "Lancas%d" % _portoes.size()
	add_child(no)
	# Placa de pedra escura no piso com a grade de furos e as faixas de aviso (shader próprio)
	var placa_mat := ShaderMaterial.new()
	placa_mat.shader = load("res://shaders/placa_lancas.gdshader")
	var placa := PlaneMesh.new()
	placa.size = Vector2(meia * 2.0 - 0.3, comp)
	_malha(no, placa, placa_mat, Transform3D(b, c + nrm * 0.03))
	var corpos: Array = []
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.16
	cone.height = 1.7
	cone.radial_segments = 6
	cone.rings = 1
	for lado in 2:
		var s := -1.0 if lado == 0 else 1.0
		var corpo := _corpo_mortal(no, true)
		var largura := meia - 0.5
		_forma_caixa(corpo, Vector3(largura, 1.5, comp - 0.6), Transform3D(Basis.IDENTITY, Vector3(0, 0.75, 0)))
		var pontas: Array[Transform3D] = []
		var nx := int(largura / 0.9)
		var nz := int((comp - 0.8) / 0.9)
		for a in nx:
			for k in nz:
				var x := (a - (nx - 1) * 0.5) * 0.9 + (0.22 if k % 2 == 1 else 0.0)
				var z := (k - (nz - 1) * 0.5) * 0.9
				pontas.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.85, z)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cone
		mm.instance_count = pontas.size()
		for k in pontas.size():
			mm.set_instance_transform(k, pontas[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mat_lanca()
		corpo.add_child(mmi)
		corpos.append([corpo, s * (meia * 0.5 + 0.1)])
	_portoes.append({"tipo": "lanca", "i": i, "s": sub.progresso_amostra(i), "comp": comp, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "mover": float(cfg.get("mover_s", 0.25)), "fora": float(cfg.get("fora_s", 1.6)), "corpos": corpos,
		"centro": c, "base": b, "nrm": nrm, "lat": lat, "placa": placa_mat, "total": false})


## Lança de obsidiana com a ponta de bronze (gradiente na altura do cone, pelo UV).
func _mat_lanca() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nvoid fragment() {\n\tfloat ponta = smoothstep(0.35, 0.05, UV.y);\n\tALBEDO = mix(vec3(0.05, 0.045, 0.06), vec3(0.75, 0.48, 0.2), ponta);\n\tMETALLIC = mix(0.2, 1.0, ponta);\n\tROUGHNESS = mix(0.12, 0.3, ponta);\n\tRIM = 0.4;\n}\n"
	m.shader = sh
	return m


func _extensao_lanca(g: Dictionary, lado: int, t: float) -> float:
	var per: float = g.periodo
	var f := fposmod(t + float(g.fase) + (per * 0.5 if lado == 1 else 0.0), per)
	return _ciclo(f, g.mover, g.fora)


func _perigo_lanca(g: Dictionary, lado: int, t: float) -> bool:
	return _extensao_lanca(g, lado, t) > 0.05


# ------------------------------------------------------------------ boca da serpente

func _montar_serpente(item: Array, cfg: Dictionary) -> void:
	if CabecaPedra.carregar():
		_montar_cabeca_pedra(item, cfg)
		return
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(item[3]) if item.size() > 3 else float(cfg.get("periodo", 6.0))
	var comp := 16.0
	var i_meio := sub.indice_adiante(i, comp * 0.5)
	var c := sub.amostra(i_meio)
	var b := _base(i_meio)
	var lat := sub.lateral_em(i_meio)
	var meia := sub.largura_em(i_meio) * 0.5
	var no := Node3D.new()
	no.name = "Serpente%d" % _portoes.size()
	add_child(no)
	_apoios(no, i_meio, meia + 4.5, comp)
	# Estuque pintado de verde-jade (as cabeças das pirâmides eram pintadas), descascando
	var pele := ShaderMaterial.new()
	pele.shader = load("res://shaders/pedra_selva.gdshader")
	pele.set_shader_parameter("modo", 1)
	pele.set_shader_parameter("fiada", 1.0)
	pele.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 211))
	pele.set_shader_parameter("cor_estuque", Color(0.14, 0.42, 0.3))
	pele.set_shader_parameter("pintura", 0.85)
	pele.set_shader_parameter("musgo", 0.4)
	var escama := ShaderMaterial.new()
	escama.shader = pele.shader
	escama.set_shader_parameter("modo", 2)
	escama.set_shader_parameter("fiada", 0.9)
	escama.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 211))
	escama.set_shader_parameter("cor_pedra", Color(0.3, 0.46, 0.36))
	escama.set_shader_parameter("cor_pedra_b", Color(0.2, 0.34, 0.27))
	escama.set_shader_parameter("cor_estuque", Color(0.6, 0.15, 0.08))
	escama.set_shader_parameter("pintura", 0.7)
	var osso := StandardMaterial3D.new()
	osso.albedo_color = Color(0.93, 0.89, 0.8)
	osso.roughness = 0.4
	var boca := StandardMaterial3D.new()
	boca.albedo_color = Color(0.45, 0.06, 0.05)
	boca.roughness = 0.6
	# Mandíbula de baixo: as duas metades nas beiradas (com dentes) e o queixo embaixo da estrada
	var baixo: Array[Transform3D] = []
	var dentes: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		baixo.append(Transform3D(b * Basis.from_scale(Vector3(3.2, 3.0, comp + 2.0)), c + lat * s * (meia + 1.6) + Vector3.UP * 0.6))
		for k in 6:
			var z := lerpf(comp * 0.45, -comp * 0.35, float(k) / 5.0)
			dentes.append(Transform3D(b, c + lat * s * (meia + 0.6) + Vector3.UP * 2.2 + b.z * z))
	baixo.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + 6.0, 3.0, comp + 4.0)), c + Vector3.UP * (-ComplexoSubida.ESPESSURA_ESTRADA - 2.2)))
	ComplexoLancamento.criar_multimesh(no, baixo, escama)
	var dente := CylinderMesh.new()
	dente.top_radius = 0.0
	dente.bottom_radius = 0.4
	dente.height = 1.8
	dente.radial_segments = 8
	var mm_d := MultiMesh.new()
	mm_d.transform_format = MultiMesh.TRANSFORM_3D
	mm_d.mesh = dente
	mm_d.instance_count = dentes.size()
	for k in dentes.size():
		mm_d.set_instance_transform(k, dentes[k])
	var mmi_d := MultiMeshInstance3D.new()
	mmi_d.multimesh = mm_d
	mmi_d.material_override = osso
	no.add_child(mmi_d)
	var est := _corpo_mortal(no)
	ComplexoLancamento.adicionar_colisoes(est, baixo.slice(0, 2))
	# Cabeça (parte de cima): corpo animado. Origem no céu da boca; +z = focinho (lado de quem chega)
	var corpo := _corpo_mortal(no, true)
	var largura := meia * 2.0 + 7.0
	var meio_z := comp * 0.5
	# Maxilar: prisma que afina e baixa do crânio até a ponta do focinho (céu da boca vermelho)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tras_w := largura * 0.5
	var frente_w := largura * 0.36
	var cantos_t := [Vector3(-tras_w, 0.0, -meio_z), Vector3(tras_w, 0.0, -meio_z), Vector3(tras_w, 5.2, -meio_z), Vector3(-tras_w, 5.2, -meio_z)]
	var cantos_f := [Vector3(-frente_w, 0.0, meio_z + 2.5), Vector3(frente_w, 0.0, meio_z + 2.5), Vector3(frente_w * 0.8, 2.6, meio_z + 3.4), Vector3(-frente_w * 0.8, 2.6, meio_z + 3.4)]
	for k in 4:
		var a: Vector3 = cantos_t[k]
		var bb: Vector3 = cantos_t[(k + 1) % 4]
		var cc: Vector3 = cantos_f[(k + 1) % 4]
		var d: Vector3 = cantos_f[k]
		var n := (bb - a).cross(d - a).normalized()
		var centro_q := (a + bb + cc + d) * 0.25
		if n.dot(centro_q - Vector3(0, 2.0, 0)) < 0.0:
			n = -n
		Egito._quad(st, a, bb, cc, d, n)
	Egito._quad(st, cantos_f[0], cantos_f[1], cantos_f[2], cantos_f[3], Vector3(0, 0.3, 1).normalized())
	_malha(corpo, st.commit(), pele, Transform3D.IDENTITY)
	_malha(corpo, _caixa(Vector3(largura * 0.8, 0.1, comp + 2.0)), boca, Transform3D(Basis.IDENTITY, Vector3(0, -0.04, 0.8)))
	# Crânio arredondado atrás, com as escamas
	var cranio := SphereMesh.new()
	cranio.radius = 1.0
	cranio.height = 2.0
	cranio.radial_segments = 24
	cranio.rings = 12
	_malha(corpo, cranio, escama, Transform3D(Basis.from_scale(Vector3(tras_w * 0.98, 4.6, comp * 0.42)), Vector3(0, 4.8, -meio_z * 0.45)))
	# Sobrancelhas, olhos grandes (acendem vermelho antes de fechar) e volutas de ouro no nariz
	var olhos: Array = []
	for s: float in [-1.0, 1.0]:
		var m := _lampada(corpo, Vector3(s * (largura * 0.33), 5.4, meio_z * 0.35), 1.35)
		olhos.append(m)
		_malha(corpo, _caixa(Vector3(4.0, 1.1, 3.6)), _mat_jade, Transform3D(Basis(Vector3.FORWARD, -s * 0.3), Vector3(s * (largura * 0.33), 6.9, meio_z * 0.35)))
		var voluta := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 0.45
		tor.outer_radius = 1.1
		voluta.mesh = tor
		voluta.material_override = _mat_ouro
		voluta.transform = Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(s * frente_w * 0.45, 3.1, meio_z + 2.4))
		corpo.add_child(voluta)
	# Presas: duas grandes curvas na frente e dentes ao longo da boca
	var presas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		presas.append(Transform3D(Basis(Vector3.RIGHT, PI - 0.25) * Basis.from_scale(Vector3(1.4, 2.4, 1.4)), Vector3(s * frente_w * 0.7, -2.0, meio_z + 1.4)))
		for k in 6:
			presas.append(Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.8, 0.7, 0.8)), Vector3(s * (lerpf(frente_w, tras_w, float(k) / 6.0) - 0.9), -0.6, lerpf(meio_z, -meio_z * 0.7, float(k) / 5.0))))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dente
	mm.instance_count = presas.size()
	for k in presas.size():
		mm.set_instance_transform(k, presas[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = osso
	corpo.add_child(mmi)
	# Penacho de quetzal: duas fileiras de plumas longas em leque atrás do crânio (verde, turquesa
	# e pontas de ouro), mais curtas e vermelhas na frente
	var pluma := CylinderMesh.new()
	pluma.top_radius = 0.08
	pluma.bottom_radius = 0.55
	pluma.height = 1.0
	pluma.radial_segments = 6
	pluma.rings = 1
	var verde := StandardMaterial3D.new()
	verde.albedo_color = Color(0.04, 0.45, 0.26)
	verde.metallic = 0.35
	verde.roughness = 0.3
	verde.rim_enabled = true
	var turquesa := StandardMaterial3D.new()
	turquesa.albedo_color = Color(0.05, 0.5, 0.55)
	turquesa.metallic = 0.35
	turquesa.roughness = 0.3
	var vermelha := StandardMaterial3D.new()
	vermelha.albedo_color = Color(0.7, 0.08, 0.06)
	vermelha.roughness = 0.5
	for fileira in 2:
		var n_p := 17 if fileira == 0 else 13
		var compr := 11.0 if fileira == 0 else 6.5
		var listas := [[], [], []]
		for k in n_p:
			var a := lerpf(-1.35, 1.35, float(k) / (n_p - 1))
			var dir := Vector3(sin(a) * 1.15, cos(a), -0.45 if fileira == 0 else -0.15).normalized()
			var raiz := Vector3(sin(a) * tras_w * 0.85, 5.0 + cos(a) * 3.0, -meio_z * (0.75 if fileira == 0 else 0.55))
			var y := dir
			var x := y.cross(Vector3.FORWARD).normalized()
			if x.length() < 0.1:
				x = Vector3.RIGHT
			var z := x.cross(y)
			var xf := Transform3D(Basis(x * 1.0, y * compr, z * 0.35), raiz + dir * compr * 0.5)
			var cor := k % 3 if fileira == 0 else 2
			listas[cor].append(xf)
		for cor in 3:
			if listas[cor].is_empty():
				continue
			var mm_p := MultiMesh.new()
			mm_p.transform_format = MultiMesh.TRANSFORM_3D
			mm_p.mesh = pluma
			mm_p.instance_count = listas[cor].size()
			for k in listas[cor].size():
				mm_p.set_instance_transform(k, listas[cor][k])
			var mmi_p := MultiMeshInstance3D.new()
			mmi_p.multimesh = mm_p
			mmi_p.material_override = [verde, turquesa, vermelha][cor]
			corpo.add_child(mmi_p)
	# Colisão (mortal): o maxilar inteiro e o crânio
	_forma_caixa(corpo, Vector3(largura * 0.9, 3.0, comp + 3.0), Transform3D(Basis.IDENTITY, Vector3(0, 1.5, 0.8)))
	_forma_caixa(corpo, Vector3(largura * 0.95, 5.0, comp * 0.8), Transform3D(Basis.IDENTITY, Vector3(0, 4.5, -meio_z * 0.45)))
	_portoes.append({"tipo": "serpente", "i": i, "s": sub.progresso_amostra(i), "comp": comp, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "fecha": float(cfg.get("fecha_s", 0.35)), "fechada": float(cfg.get("fechada_s", 1.4)), "abre": float(cfg.get("abre_s", 1.0)),
		"corpo": corpo, "centro": c, "base": b, "olhos": olhos, "total": true})


## Cabeça de pedra da arte do dono (CabecaPedra): a boca começa na amostra i e o túnel segue a estrada. A
## cabeça é reta: o eixo vai da frente até o fim do corredor e ela cresce (escala k) até a estrada inteira,
## com a curva, caber entre os meios-fios; se a estrada afunda no meio, a cabeça desce junto.
func _montar_cabeca_pedra(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(item[3]) if item.size() > 3 else float(cfg.get("periodo", 6.0))
	var med := CabecaPedra.medidas()   # [meia do túnel, meia do meio-fio, comprimento, comprimento do teto, céu]
	var k := maxf(1.0, (sub.largura_em(i) * 0.5 + 0.3) / float(med[1]))
	var p0 := sub.amostra(i)
	var x := Vector3.RIGHT
	var y := Vector3.UP
	var z := Vector3.BACK
	var i_fim := i
	var abaixo := 0.0
	for passada in 3:
		i_fim = sub.indice_adiante(i, float(med[2]) * k)
		z = (p0 - sub.amostra(i_fim)).normalized()   # para quem chega
		var lat := sub.lateral_em(i)
		x = (lat - z * lat.dot(z)).normalized()
		y = z.cross(x).normalized()
		var desvio := 0.0
		abaixo = 0.0
		for j in range(i, i_fim + 1):
			var d := sub.amostra(j) - p0
			desvio = maxf(desvio, absf(d.dot(x)) + sub.largura_em(j) * 0.5)
			abaixo = maxf(abaixo, -d.dot(y))
		k = maxf(k, (desvio + 0.3) / float(med[1]))
	var origem := p0 - y * maxf(abaixo - 0.25, 0.0)
	var chao := INF
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [0.0, -0.5, -1.0]:
			var q := origem + x * sx * 16.0 * k + z * sz * float(med[2]) * k
			chao = minf(chao, _terreno.altura_em(q.x, q.z))
	var no := Node3D.new()
	no.name = "Serpente%d" % _portoes.size()
	add_child(no)
	var cab := CabecaPedra.new()
	no.add_child(cab)
	cab.montar(Transform3D(Basis(x, y, z), origem), k, chao)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[CABECA] em %s, frente %s, escala %.2f, desce %.1f m, chão %.0f m abaixo" % [str(origem.snapped(Vector3.ONE)), str(z.snapped(Vector3.ONE * 0.01)), k, maxf(abaixo - 0.25, 0.0), origem.y - chao])
	_portoes.append({"tipo": "serpente", "i": i, "s": sub.progresso_amostra(i), "comp": 12.0 * k, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "fecha": float(cfg.get("fecha_s", 0.35)), "fechada": float(cfg.get("fechada_s", 1.4)), "abre": float(cfg.get("abre_s", 1.0)),
		"cabeca": cab, "aberta_h": cab.aberta, "olhos": cab.olhos, "total": true})


## Altura (m acima do asfalto) do céu da boca da serpente no instante t: 0,25 fechada, aberta_h (11) aberta.
func _boca(g: Dictionary, t: float) -> float:
	var f := fposmod(t + float(g.fase), float(g.periodo))
	var fecha: float = g.fecha
	var fechada: float = g.fechada
	var abre: float = g.abre
	var aberta := 1.0
	if f < fecha:
		aberta = 1.0 - f / fecha * f / fecha   # despenca acelerando
	elif f < fecha + fechada:
		aberta = 0.0
	elif f < fecha + fechada + abre:
		aberta = smoothstep(fecha + fechada, fecha + fechada + abre, f)
	return lerpf(0.25, float(g.get("aberta_h", 11.0)), aberta)


func _perigo_serpente(g: Dictionary, _lado: int, t: float) -> bool:
	return _boca(g, t) < 2.6


# ------------------------------------------------------------------ pedras rolando

func _montar_pedras(item: Array, cfg: Dictionary) -> void:
	var i0 := sub.indice_trecho(str(item[0]), float(item[1]))
	var i1 := sub.indice_trecho(str(item[0]), float(item[2]))
	var fase := float(item[3]) if item.size() > 3 else 0.0
	var periodo := float(item[4]) if item.size() > 4 else float(cfg.get("periodo", 9.0))
	var raio := float(cfg.get("raio", 2.0))
	var vel := float(cfg.get("velocidade", 13.0))
	var padrao := str(cfg.get("padrao", "alterna"))
	var no := Node3D.new()
	no.name = "Pedras%d" % _zonas_pedra.size()
	add_child(no)
	# Portal de onde as pedras saem (no alto da ladeira): pilares, lintel e cabeça de jaguar
	var c := sub.amostra(i1)
	var b := _base(i1)
	var lat := sub.lateral_em(i1)
	var meia := sub.largura_em(i1) * 0.5
	var pecas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		pecas.append(Transform3D(b * Basis.from_scale(Vector3(3.0, 9.0, 4.0)), c + lat * s * (meia + 1.8) + Vector3.UP * 4.5))
	pecas.append(Transform3D(b * Basis.from_scale(Vector3(meia * 2.0 + 7.0, 2.6, 4.6)), c + Vector3.UP * 10.2))
	_apoios(no, i1, meia + 1.8, 4.0)
	ComplexoLancamento.criar_multimesh(no, pecas, Selva.material_pedra(2, 1.3))
	var est := _corpo_mortal(no)
	ComplexoLancamento.adicionar_colisoes(est, pecas)
	var jag := Selva.cabeca_jaguar(5.0)
	jag.transform = Transform3D(b.rotated(Vector3.UP, PI), c + Vector3.UP * 11.45 - b.z * 0.4)
	no.add_child(jag)
	var lampadas: Array = []
	for s: float in [-1.0, 1.0]:
		lampadas.append(_lampada(no, c + lat * s * (meia + 1.8) + Vector3.UP * 7.6 + b.z * 2.1, 0.45))
	# Pedras (um corpo por pedra que pode estar na ladeira ao mesmo tempo)
	var comp := sub.progresso_amostra(i1) - sub.progresso_amostra(i0)
	var qtd := int(ceil(comp / vel / periodo)) + 2
	var malha := SphereMesh.new()
	malha.radius = raio
	malha.height = raio * 2.0
	malha.radial_segments = 24
	malha.rings = 12
	var mat := Selva.material_pedra(3, 1.0)
	var pedras: Array = []
	for k in qtd:
		var corpo := _corpo_mortal(no, true)
		var mi := MeshInstance3D.new()
		mi.mesh = malha
		mi.material_override = mat
		corpo.add_child(mi)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = raio * 0.95
		cs.shape = sp
		corpo.add_child(cs)
		corpo.visible = false
		pedras.append(corpo)
	_zonas_pedra.append({"i0": i0, "i1": i1, "s0": sub.progresso_amostra(i0), "s1": sub.progresso_amostra(i1), "fase": fase, "periodo": periodo,
		"vel": vel, "raio": raio, "padrao": padrao, "pedras": pedras, "lampadas": lampadas})


## Faixa (0 esquerda, 1 direita) da pedra número n da zona.
func _faixa_pedra(z: Dictionary, n: int) -> int:
	if z.padrao == "sorteio":
		return int(Terreno._hash2(n, 77) * 2.0) % 2
	return n % 2


## Pedras de uma zona no instante t: [[n, s (progresso), faixa, caindo (s além do pé da ladeira)]].
func _pedras_em(z: Dictionary, t: float) -> Array:
	var lista := []
	var per: float = z.periodo
	var dur: float = (float(z.s1) - float(z.s0)) / float(z.vel)
	var tz := t + float(z.fase)
	var n_ult := floori(tz / per)
	for n in range(n_ult, n_ult - z.pedras.size(), -1):
		var idade := tz - n * per
		if idade < 0.0 or idade > dur + 3.0:
			continue
		if gelo and idade > dur:
			continue   # bola de neve: se desfaz no pé da ladeira (não sai rolando pela beirada em cima de quem vem)
		# Sai do portal devagar e embala nos primeiros 2 s
		var dist := float(z.vel) * maxf(idade - 1.0, 0.0) + float(z.vel) * minf(idade, 1.0) * minf(idade, 1.0) * 0.5
		lista.append([n, float(z.s1) - dist, _faixa_pedra(z, n), idade > dur])
	return lista


# ------------------------------------------------------------------ jatos d'água

func _montar_jato(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var lado := float(item[2])                       # de que lado fica a boca (+1 = direita)
	var fase := float(item[3]) if item.size() > 3 else 0.0
	var periodo := float(item[4]) if item.size() > 4 else float(cfg.get("periodo", 5.0))
	# As três bocas da arte cobrem ~17 m de pista (MuroSerpentes.ALCANCE)
	var comp := maxf(float(cfg.get("comprimento", 14.0)), MuroSerpentes.ALCANCE)
	var i_meio := sub.indice_adiante(i, comp * 0.5)
	var c := sub.amostra(i_meio)
	var b := _base(i_meio)
	var lat := sub.lateral_em(i_meio)
	var meia := sub.largura_em(i_meio) * 0.5
	var no := Node3D.new()
	no.name = "Jato%d" % _portoes.size()
	add_child(no)
	_apoios(no, i_meio, meia + 2.4, comp)
	var est := StaticBody3D.new()
	est.collision_layer = 1
	est.collision_mask = 0
	est.add_to_group("estrutura")
	no.add_child(est)
	# Muro das três cabeças de serpente (a arte do dono em relevo, MuroSerpentes) com a boca virada para a pista
	var muro := _muro_serpentes(no, est, i_meio, lado)
	var particulas: Array = []
	for boca: Vector3 in muro.bocas:
		var p := _particulas_jato(muro.frente + Vector3.DOWN * 0.18, meia * 2.0 + 4.0)
		p.position = boca
		no.add_child(p)
		particulas.append(p)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	_forma_caixa(area, Vector3(meia * 2.0, 4.0, comp))
	area.transform = Transform3D(b, c + Vector3.UP * 2.0)
	no.add_child(area)
	_jatos.append({"area": area, "dir": -lat * lado, "forca": float(cfg.get("forca", 16.0))})
	_portoes.append({"tipo": "jato", "i": i, "s": sub.progresso_amostra(i), "comp": comp, "fase": fase, "periodo": periodo,
		"ligado": float(cfg.get("ligado_s", 1.8)), "jato": _jatos.size() - 1, "particulas": particulas, "total": true})


## Muro das cabeças ao lado da amostra i_meio, do lado `lado`. A estrada pode fazer curva: o muro (reto, 22 m)
## recua até nenhum ponto da beira da pista ficar a menos de FOLGA_PISTA do focinho (perto das cabeças) ou da
## face (nas pontas). Fundação até o chão mais baixo embaixo dele; calçada da face até a beira da pista.
func _muro_serpentes(no: Node3D, est: StaticBody3D, i_meio: int, lado: float) -> MuroSerpentes:
	var c := sub.amostra(i_meio)
	var lat := sub.lateral_em(i_meio)
	var meia := sub.largura_em(i_meio) * 0.5
	var med := MuroSerpentes.medidas()
	var comp: float = med[0]
	var esp: float = med[1]
	var focinho: float = med[2]
	var z := Vector3(-lat.x * lado, 0.0, -lat.z * lado).normalized()   # para a pista
	var x := Vector3.UP.cross(z).normalized()
	var origem := c - z * (meia + MuroSerpentes.FOLGA_PISTA + focinho + esp * 0.5)
	# Recuo pela curva: a beira da pista em coordenadas do muro
	var recuo := 0.0
	for j in range(maxi(i_meio - 40, 0), mini(i_meio + 41, sub.total_amostras())):
		if sub.trecho_de(j) != sub.trecho_de(i_meio):
			continue
		var beira := sub.amostra(j) - z * sub.largura_em(j) * 0.5
		var d := beira - origem
		var ax := absf(d.dot(x))
		if ax > comp * 0.5 + 1.0:
			continue
		var precisa := esp * 0.5 + MuroSerpentes.FOLGA_PISTA + (focinho if ax < comp * 0.4 else 0.0)
		recuo = maxf(recuo, precisa - d.dot(z))
	origem -= z * recuo
	var chao := INF
	for sx: float in [-0.5, 0.0, 0.5]:
		for sz: float in [-0.5, 0.5]:
			var q := origem + x * comp * sx + z * esp * sz
			chao = minf(chao, _terreno.altura_em(q.x, q.z))
	var muro := MuroSerpentes.new()
	no.add_child(muro)
	muro.montar(Transform3D(Basis(x, Vector3.UP, z), origem), chao, focinho + MuroSerpentes.FOLGA_PISTA + recuo, est)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[JATO] muro em %s, frente %s, recuo %.1f m, fundação %.0f m" % [str(origem.snapped(Vector3.ONE)), str(z.snapped(Vector3.ONE * 0.01)), recuo, origem.y - chao])
	return muro


func _particulas_jato(dir: Vector3, alcance: float) -> GPUParticles3D:
	var part := GPUParticles3D.new()
	part.amount = 320
	part.lifetime = 0.9
	part.local_coords = false
	part.emitting = false
	part.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var proc := ParticleProcessMaterial.new()
	proc.direction = dir + Vector3.UP * 0.12
	proc.spread = 4.0
	proc.initial_velocity_min = alcance * 1.6
	proc.initial_velocity_max = alcance * 1.9
	proc.gravity = Vector3(0, -14, 0)
	proc.scale_min = 0.8
	proc.scale_max = 2.2
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 0.5))
	curva.add_point(Vector2(1.0, 1.6))
	var tc := CurveTexture.new()
	tc.curve = curva
	proc.scale_curve = tc
	part.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(1.1, 1.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.6)
	mat.albedo_texture = Selva._textura_nuvem()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	quad.material = mat
	part.draw_pass_1 = quad
	return part


func _jato_ligado(g: Dictionary, t: float) -> bool:
	return fposmod(t + float(g.fase), float(g.periodo)) < float(g.ligado)


func _perigo_jato(g: Dictionary, _lado: int, t: float) -> bool:
	return _jato_ligado(g, t)


# ------------------------------------------------------------------ animação

func _physics_process(delta: float) -> void:
	# As armadilhas andam a cada 2 passos de física (60 vezes por segundo, como o cérebro dos bots): a 120
	# eram o 2º script mais caro do jogo (~3 ms por quadro) sem diferença visível
	_dt_passo += delta
	_passo += 1
	if _passo % 2 != 0:
		return
	delta = _dt_passo
	_dt_passo = 0.0
	_t += delta
	_atualizar()
	_atualizar_placas()
	for g: Dictionary in _portoes:
		if g.tipo != "jato" or not _jato_ligado(g, _t):
			continue
		var j: Dictionary = _jatos[g.jato]
		for corpo in (j.area as Area3D).get_overlapping_bodies():
			var v := corpo as Veiculo
			if v and not v.fantasma():
				v.apply_central_impulse(j.dir * float(j.forca) * v.mass * delta)


func _atualizar() -> void:
	for g: Dictionary in _portoes:
		match g.tipo:
			"lamina":
				var th := _angulo_lamina(g, _t)
				(g.corpo as AnimatableBody3D).global_transform = Transform3D(g.base * Basis(Vector3.BACK, th), g.pivo)
				_avisos(g, g.lampadas)
			"lanca":
				var aviso := false
				for lado in 2:
					var e := _extensao_lanca(g, lado, _t)
					var par: Array = g.corpos[lado]
					var y := lerpf(float(g.get("y_rec", -1.65)), 0.0, e)
					(par[0] as AnimatableBody3D).global_transform = Transform3D(g.base, g.centro + g.lat * float(par[1]) + g.nrm * y)
					aviso = aviso or _extensao_lanca(g, lado, _t + 0.8) > 0.0
					if g.has("estalactites"):
						_animar_estalactites(g, lado, e)
				if g.placa == null:
					continue
				var mat: ShaderMaterial = g.placa
				mat.set_shader_parameter("aviso_esq", 1.0 if _extensao_lanca(g, 0, _t + 0.8) > 0.0 or _extensao_lanca(g, 0, _t) > 0.0 else 0.0)
				mat.set_shader_parameter("aviso_dir", 1.0 if _extensao_lanca(g, 1, _t + 0.8) > 0.0 or _extensao_lanca(g, 1, _t) > 0.0 else 0.0)
			"serpente":
				var h := _boca(g, _t)
				if g.has("cabeca"):
					(g.cabeca as CabecaPedra).animar(h)
				else:
					var giro := clampf((h - 0.25) / 10.75, 0.0, 1.0) * float(g.get("giro", 0.22))
					var b: Basis = g.base
					# A cabeça desce inteira e levanta o focinho quando abre
					(g.corpo as AnimatableBody3D).global_transform = Transform3D(b * Basis(Vector3.RIGHT, -giro), g.centro + Vector3.UP * h)
				var perigo := _boca(g, _t + 1.0) < 2.6 or h < float(g.get("aberta_h", 11.0)) - 0.1
				for m: StandardMaterial3D in g.olhos:
					m.emission = Color(1.0, 0.08, 0.04) if perigo else Color(0.25, 1.0, 0.35)
				if g.has("esmagador"):
					_animar_esmagador(g, h, perigo)
			"fogo":
				_animar_fogo(g)
			"jato":
				var lig := _jato_ligado(g, _t)
				for p: GPUParticles3D in g.particulas:
					if p.emitting != lig:
						p.emitting = lig
				# Turbinas (Frozen Peak): as hélices embalam um pouco antes do sopro e vão parando
				if g.has("helices"):
					var dt_h := get_physics_process_delta_time()
					g.rot = move_toward(float(g.rot), 30.0 if lig or _jato_ligado(g, _t + 0.9) else 2.0, dt_h * 30.0)
					for hl: Node3D in g.helices:
						hl.rotate_object_local(Vector3.FORWARD, float(g.rot) * dt_h)
			"foca":
				_animar_focas(g)
			"yeti":
				_animar_yetis(g)
			"yeti_neve":
				_animar_yetis_plataforma(g)
	for z: Dictionary in _zonas_pedra:
		if z.has("estouro"):
			# Bola de neve que acabou de chegar ao pé da ladeira: estoura numa nuvem de neve
			var dur_z: float = (float(z.s1) - float(z.s0)) / float(z.vel) - 0.5
			var n_fim := floori((_t + float(z.fase) - dur_z) / float(z.periodo))
			if n_fim != int(z.n_estouro):
				if int(z.n_estouro) > -1000000:
					var lado_e := 1.0 if _faixa_pedra(z, n_fim) == 1 else -1.0
					var pe: GPUParticles3D = z.estouro
					pe.global_position = sub.amostra(z.i0) + sub.lateral_em(z.i0) * lado_e * FAIXA + sub.normal_em(z.i0) * float(z.raio)
					pe.restart()
				z.n_estouro = n_fim
		var ativos := _pedras_em(z, _t)
		var usados := {}
		for a: Array in ativos:
			var k: int = posmod(int(a[0]), z.pedras.size())
			usados[k] = true
			var corpo: AnimatableBody3D = z.pedras[k]
			var s: float = a[1]
			var lado := 1.0 if int(a[2]) == 1 else -1.0
			var i := _indice_s(z, s)
			# Bola de neve: cai do portal pequena e cresce; em cima da grelha quente do pé da ladeira, derrete
			var esc := 1.0
			var queda := 0.0
			if z.has("estouro"):
				var nasce := clampf((float(z.s1) - s) / (float(z.vel) * 0.5), 0.0, 1.0)   # 0 no portal, 1 depois do 1º segundo
				esc = lerpf(0.5, 1.0, nasce) * lerpf(0.22, 1.0, clampf((s - float(z.s0)) / GRELHA_COMP, 0.0, 1.0))
				queda = (1.0 - nasce) * (1.0 - nasce) * 5.5
				var malha_b: Node3D = corpo.get_meta("malha")
				malha_b.scale = Vector3.ONE * esc
			var p := sub.amostra(i) + sub.lateral_em(i) * lado * FAIXA + sub.normal_em(i) * (float(z.raio) * esc + queda)
			var giro := -s / float(z.raio)
			var b := Basis(sub.lateral_em(i), giro)
			if a[3]:
				# Passou do pé da ladeira: sai pela beirada e cai
				var tq := (float(z.s0) - s) / float(z.vel)
				p = sub.amostra(z.i0) + sub.lateral_em(z.i0) * lado * (FAIXA + float(z.vel) * 0.6 * tq) - sub.tangente_em(z.i0) * float(z.vel) * tq
				p += sub.normal_em(z.i0) * float(z.raio) + Vector3.DOWN * 4.9 * tq * tq
			if not corpo.visible:
				corpo.visible = true
				corpo.global_transform = Transform3D(b, p)
				corpo.reset_physics_interpolation()
			else:
				corpo.global_transform = Transform3D(b, p)
		for k in z.pedras.size():
			if not usados.has(k):
				var corpo: AnimatableBody3D = z.pedras[k]
				if corpo.visible:
					corpo.visible = false
					corpo.global_position = Vector3(0, -500 - k * 10, 0)
		var aviso := false
		for a: Array in _pedras_em(z, _t + 1.2):
			if float(a[1]) > float(z.s1) - 2.0:
				aviso = true
		for m: StandardMaterial3D in z.lampadas:
			m.emission = Color(1.0, 0.08, 0.04) if aviso else Color(0.25, 1.0, 0.35)


func _indice_s(z: Dictionary, s: float) -> int:
	var a: int = z.i0
	var b: int = z.i1
	s = clampf(s, float(z.s0), float(z.s1))
	while b - a > 1:
		var m := (a + b) / 2
		if sub.progresso_amostra(m) < s:
			a = m
		else:
			b = m
	return b


## Lâmpadas do pórtico da lâmina: vermelha do lado que a lâmina vai varrer no próximo segundo.
func _avisos(g: Dictionary, lampadas: Array) -> void:
	for lado in 2:
		var perigo := false
		var t := 0.0
		while t <= 1.0 and not perigo:
			perigo = _perigo(g, lado, _t + t)
			t += 0.1
		(lampadas[lado] as StandardMaterial3D).emission = Color(1.0, 0.08, 0.04) if perigo else Color(0.25, 1.0, 0.35)


# ------------------------------------------------------------------ consultas dos bots

func _perigo(g: Dictionary, lado: int, t: float) -> bool:
	match g.tipo:
		"lamina": return _perigo_lamina(g, lado, t)
		"lanca": return _perigo_lanca(g, lado, t)
		"serpente": return _perigo_serpente(g, lado, t)
		"jato": return _perigo_jato(g, lado, t)
		"fogo": return _jato_ligado(g, t)   # o fogo dos dois lados fecha a pista toda
		"placas": return _perigo_placas(g, t)
		"foca": return _perigo_foca(g, lado, t)
	return false


## A próxima armadilha de tempo (lâmina, lança, serpente, jato) até `alcance` m à frente, no mesmo
## trecho: {id, tipo, falta (m até a entrada), comp (m da passagem), total (fecha as duas faixas)}.
func portao_adiante(i: int, alcance := 150.0) -> Dictionary:
	var s := sub.progresso_amostra(i)
	var k := sub.trecho_de(i)
	for g: Dictionary in _portoes:
		var falta: float = float(g.s) - s
		if falta + float(g.comp) < -3.0 or sub.trecho_de(g.i) != k or g.tipo == "yeti" or g.tipo == "yeti_neve":   # yeti não tem hora para desviar
			continue
		if falta > alcance:
			return {}
		# Fila (montanha com vários portais): os seguintes a menos de 25 m um do outro, [id, metros depois deste]
		var fila: Array = []
		var ult: Dictionary = g
		for g2: Dictionary in _portoes:
			if float(g2.s) <= float(ult.s) or g2.tipo != g.tipo or sub.trecho_de(g2.i) != k:
				continue
			if float(g2.s) - float(ult.s) > 25.0:
				break
			fila.append([g2.id, float(g2.s) - float(g.s)])
			ult = g2
		# Velocidade da onda de machados da fila (m por s de atraso entre um e o seguinte): o bot anda nela
		var onda := 0.0
		if not fila.is_empty():
			var g2: Dictionary = _portoes[int(fila[0][0])]
			var df := absf(float(g2.fase) - float(g.fase))
			onda = float(fila[0][1]) / df if df > 0.05 else 0.0
		# Já dentro da fila (passou o portal anterior, a menos de 25 m): segue na onda, sem parar embaixo dos machados
		var na_fila := false
		for g0: Dictionary in _portoes:
			if g0.tipo == g.tipo and sub.trecho_de(g0.i) == k and float(g0.s) < float(g.s) and float(g.s) - float(g0.s) <= 25.0 and float(g0.s) <= s + 1.0:
				na_fila = true
				var df0 := absf(float(g.fase) - float(g0.fase))
				if onda <= 0.0 and df0 > 0.05:
					onda = (float(g.s) - float(g0.s)) / df0
		return {"id": g.id, "tipo": g.tipo, "falta": falta, "comp": g.comp, "total": g.total, "fila": fila, "onda": onda, "na_fila": na_fila}
	return {}


## A faixa `lado` (0 = esquerda, 1 = direita) da armadilha `id` fica livre de agora+t0 até agora+t1?
func livre_entre(id: int, lado: int, t0: float, t1: float) -> bool:
	if id < 0 or id >= _portoes.size():
		return true
	var g: Dictionary = _portoes[id]
	var t := t0
	while t <= t1:
		if _perigo(g, lado, _t + t):
			return false
		t += 0.05
	return true


## Pedras rolando na estrada à frente (até `alcance` m): [[metros até ela, faixa 0/1], ...].
func pedras_adiante(i: int, alcance := 200.0) -> Array:
	var lista := []
	var s := sub.progresso_amostra(i)
	var k := sub.trecho_de(i)
	for z: Dictionary in _zonas_pedra:
		if sub.trecho_de(z.i0) != k or s > float(z.s1) + 5.0 or s + alcance < float(z.s0):
			continue
		for a: Array in _pedras_em(z, _t):
			if a[3]:
				continue
			var d: float = float(a[1]) - s
			if d > -6.0 and d < alcance:
				lista.append([d, int(a[2])])
	return lista


## Para as câmeras de conferência: [[ponto, lateral, tangente], ...] de cada armadilha na ordem do percurso.
func posicoes() -> Array:
	var lista := []
	var todas := []
	for g: Dictionary in _portoes:
		todas.append([float(g.s), int(g.i)])
	for z: Dictionary in _zonas_pedra:
		todas.append([float(z.s1) - 60.0, sub.indice_adiante(int(z.i0), float(z.s1) - float(z.s0) - 60.0)])
	todas.sort_custom(func(a, b): return a[0] < b[0])
	for t: Array in todas:
		var i: int = t[1]
		lista.append([sub.amostra(i), sub.lateral_em(i), sub.tangente_em(i)])
	return lista


## A amostra i está numa ladeira de pedras (ou logo antes dela)?
func em_ladeira(i: int, antes := 80.0) -> bool:
	var s := sub.progresso_amostra(i)
	var k := sub.trecho_de(i)
	for z: Dictionary in _zonas_pedra:
		if sub.trecho_de(z.i0) == k and s > float(z.s0) - antes and s < float(z.s1):
			return true
	return false


# ====================================================================== Frozen Peak (gelo e aço)

func _montar_gelo(cfg: Dictionary) -> void:
	_mat_ouro = ComplexoLancamento._material_metal(Color(0.74, 0.78, 0.84), 1.0, 0.22)   # cromo
	for item in cfg.get("martelos", []):
		_montar_martelo(item, cfg.get("martelo", {}))
	for item in cfg.get("pingentes", []):
		_montar_pingentes(item, cfg.get("pingente", {}))
	for item in cfg.get("prensas", []):
		_montar_prensa(item, cfg.get("prensa", {}))
	for item in cfg.get("bolas", []):
		_montar_bolas(item, cfg.get("bola", {}))
	for item in cfg.get("turbinas", []):
		_montar_turbina(item, cfg.get("turbina", {}))
	for item in cfg.get("placas", []):
		_montar_placas(item, cfg.get("placa", {}))
	for item in cfg.get("focas", []):
		_montar_focas(item, cfg.get("foca", {}))
	for item in cfg.get("yetis", []):
		_montar_yetis(item, cfg.get("yeti", {}))
	if cfg.has("yetis_plataforma"):
		_montar_yetis_plataforma(cfg.yetis_plataforma)
	_portoes.sort_custom(func(a, b): return a.s < b.s)
	for k in _portoes.size():
		_portoes[k].id = k
	_atualizar()
	if OS.get_environment("TSC_SUB_LOG") != "":
		for g: Dictionary in _portoes:
			print("[ARMADILHA] %s em s=%.0f %s" % [g.tipo, g.s, str(sub.amostra(g.i).snapped(Vector3.ONE))])


## Laje de concreto embaixo e colunas até o chão nas duas pontas (nada flutua).
func _apoios_gelo(pai: Node3D, i: int, meia_lado: float, prof: float) -> void:
	var c := sub.amostra(i)
	var b := _base(i)
	var pecas: Array[Transform3D] = []
	pecas.append(Transform3D(b * Basis.from_scale(Vector3(meia_lado * 2.0 + 4.0, 1.2, prof + 4.0)), c + Vector3.UP * (-ComplexoSubida.ESPESSURA_ESTRADA - 0.6)))
	var colunas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var pe := c + sub.lateral_em(i) * s * meia_lado
		var chao := _terreno.altura_em(pe.x, pe.z)
		if c.y - chao > 3.0 and _terreno.gelo:
			# Pedido do dono (2026-10-04): bases antigas (colunas de concreto) viram pedestal de gelo de gotejamento
			_terreno.gelo.pedestal(pai, pe, c.y - 1.2, 4.6, -sub.lateral_em(i) * s, meia_lado - sub.largura_em(i) * 0.5 - 0.4, 3301 + i + int(s) * 5)
		elif c.y - chao > 3.0:
			colunas.append(Transform3D(b * Basis.from_scale(Vector3(3.2, c.y - chao, 3.2)), Vector3(pe.x, (c.y + chao) * 0.5 - 1.5, pe.z)))
	ComplexoLancamento.criar_multimesh(pai, pecas, Gelo.material_fenda())
	ComplexoLancamento.criar_multimesh(pai, colunas, Gelo.material(Gelo.Mat.CONCRETO))
	var est := StaticBody3D.new()
	est.collision_layer = 1
	est.collision_mask = 0
	est.add_to_group("estrutura")
	pai.add_child(est)
	ComplexoLancamento.adicionar_colisoes(est, colunas)


## Pórtico de treliça de aço atravessando a estrada na amostra i: duas torres e a viga de cima, com
## sapatas de blocos de gelo, pingentes pendurados na viga e o logo do jogo nas duas faces.
func _portico_gelo(no: Node3D, i: int, meia_fora: float, altura: float, prof := 3.0, logo := true) -> void:
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var aco: Array[Transform3D] = []
	var colisao: Array[Transform3D] = []
	var gelo_b: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var pe := c + lat * s * meia_fora
		aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * altura, 2.4, 2.6, 0.26, 0.11))
		colisao.append(Transform3D(b * Basis.from_scale(Vector3(2.4, altura, 2.4)), pe + Vector3.UP * altura * 0.5))
		# A sapata desce até a laje de apoio (que fica embaixo da estrada): a torre não fica no ar (dono, 2026-10-04)
		gelo_b.append(Transform3D(b * Basis.from_scale(Vector3(4.2, 3.8, prof + 1.6)), pe + Vector3.DOWN * 0.3))
	var e := c - lat * (meia_fora + 1.2) + Vector3.UP * (altura + 1.0)
	var d := c + lat * (meia_fora + 1.2) + Vector3.UP * (altura + 1.0)
	aco.append_array(ComplexoLancamento.trelica(e, d, 2.4, 2.6, 0.26, 0.11))
	colisao.append(Transform3D(b * Basis.from_scale(Vector3(meia_fora * 2.0 + 2.4, 2.4, 2.4)), c + Vector3.UP * (altura + 1.0)))
	ComplexoLancamento.criar_multimesh(no, aco, Gelo.material(Gelo.Mat.ACO))
	ComplexoLancamento.criar_multimesh(no, gelo_b, Gelo.material_fenda())
	# Pingentes de gelo pendurados na viga
	var pingentes: Array = []
	var n := int(meia_fora * 2.0 / 0.9)
	for k in n:
		var x := lerpf(-meia_fora, meia_fora, (k + 0.5) / n)
		var h := 0.6 + 1.6 * Terreno._hash2(i * 7 + k, 31)
		for face: float in [-1.0, 1.0]:
			pingentes.append(Transform3D(b * Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.16, h, 0.16)), c + lat * x + Vector3.UP * (altura - 0.2 - h * 0.5) + b.z * face * 1.0))
	Gelo.instancias_gelo(no, pingentes, 0.0, 0, false)
	if logo:
		for face: float in [-1.0, 1.0]:
			Gelo.painel_logo(no, c + Vector3.UP * (altura + 1.0) + b.z * face * 1.5, Basis.looking_at(-b.z * face, Vector3.UP), 2.0)
	var est := _corpo_mortal(no)
	ComplexoLancamento.adicionar_colisoes(est, colisao)


# ------------------------------------------------------------------ martelo de gelo (pêndulo)

## Bola de gelo com espinhos de aço balançando de um lado ao outro, pendurada num pórtico de treliça.
## Mesmo movimento (e mesmas consultas dos bots) da lâmina do templo.
func _montar_martelo(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(item[3]) if item.size() > 3 else float(cfg.get("periodo", 4.0))
	var comp := float(cfg.get("comprimento", 9.5))
	var amp := deg_to_rad(float(cfg.get("amplitude", 62.0)))
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	var no := Node3D.new()
	no.name = "Martelo%d" % _portoes.size()
	add_child(no)
	var hp := comp + 0.6
	_apoios_gelo(no, i, meia + 3.2, 4.0)
	_portico_gelo(no, i, meia + 2.8, hp + 0.4)
	var lampadas: Array = []
	for s: float in [-1.0, 1.0]:
		lampadas.append(_lampada(no, c + lat * s * (meia + 2.8) + Vector3.UP * (hp * 0.75) + b.z * 1.5, 0.45))
	var corpo := _corpo_mortal(no, true)
	var raio := 2.3
	var haste := comp - raio * 2.0
	# Duas barras do pivô até a bola e o eixo no pivô
	for s: float in [-1.0, 1.0]:
		_malha(corpo, _caixa(Vector3(0.22, haste + 0.6, 0.22)), _mat_ouro, Transform3D(Basis(Vector3.BACK, s * 0.06), Vector3(s * 0.55, -haste * 0.5, 0)))
	_malha(corpo, _caixa(Vector3(2.4, 0.7, 0.7)), Gelo.material(Gelo.Mat.VERMELHO), Transform3D.IDENTITY)
	_forma_caixa(corpo, Vector3(1.4, haste, 0.5), Transform3D(Basis.IDENTITY, Vector3(0, -haste * 0.5, 0)))
	var esfera := SphereMesh.new()
	esfera.radius = raio
	esfera.height = raio * 2.0
	esfera.radial_segments = 20
	esfera.rings = 10
	var centro := Vector3(0, -comp + raio, 0)
	# Bola de cristal de gelo (pedido do dono, 2026-10-04, arte "bola" em assets/frozen/extruturas): esfera
	# azul funda com a rede de fraturas brancas, espinhos grandes de cristal em todas as direções (uns
	# compridos, outros curtos, com um colar de lascas no pé) e neve assentada no alto
	var portao = load("res://scripts/mundo/portao_gelo.gd")
	_malha(corpo, esfera, portao._material("bola"), Transform3D(Basis.IDENTITY, centro))
	var espinhos: Array = []
	var lascas: Array = []
	for k in 15:
		var u := (k + 0.5) / 15.0
		var th := acos(1.0 - 2.0 * u)
		var ph := k * 2.39996
		var dir := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
		var comp_e := 1.1 + 1.1 * Terreno._hash2(k * 7 + i, 13)
		var larg_e := 0.42 + 0.2 * Terreno._hash2(k * 3 + i, 29)
		var bq := Basis(Quaternion(Vector3.UP, dir)) * Basis(Vector3.UP, k * 1.7)
		espinhos.append(Transform3D(bq * Basis.from_scale(Vector3(larg_e, comp_e, larg_e)), centro + dir * (raio - 0.25 + comp_e * 0.5)))
		for j in 2:
			var lado := (bq * Vector3(cos(j * 2.1), 0.0, sin(j * 2.1))).normalized()
			var dl := (dir + lado * 0.55).normalized()
			var cl := comp_e * (0.3 + 0.12 * j)
			lascas.append(Transform3D(Basis(Quaternion(Vector3.UP, dl)) * Basis.from_scale(Vector3(larg_e * 0.45, cl, larg_e * 0.45)), centro + dir * (raio - 0.2) + lado * larg_e * 0.6 + dl * cl * 0.5))
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 5
	cone.rings = 1
	Gelo._instancias(corpo, cone, espinhos, portao._material("espinho"), false)
	Gelo._instancias(corpo, cone, lascas, portao._material("espinho"), false)
	# Neve em cima (acompanha a bola)
	var neve_b := SphereMesh.new()
	neve_b.radius = raio * 0.72
	neve_b.height = raio * 0.5
	neve_b.radial_segments = 16
	neve_b.rings = 6
	_malha(corpo, neve_b, Gelo.material(Gelo.Mat.NEVE), Transform3D(Basis.IDENTITY, centro + Vector3.UP * raio * 0.78))
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = raio + 0.8
	cs.shape = sp
	cs.position = centro
	corpo.add_child(cs)
	_portoes.append({"tipo": "lamina", "i": i, "s": sub.progresso_amostra(i), "comp": 1.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "amp": amp, "l": comp, "hp": hp, "corpo": corpo, "pivo": c + Vector3.UP * hp, "base": b, "lampadas": lampadas, "total": false})


# ------------------------------------------------------------------ túnel de gelo com estalactites

const CAVERNA := preload("res://scripts/mundo/caverna_gelo.gd")

## Pedido do dono (2026-10-03, arte em assets/frozen/extruturas/entradagelo*.png): túnel de blocos de
## gelo sobre a estrada; do teto despenca uma leva de estalactites numa faixa, que estilhaça no chão, e
## depois de meio período a leva da outra faixa. As estalactites crescem de novo no teto; antes de cair,
## tremem e soltam pó de neve (o aviso). Mesmo ritmo e mesmas consultas dos bots da lança ("lanca").
func _montar_pingentes(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(item[3]) if item.size() > 3 else float(cfg.get("periodo", 5.0))
	var comp := float(cfg.get("comprimento", 12.0))
	var i_meio := sub.indice_adiante(i, comp * 0.5)
	var c := sub.amostra(i_meio)
	var t := sub.tangente_em(i_meio)
	var lat := sub.lateral_em(i_meio)
	var nrm := lat.cross(t).normalized()
	var b := Basis(lat, nrm, -t)
	var meia := sub.largura_em(i_meio) * 0.5
	var no := Node3D.new()
	no.name = "Pingentes%d" % _portoes.size()
	add_child(no)
	var alto := float(cfg.get("altura", 9.5))
	var w := meia + 2.2
	var h := alto + 7.2
	var chao := c.y - 4.0
	if _terreno:
		chao = minf(_terreno.altura_em(c.x + lat.x * (w + 2.0), c.z + lat.z * (w + 2.0)), _terreno.altura_em(c.x - lat.x * (w + 2.0), c.z - lat.z * (w + 2.0)))
	var caverna := Node3D.new()
	caverna.name = "Caverna"
	no.add_child(caverna)
	caverna.global_transform = Transform3D(b, c)
	var col := CAVERNA.montar(caverna, w, h, comp + 2.0, minf(chao - c.y, -1.0), 401 + i)
	var est := StaticBody3D.new()
	est.collision_layer = 1
	est.collision_mask = 0
	est.add_to_group("estrutura")
	caverna.add_child(est)
	ComplexoLancamento.adicionar_colisoes(est, col)
	var corpos: Array = []
	var cristais: Array = []
	var estouros: Array = []
	var poeiras: Array = []
	var portao = load("res://scripts/mundo/portao_gelo.gd")
	for lado in 2:
		var s := -1.0 if lado == 0 else 1.0
		var corpo := _corpo_mortal(no, true)
		var largura := meia - 0.5
		_forma_caixa(corpo, Vector3(largura, 3.2, comp - 0.6), Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)))
		var cr := CAVERNA.estalactites(corpo, largura, comp - 0.8, -0.3, 77 + lado * 13 + i)
		cr.position = Vector3(0.0, 4.4, 0.0)
		cristais.append(cr)
		corpos.append([corpo, s * (meia * 0.5 + 0.1)])
		# Estilhaços e nuvem de neve quando a leva bate no chão
		var estouro := GPUParticles3D.new()
		estouro.amount = 90
		estouro.lifetime = 1.3
		estouro.one_shot = true
		estouro.explosiveness = 0.92
		estouro.emitting = false
		estouro.local_coords = false
		var pe := ParticleProcessMaterial.new()
		pe.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pe.emission_box_extents = Vector3(largura * 0.5, 0.3, (comp - 1.0) * 0.5)
		pe.direction = Vector3.UP
		pe.spread = 70.0
		pe.initial_velocity_min = 3.0
		pe.initial_velocity_max = 9.0
		pe.gravity = Vector3(0.0, -16.0, 0.0)
		pe.angular_velocity_min = -400.0
		pe.angular_velocity_max = 400.0
		pe.scale_min = 0.4
		pe.scale_max = 1.3
		estouro.process_material = pe
		var lasca := CylinderMesh.new()
		lasca.top_radius = 0.0
		lasca.bottom_radius = 0.16
		lasca.height = 0.6
		lasca.radial_segments = 5
		lasca.rings = 1
		lasca.material = portao._material("letra")
		estouro.draw_pass_1 = lasca
		no.add_child(estouro)
		estouro.global_transform = Transform3D(b, c + lat * s * (meia * 0.5 + 0.1) + nrm * 0.3)
		estouros.append(estouro)
		# Pó de neve caindo do teto: aviso de que essa faixa vai levar a leva
		var poeira := GPUParticles3D.new()
		poeira.amount = 60
		poeira.lifetime = 1.0
		poeira.emitting = false
		poeira.local_coords = false
		var pp := ParticleProcessMaterial.new()
		pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pp.emission_box_extents = Vector3(largura * 0.5, 0.2, (comp - 1.0) * 0.5)
		pp.direction = Vector3.DOWN
		pp.spread = 10.0
		pp.initial_velocity_min = 1.0
		pp.initial_velocity_max = 3.0
		pp.gravity = Vector3(0.0, -6.0, 0.0)
		pp.scale_min = 0.6
		pp.scale_max = 1.4
		poeira.process_material = pp
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 0.5)
		var mq := StandardMaterial3D.new()
		mq.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mq.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mq.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mq.albedo_texture = Gelo._textura_floco()
		mq.albedo_color = Color(0.92, 0.97, 1.0, 0.8)
		q.material = mq
		poeira.draw_pass_1 = q
		no.add_child(poeira)
		poeira.global_transform = Transform3D(b, c + lat * s * (meia * 0.5 + 0.1) + nrm * (alto + 4.6))
		poeiras.append(poeira)
	_portoes.append({"tipo": "lanca", "i": i, "s": sub.progresso_amostra(i), "comp": comp, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "mover": float(cfg.get("mover_s", 0.25)), "fora": float(cfg.get("fora_s", 1.6)), "corpos": corpos,
		"centro": c, "base": b, "nrm": nrm, "lat": lat, "placa": null, "total": false, "y_rec": alto,
		"estalactites": cristais, "estouros": estouros, "poeiras": poeiras, "e_ant": [0.0, 0.0], "cresce": [1.0, 1.0]})


## Leva de estalactites da faixa `lado`: estilhaça ao bater no chão, some, e cresce de novo no teto.
func _animar_estalactites(g: Dictionary, lado: int, e: float) -> void:
	var cr: Node3D = g.estalactites[lado]
	var ea: float = g.e_ant[lado]
	if e >= 0.97 and ea < 0.97:
		cr.visible = false
		(g.estouros[lado] as GPUParticles3D).restart()
	if e <= 0.001 and not cr.visible:
		cr.visible = true
		g.cresce[lado] = 0.0
	g.cresce[lado] = move_toward(float(g.cresce[lado]), 1.0, get_physics_process_delta_time() / 0.9)
	var vai_cair := e <= 0.001 and _extensao_lanca(g, lado, _t + 0.9) > 0.0
	cr.scale = Vector3(1.0, maxf(float(g.cresce[lado]), 0.05), 1.0)
	cr.position = Vector3(sin(_t * 70.0) * 0.06 if vai_cair else 0.0, 4.4, 0.0)
	var po: GPUParticles3D = g.poeiras[lado]
	if po.emitting != vai_cair:
		po.emitting = vai_cair
	g.e_ant[lado] = e


# ------------------------------------------------------------------ prensa de gelo

const ESMAGADOR := preload("res://scripts/mundo/esmagador_gelo.gd")

## Esmagador (pedido do dono, 2026-10-04, arte em assets/frozen/extruturas/esmagador.png): máquina de aço
## e blocos de gelo por cima da estrada; o bloco dos faróis vermelhos despenca entre os dois pilares e
## fecha a estrada inteira; sobe devagar. Antes de cair, os faróis e a tela da viga piscam em vermelho.
## A máquina fica em cima de um maciço de gelo que vem do chão. (Mesmo ritmo da boca da serpente.)
func _montar_prensa(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var periodo := float(item[3]) if item.size() > 3 else float(cfg.get("periodo", 6.0))
	var comp := float(cfg.get("comprimento", 9.0))
	var i_meio := sub.indice_adiante(i, comp * 0.5)
	var c := sub.amostra(i_meio)
	var b := _base(i_meio)
	var lat := sub.lateral_em(i_meio)
	var meia := sub.largura_em(i_meio) * 0.5
	var no := Node3D.new()
	no.name = "Prensa%d" % _portoes.size()
	add_child(no)
	var chao := c.y - 4.0
	if _terreno:
		chao = INF
		for ax: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for az: float in [-1.0, 0.0, 1.0]:
				var p := c + lat * ax * (meia + 23.0) + b.z * az * (comp * 0.5 + 7.0)
				chao = minf(chao, _terreno.altura_em(p.x, p.z))
	var maquina := Node3D.new()
	maquina.name = "Esmagador"
	no.add_child(maquina)
	maquina.global_transform = Transform3D(b, c)
	var m: Dictionary = ESMAGADOR.montar(maquina, meia, comp, minf(chao - c.y, -4.0) - 1.0, 911 + i)
	var est := _corpo_mortal(maquina)
	ComplexoLancamento.adicionar_colisoes(est, m.colisao)
	var apoio := StaticBody3D.new()
	apoio.collision_layer = 1
	apoio.collision_mask = 0
	apoio.add_to_group("estrutura")
	maquina.add_child(apoio)
	ComplexoLancamento.adicionar_colisoes(apoio, m.base)
	# O bloco (origem na face de baixo)
	var corpo := _corpo_mortal(no, true)
	var largura := meia * 2.0 + 1.0
	m.merge(ESMAGADOR.bloco(corpo, largura, comp, 977 + i))
	_forma_caixa(corpo, Vector3(largura, 5.5, comp), Transform3D(Basis.IDENTITY, Vector3(0, 2.75, 0)))
	_portoes.append({"tipo": "serpente", "i": i, "s": sub.progresso_amostra(i), "comp": comp, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": periodo, "fecha": float(cfg.get("fecha_s", 0.35)), "fechada": float(cfg.get("fechada_s", 1.4)), "abre": float(cfg.get("abre_s", 1.0)),
		"corpo": corpo, "centro": c, "base": b, "olhos": [], "total": true, "giro": 0.0, "esmagador": m})


## Esmagador: faróis e luzes piscando no perigo, tela da viga (barra que arma, setas na queda), hastes
## dos pistões acompanhando o bloco e a nuvem de neve na batida.
func _animar_esmagador(g: Dictionary, h: float, perigo: bool) -> void:
	var e: Dictionary = g.esmagador
	var f := fposmod(_t + float(g.fase), float(g.periodo))
	var ciclo := float(g.fecha) + float(g.fechada) + float(g.abre)
	var carga := clampf((f - ciclo) / maxf(float(g.periodo) - ciclo, 0.1), 0.0, 1.0)
	var pisca := 0.5 + 0.5 * sin(_t * 22.0)
	var tela: ShaderMaterial = e.tela
	tela.set_shader_parameter("perigo", 1.0 if perigo else 0.0)
	tela.set_shader_parameter("carga", carga)
	var faixas: StandardMaterial3D = e.faixas
	faixas.emission = Color(1.0, 0.1, 0.05) if perigo else Color(0.5, 0.9, 1.0)
	faixas.albedo_color = faixas.emission
	for m: StandardMaterial3D in e.lampadas:
		m.emission_energy_multiplier = lerpf(1.2, 12.0, pisca) if perigo else 3.2
	for l: OmniLight3D in e.luzes:
		l.light_energy = lerpf(0.6, 5.0, pisca) if perigo else 1.4
	var topo := h + ESMAGADOR.ALTO + 0.3
	for haste: Node3D in e.hastes:
		var comp_h := maxf(ESMAGADOR.Y_VIGA + 0.4 - topo, 0.05)
		haste.position.y = topo + comp_h * 0.5
		haste.scale = Vector3(1.0, comp_h, 1.0)
	if h <= 0.3 and float(e.h_ant) > 0.3:
		(e.estouro as GPUParticles3D).restart()
	e.h_ant = h


# ------------------------------------------------------------------ bolas de neve (avalanche)

## Bolas de neve gigantes rolando ladeira abaixo, numa faixa de cada vez, saindo de um portal de
## blocos de gelo com o logo do jogo. Para o começo e o fim fazerem sentido (pedido do dono: "nascem
## e morrem sem lógica"): a bola CAI do depósito de neve do portal, pequena, e cresce enquanto embala;
## no pé da ladeira há uma grelha aquecida atravessando a estrada (barras em brasa, vapor) — a bola
## derrete em cima dela, encolhendo até sumir numa nuvem de vapor.
func _montar_bolas(item: Array, cfg: Dictionary) -> void:
	var i0 := sub.indice_trecho(str(item[0]), float(item[1]))
	var i1 := sub.indice_trecho(str(item[0]), float(item[2]))
	var fase := float(item[3]) if item.size() > 3 else 0.0
	var periodo := float(item[4]) if item.size() > 4 else float(cfg.get("periodo", 9.0))
	var raio := float(cfg.get("raio", 2.0))
	var vel := float(cfg.get("velocidade", 13.0))
	var padrao := str(cfg.get("padrao", "alterna"))
	var no := Node3D.new()
	no.name = "Bolas%d" % _zonas_pedra.size()
	add_child(no)
	var c := sub.amostra(i1)
	var b := _base(i1)
	var lat := sub.lateral_em(i1)
	var meia := sub.largura_em(i1) * 0.5
	# Portal: a entrada de gelo da arte do dono (pedido 2026-10-03: no lugar do pórtico de blocos)
	var w := meia + 2.2
	var chao := minf(_terreno.altura_em(c.x + lat.x * (w + 2.0), c.z + lat.z * (w + 2.0)), _terreno.altura_em(c.x - lat.x * (w + 2.0), c.z - lat.z * (w + 2.0))) if _terreno else c.y - 4.0
	var caverna := Node3D.new()
	caverna.name = "Caverna"
	no.add_child(caverna)
	caverna.global_transform = Transform3D(b, c)
	var col := CAVERNA.montar(caverna, w, 12.5, 7.0, minf(chao - c.y, -1.0), 557 + i1)
	var est := StaticBody3D.new()
	est.collision_layer = 1
	est.collision_mask = 0
	est.add_to_group("estrutura")
	caverna.add_child(est)
	ComplexoLancamento.adicionar_colisoes(est, col)
	var lampadas: Array = []
	for s: float in [-1.0, 1.0]:
		lampadas.append(_lampada(no, c + lat * s * (meia + 1.4) + Vector3.UP * 4.0 + b.z * 4.2, 0.45))
	var comp := sub.progresso_amostra(i1) - sub.progresso_amostra(i0)
	var qtd := int(ceil(comp / vel / periodo)) + 2
	var malha := SphereMesh.new()
	malha.radius = raio
	malha.height = raio * 2.0
	malha.radial_segments = 20
	malha.rings = 10
	var pedras: Array = []
	for k in qtd:
		var corpo := _corpo_mortal(no, true)
		var mi := MeshInstance3D.new()
		mi.mesh = malha
		mi.material_override = Gelo.material(Gelo.Mat.NEVE)
		corpo.add_child(mi)
		corpo.set_meta("malha", mi)
		# Lascas de gelo cravadas (dá para ver a bola girando)
		var lascas: Array = []
		for j in 7:
			var dir := Vector3(sin(j * 2.4) * cos(j * 1.1), sin(j * 1.1), cos(j * 2.4) * cos(j * 1.1)).normalized()
			lascas.append(Transform3D(Basis(Quaternion(Vector3.UP, dir)) * Basis.from_scale(Vector3(0.45, 1.0, 0.45)), dir * (raio * 0.95)))
		Gelo.instancias_gelo(mi, lascas, 0.2, 0, false, 0.0, 3)
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = raio * 0.95
		cs.shape = sp
		corpo.add_child(cs)
		corpo.visible = false
		pedras.append(corpo)
	_grelha_quente(no, i0)
	_zonas_pedra.append({"i0": i0, "i1": i1, "s0": sub.progresso_amostra(i0), "s1": sub.progresso_amostra(i1), "fase": fase, "periodo": periodo,
		"vel": vel, "raio": raio, "padrao": padrao, "pedras": pedras, "lampadas": lampadas, "estouro": _estouro_neve(no, raio), "n_estouro": -1000000})


const GRELHA_COMP := 9.0   # metros de grelha aquecida no pé da ladeira (a bola derrete em cima dela)

## Grelha aquecida no pé da ladeira das bolas de neve: chapa de aço escuro rente ao piso com barras em
## brasa atravessadas e vapor subindo. Só visual (rente ao asfalto, o carro passa por cima).
func _grelha_quente(no: Node3D, i0: int) -> void:
	var i_meio := sub.indice_adiante(i0, GRELHA_COMP * 0.5)
	var c := sub.amostra(i_meio)
	var b := _base(i_meio)
	var n := sub.normal_em(i_meio)
	var t := sub.tangente_em(i_meio)
	var larg := sub.largura_em(i_meio)
	var bt := Basis(sub.lateral_em(i_meio), n, -t)
	var chapa: Array[Transform3D] = [Transform3D(bt * Basis.from_scale(Vector3(larg - 0.4, 0.06, GRELHA_COMP)), c + n * 0.03)]
	ComplexoLancamento.criar_multimesh(no, chapa, Gelo.material(Gelo.Mat.ACO), false)
	var barras: Array[Transform3D] = []
	for k in 9:
		barras.append(Transform3D(bt * Basis.from_scale(Vector3(larg - 1.0, 0.08, 0.3)), c + t * (float(k) - 4.0) * (GRELHA_COMP / 9.0) + n * 0.07))
	ComplexoLancamento.criar_multimesh(no, barras, ComplexoLancamento._material_luz(Color(1.0, 0.33, 0.05), 3.0), false)
	var vapor := GPUParticles3D.new()
	vapor.amount = 36
	vapor.lifetime = 2.2
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(larg * 0.45, 0.1, GRELHA_COMP * 0.45)
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0.0, 0.6, 0.0)
	pm.scale_min = 1.2
	pm.scale_max = 2.6
	pm.color = Color(1.0, 1.0, 1.0, 0.22)
	vapor.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mv := StandardMaterial3D.new()
	mv.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mv.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mv.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mv.vertex_color_use_as_albedo = true
	mv.albedo_color = Color(0.92, 0.96, 1.0, 0.5)
	quad.material = mv
	vapor.draw_pass_1 = quad
	vapor.transform = Transform3D(b, c + n * 0.3)
	vapor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	no.add_child(vapor)


## Nuvem de neve de quando a bola se desfaz no pé da ladeira (um disparo por bola).
func _estouro_neve(pai: Node3D, raio: float) -> GPUParticles3D:
	var part := GPUParticles3D.new()
	part.amount = 40
	part.lifetime = 1.3
	part.one_shot = true
	part.explosiveness = 0.95
	part.emitting = false
	part.local_coords = false
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = raio * 0.6
	proc.direction = Vector3.UP
	proc.spread = 80.0
	proc.initial_velocity_min = 3.0
	proc.initial_velocity_max = 9.0
	proc.gravity = Vector3(0, -6.0, 0)
	proc.scale_min = 1.6
	proc.scale_max = 3.6
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 1.0))
	curva.add_point(Vector2(1.0, 0.0))
	var tc := CurveTexture.new()
	tc.curve = curva
	proc.alpha_curve = tc
	part.process_material = proc
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.95, 0.97, 1.0, 0.7)
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Selva._textura_nuvem()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	quad.material = mat
	part.draw_pass_1 = quad
	pai.add_child(part)
	return part


# ------------------------------------------------------------------ turbinas de vento

## Três turbinas na beirada soprando neve para dentro da estrada: o vento empurra o carro para o
## outro lado (não mata). As hélices embalam antes do sopro.
func _montar_turbina(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var lado := float(item[2])
	var fase := float(item[3]) if item.size() > 3 else 0.0
	var periodo := float(item[4]) if item.size() > 4 else float(cfg.get("periodo", 5.0))
	var comp := float(cfg.get("comprimento", 14.0))
	var i_meio := sub.indice_adiante(i, comp * 0.5)
	var c := sub.amostra(i_meio)
	var b := _base(i_meio)
	var lat := sub.lateral_em(i_meio)
	var meia := sub.largura_em(i_meio) * 0.5
	var no := Node3D.new()
	no.name = "Turbina%d" % _portoes.size()
	add_child(no)
	_apoios_gelo(no, i_meio, meia + 3.0, comp)
	# Casa das turbinas: caixa de aço com capa de neve e o logo atrás
	var casa: Array[Transform3D] = [Transform3D(b * Basis.from_scale(Vector3(3.4, 6.4, comp + 2.0)), c + lat * lado * (meia + 2.4) + Vector3.UP * 3.2)]
	ComplexoLancamento.criar_multimesh(no, casa, Gelo.material(Gelo.Mat.ACO))
	var neve: Array[Transform3D] = [Transform3D(b * Basis.from_scale(Vector3(3.8, 0.5, comp + 2.4)), c + lat * lado * (meia + 2.4) + Vector3.UP * 6.6)]
	ComplexoLancamento.criar_multimesh(no, neve, Gelo.material(Gelo.Mat.NEVE))
	Gelo.painel_logo(no, c + lat * lado * (meia + 4.2) + Vector3.UP * 3.4, Basis.looking_at(-lat * lado, Vector3.UP), 2.4)
	var est := StaticBody3D.new()
	est.collision_layer = 1
	est.collision_mask = 0
	est.add_to_group("estrutura")
	no.add_child(est)
	ComplexoLancamento.adicionar_colisoes(est, casa)
	var particulas: Array = []
	var helices: Array = []
	var aro := TorusMesh.new()
	aro.inner_radius = 1.75
	aro.outer_radius = 2.15
	for k in 3:
		var z := (k - 1) * comp * 0.33
		var boca := c + lat * lado * (meia + 0.55) + Vector3.UP * 3.0 + b.z * z
		var frente_b := Basis.looking_at(-lat * lado, Vector3.UP)   # -Z aponta para dentro da estrada
		_malha(no, aro, Gelo.material(Gelo.Mat.VERMELHO), Transform3D(frente_b * Basis(Vector3.RIGHT, PI * 0.5), boca))
		var helice := Node3D.new()
		helice.transform = Transform3D(frente_b, boca)
		no.add_child(helice)
		for p in 5:
			var giro_p := Basis(Vector3.FORWARD, TAU * p / 5.0)
			_malha(helice, _caixa(Vector3(0.5, 1.65, 0.08)), _mat_ouro, Transform3D(giro_p * Basis(Vector3.UP, 0.5), giro_p * Vector3(0, 0.9, 0)))
		_malha(helice, _caixa(Vector3(0.6, 0.6, 0.5)), Gelo.material(Gelo.Mat.ACO), Transform3D.IDENTITY)
		helices.append(helice)
		var pj := _particulas_jato(-lat * lado, meia * 2.0 + 4.0)
		pj.position = boca - lat * lado * 0.6
		no.add_child(pj)
		particulas.append(pj)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitorable = false
	_forma_caixa(area, Vector3(meia * 2.0, 4.0, comp))
	area.transform = Transform3D(b, c + Vector3.UP * 2.0)
	no.add_child(area)
	_jatos.append({"area": area, "dir": -lat * lado, "forca": float(cfg.get("forca", 16.0))})
	_portoes.append({"tipo": "jato", "i": i, "s": sub.progresso_amostra(i), "comp": comp, "fase": fase, "periodo": periodo,
		"ligado": float(cfg.get("ligado_s", 1.8)), "jato": _jatos.size() - 1, "particulas": particulas, "total": true,
		"helices": helices, "rot": 2.0})


# ------------------------------------------------------------------ gelo fino (placas que quebram)

## Trecho sem laje: o piso são placas de gelo fino apoiadas em duas longarinas de aço. Cada placa
## racha `tempo_s` depois de um carro pisar nela, cai e só volta `volta_s` depois: quem passa
## embalado atravessa; quem vai devagar, para, ou chega logo atrás de outro carro cai no buraco.
## item = [trecho, m0, m1] (o ComplexoSubida já deixou esse intervalo sem piso).
func _montar_placas(item: Array, cfg: Dictionary) -> void:
	var i0 := sub.indice_trecho(str(item[0]), float(item[1]))
	var i1 := sub.indice_trecho(str(item[0]), float(item[2]))
	var passo := float(cfg.get("comprimento", 4.0))
	var s0 := sub.progresso_amostra(i0)
	var total := sub.progresso_amostra(i1) - s0
	var n := maxi(int(round(total / passo)), 1)
	passo = total / n
	var no := Node3D.new()
	no.name = "Placas%d" % _placas.size()
	add_child(no)
	var mat: Material
	var mat_laje: Material
	var mat_long: Material
	if gelo:
		var mg := ShaderMaterial.new()
		mg.shader = load("res://shaders/pista_gelo_vivo.gdshader")
		mg.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 3))
		mg.set_shader_parameter("largura", sub.largura_em(i0))
		mg.set_shader_parameter("cor_gelo", Color(0.45, 0.78, 0.95))
		mg.set_shader_parameter("cor_fundo", Color(0.2, 0.5, 0.75))
		mat = mg
		mat_laje = Gelo.material(Gelo.Mat.GELO)
		mat_long = Gelo.material(Gelo.Mat.VERMELHO)
	else:
		# Selva: lajes de pedra rachada sobre vigas de ouro (pedido do dono: pedaços de pista que caem)
		mat = Selva.material_pedra(1, 0.8)
		mat_laje = Selva.material_pedra(2, 1.0)
		mat_long = _mat_ouro
	var corpos: Array = []
	var xfs: Array = []
	var meias := PackedFloat32Array()   # meia largura de cada placa
	var longarinas: Array[Transform3D] = []
	for k in n:
		var j := sub.indice_adiante(i0, (k + 0.5) * passo)
		var t := sub.tangente_em(j)
		var lat := sub.lateral_em(j)
		var nrm := lat.cross(t).normalized()
		var bp := Basis(lat, nrm, -t)
		var larg := sub.largura_em(j)
		var corpo := AnimatableBody3D.new()
		corpo.sync_to_physics = true
		corpo.collision_layer = 1
		corpo.collision_mask = 0
		corpo.add_to_group("estrutura")
		corpo.set_meta("aderencia", float(cfg.get("aderencia", 0.5)))
		var cs := CollisionShape3D.new()
		var forma := BoxShape3D.new()
		forma.size = Vector3(larg, 0.5, passo - 0.1)
		cs.shape = forma
		cs.position = Vector3(0, -0.25, 0)
		corpo.add_child(cs)
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(larg - 0.1, passo - 0.14)
		mi.mesh = pm
		mi.material_override = mat
		mi.position = Vector3(0, 0.01, 0)
		corpo.add_child(mi)
		_malha(corpo, _caixa(Vector3(larg - 0.1, 0.45, passo - 0.14)), mat_laje, Transform3D(Basis.IDENTITY, Vector3(0, -0.24, 0)))
		no.add_child(corpo)
		var xf := Transform3D(bp, sub.amostra(j))
		corpo.global_transform = xf
		corpos.append(corpo)
		xfs.append(xf)
		meias.append(larg * 0.5)
		for s: float in [-1.0, 1.0]:
			longarinas.append(Transform3D(bp * Basis.from_scale(Vector3(0.6, 1.0, passo + 0.05)), sub.amostra(j) + lat * s * (larg * 0.5 - 0.3) - nrm * 1.0))
	ComplexoLancamento.criar_multimesh(no, longarinas, mat_long)
	var i_meio := sub.indice_adiante(i0, total * 0.5)
	var estado := PackedInt32Array()
	estado.resize(n)
	var t_ev := PackedFloat32Array()
	t_ev.resize(n)
	_placas.append({"corpos": corpos, "xf": xfs, "estado": estado, "t_ev": t_ev, "p0": sub.amostra(i0), "tan": sub.tangente_em(i0), "meias": meias,
		"centro": sub.amostra(i_meio), "raio": total * 0.5 + 20.0,
		"passo": passo, "tempo": float(cfg.get("tempo_s", 0.8)), "volta": float(cfg.get("volta_s", 5.0))})
	_portoes.append({"tipo": "placas", "i": i0, "s": s0, "comp": total, "fase": 0.0, "periodo": 1.0, "total": true, "zona": _placas.size() - 1})


## Estados da placa: 0 inteira, 1 rachando (cai em t_ev), 2 caída (volta em t_ev).
func _atualizar_placas() -> void:
	for z: Dictionary in _placas:
		var estado: PackedInt32Array = z.estado
		var t_ev: PackedFloat32Array = z.t_ev
		var n := estado.size()
		# Placa embaixo de cada carro (vale em curva também: a zona pode ser uma curva em U)
		for no_v in get_tree().get_nodes_in_group("veiculo"):
			var v := no_v as Veiculo
			if v == null or v.rodas_no_chao == 0 or v.global_position.distance_to(z.centro) > float(z.raio):
				continue
			for k in n:
				if estado[k] != 0:
					continue
				var q: Vector3 = (z.xf[k] as Transform3D).affine_inverse() * v.global_position
				if absf(q.z) < float(z.passo) * 0.5 + 0.3 and absf(q.x) < (z.meias as PackedFloat32Array)[k] + 0.5 and q.y > -1.5 and q.y < 3.5:
					estado[k] = 1
					t_ev[k] = _t + float(z.tempo)
					if _log_placa:
						print("[PLACA] %s rachou a placa %d/%d" % [v.nome_piloto, k, n])
		for k in n:
			var corpo: AnimatableBody3D = z.corpos[k]
			var xf: Transform3D = z.xf[k]
			match estado[k]:
				1:
					if _t >= t_ev[k]:
						estado[k] = 2
						t_ev[k] = _t + float(z.volta)
					else:
						# Rachando: treme e afunda um pouco
						var f := 1.0 - (t_ev[k] - _t) / float(z.tempo)
						corpo.global_transform = xf * Transform3D(Basis(Vector3.FORWARD, sin(_t * 60.0 + k) * 0.012 * f), Vector3(0, -0.12 * f + sin(_t * 47.0 + k * 2.0) * 0.03 * f, 0))
				2:
					var caiu := float(z.volta) - (t_ev[k] - _t)
					if _t >= t_ev[k]:
						estado[k] = 0
						corpo.visible = true
						corpo.global_transform = xf
						corpo.reset_physics_interpolation()
					elif caiu < 2.2:
						corpo.global_transform = xf * Transform3D(Basis(Vector3.RIGHT, caiu * 0.7 * (1.0 if k % 2 == 0 else -1.0)), Vector3(0, -0.2 - 4.9 * caiu * caiu, 0))
					elif corpo.visible:
						corpo.visible = false
						corpo.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, -600.0 - k * 6.0, 0))
						corpo.reset_physics_interpolation()
		z.estado = estado
		z.t_ev = t_ev


## Estátuas que cospem fogo (montanha "fogo"): liga/desliga os jatos e a luz; com o fogo ligado, quem está
## na faixa dele explode (volta ao checkpoint).
func _animar_fogo(g: Dictionary) -> void:
	var lig := _jato_ligado(g, _t)
	var aviso := _jato_ligado(g, _t + 0.35)   # a luz acende um instante antes: dá para ver chegando
	for j: GPUParticles3D in g.jatos:
		if j.emitting != lig:
			j.emitting = lig
	for l: OmniLight3D in g.luzes:
		l.light_energy = 6.0 if lig else (1.2 if aviso else 0.0)
	if not lig:
		return
	var c: Vector3 = g.c
	for no_v in get_tree().get_nodes_in_group("veiculo"):
		var v := no_v as Veiculo
		if v == null or v.eliminado or v.fantasma():
			continue
		var d := v.global_position - c
		if absf(d.dot(g.tan)) < 2.4 and absf(d.dot(g.lat)) < float(g.meia) + 1.0 and absf(d.y) < 4.0:
			v.eliminar("fogo")


## Alguma placa da zona falta (ou vai faltar) daqui a t segundos?
func _perigo_placas(g: Dictionary, t: float) -> bool:
	var z: Dictionary = _placas[int(g.zona)]
	var estado: PackedInt32Array = z.estado
	var t_ev: PackedFloat32Array = z.t_ev
	var quando := _t + t
	for k in estado.size():
		if estado[k] == 1 and quando >= t_ev[k] and quando < t_ev[k] + float(z.volta):
			return true
		if estado[k] == 2 and quando < t_ev[k]:
			return true
	return false


# ------------------------------------------------------------------ focas (Frozen Peak)

const FOCA := preload("res://scripts/mundo/foca.gd")

## Pedido do dono (2026-10-03, como os dinossauros que vomitam do Extinction Day): duas focas, uma em
## cima de uma geleira de cada lado da estrada, cospem gelo na faixa do lado delas, uma de cada vez.
## Não mata: o carro atingido fica com a direção travada, sem freio nem acelerador, escorregando por
## `congela_s` segundos (Veiculo.gelo_cuspe). item = [trecho, m, fase].
func _montar_focas(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	var no := Node3D.new()
	no.name = "Focas"
	add_child(no)
	var portao = load("res://scripts/mundo/portao_gelo.gd")
	var focas := []
	var jatos := []
	var nevoas := []
	var manchas := []
	for k in 2:
		var s_k := -1.0 if k == 0 else 1.0
		var pe := c + lat * s_k * (meia + 4.3)
		var chao := _terreno.altura_em(pe.x, pe.z) if _terreno else c.y - 4.0
		var topo := c.y + 2.6
		if c.y - chao > 14.0:
			# Estrada alta (em pilares): a geleira fica grudada na beira da pista, sem ir ao chão
			pe = c + lat * s_k * (meia + 3.0)
			chao = c.y - 7.0
		# Geleira saindo do chão até acima da pista; +Z local aponta para a estrada
		var base_g := Node3D.new()
		base_g.name = "Geleira%d" % k
		no.add_child(base_g)
		base_g.global_transform = Transform3D(Basis.looking_at(lat * s_k, Vector3.UP), Vector3(pe.x, 0.0, pe.z))
		var col := FOCA.geleira(base_g, minf(chao, topo - 3.0), topo, 731 + k * 17 + i)
		if _terreno and _terreno.gelo and c.y - _terreno.altura_em(pe.x, pe.z) > 14.0:
			# Estrada alta: a geleira não fica pendurada no ar — pedestal de gelo de gotejamento até o chão
			_terreno.gelo.pedestal(base_g, pe, c.y - 1.5, 6.5, -lat * s_k, 2.7, 1733 + k * 31 + i)
		var est := StaticBody3D.new()
		est.collision_layer = 1
		est.collision_mask = 0
		est.add_to_group("estrutura")
		base_g.add_child(est)
		ComplexoLancamento.adicionar_colisoes(est, col)
		# A foca deitada em cima, de cara para a estrada
		var suporte := Node3D.new()
		suporte.position = Vector3(0.0, topo + 0.45, 0.0)
		suporte.scale = Vector3.ONE * 1.45
		base_g.add_child(suporte)
		var f := FOCA.criar(suporte, 900 + k)
		focas.append(f)
		_forma_caixa(est, Vector3(2.2, 2.0, 5.6), Transform3D(Basis.IDENTITY, Vector3(0.0, topo + 1.4, 0.0)))
		# Jato: lascas de gelo e névoa gelada saindo da boca
		var jato := GPUParticles3D.new()
		jato.amount = 320
		jato.lifetime = 0.55
		jato.local_coords = false
		jato.emitting = false
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0.0, 0.0, -1.0)
		pm.spread = 9.0
		pm.initial_velocity_min = 14.0
		pm.initial_velocity_max = 19.0
		pm.gravity = Vector3(0.0, -7.0, 0.0)
		pm.scale_min = 0.6
		pm.scale_max = 1.4
		pm.particle_flag_align_y = true
		pm.angular_velocity_min = -200.0
		pm.angular_velocity_max = 200.0
		jato.process_material = pm
		var lasca := CylinderMesh.new()
		lasca.top_radius = 0.0
		lasca.bottom_radius = 0.14
		lasca.height = 0.85
		lasca.radial_segments = 5
		lasca.rings = 1
		lasca.material = portao._material("letra")
		jato.draw_pass_1 = lasca
		no.add_child(jato)
		jatos.append(jato)
		var nevoa := GPUParticles3D.new()
		nevoa.amount = 110
		nevoa.lifetime = 0.75
		nevoa.local_coords = false
		nevoa.emitting = false
		var pn := ParticleProcessMaterial.new()
		pn.direction = Vector3(0.0, 0.0, -1.0)
		pn.spread = 13.0
		pn.initial_velocity_min = 10.0
		pn.initial_velocity_max = 14.0
		pn.gravity = Vector3(0.0, -2.5, 0.0)
		pn.damping_min = 3.0
		pn.damping_max = 5.0
		var cresce := Curve.new()
		cresce.add_point(Vector2(0.0, 0.3))
		cresce.add_point(Vector2(1.0, 1.0))
		var tc := CurveTexture.new()
		tc.curve = cresce
		pn.scale_curve = tc
		pn.scale_min = 1.2
		pn.scale_max = 2.2
		nevoa.process_material = pn
		var quad := QuadMesh.new()
		quad.size = Vector2(2.2, 2.2)
		var mq := StandardMaterial3D.new()
		mq.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mq.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mq.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mq.albedo_texture = Gelo._textura_floco()
		mq.albedo_color = Color(0.82, 0.94, 1.0, 0.65)
		quad.material = mq
		nevoa.draw_pass_1 = quad
		no.add_child(nevoa)
		nevoas.append(nevoa)
		# Mancha de geada na faixa
		var mancha := MeshInstance3D.new()
		var pl := PlaneMesh.new()
		pl.size = Vector2(5.6, 9.0)
		mancha.mesh = pl
		var mm := ShaderMaterial.new()
		mm.shader = load("res://shaders/gelo_cuspe.gdshader")
		mm.set_shader_parameter("ruido", Terreno._textura_ruido(0.02, 3, 433))
		mm.set_shader_parameter("semente", 0.31 * (k + 1) + 0.07 * i)
		mancha.material_override = mm
		mancha.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mancha.transform = Transform3D(b, c + lat * (FAIXA if k == 1 else -FAIXA) + sub.normal_em(i) * 0.06)
		no.add_child(mancha)
		manchas.append(mm)
	_portoes.append({"tipo": "foca", "i": i, "s": sub.progresso_amostra(i), "comp": 9.0, "fase": float(item[2]) if item.size() > 2 else 0.0,
		"periodo": float(cfg.get("periodo", 5.0)), "ativo": float(cfg.get("cuspe_s", 1.3)), "congela": float(cfg.get("congela_s", 4.0)),
		"c": c, "lat": lat, "tan": -b.z, "focas": focas, "jatos": jatos, "nevoas": nevoas, "manchas": manchas, "mancha_a": [0.0, 0.0], "total": false})


## Foca k no instante t: [cuspindo, preparo 0..1]. As duas se revezam (meio período de diferença).
func _foca_estado(g: Dictionary, k: int, t: float) -> Array:
	var per: float = g.periodo
	var f := fposmod(t + float(g.fase) + k * per * 0.5, per)
	return [f < float(g.ativo), smoothstep(per - 0.9, per, f)]


func _perigo_foca(g: Dictionary, lado: int, t: float) -> bool:
	return bool(_foca_estado(g, lado, t)[0])


func _animar_focas(g: Dictionary) -> void:
	var lat: Vector3 = g.lat
	var tan: Vector3 = g.tan
	var dt := get_physics_process_delta_time()
	for k in 2:
		var r := _foca_estado(g, k, _t)
		var ativo: bool = r[0]
		var f: Dictionary = g.focas[k]
		FOCA.pose(f, _t + k * 1.7, float(r[1]), ativo)
		var x_faixa := FAIXA if k == 1 else -FAIXA
		var boca := (f.boca as Node3D).global_position
		var alvo := (g.c as Vector3) + lat * x_faixa + Vector3.UP * 0.3
		var giro := Basis.looking_at((alvo - boca).normalized(), Vector3.UP)
		for p: GPUParticles3D in [g.jatos[k], g.nevoas[k]]:
			p.global_transform = Transform3D(giro, boca)
			if p.emitting != ativo:
				p.emitting = ativo
		g.mancha_a[k] = move_toward(float(g.mancha_a[k]), 1.0 if ativo else 0.0, dt * (2.5 if ativo else 0.35))
		(g.manchas[k] as ShaderMaterial).set_shader_parameter("quanto", float(g.mancha_a[k]))
		if not ativo:
			continue
		for no_v in get_tree().get_nodes_in_group("veiculo"):
			var v := no_v as Veiculo
			if v == null or v.eliminado or v.fantasma():
				continue
			var q: Vector3 = v.global_position - (g.c as Vector3)
			if absf(q.dot(tan)) < 4.5 and absf(q.dot(lat) - x_faixa) < 2.8 and absf(q.y) < 3.5:
				v.gelo_cuspe(float(g.congela))


# ------------------------------------------------------------------ yetis (Frozen Peak)

const YETI := preload("res://scripts/mundo/yeti.gd")
static var ultimo_agarrado: Veiculo   # conferência (vista gelo_yeti_seguir)
const YETI_SALTO := 0.6   # segundos do pulo até o teto do carro

## Pedido do dono (2026-10-03): dois yetis, cada um numa geleira (a mesma das focas) de um lado da
## estrada. Quando um carro passa, o yeti pula no teto e fica pendurado por `segura_s` segundos: o carro
## anda normal, mas a direção fica invertida (Veiculo.yeti). Depois ele pula de volta para a geleira e
## espera `descanso_s`. Em trechos só de pista (sem outra armadilha). item = [trecho, m].
func _montar_yetis(item: Array, cfg: Dictionary) -> void:
	var i := sub.indice_trecho(str(item[0]), float(item[1]))
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	var no := Node3D.new()
	no.name = "Yetis"
	add_child(no)
	var bichos := []
	for k in 2:
		var s_k := -1.0 if k == 0 else 1.0
		var pe := c + lat * s_k * (meia + 4.3)
		var chao := _terreno.altura_em(pe.x, pe.z) if _terreno else c.y - 4.0
		var topo := c.y + 2.2
		if c.y - chao > 14.0:
			# Estrada alta (em pilares): a geleira fica grudada na beira da pista, pendurada nela, sem ir ao chão
			pe = c + lat * s_k * (meia + 3.0)
			chao = c.y - 7.0
		if OS.get_environment("TSC_SUB_LOG") != "":
			print("[YETI] %s %.0f: pista %.1f m acima do chão" % [str(item[0]), float(item[1]), c.y - chao])
		var base_g := Node3D.new()
		no.add_child(base_g)
		base_g.global_transform = Transform3D(Basis.looking_at(lat * s_k, Vector3.UP), Vector3(pe.x, 0.0, pe.z))
		var col := FOCA.geleira(base_g, minf(chao, topo - 3.0), topo, 977 + k * 31 + i)
		if _terreno and _terreno.gelo and c.y - _terreno.altura_em(pe.x, pe.z) > 14.0:
			# Estrada alta: pedestal de gelo de gotejamento até o chão (pedido do dono: nada pendurado no ar)
			_terreno.gelo.pedestal(base_g, pe, c.y - 1.5, 6.5, -lat * s_k, 2.7, 2741 + k * 31 + i)
		var est := StaticBody3D.new()
		est.collision_layer = 1
		est.collision_mask = 0
		est.add_to_group("estrutura")
		base_g.add_child(est)
		ComplexoLancamento.adicionar_colisoes(est, col)
		var suporte := Node3D.new()
		no.add_child(suporte)
		var casa := Transform3D(Basis.looking_at(lat * s_k, Vector3.UP), Vector3(pe.x, topo + 0.4, pe.z))
		suporte.global_transform = casa
		var y := YETI.criar(suporte, 300 + k + i)
		bichos.append({"y": y, "no": suporte, "casa": casa, "estado": "parado", "t0": -100.0, "v": null, "de": casa.origin, "ginga": 0.0})
	_portoes.append({"tipo": "yeti", "i": i, "s": sub.progresso_amostra(i), "comp": 0.0, "fase": 0.0, "c": c, "lat": lat, "tan": -b.z,
		"segura": float(cfg.get("segura_s", 5.0)), "descanso": float(cfg.get("descanso_s", 3.0)), "bichos": bichos, "total": false})


## Teto do carro (onde o yeti senta), no mundo.
func _teto(v: Veiculo) -> Transform3D:
	var cx := v.caixa_corpo
	var xf := v.global_transform
	var topo := xf * Vector3(cx.get_center().x, cx.end.y, cx.get_center().z)
	# Em pé/sentado, olhando para a frente do carro (o modelo olha para +Z; o carro anda para -Z)
	return Transform3D(xf.basis.orthonormalized() * Basis(Vector3.UP, PI), topo + xf.basis.y.normalized() * 0.35 - xf.basis.z.normalized() * 0.2)


func _animar_yetis(g: Dictionary) -> void:
	# Conferência: TSC_YETI_TESTE=1 põe o primeiro yeti no teto do carro do jogador (parado na largada)
	if OS.get_environment("TSC_YETI_TESTE") != "" and g == _primeiro_yeti() and _t > 1.0:
		var yt: Dictionary = g.bichos[0]
		if yt.estado == "parado":
			for no_v in get_tree().get_nodes_in_group("veiculo"):
				var vj := no_v as Veiculo
				if vj and vj.name.contains("KZULO"):
					yt.v = vj
					yt.estado = "agarrado"
					yt.t0 = _t
					vj.yeti(9999.0)
					ultimo_agarrado = vj
	var lat: Vector3 = g.lat
	var tan: Vector3 = g.tan
	var dt := get_physics_process_delta_time()
	for yb: Dictionary in g.bichos:
		var no: Node3D = yb.no
		var dur := _t - float(yb.t0)
		match yb.estado:
			"parado":
				YETI.pose(yb.y, _t, "parado")
				if dur < float(g.descanso):
					continue
				# Carro passando na frente: o mais perto, que não esteja com outro yeti
				var melhor: Veiculo = null
				var dist := INF
				for no_v in get_tree().get_nodes_in_group("veiculo"):
					var v := no_v as Veiculo
					if v == null or v.eliminado or v.fantasma() or v.direcao_invertida() or v.has_meta("yeti") or v.estado != Veiculo.Estado.APOIADO:
						continue
					var q: Vector3 = v.global_position - (g.c as Vector3)
					var ao_longo := q.dot(tan)
					if ao_longo > -6.0 and ao_longo < 2.0 and absf(q.y) < 4.0 and absf(q.dot(lat)) < 9.0:
						var d := (v.global_position - no.global_position).length()
						if d < dist:
							dist = d
							melhor = v
				if melhor:
					melhor.set_meta("yeti", true)   # o outro yeti não pula no mesmo carro
					yb.v = melhor
					yb.estado = "ida"
					yb.t0 = _t
					yb.de = no.global_position
			"ida":
				var v: Veiculo = yb.v
				if v == null or not is_instance_valid(v) or v.eliminado:
					yb.estado = "volta"
					yb.t0 = _t
					yb.de = no.global_position
					continue
				var u := clampf(dur / YETI_SALTO, 0.0, 1.0)
				var alvo := _teto(v)
				var p: Vector3 = (yb.de as Vector3).lerp(alvo.origin, u) + Vector3.UP * 3.5 * 4.0 * u * (1.0 - u)
				var giro := (yb.casa as Transform3D).basis.slerp(alvo.basis.orthonormalized(), smoothstep(0.3, 1.0, u))
				no.global_transform = Transform3D(giro, p)
				YETI.pose(yb.y, _t, "salto", u)
				if u >= 1.0:
					yb.estado = "agarrado"
					yb.t0 = _t
					v.yeti(float(g.segura))
					ultimo_agarrado = v
					if OS.get_environment("TSC_SUB_LOG") != "":
						print("[YETI] pegou %s em %.1f s" % [v.name, _t])
			"agarrado":
				var v: Veiculo = yb.v
				if v == null or not is_instance_valid(v) or v.eliminado or not v.direcao_invertida() or dur >= float(g.segura):
					yb.estado = "volta"
					yb.t0 = _t
					yb.de = no.global_position
					continue
				# Ginga com a curva do carro (velocidade de giro)
				yb.ginga = lerpf(float(yb.ginga), clampf(v.angular_velocity.y * 0.6, -1.0, 1.0), dt * 5.0)
				no.global_transform = _teto(v) * Transform3D(Basis(Vector3.BACK, float(yb.ginga) * 0.25), Vector3.ZERO)
				YETI.pose(yb.y, _t, "agarrado", clampf(dur / 0.25, 0.0, 1.0), float(yb.ginga))
			"volta":
				# Salta do carro para a neve do lado de fora da pista, some numa nuvem de neve e volta para a
				# geleira (de longe, voar de volta parecia um balão)
				var de: Vector3 = yb.de
				if not yb.has("pouso"):
					var ip := sub.indice_estrada(de, 20.0)
					var lat_p: Vector3 = sub.lateral_em(ip) if ip >= 0 else lat
					var centro: Vector3 = sub.amostra(ip) if ip >= 0 else (g.c as Vector3)
					var meia_p := sub.largura_em(ip) * 0.5 if ip >= 0 else 6.0
					var lado := 1.0 if (de - centro).dot(lat_p) >= 0.0 else -1.0
					yb.pouso = de + lat_p * lado * (meia_p + 5.0) + Vector3.DOWN * 1.0
				var pouso: Vector3 = yb.pouso
				var u := clampf(dur / 0.8, 0.0, 1.0)
				var p := de.lerp(pouso, u) + Vector3.UP * 3.0 * 4.0 * u * (1.0 - u)
				no.global_transform = Transform3D(no.global_transform.basis.orthonormalized().slerp((yb.casa as Transform3D).basis, minf(u * 2.0, 1.0)), p)
				YETI.pose(yb.y, _t, "salto", u)
				if u >= 1.0:
					_puf_neve(no, p)
					no.visible = false
					yb.erase("pouso")
					yb.estado = "sumido"
					yb.t0 = _t
					if yb.v != null and is_instance_valid(yb.v):
						(yb.v as Veiculo).remove_meta("yeti")
					yb.v = null
			"sumido":
				if dur >= 1.5:
					no.global_transform = yb.casa
					no.visible = true
					_puf_neve(no, (yb.casa as Transform3D).origin + Vector3.UP * 1.2)
					yb.estado = "parado"
					yb.t0 = _t


## Nuvem de neve rápida (yeti sumindo ou aparecendo).
func _puf_neve(pai: Node3D, p: Vector3) -> void:
	var e := _estouro_neve(self, 1.6)
	e.global_position = p
	e.restart()
	get_tree().create_timer(3.0).timeout.connect(e.queue_free)


# ------------------------------------------------------------------ yetis da plataforma (Frozen Peak)

## Pedido do dono (2026-10-03): na plataforma alta do Frozen Peak não há buracos de fogo — o piso é todo de
## gelo — e yetis em blocos de gelo junto das muralhas jogam bolas de neve nos carros. O carro atingido
## fica `sem_pq_s` segundos sem poder abrir o paraquedas (Veiculo.pq_bloqueado_ate). cfg = {quantidade,
## intervalo_s, alcance, sem_pq_s}.
func _montar_yetis_plataforma(cfg: Dictionary) -> void:
	var r: Recinto = sub.plataforma
	if r == null:
		return
	var no := Node3D.new()
	no.name = "YetisPlataforma"
	add_child(no)
	var meia := r.largura_arena * 0.5
	var lista := []
	var qtd := int(cfg.get("quantidade", 4))
	var pontos := [[r.comprimento * 0.25, -1.0], [r.comprimento * 0.6, 1.0], [r.comprimento * 0.45, -1.0], [r.comprimento * 0.8, -1.0], [r.comprimento * 0.3, 1.0], [r.comprimento * 0.15, 1.0]]
	for k in mini(qtd, pontos.size()):
		var x: float = pontos[k][0]
		# Lados contados a partir da porta (E2 tem a porta do outro lado: sem espelhar, um yeti tampava a entrada)
		var s: float = float(pontos[k][1]) * (float(r.entradas[0][0]) if not r.entradas.is_empty() else 1.0)
		var pe := r.pa(x, s * (meia - 4.0), r.piso_y)
		var bloco := Node3D.new()
		no.add_child(bloco)
		bloco.global_transform = Transform3D(Basis.looking_at(-r.lateral * s, Vector3.UP), Vector3(pe.x, 0.0, pe.z))
		var col := FOCA.geleira(bloco, r.piso_y, r.piso_y + 2.4, 1201 + k)
		var est := StaticBody3D.new()
		est.collision_layer = 1
		est.collision_mask = 0
		est.add_to_group("estrutura")
		bloco.add_child(est)
		ComplexoLancamento.adicionar_colisoes(est, col)
		var suporte := Node3D.new()
		no.add_child(suporte)
		suporte.global_transform = Transform3D(Basis.looking_at(r.lateral * s, Vector3.UP), pe + Vector3.UP * 2.8)
		var y := YETI.criar(suporte, 700 + k)
		(y.raiz as Node3D).scale = Vector3.ONE * 1.35
		var bola := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.55
		sm.height = 1.1
		bola.mesh = sm
		bola.material_override = Gelo.material(Gelo.Mat.NEVE)
		bola.visible = false
		no.add_child(bola)
		lista.append({"y": y, "no": suporte, "bola": bola, "prox": float(k) * 0.9 + 3.0, "voo": {}})
	_portoes.append({"tipo": "yeti_neve", "i": 0, "s": -1.0e9, "comp": 0.0, "fase": 0.0, "bichos": lista, "total": false,
		"intervalo": float(cfg.get("intervalo_s", 3.2)), "alcance": float(cfg.get("alcance", 70.0)), "sem_pq": float(cfg.get("sem_pq_s", 5.0))})


func _animar_yetis_plataforma(g: Dictionary) -> void:
	var dt := get_physics_process_delta_time()
	for yb: Dictionary in g.bichos:
		var no: Node3D = yb.no
		var voo: Dictionary = yb.voo
		var bola: MeshInstance3D = yb.bola
		var raiz: Node3D = yb.y.raiz
		var tau := _t - float(yb.prox)   # segundos em relação à soltura da bola
		var alvo_v := yb.get("alvo") as Veiculo
		if not yb.has("frente0"):
			yb.frente0 = no.global_transform.basis
		# Arremesso inteiro (Yeti.ARREMESSO): escolhe o carro, vira para ele, agacha e junta a neve com as
		# duas mãos, leva a bola para trás da cabeça, joga e acompanha com o corpo
		if OS.get_environment("TSC_YETI_POSE") != "":
			# Conferência: TSC_YETI_POSE="-1.1,-0.4,0" segura cada instante do arremesso por 1 s
			var ts := OS.get_environment("TSC_YETI_POSE").split_floats(",")
			tau = ts[int(_t) % ts.size()]
			yb.prox = _t - tau
			yb.jogando = true
			yb.solta = tau >= 0.0
			bola.visible = tau < 0.0 and tau > -1.3
		var jogando := bool(yb.get("jogando", false))
		if not jogando and tau >= -YETI.ARREMESSO_ANTES and voo.is_empty():
			# Alvo: o carro mais perto dentro do alcance (no chão da plataforma ou voando por cima dela)
			var melhor: Veiculo = null
			var dist := float(g.alcance)
			for no_v in get_tree().get_nodes_in_group("veiculo"):
				var v := no_v as Veiculo
				if v == null or v.eliminado or v.fantasma() or v.travado:
					continue
				var d := v.global_position.distance_to(no.global_position)
				if d < dist:
					dist = d
					melhor = v
			if melhor == null and OS.get_environment("TSC_YETI_JOGA") == "":   # TSC_YETI_JOGA: joga mesmo sem carro (conferir a animação)
				yb.prox = _t + YETI.ARREMESSO_ANTES + 0.4
			else:
				yb.prox = _t + YETI.ARREMESSO_ANTES
				yb.alvo = melhor
				yb.jogando = true
				yb.solta = false
				jogando = true
				alvo_v = melhor
			tau = _t - float(yb.prox)
		var frente: Basis = yb.frente0
		if jogando:
			YETI.pose(yb.y, _t, "arremesso", tau)
			if tau < 0.0 and is_instance_valid(alvo_v):
				var para := alvo_v.global_position + alvo_v.linear_velocity * 0.5 - no.global_position
				para.y = 0.0
				if para.length_squared() > 1.0:
					frente = Basis.looking_at(-para.normalized(), Vector3.UP)
				yb.frente_jogada = frente
			elif yb.has("frente_jogada"):
				frente = yb.frente_jogada
			var mao_d: Vector3 = raiz.global_transform * (yb.y.mao_d as Vector3)
			var mao_e: Vector3 = raiz.global_transform * (yb.y.mao_e as Vector3)
			if not bool(yb.solta):
				if tau >= 0.0:
					# Sai da mão
					var dist_a := 30.0
					var ate := mao_d + no.global_transform.basis.z * 30.0
					var dur := 0.9
					if is_instance_valid(alvo_v) and not alvo_v.eliminado:
						dist_a = alvo_v.global_position.distance_to(mao_d)
						dur = clampf(dist_a / 32.0, 0.5, 1.6)
						ate = alvo_v.global_position + alvo_v.linear_velocity * dur + Vector3.UP * 0.6
					yb.voo = {"de": mao_d, "ate": ate, "t0": _t, "dur": dur, "arco": dist_a * 0.12, "v": alvo_v}
					voo = yb.voo
					yb.solta = true
					bola.scale = Vector3.ONE
				elif tau > -1.3:
					# Na mão: nasce pequena entre as duas mãos, no chão, e vai para a direita
					if not bola.visible:
						bola.visible = true
						_puf_neve(self, (mao_d + mao_e) * 0.5)
					var junta := smoothstep(YETI.ARREMESSO_JUNTA - 0.05, YETI.ARREMESSO_JUNTA + 0.3, tau)
					bola.global_position = ((mao_d + mao_e) * 0.5).lerp(mao_d, junta)
					bola.scale = Vector3.ONE * lerpf(0.25, 1.0, smoothstep(-1.3, YETI.ARREMESSO_JUNTA, tau))
			if tau >= YETI.ARREMESSO_DEPOIS:
				yb.jogando = false
				yb.prox = _t + float(g.intervalo) * randf_range(0.8, 1.25) + YETI.ARREMESSO_ANTES
		else:
			YETI.pose(yb.y, _t, "parado")
		no.global_transform = Transform3D(no.global_transform.basis.slerp(frente, clampf(dt * (7.0 if jogando else 2.5), 0.0, 1.0)).orthonormalized(), no.global_position)
		if voo.is_empty():
			continue
		var u := (_t - float(voo.t0)) / float(voo.dur)
		var p: Vector3 = (voo.de as Vector3).lerp(voo.ate, u) + Vector3.UP * float(voo.arco) * 4.0 * u * (1.0 - u)
		bola.global_position = p
		bola.rotate_x(0.3)
		var v_a := voo.v as Veiculo
		if is_instance_valid(v_a) and not v_a.eliminado and p.distance_to(v_a.global_position) < 2.6:
			v_a.pq_bloqueado_ate = v_a.relogio + float(g.sem_pq)
			if v_a.paraquedas_aberto:
				v_a.fechar_paraquedas()
			if OS.get_environment("TSC_SUB_LOG") != "":
				print("[NEVE] acertou %s em %.1f s" % [v_a.name, _t])
			_puf_neve(self, p)
			bola.visible = false
			yb.voo = {}
		elif u >= 1.0:
			_puf_neve(self, p)
			bola.visible = false
			yb.voo = {}


func _primeiro_yeti() -> Dictionary:
	for g: Dictionary in _portoes:
		if g.tipo == "yeti":
			return g
	return {}
