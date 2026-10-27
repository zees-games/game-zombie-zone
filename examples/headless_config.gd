extends Node

## ZzConfig through DotGameConfigBinder: fields, cvars, strict refusal, the diff, yml defaults and the workbench round trip.
##
## [codeblock]
## godot --headless --path . res://examples/headless_config.tscn
## [/codeblock]

const ZzConfig := preload("../game/zz_config.gd")
const ROOT := "user://zz_cfgtest"
const GAME := "game-zombie-zone"
const CHECKS := 38

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.FATAL)
	_run.call_deferred()


func _check(ok: bool, what: String, _detail := "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		_failures.append(what)


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
	for k in ["waves", "wave_size", "respawn_base_seconds", "box_drop_common", "defib_range", "down_attack", "start_points", "difficulty"]:
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
	_check(config.gore_level == 2 and config.gore_max_gibs == 24 and config.gore_max_wounds == 48, "gore defaults to flying limbs, 24 gibs, 48 wound marks")
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
