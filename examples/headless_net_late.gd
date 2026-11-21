extends "headless_net_base.gd"

## The net suite's later sections: gates, doors, map cues, drops, the ending, the hold and leaving.


func _test_a_gate_reaches_the_client() -> void:
	_section("a gate opened on the server opens on the client")
	_server_game.open_gate("barrier")
	await _steps(4)
	_check(str(_heard.get("gate", "")) == "barrier", "the client is told")
	_check(not _client_game.map.gate_is_shut("barrier"), "and its barrier is up: nobody walks into a wall that is not there")
	_finished()


## A world of one hinged prop door, as gs-map's manifest writes it.
class DoorWorld extends RefCounted:
	var ents: Variant = GSMapEntities.from_manifest({"movers": [{"entity": 900, "model": null, "kind": "rotate", "classname": "prop_door_rotating",
		"targetname": "", "origin": [60.0, 0.0, 60.0], "axis": [0.0, 1.0, 0.0], "degrees": 90.0, "speed": 100.0, "travel_time": 0.9, "wait": 4.0,
		"open_dir": 0, "yaw": 0.0, "use": true, "touch": false, "solid": true, "locked": false, "start_open": false, "outputs": [], "opened_by": []},
		{"classname": "func_door", "direction": [0.0, 1.0, 0.0], "distance": 3.0, "entity": 901, "kind": "slide", "lip": 0.0, "locked": false,
		"maxs": [90.5, 3.0, 70.5], "mins": [89.5, 0.0, 69.5], "model": 7, "opened_by": [], "origin": [90.0, 1.5, 70.0], "outputs": [],
		"solid": true, "spawnflags": 256, "speed": 3.0, "start_open": false, "targetname": "", "toggle": false, "touch": false,
		"travel_time": 1.0, "use": true, "wait": 4.0}]})

	func entities() -> Variant:
		return ents

	func models() -> PackedInt32Array:
		return PackedInt32Array([7])

	func hull_shapes(_model: int, _kinds: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 3.0, 1.0)
		return [{"shape": box, "kind": "solid", "brush": 0}]


