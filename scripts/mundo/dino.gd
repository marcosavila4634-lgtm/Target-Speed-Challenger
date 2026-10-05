class_name Dino
extends Node3D
## Extinction Day (mapa.subida.dino): parque dos dinossauros numa selva pré-histórica.
## - vulcão no meio do vale (cratera com lago de lava, rios de lava descendo os flancos em leitos
##   cavados, fumaça saindo da cratera) e o túnel da etapa 1 por dentro dele (TunelVulcao);
## - estradas sempre acima do terreno: o relevo é cortado ao longo delas (corte de estrada);
## - floresta de árvores gigantes (sequoias e araucárias), fetos arborescentes, cicas e samambaias;
## - estruturas do parque (portão, cercas elétricas, recinto dos raptores, jaula, ruínas, crânio de
##   tricerátopo) e dinossauros andando (DinosParque);
## - céu da etapa (dia, noite com aurora, apocalipse) e o meteoro chegando (CeuDino).

const CEL := 50.0

var penhasco := 320.0
var centro_vulcao := Vector2(-400, -1150)
var borda_vulcao := 230.0
var base_vulcao := 1000.0
var altura_vulcao := 560.0
var fundo_cratera := 430.0
var lava_cratera := 438.0
## Liga/desliga o corte das estradas (a capa de rocha do túnel usa a encosta natural)
var sem_estrada := false

var _terreno: Terreno
var _cfg: Dictionary = {}
var _segs := {}                     # célula → [[a: Vector3, b: Vector3], ...] de todas as estradas
var _estradas: Array = []           # PackedVector3Array dos pontos de controle de cada trecho
var _lagos: Array = []              # [centro Vector2, raio, nível]
var _crateras: Array = []           # [centro Vector2, raio, profundidade, borda, nível do chão]
const CRATERA_FORA := 1.75          # até onde vai o manto de ejeção (em raios da cratera)
var _rios: Array = []               # [{pts: PackedVector3Array (x, nível, z), larg}]
var _rios_cel := {}                 # célula → [[rio, i], ...]
var _evitar: Array = []             # [centro Vector2, raio] sem cenário (cercados, alvos)
var _corredores: Array = []         # [a, b, meia-largura] voo da rampa final ao alvo
var _alvos: Array = []              # Vector2 de cada etapa
var _etapa_no: Node3D
var ceu: CeuDino
var parque: DinosParque
var tuneis: Array = []              # TunelVulcao montados (permanentes: a capa de rocha cobre a vala)


# ------------------------------------------------------------------ preparação (antes do terreno)

func preparar(terreno: Terreno) -> void:
	_terreno = terreno
	_cfg = Config.valor("mapa.subida.dino", {})
	penhasco = float(_cfg.get("penhasco", 320.0))
	var v: Dictionary = _cfg.get("vulcao", {})
	var c: Array = v.get("centro", [-400, -1150])
	centro_vulcao = Vector2(float(c[0]), float(c[1]))
	borda_vulcao = float(v.get("borda", 230))
	base_vulcao = float(v.get("base", 1000))
	altura_vulcao = float(v.get("altura", 560))
	fundo_cratera = float(v.get("fundo", 430))
	lava_cratera = float(v.get("lava", 438))
	for l in _cfg.get("lagos_lava", []):
		_lagos.append([Vector2(float(l[0]), float(l[1])), float(l[2]), float(l[3]) if l.size() > 3 else 3.0])
	for cr in _cfg.get("crateras", []):
		_crateras.append([Vector2(float(cr[0]), float(cr[1])), float(cr[2]), float(cr[3]), float(cr[4]), float(cr[5]), cr.size() > 6 and bool(cr[6])])
		_evitar.append([Vector2(float(cr[0]), float(cr[1])), float(cr[2]) * CRATERA_FORA + 10.0])
	_preparar_rios()
	# Estradas de todas as etapas (o relevo é cortado ao longo delas; o cenário não pode atravessar)
	var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
	var etapas: Array = Config.valor("etapas", [])
	for k in percursos:
		var pc: Dictionary = percursos[k]
		var trechos: Dictionary = pc.get("trechos", {})
		# Trechos e desvios (o relevo é cortado ao longo de todos e o cenário não pode atravessar nenhum)
		var listas: Array = [trechos.get("A", []), trechos.get("B", []), trechos.get("C", [])]
		for dv in pc.get("desvios", []):
			listas.append((dv as Dictionary).get("pontos", []))
		for lista_p: Array in listas:
			var pts := PackedVector3Array()
			for p in lista_p:
				pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			if pts.size() < 2:
				continue
			_estradas.append(pts)
			for i in range(1, pts.size()):
				var a := pts[i - 1]
				var b := pts[i]
				var r := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(60.0)
				for cx in range(floori(r.position.x / CEL), floori(r.end.x / CEL) + 1):
					for cz in range(floori(r.position.y / CEL), floori(r.end.y / CEL) + 1):
						var chave := Vector2i(cx, cz)
						if not _segs.has(chave):
							_segs[chave] = []
						_segs[chave].append([a, b])
		# O vão do salto (fim do B → começo do C) também é cortado: dentro do túnel, sem isso a encosta
		# fechava o vão (bloco preto no meio do túnel)
		var tb: Array = trechos.get("B", [])
		var tc: Array = trechos.get("C", [])
		if not tb.is_empty() and not tc.is_empty():
			var a := Vector3(float(tb.back()[0]), float(tb.back()[1]), float(tb.back()[2]))
			var b := Vector3(float(tc[0][0]), float(tc[0][1]), float(tc[0][2]))
			var r := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(60.0)
			for cx in range(floori(r.position.x / CEL), floori(r.end.x / CEL) + 1):
				for cz in range(floori(r.position.y / CEL), floori(r.end.y / CEL) + 1):
					var chave_v := Vector2i(cx, cz)
					if not _segs.has(chave_v):
						_segs[chave_v] = []
					_segs[chave_v].append([a, b])
		for chave in ["largada", "plataforma"]:
			var rc: Dictionary = pc.get(chave, {})
			if rc.is_empty():
				continue
			var o: Array = rc.get("origem", [0, 0, 0])
			var f: Array = rc.get("frente", [0, -1])
			var comp := float(rc.get("comprimento", 70))
			var larg := float(rc.get("largura", 90))
			var c2 := Vector2(float(o[0]), float(o[2])) + Vector2(float(f[0]), float(f[1])) * comp * 0.5
			_evitar.append([c2, maxf(comp, larg) * 0.75 + 30.0])
		var idx := int(k) - 1
		var fim: Array = trechos.get("C", [[0, 0, 0]]).back()
		if idx < etapas.size():
			var d: Array = (etapas[idx] as Dictionary).get("deslocamento", [0, 0])
			var alvo := Vector2(float(d[0]), float(d[1]))
			_alvos.append(alvo)
			_evitar.append([alvo, 140.0])
			_corredores.append([Vector2(float(fim[0]), float(fim[2])), alvo, 120.0])


