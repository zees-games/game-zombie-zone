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

## What a zombie body collides with that the graph must clear: world, prop and clip (a hull clip ceiling or a solid prop no document box describes).
static func body_mask(physics: Object) -> int:
	return physics.layer_mask(&"world") | physics.layer_mask(&"prop") | physics.layer_mask(&"clip")


var _space: PhysicsDirectSpaceState3D
var _query := PhysicsShapeQueryParameters3D.new()


## Returns (points dropped, edges dropped); (0, 0) when the world has no collision to ask. Each of
## [param ladders] is then joined foot to head: its shaft blocks the capsule, and the builder drops a ladder link
## whose ends a stair link already joined, which this prune may then cut.
static func apply(nav: DotNpcNavData, space: PhysicsDirectSpaceState3D, mask: int, ladders: Array[AABB] = []) -> Vector2i:
	var pruner := new()
	pruner._setup(space, mask, MARGIN)
	var bare := new()
	bare._setup(space, mask, 0.0)
	var prune := DotNpcNavPrune.new()
	prune.point_blocked = pruner._point_blocked
	prune.edge_blocked = pruner._edge_blocked
	# The margin is for smoothing; where only the bare body fits, that gap is still the way between two pieces.
	prune.loose_point_blocked = bare._point_blocked
	prune.loose_edge_blocked = bare._edge_blocked
	prune.nudge = NUDGE
	prune.climb = CLIMB
	var dropped := prune.apply(nav)
	var climbs := join_ladders(nav, ladders)

	if dropped != Vector2i.ZERO or prune.nudged > 0 or prune.joined_edges > 0 or climbs > 0:
		DotLog.info(CHANNEL, "navigation points the world's collision blocks were dropped", {"points": dropped.x, "edges": dropped.y, "nudged": prune.nudged, "joined_points": prune.joined_points, "joined_edges": prune.joined_edges, "ladders": climbs})

	return dropped


## Joins the floor points nearest each ladder's foot and head; returns how many ladders were joined.
static func join_ladders(nav: DotNpcNavData, ladders: Array[AABB]) -> int:
	var joined := 0

	for box in ladders:
		var mid := box.get_center()
		var a := _ladder_end(nav, Vector3(mid.x, box.position.y + 0.1, mid.z))
		var b := _ladder_end(nav, Vector3(mid.x, box.end.y, mid.z))

		if a >= 0 and b >= 0 and absf(nav.points[a].y - nav.points[b].y) > CLIMB and nav.connect_points(a, b).ok:
			joined += 1

	if joined > 0:
		nav.invalidate_index()

	return joined


static func _ladder_end(nav: DotNpcNavData, at: Vector3) -> int:
	return nav.nearest_point_where(at, LADDER_REACH, func(p: int) -> bool: return absf(nav.points[p].y - at.y) <= LADDER_HEIGHT)


## The same test for a link added after the prune (a drop or a jump up): `func(a: Vector3, b: Vector3) -> bool`.
static func edge_test(space: PhysicsDirectSpaceState3D, mask: int) -> Callable:
	var pruner := new()
	pruner._setup(space, mask, MARGIN)
	# A lambda holds the pruner; a bound method would leave the Callable dangling once this returns.
	return func(a: Vector3, b: Vector3) -> bool:
		return DotNpcNavPrune.level_change_blocked(pruner._edge_blocked, pruner._point_blocked, a, b, CLIMB)


func _setup(space: PhysicsDirectSpaceState3D, mask: int, margin: float) -> void:
	_space = space
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
