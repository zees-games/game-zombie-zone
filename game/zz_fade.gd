extends RefCounted

## How see-through a zombie is drawn at the Hard Box stacks now on (`zz_mutant_fade*`, `zz_common_fade`).
## Pure arithmetic, shared by the client's view and the checks; no class_name (a pack cannot register one).

## Never fully invisible, whatever the cvar says: a mutant that cannot be seen cannot be fought.
const FLOOR := 0.05


## Alpha 1 (solid) down to the configured floor. [param c] is a ZzConfig.
static func alpha(c: Object, kind: StringName, stacks: int) -> float:
	if int(c.get(&"mutant_fade")) != 1:
		return 1.0

	if kind == &"common" and int(c.get(&"common_fade")) != 1:
		return 1.0

	var floor_alpha := clampf(float(c.get(&"mutant_min_alpha")), FLOOR, 1.0)
	var step := maxf(float(c.get(&"mutant_fade_per_stack")), 0.0)
	return clampf(1.0 - float(maxi(stacks, 0)) * step, floor_alpha, 1.0)
