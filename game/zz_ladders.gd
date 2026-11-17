extends RefCounted
## Which of the map's ladders a zombie climbs, and how high: the horde's answers to the brain's per-steer questions,
## over the ladder boxes (`ZzHorde.ladders`) and the climb speed (`zz_zombie_ladder_speed`, 0 for ladders off).

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

## How far a body's centre may stand off a ladder's box (beside it, metres) and climb it: a brute's radius and a bit.
const TOUCH := 1.0

## How far off a ladder (flat, metres) a zombie whose next corner is above makes for the ladder first: the graph joins a
## ladder to points this far from it (`ZzNavGraph.LADDER_COLUMN`).
const APPROACH := 3.0

## How far above a ladder's top a zombie climbs to reach the corner it is going to: the lip of the deck a short ladder
## stops under, which a player jumps the last of.
const OVER := 1.6


## The ladder (an index into [param boxes]) a zombie at [param here] whose next corner is [param goal] goes up: within
## [constant APPROACH] of it, between its foot and its top, with the corner over a step above. -1 for none, and always
## with ladders off ([param speed] 0).
static func find(boxes: Array[AABB], speed: float, here: Vector3, goal: Vector3) -> int:
	if speed <= 0.0 or goal == Vector3.INF or goal.y - here.y <= ZzZombieBody.STEP_UP:
		return -1

	var best := -1
	var nearest := INF

	for i in boxes.size():
		var box := boxes[i]

		if here.y < box.position.y - 1.0 or here.y > box.end.y:
			continue

		var off := flat_off(box, here)

		if off <= APPROACH and off < nearest:
			nearest = off
			best = i

	return best


## Whether a body at [param here] is close enough to [param box] to climb it.
static func touching(box: AABB, here: Vector3) -> bool:
	return flat_off(box, here) <= TOUCH


## The height a zombie on [param box] climbs to for its next corner [param goal]: the corner's, no higher than
## [constant OVER] over the ladder's top.
static func top(box: AABB, goal: Vector3) -> float:
	return minf(goal.y + 0.1, box.end.y + OVER)


## Flat metres from [param box] to [param p] (0 inside it).
static func flat_off(box: AABB, p: Vector3) -> float:
	var dx := maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0)
	var dz := maxf(maxf(box.position.z - p.z, p.z - box.end.z), 0.0)
	return Vector2(dx, dz).length()
