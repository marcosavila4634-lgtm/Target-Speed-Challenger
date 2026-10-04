class_name TunelVulcao
extends Node3D
## Túnel por dentro do vulcão (Extinction Day, percursos.N.tuneis: [trecho, m0, m1, câmaras]): a
## estrada da etapa corre suspensa sobre um rio de lava, dentro de um tubo de basalto em arco que
## acompanha as curvas dela, com câmaras de magma mais largas. O terreno é cortado ao longo da estrada
## (Dino.relevo); aqui ficam o tubo, a lava, as luzes, as bocas e a capa de rocha que refaz a encosta
## natural por cima da vala.
## As bocas ficam onde a encosta natural passa 3 m acima do arco (o intervalo do json é o máximo).
## Câmaras: [m inicial, m final, meia-largura, altura do arco] em metros do trecho.

const PASSO := 1.5
const MEIA_CAPA := 62.0

var meia_base := 9.0       # meia-largura interna
var topo_base := 13.0      # alto do arco acima da estrada
var piso := -6.0           # fundo do tubo (abaixo da estrada)
var lava_y := -4.6         # superfície do rio de lava (abaixo da estrada)
var ombro := 4.0           # onde a parede reta vira abóbada (acima da estrada)

var _terreno: Terreno
var _p := PackedVector3Array()     # centro da estrada em cada estação
var _t := PackedVector3Array()     # tangente horizontal
var _l := PackedVector3Array()     # lateral (direita)
var _s := PackedFloat32Array()     # metros desde o começo do trecho
var _meia := PackedFloat32Array()
var _topo := PackedFloat32Array()
var _nat := PackedFloat32Array()   # encosta natural (sem o corte) no eixo
var i_ini := -1                    # boca de entrada e de saída (estações)
var i_fim := -1
var trecho := ""
## Pontos [posição, lateral, tangente] para câmeras de conferência
var bocas: Array = []
## Nichos na parede (aberturas: [m, lado (0 = os dois), meia-largura ao longo, altura, fundo]): de onde
## saem os raptores e o T-Rex. Fundo 0 = a armadilha monta o covil dela.
var _aberturas: Array = []


func montar(_dino: Dino, terreno: Terreno, pc: Dictionary, item: Array, cfg: Dictionary) -> void:
	_terreno = terreno
	trecho = str(item[0])
	var m0 := float(item[1])
	var m1 := float(item[2])
	var camaras: Array = item[3] if item.size() > 3 else []
	_aberturas = item[4] if item.size() > 4 else []
	meia_base = float(cfg.get("meia_largura", 9.0))
	topo_base = float(cfg.get("altura", 13.0))
	var ctrl := PackedVector3Array()
	for q in (pc.get("trechos", {}) as Dictionary).get(trecho, []):
		ctrl.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	if ctrl.size() < 2:
		return
	var amostras := ComplexoSubida._amostrar_curva(ctrl)
	var n := amostras.size()
	var s_amostra := PackedFloat32Array()
	s_amostra.resize(n)
	for i in range(1, n):
		s_amostra[i] = s_amostra[i - 1] + amostras[i].distance_to(amostras[i - 1])
	var total := s_amostra[n - 1]
	# Trecho B que entra no túnel até o fim: o tubo continua reto pelo vão do salto até o trecho C
	var vao := 0.0
	if trecho == "B" and m1 >= total - 2.0:
		vao = 32.0
	# Estações: um pouco antes e depois do intervalo (a capa passa das bocas até o terreno natural)
	var s0 := maxf(m0 - 160.0, 0.0)
	var s1 := minf(m1 + 160.0, total) + vao
	var j := 0
	var s := s0
	while s <= s1:
		var p: Vector3
		var tg: Vector3
		if s <= total:
			while j < n - 2 and s_amostra[j + 1] < s:
				j += 1
			var f := clampf((s - s_amostra[j]) / maxf(s_amostra[j + 1] - s_amostra[j], 0.001), 0.0, 1.0)
			p = amostras[j].lerp(amostras[j + 1], f)
			tg = amostras[j + 1] - amostras[j]
		else:
			tg = amostras[n - 1] - amostras[n - 2]
			var th := Vector3(tg.x, 0.0, tg.z).normalized()
			p = amostras[n - 1] + th * (s - total) + Vector3.DOWN * (s - total) * 0.04
		var th2 := Vector3(tg.x, 0.0, tg.z).normalized()
		_p.append(p)
		_t.append(th2)
		_l.append(th2.cross(Vector3.UP).normalized())
		_s.append(s)
		var meia := meia_base
		var topo := topo_base
		for c in camaras:
			var w := smoothstep(float(c[0]) - 30.0, float(c[0]), s) * (1.0 - smoothstep(float(c[1]), float(c[1]) + 30.0, s))
			meia = lerpf(meia, float(c[2]), w)
			topo = lerpf(topo, float(c[3]), w)
		_meia.append(meia)
		_topo.append(topo)
		_nat.append(terreno.altura_sem_estrada_malha(p.x, p.z))
		s += PASSO
	var ns := _p.size()
	# Bocas: rocha natural 3 m acima do arco
	for i in ns:
		if _s[i] >= m0 and _s[i] <= m1 + vao and _nat[i] >= _p[i].y + _topo[i] + 3.0:
			if i_ini < 0:
				i_ini = i
			i_fim = i
	if i_ini < 0 or i_fim - i_ini < 20:
		return
	# Do vão em diante quem faz a boca de saída é o túnel do trecho C (este só vai até o fim do vão)
	if vao > 0.0:
		i_fim = ns - 1
	if OS.get_environment("TSC_SUB_LOG") != "":
		print("[TUNEL] %s bocas em %.0f e %.0f m (%s → %s), comprimento %.0f m" % [trecho, _s[i_ini], _s[i_fim], str(_p[i_ini].snapped(Vector3.ONE)), str(_p[i_fim].snapped(Vector3.ONE)), _s[i_fim] - _s[i_ini]])
	var mat_rocha := ShaderMaterial.new()
	mat_rocha.shader = load("res://shaders/rocha_vulcao.gdshader")
	mat_rocha.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 331))
	mat_rocha.set_shader_parameter("ruido_fino", Terreno._textura_ruido(0.08, 4, 337))
	var mortal := StaticBody3D.new()
	mortal.collision_layer = 1
	mortal.collision_mask = 0
	mortal.add_to_group("estrutura")
	mortal.add_to_group("mortal")
	add_child(mortal)
	add_to_group("tunel_vulcao")
	_montar_tubo(mat_rocha, mortal)
	# (sem cascatas de lava nas paredes: o dono mandou tirar as colunas luminosas de dentro do vulcão)
	_montar_lava()
	_montar_capa(terreno, mortal, vao > 0.0)
	var boca_ini := trecho != "C" or float(item[1]) > 2.0
	if boca_ini:
		_montar_boca(i_ini, -1.0, mortal, "ZONA VULCÂNICA")
	if vao <= 0.0:
		_montar_boca(i_fim, 1.0, mortal, "SAÍDA")


