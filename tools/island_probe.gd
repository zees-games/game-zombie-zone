extends Node
## Why each nav piece holding a spawn or post is apart from the main one: raw versus pruned edges, the first
## physics hit along each at both body radii, and the hit on each leg of a drop. Pair with spot_probe --reach.
##   godot --headless --path . res://tools/island_probe.tscn -- --maps=a,b

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")

var _game: ZzGame


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var maps := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--maps="):
			maps = a.substr(7).split(",")
	for id in maps:
		await _probe(id)
	get_tree().quit(0)


func _probe(id: String) -> void:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.nav_cache = false
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
	var horde = _game.horde
	var pr: DotNpcNavData = horde.nav
	var doc: Dictionary = horde.nav_doc()
	var blockers: Array[AABB] = []
	if _game.map != null and _game.map.mechanics != null:
		blockers = _game.map.mechanics.rest_blockers()
	var props_size := Callable()
	if _game.props_catalogue != null:
		props_size = func(pid: StringName) -> Vector3:
			return _game.props_catalogue.size_of(pid) if _game.props_catalogue.has(pid) else Vector3.ZERO
	var job = ZzNpcs.nav_job(doc, props_size, horde.open_gates, blockers, false, false)
	var raw: DotNpcNavData = job.run_blocking()
	var b: DotNpcNavBuilder = job.make_builder.call([], {})
	b.begin(&"x", "")
	var pc := _comps(pr)
	var rc := _comps(raw)
	var main := _biggest(pc)
	print("MAP %s: pruned %d pts, raw %d pts, raw pieces %d" % [id, pr.points.size(), raw.points.size(), _count(rc)])
	var ends: Array = []
	for s: Variant in (doc.get("spawns", {}) as Dictionary).get("survivors", []):
		ends.append(_v(s["at"] if s is Dictionary else s))
	for z: Variant in doc.get("zombie_spawns", []):
		ends.append(_v(z))
	for q: Variant in doc.get("posts", []):
		ends.append(_v(q))
	var pieces := {}
	for e: Vector3 in ends:
		var i := pr.nearest_point(e, 2.5)
		if i >= 0 and pc[i] != main:
			pieces[pc[i]] = int(pieces.get(pc[i], 0)) + 1
	var floors: Array = doc.get("nav", {}).get("floors", [])
	for c: int in pieces:
		var n := 0
		var bi := -1
		var bj := -1
		var best := INF
		for i in pr.points.size():
			if pc[i] != c:
				continue
			n += 1
			for j in pr.points_within(pr.points[i], 8.0):
				if pc[j] == main:
					var d := pr.points[i].distance_to(pr.points[j])
					if d < best:
						best = d
						bi = i
						bj = j
		if bi < 0:
			print("  piece %d (%d pts, %d ends): no main point within 8 m" % [c, n, pieces[c]])
			continue
		var a := pr.points[bi]
		var z := pr.points[bj]
		var ra := raw.nearest_point(a, 0.3)
		var rz := raw.nearest_point(z, 0.3)
		var joined_raw := ra >= 0 and rz >= 0 and rc[ra] == rc[rz]
		print("  piece %d (%d pts, %d ends): %s -> main %s, %.2f m dy %.2f; raw %s" % [c, n, pieces[c], _f(a), _f(z), best, z.y - a.y, "JOINED (prune split)" if joined_raw else "split"])
		if joined_raw:
			_raw_path_cuts(raw, rc, pr, pc, main, ra, rz)
		elif false:
			var steps := maxi(int(a.distance_to(z) / 0.25), 1)
			for k in steps + 1:
				var s := a.lerp(z, float(k) / steps)
				var fl := PackedStringArray()
				for f: Array in floors:
					if s.x >= float(f[0]) and s.x <= float(f[2]) and s.z >= float(f[1]) and s.z <= float(f[3]) and absf(float(f[4]) - s.y) < 3.0:
						fl.append("%.2f%s" % [float(f[4]), "B" if b._blocked(Vector3(s.x, float(f[4]), s.z)) else ""])
				var ob := _obstacle_at(b, s)
				var rp := raw.nearest_point(s, 0.45)
				print("    %s floors[%s] raw_pt %s %s" % [_f(s), ",".join(fl), _f(raw.points[rp]) if rp >= 0 else "-", ob])
		if OS.get_cmdline_user_args().has("--links"):
			_links_near(doc, pr, pc, c, main)
	remove_child(_game)
	_game.free()
	await get_tree().process_frame


func _raw_path_cuts(raw: DotNpcNavData, rc: PackedInt32Array, pr: DotNpcNavData, pc: PackedInt32Array, main: int, start: int, _goal: int) -> void:
	var adj := {}
	for k in range(0, raw.edges.size(), 2):
		(adj.get_or_add(raw.edges[k], []) as Array).append(raw.edges[k + 1])
		(adj.get_or_add(raw.edges[k + 1], []) as Array).append(raw.edges[k])
	var prev := {start: -1}
	var queue := [start]
	var found := -1
	while not queue.is_empty():
		var u: int = queue.pop_front()
		var pu := pr.nearest_point(raw.points[u], 0.05)
		if pu >= 0 and pc[pu] == main:
			found = u
			break
		for v: int in adj.get(u, []):
			if not prev.has(v):
				prev[v] = u
				queue.append(v)
	if found < 0:
		print("    no raw path to main")
		return
	var path: Array[int] = []
	var at := found
	while at >= 0:
		path.push_front(at)
		at = prev[at]
	var space := _game.get_world_3d().direct_space_state
	var shown := 0
	for k in path.size() - 1:
		var u := raw.points[path[k]]
		var v := raw.points[path[k + 1]]
		var pu := pr.nearest_point(u, 0.05)
		var pv := pr.nearest_point(v, 0.05)
		var why := ""
		if pu < 0:
			why = "point dropped " + _f(u)
		elif pv < 0:
			why = "point dropped " + _f(v)
		elif not _has_edge(pr, pu, pv):
			why = "edge cut"
		if why == "" or shown >= 3:
			continue
		shown += 1
		print("    CUT %s -> %s len %.2f dy %.2f: %s | r.42: %s | r.32: %s" % [_f(u), _f(v), u.distance_to(v), v.y - u.y, why, _first_hit(space, u, v, 0.42), _first_hit(space, u, v, 0.32)])
		if absf(u.y - v.y) > 0.6:
			var hi := u if u.y > v.y else v
			var lo := v if u.y > v.y else u
			for c: Vector3 in [hi, lo]:
				var top := Vector3(c.x, hi.y, c.z)
				var bot := Vector3(c.x, lo.y, c.z)
				print("      column %s: H1 %s | V %s | H2 %s" % [_f(c), _first_hit(space, hi, top, 0.32).left(140), _first_hit(space, top, bot, 0.32).left(140), _first_hit(space, bot, lo, 0.32).left(140)])


