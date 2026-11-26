extends RefCounted

## Seats a pack's own monster view on this game's zombie view: a pack cannot name the game's script by a relative
## path, and its globals do not register. A pack view starts `extends "ZZ_VIEW_PARENT"` and writes `ZZ_PACK_DIR`
## where it names its own files; this writes the script with both filled in under `user://zz_pack_views/` and loads
## it. A view that will not load answers null, and the caller draws the monster as the game's body (never an error).

const ZzPaths := preload("zz_paths.gd")
const DIR := "user://zz_pack_views"
const PARENT_TOKEN := "ZZ_VIEW_PARENT"
const DIR_TOKEN := "ZZ_PACK_DIR"
const PARENT := "res://npcs/zz_zombie_view.gd"
const CHANNEL := "zz.packs"

static var _cache: Dictionary = {}


## The pack's view script at [param path] (absolute, under [param pack_dir]), or null.
static func script_for(path: String, pack_dir: String) -> Script:
	var key := path + "|" + pack_dir

	if _cache.has(key):
		return _cache[key] as Script

	var made := _make(path, pack_dir)
	_cache[key] = made
	return made


static func clear() -> void:
	_cache.clear()


static func _make(path: String, pack_dir: String) -> Script:
	if not FileAccess.file_exists(path):
		return null

	var text := FileAccess.get_file_as_string(path)

	if not text.contains(PARENT_TOKEN):
		GSLog.warn(CHANNEL, "a pack view does not extend ZZ_VIEW_PARENT, ignored", {"path": path})
		return null

	text = text.replace(PARENT_TOKEN, ZzPaths.rebase(PARENT)).replace(DIR_TOKEN, pack_dir)
	var _made := DirAccess.make_dir_recursive_absolute(DIR)
	var file := "%s/%d.gd" % [DIR, text.hash()]

	if not FileAccess.file_exists(file):
		var out := FileAccess.open(file, FileAccess.WRITE)

		if out == null:
			GSLog.warn(CHANNEL, "a pack view could not be written", {"path": file})
			return null

		out.store_string(text)
		out.close()

	var script := ResourceLoader.load(file, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as Script
	return script if script != null and script.can_instantiate() else null
