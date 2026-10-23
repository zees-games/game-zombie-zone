extends RefCounted

const ZzLoot := preload("zz_loot.gd")
const ZzWeapons := preload("zz_weapons.gd")

## The map's weapon and supply spawners: dot-weapon's [DotWeaponSpawner] driving [ZzLoot].
##
## A map document lists `spawners` (`{at, id?, pool?, tags_any?, respawn?, max?, kind?, item?...}`, the fields of dot-weapon's docs/spawners.md); pools, defaults and per-map blocks are `cfg/game/game-zombie-zone/dot_weapon/spawner.yml`, and `spawner_*` keys in a map's dot_map file. Each spawned item is an ordinary loot entry, so the wire, the look-and-press use and the HUD are unchanged; using or removing the entry is what starts the respawn timer.

const CHANNEL := "zz.spawners"
const GAME_ID := "game-zombie-zone"

## Spawner kinds that are loot kinds already; anything else is laid as a weapon.
const KINDS: Array[StringName] = [ZzLoot.WEAPON, ZzLoot.AMMO, ZzLoot.MEDKIT, ZzLoot.PILLS, ZzLoot.THROWABLE, ZzLoot.BOX]

var game = null
var spawner := DotWeaponSpawner.new()

var _loot_of: Dictionary = {}
var _inst_of: Dictionary = {}


func _init(p_game: Object) -> void:
	game = p_game
	spawner.config.game = GAME_ID
	spawner.spawned.connect(_on_spawned)
	spawner.taken.connect(_on_taken)


## Reads the config files; call once the weapon packs are installed, since pools draw from their tags.
func load_config() -> void:
	spawner.config.defs = ZzWeapons.all_defs()
	var _read := spawner.config.load_files()


## Lays the map's spawners and starts the round. Call after the loot was cleared.
func start_round(doc: Dictionary) -> void:
	var sites: Array = []
	var index := 0
	for raw: Variant in doc.get("spawners", []):
		if raw is Dictionary:
			var d := (raw as Dictionary).duplicate()
			d["position"] = d.get("at", [0, 0, 0])
			if not d.has("id"):
				d["id"] = "spawner_%d" % index
			index += 1
			sites.append(DotWeaponSpawnSite.from_dictionary(d))
	for lid: int in _inst_of.keys():
		game.loot.remove(lid, &"")
	spawner.load_map(str(doc.get("id", "")), sites)
	var _added := spawner.add_entities(doc.get("entities", []))
	_loot_of.clear()
	_inst_of.clear()
	spawner.begin_round(game.now(), game.round_number)


## The loot entries the spawners laid, oldest first.
func loot_ids() -> Array:
	var ids := _inst_of.keys()
	ids.sort()
	return ids


func tick() -> void:
	spawner.tick(game.now())


## What using loot entry [param loot_id] costs, in points: the site's `data.price`, else `data.tier_price` looks the weapon's tier up in the config's `game: {shop: {prices: {tier: n}}}`. Zero for free and for anything the spawner did not lay.
func price_of(loot_id: int) -> int:
	var inst: int = _inst_of.get(loot_id, 0)
	if inst == 0 or not spawner.live().has(inst):
		return 0
	var live: Dictionary = spawner.live()[inst]
	var data: Dictionary = live["data"]
	if data.has("price"):
		return maxi(int(data["price"]), 0)
	if data.get("tier_price", false):
		var prices: Variant = (spawner.game_block().get("shop", {}) as Dictionary).get("prices", {})
		return maxi(int((prices as Dictionary).get(String(ZzWeapons.tier_of(live["item"])), 0)), 0) if prices is Dictionary else 0
	return 0


## False, with the reason sent to [param player], when they cannot pay for [param loot_id]. The charge is taken when the entry is used up.
func may_use(loot_id: int, player) -> bool:
	var price := price_of(loot_id)
	if price > 0 and player.points < price:
		game.refused.emit(player.player_id, "That costs %d points." % price)
		return false
	return true


## The game's loot entry went (used or removed): the buyer pays, and the spawner starts the item's timer.
func on_loot_removed(loot_id: int, by: StringName) -> void:
	if _inst_of.has(loot_id):
		var price := price_of(loot_id)
		if price > 0 and game.players.has(by):
			game.players[by].points -= price
		var inst: int = _inst_of[loot_id]
		var _taken := spawner.take(inst, by)


func _on_spawned(instance: int, _site: StringName, item: StringName, kind: StringName, at: Vector3) -> void:
	if game.loot == null:
		return
	var loot_kind: StringName = kind if KINDS.has(kind) else ZzLoot.WEAPON
	var lid: int = game.loot.add(loot_kind, item, at)
	_loot_of[instance] = lid
	_inst_of[lid] = instance


func _on_taken(instance: int, _site: StringName, _item: StringName, taker: StringName) -> void:
	var lid: int = _loot_of.get(instance, -1)
	_loot_of.erase(instance)
	_inst_of.erase(lid)
	if lid >= 0 and game.loot != null:
		game.loot.remove(lid, taker)
