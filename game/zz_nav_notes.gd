extends RefCounted

## What the map means to somebody walking it, for this game: dot-npc-ai's annotations
## (drops, chokepoints, covered spots) worked into the three things the bots and the horde use.
##
## [codeblock]
## drops        the zombies' graph gains one-way edges down a ledge (`ZzNavGraph`), so a balcony is a
##              way in and a tower is not a way up
## chokes       the narrow places that lie on a route from the zombies' spawns to the survivors'
##              posts, nearest the spawns first, each with a place to stand behind it
## the horde    asks `waypoint_for`: each zombie is sent through one choke, the least used, rather
##              than all down the shortest route in one line
## the bots     ask `hold_for(seat)`: a stand-in holds the place behind a choke facing the horde's
##              approach, and falls back along that route when the choke is overrun
## [/codeblock]
##
## [b]Why the annotations and not the game's own graph.[/b] The graph is a grid cut from the
## document: it has no walls, only absent points, so it cannot say where a doorway is or whether a
## ledge is a way down. The mesh baked from the colliders can, and it is baked here the way the
## annotator needs it (barricades off the mesh, so a window is a gap and the barricade in it is
## what the horde bashes, not what makes the gap not a choke).
##
## [b]A stepped state machine, never a stall.[/b] Waiting for the physics space to hold the map (the
## colliders a map adds this frame are not in it until the next physics frame), the bake (once,
## synchronously: a seeded round must not depend on when a worker thread lands), then the
## annotation in slices inside [constant SLICE_BUDGET_US] of a tick (the answer is the same however it is
## sliced; only the tick it arrives on is not). Until `state` is READY every ask answers "no
## opinion" and the game plays as it did before.

const CHANNEL := "zz.nav"

enum State { OFF, WAITING, ANNOTATING, READY, FAILED }

## What the annotation may take of one tick, microseconds, once it has done a slice.
const SLICE_BUDGET_US := 1500

## How far behind a choke (toward the post) a defender stands, and how far a covered spot may be.
const HOLD_BEHIND := 4.0
const COVER_WITHIN := 3.5

## A choke is on a route when the route passes within this of it.
const ON_ROUTE := 2.5

const MAX_CHOKES := 14

## What counts as a choke: the annotator's defaults (3 m, 15 percent of 48 routes) found none on a
## school or a stadium, where parallel corridors split the traffic, so a way in is a narrow place
## a twelfth of many routes go through. Tuned by looking (tools/nav_probe.tscn).
var choke_width: float = 4.5
var choke_traffic: float = 0.07
var choke_routes: int = 192

var state: State = State.OFF
var annotations: DotNpcAiNavAnnotations = null
var bake_ms: float = 0.0
var annotate_ms: float = 0.0
var from_cache: bool = false

## The chokes on a route, nearest the spawns first: `at`, `width`, `traffic`, `hold` (where to
## stand), `order` (0 spawn end, 1 post end), `fallback` (index of the next choke toward the
## post on the same route, -1 for the post itself), `overrun`, `routes`.
var chokes: Array[Dictionary] = []

## Every choke the annotator found, on a route or not, for the picture and the suite.
var all_chokes: Array[Dictionary] = []

## The routes the plan walked, spawn to post.
var routes: Array[PackedVector3Array] = []

## choke index -> how many different zombies have come within 4.5 m of it, for the suite.
var visited: Dictionary = {}

## choke index -> how many zombies were sent through it, ever, for the suite.
var chosen: Dictionary = {}

var _passed: Dictionary = {}

var _config = null
var _root: Node3D = null
var _world: World3D = null
var _mask: int = 0
var _seeds: PackedVector3Array = PackedVector3Array()
var _frame: int = 0
var _annotator: DotNpcAiNavAnnotator = null
var _started_ms: int = 0

## npc key -> {"at": choke index or -1, "seen": time}
var _assigned: Dictionary = {}
var _load: Dictionary = {}
var _time: float = 0.0
var _next_scan: float = 0.0

