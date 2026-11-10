extends DotNpcNavGraph

## The zombies' graph with the one thing the grid cannot say: a way that only goes one way.
##
## [b]Why a subclass and not edges in the data.[/b] dot-npc's edge list is undirected by
## declaration, and a drop is not: a zombie steps off a balcony and cannot step back up it. A
## graph that let it would route a horde to the foot of a wall and leave it pushing on the
## brick. So the drops (`ZzNavNotes`, from dot-npc-ai's annotations) live here, beside the
## adjacency, and are read three ways:
##
## [codeblock]
## a zombie        every drop, downward only (jump ups too, both ways, when `allow_climb`)
## a stand-in      none: it walks the stairs the map has, and never falls off a balcony
## [/codeblock]
##
## Which of the two is asking is the filter the spawner sets per search (`filter`), never a flag
## on the graph, for the reason dot-npc gives for filters: one graph serves everybody.

## The filter a stand-in's search sets: no link at all. Its avoid cost is a number nothing else
## uses, so the native search keeps a graph of its own for it (dot-npc keys them by signature).
var bot_filter: DotNpcNavFilter = null

## Whether a zombie may climb the jump ups (`zz_zombie_climb`). A body that jumps a metre and a
## quarter would; the zombies do not, so a tower is defensible.
var allow_climb: bool = false:
	set(value):
		if value != allow_climb:
			allow_climb = value
			_native.clear()
			_patched.clear()

			# Which piece walks to which changed with it.
			if not _component.is_empty():
				_label_components()

## A plain edge that rises more than this is a drop seen from above: the importer's links join two levels with one undirected
## edge, and a zombie cannot step back up a 2 m drop (the ship's, where commons stood under it pressing at a wall). Down only,
## up only with [member allow_climb].
var steep: float = 1.2

## from index -> PackedInt32Array of the points one drop leads down to.
var _down: Dictionary = {}

## from index -> the points a jump up leads to (a climb).
var _up: Dictionary = {}

## Every point either end of a link touches, to ask quickly whether a point has one.
var _linked: Dictionary = {}

var _patched: Dictionary = {}

## filter -> the same without NARROW ([method _relaxed]).
var _relaxed_for: Dictionary = {}

## True while the native search's graph is being built: its plain edges are bidirectional, so the
## one-way links must not be in them (they are connected after, one way).
var _building: bool = false

## Set with [member _building] when the native graph is for a kind that obeys the steep rule.
var _steep_cut: bool = false

## Drops in this graph, for suites and describe.
var drop_count: int = 0
var up_count: int = 0

## Which piece a zombie walks to from which: a row per piece, a bit per piece, [member _reach_words] 64-bit words a row.
## Empty when no edge leaves any piece ([method _label_components]).
var _reach: PackedInt64Array = PackedInt64Array()
var _reach_words: int = 0


func _init(p_data: DotNpcNavData = null) -> void:
	bot_filter = DotNpcNavFilter.new()
	bot_filter.avoid_cost = 3.9
	straight_width_ratio = 0.5
	super(p_data)


## Half the width a smoothed leg must keep clear, in metres: a body is not a line. Smoothing
## cut across the corner of a door frame the graph goes round, and whoever followed it (a stand-in
## 100 s, a common 124 s) ended on the frame, pushing.
const LEG_FLANK := 0.35


## A leg is walkable when its centre line and both flanks are, not the line alone.
func can_walk_straight(a: Vector3, b: Vector3, corridor: float = -1.0) -> bool:
	if not super(a, b, corridor):
		return false

	var along := b - a
	along.y = 0.0

	if along.length() < 0.5:
		return true

	var side := Vector3(-along.z, 0.0, along.x).normalized() * LEG_FLANK
	return super(a + side, b + side, corridor) and super(a - side, b - side, corridor)


## The flag on a point a brute's body does not fit at; the brute's definition excludes it.
const NARROW := 1 << 12


## A brute's search that found nothing without the NARROW points is asked again with them: a brute that cannot path stands
## where it is, and a map whose only ways in are doors and furniture gaps would never be reached by one (a relocate and the
## unstick watch free it from a tight spot, nothing frees it from a path it does not have).
func find_path(from: Vector3, to: Vector3, snap_radius: float = -1.0, allow_partial: bool = false) -> PackedVector3Array:
	var out := super(from, to, snap_radius, allow_partial)

	if (not out.is_empty() and not last_partial) or filter == null or (filter.exclude_flags & NARROW) == 0:
		return out

	var first_partial := last_partial
	var kept := filter
	filter = _relaxed(kept)
	var again := super(from, to, snap_radius, allow_partial)
	filter = kept

	# A partial answer without the exclusion is better than none, not better than a whole one with it.
	if again.is_empty() or (not out.is_empty() and last_partial):
		last_partial = first_partial
		return out

	return again


