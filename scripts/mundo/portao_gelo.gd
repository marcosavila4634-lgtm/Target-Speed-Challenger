class_name PortaoGelo
extends Node3D
## Portão de gelo do Frozen Peak (Recinto com tema "gelo": largada e plataforma), pela arte do dono em
## assets/frozen/extruturas/portãofrozen.png ("faça igual"). Tudo em geometria, nada de imagem:
## - de cada lado, um pilar junto da passagem (segura a viga) e uma torre alta em três degraus, feitos
##   de colunas de cristal de alturas diferentes; neve grossa em cada degrau e muitos pingentes;
##   montanhas de cristal nevadas encostadas no pé das torres;
## - viga com o fundo em arco e o nome (placa do recinto) em letras de gelo grandes, serifadas e
##   grossas (Cinzel Black, OFL), nas duas faces, com pingentes embaixo de cada letra;
## - coroa: arco em meia-lua com um maciço de montanhas nevadas dentro, o pico do meio furando o arco;
##   picos menores na viga, dos lados da coroa;
## - rochas grandes com neve e montes de neve no pé; luz ciano saindo das torres;
## - semáforo pendurado embaixo da viga, virado para dentro.
## O gelo (shaders/portao_gelo.gdshader) é partido em blocos por rachaduras brancas, como na arte.
## Coordenadas locais do nó: x = lateral do recinto, y = altura acima do piso, z = para dentro
## (z > 0 é o lado da arena).

const FONTE := "res://assets/fontes/Cinzel.ttf"
const FONTE_RESERVA := "res://assets/fontes/RacingSansOne-Regular.ttf"
const CONDENSA := 0.74   # as letras da arte são altas e estreitas
const ESPACO := 1.08     # e um pouco afastadas

static var _mats := {}

var _r: Recinto
var _rng := RandomNumberGenerator.new()
var _st_cristal := SurfaceTool.new()
var _st_moldura := SurfaceTool.new()
var _st_fundo := SurfaceTool.new()
var _st_pico := SurfaceTool.new()
var _st_neve := SurfaceTool.new()
var _st_rocha := SurfaceTool.new()
var _colisoes: Array[Transform3D] = []
var _fora_no_chao := true


static func montar(r: Recinto) -> void:
	var p: Node3D = load("res://scripts/mundo/portao_gelo.gd").new()
	p.name = "PortaoGelo"
	r.add_child(p)
	p.call("_montar", r)


# ------------------------------------------------------------------ materiais

static func _material(nome: String) -> ShaderMaterial:
	if nome == "geleira":   # geleiras das focas/yetis, túnel de gelo: o gelo de gotejamento novo (pedido do dono)
		return Gelo.material_fenda()
	if _mats.has(nome):
		return _mats[nome]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/portao_gelo.gdshader")
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 311))
	match nome:
		"moldura":   # placa e viga: gelo azul-marinho escuro, poucas rachaduras
			m.set_shader_parameter("cor_rasa", Color(0.1, 0.3, 0.55))
			m.set_shader_parameter("cor_funda", Color(0.01, 0.04, 0.12))
			m.set_shader_parameter("brilho", 0.5)
			m.set_shader_parameter("rachadura", 0.45)
			m.set_shader_parameter("celula", 4.0)
		"letra":     # letreiro (pedido do dono: "muito apagado"): gelo branco-ciano aceso, laterais azul-fundo
			m.set_shader_parameter("cor_rasa", Color(0.97, 1.0, 1.0))
			m.set_shader_parameter("cor_funda", Color(0.8, 0.94, 1.0))
			m.set_shader_parameter("brilho", 2.2)
			m.set_shader_parameter("celula", 1.6)
			m.set_shader_parameter("rachadura", 0.0)
			m.set_shader_parameter("relevo", 0.15)
			m.set_shader_parameter("profundidade", 0.3)
			m.set_shader_parameter("lados", 1.0)
			m.set_shader_parameter("eixo", Vector3(0.0, 0.0, 1.0))
			m.set_shader_parameter("neve_min", 0.6)
		"fundo":     # fundo da coroa
			m.set_shader_parameter("cor_rasa", Color(0.12, 0.42, 0.75))
			m.set_shader_parameter("cor_funda", Color(0.02, 0.07, 0.22))
			m.set_shader_parameter("brilho", 0.7)
			m.set_shader_parameter("rachadura", 0.4)
			m.set_shader_parameter("neve", 0.0)
		"pico":      # montanhas: neve nas encostas, gelo azul-acinzentado nas faces íngremes
			m.set_shader_parameter("cor_rasa", Color(0.45, 0.66, 0.86))
			m.set_shader_parameter("cor_funda", Color(0.08, 0.18, 0.36))
			m.set_shader_parameter("brilho", 0.35)
			m.set_shader_parameter("rachadura", 0.5)
			m.set_shader_parameter("celula", 2.2)
			m.set_shader_parameter("neve_min", 0.3)
		"fenda":     # agulhas de gelo em volta dos alvos (Gelo._montar_pilares), pela arte "fenda de gelo": azul-claro
			# facetado, rachaduras brancas visíveis de longe, neve em toda face que deita
			m.set_shader_parameter("cor_rasa", Color(0.36, 0.82, 1.0))
			m.set_shader_parameter("cor_funda", Color(0.03, 0.27, 0.66))
			m.set_shader_parameter("brilho", 0.5)
			m.set_shader_parameter("celula", 9.0)
			m.set_shader_parameter("rachas_min", 0.7)
			m.set_shader_parameter("geada", 0.32)
			m.set_shader_parameter("mosaico", 0.2)
			m.set_shader_parameter("rachadura", 1.0)
			m.set_shader_parameter("profundidade", 2.5)
			m.set_shader_parameter("relevo", 2.0)
			m.set_shader_parameter("neve_min", 0.2)
			m.set_shader_parameter("longe", 2600.0)
			m.set_shader_parameter("linha_larg", 0.8)
		"bola", "espinho":   # bola do martelo (arte "bola" do dono): cristal azul fundo com rede de fraturas brancas e neve
			m.set_shader_parameter("cor_rasa", Color(0.25, 0.72, 1.0) if nome == "bola" else Color(0.5, 0.86, 1.0))
			m.set_shader_parameter("cor_funda", Color(0.01, 0.14, 0.5) if nome == "bola" else Color(0.06, 0.36, 0.8))
			m.set_shader_parameter("brilho", 1.3)
			m.set_shader_parameter("celula", 1.5 if nome == "bola" else 0.9)
			m.set_shader_parameter("rachadura", 1.3 if nome == "bola" else 0.5)
			m.set_shader_parameter("rachas_min", 1.0)
			m.set_shader_parameter("linha_larg", 1.8)
			m.set_shader_parameter("profundidade", 0.5)
			m.set_shader_parameter("relevo", 1.6)
			m.set_shader_parameter("mosaico", 1.0)
			m.set_shader_parameter("neve_min", 0.72)
			m.set_shader_parameter("local", 1.0)
		"geleira":   # geleira das focas (Foca.geleira): gelo azul-claro como na arte dela
			m.set_shader_parameter("cor_rasa", Color(0.55, 0.86, 1.0))
			m.set_shader_parameter("cor_funda", Color(0.1, 0.4, 0.74))
			m.set_shader_parameter("brilho", 0.6)
			m.set_shader_parameter("celula", 2.2)
	_mats[nome] = m
	return m


