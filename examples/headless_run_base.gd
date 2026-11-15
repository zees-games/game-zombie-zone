extends "headless_run_helpers.gd"

## The menu, client, hud and first-play sections of [headless_run.gd] and its helpers, split off to keep each file under the size gate.


const ZzBindings := preload("../game/zz_bindings.gd")
const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzClient := preload("../game/zz_client.gd")
const ZzEndCameraRules := preload("../game/zz_end_camera_rules.gd")
const ZzHud := preload("../game/zz_hud.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzSettings := preload("../game/zz_settings.gd")
const ZzBlood := preload("../game/zz_blood.gd")
## In the street, clear of the cars: where a fight is staged.
const STREET := Vector3(0.0, 0.05, 14.0)
var _sections_entered := 0
## Every SCRIPT ERROR the engine prints while the suite runs: a runtime one (a call to a method
## the object lacks) aborts only its function, prints, and changes no exit code, so a client
## that errs every frame would otherwise pass. The run fails on any.
var _script_errors := ScriptErrors.new()
var _sections_finished := 0
# --- Helpers -----------------------------------------------------------------------

## The family's rule since the first play test: H opens help in every game, nothing else in
## the table is on H, and the Escape menu has Help & commands and Leave.
func _test_help_and_menu() -> void:
	_section("H opens help, and the Escape menu has Help and Leave")
	var settings := ZzSettings.new()
	add_child(settings)
	var built := settings.setup(DotSettingsStoreMemory.new())
	var keys := settings.bindings
	_check(built.ok and keys != null and keys.key_for(DotMenuBindings.HELP_ACTION) == "H", "help is on H")
	_check(keys.defaults_on("H").size() == 1, "and nothing else in the table defaults to H (the medkit is on G)",
		str(keys.defaults_on("H").map(func(r: Dictionary) -> String: return str(r["label"]))))
	# The right mouse button aims down the sights (the family's Aim row); the shove is on T.
	_check(keys.key_for(ZzBindings.AIM) == "Mouse 2" and keys.defaults_on("Mouse 2").size() == 1
		and keys.key_for(ZzBindings.SHOVE) == "T", "aim is the only row on the right mouse button, the shove is on T",
		"%s %s %d" % [keys.key_for(ZzBindings.AIM), keys.key_for(ZzBindings.SHOVE), keys.defaults_on("Mouse 2").size()])
	# Chat is two rows, so help lists Y and U and the Controls page moves them.
	var _t := settings.settings.set_value(&"bind_chat", "T")
	_check(keys.key_for(ZzBindings.CHAT) == "T" and DotInputBinding.describe_action(ZzBindings.CHAT) == "T"
		and keys.key_for(ZzBindings.CHAT_TEAM) == "U", "chat (Y) and team chat (U) are rows: rebinding one moves its key",
		"%s %s" % [keys.key_for(ZzBindings.CHAT), keys.key_for(ZzBindings.CHAT_TEAM)])
	var h := InputEventKey.new()
	h.physical_keycode = KEY_H
	h.keycode = KEY_H
	h.pressed = true
	_check(settings.menu.handle_event(h) and settings.menu.help.is_open(), "H opens the help screen")
	_check(settings.menu.help.about != "" and settings.menu.help.heading() == "How to play Zombie Zone",
		"which says what the game is before the keys")
	settings.menu.help.close()
	settings.open()
	var help_button := settings.menu.screen.find_child("Action_help", true, false) as Button
	var leave_button := settings.menu.screen.find_child("Action_leave", true, false) as Button
	_check(help_button != null and leave_button != null and leave_button.visible,
		"the Escape menu has Help & commands and Leave")
	settings.close()
	# The document and the extra rows the game's spec declares, in the order they always had.
	var sk := settings.schema.keys()
	var want_keys: Array[StringName] = [&"field_of_view", &"reduce_motion", &"gore", &"crowd_detail", &"vis_mode", &"cl_legs", &"ambient", &"ambient_volume", &"ambient_frequency"]
	_check(sk.slice(0, 9) == want_keys, "the document starts with the game's own settings, in order", str(sk.slice(0, 9)))
	_check(settings.settings.get_int(&"crowd_detail", -1) == 1 and settings.settings.get_int(&"vis_mode", -1) == 3
		and settings.schema.find(&"field_of_view").default_value == ZzSettings.DEFAULT_FOV and not settings.schema.has(&"shake_scale"),
		"with the defaults and the stock keys it leaves out")
	var img := settings.menu.page(&"video").find_section(&"image")
	var amb := settings.menu.page(&"audio").find_section(&"ambience")
	var comfort := settings.menu.page(&"general").find_section(&"comfort")
	_check(img != null and img.find_row(&"crowd_detail") != null and img.find_row(&"vis_mode") != null
		and amb != null and amb.find_row(&"ambient") != null and amb.find_row(&"ambient_volume") != null and amb.find_row(&"ambient_frequency") != null
		and comfort != null and comfort.find_row(&"reduce_motion") != null,
		"and its crowd detail, culling, ambience and reduce motion rows")
	_check(settings.applier.fov_transform.is_valid(), "and the camera takes the horizontal field of view converted")
	settings.queue_free()
	await get_tree().process_frame

	await _check_old_settings_document()
	_finished()



## A settings file saved before the keys moved still loads, and keeps what the player chose.
func _check_old_settings_document() -> void:
	# A document saved when the medkit was on H and the shove on V: they follow their new
	# defaults, help keeps H, and a key the player chose stays where they put it.
	var old_doc := DotSettingsStoreMemory.new()
	var _saved := old_doc.save_document(ZzSettings.APP_NAMESPACE, &"local", {"version": 1, "values": {
		"bind_heal": "H", "bind_help": "H", "bind_shove": "V", "bind_use": "J", "field_of_view": 92,
		"crowd_detail": 2, "vis_mode": 1, "ambient_frequency": 0.5, "gore": false, "reduce_motion": true, "sfx_volume": 0.3,
	}})
	var returning := ZzSettings.new()
	add_child(returning)
	var _r := returning.setup(old_doc, false)
	var rk: DotMenuBindings = returning.bindings
	_check(rk.key_for(ZzBindings.HEAL) == "G" and rk.key_for(DotMenuBindings.HELP_ACTION) == "H",
		"an old settings file with the medkit on H: the medkit moves to G, help keeps H",
		"%s %s" % [rk.key_for(ZzBindings.HEAL), rk.key_for(DotMenuBindings.HELP_ACTION)])
	_check(rk.key_for(ZzBindings.SHOVE) == "T" and rk.key_for(ZzBindings.USE) == "J",
		"the shove leaves V for push to talk (it moves to T), and a key the player chose is kept",
		"%s %s" % [rk.key_for(ZzBindings.SHOVE), rk.key_for(ZzBindings.USE)])
	# The rest of a v1 file loads as it was saved: only the field of view is dropped.
	var rs := returning.settings
	_check(rs.get_int(&"crowd_detail", -1) == 2 and rs.get_int(&"vis_mode", -1) == 1 and absf(rs.get_float(&"ambient_frequency", -1.0) - 0.5) < 0.001
		and not rs.get_bool(&"gore", true) and rs.get_bool(&"reduce_motion", false) and absf(rs.get_float(&"sfx_volume", -1.0) - 0.3) < 0.001,
		"a v1 settings file keeps its other values (crowd detail, culling, ambience, gore, reduce motion, volume)")
	var fov_cam := Camera3D.new()
	returning.add_child(fov_cam)
	returning.bind_camera(fov_cam)
	_check(returning.settings.get_int(&"field_of_view", 0) == ZzSettings.DEFAULT_FOV,
		"a v1 file's vertical field of view is dropped for the new default",
		str(returning.settings.get_int(&"field_of_view", 0)))
	var wide := 2.0 * atan(tan(deg_to_rad(fov_cam.fov * 0.5)) * 16.0 / 9.0)
	_check(absf(rad_to_deg(wide) - 100.0) < 1.5,
		"the default field of view is about 100 degrees across a 16:9 window", "%.1f" % rad_to_deg(wide))
	var _w := returning.settings.set_value(&"field_of_view", 70)
	_check(absf(fov_cam.fov - DotMenuApplier.vertical_from_horizontal_4_3(70.0)) < 0.01,
		"the slider is horizontal degrees at 4:3, converted for the camera", "%.2f" % fov_cam.fov)
	returning.queue_free()
	await get_tree().process_frame


## The family's rule since the first play test: M opens the map list, and solo a choice
## changes it now. The server's half (the owner's flag, the vote) is in `dedicated` and dot-vote.
func _test_the_map_menu() -> void:
	_section("M opens the map list, and solo a choice changes it")
	var game := await _world(func(c: ZzConfig) -> void: c.map_ids = PackedStringArray())
	var _a := game.add_player(&"u1", "Ada")
	var _b := game.add_player(&"u2", "Bo")
	game.start()
	for _i in 4:
		game.simulate(TICK)
		await get_tree().physics_frame
	var settings := ZzSettings.new()
	add_child(settings)
	var _built: DotResult = settings.setup(DotSettingsStoreMemory.new())
	var keys: DotMenuBindings = settings.bindings
	var image := settings.menu.page(&"video").find_section(&"image")
	var gore_row: DotMenuRow = image.find_row(&"gore") if image != null else null
	_check(gore_row != null and gore_row.row_id() == &"gore" and settings.schema.has(&"gore"),
		"the Video page's Image section has a Blood splatters row on the gore setting")
	_check_gore_persist()
	_check(keys.key_for(DotMenuBindings.MAPS_ACTION) == "M" and keys.defaults_on("M").size() == 1,
		"the map menu is on M, and nothing else in the table defaults to M",
		str(keys.defaults_on("M").map(func(r: Dictionary) -> String: return str(r["label"]))))
	var rows: Array = game.map_rows()
	_check(rows.size() > 1 and rows.filter(func(r: Dictionary) -> bool: return bool(r["current"])).size() == 1,
		"there is more than one to choose, the one playing marked", "%d" % rows.size())
	var _maps := settings.use_maps(game.map_rows, game.change_map_now)
	var m := InputEventKey.new()
	m.physical_keycode = KEY_M
	m.keycode = KEY_M
	m.pressed = true
	_check(settings.menu.handle_event(m) and settings.menu.picker.is_open(), "M opens the picker")
	var wanted: StringName = &""
	var key := KEY_NONE
	for row in range(1, DotMenuPicker.PAGE_SIZE + 1):
		var it: Variant = settings.menu.picker.at_row(row)
		if it is Dictionary and not bool((it as Dictionary)["current"]):
			wanted = StringName(str((it as Dictionary)["id"]))
			key = KEY_0 + row
			break
	var digit := InputEventKey.new()
	digit.physical_keycode = key
	digit.keycode = key
	digit.pressed = true
	var _k := settings.menu.handle_event(digit)
	for _i in 4:
		await get_tree().physics_frame
	_check(wanted != &"" and game.map.id() == wanted, "choosing one changes to it now", "%s, now %s" % [wanted, game.map.id()])
	_check(not settings.menu.picker.is_open(), "and the picker is closed")
	settings.queue_free()
	await get_tree().process_frame
	_finished()


## Gore off survives a save and a fresh settings manager, and reaches the decals.
func _check_gore_persist() -> void:
	# Gore persists: toggled off, flushed to a real file store in this process's scratch directory, read back by a fresh instance.
	var scratch := DotSettingsScratch.use("headless_gore_persist")
	var first := ZzSettings.new()
	first.directory = scratch
	add_child(first)
	var _b1 := first.setup(DotSettingsStoreFile.new(scratch), false)
	var _g2 := first.settings.set_value(&"gore", false)
	var flushed := first.settings.flush()
	_check(flushed.ok and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(scratch)) and not DirAccess.get_files_at(scratch).is_empty(),
		"turning Blood splatters off and saving writes the settings file", str(flushed.error.message if not flushed.ok else ""))
	var second := ZzSettings.new()
	second.directory = scratch
	add_child(second)
	var _b2 := second.setup(DotSettingsStoreFile.new(scratch), false)
	_check(second.settings.get_bool(&"gore", true) == false,
		"a fresh settings manager loading that file reads gore as off")
	var blood := ZzBlood.new()
	add_child(blood)
	blood.apply_settings(second.settings)
	_check(not blood.decals.config.gore, "and the blood decals' config sees gore off")
	_check(blood.decals.splatter(Vector3.ZERO, Vector3.UP) == null, "so a hit draws no splatter")
	var _g3 := second.settings.set_value(&"gore", true)
	blood.apply_settings(second.settings)
	_check(blood.decals.config.gore, "turning it back on reaches the decals again")
	blood.queue_free()
	first.queue_free()
	second.queue_free()
	var real := ProjectSettings.globalize_path(scratch)
	for f in DirAccess.get_files_at(real):
		var _rm := DirAccess.remove_absolute(real.path_join(f))
	var _rd := DirAccess.remove_absolute(real)
	_check(not DirAccess.dir_exists_absolute(real), "the scratch settings directory is removed afterwards")


