extends "zz_special_brain.gd"

## The bloater: slow, soft, and the worst thing to let near the team. Its vomit blinds whoever it
## covers and calls every common in earshot to them; so does it bursting, which is why the genre's
## answer is a shove and a step back, not a shotgun at arm's length.
##
## [codeblock]
## lurk     out of sight AHEAD of the team, beside where it will walk: a corner, a doorway
## vomit    once two of them are in its cone (or one, if it is cornered)
## after    it is spent for vomit_cooldown: it backs off, or claws if it cannot
## [/codeblock]
##
## [b]Ambush, not approach.[/b] A bloater that walks at the team is shot at twenty metres and
## bursts harmlessly. One that waits round the corner the team is about to turn, and steps out
## when they are three metres away, is the one that covers all four. So it heads for a hidden
## spot near the victim and then WAITS there until somebody comes in range.
##
## Its burst on death is the game's (`ZzGame.on_zombie_died`), so it happens whatever killed it.

const LURK := &"lurk"
const VOMIT := &"vomit"

var _vomit_at: float = INF


func _victim_bonus(_id: StringName, at: Vector3) -> float:
	# The more of the team near the victim, the better: it wants a crowd, not a straggler. This
	# undoes most of the base's preference for loners.
	var h := horde()
	return -14.0 * float(int(h.call(&"survivors_near", at, 5.0))) if h != null else 0.0


func _may_retreat() -> bool:
	return false


func _special(_delta: float) -> void:
	var b := body()
	var reach := tune(&"vomit_range", 5.0)

	if state == VOMIT:
		halt()
		b.anim = ZzZombieBody.Anim.VOMIT

		if _vomit_at != INF and now() >= _vomit_at:
			_vomit_at = INF
			_spew(reach)

		if in_state_for() > 1.4:
			cool_down(tune(&"vomit_cooldown", 20.0))
			go(APPROACH)
		return

	var in_cone := _victims_in_cone(reach)

	if cooled_down() and has_reacted() and (in_cone.size() >= 2 or (in_cone.size() == 1 and distance_to(in_cone[0]) < 3.0)):
		_vomit_at = now() + 0.4
		go(VOMIT)
		return

	if not cooled_down():
		if not claw_if_close(npc.def.move_speed, 2.0):
			var away := hidden_spot_near(victim, 8.0, 18.0)
			if away != Vector3.INF:
				go_to(away, npc.def.move_speed, 1.0)
				b.anim = ZzZombieBody.Anim.WALK
			else:
				halt()
				b.anim = ZzZombieBody.Anim.IDLE
		return

	var gap := distance_to(victim)

	# Close and seen: turn to the nearest and spew at whoever is in front.
	if gap < reach * 1.4:
		go_to(survivor_at(victim), npc.def.move_speed, 0.8)
		b.anim = ZzZombieBody.Anim.WALK
		return

	# Lurk: get to a hidden spot near the victim, then wait for them to come round.
	var spot := hidden_spot_near(victim, 2.5, 9.0)

	if spot != Vector3.INF and flat_distance(npc.position(), spot) > 1.2:
		go_to(spot, npc.def.move_speed, 0.8)
		b.anim = ZzZombieBody.Anim.WALK
	elif spot != Vector3.INF:
		halt()
		b.anim = ZzZombieBody.Anim.IDLE
		go(LURK)
		# Lurking for too long with nobody coming: go and find them.
		if in_state_for() > 10.0:
			go_to(survivor_at(victim), npc.def.move_speed, 0.8)
	else:
		go_to(survivor_at(victim), npc.def.move_speed, 0.8)
		b.anim = ZzZombieBody.Anim.WALK


func _victims_in_cone(reach: float) -> Array[StringName]:
	var out: Array[StringName] = []
	var here := npc.position()
	var facing := npc.facing()
	var limit := cos(deg_to_rad(tune(&"vomit_half_angle", 28.0) + 15.0))

	for id in _survivors():
		var at := survivor_at(id)
		var to := at - here
		to.y = 0.0

		if to.length() > reach or not survivor_is(id, &"alive"):
			continue

		if to.length() > 0.5 and facing.dot(to.normalized()) < limit:
			continue

		if clear_line(here + Vector3(0.0, 1.5, 0.0), at + Vector3(0.0, 1.2, 0.0)):
			out.append(id)

	return out


func _spew(reach: float) -> void:
	var h := horde()

	if h == null:
		return

	# Turn to the middle of whoever is there, then everybody in the cone is covered.
	var hits := _victims_in_cone(reach + 0.5)

	for id in hits:
		h.call(&"bile", id, tune(&"bile_seconds", 15.0), npc)
