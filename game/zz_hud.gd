extends CanvasLayer

const ZzGame := preload("zz_game.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzBindings := preload("zz_bindings.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzWeapons := preload("zz_weapons.gd")

## What a survivor needs on screen, and nothing that would make a dark street less dark.
##
## [codeblock]
## bottom left    your health: real health green, borrowed health white over it; down, a red
##                bleed bar and how many downs are left; your medkit and pills
## left           the team: each name, their health, and whether they are up, down, held or dead
## bottom right   what you are holding and how much is in it
## top            the objective, a hold-out's clock, a survival map's clock
## centre         the crosshair, what E would do, the bar of what you are holding E for,
##                and the bar of somebody picking you up
## right          what the boxes are doing to the game, stacked ("Horde frenzy x4 1:12")
## over it all    which way a hit came from; bile, a flash, fire, the last-life grey
## [/codeblock]
##
## [b]The keys are read from the bindings, not written here.[/b] Every prompt says the key the
## action is on NOW, from the same table the menu's Controls page edits.
##
## [b]The glance pieces are dot-ui's[/b]: health is a [DotVitals] (borrowed health as its
## `bonus`, DOWN and DEAD as its `status`), the weapon a [DotAmmoCounter] (an endless reserve
## as ∞), a hold-out's or a survival map's clock a [DotScoreStrip] under the title, the
## medkit and pills [DotKeyHints], and every hit the server confirms a [DotHitMarker] and a
## [DotDamageNumbers] number on the body. The number on the health plate is real health; the
## borrowed part is the white length after it, which drains, and a number that included it
## would fall on its own while nobody was hitting you.

const BLIND_FADE_SEC := 0.25
const HURT_SECONDS := 1.2

## Seconds left of a hold-out at which its clock turns red.
const LOW_CLOCK_SEC := 10.0

const HEALTH_COLOUR := Color(0.35, 0.85, 0.35)
const BLEED_COLOUR := Color(0.85, 0.12, 0.1)

## Where the health plate ends, pixels off the bottom: above the chat box's full eight-row
## log, which reaches 202 (checked in headless_run).
const PLATE_BOTTOM := 206.0

## The boxes' amber, which is also the glance pieces' highlight.
const AMBER := Color(0.98, 0.84, 0.5)


## The glance pieces' colours in this game's palette: a near-black plate for a dark street,
## the boxes' amber as highlight, the health bar's green as "good". Static so a render tool
## can use it.
static func piece_theme() -> Theme:
	var t := Theme.new()
	var type := DotHudPiece.THEME_TYPE
	t.set_color(&"plate", type, Color(0.04, 0.05, 0.06, 0.62))
	t.set_color(&"plate_edge", type, Color(1.0, 1.0, 1.0, 0.12))
	t.set_color(&"highlight", type, AMBER)
	t.set_color(&"good", type, HEALTH_COLOUR)
	t.set_color(&"low", type, Color(0.95, 0.3, 0.22))
	return t

var game: ZzGame = null
var player: ZzPlayer = null

## `func(action: StringName) -> String`: the key an action is on. Set by the client.
var key_fn: Callable = Callable()

var watching_label: Label = null

var _root: Control = null
var _shout: Label = null
var _shout_for: float = 0.0
var _banner: Label = null
var _banner_line: Label = null
var _banner_for: float = 0.0
var _top: Label = null
var _top_sub: Label = null
## Health: real, borrowed (its bonus), and DOWN or DEAD in place of the number.
var vitals: DotVitals = null
## What is in hand and how much is in it.
var ammo: DotAmmoCounter = null
## A hold-out's or a survival map's clock, under the title; nothing on a map without one.
var strip: DotScoreStrip = null
## The medkit and pills, each with its key.
var kits: DotKeyHints = null
## Four ticks round the crosshair on a hit the server confirmed.
var hit_marker: DotHitMarker = null
## The confirmed hits' numbers, on the bodies they landed on.
var damage_numbers: DotDamageNumbers = null
var _status: Label = null
var _team: Label = null
var _effects: Label = null
var _prompt: Label = null
var _use_back: ColorRect = null
var _use_fill: ColorRect = null
var _use_label: Label = null
var _held: Label = null
var _crosshair: ColorRect = null
var _bile: ColorRect = null
var _blind: ColorRect = null
var _fire: ColorRect = null
var _grey: ColorRect = null
var _low: ColorRect = null
var _hurt_marks: Array = []
var _effect_rows: Array = []
var _effects_at: float = 0.0


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
	_bile = _cover("Bile", Color(0.38, 0.52, 0.08))
	_fire = _cover("Fire", Color(0.95, 0.4, 0.05))
	_grey = _cover("LastLife", Color(0.12, 0.12, 0.12))
	_blind = _cover("Blind", Color(0.97, 0.97, 0.94))

	# The glance pieces read their colours from the theme on the type DotHudPiece; set on
	# the root, every piece under it inherits them. See [method piece_theme].
	_root.theme = piece_theme()

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
	strip = DotScoreStrip.new()
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
	vitals = DotVitals.new()
	vitals.name = "Vitals"
	vitals.bar_end = 300.0
	vitals.fill_colour = HEALTH_COLOUR
	vitals.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	vitals.offset_left = 22.0
	vitals.offset_right = 22.0 + 420.0
	vitals.offset_top = -PLATE_BOTTOM - 56.0
	vitals.offset_bottom = -PLATE_BOTTOM
	_root.add_child(vitals)

	kits = DotKeyHints.new()
	kits.name = "Kits"
	kits.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	kits.offset_left = 24.0
	kits.offset_right = 24.0 + 300.0
	_root.add_child(kits)

	_status = _label(16)
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.offset_left = 24.0
	_status.offset_right = 600.0

	# The team, top left.
	_team = _label(15)
	_team.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_team.offset_left = 22.0
	_team.offset_top = 18.0
	_team.offset_right = 380.0
	_team.offset_bottom = 300.0

	# Weapon and ammunition, bottom right: the counter right-aligns to its own right edge.
	ammo = DotAmmoCounter.new()
	ammo.name = "Ammo"
	ammo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo.offset_left = -420.0
	ammo.offset_right = -24.0
	ammo.offset_top = -100.0
	ammo.offset_bottom = -24.0
	_root.add_child(ammo)

	# What the boxes are doing, right side.
	_effects = _label(15)
	_effects.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_effects.offset_left = -420.0
	_effects.offset_right = -22.0
	_effects.offset_top = 90.0
	_effects.offset_bottom = 360.0
	_effects.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_effects.add_theme_color_override("font_color", Color(0.98, 0.84, 0.5))

	# The centre: crosshair, prompt, the bar of what you hold E for.
	_crosshair = ColorRect.new()
	_crosshair.name = "Crosshair"
	_crosshair.color = Color(1.0, 1.0, 1.0, 0.75)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.offset_left = -2.0
	_crosshair.offset_top = -2.0
	_crosshair.offset_right = 2.0
	_crosshair.offset_bottom = 2.0
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_crosshair)

	_prompt = _label(17)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -400.0
	_prompt.offset_right = 400.0
	_prompt.offset_top = 40.0
	_prompt.offset_bottom = 66.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))

	_use_back = _rect(Color(0.0, 0.0, 0.0, 0.55), Control.PRESET_CENTER, -160.0, 74.0, 320.0, 12.0)
	_use_fill = _rect(Color(0.95, 0.85, 0.35), Control.PRESET_CENTER, -160.0, 74.0, 0.0, 12.0)
	_use_label = _label(16)
	_use_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_use_label.offset_left = -300.0
	_use_label.offset_right = 300.0
	_use_label.offset_top = 88.0
	_use_label.offset_bottom = 112.0
	_use_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_held = _label(28)
	_held.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_held.offset_left = -500.0
	_held.offset_right = 500.0
	_held.offset_top = -120.0
	_held.offset_bottom = -80.0
	_held.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))

	# Full rect, centred on the crosshair; both draw only what the server confirmed.
	damage_numbers = DotDamageNumbers.new()
	damage_numbers.name = "DamageNumbers"
	damage_numbers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(damage_numbers)

	hit_marker = DotHitMarker.new()
	hit_marker.name = "HitMarker"
	hit_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(hit_marker)

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


