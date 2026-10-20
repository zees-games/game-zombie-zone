"""Builds assets/zombies/zombie_worker.glb: the construction-site zombie, our own variant.

    blender -b --factory-startup --python art-src/zombie_worker.py -- <zombie_basic.glb> <atlas_basic.png> <out dir> [--bake-size=2048] [--sheet]

The skeleton, the skin weights and the clips (walk, run, attack, hit, death, ...) are the Quaternius
Zombie Apocalypse Kit's (CC0 1.0, https://quaternius.com/packs/zombieapocalypsekit.html), through
`tools/build_zombie_models.py`. What is ours: the gear modelled on top of that body (hard hat, hi-vis
vest with reflective bands and a torn hem, backpack, tool belt, knee pads), each piece weighted whole to
one bone, and a new texture: the kit's colours, the gear's paint, dirt and blood splashes, and ambient
occlusion, all baked into one 2048 atlas on a fresh UV layout so the whole body is one mesh, one
material, one draw call. Triangle count stays under 10k.
"""
import bpy, bmesh, sys, os, math, mathutils
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src_glb, atlas_png, out_dir = args[:3]
BAKE = 2048
SHEET = False
for a in args[3:]:
	if a.startswith("--bake-size="):
		BAKE = int(a.split("=")[1])
	if a == "--sheet":
		SHEET = True
os.makedirs(out_dir, exist_ok=True)

CLIPS = {"Crawl": "crawl", "Death": "death", "HitReact": "hit", "Idle": "idle", "Idle_Attack": "attack_idle",
	"Jump": "jump", "Jump_Idle": "jump_idle", "Jump_Land": "jump_land", "Punch": "attack", "Run": "run",
	"Run_Arms": "run_arms", "Run_Attack": "attack_run", "Walk": "walk"}

ENEMY_CLIPS = set(CLIPS.values())
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=src_glb)
arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
body = bpy.data.objects["Body"]
for o in list(bpy.data.objects):
	if o.type == "MESH" and o is not body:
		bpy.data.objects.remove(o, do_unlink=True)


def V(*a):
	return Vector(a)


TORSO = ["Torso", "Abdomen", "Hips", "Neck", "Shoulder.L", "Shoulder.R"]


def band_fit(z0, z1, groups):
	"""Centre and half-extents of the skin between two heights, from the verts the given bones own."""
	z0 -= 0.07; z1 += 0.07  # the kit body is low poly: rings of verts sit ~0.15 apart at the waist
	idx = {g.index for g in body.vertex_groups if g.name in groups}
	pts = []
	for v in body.data.vertices:
		if z0 <= v.co.z <= z1 and any(x.group in idx and x.weight > 0.4 for x in v.groups) and abs(v.co.x) < 0.2:
			pts.append(v.co)
	if not pts:
		print('BANDFIT empty', z0, z1)
		pts = [v.co for v in body.data.vertices if z0 <= v.co.z <= z1 and abs(v.co.x) < 0.2]
	xs = [p.x for p in pts]; ys = [p.y for p in pts]
	return ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2, (max(xs) - min(xs)) / 2, (max(ys) - min(ys)) / 2)


def new_mat(name, colour, rough=0.7, metal=0.0, extra=None):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	b.inputs["Base Color"].default_value = colour
	b.inputs["Roughness"].default_value = rough
	b.inputs["Metallic"].default_value = metal
	return m


def mesh_obj(name, bm_or_obj, mat, bone):
	"""Wrap a bmesh as an object, weight every vertex to one bone (or by height: dict)."""
	if isinstance(bm_or_obj, bmesh.types.BMesh):
		me = bpy.data.meshes.new(name)
		bm_or_obj.to_mesh(me)
		bm_or_obj.free()
		o = bpy.data.objects.new(name, me)
		scene.collection.objects.link(o)
	else:
		o = bm_or_obj
		o.name = name
	o.data.materials.clear()
	o.data.materials.append(mat)
	for p in o.data.polygons:
		p.use_smooth = True
	groups = {}
	for v in o.data.vertices:
		b = bone(v.co) if callable(bone) else bone
		g = groups.get(b) or o.vertex_groups.new(name=b)
		groups[b] = g
		g.add([v.index], 1.0, "REPLACE")
	return o


