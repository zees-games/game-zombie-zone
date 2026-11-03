extends Node
## Fixed-seed, physics-free-of-randomness check of the zombie nav around known snag spots: every nav edge
## near a spot is swept with a zombie-sized capsule against the world; an edge the body cannot walk is a snag.
##   godot --headless --path . res://tools/spot_probe.tscn -- [--clear=N] [map x,y,z ...]
## Prints blocked edges per spot; exits 1 when any is blocked. No zombie, no timing: the same numbers every run.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const RADIUS := 0.32
const HEIGHT := 1.75
## Feet lifted off the line: a stair tread or kerb is climbed, a hanging prop or a wall is not.
const LIFT := 0.3
const STEP := 0.25
const PAIRS := 60
const NEAR := 10.0
const SPOTS := [
	["zm_chaos_city", Vector3(-40.0, 0.0, -31.3)],
	["ze_biohazard_manor", Vector3(-5.6, 1.8, 28.5)],
	["zm_house_outbreak", Vector3(15.0, -2.8, -3.9)],
]

var _game: ZzGame
var _verbose := OS.get_cmdline_user_args().has("--verbose")


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	_run.call_deferred()


func _run() -> void:
	var spots: Array = SPOTS
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and not args[0].begins_with("--"):
		spots = [[args[0], _vec(args[1])]]
	var code := 0
	var by_map := {}
	for s: Array in spots:
		(by_map.get_or_add(s[0], []) as Array).append(s[1])
	for id: String in by_map:
		var blocked := await _probe_map(id, by_map[id])
		for line: String in blocked:
			print(line)
			if line.contains(" blocked") and not line.ends_with(" 0 blocked"):
				code = 1
	get_tree().quit(code)


func _probe_map(id: String, at: Array) -> PackedStringArray:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.map_ids = PackedStringArray([id])
	_game = ZzGame.new()
	_game.config = config
	_game.authoritative = true
	_game.draw_world = false
	_game.register_service = false
	add_child(_game)
	_game.set_physics_process(false)
	var p := _game.add_player(&"u100", "Bot")
	p.is_bot = true
	_game.start()
	for i in 10:
		_game.simulate(0.05)
		await get_tree().physics_frame
	var graph := _game.horde.spawner.nav as DotNpcNavGraph if _game.horde != null and _game.horde.spawner != null else null
	var nav: DotNpcNavData = graph.data if graph != null else null
	var out := PackedStringArray()
	if nav == null:
		out.append("%s: no nav blocked" % id)
		return out
	var space := _game.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT - LIFT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = _game.physics.layer_mask(&"world")
	for spot: Vector3 in at:
		var near := nav.points_within(spot, NEAR)
		var sorted := Array(near)
		sorted.sort()
		var checked := 0
		var legs := 0
		var bad := PackedStringArray()
		var n := sorted.size()
		for i in mini(n, PAIRS):
			var from := nav.points[sorted[i * n / mini(n, PAIRS)]]
			var to := nav.points[sorted[(i * 7 + 3) % n]]
			var path := graph.find_smooth_path(from, to, -1.0, false, 0)
			if path.size() < 2:
				continue
			checked += 1
			for k in path.size() - 1:
				legs += 1
				var hit := _edge_hit(space, query, path[k], path[k + 1])
				if hit != Vector3.INF:
					bad.append("    leg %s -> %s blocked at %s" % [_f(path[k]), _f(path[k + 1]), _f(hit)])
		out.append("%s %s: %d paths, %d legs, %d blocked" % [id, _f(spot), checked, legs, bad.size()])
		out.append_array(bad.slice(0, 6))
	remove_child(_game)
	_game.free()
	await get_tree().process_frame
	return out


func _edge_hit(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, a: Vector3, b: Vector3) -> Vector3:
	var n := maxi(ceili(a.distance_to(b) / STEP), 1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (LIFT + shape_half(query)))
		var found := space.intersect_shape(query, 1)
		if not found.is_empty():
			if _verbose:
				var c: Variant = found[0]["collider"]
				var owner_node: Variant = (c as CollisionObject3D).shape_owner_get_owner((c as CollisionObject3D).shape_find_owner(int(found[0]["shape"])))
				var cs := owner_node as CollisionShape3D
				var box := cs.shape as BoxShape3D if cs != null else null
				print("      hit at %s size %s yaw %.0f" % [_f(cs.global_position), box.size if box != null else cs.shape, rad_to_deg(cs.global_rotation.y)] if cs != null else "      hit ?")
			return p
	return Vector3.INF


func shape_half(query: PhysicsShapeQueryParameters3D) -> float:
	return (query.shape as CapsuleShape3D).height * 0.5


static func _f(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]


static func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
