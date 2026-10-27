extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzNavGraph := preload("../game/zz_nav_graph.gd")
const ZzNavNotes := preload("../game/zz_nav_notes.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const StuckMeter := preload("../tools/stuck_meter.gd")
const ZzUnstick := preload("../game/zz_unstick.gd")

## The annotations in use: where the stand-ins stand before a wave, where the horde goes, and the
## graph's one-way drops. Every check that compares a behaviour with the old one runs both (the
## cvars `zz_bot_hold_chokes` and `zz_zombie_spread` off are the old behaviour) and fails if the
## new one is not better: armed, so a bot that goes back to its post at a window turns this red.
##
## Counts sections and checks (dot-settings' story).

## Without the per-map wave-origin sections (one section, two checks each).
const SECTIONS := 21
const CHECKS := 94

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

## Maps held to a stuck band, each once a worst case: blackout_2 had a 108 s wedge on a pallet, lot and
## high_school wedged stand-ins on a low prop. The bands
## because two runs of one map differ; they catch a return to those numbers, not a 1% drift.
const STUCK_BANDS := ["zz_blackout_2", "zz_lot", "zz_high_school"]
const STANDIN_BAND := 0.15
const COMMON_BAND := 0.10
## Stand-in goal time is 40 to 140 s of a 150 s run on a held lot (same spread before the blood
## migration: 1 run in 8 and 2 in 12 were over 15%), so the ratio is taken over at least this much.
const STANDIN_MIN_GOAL := 200.0
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

		# `--only=stuck_survival`: every survival map in maps/, however it got there (the manor, ze_potc).
		if only == "stuck_survival":
			ids = _survival_maps()

		for id: String in ids:
			var meter: StuckMeter = await _stuck(StringName(id))
			print("STUCK %-24s %s" % [id, meter.line()])
			print("      rescue: %s" % meter.rescue)
			for kind: StringName in StuckMeter.KINDS:
				print("      %s worst cells %s" % [kind, meter.worst_cells(kind)])
			for line in meter.cases.slice(0, 8):
				print("      case %s" % line)
			for block in meter.captures:
				print(block)

		get_tree().quit(0)
		return

	if only == "wave":
		await _test_wave_origins()
		print("%d passed, %d failed" % [_passed, _failed])
		for line in _failures:
			print("  FAIL  %s" % line)
		get_tree().quit(_failed)
		return

	if only == "mend":
		await _test_mend_gap()
		get_tree().quit(0)
		return

	if only == "thin":
		_test_thin_props()
		print("%d passed, %d failed" % [_passed, _failed])
		for line in _failures:
			print("  FAIL  %s" % line)
		get_tree().quit(_failed)
		return

	if only == "wedge":
		await _test_hop_wedge()
		await _test_unstick_steps()
		print("%d passed, %d failed" % [_passed, _failed])
		for line in _failures:
			print("  FAIL  %s" % line)
		get_tree().quit(_failed)
		return

	if only == "steps":
		await _test_unstick_steps()
		print("%d passed, %d failed" % [_passed, _failed])
		for line in _failures:
			print("  FAIL  %s" % line)
		get_tree().quit(_failed)
		return

	if only == "lure":
		await _test_lure_crowd()
		print("%d passed, %d failed" % [_passed, _failed])
		for line in _failures:
			print("  FAIL  %s" % line)
		get_tree().quit(_failed)
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
	await _test_async_build()
	await _test_mend_gap()

	for id: String in STUCK_BANDS:
		await _test_stuck(StringName(id))

	await _test_hop_wedge()
	await _test_unstick_steps()
	await _test_lure_crowd()
	_test_thin_props()
	await _test_wave_origins()

	print("")
	print("%d sections entered, %d finished" % [_sections_entered, _sections_finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _sections_entered != _sections_finished or _sections_entered != SECTIONS + _wave_maps():
		print("ERROR: %d of %d sections finished, %d expected." % [_sections_finished, _sections_entered, SECTIONS])
		code = 1

	if _passed + _failed != CHECKS + 2 * _wave_maps():
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS + 2 * _wave_maps()])
		code = 1

	for game in _worlds.duplicate():
		await _dispose(game)

	get_tree().quit(code)


# --- The graph built off the frame ---------------------------------------------------------------

const ASYNC_MAP := "zm_chaos_city"

## The same graph three ways: on this thread, on worker tasks while frames go by, and in slices of a
## frame's time. Every way must give the same points, edges and cover, the progress must only rise to 1,
## and the frames must have run during the build (the point of doing it off the frame).
func _test_async_build() -> void:
	_section("the graph built off the frame is the graph built at once")
	var path := "res://maps/%s.json" % ASYNC_MAP

	if not _linked or not FileAccess.file_exists(path):
		for i in 12:
			_check(true, "skipped without maps/")
		_finished()
		return

	var doc: Dictionary = ZzMapDoc.parse_json(FileAccess.get_file_as_string(path), path).value
	var started := Time.get_ticks_msec()
	var sync := ZzNpcs.nav_for(doc, Callable())
	var sync_ms := Time.get_ticks_msec() - started

	for mode in ["threads", "slices"]:
		var job := ZzNpcs.nav_job(doc, Callable(), PackedStringArray(), [], false, mode == "threads")
		job.workers = 3
		var frames := 0
		var rises := true
		var last := 0.0
		var stages := {}
		started = Time.get_ticks_msec()

		if mode == "threads":
			job.start_thread()

		while not job.advance(4.0):
			await get_tree().process_frame
			frames += 1
			var now := job.progress()
			rises = rises and now >= last
			last = now
			stages[job.stage()] = true

		var took := Time.get_ticks_msec() - started
		var built := job.nav
		var same := built != null and built.source_digest == sync.source_digest and built.points == sync.points \
			and built.edges == sync.edges and built.cover_positions == sync.cover_positions \
			and built.cover_normals == sync.cover_normals and built.flags == sync.flags
		_check(same, "%s: same digest, points, edges, cover and flags as the build at once" % mode,
			"%d points, %d edges, %d cover" % [sync.point_count(), sync.edge_count(), sync.cover_positions.size()])
		_check(rises and job.progress() == 1.0, "%s: progress only rises, and ends at 1.0" % mode,
			"passes seen %s" % [stages.keys()])
		_check(frames >= 2, "%s: the main loop ran %d frames during the build" % [mode, frames],
			"%d ms against %d ms at once" % [took, sync_ms])
		_check(job.nav != null and job.is_done(), "%s: the job reports done" % mode)

	# A gate rebuild while a build runs: the older job is dropped without a trace.
	var stale := ZzNpcs.nav_job(doc, Callable(), PackedStringArray(), [], false, true)
	stale.start_thread()
	stale.cancel()
	_check(stale.nav == null, "a cancelled build leaves no graph")
	var warned := ZzNpcs.nav_job(doc, Callable(), PackedStringArray(["no-such-gate"]), [], false, false)
	_check(warned.run_blocking().point_count() == sync.point_count(), "a gate that is not there changes nothing")
	_check(not warned.from_cache, "an uncached build says so")
	_check(sync.point_count() > 100, "the map has a graph to compare")
	_finished()


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

	var cached := DotNpcNavData.from_cache_bytes(data.to_cache_bytes())
	_check(cached != null and cached.matches("test"), "a graph survives the cache to the byte's digest")
	_check(cached != null and cached.points == data.points and cached.edges == data.edges, "with its points and edges whole")
	_check(DotNpcNavData.from_cache_bytes(PackedByteArray([1, 2, 3])) == null, "and garbage bytes are no graph")

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

## A team of stand-ins plays [param id] against its horde for [constant STUCK_SECONDS] (`--stuck-seconds=` to hunt a rare snag), and a
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
	var seconds := STUCK_SECONDS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stuck-seconds="):
			seconds = float(arg.substr(16))
	var ticks := int(seconds * float(TICK_RATE))

	for i in ticks:
		game.simulate(TICK)
		meter.sample()

		if i % 8 == 7:
			await get_tree().physics_frame

	meter.rescue = str(game.horde.describe().get("stuck", "-")) if game.horde != null else "-"
	await _dispose(game)
	return meter


func _test_stuck(id: StringName) -> void:
	_section("%s: movers with a goal do not stand still" % id)
	var meter: StuckMeter = await _stuck(id)
	var detail := meter.line()
	for block in meter.captures:
		print(block)
	_check(meter.ratio(&"standin", STANDIN_MIN_GOAL) <= STANDIN_BAND, "stand-ins are stuck under %d%% of their goal time" % int(STANDIN_BAND * 100.0), detail)
	_check(meter.ratio(&"common") <= COMMON_BAND, "commons are stuck under %d%% of their goal time" % int(COMMON_BAND * 100.0), detail)
	_check(maxf(meter.longest[&"standin"], meter.longest[&"common"]) <= LONGEST_BAND, "no mover is stuck longer than %.0f s" % LONGEST_BAND, detail)
	_finished()


# --- Mending round a body -----------------------------------------------------------------------

## Every survival map the game has, by its document's file name (the id).
func _survival_maps() -> Array[StringName]:
	var out: Array[StringName] = []
	var dir := ProjectSettings.globalize_path("res://maps")

	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".json"):
			continue

		var doc = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))

		if doc is Dictionary and str(doc.get("mode", "")) == "survival":
			out.append(StringName(file.get_basename()))

	out.sort()
	return out


