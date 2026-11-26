extends "zz_suite.gd"

const ZzLoadoutBar := preload("../game/zz_loadout_bar.gd")

## The HUD's loadout row: the slot dictionaries it takes, one picture per slot, the weight line, and its footprint.

const SECTIONS := 4
const CHECKS := 16


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone loadout bar")
	print("")
	_test_slots()
	_test_weight()
	_test_hud_has_no_boxes()
	_test_downs()
	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _picture() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(8, 4, false, Image.FORMAT_RGBA8))


func _test_slots() -> void:
	_section("slots")
	var bar := ZzLoadoutBar.new()
	add_child(bar)
	_check(bar.slot_count() == 0 and bar.footprint().size == Vector2.ZERO, "empty: nothing drawn")
	var tex := _picture()
	bar.set_slots([{"key": "1", "icon": tex, "text": "12 / 60", "selected": true}, {"key": "2", "icon": tex, "text": "8 / 8"}])
	_check(bar.slot_count() == 2, "two slots in")
	var rect := bar.footprint()
	_check(rect.size.x == 2.0 * ZzLoadoutBar.SLOT_W + ZzLoadoutBar.GAP, "the row is two slots and a gap wide")
	_check(is_equal_approx(rect.end.x, bar.size.x), "the row stays anchored at the right")
	bar.set_slots([])
	_check(bar.slot_count() == 0, "an empty row clears it")
	bar.queue_free()
	_finished()


func _test_weight() -> void:
	_section("weight")
	var bar := ZzLoadoutBar.new()
	add_child(bar)
	bar.set_weight(4.25, 10.0, 2, 3)
	_check(bar.weight_text() == "4.2 / 10.0" or bar.weight_text() == "4.3 / 10.0", "the line reads carried / limit")
	_check(bar.pack_text() == "PACK 2", "the pack count is its own text")
	bar.set_weight(4.0, 10.0)
	_check(bar.pack_text() == "", "no pack tiers, no pack text")
	_check(bar.footprint().size.y > ZzLoadoutBar.SLOT_H - 1.0, "the weight row is part of the footprint")
	bar.queue_free()
	_finished()


func _test_hud_has_no_boxes() -> void:
	_section("no help boxes, no speed")
	var text := FileAccess.get_file_as_string("res://game/zz_hud.gd")
	_check(text.find("SLOWED") < 0, "no slowed text")
	_check(text.find("USE_TEXT") < 0, "no pickup help text")
	_check(text.find("km/h") < 0 and text.find("speed_label") < 0, "no speed readout")
	_finished()


func _test_downs() -> void:
	_section("downs chip")
	var pips := ZzDownsPips.new()
	add_child(pips)
	pips.set_downs(2, 3)
	_check(pips.visible and pips.text() == "2 / 3" and pips.downs_left() == 2, "two of three downs left")
	_check(pips.chip_width() > 60.0, "the chip has a width")
	pips.set_downs(9, 3)
	_check(pips.downs_left() == 3, "more than the total is clamped")
	pips.set_downs(0, 0)
	_check(not pips.visible, "no downs rule, no chip")
	pips.queue_free()
	_finished()
