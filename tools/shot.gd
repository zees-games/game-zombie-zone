extends Node

## Renders the game and saves a frame. The check no assertion in this repository makes.
## See `tools/shot.sh` for the views. Any `--zz-*` is the game's own configuration.

const ZzClient := preload("../game/zz_client.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")

var _view := "survivor"
var _seconds := 3.0
var _board := false
var _out := "res://screenshots/shot.png"
var _at := Vector3.INF
var _look := Vector3.INF
var _spawn: Array = []
var _pin := &""
var _box := &""
var _client: Node = null


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			_view = arg.trim_prefix("--view=")
		elif arg == "--board":
			_board = true
		elif arg.begins_with("--seconds="):
			_seconds = arg.trim_prefix("--seconds=").to_float()
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--at="):
			_at = _v3(arg.trim_prefix("--at="))
		elif arg.begins_with("--look="):
			_look = _v3(arg.trim_prefix("--look="))
		elif arg.begins_with("--spawn="):
			for part in arg.trim_prefix("--spawn=").split(","):
				var bits := part.split(":")
				_spawn.append([StringName(bits[0]), bits[1].to_int() if bits.size() > 1 else 1])
		elif arg.begins_with("--pin="):
			_pin = StringName(arg.trim_prefix("--pin="))
		elif arg.begins_with("--box="):
			_box = StringName(arg.trim_prefix("--box="))

	_client = ZzClient.new()
	_client.name = "Client"
	_client.set("force_offline", true)
	_client.set("offline_bots", 3)
	add_child(_client)
	_run.call_deferred()


static func _v3(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()) if parts.size() == 3 else Vector3.INF


func _run() -> void:
	var game: ZzGame = _client.get("game")
	await _until_a_round(game)
	var local = _client.get("player")

	# Out of the start room, so the horde is running, and the stand-ins held where they are put.
	for player in game.survivors():
		player.is_bot = false
		player.health.invulnerable = true

	var stand := _at if _at != Vector3.INF else Vector3(0.0, 0.05, 12.0)
	local.place_at(stand, 0.0)

	var i := 0
	for player in game.survivors():
		if player != local:
			i += 1
			player.place_at(stand + Vector3(-1.6 + float(i) * 1.1, 0.0, 1.8), 0.0)

	if _look != Vector3.INF:
		_face(local, _look)

	await _seconds_of(0.4)

	for entry: Array in _spawn:
		for n in int(entry[1]):
			var at := stand + Vector3(randf_range(-3.0, 3.0), 0.0, -6.0 - randf_range(0.0, 8.0))
			var npc: DotNpcInstance = game.horde.spawn_brute(at) if entry[0] == ZzNpcs.BRUTE \
				else game.horde.spawner.spawn(entry[0], game.horde.snap_to_nav(at), &"shot", Basis(Vector3.UP, PI))
			if npc != null and npc.brain != null and entry[0] == ZzNpcs.COMMON:
				npc.brain.call(&"force_target", local.player_id)

	if _box != &"" and game.boxes != null:
		var _dropped := game.boxes.drop(_box, stand + Vector3(0.0, 0.0, -2.2))

	match _view:
		"overview":
			await _frames(6)
			var box: AABB = game.map.bounds()
			var centre := box.get_center()
			var reach := maxf(box.size.length() * 0.42, 14.0)
			_free_camera().look_at_from_position(centre + Vector3(reach * 0.45, reach * 0.6, reach * 0.55), centre)
		"room":
			await _seconds_of(_seconds)
			_free_camera().look_at_from_position(_at, _look)
		"third":
			_client.call("toggle_view")
			await _seconds_of(_seconds)
		"down":
			local.health.invulnerable = false
			var hit := DotDamage.make(0, local.entity_id, 500.0, game.combat.damage_type(&"strike"))
			var _applied = game.combat.apply_damage(hit)
			local.health.invulnerable = true
			await _seconds_of(_seconds)
		"pinned":
			var kind := _pin if _pin != &"" else &"pounce"
			var special: StringName = {&"pounce": ZzNpcs.LEAPER, &"choke": ZzNpcs.STRANGLER, &"carry": ZzNpcs.RAM, &"ride": ZzNpcs.RIDER}.get(kind, ZzNpcs.LEAPER)
			var friend = game.survivors()[1] if game.survivors()[0] == local else game.survivors()[0]
			friend.place_at(stand + Vector3(0.0, 0.0, -4.0), 180.0)
			var npc := game.horde.spawner.spawn(special, game.horde.snap_to_nav(stand + Vector3(0.0, 0.0, -14.0 if kind == &"choke" else -5.0)), &"shot")
			await _seconds_of(0.3)
			var _held := game.pins.pin(game.horde.entity_id_for(npc), npc, friend.player_id, kind)
			await _seconds_of(_seconds)
		_:
			await _seconds_of(_seconds)

	if _board:
		_client.call("_show_board", true)

	await _frames(3)
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := image.save_png(path)
	print("saved %s (%s): %s" % [_out, _view, error_string(saved)])
	get_tree().quit(0 if saved == OK else 1)


func _face(player, target: Vector3) -> void:
	var look: Vector3 = target - player.eye_position()
	var command := DotFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	player.controller.state.yaw = command.yaw
	player.controller.state.pitch = command.pitch

	if player.sampler != null:
		player.sampler.look_at_angles(command.yaw, command.pitch)


func _until_a_round(game: ZzGame) -> void:
	for _i in range(900):
		if game.phase != ZzGame.Phase.IDLE and _client.get("player") != null:
			return
		await get_tree().process_frame


func _free_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.far = 600.0
	add_child(camera)
	camera.current = true
	var hud: CanvasLayer = _client.get("hud")
	if hud != null:
		hud.visible = false
	return camera


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _seconds_of(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
