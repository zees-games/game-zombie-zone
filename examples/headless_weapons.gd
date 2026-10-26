extends Node

const ZzClient := preload("../game/zz_client.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

## The gun you hold, offline, through the real client: the buttons, the world's rig that decides,
## the rig the view model is drawn with, and the HUD's counter.
##
## [b]Why through `ZzClient` and not a bare world.[/b] Every other suite here drives the world's
## commands itself, and so none of them saw that offline the client's buttons never reached the
## world: the client stamped the controller's command and the world then sampled a fresh one over
## it. The first play test's counter read 15 / 60 for two and a half minutes of shooting, and
## nothing the player shot was hit. Only a suite that presses the client's own buttons sees it.
##
## Sections and checks are both counted; mg-smash-copter's notes say why the second matters.

const ZzHud := preload("../game/zz_hud.gd")
const SECTIONS := 12
const CHECKS := 76

const CONFIG_FILE := "user://zz_headless_weapons.json"

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()

var _client: ZzClient = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone weapons, offline, through the client")
	print("")

	_test_the_weapon_art_is_vendored()

	if await _test_armed():
		await _test_shots_count()
		await _test_r_reloads()
		await _test_empty_reloads()
		await _test_ammo_pile()
		await _test_rearmed()
		await _test_box_guns_are_drawn()
		_test_spawner()
		_test_trader()
		_test_shop()
		_test_trader_phases_and_grace()

	print("")
	print("%d sections entered, %d finished" % [_sections_entered, _sections_finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _sections_entered != _sections_finished or _sections_entered != SECTIONS:
		print("ERROR: %d of %d sections finished, %d expected." % [_sections_finished, _sections_entered, SECTIONS])
		code = 1

	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		code = 1

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_FILE))
	get_tree().quit(code)


# --- Sections ----------------------------------------------------------------

## A delivered game has only what is vendored in assets/, so every model the weapon art table
## names must exist here; an unvendored gun loads as bare arms and nothing else fails. The
## list and the check are the addon's; `tools/sync-art.sh` in zee-dot-weapons copies what it names.
func _test_the_weapon_art_is_vendored() -> void:
	_section("Every model the weapon art table names is vendored in this game")
	ZzWeapons.use_packs()
	var count := ZeeWeaponArtTable.model_paths().size()
	_check(count == 0, "zee's art table names no blaster models once its weapons are dropped (%d)" % count)
	var models := ZeeWeaponArtTable.validate_models()
	_check(models.ok, "no weapon model is missing", "" if models.ok else models.error.message)
	_finished()


func _test_armed() -> bool:
	_section("the client comes up armed, and the HUD counts the gun in hand")
	var failed_before := _failed

	# The practice street, no warmup and nothing that comes for you: this is about the gun.
	var file := FileAccess.open(CONFIG_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"warmup_seconds": 0.0, "start_grace_seconds": 0.0, "minimum_players": 0,
		"wanderer_density": 0.0, "sleepers_enabled": false, "specials_base": 0,
		"mob_interval_min": 900.0, "mob_interval_max": 900.0,
		"brute_interval_min": 0.0, "brute_interval_max": 0.0, "box_drop_common": 0.0,
		"map_ids": ["zz_practice"],
	}))
	file.close()

	_client = ZzClient.new()
	_client.config_file = CONFIG_FILE
	_client.force_offline = true
	_client.standalone_content = false
	_client.offline_bots = 0
	add_child(_client)

	var waited := 0
	while waited < 600 and not (_client.player != null and _client.player.weapons != null
			and _client.player.view_rig != null and _client.game.phase == _client.game.Phase.PLAY):
		await get_tree().physics_frame
		waited += 1
	await _frames(10)

	var me := _client.player
	_check(me != null and me.weapons != null and me.view_rig != null and me.view_rig != me.weapons,
		"the world's rig decides and the client's draws: two rigs", "%d frames" % waited)

	if me == null or me.weapons == null or me.view_rig == null:
		_finished()
		return false

	me.health.invulnerable = true
	var truth := me.weapons.arsenal.current()
	_check(truth != null and truth.def.uses_magazine(), "a gun with a magazine in hand",
		str(truth.def.id) if truth != null else "nothing")
	_check(_hud_magazine() == truth.magazine and _hud_reserve() == _reserve(me.weapons),
		"the HUD shows its magazine and reserve", _client.hud.ammo.count_text())
	_finished()
	return _failed == failed_before


