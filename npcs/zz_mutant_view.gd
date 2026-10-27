extends "zz_zombie_view.gd"

## The mutant as drawn: its own rigid-skinned model, posed by code (it has no clips), with a
## jetpack exhaust and sparks and smoke where a part is shot off. It keeps the zombie view's seams
## (build, present, flinch, die, the limb cuts) so the world view and the limbs treat it alike.

const MODEL := "res://assets/zombies/zombie_mutant.glb"
const MUTANT_CREDITS := "Buff Mutant 2.0 by Zeldrix (CC-BY 4.0), modified"
const PARTS: Array[StringName] = [&"gunL", &"gunR", &"pack"]
## Where the exhaust sits on the back, in the view's own space (forward is -Z).
const EXHAUST := Vector3(0.0, 1.5, 0.55)

var _rest: Dictionary = {}
var _index: Dictionary = {}
var _phase := 0.0
var _swing := 0.0
var _thruster: DotFxThruster = null
var _stump_fx: Dictionary = {}
var _dead_t := -1.0
var _body_flash := 0.0
var _jolt := 0.0


func build(p_kind: StringName, p_variant: int) -> void:
	if _model != null:
		return

	kind = p_kind
	variant = p_variant
	body_id = &"mutant"
	_look = look_for(&"common", 0)
	var scene := _scene(ZzPaths.rebase(MODEL))

	if scene == null:
		_model = _capsule()
		add_child(_model)
		return

	_model = scene.instantiate() as Node3D
	_model.basis = Basis(Vector3.UP, PI)
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	_mesh = _model.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D

	for i in _skeleton.get_bone_count():
		var n := _skeleton.get_bone_name(i)
		_index[n] = i
		_rest[n] = _skeleton.get_bone_rest(i).basis.get_rotation_quaternion()

	for m: Node in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visibility_range_end = lod.draw_until if lod != null else 120.0
		var skin := StandardMaterial3D.new()
		skin.vertex_color_use_as_albedo = true
		skin.roughness = 0.6
		skin.cull_mode = BaseMaterial3D.CULL_DISABLED
		(m as MeshInstance3D).material_override = skin

	_thruster = DotFxThruster.new()
	_thruster.position = EXHAUST
	add_child(_thruster)


func _turn(bone: String, axis: Vector3, angle: float) -> void:
	var i: int = _index.get(bone, -1)

	if i >= 0:
		_skeleton.set_bone_pose_rotation(i, (_rest[bone] as Quaternion) * Quaternion(axis, angle))


