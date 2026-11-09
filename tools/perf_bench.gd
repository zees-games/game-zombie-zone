extends DotGamePerfBench

## Solo-client benchmark (dot-game's DotGamePerfBench: see it for the flags and the report). Runs the offline client on the
## pinned map with `--bots N` stand-ins; windowed on a GPU box through tools/perf_bench.sh, not headless.


func _configure() -> void:
	client_scene = "res://game/zz.tscn"
	# A small survival map, pinned so profiles compare; `--map ID` overrides.
	map = "zs_verystill"
	bots = 3
	warmup = 10.0


## The client boots into the catalogue's first map: change to the pinned one the way the map menu does, then wait for its world.
func _select(game: Object) -> void:
	if map == "" or String(game.get("map").call("id")) == map:
		return
	var changed: DotResult = await game.call("change_map_now", StringName(map))
	say("map %s: %s" % [map, "ok" if changed.ok else changed.error.message])
	await wait_gate(120.0)


## Motor A/B switches (all default to the game's own settings): `--native 1` DotFpsMotor.native_tick, `--native-full 1`
## DotFpsMotor.native_full, `--motor-us 1` the controller's and motor's phase timers (they cost a little), totals in the sidecar.
func _record_begin() -> void:
	if args.has("native"):
		DotFpsMotor.native_tick = int(args["native"]) != 0
	if args.has("native-full"):
		DotFpsMotor.native_full = int(args["native-full"]) != 0
	if int(args.get("motor-us", 0)) != 0:
		DotFpsMotor.profile = true
		DotFpsController.phase_us.fill(0)
		DotFpsMotor.phase_us.fill(0)


func _record_end() -> void:
	DotFpsMotor.profile = false


func _sidecar_extra(game: Object) -> Dictionary:
	var phases := {}
	if int(args.get("motor-us", 0)) != 0:
		var ctl := ["pre", "consume", "motor", "publish", "report", "signals_stats", "post"]
		for i in ctl.size():
			phases["ctl." + ctl[i]] = DotFpsController.phase_us[i] / 1000.0
		for i in DotFpsMotor.PHASES.size():
			if DotFpsMotor.PHASES[i] != "":
				phases["motor." + DotFpsMotor.PHASES[i]] = DotFpsMotor.phase_us[i] / 1000.0
	return {"phases_total_ms": phases, "survivors": (game.call("survivors") as Array).size(),
		"native_tick": DotFpsMotor.native_tick, "native_full": DotFpsMotor.native_full}
