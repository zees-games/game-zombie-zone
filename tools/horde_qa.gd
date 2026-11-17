extends "res://examples/headless_nav_base.gd"
## A map's horde under load: the zombie spawns that reach no survivor spawn, then N commons chasing invulnerable stand-ins
## for S seconds (who climbed a ladder, who reached, who stood still at the end). `res://tools/horde_qa.tscn --
## --map=zm_roy_the_ship,zm_roy_highway [--zombies=40] [--seconds=120] [--seed=1]`; exits 1 on a trapped spawn or a stuck one.

## Within this of its survivor (metres) a zombie has reached it.
const REACHED := 2.5
## Moved less than this (metres) over the last [constant STILL_WINDOW] seconds, away from its survivor: stuck at the end.
const STILL := 1.0
const STILL_WINDOW := 10.0

var _maps := PackedStringArray(["zm_roy_the_ship", "zm_roy_highway"])
var _zombies := 40
var _seconds := 120.0
var _seed := 1
var _bad := false


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_maps = arg.substr(6).split(",")
		elif arg.begins_with("--zombies="):
			_zombies = int(arg.substr(10))
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.substr(10))
		elif arg.begins_with("--seed="):
			_seed = int(arg.substr(7))
	_qa.call_deferred()


func _qa() -> void:
	for id in _maps:
		await _map(StringName(id))
	print("HORDE_QA %s" % ("FAIL" if _bad else "ok"))
	get_tree().quit(1 if _bad else 0)


func _map(id: StringName) -> void:
	var game := await _world(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray([String(id)])
		c.survival_warmup_seconds = 100000.0
		c.wanderer_density = 0.0
		c.sleepers_enabled = false)
	var team: Array = []
	for i in TEAM:
		var p := game.add_player(StringName("u%d" % (300 + i)), "Bot%d" % i)
		p.is_bot = true
		p.health.invulnerable = true
		team.append(p)
	game.start()
	var ticks := 0
	while (game.horde.notes.state < ZzNavNotes.State.READY or game.horde.plan_pending()) and ticks < 40000:
		game.simulate(TICK)
		ticks += 1
		if ticks % 8 == 0:
			await get_tree().physics_frame

	var nav: ZzNavGraph = game.horde.spawner.nav
	var doc: Dictionary = game.horde.get(&"_doc")
	print("== %s: %d graph points, %d ladder boxes, %d ladder links" % [id, nav.data.points.size(), game.horde.ladders().size(), nav.ladder_count])
	var spawns: Array = doc.get("zombie_spawns", [])
	var survivors: Array = (doc.get("spawns", {}) as Dictionary).get("survivors", [])
	var trapped := 0
	for s: Variant in spawns:
		var from: Vector3 = game.horde.snap_to_nav(ZzMapDoc.v3(s))
		var cut := 0
		for t: Dictionary in survivors:
			if not _reaches(nav, from, game.horde.snap_to_nav(ZzMapDoc.v3(t["at"]))):
				cut += 1
		if cut > 0:
			trapped += 1
			print("  TRAPPED spawn %s (map %s): %d of %d survivor spawns unreachable" % [from, ZzMapDoc.v3(s), cut, survivors.size()])
	print("  zombie spawns: %d, survivor spawns %d, trapped %d" % [spawns.size(), survivors.size(), trapped])
	_bad = _bad or trapped > 0

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var movers: Array[Dictionary] = []
	for i in _zombies:
		var at: Vector3 = ZzMapDoc.v3(spawns[(i / 2) % spawns.size()]) if i % 2 == 0 and not spawns.is_empty() \
			else nav.data.points[rng.randi_range(0, nav.data.points.size() - 1)]
		at = game.horde.snap_to_nav(at)
		var npc: DotNpcInstance = game.horde.spawner.spawn(ZzNpcs.COMMON, at, &"qa")
		if npc == null:
			print("  spawn refused at %s" % at)
			continue
		var quarry = team[i % team.size()]
		npc.brain.call(&"force_target", quarry.player_id)
		movers.append({"npc": npc, "quarry": quarry, "from": at, "random": i % 2 == 1, "climbed": 0.0, "last_y": at.y,
			"closest": INF, "rescues": 0, "trail": [], "seen": {}, "island": not _reaches(nav, at, game.horde.snap_to_nav(quarry.feet()))})

	var meter := StuckMeter.new(game)
	for step in int(_seconds * 4.0):
		await _sim(game, 0.25)
		meter.sample()
		for m in movers:
			_watch(m)
	meter.rescue = str(game.horde.describe().get("stuck", "-"))
	meter.freeze()
	_summarize(id, movers, meter)
	await _dispose(game)


