class_name TunelAtalho
extends Node3D
## Túnel-atalho do Climb to Death (desenho do dono, etapa 2): quem vem de paraquedas entra voando
## pelo buraco na montanha (a estrada só começa lá dentro), atravessa por dentro e sai numa rampa já
## perto do alvo. Difícil de encaixar: bater na boca, nas paredes, no teto ou cair da estrada
## (que fica acima do piso) explode o carro — essas peças ficam no grupo "mortal".
## O terreno é cavado ao longo do túnel (Terreno._cavar_tunel); aqui ficam o tubo, as molduras das
## bocas e a capa de rocha que refaz a encosta natural por cima da vala (_Manto).

const LAMPADAS_A_CADA := 10.0


func montar(cfg: Dictionary, terreno: Terreno, complexo: ComplexoLancamento) -> void:
	name = "TunelAtalho"
	var e2 := Vector2(float(cfg.entrada[0]), float(cfg.entrada[1]))
	var s2 := Vector2(float(cfg.saida[0]), float(cfg.saida[1]))
	var li := float(cfg.get("largura_interna", 12))
	var ai := float(cfg.get("altura_interna", 9))
	var le := float(cfg.get("largura_estrada", 7))
	var ae := float(cfg.get("altura_estrada", 2.5))
	var dir_h := Vector3(s2.x - e2.x, 0.0, s2.y - e2.y).normalized()
	var lado := dir_h.cross(Vector3.UP).normalized()
	var teto_y := ai - ae   # topo da abóbada acima da estrada
	var sec := _Secao.new(li * 0.5, -ae, float(cfg.get("altura_parede", 1.0)), teto_y)

	# ---- Bocas na encosta: entrada/saída do json são aproximadas; cada boca vai para onde a
	# encosta natural passa acima do arco (a boca fica rente à face, sem nada saindo para fora)
	var man := _Manto.new(terreno, Vector3(e2.x, 0.0, e2.y), dir_h, lado, e2.distance_to(s2),
		float(cfg.altura_entrada), float(cfg.altura_saida), sec)
	var entrada := man.ponto(man.t_ini)
	var saida := man.ponto(man.t_fim)

	var estrada: Array[Transform3D] = []   # estrada (não mortal)
	var pilares: Array[Transform3D] = []
	var tubo: Array[Transform3D] = []      # piso, paredes e teto (mortais)
	var luzes: Array[Transform3D] = []

	# ---- Tubo (acompanha a descida da boca até a saída)
	var eixo := saida - entrada
	var comp := eixo.length()
	var b := Basis.looking_at(eixo / comp, Vector3.UP)
	var meio := (entrada + saida) * 0.5
	var caixa := func(tamanho: Vector3, local: Vector3) -> Transform3D:
		return Transform3D(b * Basis.from_scale(tamanho), meio + b * local)
	estrada.append(caixa.call(Vector3(le, 0.6, comp), Vector3(0.0, -0.3, 0.0)))
	# Colisão do tubo em arco (piso, paredes retas e a abóbada em gomos); o visual é a malha de rocha
	tubo.append(caixa.call(Vector3(li + 2.0, 1.0, comp), Vector3(0.0, sec.piso - 0.5, 0.0)))
	for s: float in [-1.0, 1.0]:
		var alt_parede := sec.ombro - sec.piso
		tubo.append(caixa.call(Vector3(1.0, alt_parede + 0.5, comp), Vector3(s * (sec.meia + 0.5), sec.piso + alt_parede * 0.5, 0.0)))
	const GOMOS := 10
	for k in GOMOS:
		var p0 := sec.arco(float(k) / GOMOS)
		var p1 := sec.arco(float(k + 1) / GOMOS)
		var m := (p0 + p1) * 0.5
		var corda := p1 - p0
		var fora := Vector2(corda.y, -corda.x).normalized()
		if fora.dot(m - Vector2(0.0, sec.ombro)) < 0.0:
			fora = -fora
		var bx := Vector3(corda.x, corda.y, 0.0).normalized()
		var by := Vector3(fora.x, fora.y, 0.0)
		var bl := Basis(bx, by, bx.cross(by))
		var c3 := Vector3(m.x + fora.x * 0.5, m.y + fora.y * 0.5, 0.0)
		tubo.append(Transform3D(b * bl * Basis.from_scale(Vector3(corda.length() + 0.4, 1.0, comp)), meio + b * c3))
	var z := -comp * 0.5 + 4.0
	while z < comp * 0.5:
		pilares.append(caixa.call(Vector3(0.5, ae, 0.5), Vector3(0.0, -ae * 0.5 - 0.6, z)))
		for s: float in [-1.0, 1.0]:
			var x := s * sec.meia * 0.42
			luzes.append(caixa.call(Vector3(0.25, 0.15, 2.2), Vector3(x, sec.altura_em(x) - 0.45, z)))
		z += LAMPADAS_A_CADA
	var semente := int(absf(entrada.x * 13.0 + entrada.z * 7.0))
	var rocha_tubo := _malha_tubo(sec, entrada, b, comp, semente)

	# ---- Rampa na saída (pedido do dono: do lado de fora da montanha só existe a rampa; na entrada
	# não há estrada, só o buraco — a estrada começa dentro)
	var bh := Basis.looking_at(dir_h, Vector3.UP)
	var rampa := float(cfg.get("rampa_saida", 30))
	var ang := deg_to_rad(float(cfg.get("rampa_graus", 14)))
	var dir_r := (dir_h * cos(ang) + Vector3.UP * sin(ang)).normalized()
	var br := Basis.looking_at(dir_r, Vector3.UP)
	estrada.append(Transform3D(br * Basis.from_scale(Vector3(le + 1.0, 0.8, rampa)), saida + dir_r * rampa * 0.5 - br.y * 0.4))
	# Pilares até o chão e lâmpadas nas bordas da rampa
	var d := 4.0
	while d <= rampa:
		var p := saida + dir_r * d
		var chao := maxf(terreno.altura_em(p.x, p.z), man.altura(man.t_fim + d * cos(ang), 0.0))
		if p.y - 0.8 - chao > 1.0:
			pilares.append(Transform3D(bh * Basis.from_scale(Vector3(1.4, p.y - 0.8 - chao, 1.4)), Vector3(p.x, (p.y - 0.8 + chao) * 0.5, p.z)))
		for s: float in [-1.0, 1.0]:
			luzes.append(Transform3D(br * Basis.from_scale(Vector3(0.3, 0.3, 0.8)), p + lado * s * (le * 0.5 + 0.3) + Vector3.UP * 0.15))
		d += 6.0

	# ---- Capa de rocha: a encosta natural por cima da vala do túnel (no lugar de blocos retos), com
	# o furo das bocas e um recorte na face diante de cada uma
	var capa := man.malha()
	# Moldura em arco rente à face em cada boca (fecha os cantos entre o arco e a capa)
	# (a capa fecha rente ao arco, então a moldura só vai até pouco acima dele)
	var placas: Array[Mesh] = []
	for boca: Vector3 in [entrada, saida]:
		var para_fora := -dir_h if boca == entrada else dir_h
		placas.append(_malha_boca(sec, boca + para_fora * 0.4, lado, para_fora, sec.topo + 2.2, sec.piso - 2.0, semente + placas.size()))

	# ---- Entrada: 2 m de estrada para fora da boca e portal de metal com placa "TÚNEL"
	# (pedido do dono: de longe o buraco na encosta não aparecia)
	estrada.append(Transform3D(bh * Basis.from_scale(Vector3(le, 0.6, 2.4)), entrada - dir_h * 1.0 + Vector3.DOWN * 0.3))
	var portal := _portal(sec, entrada - dir_h * 0.9, bh)
	tubo.append_array(portal.colisao)

	# ---- Visual e colisão
	var mat_rocha: Material = terreno._mat_terreno
	ComplexoLancamento.criar_multimesh(self, estrada, _material_asfalto())
	ComplexoLancamento.criar_multimesh(self, pilares, complexo.material_concreto(0.0))
	var mat_dentro := ShaderMaterial.new()
	mat_dentro.shader = load("res://shaders/rocha_tunel.gdshader")
	mat_dentro.set_shader_parameter("ruido", mat_rocha.get_shader_parameter("ruido"))
	mat_dentro.set_shader_parameter("ruido_fino", mat_rocha.get_shader_parameter("ruido_fino"))
	for malha: Mesh in [rocha_tubo, capa] + placas:
		var mi := MeshInstance3D.new()
		mi.mesh = malha
		mi.material_override = mat_dentro if malha == rocha_tubo else mat_rocha
		add_child(mi)
	ComplexoLancamento.criar_multimesh(self, luzes, ComplexoLancamento._material_luz(Color(1.0, 0.84, 0.6), 4.0), false)
	var firme := StaticBody3D.new()
	firme.collision_layer = 1
	firme.collision_mask = 0
	firme.add_to_group("estrutura")
	add_child(firme)
	ComplexoLancamento.adicionar_colisoes(firme, estrada + pilares)
	var mortal := StaticBody3D.new()
	mortal.collision_layer = 1
	mortal.collision_mask = 0
	mortal.add_to_group("estrutura")
	mortal.add_to_group("mortal")
	add_child(mortal)
	ComplexoLancamento.adicionar_colisoes(mortal, tubo)
	for malha: Mesh in [capa] + placas:
		var cs := CollisionShape3D.new()
		var forma := malha.create_trimesh_shape()
		forma.backface_collision = true
		cs.shape = forma
		mortal.add_child(cs)


