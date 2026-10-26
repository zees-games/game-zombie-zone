extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzLampBudget := preload("../game/zz_lamp_budget.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzMechanics := preload("../game/zz_mechanics.gd")
const ZzPaths := preload("../game/zz_paths.gd")

## Every map the game can be sent, built the way a server builds it and looked over for the
## mistakes a map document makes without any error: a spawn inside a wall or over nothing, a
## prop the catalogue does not have (built as nothing), a prop sunk into a wall or floating,
## an item out of reach, and — the one this game adds — ground the zombies cannot cross.
##
## [b]Why this exists apart from `headless_run`.[/b] The maps are generated in
## zombie-zone-maps by `tools/build_maps.py`, and none of those mistakes stops a map: a
## doorway the nav graph does not cross is a safe room no zombie ever enters, an objective
## off the graph is a hold-out the horde never reaches, and a gate that does not cut the
## graph is a barrier the horde walks through. The renders find the ugly ones; this finds the
## rest, on every map, every time.
##
## Sections and checks are both counted; mg-smash-copter's notes say why the second matters.
## Adding a map adds a section and CHECKS_PER_MAP checks.

const ZzNpcs := preload("../game/zz_npcs.gd")

const MAPS := ["zz_practice", "zz_blackout_1", "zz_blackout_2", "zz_blackout_3", "zz_lot", "zz_chapel", "zz_high_school", "zz_mall", "zz_stadium", "zz_relief_camp", "zs_ravenstreet", "ze_nuke_beta", "ze_runforyourlife_1_v4", "zm_atix_helicopter", "zm_4way_tunnel", "zm_abandoned_mall", "ze_boat_escape", "ze_death_star_escape", "zm_chaos_city", "zm_pathogen"]
const CHECKS_PER_MAP := 18
const BAKE_CHECKS := 7
const WORLD_CHECKS := 4
const LAMP_CHECKS := 8

## The maps actually checked: all of MAPS, or only the practice street where `maps/` is not
## linked in (CI, which clones this repository alone). As mg-deathrun's headless_courses
## does: the delivered maps are checked wherever they are present, which is every machine
## that has run dot-bootstrap. Sections and checks are counted against this list.
var _maps: Array = []
var _worlds_read := 0

## A person's capsule, for "is this spawn clear".
const RADIUS := 0.4
const HEIGHT := 1.8

## Fewest survivor spawns a map may have: a team of four starts apart.
const MIN_SPAWNS := 4

## How far a point that matters (an objective, a route point) may be from the zombies' ground.
const SNAP := 2.5

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()


## Shipped world maps whose spawner config was checked (three checks each).
var _spawner_worlds := 0
## World maps whose spawner checks were skipped because world/ is not linked.
var _worlds_skipped := 0
## Maps whose wire budget cut boxes: each adds the whole-floor check.
var _nav_extra_maps := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone maps")
	print("")

	await _test_the_catalogue()
	await _test_baked_light()
	await _test_lamp_budget()
	await _test_worlds()

	for id: String in _maps:
		await _test_map(StringName(id))

	print("")
	print("%d sections entered, %d finished" % [_sections_entered, _sections_finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _worlds_skipped > 0:
		print("SKIPPED: %d world maps' spawner checks (world/ is not linked; run dot-bootstrap for the full suite)" % _worlds_skipped)

	var sections := 4 + _maps.size()
	var checks := 1 + BAKE_CHECKS + LAMP_CHECKS + WORLD_CHECKS * _worlds_read + CHECKS_PER_MAP * _maps.size() + 3 * _spawner_worlds + _nav_extra_maps

	if _sections_entered != _sections_finished or _sections_entered != sections:
		print("ERROR: %d of %d sections finished, %d expected." % [_sections_finished, _sections_entered, sections])
		code = 1

	if _passed + _failed != checks or _maps.is_empty():
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, checks])
		code = 1

	get_tree().quit(code)


## The height of the nav floor a point stands over, nearest the point's own height. The street maps
## are flat at y=0, but an exodus map is converted at the source's heights (a deck at 22 m, a
## stair, a bridge), and the graph's points are at those heights: a target flattened to 0 is 22 m
## from every point and was "unreached" however well the ground joined.
func _ground_y(doc: Dictionary, at: Vector3) -> float:
	var best := 0.0
	var found := false
	for f: Array in (doc.get("nav", {}) as Dictionary).get("floors", []):
		if at.x < float(f[0]) or at.x > float(f[2]) or at.z < float(f[1]) or at.z > float(f[3]):
			continue
		var y := float(f[4])
		if not found or absf(y - at.y) < absf(best - at.y):
			best = y
			found = true
	if doc.has("terrain"):
		var ground := DotMapTerrain.from_dict(doc["terrain"])
		var y := (ground.value as DotMapTerrain).height_at(at.x, at.z) if ground.ok else NAN
		if not is_nan(y) and (not found or absf(y - at.y) < absf(best - at.y)):
			best = y
	return best


func _test_the_catalogue() -> void:
	_section("the catalogue")
	var game := await _world(&"")
	var ids: Array = []

	for id: StringName in game.catalogue.maps:
		ids.append(String(id))

	ids.sort()
	var linked := DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://maps"))
	_maps = MAPS.duplicate() if linked else ["zz_practice"]

	if not linked:
		print("(no map directory: the built-in practice street only)")

	var missing: Array = []

	for id: String in _maps:
		if not ids.has(id):
			missing.append(id)

	_check(missing.is_empty() and game.catalogue.refused.is_empty(),
		"every map is in it, and no file was refused", "have %s, missing %s, refused %s" % [ids, missing, game.catalogue.refused])
	await _dispose(game)
	_finished()


## The document keeps every lamp; only the nearest few are lit, and a lamp fades rather than pops.
func _test_lamp_budget() -> void:
	_section("lamp budget")
	var game := await _world(&"")
	var source := (game.catalogue.maps[&"zz_practice"] as Dictionary).duplicate(true)
	var lights: Array = []
	for i in 300:
		lights.append({"at": [i * 2.0, 3.0, 0.0], "range": 6.0, "energy": 1.0, "colour": [1, 1, 1]})
	lights.append({"at": [0, 3, 5], "range": 6.0, "energy": 1.0, "colour": [1, 1, 1], "dir": [0, -1, 0], "cone": 40.0})
	source["lights"] = lights
	var res := ZzMapDoc.validate(source)
	_check(res.ok and (res.value["lights"] as Array).size() == 301, "a document keeps all 301 lamps", "%s" % [res.error if not res.ok else ""])
	var kept: Array = res.value["lights"] if res.ok else []
	_check(not kept.is_empty() and (kept[300] as Dictionary).get("cone", 0.0) == 40.0 and (kept[0] as Dictionary).has("cone") == false,
		"a spot keeps its cone and direction, an omni gets none")

	var host := Node3D.new()
	add_child(host)
	var lamps: Array[Light3D] = []
	for light: Dictionary in lights:
		var omni := OmniLight3D.new()
		omni.position = ZzMapDoc.v3(light["at"])
		omni.omni_range = 6.0
		host.add_child(omni)
		lamps.append(omni)
	var budget := ZzLampBudget.new()
	budget.limit = 40
	budget.setup(lamps)
	_check(budget.lit_count() == 40 and _visible(lamps) == 40, "301 lamps start with only the limit lit", "%d lit, %d visible" % [budget.lit_count(), _visible(lamps)])
	budget.update(lamps, Vector3(0, 0, 0), 0.016)
	var near := true
	# The spot beside the first lamp is among the 40 nearest, so lamp 39 is not.
	for i in 39:
		near = near and lamps[i].visible
	near = near and lamps[300].visible
	_check(near and _visible(lamps) == 40, "the first pass lights the 40 nearest at once", "%d visible" % _visible(lamps))

	# Walk 400 m along the row at 8 m/s in frames of 1/60 s: no lamp's energy jumps by more than a fade step.
	var worst := 0.0
	var peak := 0
	var previous: Array = lamps.map(func(l: Light3D) -> float: return l.light_energy)
	for frame in 3000:
		budget.update(lamps, Vector3(8.0 * frame / 60.0, 0, 0), 1.0 / 60.0)
		peak = maxi(peak, _visible(lamps))
		for i in lamps.size():
			worst = maxf(worst, absf(lamps[i].light_energy - float(previous[i])))
			previous[i] = lamps[i].light_energy
	_check(worst <= ZzLampBudget.FADE_PER_SECOND / 60.0 + 0.001, "no lamp pops while walking past (largest step %.3f)" % worst)
	_check(peak <= 40 + 12, "lamps still fading out stay few while walking (peak %d visible)" % peak)
	for i in 100:
		budget.update(lamps, Vector3(400, 0, 0), 0.05)
	var lit_near := 0
	for i in lamps.size():
		if lamps[i].visible:
			lit_near += 1 if absf(lamps[i].position.x - 400.0) <= 40.0 + ZzLampBudget.KEEP_BONUS else 0
	_check(_visible(lamps) == 40 and lit_near == 40, "standing still, exactly the 40 nearest are lit", "%d visible, %d of them near" % [_visible(lamps), lit_near])

	var few: Array[Light3D] = []
	for i in 10:
		var l := OmniLight3D.new()
		host.add_child(l)
		few.append(l)
	var small := ZzLampBudget.new()
	small.setup(few)
	small.update(few, Vector3(900, 0, 0), 0.1)
	_check(_visible(few) == 10, "a map under the limit lights every lamp wherever the camera is")
	host.queue_free()
	game.free()
	_finished()


func _visible(lamps: Array[Light3D]) -> int:
	var n := 0
	for lamp in lamps:
		n += 1 if lamp.visible else 0
	return n


## The committed bakes against the maps as they are now. A map edited without a rebake still
## plays (live lamps and a WARN on every client), so nothing else would notice: this does.
## Rebake with tools/bake_lightmaps.sh. Headless, a bake's pixels are not loaded, but its
## fingerprint is, and attaching is refused without touching the map.
func _test_baked_light() -> void:
	_section("baked light")
	var game := await _world(&"")
	var stale: Array = []
	var baked: Array = []
	var unbaked: Array = []
	var casters: Array = []

	for id: String in _maps:
		var path := ZzMap.BAKE_PATH % id
		if not ResourceLoader.exists(path):
			unbaked.append(id)
			continue
		var map := ZzMap.new()
		map.doc = game.catalogue.maps.get(StringName(id), {})
		var data := load(path) as LightmapGIData
		baked.append(id)
		# The bake step trims the prop casters (tools/lightmap_trim.gd): a client builds no such node.
		var users: Array = data.get("user_data") if data != null else []
		for i in range(0, users.size(), 4):
			if str((users[i] as NodePath).get_name((users[i] as NodePath).get_name_count() - 1)).begins_with("Prop_") or str((users[i] as NodePath).get_name((users[i] as NodePath).get_name_count() - 1)).begins_with("Shiny_"):
				casters.append(id)
				break
		if data == null or str(data.get_meta(DotLightBake.META_FINGERPRINT, "")) != map.light_fingerprint():
			stale.append(id)
		map.free()

	_check(stale.is_empty(), "every committed bake was made from its map as it is now",
		"baked %s, stale %s" % [baked, stale])
	_check(unbaked.is_empty(), "every map the game ships has a bake", "no bake: %s" % [unbaked])
	_check(casters.is_empty(), "no bake names a prop or shiny caster (the trim ran)", "%s" % [casters])
	_check(baked.has("zz_practice"), "the practice street, the one map every build has, ships a bake")

	var moved := ZzMap.new()
	moved.doc = (game.catalogue.maps.get(&"zz_practice", {}) as Dictionary).duplicate(true)
	var before := moved.light_fingerprint()
	var boxes: Array = moved.doc.get("boxes", [])
	if not boxes.is_empty():
		var first: Dictionary = boxes[0]
		var at := ZzMapDoc.v3(first["at"]) + Vector3(0.25, 0.0, 0.0)
		first["at"] = [at.x, at.y, at.z]
	_check(not boxes.is_empty() and moved.light_fingerprint() != before,
		"moving one box makes the bake stale (the fingerprint changes)")
	moved.free()

	var host := Node3D.new()
	add_child(host)
	var res := DotLightBake.attach(host, ZzMap.BAKE_PATH % "zz_practice", before)
	_check(not res.ok and res.error.code == DotError.CODE_UNSUPPORTED and host.get_child_count() == 0,
		"a headless process (a server) never lays a bake over its world", "%s" % [res.error.message if not res.ok else "attached"])
	host.free()

	# A host with dot-lighting older than API level 5 must still parse the game: nothing under game/
	# may name a level-5 class, only reach it by path behind ZzMap.can_bake().
	var named := PackedStringArray()
	for f in Array(DirAccess.get_files_at("res://game")) + Array(DirAccess.get_files_at("res://game/net")).map(func(n): return "net/" + n):
		if not f.ends_with(".gd"):
			continue
		for line in FileAccess.get_file_as_string("res://game/" + f).split("\n"):
			if not line.strip_edges().begins_with("#") and (line.contains("DotLightBake") or line.contains("DotLightmapSheet")):
				named.append("%s: %s" % [f, line.strip_edges()])
	_check(named.is_empty() and ZzMap.can_bake(), "no game script names a level-5 dot-lighting class", "%s" % [named])
	await _dispose(game)
	_finished()


## Every converted map's drawn world reads, its movers all have geometry, and a mechanics builds
## from them (zombie-zone-maps' tools/check_worlds.py holds the manifest half). Every document
## in `maps/` that names a world, whether or not the section below plays it.
func _test_worlds() -> void:
	_section("worlds")
	_worlds_read = 0

	if not ZzMap.can_draw_world() or not DirAccess.dir_exists_absolute(ZzPaths.rebase("res://maps")):
		_finished()
		return

	for file in DirAccess.get_files_at(ZzPaths.rebase("res://maps")):
		if not file.ends_with(".json"):
			continue

		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(ZzPaths.rebase("res://maps/" + file)))
		var pack: String = str((doc as Dictionary).get("world", "")) if doc is Dictionary else ""
		var id := file.get_basename()
		var prefix := ZzPaths.rebase(ZzMap.LOCAL_WORLD % [pack, id])

		if pack == "" or not FileAccess.file_exists(prefix + ".json"):
			continue

		_worlds_read += 1
		var read: DotResult = (load(ZzMap.MESH_SCRIPT) as GDScript).call(&"load_prefix", prefix)
		_check(read.ok, "%s: its world reads" % id, "" if read.ok else read.error.message)

		if not read.ok:
			_check(false, "%s: its movers have geometry" % id)
			_check(false, "%s: a mechanics builds from it" % id)
			_check(false, "%s: its sounds and props attach" % id)
			continue

		var world: RefCounted = read.value
		var manifest: Dictionary = world.get("manifest")
		var models := {}
		for model: int in world.call(&"models"):
			models[model] = true

		var orphans := 0
		for rec: Dictionary in manifest.get("movers", []):
			if rec.get("model") == null:
				# A hinged prop door has no brush: dot-map's stand-in is its body.
				if rec.get("classname") != "prop_door_rotating":
					orphans += 1
			elif not models.has(int(rec["model"])):
				orphans += 1

		var movers := (manifest["movers"] as Array).size()
		_check(orphans == 0, "%s: its movers have geometry" % id, "%d movers, %d without" % [movers, orphans])
		var mech := ZzMechanics.new()
		add_child(mech)
		mech.build(world, Callable())
		_check(mech.mover_count() == movers, "%s: a mechanics builds from it" % id, "%d of %d" % [mech.mover_count(), movers])
		mech.queue_free()

		# Sounds and props: as many nodes as the manifest has stand-ins that exist, none for a
		# world without them, and no collision on any.
		var extras := ZzMap.new()
		extras.doc = (ZzMapDoc.parse_json(FileAccess.get_file_as_string(ZzPaths.rebase("res://maps/" + file))).value as Dictionary)
		var host := Node3D.new()
		extras.call(&"_attach_world_extras", world, host)
		var wanted_props := 0
		# A library model draws when the pack's model store resolves (the game's .stores link, present only
		# while a tool such as solid_props.sh holds it) and otherwise becomes a proxy, so count both worlds.
		var licence: Dictionary = manifest.get("licence", {})
		var store_root := prefix.get_base_dir().path_join(str(licence.get("model_store", "model-library"))).simplify_path()
		var in_store := {}
		for row: Dictionary in licence.get("model_stand_ins", []):
			if row.has("store_file") and FileAccess.file_exists(store_root.path_join(str(row["store_file"]))):
				in_store[str(row.get("stand_in", ""))] = true
		for rec: Dictionary in manifest.get("props", []):
			if rec.has("box") or in_store.has(str(rec.get("stand_in", ""))):
				wanted_props += 1
			elif (load(ZzMap.MESH_SCRIPT) as GDScript).call(&"find_resource", str(rec.get("stand_in", "")),
					PackedStringArray(["res://addons/dot_map/props"]), PackedStringArray([".glb", ".tscn"])) != null:
				wanted_props += 1
		var props_node := host.get_node_or_null("Props")
		# Low-detail boxes for library models this checkout lacks (dot-map's proxies) are counted apart.
		var drawn_props := 0
		var proxies := 0
		for c in (props_node.get_children() if props_node != null else []):
			if c.has_meta(&"dot_map_proxy") or c.name == &"UnseenProps":
				proxies += 1
			else:
				drawn_props += 1
		var bodies := host.find_children("*", "CollisionObject3D", true, false).size()
		_check(drawn_props == wanted_props and bodies == 0, "%s: its sounds and props attach" % id,
			"%d props drawn of %d, %d proxies, %d bodies" % [drawn_props, wanted_props, proxies, bodies])
		host.free()
		extras.free()

	_finished()


