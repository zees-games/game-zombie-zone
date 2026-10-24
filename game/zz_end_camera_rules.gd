extends RefCounted

## The map-ending camera cvars (`zz_end_camera*`). A viewer's own taste, so they are archived but never replicated.

## name, default, minimum, maximum, help. The key is the member that holds it.
const VARS := {
	"enabled": ["zz_end_camera", 1.0, 0.0, 1.0,
		"A map's ending (logic_winlose with a camera point) takes the view to that point, looking at you: 1 on, 0 keeps your own eyes."],
	"orbit": ["zz_end_camera_orbit", 10.0, -90.0, 90.0,
		"Degrees per second the ending camera circles you; 0 holds it at the map's point."],
	"blend": ["zz_end_camera_blend", 0.6, 0.05, 3.0,
		"Seconds the view takes to glide to the ending camera and back."],
	"window": ["zz_end_camera_seconds", 3.0, 0.5, 20.0,
		"Seconds the ending camera stays when the map did not say how long its ending lasts."],
}

var enabled: float = 1.0
var orbit: float = 10.0
var blend: float = 0.6
var window: float = 3.0


func is_on() -> bool:
	return enabled >= 0.5


## Registers every cvar ([param add] is the module's `add_cvar`, taking flags as a fourth argument).
func bind_cvars(add: Callable, flags: int) -> Array:
	var out: Array = []
	for key: String in VARS:
		var row: Array = VARS[key]
		var made: Variant = add.call(row[0], str(get(key)), row[4], flags)
		if not (made is Object):
			continue
		var cv := made as Object
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", func(_old: Variant, new_value: Variant) -> void: var _ok := set_cvar(row[0], str(new_value)))
		if cv.has_method(&"get_string"):
			var _loaded := set_cvar(row[0], String(cv.call(&"get_string")))
		out.append(cv)
	return out


## Sets the member a cvar [param cvar_name] names, clamped; false for a name or value that is not one.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	for key: String in VARS:
		var row: Array = VARS[key]
		if row[0] != cvar_name:
			continue
		if not text.is_valid_float():
			return false
		set(key, clampf(text.to_float(), float(row[2]), float(row[3])))
		return true
	return false


func describe() -> Dictionary:
	var out := {}
	for key: String in VARS:
		out[key] = get(key)
	return out
