extends GSGameCheckSuite

const ThinkCore := preload("../npcs/zz_think_core.gd")

## The zombies' think glue in gs-sim (`GSSimZombieThink`) answers as its script twin (`zz_think_core.gd`, which the
## brains run without the library) to the bit: ten thousand random-walk rows of the swing clock, the stuck watchdog
## and the think rate (boundary values and INF included), every state against every condition of the common's kind
## machine, and replays of random condition streams through both, state and action for state and action. The
## brains' wiring is covered by the other zombie suites. Without the library the native half is skipped;
## [code]GS_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const NATIVE := &"GSSimZombieThink"
const ROWS := 10000
const STREAMS := 300
const STEPS := 200

var _entered := 0
var _finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone native think")
	print("")
	_entered += 1
	print("the think glue is native when the library has it")
	if not ClassDB.class_exists(NATIVE):
		print("  gs-sim's zombie think module is not loaded: the native half is skipped")
		_check(OS.get_environment("GS_SIM_REQUIRE_NATIVE") != "1", "the library is loaded (GS_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, 1, 1)
		return
	_check(true, "the library has GSSimZombieThink")
	_finished += 1

	var twin := ThinkCore.new()
	var nat: Object = ClassDB.instantiate(NATIVE)

	_entered += 1
	print("random-walk rows, the swing clock")
	var bad := _swing_rows(twin, nat)
	_check(bad[0] == 0, "swing_step is the twin's code", "%d of %d differ" % [bad[0], ROWS])
	_check(bad[1] == 0, "swing_next is the twin's to the bit", "%d of %d differ" % [bad[1], ROWS])
	_check(bad[2] > 1000 and bad[3] > 1000 and bad[4] > 100, "rows landed, ended and did both at once", str(bad.slice(2)))
	_finished += 1

	_entered += 1
	print("random-walk rows, the stuck watchdog")
	var u := _unstick_rows(twin, nat)
	_check(u[0] == 0, "unstick_step is the twin's code", "%d of %d differ" % [u[0], ROWS])
	_check(u[1] > 100 and u[2] > 100 and u[3] > 100 and u[4] > 100 and u[5] > 100 and u[6] > 50,
		"rows held, reset, anchored, counted, nudged and relocated", str(u.slice(1)))
	_finished += 1

	_entered += 1
	print("random-walk rows, how often it thinks and the body stride")
	var e := _every_rows(twin, nat)
	_check(e[0] == 0, "every_early, every_tier and body_stride are the twin's", "%d of %d differ" % [e[0], ROWS])
	_check(e[1] > 500 and e[2] > 500 and e[3] > 500 and e[4] > 500 and e[5] > 500,
		"rows thought every tick, every second, third, fourth and dormant", str(e.slice(1)))
	_finished += 1

	_entered += 1
	print("the kind machine, every state against every condition")
	var k := _kind_all(twin, nat)
	_check(k[0] == 0, "needs, pre and step are the twin's", "%d of %d differ" % [k[0], k[1]])
	_check(nat.call(&"kind_after_search", true) == twin.kind_after_search(true) and nat.call(&"kind_after_search", false) == twin.kind_after_search(false),
		"after_search is the twin's")
	var after_bad := 0
	for ok in [false, true]:
		for rem in [false, true]:
			if nat.call(&"kind_after_chase", ok, rem) != twin.kind_after_chase(ok, rem):
				after_bad += 1
	_check(after_bad == 0, "after_chase is the twin's")
	_check(_needs_cover(nat), "the conditions a state needs are all its step reads (the rest is masked off)")
	_finished += 1

	_entered += 1
	print("replays of random condition streams")
	var r := _replays(twin, nat)
	_check(r[0] == 0, "state and action match at every step", "%d of %d differ" % [r[0], r[1]])
	_check(r[2] > 1000 and r[3] > 1000 and r[4] > 500 and r[5] > 500 and r[6] > 100,
		"the streams chased, alerted, searched, lured and went back to idle", str(r.slice(2)))
	_finished += 1

	_report_sections(_entered, _finished, 6, 14)


func _r(rng: RandomNumberGenerator, lo: float, hi: float) -> float:
	return snappedf(rng.randf_range(lo, hi), 0.01) if rng.randf() < 0.5 else rng.randf_range(lo, hi)


func _swing_rows(twin: Object, nat: Object) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1001
	var out := [0, 0, 0, 0, 0]
	var now := 10.0
	for i in ROWS:
		now += rng.randf_range(0.0, 0.2)
		var scale := 0.8 if rng.randf() < 0.3 else 1.0
		var swing_at := INF
		if rng.randf() < 0.85:
			# Land on the boundaries now and then: the script compares with >=.
			var offs := [0.32 * scale, 0.87 * scale, 0.0, rng.randf_range(0.0, 1.2)]
			swing_at = now - offs[rng.randi() % 4]
		var landed := rng.randf() < 0.5
		var a: int = twin.swing_step(swing_at, landed, now, scale)
		var b: int = nat.call(&"swing_step", swing_at, landed, now, scale)
		if a != b:
			out[0] += 1
		if a == 1:
			out[2] += 1
		if a & 2 != 0:
			out[3] += 1
		if a == 3:
			out[4] += 1
		var interval := rng.randf_range(0.2, 1.5)
		if not is_same(twin.swing_next(now, scale, interval), nat.call(&"swing_next", now, scale, interval)) \
				or twin.swing_next(now, scale, interval) != nat.call(&"swing_next", now, scale, interval):
			out[1] += 1
	return out


func _unstick_rows(twin: Object, nat: Object) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1002
	var out := [0, 0, 0, 0, 0, 0, 0]
	for i in ROWS:
		var flying := rng.randf() < 0.1
		var limit := 0.0 if rng.randf() < 0.1 else rng.randf_range(0.5, 3.0)
		var no_try := rng.randf() < 0.15
		var wish := 0.0 if rng.randf() < 0.1 else rng.randf_range(0.0, 6.0)
		var here := Vector3(rng.randf_range(-30, 30), rng.randf_range(0, 6), rng.randf_range(-30, 30))
		var at := Vector3.INF
		if rng.randf() < 0.9:
			at = here + Vector3(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.4, 1.4), rng.randf_range(-1.4, 1.4)) * (0.2 if rng.randf() < 0.7 else 1.0)
		var for_s := rng.randf_range(0.0, 3.0)
		var stage := rng.randi() % 3
		var delta := rng.randf_range(0.0, 0.4)
		var a: int = twin.unstick_step(flying, limit, no_try, wish, here, at, for_s, stage, delta)
		var b: int = nat.call(&"unstick_step", flying, limit, no_try, wish, here, at, for_s, stage, delta)
		if a != b:
			out[0] += 1
		out[1 + a] += 1
	return out


