class_name ZzDownsPips
extends GSHudPiece

## The downs a survivor has left, as a chip over the health plate: DOWNS and one dot per life, filled
## while it is left. Values in ([method set_downs]); the game's rules stay outside.

const HEIGHT := 24.0
const DOT := 9.0
const DOT_GAP := 7.0
## More lives than this draw a count instead of dots.
const MAX_DOTS := 6
const EASE := 12.0

var _left: int = 0
var _total: int = 0
## 1 while a dot is filled, easing to 0 as a life goes.
var _fill: Array[float] = []


func _init() -> void:
	super._init()
	custom_minimum_size = Vector2(160.0, HEIGHT)


## [param left] of [param total] downs remain. Nothing drawn for a total of 0 or less.
func set_downs(left: int, total: int) -> void:
	if left == _left and total == _total:
		return
	_left = clampi(left, 0, maxi(total, 0))
	_total = maxi(total, 0)
	visible = _total > 0
	queue_redraw()


func downs_left() -> int:
	return _left


## What the chip says, for a check: "2 / 3".
func text() -> String:
	return "%d / %d" % [_left, _total]


func chip_width() -> float:
	var dots := minf(_total, MAX_DOTS) * (DOT + DOT_GAP) if _total <= MAX_DOTS else text_width(text(), 13) + DOT_GAP
	return 14.0 + text_width("DOWNS", 12) + 10.0 + dots + 4.0


func _process(delta: float) -> void:
	super._process(delta)
	var moving := false
	var step := 1.0 - exp(-EASE * delta)
	while _fill.size() < _total:
		_fill.append(1.0)
	_fill.resize(_total)
	for i in _total:
		var goal := 1.0 if i < _left else 0.0
		if absf(_fill[i] - goal) > 0.01:
			_fill[i] = lerpf(_fill[i], goal, step)
			moving = true
	if moving:
		queue_redraw()


func _draw() -> void:
	if _total <= 0:
		return
	var width := chip_width()
	ink_plate(Rect2(0.0, 0.0, width, HEIGHT), Color(0.04, 0.05, 0.06, 0.62), 12, colour(&"plate_edge"))
	var label := Color(0.78, 0.82, 0.86, 0.9)
	ink_text(Vector2(12.0, 16.0), "DOWNS", 12, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 0)
	var x := 12.0 + text_width("DOWNS", 12) + 12.0
	var low := _left <= 1
	var on := Color(0.95, 0.4, 0.34) if low else Color(0.86, 0.9, 0.94)
	if _total > MAX_DOTS:
		ink_text(Vector2(x, 16.0), text(), 13, on, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 0)
		return
	for i in _total:
		var at := Vector2(x + DOT * 0.5, HEIGHT * 0.5)
		var f := _fill[i] if i < _fill.size() else (1.0 if i < _left else 0.0)
		draw_circle(at, DOT * 0.5, Color(1, 1, 1, 0.14))
		if f > 0.01:
			draw_circle(at, DOT * 0.5 * f, on)
		x += DOT + DOT_GAP
