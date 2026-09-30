# Blender: "mãos no volante" para a visão interna do Drag. Posa o avatar segurando um aro (9h15),
# com os dedos fechados em volta dele, veste a luva (opcional) e exporta só antebraços + mãos,
# cada lado no próprio referencial: origem no ponto do aro onde a mão segura, X para a direita,
# Y para cima no plano do volante, Z para o piloto (os mesmos eixos do nó do volante no jogo).
#
# Uso: blender -b -P tools/luvas/maos_volante.py -- <avatar.glb> <luva_original.glb|-> <saida.glb> <fotos> <altura_m> [json]
# json (opcional): raio, incl (graus do volante), alto (graus acima das 9h/3h), giro, dobra [3], polegar,
#                  luva_eixo_dedos [x,y,z] (direção dos dedos no arquivo da luva), luva_folga, luva_comprimento
#
# Importante: o importador glTF do Blender traz o "repouso" dos ossos num referencial girado em
# relação à malha; aqui tudo é medido na POSE do arquivo (aw @ pose_bone.head / .matrix).
import bpy, bmesh, sys, json, math
import numpy as np
from mathutils import Vector, Matrix, Quaternion

a = sys.argv[sys.argv.index("--") + 1:]
avatar, luva_arq, saida, fotos, altura = a[0], a[1], a[2], a[3], float(a[4])
op = json.loads(a[5]) if len(a) > 5 else {}
R = float(op.get("raio", 0.19))
INCL = math.radians(float(op.get("incl", 22.0)))
ALTO = math.radians(float(op.get("alto", 14.0)))
TUBO = 0.018

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=avatar)
arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
corpo = [o for o in bpy.data.objects if o.type == 'MESH' and o.find_armature() == arm]
for o in [o for o in bpy.data.objects if o.type == 'MESH' and o not in corpo]:
    bpy.data.objects.remove(o, do_unlink=True)

# Avatar virado para +Y (direita = +X) e na altura pedida
raiz = arm
while raiz.parent:
    raiz = raiz.parent
bpy.context.view_layer.update()
zs = []
for o in corpo:
    zs += [(o.matrix_world @ Vector(c)).z for c in o.bound_box]
esc = altura / max(max(zs) - min(zs), 0.5)
raiz.matrix_world = Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Scale(esc, 4) @ raiz.matrix_world
bpy.context.view_layer.update()
aw = arm.matrix_world.copy()


def bone(nome):
    for b in arm.pose.bones:
        if b.name.split("_")[0] == nome:
            return b
    return None


def cab(nome):
    bpy.context.view_layer.update()
    return aw @ bone(nome).head


P0 = {}
for b in arm.pose.bones:
    P0.setdefault(b.name.split("_")[0], aw @ b.head)
M0 = {b.name: aw @ b.matrix for b in arm.pose.bones}
D0 = {b.name: b.matrix @ b.bone.matrix_local.inverted() for b in arm.pose.bones}   # deformação (espaço do esqueleto)


# ------------------------------------------------------------------ luva: encaixe na mão (pose do arquivo)
def ponta_meio(pre):
    m3, m2 = P0[pre + "HandMiddle3"], P0[pre + "HandMiddle2"]
    m4 = P0.get(pre + "HandMiddle4")
    if m4 is None or (m4 - m3).length > 0.08 * esc or (m4 - m3).length < 0.003:
        m4 = m3 + (m3 - m2)
    return m4


def quadro_mao(pre):
    w, m = P0[pre + "Hand"], ponta_meio(pre)
    L = (m - w).normalized()
    T = P0[pre + "HandIndex1"] - P0[pre + "HandPinky1"]
    larg = T.length
    T = (T - L * T.dot(L)).normalized()
    return w, m, L, T, L.cross(T), (m - w).length, larg


def segmentos(pre):
    segs = [(bone(pre + "Hand").name, P0[pre + "Hand"], P0[pre + "HandMiddle1"]),
            (bone(pre + "ForeArm").name, P0[pre + "ForeArm"], P0[pre + "Hand"])]
    for dedo in ("Thumb", "Index", "Middle", "Ring", "Pinky"):
        pts = [P0[pre + "Hand%s%d" % (dedo, k)] for k in (1, 2, 3)]
        pts.append(pts[2] + (pts[2] - pts[1]))
        for k in range(3):
            segs.append((bone(pre + "Hand%s%d" % (dedo, k + 1)).name, pts[k], pts[k + 1]))
    return segs


