extends "shot_views.gd"

const _BenchCrowd := preload("bench_sim_crowd.gd")


func _cloud_store(spec: String) -> void:
	var parts := spec.split(",")
	var config := DotCloudConfig.new()
	config.cache_dir = "user://store_e2e_cache"
	DotPaths.remove_tree(config.cache_dir)
	config.require_signed_manifests = true
	var pub := FileAccess.get_file_as_string(parts[1])
	config.trusted_keys = {"e2e": pub, "default": pub}
	var cloud := DotCloudClient.new()
	cloud.name = "Cloud"
	cloud.config = config
	cloud.config_file = ""
	if parts[0].begins_with("http"):
		cloud.http_base_urls = PackedStringArray([parts[0]])
	else:
		cloud.local_search_dirs = PackedStringArray([parts[0]])
	cloud.allow_netchan_fallback = false
	add_child(cloud)
	ZzMap.local_worlds = false
	_world_key = parts[2]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if _orbit.take(arg):
			continue
		_take_arg(arg)

	_client = ZzClient.new()
	_client.name = "Client"
	_client.set("force_offline", true)
	_client.set("standalone_content", false)
	_client.set("offline_bots", 3)
	add_child(_client)
	if _world_key != "":
		_client.get("game").world_key_fn = func(_doc: Dictionary) -> String: return _world_key
	# --view=cover: the loading cover dot-game's DotGameClient puts up first, before it lifts.
	if _view == "cover":
		for _i in 2:
			await RenderingServer.frame_post_draw
		var platform: DotGameClient = _client.get("platform")
		print("cover %s" % ("lifted" if platform.is_shown() else "up"))
		var cover_path := ProjectSettings.globalize_path(_out)
		DirAccess.make_dir_recursive_absolute(cover_path.get_base_dir())
		print("saved %s: %s" % [_out, error_string(_client.get_viewport().get_texture().get_image().save_png(cover_path))])
		get_tree().quit(0)
		return
	_run.call_deferred()


func _take_arg(arg: String) -> void:
	if arg.begins_with("--view="):
		_view = arg.trim_prefix("--view=")
	elif arg.begins_with("--action="):
		_action = arg.trim_prefix("--action=")
	elif arg == "--board":
		_board = true
	elif arg == "--touch=1":
		DotPlatform.touch_override = 1
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
	elif arg.begins_with("--zombie="):
		_zombie = StringName(arg.trim_prefix("--zombie="))
	elif arg.begins_with("--sever="):
		_sever = arg.trim_prefix("--sever=").split(",", false)
	elif arg.begins_with("--pin="):
		_pin = StringName(arg.trim_prefix("--pin="))
	elif arg == "--pin-me":
		_pin_me = true
	elif arg.begins_with("--reaction="):
		_reaction = StringName(arg.trim_prefix("--reaction="))
	elif arg == "--as-spawned":
		_as_spawned = true
	elif arg == "--alone":
		_alone = true
	elif arg.begins_with("--door="):
		_doors.append(arg.trim_prefix("--door="))
	elif arg == "--tint":
		_tint = true
	elif arg.begins_with("--fire="):
		_fires.append(arg.trim_prefix("--fire="))
	elif arg.begins_with("--weapons="):
		_weapons = arg.trim_prefix("--weapons=").split(",", false)
	elif arg.begins_with("--frames="):
		_frame_count = clampi(arg.trim_prefix("--frames=").to_int(), 1, 48)
	elif arg.begins_with("--aim="):
		_aim = arg.trim_prefix("--aim=").to_float()
	elif arg.begins_with("--hard="):
		_hard = arg.trim_prefix("--hard=").to_int()
	elif arg == "--flash":
		_flash = true
	elif arg.begins_with("--goo="):
		_goo = arg.trim_prefix("--goo=").to_int()
	elif arg.begins_with("--box="):
		_box = StringName(arg.trim_prefix("--box="))
	elif arg == "--workshop":
		_subscribe_fixture()
	elif arg == "--no-bake":
		ZzMap.use_bakes = false
	elif arg == "--no-world":
		ZzMap.use_worlds = false
	elif arg.begins_with("--cloud-store="):
		_cloud_store(arg.trim_prefix("--cloud-store="))
	elif arg.begins_with("--day="):
		_day = arg.trim_prefix("--day=").to_float()


