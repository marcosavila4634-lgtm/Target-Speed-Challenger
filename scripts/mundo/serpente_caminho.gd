class_name SerpenteCaminho
extends Node3D
## Serpente colossal da etapa 1 do Serpent's Climb (mapa.subida.selva.serpente_caminho; pedido do dono,
## 2026-10-04). Não ataca. Segue um roteiro realista, sempre apoiada em alguma coisa:
## - rasteja no chão ao lado da estrada; para cruzar, sobe enrolada num pilar (hélice com a barriga no
##   pilar), sai pela beirada, atravessa a pista deitada sobre o asfalto (os carros têm de saltar com o
##   ejetor) e desce pendurada pela beirada do outro lado até o chão; às vezes volta por baixo da ponte,
##   entre dois pilares, para subir de novo do mesmo lado;
## - na largada a cabeça já está em cima da pista, no meio do trecho A, e o corpo atravessa a estrada
##   atrás dela; a velocidade é tal que a cabeça chega ao ninho (o alvo) perto da hora em que os
##   jogadores chegam lá (chegada_s);
## - o ninho é o alvo (mesma lógica de pontos): ela sobe enrolada no pilar do alvo e deita a cabeça na
##   borda; no último minuto da etapa vai se enrolando em volta do ninho, em círculo, e o corpo empilha;
## - o corpo tem colisão (caixas que andam com ela) e quem encosta fica escorregadio com a direção
##   invertida por efeito_s; quem para em cima é levado pelo movimento dela.
## O corpo passa pelo caminho que a cabeça fez (cada osso a uma distância fixa atrás dela no caminho).
## O modelo é o da serpente da largada (SerpenteGigante._malha), com a pele de coral.

var ossos := 420
const SOBRA_ESTRUTURA := 2.4   # da superfície da pista até o fundo das vigas

static var atual: SerpenteCaminho   # a da etapa (bots consultam para saltar)

var largura := 9.5
var altura := 6.0
var _comp := 620.0
var _sub: ComplexoSubida
var _terreno: Terreno
var _alvo: Alvo
var _ctrl: Array = []                    # [Vector3, up] pontos de controle do roteiro
var _pts := PackedVector3Array()          # roteiro amostrado a cada ~1 m
var _ups := PackedVector3Array()
var _s := PackedFloat32Array()
var _total := 0.0
var _s_inicio := 0.0                      # onde a cabeça está na largada
var _s_ninho := 0.0                       # cabeça na borda do ninho
var _s_fim := 0.0                         # fim do enrolar
var _cab := 0.0                           # onde a cabeça está agora
var _vel := 0.0                           # m/s da cabeça (para levar quem está em cima)
var _cfg: Dictionary = {}
var _esq: Skeleton3D
var _corpo: StaticBody3D
var _caixas: Array[CollisionShape3D] = []
var _z := PackedFloat32Array()
var _marcas := {}
var _t := 0.0
var _ach_pista := 0.55
var _achs := PackedFloat32Array()         # achatamento em cada ponto do roteiro


