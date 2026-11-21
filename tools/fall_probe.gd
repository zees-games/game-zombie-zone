extends Node
## Finds the places a survivor falls out of a map or gets stuck, without a person: holes in the ground,
## capsules dropped from start points and floor samples that end below the floor, outside the walls or
## embedded, and spots a capsule cannot move away from.
##   godot --headless --path . res://tools/fall_probe.tscn -- <map id>|--all [--step=2.0] [--drops=300] [--quiet] [--suggest] [--edges]
## --edges walks a capsule along every edge of the horde's graph and prints the places the physics world blocks one the graph calls walkable (a prop in a doorway).
## --suggest prints, per map, the spec `extra_links` that would join each piece of the horde's graph to a neighbouring one.
## Exits 1 when any map has a hole, a fall, an embedded start or a trap.
## Causes: HOLE_DRAWN (a drawn solid box is over the hole, so its collision is missing), HOLE_NO_HULLS (the
## document names world hulls and none loaded), HOLE_BARE (the nav floor has nothing under it at all).

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzPaths := preload("../game/zz_paths.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const RADIUS := 0.4
const HEIGHT := 1.8
## A ray down from this far over a nav floor must find ground within [member FLOOR_TOLERANCE] of its height.
const RAY_UP := 0.6
const FLOOR_TOLERANCE := 0.75
const SETTLE_FRAMES := 150
const PROBE_FRAMES := 30
const PROBE_SPEED := 3.0
const GRAVITY := 20.0
## A fall this far below where a capsule was put is a fall, whatever the map's own kill height says.
const FELL := 2.5
## A suggested link spans at most this far.
const LINK_REACH := 3.5

var _game: ZzGame
var _suggest := false
var _edges := false
var _p_map: ZzMap
var _p_doc: Dictionary
var _p_space: PhysicsDirectSpaceState3D
var _p_mask := 0
var _p_report: Dictionary
var _p_examples: PackedStringArray
var _p_causes: Dictionary
var _p_drawn: Array
var _p_no_hulls := false
var _p_kill := 0.0
var _p_floors: Array
var _p_samples: Array[Vector3] = []
var _p_with_hulls: Array[Vector3] = []
var _p_starts: Array[Vector3] = []
var _p_start_count := 0
var _p_picked: Array[Vector3] = []
var _p_lowest := 0.0
var _p_bodies: Array[CharacterBody3D] = []
var _p_put: Array[Vector3] = []
var _p_shoved: Array[bool] = []
var _p_skip: Array[bool] = []
var _p_settled: Array[Vector3] = []


static func ids_in_checkout() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in DirAccess.get_files_at(ZzPaths.rebase("res://maps")):
		if f.ends_with(".json"):
			ids.append(f.get_basename())
	ids.sort()
	return ids


func _ready() -> void:
	GSLog.set_level(GSLog.Level.WARN)
	_run.call_deferred()


func _run() -> void:
	var ids := PackedStringArray()
	var step := 2.0
	var drops := 300
	var quiet := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = float(a.substr(7))
		elif a.begins_with("--drops="):
			drops = int(a.substr(8))
		elif a == "--quiet":
			quiet = true
		elif a == "--suggest":
			_suggest = true
		elif a == "--edges":
			_edges = true
		elif a == "--all":
			ids = ids_in_checkout()
		else:
			ids.append_array(a.split(","))
	var failing := PackedStringArray()
	for id in ids:
		var report: Dictionary = await probe(StringName(id), step, drops)
		var bad: int = report["holes"] + report["falls"] + report["embedded"] + report["trapped"] + report["nav_void"] + report["route_off"]
		print("%s: %s" % [id, _line(report)])
		if bad > 0:
			failing.append(id)
		if bad > 0 or _edges or report["doors_blocked"] > 0:
			if not quiet:
				for what: String in report["examples"]:
					print("    ", what)
	print("failing maps (%d of %d): %s" % [failing.size(), ids.size(), ", ".join(failing)])
	get_tree().quit(1 if not failing.is_empty() else 0)


static func _line(r: Dictionary) -> String:
	return "%d nav points (%d over void, %d islands, %d route points cut off); %d floor points: %d holes %s (%d uneven); %d drops: %d fell (%d pushed out of a wall, not counted), %d embedded, %d trapped; %d doorways shut; hulls %d (%d floor points stand on them alone)" % [
		r["nav_points"], r["nav_void"], r["islands"], r["route_off"], r["points"], r["holes"], r["causes"], r["uneven"], r["dropped"], r["falls"], r["pushed_out"], r["embedded"], r["trapped"], r["doors_blocked"], r["hulls"], r["needs_hulls"]]


## Probes one map and returns the counts and a few examples of each fault.
func probe(id: StringName, step: float, drops: int) -> Dictionary:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(id)])
	_game = ZzGame.new()
	_game.config = config
	_game.authoritative = true
	_game.draw_world = false
	_game.register_service = false
	add_child(_game)
	_game.set_physics_process(false)
	for i in 8:
		await get_tree().physics_frame
	_p_map = _game.map
	_p_doc = _p_map.doc
	_p_report = {"points": 0, "holes": 0, "uneven": 0, "inside_solid": 0, "pushed_out": 0, "causes": {}, "dropped": 0, "falls": 0, "embedded": 0, "trapped": 0,
		"needs_hulls": 0, "nav_points": 0, "nav_void": 0, "islands": 0, "route_off": 0, "doors_blocked": 0, "hulls": _p_map.world_collision.get_child_count() if _p_map.world_collision != null else 0, "examples": PackedStringArray()}
	_p_examples = _p_report["examples"]
	_p_mask = _game.physics.collision_mask(&"player")
	_p_space = _p_map.get_world_3d().direct_space_state

	_p_kill = _p_map.kill_height()
	_p_floors = (_p_doc.get("nav", {}) as Dictionary).get("floors", [])
	_p_drawn = _drawn_boxes(_p_doc)
	_p_no_hulls = not (_p_doc.get("world_collision", {}) as Dictionary).is_empty() and int(_p_report["hulls"]) == 0
	_p_samples = []
	_p_with_hulls = []
	_scan_floor(step, drops)
	await _hull_only_floor()
	_pick_starts(drops)
	_nav_phase()
	await _drop_and_settle()
	_count_falls()
	await _probe_trapped()
	_game.queue_free()
	await get_tree().physics_frame
	return _p_report