## --workshop: a subscribed pack whose one map is a document (the practice street under another
## id) in the process's shared index, solo. Pair with --zz-map-ids=fixture_ruin to play only it.
func _process(_delta: float) -> void:
	if _day < 0.0 or _client == null:
		return
	var game: Variant = _client.get("game")
	if game != null and game.map != null:
		game.map.set_daylight(_day)


static func _subscribe_fixture() -> void:
	var dir := "user://ws_fixture_shot/"
	var _made := DirAccess.make_dir_recursive_absolute(dir)
	var doc := ZzCatalogue.practice().duplicate(true)
	doc["id"] = "fixture_ruin"
	doc["name"] = "Fixture Ruin"
	var f := FileAccess.open(dir + "ruin.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	var added := DotContentIndex.shared().add_pack({
		"content_id": "fixture/ruins", "version": "1.0.0", "prefix": dir,
		"session": DotContentIndex.SESSION_SOLO, "source": &"subscription",
		"provides": {"schema": 1, "title": "Ruins Pack", "kinds": ["map"], "entries": [
			{"kind": "map", "id": "fixture_ruin", "name": "Fixture Ruin", "scene": "ruin.json", "map_kind": "exodus"},
		]},
	})
	print("workshop fixture: ", added.ok)


static func _v3(text: String) -> Vector3:
	var parts := text.split(",")
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float()) if parts.size() == 3 else Vector3.INF


## Where everybody is put when --at is not given (tools/bench_sim_crowd.gd's rule, which a hosted bench's server
## half uses too): the practice street's open ground at z 12, or the first survivor seat where that point is not on
## ground inside the map's navigation (zz-ravenstreet-1: a frame of the whole team falling from a void).
func _default_stand(game: ZzGame) -> Vector3:
	return _BenchCrowd.default_stand(game)


## Waits for the delivered world (and its art slice, hundreds of MB), as a player does.
func _await_world(game: ZzGame) -> void:
	if _world_key != "":
		# The delivered world (and its art slice, hundreds of MB) arrives under the cover: wait for it, as a player does.
		# The client's first round began before world_key_fn was set, so that map has no key: ask for the world now,
		# or this waits out a whole round (261 s on the GPU box) for the next map to carry the key.
		var started := Time.get_ticks_msec()
		if not game.map.world_drawn:
			game.map.doc["world_key"] = _world_key
			await game.map.load_world()
		var waited := 0.0
		while not game.map.world_drawn and waited < 300.0:
			await get_tree().create_timer(1.0).timeout
			waited += 1.0
		print("delivered world drawn=%s after %.1f s; credits: %s" % [game.map.world_drawn, (Time.get_ticks_msec() - started) / 1000.0, game.map.world_credits])


## Opens or closes the doors named by --door and fires the logic named by --fire, printing what the copies look like.
func _drive_mechanics(game: ZzGame) -> void:
	if not _doors.is_empty() and game.map.mechanics != null:
		var mech: ZzMechanics = game.map.mechanics
		mech.authoritative = false
		for spec in _doors:
			var bits := spec.split(":")
			var opened := bits.size() > 1 and bits[1] == "open"
			mech.apply_state(bits[0].to_int(), 0, 1000 if opened else 0, 0, false, bits[2].to_float() if bits.size() > 2 else 1.0)

	if not _fires.is_empty() and game.map.mechanics != null and game.map.mechanics.logic() != null:
		for spec in _fires:
			var bits := spec.split(":")
			var sent: DotResult = game.map.mechanics.logic().send(bits[0], bits[1])
			print("fire ", spec, " -> ", sent.ok, " copies ", game.map.mechanics.copies())
			for cid: int in (game.map.mechanics.get("_copies") as Dictionary):
				var cn: Variant = (game.map.mechanics.get("_copies") as Dictionary)[cid]["node"]
				var sn: Variant = (game.map.mechanics.get("_model_nodes") as Dictionary).get(int((game.map.mechanics.get("_copies") as Dictionary)[cid]["model"]))
				var box := AABB()
				var first := true
				for mi in (cn as Node).find_children("*", "MeshInstance3D", true, false):
					var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
					box = a if first else box.merge(a)
					first = false
				var sbox := AABB()
				first = true
				for mi in (sn as Node).find_children("*", "MeshInstance3D", true, false):
					var a2: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
					sbox = a2 if first else sbox.merge(a2)
					first = false
				var vis := 0
				for mi in (cn as Node).find_children("*", "MeshInstance3D", true, false):
					vis += 1 if (mi as MeshInstance3D).is_visible_in_tree() else 0
					if _tint:
						var red := StandardMaterial3D.new()
						red.albedo_color = Color(1, 0, 0)
						red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						(mi as MeshInstance3D).material_override = red
				if _tint and sn != null:
					var blue := StandardMaterial3D.new()
					blue.albedo_color = Color(0, 0, 1)
					blue.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					(sn as Node3D).visible = true
					for mi in (sn as Node).find_children("*", "MeshInstance3D", true, false):
						(mi as MeshInstance3D).material_override = blue
				print("copy meshes visible ", vis, " in_tree ", (cn as Node3D).is_visible_in_tree())
				print("copy aabb ", box, " src aabb ", sbox)
				print("copy node ", cn, " ", (cn as Node3D).global_position if cn != null else "none", " src ", (sn as Node3D).global_position if sn != null else "none", " src visible ", (sn as Node3D).visible if sn != null else "-")