func _test_a_door_reaches_the_client() -> void:
	_section("a door a survivor opens on the server swings open on the client, away from them")
	for game: ZzGame in [_server_game, _client_game]:
		game.map.attach_mechanics(DoorWorld.new(), true)
	var server_door: ZzMechanics = _server_game.map.mechanics
	var client_door: ZzMechanics = _client_game.map.mechanics
	_check(server_door != null and client_door != null and client_door.mover_count() == 2, "both ends stand the doors up: a prop door and a brush door")

	if server_door == null or client_door == null:
		_finished()
		return

	var hinge := Vector3(60.0, 0.0, 60.0)
	await _steps(6)
	_check(float(client_door.mover(0)["from"]) == 0.0 and int(client_door.mover(0)["dir"]) == 0, "armed: with nobody near, the door stays shut on the client")
	_stand_in.place_at(hinge + Vector3(-1.0, 0.0, -0.5), 0.0)
	await _steps(90)
	_check(int(server_door.mover(0)["dir"]) != 0 or float(server_door.mover(0)["from"]) > 0.0, "the server opens it to a survivor at the door")
	_check(int(client_door.mover(0)["dir"]) > 0 or float(client_door.mover(0)["from"]) > 0.0, "and the client was told: it swings too")
	_check(float(server_door.mover(0)["side"]) == -1.0 and float(client_door.mover(0)["side"]) == -1.0, "away from somebody on the far side, the same on both ends (armed: the default is +1)", "server %s, client %s" % [str(server_door.mover(0)["side"]), str(client_door.mover(0)["side"])])
	var shown := (client_door.mover(0)["node"] as Node3D).transform.basis
	_check(not shown.is_equal_approx((client_door.mover(0)["base"] as Transform3D).basis), "and its drawn panel has turned off its closed pose")
	# The brush door (index 1): shut on the client until somebody walks up, then told, and its body is posed off the doorway.
	_check(float(client_door.mover(1)["from"]) == 0.0 and int(client_door.mover(1)["dir"]) == 0 and client_door.mover(1)["body"] != null,
		"armed: the brush door has a body and stays shut on the client while nobody is near")
	_stand_in.place_at(Vector3(90.0, 0.0, 71.0), 0.0)
	await _steps(90)
	_check(int(server_door.mover(1)["dir"]) > 0 or float(server_door.mover(1)["from"]) > 0.0, "the server opens the brush door to a survivor at it")
	_check(int(client_door.mover(1)["dir"]) > 0 or float(client_door.mover(1)["from"]) > 0.0, "and the client was told: its brush door slides open too")
	var body := client_door.mover(1)["body"] as CollisionObject3D
	var posed := PhysicsServer3D.body_get_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
	_check(posed.origin.y > 1.5 + 0.1, "and the client's collision body rose with it", str(posed.origin))
	server_door.apply_copy(900, int(server_door.mover(1)["model"]), Vector3(4.0, 0.0, 0.0), true)
	await _steps(6)
	_check(client_door.copies().size() == 1 and int(client_door.copies()[0]["id"]) == 900, "a brush copy the map's template made on the server stands on the client", str(client_door.copies()))
	var slot := server_door.copy_mover_index(900)
	_check(slot >= 0 and int(client_door.copies()[0]["mover"]) == slot, "the copy carries the same mover index on both ends", "server %d, client %s" % [slot, str(client_door.copies())])
	_stand_in.place_at(STREET + Vector3(2.0, 0.0, 1.0), 0.0)
	await _steps(30)
	var rest_y := (client_door.mover(slot)["body"] as Node3D).global_position.y if client_door.mover(slot)["body"] != null else NAN
	_check(not is_nan(rest_y) and int(client_door.mover(slot)["dir"]) == 0 and float(client_door.mover(slot)["from"]) == 0.0, "armed: the copy door is shut and has a body on the client", str(rest_y))
	server_door.input(900, "Open", _tick)
	await _steps(120)
	_check(float(server_door.mover(slot)["from"]) >= 1.0 or int(server_door.mover(slot)["dir"]) > 0, "a copy door opens on the server")
	_check(float(client_door.mover(slot)["from"]) >= 1.0 or int(client_door.mover(slot)["dir"]) > 0, "and the client was told: its copy moves too")
	var copy_body := client_door.mover(slot)["body"] as CollisionObject3D
	var copy_posed := PhysicsServer3D.body_get_state(copy_body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
	_check(copy_posed.origin.y > rest_y + 0.1, "the client's copy body rose with it", str(copy_posed.origin))
	server_door.reset(_tick)
	await _steps(6)
	_check(client_door.copies().is_empty() and server_door.copies().is_empty(), "a new round clears the copies on both ends")
	server_door.apply_copy(901, int(server_door.mover(1)["model"]), Vector3(4.0, 0.0, 0.0), true)
	_check(server_door.copy_mover_index(901) == slot, "and the copy mover indices start over", str(server_door.copy_mover_index(901)))
	server_door.apply_copy(901, int(server_door.mover(1)["model"]), Vector3.ZERO, false)
	await _steps(6)
	_check(client_door.copies().is_empty(), "and goes from the client when it goes from the server")
	_stand_in.place_at(STREET + Vector3(2.0, 0.0, 1.0), 0.0)
	_finished()


func _test_map_cues_reach_the_client() -> void:
	_section("a map's sound fades, spins and beats reach the client")
	var heard_fx: Array = []
	var on_fade := func(entity: int, fading_in: bool, seconds: float, from: float, to: float) -> void: heard_fx.append(["fade", entity, fading_in, seconds, from, to])
	var on_spin := func(entity: int, seconds: float, from: float, to: float) -> void: heard_fx.append(["spin", entity, seconds, from, to])
	var on_beat := func(beat: int, downbeat: bool) -> void: heard_fx.append(["beat", beat, downbeat])
	_client_game.map_sound_fade.connect(on_fade)
	_client_game.map_sound_spin.connect(on_spin)
	_client_game.map_beat.connect(on_beat)

	_server_game._on_map_logic_event("sound_fade", {"entity": 12, "name": "hum", "in": true, "seconds": 3.0, "from": 0.0, "to": 0.5})
	_server_game._on_map_logic_event("sound_spin", {"entity": 12, "name": "hum", "seconds": 2.0, "from": 50.0, "to": 100.0})
	_server_game._on_map_logic_event("beat", {"beat": 3, "downbeat": true})
	await _steps(6)
	var fades := heard_fx.filter(func(h: Array) -> bool: return h[0] == "fade")
	var spins := heard_fx.filter(func(h: Array) -> bool: return h[0] == "spin")
	var beats := heard_fx.filter(func(h: Array) -> bool: return h[0] == "beat")
	_check(fades.size() == 1 and fades[0][1] == 12 and fades[0][2] == true and absf(float(fades[0][3]) - 3.0) < 0.11 and absf(float(fades[0][5]) - 0.5) < 0.01, "a sound_fade reaches the client with its entity, direction, seconds and volume", str(fades))
	_check(spins.size() == 1 and spins[0][1] == 12 and float(spins[0][3]) == 50.0 and float(spins[0][4]) == 100.0, "a sound_spin reaches the client with its pitches", str(spins))
	_check(beats.size() == 1 and beats[0][1] == 3 and beats[0][2] == true, "a beat reaches the client with its number and downbeat", str(beats))

	var endings: Array = []
	var on_end := func(won: bool, scale: float, seconds: float, camera: Variant) -> void: endings.append([won, scale, seconds, camera])
	_client_game.map_ending.connect(on_end)
	_server_game._on_map_logic_event("round_end", {"won": true, "time_scale": 0.0, "seconds": 99.0, "camera": Vector3(4.0, 1.0, 2.0)})
	await _steps(6)
	_client_game.map_ending.disconnect(on_end)
	_check(endings.size() == 1 and endings[0][0] == true and endings[0][1] == ZzEvents.END_SCALE_MIN and endings[0][2] == ZzEvents.END_SECONDS_MAX
		and (endings[0][3] as Vector3).distance_to(Vector3(4.0, 1.0, 2.0)) < 0.05, "a round_end reaches the client with its slow motion and camera point, clamped", str(endings))

	heard_fx.clear()
	for i in 200:
		_server_game._on_map_logic_event("beat", {"beat": i % 256, "downbeat": false})
	await _steps(6)
	_check(heard_fx.size() > 0 and heard_fx.size() < 40, "a burst of 200 beats is rate-limited, not queued", str(heard_fx.size()))

	_client_game.map_sound_fade.disconnect(on_fade)
	_client_game.map_sound_spin.disconnect(on_spin)
	_client_game.map_beat.disconnect(on_beat)
	_finished()


func _test_a_map_drop_reaches_the_client() -> void:
	_section("a breakable's spawn_object lays a piece the client is told of")
	var at := STREET + Vector3(-1.0, 0.2, -2.0)
	_heard.erase("loot")
	var before: int = _server_game.loot.entries.size()
	_server_game._on_map_logic_event("spawn_object", {"entity": 3, "name": "", "object": 2, "at": at})
	await _steps(4)
	_check(_server_game.loot.entries.size() == before + 1, "the server lays one piece", str(_server_game.loot.entries.size()))
	_check(_heard.has("loot") and _heard["loot"][1] == ZzLoot.MEDKIT, "the client is told of a medkit", str(_heard.get("loot")))
	_check(_heard.has("loot") and absf((_heard["loot"][2] as Vector3).x - at.x) < 0.5 and absf((_heard["loot"][2] as Vector3).z - at.z) < 0.5,
		"where the break was", str(_heard.get("loot")))
	var made: int = int(_heard["loot"][0]) if _heard.has("loot") else -1
	_heard.erase("loot")
	_server_game._on_map_logic_event("spawn_object", {"entity": 3, "name": "", "object": 99, "at": at})
	await _steps(4)
	_check(not _heard.has("loot"), "an object number off the list tells the client nothing")
	if made > 0:
		_server_game.loot.remove(made, _server_me().player_id)
		await _steps(3)
	_finished()


func _test_the_map_ends() -> void:
	_section("the map ends, and the client is told how and why")
	_server_game._decide(false, "everybody is down")

	for _i in range(SERVER_TICK_RATE * 4):
		if _heard.has("round_over"):
			break
		await _step()

	_check(_heard.has("round_over") and not bool(_heard["round_over"][1]), "lost")
	_check(_heard.has("round_over") and str(_heard["round_over"][2]) == "everybody is down", "with the server's sentence")
	_check(_heard.has("round_over") and float(_heard["round_over"][3]) == _server_game.match_node.rules.intermission_sec
		and StringName(_heard["round_over"][4]) == _server_game.next_map_id,
		"and how long until the next map, and which, for its countdown", str(_heard.get("round_over")))
	var kc := ZzKillcam.new()
	_check(kc.camera_mode_fn.call() == GSKillViewRules.Camera.EYE, "the killcam camera is the eye until the server says")
	var framing := GSKillcamFraming.new(null, 1)
	var eye := Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0))
	var placed: Dictionary = framing.place(GSKillViewRules.Camera.BEHIND, eye, 75.0, Vector3(0, 1.2, -20))
	_check((placed["transform"] as Transform3D).origin.z > 1.0, "the behind camera sits behind the killer's eye")
	kc.free()
	_finished()