## Ponto da seção: x lateral, y acima da estrada. u de 0 (parede direita, no piso) a 1 (esquerda).
func _contorno(i: int) -> Array:
	var meia: float = _meia[i]
	var topo: float = _topo[i]
	var alt_arco := topo - ombro
	var pts := []
	for k in 4:
		pts.append([Vector2(meia, lerpf(piso, ombro, k / 4.0)), Vector2.RIGHT])
	for k in 25:
		var u := k / 24.0
		var p := Vector2(meia * cos(PI * u), ombro + alt_arco * sin(PI * u))
		pts.append([p, Vector2(p.x / meia, (p.y - ombro) / alt_arco).normalized()])
	for k in range(1, 5):
		pts.append([Vector2(-meia, lerpf(ombro, piso, k / 4.0)), Vector2.LEFT])
	for k in range(1, 6):
		pts.append([Vector2(lerpf(-meia, meia, k / 6.0), piso), Vector2.DOWN])
	return pts


## Tubo de basalto: o contorno puxado ao longo da estrada, com a rocha avançando e recuando (ruído,
## só para fora), UV2.y = altura acima da lava (as fissuras acendem embaixo). Colisão mortal.
func _montar_tubo(mat: ShaderMaterial, mortal: StaticBody3D) -> void:
	var ruido := FastNoiseLite.new()
	ruido.seed = 71
	ruido.frequency = 0.16
	ruido.fractal_octaves = 3
	var grande := FastNoiseLite.new()
	grande.seed = 73
	grande.frequency = 0.035
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := maxi(i_ini - 1, 0)
	var b := mini(i_fim + 1, _p.size() - 1)
	var n_anel := _contorno(a).size()
	for i in range(a, b + 1):
		var anel := _contorno(i)
		for k in n_anel:
			var q: Vector2 = anel[k][0]
			var nrm: Vector2 = anel[k][1]
			var chao := 0.15 if nrm.y < -0.5 else 1.0
			var desloc := ((ruido.get_noise_2d(k * 2.3, _s[i]) * 0.5 + 0.5) * 0.7 + (grande.get_noise_2d(k * 1.3, _s[i]) * 0.5 + 0.5) * 1.6) * chao
			var r := q + nrm * desloc
			st.set_uv(Vector2(float(k) / n_anel, _s[i]))
			st.set_uv2(Vector2(0.0, maxf(r.y - lava_y, 0.05)))
			st.add_vertex(_p[i] + _l[i] * r.x + Vector3.UP * r.y)
	for i in b - a:
		var anel_i := _contorno(a + i)
		for k in n_anel - 1:
			if _no_nicho(a + i, anel_i[k][0]) and _no_nicho(a + i + 1, anel_i[k][0]) and _no_nicho(a + i, anel_i[k + 1][0]):
				continue
			var v0 := i * n_anel + k
			var v1 := v0 + n_anel
			st.add_index(v0); st.add_index(v1); st.add_index(v0 + 1)
			st.add_index(v0 + 1); st.add_index(v1); st.add_index(v1 + 1)
	st.generate_normals()
	var malha := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.material_override = mat
	add_child(mi)
	_montar_nichos(mat)
	var cs := CollisionShape3D.new()
	var forma := malha.create_trimesh_shape()
	forma.backface_collision = true
	cs.shape = forma
	mortal.add_child(cs)


## Rio de lava no fundo do túnel, por baixo da estrada, correndo no sentido contrário ao da subida, e
## luzes rasantes de lava a cada 45 m.
func _montar_lava() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(i_ini, i_fim):
		var m0: float = _meia[i] + 0.8
		var m1: float = _meia[i + 1] + 0.8
		var q := [_p[i] - _l[i] * m0, _p[i] + _l[i] * m0, _p[i + 1] + _l[i + 1] * m1, _p[i + 1] - _l[i + 1] * m1]
		var uv := [Vector2(0, -_s[i]), Vector2(1, -_s[i]), Vector2(1, -_s[i + 1]), Vector2(0, -_s[i + 1])]
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[k])
			st.add_vertex(q[k] + Vector3.UP * lava_y)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Dino.material_lava(0, 0.45, 0.8, 10.0, 5.0, (meia_base + 0.8) * 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var i := i_ini + 10
	while i < i_fim - 10:
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.4, 0.1)
		luz.light_energy = 2.6
		luz.omni_range = 34.0
		luz.omni_attenuation = 1.3
		luz.position = _p[i] + Vector3.UP * (lava_y + 2.5)
		add_child(luz)
		i += 30


## Seção do tubo na estação mais perto de p: [meia-largura, alto do arco acima da estrada]. Vazio se p
## está fora deste túnel (as armadilhas usam para a lava do teto pegar o tubo de parede a parede).
func secao_em(p: Vector3) -> Array:
	if i_ini < 0:
		return []
	var melhor := -1
	var d2 := 900.0
	for i in range(i_ini, i_fim + 1):
		var d := _p[i].distance_squared_to(p)
		if d < d2:
			d2 = d
			melhor = i
	return [] if melhor < 0 else [_meia[melhor], _topo[melhor]]


