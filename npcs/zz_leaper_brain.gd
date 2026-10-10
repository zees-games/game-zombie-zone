extends "zz_special_brain.gd"

## The leaper: crouches somewhere nobody is looking, then jumps from up to twenty metres and pins
## whoever it lands on until somebody shoves it off or kills it.
##
## [codeblock]
## approach   crouch-run to a hidden spot pounce_min..pounce_max from the victim
## wait       crouched, coiled: until the victim looks away or the team is busy
## pounce     a ballistic leap at where the victim will be; anybody it passes within a
##            metre and a bit of on the way is who it lands on
## recover    missed: a second on the ground, then it tries again
## [/codeblock]
##
## [b]It prefers a victim facing away[/b], because a pounce seen coming is a pounce shoved out of
## the air, and [b]it prefers height[/b]: from a roof a pounce comes down onto the team rather
## than across the street at them.

const POUNCE := &"pounce"
const COIL := &"coil"
const RECOVER := &"recover"

var _launched_at: float = 0.0


func _victim_bonus(id: StringName, at: Vector3) -> float:
	# Looking away is worth ten metres.
	var facing := _facing_of(id)
	var to_me := npc.position() - at
	to_me.y = 0.0

	if facing != Vector3.ZERO and to_me.length() > 0.1 and facing.dot(to_me.normalized()) < 0.2:
		return -10.0

	return 0.0


func _facing_of(id: StringName) -> Vector3:
	var h := horde()
	if h == null:
		return Vector3.ZERO
	var player = h.game.player_by_id(id)
	return player.aim_direction() if player != null else Vector3.ZERO


func _special(_delta: float) -> void:
	var b := body()
	var gap := distance_to(victim)
	var near := tune(&"pounce_min", 4.0)
	var far := tune(&"pounce_max", 22.0)

	match state:
		POUNCE:
			b.anim = ZzZombieBody.Anim.LEAP

			if b.flying:
				# Whoever it passes close enough to on the way is who it gets.
				for id in _survivors():
					if survivor_is(id, &"up") and not survivor_is(id, &"pinned") \
							and survivor_at(id).distance_to(npc.position()) < 1.4:
						var h := horde()
						if h != null and bool(h.call(&"pin", npc, id, &"pounce")):
							b.flying = false
							b.velocity = Vector3.ZERO
							go(&"pinned")
							return
			elif now() - _launched_at > 0.2:
				go(RECOVER)
			return

		RECOVER:
			halt()
			b.anim = ZzZombieBody.Anim.CROUCH
			if in_state_for() > 1.0:
				go(APPROACH)
			return

		COIL:
			halt()
			b.anim = ZzZombieBody.Anim.CROUCH
			face(survivor_at(victim) - npc.position())

			if gap < near * 0.6 or gap > far * 1.15:
				go(APPROACH)
			elif in_state_for() > 0.6 and cooled_down() and has_reacted() and ready_to_strike(victim) \
					and clear_line(npc.position() + Vector3(0.0, 1.0, 0.0), survivor_at(victim) + Vector3(0.0, 1.0, 0.0)):
				_pounce()
			return

	# Approach: crouched, quick, out of sight.
	if gap >= near and gap <= far and in_state_for() > 0.3 \
			and clear_line(npc.position() + Vector3(0.0, 1.0, 0.0), survivor_at(victim) + Vector3(0.0, 1.0, 0.0)):
		go(COIL)
		return

	var spot := hidden_spot_near(victim, near + 2.0, far - 4.0)
	var goal := spot if spot != Vector3.INF else survivor_at(victim)
	go_to(goal, tune(&"stalk_speed", 3.2) if gap < far * 1.5 else npc.def.move_speed, 1.0)
	b.anim = ZzZombieBody.Anim.CROUCH if gap < far * 1.5 else ZzZombieBody.Anim.RUN


func _pounce() -> void:
	var b := body()
	var speed := tune(&"pounce_speed", 16.0)
	var target := lead(victim, distance_to(victim) / speed) + Vector3(0.0, 0.6, 0.0)
	b.leap(launch_to(npc.position(), target, speed, ZzZombieBody.GRAVITY))
	b.anim = ZzZombieBody.Anim.LEAP
	_launched_at = now()
	cool_down(1.5)
	go(POUNCE)


func _holding(_delta: float) -> void:
	halt()
	body().anim = ZzZombieBody.Anim.PIN


func pin_released(released: StringName, why: StringName) -> void:
	super(released, why)
	go(RECOVER)
