extends Node

## The shot tool's settings and its frame-taking helpers (the sheets of one weapon, the stamina and crosshair strips), so shot.gd holds only the scene setup.

const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzClient := preload("../game/zz_client.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzMechanics := preload("../game/zz_mechanics.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

var _view := "survivor"
## `--action=emote:dance` (`pose:sit`): the avatar action `--view=action` plays on a stand-in.
var _action := ""
var _zombie := &"common"
var _seconds := 3.0
var _board := false
var _out := "res://screenshots/shot.png"
var _at := Vector3.INF
var _look := Vector3.INF
var _spawn: Array = []
var _pin := &""
## --sever=head,armL: the spawned zombies lose those limbs, so a frame shows the stumps.
var _sever: PackedStringArray = PackedStringArray()
var _pin_me := false
var _box := &""
## --hard=N: N Hard Box stacks running, so the mutants are drawn faded.
var _hard := 0
## --goo=N: N stacks of the oil monster's black goo on the local survivor, so a frame shows the screen impair.
var _goo := 0
## --flash: the local survivor is flashed, so a frame shows the white screen.
var _flash := false
## --aim=DEG: every stand-in but you holds this view pitch (up positive), so a frame from the
## side shows the figures' spines and gun arms following it (`"aim"` in ZzPlayer's set_motion).
var _aim := INF
## --alone: the stand-ins stay in the start room, out of a close-up.
var _alone := false
## --door=INDEX:open|closed[:SIDE]: that door frozen in that state (side 1 or -1 is the way it swings), for a frame of it.
var _doors: Array[String] = []
## --fire=TARGETNAME:Input: that map-logic input sent before the frame (a maker's ForceSpawn, to see its copies).
var _fires: Array[String] = []
## --tint: the fired copies drawn flat red and their sources blue, to find them in a frame.
var _tint := false
## `--reaction=<id>`: the ragdoll view forces that death reaction (sv_ragdoll_reactions).
var _reaction := &""
var _client: Node = null
var _weapons: PackedStringArray = PackedStringArray()
## --no-bake draws the map with live lamps (the look before bakes); --no-world draws a converted
## map's boxes instead of its own geometry (ZzMap.load_world); --day=0..1 holds the map's
## light at that daylight, to compare a night and a day frame on any map that has a day.
var _day := -1.0


## `--cloud-store=<dir>,<public key file>,<id@version>`: the delivery check. A dot-cloud client reads packs published
## into <dir> (<id>/<version>/manifest.json), trusting that key, and the map's world is fetched as <id>@<version>
## (its shared art slice follows as a dependency) instead of being read from the checkout. A <dir> that is a URL
## (`https://dotgames.org/content`) fetches from that origin, over the network, which is what a player's client does.
var _world_key := ""


## Holds the stand-ins' pitch (`--aim`), every frame and every physics tick.
const _AimHolder := preload("shot_aim_holder.gd")
const _ShotCamera := preload("shot_camera.gd")


## One contact sheet per weapon, through the real client and the real buttons: at the hip, two
## and six frames into a shot, and the reload at 15/25/40/50/57/75/88% by the drawn rig's own fraction,
## each tile labelled with the HUD's count. `_out` is the directory (`sheet_<id>.png` in it).
## What `--view=weapons --weapons=all` is for: a counter that never moves and a reload that is
## a single tilt are both things only a picture says.
## Arms [param id] and brings it into hand. Weapons share slots (the SMG and pistol are both 2), so
## the slot key alone shows whichever is on top: cycle the slot until [param id] is the one held.
func _hold_exact(game: ZzGame, local, id: StringName) -> bool:
	if not game.arm(local, id):
		print("skipped %s: not armed" % id)
		return false
	var def := ZzWeapons.def_of(id)
	_client.set("_slot", def.slot)
	var arsenal: DotWeaponArsenal = _client.get("weapons").arsenal
	await _seconds_of(0.8)
	for _i in 6:
		var now := arsenal.current()
		if now != null and now.def.id == id:
			return true
		var _cycled := arsenal.cycle_slot(Engine.get_physics_frames())
		await _seconds_of(0.8)
	print("could not bring %s into hand" % id)
	return false


## The figure holding each `--weapons=` id in third person (`held_<id>.png` in the `_out` directory).
func _held_third_frames(game: ZzGame, local) -> void:
	var dir := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(dir)
	local.health.invulnerable = true
	_client.call("toggle_view")
	var yaw := deg_to_rad(float(local.controller.state.yaw))
	var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var away: Vector3 = local.feet() - ahead * 30.0
	for other in game.survivors():
		if other != local:
			other.place_at(away, 0.0)
	# Low and close, the hand filling the frame, under a lamp of its own: the night map's own light left the gun a silhouette.
	var eye: Vector3 = local.feet() + ahead * 1.3 + ahead.cross(Vector3.UP) * 0.55 + Vector3.UP * 0.85
	var lamp := OmniLight3D.new()
	lamp.omni_range = 8.0
	lamp.light_energy = 3.0
	add_child(lamp)
	lamp.global_position = local.feet() + ahead * 1.6 + Vector3.UP * 1.8
	for name in _weapons:
		var id := StringName(name)
		if not await _hold_exact(game, local, id):
			continue
		await _seconds_of(1.0)
		_free_camera().look_at_from_position(eye, local.feet() + Vector3.UP * 0.95)
		await _frames(3)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var drawn: Variant = local.figure.held.equipped() if local.figure != null and local.figure.held != null else &"(none)"
		print("%s held (figure draws %s): %s" % [id, drawn, error_string(image.save_png(dir.path_join("held_%s.png" % id)))])
	lamp.queue_free()


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
		if def == null or not await _hold_exact(game, local, id):
			continue
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


## Down the sights, through the real client and its Aim key: per gun the hip, the gun coming up
## and fully aimed (`ads_<id>_<stage>.png` in the `_out` directory), with a line per frame of the
## crosshair's alpha, the scope's fraction and the lens. Defaults to one iron-sighted gun and one
## scoped one; `--weapons=` names others.
func _ads_frames(game: ZzGame, local) -> void:
	# Seated beside the camera, a team-mate's body fills the frame; a player never sees that from a seat's own eyes with a gun, so stand them behind.
	var yaw := deg_to_rad(float(local.controller.state.yaw))
	var behind: Vector3 = local.feet() + Vector3(sin(yaw), 0.0, cos(yaw)) * 5.0
	for other in game.survivors():
		if other != local:
			other.place_at(behind, 0.0)
	var ids: Array[StringName] = []
	if _weapons.is_empty():
		var iron := &""
		var scoped := &""
		for def in ZzWeapons.all_defs():
			var art := ZeeWeaponArtTable.get_art(def.id)
			if art == null or not art.aim_enabled or not def.uses_magazine():
				continue
			if art.aim_scoped and scoped == &"":
				scoped = def.id
			elif not art.aim_scoped and iron == &"" and ZzWeapons.tier_of(def.id) == &"primary":
				iron = def.id
		for id in [iron, scoped]:
			if id != &"":
				ids.append(id)
	else:
		for id in _weapons:
			ids.append(StringName(id))

	var dir := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(dir)
	var hud = _client.get("hud")
	for id in ids:
		var def := ZzWeapons.def_of(id)
		if def == null or not await _hold_exact(game, local, id):
			continue
		_client.set("_aiming", false)
		await _seconds_of(1.2)
		await _ads_save(dir, id, "hip", hud)
		_client.set("_aiming", true)
		await _frames(4)
		await _ads_save(dir, id, "raising", hud)
		await _seconds_of(0.8)
		await _ads_save(dir, id, "aimed", hud)
		_client.set("_aiming", false)


## The spread crosshair at rest, walking, running, crouched and aimed, through the real client's
## input actions (`crosshair_<stage>.png` in the `_out` directory), with the cone each frame shows.
func _crosshair_frames(game: ZzGame, local) -> void:
	var id: StringName = StringName(_weapons[0]) if not _weapons.is_empty() else &"zz_m4"
	if not game.arm(local, id):
		print("not armed with %s" % id)
		return
	local.health.invulnerable = true
	var dir := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(dir)
	_client.set("_slot", ZzWeapons.def_of(id).slot)
	var stages := {
		"rest": [], "walk": ["dot_fps_forward", "dot_fps_walk"], "run": ["dot_fps_forward", "dot_fps_sprint"],
		"crouch": ["dot_fps_crouch"], "aimed": [], "fired": [],
	}
	for stage: String in stages:
		for action: String in stages[stage]:
			Input.action_press(action)
		_client.set("_aiming", stage == "aimed")
		_client.set("_firing", stage == "fired")
		# The spread a shot kicks decays in well under a second: look at it while the trigger is held.
		await _seconds_of(0.25 if stage == "fired" else 1.5)
		await RenderingServer.frame_post_draw
		var hud = _client.get("hud")
		var image := get_viewport().get_texture().get_image()
		var path := dir.path_join("crosshair_%s.png" % stage)
		var held_slot = _client.get("weapons").arsenal.current()
		print("%s: spread %.2f gap %.1f mag %d bloom %.2f -> %s" % [stage, _client.get("weapons").arsenal.spread_now(),
			hud._crosshair.gap_pixels(), held_slot.magazine, float(held_slot.behaviour.state.get(&"bloom", 0.0)),
			error_string(image.save_png(path))])
		_client.set("_firing", false)
		for action: String in stages[stage]:
			Input.action_release(action)
		_client.set("_aiming", false)
		await _seconds_of(0.8)
	# Dead: the crosshair must be gone (DotCrosshair.alive_source), the rest of the HUD stays.
	local.health.alive = false
	await _seconds_of(0.5)
	await RenderingServer.frame_post_draw
	var dead_path := dir.path_join("crosshair_dead.png")
	print("dead: crosshair shown %s -> %s" % [_client.get("hud")._crosshair.is_shown(),
		error_string(get_viewport().get_texture().get_image().save_png(dead_path))])


## The stamina bar while sprinting: full, draining to half, empty (exhausted), then recovering
## (`stamina_<stage>.png`, with the controller's stamina printed): `--view=stamina`.
func _stamina_frames(local) -> void:
	local.health.invulnerable = true
	var dir := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(dir)
	var state: DotFpsState = local.controller.state
	state.stamina = 1.0
	Input.action_press("dot_fps_forward")
	Input.action_press("dot_fps_sprint")
	var hud = _client.get("hud")
	for stage: String in ["full", "half", "empty"]:
		var waited := 0.0
		if stage == "full":
			while waited < 3.0 and not state.sprinting:
				await _seconds_of(0.05)
				waited += 0.05
		else:
			while waited < 40.0 and (state.stamina > 0.5 if stage == "half" else not state.stamina_exhausted):
				await _seconds_of(0.1)
				waited += 0.1
		await _stamina_save(dir, stage, state, hud)
	Input.action_release("dot_fps_sprint")
	Input.action_release("dot_fps_forward")
	await _seconds_of(2.0)
	await _stamina_save(dir, "recovering", state, hud)
	await _seconds_of(6.0)
	await _stamina_save(dir, "recovered", state, hud)


func _stamina_save(dir: String, stage: String, state: DotFpsState, hud) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var bar: Control = hud.stamina_bar
	print("%s: stamina %.2f exhausted %s sprinting %s bar visible %s rect %s -> %s" % [stage, state.stamina,
		state.stamina_exhausted, state.sprinting, bar.visible, bar.get_global_rect(),
		error_string(image.save_png(dir.path_join("stamina_%s.png" % stage)))])


## The fire-mode indicator in each state the held gun offers: `--view=firemode [--weapons=zz_m4]`.
func _fire_mode_frames(game: ZzGame, local) -> void:
	var id: StringName = StringName(_weapons[0]) if not _weapons.is_empty() else &"zz_m4"
	if not game.arm(local, id):
		print("not armed with %s" % id)
		return
	local.health.invulnerable = true
	var dir := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(dir)
	var arsenal: DotWeaponArsenal = _client.get("weapons").arsenal
	var _picked := arsenal.select(ZzWeapons.def_of(id).slot, 0)
	await _seconds_of(2.0)
	for mode in arsenal.fire_modes_available():
		var _set := arsenal.set_fire_mode(mode)
		await _seconds_of(0.6)
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := dir.path_join("firemode_%d.png" % mode)
		print("mode %d -> %s" % [mode, error_string(image.save_png(path))])


func _ads_save(dir: String, id: StringName, stage: String, hud) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := dir.path_join("ads_%s_%s.png" % [id, stage])
	var camera: Camera3D = _client.get("camera")
	print("%s %s: crosshair %.2f scope %.2f fov %.1f -> %s" % [id, stage,
		hud._crosshair.aim_opacity if hud != null and hud._crosshair.get(&"aim_opacity") != null else -1.0, hud.scope.fraction if hud != null else -1.0,
		camera.fov if camera != null else -1.0, error_string(image.save_png(path))])


func _tile(label: Label, id: StringName, what: String) -> Image:
	var hud = _client.get("hud")
	label.text = "%s · %s · HUD %s" % [id, what, hud.ammo.count_text() if hud != null else "?"]
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


func _survival_frame(game: ZzGame, local) -> void:
	local.health.invulnerable = true

	if _at != Vector3.INF and _view == "wave":
		local.place_at(_at, 0.0)

	var until := Time.get_ticks_msec() + int(_seconds * 1000.0)

	while Time.get_ticks_msec() < until:
		if _view == "wave" and _at != Vector3.INF and local.feet().distance_to(_at) > 1.5:
			local.place_at(_at, 0.0)
		if _view == "wave" and _look != Vector3.INF:
			_face(local, _look)
		await get_tree().process_frame

	if _view == "wave_cam":
		_free_camera().look_at_from_position(_at, _look if _look != Vector3.INF else _at + Vector3(0, 0, -10))
	elif _look != Vector3.INF:
		_face(local, _look)

	await _frames(3)
	print("hold: %s" % str(game.survival_state()))
	print("zombies: %d, wave alive %d" % [game.horde.count(), game.horde.wave_alive()])
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := image.save_png(path)
	print("saved %s (%s): %s" % [_out, _view, error_string(saved)])
	await DotShotSeq.new().record(get_tree(), path)
	get_tree().quit(0 if saved == OK else 1)


## The stand-ins sent out of the frame, so a close first-person shot is not a head.
func _clear_view(game: ZzGame, local, stand: Vector3) -> void:
	for p in game.survivors():
		if p != local:
			p.place_at(stand + Vector3(0.0, 0.0, 400.0), 0.0)


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


## --view=break: a barricade and a support of the map broken in front of a free camera, frames before and after (_<what>_<t>.png).
func _view_break(game: ZzGame) -> void:
	var platform: DotGameClient = _client.get("platform")
	while not platform.is_shown():
		await get_tree().process_frame
	await _seconds_of(2.5)
	var camera := _free_camera()
	var targets: Array = []
	_synth_support(game)
	var ids := game.map.barricade_ids()
	if ids.size() > 0:
		targets.append(["barricade", game.map.barricade_bounds(ids[0]), ids[0]])
	if game.map.supports.size() > 0:
		targets.append(["support", game.map.supports[0].box, 0])
	print("break targets: %d (barricades %d, supports %d)" % [targets.size(), ids.size(), game.map.supports.size()])
	for t in targets:
		var box: AABB = t[1]
		var centre := box.get_center()
		var reach := maxf(box.get_longest_axis_size() * 1.6, 3.0)
		print("break %s: centre %s size %s" % [t[0], centre.snapped(Vector3.ONE * 0.01), box.size.snapped(Vector3.ONE * 0.01)])
		camera.look_at_from_position(centre + Vector3(reach * 0.6, reach * 0.35, reach * 0.8), centre)
		var pose := camera.global_transform
		var until := Time.get_ticks_msec() + 800
		while Time.get_ticks_msec() < until:
			camera.global_transform = pose
			camera.current = true
			await get_tree().process_frame
		await _grab("%s_0_before" % t[0])
		if t[0] == "barricade":
			game.map.set_barricade(t[2], false, 0.0)
		else:
			game.map.supports[t[2]].apply_broken(centre)
		var t0 := Time.get_ticks_msec()
		for mark in [0.1, 0.3, 1.0, 4.0]:
			while (Time.get_ticks_msec() - t0) < int(mark * 1000.0):
				camera.global_transform = pose
				camera.current = true
				await get_tree().process_frame
			await _grab("%s_%s" % [t[0], str(mark)])


## No converted map marks a support yet: make one of the world's first non-glass breakable so the break can be seen.
func _synth_support(game: ZzGame) -> void:
	if game.map.supports.size() > 0:
		return
	var id := String(game.map.id())
	var text := FileAccess.get_file_as_string("res://world/zz_world_%s/%s.json" % [id, id])
	var manifest: Variant = JSON.parse_string(text)
	if not (manifest is Dictionary):
		return
	for rec: Dictionary in manifest.get("breakables", []):
		if rec.get("glass") == null and rec.has("bounds"):
			var built := DotMapSupport.build_all([rec], game.physics.layer_mask(&"toy"), true)
			for support in built:
				game.map.add_child(support)
				game.map.supports.append(support)
				var _c := support.broken.connect(game.map._on_support_broken.bind(0))
			game.map._bind_support_visuals()
			return


func _grab(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(_out.get_basename() + "_" + tag + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("saved %s: %s" % [path, error_string(get_viewport().get_texture().get_image().save_png(path))])


func _free_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.set_script(_ShotCamera)
	camera.set(&"client", _client)
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
	var gaps := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		gaps.append(float(now - last) / 1000.0)
		last = now
	# A frame time a run can be compared by (ms, first fifth dropped as warm-up): the number a
	# texture or light change is judged on, on the GPU box through ../gpu.sh.
	if seconds >= 3.0 and gaps.size() > 10:
		var kept := gaps.slice(gaps.size() / 5)
		kept.sort()
		var sum := 0.0
		for g in kept:
			sum += g
		print("FRAME_MS mean=%.2f p95=%.2f n=%d" % [sum / kept.size(), kept[int(kept.size() * 0.95)], kept.size()])


func _save_extra(suffix: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path(_out.trim_suffix(".png") + suffix + ".png")
	print("wrote ", path, ": ", error_string(get_viewport().get_texture().get_image().save_png(path)))


## The clip must start after the loading cover lifts, or it is spent unseen.
func _until_uncovered() -> void:
	var gate: DotLoadGate = _client.get("gate")
	for _i in range(1200):
		if gate == null or gate.is_open():
			break
		await get_tree().process_frame


## Stops a stand-in's bot, sets it down once and lets it settle, so the clip is not cancelled by a
## walking or falling pose (a full-body action ends the moment its figure moves).
func _settle(actor: Object) -> void:
	actor.set("is_bot", false)
	actor.place_at(actor.controller.state.position, actor.controller.state.yaw)
	await _seconds_of(0.6)
	# Dropped from above the floor it is still falling: wait for it to land, or the clip ends at once.
	var waited := 0
	while waited < 600 and actor.figure.body_node().get("state") != DotPlayerAnimState.IDLE:
		await get_tree().process_frame
		waited += 1
	await _seconds_of(0.2)


## Waits [param seconds], printing the figure's state at the end of it.
func _pin_for(actor: Object, seconds: float) -> void:
	await _seconds_of(seconds)
	var body: Object = actor.figure.body_node()
	print("actor action=", body.get("action"), " state=", body.get("state"))
