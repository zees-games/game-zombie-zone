extends RefCounted

## Pills and medkits: each its own counted slot (apart from the weapons and from each other),
## with a stack limit, a use time, healing a friend and handing one over. Server only; a client
## sends held bits and nothing more.

const CHANNEL := "zz.consumables"

## Stack limits (`zz_medkit_max` up to 7, `zz_pills_max` up to 15: what the wire has room for).
const MEDKIT_CEILING := 7
const PILLS_CEILING := 15

## Cosine of the angle off the crosshair within which a friend counts as aimed at.
const AIM_DOT := 0.82
## Looser, to keep a heal going while the friend moves a little.
const HOLD_DOT := 0.6

var medkit_max: int = 3
var pills_max: int = 4
## `zz_pills_seconds`: how long the key is held to take a pill (0 is instant).
var pills_seconds: float = 1.0
var heal_others: bool = true
## `zz_heal_range`: metres to a friend a medkit reaches.
var heal_range: float = 2.2
var give_pills: bool = true
var give_medkits: bool = true
## `zz_give_range`: metres to the friend a hand-over reaches.
var give_range: float = 2.5

var game = null
var _health_at: Dictionary = {}
var _locked: Dictionary = {}


func _init(p_game: Object) -> void:
	game = p_game


## Registers the cvars ([param add] is the module's `add_cvar`); [param flags] should replicate.
func bind_cvars(add: Callable, flags: int = 0) -> void:
	_bind(add, "zz_medkit_max", str(medkit_max), "Medkits a survivor holds at most (1 to 7)", flags,
		func(v: String) -> void: medkit_max = clampi(v.to_int(), 1, MEDKIT_CEILING))
	_bind(add, "zz_pills_max", str(pills_max), "Bottles of pills a survivor holds at most (1 to 15)", flags,
		func(v: String) -> void: pills_max = clampi(v.to_int(), 1, PILLS_CEILING))
	_bind(add, "zz_pills_seconds", str(pills_seconds), "Seconds the pills key is held to take a pill (0 is instant)", flags,
		func(v: String) -> void: pills_seconds = clampf(v.to_float(), 0.0, 20.0))
	_bind(add, "zz_heal_others", "1" if heal_others else "0", "Let a medkit be used on a friend you aim at (0 or 1)", flags,
		func(v: String) -> void: heal_others = v.strip_edges() != "0")
	_bind(add, "zz_heal_range", str(heal_range), "Metres to a friend a medkit reaches (0.5 to 10)", flags,
		func(v: String) -> void: heal_range = clampf(v.to_float(), 0.5, 10.0))
	_bind(add, "zz_give_pills", "1" if give_pills else "0", "Let a survivor hand a bottle of pills to a friend (0 or 1)", flags,
		func(v: String) -> void: give_pills = v.strip_edges() != "0")
	_bind(add, "zz_give_medkits", "1" if give_medkits else "0", "Let a survivor hand a medkit to a friend (0 or 1)", flags,
		func(v: String) -> void: give_medkits = v.strip_edges() != "0")
	_bind(add, "zz_give_range", str(give_range), "Metres to a friend a hand-over reaches (0.5 to 10)", flags,
		func(v: String) -> void: give_range = clampf(v.to_float(), 0.5, 10.0))


func _bind(add: Callable, name: String, value: String, help: String, flags: int, apply: Callable) -> void:
	var made: Variant = add.call(name, value, help, flags)

	if not (made is Object):
		return

	var cv := made as Object
	apply.call(String(cv.call(&"get_string")))
	cv.connect(&"changed", func(_old: Variant, new_value: Variant) -> void: apply.call(str(new_value)))


## Puts one medkit in the slot; false (and the reason said) when it is full.
func add_medkit(player, say: bool = true) -> bool:
	if player.medkits >= medkit_max:
		if say:
			game.refused.emit(player.player_id, "Your medkits are full.")
		return false

	player.medkits += 1
	return true


