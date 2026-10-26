extends Node
## Finds the places a survivor falls out of a map or gets stuck, without a person: holes in the ground,
## capsules dropped from start points and floor samples that end below the floor, outside the walls or
## embedded, and spots a capsule cannot move away from.
##   godot --headless --path . res://tools/fall_probe.tscn -- <map id>|--all [--step=2.0] [--drops=300] [--quiet]
## Exits 1 when any map has a hole, a fall, an embedded start or a trap.
## Causes: HOLE_DRAWN (a drawn solid box is over the hole, so its collision is missing), HOLE_NO_HULLS (the
## document names world hulls and none loaded), HOLE_BARE (the nav floor has nothing under it at all).

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzPaths := preload("../game/zz_paths.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const RADIUS := 0.4
const HEIGHT := 1.8
## A ray down from this far over a nav floor must find ground within [member FLOOR_TOLERANCE] of its height.
const RAY_UP := 0.6
const FLOOR_TOLERANCE := 0.75
const SETTLE_FRAMES := 150
const PROBE_FRAMES := 30
const PROBE_SPEED := 3.0
const GRAVITY := 20.0
## A fall this far below where a capsule was put is a fall, whatever the map's own kill height says.
const FELL := 2.5

var _game: ZzGame


static func ids_in_checkout() -> PackedStringArray:
	var ids := PackedStringArray()
	for f in DirAccess.get_files_at(ZzPaths.rebase("res://maps")):
		if f.ends_with(".json"):
			ids.append(f.get_basename())
	ids.sort()
	return ids


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	_run.call_deferred()


func _run() -> void:
	var ids := PackedStringArray()
	var step := 2.0
	var drops := 300
	var quiet := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = float(a.substr(7))
		elif a.begins_with("--drops="):
			drops = int(a.substr(8))
		elif a == "--quiet":
			quiet = true
		elif a == "--all":
			ids = ids_in_checkout()
		else:
			ids.append_array(a.split(","))
	var failing := PackedStringArray()
	for id in ids:
		var report: Dictionary = await probe(StringName(id), step, drops)
		var bad: int = report["holes"] + report["falls"] + report["embedded"] + report["trapped"]
		print("%s: %s" % [id, _line(report)])
		if bad > 0:
			failing.append(id)
			if not quiet:
				for what: String in report["examples"]:
					print("    ", what)
	print("failing maps (%d of %d): %s" % [failing.size(), ids.size(), ", ".join(failing)])
	get_tree().quit(1 if not failing.is_empty() else 0)


static func _line(r: Dictionary) -> String:
	return "%d floor points: %d holes %s (%d uneven); %d drops: %d fell, %d embedded, %d trapped; hulls %d (%d floor points stand on them alone)" % [
		r["points"], r["holes"], r["causes"], r["uneven"], r["dropped"], r["falls"], r["embedded"], r["trapped"], r["hulls"], r["needs_hulls"]]


## Probes one map and returns the counts and a few examples of each fault.
func probe(id: StringName, step: float, drops: int) -> Dictionary:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(id)])
	_game = ZzGame.new()
	_game.config = config
	_game.authoritative = true
	_game.draw_world = false
	_game.register_service = false
	add_child(_game)
	_game.set_physics_process(false)
	for i in 8:
		await get_tree().physics_frame
	var map := _game.map
	var doc := map.doc
	var report := {"points": 0, "holes": 0, "uneven": 0, "causes": {}, "dropped": 0, "falls": 0, "embedded": 0, "trapped": 0,
		"needs_hulls": 0, "hulls": map.world_collision.get_child_count() if map.world_collision != null else 0, "examples": PackedStringArray()}
	var examples: PackedStringArray = report["examples"]
	var mask: int = _game.physics.collision_mask(&"player")
	var space := map.get_world_3d().direct_space_state

	var kill := map.kill_height()
	var floors: Array = (doc.get("nav", {}) as Dictionary).get("floors", [])
	var drawn := _drawn_boxes(doc)
	var no_hulls: bool = not (doc.get("world_collision", {}) as Dictionary).is_empty() and int(report["hulls"]) == 0
	var samples: Array[Vector3] = []
	var with_hulls: Array[Vector3] = []

	# (c) holes: a ray down over every floor rectangle.
	var causes: Dictionary = report["causes"]
	for fl: Array in floors:
		var y := float(fl[4])
		# A sliver is a rounding of the nav, not ground anybody stands on.
		if float(fl[2]) - float(fl[0]) < 1.0 or float(fl[3]) - float(fl[1]) < 1.0:
			continue
		var x := float(fl[0]) + step * 0.5
		while x < float(fl[2]) or x == float(fl[0]) + step * 0.5:
			var z := float(fl[1]) + step * 0.5
			while z < float(fl[3]) or z == float(fl[1]) + step * 0.5:
				var px := minf(x, float(fl[2]))
				var pz := minf(z, float(fl[3]))
				report["points"] += 1
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
					Vector3(px, y + RAY_UP, pz), Vector3(px, y - 2.0, pz), mask))
				if not hit.is_empty() and (hit["collider"] as Node).get_parent() == map.world_collision:
					with_hulls.append(Vector3(px, y, pz))
				var lower := hit.is_empty() or (hit["position"] as Vector3).y < y - FLOOR_TOLERANCE
				if lower:
					# Ground further down is a ramp or a step the nav rectangle rounds; nothing at all is a hole.
					var deep := space.intersect_ray(PhysicsRayQueryParameters3D.create(
						Vector3(px, y - 1.0, pz), Vector3(px, kill - 5.0, pz), mask)) if hit.is_empty() else hit
					if not deep.is_empty():
						report["uneven"] += 1
					else:
						var cause := "HOLE_DRAWN" if _under_drawn(drawn, px, pz, y) else ("HOLE_NO_HULLS" if no_hulls else "HOLE_BARE")
						report["holes"] += 1
						causes[cause] = int(causes.get(cause, 0)) + 1
						if examples.size() < 6:
							examples.append("%s at (%.1f, %.2f, %.1f)" % [cause, px, y, pz])
				if samples.size() < drops * 3 and int(report["points"]) % maxi(1, int(5.0 / step) * int(5.0 / step)) == 0:
					samples.append(Vector3(px, y, pz))
				z += step
			x += step

	# A client that could not load the world pack plays on the boxes alone: how much floor is only a hull?
	if not with_hulls.is_empty():
		var layers: Array[int] = [map.world_collision.collision_layer, map.world_clip.collision_layer if map.world_clip != null else 0]
		map.world_collision.collision_layer = 0
		if map.world_clip != null:
			map.world_clip.collision_layer = 0
		await get_tree().physics_frame
		for p in with_hulls:
			var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * RAY_UP, p - Vector3.UP * FLOOR_TOLERANCE, mask))
			if r.is_empty():
				report["needs_hulls"] += 1
		map.world_collision.collision_layer = layers[0]
		if map.world_clip != null:
			map.world_clip.collision_layer = layers[1]
		await get_tree().physics_frame

	# Starts, route, horde spawns and posts, then an even share of the floor samples.
	var starts: Array[Vector3] = []
	var lowest := INF
	for fl: Array in floors:
		lowest = minf(lowest, float(fl[4]))
	for side: String in (doc.get("spawns", {}) as Dictionary):
		for entry: Dictionary in doc["spawns"][side]:
			lowest = minf(lowest, ZzMapDoc.v3(entry["at"]).y)
	var seats := ((doc.get("spawns", {}) as Dictionary).get("survivors", []) as Array).size()
	for seat in seats:
		starts.append(map.spawn("survivors", seat)[0])
	var start_count := starts.size()
	# The route's points are the author's path through the map, not ground: some hang in the air, so they are not dropped.
	var picked: Array[Vector3] = starts.duplicate()
	var every := maxi(1, samples.size() / maxi(1, drops - picked.size()))
	for i in range(0, samples.size(), every):
		picked.append(samples[i])

	# (a) and (b): drop capsules, let them settle, then try to leave.
	var bodies: Array[CharacterBody3D] = []
	var put: Array[Vector3] = []
	for p in picked:
		var body := _body(mask)
		add_child(body)
		body.global_position = p + Vector3.UP * 0.1
		bodies.append(body)
		put.append(p)
	report["dropped"] = bodies.size()
	await get_tree().physics_frame
	var skip: Array[bool] = []
	for i in bodies.size():
		var inside := _embedded(space, bodies[i].global_position, mask)
		if inside != "" and i < start_count:
		skip.append(inside != "")
		# A grid point inside a prop is the sample's fault; a start or route point inside one is the map's.
		if inside != "" and i < start_count:
			report["embedded"] += 1
			causes["EMBEDDED_" + inside] = int(causes.get("EMBEDDED_" + inside, 0)) + 1
			if examples.size() < 14:
				examples.append("EMBEDDED start at %s in %s" % [put[i], inside])
	for f in SETTLE_FRAMES:
		_fall(bodies, Vector3.ZERO)
		await get_tree().physics_frame
	var region: AABB = map.playable_region().grow(ZzMap.BOUNDARY_MARGIN + 1.0)
	var settled: Array[Vector3] = []
	for i in bodies.size():
		var at := bodies[i].global_position
		settled.append(at)
		var outside := region.size != Vector3.ZERO and not (at.x >= region.position.x and at.x <= region.end.x and at.z >= region.position.z and at.z <= region.end.z)
		if at.y < lowest - FELL or at.y < kill or outside or not at.is_finite():
			report["falls"] += 1
			if examples.size() < 20:
				examples.append("FELL from %s to %s%s (lowest floor %.1f, kill %.1f)" % [put[i], at, " (outside the walls)" if outside else "", lowest, kill])
			var kind := "DRAWN" if _under_drawn(drawn, put[i].x, put[i].z, put[i].y) else ("NO_HULLS" if no_hulls else "BARE")
			causes["FELL_" + kind] = 1 + int(causes.get("FELL_" + kind, 0))
	var blocked: Array[int] = []
	blocked.resize(bodies.size())
	for k in 8:
		var dir := Vector3(cos(TAU * k / 8.0), 0.0, sin(TAU * k / 8.0))
		for i in bodies.size():
			bodies[i].global_position = settled[i]
			bodies[i].velocity = Vector3.ZERO
		for f in PROBE_FRAMES:
			_fall(bodies, dir * PROBE_SPEED)
			await get_tree().physics_frame
		for i in bodies.size():
			var d := Vector2(bodies[i].global_position.x - settled[i].x, bodies[i].global_position.z - settled[i].z).length()
			if d < 0.3:
				blocked[i] += 1
	for i in bodies.size():
		if blocked[i] == 8 and not skip[i] and settled[i].y >= lowest - FELL:
			report["trapped"] += 1
			if examples.size() < 26:
				examples.append("TRAPPED at %s (put at %s)" % [settled[i], put[i]])
	for b in bodies:
		b.queue_free()
	_game.queue_free()
	await get_tree().physics_frame
	return report


