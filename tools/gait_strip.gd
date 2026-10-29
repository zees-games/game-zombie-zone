extends SceneTree

## Frame strips of a common walking past a side-on camera at set speeds, through the real view.
## [codeblock]
## xvfb-run -a godot --path . --script tools/gait_strip.gd -- --speeds=1.1,2.2,6.3 --out=res://screenshots/gait.png
## [/codeblock]
## One row per speed, one column per 0.2 s of walking, so a run cycle played slow or a shamble
## that is not one shows at a glance. `--variant=N` picks the body, `--kind=` the kind.

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")
const ZzWorldView := preload("../game/zz_world_view.gd")

const STEP := 1.0 / 30.0
const COLS := 7
const EVERY := 8

var _speeds: PackedFloat64Array = [1.1, 2.2, 6.3]
var _out := "res://screenshots/gait.png"
var _kind := &"common"
var _variant := 1
var _views: Array[ZzZombieView] = []
var _frames := 0
var _anim := ZzZombieBody.Anim.WALK


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speeds="):
			_speeds = PackedFloat64Array(Array(arg.trim_prefix("--speeds=").split(",")).map(func(v: String) -> float: return float(v)))
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--kind="):
			_kind = StringName(arg.trim_prefix("--kind="))
		elif arg.begins_with("--variant="):
			_variant = int(arg.trim_prefix("--variant="))
		elif arg == "--run-state":
			_anim = ZzZombieBody.Anim.RUN

	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.32, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.55
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 155, 0)
	root.add_child(sun)
	var cell := Vector2(1.8, 2.4)

	for r in _speeds.size():
		for c in COLS:
			var view := ZzWorldView.view_for(_kind) as ZzZombieView
			root.add_child(view)
			view.position = Vector3(float(c) * cell.x, -float(r) * cell.y, 0.0)
			# Side-on: walking along +X, the camera on +Z.
			view.rotation.y = deg_to_rad(90.0)
			view.build(_kind, _variant)
			_views.append(view)

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var tall := cell.y * float(_speeds.size())
	camera.size = tall
	var middle := Vector3(cell.x * float(COLS - 1) * 0.5, -tall * 0.5 + cell.y * 0.62, 0.0)
	camera.look_at_from_position(middle + Vector3(0.0, 0.0, 30.0), middle)
	get_root().size = Vector2i(1500, int(1500.0 * tall / (cell.x * float(COLS))))


func _process(_delta: float) -> bool:
	_frames += 1

	# Every column is the same walker some frames later. present() reads the movement from the
	# view's position, so each frame it is put one step on, drawn, and put back in its cell.
	for r in _speeds.size():
		for c in COLS:
			if _frames > 30 + c * EVERY:
				continue

			var view := _views[r * COLS + c]
			var home := view.global_position
			view.global_position = home + Vector3(_speeds[r] * STEP * float(_frames), 0.0, 0.0)
			view.present(STEP, _anim, 0)
			view.global_position = home

	if _frames == 30 + (COLS - 1) * EVERY + 2:
		var image := get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
		image.save_png(_out)
		print("wrote ", _out)
		quit()
		return true

	return false
