extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMechanics := preload("../game/zz_mechanics.gd")
const ZzEvents := preload("../game/net/zz_events.gd")

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
const SECTIONS := 5
const CHECKS := 27

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
	await _test_button_and_delay()
	await _test_volume_and_unsupported()
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
			{"entity": 6, "model": 6, "kind": "hurt", "classname": "trigger_hurt", "targetname": "", "wait": 0.0, "disabled": false,
				"brushes": [], "outputs": []},
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
		if key.to_lower().contains("frobnicate") or key.begins_with("volume hurt"):
			noted += 1
	_check(noted == 2, "an unknown input and a hurt volume are each noted once", str(seen.keys()))
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


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	print("  FAIL  %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
