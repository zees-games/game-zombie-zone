extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzSlideRules := preload("../game/zz_slide_rules.gd")

## Slide in Zombie Zone: only a sprinter holding C slides. A walk, a plain run or a crouch alone
## never does. (Arena keeps the addon default and slides at a run; its own suite holds that.)

const SECTIONS := 3
const CHECKS := 18
const STEP := 1.0 / 30.0

var _sections_entered := 0
var _sections_finished := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone slide")
	print("")
	_test_tunables()
	_test_gated()
	_test_sprint_slide()
	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _command(forward: float, buttons: int) -> DotFpsCommand:
	var c := DotFpsCommand.new()
	c.move = Vector2(0.0, forward)
	c.buttons = buttons
	return c


## A survivor settled after [param seconds] of holding [param buttons] forward.
class _Link extends RefCounted:
	signal replicated_cvar_changed(cvar_name: String, value: String)
	var held := {}

	func replicated_cvar(cvar_name: String, fallback: String) -> String:
		return String(held.get(cvar_name, fallback))


func _run_for(motor: DotFpsMotor, buttons: int, seconds: float) -> DotFpsState:
	var s := DotFpsState.new()
	s.mode = DotFpsState.Mode.GROUND

	for _i in range(int(seconds / STEP)):
		motor.simulate(s, _command(1.0, buttons), STEP)

	return s


func _test_tunables() -> void:
	_sections_entered += 1
	print("the survivor opts in: slide on, sprint required, above a plain run")
	var t := ZzPlayer.tunables_for(ZzConfig.new())
	_check(t.slide_enabled, "sliding is on")
	_check(t.slide_requires_sprint, "a slide needs the sprint button")
	_check(t.slide_min_speed > t.max_speed, "the minimum speed is above a plain run")
	var rules := ZzSlideRules.new()
	_check(rules.set_cvar("zz_slide", "0"), "zz_slide is a cvar")
	_check(not ZzPlayer.tunables_for(ZzConfig.new(), null, rules).slide_enabled, "zz_slide 0 turns it off")
	_check(not rules.set_cvar("zz_slide_nope", "1") and not rules.set_cvar("zz_slide_boost", "fast"), "an unknown name or a non-number is refused")
	_check(rules.set_cvar("zz_slide_boost", "99") and is_equal_approx(rules.slide_boost, 20.0), "a value is clamped to its range")
	rules.set_cvar("zz_slide", "1")
	rules.set_cvar("zz_slide_boost", "4")
	rules.set_cvar("zz_slide_min_speed", "9")
	var tuned := ZzPlayer.tunables_for(ZzConfig.new(), null, rules)
	_check(tuned.slide_enabled and is_equal_approx(tuned.slide_boost, 4.0) and is_equal_approx(tuned.slide_min_speed, 9.0), "the cvars reach the tunables")
	var names := ZzSlideRules.table().keys()
	_check(names == DotFpsSlidePreset.cvar_table("zz_slide").keys() and names.has("zz_slide_cooldown"), "the names are the addon's table under zz_slide")
	var link := _Link.new()
	link.held["zz_slide_duration"] = "2.5"
	var follower := ZzSlideRules.new()
	_check(follower.follow_cvars(link) and is_equal_approx(follower.slide_duration, 2.5), "a client follows the held value")
	link.replicated_cvar_changed.emit("zz_slide_cooldown", "0.2")
	_check(is_equal_approx(follower.slide_cooldown, 0.2), "and a change")
	_sections_finished += 1


func _test_gated() -> void:
	_sections_entered += 1
	print("no slide from a walk, a plain run or a crouch alone")
	var t := ZzPlayer.tunables_for(ZzConfig.new())
	var motor := DotFpsMotor.new(t, DotFpsFlatBody.with_floor(0.0))
	var crouch := DotFpsCommand.BUTTON_CROUCH
	var sprint := DotFpsCommand.BUTTON_SPRINT

	var standing := _run_for(motor, 0, 0.5)
	motor.simulate(standing, _command(0.0, crouch), STEP)
	_check(not standing.is_sliding(), "crouch standing still does not slide")

	var run := _run_for(motor, 0, 2.0)
	motor.simulate(run, _command(1.0, crouch), STEP)
	_check(not run.is_sliding(), "crouch at a plain run does not slide")

	var walk := _run_for(motor, DotFpsCommand.BUTTON_WALK, 2.0)
	motor.simulate(walk, _command(1.0, DotFpsCommand.BUTTON_WALK | crouch), STEP)
	_check(not walk.is_sliding(), "crouch at a walk does not slide")

	var fast := _run_for(motor, sprint, 3.0)
	motor.simulate(fast, _command(1.0, crouch), STEP)
	_check(not fast.is_sliding(), "crouch without the sprint button held does not slide, even at sprint speed")
	_sections_finished += 1


func _test_sprint_slide() -> void:
	_sections_entered += 1
	print("sprint and C together slide")
	var t := ZzPlayer.tunables_for(ZzConfig.new())
	var motor := DotFpsMotor.new(t, DotFpsFlatBody.with_floor(0.0))
	var s := _run_for(motor, DotFpsCommand.BUTTON_SPRINT, 3.0)
	var before := s.horizontal_speed()
	_check(before >= t.slide_min_speed, "a sprint is fast enough to slide", "%.2f vs %.2f" % [before, t.slide_min_speed])
	motor.simulate(s, _command(1.0, DotFpsCommand.BUTTON_SPRINT | DotFpsCommand.BUTTON_CROUCH), STEP)
	_check(s.is_sliding(), "sprint plus crouch starts a slide")
	_check(s.horizontal_speed() > before, "it starts with a burst")
	_sections_finished += 1