func _scan_floor(step: float, drops: int) -> void:
	# (c) holes: a ray down over every floor rectangle.
	_p_causes = _p_report["causes"]
	for fl: Array in _p_floors:
		var y := float(fl[4])
		# A sliver is a rounding of the nav, not ground anybody stands on.
		if float(fl[2]) - float(fl[0]) < 1.0 or float(fl[3]) - float(fl[1]) < 1.0:
			continue
		var x := float(fl[0]) + step * 0.5
		while x < float(fl[2]) or x == float(fl[0]) + step * 0.5:
			var z := float(fl[1]) + step * 0.5
			while z < float(fl[3]) or z == float(fl[1]) + step * 0.5:
				var px := minf(x, float(fl[2]))
				var pz := minf(z, float(fl[3]))
				_p_report["points"] += 1
				var hit := _p_space.intersect_ray(PhysicsRayQueryParameters3D.create(
					Vector3(px, y + RAY_UP, pz), Vector3(px, y - 2.0, pz), _p_mask))
				if not hit.is_empty() and (hit["collider"] as Node).get_parent() == _p_map.world_collision:
					_p_with_hulls.append(Vector3(px, y, pz))
				var lower := hit.is_empty() or (hit["position"] as Vector3).y < y - FLOOR_TOLERANCE
				if lower:
					# Ground further down is a ramp or a step the nav rectangle rounds; nothing at all is a hole.
					var deep := _p_space.intersect_ray(PhysicsRayQueryParameters3D.create(
						Vector3(px, y - 1.0, pz), Vector3(px, _p_kill - 5.0, pz), _p_mask)) if hit.is_empty() else hit
					if not deep.is_empty():
						_p_report["uneven"] += 1
					elif _embedded(_p_space, Vector3(px, y, pz), _p_mask) != "":
						_p_report["inside_solid"] += 1
					else:
						var cause := "HOLE_DRAWN" if _under_drawn(_p_drawn, px, pz, y) else ("HOLE_NO_HULLS" if _p_no_hulls else "HOLE_BARE")
						_p_report["holes"] += 1
						_p_causes[cause] = int(_p_causes.get(cause, 0)) + 1
						if _p_examples.size() < 6:
							_p_examples.append("%s at (%.1f, %.2f, %.1f)" % [cause, px, y, pz])
				if _p_samples.size() < drops * 3 and int(_p_report["points"]) % maxi(1, int(5.0 / step) * int(5.0 / step)) == 0:
					_p_samples.append(Vector3(px, y, pz))
				z += step
			x += step


