extends "zz_special_brain.gd"

## The mutant: a slow, heavy brute with a jetpack and two gravity guns. Each gun on its own either
## zaps a survivor or drags a loose map prop in, holds it and throws it. Hurt or maimed it gets
## angry: airborne, it charges up, dives onto the team and slams the ground.
##
## [b]Its weaknesses are its machinery.[/b] A gun shot off stops (and drops what it holds); the
## jetpack shot out falls it out of the sky and it never flies again. Parts are the body's
## [DotNpcLimbs] (`gunL`, `gunR`, `pack`), so a shot reaches them the way it reaches a limb.
##
## [b]Flight does not follow the navmesh.[/b] [DotNpcHover] flies straight at a goal; this brain
## raises the cruise height to clear the highest ground sampled along the way.

const WALK := &"walk"
const FLY := &"fly"
const CHARGE := &"charge"
const DIVE := &"dive"
const RECOVER := &"recover"

const GUNS: Array[StringName] = [&"gunL", &"gunR"]
## Local offsets of the gun muzzles from the feet (x is the side, z the front).
const MUZZLE := Vector3(0.8, 2.1, -0.4)

var hover := DotNpcHover.new()
var _guns: Array[Dictionary] = [{}, {}]
var _flight_until: float = -1.0
var _flight_ready_at: float = 0.0
var _dive_cool_until: float = 0.0
var _target_at: Vector3 = Vector3.ZERO
var _recover_until: float = 0.0
var _angry: bool = false
var _known_parts: int = 0
var _thrown: Array[Dictionary] = []
var _enraged_until: float = 0.0


func _build() -> void:
	super()
	hover.fuel_max = tune(&"fuel", 14.0)
	hover.fuel = hover.fuel_max
	hover.regen_rate = tune(&"fuel_regen", 1.4)
	hover.max_speed = tune(&"fly_speed", 8.0)
	hover.climb_speed = tune(&"climb_speed", 6.0)
	hover.cruise_height = tune(&"cruise_height", 7.0)
	for i in _guns.size():
		_guns[i] = {"mode": &"idle", "prop": null, "ready_at": now() + 1.0 + float(i), "until": 0.0, "beam_at": 0.0}
	go(WALK)


func _may_retreat() -> bool:
	return false


func _victim_allowed(id: StringName) -> bool:
	return survivor_is(id, &"alive")


func _part_gone(part: StringName) -> bool:
	var b := body()
	return b != null and b.limbs != null and b.limbs.is_severed(part)


func _decide(delta: float) -> void:
	var b := body()

	if b == null:
		return

	_watch_parts()
	_angry = npc.health_fraction() < tune(&"angry_health", 0.4) or _known_parts != 0 or now() < _enraged_until

	victim = choose_victim()

	if victim == &"":
		b.hovering = false
		if not melee_chase(npc.def.move_speed):
			halt()
			b.anim = ZzZombieBody.Anim.IDLE
		return

	var at := survivor_at(victim)

	if at == Vector3.INF:
		return

	_advance_props()

	match state:
		RECOVER:
			_recover(b)
		CHARGE:
			_charge(b, at, delta)
		DIVE:
			_dive(b, delta)
		FLY:
			_fly(b, at, delta)
			_work_guns(b, at)
		_:
			_walk(b, at, delta)
			_work_guns(b, at)


## Notices a part lost since the last think: a pack goes dark, a gun lets go of its prop.
func _watch_parts() -> void:
	var gone := 0

	for i in GUNS.size():
		if _part_gone(GUNS[i]):
			gone |= 1 << i
			_release(_guns[i])

	if _part_gone(&"pack"):
		gone |= 4

		if not hover.disabled():
			hover.disable()
			var b := body()
			if b != null:
				b.hovering = false
				b.hover_velocity = Vector3.ZERO
			if state in [FLY, CHARGE, DIVE]:
				go(WALK)

	_known_parts = gone


## Takes off now and stays angry for [param seconds] (a tool or test that wants the airborne look).
func take_flight(seconds: float = 30.0) -> void:
	_enraged_until = now() + seconds
	_flight_until = now() + seconds
	_flight_ready_at = 0.0
	hover.fuel = hover.fuel_max
	go(FLY)


# --- Walking ---------------------------------------------------------------------------------

func _walk(b: ZzZombieBody, at: Vector3, _delta: float) -> void:
	b.hovering = false
	var gap := flat_distance(npc.position(), at)
	var can_fly := not hover.disabled() and now() >= _flight_ready_at and hover.fuel >= hover.fuel_max * hover.relight_share
	var far := gap > tune(&"fly_from", 14.0) or at.y - npc.position().y > 3.0

	if can_fly and (far or (_angry and now() >= _dive_cool_until)):
		_flight_until = now() + tune(&"fly_time", 9.0)
		go(FLY)
		return

	if gap <= tune(&"reach", 1.8) and absf(npc.position().y - at.y) < 1.6:
		halt()
		face(at - npc.position())
		b.anim = ZzZombieBody.Anim.ATTACK if swinging() else ZzZombieBody.Anim.IDLE
		var _swung := swing_at(victim)
	elif not swinging():
		chase_to(at, npc.def.move_speed)
		b.anim = ZzZombieBody.Anim.WALK if b.anim != ZzZombieBody.Anim.ZAP else b.anim


