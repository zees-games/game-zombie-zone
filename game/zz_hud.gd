extends "zz_hud_aim.gd"

## The full-rect Control every piece sits on.
func screen() -> Control:
	# Built on demand: the touch buttons ask before a survivor is seated (bind builds it otherwise).
	if _root == null:
		_build()
	return _root

const LOADOUT_WIDTH := 8.0 * (GSLoadoutBar.SLOT_W + GSLoadoutBar.GAP)

## The loadout row's top edge off the bottom; the counter and fire modes stand on it.
const LOADOUT_TOP := 24.0 + GSLoadoutBar.SLOT_H + GSLoadoutBar.WEIGHT_H + 8.0
## Where the bottom-right HUD (loadout, ammo, fire mode) ends; gs-core's loading panel sits above it.
const CORNER_TOP := LOADOUT_TOP + 106.0 + 12.0

const ZzShopIcons := preload("zz_shop_icons.gd")

var _icons: ZzShopIcons = null

## Moves the loadout row (slots and weight bar) [param px] left of the right edge, clear of the touch
## buttons: FIRE and its cluster sit over it on a phone.
func shift_weight_left(px: float) -> void:
	screen()
	for c: Control in [loadout, ammo, fire_mode]:
		c.offset_left -= px
		c.offset_right -= px

## Lifts the health plate, its stamina bar and the kits stacked over it [param px] HUD units, clear of the
## touch thumbstick that sits over the bottom-left corner on a phone.
func lift_plate(px: float) -> void:
	screen()
	_plate_lift = px
	for c: Control in [vitals, stamina_bar]:
		c.offset_top -= px
		c.offset_bottom -= px

var _plate_lift := 0.0

func bind(p_game: ZzGame, p_player: ZzPlayer) -> void:
	game = p_game
	player = p_player

	if _root == null:
		_build()

