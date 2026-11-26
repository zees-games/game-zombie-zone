extends RefCounted
## What the horde makes of a landed graph besides its search graph: the links (teleports, ladders), the posts a body can
## reach and the thinned spawn points. On the worker that built the graph when it can: on gm_valley these were 4 s of
## the landing tick. [method run] is the worker's half; the main thread falls back to the same calls for a missing key.

const ZzNpcs := preload("zz_npcs.gd")
const ZzNavPrune := preload("zz_nav_prune.gd")

## Metres between two kept spawn points.
const SPAWN_SPACING := 6.0


## Main thread: what [method run] needs, copied so the worker reads nothing the main thread may change.
static func rules(doc: Dictionary, steep: float, ladders_on: bool, boxes: Array[AABB]) -> Dictionary:
	var spawns: Dictionary = doc.get("spawns", {})
	return {
		"doc": {"posts": (doc.get("posts", []) as Array).duplicate(true), "spawns": {"survivors": (spawns.get("survivors", []) as Array).duplicate(true)}},
		"teleports": ((doc.get("nav", {}) as Dictionary).get("teleports", []) as Array).duplicate(true),
		"steep": steep, "ladders_on": ladders_on, "boxes": boxes.duplicate(),
	}


## The teleports and the ladders on [param graph]; [param side] is [method ZzNavPrune.ladder_side] over a space with the
## world's bodies.
static func link(graph: Object, rule: Dictionary, side: Callable) -> void:
	graph.steep = rule["steep"]
	var _teles: int = graph.apply_teleports(rule["teleports"])
	graph.allow_ladders = rule["ladders_on"]
	var boxes: Array[AABB] = rule["boxes"]
	var _rungs: int = graph.apply_ladders(boxes, side)


## Worker: the posts and spawn points of [param nav], and the links on [param graph] when [param space] holds the
## world's bodies (keys `posts`, `spawns`, `linked`). Bound to [method rules]'s result as [member ZzNavJob.derive].
static func run(nav: GSNpcNavData, graph: Object, space: PhysicsDirectSpaceState3D, mask: int, rule: Dictionary) -> Dictionary:
	var out := {}

	# Only a ladder asks the world which side it is on: with none the links go on here without a space.
	if graph != null and (space != null or (rule["boxes"] as Array).is_empty()):
		link(graph, rule, ZzNavPrune.ladder_side(space, mask))
		out["linked"] = true

		# After the links, which clear it: on the main thread this was the first tick of play's (1.3 to 1.8 s on gm_valley).
		if rule.get("warm_bots", false):
			graph.warm_bot_search()

	out["posts"] = ZzNpcs.reachable_posts(nav, rule["doc"])
	out["spawns"] = ZzNpcs.thinned_points(nav, SPAWN_SPACING, GSNpcNavFilter.walking_only())
	return out
