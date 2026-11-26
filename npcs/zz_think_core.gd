extends RefCounted
## The zombie think glue as plain arithmetic: the swing timer, the stuck watchdog, how often a zombie
## thinks and the common's kind machine. This is the script twin of gs-sim's `GSSimZombieThink`
## (gs-sim-zombie `think.rs` and `kind.rs`): the same methods, the same integer codes, so a brain
## calls one or the other and `headless_native_think` holds them bit-equal. The brains own what only
## the engine can do (the hit, the nudge and relocate, the survivor scan) and act on the codes.

## One script twin for brains with no horde (a tool or suite thinking one by hand). Made on first use, not at load:
## an instance made at load pins this script, and the parse pass can then not reload it.
static var _shared: RefCounted = null


static func shared() -> RefCounted:
	if _shared == null:
		_shared = new()
	return _shared


const SWING_WINDUP := 0.32
const SWING_RECOVER := 0.55
const WATCH_RADIUS := 1.0

const SWING_LAND := 1
const SWING_END := 2

const WATCH_HOLD := 0
const WATCH_RESET := 1
const WATCH_ANCHOR := 2
const WATCH_COUNT := 3
const WATCH_NUDGE := 4
const WATCH_RELOCATE := 5

const EVERY_OFF := 1
const EVERY_SWINGING := 2
const EVERY_LANDED := 4
const EVERY_BASHING := 8
const EVERY_NO_HORDE := 16

const IDLE := 0
const ALERT := 1
const INVESTIGATE := 2
const CHASE := 3
const LURE := 4

const C_LURE := 1
const C_FORCED := 2
const C_WOKEN := 4
const C_REACTED := 8
const C_HEARD := 16
const C_ALERT_DONE := 32
const C_QUARRY := 64
const C_ALERT_TARGET := 128
const C_TARGET_NEAR := 256
const C_OUT_OF_RING := 512

const A_NONE := 0
const A_BEGIN_WOKEN := 1
const A_BEGIN_FORCED := 2
const A_BEGIN_TARGET := 3
const A_BEGIN_HEARD := 4
const A_ALERT := 5
const A_ALERT_FORCE := 6
const A_SEARCH := 7
const A_CHASE := 8
const A_LURE_GO := 9
const A_LURE_HOLD := 10


func swing_step(swing_at: float, landed: bool, now: float, scale: float) -> int:
	if swing_at == INF:
		return 0
	var t := now - swing_at
	var code := 0
	if not landed and t >= SWING_WINDUP * scale:
		code |= SWING_LAND
	if t >= (SWING_WINDUP + SWING_RECOVER) * scale:
		code |= SWING_END
	return code


func swing_next(now: float, scale: float, interval: float) -> float:
	return now + maxf(interval - SWING_WINDUP - SWING_RECOVER, 0.0) * scale


func unstick_step(flying: bool, limit: float, no_try: bool, wish_len: float, here: Vector3, watch_at: Vector3, watch_for: float, stage: int, delta: float) -> int:
	if flying:
		return WATCH_HOLD
	if limit <= 0.0 or no_try or wish_len < 1.0:
		return WATCH_RESET
	if watch_at == Vector3.INF or _flat(here, watch_at) > WATCH_RADIUS or absf(here.y - watch_at.y) > WATCH_RADIUS:
		return WATCH_ANCHOR
	if watch_for + delta < limit:
		return WATCH_COUNT
	return WATCH_NUDGE if stage == 0 else WATCH_RELOCATE


func every_early(flags: int, now: float, swing_at: float, scale: float) -> int:
	if flags & EVERY_OFF != 0:
		return 1
	if flags & EVERY_SWINGING != 0:
		if flags & EVERY_LANDED != 0 and (SWING_WINDUP + SWING_RECOVER) * scale - (now - swing_at) > 0.05:
			return 2
		return 1
	if flags & EVERY_BASHING != 0:
		return 4
	if flags & EVERY_NO_HORDE != 0:
		return 1
	return 0


func every_tier(nearest: float, dormant: float, dormant_every: int) -> int:
	if nearest < 6.0:
		return 1
	if nearest < 20.0:
		return 2
	if nearest < 45.0:
		return 3
	if nearest < 60.0:
		return 4
	if dormant > 0.0 and nearest >= dormant:
		return maxi(dormant_every, 8)
	return 8


func body_stride(nearest: float, near: float, far: float, dormant: float, cheap_from: float) -> int:
	var far_stride := 8 if dormant > 0.0 and nearest >= dormant else 4
	var stride := 1 if nearest < near else (2 if nearest < far else far_stride)
	var cheap := cheap_from > 0.0 and nearest >= cheap_from
	return stride | ((1 if cheap else 0) << 8)


func kind_needs(state: int) -> int:
	match state:
		IDLE:
			return C_FORCED | C_WOKEN | C_REACTED | C_HEARD
		ALERT:
			return C_ALERT_DONE | C_QUARRY | C_ALERT_TARGET | C_FORCED
		INVESTIGATE:
			return C_QUARRY
		LURE:
			return C_LURE | C_FORCED | C_TARGET_NEAR | C_QUARRY | C_OUT_OF_RING
	return 0


func kind_pre(state: int, conditions: int) -> int:
	if conditions & C_LURE != 0 and state != LURE and conditions & C_FORCED == 0:
		return LURE
	return -1


func kind_step(state: int, c: int) -> int:
	var next := state
	var act := A_NONE
	match state:
		IDLE:
			next = ALERT
			if c & C_WOKEN != 0:
				act = A_BEGIN_WOKEN
			elif c & C_FORCED != 0:
				act = A_BEGIN_FORCED
			elif c & C_REACTED != 0:
				act = A_BEGIN_TARGET
			elif c & C_HEARD != 0:
				act = A_BEGIN_HEARD
			else:
				next = IDLE
		ALERT:
			if c & C_ALERT_DONE == 0:
				act = A_ALERT
			elif c & (C_QUARRY | C_ALERT_TARGET) != 0:
				next = CHASE
				var force := c & C_FORCED == 0 and c & C_ALERT_TARGET != 0 and c & C_QUARRY == 0
				act = A_ALERT_FORCE if force else A_ALERT
			else:
				next = INVESTIGATE
				act = A_ALERT
		INVESTIGATE:
			if c & C_QUARRY != 0:
				next = CHASE
			else:
				act = A_SEARCH
		CHASE:
			act = A_CHASE
		LURE:
			if c & C_LURE == 0:
				next = CHASE if c & C_QUARRY != 0 else IDLE
			elif c & (C_FORCED | C_TARGET_NEAR) != 0:
				next = CHASE
			elif c & C_OUT_OF_RING != 0:
				act = A_LURE_GO
			else:
				act = A_LURE_HOLD
	return next | (act << 8)


func kind_after_search(running: bool) -> int:
	return INVESTIGATE if running else (IDLE | (1 << 8))


func kind_after_chase(ok: bool, remembers: bool) -> int:
	if ok:
		return CHASE
	if remembers:
		return INVESTIGATE
	return IDLE | (1 << 8)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