func _hull_only_floor() -> void:
	# A client that could not load the world pack plays on the boxes alone: how much floor is only a hull?
	if not _p_with_hulls.is_empty():
		var layers: Array[int] = [_p_map.world_collision.collision_layer, _p_map.world_clip.collision_layer if _p_map.world_clip != null else 0]
		_p_map.world_collision.collision_layer = 0
		if _p_map.world_clip != null:
			_p_map.world_clip.collision_layer = 0
		await get_tree().physics_frame
		for p in _p_with_hulls:
			var r := _p_space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * RAY_UP, p - Vector3.UP * FLOOR_TOLERANCE, _p_mask))
			if r.is_empty():
				_p_report["needs_hulls"] += 1
		_p_map.world_collision.collision_layer = layers[0]
		if _p_map.world_clip != null:
			_p_map.world_clip.collision_layer = layers[1]
		await get_tree().physics_frame


func _pick_starts(drops: int) -> void:
	# Starts, route, horde spawns and posts, then an even share of the floor _p_samples.
	_p_starts = []
	_p_lowest = INF
	for fl: Array in _p_floors:
		_p_lowest = minf(_p_lowest, float(fl[4]))
	for side: String in (_p_doc.get("spawns", {}) as Dictionary):
		for entry: Dictionary in _p_doc["spawns"][side]:
			_p_lowest = minf(_p_lowest, ZzMapDoc.v3(entry["at"]).y)
	var seats := ((_p_doc.get("spawns", {}) as Dictionary).get("survivors", []) as Array).size()
	for seat in seats:
		_p_starts.append(_p_map.spawn("survivors", seat)[0])
	_p_start_count = _p_starts.size()
	# The route's points are the author's path through the _p_map, not ground: some hang in the air, so they are not dropped.
	_p_picked = _p_starts.duplicate()
	var every := maxi(1, _p_samples.size() / maxi(1, drops - _p_picked.size()))
	for i in range(0, _p_samples.size(), every):
		_p_picked.append(_p_samples[i])


func _nav_phase() -> void:
	# The zombies' graph: points with no ground under them, and pieces the first survivor start does not reach.
	var nav := _nav_check(_p_map, _p_space, _p_mask, _p_starts)
	_p_report["nav_points"] = nav["points"]
	_p_report["nav_void"] = nav["void"]
	_p_report["islands"] = nav["islands"]
	_p_report["route_off"] = nav["route_off"]
	var shut := _door_walk(_p_map, _p_space, _p_mask)
	_p_report["doors_blocked"] = shut.size()
	for what: String in shut:
		if _p_examples.size() < 30:
			_p_examples.append(what)
	for what: String in nav["examples"]:
		if _p_examples.size() < 30:
			_p_examples.append(what)
	if int(nav["void"]) > 0:
		_p_causes["NAV_VOID"] = int(nav["void"])