func _wave_maps() -> int:
	return _survival_maps().size()


func _test_wave_origins() -> void:
	for id in _survival_maps():
		await _test_wave_origin(id)


## A survival wave has somewhere to come from, even on a map all start area (zs_goth_house's
## hints sit beside the team and its graph is one room): with no origin the wave never came.
func _test_wave_origin(id: StringName) -> void:
	_section("%s: a wave has an origin and queues" % id)
	if not _linked:
		for i in 2:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray([String(id)])
		c.survival_warmup_seconds = 300.0
		c.wanderer_density = 0.0)

	for i in maxi(game.team_size(), TEAM):
		var p := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		p.is_bot = true

	game.start()

	for i in 64 * 25:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	var horde = game.horde
	var origin: Vector3 = horde._wave_origin()
	_check(origin != Vector3.INF, "a wave origin is found", "%d spawn points" % horde.director.spawn_points.size())
	_check(horde.spawn_wave(8) == 8 and horde.pending_commons() >= 8, "a wave of 8 is queued", "%d pending" % horde.pending_commons())
	_finished()
	await _dispose(game)


func _test_mend_gap() -> void:
	_section("a survivor standing in a broken barricade's gap is not walled in by the mend")
	if not _linked:
		for i in 3:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_high_school"])
		c.survival_warmup_seconds = 300.0
		c.wanderer_density = 0.0)
	var p := game.add_player(&"u1", "Human")
	p.health.invulnerable = true
	game.start()
	game.simulate(2.0)
	await get_tree().physics_frame
	var id := str((game.map_doc["barricades"] as Array)[0]["id"])
	game.bash_barricade(id, 1.0e9)
	await get_tree().physics_frame
	var box := game.map.barricade_bounds(id)
	(game.barricades[id] as Dictionary)["torn_at"] = -INF
	p.place_at(Vector3(box.get_center().x, box.position.y + 0.05, box.get_center().z), 0.0)
	await get_tree().physics_frame
	_check(not game.barricades[id]["intact"], "the barricade is down", id)
	_check(game.mend_barricade(0, null), "it is mended")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var thin := (p.feet().z - box.get_center().z) if box.size.x > box.size.z else (p.feet().x - box.get_center().x)
	var half := minf(box.size.x, box.size.z) * 0.5
	_check(absf(thin) >= half + 0.4, "the survivor is out of the boards, a body's width clear", "%.2f from the middle of a %.2f board" % [absf(thin), half * 2.0])
	var inb := game.map.bounds()
	_check(p.feet().x >= inb.position.x and p.feet().x <= inb.end.x and p.feet().z >= inb.position.z and p.feet().z <= inb.end.z, "and inside the map", str(p.feet()))
	# A wall 0.3 m beyond the near side must send them to the other side, never into it.
	var across_x := box.size.x < box.size.z
	var wall := StaticBody3D.new()
	wall.collision_layer = game.world_mask()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(box.size.x + 6.0, 3.0, box.size.z + 6.0)
	if across_x:
		bs.size.x = 1.0
	else:
		bs.size.z = 1.0
	shape.shape = bs
	wall.add_child(shape)
	game.add_child(wall)
	var c := box.get_center()
	var inside_at := Vector3(c.x, box.position.y + 0.05, c.z)
	if across_x:
		wall.global_position = Vector3(box.end.x + 0.3 + 0.5, box.position.y + 1.0, c.z)
		inside_at.x = box.end.x - 0.05
	else:
		wall.global_position = Vector3(c.x, box.position.y + 1.0, box.end.z + 0.3 + 0.5)
		inside_at.z = box.end.z - 0.05
	await get_tree().physics_frame
	await get_tree().physics_frame
	var out := game._gap_exit(box, inside_at, across_x)
	var side := (out.x if across_x else out.z)
	var lo := box.position.x if across_x else box.position.z
	_check(out.is_finite() and side < lo, "a wall 0.3 m beyond the near side sends them to the far side", "%s from %s" % [out, inside_at])
	wall.free()
	_finished()


