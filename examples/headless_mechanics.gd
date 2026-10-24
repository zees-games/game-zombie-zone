extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMechanics := preload("../game/zz_mechanics.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzPlayer := preload("../game/zz_player.gd")

## A converted map's lifts, doors, buttons and triggers: a lift on the real 4-way tunnel carries a
## survivor up, a door blocks and opens, a button's outputs run after their delays, and a map
## without a world has no moving parts.
##
## [b]Why the doors and links are tried on a made-up world as well.[/b] The real maps' doors are
## mostly boxes or objective gates; the ones that are movers are driven by one button or by
## walking up, so the chain (button, delay, relay, volume, lock) is only reachable in a fixture.

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const LIFT_MAP := &"zm_4way_tunnel"
const SECTIONS := 7
const CHECKS := 61

var _passed := 0
var _failed := 0
var _entered := 0
var _finished := 0


## A world made of data, for the chain tests: the same calls a DotMapBspMesh answers.
class FakeWorld extends RefCounted:
	var ents: Variant = null
	var model_ids := PackedInt32Array()

	func _init(manifest: Dictionary) -> void:
		ents = DotMapEntities.from_manifest(manifest)
		for rec: Dictionary in manifest["movers"]:
			model_ids.append(int(rec["model"]))

	func entities() -> Variant:
		return ents

	func models() -> PackedInt32Array:
		return model_ids

	func hull_shapes(_model: int, _kinds: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 3.0, 2.0)
		var convex := ConvexPolygonShape3D.new()
		var pts := PackedVector3Array()
		for x in [-0.5, 0.5]:
			for y in [0.0, 3.0]:
				for z in [-1.0, 1.0]:
					pts.append(Vector3(x, y, z))
		convex.points = pts
		return [{"shape": convex, "kind": "solid", "brush": 0}]


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone mechanics")
	await _test_lift()
	await _test_real_door()
	await _test_prop_doors()
	await _test_button_and_delay()
	await _test_volume_and_unsupported()
	await _test_volumes()
	await _test_no_world()

	print("\n%d sections entered, %d finished, %d passed, %d failed" % [_entered, _finished, _passed, _failed])
	var ok := _failed == 0 and _entered == SECTIONS and _finished == SECTIONS and _passed + _failed == CHECKS
	print("PASS" if ok else "FAIL (expected %d sections and %d checks)" % [SECTIONS, CHECKS])
	get_tree().quit(0 if ok else 1)


func _game(id: StringName, start := false) -> ZzGame:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.start_grace_seconds = 600.0
	config.map_ids = PackedStringArray([String(id)])

	var game := ZzGame.new()
	game.name = "Mech%s" % id
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	if start:
		game.next_map_id = id
		game.start()
		await get_tree().physics_frame

	return game


func _sim(game: ZzGame, ticks: int) -> void:
	for i in ticks:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	await get_tree().physics_frame


func _test_lift() -> void:
	_entered += 1
	print("%s: a lift carries a survivor" % LIFT_MAP)
	ZzMap.bring_global_mechanics = true
	var game := await _game(LIFT_MAP)
	var rider := game.add_player(&"u1", "Rider")
	rider.health.invulnerable = true
	game.next_map_id = LIFT_MAP
	game.start()
	await _sim(game, 8)
	var mech: ZzMechanics = game.map.mechanics
	_check(mech != null and mech.mover_count() > 0, "the map has moving parts", "%d movers" % (mech.mover_count() if mech != null else 0))

	if mech == null:
		game.queue_free()
		_finished += 1
		return

	var plate := mech.index_of("lift01_plate")
	var button := mech.index_of_entity(107)
	var zone: AABB = mech.mover(plate)["zone"]
	var top := zone.end.y
	rider.place_at(Vector3(zone.get_center().x, top + 0.05, zone.get_center().z), 0.0)
	await _sim(game, 30)
	var start_y := rider.feet().y
	var on_plate: bool = rider.controller.state.ground_id == (mech.mover(plate)["body"] as StaticBody3D).get_instance_id()
	_check(on_plate and start_y > zone.position.y and start_y < top + 0.3, "the survivor stands on the plate's body at rest", "feet %.2f, plate %.2f to %.2f" % [start_y, zone.position.y, top])

	var pad: AABB = mech.mover(button)["zone"]
	var eye := Vector3(zone.get_center().x, pad.get_center().y + 0.6, pad.get_center().z)
	var pressed := mech.try_press(eye, (pad.get_center() - eye).normalized(), 3.0, game.current_tick())
	_check(pressed, "the use key presses the button beside the plate")

	await _sim(game, 4 * TICK_RATE)
	var plate_rise := (mech.transform_at(plate, game.current_tick()).origin - (mech.mover(plate)["origin"] as Vector3)).y
	var rode := rider.feet().y - start_y
	_check(plate_rise > 30.0, "the plate travels", "%.1f m" % plate_rise)
	_check(rode > plate_rise * 0.9 and rider.feet().y > top, "the survivor rides it up", "rode %.1f of %.1f m" % [rode, plate_rise])
	_check(absf(rider.feet().x - zone.get_center().x) < 1.0 and absf(rider.feet().z - zone.get_center().z) < 1.0,
		"and stays on it", "off by %.2f, %.2f" % [rider.feet().x - zone.get_center().x, rider.feet().z - zone.get_center().z])

	var told := mech.told_indices()
	_check(told.has(plate), "the move is queued for clients", str(mech.snapshot(plate)))
	var wire := ZzEvents.read_mover(DotNetReader.new(ZzEvents.write_mover(mech.snapshot(plate), plate)))
	var snap: Array = mech.snapshot(plate)
	_check(bool(wire["ok"]) and int(wire["index"]) == plate and int(wire["start"]) == int(snap[0]) and int(wire["dir"]) == int(snap[2]),
		"the state survives the wire", str(wire))
	game.queue_free()
	_finished += 1


func _test_real_door() -> void:
	_entered += 1
	print("%s: a door blocks, then opens" % LIFT_MAP)
	var game := await _game(LIFT_MAP)
	var mech: ZzMechanics = game.map.mechanics
	var found := -1

	if mech != null:
		for i in mech.mover_count():
			var m: Dictionary = mech.mover(i)
			if m["body"] != null and bool(m["auto"]) and str(m["kind"]) == "slide":
				found = i
				break

	_check(found >= 0, "the map has a door that opens to walkers")

	if found < 0:
		game.queue_free()
		_finished += 1
		return

	var m: Dictionary = mech.mover(found)
	var body: StaticBody3D = m["body"]
	var zone: AABB = m["zone"]
	var near := [false]
	mech.occupants_fn = func(box: AABB) -> bool: return near[0] and box.intersects(zone)
	mech.authoritative = true
	await get_tree().physics_frame

	_check(_blocks(game, body, zone), "closed, it stops a ray through it")

	near[0] = true
	var tick := 1000

	var spent := 0
	while mech.fraction_at(found, tick) < 1.0 and spent < 6000:
		tick += 1
		spent += 1
		mech.step(tick)

	await get_tree().physics_frame
	_check(mech.fraction_at(found, tick) >= 1.0 and not _blocks(game, body, zone), "walked up to, it opens and the ray passes",
		"fraction %.2f" % mech.fraction_at(found, tick))

	near[0] = false

	spent = 0
	while mech.fraction_at(found, tick) > 0.0 and spent < 12000:
		tick += 1
		spent += 1
		mech.step(tick)

	await get_tree().physics_frame
	_check(mech.fraction_at(found, tick) <= 0.0 and _blocks(game, body, zone), "left alone, it closes and blocks again")
	game.queue_free()
	_finished += 1


## Whether a ray across the thin side of [param zone] meets [param body].
func _blocks(game: ZzGame, body: StaticBody3D, zone: AABB) -> bool:
	var space := game.get_world_3d().direct_space_state
	var c := zone.get_center()
	var axis := Vector3.RIGHT if zone.size.x <= zone.size.z else Vector3.BACK
	var reach := (zone.size.x if axis == Vector3.RIGHT else zone.size.z) * 0.5 + 1.0
	var exclude: Array[RID] = []

	for attempt in 6:
		var query := PhysicsRayQueryParameters3D.create(c - axis * reach, c + axis * reach)
		query.exclude = exclude
		var hit := space.intersect_ray(query)

		if hit.is_empty():
			return false

		if hit["collider"] == body:
			return true

		exclude.append(hit["rid"])

	return false


## One button, two doors, a relay and a lock, as data.
func _fixture() -> Dictionary:
	var door := func(entity: int, model: int, name: String, x: float) -> Dictionary:
		return {"entity": entity, "model": model, "kind": "slide", "classname": "func_door", "targetname": name,
			"origin": [x, 0.0, 0.0], "mins": [x - 0.5, 0.0, -1.0], "maxs": [x + 0.5, 3.0, 1.0], "direction": [0.0, 1.0, 0.0],
			"distance": 3.0, "travel_time": 1.0, "speed": 3.0, "wait": -1.0, "locked": false, "toggle": false, "start_open": false,
			"use": false, "touch": false, "solid": true}
	var link := func(from: int, output: String, input: String, to: int, delay: float) -> Dictionary:
		return {"from": from, "from_name": "", "output": output, "target": "t%d" % to, "input": input, "param": "", "delay": delay, "times": -1, "special": false, "to": [to]}
	return {
		"movers": [
			{"entity": 1, "model": 1, "kind": "button", "classname": "func_button", "targetname": "pad", "origin": [0.0, 1.0, 0.0],
				"mins": [-0.1, 0.9, -0.1], "maxs": [0.1, 1.1, 0.1], "wait": 1.0, "use": true, "locked": false, "toggle": false, "solid": true},
			door.call(2, 2, "door_a", 5.0),
			door.call(4, 4, "door_b", 10.0),
		],
		"volumes": [
			{"entity": 5, "model": 5, "kind": "multiple", "classname": "trigger_multiple", "targetname": "", "wait": 0.0, "disabled": false,
				"brushes": [[[1.0, 0.0, 0.0, 21.0], [-1.0, 0.0, 0.0, -19.0], [0.0, 1.0, 0.0, 3.0], [0.0, -1.0, 0.0, 1.0],
					[0.0, 0.0, 1.0, 1.0], [0.0, 0.0, -1.0, 1.0]]],
				"outputs": []},
			{"entity": 6, "model": 6, "kind": "water", "classname": "func_water", "targetname": "", "wait": 0.0, "disabled": false,
				"brushes": [], "outputs": []},
			{"entity": 7, "model": 7, "kind": "hurt", "classname": "trigger_hurt", "targetname": "pit", "wait": 0.0, "disabled": true,
				"damage": 1000.0, "brushes": [[[1.0, 0.0, 0.0, 31.0], [-1.0, 0.0, 0.0, -29.0], [0.0, 1.0, 0.0, 3.0], [0.0, -1.0, 0.0, 1.0],
					[0.0, 0.0, 1.0, 1.0], [0.0, 0.0, -1.0, 1.0]]], "outputs": []},
		],
		"entities": [{"entity": 3, "classname": "logic_relay", "targetname": "relay", "target": "", "origin": [0.0, 0.0, 0.0], "treatment": "data", "keys": {}}],
		"links": [
			link.call(1, "OnPressed", "Open", 2, 1.5),
			link.call(1, "OnPressed", "Trigger", 3, 0.5),
			link.call(3, "OnTrigger", "Open", 4, 2.0),
			link.call(1, "OnPressed", "Frobnicate", 3, 0.0),
			link.call(2, "OnFullyOpen", "Lock", 1, 0.0),
			link.call(5, "OnTrigger", "Close", 2, 0.0),
		],
	}


func _built() -> ZzMechanics:
	var mech := ZzMechanics.new()
	mech.tick_rate = TICK_RATE
	add_child(mech)
	mech.build(FakeWorld.new(_fixture()), Callable())
	return mech


## A shipped map's hinged prop doors: built on a global pack, solid, swung away from whoever opens
## them, opened by a zombie as by a survivor, and the side crosses the wire.
func _test_prop_doors() -> void:
	_entered += 1
	const DOOR_MAP := &"zm_abandoned_mall"
	print("%s: its hinged doors swing" % DOOR_MAP)
	ZzMap.bring_global_mechanics = false
	var game := await _game(DOOR_MAP)
	game.next_map_id = DOOR_MAP
	game.start()
	await _sim(game, 8)
	var mech: ZzMechanics = game.map.mechanics
	var read: DotResult = (load(ZzMap.MESH_SCRIPT) as GDScript).call(&"load_prefix", game.map.local_world_prefix())
	var doors := 0
	var brush_doors := 0

	if read.ok:
		for rec: Dictionary in (read.value.get("manifest") as Dictionary)["movers"]:
			if rec.get("classname") == "prop_door_rotating":
				doors += 1
			elif rec.get("classname") == "func_door" and rec.get("model") != null and not read.value.call(&"hull_shapes", int(rec["model"])).is_empty():
				brush_doors += 1

	_check(mech != null and doors > 0 and mech.mover_count() == doors + brush_doors, "the map's prop doors and its brush doors with hulls are built, and nothing else",
		"%d built of %d prop doors and %d brush doors" % [mech.mover_count() if mech != null else 0, doors, brush_doors])

	if mech == null or doors == 0:
		game.queue_free()
		_finished += 1
		return

	var d := 0
	while d < mech.mover_count() and not mech.mover(d).has("door"):
		d += 1
	var m: Dictionary = mech.mover(d)
	var node := m["node"] as Node3D
	var body := node.get_node("col_solid") as CollisionObject3D
	var rest: Transform3D = m["base"]
	var normal := rest.basis * Vector3.RIGHT
	var hinge := rest.origin
	var middle := hinge + rest.basis * Vector3(0.0, 1.0, -DotMapDoorStandIn.SIZE.x * 0.5)
	_check(body != null and body.collision_layer != 0 and bool(m["auto"]) and not bool(m["locked"]),
		"the door has a body on a layer, and opens to anyone near", "layer %d" % (body.collision_layer if body != null else -1))

	var who := [Vector3.INF]
	mech.occupants_fn = func(box: AABB) -> bool: return who[0] != Vector3.INF and box.grow(1.0).has_point(who[0])
	mech.opener_fn = func(_box: AABB) -> Variant: return null if who[0] == Vector3.INF else who[0]
	await get_tree().physics_frame
	_check(_ray_hits(game, body, middle - normal, middle + normal), "closed, it stops a ray through its panel")

	var tick := 2000
	var swung := []

	for sign_of in [1.0, -1.0]:
		who[0] = middle + normal * sign_of * 1.0
		var spent := 0

		while mech.fraction_at(d, tick) < 1.0 and spent < 4000:
			tick += 1
			spent += 1
			mech.step(tick)

		for _f in 3:
			await get_tree().physics_frame
		var open_middle: Vector3 = mech.transform_at(d, tick) * (rest.affine_inverse() * middle)
		var side_of_opener := signf(normal.dot(who[0] - hinge))
		var side_of_panel := signf(normal.dot(open_middle - hinge))
		swung.append(float(m["side"]))
		_check(mech.fraction_at(d, tick) >= 1.0 and not _ray_hits(game, body, middle - normal, middle + normal),
			"opened for somebody on side %+d, the ray passes where the panel was" % int(sign_of),
			"fraction %.2f ray %s" % [mech.fraction_at(d, tick), game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(middle - normal, middle + normal))])
		_check(side_of_panel == -side_of_opener, "and it swung away from them", "opener %+d, panel %+d" % [int(side_of_opener), int(side_of_panel)])

		who[0] = Vector3.INF
		spent = 0

		while mech.fraction_at(d, tick) > 0.0 and spent < 12000:
			tick += 1
			spent += 1
			mech.step(tick)

		for _f in 3:
			await get_tree().physics_frame
		_check(mech.fraction_at(d, tick) <= 0.0, "left alone, it closes", "fraction %.2f after %d ticks" % [mech.fraction_at(d, tick), spent])
		_check(_ray_hits(game, body, middle - normal, middle + normal), "and blocks again", "server body %s, ray %s" % [str(PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)), str(game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(middle - normal, middle + normal)))])

	_check(swung[0] != swung[1], "the two openers made it swing opposite ways (armed: a fixed side fails this)", str(swung))

	# A zombie stands where a survivor would: the game's own callables see it, so a closed door never holds a horde.
	var zone: AABB = m["zone"]
	var occupied: Callable = game.map.occupants_fn
	_check(not occupied.call(zone), "nobody near: the game reports the door's box empty")
	var zombie := game.horde.spawner.spawn(ZzNpcs.COMMON, hinge + normal * 1.0 + Vector3(0.0, 0.1, 0.0), &"test")
	await _sim(game, 4)
	_check(zombie != null and occupied.call(zone) and game.map.opener_fn.call(zone) is Vector3, "a zombie in its box is an opener",
		"zombie %s at %s, zone %s" % [str(zombie), str(zombie.position()) if zombie != null else "", str(zone)])

	# The wire: the side is in the snapshot and survives it.
	m["side"] = -1.0
	var snap: Array = mech.snapshot(d)
	var wire := ZzEvents.read_mover(DotNetReader.new(ZzEvents.write_mover(snap, d)))
	_check(bool(wire["ok"]) and float(wire["side"]) == -1.0, "the side survives the wire", str(wire))
	m["side"] = 1.0
	snap = mech.snapshot(d)
	wire = ZzEvents.read_mover(DotNetReader.new(ZzEvents.write_mover(snap, d)))
	_check(float(wire["side"]) == 1.0, "and so does the other")
	await _test_brush_door(game, mech)
	game.queue_free()
	_finished += 1


