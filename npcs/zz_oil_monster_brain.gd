extends "zz_special_brain.gd"

## The oil monster: slides on its own goo and leaves a trail of it that hurts and slows whoever stands in it,
## spits black goo that hurts, blinds the screen and leaves a puddle, and mauls what it reaches.
##
## [b]It never breaks off.[/b] It is a wall of hazard, not a sniper: it presses the team, spitting whenever the
## spit is ready and the line is clear, and the trail is why standing still near it is a mistake. A downed
## survivor under the health threshold is eaten (pin kind eat); damage to the monster breaks it off.

const ZzPins := preload("../game/zz_pins.gd")

const SPIT := &"spit"
const EAT := &"eat"

var _spit_at: float = INF
var _eat_victim: StringName = &""
var _eat_taken: float = 0.0
var _eat_at: float = 0.0


func _build() -> void:
	super()
	var h := horde()

	if h != null:
		h.call(&"configure_goo", npc.def.meta)


func _may_retreat() -> bool:
	return false


func _victim_allowed(id: StringName) -> bool:
	return survivor_is(id, &"alive") and (not survivor_is(id, &"pinned") or id == _eat_victim)


## A survivor on the floor and low enough is its meal: nearer than any standing one.
func _victim_bonus(id: StringName, _at: Vector3) -> float:
	return -60.0 if _edible(id) else 0.0


## Whether [param id] is down and under the profile's health threshold.
func _edible(id: StringName) -> bool:
	return tune(&"eat_enabled", 1.0) > 0.0 and survivor_is(id, &"down") and not survivor_is(id, &"pinned") \
		and horde() != null and float(horde().call(&"survivor_health", id)) <= tune(&"eat_health_below", 0.5)


## Damage it takes while eating counts toward breaking the meal off.
func damaged(amount: float, by: StringName) -> void:
	super(amount, by)

	if state == EAT:
		_eat_taken += amount


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

	if _try_eat():
		return

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
		b.anim = swing_anim() if swinging() else ZzZombieBody.Anim.IDLE
		var _swung := swing_at(victim)
	elif not swinging():
		chase_to(at, npc.def.move_speed)
		b.anim = ZzZombieBody.Anim.WALK


func _npc_died(by: StringName) -> void:
	super(by)
	var h := horde()

	if h != null:
		h.call(&"end_goo_trail", npc)


## Starts eating the chosen victim when they are edible and within reach. True when it did.
func _try_eat() -> bool:
	if not _edible(victim) or not cooled_down():
		return false

	var at := survivor_at(victim)

	if at == Vector3.INF or distance_to(victim) > tune(&"eat_reach", 2.2) or absf(npc.position().y - at.y) > 1.6:
		return false

	if not bool(horde().call(&"pin", npc, victim, &"eat")):
		return false

	_eat_victim = victim
	_eat_taken = 0.0
	_eat_at = now()
	face(at - npc.position())
	go(EAT)
	return true


## The meal: grab, lift, bite, swallow, by the pin's clock. Enough damage in time breaks it off.
func _holding(delta: float) -> void:
	if state != EAT:
		super(delta)
		return

	halt()
	var b := body()
	b.anim = ZzZombieBody.Anim.EAT
	var h := horde()
	var at := survivor_at(_eat_victim)

	if at != Vector3.INF:
		face(at - npc.position())

	if _eat_taken >= tune(&"eat_interrupt_damage", 150.0):
		h.call(&"unpin", npc)
		return

	var meta := npc.def.meta
	var phase: Dictionary = ZzPins.eat_phase(now() - _eat_at, meta)

	if bool(phase["done"]):
		h.call(&"eat_finished", npc, _eat_victim)
		_end_eat(tune(&"eat_cooldown", 4.0))


## The hold broke off (interrupted, or the victim died): back to chasing after a pause.
func pin_released(_victim: StringName, why: StringName) -> void:
	if state == EAT:
		_end_eat(tune(&"eat_cooldown", 4.0) if why != &"shoved" else 3.0)
		return

	super(_victim, why)


func _end_eat(cooldown: float) -> void:
	_eat_victim = &""
	_eat_taken = 0.0
	cool_down(cooldown)
	go(APPROACH)


## State for the console and the probes.
func status() -> Dictionary:
	return {"state": String(state), "spitting": _spit_at != INF, "eating": String(_eat_victim), "eat_damage": _eat_taken}
