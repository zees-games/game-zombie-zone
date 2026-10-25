extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMechanics := preload("../game/zz_mechanics.gd")
const MapCommands := preload("../game/zz_map_commands.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapObjects := preload("../game/zz_map_objects.gd")
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
const SECTIONS := 14
const CHECKS := 134

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
	await _test_logic_fixture()
	await _test_zz_logic()
	await _test_real_zz_logic()
	await _test_logic_blockfort()
	await _test_logic_death_star()
	await _test_trail_targets()
	await _test_map_events()
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
		return {"from": from, "from_name": "", "output": output, "target": {1: "pad", 2: "door_a", 3: "relay", 4: "door_b"}.get(to, "t%d" % to), "input": input, "param": "", "delay": delay, "times": -1, "special": false, "to": [to]}
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


## Whether a ray down through [param point] meets [param body], past whatever else the world's hulls put above it.
func _body_covers(game: ZzGame, body: CollisionObject3D, point: Vector3) -> bool:
	var exclude: Array[RID] = []
	for attempt in 8:
		var query := PhysicsRayQueryParameters3D.create(point + Vector3(0.0, 3.0, 0.0), point - Vector3(0.0, 3.0, 0.0))
		query.collision_mask = 0xFFFFFFFF
		query.exclude = exclude
		var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		if hit["collider"] == body:
			return true
		exclude.append(hit["rid"])
	return false


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
	var gone: Dictionary = mech.logic().unhandled if mech.logic() != null else {}
	for key: Variant in seen.keys() + gone.keys():
		if str(key).to_lower().contains("frobnicate") or str(key).begins_with("volume water"):
			noted += 1
	_check(noted == 2, "an unknown input and a water volume are each noted once", str(seen.keys()) + str(gone.keys()))

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

	var god := game.add_player(&"u9", "God")
	deaths.clear()
	god.health.invulnerable = true
	god.place_at(Vector3(start.x, game.map.kill_height() - 3.0, start.z), 0.0)
	await _sim(game, 2 * TICK_RATE)
	_check(god.is_alive() and deaths.is_empty() and god.feet().y > game.map.kill_height(), "an invulnerable survivor below the kill height is put back, not reported as fallen", "%s %s" % [str(deaths), str(god.feet())])

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


# --- The map's logic (dot-map's DotMapIO under the mechanics) -----------------------------------

func _logic_rec(entity: int, classname: String, targetname: String, keys: Dictionary) -> Dictionary:
	return {"entity": entity, "classname": classname, "targetname": targetname, "target": "", "origin": [0.0, 0.0, 0.0], "treatment": "data", "keys": keys}


func _logic_link(from: int, output: String, target: String, input: String, to: Array, delay := 0.0, param := "") -> Dictionary:
	return {"from": from, "from_name": "", "output": output, "target": target, "input": input, "param": param, "delay": delay, "times": -1, "special": false, "to": to}


func _logic_fixture() -> Dictionary:
	var fx := _fixture()
	fx["volumes"] = []
	fx["movers"] = [fx["movers"][1]]
	fx["entities"] = [
		_logic_rec(10, "logic_relay", "relay_a", {}),
		_logic_rec(11, "math_counter", "cnt", {"min": "0", "max": "3"}),
		_logic_rec(12, "logic_relay", "relay_b", {}),
		_logic_rec(13, "game_text", "msg", {"message": "Hold!", "spawnflags": "1"}),
		_logic_rec(14, "logic_case", "case", {"case01": "a", "case02": "b"}),
		_logic_rec(15, "game_text", "msg_b", {"message": "Case B"}),
		_logic_rec(16, "logic_compare", "cmp", {"initialvalue": "1", "comparevalue": "1"}),
		_logic_rec(17, "logic_branch", "br", {"initialvalue": "0"}),
		_logic_rec(18, "env_entity_maker", "maker", {"entitytemplate": "tpl", "origin": "100 200 300"}),
		_logic_rec(19, "point_template", "tpl", {"template01": "prop_a", "spawnflags": "2"}),
		_logic_rec(20, "logic_relay", "prop_a", {}),
		_logic_rec(21, "npc_template_maker", "zmaker", {"templatename": "normal", "maxnpccount": "2", "spawnfrequency": "1", "origin": "100 200 300"}),
		_logic_rec(22, "point_servercommand", "cmd", {}),
		_logic_rec(23, "game_text", "msg_c", {"message": "Equal"}),
		_logic_rec(24, "game_text", "msg_d", {"message": "True"}),
		_logic_rec(25, "game_text", "msg_e", {"message": "Copy spawned"}),
	]
	var l := _logic_link
	fx["links"] = [
		l.call(10, "OnTrigger", "cnt", "Add", [11], 0.0, "1"),
		l.call(10, "OnTrigger", "relay_b", "Trigger", [12], 2.0),
		l.call(10, "OnTrigger", "msg", "Display", [13], 0.5),
		l.call(10, "OnTrigger", "ghost", "Trigger", [], 0.0),
		l.call(10, "OnTrigger", "cmd", "Command", [22], 0.0, "say Hello"),
		l.call(10, "OnTrigger", "cmd", "Command", [22], 0.0, "mp_friendlyfire 1"),
		l.call(10, "OnTrigger", "cmd", "Command", [22], 0.0, "sv_gravity 100"),
		l.call(10, "OnTrigger", "cmd", "Command", [22], 0.0, "quit"),
		l.call(12, "OnTrigger", "cnt", "Add", [11], 1.0, "2"),
		l.call(11, "OnHitMax", "door_a", "Open", [2]),
		l.call(14, "OnCase02", "msg_b", "Display", [15], 0.25),
		l.call(16, "OnEqualTo", "msg_c", "Display", [23]),
		l.call(17, "OnTrue", "msg_d", "Display", [24]),
		l.call(20, "OnSpawn", "msg_e", "Display", [25]),
	]
	return fx


func _logic_mech(fx: Dictionary) -> ZzMechanics:
	var mech := ZzMechanics.new()
	mech.tick_rate = TICK_RATE
	add_child(mech)
	mech.build(FakeWorld.new(fx), Callable())
	return mech


func _texts(events: Array) -> Array:
	return events.filter(func(e: Array) -> bool: return e[0] == "hud_text").map(func(e: Array) -> String: return str(e[1]["message"]))


func _test_logic_fixture() -> void:
	_entered += 1
	print("the map's logic: relays, counters, cases, compare, branch, texts, makers, commands")
	var mech := _logic_mech(_logic_fixture())
	var events: Array = []
	mech.logic_event.connect(func(kind: String, data: Dictionary) -> void: events.append([kind, data, mech.logic().now]))
	var io := mech.logic()
	_check(io != null and io.entities.size() >= 16, "every entity of the manifest is in the runtime", str(io.entities.size() if io != null else -1))
	mech.step(1)
	events.clear()
	var door := mech.index_of("door_a")
	var _r := io.send("relay_a", "Trigger")
	var at_text := -1
	var at_door := -1
	for t in range(2, 260):
		mech.step(t)
		if at_text < 0 and not _texts(events).is_empty():
			at_text = io.now
		if at_door < 0 and mech.fraction_at(door, t) > 0.0:
			at_door = io.now
	_check(at_text == 32, "a relay's output waits its 0.5 s (32 ticks) before the text shows", str(at_text))
	_check(_texts(events) == ["Hold!"], "and the text is the entity's message", str(_texts(events)))
	var counter := io.entity_of(11) as DotMapCounter
	_check(counter.value == 3.0, "the counter took 1 now and 2 after the second relay's 2 s + 1 s", str(counter.value))
	_check(at_door >= 192 and at_door <= 195, "its OnHitMax opened the door at the 3 s mark (delays add: 2 s + 1 s)", str(at_door))
	var npc_spawns := events.filter(func(e: Array) -> bool: return e[0] == "npc_spawn").size()
	var says := events.filter(func(e: Array) -> bool: return e[0] == "say")
	var cvars := events.filter(func(e: Array) -> bool: return e[0] == "cvar")
	_check(says.size() == 1 and cvars.size() == 1, "a chat line and the listed setting went to the game", "%d say, %d cvar" % [says.size(), cvars.size()])
	_check(io.commands.filter(func(c: Dictionary) -> bool: return not c["allowed"]).size() == 2, "a gravity change and a quit were denied, never run")
	var translated := MapCommands.translate("mp_friendlyfire", "1")
	_check(translated.get("key", "") == "zz_friendly_fire" and translated.get("value", -1.0) == 1.0 and MapCommands.translate("sv_gravity", "100").is_empty()
			and MapCommands.translate("zz_difficulty", "9").get("value", -1.0) == 3.0, "the whitelist maps a cvar onto a tunable and clamps it")
	var report := mech.logic_report()
	_check((report["unresolved"] as Dictionary).has("ghost") and (report["unresolved"] as Dictionary).size() == 1, "a link to a name nothing carries is reported", str(report["unresolved"]))

	events.clear()
	var _s := io.send("case", "InValue", "b")
	_s = io.send("case", "InValue", "zzz")
	_s = io.send("cmp", "Compare")
	_s = io.send("br", "SetValueTest", "1")
	for t in range(260, 260 + 20):
		mech.step(t)
	_check(_texts(events) == ["Equal", "True", "Case B"], "a case picks by value, a compare and a branch fire their branch", str(_texts(events)))

	events.clear()
	var before := io.entities.size()
	_s = io.send("maker", "ForceSpawn")
	var made := events.filter(func(e: Array) -> bool: return e[0] == "template_spawn").size()
	var at: Vector3 = (events.filter(func(e: Array) -> bool: return e[0] == "maker_spawn")[0][1]["at"]) if made > 0 else Vector3.ZERO
	_check(made == 1 and io.entities.size() == before + 1, "a maker's ForceSpawn copies its template's entity", "%d copies, %d entities" % [made, io.entities.size() - before])
	_check(at.distance_to(Vector3(100.0, 300.0, -200.0) * 0.0254) < 0.01, "and tells the game where the maker stands", str(at))
	_check(_texts(events) == ["Copy spawned"], "the copy runs its own OnSpawn output", str(_texts(events)))

	_check(npc_spawns == 2, "an NPC maker spawns MaxNPCCount zombies, a second apart, and stops", str(npc_spawns))
	mech.queue_free()
	_finished += 1


## The recorded-only classes now act: waves, win/lose, beats, game rules, score, game_ui, the maker's live cap and a brush copy.
func _test_zz_logic() -> void:
	_entered += 1
	print("the zombie logic: waves, win/lose, beats, rules, score, ui, maker cap, brush copies")
	var fx := _logic_fixture()
	fx["entities"] = [
		_logic_rec(30, "logic_waves", "waves", {"wave": "2"}),
		_logic_rec(31, "logic_winlose", "ending", {}),
		_logic_rec(32, "logic_beats", "beats", {"disableannoucner": "1"}),
		_logic_rec(33, "logic_gamerules", "rules", {"nestdistancemul": "2", "mp_friendlyfire": "1", "madeupkey": "7"}),
		_logic_rec(34, "game_score", "score", {"points": "5"}),
		_logic_rec(35, "game_ui", "ui", {}),
		_logic_rec(36, "npc_template_maker", "cap", {"templatename": "normal", "maxnpccount": "3", "maxlivechildren": "1", "spawnfrequency": "1"}),
		_logic_rec(37, "game_text", "t_wave", {"message": "Wave two"}),
		_logic_rec(38, "game_text", "t_win", {"message": "Won"}),
		_logic_rec(39, "logic_relay", "r", {}),
		_logic_rec(40, "logic_collision_pair", "pair", {"attach1": "a", "attach2": "b", "startdisabled": "0"}),
	]
	var l := _logic_link
	fx["links"] = [
		l.call(30, "OnWaveStart", "t_wave", "Display", [37]),
		l.call(31, "OnWin", "t_win", "Display", [38]),
	]
	var mech := _logic_mech(fx)
	var events: Array = []
	mech.logic_event.connect(func(kind: String, data: Dictionary) -> void: events.append([kind, data, mech.logic().now]))
	var io := mech.logic()
	var kinds := func(k: String) -> Array: return events.filter(func(e: Array) -> bool: return e[0] == k)
	mech.step(1)
	var rules: Array = kinds.call("game_rule")
	_check(rules.size() == 3, "a logic_gamerules tells the game each rule key once", str(rules.size()))
	_check(MapCommands.rule("nestdistancemul", "9").get("value", 0.0) == 3.0 and MapCommands.rule("nestdistancemul", "2").get("key", "") == "spawn_distance"
			and MapCommands.rule("madeupkey", "7").is_empty() and MapCommands.rule("mp_friendlyfire", "1").get("key", "") == "zz_friendly_fire",
			"the rule becomes a clamped runtime scale, a listed setting, or nothing")
	events.clear()
	mech.wave_changed(1)
	mech.wave_changed(2)
	for t in range(2, 6):
		mech.step(t)
	_check(_texts(events) == ["Wave two"], "a logic_waves fires only for the wave it names", str(_texts(events)))
	_check(mech.announcer_off(), "a logic_beats that disables the announcer says so")
	events.clear()
	var _s := io.send("ending", "Win")
	var d: Array = kinds.call("round_decide")
	_check(d.size() == 1 and d[0][1]["won"] == true, "a logic_winlose Win asks the game to decide for the survivors", str(d.size()))
	var _l := io.send("ending", "Lose")
	d = kinds.call("round_decide")
	_check(d.size() == 2 and d[1][1]["won"] == false, "and Lose for the infected")
	mech.round_decided(true)
	var ends: Array = kinds.call("round_end")
	_check(ends.size() == 1 and ends[0][1]["won"] == true and ends[0][1]["time_scale"] == 1.0, "a decided round tells the game how the map dresses its ending")
	for t in range(6, 10):
		mech.step(t)
	_check(_texts(events) == ["Won"], "its OnWin fires once the round is decided", str(_texts(events)))
	events.clear()
	_s = io.send("score", "ApplyScore", "", 0.0, "who")
	var sc: Array = kinds.call("score")
	_check(sc.size() == 1 and sc[0][1]["points"] == 5 and sc[0][1]["activator"] == "who", "a game_score hands its points and activator to the game", str(sc))
	_s = io.send("ui", "Activate", "", 0.0, "p1")
	var ui: Array = kinds.call("ui_active")
	_check(ui.size() == 1 and ui[0][1]["on"] == true and io.active_uis().size() == 1, "a game_ui Activate tells the game who holds the controls")
	var pressed := []
	mech.feed_uis(func(_e: int, _h: Variant) -> Dictionary: return {"attack": true})
	pressed = io.active_uis()
	_check(pressed.size() == 1, "feed_uis reaches the active ui")
	events.clear()
	var spawns := 0
	for t in range(10, 10 + 64 * 5):
		mech.step(t)
	spawns = kinds.call("npc_spawn").size()
	_check(spawns == 1, "a maker with one live child allowed stops spawning while it lives", str(spawns))
	mech.maker_child_gone(36)
	for t in range(10 + 64 * 5, 10 + 64 * 9):
		mech.step(t)
	spawns = kinds.call("npc_spawn").size()
	_check(spawns >= 2, "and spawns again once the child is dead or gone", str(spawns))
	mech.queue_free()
	_finished += 1


## Real maps: zs_lens ships waves, win/lose and beats; zm_4way_tunnel ships point_templates of brushes.
func _test_real_zz_logic() -> void:
	_entered += 1
	print("zs_lens and zm_4way_tunnel: the wave classes and brush templates on real maps")
	ZzMap.bring_global_mechanics = false
	var game := await _game(&"zs_lens", true)
	var mech: ZzMechanics = game.map.mechanics
	_check(mech != null and mech.logic() != null, "zs_lens builds a logic runtime")
	if mech != null and mech.logic() != null:
		var io := mech.logic()
		var count := func(c: GDScript) -> int: return io.entities.filter(func(e: DotMapEntity) -> bool: return is_instance_of(e, c)).size()
		_check(count.call(ZzMechanics.LogicWaves) > 0 and count.call(DotMapWinLose) > 0 and count.call(DotMapBeats) > 0,
			"its logic_waves, logic_winlose and logic_beats are the live classes, not records")
		mech.wave_changed(1)
		mech.wave_changed(1, true)
		_check(true, "a wave start and end run its outputs without error")
	game.queue_free()
	await get_tree().process_frame

	game = await _game(&"zm_4way_tunnel", true)
	mech = game.map.mechanics
	var models: Dictionary = mech.template_models() if mech != null else {}
	_check(not models.is_empty(), "zm_4way_tunnel names brush models in its point_templates", str(models.size()))
	if not models.is_empty():
		var model := int(models.keys()[0])
		mech.apply_copy(5000, model, Vector3(2.0, 0.0, 0.0), true, "func_breakable")
		var made: Array = mech.copies()
		_check(made.size() == 1, "a copy of one stands", str(made.size()))
		var body: Variant = (mech.get("_copies") as Dictionary)[5000]["body"]
		_check(body is StaticBody3D and (body as Node).get_child_count() > 0, "and, as a breakable, it is solid where it stands")
		mech.apply_copy(5000, model, Vector3.ZERO, false)
		_check(mech.copies().is_empty(), "and goes again")
	game.queue_free()
	await get_tree().process_frame

	game = await _game(&"zm_pathogen", true)
	mech = game.map.mechanics
	var tio: DotMapIO = mech.logic() if mech != null else null
	_check(tio != null and not tio.find("template_transmission2").is_empty(), "zm_pathogen builds its transmission templates")
	if tio != null and not tio.find("template_transmission2").is_empty():
		var door := tio.find("transmission_door2")[0] as DotMapEntity
		var _sent := tio.send("template_transmission2", "ForceSpawn")
		tio.settle()
		var made := tio.entities.filter(func(e: DotMapEntity) -> bool: return e.targetname.begins_with("transmission_door2&"))
		_check(made.size() == 1 and (made[0] as DotMapEntity).links.any(func(l: Dictionary) -> bool: return str(l["target"]) == (made[0] as DotMapEntity).targetname),
			"a door copy's own Kill names the copy, not the original", str(made.size()))
		tio.advance(40)
		var doorway: Dictionary = (mech.get("_copies") as Dictionary).get((made[0] as DotMapEntity).index, {}) if not made.is_empty() else {"body": 1}
		_check(door.alive and doorway.is_empty(), "the copy ran its Open to the end and was killed, so no frozen door is left standing; the original stays", "%s unhandled %s alive %s" % [doorway, tio.unhandled, (made[0] as DotMapEntity).alive])
	game.queue_free()
	_finished += 1


## zm_blockfort ships its logic: a counter that triggers a relay that shows text, a random-case modifier and template makers.
func _test_logic_blockfort() -> void:
	_entered += 1
	print("zm_blockfort: counter, relay, case, text and template makers on the real map")
	ZzMap.bring_global_mechanics = false
	var game := await _game(&"zm_blockfort", true)
	var mech: ZzMechanics = game.map.mechanics
	_check(mech != null and mech.logic() != null, "a global pack builds the logic runtime")
	if mech == null or mech.logic() == null:
		game.queue_free()
		_finished += 1
		return
	var io := mech.logic()
	var report := mech.logic_report()
	var manifest_unresolved: int = mech.get("_ents").links.unresolved().size()
	var left := 0
	for n: Variant in (report["unresolved"] as Dictionary).values():
		left += int(n)
	print("    %d entities, links with no target: %d in the manifest, %d in the runtime; unhandled %s" % [int(report["entities"]), manifest_unresolved, left, str(report["unhandled"])])
	_check(int(report["entities"]) > 500 and left <= manifest_unresolved, "the runtime leaves no link to a name nothing carries", "%d -> %d" % [manifest_unresolved, left])

	var events: Array = []
	mech.logic_event.connect(func(kind: String, data: Dictionary) -> void: events.append([kind, data]))
	var counter := io.entities.filter(func(e: DotMapEntity) -> bool: return e.targetname == "mod_counter")[0] as DotMapCounter
	for i in 3:
		var _r := io.send("mod_counter", "Add", "1")
	_check(_texts(events).is_empty() and counter.value == 3.0, "three adds to a counter that stops at 4 show nothing yet")
	var _s := io.send("mod_counter", "Add", "1")
	_check(_texts(events).size() == 1 and _texts(events)[0].begins_with("Round modifier activated"), "the fourth hits max, triggers the relay and shows its text", str(_texts(events)))

	events.clear()
	var before := io.entities.size()
	_s = io.send("base_snowman_spawner", "ForceSpawn")
	_check(events.filter(func(e: Array) -> bool: return e[0] == "template_spawn").size() >= 1 and io.entities.size() > before,
		"a template maker spawns its template on ForceSpawn", "%d entities" % (io.entities.size() - before))

	events.clear()
	_s = io.send("mod_random", "PickRandom")
	await _sim(game, 6 * TICK_RATE)
	_check(_texts(events).size() == 1, "a random case starts one of the round modifiers after its 5 s", str(_texts(events)))
	game.queue_free()
	_finished += 1


## ze_death_star_escape in a global pack: the compare that switches the push volumes on later, and the push speed set by the map.
func _test_logic_death_star() -> void:
	_entered += 1
	print("%s: the map's links run in a global pack, pushes switch on later and carry their speed" % VOLUME_MAP)
	ZzMap.bring_global_mechanics = false
	var game := await _game(VOLUME_MAP, true)
	var mech: ZzMechanics = game.map.mechanics
	if mech == null or mech.logic() == null:
		_check(false, "the global pack builds its logic")
		game.queue_free()
		_finished += 1
		return
	var io := mech.logic()
	var events: Array = []
	mech.logic_event.connect(func(kind: String, data: Dictionary) -> void: events.append([kind, data]))
	var push := {}
	for t in mech.volume_toggles():
		if str(t["kind"]) == "push" and (t["vol"] as DotMapVolume).targetname == "push":
			push = t
	_check(not push.is_empty(), "the map's pushes are built", str(mech.volume_counts()))
	var _r := io.send("push", "Disable")
	_check(not bool(push["enabled"]), "a map output can switch a push off")
	_r = io.send("compare", "SetValue", "1")
	_r = io.send("compare", "Compare")
	_check(bool(push["enabled"]), "the map's compare switches it on", "")
	await _sim(game, 6 * TICK_RATE + 8)
	_check(not bool(push["enabled"]), "and its delayed Disable switches it off again 5 s later")

	var spot := _volume_spot(push, 0.05)
	_r = io.send("push", "Enable")
	var before := mech.push_at(spot, 1.8)
	_r = io.send("push", "SetPushSpeed", "1000")
	var after := mech.push_at(spot, 1.8)
	_check(absf(after.length() - 19.0) < 0.2 and not is_equal_approx(before.length(), after.length()), "SetPushSpeed changes what prediction asks for", "%.1f -> %.1f m/s" % [before.length(), after.length()])
	var wire := ZzEvents.read_mover(DotNetReader.new(ZzEvents.write_mover(mech.snapshot(int(push["idx"])), int(push["idx"]))))
	var client := ZzMechanics.new()
	client.authoritative = false
	client.name = "Client"
	add_child(client)
	_check(int(wire["start"]) != 0 and absf(ZzMechanics.unpack_push(int(wire["start"])).length() - after.length()) < 0.01, "and the new push crosses the wire", str(wire))
	client.queue_free()

	var says := events.filter(func(e: Array) -> bool: return e[0] == "say")
	_check(not says.is_empty() and events.filter(func(e: Array) -> bool: return e[0] == "cvar").is_empty(), "the map's chat lines reach the game and its gravity command does not", "%d say" % says.size())
	game.queue_free()
	_finished += 1


## A spritetrail's parentname finds a mover's drawn node (what DotMapFx.trail_target_fn calls).
func _test_trail_targets() -> void:
	_entered += 1
	print("a trail finds the mover it follows")
	var mech := _built()
	_check(mech.node_named("door_a") == null, "before the world is drawn there is no node to follow")
	var root := Node3D.new()
	var drawn := Node3D.new()
	drawn.set_meta(&"model", 2)
	root.add_child(drawn)
	mech.bind_drawn(root)
	_check(mech.node_named("door_a") == drawn, "a mover is found by its targetname once drawn")
	_check(mech.node_named("DOOR_A") == drawn, "whatever the case the map wrote")
	_check(mech.node_named("door_b") == null and mech.node_named("nothing") == null, "a mover not drawn, or no mover, is null (the trail follows itself)")
	root.free()
	mech.queue_free()
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


## The events dot-map added: a breakable's spawn_object, the ambient fade and spin, and a start point that begins disabled and is switched on by an input.
func _test_map_events() -> void:
	_entered += 1
	print("map events: spawn_object, sound fade and spin, disabled start points")
	var fx := _fixture()
	fx["volumes"] = []
	fx["movers"] = [fx["movers"][1]]
	fx["entities"] = [
		_logic_rec(10, "logic_relay", "switch", {}),
		_logic_rec(11, "info_player_human", "late", {"origin": "100 200 0", "startdisabled": "1", "angles": "0 90 0"}),
		_logic_rec(12, "info_player_human", "other", {"origin": "500 200 0"}),
		_logic_rec(13, "func_breakable", "crate", {"health": "5", "spawnobject": "2"}),
	]
	fx["links"] = [_logic_link(10, "OnTrigger", "late", "Enable", [11])]
	var mech := _logic_mech(fx)
	var events: Array = []
	mech.logic_event.connect(func(kind: String, data: Dictionary) -> void: events.append([kind, data]))
	var io := mech.logic()
	var points := mech.spawn_entities()
	_check(points.size() == 2 and points[0]["name"] == "late" and not points[0]["enabled"] and points[1]["enabled"], "both start points are read, the first disabled", str(points))

	var map := ZzMap.new()
	map.doc = {"spawns": {"survivors": [{"at": [100.0 * 0.0254, 0.0, -200.0 * 0.0254], "yaw": 0.0}, {"at": [500.0 * 0.0254, 0.0, -200.0 * 0.0254], "yaw": 0.0}]}}
	map.mechanics = mech
	var seat0: Array = map.spawn("survivors", 0)
	_check(is_equal_approx((seat0[0] as Vector3).x, 500.0 * 0.0254), "a disabled start point is skipped by spawn selection", str(seat0[0]))
	var _s := io.send("switch", "Trigger")
	mech.step(1)
	mech.step(2)
	_check(map.spawn("survivors", 0)[0].x < 3.0 and map.spawn_enabled(map.doc["spawns"]["survivors"][0]), "the Enable input brings it back, found by position", str(map.spawn("survivors", 0)[0]))
	_s = io.send("late", "Disable")
	_s = io.send("other", "Disable")
	_check(map.spawn("survivors", 0).size() == 2 and not map.spawn_enabled(map.doc["spawns"]["survivors"][1]), "a map that disabled everything still starts somebody")
	map.doc["spawns"]["survivors"][1]["name"] = "ghost"
	_check(not map.spawn_enabled({"at": [9.0, 0.0, 9.0], "name": "ghost", "disabled": true}), "a named point nothing matches falls back to the document's disabled flag")
	map.free()

	var long_name := "x".repeat(70)
	var fx2 := _fixture()
	fx2["volumes"] = []
	fx2["movers"] = [fx2["movers"][1]]
	fx2["entities"] = [
		_logic_rec(11, "info_player_human", "dup", {"origin": "100 200 0", "startdisabled": "1"}),
		_logic_rec(12, "info_player_human", "dup", {"origin": "500 200 0"}),
		_logic_rec(13, "info_player_human", long_name, {"origin": "900 200 0", "startdisabled": "1"}),
	]
	fx2["links"] = []
	var map2 := ZzMap.new()
	map2.mechanics = _logic_mech(fx2)
	var dup_a := {"at": [100.0 * 0.0254, 0.0, -200.0 * 0.0254], "name": "dup"}
	var dup_b := {"at": [500.0 * 0.0254, 0.0, -200.0 * 0.0254], "name": "dup"}
	_check(not map2.spawn_enabled(dup_a) and map2.spawn_enabled(dup_b), "start points sharing a targetname each keep their own state", "%s %s" % [map2.spawn_enabled(dup_a), map2.spawn_enabled(dup_b)])
	_check(not map2.spawn_enabled({"at": [900.0 * 0.0254, 0.0, -200.0 * 0.0254], "name": long_name.left(64)}), "a name the document cut to 64 characters still matches")
	map2.free()

	_s = io.send("crate", "Break")
	var made := events.filter(func(e: Array) -> bool: return e[0] == "spawn_object")
	_check(made.size() == 1 and int(made[0][1]["object"]) == 2, "a broken crate says which object it leaves", str(made))
	mech.queue_free()

	var driver_root := Node3D.new()
	add_child(driver_root)
	var player := AudioStreamPlayer3D.new()
	player.name = "hum"
	player.set_meta(&"dot_map_entity", 7)
	player.set_meta(&"dot_map_gain_scale", 1.0)
	driver_root.add_child(player)
	var driver := DotMapSoundDriver.new()
	driver.root = driver_root
	driver_root.add_child(driver)
	var _d := driver.handle("sound_fade", {"entity": 7, "name": "hum", "seconds": 0.0, "from": 1.0, "to": 0.5})
	_check(absf(player.volume_db - linear_to_db(0.5)) < 0.01, "sound_fade reaches the map's player by entity", str(player.volume_db))
	_d = driver.handle("sound_spin", {"entity": 7, "seconds": 90000.0, "from": 100.0, "to": 150.0})
	_check(is_equal_approx(player.pitch_scale, 1.0), "sound_spin starts at its pitch and a huge duration is clamped, not trusted")
	_check(not driver.handle("sound_spin", {"entity": 99, "name": "../x"}), "an unknown player is ignored")
	driver_root.queue_free()

	var game := await _game(&"zz_practice")
	var objects: Variant = game.map_objects
	var floor_at := Vector3(0.0, 0.2, 0.0)
	_check(objects.spawn(0, floor_at) == -1 and objects.spawn(1, floor_at) == -1 and objects.spawn(10, floor_at) == -1 and objects.spawn(-4, floor_at) == -1, "unknown objects (nothing, battery, past the list, negative) lay nothing")
	var before: int = game.loot.entries.size()
	var medkit: int = objects.spawn(2, floor_at)
	_check(medkit > 0 and game.loot.kind_of(medkit) == ZzLoot.MEDKIT and game.loot.entries.size() == before + 1, "object 2 lays a medkit")
	var ammo: int = objects.spawn(5, floor_at)
	_check(ammo > 0 and game.loot.kind_of(ammo) == ZzLoot.AMMO and float(game.loot.entries[ammo]["fraction"]) > 0.0, "object 5 lays a part-filled ammo pile")
	_check(objects.spawn(2, Vector3(INF, 0.0, 0.0)) == -1 and objects.spawn(2, Vector3(1.0e9, 0.0, 0.0)) == -1, "a non-finite or absurd place lays nothing")
	var held: int = game.loot.entries.size()
	game._on_map_logic_event("spawn_object", {"entity": 1, "name": "nothing_by_this_name", "object": 2, "at": Vector3.ZERO})
	_check(game.loot.entries.size() == held, "an event with no place and no node to find lays nothing")
	game._on_map_logic_event("spawn_object", {"entity": 1, "name": "", "object": 2, "at": floor_at})
	_check(game.loot.entries.size() == held + 1, "the game's handler lays the piece at the event's place")
	for i in 40:
		var _laid: int = objects.spawn(3, floor_at)
	var lying := 0
	for e: Dictionary in game.loot.entries.values():
		lying += 1 if e["until"] > 0.0 else 0
	_check(lying <= ZzMapObjects.MAX_LYING, "pieces lying at once are capped", str(lying))
	game.queue_free()
	_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	print("  FAIL  %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