def dist_seg(p, a_, b_):
    ab = b_ - a_
    t = max(0.0, min(1.0, (p - a_).dot(ab) / max(ab.length_squared, 1e-12)))
    return (p - (a_ + ab * t)).length


def vestir_luva(obj, pre):
    """Encaixa a malha da luva (mão aberta) na mão `pre` e prende nos ossos (pesos pela distância)."""
    me = obj.data
    p = np.array([list(v.co) for v in me.vertices])
    c = p.mean(axis=0)
    _, _, vt = np.linalg.svd(p - c, full_matrices=False)
    Lg, Tg = vt[0], vt[1]
    if np.dot(Lg, np.array(op.get("luva_eixo_dedos", [0, -1, 0]), dtype=float)) < 0:
        Lg = -Lg
    pl, pt = (p - c) @ Lg, (p - c) @ Tg
    meio = pt[np.abs(pl) < (pl.max() - pl.min()) * 0.2]   # polegar: o lado que se estende mais
    if abs(meio.min()) > abs(meio.max()):
        Tg = -Tg
    Ng = np.cross(Lg, Tg)
    if op.get("luva_inverter_palma"):
        Tg, Ng = -Tg, Ng
    w, m, Lh, Th, Nh, comp, larg = quadro_mao(pre)
    pl, pt = (p - c) @ Lg, (p - c) @ Tg
    sL = comp * float(op.get("luva_comprimento", 1.33)) / (pl.max() - pl.min())
    sT = larg * 1.35 * float(op.get("luva_folga", 1.2)) / (pt.max() - pt.min())
    G = np.column_stack([Lg, Tg, np.cross(Lg, Tg)])
    H = np.column_stack([list(Lh), list(Th), list(Nh)])
    Rm = H @ np.diag([sL, sT, sT]) @ G.T
    novo = (p - (c + Lg * pl.max())) @ Rm.T + np.array(list(m + Lh * 0.006))
    if np.linalg.det(Rm) < 0:
        me.flip_normals()
    segs = segmentos(pre)
    grupos = {nm: obj.vertex_groups.new(name=nm) for nm, _, _ in segs}
    awi = aw.inverted()
    for i, v in enumerate(me.vertices):
        q = Vector(novo[i])
        d = sorted((dist_seg(q, a_, b_), nm) for nm, a_, b_ in segs)[:2]
        w0, w1 = 1.0 / (d[0][0] + 0.004) ** 4, 1.0 / (d[1][0] + 0.004) ** 4
        s0, s1 = w0 / (w0 + w1), w1 / (w0 + w1)
        grupos[d[0][1]].add([i], s0, 'REPLACE')
        if d[1][1] != d[0][1]:
            grupos[d[1][1]].add([i], s1, 'ADD')
        # Volta para o repouso do esqueleto: o modificador Armature reaplica a pose
        Dm = D0[d[0][1]] * s0 + D0[d[1][1]] * s1
        v.co = Dm.inverted() @ (awi @ q)
    obj.parent = arm
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_world = aw
    obj.modifiers.new("Armature", 'ARMATURE').object = arm
    obj.name = "Luva" + pre


luvas = []
if luva_arq != "-":
    antes = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=luva_arq)
    novos = [o for o in set(bpy.data.objects) - antes if o.type == 'MESH' and not o.name.lower().startswith(("icosphere", "sphere", "plane", "cube"))]
    for o in list(set(bpy.data.objects) - antes):
        if o not in novos:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in novos:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = novos[0]
    bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
    if len(novos) > 1:
        bpy.ops.object.join()
    fonte = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    p = np.array([list(v.co) for v in fonte.data.vertices])
    cx = (p[:, 0].min() + p[:, 0].max()) * 0.5
    outra = fonte.copy()
    outra.data = fonte.data.copy()
    bpy.context.collection.objects.link(outra)
    for ob, fora in ((fonte, lambda x: x > cx), (outra, lambda x: x <= cx)):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if fora(v.co.x)], context='VERTS')
        bm.to_mesh(ob.data)
        bm.free()
    trocar = bool(op.get("luva_trocar_lados", False))
    vestir_luva(fonte if trocar else outra, "Right")
    vestir_luva(outra if trocar else fonte, "Left")
    luvas = [outra, fonte]

# ------------------------------------------------------------------ volante e pose
n = Vector((0, -math.cos(INCL), math.sin(INCL)))   # normal do volante, para o piloto
u = Vector((0, math.sin(INCL), math.cos(INCL)))     # cima no plano do volante
braco = (P0["LeftForeArm"] - P0["LeftArm"]).length + (P0["LeftHand"] - P0["LeftForeArm"]).length
C = (P0["LeftArm"] + P0["RightArm"]) * 0.5 + Vector((0, 0, -0.3 * esc))


