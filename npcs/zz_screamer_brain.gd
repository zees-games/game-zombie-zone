extends "zz_special_brain.gd"

## The screamer: keeps its distance, and when it has somebody in sight it stops, throws its head
## back and screams. Every common in earshot wakes, and a mob comes for whoever it saw.
##
## [codeblock]
## approach   to a spot scream_min..scream_range from the victim, in sight of them
## scream     stands still for scream_seconds; half way, the horde hears it
## retreat    then breaks line of sight and comes back for the next one
## [/codeblock]
##
## [b]It is a target, not a fight.[/b] Ninety health and no ability that hurts anybody: the
## scream is the attack, and a team that shoots it before it finishes has stopped the mob. So it
## screams from as far off as it can still be seen (a scream from behind a wall is a scream
## nobody knew to stop), and it does not wait for a good moment the way the others do: the mob
## IS the moment.

const SCREAM := &"scream"

var _heard: bool = false


func _victim_bonus(id: StringName, at: Vector3) -> float:
	# Whoever is in sight now, over whoever is nearest: the scream wants a witness.
	var eye := npc.position() + Vector3(0.0, 1.8, 0.0)
	return -15.0 if clear_line(eye, at + Vector3(0.0, 1.4, 0.0)) else 0.0


func _victim_allowed(id: StringName) -> bool:
	return survivor_is(id, &"alive")


func _special(_delta: float) -> void:
	var b := body()
	var gap := distance_to(victim)
	var reach := tune(&"scream_range", 35.0)
	var eye := npc.position() + Vector3(0.0, 1.8, 0.0)
	var target := survivor_at(victim) + Vector3(0.0, 1.4, 0.0)

	if state == SCREAM:
		halt()
		b.anim = ZzZombieBody.Anim.SCREAM
		face(target - eye)

		if not _heard and in_state_for() >= tune(&"scream_seconds", 1.6) * 0.5:
			_heard = true
			var h := horde()
			if h != null:
				h.call(&"scream", npc, victim, int(tune(&"scream_mob", 10.0)))
			cool_down(tune(&"scream_cooldown", 20.0))

		if in_state_for() >= tune(&"scream_seconds", 1.6):
			begin_retreat(5.0)
		return

	if cooled_down() and has_reacted() and gap <= reach and gap >= tune(&"scream_min", 9.0) \
			and clear_line(eye, target):
		_heard = false
		go(SCREAM)
		return

	# Spent, or nobody in sight: claw if cornered, else keep to the edge of sight.
	if claw_if_close(npc.def.move_speed, 2.0):
		return

	var spot := hidden_spot_near(victim, tune(&"scream_min", 9.0) + 4.0, reach - 6.0, cooled_down())
	go_to(spot if spot != Vector3.INF else survivor_at(victim), npc.def.move_speed, 1.0)
	b.anim = ZzZombieBody.Anim.RUN
