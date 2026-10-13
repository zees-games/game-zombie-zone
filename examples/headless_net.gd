extends Node

const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzEvent := preload("../game/net/zz_event.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzHud := preload("../game/zz_hud.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzNetBridge := preload("../game/net/zz_net_bridge.gd")
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

const SECTIONS := 16
const CHECKS := 83

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
	print("zombiezone over the wire")
	print("")

	_test_the_codec()

	if await _build():
		await _test_a_client_joins()
		await _test_the_map_arrives()
		await _test_the_local_player_is_predicted()
		await _test_shots_count_online()
		await _test_zombies_replicate()
		await _test_a_down_reaches_the_client()
		await _test_a_pin_reaches_the_client()
		await _test_loot_reaches_the_client()
		await _test_a_box_reaches_the_client()
		await _test_a_gate_reaches_the_client()
		await _test_the_map_ends()
		await _test_a_hold_reaches_the_client()
		# Late: it runs eighty ticks, and the hold's clock above reads a time of day.
		await _test_the_toys_reach_the_client()
		await _test_leaving()

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

	var clock := ZzEvents.read_clock(_r(ZzEvents.write_clock(3, 2, 40.25, 12.5, 60.0, 4, true, 0, 1, 20.0)))
	_check(bool(clock["ok"]) and int(clock["round"]) == 3 and absf(float(clock["elapsed"]) - 40.25) < 0.1
		and absf(float(clock["held"]) - 12.5) < 0.1 and int(clock["alive"]) == 4 and int(clock["objective"]) == 0
		and int(clock["objective_state"]) == 1, "CLOCK", str(clock))

	var npc := ZzEvents.read_npc(_r(ZzEvents.write_npc(77, ZzNpcs.STRANGLER, 513, Vector3(3.5, 0.0, -12.25))))
	_check(bool(npc["ok"]) and int(npc["net_id"]) == 77 and npc["kind"] == ZzNpcs.STRANGLER and int(npc["variant"]) == 513
		and (npc["at"] as Vector3).distance_to(Vector3(3.5, 0.0, -12.25)) < 0.05, "NPC", str(npc))

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
	_check(ZzEvent.fits(), "every event kind fits the kind field",
		"%d kinds in %d bits" % [ZzEvents.Kind.size(), ZzEvent.KIND_BITS])

	var hit := ZzEvents.read_hit(_r(ZzEvents.write_hit(DotEntity.make_id(DotEntity.KIND_NPC, 4321), 17.5, Vector3(1.0, 1.4, -6.0), true, true)))
	_check(bool(hit["ok"]) and int(hit["victim"]) == 4321 and absf(float(hit["amount"]) - 17.5) < 0.1
		and bool(hit["killed"]) and bool(hit["headshot"]) and (hit["point"] as Vector3).distance_to(Vector3(1.0, 1.4, -6.0)) < 0.01,
		"HIT (the victim's entity serial, so a whole entity id never overflows the field)", str(hit))

	var effects := ZzEvents.read_effects(_r(ZzEvents.write_effects([
		{"title": "Glass cannon", "stacks": 2, "seconds": 14.25, "who": "everybody", "scale": 1.5},
	])))
	var rows: Array = effects["effects"]
	_check(bool(effects["ok"]) and rows.size() == 1 and int(rows[0]["stacks"]) == 2 and str(rows[0]["title"]) == "Glass cannon",
		"EFFECTS", str(rows))

	var hazard := ZzEvents.read_hazard(_r(ZzEvents.write_hazard(9, &"acid", Vector3(2.0, 0.0, 3.0), 3.5, 7.0)))
	_check(bool(hazard["ok"]) and hazard["kind"] == &"acid" and absf(float(hazard["radius"]) - 3.5) < 0.05
		and absf(float(hazard["seconds"]) - 7.0) < 0.1, "HAZARD", str(hazard))

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
	_client_bridge.loot_added.connect(func(id: int, kind: StringName, _item: StringName, at: Vector3) -> void:
		_heard["loot"] = [id, kind, at])
	_client_bridge.loot_removed.connect(func(id: int, by: int) -> void:
		_heard["loot_gone"] = [id, by])
	_client_bridge.box_received.connect(func(who: int, type_id: StringName, title: String, _message: String) -> void:
		_heard["box"] = [who, type_id, title])
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

	_hurt_npc(npc, 100000.0)
	await _steps(6)
	_check((_heard.get("hits", []) as Array).size() == 1,
		"and the world's damage (no survivor behind it) confirms nothing to anybody", str(_heard.get("hits", [])))
	_check(_heard.has("npc_gone") and int(_heard["npc_gone"][0]) == net_id and bool(_heard["npc_gone"][1]),
		"killed, and the client is told it died rather than went away")
	_check(_heard.has("npc_gone") and _heard["npc_gone"][2] is DotPlayerDeath,
		"and how it fell, for its body to fall that way")
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


func _test_a_gate_reaches_the_client() -> void:
	_section("a gate opened on the server opens on the client")
	_server_game.open_gate("barrier")
	await _steps(4)
	_check(str(_heard.get("gate", "")) == "barrier", "the client is told")
	_check(not _client_game.map.gate_is_shut("barrier"), "and its barrier is up: nobody walks into a wall that is not there")
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
	_check(float(told.get("daylight", -1.0)) > 0.3 and absf(float(told["daylight"]) - float(served["daylight"])) < 0.1,
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