def radial(lado):
    return Vector((lado * math.cos(ALTO), 0, 0)) + u * math.sin(ALTO)


def pegada(lado):
    return C + radial(lado) * R


# Volante na mesma posição, em relação ao olho, que no cockpit do jogo (abaixo e à frente)
OLHO = P0["Head"] + Vector((0, 0.08, 0.08)) * esc
ov = op.get("olho_volante", [0.0, 0.26, 0.41])   # do volante ao olho, eixos do jogo (x, cima, trás)
C = OLHO - Vector((ov[0], -ov[2], ov[1]))
for _ in range(0):
    C.y += (braco * 0.82 - (pegada(-1) - P0["LeftArm"]).length) * 0.8


def alinhar(pb, dir_mundo):
    bpy.context.view_layer.update()
    m = aw @ pb.matrix
    y = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
    q = y.rotation_difference(dir_mundo.normalized())
    pb.matrix = aw.inverted() @ (Matrix.Translation(m.translation) @ q.to_matrix().to_4x4() @ Matrix.Translation(-m.translation) @ m)
    bpy.context.view_layer.update()


def ik(pre, alvo, polo):
    o = cab(pre + "Arm")
    l1 = (P0[pre + "ForeArm"] - P0[pre + "Arm"]).length
    l2 = (P0[pre + "Hand"] - P0[pre + "ForeArm"]).length
    d = alvo - o
    dist = min(d.length, (l1 + l2) * 0.999)
    dn = d.normalized()
    x = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    pp = (polo - dn * polo.dot(dn)).normalized()
    alinhar(bone(pre + "Arm"), (o + dn * x + pp * h) - o)
    alinhar(bone(pre + "ForeArm"), alvo - cab(pre + "ForeArm"))


def girar_osso(pb, q):
    bpy.context.view_layer.update()
    loc, rq, sc = (aw @ pb.matrix).decompose()
    pb.matrix = aw.inverted() @ (Matrix.Translation(loc) @ (q @ rq).to_matrix().to_4x4() @ Matrix.Diagonal(sc).to_4x4())


def posar_mao(pre, lado):
    """Nós dos dedos ao longo do aro, dedos saindo do lado do piloto e fechando pela frente do aro."""
    g = pegada(lado)
    dentro = -radial(lado)
    tang = n.cross(radial(lado)).normalized()
    if tang.dot(u) < 0:
        tang = -tang
    giro = math.radians(float(op.get("giro", -40.0)))
    L = (dentro * math.cos(giro) - n * math.sin(giro)).normalized()
    T = tang if lado < 0 else -tang
    T = (T - L * T.dot(L)).normalized()
    L0 = (P0[pre + "HandMiddle1"] - P0[pre + "Hand"]).normalized()
    T0 = P0[pre + "HandIndex1"] - P0[pre + "HandPinky1"]
    T0 = (T0 - L0 * T0.dot(L0)).normalized()
    rot = Matrix((L, T, L.cross(T))).transposed() @ Matrix((L0, T0, L0.cross(T0))).transposed().inverted()
    palma = (P0[pre + "HandMiddle1"] - P0[pre + "Hand"]).length
    ik(pre, g - L * (palma * 0.9) + n * (TUBO * 1.3), Vector((lado * 0.6, 0.2, -1.0)))
    pb = bone(pre + "Hand")
    bpy.context.view_layer.update()
    loc = (aw @ pb.matrix).translation
    _, q0, sc = M0[pb.name].decompose()
    pb.matrix = aw.inverted() @ (Matrix.Translation(loc) @ (rot.to_quaternion() @ q0).to_matrix().to_4x4() @ Matrix.Diagonal(sc).to_4x4())
    dobra = op.get("dobra", [1.2, 1.3, 1.0])
    eixo = (rot @ T0).normalized()
    for dedo in ("Index", "Middle", "Ring", "Pinky"):
        for k in range(3):
            fb = bone(pre + "Hand%s%d" % (dedo, k + 1))
            if fb:
                girar_osso(fb, Quaternion(eixo, float(dobra[k]) * (0.9 if dedo == "Pinky" else 1.0)))
    eixo_p = (rot @ L0).normalized() * (1 if lado < 0 else -1)
    for k in range(3):
        fb = bone(pre + "HandThumb%d" % (k + 1))
        if fb:
            girar_osso(fb, Quaternion(eixo_p, float(op.get("polegar", 0.5)) * (0.6 if k == 0 else 1.0)))
    bpy.context.view_layer.update()


