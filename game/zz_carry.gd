extends RefCounted

## ZZ's carry-weight rules: one [DotWeaponCarry] (dot-weapon owns the logic) fed from `zz_weight_*` and from the boxes.
##
## The server's carry refuses and drops; a client's ([member mirror]) only stows several weapons
## per slot like the server, because the weights it shows come from the server's CARRY event.

const MODIFIER_PREFIX := "fx_"
## Weight by tier when no yml names the weapon.
const TIER_WEIGHT := {&"sidearm": 3.0, &"primary": 8.0, &"heavy": 14.0, &"melee": 2.0, &"thrown": 1.0}

var carry := DotWeaponCarry.new()

## A client's copy: stows several per slot, never refuses on weight.
var mirror: bool = false

var _signature: String = ""
var _prices := PackedInt32Array()


## Follows [param config] (and, on the server, [param boxes]); cheap to call every tick.
func sync(config: Object, boxes: Object = null) -> bool:
	var specs := parse_modifiers(String(config.get(&"weight_modifiers")))
	var parts: PackedStringArray = [
		str(config.get(&"weight_enabled")), str(config.get(&"weight_limit")), str(config.get(&"weight_multiplier")),
		str(config.get(&"weight_slot_capacity")), String(config.get(&"weight_over_limit")), str(config.get(&"weight_slow_floor")),
		String(config.get(&"weight_backpack_tiers")), String(config.get(&"weight_backpack_prices")),
	]
	var stacks := PackedStringArray()
	if boxes != null:
		for name: String in specs:
			stacks.append("%s%d" % [name, boxes.stacks_of(StringName(name))])
	var sig := "|".join(parts) + "#" + String(config.get(&"weight_modifiers")) + "#" + ",".join(stacks)
	if sig == _signature:
		return false
	_signature = sig

	carry.enabled = bool(config.get(&"weight_enabled")) and not mirror
	carry.base_limit = float(config.get(&"weight_limit"))
	carry.multiplier = float(config.get(&"weight_multiplier"))
	carry.slot_capacity = int(config.get(&"weight_slot_capacity")) if bool(config.get(&"weight_enabled")) else 1
	carry.over_limit = DotWeaponCarry.OverLimit.DROP if String(config.get(&"weight_over_limit")) == "drop" else DotWeaponCarry.OverLimit.SLOW
	carry.slow_floor = float(config.get(&"weight_slow_floor"))
	carry.backpack_tiers = parse_floats(String(config.get(&"weight_backpack_tiers")))
	_prices = PackedInt32Array()
	for v in parse_floats(String(config.get(&"weight_backpack_prices"))):
		_prices.append(int(v))
	for name: String in specs:
		var n: int = boxes.stacks_of(StringName(name)) if boxes != null else 0
		var key := StringName(MODIFIER_PREFIX + name)
		if n <= 0:
			carry.clear_modifier(key)
			continue
		var s: Array = specs[name]
		carry.set_modifier(key, pow(float(s[0]), n), pow(float(s[1]), n), float(s[2]) * n)
	for key in carry.modifiers():
		if not specs.has(String(key).trim_prefix(MODIFIER_PREFIX)):
			carry.clear_modifier(key)
	return true


## `a=1.2,b=1/0.8/-2` -> {a: [1.2, 1, 0], b: [1, 0.8, -2]}: weight factor, limit factor, limit addition, each per stack.
static func parse_modifiers(text: String) -> Dictionary:
	var out := {}
	for item in text.split(",", false):
		var pair := item.strip_edges().split("=", false)
		if pair.size() != 2:
			continue
		var nums := pair[1].split("/", false)
		var row := [1.0, 1.0, 0.0]
		for i in mini(nums.size(), 3):
			if nums[i].strip_edges().is_valid_float():
				row[i] = nums[i].strip_edges().to_float()
		out[pair[0].strip_edges()] = row
	return out


static func parse_floats(text: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for item in text.split(",", false):
		if item.strip_edges().is_valid_float():
			out.append(item.strip_edges().to_float())
	return out


## Price of backpack [param tier] in points; 0 when none is set.
func backpack_price(tier: int) -> int:
	return _prices[tier - 1] if tier >= 1 and tier <= _prices.size() else 0


# --- Weapon weights ------------------------------------------------------------

## Gives every def of [param catalogue] that no profile weighed (`weight:` in `cfg/addons/zee_weapons/weapon/<id>.yml`,
## which the workbench edits) the default of its tier.
func tune_catalogue(catalogue: DotWeaponCatalogue) -> void:
	for id in catalogue.ids():
		var def := catalogue.get_def(id)
		if def.weight <= 0.0:
			def.weight = default_weight(def)


static func default_weight(def: DotWeaponDef) -> float:
	for tier: StringName in TIER_WEIGHT:
		if def.tags.has(tier):
			return TIER_WEIGHT[tier]
	return 5.0


# --- What a player carries -----------------------------------------------------

## The owner's view, for the CARRY event and the HUD: weight, limit, backpack and the weapons by slot (in hand first).
func state_json(player: Object) -> String:
	var rig: Object = player.get(&"weapons")
	var arsenal: DotWeaponArsenal = rig.arsenal if rig != null else null
	if arsenal == null or not carry.enabled:
		return JSON.stringify({"on": false})
	var slots := {}
	for slot: int in arsenal.slots():
		var ids: Array = []
		for w in arsenal.weapons_in(slot):
			ids.append(String(w.id()))
		slots[str(slot)] = ids
	return JSON.stringify({
		"on": true, "w": snappedf(arsenal.carried_weight(), 0.1), "l": snappedf(arsenal.capacity(), 0.1),
		"tier": arsenal.backpack_tier, "max": carry.max_backpack_tier(), "scale": snappedf(arsenal.speed_scale(), 0.01),
		"cur": arsenal.current_slot(), "slots": slots,
	})
