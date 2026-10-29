extends RefCounted

const ZzLoot := preload("zz_loot.gd")
const ZzWeapons := preload("zz_weapons.gd")

## The drop-weapon key (Q): the weapon in hand lies in front of the survivor as a [ZzLoot] weapon
## that keeps its magazine and reserve, and is picked up with E like any other. Server only; the
## client sends a bit and nothing more.

const CHANNEL := "zz.weapon_drop"

## Slot 1 is the melee weapon, which a survivor never puts down.
const KEEP_SLOTS: Array[int] = [1]

## How far in front of the feet it lands, metres.
const REACH := 1.1

## `zz_weapon_drop`: whether Q does anything.
var enabled: bool = true
## `zz_weapon_drop_seconds`: how long a dropped weapon lies before it goes.
var lifetime: float = 120.0
## `zz_weapon_drop_max`: how many dropped weapons may lie; the oldest goes first.
var max_lying: int = 64
## Why the last [method drop] refused ("" for a silent refusal).
var refusal: String = ""

var game = null


func _init(p_game: Object) -> void:
	game = p_game


## Registers the three cvars ([param add] is the module's `add_cvar`).
func bind_cvars(add: Callable, flags: int = 0) -> void:
	_bind(add, "zz_weapon_drop", "1" if enabled else "0", "Let survivors drop the weapon in hand (0 or 1)", flags,
		func(v: String) -> void: enabled = v.strip_edges() != "0")
	_bind(add, "zz_weapon_drop_seconds", str(lifetime), "Seconds a dropped weapon lies before it goes", flags,
		func(v: String) -> void: lifetime = maxf(v.to_float(), 1.0))
	_bind(add, "zz_weapon_drop_max", str(max_lying), "Most dropped weapons lying at once; the oldest goes first", flags,
		func(v: String) -> void: max_lying = maxi(v.to_int(), 0))


func _bind(add: Callable, name: String, value: String, help: String, flags: int, apply: Callable) -> void:
	var made: Variant = add.call(name, value, help, flags)

	if not (made is Object):
		return

	var cv := made as Object
	apply.call(String(cv.call(&"get_string")))
	cv.connect(&"changed", func(_old: Variant, new_value: Variant) -> void: apply.call(str(new_value)))


## [param player] drops the weapon in hand. True if one landed.
func drop(player) -> bool:
	refusal = ""

	if not enabled or game.loot == null or player.weapons == null or player.weapons.arsenal == null:
		return false

	if player.is_down() or not player.is_alive():
		return false

	var arsenal: DotWeaponArsenal = player.weapons.arsenal
	var state := arsenal.drop_current(KEEP_SLOTS)

	if state.is_empty():
		return false

	var id := StringName(state["id"])
	var _laid: int = game.loot.add(ZzLoot.WEAPON, id, _spot(player), lifetime, 0, state)
	game.loot.trim_dropped(max_lying)
	player.wanted_slot = arsenal.current_slot()
	DotLog.debug(CHANNEL, "dropped", {"player": String(player.player_id), "weapon": String(id), "magazine": state["magazine"]})
	return true


## In front of the feet, stopped short of a wall, on the floor beneath.
func _spot(player) -> Vector3:
	var forward: Vector3 = player.aim_direction()
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	var from: Vector3 = player.feet() + Vector3(0.0, 0.8, 0.0)
	var to := from + forward * REACH
	var wall: Vector3 = game.ray_hit(from, to)

	if wall != Vector3.INF:
		to = from + forward * maxf(from.distance_to(wall) - 0.3, 0.0)

	var floor_at: Vector3 = game.ray_hit(to + Vector3(0.0, 0.5, 0.0), to + Vector3(0.0, -3.0, 0.0))
	return floor_at if floor_at != Vector3.INF else player.feet()
