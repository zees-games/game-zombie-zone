extends RefCounted

## The on-screen buttons of a phone: dot-ui's [DotTouchButtons] over the HUD, wired to the client's own
## buttons ([method ZzClient.touch_button]). The sampler's stick and look drag are dot-player-controller's
## [DotFpsTouchSampler]; this is only the buttons. Same shape as arena's, with this game's hands added.

const SelfScript := preload("zz_touch.gd")

## Offsets are from the bottom-right corner (see [DotTouchButtons]). Every radius is at least 24 so a
## button is 48 px across, thumb size, and the cluster still sits above the ammunition plate.
const LAYOUT: Array[Dictionary] = [
	{"id": &"fire", "label": "FIRE", "offset": Vector2(86, 150), "radius": 52.0},
	{"id": &"jump", "label": "JUMP", "offset": Vector2(200, 130), "radius": 42.0},
	{"id": &"crouch", "label": "DUCK", "offset": Vector2(60, 272), "radius": 36.0},
	{"id": &"reload", "label": "R", "offset": Vector2(170, 244), "radius": 36.0},
	{"id": &"next", "label": "NEXT", "offset": Vector2(268, 200), "radius": 36.0},
	{"id": &"use", "label": "USE", "offset": Vector2(290, 90), "radius": 36.0},
	{"id": &"heal", "label": "HEAL", "offset": Vector2(280, 300), "radius": 30.0},
]

var buttons: DotTouchButtons = null
var _client: Node = null
var _menu_button: Control = null


## Builds the buttons under [param host] (the HUD's screen) when the device has touch; null otherwise.
static func build(client: Node, host: Control, menu_button: Control = null) -> RefCounted:
	if not DotPlatform.has_touch():
		return null
	var made: RefCounted = (SelfScript as GDScript).new()
	made.call(&"_setup", client, host, menu_button)
	return made


func _setup(client: Node, host: Control, menu_button: Control) -> void:
	_client = client
	buttons = DotTouchButtons.new()
	buttons.name = "TouchButtons"
	buttons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.set_buttons(LAYOUT.duplicate())
	buttons.button_down.connect(func(id: StringName) -> void: client.call(&"touch_button", id, true))
	buttons.button_up.connect(func(id: StringName) -> void: client.call(&"touch_button", id, false))
	host.add_child(buttons)
	_menu_button = menu_button



## Whether [param at] is on a button or the menu button, so the sampler's look drag leaves it alone.
func covers(at: Vector2) -> bool:
	return buttons != null and (buttons.contains_point(at) or _menu_button != null and _menu_button.visible \
		and _menu_button.get_global_rect().has_point(at))


## Makes [param sampler] a touch sampler that ignores presses on the buttons, sized to [param width].
func attach(sampler: DotFpsSampler, width: float) -> void:
	if sampler is DotFpsTouchSampler:
		(sampler as DotFpsTouchSampler).ignore_fn = covers
		(sampler as DotFpsTouchSampler).set_screen_width(width)
