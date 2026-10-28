extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzHazards := preload("../game/zz_hazards.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzEvents := preload("../game/net/zz_events.gd")

## The acid pool on dot-effects' shared DotHazardPool, and what it adds: caps, trail, slow. Counts sections AND checks.

const SECTIONS := 6
const CHECKS := 28

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const SPOT := Vector3(0.0, 0.05, 14.0)

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()

func _run() -> void:
	print("zombiezone hazards")
	print("")
	await _test_acid_on_the_pool()
	await _test_caps_and_trail()
	_test_oil_catalogue()
	await _test_oil_trail()
	await _test_oil_spit()
	await _test_oil_director()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _test_acid_on_the_pool() -> void:
	_section("acid runs on the shared hazard pool")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(SPOT, 0.0)
	var told: Array = []
	game.hazards.area_added.connect(func(id: int, kind: StringName, _at: Vector3, _r: float, _s: float) -> void: told.append([id, kind]))
	var id := game.hazards.add(ZzHazards.ACID, SPOT, 3.0, 6.0, 6.0, 0)
	_check(game.hazards.pool.areas.has(id) and game.hazards.areas.has(id) and told == [[id, ZzHazards.ACID]], "an acid pool lives in the shared pool, is mirrored for the wire and announced once")
	var first := me.health.health
	await _sim(game, 1.0)
	var one := first - me.health.health
	await _sim(game, 1.5)
	var two := first - me.health.health - one
	_check(one > 0.0 and two > one, "it hurts more the longer you stand in it", "%.0f then %.0f" % [one, two])
	me.place_at(SPOT + Vector3(0.0, 0.0, -12.0), 0.0)
	await _sim(game, 0.3)
	var before := me.health.health
	await _sim(game, 1.0)
	_check(is_equal_approx(before, me.health.health), "outside it nothing is paid")
	await _sim(game, 4.0)
	_check(not game.hazards.pool.areas.has(id) and not game.hazards.areas.has(id), "it ends at its lifetime in both")
	_check(game.hazards.pool.slow_of(me.player_id) == 1.0, "acid does not slow")
	_finished()


func _test_caps_and_trail() -> void:
	_section("a configured kind: owner cap, global cap, trail, slow")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(SPOT, 0.0)
	game.hazards.configure(&"goo", {"kind": "goo", "radius": 2.0, "seconds": 20.0, "dps": 8.0, "dps_start": 8.0,
		"ramp_seconds": 0.0, "slow_factor": 0.4, "max_per_owner": 3, "global_cap": 4, "trail_spacing": 2.0, "trail_interval": 0.1})
	var ended: Array = []
	game.hazards.area_ended.connect(func(id: int) -> void: ended.append(id))
	var profile: DotHazardProfile = game.hazards.profiles[&"goo"]
	for i in 5:
		var _p := game.hazards.add(&"goo", SPOT + Vector3(40.0 + 5.0 * float(i), 0.0, 0.0), 2.0, 20.0, -1.0, 77)
	_check(game.hazards.pool.count(&"goo", 77) == 3 and ended.size() == 2, "three per owner; the oldest two ended on the wire too")
	for i in 3:
		var _q := game.hazards.add(&"goo", SPOT + Vector3(-40.0 - 5.0 * float(i), 0.0, 0.0), 2.0, 20.0, -1.0, 78)
	_check(game.hazards.pool.count(&"goo") == 4, "four in all", str(game.hazards.pool.count(&"goo")))
	game.hazards.pool.clear()
	var now: float = game.now()
	var dropped := 0
	for i in 20:
		if game.hazards.pool.trail(profile, 5, SPOT + Vector3(float(i) * 0.5, 0.0, 30.0), now + float(i) * 0.1) != 0:
			dropped += 1
	_check(dropped == 5, "a trail drops every 2 m", str(dropped))
	game.hazards.pool.clear()
	var _at_me := game.hazards.add(&"goo", me.feet(), 2.0, 20.0, -1.0, 0)
	var hp := me.health.health
	await _sim(game, 1.0)
	_check(me.health.health < hp, "standing in goo hurts through the combat manager", "%.0f to %.0f" % [hp, me.health.health])
	_check(is_equal_approx(game.hazards.pool.slow_of(me.player_id), 0.4), "and the pool reports the slow")
	_finished()


func _oil_arena(gap: float, tune: Dictionary = {}) -> Array:
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(SPOT, 0.0)
	var oil := game.horde.spawner.spawn(ZzNpcs.OIL_MONSTER, SPOT + Vector3(0.0, 0.0, gap), &"test")

	for key: String in tune:
		oil.def.meta[key] = tune[key]

	await _sim(game, 0.2)
	return [game, me, oil]


func _test_oil_catalogue() -> void:
	_section("oil monster: catalogued, its keys reach the pools, the wire carries its kinds")
	var def: DotNpcDef = ZzNpcs.builtin(ZzConfig.new()).filter(func(d: DotNpcDef) -> bool: return d.id == ZzNpcs.OIL_MONSTER)[0]
	_check(ZzNpcs.SPECIALS.has(ZzNpcs.OIL_MONSTER) and def.move_speed > 0.0 and def.move_speed < 4.0, "it is a special and slides slowly", "%.1f" % def.move_speed)
	var hazards := ZzHazards.new(null)
	hazards.configure_from_meta(def.meta)
	var goo: DotHazardProfile = hazards.profiles[ZzHazards.GOO]
	var trail: DotHazardProfile = hazards.profiles[ZzHazards.GOO_TRAIL]
	_check(is_equal_approx(goo.dps, 9.0) and is_equal_approx(goo.slow_factor, 0.6) and goo.seconds == 9.0, "goo_* keys reach the spit's puddle profile")
	_check(trail.radius == 1.1 and trail.seconds == 6.0 and trail.max_per_owner == 30 and trail.trail_spacing == 1.4 and trail.kind == &"goo_trail", "trail_* keys reach the trail profile, radius and life included")
	def.meta["trail_spacing"] = 3.0
	def.meta["goo_dps"] = 20.0
	hazards.configure_from_meta(def.meta)
	_check(trail.trail_spacing == 3.0 and goo.dps == 20.0 and trail.dps == 5.0, "a changed key moves only its own pool")
	var r := ZzEvents.read_hazard(DotNetReader.new(ZzEvents.write_hazard(5, ZzHazards.GOO_TRAIL, Vector3(1, 0, 2), 1.1, 6.0)))
	_check(r["ok"] and r["kind"] == ZzHazards.GOO_TRAIL, "a trail puddle's kind survives the wire")
	_finished()


func _test_oil_trail() -> void:
	_section("oil monster: slides toward the survivor and leaves a damaging, slowing trail")
	var a := await _oil_arena(14.0, {"spit_cooldown": 999.0, "spit_range": 0.0})
	var game: ZzGame = a[0]
	var oil: DotNpcInstance = a[2]
	await _sim(game, 5.0)
	var count := game.hazards.pool.count(ZzHazards.GOO_TRAIL)
	_check(count >= 3 and count <= 30, "it leaves trail puddles as it slides", str(count))
	_check(oil.position().distance_to(SPOT) < 14.0, "and it came closer", "%.1f" % oil.position().distance_to(SPOT))
	var any := game.hazards.pool.areas.values().back() as Dictionary
	var me: ZzPlayer = a[1]
	me.place_at((any["at"] as Vector3) + Vector3(0.0, 0.0, 0.1), 0.0)
	var hp := me.health.health
	await _sim(game, 1.5)
	_check(me.health.health < hp, "standing in the trail hurts", "%.0f to %.0f" % [hp, me.health.health])
	_check(game.hazards.slow_of(me.player_id) < 0.99, "the pool reports a slow", "%.2f" % game.hazards.slow_of(me.player_id))
	_check(me.controller.has_modifier(&"zz_goo_slow_2") or me.controller.has_modifier(&"zz_goo_slow_3"), "and slows (the step nearest the puddle's slow factor)")
	_finished()


func _test_oil_spit() -> void:
	_section("oil monster: a spit hurts, blinds the screen, mirrors on the wire and leaves a puddle")
	var a := await _oil_arena(14.0, {"reach": 0.5, "spit_cooldown": 999.0, "spit_windup": 0.1, "trail_spacing": 999.0})
	var game: ZzGame = a[0]
	var me: ZzPlayer = a[1]
	var hp := me.health.health
	await _sim(game, 4.0)
	_check(me.goo_stacks >= 1 and me.goo_until > game.now(), "a glob that lands puts goo on the screen", str(me.goo_stacks))
	_check(me.health.health < hp, "and hurts", "%.0f to %.0f" % [hp, me.health.health])
	_check(game.hazards.pool.count(ZzHazards.GOO) >= 1, "and leaves a puddle on the ground")
	var net = load("res://game/net/zz_player_net.gd").new()
	_check(net != null and (((me.goo_stacks << 3) >> 3) & 3) == me.goo_stacks, "the stacks fit the two bits net_status carries")
	net.free()
	me.goo_until = game.now() - 1.0
	await _sim(game, 0.5)
	_check(me.goo_stacks == 0, "the goo leaves the screen when its time is up")
	_finished()


func _test_oil_director() -> void:
	_section("oil monster: the director picks it by its own chance and first wave")
	var game := await _team(1, _quiet)
	game.config.oil_monster_chance = 1.0
	game.config.oil_monster_min_wave = 0
	var allowed: Array = game.horde._allowed_specials()
	_check(allowed.has(ZzNpcs.OIL_MONSTER), "with chance 1 it is a candidate")
	game.config.oil_monster_chance = 0.0
	_check(not game.horde._allowed_specials().has(ZzNpcs.OIL_MONSTER), "with chance 0 it never is")
	game.config.oil_monster_chance = 1.0
	game.config.oil_monster_min_wave = 50
	_check(not game.horde._allowed_specials().has(ZzNpcs.OIL_MONSTER), "and not before its first wave")
	_finished()


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


static func _quiet(c: ZzConfig) -> void:
	c.wanderer_density = 0.0
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


func _sim(game: ZzGame, seconds: float) -> void:
	var ticks := maxi(int(round(seconds * float(TICK_RATE))), 1)

	for i in ticks:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	await get_tree().physics_frame


func _aim(player: ZzPlayer, target: Vector3) -> void:
	var look := target - player.eye_position()
	var command := DotFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	player.controller.apply_command(command)
	player.controller.state.yaw = command.yaw
	player.controller.state.pitch = command.pitch


func _hurt(game: ZzGame, player: ZzPlayer, amount: float) -> void:
	var hit := DotDamage.make(0, player.entity_id, amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1




func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game


const CLASS_DIR := "user://carry_class_cfg"
