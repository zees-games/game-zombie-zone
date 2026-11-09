extends "zz_suite.gd"

const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzEvents := preload("../game/net/zz_events.gd")

## The aim key with the knife in hand throws it (dot-weapon's DotWeaponKnives): it leaves the hand,
## kills a zombie it meets, sticks in it, and is taken back; the cvars and the wire round-trip.

const SECTIONS := 4
const CHECKS := 18
const SPOT := Vector3(0.0, 0.05, 14.0)


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone knife throw")
	print("")
	await _test_throw()
	await _test_hit_and_return()
	await _test_rules()
	_test_wire()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _solo() -> ZzGame:
	var game := await _world(_quiet)
	var _p := game.add_player(&"u100", "Survivor0")
	game.start()
	await _sim(game, 0.25)
	return game


func _holds_knife(p: ZzPlayer) -> bool:
	var ars := p.weapons.arsenal
	var slot: int = ars.catalogue.get_def(&"zz_knife").slot
	for w in ars.weapons_in(slot):
		if w.id() == &"zz_knife":
			return true
	return false


func _knife_in_hand(game: ZzGame, p: ZzPlayer) -> bool:
	var slot: int = p.weapons.arsenal.catalogue.get_def(&"zz_knife").slot
	p.wanted_slot = slot
	var _on := p.weapons.arsenal.equip(slot)
	await _sim(game, 0.6)
	return _holds_knife(p) and p.weapons.arsenal.current_slot() == slot


func _press_aim(game: ZzGame, p: ZzPlayer) -> void:
	p.actions = ZzNetCommand.ACT_AIM
	await _sim(game, 0.1)
	p.actions = 0


func _test_throw() -> void:
	_section("throw: aim with the knife in hand throws it, once per press")
	var game := await _solo()
	var p := game.survivors()[0]
	var knives := game.weapon_layer.knives
	_check(knives != null and knives.is_inside_tree(), "the knife layer is built")
	_check(await _knife_in_hand(game, p), "the survivor holds the knife")
	game.weapon_layer.knife_rules["pickup"] = 0.0
	_aim(p, p.eye_position() + Vector3(0.0, 0.0, -30.0))
	knives.rules["enabled"] = false
	await _press_aim(game, p)
	_check(knives.count() == 0, "zz_knife_throw 0 throws nothing")
	knives.rules["enabled"] = true
	await _sim(game, 0.2)
	await _press_aim(game, p)
	_check(knives.count() == 1, "the press throws a knife", str(knives.count()))
	_check(not _holds_knife(p), "it left the hand")
	_check(p.wanted_slot == p.weapons.arsenal.current_slot(), "the wanted slot follows the arsenal")
	await _sim(game, 3.0)
	_check(knives.count() == 1, "with pickup 0 it stays out", str(knives.count()))
	_finished()


func _test_hit_and_return() -> void:
	_section("hit: the knife kills the zombie it meets, sticks in it, and the survivor takes it back")
	var game := await _solo()
	var p := game.survivors()[0]
	var knives := game.weapon_layer.knives
	var _held := await _knife_in_hand(game, p)
	var seen: Array = []
	knives.changed.connect(func(_id: int, _o: int, phase: int, victim: int, _at: Vector3, _m: Vector3) -> void:
		seen.append([phase, victim]))
	var target := SPOT + Vector3(0.0, 0.0, -6.0)
	var spawned := game.horde.spawn_common_at(target)
	await _sim(game, 0.3)
	_check(spawned and game.horde.spawner.npcs_near(target, 6.0).size() > 0, "a zombie stands in front")
	var npc: DotNpcInstance = game.horde.spawner.npcs_near(target, 6.0)[0]
	var at: Vector3 = (npc.node as Node3D).global_position + Vector3.UP * 1.0
	game.weapon_layer.knife_rules["pickup"] = 0.0
	_aim(p, at)
	await _press_aim(game, p)
	await _sim(game, 1.0)
	var stuck := false
	for e in seen:
		if int(e[0]) == DotWeaponKnives.Phase.STUCK and int(e[1]) != 0:
			stuck = true
	_check(stuck, "it stuck in a body", str(seen))
	_check(not is_instance_valid(npc.node) or not npc.is_alive(), "the zombie died of it")
	var knife: DotWeaponKnives.Knife = knives.entries()[0] if knives.count() > 0 else null
	_check(knife != null, "the knife is out")
	game.weapon_layer.knife_rules["pickup"] = 2.0
	if knife != null:
		p.place_at(knife.at - Vector3.UP * 0.9, 0.0)
	await _sim(game, 1.0)
	_check(knives.count() == 0 and _holds_knife(p), "walking up to it takes it back")
	_finished()


func _test_rules() -> void:
	_section("rules: the knife's cvars exist with a zombie-sized damage and no kill-everything default")
	var game := await _solo()
	var layer := game.weapon_layer
	_check(float(layer.knife_rules["damage"]) == layer.KNIFE_DAMAGE and layer.KNIFE_DAMAGE < 1000.0, "damage is a hit, not a kill", str(layer.knife_rules["damage"]))
	_check(layer.knives.weapon_id == &"zz_knife", "the weapon is zz_knife")
	var bad := await _solo()
	var q := bad.survivors()[0]
	var _held := await _knife_in_hand(bad, q)
	q.life = ZzPlayer.Life.DOWN
	bad.weapon_layer.knife_input(q, DotWeaponCommand.new())
	_check(bad.weapon_layer.knives.count() == 0, "a downed survivor throws nothing")
	q.life = ZzPlayer.Life.UP
	_finished()


func _test_wire() -> void:
	_section("wire: KNIFE round-trips through ZzEvents")
	var at := Vector3(1.0, 2.0, 3.0)
	var k := ZzEvents.read_knife(DotNetReader.new(ZzEvents.write_knife(5, 7, DotWeaponKnives.Phase.STUCK, 9, at, Vector3(0.0, 0.0, -1.0))))
	_check(bool(k["ok"]) and int(k["id"]) == 5 and int(k["owner"]) == 7 and int(k["victim"]) == 9, "ids and phase survive", str(k))
	_check((k["at"] as Vector3).distance_to(at) < 0.05, "the place survives", str(k["at"]))
	_check(ZzEvents.Kind.KNIFE < (1 << 6), "the kind fits the event header")
	_finished()
