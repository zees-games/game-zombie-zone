extends RefCounted

const ZzMapDoc := preload("zz_map_doc.gd")
const ZzWeapons := preload("zz_weapons.gd")

## Things on the ground a survivor presses E on: weapons, ammunition, a medkit, pills, something
## to throw, and the boxes.
##
## [b]One list, one id space, one wire event each way.[/b] Whatever lies on the ground is an
## entry here with a kind, an item and a place; a client is told when one appears and when one
## goes, and draws it (`ZzLootView`). What using one DOES is the game's: an ammo pile is never
## used up, a weapon replaces the one in its slot, a box is opened by [ZzBoxes].
##
## [b]Looked at, not walked over.[/b] A survivor picks up the thing they are looking at within
## reach, which is the genre's way: walking over a shotgun in a fight and swapping your rifle for
## it without meaning to is the thing nobody wants.

const CHANNEL := "zz.loot"

const WEAPON := &"weapon"
const AMMO := &"ammo"
const MEDKIT := &"medkit"
const PILLS := &"pills"
const THROWABLE := &"throwable"
const BOX := &"box"
const DEFIB := &"defib"
## The item is the tier ("1", "2"...); a bigger pack than the one worn raises the carry limit.
const BACKPACK := &"backpack"

## How close to the line of sight a thing must be to be the one looked at, in metres.
const AIM_SLACK := 0.55

signal added(id: int, kind: StringName, item: StringName, at: Vector3)
signal removed(id: int, by: StringName)

## Physics crates moved: `[id, at, rotation]` each (see [ZzCrates]); entries[id].at has followed already.
signal moved_many(batch: Array)

## The game (`zz_game.gd`), untyped: it preloads this file.
var game = null

## id -> {kind, item, at, until}
var entries: Dictionary = {}

## How far apart two dropped items lie, metres.
const SPACING := 0.9

var _next_id: int = 1
var _rng := RandomNumberGenerator.new()


func _init(p_game: Object) -> void:
	game = p_game
	_rng.seed = 911


func clear() -> void:
	for id: int in entries.keys():
		removed.emit(id, &"")

	entries.clear()


## Lays out what the map left lying about. A weapon or a box with no id is drawn at random.
func place_from_map(doc: Dictionary) -> void:
	_rng.seed = hash(str(doc.get("id", ""))) ^ int(game.round_number)

	for item: Dictionary in doc.get("items", []):
		var kind := StringName(str(item["kind"]))
		var what := StringName(str(item.get("id", "")))

		match kind:
			WEAPON:
				if what == &"" or not ZzWeapons.exists(what):
					what = ZzWeapons.random_of(&"primary", _rng, &"loot")
			THROWABLE:
				if what == &"" or not ZzWeapons.exists(what):
					what = ZzWeapons.random_of(&"thrown", _rng, &"loot")
			BOX:
				if what == &"" and game.boxes != null:
					what = game.boxes.random_type(&"map", _rng)

		var _id := add(kind, what, ZzMapDoc.v3(item["at"]))


## What a client is told [param item] is: a box's type only when `box_labels` is on.
func shown(kind: StringName, item: StringName) -> StringName:
	if kind == BOX and game.boxes != null:
		return game.boxes.shown_item(item)

	return item


func add(kind: StringName, item: StringName, at: Vector3, lifetime: float = -1.0, price: int = 0) -> int:
	var id := _next_id
	_next_id += 1
	if kind == WEAPON or kind == THROWABLE:
		item = ZzWeapons.resolve(item)
	# A drop never lands inside another one: two crates drawn through each other cannot be told apart or picked.
	if lifetime > 0.0:
		at = _clear_spot(at)
	entries[id] = {"kind": kind, "item": item, "at": at, "until": game.now() + lifetime if lifetime > 0.0 else -1.0, "price": price}
	added.emit(id, kind, item, at)
	return id


## [param at], or the nearest spot on a ring round it that is at least [constant SPACING] from every entry, has floor under it and no wall between it and [param at].
func _clear_spot(at: Vector3) -> Vector3:
	for ring in 4:
		for step in 8 if ring > 0 else 1:
			var angle := TAU * float(step) / 8.0 + float(ring) * 0.4
			var spot := at + Vector3(cos(angle), 0.0, sin(angle)) * SPACING * float(ring)

			if ring > 0:
				var up := Vector3(0.0, 0.5, 0.0)

				if game.ray_hit(at + up, spot + up) != Vector3.INF:
					continue

				var floor_at: Vector3 = game.ray_hit(spot + Vector3(0.0, 1.0, 0.0), spot + Vector3(0.0, -2.0, 0.0))

				if floor_at == Vector3.INF:
					continue

				spot = floor_at

			var free := true
			for other: Dictionary in entries.values():
				var there: Vector3 = other["at"]
				if Vector2(there.x - spot.x, there.z - spot.z).length() < SPACING and absf(there.y - spot.y) < 1.0:
					free = false
					break
			if free:
				return spot
	return at


func remove(id: int, by: StringName = &"") -> void:
	if entries.erase(id):
		removed.emit(id, by)


