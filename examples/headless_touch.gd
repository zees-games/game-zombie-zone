extends DotGameCheckSuite

const ZzBindings := preload("../game/zz_bindings.gd")
const ZzTouch := preload("../game/zz_touch.gd")

## The touch layout: every button presses an action the input bindings define, no two overlap, and it exists only where there is touch.
##
## [codeblock]
## godot --headless --path . res://examples/headless_touch.tscn
## [/codeblock]

const CHECKS := 28


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
	# Size is set after add_child: with full-rect anchors a size set before the node has a parent is turned into offsets against a zero-size parent, and the tree then adds the viewport's 64 px.
	for screen in [Vector2(844, 390), Vector2(667, 375), Vector2(932, 430)]:
		var buttons := ZzTouch.new()
		add_child(buttons)
		buttons.size = screen
		var tag := " at %dx%d" % [screen.x, screen.y]
		_check(buttons.visible, "touch: the buttons show" + tag)
		_check(buttons.size == screen, "the control is the screen's size" + tag, str(buttons.size))
		var seen := _overlaps(buttons, ids)
		_check(seen == "", "no two buttons overlap" + tag, seen)
		var foot := buttons.footprint()
		_check(Rect2(Vector2.ZERO, buttons.size).encloses(foot) and (foot.position.y >= 66.0 or foot.position.x >= 130.0), "the cluster is on the screen and clear of the Menu button (top left, 130 x 66)" + tag, str(foot))
		if screen.x == 844.0:
			var downs := []
			buttons.button_down.connect(func(id: StringName) -> void: downs.append(id))
			var touch := InputEventScreenTouch.new()
			touch.pressed = true
			touch.position = buttons.centre_of(ZzBindings.FIRE)
			buttons._input(touch)
			_check(buttons.is_held(ZzBindings.FIRE) and downs == [ZzBindings.FIRE], "a touch on a button holds it")
			buttons.release_all()
			_check(not buttons.is_held(ZzBindings.FIRE), "release_all frees every held button")
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
