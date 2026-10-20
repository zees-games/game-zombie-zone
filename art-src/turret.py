"""Builds assets/turret/turret.glb: the Turret Box's sentry gun. Our own model; the look reference
(a sci-fi defence-gun pack) was viewed, never downloaded or copied.

    blender -b --factory-startup --python art-src/turret.py -- <out dir> [--bake-size=1024] [--sheet]

Hard-surface, built from bevelled boxes and cylinders (the bevel is what catches light), then:
  - one UV layout over every part, a procedural paint (panel seams, scuffs, hazard stripes, rust
    at the edges) baked to `turret_albedo.png`, and the ambient occlusion baked into the same
    image's multiply, so the model needs no lights to read as solid;
  - the glowing parts keep a separate emissive material (`Glow`), not baked.
Nodes (the game finds them by name): Turret > Base, Head (yaw pivot, at the top of the column) >
Shroud, Gun (pitch pivot) > barrels, Muzzle (an empty at the barrels' mouths, -Z forward).
"""
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out_dir = args[0] if args else "/tmp/turret_out"
BAKE = 1024
SHEET = False
for a in args[1:]:
	if a.startswith("--bake-size="):
		BAKE = int(a.split("=")[1])
	if a == "--sheet":
		SHEET = True
os.makedirs(out_dir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def V(*a):
	return Vector(a)


def mat(name, colour, metal=0.0, rough=0.5, emit=None):
	m = bpy.data.materials.new(name)
	m.use_nodes = True
	b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
	b.inputs["Base Color"].default_value = colour
	b.inputs["Metallic"].default_value = metal
	b.inputs["Roughness"].default_value = rough
	if emit:
		b.inputs["Emission Color"].default_value = emit
		b.inputs["Emission Strength"].default_value = 3.0
	return m


HULL = mat("Hull", (0.30, 0.34, 0.36, 1), 0.6, 0.45)
GLOW = mat("Glow", (0.1, 0.8, 1.0, 1), 0.0, 0.3, (0.1, 0.85, 1.0, 1))


def finish(obj, bevel=0.012, segments=2, material=None):
	if bevel > 0:
		m = obj.modifiers.new("b", "BEVEL")
		m.width = bevel
		m.segments = segments
		m.limit_method = "ANGLE"
		m.angle_limit = math.radians(35)
		bpy.context.view_layer.objects.active = obj
		bpy.ops.object.modifier_apply(modifier="b")
	obj.data.materials.clear()
	obj.data.materials.append(material or HULL)
	bpy.ops.object.shade_smooth()
	return obj


def box(name, size, loc, rot=(0, 0, 0), bevel=0.012, material=None, taper=None):
	bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
	o = bpy.context.object
	o.name = name
	o.scale = size
	bpy.ops.object.transform_apply(scale=True)
	if taper is not None:  # (top x scale, top z scale): narrower top face -> sloped armour
		bm = bmesh.new(); bm.from_mesh(o.data)
		for v in bm.verts:
			if v.co.y > 0:
				v.co.x *= taper[0]; v.co.z *= taper[1]
		bm.to_mesh(o.data); bm.free()
	return finish(o, bevel, 2, material)


def strut(name, a, b, thick=0.07, bevel=0.012):
	a = Vector(a); b = Vector(b)
	d = b - a
	bpy.ops.mesh.primitive_cube_add(size=1, location=(a + b) / 2)
	o = bpy.context.object
	o.name = name
	o.scale = (thick, thick, d.length)
	o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
	bpy.ops.object.transform_apply(scale=True, rotation=True)
	return finish(o, bevel, 2)


def cyl(name, r, depth, loc, rot=(0, 0, 0), verts=24, bevel=0.01, material=None, r2=None):
	if r2 is None:
		bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=loc, rotation=rot)
	else:
		bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, vertices=verts, location=loc, rotation=rot)
	o = bpy.context.object
	o.name = name
	return finish(o, bevel, 2, material)


def join(name, objs, origin):
	bpy.ops.object.select_all(action="DESELECT")
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	bpy.ops.object.join()
	o = bpy.context.object
	o.name = name
	scene.cursor.location = origin
	bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
	return o