func _drop_and_settle() -> void:
	# (a) and (b): drop capsules, let them settle, then try to leave.
	_p_bodies = []
	_p_put = []
	for p in _p_picked:
		var body := _body(_p_mask)
		add_child(body)
		body.global_position = p + Vector3.UP * 0.1
		_p_bodies.append(body)
		_p_put.append(p)
	_p_report["dropped"] = _p_bodies.size()
	await get_tree().physics_frame
	_p_shoved = []
	for i in _p_bodies.size():
		_p_shoved.append(false)
	_p_skip = []
	for i in _p_bodies.size():
		var inside := _embedded(_p_space, _p_bodies[i].global_position, _p_mask)
		_p_skip.append(inside != "")
		# A grid point inside a prop is the sample's fault; a start or route point inside one is the _p_map's.
		if inside != "" and i < _p_start_count:
			_p_report["embedded"] += 1
			_p_causes["EMBEDDED_" + inside] = int(_p_causes.get("EMBEDDED_" + inside, 0)) + 1
			if _p_examples.size() < 14:
				_p_examples.append("EMBEDDED start at %s in %s" % [_p_put[i], inside])
	for f in SETTLE_FRAMES:
		_fall(_p_bodies, Vector3.ZERO)
		await get_tree().physics_frame
		if f == 0:
			# A sample that depenetrates sideways on its first frame started inside a wall's skin; where it lands says nothing about the _p_map.
			for i in _p_bodies.size():
				var d := Vector2(_p_bodies[i].global_position.x - _p_put[i].x, _p_bodies[i].global_position.z - _p_put[i].z).length()
				_p_shoved[i] = d > 0.15 and i >= _p_start_count


func _count_falls() -> void:
	var region: AABB = _p_map.playable_region().grow(ZzMap.BOUNDARY_MARGIN + 1.0)
	_p_settled = []
	for i in _p_bodies.size():
		var at := _p_bodies[i].global_position
		_p_settled.append(at)
		var outside := region.size != Vector3.ZERO and not (at.x >= region.position.x and at.x <= region.end.x and at.z >= region.position.z and at.z <= region.end.z)
		if (at.y < _p_lowest - FELL or at.y < _p_kill or outside or not at.is_finite()) and _p_shoved[i]:
			_p_report["pushed_out"] += 1
		elif at.y < _p_lowest - FELL or at.y < _p_kill or outside or not at.is_finite():
			_p_report["falls"] += 1
			if _p_examples.size() < 20:
				_p_examples.append("FELL from %s to %s%s (lowest floor %.1f, kill %.1f)" % [_p_put[i], at, " (outside the walls)" if outside else "", _p_lowest, _p_kill])
			var under := _p_space.intersect_ray(PhysicsRayQueryParameters3D.create(_p_put[i] + Vector3.UP * RAY_UP, _p_put[i] - Vector3.UP * 1.0, _p_mask))
			if _p_examples.size() < 20:
				_p_examples.append("  ray under the drop: %s" % [("%s at y %.2f" % [under["collider"].get_parent().name if under["collider"].get_parent() else under["collider"].name, under["position"].y]) if not under.is_empty() else "nothing"])
			var kind := "DRAWN" if _under_drawn(_p_drawn, _p_put[i].x, _p_put[i].z, _p_put[i].y) else ("NO_HULLS" if _p_no_hulls else "BARE")
			_p_causes["FELL_" + kind] = 1 + int(_p_causes.get("FELL_" + kind, 0))


