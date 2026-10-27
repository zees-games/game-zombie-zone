"""Builds assets/zombies/zombie_mutant.glb from "Buff Mutant 2.0" by Zeldrix (CC BY 4.0).

    blender -b --factory-startup --python art-src/mutant.py -- <buff_mutant.glb> <out.glb> [debug_prefix]

Modified from the original: every object is decimated (the two gravity guns from 56k faces each), split
into loose pieces, each piece skinned rigidly to one bone of a small armature (hips, spine, head, two
arms, two legs, two guns, jetpack) so the game can pose it and shoot a gun or the jetpack off, and the
textures are baked into vertex colours (one material, plus one emissive for the glowing strips).
The model is scaled to 2.4 m. Source: https://sketchfab.com/3d-models/buff-mutant-20-8933f1f4a728486e8bcbe09714b842be
"""
import bpy, sys, math, bmesh
import numpy as np
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
DEBUG = args[2] if len(args) > 2 else ""

SCALE = 1.45
GUN_RATIO, BODY_RATIO = 0.035, 0.2
GUN_VOXEL, BODY_VOXEL = 0.014, 0.011
GLOW_MATS = {"Material_15", "Material_28", "Material_29"}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:
    o.parent = None  # the importer's empty carries a rotation; bake it in below
    o.matrix_world = o.matrix_world
bpy.ops.object.select_all(action="DESELECT")
for o in bpy.data.objects:
    if o.type == "EMPTY":
        bpy.data.objects.remove(o)


