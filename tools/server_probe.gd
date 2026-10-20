extends Node

## What a dedicated Zombie Zone server's tick costs with N survivors and the horde at its cap,
## part by part (zz-scale-probe-1). The baseline every scaling and threading task measures against.
##
## [codeblock]
## tools/server_probe.sh                       # 16 32 64 100 128 at 64 and 33 Hz, one process each
## godot --headless --path . res://tools/server_probe.tscn -- --n=64 --rate=64 [--map=zz_stadium]
##     [--commons=250] [--seconds=12] [--wave=10]
## [/codeblock]
##
## [b]The real server half, without a socket[/b]: [ZzGame] on the map, a [DotNetManager] and a
## [ZzNetBridge] with the socket replaced by a counter (load_probe's pattern in game-g2gfast, and
## headless_net's wiring). Every survivor is a peer the way a real one is (`add_player`, `_admit`,
## its own entity and snapshot) and is then driven by the stand-in brain (`is_bot`), so it walks
## the route, holds a post and shoots, and the snapshots do the work they would for N people.
## The hold is put at wave 10 (`--wave`), the horde at the cap for N, and the measured window starts
## when it is up.
##
## [b]Phases[/b] are laps taken around ZzGame._step's own calls (kept in step with it, as
## survival_long_run's profile is) and around the manager's half of the tick. dot-npc has no timer
## inside a path search, so pathing is derived: searches per tick from
## [member DotNpcNavGraph.searches], times the cost of one search measured on the same graph after
## the window. The engine's own frame (one physics step of the server's world) is the time spent in
## `await physics_frame`, taken once every 16 ticks; "bodies" is the zombies' move_and_slide, the motor queries.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNetBridge := preload("../game/net/zz_net_bridge.gd")
const ZzEvents := preload("../game/net/zz_events.gd")

const SNAPSHOT_RATE := 30

var _map := &"zz_stadium"
var _n := 16
var _rate := 64
var _commons := 0
var _seconds := 12.0
var _wave := 10
## Seconds of play allowed to get the horde up before the window opens, and whether the probe tops
## the commons up to the cap itself (the stand-ins kill them as fast as a wave releases them).
var _lead := 90.0
var _fill := true
var _game: ZzGame
var _net: DotNetManager
var _bridge: ZzNetBridge
var _bytes := 0
var _watched_peer := 2
var _lap: Dictionary = {}
var _series: Dictionary = {}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map = StringName(arg.trim_prefix("--map="))
		elif arg.begins_with("--n="):
			_n = arg.trim_prefix("--n=").to_int()
		elif arg.begins_with("--rate="):
			_rate = arg.trim_prefix("--rate=").to_int()
		elif arg.begins_with("--commons="):
			_commons = arg.trim_prefix("--commons=").to_int()
		elif arg.begins_with("--seconds="):
			_seconds = arg.trim_prefix("--seconds=").to_float()
		elif arg.begins_with("--lead="):
			_lead = arg.trim_prefix("--lead=").to_float()
		elif arg == "--no-fill":
			_fill = false
		elif arg.begins_with("--wave="):
			_wave = arg.trim_prefix("--wave=").to_int()
	_run.call_deferred()


