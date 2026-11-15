extends DotConfig

const ZzCapsScript := preload("zz_caps.gd")

## Every number this game has, layered like every other [DotConfig] in the family:
## [code]exported defaults < JSON file < environment < command line[/code].
##
## [b]Metres and seconds.[/b] The maps are documents in the same units (see [ZzMapDoc]), so a
## length a mapper writes and a length this file tunes against are the same number.
##
## [b]Every rule here is a default, not a decision.[/b] A server owner changes any of them in
## `user://cfg/zombiezone.json`, an environment variable (`ZZ_DIFFICULTY`) or a flag
## (`--zz-difficulty`), and the commonly turned ones are cvars as well (see
## `ZzModule._add_tunables`). The defaults are the co-operative survival genre's: four people,
## a horde that comes in waves, specials that punish whoever strays, and a down rather than a
## death for the first two mistakes.

# --- The HUD ----------------------------------------------------------------

@export_group("The HUD")
## The top-left list of team-mates with their health bars. Off by default: the Tab board
## carries each survivor's health and downs left, and a long list of bars is noise on a big
## team. A server setting (`zz_team_roster`, replicated), so every client follows it.
@export var team_roster: bool = false

# --- The round -------------------------------------------------------------

@export_group("The round")

## Seconds between maps.
@export_range(0.0, 60.0, 1.0, "or_greater") var intermission_seconds: float = 10.0

## Seconds of the map's final killcam, added to the intermission (`mp_killcam_time`); 0 is off, the shipped default (the code stays for a server that wants it). Not added when the intermission is 0.
@export_range(0.0, 30.0, 0.5, "or_greater") var killcam_seconds: float = 0.0

## Seconds of warmup before the first round. 0 starts immediately.
@export_range(0.0, 300.0, 1.0, "or_greater") var warmup_seconds: float = 10.0

## Seconds the start area holds the director off, unless somebody leaves it first.
##
## [b]Leaving starts it, not the clock.[/b] A team that wants a minute to sort out its weapons
## gets it; one that runs out at once is met at once. This is only the ceiling.
@export_range(0.0, 600.0, 1.0, "or_greater") var start_grace_seconds: float = 60.0

## Seconds every survivor still standing must be inside the end area for the map to be won.
@export_range(0.0, 30.0, 0.5, "or_greater") var end_hold_seconds: float = 3.0

## What happens after a map is lost: 0 play it again, 1 move on.
@export_enum("retry", "next") var map_on_loss: int = 0

## How many times a lost map is played again before the server moves on regardless.
@export_range(0, 20, 1, "or_greater") var retries: int = 2

## Seconds a survival map is held for in the `clock` style, when the map does not say. 0: as
## long as you can.
@export_range(0.0, 7200.0, 10.0, "or_greater") var survive_seconds: float = 480.0

# --- Survival ----------------------------------------------------------------

@export_group("Survival")

## How a survival map is held (dot-npc-ai-director's [DotNpcDirectorWaves]):
## [codeblock]
## waves    a breather, then wave after wave, each a crowd to kill and bigger than the last
## nights   a day to get ready, then a night to live through, harder every night
## clock    one stretch of time that gets worse the longer it runs (the old survival)
## [/codeblock]
@export_enum("waves", "nights", "clock") var survival_style: int = 0

## Waves to clear, or nights to live through.
@export_range(1, 50, 1, "or_greater") var waves: int = 10
@export_range(1, 20, 1, "or_greater") var nights: int = 5

## Seconds of setup before a survival map's first wave or night (buy, position, load out):
## no zombie exists until it ends. 0 skips it. Cvar zz_prestart_time.
@export_range(0.0, 300.0, 1.0, "or_greater") var prestart_seconds: float = 30.0

## Overrides the prestart when 0 or more (zz_survival_warmup); -1 follows [member prestart_seconds].
@export_range(-1.0, 300.0, 1.0, "or_greater") var survival_warmup_seconds: float = -1.0

## Whether the dead come back as each breather begins (zz_respawn_on_wave_end).
@export var respawn_on_wave_end: bool = true

