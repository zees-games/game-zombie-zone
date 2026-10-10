extends SceneTree

## Renders every kind of zombie in a row, in the pose a state gives it, to a PNG.
##
## [codeblock]
## xvfb-run -a godot --path . --script tools/zombie_rack.gd -- --anim=RUN --out=res://screenshots/rack.png
## [/codeblock]
##
## [b]Looked at, because no check can say whether a zombie looks like one.[/b] The arm and spine
## overrides in `ZzZombieView._pose` were tuned against this picture.

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")

const KINDS: Array[StringName] = [&"common", &"common", &"common", &"leaper", &"strangler", &"bloater",
	&"ram", &"spitter", &"rider", &"brute", &"sleeper"]

var _views: Array = []
var _frames := 0
var _anim := ZzZombieBody.Anim.WALK
var _out := "res://screenshots/rack.png"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--anim="):
			_anim = ZzZombieBody.Anim.get(arg.trim_prefix("--anim="), ZzZombieBody.Anim.WALK)
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")

	var root := Node3D.new()
	get_root().add_child(root)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.22, 0.24, 0.27)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.7
	root.add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 25, 0)
	root.add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 12)
	floor_mesh.mesh = plane
	root.add_child(floor_mesh)

	for i in KINDS.size():
		var view := ZzZombieView.new()
		root.add_child(view)
		view.position = Vector3(float(i) * 1.9 - float(KINDS.size() - 1) * 0.95, 0.0, 0.0)
		view.rotation.y = PI * 0.15
		view.build(KINDS[i], i * 977)
		_views.append(view)

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 2.2, 13.0), Vector3(0.0, 1.1, 0.0))
	camera.fov = 62.0


func _process(delta: float) -> bool:
	_frames += 1

	for view in _views:
		view.present(1.0 / 30.0, _anim, 0)

	if _frames == 24:
		var image := get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
		image.save_png(_out)
		print("wrote ", _out)
		quit()

	return false
