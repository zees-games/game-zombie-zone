extends Node

const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzEvent := preload("../game/net/zz_event.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzHud := preload("../game/zz_hud.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzPlayer := preload("../game/zz_player.gd")

## Survival maps, held: the three styles a server picks (`zz_survival`), the breather, a wipe,
## the barricades, the team a map is built for, and then every big survival map played for a
## wave by a full team of stand-ins.
##
## [b]Why its own suite.[/b] `headless_run` is the rules on the practice street; this is the
## hold, and the big maps, which take a minute of simulated play each to say anything. The
## schedule itself (when a wave ends, how they grow) is dot-npc-ai-director's and its own suite
## holds it; what is checked here is what this game makes of it.
##
## Counts sections and checks; the second is the one that matters (dot-settings' story).

const SECTIONS := 13
const CHECKS := 67

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

## In the practice street, clear of the cars.
const STREET := Vector3(0.0, 0.05, 14.0)

## The big survival maps, and where in each a test window is: a classroom window, a shop
## door, a tunnel to the field, a gate. Each is a barricade id and a point inside it.
const BIG_MAPS := ["zz_high_school", "zz_mall", "zz_stadium", "zz_relief_camp"]

## Simulated seconds a full team plays a big map for.
const PLAY_SECONDS := 75.0

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()
var _worlds: Array[ZzGame] = []
var _linked := false

## The last map decided in the world under test: [won, why]. Read from `round_over`, because
## with no intermission the next round has begun (and forgotten the decision) by the time a
## section looks.
var _result: Array = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone survival")
	print("")
	_linked = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://maps"))

	await _test_waves()
	await _test_nights()
	await _test_clock()
	await _test_wipe()
	await _test_barricades()
	await _test_team_size()
	_test_the_wire()
	_test_the_hud()
	await _test_map_rows()

	for id: String in BIG_MAPS:
		await _test_big_map(StringName(id))

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


# --- The three styles --------------------------------------------------------------------------

## Waves: each bigger than the last, a breather between that stands the downed up and restocks
## the caches, and the last one cleared wins the map.
func _test_waves() -> void:
	_section("waves: bigger each time, a breather between, the last one wins")
	var game := await _hold(func(c: ZzConfig) -> void:
		c.survival_style = 0
		c.waves = 3
		c.survival_warmup_seconds = 1.0
		c.breather_seconds = 2.0
		c.wave_size = 6
		c.wave_size_per_survivor = 0
		c.brute_every_waves = 0
		c.wave_twists = false, 2)
	var budgets: Array = []
	var stages: Array = []

	await _sim(game, 1.5)
	_check(game.survival != null and game.survival.waves.stage == DotNpcDirectorWaves.Stage.HORDE and game.survival.waves.index == 1,
		"the opening quiet gives way to wave 1", str(game.survival_state()))
	game.survival.waves.stage_changed.connect(func(stage: int, index: int) -> void:
		stages.append([stage, index])
		if stage == DotNpcDirectorWaves.Stage.HORDE:
			budgets.append(game.survival.waves.budget))
	budgets.append(game.survival.waves.budget)

	# Wave 1's zombies come from the map's edges and know where the team is.
	await _sim(game, 3.0)
	var forced := 0
	for npc in game.horde.spawner.npcs_of(game.horde.WAVE):
		if npc.brain != null and str(npc.brain.get(&"forced")) != "":
			forced += 1
	_check(game.horde.wave_alive() > 0 and forced > 0, "a wave is released over time, and it comes for the team",
		"%d alive, %d sent at somebody" % [game.horde.wave_alive(), forced])

	# One of the team is down when the wave is cleared; the breather stands them up.
	var hurt: ZzPlayer = game.survivors()[1]
	hurt.health.invulnerable = false
	_hurt(game, hurt, 500.0)
	hurt.health.invulnerable = true
	var was_down := hurt.is_down()
	await _clear_wave(game, 1)
	_check(game.survival.waves.stage == DotNpcDirectorWaves.Stage.QUIET and game.survival.waves.index == 2,
		"killing all of wave 1 starts the breather", str(game.survival_state()))
	_check(was_down and hurt.is_up(), "and the breather stands the downed up")
	var stocked := 0
	for raw: Array in game.map_doc.get("caches", []):
		for id: int in game.loot.entries:
			if (game.loot.position_of(id) as Vector3).distance_to(ZzMapDoc.v3(raw)) < 1.6:
				stocked += 1
	_check(stocked >= 3 * (game.map_doc.get("caches", []) as Array).size(), "and restocks every cache", "%d things" % stocked)

	await _clear_wave(game, 2)
	await _clear_wave(game, 3)
	_check(budgets.size() == 3 and int(budgets[1]) > int(budgets[0]) and int(budgets[2]) > int(budgets[1]),
		"each wave is bigger than the last", str(budgets))
	_check(_won_with("3 waves"), "clearing the last wave wins the map", str(_result))
	_check(stages.size() >= 5, "every stage was announced", str(stages))
	_finished()


## Nights: a day to get ready (the light is day), a night to live through, harder each night;
## the last dawn wins.
func _test_nights() -> void:
	_section("nights: day, night, day, night, morning")
	var game := await _hold(func(c: ZzConfig) -> void:
		c.survival_style = 1
		c.nights = 2
		c.survival_warmup_seconds = 4.0
		c.day_seconds = 4.0
		c.night_seconds = 6.0, 2)
	await _sim(game, 2.0)
	var held := game.survival_state()
	_check(int(held.get("stage", -1)) == DotNpcDirectorWaves.Stage.QUIET and float(held.get("daylight", 0.0)) > 0.5,
		"the first stretch is day, in daylight", str(held))
	_check(not game.horde.pacing, "and nothing hunts by day")
	await _sim(game, 3.0)
	held = game.survival_state()
	_check(int(held.get("stage", -1)) == DotNpcDirectorWaves.Stage.HORDE and float(held.get("daylight", 1.0)) == 0.0 and game.horde.pacing,
		"then night falls and the horde runs", str(held))
	var first := game.horde.intensity
	await _sim(game, 6.5)
	_check(game.survival.waves.stage == DotNpcDirectorWaves.Stage.QUIET and not game.horde.pacing, "dawn ends the night, whatever is left")
	await _sim(game, 4.5)
	_check(game.horde.intensity > first, "the second night is harder", "%.2f then %.2f" % [first, game.horde.intensity])
	await _sim(game, 6.5)
	_check(_won_with("2 nights"), "living through the last night wins the map", str(_result))
	_finished()


func _test_clock() -> void:
	_section("the clock: held to its time")
	var game := await _hold(func(c: ZzConfig) -> void:
		c.survival_style = 2
		c.survive_seconds = 5.0, 1)
	await _sim(game, 1.0)
	var held := game.survival_state()
	_check(int(held.get("stage", -1)) == DotNpcDirectorWaves.Stage.HORDE and float(held.get("left", -1.0)) > 0.0 and game.horde.pacing,
		"the clock starts at once and the horde runs", str(held))
	await _sim(game, 5.0)
	_check(_won_with("held out"), "and the map is won when it runs out", str(_result))
	_finished()


## The first play test ended on "everybody is down" and nothing after it. A wipe loses the map,
## and the round after it starts the hold again.
func _test_wipe() -> void:
	_section("a wipe loses the hold, and the map starts again")
	var game := await _hold(func(c: ZzConfig) -> void:
		c.survival_style = 0
		c.survival_warmup_seconds = 1.0
		c.intermission_seconds = 1.0, 2)
	await _sim(game, 2.0)
	var number := game.round_number
	for player in game.survivors():
		player.health.invulnerable = false
		_hurt(game, player, 500.0)
	await _sim(game, 2.6)
	_check(_result.size() == 2 and not bool(_result[0]) and str(_result[1]).begins_with("everybody"), "nobody standing loses it", str(_result))
	await _sim(game, 3.5)
	_check(game.round_number > number and game.phase != ZzGame.Phase.IDLE, "and the map is played again after the intermission",
		"round %d -> %d, phase %d" % [number, game.round_number, game.phase])
	for player in game.survivors():
		player.health.invulnerable = true
	await _sim(game, 3.0)
	_check(game.survival != null and game.survival.waves.index == 1 and game.survivors()[0].is_up(),
		"with the hold begun again from wave 1, everybody up", str(game.survival_state()))
	_finished()


# --- Barricades --------------------------------------------------------------------------------

## A classroom window at the school: the horde comes to it and tears at it, cannot pass while it
## stands, comes through when it breaks; a survivor holding E mends and rebuilds it.
func _test_barricades() -> void:
	_section("barricades: torn at, broken, mended")
	if not _linked:
		print("(no map directory: skipped, and counted)")
		for i in 8:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _hold(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_high_school"])
		c.survival_style = 0
		c.survival_warmup_seconds = 300.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false, 1, &"zz_high_school")
	var me: ZzPlayer = game.survivors()[0]
	var id := "n2_e"
	var box: AABB = game.map.barricade_bounds(id)
	_check(box.size.x > 1.0 and game.barricades.has(id) and bool(game.barricades[id]["intact"]),
		"the map's windows are barricades, standing", "%s %s" % [id, box])
	# Inside the classroom, a few metres back from the window.
	me.place_at(Vector3(box.get_center().x, 0.05, 11.0), 0.0)
	var outside := Vector3(box.get_center().x, 0.0, 19.0)
	for i in 8:
		var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, game.horde.snap_to_nav(outside + Vector3(randf_range(-3, 3), 0, randf_range(0, 3))), &"test")
		if npc != null:
			npc.brain.call(&"force_target", me.player_id)
	# Whichever of the room's two windows the horde's path takes them to.
	var pair := ["n2_w", "n2_e"]
	var start := float(game.barricades[id]["health"])
	var through_early := false
	for i in 20:
		await _sim(game, 0.5)
		for npc in game.horde.spawner.npcs_of(&"test"):
			if npc.is_alive() and npc.position().z < box.position.z - 0.3:
				through_early = true
	var weakest := ""
	var torn := INF
	for bid: String in pair:
		if float(game.barricades[bid]["health"]) < torn:
			torn = float(game.barricades[bid]["health"])
			weakest = bid
	_check(torn < start, "the horde comes to the window and tears at it", "%s at %.0f of %.0f" % [weakest, torn, start])
	_check(not through_early, "and nobody passes it while it stands")

	id = weakest
	box = game.map.barricade_bounds(id)
	game.bash_barricade(id, 100000.0)
	await _sim(game, 0.3)
	_check(not bool(game.barricades[id]["intact"]) and not game.map.barricade_intact(id), "at nothing it breaks")
	var inside := 0
	for i in 16:
		await _sim(game, 0.5)
		inside = 0
		for npc in game.horde.spawner.npcs_of(&"test"):
			if npc.is_alive() and npc.position().z < box.position.z - 0.3:
				inside += 1
		if inside > 0:
			break
	_check(inside > 0, "and the horde comes through the gap", "%d inside" % inside)

	# Cleared, then mended from inside: E held on it, again and again.
	for npc in game.horde.spawner.all_npcs():
		if npc.is_alive():
			_hurt_npc(game, npc, 5000.0)
	await _sim(game, 0.5)
	me.place_at(Vector3(box.get_center().x, 0.05, box.position.z - 1.0), 0.0)
	_aim(me, box.get_center())
	_check(game.barricade_to_mend(me) >= 0, "a survivor at a broken window may mend it")
	for i in 8:
		me.actions = ZzNetCommand.ACT_USE
		await _sim(game, game.config.barricade_repair_seconds + 0.2)
		me.actions = 0
		await _sim(game, 0.1)
	var held: Dictionary = game.barricades[id]
	_check(bool(held["intact"]) and game.map.barricade_intact(id) and float(held["health"]) > float(held["max"]) * 0.5,
		"holding E rebuilds it and builds it back up", "%.0f of %.0f" % [float(held["health"]), float(held["max"])])
	_check(me.points > 0, "and mending is worth points", str(me.points))
	_finished()