## The client on dot-game's DotGameClient: the loading cover is up at the start and blocks
## input, lifts once the player is in, and Tab goes through the menu (it holds the board).
func _test_the_client_platform() -> void:
	_section("the client: the cover lifts, Tab holds the board through the menu, the wheel is a row")
	var client := ZzClient.new()
	# A random drawn world here costs gigabytes to build twice; nothing in this section reads the map.
	DirAccess.make_dir_recursive_absolute("user://cfg")
	var pin := FileAccess.open("user://cfg/headless-run-client.json", FileAccess.WRITE)
	pin.store_string(JSON.stringify({"map_ids": ["zz_lot"]}))
	pin.close()
	client.config_file = "user://cfg/headless-run-client.json"
	client.force_offline = true
	client.standalone_content = false
	client.offline_bots = 0
	add_child(client)
	var platform: DotGameClient = client.platform
	var covered := platform != null and platform.gate != null and not platform.is_shown() \
		and platform.is_input_blocked()
	for _i in 600:
		await get_tree().physics_frame
		if platform.is_shown():
			break
	for _i in 2:
		await get_tree().process_frame
	_check(covered, "the loading cover is up at the start and blocks input")
	_check(platform.is_shown() and not platform.is_input_blocked() and platform.console != null,
		"and lifts once the player is in, with the console built", str(platform.describe()))
	await _check_client_cover(client, platform)
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	var _a: bool = client.settings.menu.handle_event(tab)
	var board: DotMenuScoreboard = client.board
	_check(board != null and board.is_open() and board.rows().any(func(r: Dictionary) -> bool: return bool(r.get("you", false))),
		"Tab holds the scoreboard up, with this player on it", str(board.rows()) if board != null else "no board")
	tab.pressed = false
	var _b: bool = client.settings.menu.handle_event(tab)
	_check(board != null and not board.is_open(), "and letting go puts it away")
	await _check_trader_menu_holds_pointer(client, platform)
	await _check_client_wheel(client)
	var focus := Vector3(2.0, 1.6, -3.0)
	var spot := Vector3(10.0, 5.0, 4.0)
	var pose := ZzClient.end_camera_pose(spot, focus, 0.0)
	var ahead := -pose.basis.z
	_check(pose.origin.is_equal_approx(spot) and ahead.dot((focus - spot).normalized()) > 0.999,
		"the ending camera stands at the map's point and looks at the survivor")
	var turned := ZzClient.end_camera_pose(spot, focus, 90.0)
	_check(is_equal_approx(turned.origin.distance_to(focus), spot.distance_to(focus)) and not turned.origin.is_equal_approx(spot)
		and (-turned.basis.z).dot((focus - turned.origin).normalized()) > 0.999,
		"orbiting keeps its distance and keeps looking at them")
	var rules: ZzEndCameraRules = client.game.end_camera_rules
	_check(rules.set_cvar("zz_end_camera_orbit", "500") and rules.orbit == 90.0 and not rules.set_cvar("zz_end_camera_orbit", "x") and not rules.set_cvar("zz_nope", "1"),
		"the cvars clamp and refuse what is not theirs")
	rules.blend = 0.05
	client.game.map_ending.emit(true, 1.0, 0.0, null)
	for _i in 5:
		await get_tree().process_frame
	_check(client.end_camera_weight() == 0.0, "a map with no camera point leaves the view alone")
	client.game.map_ending.emit(true, 1.0, 0.4, spot)
	for _i in 12:
		await get_tree().process_frame
	_check(client.end_camera_weight() > 0.99, "a point takes the view to it for the ending", str(client.end_camera_weight()))
	_check(client.camera.global_position.distance_to(client.player.global_position) > 5.0, "the camera is there, away from the survivor's eyes")
	await get_tree().create_timer(0.8).timeout
	_check(client.end_camera_weight() == 0.0, "and gives the survivor's eyes back after it")
	await get_tree().process_frame
	await _check_client_endings(client, rules, spot)
	remove_child(client)
	client.free()
	await get_tree().process_frame
	_finished()


