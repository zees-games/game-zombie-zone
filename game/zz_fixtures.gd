extends RefCounted

## What a map's objectives and gates look like: a chain-link fence for a gate box whose `look`
## says so, and the thing a survivor holds Use on (a padlock and chain, a lever, a radio).
##
## [b]Pictures only.[/b] A gate's collision is still its box (a shut fence stops survivors,
## zombies and the zombies' ground alike), and nothing here collides or replicates: every
## machine that draws builds the same pieces from the same document.
##
## [b]Why the first play test asked for it[/b] (2026-10-11): the "fence lock" on the first
## Blackout map was a 3.2 m metal box under a night sky, which drew as a black slab, and the
## objective itself had no picture at all, so holding E put the camera nose-first into black.
## A fence you can see through, with a padlocked chain where the label says, is the objective
## explaining itself.
##
## Built from primitives: Kenney's fences are wooden, iron railings or low garden fences, none
## of them a 3 m chain-link run, and none of its kits has a padlock.

## Box looks a map may ask for. Anything else is drawn as the plain box (a newer map's look on
## an older game is a box, not a refusal).
const LOOKS: Array[String] = ["chain_link"]

## What a `use` objective may stand as. Unsaid draws nothing (as before), so an old map is
## unchanged.
const PROPS: Array[String] = ["padlock", "lever", "radio"]

## Metres between a chain-link run's posts, and the post and rail thickness.
const POST_SPACING := 2.5
const POST_RADIUS := 0.045
const RAIL_RADIUS := 0.028

## Metres of fence one tile of the mesh texture covers (about four diamonds across).
const MESH_TILE := 0.24

const GALVANISED := Color(0.62, 0.65, 0.68)
const BRASS := Color(0.82, 0.64, 0.24)
const STEEL := Color(0.72, 0.74, 0.78)

static var _mesh_texture: ImageTexture = null
static var _materials: Dictionary = {}


