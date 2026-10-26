extends RefCounted

## The safety net under every survivor: one who falls below the map's floor plane, or who
## pushes against the world for [member stuck_seconds] without moving, is put back on the last ground they
## stood on. The map is meant not to need this (tools/fall_probe.gd finds the places that do); a net catches
## the ones a converted world still has.

const ZzMap := preload("zz_map.gd")

const CHANNEL := "zz.footing"
## A sample of safe ground is kept at most this often, and only after this much movement.
const SAMPLE_EVERY := 1.5
const SAMPLE_MOVE := 1.5
const KEEP := 5
## Progress under this many metres of flat travel counts as not moving.
const PROGRESS := 0.6
## Metres below the lowest floor that count as out of the map, when the kill height is deeper.
const FALL_DEPTH := 4.0

var rescued: int = 0

var _seen: Dictionary = {}


## One player's tick on the authority. Returns whether the player was moved.
func advance(game: Node, player: Object, delta: float) -> bool:
	var map: Object = game.get("map")
	if map == null or player.get("controller") == null:
		return false
	var config: Object = game.get("config")
	var fall_rescue: bool = config.get("fall_rescue")
	var stuck_seconds: float = config.get("stuck_rescue_seconds")
	var id: StringName = player.get("player_id")
	var rec: Dictionary = _seen.get(id, {})
	if rec.is_empty():
		rec = {"safe": [], "since": 0.0, "stuck": 0.0, "anchor": player.call(&"feet"), "warps": int(player.get("warps"))}
		_seen[id] = rec
	# A teleport that is not ours (a rescue, a respawn) restarts the watch.
	if int(player.get("warps")) != rec["warps"]:
		rec["warps"] = int(player.get("warps"))
		rec["anchor"] = player.call(&"feet")
		rec["stuck"] = 0.0

	var feet: Vector3 = player.call(&"feet")
	if not feet.is_finite() or (fall_rescue and out_of_map(map, feet)):
		return _put_back(game, player, rec, "fell" if feet.is_finite() else "not a number", feet)

	var state: Object = player.get("controller").get("state")
	var grounded: bool = state != null and int(state.get("ground_ticks")) > 0
	rec["since"] += delta
	var safe: Array = rec["safe"]
	if grounded and rec["since"] >= SAMPLE_EVERY and (safe.is_empty() or (safe[-1] as Vector3).distance_to(feet) >= SAMPLE_MOVE):
		rec["since"] = 0.0
		safe.append(feet)
		if safe.size() > KEEP:
			safe.pop_front()

	if stuck_seconds <= 0.0 or not bool(player.call(&"is_up")) or bool(player.call(&"is_pinned")):
		rec["stuck"] = 0.0
		rec["anchor"] = feet
		return false
	var command: Variant = player.get("controller").get("current_command")
	var pushing: bool = command != null and (command.get("move") as Vector2).length() > 0.5
	var flat := Vector2(feet.x - (rec["anchor"] as Vector3).x, feet.z - (rec["anchor"] as Vector3).z)
	if flat.length() > PROGRESS or not pushing:
		rec["anchor"] = feet
		rec["stuck"] = 0.0
		return false
	rec["stuck"] += delta
	if rec["stuck"] >= stuck_seconds:
		return _put_back(game, player, rec, "stuck", feet)
	return false


func forget(player_id: StringName) -> void:
	_seen.erase(player_id)


## Under the floor plane but above the kill height: below that the map's own death applies, and a net that caught it first made the kill height dead letter. The walls (ZzMap._build_boundary) keep a body in; a nav region is not a wall, so it is not tested here.
static func out_of_map(map: Object, feet: Vector3) -> bool:
	return feet.y < floor_plane(map) and feet.y >= float(map.call(&"kill_height"))


## The lowest ground the document names, less [constant FALL_DEPTH]; INF-safe when it names none.
static func floor_plane(map: Object) -> float:
	var doc: Dictionary = map.get("doc")
	var lowest := INF
	for fl: Array in (doc.get("nav", {}) as Dictionary).get("floors", []):
		lowest = minf(lowest, float(fl[4]))
	for side: String in (doc.get("spawns", {}) as Dictionary):
		for entry: Dictionary in doc["spawns"][side]:
			lowest = minf(lowest, float((entry["at"] as Array)[1]))
	# A lift's plate rests below the floors it serves.
	var mech: Object = map.get("mechanics")
	if mech != null:
		for i in int(mech.call(&"mover_count")):
			lowest = minf(lowest, ((mech.call(&"mover", i) as Dictionary)["zone"] as AABB).position.y)
	if lowest == INF:
		return -INF
	lowest = minf(lowest, _mechanics_low(map))
	# Water is a place the map meant: a swimmer's bed lies below every deck, and is not the void.
	for pool: AABB in (map.get("water_boxes") as Array):
		lowest = minf(lowest, pool.position.y)
	return maxf(lowest - FALL_DEPTH, float(map.call(&"kill_height")) + 1.0)


## The lowest point of a lift, door or volume: a shaft or an acid pit is a place the map meant, below its lowest floor.
static func _mechanics_low(map: Object) -> float:
	if map.has_meta(&"zz_mech_low"):
		return float(map.get_meta(&"zz_mech_low"))
	var mech: Object = map.get("mechanics")
	if mech == null:
		return INF
	var low := INF
	for i in int(mech.call(&"mover_count")):
		var zone: Variant = (mech.call(&"mover", i) as Dictionary).get("zone")
		if zone is AABB:
			low = minf(low, (zone as AABB).position.y)
	for t: Dictionary in mech.call(&"volume_toggles"):
		low = minf(low, ((t["vol"] as Object).call(&"bounds") as AABB).position.y)
	map.set_meta(&"zz_mech_low", low)
	return low


func _put_back(game: Node, player: Object, rec: Dictionary, why: String, feet: Vector3) -> bool:
	var map: Object = game.get("map")
	var at := Vector3.ZERO
	var yaw := float(player.get("controller").get("state").get("yaw"))
	var found := false
	var safe: Array = rec["safe"]
	# The oldest sample far enough from here is clear of whatever held them; the newest may be the trap's own mouth.
	for p: Vector3 in safe:
		if p.distance_to(feet) >= 1.0 and not out_of_map(map, p):
			at = p
			found = true
			break
	if not found:
		var spot: Array = map.call(&"spawn", "survivors", 0)
		at = spot[0]
		yaw = float(spot[1])
	player.call(&"place_at", at, yaw)
	rec["stuck"] = 0.0
	rec["anchor"] = at
	rec["warps"] = int(player.get("warps"))
	rescued += 1
	DotLog.warn(CHANNEL, "a survivor was put back on the ground", {"player": String(player.get("player_id")), "why": why,
		"from": "%.1f,%.1f,%.1f" % [feet.x, feet.y, feet.z] if feet.is_finite() else "nan", "to": "%.1f,%.1f,%.1f" % [at.x, at.y, at.z],
		"map": String(map.call(&"id"))})
	return true
