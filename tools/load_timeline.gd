extends Node

const ZzClientScript := preload("../game/zz_client.gd")

## How long the solo client's loading cover stays up and which reasons hold it: prints the engine time each gate reason (map, world, weapons, warm-up) clears, to
## compare a change to the load. Software GL: use xvfb-run, never --headless (no weapon prewarm): `xvfb-run -a godot --path . --rendering-driver opengl3
## res://tools/load_timeline.tscn`. `-- --hitch-secs=N` (default 10, 0 = skip) records every frame of 50 ms or more for N seconds after the gate opens.


func _ready() -> void:
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
	var cover := GSHitchLog.new()
	cover.threshold_ms = 50.0
	cover.start(get_tree())
	var client: Node = ZzClientScript.new()
	client.set("force_offline", true)
	add_child(client)
	var began := Time.get_ticks_msec()
	var gate: Object = client.get("gate")
	# Software GL frames are slow; the gate's own timeout would release the holds before the work is done.
	gate.set("timeout_sec", 300.0)
	gate.set("warm_timeout_sec", 120.0)
	var seen := {}
	while not bool(gate.call(&"is_open")) and Time.get_ticks_msec() - began < 280_000:
		var why := ", ".join((gate.call(&"reasons") as Array).map(func(r: Variant) -> String: return str(r)))
		if why != "" and not seen.has(why):
			seen[why] = true
			print("load_timeline: +%5d ms  waiting on: %s" % [Time.get_ticks_msec() - began, why])
		await get_tree().process_frame
	var open := bool(gate.call(&"is_open"))
	print("load_timeline: gate %s %d ms after the client was added" % ["open" if open else "STILL CLOSED at", Time.get_ticks_msec() - began])
	cover.stop()
	_print_hitches("under cover", cover)
	if open:
		await _watch_after_gate()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if open else 1)


func _watch_after_gate() -> void:
	var secs := 10.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hitch-secs="):
			secs = float(arg.get_slice("=", 1))
	if secs <= 0.0:
		return
	var hitch := GSHitchLog.new()
	hitch.threshold_ms = 50.0
	hitch.start(get_tree())
	await get_tree().create_timer(secs).timeout
	hitch.stop()
	_print_hitches("after gate %.0f s" % secs, hitch)


func _print_hitches(label: String, hitch: GSHitchLog) -> void:
	var stall := 0.0
	for h: Dictionary in hitch.hitches:
		stall += float(h.ms)
	print("load_timeline: %s: %d frames, %d hitches, %.0f ms stalled" % [label, hitch.frames, hitch.hitches.size(), stall])
	for line in hitch.report(12):
		print("load_timeline: ", line)
