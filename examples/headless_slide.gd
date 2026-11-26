extends GSGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzSlideRules := preload("../game/zz_slide_rules.gd")
const ZzViewMotion := preload("../game/zz_view_motion.gd")

## Slide in Zombie Zone: only a sprinter holding C slides. A walk, a plain run or a crouch alone
## never does. (Fatal Contact keeps the addon default and slides at a run; its own suite holds that.)

const SECTIONS := 5
const CHECKS := 33
const STEP := 1.0 / 30.0

var _sections_entered := 0
var _sections_finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone slide")
	print("")
	_test_tunables()
	_test_gated()
	_test_sprint_slide()
	_test_matches_fatal_contact()
	_test_camera_motion()
	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _command(forward: float, buttons: int) -> GSFpsCommand:
	var c := GSFpsCommand.new()
	c.move = Vector2(0.0, forward)
	c.buttons = buttons
	return c


## A survivor settled after [param seconds] of holding [param buttons] forward.
class _Link extends RefCounted:
	signal replicated_cvar_changed(cvar_name: String, value: String)
	var held := {}

	func replicated_cvar(cvar_name: String, fallback: String) -> String:
		return String(held.get(cvar_name, fallback))


func _run_for(motor: GSFpsMotor, buttons: int, seconds: float) -> GSFpsState:
	var s := GSFpsState.new()
	s.mode = GSFpsState.Mode.GROUND

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
	var boost_before := rules.slide_boost
	_check(not rules.set_cvar("zz_slide_boost", "99") and is_equal_approx(rules.slide_boost, boost_before), "an out-of-range value is refused, not clamped")
	rules.set_cvar("zz_slide", "1")
	rules.set_cvar("zz_slide_boost", "4")
	rules.set_cvar("zz_slide_min_speed", "9")
	var tuned := ZzPlayer.tunables_for(ZzConfig.new(), null, rules)
	_check(tuned.slide_enabled and is_equal_approx(tuned.slide_boost, 4.0) and is_equal_approx(tuned.slide_min_speed, 9.0), "the cvars reach the tunables")
	var names := ZzSlideRules.table().keys()
	_check(names == GSFpsSlidePreset.cvar_table("zz_slide").keys() and names.has("zz_slide_cooldown"), "the names are the addon's table under zz_slide")
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
	var motor := GSFpsMotor.new(t, GSFpsFlatBody.with_floor(0.0))
	var crouch := GSFpsCommand.BUTTON_CROUCH
	var sprint := GSFpsCommand.BUTTON_SPRINT

	var standing := _run_for(motor, 0, 0.5)
	motor.simulate(standing, _command(0.0, crouch), STEP)
	_check(not standing.is_sliding(), "crouch standing still does not slide")

	var run := _run_for(motor, 0, 2.0)
	motor.simulate(run, _command(1.0, crouch), STEP)
	_check(not run.is_sliding(), "crouch at a plain run does not slide")

	var walk := _run_for(motor, GSFpsCommand.BUTTON_WALK, 2.0)
	motor.simulate(walk, _command(1.0, GSFpsCommand.BUTTON_WALK | crouch), STEP)
	_check(not walk.is_sliding(), "crouch at a walk does not slide")

	var fast := _run_for(motor, sprint, 3.0)
	motor.simulate(fast, _command(1.0, crouch), STEP)
	_check(not fast.is_sliding(), "crouch without the sprint button held does not slide, even at sprint speed")
	_sections_finished += 1


func _test_sprint_slide() -> void:
	_sections_entered += 1
	print("sprint and C together slide")
	var t := ZzPlayer.tunables_for(ZzConfig.new())
	var motor := GSFpsMotor.new(t, GSFpsFlatBody.with_floor(0.0))
	var s := _run_for(motor, GSFpsCommand.BUTTON_SPRINT, 3.0)
	var before := s.horizontal_speed()
	_check(before >= t.slide_min_speed, "a sprint is fast enough to slide", "%.2f vs %.2f" % [before, t.slide_min_speed])
	motor.simulate(s, _command(1.0, GSFpsCommand.BUTTON_SPRINT | GSFpsCommand.BUTTON_CROUCH), STEP)
	_check(s.is_sliding(), "sprint plus crouch starts a slide")
	_check(s.horizontal_speed() > before, "it starts with a burst")
	_sections_finished += 1


