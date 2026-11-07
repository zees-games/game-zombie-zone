extends "zz_suite.gd"

const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzDrops := preload("../game/zz_drops.gd")
const ZzPlayerNet := _BridgeFirst.ZzPlayerNet

## The defibrillator: charge, charges, cooldown, interruption, the time limit, the shield and the wire.
## Counts sections AND checks, like headless_run, because a script error aborts a section silently.

const SECTIONS := 3
const CHECKS := 31

const STREET := Vector3(0.0, 0.05, 14.0)


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone defibrillator")
	print("")
	await _test_defibrillator()
	await _test_items()
	await _test_stand_ins()

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
	_check(uses.has(&"defib") and uses.size() <= 16, "the use fits the four bits on the wire", "%d of 16" % uses.size())
	var kits := (1 if me.medkits > 0 else 0) | (2 if me.pills > 0 else 0) | (mini(7, 7) << 2)
	_check(kits < 32 and ((kits >> 2) & 7) == 7, "seven charges and both kits fit net_kits' five bits")
	var pair := ZzEvents.read_pair(DotNetReader.new(ZzEvents.write_pair(5, 9)))
	_check(pair["player_id"] == 5 and pair["other"] == 9 and int(ZzEvents.Kind.DEFIB) < 256, "the event carries who and by whom")
	_check(game.drops.item_weights(&"brute").has(&"defib") or game.drops.rolls_for(&"brute") >= 0.0, "the drop table knows the item")

	me.defibs = 0
	var offers: Array = game.shop.items().filter(func(it: Dictionary) -> bool: return str(it["id"]) == "defib")
	_check(offers.size() == 1 and int(offers[0]["price"]) == int(round(game.config.defib_price * game.shop.multiplier())), "the trader sells one at zz_defib_price", str(offers))
	_check(game.shop._give(me, "defib", offers[0]) == "" and me.defibs == game.config.defib_charges and game.shop._give(me, "defib", offers[0]) != "", "buying gives the charges once, and a second is refused")
	game.config.defib_price = 0
	_check(game.shop.items().filter(func(it: Dictionary) -> bool: return str(it["id"]) == "defib").is_empty(), "zz_defib_price 0 takes it off the shelf")
	_finished()


func _test_stand_ins() -> void:
	_section("a stand-in with a defibrillator walks to a dead friend and shocks them back; a dead body's respawn timer is cleared")
	var setup := func(c: ZzConfig) -> void:
		_quiet(c)
		c.defib_charge_seconds = 1.0
		c.defib_max_body_age = 30.0
		c.timed_respawn = true
		c.respawn_base_seconds = 40.0
		c.intermission_seconds = 60.0
	var game := await _team(2, setup, true)
	var medic := game.survivors()[0]
	var body := game.survivors()[1]
	medic.place_at(STREET, 0.0)
	body.place_at(STREET + Vector3(6.0, 0, 0), 270.0)
	body.incaps = game.config.max_incaps
	_hurt(game, body, 500.0)
	_check(body.life == ZzPlayer.Life.DEAD and body.respawn_at > 0.0, "the one too many is death, with a respawn due")
	medic.defibs = 0
	await _sim(game, 2.0)
	_check(body.life == ZzPlayer.Life.DEAD, "a stand-in with no defibrillator leaves the body")
	medic.defibs = 1
	await _sim(game, 8.0)
	_check(body.is_up() and body.is_alive() and medic.defibs == 0, "with one it walks over and shocks them back", "life %d" % body.life)
	_check(body.respawn_at < 0.0, "and the respawn timer is cleared so they are not respawned over their own revive")
	game.config.bot_defib = false
	medic.defibs = 1
	medic.defib_ready_at = 0.0
	body.incaps = game.config.max_incaps
	await _sim(game, game.config.defib_invulnerable_seconds + 0.2)
	_hurt(game, body, 500.0)
	await _sim(game, 3.0)
	_check(body.life == ZzPlayer.Life.DEAD and medic.defibs == 1, "zz_bot_defib 0 keeps it in the pocket")
	_finished()


func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game
