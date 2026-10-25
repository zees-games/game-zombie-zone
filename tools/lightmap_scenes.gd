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

## Node names of a map's prop casters in the bake (the trim and the suites find them by it), the
## smallest prop that casts one, and the metres per texel their UV2 is _unwrapped at.
const CASTER_PREFIX := "Prop_"
const CASTER_MIN_SIZE := 0.6
const CASTER_TEXEL := 4.0

## Per map: LightmapGI settings for DotLightBake.prepare. The defaults suit a street; the big
## holds take a coarser texel so the file stays a browser download.
## How much of the live ambient each surface emits into the bake (see _with_emission): an open
## street already has its sky, a closed hold has none, so the holds take more. Tuned per map
## against a live frame (tools/shot.sh --no-bake), not derived.
const EMIT_BY_MAP := {"zz_lot": 0.3, "zz_practice": 0.15, "zz_blackout_2": 0.15, "zz_blackout_3": 0.2, "zz_chapel": 0.2, "zz_stadium": 0.4, "zz_relief_camp": 0.2, "zs_ravenstreet": 0.25, "ze_runforyourlife_1_v4": 0.3, "ze_jurassicpark": 0.1, "ze_boat_escape": 0.0, "ze_death_star_escape": 0.1, "zm_chaos_city": 0.5, "zm_pathogen": 0.5, "zz_mall": 0.5, "zz_high_school": 0.75, "ze_nuke_beta": 0.95}

## The bake's sky term, as a multiple of the live ambient: an open map sees its sky from every
## surface, so it takes less than a closed hold (which sees none of it). Tuned like EMIT_BY_MAP.
const AMBIENT_GAIN_BY_MAP := {"zz_lot": 2.5, "zz_practice": 1.4, "zz_blackout_2": 1.35, "zz_blackout_3": 2.0, "zz_chapel": 1.8, "zz_stadium": 2.6, "zz_relief_camp": 1.4, "zs_ravenstreet": 2.4, "ze_runforyourlife_1_v4": 2.7, "ze_jurassicpark": 1.0, "ze_boat_escape": 0.0, "ze_death_star_escape": 0.0, "zm_chaos_city": 1.0, "zm_pathogen": 1.0}

const SETTINGS := {
	"default": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 1.0, "ambient_gain": 6.0, "bounce_energy": 0.7, "emit": 0.4},
	# Half the texels each way (a texel per 0.5 m): at full density the stadium was 12 MB and the
	# mall 6 MB, more than the rest of the game's download.
	"zz_stadium": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"zz_mall": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"zz_high_school": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"zz_relief_camp": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	# Converted maps: hundreds of boxes, long corridors.
	"ze_nuke_beta": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"ze_runforyourlife_1_v4": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"ze_jurassicpark": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 2, "texel_scale": 0.2},
	"ze_blackmesa_escape": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 2, "texel_scale": 0.2},
	"ze_death_star_escape": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 2, "texel_scale": 0.3},
	"zm_chaos_city": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
	"zm_pathogen": {"quality": LightmapGI.BAKE_QUALITY_MEDIUM, "bounces": 3, "texel_scale": 0.5},
}


