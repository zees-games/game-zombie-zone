extends RefCounted
## Drops the nav points and edges a zombie's body cannot occupy in the physics world. The builder only knows the
## boxes the document names; hulls and small props that no box describes are what this catches.

const CHANNEL := "zz.nav"
const RADIUS := 0.32
const HEIGHT := 1.75
## Feet lifted off the line: a stair tread or kerb is climbed, a hanging prop or a wall is not.
const LIFT := 0.3

var _space: PhysicsDirectSpaceState3D
var _query := PhysicsShapeQueryParameters3D.new()


## Returns (points dropped, edges dropped); (0, 0) when the world has no collision to ask.
static func apply(nav: DotNpcNavData, space: PhysicsDirectSpaceState3D, mask: int) -> Vector2i:
	var pruner := new()
	pruner._space = space
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS
	shape.height = HEIGHT - LIFT
	pruner._query.shape = shape
	pruner._query.collision_mask = mask
	var dropped := nav.prune(pruner._point_blocked, pruner._edge_blocked)

	if dropped != Vector2i.ZERO:
		DotLog.info(CHANNEL, "navigation points the world's collision blocks were dropped", {"points": dropped.x, "edges": dropped.y})

	return dropped


func _point_blocked(p: Vector3) -> bool:
	return _hit(p)


func _edge_blocked(a: Vector3, b: Vector3) -> bool:
	return _hit(a.lerp(b, 0.5))


func _hit(p: Vector3) -> bool:
	_query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (LIFT + (_query.shape as CapsuleShape3D).height * 0.5))
	return not _space.intersect_shape(_query, 1).is_empty()
