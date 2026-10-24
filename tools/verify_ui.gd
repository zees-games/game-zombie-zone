extends Node

## Drives the real client with real input events and renders frames, for what no assertion reaches:
## `--check=trader` (mouse through the trader's menu), `--check=crouch` (Ctrl and C held),
## `--check=nav` (the navigation meter while a graph builds). Run by tools/verify_ui.sh under xvfb
## (a display driver: the weapon pictures are null headless). Prints `VERIFY ok|FAIL what`.

const ZzClient := preload("../game/zz_client.gd")
const ZzBindings := preload("../game/zz_bindings.gd")

var _check := "trader"
var _out := "res://screenshots/verify"
var _client: Node = null
var _failed := 0
var _passed := 0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check="):
			_check = arg.trim_prefix("--check=")
		elif arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")

	_client = ZzClient.new()
	_client.name = "Client"
	_client.set("force_offline", true)
	_client.set("offline_bots", 3)
	add_child(_client)
	_run.call_deferred()


func _run() -> void:
	match _check:
		"trader":
			await _trader()
		"crouch":
			await _crouch()
		"nav":
			await _nav()
		"loot":
			await _loot()

	print("VERIFY %s: %d passed, %d failed" % [_check, _passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(good: bool, what: String, detail: String = "") -> void:
	if good:
		_passed += 1
		print("VERIFY ok   ", what)
	else:
		_failed += 1
		print("VERIFY FAIL ", what, " ", detail)


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _seconds(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("%s_%s.png" % [_out, shot_name])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("VERIFY shot ", path, " ", error_string(err))


func _round() -> Object:
	var game: Object = _client.get("game")
	for _i in 1800:
		if game.phase != 0 and _client.get("player") != null:
			break
		await get_tree().process_frame
	return game


func _key(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	e.ctrl_pressed = code == KEY_CTRL and pressed
	Input.parse_input_event(e)


func _action_key(action: StringName, pressed: bool) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var e := (ev as InputEventKey).duplicate() as InputEventKey
			e.pressed = pressed
			Input.parse_input_event(e)
			return


func _mouse_to(p: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = p
	m.global_position = p
	Input.parse_input_event(m)
	await _frames(2)


func _click(p: Vector2) -> void:
	await _mouse_to(p)
	for down in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = down
		b.position = p
		b.global_position = p
		b.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		Input.parse_input_event(b)
		await _frames(2)
	await _frames(3)


func _centre(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _trader() -> void:
	var game: Object = await _round()
	var local: Object = _client.get("player")
	game.config.trader_when = 2
	game.spawners.start_round(game.map_doc)
	local.points = 420
	await _seconds(1.0)
	_client.set("pointer_forced", true)

	# E, the way a player opens it.
	_action_key(ZzBindings.USE, true)
	await _frames(2)
	_action_key(ZzBindings.USE, false)
	await _seconds(0.5)
	var menu: PanelContainer = _client.get("_shop_menu")
	_ok(menu.is_open(), "E opens the trader's menu")
	if not menu.is_open():
		_client.call("open_shop")
		await _seconds(0.3)
	await _seconds(1.0)
	await _shot("trader_open")

	var shown := 0
	for row: Button in menu._rows.values():
		for child in row.get_child(0).get_children():
			if child is TextureRect and (child as TextureRect).texture != null:
				shown += 1
	_ok(shown > 0 and menu._picture.texture != null, "weapon pictures are drawn", "%d cards with one, big=%s" % [shown, menu._picture.texture])

	var rect := menu.get_global_rect()
	var vp := get_viewport().get_visible_rect()
	_ok(vp.encloses(rect), "the panel lies inside the screen", "%s in %s" % [rect, vp])

	for tab: Button in menu._tabs.get_children():
		if tab.text == "Grenades":
			await _click(_centre(tab))
			break
	await _frames(3)
	_ok(menu.category == "grenades", "clicking the Grenades tab shows grenades", menu.category)
	await _shot("trader_grenades")

	for tab: Button in menu._tabs.get_children():
		if tab.text == "Weapons":
			await _click(_centre(tab))
			break
	await _frames(3)
	_ok(menu.category == "weapons", "clicking Weapons returns")

	var target := ""
	for id: String in menu._rows:
		var it: Dictionary = menu._item(id)
		if str(menu.state_fn.call(it)) == "" and int(it.get("price", 0)) <= menu.money and id != menu.selected:
			target = id
			break
	_ok(target != "", "an affordable unowned weapon exists")
	if target != "":
		var before: int = local.points
		await _click(_centre(menu._rows[target]))
		_ok(menu.selected == target, "clicking a card selects it", "selected %s" % menu.selected)
		await _shot("trader_selected")
		await _click(_centre(menu._buy))
		await _seconds(0.3)
		_ok(local.points < before, "clicking Buy spends points", "%d -> %d" % [before, local.points])
		await _shot("trader_bought")

	_action_key(&"ui_cancel", true)
	await _frames(2)
	_action_key(&"ui_cancel", false)
	await _frames(3)
	_ok(not menu.is_open(), "Esc closes it")


func _crouch() -> void:
	var game: Object = await _round()
	var local: Object = _client.get("player")
	for p in game.survivors():
		p.is_bot = false
		p.health.invulnerable = true
	await _seconds(1.5)
	_client.set("pointer_forced", true)
	var cam: Camera3D = _client.get("camera")
	var base_eye: float = cam.global_position.y - local.controller.state.position.y
	print("VERIFY standing: eye %.2f crouch %.2f" % [base_eye, local.controller.state.crouch_fraction])
	await _shot("crouch_0_standing")

	for pair in [[KEY_CTRL, "ctrl"], [KEY_C, "c"]]:
		_key(pair[0], true)
		await _seconds(0.6)
		var eye: float = cam.global_position.y - local.controller.state.position.y
		var frac: float = local.controller.state.crouch_fraction
		var hit_h: float = local.controller.tunables.height_at(frac)
		print("VERIFY %s held: eye %.2f crouch %.2f body %.2f" % [pair[1], eye, frac, hit_h])
		_ok(frac > 0.99, "%s held: the controller crouches" % pair[1], str(frac))
		_ok(eye < base_eye - 0.3, "%s held: the camera is lower" % pair[1], "%.2f vs %.2f" % [eye, base_eye])
		await _shot("crouch_1_%s" % pair[1])
		_key(pair[0], false)
		await _seconds(0.6)
		var up: float = cam.global_position.y - local.controller.state.position.y
		_ok(absf(up - base_eye) < 0.05, "%s released: standing again" % pair[1], "%.2f" % up)


func _nav() -> void:
	var game: Object = _client.get("game")
	var best := -1
	var shown_at := -1
	for _i in 6000:
		await get_tree().process_frame
		var hud: Object = _client.get("hud")
		if hud == null or game == null:
			continue
		var pct: int = game.nav_percent()
		var meter: Control = hud.get("_nav_meter")
		if pct >= 0:
			best = maxi(best, pct)
			if _i % 60 == 0:
				print("VERIFY nav %d%% hud.player=%s hud.visible=%s meter.visible=%s in_tree=%s covered=%s" % [pct, hud.get("player") != null, hud.visible, meter.visible if meter != null else "none", meter.is_visible_in_tree() if meter != null else "none", _client.call("_covered")])
			if meter != null and meter.is_visible_in_tree() and shown_at < 0 and (pct >= 25 or _i > 3000):
				shown_at = pct
				print("VERIFY meter visible at %d%% rect %s covered=%s" % [pct, meter.get_global_rect(), _client.call("_covered")])
				await _shot("nav_meter_%d" % pct)
				break
		elif best >= 0:
			break
	_ok(best >= 0, "a build ran (nav_percent reported)", str(best))
	_ok(shown_at >= 0, "the meter was visible while it ran")


func _loot() -> void:
	var game: Object = await _round()
	var local: Object = _client.get("player")
	for p in game.survivors():
		p.is_bot = false
		p.health.invulnerable = true
	await _seconds(1.0)
	var spot: Vector3 = local.feet() + Vector3(0.0, 0.0, -2.5)
	var ids: Array[int] = []
	for n in 6:
		ids.append(game.loot.add(&"ammo", &"", spot, 60.0))
	for n in 3:
		ids.append(game.loot.add(&"box", &"mystery", spot, 60.0))
	await _seconds(1.0)
	var closest := INF
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var pa: Vector3 = game.loot.position_of(ids[a])
			var pb: Vector3 = game.loot.position_of(ids[b])
			closest = minf(closest, Vector2(pa.x - pb.x, pa.z - pb.z).length())
	_ok(closest >= 0.89, "nine drops on one spot lie apart", "closest %.2f" % closest)
	await _shot("loot_pile")
