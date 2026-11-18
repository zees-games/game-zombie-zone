extends "shot.gd"

## A fixed-seed frame benchmark: a solo game on one map, N commons kept alive round the survivor, the eyes turning
## once per run, every frame timed. Prints one BENCH line (wall, physics, script, render, GPU, draws) so runs compare.
## `tools/bench.sh --zz-map-ids=zm_abandoned_mall --zombies=56`.

const _ZombieMove := preload("../npcs/zz_zombie_brain_move.gd")
const _SimHost := preload("../game/zz_sim_host.gd")
const Probes := preload("bench_probes.gd")

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
## --ab-reuse=N (with --profile): every 64 ticks every brain's `path_reuse_thoughts` flips between 0 and N, and
## h.brains/h.bodies are summed per arm, so both arms run in one process on one box (AB lines).
var _ab_reuse := -1
## --ab-native (with --profile): every 64 ticks the horde's crowd grid flips between the script (0) and dot-sim's
## `DotSimCrowdGrid` (1) through `ZzConfig.native_crowd`; h.grid, h.brains and h.bodies are summed per arm (AB lines).
var _ab_native := false
## --crowd-parity (with --profile): every tick the live crowd grid's entries are copied into a fresh script grid and a
## fresh native one, and every zombie's spacing push and two neighbour queries are asked of all three (PARITY line).
var _crowd_parity := false
## --ab-senses (with --profile): every 64 ticks the horde's senses flip between the script (0) and dot-sim's
## `DotSimSenses` (1) through `ZzConfig.native_senses`; h.senses is summed per arm (AB lines).
var _ab_senses := false
## --senses-verify (with --profile): every perception pass runs native and script and counts the NPCs whose
## target or timestamps differ (PARITY senses line); the script's answers are the ones kept.
var _senses_verify := false
## --ab-brains (with --profile): every 64 ticks the zombies' brains flip between the script (0) and dot-sim's
## `DotSimZombieBrains` (1) through `ZzConfig.native_brains`; h.brains is summed per arm (AB lines).
var _ab_brains := false
## --brains-verify (with --profile): every native chase choice, barricade check, nearest survivor and spaced heading is
## also worked out in script and the pairs that differ counted (PARITY brains line); the script's answers are kept.
var _brains_verify := false
var _abb_us := {}
var _abb_ticks := {}
## --ab-pacing (with --profile): every 64 ticks the spawner's think pacing flips between each brain counting its
## own ticks (0) and one native batch calling only the due brains (1) through `ZzConfig.native_pacing`; h.brains
## is summed per arm (AB lines).
var _ab_pacing := false
## --pacing-verify (with --profile): the script pacer runs beside the native one and every answer is compared bit
## for bit (PARITY pacing line).
var _pacing_verify := false
var _abp_us := {}
var _abp_ticks := {}
## --ab-walk (with --profile): every 64 ticks the zombie steer flips between dot-sim's `steer_step` (0, the brain's
## watch read through Object.get) and `steer_walk` (1, the watch passed in); h.brains is summed per arm (AB lines).
var _ab_walk := false
var _abw_us := {}
var _abw_ticks := {}
## --ab-move (with --profile): every 64 ticks the zombie move flips between the script's path step plus `steer_walk`
## (0) and dot-sim's `walk` (1, the path step and the steer in one call); h.brains is summed per arm (AB lines).
var _ab_move := false
var _abm_us := {}
var _abm_ticks := {}
## --ab-decide (with --profile): every 64 ticks the commons' chase choice, barricade check and nearest survivor flip
## between the script (0) and dot-sim's `chase`, `barricade_in_way` and `nearest` (1); h.brains is summed per arm.
var _ab_decide := false
var _abd_us := {}
var _abd_ticks := {}
var _abs_us := {}
var _abs_ticks := {}
## --ab-store (with --profile): every 64 ticks the zombie move flips between dot-sim's by-value `walk`/`steer_walk`
## (0, the turn and watch handed across each call) and the native store's `walk_stored`/`steer_stored`/`face_stored`
## (1); h.brains is summed per 64-tick window and the pairs' difference printed (AB store line).
var _ab_store := false
var _abst_windows := {}
var _parity := {"compared": 0, "differ": 0, "pushes": 0}
var _ab_us := {}
var _ab_ticks := {}
var _ticks := 0
var _load_s := 0.0
## Engine monitors per measured frame: physics-process ms (the scripts' _physics_process), active bodies, pairs, islands.
var _monitors: Array[PackedFloat64Array] = []
## --sim_host=1: the game runs in the client's server process (game/zz_sim_host.gd); the crowd is kept there by
## tools/bench_sim_crowd.gd and this end only draws, so the frame numbers are the client's alone.
var _hosted := false
## Seconds the hosted game may take to appear on this end (its server's boot and the join). 0 waits without end.
var _host_wait_sec := 300.0
## What the measured window recorded, per frame: render counts, GPU/CPU times and the crowd alive.
var _measured := {}