var _props: ZzProps = null
## Prop part -> its UV2-unwrapped mesh (or null), shared by every map: unwrapping is the slow part.
var _unwrapped := {}


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
	_props = props
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
	var settings: Dictionary = (SETTINGS["default"] as Dictionary).duplicate()
	settings.merge(SETTINGS.get(String(map.id()), {}), true)
	if FileAccess.file_exists("res://tools/lb_override.json"):
		settings.merge(JSON.parse_string(FileAccess.get_file_as_string("res://tools/lb_override.json")), true)

	var ambient := Color.WHITE
	var ambient_energy := 1.0
	var env_node := map.get_node_or_null("Lighting/Lighting") as WorldEnvironment
	if env_node != null:
		ambient = env_node.environment.ambient_light_color
		ambient_energy = env_node.environment.ambient_light_energy
	var emit_gain: float = float(EMIT_BY_MAP.get(String(map.id()), settings.get("emit", 0.4))) * ambient_energy

	for child in map.get_node("Drawn").get_children():
		if child is MeshInstance3D and child.has_meta(&"zz_bakeable"):
			var mesh := MeshInstance3D.new()
			mesh.name = child.name
			mesh.mesh = (child as MeshInstance3D).mesh
			mesh.material_override = _with_emission((child as MeshInstance3D).material_override, ambient, emit_gain)
			mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			drawn.add_child(mesh)
		elif child is Light3D:
			var lamp := (child as Light3D).duplicate() as Light3D
			lamp.visible = true
			lamp.light_energy = float(lamp.get_meta(&"zz_base_energy", lamp.light_energy))    # every lamp, whatever the runtime budget lights
			lamp.light_bake_mode = Light3D.BAKE_STATIC
			lamp.shadow_enabled = bool(settings.get("lamp_shadow", true))
			lamp.light_size = 0.15
			drawn.add_child(lamp)

	if settings.get("casters", true):
		_add_prop_casters(map, drawn)

	var lighting := map.get_node("Lighting").duplicate() as Node3D
	root.add_child(lighting)

	for node in lighting.get_children():
		if node is DirectionalLight3D:
			# The sun first (DotLightRig adds it before the fill).
			var light := node as DirectionalLight3D
			light.light_bake_mode = Light3D.BAKE_DYNAMIC if node == lighting.get_child(0) else Light3D.BAKE_DISABLED

	var gi := DotLightBake.prepare(root, map.light_fingerprint(), ZzMap.BAKE_PATH % String(map.id()), settings)
	# The sky term is the map's own AMBIENT, not the bake scene's sky: the sky is a deep blue at
	# night and a lightmap lit by it came out bluer and darker than the live ambient (a flat
	# colour at the live energy) that every map is tuned under. The bake keeps what a flat
	# ambient cannot do, which is its occlusion: corners and under-shelf darkening.
	var world := lighting.get_node_or_null("Lighting") as WorldEnvironment
	if world != null:
		gi.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
		gi.environment_custom_color = world.environment.ambient_light_color
		gi.environment_custom_energy = world.environment.ambient_light_energy * float(AMBIENT_GAIN_BY_MAP.get(String(map.id()), settings.get("ambient_gain", 6.0)))
	gi.bounce_indirect_energy = float(settings.get("bounce_energy", 0.7))
	_own(root, root)
	return root


## A closed room has no sky to see, so a lightmap's sky term never reaches its walls, yet the live
## map is lit there by a flat ambient. Every surface emits the ambient colour in the bake (a
## copy of its material; the lightmap holds only what the surface receives), so light bounces
## off the others and the room is filled the way the ambient fills it, shadowed by its corners.
func _with_emission(source: Material, colour: Color, energy: float) -> Material:
	if energy <= 0.0 or not (source is StandardMaterial3D):
		return source
	var copy := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	copy.emission_enabled = true
	copy.emission = colour
	copy.emission_energy_multiplier = energy
	copy.emission_texture = null
	return copy


## Props never move once a map is built, so they belong in the bake: they shade the floor and the
## walls from the lamps, and lamplight bounces off them. They are drawn as MultiMeshes (a
## lightmap cannot name an instance of one, and a node per prop is hundreds of draw calls), so
## here they are casters only: each part gets a coarse UV2 so the baker takes it in, and the
## bake step's trim (tools/lightmap_trim.gd) drops their texels from the stored file. What is lit
## on a prop at runtime is the bake's light probes, which see the same shadows.
func _add_prop_casters(map: ZzMap, drawn: Node3D) -> void:
	var made := 0

	for index in map.props.size():
		var prop: Dictionary = map.props[index]
		var size: Vector3 = prop["size"]

		if maxf(size.x, maxf(size.y, size.z)) < CASTER_MIN_SIZE:
			continue

		var parts := _props.parts(prop["id"])

		for part_index in parts.size():
			var part: Array = parts[part_index]
			var key := "%s/%d" % [prop["id"], part_index]

			if not _unwrapped.has(key):
				var started := Time.get_ticks_msec()
				var source := part[0] as Mesh
				var mesh := ArrayMesh.new()
				if source is ArrayMesh:
					for surface in source.get_surface_count():
						mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), source.surface_get_arrays(surface))
				_unwrapped[key] = mesh if mesh.get_surface_count() > 0 and mesh.lightmap_unwrap(part[1] as Transform3D, CASTER_TEXEL) == OK else null

				print("LIGHTMAP_SCENE unwrap %s %d ms" % [key, Time.get_ticks_msec() - started])

			if _unwrapped[key] == null:
				continue

			var node := MeshInstance3D.new()
			node.name = "%s%d_%d" % [CASTER_PREFIX, index, part_index]
			node.mesh = _unwrapped[key]
			node.transform = (prop["transform"] as Transform3D) * (part[1] as Transform3D)
			node.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			node.set_meta(&"zz_caster", true)
			drawn.add_child(node)
			made += 1

	print("LIGHTMAP_SCENE casters %s %d" % [map.id(), made])


func _own(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)