## Capa de rocha por cima da vala: a encosta natural entre as bocas (nunca abaixo do arco + 2,5 m) e,
## fora delas, o corte de acesso diante de cada boca. A capa vai além das bocas até a encosta natural
## ficar abaixo do corte da estrada (senão a borda dela ficaria flutuando sobre a vala).
func _montar_capa(terreno: Terreno, mortal: StaticBody3D, ate_o_fim: bool) -> void:
	var ns := _p.size()
	var nicho := FileAccess.file_exists(ProjectSettings.globalize_path(PORTAL_IMAGEM))
	var c0 := i_ini
	while c0 > 0 and _nat[c0] > _p[c0].y - 9.0:
		c0 -= 1
	var c1 := i_fim
	while c1 < ns - 1 and _nat[c1] > _p[c1].y - 9.0:
		c1 += 1
	if ate_o_fim:
		c1 = ns - 1
	var ls: Array[float] = []
	var l := -MEIA_CAPA
	while l <= MEIA_CAPA + 0.01:
		ls.append(l)
		l += 3.0
	var estacoes: Array[int] = []
	var i := c0
	while i <= c1:
		estacoes.append(i)
		i += 2
	if estacoes.back() != c1:
		estacoes.append(c1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nl := ls.size() + 2
	for e in estacoes:
		var corte: float = _meia[e] + 1.5
		var lista := ls.duplicate()
		lista.append(-corte)
		lista.append(corte)
		lista.sort()
		for ll: float in lista:
			var p: Vector3 = _p[e] + _l[e] * ll
			var h := terreno.altura_sem_estrada_malha(p.x, p.z)
			var dentro := e >= i_ini and e <= i_fim
			var al := absf(ll)
			if dentro:
				if al < corte + 2.5:
					h = maxf(h, _p[e].y + _topo[e] + 2.5)
			elif al <= corte + 0.01:
				h = minf(h, _p[e].y + piso - 1.0)
			elif nicho and e < i_ini:
				# Diante da boca de entrada o corte alarga até caber o pórtico inteiro (o paredão cortava o pilar)
				var w_n := (1.0 - smoothstep(9.0, 16.0, _s[i_ini] - _s[e])) * (1.0 - smoothstep(corte + 11.0, corte + 15.0, al))
				h = lerpf(h, minf(h, _p[e].y - 2.5), w_n)
			h -= 2.5 * smoothstep(MEIA_CAPA - 8.0, MEIA_CAPA, al)
			st.set_uv(Vector2(ll, _s[e]))
			st.add_vertex(Vector3(p.x, h, p.z))
	for a in estacoes.size() - 1:
		var ea: int = estacoes[a]
		var eb: int = estacoes[a + 1]
		var boca := (ea < i_ini and eb >= i_ini) or (ea <= i_fim and eb > i_fim)
		for k in nl - 1:
			if boca:
				# Furo da boca: entre o corte e o teto não há rocha (a placa da boca fecha em volta do arco)
				var xa := _pos_lateral(k, ea, ls)
				var xb := _pos_lateral(k + 1, ea, ls)
				if absf(xa) <= _meia[ea] + 1.51 and absf(xb) <= _meia[ea] + 1.51:
					continue
			var v0 := a * nl + k
			var v1 := v0 + nl
			st.add_index(v0); st.add_index(v1); st.add_index(v0 + 1)
			st.add_index(v0 + 1); st.add_index(v1); st.add_index(v1 + 1)
	st.generate_normals()
	var malha := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = malha
	mi.material_override = terreno._mat_terreno
	add_child(mi)
	var cs := CollisionShape3D.new()
	var forma := malha.create_trimesh_shape()
	forma.backface_collision = true
	cs.shape = forma
	mortal.add_child(cs)


## Lateral (m) do k-ésimo vértice de uma linha da capa (a lista com os dois cortes, ordenada).
func _pos_lateral(k: int, e: int, ls: Array[float]) -> float:
	var corte: float = _meia[e] + 1.5
	var lista := ls.duplicate()
	lista.append(-corte)
	lista.append(corte)
	lista.sort()
	return lista[k]


const PORTAL_IMAGEM := "res://assets/dino/portao/boca_do_vulcao.png"
## Onde ficam as duas folhas do portão na arte (u0, v0, largura, altura em UV) — são recortadas da fachada
## e montadas à parte, abertas de verdade.
const PORTAL_FOLHAS: Array[Rect2] = [Rect2(0.255, 0.455, 0.19, 0.53), Rect2(0.555, 0.455, 0.19, 0.53)]
## Tochas da arte (u, v): ganham fogo de verdade e luz.
const PORTAL_TOCHAS: Array[Vector2] = [Vector2(0.2, 0.11), Vector2(0.13, 0.33), Vector2(0.07, 0.62), Vector2(0.8, 0.11), Vector2(0.87, 0.33), Vector2(0.93, 0.62)]
static var _arte_cache := {}
static var _relevo_cache := {}


## Arte de um pórtico (desenho pronto do dono): [textura, máscara da fachada (sem fundo e sem as folhas),
## máscara inteira (sem fundo), largura / altura, e as duas máscaras e a cópia pequena como Image]. O fundo dessas artes é um clarão liso: recorta-se a
## partir das bordas tudo o que é liso (pouca diferença para os vizinhos) e não é chama; o que já vem
## transparente também sai. Vazio sem o arquivo.
static func texturas_arte(caminho: String, folhas: Array) -> Array:
	if _arte_cache.has(caminho):
		return _arte_cache[caminho]
	var img := Recinto.ler_imagem(caminho)
	if img == null:
		return []
	var razao := float(img.get_width()) / float(img.get_height())
	var w := 384
	var h := maxi(int(round(w / razao)), 8)
	var peq: Image = img.duplicate()
	peq.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var px := peq.get_data()   # RGBA8
	var liso := PackedByteArray()
	liso.resize(w * h)
	for y in h:
		for x in w:
			var k := (y * w + x) * 4
			var dif := 0
			for viz: int in [(-1 if x > 0 else 0), (1 if x < w - 1 else 0), (-w if y > 0 else 0), (w if y < h - 1 else 0)]:
				var j := k + viz * 4
				dif = maxi(dif, maxi(absi(px[k] - px[j]), maxi(absi(px[k + 1] - px[j + 1]), absi(px[k + 2] - px[j + 2]))))
			var lum := (px[k] * 0.3 + px[k + 1] * 0.59 + px[k + 2] * 0.11) / 255.0
			liso[y * w + x] = 1 if px[k + 3] < 128 or (dif < 12 and lum < 0.5) else 0
	var fora := PackedByteArray()
	fora.resize(w * h)
	var pilha: Array[int] = []
	for x in w:
		pilha.append(x)
		pilha.append((h - 1) * w + x)
	for y in h:
		pilha.append(y * w)
		pilha.append(y * w + w - 1)
	while not pilha.is_empty():
		var k: int = pilha.pop_back()
		if fora[k] == 1 or liso[k] == 0:
			continue
		fora[k] = 1
		var kx := k % w
		if kx > 0:
			pilha.append(k - 1)
		if kx < w - 1:
			pilha.append(k + 1)
		if k >= w:
			pilha.append(k - w)
		if k < w * (h - 1):
			pilha.append(k + w)
	var total := Image.create(w, h, false, Image.FORMAT_L8)
	var fachada := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for x in w:
			# Come um pixel da beirada (a franja do clarão em volta das pedras)
			var k := y * w + x
			var dentro := fora[k] == 0 and (x == 0 or fora[k - 1] == 0) and (x == w - 1 or fora[k + 1] == 0) and (y == 0 or fora[k - w] == 0) and (y == h - 1 or fora[k + w] == 0)
			total.set_pixel(x, y, Color.WHITE if dentro else Color.BLACK)
			var uv := Vector2((x + 0.5) / w, (y + 0.5) / h)
			var na_folha := false
			for r: Rect2 in folhas:
				na_folha = na_folha or r.grow(0.004).has_point(uv)
			fachada.set_pixel(x, y, Color.WHITE if dentro and not na_folha else Color.BLACK)
	if OS.get_environment("TSC_MASC_DIR") != "":
		var prev: Image = peq.duplicate()
		for y in h:
			for x in w:
				if total.get_pixel(x, y).r < 0.5:
					prev.set_pixel(x, y, Color(0.0, 0.6, 1.0))
		prev.save_png(OS.get_environment("TSC_MASC_DIR") + "/mascara_" + caminho.get_file())
	img.generate_mipmaps()
	_arte_cache[caminho] = [ImageTexture.create_from_image(img), ImageTexture.create_from_image(fachada), ImageTexture.create_from_image(total), razao, fachada, total, peq]
	return _arte_cache[caminho]


## Malha em relevo de um pedaço `r` (UV) da arte: uma grade em que cada célula dentro da máscara vira um
## pedaço de superfície empurrado para a frente — mais alto longe da beirada (o desenho "incha" como uma
## escultura) e nas partes claras (letras, pedras iluminadas) — com paredes laterais até `esp` m para trás.
## Assim o pórtico tem corpo de qualquer ângulo, em vez de ser um painel. Local: x = direita, y = cima,
## z = para quem olha; origem no meio do pedaço. Cor do vértice = sombra (paredes mais escuras).
static func relevo_arte(caminho: String, tx: Array, r: Rect2, masc: Image, larg: float, alt: float, esp: float, inchar: float, claro: float) -> ArrayMesh:
	var chave := "%s|%s|%s|%.2f|%.2f" % [caminho, str(r), str(masc.get_instance_id()), larg, esp]
	if _relevo_cache.has(chave):
		return _relevo_cache[chave]
	var peq: Image = tx[6]
	var mw := masc.get_width()
	var mh := masc.get_height()
	var nx := maxi(int(round(r.size.x * mw * 0.5)), 4)
	var ny := maxi(int(round(r.size.y * mh * 0.5)), 4)
	# Dentro/fora e distância até a beirada (em células), em duas passadas
	var dist := PackedFloat32Array()
	dist.resize(nx * ny)
	var lum := PackedFloat32Array()
	lum.resize(nx * ny)
	for j in ny:
		for i in nx:
			var px := clampi(int((r.position.x + r.size.x * (i + 0.5) / nx) * mw), 0, mw - 1)
			var py := clampi(int((r.position.y + r.size.y * (j + 0.5) / ny) * mh), 0, mh - 1)
			dist[j * nx + i] = 99.0 if masc.get_pixel(px, py).r > 0.5 else 0.0
			lum[j * nx + i] = peq.get_pixel(px, py).get_luminance()
	for passada in 2:
		var ordem_j := range(ny) if passada == 0 else range(ny - 1, -1, -1)
		var ordem_i := range(nx) if passada == 0 else range(nx - 1, -1, -1)
		var d := -1 if passada == 0 else 1
		for j: int in ordem_j:
			for i: int in ordem_i:
				var k := j * nx + i
				if dist[k] == 0.0:
					continue
				var m := dist[k]
				var bi := i + d
				var bj := j + d
				m = minf(m, (dist[k + d] if bi >= 0 and bi < nx else 0.0) + 1.0)
				m = minf(m, (dist[k + d * nx] if bj >= 0 and bj < ny else 0.0) + 1.0)
				m = minf(m, (dist[k + d * nx + d] if bi >= 0 and bi < nx and bj >= 0 and bj < ny else 0.0) + 1.4)
				m = minf(m, (dist[k + d * nx - d] if i - d >= 0 and i - d < nx and bj >= 0 and bj < ny else 0.0) + 1.4)
				dist[k] = m
	# Altura de cada célula e de cada vértice (média das células em volta; fora = 0, a beirada fica rente)
	var hc := PackedFloat32Array()
	hc.resize(nx * ny)
	for k in nx * ny:
		if dist[k] > 0.0:
			var t := clampf(dist[k] / 7.0, 0.0, 1.0)
			hc[k] = inchar * (1.0 - (1.0 - t) * (1.0 - t)) + claro * (lum[k] - 0.35) * t
	var vw := nx + 1
	var pos := PackedVector3Array()
	pos.resize(vw * (ny + 1))
	var passo_x := r.size.x * larg / nx
	var passo_y := r.size.y * alt / ny
	for j in ny + 1:
		for i in vw:
			var soma := 0.0
			for dj in [-1, 0]:
				for di in [-1, 0]:
					var ci: int = i + di
					var cj: int = j + dj
					if ci >= 0 and ci < nx and cj >= 0 and cj < ny:
						soma += hc[cj * nx + ci]
			pos[j * vw + i] = Vector3((i - nx * 0.5) * passo_x, (ny * 0.5 - j) * passo_y, soma * 0.25)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv_de := func(i: int, j: int) -> Vector2: return r.position + r.size * Vector2(float(i) / nx, float(j) / ny)
	var normal_de := func(i: int, j: int) -> Vector3:
		var a: Vector3 = pos[j * vw + mini(i + 1, nx)] - pos[j * vw + maxi(i - 1, 0)]
		var b: Vector3 = pos[maxi(j - 1, 0) * vw + i] - pos[mini(j + 1, ny) * vw + i]
		return a.cross(b).normalized()
	for j in ny:
		for i in nx:
			if dist[j * nx + i] == 0.0:
				continue
			var cantos := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]
			for q: int in [0, 1, 2, 0, 2, 3]:
				var ci: int = cantos[q][0]
				var cj: int = cantos[q][1]
				st.set_color(Color.WHITE)
				st.set_normal(normal_de.call(ci, cj))
				st.set_uv(uv_de.call(ci, cj))
				st.add_vertex(pos[cj * vw + ci])
			# Paredes onde o vizinho está fora: [vértice a, vértice b, normal]
			for lado: Array in [[0, 1, 0, -1, Vector3.UP], [1, 2, 1, 0, Vector3.RIGHT], [2, 3, 0, 1, Vector3.DOWN], [3, 0, -1, 0, Vector3.LEFT]]:
				var vi: int = i + lado[2]
				var vj: int = j + lado[3]
				if vi >= 0 and vi < nx and vj >= 0 and vj < ny and dist[vj * nx + vi] > 0.0:
					continue
				var ca: Array = cantos[lado[0]]
				var cb: Array = cantos[lado[1]]
				var pa_f: Vector3 = pos[int(ca[1]) * vw + int(ca[0])]
				var pb_f: Vector3 = pos[int(cb[1]) * vw + int(cb[0])]
				var pa_t := Vector3(pa_f.x, pa_f.y, -esp)
				var pb_t := Vector3(pb_f.x, pb_f.y, -esp)
				# A parede repete a borda do desenho (um pouco para dentro, para pegar pedra e não o clarão do fundo)
				var meio_uv: Vector2 = r.position + r.size * Vector2((i + 0.5) / nx, (j + 0.5) / ny)
				var ua: Vector2 = (uv_de.call(ca[0], ca[1]) as Vector2).lerp(meio_uv, 0.6)
				var ub: Vector2 = (uv_de.call(cb[0], cb[1]) as Vector2).lerp(meio_uv, 0.6)
				var fundo_d: Vector2 = Vector2(-(lado[4] as Vector3).x, (lado[4] as Vector3).y) * (esp / larg) * 0.6
				for v: Array in [[pa_f, ua, 0.75], [pb_f, ub, 0.75], [pb_t, ub + fundo_d, 0.4], [pa_f, ua, 0.75], [pb_t, ub + fundo_d, 0.4], [pa_t, ua + fundo_d, 0.4]]:
					st.set_color(Color(v[2], v[2], v[2]))
					st.set_normal(lado[4])
					st.set_uv(v[1])
					st.add_vertex(v[0])
	_relevo_cache[chave] = st.commit()
	return _relevo_cache[chave]