func _ready() -> void:
	_hosted = _SimHost.arg_in(OS.get_cmdline_user_args(), "--sim_host") == "1"
	if _hosted:
		_read_args()
		var at := _SimHost.arg_in(OS.get_cmdline_user_args(), "--at")
		_SimHost.extra_args = PackedStringArray(["--bench_crowd=%d" % _count, "--bench_seed=%d" % _bench_seed,
			"--bench_ring=%s,%s" % [_ring.x, _ring.y]])
		if at != "":
			_SimHost.extra_args.append("--bench_at=%s" % at)
	super()


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zombies="):
			_count = arg.trim_prefix("--zombies=").to_int()
		elif arg.begins_with("--seed="):
			_bench_seed = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--measure="):
			_measure = arg.trim_prefix("--measure=").to_float()
		elif arg == "--profile":
			_profile = true
		elif arg.begins_with("--ab-reuse="):
			_ab_reuse = arg.trim_prefix("--ab-reuse=").to_int()
		elif arg == "--ab-native":
			_ab_native = true
		elif arg == "--ab-senses":
			_ab_senses = true
		elif arg == "--senses-verify":
			_senses_verify = true
		elif arg == "--ab-brains":
			_ab_brains = true
		elif arg == "--brains-verify":
			_brains_verify = true
		elif arg == "--ab-pacing":
			_ab_pacing = true
		elif arg == "--ab-walk":
			_ab_walk = true
			if not ClassDB.class_has_method(&"DotSimZombieBrains", &"steer_walk"):
				push_error("bench: --ab-walk needs a dot-sim build with DotSimZombieBrains.steer_walk")
				get_tree().quit(1)
		elif arg == "--ab-move":
			_ab_move = true
			if not ClassDB.class_has_method(&"DotSimZombieBrains", &"walk"):
				push_error("bench: --ab-move needs a dot-sim build with DotSimZombieBrains.walk")
				get_tree().quit(1)
		elif arg == "--ab-store":
			_ab_store = true
			if not ClassDB.class_has_method(&"DotSimZombieBrains", &"walk_stored"):
				push_error("bench: --ab-store needs a dot-sim build with DotSimZombieBrains.walk_stored")
				get_tree().quit(1)
		elif arg == "--ab-decide":
			_ab_decide = true
			if not ClassDB.class_has_method(&"DotSimZombieBrains", &"chase"):
				push_error("bench: --ab-decide needs a dot-sim build with DotSimZombieBrains.chase")
				get_tree().quit(1)
		elif arg == "--pacing-verify":
			_pacing_verify = true
		elif arg == "--crowd-parity":
			_crowd_parity = true
		elif arg.begins_with("--ring="):
			var r := arg.trim_prefix("--ring=").split(",")
			_ring = Vector2(r[0].to_float(), r[1].to_float())


