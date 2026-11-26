extends GSGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzHorde := preload("../game/zz_horde.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const CommonBrain := preload("../npcs/zz_common_brain.gd")
const ZombieMove := preload("../npcs/zz_zombie_brain_move.gd")
const DecideCases := preload("zz_native_decide_cases.gd")
const SteerState := preload("zz_native_steer_state.gd")
const CrowdGrid := preload("res://addons/gs_npc_ai/steer/gs_npc_ai_crowd_grid.gd")

## The zombies' brains in gs-sim ([member ZzConfig.native_brains], on by default) decide as the script over seeded
## worlds: the commons' chase plan (whom, whether the forced survivor is spent, where, how fast, how far, how near a
## swing lands) under Hard Box stacks, Angry runners, downed, dead and missing survivors, crawlers and burning bodies,
## and every zombie's spaced heading off the native crowd, stacked bodies included, all to the bit. The script plan
## is checked against the calls it replaced (quarry, survivor_at, _chase_speed, strikes_down) too. The fused steer
## ([code]steer_walk[/code], and [code]steer_step[/code] that reads and writes the brain itself: the heading, wish,
## eased turn, look and progress watch) leaves every body, character and brain as the script's steer does, stuck ones and paths gone rough included. The
## native decide (`chase`: the plan and what the common does with it, whether it asks for a slot; `barricade_in_way`
## off the horde's barricades; `nearest`) answers as `_chase_choice`, `ZzHorde.barricade_in_way` and
## `nearest_survivor_distance` do, pressed against boards, inside them and clear, mid-swing or not. Without the library
## the native half is skipped; [code]GS_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const SECTIONS := 8
const CHECKS := 27
const NATIVE := &"GSSimZombieBrains"
const NATIVE_CROWD := &"GSSimCrowdGrid"
const SEEDS := 60
const PASSES := 5


class Boxes:
	extends RefCounted
	var angry := false
	var hard := 0

	func is_active(id: StringName) -> bool:
		return angry if id == &"angry" else hard > 0 if id == &"hard" else false

	func stacks_of(id: StringName) -> int:
		return hard if id == &"hard" else 0


class Game:
	extends RefCounted
	var config: ZzConfig = ZzConfig.new()
	var boxes := Boxes.new()


var _entered := 0
var _finished := 0
var _world: Node3D = null


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone native brains\n")
	_unbound_watch()
	_entered += 1
	print("the brains are native by default, and the library is there")
	_check(ZzConfig.new().native_brains, "ZzConfig.native_brains is on by default")
	if not ClassDB.class_exists(NATIVE) or not ClassDB.class_exists(NATIVE_CROWD):
		print("  gs-sim's zombie module is not loaded: the native half is skipped")
		_check(OS.get_environment("GS_SIM_REQUIRE_NATIVE") != "1", "the library is loaded (GS_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, 2, 4)
		return
	_check(true, "the library has the zombie brains and the crowd")
	_finished += 1

	_entered += 1
	print("seeded worlds, script chase plan against native and against the calls it replaced")
	var bad := {"native": 0, "plan": 0, "legacy": 0}
	var counted := {"plans": 0, "forced": 0, "target": 0, "nobody": 0, "lost": 0, "spent": 0, "down": 0, "runner": 0}
	for s in SEEDS:
		_plans(s, bad, counted)
	_check(bad["native"] == 0, "the native plan ran for every zombie", "%d fell back" % bad["native"])
	_check(bad["legacy"] == 0, "the script plan is quarry, survivor_at, _chase_speed and strikes_down as before", "%d differ" % bad["legacy"])
	_check(bad["plan"] == 0, "the native plan is the script plan to the bit", "%d differ" % bad["plan"])
	_check(counted["plans"] > 3000 and counted["forced"] > 100 and counted["target"] > 300 and counted["nobody"] > 100 \
			and counted["lost"] > 100 and counted["spent"] > 50 and counted["down"] > 30 and counted["runner"] > 30,
		"the plans chased forced and own targets, nobody, lost ones, spent a forced one, struck the downed and ran",
		str(counted))
	_finished += 1

	_entered += 1
	print("seeded crowds, script spaced heading against native")
	var heads := {"bad": 0, "decided": 0, "pushed": 0, "still": 0}
	for s in SEEDS:
		_headings(s, heads)
	_check(heads["bad"] == 0, "every native heading is the script's to the bit", "%d of %d differ" % [heads["bad"], heads["decided"]])
	var grid: Object = ClassDB.instantiate(NATIVE_CROWD)
	grid.call(&"setup", 4.0)
	_check(grid.call(&"spaced_direction", 12345, Vector3.ZERO, Vector3.ONE, 1.0, Vector3.FORWARD) == Vector3.INF,
		"an id the grid lacks answers INF, so the brain keeps the script")
	_check(heads["decided"] > 3000 and heads["pushed"] > 500 and heads["still"] > 5,
		"the headings were pushed by neighbours and some cancelled to nothing", str(heads))
	_finished += 1

	_entered += 1
	print("seeded worlds, the native steer against the script's")
	_check_steers()
	_finished += 1

	_entered += 1
	print("seeded worlds, the native chase choice, barricade check and nearest survivor against the script's")
	_check_decides()
	_finished += 1

	_entered += 1
	print("the verify mode runs both and finds them the same")
	_check(_verify(), "brains_verify counts no mismatch over ten seeded worlds")
	_finished += 1

	_entered += 1
	print("think pacing: the spawner counts the zombies' ticks natively, the same thoughts as each counting its own")
	_check(ZzConfig.new().native_pacing, "ZzConfig.native_pacing is on by default")
	var off := _pace_run(false, false)
	var script := _pace_run(true, false)
	var counts := [0, 0]
	var native := _pace_run(true, true, counts)
	var kinds := {}
	for e: Array in off:
		kinds[e[0]] = true
	_check(off.size() > 1000 and kinds.size() >= 6 and script == off and native == off,
		"script and native pacing log the same thoughts, seconds, staggers, drives, removals and spawns as no pacing",
		"%d entries, %s; script %s, native %s" % [off.size(), kinds.keys(), _pace_diff(script, off), _pace_diff(native, off)])
	_check(counts[0] > 1000 and counts[1] == 0, "pacing_verify matched the script pacer call for call",
		"%d checked, %d differ" % counts)
	_finished += 1
	if _world != null:
		_world.free()
		_world = null

	_report_sections(_entered, _finished, SECTIONS, CHECKS)


## A zombie killed mid-think (a blast, a hazard, a stand-in's shot answered in the same tick) is removed at once,
## and removal unbinds its brain, so the think's last step, the unstick watch, finds its npc gone. The native
## think moved `npc.position()` ahead of the body guard that used to cover that (headless_nav_holds hit
## `Nonexistent function 'position' in base 'Nil'`); the watch must let go instead.
func _unbound_watch() -> void:
	_entered += 1
	print("the unstick watch of a zombie unbound mid-think lets go")
	_fresh_world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var brain: Object = _commons(rng, _horde(rng), 1)[0]
	brain.set(&"_watch_at", Vector3(1.0, 0.0, 1.0))
	brain.set(&"_watch_for", 2.0)
	brain.call(&"unbind")
	_check(brain.get(&"npc") == null and brain.call(&"body") == null, "unbind lets go of the npc and its body")
	brain.call(&"_unstick_watch", 0.1)
	_check(brain.get(&"_watch_at") == Vector3.INF and float(brain.get(&"_watch_for")) == 0.0,
		"the watch resets instead of reading the gone npc's position",
		"at %s for %s" % [brain.get(&"_watch_at"), brain.get(&"_watch_for")])
	_finished += 1


const PACE_PROBE := "res://examples/zz_paced_probe_brain.gd"
const PACE_BODY := "res://examples/zz_paced_probe_body"


## 1500 ticks of 30 probe zombies (and those they spawn) through a real spawner: [param pacing] off, script, or
## native with [member GSNpcSpawner.pacing_verify] ([param counts] gets checked and mismatched).
func _pace_run(pacing: bool, native: bool, counts: Array = []) -> Array:
	_fresh_world()
	var body := Node3D.new()
	var packed := PackedScene.new()
	packed.pack(body)
	body.free()
	var def := GSNpcDef.make(&"probe", PACE_BODY)
	def.brain_script_path = PACE_PROBE
	def.max_health = 100.0
	def.require_line_of_sight = false
	var spawner := GSNpcSpawner.new()
	spawner.catalogue = GSNpcCatalogue.new()
	spawner.catalogue.add(def)
	var limits := GSNpcLimits.new()
	limits.spawn_interval = 0.0
	limits.require_navigable_spawn = false
	limits.world_budget = 0
	limits.per_kind_cap = 0
	spawner.limits = limits
	spawner.authoritative = true
	spawner._held[PACE_BODY] = packed
	spawner.pacing = pacing
	spawner.pacing_native = native
	spawner.pacing_verify = native
	spawner.set_meta(&"pace_log", [])
	_world.add_child(spawner)
	for i in 30:
		spawner.spawn(&"probe", Vector3(i * 1.5 - 22.0, 0, (i % 5) * 3.0 - 6.0))
	for t in 1500:
		spawner.tick(0.016)
	if counts.size() == 2:
		counts[0] = spawner.pacing_checked
		counts[1] = spawner.pacing_mismatches
	var out: Array = spawner.get_meta(&"pace_log", [])
	spawner.queue_free()
	return out


func _pace_diff(a: Array, b: Array) -> String:
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			return "entry %d: %s vs %s" % [i, a[i], b[i]]
	return "%d vs %d entries" % [a.size(), b.size()]


func _fresh_world() -> void:
	if _world != null:
		_world.free()
	_world = Node3D.new()
	add_child(_world)


func _horde(rng: RandomNumberGenerator) -> ZzHorde:
	var h := ZzHorde.new()
	var game := Game.new()
	h.game = game
	h.config = ZzConfig.new()
	h.config.common_speed_scaling = rng.randf() < 0.7
	h.config.common_speed_base = rng.randf_range(1.0, 4.0)
	h.config.common_speed_per_hard_stack = rng.randf_range(0.0, 1.5)
	h.config.common_speed_max = rng.randf_range(3.0, 9.0)
	h.config.common_run_speed = rng.randf_range(3.0, 9.0)
	h.config.angry_runner_fraction = rng.randf()
	game.config.down_attack = rng.randf() < 0.75
	_roll_boxes(rng, game)
	h.brains_native = ClassDB.instantiate(NATIVE)
	_world.add_child(h)
	return h


func _roll_boxes(rng: RandomNumberGenerator, game: Game) -> void:
	game.boxes.angry = rng.randf() < 0.5
	game.boxes.hard = [0, 0, rng.randi_range(1, 6)][rng.randi() % 3]


func _survivors(rng: RandomNumberGenerator, h: ZzHorde) -> void:
	h._survivors.clear()
	for i in rng.randi_range(0, 8):
		var id := StringName("s%d" % rng.randi_range(0, 9))
		var at := Vector3(rng.randf_range(-30, 30), rng.randf_range(-1, 3), rng.randf_range(-30, 30))
		h._survivors[id] = {"position": at, "eye": at + Vector3.UP * 1.6, "alive": rng.randf() < 0.8,
			"up": true, "down": rng.randf() < 0.3, "pinned": false, "biled": false, "health": 1.0, "entity": i}


func _pick_id(rng: RandomNumberGenerator) -> StringName:
	match rng.randi() % 4:
		0:
			return &""
		1:
			return &"gone"
		_:
			return StringName("s%d" % rng.randi_range(0, 9))


## [param n] commons with bodies in the tree, each its own kind, flags, tuning, pace, roll, target and forced survivor.
func _commons(rng: RandomNumberGenerator, h: ZzHorde, n: int) -> Array:
	var out: Array = []
	for i in n:
		var body := ZzZombieBody.new()
		body.kind = &"crawler" if rng.randf() < 0.2 else &"common"
		body.flags = ZzZombieBody.FLAG_BURNING if rng.randf() < 0.2 else 0
		_world.add_child(body)
		var npc := GSNpcInstance.new()
		npc.instance_id = i + 1
		npc.node = body
		npc.def = GSNpcDef.new()
		match rng.randi() % 4:
			0:
				npc.def.meta["reach"] = rng.randf_range(0.6, 2.5)
			1:
				npc.def.meta["reach"] = rng.randi_range(1, 2)
			2:
				npc.def.meta["reach"] = "far"
		var brain: Object = CommonBrain.new()
		brain.npc = npc
		brain._horde = h
		_roll_common(rng, brain)
		out.append(brain)
	return out


func _roll_common(rng: RandomNumberGenerator, brain: Object) -> void:
	var body: Node3D = brain.npc.node
	body.position = Vector3(rng.randf_range(-30, 30), rng.randf_range(-1, 2), rng.randf_range(-30, 30))
	body.rotation.y = rng.randf_range(-PI, PI)
	brain.npc.target_id = _pick_id(rng)
	brain.forced = _pick_id(rng)
	brain.pace = rng.randf_range(0.88, 1.12)
	brain.runner_roll = rng.randf()


## What the old [code]_chase[/code] read, in its order: quarry() (which spends a dead forced one), survivor_at,
## _chase_speed, flat_distance, tune and strikes_down. [member forced] is put back after.
func _legacy(brain: Object, b: ZzZombieBody) -> PackedFloat64Array:
	var saved: StringName = brain.forced
	var plan := PackedFloat64Array([-1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var target: StringName = brain.quarry()
	plan[1] = 1.0 if saved != &"" and brain.forced == &"" else 0.0
	brain.forced = saved
	if target == &"":
		return plan
	plan[0] = 0.0 if target == saved and plan[1] == 0.0 else 1.0
	var at: Vector3 = brain.survivor_at(target)
	if at == Vector3.INF:
		plan[0] = -2.0
		return plan
	var speed: float = brain._chase_speed() * brain.pace
	if b.has_flag(ZzZombieBody.FLAG_BURNING):
		speed *= 1.2
	var reach: float = brain.tune(&"reach", 1.55)
	if brain.strikes_down(target):
		reach = minf(reach, 1.1)
	plan[2] = at.x
	plan[3] = at.y
	plan[4] = at.z
	plan[5] = speed
	plan[6] = CommonBrain.flat_distance(brain.npc.position(), at)
	plan[7] = reach
	return plan


func _plans(s: int, bad: Dictionary, counted: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3100 + s
	_fresh_world()
	var h := _horde(rng)
	var commons := _commons(rng, h, rng.randi_range(1, 40))
	for p in PASSES:
		_survivors(rng, h)
		_roll_boxes(rng, h.game)
		h._feed_brains()
		for brain: Object in commons:
			var b: ZzZombieBody = brain.npc.node
			var script: PackedFloat64Array = brain._chase_plan_script(b)
			if script != _legacy(brain, b):
				bad["legacy"] += 1
			if h.brains_now == null:
				bad["native"] += 1
				continue
			var native: PackedFloat64Array = brain._chase_plan(b)
			if native != script:
				bad["plan"] += 1
				if bad["plan"] <= 3:
					print("  differ: script %s native %s" % [script, native])
			counted["plans"] += 1
			counted[["nobody", "lost", "forced", "target"][int(script[0]) + 2]] += 1
			if script[1] > 0.5:
				counted["spent"] += 1
			if script[0] >= 0.0 and script[7] == 1.1 and b.kind != &"crawler":
				counted["down"] += 1
			if script[0] >= 0.0 and h.is_runner(brain.runner_roll) and h.config.common_speed_scaling:
				counted["runner"] += 1
			_roll_common(rng, brain)


func _check_decides() -> void:
	DecideCases.check(self, SEEDS, PASSES)


## Two crowds over the same bodies, one script grid and one native; the brain asks each for its heading.
func _headings(s: int, heads: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4700 + s
	_fresh_world()
	var h := _horde(rng)
	var commons := _commons(rng, h, rng.randi_range(2, 80))
	for p in PASSES:
		# Some stacked on one another, so the tie-break by facing is exercised.
		for brain: Object in commons:
			var body: Node3D = brain.npc.node
			if rng.randf() < 0.15:
				body.position = (commons[0].npc.node as Node3D).position
			elif rng.randf() < 0.7:
				body.position = Vector3(rng.randf_range(-12, 12), rng.randf_range(-0.5, 1.0), rng.randf_range(-12, 12))
			body.rotation.y = rng.randf_range(-PI, PI)
		var script_grid := CrowdGrid.new(4.0)
		var native_grid: Object = ClassDB.instantiate(NATIVE_CROWD)
		native_grid.call(&"setup", 4.0)
		var ids := PackedInt64Array()
		var at := PackedVector3Array()
		for brain: Object in commons:
			var _i := script_grid.add(brain.npc.instance_id, brain.npc.position())
			ids.append(brain.npc.instance_id)
			at.append(brain.npc.position())
		native_grid.call(&"fill", ids, at)
		for brain: Object in commons:
			var here: Vector3 = brain.npc.position()
			var goal := Vector3(rng.randf_range(-30, 30), rng.randf_range(-1, 2), rng.randf_range(-30, 30))
			if rng.randf() < 0.05:
				goal = here
			var spacing: float = [1.1, rng.randf_range(0.3, 3.0)][rng.randi() % 2]
			h.crowd = script_grid
			h.crowd_native = false
			h.brains_crowd = null
			var script: Vector3 = brain._spaced_direction(here, goal, spacing)
			h.crowd = native_grid
			h.crowd_native = true
			h.brains_crowd = native_grid
			var native: Vector3 = brain._spaced_direction(here, goal, spacing)
			heads["decided"] += 1
			if script != native:
				heads["bad"] += 1
				if heads["bad"] <= 3:
					print("  differ: script %s native %s" % [script, native])
			if script == Vector3.ZERO:
				heads["still"] += 1
			elif not script.is_equal_approx(GSNpcAiSteering.seek(here, goal)):
				heads["pushed"] += 1


## [code]turn_view[/code] of the library against [method GSNpcAiCharacter.turn_view], turns half done and overshoots
## armed or decaying, for characters of every tuning.
func _turn_probe(s: int, tp: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + s
	_fresh_world()
	var h := _horde(rng)
	var _c := _commons(rng, h, 2)
	_survivors(rng, h)
	h._feed_brains()
	var n: Object = h.brains_now
	for i in 400:
		var c := GSNpcAiCharacter.new()
		c.seed_value = rng.randi()
		c.view_turn_deg = rng.randf_range(30.0, 1440.0)
		c.view_factor = rng.randf_range(0.05, 1.0)
		c.overshoot = [0.0, 0.4, rng.randf()][rng.randi() % 3]
		c._peak_turn = [0.0, rng.randf_range(0.0, PI)][rng.randi() % 2]
		c._turns = rng.randi_range(0, 9)
		c._over_amt = [0.0, rng.randf_range(-0.3, 0.3)][rng.randi() % 2]
		c._over_axis = [Vector3.UP, Vector3.DOWN][rng.randi() % 2]
		var cur := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1))
		var want := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1))
		var delta: float = [1.0 / 60.0, rng.randf_range(0.001, 0.25)][rng.randi() % 2]
		var st := [c._peak_turn, c._over_amt, c._over_axis, c._turns]
		var o: PackedFloat64Array = n.call(&"turn_view", c, cur, want, delta)
		var f := c.turn_view(cur, want, delta)
		tp["n"] += 1
		var got := [Vector3(o[0], o[1], o[2]), o[3], o[4], int(o[5]), Vector3(o[6], o[7], o[8])]
		var expected := [f, c._peak_turn, c._over_amt, c._turns, c._over_axis]
		if got != expected:
			tp["bad"] += 1
			if tp["bad"] <= 3:
				print("  TURN in %s cur %s want %s delta %s vf %s vtd %s os %s seed %s" % [var_to_str(st), var_to_str(cur),
					var_to_str(want), var_to_str(delta), var_to_str(c.view_factor), var_to_str(c.view_turn_deg),
					var_to_str(c.overshoot), c.seed_value])
				print("    got %s exp %s" % [var_to_str(got), var_to_str(expected)])


## The native steer against the script's over seeded worlds, and the native turn_view beside it.
func _check_steers() -> void:
	var steers := {"bad": 0, "stored": 0, "walked": 0, "steered": 0, "still": 0, "turned": 0, "overshot": 0, "reset": 0, "stuck": 0, "rough": 0,
		"moved": 0, "due": 0, "advanced": 0, "ended": 0}
	var tp := {"bad": 0, "n": 0}
	for s in SEEDS:
		_turn_probe(s, tp)
	_check(tp["bad"] == 0, "the native turn_view is the character's to the bit, overshoot and its decay included",
		"%d of %d differ" % [tp["bad"], tp["n"]])
	for s in SEEDS:
		_steers(s, steers)
	_check(steers["bad"] == 0, "every native steer leaves the body, the turn, the cruise and the watch as the script's",
		"%d of %d differ" % [steers["bad"], steers["steered"] + steers["still"]])
	_check(not ClassDB.class_has_method(NATIVE, &"steer_walk") or steers["walked"] > 3000,
		"the steers went through steer_walk as well as steer_step", str(steers))
	_check(not ClassDB.class_has_method(NATIVE, &"walk") or (steers["moved"] > 1500 and steers["due"] > 300
			and steers["advanced"] > 200 and steers["ended"] > 50),
		"the whole move went through walk: paths walked, due, advanced past their corners and run to their end",
		str(steers))
	_check(not ClassDB.class_has_method(NATIVE, &"walk_stored") or steers["stored"] > 1500,
		"the whole move went through the native store too (walk_stored, steer_stored), its state taken back the same",
		str(steers))
	_check(steers["steered"] > 3000 and steers["still"] > 20 and steers["turned"] > 1000 and steers["overshot"] > 100
			and steers["reset"] > 500 and steers["stuck"] > 50 and steers["rough"] > 20,
		"the steers turned, overshot, stood still, reset their watch, got stuck and went rough", str(steers))


## Each common steered twice from the same state, once through [code]steer_step[/code] (applied) and once through
## the script's own steer, with characters of every tuning, turns half done, bodies stacked or at their goal, and
## watches fresh, moving, stale and stuck.
func _steers(s: int, steers: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6200 + s
	_fresh_world()
	var h := _horde(rng)
	var commons := _commons(rng, h, rng.randi_range(2, 60))
	_survivors(rng, h)
	h._feed_brains()
	var grid: Object = ClassDB.instantiate(NATIVE_CROWD)
	grid.call(&"setup", 4.0)
	h.crowd = grid
	h.crowd_native = true
	var ctx := GSNpcAiContext.new()
	var sp := _nav_spawner(rng)
	_tune_characters(rng, commons, ctx)
	for brain: Object in commons:
		if brain.path != null and rng.randf() < 0.8:
			brain.director = sp
			brain._sched_probe = 1 << 30
	for p in PASSES:
		var ids := PackedInt64Array()
		var at := PackedVector3Array()
		for brain: Object in commons:
			var body: Node3D = brain.npc.node
			if rng.randf() < 0.1:
				body.global_position = (commons[0].npc.node as Node3D).global_position
			elif rng.randf() < 0.5:
				body.global_position = Vector3(rng.randf_range(-12, 12), rng.randf_range(-0.5, 1.0), rng.randf_range(-12, 12))
			body.rotation = Vector3(0.0, rng.randf_range(-PI, PI), 0.0)
			ids.append(brain.npc.instance_id)
			at.append(brain.npc.position())
		grid.call(&"fill", ids, at)
		ctx.delta = [0.0, 1.0 / 60.0, rng.randf_range(0.001, 0.25)][rng.randi() % 3]
		ctx.now = 10.0 * p + rng.randf_range(0.0, 5.0)
		sp._now = ctx.now
		for brain: Object in commons:
			var kase := _steer_case(rng, brain, ctx)
			_path_case(rng, brain, kase[0], ctx)
			var to: Vector3 = kase[0]
			var spacing: float = kase[1]
			var speed: float = kase[2]
			var before := SteerState.take(brain)
			# Both steers start from a transform just set: look_at keeps the body's scale through get_scale, which a
			# set transform answers from the basis and a set rotation from its cache, an ulp apart.
			SteerState.put(brain, before)
			h.brains_crowd = null
			brain.steer_with_spacing(to, speed, ctx.delta, spacing)
			var script := SteerState.take(brain)
			h.brains_crowd = grid
			_native_steers(h, brain, before, script, kase, ctx, steers)
			_tally_steer(steers, brain, ctx, before, script)
			if brain.director == sp:
				SteerState.put(brain, before)
				_tally_path(steers, brain, sp, kase[0], before, script)
	sp.free()


## One common's native steer from [param before], through [code]steer_walk[/code] when the library has it and
## [code]steer_step[/code] after it, each against the script's [param script].
func _native_steers(h: Object, brain: Object, before: Array, script: Array, kase: Array, ctx: GSNpcAiContext,
		steers: Dictionary) -> void:
	var walks: Array = [1, 0] if h.brains_now.has_method(&"steer_walk") else [0]
	if h.brains_now.has_method(&"walk"):
		walks.push_front(2)
	# 3 is the whole move with the turn and watch in the native store (walk_stored, steer_stored), for a brain of
	# the horde's spawner, whose repath tuning the store is handed.
	if h.brains_now.has_method(&"walk_stored") and brain.director != null:
		walks.push_front(3)
	for walk: int in walks:
		SteerState.put(brain, before)
		# 2 is the whole move (walk, then steer_walk after a due path), 1 the path in script and steer_walk.
		ZombieMove._steer_walks = mini(walk, 1)
		ZombieMove._walks = 1 if walk >= 2 else 0
		ZombieMove._stores = 1 if walk == 3 else 0
		if walk == 3:
			var sp: GSNpcSpawner = brain.director
			h.spawner = sp
			h.brains_now.call(&"set_repath", sp.repath_drift, sp.repath_interval, sp.repath_drift_ratio,
				sp.repath_interval_per_m)
		var steered: int = h.brains_now.call(&"steered")
		brain.steer_with_spacing(kase[0], kase[2], ctx.delta, kase[1])
		if walk == 3:
			if brain._stored_in != null:
				steers["stored"] += 1
			brain._unstore()
			h.spawner = null
		var native := SteerState.take(brain)
		if walk == 1:
			steers["walked"] += 1
		elif walk == 2 and brain.director != null:
			steers["moved"] += 1
		if int(h.brains_now.call(&"steered")) == steered:
			steers["bad"] += 1
			if steers["bad"] <= 3:
				print("  the native steer did not run (walk %d)" % walk)
		elif native != script:
			steers["bad"] += 1
			if steers["bad"] <= 3:
				for i in script.size():
					if script[i] != native[i]:
						print("  walk %d differ at %d: script %s native %s" % [walk, i, var_to_str(script[i]),
							var_to_str(native[i])])
	ZombieMove._steer_walks = -1
	ZombieMove._walks = -1
	ZombieMove._stores = -1


## A spawner with a two-point nav graph (so it has navigation) whose repaths are deferred, with repath tuning rolled.
func _nav_spawner(rng: RandomNumberGenerator) -> GSNpcSpawner:
	var data := GSNpcNavData.new()
	data.map_id = &"walk_probe"
	data.source_digest = "walk_probe"
	var a := data.add_point(Vector3.ZERO)
	var b := data.add_point(Vector3(1.0, 0.0, 0.0))
	var _c := data.connect_points(a, b)
	var sp := GSNpcSpawner.new()
	sp.nav = GSNpcNavGraph.new(data)
	assert(sp.has_nav())
	# A due path is queued for a search, which reads the snap radius (the spawner's own default; it never enters the tree).
	sp.limits = GSNpcLimits.new()
	sp.deferred_paths = true
	sp.repath_drift = [0.0, 2.5, rng.randf_range(0.5, 6.0)][rng.randi() % 3]
	sp.repath_interval = [0.0, 1.5, rng.randf_range(0.2, 4.0)][rng.randi() % 3]
	sp.repath_drift_ratio = [0.0, rng.randf_range(0.05, 0.5)][rng.randi() % 2]
	sp.repath_interval_per_m = [0.0, rng.randf_range(0.01, 0.2)][rng.randi() % 2]
	return sp


## A pathed common's path put in a state of the pass: empty, fresh or stale, walked part way, to its end or past it,
## partial or not, corners near the body (to be passed) and far, its goal moved or not.
func _path_case(rng: RandomNumberGenerator, brain: Object, to: Vector3, ctx: GSNpcAiContext) -> void:
	var p: GSNpcPath = brain.path
	if p == null:
		return
	var here: Vector3 = brain.npc.position()
	var pts := PackedVector3Array()
	var n: int = [0, rng.randi_range(1, 3), rng.randi_range(2, 9)][rng.randi() % 3]
	var at := here
	for i in n:
		var step := rng.randf_range(0.2, 1.5) if rng.randf() < 0.5 else rng.randf_range(1.5, 8.0)
		at += Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6), rng.randf_range(-1, 1)).normalized() * step
		pts.append(at)
	p.points = pts
	p.index = [0, rng.randi_range(0, n + 1), n, -1][rng.randi() % 4] if n > 0 else 0
	p.arrive_radius = [1.2, rng.randf_range(0.3, 3.0)][rng.randi() % 2]
	p.computed_at = ctx.now - [0.0, rng.randf_range(0.0, 1.0), rng.randf_range(0.0, 6.0)][rng.randi() % 3]
	p.goal_at_compute = to + [Vector3.ZERO, Vector3(rng.randf_range(-6, 6), 0.0, rng.randf_range(-6, 6))][rng.randi() % 2]
	p.partial = rng.randf() < 0.3


## Counts what the script's path step did for a pathed common (due, passed corners, ran to its end).
func _tally_path(steers: Dictionary, brain: Object, sp: GSNpcSpawner, to: Vector3, before: Array, script: Array) -> void:
	var p: GSNpcPath = brain.path
	var saved: int = p.index
	p.index = before[11]
	var drift := sp.repath_drift
	var interval := sp.repath_interval
	if sp.repath_drift_ratio > 0.0 or sp.repath_interval_per_m > 0.0:
		var gap: float = brain.npc.position().distance_to(to)
		drift = maxf(drift, sp.repath_drift_ratio * gap)
		interval = maxf(interval, sp.repath_interval_per_m * gap)
	var due := p.needs_repath(sp.now(), to, interval, drift)
	p.index = saved
	if due:
		steers["due"] += 1
	elif script[11] > before[11]:
		steers["advanced"] += 1
		if script[11] >= p.points.size():
			steers["ended"] += 1


## Each common's character, tuned at random and given a path or not.
func _tune_characters(rng: RandomNumberGenerator, commons: Array, ctx: GSNpcAiContext) -> void:
	for brain: Object in commons:
		var c := GSNpcAiCharacter.new()
		c.seed_value = rng.randi()
		c.view_turn_deg = rng.randf_range(30.0, 1440.0)
		c.view_factor = rng.randf_range(0.05, 1.0)
		c.overshoot = [0.0, 0.4, rng.randf()][rng.randi() % 3]
		brain.character = c
		brain.context = ctx
		brain.stuck_seconds = rng.randf_range(0.5, 2.0)
		if rng.randf() < 0.5:
			brain.path = GSNpcPath.new()


## One common's random steer case: its body, character and watch put in a state of the pass; [the goal, spacing, speed].
func _steer_case(rng: RandomNumberGenerator, brain: Object, ctx: GSNpcAiContext) -> Array:
	var here: Vector3 = brain.npc.position()
	var to := Vector3(rng.randf_range(-30, 30), rng.randf_range(-1, 2), rng.randf_range(-30, 30))
	match rng.randi() % 10:
		0:
			to = here
		1:
			to = here + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
	brain._facing_at_tick = [Vector3.ZERO, (brain.npc.node as Node3D).global_transform.basis.z,
		Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1))][rng.randi() % 3]
	var c: GSNpcAiCharacter = brain.character
	c._peak_turn = [0.0, rng.randf_range(0.0, PI)][rng.randi() % 2]
	c._turns = rng.randi_range(0, 9)
	c._over_amt = [0.0, rng.randf_range(-0.3, 0.3)][rng.randi() % 2]
	match rng.randi() % 4:
		0:
			brain._progress_at = Vector3.INF
		1:
			brain._progress_at = here + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
			brain._progress_since = ctx.now - rng.randf_range(0.0, 4.0)
		2:
			brain._progress_at = here + Vector3(rng.randf_range(-3, 3), 0.0, rng.randf_range(-3, 3))
			brain._progress_since = ctx.now - rng.randf_range(0.0, 4.0)
		3:
			brain._progress_at = here
			brain._progress_since = ctx.now - 10.0
	var spacing: float = [1.1, 1.6, rng.randf_range(0.3, 3.0)][rng.randi() % 3]
	var speed := rng.randf_range(0.5, 8.0)
	return [to, spacing, speed]