func _build() -> void:
	# A full-rect Control between the CanvasLayer and the labels: a CanvasLayer does not lay its
	# children out, so anchors on a Label parented straight to one resolve against nothing.
	_root = Control.new()
	_root.name = "Screen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_low = _cover("Low", Color(0.55, 0.0, 0.0, 0.0))
	# Eyes under water: a cold green-blue over everything, under the HUD (the fog does the depth).
	_wet = _cover("Wet", Color(0.04, 0.30, 0.40))
	_bile = _cover("Bile", Color(0.38, 0.52, 0.08))
	_fire = _cover("Fire", Color(0.95, 0.4, 0.05))
	_goo = GSFxScreenGoo.new()
	_goo.name = "Goo"
	_goo.layer = layer - 1
	_goo.status_fade_in = 1.0
	add_child(_goo)
	_grey = _cover("LastLife", Color(0.12, 0.12, 0.12))
	_blind = _cover("Blind", Color(0.97, 0.97, 0.94))
	_flash = _cover("Flash", Color(1.0, 1.0, 1.0))

	# Under every HUD piece: the scope is the view, the HUD still reads over it.
	scope = ZeeScopeOverlay.new()
	scope.name = "Scope"
	_root.add_child(scope)

	# The glance pieces read their colours from the theme on the type GSHudPiece; set on
	# the root, every piece under it inherits them. See [method piece_theme].
	_root.theme = piece_theme()
	_follow()

	_top = _label(24)
	_top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top.offset_top = 14.0
	_top.offset_bottom = 46.0
	_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_top_sub = _label(16)
	_top_sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_top_sub.offset_top = 46.0
	_top_sub.offset_bottom = 70.0
	_top_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_sub.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))

	# Under the title, where the objective line is when there is no clock: a hold-out's time
	# left, or how long a survival map has been held, with what it is under it.
	strip = GSScoreStrip.new()
	strip.name = "Clock"
	strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	strip.offset_top = 50.0
	strip.offset_bottom = 130.0
	_root.add_child(strip)

	_shout = _label(36)
	_shout.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_shout.offset_top = 150.0
	_shout.offset_bottom = 210.0
	_shout.offset_left = -640.0
	_shout.offset_right = 640.0
	_shout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shout.add_theme_color_override("font_color", Color(0.98, 0.42, 0.34))

	_banner = _label(30)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 210.0
	_banner.offset_bottom = 254.0
	_banner.offset_left = -640.0
	_banner.offset_right = 640.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_banner_line = _label(18)
	_banner_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner_line.offset_top = 254.0
	_banner_line.offset_bottom = 282.0
	_banner_line.offset_left = -640.0
	_banner_line.offset_right = 640.0
	_banner_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Bottom left, above the chat box: the health plate, the kits over it, the downs over them.
	vitals = GSVitals.new()
	vitals.name = "Vitals"
	vitals.slim = true
	vitals.slim_height = 10.0
	vitals.slim_armour_height = 4.0
	vitals.armour_height = 5.0
	vitals.ease_sec = 0.28
	vitals.fill_colour = HEALTH_COLOUR
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.offset_left = 24.0
	vitals.offset_right = 24.0 + 420.0
	vitals.offset_top = -PLATE_BOTTOM - 56.0
	vitals.offset_bottom = -PLATE_BOTTOM
	_root.add_child(vitals)

	# Stamina, a thin bar right over the health plate; only drawn once it is below full.
	stamina_bar = GSStatBar.new()
	stamina_bar.name = "Stamina"
	stamina_bar.max_value = 100.0
	stamina_bar.show_text = false
	stamina_bar.bar_height = 6.0
	stamina_bar.fill_colour = Color(0.95, 0.8, 0.3)
	stamina_bar.low_colour = Color(0.9, 0.35, 0.25)
	stamina_bar.low_fraction = 0.15
	stamina_bar.ease_sec = 0.1
	stamina_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stamina_bar.offset_left = 24.0
	stamina_bar.offset_right = 24.0 + 300.0
	stamina_bar.offset_top = -PLATE_BOTTOM - 64.0
	stamina_bar.offset_bottom = -PLATE_BOTTOM - 58.0
	stamina_bar.visible = false
	var _bound := stamina_bar.bind(func() -> Variant: return _stamina_pct)
	_root.add_child(stamina_bar)

	kits = GSKeyHints.new()
	kits.name = "Kits"
	kits.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	kits.offset_left = 24.0
	kits.offset_right = 24.0 + 300.0
	_root.add_child(kits)

	downs = ZzDownsPips.new()
	downs.name = "Downs"
	downs.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	downs.offset_left = 24.0
	downs.offset_right = 24.0 + 200.0
	_root.add_child(downs)

	_status = GSStatusLines.new()
	_status.name = "Status"
	_status.font_size = 16
	_status.max_lines = 1
	_root.add_child(_status)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.offset_left = 24.0
	_status.offset_right = 600.0

	# The team, top left; rows are made as survivors appear (see [method _team_row]).
	_team = Control.new()
	_team.name = "Team"
	_team.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_team.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_team.offset_left = 22.0
	_team.offset_top = 18.0
	_team.offset_right = 380.0
	_team.offset_bottom = 18.0 + TEAM_ROW * float(TEAM_ROWS)
	_root.add_child(_team)

	# Weapon and ammunition, bottom right: the counter right-aligns to its own right edge.
	ammo = GSAmmoCounter.new()
	ammo.name = "Ammo"
	ammo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo.offset_left = -420.0
	ammo.offset_right = -24.0
	ammo.offset_top = -LOADOUT_TOP - 76.0
	ammo.offset_bottom = -LOADOUT_TOP
	_root.add_child(ammo)

	# The loadout row and the weight bar over it: bottom right, one picture per slot.
	loadout = GSLoadoutBar.new()
	loadout.name = "Loadout"
	loadout.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	loadout.offset_left = -24.0 - LOADOUT_WIDTH
	loadout.offset_right = -24.0
	loadout.offset_top = -24.0 - GSLoadoutBar.SLOT_H - GSLoadoutBar.WEIGHT_H
	loadout.offset_bottom = -24.0
	_root.add_child(loadout)
	_icons = ZzShopIcons.new()
	add_child(_icons)

	fire_mode = GSFireModeIndicator.new()
	fire_mode.name = "FireMode"
	fire_mode.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_mode.offset_left = -420.0
	fire_mode.offset_right = -24.0
	fire_mode.offset_top = -LOADOUT_TOP - 106.0
	fire_mode.offset_bottom = -LOADOUT_TOP - 80.0
	_root.add_child(fire_mode)

	# While the map's graph is built: top centre, clear of the loadout.
	_nav_meter = ZzNavMeter.new()
	_root.add_child(_nav_meter)

	# What the boxes are doing, right side.
	_effects = GSStatusLines.new()
	_effects.name = "Effects"
	_effects.align_right = true
	_effects.font_size = 15
	_root.add_child(_effects)
	_effects.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_effects.offset_left = -420.0
	_effects.offset_right = -22.0
	_effects.offset_top = 90.0
	_effects.offset_bottom = 360.0

	# The centre: crosshair, prompt, the bar of what you hold E for.
	_crosshair = _make_crosshair()
	_crosshair.name = "Crosshair"
	_root.add_child(_crosshair)

	_use_back = _rect(Color(0.0, 0.0, 0.0, 0.55), Control.PRESET_CENTER, -160.0, 74.0, 320.0, 12.0)
	_use_fill = _rect(Color(0.95, 0.85, 0.35), Control.PRESET_CENTER, -160.0, 74.0, 0.0, 12.0)
	# The breath, above the use bar's place; shown only while it is not full.
	_air_back = _rect(Color(0.0, 0.0, 0.0, 0.55), Control.PRESET_CENTER, -100.0, 96.0, 200.0, 8.0)
	_air_fill = _rect(Color(0.55, 0.85, 1.0), Control.PRESET_CENTER, -100.0, 96.0, 200.0, 8.0)
	_air_back.visible = false
	_air_fill.visible = false
	_held = _label(28)
	_held.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_held.offset_left = -500.0
	_held.offset_right = 500.0
	_held.offset_top = -120.0
	_held.offset_bottom = -80.0
	_held.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))

	# Full rect, centred on the crosshair; both draw only what the server confirmed.
	hit_fx = GSHitFeedback.mount(_root)
	hit_marker = hit_fx.marker
	damage_numbers = hit_fx.numbers

	watching_label = _label(20)
	watching_label.name = "Watching"
	watching_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	watching_label.offset_left = -520.0
	watching_label.offset_right = 520.0
	watching_label.offset_top = -140.0
	watching_label.offset_bottom = -104.0
	watching_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	watching_label.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0))

	for i in 4:
		var mark := ColorRect.new()
		mark.color = Color(0.9, 0.1, 0.05, 0.0)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_root.add_child(mark)
		_hurt_marks.append({"rect": mark, "left": 0.0})
	_attach_elements()

