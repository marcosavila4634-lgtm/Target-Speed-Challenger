class_name Selva
extends Node3D
## Serpent's Climb (mapa.subida.selva): templos astecas/maias no meio da selva fechada.
## - pirâmides em talude-tablero (talude inclinado + painel vertical com friso), escadaria com
##   balaustradas que terminam em cabeças de serpente (como em Chichén Itzá) e templo no topo;
## - rio e lago cavados no terreno (cavar_rio) e a cachoeira que despenca do paredão norte no lago;
## - jogo de bola, estelas, altares, cabeças de jaguar e colunas da serpente (as da etapa são mortais);
## - a serpente gigante rastejando pela mata (SerpenteGigante, só enfeite, nas etapas da config);
## - mata fechada (sumaúmas gigantes com cipós, árvores de copa, palmeiras, bananeiras, samambaias),
##   bandos de araras, tucanos e urubus, garças no rio e borboletas (Fauna).
## Tudo que é pedra é mortal: entra em altura() (somada em Terreno.altura_em) e tem colisão no grupo
## "mortal".

var penhasco := 170.0
var _terreno: Terreno
var _cfg: Dictionary = {}
var _chao := 6.5
var _piramides: Array = []        # {c: Vector2, mb, mt, topo, niveis, escadas: String, templo: bool}
var _colunas_fixas: Array = []    # [centro Vector2, raio, altura]
var _colunas_etapa: Array = []
var _rio := PackedVector2Array()
var _rio_meia := 30.0
var _rio_larg := PackedFloat32Array()   # meia largura em cada ponto do rio
var _lagos: Array = []            # [centro Vector2, raio]
var _rio_margem := 90.0           # até onde a margem desce suave até o rio
var _rio_padrao: Dictionary = {}  # rio/lagos/cachoeira da config (as etapas podem trocar: selva.etapas.N)
var _rio_etapa := -1
var _rio_etapa_mascara := 0       # a máscara do chão foi feita com o rio desta etapa
var _etapa_no: Node3D
var _vento_cfg: Dictionary = {}
var _t := 0.0
var _estradas: Array = []         # [PackedVector3Array] pontos de controle de todas as estradas (todas as etapas)
var _grade_estrada := {}          # Vector2i -> [[a, b], ...] segmentos
const CACHOEIRA_NOVA := "res://assets/MAPA SERPENTE/cachoeira/waterfall/waterfall.gd"
const CEL := 40.0
var _serpente_cfg: Dictionary = {}
var _rocha_lad: ImageTexture
var _trilhas_extras: Array[PackedVector2Array] = []
var _trilha_serpente := PackedVector2Array()   # por onde a serpente gigante rasteja (SerpenteGigante.tracar)
var _grade_trilha := {}           # Vector2i (células de CEL_TRILHA m) em cima da trilha: sem mata
const CEL_TRILHA := 4.0

static var _mats := {}


# ------------------------------------------------------------------ materiais (compartilhados)

static func material_pedra(modo: int, fiada := 1.2) -> ShaderMaterial:
	var chave := "%d_%.2f" % [modo, fiada]
	if _mats.has(chave):
		return _mats[chave]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/pedra_selva.gdshader")
	m.set_shader_parameter("modo", modo)
	m.set_shader_parameter("fiada", fiada)
	m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 211))
	_mats[chave] = m
	return m


static func material_ouro() -> StandardMaterial3D:
	if not _mats.has("ouro"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.76, 0.32)
		m.metallic = 1.0
		m.roughness = 0.28
		m.emission_enabled = true
		m.emission = Color(1.0, 0.7, 0.3)
		m.emission_energy_multiplier = 0.12
		_mats["ouro"] = m
	return _mats["ouro"]


static func material_jade() -> StandardMaterial3D:
	if not _mats.has("jade"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.1, 0.62, 0.42)
		m.metallic = 0.1
		m.roughness = 0.2
		m.rim_enabled = true
		m.rim = 0.3
		m.emission_enabled = true
		m.emission = Color(0.1, 0.7, 0.45)
		m.emission_energy_multiplier = 0.25
		_mats["jade"] = m
	return _mats["jade"]


static func _caixa(pai: Node3D, tam: Vector3, pos: Vector3, mat: Material, giro := Basis.IDENTITY) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = tam
	mi.mesh = b
	mi.material_override = mat
	mi.transform = Transform3D(giro, pos)
	pai.add_child(mi)
	return mi


static func _cone(pai: Node3D, r0: float, r1: float, alt: float, xf: Transform3D, mat: Material, lados := 8) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r1
	c.bottom_radius = r0
	c.height = alt
	c.radial_segments = lados
	c.rings = 1
	mi.mesh = c
	mi.material_override = mat
	mi.transform = xf
	pai.add_child(mi)


## Cabeça de serpente emplumada esculpida (olhando para -Z), com `escala` m de comprimento:
## focinho com a voluta do nariz, boca aberta com presas, olhos de jade e o colar de penas.
static func cabeca_serpente(escala: float) -> Node3D:
	var raiz := Node3D.new()
	var s := escala
	var pedra := material_pedra(2, 0.5 * s)
	var osso := StandardMaterial3D.new()
	osso.albedo_color = Color(0.9, 0.86, 0.76)
	osso.roughness = 0.5
	var vermelho := StandardMaterial3D.new()
	vermelho.albedo_color = Color(0.55, 0.1, 0.07)
	vermelho.roughness = 0.6
	_caixa(raiz, Vector3(0.8, 0.45, 0.85) * s, Vector3(0, 0.38, -0.05) * s, pedra)                 # crânio
	_caixa(raiz, Vector3(0.72, 0.22, 0.55) * s, Vector3(0, 0.3, -0.62) * s, pedra)                 # maxilar
	_caixa(raiz, Vector3(0.7, 0.16, 0.6) * s, Vector3(0, -0.02, -0.5) * s, pedra, Basis(Vector3.RIGHT, -0.25))  # mandíbula aberta
	_caixa(raiz, Vector3(0.5, 0.06, 0.5) * s, Vector3(0, 0.12, -0.55) * s, vermelho)               # língua/boca
	_caixa(raiz, Vector3(0.35, 0.3, 0.22) * s, Vector3(0, 0.62, -0.78) * s, pedra, Basis(Vector3.RIGHT, 0.5))  # voluta do nariz
	for lado: float in [-1.0, 1.0]:
		var olho := MeshInstance3D.new()
		var e := SphereMesh.new()
		e.radius = 0.09 * s
		e.height = 0.18 * s
		olho.mesh = e
		olho.material_override = material_jade()
		olho.position = Vector3(lado * 0.36, 0.55, -0.32) * s
		raiz.add_child(olho)
		_caixa(raiz, Vector3(0.2, 0.08, 0.32) * s, Vector3(lado * 0.36, 0.66, -0.32) * s, pedra)   # sobrancelha
		_cone(raiz, 0.06 * s, 0.0, 0.32 * s, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(lado * 0.27, 0.06, -0.82) * s), osso)
	# Colar de penas (placas em leque atrás da cabeça)
	var n := 9
	for k in n:
		var a := lerpf(-1.4, 1.4, float(k) / (n - 1))
		var pena := _caixa(raiz, Vector3(0.22, 0.75, 0.08) * s, Vector3(sin(a) * 0.55, 0.35 + cos(a) * 0.5, 0.45) * s, pedra, Basis(Vector3.FORWARD, a))
		pena.material_override = material_jade() if k % 2 == 0 else pedra
	return raiz


## Cabeça de jaguar esculpida (olhando para -Z), `escala` m de largura: orelhas, focinho, presas e
## olhos de jade.
static func cabeca_jaguar(escala: float) -> Node3D:
	var raiz := Node3D.new()
	var s := escala
	var pedra := material_pedra(0, 0.25 * s)
	var osso := StandardMaterial3D.new()
	osso.albedo_color = Color(0.9, 0.86, 0.76)
	_caixa(raiz, Vector3(1.0, 0.8, 0.8) * s, Vector3(0, 0.4, 0) * s, pedra)
	_caixa(raiz, Vector3(0.55, 0.35, 0.35) * s, Vector3(0, 0.22, -0.5) * s, pedra)
	_caixa(raiz, Vector3(0.24, 0.14, 0.12) * s, Vector3(0, 0.4, -0.66) * s, material_pedra(1, 0.3))
	for lado: float in [-1.0, 1.0]:
		_caixa(raiz, Vector3(0.24, 0.26, 0.12) * s, Vector3(lado * 0.36, 0.9, 0.05) * s, pedra, Basis(Vector3.FORWARD, lado * 0.3))
		var olho := MeshInstance3D.new()
		var e := SphereMesh.new()
		e.radius = 0.08 * s
		e.height = 0.16 * s
		olho.mesh = e
		olho.material_override = material_jade()
		olho.position = Vector3(lado * 0.24, 0.58, -0.4) * s
		raiz.add_child(olho)
		_cone(raiz, 0.045 * s, 0.0, 0.2 * s, Transform3D(Basis(Vector3.RIGHT, PI), Vector3(lado * 0.13, 0.0, -0.64) * s), osso)
	return raiz


# ------------------------------------------------------------------ preparação (antes do terreno)

