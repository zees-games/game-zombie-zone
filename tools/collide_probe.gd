extends Node
## Compares the drawn world with what the server collides with (dot-core's DotCollisionSweep): drawn floor and walls with no
## collision, and collision with nothing drawn. fall_probe asks what a capsule does on the collision alone; this asks whether the
## collision is where the picture says it is.
##   godot --headless --path . res://tools/collide_probe.tscn -- <map id>|--all [--step=2.0] [--stands=400] [--examples=6] [--max-invisible=N]

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzPaths := preload("../game/zz_paths.gd")
const FallProbe := preload("fall_probe.gd")


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	_run.call_deferred()


func _run() -> void:
	var ids := PackedStringArray()
	var step := 2.0
	var stands := 400
	var examples := 6
	var max_invisible := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--step="):
			step = float(a.substr(7))
		elif a.begins_with("--stands="):
			stands = int(a.substr(9))
		elif a.begins_with("--examples="):
			examples = int(a.substr(11))
		elif a.begins_with("--max-invisible="):
			max_invisible = int(a.substr(16))
		elif a == "--all":
			ids = FallProbe.ids_in_checkout()
		else:
			ids.append_array(a.split(","))
	var failed := false
	var rows: Array[String] = []
	for id in ids:
		var sweep: DotCollisionSweep = await probe(StringName(id), step, stands, examples)
		if sweep == null:
			print("%s: no drawn world" % id)
			continue
		var verdict := sweep.verdict(true, false)
		if not verdict.ok:
			printerr("%s: %s" % [id, verdict.error.message])
			failed = true
			continue
		var authored := 0
		for kind in ["invisible_floor", "invisible_wall"]:
			for label in ["Clip", "WorldClip", "Boundary"]:
				authored += sweep.count(kind, label)
		var line := "%s: floor %d wall %d buried %d invisible %d (authored clip %d) [samples %d floor, %d wall, %d rays]" % [id, sweep.count("floor_missing"), sweep.count("wall_missing"), sweep.count("wall_buried"), sweep.count("invisible_floor") + sweep.count("invisible_wall") - authored, authored, sweep.floor_samples, sweep.wall_samples, sweep.probe_rays]
		print(line)
		var invisible := sweep.count("invisible_floor") + sweep.count("invisible_wall") - authored
		if max_invisible >= 0 and invisible > max_invisible:
			printerr("%s: %d invisible hits, more than --max-invisible=%d" % [id, invisible, max_invisible])
			failed = true
		for l in sweep.describe_lines().slice(1):
			print("   ", l)
	get_tree().quit(1 if failed else 0)


func probe(id: StringName, step: float, stands: int, examples := 6) -> DotCollisionSweep:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(id)])
	var game := ZzGame.new()
	game.config = config
	game.authoritative = true
	game.draw_world = false
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	for i in 8:
		await get_tree().physics_frame
	var map := game.map
	var prefix := map.local_world_prefix()
	var read: DotResult = (load(ZzMap.MESH_SCRIPT) as GDScript).call(&"load_prefix", prefix)
	if not read.ok:
		print("%s: %s (%s)" % [id, read.error.message, prefix])
		game.queue_free()
		await get_tree().physics_frame
		return null
	var world: RefCounted = read.value
	var space := map.get_world_3d().direct_space_state
	var sweep := DotCollisionSweep.new(space, game.physics.collision_mask(&"player"))
	sweep.examples_per_kind = examples
	for rec: Dictionary in world.get("surfaces"):
		if int(rec["model"]) != 0 or rec.get("sky3d", false):
			continue
		var tag := &"world"
		if rec.get("water", false):
			tag = &"water"
		elif rec.has("glass"):
			tag = &"glass"
		elif rec.get("collide", false):
			tag = &"displacement"
		elif rec.get("two_sided", false):
			tag = &"two_sided"
		var arrays: Array = world.call(&"surface_arrays", rec)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var faces := PackedVector3Array()
		faces.resize(idx.size())
		for i in idx.size():
			faces[i] = verts[idx[i]]
		sweep.add_faces(tag, faces)
	# A solid prop collides as a box and is drawn as its stand-in, so the stand-ins (and the boxes the client draws where a model is missing) count as drawn.
	var props: Node3D = world.call(&"build_props")
	print("%s: %d prop models missing, %d drawn as boxes of their bounds" % [id, world.get("missing_models"), world.get("missing_proxied")])
	var unseen: Node3D = world.call(&"draw_unseen_boxes", map.doc.get("solid_props", []))
	if unseen != null:
		props.add_child(unseen)
	add_child(props)
	sweep.add_node(&"prop", props)
	props.free()
	# A mover's collision stands where its drawn model does (a door, a lift), so those meshes count as drawn too.
	var moving: Node3D = world.call(&"build_node")
	for child in moving.get_children():
		if int(child.get_meta(&"model", 0)) != 0:
			sweep.add_node(&"mover", child)
	add_child(moving)
	moving.free()
	var floors: Array = (map.doc.get("nav", {}) as Dictionary).get("floors", [])
	sweep.play = func(p: Vector3) -> bool:
		for fl: Array in floors:
			if p.x >= fl[0] - 0.5 and p.x <= fl[2] + 0.5 and p.z >= fl[1] - 0.5 and p.z <= fl[3] + 0.5 and p.y >= fl[4] - 0.5 and p.y <= fl[4] + 2.0:
				return true
		return false
	var standing := PackedVector3Array()
	for fl: Array in floors:
		if fl[2] - fl[0] < 1.0 or fl[3] - fl[1] < 1.0:
			continue
		var x: float = fl[0] + step * 0.5
		while x < fl[2]:
			var z: float = fl[1] + step * 0.5
			while z < fl[3]:
				standing.append(Vector3(x, fl[4], z))
				z += step * 2.0
			x += step * 2.0
	if standing.size() > stands:
		var thin := PackedVector3Array()
		for i in stands:
			thin.append(standing[i * standing.size() / stands])
		standing = thin
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			var at := Vector3(float(a.substr(5).split(",")[0]), float(a.substr(5).split(",")[1]), float(a.substr(5).split(",")[2]))
			for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD, Vector3.DOWN, Vector3.UP]:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + d * 4.0, sweep._mask))
				print("   at %s dir %s: %s" % [at, d, "%s %s at %s" % [hit["collider"].name, hit["collider"].get_parent().name, hit["position"]] if not hit.is_empty() else "nothing"])
	sweep.sweep_drawn([&"world", &"displacement", &"two_sided"])
	sweep.sweep_collision(standing)
	game.queue_free()
	await get_tree().physics_frame
	return sweep
