extends "zz_box_effect.gd"

const ZzNpcs := preload("zz_npcs.gd")

## Instakill, the worked example of a named box: positive, game-wide, does not stack. While it
## lasts every common dies to one hit and a special (or a brute) takes `special_scale` times what
## the shot would have done.
##
## [b]Nothing here but the one hook.[/b] The duration, the stack rule, the HUD line and the end of
## the round are the registry's; this file only answers "what does this shot do". The common's
## one hit is an amount no health can survive, not a kill call, so the death goes through the
## same damage path as any other (the score, the drop chance, the body falling).


## The cvars `zz_box_instakill_min` and `_max` replace the file's range when they are not negative.
func duration(config, spec: Dictionary) -> Dictionary:
	var out := spec.duplicate()

	if config.box_instakill_min >= 0.0:
		out["min"] = config.box_instakill_min

	if config.box_instakill_max >= 0.0:
		out["max"] = config.box_instakill_max

	out["max"] = maxf(float(out.get("max", 0.0)), float(out.get("min", 0.0)))
	return out


func modify_zombie_damage(boxes, _fx: Dictionary, kind: StringName, max_health: float, amount: float) -> float:
	if kind == ZzNpcs.COMMON or kind == ZzNpcs.SLEEPER:
		return maxf(amount, max_health * 2.0 + 1.0)

	return amount * float(boxes.game.config.box_instakill_special_scale)
