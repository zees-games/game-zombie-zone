extends Node

## Plays a whole survival hold on one map with the map's full team of stand-ins, headless, as
## fast as the machine runs a tick, and says how each wave went. What tuning the waves is done
## from (zz-survival-long-run-1); `headless_survival` plays only a minute of wave 1.
##
## [codeblock]
## godot --headless --path . res://tools/survival_long_run.tscn -- --map=zz_high_school
##     [--difficulty=1] [--seed=N] [--set=wave_growth=0.2 --set=barricade_bash=5 ...]
##     [--until=10] [--cap=1800]
## [/codeblock]
##
## Per wave: how long it took, how many it sent and the most alive at once, downs and deaths
## in it, barricades broken in it, how many of the team were up at its end, and the tick's
## mean and worst cost; under it what downed them and the post nearest each down (an index into
## the map's `posts`), and which barricades broke. A line `RESULT {...}` at the end is the whole
## run as JSON.
##
## Simulated time is the game's own clock; the run takes as long as the ticks cost (a school's
## ten waves are about 25 minutes of play and 5 to 10 of a desktop's time).

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

var _map := &"zz_high_school"
var _difficulty := 1
var _seed := 1
var _sets: Dictionary = {}
var _until := 99
var _cap := 3600.0
var _from := 1
var _profile := false
## --watch=S: every S simulated seconds, where the wave's zombies are and what they are doing.
var _watch := 0.0
var _next_watch := 0.0
var _watch_detail := false

## Microseconds spent in each part of a tick, over the run (`--profile`).
var _parts: Dictionary = {}
var _worst_parts: Dictionary = {}
## This tick's parts, and the slowest ticks' (`--profile`): [cost, wave time, parts], worst first.
var _tick_parts: Dictionary = {}
var _spikes: Array = []
const SPIKES_KEPT := 6

var _game: ZzGame = null
var _waves: Array[Dictionary] = []
var _current: Dictionary = {}
var _result: Array = []
var _broken := 0
## Spawns the spawner refused since the last watch line, by reason (`--watch`).
var _refusals: Dictionary = {}
var _fallen_before := 0
var _finished_waves := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map = StringName(arg.trim_prefix("--map="))
		elif arg.begins_with("--difficulty="):
			_difficulty = arg.trim_prefix("--difficulty=").to_int()
		elif arg.begins_with("--seed="):
			_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--until="):
			_until = arg.trim_prefix("--until=").to_int()
		elif arg.begins_with("--from="):
			_from = arg.trim_prefix("--from=").to_int()
		elif arg == "--detail":
			_watch_detail = true
		elif arg.begins_with("--watch="):
			_watch = arg.trim_prefix("--watch=").to_float()
		elif arg == "--profile":
			_profile = true
		elif arg.begins_with("--cap="):
			_cap = arg.trim_prefix("--cap=").to_float()
		elif arg.begins_with("--set="):
			var pair := arg.trim_prefix("--set=").split("=")
			_sets[pair[0]] = pair[1]

	_run.call_deferred()


