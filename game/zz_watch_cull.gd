extends RefCounted

## The horde's mover watch and cull (dot-spawn's DotSpawnWatch and DotSpawnCull): who is stuck or
## has fallen out of the map, and what is done about it. The game applies the actions; the watch
## is also what tools/stuck_meter.gd and the long run read, so "stuck" means one thing.

const ZzNpcs := preload("zz_npcs.gd")
const ZzUnstick := preload("zz_unstick.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const WAVE := &"wave"
## A survivor this close to a zombie is a fight, not a snag.
const FIGHT := 3.0

var watch: DotSpawnWatch
var cull: DotSpawnCull
## Zombies the cull took out, by verdict name.
var removed: Dictionary = {}
var _horde: Object
var _watched: Dictionary = {}


func _init(p_horde: Object, kill_y: float) -> void:
	_horde = p_horde
	var rules := DotSpawnCullRules.new()
	rules.enabled = true
	rules.kill_y = kill_y
	# Stuck is nudged along its way; the horde's rescue repaths and relocates on its own clock.
	rules.stuck_action = DotSpawnDecision.Action.NUDGE
	rules.cooldown_sec = 4.0
	rules.fell_out_action = DotSpawnDecision.Action.DESPAWN
	# Off nav and unreachable are not judged here, and "far" is asked for at a wave's overtime
	# (see tidy_far), never on a clock: a wave is meant to come a long way.
	rules.off_nav_action = DotSpawnDecision.Action.IGNORE
	rules.unreachable_action = DotSpawnDecision.Action.IGNORE
	rules.far_action = DotSpawnDecision.Action.DESPAWN
	rules.far_sec = 1.0e9
	watch = DotSpawnWatch.new(rules)
	cull = DotSpawnCull.new(rules)
	cull.nudge_fn = _nudge
	cull.despawn_fn = _despawn


## Once a horde tick: reports every zombie, advances the clock and applies what the cull decides.
func tick(delta: float) -> void:
	var here := PackedVector3Array()

	for id: StringName in _horde.survivor_ids():
		here.append(_horde.survivor_position(id))

	watch.set_players(here)
	var seen := {}

	for npc: DotNpcInstance in _horde.spawner.all_npcs():
		if not npc.is_alive():
			continue

		seen[npc.instance_id] = true
		var kind := &"special" if ZzNpcs.is_special(npc.def.id) else &"common"
		watch.report(npc.instance_id, npc.position(), kind, walks(npc, here))

	for id: int in _watched.keys():
		if not seen.has(id):
			watch.forget(id)
			cull.forget(id)

	_watched = seen
	var _applied := cull.apply(cull.process(watch.advance(delta)))


## Whether [param npc] has somewhere to go and is going: chasing, investigating or luring on a
## path it has not finished. Idle, at the boards, swinging, staggered, held up behind a shut gate
## or within [constant FIGHT] of a survivor it is not.
func walks(npc: DotNpcInstance, survivors: Variant) -> bool:
	var brain = npc.brain

	if brain == null:
		return false

	var state: StringName = brain.get(&"state")

	# A special's brain names its walking states approach and retreat, never chase.
	if state != &"chase" and state != &"investigate" and state != &"lure" and state != &"approach" and state != &"retreat":
		return false

	# At its place round a lure it stands by design.
	if state == &"lure" and brain.has_method(&"at_lure") and brain.at_lure():
		return false

	# With no way to go (a shut gate between it and who it chases) it waits, which is the rule's
	# doing and not a snag: only a mover with a path it does not follow is stuck.
	var path: DotNpcPath = brain.get(&"path")

	if path == null or path.partial or path.points.is_empty() or path.current(Vector3.INF) == Vector3.INF:
		return false

	# At the boards, even between two blows or in the hop the body takes there.
	var b := npc.node

	if b != null and _horde.barricade_in_way(npc.position(), b.get(&"wish")) != "":
		return false

	if bool(brain.get(&"bashing")) or brain.has_method(&"staggered") and brain.staggered() \
			or brain.has_method(&"swinging") and brain.swinging():
		return false

	var at := npc.position()

	for spot: Vector3 in survivors:
		if spot.distance_to(at) < FIGHT:
			return false

	return true


## A wave's overtime tidy: [param npcs] go through the cull as lost ("far"), so they are counted
## like any other removal. Returns how many were removed.
func tidy_far(npcs: Array[DotNpcInstance]) -> int:
	var verdicts: Array[DotSpawnVerdict] = []

	for npc in npcs:
		var v := DotSpawnVerdict.new()
		v.id = npc.instance_id
		v.kind = npc.def.id if npc.def != null else &""
		v.category = DotSpawnVerdict.Category.FAR
		v.seconds = watch.rules.far_sec
		v.position = npc.position()
		v.time = watch.now
		verdicts.append(v)

	return cull.apply(cull.process(verdicts))


func describe() -> String:
	return "%s; removed %s" % [cull.describe(), removed]


func _nudge(id: Variant, v: DotSpawnVerdict) -> void:
	var npc: DotNpcInstance = _horde.spawner.get_npc(int(id))
	var b := npc.node as ZzZombieBody if npc != null else null

	if b == null or b.anchored:
		return

	var toward := Vector3.INF
	var best := INF

	for sid: StringName in _horde.survivor_ids():
		var p: Vector3 = _horde.survivor_position(sid)
		var gap := p.distance_to(v.position)

		if gap < best:
			best = gap
			toward = p

	if toward != Vector3.INF and ZzUnstick.nudge(b, toward - b.global_position):
		_horde.stuck_nudges += 1


func _despawn(id: Variant, v: DotSpawnVerdict) -> void:
	var npc: DotNpcInstance = _horde.spawner.get_npc(int(id))

	if npc == null:
		return

	var label := DotSpawnVerdict.category_name(v.category)
	removed[label] = int(removed.get(label, 0)) + 1

	if v.category == DotSpawnVerdict.Category.FELL_OUT:
		_horde.note_fallen(npc)

	if npc.owner_id == WAVE:
		_horde.refused_wave += 1

	var _gone: bool = _horde.spawner.remove(npc.instance_id, DotNpcSpawner.REASON_CLEANUP)
