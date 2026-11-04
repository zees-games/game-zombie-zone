extends DotTouchButtons

const ZzBindings := preload("zz_bindings.gd")

## The survivor's actions as on-screen buttons: fire and aim large, the rest in a compact cluster.
##
## A button presses the same action its key is bound to ([InputEventAction]), so the client's one
## key path, the server's command bits and the rebinding all stay as they are.

## Offsets from the bottom-right corner (see [DotTouchButtons]). The top of the cluster stops under the Menu button.
const LAYOUT: Array[Dictionary] = [
	{"id": ZzBindings.FIRE, "label": "FIRE", "offset": Vector2(96, 100), "radius": 54.0},
	{"id": ZzBindings.AIM, "label": "AIM", "offset": Vector2(216, 84), "radius": 42.0},
	{"id": ZzBindings.RELOAD, "label": "R", "offset": Vector2(50, 200), "radius": 28.0},
	{"id": ZzBindings.USE, "label": "USE", "offset": Vector2(124, 200), "radius": 28.0},
	{"id": ZzBindings.HEAL, "label": "MED", "offset": Vector2(198, 200), "radius": 28.0},
	{"id": ZzBindings.FLASHLIGHT, "label": "LIGHT", "offset": Vector2(272, 200), "radius": 28.0},
	{"id": ZzBindings.FIRE_MODE, "label": "MODE", "offset": Vector2(50, 266), "radius": 28.0},
	{"id": ZzBindings.DROP, "label": "DROP", "offset": Vector2(124, 266), "radius": 28.0},
	{"id": ZzBindings.SHOVE, "label": "HIT", "offset": Vector2(198, 266), "radius": 28.0},
]

## How far the HUD's bottom-right readouts move left on a touch device, to clear the cluster.
const HUD_INSET := 350.0


func _init() -> void:
	name = "TouchButtons"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_buttons(LAYOUT)
	button_down.connect(_send.bind(true))
	button_up.connect(_send.bind(false))


## Every action the layout presses.
static func actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for b in LAYOUT:
		out.append(b["id"])
	return out


## A touch sampler on a touch device (it still reads keys), else the plain one.
static func new_sampler(tunables: DotFpsTunables) -> DotFpsSampler:
	if not DotPlatform.has_touch():
		return DotFpsSampler.new(tunables)
	return DotFpsTouchSampler.new(tunables)


## Sends a screen touch or drag to the sampler, which leaves the buttons' fingers alone.
func feed(event: InputEvent, sampler: DotFpsSampler) -> void:
	if not sampler is DotFpsTouchSampler:
		return
	var touch := sampler as DotFpsTouchSampler
	if touch.ignore_fn.is_null():
		touch.set_screen_width(get_viewport().get_visible_rect().size.x)
		touch.ignore_fn = contains_point
	touch.handle_event(event)


func _send(id: StringName, down: bool) -> void:
	var event := InputEventAction.new()
	event.action = id
	event.pressed = down
	Input.parse_input_event(event)
