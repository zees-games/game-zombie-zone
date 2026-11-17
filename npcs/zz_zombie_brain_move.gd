extends "res://addons/dot_npc_ai/runtime/dot_npc_ai_brain.gd"
## The movement half of every zombie's mind (`zz_zombie_brain.gd` extends this): the horde it reports to, the body it
## moves, and the steering overrides (a wish written for the body, the crowd's spacing, and the native brains' steer
## step with its `brains_verify` check). Split out so each half stays a size a reader can hold.

const ZzZombieBody := preload("zz_zombie_body.gd")
const CHANNEL := "zz.zombie_brain"

## Where the horde publishes itself on the spawner, so a brain built from a path can reach it.
const HORDE_META := &"zz_horde"

var _horde: Object = null
## Whether the horde's dot-sim has [code]steer_walk[/code] (-1 until asked; one library a process).
static var _steer_walks: int = -1
## Whether the horde's dot-sim has [code]walk[/code], the whole move in one call (-1 until asked; 0 also turns it off,
## as `tools/bench.gd --ab-move` does).
static var _walks: int = -1
## What [method _walk] hands dot-sim, kept so a move fills them in place rather than building them.
var _walk_s := PackedFloat64Array()
var _walk_n := PackedInt64Array()

## The horde this zombie belongs to. Duck-typed: see `zz_horde.gd`.
func horde() -> Object:
	if _horde == null and director != null and director.has_meta(HORDE_META):
		_horde = director.get_meta(HORDE_META)

	return _horde


func body() -> ZzZombieBody:
	return npc.node as ZzZombieBody if npc != null else null


# Moving

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


## The crowd round this zombie, from the horde's grid of the tick rather than the spawner's
## walk over every zombie (see `ZzHorde.zombies_near`). The same answer, measured from where
## each was when the tick began.
func neighbours(radius: float) -> Array:
	var h := horde()

	if h == null or npc == null or not npc.is_alive():
		return super(radius)

	return h.call(&"neighbour_positions", npc, radius * 2.0)


## [method steer_with_spacing]'s heading (seek, crowd push, blend) in one call to dot-sim's
## `DotSimCrowdGrid.spaced_direction` while the horde's brains and crowd are both native; the script otherwise,
## and beside it under the horde's `brains_verify`, whose answer is then the one used.
func _spaced_direction(here: Vector3, goal: Vector3, spacing: float) -> Vector3:
	var h := horde()
	var grid: Variant = h.get(&"brains_crowd") if h != null and npc != null and npc.is_alive() else null

	if grid == null:
		return super(here, goal, spacing)

	var native: Vector3 = grid.spaced_direction(npc.instance_id, here, goal, spacing, npc.facing())

	if native == Vector3.INF:
		return super(here, goal, spacing)

	if bool(h.get(&"brains_verify")):
		var script := super(here, goal, spacing)
		h.call(&"brains_tally", script == native)
		return script

	return native


## Spacing straight off the horde's crowd grid: the same push as [method neighbours] fed to
## `DotNpcAiSteering.separate`, without building the array each think.
func separation(here: Vector3, spacing: float, right: Vector3) -> Vector3:
	var h := horde()
	var grid: Variant = h.get(&"crowd") if h != null and npc != null and npc.is_alive() else null

	if grid == null:
		return super(here, spacing, right)

	var own: int = grid.index_of(npc.instance_id)

	if own < 0:
		return super(here, spacing, right)

	return grid.separation(own, here, spacing, spacing * 2.0, right)


## dot-npc-ai's steer in one native call: the whole move ([code]DotSimZombieBrains.walk[/code], path then steer) when
## the path is not due, else everything after the path ([code]steer_walk[/code], else [code]steer_step[/code]). The
## script ([method _steer_rest]) is the fallback, and under [code]brains_verify[/code] each native answer is checked.
func steer_with_spacing(to: Vector3, speed: float, delta: float, spacing: float = 1.6) -> void:
	var h := horde()
	var b := body()

	if h == null or b == null or character == null or context == null or npc == null or not npc.is_alive():
		super(to, speed, delta, spacing)
		return

	var brains: Variant = h.get(&"brains_steer")
	var grid: Variant = h.get(&"brains_crowd")

	if brains == null or grid == null or _avoider() != null:
		super(to, speed, delta, spacing)
		return

	if _walks < 0:
		_walks = 1 if (brains as Object).has_method(&"walk") else 0

	if _walks == 1 and _walk_native(h, b, brains, grid, to, speed, delta, spacing):
		return

	_steer_from(h, b, brains, grid, _steer_goal(to), to, speed, delta, spacing)


