extends "shot.gd"

## A fixed-seed frame benchmark: a solo game on one map, N commons kept alive round the
## survivor (a dead one is replaced), the eyes turning once round per run, every frame timed.
## Prints one BENCH line (wall, physics, script, render, GPU and render-CPU time, draw calls, objects, primitives) so
## runs on the same box compare. `tools/bench.sh --zz-map-ids=zm_abandoned_mall --zombies=56`.

var _count := 56
var _bench_seed := 7
var _measure := 20.0
var _warm := 4.0
var _ring := Vector2(8.0, 40.0)
var _clock := DotMenuFrameClock.new()
var _rows: Array[PackedInt32Array] = []
var _recording := false
## --profile: the game's tick is stepped here part by part (survival_long_run's split) and the
## parts are printed as PROFILE lines, ms per tick over the measured frames.
var _profile := false
var _profiler: Node = null
var _ticks := 0
var _load_s := 0.0
## Engine monitors per measured frame: physics-process ms (the scripts' _physics_process), active bodies, pairs, islands.
var _monitors: Array[PackedFloat64Array] = []


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zombies="):
			_count = arg.trim_prefix("--zombies=").to_int()
		elif arg.begins_with("--seed="):
			_bench_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--measure="):
			_measure = arg.trim_prefix("--measure=").to_float()
		elif arg == "--profile":
			_profile = true
	var game: ZzGame = _client.get("game")
	await _until_a_round(game)
	_load_s = Time.get_ticks_msec() / 1000.0
	var local = _client.get("player")
	for player in game.survivors():
		player.health.invulnerable = true
	var stand: Vector3 = _at if _at != Vector3.INF else _default_stand(game)
	local.place_at(stand, float(game.map.spawn("survivors", 0)[1]) if _at == Vector3.INF else 0.0)
	await _seconds_of(1.0)

	if "--micro" in OS.get_cmdline_user_args():
		var g := game
		var n := 200
		var t0 := Time.get_ticks_usec()
		for i in n:
			g.bots.drive(1.0 / 60.0)
		print("MICRO bots.drive %.1f us/call" % [float(Time.get_ticks_usec() - t0) / n])
		var survs = g.survivors()
		print("MICRO survivors %d" % survs.size())
		t0 = Time.get_ticks_usec()
		for i in n:
			for pl in survs:
				pl.controller.simulate_tick(1000 + i, 1.0 / 60.0)
		print("MICRO simulate_tick %.1f us/player" % [float(Time.get_ticks_usec() - t0) / n / survs.size()])
		t0 = Time.get_ticks_usec()
		for i in n:
			g._advance_weapons()
		print("MICRO advance_weapons %.1f us/call" % [float(Time.get_ticks_usec() - t0) / n])
		t0 = Time.get_ticks_usec()
		for i in n:
			for pl in survs:
				g._advance_hands(pl, 1.0 / 60.0)
		print("MICRO advance_hands %.1f us/player" % [float(Time.get_ticks_usec() - t0) / n / survs.size()])
		t0 = Time.get_ticks_usec()
		for i in n:
			g.combat.tick(g._tick, 1.0 / 60.0)
		print("MICRO combat.tick %.1f us" % [float(Time.get_ticks_usec() - t0) / n])
		get_tree().quit(0)
		return
	if _profile:
		_profiler = (load("res://tools/survival_long_run.gd") as GDScript).new()
		_profiler.set(&"_game", game)
		game.external_tick = true
	var rng := RandomNumberGenerator.new()
	rng.seed = _bench_seed
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var gpu := PackedFloat64Array()
	var cpu := PackedFloat64Array()
	_clock.on_frame = _on_frame
	_clock.start(get_tree())
	var start_yaw: float = local.controller.state.yaw
	var began := Time.get_ticks_msec()
	var total_ms := (_warm + _measure) * 1000.0
	var draws := PackedInt32Array()
	var objects := PackedInt32Array()
	var prims := PackedInt32Array()
	var alive_sum := 0
	while Time.get_ticks_msec() - began < total_ms:
		_keep_crowd(game, local, stand, rng)
		var t := float(Time.get_ticks_msec() - began) / total_ms
		local.controller.state.yaw = start_yaw + 360.0 * t
		local.controller.state.pitch = -4.0
		if local.sampler != null:
			local.sampler.look_at_angles(local.controller.state.yaw, -4.0)
		await get_tree().process_frame
		_recording = Time.get_ticks_msec() - began >= _warm * 1000.0
		if _recording:
			draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			objects.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			alive_sum += _alive(game)
			_monitors.append(PackedFloat64Array([Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
				Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)]))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	_clock.stop()
	if _profiler != null:
		var parts: Dictionary = _profiler.get(&"_parts")
		for part: String in parts:
			print("PROFILE %-10s %.3f ms/tick" % [part, float(parts[part]) / 1000.0 / maxf(1.0, _ticks)])
		_profiler.free()
	var sums := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for m in _monitors:
		for i in 4:
			sums[i] += m[i] / maxf(1.0, _monitors.size())
	print("MONITORS physics_process_ms=%.2f active_3d=%.1f pairs=%.1f islands=%.1f" % [sums[0], sums[1], sums[2], sums[3]])
	_report(draws, objects, prims, float(alive_sum) / maxf(1.0, draws.size()), game, gpu, cpu)
	# The last frame, to look at: the numbers say nothing about what a crowd detail level looks like.
	var path := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	print("saved %s: %s" % [_out, error_string(get_viewport().get_texture().get_image().save_png(path))])
	get_tree().quit(0)


