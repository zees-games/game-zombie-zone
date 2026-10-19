extends SceneTree

## Drops the prop casters from every bake in lightmaps/ (their nodes do not exist at runtime: the
## props are MultiMeshes; see tools/lightmap_scenes.gd), so a lightmap names only meshes the
## client builds. Run by tools/bake_lightmaps.sh on the machine that baked, under a display:
## a texture array saved from a headless process has no pixels.
##
##   godot --path . --script res://tools/lightmap_trim.gd [-- id ...]



## Same as tools/lightmap_scenes.gd (not preloaded: that script pulls in the whole game).
## Bake-time casters: the props, and the shiny batches (see ZzMap._build_boxes).
const CASTER_PREFIXES := ["Prop_", "Shiny_"]


func _init() -> void:
	var wanted := OS.get_cmdline_user_args()
	var failed := 0

	for file in DirAccess.get_files_at("res://lightmaps"):
		if file.get_extension() != "res" or (not wanted.is_empty() and not wanted.has(file.get_basename())):
			continue

		var path := "res://lightmaps/" + file
		var data := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LightmapGIData

		if data == null:
			printerr("LIGHTMAP_TRIM fail %s" % path)
			failed += 1
			continue

		var uses: Array = data.get("user_data")
		var kept: Array = []

		# Flat, four values a user: its path, UV scale, slice and sub-instance.
		for i in range(0, uses.size(), 4):
			if not _is_caster(str((uses[i] as NodePath).get_name(uses[i].get_name_count() - 1))):
				kept.append_array(uses.slice(i, i + 4))

		if kept.size() == uses.size():
			print("LIGHTMAP_TRIM same %s %d" % [file, uses.size() / 4])
			continue

		data.set("user_data", kept)
		var saved := ResourceSaver.save(data, path, ResourceSaver.FLAG_COMPRESS)
		print("LIGHTMAP_TRIM %s %s %d -> %d users (%d)" % [
			"ok" if saved == OK else "fail", file, uses.size() / 4, kept.size() / 4, 0])
		failed += 0 if saved == OK else 1

	quit(1 if failed > 0 else 0)


static func _is_caster(node_name: String) -> bool:
	for prefix: String in CASTER_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	return false
