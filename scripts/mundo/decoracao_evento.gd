class_name DecoracaoEvento
extends Node3D
## Ambientação de evento em volta de um complexo de lançamento (só visual, com colisão simples):
## torres de holofotes, bandeiras ao vento, banners, painel gigante de chevrons no paredão,
## telão, área de apoio da equipe (containers, tenda, cavaletes) e cabine de narração.

const COR_ACO := Color(0.13, 0.135, 0.15)

var cx: ComplexoLancamento
var terreno: Terreno
var cor := Color.WHITE
var _corpo: StaticBody3D
var _aco: Array[Transform3D] = []
var _colisoes: Array[Transform3D] = []
var _mat_aco: StandardMaterial3D


func montar(complexo: ComplexoLancamento, p_terreno: Terreno) -> void:
	cx = complexo
	terreno = p_terreno
	cor = cx.cor
	_mat_aco = ComplexoLancamento._material_metal(COR_ACO, 0.8, 0.4)
	_corpo = StaticBody3D.new()
	_corpo.name = "Colisoes"
	_corpo.collision_layer = 1
	_corpo.collision_mask = 0
	_corpo.add_to_group("estrutura")
	add_child(_corpo)

	var x_borda := cx.perfil.pontos[cx.perfil.indice_borda].x
	var meia := cx.largura * 0.5
	for lado: float in [-1.0, 1.0]:
		_torre_holofotes(8.0, meia + 16.0, lado)
		_torre_holofotes(x_borda - 14.0, meia + 16.0, lado)
		for k in 4:
			_mastro_bandeira(10.0 + k * 15.0, meia + 6.0, lado, k * 1.3 + lado)
		_banner(24.0, meia + 10.0, lado, "CANYON RUSH")
		_banner(44.0, meia + 10.0, lado, "TARGET FLIGHT")
	_cabine_narracao(30.0, meia + 22.0, 1.0)
	_painel_paredao(x_borda)
	_area_apoio()

	ComplexoLancamento.criar_multimesh(self, _aco, _mat_aco)
	ComplexoLancamento.adicionar_colisoes(_corpo, _colisoes)


## Ponto no chão da mesa: x do perfil (0 = início da plataforma) e deslocamento lateral.
func _chao(x: float, desloc: float) -> Vector3:
	var p := cx.ponto(x, 0.0) + cx.lateral * desloc
	p.y = terreno.altura_em(p.x, p.z)
	return p


## Base voltada para `alvo_dir` com +Z apontando para ele (QuadMesh é visível pelo +Z).
static func _virada_para(alvo_dir: Vector3) -> Basis:
	return Basis.looking_at(-alvo_dir, Vector3.UP)


func _painel(tamanho: Vector2, t: Transform3D, params: Dictionary) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = tamanho
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/painel_equipe.gdshader")
	mat.set_shader_parameter("cor_equipe", cor)
	mat.set_shader_parameter("proporcao", tamanho.x / tamanho.y)
	for k in params:
		mat.set_shader_parameter(k, params[k])
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.transform = t
	add_child(mi)
	# Verso escuro para não ficar oco visto de trás
	var verso := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(tamanho.x, tamanho.y, 0.2)
	verso.mesh = bm
	verso.material_override = _mat_aco
	verso.transform = t * Transform3D(Basis.IDENTITY, Vector3(0, 0, -0.12))
	add_child(verso)
	return mi


func _texto(texto: String, t: Transform3D, tamanho_px: int, pixel: float, cor_texto := Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = texto
	l.font_size = tamanho_px
	l.pixel_size = pixel
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.6)
	l.modulate = cor_texto
	l.double_sided = false
	l.transform = t
	add_child(l)
	return l


# ------------------------------------------------------------------ holofotes