def apply_all(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def texel(mat):
    """(image pixels as (h, w, 4) float array, or None, factor colour)."""
    nodes = mat.node_tree.nodes
    bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
    factor = tuple(bsdf.inputs["Base Color"].default_value[:3])
    for n in nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            img = n.image
            w, h = img.size
            px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
            return px, factor
    return None, factor


tex_cache = {}

# 1. colour from the textures, welded, then decimated (welded first: the importer splits vertices at every
# UV seam, and collapsing those apart tears the mesh into shards)
for o in meshes:
    apply_all(o)
    me = o.data
    nl, npoly = len(me.loops), len(me.polygons)
    uvs = np.zeros((nl, 2), dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", uvs.ravel())
    lv = np.zeros(nl, dtype=np.int32)
    me.loops.foreach_get("vertex_index", lv)
    ltot = np.zeros(npoly, dtype=np.int32)
    me.polygons.foreach_get("loop_total", ltot)
    lp = np.repeat(np.arange(npoly), ltot)
    pmat = np.zeros(npoly, dtype=np.int32)
    me.polygons.foreach_get("material_index", pmat)
    cols = np.zeros((nl, 3), dtype=np.float32)
    glow = np.zeros(npoly, dtype=np.int32)
    for mi, mat in enumerate(me.materials):
        sel = pmat[lp] == mi
        if mat is None or not sel.any():
            continue
        if mat.name not in tex_cache:
            tex_cache[mat.name] = texel(mat)
        px, factor = tex_cache[mat.name]
        if px is None:
            cols[sel] = factor
        else:
            h, w = px.shape[:2]
            x = ((uvs[sel, 0] % 1.0) * (w - 1) + 0.5).astype(np.int32)
            y = ((uvs[sel, 1] % 1.0) * (h - 1) + 0.5).astype(np.int32)
            cols[sel] = px[y, x, :3]
        if mat.name in GLOW_MATS:
            glow[pmat == mi] = 1
    vcol = np.zeros((len(me.vertices), 4), dtype=np.float32)
    cnt = np.zeros(len(me.vertices), dtype=np.float32)
    np.add.at(vcol[:, :3], lv, cols)
    np.add.at(cnt, lv, 1.0)
    vcol[:, :3] /= np.maximum(cnt, 1.0)[:, None]
    vcol[:, 3] = 1.0
    me.materials.clear()
    me.materials.append(None)
    me.materials.append(None)
    me.polygons.foreach_set("material_index", glow)
    me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    me.color_attributes["Col"].data.foreach_set("color", vcol.ravel())
    for n in list(me.uv_layers):
        me.uv_layers.remove(n)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me)
    bm.free()
    gun = len(me.polygons) > 20000
    ratio = GUN_RATIO if gun else (BODY_RATIO if len(me.polygons) > 300 else 1.0)
    if ratio < 1.0:
        m = o.modifiers.new("dec", "DECIMATE")
        m.ratio = ratio
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="dec")
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.verts.ensure_lookup_table()
        seen = set()
        for v in bm.verts:
            if v.index in seen:
                continue
            comp, stack = [v], [v]
            seen.add(v.index)
            while stack:
                cur = stack.pop()
                for e in cur.link_edges:
                    w = e.other_vert(cur)
                    if w.index not in seen:
                        seen.add(w.index)
                        comp.append(w)
                        stack.append(w)
            if len(comp) < 14:
                bmesh.ops.delete(bm, geom=comp, context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
    o["x"] = 1

# 3. split into loose pieces, classify each by where it sits
BONES = {
    # name: (head, tail, parent)   Blender axes, metres BEFORE the scale; the model faces -Y
    "Hips": ((0, 0, 0.85), (0, 0, 0.95), None),
    "Spine": ((0, 0, 0.95), (0, 0, 1.30), "Hips"),
    "Head": ((0, -0.04, 1.40), (0, -0.04, 1.62), "Spine"),
    "ArmL": ((0.27, 0, 1.25), (0.35, -0.05, 0.90), "Spine"),
    "ArmR": ((-0.27, 0, 1.25), (-0.35, -0.05, 0.90), "Spine"),
    "LegL": ((0.12, 0, 0.85), (0.12, 0, 0.05), "Hips"),
    "LegR": ((-0.12, 0, 0.85), (-0.12, 0, 0.05), "Hips"),
    "ShoulderL": ((0.30, 0.0, 1.30), (0.36, 0.0, 1.38), "Spine"),
    "ShoulderR": ((-0.30, 0.0, 1.30), (-0.36, 0.0, 1.38), "Spine"),
    "GunL": ((0.48, 0.10, 1.45), (0.62, 0.10, 1.45), "ShoulderL"),
    "GunR": ((-0.41, -0.10, 1.44), (-0.55, -0.10, 1.44), "ShoulderR"),
    "Jetpack": ((0, 0.21, 1.03), (0, 0.21, 1.20), "Spine"),
    "Nozzle": ((0, 0.20, 0.72), (0, 0.20, 0.62), "Jetpack"),
}


def classify(c, lo, hi):
    """Bone name for a piece with centroid c and bounding box lo..hi."""
    x, y, z = c
    if z > 1.28 and abs(x) > 0.30:
        return "GunL" if x > 0 else "GunR"
    if y > 0.13 and abs(x) < 0.4 and 0.55 < z < 1.4:
        return "Jetpack"
    if z > 1.30 and abs(x) < 0.30:
        return "Head"
    if z < 0.84:
        return "LegL" if x > 0 else "LegR"
    if abs(x) > 0.30 and z < 1.28:
        return "ArmL" if x > 0 else "ArmR"
    return "Spine"


pieces = []
for o in list(meshes):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
# the big skin and armour shells span several bones: split those by face
for o in [o for o in bpy.data.objects if o.type == "MESH" and len(o.data.polygons) > 150]:
    names = set()
    for p in o.data.polygons:
        names.add(classify(p.center, None, None))
    if len(names) < 2:
        continue
    for nm in sorted(names)[:-1]:
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.mode_set(mode="EDIT")
        bm = bmesh.from_edit_mesh(o.data)
        for f in bm.faces:
            f.select_set(classify(f.calc_center_median(), None, None) == nm)
        bmesh.update_edit_mesh(o.data)
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
for o in [o for o in bpy.data.objects if o.type == "MESH"]:
    me = o.data
    vs = np.array([o.matrix_world @ v.co for v in me.vertices])
    if len(vs) == 0:
        continue
    pieces.append((o, vs.mean(axis=0), vs.min(axis=0), vs.max(axis=0)))

groups = {}
for o, c, lo, hi in pieces:
    groups.setdefault(classify(c, lo, hi), []).append(o)
print("GROUPS", {k: len(v) for k, v in groups.items()})

# 4. join per bone group
joined = {}
for bone, objs in groups.items():
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = "Part_" + bone
    joined[bone] = ob

# 5. scale, one body mesh per bone group but all skinned to one armature
arm_data = bpy.data.armatures.new("Armature")
arm = bpy.data.objects.new("Armature", arm_data)
sc.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, parent) in BONES.items():
    b = arm_data.edit_bones.new(name)
    b.head = Vector(h) * SCALE
    b.tail = Vector(t) * SCALE
    if (b.tail - b.head).length < 0.05:
        b.tail = b.head + Vector((0, 0, 0.1))
for name, (h, t, parent) in BONES.items():
    if parent:
        arm_data.edit_bones[name].parent = arm_data.edit_bones[parent]
bpy.ops.object.mode_set(mode="OBJECT")