## [method find_path]'s batch with the same second chance.
func find_paths(queries: Array, workers: int) -> void:
	super(queries, workers)
	var again: Array = []

	for q: DotNpcNavGraph.PathQuery in queries:
		if q.points.is_empty() and q.filter != null and (q.filter.exclude_flags & NARROW) != 0:
			var retry := DotNpcNavGraph.PathQuery.new()
			retry.from = q.from
			retry.to = q.to
			retry.filter = _relaxed(q.filter)
			retry.snap_radius = q.snap_radius
			retry.allow_partial = q.allow_partial
			retry.smooth = q.smooth
			retry.horizon = q.horizon
			again.append(retry)
			again.append(q)

	if again.is_empty():
		return

	var retries: Array = []

	for i in range(0, again.size(), 2):
		retries.append(again[i])

	super(retries, workers)

	for i in range(0, again.size(), 2):
		var q: DotNpcNavGraph.PathQuery = again[i + 1]
		q.points = (again[i] as DotNpcNavGraph.PathQuery).points
		q.partial = (again[i] as DotNpcNavGraph.PathQuery).partial


## [param base] without the NARROW exclusion, kept per base so the native search keeps one graph for it.
func _relaxed(base: DotNpcNavFilter) -> DotNpcNavFilter:
	if _relaxed_for.has(base):
		return _relaxed_for[base]

	var out := DotNpcNavFilter.new()
	out.area_costs = base.area_costs.duplicate()
	out.include_flags = base.include_flags
	out.exclude_flags = base.exclude_flags & ~NARROW
	out.avoid_cost = base.avoid_cost
	_relaxed_for[base] = out
	return out


## Flags every point where a body of [param radius] would overlap [param mask] (furniture packed
## into a classroom leaves gaps the graph walks through and a brute cannot). Returns how many.
func mark_narrow(space: PhysicsDirectSpaceState3D, mask: int, radius: float = 0.7, height: float = 2.1) -> int:
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(height, radius * 2.0 + 0.05)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = mask
	var count := 0

	if data.flags.size() != data.points.size():
		data.flags.resize(data.points.size())

	for i in data.points.size():
		query.transform = Transform3D(Basis.IDENTITY, data.points[i] + Vector3(0.0, 0.12 + shape.height * 0.5, 0.0))
		var narrow := not space.intersect_shape(query, 1).is_empty()
		var flags := data.flags[i]
		data.flags[i] = (flags | NARROW) if narrow else (flags & ~NARROW)
		count += 1 if narrow else 0

	_native.clear()
	_patched.clear()
	return count


## A drop from [param high] down to [param low]. Both are graph points. A zombie goes down it;
## nobody goes back up it.
func add_drop(high: int, low: int) -> void:
	_append(_down, high, low)
	_linked[high] = true
	_linked[low] = true
	drop_count += 1
	_native.clear()
	_patched.clear()


## A jump up from [param low] to [param high], which only a climbing zombie takes.
func add_climb(low: int, high: int) -> void:
	_append(_up, low, high)
	_linked[low] = true
	_linked[high] = true
	up_count += 1
	_native.clear()
	_patched.clear()


func has_links() -> bool:
	return drop_count > 0 or up_count > 0


## Labels the components again once every link is in: a drop can join two pieces of the map.
func relabel() -> void:
	_label_components()


## The pieces as a zombie walks them: points that reach each other BOTH ways, and [member _reach] says which piece leads to
## which. dot-npc's flood in point order is right for two-way edges and wrong here: a ledge whose top was numbered after its
## foot was "another piece" and the search refused the way down. They are the pieces of whoever [member filter] is.
func _label_components() -> void:
	var count := data.points.size()
	_component = PackedInt32Array()
	_component.resize(count)
	_component.fill(-1)
	_reach = PackedInt64Array()
	_reach_words = 0

	var edges: Array[PackedInt32Array] = []

	for i in count:
		edges.append(neighbours(i))

	var pieces := _strong_pieces(edges)

	if pieces > 1:
		_fill_reach(edges, pieces)


## Writes [member _component] as the strongly connected components of [param edges] (Tarjan's, as a walk of its own: the
## recursion would overflow on a 15 000 point map) and returns how many. A piece gets its number only after every piece
## it leads to.
func _strong_pieces(edges: Array[PackedInt32Array]) -> int:
	var count := edges.size()
	var order := PackedInt32Array()
	order.resize(count)
	order.fill(-1)
	var lowest := PackedInt32Array()
	lowest.resize(count)
	lowest.fill(0)
	var open := PackedByteArray()
	open.resize(count)
	open.fill(0)
	var trail := PackedInt32Array()
	var walk := PackedInt32Array()
	var walk_edge := PackedInt32Array()
	var stamp := 0
	var pieces := 0

	for root in count:
		if order[root] >= 0:
			continue

		order[root] = stamp
		lowest[root] = stamp
		stamp += 1
		trail.append(root)
		open[root] = 1
		walk.append(root)
		walk_edge.append(0)

		while not walk.is_empty():
			var depth := walk.size() - 1
			var at := walk[depth]
			var from_here: PackedInt32Array = edges[at]
			var edge := walk_edge[depth]

			if edge < from_here.size():
				walk_edge[depth] = edge + 1
				var next := from_here[edge]

				if order[next] < 0:
					order[next] = stamp
					lowest[next] = stamp
					stamp += 1
					trail.append(next)
					open[next] = 1
					walk.append(next)
					walk_edge.append(0)
				elif open[next] == 1:
					lowest[at] = mini(lowest[at], order[next])

				continue

			walk.resize(depth)
			walk_edge.resize(depth)

			if depth > 0:
				var parent := walk[depth - 1]
				lowest[parent] = mini(lowest[parent], lowest[at])

			if lowest[at] != order[at]:
				continue

			# [param at] is the first point of its piece the walk met: everything on the trail above it is the piece.
			while true:
				var member := trail[trail.size() - 1]
				trail.resize(trail.size() - 1)
				open[member] = 0
				_component[member] = pieces

				if member == at:
					break

			pieces += 1

	return pieces