func _has_edge(d: DotNpcNavData, a: int, b: int) -> bool:
	for k in range(0, d.edges.size(), 2):
		if (d.edges[k] == a and d.edges[k + 1] == b) or (d.edges[k] == b and d.edges[k + 1] == a):
			return true
	return false


func _first_hit(space: PhysicsDirectSpaceState3D, a: Vector3, z: Vector3, radius: float) -> String:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = 1.45
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = _game.physics.layer_mask(&"world")
	var steps := maxi(int(ceil(a.distance_to(z) / 0.25)), 1)
	for k in steps + 1:
		var s := a.lerp(z, float(k) / steps)
		q.transform = Transform3D(Basis.IDENTITY, s + Vector3.UP * (0.3 + 0.725))
		var hits := _space_hits(space, q)
		if hits != "":
			return "at %s %s" % [_f(s), hits.left(160)]
	return "clear"


func _links_near(doc: Dictionary, pr: DotNpcNavData, pc: PackedInt32Array, c: int, main: int) -> void:
	var shown := 0
	for l: Array in doc.get("nav", {}).get("links", []) + doc.get("nav", {}).get("ladders", []):
		var a := Vector3(l[0], l[1], l[2])
		var z := Vector3(l[3], l[4], l[5])
		var ia := pr.nearest_point(a, 2.0)
		var iz := pr.nearest_point(z, 2.0)
		var ca := pc[ia] if ia >= 0 else -1
		var cz := pc[iz] if iz >= 0 else -1
		if (ca == c or cz == c) and shown < 6:
			shown += 1
			print("    link %s(%s) -> %s(%s)" % [_f(a), str(ca), _f(z), str(cz)])
		elif (ia < 0 or iz < 0) and shown < 6:
			var near_c := false
			for i in pr.points_within(a if ia < 0 else z, 4.0):
				if pc[i] == c:
					near_c = true
			if near_c:
				shown += 1
				print("    link %s(%s) -> %s(%s) OFF-GRAPH end" % [_f(a), str(ca), _f(z), str(cz)])


func _obstacle_at(b: DotNpcNavBuilder, s: Vector3) -> String:
	var out := PackedStringArray()
	for box: AABB in b._obstacles:
		var w := box.grow(b.clearance)
		if s.x >= w.position.x and s.x <= w.end.x and s.z >= w.position.z and s.z <= w.end.z and box.end.y > s.y - 1.0 and box.position.y < s.y + 2.0:
			out.append("obs[%s..%s]" % [_f(box.position), _f(box.end)])
	return " ".join(out.slice(0, 3))


func _physics_line(a: Vector3, z: Vector3) -> void:
	var space := _game.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.45
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = _game.physics.layer_mask(&"world")
	var steps := maxi(int(a.distance_to(z) / 0.25), 1)
	for k in steps + 1:
		var s := a.lerp(z, float(k) / steps)
		q.transform = Transform3D(Basis.IDENTITY, s + Vector3.UP * (0.3 + 0.725))
		var hits := _space_hits(space, q)
		print("    %s %s" % [_f(s), hits])


func _space_hits(space: PhysicsDirectSpaceState3D, q: PhysicsShapeQueryParameters3D) -> String:
	var out := PackedStringArray()
	for h in space.intersect_shape(q, 4):
		var co := h["collider"] as CollisionObject3D
		if co == null:
			out.append("?")
			continue
		var owner_node := co.shape_owner_get_owner(co.shape_find_owner(int(h["shape"]))) as Node3D
		var desc := "%s/%s" % [co.name, owner_node.name if owner_node != null else "?"]
		var cs := owner_node as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			desc += " box %s at %s" % [(cs.shape as BoxShape3D).size, _f(cs.global_position)]
		elif cs != null:
			desc += " " + cs.shape.get_class()
		out.append(desc)
	return "; ".join(out)


static func _comps(d: DotNpcNavData) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(d.points.size())
	for i in parent.size():
		parent[i] = i
	for k in range(0, d.edges.size(), 2):
		var x := _root(parent, d.edges[k])
		var y := _root(parent, d.edges[k + 1])
		if x != y:
			parent[y] = x
	for i in parent.size():
		parent[i] = _root(parent, i)
	return parent


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


static func _biggest(c: PackedInt32Array) -> int:
	var sizes := {}
	for x in c:
		sizes[x] = int(sizes.get(x, 0)) + 1
	var best := -1
	for k in sizes:
		if best < 0 or sizes[k] > sizes[best]:
			best = k
	return best


static func _count(c: PackedInt32Array) -> int:
	var sizes := {}
	for x in c:
		sizes[x] = true
	return sizes.size()


static func _v(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _f(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]
