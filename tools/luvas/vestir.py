# Blender: veste uma luva (modelo parado, mão aberta) nas duas mãos de um avatar Mixamo e liga a
# luva aos ossos da mão/dedos (pesos automáticos), para ela fechar junto com os dedos no jogo.
# Saída: .glb só com o esqueleto do avatar e as luvas (o jogo prende no esqueleto do avatar).
#
# Uso: blender -b -P tools/luvas/vestir.py -- <avatar.glb> <luva.glb> <saida.glb> <fotos_png> [opções json]
# Opções: {"so_direita": true}  a luva tem só a mão direita (a esquerda sai espelhada)
#         {"inverter_palma": true} troca palma/costas;  {"inverter_dedos": true} troca pulso/dedos
#         {"folga": 1.12} luva maior que a mão;  {"comprimento": 1.3} quanto a luva passa do pulso
import bpy, sys, json, math
import numpy as np
from mathutils import Vector, Matrix

a = sys.argv[sys.argv.index("--") + 1:]
avatar, luva, saida, fotos = a[0], a[1], a[2], a[3]
op = json.loads(a[4]) if len(a) > 4 else {}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=avatar)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
corpo = [o for o in bpy.data.objects if o.type == 'MESH']


def osso(nome):
    for b in arm.data.bones:
        if b.name.split("_")[0] == nome:
            return b
    return None


def pos(nome):
    return arm.matrix_world @ osso(nome).head_local


def quadro_mao(lado):
    """Pulso, direção dos dedos (L), do polegar (T), normal (N), comprimento e largura da mão."""
    w = pos(lado + "Hand")
    m3, m2 = pos(lado + "HandMiddle3"), pos(lado + "HandMiddle2")
    m = pos(lado + "HandMiddle4") if osso(lado + "HandMiddle4") else None
    if m is None or (m - m3).length > 0.08 or (m - m3).length < 0.003:   # ponta corrompida no arquivo
        m = m3 + (m3 - m2)
    ind, mind = pos(lado + "HandIndex1"), pos(lado + "HandPinky1")
    L = (m - w).normalized()
    T = (ind - mind)
    T = (T - L * T.dot(L)).normalized()
    return w, m, L, T, L.cross(T), (m - w).length, (ind - mind).length


# ------------------------------------------------------------------ luva
antes = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=luva)
novos = [o for o in set(bpy.data.objects) - antes if o.type == "MESH" and not o.name.lower().startswith(("icosphere", "sphere", "plane", "cube"))]
for o in set(bpy.data.objects) - antes:
    if o.type == "MESH" and o not in novos:
        bpy.data.objects.remove(o, do_unlink=True)
for o in novos:
    o.hide_set(False)
    o.hide_select = False
# Junta tudo numa malha só, com as transformações aplicadas
bpy.ops.object.select_all(action='DESELECT')
for o in novos:
    o.select_set(True)
bpy.context.view_layer.objects.active = novos[0]
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.join()
fonte = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(set(bpy.data.objects) - antes):
    if o != fonte and o.name in bpy.data.objects:
        bpy.data.objects.remove(o, do_unlink=True)


def pontos(o):
    return np.array([list(v.co) for v in o.data.vertices])


def separar_pares(o):
    """Luva com par: copia a malha e apaga metade em X em cada cópia (esquerda = x menor)."""
    import bmesh
    p = pontos(o)
    cx = (p[:, 0].min() + p[:, 0].max()) * 0.5
    outro = o.copy()
    outro.data = o.data.copy()
    bpy.context.collection.objects.link(outro)
    for obj, fora in ((o, lambda x: x > cx), (outro, lambda x: x <= cx)):
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if fora(v.co.x)], context='VERTS')
        bm.to_mesh(obj.data)
        bm.free()
    return o, outro   # (x menor, x maior)


def eixos(p):
    """PCA: comprimento (L), largura (T), espessura (N) e o centro."""
    c = p.mean(axis=0)
    u, s, vt = np.linalg.svd(p - c, full_matrices=False)
    return c, vt[0], vt[1], vt[2]