## A survivor outside the built map puts the cover back, and it lifts again.
func _check_client_cover(client: ZzClient, platform: DotGameClient) -> void:
	# Connected, a survivor the server moved to the next map's start before that map arrived stands in
	# the old map's void: the cover comes back, and goes once they are inside the built map again.
	client._offline = false
	var home: Vector3 = client.player.global_position
	client.player.global_position = home + Vector3(5000.0, 0.0, 0.0)
	for _i in 3:
		await get_tree().process_frame
	_check(not platform.gate.is_open() and platform.gate.is_holding(&"placed"),
		"a survivor outside the built map puts the cover back (never a frame of the void)", str(platform.gate.describe()))
	client.player.global_position = home
	for _i in 600:
		await get_tree().process_frame
		if platform.gate.is_open():
			break
	_check(platform.gate.is_open() and not platform.gate.is_holding(&"placed"),
		"and it lifts once the survivor is inside the map again", str(platform.gate.describe()))
	client._offline = true


## The wheel as a rebindable row, the next-weapon step and the aim bit.
func _check_client_wheel(client: ZzClient) -> void:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	_check(wheel.is_action_pressed(DotMenuBindings.WEAPON_NEXT_ACTION) and client.settings.bindings.key_for(DotMenuBindings.WEAPON_NEXT_ACTION) == "Wheel down",
		"the wheel changes weapon through a rebindable row")
	var binds: DotMenuBindings = client.settings.bindings
	_check(binds.key_for(DotMenuBindings.WEAPON_PREVIOUS_ACTION) == "Wheel up" and binds.key_for(DotMenuBindings.WEAPON_NEXT_ACTION) == "Wheel down",
		"the wheel rows default to previous (up) and next (down)")
	var jump_wheel := InputEventMouseButton.new()
	jump_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	jump_wheel.pressed = true
	_check(not jump_wheel.is_action_pressed(&"dot_fps_jump") and not wheel.is_action_pressed(&"dot_fps_jump"),
		"the wheel is not on jump")
	var slots: Array = client.weapons.arsenal.slots() if client.weapons != null and client.weapons.arsenal != null else []
	var before: int = client._slot
	# The press itself is gated on a captured pointer, which a headless run cannot have; the
	# routing is the action match above, so this drives what the action calls.
	client.pointer_forced = true
	var _stepped: bool = client._wheel_pressed(wheel)
	var after: int = client._slot
	var expected: int = before
	if slots.size() > 1:
		var from: int = before if before != 0 else int(client.weapons.arsenal.current_slot())
		expected = slots[posmod(slots.find(from) + 1, slots.size())] if slots.has(from) else slots[0]
	_check(after == expected and (slots.size() < 2 or after != before),
		"the next-weapon step moves one slot", "slots %s, %d -> %d" % [str(slots), before, after])
	client.pointer_forced = true
	client._aiming = true
	for _i in 4:
		await get_tree().physics_frame
	var aim_bits: int = client._actions()
	_check((aim_bits & ZzNetCommand.ACT_AIM) != 0, "an aim press in the client reaches the command's action bits", str(aim_bits))


