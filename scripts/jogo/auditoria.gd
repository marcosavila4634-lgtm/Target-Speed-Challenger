extends RefCounted
## Varredura de peças flutuando (pedido do dono: nada sem sustentação). TSC_FLUTUANDO=1 monta a etapa,
## junta a caixa (AABB no mundo) de cada peça visível — malhas soltas e cada instância dos MultiMesh —
## e marca como APOIADA a que:
##   - encosta no terreno ou na água (algum ponto da base abaixo do chão + folga), ou
##   - tem piso com colisão logo embaixo (raio de 1,4 m para baixo a partir da base: pista, laje, muro), ou
##   - encosta em outra peça apoiada (cresce por vizinhança: placa no poste, lâmpada na viga...).
## O que sobra é listado por grupo (caminho do nó), com quantas peças, a altura livre embaixo e uma
## posição de exemplo. Ficam de fora: carros, partículas, textos, o que voa de propósito (balões,
## dirigíveis, helicóptero, drone, pterossauros, meteoros), plantas (MultiMesh grandes) e malhas enormes
## (terreno, estrada, céu), que não servem de ponte entre peças mas contam como piso pelo raio.

const CELULA := 6.0
const FOLGA := 0.8
const VOA := ["Teleferico", "Balao", "Dirigivel", "Helicoptero", "Drone", "Ptero", "Meteoro", "Ceu", "Nuvem", "Bruma", "Neve", "Chuva", "Aurora", "Checkpoint", "Fantasma", "Rotor"]


static func rodar(raiz: Node, terreno: Terreno, espaco: PhysicsDirectSpaceState3D, nivel_agua: float, etiqueta: String) -> void:
	var itens: Array = []   # [AABB, caminho, grande, transformação inversa e caixa local (só das grandes de MultiMesh)]
	_coletar(raiz, raiz, itens)
	var n := itens.size()
	var apoiado := PackedByteArray()
	apoiado.resize(n)
	var grade := {}
	for i in n:
		var cx: AABB = itens[i][0]
		if itens[i][2]:
			apoiado[i] = 1
			continue
		var a := Vector3i((cx.position / CELULA).floor())
		var b := Vector3i((cx.end / CELULA).floor())
		for x in range(a.x, b.x + 1):
			for y in range(a.y, b.y + 1):
				for z in range(a.z, b.z + 1):
					var k := Vector3i(x, y, z)
					if not grade.has(k):
						grade[k] = []
					(grade[k] as Array).append(i)
		if _no_chao(cx, terreno, espaco, nivel_agua):
			apoiado[i] = 1
	# Propaga o apoio pelos vizinhos que se encostam
	var fila: Array = []
	for i in n:
		if apoiado[i] == 1 and not itens[i][2]:
			fila.append(i)
	while not fila.is_empty():
		var i: int = fila.pop_back()
		var cx: AABB = (itens[i][0] as AABB).grow(FOLGA)
		var a := Vector3i((cx.position / CELULA).floor())
		var b := Vector3i((cx.end / CELULA).floor())
		for x in range(a.x, b.x + 1):
			for y in range(a.y, b.y + 1):
				for z in range(a.z, b.z + 1):
					for j: int in grade.get(Vector3i(x, y, z), []):
						if apoiado[j] == 0 and cx.intersects(itens[j][0]):
							apoiado[j] = 1
							fila.append(j)
	# Peças encostadas numa peça ENORME (muralha, laje comprida): a caixa alinhada aos eixos de uma peça dessas
	# cobre meio mapa, então o teste é na caixa dela mesma (girada); depois propaga de novo
	var grandes: Array = []
	for i in n:
		if itens[i][2] and (itens[i] as Array).size() > 3:
			grandes.append(itens[i])
	for i in n:
		if apoiado[i] == 1:
			continue
		var cx: AABB = itens[i][0]
		for g: Array in grandes:
			if not (g[0] as AABB).grow(FOLGA).intersects(cx):
				continue
			var inv: Transform3D = g[3]
			var loc: AABB = g[4]
			var toca := false
			for k in 9:
				var q := cx.get_center() if k == 8 else cx.get_endpoint(k)
				if loc.has_point(inv * q):
					toca = true
					break
			if toca:
				apoiado[i] = 1
				fila.append(i)
				break
	while not fila.is_empty():
		var i: int = fila.pop_back()
		var cx: AABB = (itens[i][0] as AABB).grow(FOLGA)
		var a := Vector3i((cx.position / CELULA).floor())
		var b := Vector3i((cx.end / CELULA).floor())
		for x in range(a.x, b.x + 1):
			for y in range(a.y, b.y + 1):
				for z in range(a.z, b.z + 1):
					for j: int in grade.get(Vector3i(x, y, z), []):
						if apoiado[j] == 0 and cx.intersects(itens[j][0]):
							apoiado[j] = 1
							fila.append(j)
	var grupos := {}
	for i in n:
		if apoiado[i] == 1:
			continue
		var cx: AABB = itens[i][0]
		var c := cx.get_center()
		var livre := cx.position.y - maxf(terreno.altura_em(c.x, c.z), nivel_agua)
		var g: String = itens[i][1]
		if not grupos.has(g):
			grupos[g] = [0, livre, c, cx.size]
		grupos[g][0] += 1
		if livre > float(grupos[g][1]):
			grupos[g][1] = livre
			grupos[g][2] = c
			grupos[g][3] = cx.size
	if OS.get_environment("TSC_FLUTUANDO") == "2":
		# Depuração: as 12 peças sem apoio mais baixas (em relação ao chão) de cada grupo
		var vistos := {}
		for i in n:
			if apoiado[i] == 1:
				continue
			var cx: AABB = itens[i][0]
			var c := cx.get_center()
			var livre := cx.position.y - terreno.altura_em(c.x, c.z)
			if livre < 3.0 and int(vistos.get(itens[i][1], 0)) < 4:
				vistos[itens[i][1]] = int(vistos.get(itens[i][1], 0)) + 1
				print("[FLUTUA?] %s pos %s tam %s chão %.1f livre %.2f" % [itens[i][1], str(cx.position.snapped(Vector3.ONE * 0.1)), str(cx.size.snapped(Vector3.ONE * 0.1)), terreno.altura_em(c.x, c.z), livre])
	var nomes := grupos.keys()
	nomes.sort()
	print("[FLUTUA] %s: %d peças, %d sem apoio em %d grupos" % [etiqueta, n, n - apoiado.count(1), nomes.size()])
	for g: String in nomes:
		var d: Array = grupos[g]
		print("[FLUTUA]   %4d x  %5.1f m no ar  tam %s  em %s  %s" % [d[0], d[1], str((d[3] as Vector3).snapped(Vector3.ONE * 0.1)), str((d[2] as Vector3).snapped(Vector3.ONE)), g])