def ponta_dos_dedos(p, c, L, T):
    """Sinal de L que aponta para os dedos: na ponta dos dedos a fatia tem vários grupos separados."""
    proj = (p - c) @ L
    lt = (p - c) @ T
    melhor = 1.0
    grupos = {}
    for sinal in (1.0, -1.0):
        x = proj * sinal
        fatia = lt[x > x.max() - (x.max() - x.min()) * 0.12]
        if len(fatia) < 5:
            grupos[sinal] = 0
            continue
        f = np.sort(fatia)
        gap = (f.max() - f.min()) * 0.06
        grupos[sinal] = 1 + int(np.sum(np.diff(f) > gap))
    return 1.0 if grupos[1.0] >= grupos[-1.0] else -1.0


def lado_polegar(p, c, L, T):
    """Sinal de T do lado do polegar: no meio da luva, o lado que se estende mais."""
    proj = (p - c) @ L
    lt = (p - c) @ T
    meio = lt[np.abs(proj) < (proj.max() - proj.min()) * 0.2]
    return 1.0 if abs(meio.max()) > abs(meio.min()) else -1.0


def vestir(o, lado, espelhar):
    w, m, Lh, Th, Nh, comp, larg = quadro_mao(lado)
    if espelhar:
        o.data.transform(Matrix.Scale(-1.0, 4, Vector((1, 0, 0))))
        o.data.flip_normals()
    p = pontos(o)
    c, Lg, Tg, Ng = eixos(p)
    if "eixo_dedos" in op:   # direção dos dedos no arquivo da luva (mais confiável que a heurística)
        sl = 1.0 if np.dot(Lg, np.array(op["eixo_dedos"], dtype=float)) > 0 else -1.0
    else:
        sl = ponta_dos_dedos(p, c, Lg, Tg)
    sl *= -1.0 if op.get("inverter_dedos") else 1.0
    Lg = Lg * sl
    Tg = Tg * lado_polegar(p, c, Lg, Tg)
    Ng = np.cross(Lg, Tg)
    if op.get("inverter_palma"):   # palma e costas trocadas: espelha a luva pelo plano da mão
        p = p - 2.0 * np.outer((p - c) @ Ng, Ng)
        o.data.flip_normals()
    # Medidas da luva
    pl, pt = (p - c) @ Lg, (p - c) @ Tg
    comp_g, larg_g = pl.max() - pl.min(), pt.max() - pt.min()
    # Base da luva -> base da mão (matriz 3x3 com colunas L, T, N)
    G = np.column_stack([Lg, Tg, Ng])
    H = np.column_stack([list(Lh), list(Th), list(Nh)])
    if np.linalg.det(G) < 0:
        G[:, 2] *= -1
    folga = float(op.get("folga", 1.12))
    alongar = float(op.get("comprimento", 1.3))
    sL = comp * alongar / comp_g
    sT = larg * 1.35 * folga / larg_g
    S = np.diag([sL, sT, sT])
    R = H @ S @ G.T
    # Ponta dos dedos da luva na ponta do dedo médio
    ponta_g = c + Lg * pl.max()
    alvo = np.array(list(m + Lh * 0.008))
    novo = (p - ponta_g) @ R.T + alvo
    for i, v in enumerate(o.data.vertices):
        v.co = Vector(novo[i])
    o.data.update()
    o.name = "Luva" + lado
    print("[LUVA] %s: mão comp %.3f larg %.3f | luva comp %.4f larg %.4f | escala L %.2f T %.2f | pulso %s ponta %s | luva min %s max %s" % (lado, comp, larg, comp_g, larg_g, sL, sT, tuple(round(x, 3) for x in w), tuple(round(x, 3) for x in m), novo.min(0).round(3), novo.max(0).round(3)))


if op.get("so_direita"):
    d = fonte
    e = d.copy()
    e.data = d.data.copy()
    bpy.context.collection.objects.link(e)
    vestir(d, "Right", False)
    vestir(e, "Left", True)
else:
    menor, maior = separar_pares(fonte)
    # Qual é a direita: a que tem o polegar do lado certo depois de vestida; aqui pela posição
    dir_x = maior if not op.get("trocar_pares") else menor
    esq_x = menor if not op.get("trocar_pares") else maior
    vestir(dir_x, "Right", False)
    vestir(esq_x, "Left", False)

