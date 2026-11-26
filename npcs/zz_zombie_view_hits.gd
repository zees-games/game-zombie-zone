extends "zz_zombie_view_legs.gd"

## A zombie hit: the flinch a shot starts, the hit and death clips it picks, the limb it throws and the blood a cut sprays. The layer under zz_zombie_view.gd.

var _hit_left := 0.0
var _hit_head := false
var _hit_count := 0
var _rise_left := 0.0
## Seconds left knocked down by a shot leg, and the region (1 head, 2 chest, 3 arm, 4 leg) of the last hit.
var _down_left := 0.0
## The upper body torn off by a heavy chest blast: [member GSNpcGibs] reads it like a limb def, rooted at the torso bone.
const TORSO_GIB := {"bones": ["Torso"], "radius": 0.3, "tip": 0.3, "gib_mass": 30.0, "gib_seconds": 14.0}
var _last_region := 0

## A cut paints the room the way the limb was thrown: a fan of splatters along the throw (up a little, so a wall is reached), and one on the floor under the wound. The count follows the gore level; the decal ring bounds the total.
func _spray_walls(joint: Vector3, impulse: Vector3) -> void:
	if blood == null or joint == Vector3.INF or GSNpcGore.level < 2:
		return
	var along := impulse + Vector3.UP * maxf(impulse.length() * 0.25, 0.5)
	var count := 3 if GSNpcGore.level < 3 else 6
	var _drawn := blood.splat_burst(joint, along, count, 0.7, 3.5)
	var _under := blood.splat_below(joint, 2.5)


## The clip and rate of a hit number [param n] on a standing body: a head hit is the head clip (or a quick jolt of
## the chest's), a body hit is the chest clip, or the same quicker. The library's knockback is a whole fall and get-up with the pelvis carried away, so only a launch's death plays it.
static func hit_variant(head: bool, n: int) -> Array:
	var pick := posmod(n, 3)
	if head:
		return [&"ual_hit_head", 1.0] if pick != 2 else [&"ual_hit_chest", 1.4]
	return [[&"ual_hit_chest", 1.0], [&"ual_hit_chest", 1.5], [&"ual_hit_chest", 1.25]][pick]


## The clip a body dies by: a launch is the library's knockback, otherwise the death's seed picks the kit's fall or the library's.
## A shot head drops quick (the library's death), a shot leg folds (the kit's slow fall).
static func death_clip(reaction: StringName, seed: int, region := 0) -> StringName:
	if reaction == &"power_launch" or reaction == &"headshot_launch":
		return &"ual_knockback"
	if region == 1:
		return &"ual_death"
	if region == 4:
		return &"death"
	return &"death" if reaction == &"face_plant" or seed & 1 == 0 else &"ual_death"


## True when this body has the real clip [param clip] (the file is missing or the body is a capsule otherwise).
func _has(clip: StringName) -> bool:
	return _anim != null and _anim.has_animation(_qualified(clip))


## What a shot in a limb adds to the chest's flinch: a hit arm is thrown back, a hit leg buckles at the knee and
## drops the hips toward its side (the side is the one the shot came in on).
func _flinch_limb(snap: float) -> void:
	var side := ".L" if _flinch_side > 0.0 else ".R"

	if _flinch_region == 3:
		_pitch_limb("UpperArm" + side, -snap * 2.2)
		_pitch_limb("LowerArm" + side, snap * 1.2)
	elif _flinch_region == 4:
		_pitch_limb("UpperLeg" + side, snap * 0.9)
		_pitch_limb("LowerLeg" + side, -snap * 1.6)
		var hips: int = _bones.get(&"Hips", -1)
		if hips >= 0:
			_roll_index(hips, _flinch_side * snap * 0.35)


func _pitch_limb(bone: String, angle: float) -> void:
	var index: int = _limbs.get(bone, -1)

	if index >= 0:
		_pitch_index(index, angle)


## Rolls a bone about the body's own forward axis, whatever the bone's own axes are.
func _roll_index(index: int, angle: float) -> void:
	var parent := _skeleton.get_bone_parent(index)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var global := _skeleton.get_bone_global_pose(index).basis.orthonormalized()
	var local := parent_basis.inverse() * Basis(Vector3.BACK, angle) * global
	_skeleton.set_bone_pose_rotation(index, local.orthonormalized().get_rotation_quaternion())


func _pitch_index(index: int, angle: float) -> void:
	var parent := _skeleton.get_bone_parent(index)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	var global := _skeleton.get_bone_global_pose(index).basis.orthonormalized()
	var local := parent_basis.inverse() * Basis(Vector3.RIGHT, -angle) * global
	_skeleton.set_bone_pose_rotation(index, local.orthonormalized().get_rotation_quaternion())


## Hit: a flinch over whatever it is doing. [param from_side] is -1 or 1 for which side the hit
## came from; a flinch already running is not restarted, so a shotgun's pellets are one flinch.
func flinch(from_side: float = 1.0, head := false, region := 2) -> void:
	_last_region = region
	if _death.is_empty() and _flinch < 0.5:
		# Every other leg hit knocks it down, by the hit's count so it is the same on every screen.
		if region == 4 and _down_left <= 0.0 and posmod(_hit_count + variant, 2) == 0:
			_down_left = 1.4
		_flinch = 1.0
		_hit_head = head
		_hit_count += 1
		_hit_left = 0.6
		# A flinch plays out whole.
		var pick := hit_variant(head, _hit_count + variant)
		if _has(pick[0]):
			_hit_left = maxf(_hit_left, _anim.get_animation(_qualified(pick[0])).length / float(pick[1]))
		_flinch_side = signf(from_side) if from_side != 0.0 else 1.0
		_flinch_region = region


## A hit seen in the snapshot. [param code] is the server's hit code (region in the low 3 bits, side in the 4th); 0 means
## no location came, so the flinch leans away from the viewer (shots mostly come from the camera) and the second bit of
## [param health] picks the head or the chest clip.
func flinch_from(code: int, health: int) -> void:
	if code != 0:
		var region := code & 7
		flinch(1.0 if (code & 8) != 0 else -1.0, region == 1, region)
	else:
		flinch(_camera_side(), (health & 2) != 0)


## Which side of the body a shot from the camera lands on: 1 on its left, -1 on its right, 1 when unknown.
func _camera_side() -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var body := get_parent() as Node3D
	if cam == null or body == null:
		return 1.0
	return 1.0 if (cam.global_position - body.global_position).dot(global_transform.basis.x) >= 0.0 else -1.0
