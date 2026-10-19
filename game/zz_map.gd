extends Node3D

const ZzMapDoc := preload("zz_map_doc.gd")
const ZzMaterials := preload("zz_materials.gd")
const ZzProps := preload("zz_props.gd")
const ZzFixtures := preload("zz_fixtures.gd")
const ZzPaths := preload("zz_paths.gd")

## A map document, built: the building, the furniture, the lights and the sky.
##
## [b]The same document on every machine, and a server builds only what collides.[/b] Boxes
## become one static body of box shapes on the world layer; props become one static body of
## box shapes on the prop layer, each shape knowing which prop it is. A client also draws them.
## A server draws nothing, so a dedicated server holds a few thousand shapes and no meshes.
##
## [b]Boxes are drawn batched, by material and by twelve-metre chunk.[/b] A school is a
## thousand boxes, and a mesh per box is a thousand draw calls, which a browser does not give
## you. One mesh per material is the other extreme and is wrong for a reason only the renderer
## knows: the compatibility renderer the shell uses lights each mesh with at most eight omni
## lights, so one floor mesh for the whole school would be lit by eight of its forty lamps and
## every other room would be dark. A chunk is about a room, which is about a lamp.
##
## [b]Props are drawn as [MultiMeshInstance3D]s, one per model mesh.[/b] Two hundred chairs are
## one draw call per chair mesh, not two hundred. They never move.
##
## [b]A prop's collision is its catalogue pieces (or its box), turned the way the map turns
## it.[/b] A tree is its trunk, branches and leaf clumps, a table its top and legs (dot-props'
## [DotPropPieces], measured offline into `props/pieces.json`). What a shot stops on and what a
## player walks into are the same shapes, so the two can never disagree about where the car is;
## a zombie still paths round the prop's box, which only keeps it further off.
##
## [b]A gate's boxes are kept apart[/b] (`_gates`), with their own body and mesh, so that an
## objective opening a gate takes it away whole. [b]So are a barricade's[/b] (`_barricades`),
## which come and go: broken by the horde, mended by the survivors ([method set_barricade]),
## and drawn darker as they weaken so a defender sees which window is about to go.
##
## [b]Baked light, where the game ships a bake for the map[/b] (`lightmaps/<id>.res`, made by
## `tools/bake_lightmaps.sh`; dot-lighting's [DotLightBake]). Every opaque box batch carries a
## second UV set ([DotLightmapSheet]) and a name that is the same on every build (`Boxes_<n>`),
## because the bake names its meshes by path and was made from this same code. A bake whose
## fingerprint ([method light_fingerprint]) is not this document's is stale and refused with a
## WARN; with none, or refused, the lamps light the map live, as before bakes existed. Baked,
## the lamps turn `BAKE_STATIC`: they no longer light the boxes (the lightmap does, with their
## shadows and bounce) but still light every zombie, survivor and prop. The moon or sun stays
## live (a hold's day turns it) and only its bounce is baked. Gates, barricades, glass, water and
## the props are not in the bake. A server never loads one ([member draw_world] is false).

const CHANNEL := "zz.map"

## Metres of world one batched mesh covers. See the class notes.
const CHUNK := 12.0

## A shot's impact closer than this to a prop's box counts as hitting it: a bullet stops on the
## surface, and a point exactly on a face is outside a strict test half the time.
const HIT_MARGIN := 0.06

## How much deeper than drawn a ground slab collides (see `_build_boxes`).
const GROUND_DEPTH := 1.8

## What a bake of this game's maps means beyond the document (which boxes and lights are in it,
## its settings in tools/lightmap_scenes.gd). Bump it and every committed bake reads as stale.
const BAKE_VERSION := 1

## Where a map's bake is, by id; rebased, so a delivered pack finds its own.
const BAKE_PATH := "res://lightmaps/%s.res"

## Whether a client looks for a map's bake at all. Off draws every map with live lamps.
static var use_bakes: bool = true

signal built()

var physics: DotPhysicsLayout = null

## The catalogue every prop's size and model come from.
var catalogue: ZzProps = null

## Whether this machine draws anything: a client does, a server does not.
var draw_world: bool = false

## The normalised document this was built from.
var doc: Dictionary = {}

## Every prop in the map: `{id, transform, size, shapes}`. The transform's origin is the middle
## of the prop's footprint on the floor.
var props: Array[Dictionary] = []

## gate id -> {body: StaticBody3D, drawn: Array[Node]}: the boxes an objective opens, kept apart
## from the rest so they can be taken away whole.
var _gates: Dictionary = {}

## barricade id -> {body, shapes: Array[CollisionShape3D], drawn: Array[MeshInstance3D], bounds:
## AABB, mat, tint, intact, fraction}.
var _barricades: Dictionary = {}

## The map's toys (dot-props' [DotPropToyBox]): loose ones only on this game's maps (barrels,
## tyres, balls, pins), simulated where [member authoritative], posed from snapshots elsewhere,
## under the game's `sv_toys*` [member toy_rules]. Set by the game before it builds.
var toys: DotPropToyBox = null
var authoritative: bool = true
var toy_rules: DotPropToyRules = null
var gravity: float = 20.0

var _solid: StaticBody3D = null
var _furniture: StaticBody3D = null
var _drawn: Node3D = null
var _environment: WorldEnvironment = null
var _sun: DirectionalLight3D = null
## dot-lighting's fill (painted()), turned with the sun; blended with it by set_daylight.
var _fill: DirectionalLight3D = null

