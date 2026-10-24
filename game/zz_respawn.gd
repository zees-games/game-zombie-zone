extends RefCounted
## When a dead survivor comes back. Pure functions of numbers, so a suite can check the formula.
##
## delay = (base + per_wave * (wave - 1)) * lerp(scarce, healthy, alive_fraction) * difficulty_scale
## clamped to [min, max]. alive_fraction is survivors up over survivors seated, the dead one
## excluded from both counts' numerator only (a lone survivor has fraction 1).


## Seconds a survivor who died now waits. `alive` and `seated` count the others in the team.
static func delay(config, wave: int, alive: int, seated: int) -> float:
	var fraction: float = 1.0 if seated <= 0 else clampf(float(alive) / float(seated), 0.0, 1.0)
	var scale: float = lerpf(config.respawn_scarce_scale, config.respawn_healthy_scale, fraction)
	var seconds: float = (config.respawn_base_seconds + config.respawn_per_wave_seconds * float(maxi(wave - 1, 0))) \
		* scale * difficulty_scale(config)
	return clampf(seconds, config.respawn_min_seconds, maxf(config.respawn_max_seconds, config.respawn_min_seconds))


## 1.0 at normal; `respawn_difficulty_step` more per step above it and less per step below.
static func difficulty_scale(config) -> float:
	return maxf(1.0 + config.respawn_difficulty_step * float(config.difficulty - 1), 0.1)