## The PROFILE, AB and PARITY lines of a --profile run, then the profiler freed.
func _print_profile() -> void:
	var parts: Dictionary = _profiler.get(&"_parts")
	for part: String in parts:
		print("PROFILE %-10s %.3f ms/tick" % [part, float(parts[part]) / 1000.0 / maxf(1.0, _ticks)])
	for arm: int in _ab_ticks:
		print("AB reuse=%d h.brains %.3f h.bodies %.3f ms/tick over %d ticks" % [arm, float(_ab_us[arm].x) / 1000.0 / maxf(1.0, _ab_ticks[arm]),
			float(_ab_us[arm].y) / 1000.0 / maxf(1.0, _ab_ticks[arm]), _ab_ticks[arm]])
	for side: int in _abn_ticks:
		var n := maxf(1.0, _abn_ticks[side]) * 1000.0
		print("AB native=%d h.grid %.3f h.brains %.3f h.bodies %.3f ms/tick over %d ticks" % [side, _abn_us[side].z / n,
			_abn_us[side].x / n, _abn_us[side].y / n, _abn_ticks[side]])
	for side: int in _abs_ticks:
		print("AB senses=%d h.senses %.3f ms/tick over %d ticks" % [side,
			float(_abs_us[side]) / 1000.0 / maxf(1.0, _abs_ticks[side]), _abs_ticks[side]])
	if _senses_verify:
		var senses: DotNpcSenses = (_client.get("game") as ZzGame).horde.senses
		print("PARITY senses decided=%d mismatches=%d checks=%d casts=%d native=%s" % [senses.native_decided,
			senses.native_mismatches, senses.sight_checks, senses.los_casts, ClassDB.class_exists(&"DotSimSenses")])
	for side: int in _abb_ticks:
		print("AB brains=%d h.brains %.3f ms/tick over %d ticks" % [side,
			float(_abb_us[side]) / 1000.0 / maxf(1.0, _abb_ticks[side]), _abb_ticks[side]])
	if _brains_verify:
		var horde: Node = (_client.get("game") as ZzGame).horde
		print("PARITY brains decided=%d mismatches=%d native=%s" % [horde.get(&"brains_decided"),
			horde.get(&"brains_mismatches"), ClassDB.class_exists(&"DotSimZombieBrains")])
	for side: int in _abp_ticks:
		print("AB pacing=%d h.brains %.3f ms/tick over %d ticks" % [side,
			float(_abp_us[side]) / 1000.0 / maxf(1.0, _abp_ticks[side]), _abp_ticks[side]])
	for side: int in _abw_ticks:
		print("AB walk=%d h.brains %.3f ms/tick over %d ticks" % [side,
			float(_abw_us[side]) / 1000.0 / maxf(1.0, _abw_ticks[side]), _abw_ticks[side]])
	for side: int in _abm_ticks:
		print("AB move=%d h.brains %.3f ms/tick over %d ticks" % [side,
			float(_abm_us[side]) / 1000.0 / maxf(1.0, _abm_ticks[side]), _abm_ticks[side]])
	for side: int in _abd_ticks:
		print("AB decide=%d h.brains %.3f ms/tick over %d ticks" % [side,
			float(_abd_us[side]) / 1000.0 / maxf(1.0, _abd_ticks[side]), _abd_ticks[side]])
	if _ab_store:
		print(_paired_line("store", "h.brains", _abst_windows))
	if _pacing_verify:
		var sp: Node = (_client.get("game") as ZzGame).horde.spawner
		print("PARITY pacing checked=%d mismatches=%d native=%s" % [sp.get(&"pacing_checked"),
			sp.get(&"pacing_mismatches"), ClassDB.class_exists(&"DotSimThinkPacer")])
	if _crowd_parity:
		print("PARITY crowd compared=%d differ=%d pushes=%d" % [_parity["compared"], _parity["differ"], _parity["pushes"]])
	_profiler.free()


## The ticks and engine monitors, averaged over the measured frames.
func _print_monitors(game: ZzGame) -> void:
	var sums := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	for m in _monitors:
		for i in 5:
			sums[i] += m[i] / maxf(1.0, _monitors.size())
	print("TICKS game_tick_ms_per_frame=%.2f (of phys_ms; the rest is the engine step and other nodes)" % (float(game.tick_us_total - _tick_us_at_warm) / 1000.0 / maxf(1.0, _monitors.size())))
	print("MONITORS physics_process_ms=%.2f (the frame's slowest step) active_3d=%.1f pairs=%.1f islands=%.1f horde_frame_ms=%.2f" % [sums[0], sums[1], sums[2], sums[3], sums[4]])


