extends RefCounted

## The game's end of zz-historical-monsters' host seam (`spawner.set_meta(&"zhm_host", host)`): who a monster may
## hunt, how its blows land and what it afflicts. Every blow goes through the game (`ZzGame.zombie_hit` /
## `knock_survivor`), so the difficulty scale, the down, the stats and the team rules apply as to any zombie.
## Server only. No `class_name`: a mounted pack calls it by method name.

const ZzController := preload("zz_controller.gd")

## Blows that throw the victim; the rest are plain bites.
const KNOCKING: Array[StringName] = [&"tail", &"slam", &"charge", &"pounce", &"maul"]
## Afflictions that hold a survivor back for their length (bleed arrives as the monster's own damage ticks).
const SLOWING: Array[StringName] = [&"stun", &"slow"]

var horde: Object = null
## victim -> game time the slow ends.
var _slowed: Dictionary = {}


func _init(p_horde: Object = null) -> void:
	horde = p_horde


## Every living, targetable survivor as `{id, position}`.
func zhm_targets() -> Array:
	var out: Array = []
	if horde == null:
		return out
	for id: StringName in horde.survivor_ids():
		var at: Vector3 = horde.survivor_position(id)
		if at != Vector3.INF:
			out.append({"id": id, "position": at})
	return out


func zhm_hit(npc: Object, victim: StringName, amount: float, kind: StringName, info: Dictionary) -> void:
	if horde == null or npc == null or amount <= 0.0 or not horde.survivor_alive(victim):
		return
	if kind in KNOCKING and info.has("source"):
		horde.knock(victim, info["source"], amount, npc)
	else:
		horde.melee(npc, victim, amount)


func zhm_status(victim: StringName, st: StringName, seconds: float, _info: Dictionary) -> void:
	if st in SLOWING and horde != null and horde.survivor_alive(victim):
		_slowed[victim] = maxf(float(_slowed.get(victim, 0.0)), horde.game.now() + seconds)


## Once a tick: keeps the slowed survivors slowed until their time is up.
func tick() -> void:
	if _slowed.is_empty():
		return
	var now: float = horde.game.now()
	for victim: StringName in _slowed.keys():
		var player: Object = horde.game.player_by_id(victim)
		if now >= float(_slowed[victim]) or player == null or not player.is_alive():
			_slowed.erase(victim)
		elif player.is_up():
			var _on: Variant = player.controller.add_modifier(ZzController.TAGGED)


func slowed(victim: StringName) -> bool:
	return _slowed.has(victim)
