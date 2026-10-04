extends SceneTree
## Recorta só o INTERIOR de um carro completo (.glb) e salva um .glb novo em assets/cockpit/<id>/.
## Peça entra se a caixa dela cabe na caixa da cabine (com folga) e o material não é de vidro,
## lataria ou luz; as de incluir_nomes entram inteiras (ex.: retrovisores externos). O resultado
## sai em metros, frente para -Z, piloto do lado -X, e com texturas de no máximo 2048 px. Também
## tira uma foto do ponto de vista do piloto para conferência.
## Uso: godot -s tools/cockpit/extrair.gd -- <id> [pasta_fotos]
## (config em tools/cockpit/interiores.json)

const CONFIG := "res://tools/cockpit/interiores.json"
const TEX_MAX := 2048

var _texturas := {}   # textura original -> reduzida (compartilhada entre materiais)


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0]
	var fotos: String = args[1] if args.size() > 1 else ""
	var todos: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	var c: Dictionary = todos[id]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(c.arquivo, st) != OK:
		push_error("não abriu " + c.arquivo)
		quit(1)
		return
	var fonte: Node = doc.generate_scene(st)
	# Base: escala e giro para a frente ficar em -Z
	var base := Transform3D(Basis(Vector3.UP, PI if bool(c.get("frente_mais_z", false)) else 0.0).scaled(Vector3.ONE * float(c.get("escala", 1.0))), Vector3.ZERO)
	var cx: Array = c.caixa   # [xmin, xmax, ymin, ymax, zmin, zmax] já em metros e com a frente em -Z
	var caixa := AABB(Vector3(cx[0], cx[2], cx[4]), Vector3(cx[1] - cx[0], cx[3] - cx[2], cx[5] - cx[4]))
	var folga := float(c.get("folga", 0.05))
	var fora_mat: Array = c.get("excluir_materiais", [])
	fora_mat.append_array(["glass", "window", "vidro", "paint", "light", "lamp", "tyre", "tire", "rotor", "caliper", "brake", "plate", "undercar", "wheel"])
	var so_mat: Array = c.get("so_materiais", [])
	var fora_nome: Array = c.get("excluir_nomes", [])
	var incluir: Array = c.get("incluir_nomes", [])
	var saida := Node3D.new()
	saida.name = id
	var n := 0
	var tri := 0
	for mi: MeshInstance3D in fonte.find_children("*", "MeshInstance3D", true, false):
		var t := base * _glob(mi, fonte)
		var ab := t * mi.get_aabb()
		var recortar := false   # peça grande (carroceria + interior juntos): recorta por triângulo
		# Peças que entram inteiras mesmo passando da cabine (ex.: retrovisores externos)
		var inteira := incluir.any(func(k): return str(mi.name).contains(k) or str(mi.get_parent().name).contains(k))
		if not inteira and not caixa.grow(folga).encloses(ab):
			if not bool(c.get("recortar", true)) or not caixa.intersects(ab):
				continue
			recortar = true
		if fora_nome.any(func(k): return str(mi.name).contains(k)):
			continue
		# Separa por superfície: só ficam as superfícies com material aceito
		var malha := ArrayMesh.new()
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			var nome_m := (m.resource_name if m else "").to_lower()
			if not so_mat.is_empty() and not so_mat.any(func(k): return nome_m.contains(k)):
				continue
			if fora_mat.any(func(k): return nome_m.contains(k)):
				continue
			# Só os canais comuns (sem ossos nem canais extras, que não fazem sentido parados)
			var orig := mi.mesh.surface_get_arrays(s)
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_INDEX]:
				arr[k] = orig[k]
			if recortar:
				arr = _recortar(arr, t, caixa)
				if arr.is_empty():
					continue
			malha.add_surface_from_arrays(mi.mesh.surface_get_primitive_type(s), arr)
			malha.surface_set_material(malha.get_surface_count() - 1, _reduzir(m))
			malha.surface_set_name(malha.get_surface_count() - 1, nome_m)
			tri += arr[Mesh.ARRAY_INDEX].size() / 3 if arr[Mesh.ARRAY_INDEX] != null else arr[Mesh.ARRAY_VERTEX].size() / 3
		if malha.get_surface_count() == 0:
			continue
		var novo := MeshInstance3D.new()
		novo.name = "%s_%d" % [mi.name, n]
		novo.mesh = malha
		novo.transform = t
		saida.add_child(novo)
		novo.owner = saida
		n += 1
	print("[INTERIOR] %s: %d peças, %d triângulos" % [id, n, tri])
	await _marcas(saida, c.get("marcas", []), fotos + "/" + id if fotos != "" else "")
	var pasta := "res://assets/cockpit/%s" % id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(pasta))
	var doc2 := GLTFDocument.new()
	var st2 := GLTFState.new()
	doc2.append_from_scene(saida, st2)
	var err := doc2.write_to_filesystem(st2, ProjectSettings.globalize_path("%s/%s.glb" % [pasta, id]))
	print("[INTERIOR] gravado %s/%s.glb (%s)" % [pasta, id, error_string(err)])
	if fotos != "":
		await _fotos(saida, c, fotos + "/" + id)
	quit()