## What the boxes are doing to the game: `[{title, stacks, seconds, who, scale}]`.
func set_effects(rows: Array) -> void:
	_effect_rows = rows
	_effects_at = Time.get_ticks_msec() / 1000.0
	_effects_sig = 0

func _key(action: StringName) -> String:
	return String(key_fn.call(action)) if key_fn.is_valid() else String(action)

func _process(delta: float) -> void:
	if _root == null or game == null or player == null or not is_instance_valid(player):
		return

	_shout_for = maxf(_shout_for - delta, 0.0)
	_shout.visible = _shout_for > 0.0
	_banner_for = maxf(_banner_for - delta, 0.0)
	_banner.visible = _banner_for > 0.0
	_banner_line.visible = _banner_for > 0.0

	_nav_meter.show_percent(game.nav_percent())
	_draw_top()
	_draw_health()
	_draw_streak()
	_draw_stamina()
	_draw_team()
	_draw_weapon()
	_draw_weight()
	_draw_use()
	_draw_carry()
	_draw_effects()
	_draw_overlays(delta)
	_draw_hurt(delta)
	_hold_hidden_elements()

## The top's text is rebuilt when what it is made of changes (a tenth of a second at the
## finest), not every frame; the strip is fed the cached clock each frame as before.
var _top_sig: int = 0

var _top_clock: String = ""

var _top_clock_low: bool = false

var _top_under: String = ""

var _top_rebuild_fn: Callable = _top_rebuild

func _draw_top() -> void:
	var hold := game.survival_state()
	var objective := game.current_objective()
	var sig := hash([game.phase, game.is_survival(), hold.get("style", 0), hold.get("stage", 0), hold.get("index", 0),
		hold.get("count", 0), hold.get("remaining", 0), hold.get("twist", ""), floori(float(hold.get("left", -1.0)) * 10.0),
		hold.is_empty(), floori(game.next_round_seconds() * 10.0), game.next_round_map(),
		game.map.id() if game.map != null else &"", game.map_doc.get("name", ""),
		floori(game.survival_elapsed * 10.0), game.survival_goal, objective,
		game.objective_states[objective] if objective >= 0 and objective < game.objective_states.size() else &"",
		floori(game.objective_progress[objective] * 10.0) if objective >= 0 and objective < game.objective_progress.size() else 0,
		floori(game.now() * 10.0), floori(game.grace_left_for_hud() * 10.0)])
	if sig != _top_sig:
		_top_sig = sig
		_top_rebuild_fn.call()
	strip.show_clock(_top_clock, _top_clock_low, _top_under if _top_clock != "" else "")

func _top_rebuild() -> void:
	var lines := PackedStringArray()
	var hold := game.survival_state()
	var sub := ""

	# A clock, when there is one, is the strip's, with what it is counting as its line.
	var clock := ""
	var clock_low := false
	var under := ""

	if game.phase == ZzGame.Phase.READY:
		lines.append("Leave the shelter when you are ready" if not game.is_survival() else str(game.map_doc.get("name", "")))
	elif game.is_survival() and not hold.is_empty():
		var top := survival_lines(hold)
		lines.append(top[0])
		clock = top[1]
		under = top[2]
		sub = top[3]
		clock_low = top[4]
	elif game.phase == ZzGame.Phase.IDLE and game.next_round_seconds() >= 0.0:
		# Between a decided map and the next: when, and on what.
		var next := next_round_lines(game.next_round_seconds(), game.next_round_map(), game.map.id() if game.map != null else &"",
			_map_name(game.next_round_map()))
		lines.append(next[0])
		clock = next[1]
		under = next[2]
	elif game.is_survival():
		var held := game.survival_elapsed
		lines.append(str(game.map_doc.get("name", "")))
		# Counting up: whole seconds held, never one ahead of them.
		clock = GSScoreStrip.clock_text(floorf(held))
		under = "held"
		if game.survival_goal > 0.0:
			under = "held — rescue in %s" % GSScoreStrip.clock_text(maxf(game.survival_goal - held, 0.0))
	else:
		lines.append(str(game.map_doc.get("name", "")))

	var index := game.current_objective()

	if index >= 0 and index < (game.map_doc.get("objectives", []) as Array).size():
		var o: Dictionary = (game.map_doc["objectives"] as Array)[index]

		if game.objective_states[index] == &"holding":
			var left := maxf(game.objective_progress[index] - game.now(), 0.0)
			clock = GSScoreStrip.clock_text(left)
			clock_low = left <= LOW_CLOCK_SEC
			under = "%s — hold out" % str(o["label"])
		elif sub == "" and clock == "":
			sub = "Objective: %s" % str(o["label"])
	elif not game.is_survival() and game.phase == ZzGame.Phase.PLAY and sub == "":
		sub = "Make for the shelter"

	var grace_left := game.grace_left_for_hud()
	if grace_left > 0.0:
		sub = grace_line(grace_left)

	_top.text = "\n".join(lines)
	_top_sub.text = sub
	_top_clock = clock
	_top_clock_low = clock_low
	_top_under = under

## Kills in a row: each kill within this many seconds of the last extends the streak.
const STREAK_WINDOW := 6.0

