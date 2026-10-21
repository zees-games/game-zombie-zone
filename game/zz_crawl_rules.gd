extends RefCounted

## `zz_down_crawl_speed`: how fast a downed survivor crawls, in metres per second (0: stays put
## where they fell). A client predicts its own survivor's movement, and the crawl is the DOWN
## modifier's speed scale ([method ZzController.set_crawl_speed]), so both ends have to hold the
## same number or a downed player rubber-bands every tick: the cvar is REPLICATED and a client
## follows it. Shaped like [ZzPassRules].

signal changed

const CVAR := "zz_down_crawl_speed"

## Above this a "crawl" outruns a walk; the cvar and the config clamp to it.
const MAX_SPEED := 6.0

var speed: float = 1.4:
	set(value):
		var clamped := clampf(value, 0.0, MAX_SPEED)

		if is_equal_approx(clamped, speed):
			return

		speed = clamped
		changed.emit()


## Registers the cvar ([param add] is the module's `add_cvar`, taking flags as a fourth
## argument). [param flags] should carry REPLICATED.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Variant = add.call(CVAR, str(speed),
		"Metres per second a downed survivor crawls at (0: they stay where they fell, the way it was before crawling). Players follow it.", flags)

	if not (made is Object):
		return []

	var cv := made as Object

	if cv.has_signal(&"changed"):
		cv.connect(&"changed", func(_old: Variant, new_value: Variant) -> void: set_cvar(str(new_value)))

	if cv.has_method(&"get_string"):
		set_cvar(String(cv.call(&"get_string")))

	return [cv]


## Follows a server's value through its link; false for an older shell's link.
func follow_cvars(source: Object) -> bool:
	if source == null or not is_instance_valid(source):
		return false

	if not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false

	var held := String(source.call(&"replicated_cvar", CVAR, ""))

	if held != "":
		set_cvar(held)

	if not source.is_connected(&"replicated_cvar_changed", _on_replicated):
		source.connect(&"replicated_cvar_changed", _on_replicated)

	return true


func set_cvar(value: String) -> bool:
	var text := value.strip_edges()

	if not text.is_valid_float():
		return false

	speed = text.to_float()
	return true


func _on_replicated(cvar_name: String, value: String) -> void:
	if cvar_name == CVAR:
		var _set := set_cvar(value)


func describe() -> Dictionary:
	return {"down_crawl_speed": speed}
