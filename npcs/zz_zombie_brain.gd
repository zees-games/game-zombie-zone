extends "res://addons/dot_npc_ai/runtime/dot_npc_ai_brain.gd"

const ZzZombieBody := preload("zz_zombie_body.gd")

## What every zombie's mind shares: the horde it reports to, the body it moves, a swing that
## lands half a second after it starts, a stagger when shoved, and a target it may be given
## rather than have to find.
##
## [b]Extended by PATH rather than by name[/b] (the `extends` above), because a brain in a
## mounted dot-cloud pack cannot resolve a `class_name`. The same goes for every brain under
## `npcs/`.
##
## [b]No behaviour tree.[/b] dot-npc-ai's notes say it plainly: "a zombie has four states", and a
## tree for four states is a state machine with extra steps and worse debugging. Each kind's
## brain is a hand-written machine in [method _decide]; what this class takes from dot-npc-ai is
## everything round the decision — the memory that forgets, the squad's attack slots and its
## ring round a survivor's back, what it can hear, its reaction time and turn rate — which is
## the part that took that addon's suite three hundred checks to get right.
##
## [b]Steering writes a wish; the body moves.[/b] See [ZzZombieBody]. dot-npc's own
## `steer_toward` moves the body itself, once per call; overridden here so steering, a shove
## and gravity are one move a tick.

## The swing: how long from starting it to the hit landing, and to being able to swing again.
const SWING_WINDUP := 0.32
const SWING_RECOVER := 0.55

## Where the horde publishes itself on the spawner, so a brain built from a path can reach it.
const HORDE_META := &"zz_horde"

## What the brain is doing, for a describe() and for a subclass's own machine.
var state: StringName = &"idle"
var state_since: float = 0.0

## A survivor this zombie was GIVEN — a mob's, bile's, a special's choice — as a candidate id.
## Chased whether or not it can be perceived. Empty when it has none.
var forced: StringName = &""

## A place to go regardless of survivors: a beeping thing, a noise. INF when none.
var lure: Vector3 = Vector3.INF

## Staggered until, in simulated seconds.
var stagger_until: float = -1.0

## The swing in progress: when it started (INF when none), at whom, and whether it has landed.
var _swing_at: float = INF
var _swing_victim: StringName = &""
var _swing_landed: bool = false
var _next_swing: float = 0.0

var _horde: Object = null


func _npc_ready() -> void:
	super()
	state_since = context.now if context != null else 0.0


## The horde this zombie belongs to. Duck-typed: see `zz_horde.gd`.
func horde() -> Object:
	if _horde == null and director != null and director.has_meta(HORDE_META):
		_horde = director.get_meta(HORDE_META)

	return _horde


func body() -> ZzZombieBody:
	return npc.node as ZzZombieBody if npc != null else null


func now() -> float:
	return context.now if context != null else 0.0


func go(next: StringName) -> void:
	if next == state:
		return

	state = next
	state_since = now()


func in_state_for() -> float:
	return now() - state_since


# --- Moving ----------------------------------------------------------------------------------

## Overridden: steering writes the body's wish rather than moving it. See the class notes.
func steer_toward(to: Vector3, speed: float, _delta: float) -> void:
	if npc == null or not npc.is_alive():
		return

	var b := body()
	var direction := to - npc.position()
	direction.y = 0.0

	if direction.length() < 0.001 or b == null:
		return

	direction = direction.normalized()
	b.wish = direction * speed
	face(direction)


func halt() -> void:
	var b := body()

	if b != null:
		b.wish = Vector3.ZERO


## Walks the graph to [param to], kept apart from the crowd.
func go_to(to: Vector3, speed: float, spacing: float = 1.1) -> void:
	steer_with_spacing(to, speed, context.delta if context != null else 0.016, spacing)


# --- Knowing where survivors are -------------------------------------------------------------

## The survivor this zombie is after: one it was given, or one it perceived. Empty for none.
func quarry() -> StringName:
	var h := horde()

	if forced != &"" and h != null and bool(h.call(&"survivor_alive", forced)):
		return forced

	forced = &""
	return npc.target_id if npc != null and npc.has_target() else &""


## Where [param id] is now, or INF.
func survivor_at(id: StringName) -> Vector3:
	var h := horde()
	return h.call(&"survivor_position", id) if h != null else Vector3.INF


## A fact about a survivor: `down`, `pinned`, `biled`, `up`, `alive`. False when unknown.
func survivor_is(id: StringName, what: StringName) -> bool:
	var h := horde()
	return h != null and bool(h.call(&"survivor_is", id, what))


## Whether nothing solid is between two points.
func clear_line(from: Vector3, to: Vector3) -> bool:
	var h := horde()
	return h == null or bool(h.call(&"line_clear", from, to))


