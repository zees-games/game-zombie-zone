extends DotGameCheckSuite

## The world and simulation helpers of [headless_run.gd]'s suite, split off to keep each file under the size gate.


const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
var _worlds: Array[ZzGame] = []


func _world(configure: Callable = Callable()) -> ZzGame:
	for old in _worlds.duplicate():
		await _dispose(old)

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.map_ids = PackedStringArray(["zz_practice"])
	config.keep_progress = false
	config.start_grace_seconds = 1.0
	config.escape_grace_seconds = 0.0
	config.sleepers_enabled = true
	# The other sections time arrivals at the old running pace; the speed section turns it back on.
	config.common_speed_scaling = false

	if configure.is_valid():
		configure.call(config)

	var game := ZzGame.new()
	game.name = "World%d" % _worlds.size()
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	_worlds.append(game)

	await get_tree().physics_frame
	await get_tree().physics_frame
	return game


## A world with [param count] survivors, started, a moment in. Stand-ins only when [param bots].
func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game


## Nothing on the street but what a section puts there: no wanderers, no specials, no mob, no
## director crowd. A wanderer's swing during a revive or a heal is a different number, and which
## spawn point a wanderer is drawn at is the horde's business, not the section's.
static func _quiet(c: ZzConfig) -> void:
	c.wanderer_density = 0.0
	c.director_enabled = false
	c.specials_base = 0
	c.mob_interval_min = 900.0
	c.mob_interval_max = 900.0
	c.sleepers_enabled = false


func _dispose(game: ZzGame) -> void:
	_worlds.erase(game)

	if not is_instance_valid(game):
		return

	remove_child(game)
	game.free()
	await get_tree().process_frame


## [param seconds] of simulated time. A physics frame every eight ticks, which is enough for a
## freshly built body to be in the space; queries see moved bodies at once.
func _sim(game: ZzGame, seconds: float) -> void:
	var ticks := maxi(int(round(seconds * float(TICK_RATE))), 1)

	for i in ticks:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	await get_tree().physics_frame


## Holds or releases the survivor's primary fire on the command the server reads this tick.
func _fire(who: ZzPlayer, on: bool) -> void:
	var command := DotFpsCommand.new()
	command.set_button(ZzNetCommand.BUTTON_FIRE, on)
	who.controller.current_command = command


func _aim(player: ZzPlayer, target: Vector3) -> void:
	var look := target - player.eye_position()
	var command := DotFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	player.controller.apply_command(command)
	player.controller.state.yaw = command.yaw
	player.controller.state.pitch = command.pitch


func _shot(game: ZzGame, from: ZzPlayer, at: Vector3, damage: float) -> DotShot:
	var shot := DotShot.make(&"test", from.entity_id, game.current_tick(), 0)
	shot.origin = from.eye_position()
	shot.direction = (at - shot.origin).normalized()
	shot.damage = damage
	shot.damage_type = game.combat.damage_type(&"strike")
	shot.max_range = 100.0
	shot.scatter()
	return game.combat.resolve_shot(shot)


func _hurt(game: ZzGame, player: ZzPlayer, amount: float) -> void:
	var hit := DotDamage.make(0, player.entity_id, amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _hurt_npc(game: ZzGame, npc: DotNpcInstance, amount: float) -> void:
	var hit := DotDamage.make(0, game.horde.entity_id_for(npc), amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


## View-model hands as zee_weapons drew them before `resolve_scope_mode` and `view_fov_scale`.
class OldScopeHands extends RefCounted:
	const ZOOM := 0.4

	func aim_fov_scale() -> float:
		return ZOOM


## Collects the engine's SCRIPT errors (any thread) while installed.
class ScriptErrors extends Logger:
	var _lock := Mutex.new()
	var _seen := PackedStringArray()

	func _log_error(
		function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]
	) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		_seen.append("%s %s (%s %s:%d)" % [code, rationale, function, file, line])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func seen() -> PackedStringArray:
		_lock.lock()
		var out := _seen.duplicate()
		_lock.unlock()
		return out
