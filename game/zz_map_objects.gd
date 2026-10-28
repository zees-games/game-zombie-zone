extends RefCounted

const ZzLoot := preload("zz_loot.gd")

## What a map's `spawn_object` event (a breakable's `spawnobject` key) may leave lying. The key is untrusted map data: only
## the numbers below do anything, each lays one ordinary loot entry, and the counts are capped.

## spawnobject -> [loot kind, ammo fraction]. The list is the breakable's menu in the order the map editor shows it: 2 a
## health kit, 3 to 9 the ammunition boxes. Everything else (a battery, a weapon, an out-of-range number) does nothing.
const OBJECTS := {
	2: [ZzLoot.MEDKIT, 1.0],
	3: [ZzLoot.AMMO, 0.2], 4: [ZzLoot.AMMO, 0.4],
	5: [ZzLoot.AMMO, 0.25], 6: [ZzLoot.AMMO, 0.45],
	7: [ZzLoot.AMMO, 0.25], 8: [ZzLoot.AMMO, 0.45],
	9: [ZzLoot.AMMO, 0.3],
}

## Most map-made pieces lying at once, and in a round.
const MAX_LYING := 12
const MAX_PER_ROUND := 48
## Seconds a piece lies before it is swept up.
const LIFETIME := 120.0
## A drop further than this from the origin is a bad coordinate, not a place.
const MAX_REACH := 20000.0

var game = null

var _lying: Array[int] = []
var _made := 0


func _init(p_game: Object) -> void:
	game = p_game


## A new round: the count starts again.
func reset() -> void:
	_lying.clear()
	_made = 0


## Lays the piece [param object] names at [param at]; returns the loot id, or -1 when it is not on the list, the caps are met or the place is nonsense.
func spawn(object: int, at: Vector3) -> int:
	if not OBJECTS.has(object) or game == null or game.loot == null:
		return -1

	if not (is_finite(at.x) and is_finite(at.y) and is_finite(at.z)) or at.length() > MAX_REACH:
		return -1

	var loot = game.loot
	_lying = _lying.filter(func(i: int) -> bool: return loot.exists(i))

	if _lying.size() >= MAX_LYING or _made >= MAX_PER_ROUND:
		return -1

	var rule: Array = OBJECTS[object]
	var ground: Vector3 = game.ray_hit(at + Vector3(0.0, 0.5, 0.0), at + Vector3(0.0, -3.0, 0.0))
	var id: int = loot.add(rule[0], &"", ground if ground != Vector3.INF else at, LIFETIME)

	if rule[0] == ZzLoot.AMMO:
		loot.entries[id]["fraction"] = float(rule[1])

	_lying.append(id)
	_made += 1
	return id