func montar(sub: ComplexoSubida, alvo: Alvo, terreno: Terreno, cfg: Dictionary) -> void:
	name = "SerpenteCaminho"
	_sub = sub
	_alvo = alvo
	_terreno = terreno
	_cfg = cfg
	_ach_pista = float(cfg.get("achatar_pista", 0.55))
	largura = float(cfg.get("largura", 9.5))
	var achatar := float(cfg.get("achatar", 0.8))
	var prova := SerpenteGigante._malha(100.0, largura, 2, achatar)   # só para a altura do corpo
	if prova.is_empty() or sub.pilares.is_empty():
		return
	altura = prova[1]
	_comp = float(cfg.get("comprimento", 0.0))
	_tracar()
	if _pts.size() < 10:
		return
	# comprimento 0: o corpo vai da cabeça (na largada) até o começo do roteiro (pedido do dono: ela ocupa o
	# percurso inteiro desenhado, trecho A e trecho B)
	if _comp <= 0.0:
		_comp = _s_inicio - 4.0
	ossos = clampi(int(_comp / 3.0), 260, 1100)
	var md := SerpenteGigante._malha(_comp, largura, ossos, achatar)
	_esq = Skeleton3D.new()
	add_child(_esq)
	for i in ossos:
		_z.append(_comp * i / (ossos - 1))
		_esq.add_bone("o%d" % i)
		_esq.set_bone_rest(i, Transform3D(Basis.IDENTITY, Vector3(0, 0, _z[i])))
	var mi := MeshInstance3D.new()
	mi.mesh = md[0]
	var caixa := AABB(_pts[0], Vector3.ZERO)
	for q in _pts:
		caixa = caixa.expand(q)
	mi.custom_aabb = caixa.grow(largura * 2.0)
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_esq.add_child(mi)
	mi.skeleton = NodePath("..")
	var orig := (md[0] as ArrayMesh).surface_get_material(0) as BaseMaterial3D
	var pele := ShaderMaterial.new()
	pele.shader = load("res://shaders/serpente_coral.gdshader")
	if orig:
		pele.set_shader_parameter("pele", orig.albedo_texture)
		pele.set_shader_parameter("relevo", orig.normal_texture)
	var cores: Array = cfg.get("cores", [])
	for k in mini(cores.size(), 4):
		pele.set_shader_parameter(["cor_a", "cor_b", "cor_filete", "cor_barriga"][k], Color(float(cores[k][0]), float(cores[k][1]), float(cores[k][2])))
	pele.set_shader_parameter("anel", largura * 2.6)
	pele.set_shader_parameter("escama", largura * 0.09)
	pele.set_shader_parameter("volta", largura * 1.5)
	mi.set_surface_override_material(0, pele)
	var olho := StandardMaterial3D.new()
	olho.albedo_color = Color(1.0, 0.75, 0.1)
	olho.emission_enabled = true
	olho.emission = Color(1.0, 0.6, 0.05)
	olho.emission_energy_multiplier = 1.5
	olho.roughness = 0.1
	mi.set_surface_override_material(1, olho)
	# Colisão: uma caixa a cada 3 ossos, andando com o corpo
	_corpo = StaticBody3D.new()
	_corpo.name = "CorpoSerpente"
	_corpo.collision_layer = 1
	_corpo.collision_mask = 0
	_corpo.add_to_group("serpente")
	add_child(_corpo)
	var passo := _comp / (ossos - 1) * 3.0
	for k in range(0, ossos - 3, 3):
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		var afina := clampf(1.0 - float(k) / ossos * 0.55, 0.45, 1.0) if k > ossos * 0.6 else 1.0   # a cauda afina
		b.size = Vector3(largura * 0.9 * afina, altura * 0.9 * afina, passo + 1.0)
		cs.shape = b
		cs.set_meta("afina", afina)
		_corpo.add_child(cs)
		_caixas.append(cs)
	_ninho()
	_cab = _s_inicio
	_posar()
	atual = self
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[SERPENTE] caminho %.0f m: cabeça começa em %.0f, ninho em %.0f, fim em %.0f; corpo %.0f m x %.1f x %.1f m; marcas %s" % [_total, _s_inicio, _s_ninho, _s_fim, _comp, largura, altura, str(_marcas)])
		for m in _marcas:
			print("[SERPENTE] marca ", m, " s=", snappedf(marca_s(m), 1.0), " em ", ponto(marca_s(m)).snapped(Vector3.ONE * 0.1))
		_auditar.call_deferred()


func _exit_tree() -> void:
	if atual == self:
		atual = null


# ------------------------------------------------------------------ roteiro

func _chao(x: float, z: float) -> float:
	return maxf(_terreno.altura_em(x, z), float(Config.valor("mapa.nivel_agua", 4)) - altura * 0.35)


func _solo(q: Vector3) -> Vector3:
	var folga := 1.2 if _terreno.selva and _terreno.selva.altura(q.x, q.z) > -INF else 0.0   # escadaria das pirâmides: a colisão é uma rampa um pouco acima dos degraus
	return Vector3(q.x, _chao(q.x, q.z) + altura * 0.5 + folga, q.z)


## Ponto do roteiro: posição do meio do corpo, dorso e achatamento (1 = corpo redondo; deitada na pista ela
## fica mais baixa — o peso esparrama o corpo no asfalto — e dá para saltar com o ejetor).
func _por(p: Vector3, up := Vector3.UP, achata := 1.0) -> void:
	_ctrl.append([p, up.normalized(), achata])