def ring(cx, cy, rx, ry, z, n=24, gap=0.0, rot=0.0):
	pts = []
	for i in range(n):
		a = 2 * math.pi * i / n
		pts.append(V(cx + rx * math.cos(a), cy + ry * math.sin(a), z))
	return pts


def loft(rings, close=True, gap_front=0.0):
	"""Quads between consecutive rings; a gap leaves the front (-Y) open like an unzipped vest."""
	bm = bmesh.new()
	vs = [[bm.verts.new(p) for p in r] for r in rings]
	n = len(rings[0])
	for k in range(len(rings) - 1):
		for i in range(n):
			j = (i + 1) % n
			a = 2 * math.pi * (i + 0.5) / n
			if gap_front > 0 and abs(angle_diff(a, -math.pi / 2)) < gap_front:
				continue
			try:
				bm.faces.new((vs[k][i], vs[k][j], vs[k + 1][j], vs[k + 1][i]))
			except ValueError:
				pass
	bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
	return bm


def angle_diff(a, b):
	return (a - b + math.pi) % (2 * math.pi) - math.pi


def solid(o, t=0.006):
	m = o.modifiers.new("s", "SOLIDIFY"); m.thickness = t; m.offset = 1
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.modifier_apply(modifier="s")
	return o


def bevel(o, w=0.003, seg=2):
	m = o.modifiers.new("b", "BEVEL"); m.width = w; m.segments = seg; m.limit_method = "ANGLE"; m.angle_limit = math.radians(40)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.modifier_apply(modifier="b")
	return o


def box_bm(size, loc, rot=(0, 0, 0)):
	bm = bmesh.new()
	bmesh.ops.create_cube(bm, size=1.0)
	bmesh.ops.scale(bm, vec=size, verts=bm.verts)
	bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=mathutils.Euler(rot).to_matrix())
	bmesh.ops.translate(bm, vec=loc, verts=bm.verts)
	return bm


def cyl_bm(r, depth, loc, rot=(0, 0, 0), n=16):
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=n, radius1=r, radius2=r, depth=depth)
	bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=mathutils.Euler(rot).to_matrix())
	bmesh.ops.translate(bm, vec=loc, verts=bm.verts)
	return bm


def merge_bm(*bms):
	out = bmesh.new()
	for b in bms:
		me = bpy.data.meshes.new("t"); b.to_mesh(me); b.free()
		out.from_mesh(me)
		bpy.data.meshes.remove(me)
	return out


VEST = new_mat("Vest", (0.95, 0.38, 0.03, 1), 0.8)
REFL = new_mat("Reflect", (0.72, 0.74, 0.7, 1), 0.35, 0.3)
HAT = new_mat("Hat", (0.95, 0.72, 0.05, 1), 0.45)
CANVAS = new_mat("Canvas", (0.22, 0.27, 0.15, 1), 0.9)
LEATHER = new_mat("Leather", (0.28, 0.17, 0.09, 1), 0.7)
RUBBER = new_mat("Rubber", (0.06, 0.06, 0.06, 1), 0.85)
STEEL = new_mat("Steel", (0.5, 0.52, 0.55, 1), 0.4, 0.8)

gear = []

