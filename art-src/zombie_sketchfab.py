"""Builds assets/zombies/zombie_<body>.glb and its two textures from a rigged Sketchfab character, on the family's rig.

    blender -b --factory-startup --python art-src/zombie_sketchfab.py -- <zombie_basic.glb> <source.glb> <armature> <body> <out dir> [--skip=glass,hair] [--visor] [--tris=8000] [--size=1024]

Used for the commons `gent`, `cop`, `punk` and `convict` (one armature each of "Animated Zombie Characters Walking Dead
loop" by LasquetiSpice, CC-BY 4.0, https://sketchfab.com/3d-models/animated-zombie-characters-walking-dead-loop-8088449c35634de18cbf531c58544f26)
`hazmat` ("Zombie Hazmat" by LxNazarov, CC-BY, https://sketchfab.com/3d-models/zombie-hazmat-49b3b4307f6a4d2386fdb02354158d04).
Neither archive is vendored; the licence is on each page and in README.md.

What is ours is the same as `zombie_city.py`: the character's meshes joined, decimated and baked (base colour and tangent
normal map, from the full mesh) into one 1024 map each, and the family's rig re-fitted to the character's joints so the
family's clips play on it (the source's own loop is not used). Source bones are Mixamo-named; a finger or toe it lacks is
placed relative to the hand or foot.
"""
import bpy, bmesh, sys, os, math, re, mathutils
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src_glb, char_glb, arm_name, body, out_dir = args[:5]
TRIS = 8000
SIZE = 1024
SKIP = []
VISOR = "--visor" in args
for a in args[5:]:
	if a.startswith("--tris="):
		TRIS = int(a.split("=")[1])
	if a.startswith("--size="):
		SIZE = int(a.split("=")[1])
	if a.startswith("--skip="):
		SKIP = a.split("=")[1].split(",")
os.makedirs(out_dir, exist_ok=True)

CLIPS = {"crawl", "death", "hit", "idle", "attack_idle", "jump", "jump_idle", "jump_land", "attack", "run",
	"run_arms", "attack_run", "walk"}

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---- The target rig (the family's) ----
bpy.ops.import_scene.gltf(filepath=src_glb)
rig = bpy.data.objects["CharacterArmature"]
for o in list(bpy.data.objects):
	if o.type != "ARMATURE":
		bpy.data.objects.remove(o, do_unlink=True)
rig_rest = {b.name: (b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones}
family = set(bpy.data.objects)

# ---- The character ----
bpy.ops.import_scene.gltf(filepath=char_glb)
carm = bpy.data.objects[arm_name]
carm.data.pose_position = "REST"
if carm.animation_data:
	carm.animation_data_clear()
bpy.context.view_layer.update()


def norm(n):
	return re.sub(r"_\d+$", "", n.split(":")[-1])


H = {}
for b in carm.data.bones:
	H[norm(b.name)] = carm.matrix_world @ b.head_local
meshes = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == carm and not any(s in (o.data.materials[0].name if o.data.materials else "") for s in SKIP)]
for o in [o for o in bpy.data.objects if o.type == "MESH" and o.parent == carm and o not in meshes]:
	bpy.data.objects.remove(o, do_unlink=True)
for o in meshes:
	bpy.ops.object.select_all(action="DESELECT")
	o.select_set(True)
	bpy.context.view_layer.objects.active = o
	bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
	bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
	for m in list(o.modifiers):
		o.modifiers.remove(m)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
	o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
	bpy.ops.object.join()
hi = bpy.context.view_layer.objects.active
bpy.data.objects.remove(carm, do_unlink=True)
for g in hi.vertex_groups:
	g.name = norm(g.name)

# Centred under the origin, feet on the floor: joints and mesh move together.
shift = Vector((-H["Hips"].x, 0.0, -min((hi.matrix_world @ v.co).z for v in hi.data.vertices)))
for k in H:
	H[k] = H[k] + shift
for v in hi.data.vertices:
	v.co = v.co + shift


def J(name, fallback=None):
	return H.get(name, fallback)


def seg(a, b):
	return (H[a], H[b])


hip = H["Hips"]
neck_up = H["Head"] - H["Neck"]
crown = max(v.co.z for v in hi.data.vertices if (v.co - H["Head"]).length < 0.4 and v.co.z > H["Head"].z)
head_tail = H.get("HeadTop_End", Vector((H["Head"].x, H["Head"].y, crown)))
print("%s head ratio %.3f height %.3f" % (body, crown / H["Head"].z, crown))

if VISOR:
	# The hazmat hood's visor is glass over a face: a colour bake ignores the transparency and paints it black, so
	# the visor's faces go and the face behind it shows through the hole.
	bm = bmesh.new()
	bm.from_mesh(hi.data)
	cut = [f for f in bm.faces if abs(f.calc_center_median().x - H["Head"].x) < 0.11 and H["Head"].z - 0.03 < f.calc_center_median().z < crown - 0.07
		and H["Head"].y - f.calc_center_median().y > 0.04 and hi.material_slots[f.material_index].name == "HazMatSuit"]
	print("SKF visor faces cut", len(cut))
	bmesh.ops.delete(bm, geom=cut, context="FACES")
	bm.to_mesh(hi.data)
	bm.free()

lo = hi.copy()
lo.data = hi.data.copy()
lo.name = "Body"
scene.collection.objects.link(lo)
bm = bmesh.new()
bm.from_mesh(lo.data)
bmesh.ops.triangulate(bm, faces=bm.faces[:])
bm.to_mesh(lo.data)
bm.free()
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
bpy.context.view_layer.objects.active = lo
dec = lo.modifiers.new("Decimate", "DECIMATE")
dec.ratio = min(1.0, TRIS / float(len(lo.data.polygons)))
dec.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="Decimate")
print("SKF tris", len(lo.data.polygons), "from", len(hi.data.polygons))

