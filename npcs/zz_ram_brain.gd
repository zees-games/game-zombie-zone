extends "zz_special_brain.gd"

## The ram: a charge in a straight line that carries the first survivor it meets and throws the
## rest aside, then beats its catch on the floor until it is killed. Nothing else frees them.
##
## [codeblock]
## approach   to somewhere with a clear, straight, walkable line to the victim
## wind-up    a roar and a lowered shoulder: half a second to get out of the way
## charge     straight, at charge_speed, for charge_seconds or until it hits a wall
## pummel     the catch on the floor, beaten
## [/codeblock]
##
## [b]Committed, which is its weakness.[/b] The direction is fixed when the charge starts; it
## does not steer. A survivor who sidesteps the wind-up watches it run past into a wall, and the
## ram that hit the wall stands stunned for a second. It likes a victim lined up with others
## behind them, because everybody near the line goes flying.

const WINDUP := &"windup"
const CHARGE := &"charge"
const STUNNED := &"stunned"

var _direction: Vector3 = Vector3.FORWARD
var _charge_from: Vector3 = Vector3.ZERO
var _last_at: Vector3 = Vector3.ZERO
var _knocked: Array[StringName] = []


func _may_retreat() -> bool:
	return false


func _victim_bonus(id: StringName, at: Vector3) -> float:
	# A clear straight line is everything to a ram.
	return 0.0 if clear_line(npc.position() + Vector3(0.0, 1.0, 0.0), at + Vector3(0.0, 1.0, 0.0)) else 25.0


func stagger(direction: Vector3, seconds: float, strength: float = 4.0) -> void:
	# A charging ram is not shoved; a standing one is, a little.
	if state == CHARGE:
		return

	super(direction, seconds * 0.5, strength * 0.5)


func _special(delta: float) -> void:
	var b := body()

	match state:
		WINDUP:
			halt()
			b.anim = ZzZombieBody.Anim.RAGE
			face(_direction)

			if in_state_for() >= 0.55:
				_charge_from = npc.position()
				_last_at = npc.position()
				_knocked.clear()
				go(CHARGE)
			return

		CHARGE:
			_charge(b, delta)
			return

		STUNNED:
			halt()
			b.anim = ZzZombieBody.Anim.STAGGER
			if in_state_for() > 1.2:
				go(APPROACH)
			return

	var gap := distance_to(victim)
	var at := survivor_at(victim)
	var reach := tune(&"charge_range", 26.0)

	if cooled_down() and gap >= tune(&"charge_min", 6.0) and gap <= reach and has_reacted() \
			and clear_line(npc.position() + Vector3(0.0, 1.0, 0.0), at + Vector3(0.0, 1.0, 0.0)) \
			and _walkable_line(npc.position(), at) and ready_to_strike(victim):
		var lead_at := lead(victim, gap / tune(&"charge_speed", 14.0) * 0.6)
		_direction = Vector3(lead_at.x - npc.position().x, 0.0, lead_at.z - npc.position().z).normalized()
		go(WINDUP)
		return

	if gap < 2.5:
		var _fought := melee_chase(npc.def.move_speed)
		return

	var spot := hidden_spot_near(victim, 8.0, 18.0)
	go_to(spot if spot != Vector3.INF else at, npc.def.move_speed, 1.0)
	b.anim = ZzZombieBody.Anim.RUN


func _walkable_line(a: Vector3, b: Vector3) -> bool:
	var h := horde()

	if h == null or h.spawner == null or h.spawner.nav == null:
		return true

	return h.spawner.nav.can_walk_straight(a, b)


func _charge(b: ZzZombieBody, delta: float) -> void:
	var speed := tune(&"charge_speed", 14.0)
	b.wish = _direction * speed
	b.anim = ZzZombieBody.Anim.CHARGE if horde().call(&"pinning", npc) == &"" else ZzZombieBody.Anim.CARRY
	var h := horde()
	var here := npc.position()

	for id in _survivors():
		if not survivor_is(id, &"alive") or _knocked.has(id):
			continue

		var at := survivor_at(id)

		if flat_distance(here + _direction * 0.6, at) > 1.5 or absf(at.y - here.y) > 1.5:
			continue

		_knocked.append(id)

		if h.call(&"pinning", npc) == &"" and survivor_is(id, &"up") and not survivor_is(id, &"pinned") \
				and bool(h.call(&"pin", npc, id, &"carry")):
			h.call(&"melee", npc, id, tune(&"impact_damage", 10.0))
		else:
			# Everybody else in the way goes flying.
			h.call(&"knock", id, here - _direction, tune(&"impact_damage", 10.0), npc)

	var moved := here.distance_to(_last_at)
	_last_at = here
	var blocked := in_state_for() > 0.25 and moved < speed * delta * 0.35

	if blocked or in_state_for() >= tune(&"charge_seconds", 2.6):
		halt()
		cool_down(tune(&"charge_cooldown", 12.0))
		var carrying: StringName = h.call(&"pinning", npc)

		if carrying != &"":
			# Into the wall with them, then the floor.
			if blocked:
				h.call(&"knock", carrying, here + _direction, tune(&"impact_damage", 10.0), npc)
			go(&"pummel")
		else:
			go(STUNNED if blocked else APPROACH)


func _holding(_delta: float) -> void:
	if state == CHARGE:
		_charge(body(), context.delta)
		return

	halt()
	body().anim = ZzZombieBody.Anim.PIN


func pin_released(released: StringName, why: StringName) -> void:
	super(released, why)
	go(APPROACH)
