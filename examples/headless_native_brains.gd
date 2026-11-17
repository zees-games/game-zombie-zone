extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzHorde := preload("../game/zz_horde.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const CommonBrain := preload("../npcs/zz_common_brain.gd")
const CrowdGrid := preload("res://addons/dot_npc_ai/steer/dot_npc_ai_crowd_grid.gd")

## The zombies' brains in dot-sim ([member ZzConfig.native_brains], on by default) decide as the script over seeded
## worlds: the commons' chase plan (whom, whether the forced survivor is spent, where, how fast, how far, how near a
## swing lands) under Hard Box stacks, Angry runners, downed, dead and missing survivors, crawlers and burning bodies,
## and every zombie's spaced heading off the native crowd, stacked bodies included, all to the bit. The script plan
## is checked against the calls it replaced (quarry, survivor_at, _chase_speed, strikes_down) too. The fused steer
## ([code]steer_step[/code]: the heading, wish, eased turn, look and progress watch) leaves every body, character and
## brain as the script's steer does, stuck ones and paths gone rough included. Without the library
## the native half is skipped; [code]GS_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const SECTIONS := 5
const CHECKS := 13
const NATIVE := &"DotSimZombieBrains"
const NATIVE_CROWD := &"DotSimCrowdGrid"
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
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone native brains")
	print("")
	_entered += 1
	print("the brains are native by default, and the library is there")
	_check(ZzConfig.new().native_brains, "ZzConfig.native_brains is on by default")
	if not ClassDB.class_exists(NATIVE) or not ClassDB.class_exists(NATIVE_CROWD):
		print("  dot-sim's zombie module is not loaded: the native half is skipped")
		_check((OS.get_environment("GS_SIM_REQUIRE_NATIVE") if OS.has_environment("GS_SIM_REQUIRE_NATIVE") else OS.get_environment("DOT_SIM_REQUIRE_NATIVE")) != "1", "the library is loaded (GS_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, 1, 2)
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
	var steers := {"bad": 0, "steered": 0, "still": 0, "turned": 0, "overshot": 0, "reset": 0, "stuck": 0, "rough": 0}
	var tp := {"bad": 0, "n": 0}
	for s in SEEDS:
		_turn_probe(s, tp)
	_check(tp["bad"] == 0, "the native turn_view is the character's to the bit, overshoot and its decay included",
		"%d of %d differ" % [tp["bad"], tp["n"]])
	for s in SEEDS:
		_steers(s, steers)
	_check(steers["bad"] == 0, "every native steer leaves the body, the turn, the cruise and the watch as the script's",
		"%d of %d differ" % [steers["bad"], steers["steered"] + steers["still"]])
	_check(steers["steered"] > 3000 and steers["still"] > 20 and steers["turned"] > 1000 and steers["overshot"] > 100
			and steers["reset"] > 500 and steers["stuck"] > 50 and steers["rough"] > 20,
		"the steers turned, overshot, stood still, reset their watch, got stuck and went rough", str(steers))
	_finished += 1

	_entered += 1
	print("the verify mode runs both and finds them the same")
	_check(_verify(), "brains_verify counts no mismatch over ten seeded worlds")
	_finished += 1
	if _world != null:
		_world.free()
		_world = null

	_report_sections(_entered, _finished, SECTIONS, CHECKS)


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
		var npc := DotNpcInstance.new()
		npc.instance_id = i + 1
		npc.node = body
		npc.def = DotNpcDef.new()
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
			elif not script.is_equal_approx(DotNpcAiSteering.seek(here, goal)):
				heads["pushed"] += 1


## [code]turn_view[/code] of the library against [method DotNpcAiCharacter.turn_view], turns half done and overshoots
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
		var c := DotNpcAiCharacter.new()
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


## What a steer leaves behind: the body's transform and wish, the character's turn, the brain's cruise and watch.
func _steer_state(brain: Object) -> Array:
	var b: ZzZombieBody = brain.npc.node
	var c: DotNpcAiCharacter = brain.character
	var rough: float = brain.path.rough_until if brain.path != null else 0.0
	return [b.global_transform, b.wish, c._peak_turn, c._over_amt, c._over_axis, c._turns, brain._cruise_to,
		brain._cruise_dest, brain._progress_at, brain._progress_since, rough]


func _put_state(brain: Object, st: Array) -> void:
	var b: ZzZombieBody = brain.npc.node
	var c: DotNpcAiCharacter = brain.character
	b.global_transform = st[0]
	b.wish = st[1]
	c._peak_turn = st[2]
	c._over_amt = st[3]
	c._over_axis = st[4]
	c._turns = st[5]
	brain._cruise_to = st[6]
	brain._cruise_dest = st[7]
	brain._progress_at = st[8]
	brain._progress_since = st[9]
	if brain.path != null:
		brain.path.rough_until = st[10]


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
	var ctx := DotNpcAiContext.new()
	for brain: Object in commons:
		var c := DotNpcAiCharacter.new()
		c.seed_value = rng.randi()
		c.view_turn_deg = rng.randf_range(30.0, 1440.0)
		c.view_factor = rng.randf_range(0.05, 1.0)
		c.overshoot = [0.0, 0.4, rng.randf()][rng.randi() % 3]
		brain.character = c
		brain.context = ctx
		brain.stuck_seconds = rng.randf_range(0.5, 2.0)
		if rng.randf() < 0.5:
			brain.path = DotNpcPath.new()
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
		for brain: Object in commons:
			var here: Vector3 = brain.npc.position()
			var to := Vector3(rng.randf_range(-30, 30), rng.randf_range(-1, 2), rng.randf_range(-30, 30))
			match rng.randi() % 10:
				0:
					to = here
				1:
					to = here + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5))
			brain._facing_at_tick = [Vector3.ZERO, (brain.npc.node as Node3D).global_transform.basis.z,
				Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1))][rng.randi() % 3]
			var c: DotNpcAiCharacter = brain.character
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
			var before := _steer_state(brain)
			# Both steers start from a transform just set: look_at keeps the body's scale through get_scale, which a
			# set transform answers from the basis and a set rotation from its cache, an ulp apart.
			_put_state(brain, before)
			h.brains_crowd = null
			brain.steer_with_spacing(to, speed, ctx.delta, spacing)
			var script := _steer_state(brain)
			_put_state(brain, before)
			h.brains_crowd = grid
			var steered: int = h.brains_now.call(&"steered")
			brain.steer_with_spacing(to, speed, ctx.delta, spacing)
			var native := _steer_state(brain)
			if int(h.brains_now.call(&"steered")) == steered:
				steers["bad"] += 1
				if steers["bad"] <= 3:
					print("  the native steer did not run")
			elif native != script:
				steers["bad"] += 1
				if steers["bad"] <= 3:
					for i in script.size():
						if script[i] != native[i]:
							print("  differ at %d: script %s native %s" % [i, var_to_str(script[i]), var_to_str(native[i])])
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
		_survivors(rng, h)
		h._feed_brains()
		var native_grid: Object = ClassDB.instantiate(NATIVE_CROWD)
		native_grid.call(&"setup", 4.0)
		for brain: Object in commons:
			var _i: int = native_grid.call(&"add", brain.npc.instance_id, brain.npc.position())
		h.crowd = native_grid
		h.crowd_native = true
		h.brains_crowd = native_grid
		var ctx := DotNpcAiContext.new()
		for brain: Object in commons:
			brain.character = DotNpcAiCharacter.new()
			brain.character.seed_value = rng.randi()
			brain.context = ctx
		for p in 3:
			ctx.delta = 1.0 / 60.0
			ctx.now = 1.0 + p
			for brain: Object in commons:
				var b: ZzZombieBody = brain.npc.node
				var plan: PackedFloat64Array = brain._chase_plan(b)
				if plan != brain._chase_plan_script(b):
					mismatches += 1000
				var _dir: Vector3 = brain._spaced_direction(brain.npc.position(), Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), 1.1)
				brain.steer_with_spacing(Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), rng.randf_range(1.0, 6.0), ctx.delta, 1.1)
			_survivors(rng, h)
			h._feed_brains()
		decided += h.brains_decided
		mismatches += h.brains_mismatches
	print("  %d decided, %d mismatches" % [decided, mismatches])
	return decided > 500 and mismatches == 0
