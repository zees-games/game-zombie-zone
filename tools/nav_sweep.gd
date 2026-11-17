extends Node

## Builds each map's horde graph and reports the posts and survivor spawns it cannot use: "nopoint" (none in snap
## radius), "island" (unreachable from the first spawn); `inwall`/`ontop` count points in a box or on a wall top.
## `godot --headless --path . res://tools/nav_sweep.tscn -- --all` or `-- --map=zs_goth_house`.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzNavPrune := preload("../game/zz_nav_prune.gd")
const NavWalls := preload("nav_walls.gd")

const TICK := 1.0 / 64.0
## What a stand-in's path start and goal snap to (idle_probe's `_why_empty`).
const SNAP := 2.5

## --points: also lists every point of the maps named, marked "+" when the first spawn reaches it, then its piece number.
var _points := false

## --links: also prints how many of the document's nav links the builder drops as running through solid geometry.
var _links := false

## --probe=file.json: a list of candidate links [x1,y1,z1,x2,y2,z2]; prints which ones the builder's wall test lets through (PASS) and which it drops.
var _probe_file := ""

## --bridges: lists the shortest physics-clear links between every two pieces of the graph (reach in metres: --reach=4), for a mapper to pick the ones that join a sealed area.
var _bridges := false
var _reach := 4.0
## --area=x0,z0,x1,z1: limits --gaps to a rectangle (game metres); pieces are then only told apart among its points.
var _area := PackedFloat64Array()

## --gaps: lists the spots the physics world has standing room on (a floor, a stair tread, a ramp, a body fits) that no graph point is near, on a 0.5 m grid over the graph's bounds.
var _gaps := false

## --between=ax,ay,az,bx,by,bz: names the obstacle boxes that stop the builder joining two points.
var _between := PackedFloat64Array()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var ids: Array[String] = []

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			ids.append(arg.substr(6))
		elif arg.begins_with("--between="):
			_between = PackedFloat64Array(Array(arg.substr(10).split(",")).map(func(v: String) -> float: return v.to_float()))
		elif arg.begins_with("--probe="):
			_probe_file = arg.substr(8)
		elif arg == "--gaps":
			_gaps = true
		elif arg == "--bridges":
			_bridges = true
		elif arg.begins_with("--area="):
			_area = PackedFloat64Array(Array(arg.substr(7).split(",")).map(func(v: String) -> float: return v.to_float()))
		elif arg.begins_with("--reach="):
			_reach = arg.substr(8).to_float()
		elif arg == "--links":
			_links = true
		elif arg == "--points":
			_points = true
		elif arg == "--all":
			for file in DirAccess.get_files_at("res://maps"):
				if file.ends_with(".json") and not file.contains(".doc."):
					ids.append(file.trim_suffix(".json"))

	ids.sort()
	var bad_maps := 0

	for id in ids:
		var game := await _built(id)

		if game == null:
			print("%-28s no graph" % id)
			continue

		if _between.size() == 6:
			_explain(game)

		if _links:
			_report_links(game, id)

		if _probe_file != "":
			_probe_links(game)

		if _bridges:
			_list_bridges(game)
			_trace_links(game)

		if _gaps:
			_list_gaps(game)

		var line := _report(game)
		bad_maps += 1 if line.contains("nopoint") or line.contains("island") else 0
		print("%-28s %s" % [id, line])
		game.queue_free()
		await get_tree().physics_frame

	print("maps %d  with unusable posts or spawns %d" % [ids.size(), bad_maps])
	get_tree().quit()


func _built(id: String) -> Node:
	var config := ZzConfig.new()
	config.map_ids = PackedStringArray([id])
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.nav_cache = false
	var game := ZzGame.new()
	game.config = config
	game.tick_rate = 64
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	game.next_map_id = StringName(id)
	var doc: Dictionary = game.catalogue.doc(StringName(id))

	for i in maxi(int(doc.get("survivors", 4)), 1):
		var player = game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.is_bot = true

	game.start()

	# The graph is built in slices (or on a thread) while the match runs.
	var ticks := 0

	while ticks < 64 * 120 and not _graph_ready(game):
		for i in 32:
			game.simulate(TICK)

		ticks += 32
		await get_tree().physics_frame

	if not _graph_ready(game):
		game.queue_free()
		return null

	return game


## How many of the document's nav links the builder's strict wall test drops.
func _report_links(game: Node, id: String) -> void:
	var info := {}
	var job := _job_for(game, game.horde.nav_doc())
	job.make_builder.call(ZzNpcs.LINK_TEST_HEIGHTS, info)
	print("%-28s doc links %d  dropped by the strict wall test %d" % [id, (game.horde.nav_doc().get("nav", {}) as Dictionary).get("links", []).size(), info.get("rejected", -1)])


func _job_for(game: Node, doc: Dictionary) -> Object:
	var props_size := func(pid: StringName) -> Vector3:
		return game.props_catalogue.size_of(pid) if game.props_catalogue.has(pid) else Vector3.ZERO

	var blockers: Array[AABB] = []

	if game.map != null and game.map.mechanics != null:
		blockers = game.map.mechanics.rest_blockers()

	return ZzNpcs.nav_job(doc, props_size, game.horde.open_gates, blockers, false, false)