## The lot's leaning door panel (0.22 x 1.26 m, turned 147 degrees) used to close the whole corner of the
## doorway in one box, and a stand-in beside it stood in the cut with no line to the graph.
func _test_thin_props() -> void:
	_section("a turned thin prop is cut by its length, not its corners")
	var size := Vector3(0.22, 1.4, 1.26)
	var at := Vector3(0.458, 0.0, -5.205)
	var boxes := ZzNpcs.prop_obstacles(at, 147.503, size)
	var area := 0.0
	var inside := false

	for box in boxes:
		area += box.size.x * box.size.z
		inside = inside or Rect2(box.position.x, box.position.z, box.size.x, box.size.z).has_point(Vector2(0.8, -4.8))

	var one := ZzNpcs.prop_obstacles(at, 90.0, size)
	_check(boxes.size() >= 3 and area < 0.6, "it is several boxes covering well under the corner box", "%d boxes, %.2f m2 (the corner box is 0.83)" % [boxes.size(), area])
	_check(not inside, "the doorway beside it is not cut", "(0.8, -4.8)")
	_check(one.size() == 1 and absf(one[0].size.x - 1.26) < 0.01, "a prop square to the grid stays one box", "%s" % one)
	var ends := true

	for end in [Vector3(0.12, 0.0, -4.67), Vector3(0.8, 0.0, -5.74)]:
		var covered := false

		for box in boxes:
			covered = covered or box.grow(0.02).has_point(end + Vector3(0.0, 0.5, 0.0))

		ends = ends and covered

	_check(ends, "both ends of the panel are still cut", "")
	_finished()