## A survival hold through the bridge: the stage, wave and clock a client is told, the daylight of
## a hold kept by nights, and a barricade broken and mended reaching the client's map, its
## collision and its picture.
func _test_a_hold_reaches_the_client() -> void:
	_section("a survival hold, its daylight and a barricade, over the wire")
	var doc := ZzCatalogue.practice().duplicate(true)
	doc["id"] = "zz_net_hold"
	doc["mode"] = ZzMapDoc.SURVIVAL
	doc["objectives"] = []
	# Boards across the west alley's mouth, on the street side.
	(doc["boxes"] as Array).append({"at": [-9.2, 1.0, 16.0], "size": [0.3, 2.0, 3.6], "mat": "wood",
		"barricade": "alley_w", "nav": false})
	var checked := ZzMapDoc.validate(doc)
	_check(checked.ok and _server_game.catalogue._add(checked.value, "test"), "the server has a hold with a barricade",
		checked.error.message if not checked.ok else "")
	_server_game.catalogue._rebuild_order()

	# Nights, short: a warm-up that is a day (dawn and dusk), then a night.
	var config := _server_game.config
	config.map_ids = PackedStringArray(["zz_practice", "zz_net_hold"])
	config.survival_style = 1
	config.nights = 2
	config.survival_warmup_seconds = 4.0
	config.night_seconds = 3.0
	config.day_seconds = 3.0
	config.wave_size = 2
	config.wave_size_per_survivor = 0
	config.wave_twists = false
	config.brute_every_waves = 0
	# The client draws this map, so the barricade's picture is there to follow.
	_client_game.draw_world = true
	_client_game.map.draw_world = true
	_heard.erase("map")
	var changed := _server_game.change_map_now(&"zz_net_hold")
	for _i in range(SERVER_TICK_RATE * 2):
		if _heard.get("map", &"") == &"zz_net_hold":
			break
		await _step()
	_check(changed.ok and _client_game.map.id() == &"zz_net_hold" and _client_game.is_survival(),
		"the client is sent the hold and builds it", "%s %s" % [_client_game.map.id(), changed.error.message if not changed.ok else ""])

	# The same map told again (a new round on it) neither tears the world down nor puts the cover back.
	var again := {"clearing": 0, "incoming": 0, "repeated": 0}
	var on_clearing := func() -> void: again["clearing"] += 1
	var on_incoming := func() -> void: again["incoming"] += 1
	var on_repeated := func(_id: StringName) -> void: again["repeated"] += 1
	_client_game.world_clearing.connect(on_clearing)
	_client_bridge.map_incoming.connect(on_incoming)
	_client_bridge.map_repeated.connect(on_repeated)
	var built_bytes: PackedByteArray = _client_bridge.get("_built_bytes")
	_client_bridge.call("_build_told_map", built_bytes)
	var first_piece := built_bytes.slice(0, ZzEvents.MAP_PART_BYTES)
	var pieces := (built_bytes.size() + ZzEvents.MAP_PART_BYTES - 1) / ZzEvents.MAP_PART_BYTES
	var same_prefix: bool = _client_bridge.call("_is_built_prefix", 0, pieces, first_piece)
	var other_prefix: bool = _client_bridge.call("_is_built_prefix", 0, pieces + 1, first_piece)
	_client_game.world_clearing.disconnect(on_clearing)
	_client_bridge.map_incoming.disconnect(on_incoming)
	_client_bridge.map_repeated.disconnect(on_repeated)
	_check(int(again["clearing"]) == 0 and int(again["incoming"]) == 0 and int(again["repeated"]) == 1,
		"an identical map told again is not rebuilt and holds no cover", str(again))
	_check(same_prefix and not other_prefix, "a first piece that matches the built map is known, one of a different map is not")

	await _check_hold_clock()
	await _check_hold_barricade()
	_finished()


