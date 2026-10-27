extends RefCounted

const ZzLoot := preload("zz_loot.gd")
const ZzNpcs := preload("zz_npcs.gd")

## What a dead zombie leaves lying: ammunition and health, small from a common, more from a mutant
## (every special and the brute), each kind with its own odds. The boxes are [ZzBoxes]' and stay a
## separate, rarer drop.
##
## [b]Tuning is `cfg/addons/zombie_zone/drops.yml`[/b] (every `*.yml` there, then the game, then the
## operator's `cfg/server/...` tiers, then `ZOMBIE_ZONE_DROPS_*` and `--zombie_zone.drops.*`), read
## by dot-core's [DotAddonConfig]. A kind's setting is the first found of `types.<kind>`, then its
## class (`common`, or `mutant` for every other kind, a pack's monster included), then the top level.

const CHANNEL := "zz.drops"
const ADDON := "zombie_zone"

const AMMO_CATEGORY := &"ammo"
const HEALTH_CATEGORY := &"health"

## item -> [loot kind, category]. Pills are the small health; a medkit is the rare big one.
const ITEMS := {
	&"ammo": [ZzLoot.AMMO, AMMO_CATEGORY],
	&"pills": [ZzLoot.PILLS, HEALTH_CATEGORY],
	&"medkit": [ZzLoot.MEDKIT, HEALTH_CATEGORY],
	&"defib": [ZzLoot.DEFIB, HEALTH_CATEGORY],
}

const DEFAULTS := {
	"drops": {
		"enabled": true,
		"multiplier": 1.0,
		"despawn_seconds": 90.0,
		"max_lying": 40,
		"chance": 0.0,
		"min": 1,
		"max": 1,
		"ammo_fraction": 0.25,
		"categories": {"ammo": 1.0, "health": 1.0},
		"items": {"ammo": 1.0, "pills": 1.0, "medkit": 0.0, "defib": 0.0},
		"classes": {
			"common": {
				"chance": 0.16, "min": 1, "max": 1, "ammo_fraction": 0.2,
				"categories": {"ammo": 1.0, "health": 0.6},
				"items": {"ammo": 1.0, "pills": 1.0, "medkit": 0.05, "defib": 0.01},
			},
			"mutant": {
				"chance": 0.5, "min": 1, "max": 2, "ammo_fraction": 0.35,
				"categories": {"ammo": 1.0, "health": 1.0},
				"items": {"ammo": 1.0, "pills": 1.0, "medkit": 0.25, "defib": 0.06},
			},
		},
		"types": {
			"leaper": {"chance": 0.45, "categories": {"ammo": 1.0, "health": 0.9}},
			"strangler": {"chance": 0.55, "categories": {"ammo": 0.8, "health": 1.4}},
			"bloater": {"chance": 0.4, "categories": {"ammo": 0.7, "health": 1.2}},
			"ram": {"chance": 0.55, "categories": {"ammo": 1.2, "health": 1.0}},
			"spitter": {"chance": 0.45, "categories": {"ammo": 1.1, "health": 0.9}},
			"rider": {"chance": 0.5, "categories": {"ammo": 1.0, "health": 1.1}},
			"screamer": {"chance": 0.5, "categories": {"ammo": 1.3, "health": 0.8}},
			"crawler": {"chance": 0.35, "categories": {"ammo": 0.9, "health": 1.0}},
			"riot": {"chance": 0.7, "min": 2, "max": 2, "categories": {"ammo": 1.5, "health": 0.8}},
			"sleeper": {"chance": 0.6, "min": 1, "max": 2},
			"mutant": {"chance": 1.0, "min": 3, "max": 4, "ammo_fraction": 0.5, "categories": {"ammo": 1.2, "health": 1.4}},
			"brute": {
				"chance": 1.0, "min": 3, "max": 4, "ammo_fraction": 0.5,
				"categories": {"ammo": 1.2, "health": 1.4},
				"items": {"ammo": 1.0, "pills": 1.0, "medkit": 0.6, "defib": 0.25},
			},
		},
	},
}

var game = null
## The merged `drops` block (defaults < yml < environment < command line).
var config: Dictionary = DEFAULTS["drops"].duplicate(true)
## Loot ids this laid and that still lie.
var lying: Array[int] = []

var _rng := RandomNumberGenerator.new()


func _init(p_game: Object) -> void:
	game = p_game
	_rng.seed = 4177


