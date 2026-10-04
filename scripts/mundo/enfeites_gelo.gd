class_name EnfeitesGelo
extends Node3D
## Enfeites e sinalização da estrada do Frozen Peak (refeitos junto com o percurso de cada etapa):
## - pingentes de gelo pendurados nas beiradas da laje;
## - pórtico de largada, arcos de treliça com o logo do jogo em cada checkpoint e o arco da rampa final;
## - outdoors do logo em sacadas apoiadas em coluna própria (nada flutua), bandeiras do jogo ao vento
##   e birutas na rampa final;
## - sinalização antes de cada perigo: SALTO (com as guias listradas na rampinha e no pouso),
##   GELO e PISTA ESTREITA;
## - letreiros e outdoors do logo em cima dos muros da largada e da plataforma.
## Só as colunas e torres têm colisão; placas, bandeiras e painéis ficam fora da largura da pista.

var sub: ComplexoSubida
var _terreno: Terreno
var _aco: Array[Transform3D] = []
var _colisao: Array[Transform3D] = []
var _concreto: Array[Transform3D] = []
var _ocupado: Array = []     # [s0, s1] trechos já usados por armadilhas, vãos, arcos (para não sobrepor)
var _fonte: Font


func montar(p_sub: ComplexoSubida, terreno: Terreno) -> void:
	sub = p_sub
	_terreno = terreno
	name = "EnfeitesGelo"
	_fonte = load("res://assets/fontes/RacingSansOne-Regular.ttf")
	if sub.armadilhas:
		for g: Dictionary in sub.armadilhas._portoes:
			_ocupado.append([float(g.s) - 30.0, float(g.s) + float(g.comp) + 30.0])
		for z: Dictionary in sub.armadilhas._zonas_pedra:
			_ocupado.append([float(z.s1) - 30.0, float(z.s1) + 30.0])
	for v: Dictionary in sub.vaos():
		_ocupado.append([float(v.s0) - 95.0, float(v.s1) + 40.0])
	_pingentes()
	_portico_largada()
	_arcos_checkpoints()
	_sinalizacao()
	_rampa_final()
	_outdoors()
	_recintos()
	ComplexoLancamento.criar_multimesh(self, _aco, Gelo.material(Gelo.Mat.ACO))
	ComplexoLancamento.criar_multimesh(self, _concreto, Gelo.material(Gelo.Mat.CONCRETO))
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	add_child(corpo)
	ComplexoLancamento.adicionar_colisoes(corpo, _colisao)


func _livre(s0: float, s1: float) -> bool:
	for o: Array in _ocupado:
		if s1 > float(o[0]) and s0 < float(o[1]):
			return false
	return true


func _base(i: int) -> Basis:
	var t := sub.tangente_em(i)
	return Basis(sub.lateral_em(i), Vector3.UP, -Vector3(t.x, 0.0, t.z).normalized())


func _texto(texto: String, t: Transform3D, largura_max: float, altura_max: float, cor: Color) -> void:
	var l := Label3D.new()
	l.text = texto
	l.font = _fonte
	l.font_size = 160
	l.outline_size = 20
	l.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	var tam := _fonte.get_string_size(texto, HORIZONTAL_ALIGNMENT_LEFT, -1, 160)
	l.pixel_size = minf(largura_max / maxf(tam.x, 1.0), altura_max / maxf(tam.y, 1.0))
	l.modulate = cor
	l.double_sided = false
	l.transform = t
	add_child(l)


# ------------------------------------------------------------------ pingentes nas beiradas

func _pingentes() -> void:
	var xfs: Array = []
	var n := sub.total_amostras()
	for i in range(1, n):
		if sub.em_vao(i) or sub._vao[i] != 0:
			continue
		var t := sub.tangente_em(i)
		var lat := sub.lateral_em(i)
		var nrm := lat.cross(t).normalized()
		var meia := sub.largura_em(i) * 0.5
		for lado in 2:
			var sorte := Terreno._hash2(i * 3 + lado, 911)
			if sorte > 0.62:
				continue
			var h := 0.35 + 2.0 * sorte * sorte * 2.6
			var p := sub.amostra(i) + lat * (1.0 if lado == 1 else -1.0) * (meia - 0.12) - nrm * (ComplexoSubida.ESPESSURA_ESTRADA + h * 0.5 - 0.05)
			xfs.append(Transform3D(Basis(Vector3.RIGHT, PI) * Basis.from_scale(Vector3(0.07 + h * 0.06, h, 0.07 + h * 0.06)), p))
	Gelo.instancias_gelo(self, xfs, 0.0, 0, false, 450.0)