## `gap x y z piece`: a standing spot of the physics world with no graph point within 0.8 m across and 0.6 m up; piece is the nearest graph point's piece within 2 m, else -1.
func _list_gaps(game: Node) -> void:
	var data: DotNpcNavData = game.horde.spawner.nav.data
	var graph := DotNpcNavGraph.new(data)
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	var mask: int = game.physics.layer_mask(&"world")
	var body: Object = ZzNavPrune.new()
	body._setup(space, mask, 0.0)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)

	for p: Vector3 in data.points:
		lo = lo.min(p)
		hi = hi.max(p)

	lo -= Vector3(1.0, 1.0, 1.0)
	hi += Vector3(1.0, 2.0, 1.0)

	if _area.size() == 4:
		lo.x = _area[0]
		lo.z = _area[1]
		hi.x = _area[2]
		hi.z = _area[3]

	var label: Array[int] = []
	label.resize(data.point_count())
	var local: Array[int] = []

	for i in data.point_count():
		label[i] = i
		var p := data.points[i]

		if _area.size() != 4 or (p.x >= lo.x - 2.0 and p.x <= hi.x + 2.0 and p.z >= lo.z - 2.0 and p.z <= hi.z + 2.0):
			local.append(i)

	for n in local.size():
		var i := local[n]

		for m in n:
			if graph.connected(local[m], i):
				label[i] = label[local[m]]
				break

	var count := 0
	var x := lo.x

	while x <= hi.x:
		var z := lo.z

		while z <= hi.z:
			var y := hi.y

			while y > lo.y:
				var ray := PhysicsRayQueryParameters3D.create(Vector3(x, y, z), Vector3(x, lo.y, z), mask)
				var hit := space.intersect_ray(ray)

				if hit.is_empty():
					break

				var at: Vector3 = hit["position"]
				y = at.y - 0.05

				if (hit["normal"] as Vector3).y < 0.7 or body._point_blocked(at):
					continue

				var near := -1
				var near_d := INF
				var covered := false

				for i in data.points_within(at, 2.0):
					var q := data.points[i]
					var across := Vector2(q.x - at.x, q.z - at.z).length()

					if across <= 0.8 and absf(q.y - at.y) <= 0.6:
						covered = true
						break

					var d := q.distance_to(at)

					if d < near_d:
						near_d = d
						near = label[i]

				if not covered:
					print("gap %.2f %.2f %.2f %d" % [at.x, at.y, at.z, near])
					count += 1

			z += 0.5

		x += 0.5

	print("gaps %d" % count)


## For each pair of pieces, the three nearest point pairs the physics world lets a body walk between: `bridge P Q dist [link]`.
func _list_bridges(game: Node) -> void:
	var data: DotNpcNavData = game.horde.spawner.nav.data
	var graph := DotNpcNavGraph.new(data)
	var test: Callable = ZzNavPrune.edge_test(game.get_world_3d().direct_space_state, game.physics.layer_mask(&"world"))
	var label: Array[int] = []

	for i in data.point_count():
		var piece := i

		for j in i:
			if graph.connected(j, i):
				piece = label[j]
				break

		label.append(piece)

	var best := {}

	for i in data.point_count():
		var a := data.points[i]

		for j in data.points_within(a, _reach):
			if j <= i or label[j] == label[i]:
				continue

			var b := data.points[j]
			var key := "%d %d" % [mini(label[i], label[j]), maxi(label[i], label[j])]
			var rows: Array = best.get(key, [])
			var d := a.distance_to(b)

			if rows.size() >= 3 and d >= rows[-1][0]:
				continue

			if test.call(a, b):
				continue

			rows.append([d, a, b])
			rows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
			best[key] = rows.slice(0, 3)

	for key: String in best:
		for row: Array in best[key]:
			var a: Vector3 = row[1]
			var b: Vector3 = row[2]
			print("bridge %s %.2f %s" % [key, row[0], JSON.stringify([snappedf(a.x, 0.01), snappedf(a.y, 0.01), snappedf(a.z, 0.01), snappedf(b.x, 0.01), snappedf(b.y, 0.01), snappedf(b.z, 0.01)])])


## One line per candidate link in the --probe file: PASS when the strict test keeps it, else DROP.
func _probe_links(game: Node) -> void:
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(_probe_file))

	if not rows is Array:
		print("probe: %s is not a JSON list" % _probe_file)
		return

	var doc: Dictionary = game.horde.nav_doc().duplicate()

	for row: Array in rows:
		var nav: Dictionary = (doc.get("nav", {}) as Dictionary).duplicate()
		nav["links"] = [row]
		doc["nav"] = nav
		var info := {}
		_job_for(game, doc).make_builder.call(ZzNpcs.LINK_TEST_HEIGHTS, info)
		print("probe %s %s" % ["DROP" if int(info.get("rejected", 0)) > 0 else "PASS", JSON.stringify(row)])


