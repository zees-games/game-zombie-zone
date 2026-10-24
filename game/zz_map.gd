extends Node3D

const ZzMapDoc := preload("zz_map_doc.gd")
const ZzMaterials := preload("zz_materials.gd")
const ZzProps := preload("zz_props.gd")
const ZzFixtures := preload("zz_fixtures.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzMechanics := preload("zz_mechanics.gd")
const WATER_SHADER := preload("zz_water.gdshader")

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
## second UV set ([DotLightmapSheet]) and a name that is the same on every build (`Boxes_<n>`, or `Shiny_<n>` for brushed metal, a caster only),
## because the bake names its meshes by path and was made from this same code. A bake whose
## fingerprint ([method light_fingerprint]) is not this document's is stale and refused with a
## WARN; with none, or refused, the lamps light the map live, as before bakes existed. Baked,
## the lamps turn `BAKE_STATIC`: they no longer light the boxes (the lightmap does, with their
## shadows and bounce) but still light every zombie, survivor and prop. The moon or sun stays
## live (a hold's day turns it) and only its bounce is baked. Static props are bake-time casters
## only (their shadows and bounce are in the boxes' lightmap; the bake carries no prop meshes), and
## so are brushed-metal batches (`Shiny_<n>`): a lamp's highlight is what makes metal look like
## metal and a lightmap holds diffuse light only, so metal stays live-lit. Everything that moves
## (gates, barricades, toys, doors, zombies, survivors, weapons) is lit by the LightmapGI probes
## plus the live lamps. A lightmap ignores the Environment's ambient, and a closed room has no sky
## for the bake's own sky term to show, so the bake makes every surface emit the ambient colour
## (tools/lightmap_scenes.gd, `EMIT_BY_MAP`): the flat fill the live map has, with occlusion.
## What a day raises is carried by `BAKED_DAY_EXPOSURE`. Glass and water are not in the bake. A
## server never loads one ([member draw_world] is false).

const CHANNEL := "zz.map"

## Metres of world one batched mesh covers. See the class notes.
const CHUNK := 12.0

## A shot's impact closer than this to a prop's box counts as hitting it: a bullet stops on the
## surface, and a point exactly on a face is outside a strict test half the time.
const HIT_MARGIN := 0.06

## How much deeper than drawn a ground slab collides (see `_build_boxes`).
const GROUND_DEPTH := 1.8
## An invisible slab this far above everything playable is a sky box: nobody reaches it, so it does not collide.
const SKY_CLEARANCE := 30.0

## How far past the playable ground (the nav floors, spawns and route) the invisible boundary
## stands, its thickness, and how far above the highest floor it reaches. A converted map's
## boxes run far past what is walked on (ze_jurassicpark: 500 m of terrain round a 240 m play
## area), and nothing stopped a survivor going out to the edge of the world.
const BOUNDARY_MARGIN := 8.0
const BOUNDARY_THICKNESS := 4.0
const BOUNDARY_HEIGHT := 60.0

## What a bake of this game's maps means beyond the document (which boxes and lights are in it,
## its settings in tools/lightmap_scenes.gd). Bump it and every committed bake reads as stale.
const BAKE_SCRIPT := "res://addons/dot_lighting/bake/dot_light_bake.gd"
const SHEET_SCRIPT := "res://addons/dot_lighting/bake/dot_lightmap_sheet.gd"
const BAKE_VERSION := 3

## What a day adds to a lightmapped surface: nothing from the ambient, so the exposure rises with
## the day by this factor instead (frames: a baked school by day read a third darker than live).
const BAKED_DAY_EXPOSURE := 1.5

## Where a map's bake is, by id; rebased, so a delivered pack finds its own.
const BAKE_PATH := "res://lightmaps/%s.res"

## Whether a client looks for a map's bake at all. Off draws every map with live lamps.
static var use_bakes: bool = true

## Whether a client draws a converted map with its own geometry ([method load_world]). Off
## draws the boxes, as before the worlds existed.
static var use_worlds: bool = true

## dot-map's reader of a converted map's mesh, by path ([method can_draw_world]).
const SKY_ROOT := "res://assets/sky"
const MESH_SCRIPT := "res://addons/dot_map/bsp/dot_map_bsp_mesh.gd"
const SURFACES_SCRIPT := "res://addons/dot_map/surfaces/dot_map_surfaces.gd"
const VIS_SCRIPT := "res://addons/dot_map/bsp/dot_map_visibility.gd"

## Where a checkout keeps a map's world: `world/<pack>/<id>`.
const LOCAL_WORLD := "res://world/%s/%s"

## True once [method attach_world] has drawn this map's own geometry.
var world_drawn: bool = false
## How a drawn world is culled (dot-map DotMapVisibility): off, pvs, occluders or both.
var vis_mode: String = "both"
var visibility: Node = null

## The converted map's lifts, doors, buttons and triggers (null on a map without a world).
var mechanics: ZzMechanics = null
## The world pack's hulls the document's `world_collision` names ([method attach_world_collision]).
var world_collision: StaticBody3D = null
## The clip-kind hulls of the same world, on the clip layer.
var world_clip: StaticBody3D = null
## Whether a world's movers are built (off in suites that want the boxes alone).
var use_mechanics: bool = true
## Builds the movers of a world from dot-map's global converter too (they are skipped by default because the document's boxes
## already stand where its doors are); a map document says `"mechanics": true` when its boxes leave the movers out. Suites set this.
static var bring_global_mechanics: bool = false
## Handed to the mechanics: a box has somebody in it, and the living survivors' points.
var occupants_fn: Callable = Callable()
var points_fn: Callable = Callable()
var opener_fn: Callable = Callable()
## The game's side of hurt, push and teleport volumes (see [ZzMechanics]).
var volume_bodies_fn: Callable = Callable()
var volume_damage_fn: Callable = Callable()
var volume_move_fn: Callable = Callable()
var _pending_movers: Dictionary = {}

signal built()
## A moving part changed state on the server (see [method ZzMechanics.snapshot]).
signal mover_changed(index: int)
## The map's own logic asked the game for something (a HUD line, a zombie, a setting): see [signal ZzMechanics.logic_event].
signal logic_event(kind: String, data: Dictionary)

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
## Invisible solids (player clip, nodraw): movers stop at them, shots and sight pass.
var _clip: StaticBody3D = null
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
## The converted map's displacement ground (the document's `terrain`), or null.
var terrain: DotMapTerrain = null
var _missing: PackedStringArray = PackedStringArray()
var _lamps: Array[OmniLight3D] = []
## The LightmapGI laid over this map, or null: drawn with live lamps.
var baked: LightmapGI = null

## The map's water volumes, world space: what a survivor's swim mode and the horde's wading ask,
## built from the document on every end (a box list answers the same on both, which an Area3D
## cannot for a client replaying ticks). Empty for a map without water.
var water_boxes: Array[AABB] = []

var _water_nodes: Array[MeshInstance3D] = []
var _dry_fog: Dictionary = {}
var _wet: bool = false
var _baked_exposure: float = 1.0


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

	_clip = StaticBody3D.new()
	_clip.name = "Clip"
	add_child(_clip)
	_put_on(_clip, &"clip")

	if draw_world:
		_drawn = Node3D.new()
		_drawn.name = "Drawn"
		add_child(_drawn)

	_build_boxes()
	_build_terrain()
	_build_boundary()
	_build_water_volumes()
	_build_props()
	_build_toys()

	if draw_world:
		_build_water_surfaces()
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
	water_boxes.clear()
	_water_nodes.clear()
	_dry_fog = {}
	_wet = false
	_gates.clear()
	_barricades.clear()
	mechanics = null
	world_collision = null
	_pending_movers.clear()
	_missing.clear()
	_bounds = AABB()
	terrain = null
	_lamps.clear()
	baked = null
	world_drawn = false
	toys = null
	_solid = null
	_furniture = null
	_clip = null
	world_clip = null
	_drawn = null
	_environment = null
	_sun = null
	_fill = null
	_night_light = {}
	_day_light = {}
	_daylight = 0.0


## The document's water as boxes (`at` is the centre, the top face is the surface).
func _build_water_volumes() -> void:
	water_boxes.clear()

	for pool: Dictionary in doc.get("water", []):
		var size := ZzMapDoc.v3(pool["size"])
		water_boxes.append(AABB(ZzMapDoc.v3(pool["at"]) - size * 0.5, size))


## Each volume's surface: one sheet at the top face, with the water shader (see zz_water.gdshader),
## which draws the ripples, the sheen and the lip. The volume has no walls: Source's water is a
## surface too, and a swimmer sees the pool's own sides through it.
func _build_water_surfaces() -> void:
	var waters: Array = doc.get("water", [])

	for i in water_boxes.size():
		var box := water_boxes[i]
		var plane := PlaneMesh.new()
		plane.size = Vector2(box.size.x, box.size.z)
		var material := ShaderMaterial.new()
		material.shader = WATER_SHADER
		var entry: Dictionary = waters[i]

		if entry.has("tint"):
			var tint := ZzMapDoc.colour(entry["tint"])
			material.set_shader_parameter("tint", tint)
			material.set_shader_parameter("deep_tint", tint.darkened(0.65))

		material.set_shader_parameter("extent", Vector4(box.position.x, box.position.z, box.end.x, box.end.z))
		var sheet := MeshInstance3D.new()
		sheet.name = "Water%d" % i
		sheet.mesh = plane
		sheet.material_override = material
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A hair under the top face, so a wall at the pool's edge does not fight the sheet.
		sheet.position = Vector3(box.get_center().x, box.end.y - 0.02, box.get_center().z)
		_drawn.add_child(sheet)
		_water_nodes.append(sheet)


## Under the surface: the world's fog turns to the water's colour and closes in, so the pool's
## far side is a murk and not a clear room. [param tint] is the water's colour; false puts the
## map's own fog back. Presentation only, on the end whose camera it is.
func set_underwater(under: bool, tint: Color = Color(0.05, 0.28, 0.36)) -> void:
	if _environment == null or _environment.environment == null or under == _wet:
		return

	var env := _environment.environment
	_wet = under

	if under:
		_dry_fog = {
			"fog_enabled": env.fog_enabled, "fog_mode": env.fog_mode, "fog_density": env.fog_density,
			"fog_light_color": env.fog_light_color, "fog_sky_affect": env.fog_sky_affect,
			"fog_light_energy": env.fog_light_energy,
		}
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_density = 0.09
		env.fog_light_color = tint
		env.fog_sky_affect = 1.0
		env.fog_light_energy = 1.0
	else:
		for key: String in _dry_fog:
			env.set(key, _dry_fog[key])
		_dry_fog = {}


func _put_on(body: CollisionObject3D, layer: StringName) -> void:
	if physics == null:
		return

	var applied := physics.apply_to(body, layer)

	if not applied.ok:
		DotLog.warn(CHANNEL, "a map body could not be put on its layer", {"layer": String(layer)})


# --- Building --------------------------------------------------------------

## The ground a map is played on, from its document: the nav floors, spawns, route and areas
## (x and z, with y the highest floor). Empty when the document names no ground.
func playable_region() -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)

	var floors: Array = (doc.get("nav", {}) as Dictionary).get("floors", [])
	for f: Array in floors:
		lo = Vector3(minf(lo.x, float(f[0])), minf(lo.y, float(f[4])), minf(lo.z, float(f[1])))
		hi = Vector3(maxf(hi.x, float(f[2])), maxf(hi.y, float(f[4])), maxf(hi.z, float(f[3])))
	var walked := terrain.walk_points(1.0) if terrain != null else PackedVector3Array()
	for p in walked:
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))

	if floors.is_empty() and walked.is_empty():
		return AABB()

	var points: Array = []
	for side: String in (doc.get("spawns", {}) as Dictionary):
		for entry: Dictionary in doc["spawns"][side]:
			points.append(entry["at"])
	points.append_array(doc.get("route", []))
	points.append_array(doc.get("zombie_spawns", []))
	for side: String in (doc.get("areas", {}) as Dictionary):
		for area: Dictionary in doc["areas"][side]:
			points.append(area["min"])
			points.append(area["max"])
	for obj: Dictionary in doc.get("objectives", []):
		if obj.has("at"):
			points.append(obj["at"])

	for pt: Array in points:
		var v := ZzMapDoc.v3(pt)
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))

	return AABB(lo, hi - lo)