func _torre_holofotes(x: float, desloc: float, lado: float) -> void:
	var base := _chao(x, desloc * lado)
	var altura := 30.0
	var topo := base + Vector3.UP * altura
	_aco.append_array(ComplexoLancamento.trelica(base, topo, 2.0, 2.5, 0.28, 0.1))
	_colisoes.append(ComplexoLancamento._viga(base, topo, 2.0))
	# Cabeça com 3 x 2 refletores, virada para o centro da plataforma
	var mira := cx.ponto(x + 10.0, cx.perfil.pontos[0].y) - topo
	var b := _virada_para(Vector3(mira.x, 0.0, mira.z).normalized())
	var inclinada := b * Basis(Vector3.RIGHT, -0.35)
	var centro := topo + Vector3.UP * 2.0
	_aco.append(Transform3D(inclinada * Basis.from_scale(Vector3(6.4, 4.2, 0.5)), centro - inclinada.z * 0.35))
	_aco.append(ComplexoLancamento._viga(topo, centro - inclinada.z * 0.6, 0.5))
	var lampadas: Array[Transform3D] = []
	for i in 3:
		for j in 2:
			var p := centro + inclinada.x * (i - 1) * 2.0 + inclinada.y * (j - 0.5) * 1.9
			lampadas.append(Transform3D(inclinada * Basis.from_scale(Vector3(1.7, 1.5, 0.25)), p))
	ComplexoLancamento.criar_multimesh(self, lampadas, ComplexoLancamento._material_luz(Color(1.0, 0.93, 0.8), 9.0), false)
	var luz := SpotLight3D.new()
	luz.light_color = Color(1.0, 0.9, 0.75)
	luz.light_energy = 4.0
	luz.spot_range = 110.0
	luz.spot_angle = 32.0
	luz.spot_attenuation = 0.6
	luz.shadow_enabled = false
	luz.transform = Transform3D(Basis.looking_at(mira.normalized(), Vector3.UP), centro + inclinada.z * 0.5)
	add_child(luz)


# ------------------------------------------------------------------ bandeiras e banners

func _mastro_bandeira(x: float, desloc: float, lado: float, fase: float) -> void:
	var base := _chao(x, desloc * lado)
	base.y = maxf(base.y, cx.perfil.pontos[0].y - 6.0)
	var altura := cx.perfil.pontos[0].y + 14.0 - base.y
	var mastro := ComplexoLancamento._viga(base, base + Vector3.UP * altura, 0.3)
	_aco.append(mastro)
	_colisoes.append(mastro)
	var q := QuadMesh.new()
	q.size = Vector2(5.0, 2.8)
	q.subdivide_width = 20
	q.subdivide_depth = 6
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bandeira.gdshader")
	mat.set_shader_parameter("cor_equipe", cor)
	mat.set_shader_parameter("fase", fase)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	# Todas as bandeiras do mapa apontam para o mesmo vento
	var vento := Vector3(0.85, 0.0, 0.53).normalized()
	var b := Basis(vento, Vector3.UP, vento.cross(Vector3.UP))
	mi.transform = Transform3D(b, base + Vector3.UP * (altura - 1.8) + vento * 2.6)
	mi.extra_cull_margin = 2.0
	add_child(mi)


func _banner(x: float, desloc: float, lado: float, texto: String) -> void:
	var base := _chao(x, desloc * lado)
	var tamanho := Vector2(3.4, 12.0)
	var b := _virada_para(-cx.lateral * lado)
	var centro := base + Vector3.UP * (tamanho.y * 0.5 + 1.5)
	for s: float in [-1.0, 1.0]:
		var p := base + b.x * (tamanho.x * 0.5 + 0.25) * s
		var poste := ComplexoLancamento._viga(p, p + Vector3.UP * (tamanho.y + 2.2), 0.3)
		_aco.append(poste)
		_colisoes.append(poste)
	_aco.append(ComplexoLancamento._viga(centro + Vector3.UP * (tamanho.y * 0.5 + 0.35) - b.x * 2.1, centro + Vector3.UP * (tamanho.y * 0.5 + 0.35) + b.x * 2.1, 0.25))
	_painel(tamanho, Transform3D(b, centro), {"faixa_ini": 0.66, "faixa_fim": 0.95, "chevrons": 4.0, "energia": 2.2})
	_colisoes.append(Transform3D(b * Basis.from_scale(Vector3(tamanho.x, tamanho.y, 0.3)), centro))
	_texto("TSC", Transform3D(b, centro + Vector3.UP * 4.8 + b.z * 0.03), 256, 0.0055)
	var vertical := b * Basis(Vector3.BACK, PI * 0.5)
	_texto(texto, Transform3D(vertical, centro + Vector3.UP * 0.2 + b.z * 0.03), 128, 0.0068, Color(0.92, 0.95, 1.0))


