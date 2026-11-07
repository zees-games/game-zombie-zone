extends DotGameCheckSuite

## ZzConfig through DotGameConfigBinder: fields, cvars, strict refusal, the diff, yml defaults and the workbench round trip.
##
## [codeblock]
## godot --headless --path . res://examples/headless_config.tscn
## [/codeblock]

const ZzConfig := preload("../game/zz_config.gd")
const ROOT := "user://zz_cfgtest"
const GAME := "game-zombie-zone"
const ZzTurrets := preload("../game/zz_turrets.gd")
const ZzHazards := preload("../game/zz_hazards.gd")


## Stands in for the game: ZzTurrets reads only its `config`.
class FakeGame:
	var config = null
const CHECKS := 53


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _run() -> void:
	if OS.get_cmdline_user_args().has("--probe"):
		_probe()
		return
	print("game-zombie-zone: config binder")
	var config := ZzConfig.new()
	var binder := ZzConfig.make_binder(config)
	binder.strict = true
	_check(binder.load_layers().ok, "defaults load")
	_check(binder.diff().is_empty(), "no diff at the code defaults")
	var keys := PackedStringArray()
	for e: Dictionary in binder.schema():
		keys.append(e["key"])
	for k in ["waves", "wave_size", "respawn_base_seconds", "box_drop_common", "defib_range", "defib_price", "defib_hear_range", "down_attack", "start_points", "difficulty"]:
		_check(keys.has(k), "%s is exposed" % k)

	for k in ["trader_setup", "trader_grace", "trader_breather", "trader_round", "trader_closed_message", "grace_maps", "escape_grace_seconds", "grace_hud"]:
		_check(keys.has(k), "%s is exposed (a zz_%s cvar, a game.yml key, a workbench row)" % [k, k])
	_check(config.escape_grace_seconds == 30.0 and config.grace_maps == 1 and config.grace_hud == 1 and config.trader_round == -1
		and config.trader_closed_message == "Trader closed: round in progress", "the grace and trader window defaults")

	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	console.set_cvar("zz_waves", "7")
	_check(config.waves == 7 and binder.source_of("waves") == "cvar", "a cvar writes the field")
	_check(binder.diff_yaml().contains("waves: 7"), "the diff names the edit")
	_check(config.gore_level == 2 and config.gore_max_gibs == 24 and config.gore_max_wounds == 48 and config.attack_anim == 0 and keys.has("attack_anim"), "gore and attack_anim defaults to flying limbs, 24 gibs, 48 wound marks")
	console.set_cvar("zz_gore_level", "0")
	_check(config.gore_level == 0 and keys.has("gore_max_gibs"), "zz_gore_level is a cvar on the config and gore_max_gibs is exposed")
	var schema_path := "user://zz_config_schema.json"
	_check(binder.write_schema(schema_path).ok and FileAccess.file_exists(schema_path), "write_schema writes the schema")
	DirAccess.remove_absolute(schema_path)

	var bad := FileAccess.open("user://zz_config_bad.json", FileAccess.WRITE)
	bad.store_string('{"no_such_field": 1}')
	bad.close()
	var strict := ZzConfig.make_binder(ZzConfig.new(), "user://zz_config_bad.json")
	strict.strict = true
	_check(not strict.load_layers().ok, "strict: an unknown key is refused")
	DirAccess.remove_absolute("user://zz_config_bad.json")

	var shipped := "res://cfg/game/%s/config_round/game.yml" % GAME
	var kept := FileAccess.get_file_as_string(shipped)
	DirAccess.make_dir_recursive_absolute(shipped.get_base_dir())
	var yml := FileAccess.open(shipped, FileAccess.WRITE)
	yml.store_string("start_points: 75\nwaves: 6\n")
	yml.close()
	var loaded := ZzConfig.new()
	var from_yml := ZzConfig.make_binder(loaded)
	from_yml.strict = true
	var got := from_yml.load_layers()
	_check(got.ok and loaded.start_points == 75 and loaded.waves == 6 and from_yml.source_of("start_points") != "default",
		"an exported cfg/game/<game>/config_round/game.yml loads back as defaults", "" if got.ok else got.error.message)
	yml = FileAccess.open(shipped, FileAccess.WRITE)
	yml.store_string(kept)
	yml.close()

	_turrets(binder, console, config)
	_hazards(binder, console, config)
	_standins(binder, console, config)
	_batch4(binder, console, config)
	_layers()
	_templates(binder)

	var wb := DotGameWorkbench.new()
	wb.panel_mode = 1
	wb.config = {"enabled": false}
	for pset: DotProfileSet in binder.profile_sets():
		wb.add_set(pset, pset.rel_path)
	add_child(wb)
	_check(wb.start().ok, "the workbench starts")
	binder.attach(wb.api.runtime)
	var listed := PackedStringArray()
	for kind: String in wb.api.kinds():
		var lg: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "get", "kind": kind, "id": binder.profile_id})
		if lg.ok:
			listed.append_array(PackedStringArray((lg.value as Dictionary).get("values", {}).keys()))
	var missing := PackedStringArray()
	for k in keys:
		if not listed.has(k):
			missing.append(k)
	_check(missing.is_empty() and binder.profile_sets().size() == 5, "the workbench lists all %d keys over %d files" % [keys.size(), binder.profile_sets().size()], ",".join(missing))
	var res: DotResult = wb.api.handle(DotGameWorkbench.LOCAL_ACTOR, {"op": "set", "kind": "config_round", "id": binder.profile_id, "key": "start_points", "value": 90})
	_check(res.ok and config.start_points == 90, "a workbench edit reaches the live config", "" if res.ok else res.error.message)
	var files: Dictionary = wb.exporter.call("collect")
	var text: String = files.get("cfg/game/%s/config_round/game.yml" % GAME, "")
	_check(text.contains("start_points: 90"), "the export holds the edit in the cfg layout")

	wb.free()
	console.free()
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _write_root(rel: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ROOT.path_join(rel).get_base_dir())
	var f := FileAccess.open(ROOT.path_join(rel), FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Child process: loads the layers strictly over the test root and prints what the live config holds.
func _probe() -> void:
	var config := ZzConfig.new()
	var binder := ZzConfig.make_binder(config)
	binder.strict = true
	binder.roots = PackedStringArray([ProjectSettings.globalize_path(ROOT)])
	var loaded := binder.load_layers()
	var console := DotConsole.new()
	add_child(console)
	binder.bind_cvars(console.cvar, DotConVar.FLAG_ARCHIVE, console.has_name)
	print("PROBE ok=%s waves=%s waves_src=%s commons=%s commons_src=%s cvar=%s gibs=%s gibs_src=%s pts=%s pts_src=%s" % [
		loaded.ok, config.waves, binder.source_of("waves"), config.commons_base, binder.source_of("commons_base"),
		console.find_cvar("zz_commons_base").get_string(), config.gore_max_gibs, binder.source_of("gore_max_gibs"),
		config.start_points, binder.source_of("start_points")])
	get_tree().quit(0)


func _child() -> String:
	var out: Array = []
	OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"res://examples/headless_config.tscn", "--", "--probe", "--zz-gore-max-gibs=12", "--zz-start-points=120"], out, true)
	return "".join(PackedStringArray(out))