## The streak at which the row's bar reads full.
const STREAK_FULL := 10

var _streak: int = 0

var _streak_kills: int = -1

var _streak_at: float = 0.0

## The streak after [param kills] total kills at [param now]: `[streak, last_kills, last_at]`. Static so a
## suite reads it without a screen. A first look (`last_kills < 0`) only records the total; a lower
## total (a new map) resets.
static func streak_step(streak: int, last_kills: int, last_at: float, kills: int, now: float) -> Array:
	if last_kills < 0 or kills < last_kills:
		return [0, kills, now]
	if kills > last_kills:
		var run := streak if now - last_at <= STREAK_WINDOW else 0
		return [run + (kills - last_kills), kills, now]
	if streak > 0 and now - last_at > STREAK_WINDOW:
		return [0, kills, last_at]
	return [streak, kills, last_at]

func _draw_streak() -> void:
	var step := streak_step(_streak, _streak_kills, _streak_at, player.commons_killed + player.specials_killed, game.now())
	_streak = step[0]
	_streak_kills = step[1]
	_streak_at = step[2]
	vitals.show_streak(_streak, STREAK_FULL)

## The line under the title while the start grace runs; static so a suite reads it without a screen.
static func grace_line(seconds: float) -> String:
	return "Zombies arrive in %s" % GSScoreStrip.clock_text(ceilf(seconds))

## What the top says between a decided map and the next: `[title, clock, under the clock]`.
## Static, so a suite can read it without a screen.
static func next_round_lines(seconds: float, next_map: StringName, this_map: StringName, next_name: String) -> Array:
	var again := next_map == &"" or next_map == this_map
	return ["Trying again" if again else "Next: %s" % next_name, GSScoreStrip.clock_text(ceilf(seconds)),
		"until this map starts again" if again else "until the next map"]

func _map_name(id: StringName) -> String:
	if game != null and game.catalogue != null and game.catalogue.maps.has(id):
		return str((game.catalogue.maps[id] as Dictionary).get("name", id))
	return String(id)

## What the top of the screen says about a survival hold: `[title, clock, under the clock,
## line under the title, clock low]`. Static, so a suite can read it without a screen.
##
## [codeblock]
## waves    Wave 3 of 10 · Sprinters        42 left          (in a wave)
##          Breather — wave 4 next          0:24 to wave 4   mend the barricades, restock
## nights   Night 2 of 5                    1:40 until dawn
##          Day 2                           0:40 until dark
## clock    the map's name                  3:12 held
## [/codeblock]
static func survival_lines(hold: Dictionary) -> Array:
	var style := int(hold.get("style", 0))
	var stage := int(hold.get("stage", 0))
	var index := int(hold.get("index", 0))
	var count := int(hold.get("count", 0))
	var left := float(hold.get("left", -1.0))
	var twist := str(hold.get("twist", ""))
	var low := left >= 0.0 and left <= LOW_CLOCK_SEC
	var clock := GSScoreStrip.clock_text(ceilf(left)) if left >= 0.0 else ""

	match style:
		GSNpcDirectorWaves.Style.ROUNDS:
			if stage == GSNpcDirectorWaves.Stage.HORDE:
				var title := ("Wave %d of %d" % [index, count]) if index < count else "The last wave"
				if twist != "":
					title += " · %s" % twist.capitalize()
				return [title, "%d" % maxi(int(hold.get("remaining", 0)), 0), "left", "", false]
			if stage == GSNpcDirectorWaves.Stage.QUIET:
				# The hint goes under the clock, not under the title: the title's second line is
				# where the strip's clock sits, and the two were drawn over each other.
				var opening := index <= 1
				return ["Get ready" if opening else "Breather", clock,
					"until wave %d · %s" % [index, "find the doors and the caches" if opening else "mend the barricades, restock"], "", low]
			return ["All %d waves held" % count, "", "", "", false]
		GSNpcDirectorWaves.Style.CYCLE:
			if stage == GSNpcDirectorWaves.Stage.HORDE:
				return [("Night %d of %d" % [index, count]) if index < count else "The last night", clock, "until dawn", "", low]
			if stage == GSNpcDirectorWaves.Stage.QUIET:
				return ["Day %d" % index, clock, "until dark · mend the barricades, restock", "", low]
			return ["Morning", "", "", "", false]

	return ["Hold out", clock, "left" if clock != "" else "", "", low]