# The source materials name UV layers (UVMap.001) that are about to go; the bakes below bring their own.
lo.data.materials.clear()
while len(lo.data.uv_layers) > 1:
	lo.data.uv_layers.remove(lo.data.uv_layers[len(lo.data.uv_layers) - 1])
lo.data.uv_layers[0].name = "UVMap"
lo.data.uv_layers.active_index = 0
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 8
scene.cycles.use_denoising = False
scene.render.bake.use_selected_to_active = True
scene.render.bake.cage_extrusion = 0.02
scene.render.bake.max_ray_distance = 0.05
scene.render.bake.margin = 6
scene.render.bake.use_clear = True
def bake(kind, name, colourspace):
	img = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
	img.colorspace_settings.name = colourspace
	mat = bpy.data.materials.new("Bake_" + name)
	mat.use_nodes = True
	node = mat.node_tree.nodes.new("ShaderNodeTexImage")
	node.image = img
	mat.node_tree.nodes.active = node
	lo.data.materials.clear()
	lo.data.materials.append(mat)
	bpy.ops.object.select_all(action="DESELECT")
	hi.select_set(True)
	lo.select_set(True)
	bpy.context.view_layer.objects.active = lo
	if kind == "DIFFUSE":
		scene.render.bake.use_pass_direct = False
		scene.render.bake.use_pass_indirect = False
		scene.render.bake.use_pass_color = True
		bpy.ops.object.bake(type="DIFFUSE")
	else:
		scene.render.bake.normal_space = "TANGENT"
		bpy.ops.object.bake(type="NORMAL")
	img.filepath_raw = os.path.join(out_dir, name + ".png")
	img.file_format = "PNG"
	img.save()
	return img



albedo = bake("DIFFUSE", body + "_albedo", "sRGB")
lo.data.materials.clear()
for m in list(hi.data.materials):
	lo.data.materials.append(m)
normal = bake("NORMAL", body + "_normal", "Non-Color")

final = bpy.data.materials.new(body)
final.use_nodes = True
nt = final.node_tree
b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
ta = nt.nodes.new("ShaderNodeTexImage")
ta.image = albedo
nt.links.new(ta.outputs["Color"], b.inputs["Base Color"])
tn = nt.nodes.new("ShaderNodeTexImage")
tn.image = normal
nm = nt.nodes.new("ShaderNodeNormalMap")
nt.links.new(tn.outputs["Color"], nm.inputs["Color"])
nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
b.inputs["Roughness"].default_value = 0.8
lo.data.materials.clear()
lo.data.materials.append(final)

