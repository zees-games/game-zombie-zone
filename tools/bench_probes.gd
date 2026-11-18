extends RefCounted
## tools/bench.gd's one-off probes (`--bodyprobe`, `--physprobe`): what a zombie's move and the world's
## static shapes cost, printed as BODYPROBE / PHYSPROBE lines.

const ZzGame := preload("../game/zz_game.gd")


## --bodyprobe: what one zombie's move costs, and against what: move_and_slide at its own velocity,
## one test_move, two rays, and the static shapes its capsule's swept box overlaps, by shape class.
static func body_probe(game: ZzGame, local) -> void:
	var space: PhysicsDirectSpaceState3D = local.get_world_3d().direct_space_state
	var classes := {}
	var n := 0
	var t_slide := 0
	var t_test := 0
	var t_ray := 0
	var overlaps := 0
	var rayq := PhysicsRayQueryParameters3D.new()
	for npc in game.horde.spawner.all_npcs():
		var b := npc.node as CharacterBody3D
		if b == null or not npc.is_alive():
			continue
		n += 1
		var keep := b.global_transform
		var wish: Vector3 = b.get(&"wish")
		var v := Vector3(wish.x, -1.0, wish.z)
		if v.length_squared() < 0.01:
			v = Vector3(1.0, -1.0, 0.0)
		b.velocity = v
		var t0 := Time.get_ticks_usec()
		for i in 20:
			b.global_transform = keep
			b.velocity = v
			b.move_and_slide()
		t_slide += Time.get_ticks_usec() - t0
		b.global_transform = keep
		t0 = Time.get_ticks_usec()
		for i in 20:
			var _hit := b.test_move(keep, v / 60.0)
		t_test += Time.get_ticks_usec() - t0
		rayq.collision_mask = b.collision_mask
		t0 = Time.get_ticks_usec()
		for i in 20:
			rayq.from = keep.origin + Vector3(0, 0.5, 0)
			rayq.to = rayq.from + v / 60.0 + Vector3(v.x, 0, v.z).normalized() * 0.4
			var _a := space.intersect_ray(rayq)
			rayq.from = keep.origin + Vector3(0, 0.6, 0)
			rayq.to = keep.origin + Vector3(0, -0.6, 0)
			var _c := space.intersect_ray(rayq)
		t_ray += Time.get_ticks_usec() - t0
		var q := PhysicsShapeQueryParameters3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.94, 2.05, 0.94)
		q.shape = box
		q.transform = Transform3D(Basis(), keep.origin + Vector3(0, 0.9, 0))
		q.collision_mask = b.collision_mask
		for r in space.intersect_shape(q, 128):
			overlaps += 1
			var owner: Object = r.get("collider")
			var shape_class := "?"
			if owner is CollisionObject3D:
				var sid: int = (owner as CollisionObject3D).shape_find_owner(int(r.get("shape", 0)))
				var sh := (owner as CollisionObject3D).shape_owner_get_shape(sid, 0) if sid >= 0 else null
				shape_class = sh.get_class() if sh != null else "?"
				if sh is ConcavePolygonShape3D:
					shape_class += "(%d faces)" % ((sh as ConcavePolygonShape3D).get_faces().size() / 3)
				elif sh is ConvexPolygonShape3D:
					shape_class += "(%d pts)" % (sh as ConvexPolygonShape3D).points.size()
			classes[shape_class] = int(classes.get(shape_class, 0)) + 1
	n = maxi(n, 1)
	print("BODYPROBE bodies=%d move_and_slide=%.1f us test_move=%.1f us two_rays=%.1f us overlaps=%.1f per body" % [
		n, t_slide / 20.0 / n, t_test / 20.0 / n, t_ray / 20.0 / n, float(overlaps) / n])
	var keys := classes.keys()
	keys.sort_custom(func(a, c): return int(classes[a]) > int(classes[c]))
	for k in keys.slice(0, 12):
		print("BODYPROBE shape %-36s %d" % [k, classes[k]])


## --physprobe: static shapes by body and what one capsule overlap query costs near the survivor.
static func phys_probe(local: Node3D) -> void:
	var shapes := 0
	var bodies := 0
	var procs := {}
	var stack: Array[Node] = [local.get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n.is_physics_processing():
			var sc: Script = n.get_script()
			var pk := "%s|%s" % [n.get_class(), sc.resource_path.get_file() if sc != null else ""]
			procs[pk] = int(procs.get(pk, 0)) + 1
		if n is StaticBody3D:
			bodies += 1
			for c in n.get_children():
				if c is CollisionShape3D:
					shapes += 1
	print("PHYSPROBE static_bodies=%d shapes=%d" % [bodies, shapes])
	print("PHYSPROBE physics_processing ", procs)
	var space := local.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = 0xFFFFF
	var rng := RandomNumberGenerator.new()
	var n := 2000
	var hits := 0
	var t0 := Time.get_ticks_usec()
	for i in n:
		q.transform = Transform3D(Basis(), local.global_position + Vector3(rng.randf_range(-20, 20), 1.0, rng.randf_range(-20, 20)))
		hits += space.intersect_shape(q, 8).size()
	print("PHYSPROBE intersect_shape %.1f us/call hits=%d" % [float(Time.get_ticks_usec() - t0) / n, hits])
	var rayq := PhysicsRayQueryParameters3D.new()
	t0 = Time.get_ticks_usec()
	for i in n:
		rayq.from = local.global_position + Vector3(rng.randf_range(-20, 20), 1.0, rng.randf_range(-20, 20))
		rayq.to = rayq.from + Vector3(rng.randf_range(-10, 10), 0.0, rng.randf_range(-10, 10))
		hits += space.intersect_ray(rayq).size()
	print("PHYSPROBE intersect_ray %.1f us/call" % [float(Time.get_ticks_usec() - t0) / n])
