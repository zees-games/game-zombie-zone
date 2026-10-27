extends SceneTree

## Writes cfg/game/game-zombie-zone/npc/<id>.yml for the fourteen kinds from the code table:
## `godot --headless --path . --script tools/export_npc_profiles.gd`. The packs suite fails when they are stale.

const ZzConfig := preload("res://game/zz_config.gd")
const ZzNpcs := preload("res://game/zz_npcs.gd")
const ZzNpcProfiles := preload("res://game/zz_npc_profiles.gd")


func _init() -> void:
	var dir := ProjectSettings.globalize_path(ZzNpcProfiles.DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var c := ZzConfig.new()
	for def in ZzNpcs.builtin(c):
		var f := FileAccess.open(dir.path_join("%s.yml" % String(def.id)), FileAccess.WRITE)
		f.store_string(ZzNpcProfiles.yaml_of(def, c))
		f.close()
	print("wrote %d profiles to %s" % [ZzNpcs.builtin(c).size(), dir])
	quit()