## Rios de lava (dino.rios_lava: [ângulo em graus, meia-largura]): descem da borda da cratera pelo
## flanco, serpenteando, até o pé do vulcão. Pontos (x, nível da lava, z) a cada 20 m.
func _preparar_rios() -> void:
	for r in _cfg.get("rios_lava", []):
		var ang := deg_to_rad(float(r[0]))
		var larg := float(r[1]) if r.size() > 1 else 9.0
		var fim := float(r[2]) if r.size() > 2 else base_vulcao + 120.0
		var pts := PackedVector3Array()
		var dist := borda_vulcao - 20.0
		while dist <= fim:
			var a := ang + 0.11 * sin(dist / 95.0 + float(r[0])) + 0.05 * sin(dist / 37.0)
			var p := centro_vulcao + Vector2(cos(a), sin(a)) * dist
			pts.append(Vector3(p.x, 0.0, p.y))
			dist += 20.0
		# Nível da lava: um pouco abaixo da encosta (o leito é cavado em volta)
		for i in pts.size():
			var q := pts[i]
			q.y = maxf(vulcao(q.x, q.z), 6.5) - 3.5
			pts[i] = q
		var rio := {"pts": pts, "larg": larg}
		_rios.append(rio)
		var n := _rios.size() - 1
		for i in range(1, pts.size()):
			var r2 := Rect2(Vector2(pts[i - 1].x, pts[i - 1].z), Vector2.ZERO).expand(Vector2(pts[i].x, pts[i].z)).grow(larg + 40.0)
			for cx in range(floori(r2.position.x / CEL), floori(r2.end.x / CEL) + 1):
				for cz in range(floori(r2.position.y / CEL), floori(r2.end.y / CEL) + 1):
					var chave := Vector2i(cx, cz)
					if not _rios_cel.has(chave):
						_rios_cel[chave] = []
					_rios_cel[chave].append([n, i])


# ------------------------------------------------------------------ relevo

## Encosta do vulcão em (x, z): cone côncavo do pé (base) até a borda da cratera, que afunda até o
## fundo; ravinas na encosta. -INF fora dele.
func vulcao(x: float, z: float) -> float:
	var d := Vector2(x, z) - centro_vulcao
	var r := d.length()
	if r >= base_vulcao:
		return -INF
	if r < borda_vulcao:
		var f := clampf((r - 120.0) / (borda_vulcao - 120.0), 0.0, 1.0)
		return fundo_cratera + (altura_vulcao - fundo_cratera) * f * f * (3.0 - 2.0 * f)
	var t := (r - borda_vulcao) / (base_vulcao - borda_vulcao)
	var s := t * t * (3.0 - 2.0 * t)
	var h := altura_vulcao * pow(1.0 - s, 1.4)
	# Ravinas e espinhaços descendo o flanco (mais fundos no meio da encosta)
	var ang := atan2(d.y, d.x)
	var sulco := sin(ang * 9.0 + 2.0 * sin(ang * 3.0)) * 0.5 + sin(ang * 23.0 + r * 0.004) * 0.2
	var grosso := sin(ang * 5.0 + 1.3) * sin(r * 0.011 + ang * 2.0)
	return h + (sulco * 30.0 + grosso * 16.0) * sin(PI * t)


## Relevo do mapa: vulcão, leitos dos rios de lava, bacias dos lagos de lava e o corte das estradas.
func relevo(x: float, z: float, h: float) -> float:
	h = maxf(h, vulcao(x, z))
	var p := Vector2(x, z)
	# Lagos de lava: bacia com o fundo 4 m abaixo da lava
	for l: Array in _lagos:
		var d := p.distance_to(l[0])
		var r: float = l[1]
		if d < r + 80.0:
			h = minf(h, lerpf(float(l[2]) - 4.0, h, smoothstep(r * 0.9, r + 60.0, d)))
	# Crateras de impacto: o terreno (malha grossa) fica um pouco abaixo da malha fina da cratera
	for c: Array in _crateras:
		var q: Vector2 = p - c[0]
		var u := q.length() / float(c[1])
		if u < 1.25:
			h = minf(h, perfil_cratera(c, q) - lerpf(4.0, 1.0, smoothstep(0.7, 1.0, u)))
	# Leitos dos rios de lava
	var chave := Vector2i(floori(x / CEL), floori(z / CEL))
	for par: Array in _rios_cel.get(chave, []):
		var rio: Dictionary = _rios[par[0]]
		var pts: PackedVector3Array = rio.pts
		var i: int = par[1]
		var a := Vector2(pts[i - 1].x, pts[i - 1].z)
		var ab := Vector2(pts[i].x, pts[i].z) - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		var nivel := lerpf(pts[i - 1].y, pts[i].y, t)
		var larg: float = rio.larg
		h = minf(h, lerpf(nivel - 3.0, h, smoothstep(larg * 0.8, larg + 26.0, d)))
	if sem_estrada:
		return h
	# Corte das estradas: nada do relevo acima da estrada (fica 7 m abaixo dela numa faixa de 22 m
	# para cada lado e sobe até o natural em 30 m — a malha do terreno tem um ponto a cada ~13 m)
	for seg: Array in _segs.get(chave, []):
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		var d := p.distance_to(a2 + ab * t)
		if d > 52.0:
			continue
		var y := lerpf(a.y, b.y, t)
		if h > y - 7.0:
			h = minf(h, lerpf(y - 7.0, h, smoothstep(22.0, 52.0, d)))
	return h


## Cratera de impacto (dino.crateras: [x, z, raio, profundidade, borda, nível do chão]) — altura da
## superfície no ponto `q` medido do centro. Cratera simples: fundo quase plano, parede cada vez
## mais íngreme até a borda levantada (irregular, em lóbulos), degraus de desmoronamento na parede
## e, por fora, o manto de ejeção caindo depressa, com raios.
static func perfil_cratera(c: Array, q: Vector2) -> float:
	var ang := atan2(q.y, q.x)
	var lobulo := 1.0 + 0.06 * sin(ang * 3.0 + 0.7) + 0.035 * sin(ang * 7.0 + 2.1) + 0.02 * sin(ang * 13.0)
	var u := q.length() / float(c[1]) / lobulo
	var prof := float(c[2])
	var borda := float(c[3]) * (1.0 + 0.18 * sin(ang * 5.0 + 0.4))
	var h: float
	if u < 1.0:
		h = -prof + (prof + borda) * pow(u, 2.6)
		h += 1.3 * sin(u * 9.0 + ang * 2.0) * smoothstep(0.35, 0.8, u) * (1.0 - smoothstep(0.85, 1.0, u))
	else:
		h = borda * pow(u, -3.2) * (1.0 + 0.45 * sin(ang * 11.0 + 1.3) * smoothstep(1.0, 1.25, u))
		h *= 1.0 - smoothstep(1.3, CRATERA_FORA, u)
	return float(c[4]) + h