# ------------------------------------------------------------------ arcos

## Arco de treliça sobre a estrada na amostra i: duas torres fora da pista (com coluna até o chão),
## viga em cima, o logo do jogo nas duas faces, texto opcional e bandeiras nas pontas.
func _arco(i: int, altura: float, alt_logo: float, texto := "", bandeiras := true) -> void:
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5 + 2.2
	for s: float in [-1.0, 1.0]:
		var pe := c + lat * s * meia
		_aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * altura, 2.0, 2.4, 0.24, 0.1))
		_colisao.append(Transform3D(b * Basis.from_scale(Vector3(2.0, altura, 2.0)), pe + Vector3.UP * altura * 0.5))
		# Sacada de concreto e coluna até o chão
		_concreto.append(Transform3D(b * Basis.from_scale(Vector3(4.6, 1.6, 4.6)), pe + Vector3.DOWN * 0.78))   # topo rente ao pé da torre
		_colisao.append(_concreto[_concreto.size() - 1])
		var chao := _terreno.altura_em(pe.x, pe.z)
		if c.y - chao > 3.0:
			var col := Transform3D(b * Basis.from_scale(Vector3(2.4, c.y - chao, 2.4)), Vector3(pe.x, (c.y + chao) * 0.5 - 1.4, pe.z))
			_concreto.append(col)
			_colisao.append(col)
		if bandeiras:
			Gelo.criar_bandeira(self, pe + Vector3.UP * (altura + 2.0), 6.5, 4.4, 2.5, float(i) * 0.7 + s)
	var e := c - lat * (meia + 1.0) + Vector3.UP * (altura + 1.0)
	var d := c + lat * (meia + 1.0) + Vector3.UP * (altura + 1.0)
	_aco.append_array(ComplexoLancamento.trelica(e, d, 2.0, 2.4, 0.24, 0.1))
	# Nada de enfeite fantasma (pedido do dono): a viga, a faixa e o painel do logo também barram o carro
	_colisao.append(Transform3D(b * Basis.from_scale(Vector3(e.distance_to(d), 2.0, 2.0)), (e + d) * 0.5))
	_colisao.append(Transform3D(b * Basis.from_scale(Vector3(alt_logo * Gelo.PROP_LOGO, alt_logo, 2.8)), c + Vector3.UP * (altura + 1.0 + (alt_logo * 0.5 - 0.6 if texto != "" else 0.0))))
	for face: float in [-1.0, 1.0]:
		Gelo.painel_logo(self, c + Vector3.UP * (altura + 1.0 + (alt_logo * 0.5 - 0.6 if texto != "" else 0.0)) + b.z * face * 1.3, Basis.looking_at(-b.z * face, Vector3.UP), alt_logo)
	if texto != "":
		# Faixa pendurada embaixo da viga; b.z aponta para quem chega: o texto é lido de frente
		_aco.append(Transform3D(b * Basis.from_scale(Vector3(meia * 1.6, 1.9, 0.25)), c + Vector3.UP * (altura - 0.95)))
		_colisao.append(_aco[_aco.size() - 1])
		_texto(texto, Transform3D(b, c + Vector3.UP * (altura - 0.95) + b.z * 0.16), meia * 1.5, 1.5, Color(1.9, 2.0, 2.2))
	_ocupado.append([sub.progresso_amostra(i) - 25.0, sub.progresso_amostra(i) + 25.0])


func _portico_largada() -> void:
	var i := sub.indice_trecho("A", 26.0)
	_arco(i, 10.5, 3.2, Config.nome_mapa().to_upper())


func _arcos_checkpoints() -> void:
	for k in sub.checkpoints.size():
		var c: Dictionary = sub.checkpoints[k]
		var i := sub.indice_adiante(int(c.i), 9.0)
		if absf(sub.largura_em(i) - sub.largura_estrada) > 0.8 and sub.largura_em(i) < sub.largura_estrada:
			continue
		_arco(i, 9.0, 1.9, "CHECKPOINT %d" % (k + 1), k % 2 == 0)