## Stand-ins fill to the team a map is built for, and the horde's budget is sized for it.
func _test_team_size() -> void:
	_section("the team a map is built for")
	if not _linked:
		for i in 4:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _hold(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_high_school"]), 1, &"zz_high_school")
	_check(game.team_size() == 12, "the school is built for twelve", str(game.team_size()))
	_check(game.horde.spawner.limits.world_budget >= game.config.commons_cap(12), "and the horde's budget is a dozen's",
		"%d for a cap of %d" % [game.horde.spawner.limits.world_budget, game.config.commons_cap(12)])
	game.config.team_from_map = false
	_check(game.team_size() == game.config.minimum_players, "zz_team_from_map 0 keeps the server's own number")
	game.config.team_from_map = true
	var practice := ZzCatalogue.practice()
	_check(int(ZzMapDoc.validate(practice).value.get("survivors", -1)) == 0, "and a map that does not say leaves the server's number")
	_finished()


func _test_the_wire() -> void:
	_section("the hold and the barricades on the wire")
	var held := {"style": 1, "stage": 2, "index": 3, "count": 5, "left": 42.5, "remaining": -1, "twist": "swarm", "daylight": 0.0}
	var r := DotNetReader.new(ZzEvents.write_survival(held))
	var back := ZzEvents.read_survival(r)
	_check(bool(back["ok"]) and int(back["index"]) == 3 and int(back["count"]) == 5 and absf(float(back["left"]) - 42.5) < 0.1
		and str(back["twist"]) == "swarm" and int(back["remaining"]) == -1 and float(back["daylight"]) < 0.01,
		"SURVIVAL reads back what was written", str(back))
	held["left"] = -1.0
	held["remaining"] = 37
	held["daylight"] = -1.0
	back = ZzEvents.read_survival(DotNetReader.new(ZzEvents.write_survival(held)))
	_check(float(back["left"]) == -1.0 and int(back["remaining"]) == 37 and float(back["daylight"]) == -1.0,
		"including 'none' for a clock and the light", str(back))
	var bar := ZzEvents.read_barricade(DotNetReader.new(ZzEvents.write_barricade("gym_doors", 0.5, true)))
	_check(bool(bar["ok"]) and str(bar["id"]) == "gym_doors" and absf(float(bar["fraction"]) - 0.5) < 0.01 and bool(bar["intact"]),
		"BARRICADE too", str(bar))
	_check(ZzEvents.Kind.size() <= (1 << ZzEvent.KIND_BITS), "and both kinds fit the kind's bits", "%d kinds" % ZzEvents.Kind.size())
	_finished()


func _test_the_hud() -> void:
	_section("what the top of the screen says")
	var wave := ZzHud.survival_lines({"style": 0, "stage": DotNpcDirectorWaves.Stage.HORDE, "index": 3, "count": 10, "left": -1.0,
		"remaining": 42, "twist": "sprinters"})
	_check(wave[0] == "Wave 3 of 10 · Sprinters" and wave[1] == "42" and wave[2] == "left", "a wave: which, its twist, how many left", str(wave))
	var breather := ZzHud.survival_lines({"style": 0, "stage": DotNpcDirectorWaves.Stage.QUIET, "index": 4, "count": 10, "left": 24.0})
	_check(breather[0] == "Breather" and breather[1] == "0:24" and str(breather[2]).contains("wave 4") and str(breather[2]).contains("mend")
		and str(breather[3]) == "", "a breather: the clock to the next, the hint under it, nothing over it", str(breather))
	var night := ZzHud.survival_lines({"style": 1, "stage": DotNpcDirectorWaves.Stage.HORDE, "index": 2, "count": 5, "left": 100.0})
	_check(night[0] == "Night 2 of 5" and night[2] == "until dawn", "a night: until dawn", str(night))
	var last := ZzHud.survival_lines({"style": 0, "stage": DotNpcDirectorWaves.Stage.HORDE, "index": 10, "count": 10, "remaining": 3})
	_check(last[0] == "The last wave", "and the last wave says so", str(last))
	_finished()


## The map list (M) and the ballot list every survival map, with the team it is built for.
func _test_map_rows() -> void:
	_section("the map list has every survival map")
	var game := await _world(func(c: ZzConfig) -> void: c.map_ids = PackedStringArray())
	var rows := game.map_rows()
	var ids: Array = []
	var survival := 0
	for row: Dictionary in rows:
		ids.append(str(row["id"]))
		if str(row["mode"]) == "Survival":
			survival += 1
	var wanted: Array = BIG_MAPS if _linked else []
	var missing: Array = wanted.filter(func(id: String) -> bool: return not ids.has(id))
	_check(missing.is_empty(), "every big survival map is in it", "missing %s" % [missing])
	_check(not _linked or survival >= 6, "six survival maps or more", "%d" % survival)
	var school: Array = rows.filter(func(row: Dictionary) -> bool: return str(row["id"]) == "zz_high_school")
	_check(not _linked or (not school.is_empty() and str(school[0]["detail"]).contains("12 survivors")),
		"each row says the team it is built for", str(school))
	var exodus: Array = rows.filter(func(row: Dictionary) -> bool: return str(row["mode"]) == "Exodus")
	_check(not exodus.is_empty() and rows.filter(func(row: Dictionary) -> bool: return str(row["mode"]) == "Campaign").is_empty(),
		"and the old campaign mode is called Exodus", "%d exodus" % exodus.size())
	_finished()


# --- The big maps, played -----------------------------------------------------------------------

## A full team of stand-ins on one big map for a minute and a quarter of its first wave: it
## builds, its ground carries the horde from the edges to the barricades, the stand-ins hold
## their posts and fight, most of them are still standing, and a tick fits.
func _test_big_map(id: StringName) -> void:
	_section("%s: a wave, played" % id)
	if not _linked:
		for i in 6:
			_check(true, "skipped without maps/")
		_finished()
		return

	var started := Time.get_ticks_msec()
	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray([String(id)])
		c.survival_style = 0
		c.survival_warmup_seconds = 4.0
		c.wanderer_density = 0.3)
	var team := game.team_size()
	for i in team:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.is_bot = true
	game.start()
	await _sim(game, 0.1)
	var built_ms := Time.get_ticks_msec() - started
	_check(game.map.id() == id and game.horde.nav != null and game.horde.nav.point_count() > 2000,
		"it builds for %d, with its ground" % team, "%d nav points, %d ms to build and seat" % [
			game.horde.nav.point_count() if game.horde.nav != null else 0, built_ms])

	var ticks := 0
	var spent := 0
	var worst := 0
	var kills := 0
	var torn := 0
	var t := 0.0

	while t < PLAY_SECONDS:
		for i in 32:
			var before := Time.get_ticks_usec()
			game.simulate(TICK)
			var cost := Time.get_ticks_usec() - before
			spent += cost
			worst = maxi(worst, cost)
			ticks += 1
		t += 32.0 * TICK
		await get_tree().physics_frame

	for player in game.survivors():
		kills += player.commons_killed + player.specials_killed
	for bid: String in game.barricades:
		if float(game.barricades[bid]["health"]) < float(game.barricades[bid]["max"]) or not bool(game.barricades[bid]["intact"]):
			torn += 1

	var held := game.survival_state()
	# Wave 1 may already be over: since a wave down to its stragglers ends 30 s after its last
	# release (zz-survival-retune-1) the minute can reach the breather, where `sent` is zero.
	_check(int(held.get("index", 0)) >= 1 and (game.survival.waves.sent > 0 or game.survival.cleared >= 1),
		"the hold begins and wave 1 is released", str(held))
	_check(kills > 5, "the stand-ins kill what comes", "%d kills" % kills)
	_check(torn > 0 or kills > 20, "the horde reaches the barricades", "%d barricades hit, %d kills" % [torn, kills])

	var standing := 0
	var at_post := 0
	# In a breather a stand-in short of ammunition walks to a cache, so only standing counts
	# then: the camp's minute ended 2 s into wave 1's breather with four of ten at their posts.
	var in_breather: bool = game.survival != null and game.survival.waves != null \
		and game.survival.waves.stage == DotNpcDirectorWaves.Stage.QUIET
	for player in game.survivors():
		if player.is_up():
			standing += 1
			var post: Vector3 = game.bots._post_of(player)
			if Vector2(post.x - player.feet().x, post.z - player.feet().z).length() < 12.0 or in_breather:
				at_post += 1
	_check(standing >= int(ceil(team * 0.7)) and at_post >= int(ceil(standing * 0.5)),
		"most of the team is standing, most of them near their posts", "%d of %d up, %d near their post" % [standing, team, at_post])

	var mean := float(spent) / float(maxi(ticks, 1)) / 1000.0
	print("    %s: %d ticks, %.2f ms mean, %.1f ms worst, %d zombies at the end, %d nav points" % [
		id, ticks, mean, float(worst) / 1000.0, game.horde.count(), game.horde.nav.point_count()])
	_check(mean < 1000.0 / float(TICK_RATE), "a tick fits in a 64 Hz server's budget", "%.2f ms mean, %.1f worst" % [mean, float(worst) / 1000.0])
	await _dispose(game)
	_finished()