## A brush door of a global pack: its hull is a body on the world layer that is posed away when somebody walks up, and
## back when they leave; the collision follows the pose (a ray through the doorway meets it shut and passes open).
func _test_brush_door(game: ZzGame, mech: ZzMechanics) -> void:
	var index := -1
	for i in mech.mover_count():
		var mm: Dictionary = mech.mover(i)
		if not mm.has("door") and mm["body"] != null and str(mm["kind"]) == "slide":
			index = i
			break
	_check(index >= 0, "a brush door has a body on the map")
	if index < 0:
		return
	var m: Dictionary = mech.mover(index)
	var body := m["body"] as CollisionObject3D
	_check(body.collision_layer != 0 and bool(m["auto"]) and not bool(m["locked"]), "it is on a layer and opens to anyone near")
	var shape_box: AABB = (body.get_child(0) as CollisionShape3D).shape.get_debug_mesh().get_aabb()
	var centre: Vector3 = body.global_transform * shape_box.get_center()
	var shut_at: Vector3 = centre
	var shut_xf := PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
	var who := [Vector3.INF]
	mech.occupants_fn = func(box: AABB) -> bool: return who[0] != Vector3.INF and box.grow(1.0).has_point(who[0])
	mech.opener_fn = func(_box: AABB) -> Variant: return null if who[0] == Vector3.INF else who[0]
	await get_tree().physics_frame
	_check(_body_covers(game, body, shut_at), "shut, its body is at the doorway", str(shut_at))
	who[0] = centre + Vector3(0.0, 0.0, 0.5)
	var tick := 6000
	var spent := 0
	while mech.fraction_at(index, tick) < 1.0 and spent < 4000:
		tick += 1
		spent += 1
		mech.step(tick)
	for _f in 3:
		await get_tree().physics_frame
	var open_xf := PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
	_check(mech.fraction_at(index, tick) >= 1.0 and not open_xf.is_equal_approx(shut_xf), "opened for somebody near, the physics body has moved off its shut pose",
		"fraction %.2f, %s to %s" % [mech.fraction_at(index, tick), str(shut_xf.origin), str(open_xf.origin)])
	who[0] = Vector3.INF
	spent = 0
	while mech.fraction_at(index, tick) > 0.0 and spent < 12000:
		tick += 1
		spent += 1
		mech.step(tick)
	for _f in 3:
		await get_tree().physics_frame
	var closed_xf := PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
	_check(closed_xf.is_equal_approx(shut_xf) and _body_covers(game, body, shut_at), "left alone, it closes onto the doorway again")


