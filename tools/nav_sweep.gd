extends Node

## Builds each map's horde graph and reports the posts and survivor spawns the graph cannot use:
## no point within the stand-ins' snap radius ("nopoint"), or a point in a piece the first spawn
## cannot reach ("island"). `godot --headless --path . res://tools/nav_sweep.tscn -- --all`
## or `-- --map=zs_goth_house`. A post or spawn on either list is a place a stand-in idles.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")

const TICK := 1.0 / 64.0
## What a stand-in's path start and goal snap to (idle_probe's `_why_empty`).
const SNAP := 2.5

## --points: also lists every point of the maps named, marked "+" when the first spawn reaches it, then its piece number.
var _points := false

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
	var doc: Dictionary = game.catalogue.maps.get(StringName(id), {})

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


## Which obstacle boxes (grown by the clearance) hold the samples between two points.
func _explain(game: Node) -> void:
	var horde = game.horde
	var props_size := func(id: StringName) -> Vector3:
		return game.props_catalogue.size_of(id) if game.props_catalogue.has(id) else Vector3.ZERO

	var blockers: Array[AABB] = []

	if game.map != null and game.map.mechanics != null:
		blockers = game.map.mechanics.rest_blockers()

	var job := ZzNpcs.nav_job(ZzNpcs.with_nav_extra(horde._doc, horde._nav_extra), props_size, horde.open_gates, blockers, false, false)
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

	var tail := "" if out.is_empty() else "  " + "; ".join(out.slice(0, 6))
	return "points=%d checked=%d bad=%d%s" % [data.point_count(), checked, bad, tail]


func _graph_ready(game: Node) -> bool:
	var spawner = game.horde.spawner
	return spawner != null and spawner.nav != null and spawner.nav.data != null and game.map != null and not game.horde.nav_building()