func add_pills(player, say: bool = true) -> bool:
	if player.pills >= pills_max:
		if say:
			game.refused.emit(player.player_id, "Your pills are full.")
		return false

	player.pills += 1
	return true


## Starts taking a pill: held for [member pills_seconds], and cancelled by damage.
func begin_pills(player) -> void:
	if player.pills <= 0 or player.using != &"":
		return

	if player.health.health >= player.health.max_health - 1.0:
		game.refused.emit(player.player_id, "You are not hurt.")
		return

	if pills_seconds <= 0.0:
		game._take_pills(player)
		return

	game._start(player, &"pills", player.entity_id, pills_seconds)
	watch(player)


## Blocks a held medkit key from restarting after a cancel; released keys clear it.
func lock(player) -> void:
	_locked[player.player_id] = true


## Whether [param player] may start a medkit use now, given whether the key is [param held].
func may_start(player, held: bool) -> bool:
	if not held:
		_locked.erase(player.player_id)
		return false

	return not _locked.has(player.player_id)


## Remembers the health [param player] began a use at, so damage taken can cancel it.
func watch(player) -> void:
	_health_at[player.player_id] = player.real_health()


## Whether a pill or medkit use under way still holds: nothing has hurt the user since it began.
func hold_ok(player) -> bool:
	return player.real_health() >= float(_health_at.get(player.player_id, 0.0)) - 0.01


## Whether the medkit on [param who] may go on: a friend must be in range, in sight and still aimed at.
func heal_ok(player, who) -> bool:
	if who == player:
		return hold_ok(player)

	if not heal_others or not hold_ok(player):
		return false

	var eye: Vector3 = player.eye_position()
	var middle: Vector3 = who.feet() + Vector3(0.0, 1.0, 0.0)

	if eye.distance_to(middle) > heal_range + 0.8:
		return false

	return player.aim_direction().dot((middle - eye).normalized()) >= HOLD_DOT and game.clear_between(eye, middle)


## The friend [param player] aims at: {"who": ZzPlayer or null, "why": refusal text}.
func aimed_friend(player, reach: float) -> Dictionary:
	var eye: Vector3 = player.eye_position()
	var aim: Vector3 = player.aim_direction()
	var best = null
	var best_dot := AIM_DOT
	var seen_far := false
	var blocked := false

	for other in game.survivors():
		if other == player or other.watching or not other.is_alive():
			continue

		var middle: Vector3 = other.feet() + Vector3(0.0, 1.0, 0.0)

		if eye.distance_to(middle) > reach + 0.8:
			seen_far = true
			continue

		var d: float = aim.dot((middle - eye).normalized())

		if d <= best_dot:
			continue

		if not game.clear_between(eye, middle):
			blocked = true
			continue

		best_dot = d
		best = other

	if best != null:
		return {"who": best, "why": ""}

	return {"who": null, "why": "No line of sight." if blocked else ("Nobody in reach." if seen_far else "Nobody there.")}


## Hands one pill (what = &"pills") or one medkit (&"medkit") to the friend aimed at. True if it moved.
func give(player, what: StringName) -> bool:
	if player.is_down() or not player.is_alive() or player.watching:
		return false

	var pills := what == &"pills"

	if not (give_pills if pills else give_medkits):
		game.refused.emit(player.player_id, "Handing that over is off.")
		return false

	if (player.pills if pills else player.medkits) <= 0:
		game.refused.emit(player.player_id, "You have none to give.")
		return false

	var found := aimed_friend(player, give_range)
	var who = found["who"]

	if who == null:
		game.refused.emit(player.player_id, str(found["why"]))
		return false

	if not who.is_up():
		game.refused.emit(player.player_id, "They are down.")
		return false

	if not (add_pills(who, false) if pills else add_medkit(who, false)):
		game.refused.emit(player.player_id, "They cannot carry more.")
		return false

	if pills:
		player.pills -= 1
	else:
		player.medkits -= 1

	game.refused.emit(who.player_id, "%s gave you %s." % [player.display_name, "pills" if pills else "a medkit"])
	return true