## Monta em `pai` um pórtico a partir da arte, em relevo (relevo_arte): a fachada de pé em `c`, virada para
## `para_fora`, com `larg` m de largura, `esp` m de espessura e o pé `y0` m acima de `c`; as folhas do
## portão (`folhas`, em UV) separadas e abertas para o lado de `para_fora`; luz de fogo nas `tochas` (UV).
## `verso` põe a arte também nas costas. Devolve a altura em metros (0 se a arte não está na pasta).
static func montar_arte(pai: Node3D, caminho: String, folhas: Array, tochas: Array, c: Vector3, para_fora: Vector3, larg: float, y0: float, verso := false, esp := 3.0) -> float:
	var tx := texturas_arte(caminho, folhas)
	if tx.is_empty():
		return 0.0
	var olhar := Basis.looking_at(-para_fora, Vector3.UP)   # +Z para quem chega; X = direita de quem chega
	var dir := olhar.x
	var alt := larg / float(tx[3])
	var centro := c + Vector3.UP * (y0 + alt * 0.5)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/arte_relevo.gdshader")
	mat.set_shader_parameter("imagem", tx[0])
	var inchar := larg * 0.03
	var malha := relevo_arte(caminho, tx, Rect2(0, 0, 1, 1), tx[4], larg, alt, esp, inchar, larg * 0.016)
	for face in (2 if verso else 1):
		var mi := MeshInstance3D.new()
		mi.mesh = malha
		mi.material_override = mat
		mi.transform = Transform3D(olhar if face == 0 else olhar * Basis(Vector3.UP, PI), centro + para_fora * ((esp if verso else 1.0) * (1.0 if face == 0 else -1.0)))
		pai.add_child(mi)
	# Folhas do portão: recortadas da arte, em relevo fino, presas pela dobradiça ao pilar e abertas
	var esp_f := larg * 0.006
	for k in folhas.size():
		var r: Rect2 = folhas[k]
		var lf := r.size.x * larg
		var s := -1.0 if r.get_center().x < 0.5 else 1.0   # folha da esquerda / da direita de quem chega
		var u_dob := r.position.x if s < 0.0 else r.end.x
		var dobradica := c + dir * ((u_dob - 0.5) * larg) + para_fora * ((esp if verso else 1.0) + inchar * 0.5) + Vector3.UP * (y0 + alt * (1.0 - r.position.y - r.size.y * 0.5))
		var ang := deg_to_rad(64.0)
		var eixo_x := (dir * cos(ang) - para_fora * sin(ang) * s).normalized()   # X local da folha (da esquerda para a direita da arte)
		var base := Basis(eixo_x, Vector3.UP, eixo_x.cross(Vector3.UP))
		var meio := dobradica - eixo_x * s * lf * 0.5
		var malha_f := relevo_arte(caminho, tx, r, tx[5], larg, alt, esp_f, larg * 0.006, larg * 0.008)
		for face in 2:
			var mif := MeshInstance3D.new()
			mif.mesh = malha_f
			mif.material_override = mat
			mif.transform = Transform3D(base if face == 0 else base * Basis(Vector3.UP, PI), meio + base.z * (esp_f if face == 0 else -esp_f))
			pai.add_child(mif)
	# Luz de fogo nas tochas da arte (a chama é a do desenho, acesa pelo shader)
	for q: Vector2 in tochas:
		var luz := OmniLight3D.new()
		luz.light_color = Color(1.0, 0.5, 0.16)
		luz.light_energy = 4.0
		luz.omni_range = larg * 0.5
		luz.shadow_enabled = false
		luz.position = c + dir * ((q.x - 0.5) * larg) + Vector3.UP * (y0 + alt * (1.0 - q.y)) + para_fora * ((esp if verso else 1.0) + inchar + 2.5)
		pai.add_child(luz)
	return alt


