class_name Cidade
extends Node3D
## City Rush: a cidade no lugar do cânion. Mesmas rampas, distâncias e alvo do Canyon Rush:
## - cada plataforma fica no telhado de um arranha-céu (a "mesa" do cânion), com a descida passando
##   por cima de uma avenida (as colunas da rampa descem até o asfalto);
## - quadras em grade alinhadas com os corredores de voo; prédios baixos no corredor (mesmo teto
##   que o terreno do cânion tinha) e na borda da praça do alvo, arranha-céus fora deles;
## - todos os prédios são caixas alinhadas aos eixos: altura(x, z) responde por grade de células
##   (o Terreno usa isso em altura_em) e cada um tem uma caixa de colisão (grupo "predio"): bater na
##   fachada explode (o Veiculo olha a normal do contato) e o telhado é chão — dá para andar, pular
##   (ejetor), acelerar e usar o nitro em cima dos prédios.

const CELULA := 50.0
const SEM_TETO := 2000.0

## Estilos de fachada (shader predio.gdshader, INSTANCE_CUSTOM.g = estilo / 8)
enum Estilo { VIDRO, ESCRITORIO, TIJOLO, VIDRO_ESCURO, BRANCO, TORRE, MACICO, METAL, HELIPONTO, ART_DECO, CONCRETO }

var _caixas: Array = []          # [Rect2 (x, z), altura, estilo, cor, semente]
var _grade := {}                 # Vector2i → PackedInt32Array (índices de _caixas)
var _extras: Array = []          # [Transform3D, estilo, cor]: detalhes só visuais (platibanda, equipamentos...)
var _solidos: Array = []         # [centro, tamanho]: detalhes do telhado que também colidem (sem explodir)
var _balizas: Array[Transform3D] = []   # luzes vermelhas no alto das antenas
var _terreno: Terreno
var _chao := 6.0
var _quadra := 150.0
var _rua := 24.0
var _praca := 430.0
var _praca_trans := 760.0
var _torres: Array = []          # [Rect2, direção (Vector2), cor da equipe]
var _avenida := 30.0             # meia-largura da avenida livre de cada corredor
var _livres: Array[Rect2] = []   # brechas das chicanes (nada construído)
var _rotas := {}                 # Vector2i(direção) → Array[Vector3]: rota dos bots pelas brechas
var _proibidos: Array[Rect2] = []   # áreas sem prédio (ver _montar_proibidos)
var _perto_alvo := 600.0          # raio em volta do alvo com prédios altos e sem lote vazio
var _perto_min := 70.0
var _perto_max := 240.0


func gerar(terreno: Terreno, chao: float) -> void:
	name = "Cidade"
	_terreno = terreno
	_chao = chao
	var cfg: Dictionary = Config.valor("mapa.cidade", {})
	_quadra = float(cfg.get("quadra", 150))
	_rua = float(cfg.get("rua", 24))
	_praca = float(cfg.get("praca", 430))
	_praca_trans = float(cfg.get("praca_transicao", 760))
	_avenida = float(cfg.get("avenida_meia_largura", 30))
	_perto_alvo = float(cfg.get("perto_alvo_raio", 600))
	_perto_min = float(cfg.get("perto_alvo_altura_min", 70))
	_perto_max = float(cfg.get("perto_alvo_altura_max", 240))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1967)) + 3301
	var t0 := Time.get_ticks_msec()
	_montar_torres(cfg)
	_montar_chicanes(cfg, rng)
	_montar_proibidos()
	_montar_quadras(cfg, rng)
	_criar_visual(float(cfg.get("janelas_acesas", 0.28)))
	_criar_colisao()
	print("[CIDADE] gerada em %d ms: %d prédios, %d detalhes" % [Time.get_ticks_msec() - t0, _caixas.size(), _extras.size()])


## Altura do prédio mais alto em (x, z), ou -INF fora dos prédios.
func altura(x: float, z: float) -> float:
	var lista: PackedInt32Array = _grade.get(Vector2i(floori(x / CELULA), floori(z / CELULA)), PackedInt32Array())
	var h := -INF
	for i in lista:
		var c: Array = _caixas[i]
		if (c[0] as Rect2).has_point(Vector2(x, z)):
			h = maxf(h, c[1])
	return h


func _adicionar(r: Rect2, topo: float, estilo: int, cor: Color, semente: float) -> void:
	var i := _caixas.size()
	_caixas.append([r, topo, estilo, cor, semente])
	for gx in range(floori(r.position.x / CELULA), floori(r.end.x / CELULA) + 1):
		for gz in range(floori(r.position.y / CELULA), floori(r.end.y / CELULA) + 1):
			var k := Vector2i(gx, gz)
			if not _grade.has(k):
				_grade[k] = PackedInt32Array()
			(_grade[k] as PackedInt32Array).append(i)


