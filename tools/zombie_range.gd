extends SceneTree

## Every zombie kind in a row, seen from several ranges, one PNG per range: the check that a
## zombie is whole (not cut at the waist) at the distances its generated levels of detail switch in.
##   xvfb-run -a godot --path . --script tools/zombie_range.gd -- --out=res://screenshots/range --ranges=4,10,20,40 [--bias=0.4]

const ZzZombieView := preload("../npcs/zz_zombie_view.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

const KINDS: Array[StringName] = [&"common", &"leaper", &"strangler", &"bloater", &"ram", &"spitter", &"rider", &"brute", &"sleeper", &"screamer", &"crawler", &"riot"]
const SKY := Color(0.3, 0.32, 0.36)

var _out := "res://screenshots/range"
var _ranges: Array[float] = [4.0, 10.0, 20.0, 40.0]
var _views: Array[ZzZombieView] = []
var _camera: Camera3D
var _step := 0
var _frames := 0
var _gaps := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--ranges="):
			_ranges.clear()
			for t in arg.substr(9).split(","):
				_ranges.append(float(t))
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = SKY
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 155, 0)
	root.add_child(sun)
	for i in KINDS.size():
		var view := ZzZombieView.new()
		root.add_child(view)
		view.position = Vector3((i - (KINDS.size() - 1) * 0.5) * 1.6, 0.0, 0.0)
		view.rotation.y = deg_to_rad(180.0 - 25.0 * (1 if i % 2 == 0 else -1))
		view.build(KINDS[i], 11 + i)
		_views.append(view)
	_camera = Camera3D.new()
	_camera.fov = 22.0
	root.add_child(_camera)
	get_root().size = Vector2i(1800, 500)


func _process(_delta: float) -> bool:
	_frames += 1
	for v in _views:
		v.present(1.0 / 30.0, ZzZombieBody.Anim.WALK, 0)
	var range_m := _ranges[_step]
	_camera.look_at_from_position(Vector3(0.0, 1.2, range_m), Vector3(0.0, 1.0, 0.0))
	if _frames % 20 != 0:
		return false
	var image := get_root().get_texture().get_image()
	var path := "%s_%d.png" % [_out, int(range_m)]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	image.save_png(path)
	print("wrote %s" % path)
	_step += 1
	if _step >= _ranges.size():
		quit()
	return false
