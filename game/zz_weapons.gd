extends RefCounted

## Every weapon this game can hand out, by tier, from every weapon pack it has.
##
## [b]The one file that knows where weapons come from.[/b] A box that gives "a heavy weapon", a
## map that leaves "a primary" on a table, and a rescue that hands back "a sidearm" all ask here
## by tier, so adding a second pack is adding it to [method all_defs] and nothing else in the
## game changes. Tiers are dot-weapon's tags (zee-dot-weapons' `TAG_*`), not a list written here:
## a weapon says what it is.

const TIERS: Array[StringName] = [&"sidearm", &"primary", &"heavy", &"melee", &"thrown"]

const ZzPackList := preload("zz_packs.gd")

## zee-dot-weapons' own catalogue, the toy-looking blasters and tools the game shipped with. They stay in
## the rigs' catalogue (an old save, `arm`, a console command still name them) but are offered nowhere
## (boxes, loot, caches, spawners, shop, stand-ins) unless `weapons.legacy` is on in packs.yml.
## Maps to the modern pack's weapon that takes the old one's place when an old id is named by data.
const LEGACY := {
	&"knife": &"zz_knife", &"shiv": &"zz_knife", &"hatchet": &"zz_knife", &"mallet": &"zz_knife",
	&"pickaxe": &"zz_knife", &"spade": &"zz_knife",
	&"pistol": &"zz_pistol", &"revolver": &"zz_revolver", &"machine_pistol": &"zz_smg", &"derringer": &"zz_pistol",
	&"smg": &"zz_smg", &"carbine": &"zz_m4", &"rifle": &"zz_m4", &"bullpup": &"zz_m4",
	&"battle_rifle": &"zz_dmr", &"burst_rifle": &"zz_m4", &"shotgun": &"zz_shotgun", &"drum_shotgun": &"zz_spas",
	&"marksman": &"zz_dmr", &"sniper": &"zz_sniper", &"minigun": &"zz_lmg", &"launcher": &"zz_m79",
	&"beamer": &"zz_vss", &"charge_rifle": &"zz_vss", &"frag": &"zz_frag", &"sticky": &"zz_frag",
}
const MODERN_PACK := "zz_modern_weapons"

## The survival wave in play (0 outside a hold); `weapons.min_wave` holds a heavy weapon back until then.
static var wave: int = 0

static var _defs: Array[DotWeaponDef] = []
static var _by_id: Dictionary = {}
static var _zed_ids: Dictionary = {}


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


## Whether [param id] may be handed out by a pool: a legacy blaster, zed gun or other pack's weapon only with `weapons.legacy` on,
## or when the modern pack is not installed (a checkout without it still has to play).
static func offered(id: StringName) -> bool:
	if not _is_older(id):
		return true

	return bool(ZzPackList.cfg("weapons.legacy", false)) or not ZzPackList.providers.has(MODERN_PACK)


## Zee's blasters, zed-dot-weapons' guns and every non-modern provider's weapons (the medieval pack).
static func _is_older(id: StringName) -> bool:
	if LEGACY.has(id):
		return true

	if ZzPackList.pack_of.has(String(id)):
		return ZzPackList.pack_of[String(id)] != MODERN_PACK

	if _zed_ids.is_empty() and ZedWeaponPack.installed():
		for def in ZedWeaponPack.weapons({}, false):
			_zed_ids[def.id] = true

	return _zed_ids.has(id)


## The weapon an id from data (a box row, a map's pickup, a shop item) stands for: a legacy id becomes
## its modern successor while legacy is off, anything else is returned as it came.
static func resolve(id: StringName) -> StringName:
	if LEGACY.has(id) and not offered(id) and exists(LEGACY[id]):
		return LEGACY[id]

	# A checkout without the modern pack: its ids fall back to the blasters they replace.
	if not exists(id) and LEGACY.values().has(id):
		for old: StringName in LEGACY:
			if LEGACY[old] == id and exists(old):
				return old

	return id


## [method all_defs] without the legacy blasters when they are not offered.
static func offered_defs() -> Array[DotWeaponDef]:
	var out: Array[DotWeaponDef] = []

	for def in all_defs():
		if offered(def.id):
			out.append(def)

	return out


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
		if def.tags.has(tier) and def.id != &"fists" and offered(def.id):
			out.append(def.id)

	return out