## Portal de metal na entrada (pedido do dono): moldura de aço em arco em volta da boca, placa
## "TÚNEL" iluminada logo acima, com faixas de perigo e luzes âmbar — o buraco aparece de longe.
## `centro` = boca no nível da estrada; `bh` = base com -Z para dentro do túnel.
## Devolve {colisao: caixas mortais}.
func _portal(sec: _Secao, centro: Vector3, bh: Basis) -> Dictionary:
	var aco: Array[Transform3D] = []
	var faixas: Array[Transform3D] = []
	var luzes: Array[Transform3D] = []
	var peca := func(tam: Vector3, local: Vector3, giro: Basis) -> Transform3D:
		return Transform3D(bh * giro * Basis.from_scale(tam), centro + bh * local)
	var folga := 0.45
	# Pernas e arco da moldura
	for s: float in [-1.0, 1.0]:
		var alt := sec.ombro - sec.piso + 0.5
		aco.append(peca.call(Vector3(0.7, alt, 1.0), Vector3(s * (sec.meia + folga), sec.piso - 0.5 + alt * 0.5, 0.0), Basis()))
	const GOMOS := 12
	for k in GOMOS:
		var u0 := float(k) / GOMOS
		var u1 := float(k + 1) / GOMOS
		var p0 := Vector2((sec.meia + folga) * cos(PI * u0), sec.ombro + (sec.alt_arco + folga) * sin(PI * u0))
		var p1 := Vector2((sec.meia + folga) * cos(PI * u1), sec.ombro + (sec.alt_arco + folga) * sin(PI * u1))
		var m := (p0 + p1) * 0.5
		var ang := atan2(p1.y - p0.y, p1.x - p0.x)
		aco.append(peca.call(Vector3(p0.distance_to(p1) + 0.3, 0.7, 1.0), Vector3(m.x, m.y, 0.0), Basis(Vector3.BACK, ang)))
		if k % 2 == 0:
			luzes.append(peca.call(Vector3(0.3, 0.3, 0.15), Vector3(m.x, m.y, 0.55), Basis(Vector3.BACK, ang)))
	# Placa com o nome, faixas de perigo em cima e embaixo
	# Grande: tem que aparecer de longe, para quem ainda vem de paraquedas
	var larg := sec.meia * 2.0 + 10.0
	var alt_placa := 5.0
	var y_placa := sec.topo + folga + 0.6 + alt_placa * 0.5
	aco.append(peca.call(Vector3(larg, alt_placa, 0.5), Vector3(0.0, y_placa, 0.1), Basis()))
	for dy: float in [-alt_placa * 0.5 - 0.3, alt_placa * 0.5 + 0.3]:
		faixas.append(peca.call(Vector3(larg + 0.4, 0.6, 0.6), Vector3(0.0, y_placa + dy, 0.12), Basis()))
	for k in 13:
		var x := lerpf(-larg * 0.5 + 0.6, larg * 0.5 - 0.6, k / 12.0)
		for dy: float in [-alt_placa * 0.5 - 0.3, alt_placa * 0.5 + 0.3]:
			luzes.append(peca.call(Vector3(0.5, 0.3, 0.2), Vector3(x, y_placa + dy, 0.5), Basis()))
	var nome := Label3D.new()
	nome.text = "TÚNEL"
	nome.font_size = 256
	nome.pixel_size = 3.4 / 256.0
	nome.outline_size = 24
	nome.modulate = Color(1.0, 0.85, 0.3)
	nome.outline_modulate = Color(0.05, 0.05, 0.05)
	nome.double_sided = false
	nome.transform = Transform3D(bh, centro + bh * Vector3(0.0, y_placa, 0.38))
	add_child(nome)
	# Visual
	var metal := ShaderMaterial.new()
	metal.shader = load("res://shaders/metal_gasto.gdshader")
	metal.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 61))
	metal.set_shader_parameter("ferrugem", 0.25)
	metal.set_shader_parameter("cor_tinta", Color(0.2, 0.22, 0.24))
	metal.set_shader_parameter("altura_chao", centro.y - 60.0)
	ComplexoLancamento.criar_multimesh(self, aco, metal)
	var listras := ShaderMaterial.new()
	listras.shader = load("res://shaders/listras_perigo.gdshader")
	listras.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 7))
	ComplexoLancamento.criar_multimesh(self, faixas, listras)
	ComplexoLancamento.criar_multimesh(self, luzes, ComplexoLancamento._material_luz(Color(1.0, 0.62, 0.2), 6.0), false)
	return {"colisao": aco + faixas}


