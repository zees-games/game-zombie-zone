extends "zz_zombie_brain.gd"

## The common infected: the crowd.
##
## [codeblock]
## idle         standing, sitting, feeding, milling or shambling about where it was put
##   -> alert   it saw somebody, heard a gun, was hit, or one beside it screamed
## alert        a scream and a turn, under a second; wakes the commons round it
##   -> chase   when it knows who; -> investigate when it only knows where
## investigate  runs to where the noise was, looks round, gives up after a while
## chase        one of the few on that survivor at once closes in and swings; the rest hold
##              a ring round the survivor, worked round to their back
## lure         something beeping or burning: it goes there and stays
## [/codeblock]
##
## [b]What makes a crowd frightening is not one smart zombie; it is forty that are not stupid in
## the same way.[/b] Each one's idle, speed and reactions come off its own seed, so a room of
## them does not stand up together; they wake each other a beat apart, which reads as a room
## waking rather than a trigger firing; and only [member ZzConfig.attackers_per_survivor] go at
## one person while the rest circle, so a survivor backed into a corner is hit by six and
## watched by twenty — and the twenty are behind them.
##
## [b]Asleep, it is easy to sneak past, and that is a choice.[/b] An idle common sees at under
## half its alert range and a feeding one at a third; crouching survivors are quiet. A team that
## goes slowly through a street of idle commons can get through it; one that runs and shoots
## wakes the street.

enum Idle { STAND, SIT, FEED, MILL, SHAMBLE }

## How far an idle common sees, as a share of its definition's range, by what it is doing.
const IDLE_SIGHT := {Idle.STAND: 0.5, Idle.SIT: 0.38, Idle.FEED: 0.3, Idle.MILL: 0.5, Idle.SHAMBLE: 0.55}
const ALERT_SIGHT := 1.4

## A scream, before it runs.
const ALERT_MIN := 0.35
const ALERT_MAX := 0.9

## The ring the commons without an attack slot hold round a survivor.
const RING_MIN := 2.1
const RING_MAX := 3.4

## Seconds a stuck common waits before it tries to climb over what is stopping it.
const STUCK_SECONDS := 1.2

## Hops that have not freed it before it is stepped along instead.
const HOPS_BEFORE_NUDGE := 2

## [method _chase_plan]'s first value: chasing the forced survivor, its own target, nobody, or one it has no place for.
## The same codes as gs-sim's `GSSimZombieBrains`.
const PLAN_FORCED := 0.0
const PLAN_TARGET := 1.0
const PLAN_NOBODY := -1.0
const PLAN_LOST := -2.0
## [method _chase_decide]'s act: no quarry; halt, face and swing; run at it; drift at it mid-swing.
const ACT_NONE := 0.0
const ACT_HIT := 1.0
const ACT_CHASE := 2.0
const ACT_SLOW := 3.0

var idle_kind: int = Idle.STAND
var home: Vector3 = Vector3.ZERO

## This one's own speed, ring and reactions, off its seed.
var pace: float = 1.0

## Fixed per zombie, so the same ones run for as long as an Angry Box does.
var runner_roll: float = 0.0
var ring: float = 2.6

var _alert_for: float = 0.5
var _alert_target: StringName = &""
var _alert_noise: Vector3 = Vector3.INF
var _mill_goal: Vector3 = Vector3.INF
var _mill_wait_until: float = 0.0
var _stuck_at: Vector3 = Vector3.INF
var _stuck_since: float = 0.0
## Hops at one place that did not free it, and where the last was.
var _hops: int = 0
var _last_hop_at: Vector3 = Vector3.INF
var _woken_at: float = INF


