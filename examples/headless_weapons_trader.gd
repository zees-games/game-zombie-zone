extends DotGameCheckSuite

const ZzClient := preload("../game/zz_client.gd")
const ZzHud := preload("../game/zz_hud.gd")

## The weapons suite's lower layer: its counters, the client under test and the trader and shop sections.

var _sections_entered := 0
var _sections_finished := 0
var _client: ZzClient = null


func _frames(count: int) -> void:
	for _i in range(maxi(count, 0)):
		await get_tree().physics_frame
	# The HUD draws on a render frame.
	await get_tree().process_frame


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _shelf_count(game) -> int:
	var n := 0
	for id: int in game.loot.entries:
		if game.loot.price_of(id) > 0:
			n += 1
	return n


func _test_shop() -> void:
	_section("the trader's menu: the catalogue, reach, the price multiplier, a purchase, the window")
	var game = _client.game
	var me := _client.player
	var cfg = game.config
	game.grace.clear()
	cfg.trader_enabled = -1
	cfg.trader_when = -1
	game._set_phase(game.Phase.READY)
	game.spawners.start_round({"id": "shop_probe", "traders": [{"id": "own", "at": [0, 0, 8], "slots": 2}]})
	var cats := {}
	for it: Dictionary in game.shop.items():
		cats[str(it["cat"])] = true
	_check(cats.has("weapons") and cats.has("grenades") and cats.has("ammo") and cats.has("supplies"), "the list has weapons, grenades, ammo and supplies", str(cats.keys()))

	me.place_at(Vector3(0.0, 0.0, 8.0) + Vector3(20.0, 0.0, 0.0), 0.0)
	me.points = 10000
	_check(not game.shop.in_reach(me) and not game.shop.buy(me, "armour"), "out of reach nothing is sold")
	me.place_at(game.spawners.trader_positions()[0], 0.0)
	_check(game.shop.in_reach(me), "beside the trader it is in reach")

	var armour := -1
	for it: Dictionary in game.shop.items():
		if str(it["id"]) == "armour":
			armour = int(it["price"])
	me.health.armour = 0.0
	var before: int = me.points
	_check(game.shop.buy(me, "armour") and me.points == before - armour and me.health.armour > 0.0, "a purchase deducts the price and hands the item over", "%d -> %d" % [before, me.points])
	me.points = 1
	_check(not game.shop.buy(me, "heal") and me.points == 1, "too few points buys nothing")

	game.spawners.shop_block()["price_multiplier"] = 2.0
	var doubled := -1
	for it: Dictionary in game.shop.items():
		if str(it["id"]) == "armour":
			doubled = int(it["price"])
	game.spawners.shop_block().erase("price_multiplier")
	_check(doubled == armour * 2, "the global multiplier scales prices", "%d vs %d" % [doubled, armour])
	game.spawners.shop_block()["disabled"] = ["armour"]
	var listed := false
	for it: Dictionary in game.shop.items():
		listed = listed or str(it["id"]) == "armour"
	game.spawners.shop_block().erase("disabled")
	_check(not listed, "a disabled item is not listed")

	cfg.trader_when = 0
	game._set_phase(game.Phase.PLAY)
	game.spawners.tick()
	me.points = 10000
	me.health.armour = 0.0
	_check(not game.shop.in_reach(me) and not game.shop.buy(me, "armour"), "when the wave begins the trader is gone and sells nothing")
	cfg.trader_when = -1
	game._set_phase(game.Phase.READY)
	game.spawners.start_round({"id": "spawner_probe"})
	_finished()


