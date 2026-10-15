extends RefCounted

## What survivors do to each other, added up per person over a window, and what that earns.
##
## [b]Three consequences, each its own cvar and each off at 0[/b]: a new player's team damage is
## reflected onto themselves ([method reflects], by [member ZzConfig.friendly_fire_mode]); too
## much of it inside the window asks for a voteban ([signal voteban_wanted]); a hard ceiling
## inside it bans outright ([signal ban_wanted]). The game wires the last two to dot-vote's
## `DotVoteBans.start` and to the server's ban list; this file knows neither.
##
## [b]The total is counted before reflection.[/b] A new player's bullets land on themselves, but
## what they meant to do to a friend is what they did, and a reflected spray that stopped
## counting would let a rookie empty a magazine into the team for free every window.
##
## [b]Stand-ins are never counted, never reflected, never banned[/b]: a bot's stray round is a
## tuning matter (`zz_bots.gd` holds fire for a friend in the line), and there is nobody to ban.
##
## Each consequence fires once per window per player: a vote already asked for is not asked for
## again until the window it was asked in has passed, or a spree is a vote every shot.

const CHANNEL := "zz.teamdamage"

## A player's team damage crossed the vote threshold: (player_id, damage in the window).
signal voteban_wanted(player_id: StringName, damage: float)

## A player's team damage crossed the ceiling: (player_id, damage, minutes to ban for).
signal ban_wanted(player_id: StringName, damage: float, minutes: float)

var config: Object = null

## (ZzPlayer) -> float, seconds played. Unset: everybody is new.
var playtime_fn: Callable = Callable()

## player id -> Array of [time, amount]
var _ledger: Dictionary = {}
var _voted_at: Dictionary = {}
var _banned_at: Dictionary = {}


## Whether [param player] is new: a person who has played under [member ZzConfig.rookie_minutes].
func is_new(player: Object) -> bool:
	if config == null or bool(player.get("is_bot")):
		return false

	var minutes: float = config.rookie_minutes

	if minutes <= 0.0:
		return false

	var seconds := float(playtime_fn.call(player)) if playtime_fn.is_valid() else 0.0
	return seconds < minutes * 60.0


## Whether damage [param attacker] does to a teammate is turned back on them, by the mode.
func reflects(attacker: Object) -> bool:
	if config == null:
		return false

	match int(config.friendly_fire_mode):
		2:
			return is_new(attacker)
		3:
			return true

	return false


## Files [param amount] of team damage by [param attacker] at [param now], and fires whatever
## the window's total now earns.
func record(attacker: Object, amount: float, now: float) -> void:
	if config == null or bool(attacker.get("is_bot")) or amount <= 0.0:
		return

	var id: StringName = attacker.get("player_id")
	var rows: Array = _ledger.get(id, [])
	rows.append([now, amount])
	_ledger[id] = rows
	var total := damage_in_window(id, now)
	var window: float = config.team_damage_window

	var ceiling: float = config.team_damage_ban
	var ask: float = config.team_damage_vote

	if ceiling > 0.0 and total >= ceiling and now - float(_banned_at.get(id, -INF)) >= window:
		_banned_at[id] = now
		DotLog.warn(CHANNEL, "a team damage ceiling was crossed", {"player": String(id), "damage": total, "window": window})
		ban_wanted.emit(id, total, float(config.team_damage_ban_minutes))
		return

	if ask > 0.0 and total >= ask and now - float(_voted_at.get(id, -INF)) >= window:
		_voted_at[id] = now
		DotLog.info(CHANNEL, "too much team damage, a voteban is wanted", {"player": String(id), "damage": total, "window": window})
		voteban_wanted.emit(id, total)


## Team damage [param id] did in the last window, and the rows older than it forgotten.
func damage_in_window(id: StringName, now: float) -> float:
	var rows: Array = _ledger.get(id, [])
	var window: float = config.team_damage_window if config != null else 60.0
	var total := 0.0

	while not rows.is_empty() and now - float((rows[0] as Array)[0]) > window:
		rows.pop_front()

	for row: Array in rows:
		total += float(row[1])

	return total


func forget(id: StringName) -> void:
	_ledger.erase(id)
	_voted_at.erase(id)
	_banned_at.erase(id)


func describe() -> Dictionary:
	return {"tracked": _ledger.size(), "mode": int(config.friendly_fire_mode) if config != null else -1}