## Counts what one pair of steers did, by the state the script left.
func _tally_steer(steers: Dictionary, brain: Object, ctx: GSNpcAiContext, before: Array, script: Array) -> void:
	if script[1] == before[1] and script[0] == before[0]:
		steers["still"] += 1
	else:
		steers["steered"] += 1
	if script[2] != before[2] or script[5] != before[5]:
		steers["turned"] += 1
	if script[3] != 0.0 and script[3] != before[3]:
		steers["overshot"] += 1
	if script[9] != before[9]:
		steers["reset"] += 1
	if script[10] != before[10]:
		steers["rough"] += 1
	elif before[8] != Vector3.INF and script[9] == before[9] and ctx.now - before[9] >= brain.stuck_seconds:
		steers["stuck"] += 1


## The horde's [member ZzHorde.brains_verify]: both run, the script's answer is kept, every pair counted.
func _verify() -> bool:
	var decided := 0
	var mismatches := 0
	for s in 10:
		var rng := RandomNumberGenerator.new()
		rng.seed = 8800 + s
		_fresh_world()
		var h := _horde(rng)
		h.brains_verify = true
		var commons := _commons(rng, h, rng.randi_range(10, 40))
		h.set_barricades(DecideCases.barricade_bounds(rng))
		_survivors(rng, h)
		h._feed_brains()
		var native_grid: Object = ClassDB.instantiate(NATIVE_CROWD)
		native_grid.call(&"setup", 4.0)
		for brain: Object in commons:
			var _i: int = native_grid.call(&"add", brain.npc.instance_id, brain.npc.position())
		h.crowd = native_grid
		h.crowd_native = true
		h.brains_crowd = native_grid
		var ctx := GSNpcAiContext.new()
		var sp := _nav_spawner(rng)
		# The horde's own spawner, so its repath tuning is fed and the stored walk is checked beside the walk.
		h.spawner = sp
		h._feed_brains()
		for brain: Object in commons:
			brain.character = GSNpcAiCharacter.new()
			brain.character.seed_value = rng.randi()
			brain.context = ctx
			if rng.randf() < 0.6:
				brain.path = GSNpcPath.new()
				brain.director = sp
				brain._sched_probe = 1 << 30
		for p in 3:
			ctx.delta = 1.0 / 60.0
			ctx.now = 1.0 + p
			sp._now = ctx.now
			for brain: Object in commons:
				var b: ZzZombieBody = brain.npc.node
				if brain.path != null:
					_path_case(rng, brain, Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), ctx)
				var plan: PackedFloat64Array = brain._chase_plan(b)
				if plan != brain._chase_plan_script(b):
					mismatches += 1000
				brain._swing_at = INF if rng.randf() < 0.7 else ctx.now
				b.wish = Vector3(rng.randf_range(-4, 4), 0.0, rng.randf_range(-4, 4))
				if brain._chase_decide(b) != brain._chase_choice(brain._chase_plan_script(b)):
					mismatches += 1000
				var _barred: String = brain._barred(h, b)
				var _near: float = brain._nearest_survivor(h)
				var _dir: Vector3 = brain._spaced_direction(brain.npc.position(), Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), 1.1)
				brain.steer_with_spacing(Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), rng.randf_range(1.0, 6.0), ctx.delta, 1.1)
			_survivors(rng, h)
			h._feed_brains()
		decided += h.brains_decided
		mismatches += h.brains_mismatches
		h.spawner = null
		sp.free()
	print("  %d decided, %d mismatches" % [decided, mismatches])
	return decided > 500 and mismatches == 0