# --- Hard hat -----------------------------------------------------------------------------
hid = body.vertex_groups["Head"].index
hp = [v.co for v in body.data.vertices if any(x.group == hid and x.weight > 0.5 for x in v.groups) and v.co.z > 0.9]
hx0, hx1 = min(p.x for p in hp), max(p.x for p in hp)
hy0, hy1 = min(p.y for p in hp), max(p.y for p in hp)
hz0, hz1 = min(p.z for p in hp), max(p.z for p in hp)
print("HEAD", hx0, hx1, hy0, hy1, hz0, hz1)
ax = sorted(abs(p.x) for p in hp if p.z > hz0 + (hz1 - hz0) * 0.5)  # the ears stick out past the skull: ignore them
hx, hy, hrx, hry = 0.0, (hy0 + hy1) / 2, ax[int(len(ax) * 0.9)] * 1.1, ax[int(len(ax) * 0.9)] * 1.2
hz = hz0 + (hz1 - hz0) * 0.6
bm = bmesh.new()
bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1.0)
bmesh.ops.scale(bm, vec=(hrx * 1.06, hry * 1.06, (hz1 - hz) * 1.25), verts=bm.verts)
bmesh.ops.translate(bm, vec=(hx, hy, hz), verts=bm.verts)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < hz - 0.005], context="VERTS")
cap = bm
brim = bmesh.new()
bmesh.ops.create_cone(brim, cap_ends=True, segments=24, radius1=hrx * 1.12, radius2=hrx * 1.08, depth=0.012)
bmesh.ops.scale(brim, vec=(1.0, 1.15, 1.0), verts=brim.verts)
bmesh.ops.translate(brim, vec=(hx, hy - hry * 0.18, hz + 0.004), verts=brim.verts)
o = mesh_obj("hat", merge_bm(cap, brim), HAT, "Head")
gear.append(bevel(solid(o, 0.004), 0.002))

# --- Vest ---------------------------------------------------------------------------------
levels = [(0.585, "Abdomen"), (0.66, "Abdomen"), (0.74, "Torso"), (0.8, "Torso"), (0.855, "Torso")]
rings = []
for z, _ in levels:
	cx, cy, rx, ry = band_fit(z - 0.03, z + 0.03, TORSO)
	flare = 1.0 + (0.012 if z > 0.7 else 0.03)
	rings.append(ring(cx, cy, rx * flare + 0.012, ry * flare + 0.012, z, 28))
o = mesh_obj("vest", loft(rings, gap_front=0.32), VEST, lambda co: "Abdomen" if co.z < 0.73 else "Torso")
gear.append(bevel(solid(o, 0.007), 0.002))
# Reflective bands: thin rings standing 3 mm proud of the vest, and two straps up the front.
bands = []
for z in (0.64, 0.715):
	cx, cy, rx, ry = band_fit(z - 0.03, z + 0.03, TORSO)
	f = 1.0 + (0.012 if z > 0.7 else 0.03)
	bands.append(loft([ring(cx, cy, rx * f + 0.0195, ry * f + 0.0195, z - 0.012, 28), ring(cx, cy, rx * f + 0.0195, ry * f + 0.0195, z + 0.012, 28)], gap_front=0.32))
o = mesh_obj("bands", merge_bm(*bands), REFL, lambda co: "Abdomen" if co.z < 0.73 else "Torso")
gear.append(solid(o, 0.002))
cx, cy, rx, ry = band_fit(0.7, 0.8, TORSO)
straps = []
for sx in (-1, 1):
	straps.append(box_bm((0.034, 0.008, 0.2), (cx + sx * 0.062, cy - ry - 0.022, 0.74), (0, 0, 0)))
	straps.append(box_bm((0.034, ry * 2 + 0.05, 0.012), (cx + sx * 0.068, cy, 0.862)))
	straps.append(box_bm((0.034, 0.008, 0.23), (cx + sx * 0.062, cy + ry + 0.022, 0.74), (0, 0, 0)))
