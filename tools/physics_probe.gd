extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")

## Real physics-tick cost of a map held by its stand-ins: `-- --map ze_boat_escape --seconds 20 [--switch-from MAP]`.
## Prints PHYS lines (ms per frame, active bodies, pairs) for the switch and for the steady state.

var _game: ZzGame
var _profiler: Node = null
var _ticks := 0


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--" + name)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else fallback


func _physics_process(_delta: float) -> void:
	if _profiler != null:
		_profiler.call(&"_profiled_step")
		_ticks += 1


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _sample(label: String, seconds: float) -> Dictionary:
	var t_end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var n := 0
	var phys := 0.0
	var worst := 0.0
	var proc := 0.0
	var frame_worst := 0.0
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_worst = maxf(frame_worst, float(now - last) / 1000.0)
		last = now
		var p := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		phys += p
		worst = maxf(worst, p)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		n += 1
	var out := {"frames": n, "phys_avg": phys / maxf(n, 1), "phys_max": worst, "proc_avg": proc / maxf(n, 1), "frame_worst": frame_worst,
		"active": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), "pairs": int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		"islands": int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)), "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))}
	print("PHYS %s %s" % [label, JSON.stringify(out)])
	return out


func _run() -> void:
	var map_id := StringName(_arg("map", "ze_boat_escape"))
	var from_id := StringName(_arg("switch-from", ""))
	var seconds := float(_arg("seconds", "20"))
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(from_id if from_id != &"" else map_id), String(map_id)])
	_game = ZzGame.new()
	_game.name = "World"
	_game.config = config
	_game.tick_rate = 64
	_game.authoritative = true
	_game.register_service = false
	_game.next_map_id = from_id if from_id != &"" else map_id
	add_child(_game)
	await get_tree().physics_frame
	for i in range(8):
		_game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i).is_bot = true
	_game.start()
	if from_id != &"":
		await _sample("first-map", 5.0)
		var t0 := Time.get_ticks_msec()
		print("SWITCH ", _game.change_map_now(map_id))
		print("PHYS switch-call-ms ", Time.get_ticks_msec() - t0)
		await _sample("switch+5s", 5.0)
	await _sample("warm", 5.0)
	if "--profile" in OS.get_cmdline_user_args():
		_profiler = (load("res://tools/survival_long_run.gd") as GDScript).new()
		_profiler.set(&"_game", _game)
		_game.external_tick = true
	var steady := await _sample("steady", seconds)
	if _profiler != null:
		var parts: Dictionary = _profiler.get(&"_parts")
		for part: String in parts:
			print("PROFILE %-14s %.3f ms/tick" % [part, float(parts[part]) / 1000.0 / maxf(1.0, _ticks)])
		_profiler.free()
	var limit := float(_arg("max-phys-ms", "0"))
	var failed := limit > 0.0 and float(steady["phys_avg"]) > limit
	print("PHYS %s steady %.1f ms (limit %.1f)" % ["FAIL" if failed else "ok", float(steady["phys_avg"]), limit])
	_game.queue_free()
	for _i in range(3):
		await get_tree().process_frame
	get_tree().quit(1 if failed else 0)
