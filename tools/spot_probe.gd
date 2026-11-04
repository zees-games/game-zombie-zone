extends Node
## Fixed-seed, physics-free-of-randomness check of the zombie nav around known snag spots: every nav edge
## near a spot is swept with a zombie-sized capsule against the world; an edge the body cannot walk is a snag.
##   godot --headless --path . res://tools/spot_probe.tscn -- [--survival [--maps=a,b]] [map x,y,z]
## --survival: every survival map, SURVEY_SPOTS evenly spaced nav points each.
## --reach (with --survival): from every survivor spawn to every post and from every zombie spawn to every post and
## survivor spawn, the zombies' own path query must find a full path; prints the unreachable pairs, exits 1 on any.
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
const SURVEY_SPOTS := 4
## Snap radius the horde planner uses when it routes spawns to posts.
const REACH_SNAP := 2.5
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
	if _verbose:
		print("  engine up %d ms" % Time.get_ticks_msec())
	var spots: Array = SPOTS
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and not args[0].begins_with("--"):
		spots = [[args[0], _vec(args[1])]]
	var code := 0
	var by_map := {}
	if args.has("--survival"):
		var only := PackedStringArray()
		for a in args:
			if a.begins_with("--maps="):
				only = a.substr(7).split(",")
		for id: String in _survival_maps():
			if only.is_empty() or only.has(id):
				by_map[id] = []
	else:
		for s: Array in spots:
			(by_map.get_or_add(s[0], []) as Array).append(s[1])
	for id: String in by_map:
		var blocked: PackedStringArray
		if args.has("--reach"):
			blocked = await _reach_map(id)
		else:
			blocked = await _probe_map(id, by_map[id])
		for line: String in blocked:
			print(line)
			if (line.contains(" blocked") and not line.ends_with(" 0 blocked")) or (line.begins_with("MAP ") and line.contains(" unreachable") and not line.ends_with(" 0 unreachable")):
				code = 1
	if _verbose:
		print("  done %d ms" % Time.get_ticks_msec())
	get_tree().quit(code)


func _boot(id: String) -> void:
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


func _probe_map(id: String, at: Array) -> PackedStringArray:
	var t0 := Time.get_ticks_msec()
	await _boot(id)
	var t1 := Time.get_ticks_msec()
	var graph := _game.horde.spawner.nav as DotNpcNavGraph if _game.horde != null and _game.horde.spawner != null else null
	for a in OS.get_cmdline_user_args():
		if graph != null and a.begins_with("--ratio="):
			graph.straight_width_ratio = float(a.substr(8))
	var t1b := Time.get_ticks_msec()
	var nav: DotNpcNavData = graph.data if graph != null else null
	if _verbose:
		print("  data %d ms (graph at %d)" % [Time.get_ticks_msec() - t1b, t1b - t0])
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
	if at.is_empty():
		var all := nav.points_within(nav.points[0], 100000.0)
		all.sort()
		for i in SURVEY_SPOTS:
			at.append(nav.points[all[(i * 2 + 1) * all.size() / (SURVEY_SPOTS * 2)]])
	var t2 := Time.get_ticks_msec()
	if _verbose and nav != null:
		print("  spots chosen after %d ms, %d points" % [t2 - t1b, nav.points.size()])
	var total := 0
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
		total += bad.size()
	if _verbose:
		print("  timing %s: start %d ms, probe %d ms" % [id, t1 - t0, Time.get_ticks_msec() - t2])
	out.append("MAP %s: %d blocked" % [id, total])
	var t3 := Time.get_ticks_msec()
	remove_child(_game)
	if _verbose:
		print("  removed %d ms" % (Time.get_ticks_msec() - t3))
	_game.free()
	if _verbose:
		print("  freed %d ms" % (Time.get_ticks_msec() - t3))
	await get_tree().process_frame
	return out


