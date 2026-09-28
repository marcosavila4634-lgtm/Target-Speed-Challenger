class_name ChamaNitro
extends Node3D
## Chama azul nos escapamentos enquanto o nitro está ativo: jato com núcleo claro e diamantes
## de choque (shaders/chama_nitro.gdshader), luz azul tremulando na traseira,
## estouro na ignição e apagar rápido ao soltar.
## A ponta dos canos é achada pelos anéis de vértices da boca do cano (_achar_escapamentos); "escapamentos" no
## veiculos.json ([[x, y, z], ...], espaço do carro: frente em -Z, chão em y = 0) substitui a detecção.

const SHADER := preload("res://shaders/chama_nitro.gdshader")

var veiculo: Veiculo
var _jatos: Array = []      # [ShaderMaterial corpo, ShaderMaterial núcleo]
var _luz: OmniLight3D
var _nivel := 0.0           # 0..1 suavizado
var _ativo_ant := false
var _estouro := 0.0         # sobra de intensidade logo após a ignição


static func montar(v: Veiculo) -> ChamaNitro:
	var c := ChamaNitro.new()
	c.name = "ChamaNitro"
	c.veiculo = v
	v.add_child(c)
	var pontos: Array = []
	for p in v.dados.get("escapamentos", []):
		pontos.append(Vector3(p[0], p[1], p[2]))
	if pontos.is_empty():
		pontos = c._achar_escapamentos()
	for p: Vector3 in pontos:
		c._criar_jato(p)
	c._luz = OmniLight3D.new()
	c._luz.light_color = Color(0.35, 0.55, 1.0)
	c._luz.omni_range = 3.5
	c._luz.light_energy = 0.0
	c._luz.shadow_enabled = false
	c._luz.position = pontos[0] * Vector3(0, 1, 1) + Vector3(0, 0.1, 0.5) if not pontos.is_empty() else Vector3.ZERO
	c.add_child(c._luz)
	c.visible = false
	return c


## Pontas dos canos: a boca de um escapamento é um anel de vértices num mesmo plano virado
## para trás, com raio de 2 a 7 cm, na parte baixa e traseira do carro. Procura esses anéis
## (vértices agrupados por profundidade de 1 cm e por vizinhança) e fica com os mais baixos.
## Sem nada confiável: embaixo do para-choque, nos dois lados. Resultado guardado por modelo.
static var _cache := {}

func _achar_escapamentos() -> Array:
	var chave: String = veiculo.dados.get("id", "")
	if _cache.has(chave):
		return _cache[chave]
	var caixa: AABB = veiculo.caixa_corpo
	var r_roda: float = veiculo.rodas[0].raio if not veiculo.rodas.is_empty() else 0.3
	var y_max := minf(caixa.end.y * 0.5, 0.75)
	var z_min := caixa.end.z - minf(caixa.size.z * 0.3, 1.2)
	var inv := veiculo.global_transform.affine_inverse()
	# Vértices candidatos (sem repetição), por fatia de profundidade de 1 cm
	var fatias := {}
	var vistos := {}
	for n in veiculo.modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.name == "PlacaTSC":
			continue
		var xf := inv * mi.global_transform
		for s in mi.mesh.get_surface_count():
			for p: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var q := xf * p
				if q.y < 0.05 or q.y > y_max or q.z < z_min:
					continue
				var id := Vector3i(roundi(q.x * 500.0), roundi(q.y * 500.0), roundi(q.z * 500.0))
				if vistos.has(id):
					continue
				vistos[id] = true
				var k := roundi(q.z * 100.0)
				if not fatias.has(k):
					fatias[k] = PackedVector3Array()
				fatias[k].append(q)
	# Em cada fatia, agrupa vértices próximos (até 16 cm) e testa se o grupo é um anel
	var aneis: Array = []
	for k in fatias:
		var pts: PackedVector3Array = fatias[k]
		if pts.size() < 8 or pts.size() > 4000:
			continue
		var usado := PackedByteArray()
		usado.resize(pts.size())
		for a in pts.size():
			if usado[a] == 1:
				continue
			var grupo: Array = [pts[a]]
			usado[a] = 1
			var gi := 0
			while gi < grupo.size():
				var g: Vector3 = grupo[gi]
				for b in pts.size():
					if usado[b] == 0 and absf(pts[b].x - g.x) < 0.035 and absf(pts[b].y - g.y) < 0.035:
						usado[b] = 1
						grupo.append(pts[b])
				gi += 1
				if grupo.size() > 64:
					break
			if grupo.size() < 8 or grupo.size() > 64:
				continue
			var centro := Vector3.ZERO
			for g: Vector3 in grupo:
				centro += g
			centro /= grupo.size()
			var raios: Array = []
			for g: Vector3 in grupo:
				raios.append(Vector2(g.x - centro.x, g.y - centro.y).length())
			var media: float = raios.reduce(func(x, y): return x + y) / raios.size()
			var desvio := 0.0
			for r in raios:
				desvio += (r - media) * (r - media)
			desvio = sqrt(desvio / raios.size())
			if media >= 0.018 and media <= 0.075 and desvio < media * 0.18:
				aneis.append(centro)
	# Junta anéis concêntricos (borda externa/interna) ficando com o mais traseiro
	var bocas: Array = []
	for a: Vector3 in aneis:
		var junto := false
		for i in bocas.size():
			if Vector2(a.x - bocas[i].x, a.y - bocas[i].y).length() < 0.06:
				if a.z > bocas[i].z:
					bocas[i] = a
				junto = true
				break
		if not junto:
			bocas.append(a)
	# Os mais baixos (escapamento fica embaixo; lanterna redonda fica em cima), no máximo 4
	bocas.sort_custom(func(a, b): return a.y < b.y)
	var pontos: Array = []
	for b: Vector3 in bocas:
		if pontos.size() < 4 and b.y < bocas[0].y + 0.12 and b.z > caixa.end.z - 0.35:   # anel lá dentro = silencioso, não a ponta
			pontos.append(b)
	if pontos.is_empty():
		var z := caixa.end.z - 0.1
		pontos = [Vector3(-caixa.size.x * 0.28, r_roda * 0.9, z), Vector3(caixa.size.x * 0.28, r_roda * 0.9, z)]
	_cache[chave] = pontos
	return pontos


