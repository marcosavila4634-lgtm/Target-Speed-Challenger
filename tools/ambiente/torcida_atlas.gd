extends SceneTree
## Gera o atlas de "cartões" da torcida do Drag a partir do modelo Low Detail Animated Crowd
## (18 pessoas com esqueleto Mixamo): cada pessoa em 3 poses (em pé, um braço erguido, os dois
## erguidos), vista de frente, só a cor (sem luz) e fundo transparente. Uma coluna por pessoa, uma
## linha por pose; os pés no pé da célula e o quadril no meio dela.
## Uso: godot -s tools/ambiente/torcida_atlas.gd   (precisa de janela: renderiza de verdade)

const MODELO := "res://assets/dragracing ambiente/pessoas/low-detail-animated-crowd/low_detail_animated_crowd.glb"
const SAIDA := "res://assets/drag/torcida_atlas.png"
const CELULA := Vector2i(128, 256)
const ALTURA_M := 2.4   # altura da célula em metros (a largura é a metade)

## Direção de cada osso no mundo (pessoa de frente para +Z; o lado direito dela fica em -X),
## na ordem de pai para filho.
const POSES := [
	{   # em pé, braços caídos
		"RightUpLeg": Vector3(-0.06, -1, 0), "RightLeg": Vector3(0, -1, -0.04),
		"LeftUpLeg": Vector3(0.06, -1, 0), "LeftLeg": Vector3(0, -1, -0.04),
		"RightArm": Vector3(-0.22, -1, 0.05), "RightForeArm": Vector3(-0.08, -1, 0.3),
		"LeftArm": Vector3(0.22, -1, 0.05), "LeftForeArm": Vector3(0.08, -1, 0.3),
	},
	{   # um braço erguido
		"RightUpLeg": Vector3(-0.06, -1, 0), "RightLeg": Vector3(0, -1, -0.04),
		"LeftUpLeg": Vector3(0.06, -1, 0), "LeftLeg": Vector3(0, -1, -0.04),
		"RightArm": Vector3(-0.22, -1, 0.05), "RightForeArm": Vector3(-0.08, -1, 0.3),
		"LeftArm": Vector3(0.45, 1, 0.12), "LeftForeArm": Vector3(0.12, 1, 0.08),
	},
	{   # os dois braços erguidos
		"RightUpLeg": Vector3(-0.1, -1, 0), "RightLeg": Vector3(0, -1, -0.04),
		"LeftUpLeg": Vector3(0.1, -1, 0), "LeftLeg": Vector3(0, -1, -0.04),
		"RightArm": Vector3(-0.5, 1, 0.12), "RightForeArm": Vector3(-0.2, 1, 0.08),
		"LeftArm": Vector3(0.5, 1, 0.12), "LeftForeArm": Vector3(0.2, 1, 0.08),
	},
]


func _init() -> void:
	var cena: Node3D = (load(MODELO) as PackedScene).instantiate()
	root.add_child(cena)
	for ap: AnimationPlayer in cena.find_children("*", "AnimationPlayer", true, false):
		ap.active = false
	await process_frame
	var sv := SubViewport.new()
	sv.size = CELULA
	sv.transparent_bg = true
	sv.own_world_3d = true
	sv.msaa_3d = Viewport.MSAA_4X
	sv.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ALTURA_M
	cam.position = Vector3(0, ALTURA_M * 0.5, 10)
	sv.add_child(cam)
	cam.current = true
	var alvo := MeshInstance3D.new()
	sv.add_child(alvo)
	var esqueletos := cena.find_children("*", "Skeleton3D", true, false)
	var atlas := Image.create(CELULA.x * esqueletos.size(), CELULA.y * POSES.size(), false, Image.FORMAT_RGBA8)
	for i in esqueletos.size():
		var s := esqueletos[i] as Skeleton3D
		var mi := s.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		for p in POSES.size():
			s.reset_bone_poses()
			for osso: String in POSES[p]:
				_apontar(s, osso, POSES[p][osso])
			await process_frame   # o esqueleto só aplica a pose no quadro seguinte
			var malha := mi.bake_mesh_from_current_skeleton_pose()
			var t := mi.global_transform
			var ab := t * malha.get_aabb()
			var quadril := s.global_transform * s.get_bone_global_pose(_osso(s, "Hips")).origin
			alvo.mesh = malha
			alvo.material_override = mi.get_active_material(0)
			alvo.global_transform = Transform3D(t.basis, t.origin - Vector3(quadril.x, ab.position.y, quadril.z))
			for k in 3:
				await RenderingServer.frame_post_draw
			var img := sv.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(Vector2i.ZERO, CELULA), Vector2i(i * CELULA.x, p * CELULA.y))
		print("[TORCIDA] pessoa %d" % i)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAIDA.get_base_dir()))
	atlas.save_png(ProjectSettings.globalize_path(SAIDA))
	print("[TORCIDA] gravado %s (%dx%d)" % [SAIDA, atlas.get_width(), atlas.get_height()])
	quit()


## Índice do osso Mixamo pelo nome curto ("LeftArm" acha "mixamorig_LeftArm_011").
func _osso(s: Skeleton3D, curto: String) -> int:
	for i in s.get_bone_count():
		if s.get_bone_name(i).contains("_" + curto + "_"):
			return i
	return -1


## Gira o osso para o eixo dele (+Y, ao longo do osso) apontar para `dir` no mundo.
func _apontar(s: Skeleton3D, curto: String, dir: Vector3) -> void:
	var b := _osso(s, curto)
	if b < 0:
		return
	var g := s.get_bone_global_pose(b)
	var atual := g.basis.y.normalized()
	var desejado := (s.global_transform.basis.inverse() * dir).normalized()
	var q := Quaternion(atual, desejado)
	s.set_bone_global_pose(b, Transform3D(Basis(q) * g.basis, g.origin))
