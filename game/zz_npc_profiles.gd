extends RefCounted

## The twelve kinds' numbers as dot-npc profiles (`cfg/game/game-zombie-zone/npc/<id>.yml`).
##
## The code table in zz_npcs.gd is the floor and the source of the shipped files
## (tools/export_npc_profiles.gd; the packs suite fails when they are stale). A profile key
## overrides only when it differs from that shipped value, so a cvar or the difficulty still
## reaches a kind whose file was never edited; a value equal to the schema default counts as unstated. `health` is the unscaled number (the special
## health scale multiplies it); a brute's is its base, before the per-survivor share.

const ZzCues := preload("zz_cues.gd")

const CHANNEL := "zz.npc_profiles"
const GAME := "game-zombie-zone"
const DIR := "res://cfg/game/game-zombie-zone/npc"
## The sleeper costs nothing, which the schema (minimum 1) cannot say, so its cost stays in code.
const COST_IN_CODE: Array[StringName] = [&"sleeper"]


static func make_set(roots: PackedStringArray = PackedStringArray()) -> DotProfileSet:
	return DotNpcProfiles.make_set(GAME, roots)


## Lays the profile of [param def] over it; [param base] is the same kind built from default
## config, [param base_config] that config. Returns true when a profile file existed.
static func overlay(def: DotNpcDef, base: DotNpcDef, c: RefCounted, base_config: RefCounted, set: DotProfileSet) -> bool:
	if not set.has_id(String(def.id)):
		return false
	var res := set.load_profile(String(def.id))
	if not res.ok:
		DotLog.error(CHANNEL, "npc profile skipped", {"id": String(def.id), "why": res.error.message})
		return false
	var p: DotProfile = res.value
	var scale := _scale(def.id, c)
	var base_health := unscaled_health(base, base_config)
	_set_if(p, "name", base.display_name, func(v: Variant) -> void: def.display_name = str(v))
	_set_if(p, "category", String(base.category), func(v: Variant) -> void: def.category = StringName(str(v)))
	_set_if(p, "faction", String(base.faction), func(v: Variant) -> void: def.faction = StringName(str(v)))
	_set_if(p, "weight", weight_name(base.weight), func(v: Variant) -> void:
		def.weight = maxi(DotNpcDef.Weight.keys().find(str(v).to_upper()), 0) as DotNpcDef.Weight)
	if not COST_IN_CODE.has(def.id):
		_set_if(p, "cost", base.cost, func(v: Variant) -> void: def.cost = int(v))
	_set_if(p, "health", base_health, func(v: Variant) -> void:
		def.max_health = float(v) * scale
		if def.id == &"brute":
			def.meta["brute_health"] = float(v))
	_set_if(p, "speed", base.move_speed, func(v: Variant) -> void: def.move_speed = float(v))
	_set_if(p, "sight", base.sight_range, func(v: Variant) -> void: def.sight_range = float(v))
	_set_if(p, "sight_angle", base.sight_half_angle_deg, func(v: Variant) -> void: def.sight_half_angle_deg = float(v))
	_set_if(p, "hearing", base.hearing_range, func(v: Variant) -> void: def.hearing_range = float(v))
	_set_if(p, "los", base.require_line_of_sight, func(v: Variant) -> void: def.require_line_of_sight = bool(v))
	for key: String in p.extra:
		# Cues are ZzAudio's, read from the profile; they are not the body's numbers.
		if key.begins_with("cue_"):
			continue
		if not base.meta.has(key) or _differs(p.extra[key], base.meta[key]):
			def.meta[key] = p.extra[key]
	# The eye follows the body's height unless the file states one.
	def.eye_height = float(def.meta.get("height", 1.75)) * 0.9
	_set_if(p, "eye", base.eye_height, func(v: Variant) -> void: def.eye_height = float(v))
	return true


## A kind's health before the special scale (a brute's: before the per-survivor share too).
static func unscaled_health(def: DotNpcDef, c: RefCounted) -> float:
	if def.id == &"brute":
		return float(def.meta.get("brute_health", c.get("brute_health")))
	return def.max_health / _scale(def.id, c)


static func weight_name(w: int) -> String:
	return String(DotNpcDef.Weight.keys()[w]).to_lower()


static func yaml_of(def: DotNpcDef, c: RefCounted) -> String:
	var lines := PackedStringArray([
		"name: %s" % def.display_name, "category: %s" % def.category, "faction: %s" % def.faction,
		"weight: %s" % weight_name(def.weight), "cost: %d" % maxi(def.cost, 1),
		"health: %s" % _num(unscaled_health(def, c)), "speed: %s" % _num(def.move_speed),
		"sight: %s" % _num(def.sight_range), "sight_angle: %s" % _num(def.sight_half_angle_deg),
		"hearing: %s" % _num(def.hearing_range), "los: %s" % str(def.require_line_of_sight).to_lower(),
		"eye: %s" % _num(def.eye_height), "extra:"])
	for key: String in def.meta:
		var v: Variant = def.meta[key]
		lines.append("  %s: %s" % [key, _num(v) if typeof(v) in [TYPE_FLOAT, TYPE_INT] else str(v)])
	var cues: Dictionary = ZzCues.of(def.id)
	for key: String in ZzCues.KEYS:
		if cues.has(key):
			lines.append("  cue_%s: %s" % [key, cues[key]])
	return "\n".join(lines) + "\n"


static func _scale(id: StringName, c: RefCounted) -> float:
	return 1.0 if id == &"common" else float(c.call("special_health_scale"))


static func _num(v: Variant) -> String:
	return String.num(float(v), 4) if typeof(v) == TYPE_FLOAT else str(v)


static func _differs(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return not is_equal_approx(float(a), float(b))
	return a != b


static func _set_if(p: DotProfile, key: String, base_value: Variant, apply: Callable) -> void:
	var v: Variant = p.get_value(key)
	if v != null and _differs(v, base_value) and _differs(v, _schema_default(key)):
		apply.call(v)


## A value equal to the schema default counts as unstated, so a file naming one key leaves the rest to the code.
static func _schema_default(key: String) -> Variant:
	for f: Dictionary in DotNpcProfiles.schema():
		if f["name"] == key:
			return f["default"]
	return null