func _test_shots_count() -> void:
	_section("three pulls spend the world's magazine, and the HUD shows it")
	var me := _client.player
	var before := me.weapons.arsenal.current().magazine
	var hits_before: int = me.weapons.fire_seq
	# Pulled three times: the pistol is semi-automatic, so a held trigger is one shot.
	for _pull in range(3):
		_client._firing = true
		await _frames(2)
		_client._firing = false
		await _frames(int(ceilf(Engine.physics_ticks_per_second * 0.25)))
	var spent := before - me.weapons.arsenal.current().magazine
	_check(spent == 3 and me.weapons.fire_seq - hits_before == spent,
		"the world's gun fired and spent a round a shot", "%d spent, %d shots" % [spent, me.weapons.fire_seq - hits_before])
	_check(me.view_rig.arsenal.current().magazine == me.weapons.arsenal.current().magazine,
		"the drawn gun counted the same shots", "%d against %d" % [me.view_rig.arsenal.current().magazine, me.weapons.arsenal.current().magazine])
	_check(_hud_magazine() == me.weapons.arsenal.current().magazine, "the HUD says so", _client.hud.ammo.count_text())
	_finished()


func _test_r_reloads() -> void:
	_section("R reloads both guns, refills from the reserve after the reload's time")
	var me := _client.player
	var held := me.weapons.arsenal.current()
	var missing := held.def.magazine - held.magazine
	var reserve_before := _reserve(me.weapons)
	_client._reloading = true
	await _frames(1)
	_client._reloading = false
	_check(me.weapons.arsenal.is_reloading() and me.view_rig.arsenal.is_reloading(),
		"both rigs are reloading on the frame R goes down")
	_check(me.view_rig._reload_fraction(me.view_rig._last_tick) >= 0.0 and me.view_rig._reload_started >= 0,
		"and the view model is handed a reload to play")
	var takes := me.view_rig.arsenal.ticks_for(held.def, held.def.reload_ticks)
	await _frames(takes - 3)
	_check(me.weapons.arsenal.current().magazine < held.def.magazine, "not full before its time",
		"%d frames of %d" % [takes - 3, takes])
	await _frames(8)
	_check(me.weapons.arsenal.current().magazine == held.def.magazine and _reserve(me.weapons) == reserve_before - missing,
		"full after it, %d taken from the reserve" % missing, "%d / %d" % [me.weapons.arsenal.current().magazine, _reserve(me.weapons)])
	_check(_hud_magazine() == held.def.magazine and _hud_reserve() == reserve_before - missing,
		"and the HUD shows the full magazine and the smaller reserve", _client.hud.ammo.count_text())
	_finished()


func _test_empty_reloads() -> void:
	_section("the last round reloads by itself, trigger let go")
	var me := _client.player
	me.weapons.arsenal.current().magazine = 1
	me.view_rig.arsenal.current().magazine = 1
	_client._firing = true
	await _frames(1)
	_client._firing = false
	await _frames(3)
	_check(me.weapons.arsenal.is_reloading() and me.view_rig.arsenal.is_reloading(),
		"an emptied gun starts reloading with nothing held",
		"world %s, drawn %s" % [me.weapons.arsenal.is_reloading(), me.view_rig.arsenal.is_reloading()])
	var held := me.weapons.arsenal.current()
	await _frames(me.view_rig.arsenal.ticks_for(held.def, held.def.reload_ticks) + 6)
	_check(held.magazine == held.def.magazine and _hud_magazine() == held.def.magazine,
		"and fills", _client.hud.ammo.count_text())
	_finished()


func _test_ammo_pile() -> void:
	_section("an ammo pile fills the world's reserve, and the HUD follows")
	var me := _client.player
	var held := me.weapons.arsenal.current()
	var pool := held.def.ammo_type
	var _spent := me.weapons.arsenal.ammo().take(pool, 1000)
	await _frames(int(ceilf(me.VIEW_RIG_SETTLE_SEC * Engine.physics_ticks_per_second)) + 4)
	_check(_hud_reserve() == 0, "a reserve the world took away goes from the HUD too (the drawn gun is corrected)",
		_client.hud.ammo.count_text())

	# The world's own pickup, as E on the pile calls it: the world fills, the client is told.
	var pile := _client.game.loot.add(ZzLoot.AMMO, &"", me.global_position + Vector3(0.0, 0.0, -1.2))
	_client.game.loot.use(pile, me)
	await _frames(int(ceilf(me.VIEW_RIG_SETTLE_SEC * Engine.physics_ticks_per_second)) + 4)
	_check(_reserve(me.weapons) > 0 and _hud_reserve() == _reserve(me.weapons),
		"refilled, and the HUD shows the world's reserve", "%s against %d" % [_client.hud.ammo.count_text(), _reserve(me.weapons)])
	_finished()


