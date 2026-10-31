extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")
const ZzBindings := preload("../game/zz_bindings.gd")

## Q throws the held weapon through the shared DotWeaponDrops: pickup, swap, cvars, cap, downed, death, wire.

const SECTIONS := 4
const CHECKS := 26

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
	await _test_throw()
	await _test_rules()
	await _test_wire()
	await _test_shot_hold()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _solo() -> ZzGame:
	return await _team(1, _quiet)


func _equip_primary(game: ZzGame, p: ZzPlayer) -> StringName:
	var id: StringName = ZzWeapons.ids_of(&"primary")[0]
	var _g := game.arm(p, id)
	var def := p.weapons.arsenal.catalogue.get_def(id)
	p.wanted_slot = def.slot
	var _on := p.weapons.arsenal.equip(def.slot)
	await _sim(game, 1.0)
	return id


func _holds(p: ZzPlayer, id: StringName) -> bool:
	var ars := p.weapons.arsenal
	for w in ars.weapons_in(ars.catalogue.get_def(id).slot):
		if w.id() == id:
			return true
	return false


func _press_q(game: ZzGame, p: ZzPlayer) -> void:
	p.actions = ZzNetCommand.ACT_DROP
	await _sim(game, 0.1)
	p.actions = 0
	await _sim(game, 0.1)


func _test_throw() -> void:
	_section("throw: Q leaves the hands, the empty slot takes it back, a full one swaps")
	var game := await _solo()
	var p := game.survivors()[0]
	var ars := p.weapons.arsenal
	var drops := game.weapon_layer.drops
	_check(drops != null and drops.is_inside_tree(), "the drop layer is built")
	var id := await _equip_primary(game, p)
	ars.current().magazine = 3
	var def := ars.catalogue.get_def(id)
	var reserve := ars.ammo().count(def.ammo_type)

	game.weapon_layer.rules.key_enabled = false
	await _press_q(game, p)
	_check(drops.count() == 0 and _holds(p, id), "sv_weapon_drop_key 0 throws nothing")
	game.weapon_layer.rules.key_enabled = true

	await _press_q(game, p)
	_check(drops.count() == 1, "Q throws the held weapon once per press", str(drops.count()))
	_check(not _holds(p, id), "it left the hands")
	_check(p.wanted_slot == ars.current_slot(), "the wanted slot follows the arsenal", str(ars.current_slot()))
	game.weapon_layer.rules.pickup_radius = 60.0
	for i in 12:
		await _sim(game, 1.0)
		if drops.count() == 0:
			break
	_check(drops.count() == 0 and _holds(p, id), "the empty slot picks it back up")
	var back: Variant = null
	for w in ars.weapons_in(def.slot):
		if w.id() == id:
			back = w
	_check(back != null and back.magazine == 3, "with its magazine")
	_check(ars.ammo().count(def.ammo_type) == reserve, "and the reserve", "%d of %d" % [ars.ammo().count(def.ammo_type), reserve])
	_finished()


func _test_rules() -> void:
	_section("rules: radius, melee, the cap, downed, death")
	var game := await _solo()
	var p := game.survivors()[0]
	var ars := p.weapons.arsenal
	var drops := game.weapon_layer.drops
	var rules := game.weapon_layer.rules
	var id := await _equip_primary(game, p)

	rules.pickup_radius = 0.0
	_check(game.weapon_layer.throw(p) and drops.count() == 1, "a throw is accepted")
	await _sim(game, 2.0)
	_check(drops.count() == 1, "pickup_radius 0 leaves it on the floor")
	rules.pickup_radius = 2.0

	drops.clear()
	_check(drops.count() == 0, "clear() empties the layer")

	p.wanted_slot = 1
	var _m := ars.equip(1)
	await _sim(game, 0.5)
	_check(not game.weapon_layer.throw(p) and ars.weapons_in(1).size() > 0, "the permanent melee weapon is never thrown")

	rules.max_count = 1
	rules.pickup_radius = 0.0
	for i in 2:
		var _id := await _equip_primary(game, p)
		var _t := game.weapon_layer.throw(p)
	_check(drops.count() == 1, "max_count 1 cleans the oldest", str(drops.count()))
	drops.clear()

	var other := await _solo()
	var q := other.survivors()[0]
	var _oid := await _equip_primary(other, q)
	q.life = ZzPlayer.Life.DOWN
	_check(not other.weapon_layer.throw(q), "a downed survivor throws nothing")
	q.life = ZzPlayer.Life.UP

	var dead := await _solo()
	var r := dead.survivors()[0]
	var rid := await _equip_primary(dead, r)
	dead.weapon_layer.drop_dead(r)
	_check(dead.weapon_layer.drops.count() >= 1 and not _holds(r, rid), "a death leaves the weapon on the floor")
	dead.weapon_layer.drops.clear()
	var off := await _solo()
	var s := off.survivors()[0]
	var _sid := await _equip_primary(off, s)
	off.weapon_layer.rules.on_death = false
	off.weapon_layer.drop_dead(s)
	_check(off.weapon_layer.drops.count() == 0, "sv_weapon_drop_death 0 leaves nothing")
	_finished()