## Reads the cfg tiers; without files the defaults stand.
func load_config() -> void:
	var res := DotAddonConfig.load_dir(ADDON, DEFAULTS)

	if not res.ok:
		DotLog.warn(CHANNEL, "the drop settings do not load, defaults used", {"why": res.error.message})
		return

	var block: Variant = (res.value as Dictionary).get("drops", null)

	if block is Dictionary:
		config = block


## The class a kind falls under: `common`, else `mutant`.
static func class_of(kind: StringName) -> StringName:
	return &"common" if kind == ZzNpcs.COMMON else &"mutant"


## One setting for [param kind]: its own entry, its class's, then the top level, then [param fallback].
func setting(kind: StringName, key: String, fallback: Variant) -> Variant:
	for scope: Variant in [
		(config.get("types", {}) as Dictionary).get(String(kind), null),
		(config.get("classes", {}) as Dictionary).get(String(class_of(kind)), null),
		config,
	]:
		if scope is Dictionary and (scope as Dictionary).has(key):
			return (scope as Dictionary)[key]

	return fallback


## A weight table for [param kind] (`categories` or `items`): entries merge from the top level down
## to the kind's own, so an override names only what it changes.
func weights(kind: StringName, key: String) -> Dictionary:
	var out := {}

	for scope: Variant in [
		config,
		(config.get("classes", {}) as Dictionary).get(String(class_of(kind)), null),
		(config.get("types", {}) as Dictionary).get(String(kind), null),
	]:
		if scope is Dictionary and (scope as Dictionary).get(key) is Dictionary:
			out.merge((scope as Dictionary)[key], true)

	return out


## The weight of each item for [param kind]: its category's weight times its own.
func item_weights(kind: StringName) -> Dictionary:
	var cats := weights(kind, "categories")
	var items := weights(kind, "items")
	var out := {}

	for item: StringName in ITEMS:
		var category: StringName = ITEMS[item][1]
		out[item] = maxf(float(cats.get(String(category), 1.0)), 0.0) * maxf(float(items.get(String(item), 0.0)), 0.0)

	return out


## Drop events expected per kill of [param kind] (chance times the global multiplier).
func rolls_for(kind: StringName) -> float:
	if not bool(config.get("enabled", true)):
		return 0.0

	return maxf(float(setting(kind, "chance", 0.0)), 0.0) * maxf(float(config.get("multiplier", 1.0)), 0.0)


## A zombie of [param kind] died at [param at]: lays what it drops. Returns the loot ids.
func on_kill(kind: StringName, at: Vector3) -> Array[int]:
	var laid: Array[int] = []

	if game.loot == null:
		return laid

	var rolls := rolls_for(kind)
	var events := int(floorf(rolls))

	if _rng.randf() < rolls - floorf(rolls):
		events += 1

	for _e in events:
		var lo := maxi(int(setting(kind, "min", 1)), 0)
		var hi := maxi(int(setting(kind, "max", 1)), lo)

		for _i in _rng.randi_range(lo, hi):
			var id := _lay(kind, at, laid.size())

			if id >= 0:
				laid.append(id)

	return laid


func _lay(kind: StringName, at: Vector3, index: int) -> int:
	var table := item_weights(kind)
	var total := 0.0

	for item: StringName in table:
		total += float(table[item])

	if total <= 0.0:
		return -1

	var roll := _rng.randf() * total
	var chosen: StringName = &"ammo"

	for item: StringName in table:
		roll -= float(table[item])
		chosen = item

		if roll <= 0.0:
			break

	var loot = game.loot
	var cap := maxi(int(config.get("max_lying", 40)), 1)
	lying = lying.filter(func(i: int) -> bool: return loot.exists(i))

	while lying.size() >= cap:
		loot.remove(lying.pop_front())

	# Scatter a pile round the body so several are each something to look at.
	var angle := float(index) * 2.4 + _rng.randf() * 0.6
	var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * (0.0 if index == 0 else 0.6)
	var ground: Vector3 = game.ray_hit(spot + Vector3(0.0, 1.0, 0.0), spot + Vector3(0.0, -4.0, 0.0))
	var life := float(config.get("despawn_seconds", 90.0))
	var id: int = loot.add(ITEMS[chosen][0], &"", ground if ground != Vector3.INF else spot, life if life > 0.0 else -1.0)

	if chosen == &"ammo":
		loot.entries[id]["fraction"] = clampf(float(setting(kind, "ammo_fraction", 0.25)), 0.0, 1.0)

	lying.append(id)
	return id
