extends DotConfig

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
@export_range(0.0, 60.0, 1.0) var intermission_seconds: float = 10.0

## Seconds of the map's final killcam, added to the intermission (`mp_killcam_time`); 0 is off, the shipped default (the code stays for a server that wants it). Not added when the intermission is 0.
@export_range(0.0, 30.0, 0.5) var killcam_seconds: float = 0.0

## Seconds of warmup before the first round. 0 starts immediately.
@export_range(0.0, 300.0, 1.0) var warmup_seconds: float = 10.0

## Seconds the start area holds the director off, unless somebody leaves it first.
##
## [b]Leaving starts it, not the clock.[/b] A team that wants a minute to sort out its weapons
## gets it; one that runs out at once is met at once. This is only the ceiling.
@export_range(0.0, 600.0, 1.0) var start_grace_seconds: float = 60.0

## Seconds every survivor still standing must be inside the end area for the map to be won.
@export_range(0.0, 30.0, 0.5) var end_hold_seconds: float = 3.0

## What happens after a map is lost: 0 play it again, 1 move on.
@export_enum("retry", "next") var map_on_loss: int = 0

## How many times a lost map is played again before the server moves on regardless.
@export_range(0, 20, 1) var retries: int = 2

## Seconds a survival map is held for in the `clock` style, when the map does not say. 0: as
## long as you can.
@export_range(0.0, 7200.0, 10.0) var survive_seconds: float = 480.0

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
@export_range(1, 50, 1) var waves: int = 10
@export_range(1, 20, 1) var nights: int = 5

## Seconds of setup before a survival map's first wave or night (buy, position, load out):
## no zombie exists until it ends. 0 skips it. Cvar zz_prestart_time.
@export_range(0.0, 300.0, 1.0) var prestart_seconds: float = 30.0

## Overrides the prestart when 0 or more (zz_survival_warmup); -1 follows [member prestart_seconds].
@export_range(-1.0, 300.0, 1.0) var survival_warmup_seconds: float = -1.0

## Whether the dead come back as each breather begins (zz_respawn_on_wave_end).
@export var respawn_on_wave_end: bool = true

## Timed respawn (zz_timed_respawn), off by default: a dead survivor returns after
## [method ZzRespawn.delay] seconds, replacing the slow rescue clock. See the README.
@export var timed_respawn: bool = false
@export_range(0.0, 600.0, 1.0) var respawn_base_seconds: float = 30.0
@export_range(0.0, 600.0, 1.0) var respawn_min_seconds: float = 8.0
@export_range(0.0, 600.0, 1.0) var respawn_max_seconds: float = 90.0
## Delay multiplier with the whole team up, and with nearly everybody down.
@export_range(0.0, 10.0, 0.05) var respawn_healthy_scale: float = 0.5
@export_range(0.0, 10.0, 0.05) var respawn_scarce_scale: float = 2.0
## Seconds added per wave after the first.
@export_range(0.0, 120.0, 1.0) var respawn_per_wave_seconds: float = 2.0
## Fraction of the delay added per difficulty step above normal (taken off below it).
@export_range(0.0, 1.0, 0.05) var respawn_difficulty_step: float = 0.0
## Seconds the returned survivor cannot be hurt.
@export_range(0.0, 30.0, 0.5) var respawn_protect_seconds: float = 3.0

## The setup seconds in force.
func setup_seconds() -> float:
	return survival_warmup_seconds if survival_warmup_seconds >= 0.0 else prestart_seconds

## Seconds of breather between waves: the downed are up, the dead are back, the caches
## restock, and the barricades want mending.
@export_range(0.0, 300.0, 5.0) var breather_seconds: float = 30.0

## Seconds of day between nights, and of a night.
@export_range(10.0, 900.0, 5.0) var day_seconds: float = 60.0
@export_range(10.0, 1800.0, 10.0) var night_seconds: float = 150.0

## The first wave's commons for one survivor, and how many more for each further survivor.
@export_range(1, 400, 1) var wave_size: int = 16
@export_range(0, 50, 1) var wave_size_per_survivor: int = 4

## How much bigger each wave (or harder each night) is than the first, as a share of it, and
## the square term that makes the last waves a wall (see [DotNpcDirectorWaves.strength_of]).
@export_range(0.0, 2.0, 0.01) var wave_growth: float = 0.22
@export_range(0.0, 0.5, 0.005) var wave_growth_accel: float = 0.018

## Specials a wave brings: one from the second wave plus this many for each wave past the
## first, for every [member survivors_per_wave_special] survivors (never fewer than one share).
## At 0.6 and four a share a team of twelve met thirteen specials in a third-wave hunters twist
## and lost (zz-survival-retune-1; docs/survival.md).
@export_range(0.0, 5.0, 0.05) var wave_specials_growth: float = 0.6
@export_range(1.0, 32.0, 0.5) var survivors_per_wave_special: float = 6.0

## A wave down to this share of the team in stragglers (never fewer than three) ends 30 s after
## its last release: a few commons lost in a far corner held every wave to its overtime.
@export_range(0.0, 2.0, 0.05) var wave_straggler_share: float = 0.5

## The share of the commons cap a wave may have up at once in its first wave, growing to the
## whole cap by the last: a crowd as big as the server carries from wave 1 made every later wave
## a wall (zz-survival-retune-1; docs/survival.md).
@export_range(0.1, 1.0, 0.05) var wave_alive_share: float = 0.4

## Health everybody standing gets back in a breather.
@export_range(0.0, 100.0, 5.0) var breather_heal: float = 30.0

## Every this many waves a brute comes with the wave (and two with the last). 0 never.
@export_range(0, 50, 1) var brute_every_waves: int = 5

## Whether waves from the third on draw a twist (sprinters, a swarm, heavies, hunters).
@export var wave_twists: bool = true

## A barricade's strength, when the map does not say, and what one zombie's bashing takes off
## it a second (a brute's is ten times that).
@export_range(10.0, 10000.0, 10.0) var barricade_health: float = 500.0
@export_range(0.0, 200.0, 0.5) var barricade_bash: float = 6.0

