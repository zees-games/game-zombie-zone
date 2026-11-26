class_name ZzLoadoutBar
extends GSHudPiece

## The loadout, bottom right: one slot per weapon (or medkit, pill, anything the carrier keeps ready),
## laid out in a row, and the weight bar over them. Values in, never a game object.
##
## [b]Slot API[/b] ([method set_slots]; the inventory and healing work plugs in through it). Each slot is
## a Dictionary:
## [codeblock]
## {
##     "key": "1",                 # the key cap (String); "" for none
##     "icon": Texture2D,          # exactly one picture; null draws the slot's name instead
##     "name": "AK",               # shown only when there is no icon
##     "text": "30 / 120",         # the small line under the icon (ammo, count); "" for none
##     "selected": true,           # in hand
##     "low": false,               # the line in the low colour
##     "empty": false,             # nothing there: drawn faint (a vacant slot, a used-up kit)
##     "accent": Color(...),       # optional: the selected edge's colour (a medkit may be green)
## }
## [/codeblock]
## Weapons first, then whatever else the host appends: the row grows to the left and stays anchored at the
## right. [method set_weight] feeds the bar above it; [method clear_weight] hides it.

const SLOT_W := 104.0
const SLOT_H := 66.0
const GAP := 8.0
const WEIGHT_H := 30.0
const MAX_SLOTS := 8
## Easing, per second, of a slot's selected lift and the weight bar's fill.
const EASE := 14.0

var _slots: Array = []
var _lift: Array[float] = []
## Texture instance id -> its drawn rect (see [method _used_rect]).
var _used: Dictionary = {}

var _weight_on: bool = false
var _carried: float = 0.0
var _limit: float = 1.0
var _pack: int = 0
var _pack_max: int = 0
var _shown_share: float = 0.0


func _init() -> void:
	super._init()
	custom_minimum_size = Vector2(MAX_SLOTS * (SLOT_W + GAP), SLOT_H + WEIGHT_H)


## Replaces the row. Equal rows redraw nothing.
func set_slots(slots: Array) -> void:
	if slots == _slots:
		return
	_slots = slots.duplicate()
	while _lift.size() < _slots.size():
		_lift.append(0.0)
	_lift.resize(_slots.size())
	queue_redraw()


func slot_count() -> int:
	return _slots.size()


func set_weight(carried: float, limit: float, pack: int = 0, pack_max: int = 0) -> void:
	_weight_on = true
	_carried = carried
	_limit = maxf(limit, 0.1)
	_pack = pack
	_pack_max = pack_max
	queue_redraw()


func clear_weight() -> void:
	if _weight_on:
		_weight_on = false
		queue_redraw()


## The weight line as drawn, for a check: "4.2 / 10.0" and the pack "PACK 2".
func weight_text() -> String:
	var out := "%.1f / %.1f" % [_carried, _limit]
	return out


func pack_text() -> String:
	return "PACK %d" % _pack if _pack_max > 0 else ""


func footprint() -> Rect2:
	if _slots.is_empty() and not _weight_on:
		return Rect2()
	var width := _row_width()
	var top := 0.0 if _weight_on else WEIGHT_H
	return Rect2(size.x - width, top, width, size.y - top)


func _row_width() -> float:
	var n := maxi(_slots.size(), 1)
	return float(n) * SLOT_W + float(n - 1) * GAP


func _process(delta: float) -> void:
	super._process(delta)
	var moving := false
	var step := 1.0 - exp(-EASE * delta)
	for i in _slots.size():
		var goal := 1.0 if bool((_slots[i] as Dictionary).get("selected", false)) else 0.0
		if absf(_lift[i] - goal) > 0.002:
			_lift[i] = lerpf(_lift[i], goal, step)
			moving = true
	var share := minf(_carried / _limit, 1.0) if _weight_on else 0.0
	if absf(_shown_share - share) > 0.002:
		_shown_share = lerpf(_shown_share, share, step)
		moving = true
	if moving:
		queue_redraw()


func _draw() -> void:
	var width := _row_width()
	var left := size.x - width
	var slots_top := size.y - SLOT_H
	if _weight_on:
		_draw_weight(Rect2(left, 0.0, width, WEIGHT_H - 8.0))
	for i in _slots.size():
		var rect := Rect2(left + float(i) * (SLOT_W + GAP), slots_top, SLOT_W, SLOT_H)
		_draw_slot(_slots[i], rect, _lift[i])