func _probe_trapped() -> void:
	var blocked: Array[int] = []
	blocked.resize(_p_bodies.size())
	for k in 8:
		var dir := Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0))
		for i in _p_bodies.size():
			_p_bodies[i].global_position = _p_settled[i]
			_p_bodies[i].velocity = Vector3.ZERO
		for f in PROBE_FRAMES:
			_fall(_p_bodies, dir * PROBE_SPEED)
			await get_tree().physics_frame
		for i in _p_bodies.size():
			var d := Vector2(_p_bodies[i].global_position.x - _p_settled[i].x, _p_bodies[i].global_position.z - _p_settled[i].z).length()
			if d < 0.3:
				blocked[i] += 1
	for i in _p_bodies.size():
		if blocked[i] == 8 and not _p_skip[i] and _p_settled[i].y >= _p_lowest - FELL:
			_p_report["trapped"] += 1
			if _p_examples.size() < 26:
				_p_examples.append("TRAPPED at %s (put at %s)" % [_p_settled[i], _p_put[i]])
	for b in _p_bodies:
		b.queue_free()


## Whether ground lies within half a nav cell of [param p]: the graph's grid overhangs a ledge by that much, and nobody stands there.
static func _ground_near(space: PhysicsDirectSpaceState3D, p: Vector3, mask: int) -> bool:
	for k in 8:
		var off := Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0)) * 0.5
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(p + off + Vector3.UP * RAY_UP, p + off - Vector3.UP * FELL, mask)).is_empty():
			return true
	return false


## Builds the horde's graph the way the server does. A point with nothing under it within [constant FELL] is a place the
## zombies walk over void; a piece that the first survivor start does not reach is an island (reported, not failed:
## a lift or a teleport joins some on purpose).
func _nav_check(map: Node, space: PhysicsDirectSpaceState3D, mask: int, starts: Array[Vector3]) -> Dictionary:
	var out := {"points": 0, "void": 0, "islands": 0, "route_off": 0, "examples": PackedStringArray()}
	var game := _game
	var doc: Dictionary = map.doc
	var gates := PackedStringArray()
	for box: Dictionary in doc.get("boxes", []):
		if box.has("gate"):
			gates.append(str(box["gate"]))
	var props_size := func(pid: StringName) -> Vector3:
		return game.props_catalogue.size_of(pid) if game.props_catalogue.has(pid) else Vector3.ZERO
	var nav_doc := ZzNpcs.with_nav_extra(doc, map.read_nav_extra(str(game.catalogue.roots.get(StringName(str(doc.get("id", ""))), ""))))
	var graph := GSNpcNavGraph.new(ZzNpcs.nav_for(nav_doc, props_size, gates))
	var pts: PackedVector3Array = graph.data.points
	out["points"] = pts.size()
	var labels: PackedInt32Array = graph.get("_component")
	var main := -1
	if not starts.is_empty():
		var near := graph.data.nearest_point(starts[0], 3.0)
		if near >= 0:
			main = labels[near]
	var sizes := {}
	var voids := 0
	var examples: PackedStringArray = out["examples"]
	for i in pts.size():
		sizes[labels[i]] = int(sizes.get(labels[i], 0)) + 1
		var p := pts[i]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * RAY_UP, p - Vector3.UP * FELL, mask))
		if hit.is_empty() and not _ground_near(space, p, mask):
			voids += 1
			if examples.size() < 8:
				examples.append("NAV_VOID point at %s" % p)
	out["void"] = voids
	for label: int in sizes:
		if label != main:
			out["islands"] += 1
	if main >= 0:
		# The route is the author's way through: where it first leaves the start's piece is where the graph is cut.
		var route: Array = doc.get("route", [])
		var last_on := -1
		var off := PackedStringArray()
		for i in route.size():
			var rp := ZzMapDoc.v3(route[i])
			var k := graph.data.nearest_point(rp, 2.5)
			if k >= 0 and labels[k] == main:
				last_on = i
			elif k >= 0:
				off.append("%d" % i)
		out["route_off"] = off.size()
		var mlo := Vector3(INF, INF, INF)
		var mhi := -mlo
		for i in pts.size():
			if labels[i] == main:
				mlo = mlo.min(pts[i])
				mhi = mhi.max(pts[i])
		examples.append("START'S GROUND of %d points from %s to %s" % [sizes[main], mlo, mhi])
		var runs := PackedStringArray()
		var prev := -2
		for i in route.size():
			var k2 := graph.data.nearest_point(ZzMapDoc.v3(route[i]), 2.5)
			var lab := labels[k2] if k2 >= 0 else -1
			if lab != prev:
				runs.append("%d:%s%s" % [i, "none" if lab < 0 else str(lab), "(start)" if lab == main else ""])
				prev = lab
		examples.append("ROUTE components by index: " + " ".join(runs))
		if not off.is_empty():
			examples.append("ROUTE_CUT %d of %d route points are off the start's ground (first %s; last on it: %d at %s)" % [
				off.size(), route.size(), ",".join(off.slice(0, 6)), last_on, route[last_on] if last_on >= 0 else "none"])
	if _edges:
		examples.append_array(_edge_report(graph.data, space, mask))
	if _suggest and sizes.size() > 1:
		_print_links(pts, labels, sizes, space, mask)
	if main >= 0 and sizes.size() > 1:
		# Where each large piece comes closest to the start's ground, and what stands between the two points.
		for label: int in sizes:
			if label == main or int(sizes[label]) < 100:
				continue
			var best := INF
			var pa := Vector3.ZERO
			var pb := Vector3.ZERO
			for i in pts.size():
				if labels[i] != label:
					continue
				for j in pts.size():
					if labels[j] != main:
						continue
					var d2 := pts[i].distance_squared_to(pts[j])
					if d2 < best:
						best = d2
						pa = pts[i]
						pb = pts[j]
			var what := "clear at chest height"
			for h in [0.4, 1.0, 1.6]:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pa + Vector3.UP * h, pb + Vector3.UP * h, mask))
				if not hit.is_empty():
					what = "blocked at %.1f m up by %s at %s" % [h, _describe(hit["collider"], int(hit["shape"])), hit["position"]]
					break
			examples.append("NEAREST piece of %d points: %s to the start's ground %s, %.2f m: %s" % [sizes[label], pa, pb, sqrt(best), what])
		var shown := 0
		for label: int in sizes:
			if label == main or shown >= 8 or int(sizes[label]) < 20:
				continue
			var lo := Vector3(INF, INF, INF)
			var hi := -lo
			for i in pts.size():
				if labels[i] == label:
					lo = lo.min(pts[i])
					hi = hi.max(pts[i])
			examples.append("ISLAND of %d points from %s to %s" % [sizes[label], lo, hi])
			shown += 1
	return out

