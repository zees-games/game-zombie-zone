extends RefCounted

const ZzNpcs := preload("../game/zz_npcs.gd")

## How long movers that have somewhere to go stand still: the measurement behind "the bots and the
## zombies are constantly stuck" (zz-loot-stuck-1). Fed once a tick by [method sample]; it looks at
## the world every [constant EVERY] seconds. Used by `examples/headless_nav.gd` (a band per map)
## and `tools/survival_long_run.gd` (`--watch`), so both mean the same thing by stuck.
##
## [b]Stuck[/b] is a mover that has a goal and has not got further than [constant RADIUS] metres
## from where it was [constant AFTER] seconds ago. The goal is the part that matters: a zombie in
## its idle, at the boards (`bashing`), swinging, staggered or within [constant FIGHT] metres of
## a survivor is not stuck, and a stand-in is only walking when it asked for a path a moment ago,
## got one, and its goal is still further than [constant ARRIVED]; a mover with no way to its goal
## (a shut gate, a team cut off from its posts) waits, and that is a map's fault to be read from
## `unreachable`, not a snag. Counting a holder at its post would
## make every map look the same.
##
## A queued stand-in (see [constant QUEUE]) is counted apart from the ratio but still in `longest`, so a
## jam that never clears fails the longest-stretch band; who goes through a 2 m door first is not a snag
## and changes from run to run.
##
## Kinds: `standin`, `common`, `special`.

const KINDS := [&"standin", &"common", &"special"]
const EVERY := 0.5
const AFTER := 4.0
const RADIUS := 0.75
const FIGHT := 3.0
const ARRIVED := 2.5
## A stand-in this close to another survivor while still is queueing (a doorway taken in turns), not snagged.
const QUEUE := 1.0

var game = null

var _next: float = 0.0
## id -> {at: Vector3, since: float}
var _anchors: Dictionary = {}
## kind -> {goal: seconds with a goal, stuck: seconds stuck}
var totals: Dictionary = {}
## kind -> ids that were ever stuck
var ever: Dictionary = {}
## kind -> the longest single stretch, seconds
var longest: Dictionary = {}
## Where stuck movers stood: [kind, id-ish, Vector3, seconds] of the stretches that ended or are running.
var spots: Dictionary = {}
## The first few that got stuck, as text: where, towards where, and what they were doing.
var cases: Array[String] = []
## Seconds stand-ins had a goal and no path to it, summed over the team (not counted as stuck).
var unreachable: float = 0.0


func _init(p_game: Object) -> void:
	game = p_game

	for kind: StringName in KINDS:
		totals[kind] = {"goal": 0.0, "stuck": 0.0, "queued": 0.0}
		ever[kind] = {}
		longest[kind] = 0.0


## Call after every simulated tick.
func sample() -> void:
	var now: float = game.now()

	if now < _next:
		return

	_next = now + EVERY
	var seen := {}

	for player in game.survivors():
		if not player.is_bot or not player.is_alive() or player.watching or player.is_down():
			continue

		var key := "b%s" % player.player_id
		seen[key] = true
		_mover(key, &"standin", player.feet(), _standin_walks(player), now, player)

	if game.horde != null and game.horde.spawner != null:
		var here: Array = []

		for player in game.survivors():
			if player.is_alive() and not player.watching:
				here.append(player.feet())

		for npc: DotNpcInstance in game.horde.spawner.all_npcs():
			var key := "z%d" % npc.instance_id
			seen[key] = true
			var kind := &"special" if ZzNpcs.is_special(npc.def.id) else &"common"
			_mover(key, kind, npc.position(), _zombie_walks(npc, here), now, npc)

	for key: String in _anchors.keys():
		if not seen.has(key):
			var _gone := _anchors.erase(key)