func _run() -> void:
	var game: ZzGame = _client.get("game")
	await _until_a_round(game)
	var local = _client.get("player")
	await _await_world(game)
	# Waits past the load cover (slow on a cold GPU box) before any timing starts; capped, so a stuck cover cannot hang the shot.
	if not await DotShotGate.wait_lifted(get_tree(), _client.get("platform")):
		printerr("shot: load cover still up after the wait; shooting anyway")
	# A survival hold in play: the stand-ins keep playing (their posts, the barricades), you are
	# put at --at looking at --look, and the frame is taken --seconds in, with the HUD (`wave`)
	# or from a free camera at --at (`wave_cam`).
	if _view == "wave" or _view == "wave_cam":
		await _survival_frame(game, local)
		return
	var stand := _stage(game, local)
	await _seconds_of(0.4)
	_spawn_requested(game, local, stand)
	_apply_effects(game, local, stand)
	match _view:
		"overview":
			await _view_overview(game, local, stand)
		"break":
			await _view_break(game)
			get_tree().quit(0)
			return
		"room":
			await _view_room(game, local, stand)
		"crates":
			await _view_crates(game, local, stand)
		"mutant":
			await _view_mutant(game, local, stand)
		"walk":
			await _view_walk(game, local, stand)
		"fire":
			await _view_fire(game, local, stand)
		"third":
			_client.call("toggle_view")
			await _seconds_of(_seconds)
		"down":
			await _view_down(game, local, stand)
		"strike", "strike_down", "pin":
			await _view_strike(game, local, stand)
		"killcam", "reveal":
			await _view_killcam(game, local, stand)
		"possess":
			await _view_possess(game, local, stand)
		"ending", "trail":
			await _view_ending(game, local, stand)
		"crawl", "crawl_third", "crawl_down":
			await _view_crawl(game, local, stand)
		"deploy", "deploy_third", "deploy_side":
			await _view_deploy(game, local, stand)
		"boxgun":
			await _view_boxgun(game, local, stand)
		"pickup":
			await _view_pickup(game, local, stand)
		"carry":
			await _view_carry(game, local, stand)
		"defib", "defib_third", "defib_ground":
			await _view_defib(game, local, stand)
		"trader":
			await _view_trader(game, local, stand)
		"hit":
			await _view_hit(game, local, stand)
		"ads", "crosshair", "stamina", "firemode", "held", "weapons", "reload":
			await _standalone_frames(game, local)
			get_tree().quit(0)
			return
		"ragdoll":
			await _view_ragdoll(game, local, stand)
		"defib_other":
			await _view_defib_other(game, local, stand)
		"action":
			await _view_action(game, local, stand)
		"pinned":
			await _view_pinned(game, local, stand)
		_:
			await _seconds_of(_seconds)
	await _finish(local, stand)