X90 = (math.radians(90), 0, 0)   # cylinder axis along Y -> use for barrels (along -Z we rotate X by 90)
# Convention: Blender -Y is forward before export; the glTF exporter maps it to -Z in Godot... Blender +Y forward
# becomes glTF -Z with +Y up export. So the gun points along +Y here.

# ---- Base: plinth, three legs, ammo drum, column ----
parts = []
parts.append(cyl("plinth", 0.62, 0.14, (0, 0, 0.07), verts=8, bevel=0.025))
parts.append(cyl("plinth_top", 0.5, 0.1, (0, 0, 0.19), verts=8, bevel=0.02))
for i in range(3):
	a = math.radians(120 * i + 90)
	d = V(math.cos(a), math.sin(a), 0)
	parts.append(strut("leg%d" % i, d * 0.2 + V(0, 0, 0.95), d * 0.95 + V(0, 0, 0.06), 0.09))
	parts.append(strut("leg_in%d" % i, d * 0.3 + V(0, 0, 0.5), d * 0.7 + V(0, 0, 0.12), 0.05))
	parts.append(box("foot%d" % i, (0.3, 0.26, 0.07), d * 0.98 + V(0, 0, 0.035), (0, 0, a - math.pi / 2), 0.02))
	parts.append(box("spike%d" % i, (0.05, 0.12, 0.05), d * 1.14 + V(0, 0, 0.03), (0, 0, a - math.pi / 2), 0.008))
parts.append(cyl("column", 0.16, 0.7, (0, 0, 0.6), verts=16, bevel=0.015))
parts.append(cyl("column_ring", 0.21, 0.06, (0, 0, 0.35), verts=16, bevel=0.012))
parts.append(cyl("column_ring2", 0.21, 0.06, (0, 0, 0.88), verts=16, bevel=0.012))
parts.append(cyl("turntable", 0.3, 0.08, (0, 0, 0.98), verts=24, bevel=0.015))
# ammo drum on the back leg side
parts.append(cyl("drum", 0.22, 0.34, (0.0, -0.42, 0.42), (0, math.radians(90), 0), 20, 0.02))
parts.append(cyl("drum_cap", 0.17, 0.05, (0.19, -0.42, 0.42), (0, math.radians(90), 0), 20, 0.01))
parts.append(cyl("drum_cap2", 0.17, 0.05, (-0.19, -0.42, 0.42), (0, math.radians(90), 0), 20, 0.01))
parts.append(box("drum_clamp", (0.4, 0.06, 0.1), (0, -0.42, 0.66), (0, 0, 0), 0.012))
base = join("Base", parts, (0, 0, 0))

# ---- Head: shroud on the turntable (pivot (0,0,1.02)) ----
P = Vector((0, 0, 1.02))
hp = []
hp.append(box("shroud", (0.62, 0.78, 0.34), P + Vector((0, 0.02, 0.26)), bevel=0.035, taper=(0.82, 0.9)))
hp.append(box("shroud_back", (0.5, 0.26, 0.3), P + Vector((0, -0.34, 0.24)), bevel=0.03))
hp.append(box("armour_l", (0.06, 0.62, 0.3), P + Vector((-0.36, 0.06, 0.26)), bevel=0.015))
hp.append(box("armour_r", (0.06, 0.62, 0.3), P + Vector((0.36, 0.06, 0.26)), bevel=0.015))
hp.append(box("armour_l_hi", (0.05, 0.4, 0.07), P + Vector((-0.4, 0.1, 0.4)), bevel=0.012))
hp.append(box("armour_r_hi", (0.05, 0.4, 0.07), P + Vector((0.4, 0.1, 0.4)), bevel=0.012))
hp.append(box("hump", (0.34, 0.4, 0.14), P + Vector((0, -0.12, 0.5)), bevel=0.03, taper=(0.7, 0.8)))
hp.append(cyl("antenna", 0.012, 0.5, P + Vector((0.22, -0.4, 0.65)), (0, 0, 0), 8, 0.0))
hp.append(cyl("antenna_base", 0.035, 0.05, P + Vector((0.22, -0.4, 0.42)), (0, 0, 0), 12, 0.008))
hp.append(box("vent", (0.3, 0.02, 0.14), P + Vector((0, -0.48, 0.28)), bevel=0.005))
for i in range(5):
	hp.append(box("vent_slat%d" % i, (0.28, 0.03, 0.012), P + Vector((0, -0.495, 0.22 + i * 0.03)), bevel=0.003))
