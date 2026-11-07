extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNavNotes := preload("../game/zz_nav_notes.gd")

## Cold start of a round on the real game: how long the world takes to open and start, and what each
## of the first ticks costs (the map build, the first navigation bake and its annotations).
##
## [codeblock]
## godot --headless --path . res://tools/cold_start.tscn -- --map ze_biohazard_manor --ticks 600 [--cold]
## [/codeblock]
##
## --cold wipes user://nav_bake and user://nav first, so the bake is the first one on the machine.
## Prints COLDSTART / COLDSLOW / COLDWORST lines; exits 1 when open+start or any tick passes its
## limit (--max-open-ms, --max-tick-ms; 0 turns a check off).

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
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _wipe(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


func _ms(since: int) -> float:
	return float(Time.get_ticks_usec() - since) / 1000.0


func _run() -> void:
	var map_id := StringName(_arg("map", "ze_biohazard_manor"))
	var ticks := int(_arg("ticks", "600"))
	var max_tick := float(_arg("max-tick-ms", str(MAX_TICK_MS)))
	var max_open := float(_arg("max-open-ms", str(MAX_OPEN_MS)))

	if OS.get_cmdline_user_args().has("--cold"):
		_wipe("user://nav_bake")
		_wipe("user://nav")

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(map_id)])
	var game := ZzGame.new()
	game.name = "World"
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	game.next_map_id = map_id
	# As the server runs it: the first graph is built off the frame and play waits for it.
	game.nav_async = not OS.get_cmdline_user_args().has("--sync")
	var t0 := Time.get_ticks_usec()
	add_child(game)
	game.set_physics_process(false)
	var t_ready := _ms(t0)
	await get_tree().physics_frame

	var doc: Dictionary = game.catalogue.maps.get(map_id, {}) if game.catalogue != null else {}
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

	var worst := 0.0
	var worst_at := 0
	var delta := 1.0 / float(TICK_RATE)
	var waited := 0
	var wait_began := Time.get_ticks_usec()
	for i in range(ticks):
		game.horde.sections.clear()
		var began := Time.get_ticks_usec()
		game.simulate(delta)
		var spent := _ms(began)
		# The first graph is built off the frame; the ticks until it lands are the cover's.
		if game.horde.nav_blocks_play():
			waited += 1
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
	var opened := t_ready + t_start
	print("COLDNAV first graph waited %d ticks, %.0f ms wall" % [waited, _ms(wait_began)])
	print("COLDWORST %.0f ms at tick %d; open+start %.0f ms" % [worst, worst_at, opened])
	var fail := (max_tick > 0.0 and worst > max_tick) or (max_open > 0.0 and opened > max_open)
	if fail:
		printerr("COLDFAIL worst tick %.0f ms (limit %.0f), open+start %.0f ms (limit %.0f)" % [worst, max_tick, opened, max_open])
	game.queue_free()
	for _i in range(3):
		await get_tree().process_frame
	get_tree().quit(1 if fail else 0)
