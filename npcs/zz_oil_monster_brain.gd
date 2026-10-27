extends "zz_special_brain.gd"

## The oil monster: slides on its own goo and leaves a trail of it that hurts and slows whoever stands in it,
## spits black goo that hurts, blinds the screen and leaves a puddle, and mauls what it reaches.
##
## [b]It never breaks off.[/b] It is a wall of hazard, not a sniper: it presses the team, spitting whenever the
## spit is ready and the line is clear, and the trail is why standing still near it is a mistake. The eat sequence
## for a last-down survivor is a later step; this brain only chases, spits and bites.

const SPIT := &"spit"

var _spit_at: float = INF


func _build() -> void:
	super()
	var h := horde()

	if h != null:
		h.call(&"configure_goo", npc.def.meta)


func _may_retreat() -> bool:
	return false


func _victim_allowed(id: StringName) -> bool:
	return survivor_is(id, &"alive")


func _decide(delta: float) -> void:
	super(delta)
	_leak()


## Drops a trail puddle where it is if it has moved; the pool decides the spacing.
func _leak() -> void:
	var b := body()
	var h := horde()

	if b == null or h == null or state == SPIT:
		return

	if Vector2(b.velocity.x, b.velocity.z).length() > 0.3:
		var _id = h.call(&"goo_trail", npc)


func _special(_delta: float) -> void:
	var b := body()
	var gap := distance_to(victim)
	var from := npc.position() + Vector3(0.0, 1.6, 0.0)
	var to := survivor_at(victim) + Vector3(0.0, 0.8, 0.0)

	if state == SPIT:
		halt()
		b.anim = ZzZombieBody.Anim.SPIT
		face(to - from)

		if _spit_at != INF and now() >= _spit_at:
			_spit_at = INF
			var speed := tune(&"spit_speed", 16.0)
			var aim := lead(victim, gap / speed)
			var h := horde()

			if h != null:
				h.call(&"projectile", &"goo_spit", from, launch_to(from, aim + Vector3(0.0, 0.8, 0.0), speed, 18.0), npc, tune(&"spit_damage", 8.0))

			cool_down(tune(&"spit_cooldown", 7.0))

		if in_state_for() > 1.0:
			go(APPROACH)
		return

	if cooled_down() and gap <= tune(&"spit_range", 26.0) and gap >= tune(&"spit_min", 5.0) and has_reacted() \
			and clear_line(from, to):
		_spit_at = now() + tune(&"spit_windup", 0.5)
		go(SPIT)
		return

	var at := survivor_at(victim)

	if at == Vector3.INF:
		return

	if gap <= tune(&"reach", 2.0) and absf(npc.position().y - at.y) < 1.6:
		halt()
		face(at - npc.position())
		b.anim = ZzZombieBody.Anim.ATTACK if swinging() else ZzZombieBody.Anim.IDLE
		var _swung := swing_at(victim)
	elif not swinging():
		chase_to(at, npc.def.move_speed)
		b.anim = ZzZombieBody.Anim.WALK


func _npc_died(by: StringName) -> void:
	super(by)
	var h := horde()

	if h != null:
		h.call(&"end_goo_trail", npc)


## State for the console and the probes.
func status() -> Dictionary:
	return {"state": String(state), "spitting": _spit_at != INF}