func _test_trader_phases_and_grace() -> void:
	_section("the trader per phase, and the start grace: no zombies until it ends")
	var game = _client.game
	var cfg = game.config
	var sp = game.spawners
	var me := _client.player
	cfg.trader_enabled = -1
	cfg.trader_when = -1
	cfg.trader_setup = -1
	cfg.trader_grace = -1
	cfg.trader_breather = -1
	cfg.trader_round = -1
	cfg.grace_maps = 2
	cfg.escape_grace_seconds = 5.0
	game.grace.clear()
	game._set_phase(game.Phase.READY)
	sp.start_round({"id": "grace_probe", "traders": [{"id": "own", "at": [0, 0, 8], "slots": 2}]})
	sp.tick()
	_check(sp.trader_window() == &"setup" and sp.trader_open(), "before the map starts the trader is open")

	game.horde.stop_pacing()
	game._begin_play()
	sp.tick()
	_check(game.grace.is_active() and sp.trader_window() == &"grace" and sp.trader_open(), "in the grace it is open")
	_check(not game.horde.pacing and game.horde.spawner.all_npcs().is_empty(), "and no zombie exists or is paced")
	var st := ZzHud.streak_step(0, -1, 0.0, 5, 1.0)
	st = ZzHud.streak_step(st[0], st[1], st[2], 7, 3.0)
	_check(st[0] == 2, "two kills in a window make a streak of 2", str(st))
	st = ZzHud.streak_step(st[0], st[1], st[2], 8, 20.0)
	_check(st[0] == 1, "a kill after the window starts over", str(st))
	st = ZzHud.streak_step(st[0], st[1], st[2], 8, 30.0)
	_check(st[0] == 0, "a quiet window ends the streak", str(st))
	_check(game.grace_left_for_hud() > 4.0 and ZzHud.grace_line(23.0) == "Zombies arrive in 0:23", "the HUD counts down", ZzHud.grace_line(23.0))
	cfg.grace_hud = 0
	_check(game.grace_left_for_hud() == 0.0, "zz_grace_hud 0 hides the countdown")
	cfg.grace_hud = 1

	for i in 4:
		game._advance_phase(1.0)
	game.horde.tick(0.1)
	var targeted := false
	for sid: StringName in game.horde._survivors:
		targeted = targeted or bool(game.horde._survivors[sid]["alive"])
	_check(game.grace.is_active() and not game.horde.pacing and game.horde.spawner.all_npcs().is_empty() and not targeted, "four seconds in, still none, and nobody is a target")
	cfg.trader_grace = 0
	sp.tick()
	_check(not sp.trader_open() and sp.closed_message() == "Trader closed: round in progress", "zz_trader_grace 0 closes it, with the sentence")
	cfg.trader_grace = -1

	game._advance_phase(1.5)
	sp.tick()
	_check(not game.grace.is_active() and game.horde.pacing, "the grace ends and the pacing starts")
	var spawned := 0
	for i in 600:
		game.horde.tick(0.1)
	spawned = game.horde.spawner.all_npcs().size()
	_check(spawned > 0 or game.horde.director.spawn_points.is_empty(), "and zombies spawn after it", "%d" % spawned)
	_check(sp.trader_window() == &"round" and not sp.trader_open(), "then the trader closes for the round")
	me.points = 10000
	me.place_at(sp.trader_sites()[0], 0.0)
	_check(not game.shop.buy(me, "armour"), "and sells nothing")
	cfg.trader_round = 1
	sp.tick()
	_check(sp.trader_open(), "zz_trader_during_round: zz_trader_round 1 keeps it open")
	cfg.trader_round = -1
	cfg.trader_setup = 0
	game._set_phase(game.Phase.READY)
	sp.tick()
	_check(not sp.trader_open(), "zz_trader_setup 0 closes it before the start")
	cfg.trader_setup = -1

	_check_grace_maps(game, cfg)
	game.horde.stop_pacing()
	game.grace.clear()
	cfg.grace_maps = 1
	cfg.escape_grace_seconds = 30.0
	game._set_phase(game.Phase.READY)
	sp.start_round({"id": "spawner_probe"})
	_finished()


