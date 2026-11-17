extends DotGameCheckSuite

const ZzTouch := preload("../game/zz_touch.gd")
const ZzGameState := preload("../game/zz_game_state.gd")

## The phone's controls: the layout fits without overlapping, dot-mobile's overlay drives the client's sampler, the
## server's rules govern it, and auto-fire's crosshair shoots zombies but holds fire on survivors and the dead.
## Run: `godot --headless --path . res://examples/headless_touch.tscn`

const CHECKS := 29


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-zombie-zone: touch controls")
	var layout: Array[Dictionary] = ZzTouch.LAYOUT
	var ids: Array[StringName] = []
	var smallest := 999.0
	for b: Dictionary in layout:
		ids.append(b["id"])
		smallest = minf(smallest, float(b["radius"]))
	for want: StringName in [&"fire", &"jump", &"crouch", &"reload", &"next", &"use", &"heal"]:
		_check(want in ids, "the layout keeps the %s button" % want)
	_check(smallest * 2.0 >= 44.0, "every button is thumb size (44 px or more)", str(smallest * 2.0))
	for size: Vector2 in [Vector2(844, 390), Vector2(932, 430)]:
		var buttons := DotTouchButtons.new()
		buttons.size = size
		buttons.set_buttons(layout)
		add_child(buttons)
		var clash := ""
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var gap := buttons.centre_of(ids[i]).distance_to(buttons.centre_of(ids[j])) - buttons.radius_of(ids[i]) - buttons.radius_of(ids[j])
				if gap < 4.0:
					clash = "%s and %s" % [ids[i], ids[j]]
		_check(Rect2(Vector2.ZERO, size).encloses(buttons.footprint()) and clash == "", "the cluster fits %dx%d with no overlap" % [size.x, size.y], clash)
		buttons.free()
	var methods: Array = []
	for m: Dictionary in load("res://game/zz_client.gd").get_script_method_list():
		methods.append(m["name"])
	_check("touch_button" in methods and "_fire_held" in methods and "_touch_busy" in methods, "the split client carries the touch wiring")
	_overlay()
	await _crosshair()
	_report(CHECKS)


## A stand-in for a remote survivor: what the crosshair test reads.
class Survivor extends Node3D:
	pass


## A stand-in for a zombie's mirror body.
class Zombie extends Node3D:
	var height := 1.75
	var radius := 0.32


func _overlay() -> void:
	var rules: DotMobileRules = ZzGameState._make_mobile_rules()
	var prefs := DotMobilePrefs.new()
	_check(rules.resolve(prefs, true).autofire, "auto-fire is on for a touch player by default")
	_check(not rules.resolve(prefs, false).autofire, "and off for keyboard and mouse")
	DotPlatform.touch_override = 1
	var host := Control.new()
	host.size = Vector2(844, 390)
	add_child(host)
	var sampler := DotFpsTouchSampler.new(DotFpsTunables.new())
	var touch: RefCounted = ZzTouch.build(self, host, sampler, rules)
	var controls: DotMobileControls = touch.get(&"controls")
	_check(controls != null and controls.touch and controls.sampler == sampler, "the overlay drives the client's own sampler", str(touch.call(&"describe")))
	var other := DotFpsTouchSampler.new(DotFpsTunables.new())
	touch.call(&"attach", other)
	_check(controls.sampler == other, "offline play hands it the player's own sampler")
	var tap := InputEventScreenTouch.new()
	tap.pressed = true
	var fake := InputEventMouseMotion.new()
	fake.device = InputEvent.DEVICE_ID_EMULATION
	_check(bool(touch.call(&"takes", tap)) and bool(touch.call(&"takes", fake)), "it takes touches and the mouse emulated from them")
	touch.call(&"sync", true, null)
	_check(not controls.visible and not bool(touch.call(&"takes", tap)), "a menu, the shop or a spectate pauses it and lets the tap through")
	touch.call(&"sync", false, null)
	_check(bool(touch.call(&"active")), "and closing the menu brings it back")
	var hold := 0
	for b: Dictionary in ZzTouch.LAYOUT:
		if b.has("hold"):
			hold += 1
	_check(hold == 2, "jump and duck are held on the sampler by the overlay", str(hold))
	host.free()
	DotPlatform.touch_override = -1


func _crosshair() -> void:
	var me := _survivor(Vector3.ZERO)
	var foe := _zombie(Vector3(0, 0, -10))
	var eye := Vector3(0, 1.6, 0)
	var ahead := Vector3(0, 0, -1)
	var none := DotMobileAutoFire.TARGET_NONE
	var enemy := DotMobileAutoFire.TARGET_ENEMY
	var friend := DotMobileAutoFire.TARGET_FRIEND
	_check(ZzTouch.crosshair_kind(eye, ahead, me, [me], [foe], null, 0) == enemy, "the crosshair on a living zombie is an enemy")
	_check(ZzTouch.crosshair_kind(eye, Vector3(1, 0, 0), me, [me], [foe], null, 0) == none, "looking away is nothing")
	var mate := _survivor(Vector3(0, 0, -5))
	_check(ZzTouch.crosshair_kind(eye, ahead, me, [me, mate], [foe], null, 0) == friend, "another survivor in front holds fire")
	_check(ZzTouch.crosshair_kind(eye, ahead, me, [me, mate], [], null, 0) == friend, "and so does one with no zombie behind")
	mate.visible = false
	_check(ZzTouch.crosshair_kind(eye, ahead, me, [me, mate], [foe], null, 0) == enemy, "a survivor not drawn is not in the way")
	_check(ZzTouch.assist_targets(eye, ahead, [foe], null, 0).size() == 1, "aim assist sees the zombie near the crosshair")
	_check(ZzTouch.assist_targets(eye, Vector3(0, 0, 1), [foe], null, 0).is_empty(), "and not one behind")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 10, 0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.collision_layer = 1
	add_child(wall)
	wall.global_position = Vector3(0, 2, -6)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	_check(ZzTouch.crosshair_kind(eye, ahead, me, [me], [foe], space, 1) == none, "a wall in front of a zombie is nothing")
	_check(ZzTouch.assist_targets(eye, ahead, [foe], space, 1).is_empty(), "and aim assist skips it")
	var crowd: Array = []
	for i in 40:
		crowd.append(_zombie(Vector3(float(i % 8) - 4.0, 0, -12.0 - float(i))))
	var reps := 200
	var t := Time.get_ticks_usec()
	for _r in reps:
		var _k := ZzTouch.crosshair_kind(eye, ahead, me, [me], crowd, null, 0)
	var each_ms := float(Time.get_ticks_usec() - t) / reps / 1000.0
	_check(each_ms < 0.2, "the crosshair query over 40 zombies is under 0.2 ms", "%.4f ms" % each_ms)
	for n: Node in crowd + [me, foe, mate, wall]:
		n.free()


func _survivor(at: Vector3) -> Survivor:
	var s := Survivor.new()
	add_child(s)
	s.global_position = at
	return s


func _zombie(at: Vector3) -> Zombie:
	var z := Zombie.new()
	add_child(z)
	z.global_position = at
	return z