func _draw_weight(area: Rect2) -> void:
	var share := _carried / _limit
	var tone := colour(&"low") if share > 1.0 else (colour(&"highlight") if share > 0.8 else colour(&"good"))
	ink_text(Vector2(area.position.x, area.position.y + 12.0), "WEIGHT", 12, colour(&"dim"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4)
	ink_text(Vector2(area.position.x + 62.0, area.position.y + 12.0), weight_text(), 13, tone, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4)
	var pack := pack_text()
	if pack != "":
		ink_text(Vector2(area.position.x, area.position.y + 12.0), pack, 12, colour(&"dim"), HORIZONTAL_ALIGNMENT_RIGHT, area.size.x, 4)
	var bar := Rect2(area.position.x, area.end.y - 6.0, area.size.x, 6.0)
	ink_plate(bar, Color(0.0, 0.0, 0.0, 0.5), 3, Color(0, 0, 0, 0), 0)
	var fill := Rect2(bar.position, Vector2(bar.size.x * clampf(_shown_share, 0.0, 1.0), bar.size.y))
	if fill.size.x >= 3.0:
		ink_plate(fill, tone, 3, Color(0, 0, 0, 0), 0)


## The part of [param icon] that has pixels, so a thin knife fills the slot like a rifle does. Cached per texture.
func _used_rect(icon: Texture2D) -> Rect2:
	var id := icon.get_instance_id()
	if _used.has(id):
		return _used[id]
	var whole := Rect2(Vector2.ZERO, Vector2(icon.get_width(), icon.get_height()))
	var image := icon.get_image()
	if image != null and not image.is_empty() and not image.is_compressed():
		var box := image.get_used_rect()
		if box.size.x > 0 and box.size.y > 0:
			_used[id] = Rect2(box)
			return _used[id]
	# Not rendered yet (a viewport's first frames): the whole picture, and ask again next draw.
	return whole


func _draw_slot(slot: Dictionary, rect: Rect2, lift: float) -> void:
	var empty := bool(slot.get("empty", false))
	var alpha := 0.4 if empty else 1.0
	var accent: Color = slot.get("accent", colour(&"highlight"))
	rect.position.y -= 5.0 * lift
	# A lighter glass than the other plates: the weapon renders are dark metal and must read against it.
	var plate := Color(0.2, 0.24, 0.3, 0.74)
	plate = plate.lerp(Color(0.26, 0.31, 0.39, 0.9), lift * 0.7)
	var edge := colour(&"plate_edge").lerp(accent, lift)
	ink_plate(rect, Color(plate, plate.a * (0.6 + 0.4 * alpha)), 9, Color(edge, edge.a), 2 if lift > 0.5 else 1)

	var key := str(slot.get("key", ""))
	if key != "":
		var _w := ink_keycap(Vector2(rect.position.x + 7.0, rect.position.y + 14.0), key, 11, alpha)

	var icon: Texture2D = slot.get("icon", null)
	var picture := Rect2(rect.position + Vector2(8.0, 7.0), Vector2(rect.size.x - 16.0, rect.size.y - 29.0))
	if icon != null:
		var used := _used_rect(icon)
		var scale := minf(picture.size.x / used.size.x, picture.size.y / used.size.y)
		var drawn := used.size * scale
		var shade := Color(1.0, 1.0, 1.0, alpha * (0.8 + 0.2 * lift))
		draw_texture_rect_region(icon, Rect2(picture.get_center() - drawn * 0.5, drawn), used, shade)
	else:
		ink_text(Vector2(picture.position.x, picture.get_center().y + 5.0), str(slot.get("name", "")), 14,
			Color(colour(&"text"), alpha), HORIZONTAL_ALIGNMENT_CENTER, picture.size.x, 4)

	var text := str(slot.get("text", ""))
	if text != "":
		var tone := colour(&"low") if bool(slot.get("low", false)) else colour(&"text").lerp(colour(&"dim"), 1.0 - lift)
		ink_text(Vector2(rect.position.x, rect.end.y - 8.0), text, 13, Color(tone, alpha), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 4)