hp.append(cyl("eye_ring", 0.075, 0.05, P + Vector((0, 0.43, 0.46)), (math.radians(90), 0, 0), 20, 0.008))
head_s = join("Shroud", hp, P)
eye = []
eye.append(cyl("eye_lens", 0.05, 0.06, P + Vector((0, 0.45, 0.46)), (math.radians(90), 0, 0), 20, 0.0, GLOW))
eye.append(box("strip_l", (0.015, 0.3, 0.03), P + Vector((-0.395, 0.2, 0.26)), bevel=0.003, material=GLOW))
eye.append(box("strip_r", (0.015, 0.3, 0.03), P + Vector((0.395, 0.2, 0.26)), bevel=0.003, material=GLOW))
eye.append(box("status", (0.08, 0.015, 0.04), P + Vector((0, -0.48, 0.4)), bevel=0.003, material=GLOW))
head_g = join("HeadGlow", eye, P)

# ---- Gun: pitch pivot at the trunnion between the cheeks ----
G = P + Vector((0, 0.2, 0.3))
gp = []
for sx in (-1, 1):
	gp.append(cyl("barrel%d" % sx, 0.045, 0.95, G + V(0.13 * sx, 0.62, 0), (math.radians(90), 0, 0), 16, 0.006))
	gp.append(cyl("jacket%d" % sx, 0.075, 0.42, G + V(0.13 * sx, 0.4, 0), (math.radians(90), 0, 0), 16, 0.008))
	gp.append(cyl("brake%d" % sx, 0.065, 0.14, G + V(0.13 * sx, 1.08, 0), (math.radians(90), 0, 0), 16, 0.006))
	for k in range(3):
		gp.append(cyl("fin%d_%d" % (sx, k), 0.085, 0.025, G + V(0.13 * sx, 0.28 + k * 0.1, 0), (math.radians(90), 0, 0), 16, 0.004))
	gp.append(box("feed%d" % sx, (0.09, 0.5, 0.12), G + V(0.13 * sx, -0.02, -0.12), bevel=0.012))
gp.append(box("receiver", (0.46, 0.5, 0.2), G + V(0, 0.02, 0.0), bevel=0.03))
gp.append(box("receiver_top", (0.3, 0.34, 0.07), G + V(0, -0.02, 0.12), bevel=0.015))
gp.append(box("rail", (0.05, 0.4, 0.03), G + V(0, 0.0, 0.16), bevel=0.004))
gp.append(cyl("trunnion", 0.05, 0.64, G, (0, math.radians(90), 0), 12, 0.008))
gun = join("Gun", gp, G)
gg = [box("coil_l", (0.02, 0.2, 0.025), G + V(-0.235, 0.0, 0.0), bevel=0.003, material=GLOW),
	box("coil_r", (0.02, 0.2, 0.025), G + V(0.235, 0.0, 0.0), bevel=0.003, material=GLOW),
	cyl("tip_l", 0.03, 0.02, G + V(-0.13, 1.16, 0), (math.radians(90), 0, 0), 12, 0.0, GLOW),
	cyl("tip_r", 0.03, 0.02, G + V(0.13, 1.16, 0), (math.radians(90), 0, 0), 12, 0.0, GLOW)]
gun_g = join("GunGlow", gg, G)

# ---- Hierarchy: empties at the pivots ----
def empty(name, loc, parent=None):
	e = bpy.data.objects.new(name, None)
	scene.collection.objects.link(e)
	e.location = loc
	if parent:
		e.parent = parent
		e.matrix_parent_inverse = parent.matrix_world.inverted()
	return e