# --- Helpers -------------------------------------------------------------------------------------

## A survival world with [param count] invulnerable survivors standing in it. The practice street
## made a survival map (with two caches) unless [param map] names one.
func _hold(configure: Callable, count: int, map: StringName = &"") -> ZzGame:
	var game := await _world(func(c: ZzConfig) -> void:
		c.wanderer_density = 0.0
		c.sleepers_enabled = false
		c.specials_base = 0
		configure.call(c))

	if map == &"":
		var doc := ZzCatalogue.practice().duplicate(true)
		doc["id"] = "zz_hold"
		doc["mode"] = ZzMapDoc.SURVIVAL
		doc["objectives"] = []
		doc["caches"] = [[-2.0, 0.0, 10.0], [2.0, 0.0, 10.0]]
		var checked := ZzMapDoc.validate(doc)
		var _added := game.catalogue._add(checked.value, "test") if checked.ok else false
		game.next_map_id = &"zz_hold"
	else:
		game.next_map_id = map

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Holder%d" % i)
		player.health.invulnerable = true

	game.start()
	await _sim(game, 0.3)

	for player in game.survivors():
		player.health.invulnerable = true
		if map == &"":
			player.place_at(STREET + Vector3(float(player.get_index() % 3), 0.0, 0.0), 0.0)

	return game


