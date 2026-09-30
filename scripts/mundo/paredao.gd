class_name ParedaoFino
extends Node3D
## Paredão fino com buraco de atalho (Climb to Death, etapa 4, desenho do dono): uma parede de
## rocha de 3 m de espessura ligando duas montanhas, com um buraco redondo na altura do voo.
## A boca tem anel de faixas de perigo, forro de aço e luzes (destaque de longe).
## Quem passa pelo buraco com o paraquedas aberto tem o velame murcho pelo teto do buraco
## (Veiculo.murchar_velame); é preciso fechar o paraquedas no ar antes. Bater na parede ou
## na borda do buraco explode o carro (grupo "mortal").

const MOLDURA := 1.2      # largura da faixa de metal em volta do buraco
const RESSALTO := 0.35    # quanto a moldura sai da face da parede


func montar(cfg: Dictionary, terreno: Terreno) -> void:
	name = "ParedaoFino"
	var a := Vector2(float(cfg.a[0]), float(cfg.a[1]))
	var b := Vector2(float(cfg.b[0]), float(cfg.b[1]))
	var esp := float(cfg.get("espessura", 3.0))
	var topo := float(cfg.get("altura", 330.0))
	var bur: Dictionary = cfg.get("buraco", {})
	var raio := float(bur.get("diametro", 8.0)) * 0.5
	var yc := float(bur.get("altura_centro", 140.0))
	var q := raio + MOLDURA + 1.5   # meio lado do painel quadrado que leva o furo
	var larg := q * 2.0
	var comp := a.distance_to(b)
	var d2 := (b - a) / comp
	var d := Vector3(d2.x, 0.0, d2.y)
	var n := d.cross(Vector3.UP).normalized()
	var c2 := Vector2(float(bur.centro[0]), float(bur.centro[1])) if bur.has("centro") else (a + b) * 0.5
	var t_b := clampf((c2 - a).dot(d2), larg, comp - larg)
	# Pé da parede um pouco abaixo do chão mais baixo ao longo dela
	var base := INF
	var t := 0.0
	while t <= comp:
		var p := a + d2 * t
		base = minf(base, terreno.altura_em(p.x, p.y))
		t += 10.0
	base -= 2.0
	var origem := Vector3(a.x, 0.0, a.y)
	var bl := Basis(d, Vector3.UP, n)
	var caixa := func(t0: float, t1: float, y0: float, y1: float, e: float, desloc: float) -> Transform3D:
		return Transform3D(bl * Basis.from_scale(Vector3(t1 - t0, y1 - y0, e)), origem + d * ((t0 + t1) * 0.5) + Vector3.UP * ((y0 + y1) * 0.5) + n * desloc)

	# ---- Parede em quatro partes em volta do painel quadrado que leva o furo redondo
	var t0 := t_b - q
	var t1 := t_b + q
	var rocha: Array[Transform3D] = [
		caixa.call(0.0, t0, base, topo, esp, 0.0),
		caixa.call(t1, comp, base, topo, esp, 0.0),
		caixa.call(t0, t1, base, yc - q, esp, 0.0),
		caixa.call(t0, t1, yc + q, topo, esp, 0.0),
	]
	# Centro do furo (eixo local: x ao longo da parede, y para cima, z = normal da parede)
	var no_furo := Transform3D(bl, origem + d * t_b + Vector3.UP * yc)
	var meia := esp * 0.5

	# Luzes âmbar em volta da boca, nas duas faces (a boca aparece de longe)
	var luzes: Array[Transform3D] = []
	for s: float in [-1.0, 1.0]:
		for k in 16:
			var ang := TAU * k / 16.0
			var p := Vector3(cos(ang), sin(ang), 0.0) * (raio + MOLDURA * 0.5) + Vector3(0.0, 0.0, s * (meia + 0.1))
			luzes.append(no_furo * Transform3D(Basis.from_scale(Vector3(0.3, 0.3, 0.12)), p))

	# ---- Visual
	ComplexoLancamento.criar_multimesh(self, rocha, terreno._mat_terreno)
	var painel := _anel(raio, q, meia, true)          # rocha do painel, com o furo
	var tubo := _tubo(raio, meia)                       # forro de aço por dentro do furo
	var moldura := _anel(raio, raio + MOLDURA, meia + 0.05, false)   # faixas de perigo nas duas faces
	var listras := ShaderMaterial.new()
	listras.shader = load("res://shaders/listras_perigo.gdshader")
	listras.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 3, 7))
	var metal := ShaderMaterial.new()
	metal.shader = load("res://shaders/metal_gasto.gdshader")
	metal.set_shader_parameter("ruido", Terreno._textura_ruido(0.03, 4, 61))
	metal.set_shader_parameter("ferrugem", 0.25)
	metal.set_shader_parameter("cor_tinta", Color(0.2, 0.22, 0.24))
	metal.set_shader_parameter("altura_chao", base)
	for par: Array in [[painel, terreno._mat_terreno], [tubo, metal], [moldura, listras]]:
		var mi := MeshInstance3D.new()
		mi.mesh = par[0]
		mi.material_override = par[1]
		mi.transform = no_furo
		add_child(mi)
	ComplexoLancamento.criar_multimesh(self, luzes, ComplexoLancamento._material_luz(Color(1.0, 0.62, 0.2), 6.0), false)

	# ---- Colisão (tudo mortal): caixas da parede + painel e tubo do furo
	var mortal := StaticBody3D.new()
	mortal.collision_layer = 1
	mortal.collision_mask = 0
	mortal.add_to_group("estrutura")
	mortal.add_to_group("mortal")
	add_child(mortal)
	ComplexoLancamento.adicionar_colisoes(mortal, rocha)
	for m: ArrayMesh in [painel, tubo]:
		var cf := CollisionShape3D.new()
		cf.shape = m.create_trimesh_shape()
		cf.transform = no_furo
		mortal.add_child(cf)

	# ---- Passar pelo furo murcha o velame de quem está com o paraquedas aberto
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 2   # carros
	area.monitoring = true
	area.monitorable = false
	var cs := CollisionShape3D.new()
	var forma := CylinderShape3D.new()
	forma.radius = raio
	forma.height = esp + 3.0
	cs.shape = forma
	area.add_child(cs)
	area.transform = Transform3D(Basis(d, n, d.cross(n)), no_furo.origin)
	area.body_entered.connect(_passou_no_buraco)
	add_child(area)