## Fatal Contact slides on the addon's run preset (`GSFpsSlidePreset.apply_run`). ZZ's survivor must feel the same once the gate is met:
## the same numbers, and in a sim the same burst, carry and cooldown from the same entry speed.
func _test_matches_fatal_contact() -> void:
	_sections_entered += 1
	print("the slide feels like Fatal Contact's")
	var zz := ZzPlayer.tunables_for(ZzConfig.new())
	var fc := GSFpsTunables.new()
	GSFpsSlidePreset.apply_run(fc)
	_check(is_equal_approx(zz.slide_boost, fc.slide_boost), "same boost", "%.2f vs %.2f" % [zz.slide_boost, fc.slide_boost])
	_check(is_equal_approx(zz.slide_friction, fc.slide_friction), "same friction", "%.2f vs %.2f" % [zz.slide_friction, fc.slide_friction])
	_check(is_equal_approx(zz.slide_duration, fc.slide_duration), "same duration")
	_check(is_equal_approx(zz.slide_cooldown, fc.slide_cooldown), "same cooldown")
	_check(is_equal_approx(zz.slide_max_speed, fc.slide_max_speed), "same top speed")

	# Both from the same entry speed on a flat floor: the speed after the burst and the distance of the whole slide.
	var entry := zz.max_speed * 1.45
	var zz_run := _slide_from(zz, entry, GSFpsCommand.BUTTON_SPRINT)
	var fc_run := _slide_from(fc, entry, 0)
	_check(absf(zz_run[0] - fc_run[0]) < 0.01, "same speed after the burst", "%.2f vs %.2f" % [zz_run[0], fc_run[0]])
	_check(absf(zz_run[1] - fc_run[1]) < 0.15, "same distance carried", "%.2f vs %.2f" % [zz_run[1], fc_run[1]])
	_check(absf(zz_run[2] - fc_run[2]) < 0.1, "same time sliding", "%.2f vs %.2f" % [zz_run[2], fc_run[2]])
	_check(zz_run[0] > entry + 3.0, "the burst is a real shove, not a nudge", "%.2f from %.2f" % [zz_run[0], entry])
	_sections_finished += 1


## [speed right after the burst, metres slid, seconds slid] for a slide started at [param entry] m/s.
func _slide_from(t: GSFpsTunables, entry: float, extra: int) -> Array:
	var motor := GSFpsMotor.new(t, GSFpsFlatBody.with_floor(0.0))
	var s := GSFpsState.new()
	s.mode = GSFpsState.Mode.GROUND
	s.velocity = Vector3(0.0, 0.0, -entry)
	var held := extra | GSFpsCommand.BUTTON_CROUCH
	motor.simulate(s, _command(1.0, held), STEP)
	var burst := s.horizontal_speed()
	var start := s.position
	var seconds := 0.0

	while s.is_sliding() and seconds < 6.0:
		motor.simulate(s, _command(1.0, held), STEP)
		seconds += STEP

	return [burst, s.position.distance_to(start), seconds]


func _test_camera_motion() -> void:
	_sections_entered += 1
	print("the camera leans and widens in a slide, and not on a walk")
	var t := ZzPlayer.tunables_for(ZzConfig.new())
	var motor := GSFpsMotor.new(t, GSFpsFlatBody.with_floor(0.0))
	var motion := ZzViewMotion.picks()
	var s := _run_for(motor, 0, 1.0)

	for _i in range(30):
		motion.advance(s, STEP)

	_check(is_zero_approx(motion.fov_added()) and absf(motion.roll()) < 0.05, "a plain run adds nothing")

	var run := _run_for(motor, GSFpsCommand.BUTTON_SPRINT, 3.0)
	motor.simulate(run, _command(1.0, GSFpsCommand.BUTTON_SPRINT | GSFpsCommand.BUTTON_CROUCH), STEP)
	_check(run.is_sliding(), "a slide to look at")
	var widest := 0.0
	var rolled := 0.0

	for _i in range(20):
		motor.simulate(run, _command(1.0, GSFpsCommand.BUTTON_SPRINT | GSFpsCommand.BUTTON_CROUCH), STEP)
		motion.advance(run, STEP)
		widest = maxf(widest, motion.fov_added())
		rolled = maxf(rolled, absf(motion.roll()))

	_check(widest > 1.0, "sliding widens the view", "%.2f degrees" % widest)
	_check(rolled > 0.2 and rolled <= 5.0, "and rolls it, bounded", "%.2f degrees" % rolled)

	var landing := ZzViewMotion.picks()
	landing.note_landing(12.0)
	var deepest := 0.0

	for _i in range(20):
		landing.advance(run, STEP)
		deepest = minf(deepest, landing.eye_drop())

	_check(deepest < -0.01, "a hard landing dips the eye", "%.3f m" % deepest)
	var small := ZzViewMotion.picks()
	small.note_landing(3.0)
	small.advance(run, STEP)
	_check(is_zero_approx(small.eye_drop()), "a hop's landing dips nothing")
	_sections_finished += 1