# --- Flying ----------------------------------------------------------------------------------

func _ground_here() -> float:
	var h := horde()
	return float(h.call(&"ground_y", npc.position())) if h != null else npc.position().y


## Raises the cruise height to clear the highest ground sampled between here and [param goal].
func _clearance(goal: Vector3) -> float:
	var here := npc.position()
	var base := _ground_here()
	var top := base
	var h := horde()

	for t: float in [0.33, 0.66, 1.0]:
		var p := here.lerp(goal, t)
		top = maxf(top, float(h.call(&"ground_y", p)) if h != null else p.y)

	return clampf(top - base + tune(&"cruise_height", 7.0), tune(&"cruise_height", 7.0), 40.0)


func _fly(b: ZzZombieBody, at: Vector3, delta: float) -> void:
	var here := npc.position()
	var standoff := 0.0 if _angry else tune(&"standoff", 11.0)
	var flat := Vector3(at.x - here.x, 0.0, at.z - here.z)
	var goal := at if flat.length() <= standoff else here + flat.normalized() * (flat.length() - standoff)
	hover.burn_rate = 1.0
	hover.cruise_height = _clearance(goal) + (tune(&"charge_height", 12.0) - tune(&"cruise_height", 7.0) if _angry else 0.0)
	var wants := now() < _flight_until and not hover.disabled()
	var v := hover.step(delta, here, goal, _ground_here(), wants)
	b.hovering = hover.airborne()
	b.hover_velocity = v
	b.wish = Vector3.ZERO
	face(at - here)
	b.anim = ZzZombieBody.Anim.FLY

	var up := hover.state == DotNpcHover.State.CRUISE or hover.state == DotNpcHover.State.HOVER

	if _angry and up and now() >= _dive_cool_until and here.y - _ground_here() > 6.0:
		go(CHARGE)
		return

	if hover.state == DotNpcHover.State.GROUNDED and not wants:
		b.hovering = false
		_flight_ready_at = now() + tune(&"fly_rest", 4.0)
		go(WALK)


func _charge(b: ZzZombieBody, at: Vector3, delta: float) -> void:
	b.anim = ZzZombieBody.Anim.CHARGE_UP
	b.wish = Vector3.ZERO
	var here := npc.position()
	b.hover_velocity = b.hover_velocity.move_toward(Vector3(0.0, 1.5, 0.0), 12.0 * delta)
	face(at - here)
	_target_at = at

	if in_state_for() >= tune(&"charge_time", 1.4):
		go(DIVE)


func _dive(b: ZzZombieBody, _delta: float) -> void:
	b.anim = ZzZombieBody.Anim.DIVE
	var here := npc.position()
	var to := _target_at - here
	b.hover_velocity = to.normalized() * tune(&"dive_speed", 26.0)
	var low := here.y - _ground_here() < 1.4 or to.length() < 1.6
	var stuck := in_state_for() > 0.3 and b.velocity.length() < 2.0
	var h := horde()

	if low or stuck or in_state_for() > 4.0:
		b.hover_velocity = Vector3.ZERO
		b.hovering = false
		hover.state = DotNpcHover.State.GROUNDED
		hover.fuel = 0.0
		if h != null:
			var _n = h.call(&"slam", npc, here, tune(&"slam_radius", 7.0), tune(&"slam_damage", 30.0))
		_recover_until = now() + tune(&"slam_recover", 3.0)
		_dive_cool_until = now() + tune(&"dive_cooldown", 8.0)
		go(RECOVER)


func _recover(b: ZzZombieBody) -> void:
	halt()
	b.anim = ZzZombieBody.Anim.SLAM

	if now() >= _recover_until:
		go(WALK)


# --- Gravity guns ----------------------------------------------------------------------------

func _muzzle(slot: int) -> Vector3:
	var b := body()
	var side := MUZZLE.x * (1.0 if slot == 0 else -1.0)
	return b.global_transform * Vector3(side, MUZZLE.y, MUZZLE.z)


func _work_guns(b: ZzZombieBody, at: Vector3) -> void:
	if state == RECOVER or swinging():
		return

	for slot in _guns.size():
		if _part_gone(GUNS[slot]):
			continue

		var gun := _guns[slot]
		match gun["mode"]:
			&"pull":
				_pull(slot, gun)
			&"hold":
				_hold(slot, gun, at)
			_:
				if now() >= float(gun["ready_at"]):
					_choose_use(slot, gun, b, at)


