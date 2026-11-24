extends RefCounted
## Seeds a nav point at the foot or head of a ladder the grid left without one. A ladder stands in a shaft or a wall niche
## its own width, narrower than the grid's clearance, so no grid point lands within reach of its foot or head and the
## climb joins nothing (zs_krusty_krab_large: 8 of 11 ladders). The seed stands just off a face of the ladder, where a
## body fits, on the ladder's side of its wall, and is joined to the nearest floor points in reach it can walk to.

## How far (m) off a ladder's face the seed stands: a zombie's radius and room to turn.
const OFFSET := 0.8
## How far (m) from the seed the floor points it is joined to may stand, and how many it is joined to.
const JOIN_REACH := 6.0
const JOIN_COUNT := 2
## How far (m) off the seed's height a floor point may stand and still be the same floor.
const JOIN_HEIGHT := 0.6


## The index of a new point at the foot ([param head] false) or head of [param box], joined to the floor around it, or -1 when
## no spot off its faces is clear (`point_blocked(p)`), on its side of its wall ([param side], may be invalid) and walkable to
## a floor point (`edge_blocked(a, b)`). Both blocked callables are the bare body's, from `ZzNavPrune`.
static func seed_end(nav: GSNpcNavData, box: AABB, head: bool, point_blocked: Callable, edge_blocked: Callable, side: Callable) -> int:
	var mid := box.get_center()
	var y := box.end.y if head else box.position.y + 0.03
	var half := Vector2(box.size.x, box.size.z) * 0.5
	var best := PackedInt32Array()
	var best_at := Vector3.ZERO
	var best_cost := INF

	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var at := Vector3(mid.x + dir.x * (half.x + OFFSET), y, mid.z + dir.y * (half.y + OFFSET))

		if point_blocked.call(at) or (side.is_valid() and not bool(side.call(box, at))):
			continue

		var joins := _joins(nav, at, edge_blocked)

		if joins.is_empty():
			continue

		var cost := at.distance_to(nav.points[joins[0]])

		if cost < best_cost:
			best = joins
			best_at = at
			best_cost = cost

	if best.is_empty():
		return -1

	var index := nav.add_point(best_at)

	for p in best:
		nav.connect_points(index, p)

	return index


## Up to [constant JOIN_COUNT] floor points near [param at], nearest first, that a body walks to from it.
static func _joins(nav: GSNpcNavData, at: Vector3, edge_blocked: Callable) -> PackedInt32Array:
	var near: Array[int] = []

	for p in nav.points_within(at, JOIN_REACH):
		if absf(nav.points[p].y - at.y) <= JOIN_HEIGHT:
			near.append(p)

	near.sort_custom(func(a: int, b: int) -> bool: return at.distance_squared_to(nav.points[a]) < at.distance_squared_to(nav.points[b]))
	var out := PackedInt32Array()

	for p in near:
		if not edge_blocked.call(at, nav.points[p]):
			out.append(p)

		if out.size() >= JOIN_COUNT:
			break

	return out
