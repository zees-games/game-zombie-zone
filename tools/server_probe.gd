extends Node

## What a dedicated Zombie Zone server's tick costs with N survivors and the horde at its cap,
## part by part (zz-scale-probe-1). The baseline every scaling and threading task measures against.
##
## [codeblock]
## tools/server_probe.sh                       # 16 32 64 100 128 at 64 and 33 Hz, one process each
## godot --headless --path . res://tools/server_probe.tscn -- --n=64 --rate=64 [--map=zz_stadium]
##     [--commons=250] [--seconds=12] [--wave=10] [--relevance=off] [--workers=4] [--npc-workers=4] [--acks] [--native] [--native-interest] [--net=field=value]
##     [--detail] [--cfg=field=value] [--cvar=name=value]
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
## --relevance=off sends every entity to every peer (DotNetInterestAll), the before of the lever.
var _relevance := true
## DotNetConfig.snapshot_workers for the run (0 inline, -1 auto, n).
var _workers := 0
## --npc-workers=N: DotNpcSpawner.sense_workers and path_workers (what sv_threads_npc sets on a server).
var _npc_workers := 0
## --native: DotNetConfig.native, snapshots built by dot-net's native core.
var _native := false
## --native-interest: also DotNetConfig.native_interest. --net=field=value (repeatable): any other DotNetConfig field.
var _native_interest := false
var _net_fields: Dictionary = {}
## --acks: every peer acknowledges each snapshot ACK_LAG snapshots late, as a real client does
## (game-g2gfast's load_probe LOAD_ACKS=1); without it every peer is the no-ack host.
var _acks := false
## --split: the inline snapshot path run here instead of the manager's, lapped as
## si_relevant, si_thin, si_scores, si_prioritise, si_budget and snap_build (_send_to_peer) per peer.
var _split := false
## Snapshots built, for the prep/join/apply means of a native or pooled run.
var _snaps := 0
## --far-every=N --far=M: DotNetInterest thinning, everything past M metres sent every Nth snapshot.
var _far_every := 1
var _far := 0.0
## --far-coherent, --far-tiers=T: DotNetInterest.far_coherent and far_tiers.
var _far_coherent := false
var _far_tiers := 1
const ACK_LAG := 2
## --detail: brains timed by kind, players split into simulate and hands, and where the NPCs
## stand from the nearest survivor, printed as a DETAIL line after RESULT.
var _detail := false
var _acc: Dictionary = {}
var _near_hist: Dictionary = {}
var _detail_ticks := 0
## --cfg=field=value (repeatable): a ZzConfig field set before the game starts, e.g. squad_coalesce=true.
var _cfg: Dictionary = {}
## --cvar=name=value (repeatable): dot-game's DotGameNpcLod cvars (npc_lod, npc_lod_full, npc_sense_quiet ...) on a stand-in console.
var _cvars: Dictionary = {}
var _lod: DotGameNpcLod = null
## Gameplay counters over the window: zombies killed, health zombies lost, health survivors lost, and zombies with a target per tick.
var _kills := 0
var _dmg_npc := 0.0
var _dmg_survivor := 0.0
var _engaged := 0
var _sent_ticks: Dictionary = {}
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
		elif arg == "--split":
			_split = true
		elif arg == "--acks":
			_acks = true
		elif arg == "--native":
			_native = true
		elif arg == "--native-interest":
			_native = true
			_native_interest = true
		elif arg.begins_with("--net="):
			var kv := arg.trim_prefix("--net=").split("=", true, 1)
			if kv.size() == 2:
				_net_fields[kv[0]] = kv[1]
		elif arg == "--relevance=off":
			_relevance = false
		elif arg.begins_with("--npc-workers="):
			_npc_workers = arg.trim_prefix("--npc-workers=").to_int()
		elif arg.begins_with("--workers="):
			_workers = arg.trim_prefix("--workers=").to_int()
		elif arg.begins_with("--far-every="):
			_far_every = arg.trim_prefix("--far-every=").to_int()
		elif arg.begins_with("--far="):
			_far = arg.trim_prefix("--far=").to_float()
		elif arg == "--far-coherent":
			_far_coherent = true
		elif arg.begins_with("--far-tiers="):
			_far_tiers = arg.trim_prefix("--far-tiers=").to_int()
		elif arg == "--detail":
			_detail = true
		elif arg.begins_with("--cfg="):
			var pair := arg.trim_prefix("--cfg=").split("=", true, 1)
			if pair.size() == 2:
				_cfg[pair[0]] = str_to_var(pair[1])
		elif arg.begins_with("--cvar="):
			var cv := arg.trim_prefix("--cvar=").split("=", true, 1)
			if cv.size() == 2:
				_cvars[cv[0]] = cv[1]
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
	for key: String in _cfg:
		config.set(key, _cfg[key])
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
	nc.snapshot_workers = _workers
	nc.native = _native
	nc.native_interest = _native_interest
	for field: String in _net_fields:
		nc.set(field, type_convert(_net_fields[field], typeof(nc.get(field))))
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
	if not _relevance:
		_net.interest = DotNetInterestAll.new()
	_net.interest.far_every = _far_every
	_net.interest.far_distance = _far
	_net.interest.far_coherent = _far_coherent
	_net.interest.far_tiers = _far_tiers
	_bridge.open_link(self)
	_net.messages.seal()
	_bridge.link.loopback = func(method: StringName, peer_id: int, payload: PackedByteArray) -> void:
		if peer_id == _watched_peer or peer_id == 0:
			_bytes += payload.size()
		if _acks and method == &"snapshot" and peer_id >= 2:
			_ack_later(peer_id, payload)
	var _s := _net.start()
	_net.snapshot_sent.connect(func(_t: int, _n2: int) -> void: _snaps += 1)
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
		if _detail and measuring and _detail_ticks == 0:
			_acc.clear()
			_near_hist.clear()
		if measuring:
			_detail_ticks += 1
		_one_tick(tick)
		if measuring:
			for id in _game.horde.spawner._npcs:
				var inst: DotNpcInstance = _game.horde.spawner._npcs[id]
				_engaged += 1 if inst.is_alive() and inst.has_target() else 0
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
				_game.horde.spawner.died.connect(func(_n, _b): _kills += 1)
				_game.combat.damage_applied.connect(func(d: DotDamage) -> void:
					if _game.horde.is_npc_entity(d.victim):
						_dmg_npc += d.health_lost
					else:
						_dmg_survivor += d.health_lost)
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
	var row := {"acks": _acks, "relevance": _relevance, "far_every": _far_every, "far": _far, "far_coherent": _far_coherent, "far_tiers": _far_tiers, "workers": _workers, "npc_workers": _npc_workers, "native": _net._native_note if _native else "off", "relevant_per_peer": snappedf(float(told) / float(maxi(asked, 1)), 0.1), "entities": all_identities.size(), "n": _n, "rate": _rate, "commons_cap": cap, "commons": commons, "npcs": npcs, "up": up,
		"budget_ms": snappedf(1000.0 / float(_rate), 0.01), "ticks": measured,
		"bytes_per_s_per_peer": int(float(_bytes) / secs),
		"snapshot_ms": _snapshot_split(),
		"searches_per_tick": snappedf(float(searches) / float(measured), 0.01),
		"us_per_search": snappedf(us_per_search, 0.1),
		"path_ms_derived": snappedf(float(searches) / float(measured) * us_per_search / 1000.0, 0.01),
		"engine_step_ms": _stats(physics_ms), "rss_peak_mb": _peak_mb(), "phases": {}}
	for k: String in _series:
		row["phases"][k] = _stats(_series[k])
	row["gameplay"] = {"kills": _kills, "dmg_to_zombies": snappedf(_dmg_npc, 1.0),
		"dmg_to_survivors": snappedf(_dmg_survivor, 1.0), "engaged_mean": snappedf(float(_engaged) / float(maxi(measured, 1)), 0.1)}
	if _lod != null:
		row["lod"] = _lod.describe()
	print("RESULT %s" % JSON.stringify(row))
	if _detail:
		var per := {}
		for k: String in _acc:
			var a: Array = _acc[k]
			per[k] = {"ms_per_tick": snappedf(float(a[0]) / 1000.0 / float(_detail_ticks), 0.01),
				"us_each": snappedf(float(a[0]) / float(maxi(int(a[1]), 1)), 0.1),
				"per_tick": snappedf(float(a[1]) / float(_detail_ticks), 0.1)}
		print("DETAIL %s" % JSON.stringify({"parts": per, "nearest_survivor_m": _near_hist}))
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
	at = _add("bots", at)
	for id: StringName in g.players:
		var player = g.players[id]
		if player.is_alive() and not player.watching:
			if _detail:
				var t0 := Time.get_ticks_usec()
				player.simulate(g._tick, delta)
				var t1 := Time.get_ticks_usec()
				g._advance_hands(player, delta)
				_accum("player.simulate", t1 - t0)
				_accum("player.hands", Time.get_ticks_usec() - t1)
			else:
				player.simulate(g._tick, delta)
				g._advance_hands(player, delta)
	at = _add("players", at)
	var wt := Time.get_ticks_usec()
	g._advance_weapons()
	wt = _lap_logic("logic.weapons", wt)
	g._advance_toys(delta)
	wt = _lap_logic("logic.toys", wt)
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
		sp.sense_workers = _npc_workers
		sp.path_workers = _npc_workers
		if _lod == null and not _cvars.is_empty():
			var console := DotConsole.new()
			add_child(console)
			DotGameNpcLod.ensure_cvars(console)
			for name: String in _cvars:
				console.set_cvar(name, _cvars[name])
			_lod = DotGameNpcLod.attach(self, console, sp)
		if _lod != null:
			_lod.follow(delta)
		sp._perceive()
		at = _add("senses", at)
		if _detail:
			_think_detail(sp, delta)
		else:
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
	var lt := Time.get_ticks_usec()
	if g.pins != null:
		g.pins.advance(delta)
	lt = _lap_logic("logic.pins", lt)
	if g.hazards != null:
		g.hazards.tick(delta)
	if g.boxes != null:
		g.boxes.tick(delta)
	if g.loot != null:
		g.loot.tick(delta)
	lt = _lap_logic("logic.hazards_boxes_loot", lt)
	g._advance_bodies(delta)
	lt = _lap_logic("logic.bodies", lt)
	if g.combat != null:
		g.combat.tick(g._tick, delta)
	lt = _lap_logic("logic.combat", lt)
	if g.spectate != null:
		g.spectate.advance(g._tick)
	if g.sides_are_playable() or g.phase != ZzGame.Phase.IDLE:
		g.match_node.tick(g._tick)
	lt = _lap_logic("logic.spectate_match", lt)
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
		if _split and _workers == 0 and not _native:
			_split_snapshots(tick, identities)
		else:
			_net._send_snapshots(tick, identities)
	if tick % ZzNetBridge.CLOCK_EVERY == 0:
		_bridge._broadcast(ZzEvents.Kind.CLOCK, _bridge._clock_body())
	at = _add("net_snapshot", at)
	_lap["total"] = at - total_start


