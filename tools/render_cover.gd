extends Node

const ZzClient := preload("../game/zz_client.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMap := preload("../game/zz_map.gd")

## Frames of a real client on a real server, to look at: the loading cover while the server
## still holds the seat as loading, and the first frame after the cover lifts. A dedicated
## server runs in a second process (this scene with `--server`); both halves have the same
## root name because an RPC path is the name.
##
## [codeblock]
## tools/render_cover.sh
## [/codeblock]
## Writes screenshots/cover_up.png, cover_lifted.png and cover_after_1s.png.
##
## Modes (`tools/render_cover.sh join|change|slow|all`, user arg `mode=<name>`):
## [br]- join: the default above.
## [br]- change: a connected client sits through the server's map change (Practice Street to the
## Abandoned Mall) and every frame across the transition is measured.
## [br]- slow: the client joins through a lossy, delaying UDP relay (dot_net_udp_relay.gd) and the
## server stalls 3 s on its next map build, then the same map change runs on that link.
## [br]Every frame is measured (see [method _measure]); the frames that matter (cover up, the last
## covered frame, the frames right after each lift, +1 s) are written to
## screenshots/cover_<mode>/NN_label.png to be looked at. After a lift, a frame outside the built
## map, below its kill height, with an undrawn world, near black, or a map swapped under an open
## gate, or a survivor that jumps, is a FAIL and the run exits 1.

const PORT := 27399
const RELAY_PORT := 27409
const FIRST_MAP := &"zz_practice"
const SECOND_MAP := &"zm_abandoned_mall"
## The server's stall on its second map build in the slow mode, milliseconds.
const STALL_MS := 3000

var _mode := "join"
var _dir := ""
var _shots := 0
var _fails: PackedStringArray = []
var _frame := 0
var _lifted_at := -1
var _was_open := false
var _prev_covered: Image = null
var _prev_map := &""
var _prev_pos := Vector3.ZERO
var _open_frames := 0
var _client: Node = null
var _gate: DotLoadGate = null

var _server_pid := -1


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("mode="):
			_mode = a.get_slice("=", 1)
	if "server" in OS.get_cmdline_user_args():
		_serve.call_deferred()
	else:
		_run.call_deferred()


func _serve() -> void:
	var data := "user://render_cover_server"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data))
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 3
	config.map_ids = PackedStringArray([String(FIRST_MAP), String(SECOND_MAP)])
	var game := ZzGame.new()
	game.name = "World"
	game.config = config
	game.tick_rate = 60
	add_child(game)
	if _mode == "slow":
		# A slow build: the second clearing blocks the server's loop for seconds, as a heavy build does.
		var builds := [0]
		game.world_clearing.connect(func() -> void:
			builds[0] += 1
			if builds[0] > 1:
				OS.delay_msec(STALL_MS))

	var server_config := DotServerConfig.new()
	server_config.hostname = "render cover"
	server_config.port = PORT
	server_config.query_port = PORT + 1
	server_config.bind_address = "127.0.0.1"
	server_config.rcon_password = ""
	server_config.admins_path = "%s/admins.json" % data
	server_config.bans_path = "%s/bans.json" % data
	server_config.audit_log_path = "%s/audit.jsonl" % data
	server_config.hibernate_when_empty = false
	server_config.startup_config = ""
	server_config.autoexec_config = ""
	server_config.stdin_console_enabled = false
	server_config.log_level = "error"
	var server := DotServer.new()
	server.name = "Server"
	server.config = server_config
	server.config_file = ""
	server.auto_boot = false
	add_child(server)
	var booted: DotResult = await server.boot()
	if not booted.ok:
		printerr("render_cover server: ", booted.error)
		get_tree().quit(1)
		return
	var loaded: DotResult = await server.modules.load_module("res://game/zz_module.gd")
	if not loaded.ok:
		printerr("render_cover server: ", loaded.error)
		get_tree().quit(1)
		return
	if StringName(str(game.map_doc.get("id", ""))) != FIRST_MAP:
		var _first: DotResult = game.change_map_now(FIRST_MAP)
	print("render_cover server: ready on %d, map %s" % [PORT, game.map_doc.get("id", "?")])
	# The client asks for the map change by writing this file; the server obeys it once.
	var trigger := ProjectSettings.globalize_path("%s/change.txt" % data)
	while true:
		await get_tree().create_timer(0.1).timeout
		if FileAccess.file_exists(trigger):
			var _gone := DirAccess.remove_absolute(trigger)
			var changed: DotResult = game.change_map_now(SECOND_MAP)
			print("render_cover server: change_map_now ok=", changed.ok)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshots/%s.png" % name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("render_cover: %s %s" % [path, image.save_png(path)])