## What one repair (holding E on a barricade) puts back, and how long it takes.
@export_range(1.0, 2000.0, 5.0) var barricade_repair: float = 120.0
@export_range(0.2, 10.0, 0.1) var barricade_repair_seconds: float = 2.0

# --- Trader ------------------------------------------------------------------

@export_group("Trader")

## Operator overrides of the `game: shop:` block of `dot_weapon/spawner.yml` (docs/operators.md); -1 leaves the file in charge.
## `zz_trader`: 0 no trader on any map, 1 one.
@export_range(-1, 1) var trader_enabled: int = -1
## `zz_trader_when`: 0 the setup period only, 1 setup and a survival map's breathers, 2 always.
@export_range(-1, 2) var trader_when: int = -1
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
@export_range(0, 2) var grace_maps: int = 1
## `zz_escape_grace_seconds`: seconds after a map starts with no zombies (none spawn, none are woken, none target anyone). 0 is off. Set before the map starts.
@export_range(0.0, 600.0, 1.0) var escape_grace_seconds: float = 30.0
## `zz_grace_hud`: 1 shows "Zombies arrive in 0:23" on the HUD.
@export_range(0, 1) var grace_hud: int = 1
## `zz_start_points`: the points every survivor starts a map with; -1 reads the file (per difficulty and mode).
@export_range(-1, 1000000) var start_points: int = -1

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
@export_range(0.0, 100000.0, 1.0) var rookie_minutes: float = 120.0

## The window, in seconds, that team damage is added up over.
@export_range(5.0, 3600.0, 1.0) var team_damage_window: float = 60.0

## Team damage dealt within the window that starts a voteban against the player, through
## dot-vote's API. 0 never. Counted before reflection, so a new player being reflected still
## runs up their total.
@export_range(0.0, 100000.0, 5.0) var team_damage_vote: float = 150.0

## Team damage within the window that bans the player outright, for [member team_damage_ban_minutes].
## 0 never. A hard ceiling: nobody votes on it and staff are not exempt from nothing but staff.
@export_range(0.0, 100000.0, 5.0) var team_damage_ban: float = 400.0
@export_range(1.0, 100000.0, 1.0) var team_damage_ban_minutes: float = 30.0

## Whether humans walk through a barricade (and so can go outside) without breaking it: the
## zombies are still held by it and shots still stop on it. `zz_pass_barricades`.
@export var humans_pass_barricades: bool = true

## The team an exodus map is filled to with stand-ins, at least (a survival map says its own).
## An exodus is a long walk and four survivors for the whole of it is a lonely one.
@export_range(0, 24, 1) var exodus_team: int = 8

# --- Navigation notes ------------------------------------------------------

## Whether a built navigation graph is kept in `user://nav_cache` and loaded next time, keyed by
## the map's contents: a large map takes a minute or more to build and milliseconds to load.
## `zz_nav_cache`.
@export var nav_cache: bool = true

## Worker tasks a navigation build uses, off the main thread, in a hosted game; the graph of a large
## map takes a minute or more to build. 1 builds on one background thread, more split the heavy passes
## across that many; 0 (and every platform without threads) builds on the main thread in slices of
## [member nav_budget_ms] a tick. `zz_nav_threads`.
@export_range(0, 16, 1) var nav_threads: int = 2

## Milliseconds a tick a main-thread navigation build may take. `zz_nav_budget_ms`.
@export_range(0.5, 14.0, 0.5) var nav_budget_ms: float = 6.0

## Whether a map is annotated (dot-npc-ai's drops, chokepoints and covered spots) after its
## bake, and the bots and the horde use what it finds. Off plays as before the annotations.
## `zz_nav_notes`.
@export var nav_notes: bool = true

## Seconds a zombie may try to move without getting anywhere before it is freed; 0 turns it off. `zz_unstick_seconds`.
@export_range(0.0, 30.0, 0.5) var unstick_seconds: float = 4.0

## The longest drop, in metres, a zombie takes off a ledge. `zz_nav_drop`.
@export_range(1.0, 10.0, 0.5) var nav_drop_max: float = 4.0

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
@export_range(0.0, 2.0, 0.05) var squad_pull_interval: float = 0.15

## How far a zombie's goal may move, as a share of the distance to it, before its route is searched again.
@export_range(0.0, 1.0, 0.05) var repath_drift_ratio: float = 0.25

## Seconds per metre to its goal added to a zombie's forced re-search (1.5 s): 0.1 makes one 30 m off re-plan every 3 s.
@export_range(0.0, 0.5, 0.01) var repath_interval_per_m: float = 0.1

## Scales the distances past which a zombie thinks and moves less often (6, 20 and 45 m to its
## nearest survivor; its body steps every other tick past 30 m). Below 1 is cheaper. `zz_zombie_think_range`.
@export_range(0.25, 4.0, 0.05) var think_range: float = 1.0

## A drawn solo world moves the horde once per drawn frame, with up to this many ticks' time,
## rather than once per physics step: a slow frame then pays for the crowd once, not once per
## catch-up step. 0 keeps it on every step (servers and headless runs always do).
@export_range(0, 8) var horde_frame_ticks: int = 4

## Whether a survival map's stand-ins hold the place behind a choke on the horde's route, in
## place of a post at a window. `zz_bot_hold_chokes`.
@export var bot_hold_chokes: bool = true

## Zombies within four and a half metres of a choke that make it overrun: the stand-ins holding it
## fall back along the route. `zz_bot_hold_overrun`.
@export_range(2, 40, 1) var bot_hold_overrun: int = 6

## Which bot personas the stand-ins are drawn from, as `id:weight,id:weight` (a bare id weighs 1); empty uses every `cfg/.../bot/*.yml` by its own weight. `zz_bot_personas`.
@export var bot_personas: String = ""

## Whether infected that make no progress toward the survivors are repathed, then moved near them out of sight. `zz_stuck_rescue`.
@export var stuck_rescue: bool = true

