extends "zz_box_effect.gd"

const ZzController := preload("zz_controller.gd")

## The speed boxes: every survivor moves faster, or crawls faster, while the effect lasts. One
## script behind two names in `ZzBoxes.HANDLERS` (`move_speed`, `crawl_speed`); the box's
## `params.modifier` (`move` or `crawl`) picks which controller modifier it holds on everybody.
##
## [b]A modifier, not a velocity[/b]: it travels with the movement state, so the predicting
## client applies it on the same tick the server does. The scale is the controller's constant
## ([constant ZzController.MOVE_BOOST_SCALE], [constant ZzController.CRAWL_BOOST_SCALE]), because
## a definition is registered once on every end. A modifier is held once per survivor, so these
## boxes do not stack: opening a second only lengthens the first (the registry's rule), which is
## what boxes.json says with `"stacks": false`.
##
## The registry owns the clock and the round's end. This file only keeps the modifier on whoever
## is alive: [method on_tick] gives it to a survivor who joined, was rescued or came back after
## the box was opened, and [method on_end] takes it off every survivor.

func _modifier(fx: Dictionary) -> StringName:
	var wanted := str((fx.get("params", {}) as Dictionary).get("modifier", "move"))
	return ZzController.CRAWL_BOOST if wanted == "crawl" else ZzController.MOVE_BOOST


## A crawl box is no gift where nobody can crawl: it would open as a dud, so it is not dropped.
func available(boxes, params: Dictionary) -> bool:
	if str(params.get("modifier", "move")) != "crawl" or boxes.game == null:
		return true

	return boxes.game.crawl_rules.speed > 0.0


func on_start(boxes, fx: Dictionary, _ctx: Dictionary) -> void:
	_give(boxes, fx)


func on_tick(boxes, fx: Dictionary, _delta: float) -> void:
	_give(boxes, fx)


func on_end(boxes, fx: Dictionary) -> void:
	var id := _modifier(fx)

	for p in boxes.game.survivors():
		if p.controller != null:
			var _off: bool = p.controller.remove_modifier(id)


func _give(boxes, fx: Dictionary) -> void:
	var id := _modifier(fx)

	for p in boxes.game.survivors():
		if p.controller != null and p.is_alive() and not p.controller.has_modifier(id):
			var _on: bool = p.controller.add_modifier(id)
