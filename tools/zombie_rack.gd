extends SceneTree

## A contact sheet of zombies: one row per kind (or per common variant), one column per state,
## each a frame of the real view (`ZzZombieView`) doing that, saved as a PNG.
##
## [codeblock]
## xvfb-run -a godot --path . --script tools/zombie_rack.gd -- --set=specials --out=res://screenshots/specials.png
## xvfb-run -a godot --path . --script tools/zombie_rack.gd -- --set=commons --out=res://screenshots/commons.png
## xvfb-run -a godot --path . --script tools/zombie_rack.gd -- --set=horde --out=res://screenshots/horde.png
## [/codeblock]
##
## [b]Looked at, because no check can say whether a zombie looks like one.[/b] Every look in
## `ZzZombieView.LOOKS` was set against this picture. `--set=horde` stands sixty commons in a
## crowd and prints the frame time and draw calls, which is the performance number the README
## quotes; `--at=<seconds>` moves the moment the frame is taken (a death needs about 1.2).

const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")

const SPECIALS: Array[StringName] = [&"leaper", &"strangler", &"bloater", &"ram", &"spitter", &"rider",
	&"brute", &"sleeper", &"screamer", &"crawler", &"riot"]

## Column title, the state, and whether it is a death.
const COLUMNS := [
	["idle", ZzZombieBody.Anim.IDLE], ["walk", ZzZombieBody.Anim.WALK], ["run", ZzZombieBody.Anim.RUN],
	["attack", ZzZombieBody.Anim.ATTACK], ["stagger", ZzZombieBody.Anim.STAGGER], ["death", ZzZombieBody.Anim.DEAD],
]

var _cells: Array = []
var _deferred: Array[Callable] = []
var _frames := 0
var _set := "specials"
var _out := "res://screenshots/specials.png"
var _at := 1.3
var _kinds: PackedStringArray = PackedStringArray()
var _cols: PackedStringArray = PackedStringArray()
var _first := 0
var _columns: Array = []
var _times: Array[float] = []
var _last_us := 0
var _present_us := 0
var _present_frames := 0


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--set="):
			_set = arg.trim_prefix("--set=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--first="):
			_first = int(arg.trim_prefix("--first="))
		elif arg.begins_with("--cols="):
			_cols = arg.trim_prefix("--cols=").split(",")
		elif arg.begins_with("--kinds="):
			_kinds = arg.trim_prefix("--kinds=").split(",")
		elif arg.begins_with("--at="):
			_at = float(arg.trim_prefix("--at="))

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
	sun.light_energy = 1.1
	root.add_child(sun)

	var rows: Array = []

	for column: Array in COLUMNS:
		if _cols.is_empty() or _cols.has(column[0]):
			_columns.append(column)

	if _set == "commons":
		for i in range(_first, _first + 5):
			rows.append([&"common", i * 4111 + 7 + i])
	elif _set == "horde":
		_horde(root)
		return
	elif _set == "deaths":
		_deaths(root)
		return
	elif _set == "gore":
		_gore(root)
		return
	else:
		for kind in SPECIALS:
			if _kinds.is_empty() or _kinds.has(String(kind)):
				rows.append([kind, 1])

	# Each row on its own floor, one above the other, and the camera level with them, so no row
	# hides behind another.
	var cell := Vector2(2.6, 3.6)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.42, 0.42, 0.4)

	for r in rows.size():
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(cell.x * _columns.size(), 3.0)
		floor_mesh.mesh = plane
		floor_mesh.position = Vector3(cell.x * (_columns.size() - 1) * 0.5, -float(r) * cell.y, 0.0)
		floor_mesh.material_override = ground
		root.add_child(floor_mesh)

		for c in _columns.size():
			var view := ZzZombieView.new()
			root.add_child(view)
			view.position = Vector3(float(c) * cell.x, -float(r) * cell.y, 0.0)
			view.rotation.y = deg_to_rad(180.0 - 30.0)
			view.build(rows[r][0], int(rows[r][1]))
			_cells.append([view, _columns[c][1]])

			if _columns[c][1] == ZzZombieBody.Anim.DEAD:
				view.die(&"limp", Vector3(0.0, 0.0, -1.0), 1)

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var wide := cell.x * _columns.size()
	var tall := cell.y * float(rows.size())
	camera.size = tall
	var middle := Vector3(wide * 0.5 - cell.x * 0.5, -tall * 0.5 + cell.y * 0.62, 0.0)
	camera.look_at_from_position(middle + Vector3(0.0, 6.0, 30.0), middle)
	get_root().size = Vector2i(1500, int(1500.0 * tall / wide))