## The drops this map gave, as graph-free pairs, so a rebuilt graph (a gate opened) gets them again.
var _drops: Array = []
var _climbs: Array = []

## The graph the plan last used and what it was given, so the picture can say.
var drops_applied: int = 0
var climbs_applied: int = 0


## Starts: bakes and annotates [param root]'s colliders once the physics space has them.
func begin(config, root: Node3D, mask: int, seeds: PackedVector3Array) -> void:
	_config = config
	_root = root
	_world = root.get_world_3d() if root != null else null
	_mask = mask
	_seeds = seeds
	_frame = Engine.get_physics_frames()
	_started_ms = Time.get_ticks_msec()
	state = State.WAITING if _world != null and root != null and bool(config.nav_notes) else State.OFF


## Cancels everything and forgets the map.
func clear() -> void:
	state = State.OFF
	annotations = null
	chokes.clear()
	all_chokes.clear()
	routes.clear()
	visited.clear()
	_passed.clear()
	chosen.clear()
	_assigned.clear()
	_load.clear()
	_drops.clear()
	_climbs.clear()
	_annotator = null
	_root = null
	_world = null
	drops_applied = 0
	climbs_applied = 0


func is_ready() -> bool:
	return state == State.READY


## Advances the work by one tick. Returns true on the tick the annotations arrive, which is when
## the caller should [method plan].
func tick() -> bool:
	match state:
		State.WAITING:
			# Two physics frames: the first moves the colliders into the space, the second is the
			# margin a stand-alone suite needs.
			if Engine.get_physics_frames() < _frame + 2 or not _root.is_inside_tree():
				return false

			return _bake()
		State.ANNOTATING:
			var began := Time.get_ticks_usec()

			# At least one slice, then until the tick's share is spent: a big map's slice is
			# several milliseconds and six of them a tick were a visible stall.
			while _annotator.step():
				if Time.get_ticks_usec() - began > SLICE_BUDGET_US:
					break

			if _annotator.is_settled():
				return _annotated()

	return false


func _bake() -> bool:
	var bot := DotBotNav.new()
	var baked := bot.bake(_root, {"radius": 0.35, "height": 1.8, "climb": 0.4}, _mask)

	if not baked.ok:
		DotLog.warn(CHANNEL, "navigation notes: the bake failed", {"why": baked.error.message})
		state = State.FAILED
		return false

	bake_ms = bot.bake_ms
	var mesh := bot.mesh
	var annotator := DotNpcAiNavAnnotator.new(mesh, _world)
	annotator.agent_radius = 0.35
	annotator.stand_height = 1.8
	annotator.climb = 0.4
	annotator.jump_up = 1.0
	annotator.drop_max = float(_config.nav_drop_max)
	annotator.choke_width = choke_width
	annotator.choke_traffic = choke_traffic
	annotator.routes = choke_routes
	annotator.collision_mask = _mask
	annotator.seeds = _seeds
	annotator.reach_only = false
	annotator.slice = 24
	var key := annotator.cache_key()
	var path := "user://nav/%s.json" % key
	var loaded := DotNpcAiNavAnnotations.load_file(path, key)

	if loaded.ok:
		annotations = loaded.value
		from_cache = true
		state = State.READY
		_started_ms = Time.get_ticks_msec()
		return true

	_annotator = annotator
	state = State.ANNOTATING
	_started_ms = Time.get_ticks_msec()
	return false


func _annotated() -> bool:
	if _annotator.result == null or not _annotator.result.ok:
		DotLog.warn(CHANNEL, "navigation notes: the annotation failed", {
			"why": _annotator.result.error.message if _annotator.result != null else "no result"})
		state = State.FAILED
		return false

	annotations = _annotator.annotations
	annotate_ms = float(annotations.stats.get("ms", 0.0))
	DirAccess.make_dir_recursive_absolute("user://nav")
	var saved := annotations.save("user://nav/%s.json" % annotations.key)

	if not saved.ok:
		DotLog.debug(CHANNEL, "navigation notes: not cached", {"why": saved.error.message})

	_annotator = null
	state = State.READY
	return true


