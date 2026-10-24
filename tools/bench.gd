extends "shot.gd"

## A fixed-seed frame benchmark: a solo game on one map, N commons kept alive round the
## survivor (a dead one is replaced), the eyes turning once round per run, every frame timed.
## Prints one BENCH line (wall, physics, script, render, GPU and render-CPU time, draw calls, objects, primitives) so
## runs on the same box compare. `tools/bench.sh --zz-map-ids=zm_abandoned_mall --zombies=56`.

var _count := 56
var _bench_seed := 7
var _measure := 20.0
var _settle := 4.0
var _ring := Vector2(8.0, 40.0)
var _clock := DotMenuFrameClock.new()
var _rows: Array[PackedInt32Array] = []
var _recording := false
## --profile: the game's tick is stepped here part by part (survival_long_run's split) and the
## parts are printed as PROFILE lines, ms per tick over the measured frames.
var _profile := false
var _profiler: Node = null
var _ticks := 0


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
	var local = _client.get("player")
	for player in game.survivors():
		player.health.invulnerable = true
	var stand: Vector3 = _at if _at != Vector3.INF else _default_stand(game)
	local.place_at(stand, float(game.map.spawn("survivors", 0)[1]) if _at == Vector3.INF else 0.0)
	await _seconds_of(1.0)

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
	var total_ms := (_settle + _measure) * 1000.0
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
		_recording = Time.get_ticks_msec() - began >= _settle * 1000.0
		if _recording:
			draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			objects.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
			prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			alive_sum += _alive(game)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	_clock.stop()
	if _profiler != null:
		var parts: Dictionary = _profiler.get(&"_parts")
		for part: String in parts:
			print("PROFILE %-10s %.3f ms/tick" % [part, float(parts[part]) / 1000.0 / maxf(1.0, _ticks)])
		_profiler.free()
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


