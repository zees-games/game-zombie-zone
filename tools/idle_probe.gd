extends Node

## Plays a survival map with its stand-ins and reports each one that stood still: where, for how
## long, and what its brain held (goal, pick, carried box, using). `godot --headless --path .
## res://tools/idle_probe.tscn -- --map=zz_lot [--seconds=120] [--idle=10] [--set=k=v]`

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")

const TICK := 1.0 / 64.0

var _map := &"zz_lot"
var _seconds := 120.0
var _idle := 10.0
var _sets: Dictionary = {}
## --drop=S: every S seconds a box falls 2 to 7 m from a random stand-in.
var _drop := 0.0
var _rng := RandomNumberGenerator.new()
var _drop_seed := 1
## --trace=u102: prints that stand-in's goal, pick, reach and last command every second.
var _trace := ""


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):
			_map = StringName(arg.trim_prefix("--map="))
		elif arg.begins_with("--seconds="):
			_seconds = arg.trim_prefix("--seconds=").to_float()
		elif arg.begins_with("--idle="):
			_idle = arg.trim_prefix("--idle=").to_float()
		elif arg.begins_with("--drop="):
			_drop = arg.trim_prefix("--drop=").to_float()
		elif arg.begins_with("--trace="):
			_trace = arg.trim_prefix("--trace=")
		elif arg.begins_with("--set="):
			var pair := arg.trim_prefix("--set=").split("=")
			_sets[pair[0]] = pair[1]

	_rng.seed = _drop_seed
	_run.call_deferred()


func _run() -> void:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(_map)])
	config.survival_style = 0

	for key: String in _sets:
		var was: Variant = config.get(key)
		config.set(key, type_convert(_sets[key], typeof(was)))

	var game := ZzGame.new()
	game.name = "World"
	game.config = config
	game.tick_rate = 64
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	game.next_map_id = _map
	var doc: Dictionary = game.catalogue.maps.get(_map, {})
	var team := maxi(int(doc.get("survivors", 4)), 1)

	for i in team:
		var player = game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.is_bot = true

	game.start()
	var anchors := {}
	var reported := {}
	var t := 0.0
	var next := 0.0
	var idle_total := 0.0
	var samples := 0
	var next_drop := 5.0

	while t < _seconds:
		for i in 32:
			game.simulate(TICK)

		t += 32.0 * TICK
		await get_tree().physics_frame

		if _drop > 0.0 and t >= next_drop:
			next_drop = t + _drop
			var ups: Array = game.survivors().filter(func(p) -> bool: return p.is_bot and p.is_up())
			if not ups.is_empty():
				var who = ups[_rng.randi() % ups.size()]
				var angle := _rng.randf() * TAU
				var _id: int = game.boxes.drop(game.boxes.types.keys()[0], who.feet() + Vector3(cos(angle), 0.0, sin(angle)) * _rng.randf_range(2.0, 7.0))

		if t < next:
			continue

		next = t + 1.0

		if _trace != "":
			_print_trace(game, t)

		for player in game.survivors():
			if not player.is_bot or not player.is_alive():
				continue

			var id: StringName = player.player_id
			var here: Vector3 = player.feet()
			var a: Dictionary = anchors.get(id, {})

			if a.is_empty() or here.distance_to(a["at"]) > 0.75 or not player.is_up():
				anchors[id] = {"at": here, "since": t}
				continue

			samples += 1
			var still := t - float(a["since"])

			if still < _idle:
				continue

			idle_total += 1.0
			var key := "%s@%d" % [id, int(a["since"])]

			if reported.has(key):
				continue

			reported[key] = true
			var memory: Dictionary = game.bots._memory(player)
			var near_zombies := 0
			if game.horde != null:
				for z: DotNpcInstance in game.horde.spawner.all_npcs():
					if (z.position() as Vector3).distance_to(here) < 20.0:
						near_zombies += 1
			var pick := int(memory.get("pick", -1))
			if pick >= 0 and game.loot.entries.has(pick):
				var spot: Vector3 = game.loot.position_of(pick)
				print("  PICK %d %s at=%s eye_gap=%.2f reach=%.2f clear=%s dot=%.3f looked_at=%d actions=%d kind=%s" % [pick, game.loot.entries[pick]["item"], spot.snapped(Vector3.ONE * 0.1),
					player.eye_position().distance_to(spot), game.config.use_reach, game.clear_between(player.eye_position(), spot + Vector3(0.0, 0.35, 0.0)), (spot + Vector3(0.0, 0.25, 0.0) - player.eye_position()).normalized().dot(player.aim_direction()), game.loot.looked_at(player.eye_position(), player.aim_direction(), game.config.use_reach), player.actions, game.loot.kind_of(pick)])
			print("IDLE %s t=%.0f still=%.0fs at=%s goal=%s pick=%s carried=%s using=%s pts=%d zombies20=%d hold=%s path=%d" % [
				id, t, still, here.snapped(Vector3.ONE * 0.1), memory["goal"], memory.get("pick"), player.carried, player.using,
				player.points, near_zombies, game.bots._hold_of(player).snapped(Vector3.ONE * 0.1), (memory["path"] as PackedVector3Array).size()])

	print("PROBE %s team=%d seconds=%.0f idle_bot_seconds=%.0f" % [_map, team, t, idle_total])
	get_tree().quit(0)


func _print_trace(game, t: float) -> void:
	for player in game.survivors():
		if String(player.player_id) != _trace:
			continue

		var memory: Dictionary = game.bots._memory(player)
		var pick := int(memory.get("pick", -1))
		var spot := Vector3.INF
		var kind := &""

		if pick >= 0 and game.loot.entries.has(pick):
			spot = game.loot.position_of(pick)
			kind = game.loot.kind_of(pick)

		var last = memory.get("last_command")
		print("TRACE t=%.0f at=%s pick=%d kind=%s spot=%s eye_gap=%.2f using=%s carried=%s actions=%d move=%s pts=%d" % [t, player.feet().snapped(Vector3.ONE * 0.1), pick, kind,
			spot.snapped(Vector3.ONE * 0.1), player.eye_position().distance_to(spot) if spot != Vector3.INF else -1.0, player.using, player.carried, player.actions,
			(last as DotFpsCommand).move.snapped(Vector2.ONE * 0.1) if last != null else Vector2.ZERO, player.points])
