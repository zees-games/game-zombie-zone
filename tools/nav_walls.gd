extends RefCounted
## Graph points that stand in a wall ("inwall") or on a wall's top ("ontop"), judged against the document's own boxes.

const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")

## A wall is at least this tall and at most this thick; a point at its top is on a wall top, not on a floor.
const WALL_HEIGHT := 1.5
const WALL_THICK := 1.0
## How far a box reaches past its faces in the builder (the document's default clearance), and the height a body steps onto.
const CLEARANCE := 0.3
const STEP := 0.35


## {"inwall": int, "ontop": int, "examples": Array of Vector3} for the points of [param nav] against [param doc]'s boxes.
static var _last := AABB()


static func count(nav: DotNpcNavData, doc: Dictionary) -> Dictionary:
	var solids: Array[AABB] = []

	for box: Dictionary in doc.get("boxes", []):
		if not bool(box.get("solid", true)) or ZzMapDoc.is_trim(box) or box.has("gate") or str(box.get("kind", "")) == "sky":
			continue

		if box.has("nav") and not bool(box["nav"]):
			continue

		solids.append(ZzNpcs._box_bounds(box))

	var inwall := 0
	var ontop := 0
	var examples: Array = []

	for p: Vector3 in nav.points:
		var kind := _judge(p, solids)

		if kind == "ontop" and _flush(nav, p, solids):
			continue

		if kind == "":
			continue

		inwall += 1 if kind == "inwall" else 0
		ontop += 1 if kind == "ontop" else 0

		if examples.size() < 10:
			examples.append("%s %s in %s" % [kind, p.snapped(Vector3.ONE * 0.1), _last])

	return {"inwall": inwall, "ontop": ontop, "examples": examples}


## A wall top with ground at its own height on both sides is part of the floor (a retaining wall flush with the yard).
static func _flush(nav: DotNpcNavData, p: Vector3, solids: Array[AABB]) -> bool:
	for box in solids:
		if absf(p.y - box.end.y) >= 0.15 or box.size.y < WALL_HEIGHT or minf(box.size.x, box.size.z) > WALL_THICK:
			continue

		if p.x < box.position.x - 0.05 or p.x > box.end.x + 0.05 or p.z < box.position.z - 0.05 or p.z > box.end.z + 0.05:
			continue

		var across := Vector3.RIGHT if box.size.x < box.size.z else Vector3.BACK
		var reach := minf(box.size.x, box.size.z) * 0.5 + 1.0

		for side in [-1.0, 1.0]:
			var near := nav.nearest_point(p + across * reach * side, 0.6)

			if near < 0 or absf(nav.points[near].y - p.y) > 0.3:
				return false

	return true


static func _judge(p: Vector3, solids: Array[AABB]) -> String:
	var found := ""

	for box in solids:
		if p.x < box.position.x - CLEARANCE or p.x > box.end.x + CLEARANCE or p.z < box.position.z - CLEARANCE or p.z > box.end.z + CLEARANCE:
			continue

		# The builder's own rule (a box blocks a point it reaches over, grown by the clearance), less the floor's own top and a step.
		if box.end.y - p.y > STEP and box.position.y < p.y + ZzNpcs.NAV_OVERHEAD:
			_last = box
			return "inwall"

		if absf(p.y - box.end.y) < 0.15 and box.size.y >= WALL_HEIGHT and minf(box.size.x, box.size.z) <= WALL_THICK \
				and p.x >= box.position.x - 0.05 and p.x <= box.end.x + 0.05 and p.z >= box.position.z - 0.05 and p.z <= box.end.z + 0.05:
			_last = box
			found = "ontop"

	return found
