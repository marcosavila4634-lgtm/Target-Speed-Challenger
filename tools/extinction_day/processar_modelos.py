# Prepara os modelos da pasta assets/DINOSSAUROS (biblioteca do dono) para o jogo: separa os
# dinossauros do pacote, reduz os modelos pesados (decimate), diminui as texturas e exporta .glb
# em assets/dino/<id>/<id>.glb.
#   blender -b --python processar_modelos.py -- <id ou "todos">
import bpy, sys, os, math
ORIG = "H:/PROJECTS/JOGO/assets/DINOSSAUROS/"
DEST = "H:/PROJECTS/JOGO/assets/dino/"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["todos"]

def limpar():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def importar(arq):
    bpy.ops.import_scene.gltf(filepath=ORIG + arq)

def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)

def reduzir(o, alvo):
    t = tris(o)
    if t <= alvo:
        return
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("dec", 'DECIMATE')
    m.ratio = max(alvo / t, 0.002)
    m.use_collapse_triangulate = True
    # Mantém o modificador antes da armadura (aplica na malha em repouso)
    while o.modifiers.find("dec") > 0:
        bpy.ops.object.modifier_move_up(modifier="dec")
    with bpy.context.temp_override(object=o, active_object=o):
        bpy.ops.object.modifier_apply(modifier="dec")

def texturas(max_lado=1024):
    for im in bpy.data.images:
        if im.size[0] > max_lado:
            im.scale(max_lado, max_lado * im.size[1] // im.size[0])

def exportar(id, objetos, anim=False):
    os.makedirs(DEST + id, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objetos:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=DEST + id + "/" + id + ".glb", export_format='GLB', use_selection=True,
        export_image_format='JPEG', export_jpeg_quality=88, export_animations=anim, export_apply=False,
        export_yup=True)
    tot = sum(tris(o) for o in objetos if o.type == 'MESH')
    print("EXPORTADO", id, "tris", tot)

def com_filhos(raiz):
    lista = [raiz]
    for c in raiz.children_recursive:
        lista.append(c)
    return lista

def sobe_ate_raiz(o):
    while o.parent:
        o = o.parent
    return o

def dinos_pacote():
    nomes = {"GLTF_created_0": ("tiranossauro", 0.32), "GLTF_created_1": ("carnotauro", 0.18), "GLTF_created_2": ("espinossauro", 0.42),
             "GLTF_created_3": ("alossauro", 1.0), "GLTF_created_4": ("ceratossauro", 0.5)}
    for arm, (id, razao) in nomes.items():
        limpar()
        importar("Theropod_inosaur_models (coloured)/theropod_inosaur_models_coloured.glb")
        a = bpy.data.objects[arm]
        malhas = [o for o in bpy.context.scene.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == a for m in o.modifiers)]
        for o in malhas:
            reduzir(o, max(int(tris(o) * razao), 300))
        texturas(1024)
        # Sobe até o nó raiz do armature para levar as transformações
        objs = [a] + malhas
        p = a.parent
        while p:
            objs.append(p)
            p = p.parent
        exportar(id, objs)

def simples(id, arq, alvo_total, max_tex=1024, anim=False, apagar_mats=()):
    limpar()
    importar(arq)
    malhas = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for o in list(malhas):
        if any(s.material and s.material.name in apagar_mats for s in o.material_slots) and len(o.material_slots) == 1:
            bpy.data.objects.remove(o)
            malhas.remove(o)
    total = sum(tris(o) for o in malhas)
    if total > alvo_total and len(malhas) > 1 and not anim:
        # Junta tudo numa malha (muitas peças pequenas pesam no motor) e reduz
        bpy.ops.object.select_all(action='DESELECT')
        for o in malhas:
            o.select_set(True)
        bpy.context.view_layer.objects.active = malhas[0]
        bpy.ops.object.join()
        malhas = [bpy.context.view_layer.objects.active]
    for o in malhas:
        reduzir(o, int(tris(o) * alvo_total / max(total, 1)))
    texturas(max_tex)
    objs = list(bpy.context.scene.objects)
    exportar(id, objs, anim)