func _run() -> void:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(_map)])
	config.survival_style = 0
	config.difficulty = _difficulty
	config.seed_value = _seed

	for key: String in _sets:
		var was: Variant = config.get(key)
		if was == null:
			push_error("no setting called %s" % key)
			get_tree().quit(2)
			return
		config.set(key, type_convert(_sets[key], typeof(was)))

	_game = ZzGame.new()
	_game.name = "World"
	_game.config = config
	_game.tick_rate = TICK_RATE
	_game.authoritative = true
	_game.register_service = false
	add_child(_game)
	_game.set_physics_process(false)
	await get_tree().physics_frame

	_game.round_over.connect(func(_n: int, won: bool, why: String) -> void:
		if _result.is_empty():
			_result = [won, why])
	_game.player_downed.connect(func(_id: StringName, by: StringName, why: StringName) -> void:
		_current["downs"] = int(_current.get("downs", 0)) + 1
		var cause := "friend" if String(by).begins_with("u") else String(by) if by != &"" else String(why)
		var causes: Dictionary = _current.get_or_add("causes", {})
		causes[cause] = int(causes.get(cause, 0)) + 1
		# Where: the post nearest the survivor downed (its index in the map's posts).
		var who = _game.players.get(_id)
		if who != null:
			var spots: Dictionary = _current.get_or_add("down_posts", {})
			var post := _nearest_post(who.feet())
			spots[post] = int(spots.get(post, 0)) + 1)
	_game.player_died.connect(func(_id: StringName, _by: StringName, _why: StringName) -> void:
		_current["deaths"] = int(_current.get("deaths", 0)) + 1)
	_game.barricade_changed.connect(func(_id: String, _fraction: float, intact: bool) -> void:
		if not intact:
			_current["broken"] = int(_current.get("broken", 0)) + 1
			var which: Dictionary = _current.get_or_add("broke", {})
			which[_id] = int(which.get(_id, 0)) + 1)

	if _game.horde != null and _game.horde.spawner != null:
		_game.horde.spawner.refused.connect(func(owner: StringName, npc_id: StringName, reason: String) -> void:
			var key := "%s for %s: %s" % [npc_id, owner, reason]
			_refusals[key] = int(_refusals.get(key, 0)) + 1)

	var team := 0
	_game.next_map_id = _map
	# The map's team, as a server with zz_team_from_map fills it.
	var doc: Dictionary = _game.catalogue.maps.get(_map, {}) if _game.catalogue != null else {}
	team = maxi(int(doc.get("survivors", 4)), 1)
	for i in team:
		var player := _game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.is_bot = true
	_game.start()

	print("%s: %d stand-ins, difficulty %s, seed %d, %s" % [_map, team, config.difficulty_name(), _seed, _sets])
	print("wave  twist      secs   sent  peak  downs deaths broken  up    tick ms mean/worst   wall s   end")

	var t := 0.0
	var schedule: DotNpcDirectorWaves = null
	var last_index := -1
	var last_stage := -1
	var spent := 0
	var worst := 0
	var ticks := 0
	var peak := 0
	var wall := Time.get_ticks_msec()
	var started_at := 0.0

	while t < _cap and _result.is_empty():
		for i in 32:
			var before := Time.get_ticks_usec()
			if _profile:
				_profiled_step()
			else:
				_game.simulate(TICK)
			var cost := Time.get_ticks_usec() - before
			# Not the map's first tick (the round starting: the nav graph, the map built).
			if _profile and _result.is_empty() and t >= 1.0:
				_keep_spike(cost, t + float(i) * TICK)
			spent += cost
			# Not the tick the hold ended in: a decided round loads the next map in it (one to
			# two seconds), which is a map start, not the crowd's cost.
			if _result.is_empty():
				worst = maxi(worst, cost)
			ticks += 1
		t += 32.0 * TICK
		await get_tree().physics_frame

		if _game.survival == null or _game.survival.waves == null:
			continue

		var w: DotNpcDirectorWaves = _game.survival.waves
		schedule = w
		peak = maxi(peak, _game.horde.commons())

		if _watch > 0.0 and t >= _next_watch:
			_next_watch = t + _watch
			_print_watch(t, w)

		# --from=K: the warm-up leads into wave K, as if K - 1 had been cleared (the caches'
		# tier follows `cleared`). Barricades start whole and nobody is carrying damage, so a
		# late wave played this way is easier than the same wave reached.
		if _from > 1 and w.stage == DotNpcDirectorWaves.Stage.QUIET and w.index < _from and last_stage == -1:
			w.index = _from
			_game.survival.cleared = _from - 1

		if w.stage != last_stage or w.index != last_index:
			if last_stage == DotNpcDirectorWaves.Stage.HORDE:
				_finished_waves += 1
				_close_wave(last_index, t - started_at, w, peak, spent, worst, ticks, wall)
				if last_index >= _until:
					break
			if w.stage == DotNpcDirectorWaves.Stage.HORDE:
				_current = {"index": w.index, "twist": String(_game.survival.twist), "budget": w.budget}
				started_at = t
				spent = 0
				worst = 0
				ticks = 0
				peak = 0
				wall = Time.get_ticks_msec()
			last_stage = w.stage
			last_index = w.index

	if last_stage == DotNpcDirectorWaves.Stage.HORDE and not _current.is_empty() and schedule != null:
		_close_wave(last_index, t - started_at, schedule, peak, spent, worst, ticks, wall)

	var won := not _result.is_empty() and bool(_result[0])
	# Waves this run saw end (not the one it was lost or stopped in), plus those --from skipped.
	var cleared := _finished_waves + (_from - 1)
	print("%s: %s after %.0f s held, %d waves cleared%s" % [_map, "WON" if won else "lost" if not _result.is_empty() else "stopped",
		t, cleared, (" (%s)" % _result[1]) if not _result.is_empty() else ""])
	if _profile:
		var total := 0
		for part: String in _parts:
			total += int(_parts[part])
		for part: String in _parts:
			print("  %-10s %5.1f %%  %.2f ms a tick, worst %.1f ms" % [part, 100.0 * float(_parts[part]) / float(maxi(total, 1)),
				float(_parts[part]) / 1000.0 / maxf(t * float(TICK_RATE), 1.0), float(_worst_parts[part]) / 1000.0])
		# The slowest ticks part by part: one part far over its mean is the game's (a crowd
		# repathing, a spawn burst); every part slow at once is the machine (another process
		# had the core), which no change here can fix.
		for spike: Array in _spikes:
			var line := ""
			for part: String in spike[2]:
				if int(spike[2][part]) >= 1000:
					line += " %s %.0f" % [part, float(spike[2][part]) / 1000.0]
			print("  spike %.1f ms at %.0f s:%s" % [float(spike[0]) / 1000.0, spike[1], line])
	print("RESULT %s" % JSON.stringify({"map": String(_map), "team": team, "seed": _seed, "difficulty": _difficulty,
		"sets": _sets, "won": won, "why": _result[1] if not _result.is_empty() else "", "cleared": cleared,
		"held": snappedf(t, 0.1), "waves": _waves}))
	get_tree().quit(0)