## The client's ending: the first-person arms, the slow motion, and the spectator's view of it.
func _check_client_endings(client: ZzClient, rules: ZzEndCameraRules, spot: Vector3) -> void:
	var arms: DotPlayerViewArms = client.view_arms
	var arms_up: bool = arms != null and arms.get_parent() != null and arms.get_parent() is Node3D and not (arms.get_parent() is Camera3D)
	_check(arms_up and not arms.shown and not arms.arms().visible, "the first-person arms are mounted under a yaw pivot, hidden while up")
	_hurt(client.game, client.player, 500.0)
	for _i in 6:
		await get_tree().process_frame
	_check(client.player.is_down() and arms.shown and arms.arms().visible, "and shown once the survivor is down", str(client.player.is_down()))
	_check(arms.get_parent().global_position.distance_to(client.camera.global_position) < 0.01, "at the eye")
	rules.enabled = 0.0
	client.game.map_ending.emit(true, 1.0, 0.4, spot)
	for _i in 5:
		await get_tree().process_frame
	_check(client.end_camera_weight() == 0.0, "zz_end_camera 0 keeps the view even then")
	rules.enabled = 1.0
	client.slowmo_in_headless = true
	client._on_map_ending(true, 0.5, 1.0, null)
	_check(is_equal_approx(Engine.time_scale, 0.5), "an ending with slow motion slows the clock", str(Engine.time_scale))
	await get_tree().create_timer(0.3, true, false, true).timeout
	client._on_map_ending(true, 0.5, 2.0, null)
	await get_tree().create_timer(0.35, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 0.5), "a second ending is not cut short by the first one's timer", str(Engine.time_scale))
	client.reset_slowmo()
	_check(Engine.time_scale == 1.0, "leaving or changing map gives the clock back")
	client._on_map_ending(true, 0.05, 9999.0, null)
	_check(client._slowed and Engine.time_scale == 0.05, "a huge slow-motion request still arms a bounded hold")
	client.reset_slowmo()
	client.slowmo_in_headless = false
	_check(Engine.time_scale == 1.0, "and a reset brings it back")
	rules.blend = 0.05
	rules.orbit = 0.0
	client.game.spectate.apply_view(client.player.player_id, DotSpectatorView.Mode.FIXED, &"", &"", Vector3.ZERO)
	for _i in 4:
		await get_tree().process_frame
	_check(client.is_spectating(), "a dead survivor is a spectator", str(client.game.spectate.mode_of(client.player.player_id)))
	var spec_spot := Vector3(40.0, 9.0, 31.0)
	client.game.map_ending.emit(true, 1.0, 0.5, spec_spot)
	for _i in 12:
		await get_tree().process_frame
	_check(client.end_camera_weight() > 0.99 and client.camera.global_position.distance_to(spec_spot) < 0.5,
		"the ending camera takes a spectator's view too", "%s %s" % [str(client.end_camera_weight()), str(client.camera.global_position)])
	await get_tree().create_timer(0.9).timeout
	_check(client.end_camera_weight() == 0.0 and client.camera.global_position.distance_to(spec_spot) > 1.0,
		"and a spectator's own camera comes back after it")


