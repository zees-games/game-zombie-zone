extends RefCounted
## Drops the nav points and edges a zombie's body cannot occupy in the physics world. The builder only knows the
## boxes the document names; hulls and small props that no box describes are what this catches.

const CHANNEL := "zz.nav"
const RADIUS := 0.32
## Extra clearance so a smoothed leg that cuts a corner between two kept points still clears a thin post.
const MARGIN := 0.1
const HEIGHT := 1.75
## Feet lifted off the line: a stair tread or kerb is climbed, a hanging prop or a wall is not.
const LIFT := 0.3
## Metres between the samples along an edge: a post or slab thinner than the edge's midpoint gap still lands on one.
const EDGE_STEP := 0.25
## How far a point the margin blocks may slide; a grid point rarely lands where a doorway is widest.
const NUDGE := 0.3
## A rise or fall over this is a ledge or a ladder: crossed by a column beside the line, not along it.
const CLIMB := 0.6
## How far (m) from a ladder's foot or head, across and up or down, the point that ends its climb may stand.
const LADDER_REACH := 3.0
const LADDER_HEIGHT := 1.5
## How far over a ladder's head its end point may stand (`ZzHorde.LADDER_OVER`, which the climber goes on up to).
const LADDER_OVER := 1.6
## Heights (m) over a candidate end point of the flat rays that ask whether the ladder is on its side of the wall, from
## knee to head: a chain-link fence hung 1.07 m off the floor in front of a ladder lets the knee ray under it, and a
## zombie walked to that ladder climbed into the fence (zm_roy_the_ship, the ladders by the aft lower-deck bays).
const LADDER_SIDE_RISES: Array[float] = [0.5, 1.0, 1.6]
## How far (m) out from a ladder's middle, toward a head end over its top, the climber's column is tested for a deck above.
const LADDER_SIDE_FRONT := 0.35
## How far (m) in front of a ladder's face a wall hit still counts as the wall it is set in.
const LADDER_SIDE_SLACK := 0.01

## What a zombie body collides with that the graph must clear: world, prop and clip (a hull clip ceiling or a solid prop no document box describes).
static func body_mask(physics: Object) -> int:
	return physics.layer_mask(&"world") | physics.layer_mask(&"prop") | physics.layer_mask(&"clip")


var _space: PhysicsDirectSpaceState3D
var _query := PhysicsShapeQueryParameters3D.new()


## [param required] (spawns, posts) keeps a piece holding one joined to the next by a bridge edge even through a floor.
## Returns (points dropped, edges dropped); (0, 0) when there is no collision to ask. Each of [param ladders] is then
## joined foot to head, which this prune may cut; [param passable] bodies (doors that open to walkers) block nothing.
static func apply(nav: DotNpcNavData, space: PhysicsDirectSpaceState3D, mask: int, ladders: Array[AABB] = [], required: PackedVector3Array = PackedVector3Array(), passable: Array[RID] = []) -> Vector2i:
	var pruner := new()
	pruner._setup(space, mask, MARGIN, passable)
	var bare := new()
	bare._setup(space, mask, 0.0, passable)
	var prune := DotNpcNavPrune.new()
	prune.point_blocked = pruner._point_blocked
	prune.edge_blocked = pruner._edge_blocked
	# The margin is for smoothing; where only the bare body fits, that gap is still the way between two pieces.
	prune.loose_point_blocked = bare._point_blocked
	prune.loose_edge_blocked = bare._edge_blocked
	prune.nudge = NUDGE
	prune.climb = CLIMB
	prune.required = required
	var dropped := prune.apply(nav)
	var climbs := join_ladders(nav, ladders, ladder_side(space, mask, passable))

	if dropped != Vector2i.ZERO or prune.nudged > 0 or prune.joined_edges > 0 or prune.bridged_edges > 0 or climbs > 0:
		DotLog.info(CHANNEL, "navigation points the world's collision blocks were dropped", {"points": dropped.x, "edges": dropped.y, "nudged": prune.nudged, "joined_points": prune.joined_points, "joined_edges": prune.joined_edges, "bridged": prune.bridged_edges, "ladders": climbs})

	return dropped


## Joins the floor points nearest each ladder's foot and head; returns how many ladders were joined. With [param side]
## (from [method ladder_side]) an end is only a point on the ladder's side of the wall it is mounted on.
static func join_ladders(nav: DotNpcNavData, ladders: Array[AABB], side: Callable = Callable()) -> int:
	var joined := 0

	for box in ladders:
		var mid := box.get_center()
		var a := _ladder_end(nav, Vector3(mid.x, box.position.y + 0.1, mid.z), LADDER_HEIGHT, box, side)
		var b := _ladder_end(nav, Vector3(mid.x, box.end.y, mid.z), LADDER_OVER, box, side)

		if a >= 0 and b >= 0 and absf(nav.points[a].y - nav.points[b].y) > CLIMB and nav.connect_points(a, b).ok:
			joined += 1

	if joined > 0:
		nav.invalidate_index()

	return joined


