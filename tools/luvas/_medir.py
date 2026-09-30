import bpy, sys
import numpy as np
a = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
for o in bpy.data.objects:
    if o.type != 'MESH' or o.name.lower().startswith("icosphere"):
        continue
    p = np.array([list(o.matrix_world @ v.co) for v in o.data.vertices])
    for nome, sel in (("x<0", p[:, 0] < 0), ("x>0", p[:, 0] >= 0)):
        q = p[sel]
        if len(q) == 0: continue
        c = q.mean(axis=0)
        u, s, vt = np.linalg.svd(q - c, full_matrices=False)
        print(nome, "n", len(q), "min", q.min(0).round(4), "max", q.max(0).round(4), "sv", (s / np.sqrt(len(q))).round(4))
        for k in range(3):
            print("   eixo", k, vt[k].round(3))
        # perfil ao longo de y e z: largura em x por fatia
        for eixo in (1, 2):
            lo, hi = q[:, eixo].min(), q[:, eixo].max()
            linha = []
            for f in range(8):
                m = (q[:, eixo] >= lo + (hi - lo) * f / 8) & (q[:, eixo] < lo + (hi - lo) * (f + 1) / 8)
                linha.append(int(m.sum()))
            print("   verts por fatia no eixo", "xyz"[eixo], linha)
