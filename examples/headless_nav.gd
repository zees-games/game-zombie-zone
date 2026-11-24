extends "headless_nav_mend.gd"

## The annotations in use: where the stand-ins stand before a wave, where the horde goes, and the
## graph's one-way drops. Every check that compares a behaviour with the old one runs both (the
## cvars `zz_bot_hold_chokes` and `zz_zombie_spread` off are the old behaviour) and fails if the
## new one is not better: armed, so a bot that goes back to its post at a window turns this red.
##
## Counts sections and checks (gs-settings' story).

## The suite is three scenes over this script, one per `shard` (game.sh caps a suite at 1200 s):
## headless_nav (core), headless_nav_holds and headless_nav_waves, which has one section and two
## checks per survival map, dealt round-robin into game.sh's shards `w0`..`w<WAVE_SHARDS-1>`.
@export var shard := "core"

## game.sh's SUITE_SHARDS for headless_nav_waves names exactly these.
const WAVE_SHARDS := 6
const CORE_SECTIONS := 15
const CORE_CHECKS := 87
const HOLDS_SECTIONS := 10
const HOLDS_CHECKS := 40


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone navigation notes")
	print("")
	_linked = DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://maps")) and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://world"))

	# Development only: `-- --only=spread` runs the sections whose name has it (counts then skipped).
	var only := ""

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)

	if await _dev_only(only):
		return

	if shard == "waves" and GSGameShardArgs.is_merge():
		_merge_waves(GSGameShardArgs.merge_logs())
		return

	var waves_played: Array[StringName] = []
	match shard:
		"holds":
			for id: String in MAPS:
				await _test_holding(StringName(id))

			for id: String in STUCK_BANDS:
				await _test_stuck(StringName(id))
		"waves":
			var part := GSGameShardArgs.shard()
			if part != "" and not part in _wave_shard_names():
				push_error("headless_nav_waves: unknown shard %s (have %s)" % [part, _wave_shard_names()])
				get_tree().quit(1)
				return
			waves_played.assign(GSGameShardArgs.slice(_survival_maps(), part, WAVE_SHARDS, "w"))
			for id in waves_played:
				await _test_wave_origin(id)
		_:
			_test_graph()
			await _test_exodus()
			await _test_fallback()
			await _test_spread(&"zz_high_school")
			await _test_spread(&"zz_mall")
			await _test_repeatable()
			await _test_async_build()
			await _test_mend_gap()
			await _test_hop_wedge()
			await _test_ladder_climb()
			await _test_unstick_steps()
			await _test_lure_crowd()
			_test_thin_props()
			_test_ladder_seed()
			_test_island_scan()

	for game in _worlds.duplicate():
		await _dispose(game)

	match shard:
		"holds":
			_report_sections(_sections_entered, _sections_finished, HOLDS_SECTIONS, HOLDS_CHECKS)
		"waves":
			_report_sections(_sections_entered, _sections_finished, waves_played.size(), 2 * waves_played.size())
		_:
			_report_sections(_sections_entered, _sections_finished, CORE_SECTIONS, CORE_CHECKS)


# The graph built off the frame

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


# The graph

## Four points high and four low, a drop between: a zombie goes down it, never up, a stand-in
## does neither, and a climbing zombie goes both ways.
func _test_graph() -> void:
	_section("the graph: drops are one way and the zombies' alone")
	var data := GSNpcNavData.new()
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

	var cached := GSNpcNavData.from_cache_bytes(data.to_cache_bytes())
	_check(cached != null and cached.matches("test"), "a graph survives the cache to the byte's digest")
	_check(cached != null and cached.points == data.points and cached.edges == data.edges, "with its points and edges whole")
	_check(GSNpcNavData.from_cache_bytes(PackedByteArray([1, 2, 3])) == null, "and garbage bytes are no graph")
	_check_cache_key()

	_check_thinned_spawns()

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
	graph.allow_climb = false
	_check_ladder_link(data, low, high)
	_check_one_way()
	_finished()


## The cache holds the graph AFTER the physics pass cut it, so what that pass collides with is part of the key: a map
## whose colliding hulls changed (a never-solid brush taken out of a doorway) must not load its old cuts.
func _check_cache_key() -> void:
	var keyed := {"id": "key_test", "world": "zz_world_key_test", "world_collision": {"models": [1, 2], "flat": []}, "solid_props": [[0.0, 1.0, 0.0, 1.0, 2.0, 1.0, 0.0]]}
	var fewer := keyed.duplicate(true)
	fewer["world_collision"]["models"] = [1]
	var no_prop := keyed.duplicate(true)
	no_prop["solid_props"] = []
	_check(ZzNpcs.digest_of(keyed) == ZzNpcs.digest_of(keyed.duplicate(true)), "the same document keys the same cache")
	_check(ZzNpcs.digest_of(keyed) != ZzNpcs.digest_of(fewer), "a change of the colliding world hulls is another cache")
	_check(ZzNpcs.digest_of(keyed) != ZzNpcs.digest_of(no_prop), "and so is a change of the solid props")


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