## DotNetManager._send_snapshots' inline path (workers 0), the same calls, lapped by part.
func _split_snapshots(tick: int, identities: Array[DotNetIdentity]) -> void:
	var n := _net
	var context := {"tick": tick, "config": n.config, "now_ms": Time.get_ticks_msec()}
	var at := Time.get_ticks_usec()
	n.interest._prepare(identities, context)
	n._last_snapshot_tick = tick
	for identity in identities:
		for behaviour in identity.behaviours:
			behaviour.begin_snapshot_reads(int(context["now_ms"]), false)
	at = _add("snap_reads", at)
	for peer_id in n._peers:
		n.budget.begin_tick(peer_id)
		var observer := n._observer_for(peer_id)
		var relevant := n.interest.relevant_for(observer, identities, peer_id, context)
		at = _add("si_relevant", at)
		if n.interest.thins():
			var kept: Array[DotNetIdentity] = []
			n.interest.thin_into(kept, observer, relevant, peer_id, context)
			relevant = kept
		at = _add("si_thin", at)
		var scores := {}
		for identity in relevant:
			scores[identity.net_id] = n.interest._score(observer, identity, context)
		at = _add("si_scores", at)
		relevant = n.interest.prioritise(observer, relevant, n.config.entity_cap(), context, peer_id)
		at = _add("si_prioritise", at)
		relevant = n.budget.accumulate(peer_id, relevant, scores)
		at = _add("si_budget", at)
		var _sent := n._send_to_peer(peer_id, tick, relevant)
		at = _add("snap_build", at)
	for identity in identities:
		for behaviour in identity.behaviours:
			behaviour.end_snapshot_reads()
	at = _add("snap_reads", at)
	n.snapshot_sent.emit(tick, n._peers.size())


