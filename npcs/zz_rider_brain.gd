extends "zz_special_brain.gd"

## The rider: small, fast and low, it leaps onto a survivor's head and steers them — away from
## their friends, into the crowd, into the acid, off the edge.
##
## [b]The steering is the attack.[/b] Four damage a second is nothing; being walked away from
## the team, round a corner, into twenty commons, is everything. Each tick it is riding it picks
## a direction from three pulls: away from every other survivor, toward the nearest acid or fire,
## and toward the thickest crowd of commons. The victim fights back with nothing but their
## friends, who have to catch up and shove it off.

const LEAP := &"leap"
const RIDING := &"riding"

var _leapt_at: float = 0.0


func _special(_delta: float) -> void:
	var b := body()
	var gap := distance_to(victim)
	var reach := tune(&"leap_range", 6.0)

	if state == LEAP:
		b.anim = ZzZombieBody.Anim.LEAP

		if b.flying:
			if survivor_at(victim).distance_to(npc.position()) < 1.5:
				var h := horde()
				if h != null and bool(h.call(&"pin", npc, victim, &"ride")):
					b.flying = false
					b.velocity = Vector3.ZERO
					go(RIDING)
					return
		elif now() - _leapt_at > 0.25:
			cool_down(1.2)
			go(APPROACH)
		return

	if cooled_down() and gap <= reach and gap >= 1.2 and has_reacted() and ready_to_strike(victim) \
			and clear_line(npc.position() + Vector3(0.0, 0.8, 0.0), survivor_at(victim) + Vector3(0.0, 1.0, 0.0)):
		var speed := tune(&"leap_speed", 11.0)
		var target := lead(victim, gap / speed) + Vector3(0.0, 1.4, 0.0)
		b.leap(launch_to(npc.position(), target, speed, ZzZombieBody.GRAVITY))
		_leapt_at = now()
		go(LEAP)
		return

	# Low and quick, round to the victim's side or back.
	var spot := hidden_spot_near(victim, 3.0, 9.0)
	var goal := spot if spot != Vector3.INF and gap > reach else survivor_at(victim)
	go_to(goal, npc.def.move_speed, 0.9)
	b.anim = ZzZombieBody.Anim.CROUCH if gap < 14.0 else ZzZombieBody.Anim.RUN


## Riding: choose where to take them. Written into the body's wish, which the pin turns into
## the victim's velocity (see `ZzPins.steer`).
func _holding(_delta: float) -> void:
	var b := body()
	b.anim = ZzZombieBody.Anim.PIN
	var h := horde()
	var held: StringName = h.call(&"pinning", npc)
	var at := survivor_at(held)

	if at == Vector3.INF:
		return

	var pull := Vector3.ZERO

	# Away from help.
	for id in _survivors():
		if id == held:
			continue
		var away := at - survivor_at(id)
		away.y = 0.0
		var d := maxf(away.length(), 0.5)
		pull += away.normalized() * (12.0 / d)

	# Toward the crowd.
	var crowd := Vector3.ZERO
	var count := 0
	for other in h.spawner.npcs_near(at, 18.0):
		if other.def.id == &"common":
			crowd += other.position()
			count += 1
	if count > 0:
		var to_crowd := crowd / float(count) - at
		to_crowd.y = 0.0
		pull += to_crowd.normalized() * 0.8

	# Toward a hazard, which the game knows.
	var harm: Vector3 = h.game.nearest_hazard(at, 15.0)
	if harm != Vector3.INF:
		var to_harm := harm - at
		to_harm.y = 0.0
		pull += to_harm.normalized() * 1.5

	# A wobble, so it is not a straight line a teammate can predict and cut off.
	var wobble := DotNpcAiNode.deterministic_unit(npc.seed, int(now() * 2.0)) * TAU
	pull += Vector3(cos(wobble), 0.0, sin(wobble)) * 0.6

	if pull.length() < 0.01:
		b.wish = Vector3.ZERO
		return

	var steer_to := pull.normalized()
	var ahead: Vector3 = h.snap_to_nav(at + steer_to * 2.0) - at
	ahead.y = 0.0
	b.wish = (ahead.normalized() if ahead.length() > 0.2 else steer_to) * tune(&"ride_speed", 3.4)
	face(b.wish)


func pin_released(released: StringName, why: StringName) -> void:
	super(released, why)
	body().wish = Vector3.ZERO
	cool_down(tune(&"leap_cooldown", 6.0))
	begin_retreat(2.5)
