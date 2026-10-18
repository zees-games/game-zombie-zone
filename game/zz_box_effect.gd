extends RefCounted

## What a NAMED box does while it is active: the hook interface behind a box that lasts.
##
## [b]A named box is data plus a small handler.[/b] boxes.json says WHAT the box is (polarity,
## impact, radius, stacks, max_stacks, duration, its `params`); a subclass of this file, listed in
## `ZzBoxes.HANDLERS` and named by an outcome's `{"do": "effect", "name": "..."}`, says what the
## box DOES. The registry ([ZzBoxes]) owns the clock, the stack count, the HUD line and the end of
## the round; a handler never tracks time itself. Copy `zz_box_instakill.gd`.
##
## Every hook gets the registry ([param boxes], untyped: it preloads this file) and the active
## effect [param fx], a dictionary: `what`, `who` ("" for the whole game), `stacks`, `until`
## (-1: this round), `data` (the handler's own scratch space), `params` (the box's, from the file).
## No hook is required; the defaults do nothing.

## The box's duration spec {mode, min, max}, adjusted by this handler's cvars. The base leaves it.
func duration(_config, spec: Dictionary) -> Dictionary:
	return spec


## The effect began (once per holder: a game-wide effect once, a radius one per survivor in it).
func on_start(_boxes, _fx: Dictionary, _ctx: Dictionary) -> void:
	pass


## Another of the same effect landed on the holder, within `max_stacks`; `fx.stacks` is the new count.
func on_stack(_boxes, _fx: Dictionary) -> void:
	pass


## Every server tick it is active.
func on_tick(_boxes, _fx: Dictionary, _delta: float) -> void:
	pass


## It ended: timed out, the round ended, or the registry was reset. Undo anything on_start did.
func on_end(_boxes, _fx: Dictionary) -> void:
	pass


## A survivor's shot is about to hurt a zombie of [param kind] (max health [param max_health]) for
## [param amount]; return what it should do. Called for every active effect, in the order they began.
func modify_zombie_damage(_boxes, _fx: Dictionary, _kind: StringName, _max_health: float, amount: float) -> float:
	return amount