## A value set in a cfg file, the environment and argv each reaches the live config, and later layers win.
func _layers() -> void:
	_write_root("game/%s/config_round/game.yml" % GAME, "waves: 4\n")
	_write_root("game/%s/config_horde/game.yml" % GAME, "commons_base: 30\n")
	OS.set_environment("ZZ_COMMONS_BASE", "33")
	var text := _child()
	_check(text.contains("PROBE ok=true"), "the layers load strictly in a fresh process", text.right(300))
	_check(text.contains("waves=4") and text.contains("waves_src=yml"), "a cfg file reaches the live config")
	_check(text.contains("commons=33") and text.contains("commons_src=env") and text.contains("cvar=33"), "the environment beats the file and reaches the cvar")
	_check(text.contains("gibs=12") and text.contains("gibs_src=argv"), "argv alone reaches the config")
	_check(text.contains("pts=120") and text.contains("pts_src=argv"), "a second argv flag reaches it too")
	OS.unset_environment("ZZ_COMMONS_BASE")
	_write_root("game/%s/config_round/game.yml" % GAME, "commons_base: 30\n")
	_check(_child().contains("PROBE ok=false"), "strict: a key in the wrong file is refused")
	for f in ["config_round", "config_horde"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT.path_join("game/%s/%s/game.yml" % [GAME, f])))