# --- The plan ----------------------------------------------------------------------------------

## Works out the drops, the routes and the chokes on them. [param graph] is the zombies' graph
## (`ZzNavGraph`), [param zombie_spawns] where the horde comes from, [param posts] what the
## survivors hold.
func plan(graph, zombie_spawns: PackedVector3Array, posts: PackedVector3Array) -> void:
	if state != State.READY or annotations == null:
		return

	_collect_links()
	apply_links(graph)
	all_chokes = annotations.chokepoints.duplicate()
	chokes.clear()
	routes.clear()

	if all_chokes.is_empty() or posts.is_empty() or zombie_spawns.is_empty():
		return

	var saved_filter = graph.filter
	graph.filter = null
	var origins := _sample(zombie_spawns, 6)
	var homes := _sample(posts, 6)

	for o: Vector3 in origins:
		for h: Vector3 in homes:
			var path: PackedVector3Array = graph.find_path(o, h, 2.5, true)

			if path.size() >= 3 and not graph.last_partial:
				routes.append(path)

	graph.filter = saved_filter
	var found: Dictionary = {}
	var order_sum: Dictionary = {}
	var passes: Array = []

	for r in routes.size():
		var path := routes[r]
		var along := PackedFloat32Array()
		along.append(0.0)

		for i in range(1, path.size()):
			along.append(along[i - 1] + path[i].distance_to(path[i - 1]))

		var total := maxf(along[along.size() - 1], 0.001)
		var here: Array = []

		for ci in all_chokes.size():
			var at: Vector3 = all_chokes[ci]["at"]
			var best := INF
			var best_i := -1

			for i in path.size():
				var d := Vector2(path[i].x - at.x, path[i].z - at.z).length()

				if d < best and absf(path[i].y - at.y) < 2.5:
					best = d
					best_i = i

			if best_i >= 0 and best <= ON_ROUTE:
				found[ci] = int(found.get(ci, 0)) + 1
				order_sum[ci] = float(order_sum.get(ci, 0.0)) + along[best_i] / total
				here.append([along[best_i], ci])

		here.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		passes.append(here)

	var picked: Array = found.keys()
	picked.sort_custom(func(a: int, b: int) -> bool: return int(found[a]) > int(found[b]))

	if picked.size() > MAX_CHOKES:
		picked.resize(MAX_CHOKES)

	picked.sort_custom(func(a: int, b: int) -> bool:
		return float(order_sum[a]) / float(found[a]) < float(order_sum[b]) / float(found[b]))

	var index_of: Dictionary = {}

	for ci: int in picked:
		var c: Dictionary = all_chokes[ci]
		index_of[ci] = chokes.size()
		chokes.append({
			"at": c["at"], "width": float(c["width"]), "traffic": float(c["traffic"]),
			"order": float(order_sum[ci]) / float(found[ci]), "routes": int(found[ci]),
			"hold": Vector3.INF, "fallback": -1, "overrun": false, "source": ci,
		})

	# The next choke toward the post on the same route, and the place to stand behind each.
	for r in routes.size():
		var path := routes[r]
		var here: Array = passes[r]

		for k in here.size():
			var ci: int = here[k][1]

			if not index_of.has(ci):
				continue

			var entry: Dictionary = chokes[index_of[ci]]

			if entry["hold"] == Vector3.INF:
				entry["hold"] = _stand_behind(graph, path, float(here[k][0]), entry["at"])

			if int(entry["fallback"]) < 0:
				for j in range(k + 1, here.size()):
					var next_ci: int = here[j][1]

					if index_of.has(next_ci) and index_of[next_ci] != index_of[ci]:
						entry["fallback"] = index_of[next_ci]
						break

	DotLog.info(CHANNEL, "navigation notes planned", {
		"routes": routes.size(), "chokes": chokes.size(), "found": all_chokes.size(),
		"drops": drops_applied, "climbs": climbs_applied,
	})


