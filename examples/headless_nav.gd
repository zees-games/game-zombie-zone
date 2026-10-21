extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNavGraph := preload("../game/zz_nav_graph.gd")
const ZzNavNotes := preload("../game/zz_nav_notes.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const StuckMeter := preload("../tools/stuck_meter.gd")

## The annotations in use: where the stand-ins stand before a wave, where the horde goes, and the
## graph's one-way drops. Every check that compares a behaviour with the old one runs both (the
## cvars `zz_bot_hold_chokes` and `zz_zombie_spread` off are the old behaviour) and fails if the
## new one is not better: armed, so a bot that goes back to its post at a window turns this red.
##
## Counts sections and checks (dot-settings' story).

const SECTIONS := 15
const CHECKS := 56

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

## Maps held by a team, and how far from a choke a stand-in counts as holding it.
const MAPS := ["zz_high_school", "zz_mall", "zz_stadium", "zz_relief_camp", "zz_chapel", "zz_lot", "zs_ravenstreet"]
const NEAR := 7.0

## Seconds the stand-ins have to walk to their places before a wave comes.
const SETTLE := 45.0
const HORDE_SECONDS := 120.0

## Every shipped map, for the stuck measurement.
const ALL_MAPS := ["zz_blackout_1", "zz_blackout_2", "zz_blackout_3", "zz_chapel", "zz_high_school", "zz_lot", "zz_mall", "zz_relief_camp",
	"zz_stadium", "zs_ravenstreet", "zm_4way_tunnel", "zm_abandoned_mall", "zm_atix_helicopter", "zm_chaos_city", "zm_house_outbreak",
	"zm_officeattack", "zm_pathogen", "ze_blackmesa_escape", "ze_boat_escape", "ze_death_star_escape", "ze_jurassicpark", "ze_nuke_beta",
	"ze_runforyourlife_1_v4"]

## Maps held to a stuck band, each once a worst case: blackout_2 had a 108 s wedge on a pallet, atix walked
## its stand-ins into a wall through an importer link, high_school wedged on a low prop. The bands are wide
## because two runs of one map differ; they catch a return to those numbers, not a 1% drift.
const STUCK_BANDS := ["zz_blackout_2", "zm_atix_helicopter", "zz_high_school"]
const STANDIN_BAND := 0.15
const COMMON_BAND := 0.10
const LONGEST_BAND := 30.0

## Simulated seconds a map is played for the stuck measurement, after the first ten.
const STUCK_SECONDS := 150.0

## What a stand-in map's team is raised to: the maps that say none are still held by a few.
const TEAM := 8

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()
var _worlds: Array[ZzGame] = []
var _linked := false

## A stand-in for the horde that says how many zombies are at a choke.
class Crowd:
	extends RefCounted
	var count := 0

	class Fake:
		extends RefCounted
		var instance_id := 0

	func zombies_near(_at: Vector3, _radius: float) -> Array:
		var out: Array = []

		for i in count:
			var z := Fake.new()
			z.instance_id = i
			out.append(z)

		return out


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone navigation notes")
	print("")
	_linked = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://maps"))

	# Development only: `-- --only=spread` runs the sections whose name has it (counts then skipped).
	var only := ""

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)

	if only.begins_with("stuck"):
		# Development: `--only=stuck` every map, `--only=stuck:zz_mall` one; prints the table.
		var ids: Array = ALL_MAPS if only == "stuck" else [only.substr(6)]

		for id: String in ids:
			var meter: StuckMeter = await _stuck(StringName(id))
			print("STUCK %-24s %s" % [id, meter.line()])
			for kind: StringName in StuckMeter.KINDS:
				print("      %s worst cells %s" % [kind, meter.worst_cells(kind)])
			for line in meter.cases.slice(0, 8):
				print("      case %s" % line)

		get_tree().quit(0)
		return

	if only.begins_with("hold:"):
		await _test_holding(StringName(only.substr(5)))
		get_tree().quit(0)
		return

	if only != "":
		await _test_spread(&"zz_high_school")
		await _test_spread(&"zz_mall")
		get_tree().quit(0)
		return

	_test_graph()
	await _test_exodus()

	var holds := {}
	var spreads := {}

	for id: String in MAPS:
		holds[id] = await _test_holding(StringName(id))

	await _test_fallback()
	await _test_spread(&"zz_high_school")
	await _test_spread(&"zz_mall")

	for id: String in STUCK_BANDS:
		await _test_stuck(StringName(id))

	print("")
	print("%d sections entered, %d finished" % [_sections_entered, _sections_finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _sections_entered != _sections_finished or _sections_entered != SECTIONS:
		print("ERROR: %d of %d sections finished, %d expected." % [_sections_finished, _sections_entered, SECTIONS])
		code = 1

	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		code = 1

	for game in _worlds.duplicate():
		await _dispose(game)

	get_tree().quit(code)


# --- The graph ----------------------------------------------------------------------------------

## Four points high and four low, a drop between: a zombie goes down it, never up, a stand-in
## does neither, and a climbing zombie goes both ways.
func _test_graph() -> void:
	_section("the graph: drops are one way and the zombies' alone")
	var data := DotNpcNavData.new()
	data.map_id = &"drop_test"
	data.source_digest = "test"
	data.grid_spacing = 1.0
	var high := PackedInt32Array()
	var low := PackedInt32Array()

	for i in 3:
		high.append(data.add_point(Vector3(float(i), 3.0, 0.0)))

	for i in 3:
		low.append(data.add_point(Vector3(float(i), 0.0, 6.0)))

	for i in 2:
		var _a := data.connect_points(high[i], high[i + 1])
		var _b := data.connect_points(low[i], low[i + 1])

	var graph := ZzNavGraph.new()
	var built := graph.rebuild(data)
	_check(built.ok, "the test graph builds", "" if built.ok else built.error.message)
	_check(graph.find_path(Vector3(0.0, 3.0, 0.0), Vector3(2.0, 0.0, 6.0), 0.5).is_empty(),
		"two floors with no link are two pieces")

	graph.add_drop(high[2], low[0])
	graph.relabel()
	var down := graph.find_path(Vector3(0.0, 3.0, 0.0), Vector3(2.0, 0.0, 6.0), 0.5)
	var up := graph.find_path(Vector3(2.0, 0.0, 6.0), Vector3(0.0, 3.0, 0.0), 0.5)
	_check(not down.is_empty(), "a zombie walks down a drop", str(down.size()))
	_check(up.is_empty(), "and cannot walk back up it", str(up.size()))

	var saved := graph.filter
	graph.filter = graph.bot_filter
	_check(graph.find_path(Vector3(0.0, 3.0, 0.0), Vector3(2.0, 0.0, 6.0), 0.5).is_empty(),
		"a stand-in never takes a drop")
	graph.filter = saved

	graph.add_climb(low[0], high[2])
	graph.relabel()
	_check(graph.find_path(Vector3(2.0, 0.0, 6.0), Vector3(0.0, 3.0, 0.0), 0.5).is_empty(),
		"a jump up is not taken while zombies do not climb (zz_zombie_climb)")
	graph.allow_climb = true
	_check(not graph.find_path(Vector3(2.0, 0.0, 6.0), Vector3(0.0, 3.0, 0.0), 0.5).is_empty(),
		"and is taken, both ways, when they do")
	_finished()


# --- Exodus -------------------------------------------------------------------------------------

func _test_exodus() -> void:
	_section("an exodus map keeps its stand-ins and its follow-the-leader")
	if not _linked:
		for i in 3:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_blackout_1"])
		c.wanderer_density = 0.0)
	var human := game.add_player(&"u1", "Human")
	human.health.invulnerable = true
	game.start()
	await _sim(game, 4.0)
	var bots := 0

	for p in game.survivors():
		if p.is_bot:
			bots += 1

	_check(game.map.id() == &"zz_blackout_1" and not game.is_survival(), "it is the exodus map")
	_check(game.team_size() >= game.config.exodus_team and bots == 0, "the exodus team size is still zz_exodus_team", "%d of %d" % [game.team_size(), game.config.exodus_team])
	_check(game.config.humans_pass_barricades and game.config.friendly_fire_mode == 2, "barricade and friendly-fire rules untouched")
	await _dispose(game)
	_finished()


# --- Holding ------------------------------------------------------------------------------------

## Stand-ins walk to their places over [constant SETTLE] seconds of no wave: how many of them are
## within [constant NEAR] metres of a choke on the horde's way, with the holds on and off.
func _test_holding(id: StringName) -> void:
	_section("%s: stand-ins hold the chokes" % id)
	if not _linked:
		for i in 4:
			_check(true, "skipped without maps/")
		_finished()
		return

	var on := await _settle(id, true)
	var off := await _settle(id, false)
	_check(on["ready"] and on["chokes"] >= 1, "it is annotated and has chokes on the horde's routes",
		"%d on routes of %d found, %.0f ms bake, %.0f annotate" % [on["chokes"], on["found"], on["bake"], on["annotate"]])
	_check(on["share"] >= 0.75, "most stand-ins stand at a choke before the wave", "%.2f within %.0f m" % [on["share"], NEAR])
	_check(on["share"] >= off["share"] + 0.25 or (off["share"] >= 0.9 and on["share"] >= off["share"]), "which the posts alone did not do (a post already at a choke is allowed to stay)",
		"%.2f against %.2f at their posts" % [on["share"], off["share"]])
	_check(on["distinct"] >= mini(2, on["places"]), "and they are spread over the chokes, not at one",
		"%d chokes held of %d (%d places to stand)" % [on["distinct"], on["chokes"], on["places"]])
	_finished()


func _settle(id: StringName, holding: bool) -> Dictionary:
	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray([String(id)])
		c.survival_style = 0
		c.survival_warmup_seconds = 300.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false
		c.bot_hold_chokes = holding)

	for i in maxi(game.team_size(), TEAM):
		var p := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		p.is_bot = true
		p.health.invulnerable = true

	game.start()
	var ticks := 0

	while game.horde.notes.state < ZzNavNotes.State.READY and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	await _sim(game, SETTLE)
	var notes: ZzNavNotes = game.horde.notes
	var near := 0
	var total := 0
	var held := {}

	for p in game.survivors():
		if not p.is_bot:
			continue

		total += 1
		var best := INF

		for i in notes.chokes.size():
			var at: Vector3 = notes.chokes[i]["at"]
			best = minf(best, Vector2(at.x - p.feet().x, at.z - p.feet().z).length())

		if best > NEAR:
			continue

		near += 1

		# Which choke it holds is the one whose place to stand (`hold`, a few metres behind the
		# choke) is nearest it, not the one whose choke is: on a street where two chokes are a few
		# metres apart a bot standing behind one is nearer the other's choke, and the count then
		# flipped between runs on where each stand-in had got to.
		var mine := -1
		var mine_d := INF

		for i in notes.chokes.size():
			var spot: Vector3 = notes.chokes[i]["hold"]

			if spot == Vector3.INF:
				spot = notes.chokes[i]["at"]

			var d := Vector2(spot.x - p.feet().x, spot.z - p.feet().z).length()

			if d < mine_d:
				mine_d = d
				mine = i

		held[mine] = true

	# Chokes whose places to stand coincide (two on one route can share the one behind them) are one
	# place to hold, and a spread cannot be asked of fewer places than there are.
	var places := {}

	for c in notes.chokes:
		var spot: Vector3 = c["hold"] if c["hold"] != Vector3.INF else c["at"]
		places[Vector2i(roundi(spot.x / 2.0), roundi(spot.z / 2.0))] = true

	var out := {
		"places": places.size(), "ready": notes.is_ready(), "chokes": notes.chokes.size(), "found": notes.all_chokes.size(),
		"share": float(near) / float(maxi(total, 1)), "distinct": held.size(),
		"bake": notes.bake_ms, "annotate": notes.annotate_ms,
	}
	await _dispose(game)
	return out


