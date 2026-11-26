extends "shot_base.gd"

## The shot tool's scripted views: one function per --view that needs more than a camera, split from shot.gd.

const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzPossession := preload("../game/zz_possession.gd")


func _view_overview(game: ZzGame, local, stand: Vector3) -> void:
	await _frames(6)
	var box: AABB = game.map.bounds()
	var centre := box.get_center()
	var reach := maxf(box.size.length() * 0.42, 14.0)
	_free_camera().look_at_from_position(centre + Vector3(reach * 0.45, reach * 0.6, reach * 0.55), centre)


func _view_room(game: ZzGame, local, stand: Vector3) -> void:
	await _seconds_of(_seconds)
	if _aim != INF:
		# --at is where everybody stands: look along the stand-ins' row from the side.
		_free_camera().look_at_from_position(stand + Vector3(4.5, 0.4, 1.8), stand + Vector3(0.0, 1.0, 1.8))
	else:
		_free_camera().look_at_from_position(_at, _look)


func _view_fire(game: ZzGame, local, stand: Vector3) -> void:
	# A Molotov pool lit a few metres ahead, from a low three-quarter camera.
	_clear_view(game, local, stand)
	var pool := stand + Vector3(0.0, 0.0, -5.0)
	var _burning := game.hazards.add(&"fire", game.ray_hit(pool + Vector3.UP, pool + Vector3.DOWN * 4.0), 1.6, 20.0, 6.0, 0)
	_free_camera().look_at_from_position(pool + Vector3(2.6, 1.4, 2.6), pool + Vector3(0.0, 0.7, 0.0))
	await _seconds_of(_seconds)


func _view_down(game: ZzGame, local, stand: Vector3) -> void:
	local.health.invulnerable = false
	var hit := GSDamage.make(0, local.entity_id, 500.0, game.combat.damage_type(&"strike"))
	var _applied = game.combat.apply_damage(hit)
	local.health.invulnerable = true
	await _seconds_of(_seconds)


func _view_killcam(game: ZzGame, local, stand: Vector3) -> void:
	# The last survivor falls and the map is lost; --seconds is how long after, so ~3 is the
	# replay and ~9 the podium.
	await _seconds_of(4.0)
	for who in game.survivors():
		who.health.invulnerable = false
		var blow := GSDamage.make(0, who.entity_id, 9999.0, game.combat.damage_type(&"strike"))
		var _felled = game.combat.apply_damage(blow)
	game._decide(false, "the horde took the last survivor")
	await _seconds_of(_seconds)


func _view_boxgun(game: ZzGame, local, stand: Vector3) -> void:
	# A box that grants a weapon, opened on the local survivor: the gun must be drawn after it.
	_clear_view(game, local, stand)
	# Over a gun already in the same slot, the case a swap of one primary for another is.
	game.boxes.run([{"do": "give_weapon", "id": "rifle"}], {"opener": local, "at": stand, "box": &"upgrade"})
	await _seconds_of(1.0)
	game.boxes.run([{"do": "give_weapon", "id": "smg"}], {"opener": local, "at": stand, "box": &"upgrade"})
	await _seconds_of(maxf(_seconds, 1.0))


func _view_pickup(game: ZzGame, local, stand: Vector3) -> void:
	# A rifle in hand and the same one lying ahead: the prompt and the hold ring part-way round the crosshair.
	_clear_view(game, local, stand)
	game.boxes.run([{"do": "give_weapon", "id": "rifle"}], {"opener": local, "at": stand, "box": &"upgrade"})
	var layer = game.weapon_layer
	layer.rules.pickup_delay = 0.0
	var _spawned: int = layer.drops.spawn({"id": &"rifle", "magazine": 12, "reserve": 60}, local.eye_position() + local.aim_direction() * 1.0, Vector3.ZERO, 0)
	await _seconds_of(maxf(_seconds, 1.0))
	game.get_meta(&"hud").set_hold_progress(0.6)
	await _frames(3)


func _view_carry(game: ZzGame, local, stand: Vector3) -> void:
	# Two primaries in one slot, a backpack on, and the weight bar and slot list on the HUD.
	_clear_view(game, local, stand)
	game.boxes.run([{"do": "give_weapon", "id": "rifle"}], {"opener": local, "at": stand, "box": &"upgrade"})
	game.boxes.run([{"do": "give_weapon", "id": "smg"}], {"opener": local, "at": stand, "box": &"upgrade"})
	var _worn := game.wear_backpack(local, 1)
	await _seconds_of(maxf(_seconds, 1.5))