const SEGMENTOS := 48   # múltiplo de 8: os cantos do quadrado caem em vértices


## Faces (frente e verso, em z = ±meia) entre o círculo de raio r_in e o contorno externo: um
## quadrado de meio lado r_out (quadrado = true) ou outro círculo. Cada triângulo vai nas duas
## voltas, então aparece seja qual for o lado de onde se olha.
static func _anel(r_in: float, r_out: float, meia: float, quadrado: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: float in [-1.0, 1.0]:
		var normal := Vector3(0.0, 0.0, s)
		for i in SEGMENTOS:
			var pts: Array[Vector3] = []
			for j: int in [i, i + 1]:
				var ang := TAU * j / SEGMENTOS
				var dir := Vector2(cos(ang), sin(ang))
				var fora := dir / maxf(absf(dir.x), absf(dir.y)) * r_out if quadrado else dir * r_out
				pts.append(Vector3(dir.x * r_in, dir.y * r_in, s * meia))
				pts.append(Vector3(fora.x, fora.y, s * meia))
			_quad(st, pts[0], pts[1], pts[3], pts[2], normal)
	return st.commit()


## Parede de dentro do furo (cilindro de raio r de z = -meia a +meia), normal para o eixo.
static func _tubo(r: float, meia: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTOS:
		var a0 := TAU * i / SEGMENTOS
		var a1 := TAU * (i + 1) / SEGMENTOS
		var p0 := Vector3(cos(a0) * r, sin(a0) * r, 0.0)
		var p1 := Vector3(cos(a1) * r, sin(a1) * r, 0.0)
		var normal := -((p0 + p1) * 0.5).normalized()
		_quad(st, p0 + Vector3(0, 0, -meia), p1 + Vector3(0, 0, -meia), p1 + Vector3(0, 0, meia), p0 + Vector3(0, 0, meia), normal)
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for tri: Array in [[a, b, c], [a, c, d], [a, c, b], [a, d, c]]:
		for v: Vector3 in tri:
			st.set_normal(normal)
			st.add_vertex(v)


func _passou_no_buraco(corpo: Node3D) -> void:
	if corpo is Veiculo and (corpo as Veiculo).paraquedas_aberto:
		(corpo as Veiculo).murchar_velame()
