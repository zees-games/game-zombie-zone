extends GSGameCheckSuite

const CrowdGrid := preload("res://addons/gs_npc_ai/steer/gs_npc_ai_crowd_grid.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzHorde := preload("../game/zz_horde.gd")

## The stand-ins' look at the crowd in gs-sim ([member ZzConfig.native_threat], on by default) answers as
## `zz_bots.gd`'s script `_threat` ranking and `_crowd_within` count over seeded crowds: the same ten zombies in the
## same order (specials twelve metres closer, a sitting sleeper never), the same calm, the same commons count. The
## script reference below is that code, on plain arrays. Without the library the native half is skipped;
## [code]GS_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const SECTIONS := 3
const CHECKS := 9
const NATIVE := &"GSSimBotThreat"
const GRID_CLASS := &"GSSimCrowdGrid"
const GRID := 4.0
const SEEDS := 24

var _entered := 0
var _finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone native threat")
	print("")
	_entered += 1
	print("the threat ranking is native by default, and the library is there")
	_check(ZzConfig.new().native_threat, "ZzConfig.native_threat is on by default")
	if not ClassDB.class_exists(NATIVE) or not ClassDB.class_exists(GRID_CLASS):
		print("  gs-sim's threat module is not loaded: the native half is skipped")
		_check(OS.get_environment("GS_SIM_REQUIRE_NATIVE") != "1", "the library is loaded (GS_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, SECTIONS - 2, 2)
		return
	_check(true, "the library has the threat ranking")
	_finished += 1

	_entered += 1
	print("seeded crowds, script ranking against native ranking")
	var bad := {"rank": 0, "calm": 0, "commons": 0, "forgot": 0}
	var counted := {"queries": 0, "full": 0, "calm": 0, "sitting": 0}
	for s in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5000 + s
		_compare(rng, bad, counted)
	_check(bad["rank"] == 0, "every query ranks the same zombies in the same order", "%d differ" % bad["rank"])
	_check(bad["calm"] == 0, "every query is as calm", "%d differ" % bad["calm"])
	_check(bad["commons"] == 0, "every reach counts the same commons", "%d differ" % bad["commons"])
	_check(bad["forgot"] == 0, "the same after some are forgotten mid-tick", "%d differ" % bad["forgot"])
	_check(counted["full"] > 100 and counted["calm"] > 20 and counted["sitting"] > 20,
		"the crowds filled the ten, were calm, and had sitters", "%s" % [counted])
	_finished += 1

	_entered += 1
	print("a horde turns it on with its crowd grid")
	var h := ZzHorde.new()
	h.config = ZzConfig.new()
	h._pick_crowd()
	_check(h.threat_is_native() and h.threat_native != null, "a default horde asks gs-sim")
	h.config.native_threat = false
	h._pick_crowd()
	_check(not h.threat_is_native(), "native_threat off hands it back to the script")
	h.free()
	_finished += 1

	_report_sections(_entered, _finished, SECTIONS, CHECKS)


## One seeded crowd: heights, kinds, sitters, forgotten ones; asked from several survivors.
func _compare(rng: RandomNumberGenerator, bad: Dictionary, counted: Dictionary) -> void:
	var common := ClassDB.class_get_integer_constant(NATIVE, &"COMMON")
	var special := ClassDB.class_get_integer_constant(NATIVE, &"SPECIAL")
	var sit := ClassDB.class_get_integer_constant(NATIVE, &"SITTING")
	var n := rng.randi_range(1, 120)
	var ids := PackedInt64Array()
	var at := PackedVector3Array()
	var height: Array[float] = []
	var kind: Array[int] = []
	var sitting: Array[bool] = []
	var native: Object = ClassDB.instantiate(NATIVE)
	var grid: Object = ClassDB.instantiate(GRID_CLASS)
	grid.call(&"setup", GRID)
	var centre := Vector3(rng.randf_range(-20, 20), 0.0, rng.randf_range(-20, 20))

	for i in n:
		ids.append(100 + i * 3)
		var p := centre + Vector3(rng.randf_range(-30, 30), rng.randf_range(-2, 2), rng.randf_range(-30, 30))
		if rng.randf() < 0.3:
			p = centre + Vector3(rng.randf_range(-3, 3), 0.0, rng.randf_range(-3, 3))
		at.append(p)
		height.append(rng.randf_range(0.5, 3.0) if rng.randf() < 0.8 else 1.7)
		var roll := rng.randf()
		kind.append(common if roll < 0.65 else special if roll < 0.9 else 0)
		sitting.append(kind[i] == special and rng.randf() < 0.4)
		native.call(&"register", ids[i], height[i], kind[i] | (sit if sitting[i] else 0))
	grid.call(&"fill", ids, at)

	var script_grid := CrowdGrid.new(GRID)
	for i in n:
		var _a := script_grid.add(ids[i], at[i])

	var forgotten := {}
	for _f in rng.randi_range(0, n / 4):
		var k := rng.randi() % n
		forgotten[k] = true
		grid.call(&"forget", k)
		script_grid.forget(k)
		native.call(&"forget", ids[k])

	var scratch := PackedInt32Array()
	for q in 12:
		var feet := centre + Vector3(rng.randf_range(-25, 25), 0.0, rng.randf_range(-25, 25))
		var eye := feet + Vector3(0.0, 1.6, 0.0)
		var radius: float = [12.0, 25.0, 40.0][q % 3]
		var calm_radius: float = [1.5, 3.0, 6.0][(q / 3) % 3]
		var near := script_grid.near(feet, radius, scratch)
		var want := _script_rank(near, at, height, kind, sitting, forgotten, feet, eye, calm_radius)
		var got: PackedInt32Array = native.call(&"rank", grid, feet, eye, radius, calm_radius)
		counted["queries"] += 1
		counted["full"] += 1 if want[0].size() == 10 else 0
		counted["calm"] += 1 if want[1] else 0
		counted["sitting"] += 1 if sitting.has(true) else 0
		if want[0] != Array(got):
			bad["rank"] += 1
		if want[1] != bool(native.call(&"calm")):
			bad["calm"] += 1
		var reach: float = [2.0, 6.0, 15.0][q % 3]
		var commons := 0
		for i in script_grid.near(feet, reach, scratch):
			if kind[i] == common:
				commons += 1
		if commons != int(native.call(&"commons", grid, feet, reach)):
			bad["commons"] += 1
	if not forgotten.is_empty():
		for k in forgotten:
			if int(native.call(&"registered")) != n - forgotten.size():
				bad["forgot"] += 1
				break


## `zz_bots.gd` `_threat`'s scoring and ordering on plain arrays: [the ten best crowd indices, calm].
func _script_rank(near: PackedInt32Array, at: PackedVector3Array, height: Array[float], kind: Array[int],
		sitting: Array[bool], forgotten: Dictionary, feet: Vector3, eye: Vector3, calm_radius: float) -> Array:
	var special := ClassDB.class_get_integer_constant(NATIVE, &"SPECIAL")
	var keys := PackedInt64Array()
	var close_sq := calm_radius * calm_radius
	var calm := true
	for j in near.size():
		var i := near[j]
		if forgotten.has(i):
			continue
		if calm and at[i].distance_squared_to(feet) < close_sq:
			calm = false
		if sitting[i]:
			continue
		var score := (at[i] + Vector3(0.0, height[i] * 0.72, 0.0)).distance_to(eye)
		if kind[i] == special:
			score -= 12.0
		keys.append((int((score + 64.0) * 1000.0) << 12) | j)
	keys.sort()
	var out: Array = []
	for n in mini(keys.size(), 10):
		out.append(near[keys[n] & 0xFFF])
	return [out, calm]
