extends RefCounted

## The shared movement cvar names (`sv_runspeed`, `sv_gravity`, `sv_walkspeed`, `sv_airaccelerate`) over [ZzConfig], which stays the one source of truth.
##
## dot-game's `bind_movement_cvars` binds this through [method ZzGame.movement_targets]. zz builds a fresh `DotFpsTunables` per player from the config, so a write goes to the config and every player is re-tuned. Defaults are the config's own, so nothing changes until an operator sets one. `zz_gravity` and the config's other speeds are untouched.

const SOURCE_UNIT := 0.01905

## Shared name -> {field: the ZzConfig field, unit: the multiplier from the cvar's value to the field, min, max (the field's range)}.
const MAP := {
	"sv_runspeed": {"field": "run_speed", "unit": SOURCE_UNIT, "min": 1.0, "max": 20.0, "description": "Running speed, units/s"},
	"sv_gravity": {"field": "gravity", "unit": SOURCE_UNIT, "min": 1.0, "max": 100.0, "description": "Gravity, units/s^2"},
	"sv_walkspeed": {"field": "walk_speed_scale", "unit": 1.0, "min": 0.1, "max": 1.0, "description": "Walk speed, fraction of run"},
	"sv_airaccelerate": {"field": "air_accelerate", "unit": 1.0, "min": 0.0, "max": 200.0, "description": "Air acceleration"},
}

var game: Object = null


func _init(p_game: Object = null) -> void:
	game = p_game


func cvar_specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if game == null or game.get(&"config") == null:
		return out
	for shared: String in MAP:
		var entry: Dictionary = MAP[shared]
		var current := float(game.config.get(entry["field"]))
		out.append({
			"name": shared, "value": snappedf(current / float(entry["unit"]), 0.0001),
			"member": entry["field"], "description": entry["description"],
		})
	return out


## Writes the config field behind [param cvar_name] (clamped to the field's range) and re-tunes every player. False for an unknown name or a non-number.
func set_cvar(cvar_name: String, value: String) -> bool:
	if not MAP.has(cvar_name) or not value.strip_edges().is_valid_float() or game == null:
		return false
	var entry: Dictionary = MAP[cvar_name]
	var wanted := clampf(value.strip_edges().to_float() * float(entry["unit"]), float(entry["min"]), float(entry["max"]))
	if is_equal_approx(float(game.config.get(entry["field"])), wanted):
		return true
	game.config.set(entry["field"], wanted)
	for player: Variant in game.players.values():
		if player is Object and (player as Object).has_method(&"retune"):
			(player as Object).call(&"retune")
	return true