# Holding

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
	_check(on["share"] >= 0.75, "most stand-ins stand at a choke before the wave", "%.2f within %.0f m (m to the nearest choke: %s)" % [on["share"], NEAR, on["dists"]])
	_check(on["share"] >= off["share"] + 0.25 or (off["share"] >= 0.9 and on["share"] >= off["share"]), "which the posts alone did not do (a post already at a choke is allowed to stay)",
		"%.2f against %.2f at their posts (%s)" % [on["share"], off["share"], off["dists"]])
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

	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	await _sim(game, SETTLE)
	var notes: ZzNavNotes = game.horde.notes
	var near := 0
	var total := 0
	var held := {}
	var dists := PackedStringArray()

	for p in game.survivors():
		if not p.is_bot:
			continue

		total += 1
		var best := INF

		for i in notes.chokes.size():
			var at: Vector3 = notes.chokes[i]["at"]
			best = minf(best, Vector2(at.x - p.feet().x, at.z - p.feet().z).length())

		dists.append("%.1f" % best)
		if best > NEAR:
			continue

		near += 1

		held[_held_choke(notes, p)] = true

	# Chokes whose places to stand coincide (two on one route can share the one behind them) are one
	# place to hold, and a spread cannot be asked of fewer places than there are.
	var places := {}

	for c in notes.chokes:
		var spot: Vector3 = c["hold"] if c["hold"] != Vector3.INF else c["at"]
		places[Vector2i(roundi(spot.x / 2.0), roundi(spot.z / 2.0))] = true

	var out := {
		"places": places.size(), "ready": notes.is_ready(), "chokes": notes.chokes.size(), "found": notes.all_chokes.size(),
		"share": float(near) / float(maxi(total, 1)), "distinct": held.size(),
		"bake": notes.bake_ms, "annotate": notes.annotate_ms, "dists": ", ".join(dists),
	}
	await _dispose(game)
	return out


# Stuck

## A team of stand-ins plays [param id] against its horde for [constant STUCK_SECONDS] (`--stuck-seconds=` to hunt a rare snag), and a
## [StuckMeter] says how long movers with a goal stood still.


## Which choke it holds is the one whose place to stand (`hold`, a few metres behind the
## choke) is nearest it, not the one whose choke is: on a street where two chokes are a few
## metres apart a bot standing behind one is nearer the other's choke, and the count then
## flipped between runs on where each stand-in had got to.
func _held_choke(notes: ZzNavNotes, p) -> int:
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

	return mine


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
	meter.freeze()
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
	_check(meter.watch_ratio(&"common") <= COMMON_BAND, "the shared watch agrees: commons are stuck under %d%% of their goal time" % int(COMMON_BAND * 100.0), detail)
	_check(maxf(meter.longest[&"standin"], meter.longest[&"common"]) <= LONGEST_BAND, "no mover is stuck longer than %.0f s" % LONGEST_BAND, detail)
	_finished()


# Falling back

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

	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	# The plan (routes, chokes, narrow points) runs the tick after the annotations arrive.
	game.simulate(TICK)

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


# The horde

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


const REPEAT_TICKS := 2000


## sv_threads_npc's promise: the same seed gives the same horde, and worker threads change nothing.
## The horde sets gs-npc's deferred_paths (ZzHorde.setup): every repath is queued and answered
## after every brain has thought, at 0 path workers too, so path workers 0 and 2 agree.
func _test_repeatable() -> void:
	_section("a seeded horde is the same horde twice, and with npc workers")
	if not _linked:
		for i in 5:
			_check(true, "skipped without maps/")
		_finished()
		return

	var verify_before := GSParallel.verify
	var failures_before := GSParallel.verify_failures
	var off: Array = await _repeat_run(0, 0)
	var off_again: Array = await _repeat_run(0, 0)
	GSParallel.verify = true
	var on: Array = await _repeat_run(2, 0)
	var queued: Array = await _repeat_run(2, 2)
	GSParallel.verify = verify_before
	var line := "off %s, off %s, sense+think workers 2 %s, and path workers 2 %s" % [off, off_again, on, queued]
	var threads := "" if GSParallel.resolve_workers(2) > 0 else " (no threads here: inline)"
	_check(off[1] > 0 and off[2] > 0, "the hash covers a horde that moved and searched paths", line)
	_check(off[0] == off_again[0], "off against off: the same hash of %d ticks" % REPEAT_TICKS, line)
	_check(on[0] == off[0], "sense and think workers 2 against off: the same hash", line + threads)
	_check(queued[0] == off[0] and queued[2] == off[2] and queued[2] > 0,
		"sense, think and path workers 2 against off: the same hash and searches", line + threads)
	_check(GSParallel.verify_failures == failures_before, "and verify found no task that differs between runs",
		"%d failures" % (GSParallel.verify_failures - failures_before))
	_finished()