## The doorways a glass pane would shut (`ZzMap.is_glass_door`: boxes of the document) walked through by a capsule across
## the pane's thin axis (a stop beyond the pane is a table behind it, not the pane). A line for each one still shut, with what shuts it.
func _door_walk(map: Node, space: PhysicsDirectSpaceState3D, mask: int) -> PackedStringArray:
	var out := PackedStringArray()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = mask
	for box: Dictionary in map.doc.get("boxes", []):
		var size := ZzMapDoc.v3(box["size"])
		var at := ZzMapDoc.v3(box["at"])
		if not str(box.get("mat", "")).begins_with("glass") or not map.is_glass_door(at, size):
			continue
		var along := Vector3(1.0, 0.0, 0.0) if size.x < size.z else Vector3(0.0, 0.0, 1.0)
		var start := Vector3(at.x, at.y - size.y * 0.5 + 0.8, at.z) - along * 1.2
		query.transform = Transform3D(Basis.IDENTITY, start)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		query.motion = along * 2.4
		var fractions := space.cast_motion(query)
		if fractions.size() >= 2 and fractions[0] * 2.4 > 0.85 and fractions[0] * 2.4 < 1.55:
			query.transform = Transform3D(Basis.IDENTITY, start + along * 2.4 * minf(fractions[1] + 0.02, 1.0))
			query.motion = Vector3.ZERO
			var hit := space.intersect_shape(query, 1)
			out.append("DOORWAY_SHUT at %s by %s" % [at, _describe(hit[0]["collider"], int(hit[0]["shape"])) if not hit.is_empty() else "something"])
	return out


