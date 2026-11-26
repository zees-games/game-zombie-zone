extends "headless_run_client.gd"

## The HUD and first-play sections of [headless_run.gd], split off to keep each file under the size gate.


const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzHud := preload("../game/zz_hud.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")


## The HUD draws health, the clock, the kits and confirmed hits through gs-ui's glance pieces.
## A headless viewport is 64 x 64, so the layout is checked as arithmetic (`tools/shot.sh --view=hit`).
func _test_the_hud() -> void:
	_section("the HUD: gs-ui's vitals, clock, kits, and hits the server confirmed")
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
		"GSVitals: real health as the number, borrowed health as its bonus", str(hud.vitals.describe())
	)
	var with_kit: int = hud.loadout.slot_count()
	me.medkits = 0
	hud._process(0.0)
	_check(hud.kits.rows.is_empty() and with_kit == hud.loadout.slot_count() + 1,
		"the medkit is a slot in the loadout row, not a key hint (the hints keep the defibrillator)",
		"kits=%s slots %d -> %d" % [hud.kits.rows, with_kit, hud.loadout.slot_count()])
	me.medkits = 1
	hud._process(0.0)

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
		_check(hud.strip.clock == GSScoreStrip.clock_text(42.2) and hud.strip.under_text().ends_with("hold out"),
			"a hold-out's time left is GSScoreStrip's clock", str(hud.strip.describe()))

	# A survivor's hit, as gs-combat applies it, is confirmed by the world, and the HUD draws
	# the marker and the number from that confirmation.
	var confirmed: Array = []
	game.hit_landed.connect(func(id: StringName, victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
		confirmed.append([id, victim, amount, killed])
		hud.confirm_hit(victim, amount, point, killed, headshot))
	# On the street: nothing spawns in a safe room, which is where the team starts.
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -6), &"test")
	await _sim(game, 0.1)
	var shot := GSDamage.make(me.entity_id, game.horde.entity_id_for(npc), 7.0, null)
	shot.tick = game.current_tick()
	var _applied := game.combat.apply_damage(shot)
	_check(confirmed.size() == 1 and confirmed[0][0] == me.player_id and absf(float(confirmed[0][2]) - 7.0) < 0.01
		and not bool(confirmed[0][3]), "a survivor's hit on a zombie is confirmed, by whom and how much", str(confirmed))
	_check(hud.hit_marker.alpha() > 0.0 and hud.damage_numbers.texts().size() == 1,
		"and the HUD flashes GSHitMarker and puts up a GSDamageNumbers number", str(hud.damage_numbers.texts()))
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
	var chat := GSGameChatClient.new()
	add_child(chat)
	var w: GSChatWindow = chat.window
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
	# Down the sights the dot fades with the aim (gs-ui's curve), and a scope hides it.
	hud.set_aim(0.0, false)
	var hip := _crosshair_alpha(hud)
	hud.set_aim(1.0, false)
	var aimed := _crosshair_alpha(hud)
	hud.set_aim(1.0, true)
	_check(is_equal_approx(hip, 1.0) and (aimed < 0.01 or GSAddonApi.build_level("gs_ui") < 5)
		and _crosshair_alpha(hud) == 0.0 and is_equal_approx(hud.scope.fraction, 1.0),
		"the crosshair is whole at the hip, gone down the sights, and a scope replaces it",
		"hip %.2f aimed %.2f scope %.2f" % [hip, aimed, hud.scope.fraction])
	var scope_prefs := load("res://addons/gs_weapon/view/gs_weapon_scope_prefs.gd")
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
	var hides := GSAddonApi.build_level("gs_ui") >= 14
	if hides:
		cross.call(&"_process", 0.016)
	_check(not hides or bool(cross.call(&"is_shown")), "the crosshair is drawn while the survivor lives")
	me.health.alive = false
	if hides:
		cross.call(&"_process", 0.016)
	_check(not hides or not bool(cross.call(&"is_shown")), "and gone once they are dead (alive_source)")
	me.health.alive = true


## What the crosshair shows: GSCrosshair fades itself (and hides when scoped), the old dot by modulate.
func _crosshair_alpha(hud: ZzHud) -> float:
	var c: Control = hud._crosshair
	if c.has_method(&"set_aim"):
		c.call(&"follow_aim", 10.0)
		return 0.0 if bool(c.get(&"suppressed")) else float(c.get(&"aim_opacity"))
	return c.modulate.a


## The first play test's findings: missing-glyph boxes, "You is down", the black fence lock,
## the black void over the street, ten silent seconds after a wipe, and the HUD theme.
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
	var _built: GSResult = settings.setup(GSSettingsStoreMemory.new())
	hud.follow_menu(settings.menu)
	var plate := hud.vitals.colour(&"plate")
	_check(plate.get_luminance() < 0.1 and plate.a >= 0.7, "the HUD is dark by default, in the menu's theme", str(plate))
	var _t := settings.settings.set_value(&"ui_theme", &"contrast")
	var contrast: GSMenuPalette = settings.menu.palette()
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