func preparar(terreno: Terreno) -> void:
	_terreno = terreno
	_cfg = Config.valor("mapa.subida.selva", {})
	penhasco = float(_cfg.get("penhasco", 170.0))
	for p in _cfg.get("piramides", []):
		_piramides.append({"c": Vector2(float(p[0]), float(p[1])), "mb": float(p[2]), "mt": float(p[3]), "topo": float(p[4]),
			"niveis": int(p[5]) if p.size() > 5 else 6, "escadas": str(p[6]) if p.size() > 6 else "S", "templo": bool(p[7]) if p.size() > 7 else false})
	for c in _cfg.get("colunas", []):
		_colunas_fixas.append([Vector2(float(c[0]), float(c[1])), float(c[2]), float(c[3])])
	_rio_padrao = {"rio": _cfg.get("rio", {}), "lagos": _cfg.get("lagos", []), "cachoeira": _cfg.get("cachoeira", {})}
	definir_etapa(0)
	# Estradas de todas as etapas (a mata não pode atravessar nenhuma)
	var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
	for k in percursos:
		var trechos: Dictionary = (percursos[k] as Dictionary).get("trechos", {})
		for nome in ["A", "B", "C"]:
			var pts := PackedVector3Array()
			for p in trechos.get(nome, []):
				pts.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
			if pts.size() > 1:
				_estradas.append(pts)
	for pts: PackedVector3Array in _estradas:
		for i in range(1, pts.size()):
			var a := pts[i - 1]
			var b := pts[i]
			var r := Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)).grow(30.0)
			for cx in range(floori(r.position.x / CEL), floori(r.end.x / CEL) + 1):
				for cz in range(floori(r.position.y / CEL), floori(r.end.y / CEL) + 1):
					var chave := Vector2i(cx, cz)
					if not _grade_estrada.has(chave):
						_grade_estrada[chave] = []
					_grade_estrada[chave].append([a, b])
	# Trilha da serpente gigante: a mata não nasce em cima (o corpo atravessaria os troncos)
	_serpente_cfg = _cfg.get("serpente_gigante", {})
	_preparar_chao()
	_trilha_serpente = _desviar_rochas(SerpenteGigante.tracar(_serpente_cfg, self), float(_serpente_cfg.get("grossura", 7.0)))
	# Outras cobras de enfeite (pedido do dono 2026-10-05: preta, coral, verde, cascavel), cada uma na sua volta
	_trilhas_extras.clear()
	for c: Dictionary in _cfg.get("cobras_extras", []):
		_trilhas_extras.append(_desviar_rochas(SerpenteGigante.tracar(c, self), 6.0))
	var folga := float(_serpente_cfg.get("grossura", 5.0)) * 0.5 + 5.0
	var nc := ceili(folga / CEL_TRILHA)
	var todas: Array = [_trilha_serpente] + _trilhas_extras
	for trilha: PackedVector2Array in todas:
		for q in trilha:
			var c := Vector2i(floori(q.x / CEL_TRILHA), floori(q.y / CEL_TRILHA))
			for dx in range(-nc, nc + 1):
				for dz in range(-nc, nc + 1):
					if (Vector2(c.x + dx + 0.5, c.y + dz + 0.5) * CEL_TRILHA).distance_to(q) < folga:
						_grade_trilha[c + Vector2i(dx, dz)] = true


## As cobras de enfeite não atravessam as rochas gigantes da E1 (pedido do dono): cada ponto da trilha que cai
## dentro do círculo de uma rocha é empurrado para a borda dele, e a trilha é alisada de novo.
func _desviar_rochas(trilha: PackedVector2Array, gross: float) -> PackedVector2Array:
	var circ: Array = []
	for r: Array in _cfg.get("etapas", {}).get("1", {}).get("rochas", []):
		circ.append([Vector2(float(r[0]), float(r[1])), float(r[2]) * 0.62 + gross + 6.0])
	if circ.is_empty() or trilha.size() < 3:
		return trilha
	var p := trilha
	for passada in 6:
		var mexeu := false
		for i in p.size():
			for c: Array in circ:
				var d: Vector2 = p[i] - c[0]
				if d.length() < float(c[1]):
					p[i] = c[0] + (d.normalized() if d.length() > 0.01 else Vector2.RIGHT) * float(c[1])
					mexeu = true
		if not mexeu:
			break
		var q := p.duplicate()
		var m := p.size()
		for i in m:
			q[i] = (p[(i - 2 + m) % m] + p[(i - 1 + m) % m] * 2.0 + p[i] * 3.0 + p[(i + 1) % m] * 2.0 + p[(i + 2) % m]) / 9.0
		p = q
	for i in p.size():   # a última passada alisou: garante que ninguém ficou dentro
		for c: Array in circ:
			var d: Vector2 = p[i] - c[0]
			if d.length() < float(c[1]):
				p[i] = c[0] + (d.normalized() if d.length() > 0.01 else Vector2.RIGHT) * float(c[1])
	return p


## Grama e juncos no chão do vale (pedido do dono): touceiras densas, mais altas na beira dos charcos.
func _montar_capim() -> void:
	Vegetacao.plantar(self, Vegetacao.Tipo.CAPIM_SELVA, _cache("capim", _sortear_capim), 120.0, 300.0, false)