# ------------------------------------------------------------------ troca das marcas

## Pinta por cima das marcas reais e escreve TSChallenger/TSC no lugar. Cada item da config:
## {"material": trecho do nome, "canal": "albedo"|"emission", "ops": [...]}. Operações (coordenadas
## de 0 a 1 na textura, [x0, y0, x1, y1]):
##   {"r": [...], "fundo": [r,g,b] | "auto" | null, "texto": "...", "cor": [r,g,b], "fonte": "titulo"|"racing"|"sans",
##    "espelhar": bool, "virar": bool, "girar": 0|90|270, "alfa": bool (texto vira o canal alfa), "altura": 0..1}
##   {"poligono": [[x,y], ...], "fundo": [r,g,b]}
func _marcas(no: Node, lista: Array, pasta_fotos: String) -> void:
	if lista.is_empty():
		return
	var feitos := {}
	for mi: MeshInstance3D in no.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if m == null:
				continue
			var nome := m.resource_name.to_lower()
			for item: Dictionary in lista:
				# "material": trecho do nome; ou lista de nomes exatos
				if item.material is Array:
					if not (item.material as Array).any(func(k): return str(k).to_lower() == nome):
						continue
				elif not nome.contains(str(item.material).to_lower()):
					continue
				var prop: String = {"emission": "emission_texture", "normal": "normal_texture", "rugosidade": "roughness_texture", "metal": "metallic_texture"}.get(str(item.get("canal", "albedo")), "albedo_texture")
				var tex: Texture2D = m.get(prop)
				if tex == null and item.has("criar"):
					# Material sem textura nesse canal (ex.: emblema só com relevo): cria uma lisa
					var cr: Array = item.criar
					var base_img := Image.create(int(cr[0]), int(cr[1]), false, Image.FORMAT_RGBA8)
					base_img.fill(_cor(cr[2]))
					tex = ImageTexture.create_from_image(base_img)
					tex.resource_name = "%s_%s" % [nome.validate_filename(), prop]
					m.set(prop, tex)
				if tex == null:
					continue
				var chave := "%d|%s" % [tex.get_instance_id(), JSON.stringify(item.ops)]
				if not feitos.has(chave):
					var img := tex.get_image().duplicate()
					if img.is_compressed():
						img.decompress()
					img.convert(Image.FORMAT_RGBA8)
					for op: Dictionary in item.ops:
						await _op(img, op)
					var nova := ImageTexture.create_from_image(img)
					nova.resource_name = tex.resource_name
					feitos[chave] = nova
					if pasta_fotos != "":
						DirAccess.make_dir_recursive_absolute(pasta_fotos)
						img.save_png("%s/marca_%s_%s.png" % [pasta_fotos, nome.validate_filename(), prop.left(3)])
					print("[MARCA] %s (%s): %d trocas" % [nome, prop, item.ops.size()])
				m.set(prop, feitos[chave])


