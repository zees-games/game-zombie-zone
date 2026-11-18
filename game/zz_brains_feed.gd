extends RefCounted
## The native brains' per-tick feed from the horde: its survivor table and chase rules, what `zz_common_brain.gd`'s
## `_chase_plan` reads instead of quarry, survivor_position, survivor_is and common_chase_speed.

const ZzNpcs := preload("zz_npcs.gd")
const ZzHordeState := preload("zz_horde_state.gd")


## Sets [code]brains_now[/code], [code]brains_crowd[/code], [code]brains_steer[/code] and [code]brains_barred[/code] on [param h] (a `ZzHorde`) for
## this tick, off its `_survivors` and the boxes, and hands the native brains the table and the rules.
static func feed(h: Object) -> void:
	var native: Object = h.brains_native
	h.brains_now = native
	h.brains_crowd = h.crowd if native != null and h.crowd_native else null
	h.brains_steer = native if native != null and native.has_method(&"steer_step") else null
	h.brains_barred = native if native != null and h._barricades_native == native \
			and h._barricades_reach == h.config.bash_reach else null

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

	# The spawner's repath tuning, which the stored walk (`walk_stored`) paths by.
	var sp: DotNpcSpawner = h.spawner
	if sp != null and native.has_method(&"set_repath"):
		native.call(&"set_repath", sp.repath_drift, sp.repath_interval, sp.repath_drift_ratio, sp.repath_interval_per_m)


## Drops [param h]'s per-tick brains once its spawner has ticked.
static func clear(h: Object) -> void:
	h.brains_now = null
	h.brains_crowd = null
	h.brains_steer = null
	h.brains_barred = null


## Hands [param h]'s native brains its intact barricades and their cells' size and reach, so the brains ask it
## ([code]brains_barred[/code]) instead of [code]barricade_in_way[/code]. A library without the table is not told;
## one that refuses it is an error, and the script answers.
static func push_barricades(h: Object) -> void:
	var native: Object = h.brains_native
	var config: Object = h.config
	h._barricades_native = null

	if native == null or not native.has_method(&"set_barricades") or config == null:
		return

	var ids := PackedStringArray()
	var at := PackedVector3Array()
	var size := PackedVector3Array()
	var barricades: Dictionary = h.barricades

	for id: String in barricades:
		var box: AABB = (barricades[id] as Dictionary)["bounds"]
		ids.append(id)
		at.append(box.position)
		size.append(box.size)

	if bool(native.call(&"set_barricades", ids, at, size, ZzHordeState.BARRICADE_CELL, config.bash_reach)):
		h._barricades_native = native
		h._barricades_reach = config.bash_reach
	else:
		push_error("ZzHorde: the native brains refused the barricades; the script answers")
