extends GSGameCheckSuite

## The personas, the stuck rescue and the world helpers of [headless_survival.gd], split off to keep each file under the size gate.


const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
## In the practice street, clear of the cars.
const STREET := Vector3(0.0, 0.05, 14.0)
var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []
## The last map decided in the world under test: [won, why]. Read from `round_over`, because
## with no intermission the next round has begun (and forgotten the decision) by the time a
## section looks.
var _result: Array = []
func _test_personas() -> void:
	_section("bot personas: no idling with infected alive, and profiles added and deleted")
	var game := await _hold(func(c: ZzConfig) -> void:
		c.survival_style = 0
		c.waves = 2
		c.survival_warmup_seconds = 1.0
		c.wave_size = 8
		c.wave_size_per_survivor = 0
		c.brute_every_waves = 0, 4)
	var bots: Array[ZzPlayer] = []
	for bot in game.survivors():
		bot.is_bot = true
		bots.append(bot)
	await _sim(game, 3.0)
	var left: int = game.horde.infected_left()
	_check(left > 0, "a wave is on", "%d infected" % left)

	var acted := 0
	var picked := {}
	var all_assigned := true
	for bot in bots:
		var memory: Dictionary = game.bots._memory(bot)
		all_assigned = all_assigned and memory.get("persona") is GSBotPersona
		if game.bots.persona_act(bot, GSFpsCommand.new(), memory):
			acted += 1
			picked[String(memory.get("behave", &""))] = true
	_check(all_assigned, "every stand-in is given a persona from the server's pool")
	_check(acted == bots.size(), "each acts on a behaviour while infected remain", "%d of %d" % [acted, bots.size()])
	_check(not picked.is_empty() and picked.keys().all(func(k: String) -> bool: return GSBotPersona.BEHAVIOURS.has(StringName(k))),
		"and it is one of hunt, loot, hold, support, scout", str(picked.keys()))

	var before: Vector3 = bots[0].feet()
	await _sim(game, 6.0)
	var gap: float = bots[0].feet().distance_to(before)
	_check(gap > 0.5, "they walk rather than stand", "%.1f m" % gap)

	var base := "user://zz_personas_selftest"
	var runtime := GSProfileRuntime.new()
	var set: GSProfileSet = game.bot_persona_set()
	runtime.add_set(set)
	runtime.save_root = base
	runtime.permit = func(_actor: Variant, _flag: String) -> bool: return true
	var ids_before := set.list_ids().size()
	var added := runtime.handle_request("admin", GSProfileRuntime.make_request("add", GSBotPersona.KIND, "sentry", "", {"weight": 3.0}))
	game.reload_personas()
	_check(added.ok and set.has_id("sentry") and set.list_ids().size() == ids_before + 1, "a persona is added through the runtime")
	_check(game.personas().weight_of(_persona(game, "sentry")) > 0.0, "and the server's pool draws on it after a reload")
	var removed := runtime.handle_request("admin", GSProfileRuntime.make_request("delete", GSBotPersona.KIND, "sentry"))
	game.reload_personas()
	_check(removed.ok and not set.has_id("sentry") and _persona(game, "sentry") == null, "and deleted, it leaves the set and the pool")
	var shipped := runtime.handle_request("admin", GSProfileRuntime.make_request("delete", GSBotPersona.KIND, "scout"))
	game.reload_personas()
	_check(shipped.ok and _persona(game, "scout") == null and _persona(game, "hunter") != null, "a shipped persona can be deleted and the rest stay")
	game.config.bot_personas = "hunter:1"
	_check(game.personas().candidates().size() == 1 and game.personas().candidates()[0].id == &"hunter", "the server's override pins the pool", str(game.personas().describe()))
	_rm_dir(base)
	_finished()


func _persona(game: ZzGame, id: String) -> GSBotPersona:
	for p in game.personas().personas:
		if p.id == StringName(id):
			return p
	return null


func _rm_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm_dir(dir.path_join(d))
	DirAccess.remove_absolute(dir)


