extends Node

## The declarations of [zz_horde.gd]: constants, signals and variables, so the file that extends this holds behaviour only.

const ZzConfig := preload("zz_config.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNavGraph := preload("zz_nav_graph.gd")
const ZzNavJob := preload("zz_nav_job.gd")
const ZzNavPrune := preload("zz_nav_prune.gd")
## Bumped when the prune records more (2: the cut edges smoothing must not cross), so older caches prune again.
const PRUNE_VERSION := 5
const ZzNavNotes := preload("zz_nav_notes.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPackList := preload("zz_packs.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieLimbs := preload("../npcs/zz_zombie_limbs.gd")

## Every zombie: dot-npc's spawner, dot-npc-ai-director's pacing, dot-combat's health, and the
## five clocks the genre runs on top of a director.
##
## [b]The director is the background; the clocks are the events.[/b] [DotNpcDirector] keeps a
## population of commons ahead of the team that rises while they are calm and falls away once
## they are hurting — the build-up, peak and relax that makes a quiet street feel like it is
## waiting. On top of it, this file runs what a director deliberately does not:
##
## [codeblock]
## mobs       every mob_interval, a crowd spawned out of sight that KNOWS where you are
## specials   one at a time up to a cap, each from where it is most dangerous
## the brute  on its own long clock, with a warning
## panic      while an objective is held: mobs back to back until it is done
## survival   held by nights or a clock: everything above, faster and bigger by `intensity`
## waves      held by waves: the director and the clocks are off, and the survival runtime
##            (`zz_survival.gd`) releases each wave through [method spawn_wave]
## [/codeblock]
##
## [b]Barricades are on the zombies' ground on purpose.[/b] A shut gate is cut out of the graph
## so the horde goes round; a barricade is left in, so the horde paths straight at it, is
## stopped by its boxes, and breaks it down ([method barricade_in_way], [method bash]). A
## barricade cut out of the graph would leave a school with no way in, every wave spawned
## "where it cannot reach anybody", and nothing at the windows.
##
## [b]Server only.[/b] A client never builds one; it draws what the bridge tells it about.
##
## [b]A zombie's combat id comes from the game's [DotEntityTable] and carries its kind[/b], as
## game-arena's monsters do, so a survivor's session id and a zombie's id cannot collide and
## [method is_npc_entity] asks the id rather than comparing it with a constant.

const CHANNEL := "zz.horde"

## Where brains find this. See `zz_zombie_brain.gd`.
const HORDE_META := &"zz_horde"

## A zombie's scream wakes idle commons this far away, one at a time a beat apart.
const ALERT_RADIUS := 9.0

## Bile calls every common this far away.
const BILE_RADIUS := 45.0

## How far a broken bile jar splashes.
const BILE_SPLASH := 4.0

## A mob is spawned at most this many at a time, a few ticks apart, so a crowd pours out of a
## doorway rather than appearing in it.
const MOB_BURST := 6
const MOB_BURST_SECONDS := 0.4

## Commons standing about a map are at least this far from where the team starts.
const WANDERER_CLEARANCE := 28.0

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

## The most commons a survival wave lets be up at once (`ZzSurvival._release` sets it each
## tick; -1 none). A mob (a scream, bile, a box) fits under it: uncapped, one bile mob of
## forty on a third wave filled the server's whole cap and was where most holds ended
## (zz-survival-retune-1).
var wave_room: int = -1

## What the wave in play does to everything spawned in it: its twist.
var wave_speed_scale: float = 1.0
var wave_health_scale: float = 1.0

## The survival wave in play (1-based; 0 outside a survival hold), for a pack monster's `min_wave`.
var wave_index: int = 0

## Barricades this map has: id -> {bounds: AABB, centre: Vector3}. Filled by the game.
var barricades: Dictionary = {}

## Every living zombie by four-metre cell, and where it was, built once a tick before anything
## thinks ([method _rebuild_grid]). What a zombie's crowd spacing and a stand-in's threat scan
## ask instead of the spawner's `npcs_near`, which walks every zombie: ninety commons each
## asking it for their neighbours every tick was eight thousand position reads, and most of a
## big map's tick.
## By path, like every brain: a pack shell older than the class would not know its name.
const CrowdGrid := preload("res://addons/dot_npc_ai/steer/dot_npc_ai_crowd_grid.gd")
var crowd: CrowdGrid = CrowdGrid.new(GRID)
var _crowd_npcs: Array[DotNpcInstance] = []
var _near_scratch := PackedInt32Array()
const GRID := 4.0

## Grid cell -> barricade ids near it, so a zombie asks only about the ones beside it.
var _barricade_cells: Dictionary = {}
const BARRICADE_CELL := 4.0
## How far past a barricade's face a zombie bashes it from: its radius and an arm.
const BASH_REACH := 0.75

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


# --- Setting up ------------------------------------------------------------------------------