## Seconds without getting closer before an infected is repathed. `zz_stuck_repath_seconds`.
@export_range(1.0, 120.0, 1.0) var stuck_repath_seconds: float = 3.0

## Seconds without getting closer before it is moved near the survivors, out of sight. `zz_stuck_relocate_seconds`.
@export_range(2.0, 300.0, 1.0) var stuck_relocate_seconds: float = 8.0

## At or under this many infected left, those waits shrink to a third. 0 off. `zz_stuck_low_count`.
@export_range(0, 100, 1) var stuck_low_count: int = 8

## Relocations that changed nothing after which a stuck infected is removed and the wave owes it again. 0 never. `zz_stuck_remove_after`.
@export_range(0, 10, 1) var stuck_remove_after: int = 2

## A graph edge that rises more than this many metres is taken down only (a drop seen from below is a wall). 0 off. `zz_nav_steep`.
@export_range(0.0, 20.0, 0.1) var nav_steep: float = 1.2

## Whether stand-ins pick up the boxes zombies drop and open them. Off leaves every box to the humans. `zz_bot_open_boxes`.
@export var bot_open_boxes: bool = true

## Whether a stand-in lets go of E every few ticks while going for a box, so a press that missed is made again. Off holds it as before, and a box may stand untouched. `zz_bot_repress_use`.
@export var bot_repress_use: bool = true

## Seconds a stand-in that wants an item or a place may stay put, not firing or using anything, before it gives that goal up (and, with none, is put at its post). 0 off. `zz_bot_idle_seconds`.
@export_range(0.0, 120.0, 1.0) var bot_idle_seconds: float = 12.0

## How many stand-ins answer a pinned or downed friend on a survival map: the nearest standing
## ones. The rest hold their posts; with every one walking to a single friend a ram at a dugout
## downed all sixteen of the ballpark's team (docs/survival.md). 0: all of them, as an exodus map
## does. `zz_bot_helpers`.
@export_range(0, 16, 1) var bot_helpers: int = 2

## Metres within which any stand-in answers a pinned or downed friend on a survival map, however
## many already are. `zz_bot_helper_radius`.
@export_range(0.0, 40.0, 0.5) var bot_helper_radius: float = 8.0

## The share of the cap a wave may have up at once, for a map that needs more than `wave_alive_share`
## (map id to share). The ballpark's cap is so large a team of sixteen cleared every wave a size
## factor could ask of it; room, not size, is what made its middle waves hard.
@export var wave_alive_share_by_map: Dictionary = {"zz_stadium": 1.0, "zz_high_school": 0.55}

## A survival map's waves are this many times the size the team asks for (map id to factor; a
## map not named is 1.0). A bigger team has more guns per zombie than the count per survivor
## makes up for, and the stand-ins answered the ballpark's every wave until this. `zz_wave_scale_<id>`
## is not a cvar: it is a measured table (docs/survival.md).
@export var wave_scale_by_map: Dictionary = {"zz_stadium": 5.0, "zz_high_school": 1.3, "zz_mall": 1.15, "zz_relief_camp": 0.85}

# --- The survivors ---------------------------------------------------------

@export_group("The survivors")

@export_range(1.0, 400.0, 1.0) var max_health: float = 100.0

## Below this health a survivor limps: slower (by `ZzController.LIMP`, which both ends
## register identically, so how much slower is not a server setting), and told so by the screen.
@export_range(0.0, 100.0, 1.0) var limp_health: float = 40.0

## Temporary health (pills, a revive) drains this much a second.
@export_range(0.0, 10.0, 0.01) var temp_decay_per_second: float = 0.27

## Downs a survivor survives before the next one kills: the third time is death.
@export_range(0, 10, 1) var max_incaps: int = 2

## A downed survivor's pool, and how fast it bleeds away a second.
@export_range(10.0, 2000.0, 10.0) var downed_health: float = 300.0

## Metres per second a downed survivor crawls at (`zz_down_crawl_speed`, also the file key
## `downed_crawl_speed`). 0 keeps them where they fell, as downs were before crawling. A run was
## 6.2, so the default is a fifth of it: enough to reach a friend, never to escape the horde.
@export_range(0.0, 6.0, 0.1) var downed_crawl_speed: float = 1.4
@export_range(0.0, 100.0, 0.1) var downed_bleed_per_second: float = 3.0

## Seconds of holding E to pick somebody up, and the temporary health they get up with.
@export_range(0.5, 30.0, 0.1) var revive_seconds: float = 5.0
@export_range(1.0, 100.0, 1.0) var revive_health: float = 30.0

## Metres a reviver may be from the downed.
@export_range(0.5, 5.0, 0.1) var revive_range: float = 1.9

## Seconds before a dead survivor is rescued: back in, beside whoever is furthest along, with
## half health and a sidearm. 0 never: the dead watch until the map ends.
@export_range(0.0, 600.0, 5.0) var rescue_seconds: float = 75.0

## Whether a survivor below the map's floor plane is put back on the last ground they stood on
## (`zz_fall_rescue`); off, they die at the kill height.
@export var fall_rescue: bool = true

## Seconds a survivor may push on the world without moving before they are put back on the last ground (0 off).
@export_range(0.0, 600.0, 1.0) var stuck_rescue_seconds: float = 12.0

## What everybody starts a map holding, by weapon id. The first is drawn.
@export var start_weapons: PackedStringArray = PackedStringArray(["zz_pistol", "zz_knife"])

## How many medkits and pills each survivor starts a map with.
@export_range(0, 1, 1) var start_medkits: int = 1
@export_range(0, 1, 1) var start_pills: int = 0

@export_range(1.0, 20.0, 0.1) var run_speed: float = 4.3
@export_range(0.1, 1.0, 0.01) var walk_speed_scale: float = 0.45

