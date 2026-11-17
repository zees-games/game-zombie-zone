extends RefCounted
## The native brains' per-tick feed from the horde: its survivor table and chase rules, what `zz_common_brain.gd`'s
## `_chase_plan` reads instead of quarry, survivor_position, survivor_is and common_chase_speed.

const ZzNpcs := preload("zz_npcs.gd")


## Sets [code]brains_now[/code], [code]brains_crowd[/code] and [code]brains_steer[/code] on [param h] (a `ZzHorde`) for
## this tick, off its `_survivors` and the boxes, and hands the native brains the table and the rules.
static func feed(h: Object) -> void:
	var native: Object = h.brains_native
	h.brains_now = native
	h.brains_crowd = h.crowd if native != null and h.crowd_native else null
	h.brains_steer = native if native != null and native.has_method(&"steer_step") else null

	if native == null:
		return

	h._brain_ids.clear()
	h._brain_at.clear()
	h._brain_flags.clear()

	for id: StringName in h._survivors:
		var facts: Dictionary = h._survivors[id]
		h._brain_ids.append(id)
		h._brain_at.append(facts["position"])
		h._brain_flags.append((1 if bool(facts["alive"]) else 0) | (2 if bool(facts.get("down", false)) else 0))

	if not bool(native.call(&"set_survivors", h._brain_ids, h._brain_at, h._brain_flags)):
		h.brains_now = null
		h.brains_steer = null
		return

	var game: Object = h.game
	var config: Object = h.config
	var stacks: int = h.hard_stacks()
	var angry: bool = game != null and game.boxes != null and game.boxes.is_active(&"angry")
	var down_attack: bool = game != null and bool(game.config.down_attack)
	native.call(&"set_rules", ZzNpcs.common_chase_speed(config, stacks, false),
		ZzNpcs.common_chase_speed(config, stacks, true), angry, config.angry_runner_fraction, down_attack)