## Capa de rocha por cima do túnel. O terreno é cavado numa vala larga ao longo dele (a malha do
## terreno é grossa demais para um túnel); a capa refaz a encosta natural por cima, com:
## - o teto de rocha acima da abóbada entre as bocas;
## - um recorte na face diante de cada boca (a encosta desce até abaixo do piso), que forma o portal;
## - as beiradas enfiadas sob o terreno em volta (sem emenda visível).
## Coordenadas: t = metros no chão ao longo do eixo a partir da entrada do json, l = lateral.
class _Manto:
	const MEIA_LARG := 46.0          # vala (30) + interpolação da malha (13) + folga
	const PASSO := 2.0
	var terreno: Terreno
	var origem: Vector3
	var dir: Vector3
	var lado: Vector3
	var comp: float
	var h_ini: float
	var h_fim: float
	var sec: _Secao
	var t_ini := 0.0                 # bocas (onde a encosta passa acima do arco)
	var t_fim := 0.0

	func _init(p_terreno: Terreno, p_origem: Vector3, p_dir: Vector3, p_lado: Vector3, p_comp: float, p_h_ini: float, p_h_fim: float, p_sec: _Secao) -> void:
		terreno = p_terreno
		origem = p_origem
		dir = p_dir
		lado = p_lado
		comp = p_comp
		h_ini = p_h_ini
		h_fim = p_h_fim
		sec = p_sec
		# Boca = primeiro/último ponto (no passo da capa) com rocha a 3 m acima do arco
		var t := 0.0
		while t < comp and natural(t, 0.0) < estrada(t) + sec.topo + 3.0:
			t += PASSO
		t_ini = t
		t = snappedf(comp, PASSO)
		while t > t_ini and natural(t, 0.0) < estrada(t) + sec.topo + 3.0:
			t -= PASSO
		t_fim = t

	func estrada(t: float) -> float:
		return lerpf(h_ini, h_fim, clampf(t / comp, 0.0, 1.0))

	func ponto(t: float) -> Vector3:
		return Vector3(origem.x, estrada(t), origem.z) + dir * t

	func natural(t: float, l: float) -> float:
		var p := origem + dir * t + lado * l
		return terreno.altura_natural_malha(p.x, p.z)

	func altura(t: float, l: float) -> float:
		var h := natural(t, l)
		var al := absf(l)
		if t >= t_ini and t <= t_fim:
			var teto := estrada(t) + sec.topo + 1.5
			if al <= sec.meia + 1.51 and (t < t_ini + PASSO * 0.5 or t > t_fim - PASSO * 0.5):
				h = teto   # rente à boca: a rocha fecha logo acima do arco (sem fenda até o alto)
			elif al < sec.meia + 4.0:
				h = maxf(h, teto)   # teto de rocha
		elif al <= sec.meia + 1.51:
			h = minf(h, estrada(t) + sec.piso - 1.0)       # recorte diante da boca
		# Beiradas descem para baixo do terreno em volta
		h -= 2.5 * smoothstep(MEIA_LARG - 6.0, MEIA_LARG, al)
		return h

	func malha() -> ArrayMesh:
		var ts: Array[float] = []
		var t := snappedf(-40.0, PASSO)
		while t <= comp + 40.0:
			ts.append(t)
			t += PASSO
		var ls: Array[float] = []
		var l := -MEIA_LARG
		while l <= MEIA_LARG + 0.01:
			ls.append(l)
			l += PASSO
		for s: float in [-1.0, 1.0]:   # borda exata do recorte
			ls.append(s * (sec.meia + 1.5))
		ls.sort()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for tt in ts:
			for ll in ls:
				var p := origem + dir * tt + lado * ll
				st.add_vertex(Vector3(p.x, altura(tt, ll), p.z))
		var nl := ls.size()
		for i in ts.size() - 1:
			# Furo da boca: entre a face recortada e o teto de rocha não há rocha
			var boca := (ts[i] < t_ini and ts[i + 1] >= t_ini) or (ts[i] <= t_fim and ts[i + 1] > t_fim)
			for j in nl - 1:
				if boca and absf(ls[j]) <= sec.meia + 1.51 and absf(ls[j + 1]) <= sec.meia + 1.51:
					continue
				var a := i * nl + j
				var c := a + nl
				st.add_index(a); st.add_index(c); st.add_index(a + 1)   # face para cima
				st.add_index(a + 1); st.add_index(c); st.add_index(c + 1)
		st.generate_normals()
		return st.commit()