o = mesh_obj("straps", merge_bm(*straps), REFL, "Torso")
gear.append(bevel(o, 0.002))
# Torn hem: strips hanging below the vest, they swing with the hips.
hem = []
for i in range(9):
	a = 2 * math.pi * i / 9 + 0.3
	if abs(angle_diff(a, -math.pi / 2)) < 0.4:
		continue
	cx2, cy2, rx2, ry2 = band_fit(0.55, 0.6, TORSO)
	p = V(cx2 + (rx2 + 0.03) * math.cos(a), cy2 + (ry2 + 0.03) * math.sin(a), 0.565)
	length = 0.05 + 0.03 * ((i * 37) % 5) / 4
	hem.append(box_bm((0.028, 0.004, length), (p.x, p.y, p.z - length / 2), (0, 0, a + math.pi / 2)))
o = mesh_obj("hem", merge_bm(*hem), VEST, "Hips")
gear.append(o)

# --- Backpack -----------------------------------------------------------------------------
bk = []
by = cy + ry + 0.075
bk.append(box_bm((0.2, 0.09, 0.24), (cx, by, 0.745)))
bk.append(box_bm((0.17, 0.05, 0.1), (cx, by + 0.065, 0.69)))
bk.append(box_bm((0.19, 0.095, 0.045), (cx, by, 0.875)))
bk.append(cyl_bm(0.028, 0.16, (cx + 0.115, by, 0.745), (0, 0, 0), 12))
bk.append(box_bm((0.012, 0.012, 0.3), (cx - 0.07, cy + ry + 0.03, 0.75)))
bk.append(box_bm((0.012, 0.012, 0.3), (cx + 0.07, cy + ry + 0.03, 0.75)))
o = mesh_obj("backpack", merge_bm(*bk), CANVAS, "Torso")
gear.append(bevel(o, 0.006, 2))

# --- Tool belt ----------------------------------------------------------------------------
cx3, cy3, rx3, ry3 = band_fit(0.5, 0.58, TORSO)
belt = loft([ring(cx3, cy3, rx3 + 0.016, ry3 + 0.016, 0.535, 28), ring(cx3, cy3, rx3 + 0.016, ry3 + 0.016, 0.57, 28)])
pouches = [belt]
for a in (0.25, 0.9, 2.2, 3.4, 4.3):
	px = cx3 + (rx3 + 0.03) * math.cos(a); py = cy3 + (ry3 + 0.03) * math.sin(a)
	pouches.append(box_bm((0.05, 0.03, 0.06), (px, py, 0.52), (0, 0, a + math.pi / 2)))
o = mesh_obj("belt", merge_bm(*pouches), LEATHER, "Hips")
gear.append(bevel(solid(o, 0.006), 0.002))
tool = merge_bm(box_bm((0.012, 0.012, 0.13), (cx3 + rx3 + 0.045, cy3 - 0.03, 0.46)), box_bm((0.05, 0.02, 0.03), (cx3 + rx3 + 0.045, cy3 - 0.03, 0.535)))
o = mesh_obj("hammer", tool, STEEL, "Hips")
gear.append(bevel(o, 0.002))

# --- Knee pads ----------------------------------------------------------------------------
pads = []
for side in ("L", "R"):
	b = arm.data.bones["UpperLeg." + side]
	kx, ky, kz = b.tail_local
	pad = merge_bm(box_bm((0.075, 0.03, 0.085), (kx, ky - 0.06, kz + 0.005)), box_bm((0.082, 0.022, 0.03), (kx, ky - 0.075, kz + 0.04)))
	o = mesh_obj("pad" + side, pad, RUBBER, "LowerLeg." + side)
	gear.append(bevel(o, 0.008, 2))