## Timed respawn (zz_timed_respawn), off by default: a dead survivor returns after
## [method ZzRespawn.delay] seconds, replacing the slow rescue clock. See the README.
@export var timed_respawn: bool = false
@export_range(0.0, 600.0, 1.0, "or_greater") var respawn_base_seconds: float = 30.0
@export_range(0.0, 600.0, 1.0, "or_greater") var respawn_min_seconds: float = 8.0
@export_range(0.0, 600.0, 1.0, "or_greater") var respawn_max_seconds: float = 90.0
## Delay multiplier with the whole team up, and with nearly everybody down.
@export_range(0.0, 10.0, 0.05, "or_greater") var respawn_healthy_scale: float = 0.5
@export_range(0.0, 10.0, 0.05, "or_greater") var respawn_scarce_scale: float = 2.0
## Seconds added per wave after the first.
@export_range(0.0, 120.0, 1.0, "or_greater") var respawn_per_wave_seconds: float = 2.0
## Fraction of the delay added per difficulty step above normal (taken off below it).
@export_range(0.0, 1.0, 0.05) var respawn_difficulty_step: float = 0.0
## Seconds the returned survivor cannot be hurt.
@export_range(0.0, 30.0, 0.5, "or_greater") var respawn_protect_seconds: float = 3.0

## Seconds into a round after which some survivors turn into zombies (cvar zz_infect_after). 0 is off.
@export_range(0.0, 600.0, 1.0, "or_greater") var infect_after_seconds: float = 0.0

## How many survivors turn (zz_infect_count); the last one never does.
@export_range(1, 32, 1, "or_greater") var infect_count: int = 1

## The zombie kind a turned survivor becomes (zz_infect_kind).
@export var infect_kind: String = "common"

## The setup seconds in force.
func setup_seconds() -> float:
	return survival_warmup_seconds if survival_warmup_seconds >= 0.0 else prestart_seconds

## Seconds of breather between waves: the downed are up, the dead are back, the caches
## restock, and the barricades want mending.
@export_range(0.0, 300.0, 5.0, "or_greater") var breather_seconds: float = 30.0

## Seconds of day between nights, and of a night.
@export_range(10.0, 900.0, 5.0, "or_greater") var day_seconds: float = 60.0
@export_range(10.0, 1800.0, 10.0, "or_greater") var night_seconds: float = 150.0

## The first wave's commons for one survivor, and how many more for each further survivor.
@export_range(1, 400, 1, "or_greater") var wave_size: int = 16
@export_range(0, 50, 1, "or_greater") var wave_size_per_survivor: int = 4

## How much bigger each wave (or harder each night) is than the first, as a share of it, and
## the square term that makes the last waves a wall (see [DotNpcDirectorWaves.strength_of]).
@export_range(0.0, 2.0, 0.01, "or_greater") var wave_growth: float = 0.22
@export_range(0.0, 0.5, 0.005, "or_greater") var wave_growth_accel: float = 0.018

## Specials a wave brings: one from the second wave plus this many for each wave past the
## first, for every [member survivors_per_wave_special] survivors (never fewer than one share).
## At 0.6 and four a share a team of twelve met thirteen specials in a third-wave hunters twist
## and lost (zz-survival-retune-1; docs/survival.md).
@export_range(0.0, 5.0, 0.05, "or_greater") var wave_specials_growth: float = 0.6
@export_range(1.0, 32.0, 0.5, "or_greater") var survivors_per_wave_special: float = 6.0

## A wave down to this share of the team in stragglers (never fewer than three) ends 30 s after
## its last release: a few commons lost in a far corner held every wave to its overtime.
@export_range(0.0, 2.0, 0.05) var wave_straggler_share: float = 0.5

## The share of the commons cap a wave may have up at once in its first wave, growing to the
## whole cap by the last: a crowd as big as the server carries from wave 1 made every later wave
## a wall (zz-survival-retune-1; docs/survival.md).
@export_range(0.1, 1.0, 0.05) var wave_alive_share: float = 0.4

## Health everybody standing gets back in a breather.
@export_range(0.0, 100.0, 5.0, "or_greater") var breather_heal: float = 30.0

## Every this many waves a brute comes with the wave (and two with the last). 0 never.
@export_range(0, 50, 1, "or_greater") var brute_every_waves: int = 5

## Whether waves from the third on draw a twist (sprinters, a swarm, heavies, hunters).
@export var wave_twists: bool = true

## A barricade's strength, when the map does not say, and what one zombie's bashing takes off
## it a second (a brute's is ten times that).
@export_range(10.0, 10000.0, 10.0, "or_greater") var barricade_health: float = 500.0
@export_range(0.0, 200.0, 0.5, "or_greater") var barricade_bash: float = 6.0