func _run() -> void:
	_dir = "cover_%s" % _mode
	var out := ProjectSettings.globalize_path("res://screenshots/%s" % _dir)
	DirAccess.make_dir_recursive_absolute(out)
	for old in DirAccess.get_files_at(out):
		var _rm := DirAccess.remove_absolute("%s/%s" % [out, old])
	var data := ProjectSettings.globalize_path("user://render_cover_server")
	DirAccess.make_dir_recursive_absolute(data)
	_server_pid = OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://tools/render_cover.tscn", "--", "server", "mode=%s" % _mode]))
	await get_tree().create_timer(8.0).timeout

	var port := PORT
	var relay: RefCounted = null
	if _mode == "slow":
		relay = (load("res://addons/dot_net/testing/dot_net_udp_relay.gd") as GDScript).new()
		relay.set(&"threaded", true)
		relay.call(&"set_impairment", true, 0.05, 150.0, 40.0)
		relay.call(&"set_impairment", false, 0.08, 250.0, 80.0)
		var started: DotResult = relay.call(&"start", RELAY_PORT, "127.0.0.1", PORT)
		print("render_cover: relay ", started.ok)
		port = RELAY_PORT

	var link := DotClientLink.new()
	link.name = "Server"
	link.player_name = "Cover"
	link.transport_preference = "udp"
	link.udp_address = "127.0.0.1:%d" % port
	add_child(link)
	link.connect_to_server("127.0.0.1:%d" % port)
	var t := 0.0
	while not link.is_playing() and t < 90.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	print("render_cover: playing after %.1f s" % t)

	_client = ZzClient.new()
	add_child(_client)
	for i in 3:
		await get_tree().process_frame
	_gate = _client.get("gate")
	if _gate != null:
		_gate.closed.connect(func() -> void: print("render_cover: gate CLOSED at frame %d for %s" % [_frame, _gate.reasons()]))
	var g: ZzGame = _client.get("game")
	if g != null:
		g.world_clearing.connect(func() -> void: print("render_cover: world_clearing at frame %d" % _frame))
		g.world_rebuilt.connect(func() -> void: print("render_cover: world_rebuilt at frame %d" % _frame))
	print("render_cover: gate open at the first shot: ", _gate.is_open() if _gate != null else "no gate")

	# The join: from the first frame to 90 frames after the cover lifts.
	var lifts := 0
	await _observe(func() -> bool: return _open_frames >= 40, 150.0)
	lifts += 1
	await _shot_now("after_1s")
	if _mode == "join":
		await _observe(func() -> bool: return _open_frames >= 150, 150.0)
	print("render_cover: lifted at frame %d, map %s" % [_lifted_at, _map_id()])

	if _mode != "join":
		# The map change with the client connected (and on the slow link when slow).
		var trigger := "%s/change.txt" % data
		var f := FileAccess.open(trigger, FileAccess.WRITE)
		f.store_string("go")
		f.close()
		_open_frames = 0
		var t_change := Time.get_ticks_msec()
		await _observe(func() -> bool: return _map_id() == SECOND_MAP and _open_frames >= 40, 240.0)
		print("render_cover: map is %s after %.1f s" % [_map_id(), (Time.get_ticks_msec() - t_change) / 1000.0])
		if _map_id() != SECOND_MAP:
			_fails.append("the map never changed to %s" % SECOND_MAP)
		await get_tree().create_timer(1.0).timeout
		await _shot_now("change_after_1s")

	link.disconnect_from_server("done")
	if relay != null:
		relay.call(&"stop")
	if _server_pid > 0:
		var _k := OS.kill(_server_pid)
	for fail in _fails.slice(0, 12):
		printerr("render_cover FAIL: ", fail)
	print("render_cover: %s %s (%d frames measured, %d shots)" % [_mode, "FAILED" if not _fails.is_empty() else "clean", _frame, _shots])
	get_tree().quit(1 if not _fails.is_empty() else 0)


