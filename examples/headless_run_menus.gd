extends "headless_run_helpers.gd"

## The help, menu, settings, map-menu and small rule sections of [headless_run.gd], split off to keep each file under the size gate.


const ZzBindings := preload("../game/zz_bindings.gd")
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


## The family's rule since the first play test: H opens help in every game, nothing else in
## the table is on H, and the Escape menu has Help & commands and Leave.
func _test_help_and_menu() -> void:
	_section("H opens help, and the Escape menu has Help and Leave")
	var settings := ZzSettings.new()
	add_child(settings)
	var built := settings.setup(GSSettingsStoreMemory.new())
	var keys := settings.bindings
	_check(built.ok and keys != null and keys.key_for(GSMenuBindings.HELP_ACTION) == "H", "help is on H")
	_check(keys.defaults_on("H").size() == 1, "and nothing else in the table defaults to H (the medkit is on G)",
		str(keys.defaults_on("H").map(func(r: Dictionary) -> String: return str(r["label"]))))
	# The right mouse button aims down the sights (the family's Aim row); the shove is on T.
	_check(keys.key_for(ZzBindings.AIM) == "Mouse 2" and keys.defaults_on("Mouse 2").size() == 1
		and keys.key_for(ZzBindings.SHOVE) == "T", "aim is the only row on the right mouse button, the shove is on T",
		"%s %s %d" % [keys.key_for(ZzBindings.AIM), keys.key_for(ZzBindings.SHOVE), keys.defaults_on("Mouse 2").size()])
	# Chat is two rows, so help lists Y and U and the Controls page moves them.
	var _t := settings.settings.set_value(&"bind_chat", "T")
	_check(keys.key_for(ZzBindings.CHAT) == "T" and GSInputBinding.describe_action(ZzBindings.CHAT) == "T"
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
	var old_doc := GSSettingsStoreMemory.new()
	var _saved := old_doc.save_document(ZzSettings.APP_NAMESPACE, &"local", {"version": 1, "values": {
		"bind_heal": "H", "bind_help": "H", "bind_shove": "V", "bind_use": "J", "field_of_view": 92,
		"crowd_detail": 2, "vis_mode": 1, "ambient_frequency": 0.5, "gore": false, "reduce_motion": true, "sfx_volume": 0.3,
	}})
	var returning := ZzSettings.new()
	add_child(returning)
	var _r := returning.setup(old_doc, false)
	var rk: GSMenuBindings = returning.bindings
	_check(rk.key_for(ZzBindings.HEAL) == "G" and rk.key_for(GSMenuBindings.HELP_ACTION) == "H",
		"an old settings file with the medkit on H: the medkit moves to G, help keeps H",
		"%s %s" % [rk.key_for(ZzBindings.HEAL), rk.key_for(GSMenuBindings.HELP_ACTION)])
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
	_check(absf(fov_cam.fov - GSMenuApplier.vertical_from_horizontal_4_3(70.0)) < 0.01,
		"the slider is horizontal degrees at 4:3, converted for the camera", "%.2f" % fov_cam.fov)
	returning.queue_free()
	await get_tree().process_frame


## The family's rule since the first play test: M opens the map list, and solo a choice
## changes it now. The server's half (the owner's flag, the vote) is in `dedicated` and gs-vote.
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
	var _built: GSResult = settings.setup(GSSettingsStoreMemory.new())
	var keys: GSMenuBindings = settings.bindings
	var image := settings.menu.page(&"video").find_section(&"image")
	var gore_row: GSMenuRow = image.find_row(&"gore") if image != null else null
	_check(gore_row != null and gore_row.row_id() == &"gore" and settings.schema.has(&"gore"),
		"the Video page's Image section has a Blood splatters row on the gore setting")
	_check_gore_persist()
	_check(keys.key_for(GSMenuBindings.MAPS_ACTION) == "M" and keys.defaults_on("M").size() == 1,
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
	for row in range(1, GSMenuPicker.PAGE_SIZE + 1):
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
	var scratch := GSSettingsScratch.use("headless_gore_persist")
	var first := ZzSettings.new()
	first.directory = scratch
	add_child(first)
	var _b1 := first.setup(GSSettingsStoreFile.new(scratch), false)
	var _g2 := first.settings.set_value(&"gore", false)
	var flushed := first.settings.flush()
	_check(flushed.ok and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(scratch)) and not DirAccess.get_files_at(scratch).is_empty(),
		"turning Blood splatters off and saving writes the settings file", str(flushed.error.message if not flushed.ok else ""))
	var second := ZzSettings.new()
	second.directory = scratch
	add_child(second)
	var _b2 := second.setup(GSSettingsStoreFile.new(scratch), false)
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


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1


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


func _check_requires() -> void:
	var asks := GSAddonApi.derive()
	var floors := {}
	var floor_path := "res://" + GSAddonApi.FLOOR_FILE
	if FileAccess.file_exists(floor_path):
		var read := GSAddonApi.parse(FileAccess.get_file_as_string(floor_path), GSAddonApi.FLOOR_FILE)
		floors = read.value as Dictionary if read.ok else {}
	# The floor file only lowers the addons it names, so the ask a shell sees is the derived one
	# with the floors applied; the glance pieces need gs-ui level 4 on either side of that.
	var asked := GSAddonApi.apply_floors(asks, floors)
	_check(
		int(asks.get("gs_ui", 0)) >= 4 and _floor_of("gs_ui") >= 4,
		"the pack asks a shell for gs-ui level 4, the glance pieces",
		"derived %s, asked %s" % [str(asks.get("gs_ui")), str(asked.get("gs_ui"))]
	)


## The committed floor's level for [param addon]; the derived one when the floor file does not name it, so a floor
## for another addon (gs_player_char) does not read as lowering this one.
func _floor_of(addon: String) -> int:
	var path := "res://" + GSAddonApi.FLOOR_FILE
	var derived := int(GSAddonApi.derive().get(addon, 0))
	if not FileAccess.file_exists(path):
		return derived
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return int((parsed.get("addons", {}) as Dictionary).get(addon, derived))
	return derived


## Another survivor wears gs-ui's name and health pill over the drawn body; the own player and
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
	var tag := other.get_node_or_null("HealthTag") as GSHealthTag
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
