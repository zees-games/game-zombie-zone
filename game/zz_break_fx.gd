extends Node

## Splinters where a barricade or a support gives way, drawn by dot-fx's DotFxBreak and following fx_quality.

var break_fx: DotFxBreak = null


func _init() -> void:
	name = "BreakFx"
	break_fx = DotFxBreak.new()
	break_fx.name = "Break"
	add_child(break_fx)


func follow(store: Object) -> void:
	break_fx.follow(store)


func splinter(at: Vector3, size: float = 1.0) -> void:
	var _b := break_fx.burst("wood", at, Vector3.UP, size)
