extends RefCounted

## The physics questions of the navigation prune, asked ahead of it a slice a tick: does a body fit at each point, and
## along each edge between two points it fits at. On a 50 000 point map that is minutes of shape queries, which asked in
## one call froze the game at "Navigation regenerating 99%". The answers are the same queries the prune would make
## ([ZzNavPrune] reads them first and asks physics for anything missing), so the pruned graph is the same one.

const ZzNavPrune := preload("zz_nav_prune.gd")

## point -> blocked, and edge start -> {edge end -> blocked}.
var points := {}
var edges := {}
## The same for the body without its safety margin ([ZzNavPrune]'s loose tests).
var loose_points := {}
var loose_edges := {}
## While the prune is replayed to learn the rest of what it asks ([method want_point], [method want_edge]).
var recording := false
## Prune replays made, and the longest one in milliseconds (a replay is one call).
var replays := 0
var replay_ms := 0.0
## Shape queries asked so far.
var asked := 0
## The pruned copy the last replay made when it lacked no answer: that replay is the prune, done on a thread with nothing
## left to ask, so the graph takes it over ([method adopt_into]) instead of walking the whole prune again on the main thread.
var result: GSNpcNavData = null
var result_dropped := Vector2i.ZERO

var _nav: GSNpcNavData = null
var _space: PhysicsDirectSpaceState3D = null
var _mask := 0
var _passable: Array[RID] = []
var _ladders: Array[AABB] = []
var _required := PackedVector3Array()
var _tester: RefCounted = null
var _bare: RefCounted = null
## Questions the replay found unanswered: [kind (0 point, 1 edge), loose, a, b].
var _queue: Array = []
var _queue_at := 0
var _queued := {}
var _next := 0
var _in_edges := false
var _done := false
## The replay's thread: a replay is pure computation over the answers (an unanswered question is queued, not asked), and
## the main thread leaves the answers alone until it ends.
var _thread: Thread = null


func _init(nav: GSNpcNavData, space: PhysicsDirectSpaceState3D, mask: int, passable: Array[RID] = [], ladders: Array[AABB] = [], required: PackedVector3Array = PackedVector3Array()) -> void:
	nav.normalise_arrays()
	_nav = nav
	_space = space
	_mask = mask
	_passable = passable
	_ladders = ladders
	_required = required
	_tester = ZzNavPrune.strict(space, mask, passable)
	_bare = ZzNavPrune.strict(space, mask, passable, true)


func is_done() -> bool:
	return _done


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		cancel()


## Waits out a running replay (it holds no physics, so this is quick next to a build).
func cancel() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


## Puts the pruned graph the final replay made into [param nav] (the object the game already holds), in place.
func adopt_into(nav: GSNpcNavData) -> void:
	nav.points = result.points
	nav.edges = result.edges
	nav.areas = result.areas
	nav.flags = result.flags
	nav.cover_positions = result.cover_positions
	nav.cover_normals = result.cover_normals
	nav.cover_flags = result.cover_flags
	nav.meta = result.meta
	nav.invalidate_index()


## 0 to 1 over both passes.
func progress() -> float:
	if _done:
		return 1.0

	var total := float(_nav.points.size() + _nav.edges.size() / 2)
	var at := float(_next) if not _in_edges else float(_nav.points.size() + _next / 2)
	return clampf(at / maxf(total, 1.0), 0.0, 1.0)


## Asks for about [param budget_ms]; true when every point and edge is answered.
func step(budget_ms: float) -> bool:
	if _done:
		return true

	if _thread != null:
		if _thread.is_alive():
			return false

		_thread.wait_to_finish()
		_thread = null
		_done = _queue.is_empty()
		return _done

	var deadline := Time.get_ticks_usec() + int(maxf(budget_ms, 0.1) * 1000.0)
	var pts := _nav.points

	if not _in_edges:
		while _next < pts.size():
			points[pts[_next]] = _tester._hit(pts[_next])
			asked += 1
			_next += 1

			if _next % 32 == 0 and Time.get_ticks_usec() >= deadline:
				return false

		_in_edges = true
		_next = 0

	var list := _nav.edges

	while _next < list.size():
		var a := pts[list[_next]]
		var b := pts[list[_next + 1]]
		_next += 2

		if not points[a] and not points[b]:
			var row: Dictionary = edges.get(a, {})
			row[b] = _tester._edge_blocked_asked(a, b)
			edges[a] = row
			asked += 1

		if _next % 16 == 0 and Time.get_ticks_usec() >= deadline:
			return false

	return _learn(deadline)


## What the replay found it lacked, asked in slices; then the replay again, until it lacks nothing.
func _learn(deadline: int) -> bool:
	while _queue_at < _queue.size():
		var q: Array = _queue[_queue_at]
		_queue_at += 1
		var tester := _bare if q[1] else _tester

		if q[0] == 0:
			(loose_points if q[1] else points)[q[2]] = tester._hit(q[2])
		else:
			var table: Dictionary = loose_edges if q[1] else edges
			var row: Dictionary = table.get(q[2], {})
			row[q[3]] = tester._edge_blocked_asked(q[2], q[3])
			table[q[2]] = row

		asked += 1

		if _queue_at % 16 == 0 and Time.get_ticks_usec() >= deadline:
			return false

	_queue.clear()
	_queue_at = 0
	_queued.clear()
	_thread = Thread.new()
	_thread.start(_replay)
	return false


func want_point(p: Vector3, loose: bool) -> void:
	if not _queued.has([0, loose, p]):
		_queued[[0, loose, p]] = true
		_queue.append([0, loose, p, p])


func want_edge(a: Vector3, b: Vector3, loose: bool) -> void:
	if not _queued.has([1, loose, a, b]):
		_queued[[1, loose, a, b]] = true
		_queue.append([1, loose, a, b])


## The prune is run on a copy (on a thread: it is a whole walk of the graph), where an unanswered question is queued and
## answered "blocked" at no cost. Answers the strict point and edge passes did not cover (a slide off a blocked point, the
## loose body, a column beside a steep edge, a bridge between pieces) are found this way without this class knowing the
## prune's logic. A replay that queued nothing is the finished prune and is kept in [member result]. Ladders are joined
## later, on the main thread, since that asks physics rays.
func _replay() -> void:
	var began := Time.get_ticks_usec()
	recording = true
	var copy := _nav.duplicate(true) as GSNpcNavData
	var no_ladders: Array[AABB] = []
	var dropped := ZzNavPrune.apply(copy, _space, _mask, no_ladders, _required, _passable, self)
	recording = false
	replays += 1
	replay_ms = maxf(replay_ms, float(Time.get_ticks_usec() - began) / 1000.0)

	if _queue.is_empty():
		result = copy
		result_dropped = dropped
