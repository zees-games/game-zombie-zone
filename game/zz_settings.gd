extends DotMenuGameSettings

const ZzBindings := preload("zz_bindings.gd")

## A player's own settings and the menu that changes them: how fast the view turns, how wide
## it is, how loud things are, the window, and the look of the menu itself.
##
## [codeblock]
## var settings := ZzSettings.new()
## add_child(settings)
## settings.setup()                    # loads, and pushes every value at what reads it
## settings.bind_look(sampler.tunables)
## settings.bind_camera(camera)
## settings.bind_audio(audio.manager)
## settings.open()                     # Escape does this in the client
## [/codeblock]
##
## [b]dot-menu's `DotMenuGameSettings` with this game's spec[/b] (2026-11-07). It was a 250-line
## copy of mg-wipeout's file, then a [DotMenuSettings] subclass; what is left is the spec: where the
## document lives, its extra settings and rows, the view transform, the v1 migration and the help text.
##
## [b]The scopes are the family's, not this game's.[/b] `sensitivity` is ACCOUNT under the
## shared `tmc_account` namespace — a person's hand, the same number in every game here.
## `field_of_view` is SERVER_CLAMPED: a wide view is an advantage a server may cap, and
## dot-settings gives a server no way to READ it. The volumes are this machine's.

const SCHEMA_VERSION := 2

## Where this game's own document lives. The shared account document is dot-settings'.
const SETTINGS_DIR := "user://zombiezone_settings"

## The app's namespace. ACCOUNT settings are shared under dot-menu's `tmc_account`.
const APP_NAMESPACE := &"zombiezone"

## Horizontal degrees on a 4:3 frame (the family's measure), about 100 across a 16:9 window.
## The old 92 went to the camera as the vertical angle: 120 across 16:9, a fisheye.
const DEFAULT_FOV := 85

## Stock keys nothing here applies: every sound is on the SFX bus, the client binds no
## effects, and the chat box has no switch.
const NOT_APPLIED: Array[StringName] = [
	&"ui_volume", &"shake_scale", &"allow_flashes", &"chat_window",
]


func _init() -> void:
	super(spec_for())


## The document's schema, as the spec declares it.
static func schema_for() -> DotSettingsSchema:
	return spec_for().make_schema()


## The game's settings as data. Help and Leave are dot-menu's stock: H opens help, Leave leaves the server or quits a solo game.
static func spec_for() -> DotMenuGameSpec:
	var s := DotMenuGameSpec.new()
	s.schema_version = SCHEMA_VERSION
	s.brand_name = "Zombie Zone"
	s.settings_dir = SETTINGS_DIR
	s.app_namespace = APP_NAMESPACE
	s.default_fov = DEFAULT_FOV
	s.reduce_motion_text = "The end-of-map announcement appears at once, with nothing sliding, rising or bursting."
	s.comfort_row_text = "The end-of-map announcement appears at once."
	s.gore_text = "Blood splatters on the surface behind a zombie or survivor you hit."
	s.ambient_text = "The quiet creepy sounds under a map: beds and distant one-shots."
	s.not_applied = NOT_APPLIED
	s.bindings_maker = func() -> DotMenuBindings: return ZzBindings.make()
	s.extra_defs = [
		DotSettingsDef.integer(&"crowd_detail", 1, 0, 2, &"video").with_description(
			"How near a zombie must be to be animated every frame, cast a shadow and be drawn at all."),
		DotSettingsDef.integer(&"vis_mode", 3, 0, 3, &"video").with_description(
			"Which hidden parts of a map are skipped when drawing: none, by precomputed visibility, by occluders, or both."),
	]
	s.late_defs = [DotSettingsDef.number(&"ambient_frequency", 1.0, 0.0, 2.0, &"audio")]
	s.extra_rows = [
		[&"video", "Image", DotMenuRow.select(&"crowd_detail", "Crowd detail",
			"Low animates, shadows and draws far zombies less: faster in a big horde.",
			[[0, "Low"], [1, "Normal"], [2, "High"]])],
		[&"video", "Image", DotMenuRow.select(&"vis_mode", "Map culling",
			"Skips the parts of a map you cannot see. Off draws everything (slower, for checking).",
			[[0, "Off"], [1, "Precomputed"], [2, "Occluders"], [3, "Both"]])],
		[&"audio", "Ambience", DotMenuRow.toggle(&"ambient", "Creepy ambience", "Quiet beds and distant sounds under the map.")],
		[&"audio", "Ambience", DotMenuRow.slider(&"ambient_volume", "Ambience volume", "Turns the server's level down; it cannot turn it up.")],
		[&"audio", "Ambience", DotMenuRow.slider(&"ambient_frequency", "Distant sounds", "How often the one-shots come.")],
	]
	# v1 stored the vertical angle; a stored value would now mean a different view.
	s.migrations = {1: func(doc: Dictionary) -> Dictionary:
		doc.erase("field_of_view")
		return doc}
	s.fov_transform = DotMenuApplier.vertical_from_horizontal_4_3
	s.help_about = "Get the team from the shelter at the start to the one at the end, or hold a survival map through its waves. Stay together: the specials go for whoever is alone."
	s.help_sections = [
		["Maps", ["An exodus map is crossed shelter to shelter, opening gates and finishing objectives on the way. A survival map is held where you start: by default ten waves, each bigger than the last, with a breather between in which the downed get up, the dead come back and the caches restock. Hold Use on a damaged door or window to mend it, or to rebuild one that is down."], &"text"],
		["Staying alive", ["At no health you go down, not out: a friend holds Use on you to get you up. After two downs the next one is death, and the dead are rescued beside the team a little later. Pills and revives give borrowed health, the white part of the bar, which drains away. Friendly fire is on."], &"text"],
		["Mouse", [["Left", "Fire"], ["Right", "Shove"], ["Wheel", "Next or previous weapon"]], &"keys"],
		["Boxes", ["Zombies sometimes drop a box. Open it with Use and something random happens to you, your team or the horde; the HUD lists what is still in effect."], &"text"],
	]
	return s