## A map held by nights draws its day as well: the light at night (the map's own) and by day,
## captured once as the properties [method set_daylight] blends between. Empty: no day.
var _night_light: Dictionary = {}
var _day_light: Dictionary = {}
var _daylight: float = 0.0
var _bounds: AABB = AABB()
var _missing: PackedStringArray = PackedStringArray()
var _lamps: Array[OmniLight3D] = []
## The LightmapGI laid over this map, or null: drawn with live lamps.
var baked: LightmapGI = null


func id() -> StringName:
	return StringName(str(doc.get("id", "")))


## Builds [param p_doc], which [ZzMapDoc.validate] has already normalised.
func build(p_doc: Dictionary) -> DotResult:
	clear()
	doc = p_doc

	_solid = StaticBody3D.new()
	_solid.name = "Solid"
	add_child(_solid)
	_put_on(_solid, &"world")

	_furniture = StaticBody3D.new()
	_furniture.name = "Furniture"
	add_child(_furniture)
	_put_on(_furniture, &"prop")

	if draw_world:
		_drawn = Node3D.new()
		_drawn.name = "Drawn"
		add_child(_drawn)

	_build_boxes()
	_build_props()
	_build_toys()

	if draw_world:
		_build_objective_props()
		_build_lights()
		_build_environment()
		if use_bakes:
			_attach_bake()

	if not _missing.is_empty():
		DotLog.warn(CHANNEL, "a map names props this server's catalogue does not have; they are left out", {
			"map": String(id()), "missing": ", ".join(_missing),
		})

	DotLog.debug(CHANNEL, "built a map", {
		"id": String(id()), "boxes": (doc["boxes"] as Array).size(), "props": props.size(),
	})
	built.emit()
	return DotResult.success(null)


## The toys, on their own layer: a loose one (a barrel, a ball) on `toy`, which the world, the
## furniture and other toys stop and a survivor or a zombie never does (they walk through it,
## and a survivor pushes it, `ZzGame._advance_toys`).
func _build_toys() -> void:
	toys = DotPropToyBox.new()
	toys.name = "Toys"
	toys.authoritative = authoritative
	toys.draw = draw_world
	if toy_rules != null:
		toys.rules = toy_rules
	toys.gravity = gravity
	toys.kill_y = kill_height()
	if physics != null:
		toys.loose_layer = physics.layer_mask(&"toy")
		toys.loose_mask = physics.collision_mask(&"toy")
		toys.solid_layer = physics.layer_mask(&"prop")
		toys.solid_mask = physics.collision_mask(&"prop")
		toys.footprint_layer = physics.layer_mask(&"footprint")
		toys.aim_mask = physics.layer_mask(&"world") | physics.layer_mask(&"prop") | physics.layer_mask(&"toy") | physics.layer_mask(&"barricade")
	add_child(toys)
	var built := toys.build(doc.get("toys", []))
	if not built.ok:
		DotLog.warn(CHANNEL, "a map's toys would not build", {"map": String(id()), "why": built.error.message})


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	props.clear()
	_gates.clear()
	_barricades.clear()
	_missing.clear()
	_bounds = AABB()
	_lamps.clear()
	baked = null
	toys = null
	_solid = null
	_furniture = null
	_drawn = null
	_environment = null
	_sun = null
	_fill = null
	_night_light = {}
	_day_light = {}
	_daylight = 0.0


func _put_on(body: CollisionObject3D, layer: StringName) -> void:
	if physics == null:
		return

	var applied := physics.apply_to(body, layer)

	if not applied.ok:
		DotLog.warn(CHANNEL, "a map body could not be put on its layer", {"layer": String(layer)})


# --- Building --------------------------------------------------------------