root = empty("Turret", (0, 0, 0))
bpy.context.view_layer.update()
head = empty("Head", P, root)
bpy.context.view_layer.update()
gunp = empty("Gun", G, head)
bpy.context.view_layer.update()
muzzle = empty("Muzzle", Vector((0, 1.16, 0)), gunp)

for o, p in ((base, root), (head_s, head), (head_g, head), (gun, gunp), (gun_g, gunp)):
	w = o.matrix_world.copy()
	o.parent = p
	o.matrix_parent_inverse = p.matrix_world.inverted()
	o.matrix_world = w
head_s.name = "ShroudMesh"; head_g.name = "HeadGlowMesh"; gun.name = "GunMesh"; gun_g.name = "GunGlowMesh"; base.name = "BaseMesh"

# ---- UV, paint, bake ----
meshes = [base, head_s, gun]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
	o.select_set(True)
bpy.context.view_layer.objects.active = base
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
bpy.ops.uv.pack_islands(margin=0.004)
bpy.ops.object.mode_set(mode="OBJECT")

img = bpy.data.images.new("turret_albedo", BAKE, BAKE)
ao_img = bpy.data.images.new("turret_ao", BAKE, BAKE)
nt = HULL.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
# Procedural paint: gunmetal with lighter armour, wear from the cavity/edge, hazard bands by position.
tex = nt.nodes.new("ShaderNodeTexCoord")
noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 18; noise.inputs["Detail"].default_value = 10
noise2 = nt.nodes.new("ShaderNodeTexNoise"); noise2.inputs["Scale"].default_value = 120; noise2.inputs["Detail"].default_value = 4
bump = nt.nodes.new("ShaderNodeBump")
ramp = nt.nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.35; ramp.color_ramp.elements[0].color = (0.13, 0.15, 0.17, 1)
ramp.color_ramp.elements[1].position = 0.7; ramp.color_ramp.elements[1].color = (0.40, 0.44, 0.46, 1)
geo = nt.nodes.new("ShaderNodeNewGeometry")
edge = nt.nodes.new("ShaderNodeBevel"); edge.inputs["Radius"].default_value = 0.01
wear = nt.nodes.new("ShaderNodeMath"); wear.operation = "SUBTRACT"
wearramp = nt.nodes.new("ShaderNodeValToRGB"); wearramp.color_ramp.elements[0].position = 0.0; wearramp.color_ramp.elements[1].position = 0.12
mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"
sep = nt.nodes.new("ShaderNodeSeparateXYZ")
stripe = nt.nodes.new("ShaderNodeMath"); stripe.operation = "PINGPONG"; stripe.inputs[1].default_value = 0.06
mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 1.0
l = nt.links
l.new(tex.outputs["Object"], noise.inputs["Vector"])
l.new(tex.outputs["Object"], noise2.inputs["Vector"])
l.new(noise.outputs["Fac"], ramp.inputs["Fac"])
l.new(noise2.outputs["Fac"], bump.inputs["Height"])
l.new(ramp.outputs["Color"], mix.inputs["A"])
mix.inputs["B"].default_value = (0.55, 0.42, 0.28, 1)    # worn edge: bare, slightly rusty metal
l.new(geo.outputs["Pointiness"], wear.inputs[0])
wear.inputs[1].default_value = 0.5
l.new(wear.outputs["Value"], wearramp.inputs["Fac"])
l.new(wearramp.outputs["Color"], mix.inputs["Factor"])
brick = nt.nodes.new("ShaderNodeTexBrick")
brick.inputs["Scale"].default_value = 1.7; brick.inputs["Mortar Size"].default_value = 0.012
brick.inputs["Mortar Smooth"].default_value = 0.3; brick.inputs["Bias"].default_value = 0.0
brick.inputs["Brick Width"].default_value = 0.6; brick.inputs["Row Height"].default_value = 0.35
brick.inputs["Color1"].default_value = (1, 1, 1, 1); brick.inputs["Color2"].default_value = (0.82, 0.82, 0.85, 1)
brick.inputs["Mortar"].default_value = (0.1, 0.1, 0.1, 1)
l.new(tex.outputs["Object"], brick.inputs["Vector"])
seam = nt.nodes.new("ShaderNodeMix"); seam.data_type = "RGBA"; seam.blend_type = "MULTIPLY"; seam.inputs["Factor"].default_value = 1.0
l.new(mix.outputs["Result"], seam.inputs["A"])
l.new(brick.outputs["Color"], seam.inputs["B"])
l.new(seam.outputs["Result"], bsdf.inputs["Base Color"])
l.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

