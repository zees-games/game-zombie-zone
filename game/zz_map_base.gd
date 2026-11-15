extends Node3D

const ZzMapDoc := preload("zz_map_doc.gd")

const ZzLaps := preload("zz_laps.gd")

## Milliseconds by section of the last [method build], for the cold-start tool.
var sections: Dictionary = {}

const ZzMaterials := preload("zz_materials.gd")

const ZzProps := preload("zz_props.gd")

const ZzLampBudget := preload("zz_lamp_budget.gd")

const ZzFixtures := preload("zz_fixtures.gd")

const ZzPaths := preload("zz_paths.gd")

const ZzMechanics := preload("zz_mechanics.gd")

## Loaded, not preloaded: a client whose dot-map predates it still parses this file and draws a plain sheet.
const WATER_SHADER_PATH := "res://addons/dot_map/surfaces/liquid.gdshader"

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

## A hidden box with no `kind` (an older document) this far above everything playable is a sky box.
const SKY_CLEARANCE := 30.0

## How far past the playable ground (the nav floors, spawns and route) the invisible boundary
## stands, its thickness, and how far above the highest floor it reaches. A converted map's
## boxes run far past what is walked on (ze_jurassicpark: 500 m of terrain round a 240 m play
## area), and nothing stopped a survivor going out to the edge of the world.
const BOUNDARY_MARGIN := 8.0

const BOUNDARY_THICKNESS := 4.0

const BOUNDARY_HEIGHT := 60.0

## How far [method clear_spot] looks for room round a start point that is inside something.
const SPAWN_SEARCH := 3.0

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

## Whether a checkout's own `world/` is read when it is there; off, the world is always fetched through dot-cloud by `world_key` (the delivery check).
static var local_worlds: bool = true

## dot-map's reader of a converted map's mesh, by path ([method can_draw_world]).
const SKY_ROOT := "res://assets/sky"

const MESH_SCRIPT := "res://addons/dot_map/bsp/dot_map_bsp_mesh.gd"

const LIT_SCRIPT := "res://addons/dot_map/bsp/dot_map_lit_world.gd"

const SURFACES_SCRIPT := "res://addons/dot_map/surfaces/dot_map_surfaces.gd"

const VIS_SCRIPT := "res://addons/dot_map/bsp/dot_map_visibility.gd"

## Where a checkout keeps a map's world: `world/<pack>/<id>`.
const LOCAL_WORLD := "res://world/%s/%s"

## True once [method attach_world] has drawn this map's own geometry.
var world_drawn: bool = false

## How a drawn world is culled (dot-map DotMapVisibility): off, pvs, occluders or both.
var vis_mode: String = "both"

## Draw the world pack's baked lightmap when it has one (`zz_lightmaps`).
var use_lightmaps: bool = true

var visibility: Node = null

## The client platform's `attach_visibility(world, drawn)`; unset (a test, a bench) uses the culling built here.
var cull_fn := Callable()

## The converted map's lifts, doors, buttons and triggers (null on a map without a world).
var mechanics: ZzMechanics = null

## The world pack's hulls the document's `world_collision` names ([method attach_world_collision]).
var world_collision: StaticBody3D = null

## The clip-kind hulls of the same world, on the clip layer.
var world_clip: StaticBody3D = null

## A box per solid prop of the drawn world (prop_dynamic and prop_physics the source makes solid), on the prop layer.
var world_props: StaticBody3D = null

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

var _pending_copies: Array = []

signal built()

## A moving part changed state on the server (see [method ZzMechanics.snapshot]).
signal mover_changed(index: int)

## A support broke (its index in [member supports]); the host tells clients.
signal support_broken(index: int)

## Wood gave way (a barricade or a support) at a point, about this wide in metres; drawn on every end, no wire of its own.
signal wood_broke(at: Vector3, size: float)
