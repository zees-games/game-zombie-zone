"""Builds assets/zombies/zombie_city.glb and its two textures: a realistic common infected.

    blender -b --factory-startup --python art-src/zombie_city.py -- <zombie_basic.glb> <city dir> <out dir> [--tris=9000] [--size=1024]

The mesh and its textures are "Male City Zombie" (CC0, https://opengameart.org/node/111870): a 24k-polygon
anatomical body with a torn outfit and the damage painted in. `<city dir>` is the unpacked archive
(`InfectedCityMan.fbx` and its PNGs). Not vendored; the licence is on the page.

What is ours: that mesh decimated to about 9k triangles and baked (base colour and tangent normal map, from
the full mesh) into one 1024 map each, so the body is one surface and one draw call; and the skeleton, which
is the family's zombie rig (`zombie_basic.glb`: same bone names, same clips) re-fitted to this body's joints
so the clips play on realistic proportions. The kit's body is a third head, short legs; this one is not, so
the rig is moved, not the mesh squeezed. The kit's clip translations are scaled with the rig.
"""
import bpy, bmesh, sys, os, math, mathutils
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:]
src_glb, city_dir, out_dir = args[:3]
TRIS = 9000
SIZE = 1024
for a in args[3:]:
	if a.startswith("--tris="):
		TRIS = int(a.split("=")[1])
	if a.startswith("--size="):
		SIZE = int(a.split("=")[1])
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

# ---- The city man ----
bpy.ops.import_scene.fbx(filepath=os.path.join(city_dir, "InfectedCityMan.fbx"))
carm = next(o for o in bpy.data.objects if o.type == "ARMATURE" and o is not rig)
hi = next(o for o in bpy.data.objects if o.type == "MESH")
joints = {}
for b in carm.data.bones:
	joints[b.name.split(":")[-1]] = (carm.matrix_world @ b.head_local, carm.matrix_world @ b.tail_local)
bpy.ops.object.select_all(action="DESELECT")
hi.select_set(True)
bpy.context.view_layer.objects.active = hi
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for m in list(hi.modifiers):
	hi.modifiers.remove(m)
bpy.data.objects.remove(carm, do_unlink=True)
for g in hi.vertex_groups:
	g.name = g.name.split(":")[-1]


def wire(mesh):
	"""The shipped PNGs onto the importer's bare materials, by name."""
	pairs = {"City_Man_Infected_Outfit1": "InfectedCityMan_City_Man_Infected_Outfit1_",
		"City_Infected_Man_Body1": "InfectedCityMan_City_Infected_Man_Body1_"}
	for m in mesh.data.materials:
		pre = pairs.get(m.name)
		if not pre:
			continue
		nt = m.node_tree
		b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")

		def img(s, cs):
			n = nt.nodes.new("ShaderNodeTexImage")
			n.image = bpy.data.images.load(os.path.join(city_dir, pre + s + ".png"))
			n.image.colorspace_settings.name = cs
			return n
		nt.links.new(img("BaseColor", "sRGB").outputs["Color"], b.inputs["Base Color"])
		nn = next(n for n in nt.nodes if n.type == "NORMAL_MAP")
		nt.links.new(img("Normal", "Non-Color").outputs["Color"], nn.inputs["Color"])
		nt.links.new(nn.outputs["Normal"], b.inputs["Normal"])


wire(hi)

# ---- The low mesh: decimated, new UVs, baked ----
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
dec.ratio = TRIS / float(len(lo.data.polygons))
dec.use_collapse_triangulate = True
bpy.ops.object.modifier_apply(modifier="Decimate")
print("CITY tris", len(lo.data.polygons), "from", len(hi.data.polygons))
# Clearing the slots for a bake resets every face to slot 0, so the slot of each face is kept here.
slot_of = [p.material_index for p in lo.data.polygons]

for uv in list(lo.data.uv_layers):
	lo.data.uv_layers.remove(uv)
lo.data.uv_layers.new(name="UVMap")
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


albedo = bake("DIFFUSE", "city_albedo", "sRGB")

# The source colours are Voronoi smears (a dim, red-brown body), so the colour is repainted from this raw bake and
# the masks below by art-src/zombie_city_paint.py; the raw bake only says where the wounds and the folds are.
albedo.filepath_raw = os.path.join(out_dir, "city_raw.png")
albedo.save()