func _view_trader(game: ZzGame, local, stand: Vector3) -> void:
	# The trader's menu open beside the start trader, the survivor holding some points.
	game.config.trader_when = 2
	game.spawners.start_round(game.map_doc)
	local.points = 420
	await _seconds_of(0.5)
	_client.call("open_shop")
	await _seconds_of(maxf(_seconds - 0.5, 0.3))


func _view_crates(game: ZzGame, local, stand: Vector3) -> void:
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


func _view_walk(game: ZzGame, local, stand: Vector3) -> void:
	# A filmstrip of --zombie=<kind> walking at the survivor: a frame every 0.15 s for --seconds,
	# a camera tracking it from the side (walk_00.. beside --out).
	_clear_view(game, local, stand)
	var walker: GSNpcInstance = game.horde.spawner.spawn(_zombie, game.horde.snap_to_nav(stand + Vector3(2.0, 0.0, -9.0)), &"shot", Basis(Vector3.UP, PI))
	if walker != null and walker.brain != null:
		walker.brain.call(&"force_target", local.player_id)
	var walk_cam := _free_camera()
	walk_cam.track_offset = Vector3(4.0, 1.2, 0.0)
	walk_cam.track = func() -> Variant: return walker.position() + Vector3(0.0, 0.9, 0.0) if walker != null and walker.node != null else null
	for n in int(_seconds / 0.15):
		await _save_extra("_%02d" % n)
		await _seconds_of(0.15)


func _view_strike(game: ZzGame, local, stand: Vector3) -> void:
	# One zombie (--zombie=common|crawler|...) a step from the survivor, swinging at them
	# standing or, for strike_down, downed; a free camera from the side.
	if _view == "strike_down":
		local.health.invulnerable = false
		var floored := GSDamage.make(0, local.entity_id, 500.0, game.combat.damage_type(&"strike"))
		var _felled = game.combat.apply_damage(floored)
		local.health.invulnerable = true
	var foe: GSNpcInstance = game.horde.spawner.spawn(_zombie, game.horde.snap_to_nav(stand + Vector3(0.0, 0.0, -1.2)), &"shot", Basis(Vector3.UP, PI))
	if foe != null and foe.brain != null:
		foe.brain.call(&"force_target", local.player_id)
	if _view == "pin" and foe != null:
		var how: StringName = {&"rider": &"ride", &"crawler": &"grab", &"ram": &"carry"}.get(_zombie, &"pounce")
		print("pin: ", how, " held ", game.horde.pin(foe, local.player_id, how))
	_orbit.holder = foe
	_orbit.victim = local if _view == "pin" else null
	await _seconds_of(_seconds)
	var mid: Vector3 = local.feet().lerp(foe.position(), 0.5) if foe != null else local.feet()
	print("strike: survivor ", local.feet(), " zombie ", foe.position() if foe != null else "none", " anim ", foe.node.get(&"anim") if foe != null else "")
	var side := -1.0 if _view == "pin" else 1.0
	_free_camera().look_at_from_position(mid + Vector3(3.2 * side, 1.8, 1.2), mid + Vector3(0.0, 0.8 if _view == "pin" else 0.6, 0.0))
	await _seconds_of(0.2)


func _drive_for(game: ZzGame, seconds: float) -> void:
	# The shot's world is not in its play phase, so the held body's drive is fed here, a tick a frame.
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		game.possession.tick(1.0 / 64.0)
		game.horde.tick(1.0 / 64.0)


