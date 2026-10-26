extends RefCounted

## Optional content packs: weapons and monsters that an installed addon adds to the game.
##
## [b]The game ships without them and nothing here is needed to run.[/b] At start every
## directory under `res://addons` is looked at for one file, `spawn_provider.gd` (the contract
## game-playground's spawn menu reads too). An addon without it is never loaded. One with it is
## loaded by path and called by name, never named in this game's code, because a script that
## said `ZzModernWeapons...` would not parse in a checkout without the pack.
##
## A provider defines `static func spawn_entries() -> Array[Dictionary]`, rows of
## `{category, id, name, icon, kind: "weapon"|"npc", spawn, cfg_hint}`. This file adds two
## optional functions, because a row is data and a rig needs the real definition:
##
## [codeblock]
## static func weapon_defs(types: Dictionary = {}) -> Array[DotWeaponDef]   # joins every rig's catalogue (zee add_source)
## static func weapon_art() -> Dictionary              # optional: id -> ZeeWeaponArt (zee passes the damage table as `types`)
## [/codeblock]
##
## A `weapon` row whose id no `weapon_defs()` returned is listed and logged, and never handed out.
## An `npc` row's `spawn` is `{npc?, health?, speed?, damage?, reach?, body?, brain?, boss?}`:
## `body` names one of this game's zombie bodies (default `common`; the client draws it, so a
## monster is a re-skinned body, not a scene of its own), `brain` a script path (default: the
## common's chase and bite). Both ends scan, so both end up with the same catalogue.
##
## [b]Tuning is `cfg/addons/zombie_zone/*.yml`[/b], every file read by dot-core's
## `DotAddonConfig` (see its docs/addon-config.md); the defaults are [constant DEFAULTS].

const CHANNEL := "zz.packs"
const PROVIDER_FILE := "spawn_provider.gd"
const ADDON := "zombie_zone"
const SOURCE_PREFIX := "zzpack:"
## The id a pack's `cfg/game/<game>/weapon` tier is read under.
const GAME_ID := "game-zombie-zone"
const MAX_ENTRIES_PER_PROVIDER := 256

## The game's own kinds: a pack monster of the same name would shadow one, so it is refused.
const RESERVED: Array[StringName] = [&"common", &"leaper", &"strangler", &"bloater", &"ram", &"spitter",
	&"rider", &"brute", &"sleeper", &"screamer", &"crawler", &"riot"]

const TIERS_ALL: Array[StringName] = [&"sidearm", &"primary", &"heavy", &"melee", &"thrown"]

const DEFAULTS := {
	"weapons": {
		# Off: installed weapons stay out of boxes, loot and bot kits.
		"enabled": true,
		# On brings zee-dot-weapons' own blasters and tools, zed-dot-weapons and every other pack's weapons back into every pool, the shop and the stand-ins' kits.
		"legacy": false,
		# Weapon ids kept out of the pool.
		"exclude": [],
		# id -> draw weight in boxes, loot and caches (default 1, 0 never drawn; still given by name).
		"weights": {},
		# id -> tier (sidearm, primary, heavy, melee, thrown), over what the pack tags.
		"tiers": {},
		# channel (box, loot, cache, spawner, wall, crate, trader) -> ids kept out of that channel only.
		"not_in": {},
	},
	"monsters": {
		"enabled": true,
		# A pack monster's weight as a special, against 1.0 for each built-in kind the
		# director may send. 0 keeps every pack monster out.
		"weight": 1.0,
		# id -> weight, over the default. 0 drops one monster.
		"weights": {},
		# Ids that are bosses (sent in place of the brute) rather than specials.
		"boss": [],
		# id -> first survival wave that may send it (default 1).
		"min_wave": {},
		# Chance that a brute's turn goes to an installed boss, when there is one.
		"boss_chance": 0.4,
	},
}

## One monster the director may send.
class Monster:
	extends RefCounted
	var pack: String = ""
	var id: StringName = &""
	var title: String = ""
	var weight: float = 1.0
	var boss: bool = false
	var spawn: Dictionary = {}