## Sprint (Shift, hold): a modest boost over a run so it never outruns a zombie. Each is `sv_sprint*` / `sv_stamina*` in dot-player-controller.
@export var sprint_enabled: bool = true
@export_range(1.0, 2.0, 0.01) var sprint_speed_scale: float = 1.45
@export var stamina_enabled: bool = true
@export_range(0.0, 10.0, 0.01) var stamina_drain: float = 0.2
@export_range(0.0, 10.0, 0.01) var stamina_recover: float = 0.15
@export_range(0.0, 1.0, 0.01) var stamina_resume_at: float = 0.3
@export_range(0.0, 3.5, 0.05) var stamina_exhaust_delay: float = 1.5
## How strongly the carried share of the weight limit cuts the sprint bonus and raises the drain; 0 off.
@export_range(0.0, 2.0, 0.01) var sprint_load_speed: float = 1.0
@export_range(0.0, 4.0, 0.01) var sprint_load_drain: float = 1.0
## Whether sprinting stops aiming down sights and reloading.
@export var sprint_blocks_aim: bool = true
## Whether Shift toggles sprint instead of being held.
@export var sprint_toggle: bool = false
@export_range(0.1, 5.0, 0.05) var jump_height: float = 1.1
@export_range(1.0, 60.0, 0.5) var gravity: float = 20.0
@export_range(0.0, 200.0, 1.0) var air_accelerate: float = 12.0

# --- Items -----------------------------------------------------------------

@export_group("Items")

## A medkit heals this share of what is missing, after this long holding it.
@export_range(0.1, 1.0, 0.05) var medkit_heal_fraction: float = 0.8
@export_range(0.5, 20.0, 0.5) var medkit_seconds: float = 4.5

## Temporary health a bottle of pills gives.
@export_range(1.0, 100.0, 1.0) var pills_health: float = 50.0

## The defibrillator: held E at a dead teammate's body shocks them back (a downed one is picked up
## by hand as ever). Each key is also a cvar, `zz_defib_*`; see the README.
## Whether each survivor starts a map holding one (0 or 1).
@export_range(0, 1, 1) var start_defibs: int = 0
## Seconds E is held at the body, and the metres from it.
@export_range(0.5, 30.0, 0.1) var defib_charge_seconds: float = 4.0
@export_range(0.5, 5.0, 0.1) var defib_range: float = 2.0
## Share of maximum health the revived come back with, and seconds they cannot be hurt.
@export_range(0.05, 1.0, 0.05) var defib_revive_fraction: float = 0.4
@export_range(0.0, 15.0, 0.5) var defib_invulnerable_seconds: float = 2.0
## Revives one item holds, and seconds after a shock before the next try.
@export_range(1, 7, 1) var defib_charges: int = 1
@export_range(0.0, 120.0, 0.5) var defib_cooldown_seconds: float = 8.0
## Seconds after death beyond which the body is past saving (0: never).
@export_range(0.0, 600.0, 1.0) var defib_max_body_age: float = 60.0
## Metres the user may drift while charging before it is interrupted.
@export_range(0.1, 3.0, 0.1) var defib_move_tolerance: float = 0.6

## Metres from the eye an item may be picked up or a box opened.
@export_range(0.5, 5.0, 0.1) var use_reach: float = 2.2

# --- The shove -------------------------------------------------------------

@export_group("The shove")

## Seconds between shoves, and how much each shove in a row adds to it after the fourth.
@export_range(0.1, 5.0, 0.05) var shove_cooldown: float = 0.7
@export_range(0.0, 2.0, 0.05) var shove_fatigue: float = 0.35

## Reach and half-angle of a shove.
@export_range(0.5, 5.0, 0.1) var shove_range: float = 2.0
@export_range(10.0, 90.0, 1.0) var shove_half_angle: float = 55.0

## Damage a shove does to a common, which is nothing much: it is for room, not for killing.
@export_range(0.0, 100.0, 1.0) var shove_damage: float = 5.0

# --- The horde -------------------------------------------------------------

@export_group("The horde")

## Common infected alive at once, for one survivor and for each more.
@export_range(0, 400, 1) var commons_base: int = 24
@export_range(0, 50, 1) var commons_per_survivor: int = 6
## Most commons alive at once whatever the survivor count; 0 leaves [method commons_cap] uncapped.
@export_range(0, 2000, 1) var commons_max: int = 0

## Commons standing about a map at its start, per hundred square metres of walkable floor.
@export_range(0.0, 10.0, 0.05) var wanderer_density: float = 0.55

## Seconds between mobs, from and to. A mob is a crowd that knows where you are.
@export_range(10.0, 900.0, 5.0) var mob_interval_min: float = 90.0
@export_range(10.0, 900.0, 5.0) var mob_interval_max: float = 180.0

## Commons in a mob, and how many more for each survivor.
@export_range(1, 200, 1) var mob_size: int = 14
@export_range(0, 40, 1) var mob_size_per_survivor: int = 3

## A common's health, speed running and walking, and what its hit does on normal.
@export_range(1.0, 1000.0, 1.0) var common_health: float = 50.0
@export_range(1.0, 15.0, 0.1) var common_run_speed: float = 6.3
@export_range(0.2, 5.0, 0.1) var common_walk_speed: float = 1.1

## How fast a common chases (`zz_common_speed_*`). Scaling on: it starts at `common_speed_base`,
## gains `common_speed_per_hard_stack` per Hard Box stack and stops at `common_speed_max`;
## `angry_runner_fraction` of the crowd runs at `common_run_speed` while an Angry Box lasts.
## Scaling off (`zz_common_speed_scaling 0`) is the old behaviour: every common runs.
@export var common_speed_scaling: bool = true
@export_range(0.5, 15.0, 0.1) var common_speed_base: float = 2.2
@export_range(0.0, 5.0, 0.05) var common_speed_per_hard_stack: float = 0.8
@export_range(0.5, 15.0, 0.1) var common_speed_max: float = 6.3