## Retângulo (mundo, x/z) a partir de coordenadas do corredor: ao longo (do alvo para fora) e lateral.
static func _retangulo(dir: Vector2, ao_longo_min: float, ao_longo_max: float, meia_lateral: float) -> Rect2:
	var perp := Vector2(-dir.y, dir.x)
	var r := Rect2(dir * ao_longo_min + perp * meia_lateral, Vector2.ZERO)
	for p: Vector2 in [dir * ao_longo_min - perp * meia_lateral, dir * ao_longo_max + perp * meia_lateral, dir * ao_longo_max - perp * meia_lateral]:
		r = r.expand(p)
	return r


# ------------------------------------------------------------------ arranha-céus das plataformas

func _montar_torres(cfg: Dictionary) -> void:
	var perfil := _terreno.perfil
	var x_borda := perfil.pontos[perfil.indice_borda].x
	var xe := perfil.comprimento_horizontal
	var d := _terreno.distancia_saida
	var meia := float(cfg.get("torre_meia_largura", 66))
	var recuo := float(cfg.get("torre_recuo", 78))
	var topo := _terreno._topo_mesa
	for i in Config.EQUIPES.size():
		var eq: Dictionary = Config.EQUIPES[i]
		var dir := Vector2(eq.direcao.x, eq.direcao.z)
		# x do perfil (0 = início da plataforma) → distância ao alvo: d + xe - x
		var r := _retangulo(dir, d + xe - x_borda, d + xe + recuo, meia)
		_adicionar(r, topo, Estilo.TORRE, eq.cor, float(i) * 0.173 + 0.05)
		_torres.append([r, dir, eq.cor])
		# Embasamento mais largo nos primeiros andares (pódio da torre)
		var podio := _retangulo(dir, d + xe - x_borda + 6.0, d + xe + recuo + 22.0, meia + 18.0)
		_adicionar(podio, _chao + 26.0, Estilo.VIDRO_ESCURO, Color(0.8, 0.82, 0.86), float(i) * 0.31 + 0.11)


# ------------------------------------------------------------------ chicanes