func _h(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()


## Chão ao lado da estrada, do índice i0 ao i1 (amostras), `lado` (+1/-1) a `afast` m do eixo.
func _ao_lado(i0: int, i1: int, lado: float, afast: float) -> void:
	var passo := 24 if i1 >= i0 else -24
	var j := i0
	while (passo > 0 and j < i1) or (passo < 0 and j > i1):
		var q := _sub.amostra(j) + _h(_sub.lateral_em(j)) * lado * (afast + 6.0 * sin(j * 0.031))
		_por(_solo(q))
		j += passo


func _pilar_perto(i: int) -> Array:
	var melhor: Array = []
	var d := INF
	for p: Array in _sub.pilares:
		var dd := absf(int(p[2]) - i)
		if dd < d:
			d = dd
			melhor = p
	return melhor


## Vão entre dois pilares mais perto do índice i (para passar por baixo): [índice da amostra, folga].
func _vao_perto(i: int, evita: Array) -> int:
	var melhor := -1
	var d := INF
	for k in _sub.pilares.size() - 1:
		var a: int = _sub.pilares[k][2]
		var b: int = _sub.pilares[k + 1][2]
		if b - a > 40:
			continue
		var m := (a + b) / 2
		var longe := true
		for e: int in evita:
			longe = longe and absf(m - e) > 45
		var pista := _sub.amostra(m)
		var folga := pista.y - SOBRA_ESTRUTURA - _chao(pista.x, pista.z)
		if not longe or folga < altura + 1.2:
			continue
		if absf(m - i) < d:
			d = absf(m - i)
			melhor = m
	return melhor


## Escalada em "S" grande na lateral da ponte (desenho do dono, 2026-10-05: nada de saca-rolha apertado
## no pilar): o corpo serpenteia de um lado para o outro ao longo da ponte, encostado na face dos pilares,
## com as curvas largas de uma cobra de verdade subindo. `base` = ponto da pista em cima; `L` aponta para
## fora (do lado `s`); de `y_baixo` a `y_cima`; `subindo` = do chão para cima (senão, de cima para baixo).
func _s_vertical(base: Vector3, L: Vector3, T: Vector3, meia_pilar: float, y_baixo: float, y_cima: float, subindo: bool) -> void:
	var amp := 13.0                                   # meia largura do S ao longo da ponte
	var meia_onda := clampf(largura * 1.7, 13.0, 18.0)   # altura de cada curva
	var n := maxi(int(round((y_cima - y_baixo) / meia_onda)), 1)
	var rente := meia_pilar + altura * 0.5 + 0.4       # dorso para fora, barriga na face do pilar
	var pts: Array = []
	for k in n * 4 + 1:
		var f := float(k) / (n * 4)
		var y := lerpf(y_baixo, y_cima, f)
		var lado := sin(f * n * PI) * amp                 # vai de um lado ao outro a cada meia onda
		var cola := 1.0 - absf(cos(f * n * PI))           # nas pontas do S o corpo encosta mais na ponte
		pts.append([base + T * lado + L * lerpf(rente + 2.5, rente, cola) + Vector3.UP * (y - base.y), L])
	if not subindo:
		pts.reverse()
	for q: Array in pts:
		_por(q[0], q[1])


## Uma travessia: sobe em S pela lateral do lado `s`, atravessa a pista deitada e desce em S do outro
## lado, `a` m adiante. Devolve o índice da amostra onde ela desceu.
func _travessia(pil: Array, s: float, marca: String) -> int:
	var P: Vector3 = pil[0]
	var meia: float = pil[1]
	var ip: int = pil[2]
	var L := _h(_sub.lateral_em(ip))
	var T := _h(_sub.tangente_em(ip))
	var pista := _sub.amostra(ip).y
	var meia_pista := _sub.largura_em(ip) * 0.5 + 0.3
	var fora := meia_pista + altura * 0.5 + 0.5
	var base := Vector3(P.x, pista, P.z)
	var chao := _chao(P.x + L.x * s * fora, P.z + L.z * s * fora)
	var y_baixo := chao + altura * 0.5 + 6.0
	var y_cima := pista - SOBRA_ESTRUTURA - largura * 0.5 - 1.0   # subindo de lado o corpo fica de pé (a largura na vertical): o S termina abaixo da estrada
	# Chega pelo chão e começa a subir em S (barriga na ponte, dorso para fora)
	_por(_solo(base + L * s * (fora + 12.0)))
	if y_cima - y_baixo > 6.0:
		_s_vertical(base, L * s, T, maxf(fora - altura * 0.5 - 0.4, meia), y_baixo, y_cima, true)
	# Passa pela beirada e deita na pista (barriga no asfalto)
	_por(base + L * s * fora + Vector3.UP * 0.2, L * s)
	_por(base + L * s * (meia_pista + 0.8) + Vector3.UP * (altura * _ach_pista * 0.5 + 0.3), (Vector3.UP + L * s).normalized(), _ach_pista)
	var a := 2   # atravessa reto (perpendicular): na diagonal o corpo ocupava ~30 m da pista e não dava para saltar
	var marcou := false
	for k in 6:
		var f := k / 5.0
		var j := ip + int(round(a * f))
		var q := _sub.amostra(j) + _h(_sub.lateral_em(j)) * s * lerpf(meia_pista - 2.5, -(meia_pista - 2.5), f)
		q.y = _sub.amostra(j).y + altura * _ach_pista * 0.5 + 0.05
		_por(q, Vector3.UP, _ach_pista)
		if k == 2 and not marcou:
			_marcas[marca] = _ctrl.size() - 1
			marcou = true
	# Desce do outro lado em S e deita no chão
	var ja := ip + a
	var Pa := _sub.amostra(ja)
	var La := _h(_sub.lateral_em(ja))
	var Ta := _h(_sub.tangente_em(ja))
	var meia_a := _sub.largura_em(ja) * 0.5 + 0.3
	var fora_a := meia_a + altura * 0.5 + 0.5
	_por(Pa + Vector3.UP * (altura * _ach_pista * 0.5 + 0.3) + La * -s * (meia_a + 0.8), (Vector3.UP - La * s).normalized(), _ach_pista)
	_por(Pa + Vector3.UP * 0.2 + La * -s * fora_a, -La * s)
	var chao_a := _chao(Pa.x - La.x * s * fora_a, Pa.z - La.z * s * fora_a)
	var yb := chao_a + altura * 0.5 + 6.0
	var yc := Pa.y - SOBRA_ESTRUTURA - largura * 0.5 - 1.0
	if yc - yb > 6.0:
		var pil_a := _pilar_perto(ja)
		_s_vertical(Pa, -La * s, Ta, maxf(fora_a - altura * 0.5 - 0.4, float(pil_a[1]) if not pil_a.is_empty() else 2.0), yb, yc, false)
	_por(_solo(Pa + La * -s * (fora_a + 12.0)))
	return ja


## Passa por baixo da ponte no vão `im`, de `de` para o outro lado.
func _por_baixo(im: int, de: float) -> void:
	var q := _sub.amostra(im)
	var L := _h(_sub.lateral_em(im))
	var meia := _sub.largura_em(im) * 0.5
	for f: float in [meia + 16.0, meia + 4.0, 0.0, -(meia + 4.0), -(meia + 16.0)]:
		_por(_solo(q + L * de * f))


func _tracar() -> void:
	_ctrl.clear()
	var trav: Array = _cfg.get("travessias", [])
	var afast := float(_cfg.get("lado_solo", 26.0))
	var ninho := _alvo.centro_base
	var pils: Array = []
	for t in trav:
		var i := _sub.indice_trecho(str(t[0]), float(t[1]))
		pils.append(_pilar_perto(i))
	# Lados: 0 = sai do lado do ninho
	var lados: Array = []
	for k in trav.size():
		var s := float(trav[k][2])
		if s == 0.0:
			var P: Vector3 = pils[k][0]
			s = -signf(_h(_sub.lateral_em(int(pils[k][2]))).dot(ninho - P))
		lados.append(s)
	# Começo: no chão, do lado da primeira subida, bem antes dela (a cauda)
	var i_primeiro: int = pils[0][2]
	_ao_lado(maxi(i_primeiro - 700, _sub.inicio_trecho_de(i_primeiro) + 90), i_primeiro - 30, lados[0], afast)   # longe do cercado da largada
	var desceu := -1
	var usados: Array = []
	for p in pils:
		usados.append(int(p[2]))
	for k in trav.size():
		var s: float = lados[k]
		var ip: int = pils[k][2]
		if desceu >= 0 and _sub.trecho_de(ip) != _sub.trecho_de(desceu):
			# Mudou de trecho (A → B): a plataforma fica no topo da pirâmide; contorna pelo chão e segue ao
			# lado da estrada nova a partir de onde ela sai da pirâmide
			for q in _cfg.get("contorno", []):
				_por(_solo(Vector3(float(q[0]), 0, float(q[1]))))
			var ultimo_c: Vector3 = _ctrl[_ctrl.size() - 1][0]
			var i_b := _sub.indice_trecho(_sub.nome_trecho(_sub.trecho_de(ip)), float(_cfg.get("inicio_b", 140.0)))
			var lado_b := signf(_h(_sub.lateral_em(i_b)).dot(ultimo_c - _sub.amostra(i_b)))
			if lado_b != s:
				var im := _vao_perto((i_b + ip) / 2, usados)
				if im > 0:
					_ao_lado(i_b, im - 12, lado_b, afast)
					_por_baixo(im, lado_b)
					_ao_lado(im + 12, ip - 30, s, afast)
			else:
				_ao_lado(i_b, ip - 30, s, afast)
		elif desceu >= 0:
			var lado_agora: float = -lados[k - 1]
			if lado_agora != s:
				# Mesmo lado de subida: volta por baixo da ponte entre dois pilares
				var im := _vao_perto((desceu + ip) / 2, usados)
				if im > 0:
					_ao_lado(desceu + 20, im - 12, lado_agora, afast)
					_por_baixo(im, lado_agora)
					_ao_lado(im + 12, ip - 30, s, afast)
				else:
					push_warning("SerpenteCaminho: sem vão para passar por baixo antes da travessia %d" % k)
			else:
				_ao_lado(desceu + 20, ip - 30, s, afast)
		desceu = _travessia(pils[k], s, "travessia%d" % k)
	# Para o ninho: pelo chão, pelos pontos do roteiro, e sobe a escadaria norte da pirâmide do alvo
	var ultimo: Vector3 = (_ctrl[_ctrl.size() - 1][0] as Vector3)
	var saida := ultimo + _h(ninho - ultimo) * 30.0
	_por(_solo(saida))
	for q in _cfg.get("rota_ninho", []):
		_por(_solo(Vector3(float(q[0]), 0, float(q[1]))))
	_subir_ninho()
	_amostrar()
	# Cabeça na largada: em cima da pista, na travessia escolhida
	var k0 := int(_cfg.get("cabeca_inicio", trav.size() - 1))
	_s_inicio = _s_de_ctrl(int(_marcas.get("travessia%d" % k0, 0)))
	_s_ninho = _s_de_ctrl(int(_marcas.get("ninho", _ctrl.size() - 1)))
	_s_fim = _total - 1.0
	# A cauda precisa caber atrás da cabeça: estica o começo para trás, no chão
	if _s_inicio < _comp + 2.0:
		var falta := _comp + 6.0 - _s_inicio
		var p0: Vector3 = _ctrl[0][0]
		var p1: Vector3 = _ctrl[1][0]
		var para_tras := _h(p0 - p1)
		var novos: Array = []
		var n := int(ceil(falta / 20.0))
		for k in range(n, 0, -1):
			novos.append([_solo(p0 + para_tras * 20.0 * k), Vector3.UP])
		_ctrl = novos + _ctrl
		for m in _marcas:
			_marcas[m] = int(_marcas[m]) + novos.size()
		_amostrar()
		_s_inicio = _s_de_ctrl(int(_marcas.get("travessia%d" % k0, 0)))
		_s_ninho = _s_de_ctrl(int(_marcas.get("ninho", _ctrl.size() - 1)))
		_s_fim = _total - 1.0


## Da escadaria norte ao topo da pirâmide do alvo, sobe enrolada no pilar dele, passa pela borda do disco,
## deita a cabeça no ninho; depois o roteiro segue em círculo em volta do ninho (o enrolar do fim).
func _subir_ninho() -> void:
	var C := _alvo.centro_base
	var Rd := _alvo.raio + Alvo.BORDA
	var chao := _chao(C.x, C.z)
	_por(_solo(Vector3(C.x, 0, C.z - 130.0)))
	_por(_solo(Vector3(C.x, 0, C.z - 95.0)))
	for f: float in [0.0, 0.33, 0.66, 1.0]:
		_por(_solo(Vector3(C.x, 0, lerpf(C.z - 80.0, C.z - 26.0, f))))
	var R := 8.4 + altura * 0.5 + 0.6        # as sapatas do pilar do alvo têm ~8,2 m de meia largura
	var y0 := chao + 4.9 + largura * 0.5 + 0.4
	var y1 := C.y - Alvo.ESPESSURA - largura * 0.5 - 0.6
	var te := -PI * 0.5                       # sai do lado norte, de onde veio
	if y1 - y0 > 1.0:
		var voltas := floorf((y1 - y0) / (largura + 2.5))
		var giro := TAU * voltas + 1.2
		var t0 := te - giro
		var n := maxi(int(giro / deg_to_rad(15.0)), 4)
		var dir := func(t: float) -> Vector3: return Vector3(cos(t), 0.0, sin(t))
		_por(Vector3(C.x, chao + altura * 0.5, C.z) + dir.call(t0) * (R + 5.0))
		for k in n + 1:
			var f := float(k) / n
			var t := t0 + giro * f
			_por(Vector3(C.x, lerpf(y0, y1, f), C.z) + dir.call(t) * R, dir.call(t))
	else:
		y1 = chao + largura * 0.5
	var norte := Vector3(0, 0, -1)
	var fora := Rd + altura * 0.5 + 0.6
	_por(Vector3(C.x, y1, C.z) + norte * fora, norte)
	_por(Vector3(C.x, C.y + 0.4, C.z) + norte * fora, norte)
	_por(Vector3(C.x, C.y + altura * 0.5 + 1.0, C.z) + norte * (Rd + 0.6), (Vector3.UP + norte).normalized())
	# Cabeça no ninho: deitada na borda, já virando para dar a volta
	var Rc := Rd + largura * 0.5 + 0.6   # em volta do disco, por cima da borda do ninho: o alvo fica livre
	var y_d := C.y + altura * 0.5 + 0.05
	var ang0 := -PI * 0.5
	for k in 4:
		var t := ang0 + 0.12 * (k + 1)
		_por(Vector3(C.x + cos(t) * Rc, y_d, C.z + sin(t) * Rc))
	_marcas["ninho"] = _ctrl.size() - 1
	# Chegou: não para (pedido do dono, 2026-10-05) — já sai circulando. Dá meia volta no ninho, desce para a
	# pirâmide e a rodeia inteira em espiral (desce até perto da base e volta subindo), e no fim se enrola no
	# ninho. O corpo, que vem atrás, vai cobrindo a pirâmide.
	var t := ang0 + 0.48
	for k in range(1, 13):
		t = ang0 + 0.48 + PI * float(k) / 12.0
		_por(Vector3(C.x + cos(t) * Rc, y_d, C.z + sin(t) * Rc))
	var pir := _piramide_perto(C)
	if not pir.is_empty():
		var cp: Vector2 = pir.c
		var mb: float = pir.mb
		var mt: float = pir.mt
		var voltas := float(_cfg.get("voltas_piramide", 2.5))
		var n := int(voltas * 36.0)
		for k in range(0, n + 1):
			var fk := float(k) / n
			var a := t + TAU * voltas * fk
			var d := lerpf(Rc + 4.0, mb - largura * 0.5 - 2.0, sin(fk * PI))   # desce em espiral e volta subindo
			d = maxf(d, mt + largura * 0.5)
			var cx := signf(cos(a)) * pow(absf(cos(a)), 0.6)
			var cz := signf(sin(a)) * pow(absf(sin(a)), 0.6)
			_por(_solo(Vector3(cp.x + cx * d, 0.0, cp.y + cz * d)))
		t += TAU * voltas
	# Enrolar no ninho: voltas em volta do disco; depois de uma volta o corpo sobe por cima de si mesmo
	var voltas_fim := float(_cfg.get("voltas", 1.6))
	var nf := int(voltas_fim * 24.0)
	for k in range(0, nf + 1):
		var tk := t + TAU * voltas_fim * float(k) / nf
		var subida := smoothstep(TAU - 0.9, TAU + 0.1, tk - t) * altura * 0.95
		_por(Vector3(C.x + cos(tk) * Rc, y_d + subida, C.z + sin(tk) * Rc))


## Pirâmide (Selva) onde fica o alvo: {c, mb, mt, topo...} ou vazio.
func _piramide_perto(C: Vector3) -> Dictionary:
	if _terreno.selva == null:
		return {}
	for p: Dictionary in _terreno.selva._piramides:
		var c: Vector2 = p.c
		if Vector2(C.x, C.z).distance_to(c) < float(p.mb):
			return p
	return {}


func _s_de_ctrl(k: int) -> float:
	# Os pontos de controle ficam no roteiro amostrado: o mais perto dele
	var p: Vector3 = _ctrl[clampi(k, 0, _ctrl.size() - 1)][0]
	var melhor := 0
	var d := INF
	for i in _pts.size():
		var dd := _pts[i].distance_squared_to(p)
		if dd < d:
			d = dd
			melhor = i
	return _s[melhor]


## Curva de Hermite pelos pontos de controle (tangentes pesadas pelo tamanho dos trechos: não passa do
## ponto quando sai de uma subida longa para a pista — era isso que fazia a corcova em cima do asfalto),
## um ponto a cada ~1 m, com o "para cima" (dorso) interpolado.
func _amostrar() -> void:
	_pts.clear()
	_ups.clear()
	_s.clear()
	_achs.clear()
	var n := _ctrl.size()
	for i in n - 1:
		var p0: Vector3 = _ctrl[maxi(i - 1, 0)][0]
		var p1: Vector3 = _ctrl[i][0]
		var p2: Vector3 = _ctrl[i + 1][0]
		var p3: Vector3 = _ctrl[mini(i + 2, n - 1)][0]
		var u1: Vector3 = _ctrl[i][1]
		var u2: Vector3 = _ctrl[i + 1][1]
		var d01 := maxf(p0.distance_to(p1), 0.01)
		var d12 := maxf(p1.distance_to(p2), 0.01)
		var d23 := maxf(p2.distance_to(p3), 0.01)
		var m1 := (p2 - p0) * (d12 / (d01 + d12)) if i > 0 else p2 - p1
		var m2 := (p3 - p1) * (d12 / (d12 + d23)) if i + 2 < n else p2 - p1
		var m := maxi(int(ceil(d12)), 1)
		for k in m:
			var t := float(k) / m
			var t2 := t * t
			var t3 := t2 * t
			var q := (2.0 * t3 - 3.0 * t2 + 1.0) * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2
			_pts.append(q)
			_ups.append(u1.lerp(u2, t).normalized())
			_achs.append(lerpf(float(_ctrl[i][2]), float(_ctrl[i + 1][2]), smoothstep(0.0, 1.0, t)))
	_pts.append(_ctrl[n - 1][0])
	_ups.append(_ctrl[n - 1][1])
	_achs.append(float(_ctrl[n - 1][2]))
	# Dorso perpendicular ao corpo e sem saltos: projeta o "para cima" pedido no plano do corpo e o puxa
	# devagar a partir do anterior (onde o corpo fica de pé, subindo a ponte, o pedido some e vale o anterior)
	var ant := Vector3.UP
	for i in _pts.size():
		var tg := (_pts[mini(i + 1, _pts.size() - 1)] - _pts[maxi(i - 1, 0)]).normalized()
		var quer := _ups[i] - tg * _ups[i].dot(tg)
		var leva := ant - tg * ant.dot(tg)
		if leva.length_squared() < 1e-4:
			leva = quer
		var u := leva.normalized().lerp(quer.normalized() if quer.length_squared() > 1e-4 else leva.normalized(), 0.18)
		u = (u - tg * u.dot(tg)).normalized()
		_ups[i] = u
		ant = u
	_s.resize(_pts.size())
	_s[0] = 0.0
	for i in range(1, _pts.size()):
		_s[i] = _s[i - 1] + _pts[i].distance_to(_pts[i - 1])
	_total = _s[_s.size() - 1]


func _no_roteiro(s: float) -> Array:
	s = clampf(s, 0.0, _total)
	var a := 0
	var b := _s.size() - 1
	while b - a > 1:
		var meio := (a + b) >> 1
		if _s[meio] <= s:
			a = meio
		else:
			b = meio
	var f := (s - _s[a]) / maxf(_s[b] - _s[a], 0.001)
	return [_pts[a].lerp(_pts[b], f), _ups[a].lerp(_ups[b], f).normalized(), lerpf(_achs[a], _achs[b], f)]


# ------------------------------------------------------------------ movimento

func _relogio() -> Array:
	var cena := get_tree().current_scene
	if cena == null or not ("tempo_restante" in cena):
		return [0.0, INF]
	var total := float(cena.get("_tempo_total_etapa"))
	var resta := float(cena.get("tempo_restante"))
	if total <= 1.0:
		return [0.0, INF]
	return [maxf(total - resta, 0.0), resta]


func _physics_process(delta: float) -> void:
	if _esq == null:
		return
	_t += delta
	var r := _relogio()
	var corrido: float = r[0]
	var resta: float = r[1]
	# Até o ninho em chegada_s; dali segue sem parar, rodeando a pirâmide, e termina enrolada no ninho perto
	# do fim do tempo
	var chegada := maxf(float(_cfg.get("chegada_s", 190.0)), 1.0)
	var alvo_s := _s_inicio + (_s_ninho - _s_inicio) * clampf(corrido / chegada, 0.0, 1.0)
	if corrido > chegada and resta < INF:
		var resto := maxf(corrido + resta - chegada - 3.0, 1.0)
		alvo_s = _s_ninho + (_s_fim - _s_ninho) * clampf((corrido - chegada) / resto, 0.0, 1.0)
	if OS.get_environment("TSC_SERPENTE_S") != "":
		alvo_s = float(OS.get_environment("TSC_SERPENTE_S"))   # conferência: cabeça num ponto fixo do roteiro
	_vel = (alvo_s - _cab) / maxf(delta, 0.001)
	_cab = alvo_s
	_posar()
	_carros(delta)


func _posar() -> void:
	var pos := PackedVector3Array()
	pos.resize(ossos)
	var ups := PackedVector3Array()
	ups.resize(ossos)
	var achs := PackedFloat32Array()
	achs.resize(ossos)
	for i in ossos:
		var r := _no_roteiro(_cab - _z[i])
		pos[i] = r[0]
		ups[i] = r[1]
		achs[i] = lerpf(1.0, r[2], clampf((_z[i] - largura * 1.2) / (largura * 2.0), 0.0, 1.0))   # a cabeça não achata
	var ant := ups[0]
	var bases: Array[Basis] = []
	bases.resize(ossos)
	for i in ossos:
		var frente := pos[maxi(i - 1, 0)] - pos[mini(i + 1, ossos - 1)]
		if frente.length_squared() < 1e-6:
			frente = -ant.cross(Vector3.RIGHT) if i == 0 else -bases[i - 1].z
		frente = frente.normalized()
		var up := ups[i] - frente * ups[i].dot(frente)
		if up.length_squared() < 0.04:
			up = ant - frente * ant.dot(frente)   # corpo na direção do dorso: mantém o do osso anterior
		up = up.normalized()
		ant = up
		var bs := Basis(up.cross(-frente).normalized(), up, -frente)   # = looking_at(frente, up), sem a exceção dos paralelos
		bases[i] = bs
		# O osso fica na BARRIGA do modelo (y = 0 da malha): desce meia altura no sentido do dorso. Deitada
		# na pista o corpo achata (achs).
		_esq.set_bone_pose(i, Transform3D(bs.scaled_local(Vector3(1.0, achs[i], 1.0)), pos[i] - bs.y * altura * achs[i] * 0.5))
	for k in _caixas.size():
		var i := mini(k * 3 + 1, ossos - 1)
		_caixas[k].transform = Transform3D(bases[i], pos[i])
		var b := _caixas[k].shape as BoxShape3D
		var alto := altura * 0.9 * achs[i] * float(_caixas[k].get_meta("afina", 1.0))
		if absf(b.size.y - alto) > 0.05:
			b.size.y = alto


## Quem encosta: escorregadio e direção invertida; quem está em cima vai junto com o corpo.
func _carros(delta: float) -> void:
	var efeito := float(_cfg.get("efeito_s", 3.0))
	for no_v in get_tree().get_nodes_in_group("veiculo"):
		var v := no_v as Veiculo
		if v == null or v.eliminado or v.fantasma():
			continue
		var p := v.global_position
		for cs in _caixas:
			if cs.transform.origin.distance_squared_to(p) > 900.0:
				continue
			var meio: Vector3 = (cs.shape as BoxShape3D).size * 0.5
			var l := cs.transform.affine_inverse() * p
			if absf(l.x) < meio.x + 2.3 and absf(l.y) < meio.y + 1.6 and absf(l.z) < meio.z + 2.3:
				if not v.com_ovo() and OS.get_environment("TSC_SUB_LOG") != "":
					print("[SERPENTE] encostou: ", v.nome_piloto, " em ", p.snapped(Vector3.ONE * 0.1), " t=", snappedf(_t, 0.1), " local=", l.snapped(Vector3.ONE * 0.1), " caixa=", (cs.shape as BoxShape3D).size.snapped(Vector3.ONE * 0.1), " centro=", cs.transform.origin.snapped(Vector3.ONE * 0.1))
				v.escorregar(efeito)
				if l.y > 0.0 and absf(_vel) > 0.05:
					# Em cima dela: o corpo arrasta o carro no sentido em que ela anda
					var frente := -cs.transform.basis.z.normalized()
					var leva := Vector3(frente.x, 0.0, frente.z) * _vel
					var lv := v.linear_velocity
					var hz := Vector3(lv.x, 0.0, lv.z)
					hz = hz.lerp(hz + (leva - hz.project(leva.normalized() if leva.length() > 0.01 else Vector3.FORWARD)), clampf(delta * 3.0, 0.0, 1.0))
					v.linear_velocity = Vector3(hz.x, lv.y, hz.z)
				break


## Distância à frente (no rumo `dir`) até o corpo deitado na pista, ou INF (bots saltam com o ejetor).
func corpo_na_pista_adiante(p: Vector3, dir: Vector3, alcance: float) -> float:
	var melhor := INF
	for cs in _caixas:
		var c := cs.transform.origin - p
		var ao_longo := c.dot(dir)
		if ao_longo < -2.0 or ao_longo > alcance:
			continue
		var lado := (c - dir * ao_longo)
		if Vector2(lado.x, lado.z).length() < 7.0 and c.y > -1.5 and c.y < altura + 1.0:
			melhor = minf(melhor, ao_longo)
	return melhor


## Ponto da cabeça e o rumo (vistas de conferência).
func cabeca() -> Array:
	var a: Array = _no_roteiro(_cab)
	var b: Array = _no_roteiro(_cab - 3.0)
	return [a[0], ((a[0] as Vector3) - (b[0] as Vector3)).normalized()]


func ponto(s: float) -> Vector3:
	return _no_roteiro(s)[0]


func marca_s(nome: String) -> float:
	return _s_de_ctrl(int(_marcas.get(nome, 0)))


## Roteiro inteiro (para abrir a mata por onde ela passa).
func roteiro() -> PackedVector3Array:
	return _pts


# ------------------------------------------------------------------ ninho

## Ninho em volta do disco do alvo: borda de galhos trançados e folhas, com ovos nela.
func _ninho() -> void:
	var C := _alvo.centro_base
	var Rd := _alvo.raio + Alvo.BORDA
	var rng := RandomNumberGenerator.new()
	rng.seed = 818
	var galho := CylinderMesh.new()
	galho.top_radius = 0.18
	galho.bottom_radius = 0.26
	galho.height = 1.0
	galho.radial_segments = 6
	galho.rings = 1
	var galhos: Array[Transform3D] = []
	for k in 900:
		var t := rng.randf() * TAU
		var r := Rd + rng.randf_range(-0.6, 3.2)
		var y := C.y + rng.randf_range(-1.6, 0.9) - maxf(r - Rd - 1.5, 0.0) * 0.5
		var tan := Vector3(-sin(t), rng.randf_range(-0.35, 0.35), cos(t)).normalized()
		var b := Basis.looking_at(tan, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
		galhos.append(Transform3D(b.scaled(Vector3(1.0, rng.randf_range(4.0, 9.0), 1.0)), Vector3(C.x + cos(t) * r, y, C.z + sin(t) * r)))
	var madeira := StandardMaterial3D.new()
	madeira.albedo_color = Color(0.3, 0.2, 0.11)
	madeira.roughness = 0.95
	_instancias(galho, galhos, madeira)
	var ovo := SphereMesh.new()
	ovo.radius = 1.0
	ovo.height = 2.0
	var casca := StandardMaterial3D.new()
	casca.albedo_color = Color(0.92, 0.88, 0.76)
	casca.roughness = 0.6
	var ovos: Array[Transform3D] = []
	for k in 6:
		var t := -PI * 0.5 + 1.1 + k * 0.85   # longe de onde ela sobe (lado norte)
		var r := Rd + 1.6
		ovos.append(Transform3D(Basis(Vector3(cos(t), 0, sin(t)), rng.randf_range(-0.4, 0.4)).scaled(Vector3(1.3, 1.9, 1.3)), Vector3(C.x + cos(t) * r, C.y + 1.0, C.z + sin(t) * r)))
	_instancias(ovo, ovos, casca)


func _instancias(malha: Mesh, xf: Array[Transform3D], mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = malha
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


# ------------------------------------------------------------------ conferência

## TSC_SUB_LOG: o corpo, passado pelo roteiro inteiro, encosta em alguma estrutura? (o dono não quer a
## cobra atravessando pilar, viga ou pista)
func _auditar() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var espaco := get_world_3d().direct_space_state
	var forma := BoxShape3D.new()
	forma.size = Vector3(largura * 0.8, altura * 0.8, 1.5)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = forma
	q.collision_mask = 1
	q.exclude = [_corpo.get_rid()]
	var batidas := {}
	var i := 2
	while i < _pts.size() - 2:
		var frente := (_pts[i + 1] - _pts[i - 1]).normalized()
		var up := _ups[i]
		if absf(frente.dot(up)) > 0.97:
			up = Vector3.BACK if absf(frente.y) > 0.9 else Vector3.UP
		q.transform = Transform3D(Basis.looking_at(frente, up), _pts[i])
		for h in espaco.intersect_shape(q, 4):
			var nome := str((h.collider as Node).get_path()) if h.collider is Node else "?"
			if not batidas.has(nome):
				batidas[nome] = []
			if (batidas[nome] as Array).size() < 4:
				batidas[nome].append([int(_s[i]), _pts[i].snapped(Vector3.ONE * 0.1)])
		i += 2
	print("[SERPENTE] auditoria: ", batidas if not batidas.is_empty() else "nada encostado")