## Superfície da lava (mortal) em (x, z): lagos, rios e a cratera. -INF fora.
func altura(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var h := -INF

	for l: Array in _lagos:
		if p.distance_to(l[0]) < float(l[1]):
			h = maxf(h, float(l[2]))
	if p.distance_to(centro_vulcao) < 150.0:
		h = maxf(h, lava_cratera)
	var chave := Vector2i(floori(x / CEL), floori(z / CEL))
	for par: Array in _rios_cel.get(chave, []):
		var rio: Dictionary = _rios[par[0]]
		var pts: PackedVector3Array = rio.pts
		var i: int = par[1]
		var a := Vector2(pts[i - 1].x, pts[i - 1].z)
		var ab := Vector2(pts[i].x, pts[i].z) - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) < float(rio.larg):
			h = maxf(h, lerpf(pts[i - 1].y, pts[i].y, t))
	return h


## Máscara para o shader do terreno: R = brilho da lava por perto (leitos, lagos, cratera), G = chão
## vulcânico (cinza e basalto) pela distância ao vulcão.
func textura_mascara(meio: float) -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_RG8)
	var passo := meio * 2.0 / n
	for iz in n:
		for ix in n:
			var x := -meio + (ix + 0.5) * passo
			var z := -meio + (iz + 0.5) * passo
			var p := Vector2(x, z)
			var lava := INF
			for l: Array in _lagos:
				lava = minf(lava, p.distance_to(l[0]) - float(l[1]))
			lava = minf(lava, p.distance_to(centro_vulcao) - 150.0)
			var chave := Vector2i(floori(x / CEL), floori(z / CEL))
			for par: Array in _rios_cel.get(chave, []):
				var rio: Dictionary = _rios[par[0]]
				var pts: PackedVector3Array = rio.pts
				var i: int = par[1]
				var a := Vector2(pts[i - 1].x, pts[i - 1].z)
				var ab := Vector2(pts[i].x, pts[i].z) - a
				var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
				lava = minf(lava, p.distance_to(a + ab * t) - float(rio.larg))
			var r := p.distance_to(centro_vulcao)
			var vulc := clampf(1.0 - (r - base_vulcao * 0.75) / (base_vulcao * 0.5), 0.0, 1.0)
			img.set_pixel(ix, iz, Color(clampf(1.0 - lava / 45.0, 0.0, 1.0), vulc, 0.0))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ montagem

func montar() -> void:
	var sem := OS.get_environment("TSC_DINO_SEM")
	_montar_lava()
	_montar_crateras()
	_montar_tuneis()
	if not "a" in sem:
		_montar_vegetacao()
	if not "o" in sem:
		_montar_objetos()
	if not "d" in sem:
		parque = DinosParque.new()
		parque.name = "Dinossauros"
		add_child(parque)
		parque.montar(self, _terreno, _cfg.get("dinos", {}))
	ceu = CeuDino.new()
	ceu.name = "Ceu"
	add_child(ceu)
	ceu.montar(self, _terreno, _cfg)
	_etapa_no = Node3D.new()
	_etapa_no.name = "Etapa"
	add_child(_etapa_no)


## Troca o que muda por etapa: céu (dia, noite, aurora, apocalipse), meteoro e luzes neon.
func preparar_etapa(indice: int, cfg_etapa: Dictionary) -> void:
	for f in _etapa_no.get_children():
		f.queue_free()
	if ceu:
		ceu.preparar_etapa(indice, cfg_etapa)
	if parque:
		parque.preparar_etapa(indice)
	if not "o" in OS.get_environment("TSC_DINO_SEM"):
		_montar_objetos(indice + 1, _etapa_no)
	# Gigantes caminhando pelo ambiente da etapa (dino.rondas; pedido do dono para a etapa 4)
	if not "d" in OS.get_environment("TSC_DINO_SEM"):
		for r in (_cfg.get("rondas", {}) as Dictionary).get(str(indice + 1), []):
			var ronda: Node3D = load("res://scripts/mundo/ronda_dino.gd").new()
			ronda.name = "RondaEtapa"
			ronda.position = Vector3(float(r[0]), 0.0, float(r[1]))
			_etapa_no.add_child(ronda)
			ronda.montar(_terreno, r[2])


## Livre para cenário: fora da lava, dos cercados/alvos, dos corredores de voo (para o que é alto) e
## longe de qualquer estrada que passe mais baixo que o topo do objeto.
func livre(p: Vector2, alto: float, folga := 0.0) -> bool:
	if altura(p.x, p.y) > -INF:
		return false
	for e: Array in _evitar:
		if p.distance_to(e[0]) < float(e[1]) + folga:
			return false
	if alto > 25.0:
		for c: Array in _corredores:
			var a: Vector2 = c[0]
			var ab: Vector2 = c[1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), -0.1, 1.2)
			if p.distance_to(a + ab * t) < float(c[2]) + folga:
				return false
	return not estrada_perto(p, _terreno.altura_em(p.x, p.y), alto, folga)


func estrada_perto(p: Vector2, chao: float, alto: float, folga := 0.0) -> bool:
	for seg: Array in _segs.get(Vector2i(floori(p.x / CEL), floori(p.y / CEL)), []):
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if p.distance_to(a2 + ab * t) < 18.0 + alto * 0.2 + folga and lerpf(a.y, b.y, t) - 10.0 < chao + alto * 1.45:   # folga larga: o modelo passa da altura nominal e a copa abre (árvore não pode furar a pista)
			return true
	return false


## Distância horizontal até a estrada mais perto (de qualquer etapa), até 60 m.
func dist_estrada(p: Vector2) -> float:
	var melhor := 60.0
	for seg: Array in _segs.get(Vector2i(floori(p.x / CEL), floori(p.y / CEL)), []):
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		melhor = minf(melhor, p.distance_to(a2 + ab * t))
	return melhor


func plano(x: float, z: float, limite: float) -> bool:
	var dx := _terreno.altura_em(x + 6.0, z) - _terreno.altura_em(x - 6.0, z)
	var dz := _terreno.altura_em(x, z + 6.0) - _terreno.altura_em(x, z - 6.0)
	return absf(dx) + absf(dz) <= limite


# ------------------------------------------------------------------ lava

static var _mats := {}

## Material da lava (shaders/lava.gdshader) com as texturas da pasta assets/dino/lava.
## modo 0 = rio/lago deitado, 1 = cascata na parede.
static func material_lava(modo: int, velocidade: float, calor := 1.0, escala := 9.0, energia := 5.5, largura := 20.0, mundo := false) -> ShaderMaterial:
	var chave := "lava_%d_%.2f_%.2f_%.1f_%.1f_%.1f_%s" % [modo, velocidade, calor, escala, energia, largura, str(mundo)]
	if _mats.has(chave):
		return _mats[chave]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/lava.gdshader")
	m.set_shader_parameter("modo", modo)
	m.set_shader_parameter("tex_base", load("res://assets/dino/lava/lava_base.png"))
	m.set_shader_parameter("tex_brilho", load("res://assets/dino/lava/lava_emissao.png"))
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 251))
	m.set_shader_parameter("velocidade", velocidade)
	m.set_shader_parameter("calor", calor)
	m.set_shader_parameter("escala", escala)
	m.set_shader_parameter("energia", energia)
	m.set_shader_parameter("largura", largura)
	m.set_shader_parameter("mundo", mundo)
	_mats[chave] = m
	return m