## Caixas de colisão de uma arte montada com montar_arte (mesmos parâmetros): a silhueta recortada da arte
## vira colunas de caixas — onde a arte é vazada (vão do pórtico, recortes da placa) não há colisão.
static func colisao_arte(caminho: String, folhas: Array, c: Vector3, para_fora: Vector3, larg: float, y0: float, verso := false, esp := 3.0) -> Array[Transform3D]:
	var caixas: Array[Transform3D] = []
	var tx := texturas_arte(caminho, folhas)
	if tx.is_empty():
		return caixas
	var olhar := Basis.looking_at(-para_fora, Vector3.UP)
	var alt := larg / float(tx[3])
	var centro := c + Vector3.UP * (y0 + alt * 0.5)
	var inchar := larg * 0.03
	# Da face de trás à da frente (com `verso` a arte tem duas faces, uma de cada lado do meio)
	var z0 := -(esp + inchar) if verso else 1.0 - esp
	var z1 := (esp + inchar) if verso else 1.0 + inchar
	var masc: Image = tx[4]
	const NX := 32
	var ny := maxi(int(round(NX / float(tx[3]))), 2)
	for i in NX:
		var j0 := -1
		for j in ny + 1:
			var cheio := false
			if j < ny:
				var px := clampi(int((i + 0.5) / NX * masc.get_width()), 0, masc.get_width() - 1)
				var py := clampi(int((j + 0.5) / ny * masc.get_height()), 0, masc.get_height() - 1)
				cheio = masc.get_pixel(px, py).r > 0.5
			if cheio and j0 < 0:
				j0 = j
			elif not cheio and j0 >= 0:
				var h := alt * (j - j0) / ny
				var y := alt * (0.5 - (j0 + j) * 0.5 / ny)
				caixas.append(Transform3D(olhar * Basis.from_scale(Vector3(larg / NX, h, z1 - z0)),
					centro + olhar.x * (((i + 0.5) / NX - 0.5) * larg) + Vector3.UP * y + para_fora * ((z0 + z1) * 0.5)))
				j0 = -1
	return caixas


