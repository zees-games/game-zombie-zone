extends GSGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")

## No single tick may stall while a map's navigation is built. The owner's native build froze for about two minutes at
## "Navigation regenerating 99%" on gm_balkans: the build itself runs on a thread, but the graph's physics prune (a shape
## query along every edge of a 50 000 point graph) ran in one call on the main thread when the build ended. The graph is
## built cold here (no cache) the way the server builds it, off the frame, and every tick of the wait is timed.

const MAPS := [&"gm_balkans"]
const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
## The longest one tick may take while the graph is built. A frame at 20 fps; the freeze was minutes.
const MAX_TICK_MS := 250.0
## The tick that lands the finished graph (search graph, posts, spawn thinning) is one call on the main thread; it is held
## to a looser bound, which is the work left to slice (see the Nightly item zz-native-freeze-1).
const MAX_LAND_MS := 5000.0
const MAX_WAIT_TICKS := 400000
const CHECKS := 5

var _entered := 0
var _finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	for id: StringName in MAPS:
		await _test_build(id)

	_report_sections(_entered, _finished, MAPS.size(), CHECKS)


func _test_build(id: StringName) -> void:
	_entered += 1
	print("%s: a cold navigation build" % id)
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.nav_cache = false
	config.map_ids = PackedStringArray([String(id)])
	var game := ZzGame.new()
	game.name = "Stall%s" % id
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	game.next_map_id = id
	# As the server runs it: the graph is built off the frame and play waits for it.
	game.nav_async = true
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame

	if game.catalogue == null or game.catalogue.doc(id).is_empty():
		_check(false, "%s is in the catalogue" % id)
		game.queue_free()
		_finished += 1
		return

	for i in int((game.catalogue.doc(id) as Dictionary).get("survivors", 4)):
		var player := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.is_bot = true

	var began := Time.get_ticks_usec()
	game.start()
	var opened := float(Time.get_ticks_usec() - began) / 1000.0
	var worst := 0.0
	var worst_stage := "-"
	var seen_prune := false
	var landed := 0.0
	var ticks := 0

	# The first tick builds the map and starts the graph; every tick up to the one that lands it is timed.
	while ticks < MAX_WAIT_TICKS and (ticks == 0 or game.horde.nav_blocks_play()):
		ticks += 1
		var stage: String = game.horde.nav_stage()
		seen_prune = seen_prune or stage == "prune"
		var at := Time.get_ticks_usec()
		game.simulate(TICK)
		var spent := float(Time.get_ticks_usec() - at) / 1000.0

		if ticks > 1 and not game.horde.nav_blocks_play():
			landed = spent
		elif spent > worst:
			worst = spent
			worst_stage = "%s #%d -> %s" % [stage, ticks, game.horde.nav_stage()]

		if ticks % 4 == 0:
			await get_tree().physics_frame

	_check(not game.horde.nav_blocks_play(), "the graph landed", "%d ticks" % ticks)
	_check(game.horde.nav != null and game.horde.nav.point_count() > 100, "and it has ground", "%d points" % (game.horde.nav.point_count() if game.horde.nav != null else 0))
	_check(seen_prune, "the prune ran in slices (stage 'prune' was reported)")
	_check(worst <= MAX_TICK_MS, "no tick took over %d ms while it was built" % int(MAX_TICK_MS), "worst %.0f ms in %s" % [worst, worst_stage])
	_check(landed <= MAX_LAND_MS, "the tick that lands the graph took at most %d ms" % int(MAX_LAND_MS), "%.0f ms" % landed)
	print("  start %.0f ms, worst tick %.0f ms (%s), landing tick %.0f ms, %d ticks waited, sections %s" % [opened, worst, worst_stage, landed, ticks, game.horde.sections])
	remove_child(game)
	game.free()
	_finished += 1