## Disco de lava (cratera, lagos): UV.x vai de 0,5 no meio a 1 na margem; UV.y = metros (z local).
static func _malha_disco(raio: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var aneis := 10
	var lados := 64
	for a in aneis:
		for k in lados:
			var q := []
			for par: Array in [[a, k], [a, k + 1], [a + 1, k + 1], [a + 1, k]]:
				var r := raio * float(par[0]) / aneis
				var ang := TAU * float(par[1]) / lados
				var p := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
				q.append([p, Vector2(0.5 + 0.5 * r / raio, p.z)])
			for i: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(q[i][1])
				st.add_vertex(q[i][0])
	return st.commit()


## Crateras de impacto: malha fina em anéis (o terreno tem um ponto a cada ~13 m e não daria o
## detalhe), pedras arrancadas espalhadas pelo fundo e pela borda, e focos de fogo no fundo.
## A malha tem colisão no grupo "mortal": cair nela é cair no chão (o terreno fica uns metros abaixo).
func _montar_crateras() -> void:
	for c: Array in _crateras:
		var centro: Vector2 = c[0]
		var raio: float = c[1]
		var no := Node3D.new()
		no.name = "Cratera"
		no.position = Vector3(centro.x, 0.0, centro.y)
		add_child(no)
		if OS.get_environment("TSC_SUB_LOG") != "":
			print("[DINO] cratera em ", centro, ": terreno no centro ", _terreno.altura_em(centro.x, centro.y), ", na borda ", _terreno.altura_em(centro.x + raio, centro.y), ", fora ", _terreno.altura_em(centro.x + raio * 1.6, centro.y), " ", _terreno.altura_em(centro.x, centro.y + raio * 1.6), " ", _terreno.altura_em(centro.x - raio * 1.6, centro.y))
		var rugoso := FastNoiseLite.new()
		rugoso.seed = 77
		rugoso.frequency = 0.07
		rugoso.fractal_octaves = 3
		const SEGS := 128
		var aneis := int(raio * CRATERA_FORA / 2.2)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		for i in aneis + 1:
			var d := raio * CRATERA_FORA * float(i) / aneis
			var u := d / raio
			for k in SEGS:
				var a := TAU * k / SEGS
				var q := Vector2(cos(a), sin(a)) * d
				var y := perfil_cratera(c, q) + rugoso.get_noise_2d(q.x, q.y) * lerpf(0.25, 0.9, smoothstep(0.3, 1.0, u))
				# Por fora da borda a malha vai assentando no terreno
				var chao := _terreno.altura_em(centro.x + q.x, centro.y + q.y) + 0.3
				y = lerpf(y, chao, smoothstep(1.3, CRATERA_FORA - 0.05, u)) if u > 1.0 else y
				y = maxf(y, chao) if u > 1.05 else y
				st.add_vertex(Vector3(q.x, y, q.y))
		for i in aneis:
			for k in SEGS:
				var a0 := i * SEGS + k
				var a1 := i * SEGS + (k + 1) % SEGS
				var b0 := a0 + SEGS
				var b1 := a1 + SEGS
				st.add_index(a0); st.add_index(b1); st.add_index(a1)
				st.add_index(a0); st.add_index(b0); st.add_index(b1)
		st.generate_normals()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/cratera.gdshader")
		mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 331))
		mat.set_shader_parameter("ruido_fino", Terreno._textura_ruido(0.08, 4, 337))
		mat.set_shader_parameter("raio", raio)
		mat.set_shader_parameter("fora", CRATERA_FORA)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no.add_child(mi)
		var corpo := StaticBody3D.new()
		corpo.collision_layer = 1
		corpo.collision_mask = 0
		corpo.add_to_group("mortal")
		var forma := ConcavePolygonShape3D.new()
		forma.backface_collision = true
		forma.set_faces((mi.mesh as ArrayMesh).get_faces())
		var cs := CollisionShape3D.new()
		cs.shape = forma
		corpo.add_child(cs)
		no.add_child(corpo)
		# Pedras arrancadas: muitas pequenas no fundo e na parede, blocos maiores na borda e no manto
		var pedra := SphereMesh.new()
		pedra.radius = 1.0
		pedra.height = 1.7
		pedra.radial_segments = 7
		pedra.rings = 4
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var pedras: Array[Transform3D] = []
		for k in 150:
			var a := rng.randf() * TAU
			var u := rng.randf_range(0.42, 1.45)
			var q := Vector2(cos(a), sin(a)) * raio * u
			var tam := rng.randf_range(0.5, 1.6) * (2.2 if absf(u - 1.0) < 0.15 and rng.randf() < 0.4 else 1.0)
			var y := perfil_cratera(c, q)
			if u > 1.05:
				y = maxf(y, _terreno.altura_em(centro.x + q.x, centro.y + q.y))
			var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)) * Basis.from_scale(Vector3.ONE * tam)
			pedras.append(Transform3D(b, Vector3(q.x, y + tam * 0.25, q.y)))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pedra
		mm.instance_count = pedras.size()
		for k in pedras.size():
			mm.set_instance_transform(k, pedras[k])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = AlvoDino._rocha_mat()
		no.add_child(mmi)
		if c.size() > 5 and bool(c[5]):
			_carcacas(no, c, rng)
			# Dinossauros gigantes caminhando em volta da cratera (pedido do dono)
			var ronda: Node3D = load("res://scripts/mundo/ronda_dino.gd").new()
			ronda.name = "Ronda"
			no.add_child(ronda)
			ronda.montar(_terreno, [["titanossauro", 120.0, raio * 1.7, 5.5], ["titanossauro", 100.0, raio * 2.4, 5.0], ["titanossauro", 135.0, raio * 2.4, 5.0], ["espinossauro", 60.0, raio * 1.7, -7.0], ["trex", 52.0, raio * 3.0, -7.5]])
		# Focos de fogo no fundo (o mato e as raízes ainda queimam)
		for k in 7:
			var a := TAU * (k + rng.randf() * 0.6) / 7.0
			var q := Vector2(cos(a), sin(a)) * raio * rng.randf_range(0.45, 0.7)
			no.add_child(_chama(Vector3(q.x, perfil_cratera(c, q) + 0.4, q.y), rng.randf_range(1.6, 2.8)))


