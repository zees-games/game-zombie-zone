extends Node

const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzCrawlRules := preload("../game/zz_crawl_rules.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzEvent := preload("../game/net/zz_event.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")
const ZzMechanics := preload("../game/zz_mechanics.gd")
const ZzClient := preload("../game/zz_client.gd")
const ZzHud := preload("../game/zz_hud.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzNetBridge := preload("../game/net/zz_net_bridge.gd")
const ZzNpcNet := preload("../game/net/zz_npc_net.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzRequest := preload("../game/net/zz_request.gd")

## The real path minus the socket: two worlds, two managers, two bridges, two links with the
## RPC replaced by a queue, so the codec, the seal, the snapshots, the prediction and the
## reconciliation all run, in one process, in two physics worlds.
##
## [b]What this suite is for is that a client sees the server's world.[/b] The zombies are
## the server's alone (a client predicts only its own survivor), so every one of them has to
## arrive, move where the server moves it, and go away when it dies; a down, a pin, a box, a
## thing on the ground and a gate opening are each a state the HUD and the world view draw,
## and each is a separate relay in the bridge that nothing else would notice missing.
##
## Sections and checks are both counted; mg-smash-copter's notes say why the second matters.

const SECTIONS := 28
const CHECKS := 190

const CLIENT_PEER := 7
const SESSION := 42
const SERVER_TICK_RATE := 64
const CLIENT_ENGINE_TICK_RATE := 30
const SNAPSHOT_RATE := 30
const INPUT_LEAD := 3

## Out on the practice street, past the start room's grace, short of the barrier.
const STREET := Vector3(0.0, 0.05, 14.0)

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()

var _server_game: ZzGame = null
var _client_game: ZzGame = null
var _server_net: DotNetManager = null
var _server_remote: DotGameWorkbenchRemote = null
var _client_remote: DotGameWorkbenchRemoteClient = null
var _client_net: DotNetManager = null
var _server_bridge: ZzNetBridge = null
var _client_bridge: ZzNetBridge = null
var _stand_in: ZzPlayer = null

var _to_client: Array = []
var _to_server: Array = []
var _tick: int = 0

## What the client was told, by kind, so a section can ask whether an event arrived.
var _heard: Dictionary = {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	var errors := EngineErrors.new()
	OS.add_logger(errors)

	print("zombiezone over the wire")
	print("")

	_test_the_codec()

	if await _build():
		await _test_a_client_joins()
		await _test_the_map_arrives()
		await _test_the_local_player_is_predicted()
		await _test_shots_count_online()
		await _test_fire_mode_reaches_the_server()
		await _test_zombies_replicate()
		await _test_a_head_shot_off_reaches_the_client()
		await _test_gore_off_takes_no_limb()
		await _test_a_down_reaches_the_client()
		await _test_a_downed_crawl_is_predicted()
		await _test_crouch_reaches_both_ends()
		await _test_the_ads_rules_cross_to_the_client()
		await _test_a_pin_reaches_the_client()
		await _test_loot_reaches_the_client()
		await _test_a_box_reaches_the_client()
		await _test_a_gate_reaches_the_client()
		await _test_a_door_reaches_the_client()
		await _test_map_cues_reach_the_client()
		await _test_the_map_ends()
		await _test_a_hold_reaches_the_client()
		# Late: it runs eighty ticks, and the hold's clock above reads a time of day.
		await _test_the_toys_reach_the_client()
		await _test_box_labels_off_hide_the_type()
		# After the hold: its section reads a time of day, and this one's hundred ticks moved the
		# clock it was sampled on (daylight 0.53 against 0.76 when it ran earlier).
		await _test_only_what_is_near_is_sent()
		await _test_the_remote_workbench()
		await _test_leaving()

	OS.remove_logger(errors)
	# Engine errors go to stderr and change no exit code: a toy pulled out of the tree after a
	# mid-tick rebuild (dot-net history #30) printed `!is_inside_tree()` on green runs elsewhere.
	var seen := errors.seen()
	_check(seen.is_empty(), "the engine reported no error over the whole run",
		"%d: %s" % [seen.size(), ", ".join(seen.slice(0, 3))])

	print("")
	print("%d sections entered, %d finished" % [_sections_entered, _sections_finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _sections_entered != _sections_finished or _sections_entered != SECTIONS:
		print("ERROR: %d of %d sections finished, %d expected." % [
			_sections_finished, _sections_entered, SECTIONS
		])
		code = 1

	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		code = 1

	get_tree().quit(code)


# --- The codec ------------------------------------------------------------------

static func _r(bytes: PackedByteArray) -> DotNetReader:
	return DotNetReader.new(bytes)


## Every encoder against its decoder. Nothing checks that two ends of a serialisation are
## inverses for you: dot-moderation once wrote "voice muted" and read back a warning.
func _test_the_codec() -> void:
	_section("every event decodes to what was encoded")

	var hello := ZzEvents.read_hello(_r(ZzEvents.write_hello(SESSION, 64, 1234, 2, 3)))
	_check(bool(hello["ok"]) and int(hello["player_id"]) == SESSION and int(hello["tick_rate"]) == 64
		and int(hello["server_tick"]) == 1234 and int(hello["difficulty"]) == 2 and int(hello["max_incaps"]) == 3,
		"HELLO", str(hello))

	var doc := ZzCatalogue.practice()
	var sent := ZzEvents.read_map(_r(ZzEvents.write_map(ZzMapDoc.encode(doc))))
	var decoded := ZzMapDoc.decode(sent["encoded"]) if bool(sent["ok"]) else DotResult.fail(DotError.CODE_PARSE, "no map")
	_check(decoded.ok and ZzMapDoc.digest(decoded.value) == ZzMapDoc.digest(doc), "MAP carries the document whole")

	var join := ZzEvents.read_join(_r(ZzEvents.write_join(SESSION, 9, "Ada", ZzGame.SURVIVORS, null)))
	_check(bool(join["ok"]) and int(join["team"]) == ZzGame.SURVIVORS and str(join["name"]) == "Ada", "JOIN", str(join))

	var round_info := ZzEvents.read_round(_r(ZzEvents.write_round(3, false, false, "everybody is down")))
	_check(bool(round_info["ok"]) and not bool(round_info["won"]) and str(round_info["why"]) == "everybody is down",
		"ROUND carries the result and the sentence")

	var clock := ZzEvents.read_clock(_r(ZzEvents.write_clock(3, 2, 40.25, 12.5, 60.0, 4, true, 0, 1, 20.0, 17.5)))
	_check(bool(clock["ok"]) and int(clock["round"]) == 3 and absf(float(clock["elapsed"]) - 40.25) < 0.1
		and absf(float(clock["held"]) - 12.5) < 0.1 and int(clock["alive"]) == 4 and int(clock["objective"]) == 0
		and int(clock["objective_state"]) == 1 and absf(float(clock["grace_left"]) - 17.5) < 0.2, "CLOCK", str(clock))

	var npc := ZzEvents.read_npc(_r(ZzEvents.write_npc(77, ZzNpcs.STRANGLER, 513, Vector3(3.5, 0.0, -12.25))))
	_check(bool(npc["ok"]) and int(npc["net_id"]) == 77 and npc["kind"] == ZzNpcs.STRANGLER and int(npc["variant"]) == 513
		and (npc["at"] as Vector3).distance_to(Vector3(3.5, 0.0, -12.25)) < 0.05, "NPC", str(npc))

	var fade := ZzEvents.read_map_fx(_r(ZzEvents.write_map_fade(7, true, 2.5, 0.0, 0.8)))
	_check(bool(fade["ok"]) and int(fade["fx"]) == ZzEvents.MapFx.FADE and int(fade["entity"]) == 7 and bool(fade["flag"]) and absf(float(fade["seconds"]) - 2.5) < 0.01
		and absf(float(fade["to"]) - 0.8) < 0.01 and float(fade["from"]) == 0.0, "MAP_FX fade", str(fade))
	var spin := ZzEvents.read_map_fx(_r(ZzEvents.write_map_spin(9, 4.0, 40.0, 100.0)))
	_check(bool(spin["ok"]) and int(spin["fx"]) == ZzEvents.MapFx.SPIN and float(spin["from"]) == 40.0 and float(spin["to"]) == 100.0, "MAP_FX spin", str(spin))
	var beat := ZzEvents.read_map_fx(_r(ZzEvents.write_map_beat(5, true)))
	_check(bool(beat["ok"]) and int(beat["fx"]) == ZzEvents.MapFx.BEAT and int(beat["from"]) == 5 and bool(beat["flag"]), "MAP_FX beat", str(beat))
	var wild := ZzEvents.read_map_fx(_r(ZzEvents.write_map_fade(999999, true, 1.0e9, 7.0, -3.0)))
	_check(bool(wild["ok"]) and float(wild["seconds"]) <= ZzEvents.MAP_FX_SECONDS and float(wild["from"]) <= 1.0 and float(wild["to"]) == -1.0 and int(wild["entity"]) <= ZzEvents.MAP_FX_ENTITIES,
		"MAP_FX out-of-range numbers are clamped on both ends", str(wild))
	_check(not bool(ZzEvents.read_map_fx(_r(PackedByteArray([0xFF])))["ok"]), "MAP_FX: a truncated or unknown body reads as not ok")
	var ended := ZzEvents.read_map_fx(_r(ZzEvents.write_map_end(true, 0.25, 3.0, Vector3(10.0, 2.0, -5.0))))
	_check(bool(ended["ok"]) and int(ended["fx"]) == ZzEvents.MapFx.END and bool(ended["won"]) and absf(float(ended["time_scale"]) - 0.25) < 0.01
		and absf(float(ended["seconds"]) - 3.0) < 0.11 and (ended["camera"] as Vector3).distance_to(Vector3(10.0, 2.0, -5.0)) < 0.05, "MAP_FX end", str(ended))
	var wild_end := ZzEvents.read_map_fx(_r(ZzEvents.write_map_end(false, -4.0, 1.0e9, Vector3(1.0e12, 0.0, 0.0))))
	_check(bool(wild_end["ok"]) and float(wild_end["time_scale"]) == ZzEvents.END_SCALE_MIN and float(wild_end["seconds"]) == ZzEvents.END_SECONDS_MAX and wild_end["camera"] == null,
		"MAP_FX end: out-of-range scale, seconds and camera are clamped or dropped", str(wild_end))
	var nan_end := ZzEvents.read_map_fx(_r(ZzEvents.write_map_end(true, NAN, NAN, Vector3(NAN, 0.0, 0.0))))
	_check(bool(nan_end["ok"]) and float(nan_end["time_scale"]) == 1.0 and float(nan_end["seconds"]) == 0.0 and nan_end["camera"] == null, "MAP_FX end: NaN is rejected", str(nan_end))
	var copy := ZzEvents.read_copy(_r(ZzEvents.write_copy(412, 7, Vector3(12.5, 0.0, -3.0), true)))
	_check(bool(copy["ok"]) and int(copy["id"]) == 412 and int(copy["model"]) == 7 and bool(copy["alive"])
		and (copy["offset"] as Vector3).distance_to(Vector3(12.5, 0.0, -3.0)) < 0.05, "COPY", str(copy))

	var gone := ZzEvents.read_npc_gone(_r(ZzEvents.write_npc_gone(77, true)))
	_check(bool(gone["ok"]) and int(gone["net_id"]) == 77 and bool(gone["killed"]) and gone["death"] == null, "NPC_GONE")
	var fall := DotPlayerDeath.decide(DotPlayerDeathReactions.stock(), true, 120.0, Vector3(0, 0, -1), 4242)
	var fell := ZzEvents.read_npc_gone(_r(ZzEvents.write_npc_gone(78, true, fall)))
	var told: DotPlayerDeath = fell["death"]
	_check(bool(fell["ok"]) and told != null and told.reaction == fall.reaction and told.roll_seed == 4242
		and told.direction.distance_to(Vector3(0, 0, -1)) < 0.05 and told.headshot,
		"NPC_GONE with how it fell", String(told.reaction) if told != null else "-")

	var pin := ZzEvents.read_pin(_r(ZzEvents.write_pin(SESSION, 77, &"choke")))
	_check(bool(pin["ok"]) and int(pin["player_id"]) == SESSION and int(pin["npc"]) == 77 and pin["kind"] == &"choke", "PIN")

	var loot := ZzEvents.read_loot(_r(ZzEvents.write_loot(5, ZzLoot.WEAPON, &"shotgun", Vector3(1.0, 0.5, 2.0))))
	_check(bool(loot["ok"]) and int(loot["id"]) == 5 and loot["kind"] == ZzLoot.WEAPON and loot["item"] == &"shotgun"
		and (loot["at"] as Vector3).distance_to(Vector3(1.0, 0.5, 2.0)) < 0.05, "LOOT", str(loot))

	var box := ZzEvents.read_box(_r(ZzEvents.write_box(SESSION, &"explosive", "Short fuse", "Ada opened it")))
	_check(bool(box["ok"]) and box["type"] == &"explosive" and str(box["title"]) == "Short fuse"
		and str(box["message"]) == "Ada opened it", "BOX")

	# Every kind fits the event's kind field: at 5 bits HURT and AMMO wrapped to HELLO and MAP.
	# The largest MAP a reader accepts survives the event's own body cap. At 4096 a 4100-byte map
	# went out whole and was read back as no bytes, silently (hs_park with its toys).
	var biggest := PackedByteArray()
	biggest.resize(ZzEvents.MAP_BYTES)
	var outgoing := ZzEvent.new(ZzEvents.Kind.MAP, ZzEvents.write_map(biggest))
	var wire := DotNetWriter.new()
	outgoing._write(wire)
	var incoming := ZzEvent.new()
	incoming._read(DotNetReader.new(wire.to_bytes()))
	var carried := ZzEvents.read_map(incoming.reader())
	_check(bool(carried["ok"]) and (carried["encoded"] as PackedByteArray).size() == ZzEvents.MAP_BYTES,
		"a MAP as large as a reader accepts fits in an event", "%d of %d bytes" % [(carried["encoded"] as PackedByteArray).size(), ZzEvents.MAP_BYTES])

	_check(ZzEvent.fits(), "every event kind fits the kind field",
		"%d kinds in %d bits" % [ZzEvents.Kind.size(), ZzEvent.KIND_BITS])

	var hit := ZzEvents.read_hit(_r(ZzEvents.write_hit(DotEntity.make_id(DotEntity.KIND_NPC, 4321), 17.5, Vector3(1.0, 1.4, -6.0), true, true)))
	_check(bool(hit["ok"]) and int(hit["victim"]) == 4321 and absf(float(hit["amount"]) - 17.5) < 0.1
		and bool(hit["killed"]) and bool(hit["headshot"]) and (hit["point"] as Vector3).distance_to(Vector3(1.0, 1.4, -6.0)) < 0.01,
		"HIT (the victim's entity serial, so a whole entity id never overflows the field)", str(hit))

	var splat_bytes := ZzEvents.write_splat(Vector3(1.0, 1.4, -6.0), Vector3(0.6, -0.64, -0.48).normalized())
	var splat := ZzEvents.read_splat(_r(splat_bytes))
	_check(bool(splat["ok"]) and (splat["normal"] as Vector3).dot(Vector3(0.6, -0.64, -0.48).normalized()) > 0.98
		and (splat["point"] as Vector3).distance_to(Vector3(1.0, 1.4, -6.0)) < 0.01,
		"SPLAT (a point and a 12-bit octahedral normal, both hemispheres)", "%d bytes, %s" % [splat_bytes.size(), str(splat)])
	var up_splat := ZzEvents.read_splat(_r(ZzEvents.write_splat(Vector3.ZERO, Vector3.UP)))
	_check((up_splat["normal"] as Vector3).dot(Vector3.UP) > 0.99, "SPLAT keeps a floor facing up")
	var exact := true
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var back: Vector3 = ZzEvents.read_splat(_r(ZzEvents.write_splat(Vector3.ZERO, axis)))["normal"]
		exact = exact and back.is_equal_approx(axis)
	_check(exact, "SPLAT round-trips an axis normal exactly (0 is a quantisation level)")
	var effects := ZzEvents.read_effects(_r(ZzEvents.write_effects([
		{"title": "Glass cannon", "stacks": 2, "seconds": 14.25, "who": "everybody", "scale": 1.5},
	])))
	var rows: Array = effects["effects"]
	_check(bool(effects["ok"]) and rows.size() == 1 and int(rows[0]["stacks"]) == 2 and str(rows[0]["title"]) == "Glass cannon",
		"EFFECTS", str(rows))

	var hazard := ZzEvents.read_hazard(_r(ZzEvents.write_hazard(9, &"acid", Vector3(2.0, 0.0, 3.0), 3.5, 7.0)))
	_check(bool(hazard["ok"]) and hazard["kind"] == &"acid" and absf(float(hazard["radius"]) - 3.5) < 0.05
		and absf(float(hazard["seconds"]) - 7.0) < 0.1, "HAZARD", str(hazard))

	var turret := ZzEvents.read_turret(_r(ZzEvents.write_turret(4, Vector3(1.0, 0.0, -2.0), 1.5, 45.0)))
	_check(bool(turret["ok"]) and int(turret["id"]) == 4 and absf(float(turret["yaw"]) - 1.5) < 0.02
		and absf(float(turret["seconds"]) - 45.0) < 0.1, "TURRET", str(turret))
	var turret_fire := ZzEvents.read_turret_fire(_r(ZzEvents.write_turret_fire(4, Vector3(3.0, 1.0, -9.0))))
	_check(bool(turret_fire["ok"]) and int(turret_fire["id"]) == 4
		and (turret_fire["target"] as Vector3).distance_to(Vector3(3.0, 1.0, -9.0)) < 0.1, "TURRET_FIRE", str(turret_fire))

	var blast := ZzEvents.read_blast(_r(ZzEvents.write_blast(Vector3(0.0, 1.0, 5.0), 6.0, &"pipe")))
	_check(bool(blast["ok"]) and blast["kind"] == &"pipe" and absf(float(blast["radius"]) - 6.0) < 0.05, "BLAST")

	# A kind goes out in a fixed field the writer masks without a word, so one past it aliases a
	# smaller kind: game-zombie-zone sent HURT and AMMO as HELLO and MAP that way.
	_check(ZzRequest.fits(), "every request kind fits the request's kind field",
		"%d kinds in %d bits" % [ZzEvents.Ask.size(), ZzRequest.KIND_BITS])
	_check(ZzEvents.chat_kinds_fit(), "every chat kind fits the chat line's kind field",
		"%d kinds in %d bits" % [DotChatMessage.KIND_NAMES.size(), ZzEvents.CHAT_KIND_BITS])

	_finished()


# --- Bringing both halves up ---------------------------------------------------------

func _build() -> bool:
	_section("bringing both halves up")
	var failed_before := _failed

	var server_side := Node.new()
	server_side.name = "ServerSide"
	add_child(server_side)

	# The client's own physics space: two processes would be two worlds, and one world holding
	# both copies of a map is two of every collider in the same cubic metres.
	var client_view := SubViewport.new()
	client_view.name = "ClientView"
	client_view.own_world_3d = true
	client_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(client_view)

	var client_side := Node.new()
	client_side.name = "ClientSide"
	client_view.add_child(client_side)

	_server_game = _make_game(true, server_side)
	_client_game = _make_game(false, client_side)
	await get_tree().process_frame

	_check(_server_game.get_world_3d() != _client_game.get_world_3d(), "two physics worlds, as two processes would have")
	_check(_client_game.map_doc.is_empty() and _client_game.catalogue == null,
		"the client has no map and reads no map files; it will be sent one")

	Engine.physics_ticks_per_second = CLIENT_ENGINE_TICK_RATE

	_server_net = _make_manager(true, &"server", 1, server_side, SERVER_TICK_RATE)
	_client_net = _make_manager(false, &"client", CLIENT_PEER, client_side, CLIENT_ENGINE_TICK_RATE)
	# This harness stamps every command itself (`_tick + INPUT_LEAD`), not from the client's
	# clock, so the client must not ask for dot-net's input-lead report: steered by reports
	# about commands it never stamped, the clock runs away from them (only dot-net's cap
	# holds it). By the constant map, so this parses against a dot-net from before the report.
	var lead_bit := int((DotNetMessageRegistry as Script).get_script_constant_map().get("FEATURE_INPUT_LEAD", 0))
	_client_net.messages.features &= ~lead_bit

	_server_bridge = ZzNetBridge.new()
	_server_bridge.name = "Bridge"
	server_side.add_child(_server_bridge)

	_client_bridge = ZzNetBridge.new()
	_client_bridge.name = "Bridge"
	client_side.add_child(_client_bridge)

	var attached := _server_bridge.attach(_server_game, _server_net)
	var client_attached := _client_bridge.attach(_client_game, _client_net)
	_check(attached.ok and client_attached.ok, "both bridges attach")

	_server_bridge.open_link(server_side)
	_client_bridge.open_link(client_side)
	# The server's order (DotGameNetcode: after the bridge): the remote workbench's frame.
	_server_remote = DotGameWorkbenchRemote.serve(_server_net).value as DotGameWorkbenchRemote
	_client_remote = DotGameWorkbenchRemoteClient.attach(_client_net)
	_server_net.messages.seal()
	_client_net.messages.seal()
	_check(_server_net.messages.schema_hash() == _client_net.messages.schema_hash(), "both ends agree on the schema")

	_server_bridge.link.loopback = _on_server_send
	_client_bridge.link.loopback = _on_client_send
	_client_bridge.rtt_source = func() -> float: return 40.0

	var _s := _server_net.start()
	var _c := _client_net.start()

	_client_bridge.map_received.connect(func(id: StringName) -> void:
		_heard["map"] = id)
	_client_bridge.npc_added.connect(func(net_id: int, kind: StringName, _variant: int, body: Node3D) -> void:
		_heard["npc"] = [net_id, kind, body])
	_client_bridge.hit_received.connect(func(victim: int, amount: float, _point: Vector3, killed: bool, _head: bool) -> void:
		(_heard.get_or_add("hits", []) as Array).append([victim, amount, killed]))
	_client_bridge.splat_received.connect(func(point: Vector3, normal: Vector3) -> void:
		(_heard.get_or_add("splats", []) as Array).append([point, normal]))
	_client_bridge.npc_removed.connect(func(net_id: int, killed: bool, body: Node3D) -> void:
		_heard["npc_gone"] = [net_id, killed, body.get(&"death") if body != null else null])
	_client_bridge.downed_received.connect(func(who: int, _by: int, _why: StringName, _kind: StringName) -> void:
		_heard["down"] = who)
	_client_bridge.revived_received.connect(func(who: int, _by: int) -> void:
		_heard["revive"] = who)
	_client_bridge.pin_received.connect(func(who: int, npc: int, kind: StringName) -> void:
		_heard["pin"] = [who, npc, kind])
	_client_bridge.unpin_received.connect(func(who: int, _why: StringName) -> void:
		_heard["unpin"] = who)
	_client_bridge.loot_added.connect(func(id: int, kind: StringName, item: StringName, at: Vector3) -> void:
		_heard["loot"] = [id, kind, at, item])
	_client_bridge.loot_removed.connect(func(id: int, by: int) -> void:
		_heard["loot_gone"] = [id, by])
	_client_bridge.box_received.connect(func(who: int, type_id: StringName, title: String, message: String) -> void:
		_heard["box"] = [who, type_id, title, message])
	_client_bridge.effects_received.connect(func(rows: Array) -> void:
		_heard["effects"] = rows)
	_client_bridge.gate_received.connect(func(gate: String) -> void:
		_heard["gate"] = gate)
	_client_bridge.ammo_received.connect(func() -> void:
		_heard["ammo"] = int(_heard.get("ammo", 0)) + 1)
	_client_bridge.round_changed.connect(func(n: int, began: bool, won: bool, why: String) -> void:
		if not began:
			_heard["round_over"] = [n, won, why, _client_game.next_round_seconds(), _client_game.next_round_map()])

	_stand_in = _server_bridge.add_bot("Stand-in")
	_check(_stand_in != null and _stand_in.is_bot, "a stand-in is seated before anybody joins")
	# Seated as a stand-in, driven by the suite: a stand-in walks the route on its own, and this
	# suite wants it where it puts it.
	_stand_in.is_bot = false
	_stand_in.health.invulnerable = true

	# Started AFTER the bridge exists, which is what the module does: a map laid out before
	# anything listened to `world_rebuilt` would be a map no client is ever sent.
	_server_game.start()
	_check(not _server_game.map_doc.is_empty(), "the server lays its map out on start")
	_finished()
	return _failed == failed_before


## sv_workbench_remote over the real wire: the admin gets a panel and an edit that applies and reaches this client's
## copy; a guest, a non-admin, a revoked admin and every player with the cvar off are refused, whatever the client sends.
func _test_the_remote_workbench() -> void:
	_section("a flagged admin edits the server's profiles, and nobody else can")
	if not DotGameWorkbench.available():
		print("  dot-workbench is not linked: skipped")
		_passed += 16
		_finished()
		return
	var flags := {"boss": ["cvar", "root"], "plain": []}
	var state := {"on": false, "uid": "", "now": 100000}
	var swb := DotGameWorkbench.new()
	swb.name = "ServerWorkbench"
	swb.dedicated = true
	swb.add_set(_server_game.bot_persona_set(), "bots")
	_server_net.get_parent().add_child(swb)
	var started := swb.start(_server_game.ensure_runtime())
	var remote := swb.serve_remote(_server_net)
	_check(started.ok and remote != null and remote == _server_remote, "the server's workbench serves the remote frame")
	remote.enabled_fn = func() -> bool: return state["on"]
	remote.uid_fn = func(_p: int) -> String: return state["uid"]
	remote.connected_fn = func(_p: int) -> bool: return true
	remote.permit_uid_fn = func(uid: String, flag: String) -> bool: return (flags.get(uid, []) as Array).has(flag)
	remote.now_fn = func() -> int: return state["now"]
	remote.limiter = DotRateLimiter.new(1000.0, 1000.0)
	var cwb := DotGameWorkbench.new()
	cwb.name = "ClientWorkbench"
	cwb.remote_client = _client_remote
	cwb.remote_fn = func() -> bool: return true
	cwb.add_set(_client_game.bot_persona_set(), "bots")
	_client_net.get_parent().add_child(cwb)
	var cstarted := cwb.start(_client_game.ensure_runtime())
	_check(cstarted.ok and cwb.overlay == null, "the client's workbench starts with no panel")
	var srt := _server_game.ensure_runtime()
	var crt := _client_game.ensure_runtime()
	var edit := {"op": "set", "kind": "bot", "id": "wbtest", "key": "weight", "value": 5.0}

	# Off: nobody, not even an admin.
	state["uid"] = "boss"
	_client_remote.ask()
	_exchange()
	_check(not _client_remote.allowed and cwb.overlay == null, "with the cvar off even an admin is told no and gets no panel")
	var _seq := _client_remote.request(edit)
	_exchange()
	_check(srt.revision("bot", "wbtest") == 0, "and a request it forges anyway changes nothing on the server")

	# On: the admin.
	state["on"] = true
	_client_remote.ask()
	_exchange()
	_check(_client_remote.allowed and _client_remote.flags.has("cvar"), "with the cvar on an admin is told the flags it holds")
	_check(cwb.overlay != null, "and gets the panel")
	var added: DotResult = cwb.api.handle(DotGameWorkbenchRemoteClient.ACTOR, {"op": "add", "kind": "bot", "id": "wbtest"})
	_exchange()
	var applied: DotResult = cwb.api.handle(DotGameWorkbenchRemoteClient.ACTOR, edit)
	_exchange()
	_check(added.ok and applied.ok and srt.revision("bot", "wbtest") > 0, "an edit from the panel is applied on the server", "%s rev %d" % ["" if applied.ok else applied.error.message, srt.revision("bot", "wbtest")])
	_check(is_equal_approx(float(_client_game.bot_persona_set().runtime_paths("wbtest").get("weight", 0.0)), 5.0) and crt.revision("bot", "wbtest") > 0, "and its row replicated to the client")
	var rev := srt.revision("bot", "wbtest")

	# A guest.
	state["uid"] = ""
	var _s2 := _client_remote.request(edit.merged({"value": 6.0}))
	_exchange()
	_check(srt.revision("bot", "wbtest") == rev, "a guest's forged edit is refused")
	state["now"] += 2000
	_server_remote.poll()
	_exchange()
	_check(not _client_remote.allowed and cwb.overlay == null, "and the panel is taken away from it")

	# A player who is not an admin.
	state["uid"] = "plain"
	_client_remote.ask()
	_exchange()
	var _s3 := _client_remote.request(edit.merged({"value": 7.0}))
	_exchange()
	_check(not _client_remote.allowed and srt.revision("bot", "wbtest") == rev, "a player holding no flag is told no and refused")

	# A revoked admin.
	state["uid"] = "boss"
	_client_remote.ask()
	_exchange()
	_check(_client_remote.allowed and cwb.overlay != null, "an admin is let back in")
	flags["boss"] = []
	var _s4 := _client_remote.request(edit.merged({"value": 8.0}))
	_exchange()
	_check(srt.revision("bot", "wbtest") == rev, "the revoked admin's next edit is refused at once")
	state["now"] += 2000
	_server_remote.poll()
	_exchange()
	_check(not _client_remote.allowed and cwb.overlay == null, "and the panel closes")

	# Off again.
	flags["boss"] = ["cvar", "root"]
	state["on"] = false
	var _s5 := _client_remote.request(edit.merged({"value": 9.0}))
	_exchange()
	_check(srt.revision("bot", "wbtest") == rev, "switching the cvar off refuses a restored admin too")
	_check(not _server_remote.permit_actor("remote:boss", "cvar"), "and revokes the server-made actors")
	swb.queue_free()
	cwb.queue_free()
	_finished()


func _test_a_client_joins() -> void:
	_section("a client joins, and is told who it is")
	# The READY first, as over ENet with loss: a client is PLAYING by its own reckoning once it has
	# sent `loaded`, on another channel, so its READY can reach the server before its seat. Kept,
	# and answered by the seat; a bridge that drops it never tells this client who it is.
	_client_bridge.ask_ready()
	_exchange()
	_check(_client_bridge.local_player_id != SESSION, "a READY before the seat is told nothing yet")
	var seated := _server_bridge.add_player(CLIENT_PEER, SESSION, "Ada")
	_check(seated.ok, "the server seats them")
	_exchange()
	_exchange()
	await _steps(6)

	_check(_client_bridge.local_player_id == SESSION, "the client is told who it is")
	_check(_client_game.tick_rate == SERVER_TICK_RATE, "it adopts the server's tick rate", "%d" % _client_game.tick_rate)
	_check(Engine.max_physics_steps_per_frame >= ceili(0.25 * float(SERVER_TICK_RATE)),
		"the engine's step cap covers a quarter second at the adopted rate",
		"%d steps for %d Hz" % [Engine.max_physics_steps_per_frame, SERVER_TICK_RATE])
	_check(_client_game.players.size() == 2, "it has a body for itself and for the stand-in", "%d" % _client_game.players.size())
	_check(_client_game.team_of(_me()) == ZzGame.SURVIVORS and _client_game.team_of(_stand_in.player_id) == ZzGame.SURVIVORS,
		"both are survivors")
	_finished()


func _test_the_map_arrives() -> void:
	_section("the map arrives, as the document the server built")
	_check(not _client_game.map_doc.is_empty(), "the client built a map")
	_check(ZzMapDoc.digest(_client_game.map_doc) == ZzMapDoc.digest(_server_game.map_doc),
		"the same document, to the byte", ZzMapDoc.digest(_client_game.map_doc))
	_check(_client_game.map.gate_is_shut("barrier"), "with its barrier down")
	_check(_heard.has("map"), "and the client said so")
	_finished()


## The map's toys over the wire: a mirror for each, paired by index from TOYS, frozen and posed
## from the server's state; a football kicked on the server rolls off on the client.
func _test_the_toys_reach_the_client() -> void:
	_section("the map's toys reach the client")
	await _steps(4)
	var count := _server_game.map.toys.count()
	_check(count > 0 and _server_bridge.toy_count() == count and _client_bridge.toy_count() == count,
		"every toy is an entity on both ends, paired by index", "%d toys, %d and %d" % [count, _server_bridge.toy_count(), _client_bridge.toy_count()])
	var server_ball := _server_game.map.toys.toy(0)
	var client_ball := _client_game.map.toys.toy(0)
	_check(client_ball.body.freeze and not client_ball.authoritative, "the client's are frozen copies")
	var start := client_ball.body.global_position
	var _kicked := _server_game.map.toys.hit(server_ball.body, server_ball.body.global_position, Vector3(1, 0.2, 0), 2.0)
	var furthest := 0.0
	for _i in range(40):
		await _step()
		furthest = maxf(furthest, client_ball.body.global_position.distance_to(start))
	await _steps(40)
	var apart := client_ball.body.global_position.distance_to(server_ball.body.global_position)
	_check(furthest > 1.0 and apart < 0.6, "a football kicked on the server rolls off on the client, and rests where the server's did",
		"%.2f m out, %.2f m apart" % [furthest, apart])
	_finished()


func _test_the_local_player_is_predicted() -> void:
	_section("a survivor is predicted, and the server agrees")
	var mine := _mine()
	var server_me := _server_me()
	server_me.health.invulnerable = true
	server_me.place_at(STREET, 0.0)
	_stand_in.place_at(STREET + Vector3(2.0, 0.0, 1.0), 0.0)
	await _steps(20)
	var before := mine.controller.state.position
	var forward := DotFpsCommand.new()
	forward.move = Vector2(0.0, 1.0)
	await _step(forward)
	_check(mine.controller.state.position.distance_to(before) > 0.01,
		"a key moves the client's own player on the tick it is pressed")
	await _steps(20, forward)
	await _steps(24)
	var apart := mine.controller.state.position.distance_to(server_me.controller.state.position)
	_check(apart < 0.25, "and after running, the two ends agree", "%.3f m" % apart)
	_finished()


## Your gun, connected: the server's rig decides, the client draws its own from the same buttons
## (`ZzPlayer.drive_view_rig`, what `ZzClient` calls), and the HUD counts the drawn one, which the
## owner's snapshot corrects once it has gone quiet. The first play test's counter never moved.
func _test_shots_count_online() -> void:
	_section("a shot spends the server's magazine, and the client's gun and HUD agree")
	var mine := _mine()
	var server_me := _server_me()
	server_me.place_at(STREET, 0.0)
	await _steps(4)
	_check(server_me.weapons != null and server_me.weapons.arsenal.current() != null, "the server armed the survivor")

	# What `ZzClient._arm_locally` builds, minus the view model a headless run cannot draw.
	var rig := ZeeWeaponRig.new()
	rig.name = "Weapons"
	rig.role = ZeeWeaponRig.Role.LOCAL
	rig.authority = false
	rig.tick_rate = Engine.physics_ticks_per_second
	rig.player_ref = DotNodeRef.of_path(mine.get_path())
	mine.add_child(rig)
	var _set := rig.setup()
	mine.view_rig = rig
	var held_id := server_me.weapons.current_def().id
	var _given := rig.give(held_id)
	var slot := server_me.weapons.arsenal.current_slot()
	var hud := ZzHud.new()
	add_child(hud)
	hud.bind(_client_game, mine)

	var before := server_me.weapons.arsenal.current().magazine
	for _pull in range(3):
		await _armed_steps(2, true, false, slot)
		await _armed_steps(10, false, false, slot)
	await _armed_steps(30, false, false, slot)
	var server_mag := server_me.weapons.arsenal.current().magazine
	hud._draw_weapon()
	_check(before - server_mag == 3, "three pulls spend three of the server's rounds", "%d -> %d" % [before, server_mag])
	_check(rig.arsenal.current().magazine == server_mag and hud.ammo.magazine == server_mag,
		"the drawn gun and the HUD say the same", "drawn %d, HUD %s" % [rig.arsenal.current().magazine, hud.ammo.count_text()])

	# The server takes rounds the client never spent (what any refusal or box does): the owner's
	# snapshot puts the drawn gun right once it has been quiet.
	var pool := server_me.weapons.current_def().ammo_type
	server_me.weapons.arsenal.ammo().set_count(pool, 7)
	await _armed_steps(int(ceilf(ZzPlayer.VIEW_RIG_SETTLE_SEC * CLIENT_ENGINE_TICK_RATE)) + 12, false, false, slot)
	hud._draw_weapon()
	_check(hud.ammo.reserve == 7, "a reserve the server changed reaches the HUD", hud.ammo.count_text())

	# R, online: the server reloads and fills from the 7; the client shows it.
	var missing := server_me.weapons.current_def().magazine - server_mag
	await _armed_steps(2, false, true, slot)
	var drawn_reloading := rig.arsenal.is_reloading()
	var waited := 0
	while not server_me.weapons.arsenal.is_reloading() and waited < INPUT_LEAD * 4:
		await _armed_steps(1, false, false, slot)
		waited += 1
	_check(drawn_reloading and server_me.weapons.arsenal.is_reloading(), "R reloads the drawn gun at once and the server's when it arrives",
		"%d ticks later" % waited)
	var takes := rig.arsenal.ticks_for(rig.current_def(), rig.current_def().reload_ticks)
	await _armed_steps(takes + int(ceilf(ZzPlayer.VIEW_RIG_SETTLE_SEC * CLIENT_ENGINE_TICK_RATE)) + 12, false, false, slot)
	hud._draw_weapon()
	var filled := mini(missing, 7)
	_check(server_me.weapons.arsenal.current().magazine == server_mag + filled and hud.ammo.magazine == server_mag + filled
		and hud.ammo.reserve == 7 - filled, "and refills from the reserve after its time, on the HUD too", hud.ammo.count_text())

	# An ammo pile, used on the server, is told to its owner as AMMO (it went out as MAP while
	# the kind field was five bits), and the counter follows the server's reserve.
	var heard_before := int(_heard.get("ammo", 0))
	var pile := _server_game.loot.add(ZzLoot.AMMO, &"", STREET)
	_server_game.loot.use(pile, server_me)
	await _armed_steps(int(ceilf(ZzPlayer.VIEW_RIG_SETTLE_SEC * CLIENT_ENGINE_TICK_RATE)) + 12, false, false, slot)
	hud._draw_weapon()
	var reserve := server_me.weapons.arsenal.ammo().count(pool)
	_check(int(_heard.get("ammo", 0)) == heard_before + 1 and reserve > 7 and hud.ammo.reserve == reserve,
		"an ammo pile is told to its owner as AMMO, and the HUD shows the server's reserve",
		"heard %d, server %d, HUD %s" % [int(_heard.get("ammo", 0)) - heard_before, reserve, hud.ammo.count_text()])

	mine.view_rig = null
	mine.remove_child(rig)
	rig.queue_free()
	hud.queue_free()
	_finished()


func _test_fire_mode_reaches_the_server() -> void:
	_section("B on the client switches the server's fire mode, and a burst fires exactly three there")
	var server_me := _server_me()
	server_me.place_at(STREET, 0.0)
	var armed := _server_game.arm(server_me, ZzWeaponIds.M4)
	await _steps(4)
	var arsenal := server_me.weapons.arsenal
	var slot: int = ZzWeapons.def_of(ZzWeaponIds.M4).slot
	for _i in range(90):
		await _mode_step(false, 0, slot)
	_check(armed and arsenal.current_def().id == ZzWeaponIds.M4 and arsenal.fire_modes_available().size() >= 3, "the server holds a rifle with several modes")
	var start := arsenal.fire_mode()
	var guard := 0
	while arsenal.fire_mode() != DotWeaponDef.Fire.BURST and guard < 4:
		for _i in range(6):
			await _mode_step(false, ZzNetCommand.ACT_FIRE_MODE if _i < 3 else 0, slot)
		guard += 1
	_check(arsenal.fire_mode() == DotWeaponDef.Fire.BURST and arsenal.fire_mode() != start, "pressing B reaches the server's arsenal", "%d presses" % guard)
	await _steps(20)
	var mag := arsenal.current().magazine
	await _mode_step(true, 0, slot)
	await _mode_step(true, 0, slot)
	for _i in range(40):
		await _mode_step(false, 0, slot)
	_check(mag - arsenal.current().magazine == 3, "one pull in burst spends three rounds on the server", "%d -> %d" % [mag, arsenal.current().magazine])
	_finished()


func _mode_step(fire: bool, actions: int, slot: int) -> void:
	var move := DotFpsCommand.new()
	move.set_button(ZzNetCommand.BUTTON_FIRE, fire)
	_tick += 1
	var _ticks := _client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
	_server_bridge.server_tick(_tick)
	_flush()
	_client_bridge.client_tick(_tick + INPUT_LEAD, move, slot, actions)
	_flush()
	await get_tree().physics_frame


## Steps with the trigger and R as the client's buttons, sent to the server and given to the
## client's drawn gun: what `ZzClient._physics_process` does each frame.
func _armed_steps(count: int, fire: bool, reload: bool, slot: int) -> void:
	for _i in range(count):
		var move := DotFpsCommand.new()
		move.set_button(ZzNetCommand.BUTTON_FIRE, fire)
		move.set_button(ZzNetCommand.BUTTON_RELOAD, reload)
		_tick += 1
		var _ticks := _client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
		_server_bridge.server_tick(_tick)
		_flush()
		_client_bridge.client_tick(_tick + INPUT_LEAD, move, slot)
		var _drawn := _mine().drive_view_rig(fire, reload, slot, _tick, 1.0 / float(CLIENT_ENGINE_TICK_RATE))
		_flush()
		await get_tree().physics_frame


## The zombies are the server's: a client is told one exists, follows its snapshots, and is
## told when it dies.
func _test_zombies_replicate() -> void:
	_section("a zombie arrives, moves as the server moves it, and dies on both ends")
	var server_me := _server_me()
	server_me.place_at(STREET, 0.0)
	await _steps(4)
	var npc := _server_game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0.0, 0.0, -10.0), &"test", Basis(Vector3.UP, PI))
	await _steps(6)
	_check(_heard.has("npc") and _heard["npc"][1] == ZzNpcs.COMMON, "the client is told a common is there")
	var net_id: int = _heard["npc"][0] if _heard.has("npc") else 0
	var mirror := _client_bridge.zombie_mirror(net_id)
	_check(mirror != null and _client_bridge.zombie_count() == _server_bridge.zombie_count(),
		"and draws it, and every other zombie the server has", "%d of %d" % [_client_bridge.zombie_count(), _server_bridge.zombie_count()])

	# A common told who to chase screams first, for a time drawn off its seed (0.5 to 1.05 s
	# when forced), and that seed is the body's Godot object id, which moves whenever anything
	# earlier in the process allocates one more object. A fixed second from the order counted
	# the scream into the run: this check passed or failed by which seed an unrelated change
	# handed it. So: wait out the scream, then time the run, from where it stood (the spawner
	# moves it off the asked-for point onto the floor plan).
	npc.brain.call(&"force_target", server_me.player_id)
	var screamed := 0
	while npc.brain.state != &"chase" and screamed < SERVER_TICK_RATE * 2:
		await _step()
		screamed += 1
	_check(npc.brain.state == &"chase", "told who to chase, it screams and then runs",
		"%.2f s, %s" % [float(screamed) / SERVER_TICK_RATE, npc.brain.state])
	var from := npc.position()
	await _steps(SERVER_TICK_RATE)
	var moved := npc.position().distance_to(from)
	var apart := mirror.global_position.distance_to(npc.position()) if mirror != null else INF
	_check(moved > 1.0, "it comes for the survivor on the server", "%.1f m in a second" % moved)
	_check(apart < 0.6, "and the client's copy is where the server's is", "%.2f m apart" % apart)

	# A hit of this survivor's, confirmed by the server, reaches this survivor's client: what
	# its hit marker and damage numbers are drawn from.
	var shot := DotDamage.make(server_me.entity_id, _server_game.horde.entity_id_for(npc), 5.0, null)
	shot.tick = _server_game.current_tick()
	var _landed := _server_game.combat.apply_damage(shot)
	await _steps(4)
	var hits: Array = _heard.get("hits", [])
	_check(hits.size() == 1 and absf(float(hits[0][1]) - 5.0) < 0.1 and not bool(hits[0][2]),
		"a survivor's hit on it is confirmed to that survivor's client", str(hits))

	_check((_heard.get("splats", []) as Array).is_empty(),
		"the shooter is not sent a SPLAT for their own hit (they splatter from the HIT)", str(_heard.get("splats", [])))

	# Another survivor's client is told where blood landed: a floor 1 m under the point, seen from above.
	var floor_at := Vector3(0.0, 0.0, 0.0)
	var floor_shape := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.2, 20.0)
	floor_col.shape = box
	floor_shape.add_child(floor_col)
	floor_shape.collision_layer = _server_game.world_mask()
	_server_game.add_child(floor_shape)
	floor_shape.global_position = floor_at - Vector3(0.0, 0.1, 0.0)
	await _steps(2)
	var sent := _server_bridge.splat(Vector3(2.0, 0.5, 3.0), Vector3(2.0, 2.5, 3.0), 0)
	await _steps(4)
	var splats: Array = _heard.get("splats", [])
	_check(sent and splats.size() == 1 and (splats[0][0] as Vector3).distance_to(Vector3(2.0, 0.0, 3.0)) < 0.05
		and (splats[0][1] as Vector3).dot(Vector3.UP) > 0.98,
		"a SPLAT reaches another client with the surface point and its normal", str(splats))
	var budget_sent := 0
	for _i in 100:
		if _server_bridge.splat(Vector3(2.0, 0.5, 3.0), Vector3(2.0, 2.5, 3.0), 0):
			budget_sent += 1
	_check(budget_sent <= int(ZzNetBridge.SPLAT_PER_SECOND), "SPLATs are rate limited", "%d of 100 in one burst" % budget_sent)
	floor_shape.queue_free()

	_hurt_npc(npc, 100000.0)
	await _steps(6)
	_check((_heard.get("hits", []) as Array).size() == 1,
		"and the world's damage (no survivor behind it) confirms nothing to anybody", str(_heard.get("hits", [])))
	_check(_heard.has("npc_gone") and int(_heard["npc_gone"][0]) == net_id and bool(_heard["npc_gone"][1]),
		"killed, and the client is told it died rather than went away")
	_check(_heard.has("npc_gone") and _heard["npc_gone"][2] is DotPlayerDeath,
		"and how it fell, for its body to fall that way")
	_finished()


func _test_only_what_is_near_is_sent() -> void:
	_section("a zombie out of range is not sent, and the boss and the team still are")
	var server_me := _server_me()
	server_me.place_at(STREET, 0.0)
	_stand_in.place_at(STREET + Vector3(2.0, 0.0, 1.0), 0.0)
	await _steps(4)

	# The street is shorter than any real radius, so the radii are cut to two metres for this
	# section: the same rule, with everything on the street far away. Without that this would
	# prove nothing about distance, and the boss check below would pass whether or not the
	# boss were exempt.
	var rule := _server_net.interest as DotNetInterestDistance
	_check(rule != null and rule.radius_by_tag.has(ZzNetBridge.TAG_COMMON) and rule.radius_by_tag.has(ZzNetBridge.TAG_SPECIAL)
		and ZzNetBridge.zombie_radius(ZzNpcs.COMMON) < ZzNetBridge.zombie_radius(ZzNpcs.STRANGLER),
		"the server tells commons by distance, and specials from further out")
	var radii: Dictionary = rule.radius_by_tag.duplicate()
	var interval := rule.evaluation_interval_sec
	rule.radius_by_tag = {ZzNetBridge.TAG_COMMON: 2.0, ZzNetBridge.TAG_SPECIAL: 2.0}
	rule.radius = 2.0
	rule.evaluation_interval_sec = 0.0

	var common := _server_game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0.0, 0.0, -10.0), &"test")
	var boss := _server_game.horde.spawner.spawn(ZzNpcs.BRUTE, STREET + Vector3(4.0, 0.0, -10.0), &"test")
	await _steps(6)
	# Its linger is the time half of hysteresis and runs on the wall clock, which a headless
	# run does not keep to; a zero here is what lets the distance show.
	var common_net: ZzNpcNet = _server_bridge._zombie_nets[common.instance_id]
	common_net.identity.interest_linger_sec = 0.0
	var common_id: int = common_net.identity.net_id
	var boss_id: int = (_server_bridge._zombie_nets[boss.instance_id] as ZzNpcNet).identity.net_id
	_check(common_net.identity.interest_tags.has(ZzNetBridge.TAG_COMMON) and not common_net.identity.always_relevant,
		"a common is tagged and not always relevant")
	_check((_server_bridge._zombie_nets[boss.instance_id] as ZzNpcNet).identity.always_relevant,
		"the boss is always relevant")

	# Both walk twenty metres on the server, well outside two metres of everyone.
	common.node.global_position += Vector3(20.0, 0.0, 0.0)
	boss.node.global_position += Vector3(20.0, 0.0, 0.0)
	await _steps(40)
	var boss_mirror := _client_bridge.zombie_mirror(boss_id)
	var common_mirror := _client_bridge.zombie_mirror(common_id)
	var boss_apart := boss_mirror.global_position.distance_to(boss.position()) if boss_mirror != null else INF
	var common_apart := common_mirror.global_position.distance_to(common.position()) if common_mirror != null else INF
	_check(boss_mirror != null and boss_apart < 1.0, "a boss far from every survivor is still where the server has it",
		"%.1f m apart" % boss_apart)
	_check(common_mirror != null and common_apart > 10.0, "a common out of range is not sent, so its copy stays where it was told last",
		"%.1f m apart" % common_apart)

	# A teammate far away is still a teammate: the player entities are always relevant.
	var teammate := _client_game.players.get(_stand_in.player_id) as ZzPlayer
	_stand_in.place_at(STREET + Vector3(-3.0, 0.0, 6.0), 0.0)
	await _steps(30)
	var team_apart := teammate.global_position.distance_to(_stand_in.global_position) if teammate != null else INF
	_check(teammate != null and team_apart < 1.0, "a teammate is tracked whatever the radius", "%.1f m apart" % team_apart)

	_hurt_npc(common, 100000.0)
	_hurt_npc(boss, 100000.0)
	rule.radius_by_tag = radii
	rule.radius = ZzNetBridge.DEFAULT_RADIUS
	rule.evaluation_interval_sec = interval
	await _steps(8)
	_finished()


func _test_a_down_reaches_the_client() -> void:
	_section("a down and a revive reach the client")
	var server_me := _server_me()
	server_me.health.invulnerable = false
	_hurt(server_me, 500.0)
	server_me.health.invulnerable = true
	await _steps(8)
	_check(server_me.is_down(), "the server has them down")
	_check(int(_heard.get("down", 0)) == SESSION, "the client is told")
	_check(_mine().is_down() and _mine().incaps == 1, "and its own survivor is on the floor, on the first of its downs",
		"life %d, incaps %d" % [_mine().life, _mine().incaps])

	_server_game.stand_up(server_me)
	await _steps(8)
	_check(_mine().is_up() and not _mine().is_down(), "stood up on the server, up on the client")
	_finished()


func _test_the_ads_rules_cross_to_the_client() -> void:
	_section("the server's aim-down-sights numbers reach the client, and the aim bit reaches the server")
	var server_me := _server_me()
	var mine := _mine()
	var id := server_me.weapons.current_def().id
	var server_rules := _server_game.ads_rules
	var client_rules := _client_game.ads_rules
	_check(server_rules != client_rules, "each game holds its own rules, so a client in the server's process is not the server")
	var kept := server_rules.to_wire()
	var _a := server_rules.set_value(&"", "spread_multiplier", 0.2)
	var _b := server_rules.set_value(&"", "move_speed_multiplier", 0.5)
	_check(client_rules.wire_hash() != server_rules.wire_hash(), "the client starts out disagreeing with the override")
	var link := FakeLink.new()
	link.held[ZeeAdsRules.CVAR] = server_rules.to_wire()
	_check(client_rules.follow_cvars(link), "a client follows the server's zee_ads_rules")
	_check(client_rules.wire_hash() == server_rules.wire_hash()
		and is_equal_approx(client_rules.spread_for(id), 0.2) and is_equal_approx(client_rules.move_speed_for(id), 0.5),
		"and holds the server's spread and pace", "%s vs %s" % [client_rules.wire_hash(), server_rules.wire_hash()])
	var _c := server_rules.set_value(&"", "spread_multiplier", 0.9)
	link.replicated_cvar_changed.emit(ZeeAdsRules.CVAR, server_rules.to_wire())
	_check(is_equal_approx(client_rules.spread_for(id), 0.9), "and follows every change")
	_check(not client_rules.adopt_wire("not json") and is_equal_approx(client_rules.spread_for(id), 0.9), "a bad value is refused and changes nothing")
	await _steps(8)
	var aim_pace: float = 1.0
	for _i in 40:
		await _step_with_actions(ZzNetCommand.ACT_AIM)
		aim_pace = server_me.weapons.ads_move_scale()
	_check(is_equal_approx(aim_pace, 0.5), "the aim bit from the client puts the server's gun at the server's pace", "%.2f" % aim_pace)
	if mine.view_rig != null:
		_check(is_equal_approx(mine.view_rig.ads_move_scale(), aim_pace), "and the predicting rig agrees", "%.2f" % mine.view_rig.ads_move_scale())
	await _steps(8)
	_check(is_equal_approx(server_me.weapons.ads_move_scale(), 1.0), "letting go of the sights restores full pace")
	var _d := server_rules.adopt_wire(kept)
	var _e := client_rules.adopt_wire(kept)
	_finished()


func _step_with_actions(actions: int) -> void:
	_tick += 1
	var _ticks := _client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
	_server_bridge.server_tick(_tick)
	_flush()
	_client_bridge.client_tick(_tick + INPUT_LEAD, DotFpsCommand.new(), 0, actions)
	_flush()
	await get_tree().physics_frame


func _test_a_pin_reaches_the_client() -> void:
	_section("a pin reaches the client, and so does the release")
	var server_me := _server_me()
	server_me.place_at(STREET, 0.0)
	await _steps(4)
	var strangler := _server_game.horde.spawner.spawn(ZzNpcs.STRANGLER, STREET + Vector3(0.0, 0.0, -10.0), &"test")
	await _steps(4)
	var _held := _server_game.pins.pin(_server_game.horde.entity_id_for(strangler), strangler, server_me.player_id, &"choke")
	await _steps(10)
	_check(_heard.has("pin") and int(_heard["pin"][0]) == SESSION and _heard["pin"][2] == &"choke"
		and _client_bridge.zombie_mirror(int(_heard["pin"][1])) != null, "the client is told who holds them, and how")
	_check(_mine().is_pinned() and _mine().pin_kind == &"choke", "and its own survivor is held")
	_hurt_npc(strangler, 100000.0)
	await _steps(10)
	_check(int(_heard.get("unpin", 0)) == SESSION and not _mine().is_pinned(), "killed: free on both ends")
	_finished()


func _test_loot_reaches_the_client() -> void:
	_section("what lies on the ground is told, and so is its going")
	var at := STREET + Vector3(1.0, 0.0, -2.0)
	var id := _server_game.loot.add(ZzLoot.MEDKIT, &"", at)
	await _steps(3)
	_check(_heard.has("loot") and int(_heard["loot"][0]) == id and _heard["loot"][1] == ZzLoot.MEDKIT, "a medkit appears")
	_check(_heard.has("loot") and (_heard["loot"][2] as Vector3).distance_to(_server_game.loot.position_of(id)) < 0.05,
		"where the server put it")
	_server_game.loot.remove(id, _server_me().player_id)
	await _steps(3)
	_check(_heard.has("loot_gone") and int(_heard["loot_gone"][0]) == id and int(_heard["loot_gone"][1]) == SESSION,
		"and goes, taken by them")
	_finished()


func _test_a_box_reaches_the_client() -> void:
	_section("a box opened is told to everybody, with what it did")
	_server_game.config.box_labels = true
	_server_game.boxes.open(&"medical", _server_me(), STREET)
	await _steps(4)
	_check(_heard.has("box") and int(_heard["box"][0]) == SESSION and _heard["box"][1] == &"medical"
		and str(_heard["box"][2]) != "", "who opened which, and the outcome's title",
		str(_heard.get("box", [])))
	_server_game.boxes.run([{"do": "damage_boost", "who": "opener", "scale": 1.5, "seconds": 20.0}],
		{"opener": _server_me(), "at": STREET, "box": &"arsenal"})
	await _steps(4)
	var rows: Array = _heard.get("effects", [])
	_check(rows.size() >= 1 and str(rows[0]["who"]) == "Ada", "and an effect that lasts is listed, on them by name", str(rows))
	_finished()


func _test_box_labels_off_hide_the_type() -> void:
	_section("with box_labels off the type never leaves the server")
	var cfg = _server_game.config
	cfg.box_labels = false
	var id := _server_game.loot.add(ZzLoot.BOX, &"horde", STREET + Vector3(2, 0, 0))
	await _steps(4)
	_check(_heard.has("loot") and int(_heard["loot"][0]) == id and _heard["loot"][3] == &"unknown",
		"a box on the ground is announced as unknown", str(_heard.get("loot")))
	var me = _server_me()
	var _c = _server_game.boxes.carry(me, &"horde")
	await _steps(6)
	var mine = _client_game.player_by_id(_me())
	if mine != null:
		_check(mine.carried_count == 1 and mine.carried_index == 0, "and the carried slot has a count but no type", str(mine.carried_index))
	_server_game.boxes.drop_carried(me)
	_server_game.loot.remove(id)
	# Opened with labels off: the outcome is the reveal (title and message reach everybody), the
	# type is not. Armed by the section above, where the same open names its type.
	_heard.erase("box")
	_server_game.boxes.open(&"medical", me, STREET)
	await _steps(4)
	_check(_heard.has("box") and _heard["box"][1] == &"unknown" and str(_heard["box"][2]) != "" and str(_heard["box"][3]) != "",
		"an opened box reveals the outcome but sends its type as unknown", str(_heard.get("box", [])))
	cfg.box_labels = false
	_finished()


class FakeLink extends RefCounted:
	signal replicated_cvar_changed(cvar_name: String, value: String)
	var held := {}

	func replicated_cvar(cvar_name: String, fallback: String) -> String:
		return String(held.get(cvar_name, fallback))


func _test_a_downed_crawl_is_predicted() -> void:
	_section("a downed survivor's crawl is predicted, and follows the server's setting")
	var server_me := _server_me()
	var mine := _mine()
	server_me.health.invulnerable = false
	_server_game.crawl_rules.speed = 1.4
	_client_game.crawl_rules.speed = 1.4
	server_me.place_at(STREET, 0.0)
	await _steps(10)
	_hurt(server_me, 500.0)
	server_me.health.invulnerable = true
	await _steps(8)
	var forward := DotFpsCommand.new()
	forward.move = Vector2(0.0, 1.0)
	var before := mine.controller.state.position
	await _steps(48, forward)
	await _steps(24)
	var gone := mine.controller.state.position.distance_to(before)
	var apart := mine.controller.state.position.distance_to(server_me.controller.state.position)
	_check(mine.is_down() and gone > 0.5 and gone < 3.0, "the client's own downed survivor crawls on the keys", "%.2f m" % gone)
	_check(apart < 0.25, "and the two ends agree where they got to", "%.3f m" % apart)

	_server_game.crawl_rules.speed = 0.0
	_client_game.crawl_rules.speed = 0.0
	await _steps(4)
	before = mine.controller.state.position
	await _steps(40, forward)
	await _steps(16)
	_check(mine.controller.state.position.distance_to(before) < 0.15 and server_me.controller.state.position.distance_to(before) < 0.3,
		"at 0 neither end moves them")

	var link := FakeLink.new()
	link.held[ZzCrawlRules.CVAR] = "2.5"
	var follower := ZzCrawlRules.new()
	_check(follower.follow_cvars(link) and is_equal_approx(follower.speed, 2.5), "a client reads the server's value through its link")
	link.replicated_cvar_changed.emit(ZzCrawlRules.CVAR, "0.5")
	_check(is_equal_approx(follower.speed, 0.5), "and follows every change")

	_server_game.crawl_rules.speed = 1.4
	_client_game.crawl_rules.speed = 1.4
	_server_game.stand_up(server_me)
	await _steps(8)
	_finished()

	_section("the team list is the server's setting (zz_team_roster), followed by a client")
	var roster_link := FakeLink.new()
	var roster_cfg := ZzConfig.new()
	_check(not roster_cfg.team_roster, "off by default")
	roster_link.held["zz_team_roster"] = "1"
	_check(ZzClient.follow_roster(roster_link, roster_cfg) and roster_cfg.team_roster, "a client reads the server's value through its link")
	roster_link.replicated_cvar_changed.emit("zz_team_roster", "0")
	_check(not roster_cfg.team_roster, "and follows every change")
	roster_link.replicated_cvar_changed.emit("zz_team_roster", "1")
	_check(roster_cfg.team_roster, "on again")
	_check(ZzClient.health_text(_mine()) != "" and ZzClient.downs_text(_mine(), 3) != "", "the board has a health and a downs text for a replicated survivor",
		"%s / %s" % [ZzClient.health_text(_mine()), ZzClient.downs_text(_mine(), 3)])
	_finished()


## Ctrl and C as key events through the real sampler, then the command on the wire: both ends crouch and lower the eye.
func _test_crouch_reaches_both_ends() -> void:
	_section("crouching: Ctrl and C reach the command, and both ends lower the body and the eye")
	var sampler := DotFpsSampler.new(ZzPlayer.tunables_for(_server_game.config))
	ZzPlayer.register_actions(sampler)

	for code: Key in [KEY_CTRL, KEY_C]:
		var press := InputEventKey.new()
		press.physical_keycode = code
		press.keycode = code
		press.pressed = true
		press.ctrl_pressed = code == KEY_CTRL
		Input.parse_input_event(press)
		Input.flush_buffered_events()
		_check(sampler.sample(0.016).is_pressed(DotFpsCommand.BUTTON_CROUCH), "%s held sets the command's crouch bit" % OS.get_keycode_string(code))
		var release := press.duplicate() as InputEventKey
		release.pressed = false
		release.ctrl_pressed = false
		Input.parse_input_event(release)
		Input.flush_buffered_events()
		_check(not sampler.sample(0.016).is_pressed(DotFpsCommand.BUTTON_CROUCH), "%s released clears it" % OS.get_keycode_string(code))

	var server_me := _server_me()
	var mine := _mine()
	server_me.place_at(STREET, 0.0)
	await _steps(30)
	var stand_server := server_me.eye_position().y - server_me.controller.state.position.y
	var stand_client := mine.eye_position().y - mine.controller.state.position.y
	var held := DotFpsCommand.new()
	held.set_button(DotFpsCommand.BUTTON_CROUCH, true)
	await _steps(40, held)
	await _steps(10, held)
	_check(server_me.controller.state.crouch_fraction > 0.99, "the server's survivor is crouched", str(server_me.controller.state.crouch_fraction))
	_check(mine.controller.state.crouch_fraction > 0.99, "the client's predicted one is crouched", str(mine.controller.state.crouch_fraction))
	var low_server := server_me.eye_position().y - server_me.controller.state.position.y
	var low_client := mine.eye_position().y - mine.controller.state.position.y
	_check(low_server < stand_server - 0.3 and low_client < stand_client - 0.3, "and both eyes are lower", "%.2f -> %.2f, %.2f -> %.2f" % [stand_server, low_server, stand_client, low_client])
	await _steps(40)
	_check(server_me.controller.state.crouch_fraction < 0.01 and mine.controller.state.crouch_fraction < 0.01, "released, both stand again")
	_finished()


func _test_a_gate_reaches_the_client() -> void:
	_section("a gate opened on the server opens on the client")
	_server_game.open_gate("barrier")
	await _steps(4)
	_check(str(_heard.get("gate", "")) == "barrier", "the client is told")
	_check(not _client_game.map.gate_is_shut("barrier"), "and its barrier is up: nobody walks into a wall that is not there")
	_finished()


## A world of one hinged prop door, as dot-map's manifest writes it.
class DoorWorld extends RefCounted:
	var ents: Variant = DotMapEntities.from_manifest({"movers": [{"entity": 900, "model": null, "kind": "rotate", "classname": "prop_door_rotating",
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
	_finished()


## A survival hold through the bridge (zz-survival-net-check-1): the stage, wave and clock a
## client is told, the daylight of a hold kept by nights, and a barricade broken and mended
## reaching the client's map, its collision and its picture. Until this, both events were
## checked only as codec round trips and solo play reads the world directly.
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
		if int(_client_game.survival_state().get("stage", -1)) == DotNpcDirectorWaves.Stage.HORDE:
			break
		await _step()
	told = _client_game.survival_state()
	_check(int(told.get("stage", -1)) == DotNpcDirectorWaves.Stage.HORDE and int(told.get("index", 0)) == 1
		and float(told.get("daylight", -1.0)) >= 0.0 and float(told.get("daylight", 1.0)) < 0.02,
		"night 1 falls on the client, in the dark (daylight is sent in 255ths)", str(told))

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
	_finished()


func _test_leaving() -> void:
	_section("leaving")
	_server_bridge.remove_peer(CLIENT_PEER)
	await _steps(8)
	_check(not _server_game.players.has(_me()), "the server lets them go")
	_check(_server_game.players.has(_stand_in.player_id), "and keeps the stand-in")
	_finished()


# --- Helpers --------------------------------------------------------------------

func _me() -> StringName:
	return ZzNetBridge.player_key(SESSION)


func _mine() -> ZzPlayer:
	return _client_game.players.get(_me())


func _server_me() -> ZzPlayer:
	return _server_game.players[_me()]


## A command that looks from [param player]'s eye at [param target].
func _aim_at(player: ZzPlayer, target: Vector3) -> DotFpsCommand:
	var look := target - player.eye_position()
	var command := DotFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	return command


func _hurt(player: ZzPlayer, amount: float) -> void:
	var hit := DotDamage.make(0, player.entity_id, amount, _server_game.combat.damage_type(&"strike"))
	hit.tick = _server_game.current_tick()
	var _applied := _server_game.combat.apply_damage(hit)


func _test_a_head_shot_off_reaches_the_client() -> void:
	_section("a shot that takes a limb off is seen by the client, and a head off kills")
	var server_me := _server_me()
	server_me.place_at(STREET, 0.0)
	await _steps(4)
	_heard.erase("npc")
	var npc := _server_game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0.0, 0.0, -10.0), &"test", Basis(Vector3.UP, PI))
	await _steps(6)
	var net_id: int = _heard["npc"][0] if _heard.has("npc") else 0
	var body := npc.node as ZzZombieBody
	_check(body != null and body.limbs != null and body.limbs.limb_names().has(&"armL"), "a common has its limbs on the server")
	var mirror := _client_bridge.zombie_mirror(net_id)
	_check(mirror != null and mirror.limbs != null and mirror.limb_mask == 0, "and on the client, all attached")

	# A body shot at the left arm: gone, and the zombie lives, slower to hurt.
	var arm := body.limbs.points_of(body.limbs.defs[&"armL"])
	var shot := DotDamage.make(server_me.entity_id, _server_game.horde.entity_id_for(npc), 35.0, null)
	shot.point = arm[arm.size() - 1]
	shot.direction = Vector3.FORWARD
	shot.tick = _server_game.current_tick()
	var _landed := _server_game.combat.apply_damage(shot)
	_check(body.limbs.is_severed(&"armL") and npc.is_alive(), "a shot at an arm severs it, and the zombie lives")
	_check(body.limbs.attack_scale() < 1.0, "with a weaker swing", str(body.limbs.attack_scale()))
	var waited := 0
	while mirror != null and mirror.limb_mask == 0 and waited < 30:
		await _step()
		waited += 1
	_check(mirror != null and mirror.limbs != null and mirror.limbs.is_severed(&"armL"),
		"and the client's copy has the arm severed", str(mirror.limb_mask) if mirror != null else "gone")

	# A head shot: the head, then the life.
	var head := DotDamage.make(server_me.entity_id, _server_game.horde.entity_id_for(npc), 20.0, null)
	head.hit_group = DotHitGroup.HEAD
	head.point = body.global_position + Vector3(0.0, 1.6, 0.0)
	head.direction = Vector3.FORWARD
	head.tick = _server_game.current_tick()
	var _headed := _server_game.combat.apply_damage(head)
	_check(body.limbs.is_severed(&"head"), "a head shot severs the head")
	_check(not npc.is_alive(), "and a lost head kills it")
	await _steps(SERVER_TICK_RATE * 2)
	_finished()


func _test_gore_off_takes_no_limb() -> void:
	_section("gore level 0: a shot at a limb takes none and a head shot is only damage")
	var server_me := _server_me()
	var npc := _server_game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0.0, 0.0, -10.0), &"test", Basis(Vector3.UP, PI))
	await _steps(4)
	var body := npc.node as ZzZombieBody
	DotNpcGore.level = 0
	var arm := body.limbs.points_of(body.limbs.defs[&"armL"])
	var shot := DotDamage.make(server_me.entity_id, _server_game.horde.entity_id_for(npc), 35.0, null)
	shot.point = arm[arm.size() - 1]
	shot.direction = Vector3.FORWARD
	shot.tick = _server_game.current_tick()
	var _landed := _server_game.combat.apply_damage(shot)
	_check(body.limbs.mask() == 0 and npc.is_alive(), "level 0: the arm stays on")
	var head := DotDamage.make(server_me.entity_id, _server_game.horde.entity_id_for(npc), 1.0, null)
	head.hit_group = DotHitGroup.HEAD
	head.point = body.global_position + Vector3(0.0, 1.6, 0.0)
	head.direction = Vector3.FORWARD
	head.tick = _server_game.current_tick()
	var _headed := _server_game.combat.apply_damage(head)
	_check(body.limbs.mask() == 0 and npc.is_alive(), "level 0: a head shot takes no head and does not kill by it")
	DotNpcGore.reset()
	_finished()


func _hurt_npc(npc: DotNpcInstance, amount: float) -> void:
	var hit := DotDamage.make(0, _server_game.horde.entity_id_for(npc), amount, _server_game.combat.damage_type(&"strike"))
	hit.tick = _server_game.current_tick()
	var _applied := _server_game.combat.apply_damage(hit)


func _make_game(server: bool, parent: Node) -> ZzGame:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.start_grace_seconds = 0.5
	config.escape_grace_seconds = 0.0
	config.wanderer_density = 0.0
	config.sleepers_enabled = false
	config.specials_base = 0
	config.mob_interval_min = 900.0
	config.mob_interval_max = 900.0
	config.brute_interval_min = 0.0
	config.brute_interval_max = 0.0
	config.box_drop_common = 0.0
	config.map_ids = PackedStringArray(["zz_practice"])

	var game := ZzGame.new()
	game.name = "World"
	game.config = config
	game.authoritative = server
	game.tick_rate = SERVER_TICK_RATE if server else CLIENT_ENGINE_TICK_RATE
	game.register_service = false
	parent.add_child(game)
	game.set_physics_process(false)
	return game


func _make_manager(server: bool, scope: StringName, peer_id: int, parent: Node, tick_rate: int) -> DotNetManager:
	var manager := DotNetManager.new()
	manager.name = "Server" if server else "Client"
	manager.is_server = server
	manager.local_peer_id = peer_id
	manager.service_scope = scope
	manager.auto_tick = false
	manager.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = tick_rate
	config.snapshot_rate = SNAPSHOT_RATE
	config.enable_prediction = true
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 192
	config.world_extent = ZzGame.NET_WORLD_EXTENT
	manager.config = config

	parent.add_child(manager)
	var _ready_now := manager.setup()
	return manager


func _on_server_send(method: StringName, peer_id: int, payload: PackedByteArray) -> void:
	if peer_id != 0 and peer_id != CLIENT_PEER:
		return

	_to_client.append({"method": method, "payload": payload})


func _on_client_send(method: StringName, _peer_id: int, payload: PackedByteArray) -> void:
	_to_server.append({"method": method, "payload": payload})


func _flush() -> void:
	var to_client := _to_client.duplicate()
	var to_server := _to_server.duplicate()
	_to_client.clear()
	_to_server.clear()

	for entry in to_client:
		_client_bridge.link.deliver(entry["method"], 1, entry["payload"])

	for entry in to_server:
		_server_bridge.link.deliver(entry["method"], CLIENT_PEER, entry["payload"])


func _exchange() -> void:
	_flush()
	_flush()


## One tick on both ends, with a real physics frame between them.
func _step(command: DotFpsCommand = null) -> void:
	_tick += 1
	var _ticks := _client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
	_server_bridge.server_tick(_tick)
	_flush()
	_client_bridge.client_tick(_tick + INPUT_LEAD, command if command != null else DotFpsCommand.new())
	_flush()
	await get_tree().physics_frame


func _steps(count: int, command: DotFpsCommand = null) -> void:
	for _i in range(count):
		await _step(command)


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	var line := "%s%s" % [what, "" if detail == "" else "  (%s)" % detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


## Counts the engine's own errors while installed (mg-smash-copter's dedicated suite has the
## same class): they go to stderr and change no exit code, so only this makes one fail a run.
class EngineErrors extends Logger:
	var _lock := Mutex.new()
	var _seen := PackedStringArray()

	func _log_error(
		function: String, _file: String, _line: int, code: String, _rationale: String,
		_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		_lock.lock()
		_seen.append("%s (%s)" % [code, function])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func seen() -> PackedStringArray:
		_lock.lock()
		var out := _seen.duplicate()
		_lock.unlock()
		return out