## Four invisible walls round [method playable_region], from the kill height up, on the world
## layer: nobody walks, falls off a ledge or is thrown out of the map's ground, on any map.
## Under the world's own boxes, so a map that already closes itself in loses nothing.
func _build_boundary() -> void:
	var region := playable_region()
	if region.size == Vector3.ZERO:
		return

	var lo := region.position - Vector3(BOUNDARY_MARGIN, 0.0, BOUNDARY_MARGIN)
	var hi := region.end + Vector3(BOUNDARY_MARGIN, 0.0, BOUNDARY_MARGIN)
	var floor_y := minf(kill_height(), region.position.y) - 5.0
	var height := region.end.y + BOUNDARY_HEIGHT - floor_y
	var mid_y := floor_y + height * 0.5
	var t := BOUNDARY_THICKNESS
	var span := hi - lo
	# Its own body on its own layer, which survivors and zombies stop at and the navigation bake
	# and the notes' probes (the world and the furniture) never see: as world boxes the walls
	# stretched the bake over the whole void and the annotator found no chokes.
	var body := StaticBody3D.new()
	body.name = "Boundary"
	add_child(body)
	_put_on(body, &"boundary")

	var walls := [
		[Vector3(lo.x - t * 0.5, mid_y, (lo.z + hi.z) * 0.5), Vector3(t, height, span.z + t * 2.0)],
		[Vector3(hi.x + t * 0.5, mid_y, (lo.z + hi.z) * 0.5), Vector3(t, height, span.z + t * 2.0)],
		[Vector3((lo.x + hi.x) * 0.5, mid_y, lo.z - t * 0.5), Vector3(span.x + t * 2.0, height, t)],
		[Vector3((lo.x + hi.x) * 0.5, mid_y, hi.z + t * 0.5), Vector3(span.x + t * 2.0, height, t)],
	]

	for i in walls.size():
		var shape := CollisionShape3D.new()
		shape.name = "Boundary_%d" % i
		var cube := BoxShape3D.new()
		cube.size = walls[i][1]
		shape.shape = cube
		shape.position = walls[i][0]
		body.add_child(shape)


