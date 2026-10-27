extends SceneTree

## Close contact sheet of commons: a row per variant, a column per clip, rendered in a SubViewport of any size
## (`zombie_rack.gd` is limited to the window's), framed on `--frame=full|head|upper`.
##
## [codeblock]
## xvfb-run -a godot --path . --script tools/zombie_close.gd -- --variants=6,13,20 --cols=idle,walk,run,attack,stagger,death --frame=full --out=res://screenshots/city.png
## [/codeblock]

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")

const CLIPS := {"idle": ZzZombieBody.Anim.IDLE, "walk": ZzZombieBody.Anim.WALK, "run": ZzZombieBody.Anim.RUN,
	"attack": ZzZombieBody.Anim.ATTACK, "stagger": ZzZombieBody.Anim.STAGGER, "death": ZzZombieBody.Anim.DEAD}

var _cells: Array = []
var _frames := 0
var _out := "res://screenshots/close.png"
var _vp: SubViewport
var _wait := 14


func _initialize() -> void:
	var variants := PackedStringArray(["6"])
	var cols := PackedStringArray(["idle", "walk", "run", "attack", "stagger", "death"])
	var frame := "full"
	var night := false
	var kind := &"common"
	var px := 2400

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--variants="):
			variants = arg.trim_prefix("--variants=").split(",")
		elif arg.begins_with("--cols="):
			cols = arg.trim_prefix("--cols=").split(",")
		elif arg.begins_with("--frame="):
			frame = arg.trim_prefix("--frame=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--kind="):
			kind = StringName(arg.trim_prefix("--kind="))
		elif arg.begins_with("--px="):
			px = int(arg.trim_prefix("--px="))
		elif arg == "--night":
			night = true

	# A cell's size, and how far down from the cell's middle the feet are: a closer frame packs the cells tighter and
	# stands later rows in front, so a body never hides the head under it.
	var cell := {"full": Vector2(2.2, 2.4), "upper": Vector2(1.1, 1.1), "head": Vector2(0.5, 0.5)}.get(frame, Vector2(2.2, 2.4)) as Vector2
	var feet := {"full": 0.0, "upper": 1.3, "head": 1.67}.get(frame, 0.0) as float
	var wide := cell.x * cols.size()
	var tall := cell.y * variants.size()
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(px, int(px * tall / wide))
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_vp)

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.32, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.55
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 155, 0)
	sun.light_energy = 1.1

	if night:
		env.environment.background_color = Color(0.03, 0.04, 0.08)
		env.environment.ambient_light_color = Color(0.35, 0.4, 0.6)
		env.environment.ambient_light_energy = 0.3
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.35

	_vp.add_child(env)
	_vp.add_child(sun)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.42, 0.42, 0.4)

	for r in variants.size():
		for c in cols.size():
			var view := ZzZombieView.new()
			_vp.add_child(view)
			view.position = Vector3(float(c) * cell.x, -float(r) * cell.y - feet, float(r) * 1.5 + float(c) * 0.3)
			view.rotation.y = deg_to_rad(150.0 if frame == "full" else 180.0)
			view.build(kind, int(variants[r]))
			var anim: int = CLIPS[cols[c]]
			_cells.append([view, anim])

			if anim == ZzZombieBody.Anim.DEAD:
				view.die(&"limp", Vector3(0.0, 0.0, -1.0), 1)

	if frame == "full":
		for r in variants.size():
			var floor_mesh := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(wide, 3.0)
			floor_mesh.mesh = plane
			floor_mesh.position = Vector3(cell.x * (cols.size() - 1) * 0.5, -float(r) * cell.y, 0.0)
			floor_mesh.material_override = ground
			_vp.add_child(floor_mesh)

	var camera := Camera3D.new()
	_vp.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = tall
	var middle := Vector3(cell.x * (cols.size() - 1) * 0.5, -cell.y * (variants.size() - 1) * 0.5 + (0.95 if frame == "full" else 0.0), 0.0)
	camera.look_at_from_position(middle + Vector3(0.0, 0.0, 30.0), middle)


func _process(_delta: float) -> bool:
	_frames += 1

	for entry: Array in _cells:
		(entry[0] as ZzZombieView).present(1.0 / 30.0, entry[1], 0)

	if _frames == _wait * 30 / 10 + 30:
		var image := _vp.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
		image.save_png(_out)
		print("wrote %s %s" % [_out, image.get_size()])
		quit()

	return false