## Dinossauros gigantes mortos e em chamas e ossadas espalhados pela cratera (7º valor da cratera = true;
## pedido do dono para o alvo da etapa 1): titanossauros tombados de lado na parede da cratera, com
## sem fogo (o dono mandou tirar), e costelas e colunas de osso meio enterradas no fundo.
func _carcacas(no: Node3D, c: Array, rng: RandomNumberGenerator) -> void:
	var raio: float = c[1]
	for k in 3:
		var a := TAU * (float(k) + 0.25) / 3.0 + rng.randf() * 0.5
		var q := Vector2(cos(a), sin(a)) * raio * rng.randf_range(0.62, 0.8)
		var comp := rng.randf_range(30.0, 40.0) * 1.3   # 30% maiores (pedido do dono)
		var d := DinosParque.criar("titanossauro", comp)
		var raiz: Node3D = d.raiz
		DinosParque.pose(d, k * 1.7, 0.6, 0.6, 0.0)
		# Tombado de lado, acompanhando a parede (a barriga para o meio da cratera)
		var tang := Vector3(-sin(a), 0.0, cos(a))
		var bz := Basis.looking_at(tang, Vector3.UP) * Basis(Vector3.FORWARD, PI * 0.5 * (1.0 if k % 2 == 0 else -1.0))
		var larg_corpo := comp * 0.1   # mais para fora do chão (ficavam quase enterrados)
		raiz.transform = Transform3D(bz, Vector3(q.x, perfil_cratera(c, q) + larg_corpo, q.y))
		no.add_child(raiz)
	# Ossadas (o dono achou as de anéis e viga "muito artificiais"): coluna de vértebras com espinhos, em
	# curva e afinando para a cauda; costelas em arco, afiladas, tortas, algumas quebradas, com as pontas
	# enterradas; o esqueleto meio tombado e um crânio na ponta. Osso manchado e chamuscado.
	var osso := StandardMaterial3D.new()
	osso.albedo_color = Color(1.0, 0.93, 0.78)
	osso.albedo_texture = Terreno._textura_ruido(0.02, 4, 613)
	osso.uv1_triplanar = true
	osso.uv1_scale = Vector3(0.35, 0.35, 0.35)
	osso.roughness = 0.95
	var peca := CylinderMesh.new()
	peca.top_radius = 0.8
	peca.bottom_radius = 1.0
	peca.height = 1.0
	peca.radial_segments = 7
	peca.rings = 1
	var ossos: Array[Transform3D] = []
	var seg := func(a: Vector3, b: Vector3, r: float) -> void:
		var d := b - a
		if d.length() > 0.02:
			ossos.append(Transform3D(ComplexoArena._base_eixo(d.normalized()) * Basis.from_scale(Vector3(r, d.length() * 1.08, r)), (a + b) * 0.5))
	var cena_cranio: PackedScene = load("res://assets/dino/cranio/cranio.glb") if ResourceLoader.exists("res://assets/dino/cranio/cranio.glb") else null
	for k in 5:
		var a := rng.randf() * TAU
		var q := Vector2(cos(a), sin(a)) * raio * rng.randf_range(0.42, 0.9)
		var rumo := rng.randf() * TAU
		var tam := rng.randf_range(2.6, 4.4) * 1.3   # 30% maiores (pedido do dono)
		var tomba := rng.randf_range(-0.45, 0.45)
		var curva := rng.randf_range(-0.05, 0.05)
		const VERT := 18
		var ant := Vector3.ZERO
		var p_s := Vector3(q.x, 0.0, q.y)
		var ang_s := rumo
		for j in VERT:
			var eixo := Vector3(cos(ang_s), 0.0, sin(ang_s))
			var lado := eixo.cross(Vector3.UP)
			var torax := j >= 3 and j <= 9
			# Altura da coluna: alta no tórax, descendo para o pescoço e para a cauda
			var arco := sin(clampf(float(j) / 11.0, 0.0, 1.0) * PI)
			var r_cost := tam * (0.55 + 0.4 * arco) * (1.0 - 0.06 * absf(float(j) - 6.0))
			var hs := tam * (0.12 + 0.85 * arco) * (1.0 if j <= 11 else maxf(1.0 - 0.14 * (j - 11), 0.05))
			var chao := perfil_cratera(c, Vector2(p_s.x, p_s.z)) - tam * 0.08
			var cima := (Vector3.UP * cos(tomba) + lado * sin(tomba)).normalized()
			var lado_t := eixo.cross(cima)
			var v := Vector3(p_s.x, chao, p_s.z) + cima * hs
			var grosso := tam * 0.19 * (1.0 - 0.045 * j)
			if j > 0:
				seg.call(ant, v, grosso)
			# Espinho da vértebra
			seg.call(v, v + cima * tam * (0.34 if torax else 0.16) * rng.randf_range(0.7, 1.1) - eixo * tam * 0.08, grosso * 0.45)
			if torax:
				for s: float in [-1.0, 1.0]:
					var n_seg := 6 if rng.randf() > 0.3 else rng.randi_range(2, 4)   # algumas quebradas
					var torto := rng.randf_range(-0.18, 0.18)
					var p_ant := v
					for u in n_seg:
						var th := 2.3 * float(u + 1) / 6.0
						var pr := v + lado_t * s * r_cost * sin(th) - cima * r_cost * (1.0 - cos(th)) + eixo * (torto * r_cost * sin(th) - 0.12 * tam * float(u + 1) / 6.0)
						seg.call(p_ant, pr, tam * lerpf(0.11, 0.045, float(u) / 5.0))
						p_ant = pr
			ant = v
			p_s += eixo * tam * (0.5 if j <= 11 else 0.42)
			ang_s += curva + rng.randf_range(-0.03, 0.03)
		# Crânio na ponta do pescoço, meio enterrado e virado de lado
		if cena_cranio:
			var cr: Node3D = cena_cranio.instantiate()
			var maior := 0.0
			for gi in cr.find_children("*", "MeshInstance3D", true, false):
				var sz: Vector3 = (gi as MeshInstance3D).get_aabb().size * (gi as Node3D).transform.basis.get_scale()
				maior = maxf(maior, maxf(sz.x, maxf(sz.y, sz.z)))
			var esc_c := tam * 1.5 / maxf(maior, 0.01)
			var pc := Vector3(q.x, 0.0, q.y) - Vector3(cos(rumo), 0.0, sin(rumo)) * tam * 0.9
			cr.transform = Transform3D(Basis(Vector3.UP, -rumo + rng.randf_range(-0.6, 0.6)) * Basis(Vector3.FORWARD, rng.randf_range(-0.5, 0.5)) * Basis.from_scale(Vector3.ONE * esc_c), Vector3(pc.x, perfil_cratera(c, Vector2(pc.x, pc.z)) - tam * 0.05, pc.z))
			no.add_child(cr)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = peca
	mm.instance_count = ossos.size()
	for k in ossos.size():
		mm.set_instance_transform(k, ossos[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = osso
	no.add_child(mmi)


func _montar_lava() -> void:
	var no := Node3D.new()
	no.name = "Lava"
	add_child(no)
	# Lago de lava na cratera e a luz dele (vista de longe à noite)
	var cratera := MeshInstance3D.new()
	cratera.mesh = _malha_disco(160.0)
	cratera.material_override = material_lava(0, 0.06, 0.8, 26.0, 6.0, 20.0, true)
	cratera.position = Vector3(centro_vulcao.x, lava_cratera, centro_vulcao.y)
	cratera.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	no.add_child(cratera)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.42, 0.12)
	luz.light_energy = 9.0
	luz.omni_range = 520.0
	luz.omni_attenuation = 1.4
	luz.position = Vector3(centro_vulcao.x, lava_cratera + 40.0, centro_vulcao.y)
	no.add_child(luz)
	# Lagos de lava
	for l: Array in _lagos:
		var mi := MeshInstance3D.new()
		mi.mesh = _malha_disco(float(l[1]) + 6.0)
		mi.material_override = material_lava(0, 0.05, 0.75, 22.0, 5.0, 20.0, true)
		mi.position = Vector3((l[0] as Vector2).x, float(l[2]), (l[0] as Vector2).y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no.add_child(mi)
		var ll := OmniLight3D.new()
		ll.light_color = Color(1.0, 0.45, 0.14)
		ll.light_energy = 4.0
		ll.omni_range = float(l[1]) * 2.2
		ll.position = mi.position + Vector3.UP * 18.0
		no.add_child(ll)
	# Rios de lava: faixa que acompanha o leito, correndo morro abaixo
	for rio: Dictionary in _rios:
		var pts: PackedVector3Array = rio.pts
		var larg: float = rio.larg + 3.0
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var s := 0.0
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var t := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
			var lado := t.cross(Vector3.UP).normalized()
			var s1 := s + a.distance_to(b)
			var q := [a - lado * larg, a + lado * larg, b + lado * larg, b - lado * larg]
			var uv := [Vector2(0, s), Vector2(1, s), Vector2(1, s1), Vector2(0, s1)]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.set_uv(uv[k])
				st.add_vertex(q[k] + Vector3.UP * 0.3)
			s = s1
		var mr := MeshInstance3D.new()
		mr.mesh = st.commit()
		mr.material_override = material_lava(0, 0.55, 0.85, 12.0, 5.5, larg * 2.0)
		mr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		no.add_child(mr)
		for i in range(4, pts.size(), 14):
			var lr := OmniLight3D.new()
			lr.light_color = Color(1.0, 0.42, 0.12)
			lr.light_energy = 2.5
			lr.omni_range = 70.0
			lr.position = pts[i] + Vector3.UP * 10.0
			no.add_child(lr)
	_fumaca_cratera(no)


## Coluna de fumaça saindo da cratera: nuvens grandes subindo e se espalhando com o vento, a base
## iluminada de laranja pela lava, e brasas subindo.
func _fumaca_cratera(pai: Node3D) -> void:
	var part := GPUParticles3D.new()
	part.amount = 260
	part.lifetime = 50.0
	part.preprocess = 50.0
	part.local_coords = false
	part.position = Vector3(centro_vulcao.x, altura_vulcao - 40.0, centro_vulcao.y)
	part.visibility_aabb = AABB(Vector3(-1500, -200, -1500), Vector3(3000, 2600, 3000))
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 70.0
	proc.direction = Vector3(0.15, 1.0, 0.05)
	proc.spread = 14.0
	proc.initial_velocity_min = 9.0
	proc.initial_velocity_max = 16.0
	proc.gravity = Vector3(1.8, 0.4, 0.6)
	proc.damping_min = 0.1
	proc.damping_max = 0.2
	proc.scale_min = 120.0
	proc.scale_max = 200.0
	proc.angle_min = 0.0
	proc.angle_max = 360.0
	proc.angular_velocity_min = -2.0
	proc.angular_velocity_max = 2.0
	var cresce := Curve.new()
	cresce.add_point(Vector2(0.0, 0.5))
	cresce.add_point(Vector2(1.0, 3.2))
	var tc := CurveTexture.new()
	tc.curve = cresce
	proc.scale_curve = tc
	var grad := Gradient.new()
	grad.set_color(0, Color(0.45, 0.2, 0.1, 0.0))
	grad.add_point(0.05, Color(0.42, 0.24, 0.16, 0.85))
	grad.add_point(0.25, Color(0.2, 0.18, 0.17, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(0.32, 0.31, 0.31, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	proc.color_ramp = gt
	part.process_material = proc
	var quad := QuadMesh.new()
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = Selva._textura_nuvem()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.proximity_fade_enabled = true
	mat.proximity_fade_distance = 30.0
	mat.roughness = 1.0
	quad.material = mat
	part.draw_pass_1 = quad
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(part)
	# Brasas
	var bra := GPUParticles3D.new()
	bra.amount = 260
	bra.lifetime = 7.0
	bra.preprocess = 7.0
	bra.local_coords = false
	bra.position = Vector3(centro_vulcao.x, lava_cratera + 5.0, centro_vulcao.y)
	bra.visibility_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 600, 800))
	var pb := ParticleProcessMaterial.new()
	pb.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pb.emission_sphere_radius = 110.0
	pb.direction = Vector3.UP
	pb.spread = 25.0
	pb.initial_velocity_min = 25.0
	pb.initial_velocity_max = 55.0
	pb.gravity = Vector3(0.5, -9.0, 0.3)
	pb.turbulence_enabled = true
	pb.turbulence_noise_strength = 3.0
	pb.scale_min = 0.6
	pb.scale_max = 1.6
	bra.process_material = pb
	var q2 := QuadMesh.new()
	q2.size = Vector2(1.0, 1.0)
	var mb := StandardMaterial3D.new()
	mb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mb.albedo_texture = Gelo._textura_floco()
	mb.albedo_color = Color(1.0, 0.55, 0.15)
	mb.emission_enabled = true
	mb.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mb.billboard_keep_scale = true
	q2.material = mb
	bra.draw_pass_1 = q2
	bra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pai.add_child(bra)


# ------------------------------------------------------------------ túneis

## Túneis de todas as etapas (o da etapa 1 atravessa o vulcão): ficam montados o tempo todo, porque a
## capa de rocha deles é que fecha a vala cavada no terreno ao longo da estrada.
func _montar_tuneis() -> void:
	var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
	for k in percursos:
		var pc: Dictionary = percursos[k]
		for t in pc.get("tuneis", []):
			var tun := TunelVulcao.new()
			tun.name = "Tunel_%s_%s" % [k, str(t[0])]
			add_child(tun)
			tun.montar(self, _terreno, pc, t, _cfg.get("tunel", {}))
			tuneis.append(tun)


# ------------------------------------------------------------------ floresta

## Floresta pré-histórica: sequoias gigantes e araucárias em bosques, copas, fetos arborescentes,
## cicas e samambaias embaixo. Nada nas encostas altas do vulcão (rocha e cinza), na lava, nas
## estradas, nos cercados e no caminho do voo.
func _montar_vegetacao() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1)) + 313
	var vale: Array = Config.valor("mapa.subida.vale", [-2800, -2500, 1900, 1700])
	var qtd: Dictionary = _cfg.get("arvores", {})
	var bosque := FastNoiseLite.new()
	bosque.seed = 41
	bosque.frequency = 1.0 / 520.0
	var listas := {}
	# [tipo, quantidade, altura nominal (m), escala mín., escala máx., limiar do bosque, alcance, bloco, nome no registro]
	# (as linhas novas ficam no fim: assim o sorteio das plantas que já existiam não muda de lugar)
	var metas := [
		[Vegetacao.Tipo.SEQUOIA, int(qtd.get("sequoias", 900)), 70.0, 0.85, 1.25, 0.1, 5000.0, 700.0, "sequoias"],
		[Vegetacao.Tipo.ARAUCARIA, int(qtd.get("araucarias", 1300)), 45.0, 0.85, 1.2, -0.1, 3500.0, 600.0, "araucarias"],
		[Vegetacao.Tipo.COPA, int(qtd.get("copas", 2600)), 22.0, 1.0, 1.6, -0.2, 2400.0, 500.0, "copas"],
		[Vegetacao.Tipo.FETO, int(qtd.get("fetos", 4500)), 7.0, 0.9, 1.4, -0.35, 900.0, 300.0, "fetos"],
		[Vegetacao.Tipo.CICA, int(qtd.get("cicas", 2800)), 3.0, 0.9, 1.5, -0.5, 600.0, 250.0, "cicas"],
		[Vegetacao.Tipo.SAMAMBAIA, int(qtd.get("samambaias", 12000)), 1.5, 1.0, 2.0, -0.6, 300.0, 150.0, "samambaias"],
		# Pedido do dono (2026-10-04): árvores "muito mais gigantes" — sequoias colossais de 170 a 300 m —
		# e várias árvores gigantes quebradas (toco em lascas com o tronco tombado), de todos os tamanhos
		[Vegetacao.Tipo.SEQUOIA, int(qtd.get("colossos", 0)), 70.0, 2.3, 3.2, -0.15, 6000.0, 700.0, "colossos"],
		[Vegetacao.Tipo.SEQUOIA_QUEBRADA, int(qtd.get("quebradas", 0)), 40.0, 0.9, 2.6, -0.3, 4500.0, 700.0, "quebradas"],
	]
	for linha: Array in metas:
		var tipo: Vegetacao.Tipo = linha[0]
		var m: Array = linha.slice(1)
		var quebrada := tipo == Vegetacao.Tipo.SEQUOIA_QUEBRADA
		var lista := []
		var tent := 0
		var perto := float(qtd.get("perto_estrada", 0.4))
		while lista.size() < int(m[0]) and tent < int(m[0]) * 18:
			tent += 1
			var x := rng.randf_range(float(vale[0]) - 1000.0, float(vale[2]) + 1000.0)
			var z := rng.randf_range(float(vale[1]) - 1000.0, float(vale[3]) + 1000.0)
			var junto := rng.randf() < perto and not _estradas.is_empty()
			if junto:
				# Perto das estradas (onde a câmera passa): a mata fecha dos dois lados
				var pts: PackedVector3Array = _estradas[rng.randi() % _estradas.size()]
				var q := pts[rng.randi() % pts.size()]
				var ang := rng.randf() * TAU
				var d := rng.randf_range(22.0, 170.0)
				x = q.x + cos(ang) * d
				z = q.z + sin(ang) * d
			if absf(x) > Terreno.MEIO_INTERNO - 60.0 or absf(z) > Terreno.MEIO_INTERNO - 60.0:
				continue
			# Bosques: as árvores grandes se juntam onde o ruído manda; o resto enche os vãos
			if not junto and bosque.get_noise_2d(x, z) < float(m[4]) + rng.randf_range(-0.25, 0.25):
				continue
			var p := Vector2(x, z)
			var rv := p.distance_to(centro_vulcao)
			if rv < base_vulcao * 0.78 and rng.randf() < 0.97:
				continue   # encosta do vulcão: rocha e cinza
			var h := _terreno.altura_em(x, z)
			if h > 420.0:
				continue
			var esc := rng.randf_range(float(m[2]), float(m[3]))
			# (as colossais abrem a copa até ~50 m do tronco: folga maior de plataformas, alvos e caminho do voo)
			if not livre(p, float(m[1]) * esc, maxf(esc - 1.3, 0.0) * 22.0) or not plano(x, z, 9.0 if float(m[1]) > 20.0 else 6.0):
				continue
			var tinta := Color(1, 1, 1) * rng.randf_range(0.82, 1.12)
			var rot := rng.randf() * TAU
			if quebrada:
				# O tronco tombado cai para o +X da planta: o chão tem de acompanhar até a ponta (ela fica
				# enterrada, nada no ar) e o caminho dele não pode cruzar estrada, lava nem cercado
				var cai := Vector2(cos(rot), -sin(rot))
				var serve := true
				for f: float in [0.35, 0.7, 1.0]:
					var q := p + cai * Vegetacao.QUEBRADA_ALCANCE * esc * f
					var hq := _terreno.altura_em(q.x, q.y)
					if not livre(q, 30.0 * esc * (1.0 - f) + 8.0) or hq < h - 2.5 * esc or hq > h + (1.0 - f) * 14.0 * esc:
						serve = false
						break
				if not serve:
					continue
			lista.append([Vector3(x, h - 0.4, z), esc, rot, tinta])
		Vegetacao.plantar(self, tipo, lista, float(m[6]), float(m[5]), float(m[1]) > 5.0)
		listas[linha[8]] = lista.size()
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[DINO] vegetação: ", listas)


# ------------------------------------------------------------------ estruturas do parque

## Estruturas do parque (dino.objetos: [tipo, x, z, giro em graus, escala]): portão (com o arco e o
## letreiro TSC DINO PARK e tochas acesas), cerca elétrica, recinto dos raptores, jaula, ruínas e o
## crânio de tricerátopo. Os modelos são da biblioteca do dono (créditos em assets/dino/creditos.txt).
## 6º item = altura (-9999 = no chão); 7º = etapa (1..4): o objeto só existe naquela etapa (o portão da
## largada de cada percurso — sem a estrada dele, ficava perdido no meio do mato).
func _montar_objetos(etapa := 0, pai: Node3D = null) -> void:
	var no := Node3D.new()
	no.name = "Parque"
	(pai if pai else self).add_child(no)
	var cenas := {}
	for o in _cfg.get("objetos", []):
		if (int(o[6]) if o.size() > 6 else 0) != etapa:
			continue
		var tipo := str(o[0])
		var caminho := "res://assets/dino/%s/%s.glb" % [tipo, tipo]
		if not cenas.has(tipo):
			cenas[tipo] = load(caminho) if ResourceLoader.exists(caminho) else null
		if cenas[tipo] == null:
			continue
		var x := float(o[1])
		var z := float(o[2])
		var giro := deg_to_rad(float(o[3]))
		var esc := float(o[4]) if o.size() > 4 else 1.0
		var y := _terreno.altura_em(x, z) - 0.3
		if o.size() > 5 and float(o[5]) > -9000.0:
			y = float(o[5])
		var inst: Node3D = (cenas[tipo] as PackedScene).instantiate()
		inst.transform = Transform3D(Basis(Vector3.UP, giro).scaled(Vector3.ONE * esc), Vector3(x, y, z))
		no.add_child(inst)
		_sem_sombra_longe(inst, 1600.0 if tipo != "cranio" else 2600.0)
		match tipo:
			"portao": _enfeitar_portao(no, inst, esc)
			"cerca": _faiscas_cerca(no, inst, esc)
			"cranio", "ruina": _musgo(inst)


## Alcance de visibilidade (as estruturas somem longe) e sombra só do que é grande.
func _sem_sombra_longe(raiz: Node, alcance: float) -> void:
	for gi in raiz.find_children("*", "GeometryInstance3D", true, false):
		var g := gi as GeometryInstance3D
		g.visibility_range_end = alcance
		g.visibility_range_end_margin = alcance * 0.1
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _musgo(_raiz: Node) -> void:
	pass


## Portão do parque: os dois pilares de pedra do modelo ganham um arco de troncos com cintas de ferro,
## o letreiro "TSC DINO PARK" iluminado, o logo do jogo e fogo nas seis tochas.
## (Modelo: pilares em |x| 2,6–5,1 m, altura -4,6..4,6 m, centrado na origem.)
func _enfeitar_portao(pai: Node3D, portao: Node3D, esc: float) -> void:
	var xf := portao.transform
	var b := xf.basis.orthonormalized()
	var o := xf.origin
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.3, 0.2, 0.12)
	madeira.roughness = 0.85
	var ferro := ComplexoLancamento._material_metal(Color(0.12, 0.11, 0.1), 0.8, 0.5)
	var topo := 3.4 * esc
	var pecas: Array[Transform3D] = []
	var cintas: Array[Transform3D] = []
	# Arco: duas vigas de tronco empilhadas de pilar a pilar, levemente arqueadas em 5 gomos
	for camada in 2:
		var y := topo + camada * 1.15 * esc * 0.45
		for k in 5:
			var x0 := lerpf(-3.4, 3.4, k / 5.0) * esc
			var x1 := lerpf(-3.4, 3.4, (k + 1) / 5.0) * esc
			var curva0 := sin(PI * (k / 5.0)) * 0.45 * esc
			var curva1 := sin(PI * ((k + 1) / 5.0)) * 0.45 * esc
			var a := o + b * Vector3(x0, y + curva0, 0.0)
			var c := o + b * Vector3(x1, y + curva1, 0.0)
			pecas.append(ComplexoLancamento._viga(a, c, 0.55 * esc))
		for k in 7:
			var x := lerpf(-3.0, 3.0, k / 6.0) * esc
			cintas.append(Transform3D(b * Basis.from_scale(Vector3(0.18 * esc, 0.75 * esc, 0.75 * esc)), o + b * Vector3(x, y + sin(PI * (x / esc + 3.4) / 6.8) * 0.45 * esc, 0.0)))
	ComplexoLancamento.criar_multimesh(pai, pecas, madeira)
	ComplexoLancamento.criar_multimesh(pai, cintas, ferro)
	# Colisão (pedido do dono: dava para atravessar a estrutura da placa): os dois pilares de pedra do
	# modelo, o arco de troncos e a silhueta da placa
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	pai.add_child(corpo)
	var solidos: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		solidos.append(Transform3D(b * Basis.from_scale(Vector3(2.5, 9.2, 2.5) * esc), o + b * Vector3(s * 3.85 * esc, 0.0, 0.0)))
	solidos.append_array(pecas)
	const PLACA := "res://assets/dino/portao/placa_tsc_dino_park.png"
	var placa_p := o + b * Vector3(0.0, topo - 0.3 * esc, 0.0)
	# Letreiro: a placa TSC DINO PARK pronta do dono, em relevo, nas duas faces
	if TunelVulcao.montar_arte(pai, PLACA, [], [], placa_p, b.z, 8.6 * esc, 0.0, true, 0.3 * esc) > 0.0:
		solidos.append_array(TunelVulcao.colisao_arte(PLACA, [], placa_p, b.z, 8.6 * esc, 0.0, true, 0.3 * esc))
	else:
		solidos.append(Transform3D(b * Basis.from_scale(Vector3(5.6, 1.25, 0.22) * esc), o + b * Vector3(0.0, topo + 1.7 * esc, 0.0)))
		# Letreiro: placa de madeira escura com as letras acesas, nas duas faces
		var placa_c := o + b * Vector3(0.0, topo + 1.7 * esc, 0.0)
		var placa := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(5.6 * esc, 1.25 * esc, 0.22 * esc)
		placa.mesh = bm
		placa.material_override = madeira
		placa.transform = Transform3D(b, placa_c)
		pai.add_child(placa)
		for face: float in [1.0, -1.0]:
			var nome := Label3D.new()
			nome.text = "TSC DINO PARK"
			nome.font = load("res://assets/fontes/RacingSansOne-Regular.ttf") if ResourceLoader.exists("res://assets/fontes/RacingSansOne-Regular.ttf") else null
			nome.font_size = 256
			nome.pixel_size = 0.85 * esc / 256.0
			nome.outline_size = 20
			nome.modulate = Color(1.0, 0.62, 0.12)
			nome.outline_modulate = Color(0.35, 0.05, 0.02)
			nome.double_sided = false
			nome.shaded = false
			var bb := b if face > 0.0 else b * Basis(Vector3.UP, PI)
			nome.transform = Transform3D(bb, placa_c + b.z * face * 0.14 * esc)
			pai.add_child(nome)
			Gelo.painel_logo(pai, o + b * Vector3(0.0, topo + 3.2 * esc, 0.0) + b.z * face * 0.2, Basis.looking_at(-b.z * face, Vector3.UP), 0.75 * esc)
	ComplexoLancamento.adicionar_colisoes(corpo, solidos)
	# (as chamas soltas ao lado dos pilares saíram a pedido do dono: flutuavam sem tocha nem base embaixo)