## Each of dot-player-char's reactions as a row, a common falling with it over the columns
## (0, 0.15, 0.3, 0.5, 0.8 and 1.3 s after the killing shot, which comes from the camera's side).
func _deaths(root: Node3D) -> void:
	var reactions := [&"limp", &"headshot_launch", &"power_launch", &"face_plant", &"crumple"]
	var times := [0.0, 0.15, 0.3, 0.5, 0.8, 1.3]
	var cell := Vector2(3.0, 3.0)
	var ground := StandardMaterial3D.new()
	ground.albedo_color = Color(0.42, 0.42, 0.4)
	var capture := int(_at * 30.0)

	for r in reactions.size():
		var floor_mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(cell.x * times.size(), 4.0)
		floor_mesh.mesh = plane
		floor_mesh.position = Vector3(cell.x * (times.size() - 1) * 0.5, -float(r) * cell.y, -1.0)
		floor_mesh.material_override = ground
		root.add_child(floor_mesh)

		for c in times.size():
			var view := ZzZombieView.new()
			root.add_child(view)
			view.position = Vector3(float(c) * cell.x, -float(r) * cell.y, 0.0)
			view.rotation.y = deg_to_rad(180.0 - 60.0)
			view.build(&"common", 900 + r * 37)
			# Shot from the camera's side: pushed away from it, into the picture.
			_cells.append([view, ZzZombieBody.Anim.IDLE, capture - int(float(times[c]) * 30.0), reactions[r]])

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var wide := cell.x * times.size()
	var tall := cell.y * float(reactions.size())
	camera.size = tall
	var middle := Vector3(wide * 0.5 - cell.x * 0.5, -tall * 0.5 + cell.y * 0.6, 0.0)
	camera.look_at_from_position(middle + Vector3(0.0, 8.0, 30.0), middle)
	get_root().size = Vector2i(1500, int(1500.0 * tall / wide))


