extends RefCounted

## The survivor's camera motion cues (slide roll and widening, strafe lean, landing dip) as picks over the addon's
## [GSFpsViewMotion], the arithmetic Fatal Contact's camera also uses. The shape is FC's; the speeds are ZZ's:
## a sprint is [member ZzConfig.run_speed] times [member ZzConfig.sprint_speed_scale], so the lean and the widening
## start at a sprint, not at FC's 5.74 m/s run. View only: the server never reads it.

const SPRINT_SPEED := 6.2
const FULL_SPEED := 12.0


static func picks() -> GSFpsViewMotion:
	var m := GSFpsViewMotion.new()
	m.landing_dip = 0.06
	m.landing_reference_speed = 16.0
	m.landing_min_speed = 6.0
	m.landing_recovery = 0.25
	m.landing_pitch = 1.0
	m.strafe_roll = 1.0
	m.strafe_roll_reference = SPRINT_SPEED
	m.strafe_roll_response = 8.0
	m.slide_roll = GSFpsViewMotion.new().slide_roll * 0.5
	m.wall_run_roll = 0.0
	m.wall_run_eye_shift = 0.0
	m.wall_run_fov_gain = 0.0
	m.roll_limit = 5.0
	m.fov_speed_gain = 4.0
	m.fov_speed_floor = SPRINT_SPEED
	m.fov_speed_reference = FULL_SPEED
	m.fov_response = 4.0
	m.slide_fov_gain = 2.0
	return m
