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

var _space: PhysicsDirectSpaceState3D
var _query := PhysicsShapeQueryParameters3D.new()


## Returns (points dropped, edges dropped); (0, 0) when the world has no collision to ask.
static func apply(nav: DotNpcNavData, space: PhysicsDirectSpaceState3D, mask: int) -> Vector2i:
	var pruner := new()
	pruner._setup(space, mask)
	var dropped := nav.prune(pruner._point_blocked, pruner._edge_blocked)

	if dropped != Vector2i.ZERO:
		DotLog.info(CHANNEL, "navigation points the world's collision blocks were dropped", {"points": dropped.x, "edges": dropped.y})

	return dropped


## The same test for a link added after the prune (a drop or a jump up): `func(a: Vector3, b: Vector3) -> bool`.
static func edge_test(space: PhysicsDirectSpaceState3D, mask: int) -> Callable:
	var pruner := new()
	pruner._setup(space, mask)
	# A lambda holds the pruner; a bound method would leave the Callable dangling once this returns.
	return func(a: Vector3, b: Vector3) -> bool: return pruner._edge_blocked(a, b)


func _setup(space: PhysicsDirectSpaceState3D, mask: int) -> void:
	_space = space
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS + MARGIN
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