func _mover(key: String, kind: StringName, at: Vector3, goal: bool, now: float, who: Variant = null) -> void:
	var anchor: Dictionary = _anchors.get(key, {})

	# Moving counts as goal time too, or a fast mover (a special) has next to no denominator.
	if goal and not anchor.is_empty() and at.distance_to(anchor["at"]) > RADIUS:
		(totals[kind] as Dictionary)["goal"] += EVERY

	if not goal or anchor.is_empty() or at.distance_to(anchor["at"]) > RADIUS:
		_anchors[key] = {"at": at, "since": now}
		return

	(totals[kind] as Dictionary)["goal"] += EVERY
	var still: float = now - float(anchor["since"])

	if still < AFTER:
		return

	if kind == &"standin" and _queued(at, who):
		(totals[kind] as Dictionary)["queued"] += EVERY

		if still < AFTER + EVERY and cases.size() < 40:
			cases.append("queued %s %s at %s: %s" % [kind, key, at.snappedf(0.1), _why(who)])

		longest[kind] = maxf(float(longest[kind]), still)
		return

	(totals[kind] as Dictionary)["stuck"] += EVERY

	if still < AFTER + EVERY and cases.size() < 40 and who != null:
		cases.append("%s %s at %s: %s" % [kind, key, at.snappedf(0.1), _why(who)])

	(ever[kind] as Dictionary)[key] = true
	longest[kind] = maxf(float(longest[kind]), still)
	var cell := Vector3(snappedf(at.x, 4.0), 0.0, snappedf(at.z, 4.0))
	var tally: Dictionary = spots.get(kind, {})
	tally[cell] = float(tally.get(cell, 0.0)) + EVERY
	spots[kind] = tally


func _queued(at: Vector3, who: Variant) -> bool:
	for other in game.survivors():
		if other != who and other.is_alive() and other.feet().distance_to(at) < QUEUE:
			return true

	return false


## What a body would hit going 0.4 m toward [param to]: the collider and its place, or "free".
func _blocker(body: CharacterBody3D, to: Vector3) -> String:
	if body == null:
		return "-"

	var heading := to - body.global_position
	heading.y = 0.0

	if heading.length() < 0.01:
		return "-"

	var hit := KinematicCollision3D.new()

	if not body.test_move(body.global_transform, heading.normalized() * 0.4, hit):
		return "free"

	var c := hit.get_collider()
	return "%s at %s normal %s" % [c.name if c is Node else "?", hit.get_position().snappedf(0.1), hit.get_normal().snappedf(0.1)]


## Everything a body's capsule overlaps where it stands (names and places): a mover wedged in a prop.
func _touching(body: CharacterBody3D, state: Object) -> String:
	if body == null:
		return ""

	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), body.global_position + Vector3(0.0, 0.9, 0.0))
	query.collision_mask = body.collision_mask
	query.exclude = [body.get_rid()]
	var names := PackedStringArray()

	for hit: Dictionary in body.get_world_3d().direct_space_state.intersect_shape(query, 6):
		var c: Object = hit["collider"]
		names.append("%s@%s" % [c.name if c is Node else "?", (c as Node3D).global_position.snappedf(0.1) if c is Node3D else "-"])

	var mode := "-"
	if state != null:
		mode = "mode %s pos %s vel %s" % [state.mode, state.position.snappedf(0.1), state.velocity.snappedf(0.1)]
	return ", %s overlaps [%s]" % [mode, ", ".join(names)]


## What its last move slid along (names), and its velocity: a body that wishes and does not move.
func _sliding(body: CharacterBody3D) -> String:
	if body == null:
		return ""

	var names := PackedStringArray()

	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i).get_collider()
		names.append(str(c.name) if c is Node else "?")

	return ", velocity %s, slid on [%s]" % [body.velocity.snappedf(0.1), ", ".join(names)]


