extends RefCounted

## Every weapon this game can hand out, by tier, from every weapon pack it has.
##
## [b]The one file that knows where weapons come from.[/b] A box that gives "a heavy weapon", a
## map that leaves "a primary" on a table, and a rescue that hands back "a sidearm" all ask here
## by tier, so adding a second pack is adding it to [method all_defs] and nothing else in the
## game changes. Tiers are dot-weapon's tags (zee-dot-weapons' `TAG_*`), not a list written here:
## a weapon says what it is.

const TIERS: Array[StringName] = [&"sidearm", &"primary", &"heavy", &"melee", &"thrown"]

static var _defs: Array[DotWeaponDef] = []
static var _by_id: Dictionary = {}


## Puts the packs the server carries on zee's catalogue: zee-dot-weapons always, and
## zed-dot-weapons (the second pack) when [param second] is on. Called by the world before
## any rig is built, because a rig reads its catalogue once.
##
## [b]A second pack is one line here[/b] because zee builds every rig's catalogue, every world
## model's art and every report from its own tables, and `ZedWeaponPack.install()` adds to
## those (zee's `add_source`). Nothing else in the game names a pack.
static func use_packs(second: bool) -> void:
	if second:
		ZedWeaponPack.install()
	else:
		ZedWeaponPack.uninstall()

	_defs.clear()
	_by_id.clear()


## Every weapon from every pack, once.
static func all_defs() -> Array[DotWeaponDef]:
	if _defs.is_empty():
		for def in ZeeWeaponPack.weapons():
			_add(def)

	return _defs


static func _add(def: DotWeaponDef) -> void:
	if def == null or _by_id.has(def.id):
		return

	_defs.append(def)
	_by_id[def.id] = def


static func exists(id: StringName) -> bool:
	var _all := all_defs()
	return _by_id.has(id)


static func def_of(id: StringName) -> DotWeaponDef:
	var _all := all_defs()
	return _by_id.get(id)


## The weapons of [param tier] (`sidearm`, `primary`, `heavy`, `melee`, `thrown`). Fists are no
## weapon to find in a box.
static func ids_of(tier: StringName) -> Array[StringName]:
	var out: Array[StringName] = []

	for def in all_defs():
		if def.tags.has(tier) and def.id != &"fists":
			out.append(def.id)

	return out


static func random_of(tier: StringName, rng: RandomNumberGenerator) -> StringName:
	var ids := ids_of(tier) if tier != &"any" else _any()

	if ids.is_empty():
		return &"pistol"

	return ids[rng.randi_range(0, ids.size() - 1)]


static func _any() -> Array[StringName]:
	var out: Array[StringName] = []

	for tier in TIERS:
		out.append_array(ids_of(tier))

	return out


static func tier_of(id: StringName) -> StringName:
	var def := def_of(id)

	if def == null:
		return &""

	for tier in TIERS:
		if def.tags.has(tier):
			return tier

	return &""


static func title_of(id: StringName) -> String:
	var def := def_of(id)
	return def.display_name if def != null and def.display_name != "" else String(id).capitalize()