# --- Stuck -------------------------------------------------------------------------------------

## A team of stand-ins plays [param id] against its horde for [constant STUCK_SECONDS], and a
## [StuckMeter] says how long movers with a goal stood still.
func _stuck(id: StringName) -> StuckMeter:
	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray([String(id)])
		c.survival_warmup_seconds = 10.0
		c.wanderer_density = 0.0)

	for i in maxi(game.team_size(), TEAM):
		var p := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		p.is_bot = true
		p.health.invulnerable = true

	game.start()
	var meter := StuckMeter.new(game)
	var ticks := int(STUCK_SECONDS * float(TICK_RATE))

	for i in ticks:
		game.simulate(TICK)
		meter.sample()

		if i % 8 == 7:
			await get_tree().physics_frame

	await _dispose(game)
	return meter


func _test_stuck(id: StringName) -> void:
	_section("%s: movers with a goal do not stand still" % id)
	var meter: StuckMeter = await _stuck(id)
	var detail := meter.line()
	_check(meter.ratio(&"standin") <= STANDIN_BAND, "stand-ins are stuck under %d%% of their goal time" % int(STANDIN_BAND * 100.0), detail)
	_check(meter.ratio(&"common") <= COMMON_BAND, "commons are stuck under %d%% of their goal time" % int(COMMON_BAND * 100.0), detail)
	_check(maxf(meter.longest[&"standin"], meter.longest[&"common"]) <= LONGEST_BAND, "no mover is stuck longer than %.0f s" % LONGEST_BAND, detail)
	_finished()