## `zz_mutant_fade*`: mutants (every kind but a common) draw more transparent as Hard Box stacks
## rise, `mutant_fade_per_stack` of alpha per stack, never below `mutant_min_alpha`. Drawing only;
## 0 on `mutant_fade` restores the solid look. `common_fade` 1 fades commons the same way.
@export_range(0, 1) var mutant_fade: int = 1
@export_range(0.05, 1.0, 0.01) var mutant_min_alpha: float = 0.25
@export_range(0.0, 0.5, 0.01) var mutant_fade_per_stack: float = 0.1
@export_range(0, 1) var common_fade: int = 0
@export_range(0.0, 1.0, 0.05) var angry_runner_fraction: float = 0.3
@export_range(0.0, 100.0, 0.5) var common_damage: float = 2.0

## Seconds between a common's swings.
@export_range(0.2, 5.0, 0.05) var common_attack_interval: float = 0.9

## Whether zombies kneel and strike a downed survivor, and the damage that blow does compared to a standing hit.
@export var down_attack: bool = true
@export_range(0.0, 10.0, 0.1) var down_attack_damage: float = 1.5

## Commons that may be on one survivor at once; the rest wait their turn round them.
@export_range(1, 20, 1) var attackers_per_survivor: int = 6

## How far gunfire carries to a common, in metres.
@export_range(0.0, 200.0, 1.0) var gunfire_radius: float = 30.0

## Whether the director runs the build-up / peak / relax cycle at all. Off: only mobs.
@export var director_enabled: bool = true

# --- The specials ----------------------------------------------------------

@export_group("The specials")

## Special infected alive at once, for one survivor and one more for each this many survivors.
@export_range(0, 32, 1) var specials_base: int = 2
@export_range(1.0, 32.0, 0.5) var survivors_per_special: float = 3.0

## Seconds between a special dying and the next of any kind, from and to.
@export_range(1.0, 300.0, 1.0) var special_interval_min: float = 18.0
@export_range(1.0, 300.0, 1.0) var special_interval_max: float = 40.0

## Which specials may spawn, by id. Empty means all of them.
@export var special_kinds: PackedStringArray = PackedStringArray()

## Commons a screamer's scream sends at whoever it saw (before survival's growth).
@export_range(0, 100, 1) var screamer_mob: int = 10

## Seconds between one screamer's screams.
@export_range(4.0, 120.0, 1.0) var screamer_cooldown: float = 20.0

## What a crawler's hold on an ankle does a second, on normal.
@export_range(0.0, 50.0, 0.5) var crawler_grab_dps: float = 6.0

## The share of a hit on a riot zombie's shield that gets through (0 none, 1 all of it).
@export_range(0.0, 1.0, 0.01) var riot_shield: float = 0.1

## The chance a special roll may pick the mutant at all (rare), and the first wave it can appear on.
@export_range(0.0, 1.0, 0.01) var mutant_chance: float = 0.12
@export_range(0, 100, 1) var mutant_min_wave: int = 3

## The oil monster: the chance a special roll may pick it (rare), and the first wave it can appear on. Its slide, spit, goo and trail numbers are its profile's keys (`zz_oil_*`).
@export_range(0.0, 1.0, 0.01) var oil_monster_chance: float = 0.3
@export_range(0, 100, 1) var oil_monster_min_wave: int = 2

## The black goo a spit leaves on the screen (drawing only, replicated): how much one stack covers, the most the stacks reach (1 is a blackout).
@export_range(0.0, 1.0, 0.01) var goo_screen_per_stack: float = 0.4
@export_range(0.0, 1.0, 0.01) var goo_screen_max: float = 0.9

## Seconds between brutes, from and to, on a campaign map. 0 never.
@export_range(0.0, 3600.0, 10.0) var brute_interval_min: float = 300.0
@export_range(0.0, 3600.0, 10.0) var brute_interval_max: float = 480.0

## A brute's health for one survivor, and how much more for each further survivor.
@export_range(100.0, 50000.0, 50.0) var brute_health: float = 3000.0
@export_range(0.0, 20000.0, 50.0) var brute_health_per_survivor: float = 900.0

## Whether the crying sleepers a map places are there at all.
@export var sleepers_enabled: bool = true

# --- Boxes -----------------------------------------------------------------

@export_group("Boxes")

## Where the boxes and what they do are read from, relative to this game's root.
@export var box_file: String = "boxes/boxes.json"

## Chance a common drops a box when it dies, and a special, and a brute. A common was 1.2% (one in eighty), so a solo run of a few dozen kills saw no loot at all; 4% is about one a minute at a hold's pace.
@export_range(0.0, 1.0, 0.001) var box_drop_common: float = 0.04
@export_range(0.0, 1.0, 0.01) var box_drop_special: float = 0.3
@export_range(0.0, 1.0, 0.01) var box_drop_brute: float = 1.0

## Seconds of holding E to open a box lying on the ground when nobody can carry one
## ([member box_carry] 0), and how long an unopened one lies there.
@export_range(0.0, 10.0, 0.1) var box_open_seconds: float = 0.8
@export_range(5.0, 1200.0, 5.0) var box_lifetime: float = 150.0

## How many boxes a survivor carries (E picks one up into the hands; primary fire held opens it). 0: no carrying, E
## opens a box on the ground as it did before boxes could be carried.
@export_range(0, 6, 1) var box_carry: int = 1

# --- Physics crates (zz_crates.gd) -----------------------------------------

## Ammo piles and boxes on the ground are rigid bodies: pushed along by survivors and zombies, shot, thrown by blasts (cvar `zz_physics_crates`). 0 keeps them where the map or the drop put them.
@export var physics_crates: bool = true

## Which loot kinds are crates, comma separated (ammo, box, medkit, pills, weapon, throwable, defib).
@export var crate_kinds: String = "ammo,box"

## A crate's mass in kilograms, against a walking survivor's push (`crate_push` scales it) and a blast.
@export_range(0.25, 200.0, 0.25) var crate_mass: float = 8.0

## How hard a walk pushes a crate, against the walker's speed (0: nothing pushes one), and whether zombies push too.
@export_range(0.0, 4.0, 0.05) var crate_push: float = 1.0
@export var crate_zombie_push: bool = true

