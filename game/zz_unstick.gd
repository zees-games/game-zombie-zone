extends RefCounted

## The last resort for a mover wedged where hopping does not help: a sill under a lintel, a
## chamfered corner the graph cut too fine. Stand-ins and commons both hop first; when the hop
## has failed more than once at the same place, this moves the body a little way along where it
## was going, if there is room to stand there.
##
## [b]A step, never a teleport to somewhere else.[/b] The distance is under a metre and the spot
## must be free for the body's own shape, and not over a drop, so the move is the one the body
## would have made had the geometry let it.

## How far one nudge goes, in metres.
const REACH := 0.7

## Moves [param body] [constant REACH] metres along [param direction] (flattened) when the shape
## fits there and the floor is under it. Returns whether it moved.
static func nudge(body: CharacterBody3D, direction: Vector3) -> bool:
	var flat := Vector3(direction.x, 0.0, direction.z)

	if body == null or flat.length() < 0.01:
		return false

	var to := body.global_transform
	to.origin += flat.normalized() * REACH

	# Lifted a little so the floor under it is not a collision, and the shape must be free there.
	var lifted := to
	lifted.origin.y += 0.08

	if body.test_move(lifted, Vector3.ZERO):
		return false

	# And ground within a step below, so a nudge is never off a ledge.
	if not body.test_move(lifted, Vector3(0.0, -0.6, 0.0)):
		return false

	body.global_transform = lifted
	return true