func _test_spectate_tap() -> void:
	_section("out, one tap or left click steps once, whether or not the engine emulates the mouse")
	var game := await _world()
	var a := game.add_player(&"u1", "Ada")
	var others: Array[StringName] = []
	for n in 3:
		others.append(game.add_player(StringName("v%d" % n), "V%d" % n).player_id)
	var id := a.player_id
	a.watching = true
	game.spectate.on_died(id, others[0], false, Vector3(0, 2, 0), 0.0, 0)
	game.spectate.manager.set_mode(String(id), DotSpectatorView.Mode.CHASE)
	var client := ZzClient.new()
	client.game = game
	client._adopt(a)
	_check(client.is_spectating(), "the client is out and spectating")

	# Three live targets, so a double step lands on a different one from a single step.
	var start: Variant = game.spectate.watching(id)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	client._unhandled_input(touch)
	var after_touch: Variant = game.spectate.watching(id)
	_check(after_touch != start, "a real touch steps to the next target", "%s -> %s of %s" % [start, after_touch, game.spectate.manager.targets_for(String(id))])

	var emulated := InputEventMouseButton.new()
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.pressed = true
	emulated.device = InputEvent.DEVICE_ID_EMULATION
	client._unhandled_input(emulated)
	_check(game.spectate.watching(id) == after_touch, "the mouse press the engine emulates from it steps nothing more")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	client._unhandled_input(click)
	var after_click: Variant = game.spectate.watching(id)
	_check(after_click != after_touch and after_click != start, "a real left click steps once", "%s %s %s" % [start, after_touch, after_click])

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	client._unhandled_input(release)
	_check(game.spectate.watching(id) == after_click, "and a release steps nothing")

	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	client._unhandled_input(right)
	_check(game.spectate.watching(id) == after_touch, "the right button still steps back")
	client.free()
	_finished()


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1


## A world on the practice street, stepped by hand. The previous one is freed first: every world
## here shares ONE physics space, and every map is built at the origin.
## The HUD draws health, the clock, the kits and confirmed hits through dot-ui's glance
## pieces, from this world's numbers. A headless viewport is 64 x 64, so the layout is checked
## as arithmetic and looked at with `tools/shot.sh --view=hit` and `--view=down`.
func _test_the_hud() -> void:
	_section("the HUD: dot-ui's vitals, clock, kits, and hits the server confirmed")
	var game := await _team(1)
	var me: ZzPlayer = game.survivors()[0]
	var hud := ZzHud.new()
	add_child(hud)
	hud.bind(game, me)

	me.health.health = 55.0
	me.temp_health = 25.0
	me.medkits = 1
	hud._process(0.0)
	_check(
		hud.vitals.number_text() == "30" and is_equal_approx(hud.vitals.bonus, 25.0) and hud.vitals.status == "",
		"DotVitals: real health as the number, borrowed health as its bonus", str(hud.vitals.describe())
	)
	_check(hud.kits.rows.size() == 1 and str(hud.kits.rows[0][0]) == "medkit x1" and str(hud.kits.rows[0][1]) != "",
		"the medkit is a DotKeyHints row with its key", str(hud.kits.rows))

	_check_hud_roster(game, me, hud)
	_hurt(game, me, 500.0)
	await _sim(game, 0.1)
	hud._process(0.0)
	_check(ZzClient.health_text(me) == "DOWN" and ZzClient.downs_text(me, game.config.max_incaps) == str(game.config.max_incaps - 1),
		"down shows DOWN and one down fewer on the board")
	_check(me.is_down() and hud.vitals.status == "DOWN" and hud.vitals.is_low(),
		"down, DOWN replaces the number and it is all in the low colour", str(hud.vitals.describe()))

	# A hold-out's clock is the strip's.
	var objectives: Array = game.map_doc.get("objectives", [])
	if objectives.is_empty():
		_check(false, "the practice street has an objective to hold")
	else:
		game.objective_states[0] = &"holding"
		game.objective_progress[0] = game.now() + 42.2
		hud._process(0.0)
		_check(hud.strip.clock == DotScoreStrip.clock_text(42.2) and hud.strip.under_text().ends_with("hold out"),
			"a hold-out's time left is DotScoreStrip's clock", str(hud.strip.describe()))

	# A survivor's hit, as dot-combat applies it, is confirmed by the world, and the HUD draws
	# the marker and the number from that confirmation.
	var confirmed: Array = []
	game.hit_landed.connect(func(id: StringName, victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
		confirmed.append([id, victim, amount, killed])
		hud.confirm_hit(victim, amount, point, killed, headshot))
	# On the street: nothing spawns in a safe room, which is where the team starts.
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -6), &"test")
	await _sim(game, 0.1)
	var shot := DotDamage.make(me.entity_id, game.horde.entity_id_for(npc), 7.0, null)
	shot.tick = game.current_tick()
	var _applied := game.combat.apply_damage(shot)
	_check(confirmed.size() == 1 and confirmed[0][0] == me.player_id and absf(float(confirmed[0][2]) - 7.0) < 0.01
		and not bool(confirmed[0][3]), "a survivor's hit on a zombie is confirmed, by whom and how much", str(confirmed))
	_check(hud.hit_marker.alpha() > 0.0 and hud.damage_numbers.texts().size() == 1,
		"and the HUD flashes DotHitMarker and puts up a DotDamageNumbers number", str(hud.damage_numbers.texts()))
	_hurt_npc(game, npc, 7.0)
	_check(confirmed.size() == 1, "the world's damage confirms nothing", str(confirmed))

	_check_hud_plate(hud)
	_check_hud_aim(hud, me)
	_check_requires()
	await _check_survivor_tag()
	await _check_killcam_time()

	hud.queue_free()
	_finished()


