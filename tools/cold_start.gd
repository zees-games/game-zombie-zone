extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNavNotes := preload("../game/zz_nav_notes.gd")
const ZzNavPrune := preload("../game/zz_nav_prune.gd")
const ZzNavPruneThread := preload("../game/zz_nav_prune_thread.gd")

## Cold start of a round on the real game: open and start time, and what each of the first ticks costs.
## Run: godot --headless --path . res://tools/cold_start.tscn -- --map ze_biohazard_manor --ticks 600 [--cold]
## --cold wipes user://nav_bake, user://nav and user://nav_cache first, --cold-docs also user://map_docs. Prints COLDSTART / COLDSLOW / COLDWORST; exits 1 past --max-open-ms or --max-tick-ms (0 is off).

const TICK_RATE := 64
const MAX_TICK_MS := 1000.0
const MAX_OPEN_MS := 6000.0


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--" + name)
	if at >= 0 and at + 1 < args.size():
		return args[at + 1]
	return fallback


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _wipe(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


func _ms(since: int) -> float:
	return float(Time.get_ticks_usec() - since) / 1000.0


## A round on [param map_id] alone that starts at once, with no players needed and nothing kept.
func _config(map_id: StringName) -> ZzConfig:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(map_id)])
	return config

func _run() -> void:
	var map_id := StringName(_arg("map", "ze_biohazard_manor"))
	var ticks := int(_arg("ticks", "600"))
	var max_tick := float(_arg("max-tick-ms", str(MAX_TICK_MS)))
	var max_open := float(_arg("max-open-ms", str(MAX_OPEN_MS)))

	if OS.get_cmdline_user_args().has("--cold"):
		_wipe("user://nav_bake")
		_wipe("user://nav")
		_wipe("user://nav_cache")

	if OS.get_cmdline_user_args().has("--cold-docs"):
		_wipe("user://map_docs")

	var game := ZzGame.new()
	game.name = "World"
	game.config = _config(map_id)
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	game.next_map_id = map_id
	# As the server runs it: the first graph is built off the frame and play waits for it.
	game.nav_async = not OS.get_cmdline_user_args().has("--sync")
	ZzNavPruneThread.parity = OS.get_cmdline_user_args().has("--prune-parity")
	var t0 := Time.get_ticks_usec()
	add_child(game)
	game.set_physics_process(false)
	var t_ready := _ms(t0)
	await get_tree().physics_frame

	var doc: Dictionary = game.catalogue.doc(map_id) if game.catalogue != null else {}
	if doc.is_empty():
		printerr("COLDSTART no map %s" % map_id)
		get_tree().quit(2)
		return
	for i in range(int(doc.get("survivors", 4))):
		var player := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.is_bot = true
	var t1 := Time.get_ticks_usec()
	game.start()
	var t_start := _ms(t1)
	print("COLDSTART open %.0f ms (_ready), start %.0f ms; sections %s map %s" % [t_ready, t_start, game.build_sections, game.map.sections])

	print("COLDHORDE %s" % game.horde.sections)
	var run := await _tick_through(game, ticks)
	var worst: float = run.worst
	var worst_at: int = run.worst_at
	var waited: int = run.waited
	var wait_began: int = run.wait_began
	var opened := t_ready + t_start
	var nav = game.horde.nav
	var digest := hash([nav.points, nav.edges]) if nav != null else 0
	print("COLDDIGEST points %d edges %d hash %d spawns %d" % [nav.point_count(), nav.edge_count(), digest, game.horde.director.spawn_points.size()] if nav != null else "none")
	print("COLDNAV first graph waited %d ticks, %.0f ms wall, worst waiting tick %.0f ms" % [waited, _ms(wait_began), run.wait_worst])
	print("COLDWORST %.0f ms at tick %d; open+start %.0f ms" % [worst, worst_at, opened])
	var fail := (max_tick > 0.0 and worst > max_tick) or (max_open > 0.0 and opened > max_open)
	if fail:
		printerr("COLDFAIL worst tick %.0f ms (limit %.0f), open+start %.0f ms (limit %.0f)" % [worst, max_tick, opened, max_open])
	game.queue_free()
	for _i in range(3):
		await get_tree().process_frame
	get_tree().quit(1 if fail else 0)