func _build() -> void:
	var seed_id := npc.seed if npc != null else 0
	var roll := GSNpcAiNode.deterministic_unit(seed_id, 4111)

	# Mostly standing and milling; a few sitting against things; fewer feeding on the floor.
	if roll < 0.32:
		idle_kind = Idle.STAND
	elif roll < 0.55:
		idle_kind = Idle.MILL
	elif roll < 0.72:
		idle_kind = Idle.SHAMBLE
	elif roll < 0.88:
		idle_kind = Idle.SIT
	else:
		idle_kind = Idle.FEED

	pace = lerpf(0.88, 1.12, GSNpcAiNode.deterministic_unit(seed_id, 4127))
	runner_roll = GSNpcAiNode.deterministic_unit(seed_id, 4153)
	ring = lerpf(RING_MIN, RING_MAX, GSNpcAiNode.deterministic_unit(seed_id, 4133))
	_alert_for = lerpf(ALERT_MIN, ALERT_MAX, GSNpcAiNode.deterministic_unit(seed_id, 4139))
	home = npc.position() if npc != null else Vector3.ZERO

	# Its own reactions: a sleepy one is a second slow, an edgy one is a tenth.
	character = GSNpcAiCharacter.preset(&"normal").with_seed(seed_id)
	character.reaction_time = lerpf(0.15, 0.9, GSNpcAiNode.deterministic_unit(seed_id, 4153))
	character.view_turn_deg = 360.0
	character.memory_time = 12.0
	character.alertness = 1.0
	go(&"idle")
	_set_sight(IDLE_SIGHT[idle_kind])


## How far it sees and hears, as a share of the kind's. Through the character's alertness,
## which gs-npc-ai writes onto the instance's `sight_scale` and also reads for hearing: a
## sight scale written straight onto the instance was overwritten by the brain on its next
## character refresh, and an idle common saw as far as an alert one.
func _set_sight(scale: float) -> void:
	if character != null:
		character.alertness = clampf(scale, 0.1, 2.0)
	if npc != null:
		npc.sight_scale = scale


## Woken by something it did not see itself. [param who] may be empty; [param where] may be INF.
func wake(who: StringName, where: Vector3, delay: float = 0.0) -> void:
	if state != &"idle" and state != &"investigate":
		return

	_alert_target = who
	_alert_noise = where
	_woken_at = now() + delay


func force_target(id: StringName) -> void:
	super(id)

	if state == &"idle" or state == &"investigate" or state == &"lure":
		_begin_alert(id, Vector3.INF, 0.15)


func lure_to(at: Vector3) -> void:
	super(at)

	if at != Vector3.INF:
		go(&"lure")
		_set_sight(ALERT_SIGHT)


## Has this one reached its place round a lure? Each stops at its own ring, so a crowd spreads.
func at_lure() -> bool:
	return lure != Vector3.INF and flat_distance(npc.position(), lure) <= ring


## The kind machine's states by [constant ZzThinkCore] number (the core answers in numbers, `state` is a name).
const KINDS: Array[StringName] = [&"idle", &"alert", &"investigate", &"chase", &"lure"]


