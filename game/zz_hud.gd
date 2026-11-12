extends CanvasLayer

const ZzGame := preload("zz_game.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzBindings := preload("zz_bindings.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzWeaponIcons := preload("zz_weapon_icons.gd")
const ZzNavMeter := preload("zz_nav_meter.gd")

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


## This game's accent over whichever theme the player picked in the menu: the boxes' amber as
## the glance pieces' highlight, the health bar's green as "good". The plates, the words and
## their outline are the theme's (dark by default), so a light or high-contrast theme can
## change them. Static so a render tool can use it.
static func piece_theme() -> Theme:
	var t := Theme.new()
	var type := DotHudPiece.THEME_TYPE
	t.set_color(&"highlight", type, AMBER)
	t.set_color(&"good", type, HEALTH_COLOUR)
	return t


## The Escape menu, whose theme this HUD follows (dot-menu's `follow_hud`): the menu sets the
## theme on the HUD's root now and at every theme change, and applies the player's HUD size.
## Christian's first play test (2026-10-11) asked for a darker HUD a player can restyle in the
## menu. Duck-typed and called by name, for a client shell older than dot-menu 7.
var _menu: Object = null


func follow_menu(menu: Object) -> void:
	_menu = menu
	_follow()


func _follow() -> void:
	if _root != null and _menu != null and _menu.has_method(&"follow_hud"):
		_menu.call(&"follow_hud", _root, piece_theme())


## The player's `cl_hud_show_<element>` switches (dot-ui's [DotHudElementCvars]; `cl_hud_scale` is
## the menu's own HUD size, so it is not registered). The pieces below are attached in [method _attach_elements].
var elements := DotHudElementCvars.new()

## element id -> the controls it hides; a piece that sets its own visibility each frame is put
## back to hidden after the draw (see [method _hold_hidden_elements]).
var _element_nodes: Dictionary = {}


func _attach_elements() -> void:
	var map := {
		&"vitals": [vitals, stamina_bar, kits],
		&"weapons": [_weapon_icon, _weight, _weight_back, _weight_fill, _carry],
		&"ammo": [ammo],
		&"fire_mode": [fire_mode],
		&"teammates": [_team],
		&"wave": [strip],
		&"prompts": [_prompt, _use_back, _use_fill, _use_label, _held],
		&"damage_dir": _hurt_marks.map(func(m: Dictionary) -> Control: return m["rect"]),
		&"hit_markers": [hit_marker, damage_numbers],
	}
	for id: StringName in map:
		_element_nodes[id] = map[id]
		for node: Variant in map[id]:
			var _ok := elements.attach(id, node as CanvasItem)
	elements.changed.connect(elements.apply)


func _hold_hidden_elements() -> void:
	for id: StringName in _element_nodes:
		if elements.is_shown(id):
			continue
		for node: Variant in _element_nodes[id]:
			if is_instance_valid(node):
				(node as CanvasItem).visible = false


## Registers the element cvars on a console's local source.
func bind_elements(local: Object) -> void:
	if local == null or not local.has_method(&"add_var"):
		return
	for id: StringName in DotHudElementCvars.ELEMENTS:
		var name := DotHudElementCvars.cvar_name(id)
		local.call(&"add_var", StringName(name), String((DotHudElementCvars.ELEMENTS[id] as Array)[1]) + " (0 hides, 1 shows)",
			func() -> Variant: return "1" if elements.is_shown(id) else "0",
			func(v: Variant) -> Variant:
				if not elements.set_cvar(name, str(v)):
					return DotResult.fail(DotError.CODE_INVALID, "unreadable value: " + str(v))
				elements.apply()
				return null)


## The full-rect Control every piece sits on.
func screen() -> Control:
	# Built on demand: the touch buttons ask before a survivor is seated (bind builds it otherwise).
	if _root == null:
		_build()
	return _root


## Moves the weight readout (slot list and bar) [param px] left of the right edge, clear of the touch
## buttons: FIRE and its cluster sit over it on a phone.
func shift_weight_left(px: float) -> void:
	screen()
	for c: Control in [_weight, _weight_back, _weight_fill]:
		c.offset_left -= px
		c.offset_right -= px


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
## The carried weapon's sprite above the counter (`cl_weapon_icons`); hidden when the weapon has none.
var _weapon_icon: DotWeaponIconPlate = null
## The held gun's fire modes, above the ammunition.
var fire_mode: DotFireModeIndicator = null
## A hold-out's or a survival map's clock, under the title; nothing on a map without one.
var strip: DotScoreStrip = null
## The medkit and pills, each with its key.
var kits: DotKeyHints = null
var stamina_bar: DotStatBar = null
var _stamina_pct: float = 100.0
## Four ticks round the crosshair on a hit the server confirmed.
## The marker and numbers layer ([DotHitFeedback]); [member hit_marker] and
## [member damage_numbers] are its two pieces.
var hit_fx: DotHitFeedback = null
var hit_marker: DotHitMarker = null
## The confirmed hits' numbers, on the bodies they landed on.
var damage_numbers: DotDamageNumbers = null
var _status: DotStatusLines = null
var _nav_meter: PanelContainer = null
## The team, top left: a row per other survivor (name, a health bar, the number or DOWN /
## HELD / dead). The bar is drawn, not typed: as a row of block characters it came out as
## missing-glyph boxes on Windows, whose fallback fonts lack them (first play test).
var _team: Control = null
var _team_rows: Array[Dictionary] = []
var _effects: DotStatusLines = null
var _prompt: Label = null
## The box file's order, titles and colours, set by the client: the carried slot is drawn from
## `player.carried_index` (an index into it plus one; 0 is unknown, or nothing carried).
var box_order: Array[StringName] = []
var box_titles: Dictionary = {}
var box_colours: Dictionary = {}
var _carry: Label = null
## The weight readout (bar and slot contents), fed by [method set_carry]; hidden when the rule is off.
var _weight: Label = null
var _weight_back: ColorRect = null
var _weight_fill: ColorRect = null
var _weight_state: Dictionary = {"on": false}
var _use_back: ColorRect = null
var _use_fill: ColorRect = null
var _use_label: Label = null
var _held: Label = null
var _crosshair: Control = null
## Through a scoped weapon at full aim: zee's circle and reticle (the gun is not drawn then).
var scope: ZeeScopeOverlay = null
## 0 at the hip to 1 down the sights, from the client's view model ([method set_aim]).
var aim_fraction: float = 0.0
var _scoped: bool = false
## Whether the host's dot-ui has `DotCrosshair.opacity_for_aim` (API 5).
var _fades: bool = DotAddonApi.build_level("dot_ui") >= 5
var _bile: ColorRect = null
## The black goo a spit leaves on the screen; stacks come from the server in `net_status`.
var _goo: DotFxScreenGoo = null
var _blind: ColorRect = null
var _flash: ColorRect = null
var _fire: ColorRect = null
var _grey: ColorRect = null
var _low: ColorRect = null
var _wet: ColorRect = null
var _air_back: ColorRect = null
var _air_fill: ColorRect = null
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
	# Eyes under water: a cold green-blue over everything, under the HUD (the fog does the depth).
	_wet = _cover("Wet", Color(0.04, 0.30, 0.40))
	_bile = _cover("Bile", Color(0.38, 0.52, 0.08))
	_fire = _cover("Fire", Color(0.95, 0.4, 0.05))
	_goo = DotFxScreenGoo.new()
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

	# The glance pieces read their colours from the theme on the type DotHudPiece; set on
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

	# Stamina, a thin bar right over the health plate; only drawn once it is below full.
	stamina_bar = DotStatBar.new()
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

	kits = DotKeyHints.new()
	kits.name = "Kits"
	kits.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	kits.offset_left = 24.0
	kits.offset_right = 24.0 + 300.0
	_root.add_child(kits)

	_status = DotStatusLines.new()
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
	ammo = DotAmmoCounter.new()
	ammo.name = "Ammo"
	ammo.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo.offset_left = -420.0
	ammo.offset_right = -24.0
	ammo.offset_top = -100.0
	ammo.offset_bottom = -24.0
	_root.add_child(ammo)

	_weapon_icon = DotWeaponIconPlate.new()
	_weapon_icon.name = "WeaponIcon"
	_weapon_icon.show_plate = false
	_weapon_icon.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_icon.offset_left = -310.0
	_weapon_icon.offset_right = -150.0
	_weapon_icon.offset_top = -96.0
	_weapon_icon.offset_bottom = -28.0
	_root.add_child(_weapon_icon)

	fire_mode = DotFireModeIndicator.new()
	fire_mode.name = "FireMode"
	fire_mode.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_mode.offset_left = -420.0
	fire_mode.offset_right = -24.0
	fire_mode.offset_top = -130.0
	fire_mode.offset_bottom = -104.0
	_root.add_child(fire_mode)

	# While the map's graph is built: above the ammunition.
	_nav_meter = ZzNavMeter.new()
	_root.add_child(_nav_meter)

	# What the boxes are doing, right side.
	_effects = DotStatusLines.new()
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
	# The breath, above the use bar's place; shown only while it is not full.
	_air_back = _rect(Color(0.0, 0.0, 0.0, 0.55), Control.PRESET_CENTER, -100.0, 96.0, 200.0, 8.0)
	_air_fill = _rect(Color(0.55, 0.85, 1.0), Control.PRESET_CENTER, -100.0, 96.0, 200.0, 8.0)
	_air_back.visible = false
	_air_fill.visible = false
	_carry = _label(16)
	_carry.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_carry.offset_left = -300.0
	_carry.offset_right = 300.0
	_carry.offset_top = -150.0
	_carry.offset_bottom = -126.0
	_carry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_use_label = _label(16)
	_use_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_use_label.offset_left = -300.0
	_use_label.offset_right = 300.0
	_use_label.offset_top = 88.0
	_use_label.offset_bottom = 112.0
	_use_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_weight = _label(15)
	_weight.name = "Weight"
	_weight.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_weight.offset_left = -330.0
	_weight.offset_right = -20.0
	_weight.offset_top = -240.0
	_weight.offset_bottom = -140.0
	_weight.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weight.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_weight.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weight_back = _rect(Color(0.0, 0.0, 0.0, 0.55), Control.PRESET_BOTTOM_RIGHT, -330.0, -136.0, 310.0, 8.0)
	_weight_fill = _rect(Color(0.55, 0.8, 0.4), Control.PRESET_BOTTOM_RIGHT, -330.0, -136.0, 0.0, 8.0)

	_held = _label(28)
	_held.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_held.offset_left = -500.0
	_held.offset_right = 500.0
	_held.offset_top = -120.0
	_held.offset_bottom = -80.0
	_held.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))

	# Full rect, centred on the crosshair; both draw only what the server confirmed.
	hit_fx = DotHitFeedback.mount(_root)
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
	# An outline rather than a panel: readable over a lamp-lit wall and the night alike. Its
	# colour and the words' are the menu's theme's (a Label under the root takes them), so a
	# player's theme reaches these lines; only the accent lines (a shout, the boxes) set their own.
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
	_effects_sig = 0