## Em cada corredor, arranha-céus atravessados na avenida (mais altos que o voo), de lados
## alternados: o 1º fecha a avenida de um lado e deixa uma brecha do outro; o 2º faz o contrário —
## quem voa reto bate; é preciso costurar em "S". Config mapa.cidade.chicanes:
## [[ao longo (m do alvo), meia-largura da brecha, altura mínima, altura máxima], ...].
func _montar_chicanes(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var lista: Array = cfg.get("chicanes", [[560, 50, 250, 320], [270, 50, 230, 300]])
	var prof := float(cfg.get("chicane_profundidade", 46))
	for dir: Vector2 in _terreno._direcoes:
		var perp := Vector2(-dir.y, dir.x)
		var lado := 1.0 if rng.randf() < 0.5 else -1.0
		var rota: Array[Vector3] = []
		for c: Array in lista:
			var u := float(c[0]) + rng.randf_range(-30.0, 30.0)
			var meia_brecha := float(c[1])
			var cruza := rng.randf_range(10.0, 22.0)   # quanto o prédio passa do meio da avenida
			# Prédio: do lado "lado", de cruza além do meio até 110 m para fora
			var a := dir * (u - prof * 0.5) + perp * (-lado * cruza)
			var b := dir * (u + prof * 0.5) + perp * (lado * 110.0)
			var r := Rect2(a, Vector2.ZERO).expand(b)
			var h := _chao + snappedf(rng.randf_range(float(c[2]), float(c[3])), 3.6)
			var est := Estilo.VIDRO if rng.randf() < 0.5 else Estilo.VIDRO_ESCURO
			_adicionar(r, h, est, _cor_para(est, rng), rng.randf())
			_telhado(r, h, h - _chao, est, Color(0.3, 0.32, 0.34), rng)
			# Brecha do outro lado: livre de prédios um pouco antes e depois
			var centro_brecha := -lado * (cruza + meia_brecha + 4.0)
			var la := dir * (u - prof - 60.0) + perp * (-lado * cruza)
			var lb := dir * (u + prof + 60.0) + perp * (-lado * (cruza + meia_brecha * 2.0 + 8.0))
			_livres.append(Rect2(la, Vector2.ZERO).expand(lb))
			for k: float in [1.0, 0.0, -1.0]:
				var w := dir * (u + k * (prof * 0.5 + 45.0)) + perp * centro_brecha
				rota.append(Vector3(w.x, 0.0, w.y))
			lado = -lado
		var fim := dir * 140.0
		rota.append(Vector3(fim.x, 0.0, fim.y))
		_rotas[Vector2i(roundi(dir.x * 100.0), roundi(dir.y * 100.0))] = rota


## Rota dos bots do corredor que sai na direção `dir` (do alvo para a rampa), da rampa para o alvo.
func rota(dir: Vector2) -> Array[Vector3]:
	var r: Array[Vector3] = []
	r.assign(_rotas.get(Vector2i(roundi(dir.x * 100.0), roundi(dir.y * 100.0)), []))
	return r


# ------------------------------------------------------------------ quadras

## Teto de altura em (x, z) para o que sobrou do lote depois de recortado pelas áreas livres
## (_proibidos): prédios abaixo do tabuleiro ao lado da descida e, se praca_transicao > praca,
## baixos perto do alvo.
func _teto(p: Vector2) -> float:
	var r := p.length()
	var teto := SEM_TETO
	if _praca_trans > _praca:
		teto = lerpf(16.0, SEM_TETO, smoothstep(_praca, _praca_trans, r))
	var perfil := _terreno.perfil
	var xe := perfil.comprimento_horizontal
	var x_borda := perfil.pontos[perfil.indice_borda].x
	var d := _terreno.distancia_saida
	for dir: Vector2 in _terreno._direcoes:
		var ao_longo := p.dot(dir)
		if ao_longo < 0.0:
			continue
		var lateral := absf(p.dot(Vector2(-dir.y, dir.x)))
		var xp := d + xe - ao_longo
		if xp > x_borda - 10.0 and xp < xe + 20.0:
			var sob := perfil.altura_em(clampf(xp, 0.0, xe)) - 28.0
			teto = minf(teto, lerpf(sob, SEM_TETO, smoothstep(40.0, 140.0, lateral)))
	return teto


## Áreas sem prédio (retângulos alinhados aos eixos). Pedido do dono: SEM espaço aberto — só a
## clareira do alvo, a avenida de cada corredor (do alvo até a rampa), as brechas das chicanes,
## a faixa sob a descida e a calçada das torres. Lote que encosta nelas é RECORTADO, não descartado
## (descartar apagava quarteirões inteiros em volta do alvo).
func _montar_proibidos() -> void:
	var perfil := _terreno.perfil
	var xe := perfil.comprimento_horizontal
	var x_borda := perfil.pontos[perfil.indice_borda].x
	var d := _terreno.distancia_saida
	_proibidos.append(Rect2(-Vector2.ONE * _praca, Vector2.ONE * _praca * 2.0))
	for dir: Vector2 in _terreno._direcoes:
		_proibidos.append(_retangulo(dir, 0.0, d + 40.0, _avenida))
		_proibidos.append(_retangulo(dir, d + xe - (xe + 20.0), d + xe - (x_borda - 10.0), 34.0))
	for t: Array in _torres:
		_proibidos.append((t[0] as Rect2).grow(34.0))
	_proibidos.append_array(_livres)


## Tira de `lote` a área `fora`: fica o maior pedaço que sobra (esquerda, direita, frente ou trás).
static func _recortar(lote: Rect2, fora: Rect2) -> Rect2:
	if not lote.intersects(fora):
		return lote
	var pedacos: Array[Rect2] = [
		Rect2(lote.position, Vector2(fora.position.x - lote.position.x, lote.size.y)),
		Rect2(Vector2(fora.end.x, lote.position.y), Vector2(lote.end.x - fora.end.x, lote.size.y)),
		Rect2(lote.position, Vector2(lote.size.x, fora.position.y - lote.position.y)),
		Rect2(Vector2(lote.position.x, fora.end.y), Vector2(lote.size.x, lote.end.y - fora.end.y)),
	]
	var melhor := Rect2()
	for p in pedacos:
		if p.size.x > 0.0 and p.size.y > 0.0 and p.get_area() > melhor.get_area():
			melhor = p
	return melhor


func _teto_retangulo(r: Rect2) -> float:
	var t := SEM_TETO
	for fx: float in [0.0, 0.5, 1.0]:
		for fz: float in [0.0, 0.5, 1.0]:
			t = minf(t, _teto(r.position + r.size * Vector2(fx, fz)))
			if t < 0.0:
				return t
	return t


func _montar_quadras(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	var calcada := float(cfg.get("calcada", 5))
	var h_min := float(cfg.get("altura_min", 14))
	var h_max := float(cfg.get("altura_max", 230))
	var marco := float(cfg.get("marco_chance", 0.05))
	var marco_max := float(cfg.get("marco_max", 360))
	var meio := Terreno.MEIO_INTERNO - 100.0
	var n := int(meio / _quadra)
	var recuo := _rua * 0.5 + calcada
	for ix in range(-n, n):
		for iz in range(-n, n):
			var quadra := Rect2(Vector2(ix, iz) * _quadra + Vector2.ONE * recuo, Vector2.ONE * (_quadra - recuo * 2.0))
			for lote in _lotes(quadra, rng):
				_predio(lote, rng, h_min, h_max, marco, marco_max)
	# Silhueta ao longe (sem detalhe de lote): uma caixa por quadra sorteada
	var longe := 6400.0
	var passo := _quadra * 2.0
	var nl := int(longe / passo)
	for ix in range(-nl, nl):
		for iz in range(-nl, nl):
			var c := Vector2(ix + 0.5, iz + 0.5) * passo
			if absf(c.x) < meio + passo and absf(c.y) < meio + passo:
				continue
			if rng.randf() > 0.45:
				continue
			var lado := rng.randf_range(50.0, 120.0)
			var r := Rect2(c - Vector2.ONE * lado * 0.5, Vector2(lado, lado * rng.randf_range(0.6, 1.2)))
			var h := _chao + rng.randf_range(20.0, 60.0) + 220.0 * pow(rng.randf(), 4.0)
			var est := _estilo_para(h - _chao, rng)
			_adicionar(r, h, est, _cor_para(est, rng), rng.randf())


## Divide a quadra em 1, 2 ou 4 lotes com vão de 6 m entre os prédios.
func _lotes(q: Rect2, rng: RandomNumberGenerator) -> Array[Rect2]:
	var lista: Array[Rect2] = []
	var vao := 6.0
	var s := rng.randf()
	if s < 0.25:
		lista.append(q)
	elif s < 0.55:
		var corte := rng.randf_range(0.35, 0.65)
		if rng.randf() < 0.5:
			var w := q.size.x * corte
			lista.append(Rect2(q.position, Vector2(w - vao * 0.5, q.size.y)))
			lista.append(Rect2(q.position + Vector2(w + vao * 0.5, 0.0), Vector2(q.size.x - w - vao * 0.5, q.size.y)))
		else:
			var hgt := q.size.y * corte
			lista.append(Rect2(q.position, Vector2(q.size.x, hgt - vao * 0.5)))
			lista.append(Rect2(q.position + Vector2(0.0, hgt + vao * 0.5), Vector2(q.size.x, q.size.y - hgt - vao * 0.5)))
	else:
		var cx := q.size.x * rng.randf_range(0.4, 0.6)
		var cz := q.size.y * rng.randf_range(0.4, 0.6)
		for a in 2:
			for b in 2:
				var x0 := q.position.x + (0.0 if a == 0 else cx + vao * 0.5)
				var x1 := q.position.x + (cx - vao * 0.5 if a == 0 else q.size.x)
				var z0 := q.position.y + (0.0 if b == 0 else cz + vao * 0.5)
				var z1 := q.position.y + (cz - vao * 0.5 if b == 0 else q.size.y)
				lista.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	return lista


func _predio(lote: Rect2, rng: RandomNumberGenerator, h_min: float, h_max: float, marco: float, marco_max: float) -> void:
	var dist_alvo := lote.get_center().length()
	var perto := dist_alvo < _perto_alvo   # em volta do alvo: cheio e alto (pousar tem que ser difícil)
	# Recuo do lote (jardim/estacionamento) e às vezes um lote vazio
	if not perto and rng.randf() < 0.06:
		return
	var folga := rng.randf_range(0.0, 2.0 if perto else 6.0)
	var r := lote.grow(-folga)
	for fora in _proibidos:
		r = _recortar(r, fora.grow(3.0))
	if r.size.x < 10.0 or r.size.y < 10.0:
		return
	var teto := _teto_retangulo(r)
	if teto < 8.0:
		return
	var h: float
	if rng.randf() < marco:
		h = rng.randf_range(h_max, marco_max)
	elif perto:
		h = lerpf(_perto_min, _perto_max, pow(rng.randf(), 1.3))
	else:
		h = lerpf(h_min, h_max, pow(rng.randf(), 2.6))
	h = minf(h, teto)
	if h < 8.0:
		return
	h = maxf(snappedf(h, 3.6), 7.2)   # andares inteiros
	var estilo := _estilo_para(h, rng)
	var cor := _cor_para(estilo, rng)
	var semente := rng.randf()
	var topo := r
	var h_topo := _chao + h
	var forma := rng.randf()
	if h > 110.0 and forma < 0.7 and r.size.x > 40.0 and r.size.y > 40.0:
		# Arranha-céu: pódio (às vezes de outro estilo), torre fora do centro e 0 a 2 recuos
		var h_base := snappedf(h * rng.randf_range(0.12, 0.38), 3.6)
		var est_base := estilo if rng.randf() < 0.5 else _estilo_para(h_base, rng)
		var cor_base := cor if est_base == estilo else _cor_para(est_base, rng)
		_adicionar(r, _chao + h_base, est_base, cor_base, semente + 0.31)
		_telhado(r, _chao + h_base, h_base, est_base, cor_base, rng, false)
		var folga_t := rng.randf_range(5.0, minf(r.size.x, r.size.y) * 0.24)
		var corpo := r.grow(-folga_t)
		corpo.position += Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * folga_t * 0.7
		var degraus := rng.randi_range(0, 2)
		for k in degraus + 1:
			var hk := h if k == degraus else snappedf(lerpf(h_base, h, float(k + 1) / float(degraus + 1) * rng.randf_range(0.8, 0.95)), 3.6)
			_adicionar(corpo, _chao + hk, estilo, cor, semente)
			if k < degraus:
				_telhado(corpo, _chao + hk, hk, estilo, cor, rng, false)
				corpo = corpo.grow(-minf(corpo.size.x, corpo.size.y) * rng.randf_range(0.08, 0.16))
		topo = corpo
		var fim := rng.randf()
		if h > 180.0 and fim < 0.2:
			# Agulha: três blocos cada vez menores e um mastro com baliza
			var y := _chao + h
			var b := corpo
			for k in 3:
				_cornija(b, y, cor)
				b = b.grow(-minf(b.size.x, b.size.y) * 0.22)
				y += snappedf(rng.randf_range(7.2, 14.4), 3.6)
				_adicionar(b, y, estilo, cor, semente + 0.5)
			var c := b.get_center()
			var a := rng.randf_range(25.0, 50.0)
			_peca(Vector3(c.x, y + a * 0.5, c.y), Vector3(0.8, a, 0.8), Estilo.METAL, Color.WHITE)
			_luz_baliza(Vector3(c.x, y + a + 0.4, c.y))
			_cornija(b, y, cor)
			return
		elif fim < 0.5:
			_cornija(corpo, _chao + h, cor)
			var coroa := corpo.grow(-minf(corpo.size.x, corpo.size.y) * rng.randf_range(0.15, 0.3))
			h_topo = _chao + h + snappedf(rng.randf_range(7.2, 18.0), 3.6)
			_adicionar(coroa, h_topo, Estilo.MACICO if rng.randf() < 0.4 else estilo, cor * 0.9, semente + 0.5)
			topo = coroa
	elif h > 25.0 and forma > 0.72 and r.size.x > 30.0 and r.size.y > 30.0:
		# Bloco em L / com ala baixa: metade alta, a outra mais baixa (outro tom ou outro estilo)
		var ao_x := r.size.x > r.size.y if rng.randf() < 0.75 else r.size.x <= r.size.y
		var corte := rng.randf_range(0.45, 0.65)
		var alta := r
		var baixa := r
		if ao_x:
			alta.size.x *= corte
			baixa.position.x = alta.end.x
			baixa.size.x = r.size.x - alta.size.x
		else:
			alta.size.y *= corte
			baixa.position.y = alta.end.y
			baixa.size.y = r.size.y - alta.size.y
		if rng.randf() < 0.5:
			var t := alta
			alta = baixa
			baixa = t
		var h_baixa := maxf(snappedf(h * rng.randf_range(0.35, 0.65), 3.6), 7.2)
		var est_b := estilo if rng.randf() < 0.6 else _estilo_para(h_baixa, rng)
		var cor_b := cor * rng.randf_range(0.85, 1.0) if est_b == estilo else _cor_para(est_b, rng)
		_adicionar(alta, _chao + h, estilo, cor, semente)
		_adicionar(baixa, _chao + h_baixa, est_b, cor_b, semente + 0.27)
		_telhado(baixa, _chao + h_baixa, h_baixa, est_b, cor_b, rng)
		topo = alta
	else:
		_adicionar(r, _chao + h, estilo, cor, semente)
	_telhado(topo, h_topo, h, estilo, cor, rng)
	if h < 70.0 and estilo != Estilo.VIDRO and estilo != Estilo.VIDRO_ESCURO:
		_marquise(r, rng)


# ------------------------------------------------------------------ detalhes (só visual)

## Peça de detalhe: entra no mesmo desenho dos prédios, mas não em altura_em. `solido`: tem caixa
## de colisão (carro bate/sobe nela, mas não explode).
func _peca(centro: Vector3, tamanho: Vector3, estilo: int, cor: Color, solido := false) -> void:
	_extras.append([Transform3D(Basis.from_scale(tamanho), centro), estilo, cor])
	if solido:
		_solidos.append([centro, tamanho])


## Cornija: aba saliente no alto da caixa (sombra marcada na fachada).
func _cornija(r: Rect2, y: float, cor: Color) -> void:
	var c := r.get_center()
	_peca(Vector3(c.x, y - 0.35, c.y), Vector3(r.size.x + 1.2, 0.7, r.size.y + 1.2), Estilo.MACICO, cor * 0.92)


## Topo: platibanda (mureta baixa em volta: só visual, o carro passa por cima dela para saltar de
## um telhado a outro), casa de máquinas, caixas d'água, condensadoras e, nos arranha-céus, antenas
## e às vezes heliponto. completo = false: só platibanda e cornija (recuos no meio da torre).
func _telhado(r: Rect2, y: float, h: float, estilo: int, cor: Color, rng: RandomNumberGenerator, completo := true) -> void:
	var c := r.get_center()
	var alt := 0.45 if h < 60.0 else 0.6
	var esp := 0.35
	var vidro := estilo == Estilo.VIDRO or estilo == Estilo.VIDRO_ESCURO
	var cor_m := cor * 0.95 if not vidro else Color(0.3, 0.32, 0.34)
	_peca(Vector3(c.x, y + alt * 0.5, r.position.y + esp * 0.5), Vector3(r.size.x, alt, esp), Estilo.MACICO, cor_m)
	_peca(Vector3(c.x, y + alt * 0.5, r.end.y - esp * 0.5), Vector3(r.size.x, alt, esp), Estilo.MACICO, cor_m)
	_peca(Vector3(r.position.x + esp * 0.5, y + alt * 0.5, c.y), Vector3(esp, alt, r.size.y), Estilo.MACICO, cor_m)
	_peca(Vector3(r.end.x - esp * 0.5, y + alt * 0.5, c.y), Vector3(esp, alt, r.size.y), Estilo.MACICO, cor_m)
	_cornija(r, y, cor_m if vidro else cor)
	if not completo:
		return
	var livre := r.grow(-3.0)
	if livre.size.x < 6.0 or livre.size.y < 6.0:
		return
	var ponto := func(margem: Vector2) -> Vector2:
		return Vector2(rng.randf_range(livre.position.x + margem.x, livre.end.x - margem.x), rng.randf_range(livre.position.y + margem.y, livre.end.y - margem.y))
	# Casa de máquinas (com o poço do elevador mais alto)
	if h > 18.0 and livre.size.x > 14.0 and livre.size.y > 14.0:
		var m := Vector3(rng.randf_range(6.0, minf(12.0, livre.size.x * 0.5)), rng.randf_range(3.2, 4.5), rng.randf_range(6.0, minf(12.0, livre.size.y * 0.5)))
		var p: Vector2 = ponto.call(Vector2(m.x, m.z) * 0.5)
		_peca(Vector3(p.x, y + m.y * 0.5, p.y), m, Estilo.MACICO, Color(0.66, 0.65, 0.62), true)
		_peca(Vector3(p.x + m.x * 0.25, y + m.y + 0.9, p.y), Vector3(m.x * 0.4, 1.8, m.z * 0.6), Estilo.MACICO, Color(0.62, 0.61, 0.58))
	# Caixas d'água (prédios baixos e médios)
	if h < 120.0 and rng.randf() < 0.6:
		for k in rng.randi_range(1, 2):
			var p: Vector2 = ponto.call(Vector2(2.0, 2.0))
			_peca(Vector3(p.x, y + 2.6, p.y), Vector3(3.2, 1.8, 3.2), Estilo.MACICO, Color(0.55, 0.56, 0.6), true)
			for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				_peca(Vector3(p.x + s.x * 1.3, y + 0.85, p.y + s.y * 1.3), Vector3(0.15, 1.7, 0.15), Estilo.METAL, Color.WHITE)
	# Condensadoras de ar-condicionado
	var n_ar := int(clampf(livre.get_area() / 120.0, 1.0, 8.0) * rng.randf_range(0.4, 1.0))
	for k in n_ar:
		var p: Vector2 = ponto.call(Vector2(1.2, 1.2))
		_peca(Vector3(p.x, y + 0.8, p.y), Vector3(rng.randf_range(1.6, 2.6), 1.6, rng.randf_range(1.2, 2.0)), Estilo.METAL, Color.WHITE, true)
	# Arranha-céu: antenas; ou heliponto
	if h > 150.0:
		if rng.randf() < 0.35 and livre.size.x > 24.0 and livre.size.y > 24.0:
			_peca(Vector3(c.x, y + 0.25, c.y), Vector3(18.0, 0.5, 18.0), Estilo.HELIPONTO, Color.WHITE)
		else:
			for k in rng.randi_range(1, 3):
				var p: Vector2 = ponto.call(Vector2(1.0, 1.0))
				var a := rng.randf_range(8.0, 30.0)
				_peca(Vector3(p.x, y + a * 0.5, p.y), Vector3(0.5, a, 0.5), Estilo.METAL, Color.WHITE)
				_luz_baliza(Vector3(p.x, y + a + 0.4, p.y))


## Marquise do térreo nas quatro faces (prédios baixos de comércio).
func _marquise(r: Rect2, rng: RandomNumberGenerator) -> void:
	if rng.randf() < 0.35:
		return
	var prof := rng.randf_range(1.8, 2.6)
	var y := _chao + 4.55
	var cor := Color(0.22, 0.23, 0.25) if rng.randf() < 0.6 else Color(0.62, 0.2, 0.15)
	var c := r.get_center()
	_peca(Vector3(c.x, y, r.position.y - prof * 0.5), Vector3(r.size.x, 0.3, prof), Estilo.MACICO, cor)
	_peca(Vector3(c.x, y, r.end.y + prof * 0.5), Vector3(r.size.x, 0.3, prof), Estilo.MACICO, cor)
	_peca(Vector3(r.position.x - prof * 0.5, y, c.y), Vector3(prof, 0.3, r.size.y + prof * 2.0), Estilo.MACICO, cor)
	_peca(Vector3(r.end.x + prof * 0.5, y, c.y), Vector3(prof, 0.3, r.size.y + prof * 2.0), Estilo.MACICO, cor)


func _luz_baliza(p: Vector3) -> void:
	_balizas.append(Transform3D(Basis.from_scale(Vector3.ONE * 0.45), p))


func _estilo_para(h: float, rng: RandomNumberGenerator) -> int:
	var s := rng.randf()
	var lista: Array
	if h > 120.0:
		lista = [Estilo.VIDRO, Estilo.VIDRO, Estilo.VIDRO_ESCURO, Estilo.ESCRITORIO, Estilo.BRANCO, Estilo.ART_DECO, Estilo.CONCRETO]
	elif h > 45.0:
		lista = [Estilo.ESCRITORIO, Estilo.VIDRO, Estilo.BRANCO, Estilo.TIJOLO, Estilo.ART_DECO, Estilo.CONCRETO, Estilo.VIDRO_ESCURO]
	else:
		lista = [Estilo.TIJOLO, Estilo.TIJOLO, Estilo.ESCRITORIO, Estilo.BRANCO, Estilo.CONCRETO, Estilo.ART_DECO]
	return lista[int(s * lista.size()) % lista.size()]


## Tom da fachada conforme o estilo. Nas peles de vidro é a cor do próprio vidro.
static func _cor_para(estilo: int, rng: RandomNumberGenerator) -> Color:
	var cores: Array
	match estilo:
		Estilo.VIDRO:
			cores = [Color(0.35, 0.56, 0.62), Color(0.4, 0.52, 0.72), Color(0.42, 0.62, 0.5), Color(0.62, 0.65, 0.68), Color(0.26, 0.34, 0.5), Color(0.5, 0.62, 0.7)]
		Estilo.VIDRO_ESCURO:
			cores = [Color(0.22, 0.24, 0.27), Color(0.44, 0.33, 0.22), Color(0.2, 0.27, 0.25), Color(0.52, 0.44, 0.26), Color(0.16, 0.18, 0.24)]
		Estilo.TIJOLO:
			cores = [Color(1.0, 0.95, 0.9), Color(0.85, 0.7, 0.6), Color(1.0, 0.85, 0.7), Color(0.7, 0.65, 0.62), Color(0.95, 1.0, 0.95)]
		Estilo.ART_DECO:
			cores = [Color(0.9, 0.82, 0.68), Color(0.82, 0.74, 0.62), Color(0.95, 0.9, 0.8), Color(0.75, 0.68, 0.6), Color(0.86, 0.76, 0.7)]
		Estilo.CONCRETO:
			cores = [Color(0.66, 0.66, 0.64), Color(0.58, 0.6, 0.62), Color(0.74, 0.72, 0.68), Color(0.52, 0.52, 0.5)]
		_:
			cores = [Color(0.92, 0.9, 0.86), Color(0.85, 0.8, 0.72), Color(0.78, 0.82, 0.88), Color(0.9, 0.86, 0.8),
				Color(0.72, 0.74, 0.76), Color(0.95, 0.93, 0.9), Color(0.9, 0.78, 0.7), Color(0.78, 0.86, 0.8),
				Color(0.95, 0.88, 0.7), Color(0.86, 0.8, 0.86)]
	return (cores[rng.randi() % cores.size()] as Color) * rng.randf_range(0.88, 1.05)


# ------------------------------------------------------------------ visual

func _criar_visual(acesas: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/predio.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 4431))
	# Prédios em blocos de 600 m: cada bloco é cortado sozinho quando sai da tela/sombra
	var pecas: Array = []   # [Transform3D, estilo, cor, semente, acesas]
	for c: Array in _caixas:
		var r: Rect2 = c[0]
		var topo: float = c[1]
		var base := _chao - 2.0
		var centro := Vector3(r.get_center().x, (topo + base) * 0.5, r.get_center().y)
		pecas.append([Transform3D(Basis.from_scale(Vector3(r.size.x, topo - base, r.size.y)), centro), c[2], c[3], c[4], acesas])
	_multimesh_blocos(pecas, mat, 0.0, true)
	# Detalhes: sem sombra e somem de longe
	var det: Array = []
	for e: Array in _extras:
		det.append([e[0], e[1], e[2], 0.5, 0.0])
	_multimesh_blocos(det, mat, 1600.0, false)
	var verm := StandardMaterial3D.new()
	verm.albedo_color = Color(1.0, 0.1, 0.05)
	verm.emission_enabled = true
	verm.emission = Color(1.0, 0.1, 0.05)
	verm.emission_energy_multiplier = 2.0
	ComplexoLancamento.criar_multimesh(self, _balizas, verm, false)
	_luzes_torres()


## Colisão dos prédios: uma caixa por prédio em corpos estáticos de 600 m (camada 1, como pista e
## estruturas: as rodas apoiam no telhado e a câmera não atravessa a fachada). Grupo "predio": o
## Veiculo explode ao bater de lado (normal do contato na horizontal). As torres das plataformas
## ficam de fora (a rampa já tem a colisão dela; a borda da torre encosta no tabuleiro da descida).
## Os equipamentos do telhado entram em "predio_det": batem, mas não explodem.
func _criar_colisao() -> void:
	var caixas: Array = []
	for c: Array in _caixas:
		if int(c[2]) == Estilo.TORRE:
			continue
		var r: Rect2 = c[0]
		var base := _chao - 2.0
		caixas.append([Vector3(r.get_center().x, (float(c[1]) + base) * 0.5, r.get_center().y), Vector3(r.size.x, float(c[1]) - base, r.size.y)])
	_corpos_blocos(caixas, "predio")
	_corpos_blocos(_solidos, "predio_det")


func _corpos_blocos(caixas: Array, grupo: String) -> void:
	var blocos := {}
	for cx: Array in caixas:
		var o: Vector3 = cx[0]
		var k := Vector2i(floori(o.x / 600.0), floori(o.z / 600.0))
		if not blocos.has(k):
			var corpo := StaticBody3D.new()
			corpo.collision_layer = 1
			corpo.collision_mask = 0
			corpo.add_to_group(grupo)
			add_child(corpo)
			blocos[k] = corpo
		var forma := BoxShape3D.new()
		forma.size = cx[1]
		var cs := CollisionShape3D.new()
		cs.shape = forma
		cs.position = o
		(blocos[k] as StaticBody3D).add_child(cs)


func _multimesh_blocos(pecas: Array, mat: Material, alcance: float, sombra: bool) -> void:
	var blocos := {}
	for p: Array in pecas:
		var o: Vector3 = (p[0] as Transform3D).origin
		var k := Vector2i(floori(o.x / 600.0), floori(o.z / 600.0))
		if not blocos.has(k):
			blocos[k] = []
		blocos[k].append(p)
	for k in blocos:
		var lista: Array = blocos[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = BoxMesh.new()
		mm.instance_count = lista.size()
		for i in lista.size():
			var p: Array = lista[i]
			mm.set_instance_transform(i, p[0])
			mm.set_instance_color(i, p[2])
			mm.set_instance_custom_data(i, Color(p[3], (float(p[1]) + 0.5) / 8.0, p[4], 0.0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if sombra else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if alcance > 0.0:
			mi.visibility_range_end = alcance
			mi.visibility_range_end_margin = 200.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)



## Torres das plataformas: filetes de LED na cor da equipe nas quinas e anéis a cada 48 m,
## luz de balizamento vermelha nas quinas do telhado.
func _luzes_torres() -> void:
	for t: Array in _torres:
		var r: Rect2 = t[0]
		var cor: Color = t[2]
		var topo := _terreno._topo_mesa
		var leds: Array[Transform3D] = []
		var cantos := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
		var meio_y := (topo + _chao + 26.0) * 0.5
		var alt := topo - (_chao + 26.0)
		for k in 4:
			var p: Vector2 = cantos[k]
			var fora := (p - r.get_center()).normalized() * 0.35
			leds.append(Transform3D(Basis.from_scale(Vector3(0.5, alt, 0.5)), Vector3(p.x + fora.x, meio_y, p.y + fora.y)))
		var y := _chao + 26.0 + 48.0
		while y < topo - 10.0:
			for lado in 4:
				var a: Vector2 = cantos[lado]
				var b: Vector2 = cantos[(lado + 1) % 4]
				var m := (a + b) * 0.5
				var fora := (m - r.get_center()).normalized() * 0.3
				var comprimento := a.distance_to(b)
				var ao_x := absf(b.x - a.x) > 1.0
				leds.append(Transform3D(Basis.from_scale(Vector3(comprimento if ao_x else 0.4, 0.45, 0.4 if ao_x else comprimento)), Vector3(m.x + fora.x, y, m.y + fora.y)))
			y += 48.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = cor
		mat.emission_enabled = true
		mat.emission = cor
		mat.emission_energy_multiplier = 3.5
		ComplexoLancamento.criar_multimesh(self, leds, mat, false)
		var balizas: Array[Transform3D] = []
		for p: Vector2 in cantos:
			balizas.append(Transform3D(Basis.from_scale(Vector3.ONE * 1.2), Vector3(p.x, topo + 2.5, p.y)))
			balizas.append(Transform3D(Basis.from_scale(Vector3(0.3, 2.5, 0.3)), Vector3(p.x, topo + 1.25, p.y)))
		var verm := StandardMaterial3D.new()
		verm.albedo_color = Color(1.0, 0.1, 0.05)
		verm.emission_enabled = true
		verm.emission = Color(1.0, 0.1, 0.05)
		verm.emission_energy_multiplier = 2.0
		ComplexoLancamento.criar_multimesh(self, balizas, verm, false)
