extends RefCounted

## The supply crate as a drawn thing: a base, a hinged lid and a glow inside. The first-person
## hands ([ZzBoxHands]) and the third-person figure hold the same one, and both pose it from the
## deploy fraction the server replicates, so a team-mate sees the lift, set-down and opening the
## carrier sees.

const SIZE := Vector3(0.40, 0.22, 0.28)
const LID_HEIGHT := 0.05
const OPEN_DEGREES := 112.0

## Fraction of the deploy spent setting the crate down before the lid starts to open.
const SET_DOWN_END := 0.4
const OPEN_START := 0.55


## Builds the crate under a new root. Returns `{"root", "lid", "glow"}`.
static func build(colour: Color, layer_mask: int = 1) -> Dictionary:
	var root := Node3D.new()
	root.name = "Crate"

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = colour
	body_material.roughness = 0.75
	body_material.emission_enabled = true
	body_material.emission = colour * 0.15

	var dark := StandardMaterial3D.new()
	dark.albedo_color = colour.darkened(0.55)
	dark.roughness = 0.9

	var base := _box(Vector3(SIZE.x, SIZE.y, SIZE.z), body_material, layer_mask)
	base.name = "Base"
	root.add_child(base)

	# A band round the middle and a handle on the front: what makes a block read as a carried crate.
	var band := _box(Vector3(SIZE.x + 0.01, 0.04, SIZE.z + 0.01), dark, layer_mask)
	band.position.y = 0.02
	root.add_child(band)
	var handle := _box(Vector3(0.14, 0.03, 0.03), dark, layer_mask)
	handle.position = Vector3(0.0, 0.03, -SIZE.z * 0.5 - 0.015)
	root.add_child(handle)

	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.albedo_color = Color(1.0, 0.92, 0.6)
	var glow := _box(Vector3(SIZE.x - 0.05, 0.01, SIZE.z - 0.05), glow_material, layer_mask)
	glow.position.y = SIZE.y * 0.5
	glow.visible = false
	root.add_child(glow)

	# The lid hinges on the back top edge; its mesh hangs forward of the pivot.
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0.0, SIZE.y * 0.5 + LID_HEIGHT * 0.5, SIZE.z * 0.5)
	var lid_mesh := _box(Vector3(SIZE.x, LID_HEIGHT, SIZE.z), body_material, layer_mask)
	lid_mesh.position.z = -SIZE.z * 0.5
	lid.add_child(lid_mesh)
	root.add_child(lid)

	return {"root": root, "lid": lid, "glow": glow}


## Opens the lid by [param open] (0..1) and lights the inside once it is ajar.
static func set_open(crate: Dictionary, open: float) -> void:
	var lid: Node3D = crate["lid"]
	lid.rotation.x = deg_to_rad(OPEN_DEGREES) * open
	(crate["glow"] as Node3D).visible = open > 0.05


## How far down the set-down is at [param fraction] of the deploy, 0..1.
static func lowered(fraction: float) -> float:
	return smoothstep(0.0, SET_DOWN_END, fraction)


## How far open the lid is at [param fraction] of the deploy, 0..1.
static func opened(fraction: float) -> float:
	return smoothstep(OPEN_START, 1.0, fraction)


static func _box(size: Vector3, material: Material, layer_mask: int) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.layers = layer_mask
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
