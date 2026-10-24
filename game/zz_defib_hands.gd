extends Node3D

const ZzDefibModel := preload("zz_defib_model.gd")

## The defibrillator in the survivor's own hands while they charge it at a body: the unit under the
## camera, two arms on its sides, raised as the hold begins. Client side, presentation only.

const HOLD := Vector3(0.0, -0.34, -0.55)
const TILT := Vector3(-18.0, 180.0, 0.0)
## Seconds it takes to come up.
const RAISE_SECONDS := 0.25

var _model: Node3D = null
var _arms: ZeeViewArms = null
var _raise: float = 0.0


func _ready() -> void:
	visible = false


## Draws the unit while [param out]; [param charge] is 0..1 and makes it shake as it fills.
func present(out: bool, charge: float, delta: float) -> void:
	visible = out

	if not out:
		_raise = 0.0
		return

	if _model == null:
		_build()

	_raise = minf(_raise + delta / RAISE_SECONDS, 1.0)
	var rise := smoothstep(0.0, 1.0, _raise)
	var shake := charge * 0.006 * sin(Time.get_ticks_msec() * 0.06)
	_model.position = HOLD + Vector3(shake, -0.4 * (1.0 - rise) + shake, 0.0)
	_model.rotation_degrees = TILT

	if _arms != null:
		var right := _model.position + _model.basis * Vector3(0.17, 0.08, 0.0)
		var left := _model.position + _model.basis * Vector3(-0.17, 0.08, 0.0)
		_arms.reach(right, left, &"rifle", Vector3.UP, Vector3.UP, 0.04)


func _build() -> void:
	_model = ZzDefibModel.instantiate()

	if _model == null:
		_model = Node3D.new()
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.3, 0.16, 0.4)
		box.mesh = mesh
		box.position.y = 0.08
		_model.add_child(box)

	add_child(_model)
	_arms = ZeeViewArms.new()
	_arms.view_layer = 0
	add_child(_arms)

	if not _arms.build().ok:
		_arms.queue_free()
		_arms = null