func _build_boxes() -> void:
	var batches := {}
	var any := false

	for box: Dictionary in doc["boxes"]:
		var size := ZzMapDoc.v3(box["size"])
		var at := ZzMapDoc.v3(box["at"])
		var frame := Transform3D(Basis(Vector3.UP, deg_to_rad(float(box.get("yaw", 0.0)))), at)

		var corner := AABB(at - size * 0.5, size)
		_bounds = corner if not any else _bounds.merge(corner)
		any = true

		if box.has("gate"):
			_add_gate_box(str(box["gate"]), box, frame, size)
			continue

		if box.has("barricade"):
			_add_barricade_box(str(box["barricade"]), box, frame, size, corner)
			continue

		if bool(box.get("solid", true)):
			var shape := CollisionShape3D.new()
			var cube := BoxShape3D.new()
			cube.size = size
			shape.shape = cube
			shape.transform = frame

			# A ground slab (its top at the ground, thin) collides GROUND_DEPTH deep, drawn as
			# it is: a body pushed into a 0.2 m slab past its middle was pushed out of the
			# bottom, and nothing is under the ground (zz-mall-floor-falls-1).
			var top := at.y + size.y * 0.5
			if absf(top) < 0.05 and size.y <= 0.5:
				cube.size.y = size.y + GROUND_DEPTH
				shape.transform.origin.y -= GROUND_DEPTH * 0.5
			# What a footstep on it sounds like (dot-audio's DotAudioFootsteps reads the hit
			# shape's meta; "wood_floor", "asphalt" and the rest fold onto its surfaces).
			shape.set_meta(&"surface", str(box.get("mat", "")))
			_solid.add_child(shape)

		if not draw_world or not bool(box.get("visible", true)):
			continue

		if str(box.get("look", "")) == "chain_link":
			_drawn.add_child(ZzFixtures.chain_link(frame, size))
			continue

		var tint := ZzMapDoc.colour(box.get("tint", [1, 1, 1]))
		var cell := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
		# Seen and not hit (a road marking, a decal, a lamp's bulb, water) is batched apart from
		# the solid boxes, so the whole chunk can say it is meant to be walked through.
		var ghost := not bool(box.get("solid", true))
		var key := "%s|%s|%d|%d|%s" % [str(box["mat"]), tint.to_html(), cell.x, cell.y, ghost]

		if not batches.has(key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Baked light falls on what is solid and opaque; a decal, a bulb, water and glass
			# are drawn live (and the bake sees through them).
			var bakeable := not ghost and not ZzMaterials.is_transparent(str(box["mat"]))
			batches[key] = {"tool": tool, "mat": str(box["mat"]), "tint": tint, "ghost": ghost,
				"sheet": DotLightmapSheet.new() if bakeable else null}

		var batch_of: Dictionary = batches[key]
		if batch_of["sheet"] != null:
			_add_box_faces(batch_of["sheet"], frame, size)
		else:
			_add_box(batch_of["tool"], frame, size)

	var index := 0

	for key: String in batches:
		var batch: Dictionary = batches[key]
		var tool: SurfaceTool = batch["tool"]
		var sheet: DotLightmapSheet = batch["sheet"]
		if sheet != null:
			sheet.commit(tool)
		var mesh := MeshInstance3D.new()
		# The same name on every build of this document: a bake finds its meshes by path.
		mesh.name = "Boxes_%d" % index
		index += 1
		# dot-core's DotCollisionAudit: a chunk of `"solid": false` boxes is decoration by the
		# map's own say-so, and a player is meant to walk through it.
		if bool(batch["ghost"]):
			mesh.set_meta(&"dot_no_collision", true)
		var arrays := tool.commit()
		if sheet != null:
			arrays.lightmap_size_hint = sheet.size
			mesh.set_meta(&"zz_bakeable", true)
		mesh.mesh = arrays
		mesh.material_override = ZzMaterials.material(batch["mat"], batch["tint"])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
			if ZzMaterials.is_transparent(batch["mat"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_drawn.add_child(mesh)


## A box that belongs to a gate: its own body, its own mesh, so opening the gate removes it whole.
func _add_gate_box(gate: String, box: Dictionary, frame: Transform3D, size: Vector3) -> void:
	if not _gates.has(gate):
		var body := StaticBody3D.new()
		body.name = "Gate_%s" % gate
		add_child(body)
		_put_on(body, &"world")
		_gates[gate] = {"body": body, "drawn": []}

	var entry: Dictionary = _gates[gate]

	if bool(box.get("solid", true)):
		var shape := CollisionShape3D.new()
		var cube := BoxShape3D.new()
		cube.size = size
		shape.shape = cube
		shape.transform = frame
		(entry["body"] as StaticBody3D).add_child(shape)

	if draw_world and bool(box.get("visible", true)):
		var drawn: Node3D = null
		if str(box.get("look", "")) == "chain_link":
			drawn = ZzFixtures.chain_link(frame, size)
		else:
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			_add_box(tool, frame, size)
			var mesh := MeshInstance3D.new()
			mesh.mesh = tool.commit()
			mesh.material_override = ZzMaterials.material(str(box["mat"]), ZzMapDoc.colour(box.get("tint", [1, 1, 1])))
			drawn = mesh
		drawn.name = "Gate_%s" % gate
		_drawn.add_child(drawn)
		(entry["drawn"] as Array).append(drawn)


## The objectives' pictures ([ZzFixtures]): a padlock hangs on the gate its objective opens and
## goes with it, a lever or a radio stands where the objective is.
func _build_objective_props() -> void:
	for o: Dictionary in doc.get("objectives", []):
		var gate_id := ""
		var gate_box := {}
		for opens: String in (o.get("opens", PackedStringArray()) as PackedStringArray):
			for box: Dictionary in doc["boxes"]:
				if str(box.get("gate", "")) == opens:
					gate_id = opens
					gate_box = box
					break
			if gate_id != "":
				break

		var drawn := ZzFixtures.objective_prop(o, gate_box if str(o.get("prop", "")) == "padlock" else {})
		if drawn == null:
			continue
		# dot-core's DotCollisionAudit: a padlock hangs on a gate that has its own body, a lever
		# or a radio is something you reach and use. None of them should stop a survivor.
		drawn.set_meta(&"dot_no_collision", true)
		_drawn.add_child(drawn)
		if str(o.get("prop", "")) == "padlock" and _gates.has(gate_id):
			((_gates[gate_id] as Dictionary)["drawn"] as Array).append(drawn)


## A box that belongs to a barricade: its own body (one per barricade) and its own mesh.
func _add_barricade_box(id: String, box: Dictionary, frame: Transform3D, size: Vector3, bounds: AABB) -> void:
	if not _barricades.has(id):
		var body := StaticBody3D.new()
		body.name = "Barricade_%s" % id
		add_child(body)
		# Its own layer: a survivor's mask may leave it out (zz_pass_barricades); the horde's and
		# every ray's keep it.
		_put_on(body, &"barricade")
		_barricades[id] = {"body": body, "shapes": [], "drawn": [], "bounds": bounds, "intact": true, "fraction": 1.0}

	var entry: Dictionary = _barricades[id]
	entry["bounds"] = (entry["bounds"] as AABB).merge(bounds)
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = size
	shape.shape = cube
	shape.transform = frame
	(entry["body"] as StaticBody3D).add_child(shape)
	(entry["shapes"] as Array).append(shape)

	if draw_world and bool(box.get("visible", true)):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_add_box(tool, frame, size)
		var mesh := MeshInstance3D.new()
		mesh.name = "Barricade_%s" % id
		mesh.mesh = tool.commit()
		var tint := ZzMapDoc.colour(box.get("tint", [1, 1, 1]))
		mesh.material_override = ZzMaterials.material(str(box["mat"]), tint)
		mesh.set_meta(&"zz_mat", str(box["mat"]))
		mesh.set_meta(&"zz_tint", tint)
		_drawn.add_child(mesh)
		(entry["drawn"] as Array).append(mesh)


## Every barricade's id, in the order the map lists its boxes.
func barricade_ids() -> PackedStringArray:
	return PackedStringArray(_barricades.keys())


## The space a barricade's boxes fill, or an empty AABB.
func barricade_bounds(id: String) -> AABB:
	var entry: Variant = _barricades.get(id)
	return (entry as Dictionary)["bounds"] if entry != null else AABB()


func barricade_intact(id: String) -> bool:
	var entry: Variant = _barricades.get(id)
	return entry != null and bool((entry as Dictionary)["intact"])


## Puts a barricade up or takes it down, collision and picture, and shades what stands by
## [param fraction] of its strength: whole is the wood's own colour, a quarter is near black.
## Collision is switched deferred: this is called from inside the physics tick.
func set_barricade(id: String, intact: bool, fraction: float) -> void:
	var entry: Variant = _barricades.get(id)

	if entry == null:
		return

	var e := entry as Dictionary
	var was := bool(e["intact"])
	e["intact"] = intact
	e["fraction"] = fraction

	if was != intact:
		for shape: CollisionShape3D in e["shapes"]:
			if is_instance_valid(shape):
				shape.set_deferred(&"disabled", not intact)

	var shade := lerpf(0.3, 1.0, clampf(fraction, 0.0, 1.0))

	for mesh: MeshInstance3D in e["drawn"]:
		if not is_instance_valid(mesh):
			continue
		mesh.visible = intact
		var tint: Color = mesh.get_meta(&"zz_tint", Color.WHITE)
		# Three steps, not a material per percent: a few shared materials, never one per hit.
		var step := snappedf(shade, 0.233)
		mesh.material_override = ZzMaterials.material(str(mesh.get_meta(&"zz_mat", "wood")),
			Color(tint.r * step, tint.g * step, tint.b * step))


## Takes a gate's boxes away: collision and picture.
func open_gate(gate: String) -> void:
	var entry: Variant = _gates.get(gate)

	if entry == null:
		return

	_gates.erase(gate)
	var body: StaticBody3D = (entry as Dictionary)["body"]

	if is_instance_valid(body):
		body.queue_free()

	for node: Node in (entry as Dictionary)["drawn"]:
		if is_instance_valid(node):
			node.queue_free()


func gate_is_shut(gate: String) -> bool:
	return _gates.has(gate)


## Whether [param point] is inside any of the map's [param side] areas (`start`, `end`).
func in_area(side: String, point: Vector3) -> bool:
	for area: Dictionary in (doc.get("areas", {}) as Dictionary).get(side, []):
		if ZzMapDoc.area_box(area).grow(0.05).has_point(point + Vector3(0.0, 0.1, 0.0)):
			return true

	return false


## Six faces of a box, outward normals, into [param tool]. No UVs: every surface material is
## mapped in world space.
static func _add_box(tool: SurfaceTool, frame: Transform3D, size: Vector3) -> void:
	for face: Array in _box_faces(frame, size):
		# Godot's front face winds so that (b - a) x (c - a) points AGAINST the normal (measured
		# against BoxMesh's own arrays). The corners above go round the other way, so each
		# triangle is emitted reversed; the other order is a map drawn inside out, every wall
		# invisible from the room it bounds.
		for v: Vector3 in [face[1], face[3], face[2], face[1], face[4], face[3]]:
			tool.set_normal(face[0])
			tool.add_vertex(v)


## The same six faces into a lightmap sheet, which writes them with the same winding plus UV2.
static func _add_box_faces(sheet: DotLightmapSheet, frame: Transform3D, size: Vector3) -> void:
	for face: Array in _box_faces(frame, size):
		sheet.face(face[1], face[2], face[3], face[4], face[0])


## `[normal, a, b, c, d]` per face, in world space: a to b up the face, a to d across it.
static func _box_faces(frame: Transform3D, size: Vector3) -> Array:
	var out := []
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.BACK, Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		[Vector3.FORWARD, Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)],
	]

	for face: Array in faces:
		out.append([frame.basis * (face[0] as Vector3), frame * (face[1] as Vector3),
			frame * (face[2] as Vector3), frame * (face[3] as Vector3), frame * (face[4] as Vector3)])

	return out


func _build_props() -> void:
	var by_id := {}

	for raw: Dictionary in doc["props"]:
		var prop_id := StringName(str(raw["id"]))

		if catalogue == null or not catalogue.has(prop_id):
			if not _missing.has(String(prop_id)):
				_missing.append(String(prop_id))
			continue

		var size := catalogue.size_of(prop_id)
		var basis := Basis.from_euler(Vector3(
			deg_to_rad(float(raw.get("pitch", 0.0))),
			deg_to_rad(float(raw.get("yaw", 0.0))),
			deg_to_rad(float(raw.get("roll", 0.0)))
		), EULER_ORDER_YXZ)
		var frame := Transform3D(basis, ZzMapDoc.v3(raw["at"]))

		# Its pieces (a tree's trunk, branches and clumps), or its box when it has none.
		var shapes: Array = []

		for part: Array in catalogue.shapes_of(prop_id):
			var shape := CollisionShape3D.new()
			shape.shape = part[0]
			shape.transform = frame * (part[1] as Transform3D)
			shape.set_meta(&"zz_prop", props.size())
			_furniture.add_child(shape)
			shapes.append(shape)

		props.append({"id": prop_id, "transform": frame, "size": size, "shapes": shapes})

		if draw_world:
			if not by_id.has(prop_id):
				by_id[prop_id] = []
			(by_id[prop_id] as Array).append(frame)

	if not draw_world:
		return

	for prop_id: StringName in by_id:
		var frames: Array = by_id[prop_id]
		var parts := catalogue.parts(prop_id)

		if parts.is_empty():
			for frame: Transform3D in frames:
				var stand_in := catalogue.instance(prop_id)
				stand_in.transform = frame
				_drawn.add_child(stand_in)
			continue

		for part: Array in parts:
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = part[0]
			multi.instance_count = frames.size()

			for i in range(frames.size()):
				multi.set_instance_transform(i, (frames[i] as Transform3D) * (part[1] as Transform3D))

			var drawn := MultiMeshInstance3D.new()
			drawn.name = "Props_%s" % String(prop_id)
			drawn.multimesh = multi
			_drawn.add_child(drawn)


func _build_lights() -> void:
	for light: Dictionary in doc["lights"]:
		var omni := OmniLight3D.new()
		omni.position = ZzMapDoc.v3(light["at"])
		omni.omni_range = float(light["range"])
		omni.light_energy = float(light["energy"])
		omni.light_color = ZzMapDoc.colour(light["colour"])
		omni.omni_attenuation = 1.2
		omni.shadow_enabled = false
		_drawn.add_child(omni)
		_lamps.append(omni)


## What this map's bake must have been made from: the boxes, the lamps and the sky, and the
## versions of everything that lays them out. The same on the machine that baked and on every
## client, from the document alone.
func light_fingerprint() -> String:
	return DotLightBake.fingerprint({
		"zz": BAKE_VERSION, "boxes": doc.get("boxes", []), "lights": doc.get("lights", []),
		"environment": doc.get("environment", {}),
	})


## The map's bake laid over it, if the game ships one made from this document.
func _attach_bake() -> void:
	var path := ZzPaths.rebase(BAKE_PATH % String(id()))
	var res := DotLightBake.attach(self, path, light_fingerprint())

	if not res.ok:
		return

	baked = res.value
	for lamp in _lamps:
		lamp.light_bake_mode = Light3D.BAKE_STATIC
	DotLog.debug(CHANNEL, "the map is drawn with its baked light", {"map": String(id())})


## The lamps, for the bake scene and the suites.
func lamps() -> Array[OmniLight3D]:
	return _lamps


## The sky, the moon or the low sun, and the fill: a dot-lighting document made from the map's
## `environment` ([method light_document]), so every map has the family's light (filmic tone
## map, soft shadows, glow only from the lamps) while keeping its own hour: the blackout
## streets, the depot, the chapel and the lot stay night under a blue moon, the pier stays
## dusk under an orange sun on the horizon.
func _build_environment() -> void:
	var env_doc: Dictionary = doc["environment"]
	var lighting := Node3D.new()
	lighting.name = "Lighting"
	add_child(lighting)
	_sun = DotLightRig.apply(lighting, DotLightDocument.from_dictionary(light_document(env_doc)),
		light_profile(float(env_doc["ambient_energy"])))

	if _sun != null:
		# The map's own angle, in Godot's degrees as the map document has always written it,
		# rather than through dot-lighting's source convention.
		_sun.rotation_degrees = Vector3(float(env_doc["sun_pitch"]), float(env_doc["sun_yaw"]), 0.0)
		_fill = _aim_fill(lighting, env_doc, _sun)
		_sun.shadow_blur = 1.5
		_sun.directional_shadow_max_distance = 60.0
		# The rig never draws a sun under 0.35, a floor for daylight worlds; a night map's
		# moon there lit every street like an overcast afternoon. The map's own strength, on
		# the rig's curve, without the floor.
		var profile := light_profile(float(env_doc["ambient_energy"]))
		var brightness := float(light_document(env_doc)["sun"]["brightness"])
		_sun.light_energy = clampf(sqrt(brightness / profile.brightness_reference), 0.0, 2.0)

	for node in lighting.get_children():
		if node is WorldEnvironment:
			_environment = node as WorldEnvironment
			var sky := (node as WorldEnvironment).environment.sky
			if sky != null and sky.sky_material is ProceduralSkyMaterial:
				# The map's own zenith (the rig draws it in the fill colour, a pale grey chosen
				# for the shade, which turned the night sky to dusk) and its ground below.
				var material := sky.sky_material as ProceduralSkyMaterial
				material.sky_top_color = ZzMapDoc.colour(env_doc["sky_top"])
				material.ground_bottom_color = ZzMapDoc.colour(env_doc["ground"])
				if is_night(env_doc):
					_dress_night_sky(material, _sun)

	if str(doc.get("mode", "")) == ZzMapDoc.SURVIVAL:
		_capture_day()


## What [method set_daylight] blends: the sun, the fill, the fog and the sky.
const LIGHT_KEYS := [
	"sun:light_energy", "sun:light_color", "sun:rotation_degrees",
	"env:ambient_light_color", "env:ambient_light_energy", "env:fog_light_color", "env:fog_depth_begin",
	"env:fog_depth_end", "env:fog_density", "sky:sky_top_color", "sky:sky_horizon_color",
	"sky:ground_horizon_color", "sky:ground_bottom_color", "sky:sky_cover_modulate", "sky:sun_angle_max",
	"fill:light_energy", "fill:light_color", "fill:rotation",
]


## A map's sky is night when its zenith is this dark (every blackout street, the holds' nights).
const NIGHT_SKY_LUMINANCE := 0.12

## The night sky's zenith and horizon as drawn. The map's own (0.02 and 0.07) are right for
## the fog and the fill, which they still set, but drawn they are black: the first play test
## (2026-10-11) saw "a black void above the alley" in every frame, the walls' tops cut against
## nothing. Drawn here: a deep blue overhead, the glow of a dead city low down, so a roofline
## reads, and stars and a moon in it.
const NIGHT_ZENITH := Color(0.035, 0.05, 0.12)
const NIGHT_HORIZON := Color(0.15, 0.15, 0.22)

## How many stars, and the cover's size (equirectangular: the top half is the sky).
const STARS := 1400
const STAR_MAP := Vector2i(2048, 1024)

static var _star_maps: Dictionary = {}


static func is_night(env_doc: Dictionary) -> bool:
	return ZzMapDoc.colour(env_doc["sky_top"]).get_luminance() < NIGHT_SKY_LUMINANCE \
		and float(env_doc["sun_energy"]) < 0.4


## Stars and the moon on the sky's cover. Only what is drawn: the fog keeps the map's horizon
## and the fill its ambient. The moon is painted where the map's (dim) sun shines from: the
## sky's own disc is the light's colour times its energy, and a moon at a twelfth of a sun's
## energy drew nothing at all.
func _dress_night_sky(material: ProceduralSkyMaterial, moon: DirectionalLight3D) -> void:
	material.sky_top_color = NIGHT_ZENITH.lerp(material.sky_top_color, 0.3)
	material.sky_horizon_color = NIGHT_HORIZON
	material.ground_horizon_color = NIGHT_HORIZON
	material.sky_curve = 0.12
	material.sun_angle_max = 0.0
	var towards := Vector3.ZERO if moon == null else moon.global_transform.basis.z.normalized()
	if moon != null and not moon.is_inside_tree():
		towards = moon.transform.basis.z.normalized()
	material.sky_cover = star_map(towards)
	material.sky_cover_modulate = Color(1.0, 1.0, 1.0, 0.9)


## The stars (seeded, so every machine draws the same sky; brighter ones rarer, a few two
## pixels wide) and a moon towards [param moon_from] (none when zero), built once per moon
## direction per process.
static func star_map(moon_from: Vector3 = Vector3.ZERO) -> ImageTexture:
	var key := "%.2f,%.2f,%.2f" % [moon_from.x, moon_from.y, moon_from.z]
	if _star_maps.has(key):
		return _star_maps[key]

	var image := Image.create(STAR_MAP.x, STAR_MAP.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011

	for i in STARS:
		var x := rng.randi_range(0, STAR_MAP.x - 2)
		# The top 44 % of the map, which is above the horizon, thinning towards it.
		var y := int(pow(rng.randf(), 1.4) * float(STAR_MAP.y) * 0.44)
		var bright := pow(rng.randf(), 3.0) * 0.85 + 0.15
		var tint := Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.92, 0.8), rng.randf())
		var star := Color(tint.r, tint.g, tint.b, bright)
		image.set_pixel(x, y, star)
		if bright > 0.7:
			image.set_pixel(x + 1, y, Color(star, bright * 0.6))
			image.set_pixel(x, mini(y + 1, STAR_MAP.y - 1), Color(star, bright * 0.6))

	if moon_from.y > 0.05:
		_paint_moon(image, moon_from.normalized())

	var texture := ImageTexture.create_from_image(image)
	_star_maps[key] = texture
	return texture


