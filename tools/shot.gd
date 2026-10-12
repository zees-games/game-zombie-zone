extends Node

## Renders the game and saves a frame. The check no assertion in this repository makes.
## See `tools/shot.sh` for the views. Any `--zz-*` is the game's own configuration.

const ZzClient := preload("../game/zz_client.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

var _view := "survivor"
var _seconds := 3.0
var _board := false
var _out := "res://screenshots/shot.png"
var _at := Vector3.INF
var _look := Vector3.INF
var _spawn: Array = []
var _pin := &""
var _pin_me := false
var _box := &""
var _client: Node = null
var _weapons: PackedStringArray = PackedStringArray()


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
		elif arg == "--pin-me":
			_pin_me = true
		elif arg.begins_with("--weapons="):
			_weapons = arg.trim_prefix("--weapons=").split(",", false)
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
		"hit":
			# Two hits the server confirms on the zombie nearest the crosshair, the second a kill to the head,
			# through dot-combat as a shot would go: the marker and the numbers the client draws
			# for them. Hurt, with borrowed health over the real, and an objective being held, so
			# the vitals' bonus and the hold-out clock are in the frame too.
			await _seconds_of(maxf(_seconds - 0.5, 0.5))
			# The one nearest the line of sight (straight ahead is -Z), so the number is on screen.
			var nearest: DotNpcInstance = null
			var off := INF
			for npc: DotNpcInstance in game.horde.spawner.all_npcs():
				var to := npc.position() - stand
				if npc.is_alive() and to.z < -1.0 and absf(to.x / to.z) < off:
					off = absf(to.x / to.z)
					nearest = npc
			if nearest != null:
				var victim: int = game.horde.entity_id_for(nearest)
				var first := DotDamage.make(local.entity_id, victim, 18.0, null)
				first.point = nearest.position() + Vector3(0.0, 1.2, 0.0)
				var _a = game.combat.apply_damage(first)
				var second := DotDamage.make(local.entity_id, victim, 400.0, null)
				second.point = nearest.position() + Vector3(0.0, 1.6, 0.0)
				second.hit_group = DotHitGroup.HEAD
				var _b = game.combat.apply_damage(second)
			local.health.invulnerable = false
			local.health.health = 55.0
			local.temp_health = 25.0
			var objectives: Array = game.map_doc.get("objectives", [])
			if not objectives.is_empty():
				var index := maxi(game.current_objective(), 0)
				game.objective_states[index] = &"holding"
				game.objective_progress[index] = game.now() + 45.0
			await _seconds_of(0.12)
		"weapons":
			await _weapon_sheets(game, local)
			get_tree().quit(0)
			return
		"pinned":
			var kind := _pin if _pin != &"" else &"pounce"
			var special: StringName = {&"pounce": ZzNpcs.LEAPER, &"choke": ZzNpcs.STRANGLER, &"carry": ZzNpcs.RAM,
				&"ride": ZzNpcs.RIDER, &"grab": ZzNpcs.CRAWLER}.get(kind, ZzNpcs.LEAPER)
			# --pin-me: the special takes you, which is what the lens drawing is for.
			var friend = local if _pin_me else (game.survivors()[1] if game.survivors()[0] == local else game.survivors()[0])
			if not _pin_me:
				friend.place_at(stand + Vector3(0.0, 0.0, -4.0), 180.0)
			var npc := game.horde.spawner.spawn(special, game.horde.snap_to_nav(stand + (Vector3(3.5, 0.0, -14.0) if kind == &"choke" else Vector3(0.0, 0.0, -5.0))), &"shot")
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


## One contact sheet per weapon, through the real client and the real buttons: at the hip, two
## and six frames into a shot, and the reload at 15/25/40/50/57/75/88% by the drawn rig's own fraction,
## each tile labelled with the HUD's count. `_out` is the directory (`sheet_<id>.png` in it).
## What `--view=weapons --weapons=all` is for: a counter that never moves and a reload that is
## a single tilt are both things only a picture says.
func _weapon_sheets(game: ZzGame, local) -> void:
	var ids: Array[StringName] = []
	if _weapons.is_empty() or _weapons[0] == "all":
		for def in ZzWeapons.all_defs():
			if def.uses_magazine():
				ids.append(def.id)
	else:
		for id in _weapons:
			ids.append(StringName(id))

	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(24.0, 70.0)
	label.add_theme_font_size_override(&"font_size", 34)
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 8)
	layer.add_child(label)
	var dir := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(dir)

	for id in ids:
		var def := ZzWeapons.def_of(id)
		if def == null or not game.arm(local, id):
			print("skipped %s: not armed" % id)
			continue
		_client.set("_slot", def.slot)
		var rig: ZeeWeaponRig = local.view_rig
		var tiles: Array[Image] = []
		await _seconds_of(1.2)
		tiles.append(await _tile(label, id, "hip"))
		_client.set("_firing", true)
		await _frames(2)
		tiles.append(await _tile(label, id, "fire +2"))
		await _frames(4)
		tiles.append(await _tile(label, id, "fire +6"))
		_client.set("_firing", false)
		await _seconds_of(0.6)
		# Down to one round on both rigs, so the reload is a whole one (a shell-at-a-time gun loads
		# several), not the one round the shots above spent.
		for held in [local.weapons, rig]:
			if held != null and held.arsenal.current() != null:
				held.arsenal.current().magazine = mini(1, held.arsenal.current().magazine)
		_client.set("_reloading", true)
		await _frames(2)
		_client.set("_reloading", false)
		for target in [0.15, 0.25, 0.4, 0.5, 0.57, 0.75, 0.88]:
			var waited := 0
			while rig != null and rig.arsenal.is_reloading() and rig._reload_fraction(rig._last_tick) < target and waited < 2000:
				await get_tree().process_frame
				waited += 1
			tiles.append(await _tile(label, id, "reload %d%%%s" % [int(target * 100.0), "" if rig.arsenal.is_reloading() else " (not reloading)"]))
		var sheet := Image.create(640 * 5, 360 * 2, false, Image.FORMAT_RGB8)
		for n in tiles.size():
			var tile := tiles[n]
			tile.resize(640, 360, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(tile, Rect2i(0, 0, 640, 360), Vector2i((n % 5) * 640, (n / 5) * 360))
		var path := dir.path_join("sheet_%s.png" % id)
		print("saved %s: %s" % [path, error_string(sheet.save_png(path))])


func _tile(label: Label, id: StringName, what: String) -> Image:
	var hud = _client.get("hud")
	label.text = "%s · %s · HUD %s" % [id, what, hud.ammo.count_text() if hud != null else "?"]
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


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