# --- Grime on every material, then the bake -----------------------------------------------------
atlas = bpy.data.images.load(atlas_png)
SKIN = new_mat("Skin", (0.5, 0.6, 0.4, 1), 0.7)
nt = SKIN.node_tree
tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = atlas; tex.interpolation = "Closest"
uvn = nt.nodes.new("ShaderNodeUVMap"); uvn.uv_map = "UVMap"
nt.links.new(uvn.outputs["UV"], tex.inputs["Vector"])
nt.links.new(tex.outputs["Color"], next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"])
body.data.materials.clear()
body.data.materials.append(SKIN)


def grime(m, blood_amount=0.0):
	nt = m.node_tree
	bs = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
	src = bs.inputs["Base Color"]
	base_link = src.links[0].from_socket if src.links else None
	base_val = tuple(src.default_value)
	co = nt.nodes.new("ShaderNodeTexCoord")
	n1 = nt.nodes.new("ShaderNodeTexNoise"); n1.inputs["Scale"].default_value = 9; n1.inputs["Detail"].default_value = 9
	n2 = nt.nodes.new("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = 60; n2.inputs["Detail"].default_value = 3
	vor = nt.nodes.new("ShaderNodeTexVoronoi"); vor.inputs["Scale"].default_value = 14
	r1 = nt.nodes.new("ShaderNodeValToRGB"); r1.color_ramp.elements[0].position = 0.38; r1.color_ramp.elements[0].color = (0.45, 0.4, 0.33, 1)
	r1.color_ramp.elements[1].position = 0.62; r1.color_ramp.elements[1].color = (1, 1, 1, 1)
	r2 = nt.nodes.new("ShaderNodeValToRGB"); r2.color_ramp.elements[0].position = 0.4; r2.color_ramp.elements[1].position = 0.55
	r2.color_ramp.elements[0].color = (0.82, 0.82, 0.82, 1); r2.color_ramp.elements[1].color = (1, 1, 1, 1)
	rb = nt.nodes.new("ShaderNodeValToRGB"); rb.color_ramp.elements[0].position = 0.0; rb.color_ramp.elements[1].position = 0.12
	rb.color_ramp.elements[0].color = (1, 1, 1, 1); rb.color_ramp.elements[1].color = (0.35, 0.03, 0.02, 1)
	rb.color_ramp.elements[0].color = (0.35, 0.03, 0.02, 1); rb.color_ramp.elements[1].color = (1, 1, 1, 1)
	rb.color_ramp.elements[0].position = 0.1; rb.color_ramp.elements[1].position = 0.18
	geo = nt.nodes.new("ShaderNodeNewGeometry")
	edge = nt.nodes.new("ShaderNodeValToRGB"); edge.color_ramp.elements[0].position = 0.42; edge.color_ramp.elements[1].position = 0.55
	edge.color_ramp.elements[0].color = (0.72, 0.62, 0.5, 1); edge.color_ramp.elements[1].color = (1, 1, 1, 1)
	mix1 = nt.nodes.new("ShaderNodeMix"); mix1.data_type = "RGBA"; mix1.blend_type = "MULTIPLY"; mix1.inputs["Factor"].default_value = 1.0
	mix2 = nt.nodes.new("ShaderNodeMix"); mix2.data_type = "RGBA"; mix2.blend_type = "MULTIPLY"; mix2.inputs["Factor"].default_value = 1.0
	mix3 = nt.nodes.new("ShaderNodeMix"); mix3.data_type = "RGBA"; mix3.blend_type = "MULTIPLY"; mix3.inputs["Factor"].default_value = 1.0
	mix4 = nt.nodes.new("ShaderNodeMix"); mix4.data_type = "RGBA"; mix4.blend_type = "MULTIPLY"; mix4.inputs["Factor"].default_value = blood_amount
	l = nt.links
	l.new(co.outputs["Object"], n1.inputs["Vector"]); l.new(co.outputs["Object"], n2.inputs["Vector"]); l.new(co.outputs["Object"], vor.inputs["Vector"])
	l.new(n1.outputs["Fac"], r1.inputs["Fac"]); l.new(n2.outputs["Fac"], r2.inputs["Fac"]); l.new(vor.outputs["Distance"], rb.inputs["Fac"])
	l.new(geo.outputs["Pointiness"], edge.inputs["Fac"])
	if base_link:
		l.new(base_link, mix1.inputs["A"])
	else:
		mix1.inputs["A"].default_value = base_val
	l.new(r1.outputs["Color"], mix1.inputs["B"])
	l.new(mix1.outputs["Result"], mix2.inputs["A"]); l.new(r2.outputs["Color"], mix2.inputs["B"])
	l.new(mix2.outputs["Result"], mix3.inputs["A"]); l.new(edge.outputs["Color"], mix3.inputs["B"])
	l.new(mix3.outputs["Result"], mix4.inputs["A"]); l.new(rb.outputs["Color"], mix4.inputs["B"])
	l.new(mix4.outputs["Result"], src)


for m, blood in ((SKIN, 0.9), (VEST, 0.8), (REFL, 0.5), (HAT, 0.4), (CANVAS, 0.5), (LEATHER, 0.3), (RUBBER, 0.2), (STEEL, 0.3)):
	grime(m, blood)

# Armature on every gear piece (rest pose binds), then one mesh.
for g in gear:
	g.parent = arm
	mod = g.modifiers.new("Armature", "ARMATURE"); mod.object = arm
bpy.ops.object.select_all(action="DESELECT")
for o in [body] + gear:
	o.select_set(True)
	if "Bake" not in o.data.uv_layers:
		o.data.uv_layers.new(name="Bake")
	o.data.uv_layers["Bake"].active = True
bpy.context.view_layer.objects.active = body
# Bake while the pieces are still separate objects: each keeps its own paint.
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
bpy.ops.uv.pack_islands(margin=0.003)
bpy.ops.object.mode_set(mode="OBJECT")
for o in [body] + gear:
	o.data.uv_layers["Bake"].active_render = True

img = bpy.data.images.new("worker_albedo", BAKE, BAKE)
ao = bpy.data.images.new("worker_ao", BAKE, BAKE)
targets = {}
for o in [body] + gear:
	for m in o.data.materials:
		tn = m.node_tree.nodes.new("ShaderNodeTexImage"); tn.image = img
		targets[(o.name, m.name)] = tn
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
try:
	p = bpy.context.preferences.addons["cycles"].preferences
	p.compute_device_type = "OPTIX"; p.get_devices()
	for d in p.devices:
		d.use = True
	scene.cycles.device = "GPU"
except Exception as e:
	print("no GPU", e)


def set_target(image):
	for (_, mn), tn in targets.items():
		tn.image = image
	for o in [body] + gear:
		for m in o.data.materials:
			m.node_tree.nodes.active = next(n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image == image)


bpy.ops.object.select_all(action="DESELECT")
for o in [body] + gear:
	o.select_set(True)
bpy.context.view_layer.objects.active = body
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
scene.render.bake.margin = 6
set_target(img)
bpy.ops.object.bake(type="DIFFUSE")
set_target(ao)
scene.cycles.samples = 96
bpy.ops.object.bake(type="AO")
px = list(img.pixels); pa = list(ao.pixels)
for i in range(0, len(px), 4):
	k = 0.38 + 0.62 * pa[i]
	px[i] *= k; px[i + 1] *= k; px[i + 2] *= k
img.pixels = px
img.filepath_raw = os.path.join(out_dir, "worker_albedo.png")
img.file_format = "PNG"
img.save()

# One mesh, one material.
final = bpy.data.materials.new("Atlas")
final.use_nodes = True
fb = next(n for n in final.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
ti = final.node_tree.nodes.new("ShaderNodeTexImage"); ti.image = bpy.data.images.load(img.filepath_raw)
final.node_tree.links.new(ti.outputs["Color"], fb.inputs["Base Color"])
fb.inputs["Roughness"].default_value = 0.75
for o in gear:
	o.parent = None
	for mod in list(o.modifiers):
		if mod.type == "ARMATURE":
			o.modifiers.remove(mod)
for o in [body] + gear:
	o.data.materials.clear()
	o.data.materials.append(final)
	o.data.uv_layers.remove(o.data.uv_layers["UVMap"]) if "UVMap" in o.data.uv_layers else None
bpy.ops.object.select_all(action="DESELECT")
for o in [body] + gear:
	o.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Body"
tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
print("WORKER tris", tris)

# Wear: the kit's three noise fields in vertex colours (R grime, G blood, B rot), same as the kit bodies,
# because the view's shader reads them for its per-zombie dirt threshold.
for old in list(body.data.color_attributes):
	body.data.color_attributes.remove(old)
attr = body.data.color_attributes.new("Wear", "BYTE_COLOR", "POINT")
def n01(p, s, o):
	return max(0.0, min(1.0, 0.5 + 0.5 * mathutils.noise.noise(p * s + o)))
for v in body.data.vertices:
	attr.data[v.index].color = (n01(v.co, 3.0, V(1.3, 7.1, 2.9)), n01(v.co, 4.5, V(9.2, 3.3, 5.7)), n01(v.co, 2.0, V(4.4, 8.8, 0.6)), 1.0)
body.data.color_attributes.active_color = attr

# Clips, named as the game expects.
for a in list(bpy.data.actions):
	a.name = a.name.replace("_CharacterArmature", "")

if SHEET:
	# Render from the rest pose and two clip frames, then restore.
	bpy.ops.mesh.primitive_plane_add(size=6, location=(0, 0, 0))
	fl = bpy.context.object
	fl.data.materials.append(new_mat("Floor", (0.18, 0.18, 0.18, 1), 0.9))
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
	cam.data.lens = 70
	s = bpy.data.lights.new("sun", "SUN"); s.energy = 3.5
	so = bpy.data.objects.new("sun", s); so.rotation_euler = (math.radians(50), 0, math.radians(-30)); scene.collection.objects.link(so)
	w = bpy.data.worlds.new("w"); w.use_nodes = True; scene.world = w
	w.node_tree.nodes["Background"].inputs[0].default_value = (0.4, 0.45, 0.55, 1)
	scene.render.resolution_x = 700; scene.render.resolution_y = 900
	scene.cycles.samples = 48
	arm.animation_data_create()

	def shot(name, ang, dist=3.3, z=0.62):
		r = math.radians(ang)
		cam.location = (math.sin(r) * dist, -math.cos(r) * dist, z + 0.2)
		cam.rotation_euler = (Vector((0, 0, z)) - cam.location).to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = os.path.join(out_dir, "worker_%s.png" % name)
		bpy.ops.render.render(write_still=True)

	for nm, ang in (("front", 180), ("back", 0), ("side", 90), ("quarter", 135)):
		shot(nm, ang)
	for clip, frame, nm in (("walk", 6, "walk"), ("attack", 8, "attack"), ("death", 14, "death")):
		arm.animation_data.action = bpy.data.actions[clip]
		scene.frame_set(frame)
		shot(nm, 140)
	arm.animation_data.action = None
	scene.frame_set(1)
	bpy.data.objects.remove(fl, do_unlink=True)

# Export: clips as NLA tracks (the game finds them by name), same options as the kit bodies.
if arm.animation_data is None:
	arm.animation_data_create()
arm.animation_data.action = None
for t in list(arm.animation_data.nla_tracks):
	arm.animation_data.nla_tracks.remove(t)
for a in bpy.data.actions:
	if a.name in CLIPS.values() or a.name in ENEMY_CLIPS:
		tr = arm.animation_data.nla_tracks.new(); tr.name = a.name
		tr.strips.new(a.name, int(a.frame_range[0]), a)
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True); arm.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "zombie_worker.glb"), export_format="GLB", use_selection=True,
	export_yup=True, export_texcoords=True, export_normals=True, export_vertex_color="ACTIVE",
	export_materials="EXPORT", export_animations=True, export_animation_mode="NLA_TRACKS",
	export_skins=True, export_morph=False, export_def_bones=False, export_image_format="NONE")
print("WORKER OK")
