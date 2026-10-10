extends "zz_special_brain.gd"

## The spitter: lobs a glob that becomes a spreading pool of acid where it lands, and hurts more
## the longer anybody stands in it. Then it runs.
##
## [b]It spits where people cannot leave.[/b] A survivor who is pinned or down cannot step out of
## the pool, and a teammate kneeling to revive them or shoving their special off has to stand in
## it to do so; that is the spitter's whole game, and its victim scoring says so. Failing that it
## spits into the thickest knot of the team, or at a doorway they are holding.
##
## Spit and run: a spitter that stood and watched its pool would die in it. It breaks line of
## sight after every spit and comes back from somewhere else.

const SPIT := &"spit"

var _spit_at: float = INF


func _victim_allowed(id: StringName) -> bool:
	return survivor_is(id, &"alive")


func _victim_bonus(id: StringName, at: Vector3) -> float:
	var bonus := 0.0

	if survivor_is(id, &"pinned") or survivor_is(id, &"down"):
		bonus -= 40.0

	var h := horde()
	if h != null:
		# Everybody near them is somebody else in the pool; this undoes the loner preference.
		bonus -= 16.0 * float(int(h.call(&"survivors_near", at, 4.0, id)))

	return bonus


func _special(_delta: float) -> void:
	var b := body()
	var gap := distance_to(victim)
	var reach := tune(&"spit_range", 28.0)
	var from := npc.position() + Vector3(0.0, 1.7, 0.0)
	var to := survivor_at(victim) + Vector3(0.0, 0.5, 0.0)

	if state == SPIT:
		halt()
		b.anim = ZzZombieBody.Anim.SPIT
		face(to - from)

		if _spit_at != INF and now() >= _spit_at:
			_spit_at = INF
			var speed := tune(&"spit_speed", 15.0)
			var aim := lead(victim, gap / speed)
			var h := horde()
			if h != null:
				h.call(&"projectile", &"spit", from, launch_to(from, aim, speed, 18.0), npc, tune(&"acid_damage", 6.0))
			cool_down(tune(&"spit_cooldown", 18.0))

		if in_state_for() > 0.9:
			begin_retreat(4.0)
		return

	if cooled_down() and gap <= reach and gap >= tune(&"spit_min", 6.0) and has_reacted() \
			and clear_line(from, to + Vector3(0.0, 1.0, 0.0)):
		_spit_at = now() + 0.45
		go(SPIT)
		return

	if not cooled_down():
		if not claw_if_close(npc.def.move_speed, 2.0):
			var away := hidden_spot_near(victim, 14.0, reach)
			if away != Vector3.INF:
				go_to(away, npc.def.move_speed, 1.0)
				b.anim = ZzZombieBody.Anim.RUN
			else:
				halt()
				b.anim = ZzZombieBody.Anim.IDLE
		return

	var spot := hidden_spot_near(victim, 10.0, reach - 4.0)
	go_to(spot if spot != Vector3.INF else survivor_at(victim), npc.def.move_speed, 1.0)
	b.anim = ZzZombieBody.Anim.RUN
