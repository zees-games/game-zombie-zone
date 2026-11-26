extends GSGameCheckSuite

const ZzZombieLod := preload("../npcs/zz_zombie_lod.gd")

## The client's zombie level of detail judged for the whole crowd by gs-sim ([code]GSSimPresentLod[/code]) gives
## every zombie the clip rate and shadow the per-zombie script gives, at every preset and camera. Without the
## library the native half is skipped; [code]GS_SIM_REQUIRE_NATIVE=1[/code] (CI) fails instead.

const SECTIONS := 2
const CHECKS := 5
const NATIVE := &"GSSimPresentLod"
const VIEWS := 30
const BODIES := 120

var _entered := 0
var _finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone native lod")
	print("")
	_entered += 1
	print("the library has the present judge")
	if not ClassDB.class_exists(NATIVE):
		print("  gs-sim's present module is not loaded: the native half is skipped")
		_check(OS.get_environment("GS_SIM_REQUIRE_NATIVE") != "1", "the library is loaded (GS_SIM_REQUIRE_NATIVE=1)")
		_finished += 1
		_report_sections(_entered, _finished, SECTIONS - 1, 1)
		return
	_check(ZzZombieLod.new().batched(), "a lod judge is native when the library is")
	_finished += 1

	_entered += 1
	print("random crowds and cameras, script judge against native codes")
	var cam := Camera3D.new()
	add_child(cam)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var bad_every := 0
	var bad_shadow := 0
	var offscreen := 0
	var far_count := 0
	var total := 0
	for v in VIEWS:
		var lod := ZzZombieLod.new()
		lod.apply_detail(v % 3)
		cam.global_transform = Transform3D(Basis.from_euler(Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * TAU, 0.0)),
			Vector3(rng.randf_range(-50, 50), rng.randf_range(1, 6), rng.randf_range(-50, 50)))
		lod.refresh(cam)
		var ats := PackedVector3Array()
		for i in BODIES:
			ats.append(cam.global_position + Vector3(rng.randf_range(-120, 120), rng.randf_range(-3, 3), rng.randf_range(-120, 120)))
		var codes := lod.classify(ats)
		if codes.size() != ats.size():
			bad_every += BODIES
			continue
		for i in BODIES:
			var want := lod.every(ats[i])
			offscreen += 1 if want == lod.offscreen_every and want != 1 else 0
			far_count += 1 if want == 4 else 0
			total += 1
			if lod.every_coded(codes[i]) != want:
				bad_every += 1
			if lod.shadowed_coded(codes[i]) != (lod.camera_at.distance_to(ats[i]) < lod.shadow_until):
				bad_shadow += 1
	_check(total == VIEWS * BODIES, "every body was judged", "%d of %d" % [total, VIEWS * BODIES])
	_check(bad_every == 0, "the same clip rate for every body", "%d differ" % bad_every)
	_check(bad_shadow == 0, "the same shadow for every body", "%d differ" % bad_shadow)
	_check(offscreen > 300 and far_count > 100, "the crowds had unseen and far bodies",
		"%d unseen, %d far" % [offscreen, far_count])
	_finished += 1
	cam.queue_free()
	await get_tree().process_frame
	_report_sections(_entered, _finished, SECTIONS, CHECKS)
