extends CanvasLayer

const ZzGame := preload("zz_game.gd")

const ZzPlayer := preload("zz_player.gd")

const ZzBindings := preload("zz_bindings.gd")

const ZzMapDoc := preload("zz_map_doc.gd")

const ZzWeapons := preload("zz_weapons.gd")

const ZzWeaponIcons := preload("zz_weapon_icons.gd")

const ZzNavMeter := preload("zz_nav_meter.gd")

## What a survivor needs on screen, and nothing that would make a dark street less dark. [codeblock] bottom left your health: real health green, borrowed health white over it; down, a red bleed bar and how many downs are left; your medkit and pills left the team: each name, their health, and whether they are up, down, held or dead bottom right what you are holding and how much is in it top the objective, a hold-out's clock, a survival map's clock centre the crosshair, what E would do, the bar of what
## you are holding E for, and the bar of somebody picking you up right what the boxes are doing to the game, stacked ("Horde frenzy x4 1:12") over it all which way a hit came from; bile, a flash, fire, the last-life grey [/codeblock] [b]The keys are read from the bindings, not written here.[/b] Every prompt says the key the action is on NOW, from the same table the menu's Controls page edits. [b]The glance pieces are gs-ui's[/b]: health is a [GSVitals] (borrowed health as its `bonus`, DOWN and DEAD as
## its `status`), the weapon a [GSAmmoCounter] (an endless reserve as ∞), a hold-out's or a survival map's clock a [GSScoreStrip] under the title, the medkit and pills [GSKeyHints], and every hit the server confirms a [GSHitMarker] and a [GSDamageNumbers] number on the body. The number on the health plate is real health; the borrowed part is the white length after it, which drains, and a number that included it would fall on its own while nobody was hitting you.

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

## This game's accent over whichever theme the player picked: the boxes' amber as the glance pieces' highlight, the
## health bar's green as "good". The plates, words and outline are the theme's (dark by default), so a light or
## high-contrast theme can change them. Static so a render tool can use it.
static func piece_theme() -> Theme:
	var t := Theme.new()
	var type := GSHudPiece.THEME_TYPE
	t.set_color(&"highlight", type, AMBER)
	t.set_color(&"good", type, HEALTH_COLOUR)
	return t

## The Escape menu, whose theme this HUD follows (gs-menu's `follow_hud`): the menu sets the theme on the HUD's root now and at
## every theme change, and applies the player's HUD size. A play test asked for a darker HUD a player
## can restyle in the menu. Duck-typed and called by name, for a client shell older than gs-menu 7.
var _menu: Object = null

func follow_menu(menu: Object) -> void:
	_menu = menu
	_follow()

func _follow() -> void:
	if _root != null and _menu != null and _menu.has_method(&"follow_hud"):
		_menu.call(&"follow_hud", _root, piece_theme())

## The player's `cl_hud_show_<element>` switches (gs-ui's [GSHudElementCvars]; `cl_hud_scale` is
## the menu's own HUD size, so it is not registered). The pieces below are attached in [method _attach_elements].
var elements := GSHudElementCvars.new()

## element id -> the controls it hides; a piece that sets its own visibility each frame is put
## back to hidden after the draw (see [method _hold_hidden_elements]).
var _element_nodes: Dictionary = {}

func _attach_elements() -> void:
	var map := {
		&"vitals": [vitals, stamina_bar, kits],
		&"weapons": [loadout],
		&"ammo": [ammo],
		&"fire_mode": [fire_mode],
		&"teammates": [_team],
		&"wave": [strip],
		&"prompts": [_use_back, _use_fill, _held],
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
	for id: StringName in GSHudElementCvars.ELEMENTS:
		var name := GSHudElementCvars.cvar_name(id)
		local.call(&"add_var", StringName(name), String((GSHudElementCvars.ELEMENTS[id] as Array)[1]) + " (0 hides, 1 shows)",
			func() -> Variant: return "1" if elements.is_shown(id) else "0",
			func(v: Variant) -> Variant:
				if not elements.set_cvar(name, str(v)):
					return GSResult.fail(GSError.CODE_INVALID, "unreadable value: " + str(v))
				elements.apply()
				return null)

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
var vitals: GSVitals = null

## What is in hand and how much is in it.
var ammo: GSAmmoCounter = null

## The held gun's fire modes, above the ammunition.
var fire_mode: GSFireModeIndicator = null

## A hold-out's or a survival map's clock, under the title; nothing on a map without one.
var strip: GSScoreStrip = null

## The medkit and pills, each with its key.
var kits: GSKeyHints = null

var stamina_bar: GSStatBar = null

var _stamina_pct: float = 100.0

## Four ticks round the crosshair on a hit the server confirmed.
## The marker and numbers layer ([GSHitFeedback]); [member hit_marker] and
## [member damage_numbers] are its two pieces.
var hit_fx: GSHitFeedback = null

var hit_marker: GSHitMarker = null

## The confirmed hits' numbers, on the bodies they landed on.
var damage_numbers: GSDamageNumbers = null

var _status: GSStatusLines = null

var _nav_meter: PanelContainer = null

## The team, top left: a row per other survivor (name, a health bar, the number or DOWN /
## HELD / dead). The bar is drawn, not typed: as a row of block characters it came out as
## missing-glyph boxes on Windows, whose fallback fonts lack them (first play test).
var _team: Control = null

var _team_rows: Array[Dictionary] = []

var _effects: GSStatusLines = null

## The box file's order, titles and colours, set by the client: the carried slot is drawn from
## `player.carried_index` (an index into it plus one; 0 is unknown, or nothing carried).
var box_order: Array[StringName] = []

var box_titles: Dictionary = {}

var box_colours: Dictionary = {}

## The row of weapon slots and the weight bar over it (see [ZzLoadoutBar]).
var loadout: ZzLoadoutBar = null

var _weight_state: Dictionary = {"on": false}

var _use_back: ColorRect = null

var _use_fill: ColorRect = null

var _held: Label = null

var _crosshair: Control = null

## Through a scoped weapon at full aim: zee's circle and reticle (the gun is not drawn then).
var scope: ZeeScopeOverlay = null

## 0 at the hip to 1 down the sights, from the client's view model ([method set_aim]).
var aim_fraction: float = 0.0

var _scoped: bool = false

## Whether the host's gs-ui has `GSCrosshair.opacity_for_aim` (API 5).
var _fades: bool = GSAddonApi.build_level("gs_ui") >= 5

var _bile: ColorRect = null

## The black goo a spit leaves on the screen; stacks come from the server in `net_status`.
var _goo: GSFxScreenGoo = null

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

## Kept for the client's call; nothing is drawn. The "press E to ..." line was a box that said what a key does,
## and the owner had the HUD stop explaining itself.
func set_prompt(_text: String) -> void:
	pass

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