## The steer after [method _steer_goal] for [param goal]: [code]steer_walk[/code] (or [code]steer_step[/code]), or the
## script.
func _steer_from(h: Object, b: ZzZombieBody, brains: Object, grid: Object, goal: Vector3, to: Vector3, speed: float,
		delta: float, spacing: float) -> void:
	if goal == Vector3.INF:
		_cruise_dest = to
		return

	var now := _world_now()
	var verify := bool(h.get(&"brains_verify"))

	if _steer_walks < 0:
		_steer_walks = 1 if brains.has_method(&"steer_walk") else 0

	var out: PackedFloat64Array
	if _steer_walks == 1:
		# The brain's watch handed in and its writes made here: six fewer member calls across the boundary.
		out = brains.steer_walk(grid, npc.instance_id, character, b, goal, to, spacing, speed, context.delta,
			not verify, _facing_at_tick, _progress_at, now - _progress_since, stuck_seconds)
	else:
		out = brains.steer_step(grid, npc.instance_id, self, character, b, goal, to,
			spacing, speed, context.delta, now, not verify)

	if out[0] < 0.0:
		_steer_rest(goal, to, speed, delta, spacing)
		return

	if verify:
		_verify_steer(h, b, out, goal, to, speed, delta, spacing, now)
		return

	if _steer_walks == 1 and out[0] == 1.0:
		_cruise_to = goal
		_cruise_dest = to
		if out[1] == 1.0:
			_progress_at = Vector3(out[16], out[17], out[18])
			_progress_since = now

	if out[1] == 2.0 and path != null and path.has_method(&"go_rough"):
		path.call(&"go_rough", now, 4.0)
		_progress_at = Vector3(out[16], out[17], out[18])
		_progress_since = now


## The whole move in one [code]DotSimZombieBrains.walk[/code]: dot-npc-ai's [code]_steer_goal[/code] (dot-npc's
## [code]path_toward[/code]: its repath test and the path's advance) and then the steer, with the brain's, character's,
## path's and spawner's members handed in by value and the answer written back here. Only where the script's own
## [code]_steer_goal[/code] is exactly [code]path_toward[/code] (a nav graph and a path, no scheduler, no path reuse);
## false there, with nothing done, and the caller steers as before. A path due a repath goes to the script's
## [code]path_toward[/code] (which queues or searches) and the steer after it, as [method _steer_from].
func _walk_native(h: Object, b: ZzZombieBody, brains: Object, grid: Object, to: Vector3, speed: float, delta: float,
		spacing: float) -> bool:
	var p := path
	var sp := director as DotNpcSpawner
	# _path_goal's own way to path_toward, with its scheduler probe taken only where it cannot find one.
	if p == null or sp == null or path_reuse_thoughts > 0 or scheduler != null or _sched_probe <= 1 \
			or not sp.has_nav():
		return false

	_path_denied = false
	_sched()
	var now := _world_now()
	var verify := bool(h.get(&"brains_verify"))
	_walk_pack(sp, to, speed, spacing, now)

	var out: PackedFloat64Array = brains.walk(grid, npc.instance_id, b, p.points, _walk_s, _walk_n, not verify)

	if out[0] < 0.0:
		# Due a repath (or no answer): path_toward as _asked_goal asks it, then the steer as before.
		var asked := _as_goal(sp.path_toward(npc, p, to))
		_steer_from(h, b, brains, grid, asked if asked != Vector3.INF else to, to, speed, delta, spacing)
		return true

	var goal := Vector3(out[20], out[21], out[22])

	if verify:
		var index0 := p.index
		var asked := _as_goal(sp.path_toward(npc, p, to))
		var same := asked == goal and p.index == int(out[19]) and _waypoint == goal
		if not same:
			DotLog.debug(CHANNEL, "native walk differs from the script's", {"native": str([goal, int(out[19])]),
				"script": str([asked, p.index, _waypoint]), "was": index0})
		h.call(&"brains_tally", same)
		_verify_steer(h, b, out, asked if asked != Vector3.INF else to, to, speed, delta, spacing, now)
		return true

	_walk_apply(p, b, out, goal, to, now)
	return true


## The members [method _walk_native] hands [code]walk[/code] by value.
func _walk_pack(sp: DotNpcSpawner, to: Vector3, speed: float, spacing: float, now: float) -> void:
	var p := path
	var c := character
	if _walk_s.size() != 32:
		_walk_s.resize(32)
		_walk_n.resize(4)
	_walk_s[0] = to.x
	_walk_s[1] = to.y
	_walk_s[2] = to.z
	_walk_s[3] = spacing
	_walk_s[4] = speed
	_walk_s[5] = context.delta
	_walk_s[6] = now
	_walk_s[7] = _facing_at_tick.x
	_walk_s[8] = _facing_at_tick.y
	_walk_s[9] = _facing_at_tick.z
	_walk_s[10] = _progress_at.x
	_walk_s[11] = _progress_at.y
	_walk_s[12] = _progress_at.z
	_walk_s[13] = _progress_since
	_walk_s[14] = stuck_seconds
	_walk_s[15] = c._peak_turn
	_walk_s[16] = c._over_amt
	_walk_s[17] = c._over_axis.x
	_walk_s[18] = c._over_axis.y
	_walk_s[19] = c._over_axis.z
	_walk_s[20] = c.view_factor
	_walk_s[21] = c.view_turn_deg
	_walk_s[22] = c.overshoot
	_walk_s[23] = p.arrive_radius
	_walk_s[24] = p.computed_at
	_walk_s[25] = p.goal_at_compute.x
	_walk_s[26] = p.goal_at_compute.y
	_walk_s[27] = p.goal_at_compute.z
	_walk_s[28] = sp.repath_drift
	_walk_s[29] = sp.repath_interval
	_walk_s[30] = sp.repath_drift_ratio
	_walk_s[31] = sp.repath_interval_per_m
	_walk_n[0] = c._turns
	_walk_n[1] = c.seed_value
	_walk_n[2] = p.index
	_walk_n[3] = 1 if p.partial else 0