## The health plate against a full chat log.
func _check_hud_plate(hud: ZzHud) -> void:
	# Both bottom-anchored, so the arithmetic holds at any height.
	var chat := DotGameChatClient.new()
	add_child(chat)
	var w: DotChatWindow = chat.window
	var log_top := w.margin_bottom + w.entry_height + float(w.max_lines) * (w.line_height + w.line_gap)
	_check(ZzHud.PLATE_BOTTOM >= log_top and is_equal_approx(-hud.vitals.offset_bottom, ZzHud.PLATE_BOTTOM),
		"the health plate stays above a full chat log",
		"log reaches %.0f px off the bottom, the plate ends %.0f off it" % [log_top, -hud.vitals.offset_bottom])
	chat.queue_free()


## The team list setting and the board's health and downs.
func _check_hud_roster(game: ZzGame, me: ZzPlayer, hud: ZzHud) -> void:
	# The team-mate list is a server setting, off by default; the board carries the same facts.
	_check(not game.config.team_roster and not hud._team.visible, "the team list is off by default and hidden")
	game.config.team_roster = true
	hud._process(0.0)
	_check(hud._team.visible, "zz_team_roster 1 shows the team list")
	game.config.team_roster = false
	hud._process(0.0)
	_check(not hud._team.visible, "and 0 hides it again")
	_check(ZzClient.health_text(me) == "55" and ZzClient.downs_text(me, game.config.max_incaps) == str(game.config.max_incaps),
		"the board's health and downs left for a survivor", ZzClient.health_text(me))


## The crosshair down the sights, the scope preference and the death of the crosshair.
func _check_hud_aim(hud: ZzHud, me: ZzPlayer) -> void:
	# Down the sights the dot fades with the aim (dot-ui's curve), and a scope hides it.
	hud.set_aim(0.0, false)
	var hip := _crosshair_alpha(hud)
	hud.set_aim(1.0, false)
	var aimed := _crosshair_alpha(hud)
	hud.set_aim(1.0, true)
	_check(is_equal_approx(hip, 1.0) and (aimed < 0.01 or DotAddonApi.build_level("dot_ui") < 5)
		and _crosshair_alpha(hud) == 0.0 and is_equal_approx(hud.scope.fraction, 1.0),
		"the crosshair is whole at the hip, gone down the sights, and a scope replaces it",
		"hip %.2f aimed %.2f scope %.2f" % [hip, aimed, hud.scope.fraction])
	var scope_prefs := load("res://addons/dot_weapon/view/dot_weapon_scope_prefs.gd")
	var probe := ZeeViewModel.new()
	scope_prefs.mode = 2
	scope_prefs.apply(probe)
	_check(probe.scope_mode == ZeeViewModel.SCOPE_FULL and not probe.scope_is_lens(),
		"the cl_scope_mode pref reaches the view model", "mode %d" % probe.scope_mode)
	scope_prefs.mode = 1
	var before := _script_errors.seen().size()
	_check(is_equal_approx(ZzClient.scope_view_zoom(probe), probe.view_fov_scale()) and probe.scope_mode == ZeeViewModel.SCOPE_LENS,
		"the client's camera zoom comes from the view model's view_fov_scale, prefs applied", "mode %d" % probe.scope_mode)
	probe.free()
	# A zee_weapons copy from before its scope views (no LEVEL bump came with them) errs every frame if called blind.
	var old_hands := OldScopeHands.new()
	_check(is_equal_approx(ZzClient.scope_view_zoom(old_hands), OldScopeHands.ZOOM) and _script_errors.seen().size() == before,
		"hands without resolve_scope_mode/view_fov_scale zoom the main camera, with no script error",
		str(_script_errors.seen().slice(before)))
	hud.set_aim(0.0, false)
	var cross: Control = hud._crosshair
	var hides := DotAddonApi.build_level("dot_ui") >= 14
	if hides:
		cross.call(&"_process", 0.016)
	_check(not hides or bool(cross.call(&"is_shown")), "the crosshair is drawn while the survivor lives")
	me.health.alive = false
	if hides:
		cross.call(&"_process", 0.016)
	_check(not hides or not bool(cross.call(&"is_shown")), "and gone once they are dead (alive_source)")
	me.health.alive = true