## What one repair (holding E on a barricade) puts back, and how long it takes.
@export_range(1.0, 2000.0, 5.0, "or_greater") var barricade_repair: float = 120.0
@export_range(0.2, 10.0, 0.1, "or_greater") var barricade_repair_seconds: float = 2.0

# --- Trader ------------------------------------------------------------------

@export_group("Trader")

## Operator overrides of the `game: shop:` block of `dot_weapon/spawner.yml` (docs/operators.md); -1 leaves the file in charge.
## `zz_trader`: 0 no trader on any map, 1 one.
@export_range(-1, 1) var trader_enabled: int = -1
## `zz_trader_when`: 0 the setup period only, 1 setup and a survival map's breathers, 2 always.
@export_range(-1, 2, 1.0, "or_greater") var trader_when: int = -1
## `zz_trader_despawn`: 1 the shelf is gone when closed, 0 it stays standing and refuses to sell.
@export_range(-1, 1) var trader_despawn: int = -1
## Per phase, whether the trader sells (1 yes, 0 no, -1 derives it from `zz_trader_when`): `zz_trader_setup` before a map starts and between maps, `zz_trader_grace` in the grace after it starts, `zz_trader_breather` in a survival map's breathers, `zz_trader_round` while the horde is on.
@export_range(-1, 1) var trader_setup: int = -1
@export_range(-1, 1) var trader_grace: int = -1
@export_range(-1, 1) var trader_breather: int = -1
@export_range(-1, 1) var trader_round: int = -1
## `zz_trader_closed_message`: what a survivor is told on E at a closed trader; empty is silent.
@export var trader_closed_message: String = "Trader closed: round in progress"
## `zz_grace_maps`: which maps get the start grace, 0 none, 1 escape (exodus) maps only, 2 every map.
@export_range(0, 2, 1.0, "or_greater") var grace_maps: int = 1
## `zz_escape_grace_seconds`: seconds after a map starts with no zombies (none spawn, none are woken, none target anyone). 0 is off. Set before the map starts.
@export_range(0.0, 600.0, 1.0, "or_greater") var escape_grace_seconds: float = 30.0
## `zz_grace_hud`: 1 shows "Zombies arrive in 0:23" on the HUD.
@export_range(0, 1) var grace_hud: int = 1
## `zz_start_points`: the points every survivor starts a map with; -1 reads the file (per difficulty and mode).
@export_range(-1, 1000000, 1.0, "or_greater") var start_points: int = -1

# --- Difficulty ------------------------------------------------------------

@export_group("Difficulty")

## 0 easy, 1 normal, 2 advanced, 3 expert. Scales what a zombie's hit does, how much a special
## can take, and friendly fire. See [method damage_scale].
@export_enum("easy", "normal", "advanced", "expert") var difficulty: int = 1

## What a teammate's bullet does to you, as a fraction of what it would do to a zombie, before
## difficulty. The genre's answer to "spray into the crowd your friend is in".
@export_range(0.0, 1.0, 0.01) var friendly_fire: float = 0.1

## What a teammate's bullet does to you: 0 nothing, 1 the share above (friendly fire), 2 the
## same but a NEW player's (under [member rookie_minutes] played) is reflected onto themselves
## and the teammate they hit takes nothing, 3 everybody's is reflected. 2 by default: the player
## who does not yet know to stop spraying pays for it, and a veteran's slip still hurts a friend.
@export_enum("off", "on", "reflect new players", "reflect everybody") var friendly_fire_mode: int = 2

## Playtime under which a player is new, in minutes (lifetime where progress is kept, this
## session where it is not). 0 makes nobody new.
@export_range(0.0, 100000.0, 1.0, "or_greater") var rookie_minutes: float = 120.0

## The window, in seconds, that team damage is added up over.
@export_range(5.0, 3600.0, 1.0, "or_greater") var team_damage_window: float = 60.0

## Team damage dealt within the window that starts a voteban against the player, through
## dot-vote's API. 0 never. Counted before reflection, so a new player being reflected still
## runs up their total.
@export_range(0.0, 100000.0, 5.0, "or_greater") var team_damage_vote: float = 150.0

## Team damage within the window that bans the player outright, for [member team_damage_ban_minutes].
## 0 never. A hard ceiling: nobody votes on it and staff are not exempt from nothing but staff.
@export_range(0.0, 100000.0, 5.0, "or_greater") var team_damage_ban: float = 400.0
@export_range(1.0, 100000.0, 1.0, "or_greater") var team_damage_ban_minutes: float = 30.0

