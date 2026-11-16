extends RefCounted

## Zombie Zone's own copy (2026-11-16) of the grenade code first written for fc-weapons: the game depends on no FC addon.

## Who is blinded and for how long, on the server: one end time per victim, ticking down with the host's clock.
## A second flash extends a blind, never shortens it, and none passes [member max_seconds].

## Longest a victim stays blind however many flashes land.
var max_seconds := 10.0

var _now := 0.0
## victim id -> end time on [member _now]'s clock.
var _ends: Dictionary = {}
## victim id -> strongest blind of the current stretch, 0..1.
var _strengths: Dictionary = {}


## Blinds [param victim] for [param seconds] at [param strength] (0..1, how hard the flash hit); returns the seconds now left.
func blind(victim: int, seconds: float, strength: float = 1.0) -> float:
	_strengths[victim] = maxf(float(_strengths.get(victim, 0.0)), clampf(strength, 0.0, 1.0))
	var end := minf(_now + maxf(seconds, 0.0), _now + max_seconds)
	_ends[victim] = maxf(float(_ends.get(victim, 0.0)), end)
	return remaining(victim)


## Once per host tick; forgets whoever has come back.
func tick(delta: float) -> void:
	_now += delta
	for victim: int in _ends.keys():
		if float(_ends[victim]) <= _now:
			var _gone := _ends.erase(victim)
			var _s := _strengths.erase(victim)


## How hard [param victim] is blinded: the strongest flash of this stretch, 0 once it has ended. Never lowered by a weaker flash.
func strength(victim: int) -> float:
	return float(_strengths.get(victim, 0.0)) if is_blind(victim) else 0.0


func remaining(victim: int) -> float:
	return maxf(0.0, float(_ends.get(victim, 0.0)) - _now) if _ends.has(victim) else 0.0


func is_blind(victim: int) -> bool:
	return remaining(victim) > 0.0


## Lifts [param victim]'s blind (death, respawn).
func clear_victim(victim: int) -> void:
	var _gone := _ends.erase(victim)
	var _s := _strengths.erase(victim)


func count() -> int:
	return _ends.size()


func clear() -> void:
	_ends.clear()
	_strengths.clear()
