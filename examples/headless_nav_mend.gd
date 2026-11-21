extends "headless_nav_base.gd"

## The nav suite's mending, wedge and lure sections.


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

	# By name: a plain sort() orders StringNames by their interned address, which differs per process,
	# and every wave shard must deal the same list.
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	return out


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


## The lot's leaning door panel (0.22 x 1.26 m, turned 147 degrees) closed the whole corner of the
## doorway in one box, so a stand-in beside it had no line to the graph.
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

	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 20000:
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
			var npc: GSNpcInstance = npcs[i]
			if npc.is_alive():
				var start: Vector3 = WEDGES[i][0]
				furthest[i] = maxf(furthest[i], Vector2(npc.position().x - start.x, npc.position().z - start.z).length())

	for i in npcs.size():
		var npc: GSNpcInstance = npcs[i]
		var remedies: PackedStringArray = npc.brain.get(&"unstick_log") if npc.is_alive() else PackedStringArray()
		var detail := "from %s furthest %.1f m, remedies [%s]" % [WEDGES[i][0], furthest[i], ", ".join(remedies)]
		_check(npc.is_alive() and furthest[i] > 3.0, "the common caught at %s gets 3 m clear within 15 s" % WEDGES[i][0], detail)

	# The hop itself zeroes wish; the watchdog must pause through it, not start again.
	var hopper: GSNpcInstance = npcs[0]
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


## The ship's mezzanine (7.92 m, over the aft landing) and the main deck 2.2 m above it, joined only by the hatch ladder
## at x -47.55. The lower deck is no start: its door aft is 1.6 m high (a common is 1.75 m) and its caged ladders stop
## under the closed deck, so a common cannot leave it, and a ladder joined through a cage or a deck slab is a graph lie.
const LADDER_FOOT := Vector3(-50.45, 7.92, -36.45)
const LADDER_DECK := Vector3(-45.5, 10.0, -21.0)
## Metres the zombie must rise while climbing: the hatch ladder's 1.95 m less its lip.
const LADDER_CLIMB := 1.5

## A common on the ship's mezzanine, its quarry on the main deck above: it reaches the deck up a ladder
## (`zz_zombie_ladder_speed`) instead of standing below forever, which it did while ladders were not on its graph.
func _test_ladder_climb() -> void:
	_section("a zombie climbs a ladder to the survivor on the floor above")
	if not _linked:
		_check(true, "skipped without maps/")
		_check(true, "skipped without maps/")
		_finished()
		return

	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zm_roy_the_ship"])
		c.survival_warmup_seconds = 600.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false)
	var quarry := game.add_player(&"u200", "Deckhand")
	quarry.health.invulnerable = true
	game.start()
	var ticks := 0

	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	var nav: ZzNavGraph = game.horde.spawner.nav
	var saved := nav.filter
	nav.filter = null
	var with_rungs := nav.find_path(LADDER_FOOT, LADDER_DECK, 1.0)
	var rungs_partial := nav.last_partial
	nav.allow_ladders = false
	var without := nav.find_path(LADDER_FOOT, LADDER_DECK, 1.0)
	var without_partial := nav.last_partial
	nav.allow_ladders = true
	nav.filter = saved
	_check(not with_rungs.is_empty() and not rungs_partial and (without.is_empty() or without_partial),
		"the zombies' graph goes from the mezzanine to the main deck by the ladder, and not without it",
		"with %d points (partial %s), without %d (partial %s), %d ladder links" % [with_rungs.size(), rungs_partial, without.size(), without_partial, nav.ladder_count])
	quarry.place_at(LADDER_DECK, 0.0)
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, LADDER_FOOT, &"test")
	npc.brain.call(&"force_target", &"u200")
	var highest := LADDER_FOOT.y
	var closest := INF
	# Metres risen while the body was climbing (ZzZombieBody.climbing), and every time the unstick watchdog set it down
	# somewhere else (ZzUnstick relocate or nudge): the deck has to be reached up the ladder. A hop is a common's own
	# way up a jump-up link (the crate), so it counts as walking.
	var climbed := 0.0
	var last_y := LADDER_FOOT.y
	var rescues := PackedStringArray()

	for step in 160:
		await _sim(game, 0.25)
		if not npc.is_alive():
			break
		var y := npc.position().y
		var body := npc.brain.call(&"body") as ZzZombieBody
		if body != null and body.climbing() and y > last_y:
			climbed += y - last_y
		last_y = y
		highest = maxf(highest, y)
		for line: String in npc.brain.unstick_log:
			if (line.contains("relocate") or line.contains("nudge")) and not rescues.has(line):
				rescues.append(line)
		closest = minf(closest, npc.position().distance_to(quarry.global_position))
		if closest < 2.5:
			break

	_check(npc.is_alive() and highest > LADDER_DECK.y - 0.5 and closest < 2.5 and climbed >= LADDER_CLIMB and rescues.is_empty(),
		"it climbs the ladder itself (no unstick relocation or nudge) and is on the deck beside the survivor within 40 s",
		"rose to %.1f m (deck %.1f), %.1f m of it climbing (want %.1f), closest %.1f m, ladders on the graph %d, unstick rescues %s" % [highest, LADDER_DECK.y, climbed, LADDER_CLIMB, closest, int(game.horde.spawner.nav.get(&"ladder_count")), rescues])
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

	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	# The plan (routes, chokes, narrow points) runs the tick after the annotations arrive.
	game.simulate(TICK)

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

	_check_door_frames(game)

	await _dispose(game)
	_finished()