## The shipped cfg files hold every key, in step with ZzConfig, and change nothing as they are.
func _templates(binder: DotGameConfigBinder) -> void:
	var files := binder.template_files()
	_check(files.size() == 5, "five shipped cfg files", str(files.size()))
	var stale := PackedStringArray()
	for path: String in files:
		if not FileAccess.file_exists("res://" + path) or FileAccess.get_file_as_string("res://" + path) != files[path]:
			stale.append(path)
	_check(stale.is_empty(), "the shipped files match the config (run addons/dot_game/qa/dot_game_cfg_templates.gd)", ",".join(stale))


## The turret rules moved out of zz_turrets.gd keep the old constants as defaults, and a cvar changes what the rules read.
func _turrets(binder: DotGameConfigBinder, console: DotConsole, config: ZzConfig) -> void:
	var fresh := ZzConfig.new()
	_check(fresh.turret_max_per_owner == 2 and fresh.turret_seconds == 40.0 and fresh.turret_ammo == 220 and fresh.turret_damage == 14.0
		and fresh.turret_reach == 20.0 and fresh.turret_interval == 0.14 and fresh.turret_muzzle_height == 0.85
		and fresh.turret_chest_height == 1.1 and fresh.turret_place_reach == 2.2 and fresh.turret_foot_reach == 0.4,
		"the turret defaults equal the old constants (cap 2; 40 s, 220 rounds, 14 damage, 20 m, 0.14 s; muzzle 0.85, chest 1.1, place 2.2 / 0.4)")
	var cvars_ok := true
	for k in ["max_per_owner", "seconds", "ammo", "damage", "reach", "interval", "muzzle_height", "chest_height", "place_reach", "foot_reach"]:
		cvars_ok = cvars_ok and console.find_cvar("zz_turret_" + k) != null and binder.source_of("turret_" + k) == "default"
	_check(cvars_ok, "every turret field is a zz_turret_* cvar")
	var game := FakeGame.new()
	game.config = fresh
	var turrets := ZzTurrets.new(game)
	var d := turrets.defaults()
	_check(d == {"seconds": 40.0, "ammo": 220, "damage": 14.0, "reach": 20.0, "interval": 0.14}, "the rules read the old action defaults from the config")
	turrets.turrets = {1: {"owner": 5}, 2: {"owner": 5}}
	turrets._make_room(5)
	var at_default := turrets.count_for(5)
	game.config = config
	console.set_cvar("zz_turret_max_per_owner", "3")
	console.set_cvar("zz_turret_ammo", "99")
	turrets.turrets = {1: {"owner": 5}, 2: {"owner": 5}}
	turrets._make_room(5)
	_check(at_default == 1 and turrets.count_for(5) == 2 and turrets.defaults()["ammo"] == 99, "zz_turret_max_per_owner and zz_turret_ammo change what the turret rules do")