## An infected that makes no progress toward the survivors is repathed, then put near them.
func _test_stuck_rescue() -> void:
	_section("stuck infected: no progress means a repath, then a relocation near the survivors")
	var game := await _hold(func(c: ZzConfig) -> void:
		c.survival_style = 0
		c.waves = 2
		c.survival_warmup_seconds = 1.0
		c.wave_size = 8
		c.wave_size_per_survivor = 0
		c.stuck_repath_seconds = 5.0
		c.stuck_relocate_seconds = 12.0
		c.stuck_low_count = 0
		c.brute_every_waves = 0, 1)
	await _sim(game, 3.0)
	var npc: GSNpcInstance = null
	for n in game.horde.spawner.npcs_of(game.horde.WAVE):
		if n.is_alive() and n.node is ZzZombieBody:
			npc = n
			break
	_check(npc != null, "a wave zombie to hold still")
	if npc == null:
		for i in 3:
			_check(false, "skipped: no zombie")
		_finished()
		return
	var body := npc.node as ZzZombieBody
	body.global_position = STREET + Vector3(0.0, 0.0, 30.0)
	game.horde.stuck.clear()
	game.horde._rescue_if_stuck(npc)
	game.horde._time += 6.0
	game.horde._rescue_if_stuck(npc)
	_check(game.horde.stuck.repaths == 1 and game.horde.stuck.relocations == 0, "five seconds without progress repaths it", str(game.horde.stuck.describe()))
	var from := npc.position()
	game.horde._time += 8.0
	game.horde._rescue_if_stuck(npc)
	_check(game.horde.stuck.relocations == 1 and npc.position().distance_to(from) > 1.0, "twelve without progress relocates it", "%.1f m" % npc.position().distance_to(from))
	var near := INF
	for id in game.horde.survivor_ids():
		near = minf(near, npc.position().distance_to(game.horde.survivor_position(id)))
	_check(near < from.distance_to(STREET) + 0.1 or near < 60.0, "to somewhere near the survivors", "%.1f m" % near)
	_finished()




## A survival world with [param count] invulnerable survivors standing in it. The practice street
## made a survival map (with two caches) unless [param map] names one.
func _hold(configure: Callable, count: int, map: StringName = &"") -> ZzGame:
	var game := await _world(func(c: ZzConfig) -> void:
		c.wanderer_density = 0.0
		c.sleepers_enabled = false
		c.specials_base = 0
		configure.call(c))

	if map == &"":
		var doc := ZzCatalogue.practice().duplicate(true)
		doc["id"] = "zz_hold"
		doc["mode"] = ZzMapDoc.SURVIVAL
		doc["objectives"] = []
		doc["caches"] = [[-2.0, 0.0, 10.0], [2.0, 0.0, 10.0]]
		var checked := ZzMapDoc.validate(doc)
		var _added := game.catalogue._add(checked.value, "test") if checked.ok else false
		game.next_map_id = &"zz_hold"
	else:
		game.next_map_id = map

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Holder%d" % i)
		player.health.invulnerable = true

	game.start()
	await _sim(game, 0.3)

	for player in game.survivors():
		player.health.invulnerable = true
		if map == &"":
			player.place_at(STREET + Vector3(float(player.get_index() % 3), 0.0, 0.0), 0.0)

	return game


## Kills the wave in play until wave [param index] is over.
func _clear_wave(game: ZzGame, index: int) -> void:
	for i in 400:
		if game.survival == null or game.survival.waves.index > index or game.survival.waves.stage == GSNpcDirectorWaves.Stage.DONE:
			return
		if game.survival.waves.stage == GSNpcDirectorWaves.Stage.QUIET and game.survival.waves.index > index:
			return
		for npc in game.horde.spawner.npcs_of(game.horde.WAVE):
			if npc.is_alive():
				_hurt_npc(game, npc, 5000.0)
		await _sim(game, 0.25)


func _won_with(words: String) -> bool:
	return _result.size() == 2 and bool(_result[0]) and str(_result[1]).contains(words)


func _world(configure: Callable = Callable()) -> ZzGame:
	for old in _worlds.duplicate():
		await _dispose(old)

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.start_grace_seconds = 1.0
	config.escape_grace_seconds = 0.0

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
	_result = []
	game.round_over.connect(func(_number: int, won: bool, why: String) -> void: _result = [won, why])
	await get_tree().physics_frame
	await get_tree().physics_frame
	return game


func _dispose(game: ZzGame) -> void:
	_worlds.erase(game)

	if not is_instance_valid(game):
		return

	remove_child(game)
	game.free()
	await get_tree().process_frame


func _sim(game: ZzGame, seconds: float) -> void:
	var ticks := maxi(int(round(seconds * float(TICK_RATE))), 1)

	for i in ticks:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	await get_tree().physics_frame


func _aim(player: ZzPlayer, target: Vector3) -> void:
	var look := target - player.eye_position()
	var command := GSFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	player.controller.apply_command(command)
	player.controller.state.yaw = command.yaw
	player.controller.state.pitch = command.pitch


func _hurt(game: ZzGame, player: ZzPlayer, amount: float) -> void:
	var hit := GSDamage.make(0, player.entity_id, amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _hurt_npc(game: ZzGame, npc: GSNpcInstance, amount: float) -> void:
	var hit := GSDamage.make(0, game.horde.entity_id_for(npc), amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1