## A stand-in's first path legs must not run through the door frame.
func _check_door_frames(game: ZzGame) -> void:
	# Stand-ins at these spots had smoothing cut the corner of a door frame.
	var nav: GSNpcNavGraph = game.horde.spawner.nav
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
		# A cold nav cache spends seconds of game time getting READY; the director's commons then down
		# the Watcher before the lure and the lost round clears the crowd. Only the test's crowd here.
		c.director_enabled = false
		c.sleepers_enabled = false)
	var _p := game.add_player(&"u100", "Watcher")
	game.start()
	var ticks := 0

	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 20000:
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

	for npc: GSNpcInstance in game.horde.spawner.all_npcs():
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


## The pieces are a zombie's, and a zombie's edges are one way. [method _test_graph]'s graph numbers its high floor first,
## the one order a forward flood labels right; Roy Highway's deck was numbered after the street and its two zombie
## spawns were refused the way down they had.
func _check_one_way() -> void:
	var late := GSNpcNavData.new()
	late.map_id = &"late_test"
	late.source_digest = "test"
	late.grid_spacing = 1.0
	var foot := PackedInt32Array()
	var top := PackedInt32Array()
	var roof := PackedInt32Array()

	for i in 3:
		foot.append(late.add_point(Vector3(float(i), 0.0, 6.0)))

	for i in 3:
		top.append(late.add_point(Vector3(float(i), 3.0, 0.0)))

	for i in 2:
		roof.append(late.add_point(Vector3(float(i), 6.0, -6.0)))

	for i in 2:
		var _c := late.connect_points(foot[i], foot[i + 1])
		var _d := late.connect_points(top[i], top[i + 1])

	var _e := late.connect_points(roof[0], roof[1])
	# A plain edge 3 m high: the importer's link down a ledge, which a zombie takes down only.
	var _f := late.connect_points(top[2], foot[0])
	var one_way := ZzNavGraph.new()
	var late_built := one_way.rebuild(late)
	_check(late_built.ok, "the late graph builds", "" if late_built.ok else late_built.error.message)
	_check(not one_way.find_path(Vector3(0.0, 3.0, 0.0), Vector3(2.0, 0.0, 6.0), 0.5).is_empty(),
		"a zombie walks down a ledge whose top is numbered after its foot")
	_check(one_way.find_path(Vector3(2.0, 0.0, 6.0), Vector3(0.0, 3.0, 0.0), 0.5).is_empty(), "and still not up it")
	_check(one_way.connected(top[0], foot[2]) and not one_way.connected(foot[2], top[0]),
		"the pieces say the same: the top reaches the foot, the foot not the top")
	var short := one_way.find_path(Vector3(2.0, 0.0, 6.0), Vector3(0.0, 3.0, 0.0), 0.5, true)
	_check(one_way.last_partial and short.size() >= 2 and short[short.size() - 1].distance_to(Vector3(0.0, 0.0, 6.0)) < 0.1,
		"a partial path up it ends at the foot of the ledge", str(short))

	one_way.add_drop(roof[1], top[0])
	one_way.relabel()
	_check(one_way.connected(roof[0], foot[2]) and not one_way.connected(top[0], roof[0]),
		"a drop numbered last reaches through two pieces, and nothing reaches back up it")
	_check(not one_way.find_path(Vector3(0.0, 6.0, -6.0), Vector3(2.0, 0.0, 6.0), 0.5).is_empty(),
		"and the zombie on the roof walks all the way down")

	one_way.allow_climb = true
	_check(one_way.connected(foot[2], top[0]) and not one_way.connected(foot[2], roof[0]),
		"with climbing on the ledge is one piece again, at once; a drop still is not a way up")