## Where a direction lands on the equirectangular cover, in pixels. Measured from frames (a
## disc painted by the textbook `atan2(x, -z)` came out on the opposite side of the sky).
static func sky_pixel(direction: Vector3) -> Vector2:
	var u := atan2(-direction.x, direction.z) / TAU + 0.5
	var v := acos(clampf(direction.y, -1.0, 1.0)) / PI
	return Vector2(u * float(STAR_MAP.x), v * float(STAR_MAP.y))


## A pale disc a degree and a half across, a little shading on one side, in a wide faint halo.
static func _paint_moon(image: Image, direction: Vector3) -> void:
	var centre := sky_pixel(direction)
	var per_degree := float(STAR_MAP.x) / 360.0
	# A row of the map is a circle of latitude: shorter towards the top, so the disc is
	# drawn wider in pixels by 1 / cos(latitude) to stay round.
	var widen := 1.0 / maxf(cos(asin(clampf(direction.y, -1.0, 1.0))), 0.2)
	var disc := 1.6 * per_degree
	var halo := 9.0 * per_degree

	for dy in range(-int(halo), int(halo) + 1):
		for dx in range(-int(halo * widen), int(halo * widen) + 1):
			var px := int(centre.x) + dx
			var py := int(centre.y) + dy
			if py < 0 or py >= STAR_MAP.y:
				continue
			px = posmod(px, STAR_MAP.x)
			var r := Vector2(float(dx) / widen, float(dy)).length()
			var colour := Color(0.0, 0.0, 0.0, 0.0)
			if r <= disc:
				var shade := 1.0 - 0.18 * clampf((float(dx) / widen + float(dy) * 0.4) / disc, 0.0, 1.0)
				colour = Color(0.93 * shade, 0.95 * shade, 1.0 * shade, 1.0)
			elif r <= halo:
				var t := 1.0 - (r - disc) / (halo - disc)
				colour = Color(0.7, 0.78, 1.0, 0.22 * t * t)
			else:
				continue
			image.set_pixel(px, py, colour)