## Pórtico "BOCA DO VULCÃO" na entrada do túnel (pedido do dono: igual à arte que ele mandou, no lugar da
## moldura de aço com o letreiro ZONA VULCÂNICA): a arte como fachada (montar_arte) e torres de rocha de
## verdade atrás dos pilares (volume e colisão). Devolve false se a arte não está na pasta.
func _montar_portal(c: Vector3, para_fora: Vector3, meia: float, mortal: StaticBody3D) -> bool:
	var larg := (meia * 2.0 + 1.0) / 0.5   # o vão entre os pilares da arte é metade da largura dela
	var y0 := -1.5                          # pé da arte, um pouco abaixo da estrada
	var alt := montar_arte(self, PORTAL_IMAGEM, PORTAL_FOLHAS, PORTAL_TOCHAS, c, para_fora, larg, y0)
	if alt <= 0.0:
		return false
	var dir := Basis.looking_at(-para_fora, Vector3.UP).x
	# Torres de rocha atrás dos pilares da arte, mais estreitas que eles (de frente ficam escondidas; de lado
	# o pórtico tem corpo; batendo nelas o carro explode)
	var torres: Array[Transform3D] = []
	var bh := Basis(dir, Vector3.UP, dir.cross(Vector3.UP))
	var base_t := piso - 1.0
	for s: float in [-1.0, 1.0]:
		for deg: Array in [[0.33, 0.13, 0.8], [0.385, 0.1, 0.42]]:   # [meio (fração da largura, a partir do centro), largura, altura (fração)]
			var topo_t := y0 + alt * float(deg[2])
			torres.append(Transform3D(bh * Basis.from_scale(Vector3(larg * float(deg[1]), topo_t - base_t, 4.0)),
				c + dir * s * larg * float(deg[0]) + Vector3.UP * ((topo_t + base_t) * 0.5) - para_fora * 0.9))
	ComplexoLancamento.criar_multimesh(self, torres, _terreno._mat_terreno)
	ComplexoLancamento.adicionar_colisoes(mortal, torres)
	# Ombro de montanha embaixo e em volta do pórtico (pedido do dono: a parte de baixo ficava no ar, sem
	# sustentação): a encosta avança até passar dos pilares e desce irregular até o terreno
	var ruido := FastNoiseLite.new()
	ruido.seed = 97
	ruido.frequency = 0.06
	ruido.fractal_octaves = 3
	const NL := 30
	const ND := 22
	var meia_l := larg * 0.78
	var d0 := -7.0
	var d1 := 30.0
	var topo_o := c.y + y0 + 0.6
	var alturas := PackedVector3Array()
	for j in ND + 1:
		var d := lerpf(d0, d1, float(j) / ND)
		for i in NL + 1:
			var l := lerpf(-meia_l, meia_l, float(i) / NL)
			var q := c + dir * l + para_fora * d
			var queda := maxf(d - 3.5, 0.0) * 1.05 + maxf(absf(l) - larg * 0.52, 0.0) * 1.6
			var h := topo_o - queda + ruido.get_noise_2d(q.x, q.z) * (1.2 + queda * 0.12)
			# Nas bordas mergulha para baixo do terreno (nada fica flutuando)
			var borda := maxf(smoothstep(0.8, 1.0, absf(l) / meia_l), smoothstep(0.82, 1.0, float(j) / ND))
			var chao := minf(_terreno.altura_sem_estrada_malha(q.x, q.z), c.y + piso - 1.0) - 3.0
			alturas.append(Vector3(q.x, lerpf(maxf(h, chao), chao, borda), q.z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vw := NL + 1
	for j in ND + 1:
		for i in vw:
			var e: Vector3 = alturas[j * vw + mini(i + 1, NL)] - alturas[j * vw + maxi(i - 1, 0)]
			var f: Vector3 = alturas[mini(j + 1, ND) * vw + i] - alturas[maxi(j - 1, 0) * vw + i]
			var nrm := e.cross(f).normalized()
			st.set_normal(nrm if nrm.y > 0.0 else -nrm)
			st.set_uv(Vector2(i, j))
			st.add_vertex(alturas[j * vw + i])
	for j in ND:
		for i in NL:
			var v0 := j * vw + i
			for v: int in [v0, v0 + vw, v0 + 1, v0 + 1, v0 + vw, v0 + vw + 1, v0, v0 + 1, v0 + vw, v0 + 1, v0 + vw + 1, v0 + vw]:
				st.add_index(v)
	var ombro_m := st.commit()
	var mi_o := MeshInstance3D.new()
	mi_o.mesh = ombro_m
	mi_o.material_override = _terreno._mat_terreno
	add_child(mi_o)
	var cs_o := CollisionShape3D.new()
	var forma_o := ombro_m.create_trimesh_shape()
	forma_o.backface_collision = true
	cs_o.shape = forma_o
	mortal.add_child(cs_o)
	return true


## Boca do túnel: placa de rocha com o furo em arco (fecha entre o arco e o corte), moldura de vigas
## de aço com faixas de perigo, letreiro aceso e luzes âmbar. `fora` = -1 na entrada, +1 na saída.
## Na entrada, havendo a arte na pasta, a moldura dá lugar ao pórtico BOCA DO VULCÃO (_montar_portal).
func _montar_boca(i: int, fora: float, mortal: StaticBody3D, texto: String) -> void:
	var c := _p[i]
	var lat := _l[i]
	var para_fora := _t[i] * fora
	var meia: float = _meia[i]
	var topo: float = _topo[i]
	var alt_arco := topo - ombro
	bocas.append([c, lat, -para_fora])
	# Placa de rocha (duas faces) com o furo do arco
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var larg := meia + 1.8
	var alto := topo + 2.6
	var baixo := piso - 1.2
	const COL := 32
	for k in COL:
		var x0 := lerpf(-larg, larg, float(k) / COL)
		var x1 := lerpf(-larg, larg, float(k + 1) / COL)
		var arco0 := (ombro + alt_arco * sqrt(maxf(1.0 - pow(x0 / meia, 2.0), 0.0))) if absf(x0) < meia else baixo
		var arco1 := (ombro + alt_arco * sqrt(maxf(1.0 - pow(x1 / meia, 2.0), 0.0))) if absf(x1) < meia else baixo
		for faixa: Array in [[arco0, alto, arco1, alto], [baixo, piso, baixo, piso]]:
			var a := c + lat * x0 + Vector3.UP * float(faixa[0]) + para_fora * 0.3
			var b := c + lat * x0 + Vector3.UP * float(faixa[1]) + para_fora * 0.3
			var cc := c + lat * x1 + Vector3.UP * float(faixa[2]) + para_fora * 0.3
			var d := c + lat * x1 + Vector3.UP * float(faixa[3]) + para_fora * 0.3
			for tri: Array in [[a, b, cc], [cc, b, d], [a, cc, b], [cc, d, b]]:
				for v: Vector3 in tri:
					st.add_vertex(v)
	st.generate_normals()
	var placa := MeshInstance3D.new()
	placa.mesh = st.commit()
	placa.material_override = _terreno._mat_terreno
	add_child(placa)
	# Entrada: pórtico BOCA DO VULCÃO (arte do dono) no lugar da moldura de aço
	if fora < 0.0 and _montar_portal(c, para_fora, meia, mortal):
		return
	# Moldura de aço em arco, faixas de perigo e o letreiro
	var bh := Basis(lat, Vector3.UP, lat.cross(Vector3.UP))   # sempre destra (instâncias espelhadas viram do avesso)
	var aco: Array[Transform3D] = []
	var luzes: Array[Transform3D] = []
	var folga := 0.6
	for s: float in [-1.0, 1.0]:
		aco.append(Transform3D(bh * Basis.from_scale(Vector3(0.9, ombro + 1.5, 1.2)), c + lat * s * (meia + folga) + Vector3.UP * (ombro * 0.5 - 0.6) + para_fora * 0.9))
	const GOMOS := 14
	for k in GOMOS:
		var u0 := float(k) / GOMOS
		var u1 := float(k + 1) / GOMOS
		var p0 := Vector2((meia + folga) * cos(PI * u0), ombro + (alt_arco + folga) * sin(PI * u0))
		var p1 := Vector2((meia + folga) * cos(PI * u1), ombro + (alt_arco + folga) * sin(PI * u1))
		var m := (p0 + p1) * 0.5
		var ang := atan2(p1.y - p0.y, p1.x - p0.x)
		aco.append(Transform3D(bh * Basis(Vector3.BACK, ang) * Basis.from_scale(Vector3(p0.distance_to(p1) + 0.3, 0.9, 1.2)), c + lat * m.x + Vector3.UP * m.y + para_fora * 0.9))
		if k % 2 == 0:
			luzes.append(Transform3D(bh * Basis(Vector3.BACK, ang) * Basis.from_scale(Vector3(0.35, 0.35, 0.2)), c + lat * m.x + Vector3.UP * m.y + para_fora * 1.55))
	var y_placa := topo + folga + 3.4
	aco.append(Transform3D(bh * Basis.from_scale(Vector3(meia * 2.0 + 8.0, 4.6, 0.5)), c + Vector3.UP * y_placa + para_fora * 1.0))
	var faixas: Array[Transform3D] = []
	for dy: float in [-2.6, 2.6]:
		faixas.append(Transform3D(bh * Basis.from_scale(Vector3(meia * 2.0 + 8.4, 0.6, 0.6)), c + Vector3.UP * (y_placa + dy) + para_fora * 1.05))
		for k in 13:
			var x := lerpf(-meia - 3.6, meia + 3.6, k / 12.0)
			luzes.append(Transform3D(bh * Basis.from_scale(Vector3(0.5, 0.3, 0.2)), c + lat * x + Vector3.UP * (y_placa + dy) + para_fora * 1.4))
	var metal := ShaderMaterial.new()
	metal.shader = load("res://shaders/metal_gasto.gdshader")
	metal.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 61))
	metal.set_shader_parameter("ferrugem", 0.45)
	metal.set_shader_parameter("cor_tinta", Color(0.18, 0.17, 0.16))
	metal.set_shader_parameter("altura_chao", c.y - 60.0)
	ComplexoLancamento.criar_multimesh(self, aco, metal)
	var listras := ShaderMaterial.new()
	listras.shader = load("res://shaders/listras_perigo.gdshader")
	listras.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 7))
	ComplexoLancamento.criar_multimesh(self, faixas, listras)
	ComplexoLancamento.criar_multimesh(self, luzes, ComplexoLancamento._material_luz(Color(1.0, 0.55, 0.15), 6.0), false)
	ComplexoLancamento.adicionar_colisoes(mortal, aco + faixas)
	var nome := Label3D.new()
	nome.text = texto
	nome.font_size = 256
	nome.pixel_size = 3.0 / 256.0
	nome.outline_size = 24
	nome.modulate = Color(1.0, 0.7, 0.25)
	nome.outline_modulate = Color(0.05, 0.03, 0.02)
	nome.double_sided = false
	nome.transform = Transform3D(Basis(lat * -fora, Vector3.UP, para_fora), c + Vector3.UP * y_placa + para_fora * 1.3)
	add_child(nome)