## Whether humans walk through a barricade (and so can go outside) without breaking it: the
## zombies are still held by it and shots still stop on it. `zz_pass_barricades`.
@export var humans_pass_barricades: bool = true

## The team an exodus map is filled to with stand-ins, at least (a survival map says its own).
## An exodus is a long walk and four survivors for the whole of it is a lonely one.
@export_range(0, 24, 1, "or_greater") var exodus_team: int = 8

# --- Navigation notes ------------------------------------------------------

## Whether a built navigation graph is kept in `user://nav_cache` and loaded next time, keyed by
## the map's contents: a large map takes a minute or more to build and milliseconds to load.
## `zz_nav_cache`.
@export var nav_cache: bool = true

## Worker tasks a navigation build uses, off the main thread, in a hosted game; the graph of a large
## map takes a minute or more to build. 1 builds on one background thread, more split the heavy passes
## across that many; 0 (and every platform without threads) builds on the main thread in slices of
## [member nav_budget_ms] a tick. `zz_nav_threads`.
@export_range(0, 16, 1, "or_greater") var nav_threads: int = 2

## Milliseconds a tick a main-thread navigation build may take. `zz_nav_budget_ms`.
@export_range(0.5, 14.0, 0.5, "or_greater") var nav_budget_ms: float = 6.0

## Whether a map is annotated (dot-npc-ai's drops, chokepoints and covered spots) after its
## bake, and the bots and the horde use what it finds. Off plays as before the annotations.
## `zz_nav_notes`.
@export var nav_notes: bool = true

## Side of the square tiles a navigation bake is cut into, metres; 0 = auto: one grid while the map is
## within the engine's 30 million cells (as before), else 128 m tiles joined into one mesh. A size the
## engine would refuse fails the bake saying so. `zz_nav_notes_bake_tile`.
@export_range(0.0, 512.0, 1.0, "or_greater") var nav_notes_bake_tile: float = 0.0

## Seconds a zombie may try to move without getting anywhere before it is freed; 0 turns it off. `zz_unstick_seconds`.
@export_range(0.0, 30.0, 0.5, "or_greater") var unstick_seconds: float = 4.0

## The longest drop, in metres, a zombie takes off a ledge. `zz_nav_drop`.
@export_range(1.0, 10.0, 0.5, "or_greater") var nav_drop_max: float = 4.0

## Whether the zombies step down ledges the annotations found (a balcony is a way in, never a way
## up). `zz_zombie_drops`.
@export var zombie_drops: bool = true

## Whether a zombie climbs the jump ups too, which lets it up a ledge a survivor holds. Off, so a
## tower is defensible. `zz_zombie_climb`.
@export var zombie_climb: bool = false

## Whether each zombie is sent through one of the chokes on the way, the least used, so a horde
## arrives by every way in and not down one in a line. `zz_zombie_spread`.
@export var zombie_spread: bool = true

## Whether a zombie reads its squad's sightings when it thinks instead of each sighting calling
## the whole horde (DotNpcAiSquads.pull_reports). Read at map load.
@export var squad_pull_reports: bool = true

## Seconds between a zombie's reads of its squad's sightings (the log keeps them, so this only delays news). 0 reads on every think.
@export_range(0.0, 2.0, 0.05, "or_greater") var squad_pull_interval: float = 0.15

## How far a zombie's goal may move, as a share of the distance to it, before its route is searched again.
@export_range(0.0, 1.0, 0.05) var repath_drift_ratio: float = 0.25

## Seconds per metre to its goal added to a zombie's forced re-search (1.5 s): 0.1 makes one 30 m off re-plan every 3 s.
@export_range(0.0, 0.5, 0.01) var repath_interval_per_m: float = 0.1

## Scales the distances past which a zombie thinks and moves less often (6, 20 and 45 m to its
## nearest survivor; its body steps every other tick past 30 m). Below 1 is cheaper. `zz_zombie_think_range`.
@export_range(0.25, 4.0, 0.05, "or_greater") var think_range: float = 1.0

## Metres to the nearest survivor past which a zombie's body moves every second tick (before `think_range`). `zz_body_stride_near`.
@export_range(5.0, 500.0, 1.0, "or_greater") var body_stride_near: float = 20.0
## Metres past which a zombie's body moves every fourth tick. `zz_body_stride_far`.
@export_range(5.0, 500.0, 1.0, "or_greater") var body_stride_far: float = 45.0
## Metres past which a zombie in the open moves by three rays instead of a capsule sweep, which
## costs a tenth; any wall ahead or a missing floor still sweeps. 0 always sweeps.
@export_range(0.0, 500.0, 1.0, "or_greater") var body_cheap_from: float = 12.0