head_j, head_t = joints["Head"]
toe_j = joints["LeftToeBase"][1]
front = 1.0 if toe_j.y > joints["LeftFoot"][0].y else -1.0
hh = max(head_t.z - head_j.z, 0.05)
extremity = [i for i, g in enumerate(lo.vertex_groups) if any(k in g.name for k in ("Hand", "Foot", "Toe"))]
head_group = [i for i, g in enumerate(lo.vertex_groups) if g.name in ("Head", "HeadTop_End")]
head_v = [v.co for v in lo.data.vertices if sum(g.weight for g in v.groups if g.group in head_group) > 0.5]
front_v = [c for c in head_v if (c.y - head_j.y) * front > 0.0]
chin = min(c.z for c in front_v)
crown = max(c.z for c in head_v)
fh = crown - chin
eye_z, mouth_z = chin + 0.52 * fh, chin + 0.2 * fh
head_x = sum(c.x for c in head_v) / len(head_v)
print("CITY head chin %.3f crown %.3f x %.3f" % (chin, crown, head_x))
body_slot = [i for i, m in enumerate(hi.data.materials) if m and "Body" in m.name]
top_z = max(v.co.z for v in lo.data.vertices)
ma = lo.data.color_attributes.new("MaskA", "FLOAT_COLOR", "CORNER")
lo.data.color_attributes.new("MaskB", "FLOAT_COLOR", "CORNER")
lo.data.color_attributes.new("MaskC", "FLOAT_COLOR", "CORNER")
ma = lo.data.color_attributes["MaskA"]
mb = lo.data.color_attributes["MaskB"]
mc = lo.data.color_attributes["MaskC"]
for poly in lo.data.polygons:
	skin = 1.0 if slot_of[poly.index] in body_slot else (0.5 if slot_of[poly.index] == 2 else 0.0)
	for li in poly.loop_indices:
		v = lo.data.vertices[lo.data.loops[li].vertex_index]
		co = v.co
		hw = sum(g.weight for g in v.groups if g.group in head_group)
		ew = sum(g.weight for g in v.groups if g.group in extremity)
		rel = (co.z - head_j.z) / hh
		fwd = (co.y - head_j.y) * front / (0.5 * hh)
		scalp = 1.0 if (hw > 0.5 and rel > 0.62 and (fwd < 0.2 or rel > 0.8)) else 0.0
		face = 1.0 if (hw > 0.5 and fwd > 0.2 and 0.1 < rel < 0.75) else 0.0
		ma.data[li].color = (skin, min(max(co.z / top_z, 0.0), 1.0), scalp, 1.0)
		infront = (co.y - head_j.y) * front > 0.0 and hw > 0.5
		dx = co.x - head_x
		eyes = 0.0
		if infront:
			for sx in (-1.0, 1.0):
				d = ((dx - sx * 0.17 * fh) / (0.1 * fh)) ** 2 + ((co.z - eye_z) / (0.07 * fh)) ** 2
				eyes = max(eyes, math.exp(-d))
		mouth = math.exp(-((dx / (0.2 * fh)) ** 2 + ((co.z - mouth_z) / (0.06 * fh)) ** 2)) if infront else 0.0
		mc.data[li].color = (eyes, mouth, min(abs(co.x) / 0.9, 1.0), 1.0)
		mb.data[li].color = (face, min(ew, 1.0), min(abs(co.x) / 0.9, 1.0), 1.0)


def bake_attr(attr, name):
	img = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
	img.colorspace_settings.name = "Non-Color"
	mat = bpy.data.materials.new("Mask_" + name)
	mat.use_nodes = True
	nt = mat.node_tree
	for n in list(nt.nodes):
		nt.nodes.remove(n)
	col = nt.nodes.new("ShaderNodeVertexColor")
	col.layer_name = attr
	em = nt.nodes.new("ShaderNodeEmission")
	out = nt.nodes.new("ShaderNodeOutputMaterial")
	nt.links.new(col.outputs["Color"], em.inputs["Color"])
	nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
	node = nt.nodes.new("ShaderNodeTexImage")
	node.image = img
	nt.nodes.active = node
	old = list(lo.data.materials)
	lo.data.materials.clear()
	lo.data.materials.append(mat)
	bpy.ops.object.select_all(action="DESELECT")
	lo.select_set(True)
	bpy.context.view_layer.objects.active = lo
	scene.render.bake.use_selected_to_active = False
	bpy.ops.object.bake(type="EMIT")
	scene.render.bake.use_selected_to_active = True
	img.filepath_raw = os.path.join(out_dir, name + ".png")
	img.file_format = "PNG"
	img.save()
	lo.data.materials.clear()
	for m in old:
		lo.data.materials.append(m)