## The day of a map held by nights: its `day_environment`, or a plain overcast morning over
## the same ground. Built beside the night once, so a dawn is a blend and never a rebuild.
func _capture_day() -> void:
	if _sun == null or _environment == null:
		return

	_night_light = _light_values(_sun, _environment, _fill)
	var day_doc: Dictionary = doc.get("day_environment", ZzMapDoc.DEFAULT_ENV)
	var scratch := Node3D.new()
	var day_sun := DotLightRig.apply(scratch, DotLightDocument.from_dictionary(light_document(day_doc)),
		light_profile(float(day_doc["ambient_energy"])))
	var day_env: WorldEnvironment = null

	for node in scratch.get_children():
		if node is WorldEnvironment:
			day_env = node as WorldEnvironment

	if day_sun != null and day_env != null:
		var sky := day_env.environment.sky
		if sky != null and sky.sky_material is ProceduralSkyMaterial:
			(sky.sky_material as ProceduralSkyMaterial).sky_top_color = ZzMapDoc.colour(day_doc["sky_top"])
			(sky.sky_material as ProceduralSkyMaterial).ground_bottom_color = ZzMapDoc.colour(day_doc["ground"])
			# The stars fade out by day rather than switching off: the day is the night's
			# cover at no strength, and a dawn blends between the two.
			(sky.sky_material as ProceduralSkyMaterial).sky_cover_modulate = Color(1.0, 1.0, 1.0, 0.0)
		day_sun.rotation_degrees = Vector3(float(day_doc["sun_pitch"]), float(day_doc["sun_yaw"]), 0.0)
		var day_fill := _aim_fill(scratch, day_doc, day_sun)
		var profile := light_profile(float(day_doc["ambient_energy"]))
		var brightness := float(light_document(day_doc)["sun"]["brightness"])
		day_sun.light_energy = clampf(sqrt(brightness / profile.brightness_reference), 0.0, 2.0)
		_day_light = _light_values(day_sun, day_env, day_fill)

	scratch.free()