func _test_map(id: StringName) -> void:
	_section(String(id))
	var game := await _world(id)
	var doc := game.map_doc
	_check(str(doc.get("id", "")) == String(id), "it is the map that was built", str(doc.get("id", "")))

	var bytes := ZzMapDoc.encode(doc).size()
	_check(bytes > 0 and bytes < ZzMapDoc.WIRE_LIMIT, "it fits on the wire", "%d of %d bytes" % [bytes, ZzMapDoc.WIRE_LIMIT])

	var missing: PackedStringArray = game.map.get("_missing")
	_check(missing.is_empty() and game.map.props.size() == (doc["props"] as Array).size(),
		"every prop in it is one the catalogue has", ", ".join(missing))

	await _report_colliderless(id, doc)

	# The playable ground is walled in (ZzMap._build_boundary), and a ray along the ground from
	# a spawn to well past the margin on every side is stopped.
	var region: AABB = game.map.playable_region()
	var open_sides: Array = []
	if region.size == Vector3.ZERO:
		open_sides.append("no playable region")
	else:
		var space := game.get_world_3d().direct_space_state
		var origin: Vector3 = game.map.spawn("survivors", 0)[0] + Vector3(0.0, 1.0, 0.0)
		for dir: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var reach := (ZzMap.BOUNDARY_MARGIN + ZzMap.BOUNDARY_THICKNESS) + region.size.length()
			var ray := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, game.physics.layer_mask(&"boundary"))
			if space.intersect_ray(ray).is_empty():
				open_sides.append(str(dir))
	_check(open_sides.is_empty(), "the playable ground is walled in on every side", "open: %s" % [open_sides])
	# zm_4way_tunnel's wall once crossed its lower pool, which the horde's floors never reach.
	var walled_off: Array = []
	for pool: AABB in game.map.water_boxes:
		if not region.grow(0.01).encloses(pool):
			walled_off.append(str(pool))
	_check(walled_off.is_empty(), "every pool is inside the walls", "outside: %s" % [walled_off])

	var seats := ((doc.get("spawns", {}) as Dictionary).get("survivors", []) as Array).size()
	var bad_spawns: Array = []

	for seat in range(seats):
		var at: Vector3 = game.map.spawn("survivors", seat)[0]
		var why := _spawn_fault(game, at)
		if why != "":
			bad_spawns.append("%d at %s: %s" % [seat, at, why])

	_check(seats >= MIN_SPAWNS and bad_spawns.is_empty(), "%d spawns, each on a floor with room for a person" % seats,
		"; ".join(bad_spawns))

	# Spawns are not the only places a body is put: a post (a stand-in walks to it), a cache and
	# a horde spawn at ground level over a hole in a converted map is a body that falls at once.
	var airborne: Array = []

	for key in ["posts", "caches", "zombie_spawns"]:
		for point in (doc.get(key, []) as Array):
			var at: Vector3 = ZzMapDoc.v3(point)
			if at.y < 0.3 and not _over_something(game, at):
				airborne.append("%s %s" % [key, at])

	_check(airborne.is_empty(), "every ground-level post, cache and horde spawn has floor under it", "; ".join(airborne.slice(0, 6)))

	var buried: Array = []
	var floating: Array = []

	for index in range(game.map.props.size()):
		var prop: Dictionary = game.map.props[index]
		var frame: Transform3D = prop["transform"]
		var size: Vector3 = prop["size"]
		var centre := frame * Vector3(0.0, size.y * 0.5, 0.0)

		if _inside_world(game, centre):
			buried.append("%s at %s" % [prop["id"], frame.origin])

		if not _rests_on_something(game, frame, size):
			floating.append("%s at %s" % [prop["id"], frame.origin])

	_check(buried.is_empty(), "no prop is sunk into a wall or a floor", "; ".join(buried.slice(0, 6)))
	_check(floating.is_empty(), "every prop stands on something", "%d: %s" % [floating.size(), "; ".join(floating.slice(0, 6))])

	# An item is picked up by looking at it from where a person stands: over a floor or a
	# table, and not inside anything.
	var lost: Array = []

	for item: Dictionary in doc.get("items", []):
		var at := ZzMapDoc.v3(item["at"])
		if _inside_world(game, at + Vector3(0.0, 0.1, 0.0)) or not _over_something(game, at):
			lost.append("%s at %s" % [item["kind"], at])

	_check(lost.is_empty(), "every item lies where it can be picked up", "; ".join(lost.slice(0, 6)))

	# A shipped world map resolves a spawner config and lays at least one weapon site, each over a floor.
	if str(doc.get("world", "")) != "" and game.spawners != null and not FileAccess.file_exists(game.map.local_world_prefix() + ".json"):
		# world/ is never in CI; its sites come from the drawn world, so without it there is nothing to count.
		_worlds_skipped += 1
		print("  SKIP  %s: spawner and shelf checks need world/ (not linked), not counted as passed" % doc.get("id", "?"))
	elif str(doc.get("world", "")) != "" and game.spawners != null:
		_spawner_worlds += 1
		game.spawners.start_round(doc)
		var ours := {}
		for key: String in ["spawners", "traders"]:
			for raw: Variant in lay_block(game, doc).get(key, []):
				ours[StringName(str((raw as Dictionary).get("id", "")))] = true
		var lay := game.spawners.spawner
		var weapon_sites := 0
		var site_floating: Array = []
		for sid: StringName in lay.site_ids():
			var laid := lay.site(sid)
			if laid == null:
				continue
			if laid.enabled and laid.pool in [&"field_guns", &"heavy_guns", &"wall_guns", &"crate"]:
				weapon_sites += 1
			if ours.has(sid) and not _over_something(game, laid.position):
				site_floating.append("%s at %s" % [sid, laid.position])
		var shelves: int = (game.spawners.get("_traders") as Dictionary).size()
		_check(weapon_sites > 0, "it lays at least one weapon site", str(weapon_sites))
		_check(site_floating.is_empty(), "every spawner and shelf the config adds stands over something", "; ".join(site_floating.slice(0, 6)))
		_check(str(doc.get("mode", "")) == "exodus" or shelves > 0, "a survival world has a trader", str(shelves))

	# The zombies' ground, every gate open: the first spawn reaches everything that matters.
	var gates := PackedStringArray()

	for box: Dictionary in doc.get("boxes", []):
		if box.has("gate"):
			gates.append(str(box["gate"]))

	var props_size := func(pid: StringName) -> Vector3:
		return game.props_catalogue.size_of(pid) if game.props_catalogue.has(pid) else Vector3.ZERO
	var nav_doc := ZzNpcs.with_nav_extra(doc, game.map.read_nav_extra(str(game.catalogue.roots.get(StringName(str(doc.get("id", ""))), ""))))
	var open := DotNpcNavGraph.new(ZzNpcs.nav_for(nav_doc, props_size, gates))
	var shut := DotNpcNavGraph.new(ZzNpcs.nav_for(nav_doc, props_size))
	var from: Vector3 = game.map.spawn("survivors", 0)[0]
	var unreached: Array = []
	var places: Array = []

	for p: Array in doc.get("route", []):
		places.append(["route", ZzMapDoc.v3(p)])
	for o: Dictionary in doc.get("objectives", []):
		places.append(["objective %s" % o["id"], ZzMapDoc.v3(o["at"])])
	for s: Array in doc.get("sleepers", []):
		places.append(["sleeper", ZzMapDoc.v3(s)])
	for h: Array in doc.get("zombie_spawns", []):
		places.append(["spawn hint", ZzMapDoc.v3(h)])
	for area: Dictionary in (doc["areas"] as Dictionary).get("end", []):
		var end_box: AABB = ZzMapDoc.area_box(area)
		places.append(["end area", end_box.get_center() * Vector3(1.0, 0.0, 1.0) + Vector3(0.0, end_box.position.y, 0.0)])

	for place: Array in places:
		var to: Vector3 = place[1]
		to.y = _ground_y(doc, to)
		if not open.is_reachable(from, to, SNAP):
			unreached.append("%s at %s" % [place[0], to])

	_check(unreached.is_empty() and open.data.points.size() > 50, "the zombies' ground joins everything to the start",
		"%d points; %s" % [open.data.points.size(), "; ".join(unreached.slice(0, 40))])

	# A map whose wire budget cut boxes walks on the whole map's floor, not the document's.
	if (nav_doc["boxes"] as Array).size() > (doc["boxes"] as Array).size():
		_nav_extra_maps += 1
		var plain := ZzNpcs.nav_for(doc, props_size, gates)
		var floors_ok := open.data.points.size() >= plain.points.size() * 9 / 10
		_check(floors_ok, "the whole map's floor gives the horde as much ground as the document's", "%d points against %d" % [open.data.points.size(), plain.points.size()])

	# With the gates shut, what lies past them is cut off: a gate the horde walks through is
	# not one. A map without gates says so.
	var past_gates: Array = []

	if not gates.is_empty():
		for area: Dictionary in (doc["areas"] as Dictionary).get("end", []):
			var centre := ZzMapDoc.area_box(area).get_center() * Vector3(1.0, 0.0, 1.0)
			if shut.is_reachable(from, centre, SNAP):
				past_gates.append(str(centre))

	_check(past_gates.is_empty(), "its gates shut the way" if not gates.is_empty() else "it has no gates to shut",
		", ".join(gates))

	var mode_ok: bool = doc["mode"] == ZzMapDoc.SURVIVAL or not (doc["areas"]["end"] as Array).is_empty()
	var next := str(doc.get("next", ""))
	_check(mode_ok and (next == "" or game.catalogue.maps.has(StringName(next))),
		"an exodus map has an end, and its next map exists", next)

	# A survival map is held by a team: a seat for each of the team it is built for, and posts
	# and caches on the ground the team walks (the zombies' ground, which is the stand-ins' too).
	var held_ok := true
	var held_why: Array = []
	if doc["mode"] == ZzMapDoc.SURVIVAL:
		if seats < int(doc.get("survivors", 0)):
			held_ok = false
			held_why.append("%d spawns for a team of %d" % [seats, int(doc.get("survivors", 0))])
		for p: Array in doc.get("posts", []) + doc.get("caches", []):
			var at := ZzMapDoc.v3(p)  # the post's own height: a start on an upper level is not reached from the ground below it
			if not open.is_reachable(from, at, SNAP):
				held_ok = false
				held_why.append("post or cache at %s" % at)
				continue
			# The short way, not round the outside: a door whose floor does not join its two
			# rooms leaves them joined only through some other door, and the school's gym was
			# reached from the hallway beside it through the kitchen, the loading bay and the
			# car park, which is where the stand-ins went (and the horde came in).
			var route := open.find_path(from, at, SNAP, false)
			var walked := 0.0
			for i in range(1, route.size()):
				walked += route[i - 1].distance_to(route[i])
			var straight := Vector2(at.x - from.x, at.z - from.z).length()
			if walked > straight * 1.8 + 12.0:
				held_ok = false
				held_why.append("%s is %.0f m away the long way round (%.0f straight)" % [at, walked, straight])
	_check(held_ok, "a survival map seats its team, its posts and caches on the ground" if doc["mode"] == ZzMapDoc.SURVIVAL \
		else "it is not a survival map", "; ".join(held_why.slice(0, 6)))

	# Every barricade is ON the zombies' ground, both faces of it: they come to it, and once it
	# is down they come through. One cut out of the graph is a window nobody ever attacks.
	var cut: Array = []
	for entry: Dictionary in doc.get("barricades", []):
		var box: AABB = game.map.barricade_bounds(str(entry["id"]))
		var across := Vector3(0.0, 0.0, 1.2) if box.size.z < box.size.x else Vector3(1.2, 0.0, 0.0)
		var centre := box.get_center() * Vector3(1.0, 0.0, 1.0)
		if not open.is_reachable(from, centre + across, SNAP) or not open.is_reachable(from, centre - across, SNAP):
			cut.append(str(entry["id"]))
	_check(cut.is_empty(), "%d barricades, the horde's ground on both sides of each" % (doc.get("barricades", []) as Array).size(),
		", ".join(cut))

	# The toys (dot-props', loose only): all built, none inside a wall, a car or a shelf, and two
	# seconds of physics later every one still where the map put it, not through a floor.
	var box := game.map.toys
	var placed := (doc.get("toys", []) as Array).size()
	var stuck: Array = []
	var own: Array[RID] = []
	for toy in box.toys:
		if toy.body != null:
			own.append(toy.body.get_rid())
	var space := game.get_world_3d().direct_space_state
	for toy in box.toys:
		for child in toy.body.get_children():
			var shape := child as CollisionShape3D
			if shape == null or shape.shape == null:
				continue
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape.shape
			query.transform = shape.global_transform.translated(Vector3(0, 0.05, 0))
			query.collision_mask = game.ground_mask() | game.physics.layer_mask(&"prop")
			query.exclude = own
			if not space.intersect_shape(query, 1).is_empty():
				stuck.append("%s %d at %s" % [toy.def["id"], toy.index, toy.global_position.snapped(Vector3.ONE * 0.1)])
				break
	_check(box.count() == placed and placed > 0 and box.missing.is_empty() and stuck.is_empty(),
		"%d toys, every one dot-props', standing clear" % placed, "%d built; %s" % [box.count(), "; ".join(stuck.slice(0, 6))])
	for _i in range(120):
		await get_tree().physics_frame
	var strayed: Array = []
	for toy in box.toys:
		if toy.body.global_position.distance_to(toy.rest.origin) > 0.6:
			strayed.append("%s %d: %s to %s" % [toy.def["id"], toy.index, toy.rest.origin.snapped(Vector3.ONE * 0.1), toy.body.global_position.snapped(Vector3.ONE * 0.1)])
	_check(strayed.is_empty(), "two seconds on, every toy is still where the map put it", "; ".join(strayed.slice(0, 6)))
	await _dispose(game)
	_finished()