bake_attr("MaskA", "city_mask_a")
bake_attr("MaskB", "city_mask_b")
bake_attr("MaskC", "city_mask_c")

lo.data.materials.clear()
for m in list(hi.data.materials):
	lo.data.materials.append(m)
normal = bake("NORMAL", "city_normal", "Non-Color")

final = bpy.data.materials.new("City")
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

# ---- Weights: the city rig's groups onto the family's bones ----
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
J = joints
f = J["Hips"][0].z / rig_rest["Hips"][0].z
dy = rig_rest["Hips"][0].y * f - J["Hips"][0].y


def P(v):
	return Vector((v.x, v.y + dy, v.z))


T = {}
T["Hips"] = (J["Hips"][0], J["Spine"][0])
T["Abdomen"] = (J["Spine"][0], J["Spine1"][1])
T["Torso"] = (J["Spine1"][1], J["Neck"][0])
T["Neck"] = (J["Neck"][0], J["Neck"][1])
T["Head"] = (J["Head"][0], J["Head"][1])
for side, tag in (("Left", "L"), ("Right", "R")):
	T["Shoulder." + tag] = J[side + "Shoulder"]
	T["UpperArm." + tag] = J[side + "Arm"]
	T["LowerArm." + tag] = J[side + "ForeArm"]
	T["UpperLeg." + tag] = J[side + "UpLeg"]
	T["LowerLeg." + tag] = J[side + "Leg"]
	for finger, ours in (("Index", "Index"), ("Middle", "Middle"), ("Pinky", "Pinky")):
		h = side + "Hand" + finger
		T["%s1.%s" % (ours, tag)] = (J[h + "1"][0], J[h + "2"][0])
		T["%s2.%s" % (ours, tag)] = (J[h + "2"][0], J[h + "3"][0])
		T["%s3.%s" % (ours, tag)] = (J[h + "3"][0], J[h + "4"][1])
	h = side + "HandThumb"
	T["Thumb1." + tag] = (J[h + "1"][0], J[h + "2"][0])
	T["Thumb2." + tag] = (J[h + "2"][0], J[h + "4"][1])
	# The IK targets stay on the floor under each foot.
	foot = J[side + "Foot"][0]
	toe = J[side + "ToeBase"][1]
	T["Foot." + tag] = (Vector((foot.x, foot.y, 0.02)), Vector((foot.x, toe.y, 0.02)))
	T["PoleTarget." + tag] = (Vector((foot.x, foot.y - 0.7, 0.26 * f)), Vector((foot.x, foot.y - 0.7, 0.41 * f)))
T["Root"] = (Vector((0, J["Hips"][0].y, 0)), Vector((0, J["Hips"][0].y, 0.15 * f)))
T["Body"] = (Vector((0, J["Hips"][0].y, J["Hips"][0].z * 0.99)), Vector((0, J["Hips"][0].y, J["Hips"][0].z * 1.2)))
head0 = rig_rest["Head"][0]
for name in list(rig_rest):
	if name not in T:
		h, t = rig_rest[name]
		T[name] = (J["Head"][0] + (h - head0) * 0.5, J["Head"][0] + (t - head0) * 0.5)

bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t) in T.items():
	eb = rig.data.edit_bones[name]
	eb.head = P(h) if name not in ("Foot.L", "Foot.R", "PoleTarget.L", "PoleTarget.R", "Root", "Body") else h
	eb.tail = P(t) if name not in ("Foot.L", "Foot.R", "PoleTarget.L", "PoleTarget.R", "Root", "Body") else t
bpy.ops.object.mode_set(mode="OBJECT")

# The mesh moves with the joints; the vertices went through the same offset.
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

print("CITY export", [u.name for u in lo.data.uv_layers], [m.name for m in lo.data.materials], [a.name for a in lo.data.color_attributes])
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
rig.select_set(True)
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "zombie_city.glb"), export_format="GLB", use_selection=True,
	export_yup=True, export_texcoords=True, export_normals=True, export_tangents=True, export_vertex_color="ACTIVE",
	export_materials="EXPORT", export_animations=True, export_animation_mode="NLA_TRACKS",
	export_skins=True, export_morph=False, export_def_bones=False, export_image_format="NONE")
print("CITY OK f=%.3f" % f)