## The warm-up's style, stage and daylight, and night one falling on the client.
func _check_hold_clock() -> void:
	# Mid warm-up: what the hold says, and the light it is at.
	await _steps(int(SERVER_TICK_RATE * 2.0))
	var served := _server_game.survival_state()
	var told := _client_game.survival_state()
	_check(not told.is_empty() and int(told.get("style", -1)) == int(served["style"])
		and int(told.get("stage", -1)) == int(served["stage"]) and int(told.get("index", -1)) == int(served["index"])
		and absf(float(told.get("left", -9.0)) - float(served["left"])) < 0.75,
		"the client is told the style, the stage, the night and the clock", "%s / %s" % [told, served])
	# The state is broadcast every CLOCK_EVERY ticks, so what is told lags by up to that, and
	# the warm-up dusk moves fast: the tolerance is that lag, not an exact match.
	_check(float(told.get("daylight", -1.0)) > 0.3 and absf(float(told["daylight"]) - float(served["daylight"])) < 0.25,
		"and the daylight of the warm-up's day", "%.2f / %.2f" % [float(told.get("daylight", -1.0)), float(served["daylight"])])

	for _i in range(SERVER_TICK_RATE * 4):
		if int(_client_game.survival_state().get("stage", -1)) == GSNpcDirectorWaves.Stage.HORDE:
			break
		await _step()
	told = _client_game.survival_state()
	_check(int(told.get("stage", -1)) == GSNpcDirectorWaves.Stage.HORDE and int(told.get("index", 0)) == 1
		and float(told.get("daylight", -1.0)) >= 0.0 and float(told.get("daylight", 1.0)) < 0.02,
		"night 1 falls on the client, in the dark (daylight is sent in 255ths)", str(told))