## The thrown-thing rules moved out of zz_hazards.gd keep the old constants as defaults, and a cvar changes what the rules read.
func _hazards(binder: DotGameConfigBinder, console: DotConsole, config: ZzConfig) -> void:
	var fresh := ZzConfig.new()
	_check(fresh.hazard_goo_hit_radius == 1.1 and fresh.hazard_rock_hit_radius == 1.3 and fresh.hazard_bile_lure == 35.0
		and fresh.hazard_bile_seconds == 15.0 and fresh.hazard_pipe_fuse == 6.0 and fresh.hazard_pipe_lure == 40.0
		and fresh.hazard_afterburn_seconds == 4.0 and fresh.hazard_burn_dps == 18.0,
		"the hazard defaults equal the old constants (goo 1.1, rock 1.3; bile 35 m 15 s; pipe 6 s 40 m; afterburn 4 s, 18 dps)")
	var cvars_ok := true
	for k in ["goo_hit_radius", "rock_hit_radius", "bile_lure", "bile_seconds", "pipe_fuse", "pipe_lure", "afterburn_seconds", "burn_dps"]:
		cvars_ok = cvars_ok and console.find_cvar("zz_hazard_" + k) != null and binder.source_of("hazard_" + k) == "default"
	_check(cvars_ok, "every hazard field is a zz_hazard_* cvar")
	var hazards := ZzHazards.new(null)
	hazards.game = FakeGame.new()
	hazards.game.config = config
	console.set_cvar("zz_hazard_afterburn_seconds", "9")
	_check(is_equal_approx(hazards._cfg().hazard_afterburn_seconds, 9.0), "zz_hazard_afterburn_seconds changes what the hazard rules read")


## The stand-in rules moved out of zz_bots.gd keep the old constants as defaults, and a cvar changes the live config the bots read.
func _standins(binder: DotGameConfigBinder, console: DotConsole, config: ZzConfig) -> void:
	var fresh := ZzConfig.new()
	var old := {"sight": 32.0, "upgrade_ratio": 1.35, "blast_safe": 9.0, "launcher_bonus": 10000.0, "friend_clearance": 0.7,
		"friend_cone_degrees": 14.0, "muzzle_margin": 0.08, "penetration_reach": 8.0, "shove_range": 1.7, "follow_near": 3.5,
		"follow_far": 6.0, "behave_min": 10.0, "behave_max": 22.0, "loot_reach": 90.0, "pick_up_reach": 7.0, "pick_up_give_up": 15.0,
		"pick_blocked_give_up": 3.0, "hops_before_nudge": 2, "stuck_before_relocate": 8.0, "stuck_area": 2.5, "stuck_radius": 0.8,
		"smooth_horizon": 16}
	var same := true
	var cvars_ok := true
	for k: String in old:
		same = same and fresh.get("bot_" + k) == old[k]
		cvars_ok = cvars_ok and console.find_cvar("zz_bot_" + k) != null and binder.source_of("bot_" + k) == "default"
	_check(same, "the stand-in defaults equal the old zz_bots.gd constants (%d of them)" % old.size())
	_check(cvars_ok, "every stand-in rule is a zz_bot_* cvar")
	console.set_cvar("zz_bot_shove_range", "2.5")
	console.set_cvar("zz_bot_smooth_horizon", "24")
	_check(is_equal_approx(config.bot_shove_range, 2.5) and config.bot_smooth_horizon == 24, "zz_bot_shove_range and zz_bot_smooth_horizon change the live config")


## Horde, footing and medkit-aim numbers moved out of their files keep the old constants as defaults, and a cvar changes the live config.
func _batch4(binder: DotGameConfigBinder, console: DotConsole, config: ZzConfig) -> void:
	var fresh := ZzConfig.new()
	var old := {"alert_radius": 9.0, "bile_radius": 45.0, "bile_splash": 4.0, "mob_burst": 6, "mob_burst_seconds": 0.4,
		"wanderer_clearance": 28.0, "bash_reach": 0.75, "footing_sample_every": 1.5, "footing_sample_move": 1.5,
		"footing_keep": 5, "footing_progress": 0.6, "heal_aim_dot": 0.82, "heal_hold_dot": 0.6}
	var same := true
	var cvars_ok := true
	for k: String in old:
		same = same and fresh.get(k) == old[k]
		cvars_ok = cvars_ok and console.find_cvar("zz_" + k) != null and binder.source_of(k) == "default"
	_check(same, "the horde, footing and heal-aim defaults equal the old constants (%d of them)" % old.size())
	_check(cvars_ok, "each of them is a zz_* cvar")
	console.set_cvar("zz_mob_burst", "9")
	console.set_cvar("zz_footing_keep", "7")
	_check(config.mob_burst == 9 and config.footing_keep == 7, "zz_mob_burst and zz_footing_keep change the live config")