## Painel gigante com chevrons descendo, preso no paredão abaixo da borda e virado para o alvo.
func _painel_paredao(x_borda: float) -> void:
	var x := x_borda + 7.0
	var topo_y := cx.perfil.pontos[0].y - 4.0
	var largura := cx.largura + 6.0
	var chao := -INF
	for k in 5:
		var p := _chao(x, lerpf(-largura * 0.5, largura * 0.5, k / 4.0))
		chao = maxf(chao, p.y)
	var altura := minf(topo_y - (chao + 2.0), 60.0)
	if altura < 14.0:
		return
	var b := _virada_para(cx.frente)
	var centro := cx.ponto(x, topo_y - altura * 0.5)
	_painel(Vector2(largura, altura), Transform3D(b, centro), {"chevrons": altura / 9.0, "faixa_ini": 0.04, "faixa_fim": 0.96, "energia": 3.0, "moldura": 0.015, "velocidade": 0.6})
	_colisoes.append(Transform3D(b * Basis.from_scale(Vector3(largura, altura, 0.4)), centro))
	# Pilares de treliça dos dois lados, do chão até o topo
	for s: float in [-1.0, 1.0]:
		var p := centro + b.x * (largura * 0.5 + 0.9) * s - b.z * 0.6
		var pe := Vector3(p.x, chao - 4.0, p.z)
		_aco.append_array(ComplexoLancamento.trelica(pe, Vector3(p.x, topo_y + 1.0, p.z), 1.4, 2.5, 0.25, 0.09))
		_colisoes.append(ComplexoLancamento._viga(pe, Vector3(p.x, topo_y + 1.0, p.z), 1.4))


# ------------------------------------------------------------------ área de apoio atrás da largada

func _area_apoio() -> void:
	# Telão atrás da largada, virado para a pista
	var base := _chao(-10.0, 0.0)
	var b := _virada_para(cx.frente)
	var tam := Vector2(20.0, 8.0)
	var centro := base + Vector3.UP * (tam.y * 0.5 + 9.0)
	for s: float in [-1.0, 1.0]:
		var p := base + b.x * (tam.x * 0.5 - 1.0) * s
		_aco.append_array(ComplexoLancamento.trelica(p, p + Vector3.UP * (tam.y + 9.5), 1.2, 1.8, 0.2, 0.08))
		_colisoes.append(ComplexoLancamento._viga(p, p + Vector3.UP * (tam.y + 9.5), 1.2))
	_painel(tam, Transform3D(b, centro), {"faixa_ini": 0.72, "faixa_fim": 0.94, "chevrons": 2.0, "energia": 2.5, "moldura": 0.012})
	_colisoes.append(Transform3D(b * Basis.from_scale(Vector3(tam.x, tam.y, 0.4)), centro))
	_texto("TARGET SPEED CHALLENGER", Transform3D(b, centro + Vector3.UP * 2.2 + b.z * 0.03), 160, 0.009)
	_texto("EQUIPE " + str(Config.EQUIPES[cx.indice_equipe].nome), Transform3D(b, centro + Vector3.UP * 0.1 + b.z * 0.03), 200, 0.012, cor.lightened(0.45))

	# Containers (dois empilhados e um solto) nas cores da equipe e cinza
	var cores := [cor.darkened(0.25), Color(0.55, 0.56, 0.58), Color(0.62, 0.3, 0.12)]
	var dados := [[-26.0, -18.0, 0.0, 0], [-26.0, -18.0, 2.6, 1], [-42.0, -17.0, 0.0, 2], [-30.0, 20.0, 0.0, 1]]
	for d: Array in dados:
		var p := _chao(d[0], d[1])
		var bc := Basis.looking_at(cx.frente, Vector3.UP)
		var t := Transform3D(bc * Basis.from_scale(Vector3(2.44, 2.6, 12.2)), p + Vector3.UP * (1.3 + d[2]))
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		mi.material_override = _material_container(cores[d[3]])
		mi.transform = t
		add_child(mi)
		_colisoes.append(t)

	# Tenda da equipe
	var pt := _chao(-34.0, 4.0)
	var bt := Basis.looking_at(cx.frente, Vector3.UP)
	for i in 4:
		var canto := pt + bt.x * (3.0 if i % 2 == 0 else -3.0) + bt.z * (3.0 if i < 2 else -3.0)
		_aco.append(ComplexoLancamento._viga(canto, canto + Vector3.UP * 3.0, 0.14))
	var teto := MeshInstance3D.new()
	var prisma := PrismMesh.new()
	prisma.size = Vector3(6.4, 1.6, 6.4)
	teto.mesh = prisma
	teto.material_override = ComplexoLancamento._material_metal(cor, 0.0, 0.8)
	teto.transform = Transform3D(bt, pt + Vector3.UP * 3.8)
	add_child(teto)
	_texto("TSC", Transform3D(bt.rotated(Vector3.UP, PI), pt + Vector3.UP * 3.4 + bt.z * 3.25), 160, 0.008)

	# Cavaletes zebrados fechando o fundo da área
	var cav: Array[Transform3D] = []
	var cav_esc: Array[Transform3D] = []
	for k in 16:
		var p := _chao(-52.0, (k - 7.5) * 2.2)
		var t := Transform3D(Basis.looking_at(cx.lateral, Vector3.UP) * Basis.from_scale(Vector3(0.5, 1.0, 2.0)), p + Vector3.UP * 0.5)
		(cav if k % 2 == 0 else cav_esc).append(t)
	ComplexoLancamento.criar_multimesh(self, cav, ComplexoLancamento._material_metal(Color(0.9, 0.9, 0.88), 0.0, 0.7))
	ComplexoLancamento.criar_multimesh(self, cav_esc, ComplexoLancamento._material_metal(Color(0.75, 0.1, 0.08), 0.0, 0.7))


