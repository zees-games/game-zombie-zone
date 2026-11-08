extends "zz_suite.gd"

const ZzWeapons := preload("../game/zz_weapons.gd")
const STREET := Vector3(0.0, 0.05, 14.0)

## Sprint must be faster than a run: measured as ground speed on the server's player and on a predicting client's motor,
## unarmed, armed and with carry weight on. Counts sections AND checks, because a script error aborts a section silently.

const SECTIONS := 3
const CHECKS := 9


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone sprint speed")
	print("")
	await _test_server()
	_test_client()
	_test_config()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _team1(configure: Callable) -> ZzGame:
	var game := await _world(configure)
	var _p := game.add_player(&"u100", "Sprinter")
	game.start()
	await _sim(game, 0.25)
	return game


## Steady forward ground speed after [param buttons] held for [param seconds].
func _server_speed(game: ZzGame, buttons: int, seconds: float = 1.5) -> float:
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	me.controller.state.velocity = Vector3.ZERO
	me.controller.state.stamina = 1.0
	me.controller.state.stamina_exhausted = false
	var go := DotFpsCommand.new()
	go.move = Vector2(0.0, 1.0)
	go.buttons = buttons
	me.controller.apply_command(go)
	await _sim(game, seconds)
	var speed := Vector2(me.controller.state.velocity.x, me.controller.state.velocity.z).length()
	me.controller.apply_command(DotFpsCommand.new())
	await _sim(game, 0.6)
	return speed


func _test_server() -> void:
	_section("the server: sprint is faster than a run, unarmed, armed and loaded")
	var game := await _team1(func(c: ZzConfig) -> void:
		_quiet(c)
		c.weight_enabled = true)
	var me := game.survivors()[0]
	me.health.invulnerable = true
	var ratio := game.config.sprint_speed_scale
	var run := await _server_speed(game, 0)
	var sprint := await _server_speed(game, DotFpsCommand.BUTTON_SPRINT)
	print("    run %.2f sprint %.2f ratio %.3f configured %.2f load %.2f weight_scale %.2f" % [run, sprint, sprint / maxf(run, 0.01), ratio, me.controller.motor.load_fraction, me.carry_scale])
	_check(run > 3.0, "a run moves", "%.2f" % run)
	var load0 := me.controller.motor.load_fraction
	var expect0 := 1.0 + (ratio - 1.0) * (1.0 - clampf(load0 * game.config.sprint_load_speed, 0.0, 1.0))
	_check(sprint > run * 1.2 and absf(sprint / run - expect0) < 0.05, "sprint beats a run by the configured ratio (less the starting kit's load)", "%.2f vs %.2f expected x%.3f" % [sprint, run, expect0])
	var heavy := ZzWeapons.ids_of(&"heavy")
	var _a := game.arm(me, heavy[0]) if heavy.size() > 0 else false
	await _sim(game, 0.3)
	var run_w := await _server_speed(game, 0)
	var sprint_w := await _server_speed(game, DotFpsCommand.BUTTON_SPRINT)
	var load := me.controller.motor.load_fraction
	var expect := 1.0 + (ratio - 1.0) * (1.0 - clampf(load * game.config.sprint_load_speed, 0.0, 1.0))
	print("    armed: run %.2f sprint %.2f ratio %.3f expected %.3f load %.2f weight_scale %.2f" % [run_w, sprint_w, sprint_w / maxf(run_w, 0.01), expect, load, me.carry_scale])
	_check(sprint_w > run_w * 1.05, "armed and loaded, sprint is still clearly faster than a run", "%.2f vs %.2f" % [sprint_w, run_w])
	_check(absf(sprint_w / maxf(run_w, 0.01) - expect) < 0.08, "and by the load-reduced ratio", "%.3f vs %.3f" % [sprint_w / maxf(run_w, 0.01), expect])
	_finished()


func _test_client() -> void:
	_section("the predicting client: the same tunables and load give the same speeds")
	var t := ZzPlayer.tunables_for(ZzConfig.new())
	var ratio := t.sprint_speed_scale
	var run := _motor_speed(t, 0, 0.0)
	var sprint := _motor_speed(t, DotFpsCommand.BUTTON_SPRINT, 0.0)
	print("    client run %.2f sprint %.2f ratio %.3f" % [run, sprint, sprint / maxf(run, 0.01)])
	_check(absf(sprint / run - ratio) < 0.03, "unloaded: sprint is the configured ratio of a run", "%.3f vs %.2f" % [sprint / run, ratio])
	var loaded := _motor_speed(t, DotFpsCommand.BUTTON_SPRINT, 0.4) / run
	_check(loaded > 1.05 and loaded < sprint / run, "a 40 percent load trims the bonus but keeps it", "%.3f" % loaded)
	# The key reaches the command: Shift is bound to the sprint action (and not the slow walk), and holding it sets the sprint bit.
	ZzPlayer.register_actions()
	var shift := false
	for event in InputMap.action_get_events(&"dot_fps_sprint"):
		shift = shift or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_SHIFT)
	_check(shift, "Shift is bound to the sprint action")
	var sampler := DotFpsSampler.new(t)
	Input.action_press(&"dot_fps_sprint")
	Input.action_press(&"dot_fps_forward")
	var command := sampler.sample(TICK)
	Input.action_release(&"dot_fps_sprint")
	Input.action_release(&"dot_fps_forward")
	_check(command.is_pressed(DotFpsCommand.BUTTON_SPRINT) and command.move.y > 0.9, "holding the sprint action sets the sprint bit on the command")
	_finished()


func _motor_speed(t: DotFpsTunables, buttons: int, load: float) -> float:
	var motor := DotFpsMotor.new(t, DotFpsFlatBody.with_floor(0.0))
	motor.load_fraction = load
	var s := DotFpsState.new()
	var c := DotFpsCommand.new()
	c.move = Vector2(0.0, 1.0)
	c.buttons = buttons
	for _i in 4:
		motor.simulate(s, DotFpsCommand.new(), TICK)
	for _i in 160:
		motor.simulate(s, c, TICK)
	return Vector2(s.velocity.x, s.velocity.z).length()


func _test_config() -> void:
	_section("the default survivor profile keeps a sprint")
	var base := ZzPlayer.tunables_for(ZzConfig.new())
	_check(base.can_sprint and base.sprint_speed_scale > 1.2, "the default survivor sprints at more than a run", "%.2f can=%s" % [base.sprint_speed_scale, base.can_sprint])
	_finished()
