extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")

## How a zombie moves: the locomotion style is chosen from the speed it really has, so a
## zombie at a walking or slow chasing pace shambles and only one at running pace runs.

const SECTIONS := 3
const CHECKS := 16
const STEP := 1.0 / 30.0

var _sections_entered := 0
var _sections_finished := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone gait")
	print("")
	_test_bands()
	_test_view()
	_test_speeds()
	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _test_bands() -> void:
	_sections_entered += 1
	print("the style follows the speed, with a margin so the edge does not flicker")
	var shamble := ZzZombieView.GAIT_SHAMBLE
	var run := ZzZombieView.GAIT_RUN
	_check(ZzZombieView.gait_for(1.1, run) == shamble, "a walking pace shambles")
	_check(ZzZombieView.gait_for(2.2, run) == shamble, "a slow chase shambles")
	_check(ZzZombieView.gait_for(6.3, shamble) == run, "a sprint runs")
	_check(ZzZombieView.gait_for(2.9, shamble) == shamble and ZzZombieView.gait_for(2.9, run) == run, "between the bands it keeps what it did")
	_check(ZzZombieView.gait_for(4.0, shamble, {"shamble_below": 4.5, "run_from": 5.0}) == shamble, "a kind's own gait moves the bands")
	_sections_finished += 1


## Drives a real view along the ground the way the brain does: RUN as the state, whatever the pace.
func _drive(speed: float, seconds: float, variant: int = 3) -> ZzZombieView:
	var view := ZzZombieView.new()
	add_child(view)
	view.build(ZzNpcs.COMMON, variant)

	for i in int(seconds / STEP):
		view.global_position = Vector3(speed * STEP * float(i), 0.0, 0.0)
		view.present(STEP, ZzZombieBody.Anim.RUN, 0)

	return view


func _test_view() -> void:
	_sections_entered += 1
	print("a common told to RUN at a walking pace draws the shamble; at a run it draws the run")
	var slow := _drive(1.1, 1.5)
	_check(slow._gait == ZzZombieView.GAIT_SHAMBLE, "at 1.1 m/s the gait is the shamble")
	_check(slow._clip == &"walk", "at 1.1 m/s the clip is the walk, not the run cycle slowed down")
	_check(slow._shamble > 0.95, "the shamble pose is fully applied")
	var chase := _drive(2.2, 1.5)
	_check(chase._gait == ZzZombieView.GAIT_SHAMBLE and chase._clip == &"walk", "at the slow chase speed (2.2 m/s) it still shambles")
	var fast := _drive(6.3, 1.5)
	_check(fast._gait == ZzZombieView.GAIT_RUN, "at 6.3 m/s the gait is the run")
	_check(fast._clip == &"run_arms", "at 6.3 m/s the clip is the run cycle")
	_check(fast._shamble < 0.01, "the shamble pose is gone at a run")

	for view: ZzZombieView in [slow, chase, fast]:
		view.queue_free()

	_sections_finished += 1


func _test_speeds() -> void:
	_sections_entered += 1
	print("the game's own speeds land in the right band")
	var c := ZzConfig.new()
	var below: float = ZzZombieView.GAIT["shamble_below"]
	var from: float = ZzZombieView.GAIT["run_from"]
	_check(c.common_walk_speed < below, "the walking speed is a shamble")
	_check(ZzNpcs.common_chase_speed(c, 0, false) < below, "the base chase speed is a shamble")
	_check(ZzNpcs.common_chase_speed(c, 0, true) >= from, "a runner's speed is a run")
	_check(c.common_run_speed >= from, "the full run speed is a run")
	_sections_finished += 1
