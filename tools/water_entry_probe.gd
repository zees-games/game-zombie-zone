extends Node
## Probe: drops a survivor at points of a map and walks it in eight directions with the real motor,
## printing where it moved less than a metre and its water level.
## Probe: drops a survivor into a map's water, ticks it and prints the feet, mode and the slowest ticks.
##   godot --headless --path . res://tools/water_entry_probe.tscn -- <map id> x,z[,y] [--walk]
const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const TICK_RATE := 60
const TICK := 1.0 / TICK_RATE


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var dir := ""
	var trace := args.has("--trace")
	args.erase("--trace")
	for a: String in args.duplicate():
		if a.begins_with("--dir="):
			dir = a.substr(6)
			args.erase(a)
	var id := StringName(args[0]) if args.size() > 0 else &"zm_4way_tunnel"
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.start_grace_seconds = 600.0
	config.map_ids = PackedStringArray([String(id)])
	if dir != "":
		config.map_directory = dir
	var game := ZzGame.new()
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	var p := game.add_player(&"u1", "Walker")
	p.health.invulnerable = true
	game.next_map_id = id
	game.start()
	for i in 8:
		game.simulate(TICK)
	var parts: PackedStringArray = (args[1] as String).split(",")
	var at := Vector3(float(parts[0]), float(parts[2]) if parts.size() > 2 else 2.0, float(parts[1]))
	p.place_at(at, 0.0)
	var walk := OS.get_cmdline_user_args().has("--walk")
	var c := DotFpsCommand.new()
	c.move = Vector2(0, 1) if walk else Vector2.ZERO
	var times: Array = []
	var lowest := INF
	for i in 600:
		p.controller.apply_command(c)
		var t0 := Time.get_ticks_usec()
		game.simulate(TICK)
		times.append([Time.get_ticks_usec() - t0, i])
		lowest = minf(lowest, p.feet().y)
		if i % 60 == 59:
			print("t%d feet %s mode %s water %s" % [i, p.feet(), p.controller.state.mode, p.water_level])
		await get_tree().physics_frame
	times.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("slowest ticks (usec, index): ", times.slice(0, 5))
	print("median usec: ", times[times.size() / 2][0], " lowest y: ", lowest, " rescued: ", game.footing.rescued)
	get_tree().quit(0)