func set_prompt(text: String) -> void:
	if _prompt != null:
		_prompt.text = text


## A hit of this survivor's that the server confirmed: the marker round the crosshair, and
## the number rising off the body. Never called from the local prediction.
func confirm_hit(victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
	if hit_fx != null:
		hit_fx.confirm_hit(victim, amount, point, killed, headshot)


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
	return "Zombies arrive in %s" % DotScoreStrip.clock_text(ceilf(seconds))


## What the top says between a decided map and the next: `[title, clock, under the clock]`.
## Static, so a suite can read it without a screen.
static func next_round_lines(seconds: float, next_map: StringName, this_map: StringName, next_name: String) -> Array:
	var again := next_map == &"" or next_map == this_map
	return ["Trying again" if again else "Next: %s" % next_name, DotScoreStrip.clock_text(ceilf(seconds)),
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
		_set_status_sig(6 if downs_left <= 0 else 100 + downs_left)
	_status.show_lines(_status_lines)

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
	var plate_top := -PLATE_BOTTOM - 56.0
	kits.offset_bottom = plate_top - 4.0
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
	if player.medkits > 0:
		rows.append(["medkit x%d" % player.medkits, _kit_keys[0]])
	if player.pills > 0:
		rows.append(["pills x%d" % player.pills, _kit_keys[1]])
	if player.defibs > 0:
		rows.append(["defibrillator x%d" % player.defibs, _kit_keys[2]])
	return rows
var _build_status_lines: Callable = func(sig: int) -> Array:
	match sig:
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
	if _root != null and _root.has_theme_color(colour, DotHudPiece.THEME_TYPE):
		return _root.get_theme_color(colour, DotHudPiece.THEME_TYPE)
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


## The weight readout's words, rebuilt when [method set_carry] brings a new state.
var _weight_text: String = ""
var _weight_text_stale: bool = true
var _weight_text_fn: Callable = func() -> String:
	var carried := float(_weight_state.get("w", 0.0))
	var limit := maxf(float(_weight_state.get("l", 1.0)), 0.1)
	var lines := PackedStringArray()
	var slots: Dictionary = _weight_state.get("slots", {})
	var keys := slots.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key in keys:
		var names := PackedStringArray()
		for id: Variant in slots[key]:
			names.append(ZzWeapons.title_of(StringName(str(id))))
		if names.size() > 1:
			var rest := names.slice(1)
			lines.append("%s: [%s] %s" % [key, names[0], " ".join(rest)])
		else:
			lines.append("%s: %s" % [key, names[0]])
	var pack: String = " | pack %d" % int(_weight_state.get("tier", 0)) if int(_weight_state.get("max", 0)) > 0 else ""
	var slow: String = " | SLOWED" if float(_weight_state.get("scale", 1.0)) < 0.999 else ""
	return "%s\nweight %.1f / %.1f%s%s" % ["\n".join(lines), carried, limit, pack, slow]


## What the player carries (the CARRY event's document, or [method ZzCarry.state_json] offline).
func set_carry(state: Dictionary) -> void:
	_weight_state = state
	_weight_text_stale = true


func _draw_stamina() -> void:
	var s: DotFpsState = player.controller.state if player.controller != null else null
	var tunables: DotFpsTunables = player.controller.tunables if player.controller != null else null
	var shown := s != null and tunables != null and tunables.stamina_enabled and tunables.can_sprint \
		and player.is_alive() and (s.stamina < 0.999 or s.sprinting)
	stamina_bar.visible = shown
	if not shown:
		return
	stamina_bar.fill_colour = Color(0.9, 0.35, 0.25) if s.stamina_exhausted else Color(0.95, 0.8, 0.3)
	_stamina_pct = s.stamina * 100.0
	stamina_bar.refresh()


func _draw_weight() -> void:
	if _weight == null:
		return
	var on := bool(_weight_state.get("on", false)) and player.is_alive()
	_weight.visible = on
	_weight_back.visible = on
	_weight_fill.visible = on
	if not on:
		return
	var carried := float(_weight_state.get("w", 0.0))
	var limit := maxf(float(_weight_state.get("l", 1.0)), 0.1)
	var share := carried / limit
	var over := share > 1.0
	var colour := Color(1.0, 0.35, 0.3) if over else (AMBER if share > 0.8 else Color(0.55, 0.8, 0.4))
	_set_width(_weight_fill, 310.0 * minf(share, 1.0))
	_weight_fill.color = colour
	if _weight_text_stale:
		_weight_text_stale = false
		_weight_text = _weight_text_fn.call()
	_weight.text = _weight_text
	_weight.add_theme_color_override("font_color", colour)


const FIRE_NAMES := {DotWeaponDef.Fire.AUTO: &"auto", DotWeaponDef.Fire.SEMI: &"semi", DotWeaponDef.Fire.BURST: &"burst"}

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
		_weapon_icon.clear()
		return

	_offered.clear()
	for m in rig.arsenal.fire_modes_available():
		_offered.append(FIRE_NAMES.get(m, &""))
	fire_mode.show_modes(_offered, FIRE_NAMES.get(rig.arsenal.fire_mode(), &""))

	var slot := rig.arsenal.current()
	var title := ZzWeapons.title_of(slot.def.id)
	var sprite := ZzWeaponIcons.shared.texture(slot.def.id)
	_weapon_icon.show_icon(sprite, slot.def.id)

	if slot.def.magazine > 0:
		var reserve := rig.arsenal.ammo().count(slot.def.ammo_type) if slot.def.ammo_type != &"" else 0
		# Low at a quarter of a magazine: the reload worth starting before the crowd arrives.
		ammo.show_ammo(title, slot.magazine, reserve, float(slot.magazine) <= float(slot.def.magazine) * 0.25,
			slot.def.infinite_reserve)
	else:
		ammo.show_ammo(title, -1, -1)


const USE_TEXT := {&"revive": "Picking them up…", &"heal": "Healing…", &"pills": "Taking a pill — hold still…", &"loot": "Opening…", &"objective": "Working…", &"repair": "Mending the barricade…", &"defib": "Charging the defibrillator — hold still…", &"deploy": "Setting the box down — stay put and keep firing held…"}
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
	var text := ""

	if player.using != &"":
		fraction = player.use_fraction
		text = USE_TEXT.get(player.using, "")
	elif player.helped_fraction > 0.0:
		fraction = player.helped_fraction
		text = "Somebody is helping you…"

	_use_back.visible = fraction > 0.0
	_use_label.visible = fraction > 0.0
	_set_width(_use_fill, 320.0 * fraction)
	_use_fill.visible = fraction > 0.0
	_use_label.text = text

	if player.is_pinned():
		_held.text = HELD_TEXT.get(player.pin_kind, HELD_DEFAULT)
		_held.visible = true
	else:
		_held.visible = false


## The box slot: what is in the hands and the key that opens it. Without `box_labels` the type is
## not known to this end at all (`carried_index` is 0), so this says only "a box".
var _carry_sig: int = -1
var _carry_keys: Array = ["", ""]
var _carry_text_fn: Callable = func(id: StringName) -> String:
	var title := str(box_titles.get(id, "Box")) if id != &"" else "Unknown box"
	var more := " x%d" % player.carried_count if player.carried_count > 1 else ""
	if player.box_out:
		return "%s%s — hold %s to deploy (%s puts it away)" % [title, more, _carry_keys[0], _carry_keys[1]]
	return "%s%s — %s takes it out" % [title, more, _carry_keys[1]]


func _draw_carry() -> void:
	if _carry == null:
		return

	_carry.visible = player.carried_count > 0 and player.is_alive()

	if not _carry.visible:
		return

	var id: StringName = box_order[player.carried_index - 1] if player.carried_index > 0 and player.carried_index <= box_order.size() else &""
	var fire_key := _key(ZzBindings.FIRE)
	var box_key := _key(ZzBindings.BOX)
	var carry_sig := player.carried_index + (player.carried_count << 8) + ((1 << 20) if player.box_out else 0)
	if carry_sig != _carry_sig or fire_key != _carry_keys[0] or box_key != _carry_keys[1]:
		_carry_sig = carry_sig
		_carry_keys = [fire_key, box_key]
		_carry.text = _carry_text_fn.call(id)
	_carry.add_theme_color_override("font_color", (box_colours.get(id, Color(0.98, 0.84, 0.5)) as Color).lightened(0.2))
	# The meter pulses while it fills: the first-person cue that something is happening.
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
		lines.append({"text": DotStatusLines.effect_text(title, stacks, left if timed else -1.0), "colour": AMBER})

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


## The ring round the crosshair that fills while the use key is held over a dropped weapon (dot-ui API 18).
func set_hold_progress(fraction: float) -> void:
	if _crosshair != null and DotAddonApi.build_level("dot_ui") >= 18:
		_crosshair.set(&"hold_progress", fraction)


## dot-ui's spread crosshair where the host has it (API 10), else the old dot. Through Variants: named
## directly, an older dot-ui fails to compile this script.
func _make_crosshair() -> Control:
	if DotAddonApi.build_level("dot_ui") >= 10:
		var shape: Variant = DotCrosshair
		var cross := (shape as GDScript).new() as Control
		cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Dead or spectating: nothing in hand to aim (dot-ui API 14; older ones ignore the property).
		if DotAddonApi.build_level("dot_ui") >= 14:
			cross.set(&"alive_source", func() -> bool: return player != null and player.is_alive() and not player.watching)
		return cross

	var dot := ColorRect.new()
	dot.color = Color(1.0, 1.0, 1.0, 0.75)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.offset_left = -2.0
	dot.offset_top = -2.0
	dot.offset_right = 2.0
	dot.offset_bottom = 2.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return dot


## The crosshair control, for the feel's cl_crosshair_* binding.
func crosshair() -> Control:
	return _crosshair

## The weapon's spread cone in degrees, from the arsenal; the crosshair opens with it.
func set_spread(degrees: float, fov: float = 75.0, gap_scale: float = 1.0) -> void:
	if _crosshair != null and _crosshair.has_method(&"set_spread"):
		_crosshair.set(&"gap_scale", clampf(gap_scale, 0.1, 4.0))
		_crosshair.set(&"fov_degrees", clampf(fov, 10.0, 170.0))
		_crosshair.call(&"set_spread", degrees)


func _place(rect: ColorRect, at: Vector2, size: Vector2) -> void:
	rect.offset_left = at.x
	rect.offset_top = at.y
	rect.offset_right = at.x + size.x
	rect.offset_bottom = at.y + size.y


## The client's hands this frame: the scope follows their progressive fade-in and the crosshair gives way as it rises.
func follow_hands(hands: ZeeViewModel, camera: Camera3D = null) -> void:
	set_aim(hands.aim_fraction() if hands != null else 0.0, hands != null and hands.scope_fraction() > 0.0)
	if scope != null and hands != null:
		scope.follow(hands)
		# The lens view draws the zoom with a second camera that follows the player's and leaves the hands out.
		# Only for hands that keep the main camera at the hip in lens mode (`view_fov_scale`); an older
		# zee-weapons copy zooms the main camera, and a lens on top would zoom twice. By name, as the
		# overlay of such a copy has no `mode` either (ZzClient.scope_view_zoom has the story).
		var overlay: Object = scope
		if camera != null and hands.has_method(&"view_fov_scale") and "mode" in overlay and int(overlay.get(&"mode")) == 1 \
				and overlay.has_method(&"bind_camera"):
			overlay.call(&"bind_camera", camera, (1 << (hands.view_layer - 1)) if hands.view_layer > 0 else 0)


## The aim this frame: the dot fades as the gun comes up; [param scoped] hides it for the scope.
func set_aim(fraction: float, scoped: bool) -> void:
	aim_fraction = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0
	_scoped = scoped
	if scope != null:
		scope.fraction = aim_fraction if scoped else 0.0
	if _crosshair != null and _crosshair.has_method(&"set_aim"):
		_crosshair.call(&"set_aim", aim_fraction)
		_crosshair.set(&"suppressed", scoped)
	elif _crosshair != null:
		_crosshair.modulate.a = 0.0 if scoped else crosshair_opacity(aim_fraction)


## How much of the dot [param fraction] leaves: dot-ui's curve where the host has it, else the
## dot stays (an older shell had no aim to fade for).
func crosshair_opacity(fraction: float) -> float:
	if not _fades:
		return 1.0
	# Through a Variant: named directly, an older dot-ui without it fails to compile this script.
	var crosshair: Variant = DotCrosshair
	return float((crosshair as Script).call(&"opacity_for_aim", fraction))


func is_blind() -> bool:
	return player != null and is_instance_valid(player) and (player.blinded or player.box_blind)