func _build_boxes() -> void:
	var batches := {}
	var any := false
	var sky_floor := playable_region().end.y + SKY_CLEARANCE

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

		if bool(box.get("solid", true)) and not ZzMapDoc.is_trim(box):
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
			if bool(box.get("visible", true)):
				_solid.add_child(shape)
			elif at.y - size.y * 0.5 < sky_floor:
				_clip.add_child(shape)
			else:
				shape.free()

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
		var role := ZzMaterials.role_of(size)
		var surface := ZzMaterials.surface_for(str(id()), str(box["mat"]), str(box.get("surface", "")))
		var key :="%s|%s|%d|%d|%s|%s|%s" % [str(box["mat"]), tint.to_html(), cell.x, cell.y, ghost, role, surface]

		if not batches.has(key):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			# Baked light falls on what is solid and opaque; a decal, a bulb, water and glass
			# are drawn live (and the bake sees through them).
			var bakeable := not ghost and not ZzMaterials.is_transparent(str(box["mat"]))
			batches[key] = {"tool": tool, "mat": str(box["mat"]), "tint": tint, "ghost": ghost, "role": role, "surface": surface,
				"shiny": bakeable and ZzMaterials.is_shiny(str(box["mat"]), role, surface),
				"sheet": (load(SHEET_SCRIPT) as GDScript).new() if bakeable and can_bake() else null}

		var batch_of: Dictionary = batches[key]
		batch_of["trim"] = bool(batch_of.get("trim", true)) and ZzMapDoc.is_trim(box)
		if batch_of["sheet"] != null:
			_add_box_faces(batch_of["sheet"], frame, size)
		else:
			_add_box(batch_of["tool"], frame, size)

	var index := 0

	for key: String in batches:
		var batch: Dictionary = batches[key]
		var tool: SurfaceTool = batch["tool"]
		var sheet: RefCounted = batch["sheet"]
		if sheet != null:
			sheet.commit(tool)
		var mesh := MeshInstance3D.new()
		# The same name on every build of this document: a bake finds its meshes by path.
		# A shiny batch (brushed metal) is in the bake as a caster only and trimmed from the stored
		# file (tools/lightmap_trim.gd): what makes it look like metal is a lamp's highlight, which a
		# lightmap cannot hold, so it stays unlit by the lightmap and the lamps light it live.
		mesh.name = "%s_%d" % ["Shiny" if batch["shiny"] else "Boxes", index]
		index += 1
		# dot-core's DotCollisionAudit: a chunk of `"solid": false` boxes is decoration by the
		# map's own say-so, and a player is meant to walk through it.
		# a batch of nothing but trim has no shape by ZzMapDoc.is_trim's rule, not by a loss
		if bool(batch["ghost"]) or bool(batch.get("trim", false)):
			mesh.set_meta(&"dot_no_collision", true)
		var arrays := tool.commit()
		if sheet != null:
			arrays.lightmap_size_hint = sheet.size
			mesh.set_meta(&"zz_bakeable", true)
		mesh.mesh = arrays
		mesh.material_override = ZzMaterials.material(batch["mat"], batch["tint"], batch["role"], batch["surface"])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
			if ZzMaterials.is_transparent(batch["mat"]) else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_drawn.add_child(mesh)