func _reaches(nav: ZzNavGraph, from: Vector3, to: Vector3) -> bool:
	var saved := nav.filter
	nav.filter = null
	var path := nav.find_path(from, to, 1.0)
	var ok := not path.is_empty() and not nav.last_partial
	nav.filter = saved
	return ok


func _watch(m: Dictionary) -> void:
	var npc: DotNpcInstance = m["npc"]
	if not npc.is_alive():
		return
	var y := npc.position().y
	var body := npc.brain.call(&"body") as ZzZombieBody
	if body != null and body.climbing() and y > float(m["last_y"]):
		m["climbed"] = float(m["climbed"]) + y - float(m["last_y"])
	m["last_y"] = y
	m["closest"] = minf(float(m["closest"]), npc.position().distance_to(m["quarry"].feet()))
	var seen: Dictionary = m["seen"]
	for line: String in npc.brain.unstick_log:
		if (line.contains("relocate") or line.contains("nudge")) and not seen.has(line):
			seen[line] = true
			m["rescues"] = int(m["rescues"]) + 1
	var trail: Array = m["trail"]
	trail.append(npc.position())
	if trail.size() > int(STILL_WINDOW * 4.0) + 1:
		trail.pop_front()


func _summarize(id: StringName, movers: Array[Dictionary], meter: StuckMeter) -> void:
	var climbers := 0
	var reached := 0
	var islands := 0
	var rescued := 0
	var stuck: Array[String] = []
	for m in movers:
		var npc: DotNpcInstance = m["npc"]
		climbers += 1 if float(m["climbed"]) >= 1.0 else 0
		reached += 1 if float(m["closest"]) < REACHED else 0
		islands += 1 if m["island"] else 0
		rescued += 1 if int(m["rescues"]) > 0 else 0
		var trail: Array = m["trail"]
		if not npc.is_alive() or trail.size() < 2:
			continue
		var gap: float = npc.position().distance_to(m["quarry"].feet())
		if (trail[-1] as Vector3).distance_to(trail[0]) < STILL and gap > REACHED * 2.0:
			var body := npc.brain.call(&"body") as ZzZombieBody
			stuck.append("from %s (%s%s) now %s, %.1f m from its survivor, climbed %.1f m, %d rescues, climbing %s" % [m["from"],
				"random" if m["random"] else "spawn", ", island" if m["island"] else "", npc.position(), gap, m["climbed"],
				m["rescues"], body != null and body.climbing()])
	print("  %d zombies (%d on islands), %d climbed a ladder (>= 1 m), %d reached their survivor, %d set down by unstick" % [
		movers.size(), islands, climbers, reached, rescued])
	print("  stuck meter: %s" % meter.line())
	print("  rescue: %s" % meter.rescue)
	print("  still for the last %.0f s away from their survivor: %d" % [STILL_WINDOW, stuck.size()])
	for line in stuck:
		print("    STUCK %s" % line)
	_bad = _bad or not stuck.is_empty()
	print("HORDE_QA_MAP %s zombies=%d climbed=%d reached=%d stuck=%d rescued=%d islands=%d" % [id, movers.size(), climbers,
		reached, stuck.size(), rescued, islands])
