extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const StuckMeter := preload("stuck_meter.gd")

## Bot soak on the real game: the map's team of stand-in survivors holds a map for M simulated
## minutes through dot-bot's DotBotSoak, fed by dot-spawn's DotSpawnWatch. Kills, deaths and damage
## come from the game's own signals.
##
## [codeblock]
## ./game.sh soak [map] [minutes]
## godot --headless --path . res://tools/soak.tscn -- --map zz_high_school --bots 4 --minutes 2
## [/codeblock]
##
## Takes the harness's own flags too (--soak-max-stuck-sec and the rest of DotBotSoakConfig).
## Writes .godot/test-logs/soak-<map>.json, prints the SOAK line, exits 1 when the run fails.

const DEFAULT_MAP := &"zz_high_school"
const DEFAULT_MINUTES := 1.0
const TICK_RATE := 64

var _game: ZzGame
var _goals: StuckMeter
var _kills := 0
var _deaths := 0
var _damage := 0.0
var _laid := {}
var _taken := 0
var _last_laid := -1.0
var _kills_with_loot := 0
var _peak_alive := 0
var _spawn_failed := false


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--" + name)
	if at >= 0 and at + 1 < args.size():
		return args[at + 1]
	return fallback


func _run() -> void:
	var map_id := StringName(_arg("map", String(DEFAULT_MAP)))
	var cfg := DotBotSoakConfig.new()
	cfg.minutes = DEFAULT_MINUTES
	cfg.max_object_growth_pct = 40.0
	cfg.apply_cli()
	cfg.minutes = float(_arg("minutes", str(cfg.minutes)))

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(map_id)])
	_game = ZzGame.new()
	_game.name = "World"
	_game.config = config
	_game.tick_rate = TICK_RATE
	_game.authoritative = true
	_game.register_service = false
	_game.next_map_id = map_id
	add_child(_game)
	_game.set_physics_process(false)
	await get_tree().physics_frame

	var doc: Dictionary = _game.catalogue.maps.get(map_id, {}) if _game.catalogue != null else {}
	if doc.is_empty():
		await _release_game()
		_fail("no map %s" % map_id)
		return
	cfg.bots = int(_arg("bots", str(maxi(int(doc.get("survivors", 4)), 1))))
	_game.zombie_killed.connect(_on_killed)
	_game.player_died.connect(func(_id: StringName, _by: StringName, _why: StringName) -> void: _deaths += 1)
	_game.player_hurt.connect(func(_id: StringName, amount: float, _from: Vector3) -> void: _damage += amount)
	for i in range(cfg.bots):
		var player := _game.add_player(StringName("u%d" % (100 + i)), "Bot%d" % i)
		player.is_bot = true
	_game.start()
	_goals = StuckMeter.new(_game)
	if _game.loot != null:
		_game.loot.added.connect(_on_laid)
		_game.loot.removed.connect(func(_id: int, by: StringName) -> void: _taken += 1 if by != &"" else 0)

	var watch := DotSpawnWatch.new()
	watch.rules.enabled = true
	watch.rules.kill_y = -200.0

	var soak := DotBotSoak.new(cfg)
	soak.watch = watch
	soak.movers_fn = _movers
	soak.stats_fn = func() -> Dictionary: return {"kills": _kills, "deaths": _deaths, "damage": _damage}
	soak.object_count_fn = func() -> int: return int(Performance.get_monitor(Performance.OBJECT_COUNT))
	soak.step_fn = func(delta: float) -> void:
		_game.simulate(delta)
		_goals.sample()
		if _game.horde != null and _game.horde.spawner != null:
			_peak_alive = maxi(_peak_alive, _game.horde.spawner.all_npcs().size())

	var delta := 1.0 / float(TICK_RATE)
	while not soak.is_done():
		soak.advance(delta)
		# Yield now and then so deferred frees run.
		if soak.ticks % 32 == 0:
			await get_tree().physics_frame

	var report := soak.finish()
	report["map"] = String(map_id)
	report["bots"] = cfg.bots
	report["loot_laid"] = _laid
	report["loot_taken"] = _taken
	print("SOAKLOOT kills %d (%d with a drop at the body) laid %s taken %d, peak zombies alive %d" % [_kills, _kills_with_loot, _laid, _taken, _peak_alive])
	print("SOAKSTUCK ", _goals.line())
	for kind: StringName in StuckMeter.KINDS:
		print("SOAKCELLS %s %s" % [kind, _goals.worst_cells(kind)])
	# Waves were due (a survival map past its first wave's time) yet no zombie was ever alive.
	var waves_due: bool = str(doc.get("mode", "")) == "survival" and cfg.minutes * 60.0 > _game.config.survival_warmup_seconds + 30.0
	_spawn_failed = waves_due and _peak_alive == 0 and _kills == 0
	if _spawn_failed:
		report["ok"] = false
		print("SOAKFAIL spawn: waves expected on %s but no zombie was ever alive (peak 0, kills 0)" % map_id)
	print(DotBotSoak.summary(report))
	print(DotBotSoak.report_line(report))
	var path := ProjectSettings.globalize_path("res://.godot/test-logs/soak-%s.json" % map_id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if soak.write_report(report, path) != OK:
		push_error("could not write %s" % path)
	await _release_game()
	get_tree().quit(0 if report["ok"] else 1)


func _on_killed(_kind: StringName, _by: StringName, _headshot: bool) -> void:
	_kills += 1
	_kills_with_loot += 1 if is_equal_approx(_last_laid, _game.now()) else 0


func _on_laid(_id: int, kind: StringName, _item: StringName, _at: Vector3) -> void:
	_laid[kind] = int(_laid.get(kind, 0)) + 1
	_last_laid = _game.now()


## Frees the game before quitting: a world still loaded at quit can abort the process.
func _release_game() -> void:
	_game.queue_free()
	for _i in range(3):
		await get_tree().process_frame


## A stand-in has a goal while it holds a fresh path to somewhere further than a post's reach
## (the stuck meter's own rule), so a holder standing at its post is not stuck.
func _movers() -> Array:
	var out: Array = []
	for player in _game.survivors():
		if not player.is_bot or not player.is_alive() or player.watching or player.is_down():
			continue
		out.append({"id": player.player_id, "position": player.feet(), "kind": &"bot", "has_goal": _goals._standin_walks(player)})
	return out


func _fail(why: String) -> void:
	printerr("SOAK setup failed: ", why)
	get_tree().quit(2)