## Which obstacle boxes (grown by the clearance) hold the samples between two points.
func _explain(game: Node) -> void:
	var horde = game.horde
	var props_size := func(id: StringName) -> Vector3:
		return game.props_catalogue.size_of(id) if game.props_catalogue.has(id) else Vector3.ZERO

	var blockers: Array[AABB] = []

	if game.map != null and game.map.mechanics != null:
		blockers = game.map.mechanics.rest_blockers()

	var job := ZzNpcs.nav_job(horde.nav_doc(), props_size, horde.open_gates, blockers, false, false)
	var builder: DotNpcNavBuilder = job.make_builder.call([], {})
	var a := Vector3(_between[0], _between[1], _between[2])
	var b := Vector3(_between[3], _between[4], _between[5])
	var hit := {}

	for k in 21:
		var p := a.lerp(b, k / 20.0)

		for i in builder._obstacles.size():
			var box: AABB = builder._obstacles[i]

			if box.end.y >= p.y - builder._under_feet() and box.grow(builder.clearance).has_point(p):
				hit[i] = "sample %d at %s box %s" % [k, p.snapped(Vector3.ONE * 0.01), box]

	print("between: %d obstacles hold a sample" % hit.size())

	for i: int in hit:
		print("  ", hit[i])


func _report(game: Node) -> String:
	var data: DotNpcNavData = game.horde.spawner.nav.data
	var graph := DotNpcNavGraph.new(data)
	var doc: Dictionary = game.map.doc
	var spawns: Array = (doc.get("spawns", {}) as Dictionary).get("survivors", [])
	var home := -1 if spawns.is_empty() else data.nearest_point(ZzMapDoc.v3(spawns[0]["at"]), SNAP)
	var posts: Array = doc.get("posts", [])

	if _points:
		var label: Array[int] = []

		for i in data.point_count():
			var piece := i

			for j in i:
				if graph.connected(j, i):
					piece = label[j]
					break

			label.append(piece)
			print("  %s %s %s" % ["+" if home >= 0 and graph.connected(home, i) else "-", data.points[i].snapped(Vector3.ONE * 0.1), piece])

	var out := PackedStringArray()
	var bad := 0
	var checked := 0

	for entry: Array in [["post", posts], ["spawn", spawns]]:
		for item: Variant in entry[1]:
			var at := ZzMapDoc.v3(item["at"] if item is Dictionary else item)
			var point := data.nearest_point(at, SNAP)
			var why := ""

			if point < 0:
				why = "nopoint"
			elif home >= 0 and not graph.connected(home, point):
				why = "island"

			checked += 1

			if why != "":
				bad += 1
				out.append("%s %s %s" % [why, entry[0], at.snapped(Vector3.ONE * 0.1)])

	# Zombie spawn -> survivor spawn pairs the graph cannot join (what the horde needs to reach a survivor).
	var zpoints: Array[int] = []
	var spoints: Array[int] = []

	for z: Variant in doc.get("zombie_spawns", []):
		zpoints.append(data.nearest_point(ZzMapDoc.v3(z["at"] if z is Dictionary else z), SNAP))

	for item: Variant in spawns:
		spoints.append(data.nearest_point(ZzMapDoc.v3(item["at"]), SNAP))

	var pair_total := 0
	var pair_bad := 0

	for zp in zpoints:
		for sp in spoints:
			pair_total += 1

			if zp < 0 or sp < 0 or not graph.connected(zp, sp):
				pair_bad += 1

	var tail := "  pairs=%d unreachable=%d" % [pair_total, pair_bad]
	tail += "" if out.is_empty() else "  " + "; ".join(out.slice(0, 6))
	var walls := NavWalls.count(data, game.horde.nav_doc())

	if walls["inwall"] + walls["ontop"] > 0:
		tail += "  walls: %s" % [walls["examples"]]

	return "points=%d checked=%d bad=%d inwall=%d ontop=%d%s" % [data.point_count(), checked, bad, walls["inwall"], walls["ontop"], tail]


func _graph_ready(game: Node) -> bool:
	var spawner = game.horde.spawner
	return spawner != null and spawner.nav != null and spawner.nav.data != null and game.map != null and not game.horde.nav_building()


## `trace i a b adjacent`: the last 8 doc links, the graph points their ends snap to (nearest within 2 m) and whether the two are joined by an edge.
func _trace_links(game: Node) -> void:
	var data: DotNpcNavData = game.horde.spawner.nav.data
	var graph := DotNpcNavGraph.new(data)
	var links: Array = (game.horde.nav_doc().get("nav", {}) as Dictionary).get("links", [])

	for k in range(maxi(links.size() - 13, 0), links.size()):
		var l: Array = links[k]
		var a := data.nearest_point(Vector3(l[0], l[1], l[2]), 2.0)
		var b := data.nearest_point(Vector3(l[3], l[4], l[5]), 2.0)
		var near := graph.connected(a, b) if a >= 0 and b >= 0 else false
		print("trace %d a=%d b=%d joined=%s pa=%s pb=%s" % [k, a, b, near, str(data.points[a]) if a >= 0 else "-", str(data.points[b]) if b >= 0 else "-"])