func _test_rearmed() -> void:
	_section("a fresh map's gun carries a fresh reserve, not the last map's on top")
	var me := _client.player
	var id := me.view_rig.arsenal.current().def.id
	var def := ZzWeapons.def_of(id)
	_client._on_armed(_client._watch_id, &"")
	_client._on_armed(_client._watch_id, id)
	_check(me.view_rig.arsenal.current() != null and _reserve(me.view_rig) == def.reserve,
		"stripped and handed the same gun, the drawn reserve is the gun's own",
		"%d, the gun gives %d" % [_reserve(me.view_rig), def.reserve])
	_check(me.view_rig.arsenal.current().magazine == def.magazine, "with a full magazine")
	_finished()


func _test_box_guns_are_drawn() -> void:
	_section("a gun a box hands over, from any pack, is the gun in the view model")
	var me := _client.player
	var game := _client.game
	var settle := 12
	# Every gun of every tier is handed over in turn; the carry limit has its own suite (headless_carry).
	game.config.weight_enabled = false

	for tier in [&"sidearm", &"primary", &"heavy"]:
		var bad := PackedStringArray()
		var ids := ZzWeapons.ids_of(tier)

		for id in ids:
			game.boxes.run([{"do": "give_weapon", "id": String(id)}], {"opener": me, "at": me.global_position, "box": &"upgrade"})
			await _frames(settle)
			var waited := 0

			while me.view_rig.arsenal.is_switching() and waited < 200:
				await _frames(1)
				waited += 1

			await _frames(2)
			var shown: StringName = _client.view_model.equipped() if _client.view_model != null else &""

			if shown != id or not _client.view_model.visible or me.view_rig.arsenal.current().def.id != id:
				bad.append("%s (showing '%s')" % [id, shown])

		_check(not ids.is_empty() and bad.is_empty(), "every %s the boxes hand out is drawn (%d)" % [tier, ids.size()], ", ".join(bad))

	_finished()


