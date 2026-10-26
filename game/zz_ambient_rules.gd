extends DotAmbienceRules

## The `zz_ambient*` cvars: dot-audio's rules under this game's prefix.


func _init() -> void:
	prefix = "zz"


## The cvars a workbench set offers: name -> profile type.
func cvar_types() -> Dictionary:
	var out := {}
	for key: String in VARS:
		var row: Array = VARS[key]
		out[cvar_of(row)] = "string" if row[2] == null else "float"
	return out