## A weighted pick among the weapons of [param tier] (or any), drawn for [param channel] (`box`, `loot`,
## `cache`, or "" for none; the spawner pools use `spawner`, `wall`, `crate`, `trader` through channel_weight): `weapons.not_in.<channel>` keeps ids out of one channel, `weapons.weights`
## weighs each draw (default 1, 0 never), both from `cfg/addons/zombie_zone/packs.yml`.
static func random_of(tier: StringName, rng: RandomNumberGenerator, channel: StringName = &"") -> StringName:
	var ids := ids_of(tier) if tier != &"any" else _any()
	var barred: Array = ZzPackList.cfg("weapons.not_in.%s" % channel, []) if channel != &"" else []
	var weights: Dictionary = ZzPackList.cfg("weapons.weights", {})
	var pool: Array[StringName] = []
	var total := 0.0

	for id in ids:
		if barred.has(String(id)) or float(weights.get(String(id), 1.0)) <= 0.0 or not from_wave(id):
			continue

		pool.append(id)
		total += float(weights.get(String(id), 1.0))

	if pool.is_empty():
		return &"zz_pistol" if exists(&"zz_pistol") else &"pistol"

	var at := rng.randf() * total

	for id in pool:
		at -= float(weights.get(String(id), 1.0))

		if at < 0.0:
			return id

	return pool[pool.size() - 1]


## A spawner pool's weight for weapon [param id] on [param channel] (`spawner`, `wall`, `crate`, `trader`, plus the
## box, loot and cache ones): 0 when `weapons.not_in.<channel>` bars it, else [param weight] times `weapons.weights`.
## Handed to dot-weapon's `DotWeaponSpawnerConfig.weigher`; ids that are no weapon (a medkit) pass through.
static func channel_weight(channel: StringName, id: StringName, weight: float) -> float:
	if not exists(id):
		return weight

	var barred: Array = ZzPackList.cfg("weapons.not_in.%s" % channel, []) if channel != &"" else []
	if barred.has(String(id)) or not offered(id) or not from_wave(id):
		return 0.0

	var weights: Dictionary = ZzPackList.cfg("weapons.weights", {})
	return weight * float(weights.get(String(id), 1.0))


## Whether the wave in play is late enough for [param id] to be laid out (`weapons.min_wave`; always, outside a hold).
## The trader is not gated: its price is.
static func from_wave(id: StringName) -> bool:
	return wave <= 0 or wave >= int((ZzPackList.cfg("weapons.min_wave", {}) as Dictionary).get(String(id), 0))


## How hard [param id] hits per second, for a stand-in choosing between two guns: `weapons.rating.<id>` over a figure
## worked out from the def (pellets times damage, a quarter of the blast, over the time between uses).
static func rating(id: StringName) -> float:
	var set: Dictionary = ZzPackList.cfg("weapons.rating", {})
	if set.has(String(id)):
		return float(set[String(id)])

	var def := def_of(id)
	if def == null or def.tuning == null or not "damage" in def.tuning:
		return 0.0

	var per_use: float = float(def.tuning.damage) * maxf(float(def.tuning.pellets), 1.0) + float(def.tuning.splash_damage) * 0.25
	return per_use / maxf(float(def.use_interval_ticks) / maxf(float(def.authored_tick_rate), 1.0), 0.05)


## Whether [param id] hurts whoever fires it when the target is near.
static func explosive(id: StringName) -> bool:
	var def := def_of(id)
	return def != null and def.tags.has(&"explosive") and not def.tags.has(&"thrown")


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


## The weapon command a survivor's buttons make, on every end that simulates their gun: the
## server's rig, and the rig a client draws (offline and connected).
##
## [b]One function, because the two rigs count the same magazine.[/b] A rule written on one end
## only (hands that are busy, a magazine that reloads itself) is a client whose drawn gun and
## counter say one thing while the server's gun does another. [param held] is the server's own
## test: pinned, or using something with both hands. Down, you still shoot.
static func command_for(fire: bool, reload: bool, held: bool, yaw: float, pitch: float, slot: int,
		arsenal: DotWeaponArsenal, aim: bool = false) -> DotWeaponCommand:
	var command := DotWeaponCommand.new()
	command.set_button(DotWeaponCommand.BUTTON_USER_0, aim and not held)

	if not held:
		command.set_button(DotWeaponCommand.BUTTON_ATTACK, fire)
		command.set_button(DotWeaponCommand.BUTTON_RELOAD, reload or wants_reload(arsenal))

	command.yaw = yaw
	command.pitch = pitch
	command.slot = slot
	return command


## Whether the gun in hand is empty and has something to reload from.
##
## [b]An empty magazine reloads itself, trigger held or not.[/b] dot-weapon starts a reload only
## on a dry pull (`auto_reload`), so a survivor who let go on the last round stood with an empty
## gun until the next pull clicked: with a horde coming, that click is the reload starting a
## second late. A weapon with `auto_reload` off (a minigun, a beam) is left to the R key.
static func wants_reload(arsenal: DotWeaponArsenal) -> bool:
	if arsenal == null or arsenal.is_reloading() or arsenal.is_switching():
		return false

	var slot := arsenal.current()

	if slot == null or not slot.def.uses_magazine() or not slot.def.auto_reload:
		return false

	if slot.magazine >= maxi(slot.def.cost_per_use, 1):
		return false

	return slot.def.ammo_type == &"" or slot.def.infinite_reserve or arsenal.ammo().has(slot.def.ammo_type, 1)
