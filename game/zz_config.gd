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

## Seconds of quiet before the first wave or night: time to find the doors and the caches.
@export_range(0.0, 300.0, 5.0) var survival_warmup_seconds: float = 30.0

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

## Whether a map is annotated (dot-npc-ai's drops, chokepoints and covered spots) after its
## bake, and the bots and the horde use what it finds. Off plays as before the annotations.
## `zz_nav_notes`.
@export var nav_notes: bool = true

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

## Whether a survival map's stand-ins hold the place behind a choke on the horde's route, in
## place of a post at a window. `zz_bot_hold_chokes`.
@export var bot_hold_chokes: bool = true

## Zombies within four and a half metres of a choke that make it overrun: the stand-ins holding it
## fall back along the route. `zz_bot_hold_overrun`.
@export_range(2, 40, 1) var bot_hold_overrun: int = 6

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
## `downed_crawl_speed`). 0 keeps them where they fell, as downs were before crawling. A run is
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

## What everybody starts a map holding, by weapon id. The first is drawn.
@export var start_weapons: PackedStringArray = PackedStringArray(["pistol", "knife"])

## How many medkits and pills each survivor starts a map with.
@export_range(0, 1, 1) var start_medkits: int = 1
@export_range(0, 1, 1) var start_pills: int = 0

@export_range(1.0, 20.0, 0.1) var run_speed: float = 6.2
@export_range(0.1, 1.0, 0.01) var walk_speed_scale: float = 0.45
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
@export_range(0.0, 100.0, 0.5) var common_damage: float = 2.0

## Seconds between a common's swings.
@export_range(0.2, 5.0, 0.05) var common_attack_interval: float = 0.9

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

## How many boxes a survivor carries (E picks one up; the deploy key opens it). 0: no carrying, E
## opens a box on the ground as it did before boxes could be carried.
@export_range(0, 6, 1) var box_carry: int = 1

## Seconds the deploy key is held to open a carried box (server file key `box_deploy_seconds`,
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

## Boxes lying about at once; past it, the oldest goes.
@export_range(1, 200, 1) var max_boxes: int = 16

## Whether boxes exist at all.
@export var boxes_enabled: bool = true

# --- The maps --------------------------------------------------------------

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

## Seed every random choice is drawn from.
@export var seed_value: int = 20261010

## Whether zed-dot-weapons (real-world guns, launchers, a flamethrower, molotovs, pipe bombs
## and bile jars) is carried beside zee-dot-weapons. Read when a world is built.
@export var second_weapon_pack: bool = true

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
	return commons_base + commons_per_survivor * first + (commons_per_survivor * past) / 3


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

	return DotResult.success(null)


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