## Metres to the nearest survivor past which a zombie is dormant: it thinks every `dormant_think_every` ticks and its body moves every eighth (`think_range` scales it). Meant for 100+ survivors on big maps, where most of the horde is far from everybody. 0 is off. `zz_dormant_from`.
@export_range(0.0, 1000.0, 1.0, "or_greater") var dormant_from: float = 0.0
## Ticks a dormant zombie's thought spans (at least 8). `zz_dormant_think_every`.
@export_range(8, 64, 1, "or_greater") var dormant_think_every: int = 16
## Thoughts a zombie keeps following the waypoint it was given while its goal drifts under 3 m and it stays within 2 m of
## where it asked, instead of asking the graph again each thought. 0 (the default) asks every thought: on the 56-zombie
## bench 4 moved brains -6%, +1%, -3% and -3% on three boxes, inside the noise (docs/survival.md). `zz_path_reuse_thoughts`.
@export_range(0, 64, 1, "or_greater") var path_reuse_thoughts: int = 0
## Whether the horde's crowd grid (spacing and who is near, rebuilt each tick) runs in dot-sim's native
## `DotSimCrowdGrid` when the library is loaded: the same indices and pushes to the bit as dot-npc-ai's
## script grid, which false (or no library, the web) keeps. `zz_native_crowd`.
@export var native_crowd: bool = true

## Most stand-ins a server keeps at once (people not counted); 0 is no cap. Each costs about 0.2 ms a tick at 64 Hz, so a big
## team on a small box is people plus this many. `zz_bot_max`.
@export_range(0, 256, 1, "or_greater") var bot_max: int = 0

## A stand-in with nothing pressed, nothing switching or reloading, ticks its weapon every this many
## ticks (staggered per stand-in). 1 ticks every tick; the idle path is cheap since dot-weapon 0.1.39.
## `zz_bot_weapon_idle_every`.
@export_range(1, 16, 1, "or_greater") var bot_weapon_idle_every: int = 1

## A stand-in standing still (grounded, no velocity, nothing pressed, every motor timer at rest)
## runs its motor every this many ticks, staggered per stand-in: the tick would change nothing, and
## costs 290 us. 1 ticks every tick. `zz_bot_motor_idle_every`.
@export_range(1, 16, 1, "or_greater") var bot_motor_idle_every: int = 4

## A stand-in with no zombie within `bot_calm_radius` and no person within this many metres moves its
## motor every second tick with two ticks' time and decides every `bot_decide_every_far` ticks: far
## from anyone watching, the same walk costs half. 0 ticks every stand-in fully. `zz_bot_motor_stride_far`.
@export_range(0.0, 500.0, 1.0, "or_greater") var bot_motor_stride_far: float = 0.0

## Metres of clear ground from the nearest zombie that make a stand-in calm (see `bot_motor_stride_far`).
@export_range(4.0, 32.0, 1.0, "or_greater") var bot_calm_radius: float = 18.0

## A calm stand-in far from every person decides every this many ticks (staggered). 2 is the pace of
## every standing post. `zz_bot_decide_every_far`.
@export_range(2, 16, 1, "or_greater") var bot_decide_every_far: int = 4

## A drawn solo world moves the horde once per drawn frame, with up to this many ticks' time,
## rather than once per physics step: a slow frame then pays for the crowd once, not once per
## catch-up step. 0 keeps it on every step (servers and headless runs always do).
@export_range(0, 8, 1.0, "or_greater") var horde_frame_ticks: int = 4

## A drawn solo world's cap on physics steps per drawn frame (the engine's is 8): a frame slower
## than this many ticks slows the game instead of spiralling. Online never changes it. 0 keeps 8.
@export_range(0, 8, 1.0, "or_greater") var solo_max_steps: int = 3

## Whether a survival map's stand-ins hold the place behind a choke on the horde's route, in
## place of a post at a window. `zz_bot_hold_chokes`.
@export var bot_hold_chokes: bool = true

## Zombies within four and a half metres of a choke that make it overrun: the stand-ins holding it
## fall back along the route. `zz_bot_hold_overrun`.
@export_range(2, 40, 1, "or_greater") var bot_hold_overrun: int = 6

## Which bot personas the stand-ins are drawn from, as `id:weight,id:weight` (a bare id weighs 1); empty uses every `cfg/.../bot/*.yml` by its own weight. `zz_bot_personas`.
@export var bot_personas: String = ""

