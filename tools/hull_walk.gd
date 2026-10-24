extends Node
## Walks a person's capsule along a line on a converted map, once on its boxes alone and once with
## the world pack's hulls (`world_collision`): the proof that what the wire budget dropped holds a body.
##   godot --headless --path . res://tools/hull_walk.tscn -- <map id> x0,y0,z0 x1,y1,z1
## Prints one line per pass; exits 1 when the pass with hulls dips more than SAG below the line or stops short of its end.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const SPEED := 4.0
const GRAVITY := 20.0
## How far a walk may dip below its ends and still be on the floor (a rope bridge sags).
const SAG := 2.0

var _game: ZzGame


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var id := StringName(args[0] if args.size() > 0 else "ze_potc")
	var from := _vec(args[1] if args.size() > 1 else "-29.3,27.6,-44.2")
	var to := _vec(args[2] if args.size() > 2 else "-15.3,27.5,-44.2")
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.map_ids = PackedStringArray([String(id)])
	_game = ZzGame.new()
	_game.config = config
	_game.authoritative = true
	_game.draw_world = false
	_game.register_service = false
	add_child(_game)
	_game.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var hulls := _game.map.world_collision
	print("%s: %s hulls" % [id, hulls.get_child_count() if hulls != null else 0])
	var code := 0
	for with_hulls: bool in [false, true]:
		if hulls != null:
			hulls.collision_layer = _game.physics.layer_mask(&"world") if with_hulls else 0
		var walked: Array = await _walk(from, to)
		var lowest: float = walked[0]
		var end: Vector3 = walked[1]
		var fell := lowest < minf(from.y, to.y) - SAG or end.distance_to(to) > 1.0
		print("  %s: lowest feet %.2f m on a line from %.2f to %.2f, ended %.1f m from the far end: %s" % [
			"boxes and hulls" if with_hulls else "boxes only", lowest, from.y, to.y, end.distance_to(to), "FELL" if fell else "held"])
		if with_hulls and (fell or hulls == null):
			code = 1
	get_tree().quit(code)


## Feet lowest on the way and where the walk ended.
func _walk(from: Vector3, to: Vector3) -> Array:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	body.add_child(shape)
	body.collision_layer = 0
	body.collision_mask = _game.physics.layer_mask(&"world")
	body.floor_snap_length = 0.3
	add_child(body)
	body.global_position = from + Vector3.UP * 0.1
	var lowest := INF
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var steps := ceili(flat.length() / SPEED * 60.0) + 30
	for i in steps:
		await get_tree().physics_frame
		var left := Vector3(to.x - body.global_position.x, 0.0, to.z - body.global_position.z)
		var v := left.normalized() * SPEED if left.length() > 0.2 else Vector3.ZERO
		body.velocity = Vector3(v.x, body.velocity.y - GRAVITY / 60.0 if not body.is_on_floor() else 0.0, v.z)
		body.move_and_slide()
		lowest = minf(lowest, body.global_position.y)
	var end := body.global_position
	body.queue_free()
	return [lowest, end]


static func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
