extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")
const ZzBindings := preload("../game/zz_bindings.gd")

## Q drops the weapon in hand: server side, ammo kept, picked up again, cvar, melee, cap, downed, the action bit and the binding.

const SECTIONS := 3
const CHECKS := 20

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone weapon drop")
	print("")
	await _test_drop()
	await _test_rules()
	await _test_wire()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _solo() -> ZzGame:
	return await _team(1, _quiet)


func _lying(game: ZzGame, id: StringName) -> int:
	for key: int in game.loot.entries:
		var e: Dictionary = game.loot.entries[key]
		if e["kind"] == &"weapon" and e["item"] == id and not (e.get("state", {}) as Dictionary).is_empty():
			return key
	return -1


func _dropped_count(game: ZzGame) -> int:
	var n := 0
	for key: int in game.loot.entries:
		if not ((game.loot.entries[key] as Dictionary).get("state", {}) as Dictionary).is_empty():
			n += 1
	return n


func _test_drop() -> void:
	_section("drop: the weapon leaves the hand, ammo and a despawn time ride with it, E picks it up")
	var game := await _solo()
	var p := game.survivors()[0]
	var ars := p.weapons.arsenal
	var primaries := ZzWeapons.ids_of(&"primary")
	_check(primaries.size() >= 1 and game.arm(p, primaries[0]), "a primary is handed over")
	var id: StringName = primaries[0]
	var def := ars.catalogue.get_def(id)
	p.wanted_slot = def.slot
	var _on := ars.equip(def.slot)
	await _sim(game, 1.0)
	ars.current().magazine = 3
	var reserve := ars.ammo().count(def.ammo_type)
	var shelf_before := ars.weapons_in(def.slot).size()
	_check(game.weapon_drop.drop(p), "drop() accepts")
	var held := false
	for w in ars.weapons_in(def.slot):
		held = held or w.id() == id
	_check(not held, "the weapon is out of the arsenal", str(shelf_before))
	var key := _lying(game, id)
	_check(key >= 0, "a pickup with its state lies on the ground")
	_check(key >= 0 and game.loot.position_of(key).distance_to(p.global_position) < 3.0, "it lies near the survivor")
	_check(key >= 0 and float((game.loot.entries[key] as Dictionary).get("until", 0.0)) > 0.0, "it has a despawn time")
	_check(p.wanted_slot == ars.current_slot(), "the wanted slot follows the arsenal, never a stale one", str(ars.current_slot()))
	if key >= 0:
		game.loot.use(key, p)
	var back: Variant = null
	for w in ars.weapons_in(def.slot):
		if w.id() == id:
			back = w
	_check(back != null and back.magazine == 3, "picking it up restores the magazine")
	_check(ars.ammo().count(def.ammo_type) == reserve, "and the reserve", "%d of %d" % [ars.ammo().count(def.ammo_type), reserve])
	_check(_lying(game, id) < 0, "the pickup is used up")
	_finished()


func _test_rules() -> void:
	_section("rules: cvar off, melee, downed, the cap")
	var game := await _solo()
	var p := game.survivors()[0]
	var ars := p.weapons.arsenal
	var primaries := ZzWeapons.ids_of(&"primary")
	var _g1 := game.arm(p, primaries[0])
	var d0 := ars.catalogue.get_def(primaries[0])
	p.wanted_slot = d0.slot
	var _on := ars.equip(d0.slot)
	await _sim(game, 1.0)

	game.weapon_drop.enabled = false
	_check(not game.weapon_drop.drop(p) and _dropped_count(game) == 0, "zz_weapon_drop 0 refuses")
	game.weapon_drop.enabled = true

	_check(ars.weapons_in(1).size() > 0, "the survivor carries a melee weapon")
	p.wanted_slot = 1
	var _m := ars.equip(1)
	await _sim(game, 1.0)
	_check(ars.current_slot() == 1 and not game.weapon_drop.drop(p) and ars.weapons_in(1).size() > 0, "the permanent melee weapon is never dropped")

	p.wanted_slot = d0.slot
	var _a := ars.equip(d0.slot)
	await _sim(game, 1.0)
	game.weapon_drop.max_lying = 1
	_check(game.weapon_drop.drop(p), "a first weapon drops")
	var _g4 := game.arm(p, primaries[0])
	p.wanted_slot = d0.slot
	var _b := ars.equip(d0.slot)
	await _sim(game, 1.0)
	_check(game.weapon_drop.drop(p), "a second drops")
	_check(_dropped_count(game) == 1, "only zz_weapon_drop_max lie; the oldest went", str(_dropped_count(game)))

	var other := await _solo()
	var q := other.survivors()[0]
	var _g3 := other.arm(q, primaries[0])
	q.wanted_slot = d0.slot
	var _s := q.weapons.arsenal.equip(d0.slot)
	await _sim(other, 1.0)
	q.life = ZzPlayer.Life.DOWN
	_check(not other.weapon_drop.drop(q), "a dead or downed survivor drops nothing")
	_finished()


func _test_wire() -> void:
	_section("wire: the action bit drops through the tick, and the key is bound")
	_check(ZzNetCommand.ACT_DROP == 512 and ZzNetCommand.ACT_BITS == 10, "ACT_DROP is bit 9")
	var game := await _solo()
	var p := game.survivors()[0]
	var ars := p.weapons.arsenal
	var primaries := ZzWeapons.ids_of(&"primary")
	var _g := game.arm(p, primaries[0])
	var def := ars.catalogue.get_def(primaries[0])
	p.wanted_slot = def.slot
	var _on := ars.equip(def.slot)
	await _sim(game, 1.0)
	p.actions = ZzNetCommand.ACT_DROP
	await _sim(game, 0.2)
	p.actions = 0
	_check(_lying(game, primaries[0]) >= 0, "the bit makes the server drop the weapon")
	var table := ZzBindings.make()
	_check(not table.row_for_action(ZzBindings.DROP).is_empty(), "the Controls page lists the drop key")
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