for bone, ob in joined.items():
    ob.scale = (SCALE, SCALE, SCALE)
    apply_all(ob)
    me = ob.data
    # drop the original materials: slot 0 = body (vertex colour), slot 1 = glow
    keep = [p.material_index for p in me.polygons]
    me.materials.clear()
    mb = bpy.data.materials.get("mutant_body") or bpy.data.materials.new("mutant_body")
    mg = bpy.data.materials.get("mutant_glow") or bpy.data.materials.new("mutant_glow")
    for m, glowing in ((mb, False), (mg, True)):
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        if glowing:
            bsdf.inputs["Base Color"].default_value = (1.0, 0.45, 0.05, 1)
            bsdf.inputs["Emission Color"].default_value = (1.0, 0.4, 0.02, 1)
            bsdf.inputs["Emission Strength"].default_value = 3.0
        elif not any(n.type == "VERTEX_COLOR" or n.type == "ATTRIBUTE" for n in nt.nodes):
            col = nt.nodes.new("ShaderNodeVertexColor")
            col.layer_name = "Col"
            nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
            bsdf.inputs["Roughness"].default_value = 0.6
            bsdf.inputs["Metallic"].default_value = 0.0
    me.materials.append(mb)
    me.materials.append(mg)
    for p, k in zip(me.polygons, keep):
        p.material_index = k
    for p in me.polygons:
        p.use_smooth = True
    vg = ob.vertex_groups.new(name=bone)
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
    ob.parent = arm
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

# legs: a soft join at the hip so a stride does not tear the trousers
for bone in ("LegL", "LegR"):
    ob = joined.get(bone)
    if ob is None:
        continue
    me = ob.data
    vg_hips = ob.vertex_groups.new(name="Hips")
    vg_leg = ob.vertex_groups[bone]
    for v in me.vertices:
        w = min(max((v.co.z - 0.80 * SCALE) / (0.12 * SCALE), 0.0), 1.0)
        vg_leg.add([v.index], 1.0 - w, "REPLACE")
        vg_hips.add([v.index], w, "REPLACE")

# arms: soft at the shoulder
for bone in ("ArmL", "ArmR"):
    ob = joined.get(bone)
    if ob is None:
        continue
    me = ob.data
    vg_sp = ob.vertex_groups.new(name="Spine")
    vg = ob.vertex_groups[bone]
    sx = 0.27 * SCALE * (1 if bone == "ArmL" else -1)
    for v in me.vertices:
        d = math.hypot(v.co.x - sx, v.co.z - 1.25 * SCALE)
        w = max(1.0 - d / (0.22 * SCALE), 0.0)
        vg.add([v.index], 1.0 - w, "REPLACE")
        vg_sp.add([v.index], w, "REPLACE")

tris = 0
for ob in joined.values():
    me = ob.data
    me.calc_loop_triangles()
    tris += len(me.loop_triangles)
print("TRIS", tris)

if DEBUG:
    import colorsys
    for i, (bone, ob) in enumerate(joined.items()):
        m = bpy.data.materials.new("dbg" + bone)
        c = colorsys.hsv_to_rgb((i * 0.31) % 1, 0.8, 0.9)
        m.diffuse_color = (*c, 1)
        print("DBG", bone, "#%02x%02x%02x" % tuple(int(x * 255) for x in c))
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.color_type = "VERTEX"
    sc.display.shading.light = "STUDIO"
    sc.render.resolution_x, sc.render.resolution_y = 500, 600
    cam = bpy.data.cameras.new("c"); cam.type = "ORTHO"; cam.ortho_scale = 3.0
    co = bpy.data.objects.new("c", cam); sc.collection.objects.link(co); sc.camera = co
    for name, loc, rot in [("front", (0, -6, 1.2), (math.pi / 2, 0, 0)),
                           ("side", (6, 0, 1.2), (math.pi / 2, 0, math.pi / 2)),
                           ("back", (0, 6, 1.2), (math.pi / 2, 0, math.pi))]:
        co.location = loc; co.rotation_euler = rot
        sc.render.filepath = DEBUG + "_" + name + ".png"
        bpy.ops.render.render(write_still=True)
    # bone colouring
    for i, (bone, ob) in enumerate(joined.items()):
        m = bpy.data.materials["dbg" + bone]
        ob.data.materials.clear(); ob.data.materials.append(m)
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.light = "FLAT"
    for name, loc, rot in [("front", (0, -6, 1.2), (math.pi / 2, 0, 0)),
                           ("side", (6, 0, 1.2), (math.pi / 2, 0, math.pi / 2))]:
        co.location = loc; co.rotation_euler = rot
        sc.render.filepath = DEBUG + "_bone_" + name + ".png"
        bpy.ops.render.render(write_still=True)
else:
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=False, export_yup=True,
                              export_materials="EXPORT", export_animations=False, export_skins=True)
    print("WROTE", OUT)
