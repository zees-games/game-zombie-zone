extends DotGameCheckSuite

const CrowdGrid := preload("res://addons/dot_npc_ai/steer/dot_npc_ai_crowd_grid.gd")
const ZzConfig := preload("../game/zz_config.gd")

## The horde's crowd grid in dot-sim ([member ZzConfig.native_crowd], on by default) answers exactly as dot-npc-ai's
## script grid: over seeded crowds (spread, packed, stacked on one spot, either side of zero) both give the same index
## for every id, the same neighbours in the same order for every query (narrow, and wide enough to walk them all), and
## the same spacing push to the bit for every zombie, before and after some are forgotten mid-tick. Spacing feeds the
## brains' steering only; hit registration and the sim's rules are not touched.
## With no library the native half is skipped; [code]DOT_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const SECTIONS := 3
const CHECKS := 9
const NATIVE := &"DotSimCrowdGrid"
const GRID := 4.0
const SEEDS := 24

var _entered := 0
var _finished := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone native crowd")
	print("")
	_entered += 1
	print("the crowd is native by default, and the library is there")
	_check(ZzConfig.new().native_crowd, "ZzConfig.native_crowd is on by default")
	if not ClassDB.class_exists(NATIVE):
		print("  dot-sim's crowd module is not loaded: the native half is skipped")
		_check(OS.get_environment("DOT_SIM_REQUIRE_NATIVE") != "1", "the library is loaded (DOT_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, SECTIONS - 2, 2)
		return
	_check(true, "the library has the crowd grid")
	_finished += 1

	_entered += 1
	print("seeded crowds, script grid against native grid")
	var rng := RandomNumberGenerator.new()
	var bad := {"index": 0, "near": 0, "separation": 0, "forgot": 0, "describe": 0}
	var counted := {"near": 0, "pushes": 0, "wide": 0}
	for s in SEEDS:
		rng.seed = 1000 + s
		_compare(rng, s, bad, counted)
	_check(bad["index"] == 0, "every id has the same index", "%d differ" % bad["index"])
	_check(bad["near"] == 0, "every query finds the same neighbours in the same order", "%d differ" % bad["near"])
	_check(bad["separation"] == 0, "every spacing push is the same to the bit", "%d differ" % bad["separation"])
	_check(bad["forgot"] == 0, "the same after some are forgotten mid-tick", "%d differ" % bad["forgot"])
	_check(bad["describe"] == 0, "the same entries and cells", "%d differ" % bad["describe"])
	_check(counted["pushes"] > 2000 and counted["wide"] > 100,
		"the crowds pushed and the wide walks ran", "%d pushes, %d wide queries" % [counted["pushes"], counted["wide"]])
	_finished += 1

	_entered += 1
	print("one grid refilled tick after tick keeps answering the same")
	_check(_refill(rng), "fifty refills of a moving crowd give the same pushes")
	_finished += 1

	_report_sections(_entered, _finished, SECTIONS, CHECKS)


## Up to 300 zombies: some spread over 120 m, some packed in a few metres, some on exactly one spot.
func _crowd(rng: RandomNumberGenerator, s: int) -> Array:
	var ids := PackedInt64Array()
	var at := PackedVector3Array()
	var n := rng.randi_range(1, 300)
	var centre := Vector3(rng.randf_range(-60, 60), rng.randf_range(-5, 5), rng.randf_range(-60, 60))
	for i in n:
		var kind := rng.randi() % 4
		var p: Vector3
		match kind:
			0:
				p = Vector3(rng.randf_range(-60, 60), rng.randf_range(-3, 6), rng.randf_range(-60, 60))
			1:
				p = centre + Vector3(rng.randf_range(-3, 3), rng.randf_range(-0.5, 0.5), rng.randf_range(-3, 3))
			2:
				p = centre
			_:
				p = Vector3(rng.randf_range(-4, 4), rng.randf_range(-2, 2), rng.randf_range(-4, 4))
		ids.append(1 + s * 100000 + i * 7 + rng.randi() % 5)
		at.append(p)
	return [ids, at]


func _compare(rng: RandomNumberGenerator, s: int, bad: Dictionary, counted: Dictionary) -> void:
	var c := _crowd(rng, s)
	var ids: PackedInt64Array = c[0]
	var at: PackedVector3Array = c[1]
	var script_grid := CrowdGrid.new(GRID)
	var native: Object = ClassDB.instantiate(NATIVE)
	native.call(&"setup", GRID)
	for i in ids.size():
		var _a := script_grid.add(ids[i], at[i])
	# Half the seeds through add, half through fill, as the horde does.
	if s % 2 == 0:
		native.call(&"fill", ids, at)
	else:
		for i in ids.size():
			native.call(&"add", ids[i], at[i])

	var d1 := script_grid.describe()
	var d2: Dictionary = native.call(&"describe")
	if d1["entries"] != d2["entries"] or d1["cells"] != d2["cells"]:
		bad["describe"] += 1
	for id in ids:
		if script_grid.index_of(id) != int(native.call(&"index_of", id)) or script_grid.has(id) != bool(native.call(&"has", id)):
			bad["index"] += 1
	if script_grid.index_of(-5) != int(native.call(&"index_of", -5)):
		bad["index"] += 1

	var scratch := PackedInt32Array()
	for q in 60:
		var point := at[rng.randi() % at.size()] + Vector3(rng.randf_range(-3, 3), rng.randf_range(-1, 1), rng.randf_range(-3, 3))
		var radius: float = [0.5, 1.1, 2.2, 6.0, 40.0, 200.0][q % 6]
		var a := script_grid.near(point, radius, scratch).duplicate()
		var b: PackedInt32Array = native.call(&"near", point, radius, scratch)
		counted["near"] += 1
		if radius >= 40.0:
			counted["wide"] += 1
		if a != b:
			bad["near"] += 1

	bad["separation"] += _pushes(rng, script_grid, native, ids, at, counted)

	for k in int(ids.size() / 5.0):
		var i := rng.randi() % ids.size()
		script_grid.forget(i)
		native.call(&"forget", i)
	bad["forgot"] += _pushes(rng, script_grid, native, ids, at, counted)


## Every zombie's push both ways, as the brain asks it (index, then push from where it stands now).
func _pushes(rng: RandomNumberGenerator, script_grid: CrowdGrid, native: Object, ids: PackedInt64Array,
		at: PackedVector3Array, counted: Dictionary) -> int:
	var bad := 0
	for i in ids.size():
		var own := script_grid.index_of(ids[i])
		var from := at[i] + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.1, 0.1), rng.randf_range(-0.3, 0.3))
		var spacing: float = [0.6, 1.1, 1.5][i % 3]
		var right := Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)) if i % 7 != 0 else Vector3.ZERO
		var a := script_grid.separation(own, from, spacing, spacing * 2.0, right)
		var b: Vector3 = native.call(&"separation", own, from, spacing, spacing * 2.0, right)
		var c: Vector3 = native.call(&"separation_of", ids[i], from, spacing, spacing * 2.0, right)
		if a != Vector3.ZERO:
			counted["pushes"] += 1
		if a != b or a != c:
			bad += 1
	return bad


func _refill(rng: RandomNumberGenerator) -> bool:
	rng.seed = 77
	var c := _crowd(rng, 3)
	var ids: PackedInt64Array = c[0]
	var at: PackedVector3Array = c[1]
	var script_grid := CrowdGrid.new(GRID)
	var native: Object = ClassDB.instantiate(NATIVE)
	native.call(&"setup", GRID)
	for tick in 50:
		script_grid.clear()
		native.call(&"clear")
		for i in at.size():
			at[i] += Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))
			var _a := script_grid.add(ids[i], at[i])
		native.call(&"fill", ids, at)
		var counted := {"pushes": 0}
		if _pushes(rng, script_grid, native, ids, at, counted) != 0:
			return false
	return true