func _run() -> void:
	_read_args()
	var game: ZzGame = await _wait_for_game()
	if game == null:
		get_tree().quit(1)
		return
	await _until_a_round(game)
	var waited := 0.0
	while not game.map.world_drawn and str(game.map.doc.get("world", "")) != "" and waited < 400.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	print("BENCH world_drawn=%s after %.0f s" % [game.map.world_drawn, waited])
	_load_s = Time.get_ticks_msec() / 1000.0
	var local = _client.get("player")
	var stand := Vector3.ZERO
	if _hosted:
		# The server half (tools/bench_sim_crowd.gd) makes everyone unkillable and puts the survivor at the stand.
		await _seconds_of(2.0)
	else:
		for player in game.survivors():
			player.health.invulnerable = true
		stand = _at if _at != Vector3.INF else _default_stand(game)
		local.place_at(stand, float(game.map.spawn("survivors", 0)[1]) if _at == Vector3.INF else 0.0)
	await _seconds_of(1.0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--without="):
			_without(arg.trim_prefix("--without=").split(","))
	await _seconds_of(1.0)
	for v in get_tree().root.find_children("*", "DotMapVisibility", true, false):
		print("VIS ", v.call(&"describe"))

	if "--micro" in OS.get_cmdline_user_args():
		_micro(game)
		get_tree().quit(0)
		return
	if "--physprobe" in OS.get_cmdline_user_args():
		Probes.phys_probe(local)
		get_tree().quit(0)
		return
	if _profile and _hosted:
		push_error("bench: --profile steps the in-process world; it does not combine with --sim_host=1")
		get_tree().quit(1)
		return
	if _profile:
		_profiler = (load("res://tools/survival_long_run.gd") as GDScript).new()
		_profiler.set(&"_game", game)
		game.external_tick = true
	await _measure_frames(game, local, stand)
	if _profiler != null:
		_print_profile()
	_print_monitors(game)
	if "--census" in OS.get_cmdline_user_args():
		_census()
	if "--bodyprobe" in OS.get_cmdline_user_args():
		Probes.body_probe(game, local)
	_report_measured(game)
	_save_last_frame()
	get_tree().quit(0)


## The game the client built; a hosted client builds it only once its server is up and joined.
## Null (with the error pushed) when it never came or the sim host did not start.
func _wait_for_game() -> ZzGame:
	var game: ZzGame = _client.get("game")
	var t0 := Time.get_ticks_msec()
	while game == null:
		if _host_wait_sec > 0.0 and Time.get_ticks_msec() - t0 > int(_host_wait_sec * 1000.0):
			push_error("bench: no game after %.0f s" % _host_wait_sec)
			return null
		await get_tree().process_frame
		game = _client.get("game")
	if _hosted and _client.get("_sim_host") == null:
		push_error("bench: --sim_host=1 but the sim host did not start (see user://logs/sim_server.log)")
		return null
	return game


## The warm-up and measured window: the survivor turns a full circle while frames are recorded
## into [member _measured]; the frame clock stops at the end.
func _measure_frames(game: ZzGame, local, stand: Vector3) -> void:
	var gpu := PackedFloat64Array()
	var cpu := PackedFloat64Array()
	var draws := PackedInt32Array()
	var objects := PackedInt32Array()
	var prims := PackedInt32Array()
	var alive_sum := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = _bench_seed
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_clock.on_frame = _on_frame
	_clock.start(get_tree())
	var start_yaw: float = local.controller.state.yaw
	var began := Time.get_ticks_msec()
	var total_ms := (_warm + _measure) * 1000.0
	while Time.get_ticks_msec() - began < total_ms:
		if not _hosted:
			_keep_crowd(game, local, stand, rng)
		var t := float(Time.get_ticks_msec() - began) / total_ms
		local.controller.state.yaw = start_yaw + 360.0 * t
		local.controller.state.pitch = -4.0
		if local.sampler != null:
			local.sampler.look_at_angles(local.controller.state.yaw, -4.0)
		await get_tree().process_frame
		var was_recording := _recording
		_recording = Time.get_ticks_msec() - began >= _warm * 1000.0
		if _recording and not was_recording:
			_tick_us_at_warm = game.tick_us_total
		if _recording:
			alive_sum += _record_frame(game, vp, draws, objects, prims, gpu, cpu)
	_clock.stop()
	_measured = {"draws": draws, "objects": objects, "prims": prims, "gpu": gpu, "cpu": cpu, "alive_sum": alive_sum}


## The report over what [method _measure_frames] recorded.
func _report_measured(game: ZzGame) -> void:
	var m := _measured
	var draws: PackedInt32Array = m.draws
	_report(draws, m.objects, m.prims, float(m.alive_sum) / maxf(1.0, draws.size()), game, m.gpu, m.cpu)


## One measured frame's render counts, physics monitors and GPU/CPU times; returns the crowd alive.
func _record_frame(game: ZzGame, vp: RID, draws: PackedInt32Array, objects: PackedInt32Array, prims: PackedInt32Array, gpu: PackedFloat64Array, cpu: PackedFloat64Array) -> int:
	var alive := 0
	draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	objects.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	alive += _alive(game)
	_monitors.append(PackedFloat64Array([Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT), float(game.horde_frame_us) / 1000.0]))
	gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	return alive


## The last frame, to look at: the numbers say nothing about what a crowd detail level looks like.
func _save_last_frame() -> void:
	var path := ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	# Headless has no image: the save errored and the quit after it never ran, so a bench held its slot until the timeout.
	var shot := get_viewport().get_texture().get_image()
	print("saved %s: %s" % [_out, error_string(shot.save_png(path))] if shot != null else "no image (headless)")