## Edges of [param data] a walking capsule cannot follow, as one line per 3 m cluster with what is in the way.
func _edge_report(data: Object, space: PhysicsDirectSpaceState3D, mask: int) -> PackedStringArray:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = mask
	var lift := Vector3(0.0, 0.95, 0.0)
	var pts: PackedVector3Array = data.points
	var edges: PackedInt32Array = data.edges
	var clusters := {}
	var walked := 0
	for i in range(0, edges.size() - 1, 2):
		var a := pts[edges[i]]
		var b := pts[edges[i + 1]]
		if a.distance_to(b) > 2.0 or absf(a.y - b.y) > 0.6:
			continue
		query.transform = Transform3D(Basis.IDENTITY, a + lift)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		walked += 1
		query.motion = b - a
		var fractions := space.cast_motion(query)
		if fractions.size() < 2 or fractions[0] >= 1.0:
			continue
		query.transform = Transform3D(Basis.IDENTITY, a + lift + (b - a) * minf(fractions[1] + 0.02, 1.0))
		query.motion = Vector3.ZERO
		var hit := space.intersect_shape(query, 1)
		var key := Vector3i(floori(a.x / 3.0), floori(a.y / 3.0), floori(a.z / 3.0))
		var rec: Dictionary = clusters.get(key, {"n": 0, "at": a, "what": ""})
		rec["n"] += 1
		if rec["what"] == "" and not hit.is_empty():
			rec["what"] = _describe(hit[0]["collider"], int(hit[0]["shape"]))
		clusters[key] = rec
	var out := PackedStringArray()
	var total := 0
	for rec: Dictionary in clusters.values():
		total += int(rec["n"])
	out.append("EDGES_BLOCKED %d of %d walked, in %d places" % [total, walked, clusters.size()])
	var list: Array = clusters.values()
	list.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["n"]) > int(y["n"]))
	for rec: Dictionary in list.slice(0, 12):
		out.append("EDGE_BLOCKED %d edges near %s by %s" % [rec["n"], rec["at"], rec["what"]])
	return out


## A link from every piece of the graph (8 points or more, not buried in a solid) to the nearest bigger piece within
## [constant LINK_REACH], where a line at 0.4, 1.0 and 1.6 m is clear and both ends have ground.
func _print_links(pts: PackedVector3Array, labels: PackedInt32Array, sizes: Dictionary, space: PhysicsDirectSpaceState3D, mask: int) -> void:
	var cell := LINK_REACH
	var grid := {}
	var open := PackedByteArray()
	open.resize(pts.size())
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = mask
	for i in pts.size():
		query.transform = Transform3D(Basis.IDENTITY, pts[i] + Vector3(0.0, 0.85, 0.0))
		open[i] = 1 if space.intersect_shape(query, 1).is_empty() else 0
		if open[i] == 1:
			var key := Vector3i(floori(pts[i].x / cell), floori(pts[i].y / cell), floori(pts[i].z / cell))
			var members: PackedInt32Array = grid.get(key, PackedInt32Array())
			members.append(i)
			grid[key] = members
	var order: Array = sizes.keys()
	order.sort_custom(func(a: int, b: int) -> bool: return int(sizes[a]) < int(sizes[b]))
	var made := 0
	for label: int in order:
		if int(sizes[label]) < 8:
			continue
		var best := INF
		var from := -1
		var to := -1
		for i in pts.size():
			if labels[i] != label or open[i] == 0:
				continue
			var key := Vector3i(floori(pts[i].x / cell), floori(pts[i].y / cell), floori(pts[i].z / cell))
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					for dz in [-1, 0, 1]:
						for j: int in grid.get(key + Vector3i(dx, dy, dz), PackedInt32Array()):
							var other := labels[j]
							if other == label or int(sizes[other]) < int(sizes[label]) or (int(sizes[other]) == int(sizes[label]) and other < label):
								continue
							var d := pts[i].distance_to(pts[j])
							if d >= best or d > LINK_REACH or absf(pts[i].y - pts[j].y) > 1.2:
								continue
							var clear := true
							for h in [0.4, 1.0, 1.6]:
								if not space.intersect_ray(PhysicsRayQueryParameters3D.create(pts[i] + Vector3.UP * h, pts[j] + Vector3.UP * h, mask)).is_empty():
									clear = false
									break
							if clear:
								best = d
								from = i
								to = j
		if from >= 0:
			made += 1
			print("SUGGEST %s  (%d points -> %d, %.2f m)" % [JSON.stringify([snappedf(pts[from].x, 0.001), snappedf(pts[from].y, 0.001), snappedf(pts[from].z, 0.001),
				snappedf(pts[to].x, 0.001), snappedf(pts[to].y, 0.001), snappedf(pts[to].z, 0.001)]), sizes[label], sizes[labels[to]], best])
	print("SUGGEST total %d links for %d pieces" % [made, sizes.size()])