## The rig's Fill under [param lighting], aimed away from [param sun] as the map turned it: the
## rig aimed it opposite the sun it was given, and the map's own angle is set after, so left
## alone the fill lights the faces the sun already does. Null when the profile has no fill.
static func _aim_fill(lighting: Node, env_doc: Dictionary, sun: DirectionalLight3D) -> DirectionalLight3D:
	var fill := lighting.get_node_or_null("Fill") as DirectionalLight3D
	if fill == null:
		return null
	var aimed := DotLightRig.fill(DotLightDocument.from_dictionary(light_document(env_doc)), sun.rotation,
		light_profile(float(env_doc["ambient_energy"])))
	fill.rotation = aimed.rotation
	aimed.free()
	return fill


static func _light_values(sun: DirectionalLight3D, world: WorldEnvironment, fill: DirectionalLight3D) -> Dictionary:
	var out := {}
	var env := world.environment
	var sky_mat: Object = env.sky.sky_material if env.sky != null else null

	for key: String in LIGHT_KEYS:
		var parts := key.split(":")
		var holder: Object = sun if parts[0] == "sun" else env if parts[0] == "env" else fill if parts[0] == "fill" else sky_mat
		if holder != null:
			out[key] = holder.get(parts[1])

	return out


## How much of the light is day, 0 (the map's own night) to 1. Nothing happens on a map that
## has no day captured, or on a server, which draws no light.
func set_daylight(amount: float) -> void:
	if _day_light.is_empty() or _sun == null or _environment == null:
		return

	amount = clampf(amount, 0.0, 1.0)

	if is_equal_approx(amount, _daylight):
		return

	_daylight = amount
	var env := _environment.environment
	var sky_mat: Object = env.sky.sky_material if env.sky != null else null

	for key: String in LIGHT_KEYS:
		if not _night_light.has(key) or not _day_light.has(key):
			continue
		var parts := key.split(":")
		var holder: Object = _sun if parts[0] == "sun" else env if parts[0] == "env" else _fill if parts[0] == "fill" else sky_mat
		if holder == null:
			continue
		var a: Variant = _night_light[key]
		var b: Variant = _day_light[key]
		if a is Color:
			holder.set(parts[1], (a as Color).lerp(b as Color, amount))
		elif a is Vector3:
			holder.set(parts[1], (a as Vector3).lerp(b as Vector3, amount))
		else:
			holder.set(parts[1], lerpf(float(a), float(b), amount))