## O ponto (x lateral, y) da seção na estação i cai num nicho?
func _no_nicho(i: int, q: Vector2) -> bool:
	for ab in _aberturas:
		var meia_c := float(ab[2])
		if absf(_s[i] - float(ab[0])) > meia_c:
			continue
		var lado := float(ab[1])
		var dentro_lado := absf(q.x) > _meia[i] * 0.55 if lado == 0.0 else q.x * lado > _meia[i] * 0.55
		if dentro_lado and q.y > -1.2 and q.y < float(ab[3]):
			return true
	return false


## Salas de rocha atrás dos nichos com fundo (raptores): piso no nível da estrada, paredes, teto e
## uma brasa no fundo (os olhos dos bichos brilham na penumbra).
func _montar_nichos(mat: ShaderMaterial) -> void:
	var pecas: Array[Transform3D] = []
	for ab in _aberturas:
		var fundo := float(ab[4]) if ab.size() > 4 else 0.0
		if fundo <= 0.0:
			continue
		var i := 0
		while i < _s.size() - 1 and _s[i] < float(ab[0]):
			i += 1
		var c := _p[i]
		var lat := _l[i]
		var t := _t[i]
		var b := Basis(lat, Vector3.UP, -t)
		var meia_c := float(ab[2])
		var alto := float(ab[3])
		var lados: Array[float] = [-1.0, 1.0]
		if float(ab[1]) != 0.0:
			lados = [float(ab[1])]
		for s: float in lados:
			var x0 := _meia[i] - 0.5
			var xm := x0 + fundo * 0.5
			pecas.append(Transform3D(b * Basis.from_scale(Vector3(fundo + 1.0, 1.0, meia_c * 2.0 + 1.0)), c + lat * s * xm + Vector3.DOWN * 1.5))
			pecas.append(Transform3D(b * Basis.from_scale(Vector3(fundo + 1.0, 1.0, meia_c * 2.0 + 1.0)), c + lat * s * xm + Vector3.UP * (alto + 0.5)))
			pecas.append(Transform3D(b * Basis.from_scale(Vector3(1.0, alto + 2.0, meia_c * 2.0 + 1.0)), c + lat * s * (x0 + fundo + 0.5) + Vector3.UP * (alto * 0.5 - 0.5)))
			for z: float in [-1.0, 1.0]:
				pecas.append(Transform3D(b * Basis.from_scale(Vector3(fundo + 1.0, alto + 2.0, 1.0)), c + lat * s * xm + t * z * (meia_c + 0.5) + Vector3.UP * (alto * 0.5 - 0.5)))
			var brasa := OmniLight3D.new()
			brasa.light_color = Color(1.0, 0.35, 0.1)
			brasa.light_energy = 1.4
			brasa.omni_range = fundo + 4.0
			brasa.position = c + lat * s * (x0 + fundo - 1.0) + Vector3.UP * 1.0
			add_child(brasa)
	if not pecas.is_empty():
		ComplexoLancamento.criar_multimesh(self, pecas, mat)
