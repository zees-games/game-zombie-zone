"""Builds assets/zombies/zombie_oil_monster.glb (and _lod1.glb) from "Scary, Lovcraftian, Toothy, Oil-monster"
by lealeelu (CC BY 4.0), whose teeth are "Tooth and spike collection" by mStuff (CC0, Blendswap 12455).

    blender -b --factory-startup --python art-src/oil_monster.py -- <oil_monster_src.glb> <out_dir>

The source is a baked fluid simulation: a lacy shell of oil draped over an invisible collider sphere, with a
splash sheet on the floor and a ring of teeth. It has no rig and no clips. Here:
  - the floor sheet is cut away (a round puddle, `Pool`, replaces it) and the lace is decimated (collapse),
  - the collider sphere becomes the solid `Core` (decimated, mouth hole cut), joined with the lace as `Body`,
  - `Mouth` is a small dark cavity behind the hole, `TeethTop` and `TeethBottom` are decimated separately,
  - one armature: root > spine_lo > spine_mid > spine_hi > jaw (the lower lip and bottom teeth ride the jaw),
  - test clips (30 fps): idle-loop, slide-loop, mouth_open, bite, grab, lift, swallow, flinch, die.
The mouth faces -Y in Blender, which is +Z in the glTF (the view turns it by PI). The model is 2.5 m tall, the origin on the floor at the centre.
"""
import bpy, bmesh, sys, math
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
HEIGHT = 2.5
LODS = {"": dict(lace=9500, core=1800, top=1300, bottom=1900),
        "_lod1": dict(lace=1500, core=700, top=250, bottom=400)}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def world_flat(o):
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.select_set(False)


def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def decimate(o, target):
    n = tris(o)
    if n <= target:
        return
    m = o.modifiers.new("d", "DECIMATE")
    m.ratio = target / n
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=m.name)


def drop_small_islands(o, keep_frac=0.02):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    seen, islands = set(), []
    for f in bm.faces:
        if f in seen:
            continue
        stack, isl = [f], []
        seen.add(f)
        while stack:
            c = stack.pop()
            isl.append(c)
            for e in c.edges:
                for g in e.link_faces:
                    if g not in seen:
                        seen.add(g)
                        stack.append(g)
        islands.append(isl)
    big = max(len(i) for i in islands)
    kill = [f for i in islands if len(i) < big * keep_frac for f in i]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()


def smooth(o):
    for p in o.data.polygons:
        p.use_smooth = True


def material(name, base, metal, rough, emit=None, spec=0.5):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = base
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    b.inputs["Specular IOR Level"].default_value = spec
    if emit:
        b.inputs["Emission Color"].default_value = emit
        b.inputs["Emission Strength"].default_value = 0.4
    return m


def assign(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)


