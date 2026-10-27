extends SceneTree

## Writes cfg/game/game-zombie-zone/box/<id>.yml for every box in boxes/boxes.json:
## `godot --headless --path . --script tools/export_box_profiles.gd`. The packs suite fails when they are stale.

const ZzBoxProfiles := preload("res://game/zz_box_profiles.gd")


func _init() -> void:
	var dir := ProjectSettings.globalize_path(ZzBoxProfiles.DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://boxes/boxes.json"))
	var n := 0
	for box: Dictionary in doc["boxes"]:
		var f := FileAccess.open(dir.path_join("%s.yml" % box["id"]), FileAccess.WRITE)
		f.store_string(ZzBoxProfiles.yaml_of(box))
		f.close()
		n += 1
	print("wrote %d box profiles to %s" % [n, dir])
	quit()