func _sortear_capim() -> Array:
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var nivel := float(Config.valor("mapa.nivel_agua", 4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 6061
	var lista: Array = []
	var tent := 0
	while lista.size() < 380000 and tent < 1000000:
		tent += 1
		var x := rng.randf_range(float(vale[0]), float(vale[2]))
		var z := rng.randf_range(float(vale[1]), float(vale[3]))
		var h := _terreno.altura_em(x, z)
		if h < nivel + 0.15 or h > 26.0 or altura(x, z) > -INF:
			continue
		var p := Vector2(x, z)
		if _estrada_perto(p, h, 2.0):
			continue
		var beira := 1.0 - smoothstep(nivel + 0.2, nivel + 2.0, h)   # junco alto na beira d'água
		lista.append([Vector3(x, h - 0.1, z), rng.randf_range(1.2, 2.2) + beira * 1.6, rng.randf() * TAU, Color(0.85, 1.0, 0.8) * rng.randf_range(0.75, 1.1)])
	return lista


## Sorteios pesados (posições da mata e da grama) guardados em user://cache: só mudam com o mapa (config) ou
## com o terreno (Terreno.VERSAO_CACHE). Carregar a selva caiu de ~70 s para poucos segundos.
func _cache(nome: String, gerar: Callable) -> Variant:
	var chave := str([Terreno.VERSAO_CACHE, Config.mapa_id, Config.valor("mapa", {}), 3]).md5_text().substr(0, 12)
	var arq := "user://cache/selva_%s_%s.bin" % [nome, chave]
	if FileAccess.file_exists(arq):
		var fa := FileAccess.open(arq, FileAccess.READ)
		if fa:
			var v: Variant = fa.get_var()
			if v != null:
				return v
	var dados: Variant = gerar.call()
	DirAccess.make_dir_recursive_absolute("user://cache")
	var fw := FileAccess.open(arq, FileAccess.WRITE)
	if fw:
		fw.store_var(dados)
	return dados


func _preparar_chao() -> void:
	_ruido_chao.seed = 4242
	_ruido_chao.frequency = 0.012
	_ruido_chao.fractal_octaves = 3
	_livres_chao = _areas_livres()
	for pr: Dictionary in _piramides:
		_livres_chao.append([pr.c, float(pr.mb) * 1.45 + 25.0])
	for c: Array in _colunas_fixas:
		_livres_chao.append([c[0], float(c[1]) + 20.0])


func _na_trilha(p: Vector2) -> bool:
	return _grade_trilha.has(Vector2i(floori(p.x / CEL_TRILHA), floori(p.y / CEL_TRILHA)))


## Distância (no chão) até a estrada mais próxima de qualquer etapa; INF a mais de ~30 m.
func dist_estrada(p: Vector2) -> float:
	var melhor := INF
	for seg: Array in _grade_estrada.get(Vector2i(floori(p.x / CEL), floori(p.y / CEL)), []):
		var a := Vector2(seg[0].x, seg[0].z)
		var ab := Vector2(seg[1].x, seg[1].z) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		melhor = minf(melhor, p.distance_to(a + ab * t))
	return melhor


# ------------------------------------------------------------------ alturas (mortais)

## Altura das construções de pedra em (x, z): pirâmides e colunas. -INF fora delas.
func altura(x: float, z: float) -> float:
	var h := -INF
	for p: Dictionary in _piramides:
		if p.get("oculta", false):
			continue
		var c: Vector2 = p.c
		var dx := absf(x - c.x)
		var dz := absf(z - c.y)
		var ch := maxf(dx, dz)
		if ch < p.mb:
			h = maxf(h, _altura_piramide(p, ch, x - c.x, z - c.y))
	for lista: Array in [_colunas_fixas, _colunas_etapa]:
		for col: Array in lista:
			var d := Vector2(x, z).distance_to(col[0])
			if d < col[1]:
				h = maxf(h, _chao + float(col[2]))
	return h


## Ponto em cima de uma pirâmide (visível) da etapa: lá o carro não morre por "afundar no chão" (a pirâmide tem
## colisão própria e não mata; pedido do dono 2026-10-06).
func na_piramide(x: float, z: float) -> bool:
	for p: Dictionary in _piramides:
		if p.get("oculta", false):
			continue
		var c: Vector2 = p.c
		if maxf(absf(x - c.x), absf(z - c.y)) < float(p.mb) + 1.0:
			return true
	return false


## Perfil da pirâmide: em cada nível, talude (inclinado, 65% da altura) e painel vertical; a escada
## (faixa no meio de cada face com escada) sobe reto da base ao topo.
func _altura_piramide(p: Dictionary, ch: float, dx: float, dz: float) -> float:
	var n: int = p.niveis
	var mb: float = p.mb
	var mt: float = p.mt
	var topo: float = p.topo
	if ch <= mt:
		return topo
	var recuo := (mb - mt) / n
	var hk := (topo - _chao) / n
	var k := clampi(int((mb - ch) / recuo), 0, n - 1)
	var m0 := mb - k * recuo
	var y0 := _chao + k * hk
	var talude_fim := m0 - recuo * 0.55
	var h := y0 + hk if ch <= talude_fim else y0 + hk * 0.65 * (m0 - ch) / (recuo * 0.55)
	# Escadaria
	var esc: String = p.escadas
	var meia_esc := mb * 0.13
	for f in esc:
		var ao_longo := 0.0
		var lateral := 0.0
		match f:
			"S": ao_longo = dz; lateral = dx
			"N": ao_longo = -dz; lateral = dx
			"E": ao_longo = dx; lateral = dz
			"W": ao_longo = -dx; lateral = dz
		if ao_longo > 0.0 and absf(lateral) < meia_esc + 2.0:
			var t := clampf((mb + 4.0 - ao_longo) / (mb + 4.0 - mt), 0.0, 1.0)
			h = maxf(h, _chao + t * (topo - _chao))
	return h

# ------------------------------------------------------------------ rio e lago

## Distância até a BEIRA do rio (negativa dentro d'água): cada ponto pode ter a própria meia largura
## (pontos [x, z, meia]; sem ela, rio.meia_largura) — o córrego nasce estreito e vai alargando.
func _dist_rio(p: Vector2) -> float:
	return _rio_beira(p).x


## (distância até a beira, meia largura do rio ali). Sem estado guardado: o terreno pode ser feito em threads.
func _rio_beira(p: Vector2) -> Vector2:
	var melhor := INF
	var meia_m := _rio_meia
	for i in range(1, _rio.size()):
		var a := _rio[i - 1]
		var ab := _rio[i] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var meia := lerpf(_rio_larg[i - 1], _rio_larg[i], t)
		var d := p.distance_to(a + ab * t) - meia
		if d < melhor:
			melhor = d
			meia_m = meia
	return Vector2(melhor, meia_m)


## Leito do rio e do lago: fundo a -6 m, margens de barro subindo até o chão da mata.
## Rio, lagos e cachoeira da etapa (selva.etapas.N.rio/lagos/cachoeira; sem eles, os da config). O terreno
## chama antes de refazer o chão da etapa (o rio é cavado nele).
func definir_etapa(indice: int) -> void:
	if indice == _rio_etapa:
		return
	_rio_etapa = indice
	var e: Dictionary = _cfg.get("etapas", {}).get(str(indice + 1), {})
	var rio: Dictionary = e.get("rio", _rio_padrao.rio)
	_rio_meia = float(rio.get("meia_largura", 30))
	_rio.clear()
	_rio_larg.clear()
	for q in rio.get("pontos", []):
		_rio.append(Vector2(float(q[0]), float(q[1])))
		_rio_larg.append(float(q[2]) if q.size() > 2 else _rio_meia)
	_rio_margem = float(rio.get("margem", 90))
	_lagos.clear()
	for l in e.get("lagos", _rio_padrao.lagos):
		_lagos.append([Vector2(float(l[0]), float(l[1])), float(l[2])])


func cachoeira_da_etapa(indice: int) -> Dictionary:
	return _cfg.get("etapas", {}).get(str(indice + 1), {}).get("cachoeira", _rio_padrao.cachoeira)


## Chão do vale com desníveis leves e poças de pântano raso (pedido do dono, 2026-10-05): ondulações de até
## ~2,5 m e, em manchas baixas, o chão desce até logo abaixo da água (o plano d'água vira charco). Longe das
## estradas, das pirâmides, dos cercados e do rio (o rio tem a margem dele).
var _ruido_chao := FastNoiseLite.new()
var _livres_chao: Array = []

func relevo_chao(x: float, z: float, h: float) -> float:
	if h < 3.0 or h > 24.0:
		return h
	var p := Vector2(x, z)
	var longe := 1.0
	var de := dist_estrada(p)
	if de < INF:
		longe = smoothstep(18.0, 30.0, de)
	for l: Array in _livres_chao:
		longe = minf(longe, smoothstep(float(l[1]), float(l[1]) + 40.0, p.distance_to(l[0])))
	if longe <= 0.0:
		return h
	var onda := _ruido_chao.get_noise_2d(x, z)
	h += onda * 2.5 * longe
	# Charco: manchas largas e baixas
	var charco := _ruido_chao.get_noise_2d(x * 0.35 + 900.0, z * 0.35 - 400.0)
	var nivel := float(Config.valor("mapa.nivel_agua", 4))
	var t := smoothstep(0.28, 0.42, charco) * longe
	return lerpf(h, minf(h, nivel - 0.5), t)


func cavar_rio(x: float, z: float, h: float) -> float:
	var p := Vector2(x, z)
	var d := INF
	var meia := _rio_meia
	if _rio.size() > 1:
		var b := _rio_beira(p)
		d = b.x
		meia = b.y
	for l: Array in _lagos:
		d = minf(d, p.distance_to(l[0]) - float(l[1]))
	# Margem proporcional à largura ali: o córrego estreito da nascente não escava o pé da montanha
	var margem := _rio_margem * clampf(meia / maxf(_rio_meia, 1.0), 0.25, 1.0)
	if d > margem + 30.0:
		return h
	h = minf(h, lerpf(-6.0, h, smoothstep(-meia * 0.6, 3.0, d)))
	h = minf(h, lerpf(5.0, h, smoothstep(2.0, margem, d)))
	return h


## Máscara (R = 1 na água, cai a 0 a 60 m da margem) para o shader do chão: barro e capim na margem.
func textura_margem(meio: float) -> ImageTexture:
	var n := 512
	var img := Image.create(n, n, false, Image.FORMAT_R8)
	var passo := meio * 2.0 / n
	for iz in n:
		for ix in n:
			var p := Vector2(-meio + (ix + 0.5) * passo, -meio + (iz + 0.5) * passo)
			var d := INF
			if _rio.size() > 1:
				d = _dist_rio(p)
			for l: Array in _lagos:
				d = minf(d, p.distance_to(l[0]) - float(l[1]))
			img.set_pixel(ix, iz, Color(clampf(1.0 - d / 60.0, 0.0, 1.0), 0.0, 0.0))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ montagem

func montar() -> void:
	for p: Dictionary in _piramides:
		_montar_piramide(p)
		if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    piramides" % Time.get_ticks_msec())
	var fixas := Node3D.new()
	fixas.name = "ColunasFixas"
	add_child(fixas)
	_montar_colunas(fixas, _colunas_fixas)
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    colunas" % Time.get_ticks_msec())
	var t0 := Time.get_ticks_msec()
	_montar_ruinas()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    ruinas" % Time.get_ticks_msec())
	var t1 := Time.get_ticks_msec()
	_montar_vegetacao()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    vegetacao" % Time.get_ticks_msec())
	var t2 := Time.get_ticks_msec()
	_montar_bruma()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    bruma" % Time.get_ticks_msec())
	if OS.get_environment("TSC_TEMPO") != "":
		print("[TEMPO] ruinas %d ms, vegetacao %d ms" % [t1 - t0, t2 - t1])
	var fauna := Fauna.new()
	fauna.name = "Fauna"
	add_child(fauna)
	fauna.montar(self, _terreno, _cfg.get("fauna", {}))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    fauna" % Time.get_ticks_msec())
	_etapa_no = Node3D.new()
	_etapa_no.name = "Etapa"
	add_child(_etapa_no)


func _corpo_mortal(pai: Node = null) -> StaticBody3D:
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	corpo.add_to_group("mortal")
	(pai if pai else self).add_child(corpo)
	return corpo


## Pirâmide em talude-tablero com escadarias, alfardas (balaustradas) terminando em cabeças de
## serpente, braseiros nos cantos do topo e (opcional) o templo com crista no alto.
func _montar_piramide(p: Dictionary) -> void:
	var c: Vector2 = p.c
	var n: int = p.niveis
	var mb: float = p.mb
	var mt: float = p.mt
	var topo: float = p.topo
	var recuo := (mb - mt) / n
	var hk := (topo - _chao) / n
	var st_t := SurfaceTool.new()   # taludes e patamares (blocos)
	st_t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st_p := SurfaceTool.new()   # painéis (friso entalhado e pintado)
	st_p.begin(Mesh.PRIMITIVE_TRIANGLES)
	var caixas: Array[Transform3D] = []
	for k in n:
		var m0 := mb - k * recuo
		var y0 := _chao + k * hk
		var ym := y0 + hk * 0.65
		var y1 := y0 + hk
		var mm := m0 - recuo * 0.55   # topo do talude
		var mp := mm + 0.6             # painel um pouco saliente (sombra embaixo)
		var cantos := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for q in 4:
			var a: Vector2 = cantos[q]
			var b: Vector2 = cantos[(q + 1) % 4]
			var fora := Vector3((a + b).x, 0.0, (a + b).y).normalized()
			var ba := Vector3(c.x + a.x * m0, y0 - (3.0 if k == 0 else 0.0), c.y + a.y * m0)
			var bb := Vector3(c.x + b.x * m0, y0 - (3.0 if k == 0 else 0.0), c.y + b.y * m0)
			var ta := Vector3(c.x + a.x * mm, ym, c.y + a.y * mm)
			var tb := Vector3(c.x + b.x * mm, ym, c.y + b.y * mm)
			var n_t := (tb - ta).cross(ba - ta).normalized()
			if n_t.dot(fora) < 0.0:
				n_t = -n_t
			Egito._quad(st_t, ta, tb, bb, ba, n_t)
			# Painel vertical
			var pa := Vector3(c.x + a.x * mp, ym, c.y + a.y * mp)
			var pb := Vector3(c.x + b.x * mp, ym, c.y + b.y * mp)
			Egito._quad(st_p, pa + Vector3.UP * (y1 - ym), pb + Vector3.UP * (y1 - ym), pb, pa, fora)
			# Base do painel (por baixo da saliência) e o patamar até o próximo nível
			Egito._quad(st_t, ta, tb, pb, pa, Vector3.DOWN)
			var m1 := m0 - recuo
			var ia := Vector3(c.x + a.x * m1, y1, c.y + a.y * m1)
			var ib := Vector3(c.x + b.x * m1, y1, c.y + b.y * m1)
			Egito._quad(st_t, pa + Vector3.UP * (y1 - ym), pb + Vector3.UP * (y1 - ym), ib, ia, Vector3.UP)
		caixas.append(Transform3D(Basis.from_scale(Vector3(mm * 2.0, hk + (3.0 if k == 0 else 0.0), mm * 2.0)), Vector3(c.x, (y0 + y1) * 0.5 - (1.5 if k == 0 else 0.0), c.y)))
	# Topo
	Egito._quad(st_t, Vector3(c.x - mt, topo, c.y - mt), Vector3(c.x + mt, topo, c.y - mt), Vector3(c.x + mt, topo, c.y + mt), Vector3(c.x - mt, topo, c.y + mt), Vector3.UP)
	var no := Node3D.new()
	no.name = "Piramide"
	add_child(no)
	p["no"] = no   # a etapa com poço no lugar dela a esconde (_pirâmides_do_poco)
	for par: Array in [[st_t, material_pedra(0, 1.1)], [st_p, material_pedra(2, hk * 0.35 / 2.0)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (par[0] as SurfaceTool).commit()
		mi.material_override = par[1]
		no.add_child(mi)
	var corpo := _corpo_mortal(no)
	corpo.remove_from_group("mortal")   # pedido do dono (2026-10-06): encostar na pirâmide não explode, só bate
	ComplexoLancamento.adicionar_colisoes(corpo, caixas)
	# Escadarias
	for f in str(p.escadas):
		_escadaria(no, corpo, p, f)
	# Braseiros acesos nos cantos do topo
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q := c + s * (mt - 4.0)
		var base := Vector3(q.x, topo, q.y)
		_caixa(no, Vector3(2.2, 1.6, 2.2), base + Vector3.UP * 0.8, material_pedra(2, 0.8))
		Fogo.criar(no, base + Vector3.UP * 1.7, 0.9, 3.5, 24, 1.4)
	if p.templo:
		_templo(no, Vector3(c.x, topo, c.y), mt)


## Escadaria numa face (S, N, E ou W): degraus de 0,55 m, alfardas dos lados e cabeças de serpente
## na base das alfardas.
func _escadaria(no: Node3D, corpo: StaticBody3D, p: Dictionary, f: String) -> void:
	var c: Vector2 = p.c
	var mb: float = p.mb
	var mt: float = p.mt
	var topo: float = p.topo
	var dir: Vector3 = {"S": Vector3(0, 0, 1), "N": Vector3(0, 0, -1), "E": Vector3(1, 0, 0), "W": Vector3(-1, 0, 0)}[f]
	var lat := Vector3.UP.cross(dir).normalized()
	var meia := mb * 0.13
	var ini := mb + 4.0     # pé da escada (fora da base)
	var fim := mt
	var degraus := int((topo - _chao) / 0.55)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centro := Vector3(c.x, 0.0, c.y)
	for k in degraus:
		var t0 := float(k) / degraus
		var t1 := float(k + 1) / degraus
		var d0 := lerpf(ini, fim, t0)
		var d1 := lerpf(ini, fim, t1)
		var y1 := _chao + (topo - _chao) * t1
		var y0 := _chao + (topo - _chao) * t0
		# espelho (vertical) e piso do degrau
		var e0 := centro + dir * d0 - lat * meia
		var e1 := centro + dir * d0 + lat * meia
		Egito._quad(st, e0 + Vector3.UP * y0, e1 + Vector3.UP * y0, e1 + Vector3.UP * y1, e0 + Vector3.UP * y1, dir)
		var f0 := centro + dir * d1 - lat * meia
		var f1 := centro + dir * d1 + lat * meia
		Egito._quad(st, e0 + Vector3.UP * y1, e1 + Vector3.UP * y1, f1 + Vector3.UP * y1, f0 + Vector3.UP * y1, Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material_pedra(0, 0.55)
	no.add_child(mi)
	# Alfardas: blocos inclinados dos dois lados
	var comp := Vector2(ini - fim, topo - _chao).length()
	var ang := atan2(topo - _chao, ini - fim)
	var meio := centro + dir * ((ini + fim) * 0.5) + Vector3.UP * ((topo + _chao) * 0.5 + 0.8)
	var alfardas: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		var b := Basis(lat, Vector3.UP, dir) * Basis(Vector3.RIGHT, ang)
		alfardas.append(Transform3D(b * Basis.from_scale(Vector3(2.4, 2.2, comp)), meio + lat * s * (meia + 1.2)))
		var cab := cabeca_serpente(4.2)
		cab.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), centro + dir * (ini + 1.2) + lat * s * (meia + 1.2) + Vector3.UP * (_chao - 0.2))
		no.add_child(cab)
	ComplexoLancamento.criar_multimesh(no, alfardas, material_pedra(2, 0.9))
	# Colisão da escada: uma rampa inclinada (mortal como o resto)
	var rampa := Transform3D(Basis(lat, Vector3.UP, dir) * Basis(Vector3.RIGHT, ang) * Basis.from_scale(Vector3(meia * 2.0 + 4.8, 2.0, comp)), meio - Vector3.UP * 1.6)
	ComplexoLancamento.adicionar_colisoes(corpo, [rampa])


## Templo no topo: base, cela com porta escura e colunas, e a crista vazada (cresteria) pintada.
func _templo(no: Node3D, base: Vector3, mt: float) -> void:
	var w := minf(mt * 1.2, 26.0)
	var est := material_pedra(1, 1.0)
	_caixa(no, Vector3(w, 1.2, w * 0.7), base + Vector3.UP * 0.6, material_pedra(0, 0.6))
	_caixa(no, Vector3(w * 0.85, 7.0, w * 0.55), base + Vector3.UP * 4.7, est)
	_caixa(no, Vector3(w * 0.95, 1.4, w * 0.62), base + Vector3.UP * 8.9, material_pedra(2, 0.7))
	var porta := StandardMaterial3D.new()
	porta.albedo_color = Color(0.03, 0.025, 0.02)
	_caixa(no, Vector3(w * 0.22, 4.6, 0.3), base + Vector3(0, 3.5, w * 0.28), porta)
	for k in 5:
		var x := lerpf(-w * 0.32, w * 0.32, float(k) / 4.0)
		_caixa(no, Vector3(w * 0.1, 6.0, 0.4), base + Vector3(x, 12.6, 0), est)
	_caixa(no, Vector3(w * 0.75, 1.0, 0.6), base + Vector3.UP * 15.9, material_pedra(2, 0.6))
	var corpo := _corpo_mortal(no)
	corpo.remove_from_group("mortal")   # o templo é parte da pirâmide: só bate
	ComplexoLancamento.adicionar_colisoes(corpo, [Transform3D(Basis.from_scale(Vector3(w * 0.9, 16.0, w * 0.6)), base + Vector3.UP * 8.0)])

## Colunas da serpente: fuste cilíndrico entalhado com escamas, anéis de jade e a cabeça no alto.
func _montar_colunas(pai: Node3D, lista: Array) -> void:
	if lista.is_empty():
		return
	var corpo := _corpo_mortal(pai)
	for col: Array in lista:
		var c: Vector2 = col[0]
		var r: float = col[1]
		var alto: float = col[2]
		var fuste := MeshInstance3D.new()
		var cil := CylinderMesh.new()
		cil.top_radius = r * 0.8
		cil.bottom_radius = r * 0.92
		cil.height = alto
		cil.radial_segments = 32
		fuste.mesh = cil
		fuste.material_override = material_pedra(2, r * 0.12)
		fuste.position = Vector3(c.x, _chao + alto * 0.5, c.y)
		pai.add_child(fuste)
		for k in 4:
			var anel := MeshInstance3D.new()
			var ca := CylinderMesh.new()
			var ra := lerpf(r * 0.92, r * 0.8, (k + 0.5) / 4.0) + 0.6
			ca.top_radius = ra
			ca.bottom_radius = ra
			ca.height = 2.4
			ca.radial_segments = 32
			anel.mesh = ca
			anel.material_override = material_jade() if k % 2 == 0 else material_ouro()
			anel.position = Vector3(c.x, _chao + alto * (k + 0.5) / 4.0, c.y)
			pai.add_child(anel)
		_caixa(pai, Vector3(r * 2.4, 4.0, r * 2.4), Vector3(c.x, _chao + 1.0, c.y), material_pedra(0, 1.0))
		var cab := cabeca_serpente(r * 2.2)
		cab.transform = Transform3D(Basis(Vector3.UP, Terreno._hash2(int(c.x), int(c.y)) * TAU), Vector3(c.x, _chao + alto - 0.5, c.y))
		pai.add_child(cab)
		var cs := CollisionShape3D.new()
		var forma := CylinderShape3D.new()
		forma.radius = r * 0.92
		forma.height = alto + 4.0
		cs.shape = forma
		cs.position = Vector3(c.x, _chao + alto * 0.5, c.y)
		corpo.add_child(cs)


# ------------------------------------------------------------------ cachoeira

## Cachoeira do paredão norte: lâmina d'água (shader com fios descendo) do alto do paredão até o
## lago, espuma e névoa na base, e o rio de cima chegando pelo canal.
func _montar_cachoeira(cfg: Dictionary) -> void:
	if cfg.is_empty() or not cfg.has("x"):
		return
	var x := float(cfg.get("x", -700))
	var z_pe := float(cfg.get("z_pe", -1735))
	var z_topo := float(cfg.get("z_topo", -1800))
	var y_topo := _terreno.altura_em(x, z_topo - 10.0)
	cachoeira(_etapa_no, Vector3(x, y_topo, z_topo), Vector3.BACK, z_pe - z_topo, float(cfg.get("largura", 60)))


## Cachoeira: lâmina d'água saindo do lábio `topo` (para `fora`, horizontal) e caindo em parábola até a água,
## `avanco` m à frente do lábio no pé; névoa e espuma embaixo. Usada pelo paredão e pela toca da cobra (E1).
## densa: três camadas quase opacas e muito vapor ao longo da queda e em volta de y_nevoa (esconde o que
## tem atrás, como a toca da cobra 3).
func cachoeira(pai: Node3D, topo: Vector3, fora: Vector3, avanco: float, larg: float, densa := false, y_nevoa := -INF) -> void:
	fora = Vector3(fora.x, 0.0, fora.z).normalized()
	var lado := Vector3.UP.cross(fora).normalized()
	var giro := Basis(-lado, Vector3.UP, fora)
	var raiz := Node3D.new()
	raiz.name = "Cachoeira"
	raiz.transform = Transform3D(giro, Vector3(topo.x, 0.0, topo.z))
	pai.add_child(raiz)
	var x := 0.0
	var z_topo := 0.0
	var z_pe := avanco
	var y_topo := topo.y
	var nivel := float(Config.valor("mapa.nivel_agua", 4))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for k in n:
		var t0 := float(k) / n
		var t1 := float(k + 1) / n
		# Perfil: sai na horizontal do lábio e cai em parábola, afastando do paredão
		var p0 := _ponto_queda(x, z_topo, z_pe, y_topo, nivel, t0)
		var p1 := _ponto_queda(x, z_topo, z_pe, y_topo, nivel, t1)
		for s in 6:
			var u0 := lerpf(-0.5, 0.5, float(s) / 6.0)
			var u1 := lerpf(-0.5, 0.5, float(s + 1) / 6.0)
			var w0 := larg * (1.0 + t0 * 0.25)
			var w1 := larg * (1.0 + t1 * 0.25)
			var q := [p0 + Vector3(u0 * w0, 0, 0), p0 + Vector3(u1 * w0, 0, 0), p1 + Vector3(u1 * w1, 0, 0), p1 + Vector3(u0 * w1, 0, 0)]
			var uv := [Vector2(u0 + 0.5, t0), Vector2(u1 + 0.5, t0), Vector2(u1 + 0.5, t1), Vector2(u0 + 0.5, t1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3(0, 0.2, 1).normalized())
				st.set_uv(uv[idx])
				st.add_vertex(q[idx])
	var lamina := st.commit()
	# Cachoeira nova (pacote do dono em assets/MAPA SERPENTE/cachoeira/waterfall): lâmina em três camadas com
	# textura de fluxo, espuma, névoa e respingos na base. selva.cachoeira_nova = false (ou TSC_CACHOEIRA_VELHA)
	# volta para a lâmina antiga.
	var nova := bool(_cfg.get("cachoeira_nova", true)) and OS.get_environment("TSC_CACHOEIRA_VELHA") == ""
	if nova:
		var wf: Node3D = load(CACHOEIRA_NOVA).new()
		wf.name = "CachoeiraModelo"
		wf.altura_m = y_topo - nivel
		wf.largura_m = larg
		wf.projecao_m = z_pe + 6.0
		wf.criar_lago = false   # o lago dele é um plano de 1500 m; aqui a água é a do mapa
		wf.opacidade = 1.6 if densa else 1.0
		wf.envolver_m = (z_pe + 6.0) * 0.55 if densa else larg * 0.12   # densa: as bordas voltam para o paredão (escondem a toca de lado) mas terminam no ar, em fios
		wf.position = Vector3(x, nivel, z_topo + z_pe + 8.0)
		raiz.add_child(wf)
	for camada in (0 if nova else (3 if densa else 1)):
		var mi := MeshInstance3D.new()
		mi.mesh = lamina
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/cachoeira.gdshader")
		mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.04, 3, 333 + camada))
		mat.set_shader_parameter("opaco", 0.9 if densa else 0.0)
		mat.set_shader_parameter("velocidade", 0.55 + 0.12 * camada)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0.0, 0.0, camada * 1.6)
		mi.scale = Vector3(1.0 + camada * 0.06, 1.0, 1.0)
		raiz.add_child(mi)
	if densa:
		# Laterais: cortinas d'água do paredão até a frente da queda (de lado não se vê a toca)
		var lado_st := SurfaceTool.new()
		lado_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var fundo := z_pe + 4.0
		for sx: float in [-1.0, 1.0]:
			var xx := sx * larg * 0.56
			var nseg := 12
			for k in nseg:
				var t0 := float(k) / nseg
				var t1 := float(k + 1) / nseg
				var y0 := lerpf(y_topo, nivel - 0.5, t0)
				var y1 := lerpf(y_topo, nivel - 0.5, t1)
				var q := [Vector3(xx, y0, -3.0), Vector3(xx, y0, fundo), Vector3(xx, y1, fundo), Vector3(xx, y1, -3.0)]
				var uv := [Vector2(0.15, t0), Vector2(0.85, t0), Vector2(0.85, t1), Vector2(0.15, t1)]
				for idx in [0, 1, 2, 0, 2, 3]:
					lado_st.set_normal(Vector3(sx, 0, 0))
					lado_st.set_uv(uv[idx])
					lado_st.add_vertex(q[idx])
		var lados := lado_st.commit()
		for camada in (0 if nova else 2):   # a cachoeira nova se curva até o paredão: sem cortina plana
			var ml := MeshInstance3D.new()
			ml.mesh = lados
			var mat_l := ShaderMaterial.new()
			if nova:   # mesma água da cachoeira nova (o relógio do shader anda com o modelo)
				var wf_l: Node3D = raiz.get_node("CachoeiraModelo")
				mat_l.shader = wf_l.FLOW_SHADER
				mat_l.set_shader_parameter("flow_texture", wf_l._textura_fluxo())
				mat_l.set_shader_parameter("height_m", y_topo - nivel)
				mat_l.set_shader_parameter("phase", 0.37 + camada * 0.731)
				mat_l.set_shader_parameter("opacity", 0.95 if camada == 0 else 0.5)
				mat_l.set_shader_parameter("turbulence", 0.0)
				wf_l._materials.append(mat_l)
			else:
				mat_l.shader = load("res://shaders/cachoeira.gdshader")
				mat_l.set_shader_parameter("ruido", Terreno._textura_ruido(0.04, 3, 340 + camada))
				mat_l.set_shader_parameter("opaco", 0.92)
				mat_l.set_shader_parameter("velocidade", 0.6 + 0.15 * camada)
			ml.material_override = mat_l
			ml.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ml.scale = Vector3(1.0 + camada * 0.05, 1.0, 1.0)
			raiz.add_child(ml)
		# Mata no alto, dos dois lados do lábio da cachoeira
		var rng := RandomNumberGenerator.new()
		rng.seed = 919
		var copas: Array = []
		var baixas: Array = []
		for k in 90:
			var a := rng.randf_range(-PI, PI)
			var r := rng.randf_range(larg * 0.75, larg * 2.8)
			var lx := cos(a) * r
			var lz := -absf(sin(a)) * r * 0.9 - 4.0   # atrás do lábio, em cima da montanha
			var w := raiz.transform * Vector3(lx, 0.0, lz)
			var hh := _terreno.altura_em(w.x, w.z)
			if hh < y_topo - 25.0:
				continue
			var item := [Vector3(w.x, hh - 0.3, w.z), rng.randf_range(0.5, 1.0) if k % 3 == 0 else rng.randf_range(1.4, 2.6), rng.randf() * TAU, Color(1, 1, 1) * rng.randf_range(0.8, 1.05)]
			(copas if k % 3 == 0 else baixas).append(item)
		Vegetacao.plantar(pai, Vegetacao.Tipo.COPA, copas, 400.0, 2500.0, true)
		Vegetacao.plantar(pai, Vegetacao.Tipo.SAMAMBAIA, baixas, 300.0, 900.0, false)
		Vegetacao.colidir(pai, Vegetacao.Tipo.COPA, copas)
		# Vapor ao longo de toda a queda e uma nuvem grossa na altura da toca
		var meio_y := (y_topo + nivel) * 0.5
		raiz.add_child(_vapor(Vector3(0.0, meio_y, z_pe + 5.0), Vector3(larg * 0.65, (y_topo - nivel) * 0.5, 6.0), 700, 26.0, 0.28))
		if y_nevoa > -INF:
			raiz.add_child(_vapor(Vector3(0.0, y_nevoa + 3.0, z_pe + 7.0), Vector3(larg * 0.8, 8.0, 10.0), 900, 18.0, 0.45))
		raiz.add_child(_vapor(Vector3(0.0, nivel + 4.0, z_pe + 10.0), Vector3(larg * 0.9, 3.0, 14.0), 600, 30.0, 0.35))
	if nova:
		return   # a base (espuma, névoa, respingos) vem no modelo
	# Névoa e espuma na base
	var base := Vector3(x, nivel + 2.0, z_pe + 12.0)
	var part := GPUParticles3D.new()
	part.amount = 260
	part.lifetime = 5.0
	part.preprocess = 4.0
	part.visibility_aabb = AABB(Vector3(-120, -10, -120), Vector3(240, 140, 240))
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(larg * 0.6, 2.0, 8.0)
	proc.direction = Vector3(0, 1, 0.6)
	proc.spread = 35.0
	proc.initial_velocity_min = 4.0
	proc.initial_velocity_max = 10.0
	proc.gravity = Vector3(0, 0.4, 0)
	proc.scale_min = 8.0
	proc.scale_max = 18.0
	proc.color = Color(1, 1, 1, 0.35)
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.2))
	curva.add_point(Vector2(0.4, 1.0))
	curva.add_point(Vector2(1, 0.0))
	var tc := CurveTexture.new()
	tc.curve = curva
	proc.alpha_curve = tc
	part.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mq := StandardMaterial3D.new()
	mq.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mq.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mq.albedo_color = Color(0.92, 0.96, 1.0, 0.22)
	mq.albedo_texture = _textura_nuvem()
	mq.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mq.vertex_color_use_as_albedo = true
	quad.material = mq
	part.draw_pass_1 = quad
	part.position = base
	raiz.add_child(part)
	# Arco de espuma branca no lago
	var espuma := MeshInstance3D.new()
	var disco := CylinderMesh.new()
	disco.top_radius = larg * 0.75
	disco.bottom_radius = larg * 0.75
	disco.height = 0.2
	espuma.mesh = disco
	var me := ShaderMaterial.new()
	me.shader = load("res://shaders/espuma.gdshader")
	me.set_shader_parameter("ruido", Terreno._textura_ruido(0.06, 3, 334))
	espuma.material_override = me
	espuma.position = Vector3(x, nivel + 0.12, z_pe + larg * 0.4)
	espuma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	raiz.add_child(espuma)