## A gate or box drawn as a chain-link run: posts, a top and bottom rail, and the mesh between,
## see-through and double-sided. [param frame] and [param size] are the box's.
static func chain_link(frame: Transform3D, size: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "ChainLink"
	root.transform = frame

	# The run goes along the box's longer horizontal side.
	var along_x := size.x >= size.z
	var length := size.x if along_x else size.z
	var height := size.y
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	var bottom := -height * 0.5

	var posts := maxi(int(ceil(length / POST_SPACING)), 1)
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = POST_RADIUS
	post_mesh.bottom_radius = POST_RADIUS
	post_mesh.height = height
	post_mesh.radial_segments = 8

	for i in posts + 1:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.material_override = metal(GALVANISED)
		post.position = axis * (-length * 0.5 + length * float(i) / float(posts))
		root.add_child(post)

	for y in [bottom + 0.08, bottom + height - 0.05]:
		var rail := MeshInstance3D.new()
		var rail_mesh := CylinderMesh.new()
		rail_mesh.top_radius = RAIL_RADIUS
		rail_mesh.bottom_radius = RAIL_RADIUS
		rail_mesh.height = length
		rail_mesh.radial_segments = 6
		rail.mesh = rail_mesh
		rail.material_override = metal(GALVANISED)
		rail.position = Vector3(0.0, y, 0.0)
		rail.rotation = Vector3(0.0, 0.0, PI * 0.5) if along_x else Vector3(PI * 0.5, 0.0, 0.0)
		root.add_child(rail)

	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(length, height - 0.1)
	panel.mesh = quad
	panel.material_override = mesh_material(Vector2(length, height - 0.1))
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	panel.position = Vector3(0.0, 0.0, 0.0)
	# A QuadMesh faces +Z; the run along x wants that, along z it turns a quarter.
	panel.rotation = Vector3.ZERO if along_x else Vector3(0.0, PI * 0.5, 0.0)
	root.add_child(panel)
	return root


## The see-through mesh, tiled to [param size] metres.
static func mesh_material(size: Vector2) -> StandardMaterial3D:
	var key := "mesh|%.1f|%.1f" % [size.x, size.y]
	if _materials.has(key):
		return _materials[key]

	var m := StandardMaterial3D.new()
	m.albedo_texture = mesh_texture()
	m.albedo_color = GALVANISED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.metallic = 0.5
	m.roughness = 0.45
	m.uv1_scale = Vector3(size.x / MESH_TILE, size.y / MESH_TILE, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[key] = m
	return m


## One tile of chain-link: four diamonds of wire, transparent between. Seeded by nothing; it
## is a pattern.
static func mesh_texture() -> ImageTexture:
	if _mesh_texture != null:
		return _mesh_texture

	var n := 64
	var image := Image.create(n, n, true, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 0.0))
	var wire := Color(1.0, 1.0, 1.0, 1.0)
	var cell := n / 4

	for y in n:
		for x in n:
			# Two families of diagonals, one wire wide (two pixels so mipmaps keep it).
			var a := posmod(x + y, cell)
			var b := posmod(x - y, cell)
			if a <= 1 or b <= 1:
				image.set_pixel(x, y, wire)

	image.generate_mipmaps()
	_mesh_texture = ImageTexture.create_from_image(image)
	return _mesh_texture


static func metal(colour: Color, roughness: float = 0.4) -> StandardMaterial3D:
	var key := "metal|%s|%.2f" % [colour.to_html(), roughness]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.metallic = 0.7
	m.roughness = roughness
	_materials[key] = m
	return m


static func painted(colour: Color) -> StandardMaterial3D:
	var key := "paint|%s" % colour.to_html()
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.8
	_materials[key] = m
	return m


## The picture of objective [param o] ([member PROPS]), or null. [param gate_box] is the box of
## the gate it opens, if any: a padlock hangs on that gate's face nearest the objective, at
## hand height, with its chain round the nearest post-height, rather than in the air where the
## objective's point is.
static func objective_prop(o: Dictionary, gate_box: Dictionary = {}) -> Node3D:
	var kind := str(o.get("prop", ""))
	if not PROPS.has(kind):
		return null

	var at := _v3(o["at"])
	var yaw := deg_to_rad(float(o.get("yaw", 0.0)))
	var root := Node3D.new()
	root.name = "Objective_%s" % str(o.get("id", kind))

	match kind:
		"padlock":
			var face := at
			var facing := Vector3.FORWARD
			if not gate_box.is_empty():
				var centre := _v3(gate_box["at"])
				var half := _v3(gate_box["size"]) * 0.5
				# The gate's face towards the objective, along its thin axis.
				if half.x <= half.z:
					var side := signf(at.x - centre.x) if at.x != centre.x else -1.0
					face = Vector3(centre.x + side * (half.x + 0.04), centre.y - half.y + 1.15,
						clampf(at.z, centre.z - half.z, centre.z + half.z))
					facing = Vector3(side, 0.0, 0.0)
				else:
					var side := signf(at.z - centre.z) if at.z != centre.z else -1.0
					face = Vector3(clampf(at.x, centre.x - half.x, centre.x + half.x),
						centre.y - half.y + 1.15, centre.z + side * (half.z + 0.04))
					facing = Vector3(0.0, 0.0, side)
			root.position = face
			root.basis = Basis.looking_at(-facing, Vector3.UP)
			_padlock(root)
		"lever":
			root.position = Vector3(at.x, at.y - 1.0, at.z)
			root.rotation.y = yaw
			_lever(root)
		"radio":
			root.position = Vector3(at.x, at.y - 1.0, at.z)
			root.rotation.y = yaw
			_radio(root)

	return root


## A chain wrapped twice round the gate's leaves, and a brass padlock hanging from it; the
## node's +Z faces the objective's side.
static func _padlock(root: Node3D) -> void:
	var link := TorusMesh.new()
	link.inner_radius = 0.022
	link.outer_radius = 0.04
	link.rings = 8
	link.ring_segments = 6

	# Two loops of chain, each a vertical column of links alternating flat and edge-on.
	for loop in 2:
		for i in 7:
			var piece := MeshInstance3D.new()
			piece.mesh = link
			piece.material_override = metal(STEEL, 0.35)
			piece.position = Vector3(-0.09 + 0.18 * float(loop), 0.22 - float(i) * 0.06, 0.0)
			piece.rotation = Vector3(0.0, 0.0, PI * 0.5) if i % 2 == 0 else Vector3(PI * 0.5, 0.0, PI * 0.5)
			root.add_child(piece)

	var shackle := MeshInstance3D.new()
	var bow := TorusMesh.new()
	bow.inner_radius = 0.032
	bow.outer_radius = 0.046
	bow.rings = 12
	bow.ring_segments = 6
	shackle.mesh = bow
	shackle.material_override = metal(STEEL, 0.3)
	shackle.position = Vector3(0.0, -0.17, 0.03)
	shackle.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	root.add_child(shackle)

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.11, 0.12, 0.045)
	body.mesh = box
	body.material_override = metal(BRASS, 0.35)
	body.position = Vector3(0.0, -0.25, 0.03)
	root.add_child(body)

	var keyhole := MeshInstance3D.new()
	var hole := BoxMesh.new()
	hole.size = Vector3(0.012, 0.03, 0.004)
	keyhole.mesh = hole
	keyhole.material_override = painted(Color(0.08, 0.06, 0.04))
	keyhole.position = Vector3(0.0, -0.26, 0.054)
	root.add_child(keyhole)


