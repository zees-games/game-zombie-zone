extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzPackList := preload("../game/zz_packs.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

## The weapon pool as a player meets it: every pack weapon has a source, every ammunition type has one, a late wave holds the heavy
## guns back, and a stand-in can fire each gun and chooses between two. Sections and checks are both counted.

const SECTIONS := 5
const CHECKS := 73

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const STREET := Vector3(0.0, 0.05, 14.0)

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()
var _worlds: Array[ZzGame] = []
var _ids: Array[StringName] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone arsenal: sources, ammunition, waves, stand-ins")
	print("")
	var game := await _team(1, true)
	var pack: Array = ZzPackList.cfg("weapons.min_wave", {}).keys()
	_ids = _pack_ids()
	_check(_ids.size() >= 23, "the modern pack's weapons are installed", "%d" % _ids.size())
	_check(not pack.is_empty(), "packs.yml gates the heavy weapons by wave", str(pack))
	_sources(game)
	_ammunition(game)
	_waves()
	await _stand_ins_choose(game)
	await _stand_ins_fire()

	for world in _worlds.duplicate():
		await _dispose(world)

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

	get_tree().quit(code)


func _pack_ids() -> Array[StringName]:
	var out: Array[StringName] = []

	for id in ZzPackList.pack_of:
		if ZzPackList.pack_of[id] == ZzWeapons.MODERN_PACK:
			out.append(StringName(id))

	return out


## Where a weapon can come from: a box or a cache (by tier), a wall-buy or map pool (by catalogue tags) or the trader's menu.
func _sources_of(game: ZzGame, id: StringName, shop_ids: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var tier := ZzWeapons.tier_of(id)
	var late := 10

	ZzWeapons.wave = late
	if ZzWeapons.ids_of(tier).has(id) and ZzWeapons.channel_weight(&"box", id, 1.0) > 0.0:
		out.append("box")
	if ZzWeapons.channel_weight(&"wall", id, 1.0) > 0.0 and [&"sidearm", &"primary"].has(tier):
		out.append("wall")
	if ZzWeapons.channel_weight(&"crate", id, 1.0) > 0.0 and [&"sidearm", &"primary", &"heavy"].has(tier):
		out.append("crate")
	if ZzWeapons.channel_weight(&"spawner", id, 1.0) > 0.0 and [&"sidearm", &"primary", &"heavy", &"thrown"].has(tier):
		out.append("field")
	ZzWeapons.wave = 0
	if shop_ids.has(String(id)):
		out.append("trader")

	return out


func _sources(game: ZzGame) -> void:
	_section("every weapon in the pack has at least one source")
	var shop_ids := {}

	for it: Dictionary in game.shop.items():
		shop_ids[str(it["id"])] = it

	for id in _ids:
		var found := _sources_of(game, id, shop_ids)
		_check(not found.is_empty(), "%s is obtainable" % id, ", ".join(found))

	_check(shop_ids.has("zz_machete") and str((shop_ids["zz_machete"] as Dictionary)["cat"]) == "weapons", "the machete is on the trader's weapons tab")
	_check(not shop_ids.has("mag:zz_machete") and not shop_ids.has("mag:zz_knife"), "and has no magazine to sell")
	_finished()


func _ammunition(game: ZzGame) -> void:
	_section("every ammunition type has a source")
	var shop_ids := {}
	var shop_items := {}

	for it: Dictionary in game.shop.items():
		shop_ids[str(it["id"])] = true
		shop_items[str(it["id"])] = it

	var pools := {}

	for id in _ids:
		var def := ZzWeapons.def_of(id)

		if def != null and def.ammo_type != &"" and not def.infinite_reserve and not def.tags.has(&"melee") and not def.tags.has(&"thrown"):
			var list: Array = pools.get(def.ammo_type, [])
			list.append(id)
			pools[def.ammo_type] = list

	_check(pools.has(&"zz_rocket") and pools.has(&"zz_357") and pools.has(&"zz_40mm"), "the new pools are among them", str(pools.keys()))

	for pool: StringName in pools:
		var users: Array = pools[pool]
		var sold := false

		for id in users:
			sold = sold or (shop_ids.has("mag:%s" % id) and shop_ids.has("refill:%s" % id))

		var me: ZzPlayer = game.survivors()[0]
		var gun: StringName = users[0]
		var _ok := game.arm(me, gun)
		me.weapons.arsenal.ammo().set_count(pool, 0)
		var dropped := ZzLoot.give_ammo(me, 0.25)
		_check(sold and dropped > 0 and me.weapons.arsenal.ammo().count(pool) > 0, "%s: magazines and refills at the trader, and a pile refills it" % pool, "%d from a pile" % dropped)

	var frag_row: Dictionary = shop_items.get("zz_frag", {})
	_check(str(frag_row.get("cat", "")) == "grenades", "a grenade is bought whole, on the grenades tab")
	var rocket := ZzWeapons.def_of(&"zz_rpg")
	var me2: ZzPlayer = game.survivors()[0]
	var _armed := game.arm(me2, &"zz_rpg")
	me2.weapons.arsenal.ammo().set_count(&"zz_rocket", 0)
	me2.points = 100000
	me2.place_at(STREET, 0.0)
	var bought := 0
	for it: Dictionary in game.shop.items():
		if str(it["id"]) == "mag:zz_rpg":
			bought = int(it["price"])
	_check(bought > 0 and bought < 500, "a rocket costs a fraction of the launcher", "%d" % bought)
	var before := me2.points
	var done: bool = game.shop._give(me2, "mag:zz_rpg", {"w": "zz_rpg", "cat": "ammo"}) == ""
	_check(done and me2.weapons.arsenal.ammo().count(&"zz_rocket") == maxi(rocket.magazine, 1) and before == me2.points, "buying a magazine puts a rocket in the pool")
	_finished()


func _waves() -> void:
	_section("a late wave holds the heavy and drum-fed guns back")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var gates: Dictionary = ZzPackList.cfg("weapons.min_wave", {})
	_check(int(gates.get("zz_rpg", 0)) > int(gates.get("zz_aa12", 0)) and int(gates.get("zz_aa12", 0)) > 1, "the rocket launcher comes after the auto shotgun, which comes after the start")

	ZzWeapons.wave = 0
	_check(ZzWeapons.from_wave(&"zz_rpg"), "outside a hold nothing is gated")
	ZzWeapons.wave = 2
	_check(not ZzWeapons.from_wave(&"zz_rpg") and not ZzWeapons.from_wave(&"zz_aa12") and ZzWeapons.from_wave(&"zz_ak"), "wave 2 has no rocket launcher and no auto shotgun")
	_check(ZzWeapons.channel_weight(&"crate", &"zz_rpg", 1.0) == 0.0 and ZzWeapons.channel_weight(&"wall", &"zz_aa12", 1.0) == 0.0, "so no crate or wall-buy lays them")

	var early := 0
	for i in 400:
		early += 1 if [&"zz_rpg", &"zz_aa12"].has(ZzWeapons.random_of(&"heavy", rng, &"box")) or ZzWeapons.random_of(&"primary", rng, &"box") == &"zz_aa12" else 0
	_check(early == 0, "400 box draws at wave 2 never give either", "%d" % early)

	ZzWeapons.wave = int(gates.get("zz_rpg", 7))
	var late_rpg := 0
	var late_aa := 0
	for i in 600:
		late_rpg += 1 if ZzWeapons.random_of(&"heavy", rng, &"box") == &"zz_rpg" else 0
		late_aa += 1 if ZzWeapons.random_of(&"primary", rng, &"box") == &"zz_aa12" else 0
	_check(late_rpg > 0 and late_aa > 0, "at the gate's wave both are drawn", "rpg %d, aa12 %d of 600" % [late_rpg, late_aa])
	ZzWeapons.wave = 0
	_finished()


func _stand_ins_choose(game: ZzGame) -> void:
	_section("a stand-in takes the better gun and holds the launcher for far targets")
	var bot: ZzPlayer = game.survivors()[0]
	var primaries: Array = ZzWeapons.ids_of(&"primary").filter(func(i: StringName) -> bool: return ZzWeapons.def_of(i).slot == 3)
	primaries.sort_custom(func(a: StringName, b: StringName) -> bool: return ZzWeapons.rating(a) < ZzWeapons.rating(b))
	var worst: StringName = primaries[0]
	var best: StringName = primaries[primaries.size() - 1]
	game._disarm(bot)
	var _a := game.arm(bot, worst)
	_check(ZzWeapons.rating(best) > ZzWeapons.rating(worst) * 1.35, "the best primary is rated well above the worst", "%s %.0f, %s %.0f" % [best, ZzWeapons.rating(best), worst, ZzWeapons.rating(worst)])
	_check(game.bots._wants_weapon(bot, best), "a stand-in with the worst primary wants the best")
	var _b := game.arm(bot, best)
	_check(not game.bots._wants_weapon(bot, worst), "and, holding the best, does not trade it down")
	_check(game.bots._wants_weapon(bot, &"zz_rpg"), "it wants a launcher for its empty heavy slot")

	var _c := game.arm(bot, &"zz_rpg")
	bot.place_at(STREET, 0.0)
	var common := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -15), &"test")
	var brute := game.horde.spawner.spawn(ZzNpcs.BRUTE, STREET + Vector3(0, 0, -16), &"test")
	var heavy_slot := ZzWeapons.def_of(&"zz_rpg").slot
	bot.wanted_slot = ZzWeapons.def_of(best).slot
	game.bots._choose_slot(bot, common)
	_check(bot.wanted_slot != heavy_slot, "against a common, never the launcher")
	game.bots._choose_slot(bot, brute)
	_check(bot.wanted_slot == heavy_slot, "against a brute 15 m off, the launcher")
	var near := game.horde.spawner.spawn(ZzNpcs.BRUTE, STREET + Vector3(0, 0, -5), &"test")
	bot.wanted_slot = ZzWeapons.def_of(best).slot
	game.bots._choose_slot(bot, near)
	_check(bot.wanted_slot != heavy_slot, "and against one 5 m off, the gun again")
	_finished()