## Nuvem de vapor d'água (partículas brancas macias subindo devagar e se espalhando).
func _vapor(centro: Vector3, ext: Vector3, qtd: int, tam: float, alfa: float) -> GPUParticles3D:
	var part := GPUParticles3D.new()
	part.amount = qtd
	part.lifetime = 6.0
	part.preprocess = 6.0
	part.position = centro
	part.visibility_aabb = AABB(-ext - Vector3(60, 60, 60), (ext + Vector3(60, 60, 60)) * 2.0)
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = ext
	proc.direction = Vector3(0, 0.6, 1)
	proc.spread = 70.0
	proc.initial_velocity_min = 1.5
	proc.initial_velocity_max = 5.0
	proc.gravity = Vector3(0, 0.5, 0)
	proc.damping_min = 0.5
	proc.damping_max = 1.0
	proc.scale_min = tam * 0.5
	proc.scale_max = tam
	proc.angle_min = 0.0
	proc.angle_max = 360.0
	var curva := Curve.new()
	curva.add_point(Vector2(0, 0.0))
	curva.add_point(Vector2(0.25, 1.0))
	curva.add_point(Vector2(1, 0.0))
	var tc := CurveTexture.new()
	tc.curve = curva
	proc.alpha_curve = tc
	part.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mq := StandardMaterial3D.new()
	mq.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mq.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mq.albedo_color = Color(0.94, 0.97, 1.0, alfa)
	mq.albedo_texture = _textura_nuvem()
	mq.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mq.vertex_color_use_as_albedo = true
	mq.proximity_fade_enabled = true
	mq.proximity_fade_distance = 4.0
	quad.material = mq
	part.draw_pass_1 = quad
	return part