## ZzGame._step, part by part, timed. Kept in the order `_step` has; a profile, not the game.
func _profiled_step() -> void:
	var g := _game
	g._tick += 1
	var delta := TICK
	var at := Time.get_ticks_usec()
	g._advance_phase(delta)
	at = _part("phase", at)
	if g.bots != null:
		g.bots.drive(delta)
	at = _part("bots", at)
	if g.pins != null:
		g.pins.steer(delta)
	for id: StringName in g.players:
		var player = g.players[id]
		if player.is_alive() and not player.watching:
			player.simulate(g._tick, delta)
			g._advance_hands(player, delta)
	at = _part("players", at)
	g._advance_weapons()
	at = _part("weapons", at)
	if g.horde != null:
		at = _profiled_horde(g.horde, delta, at)
	if g.pins != null:
		g.pins.advance(delta)
	if g.hazards != null:
		g.hazards.tick(delta)
	if g.boxes != null:
		g.boxes.tick(delta)
	if g.loot != null:
		g.loot.tick(delta)
	g._advance_bodies(delta)
	at = _part("world", at)
	if g.combat != null:
		g.combat.tick(g._tick, delta)
	if g.spectate != null:
		g.spectate.advance(g._tick)
	if g.sides_are_playable() or g.phase != ZzGame.Phase.IDLE:
		g.match_node.tick(g._tick)
	at = _part("match", at)