func _view_possess(game: ZzGame, local, stand: Vector3) -> void:
	# A turned survivor driving --zombie=<kind> (rider, brute, spitter, leaper, ram): the client's follow camera
	# (behind, looking where the holder's yaw and pitch say) at rest, turned, looking up and down, then the shove
	# key pressed, a frame after each (_a_rest .. _g_ability2). The rider leaps at the survivor in front.
	_clear_view(game, local, stand)
	var holder = null
	for other in game.survivors():
		if other != local:
			holder = other
			break
	if game.possession == null:
		game.possession = load("res://game/zz_possession.gd").new(game)
	var cmd := GSFpsCommand.new()
	cmd.yaw = 180.0
	holder.input_move = cmd
	# The horde stands still while the map's nav bakes (a big map takes seconds): wait it out (up to 60 s)
	# before snapping the spawn to it, or a ship's zombie lands in the sea.
	var waited := 0
	while bool(game.horde.get(&"_map_nav_pending")) and waited < 3600:
		await get_tree().process_frame
		game.horde.tick(1.0 / 64.0)
		waited += 1
	# 7 m ahead, else to a side or behind, where the graph is: a ship's bow has only sea 7 m ahead.
	var at: Vector3 = stand
	var data: GSNpcNavData = game.horde.nav
	for ahead: Vector3 in [Vector3(0.0, 0.0, -7.0), Vector3(-7.0, 0.0, 0.0), Vector3(7.0, 0.0, 0.0), Vector3(0.0, 0.0, 7.0)]:
		if data != null and data.is_navigable(stand + ahead, 3.0):
			at = stand + ahead
			break
	at = game.horde.snap_to_nav(at)
	var npc: GSNpcInstance = game.horde.spawner.spawn(_zombie, at, &"shot", Basis(Vector3.UP, PI))
	print("possess: ", _zombie, " held ", game.possession.possess(holder, npc) if npc != null else false)
	var cam := _free_camera()
	var look_pitch := [0.0]
	cam.track = func() -> Variant:
		if npc == null or npc.node == null:
			return null
		var basis := Basis.from_euler(Vector3(deg_to_rad(look_pitch[0]), deg_to_rad(cmd.yaw), 0.0))
		var focus := npc.position() + Vector3(0.0, 2.1, 0.0)
		var spot := ZzPossession.camera_spot(cam.get_world_3d().direct_space_state, game.world_mask(), focus,
				focus + basis.z * 3.6, [local.get_rid()])
		cam.track_offset = spot - focus
		return focus
	await _drive_for(game, 0.6)
	await _save_extra("_a_rest")
	cmd.yaw = 270.0
	await _drive_for(game, 0.8)
	await _save_extra("_b_turned")
	cmd.yaw = 180.0
	for step in [["_c_up", 40.0], ["_d_down", -45.0]]:
		cmd.pitch = step[1]
		look_pitch[0] = step[1]
		await _drive_for(game, 0.4)
		await _save_extra(step[0])
	cmd.pitch = 0.0
	look_pitch[0] = 0.0
	cmd.set_button(ZzNetCommand.BUTTON_SHOVE, true)
	await _drive_for(game, 0.15)
	cmd.set_button(ZzNetCommand.BUTTON_SHOVE, false)
	for suffix in ["_e_ability0", "_f_ability1", "_g_ability2"]:
		await _drive_for(game, 0.35)
		print("possess ", suffix, ": ", npc.position() if npc != null else "gone", " anim ", npc.node.get(&"anim") if npc != null and npc.node != null else "")
		await _save_extra(suffix)


func _view_ending(game: ZzGame, local, stand: Vector3) -> void:
	# A map's ending camera 7 m ahead and up, mid-glide (--seconds in); `trail` instead follows a node
	# the resolver looked up by name round a circle in front of the eyes, so the ribbon is in the frame.
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
		var trail := GSMapTrail.new()
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


func _view_crawl(game: ZzGame, local, stand: Vector3) -> void:
	# Down and crawling: the forward key held, a Swift and a Lifeline box running so the
	# effects strip is in the frame, and the status line saying you may crawl. The third
	# person one is the figure's crawl clip, at the server's crawl pace.
	var ctx := {"opener": local, "at": stand, "box": &"swift"}
	game.boxes.run([{"do": "effect", "name": "move_speed"}], ctx)
	game.boxes.run([{"do": "effect", "name": "crawl_speed"}], {"opener": local, "at": stand, "box": &"lifeline"})
	if _view == "crawl_seq":
		await _crawl_sequence(game, local)
		return
	local.health.invulnerable = false
	var wound := GSDamage.make(0, local.entity_id, 500.0, game.combat.damage_type(&"strike"))
	var _hurt = game.combat.apply_damage(wound)
	local.health.invulnerable = true
	if _view == "crawl_third":
		_client.call("toggle_view")
	Input.action_press(&"gs_fps_forward")
	await _seconds_of(_seconds)
	print("crawled to ", local.feet(), " from ", stand, " speed ", game.crawl_rules.speed)
	Input.action_release(&"gs_fps_forward")
	if _view == "crawl_down":
		# The steepest look-down: the arms' edge, and the backpack, may peek in.
		await _save_extra("_level")
		local.controller.state.pitch = -89.0
		if local.sampler != null:
			local.sampler.look_at_angles(local.controller.state.yaw, -89.0)
		await _seconds_of(0.3)


