extends "zz_suite.gd"

const ZzPropForce := preload("../game/zz_prop_force.gd")

## The per-weapon force table on loose props: lookup rules, the shipped file, and a shot moving a barrel further with a bigger multiplier.

const SECTIONS := 2
const CHECKS := 9


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone prop force")
	print("")
	_test_table()
	await _test_shot()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _test_table() -> void:
	_section("the multiplier table")
	var force = ZzPropForce.new()
	force.set_table({"comment": "x", "*": {"default": 1.0}, "a": {"default": 2.0, "ball": 4.0}, "bad": 3, "neg": {"default": -5}})
	_check(is_equal_approx(force.multiplier(&"a", &"ball"), 4.0), "a weapon's own column wins")
	_check(is_equal_approx(force.multiplier(&"a", &"barrel"), 2.0), "its default covers the other kinds")
	_check(is_equal_approx(force.multiplier(&"other", &"ball"), 1.0), "an unlisted weapon takes the * row")
	_check(is_equal_approx(force.multiplier(&"neg", &"ball"), 0.0), "a negative multiplier is clamped to zero")
	_check(is_equal_approx(ZzPropForce.new().multiplier(&"a", &"ball"), 1.0), "an empty table is 1.0 everywhere")
	var shipped = ZzPropForce.load_file()
	_check(shipped.multiplier(&"zz_sniper", &"barrel") > 1.0 and is_equal_approx(shipped.multiplier(&"no_such_gun", &"barrel"), 1.0), "the shipped file loads: a sniper pushes a barrel harder, an unknown gun as before")
	_finished()


func _team(count: int, configure: Callable = Callable()) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var _player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)

	game.start()
	await _sim(game, 0.25)
	return game


## One shot at the practice street's barrel with [param scale] on every weapon; how far it moved.
func _shot_with(scale: float) -> float:
	var game := await _team(1, _quiet)
	game.prop_force = ZzPropForce.new()
	game.prop_force.set_table({"*": {"default": scale}})
	var me := game.survivors()[0]
	var barrel := game.map.toys.toy(1)
	var r0 := barrel.body.global_position
	var shot := DotShot.make(&"test", me.entity_id, game.current_tick(), 0)
	shot.weapon_id = &"zz_m4"
	shot.origin = r0 + Vector3(0.0, 0.0, -5.0)
	shot.direction = Vector3(0.0, 0.0, 1.0)
	shot.damage = 30.0
	shot.max_range = 40.0
	game._shoot_toys(shot)
	for _i in range(20):
		await get_tree().physics_frame
	return barrel.body.global_position.distance_to(r0)


func _test_shot() -> void:
	_section("a bigger multiplier moves the barrel further")
	var plain := await _shot_with(1.0)
	var heavy := await _shot_with(3.0)
	var none := await _shot_with(0.0)
	_check(plain > 0.02, "the base shot still pushes the barrel", "%.3f m" % plain)
	_check(heavy > plain * 1.5, "three times the force carries it further", "%.3f vs %.3f m" % [heavy, plain])
	_check(none < 0.02, "zero leaves it where it stood", "%.3f m" % none)
	_finished()
