extends SceneTree
## Conferência: lista, para cada carro ativo, os nós e materiais do modelo com cara de farol/lanterna
## (pelo nome), com a caixa de cada um no espaço do modelo. Uso:
##   Godot --headless --path . -s tools/farois/listar.gd

const CHAVES := ["light", "lamp", "farol", "lantern", "brake", "signal", "blinker", "indicator", "emiss", "led", "beam", "bulb", "lens", "reflector"]


func _init() -> void:
	var dados: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/veiculos.json"))
	var lista: Array = dados.veiculos if dados is Dictionary and dados.has("veiculos") else (dados if dados is Array else (dados as Dictionary).values())
	for v: Dictionary in lista:
		if not bool(v.get("ativo", true)):
			continue
		var cena := load(str(v.modelo)) as PackedScene
		if cena == null:
			print("== ", v.id, " (sem modelo)")
			continue
		var modelo: Node3D = cena.instantiate()
		var total := AABB()
		var primeiro := true
		var achados: Array = []
		for n in modelo.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh == null:
				continue
			var xf := Transform3D.IDENTITY
			var sobe: Node = mi
			while sobe != modelo:
				xf = (sobe as Node3D).transform * xf
				sobe = sobe.get_parent()
			var cx := xf * mi.mesh.get_aabb()
			total = cx if primeiro else total.merge(cx)
			primeiro = false
			var caminho := str(modelo.get_path_to(mi)).to_lower()
			for s in mi.mesh.get_surface_count():
				var m := mi.get_active_material(s)
				var nome_m := (m.resource_name if m else "").to_lower()
				var emite := m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled
				var bate := emite
				for k: String in CHAVES:
					if k in caminho.get_file() or k in nome_m:
						bate = true
				if not bate:
					continue
				var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				if verts.is_empty():
					continue
				var c := AABB(xf * verts[0], Vector3.ZERO)
				for p in verts:
					c = c.expand(xf * p)
				achados.append("   %-44s mat %-26s%s centro %s tam %s" % [str(modelo.get_path_to(mi)).right(44), nome_m.left(26), " EMITE" if emite else "", str(c.get_center().snapped(Vector3.ONE * 0.01)), str(c.size.snapped(Vector3.ONE * 0.01))])
		print("== %s  caixa pos %s tam %s" % [v.id, str(total.position.snapped(Vector3.ONE * 0.01)), str(total.size.snapped(Vector3.ONE * 0.01))])
		for a: String in achados:
			print(a)
		modelo.free()
	quit()
