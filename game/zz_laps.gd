extends RefCounted

## Section timers for the cold start (tools/cold_start.gd): milliseconds by name, added to a dictionary
## the owner keeps. `lap` returns the new start, so a run of sections reads as one chain.

## Adds the time since [param since] (usec) to [param into][[param name]]; returns now (usec).
static func lap(into: Dictionary, name: StringName, since: int) -> int:
	var now := Time.get_ticks_usec()
	into[name] = snappedf(float(into.get(name, 0.0)) + float(now - since) / 1000.0, 0.1)
	return now