func _micro(game: ZzGame) -> void:
	var g := game
	var n := 200
	var t0 := Time.get_ticks_usec()
	for i in n:
		g.bots.drive(1.0 / 60.0)
	print("MICRO bots.drive %.1f us/call" % [float(Time.get_ticks_usec() - t0) / n])
	var survs = g.survivors()
	print("MICRO survivors %d" % survs.size())
	for pl in survs:
		var st = pl.controller.state
		var cm = pl.controller.current_command
		print("MICRO motor bot=%s up=%s grounded=%s vel=%s move=%s btn=%s prevbtn=%s yawdiff=%s crouch=%s stam=%s mods=%d using=%s" % [pl.is_bot, pl.is_up(), st.is_grounded(), st.velocity, cm.move if cm else "-", cm.buttons if cm else "-", st.previous_buttons, (cm.yaw - st.yaw) if cm else "-", st.crouch_fraction, st.stamina, st.modifiers.size(), pl.using])
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
		g._carry_update()
	print("MICRO carry_update %.1f us/call" % [float(Time.get_ticks_usec() - t0) / n])
	t0 = Time.get_ticks_usec()
	for i in n:
		for pl in survs:
			var _c := g.weapon_command_for(pl)
	print("MICRO weapon_command_for %.1f us/player" % [float(Time.get_ticks_usec() - t0) / n / survs.size()])
	t0 = Time.get_ticks_usec()
	for i in n:
		for pl in survs:
			var _o = pl.weapons.simulate_tick(g.weapon_command_for(pl), 1000 + i)
	print("MICRO weapons.simulate_tick %.1f us/player" % [float(Time.get_ticks_usec() - t0) / n / survs.size()])
	for pl in survs:
		var cm := g.weapon_command_for(pl)
		var sl = pl.weapons.arsenal.current()
		print("MICRO idle buttons=%d slot=%d idle=%s needs_ctx=%s beh=%s" % [cm.buttons, cm.slot, pl.weapons.arsenal.is_idle_for(cm, pl.weapons._previous_command), sl.behaviour.tick_needs_context() if sl else "-", sl.behaviour.get_script().resource_path.get_file() if sl else "-"])
	t0 = Time.get_ticks_usec()
	for i in n:
		for pl in survs:
			g._advance_hands(pl, 1.0 / 60.0)
	print("MICRO advance_hands %.1f us/player" % [float(Time.get_ticks_usec() - t0) / n / survs.size()])
	t0 = Time.get_ticks_usec()
	for i in n:
		g.combat.tick(g._tick, 1.0 / 60.0)
	print("MICRO combat.tick %.1f us" % [float(Time.get_ticks_usec() - t0) / n])