## How hard a blast throws a crate, against a barrel's blast speed (0: blasts leave crates alone).
@export_range(0.0, 8.0, 0.05) var crate_blast: float = 1.0

## The most crates simulating at once; the longest untouched sleep first. A crate at rest for `crate_sleep_seconds` sleeps (0: the engine's own timer).
@export_range(1, 256, 1) var crate_max_active: int = 16
@export_range(0.0, 30.0, 0.1) var crate_sleep_seconds: float = 2.0

## Times a second the moved crates' places go to clients.
@export_range(1.0, 30.0, 1.0) var crate_sync_hz: float = 10.0

## Most crate bodies in the world; loot laid beyond it lies static, as with `zz_physics_crates 0`.
@export_range(1, 2048, 1) var crate_max_bodies: int = 128

## A crate this far below where it last rested has fallen out of the map (a drop over a pit) and is recovered (0: only the map's kill height counts).
@export_range(0.0, 200.0, 1.0) var crate_fall_limit: float = 15.0

## What becomes of a lost crate: back to where it last rested (never rested: gone), or just gone.
@export_enum("rest", "remove") var crate_lost: int = 0

## Seconds primary fire is held to open a carried box (server file key `box_deploy_seconds`,
## cvar `zz_box_deploy_seconds`, 0.5 to 15), and the radius (metres) the survivor may drift in
## meanwhile before it is cancelled. 1 s is quick enough to open one mid-fight; it was 3.5, which
## nobody did with a horde about, so boxes were only ever opened in the safe room.
@export_range(0.5, 15.0, 0.1) var box_deploy_seconds: float = 1.0
@export_range(0.2, 6.0, 0.1) var box_deploy_radius: float = 1.2

## Whether a box on the ground and in the slot says what type it is. Off (the default): every
## box looks the same and what is in it is a surprise until it is opened; the server never sends
## the type, only the outcome once it is opened. On: the type is shown on the ground and in the hands.
@export var box_labels: bool = false

## Instakill, the first named box: the duration it lasts (seconds, uniform between; a negative
## minimum or maximum leaves boxes.json's own), and what a special takes per hit as a multiple of
## its damage (a common simply dies).
@export var box_instakill_min: float = -1.0
@export var box_instakill_max: float = -1.0
@export_range(1.0, 100.0, 0.5) var box_instakill_special_scale: float = 4.0

## Great Depression box: every shop price is multiplied by this per box in force; its weight-limit cut is `depression` in `zz_weight_modifiers`.
@export_range(1.0, 10.0, 0.05) var box_depression_price: float = 1.5

## A limb's health follows the zombie's actual health (a later wave's, a brute's), and Instakill's
## boosted damage does not reach limbs; off restores the old limb rules (zz_limb_follow_health).
@export var limb_follow_health: bool = true

## Boxes lying about at once; past it, the oldest goes.
@export_range(1, 200, 1) var max_boxes: int = 16

## Whether boxes exist at all.
@export var boxes_enabled: bool = true

# --- The maps --------------------------------------------------------------

@export_group("Carry weight")

## Master switch for `zz_weight_*`: every weapon has a weight, a survivor a carry limit, and slots may hold several weapons.
@export var weight_enabled: bool = true

## What a survivor with no backpack carries, in weight units (kilograms: a pistol is about 1, a rifle 4).
@export_range(0.0, 1000.0, 0.5) var weight_limit: float = 14.0

## Every weapon's weight is multiplied by this, on top of the box modifiers.
@export_range(0.0, 10.0, 0.05) var weight_multiplier: float = 1.0

## Weapons one slot holds; pressing the slot key again cycles through them.
@export_range(1, 8, 1) var weight_slot_capacity: int = 2

## Over the limit (a limit that fell, a box that made weapons heavier): `slow` slows the survivor down, `drop` makes them drop the heaviest spare weapon.
@export_enum("slow", "drop") var weight_over_limit: String = "slow"

## The slowest an overloaded survivor goes, as a share of normal speed.
@export_range(0.05, 1.0, 0.05) var weight_slow_floor: float = 0.55

## Capacity a backpack of tier 1, 2, 3... adds, comma separated. Empty: no backpacks.
@export var weight_backpack_tiers: String = "4,8,14"

## Shop price of backpack tier 1, 2, 3...
@export var weight_backpack_prices: String = "300,600,1000"

## What an active box effect does to carrying, `effect=weight_factor[/limit_factor[/limit_add]]`, comma separated, once per stack. Any effect name works (hard, angry, a later Great Depression box).
@export var weight_modifiers: String = "hard=1.15,angry=1.1/0.9,depression=1/0.75"

@export_group("Gore")

## How much dismemberment there is (dot-npc's DotNpcGore): 0 none (limbs cannot be shot off), 1 clean stumps, 2 flying limbs and blood (the default), 3 limbs give way sooner and the spray is heavier. Family-friendly servers set 0. `zz_gore_level`.
@export_range(0, 3, 1) var gore_level: int = 2

## The most severed limbs lying about at once on a machine; the oldest is recycled. 0 throws none. `zz_gore_max_gibs`.
@export_range(0, 200, 1) var gore_max_gibs: int = 24

## Wound marks on bodies plus blood pools under crawling zombies, at most this many on a machine (drawn only; the oldest is recycled). 0 draws none. `zz_gore_max_wounds`.
@export_range(0, 400, 1) var gore_max_wounds: int = 48

@export_group("The maps")

## Which maps this server may play, by id. Empty means every one it has.
@export var map_ids: PackedStringArray = PackedStringArray()

## Whether the next map is drawn at random (seeded) rather than taken in order; a campaign
## map's `next` always wins over both.
@export var shuffle_maps: bool = false

## The file that says which maps this server ROTATES: `cfg/maps.yml` (dot-map's
## `DotMapRotationFile`: named rotations, `random` or `cycle`, wildcards, command names), looked
## for in the `--config` directory. Empty, or no such file, rotates every map. A map it leaves out
## stays installed (`zz_map <id>` and the map menu load it); it is only never drawn, balloted or
## nominated. A rotation in the file replaces [member shuffle_maps]. `sv_map_rotation_file`.
@export var map_rotation_file: String = "cfg/maps.yml"