# ---- Weights: the character's groups onto the family's bones ----
MAP = {"Hips": "Hips", "Spine": "Abdomen", "Spine1": "Abdomen", "Spine2": "Torso", "Neck": "Neck", "Head": "Head",
	"HeadTop_End": "Head"}
for side, tag in (("Left", "L"), ("Right", "R")):
	MAP.update({side + "Shoulder": "Shoulder." + tag, side + "Arm": "UpperArm." + tag, side + "ForeArm": "LowerArm." + tag,
		side + "Hand": "LowerArm." + tag, side + "UpLeg": "UpperLeg." + tag, side + "Leg": "LowerLeg." + tag,
		side + "Foot": "LowerLeg." + tag, side + "ToeBase": "LowerLeg." + tag, side + "Toe_End": "LowerLeg." + tag})
	for finger, ours in (("Index", "Index"), ("Middle", "Middle"), ("Ring", "Middle"), ("Pinky", "Pinky")):
		for i in range(1, 5):
			MAP[side + "Hand" + finger + str(i)] = "%s%d.%s" % (ours, min(i, 3), tag)
	for i in range(1, 5):
		MAP[side + "HandThumb" + str(i)] = "Thumb%d.%s" % (min(i, 2), tag)

old = {g.index: g.name for g in lo.vertex_groups}
acc = {}
for v in lo.data.vertices:
	w = {}
	for g in v.groups:
		target = MAP.get(old.get(g.group, ""))
		if target:
			w[target] = w.get(target, 0.0) + g.weight
	acc[v.index] = w
lo.vertex_groups.clear()
for name in rig_rest:
	lo.vertex_groups.new(name=name)
for i, w in acc.items():
	total = sum(w.values())
	for name, x in w.items():
		if total > 0.0:
			lo.vertex_groups[name].add([i], x / total, "REPLACE")

# ---- The rig, moved to the body ----
f = hip.z / rig_rest["Hips"][0].z
dy = rig_rest["Hips"][0].y * f - hip.y + 0.0


def P(v):
	return Vector((v.x, v.y + dy, v.z))


T = {}
T["Hips"] = seg("Hips", "Spine")
T["Abdomen"] = seg("Spine", "Spine2")
T["Torso"] = seg("Spine2", "Neck")
T["Neck"] = seg("Neck", "Head")
T["Head"] = (H["Head"], head_tail)
hand_fam = {}
for side, tag in (("Left", "L"), ("Right", "R")):
	T["Shoulder." + tag] = seg(side + "Shoulder", side + "Arm")
	T["UpperArm." + tag] = seg(side + "Arm", side + "ForeArm")
	T["LowerArm." + tag] = seg(side + "ForeArm", side + "Hand")
	T["UpperLeg." + tag] = seg(side + "UpLeg", side + "Leg")
	T["LowerLeg." + tag] = seg(side + "Leg", side + "Foot")
	hand = H[side + "Hand"]
	fam_hand = rig_rest["LowerArm." + tag][1]
	for finger, ours in (("Index", "Index"), ("Middle", "Middle"), ("Pinky", "Pinky")):
		h = side + "Hand" + finger
		if h + "3" in H:
			T["%s1.%s" % (ours, tag)] = seg(h + "1", h + "2")
			T["%s2.%s" % (ours, tag)] = seg(h + "2", h + "3")
			T["%s3.%s" % (ours, tag)] = (H[h + "3"], H[h + "4"] if h + "4" in H else H[h + "3"] + (H[h + "3"] - H[h + "2"]) * 0.8)
	h = side + "HandThumb"
	if h + "3" in H:
		T["Thumb1." + tag] = seg(h + "1", h + "2")
		T["Thumb2." + tag] = (H[h + "2"], H[h + "4"] if h + "4" in H else H[h + "3"] + (H[h + "3"] - H[h + "2"]) * 0.8)
	for name in list(rig_rest):
		if name.endswith("." + tag) and name not in T and re.match(r"(Index|Middle|Pinky|Thumb)\d", name):
			hh, tt = rig_rest[name]
			T[name] = (hand + (hh - fam_hand) * f, hand + (tt - fam_hand) * f)
	foot = H[side + "Foot"]
	toe_h = H[side + "ToeBase"]
	toe = H[side + "Toe_End"] if side + "Toe_End" in H else toe_h + (toe_h - foot) * Vector((0, 1, 0)) * 0.5
	T["Foot." + tag] = (Vector((foot.x, foot.y, 0.02)), Vector((foot.x, toe.y, 0.02)))
	T["PoleTarget." + tag] = (Vector((foot.x, foot.y - 0.7, 0.26 * f)), Vector((foot.x, foot.y - 0.7, 0.41 * f)))