# --- Falling back -------------------------------------------------------------------------------

func _test_fallback() -> void:
	_section("an overrun choke is given up for the next one toward the post")
	if not _linked:
		for i in 4:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_high_school"])
		c.survival_style = 0
		c.survival_warmup_seconds = 300.0
		c.wanderer_density = 0.0)
	var p := game.add_player(&"u1", "Human")
	p.health.invulnerable = true
	game.start()
	var ticks := 0

	while game.horde.notes.state < ZzNavNotes.State.READY and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	var notes: ZzNavNotes = game.horde.notes
	var seat := -1

	for i in notes.chokes.size():
		if int(notes.chokes[i]["fallback"]) >= 0:
			seat = i
			break

	_check(seat >= 0, "a choke has one nearer the post to fall back to", "%d chokes" % notes.chokes.size())
	var own: Vector3 = notes.hold_for(seat)
	var crowd := Crowd.new()
	crowd.count = notes.chokes.size() * 0 + game.config.bot_hold_overrun
	notes._time = 10.0
	notes._next_scan = 0.0
	notes.update(0.0, crowd)
	var moved: Vector3 = notes.hold_for(seat)
	_check(notes.chokes[seat]["overrun"] and moved != own and moved != Vector3.INF or notes.held_by(seat) != seat,
		"overrun, a stand-in leaves for another place", "%s -> %s" % [own, moved])
	crowd.count = 0
	notes._time = 12.0
	notes._next_scan = 0.0
	notes.update(0.0, crowd)
	_check(notes.hold_for(seat) == own, "and goes back when the crowd is gone")
	await _dispose(game)
	_finished()


