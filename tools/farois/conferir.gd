extends Node
## Conferência dos faróis de todos os carros ativos: monta cada carro, liga os faróis e mostra o que
## acendeu — as peças do modelo (farol / lanterna de verdade) ou, na falta delas, onde ficaram as lentes.
##   Godot --headless --path . res://tools/farois/conferir.tscn


func _ready() -> void:
	var dados: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/veiculos.json"))
	for d: Dictionary in dados.veiculos:
		if not bool(d.get("ativo", true)):
			continue
		var v := Veiculo.new()
		v.dados = d
		v.freeze = true
		add_child(v)
		v.farois(true)
		var c := v.caixa_corpo
		var frente: Array = []
		var tras: Array = []
		for p: Array in v._farois_pecas:
			var mi := p[0] as MeshInstance3D
			var z := ((v.global_transform.affine_inverse() * mi.global_transform) * mi.mesh.get_aabb()).get_center().z
			(frente if z < c.get_center().z else tras).append(String(mi.name).left(34))
		var lentes: Array = []
		var facho := ""
		for f in v._farois.get_children():
			if f is MeshInstance3D:
				lentes.append(str((f as MeshInstance3D).position.snapped(Vector3.ONE * 0.01)))
			elif f is SpotLight3D:
				facho = str((f as SpotLight3D).position.snapped(Vector3.ONE * 0.01))
		print("== %-14s caixa z %.2f..%.2f y %.2f..%.2f  facho %s" % [d.id, c.position.z, c.end.z, c.position.y, c.end.y, facho])
		print("     farol: %s" % [", ".join(frente) if not frente.is_empty() else "(sem peça)"])
		print("     lanterna: %s" % [", ".join(tras) if not tras.is_empty() else "(sem peça)"])
		if not lentes.is_empty():
			print("     lentes postas: %s" % ", ".join(lentes))
		v.free()
	get_tree().quit()