## Arco grande antes da rampa final, birutas dos dois lados da ponta e fila de bandeiras.
func _rampa_final() -> void:
	var fim := sub.total_amostras() - 1
	var i := sub.indice_trecho("C", -75.0)
	_arco(i, 11.0, 3.4, "TARGET SPEED CHALLENGER")
	# (Sem birutas na ponta da rampa: o dono mandou tirar, 2026-10-04)
	for k in 5:
		var q := sub.indice_trecho("C", -150.0 - k * 16.0)
		if q <= 0 or q >= fim:
			continue
		var lq := sub.lateral_em(q)
		for s: float in [-1.0, 1.0]:
			var pe_f := sub.amostra(q) + lq * s * (sub.largura_em(q) * 0.5 + 0.5) + Vector3.DOWN * 0.5
			Gelo.criar_bandeira(self, pe_f, 6.5, 3.8, 2.2, k * 1.9 + s)
			_consolo(pe_f, lq * s)


## Consolo de aço preso na lateral da laje para o pé de um mastro que fica fora dela (biruta, bandeira):
## braço horizontal até o pé e mão-francesa por baixo. `fora` = direção da pista para o mastro.
func _consolo(pe: Vector3, fora: Vector3) -> void:
	_aco.append(ComplexoLancamento._viga(pe - fora * 1.6, pe + fora * 0.25, 0.3))
	_aco.append(ComplexoLancamento._viga(pe - fora * 1.5 + Vector3.DOWN * 1.1, pe + Vector3.DOWN * 0.1, 0.2))
	_aco.append(Transform3D(Basis.from_scale(Vector3(0.6, 0.25, 0.6)), pe))


# ------------------------------------------------------------------ sinalização dos perigos

## Placa num poste na beirada (dos dois lados), virada para quem chega.
func _placa(i: int, texto: String, cor: Color, sub_texto := "") -> void:
	var c := sub.amostra(i)
	var b := _base(i)
	var lat := sub.lateral_em(i)
	var meia := sub.largura_em(i) * 0.5
	for s: float in [-1.0, 1.0]:
		var pe := c + lat * s * (meia + 0.9) + Vector3.DOWN * 0.8
		_aco.append(ComplexoLancamento._viga(pe, pe + Vector3.UP * 5.6, 0.22))
		_aco.append(ComplexoLancamento._viga(pe, pe - lat * s * 1.0, 0.3))
		var centro := pe + Vector3.UP * 5.0
		_aco.append(Transform3D(b * Basis.from_scale(Vector3(3.6, 2.2, 0.2)), centro))
		_colisao.append(_aco[_aco.size() - 1])
		_colisao.append(Transform3D(b * Basis.from_scale(Vector3(0.3, 5.6, 0.3)), pe + Vector3.UP * 2.8))
		var leitura := Basis(-b.x, Vector3.UP, -b.z) * Basis(Vector3.UP, PI)   # +Z para quem chega (b.z)
		_texto(texto, Transform3D(leitura, centro + b.z * 0.13 + Vector3.UP * (0.35 if sub_texto != "" else 0.0)), 3.2, 1.1 if sub_texto != "" else 1.6, cor)
		if sub_texto != "":
			_texto(sub_texto, Transform3D(leitura, centro + b.z * 0.13 + Vector3.DOWN * 0.6), 3.2, 0.6, Color(1.6, 1.6, 1.7))
		var luz: Array[Transform3D] = []
		for q: float in [-1.0, 1.0]:
			luz.append(Transform3D(b * Basis.from_scale(Vector3(3.7, 0.1, 0.26)), centro + Vector3.UP * q * 1.15))
		ComplexoLancamento.criar_multimesh(self, luz, ComplexoLancamento._material_luz(Color(cor.r, cor.g, cor.b).clamp(), 5.0), false)