## [member _reach] from the edges that cross from one piece to another.
func _fill_reach(edges: Array[PackedInt32Array], pieces: int) -> void:
	var leads_to: Array[Dictionary] = []

	for _i in pieces:
		leads_to.append({})

	var any := false

	for i in edges.size():
		var here := _component[i]

		for next in edges[i]:
			if _component[next] != here:
				leads_to[here][_component[next]] = true
				any = true

	# No edge between two pieces: the label alone answers, and a map of a thousand loose points keeps no table.
	if not any:
		return

	var words := (pieces + 63) >> 6
	var reach := PackedInt64Array()
	reach.resize(pieces * words)
	reach.fill(0)

	# A piece is closed only after every piece it leads to, so those have the lower numbers and their rows are whole.
	for piece in pieces:
		var row := piece * words
		reach[row + (piece >> 6)] |= 1 << (piece & 63)

		for below: int in leads_to[piece]:
			var other := below * words

			for w in words:
				reach[row + w] |= reach[other + w]

	_reach = reach
	_reach_words = words


## Whether a zombie at point [param a] can walk to point [param b]. One way, like its edges: the top of a ledge is
## connected to its foot, the foot is not connected to the top.
func connected(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= _component.size() or b >= _component.size():
		return false

	var from := _component[a]
	var to := _component[b]

	if from == to:
		return true

	if _reach.is_empty():
		return false

	return ((_reach[from * _reach_words + (to >> 6)] >> (to & 63)) & 1) == 1


func _append(into: Dictionary, from: int, to: int) -> void:
	var list: PackedInt32Array = into.get(from, PackedInt32Array())

	if list.has(to):
		return

	list.append(to)
	into[from] = list


## Whether [param a] to [param b] is a link edge of any kind, either way round.
func is_link(a: int, b: int) -> bool:
	var d: PackedInt32Array = _down.get(a, PackedInt32Array())

	if d.has(b):
		return true

	d = _down.get(b, PackedInt32Array())

	if d.has(a):
		return true

	var u: PackedInt32Array = _up.get(a, PackedInt32Array())
	return u.has(b) or (_up.get(b, PackedInt32Array()) as PackedInt32Array).has(a)


func neighbours(index: int) -> PackedInt32Array:
	var base := super(index)

	if filter == bot_filter and not _building:
		return base

	if _steep_cut or not _building:
		base = _without_steep(index, base, _steep_cut)

	if _building or not _linked.has(index) or filter == bot_filter:
		return base

	var out := base.duplicate()

	for to in _down.get(index, PackedInt32Array()) as PackedInt32Array:
		if not out.has(to):
			out.append(to)

	if allow_climb:
		for to in _up.get(index, PackedInt32Array()) as PackedInt32Array:
			if not out.has(to):
				out.append(to)

	return out


## [param base] without the edges from [param index] a zombie cannot take: up a rise over [member steep] (all steep ones
## when [param both], which the native build uses so it can connect the steep ones one way after).
func _without_steep(index: int, base: PackedInt32Array, both: bool) -> PackedInt32Array:
	var here := data.points[index].y
	var out := PackedInt32Array()
	var cut := false

	for to in base:
		var rise := data.points[to].y - here

		if (both and absf(rise) > steep) or (rise > steep and not allow_climb):
			cut = true
			continue

		out.append(to)

	return out if cut else base


## The native search's graph: [method super]'s (the plain edges), which has no link in it, plus
## the links as one-way segments.
func _native_for(with: DotNpcNavFilter) -> AStar3D:
	_building = true
	_steep_cut = with != bot_filter
	var astar: AStar3D = super(with)
	_building = false
	_steep_cut = false

	if with == bot_filter or _patched.has(astar.get_instance_id()):
		return astar

	_patched[astar.get_instance_id()] = true

	# The steep plain edges, downhill (and uphill with allow_climb), one way each.
	for i in data.points.size():
		var here := data.points[i].y

		for to in super.neighbours(i):
			var rise := data.points[to].y - here

			if rise < -steep or (rise > steep and allow_climb):
				astar.connect_points(i, to, false)

	for from: int in _down:
		for to in _down[from] as PackedInt32Array:
			astar.connect_points(from, to, false)

	if allow_climb:
		for from: int in _up:
			for to in _up[from] as PackedInt32Array:
				astar.connect_points(from, to, false)

	return astar