func present(delta: float, anim: int, flags: int) -> void:
	if _model == null or _skeleton == null:
		return

	_frame += 1
	var at := global_position
	if _last_at != Vector3.INF and delta > 0.0:
		var moved := Vector2(at.x - _last_at.x, at.z - _last_at.z).length() / delta
		_speed = lerpf(_speed, moved, clampf(delta * 8.0, 0.0, 1.0))
	_last_at = at

	if anim == ZzZombieBody.Anim.DEAD and _dead_t < 0.0:
		die(&"limp", Vector3.ZERO, 0)

	if _dead_t >= 0.0:
		_dead_t += delta
		var fall := clampf(_dead_t / 1.1, 0.0, 1.0)
		_model.rotation.x = lerpf(0.0, -PI * 0.5, fall * fall)
		_model.position.y = lerpf(0.0, 0.5, fall)
		_thruster.throttle = 0.0
		return

	_jolt = maxf(_jolt - delta * 4.0, 0.0)
	_phase += delta * clampf(_speed, 0.0, 6.0) * 1.9
	var walk := clampf(_speed / 2.0, 0.0, 1.0)
	var s := sin(_phase)
	var airborne := anim == ZzZombieBody.Anim.FLY or anim == ZzZombieBody.Anim.CHARGE_UP or anim == ZzZombieBody.Anim.DIVE
	var pack_gone := _is_gone(&"pack")

	# Rest, then the pose of the moment.
	_turn("Hips", Vector3.RIGHT, 0.0)
	_turn("Spine", Vector3.RIGHT, 0.04 * s * walk)
	_turn("LegL", Vector3.RIGHT, 0.0 if airborne else 0.55 * s * walk)
	_turn("LegR", Vector3.RIGHT, 0.0 if airborne else -0.55 * s * walk)
	_turn("ArmL", Vector3.RIGHT, -0.4 * s * walk)
	_turn("ArmR", Vector3.RIGHT, 0.4 * s * walk)
	_turn("ShoulderL", Vector3.RIGHT, 0.0)
	_turn("ShoulderR", Vector3.RIGHT, 0.0)
	_turn("Head", Vector3.RIGHT, 0.0)
	_model.rotation.x = 0.0
	_model.position = Vector3(0.0, 0.05 * absf(s) * walk, 0.0)
	var throttle := 0.0

	match anim:
		ZzZombieBody.Anim.ATTACK, ZzZombieBody.Anim.STRIKE_DOWN:
			_swing = fposmod(_swing + delta / 1.0, 1.0)
			var arc := sin(_swing * PI)
			_turn("ArmR", Vector3.RIGHT, -2.1 * arc)
			_turn("Spine", Vector3.UP, 0.4 * arc)
		ZzZombieBody.Anim.ZAP:
			_turn("ShoulderL", Vector3.RIGHT, -1.3)
			_turn("ShoulderR", Vector3.RIGHT, -1.3)
		ZzZombieBody.Anim.FLY:
			throttle = 0.8
			_turn("Spine", Vector3.RIGHT, 0.25)
			_turn("LegL", Vector3.RIGHT, 0.4)
			_turn("LegR", Vector3.RIGHT, 0.3)
		ZzZombieBody.Anim.CHARGE_UP:
			throttle = 1.0
			_turn("ArmL", Vector3.RIGHT, -2.6)
			_turn("ArmR", Vector3.RIGHT, -2.6)
			_model.position.x = sin(float(_frame) * 1.7) * 0.05
		ZzZombieBody.Anim.DIVE:
			throttle = 1.0
			_model.rotation.x = -1.2
			_turn("ArmL", Vector3.RIGHT, -3.0)
			_turn("ArmR", Vector3.RIGHT, -3.0)
		ZzZombieBody.Anim.SLAM:
			_turn("Spine", Vector3.RIGHT, 0.7)
			_turn("ArmL", Vector3.RIGHT, 0.8)
			_turn("ArmR", Vector3.RIGHT, 0.8)
			_model.position.y = -0.25

	if _jolt > 0.0:
		_turn("Head", Vector3.RIGHT, -0.35 * _jolt)

	if not pack_gone:
		_thruster.throttle = throttle
		_thruster.rotation.x = -0.5 if anim == ZzZombieBody.Anim.DIVE else 0.0
	else:
		_thruster.throttle = 0.0

	for gone: int in _skeleton.get_meta(DotNpcGibs.COLLAPSED, []):
		_skeleton.set_bone_pose_scale(gone, Vector3.ONE * 0.001)


func _is_gone(part: StringName) -> bool:
	return _stump_fx.has(part)


func flinch(_from_side: float = 1.0) -> void:
	_jolt = 1.0


func set_fade(_alpha: float) -> void:
	pass


func fade() -> float:
	return 1.0


func die(_reaction: StringName, _push: Vector3, _seed: int) -> void:
	if _dead_t < 0.0:
		_dead_t = 0.0


func sever_limb(limb: StringName, d: Dictionary, impulse: Vector3) -> Vector3:
	var at := super(limb, d, impulse)
	_part_lost(limb, at)
	return at


func stump_limb(limb: StringName, d: Dictionary) -> Vector3:
	var at := super(limb, d)
	_part_lost(limb, at)
	return at


## Sparks, and for the pack smoke from a failed exhaust; a gun gets a smoking stump of its own.
func _part_lost(limb: StringName, at: Vector3) -> void:
	if _stump_fx.has(limb) or _skeleton == null:
		return

	if limb == &"pack":
		_stump_fx[limb] = _thruster
		_thruster.broken = true
		_thruster.spark()
		return

	var fx := DotFxThruster.new()
	fx.broken = true
	add_child(fx)
	fx.global_position = at if at.is_finite() else global_position + Vector3(0.0, 2.0, 0.0)
	fx.rotation.x = PI
	fx.spark()
	_stump_fx[limb] = fx


func restore_limbs() -> void:
	super()

	for key: StringName in _stump_fx:
		var fx: DotFxThruster = _stump_fx[key]
		if fx != _thruster and is_instance_valid(fx):
			fx.queue_free()

	_stump_fx.clear()
	_thruster.broken = false