## Each think: the conditions the state reads become a bitmask, the core ([method _core]: gs-sim's, else the
## script twin) answers the next state and what to do, and this runs the side effects (the engine's part).
func _decide(_delta: float) -> void:
	var b := body()
	var core := _core()
	var k := KINDS.find(state)
	var c := 0

	# A lure outranks everything but a survivor in its face.
	if lure != Vector3.INF:
		c |= ZzThinkCore.C_LURE
	if forced != &"":
		c |= ZzThinkCore.C_FORCED

	if k >= 0 and core.kind_pre(k, c) >= 0:
		go(&"lure")
		k = ZzThinkCore.LURE

	match k:
		ZzThinkCore.IDLE:
			_idle(b)

			if _woken_at != INF and now() >= _woken_at:
				c |= ZzThinkCore.C_WOKEN
			elif c & ZzThinkCore.C_FORCED == 0:
				if npc.has_target() and has_reacted():
					c |= ZzThinkCore.C_REACTED
				else:
					var cond := context.conditions
					if cond.has(GSNpcAiConditions.LIGHT_DAMAGE) or cond.has(GSNpcAiConditions.HEAR_COMBAT):
						c |= ZzThinkCore.C_HEARD

			var r := core.kind_step(k, c) as int

			match r >> 8:
				ZzThinkCore.A_BEGIN_WOKEN:
					_woken_at = INF
					_begin_alert(_alert_target, _alert_noise, 0.0)
				ZzThinkCore.A_BEGIN_FORCED:
					_begin_alert(forced, Vector3.INF, 0.1)
				ZzThinkCore.A_BEGIN_TARGET:
					_begin_alert(npc.target_id, Vector3.INF, 0.0)
				ZzThinkCore.A_BEGIN_HEARD:
					var heard := last_known_position()
					_begin_alert(&"", heard if heard != Vector3.INF else npc.position(), 0.0)

		ZzThinkCore.ALERT:
			halt()
			b.anim = ZzZombieBody.Anim.RAGE

			var look := survivor_at(_alert_target) if _alert_target != &"" else _alert_noise
			if look != Vector3.INF:
				face(look - npc.position())

			if in_state_for() >= _alert_for:
				c |= ZzThinkCore.C_ALERT_DONE
				if quarry() != &"":
					c |= ZzThinkCore.C_QUARRY
				if _alert_target != &"":
					c |= ZzThinkCore.C_ALERT_TARGET

			var r := core.kind_step(k, c) as int

			if r >> 8 == ZzThinkCore.A_ALERT_FORCE:
				forced = _alert_target
			if r & 255 != k:
				go(KINDS[r & 255])

		ZzThinkCore.INVESTIGATE:
			if quarry() != &"":
				c |= ZzThinkCore.C_QUARRY

			var r := core.kind_step(k, c) as int

			if r >> 8 == ZzThinkCore.A_SEARCH:
				var running := search(context, tune(&"walk_speed", 1.1) * 3.5 * pace, 1.1) == GSNpcAiNode.Status.RUNNING
				var after := core.kind_after_search(running) as int

				if after & 255 == ZzThinkCore.IDLE:
					home = npc.position()
					go(&"idle")
					_set_sight(IDLE_SIGHT[Idle.STAND])
					idle_kind = Idle.MILL
				else:
					b.anim = ZzZombieBody.Anim.RUN if b.wish.length() > 2.0 else ZzZombieBody.Anim.IDLE
					# Chase hopped a wedged body free; investigating one sat 24 s on a floor seam (ze_death_star_escape).
					_unstick(b, npc.position())
			else:
				go(KINDS[r & 255])

		ZzThinkCore.CHASE:
			_set_sight(ALERT_SIGHT)

			var ok := _chase(b)
			var after := core.kind_after_chase(ok, not ok and remembers_target()) as int

			if after & 255 == ZzThinkCore.INVESTIGATE:
				go(&"investigate")
			elif after & 255 == ZzThinkCore.IDLE:
				home = npc.position()
				idle_kind = Idle.SHAMBLE
				go(&"idle")

		ZzThinkCore.LURE:
			_set_sight(ALERT_SIGHT)

			var gap := 0.0
			if lure != Vector3.INF:
				if quarry() != &"":
					c |= ZzThinkCore.C_QUARRY
				if c & ZzThinkCore.C_FORCED != 0 or (npc.has_target() and distance_to(npc.target_id) < 3.0):
					c |= ZzThinkCore.C_TARGET_NEAR
				else:
					gap = flat_distance(npc.position(), lure)
					if gap > ring:
						c |= ZzThinkCore.C_OUT_OF_RING
			elif quarry() != &"":
				c |= ZzThinkCore.C_QUARRY

			var r := core.kind_step(k, c) as int

			match r >> 8:
				ZzThinkCore.A_LURE_GO:
					go_to(lure, _chase_speed() * pace, 1.0)
					b.anim = ZzZombieBody.Anim.RUN
					_unstick(b, lure)
				ZzThinkCore.A_LURE_HOLD:
					halt()
					face(lure - npc.position())
					b.anim = ZzZombieBody.Anim.RAGE
				_:
					go(KINDS[r & 255])


func _begin_alert(who: StringName, where: Vector3, extra: float) -> void:
	_alert_target = who
	_alert_noise = where
	_alert_for += extra
	go(&"alert")
	_set_sight(ALERT_SIGHT)

	# The scream wakes the room: every idle common near it, a beat apart.
	var h := horde()
	if h != null:
		h.call(&"spread_alert", npc, who, where if where != Vector3.INF else npc.position())


## The horde owns the rule (Hard Box stacks, Angry runners); without one the def's run speed stands.
func _chase_speed() -> float:
	var h := horde()
	return float(h.call(&"common_chase_speed", runner_roll)) if h != null else npc.def.move_speed