posar_mao("Left", -1)
posar_mao("Right", 1)

# ------------------------------------------------------------------ peças que vão para o jogo
manter = {b.name for b in arm.data.bones if b.name.split("_")[0].startswith(("LeftForeArm", "RightForeArm", "LeftHand", "RightHand"))}
de_mao = {b for b in manter if b.split("_")[0].startswith(("LeftHand", "RightHand"))}
dg = bpy.context.evaluated_depsgraph_get()
pedacos = {-1: [], 1: []}
for o in corpo + luvas:
    ev = o.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    me.transform(o.matrix_world)
    grupos = {g.index: g.name for g in o.vertex_groups}
    lado_v = np.zeros(len(me.vertices))
    for v in o.data.vertices:
        if o in luvas:
            lado_v[v.index] = -1 if o.name == "LuvaLeft" else 1
            continue
        pm = [(grupos.get(x.group, ""), x.weight) for x in v.groups]
        if sum(w for nm, w in pm if nm in manter) <= 0.5:
            continue
        if luvas and sum(w for nm, w in pm if nm in de_mao) > 0.5:
            continue   # mão de pele some sob a luva
        nm = max((x for x in pm if x[0] in manter), key=lambda x: x[1])[0]
        lado_v[v.index] = -1 if nm.startswith("Left") else 1
    for lado in (-1, 1):
        sel = lado_v == lado
        if not sel.any():
            continue
        m2 = me.copy()
        bm = bmesh.new()
        bm.from_mesh(m2)
        bm.verts.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[bm.verts[i] for i in range(len(bm.verts)) if not sel[i]], context='VERTS')
        bm.to_mesh(m2)
        bm.free()
        ob = bpy.data.objects.new("pedaco", m2)
        bpy.context.collection.objects.link(ob)
        pedacos[lado].append(ob)
    bpy.data.meshes.remove(me)

# ------------------------------------------------------------------ fotos (conferência)
bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=TUBO, major_segments=96, minor_segments=16)
aro = bpy.context.active_object
aro.matrix_world = Matrix.Translation(C) @ Matrix((Vector((1, 0, 0)), u, n)).transposed().to_4x4()
mat = bpy.data.materials.new("aro")
mat.diffuse_color = (0.05, 0.05, 0.06, 1)
aro.data.materials.append(mat)
for o in corpo + luvas:
    o.hide_render = True


def foto(nome, olho, alvo, lente):
    cam = bpy.data.objects.get("CamFoto")
    if cam is None:
        cam = bpy.data.objects.new("CamFoto", bpy.data.cameras.new("CamFoto"))
        bpy.context.collection.objects.link(cam)
    cam.location = olho
    cam.rotation_euler = (Vector(alvo) - Vector(olho)).to_track_quat('-Z', 'Z').to_euler()
    cam.data.lens = lente
    cam.data.clip_start = 0.01
    sc = bpy.context.scene
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'TEXTURE'
    sc.render.resolution_x, sc.render.resolution_y = 1000, 620
    sc.render.filepath = fotos + "_" + nome + ".png"
    bpy.ops.render.render(write_still=True)


foto("piloto", OLHO, OLHO + Vector((0, math.cos(math.radians(8)), -math.sin(math.radians(8)))), 17)
foto("lado", C + Vector((-0.6, 0.0, 0.06)), C, 30)
foto("frente", C + Vector((0.0, 0.55, 0.15)), C, 30)
foto("perto", pegada(-1) + Vector((-0.1, -0.2, 0.14)), pegada(-1), 30)

# ------------------------------------------------------------------ exporta (cada mão na sua pegada)
W = Matrix((Vector((1, 0, 0)), u, n)).transposed()
M = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0))) @ W.inverted()   # local (volante) -> Blender de exportação
for lado, obs in pedacos.items():
    if not obs:
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "MaoEsq" if lado < 0 else "MaoDir"
    ob.data.transform(M.to_4x4() @ Matrix.Translation(-pegada(lado)))
    ob.matrix_world = Matrix.Identity(4)
for o in list(bpy.data.objects):
    if o.name not in ("MaoEsq", "MaoDir"):
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=saida, export_format='GLB', export_animations=False, export_skins=False)
print("[MAOS] gravado %s (raio %.3f, alto %.1f graus)" % (saida, R, math.degrees(ALTO)))