## The barricade broken and mended on the server, as the client sees it.
func _check_hold_barricade() -> void:
	# The barricade: broken on the server, on the client's ground and in its picture.
	var entry: Dictionary = _client_game.map._barricades.get("alley_w", {})
	var drawn: Array = entry.get("drawn", [])
	var shapes: Array = entry.get("shapes", [])
	_server_game.bash_barricade("alley_w", 100000.0)
	await _steps(4)
	_check(not _client_game.map.barricade_intact("alley_w") and not bool(_client_game.barricades["alley_w"]["intact"]),
		"a barricade broken on the server is broken on the client")
	_check(not shapes.is_empty() and shapes.all(func(c: CollisionShape3D) -> bool: return c.disabled)
		and not drawn.is_empty() and drawn.all(func(m: MeshInstance3D) -> bool: return not m.visible),
		"its collision is off and its boards are gone from the picture", "%d shapes, %d meshes" % [shapes.size(), drawn.size()])

	# Nobody mends what is being torn at (ZzGame.MEND_LOCKOUT): refused straight after the blow,
	# taken once the lockout has passed.
	var refused_now := not _server_game.mend_barricade(0, null)
	await _steps(int(SERVER_TICK_RATE * (ZzGame.MEND_LOCKOUT + 0.2)))
	var _mended := _server_game.mend_barricade(0, null)
	await _steps(4)
	_check(refused_now and _mended, "a mend is refused while the boards are being torn at, and taken after")
	var fraction := float(_client_game.barricades["alley_w"]["health"]) / float(_client_game.barricades["alley_w"]["max"])
	_check(_client_game.map.barricade_intact("alley_w") and shapes.all(func(c: CollisionShape3D) -> bool: return not c.disabled)
		and drawn.all(func(m: MeshInstance3D) -> bool: return m.visible)
		and absf(fraction - float(_server_game.barricades["alley_w"]["health"]) / float(_server_game.barricades["alley_w"]["max"])) < 0.07,
		"mended, it stands again on the client, as strong as the server says", "%.2f" % fraction)


func _test_leaving() -> void:
	_section("leaving")
	_server_bridge.remove_peer(CLIENT_PEER)
	await _steps(8)
	_check(not _server_game.players.has(_me()), "the server lets them go")
	_check(_server_game.players.has(_stand_in.player_id), "and keeps the stand-in")
	_finished()