## `--view=crawl_seq`: the first-person frames across the whole crawl, saved as `<out>_NN.png` every `--seconds`/10 of a second:
## standing, going down, down and still (propped), crawling, still again. `--weapons=` is not read; the survivor holds what the
## map gave them. A frame sequence shows the transitions a single shot cannot (a pop, a double pair of hands, a body at the lens).
func _crawl_sequence(game: ZzGame, local) -> void:
	var step := maxf(_seconds, 1.0) / 10.0
	var n := 0
	await _seconds_of(0.5)
	for _i in range(2):
		await _save_extra("_%02d" % n)
		n += 1
		await _seconds_of(step)
	local.health.invulnerable = false
	var wound := GSDamage.make(0, local.entity_id, 500.0, game.combat.damage_type(&"strike"))
	var _hurt = game.combat.apply_damage(wound)
	local.health.invulnerable = true
	for _i in range(5):
		await _save_extra("_%02d" % n)
		n += 1
		await _seconds_of(step * 0.5)
	Input.action_press(&"gs_fps_forward")
	for _i in range(6):
		await _save_extra("_%02d" % n)
		n += 1
		await _seconds_of(step * 0.5)
	Input.action_release(&"gs_fps_forward")
	for _i in range(5):
		await _save_extra("_%02d" % n)
		n += 1
		await _seconds_of(step * 0.5)


func _view_deploy(game: ZzGame, local, stand: Vector3) -> void:
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


func _view_defib(game: ZzGame, local, stand: Vector3) -> void:
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
		var kill := GSDamage.make(0, corpse.entity_id, 9999.0, game.combat.damage_type(&"strike"))
		var _k = game.combat.apply_damage(kill)
		await _seconds_of(0.3)
		game._begin_defib(local, corpse)
		_client.set("_using", true)
		await _seconds_of(maxf(_seconds - 0.8, 0.5))


func _view_hit(game: ZzGame, local, stand: Vector3) -> void:
	# Two hits the server confirms on the zombie nearest the crosshair, the second a head kill, through
	# gs-combat as a shot would go: the marker and numbers the client draws. Hurt on borrowed health and
	# holding an objective, so the vitals' bonus and the hold-out clock are in the frame too.
	await _seconds_of(maxf(_seconds - 0.5, 0.5))
	# The one nearest the line of sight (straight ahead is -Z), so the number is on screen.
	var nearest: GSNpcInstance = null
	var off := INF
	for npc: GSNpcInstance in game.horde.spawner.all_npcs():
		var to := npc.position() - stand
		if npc.is_alive() and to.z < -1.0 and absf(to.x / to.z) < off:
			off = absf(to.x / to.z)
			nearest = npc
	if nearest != null:
		var victim: int = game.horde.entity_id_for(nearest)
		var first := GSDamage.make(local.entity_id, victim, 18.0, null)
		first.point = nearest.position() + Vector3(0.0, 1.2, 0.0)
		var _a = game.combat.apply_damage(first)
		var second := GSDamage.make(local.entity_id, victim, 400.0, null)
		second.point = nearest.position() + Vector3(0.0, 1.6, 0.0)
		second.hit_group = GSHitGroup.HEAD
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


func _view_ragdoll(game: ZzGame, local, stand: Vector3) -> void:
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
		for id: StringName in GSPlayerDeathReactions.stock().ids():
			weights.append("%s=%d" % [id, 1 if id == _reaction else 0])
		var _forced: bool = game.ragdoll_rules.set_cvar("sv_ragdoll_reactions", ",".join(weights))
	# Your own eyes (and the gun drawn at them) out of the frame, behind the camera.
	local.place_at(feet + Vector3(0.0, 0.0, 9.0), 0.0)
	var camera := _free_camera()
	camera.look_at_from_position(feet + Vector3(1.9, 1.3, 1.7), feet + Vector3(0.0, 0.4, 0.0))
	victim.health.invulnerable = false
	victim.incaps = game.config.max_incaps
	var slay := GSDamage.make(0, victim.entity_id, 5000.0, game.combat.damage_type(&"strike"))
	slay.tick = game.current_tick()
	slay.direction = (feet - camera.global_position) * Vector3(1, 0, 1)
	var _killed = game.combat.apply_damage(slay)
	print("killed %s at %s: %s" % [victim.display_name, feet.snapped(Vector3.ONE * 0.1),
		victim.death.describe() if victim.death != null else "no fall"])
	await _seconds_of(_seconds)
	var yard: GSPlayerRagdolls = (_client.get("world_view") as Node).get("ragdolls")
	for body: GSPlayerRagdoll in yard.live():
		print("body: %s, centre %s" % [body.describe(), body.centre().snapped(Vector3.ONE * 0.01)])