func _draw_health() -> void:
	var health := player.health

	if health == null:
		return

	var max_health := maxf(health.max_health, 1.0)

	if player.is_down():
		# The bleed-out pool, in red, with DOWN where the number was.
		# All of it in the low colour, the cross too: a green cross over a bleed-out reads as fine.
		vitals.fill_colour = BLEED_COLOUR
		vitals.low_fraction = 1.0
		vitals.show_vitals(health.health, max_health)
		vitals.show_status("DOWN")
		if player.helped_fraction > 0.0:
			_set_status_sig(1)
		elif game.crawl_rules.speed > 0.0:
			_set_status_sig(2)
		else:
			_set_status_sig(3)
	elif not player.is_alive():
		vitals.low_fraction = 1.0
		vitals.show_vitals(0.0, max_health)
		vitals.show_status("DEAD")
		_set_status_sig(4 if game.config.rescue_seconds > 0.0 else 5)
	else:
		# Red at the limp: the bar and the number go to the theme's low colour where the
		# controller starts limping, which is the line that matters here.
		vitals.fill_colour = HEALTH_COLOUR
		vitals.low_fraction = clampf(game.config.limp_health / max_health, 0.0, 1.0)
		vitals.show_vitals(player.real_health(), max_health, 0.0, 100.0, player.temp_health)
		vitals.show_status("")

		var downs_left := game.config.max_incaps - player.incaps
		_set_status_sig(6 if downs_left <= 0 else 0)
	_status.show_lines(_status_lines)
	downs.set_downs(game.config.max_incaps - player.incaps, game.config.max_incaps)

	# The kit rows are rebuilt only when a count or a key changes, not every frame.
	var heal_key := _key(ZzBindings.HEAL)
	var pills_key := _key(ZzBindings.PILLS)
	var use_key := _key(ZzBindings.USE)
	var kit_sig := player.medkits + (player.pills << 10) + (player.defibs << 20)
	if kit_sig != _kit_sig or heal_key != _kit_keys[0] or pills_key != _kit_keys[1] or use_key != _kit_keys[2]:
		_kit_sig = kit_sig
		_kit_keys = [heal_key, pills_key, use_key]
		_kit_rows = _build_kit_rows.call()
	kits.show_hints(_kit_rows)
	var rows := _kit_rows

	# Stacked upward from the plate: the kits' rows, then the line about downs.
	var plate_top := -PLATE_BOTTOM - 56.0 - _plate_lift
	downs.offset_bottom = plate_top - 6.0
	downs.offset_top = downs.offset_bottom - ZzDownsPips.HEIGHT
	var kits_floor := downs.offset_top if downs.visible else plate_top
	kits.offset_bottom = kits_floor - 4.0
	kits.offset_top = kits.offset_bottom - kits.row_height * rows.size()
	_status.offset_bottom = kits.offset_top - 2.0
	_status.offset_top = _status.offset_bottom - _status.row_height

## What the status line says, by what the player is: set only when the state changes. The
## builders are Callables, run on a change and not every frame.
var _status_sig: int = 0

var _status_lines: Array = []

var _kit_sig: int = -1

var _kit_keys: Array = ["", "", ""]

var _kit_rows: Array = []

var _build_kit_rows: Callable = func() -> Array:
	var rows: Array = []
	if player.defibs > 0:
		rows.append(["defibrillator x%d" % player.defibs, _kit_keys[2]])
	return rows

var _build_status_lines: Callable = func(sig: int) -> Array:
	match sig:
		0: return []
		1: return ["Getting up…"]
		2: return ["Down — crawl to a friend, or hold on for help"]
		3: return ["Down — hold on for help"]
		4: return ["Dead. Wait to be rescued."]
		5: return ["Dead."]
		6: return ["LAST LIFE — the next down is death"]
	var n := sig - 100
	return ["%d down%s left" % [n, "" if n == 1 else "s"]]

func _set_status_sig(sig: int) -> void:
	if sig != _status_sig:
		_status_sig = sig
		_status_lines = _build_status_lines.call(sig)

func _set_width(rect: ColorRect, width: float) -> void:
	rect.offset_right = rect.offset_left + maxf(width, 0.0)
	rect.visible = width > 0.5

## Pixels per team row, how many rows at most (a survival map's dozen, and a few more), and
## where the bar sits in a row.
const TEAM_ROW := 22.0

const TEAM_ROWS := 16

const TEAM_NAME_WIDTH := 150.0

const TEAM_BAR_WIDTH := 110.0

const TEAM_BAR_HEIGHT := 8.0

func _draw_team() -> void:
	# Off by default (`zz_team_roster`): hidden, so nothing is drawn and the corner is empty;
	# every other HUD piece is anchored on its own, so there is no gap to close.
	var wanted := game.config != null and game.config.team_roster
	_team.visible = wanted
	if not wanted:
		return

	var shown := 0

	for other in game.survivors():
		if other == player or shown >= TEAM_ROWS:
			continue

		var kind := 0
		var value := 0
		var fraction := -1.0

		if other.watching or not other.is_alive():
			kind = 1
		elif other.is_pinned():
			kind = 2
			value = hash(other.pin_kind)
		elif other.is_down():
			kind = 3
		elif other.health != null:
			kind = 4
			value = int(ceilf(other.health.health))
			fraction = clampf(other.health.health / maxf(other.health.max_health, 1.0), 0.0, 1.0)

		var row := _team_row(shown)
		(row["name"] as Label).text = other.display_name.substr(0, 16)
		# The state's words are built when they change, not every frame.
		var state_sig := kind + (value << 3)
		if state_sig != int(row.get("sig", -1)):
			row["sig"] = state_sig
			(row["state"] as Label).text = _team_state_fn.call(kind, value, other)
		var back: ColorRect = row["back"]
		var fill: ColorRect = row["fill"]
		back.visible = fraction >= 0.0
		_set_width(fill, TEAM_BAR_WIDTH * maxf(fraction, 0.0))
		fill.color = _piece_colour(&"good" if fraction > 0.4 else &"low", HEALTH_COLOUR)
		(row["state"] as Label).add_theme_color_override(&"font_color",
			_piece_colour(&"low", Color(0.95, 0.3, 0.22)) if fraction < 0.0 else _piece_colour(&"text", Color.WHITE))
		for part: String in ["name", "state"]:
			(row[part] as Label).visible = true
		shown += 1

	for i in range(shown, _team_rows.size()):
		var row: Dictionary = _team_rows[i]
		for part: String in ["name", "state", "back", "fill"]:
			(row[part] as CanvasItem).visible = false