func _sinalizacao() -> void:
	var listras := ShaderMaterial.new()
	listras.shader = load("res://shaders/listras_perigo.gdshader")
	listras.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 7))
	var guias: Array[Transform3D] = []
	var pisca: Array[Transform3D] = []
	var fases := PackedFloat32Array()
	for v: Dictionary in sub.vaos():
		var i0: int = v.i0
		var i1: int = v.i1
		var ini := sub.inicio_trecho_de(i0)
		# Placa 70 m antes (ou no começo do trecho)
		var ip := i0
		while ip > ini + 2 and sub.progresso_amostra(i0) - sub.progresso_amostra(ip) < 70.0:
			ip -= 1
		_placa(ip, "SALTO", Color(2.2, 0.5, 0.15), "%d m" % int(round(float(v.s1) - float(v.s0))))
		# Guias listradas nas beiradas da rampinha (16 m antes do lábio) e do pouso (14 m depois)
		for par: Array in [[i0, -1, 16.0], [i1, 1, 14.0]]:
			var j: int = par[0]
			var andou := 0.0
			while andou < float(par[2]) and j > ini and j < sub.fim_do_trecho(i0):
				var jn: int = j + int(par[1])
				var a := sub.amostra(j)
				var bq := sub.amostra(jn)
				var lat := sub.lateral_em(j)
				var meia := sub.largura_em(j) * 0.5
				for s: float in [-1.0, 1.0]:
					guias.append(ComplexoLancamento._viga(a + lat * s * (meia + 0.2) + Vector3.UP * 0.25, bq + lat * s * (meia + 0.2) + Vector3.UP * 0.25, 0.4) * Transform3D(Basis.from_scale(Vector3(1.0, 2.6, 1.02)), Vector3.ZERO))
				andou += a.distance_to(bq)
				j = jn
			var lt := sub.lateral_em(int(par[0]))
			for s: float in [-1.0, 1.0]:
				pisca.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.9), sub.amostra(int(par[0])) + lt * s * (sub.largura_em(int(par[0])) * 0.5 + 0.2) + Vector3.UP * 1.1))
				fases.append(0.0 if s < 0.0 else PI)
	ComplexoLancamento.criar_multimesh(self, guias, listras)
	if not pisca.is_empty():
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/luz_sequencial.gdshader")
		mat.set_shader_parameter("cor", Color(1.0, 0.25, 0.05))
		mat.set_shader_parameter("energia", 10.0)
		mat.set_shader_parameter("velocidade", 9.0)
		mat.set_shader_parameter("minimo", 0.05)
		ComplexoLancamento.criar_multimesh(self, pisca, mat, false, fases)
	# Começo de cada trecho de gelo e de cada estreito
	var n := sub.total_amostras()
	for i in range(2, n):
		if sub.trecho_de(i) != sub.trecho_de(i - 1):
			continue
		var ini := sub.inicio_trecho_de(i)
		if sub.aderencia_em(i) < 0.99 and sub.aderencia_em(i - 1) >= 0.99:
			_placa(maxi(i - 42, ini + 2), "GELO", Color(0.4, 1.6, 2.4), "ESCORREGA")
		var estreito := sub.largura_em(i) < sub.largura_estrada - 2.5
		var antes := sub.largura_em(i - 1) < sub.largura_estrada - 2.5
		if estreito and not antes:
			_placa(maxi(i - 46, ini + 2), "ESTREITO", Color(2.4, 1.7, 0.2), "DEVAGAR")


# ------------------------------------------------------------------ outdoors na estrada