## Where packs are looked for; a test points it at a fixture.
static var root: String = "res://addons"
static var config: Dictionary = DEFAULTS.duplicate(true)
static var providers: Dictionary = {}
static var weapon_rows: Array[Dictionary] = []
## Weapon id -> the pack directory that defined it.
static var pack_of: Dictionary = {}
static var monsters: Array[Monster] = []
static var _sources: Array[StringName] = []
static var _notes: PackedStringArray = PackedStringArray()


## Finds the packs under [param root], reads their tuning and registers what they offer.
## Safe to call again: it starts from nothing. Returns how many providers were loaded.
static func scan(from: String = "") -> int:
	clear()
	_load_config()
	var base := from if from != "" else root

	var found := 0

	if not DirAccess.dir_exists_absolute(base):
		return 0

	for dir_name in DirAccess.get_directories_at(base):
		var path := "%s/%s/%s" % [base, dir_name, PROVIDER_FILE]

		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			continue

		var script := load(path) as GDScript

		if script == null or not script.can_instantiate():
			DotLog.warn(CHANNEL, "a pack's provider does not load", {"pack": dir_name, "path": path})
			continue

		_set_pack_game("%s/%s/" % [base, dir_name])
		var provider: Object = script.new()
		providers[dir_name] = provider
		found += 1
		_take(dir_name, provider)

	DotLog.info(CHANNEL, "packs scanned", {
		"providers": found, "weapons": weapon_rows.size(), "monsters": monsters.size(),
	})
	return found


static func clear() -> void:
	for source in _sources:
		ZeeWeaponPack.remove_source(source)
		ZeeWeaponArtTable.remove_source(source)

	_sources.clear()
	providers.clear()
	weapon_rows.clear()
	pack_of.clear()
	monsters.clear()
	_notes = PackedStringArray()


static func _load_config() -> void:
	var res := DotAddonConfig.load_dir(ADDON, DEFAULTS)

	if not res.ok:
		DotLog.warn(CHANNEL, "the pack settings do not load, defaults used", {"why": res.error.message})
		config = DEFAULTS.duplicate(true)
		return

	config = res.value


## Gives every config class of a pack (a global `*Config` class under [param dir] with a static `game`) this game's id.
## Reached by path because a pack's class cannot be named here; it must run before weapon_defs().
static func _set_pack_game(dir: String) -> void:
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if not str(entry.get("path", "")).begins_with(dir) or not str(entry.get("class", "")).ends_with("Config"):
			continue

		var script := load(str(entry["path"])) as GDScript

		if script != null and script.get(&"game") is String:
			script.set(&"game", GAME_ID)

		if script != null and script.get(&"pack_cfg_root") is String:
			script.set(&"pack_cfg_root", _mounted_cfg_root(dir))


## A pack delivered by dot-cloud sits under `<mount prefix>/addons/<pack>/`, and its profiles under `<prefix>/cfg`
## (`DotCloudMounter.cfg_root_of`); a pack linked into `res://addons` has no root of its own, so this is empty.
static func _mounted_cfg_root(dir: String) -> String:
	var at := dir.find("/addons/")
	var prefix := dir.substr(0, at) if at >= 0 else ""

	if prefix in ["", "res:/", "res:", "res://"]:
		return ""

	var root := prefix.path_join("cfg")
	return root if DirAccess.dir_exists_absolute(root) else ""


static func cfg(path: String, fallback: Variant) -> Variant:
	return DotAddonConfig.get_value(config, path, fallback)


