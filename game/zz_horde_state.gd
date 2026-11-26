extends Node

## The declarations of [zz_horde.gd]: constants, signals and variables, so the file that extends this holds behaviour only.

const ZzConfig := preload("zz_config.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNavGraph := preload("zz_nav_graph.gd")
const ZzNavJob := preload("zz_nav_job.gd")
const ZzNavPrune := preload("zz_nav_prune.gd")
const ZzNavPruneThread := preload("zz_nav_prune_thread.gd")
const ZzNavWarmThread := preload("zz_nav_warm_thread.gd")
## Bumped when the prune records or tests more (6: the prop and clip layers too; 7: gs-npc v0.1.21 and the hull files in the key; 8: bridges between pieces holding a spawn or post; 11: ladder ends only on the ladder's side of its wall, knee to head, a head over its top only up an open column); 12: a ladder end with no grid point gets a seeded one), so older caches prune again.
const PRUNE_VERSION := 13
const ZzNavNotes := preload("zz_nav_notes.gd")
const ZzLaps := preload("zz_laps.gd")

## Milliseconds by section for the cold-start tool (tools/cold_start.gd).
var sections: Dictionary = {}
## The landed graph's prune on a worker ([member ZzConfig.nav_prune_thread]); null when none is running.
var _pruning = null
## The stand-ins' search of a landed graph whose links went on here (a cached ladder map) built on a worker
## ([member ZzConfig.nav_warm_bots]); the map build waits for it. Null when none is running.
var _warming = null
const ZzNpcs := preload("zz_npcs.gd")
const MonsterHost := preload("zz_monster_host.gd")
const ZzPackList := preload("zz_packs.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieLimbs := preload("../npcs/zz_zombie_limbs.gd")

## Every zombie: gs-npc's spawner, gs-npc-ai-director's pacing, gs-combat's health, and the clocks the genre runs on top of a director. Server only.
## The director keeps a calm-rising population of commons; this file adds mobs, specials, the brute, panic while an objective is held, survival intensity and waves.
## Barricades stay on the zombies' ground so the horde paths at them and bashes ([method barricade_in_way], [method bash]); a combat id comes from the game's [GSEntityTable] and carries its kind.

const CHANNEL := "zz.horde"

## Where brains find this. See `zz_zombie_brain.gd`.
const HORDE_META := &"zz_horde"

signal zombie_spawned(npc: GSNpcInstance)
signal zombie_removed(npc: GSNpcInstance)
signal zombie_died(npc: GSNpcInstance, killer: StringName, damage: GSDamage)
## A zombie a map's spawner made is dead, gone, or never came to be: its spawner's live count drops.
signal maker_child_gone(maker: int)
signal mob_started(size: int)
signal special_spawned(npc: GSNpcInstance)
signal brute_spawned(npc: GSNpcInstance)

## The game this horde serves (`zz_game.gd`), untyped: it preloads this file.
var game = null
var config: ZzConfig = null

var spawner: GSNpcSpawner = null
## The game's end of the monsters' host seam (also the spawner's meta `zhm_host`).
var monster_host: MonsterHost = null
var director: GSNpcDirector = null
## Every spawn point the graph gave, safe rooms left out: the wanderers' and the notes' ground. The
## director's own `spawn_points` are those a zombie can walk to a survivor from ([code]_keep_reaching[/code]).
var spawn_ground: PackedVector3Array = PackedVector3Array()
var _spawn_ground_nodes: PackedInt32Array = PackedInt32Array()
## Seconds between [code]_keep_reaching[/code] passes, and the horde time of the next one.
const REACH_REFRESH := 1.0
var _reach_due: float = 0.0
var senses: GSNpcSenses = null
var squads: GSNpcAiSquads = GSNpcAiSquads.new()

## The server's `npc_skill`, `npc_reaction_scale` and `npc_reaction_min`, which move every kind
## toward easy or nightmare without making them one monster (gs-npc-ai's [GSNpcAiSkill]).
var skill: GSNpcAiSkill = GSNpcAiSkill.new()
var sounds: GSNpcAiSounds = GSNpcAiSounds.new()
var nav: GSNpcNavData = null

## The map's annotations worked into chokes, drops and holds (`ZzNavNotes`); never null.
var notes: ZzNavNotes = ZzNavNotes.new()

## Graph points a brute does not fit at (kept off its paths), for suites and describe.
var narrow_points: int = 0
var catalogue: GSNpcCatalogue = null

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

## Every living zombie by four-metre cell, built once a tick ([method _rebuild_grid]) for spacing and threat scans.
## The script grid (by path: an old pack shell lacks the class name), or gs-sim's `GSSimCrowdGrid` (same answers
## to the bit) while [member ZzConfig.native_crowd] is on and the library is loaded: untyped, so either answers.
const CrowdGrid := preload("res://addons/gs_npc_ai/steer/gs_npc_ai_crowd_grid.gd")
const NATIVE_CROWD := &"GSSimCrowdGrid"
var crowd: Variant = CrowdGrid.new(GRID)
## Whether [member crowd] is the native grid now.
var crowd_native: bool = false

## gs-sim's `GSSimZombieBrains` while [member ZzConfig.native_brains] is on and the library is loaded, else null:
## the commons' chase plan off a survivor table fed once a tick ([code]_feed_brains[/code]).
const NATIVE_BRAINS := &"GSSimZombieBrains"
var brains_native: Object = null
## What the brains' think glue asks (swing clock, stuck watchdog, think rate, the commons' kind machine): gs-sim's
## `GSSimZombieThink` while [member ZzConfig.native_brains] is on and the library has it, else the script twin
## (`zz_think_core.gd`, the same answers to the bit; `headless_native_think`). Never null.
const NATIVE_THINK := &"GSSimZombieThink"
var think_core: Object = preload("../npcs/zz_think_core.gd").new()
var think_native: bool = false
## What a brain asks while the brains think in [method tick] (null outside it, so a tool or suite that calls a brain
## by hand gets the script): [member brains_native], and the native crowd for the spaced heading when it is on too.
var brains_now: Object = null
var brains_crowd: Variant = null
## [member brains_now] while its library steers too ([code]steer_step[/code]; an older one only plans), else null.
var brains_steer: Object = null
## [member brains_now] while it holds this map's barricades ([code]set_barricades[/code]; an older library has none),
## else null: what [code]_bash_if_barred[/code] asks instead of [method barricade_in_way].
var brains_barred: Object = null
## The native brains [method set_barricades] last handed the barricades to, so a new one gets them too.
var _barricades_native: Object = null
## The bash reach it was handed with: the script reads the config's each time, so a changed one leaves it to the script.
var _barricades_reach: float = 0.0
## Re-run the script beside every native answer and count; the script's answer is the one used (bench
## `--brains-verify`, `headless_native_brains`).
var brains_verify: bool = false
var brains_decided: int = 0
var brains_mismatches: int = 0
var _brain_ids: Array[StringName] = []
var _brain_at := PackedVector3Array()
var _brain_flags := PackedInt32Array()
var _crowd_npcs: Array[GSNpcInstance] = []
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

## How a zombie falls when it dies: gs-player-char's reactions, picked here on the server from
## the killing hit and sent with the zombie's end (NPC_GONE), so every screen draws the same fall.
var death_reactions: GSPlayerDeathReactions = GSPlayerDeathReactions.stock()

## Screams heard this map, for a suite and `describe`.
var screams: int = 0

var _world: Node3D = null
var _by_entity: Dictionary = {}
var _candidates: Array = []
var _survivors: Dictionary = {}
## Per survivor id, the [member _survivors] facts and the perception candidate, refilled in place each tick
## (nothing holds either past the tick). A new nine-key dictionary and Candidate per survivor per tick
## was most of _rebuild_candidates' 2.9 ms on PH with 100 survivors.
var _facts_of: Dictionary = {}
var _cand_of: Dictionary = {}
var _doc: Dictionary = {}
## The server-only `hulls/<id>.nav.json` of a map whose boxes the wire budget cut ([method ZzMap.read_nav_extra]).
var _nav_extra: Dictionary = {}

var _usable_posts: Array = []
var _usable_posts_for: GSNpcNavData = null
var _populated: bool = true
var _time: float = 0.0

## Infected that make no progress toward the survivors: repath, then relocate near them out of sight.
var stuck := GSNpcStuckRescue.new()
## Sideways nudges given to stuck infected (a repath step), for [method describe].
var stuck_nudges: int = 0

## Time of the last "stuck infected repathed" log line, and repaths left unlogged since.
var stuck_log_at: float = -1.0
var stuck_log_skipped: int = 0
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


