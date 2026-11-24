extends RefCounted
## Floors under a ladder's ends that the document's nav floors leave out. A map's converted floors can miss a whole
## level (zs_krusty_krab_large: a sump at -15.85, a room at -8.84, a landing at -5.8) while the solid slab it stands
## on is in `boxes`; with no floor the grid has no point there, so a ladder to it joins nothing. For each ladder end
## with no floor in reach, the tops of the slabs around it become floors, as if the converter had listed them.

const ZzMapDoc := preload("zz_map_doc.gd")

## How far (m) off a ladder end a slab may lie and be its floor.
const REACH := 3.0
## How far (m) off a ladder end a listed floor may lie and be its floor already.
const HAVE_REACH := 2.0
## How far (m) a slab top may stand below the ladder's foot or head and still be what the climber steps off onto.
const DEPTH := 1.5
## How far (m) a slab top may stand above the foot or head.
const RISE := 0.5
## The smallest slab (m, each side of the top) taken for a floor: a step or a ledge is not.
const MIN_SIDE := 1.0
## Shrunk off each edge of a slab top (m), where a wall's face or a kerb stands.
const INSET := 0.1


## The document's nav floors plus the rows under the ladder ends they leave bare. [param bounds_of] turns a box
## record into its AABB.
static func with_rows(doc: Dictionary, open_gates: PackedStringArray, bounds_of: Callable) -> Array:
	var nav_doc: Dictionary = doc.get("nav", {})
	var floors: Array = (nav_doc.get("floors", []) as Array).duplicate()

	if not nav_doc.has("ladders"):
		return floors

	var slabs: Array[AABB] = []

	for box: Dictionary in doc.get("boxes", []):
		if not bool(box.get("solid", true)) or ZzMapDoc.is_trim(box) or box.has("nav") or str(box.get("kind", "")) == "sky":
			continue

		if box.has("gate") and open_gates.has(str(box["gate"])):
			continue

		slabs.append(bounds_of.call(box))

	floors.append_array(rows(nav_doc["ladders"], floors, slabs))
	return floors


## Floor rows `[min_x, min_z, max_x, max_z, y]` (the document's format) for the ladder ends in [param ladders] (rows of
## `[x, foot_y, z, x, head_y, z]`) that no row of [param floors] reaches, from the solid boxes of [param boxes]
## (their bounds).
static func rows(ladders: Array, floors: Array, boxes: Array[AABB]) -> Array:
	var out: Array = []

	for ladder: Array in ladders:
		for end in [Vector3(ladder[0], ladder[1], ladder[2]), Vector3(ladder[3], ladder[4], ladder[5])]:
			if _has_floor(end, floors) or _has_floor(end, out):
				continue

			for bounds in boxes:
				var top := bounds.end.y

				if top > end.y + RISE or top < end.y - DEPTH:
					continue

				if bounds.size.x < MIN_SIDE or bounds.size.z < MIN_SIDE or _flat_distance(bounds, end) > REACH:
					continue

				if _has_row(out, bounds):
					continue

				out.append([bounds.position.x + INSET, bounds.position.z + INSET, bounds.end.x - INSET, bounds.end.z - INSET, top])

	return out


static func _has_floor(end: Vector3, floors: Array) -> bool:
	for f: Array in floors:
		if end.y - DEPTH <= float(f[4]) and float(f[4]) <= end.y + RISE \
				and end.x >= float(f[0]) - HAVE_REACH and end.x <= float(f[2]) + HAVE_REACH \
				and end.z >= float(f[1]) - HAVE_REACH and end.z <= float(f[3]) + HAVE_REACH:
			return true

	return false


static func _has_row(rows_so_far: Array, bounds: AABB) -> bool:
	for f: Array in rows_so_far:
		if absf(float(f[4]) - bounds.end.y) < 0.01 and absf(float(f[0]) - (bounds.position.x + INSET)) < 0.01 and absf(float(f[1]) - (bounds.position.z + INSET)) < 0.01:
			return true

	return false


static func _flat_distance(bounds: AABB, at: Vector3) -> float:
	var dx := maxf(maxf(bounds.position.x - at.x, at.x - bounds.end.x), 0.0)
	var dz := maxf(maxf(bounds.position.z - at.z, at.z - bounds.end.z), 0.0)
	return sqrt(dx * dx + dz * dz)