func _ponto_queda(x: float, z_topo: float, z_pe: float, y_topo: float, nivel: float, t: float) -> Vector3:
	var y := lerpf(y_topo + 0.5, nivel - 0.5, t)
	var avanco := (z_pe - z_topo) * (1.0 - (1.0 - t) * (1.0 - t)) + 6.0 * t
	return Vector3(x, y, z_topo + avanco + 2.0)


static func _textura_nuvem() -> ImageTexture:
	if _mats.has("nuvem"):
		return _mats["nuvem"]
	# Bola de fumaça/poeira: borda macia e "couve-flor" (ruído fractal), sem contorno de disco
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var ruido := FastNoiseLite.new()
	ruido.seed = 5
	ruido.frequency = 0.045
	ruido.fractal_octaves = 4
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
			var r := ruido.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(1.0 - d * (0.8 + 0.5 * (1.0 - r)), 0.0, 1.0)
			a = smoothstep(0.0, 1.0, a) * (0.55 + 0.45 * r)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_mats["nuvem"] = tex
	return tex


# ------------------------------------------------------------------ ruínas e esculturas

## Jogo de bola (dois muros inclinados com os anéis), estelas, altares e cabeças de jaguar
## espalhados pela mata (sem colisão: longe da estrada e do voo).
func _montar_ruinas() -> void:
	var pedra := material_pedra(0, 0.9)
	var friso := material_pedra(2, 0.8)
	for jb in _cfg.get("jogo_de_bola", []):
		var c := Vector3(float(jb[0]), 0.0, float(jb[1]))
		c.y = _terreno.altura_base(c.x, c.z)
		var giro := Basis(Vector3.UP, deg_to_rad(float(jb[2])))
		for s: float in [-1.0, 1.0]:
			_caixa(self, Vector3(14.0, 5.0, 90.0), c + giro * Vector3(s * 22.0, 2.0, 0), pedra, giro)
			_caixa(self, Vector3(6.0, 9.0, 90.0), c + giro * Vector3(s * 28.0, 4.0, 0), friso, giro)
			var anel := MeshInstance3D.new()
			var tor := TorusMesh.new()
			tor.inner_radius = 0.9
			tor.outer_radius = 1.6
			anel.mesh = tor
			anel.material_override = friso
			# Engastado na face do muro alto (a 15,4 m ficava solto no ar, acima da banqueta)
			anel.transform = Transform3D(giro * Basis(Vector3.FORWARD, PI * 0.5), c + giro * Vector3(s * 24.3, 6.4, 0))
			add_child(anel)
		_caixa(self, Vector3(30.0, 0.4, 110.0), c + Vector3.UP * 0.1, material_pedra(1, 2.0), giro)
	var estelas: Array[Transform3D] = []
	for e in _cfg.get("estelas", []):
		var q := Vector3(float(e[0]), 0.0, float(e[1]))
		q.y = _terreno.altura_base(q.x, q.z)
		estelas.append(Transform3D(Basis(Vector3.UP, float(e[2])) * Basis.from_scale(Vector3(3.0, 9.0, 1.2)), q + Vector3.UP * 4.0))
	ComplexoLancamento.criar_multimesh(self, estelas, friso)
	for j in _cfg.get("jaguares", []):
		var cab := cabeca_jaguar(float(j[3]))
		var q := Vector3(float(j[0]), 0.0, float(j[1]))
		q.y = _terreno.altura_base(q.x, q.z) - 0.4
		cab.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(j[2]))), q)
		add_child(cab)