## The displacement ground: one triangle shape, and drawn as a "Boxes_" mesh so a drawn world
## replaces it like the boxes.
func _build_terrain() -> void:
	if not doc.has("terrain"):
		return
	var res := DotMapTerrain.from_dict(doc["terrain"])
	if not res.ok:
		DotLog.warn(CHANNEL, "a map's terrain would not read; it has no ground there", {"map": String(id()), "error": str(res)})
		return
	terrain = res.value
	var shape := CollisionShape3D.new()
	shape.name = "Terrain"
	shape.shape = terrain.build_shape()
	shape.set_meta(&"surface", terrain.mat)
	_solid.add_child(shape)
	var box := terrain.bounds()
	_bounds = box if _bounds == AABB() else _bounds.merge(box)
	if not draw_world:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "Boxes_terrain"
	mesh.mesh = terrain.build_mesh()
	var mat := terrain.mat if terrain.mat != "" else "dirt"
	mesh.material_override = ZzMaterials.material(mat, Color.WHITE, "floor", ZzMaterials.surface_for(str(id()), mat, ""))
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
			mesh.material_override = ZzMaterials.material(str(box["mat"]), ZzMapDoc.colour(box.get("tint", [1, 1, 1])),
				ZzMaterials.role_of(size), str(box.get("surface", "")))
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
		body.set_meta(&"barricade", true)
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
		mesh.material_override = ZzMaterials.material(str(box["mat"]), tint, "barricade")
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
			Color(tint.r * step, tint.g * step, tint.b * step), "barricade")


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
static func _add_box_faces(sheet: RefCounted, frame: Transform3D, size: Vector3) -> void:
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


## Whether the host's dot-lighting can lay a bake (API level 5: DotLightBake, DotLightmapSheet). Those
## classes are reached by path, never by name: a host shell with an older dot-lighting would fail to
## parse this whole script on the name, and the map would not load. Without them the map is drawn
## with its live lamps.
static func can_bake() -> bool:
	return DotAddonApi.build_level("dot_lighting") >= 5 and ResourceLoader.exists(BAKE_SCRIPT) \
			and ResourceLoader.exists(SHEET_SCRIPT)