var _team_state_fn: Callable = func(kind: int, value: int, other: ZzPlayer) -> String:
	match kind:
		1: return "dead"
		2: return "HELD (%s)" % String(other.pin_kind)
		3: return "DOWN"
		4: return "%d" % value
	return ""

## Row [param index] of the team list, made the first time it is needed.
func _team_row(index: int) -> Dictionary:
	while _team_rows.size() <= index:
		var top := TEAM_ROW * float(_team_rows.size())
		var name_label := Label.new()
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_constant_override("outline_size", 6)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.clip_text = true
		name_label.position = Vector2(0.0, top)
		name_label.size = Vector2(TEAM_NAME_WIDTH, TEAM_ROW)
		_team.add_child(name_label)

		var bar_top := top + (TEAM_ROW - TEAM_BAR_HEIGHT) * 0.5
		var back := ColorRect.new()
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.color = Color(0.0, 0.0, 0.0, 0.55)
		back.position = Vector2(TEAM_NAME_WIDTH + 6.0, bar_top)
		back.size = Vector2(TEAM_BAR_WIDTH, TEAM_BAR_HEIGHT)
		_team.add_child(back)

		var fill := ColorRect.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.position = back.position
		fill.size = Vector2(TEAM_BAR_WIDTH, TEAM_BAR_HEIGHT)
		_team.add_child(fill)

		var state := Label.new()
		state.add_theme_font_size_override("font_size", 15)
		state.add_theme_constant_override("outline_size", 6)
		state.mouse_filter = Control.MOUSE_FILTER_IGNORE
		state.position = Vector2(TEAM_NAME_WIDTH + TEAM_BAR_WIDTH + 14.0, top)
		state.size = Vector2(120.0, TEAM_ROW)
		_team.add_child(state)

		_team_rows.append({"name": name_label, "back": back, "fill": fill, "state": state})

	return _team_rows[index]

## One of the glance pieces' colours from the theme the root has now (this game's, or the
## menu's when it follows one), or [param fallback] when the theme does not say.
func _piece_colour(colour: StringName, fallback: Color) -> Color:
	if _root != null and _root.has_theme_color(colour, GSHudPiece.THEME_TYPE):
		return _root.get_theme_color(colour, GSHudPiece.THEME_TYPE)
	return fallback

## What the team list says, row by row, for a suite: `"name|state|bar fraction"`.
func team_lines() -> PackedStringArray:
	var out := PackedStringArray()
	for row: Dictionary in _team_rows:
		if (row["name"] as Label).visible:
			var fill: ColorRect = row["fill"]
			out.append("%s|%s|%.2f" % [(row["name"] as Label).text, (row["state"] as Label).text,
				(fill.size.x / TEAM_BAR_WIDTH) if fill.visible else 0.0])
	return out

## What the player carries (the CARRY event's document, or [method ZzCarry.state_json] offline).
func set_carry(state: Dictionary) -> void:
	_weight_state = state

func _draw_stamina() -> void:
	var s: GSFpsState = player.controller.state if player.controller != null else null
	var tunables: GSFpsTunables = player.controller.tunables if player.controller != null else null
	var shown := s != null and tunables != null and tunables.stamina_enabled and tunables.can_sprint \
		and player.is_alive() and (s.stamina < 0.999 or s.sprinting)
	stamina_bar.visible = shown
	if not shown:
		return
	stamina_bar.fill_colour = Color(0.9, 0.35, 0.25) if s.stamina_exhausted else Color(0.95, 0.8, 0.3)
	_stamina_pct = s.stamina * 100.0
	stamina_bar.refresh()

## The row of slots: one picture each, from the weapon's own model (the first time it is asked for), else the
## sprite sheet's. A slot holding several weapons shows the one in hand.
func _draw_loadout(arsenal: GSWeaponArsenal) -> void:
	var rows: Array = []
	for key in arsenal.slots():
		var held: Array[GSWeaponSlot] = arsenal.weapons_in(key)
		if held.is_empty():
			continue
		var weapon: GSWeaponSlot = held[0]
		var def := weapon.def
		var picture: Texture2D = _icons.icon_for(def.id)
		if picture == null:
			picture = ZzWeaponIcons.shared.texture(def.id)
		var line := ""
		var low := false
		if def.magazine > 0:
			if def.infinite_reserve:
				line = "%d / ∞" % weapon.magazine
			else:
				line = "%d / %d" % [weapon.magazine, arsenal.ammo().count(def.ammo_type) if def.ammo_type != &"" else 0]
			low = float(weapon.magazine) <= float(def.magazine) * 0.25
		rows.append({"key": str(key), "icon": picture, "name": ZzWeapons.title_of(def.id), "text": line,
			"selected": key == arsenal.current_slot(), "low": low})
	_append_kit_slots(rows)
	loadout.set_slots(rows)

## 0..1 of a hold-to-heal in progress, set by whatever runs the heal (the inventory work); 0 draws no bar.
var _heal_fraction: float = 0.0

func set_heal_fraction(fraction: float) -> void:
	_heal_fraction = clampf(fraction, 0.0, 1.0)