func _op(img: Image, op: Dictionary) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if op.has("poligono"):
		var pts := PackedVector2Array()
		for p: Array in op.poligono:
			pts.append(Vector2(p[0] * w, p[1] * h))
		var cor := _cor(op.fundo)
		for y in h:
			for x in w:
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
					img.set_pixel(x, y, Color(cor, img.get_pixel(x, y).a))
		return
	var r: Array = op.get("r", [0, 0, 1, 1])
	var ret := Rect2i(int(r[0] * w), int(r[1] * h), maxi(1, int((r[2] - r[0]) * w)), maxi(1, int((r[3] - r[1]) * h)))
	var fundo = op.get("fundo", null)
	if fundo != null:
		var cf := _cor_auto(img, ret) if str(fundo) == "auto" else _cor(fundo)
		for y in range(ret.position.y, ret.end.y):
			for x in range(ret.position.x, ret.end.x):
				img.set_pixel(x, y, Color(cf, img.get_pixel(x, y).a) if not bool(op.get("alfa", false)) else Color(cf, 0.0))
	if not op.has("texto"):
		return
	var giro := int(op.get("girar", 0))
	var tam := ret.size if giro % 180 == 0 else Vector2i(ret.size.y, ret.size.x)
	var cob := await _texto(str(op.texto), tam, str(op.get("fonte", "sans")), float(op.get("altura", 0.8)))
	if bool(op.get("espelhar", false)):
		cob.flip_x()
	if bool(op.get("virar", false)):
		cob.flip_y()
	if giro == 90:
		cob.rotate_90(CLOCKWISE)
	elif giro == 270:
		cob.rotate_90(COUNTERCLOCKWISE)
	var ct := _cor(op.get("cor", [1, 1, 1]))
	for y in mini(cob.get_height(), ret.size.y):
		for x in mini(cob.get_width(), ret.size.x):
			var a := cob.get_pixel(x, y).a
			if a <= 0.0:
				continue
			var px := ret.position + Vector2i(x, y)
			if px.x >= w or px.y >= h:
				continue
			var c0 := img.get_pixel(px.x, px.y)
			if bool(op.get("alfa", false)):
				img.set_pixel(px.x, px.y, Color(ct, maxf(c0.a, a)))
			else:
				img.set_pixel(px.x, px.y, Color(c0.lerp(ct, a), c0.a))