## This tick's chase as [code][code, dropped, at.x, at.y, at.z, speed, gap, reach][/code]: whom ([code]PLAN_*[/code]),
## whether [member forced] is spent, where they stand, how fast and how far, and how near a swing lands. In gs-sim's
## `GSSimZombieBrains` while the horde has one ([member ZzConfig.native_brains]); the script below otherwise, and
## beside it under the horde's `brains_verify`, whose answer is then the one used.
func _chase_plan(b: ZzZombieBody) -> PackedFloat64Array:
	var h := horde()
	var native: Object = h.get(&"brains_now") if h != null else null

	if native == null:
		return _chase_plan_script(b)

	var plan: PackedFloat64Array = native.call(&"plan_chase", forced, npc.target_id if npc.has_target() else &"",
		pace, runner_roll, tune(&"reach", 1.55), b.has_flag(ZzZombieBody.FLAG_BURNING), b.kind == &"crawler",
		npc.position())

	if bool(h.get(&"brains_verify")):
		var script := _chase_plan_script(b)
		h.call(&"brains_tally", script == plan)
		return script

	return plan


## [method _chase_plan] in script: [method quarry], [method survivor_at], [method _chase_speed] and
## [method strikes_down] as they were, without spending [member forced] (the caller does).
func _chase_plan_script(b: ZzZombieBody) -> PackedFloat64Array:
	var h := horde()
	var plan := PackedFloat64Array([PLAN_NOBODY, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var target: StringName = &""

	if forced != &"" and h != null and bool(h.call(&"survivor_alive", forced)):
		plan[0] = PLAN_FORCED
		target = forced
	else:
		plan[1] = 1.0 if forced != &"" else 0.0

		if npc != null and npc.has_target() and npc.target_id != &"":
			plan[0] = PLAN_TARGET
			target = npc.target_id

	if target == &"":
		return plan

	var at := survivor_at(target)

	if at == Vector3.INF:
		plan[0] = PLAN_LOST
		return plan

	var speed := _chase_speed() * pace

	if b.has_flag(ZzZombieBody.FLAG_BURNING):
		speed *= 1.2

	var reach := tune(&"reach", 1.55)

	if strikes_down(target):
		reach = minf(reach, 1.1)

	plan[2] = at.x
	plan[3] = at.y
	plan[4] = at.z
	plan[5] = speed
	plan[6] = flat_distance(npc.position(), at)
	plan[7] = reach
	return plan


## This tick's chase choice: [method _chase_plan]'s eight values, the act ([code]ACT_*[/code]) and 1 when it must ask
## [method claim_attack_slot] first. gs-sim's `chase` while the brains decide natively ([code]_decides[/code]), else
## the script's; under `brains_verify` both, and the script's answer is used.
func _chase_decide(b: ZzZombieBody) -> PackedFloat64Array:
	var h := horde()
	var native: Object = h.get(&"brains_now") if h != null else null

	if native == null or not _decides_with(native):
		return _chase_choice(_chase_plan(b))

	var flags := (1 if b.has_flag(ZzZombieBody.FLAG_BURNING) else 0) | (2 if b.kind == &"crawler" else 0) \
			| (4 if swinging() else 0)
	var out: PackedFloat64Array = native.call(&"chase", forced, npc.target_id if npc.has_target() else &"", pace,
		runner_roll, tune(&"reach", 1.55), ring, flags, npc.position())

	if bool(h.get(&"brains_verify")):
		var script := _chase_choice(_chase_plan_script(b))
		h.call(&"brains_tally", script == out)
		return script

	return out


## [param plan] with the script's choice after it, as [method _chase_decide] answers. Close enough to matter, only
## the slot holders go in and the rest hold the ring; a forced zombie (a mob, bile) skips the queue, a mob is
## supposed to swamp you ([member forced] outlives the plan only when it is the one chased).
func _chase_choice(plan: PackedFloat64Array) -> PackedFloat64Array:
	var out := plan.duplicate()
	out.append(ACT_NONE)
	out.append(0.0)

	if plan[0] < 0.0:
		return out

	out[9] = 1.0 if plan[0] != PLAN_FORCED and plan[6] <= ring + 3.0 else 0.0

	if plan[6] <= plan[7] and absf(npc.position().y - plan[3]) < 1.6:
		out[8] = ACT_HIT
	elif not swinging():
		out[8] = ACT_CHASE
	else:
		out[8] = ACT_SLOW

	return out


## One tick of the fight. False when there is nobody to fight.
func _chase(b: ZzZombieBody) -> bool:
	var plan := _chase_decide(b)

	if plan[1] > 0.5:
		forced = &""

	if plan[0] < 0.0:
		return false

	var target: StringName = forced if plan[0] == PLAN_FORCED else npc.target_id
	var at := Vector3(plan[2], plan[3], plan[4])
	var speed := plan[5]
	var act := plan[8]

	if plan[9] < 0.5 or claim_attack_slot():
		if act == ACT_HIT:
			halt()
			face(at - npc.position())
			if not swinging():
				var _swung := swing_at(target)
		elif act == ACT_CHASE:
			chase_to(at, speed)
			b.anim = ZzZombieBody.Anim.RUN
		else:
			go_to(at, speed * 0.35)
	else:
		var _held := surround(context, speed, ring, 1.1)
		b.anim = ZzZombieBody.Anim.RUN if b.wish.length() > 1.5 else ZzZombieBody.Anim.IDLE

	_unstick(b, at)
	return true


## A common stuck against something for over a second climbs it: a hop up and forward.
##
## The graph routes round everything it knows is in the way; what stops a common is the
## crowd, a car's corner the graph cut too fine, or a survivor standing on something. A
## real crowd climbs over that, and one that stood pressing into a bumper read as broken.
func _unstick(b: ZzZombieBody, toward: Vector3) -> void:
	if b.wish.length() < 1.0 or not b.is_on_floor():
		_stuck_at = Vector3.INF
		return

	var here := npc.position()

	if _stuck_at == Vector3.INF or here.distance_to(_stuck_at) > 0.6:
		if _stuck_at == Vector3.INF and here.distance_to(_last_hop_at) > 1.5:
			_hops = 0

		_stuck_at = here
		_stuck_since = now()
		return

	if now() - _stuck_since >= STUCK_SECONDS:
		# Up and the way it was trying to go (its path's next corner), not straight at its
		# target, which from a doorway is often into the wall beside it.
		var forward := b.wish if b.wish.length() > 0.1 else (toward - here)
		forward.y = 0.0
		_hops += 1
		_last_hop_at = here

		# Two hops that did not free it: a step along where it was going, if it fits (`ZzUnstick`).
		if _hops > HOPS_BEFORE_NUDGE and ZzUnstick.nudge(b, forward):
			note_unstick("hop nudge")
			_hops = 0
			_stuck_at = Vector3.INF
			return

		note_unstick("hop %d" % _hops)
		b.leap(forward.normalized() * 3.0 + Vector3(0.0, 7.0, 0.0))
		b.anim = ZzZombieBody.Anim.LEAP
		_stuck_at = Vector3.INF


func _idle(b: ZzZombieBody) -> void:
	match idle_kind:
		Idle.SIT:
			halt()
			b.anim = ZzZombieBody.Anim.SIT
		Idle.FEED:
			halt()
			b.anim = ZzZombieBody.Anim.FEED
		Idle.STAND:
			halt()
			b.anim = ZzZombieBody.Anim.IDLE
		Idle.MILL, Idle.SHAMBLE:
			var wander := 5.0 if idle_kind == Idle.MILL else 14.0

			if _mill_goal == Vector3.INF or flat_distance(npc.position(), _mill_goal) < 0.8:
				if _mill_goal != Vector3.INF:
					_mill_wait_until = now() + lerpf(1.5, 6.0, GSNpcAiNode.deterministic_unit(npc.seed, int(now() * 10.0)))
				var angle := GSNpcAiNode.deterministic_unit(npc.seed, int(now() * 3.0) + 77) * TAU
				var far := lerpf(1.5, wander, GSNpcAiNode.deterministic_unit(npc.seed, int(now() * 5.0) + 91))
				_mill_goal = home + Vector3(cos(angle), 0.0, sin(angle)) * far
				var h := horde()
				if h != null:
					_mill_goal = h.call(&"snap_to_nav", _mill_goal)

			if now() < _mill_wait_until:
				halt()
				b.anim = ZzZombieBody.Anim.IDLE
			else:
				go_to(_mill_goal, tune(&"walk_speed", 1.1) * pace, 1.2)
				b.anim = ZzZombieBody.Anim.SHAMBLE


func describe() -> Dictionary:
	var out := super.describe()
	out["idle"] = Idle.keys()[idle_kind]
	return out