func _body(mask: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	shape.shape = capsule
	shape.position.y = HEIGHT * 0.5
	body.add_child(shape)
	body.collision_layer = 0
	body.collision_mask = mask
	body.floor_snap_length = 0.3
	return body


func _fall(bodies: Array[CharacterBody3D], walk: Vector3) -> void:
	for b in bodies:
		var vy := 0.0 if b.is_on_floor() else b.velocity.y - GRAVITY / 60.0
		b.velocity = Vector3(walk.x, maxf(vy, -25.0), walk.z)
		b.move_and_slide()


func _embedded(space: PhysicsDirectSpaceState3D, feet: Vector3, mask: int) -> String:
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS - 0.08
	capsule.height = HEIGHT - 0.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = mask
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, HEIGHT * 0.5 + 0.1, 0.0))
	var hits := space.intersect_shape(query, 1)
	if hits.is_empty():
		return ""
	var index := _game.map.prop_from_hit(hits[0]["collider"], int(hits[0]["shape"]))
	return "prop %s" % _game.map.prop_id(index) if index >= 0 else "%s/%s" % [(hits[0]["collider"] as Node).name, (hits[0]["collider"] as Node).get_parent().name]


## Visible boxes as [inverse transform, half size]: what the player sees as floor.
static func _drawn_boxes(doc: Dictionary) -> Array:
	var out := []
	for b: Dictionary in doc.get("boxes", []):
		if not bool(b.get("visible", true)) or b.has("gate") or b.has("barricade"):
			continue
		var at := ZzMapDoc.v3(b["at"])
		var half := ZzMapDoc.v3(b["size"]) * 0.5
		out.append([AABB(at - half, half * 2.0), bool(b.get("solid", true))])
	return out


## Whether a drawn box's top is within a step of the floor under the point.
static func _under_drawn(drawn: Array, x: float, z: float, y: float) -> bool:
	for rec: Array in drawn:
		var box: AABB = rec[0]
		if x >= box.position.x and x <= box.end.x and z >= box.position.z and z <= box.end.z and absf(box.end.y - y) < 0.6:
			return true
	return false