func _map_id() -> StringName:
	var game: Object = _client.get("game")
	if game == null or game.get("map") == null:
		return &""
	return (game.get("map") as ZzMap).id()


## Draws frames until [param done] or [param limit] seconds, measuring each one.
func _observe(done: Callable, limit: float) -> void:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < int(limit * 1000.0):
		await RenderingServer.frame_post_draw
		await _measure()
		if done.call():
			return
	_fails.append("timed out after %.0f s in %s" % [limit, _mode])


## One drawn frame: the gate's state, what the camera sees, and (after a lift) the checks that say
## whether a player could see the void.
func _measure() -> void:
	_frame += 1
	var open := _gate != null and _gate.is_open()
	var image := get_viewport().get_texture().get_image()
	var small := image.duplicate() as Image
	small.resize(32, 18, Image.INTERPOLATE_BILINEAR)
	var luma := 0.0
	for y in 18:
		for x in 32:
			luma += small.get_pixel(x, y).get_luminance()
	luma /= 576.0

	var map_id := _map_id()
	var player: Node3D = _client.get("player")
	var cam: Camera3D = _client.get("camera")
	var game: ZzGame = _client.get("game")
	var pos := cam.global_position if cam != null and cam.is_inside_tree() else Vector3.INF

	if _prev_map != &"" and map_id != _prev_map and open:
		_fails.append("frame %d: the map swapped from %s to %s under an open gate" % [_frame, _prev_map, map_id])
	_prev_map = map_id

	var label := ""
	if open and not _was_open:
		_lifted_at = _frame
		_open_frames = 0
		if _prev_covered != null:
			_save(_prev_covered, "last_covered")
		label = "lift_0"
		_prev_pos = pos
	elif not open and _was_open:
		label = "cover_up"
		print("render_cover: cover back at frame %d (%d open frames) for %s, survivor placed: %s" % [_frame, _open_frames, _gate.reasons(), _client.call(&"_is_placed")])
	elif not open and _frame <= 3:
		label = "first_frames"
	if open:
		_open_frames += 1
		if label == "" and _open_frames in [2, 3, 6, 30]:
			label = "open_%d" % (_open_frames - 1)
		var why := _gap(game, cam, player, pos, luma)
		if player != null and _prev_pos.is_finite() and pos.is_finite() and pos.distance_to(_prev_pos) > 1.5:
			why += " camera jumped %.1f m in one frame;" % pos.distance_to(_prev_pos)
		if why != "":
			_fails.append("frame %d (open %d): %s luma %.3f cam %s" % [_frame, _open_frames, why, luma, pos])
			if label == "" and _fails.size() <= 6:
				label = "FAIL"
		_prev_pos = pos
	else:
		_prev_covered = image
	if label != "":
		_save(image, label)
	_was_open = open


## What is wrong with an open frame, or "".
func _gap(game: ZzGame, cam: Camera3D, player: Node3D, pos: Vector3, luma: float) -> String:
	var why := ""
	if game == null or game.map == null or player == null or cam == null or not pos.is_finite():
		return "no map, survivor or camera;"
	var bounds := game.map.bounds()
	if pos.y <= game.map.kill_height() or (bounds.size != Vector3.ZERO and not bounds.grow(8.0).has_point(pos)):
		why += " camera outside the built map %s;" % bounds
	if str(game.map.doc.get("world", "")) != "" and not game.map.world_drawn:
		why += " world not drawn;"
	if luma < 0.02:
		why += " near black;"
	if _gate.reasons().size() > 0:
		why += " holds %s;" % [_gate.reasons()]
	return why


func _save(image: Image, label: String) -> void:
	_shots += 1
	var path := ProjectSettings.globalize_path("res://screenshots/%s/%02d_%s.png" % [_dir, _shots, label])
	print("render_cover: %s f%d %s" % [path.get_file(), _frame, image.save_png(path)])


func _shot_now(label: String) -> void:
	await RenderingServer.frame_post_draw
	_save(get_viewport().get_texture().get_image(), label)
