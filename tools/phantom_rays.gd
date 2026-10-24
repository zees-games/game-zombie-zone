extends Node
## Finds collision nobody can see: rays from eye height over a map's nav floors, spawns and route. A strike on
## the shot mask (`ZzGame.world_mask`) by a map box (`Solid`) inside an invisible box and no drawn one is a
## phantom a bullet stops on. `before` counts the clip layer too: what shots met before invisible solids moved to it.
##   godot --headless --path . res://tools/phantom_rays.tscn -- <map id>[,<map id>...] [--step=3] [--quiet]
## Exits 1 when any map has a phantom strike on the shot mask.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const EYE := 1.6
const RANGE := 40.0
const SLACK := 0.05
const PITCHES := [0.0, 0.35, -0.35, 0.8, -0.8]
const YAWS := 16


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	_run.call_deferred()


func _run() -> void:
	var ids := PackedStringArray()
	var step := 3.0
	var quiet := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = float(a.substr(7))
		elif a == "--quiet":
			quiet = true
		else:
			ids.append_array(a.split(","))
	var code := 0
	for id in ids:
		if await _scan(StringName(id), step, quiet) > 0:
			code = 1
	get_tree().quit(code)


func _scan(id: StringName, step: float, quiet: bool) -> int:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.map_ids = PackedStringArray([String(id)])
	var game := ZzGame.new()
	game.config = config
	game.authoritative = true
	game.draw_world = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	for i in 3:
		await get_tree().physics_frame
	var loaded: DotResult = await game.map.load_world()
	await get_tree().physics_frame
	await get_tree().physics_frame

	var seen: Array = []
	var hidden: Array = []
	for b: Dictionary in game.map.doc["boxes"]:
		if b.has("gate") or b.has("barricade") or not bool(b.get("solid", true)):
			continue
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(b.get("yaw", 0.0)))), ZzMapDoc.v3(b["at"]))
		var drawn := bool(b.get("visible", true))
		# A ground slab collides deeper than it is drawn (ZzMap.GROUND_DEPTH).
		var rec := [xf.affine_inverse(), ZzMapDoc.v3(b["size"]) * 0.5 + Vector3(SLACK, ZzMap.GROUND_DEPTH if drawn else SLACK, SLACK)]
		(seen if drawn else hidden).append(rec)

	print("clip shapes: ", game.map._clip.get_child_count(), " layer ", game.map._clip.collision_layer, " mask ", game.world_mask(), " every ", game.world_mask() | game.physics.layer_mask(&"clip"))
	var space := game.map.get_world_3d().direct_space_state
	var shot: int = game.world_mask()
	var every: int = shot | game.physics.layer_mask(&"clip")
	var rays := 0
	var before := 0
	var after := 0
	var touching := 0
	var first := ""
	var eyes: Array[Vector3] = []
	for fl: Array in game.map.doc["nav"]["floors"]:
		var x := float(fl[0]) + step * 0.5
		while x < float(fl[2]):
			var z := float(fl[1]) + step * 0.5
			while z < float(fl[3]):
				eyes.append(Vector3(x, float(fl[4]) + EYE, z))
				z += step
			x += step
	for side: String in game.map.doc.get("spawns", {}):
		for entry: Dictionary in game.map.doc["spawns"][side]:
			eyes.append(ZzMapDoc.v3(entry["at"]) + Vector3.UP * EYE)
	for pt: Array in game.map.doc.get("route", []):
		eyes.append(ZzMapDoc.v3(pt) + Vector3.UP * EYE)
	for eye in eyes:
		for pitch: float in PITCHES:
			for k in YAWS:
				var yaw := TAU * k / YAWS
				var to := eye + Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * RANGE
				rays += 1
				for pass_mask: int in [every, shot]:
					var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, to, pass_mask))
					if r.is_empty():
						continue
					var clip := ((r["collider"] as Node).name in [&"Clip", &"WorldClip"])
					if not clip and not (_shape_of(r).shape is BoxShape3D and (r["collider"] as Node).name == &"Solid" and _inside(hidden, r["position"])):
						continue
					if _inside(seen, r["position"]):
						touching += 1
						continue
					if pass_mask == every:
						before += 1
					else:
						after += 1
						first = first if first != "" else "%s from %s on %s" % [r["position"], eye, (r["collider"] as Node).name]
	print("%s: %d rays, phantom strikes: %d before (clip counted), %d on the shot mask (%d more at a drawn box too)%s%s" % [id, rays, before, after, touching, "" if first == "" else ", first at ", first])
	if not quiet:
		print("  invisible solid boxes: %d, drawn solid boxes: %d, world drawn: %s" % [hidden.size(), seen.size(), loaded.ok and bool(loaded.value)])
	game.queue_free()
	await get_tree().physics_frame
	return after


func _inside(boxes: Array, p: Vector3) -> bool:
	for b: Array in boxes:
		var l: Vector3 = (b[0] as Transform3D) * p
		var h: Vector3 = b[1]
		if absf(l.x) <= h.x and absf(l.y) <= h.y and absf(l.z) <= h.z:
			return true
	return false


func _shape_of(r: Dictionary) -> CollisionShape3D:
	var body := r["collider"] as CollisionObject3D
	return body.shape_owner_get_owner(body.shape_find_owner(int(r["shape"]))) as CollisionShape3D