static func _ladder_end(nav: DotNpcNavData, at: Vector3, over: float, box: AABB, side: Callable) -> int:
	return nav.nearest_point_where(at, LADDER_REACH, func(p: int) -> bool:
		var rise := nav.points[p].y - at.y
		return rise >= -LADDER_HEIGHT and rise <= over and (not side.is_valid() or bool(side.call(box, nav.points[p]))))


## `func(box: AABB, p: Vector3) -> bool`: whether graph point [param p] reaches ladder [param box] without a wall
## between them: flat rays [constant LADDER_SIDE_RISES] over p to the ladder's middle hit nothing in [param mask] before the ladder's face.
## A ladder bolted to the outside of a hull is otherwise joined to the floor inside it, and a zombie climbs the hull's
## inner face into the deck above (zm_roy_the_ship). A head end over the ladder's top also needs the climb's column open
## up to it: a ladder that stops under a closed deck is not a way onto that deck.
static func ladder_side(space: PhysicsDirectSpaceState3D, mask: int, passable: Array[RID] = []) -> Callable:
	if space == null or mask == 0:
		return Callable()

	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = mask
	query.exclude = passable
	return func(box: AABB, p: Vector3) -> bool:
		var mid := box.get_center()

		for rise: float in LADDER_SIDE_RISES:
			query.from = p + Vector3.UP * rise
			query.to = Vector3(mid.x, query.from.y, mid.z)
			var hit := space.intersect_ray(query)

			if hit.is_empty():
				continue

			# The wall a ladder is set in or against is hit at or past the ladder's face from its own side, before it from the other.
			var column := AABB(Vector3(box.position.x, query.from.y - 1.0, box.position.z), Vector3(box.size.x, 2.0, box.size.z)).grow(LADDER_SIDE_SLACK)
			var entry: Variant = column.intersects_segment(query.from, query.to)
			var face: Vector3 = entry if entry is Vector3 else query.from

			if query.from.distance_to(hit["position"] as Vector3) < query.from.distance_to(face):
				return false

		if p.y <= box.end.y:
			return true

		# A head end over the ladder's top (LADDER_OVER) is reached through the opening the ladder climbs into, not
		# through a deck: the column in front of the ladder, from its top to a head over p, hits nothing.
		var out := Vector3(p.x - mid.x, 0.0, p.z - mid.z)
		var front := Vector3(mid.x, 0.0, mid.z) + (out.normalized() * minf(out.length(), LADDER_SIDE_FRONT) if out.length() > 0.001 else Vector3.ZERO)
		query.from = Vector3(front.x, box.end.y - LADDER_SIDE_SLACK, front.z)
		query.to = Vector3(front.x, p.y + LADDER_SIDE_RISES[0], front.z)
		return space.intersect_ray(query).is_empty()


## The same test for a link added after the prune (a drop or a jump up): `func(a: Vector3, b: Vector3) -> bool`.
static func edge_test(space: PhysicsDirectSpaceState3D, mask: int, passable: Array[RID] = []) -> Callable:
	var pruner := new()
	pruner._setup(space, mask, MARGIN, passable)
	# A lambda holds the pruner; a bound method would leave the Callable dangling once this returns.
	return func(a: Vector3, b: Vector3) -> bool:
		return DotNpcNavPrune.level_change_blocked(pruner._edge_blocked, pruner._point_blocked, a, b, CLIMB)


func _setup(space: PhysicsDirectSpaceState3D, mask: int, margin: float, passable: Array[RID] = []) -> void:
	_space = space
	_query.exclude = passable
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS + margin
	shape.height = HEIGHT - LIFT
	_query.shape = shape
	_query.collision_mask = mask


func _point_blocked(p: Vector3) -> bool:
	return _hit(p)


func _edge_blocked(a: Vector3, b: Vector3) -> bool:
	var steps := int(ceil(a.distance_to(b) / EDGE_STEP))

	for i in range(1, steps):
		if _hit(a.lerp(b, float(i) / steps)):
			return true

	return false


func _hit(p: Vector3) -> bool:
	_query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (LIFT + (_query.shape as CapsuleShape3D).height * 0.5))
	return not _space.intersect_shape(_query, 1).is_empty()
