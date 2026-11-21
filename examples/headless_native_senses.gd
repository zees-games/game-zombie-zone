extends GSGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")

## The horde's senses in dot-sim ([member ZzConfig.native_senses], on by default) decide as dot-npc's script
## pass over seeded worlds: walls, smoke, blind and deaf zombies, cones, missing and duplicate candidates, held
## targets that leave, and several passes a seed, so the same targets at the same moments, the same rays and the
## same counters. Without the library the native half is skipped; [code]GS_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const SECTIONS := 3
const CHECKS := 8
const NATIVE := &"GSSimSenses"
const SEEDS := 40
const PASSES := 6
const FACTIONS: Array[StringName] = [&"survivors", &"hostile", &"rival", &"wildlife"]

var _entered := 0
var _finished := 0
var _world: Node3D = null


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone native senses")
	print("")
	_entered += 1
	print("the senses are native by default, and the library is there")
	_check(ZzConfig.new().native_senses, "ZzConfig.native_senses is on by default")
	if not ClassDB.class_exists(NATIVE):
		print("  dot-sim's senses module is not loaded: the native half is skipped")
		_check((OS.get_environment("GS_SIM_REQUIRE_NATIVE") if OS.has_environment("GS_SIM_REQUIRE_NATIVE") else OS.get_environment("DOT_SIM_REQUIRE_NATIVE")) != "1", "the library is loaded (GS_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, SECTIONS - 2, 2)
		return
	_check(true, "the library has the senses")
	_finished += 1

	_entered += 1
	print("seeded worlds, script pass against native pass")
	var bad := {"state": 0, "signals": 0, "counters": 0, "native": 0}
	var counted := {"decided": 0, "casts": 0, "switches": 0, "clears": 0}
	for s in SEEDS:
		await _compare(s, bad, counted)
	_check(bad["native"] == 0, "the native pass ran on every native pass", "%d passes fell back" % bad["native"])
	_check(bad["state"] == 0, "every zombie has the same target, seen, engaged, since and quiet", "%d differ" % bad["state"])
	_check(bad["signals"] == 0, "the same target_changed signals in the same order", "%d passes differ" % bad["signals"])
	_check(bad["counters"] == 0, "the same sight checks and rays cast", "%d passes differ" % bad["counters"])
	_check(counted["decided"] > 3000 and counted["casts"] > 500 and counted["switches"] > 50 \
			and counted["clears"] > 20,
		"the passes decided, cast rays, switched and dropped targets",
		"%d decided, %d rays, %d switches, %d clears" % [counted["decided"], counted["casts"],
			counted["switches"], counted["clears"]])
	_finished += 1

	_entered += 1
	print("the verify mode runs both and finds them the same")
	_check(await _verify(), "native_verify counts no mismatch over ten seeded worlds")
	_finished += 1
	_world.free()
	_world = null

	_report_sections(_entered, _finished, SECTIONS, CHECKS)


## A floor, a few walls and pillars, and [param n] zombie bodies (some plain Node3D, some not 3D at all).
func _build(rng: RandomNumberGenerator, n: int) -> Array[Node]:
	if _world != null:
		_world.free()
	_world = Node3D.new()
	add_child(_world)
	for w in rng.randi_range(0, 14):
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(rng.randf_range(0.3, 12.0), rng.randf_range(0.5, 4.0), rng.randf_range(0.3, 12.0))
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(rng.randf_range(-30, 30), rng.randf_range(-1, 2), rng.randf_range(-30, 30))
		body.rotation.y = rng.randf_range(-PI, PI)
		_world.add_child(body)
	var nodes: Array[Node] = []
	for i in n:
		var node: Node3D
		match rng.randi() % 8:
			0:
				node = Node3D.new()
			1:
				# Not 3D: the script treats its sight as clear, so must the native pass.
				var plain := Node.new()
				_world.add_child(plain)
				nodes.append(plain)
				continue
			_:
				var body := CharacterBody3D.new()
				var shape := CollisionShape3D.new()
				var capsule := CapsuleShape3D.new()
				capsule.height = 1.8
				capsule.radius = 0.35
				shape.shape = capsule
				shape.position.y = 0.9
				body.add_child(shape)
				node = body
		_world.add_child(node)
		_place(rng, node)
		nodes.append(node)
	return nodes


func _place(rng: RandomNumberGenerator, node: Node3D) -> void:
	node.position = Vector3(rng.randf_range(-35, 35), rng.randf_range(-0.5, 1.5), rng.randf_range(-35, 35))
	node.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-PI, PI), 0.0)