## Seção do túnel (pedido do dono, desenho): piso reto, paredes retas curtas e abóbada arredondada.
## Coordenadas: x lateral, y a partir do nível da estrada.
class _Secao:
	var meia: float      # meia-largura interna
	var piso: float      # piso do tubo (abaixo da estrada)
	var ombro: float     # onde a parede reta vira abóbada
	var topo: float      # alto da abóbada
	var alt_arco: float

	func _init(p_meia: float, p_piso: float, p_ombro: float, p_topo: float) -> void:
		meia = p_meia
		piso = p_piso
		ombro = p_ombro
		topo = p_topo
		alt_arco = topo - ombro

	## Ponto da abóbada: u = 0 na parede direita, 1 na esquerda.
	func arco(u: float) -> Vector2:
		return Vector2(meia * cos(PI * u), ombro + alt_arco * sin(PI * u))

	## Altura do teto em x (0 fora da largura).
	func altura_em(x: float) -> float:
		var r := clampf(absf(x) / meia, 0.0, 1.0)
		return ombro + alt_arco * sqrt(1.0 - r * r)

	## Contorno fechado (parede direita, abóbada, parede esquerda, piso), com a normal para fora de
	## cada ponto e se é piso (quase sem relevo).
	func anel() -> Array:
		var pts := []
		for k in 3:   # parede direita subindo
			pts.append([Vector2(meia, lerpf(piso, ombro, k / 3.0)), Vector2.RIGHT, false])
		for k in 25:   # abóbada
			var u := k / 24.0
			var p := arco(u)
			var n := Vector2(p.x / meia, (p.y - ombro) / alt_arco).normalized()
			pts.append([p, n, false])
		for k in range(1, 4):   # parede esquerda descendo
			pts.append([Vector2(-meia, lerpf(ombro, piso, k / 3.0)), Vector2.LEFT, false])
		for k in range(1, 6):   # piso da esquerda para a direita
			pts.append([Vector2(lerpf(-meia, meia, k / 6.0), piso), Vector2.DOWN, true])
		return pts