## [where the common stood, where its quarry stood] for two snags the stuck meter caught (18 s, 124 s).
const WEDGES := [[Vector3(29.84, 0.0, -24.84), Vector3(21.6, 0.2, -2.0)], [Vector3(41.34, 0.0, 13.92), Vector3(24.0, 0.2, 14.3)]]

## The 30 s snags the stuck meter caught on the school: a common heading past a corner its path cut
## hopped on the spot for ever, and every hop read as progress to the brain's go-rough watch and
## reset the game's unstick watchdog, so neither remedy ever ran.
func _test_hop_wedge() -> void:
	_section("commons hopping against a corner their path cut are still seen as stuck and get round it")
	if not _linked:
		for i in WEDGES.size() + 1:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_high_school"])
		c.survival_warmup_seconds = 600.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false)
	var quarries: Array = []
	for i in WEDGES.size():
		var p := game.add_player(StringName("u%d" % (100 + i)), "Quarry%d" % i)
		p.health.invulnerable = true
		quarries.append(p)
	game.start()
	var ticks := 0

	while game.horde.notes.state < ZzNavNotes.State.READY and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	var npcs: Array = []
	var furthest: Array[float] = []
	for i in WEDGES.size():
		quarries[i].place_at(WEDGES[i][1], 0.0)
		var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, WEDGES[i][0], &"test")
		npc.brain.call(&"force_target", StringName("u%d" % (100 + i)))
		npcs.append(npc)
		furthest.append(0.0)

	for step in 30:
		await _sim(game, 0.5)
		for i in npcs.size():
			var npc: DotNpcInstance = npcs[i]
			if npc.is_alive():
				var start: Vector3 = WEDGES[i][0]
				furthest[i] = maxf(furthest[i], Vector2(npc.position().x - start.x, npc.position().z - start.z).length())

	for i in npcs.size():
		var npc: DotNpcInstance = npcs[i]
		var remedies: PackedStringArray = npc.brain.get(&"unstick_log") if npc.is_alive() else PackedStringArray()
		var detail := "from %s furthest %.1f m, remedies [%s]" % [WEDGES[i][0], furthest[i], ", ".join(remedies)]
		_check(npc.is_alive() and furthest[i] > 3.0, "the common caught at %s gets 3 m clear within 15 s" % WEDGES[i][0], detail)

	# The hop itself zeroes wish; the watchdog must pause through it, not start again.
	var hopper: DotNpcInstance = npcs[0]
	var watched: Object = hopper.brain
	var hop_body: Object = watched.call(&"body")
	watched.set(&"bashing", false)
	watched.set(&"_watch_at", hopper.position())
	watched.set(&"_watch_for", 2.0)
	hop_body.set(&"wish", Vector3(3.0, 0.0, 0.0))
	hop_body.call(&"leap", Vector3(0.0, 7.0, 0.0))
	watched.call(&"_unstick_watch", 0.1)
	_check(is_equal_approx(float(watched.get(&"_watch_for")), 2.0), "a hop pauses the unstick watchdog instead of restarting it",
		"watched %.2f s at %s" % [float(watched.get(&"_watch_for")), watched.get(&"_watch_at")])

	await _dispose(game)
	_finished()