def build(cfg, suffix):
    clear()
    bpy.ops.import_scene.gltf(filepath=SRC)
    by = {o.name: o for o in bpy.data.objects if o.type == "MESH" and o.visible_get()}
    lace, core = by["Domain_oil_0"], by["Sphere.col_oil_0"]
    top, bot = by["Teeth.top_Teeth_Material_0"], by["Teeth.bottom_Teeth_Material_0"]
    parts = [lace, core, top, bot]
    bpy.context.view_layer.update()
    for o in parts:
        world_flat(o)
    for o in list(bpy.data.objects):
        if o not in parts:
            bpy.data.objects.remove(o)

    def zrange(o):
        zs = [v.co.z for v in o.data.vertices]
        return min(zs), max(zs)

    floor = zrange(lace)[0]
    ccent = sum((v.co for v in core.data.vertices), Vector()) / len(core.data.vertices)
    R = max((v.co - ccent).length for v in core.data.vertices)
    s = HEIGHT / (zrange(core)[1] - floor)
    # cut the floor splash: low and far from the axis
    bm = bmesh.new()
    bm.from_mesh(lace.data)
    cut = [v for v in bm.verts
           if v.co.z < floor + 0.30 * R and math.hypot(v.co.x - ccent.x, v.co.y - ccent.y) > 0.85 * R]
    bmesh.ops.delete(bm, geom=cut, context="VERTS")
    bm.to_mesh(lace.data)
    bm.free()

    # normalise: origin on the floor under the core, metres
    for o in parts:
        for v in o.data.vertices:
            v.co = Vector(((v.co.x - ccent.x) * s, (v.co.y - ccent.y) * s, (v.co.z - floor) * s))
        o.data.update()
    cz = (ccent.z - floor) * s
    R *= s

    # mouth: where the teeth are
    def bounds(o):
        vs = [v.co for v in o.data.vertices]
        return [(min(v[i] for v in vs), max(v[i] for v in vs)) for i in range(3)]

    bt, bb = bounds(top), bounds(bot)
    mx0 = min(bt[0][0], bb[0][0]); mx1 = max(bt[0][1], bb[0][1])
    mz0 = min(bt[2][0], bb[2][0]); mz1 = max(bt[2][1], bb[2][1])
    mzc = (mz0 + mz1) / 2
    print("MOUTH x", mx0, mx1, "z", mz0, mz1, "core z", cz, "R", R)
    print("TEETH top", bt, "bottom", bb)

    # core: decimate, then cut the mouth hole
    decimate(core, cfg["core"])
    for v in core.data.vertices:  # a hair inside, so the lace stands proud of it
        v.co = Vector((v.co.x * 0.97, v.co.y * 0.97, cz + (v.co.z - cz) * 0.97))
    bm = bmesh.new()
    bm.from_mesh(core.data)
    hole = [f for f in bm.faces
            if f.calc_center_median().y < -0.3 * R
            and mx0 * 0.9 <= f.calc_center_median().x <= mx1 * 0.9
            and mz0 + 0.1 * (mz1 - mz0) <= f.calc_center_median().z <= mz1 - 0.05 * (mz1 - mz0)]
    bmesh.ops.delete(bm, geom=hole, context="FACES_ONLY")
    bm.to_mesh(core.data)
    bm.free()

    drop_small_islands(lace)
    decimate(lace, cfg["lace"])
    drop_small_islands(lace, 0.01)
    decimate(top, cfg["top"])
    decimate(bot, cfg["bottom"])

    oil = material("oil", (0.02, 0.02, 0.03, 1), 0.35, 0.08, spec=0.9)
    tooth = material("teeth", (0.78, 0.74, 0.60, 1), 0.0, 0.45)
    wet = material("mouth", (0.12, 0.008, 0.015, 1), 0.0, 0.25, emit=(0.35, 0.01, 0.02, 1))

    # body = lace + core; pool and mouth separate
    for o in (lace, core):
        o.select_set(True)
    bpy.context.view_layer.objects.active = lace
    bpy.ops.object.join()
    body = lace
    body.name = "Body"
    assign(body, oil)
    smooth(body)

    bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=1)
    mouth = bpy.context.active_object
    mouth.name = "Mouth"
    mouth.scale = ((mx1 - mx0) * 0.5, 0.3 * R, (mz1 - mz0) * 0.6)
    mouth.location = ((mx0 + mx1) / 2, -R * 0.4, mzc)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.flip_normals()
    bpy.ops.object.mode_set(mode="OBJECT")
    assign(mouth, wet)

    bpy.ops.mesh.primitive_circle_add(vertices=28, radius=1, fill_type="NGON")
    pool = bpy.context.active_object
    pool.name = "Pool"
    bm = bmesh.new()
    bm.from_mesh(pool.data)
    bmesh.ops.inset_region(bm, faces=bm.faces[:], thickness=0.0)
    ring = [v for v in bm.verts]
    for i, v in enumerate(ring):
        k = 1.0 + 0.16 * math.sin(i * 2.3) + 0.08 * math.sin(i * 5.1)
        v.co.x *= 0.95 * k
        v.co.y *= 0.95 * k
    bm.to_mesh(pool.data)
    bm.free()
    pool.location.z = 0.012
    bpy.context.view_layer.objects.active = pool
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    assign(pool, oil)
    smooth(pool)

    for o, n in ((top, "TeethTop"), (bot, "TeethBottom")):
        o.name = n
        assign(o, tooth)
        smooth(o)

    # armature
    bpy.ops.object.armature_add(enter_editmode=True)
    arm = bpy.context.active_object
    arm.name = "OilMonster"
    ab = arm.data.edit_bones
    ab.remove(ab[0])
    top_z = HEIGHT
    spec = [("root", None, (0, 0, 0), (0, 0, 0.25)),
            ("spine_lo", "root", (0, 0, 0.25), (0, 0, 0.8)),
            ("spine_mid", "spine_lo", (0, 0, 0.8), (0, 0, 1.3)),
            ("spine_hi", "spine_mid", (0, 0, 1.3), (0, 0, top_z)),
            ("jaw", "spine_hi", (0, -R * 0.25, mzc), (0, -R * 0.95, mzc - 0.05))]
    for n, p, h, t in spec:
        b = ab.new(n)
        b.head, b.tail = h, t
        if p:
            b.parent = ab[p]
    bpy.ops.object.mode_set(mode="OBJECT")

    heights = [("root", 0.0), ("spine_lo", 0.45), ("spine_mid", 1.0), ("spine_hi", 1.55)]

    def smoothstep(a, b, x):
        t = max(0.0, min(1.0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)

    def jaw_w(co):
        front = smoothstep(-0.05 * R, -0.45 * R, co.y)
        band = smoothstep(mz1 + 0.06 * R, mz1 - 0.1 * R, co.z) * (1 - smoothstep(mz0 - 0.2 * R, mz0 - 0.6 * R, co.z))
        return front * band * smoothstep(-0.2 * R, 0.0, mz1 - co.z + 0.2 * R)

    def skin(o, fn):
        o.parent = arm
        for n, _, _, _ in spec:
            o.vertex_groups.new(name=n)
        for v in o.data.vertices:
            for n, w in fn(v.co).items():
                if w > 0.01:
                    o.vertex_groups[n].add([v.index], w, "REPLACE")
        m = o.modifiers.new("Armature", "ARMATURE")
        m.object = arm

    def height_w(co):
        z = co.z
        out = {}
        for i in range(len(heights) - 1):
            (n0, z0), (n1, z1) = heights[i], heights[i + 1]
            if z0 <= z <= z1:
                t = (z - z0) / (z1 - z0)
                out = {n0: 1 - t, n1: t}
        if z < heights[0][1]:
            out = {"root": 1.0}
        elif z > heights[-1][1]:
            out = {"spine_hi": 1.0}
        return out

    def body_w(co):
        w = height_w(co)
        j = jaw_w(co)
        w = {k: v * (1 - j) for k, v in w.items()}
        w["jaw"] = j
        return w

    skin(body, body_w)
    skin(pool, lambda co: {"root": 1.0})
    skin(mouth, lambda co: {"spine_hi": 1.0 - 0.5 * smoothstep(mzc, mz0, co.z), "jaw": 0.5 * smoothstep(mzc, mz0, co.z)})
    skin(top, lambda co: {"spine_hi": 1.0})
    skin(bot, lambda co: {"jaw": 1.0})

    make_actions(arm)

    bpy.ops.object.select_all(action="DESELECT")
    for o in (arm, body, pool, mouth, top, bot):
        o.select_set(True)
    out = f"{OUT}/zombie_oil_monster{suffix}.glb"
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_skins=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True,
                              export_materials="EXPORT", export_normals=True)
    rename_clips(out)
    print("WROTE", out, {o.name: tris(o) for o in (body, pool, mouth, top, bot)})


