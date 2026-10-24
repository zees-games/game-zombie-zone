extends RefCounted

## The creepy-ambience cvars (`zz_ambient*`). A server owner's choices (on/off, level, one-shot
## rate, a forced mood, an allowed list) are REPLICATED, so every player hears the server's
## intent; a player's own sliders multiply on top ([method ZzAudio.follow_settings]).
## `zz_ambient_dir` is a path on the machine that plays and is never replicated.

signal changed

## name, default, minimum, maximum (null: text), replicated, help. The key is the member that holds it.
const VARS := {
	"enabled": ["zz_ambient", 1.0, 0.0, 1.0, true,
		"The creepy ambience (quiet beds and distant sounds under the map): 1 on, 0 off."],
	"volume": ["zz_ambient_volume", 0.5, 0.0, 1.0, true,
		"Level of the ambience. 0.5 is the files' own quiet level."],
	"frequency": ["zz_ambient_frequency", 1.0, 0.0, 4.0, true,
		"How often the distant one-shots come: 1 normal, 2 twice as often, 0 none."],
	"mood": ["zz_ambient_mood", "", null, null, true,
		"Forces one mood on every map (outdoor_night, indoor_hall, industrial, cave_tunnel, snow_wind, swamp, city_ruins, interior_horror, or your own). Empty lets each map choose."],
	"allowed": ["zz_ambient_allowed", "", null, null, true,
		"Comma-separated moods a map may use; empty allows all."],
	"dir": ["zz_ambient_dir", "", null, null, false,
		"A directory with your own moods.json and sounds (docs/ambience.md); its moods replace the built-in ones of the same name."],
}

var enabled: float = 1.0
var volume: float = 0.5
var frequency: float = 1.0
var mood: String = ""
var allowed: String = ""
var dir: String = ""


func is_on() -> bool:
	return enabled >= 0.5


## Registers every cvar ([param add] is the module's `add_cvar`, taking flags as a fourth argument).
func bind_cvars(add: Callable, replicated_flags: int, flags: int) -> Array:
	var out: Array = []
	for key: String in VARS:
		var row: Array = VARS[key]
		var made: Variant = add.call(row[0], str(get(key)), row[5], replicated_flags if bool(row[4]) else flags)
		if not (made is Object):
			continue
		var cv := made as Object
		if cv.has_signal(&"changed"):
			cv.connect(&"changed", func(_old: Variant, new_value: Variant) -> void: set_cvar(row[0], str(new_value)))
		if cv.has_method(&"get_string"):
			set_cvar(row[0], String(cv.call(&"get_string")))
		out.append(cv)
	return out


## Follows the server's values through its link; false for an older shell's link.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false
	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	for key: String in VARS:
		var row: Array = VARS[key]
		if bool(row[4]) and source.has_method(&"replicated_cvar"):
			var held := String(source.call(&"replicated_cvar", row[0], ""))
			if held != "" or row[2] == null:
				set_cvar(row[0], held)
	if not source.is_connected(&"replicated_cvar_changed", _on_replicated):
		source.connect(&"replicated_cvar_changed", _on_replicated)
	return true


## Sets the member a cvar [param cvar_name] names; false for a name or value that is not one.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()
	for key: String in VARS:
		var row: Array = VARS[key]
		if row[0] != cvar_name:
			continue
		if row[2] == null:
			if str(get(key)) != text:
				set(key, text)
				changed.emit()
			return true
		if not text.is_valid_float():
			return false
		var clamped := clampf(text.to_float(), float(row[2]), float(row[3]))
		if not is_equal_approx(clamped, float(get(key))):
			set(key, clamped)
			changed.emit()
		return true
	return false


func _on_replicated(cvar_name: String, value: String) -> void:
	var _set := set_cvar(cvar_name, value)


func describe() -> Dictionary:
	var out := {}
	for key: String in VARS:
		out[key] = get(key)
	return out
