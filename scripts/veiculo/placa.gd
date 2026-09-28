class_name Placa
extends RefCounted
## Placa "TSCHALLENGER" no estilo do logo (itálico pesado; T e CHALLENGER escuros, S vermelho como no TSC),
## aplicada por cima das placas originais dos modelos (malhas com "numberplate" ou "_np" no nome).
## A arte é desenhada uma vez num SubViewport e compartilhada por todos os carros.

const TAMANHO := Vector2i(512, 256)

static var _viewport: SubViewport
static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_texture = _textura()
		_material.roughness = 0.35
		_material.metallic = 0.3
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _material


static func _textura() -> ViewportTexture:
	_viewport = SubViewport.new()
	_viewport.name = "ArtePlaca"
	_viewport.size = TAMANHO
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var fundo := Panel.new()
	var caixa := StyleBoxFlat.new()
	caixa.bg_color = Color(0.93, 0.93, 0.9)
	caixa.border_color = Color(0.08, 0.1, 0.16)
	caixa.set_border_width_all(14)
	caixa.set_corner_radius_all(26)
	fundo.add_theme_stylebox_override("panel", caixa)
	fundo.size = TAMANHO
	_viewport.add_child(fundo)
	# Faixa superior azul-escura com o nome do estúdio
	var topo := ColorRect.new()
	topo.color = Color(0.08, 0.14, 0.32)
	topo.position = Vector2(14, 14)
	topo.size = Vector2(TAMANHO.x - 28, 50)
	fundo.add_child(topo)
	var estudio := Label.new()
	estudio.text = "KZULO STUDIOS"
	estudio.add_theme_font_override("font", Estilo.fonte(700))
	estudio.add_theme_font_size_override("font_size", 30)
	estudio.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	estudio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	estudio.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	estudio.size = topo.size
	topo.add_child(estudio)
	# TSCHALLENGER: T escuro, S vermelho, CHALLENGER escuro (como no logo)
	var texto := RichTextLabel.new()
	texto.bbcode_enabled = true
	texto.fit_content = true
	texto.scroll_active = false
	texto.autowrap_mode = TextServer.AUTOWRAP_OFF
	texto.add_theme_font_override("normal_font", Estilo.fonte_titulo(900))
	texto.add_theme_font_size_override("normal_font_size", 60)
	texto.add_theme_color_override("default_color", Color(0.1, 0.12, 0.18))
	texto.text = "[center]T[color=#d41414]S[/color]CHALLENGER[/center]"
	texto.position = Vector2(0, 92)
	texto.size = Vector2(TAMANHO.x, 110)
	fundo.add_child(texto)
	# Traço vermelho com quadriculado (como sob o "TARGET SPEED CHALLENGER")
	var traco := ColorRect.new()
	traco.color = Color(0.83, 0.08, 0.08)
	traco.position = Vector2(60, 200)
	traco.size = Vector2(TAMANHO.x - 150, 10)
	fundo.add_child(traco)
	for i in 3:
		var q := ColorRect.new()
		q.color = Color(0.83, 0.08, 0.08)
		q.position = Vector2(TAMANHO.x - 80 + i * 16, 196 + (i % 2) * 8)
		q.size = Vector2(10, 10)
		fundo.add_child(q)
	var arvore := Engine.get_main_loop() as SceneTree
	arvore.root.add_child.call_deferred(_viewport)
	return _viewport.get_texture()


## Cobre cada placa do modelo com a arte TSCHALLENGER (quad filho da malha da placa, no espaço dela).
static func aplicar(modelo: Node) -> void:
	for n in modelo.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nome := String(mi.name).to_lower()
		if mi.mesh == null or not ("numberplate" in nome or "_np_" in nome):
			continue
		var aabb := mi.get_aabb()
		# Eixo mais fino = normal da placa; o sentido vem da normal real da malha
		var tam := aabb.size
		var eixo := 0 if tam.x <= tam.y and tam.x <= tam.z else (1 if tam.y <= tam.z else 2)
		var normal := Vector3.ZERO
		normal[eixo] = 1.0
		var normais: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		if not normais.is_empty() and normais[0][eixo] < 0.0:
			normal = -normal
		var outros := [0, 1, 2]
		outros.erase(eixo)
		var largura: float = maxf(tam[outros[0]], tam[outros[1]])
		var altura: float = minf(tam[outros[0]], tam[outros[1]])
		var eixo_largo: int = outros[0] if tam[outros[0]] >= tam[outros[1]] else outros[1]
		var direita := Vector3.ZERO
		direita[eixo_largo] = 1.0
		var cima := normal.cross(direita)
		if cima.dot(Vector3.UP) < 0.0 and eixo_largo != 1:
			direita = -direita
			cima = -cima
		var q := QuadMesh.new()
		q.size = Vector2(largura, altura)
		var placa := MeshInstance3D.new()
		placa.name = "PlacaTSC"
		placa.mesh = q
		placa.material_override = material()
		placa.layers = 1   # não recebe a faixa da equipe
		placa.transform = Transform3D(Basis(direita, cima, normal), aabb.get_center() + normal * largura * 0.015)
		mi.add_child(placa)


## Placas para modelos que não trazem placa própria: lista "placas" do veiculos.json,
## cada uma {"pos": [x, y, z], "normal": [x, y, z]} no espaço do .glb (antes da "escala").
## O tamanho é o mesmo das placas dos outros modelos (0,30 × 0,15 m).
static func aplicar_extras(modelo: Node3D, placas: Array, escala := 1.0) -> void:
	for p: Dictionary in placas:
		var normal := Vector3(p.normal[0], p.normal[1], p.normal[2]).normalized()
		var direita := Vector3.UP.cross(normal).normalized()
		var cima := normal.cross(direita)
		var q := QuadMesh.new()
		q.size = Vector2(0.3, 0.15) / escala
		var placa := MeshInstance3D.new()
		placa.name = "PlacaTSC"
		placa.mesh = q
		placa.material_override = material()
		placa.layers = 1
		placa.transform = Transform3D(Basis(direita, cima, normal), Vector3(p.pos[0], p.pos[1], p.pos[2]))
		modelo.add_child(placa)