func _sample(list: PackedVector3Array, count: int) -> PackedVector3Array:
	if list.size() <= count:
		return list

	var out := PackedVector3Array()

	for i in count:
		out.append(list[i * list.size() / count])

	return out


## The place to stand [constant HOLD_BEHIND] metres on from the choke along its route, moved to a
## covered spot nearby that hides a crouched body from the choke when there is one.
func _stand_behind(graph, path: PackedVector3Array, along_choke: float, choke_at: Vector3) -> Vector3:
	var walked := 0.0
	var behind := path[path.size() - 1]

	for i in range(1, path.size()):
		walked += path[i].distance_to(path[i - 1])

		if walked >= along_choke + HOLD_BEHIND:
			behind = path[i]
			break

	var best := behind

	for spot in annotations.cover_from(choke_at, behind, COVER_WITHIN, "low"):
		var at: Vector3 = spot["at"]
		var gap := Vector2(at.x - choke_at.x, at.z - choke_at.z).length()

		if gap < 2.5 or gap > 9.0 or absf(at.y - behind.y) > 1.2:
			continue

		if graph.data.is_navigable(at, 1.0):
			best = at
			break

	return best


# --- Links on the graph -------------------------------------------------------------------------

func _collect_links() -> void:
	_drops.clear()
	_climbs.clear()

	for link in annotations.links:
		var kind := int(link["kind"])

		if kind == DotNpcAiNavAnnotations.LINK_DROP:
			_drops.append([link["from"], link["to"]])
		elif kind == DotNpcAiNavAnnotations.LINK_JUMP_UP:
			_climbs.append([link["from"], link["to"]])


## Puts the drops (and, for `zz_zombie_climb`, the jump ups) on [param graph] again: a gate that
## opens rebuilds the graph and the links go with the old one.
func apply_links(graph) -> void:
	drops_applied = 0
	climbs_applied = 0

	if not graph.has_method(&"add_drop"):
		return

	graph.allow_climb = bool(_config.zombie_climb)

	if bool(_config.zombie_drops):
		for pair: Array in _drops:
			var high: int = _point_at(graph, pair[0])
			var low: int = _point_at(graph, pair[1])

			if high >= 0 and low >= 0 and high != low and absf(graph.data.points[high].y - graph.data.points[low].y) > 0.8:
				graph.add_drop(high, low)
				drops_applied += 1

	for pair: Array in _climbs:
		var low: int = _point_at(graph, pair[0])
		var high: int = _point_at(graph, pair[1])

		if high >= 0 and low >= 0 and high != low:
			graph.add_climb(low, high)
			climbs_applied += 1

	graph.relabel()


func _point_at(graph, at: Vector3) -> int:
	return graph.data.nearest_point_where(at, 1.6, func(i: int) -> bool:
		return absf(graph.data.points[i].y - at.y) < 0.9)


# --- Asking -------------------------------------------------------------------------------------

## Where the stand-in in [param seat] should hold: the place behind its choke, or the next choke
## toward the post while its own is overrun. INF for none (use the post).
func hold_for(seat: int) -> Vector3:
	if chokes.is_empty():
		return Vector3.INF

	var i := seat % chokes.size()
	var lap := seat / chokes.size()
	var guard := chokes.size()

	while i >= 0 and bool(chokes[i]["overrun"]) and guard > 0:
		i = int(chokes[i]["fallback"])
		guard -= 1

	if i < 0:
		return Vector3.INF

	var at: Vector3 = chokes[i]["hold"]

	if at == Vector3.INF:
		return at

	if lap > 0:
		var angle := float(lap) * 2.39996
		at += Vector3(cos(angle), 0.0, sin(angle)) * 1.4

	return at


## The index of the choke [param seat] holds now, -1 for none.
func held_by(seat: int) -> int:
	if chokes.is_empty():
		return -1

	var i := seat % chokes.size()
	var guard := chokes.size()

	while i >= 0 and bool(chokes[i]["overrun"]) and guard > 0:
		i = int(chokes[i]["fallback"])
		guard -= 1

	return i