## What a client does with a snapshot, ACK_LAG snapshots late: the ack its encode_ack would send.
func _ack_later(peer_id: int, payload: PackedByteArray) -> void:
	var tick := DotNetReader.new(payload).read_uint(32)
	var list: Array = _sent_ticks.get_or_add(peer_id, [])
	if not list.is_empty() and list.back() == tick:
		return
	list.append(tick)
	if list.size() <= ACK_LAG:
		return
	var ack := DotNetWriter.new()
	ack.write_uint(int(list.pop_front()), 32)
	var _taken := _net.receive_ack_payload(peer_id, ack.to_bytes())


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


func _lap_logic(key: String, t0: int) -> int:
	var now := Time.get_ticks_usec()
	if _detail:
		_accum(key, now - t0)
	return now


func _accum(key: String, usec: int) -> void:
	var a: Array = _acc.get_or_add(key, [0, 0])
	a[0] += usec
	a[1] += 1


## DotNpcSpawner._think, each brain lapped by its kind; every 64th tick, the NPCs' distances.
func _think_detail(sp: DotNpcSpawner, delta: float) -> void:
	var sample := sp._ticks % 64 == 0
	var survivors: Array = []
	if sample:
		for p in _game.survivors():
			if p.is_up():
				survivors.append(p.global_position)
	for id in sp._npcs.keys():
		var found: Variant = sp._npcs.get(id)
		if not (found is DotNpcInstance):
			continue
		var npc: DotNpcInstance = found
		if not npc.is_alive() or npc.brain == null:
			continue
		var t0 := Time.get_ticks_usec()
		(npc.brain as DotNpcBrain).think(delta)
		var spent := Time.get_ticks_usec() - t0
		_accum("brain." + String(npc.def.id), spent)
		_accum("brain.thought" if int(npc.brain.get(&"_since_thought")) == 0 else "brain.skipped", spent)
		if sample and npc.node is Node3D:
			var best := INF
			var at: Vector3 = (npc.node as Node3D).global_position
			for q: Vector3 in survivors:
				best = minf(best, at.distance_to(q))
			var bucket := "<10" if best < 10.0 else "<20" if best < 20.0 else "<40" if best < 40.0 else "<80" if best < 80.0 else ">=80"
			_near_hist[bucket] = int(_near_hist.get(bucket, 0)) + 1
	var t1 := Time.get_ticks_usec()
	sp.answer_paths()
	_accum("paths", Time.get_ticks_usec() - t1)


## Mean ms per snapshot (all peers) spent preparing, joining the workers and applying the results.
func _snapshot_split() -> Dictionary:
	var n := float(maxi(_snaps, 1))
	return {"snapshots": _snaps, "interest": snappedf(_net._snapshot_interest_usec_total / n / 1000.0, 0.01),
		"submit": snappedf(_net._snapshot_submit_usec_total / n / 1000.0, 0.01), "prep": snappedf(_net._snapshot_prep_usec_total / n / 1000.0, 0.01),
		"join": snappedf(_net._snapshot_join_usec_total / n / 1000.0, 0.01),
		"apply": snappedf(_net._snapshot_apply_usec_total / n / 1000.0, 0.01)}