func _criar_jato(p: Vector3) -> void:
	var raiz := Node3D.new()
	# Eixo Y do jato apontando para trás (+Z do carro) e um pouco para baixo
	raiz.basis = Basis(Vector3.RIGHT, deg_to_rad(84.0))
	raiz.position = p + Vector3(0, 0, 0.02)
	add_child(raiz)
	var semente := randf() * 10.0
	var mats: Array = []
	for nucleo in [false, true]:
		var cil := CylinderMesh.new()
		cil.top_radius = 1.0
		cil.bottom_radius = 1.0
		cil.height = 1.0
		cil.radial_segments = 14
		cil.rings = 18
		cil.cap_top = false
		cil.cap_bottom = false
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("nucleo", nucleo)
		mat.set_shader_parameter("semente", semente)
		mat.set_shader_parameter("intensidade", 0.0)
		mat.render_priority = 1 if nucleo else 0
		var mi := MeshInstance3D.new()
		mi.mesh = cil
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = 1
		mi.extra_cull_margin = 2.0   # a forma real vem do shader de vértice
		raiz.add_child(mi)
		mats.append(mat)
	_jatos.append(mats)


func _process(delta: float) -> void:
	if veiculo == null or _jatos.is_empty():
		return
	var ativo: bool = veiculo.nitro_ativo
	if ativo and not _ativo_ant:
		_estouro = 0.45   # a chama "estoura" mais longa na ignição e assenta
	_ativo_ant = ativo
	_estouro = move_toward(_estouro, 0.0, delta * 2.2)
	# Acende rápido e apaga mais rápido ainda (corte de combustível)
	_nivel = move_toward(_nivel, 1.0 if ativo else 0.0, delta * (9.0 if ativo else 14.0))
	visible = _nivel > 0.001
	if not visible:
		return
	var cintila := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.09) * randf()
	var intens := _nivel * cintila + _estouro
	var vel := veiculo.linear_velocity.length()
	# Mais comprido com o carro parado (sem vento empurrando), mais curto e grosso em alta
	var comp := lerpf(1.5, 1.1, clampf(vel / 60.0, 0.0, 1.0)) * (1.0 + _estouro * 0.6)
	for j: Array in _jatos:
		for mat: ShaderMaterial in j:
			mat.set_shader_parameter("intensidade", intens)
			mat.set_shader_parameter("comprimento", comp)
	_luz.light_energy = 2.2 * intens * (0.7 + 0.3 * randf())