func _choose_use(slot: int, gun: Dictionary, b: ZzZombieBody, at: Vector3) -> void:
	var h := horde()
	var from := _muzzle(slot)
	var chest := at + Vector3(0.0, 1.1, 0.0)

	if h == null or not clear_line(from, chest):
		gun["ready_at"] = now() + 0.6
		return

	var taken: Array = []
	for g in _guns:
		if g["prop"] != null:
			taken.append(g["prop"])
	for t in _thrown:
		taken.append(t["prop"])

	var gap := from.distance_to(chest)
	var prop: RigidBody3D = null

	if _rand() < tune(&"prop_chance", 0.5):
		prop = h.call(&"loose_prop_near", npc.position() + Vector3(0.0, 1.0, 0.0), tune(&"prop_range", 14.0), tune(&"prop_mass", 40.0), taken)

	if prop != null and gap <= tune(&"throw_range", 30.0):
		gun["mode"] = &"pull"
		gun["prop"] = prop
		gun["until"] = now() + tune(&"pull_time", 3.0)
		b.anim = ZzZombieBody.Anim.ZAP
		return

	if gap <= tune(&"zap_range", 24.0):
		h.call(&"beam", &"beam_zap", from, chest)
		h.call(&"melee", npc, victim, tune(&"zap_damage", 4.0))
		gun["ready_at"] = now() + tune(&"zap_interval", 2.5) * (0.8 + 0.4 * _rand())
		b.anim = ZzZombieBody.Anim.ZAP
	else:
		gun["ready_at"] = now() + 1.0


## Drags the prop to just in front of the gun.
func _pull(slot: int, gun: Dictionary) -> void:
	var rb: RigidBody3D = gun["prop"]

	if rb == null or not is_instance_valid(rb) or now() > float(gun["until"]):
		_release(gun)
		return

	var hold := _hold_point(slot)
	var to := hold - rb.global_position
	rb.sleeping = false
	rb.linear_velocity = to.normalized() * minf(tune(&"pull_speed", 14.0), to.length() * 6.0 + 2.0)

	if now() - float(gun["beam_at"]) > 0.2:
		gun["beam_at"] = now()
		var h := horde()
		if h != null:
			h.call(&"beam", &"beam_pull", _muzzle(slot), rb.global_position)

	if to.length() < 0.9:
		gun["mode"] = &"hold"
		gun["until"] = now() + tune(&"hold_time", 1.0)


func _hold_point(slot: int) -> Vector3:
	var b := body()
	var side := 0.9 * (1.0 if slot == 0 else -1.0)
	return b.global_transform * Vector3(side, 2.7, -1.2)


func _hold(slot: int, gun: Dictionary, at: Vector3) -> void:
	var rb: RigidBody3D = gun["prop"]

	if rb == null or not is_instance_valid(rb):
		_release(gun)
		return

	rb.sleeping = false
	rb.linear_velocity = (_hold_point(slot) - rb.global_position) * 8.0

	if now() < float(gun["until"]):
		return

	var chest := at + Vector3(0.0, 1.1, 0.0)
	var speed := tune(&"throw_speed", 22.0)
	rb.linear_velocity = launch_to(rb.global_position, chest, speed, 20.0)
	_thrown.append({"prop": rb, "until": now() + 3.0, "victim": victim})
	gun["mode"] = &"idle"
	gun["prop"] = null
	gun["ready_at"] = now() + tune(&"throw_interval", 4.0)


## Lets go of whatever the gun holds; it falls where it is.
func _release(gun: Dictionary) -> void:
	if gun.get("mode", &"idle") != &"idle":
		gun["ready_at"] = now() + 2.0

	gun["mode"] = &"idle"
	gun["prop"] = null


## A thrown prop that reaches a survivor hurts them once.
func _advance_props() -> void:
	var i := _thrown.size() - 1

	while i >= 0:
		var t := _thrown[i]
		var rb: RigidBody3D = t["prop"]
		var done := rb == null or not is_instance_valid(rb) or now() > float(t["until"])

		if not done:
			for id in _survivors():
				var at := survivor_at(id)
				if at != Vector3.INF and rb.global_position.distance_to(at + Vector3(0.0, 1.0, 0.0)) < tune(&"prop_hit_radius", 1.4) \
						and rb.linear_velocity.length() > 4.0:
					var h := horde()
					if h != null:
						h.call(&"melee", npc, id, tune(&"throw_damage", 8.0))
					done = true
					break

		if done:
			_thrown.remove_at(i)

		i -= 1


func _rand() -> float:
	return DotNpcAiNode.deterministic_unit(npc.seed, int(now() * 10.0) + 17)


## State for the console and the probes.
func status() -> Dictionary:
	return {
		"state": String(state), "angry": _angry, "fuel": snappedf(hover.fuel, 0.1),
		"hover": DotNpcHover.State.keys()[hover.state], "parts": _known_parts,
		"guns": [String(_guns[0]["mode"]), String(_guns[1]["mode"])],
	}
