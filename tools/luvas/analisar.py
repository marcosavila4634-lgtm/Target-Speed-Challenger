# Blender: relatório dos ossos da mão de um avatar e das partes soltas de uma luva.
# Uso: blender -b -P tools/luvas/analisar.py -- <avatar.glb> <luva.glb>
import bpy, sys, bmesh
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=args[0])
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
print("ARMATURE", arm.name, "escala", arm.matrix_world.to_scale())
for b in arm.data.bones:
    if "Hand" in b.name and ("Right" in b.name or b.name.startswith("RightHand")):
        h = arm.matrix_world @ b.head_local
        t = arm.matrix_world @ b.tail_local
        print("OSSO", b.name, "cabeca", tuple(round(x, 3) for x in h), "ponta", tuple(round(x, 3) for x in t))
for o in bpy.data.objects:
    if o.type == 'MESH':
        print("MALHA_AVATAR", o.name, len(o.data.vertices), [g.name for g in o.vertex_groups][:3])
bpy.ops.object.select_all(action='DESELECT')
antes = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=args[1])
for o in set(bpy.data.objects) - antes:
    if o.type != 'MESH':
        continue
    mw = o.matrix_world
    bm = bmesh.new(); bm.from_mesh(o.data)
    # partes soltas
    vistos = set(); partes = []
    for v in bm.verts:
        if v.index in vistos: continue
        pilha = [v]; grupo = []
        vistos.add(v.index)
        while pilha:
            a = pilha.pop(); grupo.append(a)
            for e in a.link_edges:
                w = e.other_vert(a)
                if w.index not in vistos:
                    vistos.add(w.index); pilha.append(w)
        pts = [mw @ x.co for x in grupo]
        mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
        mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
        partes.append((len(grupo), mn, mx))
    partes.sort(key=lambda p: -p[0])
    print("LUVA", o.name, "verts", len(bm.verts), "partes", len(partes))
    for n, mn, mx in partes[:6]:
        print("   parte", n, "min", tuple(round(x, 3) for x in mn), "max", tuple(round(x, 3) for x in mx))