static func _take(pack: String, provider: Object) -> void:
	if not provider.has_method(&"spawn_entries"):
		DotLog.warn(CHANNEL, "a provider has no spawn_entries", {"pack": pack})
		return

	var rows: Array = provider.call(&"spawn_entries")
	var weapon_ids := PackedStringArray()
	var defs: Array = []

	if provider.has_method(&"weapon_defs") and bool(cfg("weapons.enabled", true)):
		defs = provider.call(&"weapon_defs", ZeeWeaponDamage.table())

	var excluded: Array = cfg("weapons.exclude", [])
	var source := StringName(SOURCE_PREFIX + pack)
	var kept: Array[DotWeaponDef] = []

	for def: Variant in defs:
		if def is DotWeaponDef and not excluded.has(String(def.id)):
			kept.append(def)
			weapon_ids.append(String(def.id))
			pack_of[String(def.id)] = pack

	if not kept.is_empty():
		# Through _tiered, never the provider's own: zee calls the source on every rig it builds and
		# a pack's definitions come back fresh each time, so the tier has to be given each time.
		ZeeWeaponPack.add_source(source, Callable(load("res://game/zz_packs.gd"), &"_tiered").bind(provider.get_script()))
		_sources.append(source)

		if provider.has_method(&"weapon_art"):
			ZeeWeaponArtTable.add_source(source, Callable(provider.get_script(), &"weapon_art"))
		else:
			ZeeWeaponArtTable.add_source(source, Callable(load("res://game/zz_packs.gd"), &"_stand_in_art").bind(provider.get_script()))

	var seen := 0

	for row_var: Variant in rows:
		seen += 1

		if seen > MAX_ENTRIES_PER_PROVIDER:
			DotLog.warn(CHANNEL, "a provider offers too many entries, the rest ignored", {"pack": pack})
			break

		if not row_var is Dictionary:
			continue

		var row: Dictionary = row_var
		var kind := str(row.get("kind", ""))
		var id := str(row.get("id", ""))

		if id == "":
			continue

		if kind == "weapon":
			var spawn: Dictionary = row.get("spawn", {})
			var wid := str(spawn.get("weapon", spawn.get("weapon_id", id)))

			if weapon_ids.has(wid) or weapon_ids.has(id):
				weapon_rows.append(row)
			else:
				DotLog.warn(CHANNEL, "a weapon row has no definition here (provider lacks weapon_defs or the weapon is excluded)",
					{"pack": pack, "id": id})
		elif kind == "npc" and bool(cfg("monsters.enabled", true)):
			_add_monster(pack, row)


## The art of a pack that ships none: a copy of a zee gun of the same tier under the pack weapon's id,
## so the hands are never empty (a weapon with no art equipped nothing, and the HUD still counted its ammo).
static func _stand_in_art(provider_script: Script) -> Array[ZeeWeaponArt]:
	var out: Array[ZeeWeaponArt] = []
	var tiers := _tiered(ZeeWeaponDamage.table(), provider_script)
	var rows: Dictionary = provider_script.call(&"art_rows") if provider_script.has_method(&"art_rows") else {}

	for def in tiers:
		var copy: ZeeWeaponArt

		# Built, never read back from the table: this runs while the table is being built.
		if def.tags.has(&"sidearm"):
			copy = ZeeWeaponArtTable.pistol()
		elif def.tags.has(&"heavy"):
			copy = ZeeWeaponArtTable.launcher()
		elif def.tags.has(&"melee"):
			copy = ZeeWeaponArtTable.knife()
		elif def.tags.has(&"thrown"):
			copy = ZeeWeaponArtTable.frag()
		else:
			copy = ZeeWeaponArtTable.rifle()

		copy.id = def.id
		_dress(copy, rows.get(def.id, {}))
		out.append(copy)

	return out


## Gives [param art] the pack's own model and hold when its provider names them (`art_rows()`): the toy stand-in's model, magazine,
## attachments and muzzle would otherwise show for a weapon whose pack ships real art.
static func _dress(art: ZeeWeaponArt, row: Dictionary) -> void:
	var model := str(row.get("model", ""))

	if model == "" or not ResourceLoader.exists(model):
		return

	var view: Dictionary = row.get("view", {})
	var motion := str(row.get("motion", "gun"))
	art.model_path = model

	# A melee model stands along +Y and a thrown one has no front: the stand-in's carry stays.
	if motion != "gun":
		art.model_forward = Vector3.UP if motion == "melee" else art.model_forward
		art.magazine_path = ""
		art.attachments = []
		return

	art.model_forward = Vector3.FORWARD
	art.muzzle_distance = float(row.get("muzzle", 0.0))
	art.muzzle_offset = Vector3.ZERO
	art.magazine_path = ""
	art.attachments = []
	art.ejects = false
	art.iron_sight = false
	art.view_scale = 1.0
	art.view_rotation = Vector3.ZERO
	art.world_offset = Vector3.ZERO
	art.world_rotation = Vector3.ZERO
	art.world_scale = 1.0
	art.aim_rotation = Vector3.ZERO

	if view.has("hold"):
		art.view_offset = view["hold"]

	if view.has("aim"):
		art.aim_offset = view["aim"]

	if view.has("zoom"):
		art.aim_zoom = float(view["zoom"])


