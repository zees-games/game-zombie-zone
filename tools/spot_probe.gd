extends Node
## Fixed-seed check of the zombie nav around known snag spots: each nearby edge is swept with a capsule; a blocked one is a snag.
##   godot --headless --path . res://tools/spot_probe.tscn -- [--survival [--maps=a,b]] [--reach] [map x,y,z]
## --reach: every spawn to every post must have a full path (stand-in and zombie filters); exits 1 on any unreachable pair or blocked edge.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNavPrune := preload("../game/zz_nav_prune.gd")
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
	query.collision_mask = ZzNavPrune.body_mask(_game.physics)
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
			jobs.append(["survivor spawn", a, "post", b, true])
	for a in zombies:
		for b in posts:
			jobs.append(["zombie spawn", a, "post", b])
		for b in survivors:
			jobs.append(["zombie spawn", a, "survivor spawn", b])
	graph.filter = graph.bot_filter
	graph.relabel()
	out.append("  as a stand-in (no drops, stairs walked):")
	out.append_array(_reach_causes(graph, survivors, [] as Array[Vector3], posts))
	graph.filter = null
	graph.relabel()
	out.append("  as a zombie (drops down only):")
	out.append_array(_reach_causes(graph, [] as Array[Vector3], zombies, posts))
	var bad := PackedStringArray()
	for j: Array in jobs:
		graph.filter = graph.bot_filter if j.size() > 4 else null
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


## Per endpoint: off the graph (no point within the snap), or the graph piece it lands in with that piece's size.
func _reach_causes(graph: DotNpcNavGraph, survivors: Array[Vector3], zombies: Array[Vector3], posts: Array[Vector3]) -> PackedStringArray:
	var out := PackedStringArray()
	var sizes := {}
	for c in graph._component:
		sizes[c] = int(sizes.get(c, 0)) + 1
	var biggest := -1
	for c in sizes:
		if biggest < 0 or int(sizes[c]) > int(sizes[biggest]):
			biggest = c
	out.append("  graph: %d points, %d pieces, main piece %d points" % [graph.data.point_count(), sizes.size(), int(sizes.get(biggest, 0))])
	var pts := graph.data.points
	var island_ids := {}
	for i in pts.size():
		var c: int = graph._component[i]
		if c != biggest and not island_ids.has(c):
			island_ids[c] = i
	for c in island_ids:
		var best := INF
		var near := Vector3.ZERO
		var mine := Vector3.ZERO
		for i in pts.size():
			if graph._component[i] != c:
				continue
			for j in graph.data.points_within(pts[i], 6.0):
				if graph._component[j] == biggest and pts[i].distance_to(pts[j]) < best:
					best = pts[i].distance_to(pts[j])
					near = pts[j]
					mine = pts[i]
		out.append("  piece %d (%d points) at %s: %s" % [c, int(sizes[c]), _f(mine), "no main-piece point within 6 m" if best == INF else "nearest main point %s, %.1f m (dy %.2f)" % [_f(near), best, near.y - mine.y]])
	var no_end := 0
	var lines2 := PackedStringArray()
	for l: Array in _game.map_doc.get("nav", {}).get("links", []):
		var a := graph.data.nearest_point(Vector3(l[0], l[1], l[2]), 2.0)
		var b := graph.data.nearest_point(Vector3(l[3], l[4], l[5]), 2.0)
		if a < 0 or b < 0:
			no_end += 1
			lines2.append("      link end has no point: %s %s" % [_f(Vector3(l[0], l[1], l[2])) + (" (no point)" if a < 0 else ""), _f(Vector3(l[3], l[4], l[5])) + (" (no point)" if b < 0 else "")])
	out.append("  doc links: %d, %d with an end on no point (2 m snap)" % [_game.map_doc.get("nav", {}).get("links", []).size(), no_end])
	out.append_array(lines2.slice(0, 8))
	for group: Array in [["survivor spawn", survivors], ["zombie spawn", zombies], ["post", posts]]:
		var off := 0
		var island := 0
		var lines := PackedStringArray()
		for p: Vector3 in group[1]:
			var i := graph.data.nearest_point(p, REACH_SNAP)
			if i < 0:
				off += 1
				lines.append("      off graph %s (nearest point %.1f m)" % [_f(p), p.distance_to(graph.data.points[graph.data.nearest_point(p, 4096.0)])])
			elif graph._component[i] != biggest:
				island += 1
				lines.append("      island of %d points %s" % [int(sizes[graph._component[i]]), _f(p)])
		out.append("  %s: %d total, %d off graph, %d on a non-main piece" % [group[0], (group[1] as Array).size(), off, island])
		out.append_array(lines.slice(0, 6))
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
