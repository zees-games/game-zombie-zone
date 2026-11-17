extends RefCounted
## `headless_native_brains`' decide section: seeded worlds of commons by survivors and barricades, the native chase
## choice, barricade check and nearest survivor against the script's. [code]t[/code] is the suite, for its worlds.

const CommonBrain := preload("../npcs/zz_common_brain.gd")
const ZombieMove := preload("../npcs/zz_zombie_brain_move.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")


## Runs [param seeds] worlds of [param passes] passes each and makes [param t]'s six checks.
static func check(t: Node, seeds: int, passes: int) -> void:
	var bad := {"fell": 0, "choice": 0, "barred": 0, "nearest": 0, "stale": 0}
	var counted := {"choices": 0, "hit": 0, "chase": 0, "slow": 0, "ask": 0, "past_ring": 0, "barred": 0,
		"inside": 0, "clear": 0, "nobody": 0}
	ZombieMove._decides = -1
	for s in seeds:
		_decides(t, s, passes, bad, counted)
	ZombieMove._decides = -1
	t._check(bad["fell"] == 0, "the native decide ran for every zombie, barricades handed over first or later",
		"%d fell back" % bad["fell"])
	t._check(bad["choice"] == 0, "the native chase choice is the script's to the bit", "%d differ" % bad["choice"])
	t._check(bad["barred"] == 0, "the native barricade check is the horde's", "%d differ" % bad["barred"])
	t._check(bad["nearest"] == 0, "the native nearest survivor is the horde's to the bit", "%d differ" % bad["nearest"])
	t._check(bad["stale"] == 0, "a bash reach changed since the barricades were handed over leaves them to the script",
		"%d stale" % bad["stale"])
	t._check(counted["choices"] > 3000 and counted["hit"] > 100 and counted["chase"] > 300 and counted["slow"] > 100 \
			and counted["ask"] > 100 and counted["past_ring"] > 100 and counted["barred"] > 100 \
			and counted["inside"] > 20 and counted["clear"] > 1000 and counted["nobody"] > 50,
		"the choices hit, chased, drifted and asked; zombies were barred, inside boards and clear; some had nobody",
		str(counted))


## Up to a dozen boxes over the commons' ground, for [method ZzHorde.set_barricades].
static func barricade_bounds(rng: RandomNumberGenerator) -> Dictionary:
	var bounds := {}
	for i in rng.randi_range(0, 12):
		bounds["b%d" % i] = AABB(Vector3(rng.randf_range(-30, 30), rng.randf_range(-2, 2), rng.randf_range(-30, 30)),
			Vector3(rng.randf_range(0.1, 4.0), rng.randf_range(0.5, 3.0), rng.randf_range(0.1, 4.0)))
	return bounds


static func _decides(t: Node, s: int, passes: int, bad: Dictionary, counted: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5300 + s
	t._fresh_world()
	var h: Object = t._horde(rng)
	h.config.bash_reach = rng.randf_range(0.4, 2.0)
	var bounds := barricade_bounds(rng)
	if s % 2 == 1:
		# Barricades first, the brains after (the library loaded once the map was up): `_pick_crowd` hands them over.
		h.brains_native = null
		h.set_barricades(bounds)
		h._pick_crowd()
	else:
		h.set_barricades(bounds)
	var boxes: Array = bounds.values()
	var commons: Array = t._commons(rng, h, rng.randi_range(1, 40))
	for p in passes:
		t._survivors(rng, h)
		t._roll_boxes(rng, h.game)
		h._feed_brains()
		if h.brains_now == null or h.brains_barred == null:
			bad["fell"] += 1
			continue
		var ids: Array = h._survivors.keys()
		for brain: Object in commons:
			_place(rng, h, brain, ids, boxes)
			_compare(h, brain, bad, counted)
			t._roll_common(rng, brain)
	h.config.bash_reach += 0.25
	h._feed_brains()
	if h.brains_barred != null:
		bad["stale"] += 1


## Puts [param brain]'s body up against a survivor, at a barricade or where it was, with a ring, swing and wish.
static func _place(rng: RandomNumberGenerator, h: Object, brain: Object, ids: Array, boxes: Array) -> void:
	var b: ZzZombieBody = brain.npc.node
	var roll := rng.randf()
	if roll < 0.4 and not ids.is_empty():
		# Up against somebody: in reach, above or below it, or just out of the ring.
		var id: StringName = ids[rng.randi() % ids.size()]
		brain.npc.target_id = id
		b.position = (h._survivors[id]["position"] as Vector3) \
			+ Vector3(rng.randf_range(-4, 4), rng.randf_range(-2.5, 2.5), rng.randf_range(-4, 4))
	elif roll < 0.75 and not boxes.is_empty():
		# At a barricade: against its face, beside it, above or below it, or inside the boards.
		var box: AABB = boxes[rng.randi() % boxes.size()]
		b.position = box.position + Vector3(rng.randf_range(-2.5, box.size.x + 2.5),
			rng.randf_range(-2.5, box.size.y + 0.5), rng.randf_range(-2.5, box.size.z + 2.5))
		if rng.randf() < 0.15:
			b.position = box.position + box.size * Vector3(rng.randf(), rng.randf(), rng.randf())
	brain.ring = rng.randf_range(CommonBrain.RING_MIN, CommonBrain.RING_MAX)
	brain._swing_at = rng.randf() if rng.randf() < 0.3 else INF
	b.wish = Vector3(rng.randf_range(-4, 4), rng.randf_range(-1, 1), rng.randf_range(-4, 4))
	if rng.randf() < 0.05:
		b.wish = Vector3.ZERO


## The script's and the native chase choice, barricade check and nearest survivor for [param brain], tallied.
static func _compare(h: Object, brain: Object, bad: Dictionary, counted: Dictionary) -> void:
	var b: ZzZombieBody = brain.npc.node
	var script: PackedFloat64Array = brain._chase_choice(brain._chase_plan_script(b))
	var native: PackedFloat64Array = brain._chase_decide(b)
	if native != script:
		bad["choice"] += 1
		if bad["choice"] <= 3:
			print("  differ: script %s native %s" % [script, native])
	counted["choices"] += 1
	if script[0] >= 0.0:
		counted[["", "hit", "chase", "slow"][int(script[8])]] += 1
		if script[9] > 0.5:
			counted["ask"] += 1
		elif script[0] != CommonBrain.PLAN_FORCED:
			counted["past_ring"] += 1

	var at: Vector3 = brain.npc.position()
	var want: String = h.barricade_in_way(at, b.wish)
	var got: String = brain._barred(h, b)
	if got != want:
		bad["barred"] += 1
		if bad["barred"] <= 3:
			print("  differ: at %s wish %s script '%s' native '%s'" % [at, b.wish, want, got])
	if want != "":
		counted["barred"] += 1
		if (h.barricades[want]["bounds"] as AABB).has_point(at):
			counted["inside"] += 1
	else:
		counted["clear"] += 1

	var near: float = h.nearest_survivor_distance(at)
	if brain._nearest_survivor(h) != near:
		bad["nearest"] += 1
	if near == INF:
		counted["nobody"] += 1
