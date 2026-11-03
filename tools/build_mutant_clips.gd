extends SceneTree

## Writes assets/zombies/mutant_clips.tres: the Mutant's idle, walk, run, attack, hit and death as
## AnimationPlayer tracks on its part rig. Rotations are rest * delta, so a clip survives a re-rig
## that keeps the bone names. Run: godot --headless --path . --script tools/build_mutant_clips.gd

const MODEL := "res://assets/zombies/zombie_mutant.glb"
const OUT := "res://assets/zombies/mutant_clips.tres"
const STEPS := 12

var _rest_q: Dictionary = {}
var _rest_p: Dictionary = {}


## A bone's delta (Euler, radians) at phase p in 0..1, per clip.
func _walk(bone: String, p: float) -> Vector3:
	var s := sin(p * TAU)
	match bone:
		"LegL": return Vector3(0.55 * s, 0.0, 0.0)
		"LegR": return Vector3(-0.55 * s, 0.0, 0.0)
		"ArmL": return Vector3(-0.4 * s, 0.0, 0.0)
		"ArmR": return Vector3(0.4 * s, 0.0, 0.0)
		"Spine": return Vector3(0.05, 0.12 * s, 0.0)
		"Head": return Vector3(-0.05, -0.1 * s, 0.0)
		"Hips": return Vector3(0.0, -0.08 * s, 0.04 * cos(p * TAU))
	return Vector3.ZERO


func _run(bone: String, p: float) -> Vector3:
	var s := sin(p * TAU)
	match bone:
		"LegL": return Vector3(0.95 * s, 0.0, 0.0)
		"LegR": return Vector3(-0.95 * s, 0.0, 0.0)
		"ArmL": return Vector3(-0.9 * s - 0.4, 0.0, 0.0)
		"ArmR": return Vector3(0.9 * s - 0.4, 0.0, 0.0)
		"Spine": return Vector3(0.3, 0.18 * s, 0.0)
		"Head": return Vector3(-0.2, -0.1 * s, 0.0)
		"Hips": return Vector3(0.0, -0.12 * s, 0.0)
	return Vector3.ZERO


func _idle(bone: String, p: float) -> Vector3:
	var s := sin(p * TAU)
	match bone:
		"Spine": return Vector3(0.03 * s, 0.0, 0.0)
		"ArmL": return Vector3(0.05 * s, 0.0, 0.03)
		"ArmR": return Vector3(0.05 * s, 0.0, -0.03)
		"Head": return Vector3(-0.03 * s, 0.0, 0.0)
	return Vector3.ZERO


## Keyed poses: [time fraction, {bone: delta}], linear in between after smoothing.
func _attack_keys() -> Array:
	return [
		[0.0, {}],
		[0.35, {"ArmR": Vector3(-2.7, 0, 0), "ArmL": Vector3(-0.6, 0, 0), "Spine": Vector3(-0.2, -0.35, 0), "Head": Vector3(-0.2, 0, 0)}],
		[0.5, {"ArmR": Vector3(-2.9, 0, 0), "ArmL": Vector3(-0.6, 0, 0), "Spine": Vector3(-0.25, -0.4, 0), "Head": Vector3(-0.2, 0, 0)}],
		[0.62, {"ArmR": Vector3(-0.3, 0, 0), "ArmL": Vector3(-0.2, 0, 0), "Spine": Vector3(0.45, 0.45, 0), "Head": Vector3(0.2, 0, 0)}],
		[0.78, {"ArmR": Vector3(-0.2, 0, 0), "Spine": Vector3(0.4, 0.35, 0), "Head": Vector3(0.15, 0, 0)}],
		[1.0, {}],
	]


func _hit_keys() -> Array:
	return [
		[0.0, {}],
		[0.2, {"Head": Vector3(-0.9, 0.2, 0), "Spine": Vector3(-0.45, 0.0, 0.0), "Hips": Vector3(-0.15, 0, 0), "ArmL": Vector3(0.9, 0, 0), "ArmR": Vector3(0.9, 0, 0)}],
		[0.55, {"Head": Vector3(-0.35, 0.05, 0), "Spine": Vector3(-0.15, 0, 0), "Hips": Vector3(-0.05, 0, 0)}],
		[1.0, {}],
	]


