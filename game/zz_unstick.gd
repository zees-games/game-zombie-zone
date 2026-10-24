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

	# `test_move` at the destination only asks whether the body fits THERE, so a wedged zombie
	# tearing at a 0.14 m barricade was once nudged clean through the boards. Rays at knee and chest
	# height catch a thin wall without refusing the sill or chamfer a swept shape clips.
	if walled_off(body, body.global_transform.origin, lifted.origin - Vector3(0.0, 0.08, 0.0)):
		return false

	# And ground within a step below, so a nudge is never off a ledge.
	if not body.test_move(lifted, Vector3(0.0, -0.6, 0.0)):
		return false

	body.global_transform = lifted
	return true


## Whether something solid lies between [param from] and [param to] at knee or chest height.
static func walled_off(body: CharacterBody3D, from: Vector3, to: Vector3) -> bool:
	var space := body.get_world_3d().direct_space_state

	for height: float in [0.4, 1.2]:
		var query := PhysicsRayQueryParameters3D.create(from + Vector3(0.0, height, 0.0),
			to + Vector3(0.0, height, 0.0), body.collision_mask, [body.get_rid()])

		if not space.intersect_ray(query).is_empty():
			return true

	return false


## Puts [param body] on the clear, grounded spot within a few metres that is nearest
## [param goal], when that is closer to it than the body is. The last resort after [method nudge]:
## it moves farther, so it only takes a spot the body fits on, not over a drop, and in sight of here through no wall. Returns whether it moved.
static func relocate(body: CharacterBody3D, goal: Vector3) -> bool:
	if body == null:
		return false

	var here := body.global_transform.origin
	var best := Vector3.INF
	var best_d := here.distance_to(goal) - 0.5

	for radius: float in [1.5, 2.5, 3.5]:
		for i in 12:
			var a := TAU * float(i) / 12.0
			var to := body.global_transform
			to.origin = here + Vector3(cos(a), 0.0, sin(a)) * radius + Vector3(0.0, 0.08, 0.0)

			if body.test_move(to, Vector3.ZERO) or not body.test_move(to, Vector3(0.0, -0.6, 0.0)):
				continue

			if walled_off(body, here, to.origin - Vector3(0.0, 0.08, 0.0)):
				continue

			var d := to.origin.distance_to(goal)

			if d < best_d:
				best_d = d
				best = to.origin

	if best == Vector3.INF:
		return false

	var moved := body.global_transform
	moved.origin = best
	body.global_transform = moved
	return true
