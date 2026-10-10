extends DotFpsController

## The first-person controller, with the modifiers a survivor's body can be under.
##
## [b]Modifiers, not checks in the game's loop.[/b] A modifier is part of the movement state, so
## it travels in the snapshot and a predicting client applies it to its own survivor on exactly
## the ticks the server does; a rule the game applied around the controller would be skipped by
## every replayed tick, and a pinned survivor's client would predict them walking off while the
## server held them. Registered in [method _register_extensions], on every player on every
## machine and in the same order, because the id is what travels.
##
## [b]Knockback is eight modifiers, not one with a direction.[/b] A modifier's impulse is part
## of its definition, and a definition is what both ends registered at start; a direction
## decided at the moment of the hit would have to travel separately and arrive after the tick
## that needed it. Eight compass points at 45 degrees is coarse, and nobody hit by something
## the size of a car can tell 45 degrees from 30.

## Held where they are by a special: pounced on, strangled, carried, ridden.
const PINNED := &"zz_pinned"

## Down: bleeding out on the floor, unable to move, able to shoot a sidearm.
const DOWN := &"zz_down"

## Under this much health, slower.
const LIMP := &"zz_limp"

## Hit by a common a moment ago: slowed, briefly. The genre's "tagging", and the reason a crowd
## is something to get out of rather than walk through.
const TAGGED := &"zz_tagged"

## Being healed or reviving somebody: you cannot walk while you do it.
const BUSY := &"zz_busy"

## Boxes.
const HASTE := &"zz_haste"
const LOW_GRAVITY := &"zz_low_gravity"
const HEAVY := &"zz_heavy"

## Knocked flying, toward one of eight compass points (index 0 is -Z, then clockwise).
const KNOCK_PREFIX := "zz_knock_"
const KNOCK_DIRECTIONS := 8

## How hard a knock throws, sideways and up, in m/s.
const KNOCK_SPEED := 9.0
const KNOCK_LIFT := 5.0


func _register_extensions() -> void:
	var pinned := DotFpsModifier.make(PINNED)
	pinned.deny_move = true
	pinned.deny_jump = true
	pinned.deny_crouch = true
	pinned.max_speed_scale = 0.0
	var _p := motor.register_modifier(pinned)

	var down := DotFpsModifier.make(DOWN)
	down.deny_move = true
	down.deny_jump = true
	down.deny_crouch = true
	down.max_speed_scale = 0.0
	var _d := motor.register_modifier(down)

	var limp := DotFpsModifier.make(LIMP)
	limp.max_speed_scale = 0.78
	limp.deny_jump = false
	var _l := motor.register_modifier(limp)

	var tagged := DotFpsModifier.make(TAGGED)
	tagged.duration_sec = 0.35
	tagged.max_speed_scale = 0.55
	tagged.refreshable = true
	var _t := motor.register_modifier(tagged)

	var busy := DotFpsModifier.make(BUSY)
	busy.deny_move = true
	busy.deny_jump = true
	busy.max_speed_scale = 0.0
	var _b := motor.register_modifier(busy)

	var haste := DotFpsModifier.make(HASTE)
	haste.duration_sec = 20.0
	haste.max_speed_scale = 1.4
	haste.accelerate_scale = 1.4
	var _h := motor.register_modifier(haste)

	var floaty := DotFpsModifier.make(LOW_GRAVITY)
	floaty.duration_sec = 25.0
	floaty.gravity_scale = 0.35
	floaty.jump_scale = 1.6
	var _f := motor.register_modifier(floaty)

	var heavy := DotFpsModifier.make(HEAVY)
	heavy.duration_sec = 15.0
	heavy.max_speed_scale = 0.6
	heavy.jump_scale = 0.5
	var _w := motor.register_modifier(heavy)

	for i in KNOCK_DIRECTIONS:
		var knock := DotFpsModifier.make(StringName(KNOCK_PREFIX + str(i)))
		knock.duration_sec = 0.05
		knock.refreshable = true
		var angle := float(i) * TAU / float(KNOCK_DIRECTIONS)
		knock.impulse = Vector3(sin(angle) * KNOCK_SPEED, KNOCK_LIFT, -cos(angle) * KNOCK_SPEED)
		knock.impulse_clears_velocity = true
		var _k := motor.register_modifier(knock)


## The knock modifier that throws somebody along [param direction] (horizontal).
static func knock_toward(direction: Vector3) -> StringName:
	var flat := Vector3(direction.x, 0.0, direction.z)

	if flat.length() < 0.001:
		flat = Vector3.FORWARD

	# Index 0 is -Z and the indices run clockwise seen from above, which is +X next.
	var angle := atan2(flat.x, -flat.z)
	var index := posmod(roundi(angle / (TAU / float(KNOCK_DIRECTIONS))), KNOCK_DIRECTIONS)
	return StringName(KNOCK_PREFIX + str(index))
