extends "headless_nav_base.gd"

## A stand-in rides a ladder link of the nav graph, up and down, on zs_krusty_krab_large (8 of its 11 ladders are linked).
## The bot is driven by `ZzBots._walk_to` alone (the game's own bot think is parked), so what is tested is the path
## following and the ride (`ZzBotLadders`, gs-bot's `GSBotClimb`), not what a bot would rather do.

const MAP := "zs_krusty_krab_large"
const SECTIONS := 1
const CHECKS := 2

## Linked ladders tried (all 7 tall ones of the map), each ridden up and then down.
const TRIES := 7

## Seconds a ride has, and how close to the far end of the link the bot must stand to have made it.
const RIDE_SECONDS := 40.0
const ARRIVED := 1.2


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone bot ladders")
	print("")
	_linked = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://maps")) and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://world"))
	await _test_bot_ladders()

	for game in _worlds.duplicate():
		await _dispose(game)

	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _test_bot_ladders() -> void:
	_section("a stand-in climbs a ladder link up and down on %s" % MAP)

	if not _linked:
		for i in CHECKS:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray([MAP])
		c.survival_warmup_seconds = 600.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false)
	var bot := game.add_player(&"u300", "Climber")
	bot.is_bot = true
	bot.health.invulnerable = true
	game.start()
	var ticks := 0

	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	var nav: ZzNavGraph = game.horde.spawner.nav
	var links := _tall_links(nav)
	_check(links.size() >= TRIES, "the graph has ladder links to ride (%d tall ones, %d links)" % [links.size(), nav.ladder_count])
	var bots := game.bots
	game.bots = null
	bots._dt = TICK
	var failed := PackedStringArray()
	var step := maxi(links.size() / TRIES, 1)

	for t in mini(TRIES, links.size()):
		var link: Array = links[t * step]
		var low: Vector3 = link[0]
		var high: Vector3 = link[1]

		for up in [true, false]:
			var from := low if up else high
			var to := high if up else low
			bot.place_at(from + Vector3(0.0, 0.1, 0.0), 0.0)
			var memory: Dictionary = bots._memory(bot)
			memory["path"] = PackedVector3Array()
			memory["path_at"] = -100.0
			memory.erase("climb")
			var reached := await _ride(game, bots, bot, memory, to)

			if not reached:
				failed.append("%s %v to %v ended at %v" % ["up" if up else "down", from, to, bot.feet()])

	game.bots = bots
	_check(failed.is_empty(), "the stand-in rides every tried ladder link both ways", "; ".join(failed))
	_finished()


## [low, high] of each ladder link that rises over 2 m.
func _tall_links(nav: ZzNavGraph) -> Array:
	var out: Array = []
	var points := nav.data.points

	for a: int in nav._ladder:
		for b: int in nav._ladder[a]:
			if a < b and absf(points[a].y - points[b].y) > 2.0:
				out.append([points[a], points[b]] if points[a].y < points[b].y else [points[b], points[a]])

	return out


## Walks [param bot] to [param to] with the ride and the path following alone; true when it stands there within the time.
func _ride(game: ZzGame, bots, bot: ZzPlayer, memory: Dictionary, to: Vector3) -> bool:
	for i in int(RIDE_SECONDS * TICK_RATE):
		var command := GSFpsCommand.new()
		command.yaw = bot.controller.state.yaw
		var aim: GSBotAim = memory["aim"]
		aim.view_from(command.yaw, command.pitch)
		bots._aiming = false
		bots._walk_to(bot, command, to, memory)
		bot.controller.apply_command(command)
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

		var feet: Vector3 = bot.feet()

		if absf(feet.y - to.y) < 0.6 and Vector2(feet.x - to.x, feet.z - to.z).length() < ARRIVED:
			return true

	return false