## What the crosshair shows: DotCrosshair fades itself (and hides when scoped), the old dot by modulate.
func _crosshair_alpha(hud: ZzHud) -> float:
	var c: Control = hud._crosshair
	if c.has_method(&"set_aim"):
		c.call(&"follow_aim", 10.0)
		return 0.0 if bool(c.get(&"suppressed")) else float(c.get(&"aim_opacity"))
	return c.modulate.a


## Christian's first play test (2026-10-11): the team list's missing-glyph boxes, "You is down",
## the fence lock a black slab, the black void over the street, ten silent seconds after a
## wipe, and a HUD that should be darker and follow the menu's theme.
func _test_the_first_play_test() -> void:
	_section("the first play test: glyphs, the feed, the fence and its lock, the sky, the wipe, the theme")

	_check_font_coverage()
	var game := await _team(3, func(c: ZzConfig) -> void:
		_quiet(c)
		c.intermission_seconds = 3.0
		c.killcam_seconds = 0.0
		c.team_roster = true)
	var me: ZzPlayer = game.survivors()[0]
	var hud := ZzHud.new()
	add_child(hud)
	hud.bind(game, me)
	var other: ZzPlayer = game.survivors()[1]
	other.health.health = other.health.max_health * 0.5
	_hurt(game, game.survivors()[2], 500.0)
	await _sim(game, 0.1)
	hud._process(0.0)
	var rows := hud.team_lines()
	_check(rows.size() == 2 and rows[0] == "%s|%d|0.50" % [other.display_name, int(ceilf(other.health.health))]
		and rows[1].ends_with("|DOWN|0.00"), "the team list is a drawn bar per survivor, not typed blocks", str(rows))

	_check(ZzClient.feed_line("You", "is down", "", &"", &"strangler", true) == "You are down (strangler)"
		and ZzClient.feed_line("You", "died", "", &"", &"common", true) == "You died (common)"
		and ZzClient.feed_line("Odell", "is down", "", &"", &"strangler") == "Odell is down (strangler)"
		and ZzClient.feed_line("You", "was picked up", "", &"", &"", true) == "You were picked up",
		"the feed says \"You are down\", and somebody else \"is down\"",
		ZzClient.feed_line("You", "is down", "", &"", &"strangler", true))

	# Christian asked for a darker HUD by default that the menu's theme restyles.
	var settings := ZzSettings.new()
	add_child(settings)
	var _built: DotResult = settings.setup(DotSettingsStoreMemory.new())
	hud.follow_menu(settings.menu)
	var plate := hud.vitals.colour(&"plate")
	_check(plate.get_luminance() < 0.1 and plate.a >= 0.7, "the HUD is dark by default, in the menu's theme", str(plate))
	var _t := settings.settings.set_value(&"ui_theme", &"contrast")
	var contrast: DotMenuPalette = settings.menu.palette()
	_check(contrast.id == &"contrast" and hud.vitals.colour(&"plate") == contrast.hud_plate and hud.strip.colour(&"text") == contrast.hud_text,
		"a theme picked in the menu reaches every piece at once")
	_check(hud.vitals.colour(&"highlight") == ZzHud.AMBER and hud._top.get_theme_color(&"font_color") == contrast.hud_text,
		"keeping this game's amber, and the HUD's own lines follow it too")
	_t = settings.settings.set_value(&"ui_theme", &"midnight")
	settings.queue_free()

	# A wipe counts down to the next round, on the strip, instead of ten silent seconds.
	for player in game.survivors():
		_hurt(game, player, 5000.0)
		_hurt(game, player, 5000.0)
		_hurt(game, player, 5000.0)
	await _sim(game, 2.6)
	hud._process(0.0)
	_check(game._decided and game.next_round_seconds() > 0.0 and game.next_round_seconds() <= 3.0
		and hud._top.text == "Trying again" and hud.strip.clock != "",
		"after a wipe the HUD counts down to the map again", "%.1f s, '%s' %s" % [game.next_round_seconds(), hud._top.text, hud.strip.clock])
	var number := game.round_number
	await _sim(game, 3.2)
	_check(game.round_number > number and game.next_round_seconds() < 0.0, "and the map starts again when it reaches nothing")
	hud.queue_free()

	_check_fence_and_sky(game)
	_finished()


## The fence and its lock, and the sky, as a client draws them.
func _check_fence_and_sky(game: ZzGame) -> void:
	# The fence and its lock, and the sky, as a client draws them.
	var doc := ZzCatalogue.practice().duplicate(true)
	for box: Dictionary in doc["boxes"]:
		if str(box.get("gate", "")) == "barrier":
			box["look"] = "chain_link"
	(doc["objectives"][0] as Dictionary)["prop"] = "padlock"
	var checked := ZzMapDoc.validate(doc)
	_check(checked.ok and str((checked.value["objectives"][0] as Dictionary).get("prop", "")) == "padlock",
		"a map may say what its objective is (a padlock) and how a gate looks (chain-link)")
	var drawn := ZzMap.new()
	drawn.physics = game.physics
	drawn.catalogue = game.props_catalogue
	drawn.draw_world = true
	add_child(drawn)
	var _b := drawn.build(checked.value)
	var fence := drawn.find_child("Gate_barrier", true, false)
	var lock := drawn.find_child("Objective_barrier", true, false)
	_check(fence != null and fence.find_child("ChainLink", true, false) == null and fence.get_child_count() > 3 and lock != null
		and lock.get_child_count() >= 10, "the gate is drawn as posts, rails and mesh, with a chain and padlock on it",
		"%s, %s" % [fence, lock])
	drawn.open_gate("barrier")
	_check(not is_instance_valid(lock) or lock.is_queued_for_deletion(), "and opening the gate takes the lock with it")
	var sky := (drawn._environment.environment.sky.sky_material as ProceduralSkyMaterial) if drawn._environment != null else null
	_check(ZzMap.is_night(checked.value["environment"]) and sky != null and sky.sky_cover != null
		and sky.sky_horizon_color.get_luminance() > 0.1, "a night map has a sky: stars, a moon, a lit horizon, not a black void")
	drawn.free()


