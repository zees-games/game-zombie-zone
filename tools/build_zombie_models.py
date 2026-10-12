"""Builds assets/zombies/zombie_*.glb from Quaternius' Zombie Apocalypse Kit (CC0).

    blender -b --factory-startup --python tools/build_zombie_models.py -- <kit glTF dir> assets/zombies

The kit is not vendored: download its `Characters/glTF` folder from
https://quaternius.com/packs/zombieapocalypsekit.html (CC0 1.0, by Quaternius) and point the first
argument at it. What this does to each body, and why:

- Keeps the one skinned mesh and drops everything else: the survivors carry eleven weapons
  parented to a finger bone, and Blender's importer adds a hidden bone-display icosphere.
- Joins a body's meshes into one, with the kit's one atlas material, so a zombie is one surface
  and one draw call. The atlas itself is not embedded (the import discards it): every body shares
  `zombie_atlas.png` through the view's palette shader.
- Paints three noise fields (less blood on the head) into the vertex colours from the rest pose (R grime, G blood, B rot).
  They are fixed to the skin, so they move with it; the view's shader turns them into dirt and
  blood at a threshold each zombie picks, which is how two zombies of one body differ.
- Halves the triangles (Blender's collapse decimation, which keeps the vertex groups): the kit's
  bodies are 6 to 9 thousand triangles each, and a horde of sixty of them was the most expensive
  thing in a browser frame. The atlas swatches are flat, so a collapse that crosses a seam moves
  a colour boundary a little and loses no detail.
- Renames the clips to the game's names. Only the four zombie bodies keep animations; the four
  survivor bodies share the same 43-bone rig and are driven by zombie_basic's clips at runtime,
  which is what makes them shamble rather than jog, and keeps them a quarter of the size.
"""
import bpy, sys, os
import mathutils

src, out = sys.argv[sys.argv.index("--") + 1:][:2]

CLIPS = {"Crawl": "crawl", "Death": "death", "HitReact": "hit", "Idle": "idle", "Idle_Attack": "attack_idle",
	"Jump": "jump", "Jump_Idle": "jump_idle", "Jump_Land": "jump_land", "Punch": "attack", "Run": "run",
	"Run_Arms": "run_arms", "Run_Attack": "attack_run", "Walk": "walk"}

# (output name, kit file, keeps its own clips)
BODIES = [("basic", "Zombie_Basic", True), ("chubby", "Zombie_Chubby", True), ("arm", "Zombie_Arm", True),
	("matt", "Characters_Matt", False), ("lis", "Characters_Lis", False), ("sam", "Characters_Sam", False),
	("shaun", "Characters_Shaun", False)]


RATIO = 0.35


def noise01(p, scale, offset):
	return max(0.0, min(1.0, 0.5 + 0.5 * mathutils.noise.noise(p * scale + offset)))


def paint(body):
	mesh = body.data
	head = {g.index for g in body.vertex_groups if g.name in ("Head", "Neck", "TopMouth", "BottomMouth", "Eyelid.L", "Eyelid.R")}
	# Some kit meshes carry a colour layer of their own (white); the exporter would write that one.
	for old in list(mesh.color_attributes):
		mesh.color_attributes.remove(old)
	attr = mesh.color_attributes.new("Wear", "BYTE_COLOR", "POINT")
	for v in mesh.vertices:
		p = v.co
		r = noise01(p, 3.0, mathutils.Vector((1.3, 7.1, 2.9)))
		g = noise01(p, 4.5, mathutils.Vector((9.2, 3.3, 5.7)))
		b = noise01(p, 2.0, mathutils.Vector((4.4, 8.8, 0.6)))
		# Less blood on the face: the head is a third of these bodies, and a face under a red
		# splash reads as a red face, not a wound.
		weights = sorted(((x.weight, x.group) for x in v.groups), reverse=True)
		if weights and weights[0][1] in head:
			g *= 0.72
		attr.data[v.index].color = (r, g, b, 1.0)
	mesh.color_attributes.active_color = attr


for name, file, own_anims in BODIES:
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=os.path.join(src, file + ".gltf"))
	arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]

	for o in list(bpy.data.objects):
		if o.type == "MESH" and (not o.visible_get() or o.parent_type == "BONE"
				or not any(m.type == "ARMATURE" for m in o.modifiers)):
			bpy.data.objects.remove(o, do_unlink=True)

	meshes = [o for o in bpy.data.objects if o.type == "MESH"]
	bpy.ops.object.select_all(action="DESELECT")
	for m in meshes:
		m.select_set(True)
	bpy.context.view_layer.objects.active = meshes[0]
	if len(meshes) > 1:
		bpy.ops.object.join()
	body = bpy.context.view_layer.objects.active
	body.name = "Body"
	decimate = body.modifiers.new("Decimate", "DECIMATE")
	decimate.ratio = RATIO
	decimate.use_collapse_triangulate = True
	bpy.context.view_layer.objects.active = body
	# Before the armature modifier, so the skin deforms the simplified mesh.
	while body.modifiers[0].name != "Decimate":
		bpy.ops.object.modifier_move_up(modifier="Decimate")
	bpy.ops.object.modifier_apply(modifier="Decimate")
	paint(body)

	for a in list(bpy.data.actions):
		base = a.name.replace("_CharacterArmature", "")
		if not own_anims or base not in CLIPS:
			bpy.data.actions.remove(a)
		else:
			a.name = CLIPS[base]

	if arm.animation_data:
		arm.animation_data.action = None
		for t in list(arm.animation_data.nla_tracks):
			arm.animation_data.nla_tracks.remove(t)

	for a in bpy.data.actions:
		if arm.animation_data is None:
			arm.animation_data_create()
		track = arm.animation_data.nla_tracks.new()
		track.name = a.name
		track.strips.new(a.name, int(a.frame_range[0]), a)

	print("BODY", name, "verts", len(body.data.vertices), "anims", sorted(a.name for a in bpy.data.actions))
	bpy.ops.export_scene.gltf(filepath=os.path.join(out, "zombie_%s.glb" % name), export_format="GLB",
		export_yup=True, export_texcoords=True, export_normals=True, export_vertex_color="ACTIVE",
		export_materials="EXPORT", export_animations=own_anims, export_animation_mode="NLA_TRACKS",
		export_skins=True, export_morph=False, export_def_bones=False, export_image_format="NONE")