## Paredes internas de rocha: o contorno em arco puxado ao longo do eixo, com relevo irregular
## (a rocha avança e recua) e o material do terreno (estratos das montanhas).
static func _malha_tubo(sec: _Secao, entrada: Vector3, b: Basis, comp: float, semente: int) -> ArrayMesh:
	var ruido := FastNoiseLite.new()
	ruido.seed = semente
	ruido.frequency = 0.18
	ruido.fractal_octaves = 3
	var ruido_grande := FastNoiseLite.new()   # bojos e reentrâncias maiores
	ruido_grande.seed = semente + 5
	ruido_grande.frequency = 0.05
	var anel := sec.anel()
	var n_anel := anel.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var passo := 1.5
	var t0 := -0.6   # só um pouco além das bocas (a moldura fica rente à face)
	var estacoes := int(ceil((comp + 1.2) / passo)) + 1
	for i in estacoes:
		var t := minf(t0 + i * passo, comp + 0.6)
		for j in n_anel:
			var p: Vector2 = anel[j][0]
			var n: Vector2 = anel[j][1]
			var amp := 0.12 if anel[j][2] else 1.0
			# Só para fora: o vão livre não diminui
			var desloc := ((ruido.get_noise_2d(j * 2.3, t) * 0.5 + 0.5) * 0.45 + (ruido_grande.get_noise_2d(j * 1.1, t) * 0.5 + 0.5) * 0.55) * amp
			var q := p + n * desloc
			st.add_vertex(entrada + b * Vector3(q.x, q.y, -t))
	for i in estacoes - 1:
		for j in n_anel:
			var j2 := (j + 1) % n_anel
			var a := i * n_anel + j
			var c := i * n_anel + j2
			var d := (i + 1) * n_anel + j
			var e := (i + 1) * n_anel + j2
			st.add_index(a); st.add_index(d); st.add_index(c)   # face para dentro do tubo
			st.add_index(c); st.add_index(d); st.add_index(e)
	st.generate_normals()
	return st.commit()