## Out of the start room, the survivors put on their seats (or at --at), facing --look, mechanics driven, the aim held.
func _stage(game: ZzGame, local) -> Vector3:
	# Out of the start room, so the horde is running, and the stand-ins held where they are put.
	if not _as_spawned:
		for player in game.survivors():
			player.is_bot = false
			player.health.invulnerable = true
	var stand := _at if _at != Vector3.INF else _default_stand(game)
	# Facing the way the map's first seat faces (a frame that ignores it stares at whatever is
	# behind that seat's back, which once read as a map that starts you against a wall).
	if not _as_spawned:
		local.place_at(stand, float(game.map.spawn("survivors", 0)[1]) if _at == Vector3.INF else 0.0)
	var i := 0
	for player in game.survivors():
		if player != local and not _as_spawned:
			i += 1
			# Off the practice street's open ground the offset spot is as likely a void as not (the seat
			# fallback above), so each stand-in takes its own seat.
			var on_seat := _alone or (_at == Vector3.INF and stand != Vector3(0.0, 0.05, 12.0))
			var seat: Array = game.map.spawn("survivors", i)
			player.place_at(seat[0] if on_seat else stand + Vector3(-1.6 + float(i) * 1.1, 0.0, 1.8), float(seat[1]) if on_seat else 0.0)
	if _look != Vector3.INF:
		_face(local, _look)
	_drive_mechanics(game)
	if _aim != INF:
		# Written before anything else runs each frame: the stand-ins' empty commands would
		# put their pitch back to level.
		var holder := Node.new()
		holder.process_priority = -1000000
		holder.set_script(_AimHolder)
		holder.set(&"players", game.survivors().filter(func(p) -> bool: return p != local))
		holder.set(&"pitch", _aim)
		add_child(holder)
	return stand


## An orbit, or the scoreboard, then the frame saved as --out.
func _finish(local, stand: Vector3) -> void:
	if _orbit.enabled:
		_orbit.me = local
		_orbit.point = _at if _at != Vector3.INF else stand
		await _orbit_frames()
		get_tree().quit(0)
		return
	if _board:
		var tab := InputEventKey.new()
		tab.physical_keycode = KEY_TAB
		tab.pressed = true
		_client.settings.menu.handle_event(tab)
	await _frames(3)
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var saved := image.save_png(path)
	print("saved %s (%s): %s" % [_out, _view, error_string(saved)])
	await DotShotSeq.new().record(get_tree(), path)
	get_tree().quit(0 if saved == OK else 1)


func _spawn_requested(game: ZzGame, local, stand: Vector3) -> void:
	for entry: Array in _spawn:
		for n in int(entry[1]):
			var at := stand + Vector3(randf_range(-3.0, 3.0), 0.0, -6.0 - randf_range(0.0, 8.0))
			var npc: DotNpcInstance = game.horde.call(&"spawn_brute", at) if entry[0] == ZzNpcs.BRUTE \
				else game.horde.spawner.spawn(entry[0], game.horde.snap_to_nav(at), &"shot", Basis(Vector3.UP, PI))
			if npc != null and npc.brain != null and entry[0] == ZzNpcs.COMMON:
				npc.brain.call(&"force_target", local.player_id)
			var body: Node3D = npc.node if npc != null else null
			if body != null and body.get(&"limbs") != null:
				for limb in _sever:
					body.limbs.sever(StringName(limb), body.global_position + Vector3(0.0, 1.2, 0.0), Vector3(0.0, 2.0, 1.0))


func _apply_effects(game: ZzGame, local, stand: Vector3) -> void:
	if _flash:
		local.flash_until = game.now() + 600.0
	if _goo > 0:
		local.goo_stacks = _goo
		local.goo_until = game.now() + 600.0
	for _stack in _hard:
		game.boxes.run([{"do": "effect", "name": "hard"}], {"opener": local, "at": stand, "box": &"hard"})
	if _box != &"" and game.boxes != null:
		var _dropped := game.boxes.drop(_box, stand + Vector3(0.0, 0.0, -2.2))


func _standalone_frames(game: ZzGame, local) -> void:
	match _view:
		"ads":
			await _ads_frames(game, local)
		"crosshair":
			await _crosshair_frames(game, local)
		"stamina":
			await _stamina_frames(local)
		"firemode":
			await _fire_mode_frames(game, local)
		"held":
			await _held_third_frames(game, local)
		"weapons":
			await _weapon_sheets(game, local)
		"reload":
			await _reload_shots(game, local)
