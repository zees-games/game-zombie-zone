extends "zz_suite.gd"

## A survivor picking up a loose prop, carrying it and putting it down (server side), and the zz_prop_force override.

const SECTIONS := 3
const CHECKS := 16


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone prop carry")
	print("")
	await _test_carry()
	await _test_refusals()
	_test_override()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _start_game() -> ZzGame:
	var game := await _world(_quiet)
	var _player := game.add_player(&"u100", "Survivor")
	game.start()
	await _sim(game, 0.25)
	return game


## Stands [param me] a metre and a bit from [param spot] looking at it.
func _face(me: ZzPlayer, spot: Vector3) -> void:
	var state := me.controller.state
	state.position = spot + Vector3(1.2, -0.7, 0.0)
	var look := (spot - me.eye_position()).normalized()
	state.yaw = rad_to_deg(atan2(-look.x, -look.z))
	state.pitch = rad_to_deg(asin(look.y))


func _test_carry() -> void:
	_section("pick up, carry, place")
	var game := await _start_game()
	var me := game.survivors()[0]
	var barrel := game.map.toys.toy(1)
	_face(me, barrel.body.global_position)
	game._begin_use(me)
	_check(game.prop_carry.carrying(me.player_id), "the use key lifts the barrel it looks at")
	_check(barrel.body.freeze, "a held barrel is frozen, moved by hand")
	await _sim(game, 0.2)
	var held_at := barrel.body.global_position
	var want := me.eye_position() + me.aim_direction() * game.prop_carry.HOLD_DISTANCE
	_check(held_at.distance_to(want) < 0.5, "it rides in front of the carrier's eyes", "%.2f m off" % held_at.distance_to(want))
	_check(barrel.state_transform().origin.is_equal_approx(held_at), "the replicated state is where it is held")
	me.controller.state.position += Vector3(0.0, 0.0, 3.0)
	await _sim(game, 0.2)
	_check(barrel.body.global_position.distance_to(held_at) > 2.0, "walking takes it along")
	game._begin_use(me)
	_check(not game.prop_carry.carrying(me.player_id) and not barrel.body.freeze, "the use key again puts it down, a body once more")
	var put_y := barrel.body.global_position.y
	await _sim(game, 0.5)
	_check(barrel.body.global_position.y <= put_y + 0.001, "a barrel put down in the air falls rather than floats", "%.2f to %.2f" % [put_y, barrel.body.global_position.y])
	_finished()


func _test_refusals() -> void:
	_section("what cannot be lifted, and a dropped hold")
	var game := await _start_game()
	var me := game.survivors()[0]
	var barrel := game.map.toys.toy(1)
	game.prop_carry.max_mass = 1.0
	_face(me, barrel.body.global_position)
	game._begin_use(me)
	_check(not game.prop_carry.carrying(me.player_id), "a prop over the mass limit stays where it is")
	_check(not barrel.body.freeze, "and is not frozen")
	game.prop_carry.max_mass = 30.0
	game._begin_use(me)
	_check(game.prop_carry.carrying(me.player_id), "within the limit it lifts")
	me.watching = true
	await _sim(game, 0.2)
	_check(not game.prop_carry.carrying(me.player_id) and not barrel.body.freeze, "a carrier who stops playing drops it")
	me.watching = false
	var stranger := game.map.toys.toy(0)
	_check(stranger != null and game.map.toys.count() > 1, "the street has more toys")
	_finished()


func _test_override() -> void:
	_section("the zz_prop_force override")
	var game := ZzGame.new()
	_check(game.set_prop_force_override("{\"zz_m4\": {\"barrel\": 7.0}}") and is_equal_approx(game.prop_force.multiplier(&"zz_m4", &"barrel"), 7.0), "a JSON row replaces that weapon's column")
	_check(game.prop_force.multiplier(&"zz_sniper", &"barrel") > 1.0, "the other rows keep the shipped file")
	_check(not game.set_prop_force_override("not json") and is_equal_approx(game.prop_force.multiplier(&"zz_m4", &"barrel"), 7.0), "text that is not an object is refused and changes nothing")
	_check(game.set_prop_force_override("") and not is_equal_approx(game.prop_force.multiplier(&"zz_m4", &"barrel"), 7.0), "empty restores the file")
	game.free()
	_finished()
