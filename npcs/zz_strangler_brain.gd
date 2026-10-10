extends "zz_special_brain.gd"

## The strangler: from cover across a street, a tongue round the last survivor in the line, who
## is dragged away from the rest and choked until somebody shoves them free or kills it.
##
## [codeblock]
## approach   to a spot in tongue range that the victim can see and the rest of the team
##            preferably cannot
## aim        a moment's stillness, which is the tell
## tongue     the tongue in flight (range / tongue_speed); it holds if the line is still clear
## pull       the victim dragged to it, then choked
## relocate   tongue broken: it moves somewhere else before it tries again
## [/codeblock]
##
## [b]It wants the one at the back[/b], which is the one the rest of the team is not looking
## at, and it wants to be out of the team's sight while still in the victim's. Once it has
## pulled it keeps its distance from the others: a strangler that held its ground while the team
## walked up and shoved their friend free would be a strangler nobody feared.

const AIM := &"aim"
const TONGUE := &"tongue"
const RELOCATE := &"relocate"

var _tongue_hits_at: float = INF
var _line_lost_since: float = -1.0


func _victim_bonus(id: StringName, at: Vector3) -> float:
	# The one furthest behind along the route is the one nobody is watching.
	var h := horde()
	if h == null or h.director == null or h.director.flow == null or not h.director.flow.has_route():
		return 0.0
	return h.director.flow.flow_of(at) * 0.4


func _special(_delta: float) -> void:
	var b := body()
	var gap := distance_to(victim)
	var reach := tune(&"tongue_range", 24.0)
	var from := npc.position() + Vector3(0.0, 1.7, 0.0)
	var to := survivor_at(victim) + Vector3(0.0, 1.2, 0.0)

	match state:
		TONGUE:
			b.anim = ZzZombieBody.Anim.TONGUE
			halt()
			face(to - from)

			if now() >= _tongue_hits_at:
				var h := horde()
				if clear_line(from, to) and gap <= reach + 2.0 and h != null and bool(h.call(&"pin", npc, victim, &"choke")):
					go(&"pulling")
				else:
					cool_down(4.0)
					go(RELOCATE)
			return

		AIM:
			halt()
			b.anim = ZzZombieBody.Anim.IDLE
			face(to - from)

			if not clear_line(from, to) or gap > reach:
				go(APPROACH)
			elif in_state_for() > 0.45 and has_reacted() and ready_to_strike(victim):
				_tongue_hits_at = now() + gap / tune(&"tongue_speed", 30.0)
				go(TONGUE)
			return

		RELOCATE:
			var away := hidden_spot_near(victim, 14.0, reach - 2.0)
			if away == Vector3.INF or flat_distance(npc.position(), away) < 1.5 or in_state_for() > 6.0:
				go(APPROACH)
			else:
				go_to(away, npc.def.move_speed, 1.0)
				b.anim = ZzZombieBody.Anim.RUN
			return

	if not cooled_down():
		# Waiting for its tongue: keep away, claw only if cornered.
		if not claw_if_close(npc.def.move_speed):
			var spot := hidden_spot_near(victim, 16.0, reach)
			if spot != Vector3.INF:
				go_to(spot, npc.def.move_speed, 1.0)
				b.anim = ZzZombieBody.Anim.RUN
			else:
				halt()
				b.anim = ZzZombieBody.Anim.IDLE
		return

	if gap <= reach and gap >= 5.0 and clear_line(from, to):
		go(AIM)
		return

	var spot := hidden_spot_near(victim, 10.0, reach - 2.0, true)
	go_to(spot if spot != Vector3.INF else survivor_at(victim), npc.def.move_speed, 1.0)
	b.anim = ZzZombieBody.Anim.RUN


func _holding(_delta: float) -> void:
	var b := body()
	halt()
	b.anim = ZzZombieBody.Anim.TONGUE
	var held: StringName = horde().call(&"pinning", npc)
	var at := survivor_at(held)

	if at == Vector3.INF:
		return

	face(at - npc.position())

	# The tongue needs a line. Round a corner for over a second and it snaps.
	if clear_line(npc.position() + Vector3(0.0, 1.7, 0.0), at + Vector3(0.0, 1.0, 0.0)):
		_line_lost_since = -1.0
	elif _line_lost_since < 0.0:
		_line_lost_since = now()
	elif now() - _line_lost_since > 1.2:
		horde().call(&"unpin", npc)


func pin_released(released: StringName, why: StringName) -> void:
	super(released, why)
	cool_down(tune(&"tongue_cooldown", 15.0))
	_line_lost_since = -1.0
	go(RELOCATE)