# Bake the colour (no light) into the image.
for o in meshes:
	o.data.materials[0] = HULL
imgnode = nt.nodes.new("ShaderNodeTexImage"); imgnode.image = img
nt.nodes.active = imgnode
scene.render.engine = "CYCLES"
scene.cycles.samples = 32
try:
	prefs = bpy.context.preferences.addons["cycles"].preferences
	prefs.compute_device_type = "OPTIX"
	prefs.get_devices()
	for d in prefs.devices:
		d.use = True
	scene.cycles.device = "GPU"
except Exception as e:
	print("no GPU:", e)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
	o.select_set(True)
bpy.context.view_layer.objects.active = base
scene.render.bake.use_pass_direct = False
scene.render.bake.use_pass_indirect = False
scene.render.bake.use_pass_color = True
scene.render.bake.margin = 4
bpy.ops.object.bake(type="DIFFUSE")

# AO into a second image, multiplied in with numpy-free pixel math afterwards.
nt.nodes.active = None
imgnode.image = ao_img
nt.nodes.active = imgnode
scene.cycles.samples = 96
bpy.ops.object.bake(type="AO")

import array
a = list(img.pixels); b = list(ao_img.pixels)
for i in range(0, len(a), 4):
	k = 0.35 + 0.65 * b[i]
	a[i] *= k; a[i + 1] *= k; a[i + 2] *= k
img.pixels = a
img.filepath_raw = os.path.join(out_dir, "turret_albedo.png")
img.file_format = "PNG"
img.save()

# Final hull material: the baked image, plus a gentle metal/rough so the game's light finds the bevels.
final = bpy.data.materials.new("Hull")
final.use_nodes = True
fb = next(n for n in final.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
ti = final.node_tree.nodes.new("ShaderNodeTexImage"); ti.image = bpy.data.images.load(img.filepath_raw)
final.node_tree.links.new(ti.outputs["Color"], fb.inputs["Base Color"])
fb.inputs["Metallic"].default_value = 0.35
fb.inputs["Roughness"].default_value = 0.55
for o in meshes:
	o.data.materials[0] = final

# ---- Export ----
bpy.ops.object.select_all(action="SELECT")
glb = os.path.join(out_dir, "turret.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_apply=True, export_yup=True, use_selection=True,
	export_image_format="AUTO")
tris = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
print("TURRET OK", glb, "polys", tris)

if SHEET:
	# Contact sheet: four views on a floor, lit.
	bpy.ops.mesh.primitive_plane_add(size=8, location=(0, 0, 0))
	bpy.context.object.data.materials.append(mat("Floor", (0.2, 0.2, 0.2, 1), 0, 0.9))
	cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
	cam.data.lens = 55
	for n, (loc, e) in {"sun": ((4, -3, 6), (math.radians(50), 0, math.radians(35)))}.items():
		s = bpy.data.lights.new(n, "SUN"); s.energy = 3.5
		o = bpy.data.objects.new(n, s); o.location = loc; o.rotation_euler = e; scene.collection.objects.link(o)
	world = bpy.data.worlds.new("w"); world.use_nodes = True; scene.world = world
	world.node_tree.nodes["Background"].inputs[0].default_value = (0.35, 0.4, 0.5, 1)
	world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
	scene.render.resolution_x = 900; scene.render.resolution_y = 700
	scene.cycles.samples = 64
	for name, ang in (("front", 25), ("side", 115), ("back", 205), ("quarter", 60)):
		r = math.radians(ang)
		cam.location = (math.sin(r) * 3.6, -math.cos(r) * 3.6, 1.9)
		d = Vector((0, 0, 0.85)) - cam.location
		cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
		scene.render.filepath = os.path.join(out_dir, "sheet_%s.png" % name)
		bpy.ops.render.render(write_still=True)