static func _no_chao(cx: AABB, terreno: Terreno, espaco: PhysicsDirectSpaceState3D, nivel_agua: float) -> bool:
	var y0 := cx.position.y
	var tol := 0.7 + 0.03 * maxf(cx.size.x, cx.size.z)
	var pontos: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.15, 0.15), Vector2(0.85, 0.15), Vector2(0.15, 0.85), Vector2(0.85, 0.85)]
	for q in pontos:
		var x := cx.position.x + cx.size.x * q.x
		var z := cx.position.z + cx.size.z * q.y
		if y0 <= maxf(terreno.altura_em(x, z), nivel_agua) + tol:
			return true
	for q in pontos:
		var de := Vector3(cx.position.x + cx.size.x * q.x, y0 + 0.2, cx.position.z + cx.size.z * q.y)
		var par := PhysicsRayQueryParameters3D.create(de, de + Vector3.DOWN * 1.6, 1)
		if not espaco.intersect_ray(par).is_empty():
			return true
	# Pendurada: estrutura com colisão logo acima do topo (pêndulo no pórtico, lâmpada na viga)
	var topo := Vector3(cx.position.x + cx.size.x * 0.5, cx.end.y - 0.2, cx.position.z + cx.size.z * 0.5)
	if not espaco.intersect_ray(PhysicsRayQueryParameters3D.create(topo, topo + Vector3.UP * 2.2, 1)).is_empty():
		return true
	# Colada de lado numa estrutura com colisão (lâmpada na lateral da laje, placa no muro): só peças pequenas
	if cx.get_longest_axis_size() < 6.0:
		var meio := cx.get_center()
		for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
			var alcance := absf(dir.dot(cx.size)) * 0.5 + 1.3
			if not espaco.intersect_ray(PhysicsRayQueryParameters3D.create(meio, meio + dir * alcance, 1)).is_empty():
				return true
	return false


