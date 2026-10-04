extends RefCounted
## Megalodonte congelado do Frozen Peak (pedido do dono, 2026-10-04): o tubarão gigante sai do lago
## congelado do castelo com a cabeça para fora e a boca aberta — a boca é o alvo final (etapas[].tubarao).
## O tampo do alvo (disco) fica deitado em cima da mandíbula de baixo; o tubarão inclina o focinho para
## cima e a mandíbula abre o mesmo tanto, ficando na horizontal, virada para quem chega voando.
## Modelo: assets/frozen/animais/shark/shark_modelo.glb (Cretoxyrhina, CC-BY, reduzido de 1,3 milhão para
## 67 mil triângulos — ver creditos.txt). Sem ossos: a mandíbula abre no shader (shaders/tubarao.gdshader).

const MODELO := "res://assets/frozen/animais/shark/shark_modelo.glb"
const ARTIC := Vector3(0.0, 7.2, 10.0)     # articulação da mandíbula (espaço da malha: +Z = focinho)
const QUEIXO := Vector3(0.0, 6.3, 12.4)    # meio da mandíbula de baixo

static var _pecas: Array = []   # [[malha, textura], ...]


static func _carregar() -> Array:
	if not _pecas.is_empty():
		return _pecas
	var arq := ProjectSettings.globalize_path(MODELO)
	if not FileAccess.file_exists(arq):
		return []
	var doc := GLTFDocument.new()
	var estado := GLTFState.new()
	if doc.append_from_file(arq, estado) != OK:
		return []
	var cena := doc.generate_scene(estado)
	for no in cena.find_children("*", "MeshInstance3D", true, false):
		var mi := no as MeshInstance3D
		var mat := mi.get_active_material(0) as BaseMaterial3D
		_pecas.append([mi.mesh, mat.albedo_texture if mat else null])
	cena.free()
	return _pecas


## Monta o tubarão em volta do tampo do `alvo` (origem do alvo = centro do tampo, em cima).
static func montar(alvo: Node3D, etapa: Dictionary) -> void:
	var cfg: Dictionary = etapa.get("tubarao", {})
	var pecas := _carregar()
	if pecas.is_empty():
		return
	var diam := float(etapa.get("diametro", 26.0))
	var esc := float(cfg.get("escala", diam / 4.0))          # a boca do modelo tem ~5,4 de largura
	var incl := deg_to_rad(float(cfg.get("inclinacao", 55.0)))
	var fr: Array = cfg.get("frente", [-1, 0])
	var f := Vector3(float(fr[0]), 0.0, float(fr[1])).normalized()
	var b_giro := Basis(Vector3.UP, atan2(f.x, f.z))
	var b_incl := Basis(Vector3.RIGHT, -incl)
	# Mandíbula aberta `incl`: fica na horizontal, só deslocada (a abertura desfaz a inclinação)
	var queixo := b_incl * ARTIC + (QUEIXO - ARTIC)
	var origem := Vector3(0.0, -2.2, 0.0) - b_giro * (queixo * esc)
	var no := Node3D.new()
	no.name = "Tubarao"
	alvo.add_child(no)
	no.transform = Transform3D(b_giro * b_incl * Basis.from_scale(Vector3.ONE * esc), origem)
	for p: Array in pecas:
		var mi := MeshInstance3D.new()
		mi.mesh = p[0]
		var m := ShaderMaterial.new()
		m.shader = load("res://shaders/tubarao.gdshader")
		m.set_shader_parameter("tex", p[1])
		m.set_shader_parameter("ruido", Terreno._textura_ruido(0.05, 4, 311))
		m.set_shader_parameter("abre", incl)
		m.set_shader_parameter("artic", ARTIC)
		mi.material_override = m
		mi.extra_cull_margin = 60.0
		no.add_child(mi)
	# Colisão (não mata: quem bate no céu da boca cai na língua; quem escorrega do focinho cai no lago)
	var corpo := StaticBody3D.new()
	corpo.collision_layer = 1
	corpo.collision_mask = 0
	corpo.add_to_group("estrutura")
	alvo.add_child(corpo)
	# (o dono pousou nele e atravessou: as duas caixas de antes não cobriam a cabeça) — a colisão agora é a
	# própria malha do corpo, com a mandíbula aberta como no shader
	var xf := no.transform
	var faces := PackedVector3Array()
	var maior: ArrayMesh = null
	var qtd_maior := 0
	for p: Array in pecas:
		var qtd := (p[0] as Mesh).get_faces().size()
		if qtd > qtd_maior:
			qtd_maior = qtd
			maior = p[0]
	for v: Vector3 in maior.get_faces():
		var w := smoothstep(ARTIC.y + 0.25, ARTIC.y - 0.35, v.y) * smoothstep(ARTIC.z - 2.5, ARTIC.z + 0.3, v.z)
		var d := v - ARTIC
		var a := incl * w
		faces.append(xf * (ARTIC + Vector3(d.x, d.y * cos(a) - d.z * sin(a), d.y * sin(a) + d.z * cos(a))))
	var casca := ConcavePolygonShape3D.new()
	casca.backface_collision = true
	casca.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = casca
	corpo.add_child(cs)
	# Luz fria dentro da boca
	var luz := OmniLight3D.new()
	luz.light_color = Color(0.5, 0.85, 1.0)
	luz.light_energy = 2.5
	luz.omni_range = diam * 1.6
	luz.shadow_enabled = false
	luz.position = Vector3(0.0, diam * 0.3, 0.0)
	alvo.add_child(luz)