## Whether infected that make no progress toward the survivors are repathed, then moved near them out of sight. `zz_stuck_rescue`.
@export var stuck_rescue: bool = true

## Seconds without getting closer before an infected is repathed. `zz_stuck_repath_seconds`.
@export_range(1.0, 120.0, 1.0, "or_greater") var stuck_repath_seconds: float = 6.0

## Seconds without getting closer before it is moved near the survivors, out of sight. `zz_stuck_relocate_seconds`.
@export_range(2.0, 300.0, 1.0, "or_greater") var stuck_relocate_seconds: float = 14.0

## Seconds the places a zombie stalled at cost the whole horde extra to path through.
@export_range(0.0, 600.0, 1.0, "or_greater") var stuck_bad_edge_seconds: float = 60.0

## At or under this many infected left, those waits shrink to a third. 0 off. `zz_stuck_low_count`.
@export_range(0, 100, 1, "or_greater") var stuck_low_count: int = 8

## Relocations that changed nothing after which a stuck infected is removed and the wave owes it again. 0 never. `zz_stuck_remove_after`.
@export_range(0, 10, 1, "or_greater") var stuck_remove_after: int = 2

## Seconds between "stuck infected repathed" log lines; repaths in between are counted and reported on the next line. 0 logs every one. `zz_stuck_log_interval`.
@export_range(0.0, 300.0, 1.0, "or_greater") var stuck_log_interval: float = 5.0

## A graph edge that rises more than this many metres is taken down only (a drop seen from below is a wall). 0 off. `zz_nav_steep`.
@export_range(0.0, 20.0, 0.1, "or_greater") var nav_steep: float = 1.2

## Whether stand-ins pick up the boxes zombies drop and open them. Off leaves every box to the humans. `zz_bot_open_boxes`.
@export var bot_open_boxes: bool = true

## Whether a stand-in lets go of E every few ticks while going for a box, so a press that missed is made again. Off holds it as before, and a box may stand untouched. `zz_bot_repress_use`.
@export var bot_repress_use: bool = true

## Whether stand-ins pick up a defibrillator and shock a dead friend back with it. `zz_bot_defib`.
@export var bot_defib: bool = true

## Metres a stand-in holding a defibrillator will walk to a dead friend's body. `zz_bot_defib_reach`.
@export_range(1.0, 200.0, 1.0, "or_greater") var bot_defib_reach: float = 40.0

## Seconds a stand-in that wants an item or a place may stay put, not firing or using anything, before it gives that goal up (and, with none, is put at its post). 0 off. `zz_bot_idle_seconds`.
@export_range(0.0, 120.0, 1.0, "or_greater") var bot_idle_seconds: float = 12.0

## How many stand-ins answer a pinned or downed friend on a survival map: the nearest standing
## ones. The rest hold their posts; with every one walking to a single friend a ram at a dugout
## downed all sixteen of the ballpark's team (docs/survival.md). 0: all of them, as an exodus map
## does. `zz_bot_helpers`.
@export_range(0, 16, 1, "or_greater") var bot_helpers: int = 2

## Metres within which any stand-in answers a pinned or downed friend on a survival map, however
## many already are. `zz_bot_helper_radius`.
@export_range(0.0, 40.0, 0.5, "or_greater") var bot_helper_radius: float = 8.0

## The share of the cap a wave may have up at once, for a map that needs more than `wave_alive_share`
## (map id to share). The ballpark's cap is so large a team of sixteen cleared every wave a size
## factor could ask of it; room, not size, is what made its middle waves hard.
@export var wave_alive_share_by_map: Dictionary = {"zz_stadium": 1.0, "zz_high_school": 0.55}

## A survival map's waves are this many times the size the team asks for (map id to factor; a
## map not named is 1.0). A bigger team has more guns per zombie than the count per survivor
## makes up for, and the stand-ins answered the ballpark's every wave until this. `zz_wave_scale_<id>`
## is not a cvar: it is a measured table (docs/survival.md).
@export var wave_scale_by_map: Dictionary = {"zz_stadium": 5.0, "zz_high_school": 1.3, "zz_mall": 1.15, "zz_relief_camp": 0.85}

## The wave set `sv_waves` names (cfg/game/game-zombie-zone/waves/<id>.yml); empty lets the rotation entry, the map document or the cvars above decide.
@export var waves_set: String = ""

# --- The survivors ---------------------------------------------------------