func _test_shot_hold() -> void:
	_section("shot and hold: a traced shot wakes a drop, a tap does not swap, a hold does")
	var game := await _solo()
	var p := game.survivors()[0]
	var ars := p.weapons.arsenal
	var layer := game.weapon_layer
	var drops := layer.drops
	var id := await _equip_primary(game, p)
	layer.rules.pickup_radius = 0.0
	layer.rules.pickup_delay = 0.0
	_check(layer.throw(p), "a throw is accepted")
	for _k in 20:
		await _sim(game, 1.0)
		if drops.active_count() == 0:
			break
	var snap: Dictionary = drops.snapshot()[0]
	var rest: Vector3 = snap["at"].origin if snap.has("at") else Vector3.ZERO
	var awake: int = drops.active_count()
	var tr: DotTrace = game.combat.trace
	var _miss := tr.ray(rest + Vector3(3, 1, 0), Vector3.DOWN, 5.0)
	_check(drops.active_count() == awake, "a trace that misses wakes nothing")
	var _hit := tr.ray(rest + Vector3(0, 1, 0), Vector3.DOWN, 5.0)
	_check(drops.active_count() > awake, "a traced shot wakes the dropped weapon")

	var def := ars.catalogue.get_def(id)
	var other := &""
	for cid in ZzWeapons.ids_of(&"primary"):
		if cid != id and ars.catalogue.get_def(cid).slot == def.slot:
			other = cid
			break
	var _g := game.arm(p, other)
	_check(other != &"" and _holds(p, other), "another primary fills the slot")
	var slot_def := ars.catalogue.get_def(other)
	if ars.carry != null:
		ars.carry.slot_capacity = ars.weapons_in(slot_def.slot).size()
	var third := &""
	for cid in ZzWeapons.ids_of(&"primary"):
		if not _holds(p, cid) and ars.catalogue.get_def(cid).slot == slot_def.slot:
			third = cid
			break
	var at: Vector3 = p.eye_position() + p.aim_direction() * 1.0
	drops.clear()
	layer.rules.pickup_radius = 2.0
	var state: Dictionary = (snap["state"] as Dictionary).duplicate()
	state["id"] = third
	var d := drops.spawn(state, at, Vector3.ZERO, 0)
	await _sim(game, 0.02)
	for _k in 3:
		var _tap := layer.use_key(p, true, 0.05)
		var _rel := layer.use_key(p, false, 0.05)
	_check(third != &"" and drops.has_drop(d) and not _holds(p, third), "a tap on a different weapon in a full slot swaps nothing")
	for _k in 40:
		var _hold := layer.use_key(p, true, 0.05)
	_check(not drops.has_drop(d) and _holds(p, third), "a hold takes it")
	_finished()


func _test_wire() -> void:
	_section("wire: the action bit, the key binding and the event codecs")
	_check(ZzNetCommand.ACT_DROP == 512 and ZzNetCommand.ACT_BITS == 12, "ACT_DROP is bit 9")
	var table := ZzBindings.make()
	_check(not table.row_for_action(ZzBindings.DROP).is_empty(), "the Controls page lists the drop key")
	var at := Transform3D(Basis.IDENTITY, Vector3(4, 1, -7))
	var d := ZzEvents.read_weapon_drop(DotNetReader.new(ZzEvents.write_weapon_drop(7, &"m4", 12, 90, at, Vector3(1, 2, 3), 20.0, false)))
	_check(d["ok"] and d["id"] == 7 and d["magazine"] == 12 and d["reserve"] == 90 and d["at"].origin.distance_to(at.origin) < 0.1, "a weapon drop round-trips")
	var st := ZzEvents.read_weapon_settled(DotNetReader.new(ZzEvents.write_weapon_settled(7, at)))
	_check(st["id"] == 7 and st["at"].origin.distance_to(at.origin) < 0.1, "a settle round-trips")
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