## What this map's bake must have been made from: the boxes, the lamps and the sky, and the
## versions of everything that lays them out. The same on the machine that baked and on every
## client, from the document alone.
func light_fingerprint() -> String:
	if not can_bake():
		return ""

	return (load(BAKE_SCRIPT) as GDScript).call(&"fingerprint", {
		"zz": BAKE_VERSION, "boxes": doc.get("boxes", []), "props": doc.get("props", []), "lights": doc.get("lights", []),
		"environment": doc.get("environment", {}),
	})


## The map's bake laid over it, if the game ships one made from this document.
func _attach_bake() -> void:
	var path := ZzPaths.rebase(BAKE_PATH % String(id()))
	if not can_bake():
		return

	var res: DotResult = (load(BAKE_SCRIPT) as GDScript).call(&"attach", self, path, light_fingerprint())

	if not res.ok:
		return

	baked = res.value
	for lamp in _lamps:
		lamp.light_bake_mode = Light3D.BAKE_STATIC

	# A lightmapped surface takes its ambient from the bake, not from the environment, so the
	# ambient a day raises reaches only what is not lightmapped: the exposure rises with the day
	# instead (BAKED_DAY_EXPOSURE). The night's ambient is in the bake (tools/lightmap_scenes.gd).
	if _environment != null:
		_baked_exposure = _environment.environment.tonemap_exposure

	DotLog.debug(CHANNEL, "the map is drawn with its baked light", {"map": String(id())})


## Whether this host can read a map's drawn world: dot-map's [code]DotMapBspMesh[/code], reached by
## path for the reason [method can_bake] gives (a shell with an older dot-map would fail to parse
## this script on the name).
static func can_draw_world() -> bool:
	return ResourceLoader.exists(MESH_SCRIPT)


## Where a world sits beside the game in a checkout (`world/` is zombie-zone-maps' `world/`,
## linked by dot-bootstrap and never shipped in the game's pack).
func local_world_prefix() -> String:
	return ZzPaths.rebase(LOCAL_WORLD % [str(doc.get("world", "")), String(id())])


## Collides with the hulls of [param world] (a [code]DotMapBspMesh[/code]) that the document's
## `world_collision` selects: the solids the wire budget dropped from its boxes. Once per map.
func attach_world_collision(world: RefCounted) -> void:
	var sel: Dictionary = doc.get("world_collision", {})
	if sel.is_empty() or world_collision != null:
		return
	var whole := {}
	for m: Variant in sel.get("models", []):
		whole[int(m)] = true
	var flat := {}
	for m: Variant in sel.get("flat", []):
		if not whole.has(int(m)):
			flat[int(m)] = true
	var flat_height := float(sel.get("flat_height", 0.5))
	var skips: Array[AABB] = []
	for r: Array in sel.get("skip", []):
		skips.append(AABB(Vector3(r[0], r[1], r[2]), Vector3(r[3] - r[0], r[4] - r[1], r[5] - r[2])))
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	var clip := StaticBody3D.new()
	clip.name = "WorldClip"
	var kinds := PackedStringArray(["solid", "clip", "glass"])
	var within: Array = sel.get("within", [])
	var band: Array = sel.get("band", [])
	for model: int in whole.keys() + flat.keys():
		var origin: Vector3 = world.call(&"model_origin", model)
		for h: Dictionary in world.call(&"hull_shapes", model, kinds):
			var shape: ConvexPolygonShape3D = h["shape"]
			var bounds := AABB(shape.points[0] + origin, Vector3.ZERO)
			for p in shape.points:
				bounds = bounds.expand(p + origin)
			if flat.has(model) and bounds.size.y > flat_height:
				continue
			if skips.any(func(r: AABB) -> bool: return r.has_point(bounds.get_center())):
				continue
			var cs := CollisionShape3D.new()
			if within.size() == 4 and (bounds.end.x < within[0] or bounds.position.x > within[2] or bounds.end.z < within[1] or bounds.position.z > within[3]):
				continue
			if band.size() == 2 and (bounds.end.y <= band[0] or bounds.position.y >= band[1]):
				continue
			cs.shape = shape
			cs.position = origin
			(clip if str(h["kind"]) == "clip" else body).add_child(cs)
	_put_on(body, &"world")
	add_child(body)
	world_collision = body
	_put_on(clip, &"clip")
	add_child(clip)
	world_clip = clip
	DotLog.debug(CHANNEL, "the map collides with its world's hulls", {"map": String(id()), "hulls": body.get_child_count(), "clip": clip.get_child_count()})


func _hull_prefixes(root: String) -> PackedStringArray:
	var prefixes := PackedStringArray([ZzPaths.rebase("res://maps/hulls/" + String(id())), local_world_prefix()])
	if root != "":
		prefixes.insert(0, root.path_join("hulls").path_join(String(id())))
	return prefixes


