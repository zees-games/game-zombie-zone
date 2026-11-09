extends "zz_suite.gd"

## A survivor picking up a loose prop, carrying it and putting it down (server side), and the zz_prop_force override.

const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzTestToys := preload("zz_test_toys.gd")
const SECTIONS := 5
const CHECKS := 29


func _ready() -> void:
	ZzCatalogue.practice_toys = ZzTestToys.PRACTICE
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone prop carry")
	print("")
	await _test_carry()
	await _test_refusals()
	await _test_throw()
	await _test_blast_and_hint()
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


func _test_throw() -> void:
	_section("throwing a held prop")
	var game := await _start_game()
	var me := game.survivors()[0]
	var barrel := game.map.toys.toy(1)
	_face(me, barrel.body.global_position)
	game._begin_use(me)
	_check(game.prop_carry.carrying(me.player_id), "the barrel is in hand")
	var aim := me.aim_direction()
	var index: int = game.prop_carry.throw_held(game.map.toys, me.player_id, aim, 1.0)
	_check(index == barrel.index and not game.prop_carry.carrying(me.player_id) and not barrel.body.freeze, "a throw lets go of it")
	var v := barrel.body.linear_velocity
	var cap: float = game.prop_carry.THROW_SPEED_MAX
	_check(v.length() > 0.5 and v.length() <= cap + 0.01, "it leaves moving, within the speed cap", "%.2f m/s" % v.length())
	_check(v.normalized().dot(aim) > 0.9, "along the thrower's aim")
	_check(game.prop_carry.throw_held(game.map.toys, me.player_id, aim) == -1, "an empty hand throws nothing")
	# The attack key does it through the hands, and does not also fire the gun.
	_face(me, barrel.body.global_position)
	game._begin_use(me)
	_check(game.prop_carry.carrying(me.player_id), "picked up again")
	var cmd := DotFpsCommand.new()
	cmd.set_button(ZzNetCommand.BUTTON_FIRE, true)
	me.controller.current_command = cmd
	game._advance_hands(me, 0.016)
	_check(not game.prop_carry.carrying(me.player_id), "the attack key throws the held prop")
	me.controller.current_command = null
	_check(barrel.body.linear_velocity.length() > 0.5, "the barrel flies")
	_finished()


func _test_blast_and_hint() -> void:
	_section("explosion force by kind, and the prompt")
	var game := await _start_game()
	var me := game.survivors()[0]
	var barrel := game.map.toys.toy(1)
	var home := barrel.body.global_position
	var at := home + Vector3(1.0, 0.0, 0.0)
	var force: RefCounted = game._prop_force()
	var moved: Array[float] = []
	for scale in [0.0, 1.0, 3.0]:
		barrel.body.global_position = home
		barrel.body.linear_velocity = Vector3.ZERO
		await _sim(game, 0.3)
		var start := barrel.body.global_position
		force.table["grenade"] = {"default": scale}
		game._on_exploded_near_toys(at, 4.0, &"grenade")
		await _sim(game, 0.2)
		moved.append(barrel.body.global_position.distance_to(start))
	_check(moved[0] < 0.05, "a kind with force 0 moves nothing", "%.2f m" % moved[0])
	_check(moved[1] > 0.1, "force 1 moves it", "%.2f m" % moved[1])
	_check(moved[2] > moved[1] * 1.5, "force 3 moves it further", "%.2f vs %.2f m" % [moved[2], moved[1]])
	barrel.body.linear_velocity = Vector3.ZERO
	_face(me, barrel.body.global_position)
	await _sim(game, 0.1)
	_face(me, barrel.body.global_position)
	var text: String = game.prop_carry.hint(game.map.toys, me.eye_position(), me.aim_direction(), game.world_mask(), 30.0)
	_check(text == "pick up barrel", "looking at a barrel hints pick up", text)
	game._begin_use(me)
	await _sim(game, 0.2)
	text = game.prop_carry.hint(game.map.toys, me.eye_position(), me.aim_direction(), game.world_mask(), 30.0)
	_check(text == "put down", "holding it hints put down", text)
	_finished()