func daylight() -> float:
	return _daylight


## The dot-lighting document a map's `environment` describes.
##
## [b]The sun is the map's, at the map's strength[/b]: 380 (game-arena's daylight) times the
## square of `sun_energy`, which for a night map's 0.12 is a faint moon (drawn below the rig's
## floor, see [method _build_environment]) and leaves the lamps to light the street. [b]The fill is the map's
## ambient hue taken halfway to neutral and brought up to a pale value[/b]: a night map's
## ambient is a deep blue that, at the strength the dark needs to stay readable, tinted
## everything navy and lost every zombie against every wall; halfway keeps the moonlit cool
## (and the pier's dusk rose) without the cast. [b]The fog is the map's own darkness from
## 14 m[/b]: its horizon colour, reaching full at about 2 / `fog` metres further on and never
## quite opaque, so what comes out of the dark comes out of it at a distance a survivor can
## still shoot, and the map's `fog` (the chapel's 0.05 is twice the street's) still says how
## thick. Source units (metres / 0.01905), as the rig reads them.
static func light_document(env_doc: Dictionary) -> Dictionary:
	var sun := ZzMapDoc.colour(env_doc["sun_colour"])
	var horizon := ZzMapDoc.colour(env_doc["sky_horizon"])
	var ambient := ZzMapDoc.colour(env_doc["ambient"])
	var peak := maxf(maxf(ambient.r, ambient.g), maxf(ambient.b, 0.01))
	var fill := Color(ambient.r / peak, ambient.g / peak, ambient.b / peak).lerp(Color(1.0, 1.0, 1.0), 0.5) * 0.9
	var energy := float(env_doc["sun_energy"])
	var fog := maxf(float(env_doc["fog"]), 0.01)
	var start := 14.0
	return {
		"sun": {
			"colour": [sun.r, sun.g, sun.b],
			"brightness": 380.0 * energy * energy,
			"spread_degrees": 1.0,
			"ambient_colour": [fill.r, fill.g, fill.b],
		},
		"fog": {
			"enabled": true,
			"colour": [horizon.r, horizon.g, horizon.b],
			"start": start / 0.01905,
			"end": (start + 2.0 / fog) / 0.01905,
			"max_density": clampf(fog * 20.0, 0.35, 0.85),
		},
	}