func _physics_process(_delta: float) -> void:
	if _profiler == null:
		return
	if not _recording:
		(_profiler.get(&"_parts") as Dictionary).clear()
		_ticks = 0
	_profiler.call(&"_profiled_step")
	_ticks += 1


func _alive(game: ZzGame) -> int:
	return game.horde.spawner.all_npcs().size()


## Tops the crowd up to N commons at seeded points on the ground 8 to 40 m out.
func _keep_crowd(game: ZzGame, local, stand: Vector3, rng: RandomNumberGenerator) -> void:
	var missing := _count - _alive(game)
	for _i in mini(missing, 8):
		var angle := rng.randf() * TAU
		var reach := rng.randf_range(_ring.x, _ring.y)
		var at := stand + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
		var npc: DotNpcInstance = game.horde.spawner.spawn(ZzNpcs.COMMON, game.horde.snap_to_nav(at), &"bench", Basis(Vector3.UP, rng.randf() * TAU))
		if npc != null and npc.brain != null:
			npc.brain.call(&"force_target", local.player_id)


func _on_frame(wall_us: int, physics_us: int, script_us: int, render_us: int, steps: int) -> void:
	if _recording:
		_rows.append(PackedInt32Array([wall_us, physics_us, script_us, render_us, steps]))


func _report(draws: PackedInt32Array, objects: PackedInt32Array, prims: PackedInt32Array, alive: float, game: ZzGame, gpu: PackedFloat64Array, cpu: PackedFloat64Array) -> void:
	var cols: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array(), PackedFloat64Array()]
	for row in _rows:
		for c in 5:
			cols[c].append(float(row[c]) / (1000.0 if c < 4 else 1.0))
	var mean := func(a: PackedFloat64Array) -> float:
		var s := 0.0
		for v in a:
			s += v
		return s / maxf(1.0, a.size())
	var p := func(a: PackedFloat64Array, q: float) -> float:
		var b := a.duplicate()
		b.sort()
		return b[clampi(int(b.size() * q), 0, b.size() - 1)] if b.size() > 0 else 0.0
	var as_f := func(a: PackedInt32Array) -> PackedFloat64Array:
		var out := PackedFloat64Array()
		for v in a:
			out.append(float(v))
		return out
	var wall_mean: float = mean.call(cols[0])
	print("BENCH map=%s zombies=%d alive=%.1f frames=%d fps=%.1f wall_ms=%.2f p50=%.2f p99=%.2f phys_ms=%.2f steps=%.2f script_ms=%.2f render_ms=%.2f gpu_ms=%.2f rcpu_ms=%.2f draws=%.0f objects=%.0f prims_k=%.0f nodes=%d" % [
		game.map.doc.get("id", "?"), _count, alive, _rows.size(), 1000.0 / maxf(0.001, wall_mean), wall_mean,
		p.call(cols[0], 0.5), p.call(cols[0], 0.99), mean.call(cols[1]), mean.call(cols[4]), mean.call(cols[2]), mean.call(cols[3]), mean.call(gpu), mean.call(cpu),
		mean.call(as_f.call(draws)), mean.call(as_f.call(objects)), mean.call(as_f.call(prims)) / 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	_print_perf(game, cols[0], mean.call(cols[1]), mean.call(as_f.call(draws)), p)


## The line tools/perf_budget.sh compares (dot-game/tools): frame percentiles of the measured window, seconds until
## a round is running, peak resident memory, GPU name, and the game's own physics, draw and node numbers.
func _print_perf(game: ZzGame, wall: PackedFloat64Array, phys_ms: float, draws: float, pct: Callable) -> void:
	var rss_kb := 0
	var status := FileAccess.open("/proc/self/status", FileAccess.READ)
	while status != null and not status.eof_reached():
		var line := status.get_line()
		if line.begins_with("VmHWM:"):
			rss_kb = int(line.get_slice(":", 1).strip_edges().get_slice(" ", 0))
	var worst := 0.0
	for v in wall:
		worst = maxf(worst, v)
	var vp := get_viewport().get_visible_rect().size
	print("PERF " + JSON.stringify({
		"map": game.map.doc.get("id", "?"), "zombies": _count, "frames": wall.size(),
		"p50_ms": pct.call(wall, 0.5), "p95_ms": pct.call(wall, 0.95), "p99_ms": pct.call(wall, 0.99), "stall_ms": worst,
		"load_s": _load_s, "rss_mb": rss_kb / 1024.0, "phys_ms": phys_ms, "draws": draws,
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"gpu": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"resolution": "%dx%d" % [vp.x, vp.y], "godot": Engine.get_version_info().get("string", "")}))