func _run() -> void:
	Engine.physics_ticks_per_second = _rate
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(_map)])
	config.survival_style = 0
	config.seed_value = 1
	if _commons > 0:
		# A fixed crowd whatever the team: the cap is the base alone.
		config.commons_base = _commons
		config.commons_per_survivor = 0
	_game = ZzGame.new()
	_game.name = "World"
	_game.config = config
	_game.tick_rate = _rate
	_game.authoritative = true
	_game.register_service = false
	add_child(_game)
	_game.set_physics_process(false)

	_net = DotNetManager.new()
	_net.name = "Server"
	_net.is_server = true
	_net.local_peer_id = 1
	_net.service_scope = &"server_probe"
	_net.auto_tick = false
	_net.config_file = ""
	var nc := DotNetConfig.new()
	nc.tick_rate = _rate
	nc.snapshot_rate = SNAPSHOT_RATE
	nc.enable_prediction = true
	nc.enable_lag_compensation = false
	nc.max_entities_per_snapshot = 192
	nc.world_extent = ZzGame.NET_WORLD_EXTENT
	_net.config = nc
	add_child(_net)
	var _ok := _net.setup()
	_bridge = ZzNetBridge.new()
	add_child(_bridge)
	var attached := _bridge.attach(_game, _net)
	if not attached.ok:
		push_error("bridge refused: %s" % attached.error)
		get_tree().quit(2)
		return
	_bridge.open_link(self)
	_net.messages.seal()
	_bridge.link.loopback = func(_method: StringName, peer_id: int, payload: PackedByteArray) -> void:
		if peer_id == _watched_peer or peer_id == 0:
			_bytes += payload.size()
	var _s := _net.start()
	await get_tree().physics_frame

	_game.next_map_id = _map
	for i in _n:
		var peer := i + 2
		var added := _bridge.add_player(peer, peer, "Survivor%d" % i)
		if not added.ok:
			push_error("player %d refused: %s" % [i, added.error])
			continue
		(added.value as Object).set(&"is_bot", true)
		_bridge._admit(peer)
	_game.start()

	var tick := 0
	var wave_set := false
	var up_to_cap_at := -1
	var measured := 0
	var window := int(_seconds * float(_rate))
	var physics_ms: Array = []
	var searches0 := 0
	var wall := Time.get_ticks_msec()
	var cap := 0
	var limit := 3600 * _rate
	var path_graph = null

	while measured < window and tick < limit:
		tick += 1
		var measuring := up_to_cap_at >= 0
		_lap = {}
		_one_tick(tick)
		if measuring:
			measured += 1
			for k: String in _lap:
				(_series.get_or_add(k, []) as Array).append(float(_lap[k]) / 1000.0)
		if tick % 16 == 0:
			var before := Time.get_ticks_usec()
			await get_tree().physics_frame
			if measuring:
				physics_ms.append(float(Time.get_ticks_usec() - before) / 1000.0)

		var w: DotNpcDirectorWaves = _game.survival.waves if _game.survival != null else null
		if w == null:
			continue
		if not wave_set and w.stage == DotNpcDirectorWaves.Stage.QUIET:
			w.index = _wave
			_game.survival.cleared = _wave - 1
			wave_set = true
		if wave_set and up_to_cap_at < 0:
			cap = _game.config.commons_cap(_n)
			if _game.horde.commons() >= int(0.9 * cap) or tick > int(_lead * float(_rate)):
				up_to_cap_at = tick
				_bytes = 0
				path_graph = _game.horde.spawner.nav
				searches0 = path_graph.searches
		if wave_set and _fill and tick % (_rate / 2) == 0:
			_game.horde.spawn_mob(maxi(cap - _game.horde.commons() - _game.horde.pending_commons(), 0))
		if tick % (_rate * 20) == 0:
			print("[probe] tick %d  stage %s  commons %d/%d  wall %.0f s" % [tick, w.stage_name(), _game.horde.commons(), cap, float(Time.get_ticks_msec() - wall) / 1000.0])

	if up_to_cap_at < 0 or measured == 0:
		print("[probe] FAILED to reach the cap or measure (n=%d rate=%d)" % [_n, _rate])
		get_tree().quit(1)
		return

	var searches: int = path_graph.searches - searches0
	var us_per_search := _search_cost(path_graph)
	var up := 0
	for p in _game.survivors():
		if p.is_up():
			up += 1
	var commons := _game.horde.commons()
	var npcs := _game.horde.spawner.all_npcs().size()
	var secs := float(measured) / float(_rate)
	# What interest leaves each peer, averaged over the peers: the number a snapshot's cost follows.
	var all_identities := _net.registry.all()
	var told := 0
	var asked := 0
	for p in _game.survivors():
		var peer := _bridge.peer_for_player(_bridge.session_of(p.player_id))
		if peer <= 0:
			continue
		var seen := _net.interest.relevant_for(_net._observer_for(peer), all_identities, peer, {"tick": 0, "config": _net.config})
		told += seen.size()
		asked += 1
	var row := {"relevant_per_peer": snappedf(float(told) / float(maxi(asked, 1)), 0.1), "entities": all_identities.size(), "n": _n, "rate": _rate, "commons_cap": cap, "commons": commons, "npcs": npcs, "up": up,
		"budget_ms": snappedf(1000.0 / float(_rate), 0.01), "ticks": measured,
		"bytes_per_s_per_peer": int(float(_bytes) / secs),
		"searches_per_tick": snappedf(float(searches) / float(measured), 0.01),
		"us_per_search": snappedf(us_per_search, 0.1),
		"path_ms_derived": snappedf(float(searches) / float(measured) * us_per_search / 1000.0, 0.01),
		"engine_step_ms": _stats(physics_ms), "rss_peak_mb": _peak_mb(), "phases": {}}
	for k: String in _series:
		row["phases"][k] = _stats(_series[k])
	print("RESULT %s" % JSON.stringify(row))
	get_tree().quit(0)