## The maps pack's `hulls/<id>.nav.json` (the whole map's boxes, floors and links the budget cut from the
## document, for the horde's graph), or {} when the map lost nothing or the file is not here.
func read_nav_extra(root: String = "") -> Dictionary:
	if doc.get("world_collision", {}).is_empty():
		return {}
	for prefix in _hull_prefixes(root):
		if FileAccess.file_exists(prefix + ".nav.json"):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(prefix + ".nav.json"))
			if parsed is Dictionary:
				return parsed
			DotLog.warn(CHANNEL, "a map's navigation extra would not read", {"map": String(id()), "at": prefix})
			return {}
	DotLog.warn(CHANNEL, "a map's navigation extra was not found; the horde walks the document's floor only", {"map": String(id())})
	return {}


## [method attach_world_collision] on a server, which loads no world: from the maps pack's
## `hulls/<id>` under [param root] (where the document was read), else the checkout's world.
func build_world_collision_local(root: String = "") -> bool:
	if doc.get("world_collision", {}).is_empty() or world_collision != null or not can_draw_world():
		return false
	for prefix in _hull_prefixes(root):
		if not FileAccess.file_exists(prefix + ".json"):
			continue
		var read: DotResult = (load(MESH_SCRIPT) as GDScript).call(&"load_prefix", prefix)
		if read.ok:
			attach_world_collision(read.value)
			return true
		DotLog.warn(CHANNEL, "a map's hulls would not read", {"map": String(id()), "at": prefix, "why": read.error.message})
	DotLog.warn(CHANNEL, "a map's hulls were not found; it collides with its boxes only", {"map": String(id())})
	return false


## Draws the map with its own geometry ([member doc]'s `world`, zombie-zone-maps'
## tools/build_worlds.py) in place of its boxes, which still collide and still are the horde's
## ground: the mesh is what a survivor sees, never what anything stands on. From the checkout's
## `world/` when it is there, else fetched through dot-cloud by the `world_key` the server sent.
## A world that cannot be had leaves the boxes drawn: the map plays the same either way.
##
## Succeeds with true when the world is drawn, false when there is none to draw.
func load_world() -> DotResult:
	var pack := str(doc.get("world", ""))
	if not draw_world or not use_worlds or pack == "" or not can_draw_world() or _drawn == null:
		return DotResult.success(false)

	var wanted := id()
	var prefix := local_world_prefix()

	if not FileAccess.file_exists(prefix + ".json"):
		var key := str(doc.get("world_key", ""))
		if key == "":
			return DotResult.success(false)
		var got: DotResult = await DotGameContent.ensure_one(key)
		if id() != wanted or _drawn == null:
			return DotResult.success(false)
		if not got.ok:
			DotLog.warn(CHANNEL, "a map's world could not be fetched; its boxes are drawn", {
				"map": String(wanted), "pack": key, "why": got.error.message,
			})
			return got
		prefix = DotGameContent.mount_of(key) + "/" + String(wanted)

	var read: DotResult = (load(MESH_SCRIPT) as GDScript).call(&"load_prefix", prefix)

	if not read.ok:
		DotLog.warn(CHANNEL, "a map's world would not read; its boxes are drawn", {
			"map": String(wanted), "at": prefix, "why": read.error.message,
		})
		return read

	attach_world(read.value, prefix.get_base_dir())
	return DotResult.success(true)


## The converted world's `sounds` block (soundscapes, ambient sounds): they pick the ambience mood.
var world_sounds: Dictionary = {}


## Lays [param world] (a [code]DotMapBspMesh[/code]) over the map: its meshes in, the box batches
## out. Gates, barricades, fixtures and the boxes the converter added (`zz.keep_boxes`) stay
## drawn as boxes; they are not in the original's faces. A bake is made from the boxes, so it is
## taken off and the lamps light the world live.
func attach_world(world: RefCounted, dir: String = "") -> void:
	if _drawn == null:
		return

	var zz: Dictionary = (world.get("manifest") as Dictionary).get("zz", {})
	var mats: Dictionary = zz.get("materials", {})
	world_sounds = (world.get("manifest") as Dictionary).get("sounds", {})
	var map_id := String(id())
	var material_for := func(rec: Dictionary) -> Material:
		var mat := str(mats.get(str(rec.get("material", "")), "concrete"))
		return ZzMaterials.material(mat, Color.WHITE, "wall", ZzMaterials.surface_for(map_id, mat, ""))
	# A pack from dot-map's global converter has no `zz` block: it draws itself with free textures and glass.
	var global_pack := not (world.get("manifest") as Dictionary).has("zz")
	if global_pack:
		# The vendored kinds, rebased onto the mount: the addon's own folder never ships to a client.
		var surfaces: RefCounted = (load(SURFACES_SCRIPT) as GDScript).new(ZzPaths.rebase(ZzMaterials.SURFACES_ROOT))
		material_for = surfaces.call(&"world_material_for", world, dir)

	_unbake()

	for child in _drawn.get_children():
		if child is MeshInstance3D and (String(child.name).begins_with("Boxes_") or String(child.name).begins_with("Shiny_")):
			_drawn.remove_child(child)
			child.queue_free()

	var node: Node3D = world.call(&"build_node", material_for)
	node.name = "World"
	_drawn.add_child(node)
	attach_world_collision(world)
	_light_from_world(world)
	_dress_panorama_sky(world)
	# The document stands up the gates and movers the horde and the objectives drive; a global pack's own
	# doors would collide a second time, so only a pack made for this game brings mechanics.
	if not global_pack or bool(doc.get("mechanics", false)) or bring_global_mechanics:
		attach_mechanics(world)
	else:
		attach_mechanics(world, true)
	if mechanics != null:
		mechanics.bind_drawn(node)

	for box: Dictionary in zz.get("keep_boxes", []):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var size := ZzMapDoc.v3(box["size"])
		_add_box(tool, Transform3D(Basis(Vector3.UP, deg_to_rad(float(box.get("yaw", 0.0)))), ZzMapDoc.v3(box["at"])), size)
		var kept := MeshInstance3D.new()
		kept.name = "Kept"
		kept.mesh = tool.commit()
		var mat := str(box.get("mat", "concrete"))
		kept.material_override = ZzMaterials.material(mat, ZzMapDoc.colour(box.get("tint", [1, 1, 1])), ZzMaterials.role_of(size),
			ZzMaterials.surface_for(map_id, mat, ""))
		_drawn.add_child(kept)

	_attach_world_extras(world, node)
	_attach_visibility(world, node)
	world_drawn = true
	DotLog.debug(CHANNEL, "the map is drawn with its own geometry", {"map": map_id, "counts": str(world.call(&"counts"))})