## Outdoor do logo numa sacada ao lado da estrada (coluna própria até o chão), a cada ~380 m, de
## lados alternados, só em reta e longe de armadilhas, saltos e arcos.
func _outdoors() -> void:
	var n := sub.total_amostras()
	var proximo := 240.0
	var lado := 1.0
	for i in range(30, n - 60):
		var s := sub.progresso_amostra(i)
		if s < proximo:
			continue
		if sub.curvatura_adiante(maxi(i - 20, sub.inicio_trecho_de(i)), 50.0) > 1.0 / 260.0 or not _livre(s - 22.0, s + 22.0) \
				or sub.largura_em(i) < sub.largura_estrada - 0.5 or sub.fim_do_trecho(i) - i < 90 or i - sub.inicio_trecho_de(i) < 40:
			continue
		proximo = s + 380.0
		_ocupado.append([s - 22.0, s + 22.0])
		var c := sub.amostra(i)
		var b := _base(i)
		var lat := sub.lateral_em(i) * lado
		var meia := sub.largura_em(i) * 0.5
		var centro_s := c + lat * (meia + 4.6)
		_concreto.append(Transform3D(b * Basis.from_scale(Vector3(8.6, 1.0, 13.0)), centro_s + Vector3.DOWN * (ComplexoSubida.ESPESSURA_ESTRADA * 0.5 + 0.1)))
		_colisao.append(_concreto[_concreto.size() - 1])
		var chao := _terreno.altura_em(centro_s.x, centro_s.z)
		if c.y - chao > 3.0:
			var col := Transform3D(b * Basis.from_scale(Vector3(3.0, c.y - chao, 3.0)), Vector3(centro_s.x, (c.y + chao) * 0.5 - 1.4, centro_s.z))
			_concreto.append(col)
			_colisao.append(col)
		# Painel virado para quem chega, um pouco aberto para a estrada
		var alt := 4.0
		var giro := b * Basis(Vector3.UP, -lado * deg_to_rad(28.0))
		var centro := centro_s + Vector3.UP * (3.4 + alt * 0.5)
		for q: float in [-1.0, 1.0]:
			var pe := centro_s + giro.x * q * alt * Gelo.PROP_LOGO * 0.36
			_aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * (3.4 + alt + 0.4), 1.0, 1.8, 0.16, 0.07))
			_colisao.append(Transform3D(giro * Basis.from_scale(Vector3(1.0, 3.4 + alt + 0.4, 1.0)), pe + Vector3.UP * (3.4 + alt + 0.4) * 0.5))
		_colisao.append(Transform3D(giro * Basis.from_scale(Vector3(alt * Gelo.PROP_LOGO, alt, 0.5)), centro))
		Gelo.painel_logo(self, centro, Basis(-giro.x, Vector3.UP, -giro.z) * Basis(Vector3.UP, PI), alt, true)
		lado = -lado


# ------------------------------------------------------------------ largada e plataforma

## Em cima dos muros dos cercados: letreiro com o nome da fase e o logo no fundo (virado para a
## saída) e dois outdoors do logo em cada lateral, sobre pernas de treliça presas no muro.
func _recintos() -> void:
	for r: Recinto in [sub.largada, sub.plataforma]:
		var topo := r.piso_y + r.muro_altura + r.grade_altura
		var meia := r.largura_arena * 0.5
		# Fundo: logo grande + nome
		var alt := 4.4
		var bf := Basis.looking_at(-r.frente, Vector3.UP)   # +Z = frente (lido de dentro, por quem olha o fundo)
		var centro := r.pa(-1.4, 0.0, topo + 2.2 + alt * 0.5)
		for lat: float in [-9.0, 9.0]:
			var pe := r.pa(-1.6, lat, topo)
			_aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * (2.2 + alt + 2.6), 0.9, 1.5, 0.15, 0.07))
		Gelo.painel_logo(self, centro, bf, alt)
		_texto(Config.nome_mapa().to_upper(), Transform3D(bf, centro + Vector3.UP * (alt * 0.5 + 1.6) + bf.z * 0.3), 13.0, 1.9, Color(1.6, 2.0, 2.4))
		for x: float in [r.comprimento * 0.28, r.comprimento * 0.72]:
			for s: float in [-1.0, 1.0]:
				var entra := false
				for en in r.entradas:
					if signf(float(en[0])) == s and absf(float(en[1]) - x) < float(en[2]) * 0.5 + 9.0:
						entra = true
				if entra:
					continue
				var bl := Basis.looking_at(r.lateral * s, Vector3.UP)   # +Z para dentro
				var c2 := r.pa(x, s * (meia + 1.2), topo + 1.8 + 1.5)
				for dx: float in [-3.4, 3.4]:
					var pe := r.pa(x + dx, s * (meia + 1.4), topo)
					_aco.append_array(ComplexoLancamento.trelica(pe, pe + Vector3.UP * (1.8 + 3.2), 0.8, 1.4, 0.14, 0.06))
				Gelo.painel_logo(self, c2, bl, 3.0)
		# Bandeiras nos quatro cantos do muro
		for x: float in [0.0, r.comprimento]:
			for s: float in [-1.0, 1.0]:
				Gelo.criar_bandeira(self, r.pa(x, s * meia, topo + 0.4), 9.0, 5.0, 2.8, x * 0.1 + s)
