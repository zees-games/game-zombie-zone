extends DotGameCheckSuite
## Collision against the drawn mesh on 4-Way Tunnel (nightly zz-4way-blocked-1): a warehouse shelf boxed a whole grid cell (0.26 m) proud of
## its posts, which read as an invisible wall beside the red door frame. dot-map's decomposition now cuts each box back to the surface.

const CollideProbe := preload("../tools/collide_probe.gd")

const NavWalls := preload("../tools/nav_walls.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")

const SECTIONS := 2
const CHECKS := 7
## What the probe finds today (it was 4 invisible hits, 3 of them the shelves, before the cut-back).
const MAX_INVISIBLE := 2
const MAX_INVISIBLE_PROPS := 1

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
	_nav_walls()
	_report_sections(_entered, _finished, SECTIONS, CHECKS)


## The manor's cellar walls reach the ground floor, so a floor test took them for slabs and the graph laid points inside them (14 of 58242).
func _nav_walls() -> void:
	print("zombiezone nav against walls")
	_entered += 1
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/ze_biohazard_manor.json"))
	var extra: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://maps/hulls/ze_biohazard_manor.nav.json"))

	if doc is Dictionary and extra is Dictionary:
		var merged := ZzNpcs.with_nav_extra(doc, extra)
		var nav := ZzNpcs.nav_for(merged, func(_id: StringName) -> Vector3: return Vector3.ZERO)
		var walls := NavWalls.count(nav, merged)
		_check(nav.point_count() > 50000, "the manor's graph keeps its ground (%d points)" % nav.point_count())
		_check(walls["inwall"] == 0, "no graph point inside a wall (%d)" % walls["inwall"])
		_finished += 1
	else:
		_check(false, "the manor document and its nav extra read")