## Where a brute stood wedged among the school's furniture for 36 s (its goal was behind it).
const BRUTE_CORNER := Vector3(17.73, 0.02, 8.08)

## The last-resort steps: a brute wedged among furniture with its goal behind the furniture is
## stepped out (it was left in place, 36 s), and a stand-in's step is its controller's, not the
## node's (the node is copied from the controller every tick, so the step was undone at once).
func _test_unstick_steps() -> void:
	_section("a wedged brute is stepped out, a stand-in's step sticks and its path keeps off the door frames")
	if not _linked:
		for i in 9:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_high_school"])
		c.survival_warmup_seconds = 600.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false)
	var quarry := game.add_player(&"u100", "Quarry")
	game.start()
	var ticks := 0

	while game.horde.notes.state < ZzNavNotes.State.READY and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	var graph_size: int = game.horde.spawner.nav.data.points.size()
	_check(game.horde.narrow_points > 0 and game.horde.narrow_points < graph_size / 4, "the points a brute does not fit at are flagged, not the whole map",
		"%d of %d" % [game.horde.narrow_points, graph_size])
	_check(game.horde.spawner.catalogue.get_npc(ZzNpcs.BRUTE).nav_exclude_flags & game.horde.spawner.nav.NARROW != 0, "and the brute's paths keep off them")
	var brute := game.horde.spawner.spawn(ZzNpcs.BRUTE, BRUTE_CORNER, &"test")
	await _sim(game, 0.5)
	var body: CharacterBody3D = brute.brain.call(&"body")
	var start := body.global_position

	for goal: Vector3 in [Vector3(17.5, 0.0, 8.6), Vector3(25.0, 0.0, 8.0)]:
		var moved := ZzUnstick.relocate(body, goal, true)
		var went := body.global_position.distance_to(start)
		_check(moved and went > 1.4 and went < 4.0, "relocate frees the brute even with its goal behind the furniture (%s)" % goal,
			"moved %s, %.1f m from %s" % [moved, went, start])
		body.global_position = start

	body.global_position = start

	await _sim(game, 0.2)
	var from := quarry.feet()
	var stepped := false

	for heading: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]:
		if ZzUnstick.nudge_player(quarry, heading, 0.0):
			stepped = true
			break

	var at_once := quarry.feet().distance_to(from)
	game.simulate(TICK)
	var after := quarry.feet().distance_to(from)
	_check(stepped and at_once > 0.5, "a survivor's nudge moves its controller", "moved %.2f m" % at_once)
	_check(after > 0.5, "and a tick later it is still there", "%.2f m from %s" % [after, from])

	# Where stand-ins stood 100 s and 15 s on the school: smoothing cut across the corner of a door
	# frame, so the first legs of their path ran through the wall.
	var nav: DotNpcNavGraph = game.horde.spawner.nav
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state

	for pair: Array in [[Vector3(-4.57, 0.0, 4.35), Vector3(39.6, 0.0, -9.8)], [Vector3(6.35, 0.0, 3.73), Vector3(-39.4, 0.0, -10.3)]]:
		var kept = nav.filter
		nav.filter = nav.bot_filter
		var path := nav.find_smooth_path(pair[0], pair[1], 2.5, true)
		nav.filter = kept
		var sphere := SphereShape3D.new()
		sphere.radius = 0.25
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = sphere
		query.collision_mask = game.world_mask() | game.ground_mask()
		var prev: Vector3 = pair[0]
		var blocked := PackedStringArray()

		for pt: Vector3 in path.slice(1, 5):
			query.transform = Transform3D(Basis.IDENTITY, prev + Vector3(0.0, 0.6, 0.0))
			query.motion = pt - prev
			var fractions := space.cast_motion(query)

			if fractions[0] < 0.999:
				blocked.append("%s to %s" % [prev.snappedf(0.1), pt.snappedf(0.1)])

			prev = pt

		_check(blocked.is_empty(), "a stand-in's path from %s keeps clear of the door frame" % pair[0], "legs through the wall: %s" % ", ".join(blocked))

	await _dispose(game)
	_finished()