func _cover(cover_name: String, colour: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.name = cover_name
	rect.color = colour
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	rect.visible = false
	_root.add_child(rect)
	return rect


func _rect(colour: Color, preset: int, left: float, top: float, width: float, height: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = colour
	rect.set_anchors_and_offsets_preset(preset)
	rect.offset_left = left
	rect.offset_right = left + width
	rect.offset_top = top
	rect.offset_bottom = top + height
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rect)
	return rect


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


func set_watching(text: String) -> void:
	if watching_label != null:
		watching_label.text = text


## One line in the middle of the screen, for a few seconds.
func shout(text: String, seconds: float = 3.5) -> void:
	if _shout == null:
		return

	_shout.text = text
	_shout_for = seconds


## A box's outcome: its title in the box's colour, and the message under it.
func box_banner(title: String, message: String, colour: Color) -> void:
	if _banner == null:
		return

	_banner.text = title
	_banner.add_theme_color_override("font_color", colour.lightened(0.15))
	_banner_line.text = message
	_banner_for = 4.0


## What the boxes are doing to the game: `[{title, stacks, seconds, who, scale}]`.
func set_effects(rows: Array) -> void:
	_effect_rows = rows
	_effects_at = Time.get_ticks_msec() / 1000.0


func set_prompt(text: String) -> void:
	if _prompt != null:
		_prompt.text = text


## A hit of this survivor's that the server confirmed: the marker round the crosshair, and
## the number rising off the body. Never called from the local prediction.
func confirm_hit(victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
	if hit_marker == null:
		return

	hit_marker.flash(killed, headshot)
	damage_numbers.add(victim, amount, point, headshot)


## A hit from [param from]: a red mark on that side of the crosshair.
func hurt_from(from: Vector3, amount: float) -> void:
	if player == null or _hurt_marks.is_empty():
		return

	var to := from - player.feet()
	to.y = 0.0

	if to.length() < 0.1:
		return

	var yaw := deg_to_rad(player.controller.state.yaw)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var bearing := atan2(to.normalized().dot(right), to.normalized().dot(forward))
	var index := posmod(roundi(bearing / (PI * 0.5)), 4)
	var mark: Dictionary = _hurt_marks[index]
	mark["left"] = HURT_SECONDS * clampf(amount / 10.0, 0.5, 1.5)


func _key(action: StringName) -> String:
	return str(key_fn.call(action)) if key_fn.is_valid() else String(action)


func _process(delta: float) -> void:
	if _root == null or game == null or player == null or not is_instance_valid(player):
		return

	_shout_for = maxf(_shout_for - delta, 0.0)
	_shout.visible = _shout_for > 0.0
	_banner_for = maxf(_banner_for - delta, 0.0)
	_banner.visible = _banner_for > 0.0
	_banner_line.visible = _banner_for > 0.0

	_draw_top()
	_draw_health()
	_draw_team()
	_draw_weapon()
	_draw_use()
	_draw_effects()
	_draw_overlays(delta)
	_draw_hurt(delta)


func _draw_top() -> void:
	var lines := PackedStringArray()
	var sub := ""

	# A clock, when there is one, is the strip's, with what it is counting as its line.
	var clock := ""
	var clock_low := false
	var under := ""

	var hold := game.survival_state()

	if game.phase == ZzGame.Phase.READY:
		lines.append("Leave the shelter when you are ready" if not game.is_survival() else str(game.map_doc.get("name", "")))
	elif game.is_survival() and not hold.is_empty():
		var top := survival_lines(hold)
		lines.append(top[0])
		clock = top[1]
		under = top[2]
		sub = top[3]
		clock_low = top[4]
	elif game.is_survival():
		var held := game.survival_elapsed
		lines.append(str(game.map_doc.get("name", "")))
		# Counting up: whole seconds held, never one ahead of them.
		clock = DotScoreStrip.clock_text(floorf(held))
		under = "held"
		if game.survival_goal > 0.0:
			under = "held — rescue in %s" % DotScoreStrip.clock_text(maxf(game.survival_goal - held, 0.0))
	else:
		lines.append(str(game.map_doc.get("name", "")))

	var index := game.current_objective()

	if index >= 0 and index < (game.map_doc.get("objectives", []) as Array).size():
		var o: Dictionary = (game.map_doc["objectives"] as Array)[index]

		if game.objective_states[index] == &"holding":
			var left := maxf(game.objective_progress[index] - game.now(), 0.0)
			clock = DotScoreStrip.clock_text(left)
			clock_low = left <= LOW_CLOCK_SEC
			under = "%s — hold out" % str(o["label"])
		elif sub == "" and clock == "":
			sub = "Objective: %s" % str(o["label"])
	elif not game.is_survival() and game.phase == ZzGame.Phase.PLAY and sub == "":
		sub = "Make for the shelter"

	_top.text = "\n".join(lines)
	_top_sub.text = sub
	strip.show_clock(clock, clock_low, under if clock != "" else "")


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
	var clock := DotScoreStrip.clock_text(ceilf(left)) if left >= 0.0 else ""

	match style:
		DotNpcDirectorWaves.Style.ROUNDS:
			if stage == DotNpcDirectorWaves.Stage.HORDE:
				var title := ("Wave %d of %d" % [index, count]) if index < count else "The last wave"
				if twist != "":
					title += " · %s" % twist.capitalize()
				return [title, "%d" % maxi(int(hold.get("remaining", 0)), 0), "left", "", false]
			if stage == DotNpcDirectorWaves.Stage.QUIET:
				# The hint goes under the clock, not under the title: the title's second line is
				# where the strip's clock sits, and the two were drawn over each other.
				var opening := index <= 1
				return ["Get ready" if opening else "Breather", clock,
					"until wave %d · %s" % [index, "find the doors and the caches" if opening else "mend the barricades, restock"], "", low]
			return ["All %d waves held" % count, "", "", "", false]
		DotNpcDirectorWaves.Style.CYCLE:
			if stage == DotNpcDirectorWaves.Stage.HORDE:
				return [("Night %d of %d" % [index, count]) if index < count else "The last night", clock, "until dawn", "", low]
			if stage == DotNpcDirectorWaves.Stage.QUIET:
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
		_status.text = "Down — hold on for help" if player.helped_fraction <= 0.0 else "Getting up…"
	elif not player.is_alive():
		vitals.low_fraction = 1.0
		vitals.show_vitals(0.0, max_health)
		vitals.show_status("DEAD")
		_status.text = "Dead. Wait to be rescued." if game.config.rescue_seconds > 0.0 else "Dead."
	else:
		# Red at the limp: the bar and the number go to the theme's low colour where the
		# controller starts limping, which is the line that matters here.
		vitals.fill_colour = HEALTH_COLOUR
		vitals.low_fraction = clampf(game.config.limp_health / max_health, 0.0, 1.0)
		vitals.show_vitals(player.real_health(), max_health, 0.0, 100.0, player.temp_health)
		vitals.show_status("")

		var downs_left := game.config.max_incaps - player.incaps
		_status.text = "LAST LIFE — the next down is death" if downs_left <= 0 \
			else ("%d down%s left" % [downs_left, "" if downs_left == 1 else "s"])

	var rows: Array = []
	if player.medkits > 0:
		rows.append(["medkit", _key(ZzBindings.HEAL)])
	if player.pills > 0:
		rows.append(["pills", _key(ZzBindings.PILLS)])
	kits.show_hints(rows)

	# Stacked upward from the plate: the kits' rows, then the line about downs.
	var plate_top := -PLATE_BOTTOM - 56.0
	kits.offset_bottom = plate_top - 4.0
	kits.offset_top = kits.offset_bottom - kits.row_height * rows.size()
	_status.offset_bottom = kits.offset_top - 2.0
	_status.offset_top = _status.offset_bottom - 26.0


func _set_width(rect: ColorRect, width: float) -> void:
	rect.offset_right = rect.offset_left + maxf(width, 0.0)
	rect.visible = width > 0.5


func _draw_team() -> void:
	var lines := PackedStringArray()

	for other in game.survivors():
		if other == player:
			continue

		var state := ""

		if other.watching or not other.is_alive():
			state = "dead"
		elif other.is_pinned():
			state = "HELD (%s)" % String(other.pin_kind)
		elif other.is_down():
			state = "DOWN"
		else:
			state = "%d" % int(ceilf(other.health.health)) if other.health != null else ""

		var bar := ""
		if other.is_alive() and not other.is_down() and other.health != null:
			var filled := int(round(clampf(other.health.health / maxf(other.health.max_health, 1.0), 0.0, 1.0) * 10.0))
			bar = "▮".repeat(filled) + "▯".repeat(10 - filled)

		lines.append("%-14s %s %s" % [other.display_name.substr(0, 14), bar, state])

	_team.text = "\n".join(lines)


func _draw_weapon() -> void:
	# The gun you see, whose reload you watch, corrected from the server's count. By the node's
	# name this read the world's rig offline, a second rig beside the drawn one (which Godot had
	# renamed), and showed whatever that one had.
	var rig: ZeeWeaponRig = player.view_rig if player.view_rig != null and is_instance_valid(player.view_rig) \
		else player.get_node_or_null(^"Weapons") as ZeeWeaponRig

	if rig == null or rig.arsenal == null or rig.arsenal.current() == null:
		ammo.clear()
		return

	var slot := rig.arsenal.current()
	var title := ZzWeapons.title_of(slot.def.id)

	if slot.def.magazine > 0:
		var reserve := rig.arsenal.ammo().count(slot.def.ammo_type) if slot.def.ammo_type != &"" else 0
		# Low at a quarter of a magazine: the reload worth starting before the crowd arrives.
		ammo.show_ammo(title, slot.magazine, reserve, float(slot.magazine) <= float(slot.def.magazine) * 0.25,
			slot.def.infinite_reserve)
	else:
		ammo.show_ammo(title, -1, -1)


func _draw_use() -> void:
	var fraction := 0.0
	var text := ""

	if player.using != &"":
		fraction = player.use_fraction
		text = {&"revive": "Picking them up…", &"heal": "Healing…", &"loot": "Opening…", &"objective": "Working…", &"repair": "Mending the barricade…"}.get(player.using, "")
	elif player.helped_fraction > 0.0:
		fraction = player.helped_fraction
		text = "Somebody is helping you…"

	_use_back.visible = fraction > 0.0
	_use_label.visible = fraction > 0.0
	_set_width(_use_fill, 320.0 * fraction)
	_use_fill.visible = fraction > 0.0
	_use_label.text = text

	if player.is_pinned():
		_held.text = "GRABBED — shoot it, or a friend can shove it off" if player.pin_kind == &"grab" \
			else {&"pounce": "POUNCED", &"choke": "TONGUED", &"carry": "CARRIED", &"ride": "RIDDEN"}.get(player.pin_kind, "HELD") \
			+ " — your team has to free you"
		_held.visible = true
	else:
		_held.visible = false


func _draw_effects() -> void:
	if _effect_rows.is_empty():
		_effects.text = ""
		return

	var since := Time.get_ticks_msec() / 1000.0 - _effects_at
	var lines := PackedStringArray()

	for row: Dictionary in _effect_rows:
		var left := float(row["seconds"]) - since

		if left <= 0.0:
			continue

		var who := str(row.get("who", ""))
		if who != "" and player != null and who != String(player.player_id):
			continue

		var stacks := int(row["stacks"])
		var scale := float(row.get("scale", 1.0))
		var tag := ""
		if scale != 1.0 and scale > 0.0:
			tag = " x%s" % (str(snappedf(scale, 0.01)) if scale < 10.0 else str(int(scale)))
		elif stacks > 1:
			tag = " x%d" % stacks
		lines.append("%s%s  %s" % [str(row["title"]), tag, DotScoreStrip.clock_text(left)])

	_effects.text = "\n".join(lines)


func _draw_overlays(delta: float) -> void:
	var step := maxf(delta, 0.0) / BLIND_FADE_SEC
	_fade(_bile, 0.42 if player.biled else 0.0, step)
	_fade(_blind, 1.0 if (player.blinded or player.box_blind) else 0.0, step * 0.5)
	_fade(_fire, 0.18 if player.burning else 0.0, step)
	_fade(_grey, 0.35 if player.is_alive() and player.incaps >= game.config.max_incaps and not player.is_down() else 0.0, step * 0.3)

	var low := player.is_alive() and not player.is_down() and player.health != null \
		and player.health.health < game.config.limp_health
	var pulse := 0.12 + 0.08 * sin(Time.get_ticks_msec() * 0.006)
	_fade(_low, pulse if low or player.is_down() else 0.0, step)


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


func _place(rect: ColorRect, at: Vector2, size: Vector2) -> void:
	rect.offset_left = at.x
	rect.offset_top = at.y
	rect.offset_right = at.x + size.x
	rect.offset_bottom = at.y + size.y


func is_blind() -> bool:
	return player != null and is_instance_valid(player) and (player.blinded or player.box_blind)
