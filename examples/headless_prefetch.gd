extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzPaths := preload("../game/zz_paths.gd")
const MapThreads := preload("res://addons/dot_game/runtime/dot_game_map_threads.gd")

## A drawn world awaits dot-map's texture prefetch without stopping the main thread: the map reaches "built" with frames advancing, and a baked texture is preferred when present and a plain decode used otherwise.
##
## [codeblock]
## godot --headless --path . res://examples/headless_prefetch.tscn
## [/codeblock]

const MAP := &"zm_lila_panic"
const SECTIONS := 2
const CHECKS := 10

var _entered := 0
var _finished := 0
var _checks := CHECKS


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	await _test_world()
	_test_baked()
	_report_sections(_entered, _finished, SECTIONS, _checks)


func _test_world() -> void:
	_entered += 1
	if not ZzMap.can_draw_world() or not FileAccess.file_exists(ZzPaths.rebase(ZzMap.LOCAL_WORLD % ["zz_world_zm_lila_panic", String(MAP)]) + ".json"):
		print("SKIPPED: %s's world is not linked (run dot-bootstrap)" % MAP)
		_checks -= 6
		_finished += 1
		return
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(MAP)])
	var game := ZzGame.new()
	game.config = config
	game.authoritative = true
	game.draw_world = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().process_frame
	_check(game.map_builds == 1, "the map builds once before its world", str(game.map_builds))

	var frames := [0]
	var counter := func() -> void: frames[0] += 1
	get_tree().process_frame.connect(counter)
	var before := MapThreads.current()
	var _on := MapThreads.apply(-1)
	var started := Time.get_ticks_msec()
	var res: DotResult = await game.map.load_world()
	var took := Time.get_ticks_msec() - started
	get_tree().process_frame.disconnect(counter)
	var _off := MapThreads.apply(before)
	_check(res.ok and res.value == true and game.map.world_drawn, "the world is drawn", "%s" % [res.error.message if not res.ok else res.value])
	_check(game.map_builds == 1, "drawing the world does not rebuild the map", str(game.map_builds))
	_check(frames[0] >= 1 or took < 100, "the tree kept running while it loaded", "%d frames in %d ms" % [frames[0], took])
	game.queue_free()
	await get_tree().process_frame
	_finished += 1
	await _test_concurrent(config)


## Two loads in one frame (the client's draw and a tool's own call) draw one World and run the extras once.
func _test_concurrent(config: ZzConfig) -> void:
	var game := ZzGame.new()
	game.config = config
	game.authoritative = true
	game.draw_world = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().process_frame
	var both := [0]
	var load_one := func() -> void:
		var r: DotResult = await game.map.load_world()
		both[0] += 1 if r.ok else 0
	load_one.call()
	load_one.call()
	while both[0] < 2:
		await get_tree().process_frame
	for i in 8:
		await get_tree().process_frame
	var worlds := game.map._drawn.get_children().filter(func(c: Node) -> bool: return String(c.name).contains("World"))
	_check(worlds.size() == 1, "two concurrent loads attach one World", str(worlds.size()))
	_check(game.map.extras_runs == 1, "two concurrent loads run the extras once", str(game.map.extras_runs))
	game.queue_free()
	await get_tree().process_frame


func _test_baked() -> void:
	_entered += 1
	var dir := "user://prefetch_check"
	DirAccess.make_dir_recursive_absolute(dir)
	var png := dir.path_join("albedo.png")
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.8, 0.3, 0.1))
	var _saved := img.save_png(png)
	var surfaces := DotMapSurfaces.new("res://addons/dot_map/surfaces")
	var variant := DotMapSurfaces.baked_variant()
	_check(surfaces.call(&"_baked_texture", png) == null, "with no baked file the plain decode is used")
	var baked := DotMapTextureBake.bake_file(png, dir.path_join("albedo"), 0)
	_check(baked.ok, "a texture bakes", "" if baked.ok else baked.error.message)
	if variant == "":
		print("SKIPPED: this renderer has no VRAM format; baked textures are read only where one exists")
		_checks -= 1
	else:
		_check(surfaces.call(&"_baked_texture", png) != null, "a baked file is preferred when present")
	_check(surfaces.call(&"_file_texture", png) != null, "the texture loads either way")
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	_finished += 1