## Where the wave's zombies are: within 6 m of a survivor, 6 to 25, 25 to 60, beyond; how
## many are at a barricade, have a target, are in a pending queue; and the survivors' state.
func _print_watch(t: float, w: DotNpcDirectorWaves) -> void:
	var near := 0
	var mid := 0
	var far := 0
	var lost := 0
	var bashing := 0
	var targeted := 0
	var still := 0
	for npc: DotNpcInstance in _game.horde.spawner.npcs_of(_game.horde.WAVE):
		if not npc.is_alive():
			continue
		var best := INF
		for player in _game.survivors():
			if player.is_alive() and not player.watching:
				best = minf(best, player.feet().distance_to(npc.position()))
		if best < 6.0:
			near += 1
		elif best < 25.0:
			mid += 1
		elif best < 60.0:
			far += 1
		else:
			lost += 1
		if npc.brain != null and bool(npc.brain.get(&"bashing")):
			bashing += 1
		if npc.has_target():
			targeted += 1
		var body = npc.node
		if body != null and body is CharacterBody3D and (body as CharacterBody3D).velocity.length() < 0.2:
			still += 1
	var up := 0
	var down := 0
	var shots := 0
	for player in _game.survivors():
		if player.is_up():
			up += 1
		elif player.is_down():
			down += 1
	if _watch_detail:
		var shown := 0
		for npc: DotNpcInstance in _game.horde.spawner.npcs_of(_game.horde.WAVE):
			if not npc.is_alive() or shown >= 6:
				continue
			var nearest = null
			var best := INF
			for player in _game.survivors():
				if player.is_alive() and not player.watching and player.feet().distance_to(npc.position()) < best:
					best = player.feet().distance_to(npc.position())
					nearest = player
			if nearest == null or best > 8.0:
				continue
			shown += 1
			var eye: Vector3 = nearest.eye_position()
			var chest := npc.position() + Vector3(0.0, 1.2, 0.0)
			var head := npc.position() + Vector3(0.0, 1.6, 0.0)
			print("      %s %s at %s, %.1f m from %s at %s; sees chest %s head %s; state %s bashing %s target %s barred '%s'" % [
				npc.def.id, npc.instance_id, npc.position().snappedf(0.1), best, nearest.display_name, nearest.feet().snappedf(0.1),
				_game.clear_between(eye, chest), _game.clear_between(eye, head), npc.brain.get(&"state") if npc.brain != null else "-",
				npc.brain.get(&"bashing") if npc.brain != null else "-", npc.target_id,
				_game.horde.barricade_in_way(npc.position(), (nearest.feet() - npc.position()).normalized())])
		# And a few of the far ones, still: what a stalled wave is doing out there.
		var far_shown := 0
		for npc: DotNpcInstance in _game.horde.spawner.npcs_of(_game.horde.WAVE):
			if not npc.is_alive() or far_shown >= 4 or npc.brain == null:
				continue
			var best := INF
			for player in _game.survivors():
				if player.is_alive() and not player.watching:
					best = minf(best, player.feet().distance_to(npc.position()))
			var body = npc.node
			if best < 25.0 or body == null or (body as CharacterBody3D).velocity.length() >= 0.2:
				continue
			far_shown += 1
			var path: DotNpcPath = npc.brain.get(&"path")
			print("      far %s at %s, %.1f m from anybody; state %s forced '%s' target '%s' wish %s floor %s; path %d points%s, next %s, ends %s" % [
				npc.def.id, npc.position().snappedf(0.1), best, npc.brain.get(&"state"), npc.brain.get(&"forced"), npc.target_id,
				(body.get(&"wish") as Vector3).snappedf(0.1), (body as CharacterBody3D).is_on_floor(), path.points.size() if path != null else -1,
				" partial" if path != null and path.partial else "", path.current(Vector3.INF).snappedf(0.1) if path != null else "-",
				path.points[path.points.size() - 1].snappedf(0.1) if path != null and not path.points.is_empty() else "-"])
	print("  %5.0f s  %s %d  sent %d/%d alive %d: near %d, 6-25 m %d, 25-60 m %d, further %d; bashing %d, targeted %d, still %d | up %d down %d" % [
		t, w.stage_name(), w.index, w.sent, w.budget, _game.horde.wave_alive(), near, mid, far, lost, bashing, targeted, still, up, down])
	if not _refusals.is_empty():
		print("      refused %s" % _refusals)
		_refusals.clear()


## ZzHorde.tick, part by part (the same order).
func _profiled_horde(h, delta: float, at: int) -> int:
	h._time += delta
	h._rebuild_candidates()
	h._rebuild_grid()
	h.spawner.set_candidates(h._candidates)
	at = _part("h.grid", at)
	h._land_alerts()
	h._advance_lures()
	h._advance_bile()
	at = _part("h.alerts", at)
	var sp: DotNpcSpawner = h.spawner
	sp._now += delta
	sp._ticks += 1
	sp._perceive()
	at = _part("h.senses", at)
	sp._think(delta)
	at = _part("h.brains", at)
	sp._reclaim()
	at = _part("h.reclaim", at)
	var speed: float = h.zombie_speed_scale * h.wave_speed_scale
	for npc: DotNpcInstance in h.spawner.all_npcs():
		if npc.is_alive() and npc.node != null and npc.node.has_method(&"tick"):
			npc.node.speed_scale = speed
			npc.node.tick(delta)
	at = _part("h.bodies", at)
	h.squads.prune()
	h._release_pending()
	at = _part("h.release", at)
	if h.pacing:
		if h.waves_mode:
			h._advance_panic()
		else:
			for id: StringName in h._survivors:
				var info: Dictionary = h._survivors[id]
				if bool(info["alive"]):
					h.director.report_player(id, info["position"], float(info["health"]))
			h.director.rules.absolute_cap = h.config.commons_cap(h._survivor_count())
			h.director.tick(delta)
			h._advance_mobs()
			h._advance_specials()
			h._advance_brute()
			h._advance_panic()
	return _part("h.pacing", at)