# ------------------------------------------------------------------ vegetação

## Mata fechada no vale e nos morros em volta, longe das construções, dos alvos, dos cercados e de
## onde alguma estrada passa baixa (a copa atravessaria o asfalto).
func _sortear_vegetacao() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(Config.valor("mapa.semente_terreno", 1)) + 77
	var nivel := float(Config.valor("mapa.nivel_agua", 4))
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var qtd: Dictionary = _cfg.get("vegetacao", {})
	var listas := {"gigante": [], "copa": [], "palmeira": [], "bananeira": [], "samambaia": []}
	var metas := {"gigante": int(qtd.get("gigantes", 1400)), "copa": int(qtd.get("copas", 9000)), "palmeira": int(qtd.get("palmeiras", 2600)),
		"bananeira": int(qtd.get("bananeiras", 9000)), "samambaia": int(qtd.get("samambaias", 12000))}
	var alturas := {"gigante": 46.0, "copa": 24.0, "palmeira": 16.0, "bananeira": 6.0, "samambaia": 2.5}
	var evitar := _areas_livres()
	var x0 := float(vale[0]) - 900.0
	var x1 := float(vale[2]) + 900.0
	var z0 := float(vale[1]) - 900.0
	var z1 := float(vale[3]) + 900.0
	var tentativas := 0
	var faltam := true
	while faltam and tentativas < 700000:
		tentativas += 1
		var x := rng.randf_range(x0, x1)
		var z := rng.randf_range(z0, z1)
		if absf(x) > Terreno.MEIO_INTERNO - 60.0 or absf(z) > Terreno.MEIO_INTERNO - 60.0:
			continue
		var p := Vector2(x, z)
		var h := _terreno.altura_base(x, z)
		if h < nivel + 1.2 or altura(x, z) > -INF:
			continue
		var dentro := x > float(vale[0]) and x < float(vale[2]) and z > float(vale[1]) and z < float(vale[3])
		var livre := true
		for e: Array in evitar:
			if p.distance_to(e[0]) < e[1]:
				livre = false
				break
		if not livre:
			continue
		var sorteio := rng.randf()
		var tipo := ""
		if not dentro:
			tipo = "copa" if sorteio < 0.75 else ("gigante" if sorteio < 0.85 else "palmeira")
		elif sorteio < 0.06:
			tipo = "gigante"
		elif sorteio < 0.36:
			tipo = "copa"
		elif sorteio < 0.46:
			tipo = "palmeira"
		elif sorteio < 0.72:
			tipo = "bananeira"
		else:
			tipo = "samambaia"
		var lista: Array = listas[tipo]
		if lista.size() >= int(metas[tipo]):
			faltam = false
			for k in listas:
				if (listas[k] as Array).size() < int(metas[k]):
					faltam = true
			continue
		var esc := rng.randf_range(0.75, 1.25)
		if tipo in ["gigante", "copa", "palmeira"] and not _plano(x, z, 9.0):
			continue
		if _estrada_perto(p, h, float(alturas[tipo]) * esc):
			continue
		var tinta := Color(1, 1, 1) * rng.randf_range(0.8, 1.12)
		tinta.g *= rng.randf_range(0.95, 1.1)
		var giro := rng.randf() * TAU
		if _na_trilha(p):
			continue   # depois dos sorteios: o resto da mata fica onde sempre esteve
		lista.append([Vector3(x, h - 0.3, z), esc, giro, tinta])
	# Sub-bosque: moitas densas (a copa em miniatura) cobrindo o chão do vale
	var moitas := []
	var n_moitas := int(qtd.get("moitas", 26000))
	tentativas = 0
	while moitas.size() < n_moitas and tentativas < n_moitas * 4:
		tentativas += 1
		var x := rng.randf_range(float(vale[0]), float(vale[2]))
		var z := rng.randf_range(float(vale[1]), float(vale[3]))
		var h := _terreno.altura_base(x, z)
		if h < nivel + 1.2 or h > 20.0 or altura(x, z) > -INF:
			continue
		var p := Vector2(x, z)
		var livre := true
		for e: Array in evitar:
			if p.distance_to(e[0]) < e[1]:
				livre = false
				break
		if not livre or _estrada_perto(p, h, 6.0):
			continue
		var moita := [Vector3(x, h - 0.6, z), rng.randf_range(0.18, 0.34), rng.randf() * TAU, Color(0.85, 1.0, 0.8) * rng.randf_range(0.75, 1.1)]
		if not _na_trilha(p):
			moitas.append(moita)
	return {"listas": listas, "moitas": moitas}


func _montar_vegetacao() -> void:
	var dados: Dictionary = _cache("vegetacao", _sortear_vegetacao)
	var listas: Dictionary = dados.listas
	var moitas: Array = dados.moitas
	var antes := get_child_count()
	Vegetacao.plantar(self, Vegetacao.Tipo.COPA, moitas, 220.0, 950.0, false)
	Vegetacao.plantar(self, Vegetacao.Tipo.SUMAUMA, listas.gigante, 500.0, 4200.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.COPA, listas.copa, 400.0, 3000.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.PALMEIRA_SELVA, listas.palmeira, 400.0, 2400.0, true)
	Vegetacao.plantar(self, Vegetacao.Tipo.BANANEIRA, listas.bananeira, 250.0, 900.0, false)
	Vegetacao.plantar(self, Vegetacao.Tipo.SAMAMBAIA, listas.samambaia, 200.0, 500.0, false)
	var tc := Time.get_ticks_msec()
	_montar_capim()
	if OS.get_environment("TSC_TEMPO") != "":
		print("[TEMPO] capim %d ms" % (Time.get_ticks_msec() - tc))
	Vegetacao.colidir(self, Vegetacao.Tipo.SUMAUMA, listas.gigante)
	Vegetacao.colidir(self, Vegetacao.Tipo.COPA, listas.copa)
	Vegetacao.colidir(self, Vegetacao.Tipo.PALMEIRA_SELVA, listas.palmeira)
	Vegetacao.colidir(self, Vegetacao.Tipo.BANANEIRA, listas.bananeira)
	for k in range(antes, get_child_count()):
		if get_child(k) is MultiMeshInstance3D:
			_mata.append(get_child(k))
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SELVA] vegetação: ", {"gigante": listas.gigante.size(), "copa": listas.copa.size(), "palmeira": listas.palmeira.size(), "bananeira": listas.bananeira.size(), "samambaia": listas.samambaia.size()})


## Círculos [centro, raio] sem vegetação: cercados de todas as etapas, alvos e pés da cachoeira.
func _areas_livres() -> Array:
	var lista := []
	var percursos: Dictionary = Config.valor("mapa.subida.percursos", {})
	for k in percursos:
		var pc: Dictionary = percursos[k]
		for chave in ["largada", "plataforma"]:
			var r: Dictionary = pc.get(chave, {})
			if r.is_empty():
				continue
			var o: Array = r.get("origem", [0, 0, 0])
			var f: Array = r.get("frente", [0, -1])
			var comp := float(r.get("comprimento", 70))
			var c := Vector2(float(o[0]), float(o[2])) + Vector2(float(f[0]), float(f[1])) * comp * 0.5
			lista.append([c, maxf(comp, float(r.get("largura", 90))) * 0.75 + 15.0])
	for e in Config.valor("etapas", []):
		var d: Array = (e as Dictionary).get("deslocamento", [0, 0])
		lista.append([Vector2(float(d[0]), float(d[1])), 45.0])
	for jb in _cfg.get("jogo_de_bola", []):
		lista.append([Vector2(float(jb[0]), float(jb[1])), 70.0])
	return lista


## Alguma estrada (de qualquer etapa) passa a menos de 16 m daqui com o fundo abaixo do topo da planta?
func _estrada_perto(p: Vector2, chao: float, alto: float) -> bool:
	var lista: Array = _grade_estrada.get(Vector2i(floori(p.x / CEL), floori(p.y / CEL)), [])
	for seg: Array in lista:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.01), 0.0, 1.0)
		if p.distance_to(a2 + ab * t) < 16.0 + alto * 0.25 and lerpf(a.y, b.y, t) - 4.0 < chao + alto:
			return true
	return false


func _plano(x: float, z: float, limite: float) -> bool:
	var dx := _terreno.altura_base(x + 6.0, z) - _terreno.altura_base(x - 6.0, z)
	var dz := _terreno.altura_base(x, z + 6.0) - _terreno.altura_base(x, z - 6.0)
	return absf(dx) + absf(dz) <= limite


