extends "zz_zombie_view.gd"

## The oil monster as drawn: its own baked model and clips (slide, mouth_open for the spit, bite, flinch, die),
## with a dark glossy material and goo drips. It keeps the zombie view's seams (build, present, flinch, die) so the
## world view treats it like any zombie. The mouth faces +Z in the file; this family's forward is -Z, so it is turned by PI.

const Model := preload("zz_oil_monster_model.gd")
const SLIDE_SPEED := 3.0
const ONE_SHOTS: Array[StringName] = [&"mouth_open", &"bite", &"flinch", &"die"]

var _dead_t := -1.0
var _flinch_left := 0.0


func build(p_kind: StringName, p_variant: int) -> void:
	if _model != null:
		return

	kind = p_kind
	variant = p_variant
	body_id = &"oil_monster"
	_look = look_for(&"common", 0)
	var scene := _scene(ZzPaths.rebase(Model.MODEL))

	if scene == null:
		_model = _capsule()
		add_child(_model)
		return

	_model = scene.instantiate() as Node3D
	_model.basis = Basis(Vector3.UP, PI)
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	for m: Node in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visibility_range_end = lod.draw_until if lod != null else 120.0

	_mesh = _model.find_children("*", "MeshInstance3D", true, false).front() as MeshInstance3D
	_play(&"idle", 1.0)


func _qualified(clip: StringName) -> StringName:
	return clip


func present(delta: float, anim: int, _flags: int) -> void:
	if _model == null or _anim == null:
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
		_anim.advance(delta)
		return

	_flinch_left = maxf(_flinch_left - delta, 0.0)
	var clip := &"idle"
	var rate := 1.0

	if _flinch_left > 0.0:
		clip = &"flinch"
	elif anim == ZzZombieBody.Anim.SPIT:
		clip = &"mouth_open"
	elif anim == ZzZombieBody.Anim.ATTACK or anim == ZzZombieBody.Anim.STRIKE_DOWN:
		clip = &"bite"
	elif _speed > 0.3:
		clip = &"slide"
		rate = clampf(_speed / SLIDE_SPEED, 0.4, 2.0)

	if clip != _clip:
		_clip = clip
		_anim.play(clip, 0.2)

	_anim.speed_scale = rate
	_anim.advance(delta)


func flinch(_from_side: float = 1.0) -> void:
	if _dead_t < 0.0:
		_flinch_left = 0.4
		_clip = &""


func die(_reaction: StringName, _push: Vector3, _seed: int) -> void:
	if _dead_t < 0.0 and _anim != null:
		_dead_t = 0.0
		_clip = &"die"
		_anim.speed_scale = 1.0
		_anim.play(&"die", 0.1)


func set_fade(_alpha: float) -> void:
	pass


func fade() -> float:
	return 1.0


func sever_limb(_limb: StringName, _d: Dictionary, _impulse: Vector3) -> Vector3:
	return Vector3.INF


func stump_limb(_limb: StringName, _d: Dictionary) -> Vector3:
	return Vector3.INF