## Simulates [param ticks] ticks once the first nav graph has landed (the ticks it is waited on do not count),
## printing the slow ones; returns the worst tick and when, and how long the graph was waited on.
func _tick_through(game: ZzGame, ticks: int) -> Dictionary:
	var worst := 0.0
	var worst_at := 0
	var delta := 1.0 / float(TICK_RATE)
	var waited := 0
	var landed := false
	var wait_began := Time.get_ticks_usec()
	var wait_worst := 0.0
	var i := -1
	while i < ticks - 1:
		i += 1
		game.horde.sections.clear()
		var began := Time.get_ticks_usec()
		game.simulate(delta)
		var spent := _ms(began)
		if waited > 0 and not game.horde.nav_blocks_play() and not landed:
			landed = true
			print("COLDNAVLAND tick %d %.0f ms after %.0f ms wall %s" % [i, spent, _ms(wait_began), game.horde.sections])
			if ZzNavPruneThread.parity_after != null:
				_prune_parity(game)
		# The first graph is built off the frame; the ticks until it lands are the cover's.
		if game.horde.nav_blocks_play():
			waited += 1
			wait_worst = maxf(wait_worst, spent)
			i -= 1
			if waited % 16 == 0:
				await get_tree().physics_frame
			continue
		if spent > 60.0:
			var n: ZzNavNotes = game.horde.notes if game.horde != null else null
			print("COLDSLOW tick %d %.0f ms (bake %.0f cached %s annotate %.0f) %s" % [i, spent, n.bake_ms if n != null else 0.0, str(n.bake_cached) if n != null else "-", n.annotate_ms if n != null else 0.0, game.horde.sections])
		if spent > worst:
			worst = spent
			worst_at = i
		if i % 32 == 31:
			await get_tree().physics_frame
	return {"worst": worst, "worst_at": worst_at, "waited": waited, "wait_began": wait_began, "wait_worst": wait_worst}


## `--prune-parity`: prunes the graph the worker started from again, on the main thread against the world's own space and
## against a fresh private copy, and lists the edges each differs by from the worker's result and the copied bodies that
## have moved since the worker's copy. Main and fresh copy agreeing means the copy asks what the world does.
func _prune_parity(game: ZzGame) -> void:
	var mech: Variant = ZzNavPruneThread._mechanics(game)
	var ladders := ZzNavPruneThread._ladders(mech)
	var passable := ZzNavPruneThread._passable(mech)
	var required: PackedVector3Array = game.horde._required_spots()
	var mask := ZzNavPrune.body_mask(game.physics)
	var main: GSNpcNavData = ZzNavPruneThread.parity_before.duplicate(true)
	var _dropped := ZzNavPrune.run(main, game.get_world_3d().direct_space_state, mask, ladders, required, passable, {})
	var fresh: GSNpcNavData = ZzNavPruneThread.parity_before.duplicate(true)
	ZzNavPruneThread.new().run_here(fresh, game.get_world_3d(), game.get_tree().root, mask, ladders, required, passable)
	var moved: Array[Vector3] = []

	for body: Variant in ZzNavPruneThread.parity_bodies:
		var then: Transform3D = ZzNavPruneThread.parity_bodies[body]

		if is_instance_valid(body) and then.origin.distance_to(body.global_transform.origin) > 0.001:
			moved.append(body.global_transform.origin)
			print("COLDPARITY moved %s %s %.3f m" % [body.get_path(), body.get_class(), then.origin.distance_to(body.global_transform.origin)])

	_parity_diff("worker vs main", ZzNavPruneThread.parity_after, main, moved)
	_parity_diff("fresh copy vs main", fresh, main, moved)
	_parity_diff("worker vs fresh copy", ZzNavPruneThread.parity_after, fresh, moved)
	# Statics outlive the scene: dropped here so nothing is still held at exit.
	ZzNavPruneThread.parity = false
	ZzNavPruneThread.parity_before = null
	ZzNavPruneThread.parity_after = null
	ZzNavPruneThread.parity_bodies = {}


func _parity_diff(what: String, a: GSNpcNavData, b: GSNpcNavData, moved: Array[Vector3]) -> void:
	var ea := _edge_keys(a)
	var eb := _edge_keys(b)
	var only_a := ea.keys().filter(func(k: String) -> bool: return not eb.has(k))
	var only_b := eb.keys().filter(func(k: String) -> bool: return not ea.has(k))
	print("COLDPARITY %s: points %d/%d edges %d/%d, %d only in the first, %d only in the second" % [what, a.point_count(), b.point_count(), a.edge_count(), b.edge_count(), only_a.size(), only_b.size()])

	for k: String in (only_a + only_b).slice(0, 12):
		var at: Vector3 = ea.get(k, eb.get(k))
		var near := INF

		for p in moved:
			near = minf(near, p.distance_to(at))

		print("COLDPARITY   %s %s, nearest moved body %.2f m" % ["first" if ea.has(k) else "second", k, near])


func _edge_keys(nav: GSNpcNavData) -> Dictionary:
	var out := {}

	for k in range(0, nav.edges.size(), 2):
		var a := nav.points[nav.edges[k]].snappedf(0.001)
		var b := nav.points[nav.edges[k + 1]].snappedf(0.001)
		var key := "%s-%s" % [a, b] if str(a) < str(b) else "%s-%s" % [b, a]
		out[key] = (a + b) * 0.5

	return out