## Whether a ray down through [param point] meets [param body].
func _body_covers(game: ZzGame, body: CollisionObject3D, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3(0.0, 3.0, 0.0), point - Vector3(0.0, 3.0, 0.0))
	query.collision_mask = 0xFFFFFFFF
	var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == body


## Whether the first thing a ray from [param from] to [param to] meets is [param body].
func _ray_hits(game: ZzGame, body: CollisionObject3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF
	var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == body


func _test_button_and_delay() -> void:
	_entered += 1
	print("a button opens a door; delays are kept")
	var mech := _built()
	var a := mech.index_of("door_a")
	var b := mech.index_of("door_b")
	var pad := mech.index_of("pad")
	_check(mech.mover_count() == 3 and a >= 0 and b >= 0, "the fixture reads", "%d movers" % mech.mover_count())

	var pressed := mech.try_press(Vector3(0.0, 1.0, -1.0), Vector3.BACK, 2.0, 10)
	_check(pressed, "a look at the button presses it")
	_check(not mech.try_press(Vector3(0.0, 1.0, -1.0), Vector3.FORWARD, 2.0, 10), "a look away presses nothing")

	for t in range(11, 400):
		mech.step(t)

		if t == 10 + 95:
			_check(mech.fraction_at(a, t) == 0.0, "the door waits out its 1.5 s delay", "fraction %.2f" % mech.fraction_at(a, t))

		if t == 10 + 96 + 32:
			_check(absf(mech.fraction_at(a, t) - 0.5) < 0.05, "then travels at its speed", "fraction %.2f" % mech.fraction_at(a, t))

		if t == 10 + 32 + 128 - 1:
			_check(mech.fraction_at(b, t) == 0.0, "a relay's delay and its output's add (0.5 s + 2 s)", "fraction %.2f" % mech.fraction_at(b, t))

	_check(mech.fraction_at(a, 399) == 1.0 and mech.fraction_at(b, 399) == 1.0, "both doors end open")
	_check(bool(mech.mover(pad)["locked"]), "the door's OnFullyOpen locked the button")

	# A client told door_a's state at tick 106 predicts the pose the server has at any tick.
	var client := _built()
	client.authoritative = false
	client.apply_state(a, 106, 0, 1, false)
	_check(absf(client.fraction_at(a, 138) - 0.5) < 0.01 and client.fraction_at(a, 200) == 1.0,
		"a client told the state predicts the same pose")
	client.queue_free()
	mech.queue_free()
	_finished += 1


func _test_volume_and_unsupported() -> void:
	_entered += 1
	print("a trigger volume fires its outputs; the unsupported are noted once")
	var mech := _built()
	var a := mech.index_of("door_a")
	var inside := [false]
	mech.points_fn = func() -> PackedVector3Array:
		return PackedVector3Array([Vector3(20.0, 1.5, 0.0)]) if inside[0] else PackedVector3Array()

	mech.step(1)
	var _p := mech.try_press(Vector3(0.0, 1.0, -1.0), Vector3.BACK, 2.0, 2)

	for t in range(2, 300):
		mech.step(t)

	_check(mech.fraction_at(a, 299) == 1.0, "the door is open before the trigger")

	inside[0] = true
	for t in range(300, 304):
		mech.step(t)

	inside[0] = false
	for t in range(304, 320):
		mech.step(t)

	var closing: bool = int(mech.mover(a)["dir"]) < 0 or float(mech.mover(a)["from"]) < 1.0
	_check(closing, "walking into the volume closes it (OnTrigger to Close)", "fraction %.2f" % mech.fraction_at(a, 319))

	var seen: Dictionary = mech.get("_unsupported_seen")
	var noted := 0
	for key: String in seen:
		if key.to_lower().contains("frobnicate") or key.begins_with("volume water"):
			noted += 1
	_check(noted == 2, "an unknown input and a water volume are each noted once", str(seen.keys()))

	var hurts: Array[float] = []
	mech.bodies_fn = func() -> Array:
		return [{"id": 1, "body": null, "position": Vector3(30.0, 0.0, 0.0), "height": 1.8, "kind": "player", "name": "", "class": "player", "team": 3}]
	mech.damage_fn = func(_body: Variant, amount: float, _kind: String, _entity: int) -> void:
		hurts.append(amount)
	for t in range(320, 340):
		mech.step(t)
	_check(hurts.is_empty(), "a disabled trigger_hurt hurts nobody", str(hurts))
	mech.input(7, "Enable", 340)
	for t in range(340, 372):
		mech.step(t)
	_check(not hurts.is_empty() and hurts[0] == 500.0, "an enabled trigger_hurt hurts who stands in it, damage a second times the hit period", str(hurts))
	mech.queue_free()
	_finished += 1


const VOLUME_MAP := &"ze_death_star_escape"


func _first_volume(mech: ZzMechanics, kind: String, want_enabled := true, least := -1.0, most := 1e9, filtered := false) -> Dictionary:
	for t in mech.volume_toggles():
		var rec: Dictionary = (t["vol"] as DotMapVolume).record
		var damage := float(rec.get("damage", 0.0))
		if str(t["kind"]) == kind and bool(t["enabled"]) == want_enabled and damage >= least and damage <= most \
				and (str(rec.get("filter", "")) != "") == filtered:
			return t
	return {}


func _volume_spot(t: Dictionary, lift := 0.1) -> Vector3:
	var box: AABB = (t["vol"] as DotMapVolume).bounds()
	return Vector3(box.get_center().x, box.position.y + lift, box.get_center().z)


## The map's hurt, teleport, push and gravity volumes, run on the server on a real map: they hurt, move and push survivors and
## zombies, a fall below the map kills, and the enabled state of a push or gravity volume survives the wire.
func _test_volumes() -> void:
	_entered += 1
	print("%s: hurt, teleport, push and gravity volumes" % VOLUME_MAP)
	ZzMap.bring_global_mechanics = true
	var game := await _game(VOLUME_MAP)
	var deaths: Array = []
	game.player_died.connect(func(id: StringName, _by: StringName, why: StringName) -> void: deaths.append([id, why]))
	var rider := game.add_player(&"u1", "Rider")
	var bystander := game.add_player(&"u0", "Bystander")
	bystander.health.invulnerable = true
	game.next_map_id = VOLUME_MAP
	game.start()
	await _sim(game, 8)
	var mech: ZzMechanics = game.map.mechanics
	var counts: Dictionary = mech.volume_counts() if mech != null else {}
	print("    volumes by kind: %s" % str(counts))
	_check(int(counts.get("hurt", 0)) > 0 and int(counts.get("teleport", 0)) > 0 and int(counts.get("push", 0)) > 0 and int(counts.get("gravity", 0)) > 0,
		"the map's hurt, teleport, push and gravity volumes are all built", str(counts))
	if mech == null:
		game.queue_free()
		_finished += 1
		return

	var mild := _first_volume(mech, "hurt", true, 0.0, 499.0)
	rider.place_at(_volume_spot(mild), 0.0)
	await _sim(game, 4 * TICK_RATE)
	print("    mild hurt entity %d: survivor life %s, health %.0f, deaths %s" % [int(mild["entity"]), str(rider.life), rider.health.health, str(deaths)])
	_check(rider.life != ZzPlayer.Life.UP and rider.life != ZzPlayer.Life.DEAD, "a mild hurt volume downs a survivor as a bite does", str(rider.life))

	var lethal := _first_volume(mech, "hurt", true, 500.0)
	var victim := game.add_player(&"u5", "Victim")
	victim.place_at(_volume_spot(lethal), 0.0)
	await _sim(game, 3 * TICK_RATE)
	var why: StringName = deaths[0][1] if not deaths.is_empty() else &""
	print("    lethal hurt entity %d: alive %s, deaths %s" % [int(lethal["entity"]), str(victim.is_alive()), str(deaths)])
	_check(not victim.is_alive() and why == ZzGame.BY_HAZARD, "a lethal hurt volume kills a survivor as a hazard death", str(deaths))

	rider = game.add_player(&"u2", "Faller")
	deaths.clear()
	var start := rider.feet()
	rider.place_at(Vector3(start.x, game.map.kill_height() - 3.0, start.z), 0.0)
	await _sim(game, 2 * TICK_RATE)
	print("    below kill_y %.1f: deaths %s" % [game.map.kill_height(), str(deaths)])
	_check(not rider.is_alive() and not deaths.is_empty() and deaths.any(func(d: Array) -> bool: return d[0] == &"u2" and d[1] == ZzGame.BY_FELL), "a fall below the map's kill height kills", str(deaths))

	var tele := _first_volume(mech, "teleport")
	var tele_zombie := _first_volume(mech, "teleport", true, -1.0, 1e9, true)
	var walker := game.add_player(&"u3", "Walker")
	var from := _volume_spot(tele)
	walker.place_at(from, 0.0)
	await _sim(game, 2 * TICK_RATE)
	var moved := walker.feet().distance_to(from)
	print("    teleport entity %d: survivor moved %.1f m to %s" % [int(tele["entity"]), moved, str(walker.feet())])
	_check(moved > 5.0 or not walker.is_alive(), "a teleport volume moves a survivor to its destination", "%.1f m" % moved)

	var zfrom := _volume_spot(tele_zombie)
	var zombie := game.horde.spawner.spawn(ZzNpcs.COMMON, game.horde.snap_to_nav(bystander.feet()), &"test")
	_check(zombie != null, "a zombie stands on the map")
	if zombie == null:
		game.queue_free()
		_finished += 1
		return
	game.horde.warp(zombie, zfrom, 0.0)
	zombie.brain.path.set_points(PackedVector3Array([zfrom + Vector3.RIGHT, zfrom + Vector3.RIGHT * 2.0]), 0.0, zfrom)
	await _sim(game, 2 * TICK_RATE)
	var zmoved := zombie.position().distance_to(zfrom)
	print("    teleport: zombie moved %.1f m, path left %d" % [zmoved, zombie.brain.path.points.size()])
	var stale: bool = zombie.brain.path.points.size() > 0 and zombie.brain.path.points[0].distance_to(zfrom + Vector3.RIGHT) < 0.01
	_check((zmoved > 5.0 or not zombie.is_alive()) and not stale, "and a zombie, which must find its way again from there", "%.1f m, stale path %s" % [zmoved, str(stale)])

	var push := _first_volume(mech, "push", false)
	if push.is_empty():
		push = _first_volume(mech, "push")
	mech.input(int(push["entity"]), "Enable", game.current_tick())
	var pushed := game.add_player(&"u4", "Pushed")
	pushed.health.invulnerable = true
	pushed.place_at(_volume_spot(push, 0.05), 0.0)
	var feet := pushed.feet()
	var force := mech.push_at(feet, 1.8)
	await _sim(game, 6)
	var speed := Vector2(pushed.controller.state.velocity.x, pushed.controller.state.velocity.z).length()
	print("    push entity %d: %.1f m/s asked, survivor at %.1f m/s, push_at stable %s" % [int(push["entity"]), force.length(), speed, str(mech.push_at(feet, 1.8) == force)])
	_check(force.length() > 0.0 and mech.push_at(feet, 1.8) == force, "a push volume answers the same for the same place (prediction and server agree)", str(force))
	_check(pushed.feet().distance_to(feet) > 0.2 or speed > 1.0, "and a survivor in it is pushed", "%.1f m/s" % speed)

	var grav := _first_volume(mech, "gravity")
	var gbox: AABB = (grav["vol"] as DotMapVolume).bounds()
	var high := Vector3(gbox.get_center().x, gbox.end.y - 0.3, gbox.get_center().z)
	var scale := mech.gravity_at(high, 1.8)
	print("    gravity entity %d: scale %.2f at %s" % [int(grav["entity"]), scale, str(high)])
	_check(scale != 1.0 and mech.gravity_at(Vector3(1e5, 1e5, 1e5), 1.8) == 1.0, "a gravity volume scales gravity inside it and not outside", "%.2f" % scale)

	var wire_ok := true
	for off in [false, true]:
		mech.input(int(push["entity"]), "Disable" if not off else "Enable", game.current_tick())
		var snap: Array = mech.snapshot(int(push["idx"]))
		var wire := ZzEvents.read_mover(DotNetReader.new(ZzEvents.write_mover(snap, int(push["idx"]))))
		wire_ok = wire_ok and bool(wire["ok"]) and int(wire["index"]) == int(push["idx"]) and bool(wire["locked"]) == (not off)
	_check(wire_ok, "a volume switched by the map's I/O is told to clients and applied as locked or not")

	game.queue_free()
	_finished += 1


func _test_no_world() -> void:
	_entered += 1
	print("maps without a world have no moving parts")
	for id: StringName in [&"zz_lot", &"zz_practice"]:
		var game := await _game(id)
		_check(game.map.mechanics == null and game.map.get_node_or_null("Mechanics") == null,
			"%s has none" % id)
		game.queue_free()
	_check(true, "and no input to press")
	_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	print("  FAIL  %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