## What using entry [param id] costs in points (the shop's price; 0 is free).
func price_of(id: int) -> int:
	return int((entries[id] as Dictionary).get("price", 0)) if entries.has(id) else 0


func exists(id: int) -> bool:
	return entries.has(id)


func position_of(id: int) -> Vector3:
	return (entries[id] as Dictionary)["at"] if entries.has(id) else Vector3.INF


func kind_of(id: int) -> StringName:
	return (entries[id] as Dictionary)["kind"] if entries.has(id) else &""


func count_of(kind: StringName) -> int:
	var n := 0

	for id: int in entries:
		if (entries[id] as Dictionary)["kind"] == kind:
			n += 1

	return n


## The oldest entry of [param kind], or -1.
func oldest(kind: StringName) -> int:
	var best := -1

	for id: int in entries:
		if (entries[id] as Dictionary)["kind"] == kind and (best < 0 or id < best):
			best = id

	return best


## The entry nearest the line from [param eye] along [param aim], within [param reach]; -1 for none.
func looked_at(eye: Vector3, aim: Vector3, reach: float) -> int:
	var best := -1
	var best_score := INF

	for id: int in entries:
		var at: Vector3 = (entries[id] as Dictionary)["at"] + Vector3(0.0, 0.25, 0.0)
		var to := at - eye
		var along := to.dot(aim)

		if along < 0.0 or along > reach + 0.3:
			continue

		var off := (to - aim * along).length()

		if off > AIM_SLACK + along * 0.08:
			continue

		var score := off + along * 0.1

		if score < best_score and game.clear_between(eye, at + Vector3(0.0, 0.1, 0.0)):
			best_score = score
			best = id

	return best


## Seconds of holding E a thing takes: a box takes a moment, the rest none.
func use_seconds(id: int) -> float:
	# Carried, a box is picked up in a moment; it is the deploy that takes the time.
	if kind_of(id) == BOX and game.config.box_carry <= 0:
		return game.config.box_open_seconds

	return 0.0


## [param player] uses entry [param id].
func use(id: int, player) -> void:
	if not entries.has(id):
		return

	var e: Dictionary = entries[id]
	var item: StringName = e["item"]

	match e["kind"]:
		WEAPON, THROWABLE:
			if game.arm(player, item):
				# A gun picked up is drawn, as the genre does; a grenade is pocketed, or a
				# survivor who walked over one in a fight finds a grenade in their hand.
				if e["kind"] == WEAPON:
					game._draw(player, item)
				remove(id, player.player_id)
			elif game.arm_failure != "":
				game.refused.emit(player.player_id, game.arm_failure)
		AMMO:
			# A map's own pile stays for the next person; one a spawner laid or a shop prices is used up,
			# so it is charged and its site respawns it.
			var spent: bool = price_of(id) > 0 or e.has("fraction") or (game.spawners != null and game.spawners.lays(id))
			var filled := give_ammo(player, float(e.get("fraction", 1.0)))
			game.ammo_given.emit(player.player_id)
			if spent and filled > 0:
				remove(id, player.player_id)
		MEDKIT:
			if player.medkits >= 1:
				game.refused.emit(player.player_id, "You already have a medkit.")
				return
			player.medkits = 1
			remove(id, player.player_id)
		PILLS:
			if player.pills >= 1:
				game.refused.emit(player.player_id, "You already have pills.")
				return
			player.pills = 1
			remove(id, player.player_id)
		DEFIB:
			if player.defibs >= 1:
				game.refused.emit(player.player_id, "You already have a defibrillator.")
				return
			player.defibs = game.config.defib_charges
			remove(id, player.player_id)
		BACKPACK:
			if not game.wear_backpack(player, int(String(item))):
				return
			remove(id, player.player_id)
		BOX:
			if game.config.box_carry > 0:
				if not game.boxes.can_carry(player):
					game.refused.emit(player.player_id, "Your hands are full: deploy the box you have first.")
					return

				remove(id, player.player_id)
				var _held: bool = game.boxes.carry(player, item)
				return

			var at: Vector3 = e["at"]
			remove(id, player.player_id)
			game.boxes.open(item, player, at)


## Adds [param fraction] of every ammunition pool's cap [param player] carries (1: fills them).
static func give_ammo(player, fraction: float = 1.0) -> int:
	if player.weapons == null or player.weapons.arsenal == null:
		return 0

	var arsenal: DotWeaponArsenal = player.weapons.arsenal
	var total := 0

	for pool in arsenal.ammo().pools():
		total += arsenal.add_ammo(pool, maxi(ceili(arsenal.ammo().cap(pool) * fraction), 1))

	return total


func tick(_delta: float) -> void:
	var now: float = game.now()

	for id: int in entries.keys():
		var until := float((entries[id] as Dictionary)["until"])

		if until > 0.0 and now >= until:
			remove(id, &"")


func describe() -> Dictionary:
	var counts := {}

	for id: int in entries:
		var kind: StringName = (entries[id] as Dictionary)["kind"]
		counts[kind] = int(counts.get(kind, 0)) + 1

	return counts
