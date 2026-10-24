extends Node3D

const ZzBoxCrate := preload("zz_box_crate.gd")

## The carried box in the survivor's own hands: the crate under the camera, two arms on its sides,
## lifted into view when it comes out and set down and opened as the deploy fills. Client side,
## presentation only: the server's deploy is what spawns the box.

const DEFAULT_COLOUR := Color(0.95, 0.7, 0.2)
const HOLD := Vector3(0.0, -0.30, -0.58)
const DOWN := Vector3(0.0, -0.66, -0.80)
const HOLD_TILT := Vector3(-14.0, 0.0, 0.0)
const DOWN_TILT := Vector3(-3.0, 0.0, 0.0)
## Seconds the crate takes to come up when taken out.
const RAISE_SECONDS := 0.3

var _crate: Dictionary = {}
var _arms: ZeeViewArms = null
var _raise: float = 0.0
var _colour: Color = Color(-1, 0, 0)


func _ready() -> void:
	visible = false


## Draws the crate while [param out], posed for [param deploying] (0..1, 0 when not deploying).
func present(out: bool, deploying: float, colour: Color, delta: float) -> void:
	visible = out

	if not out:
		_raise = 0.0
		return

	if _crate.is_empty() or colour != _colour:
		_rebuild(colour)

	_raise = minf(_raise + delta / RAISE_SECONDS, 1.0)
	var lower := ZzBoxCrate.lowered(deploying)
	var root: Node3D = _crate["root"]
	var rise := smoothstep(0.0, 1.0, _raise)
	root.position = HOLD.lerp(DOWN, lower) + Vector3(0.0, -0.45 * (1.0 - rise), 0.1 * (1.0 - rise))
	root.rotation_degrees = HOLD_TILT.lerp(DOWN_TILT, lower)
	ZzBoxCrate.set_open(_crate, ZzBoxCrate.opened(deploying))
	_reach(root)


## The hand positions follow the crate's sides; they are the camera-space points the arms grip.
func _reach(root: Node3D) -> void:
	if _arms == null:
		return

	var half := ZzBoxCrate.SIZE.x * 0.5
	var right := root.position + root.basis * Vector3(half + 0.01, 0.0, 0.02)
	var left := root.position + root.basis * Vector3(-half - 0.01, 0.0, 0.02)
	# A hand on a thing at the side is held with the forearm up it: same axis for both.
	_arms.reach(right, left, &"rifle", Vector3.UP, Vector3.UP, 0.04)


func _rebuild(colour: Color) -> void:
	for child in get_children():
		child.queue_free()

	_colour = colour
	_crate = ZzBoxCrate.build(colour)
	add_child(_crate["root"])
	_arms = null

	_arms = ZeeViewArms.new()
	_arms.view_layer = 0
	add_child(_arms)

	if not _arms.build().ok:
		_arms.queue_free()
		_arms = null