## Where map documents are read from, relative to this game's root.
@export var map_directory: String = "maps"

## How the client culls a world: off, pvs, occluders or both (dot-map's DotMapVisibility). Empty
## leaves it to the client's video setting. `--zz-vis-mode=`.
@export var vis_mode: String = ""

## Draws a converted map with the author's baked lighting when its world pack carries it. Off draws the
## lit materials and the document's lamps. `--zz-lightmaps=`.
@export var lightmaps: bool = true

## The least mean light a drawn converted map's surfaces and a survivor's ambient have, so a map the author lit darkly can be played (dot-map's `DotMapBspMesh.visibility_floor`, tinted by the map's own ambient). 0 is the author's light alone. `--zz-light-floor=`.
@export_range(0.0, 2.0) var light_floor: float = 0.6

## The least energy of a lightmapped map's sun on a client, for the shadowed interiors of a dim map (0 leaves the map's own). `--zz-sun-floor=`.
@export_range(0.0, 2.0) var sun_floor: float = 0.6

## Whether a drawn world's sun shadow comes from one shadows-only proxy per chunk (cheap) instead of every material's surfaces. `--zz-shadow-proxy=`.
@export var shadow_proxy: bool = true

## Metres beyond which a chunk's shadow proxy is not drawn into the sun's cascades (0: all are). `--zz-shadow-range=`.
@export_range(0.0, 1000.0, 1.0, "or_greater") var shadow_range: float = 0.0

## Whether foliage and glass cards cast a sun shadow (costly: their alpha is tested in the shadow pass). Needs `shadow_proxy`. `--zz-shadow-translucent=`.
@export var shadow_translucent: bool = false

## Cascades of the sun's shadow on a client: 1, 2 or 4. Every cascade draws each caster in it again, so 4 (the old look) is
## about twice the draws of 2 on a converted map. `--zz-sun-shadow-splits=`.
@export_range(1, 4) var sun_shadow_splits: int = 2

## Props whose longest side is under this many metres cast no sun shadow on a client (0: all do, as before). A can's shadow
## is a draw call a player never reads. `--zz-prop-shadow-min=`.
@export var prop_shadow_min: float = 1.2

## Triangles a library model's mesh must have before a client simplifies it into LOD levels (0: never; a scanned tree is over a million, and a street of them was the frame). Read when a world is built. `--zz-prop-lod-min-tris=`.
@export var prop_lod_min_tris: int = 20000

## Most triangles a library model's mesh keeps at full detail on a client (0: its own): a scanned tree of 1.6 million is cut to about this before its LODs are made. Read when a world is built. `--zz-prop-max-tris=`.
@export var prop_max_tris: int = 150000

## Pixels of error a mesh may show before the engine picks a finer LOD, on a client: higher is coarser and cheaper (1 is the engine's own). `--zz-mesh-lod-threshold=`.
@export_range(0.0, 16.0) var mesh_lod_threshold: float = 1.0

## Seed every random choice is drawn from.
@export var seed_value: int = 20261010

# --- Netcode ----------------------------------------------------------------

@export_group("Netcode")

## Metres within which a survivor is sent a common's and a special's updates (live). A client hides
## a mirror the server stopped sending, so either can change mid-round.
@export_range(40.0, 1000.0, 5.0) var net_common_radius: float = 80.0
@export_range(40.0, 1000.0, 5.0) var net_special_radius: float = 260.0
## Anything past [member net_far_distance] metres from a survivor (players included, never their
## own) is sent every Nth snapshot only. 1 is off; dot-net's DotNetInterest.far_every.
@export_range(1, 16, 1) var net_far_every: int = 1
@export_range(0.0, 1000.0, 5.0) var net_far_distance: float = 40.0
## Every survivor far from a zombie skips the same snapshots of it, so the server encodes it once
## for all of them (DotNetInterest.far_coherent). Off staggers each survivor's turns.
@export var net_far_coherent: bool = false
## Bands past [member net_far_distance], each twice as far and sent half as often (1 is one band).
@export_range(1, 4, 1) var net_far_tiers: int = 1

# --- Bots ------------------------------------------------------------------

@export_group("Bots")

## How many survivors the server keeps in the game by adding stand-ins.
@export_range(0, 24, 1) var minimum_players: int = 4

## Whether a map that says how big a team it is built for (its `survivors`) raises that number
## to it: a high school wants a dozen, a street four.
@export var team_from_map: bool = true

# How a stand-in aims and how quickly it reacts are dot-bot's `bot_*` settings, shared by every
# game (`bot_difficulty`, `bot_reaction`, `bot_aim_error`, ...), not numbers of this file.

# --- Watching --------------------------------------------------------------

@export_group("Watching")

## Who somebody who is out may watch: 0 anybody, 1 their own side, 2 nobody.
@export_enum("anybody", "own side", "nobody") var spectate_camera: int = 0

# --- Progress --------------------------------------------------------------

@export_group("Progress")

@export var keep_progress: bool = true
@export var progress_directory: String = ""
@export var report_progress: bool = false


func env_prefix() -> String:
	return "ZZ_"


func cli_prefix() -> String:
	return "--zz-"


## What a zombie's hit is worth at this difficulty, as a multiple of the normal one.
##
## The genre's ladder, roughly: easy is a third, normal is the number, advanced is two and a
## half times it, expert is a common taking five off with every hit — which is what makes
## being surrounded on expert a down in two seconds.
func damage_scale() -> float:
	return [0.35, 1.0, 2.5, 5.0][clampi(difficulty, 0, 3)]


## How much a special can take, as a multiple of its normal health.
func special_health_scale() -> float:
	return [0.75, 1.0, 1.15, 1.3][clampi(difficulty, 0, 3)]


## A teammate's bullet, as a multiple of what it would do to a zombie.
func friendly_fire_scale() -> float:
	if friendly_fire_mode == 0:
		return 0.0
	return friendly_fire * [0.0, 1.0, 3.0, 8.0][clampi(difficulty, 0, 3)]