## What this machine draws of a map's light: dot-lighting's `painted()` (API level 3), the
## family's profile for hand-built worlds, with the map's ambient and fill.
##
## [b]Shadows stay on in the browser[/b], unlike dot-lighting's `web()`: a moonlit street
## without them is every face lit alike, and the boxes are batched into a few dozen meshes.
## `painted()` matches its light to the renderer (the Compatibility renderer this game and the
## client shell use has no headroom above white), lowers the exposure, grades, and trades
## ambient for a shadowless fill from the side the sun is not on, turned with the map's sun
## ([method _aim_fill]) and blended between night and day with it ([method set_daylight]).
##
## [b]The ambient is the map's `ambient_energy` times [constant AMBIENT] of `painted()`'s, the
## fill times [constant FILL][/b], chosen from rendered frames under Compatibility (the
## family's 4 and 2.8 scaled by this game's old 1.2 against their 1.4): a night street stays
## dusky with the lamps pooling and a zombie a dark figure against a lighter wall, and the
## school by day loses the glare that washed its field white.
const AMBIENT := 3.4
const FILL := 2.4

static func light_profile(ambient_energy: float = 0.5) -> DotLightProfile:
	var p := DotLightProfile.painted()
	p.sun_shadows = true
	p.ambient_energy *= ambient_energy * AMBIENT
	p.fill_energy *= ambient_energy * FILL
	# Less contrast than painted()'s 1.12: the grade pivots at mid grey, and dark props and
	# zombies in shade went to black at 1.12.
	p.contrast = 1.04
	# Glow only from what is brighter than white (the lamps, the fires), not from every
	# pale wall.
	p.glow_threshold = 1.0
	return p


# --- Asking ----------------------------------------------------------------

## Where seat [param seat] of [param side] (`"survivors"`) starts:
## `[position, yaw]`. More people than spawns stand in rings round them, a metre and a bit
## apart, so nobody starts inside anybody else.
func spawn(side: String, seat: int) -> Array:
	var list: Array = (doc.get("spawns", {}) as Dictionary).get(side, [])

	if list.is_empty():
		return [Vector3(0.0, 1.0, 0.0), 0.0]

	var base: Dictionary = list[seat % list.size()]
	var lap := seat / list.size()
	var at := ZzMapDoc.v3(base["at"])

	if lap > 0:
		var angle := float(lap) * 2.39996
		at += Vector3(cos(angle), 0.0, sin(angle)) * (1.1 * ceilf(float(lap) / 6.0))

	return [at, float(base.get("yaw", 0.0))]


func kill_height() -> float:
	return float(doc.get("kill_y", -30.0))


func bounds() -> AABB:
	return _bounds


## Which prop a physics query hit, from the collider and the shape index it reported; -1 for
## anything that is not a prop.
func prop_from_hit(collider: Object, shape_index: int) -> int:
	if collider == null or collider != _furniture:
		return -1

	var owner_id := _furniture.shape_find_owner(shape_index)
	var node := _furniture.shape_owner_get_owner(owner_id) as Node

	if node == null or not node.has_meta(&"zz_prop"):
		return -1

	return int(node.get_meta(&"zz_prop"))


## Which prop [param point] is on, within [constant HIT_MARGIN]: a shot that stopped
## on furniture. -1 for none.
func prop_containing(point: Vector3) -> int:
	for index in range(props.size()):
		var prop: Dictionary = props[index]
		var size: Vector3 = prop["size"]
		var local: Vector3 = (prop["transform"] as Transform3D).affine_inverse() * point
		var half := size * 0.5 + Vector3.ONE * HIT_MARGIN
		var pieces := catalogue.pieces_of(prop["id"]) if catalogue != null else []

		if not pieces.is_empty():
			if DotPropPieces.contains(pieces, local, HIT_MARGIN):
				return index
			continue

		if absf(local.x) <= half.x and local.y >= -HIT_MARGIN and local.y <= size.y + HIT_MARGIN \
				and absf(local.z) <= half.z:
			return index

	return -1


func prop_id(index: int) -> StringName:
	return (props[index] as Dictionary)["id"] if index >= 0 and index < props.size() else &""


## A camera for watching the whole map from above, for somebody with nobody left to watch.
func overview() -> Transform3D:
	var centre := _bounds.get_center()
	var reach := maxf(_bounds.size.length() * 0.45, 12.0)
	var eye := centre + Vector3(reach * 0.5, reach * 0.55, reach * 0.5)
	return Transform3D(Basis.IDENTITY, eye).looking_at(centre, Vector3.UP)


func describe_lines() -> PackedStringArray:
	return PackedStringArray([
		"map        %s (%s)" % [str(doc.get("name", "")), String(id())],
		"boxes      %d" % (doc.get("boxes", []) as Array).size(),
		"props      %d" % props.size(),
		"lights     %d" % (doc.get("lights", []) as Array).size(),
		"light      %s" % ("baked" if baked != null else "live lamps"),
	])