## A post with a box on it and a red-handled lever, for "lower the barrier", "raise the shutter".
static func _lever(root: Node3D) -> void:
	var post := MeshInstance3D.new()
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.14, 1.0, 0.14)
	post.mesh = post_box
	post.material_override = painted(Color(0.92, 0.72, 0.12))
	post.position = Vector3(0.0, 0.5, 0.0)
	root.add_child(post)

	var housing := MeshInstance3D.new()
	var housing_box := BoxMesh.new()
	housing_box.size = Vector3(0.34, 0.4, 0.22)
	housing.mesh = housing_box
	housing.material_override = metal(Color(0.45, 0.48, 0.5))
	housing.position = Vector3(0.0, 1.15, 0.0)
	root.add_child(housing)

	var arm := MeshInstance3D.new()
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.02
	arm_mesh.bottom_radius = 0.02
	arm_mesh.height = 0.42
	arm.mesh = arm_mesh
	arm.material_override = metal(STEEL)
	arm.position = Vector3(0.0, 1.3, 0.2)
	arm.rotation = Vector3(deg_to_rad(-35.0), 0.0, 0.0)
	root.add_child(arm)

	var grip := MeshInstance3D.new()
	var grip_mesh := SphereMesh.new()
	grip_mesh.radius = 0.05
	grip_mesh.height = 0.1
	grip.mesh = grip_mesh
	grip.material_override = painted(Color(0.85, 0.12, 0.1))
	grip.position = Vector3(0.0, 1.47, 0.32)
	root.add_child(grip)


## A field radio on a crate, its aerial up and a lit dial: "radio the boat".
static func _radio(root: Node3D) -> void:
	var crate := MeshInstance3D.new()
	var crate_box := BoxMesh.new()
	crate_box.size = Vector3(0.6, 0.8, 0.5)
	crate.mesh = crate_box
	crate.material_override = painted(Color(0.42, 0.32, 0.2))
	crate.position = Vector3(0.0, 0.4, 0.0)
	root.add_child(crate)

	var set_body := MeshInstance3D.new()
	var set_box := BoxMesh.new()
	set_box.size = Vector3(0.44, 0.26, 0.3)
	set_body.mesh = set_box
	set_body.material_override = painted(Color(0.28, 0.33, 0.22))
	set_body.position = Vector3(0.0, 0.93, 0.0)
	root.add_child(set_body)

	var dial := MeshInstance3D.new()
	var dial_box := BoxMesh.new()
	dial_box.size = Vector3(0.16, 0.07, 0.01)
	dial.mesh = dial_box
	var lit := StandardMaterial3D.new()
	lit.albedo_color = Color(1.0, 0.75, 0.3)
	lit.emission_enabled = true
	lit.emission = Color(1.0, 0.7, 0.25)
	lit.emission_energy_multiplier = 2.0
	dial.material_override = lit
	dial.position = Vector3(-0.08, 0.96, 0.155)
	root.add_child(dial)

	var aerial := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.006
	rod.bottom_radius = 0.01
	rod.height = 0.9
	aerial.mesh = rod
	aerial.material_override = metal(Color(0.2, 0.2, 0.22))
	aerial.position = Vector3(0.16, 1.5, -0.08)
	root.add_child(aerial)


static func _v3(raw: Variant) -> Vector3:
	var a: Array = raw
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
