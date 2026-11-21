extends Node3D

const CHANNEL := "zz.mechanics"

## Kinds that move and collide (the others are read for their outputs only).
const SOLID_KINDS := ["slide", "rotate", "plat", "path"]

const BUTTON_KINDS := ["button", "rotate_button"]

## A brush door's classes: what a global pack's mover list holds that opens to whoever walks up, with no switch run.
const DOOR_CLASSES := ["func_door", "func_door_rotating", "func_movelinear"]

const MIN_TRAVEL := 0.05

const DEFAULT_PATH_SPEED := 2.0

## How long a door that stays open waits for nobody to be near before it closes.
const STAY_OPEN_SECONDS := 2.0

const NEAR_EVERY := 4

const VOLUME_EVERY := 2

const PRESS_PAD := 0.3

const DOOR_PAD := 1.5

const MAX_FIRES := 256

## Volumes the server runs through gs-map's GSMapVolumes; push and gravity are also read by prediction.
const VOLUME_KINDS := ["hurt", "push", "teleport", "gravity"]

const PREDICTED_KINDS := ["push", "gravity"]

## How far past a volume's brushes a body is still handed to it (its column and a margin).
const BODY_PAD := 1.0

const GameText := preload("zz_game_text.gd")

const EntityMaker := preload("zz_entity_maker.gd")

const NpcMaker := preload("zz_npc_maker.gd")

const MapCommands := preload("zz_map_commands.gd")

const LogicWaves := preload("zz_logic_waves.gd")

const LogicGameRules := preload("zz_logic_gamerules.gd")

## A template copy of these brush classes is solid where it stands (the others are drawn only).
const COPY_SOLID := ["func_breakable", "func_brush", "func_wall", "func_physbox", "func_physbox_multiplayer"]

## A copy of one of these has no mover of its own: it is drawn where it was made and an Open reaches its end at once.
const MAX_COPY_MOVERS := 256

const COPY_DOORS := ["func_door", "func_door_rotating", "func_movelinear"]

## Longest gap of ticks the map's logic is stepped through in one go.
const MAX_LOGIC_STEP := 4096

## A mover changed state (it was told, or it settled); the bridge broadcasts this index.
signal state_changed(index: int)

## The map's own logic asked the game for something: `hud_text`, `say`, `cvar`, `npc_spawn`, `maker_spawn`, `template_spawn`, `damage_force`.
signal logic_event(kind: String, data: Dictionary)

## A brush a point_template made (or killed): `(id, model, offset in metres from where the model stands, alive)`; the bridge tells clients.
signal copy_changed(id: int, model: int, offset: Vector3, alive: bool)

var tick_rate: int = 64

var authoritative: bool = true

## Whether a box (world metres) has a survivor or a zombie in it.
var occupants_fn: Callable = Callable()

## The living survivors' body points.
var points_fn: Callable = Callable()

## Where whoever is in a box (survivor or zombie) stands, nearest its centre, or null: which way a door swings away from.
var opener_fn: Callable = Callable()

## Server: where the entities' source document is (`<prefix>.doc.json`), for their keys and filters.
var source_doc_path: String = ""

## Server: every body a volume may touch, as `{id, body, position (feet), height, kind, name, class, team}`.
var bodies_fn: Callable = Callable()

## Server: `(body, amount, kind, entity_index)` for a hurt volume's hit.
var damage_fn: Callable = Callable()