## What [code]walk[/code] answered, written back to the path, the character and this brain.
func _walk_apply(p: DotNpcPath, b: ZzZombieBody, out: PackedFloat64Array, goal: Vector3, to: Vector3, now: float) -> void:
	var c := character
	p.index = int(out[19])
	_waypoint = goal

	if out[0] != 1.0:
		return

	if out[2] == 1.0:
		b.wish = Vector3(out[3], out[4], out[5])
	c._peak_turn = out[10]
	c._over_amt = out[11]
	c._turns = int(out[12])
	c._over_axis = Vector3(out[13], out[14], out[15])
	_cruise_to = goal
	_cruise_dest = to

	if out[1] == 1.0:
		_progress_at = Vector3(out[16], out[17], out[18])
		_progress_since = now
	elif out[1] == 2.0:
		p.go_rough(now, 4.0)
		_progress_at = Vector3(out[16], out[17], out[18])
		_progress_since = now


## dot-npc-ai's [code]steer_with_spacing[/code] after its [code]_steer_goal[/code], as the script runs it.
func _steer_rest(goal: Vector3, to: Vector3, speed: float, delta: float, spacing: float) -> void:
	var here := npc.position()
	var direction := _spaced_direction(here, goal, spacing)

	if direction.length() < 0.001:
		return

	var av := _avoider()
	if av != null:
		var tier := scheduler.tier_of(self) if scheduler != null and is_instance_valid(scheduler) else 0
		var safe: Vector3 = av.steer(npc.instance_id, npc, direction.normalized() * speed, tier)
		if safe.length() > 0.001:
			direction = safe.normalized()

	steer_toward(here + direction * 4.0, speed, delta)
	_cruise_to = goal
	_cruise_dest = to
	_watch_progress(here, to)


## [code]brains_verify[/code]: the script steers, and the native answer [param out] (asked without applying) is
## tallied against what it wrote: the wish, the turn state, the body's transform, the cruise and the watch.
func _verify_steer(h: Object, b: ZzZombieBody, out: PackedFloat64Array, goal: Vector3, to: Vector3,
		speed: float, delta: float, spacing: float, now: float) -> void:
	var t0 := b.global_transform
	# Set back as it is, so the script's look_at starts where the native one's below does: a Node3D whose transform was
	# just set has no cached scale, and look_at keeps its scale through get_scale, an ulp off the cached one.
	b.global_transform = t0
	var wish0 := b.wish
	var at0 := _progress_at
	var since0 := _progress_since
	_steer_rest(goal, to, speed, delta, spacing)
	var t1 := b.global_transform
	var want := t0
	var same := true

	if out[0] == 0.0:
		same = b.wish == wish0 and t1 == t0 and _progress_at == at0 and _progress_since == since0
	else:
		if out[6] == 1.0:
			b.global_transform = t0
			b.look_at(Vector3(out[7], out[8], out[9]), Vector3.UP)
			want = b.global_transform
			b.global_transform = t1
		var wish := Vector3(out[3], out[4], out[5]) if out[2] == 1.0 else wish0
		same = (b.wish == wish and t1 == want
			and character._peak_turn == out[10] and character._over_amt == out[11]
			and character._turns == int(out[12])
			and character._over_axis == Vector3(out[13], out[14], out[15])
			and _cruise_to == goal and _cruise_dest == to)
		if out[1] == 1.0:
			same = same and _progress_at == Vector3(out[16], out[17], out[18]) and _progress_since == now
		elif out[1] == 0.0:
			same = same and _progress_at == at0 and _progress_since == since0

	if not same:
		DotLog.debug(CHANNEL, "native steer differs from the script's", {"native": str(out), "wish": str(b.wish),
			"turn": str([character._peak_turn, character._over_amt, character._turns, character._over_axis]),
			"progress": str([_progress_at, _progress_since]), "xf": str(t1), "want": str(want), "cruise": str(_cruise_to), "goal": str(goal)})

	h.call(&"brains_tally", same)