## zz_grace_maps: none, escape maps only, and the shipped grace.
func _check_grace_maps(game: Variant, cfg: Variant) -> void:
	cfg.grace_maps = 0
	game.grace.clear()
	game._set_phase(game.Phase.READY)
	game._begin_play()
	_check(not game.grace.is_active() and game.horde.pacing, "zz_grace_maps 0: no grace, the horde runs at once")
	cfg.grace_maps = 1
	_check(game.grace_seconds_for_map() == (0.0 if game.is_survival() else 5.0), "zz_grace_maps 1: escape maps only")
	cfg.grace_maps = 1
	cfg.escape_grace_seconds = 30.0
	_check(game.grace_seconds_for_map() == (0.0 if game.is_survival() else 30.0), "the shipped grace is 30 s")


func _test_trader() -> void:
	_section("the startup trader: present in the setup period, per config after it, starting points, a purchase")
	var game = _client.game
	var me := _client.player
	var cfg = game.config
	game.grace.clear()
	cfg.trader_enabled = -1
	cfg.trader_when = -1
	cfg.trader_despawn = -1
	cfg.start_points = -1
	var doc := {"id": "trader_probe", "traders": [{"id": "own", "at": [0, 0, 8], "slots": 3}]}

	game._set_phase(game.Phase.READY)
	game.spawners.start_round(doc)
	_check(_shelf_count(game) == 3, "a map's own trader stands during setup", str(_shelf_count(game)))
	game.spawners.start_round({"id": "trader_probe2"})
	_check(_shelf_count(game) == 4 and game.spawners._traders.has(&"trader_start"), "a map with none gets one by the survivor spawn", str(_shelf_count(game)))

	cfg.start_points = 120
	me.points = 20
	game.spawners.grant_start_points()
	_check(me.points == 120, "starting points top a survivor up", str(me.points))
	me.points = 500
	game.spawners.grant_start_points()
	_check(me.points == 500, "and keep a higher balance", str(me.points))
	cfg.start_points = -1
	cfg.difficulty = 0
	var easy: int = game.spawners.start_points()
	cfg.difficulty = 3
	_check(easy > game.spawners.start_points(), "the file's starting points differ by difficulty", "%d easy, %d expert" % [easy, game.spawners.start_points()])
	cfg.difficulty = 1

	var shelf_id := -1
	for id: int in game.loot.entries:
		if game.loot.price_of(id) > 0:
			shelf_id = id
	var price: int = game.loot.price_of(shelf_id)
	me.points = price + 7
	_check(game.spawners.may_use(shelf_id, me), "an affordable item may be used")
	game.loot.use(shelf_id, me)
	_check(me.points == 7 and _shelf_count(game) == 3, "a purchase deducts the price and the shelf loses the item", str(me.points))

	game.spawners.start_round(doc)
	cfg.trader_when = 0
	game._set_phase(game.Phase.PLAY)
	game.spawners.tick()
	_check(_shelf_count(game) == 0 and not game.spawners.trader_open(), "setup only: the shelf is gone once the horde runs")
	game._set_phase(game.Phase.READY)
	game.spawners.tick()
	_check(_shelf_count(game) == 3, "and stands again in the next setup", str(_shelf_count(game)))

	cfg.trader_despawn = 0
	game._set_phase(game.Phase.PLAY)
	game.spawners.tick()
	var kept := _shelf_count(game)
	var stocked: int = 0
	for id: int in game.loot.entries:
		if game.loot.price_of(id) > 0:
			stocked = id
	me.points = 100000
	_check(kept == 3 and not game.spawners.may_use(stocked, me), "despawn off: the shelf stays but will not sell", str(kept))
	cfg.trader_despawn = -1

	cfg.trader_when = 2
	game.spawners.tick()
	_check(game.spawners.trader_open() and _shelf_count(game) == 3, "always: it sells while the horde runs", str(_shelf_count(game)))

	cfg.trader_enabled = 0
	game.spawners.start_round(doc)
	_check(_shelf_count(game) == 0, "disabled: no trader on any map")
	cfg.trader_enabled = -1
	cfg.trader_when = -1
	game._set_phase(game.Phase.READY)
	game.spawners.start_round({"id": "spawner_probe"})
	_finished()


func _finished() -> void:
	_sections_finished += 1