def portao():
    limpar()
    importar("MAPA/Jurassic Park Gate/jurassic_park_gate.glb")
    # Tira o letreiro original (letras douradas e vermelhas pintadas na textura): vira pedra/madeira escura
    import numpy as np
    for im in bpy.data.images:
        if im.size[0] == 0 or "Image_0" not in im.name:
            continue
        w, h = im.size
        px = np.array(im.pixels[:]).reshape(h, w, 4)
        r, g, b = px[..., 0], px[..., 1], px[..., 2]
        mx = np.maximum(np.maximum(r, g), b); mn = np.minimum(np.minimum(r, g), b)
        sat = (mx - mn) / np.maximum(mx, 1e-4)
        tinta = (sat > 0.45) & (mx > 0.25) & ((r > b * 1.6))
        cinza = 0.27
        for c in range(3):
            px[..., c] = np.where(tinta, cinza * (0.85 + 0.3 * (px[..., c] - mn)), px[..., c])
        im.pixels[:] = px.ravel()
        im.update()
        print("PORTAO pixels trocados", int(tinta.sum()))
    texturas(1024)
    exportar("portao", list(bpy.context.scene.objects))

def lava():
    limpar()
    importar("LAVA/lava.glb")
    os.makedirs(DEST + "lava", exist_ok=True)
    for m in bpy.data.materials:
        if m.name != "01_-_Default" or not m.use_nodes:
            continue
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image:
                destino = [l.to_socket.name for o in n.outputs for l in o.links]
                nome = "base" if "Base Color" in destino else ("emissao" if "Emission Color" in destino else ("normal" if "Color" in destino and any(l.to_node.type == 'NORMAL_MAP' for o in n.outputs for l in o.links) else "orm"))
                im = n.image
                if im.size[0] > 1024:
                    im.scale(1024, 1024)
                im.filepath_raw = DEST + "lava/lava_" + nome + ".png"
                im.file_format = 'PNG'
                im.save()
                print("LAVA", nome, im.size[:])

def pterossauro():
    # Pterossauro da plataforma dos buracos (solta ovos nos carros): só o bicho, sem a ilha do cenário,
    # com o esqueleto e a animação de voo do autor — três batidas de asa e um planeio, que se repetem a
    # cada 258 quadros (o resto do arquivo é a mesma coisa com o bicho dando a volta na ilha). O passeio
    # pela ilha fica nos nós de cima e nas curvas do objeto: saem, o voo é feito no jogo.
    limpar()
    importar("pterodactilo/flying_pterodactyl_dinosaur_soars_over_island (1).glb")
    sc = bpy.context.scene
    sc.frame_set(0)
    arm = bpy.data.objects["GLTF_created_0"]
    malhas = [o for o in sc.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == arm for m in o.modifiers)]
    mw = arm.matrix_world.copy()
    ac = arm.animation_data.action
    fora = 0
    for camada in ac.layers:
        for faixa in camada.strips:
            for saco in faixa.channelbags:
                for fc in list(saco.fcurves):
                    if not fc.data_path.startswith("pose.bones"):
                        saco.fcurves.remove(fc)
                        fora += 1
    arm.parent = None
    arm.matrix_world = mw
    for o in list(sc.objects):
        if o != arm and o not in malhas:
            bpy.data.objects.remove(o)
    texturas(1024)
    sc.frame_start = 0
    sc.frame_end = 258
    os.makedirs(DEST + "pterossauro", exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in [arm] + malhas:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=DEST + "pterossauro/pterossauro.glb", export_format='GLB', use_selection=True,
        export_image_format='JPEG', export_jpeg_quality=88, export_animations=True, export_frame_range=True,
        export_force_sampling=True, export_apply=False, export_yup=True)
    print("EXPORTADO pterossauro tris", sum(tris(o) for o in malhas), "curvas de objeto tiradas", fora)

tarefas = {
    "pterossauro": pterossauro,
    "dinos": dinos_pacote,
    "trex": lambda: simples("trex", "Tyrannosaurus/tyrannosaurus_rex_lowpoly.glb", 12000, 1024, True),
    "titanossauro": lambda: simples("titanossauro", "Theropod_inosaur_models (coloured)/jwa_titanosaurus.glb", 12000, 1024, True),
    "meteoro": lambda: simples("meteoro", "Meteor/meteor (1).glb", 13000, 1024),
    "portao": portao,
    "cerca": lambda: simples("cerca", "MAPA/Electric fence Jurassic Park/electric_fence_jurassic_park.glb", 24000, 512),
    "jaula": lambda: simples("jaula", "MAPA/GATE 2/jurassic_park_cage.glb", 30000, 512),
    "recinto": lambda: simples("recinto", "ASDF/jurassic_park_raptor_pen.glb", 70000, 1024, False, ("sand", "grass")),
    "cranio": lambda: simples("cranio", "riceratops Horridus/triceratops_horridus.glb", 40000, 2048),
    "ruina": lambda: simples("ruina", "Theropod_inosaur_models (coloured)/chateau_de_beauregard_jura.glb", 60000, 2048),
    "lava": lava,
}
for nome in (tarefas.keys() if argv[0] == "todos" else argv):
    tarefas[nome]()