func _def(rng: RandomNumberGenerator) -> GSNpcDef:
	var def := GSNpcDef.new()
	def.faction = FACTIONS[1 + rng.randi() % 3]
	def.sight_range = [0.0, rng.randf_range(4.0, 60.0), rng.randf_range(10.0, 30.0)][rng.randi() % 3]
	def.sight_half_angle_deg = [180.0, rng.randf_range(10.0, 179.0), 60.0][rng.randi() % 3]
	def.hearing_range = [0.0, rng.randf_range(2.0, 30.0)][rng.randi() % 2]
	def.require_line_of_sight = rng.randf() < 0.85
	def.eye_height = rng.randf_range(0.0, 2.0)
	return def


func _candidates(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for i in rng.randi_range(0, 24):
		if rng.randf() < 0.06:
			out.append(null)
			continue
		var id := StringName("p%d" % rng.randi_range(0, 18))
		var faction: StringName = FACTIONS[0] if rng.randf() < 0.7 else FACTIONS[rng.randi() % FACTIONS.size()]
		var at := Vector3(rng.randf_range(-40, 40), rng.randf_range(-0.5, 2.5), rng.randf_range(-40, 40))
		out.append(GSNpcSenses.Candidate.new(id, at, faction, [0.0, 0.0, rng.randf_range(1.0, 25.0)][rng.randi() % 3]))
	return out


## Two spawners (not in the tree: only their perception pass runs) over the same seeded state, one native.
func _spawner(rng_seed: int, native: bool, verify := false) -> GSNpcSpawner:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var sp := GSNpcSpawner.new()
	sp.limits = GSNpcLimits.new()
	sp.limits.sense_period_ticks = rng.randi_range(1, 3)
	sp.limits.sense_quiet_mult = rng.randi_range(1, 3)
	sp.limits.sense_candidate_cap = [0, 0, rng.randi_range(1, 8)][rng.randi() % 3]
	sp.senses = GSNpcSenses.new()
	sp.senses.switch_ratio = [0.6, rng.randf_range(0.2, 1.0)][rng.randi() % 2]
	sp.senses.commitment_grace = rng.randf_range(0.0, 5.0)
	sp.senses.line_of_sight_enabled = rng.randf() < 0.9
	sp.senses.prune_by_held = rng.randf() < 0.7
	sp.senses.occlusion_mask = 1
	sp.senses.native_enabled = native
	sp.senses.native_verify = verify
	return sp


func _instances(rng: RandomNumberGenerator, nodes: Array[Node], cands: Array) -> Array[GSNpcInstance]:
	var out: Array[GSNpcInstance] = []
	for i in nodes.size():
		var npc := GSNpcInstance.new()
		npc.instance_id = i + 1
		npc.def = _def(rng)
		npc.node = nodes[i]
		npc.alive = rng.randf() < 0.95
		npc.sight_scale = [1.0, rng.randf_range(-0.5, 2.0)][rng.randi() % 2]
		npc.blind_until = [-1.0, rng.randf_range(0.0, 6.0)][rng.randi() % 2]
		npc.sense_quiet = rng.randf() < 0.3
		match rng.randi() % 4:
			0:
				npc.target_id = &""
			1:
				npc.target_id = &"gone"
			_:
				var c: Variant = cands[rng.randi() % cands.size()] if not cands.is_empty() else null
				npc.target_id = (c as GSNpcSenses.Candidate).id if c != null else &""
		npc.target_seen_at = rng.randf_range(-3.0, 2.0)
		npc.engaged_at = npc.target_seen_at
		npc.target_since = npc.target_seen_at - 1.0
		out.append(npc)
	return out


## One seed: [constant PASSES] passes with the candidates, zombies, blockers and clock moving between them.
func _compare(s: int, bad: Dictionary, counted: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + s
	var nodes := _build(rng, rng.randi_range(1, 60))
	var cands := _candidates(rng)
	var state := rng.randi()
	var a := _spawner(9000 + s, false)
	var b := _spawner(9000 + s, true)
	var sides: Array[GSNpcSpawner] = [a, b]
	var logs: Array = [[], []]
	for side in 2:
		var r := RandomNumberGenerator.new()
		r.seed = state
		for npc in _instances(r, nodes, cands):
			sides[side]._npcs[npc.instance_id] = npc
		var seen: Array = logs[side]
		sides[side].target_changed.connect(func(npc: GSNpcInstance, t: StringName) -> void: seen.append([npc.instance_id, t]))
	var now := rng.randf_range(0.0, 4.0)
	for p in PASSES:
		await get_tree().physics_frame
		await get_tree().physics_frame
		for sp in sides:
			sp.senses.now = now
		if rng.randf() < 0.5:
			var at := Vector3(rng.randf_range(-30, 30), rng.randf_range(0, 2), rng.randf_range(-30, 30))
			var radius := rng.randf_range(0.0, 6.0)
			var secs: float = [0.0, rng.randf_range(0.2, 3.0)][rng.randi() % 2]
			for sp in sides:
				sp.senses.add_sight_blocker(at, radius, secs)
		a._candidates = cands
		b._candidates = cands
		for sp in sides:
			sp._now = now
			sp._ticks = p + s
		var held: Array = []
		for npc: GSNpcInstance in a._npcs.values():
			held.append(npc.target_id)
		a._perception.perceive()
		b._perception.perceive()
		if b.senses.native() == null:
			bad["native"] += 1
		if a.senses.sight_checks != b.senses.sight_checks or a.senses.los_casts != b.senses.los_casts:
			bad["counters"] += 1
		if logs[0] != logs[1]:
			bad["signals"] += 1
		var k := 0
		for id: int in a._npcs:
			var x: GSNpcInstance = a._npcs[id]
			var y: GSNpcInstance = b._npcs[id]
			if x.target_id != y.target_id or x.target_seen_at != y.target_seen_at or x.engaged_at != y.engaged_at \
					or x.target_since != y.target_since or x.sense_quiet != y.sense_quiet:
				bad["state"] += 1
			if held[k] != &"" and x.target_id != &"" and held[k] != x.target_id:
				counted["switches"] += 1
			if held[k] != &"" and x.target_id == &"":
				counted["clears"] += 1
			k += 1
		logs[0].clear()
		logs[1].clear()
		# Moved on: some candidates walk, some leave or arrive, some zombies turn and walk, time passes.
		for i in cands.size():
			var c := cands[i] as GSNpcSenses.Candidate
			if c != null and rng.randf() < 0.6:
				cands[i] = GSNpcSenses.Candidate.new(c.id, c.position + Vector3(rng.randf_range(-6, 6), 0.0,
					rng.randf_range(-6, 6)), c.faction, [0.0, rng.randf_range(1.0, 25.0)][rng.randi() % 2])
		if rng.randf() < 0.3 and not cands.is_empty():
			cands.remove_at(rng.randi() % cands.size())
		if rng.randf() < 0.3:
			cands.append_array(_candidates(rng).slice(0, 2))
		for node in nodes:
			if node is Node3D and rng.randf() < 0.4:
				_place(rng, node as Node3D)
		now += [0.0, rng.randf_range(0.05, 2.5)][rng.randi() % 4 % 2]
	counted["decided"] += b.senses.native_decided
	counted["casts"] += b.senses.los_casts
	a.free()
	b.free()


## [member GSNpcSenses.native_verify] over ten worlds: both passes run, the script's answers kept, no mismatch.
func _verify() -> bool:
	var decided := 0
	var mismatches := 0
	for s in 10:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + s
		var nodes := _build(rng, rng.randi_range(10, 60))
		var cands := _candidates(rng)
		var sp := _spawner(6000 + s, true, true)
		for npc in _instances(rng, nodes, cands):
			sp._npcs[npc.instance_id] = npc
		sp._candidates = cands
		for p in 3:
			await get_tree().physics_frame
			await get_tree().physics_frame
			sp._now = float(p)
			sp._ticks = p
			sp._perception.perceive()
		decided += sp.senses.native_decided
		mismatches += sp.senses.native_mismatches
		sp.free()
	print("  %d decided, %d mismatches" % [decided, mismatches])
	return decided > 300 and mismatches == 0
