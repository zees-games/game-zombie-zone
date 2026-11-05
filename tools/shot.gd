extends "shot_base.gd"

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


## Where everybody is put when --at is not given: the practice street's open ground at z 12, or
## the first survivor seat on a map with nothing under that point. A converted street has a
## void there, and a frame taken from it showed the whole team falling, which read as a broken
## map when it was only this tool standing them in the air (zz-ravenstreet-1).
func _default_stand(game: ZzGame) -> Vector3:
	var usual := Vector3(0.0, 0.05, 12.0)
	var space := game.get_world_3d().direct_space_state
	var mask := game.physics.layer_mask(&"world")
	var down := PhysicsRayQueryParameters3D.create(usual + Vector3(0.0, 1.0, 0.0), usual + Vector3(0.0, -0.6, 0.0), mask)

	# Ground under it is not enough: a converted yard's slab runs past its own fence, and the
	# point can be on the slab's rim, outside every floor the map has (a frame of the whole team
	# falling, again). It must also be in a floor of the map's own navigation.
	var inside := false
	for f in ((game.map.doc.get("nav", {}) as Dictionary).get("floors", []) as Array):
		if usual.x >= float(f[0]) and usual.x <= float(f[2]) and usual.z >= float(f[1]) and usual.z <= float(f[3]):
			inside = true

	if inside and not space.intersect_ray(down).is_empty():
		return usual

	var seat: Vector3 = game.map.spawn("survivors", 0)[0]
	return seat + Vector3(0.0, 0.05, 0.0)


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

	# A survival hold in play: the stand-ins keep playing (their posts, the barricades), you are
	# put at --at looking at --look, and the frame is taken --seconds in, with the HUD (`wave`)
	# or from a free camera at --at (`wave_cam`).
	if _view == "wave" or _view == "wave_cam":
		await _survival_frame(game, local)
		return

	# Out of the start room, so the horde is running, and the stand-ins held where they are put.
	for player in game.survivors():
		player.is_bot = false
		player.health.invulnerable = true

	var stand := _at if _at != Vector3.INF else _default_stand(game)
	# Facing the way the map's first seat faces (a frame that ignores it stares at whatever is
	# behind that seat's back, which once read as a map that starts you against a wall).
	local.place_at(stand, float(game.map.spawn("survivors", 0)[1]) if _at == Vector3.INF else 0.0)

	var i := 0
	for player in game.survivors():
		if player != local:
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

	await _seconds_of(0.4)

	for entry: Array in _spawn:
		for n in int(entry[1]):
			var at := stand + Vector3(randf_range(-3.0, 3.0), 0.0, -6.0 - randf_range(0.0, 8.0))
			var npc: DotNpcInstance = game.horde.spawn_brute(at) if entry[0] == ZzNpcs.BRUTE \
				else game.horde.spawner.spawn(entry[0], game.horde.snap_to_nav(at), &"shot", Basis(Vector3.UP, PI))
			if npc != null and npc.brain != null and entry[0] == ZzNpcs.COMMON:
				npc.brain.call(&"force_target", local.player_id)
			var body: Node3D = npc.node if npc != null else null
			if body != null and body.get(&"limbs") != null:
				for limb in _sever:
					body.limbs.sever(StringName(limb), body.global_position + Vector3(0.0, 1.2, 0.0), Vector3(0.0, 2.0, 1.0))

	if _flash:
		local.flash_until = game.now() + 600.0

	if _goo > 0:
		local.goo_stacks = _goo
		local.goo_until = game.now() + 600.0

	for _stack in _hard:
		game.boxes.run([{"do": "effect", "name": "hard"}], {"opener": local, "at": stand, "box": &"hard"})

	if _box != &"" and game.boxes != null:
		var _dropped := game.boxes.drop(_box, stand + Vector3(0.0, 0.0, -2.2))

	match _view:
		"overview":
			await _frames(6)
			var box: AABB = game.map.bounds()
			var centre := box.get_center()
			var reach := maxf(box.size.length() * 0.42, 14.0)
			_free_camera().look_at_from_position(centre + Vector3(reach * 0.45, reach * 0.6, reach * 0.55), centre)
		"break":
			await _view_break(game)
			get_tree().quit(0)
			return
		"room":
			await _seconds_of(_seconds)
			if _aim != INF:
				# --at is where everybody stands: look along the stand-ins' row from the side.
				_free_camera().look_at_from_position(stand + Vector3(4.5, 0.4, 1.8), stand + Vector3(0.0, 1.0, 1.8))
			else:
				_free_camera().look_at_from_position(_at, _look)
		"crates":
			# A ring of ammo piles and boxes, a blast in the middle, and frames before it and 0.35 s and --seconds after.
			_clear_view(game, local, stand)
			var middle := stand + Vector3(0.0, 0.0, -5.0)
			for n in 8:
				var a := float(n) * TAU / 8.0
				var spot := middle + Vector3(cos(a), 0.0, sin(a)) * 1.6
				var _id := game.loot.add(ZzLoot.AMMO if n % 2 == 0 else ZzLoot.BOX, &"", game.ray_hit(spot + Vector3.UP, spot + Vector3.DOWN * 4.0), 600.0)
			await _seconds_of(1.0)
			# Low and close: a crate is 0.3 m, and from the side a launch shows as crates leaving the ring.
			_free_camera().look_at_from_position(middle + Vector3(3.6, 0.9, -2.4), middle + Vector3(0.0, 0.3, 0.0))
			await _save_extra("_before")
			game.explode(middle + Vector3(0.0, 0.3, 0.0), 6.0, 50.0, -1, &"grenade", 0.0)
			await _save_extra("_t0")
			await _seconds_of(0.35)
			await _save_extra("_t035")
			await _seconds_of(maxf(_seconds - 0.35, 0.65))
		"mutant":
			# A mutant 9 m off, angry and flying: taking flight at once, then
			# frames as it cruises, charges and dives (_a, _b, _c, each --seconds apart).
			_clear_view(game, local, stand)
			var mut: DotNpcInstance = game.horde.spawn_special(&"mutant", game.horde.snap_to_nav(stand + Vector3(-9.0, 0.0, -5.0)))
			if mut != null and mut.brain != null:
				mut.brain.call(&"take_flight", 30.0)
			# Deterministic: climb to altitude, then fire the guns, then force the dive; frames around each.
			# Kept on the mutant itself: it flies off, so a camera aimed at a fixed point shows sky.
			var mut_cam := _free_camera()
			mut_cam.track_offset = Vector3(-5.0, 1.0, -5.0)
			mut_cam.track = func() -> Variant: return mut.position() + Vector3(0.0, 1.5, 0.0) if mut != null and mut.node != null else null
			var brain = mut.brain if mut != null else null
			var waited := 0.0
			while brain != null and waited < 15.0 and mut.position().y - stand.y < 7.0:
				await _seconds_of(0.25)
				waited += 0.25
			await _save_extra("_a_altitude")
			if brain != null:
				print("mutant altitude: %s state=%s" % [mut.position(), brain.get(&"state")])
				brain.call(&"zap_now")
				await _save_extra("_b_zap0")
				await _seconds_of(0.1)
				brain.call(&"zap_now")
				await _save_extra("_b_zap1")
				brain.call(&"force_dive")
				await _seconds_of(0.5)
				await _save_extra("_c_charge")
				var guard := 0.0
				while brain.get(&"state") != &"dive" and guard < 8.0:
					await _seconds_of(0.25)
					guard += 0.25
				for suffix in ["_d_dive0", "_e_dive1", "_f_dive2"]:
					print("mutant %s: %s state=%s" % [suffix, mut.position(), brain.get(&"state")])
					await _save_extra(suffix)
					await _seconds_of(0.2)
		"walk":
			# A filmstrip of --zombie=<kind> walking at the survivor: a frame every 0.15 s for --seconds,
			# a camera tracking it from the side (walk_00.. beside --out).
			_clear_view(game, local, stand)
			var walker: DotNpcInstance = game.horde.spawner.spawn(_zombie, game.horde.snap_to_nav(stand + Vector3(2.0, 0.0, -9.0)), &"shot", Basis(Vector3.UP, PI))
			if walker != null and walker.brain != null:
				walker.brain.call(&"force_target", local.player_id)
			var walk_cam := _free_camera()
			walk_cam.track_offset = Vector3(4.0, 1.2, 0.0)
			walk_cam.track = func() -> Variant: return walker.position() + Vector3(0.0, 0.9, 0.0) if walker != null and walker.node != null else null
			for n in int(_seconds / 0.15):
				await _save_extra("_%02d" % n)
				await _seconds_of(0.15)
		"fire":
			# A Molotov pool lit a few metres ahead, from a low three-quarter camera.
			_clear_view(game, local, stand)
			var pool := stand + Vector3(0.0, 0.0, -5.0)
			var _burning := game.hazards.add(&"fire", game.ray_hit(pool + Vector3.UP, pool + Vector3.DOWN * 4.0), 1.6, 20.0, 6.0, 0)
			_free_camera().look_at_from_position(pool + Vector3(2.6, 1.4, 2.6), pool + Vector3(0.0, 0.7, 0.0))
			await _seconds_of(_seconds)
		"third":
			_client.call("toggle_view")
			await _seconds_of(_seconds)
		"down":
			local.health.invulnerable = false
			var hit := DotDamage.make(0, local.entity_id, 500.0, game.combat.damage_type(&"strike"))
			var _applied = game.combat.apply_damage(hit)
			local.health.invulnerable = true
			await _seconds_of(_seconds)
		"strike", "strike_down", "pin":
			# One zombie (--zombie=common|crawler|...) a step from the survivor, swinging at them
			# standing or, for strike_down, downed; a free camera from the side.
			if _view == "strike_down":
				local.health.invulnerable = false
				var floored := DotDamage.make(0, local.entity_id, 500.0, game.combat.damage_type(&"strike"))
				var _felled = game.combat.apply_damage(floored)
				local.health.invulnerable = true
			var foe: DotNpcInstance = game.horde.spawner.spawn(_zombie, game.horde.snap_to_nav(stand + Vector3(0.0, 0.0, -1.2)), &"shot", Basis(Vector3.UP, PI))
			if foe != null and foe.brain != null:
				foe.brain.call(&"force_target", local.player_id)
			if _view == "pin" and foe != null:
				var how: StringName = {&"rider": &"ride", &"crawler": &"grab", &"ram": &"carry"}.get(_zombie, &"pounce")
				print("pin: ", how, " held ", game.horde.pin(foe, local.player_id, how))
			await _seconds_of(_seconds)
			var mid: Vector3 = local.feet().lerp(foe.position(), 0.5) if foe != null else local.feet()
			print("strike: survivor ", local.feet(), " zombie ", foe.position() if foe != null else "none", " anim ", foe.node.get(&"anim") if foe != null else "")
			var side := -1.0 if _view == "pin" else 1.0
			_free_camera().look_at_from_position(mid + Vector3(3.2 * side, 1.8, 1.2), mid + Vector3(0.0, 0.8 if _view == "pin" else 0.6, 0.0))
			await _seconds_of(0.2)
		"killcam", "reveal":
			# The last survivor falls and the map is lost; --seconds is how long after, so ~3 is the
			# replay and ~9 the podium.
			await _seconds_of(4.0)
			for who in game.survivors():
				who.health.invulnerable = false
				var blow := DotDamage.make(0, who.entity_id, 9999.0, game.combat.damage_type(&"strike"))
				var _felled = game.combat.apply_damage(blow)
			game._decide(false, "the horde took the last survivor")
			await _seconds_of(_seconds)
		"ending", "trail":
			# A map's ending camera 7 m ahead and up, mid-glide (--seconds in); `trail` instead follows a node
			# the resolver found by name round a circle in front of the eyes, so the ribbon is in the frame.
			if _view == "ending":
				game.end_camera_rules.blend = 0.3
				game.end_camera_rules.orbit = 30.0
				game.map_ending.emit(true, 1.0, 20.0, stand + Vector3(5.0, 4.0, -7.0))
			else:
				# A free camera 5 m from a mover crossing the view at 3 m/s: the ribbon is seen from the side, with the
				# stand-ins sent away so nothing else fills the frame.
				_clear_view(game, local, stand)
				var cam := _free_camera()
				var eye := stand + Vector3(0.0, 1.7, 0.0)
				cam.look_at_from_position(eye, eye + Vector3(0.0, 0.25, -5.0))
				var mover := Node3D.new()
				mover.name = "shot_mover"
				game.map.add_child(mover)
				var trail := DotMapTrail.new()
				trail.follow = mover
				trail.lifetime = 1.4
				trail.start_width = 0.4
				trail.colour = Color(1.0, 0.6, 0.2)
				game.map.add_child(trail)
				var found: Node3D = game.map.find_child("shot_mover", true, false)
				print("resolved ", found == mover)
				# Real time, not a count of timer ticks: a slow software frame would otherwise outrun the trail's lifetime.
				var began := Time.get_ticks_msec()
				var t := 0.0
				while t < _seconds:
					t = float(Time.get_ticks_msec() - began) / 1000.0
					mover.global_position = eye + Vector3(-3.5 + t * 3.0, 0.4 + sin(t * 5.0) * 0.5, -5.0)
					await get_tree().create_timer(0.02).timeout
			await _seconds_of(_seconds if _view == "ending" else 0.0)
		"crawl", "crawl_third", "crawl_down":
			# Down and crawling: the forward key held, a Swift and a Lifeline box running so the
			# effects strip is in the frame, and the status line saying you may crawl. The third
			# person one is the figure's crawl clip, at the server's crawl pace.
			var ctx := {"opener": local, "at": stand, "box": &"swift"}
			game.boxes.run([{"do": "effect", "name": "move_speed"}], ctx)
			game.boxes.run([{"do": "effect", "name": "crawl_speed"}], {"opener": local, "at": stand, "box": &"lifeline"})
			local.health.invulnerable = false
			var wound := DotDamage.make(0, local.entity_id, 500.0, game.combat.damage_type(&"strike"))
			var _hurt = game.combat.apply_damage(wound)
			local.health.invulnerable = true
			if _view == "crawl_third":
				_client.call("toggle_view")
			Input.action_press(&"dot_fps_forward")
			await _seconds_of(_seconds)
			print("crawled to ", local.feet(), " from ", stand, " speed ", game.crawl_rules.speed)
			Input.action_release(&"dot_fps_forward")
			if _view == "crawl_down":
				# The steepest look-down: the arms' edge, and the backpack, may peek in.
				await _save_extra("_level")
				local.controller.state.pitch = -89.0
				if local.sampler != null:
					local.sampler.look_at_angles(local.controller.state.yaw, -89.0)
				await _seconds_of(0.3)
		"deploy", "deploy_third", "deploy_side":
			_clear_view(game, local, stand)
			# Carrying a box: --seconds is how long primary fire has been held, of a 4 s deploy
			# (0 shows it held, 4.6 shows it deployed). deploy_third is the figure's view of it.
			game.config.box_deploy_seconds = 4.0
			var _c := game.boxes.carry(local, &"mystery")
			if _view == "deploy_third":
				_client.call("toggle_view")
			await _seconds_of(0.5)
			if _seconds > 0.6:
				_client.set("_firing", true)
				await _seconds_of(_seconds - 0.5)
			if _view == "deploy_side":
				# From in front and to one side, where the figure's crate shows.
				var yaw := deg_to_rad(local.controller.state.yaw)
				var ahead := Vector3(-sin(yaw), 0.0, -cos(yaw))
				var right := Vector3(cos(yaw), 0.0, -sin(yaw))
				var at: Vector3 = local.feet()
				_free_camera().look_at_from_position(at + ahead * 2.4 + right * 1.0 + Vector3(0.0, 1.5, 0.0), at + Vector3(0.0, 0.9, 0.0))
		"boxgun":
			# A box that grants a weapon, opened on the local survivor: the gun must be drawn after it.
			_clear_view(game, local, stand)
			# Over a gun already in the same slot, the case a swap of one primary for another is.
			game.boxes.run([{"do": "give_weapon", "id": "rifle"}], {"opener": local, "at": stand, "box": &"upgrade"})
			await _seconds_of(1.0)
			game.boxes.run([{"do": "give_weapon", "id": "smg"}], {"opener": local, "at": stand, "box": &"upgrade"})
			await _seconds_of(maxf(_seconds, 1.0))
		"pickup":
			# A rifle in hand and the same one lying ahead: the prompt and the hold ring part-way round the crosshair.
			_clear_view(game, local, stand)
			game.boxes.run([{"do": "give_weapon", "id": "rifle"}], {"opener": local, "at": stand, "box": &"upgrade"})
			var layer = game.weapon_layer
			layer.rules.pickup_delay = 0.0
			var _spawned: int = layer.drops.spawn({"id": &"rifle", "magazine": 12, "reserve": 60}, local.eye_position() + local.aim_direction() * 1.0, Vector3.ZERO, 0)
			await _seconds_of(maxf(_seconds, 1.0))
			game.get_meta(&"hud").set_hold_progress(0.6)
			await _frames(3)
		"carry":
			# Two primaries in one slot, a backpack on, and the weight bar and slot list on the HUD.
			_clear_view(game, local, stand)
			game.boxes.run([{"do": "give_weapon", "id": "rifle"}], {"opener": local, "at": stand, "box": &"upgrade"})
			game.boxes.run([{"do": "give_weapon", "id": "smg"}], {"opener": local, "at": stand, "box": &"upgrade"})
			var _worn := game.wear_backpack(local, 1)
			await _seconds_of(maxf(_seconds, 1.5))
		"defib", "defib_third", "defib_ground":
			# The defibrillator: in hand (first person, or the figure's view), or lying a step ahead.
			for other in game.survivors():
				if other != local:
					other.place_at(stand + Vector3(0.0, 0.0, 400.0), 0.0)
			if _view == "defib_ground":
				var _id := game.loot.add(ZzLoot.DEFIB, &"defib", stand + Vector3(0.0, 0.1, -1.4))
				await _seconds_of(0.6)
				_face(local, stand + Vector3(0.0, 0.1, -1.4))
				await _seconds_of(0.4)
			else:
				local.defibs = 1
				if _view == "defib_third":
					_client.call("toggle_view")
				await _seconds_of(0.5)
				game.config.defib_charge_seconds = 4.0
				var corpse := game.add_player(&"u900", "Fallen")
				corpse.place_at(stand + Vector3(0.0, 0.0, -1.2), 0.0)
				corpse.incaps = game.config.max_incaps
				corpse.health.invulnerable = false
				var kill := DotDamage.make(0, corpse.entity_id, 9999.0, game.combat.damage_type(&"strike"))
				var _k = game.combat.apply_damage(kill)
				await _seconds_of(0.3)
				game._begin_defib(local, corpse)
				_client.set("_using", true)
				await _seconds_of(maxf(_seconds - 0.8, 0.5))
		"trader":
			# The trader's menu open beside the start trader, the survivor holding some points.
			game.config.trader_when = 2
			game.spawners.start_round(game.map_doc)
			local.points = 420
			await _seconds_of(0.5)
			_client.call("open_shop")
			await _seconds_of(maxf(_seconds - 0.5, 0.3))
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
		"ads":
			await _ads_frames(game, local)
			get_tree().quit(0)
			return
		"crosshair":
			await _crosshair_frames(game, local)
			get_tree().quit(0)
			return
		"stamina":
			await _stamina_frames(local)
			get_tree().quit(0)
			return
		"firemode":
			await _fire_mode_frames(game, local)
			get_tree().quit(0)
			return
		"held":
			await _held_third_frames(game, local)
			get_tree().quit(0)
			return
		"weapons":
			await _weapon_sheets(game, local)
			get_tree().quit(0)
			return
		"ragdoll":
			# A stand-in on their last life killed in front of a free camera, and [member _seconds]
			# of the fall: `--seconds=0.15`, `0.6` and `2` are the start, the drop and the body at
			# rest. `--reaction=face_plant` forces one; the push is away from the camera. `--at` is where.
			var victim = game.survivors()[1] if game.survivors()[0] == local else game.survivors()[0]
			var feet: Vector3 = stand + Vector3(0.0, 0.0, -3.0)
			victim.place_at(feet, 180.0)
			await _seconds_of(0.3)
			feet = victim.feet()
			if _reaction != &"":
				var weights := PackedStringArray()
				for id: StringName in DotPlayerDeathReactions.stock().ids():
					weights.append("%s=%d" % [id, 1 if id == _reaction else 0])
				var _forced: bool = game.ragdoll_rules.set_cvar("sv_ragdoll_reactions", ",".join(weights))
			# Your own eyes (and the gun drawn at them) out of the frame, behind the camera.
			local.place_at(feet + Vector3(0.0, 0.0, 9.0), 0.0)
			var camera := _free_camera()
			camera.look_at_from_position(feet + Vector3(1.9, 1.3, 1.7), feet + Vector3(0.0, 0.4, 0.0))
			victim.health.invulnerable = false
			victim.incaps = game.config.max_incaps
			var slay := DotDamage.make(0, victim.entity_id, 5000.0, game.combat.damage_type(&"strike"))
			slay.tick = game.current_tick()
			slay.direction = (feet - camera.global_position) * Vector3(1, 0, 1)
			var _killed = game.combat.apply_damage(slay)
			print("killed %s at %s: %s" % [victim.display_name, feet.snapped(Vector3.ONE * 0.1),
				victim.death.describe() if victim.death != null else "no fall"])
			await _seconds_of(_seconds)
			var yard: DotPlayerRagdolls = (_client.get("world_view") as Node).get("ragdolls")
			for body: DotPlayerRagdoll in yard.live():
				print("body: %s, centre %s" % [body.describe(), body.centre().snapped(Vector3.ONE * 0.01)])
		"action":
			await _until_uncovered()
			# A stand-in playing an avatar action, from the front, early in the clip.
			var actor = game.survivors()[1] if game.survivors()[0] == local else game.survivors()[0]
			var at_feet: Vector3 = stand + Vector3(0.0, 0.0, -3.0)
			actor.place_at(at_feet, 180.0)
			await _settle(actor)
			at_feet = actor.feet()
			local.place_at(at_feet + Vector3(0.0, 0.0, 9.0), 0.0)
			var parts := _action.split(":")
			var entry: Dictionary = DotAvatarActions.defaults().find(StringName(parts[0]), parts[1])
			var ok: bool = actor.figure.body_node().play_action(StringName(parts[1]), bool(entry.get("loop", false)), 0.0)
			print("action %s: played=%s" % [_action, ok])
			_free_camera().look_at_from_position(at_feet + Vector3(0.0, 1.5, 3.0), at_feet + Vector3(0.0, 1.0, 0.0))
			# Early and late frames of the clip: <out>_a.png now, the usual frame at the end.
			await _pin_for(actor, 0.4)
			await _save_extra("_a")
			await _pin_for(actor, maxf(_seconds - 0.4, 0.1))
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