func _why(who: Variant) -> String:
	if who is DotNpcInstance:
		var npc: DotNpcInstance = who
		var brain = npc.brain
		var body := npc.node as CharacterBody3D
		var path: DotNpcPath = brain.get(&"path") if brain != null else null
		return "%s state %s lure %s (%d active) target '%s' wish %s floor %s path %s next %s ends %s" % [
			npc.def.id, brain.get(&"state"), (brain.get(&"lure") as Vector3).snappedf(0.1), game.horde._lures.size(), npc.target_id, (body.get(&"wish") as Vector3).snappedf(0.1) if body != null else "-",
			body.is_on_floor() if body != null else "-", path.points.size() if path != null else -1,
			path.current(Vector3.INF).snappedf(0.1) if path != null else "-",
			path.points[path.points.size() - 1].snappedf(0.1) if path != null and not path.points.is_empty() else "-"] \
			+ " blocked by " + _blocker(body, path.current(Vector3.INF) if path != null else Vector3.INF) + _sliding(body)

	var memory: Dictionary = game.bots._state[who.player_id]
	var path: PackedVector3Array = memory["path"]
	var mates := PackedStringArray()
	for other in game.survivors():
		if other != who and other.feet().distance_to(who.feet()) < 1.5:
			mates.append("%s %.1f m" % [other.player_id, other.feet().distance_to(who.feet())])
	var kept: Variant = memory.get("last_command")
	var move: Variant = (kept as DotFpsCommand).move.snappedf(0.1) if kept is DotFpsCommand else "-"
	return "t %.1f phase %s move %s using '%s' goal %s path %d points, next %s, blocked by %s, velocity %s floor %s hops %s mates [%s]" % [game.now(), game.phase, move, who.using, (memory["goal"] as Vector3).snappedf(0.1), path.size(),
		path[0].snappedf(0.1) if not path.is_empty() else "-", _blocker(who, path[0] if not path.is_empty() else Vector3.INF),
		who.velocity.snappedf(0.1), who.is_on_floor(), memory.get("hops", 0), ", ".join(mates)] + _sliding(who) + _touching(who, who.controller.state)


func _standin_walks(player) -> bool:
	if game.bots == null or not game.bots._state.has(player.player_id):
		return false

	var memory: Dictionary = game.bots._state[player.player_id]
	var goal: Vector3 = memory["goal"]

	if goal == Vector3.INF or game.now() - float(memory["path_at"]) > 1.5:
		return false

	var here: Vector3 = player.feet()

	if Vector2(goal.x - here.x, goal.z - here.z).length() <= ARRIVED:
		return false

	if (memory["path"] as PackedVector3Array).is_empty():
		unreachable += EVERY
		return false

	return true


func _zombie_walks(npc: DotNpcInstance, survivors: Array) -> bool:
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

	if bool(brain.get(&"bashing")) or brain.has_method(&"staggered") and brain.staggered() \
			or brain.has_method(&"swinging") and brain.swinging():
		return false

	var at := npc.position()

	for spot: Vector3 in survivors:
		if spot.distance_to(at) < FIGHT:
			return false

	return true


## Stuck seconds over seconds with a goal, 0 to 1. [param at_least] floors the denominator: stand-ins
## that mostly hold a post have 40 to 140 s of goal time, where one 14 s wait in a doorway reads 25%.
func ratio(kind: StringName, at_least: float = 1.0) -> float:
	var t: Dictionary = totals[kind]
	return float(t["stuck"]) / maxf(float(t["goal"]), at_least)


func line() -> String:
	var parts := PackedStringArray()

	for kind: StringName in KINDS:
		var t: Dictionary = totals[kind]
		parts.append("%s %.1f%% of %.0f s goal (%d stuck, worst %.0f s)" % [
			kind, 100.0 * ratio(kind), float(t["goal"]), (ever[kind] as Dictionary).size(), float(longest[kind])])

	parts.append("queued %.0f s, no path to goal %.0f s" % [float((totals[&"standin"] as Dictionary)["queued"]), unreachable])
	return " | ".join(parts)


## The [param count] 4 m cells where most stuck seconds were spent, as "x,z=seconds".
func worst_cells(kind: StringName, count: int = 3) -> String:
	var tally: Dictionary = spots.get(kind, {})
	var cells: Array = tally.keys()
	cells.sort_custom(func(a: Vector3, b: Vector3) -> bool: return tally[a] > tally[b])
	var out := PackedStringArray()

	for i in mini(count, cells.size()):
		out.append("%d,%d=%.0f" % [int(cells[i].x), int(cells[i].z), float(tally[cells[i]])])

	return ", ".join(out)