## Culls the drawn world to what the camera's cluster can see, and adds its occluders; a pack
## without visibility data, or a headless run, draws everything.
func _attach_visibility(world: RefCounted, node: Node3D) -> void:
	if visibility != null:
		visibility.queue_free()
		visibility = null
	if DisplayServer.get_name() == "headless" or not ResourceLoader.exists(VIS_SCRIPT):
		return
	var vis: Node = (load(VIS_SCRIPT) as GDScript).new()
	vis.name = "Visibility"
	vis.set(&"mode", vis.call(&"parse_mode", vis_mode))
	add_child(vis)
	var res: DotResult = vis.call(&"setup", world, node)
	if not res.ok:
		DotLog.debug(CHANNEL, "the world is drawn without culling", {"why": res.error.message})
		vis.queue_free()
		return
	visibility = vis


## Follows the client's culling setting on a world already drawn.
func set_vis_mode(text: String) -> void:
	vis_mode = text
	if visibility != null:
		visibility.call(&"set_mode", visibility.call(&"parse_mode", text))


## The free sky panorama (assets/sky, CC0) for a day map's sky name, in place of the plain gradient.
## Night and space skies keep the procedural sky and its stars.
func _dress_panorama_sky(world: RefCounted) -> void:
	if _environment == null or is_night(doc["environment"]) or not world.has_method(&"sky_panorama"):
		return
	var tex: Texture2D = world.call(&"sky_panorama", ZzPaths.rebase(SKY_ROOT))
	var sky := _environment.environment.sky
	if tex == null or sky == null:
		return
	var panorama := PanoramaSkyMaterial.new()
	panorama.panorama = tex
	sky.sky_material = panorama


## A converted map whose document kept the converter's placeholder light takes the sky, sun,
## ambient and fog its own entities name, and the lighting is built again from them.
func _light_from_world(world: RefCounted) -> void:
	if not ZzMapDoc.is_importer_env(doc["environment"]):
		return
	var derived := ZzMapDoc.environment_from_world(world.call(&"environment_data"))
	if derived.is_empty():
		return
	ZzMapDoc.take_derived_light(doc, derived)
	var old := get_node_or_null("Lighting")
	if old != null:
		remove_child(old)
		old.free()
	_sun = null
	_fill = null
	_environment = null
	_build_environment()


## What the drawn world carries beyond its meshes: reflection probes, fog when the map document
## sets none (the document's own sun and sky stay: a second sun lit everything twice), ambient
## sounds and prop stand-ins, drawn only. Each is nothing for a world without it.
func _attach_world_extras(world: RefCounted, node: Node3D) -> void:
	var env_node: Node3D = world.call(&"build_environment", 8, false)
	if env_node != null:
		var probes := env_node.get_node_or_null("Probes")
		if probes != null:
			env_node.remove_child(probes)
			node.add_child(probes)
		var we := env_node.get_node_or_null("Environment") as WorldEnvironment
		if we != null and we.environment.fog_enabled and _environment != null \
				and float((doc["environment"] as Dictionary).get("fog", 0.0)) <= 0.0:
			var target := _environment.environment
			target.fog_enabled = true
			target.fog_light_color = we.environment.fog_light_color
			target.fog_density = we.environment.fog_density
		env_node.free()

	var sounds: Node3D = world.call(&"build_sounds")
	if sounds.get_child_count() > 0:
		node.add_child(sounds)
	else:
		sounds.free()

	var drawn_props: Node3D = world.call(&"build_props")
	if drawn_props.get_child_count() > 0:
		node.add_child(drawn_props)
	else:
		drawn_props.free()

	_attach_fx(world, node)


