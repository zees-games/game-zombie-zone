extends Node
## Collision against the drawn mesh on 4-Way Tunnel (nightly zz-4way-blocked-1): a warehouse shelf boxed a whole grid cell (0.26 m) proud of
## its posts, which read as an invisible wall beside the red door frame. dot-map's decomposition now cuts each box back to the surface.

const CollideProbe := preload("../tools/collide_probe.gd")

const SECTIONS := 1
const CHECKS := 5
## What the probe finds today (it was 4 invisible hits, 3 of them the shelves, before the cut-back).
const MAX_INVISIBLE := 2
const MAX_INVISIBLE_PROPS := 1

var _passed := 0
var _failed := 0
var _entered := 0
var _finished := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone collide")
	_entered += 1
	var probe := CollideProbe.new()
	probe.manual = true
	add_child(probe)
	var sweep: DotCollisionSweep = await probe.probe(&"zm_4way_tunnel", 2.0, 400, 6)
	if sweep != null:
		_check(sweep.count("floor_missing") == 0, "no drawn floor without collision")
		_check(sweep.count("wall_missing") == 0, "no drawn wall without collision")
		_check(sweep.count("wall_buried") == 0, "no wall buried")
		var props := sweep.count("invisible_wall", "SolidProps") + sweep.count("invisible_floor", "SolidProps")
		_check(props <= MAX_INVISIBLE_PROPS, "solid props (shelves) hold at most %d invisible hits, found %d" % [MAX_INVISIBLE_PROPS, props])
		var all := sweep.count("invisible_wall") + sweep.count("invisible_floor")
		_check(all <= MAX_INVISIBLE, "at most %d invisible hits, found %d" % [MAX_INVISIBLE, all])
		_finished += 1
	probe.queue_free()
	await get_tree().process_frame
	print("")
	print("%d sections entered, %d finished" % [_entered, _finished])
	print("%d passed, %d failed" % [_passed, _failed])
	var code := 1 if _failed > 0 else 0
	if _entered != _finished or _entered != SECTIONS or _passed + _failed != CHECKS:
		print("ERROR: %d of %d sections, %d of %d checks" % [_finished, SECTIONS, _passed + _failed, CHECKS])
		code = 1
	get_tree().quit(code)


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		print("  FAIL  %s" % what)