## Dismemberment: a common with no limb, then one each, then several, side by side, standing and walking.
## `--level=N` sets DotNpcGore.level first.
func _gore(root: Node3D) -> void:
	var ZzZombieLimbs := preload("../npcs/zz_zombie_limbs.gd")
	var defs := ZzZombieLimbs.defs_for(&"common", 100.0)
	var sets := [[], ["head"], ["armL"], ["legR"], ["armL", "armR"], ["legL", "legR"], ["head", "armR", "legL"]]
	var pick := PackedStringArray()
	var yaw := 30.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pick="):
			pick = arg.trim_prefix("--pick=").split(",")
		elif arg.begins_with("--yaw="):
			yaw = float(arg.trim_prefix("--yaw="))
	if not pick.is_empty():
		var chosen := []
		for i in pick:
			chosen.append(sets[int(i)])
		sets = chosen
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(sets.size() * 2.4, 6.0)
	ground.mesh = plane
	ground.position = Vector3(sets.size() * 1.2 - 1.2, 0.0, 0.0)
	root.add_child(ground)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			DotNpcGore.level = int(arg.trim_prefix("--level="))
	for i in sets.size():
		var view := ZzZombieView.new()
		root.add_child(view)
		view.position = Vector3(float(i) * 2.4, 0.0, 0.0)
		view.rotation.y = deg_to_rad(180.0 - yaw)
		view.build(&"common", 4111 + i)
		_cells.append([view, ZzZombieBody.Anim.IDLE])
		var setup := func() -> void:
			for limb: String in sets[i]:
				view.sever_limb(StringName(limb), defs[limb], Vector3(0.0, 1.0, 2.0))
			if "--wounds" in OS.get_cmdline_user_args():
				for w in [Vector3(0.06, 1.2, 0.2), Vector3(-0.12, 0.95, 0.2), Vector3(0.1, 0.7, 0.18)]:
					view.wound_at(view.global_position + view.global_basis * w, 0.1)
				if "legL" in sets[i] and "legR" in sets[i]:
					for k in 4:
						var _p := DotNpcGibs.add_pool(root.get_tree(), view.global_position + view.global_basis * Vector3(0.0, 0.0, -0.5 - 0.7 * float(k)), 0.22 - 0.02 * float(k))
		_deferred.append(setup)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var wide := float(sets.size()) * 2.4
	camera.size = clampf(wide * 720.0 / 1800.0, 2.6, 7.0)
	var mid := Vector3(sets.size() * 1.2 - 1.2, 1.0 + camera.size * 0.12, 0.0)
	camera.look_at_from_position(mid + Vector3(0.0, 2.0, 30.0), mid)
	get_root().size = Vector2i(1800, 720)


## Sixty commons in a crowd walking at the camera, for the frame time and draw calls.
func _horde(root: Node3D) -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	root.add_child(floor_mesh)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	for i in 60:
		var view := ZzZombieView.new()
		root.add_child(view)
		view.position = Vector3(rng.randf_range(-7.0, 7.0), 0.0, -rng.randf_range(2.0, 30.0))
		view.rotation.y = PI + rng.randf_range(-0.4, 0.4)
		view.build(&"common", rng.randi() & 0xFFFF)
		_cells.append([view, [ZzZombieBody.Anim.WALK, ZzZombieBody.Anim.RUN, ZzZombieBody.Anim.SHAMBLE][i % 3]])

	var camera := Camera3D.new()
	root.add_child(camera)
	camera.look_at_from_position(Vector3(0.0, 1.7, 4.0), Vector3(0.0, 1.2, -10.0))
	get_root().size = Vector2i(1280, 720)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 3:
		for call in _deferred:
			call.call()
	var now := Time.get_ticks_usec()

	if _last_us > 0 and _frames > 10:
		_times.append(float(now - _last_us) / 1000.0)
	_last_us = now

	var started := Time.get_ticks_usec()

	for entry: Array in _cells:
		if entry.size() > 2:
			# A death cell: standing until its moment, then killed and falling.
			if _frames == int(entry[2]):
				(entry[0] as ZzZombieView).die(entry[3], Vector3(0.0, 0.0, -1.6), 5)
			(entry[0] as ZzZombieView).present(1.0 / 30.0,
				ZzZombieBody.Anim.DEAD if _frames >= int(entry[2]) else ZzZombieBody.Anim.IDLE, 0)
			continue
		(entry[0] as ZzZombieView).present(1.0 / 30.0, entry[1], 0)

	if _frames > 10:
		_present_us += Time.get_ticks_usec() - started
		_present_frames += 1

	if _frames == int(_at * 30.0):
		var image := get_root().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out.get_base_dir()))
		image.save_png(_out)
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var mean := 0.0
		for t in _times:
			mean += t
		mean /= maxf(float(_times.size()), 1.0)
		print("process_ms=%.2f physics_ms=%.2f  vertices=%d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
		print("wrote %s  zombies=%d draw_calls=%d objects=%d mean_frame_ms=%.1f present_us_per_zombie=%.0f (llvmpipe, software)" % [
			_out, _cells.size(), draws, objects, mean,
			float(_present_us) / maxf(float(_present_frames * _cells.size()), 1.0)])
		quit()

	return false