func _every_rows(twin: Object, nat: Object) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1003
	var out := [0, 0, 0, 0, 0, 0]
	for i in ROWS:
		var flags := rng.randi() % 32
		var now := rng.randf_range(5.0, 20.0)
		var scale := 0.8 if rng.randf() < 0.3 else 1.0
		var swing_at := now - rng.randf_range(0.0, 1.0)
		var bad := false
		if twin.every_early(flags, now, swing_at, scale) != nat.call(&"every_early", flags, now, swing_at, scale):
			bad = true
		var nearest := rng.randf_range(0.0, 90.0)
		for edge in [6.0, 20.0, 45.0, 60.0]:
			if rng.randf() < 0.05:
				nearest = edge
		var dormant := 0.0 if rng.randf() < 0.4 else rng.randf_range(40.0, 90.0)
		var every := 8 + rng.randi() % 24
		var t: int = twin.every_tier(nearest, dormant, every)
		if t != nat.call(&"every_tier", nearest, dormant, every):
			bad = true
		var near := rng.randf_range(5.0, 25.0)
		var far := near + rng.randf_range(0.0, 30.0)
		var cheap := 0.0 if rng.randf() < 0.5 else rng.randf_range(10.0, 80.0)
		if twin.body_stride(nearest, near, far, dormant, cheap) != nat.call(&"body_stride", nearest, near, far, dormant, cheap):
			bad = true
		if bad:
			out[0] += 1
		if t == 1:
			out[1] += 1
		elif t == 2:
			out[2] += 1
		elif t == 3:
			out[3] += 1
		elif t == 4:
			out[4] += 1
		elif t >= 8 and dormant > 0.0 and nearest >= dormant:
			out[5] += 1
	return out


func _kind_all(twin: Object, nat: Object) -> Array:
	var bad := 0
	var n := 0
	for state in range(-1, 6):
		n += 1
		if twin.kind_needs(state) != nat.call(&"kind_needs", state):
			bad += 1
		for c in 1024:
			n += 2
			if twin.kind_pre(state, c) != nat.call(&"kind_pre", state, c):
				bad += 1
			if twin.kind_step(state, c) != nat.call(&"kind_step", state, c):
				bad += 1
	return [bad, n]


func _needs_cover(nat: Object) -> bool:
	for state in range(0, 5):
		var need: int = nat.call(&"kind_needs", state)
		for c in 1024:
			if nat.call(&"kind_step", state, c & need) != nat.call(&"kind_step", state, c):
				return false
	return true


## Random condition streams: each step builds the mask the state needs, steps both and follows the answer, with
## the search and chase callbacks drawn at random.
func _replays(twin: Object, nat: Object) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1004
	var out := [0, 0, 0, 0, 0, 0, 0]
	for s in STREAMS:
		var st_t := ThinkCore.IDLE
		var st_n := ThinkCore.IDLE
		for i in STEPS:
			out[1] += 1
			var c := 0
			for bit in 10:
				if rng.randf() < (0.15 if bit != 6 else 0.4):
					c |= 1 << bit
			var pt: int = twin.kind_pre(st_t, c)
			var pn: int = nat.call(&"kind_pre", st_n, c)
			if pt != pn:
				out[0] += 1
			if pt >= 0:
				st_t = pt
				st_n = pn
			var need: int = nat.call(&"kind_needs", st_n)
			var rt: int = twin.kind_step(st_t, c & need)
			var rn: int = nat.call(&"kind_step", st_n, c & need)
			if rt != rn or st_t != st_n:
				out[0] += 1
			var next := rn & 255
			var act := rn >> 8
			match act:
				ThinkCore.A_ALERT, ThinkCore.A_ALERT_FORCE:
					out[3] += 1
				ThinkCore.A_SEARCH:
					out[4] += 1
					var running := rng.randf() < 0.8
					var at: int = twin.kind_after_search(running)
					var an: int = nat.call(&"kind_after_search", running)
					if at != an:
						out[0] += 1
					next = an & 255
					if next == ThinkCore.IDLE:
						out[6] += 1
				ThinkCore.A_CHASE:
					out[2] += 1
					var ok := rng.randf() < 0.9
					var rem := rng.randf() < 0.5
					var at2: int = twin.kind_after_chase(ok, rem)
					var an2: int = nat.call(&"kind_after_chase", ok, rem)
					if at2 != an2:
						out[0] += 1
					next = an2 & 255
					if next == ThinkCore.IDLE:
						out[6] += 1
				ThinkCore.A_LURE_GO, ThinkCore.A_LURE_HOLD:
					out[5] += 1
			st_t = next
			st_n = next
	return out
