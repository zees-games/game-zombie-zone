extends "headless_run_menus.gd"

## The client-platform and spectate sections of [headless_run.gd], split off to keep each file under the size gate.


const ZzClient := preload("../game/zz_client.gd")
const ZzEndCameraRules := preload("../game/zz_end_camera_rules.gd")


## The client on gs-game's GSGameClient: the loading cover is up at the start and blocks
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
	var platform: GSGameClient = client.platform
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
	var tier_quality: int = client.settings.settings.get_int(&"texture_quality", -1)
	var tier_surfaces := GSMapSurfaces.new()
	var _tier: Dictionary = GSMapTextureTier.apply_current(tier_surfaces)
	_check(tier_quality >= 0 and GSMapTextureTier.current_quality == tier_quality
		and tier_surfaces.max_texture_size == int(GSMapTextureTier.settings(tier_quality)["max_size"]),
		"the video setting's texture quality caps the map art", "%d %d" % [GSMapTextureTier.current_quality, tier_surfaces.max_texture_size])
	await _check_client_cover(client, platform)
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	var _a: bool = client.settings.menu.handle_event(tab)
	var board: GSMenuScoreboard = client.board
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
	_check(not rules.set_cvar("zz_end_camera_orbit", "500") and rules.orbit != 500.0 and rules.set_cvar("zz_end_camera_orbit", "90") and rules.orbit == 90.0
		and not rules.set_cvar("zz_end_camera_orbit", "x") and not rules.set_cvar("zz_nope", "1"),
		"the cvars refuse out-of-range values and what is not theirs")
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
func _check_client_cover(client: ZzClient, platform: GSGameClient) -> void:
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
	_check(wheel.is_action_pressed(GSMenuBindings.WEAPON_NEXT_ACTION) and client.settings.bindings.key_for(GSMenuBindings.WEAPON_NEXT_ACTION) == "Wheel down",
		"the wheel changes weapon through a rebindable row")
	var binds: GSMenuBindings = client.settings.bindings
	_check(binds.key_for(GSMenuBindings.WEAPON_PREVIOUS_ACTION) == "Wheel up" and binds.key_for(GSMenuBindings.WEAPON_NEXT_ACTION) == "Wheel down",
		"the wheel rows default to previous (up) and next (down)")
	var jump_wheel := InputEventMouseButton.new()
	jump_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	jump_wheel.pressed = true
	_check(not jump_wheel.is_action_pressed(&"gs_fps_jump") and not wheel.is_action_pressed(&"gs_fps_jump"),
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
	var arms: GSPlayerViewArms = client.view_arms
	var arms_up: bool = arms != null and arms.get_parent() != null and arms.get_parent() is Node3D and not (arms.get_parent() is Camera3D)
	_check(arms_up and not arms.shown and not arms.arms().visible, "the first-person arms are mounted under a yaw pivot, hidden while up")
	_hurt(client.game, client.player, 500.0)
	for _i in 12:
		await get_tree().process_frame
	_check(client.player.is_down() and not arms.shown, "and still hidden while propped up (the weapon draws its own hands)", str(client.player.is_down()))
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
	client.game.spectate.apply_view(client.player.player_id, GSSpectatorView.Mode.FIXED, &"", &"", Vector3.ZERO)
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
	game.spectate.manager.set_mode(String(id), GSSpectatorView.Mode.CHASE)
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


## A pack naming gs-ui's glance pieces does not parse on a shell whose gs-ui predates them,
## so the requires.json gs-ci derives must ask for gs-ui 4, and nothing may lower it.
## The trader menu is the one modal this game frees the mouse for; it must hold the pointer through GSGameClient.
func _check_trader_menu_holds_pointer(client: ZzClient, platform: GSGameClient) -> void:
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