func _death_keys() -> Array:
	return [
		[0.0, {}],
		[0.25, {"Spine": Vector3(-0.3, 0, 0), "Head": Vector3(-0.5, 0, 0), "ArmL": Vector3(0.6, 0, 0), "ArmR": Vector3(0.6, 0, 0), "LegL": Vector3(0.2, 0, 0)}],
		[0.7, {"Hips": Vector3(-1.15, 0, 0), "HipsY": Vector3(0, -0.55, 0), "Spine": Vector3(-0.25, 0, 0), "Head": Vector3(-0.5, 0, 0), "ArmL": Vector3(1.0, 0, -0.5), "ArmR": Vector3(1.0, 0, 0.5), "LegL": Vector3(0.5, 0, 0), "LegR": Vector3(-0.3, 0, 0)}],
		[1.0, {"Hips": Vector3(-1.5708, 0, 0), "HipsY": Vector3(0, -1.0, 0), "Spine": Vector3(-0.15, 0, 0), "Head": Vector3(-0.3, 0, 0), "ArmL": Vector3(1.4, 0, -0.7), "ArmR": Vector3(1.2, 0, 0.7), "LegL": Vector3(0.2, 0, 0), "LegR": Vector3(-0.1, 0, 0)}],
	]


func _init() -> void:
	var scene := (load(MODEL) as PackedScene).instantiate()
	var skel := scene.find_children("*", "Skeleton3D", true, false).front() as Skeleton3D
	var prefix := String(scene.get_path_to(skel))

	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		_rest_q[n] = skel.get_bone_rest(i).basis.get_rotation_quaternion()
		_rest_p[n] = skel.get_bone_rest(i).origin

	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _loop(prefix, 2.4, _idle, ["Spine", "ArmL", "ArmR", "Head"]))
	lib.add_animation(&"walk", _loop(prefix, 1.2, _walk, ["LegL", "LegR", "ArmL", "ArmR", "Spine", "Head", "Hips"], 0.05))
	lib.add_animation(&"run", _loop(prefix, 0.62, _run, ["LegL", "LegR", "ArmL", "ArmR", "Spine", "Head", "Hips"], 0.12))
	lib.add_animation(&"attack", _keyed(prefix, 1.1, _attack_keys(), false))
	lib.add_animation(&"hit", _keyed(prefix, 0.5, _hit_keys(), false))
	lib.add_animation(&"death", _keyed(prefix, 1.3, _death_keys(), true))
	var err := ResourceSaver.save(lib, OUT)
	print("mutant clips: ", OUT, " err=", err, " tracks=", lib.get_animation(&"walk").get_track_count())
	scene.free()
	quit(0 if err == OK else 1)


func _rot(prefix: String, a: Animation, bone: String) -> int:
	var t := a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(t, NodePath("%s:%s" % [prefix, bone]))
	return t


func _q(bone: String, d: Vector3) -> Quaternion:
	return (_rest_q[bone] as Quaternion) * Quaternion.from_euler(d)


func _loop(prefix: String, length: float, f: Callable, bones: Array, bob := 0.0) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR

	for bone: String in bones:
		var t := _rot(prefix, a, bone)
		for k in STEPS + 1:
			var p := float(k) / STEPS
			a.rotation_track_insert_key(t, p * length, _q(bone, f.call(bone, p)))

	if bob > 0.0:
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath("%s:Hips" % prefix))
		for k in STEPS + 1:
			var p := float(k) / STEPS
			var up := absf(sin(p * TAU)) * bob
			a.position_track_insert_key(t, p * length, (_rest_p["Hips"] as Vector3) + Vector3(0.0, up - bob * 0.5, 0.0))

	return a


func _keyed(prefix: String, length: float, keys: Array, hold: bool) -> Animation:
	var a := Animation.new()
	a.length = length
	var bones := {}

	for k: Array in keys:
		for b: String in (k[1] as Dictionary):
			if b != "HipsY":
				bones[b] = true

	for bone: String in bones:
		var t := _rot(prefix, a, bone)
		a.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC)
		for k: Array in keys:
			var d: Vector3 = (k[1] as Dictionary).get(bone, Vector3.ZERO)
			a.rotation_track_insert_key(t, float(k[0]) * length, _q(bone, d))

	if hold:
		var t := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(t, NodePath("%s:Hips" % prefix))
		for k: Array in keys:
			var d: Vector3 = (k[1] as Dictionary).get("HipsY", Vector3.ZERO)
			a.position_track_insert_key(t, float(k[0]) * length, (_rest_p["Hips"] as Vector3) + d)

	return a
