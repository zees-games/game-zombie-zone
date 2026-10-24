extends RefCounted

const ZzLoot := preload("zz_loot.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPackList := preload("zz_packs.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzWeapons := preload("zz_weapons.gd")

## A survival map held: the schedule, what each stage does to the horde, and the breather.
##
## [b]The schedule is dot-npc-ai-director's[/b] ([DotNpcDirectorWaves]); this file is what it
## means in this game. The server owner picks the style (`zz_survival`), and the default is the
## one the first play test asked for:
##
## [codeblock]
## waves    30 s to find the doors, then ten waves, each a crowd that has to be killed, each
##          bigger and quicker to arrive than the last, with a breather between
## nights   a day to get ready, then a night to live through, five of them, each worse
## clock    the old survival: one stretch that gets worse the longer it runs
## [/codeblock]
##
## [b]What makes a wave ours[/b] rather than the genre's stock shape:
## - [b]The breather is a patch-up, not a shop.[/b] Everybody down gets up, the dead come back
##   beside the team, everybody standing gets some health back, and the map's caches restock,
##   with better guns as the waves go on (a sidearm-and-SMG table at wave 1, launchers by the
##   end). There is no money: what you get is what is on the table, and it goes to whoever
##   walks over first.
## - [b]The barricades are the clock that matters.[/b] A wave's zombies come to the doors and
##   windows and break them down, and mending them (hold E) is the breather's other job. A
##   team that spends the breather looting comes back to open windows.
## - [b]From the third wave on, each wave draws a twist[/b] (never the same twice running):
##   sprinters (a quarter faster), a swarm (half as many again, each weaker), heavies (fewer,
##   much tougher), hunters (half as many specials again). It is announced as the wave starts.
## - [b]Every fifth wave brings a brute, and the last two.[/b] A brute's wave draws no twist.
##
## [b]Server only.[/b] A client is told the stage, the wave, the clock and the twist by the
## bridge (SURVIVAL), and draws the light from the daylight it is sent.

const CHANNEL := "zz.survival"

## Twists a wave may draw, with what each does: size, health and speed of its commons, and how
## many times the specials. `title` is what the HUD says.
const TWISTS := {
	&"sprinters": {"title": "Sprinters", "size": 1.0, "health": 1.0, "speed": 1.25, "specials": 1.0},
	&"swarm": {"title": "Swarm", "size": 1.5, "health": 0.6, "speed": 1.0, "specials": 1.0},
	&"heavies": {"title": "Heavies", "size": 0.7, "health": 1.8, "speed": 0.9, "specials": 1.0},
	&"hunters": {"title": "Hunters", "size": 0.85, "health": 1.0, "speed": 1.0, "specials": 1.5},
}

## The game (`zz_game.gd`), untyped: it preloads this file.
var game = null
var waves: DotNpcDirectorWaves = null

## The wave's twist, or empty.
var twist: StringName = &""

## The specials still owed this wave, and when the next is due.
var _specials_owed: int = 0
var _next_special: float = INF

## The brutes this wave brings, and how many are still owed: each comes once another third of
## the wave is out.
var _brutes_this_wave: int = 0
var _brutes_owed: int = 0

var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _last_twist: StringName = &""

## Waves cleared, nights lived through, for the HUD's last line and a suite.
var cleared: int = 0
var refused_spawns: int = 0


func _init(p_game: Object) -> void:
	game = p_game


## Builds the schedule from the configuration and starts it.
func begin() -> DotResult:
	var c = game.config
	waves = DotNpcDirectorWaves.new()
	waves.style = [DotNpcDirectorWaves.Style.ROUNDS, DotNpcDirectorWaves.Style.CYCLE, DotNpcDirectorWaves.Style.CLOCK][clampi(c.survival_style, 0, 2)]
	waves.count = c.waves if waves.style == DotNpcDirectorWaves.Style.ROUNDS else c.nights
	waves.first_quiet_seconds = c.setup_seconds() if waves.style != DotNpcDirectorWaves.Style.CLOCK else 0.0
	waves.quiet_seconds = c.breather_seconds if waves.style == DotNpcDirectorWaves.Style.ROUNDS else c.day_seconds
	waves.horde_seconds = c.night_seconds if waves.style == DotNpcDirectorWaves.Style.CYCLE else game.survival_goal
	var scale: float = float(c.wave_scale_by_map.get(str(game.map_doc.get("id", "")), 1.0))
	waves.wave_base = int(round(float(c.wave_size) * scale))
	waves.wave_per_player = int(round(float(c.wave_size_per_survivor) * scale))
	waves.growth = c.wave_growth
	waves.growth_accel = c.wave_growth_accel
	waves.straggler_count = maxi(3, int(round(float(_team()) * c.wave_straggler_share)))

	var valid := waves.validate()

	if not valid.ok:
		DotLog.error(CHANNEL, "the survival schedule is not usable", {"why": valid.error.message})
		return valid

	_rng.seed = int(c.seed_value) ^ hash(str(game.map_doc.get("id", ""))) ^ int(game.round_number) * 131
	_time = 0.0
	cleared = 0
	twist = &""
	_last_twist = &""
	waves.stage_changed.connect(_on_stage)
	waves.begin(_team())
	DotLog.info(CHANNEL, "the hold began", {"style": waves.style_name(), "count": waves.count, "team": _team()})
	return DotResult.success(waves)


func stop() -> void:
	if waves != null:
		if waves.stage_changed.is_connected(_on_stage):
			waves.stage_changed.disconnect(_on_stage)
		waves.stop()

	_set_twist(&"")


func is_running() -> bool:
	return waves != null and waves.stage != DotNpcDirectorWaves.Stage.IDLE


func is_done() -> bool:
	return waves != null and waves.stage == DotNpcDirectorWaves.Stage.DONE


## One tick: the schedule, and what it releases.
func tick(delta: float) -> void:
	if waves == null or game.horde == null:
		return

	_time += delta
	var horde = game.horde
	var alive: int = horde.wave_alive()
	# A wave is not down to its stragglers while its brute stands: ended early, the brute was sent
	# at the team through the breather and into the next wave, a twist on top, and that sixth
	# wave was where the school and the ballpark went down (zz-survival-retune-2). The overtime
	# still ends it.
	if waves.style == DotNpcDirectorWaves.Style.ROUNDS and waves.stage == DotNpcDirectorWaves.Stage.HORDE and horde.wave_brutes() > 0:
		alive = maxi(alive, waves.straggler_count + 1)
	waves.tick(delta, alive, _team())

	if waves.stage != DotNpcDirectorWaves.Stage.HORDE:
		return

	match waves.style:
		DotNpcDirectorWaves.Style.ROUNDS:
			_release(horde)
		_:
			# A night or the clock: the horde's own pacing, harder by the schedule.
			horde.intensity = waves.strength()


## What a wave owes, spawned within the room the living leave.
func _release(horde) -> void:
	if horde.refused_wave > 0:
		waves.give_back(horde.refused_wave)
		refused_spawns += horde.refused_wave
		horde.refused_wave = 0

	# What is queued counts against the room: without it each tick took the room again while the
	# last tick's were still queued, the spawner refused the extra, and the wave's 'sent' fell
	# back by what it owed again (thirty-six on the ballpark).
	# And a wave may have only part of the cap up at once, growing to all of it by the last, on
	# a curve: slow through the middle waves (where holds were lost), a wall at the end.
	horde.wave_index = waves.index
	var ramp := clampf(float(waves.index - 1) / maxf(float(waves.count - 1), 1.0), 0.0, 1.0)
	var share := lerpf(clampf(float(game.config.wave_alive_share_by_map.get(str(game.map_doc.get("id", "")), game.config.wave_alive_share)), 0.1, 1.0), 1.0, ramp * ramp)
	horde.wave_room = int(float(game.config.commons_cap(_team())) * share)
	var room: int = horde.wave_room - horde.commons() - horde.pending_commons()
	var n := waves.take(room)

	if n > 0:
		var queued: int = horde.spawn_wave(n)
		if queued < n:
			waves.give_back(n - queued)

	var progress := float(waves.sent) / maxf(float(waves.budget), 1.0)

	if _specials_owed > 0 and _time >= _next_special:
		var kinds: Array[StringName] = horde._allowed_specials()
		var packed := ZzPackList.specials(waves.index)
		var pick: ZzPackList.Monster = null

		# No roll without an installed monster, so a game without packs draws what it always did.
		if not packed.is_empty():
			var roll := _rng.randf() * (float(kinds.size()) + ZzPackList.total_weight(packed))
			pick = ZzPackList.pick(packed, roll - float(kinds.size())) if roll >= float(kinds.size()) else null

		if pick != null:
			if horde.spawn_special(pick.id, Vector3.INF, horde.WAVE) != null:
				_specials_owed -= 1
		elif not kinds.is_empty():
			var made = horde.spawn_special(kinds[_rng.randi_range(0, kinds.size() - 1)], Vector3.INF, horde.WAVE)
			if made != null:
				_specials_owed -= 1
		_next_special = _time + maxf(4.0, 40.0 / maxf(float(_specials_owed + 1), 1.0))

	# The brute comes once a third of the wave is out, the second one at two thirds.
	if _brutes_owed > 0 and progress >= 1.0 / 3.0 * float(_brutes_total() - _brutes_owed + 1):
		if horde.spawn_brute(Vector3.INF, horde.WAVE) != null:
			_brutes_owed -= 1


func _brutes_total() -> int:
	return _brutes_this_wave


## The schedule moved on.
func _on_stage(stage: int, index: int) -> void:
	var horde = game.horde

	match stage:
		DotNpcDirectorWaves.Stage.QUIET:
			horde.stop_pacing()
			_set_twist(&"")

			if index > 1:
				cleared += 1
				var straggled := 0
				if waves.style == DotNpcDirectorWaves.Style.ROUNDS:
					if waves.overtime:
						straggled = horde.clear_wave_stragglers(30.0)
				else:
					straggled = horde.dawn(30.0)
				_breather()
				# A wave held is a round over: what the boxes did to the game ends with it.
				if game.boxes != null:
					game.boxes.end_round()
				game.notice.emit(_cleared_line(index - 1))
				game.map_wave_changed(index - 1, true)
				DotLog.info(CHANNEL, "a breather", {"after": index - 1, "tidied": straggled})
			else:
				# Four of the big maps have no loose items, only caches, and a cache was filled
				# only by the first breather: wave 1 began with nothing to pick up.
				var _placed := restock()
				game.notice.emit(_opening_line())

		DotNpcDirectorWaves.Stage.HORDE:
			# Nothing walks the map until the setup time is over.
			horde.populate_map()

			if waves.style == DotNpcDirectorWaves.Style.ROUNDS:
				_begin_wave(index)
			else:
				horde.intensity = waves.strength()
				horde.start_pacing(true)
				if waves.style == DotNpcDirectorWaves.Style.CYCLE:
					game.notice.emit("Night %d of %d. Hold on until dawn." % [index, waves.count] if index < waves.count \
						else "The last night. Hold on until dawn.")
				else:
					game.notice.emit("Here they come.")

		DotNpcDirectorWaves.Stage.DONE:
			horde.stop_pacing()
			_set_twist(&"")
			cleared += 1
			game.map_wave_changed(waves.count, true)
			game.survival_finished(_won_line())


func _begin_wave(index: int) -> void:
	var c = game.config
	var horde = game.horde
	# A brute's wave plays straight: a brute on top of sprinters or a swarm downed half a team
	# at once, and wave 5 was where most holds ended (zz-survival-retune-1).
	var brute_wave: bool = c.brute_every_waves > 0 and (index % c.brute_every_waves == 0 or waves.is_last())
	_set_twist(_draw_twist(index) if c.wave_twists and index >= 3 and not brute_wave else &"")
	var t: Dictionary = TWISTS.get(twist, {"size": 1.0, "specials": 1.0})

	# The twist's size is the wave's own: written back into the budget the schedule just set.
	waves.budget = maxi(int(round(float(waves.budget) * float(t["size"]))), 1)

	var team := _team()
	_specials_owed = int(round((float(index - 1) * c.wave_specials_growth + (1.0 if index >= 2 else 0.0))
		* maxf(float(team) / c.survivors_per_wave_special, 1.0) * float(t["specials"])))
	_next_special = _time + 6.0
	_brutes_this_wave = 0

	if c.brute_every_waves > 0 and index % c.brute_every_waves == 0:
		_brutes_this_wave = 1
	if waves.is_last() and c.brute_every_waves > 0:
		_brutes_this_wave = 2

	_brutes_owed = _brutes_this_wave
	horde.start_waves()
	var _called_in: int = horde.send_map_commons()

	var title := "Wave %d of %d" % [index, waves.count] if not waves.is_last() else "The last wave"
	game.map_wave_changed(index)
	if not game.map_announcer_off():
		game.notice.emit("%s%s" % [title, (" — %s" % str(TWISTS[twist]["title"])) if twist != &"" else ""])
	DotLog.info(CHANNEL, "a wave", {"index": index, "size": waves.budget, "twist": String(twist),
		"specials": _specials_owed, "brutes": _brutes_owed, "team": team})


func _draw_twist(index: int) -> StringName:
	var names: Array = TWISTS.keys()
	names.erase(_last_twist)
	# One wave in three plays straight: a twist every wave is no twist at all.
	if index % 3 == 1:
		return &""
	var pick: StringName = names[_rng.randi_range(0, names.size() - 1)]
	_last_twist = pick
	return pick


func _set_twist(t: StringName) -> void:
	twist = t
	var horde = game.horde

	if horde == null:
		return

	var spec: Dictionary = TWISTS.get(t, {"health": 1.0, "speed": 1.0})
	horde.wave_speed_scale = float(spec["speed"])
	horde.wave_health_scale = float(spec["health"])


## The breather: up, back, patched, restocked.
func _breather() -> void:
	for player in game.survivors():
		if player.watching:
			continue

		if player.is_down():
			game.stand_up(player)
		elif player.life == ZzPlayer.Life.DEAD and game.config.respawn_on_wave_end:
			var _back: bool = game.rescue(player)

		if player.is_up():
			player.health.health = minf(player.health.health + float(game.config.breather_heal), player.health.max_health)

	restock()


## Every cache the map has gets ammunition, a medkit or pills, a throwable, and a gun from the
## tier the wave has reached. What was left on a cache from last time is cleared first, so a
## cache is never a pile.
func restock() -> int:
	var loot = game.loot

	if loot == null:
		return 0

	var tier := _tier()
	var placed := 0

	for raw: Array in game.map_doc.get("caches", []):
		var at := ZzMapDoc.v3(raw)

		for id: int in loot.entries.keys():
			if (loot.position_of(id) as Vector3).distance_to(at) < 1.6:
				loot.remove(id)

		var gun: StringName = ZzWeapons.random_of(tier, _rng, &"cache")
		var things := [
			[ZzLoot.AMMO, &"", Vector3(-0.45, 0.0, 0.0)],
			[ZzLoot.MEDKIT if _rng.randf() < 0.5 else ZzLoot.PILLS, &"", Vector3(0.0, 0.0, 0.0)],
			[ZzLoot.WEAPON, gun, Vector3(0.45, 0.0, 0.0)],
		]

		if waves != null and waves.index >= 3:
			things.append([ZzLoot.THROWABLE, ZzWeapons.random_of(&"thrown", _rng, &"cache"), Vector3(0.0, 0.0, 0.4)])

		for thing: Array in things:
			var _id: int = loot.add(thing[0], thing[1], at + (thing[2] as Vector3))
			placed += 1

	return placed


## Better guns as the hold goes on: primaries from the start, heavies past the middle.
func _tier() -> StringName:
	if waves == null:
		return &"primary"

	var share := float(waves.index) / maxf(float(waves.count), 1.0)
	return &"heavy" if share > 0.55 and _rng.randf() < share else &"primary"


func _team() -> int:
	var n := 0

	for player in game.survivors():
		if player.is_alive() and not player.watching and game.can_be_harmed(player.player_id):
			n += 1

	return maxi(n, 1)


func _opening_line() -> String:
	match waves.style:
		DotNpcDirectorWaves.Style.ROUNDS:
			return "%d waves are coming. Find the doors, the caches and each other." % waves.count
		DotNpcDirectorWaves.Style.CYCLE:
			return "Night falls in %d seconds. Get ready." % int(waves.first_quiet_seconds)
	return "Here they come."


func _cleared_line(index: int) -> String:
	if waves.style == DotNpcDirectorWaves.Style.CYCLE:
		return "Dawn. Night %d is over: the caches are full, mend what they broke." % index

	return "Wave %d cleared. %d seconds: restock at the caches, mend the barricades." % [index, int(waves.quiet_seconds)]


func _won_line() -> String:
	match waves.style:
		DotNpcDirectorWaves.Style.ROUNDS:
			return "held through %d waves" % waves.count
		DotNpcDirectorWaves.Style.CYCLE:
			return "lived through %d nights" % waves.count

	return "held out for %d:%02d" % [int(waves.elapsed) / 60, int(waves.elapsed) % 60]


## What a client is told and the HUD draws: `{style, stage, index, count, left, remaining,
## twist, daylight}`. `left` is the stage's seconds (-1 for none), `remaining` the wave's
## zombies (-1 outside a wave).
func state() -> Dictionary:
	if waves == null:
		return {}

	return {
		"style": waves.style, "stage": waves.stage, "index": waves.index, "count": waves.count,
		"left": waves.seconds_left(), "remaining": waves.remaining() if waves.stage == DotNpcDirectorWaves.Stage.HORDE else -1,
		"twist": String(twist), "daylight": waves.daylight(),
	}


func describe() -> Dictionary:
	var out := waves.describe() if waves != null else {}
	out["twist"] = String(twist)
	out["cleared"] = cleared
	out["specials_owed"] = _specials_owed
	return out