func distance_to(id: StringName) -> float:
	var at := survivor_at(id)
	return INF if at == Vector3.INF else flat_distance(npc.position(), at)


static func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- Fighting ------------------------------------------------------------------------------

## Starts a swing at [param victim] if one can start now. The hit lands [constant SWING_WINDUP]
## later, and only if they are still in reach and in front: a survivor who backs off in time
## takes nothing, which is the whole of melee feeling fair.
func swing_at(victim: StringName) -> bool:
	if _swing_at != INF or now() < _next_swing or now() < stagger_until:
		return false

	_swing_at = now()
	_swing_victim = victim
	_swing_landed = false
	var b := body()

	if b != null:
		b.anim = ZzZombieBody.Anim.ATTACK

	return true


func swinging() -> bool:
	return _swing_at != INF


## Advances a swing in progress. Called every think by every brain.
func _advance_swing() -> void:
	if _swing_at == INF:
		return

	var t := now() - _swing_at

	if not _swing_landed and t >= SWING_WINDUP * _attack_scale():
		_swing_landed = true
		var at := survivor_at(_swing_victim)
		var reach := tune(&"reach", 1.5) + 0.45

		if at != Vector3.INF and flat_distance(npc.position(), at) <= reach \
				and absf(npc.position().y - at.y) < 1.6:
			var h := horde()
			if h != null:
				h.call(&"melee", npc, _swing_victim, tune(&"damage", 2.0))

	if t >= (SWING_WINDUP + SWING_RECOVER) * _attack_scale():
		_swing_at = INF
		_next_swing = now() + maxf(tune(&"attack_interval", 0.9) - SWING_WINDUP - SWING_RECOVER, 0.0) * _attack_scale()


## A burning zombie swings faster; a staggered one does not swing.
func _attack_scale() -> float:
	var b := body()
	return 0.8 if b != null and b.has_flag(ZzZombieBody.FLAG_BURNING) else 1.0


func cancel_swing() -> void:
	_swing_at = INF


## Knocked back along [param direction] for [param seconds]. Called by the horde: a shove, a
## blast, a shotgun at point blank.
func stagger(direction: Vector3, seconds: float, strength: float = 4.0) -> void:
	stagger_until = maxf(stagger_until, now() + seconds)
	cancel_swing()
	var b := body()

	if b != null:
		b.shove(Vector3(direction.x, 0.0, direction.z).normalized() * strength)
		b.anim = ZzZombieBody.Anim.STAGGER

	_on_staggered(direction)


func staggered() -> bool:
	return now() < stagger_until


## For a special that lets go of what it held when shoved.
func _on_staggered(_direction: Vector3) -> void:
	pass


## Told to go after [param id] whatever it can see: a mob, bile, the director.
func force_target(id: StringName) -> void:
	forced = id


## Told to go to [param at] and stay there: a lure.
func lure_to(at: Vector3) -> void:
	lure = at


# --- The tick --------------------------------------------------------------------------------

func _npc_think(delta: float) -> void:
	super(delta)

	if npc == null or not npc.is_alive() or body() == null:
		return

	# Frozen by a box: everything stops, including a swing half way through.
	var h := horde()
	if h != null and float(h.get(&"zombie_speed_scale")) <= 0.0:
		halt()
		cancel_swing()
		return

	_advance_swing()

	if staggered():
		halt()
		return

	_decide(delta)


## A kind's own machine. Called every think after sensing, unless staggered.
func _decide(_delta: float) -> void:
	pass


## The default melee behaviour every kind falls back on: close in and hit. Returns false when
## there is nobody to fight.
func melee_chase(speed: float) -> bool:
	var target := quarry()

	if target == &"":
		return false

	var at := survivor_at(target)

	if at == Vector3.INF:
		return false

	var reach := tune(&"reach", 1.5)
	var gap := flat_distance(npc.position(), at)

	if gap <= reach and absf(npc.position().y - at.y) < 1.6:
		halt()
		face(at - npc.position())

		if not swinging():
			var _swung := swing_at(target)
	elif not swinging():
		go_to(at, speed)
		body().anim = ZzZombieBody.Anim.RUN
	else:
		# Mid-swing: keep closing at a walk, so a backing survivor is followed.
		go_to(at, speed * 0.35)

	return true


func _npc_died(by: StringName) -> void:
	super(by)
	var b := body()

	if b != null:
		b.anim = ZzZombieBody.Anim.DEAD
		b.wish = Vector3.ZERO


func describe() -> Dictionary:
	var out := super.describe()
	out["state"] = String(state)
	out["forced"] = String(forced)
	return out
