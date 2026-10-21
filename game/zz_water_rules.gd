extends RefCounted

## The water cvars (`zz_water*`): how a survivor wades and swims, how long they hold their
## breath, and how the horde wades. Source-like defaults, every one a server setting.
##
## [b]Two kinds, and the split is what a prediction needs.[/b] The movement ones (`zz_water`,
## `zz_water_wade_scale`, `zz_water_swim_speed`) are part of the predicted motor: a client that
## held a different swim speed would rubber-band every tick in a pool, so they are REPLICATED and
## a client follows them ([method follow_cvars]), the way [ZzCrawlRules] does for the crawl. The
## rest (breath, drowning, the horde's pace) only the server acts on and are plain server cvars.
## One class and a table, not a rules class per number: the set changes together and a map that
## wants to retune the water wants all of it.

signal changed

## name, default, minimum, maximum, replicated, help. The key is the member that holds it.
const VARS := {
	"enabled": ["zz_water", 1.0, 0.0, 1.0, true,
		"Whether a map's water volumes are water at all (1) or only a picture (0). Players follow it."],
	"wade_scale": ["zz_water_wade_scale", 0.8, 0.2, 1.0, true,
		"Speed scale for a survivor with the feet in water below the waist. Players follow it."],
	"swim_speed": ["zz_water_swim_speed", 4.4, 1.0, 12.0, true,
		"Metres per second a survivor swims at, once the waist is in the water. Players follow it."],
	"drown_seconds": ["zz_water_drown_seconds", 12.0, 0.0, 120.0, false,
		"Seconds a survivor holds their breath with the eyes under water before they start to drown (0: never)."],
	"drown_damage": ["zz_water_drown_damage", 5.0, 0.0, 100.0, false,
		"Health a drowning survivor loses each second."],
	"air_refill": ["zz_water_air_refill", 3.0, 0.1, 30.0, false,
		"Seconds of breath regained for each second with the head out of the water."],
	"zombie_wade": ["zz_water_zombie_scale", 0.6, 0.1, 1.0, false,
		"Speed scale for a zombie with the feet in water below the waist."],
	"zombie_deep": ["zz_water_zombie_deep_scale", 0.4, 0.1, 1.0, false,
		"Speed scale for a zombie with the waist in water (wading chest deep)."],
}

var enabled: float = 1.0
var wade_scale: float = 0.8
var swim_speed: float = 4.4
var drown_seconds: float = 12.0
var drown_damage: float = 5.0
var air_refill: float = 3.0
var zombie_wade: float = 0.6
var zombie_deep: float = 0.4


func is_on() -> bool:
	return enabled >= 0.5


## Registers every cvar ([param add] is the module's `add_cvar`, taking flags as a fourth
## argument). [param replicated_flags] is what the movement ones carry (REPLICATED included),
## [param flags] what the server-only ones do.
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


## Follows the server's movement values through its link; false for an older shell's link.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false

	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false

	for key: String in VARS:
		var row: Array = VARS[key]

		if not bool(row[4]):
			continue

		var held := String(source.call(&"replicated_cvar", row[0], ""))

		if held != "":
			set_cvar(row[0], held)

	if not source.is_connected(&"replicated_cvar_changed", _on_replicated):
		source.connect(&"replicated_cvar_changed", _on_replicated)

	return true


## Sets the member a cvar [param cvar_name] names; false for a name or a value that is not one.
func set_cvar(cvar_name: String, value: String) -> bool:
	var text := value.strip_edges()

	if not text.is_valid_float():
		return false

	for key: String in VARS:
		var row: Array = VARS[key]

		if row[0] != cvar_name:
			continue

		var clamped := clampf(text.to_float(), float(row[2]), float(row[3]))

		if is_equal_approx(clamped, float(get(key))):
			return true

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