## Commons alive at once, for [param survivors]: [member commons_per_survivor] more for each of
## the first eight, a third of that for each past them. A dozen survivors meet 74 at once and
## sixteen 82, which is what a server's 64 Hz tick carries at wave 10 with the stand-ins (half
## past eight, 78 and 90, measured 16 and 18 ms a tick at the cap; see docs/survival.md); a
## wave's total is not capped, only how many are up at once.
func commons_cap(survivors: int) -> int:
	var first := mini(maxi(survivors - 1, 0), 7)
	var past := maxi(survivors - 8, 0)
	var cap := commons_base + commons_per_survivor * first + (commons_per_survivor * past) / 3
	return mini(cap, commons_max) if commons_max > 0 else cap


## Specials alive at once, for [param survivors].
func specials_cap(survivors: int) -> int:
	return specials_base + int(floor(float(maxi(survivors - 1, 0)) / maxf(survivors_per_special, 1.0)))


func validate() -> DotResult:
	if mob_interval_min > mob_interval_max:
		return DotResult.fail(DotError.CODE_INVALID, "mob_interval_min is over mob_interval_max.")

	if special_interval_min > special_interval_max:
		return DotResult.fail(DotError.CODE_INVALID, "special_interval_min is over special_interval_max.")

	if brute_interval_min > brute_interval_max:
		return DotResult.fail(DotError.CODE_INVALID, "brute_interval_min is over brute_interval_max.")

	if difficulty < 0 or difficulty > 3:
		return DotResult.fail(DotError.CODE_INVALID,
			"difficulty is %d; it is 0 (easy), 1 (normal), 2 (advanced) or 3 (expert)." % difficulty)

	if survival_style < 0 or survival_style > 2:
		return DotResult.fail(DotError.CODE_INVALID,
			"survival_style is %d; it is 0 (waves), 1 (nights) or 2 (clock)." % survival_style)

	if start_weapons.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "Survivors have to start holding something.")

	if box_deploy_seconds < 0.5 or box_deploy_seconds > 15.0:
		return DotResult.fail(DotError.CODE_INVALID,
			"box_deploy_seconds is %.2f; it is 0.5 to 15 (the cvar zz_box_deploy_seconds clamps the same)." % box_deploy_seconds)

	if downed_crawl_speed < 0.0 or downed_crawl_speed > 6.0:
		return DotResult.fail(DotError.CODE_INVALID,
			"downed_crawl_speed is %.2f; it is 0 (stay put) to 6 metres per second." % downed_crawl_speed)

	if weight_over_limit != "slow" and weight_over_limit != "drop":
		return DotResult.fail(DotError.CODE_INVALID, "weight_over_limit is '%s'; it is slow or drop." % weight_over_limit)

	return DotResult.success(null)


## `@export_group` -> the cfg file it lives in: `cfg/game/game-zombie-zone/config_<file>/game.yml`.
const CFG_FILES := {
	"The HUD": "round", "The round": "round", "Survival": "round", "Trader": "round", "Watching": "round", "Progress": "round",
	"Difficulty": "horde", "The horde": "horde", "The specials": "horde", "Bots": "horde",
	"The survivors": "survivors", "Items": "survivors", "The shove": "survivors", "Boxes": "survivors",
	"Carry weight": "carry", "Gore": "world", "The maps": "world", "Netcode": "world",
}


## The binder every entry point uses: [param config] layered, one cfg file per [constant CFG_FILES] entry.
static func make_binder(config: DotConfig, json_path := "") -> DotGameConfigBinder:
	var b := DotGameConfigBinder.create(config, "game-zombie-zone", "zz", json_path)
	b.grouped = true
	b.group_files = CFG_FILES
	return b


## The layered load through [DotGameConfigBinder] (JSON, cfg/ yml, env, argv; strict on a server). The value is the binder.
static func boot(config: DotConfig, json_path: String) -> DotResult:
	var binder := make_binder(config, json_path)
	var loaded := binder.load_layers()
	if not loaded.ok:
		return loaded
	return DotResult.success(binder)


## The survival style's name, as the cvar and the HUD say it.
func survival_style_name() -> String:
	return ["waves", "nights", "clock"][clampi(survival_style, 0, 2)]


func survival_description() -> String:
	match survival_style:
		0:
			return "%d waves, %.0f s breathers" % [waves, breather_seconds]
		1:
			return "%d nights of %.0f s, %.0f s days" % [nights, night_seconds, day_seconds]
	return "a clock" if survive_seconds <= 0.0 else "%.0f s clock" % survive_seconds


func difficulty_name() -> String:
	return ["easy", "normal", "advanced", "expert"][clampi(difficulty, 0, 3)]


func describe() -> Dictionary:
	return {
		"difficulty": difficulty_name(),
		"horde": "%d + %d/survivor, mobs every %.0f..%.0f s" % [commons_base, commons_per_survivor,
			mob_interval_min, mob_interval_max],
		"specials": "%d + 1 per %.1f survivors, every %.0f..%.0f s" % [specials_base, survivors_per_special,
			special_interval_min, special_interval_max],
		"downs": "%d, then death; rescue %s; crawl %s" % [max_incaps, "off" if rescue_seconds <= 0.0 else "%.0f s" % rescue_seconds,
			"off" if downed_crawl_speed <= 0.0 else "%.1f m/s" % downed_crawl_speed],
		"boxes": "off" if not boxes_enabled else "%.1f%% common, %.0f%% special" % [box_drop_common * 100.0, box_drop_special * 100.0],
		"maps": "all" if map_ids.is_empty() else ",".join(map_ids),
		"bots": "%d%s" % [minimum_players, ", or the map's team" if team_from_map else ""],
		"survival": survival_description(),
	}


func describe_lines(_redact_sensitive: bool = true) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("zombiezone configuration")
	var facts := describe()
	for key: String in facts:
		lines.append("  %-10s %s" % [key, facts[key]])
	return lines
