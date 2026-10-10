extends RefCounted

const ZzController := preload("zz_controller.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

## Who is holding whom: a survivor a special has hold of, and what it is doing to them.
##
## [b]A pin is the special's whole attack, and it only means something because the victim
## cannot get out alone.[/b] Four kinds, and they differ in what frees the victim and where the
## victim goes:
##
## [codeblock]
## pounce   the leaper on top of them, clawing.     Freed by a shove, or the leaper dying.
## choke    a tongue round them, dragged to the strangler, then strangled.
##                                                   Freed by a shove, or the strangler dying.
## carry    the ram running with them, then beating them on the floor.
##                                                   Freed ONLY by the ram dying.
## ride     the rider on their head, steering them away from help.
##                                                   Freed by a shove, or the rider dying.
## [/codeblock]
##
## [b]The victim is moved by velocity, not by teleport.[/b] On the server, before the victim's
## controller simulates, this sets their velocity toward where the special wants them; the motor
## then moves them with collision, so a survivor dragged by a tongue catches on the corner of a
## car exactly as the genre does, and is never pulled through a wall. The PINNED modifier is
## what stops the victim's own keys counting, on both ends.
##
## [b]A pinned survivor's own client mispredicts the drag[/b], because it does not know the
## special's velocity: it is corrected every snapshot, which on screen is being hauled along in
## steps. That is the honest cost of not predicting NPCs (dot-npc's CLAUDE.md), and a pinned
## player has no input to feel the correction in.

const POUNCE := &"pounce"
const CHOKE := &"choke"
const CARRY := &"carry"
const RIDE := &"ride"

## Damage over time, per kind, per second, on normal. A brain may override it in its meta.
const DAMAGE_PER_SECOND := {POUNCE: 10.0, CHOKE: 5.0, CARRY: 13.0, RIDE: 4.0}

## How close a choked survivor ends up to the strangler, and how fast they are dragged.
const CHOKE_GAP := 1.2

signal pinned(victim: StringName, kind: StringName, attacker: int)
signal released(victim: StringName, kind: StringName, why: StringName)

## The game (`zz_game.gd`), untyped: it preloads this file.
var game = null

## victim id -> {npc, entity, kind, since, dealt}
var pins: Dictionary = {}


func _init(p_game: Object) -> void:
	game = p_game


## [param npc] takes hold of [param victim]. False when they cannot be held: dead, already held,
## or the special already holds somebody.
func pin(entity: int, npc: DotNpcInstance, victim: StringName, kind: StringName) -> bool:
	var player = game.player_by_id(victim)

	if player == null or not player.is_alive() or player.is_pinned() or player.watching:
		return false

	if victim_of(entity) != &"":
		return false

	# Only a ram's carry and a choke may take a downed survivor; a leaper or a rider on somebody
	# already on the floor is a special wasting itself, and the genre does not allow it.
	if player.is_down() and kind != CHOKE and kind != CARRY:
		return false

	pins[victim] = {"npc": npc, "entity": entity, "kind": kind, "since": game.now(), "dealt": 0.0}
	player.pinned_by = entity
	player.pin_kind = kind
	var _held: bool = player.controller.add_modifier(ZzController.PINNED)
	player.using = &""
	game.cancel_use(player)
	pinned.emit(victim, kind, entity)
	return true


## Lets go of [param victim], for [param why] (`shoved`, `killed`, `let go`, `died`).
func release(victim: StringName, why: StringName) -> void:
	var held: Variant = pins.get(victim)

	if held == null:
		return

	pins.erase(victim)
	var kind: StringName = (held as Dictionary)["kind"]
	var player = game.player_by_id(victim)

	if player != null:
		player.pinned_by = 0
		player.pin_kind = &""
		var _off: bool = player.controller.remove_modifier(ZzController.PINNED)

	var npc: DotNpcInstance = (held as Dictionary)["npc"]

	if npc != null and npc.node != null and is_instance_valid(npc.node) and npc.node is ZzZombieBody:
		(npc.node as ZzZombieBody).anchored = false

	if npc != null and npc.is_alive() and npc.brain != null and npc.brain.has_method(&"pin_released"):
		npc.brain.call(&"pin_released", victim, why)

	released.emit(victim, kind, why)


func release_by(entity: int, why: StringName) -> void:
	var victim := victim_of(entity)

	if victim != &"":
		release(victim, why)


## Whom [param entity] holds, or empty.
func victim_of(entity: int) -> StringName:
	for victim: StringName in pins:
		if int((pins[victim] as Dictionary)["entity"]) == entity:
			return victim

	return &""


func holder_of(victim: StringName) -> DotNpcInstance:
	var held: Variant = pins.get(victim)
	return (held as Dictionary)["npc"] if held != null else null


func kind_of(victim: StringName) -> StringName:
	var held: Variant = pins.get(victim)
	return (held as Dictionary)["kind"] if held != null else &""


## Before the survivors move: every victim's velocity toward where they are being taken.
func steer(delta: float) -> void:
	for victim: StringName in pins.keys():
		var held: Dictionary = pins[victim]
		var npc: DotNpcInstance = held["npc"]
		var player = game.player_by_id(victim)

		if player == null or npc == null or not npc.is_alive() or npc.node == null or not is_instance_valid(npc.node):
			release(victim, &"killed")
			continue

		var state: DotFpsState = player.controller.state
		var from: Vector3 = state.position
		var special: Vector3 = npc.position()

		match held["kind"]:
			CHOKE:
				var to := special - from
				to.y = 0.0

				if to.length() > CHOKE_GAP:
					var speed: float = float(npc.def.meta.get("pull_speed", 3.2))
					var pull := to.normalized() * speed
					state.velocity = Vector3(pull.x, minf(state.velocity.y, 0.0), pull.z)
				else:
					state.velocity = Vector3(0.0, minf(state.velocity.y, 0.0), 0.0)
			CARRY:
				var body := npc.node as ZzZombieBody
				var carried := Vector3(body.velocity.x, 0.0, body.velocity.z) if body != null else Vector3.ZERO
				# Held in front of the ram, at its speed.
				var ahead := special + npc.facing() * 0.9 - from
				ahead.y = 0.0
				state.velocity = carried + ahead * 8.0
			RIDE:
				var body := npc.node as ZzZombieBody
				var steer_to := body.wish if body != null else Vector3.ZERO
				state.velocity = Vector3(steer_to.x, minf(state.velocity.y, 0.0), steer_to.z)
			_:
				state.velocity = Vector3(0.0, minf(state.velocity.y, 0.0), 0.0)


## After the survivors move: the special sits where it should on its victim, and the damage.
func advance(delta: float) -> void:
	for victim: StringName in pins.keys():
		var held: Dictionary = pins[victim]
		var npc: DotNpcInstance = held["npc"]
		var player = game.player_by_id(victim)

		if player == null or not player.is_alive():
			release(victim, &"died")
			continue

		if npc == null or not npc.is_alive() or npc.node == null or not is_instance_valid(npc.node):
			release(victim, &"killed")
			continue

		var body := npc.node as ZzZombieBody
		var at: Vector3 = player.controller.state.position

		match held["kind"]:
			POUNCE:
				body.global_position = at + Vector3(0.0, 0.25, 0.0) - npc.facing() * 0.35
				body.anchored = true
			RIDE:
				body.global_position = at + Vector3(0.0, 1.05, 0.0)
				body.anchored = true
			CARRY:
				pass
			CHOKE:
				pass

		var rate: float = float(npc.def.meta.get("pin_dps", DAMAGE_PER_SECOND.get(held["kind"], 5.0)))
		held["dealt"] = float(held["dealt"]) + rate * delta

		# Whole points, a few a second: dot-combat is told about every one, and a stream of
		# 0.15 hits would be a kill feed and a hurt flash sixty times a second.
		if float(held["dealt"]) >= 2.0:
			var amount := floorf(float(held["dealt"]))
			held["dealt"] = float(held["dealt"]) - amount
			game.pin_damage(npc, int(held["entity"]), victim, amount, held["kind"])


## A shove reaching [param victim] or their special: frees them, unless it is a carry.
func shoved(victim: StringName) -> bool:
	var kind := kind_of(victim)

	if kind == &"" or kind == CARRY:
		return false

	var npc := holder_of(victim)
	release(victim, &"shoved")

	if npc != null and npc.is_alive() and npc.brain != null and npc.brain.has_method(&"stagger"):
		var away := npc.position() - (game.player_by_id(victim).controller.state.position as Vector3)
		npc.brain.call(&"stagger", away, 1.4, 6.0)

	return true


func clear() -> void:
	for victim: StringName in pins.keys():
		release(victim, &"cleared")


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	for victim: StringName in pins:
		var held: Dictionary = pins[victim]
		out.append("  %s %s by %d for %.1f s" % [String(victim), String(held["kind"]), int(held["entity"]),
			game.now() - float(held["since"])])

	return out