## The medkits and pills after the weapons, one slot each (a text slot: no model to render). A heal in progress
## ([method set_heal_fraction]) fills the bar along the foot of its slot. The kits' hint rows over the health plate keep only the defibrillator.
func _append_kit_slots(rows: Array) -> void:
	if player.medkits <= 0 and player.pills <= 0:
		return
	var green := Color(0.35, 0.9, 0.5)
	if player.medkits > 0:
		rows.append({"key": _kit_keys[0], "name": "MEDKIT", "text": "x%d" % player.medkits, "accent": green,
			"fill": _heal_fraction})
	if player.pills > 0:
		rows.append({"key": _kit_keys[1], "name": "PILLS", "text": "x%d" % player.pills, "accent": green})

func _draw_weight() -> void:
	if loadout == null:
		return
	if not (bool(_weight_state.get("on", false)) and player.is_alive()):
		loadout.clear_weight()
		return
	loadout.set_weight(float(_weight_state.get("w", 0.0)), float(_weight_state.get("l", 1.0)),
		int(_weight_state.get("tier", 0)), int(_weight_state.get("max", 0)))

const FIRE_NAMES := {GSWeaponDef.Fire.AUTO: &"auto", GSWeaponDef.Fire.SEMI: &"semi", GSWeaponDef.Fire.BURST: &"burst"}

## Scratch for the fire modes on offer, reused each frame.
var _offered: Array = []

var _rig_player: ZzPlayer = null

var _rig_node: ZeeWeaponRig = null

var _rig_lookup_fn: Callable = func() -> ZeeWeaponRig:
	return player.get_node_or_null(^"Weapons") as ZeeWeaponRig

## The player's own "Weapons" rig by name (the world's, offline), looked up once per player.
func _world_rig() -> ZeeWeaponRig:
	if _rig_player != player or not is_instance_valid(_rig_node):
		_rig_player = player
		_rig_node = _rig_lookup_fn.call()
	return _rig_node

func _draw_weapon() -> void:
	# The gun you see, whose reload you watch, corrected from the server's count. By the node's
	# name this read the world's rig offline, a second rig beside the drawn one (which Godot had
	# renamed), and showed whatever that one had.
	var rig: ZeeWeaponRig = player.view_rig if player.view_rig != null and is_instance_valid(player.view_rig) \
		else _world_rig()

	if rig == null or rig.arsenal == null or rig.arsenal.current() == null:
		ammo.clear()
		fire_mode.clear()
		loadout.set_slots([])
		return

	_offered.clear()
	for m in rig.arsenal.fire_modes_available():
		_offered.append(FIRE_NAMES.get(m, &""))
	fire_mode.show_modes(_offered, FIRE_NAMES.get(rig.arsenal.fire_mode(), &""))

	var slot := rig.arsenal.current()
	var title := ZzWeapons.title_of(slot.def.id)
	_draw_loadout(rig.arsenal)

	if slot.def.magazine > 0:
		var reserve := rig.arsenal.ammo().count(slot.def.ammo_type) if slot.def.ammo_type != &"" else 0
		# Low at a quarter of a magazine: the reload worth starting before the crowd arrives.
		ammo.show_ammo(title, slot.magazine, reserve, float(slot.magazine) <= float(slot.def.magazine) * 0.25,
			slot.def.infinite_reserve)
	else:
		ammo.show_ammo(title, -1, -1)

const HELD_TEXT := {
	&"grab": "GRABBED — shoot it, or a friend can shove it off",
	&"pounce": "POUNCED — your team has to free you",
	&"choke": "TONGUED — your team has to free you",
	&"carry": "CARRIED — your team has to free you",
	&"ride": "RIDDEN — your team has to free you",
	&"eat": "BEING EATEN — your team has to free you",
}

const HELD_DEFAULT := "HELD — your team has to free you"

func _draw_use() -> void:
	var fraction := 0.0

	# Only the bar: the words under it said what the action was, which the hands already show.
	if player.using != &"":
		fraction = player.use_fraction
	elif player.helped_fraction > 0.0:
		fraction = player.helped_fraction

	_use_back.visible = fraction > 0.0
	_set_width(_use_fill, 320.0 * fraction)
	_use_fill.visible = fraction > 0.0

	if player.is_pinned():
		_held.text = HELD_TEXT.get(player.pin_kind, HELD_DEFAULT)
		_held.visible = true
	else:
		_held.visible = false

## The deploy meter pulses while it fills: the first-person cue that something is happening.
func _draw_carry() -> void:
	if player.using == &"deploy":
		_use_fill.color = Color(0.95, 0.85, 0.35).lerp(Color(1.0, 0.45, 0.2), 0.5 + 0.5 * sin(Time.get_ticks_msec() / 90.0))
	else:
		_use_fill.color = Color(0.95, 0.85, 0.35)

## The effect lines are rebuilt when a clock ticks over, a row comes or goes, or the rows are
## replaced, not every frame. The signature below is integers only.
var _effects_sig: int = 0

var _effects_rebuild_fn: Callable = _effects_rebuild

## Whether [param row] is on show [param since] seconds after the rows arrived.
func _effect_on(row: Dictionary, since: float) -> bool:
	# A negative clock is "until the round ends": it never runs out here.
	if float(row["seconds"]) >= 0.0 and float(row["seconds"]) - since <= 0.0:
		return false

	var who: String = row.get("who", "")
	# The rows carry a name ("everybody" or a person), never a player key, so compare by name.
	return who == "" or who == "everybody" or player == null or who == player.display_name

