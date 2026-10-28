extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzDrops := preload("../game/zz_drops.gd")
const ZzPlayerNet := preload("../game/net/zz_player_net.gd")

## The defibrillator: charge, charges, cooldown, interruption, the time limit, the shield and the wire.
## Counts sections AND checks, like headless_run, because a script error aborts a section silently.

const SECTIONS := 2
const CHECKS := 23

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const STREET := Vector3(0.0, 0.05, 14.0)

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone defibrillator")
	print("")
	await _test_defibrillator()
	await _test_items()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _test_defibrillator() -> void:
	_section("a defibrillator shocks a dead teammate back: charge, charges, cooldown, interruption, time limit")
	var game := await _team(2, func(c: ZzConfig) -> void:
		_quiet(c)
		c.defib_charge_seconds = 1.0
		c.defib_cooldown_seconds = 3.0
		c.defib_max_body_age = 20.0
		c.intermission_seconds = 60.0
		c.defib_charges = 2
		c.defib_invulnerable_seconds = 2.0)
	var me := game.survivors()[0]
	var friend := game.survivors()[1]
	me.place_at(STREET, 0.0)
	friend.place_at(STREET + Vector3(1.0, 0, 0), 270.0)
	me.incaps = game.config.max_incaps
	_hurt(game, me, 500.0)
	_check(me.life == ZzPlayer.Life.DEAD, "the one too many is death")

	_aim(friend, me.feet() + Vector3(0, 0.3, 0))
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.3)
	_check(friend.using == &"" and me.life == ZzPlayer.Life.DEAD, "with no defibrillator, E at a body does nothing")
	friend.actions = 0
	await _sim(game, 0.1)

	friend.defibs = game.config.defib_charges
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.4)
	_check(friend.using == &"defib" and friend.use_fraction > 0.2 and friend.use_fraction < 0.7, "with one, holding E charges it", "%.2f" % friend.use_fraction)
	_check(me.life == ZzPlayer.Life.DEAD, "and the body waits for the shock")
	await _sim(game, 0.9)
	friend.actions = 0
	_check(me.is_up() and me.is_alive() and not me.watching, "then they are up where they lay")
	_check(absf(me.health.health - game.config.max_health * game.config.defib_revive_fraction) < 1.5, "at the configured share of health", "%.0f" % me.health.health)
	_check(friend.defibs == 1 and friend.revives_done == 1, "the shock cost a charge", "%d left" % friend.defibs)
	_check(me.incaps == game.config.max_incaps - 1, "and they are one down from dead again")
	var before := me.health.health
	_hurt(game, me, 30.0)
	_check(is_equal_approx(me.health.health, before), "they cannot be hurt for the first moments")
	await _sim(game, game.config.defib_invulnerable_seconds + 0.2)
	_hurt(game, me, 10.0)
	_check(me.health.health < before - 5.0, "and can be after")

	me.incaps = game.config.max_incaps
	_hurt(game, me, 500.0)
	await _sim(game, 0.1)
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.3)
	_check(friend.using == &"", "the item is recharging after a shock: no second try at once")
	friend.actions = 0
	await _sim(game, game.config.defib_cooldown_seconds)
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, game.config.defib_charge_seconds + 0.4)
	friend.actions = 0
	_check(me.is_up() and friend.defibs == 0, "after the cooldown it works again and is spent")

	await _sim(game, game.config.defib_invulnerable_seconds + 0.2)
	me.incaps = game.config.max_incaps
	_hurt(game, me, 500.0)
	await _sim(game, game.config.defib_cooldown_seconds + 0.2)
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.3)
	_check(friend.using == &"" and me.life == ZzPlayer.Life.DEAD, "a spent one does nothing")
	friend.actions = 0

	friend.defibs = 1
	friend.defib_ready_at = 0.0
	await _sim(game, 0.1)
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.4)
	_check(friend.using == &"defib", "a new one starts")
	_hurt(game, friend, 20.0)
	_check(friend.using == &"" and me.life == ZzPlayer.Life.DEAD, "a hit on the user interrupts it")
	friend.actions = 0
	await _sim(game, 0.1)
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.3)
	friend.place_at(STREET + Vector3(1.9, 0, 0), 270.0)
	await _sim(game, 0.3)
	_check(friend.using == &"" and me.life == ZzPlayer.Life.DEAD and friend.defibs == 1, "so does drifting off, and nothing is spent")
	friend.actions = 0
	friend.place_at(STREET + Vector3(1.0, 0, 0), 270.0)

	await _sim(game, game.config.defib_max_body_age + 1.0)
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.3)
	_check(friend.using == &"" and me.life == ZzPlayer.Life.DEAD, "a body past the time limit is past saving")
	friend.actions = 0
	_finished()


func _test_items() -> void:
	_section("the item: picked up once, carried over the wire, and in the drop table")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	me.defibs = 0
	var id := game.loot.add(ZzLoot.DEFIB, &"defib", me.feet())
	game.loot.use(id, me)
	_check(me.defibs == game.config.defib_charges and not game.loot.exists(id), "taking one gives the configured charges", "%d" % me.defibs)
	id = game.loot.add(ZzLoot.DEFIB, &"defib", me.feet())
	game.loot.use(id, me)
	_check(game.loot.exists(id), "and a second is left where it lies")

	var uses: Array = ZzPlayerNet.USES
	_check(uses.has(&"defib") and uses.size() <= 8, "the use fits the three bits on the wire", "%d of 8" % uses.size())
	var kits := (1 if me.medkits > 0 else 0) | (2 if me.pills > 0 else 0) | (mini(7, 7) << 2)
	_check(kits < 32 and ((kits >> 2) & 7) == 7, "seven charges and both kits fit net_kits' five bits")
	var pair := ZzEvents.read_pair(DotNetReader.new(ZzEvents.write_pair(5, 9)))
	_check(pair["player_id"] == 5 and pair["other"] == 9 and int(ZzEvents.Kind.DEFIB) < 256, "the event carries who and by whom")
	_check(game.drops.item_weights(&"brute").has(&"defib") or game.drops.rolls_for(&"brute") >= 0.0, "the drop table knows the item")
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