func _view_defib_other(game: ZzGame, local, stand: Vector3) -> void:
	await _until_uncovered()
	# A stand-in charging a defibrillator as a team-mate sees it: from the front (the frame),
	# from behind (_b) and from the side (_c).
	var holder = game.survivors()[1] if game.survivors()[0] == local else game.survivors()[0]
	var spot: Vector3 = stand + Vector3(0.0, 0.0, -3.0)
	holder.place_at(spot, 180.0)
	await _settle(holder)
	spot = holder.feet()
	local.place_at(spot + Vector3(0.0, 0.0, 9.0), 0.0)
	var cam := _free_camera()
	cam.look_at_from_position(spot + Vector3(0.0, 1.5, 2.2), spot + Vector3(0.0, 1.0, 0.0))
	# The holder turned away (_b), side on (_c) and facing the camera, each held a moment: the
	# server's tick clears `using`, so it is set again each frame after the physics step.
	for view: Array in [["_b", 0.0], ["_c", 90.0], ["", 180.0]]:
		holder.place_at(spot, view[1])
		for _i in 20:
			await get_tree().process_frame
			holder.using = &"defib"
		if view[0] == "":
			await _seconds_of(0.1)
		else:
			await _save_extra(view[0])


func _view_action(game: ZzGame, local, stand: Vector3) -> void:
	await _until_uncovered()
	# A stand-in playing an avatar action, from the front, early in the clip.
	var actor = game.survivors()[1] if game.survivors()[0] == local else game.survivors()[0]
	var at_feet: Vector3 = stand + Vector3(0.0, 0.0, -3.0)
	actor.place_at(at_feet, 180.0)
	await _settle(actor)
	at_feet = actor.feet()
	local.place_at(at_feet + Vector3(0.0, 0.0, 9.0), 0.0)
	var parts := _action.split(":")
	var entry: Dictionary = GSAvatarActions.defaults().find(StringName(parts[0]), parts[1])
	var ok: bool = actor.figure.body_node().play_action(StringName(parts[1]), bool(entry.get("loop", false)), 0.0)
	print("action %s: played=%s" % [_action, ok])
	_free_camera().look_at_from_position(at_feet + Vector3(0.0, 1.5, 3.0), at_feet + Vector3(0.0, 1.0, 0.0))
	# Early and late frames of the clip: <out>_a.png now, the usual frame at the end.
	await _pin_for(actor, 0.4)
	await _save_extra("_a")
	await _pin_for(actor, maxf(_seconds - 0.4, 0.1))


func _view_pinned(game: ZzGame, local, stand: Vector3) -> void:
	var kind := _pin if _pin != &"" else &"pounce"
	var special: StringName = {&"pounce": ZzNpcs.LEAPER, &"choke": ZzNpcs.STRANGLER, &"carry": ZzNpcs.RAM,
		&"ride": ZzNpcs.RIDER, &"grab": ZzNpcs.CRAWLER}.get(kind, ZzNpcs.LEAPER)
	# --pin-me: the special takes you, which is what the lens drawing is for.
	var friend = local if _pin_me else (game.survivors()[1] if game.survivors()[0] == local else game.survivors()[0])
	if not _pin_me:
		friend.place_at(stand + Vector3(0.0, 0.0, -4.0), 180.0)
	var npc := game.horde.spawner.spawn(special, game.horde.snap_to_nav(stand + (Vector3(3.5, 0.0, -14.0) if kind == &"choke" else Vector3(0.0, 0.0, -5.0))), &"shot", Basis(Vector3.UP, PI))
	await _seconds_of(0.3)
	var _held := game.pins.pin(game.horde.entity_id_for(npc), npc, friend.player_id, kind)
	_orbit.holder = npc
	_orbit.victim = friend
	await _seconds_of(_seconds)


func _view_mutant(game: ZzGame, local: Node, stand: Vector3) -> void:
	# A mutant 9 m off, angry and flying: taking flight at once, then
	# frames as it cruises, charges and dives (_a, _b, _c, each --seconds apart).
	_clear_view(game, local, stand)
	var mut: GSNpcInstance = game.horde.spawn_special(&"mutant", game.horde.snap_to_nav(stand + Vector3(-9.0, 0.0, -5.0)))
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