## Bancos de neblina baixa sobre a mata e o lago (a selva "fuma" de umidade).
func _montar_bruma() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var xf: Array[Transform3D] = []
	var sementes := PackedFloat32Array()
	for k in 260:
		var x := rng.randf_range(float(vale[0]) - 1500.0, float(vale[2]) + 1500.0)
		var z := rng.randf_range(float(vale[1]) - 1500.0, float(vale[3]) + 1500.0)
		var h := _terreno.altura_em(x, z)
		var esc := rng.randf_range(110.0, 260.0)
		xf.append(Transform3D(Basis.from_scale(Vector3.ONE * esc), Vector3(x, h + rng.randf_range(18.0, 45.0), z)))
		sementes.append(rng.randf() * 10.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bruma.gdshader")
	mat.set_shader_parameter("ruido", Terreno._textura_ruido(0.02, 4, 97))
	quad.material = mat
	mm.mesh = quad
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, Color(sementes[i], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-6000, -50, -6000), Vector3(12000, 600, 12000))
	add_child(mmi)


# ------------------------------------------------------------------ etapas

## Troca o que muda por etapa: colunas da serpente no caminho do voo, a serpente gigante e o vento.
func preparar_etapa(indice: int, cfg_etapa: Dictionary) -> void:
	for f in _etapa_no.get_children():
		f.queue_free()
	_restaurar_mata()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: restaurar mata" % Time.get_ticks_msec())
	_colunas_etapa.clear()
	var e: Dictionary = _cfg.get("etapas", {}).get(str(indice + 1), {})
	for c in e.get("colunas", []):
		_colunas_etapa.append([Vector2(float(c[0]), float(c[1])), float(c[2]), float(c[3])])
	_montar_colunas(_etapa_no, _colunas_etapa)
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: colunas" % Time.get_ticks_msec())
	if (indice + 1) in Array(_serpente_cfg.get("etapas", [])).map(func(n): return int(n)) and not _trilha_serpente.is_empty():
		var serpente := SerpenteGigante.new()
		_etapa_no.add_child(serpente)
		serpente.montar(_trilha_serpente, _terreno, _serpente_cfg)
	var extras: Array = _cfg.get("cobras_extras", [])
	for k in extras.size():
		var c: Dictionary = extras[k]
		if (indice + 1) in Array(c.get("etapas", [1])).map(func(n): return int(n)) and _trilhas_extras[k].size() > 8:
			var cobra := SerpenteGigante.new()
			_etapa_no.add_child(cobra)
			cobra.montar(_trilhas_extras[k], _terreno, c)
			cobra.name = "Cobra_" + str(c.get("cor", k))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: serpentes" % Time.get_ticks_msec())
	_mata_da_etapa()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: mata da etapa" % Time.get_ticks_msec())
	_montar_cachoeira(cachoeira_da_etapa(indice))
	_montar_poco()
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: cachoeira" % Time.get_ticks_msec())
	RochasSelva.so_percurso = "" if indice == 0 else str(indice + 1)   # da E2 em diante: só a pista da etapa
	var e_r: Dictionary = _cfg.get("etapas", {}).get(str(indice + 1), {})
	var de: Array = e_r.get("rochas_dentro", [])
	var lista_r: Array = e_r.get("rochas", []).duplicate()
	if bool(e_r.get("rochas_paredoes", false)):
		lista_r.append_array(RochasSelva.paredoes(_terreno, Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000]), 55.0, e_r.get("rochas_livres", [])))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: paredoes (lista %d)" % [Time.get_ticks_msec(), lista_r.size()])
	RochasSelva.montar(_etapa_no, _terreno, lista_r, Vector2(float(de[0]), float(de[1])) if de.size() == 2 else Vector2(INF, INF), e_r.get("rochas_livres", []))
	if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: rochas" % Time.get_ticks_msec())
	if _rio_etapa_mascara != indice and _terreno._mat_terreno:
		_rio_etapa_mascara = indice
		_terreno._mat_terreno.set_shader_parameter("mascara_rio", textura_margem(Terreno.MEIO_INTERNO))
		if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: mascara do rio" % Time.get_ticks_msec())
	if OS.get_environment("TSC_ALTURAS") != "":   # conferência: alturas do chão em "x,z;x,z;..."
		for par in OS.get_environment("TSC_ALTURAS").split(";"):
			var xz := par.split(",")
			print("[ALT] %s,%s = %.1f" % [xz[0], xz[1], _terreno.altura_em(float(xz[0]), float(xz[1]))])
	# Encostas de mata virgem só na etapa 1 (pedido do dono: as outras ficam como estavam)
	var virgem := indice == 0
	if _terreno._mat_terreno:
		_terreno._mat_terreno.set_shader_parameter("mata_virgem", virgem)
		if _rocha_lad == null:
			var img := Recinto.ler_imagem("res://assets/selva/rochas/rocha_ladrilho.png")
			if img:
				img.generate_mipmaps()
				_rocha_lad = ImageTexture.create_from_image(img)
		_terreno._mat_terreno.set_shader_parameter("rocha_lad", _rocha_lad)
		_terreno._mat_terreno.set_shader_parameter("com_rocha_lad", _rocha_lad != null)   # todas as etapas
		if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: rocha ladrilho" % Time.get_ticks_msec())
	if virgem:
		_mata_encosta()
		if OS.get_environment("TSC_TEMPO") != "": print("[T] %6d ms    etapa: mata da encosta" % Time.get_ticks_msec())
	_vento_cfg = cfg_etapa.get("vento", {})
	if _vento_cfg.is_empty():
		Veiculo.vento = Vector3.ZERO


## Poço do alvo da etapa (Terreno.poco_da_etapa): a pirâmide que estava ali some (sem malha e sem colisão) e
## PocoNinho monta parede, boca, fundo, a pirâmide do ninho e as cobras.
func _montar_poco() -> void:
	var poco := _terreno.poco_da_etapa()
	for p: Dictionary in _piramides:
		var oculta := poco.size() >= 4 and (p.c as Vector2).distance_to(Vector2(float(poco[0]), float(poco[1]))) < float(poco[2]) + float(p.mb)
		# (só mexe na que muda: as outras podem ter a colisão desligada por quem está em cima delas — a plataforma)
		if bool(p.get("oculta", false)) == oculta:
			continue
		p["oculta"] = oculta
		var no: Node3D = p.get("no")
		if no:
			no.visible = not oculta
			for corpo in no.find_children("*", "CollisionObject3D", true, false):
				if oculta:
					corpo.set_meta("camada", (corpo as CollisionObject3D).collision_layer)
				(corpo as CollisionObject3D).collision_layer = 0 if oculta else int(corpo.get_meta("camada", 1))
	if poco.size() < 4:
		return
	var pn := PocoNinho.new()
	pn.name = "PocoNinho"
	_etapa_no.add_child(pn)
	pn.montar(_terreno, poco, _cfg.get("poco", {}))


## Mata em cima do chão que a etapa levantou (terra preenchida e montanhas de montanhas.etapas.N): a mata
## do vale é plantada uma vez só, no chão (Terreno.altura_base), e ali fica enterrada.
func _mata_da_etapa() -> void:
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5501
	var listas := {"gigante": [], "copa": [], "palmeira": [], "moita": []}
	var metas := {"gigante": 900, "copa": 5200, "palmeira": 900, "moita": 9000}
	var tentativas := 0
	var faltam := true
	while faltam and tentativas < 160000:
		tentativas += 1
		var x := rng.randf_range(float(vale[0]), float(vale[2]))
		var z := rng.randf_range(float(vale[1]), float(vale[3]))
		if not _terreno.elevado_na_etapa(x, z):
			if tentativas > 4000 and listas.copa.is_empty():
				return   # etapa sem chão levantado
			continue
		var h := _terreno.altura_em(x, z)
		var sorteio := rng.randf()
		var tipo := "moita" if sorteio < 0.5 else ("copa" if sorteio < 0.82 else ("gigante" if sorteio < 0.91 else "palmeira"))
		var lista: Array = listas[tipo]
		if lista.size() >= int(metas[tipo]):
			faltam = false
			for k in listas:
				faltam = faltam or (listas[k] as Array).size() < int(metas[k])
			continue
		var dx := _terreno.altura_em(x + 6.0, z) - _terreno.altura_em(x - 6.0, z)
		var dz := _terreno.altura_em(x, z + 6.0) - _terreno.altura_em(x, z - 6.0)
		if absf(dx) + absf(dz) > (14.0 if tipo == "moita" else 9.0) or _estrada_perto(Vector2(x, z), h, 30.0):
			continue
		var esc := rng.randf_range(0.18, 0.34) if tipo == "moita" else rng.randf_range(0.75, 1.25)
		var tinta := Color(1, 1, 1) * rng.randf_range(0.8, 1.12)
		lista.append([Vector3(x, h - (0.6 if tipo == "moita" else 0.3), z), esc, rng.randf() * TAU, tinta])
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.COPA, listas.moita, 220.0, 950.0, false)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.SUMAUMA, listas.gigante, 500.0, 4200.0, true)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.COPA, listas.copa, 400.0, 3000.0, true)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.PALMEIRA_SELVA, listas.palmeira, 400.0, 2400.0, true)
	Vegetacao.colidir(_etapa_no, Vegetacao.Tipo.SUMAUMA, listas.gigante)
	Vegetacao.colidir(_etapa_no, Vegetacao.Tipo.COPA, listas.copa)
	Vegetacao.colidir(_etapa_no, Vegetacao.Tipo.PALMEIRA_SELVA, listas.palmeira)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SELVA] mata da etapa: ", {"gigante": listas.gigante.size(), "copa": listas.copa.size(), "palmeira": listas.palmeira.size(), "moita": listas.moita.size()})


## Mata virgem nas encostas das montanhas da etapa (pedido do dono, 2026-10-05): arbustos e árvores
## agarrados no paredão, samambaias e bananeiras nos degraus, palmeiras na beirada e cortinas de cipó
## penduradas (Vegetacao CIPO, deitadas na rampa). Pontos sorteados nas células íngremes da grade do
## terreno, longe das estradas e das construções; refeito a cada etapa (o terreno muda).
func _mata_encosta() -> void:
	var t0 := Time.get_ticks_msec()
	# (o sorteio das plantas só muda com o mapa: guardado em user://cache como o da vegetação do vale)
	var sorteadas: Dictionary = _cache("encosta", _sortear_encosta)
	var listas: Dictionary = sorteadas.listas
	var cipos: Array = sorteadas.cipos
	_plantar_encosta(t0, listas, cipos)