## One server tick: ZzGame._step's laps, then the manager's pull and snapshot send.
func _one_tick(tick: int) -> void:
	var g := _game
	g._tick = tick
	_bridge._tick = tick
	_bridge._game_ticked_for = tick
	var delta := g.delta_for_tick()
	var at := Time.get_ticks_usec()
	var total_start := at
	g._advance_phase(delta)
	if g.bots != null:
		g.bots.drive(delta)
	if g.pins != null:
		g.pins.steer(delta)
	for id: StringName in g.players:
		var player = g.players[id]
		if player.is_alive() and not player.watching:
			player.simulate(g._tick, delta)
			g._advance_hands(player, delta)
	g._advance_weapons()
	g._advance_toys(delta)
	at = _add("logic", at)
	var h = g.horde
	if h != null:
		h._time += delta
		h._rebuild_candidates()
		h._rebuild_grid()
		h.spawner.set_candidates(h._candidates)
		h._land_alerts()
		h._advance_lures()
		h._advance_bile()
		at = _add("horde_other", at)
		var sp: DotNpcSpawner = h.spawner
		sp._now += delta
		sp._ticks += 1
		sp._perceive()
		at = _add("senses", at)
		sp._think(delta)
		at = _add("brains", at)
		sp._reclaim()
		var speed: float = h.zombie_speed_scale * h.wave_speed_scale
		at = _add("horde_other", at)
		for npc: DotNpcInstance in sp.all_npcs():
			if npc.is_alive() and npc.node != null and npc.node.has_method(&"tick"):
				npc.node.speed_scale = speed
				npc.node.tick(delta)
		at = _add("bodies", at)
		h.squads.prune()
		h._release_pending()
		if h.pacing:
			if h.waves_mode:
				h._advance_panic()
			else:
				h._advance_mobs()
				h._advance_specials()
				h._advance_brute()
				h._advance_panic()
		at = _add("horde_other", at)
	if g.pins != null:
		g.pins.advance(delta)
	if g.hazards != null:
		g.hazards.tick(delta)
	if g.boxes != null:
		g.boxes.tick(delta)
	if g.loot != null:
		g.loot.tick(delta)
	g._advance_bodies(delta)
	if g.combat != null:
		g.combat.tick(g._tick, delta)
	if g.spectate != null:
		g.spectate.advance(g._tick)
	if g.sides_are_playable() or g.phase != ZzGame.Phase.IDLE:
		g.match_node.tick(g._tick)
	at = _add("logic", at)

	# The manager's half of net.server_tick, apart: the entities' pull, then the snapshots.
	_net.clock.tick = maxi(_net.clock.tick, tick)
	var identities := _net.registry.all()
	var step := _net.clock.tick_duration()
	for identity in identities:
		if identity.can_simulate():
			for behaviour in identity.behaviours:
				behaviour._net_simulate(tick, step)
	at = _add("net_pull", at)
	_net._ticks_since_snapshot += 1
	if _net._ticks_since_snapshot >= _net.config.ticks_per_snapshot():
		_net._ticks_since_snapshot = 0
		_net.history.record(identities, tick)
		at = _add("net_history", at)
		_net._send_snapshots(tick, identities)
	if tick % ZzNetBridge.CLOCK_EVERY == 0:
		_bridge._broadcast(ZzEvents.Kind.CLOCK, _bridge._clock_body())
	at = _add("net_snapshot", at)
	_lap["total"] = at - total_start


func _add(phase: String, since: int) -> int:
	var now := Time.get_ticks_usec()
	_lap[phase] = int(_lap.get(phase, 0)) + now - since
	return now


## Microseconds for one A* search on this graph between two random points of the crowd.
func _search_cost(graph) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pts: Array = []
	for npc: DotNpcInstance in _game.horde.spawner.all_npcs():
		if npc.is_alive():
			pts.append(npc.position())
	for p in _game.survivors():
		pts.append(p.feet())
	if pts.size() < 2:
		return 0.0
	var runs := 300
	var at := Time.get_ticks_usec()
	for i in runs:
		var _path: PackedVector3Array = graph.find_path(pts[rng.randi() % pts.size()], pts[rng.randi() % pts.size()], 3.0, true)
	return float(Time.get_ticks_usec() - at) / float(runs)


func _stats(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var mean := 0.0
	for v in values:
		mean += v
	mean /= maxf(float(values.size()), 1.0)
	if sorted.is_empty():
		return {"mean": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0}
	return {"mean": snappedf(mean, 0.01), "p50": snappedf(sorted[sorted.size() / 2], 0.01),
		"p95": snappedf(sorted[int(sorted.size() * 0.95)], 0.01), "max": snappedf(sorted.back(), 0.01)}


func _peak_mb() -> int:
	var file := FileAccess.open("/proc/self/status", FileAccess.READ)
	while file != null and not file.eof_reached():
		var line := file.get_line()
		if line.begins_with("VmHWM:"):
			return int(line.get_slice(":", 1).strip_edges().get_slice(" ", 0)) / 1024
	return 0
