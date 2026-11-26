extends "zz_client_ending.gd"

## The own first-person view of [zz_client.gd]: the camera's motion (slide roll, sprint widening and landing dip,
## [ZzViewMotion]; the eased drop to the floor when downed), which [method _present_rig] adds, and the view arms.

const ZzViewGrip := preload("zz_view_grip.gd")
const ZzViewMotion := preload("zz_view_motion.gd")
const DOWN_EASE_SECONDS := 0.25

## Slide roll, sprint widening and the landing dip of the own camera; [member _motion_fov] is the widening this frame.
var _motion: GSFpsViewMotion = ZzViewMotion.picks()
var _motion_fov: float = 0.0
## 0 standing, 1 down: the camera's roll and drop follow it over [constant DOWN_EASE_SECONDS].
var _down_eased: float = 0.0


## The controller's landing (not emitted in a prediction replay) kicks the own camera's dip.
func _follow_landings() -> void:
	if player.controller != null and not player.controller.landed.is_connected(_on_landed):
		player.controller.landed.connect(_on_landed)


func _on_landed(impact: float) -> void:
	_motion.note_landing(impact)


## The camera motion settings onto the view cues ([method ZzViewMotion.scale]), when [param key] is one of them (or
## empty: all of them, at start).
func _apply_motion_scales(key: StringName = &"") -> void:
	if settings == null or settings.settings == null or (key != &"" and not ZzViewMotion.SETTING_KEYS.has(key)):
		return

	var st: GSSettingsManager = settings.settings
	ZzViewMotion.scale(_motion, st.get_float(&"camera_landing_dip", 1.0), st.get_float(&"camera_strafe_roll", 1.0), st.get_float(&"camera_speed_fov", 1.0))


## How far down the view is, 0 standing to 1 down, eased in and out: the roll and the drop used to jump the frame a
## survivor went down or got up.
func _ease_down(delta: float) -> float:
	_down_eased = move_toward(_down_eased, 1.0 if player.is_down() else 0.0, delta / DOWN_EASE_SECONDS)
	return smoothstep(0.0, 1.0, _down_eased)


## The motion cues this frame for the body drawn at [param drawn]: roll (x) and pitch (y) in radians and the eye's
## drop (z) in metres; the widening goes to [member _motion_fov]. None in third person, down or held.
func _motion_cues(drawn: GSFpsState, delta: float) -> Vector3:
	_motion_fov = 0.0
	if third_person or player.is_down() or player.is_held():
		_motion.snap()
		return Vector3.ZERO

	_motion.advance(drawn, delta)
	_motion_fov = _motion.fov_added()
	return Vector3(deg_to_rad(_motion.roll()), deg_to_rad(_motion.pitch()), _motion.eye_drop())


## Your crawling arms while down in first person. The pivot turns with the yaw only: under the pitch they would swing with the look.
var cl_viewarms_held: bool = false
var _held_grip: GSViewGrip = null
var _held_on: bool = false
var _arms_downed: bool = false


func _present_view_arms(delta: float, yaw: float) -> void:
	if view_arms == null or not is_instance_valid(view_arms):
		_arms_yaw = Node3D.new()
		_arms_yaw.name = "ViewArmsYaw"
		_arms_yaw.top_level = true
		add_child(_arms_yaw)
		view_arms = GSPlayerViewArms.new()
		view_arms.hide_until_fitted = true
		view_arms.name = "ViewArms"
		_arms_yaw.add_child(view_arms)
		view_arms.build(player.view_look(game.side_colour(ZzGame.SURVIVORS)), ZzPlayer.BODY_HEIGHT)

	_arms_yaw.global_position = camera.global_position
	# Holding a weapon the arms follow the look's pitch too: the gun they grip is under the camera.
	_arms_yaw.global_rotation = Vector3(camera.global_rotation.x if _held_on else 0.0, yaw, 0.0)
	# The empty crawling hands only while crawling with the gun put away. Still down (propped) or crawling with the weapon out, the
	# weapon's own hands are the ones drawn, and the crawl arms on top of them made two pairs.
	var on := player.is_crawling() and player.is_holstered() and player.is_alive() and not third_person \
		and not is_spectating() and _end_weight < 0.3

	if on != _arms_downed:
		_arms_downed = on
		view_arms.set_downed(on)

	_arms_yaw.visible = on or _held_on

	_present_held_hands()

	var velocity := player.controller.state.velocity
	view_arms.tick(Vector2(velocity.x, velocity.z).length(), delta)


## `cl_viewarms_held 1` (opt-in): the arms hold the weapon where the view model measured its grip, in place of
## the view model's own hands.
func _on_hands_reached(anchor: Node3D, grip: Vector3, fore: Vector3, pose: StringName) -> void:
	_held_grip = ZzViewGrip.update(_held_grip, anchor, grip, fore, pose)


func _present_held_hands() -> void:
	var opted := cl_viewarms_held and ZzViewGrip.available()
	if view_model != null and is_instance_valid(view_model):
		view_model.show_arms = not opted

	var want := opted and _held_grip != null and player.is_alive() and not third_person \
		and not is_spectating() and _end_weight < 0.3 and (view_model == null or view_model.visible)
	if want != _held_on:
		_held_on = want
		if not want:
			_held_grip = null
	view_arms.set_held(_held_grip if want else null)
