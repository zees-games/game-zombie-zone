extends "zz_bots_base.gd"

## What a stand-in sees: the threat it picks among the zombies in sight, the points it aims at, and the crowd round it.

## The most dangerous zombie this bot can see: a special within reach first, then the nearest.
##
## [b]Scored first, looked at in order, and the first one seen wins[/b]: a sight line is a
## raycast, and a stand-in in front of a crowd of forty that tested each one it might prefer
## cast forty a tick. Asked again only every few ticks while the one it has is alive.
func _threat(player) -> GSNpcInstance:
	if game.horde == null:
		return null

	var memory := _memory(player)

	if player.flashed:
		memory["threat"] = null
		return null

	var held: Variant = memory.get("threat")

	# Nobody in sight is an answer too: kept as long as a sighting is.
	if game.current_tick() < int(memory.get("threat_until", 0)) \
			and (held == null or (held is GSNpcInstance and (held as GSNpcInstance).is_alive())):
		return held

	var eye: Vector3 = player.eye_position()
	var horde: Variant = game.horde

	if horde.threat_is_native():
		return _threat_native(player, memory, horde.ranked_threats(
				player.feet(), eye, game.config.bot_sight, game.config.bot_calm_radius))

	var near: Array = horde.zombies_near(player.feet(), game.config.bot_sight)
	# Sorted as one packed key (millimetres above, the index below) rather than with a lambda,
	# which was a script call per comparison: six thousand a frame at wave 7.
	var keys := PackedInt64Array()
	var calm_radius: float = game.config.bot_calm_radius
	var close_sq := calm_radius * calm_radius
	var feet: Vector3 = player.feet()
	var calm := true

	for i in near.size():
		var npc: GSNpcInstance = near[i]

		if calm and npc.position().distance_squared_to(feet) < close_sq:
			calm = false

		# The sleeper is left alone unless she is up.
		if npc.def.id == ZzNpcs.SLEEPER and npc.brain != null and str(npc.brain.get(&"state")) == "sitting":
			continue

		var score := _aim_point(npc).distance_to(eye)

		if ZzNpcs.is_special(npc.def.id):
			score -= 12.0

		keys.append((int((score + 64.0) * 1000.0) << 12) | i)

	keys.sort()
	var best: GSNpcInstance = null

	# The ten it would rather shoot, at most: past those, a crowd behind a wall is a crowd
	# behind a wall.
	for n in mini(keys.size(), 10):
		var npc: GSNpcInstance = near[keys[n] & 0xFFF]
		if _sees(player, _aim_point(npc)) or _sees(player, _head_point(npc)):
			best = npc
			break

	return _threat_noted(player, memory, best, calm)

## [method _threat] off gs-sim's ranking of [param ranked] (the ten it would rather shoot, best first).
func _threat_native(player, memory: Dictionary, ranked: Array[GSNpcInstance]) -> GSNpcInstance:
	var best: GSNpcInstance = null

	for npc in ranked:
		if _sees(player, _aim_point(npc)) or _sees(player, _head_point(npc)):
			best = npc
			break

	return _threat_noted(player, memory, best, game.horde.threat_calm)

## Keeps [param best] as [param player]'s threat for a few ticks, and whether nothing was near.
func _threat_noted(player, memory: Dictionary, best: GSNpcInstance, calm: bool) -> GSNpcInstance:
	memory["threat"] = best
	# Staggered by the stand-in's own seat, so a dozen do not all look on the same tick.
	memory["threat_until"] = game.current_tick() + 3 + (hash(String(player.player_id)) & 1)
	memory["calm_until"] = int(memory["threat_until"]) if calm and best == null else 0
	return best

## True while the last look found nothing in sight and no zombie within `bot_calm_radius`.
func is_calm(player) -> bool:
	return game.current_tick() < int(_memory(player).get("calm_until", 0))

func _aim_point(npc: GSNpcInstance) -> Vector3:
	var height := float(npc.def.meta.get("height", 1.7))
	return npc.position() + Vector3(0.0, height * 0.72, 0.0)

func _head_point(npc: GSNpcInstance) -> Vector3:
	var height := float(npc.def.meta.get("height", 1.7))
	return npc.position() + Vector3(0.0, height * 0.9, 0.0)

## Where to shoot [param npc] from [param player]'s eye: the chest, or the head when only the
## head shows (over a window's boards, a person aims there; aimed at the chest, every shot
## went into the planks and the crowd at the window was never thinned).
func _shot_point(player, npc: GSNpcInstance) -> Vector3:
	var chest := _aim_point(npc)
	if _sees(player, chest):
		return chest
	var head := _head_point(npc)
	return head if _sees(player, head) else chest

func _sees(player, at: Vector3) -> bool:
	# A flashed stand-in sees nothing; smoke stops sight the way it does for zombies.
	if player.flashed:
		return false

	var senses: Object = game.horde.senses if game.horde != null else null

	if senses != null and senses.sight_blocked(player.eye_position(), at):
		return false

	return game.clear_between(player.eye_position(), at)

func _crowd_within(player, reach: float) -> int:
	if game.horde == null:
		return 0

	if game.horde.threat_is_native():
		return game.horde.commons_near(player.feet(), reach)

	var n := 0

	for npc in game.horde.zombies_near(player.feet(), reach):
		if npc.is_alive() and npc.def.id == ZzNpcs.COMMON:
			n += 1

	return n
