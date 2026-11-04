extends DotGameCheckSuite

const ZzBindings := preload("../game/zz_bindings.gd")
const ZzTouch := preload("../game/zz_touch.gd")

## The touch layout: every button presses an action the input bindings define, no two overlap, and it exists only where there is touch.
##
## [codeblock]
## godot --headless --path . res://examples/headless_touch.tscn
## [/codeblock]

const CHECKS := 17


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-zombie-zone: touch buttons")
	var keys := ZzBindings.make()
	var rows := PackedStringArray()
	for row in keys.rows:
		rows.append(String(row.action))
	var ids := ZzTouch.actions()
	_check(ids.size() == ZzTouch.LAYOUT.size() and ids.size() >= 9, "the layout has fire, aim and the secondary actions")
	for id in ids:
		_check(rows.has(String(id)), "%s is an action in the bindings" % id)
	_check(ids.has(ZzBindings.FIRE) and ids.has(ZzBindings.AIM) and ids.has(ZzBindings.RELOAD) and ids.has(ZzBindings.USE), "fire, aim, reload and use are on it")

	DotPlatform.touch_override = 0
	var none := ZzTouch.new_sampler(DotFpsTunables.new())
	_check(not none is DotFpsTouchSampler, "no touch: the plain sampler")
	DotPlatform.touch_override = 1
	_check(ZzTouch.new_sampler(DotFpsTunables.new()) is DotFpsTouchSampler, "touch: the touch sampler")
	var buttons := ZzTouch.new()
	buttons.size = Vector2(844, 390)
	add_child(buttons)
	_check(buttons.visible, "touch: the buttons show")
	var seen := _overlaps(buttons, ids)
	_check(seen == "", "no two buttons overlap", seen)
	var foot := buttons.footprint()
	_check(Rect2(Vector2.ZERO, buttons.size).encloses(foot) and foot.position.y >= 66.0, "the cluster is on a phone screen and clear of the Menu button", str(foot))
	buttons.free()
	DotPlatform.touch_override = 0
	var off := ZzTouch.new()
	add_child(off)
	_check(not off.visible, "no touch: the buttons are hidden")
	off.free()
	DotPlatform.touch_override = -1
	_report(CHECKS)


func _overlaps(buttons: Control, ids: Array[StringName]) -> String:
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var gap: float = buttons.centre_of(ids[i]).distance_to(buttons.centre_of(ids[j])) - buttons.radius_of(ids[i]) - buttons.radius_of(ids[j])
			if gap < 4.0:
				return "%s and %s" % [ids[i], ids[j]]
	return ""
