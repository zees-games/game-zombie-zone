extends SceneTree

## Writes cfg/game/game-zombie-zone/npc/<id>.yml for the game's own kind (the common) from the code table; the thirteen special kinds are the zz-mutants pack's and ship no file here (the packs scan is not run, so only the common is built):
## `godot --headless --path . --script tools/export_npc_profiles.gd`. The packs suite fails when they are stale.

const ZzConfig := preload("res://game/zz_config.gd")
const ZzNpcs := preload("res://game/zz_npcs.gd")
const ZzNpcProfiles := preload("res://game/zz_npc_profiles.gd")


func _init() -> void:
	var dir := ProjectSettings.globalize_path(ZzNpcProfiles.DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var c := ZzConfig.new()
	var built := ZzNpcs.builtin(c)
	var kept := PackedStringArray()
	for def in built:
		kept.append("%s.yml" % String(def.id))
		var f := FileAccess.open(dir.path_join("%s.yml" % String(def.id)), FileAccess.WRITE)
		f.store_string(ZzNpcProfiles.yaml_of(def, c))
		f.close()
	# A file for a kind this game no longer builds (the pack's thirteen) is stale: removed.
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".yml") and not kept.has(name):
			DirAccess.remove_absolute(dir.path_join(name))
			print("removed ", name)
	print("wrote %d profiles to %s" % [built.size(), dir])
	quit()
