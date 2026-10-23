extends Node

const ZzMapConfig := preload("../game/zz_map_config.gd")

## A map's per-map file sets the whitelisted rules, the next map gets the old values back, and a key outside the whitelist is refused.
##
## [codeblock]
## godot --headless --path . res://examples/headless_mapcfg.tscn
## [/codeblock]
##
## The files are written into a scratch operator root, so the suite does not depend on a shipped map's file; the cvars start away from the values.

const CHECKS := 8

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("game-zombie-zone: per-map cvars")
	var root := OS.get_cache_dir().path_join("zz_mapcfg_%d" % OS.get_process_id())
	var dir := root.path_join("server/game/%s/dot_map/map" % ZzMapConfig.GAME_ID)
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir.path_join("zz_probe_hold.yml"), "zz_waves: 4\nzz_difficulty: 3\nzz_gravity: 1\n")

	var console := DotConsole.new()
	add_child(console)
	console.cvar("zz_waves", "10", "")
	console.cvar("zz_difficulty", "1", "")
	console.cvar("zz_gravity", "20", "")
	var cfg := DotGameMapConfig.for_console(ZzMapConfig.GAME_ID, console, ZzMapConfig.KEYS)
	cfg.config_dir = root

	var got := cfg.apply("zz_probe_hold")
	_check(got.size() == 2, "the map applies its two whitelisted keys (%s)" % [got])
	_check(console.find_cvar("zz_waves").get_int() == 4, "zz_waves is 4 on the map")
	_check(console.find_cvar("zz_difficulty").get_int() == 3, "zz_difficulty is 3 on the map")
	_check(console.find_cvar("zz_gravity").get_int() == 20, "zz_gravity is outside the whitelist and untouched")

	cfg.apply("zz_other")
	_check(console.find_cvar("zz_waves").get_int() == 10, "the next map has zz_waves back")
	_check(console.find_cvar("zz_difficulty").get_int() == 1, "and zz_difficulty")
	_check(cfg.applied().is_empty(), "a map with no file applies nothing")
	_check(ZzMapConfig.KEYS.keys().all(func(k: String) -> bool: return k.begins_with("zz_") and k != "zz_gravity"), "no movement key is whitelisted")

	DirAccess.remove_absolute(dir.path_join("zz_probe_hold.yml"))
	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	for line in _failures:
		print("  FAIL  %s" % line)
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected." % [_passed + _failed, CHECKS])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what)
		print("  FAIL  %s" % what)