## Placa de rocha da boca com o furo em arco (dos dois lados), no plano da face da montanha.
static func _malha_boca(sec: _Secao, centro: Vector3, lado: Vector3, para_fora: Vector3, topo: float, fundo: float, semente: int) -> ArrayMesh:
	var ruido := FastNoiseLite.new()
	ruido.seed = semente
	ruido.frequency = 0.25
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var larg := sec.meia + 1.8   # passa um pouco da borda do recorte da capa (meia + 1,5)
	const COLUNAS := 32
	var ponto := func(x: float, y: float) -> Vector3:
		return centro + lado * x + Vector3.UP * y + para_fora * ruido.get_noise_2d(x, y) * 0.6
	var quad := func(x0: float, x1: float, y00: float, y01: float, y10: float, y11: float) -> void:
		# (x0, y00)-(x0, y01) e (x1, y10)-(x1, y11), dos dois lados
		var a: Vector3 = ponto.call(x0, y00)
		var b: Vector3 = ponto.call(x0, y01)
		var c: Vector3 = ponto.call(x1, y10)
		var d: Vector3 = ponto.call(x1, y11)
		for tri in [[a, b, c], [c, b, d], [a, c, b], [c, d, b]]:
			for v: Vector3 in tri:
				st.add_vertex(v)
	for k in COLUNAS:
		var x0 := lerpf(-larg, larg, float(k) / COLUNAS)
		var x1 := lerpf(-larg, larg, float(k + 1) / COLUNAS)
		var dentro0 := absf(x0) < sec.meia
		var dentro1 := absf(x1) < sec.meia
		var arco0 := sec.altura_em(x0) - 0.3 if dentro0 else sec.piso
		var arco1 := sec.altura_em(x1) - 0.3 if dentro1 else sec.piso
		quad.call(x0, x1, arco0, topo, arco1, topo)            # acima do arco (e parede ao lado)
		quad.call(x0, x1, fundo, sec.piso + 0.3, fundo, sec.piso + 0.3)   # abaixo do piso
	st.generate_normals()
	return st.commit()


static func _material_asfalto() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.2, 0.22)
	m.roughness = 0.9
	return m