## Every character the game writes is in the HUD's font.
func _check_font_coverage() -> void:
	# Every character the game writes is in the HUD's font. The team bars were "▮▯", which the
	# embedded font lacks and Windows' fallback does not have either.
	var font: Font = ThemeDB.fallback_font
	var missing := PackedStringArray()
	for folder in ["res://game", "res://game/net", "res://npcs"]:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".gd"):
				continue
			for line in FileAccess.get_file_as_string(folder.path_join(file)).split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				var code := line.split("#")[0] if line.count("\"") % 2 == 0 else line
				for c in code:
					if c.unicode_at(0) > 127 and not font.has_char(c.unicode_at(0)):
						missing.append("%s %s" % [file, c])
	_check(missing.is_empty(), "every character the game writes is in the HUD's font", ", ".join(missing))


## A pack naming dot-ui's glance pieces does not parse on a shell whose dot-ui predates them,
## so the requires.json dot-ci derives must ask for dot-ui 4, and nothing may lower it.
## The trader menu is the one modal this game frees the mouse for; it must hold the pointer through DotGameClient.
func _check_trader_menu_holds_pointer(client: ZzClient, platform: DotGameClient) -> void:
	var feet: Vector3 = client.player.feet() if client.player != null else Vector3.ZERO
	client.shop_state = {"menu": true, "open": true, "radius": 3.5, "at": [[feet.x, feet.y, feet.z]], "items": []}
	client.open_shop()
	_check(client.is_shop_open() and platform.is_input_blocked(), "the trader menu opens and holds the pointer, blocking input")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	get_viewport().push_input(click)
	platform._on_menu_state(false)
	platform.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
	await get_tree().process_frame
	_check(client.is_shop_open() and platform.is_input_blocked() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"a click outside, another menu closing and a focus event leave the pointer free while the trader menu is up")
	client.close_shop()
	_check(not client.is_shop_open() and not platform.is_input_blocked(), "closing the trader menu releases the hold")


func _check_requires() -> void:
	var asks := DotAddonApi.derive()
	_check(
		int(asks.get("dot_ui", 0)) >= 4 and not FileAccess.file_exists("res://" + DotAddonApi.FLOOR_FILE),
		"the pack asks a shell for dot-ui level 4, the glance pieces",
		str(asks.get("dot_ui"))
	)


## Another survivor wears dot-ui's name and health pill over the drawn body; the own player and
## the hidden or dead wear none. Presentation only.
func _check_survivor_tag() -> void:
	var game := await _world()
	var other := game.add_player(&"u-tag", "Tagged")
	game.start()
	await get_tree().physics_frame
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(0.0, 2.0, 6.0)
	other.present_tag(true, Vector3.ZERO, camera, 0.016)
	var tag := other.get_node_or_null("HealthTag") as DotHealthTag
	_check(tag != null and tag.visible, "another survivor wears a health tag over the drawn body")
	_check(tag != null and tag.global_position.y > ZzPlayer.BODY_HEIGHT and absf(tag.global_transform.basis.z.normalized().dot(Vector3.UP)) < 0.5,
		"above the head, turned to the camera")
	other.present_tag(false, Vector3.ZERO, camera, 0.016)
	_check(tag != null and not tag.visible, "and none once the body is not shown")
	camera.queue_free()


## The killcam is added to an intermission, never to an intermission of 0 (the suites run on 0).
func _check_killcam_time() -> void:
	var world := await _world()
	world.config.killcam_seconds = 7.0
	world.apply_intermission()
	_check(is_zero_approx(world.match_node.rules.intermission_sec), "the killcam adds nothing to an intermission of 0")
	world.config.intermission_seconds = 8.0
	world.apply_intermission()
	_check(is_equal_approx(world.match_node.rules.intermission_sec, 15.0), "and is added to the pause otherwise",
		str(world.match_node.rules.intermission_sec))

	# The replay draws the zombies too, so each recorded frame holds them.
	var recorder: Node = load("res://game/zz_killcam.gd").new()
	var tick := [0.0]
	recorder.now_fn = func() -> float:
		tick[0] += 0.016
		return tick[0]
	recorder.players_fn = func() -> Array: return []
	recorder.zombies_fn = func() -> Array: return [[7, &"common", 0, Vector3(1.0, 0.0, 2.0), 0.5, 0, 0]]
	recorder.call(&"frame")
	var held: Dictionary = recorder.buffer.sample(tick[0])["b"]
	_check(held.has("~zombies") and (held["~zombies"] as Array).size() == 1, "a killcam frame records the zombies near the survivors", str(held.keys()))
	recorder.free()

	var iconed: Node = load("res://game/zz_killcam.gd").new()
	iconed.weapon_icon_fn = func(id: String) -> Texture2D: return PlaceholderTexture2D.new() if id == "rifle" else null
	add_child(iconed)
	iconed.note_moment(&"p1", "fell to the horde", "THE LAST STAND", &"rifle")
	var noted: Dictionary = iconed.buffer.last_event(&"moment")
	_check(noted["data"]["weapon_id"] == "rifle" and iconed.killcam.icon_provider.call("rifle") != null and iconed.killcam.icon_provider.call("axe") == null,
		"a killcam moment keeps the weapon id and the banner's icon provider asks the game's icons")
	iconed.queue_free()