func _draw_effects() -> void:
	if _effect_rows.is_empty():
		_effects.clear()
		_effects_sig = 0
		return

	var since := Time.get_ticks_msec() / 1000.0 - _effects_at
	var sig := _effect_rows.size() + 1

	for i in _effect_rows.size():
		var row: Dictionary = _effect_rows[i]

		if _effect_on(row, since):
			var seconds := float(row["seconds"])
			sig = sig * 1000003 + i * 7919 + (int(ceilf(seconds - since)) if seconds >= 0.0 else -1)

	if sig == _effects_sig:
		return

	_effects_sig = sig
	_effects_rebuild_fn.call(since)

func _effects_rebuild(since: float) -> void:
	var lines: Array = []

	for row: Dictionary in _effect_rows:
		if not _effect_on(row, since):
			continue

		var timed := float(row["seconds"]) >= 0.0
		var left := float(row["seconds"]) - since
		var stacks := int(row["stacks"])
		var scale := float(row.get("scale", 1.0))
		var title := str(row["title"])
		if scale != 1.0 and scale > 0.0:
			title += " x%s" % (str(snappedf(scale, 0.01)) if scale < 10.0 else str(int(scale)))
			stacks = 1
		lines.append({"text": GSStatusLines.effect_text(title, stacks, left if timed else -1.0), "colour": AMBER})

	_effects.show_lines(lines)

func _draw_overlays(delta: float) -> void:
	var step := maxf(delta, 0.0) / BLIND_FADE_SEC
	_fade(_bile, 0.42 if player.biled else 0.0, step)
	_goo.per_stack_amount = game.config.goo_screen_per_stack
	_goo.max_amount = game.config.goo_screen_max
	_goo.set_status(player.goo_stacks, 1.0)
	_fade(_wet, 0.38 if player.submerged else 0.0, step * 2.0)
	_draw_air()
	_fade(_blind, 1.0 if (player.blinded or player.box_blind) else 0.0, step * 0.5)
	# A flash is white at once and clears slowly; a box blind eases in.
	if player.flashed:
		_flash.modulate.a = player.flash_strength
		_flash.visible = true
	else:
		_fade(_flash, 0.0, step * 0.4)
	_fade(_fire, 0.18 if player.burning else 0.0, step)
	_fade(_grey, 0.35 if player.is_alive() and player.incaps >= game.config.max_incaps and not player.is_down() else 0.0, step * 0.3)

	var low := player.is_alive() and not player.is_down() and player.health != null \
		and player.health.health < game.config.limp_health
	var pulse := 0.12 + 0.08 * sin(Time.get_ticks_msec() * 0.006)
	_fade(_low, pulse if low or player.is_down() else 0.0, step)

## The breath bar: there while the eyes are under or the lungs not yet full, red when it is out.
func _draw_air() -> void:
	var full := maxf(game.water_rules.drown_seconds, 0.001)
	var fraction := clampf(player.air / full, 0.0, 1.0)
	var show := game.water_rules.drown_seconds > 0.0 and (player.submerged or fraction < 0.999)
	_air_back.visible = show
	_air_fill.visible = show

	if show:
		_air_fill.offset_right = _air_fill.offset_left + 200.0 * fraction
		_air_fill.color = Color(0.55, 0.85, 1.0) if fraction > 0.0 else Color(0.95, 0.2, 0.15)
		_air_fill.visible = fraction > 0.0

func _fade(rect: ColorRect, target: float, step: float) -> void:
	rect.modulate.a = move_toward(rect.modulate.a, target, step)
	rect.visible = rect.modulate.a > 0.001

func _draw_hurt(delta: float) -> void:
	var size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1280, 720)
	var reach := minf(size.x, size.y) * 0.16

	for i in _hurt_marks.size():
		var mark: Dictionary = _hurt_marks[i]
		mark["left"] = maxf(float(mark["left"]) - delta, 0.0)
		var rect: ColorRect = mark["rect"]
		var a := clampf(float(mark["left"]) / HURT_SECONDS, 0.0, 1.0)
		rect.color.a = a * 0.7

		# 0 ahead, 1 right, 2 behind, 3 left.
		match i:
			0:
				_place(rect, Vector2(-60, -reach - 8), Vector2(120, 8))
			1:
				_place(rect, Vector2(reach, -60), Vector2(8, 120))
			2:
				_place(rect, Vector2(-60, reach), Vector2(120, 8))
			3:
				_place(rect, Vector2(-reach - 8, -60), Vector2(8, 120))

## The ring round the crosshair that fills while the use key is held over a dropped weapon (gs-ui API 18).
func set_hold_progress(fraction: float) -> void:
	if _crosshair != null and GSAddonApi.build_level("gs_ui") >= 18:
		_crosshair.set(&"hold_progress", fraction)

func _place(rect: ColorRect, at: Vector2, size: Vector2) -> void:
	rect.offset_left = at.x
	rect.offset_top = at.y
	rect.offset_right = at.x + size.x
	rect.offset_bottom = at.y + size.y

func is_blind() -> bool:
	return player != null and is_instance_valid(player) and (player.blinded or player.box_blind)