## Cobertura do texto (branco com alfa) do tamanho pedido, centralizado e ajustado à caixa.
func _texto(texto: String, tam: Vector2i, fonte: String, altura: float) -> Image:
	var sv := SubViewport.new()
	sv.size = tam
	sv.transparent_bg = true
	sv.msaa_2d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	var f: Font
	match fonte:
		"racing":
			f = load("res://assets/fontes/RacingSansOne-Regular.ttf")
		"titulo":
			f = load("res://assets/fontes/Exo2-Italic.ttf")
		_:
			var sf := SystemFont.new()
			sf.font_names = PackedStringArray(["Arial Black", "Arial", "Bahnschrift"])
			sf.font_weight = 800
			f = sf
	var linhas := texto.split("\n")
	var tela := Control.new()
	tela.size = Vector2(tam)
	var desenho := func() -> void:
		var n := linhas.size()
		var alto := tam.y * altura / n
		for i in n:
			var fs := int(alto)
			var larg := f.get_string_size(linhas[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if larg > tam.x * 0.94:
				fs = int(fs * tam.x * 0.94 / larg)
				larg = f.get_string_size(linhas[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var asc := f.get_ascent(fs)
			var desc := f.get_descent(fs)
			var cy := tam.y * (0.5 - altura * 0.5) + alto * (i + 0.5)
			tela.draw_string(f, Vector2((tam.x - larg) * 0.5, cy + (asc - desc) * 0.5), linhas[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	tela.draw.connect(desenho)
	sv.add_child(tela)
	root.add_child(sv)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	sv.queue_free()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _cor(v) -> Color:
	var a: Array = v
	return Color(a[0], a[1], a[2])


## Cor mediana da borda do retângulo (para apagar sem deixar mancha).
static func _cor_auto(img: Image, r: Rect2i) -> Color:
	var cs: Array[Color] = []
	for x in range(r.position.x, r.end.x):
		cs.append(img.get_pixel(x, maxi(r.position.y - 1, 0)))
		cs.append(img.get_pixel(x, mini(r.end.y, img.get_height() - 1)))
	for y in range(r.position.y, r.end.y):
		cs.append(img.get_pixel(maxi(r.position.x - 1, 0), y))
		cs.append(img.get_pixel(mini(r.end.x, img.get_width() - 1), y))
	cs.sort_custom(func(a: Color, b: Color): return a.get_luminance() < b.get_luminance())
	return cs[cs.size() / 2]


## Transformação acumulada até a raiz (a cena não está na árvore).
static func _glob(n: Node, raiz: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != raiz.get_parent():
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## Fica só com os triângulos que estão inteiros dentro da caixa (vértices compactados).
static func _recortar(arr: Array, t: Transform3D, caixa: AABB) -> Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
	var dentro := PackedByteArray()
	dentro.resize(vs.size())
	for i in vs.size():
		dentro[i] = 1 if caixa.has_point(t * vs[i]) else 0
	var novo_de := PackedInt32Array()
	novo_de.resize(vs.size())
	novo_de.fill(-1)
	var usados := PackedInt32Array()
	var novo_idx := PackedInt32Array()
	for k in range(0, idx.size(), 3):
		if dentro[idx[k]] and dentro[idx[k + 1]] and dentro[idx[k + 2]]:
			for j in 3:
				var v := idx[k + j]
				if novo_de[v] < 0:
					novo_de[v] = usados.size()
					usados.append(v)
				novo_idx.append(novo_de[v])
	if novo_idx.is_empty():
		return []
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2]:
		if arr[k] == null:
			continue
		var fonte = arr[k]
		var passo := 4 if k == Mesh.ARRAY_TANGENT else 1
		var dest = fonte.duplicate()
		dest.resize(usados.size() * passo)
		for i in usados.size():
			for p in passo:
				dest[i * passo + p] = fonte[usados[i] * passo + p]
		out[k] = dest
	out[Mesh.ARRAY_INDEX] = novo_idx
	return out


func _reduzir(m: Material) -> Material:
	if not m is BaseMaterial3D:
		return m
	var b := m as BaseMaterial3D
	for p in ["albedo_texture", "normal_texture", "orm_texture", "roughness_texture", "metallic_texture", "emission_texture", "ao_texture"]:
		var tex = b.get(p)
		if tex is Texture2D:
			b.set(p, _tex(tex))
	return b


func _tex(t: Texture2D) -> Texture2D:
	if _texturas.has(t):
		return _texturas[t]
	var img := t.get_image()
	if img == null or maxi(img.get_width(), img.get_height()) <= TEX_MAX:
		_texturas[t] = t
		return t
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	var f: float = float(TEX_MAX) / maxi(img.get_width(), img.get_height())
	img.resize(int(img.get_width() * f), int(img.get_height() * f), Image.INTERPOLATE_LANCZOS)
	var nova := ImageTexture.create_from_image(img)
	nova.resource_name = t.resource_name
	_texturas[t] = nova
	return nova


## Fotos: do olho do piloto (config "olho") e de cima, para conferir o recorte.
func _fotos(no: Node3D, c: Dictionary, pasta: String) -> void:
	DirAccess.make_dir_recursive_absolute(pasta)
	root.size = Vector2i(1600, 900)
	var mundo := Node3D.new()
	root.add_child(mundo)
	mundo.add_child(no)
	var luz := DirectionalLight3D.new()
	luz.rotation_degrees = Vector3(-40, 20, 0)
	mundo.add_child(luz)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.6, 0.75)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	mundo.add_child(env)
	var cam := Camera3D.new()
	mundo.add_child(cam)
	cam.current = true
	var o: Array = c.get("olho", [-0.37, 0.6, 0.2])
	cam.fov = 70
	cam.near = 0.02
	cam.position = Vector3(o[0], o[1], o[2])
	cam.rotation_degrees = Vector3(-8, 0, 0)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(pasta + "/olho.png")
	# Do banco do carona, olhando o painel dele e o console
	cam.position = Vector3(-o[0], o[1], o[2])
	cam.rotation_degrees = Vector3(-22, 12, 0)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png(pasta + "/carona.png")