def rename_clips(path):
    """The exporter names a clip <action>_<armature>; Godot wants the plain name (and the -loop suffix)."""
    import json, struct
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    for a in j.get("animations", []):
        a["name"] = a["name"].replace("_OilMonster", "")
    nj = json.dumps(j, separators=(",", ":")).encode()
    nj += b" " * (-len(nj) % 4)
    rest = b[20 + jl:]
    open(path, "wb").write(b[:8] + struct.pack("<I", 12 + 8 + len(nj) + len(rest)) + struct.pack("<I", len(nj)) + b[16:20] + nj + rest)


BONES = ["root", "spine_lo", "spine_mid", "spine_hi", "jaw"]
D = math.radians


def make_actions(arm):
    arm.animation_data_create()
    bpy.context.scene.render.fps = 30
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"

    def clip(name, end, keys, loop=False):
        """keys: {frame: {bone: (rx_deg, ry_deg, rz_deg, sx, sy, sz, lz_m)}}; unlisted bones stay at rest."""
        act = bpy.data.actions.new(name + ("-loop" if loop else ""))
        act.use_fake_user = True
        arm.animation_data.action = act
        for f in sorted(keys):
            for pb in arm.pose.bones:
                v = keys[f].get(pb.name, (0, 0, 0, 1, 1, 1, 0))
                pb.rotation_euler = (D(v[0]), D(v[1]), D(v[2]))
                pb.scale = (v[3], v[5], v[4])  # the bone's own Y is up the body
                pb.location = (0, v[6], 0)  # bone-local Y is up the body; only root lifts
                pb.keyframe_insert("rotation_euler", frame=f)
                pb.keyframe_insert("scale", frame=f)
                if pb.name == "root":
                    pb.keyframe_insert("location", frame=f)

    R0 = lambda **k: k
    # forward = +X rotation (top goes -Y); jaw +X opens
    clip("idle", 60, {
        1: {"spine_mid": (0, 0, 0, 1, 1, 1, 0)},
        16: {"spine_lo": (1.5, 0, 1.5, 1.02, 1.02, 0.99, 0), "spine_mid": (0, 0, 0, 1.03, 1.03, 0.98, 0), "spine_hi": (-1, 0, -1, 1.02, 1.02, 1.02, 0)},
        31: {"spine_lo": (0, 0, 0, 1, 1, 1, 0), "spine_mid": (0, 0, 0, 1, 1, 1, 0), "jaw": (3, 0, 0, 1, 1, 1, 0)},
        46: {"spine_lo": (1.5, 0, -1.5, 1.02, 1.02, 0.99, 0), "spine_mid": (0, 0, 0, 1.03, 1.03, 0.98, 0), "spine_hi": (-1, 0, 1, 1.02, 1.02, 1.02, 0)},
        61: {"spine_mid": (0, 0, 0, 1, 1, 1, 0)}}, loop=True)
    clip("slide", 40, {
        1: {"spine_lo": (9, 0, 0, 0.97, 0.97, 1.05, 0), "spine_mid": (6, 0, 0, 1, 1, 1.03, 0), "spine_hi": (-3, 0, 2, 1, 1, 1, 0.02)},
        11: {"spine_lo": (6, 0, 2, 1.03, 1.03, 0.96, 0), "spine_mid": (4, 0, 2, 1.02, 1.02, 0.98, 0), "spine_hi": (-2, 0, 0, 1, 1, 1, 0)},
        21: {"spine_lo": (9, 0, 0, 0.97, 0.97, 1.05, 0), "spine_mid": (6, 0, 0, 1, 1, 1.03, 0), "spine_hi": (-3, 0, -2, 1, 1, 1, 0.02)},
        31: {"spine_lo": (6, 0, -2, 1.03, 1.03, 0.96, 0), "spine_mid": (4, 0, -2, 1.02, 1.02, 0.98, 0), "spine_hi": (-2, 0, 0, 1, 1, 1, 0)},
        41: {"spine_lo": (9, 0, 0, 0.97, 0.97, 1.05, 0), "spine_mid": (6, 0, 0, 1, 1, 1.03, 0), "spine_hi": (-3, 0, 2, 1, 1, 1, 0.02)}}, loop=True)
    clip("mouth_open", 30, {
        1: {}, 12: {"spine_hi": (-8, 0, 0, 1, 1, 1.03, 0), "jaw": (34, 0, 0, 1, 1, 1, 0)},
        30: {"spine_hi": (-8, 0, 0, 1, 1, 1.03, 0), "jaw": (34, 0, 0, 1, 1, 1, 0)}})
    clip("bite", 45, {
        1: {},
        10: {"spine_lo": (-4, 0, 0, 1.02, 1.02, 0.98, 0), "spine_hi": (-12, 0, 0, 1, 1, 1, 0), "jaw": (38, 0, 0, 1, 1, 1, 0)},
        16: {"spine_lo": (10, 0, 0, 0.97, 0.97, 1.06, 0), "spine_mid": (8, 0, 0, 1, 1, 1.04, 0), "spine_hi": (10, 0, 0, 1, 1, 1, 0), "jaw": (36, 0, 0, 1, 1, 1, 0)},
        20: {"spine_lo": (10, 0, 0, 0.97, 0.97, 1.06, 0), "spine_mid": (8, 0, 0, 1, 1, 1.04, 0), "spine_hi": (10, 0, 0, 1, 1, 1, 0), "jaw": (-2, 0, 0, 1, 1, 1, 0)},
        32: {"spine_lo": (3, 0, 0, 1, 1, 1, 0), "spine_hi": (2, 0, 0, 1, 1, 1, 0), "jaw": (6, 0, 0, 1, 1, 1, 0)},
        45: {}})
    clip("grab", 50, {
        1: {},
        12: {"spine_lo": (-6, 0, 0, 1.02, 1.02, 0.98, 0), "spine_mid": (-4, 0, 0, 1, 1, 1, 0), "spine_hi": (-4, 0, 0, 1, 1, 1, 0), "jaw": (14, 0, 0, 1, 1, 1, 0)},
        30: {"spine_lo": (13, 0, 0, 0.97, 0.97, 1.05, 0), "spine_mid": (9, 0, 0, 0.97, 0.97, 1.05, 0), "spine_hi": (7, 0, 0, 0.97, 0.97, 1.05, 0), "jaw": (26, 0, 0, 1, 1, 1, 0)},
        50: {"spine_lo": (12, 0, 0, 0.96, 0.96, 1.1, 0), "spine_mid": (9, 0, 0, 0.97, 0.97, 1.05, 0), "spine_hi": (6, 0, 0, 0.96, 0.96, 1.1, 0), "jaw": (26, 0, 0, 1, 1, 1, 0)}})
    clip("lift", 40, {
        1: {"spine_lo": (12, 0, 0, 0.96, 0.96, 1.1, 0), "spine_mid": (9, 0, 0, 0.97, 0.97, 1.05, 0), "spine_hi": (6, 0, 0, 0.96, 0.96, 1.1, 0), "jaw": (26, 0, 0, 1, 1, 1, 0)},
        25: {"root": (0, 0, 0, 1, 1, 1, 0.45), "spine_lo": (-8, 0, 0, 1, 1, 1.03, 0), "spine_mid": (-8, 0, 0, 1, 1, 1.03, 0), "spine_hi": (-10, 0, 0, 1, 1, 1.02, 0), "jaw": (36, 0, 0, 1, 1, 1, 0)},
        40: {"root": (0, 0, 0, 1, 1, 1, 0.42), "spine_lo": (-7, 0, 0, 1.0, 1.0, 1.07, 0), "spine_mid": (-7, 0, 0, 1, 1, 1.03, 0), "spine_hi": (-9, 0, 0, 1, 1, 1.02, 0), "jaw": (36, 0, 0, 1, 1, 1, 0)}})
    clip("swallow", 60, {
        1: {"spine_hi": (-12, 0, 0, 1, 1, 1, 0), "jaw": (34, 0, 0, 1, 1, 1, 0)},
        10: {"spine_hi": (-18, 0, 0, 1, 1, 1, 0), "jaw": (-1, 0, 0, 1, 1, 1, 0)},
        22: {"spine_hi": (-18, 0, 0, 1.18, 1.18, 1.1, 0), "jaw": (0, 0, 0, 1, 1, 1, 0)},
        34: {"spine_hi": (-12, 0, 0, 1, 1, 1, 0), "spine_mid": (0, 0, 0, 1.2, 1.2, 1.1, 0)},
        46: {"spine_mid": (0, 0, 0, 1, 1, 1, 0), "spine_lo": (0, 0, 0, 1.18, 1.18, 1.08, 0), "spine_hi": (-4, 0, 0, 1, 1, 1, 0)},
        60: {}})
    clip("flinch", 24, {
        1: {},
        5: {"spine_lo": (-9, 0, 4, 1.06, 1.06, 0.9, 0), "spine_mid": (-8, 0, 3, 1.04, 1.04, 0.94, 0), "spine_hi": (-10, 0, 3, 1, 1, 1, 0), "jaw": (14, 0, 0, 1, 1, 1, 0)},
        14: {"spine_lo": (3, 0, -1, 0.98, 0.98, 1.03, 0), "spine_hi": (2, 0, -1, 1, 1, 1, 0)},
        24: {}})
    clip("die", 75, {
        1: {},
        8: {"spine_lo": (-12, 0, 0, 1.05, 1.05, 0.95, 0), "spine_hi": (-14, 0, 0, 1, 1, 1, 0), "jaw": (30, 0, 0, 1, 1, 1, 0)},
        30: {"root": (0, 0, 0, 1.2, 1.2, 0.6, 0), "spine_lo": (6, 0, 4, 1, 1, 1, 0), "spine_hi": (10, 0, -4, 1, 1, 1, 0), "jaw": (40, 0, 0, 1, 1, 1, 0)},
        75: {"root": (0, 0, 0, 1.75, 1.75, 0.16, 0), "spine_lo": (0, 0, 0, 1, 1, 1, 0), "spine_hi": (4, 0, 0, 1, 1, 1, 0), "jaw": (46, 0, 0, 1, 1, 1, 0)}})
    arm.animation_data.action = None


for suffix, cfg in LODS.items():
    build(cfg, suffix)