func _stand_ins_fire() -> void:
	_section("a stand-in fires every gun in the pack without a script error")
	var fired := 0
	var guns := 0

	for id in _ids:
		var def := ZzWeapons.def_of(id)

		if def == null or def.tags.has(&"melee") or def.tags.has(&"thrown"):
			continue

		guns += 1
		var game := await _team(1, true)
		var bot: ZzPlayer = game.survivors()[0]
		game._disarm(bot)
		var _a := game.arm(bot, id)
		game._draw(bot, id)
		bot.place_at(STREET, 0.0)
		var target := game.horde.spawner.spawn(ZzNpcs.BRUTE, STREET + Vector3(0, 0, -14), &"test")
		(target.brain as Object).set(&"idle_kind", 0)
		var start_mag := bot.weapons.arsenal.current().magazine
		var start_hp: float = target.health
		var shot := false

		for t in 8:
			await _sim(game, 0.5)
			var slot: DotWeaponSlot = bot.weapons.arsenal.current()
			shot = slot == null or slot.magazine < start_mag or bot.weapons.arsenal.is_reloading() or not target.is_alive() or target.health < start_hp
			if shot:
				break

		fired += 1 if shot else 0
		_check(shot, "%s: fired at a target 14 m off" % id)
		await _dispose(game)

	_check(guns == 20 and fired == guns, "all %d guns fired" % guns, "%d" % fired)
	_finished()


func _team(count: int, bots: bool) -> ZzGame:
	for old in _worlds.duplicate():
		await _dispose(old)

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.map_ids = PackedStringArray(["zz_practice"])
	config.keep_progress = false
	config.start_grace_seconds = 1.0
	config.wanderer_density = 0.0
	config.specials_base = 0
	config.mob_interval_min = 900.0
	config.mob_interval_max = 900.0
	config.sleepers_enabled = false
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

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
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
