extends Node

## The declarations of [zz_horde.gd]: constants, signals and variables, so the file that extends this holds behaviour only.

const ZzConfig := preload("zz_config.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNavGraph := preload("zz_nav_graph.gd")
const ZzNavJob := preload("zz_nav_job.gd")
const ZzNavPrune := preload("zz_nav_prune.gd")
## Bumped when the prune records or tests more (6: the prop and clip layers too), so older caches prune again.
const PRUNE_VERSION := 6
const ZzNavNotes := preload("zz_nav_notes.gd")
const ZzNpcs := preload("zz_npcs.gd")
const MonsterHost := preload("zz_monster_host.gd")
const ZzPackList := preload("zz_packs.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieLimbs := preload("../npcs/zz_zombie_limbs.gd")

## Every zombie: dot-npc's spawner, dot-npc-ai-director's pacing, dot-combat's health, and the clocks the genre runs on top of a director. Server only.
## The director keeps a calm-rising population of commons; this file adds mobs, specials, the brute, panic while an objective is held, survival intensity and waves.
## Barricades stay on the zombies' ground so the horde paths at them and bashes ([method barricade_in_way], [method bash]); a combat id comes from the game's [DotEntityTable] and carries its kind.

const CHANNEL := "zz.horde"

## Where brains find this. See `zz_zombie_brain.gd`.
const HORDE_META := &"zz_horde"

signal zombie_spawned(npc: DotNpcInstance)
signal zombie_removed(npc: DotNpcInstance)
signal zombie_died(npc: DotNpcInstance, killer: StringName, damage: DotDamage)
## A zombie a map's spawner made is dead, gone, or never came to be: its spawner's live count drops.
signal maker_child_gone(maker: int)
signal mob_started(size: int)
signal special_spawned(npc: DotNpcInstance)
signal brute_spawned(npc: DotNpcInstance)

## The game this horde serves (`zz_game.gd`), untyped: it preloads this file.
var game = null
var config: ZzConfig = null

var spawner: DotNpcSpawner = null
## The game's end of the monsters' host seam (also the spawner's meta `zhm_host`).
var monster_host: MonsterHost = null
var director: DotNpcDirector = null
var senses: DotNpcSenses = null
var squads: DotNpcAiSquads = DotNpcAiSquads.new()

## The server's `npc_skill`, `npc_reaction_scale` and `npc_reaction_min`, which move every kind
## toward easy or nightmare without making them one monster (dot-npc-ai's [DotNpcAiSkill]).
var skill: DotNpcAiSkill = DotNpcAiSkill.new()
var sounds: DotNpcAiSounds = DotNpcAiSounds.new()
var nav: DotNpcNavData = null

## The map's annotations worked into chokes, drops and holds (`ZzNavNotes`); never null.
var notes: ZzNavNotes = ZzNavNotes.new()

## Graph points a brute does not fit at (kept off its paths), for suites and describe.
var narrow_points: int = 0
var catalogue: DotNpcCatalogue = null

## Whether the pacing runs: false in a start area, between maps, in warmup.
var pacing: bool = false

## Whether this is a survival map's hold (bigger mobs, quicker specials, a quicker brute).
var survival: bool = false

## How much harder the hold is than its start: 1 at first, the survival runtime raises it with
## each night or with the clock. Mobs grow by it, come more often by it, specials by its root.
var intensity: float = 1.0

## Whether the waves drive the spawning (the director, mobs, specials and brute clocks off).
var waves_mode: bool = false

## The most commons a survival wave lets be up at once (`ZzSurvival._release` sets it each tick; -1 none).
## A mob fits under it: uncapped, one bile mob filled the whole cap and ended most holds.
var wave_room: int = -1

## What the wave in play does to everything spawned in it: its twist.
var wave_speed_scale: float = 1.0
var wave_health_scale: float = 1.0

## The survival wave in play (1-based; 0 outside a survival hold), for a pack monster's `min_wave`.
var wave_index: int = 0

## Barricades this map has: id -> {bounds: AABB, centre: Vector3}. Filled by the game.
var barricades: Dictionary = {}

## Every living zombie by four-metre cell, built once a tick before anything thinks ([method _rebuild_grid]).
## Crowd spacing and threat scans ask it instead of the spawner's `npcs_near`, which walks every zombie.
## By path, like every brain: a pack shell older than the class would not know its name.
const CrowdGrid := preload("res://addons/dot_npc_ai/steer/dot_npc_ai_crowd_grid.gd")
var crowd: CrowdGrid = CrowdGrid.new(GRID)
var _crowd_npcs: Array[DotNpcInstance] = []
var _near_scratch := PackedInt32Array()
const GRID := 4.0

## Grid cell -> barricade ids near it, so a zombie asks only about the ones beside it.
var _barricade_cells: Dictionary = {}
const BARRICADE_CELL := 4.0

## Multipliers boxes stack: how often mobs come, how hard specials are, how big mobs are.
var mob_rate_scale: float = 1.0
var special_rate_scale: float = 1.0
var special_health_scale: float = 1.0
var mob_size_scale: float = 1.0
var zombie_speed_scale: float = 1.0

## Gates opened this map, so the graph is rebuilt without them.
var open_gates: PackedStringArray = PackedStringArray()

## How a zombie falls when it dies: dot-player-char's reactions, picked here on the server from
## the killing hit and sent with the zombie's end (NPC_GONE), so every screen draws the same fall.
var death_reactions: DotPlayerDeathReactions = DotPlayerDeathReactions.stock()

## Screams heard this map, for a suite and `describe`.
var screams: int = 0

var _world: Node3D = null
var _by_entity: Dictionary = {}
var _candidates: Array = []
var _survivors: Dictionary = {}
var _doc: Dictionary = {}
## The server-only `hulls/<id>.nav.json` of a map whose boxes the wire budget cut ([method ZzMap.read_nav_extra]).
var _nav_extra: Dictionary = {}

var _usable_posts: Array = []
var _usable_posts_for: DotNpcNavData = null
var _populated: bool = true
var _time: float = 0.0

## Infected that make no progress toward the survivors: repath, then relocate near them out of sight.
var stuck := DotNpcStuckRescue.new()
## Sideways nudges given to stuck infected (a repath step), for [method describe].
var stuck_nudges: int = 0
## Nav points costed up after a stall, and the last pair marked (point indexes), for the log.
var stuck_marked: int = 0
var _last_edge: String = "-"
var _left_at: float = -100.0
var _left: int = 0

var _next_mob: float = INF
var _next_special: float = INF
var _next_brute: float = INF
var _panic_until: float = -1.0
var _next_panic_mob: float = 0.0

## Mob commons still to come out: [kind, at, target, flags] per entry.
var _pending: Array = []
## How far from the survivors the director spawns, against its stock distances (a map's `nestdistancemul`).
var spawn_distance_scale: float = 1.0
## Map spawner index by zombie instance id, until it dies or goes.
var _maker_of: Dictionary = {}
var _next_pending: float = 0.0

## Alerts waiting to land: [instance_id, at_time, who, where].
var _alerts: Array = []

## Lures: {at, until, radius}. Bile: player id -> until.
var _lures: Array = []
var _bile: Dictionary = {}

var _rng := RandomNumberGenerator.new()