## A lure draws a crowd to a place, and each stops at its own ring: not twenty on one spot.
func _test_lure_crowd() -> void:
	_section("a lured crowd spreads round the lure instead of piling on it")
	if not _linked:
		for i in 3:
			_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_blackout_2"])
		c.survival_warmup_seconds = 10.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false)
	var _p := game.add_player(&"u100", "Watcher")
	game.start()
	var ticks := 0

	while game.horde.notes.state < ZzNavNotes.State.READY and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	var at := Vector3(1.6, 0.0, 50.1)

	for i in 20:
		var _npc := game.horde.spawner.spawn(ZzNpcs.COMMON, game.horde.nav.snap(at + Vector3(-12.0 + float(i % 5) * 1.5, 0.0, -10.0 - float(i / 5) * 1.5), 2.5), &"test")

	await _sim(game, 6.0)
	game.horde.lure(at, 40.0, 60.0)
	await _sim(game, 25.0)
	var gaps: Array[float] = []
	var states := {}

	for npc: DotNpcInstance in game.horde.spawner.all_npcs():
		var st := str(npc.brain.get(&"state")) if npc.brain != null else "-"
		states[st] = int(states.get(st, 0)) + 1
		if npc.brain != null and npc.brain.get(&"state") == &"lure" and npc.brain.call(&"at_lure"):
			gaps.append(Vector2(npc.position().x - at.x, npc.position().z - at.z).length())

	gaps.sort()
	var detail := "%d arrived of %s, gaps %s" % [gaps.size(), states, gaps.map(func(g: float) -> float: return snappedf(g, 0.1))]
	_check(gaps.size() >= 8, "most of the crowd reaches the lure", detail)
	_check(not gaps.is_empty() and gaps[gaps.size() - 1] - gaps[0] >= 0.6, "they stop at different distances from it", detail)
	_check(not gaps.is_empty() and gaps[gaps.size() / 2] >= 1.5, "the median one stands off the spot itself", detail)
	await _dispose(game)
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
	config.common_speed_scaling = false  # timed against the old running pace
	config.escape_grace_seconds = 0.0

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