func _keep_spike(cost: int, at: float) -> void:
	var parts := _tick_parts
	_tick_parts = {}

	if _spikes.size() >= SPIKES_KEPT and cost <= int(_spikes[_spikes.size() - 1][0]):
		return

	_spikes.append([cost, at, parts])
	_spikes.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	_spikes.resize(mini(_spikes.size(), SPIKES_KEPT))


func _part(part: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	_tick_parts[part] = now - since
	_parts[part] = int(_parts.get(part, 0)) + now - since
	_worst_parts[part] = maxi(int(_worst_parts.get(part, 0)), now - since)
	return now


func _close_wave(index: int, seconds: float, w: DotNpcDirectorWaves, peak: int, spent: int, worst: int, ticks: int,
		wall: int) -> void:
	var up := 0
	for player in _game.survivors():
		if player.is_up():
			up += 1
	# Fell out of the map during the wave (the horde takes them out below kill_y and says where
	# each last stood on the floor).
	var fallen: int = _game.horde.fallen_count - _fallen_before
	_fallen_before = _game.horde.fallen_count
	var alive := 0
	for npc: DotNpcInstance in _game.horde.spawner.all_npcs():
		if npc.is_alive():
			alive += 1
	var row := {
		"overtime": w.overtime, "left_alive": alive, "fallen": fallen,
		"index": index, "twist": _current.get("twist", ""), "seconds": snappedf(seconds, 0.1),
		"sent": int(_current.get("budget", w.sent)), "peak": peak,
		"downs": int(_current.get("downs", 0)), "deaths": int(_current.get("deaths", 0)),
		"broken": int(_current.get("broken", 0)), "up": up, "team": _game.survivors().size(),
		"causes": _current.get("causes", {}),
		"tick_mean": snappedf(float(spent) / float(maxi(ticks, 1)) / 1000.0, 0.01),
		"tick_worst": snappedf(float(worst) / 1000.0, 0.1),
		"wall": snappedf(float(Time.get_ticks_msec() - wall) / 1000.0, 0.1),
	}
	_waves.append(row)
	print("%4d  %-9s %6.0f %6d %5d %6d %6d %6d  %2d/%-2d   %6.2f / %6.1f    %6.0f   %s%d alive, %d fallen" % [index, row["twist"], seconds,
		row["sent"], peak, row["downs"], row["deaths"], row["broken"], up, row["team"], row["tick_mean"], row["tick_worst"], row["wall"],
		"overtime, " if w.overtime else "", alive, fallen])
	if not (row["causes"] as Dictionary).is_empty():
		print("        downed by %s, by post %s" % [row["causes"], _current.get("down_posts", {})])
	if not (_current.get("broke", {}) as Dictionary).is_empty():
		print("        broke %s" % _current["broke"])
	if fallen > 0:
		print("        fell out from %s, %s" % [_game.horde.fallen_from.slice(-mini(fallen, 8)), _game.horde.fallen_how.slice(-mini(fallen, 8))])
	_current = {}


## The index of the map's post nearest [param at] ("-" for a map without posts): where a
## survivor was downed, by the post that covers it.
func _nearest_post(at: Vector3) -> String:
	var posts: Array = _game.map_doc.get("posts", [])
	var best := -1
	var gap := INF
	for i in posts.size():
		var p: Array = posts[i]
		var d := Vector2(float(p[0]) - at.x, float(p[2]) - at.z).length()
		if d < gap:
			gap = d
			best = i
	return "-" if best < 0 else str(best)