## --without=shadows,decals,multimesh,lamps,ranged: turns a kind of thing off before measuring, to see what its frames cost.
func _without(kinds: PackedStringArray) -> void:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is RigidBody3D and "rigid_off" in kinds:
			(n as RigidBody3D).freeze = true
		if n is CollisionShape3D and "far_shapes_off" in kinds and n.get_parent() is StaticBody3D:
			(n as CollisionShape3D).disabled = true
		if n is Light3D and "shadows" in kinds:
			(n as Light3D).shadow_enabled = false
		if n is DirectionalLight3D and n.shadow_enabled:
			var sun := n as DirectionalLight3D
			print("SUN mode=%d dist=%.0f blend=%s split=%.2f,%.2f,%.2f blur=%.1f" % [sun.directional_shadow_mode, sun.directional_shadow_max_distance, sun.directional_shadow_blend_splits, sun.directional_shadow_split_1, sun.directional_shadow_split_2, sun.directional_shadow_split_3, sun.shadow_blur])
			if "splits1" in kinds:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			if "splits2" in kinds:
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			if "dist30" in kinds:
				sun.directional_shadow_max_distance = 30.0
			if "dist30_1" in kinds:
				sun.directional_shadow_max_distance = 30.0
				sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		if n is Light3D and "lamps" in kinds and not n is DirectionalLight3D:
			(n as Light3D).visible = false
		if (n is GPUParticles3D or n is CPUParticles3D) and "particles" in kinds:
			(n as Node3D).visible = false
		if n is FogVolume and "fog" in kinds:
			(n as Node3D).visible = false
		if n is Decal and "decals" in kinds:
			(n as Decal).visible = false
		if n is MultiMeshInstance3D and "multimesh" in kinds:
			(n as MultiMeshInstance3D).visible = false
		if n is MeshInstance3D and (("props_noshadow" in kinds) or ("props_small" in kinds)):
			var anc := n.get_parent()
			while anc != null and not (anc.name == &"Props" or anc.name == &"UnseenProps"):
				anc = anc.get_parent()
			if anc != null:
				var box := (n as MeshInstance3D).get_aabb().size * (n as MeshInstance3D).global_transform.basis.get_scale()
				if "props_noshadow" in kinds or maxf(box.x, maxf(box.y, box.z)) < 1.2:
					(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if n is GeometryInstance3D and "mesh_shadows" in kinds:
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for v in get_tree().root.find_children("*", "DotMapVisibility", true, false):
		if "vis_noshadow" in kinds:
			v.set(&"shadows", 0)
			v.set(&"_dirty", true)
	if "splits2" in kinds:
		pass
	var lod = _client.get("world_view").lod
	if "zombie_anim" in kinds:
		lod.near = 0.0
		lod.far = 0.0
	if "zombie_draw" in kinds:
		lod.draw_until = 0.5
	if "fog" in kinds:
		for e in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			(e as WorldEnvironment).environment.fog_enabled = false
			(e as WorldEnvironment).environment.volumetric_fog_enabled = false
	if "env" in kinds:
		for e in get_tree().root.find_children("*", "WorldEnvironment", true, false):
			var env: Environment = (e as WorldEnvironment).environment
			env.glow_enabled = false
			env.fog_enabled = false
			env.adjustment_enabled = false


## --census: what the tree holds that is drawn, by kind, to find which part of a map costs the draws.
func _census() -> void:
	var c := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MultiMeshInstance3D:
			c["multimesh"] = int(c.get("multimesh", 0)) + 1
			c["multimesh_instances"] = int(c.get("multimesh_instances", 0)) + (n as MultiMeshInstance3D).multimesh.visible_instance_count
		elif n is MeshInstance3D:
			var m := n as MeshInstance3D
			var k := "mesh"
			c[k] = int(c.get(k, 0)) + 1
			var surfaces := m.mesh.get_surface_count() if m.mesh != null else 0
			var holder := m.get_parent().name if m.get_parent() != null else &""
			var hk := "in_" + String(holder).rstrip("0123456789_")
			c[hk] = int(c.get(hk, 0)) + 1
			c[hk + "_surf"] = int(c.get(hk + "_surf", 0)) + surfaces
			var tris := _triangles(m.mesh)
			c[hk + "_tris"] = int(c.get(hk + "_tris", 0)) + tris
			c["tris_total"] = int(c.get("tris_total", 0)) + tris
			if m.visibility_range_end > 0.0:
				c["tris_ranged"] = int(c.get("tris_ranged", 0)) + tris
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				c[hk + "_shadow"] = int(c.get(hk + "_shadow", 0)) + 1
			c["mesh_surfaces"] = int(c.get("mesh_surfaces", 0)) + surfaces
			if m.visibility_range_end > 0.0:
				c["mesh_ranged"] = int(c.get("mesh_ranged", 0)) + 1
			if m.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				c["mesh_shadow"] = int(c.get("mesh_shadow", 0)) + 1
		elif n is Light3D:
			var kind := "light_" + n.get_class()
			c[kind] = int(c.get(kind, 0)) + 1
			if (n as Light3D).visible:
				c[kind + "_on"] = int(c.get(kind + "_on", 0)) + 1
			if (n as Light3D).shadow_enabled:
				c[kind + "_shadow"] = int(c.get(kind + "_shadow", 0)) + 1
		elif n is GPUParticles3D or n is CPUParticles3D or n is Sprite3D or n is Decal or n is AnimatedSprite3D or n is Label3D or n is GeometryInstance3D:
			c[n.get_class()] = int(c.get(n.get_class(), 0)) + 1
	print("CENSUS ", c)
	var tops: Array = c.keys().filter(func(k): return String(k).ends_with("_tris"))
	tops.sort_custom(func(a, b): return int(c[a]) > int(c[b]))
	for k in tops.slice(0, 12):
		print("TRIS %-40s %d" % [k, c[k]])
	print("TRIS total %d ranged %d" % [int(c.get("tris_total", 0)), int(c.get("tris_ranged", 0))])


var _tri_cache := {}


func _triangles(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	if _tri_cache.has(mesh):
		return _tri_cache[mesh]
	var n := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var idx = arrays[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	_tri_cache[mesh] = n
	return n


var _tick_us_at_warm := 0


func _physics_process(_delta: float) -> void:
	if _profiler == null:
		return
	if not _recording:
		(_profiler.get(&"_parts") as Dictionary).clear()
		_ticks = 0
	var arm := (_ab_reuse if ((Engine.get_physics_frames() >> 6) & 1) == 1 else 0) if _ab_reuse >= 0 else -1
	if arm >= 0:
		for npc: DotNpcInstance in (_client.get("game") as ZzGame).horde.spawner.all_npcs():
			if npc.brain != null:
				npc.brain.set(&"path_reuse_thoughts", arm)
	var native_arm := ((Engine.get_physics_frames() >> 6) & 1) if _ab_native else -1
	if native_arm >= 0:
		(_client.get("game") as ZzGame).horde.config.native_crowd = native_arm == 1
	var senses_arm := ((Engine.get_physics_frames() >> 6) & 1) if _ab_senses else -1
	if senses_arm >= 0:
		(_client.get("game") as ZzGame).horde.config.native_senses = senses_arm == 1
	if _senses_verify:
		(_client.get("game") as ZzGame).horde.senses.native_verify = true
	var brains_arm := ((Engine.get_physics_frames() >> 6) & 1) if _ab_brains else -1
	if brains_arm >= 0:
		(_client.get("game") as ZzGame).horde.config.native_brains = brains_arm == 1
	if _brains_verify:
		(_client.get("game") as ZzGame).horde.brains_verify = true
	var pacing_arm := ((Engine.get_physics_frames() >> 6) & 1) if _ab_pacing else -1
	if pacing_arm >= 0:
		(_client.get("game") as ZzGame).horde.config.native_pacing = pacing_arm == 1
	if _pacing_verify:
		(_client.get("game") as ZzGame).horde.config.native_pacing = true
		(_client.get("game") as ZzGame).horde.spawner.set(&"pacing_verify", true)
	var walk_arm := ((Engine.get_physics_frames() >> 6) & 1) if _ab_walk else -1
	if walk_arm >= 0:
		_ZombieMove._steer_walks = walk_arm
	var move_arm := ((Engine.get_physics_frames() >> 6) & 1) if _ab_move else -1
	if move_arm >= 0:
		_ZombieMove._walks = move_arm
	var decide_arm := ((Engine.get_physics_frames() >> 6) & 1) if _ab_decide else -1
	if decide_arm >= 0:
		_ZombieMove._decides = decide_arm
	var store_window := Engine.get_physics_frames() >> 6
	if _ab_store:
		_ZombieMove._stores = store_window & 1
	_profiler.call(&"_profiled_step")
	_ticks += 1
	if senses_arm >= 0 and _recording:
		_abs_us[senses_arm] = int(_abs_us.get(senses_arm, 0)) + int((_profiler.get(&"_tick_parts") as Dictionary).get("h.senses", 0))
		_abs_ticks[senses_arm] = int(_abs_ticks.get(senses_arm, 0)) + 1
	if brains_arm >= 0 and _recording:
		_abb_us[brains_arm] = int(_abb_us.get(brains_arm, 0)) + int((_profiler.get(&"_tick_parts") as Dictionary).get("h.brains", 0))
		_abb_ticks[brains_arm] = int(_abb_ticks.get(brains_arm, 0)) + 1
	if walk_arm >= 0 and _recording:
		_abw_us[walk_arm] = int(_abw_us.get(walk_arm, 0)) + int((_profiler.get(&"_tick_parts") as Dictionary).get("h.brains", 0))
		_abw_ticks[walk_arm] = int(_abw_ticks.get(walk_arm, 0)) + 1
	if move_arm >= 0 and _recording:
		_abm_us[move_arm] = int(_abm_us.get(move_arm, 0)) + int((_profiler.get(&"_tick_parts") as Dictionary).get("h.brains", 0))
		_abm_ticks[move_arm] = int(_abm_ticks.get(move_arm, 0)) + 1
	if _ab_store and _recording:
		_abst_windows[store_window] = _abst_windows.get(store_window, Vector2.ZERO) + Vector2(
			float((_profiler.get(&"_tick_parts") as Dictionary).get("h.brains", 0)), 1.0)
	if decide_arm >= 0 and _recording:
		_abd_us[decide_arm] = int(_abd_us.get(decide_arm, 0)) + int((_profiler.get(&"_tick_parts") as Dictionary).get("h.brains", 0))
		_abd_ticks[decide_arm] = int(_abd_ticks.get(decide_arm, 0)) + 1
	if pacing_arm >= 0 and _recording:
		_abp_us[pacing_arm] = int(_abp_us.get(pacing_arm, 0)) + int((_profiler.get(&"_tick_parts") as Dictionary).get("h.brains", 0))
		_abp_ticks[pacing_arm] = int(_abp_ticks.get(pacing_arm, 0)) + 1
	if native_arm >= 0 and _recording:
		var parts: Dictionary = _profiler.get(&"_tick_parts")
		_abn_us[native_arm] = _abn_us.get(native_arm, Vector3.ZERO) + Vector3(float(parts.get("h.brains", 0)),
			float(parts.get("h.bodies", 0)), float(parts.get("h.grid", 0)))
		_abn_ticks[native_arm] = int(_abn_ticks.get(native_arm, 0)) + 1
	if _crowd_parity and _recording:
		_check_crowd((_client.get("game") as ZzGame).horde)
	if arm >= 0 and _recording:
		var tick_parts: Dictionary = _profiler.get(&"_tick_parts")
		_ab_us[arm] = _ab_us.get(arm, Vector2i.ZERO) + Vector2i(int(tick_parts.get("h.brains", 0)), int(tick_parts.get("h.bodies", 0)))
		_ab_ticks[arm] = int(_ab_ticks.get(arm, 0)) + 1


var _abn_us := {}
var _abn_ticks := {}


## A paired A/B over 64-tick windows: window `w` ran arm `w & 1`, so each odd window and the one before it are a pair
## under (nearly) the same load and game state. Each arm's mean, then the pairs' mean difference (arm 1 minus arm 0)
## and its standard error; a gain inside about two errors is noise. [param windows] maps a window to
## Vector2(summed microseconds, ticks).
static func _paired_line(name: String, part: String, windows: Dictionary) -> String:
	var arm_sum: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
	var diffs := PackedFloat64Array()
	for w: int in windows:
		var cur: Vector2 = windows[w]
		arm_sum[w & 1] += cur
		if w & 1 == 1 and windows.has(w - 1) and cur.y > 0.0 and windows[w - 1].y > 0.0:
			diffs.append((cur.x / cur.y - windows[w - 1].x / windows[w - 1].y) / 1000.0)
	var mean := 0.0
	for d in diffs:
		mean += d
	mean /= maxf(1.0, diffs.size())
	var sq := 0.0
	for d in diffs:
		sq += (d - mean) * (d - mean)
	var se := sqrt(sq / maxf(1.0, diffs.size() - 1)) / sqrt(maxf(1.0, diffs.size()))
	return "AB %s=0 %s %.3f =1 %.3f ms/tick over %d+%d ticks; paired diff %+.3f +- %.3f ms (%d pairs)" % [name, part,
		arm_sum[0].x / 1000.0 / maxf(1.0, arm_sum[0].y), arm_sum[1].x / 1000.0 / maxf(1.0, arm_sum[1].y),
		int(arm_sum[0].y), int(arm_sum[1].y), mean, se, diffs.size()]


## The live grid's entries, in its order, into a fresh script grid and a fresh native grid; every entry's push
## (as a brain asks it, from a little off where it was added) and its 6 m and 32 m neighbours from all three.
func _check_crowd(horde: Object) -> void:
	if not ClassDB.class_exists(&"DotSimCrowdGrid"):
		return
	var live: Variant = horde.get(&"crowd")
	var script_grid := DotNpcAiCrowdGrid.new(4.0)
	var native: Object = ClassDB.instantiate(&"DotSimCrowdGrid")
	native.call(&"setup", 4.0)
	var n: int = live.size()
	for i in n:
		var _a := script_grid.add(live.id_of(i), live.position_of(i))
		native.call(&"add", live.id_of(i), live.position_of(i))
	# One scratch per answer: the script grid fills and returns the one it is given.
	var scratch := PackedInt32Array()
	var s6 := PackedInt32Array()
	var s32 := PackedInt32Array()
	for i in n:
		var at: Vector3 = live.position_of(i)
		if not at.is_finite():
			continue
		var from := at + Vector3(0.05 * sin(i), 0.0, 0.05 * cos(i))
		var right := Vector3(cos(i * 0.7), 0.0, sin(i * 0.7))
		var id: int = live.id_of(i)
		var a := script_grid.separation(script_grid.index_of(id), from, 1.1, 2.2, right)
		var b: Vector3 = native.call(&"separation_of", id, from, 1.1, 2.2, right)
		var c: Vector3 = live.separation(live.index_of(id), from, 1.1, 2.2, right)
		var near6 := script_grid.near(at, 6.0, s6)
		var near32 := script_grid.near(at, 32.0, s32)
		var same: bool = a == b and a == c and near6 == native.call(&"near", at, 6.0, scratch) \
			and near32 == native.call(&"near", at, 32.0, scratch) and near32 == PackedInt32Array(live.near(at, 32.0, scratch))
		_parity["compared"] += 1
		_parity["pushes"] += 1 if a != Vector3.ZERO else 0
		_parity["differ"] += 0 if same else 1


func _alive(game: ZzGame) -> int:
	if _hosted:
		return (_client.get("bridge") as Object).call(&"zombie_count")
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
	print("BENCH map=%s zombies=%d alive=%.1f frames=%d fps=%.1f wall_ms=%.2f p50=%.2f p99=%.2f phys_ms=%.2f steps=%.2f script_ms=%.2f render_ms=%.2f gpu_ms=%.2f rcpu_ms=%.2f draws=%.0f objects=%.0f prims_k=%.0f nodes=%d sim_host=%d" % [
		game.map.doc.get("id", "?"), _count, alive, _rows.size(), 1000.0 / maxf(0.001, wall_mean), wall_mean,
		p.call(cols[0], 0.5), p.call(cols[0], 0.99), mean.call(cols[1]), mean.call(cols[4]), mean.call(cols[2]), mean.call(cols[3]), mean.call(gpu), mean.call(cpu),
		mean.call(as_f.call(draws)), mean.call(as_f.call(objects)), mean.call(as_f.call(prims)) / 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), 1 if _hosted else 0])
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