## Where a zombie keyed [param key] at [param from] should go on its way to [param goal]: a choke
## it was given, the least used of those on the way, until it is through; the goal when none.
func waypoint_for(key: int, from: Vector3, goal: Vector3) -> Vector3:
	if state != State.READY or chokes.is_empty():
		return goal

	var entry: Variant = _assigned.get(key)

	if entry == null:
		entry = {"at": _choose(from, goal), "seen": _time}
		_assigned[key] = entry
		var first: int = entry["at"]

		if first >= 0:
			_load[first] = int(_load.get(first, 0)) + 1
			chosen[first] = int(chosen.get(first, 0)) + 1

	entry["seen"] = _time
	var i: int = entry["at"]

	if i < 0:
		return goal

	var at: Vector3 = chokes[i]["at"]
	var gap := Vector2(from.x - at.x, from.z - at.z).length()

	# Through it: nearer the goal than the choke is, or at it.
	if gap < 3.5 or Vector2(from.x - goal.x, from.z - goal.z).length() < Vector2(at.x - goal.x, at.z - goal.z).length():
		_release(key, entry)
		entry["at"] = -1
		return goal

	return at


func _choose(from: Vector3, goal: Vector3) -> int:
	var direct := Vector2(from.x - goal.x, from.z - goal.z).length()

	# Near its quarry a zombie just goes.
	if direct < 14.0:
		return -1

	var best := -1
	var best_score := INF

	for i in chokes.size():
		var at: Vector3 = chokes[i]["at"]
		var there := Vector2(from.x - at.x, from.z - at.z).length()
		var onward := Vector2(at.x - goal.x, at.z - goal.z).length()

		# A detour of a third and eight metres at most, and it must lie ahead.
		if there + onward > direct * 1.33 + 8.0 or onward > direct:
			continue

		var score := float(_load.get(i, 0)) * 6.0 + (there + onward - direct)

		if score < best_score:
			best_score = score
			best = i

	return best


func _release(key: int, entry: Dictionary) -> void:
	var i: int = entry["at"]

	if i >= 0:
		_load[i] = maxi(int(_load.get(i, 0)) - 1, 0)

	_assigned[key] = entry


## Zombies that have a choke they have not reached, per choke index, for the suite.
func assigned_counts() -> Dictionary:
	var out: Dictionary = {}

	for key in _assigned:
		var i: int = _assigned[key]["at"]

		if i >= 0:
			out[i] = int(out.get(i, 0)) + 1

	return out


## Once a tick, from the horde: forgets zombies not asked about for a while, and reads which
## chokes are overrun.
func update(delta: float, horde) -> void:
	_time += delta

	if state != State.READY or chokes.is_empty() or _time < _next_scan:
		return

	_next_scan = _time + 0.5
	var limit := int(_config.bot_hold_overrun)

	for key in _assigned.keys():
		var entry: Dictionary = _assigned[key]

		if _time - float(entry["seen"]) > 2.0:
			_release(key, entry)
			_assigned.erase(key)

	for i in chokes.size():
		var near: Array = horde.zombies_near(chokes[i]["at"], 4.5)

		if not near.is_empty():
			var who: Dictionary = _passed.get(i, {})

			for npc in near:
				who[npc.instance_id] = true

			_passed[i] = who
			visited[i] = who.size()

		var over: bool = bool(chokes[i]["overrun"])
		chokes[i]["overrun"] = near.size() >= limit or (over and near.size() > limit / 2)


func describe() -> Dictionary:
	return {
		"state": State.keys()[state], "chokes": chokes.size(), "found": all_chokes.size(),
		"routes": routes.size(), "drops": drops_applied, "climbs": climbs_applied,
		"bake_ms": snappedf(bake_ms, 0.1), "annotate_ms": annotate_ms, "cached": from_cache,
	}