# Exodus


## A ladder is a two-way link, off the graph with `zz_zombie_ladder_speed` 0: [method _test_graph]'s two floors joined.
func _check_ladder_link(data: GSNpcNavData, low: PackedInt32Array, high: PackedInt32Array) -> void:
	# A ladder is a two-way link: up the rungs as well as down, while zz_zombie_ladder_speed is over 0.
	var ladder := ZzNavGraph.new()
	var _rebuilt := ladder.rebuild(data)
	ladder.add_ladder(low[1], high[1])
	ladder.relabel()
	var rungs_up := ladder.find_path(Vector3(2.0, 0.0, 6.0), Vector3(0.0, 3.0, 0.0), 0.5)
	var rungs_down := ladder.find_path(Vector3(0.0, 3.0, 0.0), Vector3(2.0, 0.0, 6.0), 0.5)
	_check(not rungs_up.is_empty() and not rungs_down.is_empty(), "a zombie climbs a ladder up and down",
		"%d up, %d down" % [rungs_up.size(), rungs_down.size()])
	var standing := ladder.filter
	ladder.filter = ladder.bot_filter
	_check(ladder.find_path(Vector3(2.0, 0.0, 6.0), Vector3(0.0, 3.0, 0.0), 0.5).is_empty(),
		"a stand-in's search leaves the ladder to its own climbing")
	ladder.filter = standing
	ladder.allow_ladders = false
	_check(ladder.find_path(Vector3(2.0, 0.0, 6.0), Vector3(0.0, 3.0, 0.0), 0.5).is_empty(),
		"and with zz_zombie_ladder_speed 0 the ladder is off the graph")


## The grid thinning of spawn points keeps what the director's own loop keeps, in its order.
func _check_thinned_spawns() -> void:
	var cloud := GSNpcNavData.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for _i in 900:
		var _p := cloud.add_point(Vector3(rng.randf_range(0.0, 60.0), rng.randf_range(0.0, 6.0), rng.randf_range(0.0, 60.0)))
	var director := GSNpcDirector.new()
	var _n := director.set_spawn_points_from_nav(cloud, 6.0, null)
	var thinned := ZzNpcs.thinned_points(cloud, 6.0, null)
	var expected := director.spawn_points
	director.free()
	_check(thinned.size() > 10 and thinned == expected, "thinned spawn points equal the director's", "%d vs %d" % [thinned.size(), expected.size()])
