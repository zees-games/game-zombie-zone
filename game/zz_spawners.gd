extends RefCounted

const ZzLoot := preload("zz_loot.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzPaths := preload("zz_paths.gd")

## The map's weapon and supply spawners: dot-weapon's [DotWeaponSpawner] driving [ZzLoot].
##
## The sources of what lies on a map, all through the one spawner: the document's `spawners`, the converted world's `pickups` (weapon_*, item_*, ammo_* entities, mapped by the config's `classes:`), the config's per-map `game: spawners:` list (same fields as the document's), and traders (`traders` in the document or the config's `game: traders:`; a shelf of priced stock rolled from a pool).
## A map document lists `spawners` (`{at, id?, pool?, tags_any?, respawn?, max?, kind?, item?...}`, the fields of dot-weapon's docs/spawners.md); pools, defaults and per-map blocks are `cfg/game/game-zombie-zone/dot_weapon/spawner.yml`, and `spawner_*` keys in a map's dot_map file. Each spawned item is an ordinary loot entry, so the wire, the look-and-press use and the HUD are unchanged; using or removing the entry is what starts the respawn timer.

const CHANNEL := "zz.spawners"
const GAME_ID := "game-zombie-zone"

## Spawner kinds that are loot kinds already; anything else is laid as a weapon.
const KINDS: Array[StringName] = [ZzLoot.WEAPON, ZzLoot.AMMO, ZzLoot.MEDKIT, ZzLoot.PILLS, ZzLoot.THROWABLE, ZzLoot.BOX, ZzLoot.DEFIB]

var game = null
var spawner := DotWeaponSpawner.new()

var _loot_of: Dictionary = {}
var _inst_of: Dictionary = {}
var _price_of: Dictionary = {}
## Loot id -> {site, slot} for a trader's shelf; restocks wait in _restock as {at, site, slot}.
var _shelf: Dictionary = {}
var _empty_tries: Dictionary = {}

## The most one entry may cost; a price outside 0..this (or not a number) is unaffordable, never free.
const MAX_PRICE := 1000000.0
var _restock: Array = []
var _traders: Dictionary = {}
## Trader id -> how many shelf rolls it has had, so each restock is a new draw.
var _generation: Dictionary = {}
## Whether the shelves are standing, and whether they sell, as of the last tick.
var _present := true
var _open := true

const WHEN_SETUP := 0
const WHEN_WAVES := 1
const WHEN_ALWAYS := 2


func _init(p_game: Object) -> void:
	game = p_game
	spawner.config.game = GAME_ID
	spawner.spawned.connect(_on_spawned)
	spawner.taken.connect(_on_taken)


## Reads the config files; call once the weapon packs are installed, since pools draw from their tags.
func load_config() -> void:
	spawner.config.defs = ZzWeapons.offered_defs()
	spawner.config.weigher = ZzWeapons.channel_weight
	var _read := spawner.config.load_files()


## Lays the map's spawners and starts the round. Call after the loot was cleared.
func start_round(doc: Dictionary) -> void:
	for lid: int in _price_of.keys():
		if game.loot.exists(lid):
			game.loot.remove(lid, &"")

	_loot_of.clear()
	_inst_of.clear()
	_price_of.clear()
	_shelf.clear()
	_restock.clear()
	_empty_tries.clear()
	_traders.clear()
	_generation.clear()
	spawner.load_map(str(doc.get("id", "")), [])
	var game_block := spawner.game_block()
	var index := 0

	for source: Array in [doc.get("spawners", []), game_block.get("spawners", [])]:
		for raw: Variant in source:
			if raw is Dictionary:
				var d := (raw as Dictionary).duplicate()
				d["position"] = _vec(d.get("at", [0, 0, 0]))
				if not d.has("id"):
					d["id"] = "spawner_%d" % index
				index += 1
				var _site := spawner.add_site(DotWeaponSpawnSite.from_dictionary(d))

	var entities: Array = (doc.get("entities", []) as Array).duplicate()
	entities.append_array(world_pickups(doc))
	var _added := spawner.add_entities(entities)

	var trader_defaults: Dictionary = game_block.get("trader", {}) as Dictionary if game_block.get("trader") is Dictionary else {}

	if trader_enabled():
		for source: Array in [doc.get("traders", []), game_block.get("traders", [])]:
			for raw: Variant in source:
				if raw is Dictionary:
					_add_trader(raw as Dictionary, trader_defaults)

		if _traders.is_empty() and bool(shop_block().get("fallback", true)):
			_add_trader(_fallback_trader(), trader_defaults)

	spawner.begin_round(game.now(), game.round_number)
	_open = _window_open()
	_present = _open or not trader_despawns()

	if _present:
		_stock_all()
	game.shop_changed.emit()


## The `pickups` the converter wrote into the map's world manifest (weapon_*, item_*, ammo_* entities), read from the checkout's `world/`; empty for a map with no world.
static func world_pickups(doc: Dictionary) -> Array:
	var pack := str(doc.get("world", ""))
	if pack == "":
		return []
	var path := ZzPaths.rebase("res://world/%s/%s" % [pack, str(doc.get("id", ""))]) + ".json"
	if not FileAccess.file_exists(path):
		return []
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (manifest as Dictionary).get("pickups", []) if manifest is Dictionary else []


static func _vec(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	var a: Array = v if v is Array else [0, 0, 0]
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## A trader is a disabled site (it lays nothing itself) whose pool the shelf rolls from, `slots` items side by side `spacing` metres apart across its `yaw`; a bought slot is restocked after `restock` seconds (0 never).
func _add_trader(raw: Dictionary, defaults: Dictionary) -> void:
	var d := raw.duplicate()
	var id := StringName(str(d.get("id", "trader_%d" % _traders.size())))
	var at := _vec(d.get("at", [0, 0, 0]))
	var site := DotWeaponSpawnSite.from_dictionary({"id": String(id), "position": at, "pool": str(d.get("pool", defaults.get("pool", "trader_stock"))),
		"enabled": false, "data": {"tier_price": true}})
	var _site := spawner.add_site(site)
	_traders[id] = {"at": at, "yaw": deg_to_rad(float(d.get("yaw", defaults.get("yaw", 0.0)))),
		"slots": clampi(int(d.get("slots", defaults.get("slots", 4))), 1, 12),
		"spacing": float(d.get("spacing", defaults.get("spacing", 0.9))),
		"restock": float(d.get("restock", defaults.get("restock", 0.0)))}
	_generation[id] = 0


func _stock_all() -> void:
	for id: StringName in _traders:
		for slot in int(_traders[id]["slots"]):
			_stock(id, slot)


func _stock(id: StringName, slot: int) -> void:
	if not _present:
		return
	var t: Dictionary = _traders[id]
	var rolled := spawner.roll(id, int(_generation[id]))
	_generation[id] = int(_generation[id]) + 1
	if rolled.is_empty():
		var wait: float = maxf(float(t.get("restock", 0.0)), 10.0)
		if int(_empty_tries.get(id, 0)) < 5:
			_empty_tries[id] = int(_empty_tries.get(id, 0)) + 1
			_restock.append({"at": game.now() + wait, "site": id, "slot": slot})
		return
	_empty_tries.erase(id)
	var side := Vector3(cos(t["yaw"]), 0.0, -sin(t["yaw"]))
	var at: Vector3 = t["at"] + side * (float(slot) - float(int(t["slots"]) - 1) * 0.5) * float(t["spacing"])
	var data: Dictionary = rolled.get("data", {})
	var merged := {"tier_price": true}
	merged.merge(data, true)
	var kind: StringName = rolled.get("kind", &"weapon")
	var loot_kind: StringName = kind if KINDS.has(kind) else ZzLoot.WEAPON
	var lid: int = game.loot.add(loot_kind, rolled["id"], at, -1.0, _price_for(rolled["id"], merged))
	_price_of[lid] = game.loot.price_of(lid)
	_shelf[lid] = {"site": id, "slot": slot}


## The loot entries the spawners and traders laid, oldest first.
func loot_ids() -> Array:
	var ids := _inst_of.keys()
	ids.append_array(_shelf.keys())
	ids.sort()
	return ids


func tick() -> void:
	spawner.tick(game.now())
	_follow_window()

	var i := 0
	while i < _restock.size():
		var r: Dictionary = _restock[i]
		if game.now() >= float(r["at"]):
			_restock.remove_at(i)
			_stock(r["site"], int(r["slot"]))
		else:
			i += 1


## The `game: shop:` block of the map's spawner config (operator keys: docs/operators.md).
func shop_block() -> Dictionary:
	var shop: Variant = spawner.game_block().get("shop", {})
	return shop as Dictionary if shop is Dictionary else {}


func trader_enabled() -> bool:
	var forced: int = game.config.trader_enabled
	return forced == 1 if forced >= 0 else bool(shop_block().get("enabled", true))


## 0 setup only, 1 setup and a survival map's breathers, 2 always.
func trader_when() -> int:
	var forced: int = game.config.trader_when
	if forced >= 0:
		return forced
	var v: Variant = shop_block().get("available", "always")
	if v is int or v is float:
		return clampi(int(v), WHEN_SETUP, WHEN_ALWAYS)
	return {"setup": WHEN_SETUP, "waves": WHEN_WAVES, "always": WHEN_ALWAYS}.get(str(v).to_lower(), WHEN_ALWAYS)


func trader_despawns() -> bool:
	var forced: int = game.config.trader_despawn
	return forced == 1 if forced >= 0 else bool(shop_block().get("despawn", true))


## Points a survivor starts a map with: `shop.start_points` is a number, or a map with `default`, a key per difficulty (easy, normal, advanced, expert) and a key per mode (exodus, survival) that wins over the difficulty's.
func start_points() -> int:
	var forced: int = game.config.start_points
	if forced >= 0:
		return forced
	var v: Variant = shop_block().get("start_points", 0)
	if not v is Dictionary:
		return _clean_price(v)
	var d := v as Dictionary
	var picked: Variant = d.get("default", 0)
	var diff := str(game.config.difficulty_name())
	if d.has(diff):
		picked = d[diff]
	var mode := "survival" if game.is_survival() else "exodus"
	if d.has(mode):
		picked = d[mode]
	return _clean_price(picked)


## Tops every survivor up to the starting points; a balance already higher is kept.
func grant_start_points() -> void:
	var start := start_points()
	for id: StringName in game.players:
		grant_start_points_to(game.players[id], start)


func grant_start_points_to(player, start: int = -1) -> void:
	var amount := start_points() if start < 0 else start
	if int(player.points) < amount:
		player.points = amount


## True while the trader may sell: the setup period (before the horde runs), and by `available` a survival map's breathers or always.
func trader_sites() -> Array:
	var out: Array = []
	for id: StringName in _traders:
		out.append(_traders[id]["at"])
	return out


func trader_positions() -> Array:
	var out: Array = []
	if _present:
		for id: StringName in _traders:
			out.append(_traders[id]["at"])
	return out


func trader_open() -> bool:
	return _open


## Which window a map is in, for `zz_trader_<window>`: setup (not started, or between maps), grace, breather (a survival map's rest between waves) or round.
func trader_window() -> StringName:
	if game.phase != game.Phase.PLAY:
		return &"setup"
	if game.grace.is_active():
		return &"grace"
	var run = game.survival
	if game.is_survival() and (run == null or run.waves == null or run.waves.stage != DotNpcDirectorWaves.Stage.HORDE):
		return &"breather"
	return &"round"


## Whether the trader sells in [param window]: its own cvar when set, else what `zz_trader_when` / the file's `available` says.
func trader_allowed_in(window: StringName) -> bool:
	var forced: int = int(game.config.get("trader_" + String(window)))
	if forced >= 0:
		return forced == 1
	match window:
		&"setup", &"grace":
			return true
		&"breather":
			return trader_when() >= WHEN_WAVES
	return trader_when() == WHEN_ALWAYS


func _window_open() -> bool:
	return trader_allowed_in(trader_window())


## The sentence for a survivor who presses use at a closed trader; "" is silence.
func closed_message() -> String:
	return str(game.config.trader_closed_message)


func _follow_window() -> void:
	var open := _window_open() and trader_enabled()
	if open != _open:
		_open = open
		DotLog.debug(CHANNEL, "the trader changed", {"open": open})
		game.shop_changed.emit()
	var present := _open or not trader_despawns()
	if present == _present:
		return
	_present = present
	if present:
		_stock_all()
		return
	_restock.clear()
	for lid: int in _shelf.keys():
		game.loot.remove(lid, &"")


## A trader for a map with none: a few metres ahead of the first survivor spawn, facing back at it.
func _fallback_trader() -> Dictionary:
	var at := Vector3(0.0, 0.8, 0.0)
	var yaw := 0.0
	if game.map != null:
		var spot: Array = game.map.spawn("survivors", 0)
		yaw = float(spot[1])
		at = (spot[0] as Vector3) + Vector3(-sin(yaw), 0.0, -cos(yaw)) * float(shop_block().get("fallback_distance", 3.0)) - Vector3(0.0, 0.2, 0.0)
	return {"id": "trader_start", "at": [at.x, at.y, at.z], "yaw": rad_to_deg(yaw)}


## What using loot entry [param loot_id] costs, in points: the site's `data.price`, else `data.tier_price` looks the weapon's tier up in the config's `game: {shop: {prices: {tier: n}}}`. Zero for free and for anything the spawner did not lay.
func price_of(loot_id: int) -> int:
	return int(_price_of.get(loot_id, 0))


func _price_for(item: StringName, data: Dictionary) -> int:
	if data.has("price"):
		return _clean_price(data["price"])
	if data.get("tier_price", false):
		var prices: Variant = (spawner.game_block().get("shop", {}) as Dictionary).get("prices", {})
		return _clean_price((prices as Dictionary).get(String(ZzWeapons.tier_of(item)), 0)) if prices is Dictionary else 0
	return 0


static func _clean_price(v: Variant) -> int:
	if not (v is int or v is float or v is String):
		return 0
	var f := float(v)
	if is_nan(f) or is_inf(f) or f > MAX_PRICE:
		return int(MAX_PRICE)
	return int(maxf(f, 0.0))


## True when loot entry [param loot_id] was laid by a spawner site (not a trader shelf).
func lays(loot_id: int) -> bool:
	return _inst_of.has(loot_id)


## False, with the reason sent to [param player], when they cannot pay for [param loot_id]. The charge is taken when the entry is used up.
func may_use(loot_id: int, player) -> bool:
	if _shelf.has(loot_id) and not _open:
		game.refused.emit(player.player_id, "The trader is closed.")
		return false
	var price := price_of(loot_id)
	if price > 0 and player.points < price:
		game.refused.emit(player.player_id, "That costs %d points." % price)
		return false
	return true


## The game's loot entry went (used or removed): the buyer pays, and the spawner starts the item's timer (a trader's slot restocks instead).
func on_loot_removed(loot_id: int, by: StringName) -> void:
	var price: int = int(_price_of.get(loot_id, 0))
	if price > 0 and game.players.has(by):
		game.players[by].points = maxi(int(game.players[by].points) - price, 0)
	_price_of.erase(loot_id)

	if _shelf.has(loot_id):
		var shelf: Dictionary = _shelf[loot_id]
		_shelf.erase(loot_id)
		var wait: float = float(_traders.get(shelf["site"], {}).get("restock", 0.0))
		if wait > 0.0 and by != &"":
			_restock.append({"at": game.now() + wait, "site": shelf["site"], "slot": shelf["slot"]})

	if _inst_of.has(loot_id):
		var inst: int = _inst_of[loot_id]
		var _taken := spawner.take(inst, by)


func _on_spawned(instance: int, _site: StringName, item: StringName, kind: StringName, at: Vector3) -> void:
	if game.loot == null:
		return
	var loot_kind: StringName = kind if KINDS.has(kind) else ZzLoot.WEAPON
	var live: Dictionary = spawner.live().get(instance, {})
	var lid: int = game.loot.add(loot_kind, item, at, -1.0, _price_for(item, live.get("data", {})))
	_price_of[lid] = game.loot.price_of(lid)
	_loot_of[instance] = lid
	_inst_of[lid] = instance


func _on_taken(instance: int, _site: StringName, _item: StringName, taker: StringName) -> void:
	var lid: int = _loot_of.get(instance, -1)
	_loot_of.erase(instance)
	_inst_of.erase(lid)
	if lid >= 0 and game.loot != null:
		game.loot.remove(lid, taker)
