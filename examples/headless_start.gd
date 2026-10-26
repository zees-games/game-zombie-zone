extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzPlayer := preload("../game/zz_player.gd")

## A real round start on the escape maps: a full team is added, the round begins the way a server
## begins it, and a few seconds play out with nobody invulnerable. Nobody may be dead (or below
## the map's kill height) afterwards.
##
## [b]Why its own suite.[/b] Dropping a capsule at each spawn point passed on Run For Your Life
## while every survivor fell to their death on the unrailed bridge: only stand-ins running the
## route in a real round show it. Armed: it failed (six of eight dead) before the rails.

const MAPS := [&"ze_runforyourlife_1_v4", &"ze_nuke_beta"]
const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const PLAY_SECONDS := 30.0
const SECTIONS := 2
const CHECKS := 8

var _passed := 0
var _failed := 0
var _entered := 0
var _finished := 0
var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	for id: StringName in MAPS:
		await _test_start(id)

	for old in _worlds.duplicate():
		remove_child(old)
		old.free()

	print("\n%d sections (%d finished), %d passed, %d failed" % [_entered, _finished, _passed, _failed])
	var ok := _failed == 0 and _entered == SECTIONS and _finished == SECTIONS and _passed + _failed == CHECKS
	print("PASS" if ok else "FAIL (expected %d sections and %d checks)" % [SECTIONS, CHECKS])
	get_tree().quit(0 if ok else 1)


func _test_start(id: StringName) -> void:
	_entered += 1
	print("%s: a real round start" % id)

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.start_grace_seconds = 1.0
	config.escape_grace_seconds = 0.0
	config.map_ids = PackedStringArray([String(id)])

	var game := ZzGame.new()
	game.name = "Start%s" % id
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	_worlds.append(game)
	await get_tree().physics_frame
	await get_tree().physics_frame

	game.next_map_id = id
	var team := maxi(game.team_size(), 8)

	for i in team:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.is_bot = true

	game.start()
	var low := INF

	for second in int(PLAY_SECONDS):
		await _sim(game, 1.0)

		for player in game.survivors():
			low = minf(low, player.feet().y)


	var dead := 0
	var fell := 0

	for player in game.survivors():
		if not player.is_alive():
			dead += 1

		if player.feet().y < game.map.kill_height():
			fell += 1

	var spawn_y: float = game.map.spawn("survivors", 0)[0].y
	_check(game.map.id() == id, "the round is on %s" % id)
	_check(game.survivors().size() >= 8, "a full team is seated", "%d survivors" % game.survivors().size())
	_check(dead == 0, "nobody is dead %d s in" % int(PLAY_SECONDS), "%d dead, lowest feet y %.2f, spawn y %.2f, kill_y %.1f" % [
		dead, low, spawn_y, game.map.kill_height()])
	_check(fell == 0 and low > spawn_y - 3.0, "nobody has fallen from the start", "%d below kill_y" % fell)
	_finished += 1


func _sim(game: ZzGame, seconds: float) -> void:
	var ticks := maxi(int(round(seconds * float(TICK_RATE))), 1)

	for i in ticks:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	await get_tree().physics_frame


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	print("  FAIL  %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