## [hash of every NPC's id, target, state and position each tick, NPC-ticks seen, path searches].
## Nav notes are off: their annotation is sliced by wall time, so its arrival tick is not repeatable.
func _repeat_run(workers: int, path_workers: int) -> Array:
	seed(4402)
	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_high_school"])
		c.survival_style = 0
		c.survival_warmup_seconds = 2.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false
		c.nav_notes = false
		c.seed_value = 4402)

	for i in 4:
		var p := game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		p.is_bot = false
		p.health.invulnerable = true

	game.start()
	var spawner: GSNpcSpawner = game.horde.spawner
	spawner.sense_workers = workers
	spawner.path_workers = path_workers
	spawner.think_workers = workers
	var h := 0
	var seen := 0

	for t in REPEAT_TICKS:
		game.simulate(TICK)
		for npc in spawner.all_npcs():
			var brain: Object = npc.brain
			var state: Variant = brain.get(&"state") if brain != null else null
			var at := npc.position()
			h = hash([h, npc.seed, npc.target_id, state, snappedf(at.x, 0.001), snappedf(at.z, 0.001)])
			seen += 1
		if t % 8 == 7:
			await get_tree().physics_frame

	var searches: int = spawner.nav.searches if spawner.has_nav() else 0
	h = hash([h, searches, spawner.nav.failures if spawner.has_nav() else 0])
	await _dispose(game)
	return [h, seen, searches]


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
		p.is_bot = false  # idle: a bot shoots, and the wave then dies at the first choke it meets
		p.health.invulnerable = true

	game.start()
	var ticks := 0

	# Notes first: the wave is two seconds off, and its planning must not race the first zombies.
	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 20000:
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


func _wave_shard_names() -> Array:
	var out := []
	for i in WAVE_SHARDS:
		out.append("w%d" % i)
	return out


## The merge run: every shard's log is there and together they entered a section per survival map.
func _merge_waves(logs: PackedStringArray) -> void:
	var absent := GSGameShardArgs.missing(logs)
	_check(logs.size() == WAVE_SHARDS and absent.is_empty(), "every wave shard's log is there (%d logs)" % logs.size(), "missing %s" % [absent])
	var entered := GSGameShardArgs.sections_entered(logs)
	var want := _survival_maps().size()
	_check(entered == want, "the wave shards entered a section per survival map (%d of %d)" % [entered, want])
	_report_sections(1, 1, 1, 2)


## Development: `--only=stuck` prints the stuck table for every map.
func _dev_stuck(only: String) -> void:
	# Development: `--only=stuck` every map, `--only=stuck:zz_mall` one; prints the table.
	var ids: Array = ALL_MAPS if only == "stuck" else [only.substr(6)]

	# `--only=stuck_survival`: every survival map in maps/, however it got there (the manor, ze_potc).
	if only == "stuck_survival":
		ids = _survival_maps()

	for id: String in ids:
		var meter: StuckMeter = await _stuck(StringName(id))
		print("STUCK %-24s %s" % [id, meter.line()])
		print("      rescue: %s" % meter.rescue)
		print("      watch: %s" % meter.watch_line())
		for kind: StringName in StuckMeter.KINDS:
			print("      %s worst cells %s" % [kind, meter.worst_cells(kind)])
		for line in meter.cases.slice(0, 8):
			print("      case %s" % line)
		for block in meter.captures:
			print(block)


## Development `--only=` runs; true when one ran (the caller then quits).
func _dev_only(only: String) -> bool:
	if only.begins_with("stuck"):
		await _dev_stuck(only)
		get_tree().quit(0)
		return true

	# `--only=wave` every survival map, `--only=wave:gm_valley,zz_lot` those.
	if only == "wave" or only.begins_with("wave:"):
		if only == "wave":
			await _test_wave_origins()
		else:
			for id in only.substr(5).split(","):
				await _test_wave_origin(StringName(id))
		_report()
		return true

	if only == "mend":
		await _test_mend_gap()
		get_tree().quit(0)
		return true

	if only == "ladder":
		_test_graph()
		await _test_ladder_climb()
		_report()
		return true

	if only == "thin":
		_test_thin_props()
		_report()
		return true

	if only == "wedge":
		await _test_hop_wedge()
		await _test_unstick_steps()
		_report()
		return true

	if only == "steps":
		await _test_unstick_steps()
		_report()
		return true

	if only == "repeat":
		await _test_repeatable()
		_report()
		return true

	if only == "lure":
		await _test_lure_crowd()
		_report()
		return true

	if only.begins_with("hold:"):
		await _test_holding(StringName(only.substr(5)))
		get_tree().quit(0)
		return true

	if only != "":
		await _test_spread(&"zz_high_school")
		await _test_spread(&"zz_mall")
		get_tree().quit(0)
		return true

	return false
