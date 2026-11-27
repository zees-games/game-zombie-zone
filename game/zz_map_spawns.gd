extends RefCounted

## Where a map starts people: the start points it lists, which of them are on, and the ring round one when there are more
## people than points. Called by the map's `spawn` and `spawn_enabled`.

const ZzMapDoc := preload("zz_map_doc.gd")

## Where seat [param seat] of [param side] (`"survivors"`) starts:
## `[position, yaw]`. More people than spawns stand in rings round them, a metre and a bit
## apart, so nobody starts inside anybody else.
static func start(map: Node3D, side: String, seat: int) -> Array:
	var list: Array = (map.doc.get("spawns", {}) as Dictionary).get(side, [])
	# The map's start entities are listed once for every point, not once per point: a converted map's 64 starts each
	# scanning its thousands of entities held a stand-in's first walk to its start for half a second (headless_nav_stall).
	var points: Array = map.mechanics.spawn_entities() if map.mechanics != null else []
	var live := list.filter(func(entry: Dictionary) -> bool: return enabled(map, entry, points))
	# A map that disabled every start point still starts somebody.
	list = live if not live.is_empty() else list

	if list.is_empty():
		return [Vector3(0.0, 1.0, 0.0), 0.0]

	var base: Dictionary = list[seat % list.size()]
	var lap := seat / list.size()
	var at := ZzMapDoc.v3(base["at"])

	if lap > 0:
		var angle := float(lap) * 2.39996
		at += Vector3(cos(angle), 0.0, sin(angle)) * (1.1 * ceilf(float(lap) / 6.0))

	return [map.clear_spot(at), float(base.get("yaw", 0.0))]

## Whether a start point is on: the map's `info_player_*` entity says so live, else the document's `disabled`. Matched by name (the document keeps 64 characters of it); where several share a name, the one nearest the entry, else by standing within 0.75 m of it.
## [param points] is [method ZzMechanics.spawn_entities] when the caller already has it.
static func enabled(map: Node3D, entry: Dictionary, points: Variant = null) -> bool:
	if map.mechanics != null:
		var named := str(entry.get("name", ""))
		var at := ZzMapDoc.v3(entry["at"])
		var best: Dictionary = {}
		var best_d := INF
		var near: Dictionary = {}
		var near_d := 0.75

		for point: Dictionary in (points if points != null else map.mechanics.spawn_entities()):
			var o: Vector3 = point["origin"]
			var d := Vector2(o.x - at.x, o.z - at.z).length()

			if named != "" and str(point["name"]).strip_edges().left(64) == named:
				if d < best_d:
					best = point
					best_d = d

			elif d < near_d:
				near = point
				near_d = d

		if not best.is_empty():
			return bool(best["enabled"])

		if named == "" and not near.is_empty():
			return bool(near["enabled"])

	return not bool(entry.get("disabled", false))