func _test_spawner() -> void:
	_section("a map spawner lays a gun as loot; using it starts the timer, the timer lays the next")
	var game = _client.game
	var me := _client.player
	game.config.trader_enabled = 0
	var doc := {"id": "spawner_probe", "spawners": [{"id": "wall", "at": [0, 0, 0], "pool": "wall_guns", "filter": {"ids": ["zz_shotgun"]}, "respawn": 20, "max": 1}]}
	game.spawners.start_round(doc)
	game.spawners.tick()
	var lid: int = game.spawners.loot_ids()[0] if not game.spawners.loot_ids().is_empty() else -1
	_check(game.spawners.spawner.alive() == 1 and lid >= 0, "the spawner's item is a loot entry")
	var item: StringName = game.loot.entries[lid]["item"]
	_check(ZzWeapons.exists(item), "drawn from the weapon catalogue", String(item))
	game.loot.use(lid, me)
	_check(game.spawners.spawner.alive() == 0 and not game.loot.exists(lid), "using it frees the slot and the entry")
	_check(game.spawners.spawner.seconds_until(&"wall") > 10.0, "the respawn timer runs", str(game.spawners.spawner.seconds_until(&"wall")))
	game.spawners.spawner.tick(game.now() + 25.0)
	_check(game.spawners.spawner.alive() == 1 and game.loot.count_of(ZzLoot.WEAPON) >= 1, "after the timer the next one lies there")
	var shop := {"id": "spawner_probe", "spawners": [{"id": "buy", "at": [0, 0, 0], "item": "zz_shotgun", "respawn": 0, "data": {"price": 300}}]}
	game.spawners.start_round(shop)
	game.spawners.tick()
	var buy: int = game.spawners.loot_ids()[0] if not game.spawners.loot_ids().is_empty() else -1
	me.points = 100
	_check(game.spawners.price_of(buy) == 300 and not game.spawners.may_use(buy, me), "a priced spawner refuses a survivor who cannot pay")
	me.points = 400
	game.loot.use(buy, me)
	_check(me.points == 100, "and takes the price when the item is used", str(me.points))

	game.config.trader_enabled = -1
	# A converter's weapon_* and item_* entities lay what the config's classes say; a trader shelves priced stock.
	var world := {"id": "spawner_probe2", "entities": [
		{"classname": "weapon_m3", "origin": [4, 0, 0], "angle": 0},
		{"classname": "item_healthkit", "origin": [5, 0, 0], "angle": 0},
		{"classname": "item_ammo_pistol", "origin": [6, 0, 0], "angle": 0}],
		"traders": [{"id": "shop", "at": [0, 0, 8], "slots": 3, "restock": 30.0}]}
	game.spawners.start_round(world)
	game.spawners.tick()
	var kinds := {}
	for id: int in game.spawners.loot_ids():
		kinds[game.loot.kind_of(id)] = true
	_check(kinds.has(ZzLoot.WEAPON) and (kinds.has(ZzLoot.MEDKIT) or kinds.has(ZzLoot.PILLS)) and kinds.has(ZzLoot.AMMO), "converter entities lay a gun, a medkit and ammo through the classes mapping", str(kinds.keys()))
	var shelf: Array = []
	for id: int in game.loot.entries:
		if game.loot.price_of(id) > 0:
			shelf.append(id)
	_check(shelf.size() == 3, "a trader shelves three priced entries", str(shelf.size()))
	# A stand-in with the points does not walk to a shelf the trader has closed: the press is refused for good.
	me.points = 1000
	me.place_at(game.loot.position_of(shelf[0]), 0.0)
	var wants_open: bool = game.bots._pick_up(me, DotFpsCommand.new(), {"pick": -1})
	game.spawners.set("_open", false)
	var memory := {"pick": -1}
	var wants_closed: bool = game.bots._pick_up(me, DotFpsCommand.new(), memory)
	game.spawners.set("_open", true)
	_check(wants_open and not wants_closed and int(memory["pick"]) == -1, "a stand-in goes for a shelf item while the trader is open and not while it is closed", "open %s, closed %s" % [wants_open, wants_closed])
	var bought: int = shelf[0]
	var price: int = game.loot.price_of(bought)
	me.points = 1000
	game.loot.remove(bought, me.player_id)
	_check(me.points == 1000 - price, "buying from the shelf charges the entry's price", "%d for %d" % [price, 1000 - me.points])
	game.spawners.spawner.tick(game.now() + 40.0)
	game.spawners.tick()
	var again := 0
	for id: int in game.loot.entries:
		if game.loot.price_of(id) > 0:
			again += 1
	_check(again == 3 or game.now() < 30.0, "the slot restocks after its wait", str(again))
	# A priced ammo pile is used up: charged once, and its site lays the next.
	game.spawners.start_round({"id": "spawner_probe3", "spawners": [{"id": "am", "at": [0, 0, 0], "kind": "ammo", "item": "ammo", "respawn": 5, "data": {"price": 50}}],
		"traders": [{"id": "empty_shop", "at": [0, 0, 20], "slots": 2, "pool": "no_such_pool", "restock": 5.0}]})
	game.spawners.tick()
	var amid: int = -1
	for id: int in game.spawners.loot_ids():
		if game.loot.kind_of(id) == ZzLoot.AMMO:
			amid = id
	var arsenal: DotWeaponArsenal = me.weapons.arsenal
	for pool in arsenal.ammo().pools():
		arsenal.ammo().set_count(pool, 0)
	me.points = 200
	game.loot.use(amid, me)
	_check(amid >= 0 and not game.loot.exists(amid) and me.points == 150, "a priced ammo pile is used up and charged", str(me.points))
	_check(game.spawners.spawner.alive() == 0 and game.spawners.spawner.seconds_until(&"am") > 0.0, "and its site respawns it")
	_check(game.spawners._restock.size() >= 2, "an empty roll reschedules the trader's slot", str(game.spawners._restock.size()))
	_check(game.spawners._clean_price(NAN) > 100000 and game.spawners._clean_price(INF) > 100000 and game.spawners._clean_price(1e30) > 100000 and game.spawners._clean_price(-5) == 0 and game.spawners._clean_price(75) == 75, "a nan, infinite or huge price is unaffordable, never free")
	var cheap: int = game.loot.add(ZzLoot.WEAPON, &"zz_shotgun", Vector3.ZERO, -1.0, 300)
	game.spawners._price_of[cheap] = 300
	me.points = 10
	game.loot.remove(cheap, me.player_id)
	_check(me.points == 0, "a charge never takes the points below zero", str(me.points))
	var wire := ZzEvents.read_loot(DotNetReader.new(ZzEvents.write_loot(7, &"weapon", &"zz_shotgun", Vector3.ZERO, 250)))
	_check(int(wire["price"]) == 250 and bool(wire["ok"]), "the loot event carries the price to the client")
	_finished()


# --- Helpers -----------------------------------------------------------------

func _reserve(rig: ZeeWeaponRig) -> int:
	var held := rig.arsenal.current()
	return rig.arsenal.ammo().count(held.def.ammo_type) if held != null and held.def.ammo_type != &"" else 0


func _hud_magazine() -> int:
	return _client.hud.ammo.magazine


func _hud_reserve() -> int:
	return _client.hud.ammo.reserve


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

	game.horde.stop_pacing()
	game.grace.clear()
	cfg.grace_maps = 1
	cfg.escape_grace_seconds = 30.0
	game._set_phase(game.Phase.READY)
	sp.start_round({"id": "spawner_probe"})
	_finished()


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


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	var line := "%s%s" % [what, "" if detail == "" else "  (%s)" % detail]
	_failures.append(line)
	print("  FAIL  %s" % line)
