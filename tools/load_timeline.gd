extends Node

const ZzClientScript := preload("../game/zz_client.gd")

## How long the solo client's loading cover stays up, and which reasons hold it: prints the engine
## time each gate reason (map, world, weapons, warm-up) clears and when the gate opens, so a change
## to the load can be compared back to back. Software GL: the CPU side is real, shader compiles are
## not (use xvfb-run, never --headless, which skips the weapon prewarm).
##
## [codeblock]
## xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 480x270 res://tools/load_timeline.tscn
## [/codeblock]


func _ready() -> void:
	Engine.max_fps = 0
	_run.call_deferred()


func _run() -> void:
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
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0 if open else 1)
