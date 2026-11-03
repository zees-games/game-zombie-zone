extends Node
## Frame-time cost of straight_width_ratio for a horde: HORDE zombies each plan a path to a shared survivor
## spot, then repath after the survivor moved. Prints find_path alone, then plan + smooth_path for each ratio,
## cold (memo off) and warm (memo on, as in play).
##   godot --headless --path . res://tools/smooth_bench.tscn -- --maps=a,b [--horde=120]

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const RATIOS := [0.75, 0.5]

var _game: ZzGame


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	_run.call_deferred()


func _run() -> void:
	var horde := 120
	var maps := PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--maps="):
			maps = a.substr(7).split(",")
		elif a.begins_with("--horde="):
			horde = int(a.substr(8))
	for id in maps:
		await _bench(id, horde)
	get_tree().quit(0)


func _bench(id: String, horde: int) -> void:
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
	if graph == null or graph.data == null:
		print("%s: no nav" % id)
		return
	var pts := graph.data.points
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var starts: Array[Vector3] = []
	for i in horde:
		starts.append(pts[rng.randi() % pts.size()])
	var goal_a: Vector3 = pts[rng.randi() % pts.size()]
	var goal_b: Vector3 = pts[rng.randi() % pts.size()]
	var t0 := Time.get_ticks_usec()
	var raw: Array = []
	for s in starts:
		raw.append(graph.find_path(s, goal_a))
	var plan_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var legs := 0
	for r: PackedVector3Array in raw:
		legs += r.size()
	print("%s: %d points, horde %d, find_path only %.1f ms (%.0f raw points)" % [id, pts.size(), horde, plan_ms, legs])
	for memo in [false, true]:
		graph.memo_legs = memo
		for ratio: float in RATIOS:
			graph.straight_width_ratio = ratio
			var smoothed := 0
			var t1 := Time.get_ticks_usec()
			# Two goals: the survivor moves, the whole horde repaths.
			for goal in [goal_a, goal_b]:
				for s in starts:
					smoothed += graph.find_smooth_path(s, goal).size()
			var ms := (Time.get_ticks_usec() - t1) / 1000.0
			print("  memo=%s ratio=%.2f: %.1f ms for %d plans (%.2f ms each), %d smoothed points" % [memo, ratio, ms, horde * 2, ms / (horde * 2), smoothed])
	graph.memo_legs = true
	remove_child(_game)
	_game.free()
	await get_tree().process_frame