func _sortear_encosta() -> Dictionary:
	var vale: Array = Config.valor("mapa.subida.vale", [-2100, -1750, 1100, 1000])
	var a := _terreno.alturas_interno
	var n := Terreno.N_INTERNO
	var meio := Terreno.MEIO_INTERNO
	var passo := meio * 2.0 / (n - 1)
	var folga := 700.0
	var ix0 := clampi(floori((float(vale[0]) - folga + meio) / passo), 1, n - 2)
	var ix1 := clampi(ceili((float(vale[2]) + folga + meio) / passo), 1, n - 2)
	var iz0 := clampi(floori((float(vale[1]) - folga + meio) / passo), 1, n - 2)
	var iz1 := clampi(ceili((float(vale[3]) + folga + meio) / passo), 1, n - 2)
	var nivel := float(Config.valor("mapa.nivel_agua", 4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 8807
	var listas := {Vegetacao.Tipo.COPA: [], Vegetacao.Tipo.SAMAMBAIA: [], Vegetacao.Tipo.BANANEIRA: [], Vegetacao.Tipo.PALMEIRA_SELVA: []}
	var cipos: Array = []   # [Transform3D]
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var gx := (a[iz * n + ix + 1] - a[iz * n + ix - 1]) / (2.0 * passo)
			var gz := (a[(iz + 1) * n + ix] - a[(iz - 1) * n + ix]) / (2.0 * passo)
			var g := sqrt(gx * gx + gz * gz)
			if g < 0.55:
				continue
			var qtd := 4 + int(g * 3.0)
			for k in mini(qtd, 12):
				var x := -meio + (ix + rng.randf_range(-0.5, 0.5)) * passo
				var z := -meio + (iz + rng.randf_range(-0.5, 0.5)) * passo
				var h := _terreno.altura_em(x, z)
				if h < nivel + 1.5 or altura(x, z) > -INF:
					continue
				var p := Vector2(x, z)
				if _estrada_perto(p, h, 10.0) or _na_trilha(p):
					continue
				# Normal e inclinação ali
				var e := 2.0
				var hx := (_terreno.altura_em(x + e, z) - _terreno.altura_em(x - e, z)) / (2.0 * e)
				var hz := (_terreno.altura_em(x, z + e) - _terreno.altura_em(x, z - e)) / (2.0 * e)
				var nrm := Vector3(-hx, 1.0, -hz).normalized()
				var incl := sqrt(hx * hx + hz * hz)
				if incl > 1.6:
					continue   # paredão quase vertical: só rocha (pedido do dono)
				var sorteio := rng.randf()
				var tinta := Color(1, 1, 1) * rng.randf_range(0.7, 1.05)
				tinta.g *= rng.randf_range(0.95, 1.1)
				# Afunda um pouco na rampa: o pé fica escondido no barranco
				var base := Vector3(x, h - 0.4 - minf(incl, 3.0) * 0.6, z)
				if sorteio < 0.32 and incl > 0.8:
					# Cortina de cipó deitada na rampa: +Y sobe a encosta, +Z para fora
					var fora := Vector3(nrm.x, 0.0, nrm.z).normalized()
					var lado := Vector3.UP.cross(fora).normalized()
					var sobe := nrm.cross(lado).normalized()   # na rampa, para cima
					if sobe.y < 0.0:
						sobe = -sobe
					var esc := rng.randf_range(1.4, 2.6)
					var b := Basis(lado, sobe, lado.cross(sobe).normalized()).scaled(Vector3(esc, esc, esc))
					cipos.append([Transform3D(b, Vector3(x, h, z) + nrm * 0.25), tinta])
				elif sorteio < 0.62:
					listas[Vegetacao.Tipo.COPA].append([base, rng.randf_range(0.3, 0.75), rng.randf() * TAU, tinta])
				elif sorteio < 0.86:
					listas[Vegetacao.Tipo.SAMAMBAIA].append([base, rng.randf_range(2.0, 3.5), rng.randf() * TAU, tinta])
				elif sorteio < 0.96:
					listas[Vegetacao.Tipo.BANANEIRA].append([base, rng.randf_range(1.3, 2.2), rng.randf() * TAU, tinta])
				else:
					listas[Vegetacao.Tipo.PALMEIRA_SELVA].append([base, rng.randf_range(0.6, 1.0), rng.randf() * TAU, tinta])
	return {"listas": listas, "cipos": cipos}


func _plantar_encosta(t0: int, listas: Dictionary, cipos: Array) -> void:
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.COPA, listas[Vegetacao.Tipo.COPA], 400.0, 2600.0, true)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.SAMAMBAIA, listas[Vegetacao.Tipo.SAMAMBAIA], 250.0, 700.0, false)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.BANANEIRA, listas[Vegetacao.Tipo.BANANEIRA], 300.0, 1000.0, false)
	Vegetacao.plantar(_etapa_no, Vegetacao.Tipo.PALMEIRA_SELVA, listas[Vegetacao.Tipo.PALMEIRA_SELVA], 400.0, 2000.0, true)
	Vegetacao.colidir(_etapa_no, Vegetacao.Tipo.PALMEIRA_SELVA, listas[Vegetacao.Tipo.PALMEIRA_SELVA])
	Vegetacao.colidir(_etapa_no, Vegetacao.Tipo.COPA, listas[Vegetacao.Tipo.COPA], 0.5)
	Vegetacao.colidir(_etapa_no, Vegetacao.Tipo.BANANEIRA, listas[Vegetacao.Tipo.BANANEIRA])
	_plantar_cipos(cipos)
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SELVA] mata da encosta em %d ms: copa %d, samambaia %d, bananeira %d, palmeira %d, cipó %d" % [Time.get_ticks_msec() - t0,
			listas[Vegetacao.Tipo.COPA].size(), listas[Vegetacao.Tipo.SAMAMBAIA].size(), listas[Vegetacao.Tipo.BANANEIRA].size(),
			listas[Vegetacao.Tipo.PALMEIRA_SELVA].size(), cipos.size()])


## Cortinas de cipó (cada uma com a própria orientação na rampa): MultiMesh por bloco e variação.
func _plantar_cipos(cipos: Array) -> void:
	var variacoes := Vegetacao.malhas(Vegetacao.Tipo.CIPO)
	var mat := Vegetacao.material(Vegetacao.Tipo.CIPO)
	var grupos := {}
	var k := 0
	for c: Array in cipos:
		var t: Transform3D = c[0]
		var chave := Vector3i(floori(t.origin.x / 300.0), k % variacoes.size(), floori(t.origin.z / 300.0))
		k += 1
		if not grupos.has(chave):
			grupos[chave] = []
		grupos[chave].append(c)
	for chave: Vector3i in grupos:
		var itens: Array = grupos[chave]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = variacoes[chave.y]
		mm.instance_count = itens.size()
		for i in itens.size():
			mm.set_instance_transform(i, itens[i][0])
			mm.set_instance_custom_data(i, itens[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 1400.0
		mmi.visibility_range_end_margin = 200.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_etapa_no.add_child(mmi)


## Serpente colossal da etapa (SerpenteCaminho): depende do percurso e do alvo da etapa, por isso é
## montada depois deles (Partida._iniciar_etapa). A mata por onde ela passa some enquanto a etapa durar.
func montar_serpente_caminho(indice: int, sub: ComplexoSubida, alvo: Alvo) -> void:
	_montar_cobras_bote(indice, sub)
	var cfg: Dictionary = _cfg.get("serpente_caminho", {})
	if not (indice + 1) in Array(cfg.get("etapas", [])).map(func(n): return int(n)):
		return
	var cobra := SerpenteCaminho.new()
	_etapa_no.add_child(cobra)
	cobra.montar(sub, alvo, _terreno, cfg)
	_abrir_mata(cobra.roteiro(), cobra.largura * 0.5 + 9.0)


## Cobras que dão o bote (SerpenteBote, pedido do dono 2026-10-05): a da plataforma dos buracos
## (cobra_arena) e a da toca na montanha colada na pista (cobra_toca), nas etapas da config.
func _montar_cobras_bote(indice: int, sub: ComplexoSubida) -> void:
	var na_etapa := func(cfg: Dictionary) -> bool: return (indice + 1) in Array(cfg.get("etapas", [])).map(func(n): return int(n))
	var arena: Dictionary = (_cfg.get("cobra_arena", {}) as Dictionary).duplicate()
	arena.merge(arena.get("por_etapa", {}).get(str(indice + 1), {}), true)   # volta própria de cada etapa
	if na_etapa.call(arena) and sub.plataforma:
		var cobra := SerpenteBote.new()
		_etapa_no.add_child(cobra)
		cobra.montar_arena(sub.plataforma, arena)
	var toca: Dictionary = (_cfg.get("cobra_toca", {}) as Dictionary).duplicate()
	toca.merge(toca.get("por_etapa", {}).get(str(indice + 1), {}), true)   # trecho/metros/lado próprios de cada etapa
	if na_etapa.call(toca):
		var cobra := SerpenteBote.new()
		_etapa_no.add_child(cobra)
		cobra.montar_toca(sub, _terreno, toca)


var _mata: Array = []          # MultiMeshInstance3D da vegetação
var _mata_tirada: Array = []   # [MultiMesh, índice, Transform3D] escondidas pela serpente da etapa


func _abrir_mata(pontos: PackedVector3Array, raio: float) -> void:
	var grade := {}
	for k in range(0, pontos.size(), 3):
		var q := pontos[k]
		grade[Vector2i(floori(q.x / 20.0), floori(q.z / 20.0))] = true
	var zero := Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), Vector3.ZERO)
	for mmi: MultiMeshInstance3D in _mata:
		var mm := mmi.multimesh
		for i in mm.instance_count:
			var xf := mm.get_instance_transform(i)
			var c := Vector2i(floori(xf.origin.x / 20.0), floori(xf.origin.z / 20.0))
			var perto := false
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					perto = perto or grade.has(c + Vector2i(dx, dz))
			if not perto:
				continue
			for k in range(0, pontos.size(), 2):
				var q := pontos[k]
				if Vector2(q.x - xf.origin.x, q.z - xf.origin.z).length_squared() < raio * raio and xf.origin.y < q.y + 4.0:
					_mata_tirada.append([mm, i, xf])
					mm.set_instance_transform(i, zero)
					break


func _restaurar_mata() -> void:
	for t: Array in _mata_tirada:
		(t[0] as MultiMesh).set_instance_transform(t[1], t[2])
	_mata_tirada.clear()


func _physics_process(delta: float) -> void:
	_t += delta
	if _vento_cfg.is_empty():
		return
	var ang := deg_to_rad(float(_vento_cfg.get("direcao", 90)))
	var dir := Vector3(sin(ang), 0.0, -cos(ang))
	var periodo := maxf(float(_vento_cfg.get("periodo", 6.0)), 0.5)
	var rajada := float(_vento_cfg.get("rajada", 0.0)) * (0.5 + 0.5 * sin(_t * TAU / periodo)) * (0.7 + 0.3 * sin(_t * 2.3))
	Veiculo.vento = dir * (float(_vento_cfg.get("forca", 0.0)) + rajada)


func _exit_tree() -> void:
	Veiculo.vento = Vector3.ZERO