## Chama de tocha: partículas de fogo subindo e uma luz que tremula.
static func _chama(p: Vector3, tam: float) -> Node3D:
	var no := Node3D.new()
	no.position = p
	var f := GPUParticles3D.new()
	f.amount = 24
	f.lifetime = 0.7
	f.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = tam * 0.25
	pm.direction = Vector3.UP
	pm.spread = 12.0
	pm.initial_velocity_min = tam * 1.6
	pm.initial_velocity_max = tam * 2.6
	pm.gravity = Vector3(0, tam * 1.5, 0)
	pm.scale_min = tam * 0.8
	pm.scale_max = tam * 1.5
	var curva := Curve.new()
	curva.add_point(Vector2(0.0, 1.0))
	curva.add_point(Vector2(1.0, 0.1))
	var tc := CurveTexture.new()
	tc.curve = curva
	pm.scale_curve = tc
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.45, 1.0))
	grad.add_point(0.4, Color(1.0, 0.4, 0.08, 0.8))
	grad.set_color(grad.get_point_count() - 1, Color(0.3, 0.05, 0.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	f.process_material = pm
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = Selva._textura_nuvem()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	q.material = m
	f.draw_pass_1 = q
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	no.add_child(f)
	var luz := OmniLight3D.new()
	luz.light_color = Color(1.0, 0.55, 0.2)
	luz.light_energy = 1.6
	luz.omni_range = tam * 14.0
	luz.position = Vector3.UP * tam
	no.add_child(luz)
	return no


## Cerca elétrica: de vez em quando um arco azul estala num dos fios.
func _faiscas_cerca(_pai: Node3D, _cerca: Node3D, _esc: float) -> void:
	pass