## Sprites, glows, spotlight cones and decals from the world's source document (dot-map's DotMapFx), capped per map.
func _attach_fx(world: RefCounted, node: Node3D) -> void:
	var path := local_world_prefix() + ".doc.json"
	if DisplayServer.get_name() == "headless" or OS.get_environment("ZZ_NO_FX") != "" or "--zz-map-fx=false" in OS.get_cmdline_user_args() or not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var fx := DotMapFx.new()
	fx.unit_scale = float(((world.get("manifest") as Dictionary).get("units", {}) as Dictionary).get("metres_per_unit", 0.0254))
	var mask := physics.layer_mask(&"world") if physics != null else 1
	fx.ray_fn = func(from: Vector3, to: Vector3) -> Dictionary:
		var hit := node.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, mask))
		return {} if hit.is_empty() else {"position": hit["position"], "normal": hit["normal"]}
	node.add_child(fx.build((parsed as Dictionary).get("entities", [])))


## Builds the world's movers and triggers from [param world] (a DotMapBspMesh) once: colliders
## for the solid ones, the outputs that drive them. A second call keeps the first.
## [param doors_only]: a global pack's hinged prop doors alone (its brush doors are already in the boxes).
func attach_mechanics(world: RefCounted, doors_only: bool = false) -> void:
	if mechanics != null or not use_mechanics:
		return
	var made := ZzMechanics.new()
	made.name = "Mechanics"
	made.authoritative = authoritative
	made.occupants_fn = occupants_fn
	made.points_fn = points_fn
	made.opener_fn = opener_fn
	made.bodies_fn = volume_bodies_fn
	made.damage_fn = volume_damage_fn
	made.move_fn = volume_move_fn
	if authoritative and str(doc.get("world", "")) != "":
		made.source_doc_path = local_world_prefix() + ".doc.json"
	made.build(world, func(body: CollisionObject3D) -> void: _put_on(body, &"world"), doors_only)
	if made.mover_count() == 0 and not made.has_logic():
		made.free()
		return
	made.state_changed.connect(func(index: int) -> void: mover_changed.emit(index))
	made.logic_event.connect(func(kind: String, data: Dictionary) -> void: logic_event.emit(kind, data))
	add_child(made)
	mechanics = made
	for index: int in _pending_movers:
		var s: Array = _pending_movers[index]
		made.apply_state(index, int(s[0]), int(s[1]), int(s[2]), int(s[3]) != 0, float(s[4]))
	_pending_movers.clear()


## Reads the map's world from the checkout's `world/` (no drawing, no fetch) and builds its
## mechanics: what a server, which draws nothing, runs. True when there were any.
func build_mechanics_local() -> bool:
	var pack := str(doc.get("world", ""))
	if mechanics != null or not use_mechanics or pack == "" or not can_draw_world():
		return false
	var prefix := local_world_prefix()
	if not FileAccess.file_exists(prefix + ".json"):
		return false
	var read: DotResult = (load(MESH_SCRIPT) as GDScript).call(&"load_prefix", prefix)
	if not read.ok:
		DotLog.warn(CHANNEL, "a map's world would not read; it has no moving parts", {"map": String(id()), "why": read.error.message})
		return false
	var own := (read.value.get("manifest") as Dictionary).has("zz") or bool(doc.get("mechanics", false)) or bring_global_mechanics
	attach_mechanics(read.value, not own)
	return mechanics != null


## A mover's state as the server sent it; kept until the mechanics exist.
func apply_mover_state(index: int, start: int, from_thousandths: int, dir: int, locked: bool, side: float = 1.0) -> void:
	if mechanics != null:
		mechanics.apply_state(index, start, from_thousandths, dir, locked, side)
	else:
		_pending_movers[index] = [start, from_thousandths, dir, 1 if locked else 0, side]


## Takes a bake off: what was baked was the boxes.
func _unbake() -> void:
	if baked == null:
		return
	baked.get_parent().remove_child(baked)
	baked.queue_free()
	baked = null
	for lamp in _lamps:
		lamp.light_bake_mode = Light3D.BAKE_DYNAMIC
	if _environment != null:
		_environment.environment.tonemap_exposure = _baked_exposure


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

	if baked != null:
		env.tonemap_exposure = _baked_exposure * lerpf(1.0, BAKED_DAY_EXPOSURE, amount)


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
	var end := start + 2.0 / fog
	var thickest := clampf(fog * 20.0, 0.35, 0.85)
	if env_doc.has("fog_start"):
		# Clear air from a converted day map (ZzMapDoc.environment_from_world): a thin haze far off.
		start = float(env_doc["fog_start"])
		end = maxf(float(env_doc.get("fog_end", start * 10.0)), start + 1.0)
		thickest = 0.25
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
			"end": end / 0.01905,
			"max_density": thickest,
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