func _body(mask: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position.y = HEIGHT * 0.5
	body.add_child(shape)
	body.collision_layer = 0
	body.collision_mask = mask
	body.floor_snap_length = 0.3
	return body


func _fall(bodies: Array[CharacterBody3D], walk: Vector3) -> void:
	for b in bodies:
		var vy := 0.0 if b.is_on_floor() else b.velocity.y - GRAVITY / 60.0
		b.velocity = Vector3(walk.x, maxf(vy, -25.0), walk.z)
		b.move_and_slide()


func _embedded(space: PhysicsDirectSpaceState3D, feet: Vector3, mask: int) -> String:
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS - 0.08
	capsule.height = HEIGHT - 0.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = mask
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, HEIGHT * 0.5 + 0.1, 0.0))
	var hits := space.intersect_shape(query, 1)
	if hits.is_empty():
		return ""
	return _describe(hits[0]["collider"], int(hits[0]["shape"]))


## What a hit shape is: a prop's id, or the body's name with the box or hull the shape is.
func _describe(collider: Object, shape_index: int) -> String:
	var index := _game.map.prop_from_hit(collider, shape_index)
	if index >= 0:
		return "prop %s" % _game.map.prop_id(index)
	var body := collider as CollisionObject3D
	var named := "%s/%s" % [body.name, body.get_parent().name]
	var node := body.shape_owner_get_owner(body.shape_find_owner(shape_index)) as CollisionShape3D
	if node != null and node.shape is BoxShape3D:
		named += " box at %s size %s" % [node.global_position.snapped(Vector3.ONE * 0.01), (node.shape as BoxShape3D).size.snapped(Vector3.ONE * 0.01)]
	elif node != null and node.shape is ConvexPolygonShape3D:
		var box := AABB(node.global_position + (node.shape as ConvexPolygonShape3D).points[0], Vector3.ZERO)
		for pt in (node.shape as ConvexPolygonShape3D).points:
			box = box.expand(node.global_position + pt)
		named += " hull from %s to %s" % [box.position.snapped(Vector3.ONE * 0.01), box.end.snapped(Vector3.ONE * 0.01)]
	return named


## Visible boxes as [inverse transform, half size]: what the player sees as floor.
static func _drawn_boxes(doc: Dictionary) -> Array:
	var out := []
	for b: Dictionary in doc.get("boxes", []):
		if not bool(b.get("visible", true)) or b.has("gate") or b.has("barricade"):
			continue
		var at := ZzMapDoc.v3(b["at"])
		var half := ZzMapDoc.v3(b["size"]) * 0.5
		out.append([AABB(at - half, half * 2.0), bool(b.get("solid", true))])
	return out


## Whether a drawn box's top is within a step of the floor under the point.
static func _under_drawn(drawn: Array, x: float, z: float, y: float) -> bool:
	for rec: Array in drawn:
		var box: AABB = rec[0]
		if x >= box.position.x and x <= box.end.x and z >= box.position.z and z <= box.end.z and absf(box.end.y - y) < 0.6:
			return true
	return false
