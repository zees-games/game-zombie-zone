extends RefCounted

## The only server commands a map's `point_servercommand` may have run: a short list that maps onto
## this game's tunables. Everything else (a gravity change, a cvar that is not ours) is denied by dot-map and logged.

## Map cvar to `[tunable, scale]`: the value read is multiplied by scale.
const ALIASES := {
	"mp_friendlyfire": ["zz_friendly_fire", 1.0],
	"zz_friendly_fire": ["zz_friendly_fire", 1.0],
	"zz_difficulty": ["zz_difficulty", 1.0],
}


## The allow-list for [member DotMapIO.command_allow].
static func allow() -> PackedStringArray:
	return PackedStringArray(ALIASES.keys())


## `{key, value}` for an allowed command, or {} when [param name] maps to nothing or the value is out of range.
static func translate(name: String, args: String) -> Dictionary:
	if not ALIASES.has(name.to_lower()) or not args.strip_edges().is_valid_float():
		return {}
	var rule: Array = ALIASES[name.to_lower()]
	var limits: Dictionary = preload("zz_map_config.gd").KEYS.get(rule[0], {})
	var value := args.strip_edges().to_float() * float(rule[1])
	if limits.has("min"):
		value = maxf(value, float(limits["min"]))
	if limits.has("max"):
		value = minf(value, float(limits["max"]))
	return {"key": rule[0], "value": value}
