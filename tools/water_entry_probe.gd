extends "zz_water_probe.gd"

## Probe: drops a survivor into a map's water, ticks it and prints the feet, mode and the slowest ticks.
##   godot --headless --path . res://tools/water_entry_probe.tscn -- <map id> x,z[,y] [--walk]

const ZzPlayer := preload("../game/zz_player.gd")


func _run() -> void:
	await _open_walker()
	var args := _args
	var game := _game
	var p: ZzPlayer = _walker
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
