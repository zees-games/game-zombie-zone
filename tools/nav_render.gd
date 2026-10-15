extends Node

## Looks at what the stand-ins and the horde were told: a map's chokepoints, the places stand-ins
## hold behind them, the routes the horde was planned over, and the team standing there.
##
##   xvfb-run -a godot --path . --resolution 1600x900 res://tools/nav_render.tscn -- --map=zz_high_school --out=/tmp/zz_nav
##
## Writes PREFIX_top.png (the debug layer from above, level hidden, which is how a roofed map is
## seen at all) and PREFIX_hold.png (the level drawn, a camera behind one held choke, the team as
## blue capsules). `--seconds=N` is how long the team walks to its places (default 40).

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNavNotes := preload("../game/zz_nav_notes.gd")

const TICK := 1.0 / 64.0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)

	return fallback


func _run() -> void:
	var id := _arg("map", "zz_high_school")
	var out := _arg("out", "/tmp/zz_nav")
	var config := ZzConfig.new()
	config.map_ids = PackedStringArray([id])
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.survival_warmup_seconds = 300.0
	config.wanderer_density = 0.0
	config.sleepers_enabled = false
	var game := ZzGame.new()
	game.config = config
	game.tick_rate = 64
	game.authoritative = true
	game.draw_world = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	for i in maxi(game.team_size(), 8):
		var p := game.add_player(StringName("u%d" % i), "B%d" % i)
		p.is_bot = true
		p.health.invulnerable = true

	game.start()
	var notes: ZzNavNotes = game.horde.notes
	var ticks := 0

	while notes.state < ZzNavNotes.State.READY and ticks < 20000:
		game.simulate(TICK)
		ticks += 1

		if ticks % 8 == 0:
			await get_tree().physics_frame

	var settle := int(float(_arg("seconds", "40")) * 64.0)

	for i in settle:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	print(notes.describe())
	var team: Array[Vector3] = []

	for p in game.survivors():
		team.append(p.feet())

	# The picture of the layer: its own node, so the level can be hidden under it.
	var layer := Node3D.new()
	add_child(layer)
	var debug := DotNpcAiNavDebug.new()
	layer.add_child(debug)
	debug.show_annotations(notes.annotations)
	var lines := ImmediateMesh.new()
	var drawn := MeshInstance3D.new()
	drawn.mesh = lines
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	drawn.material_override = mat
	layer.add_child(drawn)
	lines.surface_begin(Mesh.PRIMITIVE_LINES)

	for route in notes.routes:
		for k in range(1, route.size()):
			_line(lines, route[k - 1] + Vector3.UP * 0.5, route[k] + Vector3.UP * 0.5, Color(1.0, 0.9, 0.2, 0.5))

	for c in notes.chokes:
		var hold: Vector3 = c["hold"]
		_line(lines, c["at"] + Vector3.UP * 0.3, hold + Vector3.UP * 0.3, Color(0.2, 1.0, 0.3))
		_cross(lines, hold + Vector3.UP * 0.3, 1.2, Color(0.2, 1.0, 0.3))

	for at in team:
		_cross(lines, at + Vector3.UP * 0.2, 0.7, Color(0.3, 0.6, 1.0))

	lines.surface_end()
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	game.map.visible = false
	var box := AABB(team[0], Vector3.ZERO)

	for c in notes.all_chokes:
		box = box.expand(c["at"])

	for at in team:
		box = box.expand(at)

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(box.size.x / 1.7, box.size.z) * 1.25 + 8.0
	camera.position = box.get_center() + Vector3(0.0, 60.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _save("%s_top.png" % out)

	# Close: behind the first held choke, the level back.
	game.map.visible = true
	layer.visible = false
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 70.0
	var look: Vector3 = notes.chokes[0]["at"]
	var hold: Vector3 = notes.chokes[0]["hold"]
	var back := (hold - look).normalized()
	camera.position = hold + back * 5.0 + Vector3(0.0, 3.2, 0.0)
	camera.look_at(look + Vector3(0.0, 1.0, 0.0))
	var bodies := Node3D.new()
	add_child(bodies)

	for at in team:
		var m := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.8
		m.mesh = cap
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.2, 0.5, 1.0)
		m.material_override = bm
		m.position = at + Vector3(0.0, 0.9, 0.0)
		bodies.add_child(m)

	await _save("%s_hold.png" % out)
	get_tree().quit()


func _save(path: String) -> void:
	for i in 4:
		await get_tree().process_frame

	var image := get_viewport().get_texture().get_image()
	var _saved := image.save_png(path)
	print("wrote ", path, " ", image.get_size())


func _line(mesh: ImmediateMesh, a: Vector3, b: Vector3, colour: Color) -> void:
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(colour)
	mesh.surface_add_vertex(b)


func _cross(mesh: ImmediateMesh, at: Vector3, size: float, colour: Color) -> void:
	_line(mesh, at + Vector3(-size, 0.0, 0.0), at + Vector3(size, 0.0, 0.0), colour)
	_line(mesh, at + Vector3(0.0, 0.0, -size), at + Vector3(0.0, 0.0, size), colour)
	_line(mesh, at, at + Vector3(0.0, size * 2.0, 0.0), colour)