static func _fonte() -> Font:
	if _mats.has("fonte"):
		return _mats["fonte"]
	var f: Font = null
	var ff := FontFile.new()
	if ff.load_dynamic_font(FONTE) == OK:
		var fv := FontVariation.new()
		fv.base_font = ff
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): 900}
		fv.variation_embolden = 0.12
		f = fv
	else:
		f = load(FONTE_RESERVA)
	_mats["fonte"] = f
	return f


# ------------------------------------------------------------------ montagem

func _montar(r: Recinto) -> void:
	_r = r
	_rng.seed = 6113 + int(r.piso_y)
	var x := r.comprimento + Recinto.PAREDE * 0.5
	transform = Transform3D(Basis.looking_at(r.frente, Vector3.UP), r.pa(x, 0.0, r.piso_y))
	for st: SurfaceTool in [_st_cristal, _st_moldura, _st_fundo, _st_pico, _st_neve, _st_rocha]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fy := minf(r.chao_y, r.piso_y - 2.0) - 1.0 - r.piso_y   # pé (na plataforma, até o chão)
	_fora_no_chao = r.piso_y - r.chao_y < 2.5
	var g := r.saida_largura * 0.5
	var u_v := g + 9.0                      # a viga vai até dentro das torres
	var arco := 1.5
	var yb := 16.0 + maxf(r.muro_altura + r.grade_altura - 10.0, 0.0)
	var fundo_viga := func(u: float) -> float: return yb + arco * (1.0 - pow(clampf(u / u_v, -1.0, 1.0), 2.0))
	var zv := 1.5

	# Letreiro: mede o nome para dimensionar a viga
	var fonte := _fonte()
	var texto := r.nome_placa.to_upper() if r.nome_placa != "" else "FROZEN PEAK"
	var fs := 64
	var larg_px := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * CONDENSA * ESPACO
	var px := minf((g + 8.0) * 2.0 / maxf(larg_px, 1.0), 5.2 / (fs * 0.7))
	var cap := fs * 0.7 * px
	var yl0 := yb + arco + 0.75
	var yt := yl0 + cap + 0.9
	var yc := yt + 0.45
	var raio := g + 3.6
	var y_torre := yc + raio * 0.95

	_viga(fundo_viga, yt, u_v, zv)
	if r.placa_imagem != "":
		_placa_arte(r.placa_imagem, yb - 0.6, (g + 7.0) * 2.0)
	else:
		_letras(texto, fonte, fs, px, yl0, zv)
		_coroa(yc, raio)
	for s: float in [-1.0, 1.0]:
		_pilar(s, g, fy, fundo_viga)
		_macico(s, g, y_torre)
		for k in 2:
			var u := s * (raio + 0.7 + 0.9 * k)
			var h := _rng.randf_range(3.5, 5.5) * (1.0 - 0.3 * k)
			_prisma(_st_pico, Vector3(u, yt + 0.3, _rng.randf_range(-0.3, 0.3)), Vector3.UP, 5,
				[Vector2(0.0, h * 0.42)], h, 0.2, Vector2(1.0, 0.6))
		_pe(s, g, fy)
	_pingentes_viga(fundo_viga, u_v, yt, zv, g)
	_semaforo(fundo_viga.call(0.0) - 0.4, zv)
	for s: float in [-1.0, 1.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(0.35, 0.8, 1.0)
		l.light_energy = 2.4
		l.omni_range = 13.0
		l.shadow_enabled = false
		l.position = Vector3(s * (g + 7.5), 3.0, 4.2)
		add_child(l)

	# Torres, pilares, pingentes e picos com o gelo de gotejamento dos maciços dos alvos (pedido do dono, 2026-10-04:
	# "faça com as texturas novas"); a viga e o fundo da coroa continuam no gelo escuro, para o letreiro ler
	for par: Array in [[_st_cristal, Gelo.material_fenda()], [_st_moldura, _material("moldura")], [_st_fundo, _material("fundo")],
			[_st_pico, Gelo.material_fenda()], [_st_neve, Gelo.material(Gelo.Mat.NEVE)], [_st_rocha, Gelo.material(Gelo.Mat.ROCHA)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (par[0] as SurfaceTool).commit()
		mi.material_override = par[1]
		add_child(mi)
	# Colisão: tudo que o carro alcança (pedido do dono: nada de enfeite fantasma)
	var no_mundo: Array[Transform3D] = []
	for c in _colisoes:
		no_mundo.append(transform * c)
	ComplexoLancamento.adicionar_colisoes(r.corpo, no_mundo)


# ------------------------------------------------------------------ peças

## Viga: placa de gelo escuro com o fundo em arco, frisos de cristal embaixo e em cima, neve grossa por cima.
func _viga(fundo: Callable, yt: float, u_v: float, zv: float) -> void:
	var n := 32
	for i in n:
		var ua := lerpf(-u_v, u_v, float(i) / n)
		var ub := lerpf(-u_v, u_v, float(i + 1) / n)
		var ya: float = fundo.call(ua)
		var yb2: float = fundo.call(ub)
		_bloco(_st_moldura, ua, ub, ya, yb2, yt, yt, -zv, zv)
		_bloco(_st_cristal, ua, ub, ya - 0.45, yb2 - 0.45, ya + 0.4, yb2 + 0.4, -zv - 0.35, zv + 0.35)
		_bloco(_st_cristal, ua, ub, yt - 0.4, yt - 0.4, yt + 0.4, yt + 0.4, -zv - 0.35, zv + 0.35)
	_faixa_neve(-u_v + 0.3, u_v - 0.3, yt + 0.38, zv + 0.75, 1.0)
	_colisoes.append(Transform3D(Basis.from_scale(Vector3(u_v * 2.0, yt - fundo.call(u_v) + 1.0, (zv + 1.4) * 2.0)),
		Vector3(0.0, (yt + fundo.call(u_v)) * 0.5 + 0.2, 0.0)))


## Letras de gelo extrudadas, uma a uma (leve giro e escala: entalhadas à mão), nas duas faces, com
## pingentes embaixo de cada uma.
func _letras(texto: String, fonte: Font, fs: int, px: float, y0: float, zv: float) -> void:
	var total := fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px * CONDENSA * ESPACO
	var mat := _material("letra").duplicate() as ShaderMaterial
	mat.set_shader_parameter("eixo", global_transform.basis.z.normalized())   # frente da letra no mundo: as laterais ficam escuras
	var prof := 2.3   # a frente passa da frente das torres
	var medida := TextMesh.new()
	medida.font = fonte
	medida.font_size = fs
	medida.pixel_size = px
	medida.text = texto
	medida.depth = prof
	medida.get_mesh_arrays()
	var caixa := medida.get_aabb()
	var base_y := -caixa.position.y
	var meio_z := caixa.position.z + caixa.size.z * 0.5   # a extrusão nem sempre é centrada
	for face: float in [1.0, -1.0]:
		var giro := Basis.IDENTITY if face > 0.0 else Basis(Vector3.UP, PI)
		for k in texto.length():
			var ch := texto.substr(k, 1)
			if ch == " ":
				continue
			var antes := fonte.get_string_size(texto.substr(0, k), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px * CONDENSA * ESPACO
			var larg := fonte.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * px * CONDENSA
			var u := antes + larg * ESPACO * 0.5 - total * 0.5
			var tm := TextMesh.new()
			tm.font = fonte
			tm.font_size = fs
			tm.pixel_size = px
			tm.text = ch
			tm.depth = prof
			tm.curve_step = 0.3
			var mi := MeshInstance3D.new()
			mi.mesh = tm
			mi.material_override = mat
			var esc := _rng.randf_range(0.97, 1.04)
			var b := giro * Basis(Vector3.BACK, deg_to_rad(_rng.randf_range(-2.0, 2.0))) * Basis.from_scale(Vector3(esc * CONDENSA, esc, 1.0))
			var pos := Vector3(u * face, y0 + base_y * esc + _rng.randf_range(-0.05, 0.08), face * (zv + prof * 0.5 - 0.45))   # o fundo da letra entra na placa
			mi.transform = Transform3D(b, pos - b * Vector3(0.0, 0.0, meio_z))
			add_child(mi)
			# Pingentes embaixo da letra
			for j in _rng.randi_range(2, 4):
				var pu := u + _rng.randf_range(-larg * 0.35, larg * 0.35)
				_pingente(Vector3(pu * face, y0 + 0.1, face * (zv + _rng.randf_range(0.3, prof))), _rng.randf_range(0.25, 0.7) if _rng.randf() < 0.7 else _rng.randf_range(0.8, 1.5), 0.08)


## Placa pronta do dono (ex.: Passo do Yeti na etapa 2) no lugar das letras e da coroa: a arte vira malha
## em relevo recortada do fundo (TunelVulcao.montar_arte), nas duas faces, apoiada em cima da viga.
func _placa_arte(caminho: String, y0: float, larg: float) -> void:
	var alt := TunelVulcao.montar_arte(self, caminho, [], [], Vector3.ZERO, Vector3.BACK, larg, y0, true, 1.4)
	if alt <= 0.0:
		return
	_colisoes.append_array(TunelVulcao.colisao_arte(caminho, [], Vector3.ZERO, Vector3.BACK, larg, y0, true, 1.4))


## Coroa: arco em meia-lua de gelo escuro com borda de cristal, fundo azul e um maciço de montanhas nevadas.
func _coroa(yc: float, raio: float) -> void:
	var n := 26
	var esp := 1.3
	var z := 1.0
	for i in n:
		var a0 := PI * float(i) / n
		var a1 := PI * float(i + 1) / n
		var o0 := Vector2(cos(a0), sin(a0))
		var o1 := Vector2(cos(a1), sin(a1))
		for camada: Array in [[raio - esp, raio - 0.35, z, _st_moldura], [raio - 0.4, raio, z + 0.2, _st_cristal]]:
			var ri: float = camada[0]
			var ro: float = camada[1]
			var zz: float = camada[2]
			_hexaedro(camada[3], [Vector3(o0.x * ri, yc + o0.y * ri, -zz), Vector3(o1.x * ri, yc + o1.y * ri, -zz), Vector3(o1.x * ro, yc + o1.y * ro, -zz), Vector3(o0.x * ro, yc + o0.y * ro, -zz),
				Vector3(o0.x * ri, yc + o0.y * ri, zz), Vector3(o1.x * ri, yc + o1.y * ri, zz), Vector3(o1.x * ro, yc + o1.y * ro, zz), Vector3(o0.x * ro, yc + o0.y * ro, zz)])
		var rf := raio - esp + 0.1
		_hexaedro(_st_fundo, [Vector3(o0.x * 0.02, yc, -0.25), Vector3(o1.x * 0.02, yc, -0.25), Vector3(o1.x * rf, yc + o1.y * rf, -0.25), Vector3(o0.x * rf, yc + o0.y * rf, -0.25),
			Vector3(o0.x * 0.02, yc, 0.25), Vector3(o1.x * 0.02, yc, 0.25), Vector3(o1.x * rf, yc + o1.y * rf, 0.25), Vector3(o0.x * rf, yc + o0.y * rf, 0.25)])
		# Pingentes na borda do arco, onde ela já desce
		var a := (a0 + a1) * 0.5
		if absf(cos(a)) > 0.55:
			for face: float in [-1.0, 1.0]:
				_pingente(Vector3(cos(a) * (raio - 0.2), yc + sin(a) * (raio - 0.2) - 0.1, face * (z + 0.05)), _rng.randf_range(0.3, 1.2), 0.08)
	# Maciço: duas fileiras de picos; o do meio fura o arco
	for fila: float in [-0.55, 0.55]:
		var u := -raio + 1.2
		while u < raio - 1.2:
			var teto := sqrt(maxf(raio * raio - u * u, 0.0)) - 0.9
			var h := teto * _rng.randf_range(0.6, 0.95)
			if absf(u) < 1.6:
				h = raio * 1.3
			var rr := clampf(h * 0.42, 1.0, 3.6)
			var inc := Basis(Vector3.BACK, deg_to_rad(_rng.randf_range(-6.0, 6.0)))
			_prisma(_st_pico, Vector3(u, yc - 0.3, fila + _rng.randf_range(-0.2, 0.2)), inc * Vector3.UP, _rng.randi_range(5, 7),
				[Vector2(0.0, rr), Vector2(h * 0.3, rr * 0.68)], h * 0.7, 0.22, Vector2(1.0, 0.45))
			u += _rng.randf_range(1.3, 2.1)
	_colisoes.append(Transform3D(Basis.from_scale(Vector3(raio * 2.0, raio, 2.2)), Vector3(0.0, yc + raio * 0.5, 0.0)))


## Pilar junto da passagem: três colunas de cristal até a viga e um contraforte baixo em cada face,
## com neve e pingentes.
func _pilar(s: float, g: float, fy: float, fundo: Callable) -> void:
	var u0 := g + 0.1
	var u1 := g + 4.3
	var topo: float = fundo.call(s * u1) + 0.4
	_colunas(s, u0, u1, 1.7, fy, topo, 3, 0.0, false)
	for face: float in [-1.0, 1.0]:
		var alto := _rng.randf_range(7.5, 9.0)
		var zc := face * 2.2
		_colunas_z(s, u0 + 0.4, u1 - 0.2, zc, 0.6, fy, alto, 2)
		_almofada(Vector3(s * (u0 + u1 + 0.2) * 0.5, alto, zc), (u1 - u0 - 0.6) * 0.5, 0.68, 1.0)
	_colisoes.append(Transform3D(Basis.from_scale(Vector3(u1 - u0, topo - fy, 6.6)), Vector3(s * (u0 + u1) * 0.5, (topo + fy) * 0.5, 0.0)))


## Maciço de gelo de gotejamento de cada lado (pedido do dono, 2026-10-04, com desenho: as torres retas
## "pareciam canos"): picos altos junto do arco, passando da coroa, descendo em degraus para fora até o
## chão, com picos menores na frente e atrás. O pico colado na passagem é cortado do lado dela. Na
## plataforma (sem chão do lado de fora) o maciço fica do lado de dentro.
func _macico(s: float, g: float, y_torre: float) -> void:
	var dentro := 0.0 if _fora_no_chao else 3.5
	var cortes_z: Array = [] if _fora_no_chao else [[-PI * 0.5, 4.5]]
	var picos: Array = []
	var perfil := [[3.6, -2.6, 1.12, 3.0], [9.4, -2.8, 0.95, 3.2], [14.5, 0.3, 0.7, 4.2], [20.0, -0.6, 0.46, 4.0], [25.0, 0.2, 0.28, 3.4], [29.5, 0.0, 0.15, 2.8]]
	for k in perfil.size():
		var p: Array = perfil[k]
		var cortes := cortes_z.duplicate()
		if k == 0:
			cortes.append([PI if s > 0.0 else 0.0, 3.3])
		picos.append([Vector3(s * (g + float(p[0])), -3.0, float(p[1]) + dentro), y_torre * float(p[2]) * _rng.randf_range(0.94, 1.06) + 3.0, p[3], 0.3, cortes])
	for k in 9:
		var u := _rng.randf_range(12.5, 28.0)
		var z := _rng.randf_range(3.5, 5.5) * (1.0 if k % 2 == 0 or not _fora_no_chao else -1.0)
		var h := y_torre * lerpf(1.0, 0.15, (u - 3.8) / 25.7) * _rng.randf_range(0.22, 0.45)
		picos.append([Vector3(s * (g + u), -3.0, z + dentro), h + 3.0, _rng.randf_range(1.6, 2.6), 0.2, cortes_z])
	var gl := Gelo.new()
	gl.macico(self, picos, 4421 + int(s) * 7 + int(_r.piso_y))
	gl.free()


## Torre em três degraus de colunas de cristal, neve grossa em cada degrau e no topo, montanhas de
## cristal nevadas encostadas no pé.
func _torre(s: float, g: float, fy: float, y_topo: float) -> void:
	var degraus := [[g + 4.3, g + 10.2, 3.2, fy, 14.0], [g + 4.8, g + 9.6, 2.6, 13.4, y_topo - 5.5], [g + 5.5, g + 9.0, 2.1, y_topo - 5.9, y_topo]]
	for d: Array in degraus:
		_colunas(s, float(d[0]), float(d[1]), float(d[2]), float(d[3]), float(d[4]), 2, 1.2, true)
		_colisoes.append(Transform3D(Basis.from_scale(Vector3(float(d[1]) - float(d[0]), float(d[4]) - float(d[3]), float(d[2]) * 2.0)),
			Vector3(s * (float(d[0]) + float(d[1])) * 0.5, (float(d[3]) + float(d[4])) * 0.5, 0.0)))
	# Montanhas de cristal encostadas nas faces do degrau de baixo
	for face: float in [-1.0, 1.0]:
		for k in 2:
			var u := s * (g + 5.8 + 3.0 * k + _rng.randf_range(-0.4, 0.4))
			var h := _rng.randf_range(6.0, 9.5)
			_prisma(_st_pico, Vector3(u, -0.3, face * 3.3), Vector3.UP, 6,
				[Vector2(0.0, 2.2), Vector2(h * 0.3, 1.5)], h * 0.7, 0.2, Vector2(1.0, 0.45), false)


## Colunas de cristal lado a lado entre u0 e u1 (do lado `s`), com alturas sorteadas até `y1`
## (`varia` para baixo) e, com `neve`, neve grossa e pingentes no topo de cada uma.
func _colunas(s: float, u0: float, u1: float, hd: float, y0: float, y1: float, n: int, varia: float, neve: bool) -> void:
	var larg := (u1 - u0) / n
	for k in n:
		var a := u0 + larg * k
		var topo := y1 - _rng.randf_range(0.0, varia)
		var dz := _rng.randf_range(-0.25, 0.25)
		_caixa_cristal(Vector3(s * (a + larg * 0.5), y0, dz), larg * 0.5 + 0.08, hd + _rng.randf_range(-0.15, 0.2), topo - y0)
		if neve:
			_almofada(Vector3(s * (a + larg * 0.5), topo, dz), larg * 0.5 + 0.15, hd + 0.2, 1.2)


## Colunas de um contraforte encostado numa face (centro em z = zc, meia espessura hz).
func _colunas_z(s: float, u0: float, u1: float, zc: float, hz: float, y0: float, y1: float, n: int) -> void:
	var larg := (u1 - u0) / n
	for k in n:
		var a := u0 + larg * k
		_caixa_cristal(Vector3(s * (a + larg * 0.5), y0, zc), larg * 0.5 + 0.05, hz, y1 - y0 - _rng.randf_range(0.0, 0.5))


## Coluna de cristal: prisma de oito faces (caixa com as quinas chanfradas, cantos sorteados), afinando
## um pouco no alto, com o topo levemente inclinado: as faces pegam a luz cada uma de um jeito.
func _caixa_cristal(base: Vector3, hx: float, hz: float, alto: float) -> void:
	var ch := minf(hx, hz) * _rng.randf_range(0.25, 0.5)
	var forma := [Vector2(-hx + ch, -hz), Vector2(hx - ch, -hz), Vector2(hx, -hz + ch), Vector2(hx, hz - ch),
		Vector2(hx - ch, hz), Vector2(-hx + ch, hz), Vector2(-hx, hz - ch), Vector2(-hx, -hz + ch)]
	var incl := Vector2(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.12, 0.12))
	var aneis: Array[PackedVector3Array] = []
	for cima: float in [0.0, 1.0]:
		var f := 1.0 - 0.07 * cima
		var anel := PackedVector3Array()
		for c: Vector2 in forma:
			var q := c * f * _rng.randf_range(0.93, 1.05)
			anel.append(base + Vector3(q.x, (alto + q.x * incl.x + q.y * incl.y) * cima, q.y))
		aneis.append(anel)
	var meio := base + Vector3.UP * alto * 0.5
	var n := forma.size()
	for k in n:
		var k2 := (k + 1) % n
		_tri(_st_cristal, aneis[0][k], aneis[0][k2], aneis[1][k2], meio)
		_tri(_st_cristal, aneis[0][k], aneis[1][k2], aneis[1][k], meio)
		_tri(_st_cristal, aneis[1][k], aneis[1][k2], base + Vector3.UP * alto, meio)
		_tri(_st_cristal, aneis[0][k], aneis[0][k2], base, meio)


## Almofada de neve grossa em cima de um topo retangular (passa da borda), com pingentes em volta.
func _almofada(c: Vector3, hx: float, hz: float, alto: float) -> void:
	var n := 24
	var aneis := [[0.0, 0.97], [alto * 0.3, 1.05], [alto * 0.62, 1.03], [alto * 0.88, 0.86], [alto, 0.55]]
	var pts: Array[PackedVector3Array] = []
	for an: Array in aneis:
		var anel := PackedVector3Array()
		for k in n:
			var t := TAU * float(k) / n
			var cx := signf(cos(t)) * pow(absf(cos(t)), 0.5)
			var cz := signf(sin(t)) * pow(absf(sin(t)), 0.5)
			var calombo := 0.8 + 0.4 * sin(t * 3.0 + c.x) * sin(t * 5.0 + c.z)
			var f: float = float(an[1]) * _rng.randf_range(0.94, 1.06)
			anel.append(c + Vector3(cx * hx * f, float(an[0]) * calombo - (0.3 if float(an[0]) == 0.0 else 0.0) + _rng.randf_range(-0.08, 0.08), cz * hz * f))
		pts.append(anel)
	var centro := c - Vector3.UP * alto
	for i in pts.size() - 1:
		for k in n:
			var k2 := (k + 1) % n
			_tri(_st_neve, pts[i][k], pts[i][k2], pts[i + 1][k2], centro, centro)
			_tri(_st_neve, pts[i][k], pts[i + 1][k2], pts[i + 1][k], centro, centro)
	var topo := c + Vector3.UP * (alto + 0.08)
	var ult := pts[pts.size() - 1]
	for k in n:
		_tri(_st_neve, ult[k], ult[(k + 1) % n], topo, centro, centro)
	# Pingentes na beirada
	for j in int(4.0 * (hx + hz) / 0.32):
		var t := _rng.randf() * TAU
		var cx := signf(cos(t)) * pow(absf(cos(t)), 0.35)
		var cz := signf(sin(t)) * pow(absf(sin(t)), 0.35)
		var l := _rng.randf_range(0.3, 1.2) if _rng.randf() < 0.75 else _rng.randf_range(1.4, 2.8)
		_pingente(c + Vector3(cx * hx * 0.98, -0.15, cz * hz * 0.98), l, 0.06 + l * 0.03)


## Pé: rochas grandes com neve, montes de neve e lascas de cristal. Do lado de fora só se há chão.
func _pe(s: float, g: float, _fy: float) -> void:
	for lado: float in ([1.0, -1.0] if _fora_no_chao else [1.0]):
		for k in 4:
			var u := s * _rng.randf_range(g + 4.5, g + 12.0)
			var z := lado * _rng.randf_range(3.6, 6.0)
			var r := _rng.randf_range(1.5, 2.7)
			var h := r * _rng.randf_range(0.8, 1.15)
			_prisma(_st_rocha, Vector3(u, -0.5, z), Vector3.UP, 7,
				[Vector2(0.0, r), Vector2(h * 0.5, r * 1.08), Vector2(h * 0.9, r * 0.85)], h * 0.12, 0.2, Vector2(1.0, _rng.randf_range(0.7, 0.95)))
			_prisma(_st_neve, Vector3(u, h * 0.62 - 0.5, z), Vector3.UP, 14,
				[Vector2(0.0, r * 0.98), Vector2(h * 0.3, r * 0.9), Vector2(h * 0.48, r * 0.55)], h * 0.1, 0.1, Vector2(1.0, 0.8), true, true)
			_colisoes.append(Transform3D(Basis.from_scale(Vector3(r * 1.9, h * 1.1, r * 1.6)), Vector3(u, h * 0.5 - 0.4, z)))
		# Montes de neve ao longo do pé
		for k in 5:
			var u := s * _rng.randf_range(g + 1.0, g + 12.0)
			var z := lado * _rng.randf_range(2.6, 4.5)
			var r := _rng.randf_range(1.6, 3.0)
			_prisma(_st_neve, Vector3(u, -0.35, z), Vector3.UP, 14,
				[Vector2(0.0, r), Vector2(0.4, r * 0.8), Vector2(0.75, r * 0.45)], 0.15, 0.08, Vector2(1.0, 0.6), true, true)
		# Lascas de cristal saindo do chão
		for k in 3:
			var u := s * _rng.randf_range(g + 1.6, g + 11.0)
			var z := lado * _rng.randf_range(3.0, 4.0)
			var inc := Basis(Vector3.RIGHT, lado * deg_to_rad(_rng.randf_range(10.0, 28.0))) * Basis(Vector3.BACK, -s * deg_to_rad(_rng.randf_range(-12.0, 18.0)))
			var h := _rng.randf_range(1.6, 3.6)
			_prisma(_st_cristal, Vector3(u, -0.3, z), inc * Vector3.UP, _rng.randi_range(5, 6),
				[Vector2(0.0, h * 0.2), Vector2(h * 0.6, h * 0.17)], h * 0.4, 0.12, Vector2.ONE)
			_colisoes.append(Transform3D(inc * Basis.from_scale(Vector3(h * 0.35, h, h * 0.35)), Vector3(u, -0.3, z) + inc * Vector3.UP * h * 0.5))


## Pingentes densos embaixo da viga (os do meio chegam a 5 m) e embaixo do friso de cima.
func _pingentes_viga(fundo: Callable, u_v: float, yt: float, zv: float, g: float) -> void:
	var livre := _r.muro_altura + _r.grade_altura - 0.5   # ponta mais baixa permitida
	for face: float in [1.0, -1.0]:
		var u := -u_v + 0.6
		while u < u_v - 0.6:
			u += _rng.randf_range(0.16, 0.34)
			if face > 0.0 and absf(u) < 4.9:
				continue   # lado de dentro, no meio: semáforo
			var y: float = fundo.call(u) - 0.42
			var l := _rng.randf_range(0.35, 1.6)
			if _rng.randf() < 0.16:
				l = _rng.randf_range(2.0, 3.6) + (1.6 if absf(u) < g + 2.0 else 0.0)
			l = minf(l, y - livre)
			_pingente(Vector3(u, y, face * _rng.randf_range(zv - 0.1, zv + 0.32)), l, 0.07 + l * 0.035)
		u = -u_v + 0.5
		while u < u_v - 0.5:
			u += _rng.randf_range(0.3, 0.7)
			_pingente(Vector3(u, yt, face * (zv + 0.7)), _rng.randf_range(0.2, 0.7), 0.06)


func _semaforo(y_viga: float, zv: float) -> void:
	var y := y_viga - 1.75
	var aco := Gelo.material(Gelo.Mat.ACO)
	var z := zv - 0.1
	Gelo._caixa(self, Vector3(7.6, 2.1, 0.7), Vector3(0.0, y, z), aco)
	for s: float in [-1.0, 1.0]:
		Gelo._caixa(self, Vector3(0.18, 0.75, 0.18), Vector3(s * 3.0, y + 1.4, z), aco)
	var lampada := CylinderMesh.new()
	lampada.top_radius = 0.75
	lampada.bottom_radius = 0.75
	lampada.height = 0.25
	lampada.radial_segments = 24
	for k in 3:
		var l := MeshInstance3D.new()
		l.mesh = lampada
		l.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3((k - 1) * 2.3, y, z + 0.42))
		add_child(l)
		_r.semaforo_lampadas.append(l)
	_colisoes.append(Transform3D(Basis.from_scale(Vector3(7.6, 2.1, 0.8)), Vector3(0.0, y, z)))


# ------------------------------------------------------------------ geometria

## Triângulo com a face virada para fora de `dentro` (Godot: frente em sentido horário).
## Normal plana (cristal lapidado) ou, com `centro` finito, lisa: do centro para o vértice (neve).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, dentro: Vector3, centro := Vector3.INF) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	if n.dot((a + b + c) / 3.0 - dentro) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	for v: Vector3 in [a, c, b]:
		st.set_normal(n if centro == Vector3.INF else ((v - centro).normalized() + n * 0.35).normalized())
		st.add_vertex(v)


## Prisma irregular ao longo de `eixo`: anéis [altura, raio] com raio e ângulo sorteados por vértice,
## ponta (pirâmide) ou topo cortado, `esc` achata as direções de lado (x) e de fundo (z).
func _prisma(st: SurfaceTool, base: Vector3, eixo: Vector3, lados: int, aneis: Array, ponta: float, jit: float,
		esc := Vector2.ONE, tampa_base := true, suave := false) -> void:
	eixo = eixo.normalized()
	var ref := Vector3.BACK if absf(eixo.z) < 0.9 else Vector3.RIGHT
	var e1 := ref.cross(eixo).normalized()
	var e2 := eixo.cross(e1).normalized()
	if absf(e1.x) < absf(e2.x):
		var t := e1
		e1 = e2
		e2 = t
	var fase := _rng.randf() * TAU
	var angs := PackedFloat32Array()
	for k in lados:
		angs.append(fase + TAU * (float(k) + _rng.randf_range(-0.3, 0.3)) / lados)
	var pts: Array[PackedVector3Array] = []
	for an: Vector2 in aneis:
		var anel := PackedVector3Array()
		for k in lados:
			var rr := an.y * (1.0 + _rng.randf_range(-jit, jit))
			anel.append(base + eixo * an.x + (e1 * cos(angs[k]) * esc.x + e2 * sin(angs[k]) * esc.y) * rr)
		pts.append(anel)
	var h_fim: float = (aneis[aneis.size() - 1] as Vector2).x
	var centro := base + eixo * (h_fim * 0.25) if suave else Vector3.INF
	for i in pts.size() - 1:
		var dentro := base + eixo * (((aneis[i] as Vector2).x + (aneis[i + 1] as Vector2).x) * 0.5)
		for k in lados:
			var k2 := (k + 1) % lados
			_tri(st, pts[i][k], pts[i][k2], pts[i + 1][k2], dentro, centro)
			_tri(st, pts[i][k], pts[i + 1][k2], pts[i + 1][k], dentro, centro)
	var ult := pts[pts.size() - 1]
	if ponta > 0.0:
		var r_fim: float = (aneis[aneis.size() - 1] as Vector2).y
		var topo := base + eixo * (h_fim + ponta) + (e1 * _rng.randf_range(-1.0, 1.0) + e2 * _rng.randf_range(-1.0, 1.0)) * r_fim * 0.12
		for k in lados:
			_tri(st, ult[k], ult[(k + 1) % lados], topo, base + eixo * h_fim, centro)
	else:
		var meio := base + eixo * h_fim
		for k in lados:
			_tri(st, ult[k], ult[(k + 1) % lados], meio, meio - eixo, centro)
	if tampa_base:
		var b0 := base + eixo * (aneis[0] as Vector2).x
		for k in lados:
			_tri(st, pts[0][k], pts[0][(k + 1) % lados], b0, b0 + eixo, centro)


## Pingente: cone de gelo de 5 faces pendurado em `topo`.
func _pingente(topo: Vector3, comp: float, r: float) -> void:
	if comp < 0.1:
		return
	_prisma(_st_cristal, topo, Vector3.DOWN, 5, [Vector2(0.0, r), Vector2(comp * 0.4, r * 0.55)], comp * 0.6, 0.15, Vector2.ONE, false)


## Bloco entre u0 e u1 com fundo e topo próprios em cada ponta (segmento de viga).
func _bloco(st: SurfaceTool, u0: float, u1: float, yb0: float, yb1: float, yt0: float, yt1: float, z0: float, z1: float) -> void:
	_hexaedro(st, [Vector3(u0, yb0, z0), Vector3(u1, yb1, z0), Vector3(u1, yt1, z0), Vector3(u0, yt0, z0),
		Vector3(u0, yb0, z1), Vector3(u1, yb1, z1), Vector3(u1, yt1, z1), Vector3(u0, yt0, z1)])


## Hexaedro: 4 cantos de trás (z0) e os 4 correspondentes da frente, na mesma ordem.
func _hexaedro(st: SurfaceTool, p: Array) -> void:
	var c := Vector3.ZERO
	for v: Vector3 in p:
		c += v
	c /= 8.0
	for f: Array in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		_tri(st, p[f[0]], p[f[1]], p[f[2]], c)
		_tri(st, p[f[0]], p[f[2]], p[f[3]], c)


## Faixa de neve fofa por cima da viga (seção em meia elipse com calombos, passando da borda).
func _faixa_neve(u0: float, u1: float, y0: float, meia: float, alto: float) -> void:
	var n := 40
	var m := 9
	var secoes: Array[PackedVector3Array] = []
	for i in n + 1:
		var u := lerpf(u0, u1, float(i) / n)
		var calombo := 0.75 + 0.5 * _rng.randf()
		var sec := PackedVector3Array()
		for j in m:
			var t := PI * float(j) / (m - 1)
			var zz := cos(t) * meia * (1.0 + _rng.randf_range(-0.06, 0.06))
			var yy := y0 + sin(t) * alto * calombo - (0.18 if j == 0 or j == m - 1 else 0.0)
			sec.append(Vector3(u, yy, zz))
		secoes.append(sec)
	for i in n:
		var centro := Vector3(lerpf(u0, u1, (i + 0.5) / n), y0 - alto, 0.0)
		for j in m - 1:
			_tri(_st_neve, secoes[i][j], secoes[i + 1][j], secoes[i + 1][j + 1], centro, centro)
			_tri(_st_neve, secoes[i][j], secoes[i + 1][j + 1], secoes[i][j + 1], centro, centro)
	for i: int in [0, n]:
		var lado := Vector3(u0 - 1.0 if i == 0 else u1 + 1.0, y0, 0.0)
		var meio := Vector3(secoes[i][0].x, y0 + alto * 0.3, 0.0)
		for j in m - 1:
			_tri(_st_neve, secoes[i][j], secoes[i][j + 1], meio, meio * 2.0 - lado, lado)
