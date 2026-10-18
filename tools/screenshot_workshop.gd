extends SceneTree

const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzSettings := preload("../game/zz_settings.gd")

## The solo map menu (M) with a Workshop map in it, to screenshots/menu_maps_workshop.png.
## The rows are the game's own `ZzGame.map_rows` over a fixture [DotContentIndex]; nothing is
## drawn by hand. Run: `xvfb-run -a godot --path . --resolution 1280x800 --script tools/screenshot_workshop.gd`
## (not `--headless`: a null renderer saves empty frames).

const OUT := "res://screenshots/menu_maps_workshop.png"

var _settings: ZzSettings = null
var _wait := 8
var _opened := false


func _process(_delta: float) -> bool:
	if _settings == null:
		DotLog.set_level(DotLog.Level.ERROR)
		DirAccess.make_dir_recursive_absolute("res://screenshots")
		var index := DotContentIndex.new()
		index.set_session(DotContentIndex.SESSION_SOLO)
		var _added := index.add_pack({
			"content_id": "fixture/ruins", "version": "1.0.0", "prefix": "res://fixture/",
			"session": DotContentIndex.SESSION_SOLO, "source": &"subscription",
			"provides": {"schema": 1, "title": "Ruins Pack", "kinds": ["map"], "entries": [
				{"kind": "map", "id": "fixture_ruin", "name": "Fixture Ruin", "scene": "ruin.tscn", "map_kind": "survival"},
				{"kind": "map", "id": "fixture_run", "name": "Fixture Run", "scene": "run.tscn", "map_kind": "race"},
			]},
		})
		var game := ZzGame.new()
		game.config = ZzConfig.new()
		game.catalogue = ZzCatalogue.new()
		var _loaded := game.catalogue.load_from("maps")
		game.content_index = index
		_settings = ZzSettings.new()
		root.add_child(_settings)
		var _built := _settings.setup()
		var _maps: Variant = _settings.call(&"use_maps", game.map_rows,
			func(id: StringName) -> DotResult: return game.change_map_now(id))
		return false
	if not _opened:
		_settings.menu.open_maps()
		# The game's own maps come first, so a pack's is on the last page.
		_settings.menu.picker.turn(99)
		_opened = true
	if _wait > 0:
		_wait -= 1
		return false
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("wrote %s (%d x %d)" % [OUT, image.get_width(), image.get_height()])
	return true
