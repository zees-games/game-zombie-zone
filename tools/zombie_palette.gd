extends SceneTree

## Prints the atlas colours each zombie body wears, by role, for `ZzZombieView.WEARS`.
##
## [codeblock]
## godot --headless --path . --script tools/zombie_palette.gd
## [/codeblock]
##
## Measured in Godot rather than in Blender because what matters is the colour Godot samples:
## the kit ships three slightly different atlases, and a probe that read the wrong one gave
## colours the palette shader never matched. Each vertex takes the role of the bone that moves it
## most (head, torso, arm, hand, hips, leg, foot), and the colour under its UV is counted.

const ZzZombieView := preload("../npcs/zz_zombie_view.gd")

const ROLES := [["Head", "head"], ["Neck", "head"], ["Tongue", "head"], ["Eyelid", "head"], ["Mouth", "head"],
	["Torso", "torso"], ["Abdomen", "torso"], ["Shoulder", "torso"], ["UpperArm", "arm"], ["LowerArm", "arm"],
	["Pinky", "hand"], ["Middle", "hand"], ["Index", "hand"], ["Thumb", "hand"], ["Hips", "hips"], ["Body", "hips"],
	["UpperLeg", "leg"], ["LowerLeg", "leg"], ["Foot", "foot"]]


func _initialize() -> void:
	for id: StringName in ZzZombieView.BODIES:
		var model := (load(ZzZombieView.BODIES[id]) as PackedScene).instantiate()
		var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false).front()
		var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false).front()
		var image := (load(ZzZombieView.ATLASES[ZzZombieView.ATLAS_OF[id]]) as Texture2D).get_image()
		var arrays := mesh.mesh.surface_get_arrays(0)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / uvs.size()
		var counts := {}
		var skin := mesh.skin

		for i in uvs.size():
			var best := 0
			for k in per:
				if weights[i * per + k] > weights[i * per + best]:
					best = k
			var bind := bones[i * per + best]
			var bone_name: StringName = skin.get_bind_name(bind) if skin != null and skin.get_bind_name(bind) != &"" else skeleton.get_bone_name(skin.get_bind_bone(bind) if skin != null else bind)
			var role: String = "?"
			for pair: Array in ROLES:
				if String(bone_name).contains(pair[0]):
					role = pair[1]
					break
			var x := clampi(int(uvs[i].x * image.get_width()), 0, image.get_width() - 1)
			var y := clampi(int(uvs[i].y * image.get_height()), 0, image.get_height() - 1)
			var hex := image.get_pixel(x, y).to_html(false)
			if not counts.has(role):
				counts[role] = {}
			counts[role][hex] = int(counts[role].get(hex, 0)) + 1

		print("== ", id)
		for role: String in counts:
			var row: Dictionary = counts[role]
			var keys := row.keys()
			keys.sort_custom(func(a, b) -> bool: return row[a] > row[b])
			var total := 0
			for k in keys:
				total += int(row[k])
			var parts := PackedStringArray()
			for k in keys.slice(0, 5):
				parts.append("%s:%d%%" % [k, 100 * int(row[k]) / maxi(total, 1)])
			print("   %-6s %s" % [role, " ".join(parts)])
		model.free()

	quit()
