extends RefCounted

## `zz_pass_barricades`: whether survivors walk through a barricade instead of being stopped by
## it. The horde is held by a barricade either way, and a shot stops on it either way; only
## the people's own mask changes, which is why a client has to know it (it predicts its own
## player) and the cvar is REPLICATED. Shaped like dot-player-controller's `DotPlayerBodyRules`.

signal changed

const CVAR := "zz_pass_barricades"

var humans_pass: bool = true:
	set(value):
		if value == humans_pass:
			return
		humans_pass = value
		changed.emit()


## Registers the cvar ([param add] is the module's `add_cvar`, taking flags as a fourth
## argument). [param flags] should carry REPLICATED.
func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Variant = add.call(CVAR, "1" if humans_pass else "0",
		"1: survivors walk through barricades (and can go outside) without breaking them. 0: a barricade stops everybody; the horde is held either way.", flags)

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

	if not text.is_valid_int():
		return false

	humans_pass = text.to_int() != 0
	return true


func _on_replicated(cvar_name: String, value: String) -> void:
	if cvar_name == CVAR:
		var _set := set_cvar(value)


func describe() -> Dictionary:
	return {"humans_pass_barricades": humans_pass}