## Kills the wave in play until wave [param index] is over.
func _clear_wave(game: ZzGame, index: int) -> void:
	for i in 400:
		if game.survival == null or game.survival.waves.index > index or game.survival.waves.stage == DotNpcDirectorWaves.Stage.DONE:
			return
		if game.survival.waves.stage == DotNpcDirectorWaves.Stage.QUIET and game.survival.waves.index > index:
			return
		for npc in game.horde.spawner.npcs_of(game.horde.WAVE):
			if npc.is_alive():
				_hurt_npc(game, npc, 5000.0)
		await _sim(game, 0.25)


func _won_with(words: String) -> bool:
	return _result.size() == 2 and bool(_result[0]) and str(_result[1]).contains(words)


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
	_result = []
	game.round_over.connect(func(_number: int, won: bool, why: String) -> void: _result = [won, why])
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


func _aim(player: ZzPlayer, target: Vector3) -> void:
	var look := target - player.eye_position()
	var command := DotFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	player.controller.apply_command(command)
	player.controller.state.yaw = command.yaw
	player.controller.state.pitch = command.pitch


func _hurt(game: ZzGame, player: ZzPlayer, amount: float) -> void:
	var hit := DotDamage.make(0, player.entity_id, amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _hurt_npc(game: ZzGame, npc: DotNpcInstance, amount: float) -> void:
	var hit := DotDamage.make(0, game.horde.entity_id_for(npc), amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


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