func _reach_map(id: String) -> PackedStringArray:
	await _boot(id)
	var out := PackedStringArray()
	var graph := _game.horde.spawner.nav as DotNpcNavGraph if _game.horde != null and _game.horde.spawner != null else null
	if graph == null or not graph.is_ready():
		out.append("MAP %s: no nav graph, 1 unreachable" % id)
		_free_game()
		return out
	var doc: Dictionary = _game.map_doc
	var survivors: Array[Vector3] = []
	for s: Variant in (doc.get("spawns", {}) as Dictionary).get("survivors", []):
		survivors.append(_vec3(s["at"] if s is Dictionary else s))
	var zombies: Array[Vector3] = []
	for z: Variant in doc.get("zombie_spawns", []):
		zombies.append(_vec3(z))
	var posts: Array[Vector3] = []
	for q: Variant in doc.get("posts", []):
		posts.append(_vec3(q))
	var saved_filter = graph.filter
	graph.filter = null
	var jobs: Array = []
	for a in survivors:
		for b in posts:
			jobs.append(["survivor spawn", a, "post", b])
	for a in zombies:
		for b in posts:
			jobs.append(["zombie spawn", a, "post", b])
		for b in survivors:
			jobs.append(["zombie spawn", a, "survivor spawn", b])
	var bad := PackedStringArray()
	for j: Array in jobs:
		var path := graph.find_path(j[1], j[3], REACH_SNAP, false)
		if path.size() < 2 or graph.last_partial:
			bad.append("    %s %s -> %s %s unreachable" % [j[0], _f(j[1]), j[2], _f(j[3])])
	graph.filter = saved_filter
	out.append("%s: %d pairs (%d survivor spawns, %d zombie spawns, %d posts), %d unreachable" % [id, jobs.size(), survivors.size(), zombies.size(), posts.size(), bad.size()])
	out.append_array(bad.slice(0, 12))
	out.append("MAP %s: %d unreachable" % [id, bad.size()])
	_free_game()
	await get_tree().process_frame
	return out


func _free_game() -> void:
	remove_child(_game)
	_game.free()


static func _vec3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _edge_hit(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, a: Vector3, b: Vector3) -> Vector3:
	var n := maxi(ceili(a.distance_to(b) / STEP), 1)
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		var found := _body_at(space, query, p)
		# The line between two points' heights is not the ground: where the floor rises a little between them
		# (a kerb, a hump) the body steps onto it. Only a sample blocked on the ground too is a real block.
		if not found.is_empty() and not _body_at(space, query, _on_ground(space, query.collision_mask, p)).is_empty():
			if _verbose:
				var c: Variant = found[0]["collider"]
				var owner_node: Variant = (c as CollisionObject3D).shape_owner_get_owner((c as CollisionObject3D).shape_find_owner(int(found[0]["shape"])))
				var cs := owner_node as CollisionShape3D
				var box := cs.shape as BoxShape3D if cs != null else null
				print("      hit at %s size %s yaw %.0f" % [_f(cs.global_position), box.size if box != null else cs.shape, rad_to_deg(cs.global_rotation.y)] if cs != null else "      hit ?")
			return p
	return Vector3.INF


func _body_at(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, p: Vector3) -> Array[Dictionary]:
	query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (LIFT + shape_half(query)))
	return space.intersect_shape(query, 1)


func _on_ground(space: PhysicsDirectSpaceState3D, mask: int, p: Vector3) -> Vector3:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * LIFT * 2.0, p + Vector3.DOWN * LIFT * 2.0, mask))
	return hit["position"] if not hit.is_empty() else p


func shape_half(query: PhysicsShapeQueryParameters3D) -> float:
	return (query.shape as CapsuleShape3D).height * 0.5


static func _survival_maps() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := ProjectSettings.globalize_path("res://maps")
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
			if doc is Dictionary and str(doc.get("mode", "")) == "survival":
				out.append(file.get_basename())
	out.sort()
	return out


static func _f(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]


static func _vec(s: String) -> Vector3:
	var p := s.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
