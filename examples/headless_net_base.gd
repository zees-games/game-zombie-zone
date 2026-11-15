extends DotGameCheckSuite

const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzCrawlRules := preload("../game/zz_crawl_rules.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzEvent := preload("../game/net/zz_event.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzEventsText := preload("../game/net/zz_events_text.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")
const ZzMechanics := preload("../game/zz_mechanics.gd")
const ZzClient := preload("../game/zz_client.gd")
const ZzKillcam := preload("../game/zz_killcam.gd")
const ZzHud := preload("../game/zz_hud.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzNetBridge := preload("../game/net/zz_net_bridge.gd")
const ZzImpactMarks := preload("../game/zz_impact_marks.gd")
const ZzNpcNet := preload("../game/net/zz_npc_net.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzPacks := preload("../game/zz_packs.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view_base.gd")
const ZzRequest := preload("../game/net/zz_request.gd")
const ZzTestToys := preload("zz_test_toys.gd")

const CLIENT_PEER := 7
const SESSION := 42
const SERVER_TICK_RATE := 64
const CLIENT_ENGINE_TICK_RATE := 30
const SNAPSHOT_RATE := 30
const INPUT_LEAD := 3

## Out on the practice street, past the start room's grace, short of the barrier.
const STREET := Vector3(0.0, 0.05, 14.0)


var _sections_entered := 0
var _sections_finished := 0

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
	config.max_entities_per_snapshot = 0
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