## A ray down from just over [param at] finds a floor, a table or a prop within half a metre.
func _over_something(game: ZzGame, at: Vector3) -> bool:
	var space := game.get_world_3d().direct_space_state
	var mask := game.ground_mask() | game.physics.layer_mask(&"prop")
	var query := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 0.3, 0.0), at + Vector3(0.0, -0.5, 0.0), mask)
	return not space.intersect_ray(query).is_empty()


## Why a person could not stand at [param at], or "" when they can.
func _spawn_fault(game: ZzGame, at: Vector3) -> String:
	var space := game.get_world_3d().direct_space_state
	var mask := game.ground_mask() | game.physics.layer_mask(&"prop")

	var down := PhysicsRayQueryParameters3D.create(at + Vector3(0.0, 0.5, 0.0), at + Vector3(0.0, -0.6, 0.0), mask)
	if space.intersect_ray(down).is_empty():
		return "nothing under it"

	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = mask
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, HEIGHT * 0.5 + 0.08, 0.0))

	var hits := space.intersect_shape(query, 4)

	if not hits.is_empty():
		var what: Array = []
		for hit: Dictionary in hits:
			var index := game.map.prop_from_hit(hit["collider"], int(hit["shape"]))
			what.append(String(game.map.prop_id(index)) if index >= 0 else "a wall")
		return "in the way: %s" % ", ".join(what)

	return ""


