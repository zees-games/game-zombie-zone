extends Node

## The survivors' look, with nothing else in the frame: eight figures built the way the game builds a player (ZzFigure,
## a seed from a player id), in a row, shot from the front, the back and close on the heads, under a neutral light.
## The check a per-player palette needs (the first lineup was from behind only, so faces went unchecked).
##
##   tools/lineup.sh [out dir, default res://screenshots/lineup]    # lineup_front.png, lineup_back.png, lineup_heads.png
##   tools/lineup.sh --warm                                         # under the yellow light of a warm map

const ZzFigure := preload("../game/zz_figure.gd")

const COUNT := 8
const GAP := 0.9


func _ready() -> void:
	var out := "res://screenshots/lineup"
	var warm := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--warm":
			warm = true
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.53, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.92, 0.6) if warm else Color(0.8, 0.82, 0.85)
	env.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_color = Color(1.0, 0.85, 0.5) if warm else Color.WHITE
	add_child(sun)

	var atlases := ZzFigure.ATLASES
	for i in COUNT:
		var figure := ZzFigure.new()
		add_child(figure)
		figure.look_seed = hash(StringName("u%d" % (900000 + i)))
		figure.build(1.8, atlases[i % atlases.size()], Color.WHITE)
		# Standing in the row, facing +z (the camera in front of them looks along -z).
		figure.pose(Vector3((float(i) - float(COUNT - 1) * 0.5) * GAP, 0.0, 0.0), 0.0, 0.0)
		# Facing the camera: the figures face their -z by default, so turn them to +z.
		figure.rotation = Vector3(0.0, PI, 0.0)

	var camera := Camera3D.new()
	camera.fov = 40.0
	add_child(camera)
	camera.current = true

	for _i in 8:
		await get_tree().process_frame

	var reach := float(COUNT) * GAP
	camera.look_at_from_position(Vector3(0.0, 1.1, 8.5), Vector3(0.0, 0.9, 0.0))
	await _save(out + "/lineup_front.png")
	camera.look_at_from_position(Vector3(0.0, 1.1, -8.5), Vector3(0.0, 0.9, 0.0))
	await _save(out + "/lineup_back.png")
	# Heads: the four on the left, then the four on the right, from a little above the front.
	camera.fov = 22.0
	camera.look_at_from_position(Vector3(-reach * 0.25, 1.9, 5.0), Vector3(-reach * 0.25, 1.55, 0.0))
	await _save(out + "/lineup_heads_a.png")
	camera.look_at_from_position(Vector3(reach * 0.25, 1.9, 5.0), Vector3(reach * 0.25, 1.55, 0.0))
	await _save(out + "/lineup_heads_b.png")
	get_tree().quit(0)


func _save(path: String) -> void:
	for _i in 3:
		await RenderingServer.frame_post_draw
	print("saved %s: %s" % [path, error_string(get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path)))])