# --- The horde ----------------------------------------------------------------------------------

## A wave plays for [constant HORDE_SECONDS] against a team that cannot die: how many different
## zombies reached each choke, with the spread on and off.
func _test_spread(id: StringName) -> void:
	_section("%s: the horde comes by every way in" % id)
	if not _linked:
		for i in 3:
			_check(true, "skipped without maps/")
		_finished()
		return

	var on := await _horde(id, true)
	var off := await _horde(id, false)
	var line := "on %s, off %s" % [on, off]
	_check(on["total"] >= 5 and on["reached"] >= 2, "a wave reaches the chokes, by more than one", line)
	_check(on["sent"] >= mini(3, on["chokes"]) and on["sent_top"] <= 0.5,
		"zombies are sent through at least three chokes, none taking half", line)
	# Where they physically arrive is noisy (the stand-ins kill what comes, wherever it comes by),
	# so it is printed in the detail and not asserted: the sending is what the code decides.
	_check(off["sent"] == 0, "with zz_zombie_spread off nothing is sent anywhere (the old behaviour)", line)
	_finished()


func _horde(id: StringName, spread: bool) -> Dictionary:
	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray([String(id)])
		c.survival_style = 0
		c.survival_warmup_seconds = 25.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false
		c.zombie_spread = spread)

	for i in maxi(game.team_size(), TEAM):
		var p := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		p.is_bot = true
		p.health.invulnerable = true

	game.start()
	var ticks := 0

	# Notes first: the wave is two seconds off, and its planning must not race the first zombies.
	while game.horde.notes.state < ZzNavNotes.State.READY and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	await _sim(game, HORDE_SECONDS)
	var notes: ZzNavNotes = game.horde.notes
	var total := 0
	var top := 0
	var sent_total := 0

	for i in notes.visited:
		var n: int = notes.visited[i]
		total += n
		top = maxi(top, n)

	var sent := 0
	var sent_top := 0

	for i in notes.chosen:
		sent_total += int(notes.chosen[i])
		sent += 1
		sent_top = maxi(sent_top, int(notes.chosen[i]))

	var out := {
		"total": total, "top": float(top) / float(maxi(total, 1)), "reached": notes.visited.size(),
		"sent": sent, "sent_top": float(sent_top) / float(maxi(sent_total, 1)), "chokes": notes.chokes.size(),
	}
	await _dispose(game)
	return out


# --- Helpers -------------------------------------------------------------------------------------

func _world(configure: Callable = Callable()) -> ZzGame:
	for old in _worlds.duplicate():
		await _dispose(old)

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.start_grace_seconds = 1.0

	if configure.is_valid():
		configure.call(config)

	var game := ZzGame.new()
	game.name = "World%d" % _worlds.size()
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	_worlds.append(game)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return game


func _dispose(game: ZzGame) -> void:
	_worlds.erase(game)

	if not is_instance_valid(game):
		return

	remove_child(game)
	game.free()
	await get_tree().process_frame


func _sim(game: ZzGame, seconds: float) -> void:
	var ticks := maxi(int(round(seconds * float(TICK_RATE))), 1)

	for i in ticks:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	await get_tree().physics_frame


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	var line := "%s%s" % [what, "" if detail == "" else "  (%s)" % detail]
	_failures.append(line)
	print("  FAIL  %s" % line)