# ------------------------------------------------------------------ pesos (só ossos da mão)
# Pesos por distância aos segmentos dos ossos (os automáticos do Blender falham em malha densa):
# cada vértice vai para os 2 segmentos mais próximos. Ponta de dedo corrompida no arquivo
# (osso "4" na origem) é estimada pelas falanges anteriores.
luvas = [o for o in bpy.data.objects if o.name.startswith("Luva")]


def segmentos(lado):
    segs = []   # (nome do osso, a, b)
    segs.append((osso(lado + "Hand").name, pos(lado + "Hand"), pos(lado + "HandMiddle1")))
    for dedo in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        cad = [pos(lado + "Hand%s%d" % (dedo, k)) for k in (1, 2, 3)]
        p4 = osso(lado + "Hand%s4" % dedo)
        tip = arm.matrix_world @ p4.head_local if p4 else None
        if tip is None or (tip - cad[2]).length > 0.08 or (tip - cad[2]).length < 0.003:
            tip = cad[2] + (cad[2] - cad[1])
        pts = cad + [tip]
        for k in range(3):
            segs.append((osso(lado + "Hand%s%d" % (dedo, k + 1)).name, pts[k], pts[k + 1]))
    return segs


def dist_seg(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


for o in luvas:
    lado = o.name.replace("Luva", "")
    segs = segmentos(lado)
    grupos = {n: o.vertex_groups.new(name=n) for n, _, _ in segs}
    for v in o.data.vertices:
        d = sorted(((dist_seg(v.co, a, b), n) for n, a, b in segs))[:2]
        w0, w1 = 1.0 / (d[0][0] + 0.004) ** 4, 1.0 / (d[1][0] + 0.004) ** 4
        grupos[d[0][1]].add([v.index], w0 / (w0 + w1), 'REPLACE')
        if d[1][1] != d[0][1]:
            grupos[d[1][1]].add([v.index], w1 / (w0 + w1), 'ADD')
    mod = o.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    o.parent = arm
    o.matrix_parent_inverse = arm.matrix_world.inverted()
    print("[LUVA] %s: %d vértices pesados em %d ossos" % (o.name, len(o.data.vertices), len(segs)))

# ------------------------------------------------------------------ fotos (conferência)
def foto(nome, olho, alvo, esconder_corpo=False):
    cam = bpy.data.objects.get("CamFoto")
    if cam is None:
        cam = bpy.data.objects.new("CamFoto", bpy.data.cameras.new("CamFoto"))
        bpy.context.collection.objects.link(cam)
    cam.location = olho
    d = (Vector(alvo) - Vector(olho)).normalized()
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = 50
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x, sc.render.resolution_y = 700, 700
    for o in corpo:
        o.hide_render = esconder_corpo
    sc.render.filepath = fotos + "_" + nome + ".png"
    bpy.ops.render.render(write_still=True)


wr, mr = pos("RightHand"), pos("RightHandMiddle3")
cen = (wr + mr) * 0.5
_, _, L, T, N, comp, _ = quadro_mao("Right")
foto("dir_costas", cen + N * 0.45, cen)
foto("dir_palma", cen - N * 0.45, cen)
foto("dir_lado", cen + T * 0.45, cen)
wl = pos("LeftHand")
foto("esq_costas", (wl + pos("LeftHandMiddle3")) * 0.5 + quadro_mao("Left")[4] * 0.45, (wl + pos("LeftHandMiddle3")) * 0.5)

# ------------------------------------------------------------------ exporta esqueleto + luvas
for o in corpo:
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action='DESELECT')
for o in luvas:
    o.select_set(True)
arm.select_set(True)
pai = arm.parent
while pai is not None:   # nós-pai do avatar (giro e escala do FBX): as binds precisam do mesmo espaço
    pai.select_set(True)
    pai = pai.parent
bpy.ops.export_scene.gltf(filepath=saida, use_selection=True, export_format='GLB', export_animations=False)
print("[LUVA] gravado", saida)