static func _coletar(no: Node, raiz: Node, itens: Array) -> void:
	if no is Veiculo or no is GPUParticles3D or no is Label3D or no is Camera3D or no is CanvasItem:
		return
	if no is Node3D and not (no as Node3D).visible:
		return
	var nome := str(no.name)
	for v: String in VOA:
		if nome.contains(v):
			return
	if no is Alvo and (no as Alvo).movel:
		return
	if no is MeshInstance3D and (no as MeshInstance3D).mesh:
		var mi := no as MeshInstance3D
		if mi.mesh is QuadMesh or mi.mesh is PlaneMesh:
			pass   # planos (placas de aceleração, luzes de chão): contam, mas são finos
		var cx := mi.global_transform * mi.get_aabb()
		itens.append([cx, _caminho(no, raiz), maxf(cx.size.x, cx.size.z) > 90.0 or cx.size.y > 200.0])
	elif no is MultiMeshInstance3D and (no as MultiMeshInstance3D).multimesh and (no as MultiMeshInstance3D).multimesh.mesh:
		var mmi := no as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm.instance_count <= 2500 and not (mmi.material_override is ShaderMaterial and (mmi.material_override as ShaderMaterial).shader and (mmi.material_override as ShaderMaterial).shader.resource_path.contains("folhagem")):
			var base := mm.mesh.get_aabb()
			var cam := _caminho(no, raiz)
			for i in mm.instance_count:
				var xf := mmi.global_transform * mm.get_instance_transform(i)
				var cx := xf * base
				if maxf(cx.size.x, cx.size.z) > 90.0 or cx.size.y > 200.0:
					var esc := xf.basis.get_scale()
					var loc := AABB(base.position - Vector3.ONE * FOLGA / esc, base.size + Vector3.ONE * 2.0 * FOLGA / esc)
					itens.append([cx, cam, true, xf.affine_inverse(), loc])
				else:
					itens.append([cx, cam, false])
	for f in no.get_children():
		_coletar(f, raiz, itens)


## Caminho curto do nó (até 5 níveis a partir da raiz), sem os números que o motor põe nos nomes.
static func _caminho(no: Node, raiz: Node) -> String:
	var partes: Array = []
	var n := no
	while n and n != raiz:
		var nome := str(n.name)
		if nome.begins_with("@"):
			nome = nome.split("@")[1]
		partes.push_front(nome + ("[" + n.get_script().resource_path.get_file().get_basename() + "]" if n.get_script() and partes.is_empty() == false and nome.begins_with("Node") else ""))
		n = n.get_parent()
	if partes.size() > 5:
		partes = partes.slice(0, 5)
	return "/".join(partes)


## TSC_FLUTUANDO=dinos: lista os dinossauros com os pés longe do que há embaixo — o terreno ou um piso com
## colisão (laje, pista, passarela). Mede pelo osso de pé mais baixo de cada esqueleto (a origem do nó não
## serve: cada modelo tem a sua). Folga normal: o tornozelo fica um pouco acima da sola.
static func dinos(raiz: Node, terreno: Terreno, espaco: PhysicsDirectSpaceState3D, etiqueta: String) -> void:
	var total := 0
	var ruins := 0
	for no in raiz.find_children("*", "Skeleton3D", true, false):
		var esq := no as Skeleton3D
		if not esq.is_visible_in_tree():
			continue
		var dono: Node = esq
		var especie := ""
		while dono and dono != raiz and especie == "":
			var nome := str(dono.name)
			if nome.begins_with("@"):
				nome = nome.split("@")[1]
			if DinosParque.ESPECIES.has(nome.rstrip("0123456789")):
				especie = nome
			dono = dono.get_parent()
		if especie == "":
			continue
		var pe := Vector3.INF
		var alto := -INF
		for b in esq.get_bone_count():
			var q := esq.global_transform * esq.get_bone_global_pose(b).origin
			alto = maxf(alto, q.y)
			var nb := esq.get_bone_name(b).to_lower()
			if ("foot" in nb or "ankle" in nb or "toe" in nb) and not "end" in nb and q.y < pe.y:
				pe = q
		if pe == Vector3.INF:
			continue
		total += 1
		var piso := terreno.altura_em(pe.x, pe.z)
		var r := espaco.intersect_ray(PhysicsRayQueryParameters3D.create(pe + Vector3.UP * 2.0, pe + Vector3.DOWN * 80.0, 1))
		if not r.is_empty():
			piso = maxf(piso, (r.position as Vector3).y)
		var livre := pe.y - piso
		var tam := alto - pe.y
		if livre > 0.25 + tam * 0.06 or livre < -(0.4 + tam * 0.1):
			ruins += 1
			print("[DINO-AR] %-13s %5.2f m %-9s (altura %.1f)  pé %s  terreno %.1f  em %s" % [especie, absf(livre), "no ar" if livre > 0.0 else "enterrado", tam, str(pe.snapped(Vector3.ONE * 0.1)), terreno.altura_em(pe.x, pe.z), _caminho(esq, raiz).left(70)])
	print("[DINO-AR] %s: %d dinossauros, %d fora do chão" % [etiqueta, total, ruins])
