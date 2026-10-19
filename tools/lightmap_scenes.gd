extends Node

## Writes one bake scene per map for dot-lighting's baker: the map built exactly as a client
## builds it, its drawn half kept (the opaque box batches with their UV2, the lamps, the sun and
## the sky), a LightmapGI added and the map's fingerprint recorded. tools/bake_lightmaps.sh runs
## this and then the bake; nobody needs to run it alone.
##
##   xvfb-run -a godot --path . res://tools/lightmap_scenes.tscn -- --out=res://lightbake_work [--maps=zz_lot,zz_mall]
##
## Under a display, not --headless: a headless process keeps no mesh or image data to save.
##
## [b]What the bake sees.[/b] The lamps are baked whole (BAKE_STATIC, with soft shadows they do
## not cast live); the moon or sun only gives its bounce (BAKE_DYNAMIC), because it stays live
## and a hold's day turns it; dot-lighting's fill is left out (BAKE_DISABLED), being already
## "more sky", which the environment gives the bake. Changing any of that changes what a bake
## means: bump ZzMap.BAKE_VERSION.

const ZzMap := preload("../game/zz_map.gd")
const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzProps := preload("../game/zz_props.gd")

## Per map: LightmapGI settings for DotLightBake.prepare. The defaults suit a street; the big
## holds take a coarser texel so the file stays a browser download.
const SETTINGS := {
	"default": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 1.0},
	# Half the texels each way (a texel per 0.5 m): at full density the stadium was 12 MB and the
	# mall 6 MB, more than the rest of the game's download.
	"zz_stadium": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"zz_mall": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"zz_high_school": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"zz_relief_camp": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
}


func _ready() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	_run.call_deferred()


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return fallback


func _run() -> void:
	var out := _arg("out", "res://lightbake_work")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var catalogue := ZzCatalogue.new()
	catalogue.load_from("maps")
	var props := ZzProps.new()
	props.load_file()
	var wanted := _arg("maps", "")
	var ids: Array = catalogue.maps.keys()
	ids.sort()
	var written := 0

	for id: StringName in ids:
		if wanted != "" and not wanted.split(",").has(String(id)):
			continue

		var map := ZzMap.new()
		map.catalogue = props
		map.draw_world = true
		add_child(map)
		ZzMap.use_bakes = false
		var built := map.build(catalogue.maps[id])

		if not built.ok:
			printerr("LIGHTMAP_SCENE fail %s %s" % [id, built.error.message])
			continue

		var scene := _bake_scene(map)
		var path := out.path_join("%s.tscn" % id)
		var packed := PackedScene.new()
		packed.pack(scene)
		var saved := ResourceSaver.save(packed, path)
		print("LIGHTMAP_SCENE %s %s %s" % ["ok" if saved == OK else "fail", id, path])
		written += 1 if saved == OK else 0
		scene.free()
		remove_child(map)
		map.free()

	get_tree().quit(0 if written > 0 else 1)


func _bake_scene(map: ZzMap) -> Node3D:
	var root := Node3D.new()
	root.name = "Bake"
	var drawn := Node3D.new()
	drawn.name = "Drawn"
	root.add_child(drawn)
	var settings: Dictionary = SETTINGS.get(String(map.id()), SETTINGS["default"])

	for child in map.get_node("Drawn").get_children():
		if child is MeshInstance3D and child.has_meta(&"zz_bakeable"):
			var mesh := MeshInstance3D.new()
			mesh.name = child.name
			mesh.mesh = (child as MeshInstance3D).mesh
			mesh.material_override = (child as MeshInstance3D).material_override
			mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			drawn.add_child(mesh)
		elif child is OmniLight3D:
			var lamp := (child as OmniLight3D).duplicate() as OmniLight3D
			lamp.light_bake_mode = Light3D.BAKE_STATIC
			lamp.shadow_enabled = true
			lamp.light_size = 0.15
			drawn.add_child(lamp)

	var lighting := map.get_node("Lighting").duplicate() as Node3D
	root.add_child(lighting)

	for node in lighting.get_children():
		if node is DirectionalLight3D:
			# The sun first (DotLightRig adds it before the fill).
			var light := node as DirectionalLight3D
			light.light_bake_mode = Light3D.BAKE_DYNAMIC if node == lighting.get_child(0) else Light3D.BAKE_DISABLED

	DotLightBake.prepare(root, map.light_fingerprint(), ZzMap.BAKE_PATH % String(map.id()), settings)
	_own(root, root)
	return root


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
