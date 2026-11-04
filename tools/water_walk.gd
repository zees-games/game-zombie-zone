extends "zz_water_probe.gd"

## Probe: drops a survivor at points of a map and walks it in eight directions with the real motor,
## printing where it moved less than a metre and its water level.
##   godot --headless --path . res://tools/water_walk.tscn -- <map id> x,z[,y] ...

const ZzPlayer := preload("../game/zz_player.gd")


func _run() -> void:
	await _open_walker()
	var args := _args
	var trace := _trace
	var id := _id
	var game := _game
	var p: ZzPlayer = _walker
	await get_tree().physics_frame
	print("water boxes: ", game.map.water_boxes)
	var stuck := 0
	for a: String in args.slice(1):
		var parts := a.split(",")
		var y := float(parts[2]) if parts.size() > 2 else 2.0
		var at := Vector3(float(parts[0]), y, float(parts[1]))
		for d in 8:
			p.place_at(at, 0.0)
			p.controller.apply_command(DotFpsCommand.new())
			for i in 30:
				game.simulate(TICK)
			var from := p.feet()
			var c := DotFpsCommand.new()
			c.yaw = d * 45.0
			c.move = Vector2(0, 1)
			for i in 120:
				p.controller.apply_command(c)
				game.simulate(TICK)
				if trace and i % 10 == 9:
					print("  t%d %s mode %s water %s" % [i, p.feet(), p.controller.state.mode, p.water_level])
				if i % 8 == 7:
					await get_tree().physics_frame
			var moved := Vector2(p.feet().x - from.x, p.feet().z - from.z).length()
			var lvl := p.water_level if "water_level" in p else -1
			var tag := "STUCK" if moved < 1.0 else "ok"
			if moved < 1.0:
				stuck += 1
			print("%s at %s yaw %d: from %s to %s moved %.2f water %s mode %s" % [tag, at, d * 45, from, p.feet(), moved, lvl, p.controller.state.mode])
	print("stuck walks: %d" % stuck)
	if OS.has_environment("WALK_RAY"):
		var r := OS.get_environment("WALK_RAY").split_floats(",")
		var q := PhysicsRayQueryParameters3D.create(Vector3(r[0], r[1], r[2]), Vector3(r[3], r[4], r[5]))
		var hit := game.get_world_3d().direct_space_state.intersect_ray(q)
		print("ray: ", hit, " ", hit.get("collider").get_path() if hit.has("collider") else "", " ", (hit.get("collider") as Object).get_meta_list() if hit.has("collider") else "")
	get_tree().quit(0)
