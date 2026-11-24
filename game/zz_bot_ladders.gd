extends RefCounted
## A stand-in on a ladder: where its path says to climb ([method start]), and the legs while it does ([method steer]).
## The ride itself is gs-bot's `GSBotClimb` (up and down); the graph's ladder links (`ZzNavGraph.apply_ladders`) are what
## send a stand-in's path through a ladder at all.

const ZzLadders := preload("zz_ladders.gd")

## How far off a ladder's box (flat, metres) a stand-in starts the ride, and how far it may stray before the ride is dropped.
const APPROACH := 1.4
const STRAY := 3.0

## The least rise or fall to the next corner of a path that is a ladder and not a stair.
const RISE := 1.0

## How far over a ladder's top, and under its foot, a stand-in's feet may be and the ladder still be its.
const OVER := 1.6
const UNDER := 1.0


## The ride (`GSBotClimb`) for a stand-in at [param here] whose path goes on to [param next], or null when that is no ladder:
## the corner is a rise away and a ladder box (of [param boxes]) is within [constant APPROACH] of the feet.
static func start(boxes: Array[AABB], here: Vector3, next: Vector3, now: float) -> GSBotClimb:
	if absf(next.y - here.y) < RISE:
		return null

	var best := -1
	var nearest := APPROACH

	for i in boxes.size():
		var box := boxes[i]
		var off := ZzLadders.flat_off(box, here)

		if off <= nearest and here.y >= box.position.y - UNDER and here.y <= box.end.y + OVER:
			nearest = off
			best = i

	if best < 0:
		return null

	return GSBotClimb.begin({"box": boxes[best], "to": next}, now)


## One tick of [param climb] from [param feet] into [param command]; false when the ride is over (done, timed out or strayed).
static func steer(climb: GSBotClimb, feet: Vector3, now: float, command: GSFpsCommand) -> bool:
	if ZzLadders.flat_off(climb.box, feet) > STRAY:
		return false

	var r := climb.step(feet, now)

	if r["done"]:
		return false

	if not is_nan(float(r.get("yaw", NAN))):
		command.yaw = float(r["yaw"])

	command.move = r["move"]
	command.set_button(GSFpsCommand.BUTTON_JUMP, bool(r["jump"]))
	return true



## One tick of a stand-in's ladder ride, held in [param memory]["climb"]: continues it, or starts it when the next corner of
## the path is a ladder's rise away. True when the ride set [param command] (the caller walks no further this tick).
static func drive(game, player, command: GSFpsCommand, memory: Dictionary) -> bool:
	var now: float = game.now()

	if not memory.has("climb"):
		var path: PackedVector3Array = memory["path"]

		if path.is_empty() or game.map == null or game.map.mechanics == null:
			return false

		var ride := start(game.map.mechanics.ladder_boxes(), player.feet(), path[0], now)

		if ride == null:
			return false

		memory["climb"] = ride

	if steer(memory["climb"], player.feet(), now, command):
		return true

	memory.erase("climb")
	memory["path"] = PackedVector3Array()
	return false