## A pack weapon's definitions with a tier. The game draws boxes, loot and stand-in kits by tier
## (ZzWeapons.TIERS) and a weapon with none is in the pool and never handed out: the medieval
## pack's bow and crossbow are tagged `ranged`, not `primary`, so they were silently unreachable.
## A ranged weapon with no tier joins `primary`, a melee one `melee`. Static and public to the
## engine only because a source Callable must be a static method, never a lambda.
static func _tiered(types: Dictionary, provider_script: Script) -> Array[DotWeaponDef]:
	var defs: Array[DotWeaponDef] = provider_script.call(&"weapon_defs", types)
	var tiers: Dictionary = cfg("weapons.tiers", {})

	for def in defs:
		var has_tier := false

		if tiers.has(String(def.id)) and TIERS_ALL.has(StringName(str(tiers[String(def.id)]))):
			for tier: StringName in TIERS_ALL:
				def.tags.erase(tier)

			def.tags.append(StringName(str(tiers[String(def.id)])))

		for tier: StringName in [&"sidearm", &"primary", &"heavy", &"melee", &"thrown"]:
			has_tier = has_tier or def.tags.has(tier)

		if not has_tier:
			def.tags.append(&"melee" if def.tags.has(&"melee") else &"primary")

	return defs


static func _add_monster(pack: String, row: Dictionary) -> void:
	var spawn: Dictionary = row.get("spawn", {})
	var m := Monster.new()
	m.pack = pack
	m.id = StringName(str(spawn.get("npc", row["id"])))
	m.title = str(row.get("name", m.id))
	m.spawn = spawn
	m.boss = bool(spawn.get("boss", false)) or (cfg("monsters.boss", []) as Array).has(String(m.id))
	var weights: Dictionary = cfg("monsters.weights", {})
	m.weight = maxf(float(weights.get(String(m.id), cfg("monsters.weight", 1.0))), 0.0)

	if RESERVED.has(m.id):
		DotLog.warn(CHANNEL, "a pack monster shares a built-in kind's name, ignored", {"pack": pack, "id": String(m.id)})
		return

	if m.weight <= 0.0:
		_notes.append("%s switched off by weight 0" % m.id)
		return

	monsters.append(m)


## The monsters sent as specials in [param wave] (0 = any); `monsters.min_wave` holds each back.
static func specials(wave: int = 0) -> Array[Monster]:
	var out: Array[Monster] = []

	for m in monsters:
		if not m.boss and _from_wave(m, wave):
			out.append(m)

	return out


static func bosses(wave: int = 0) -> Array[Monster]:
	var out: Array[Monster] = []

	for m in monsters:
		if m.boss and _from_wave(m, wave):
			out.append(m)

	return out


static func _from_wave(m: Monster, wave: int) -> bool:
	return wave <= 0 or wave >= int((cfg("monsters.min_wave", {}) as Dictionary).get(String(m.id), 0))


static func is_pack_kind(kind: StringName) -> bool:
	for m in monsters:
		if m.id == kind:
			return true

	return false


## A weighted pick among [param pool], with [param roll] in [0, total). Null when empty.
static func pick(pool: Array[Monster], roll: float) -> Monster:
	var at := roll

	for m in pool:
		if at < m.weight:
			return m

		at -= m.weight

	return pool[pool.size() - 1] if not pool.is_empty() else null


static func total_weight(pool: Array[Monster]) -> float:
	var sum := 0.0

	for m in pool:
		sum += m.weight

	return sum


static func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("packs: %d providers (%s), %d weapon rows, %d monsters (%d boss)" % [
		providers.size(), ", ".join(PackedStringArray(providers.keys())), weapon_rows.size(),
		monsters.size(), bosses().size()])

	for m in monsters:
		out.append("  %s/%s weight %.2f%s" % [m.pack, m.id, m.weight, " boss" if m.boss else ""])

	out.append_array(_notes)
	return out