func _inside_world(game: ZzGame, point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.collision_mask = game.physics.layer_mask(&"world")
	return not game.get_world_3d().direct_space_state.intersect_point(query, 1).is_empty()


## A ray down from just inside the prop's base finds a floor, a table or another prop within
## a few centimetres. A tilted prop is tested from its lowest corner's height.
func _rests_on_something(game: ZzGame, frame: Transform3D, size: Vector3) -> bool:
	var space := game.get_world_3d().direct_space_state
	var mask := game.ground_mask() | game.physics.layer_mask(&"prop")
	var base := frame.origin

	for x in [-0.3, 0.0, 0.3]:
		for z in [-0.3, 0.0, 0.3]:
			var from := frame * Vector3(size.x * x, 0.04, size.z * z)
			var query := PhysicsRayQueryParameters3D.create(from, Vector3(from.x, base.y - 0.12, from.z), mask)
			query.hit_from_inside = false
			if not space.intersect_ray(query).is_empty():
				return true

	return false


func _world(id: StringName, drawn := false) -> ZzGame:
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray([String(id)]) if id != &"" else PackedStringArray()

	var game := ZzGame.new()
	game.name = "World_%s" % String(id)
	game.config = config
	game.tick_rate = 60
	game.authoritative = true
	game.draw_world = drawn
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return game


## dot-core's [DotCollisionAudit] over the map as a client draws it. The map keeps its drawing
## in `Drawn` (batched into chunks) and its shapes in `Solid`, so the audit is the lenient one;
## the exact half is the document: a visible box that is not solid is drawn and walked through.
func _report_colliderless(id: StringName, doc: Dictionary) -> void:
	var drawn := await _world(id, true)
	var res := DotCollisionAudit.audit(drawn.map, true)
	var ghosts: Array = []

	for box: Dictionary in doc["boxes"]:
		if bool(box.get("visible", true)) and not bool(box.get("solid", true)):
			ghosts.append(str(box.get("mat", "")))

	if res.ok:
		var report: DotCollisionAudit = res.value
		print("  collision audit: %d meshes with no shape near them of %d, %d visible boxes not solid" % [report.count(), report.examined, ghosts.size()])

		for line in report.describe_lines().slice(1, 8):
			print("  %s" % line)

	var found: PackedStringArray = (res.value as DotCollisionAudit).paths() if res.ok else PackedStringArray()
	_check(res.ok and (res.value as DotCollisionAudit).examined > 0 and found.is_empty(),
		"everything drawn has collision, or says it is decoration (dot_no_collision)", "; ".join(found.slice(0, 6)) if res.ok else res.error.message)
	await _dispose(drawn)
	# Both worlds share one physics space: let the server drop the drawn one's bodies before the
	# checks that follow ask it about the same spot.
	await get_tree().physics_frame


func _dispose(game: ZzGame) -> void:
	remove_child(game)
	game.free()
	await get_tree().process_frame


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	var line := "%s%s" % [what, "" if detail == "" else "  (%s)" % detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


## The `game:` block of the spawner config the map resolved to (its traders and spawners).
func lay_block(game: ZzGame, _doc: Dictionary) -> Dictionary:
	return game.spawners.spawner.game_block()
