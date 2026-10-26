extends SceneTree

## Rewrites cfg/game/game-zombie-zone/config_*/game.yml from ZzConfig's fields: godot --headless --path . --script tools/cfg_templates.gd

const ZzConfig := preload("../game/zz_config.gd")


func _init() -> void:
	var binder := ZzConfig.make_binder(ZzConfig.new())
	var files := binder.template_files()
	for path: String in files:
		var res := DotPaths.write_text("res://" + path, files[path])
		print("%s %s" % ["wrote" if res.ok else "FAILED", path])
	quit()