T["Root"] = (Vector((0, hip.y, 0)), Vector((0, hip.y, 0.15 * f)))
T["Body"] = (Vector((0, hip.y, hip.z * 0.99)), Vector((0, hip.y, hip.z * 1.2)))
head0 = rig_rest["Head"][0]
for name in list(rig_rest):
	if name not in T:
		h, t = rig_rest[name]
		T[name] = (H["Head"] + (h - head0) * 0.5, H["Head"] + (t - head0) * 0.5)

bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
RAW = ("Foot.L", "Foot.R", "PoleTarget.L", "PoleTarget.R", "Root", "Body")
for name, (h, t) in T.items():
	eb = rig.data.edit_bones[name]
	eb.head = P(h) if name not in RAW else h
	eb.tail = P(t) if name not in RAW else t
bpy.ops.object.mode_set(mode="OBJECT")

for v in lo.data.vertices:
	v.co = P(v.co)
mod = lo.modifiers.new("Armature", "ARMATURE")
mod.object = rig
lo.parent = rig

# Clip translations were keyed against the kit's body; this one is f times as large.
for a in bpy.data.actions:
	for fc in a.fcurves:
		if fc.data_path.endswith(".location"):
			for k in fc.keyframe_points:
				k.co[1] *= f
				k.handle_left[1] *= f
				k.handle_right[1] *= f

# ---- Wear: the family's three noise fields, which the view's dirt and blood read ----
while len(lo.data.color_attributes):
	lo.data.color_attributes.remove(lo.data.color_attributes[0])
attr = lo.data.color_attributes.new("Wear", "BYTE_COLOR", "POINT")
head_idx = {g.index for g in lo.vertex_groups if g.name in ("Head", "Neck")}


def n01(p, s, o):
	return max(0.0, min(1.0, 0.5 + 0.5 * mathutils.noise.noise(p * s + o)))


for v in lo.data.vertices:
	p = v.co
	g = n01(p, 4.5, Vector((9.2, 3.3, 5.7)))
	top = max(v.groups, key=lambda x: x.weight).group if v.groups else -1
	if top in head_idx:
		g *= 0.72
	attr.data[v.index].color = (n01(p, 3.0, Vector((1.3, 7.1, 2.9))), g, n01(p, 2.0, Vector((4.4, 8.8, 0.6))), 1.0)
lo.data.color_attributes.active_color = attr

bpy.data.objects.remove(hi, do_unlink=True)
for a in list(bpy.data.actions):
	a.name = a.name.replace("_CharacterArmature", "")
	if a.name not in CLIPS:
		bpy.data.actions.remove(a)
if rig.animation_data is None:
	rig.animation_data_create()
rig.animation_data.action = None
for t in list(rig.animation_data.nla_tracks):
	rig.animation_data.nla_tracks.remove(t)
for a in bpy.data.actions:
	tr = rig.animation_data.nla_tracks.new()
	tr.name = a.name
	tr.strips.new(a.name, int(a.frame_range[0]), a)

print("SKF export", [u.name for u in lo.data.uv_layers], [m.name for m in lo.data.materials], [a.name for a in lo.data.color_attributes])
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "zombie_%s.glb" % body), export_format="GLB", use_selection=True,
	export_yup=True, export_texcoords=True, export_normals=True, export_tangents=True, export_vertex_color="ACTIVE",
	export_materials="EXPORT", export_animations=True, export_animation_mode="NLA_TRACKS",
	export_skins=True, export_morph=False, export_def_bones=False, export_image_format="NONE")
print("SKF OK f=%.3f" % f)
