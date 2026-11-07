extends RefCounted

## Per-weapon force on each kind of loose prop: a multiplier table (`props/forces.json`, rows weapon ids and `*`, columns toy kinds and `default`).
## Pure data so a server owner retunes it without code; the push itself is dot-props' [method DotPropToyBox.hit].

const PATH := "res://props/forces.json"

## weapon id (String) -> {kind (String) -> float}
var table: Dictionary = {}


## The shipped table, or an empty one (every multiplier 1.0) when the file is missing or malformed.
static func load_file(path: String = PATH) -> RefCounted:
	var force: RefCounted = (load("res://game/zz_prop_force.gd") as GDScript).new()
	if not FileAccess.file_exists(path):
		return force
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		force.set_table(parsed)
	return force


## Keeps the rows that are dictionaries of numbers; `comment` and anything else is dropped.
func set_table(source: Dictionary) -> void:
	table.clear()
	for weapon: Variant in source:
		var row: Variant = source[weapon]
		if not row is Dictionary:
			continue
		var clean := {}
		for kind: Variant in row:
			if typeof(row[kind]) in [TYPE_FLOAT, TYPE_INT]:
				clean[String(kind)] = maxf(float(row[kind]), 0.0)
		table[String(weapon)] = clean


## The multiplier for [param weapon_id] on a prop of [param kind]: the weapon's row (else `*`), the kind's column (else `default`, else 1).
func multiplier(weapon_id: StringName, kind: StringName) -> float:
	var row: Dictionary = table.get(String(weapon_id), table.get("*", {}))
	return float(row.get(String(kind), row.get("default", 1.0)))