func _material_container(c: Color) -> StandardMaterial3D:
	var m := ComplexoLancamento._material_metal(c, 0.4, 0.6)
	return m


## Andaime com cabine de narração no topo, ao lado da plataforma.
func _cabine_narracao(x: float, desloc: float, lado: float) -> void:
	var base := _chao(x, desloc * lado)
	var topo_y := cx.perfil.pontos[0].y + 6.0
	var b := _virada_para(-cx.lateral * lado)
	var meio := 2.5
	var cantos := []
	for i in 4:
		cantos.append(b.x * (meio if i % 2 == 0 else -meio) + b.z * (meio if i < 2 else -meio))
	for c: Vector3 in cantos:
		_aco.append(ComplexoLancamento._viga(base + c, Vector3(base.x + c.x, topo_y, base.z + c.z), 0.2))
	var y := base.y + 2.0
	while y < topo_y:
		for par: Array in [[0, 1], [1, 3], [3, 2], [2, 0]]:
			var a: Vector3 = cantos[par[0]]
			var c: Vector3 = cantos[par[1]]
			_aco.append(ComplexoLancamento._viga(Vector3(base.x + a.x, y, base.z + a.z), Vector3(base.x + c.x, y, base.z + c.z), 0.12))
		# Escada em zigue-zague numa das faces
		var e0: Vector3 = cantos[2]
		var e1: Vector3 = cantos[3]
		var subindo := int((y - base.y) / 2.0) % 2 == 0
		var de := e0 if subindo else e1
		var ate := e1 if subindo else e0
		_aco.append(ComplexoLancamento._viga(Vector3(base.x + de.x, y, base.z + de.z) - b.z * 0.6, Vector3(base.x + ate.x, y + 2.0, base.z + ate.z) - b.z * 0.6, 0.35))
		y += 2.0
	_colisoes.append(ComplexoLancamento._viga(base, Vector3(base.x, topo_y, base.z), meio * 2.0))
	# Cabine envidraçada
	var cabine := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(meio * 2.4, 3.0, meio * 2.4)
	cabine.mesh = bm
	var vidro := ComplexoLancamento._material_metal(Color(0.1, 0.16, 0.22), 0.9, 0.08)
	cabine.material_override = vidro
	cabine.transform = Transform3D(b, Vector3(base.x, topo_y + 1.5, base.z))
	add_child(cabine)
	_aco.append(Transform3D(b * Basis.from_scale(Vector3(meio * 2.6, 0.3, meio * 2.6)), Vector3(base.x, topo_y + 3.15, base.z)))
	_colisoes.append(cabine.transform * Transform3D(Basis.from_scale(bm.size), Vector3.ZERO))
	var faixa := ComplexoLancamento._material_luz(cor, 2.5)
	var f := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(meio * 2.45, 0.25, meio * 2.45)
	f.mesh = fm
	f.material_override = faixa
	f.transform = Transform3D(b, Vector3(base.x, topo_y + 2.9, base.z))
	add_child(f)
