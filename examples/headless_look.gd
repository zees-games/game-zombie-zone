extends Node

const ZzBlood := preload("../game/zz_blood.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")

## Blood behind a hit body (zz_blood.gd over dot-fx's DotFxDecals) and which end of a hold's
## day a map's own light becomes (ZzMapDoc.take_derived_light).
##
## [codeblock]
## godot --headless --path . res://examples/headless_look.tscn
## [/codeblock]

const CHECKS := 15

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-zombie-zone: blood and the hold's day")
	await _blood()
	_light()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _blood() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 10, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	wall.global_position = Vector3(0, 2, -4)
	var blood := ZzBlood.new()
	add_child(blood)
	blood.mask = 0xFFFFFFFF
	blood.apply_settings(null)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var npc := DotEntity.make_id(DotEntity.KIND_NPC, 1)
	var from := Vector3(0, 1.7, 8)
	_check(blood.on_body_hit(npc, Vector3(0, 1.2, -1), from, 8.0) != null, "a hit NPC splatters the wall behind it")
	_check(blood.decals.blood_count() == 1, "one splatter is counted (%d)" % blood.decals.blood_count())
	_check(blood.on_body_hit(DotEntity.make_id(DotEntity.KIND_PLAYER, 2), Vector3(1, 1.2, -1), from, 8.0) != null, "a hit player splatters it too")
	_check(blood.on_body_hit(DotEntity.make_id(DotEntity.KIND_PROP, 3), Vector3(1, 1.2, -1), from, 8.0) == null, "a prop bleeds nothing")
	_check(blood.on_body_hit(npc, Vector3(0, 1.2, -1), from, 1.0) == null, "no surface in reach, no splatter")
	for i in 300:
		var _s := blood.on_body_hit(npc, Vector3(-5 + (i % 10), 1.0 + (i % 4) * 0.5, -1), from, 8.0)
	var cap: int = blood.decals.config.effective_blood_cap()
	_check(blood.decals.blood_count() <= cap, "the cap holds (%d of %d)" % [blood.decals.blood_count(), cap])
	blood.clear()
	_check(blood.decals.blood_count() == 0, "a map change clears the blood")

	var surf := Vector3(0, 1.5, -3.7)
	_check(blood.on_splat(surf, Vector3.BACK) == null, "a server splat with no camera is dropped, not drawn without the distance gate")
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.global_position = Vector3(0, 1.7, 8)
	var drawn := 0
	for i in 40:
		if blood.on_splat(surf + Vector3(i * 0.01, 0, 0), Vector3.BACK) != null:
			drawn += 1
	_check(drawn == ZzBlood.SPLATS_PER_SECOND, "server splats are capped per second (%d drawn of 40, cap %d)" % [drawn, ZzBlood.SPLATS_PER_SECOND])
	_check(blood.on_splat(Vector3(0, 1.5, -300), Vector3.BACK) == null, "a splat beyond 60 m of the camera is dropped")
	blood.clear()

	var off := DotFxDecalConfig.new()
	off.gore = false
	blood.decals.apply_config(off)
	_check(blood.on_body_hit(npc, Vector3(0, 1.2, -1), from, 8.0) == null or blood.decals.blood_count() == 0, "gore off draws none")
	var low := DotFxDecalConfig.new()
	low.quality = 0
	blood.decals.apply_config(low)
	var _q := blood.on_body_hit(npc, Vector3(0, 1.2, -1), from, 8.0)
	_check(blood.decals.blood_count() == 0, "effects quality 0 draws none")


func _light() -> void:
	var day := ZzMapDoc.DEFAULT_ENV.duplicate(true)
	day["sun_energy"] = 0.8
	var hold := {"mode": ZzMapDoc.SURVIVAL, "environment": ZzMapDoc.IMPORTER_ENV.duplicate(true)}
	ZzMapDoc.take_derived_light(hold, day)
	_check(hold["day_environment"] == day and ZzMapDoc.is_importer_env(hold["environment"]), "a hold's derived day is its day and the night stays")
	var night := ZzMapDoc.IMPORTER_ENV.duplicate(true)
	night["sun_energy"] = 0.2
	var dark_hold := {"mode": ZzMapDoc.SURVIVAL, "environment": ZzMapDoc.IMPORTER_ENV.duplicate(true)}
	ZzMapDoc.take_derived_light(dark_hold, night)
	_check(not dark_hold.has("day_environment") and dark_hold["environment"] == night, "a derived night replaces the night and leaves no day")
	var exodus := {"mode": ZzMapDoc.EXODUS, "environment": ZzMapDoc.IMPORTER_ENV.duplicate(true)}
	ZzMapDoc.take_derived_light(exodus, day)
	_check(exodus["environment"] == day and not exodus.has("day_environment"), "an exodus map takes the derived day as its light")


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what)
		print("  FAIL  %s" % what)
