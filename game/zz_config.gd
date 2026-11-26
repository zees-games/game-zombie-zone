extends "zz_config_base.gd"

const ZzConfigText := preload("zz_config_text.gd")

@export_group("The survivors")

@export_range(1.0, 400.0, 1.0, "or_greater") var max_health: float = 100.0

## The class every survivor starts as (cfg/game/game-zombie-zone/class/<id>.yml, shipped by zz-ply-class-pack, else the built-in survivor). `zz_class_default`.
@export var class_default: String = "survivor"

## Whether a survivor may pick another class with `zz_class <id>` (server-authoritative; lands on the next spawn). Off: everybody is the default class. `zz_class_select`.
@export var class_select: bool = false

## The classes a survivor may pick, as a comma list of ids; empty offers every class whose profile is `selectable`. `zz_class_allowed`.
@export var class_allowed: String = ""

## Below this health a survivor limps: slower (by `ZzController.LIMP`, which both ends
## register identically, so how much slower is not a server setting), and told so by the screen.
@export_range(0.0, 100.0, 1.0, "or_greater") var limp_health: float = 40.0

## Temporary health (pills, a revive) drains this much a second.
@export_range(0.0, 10.0, 0.01, "or_greater") var temp_decay_per_second: float = 0.27

## Downs a survivor survives before the next one kills: the third time is death.
@export_range(0, 10, 1, "or_greater") var max_incaps: int = 2

## A downed survivor's pool, and how fast it bleeds away a second.
@export_range(10.0, 2000.0, 10.0, "or_greater") var downed_health: float = 300.0

## Metres per second a downed survivor crawls at (`zz_down_crawl_speed`, also the file key
## `downed_crawl_speed`). 0 keeps them where they fell, as downs were before crawling. A run was
## 6.2, so the default is a fifth of it: enough to reach a friend, never to escape the horde.
@export_range(0.0, 6.0, 0.1, "or_greater") var downed_crawl_speed: float = 1.4
@export_range(0.0, 100.0, 0.1, "or_greater") var downed_bleed_per_second: float = 3.0

## Seconds of holding E to pick somebody up, and the temporary health they get up with.
@export_range(0.5, 30.0, 0.1, "or_greater") var revive_seconds: float = 5.0
@export_range(1.0, 100.0, 1.0, "or_greater") var revive_health: float = 30.0

## Metres a reviver may be from the downed.
@export_range(0.5, 5.0, 0.1, "or_greater") var revive_range: float = 1.9

## Seconds before a dead survivor is rescued: back in, beside whoever is furthest along, with
## half health and a sidearm. 0 never: the dead watch until the map ends.
@export_range(0.0, 600.0, 5.0, "or_greater") var rescue_seconds: float = 75.0

## Whether a survivor below the map's floor plane is put back on the last ground they stood on
## (`zz_fall_rescue`); off, they die at the kill height.
@export var fall_rescue: bool = true

## Seconds a survivor may push on the world without moving before they are put back on the last ground (0 off).
@export_range(0.0, 600.0, 1.0, "or_greater") var stuck_rescue_seconds: float = 12.0

## Seconds between the samples of safe ground the rescue keeps for a survivor (`zz_footing_sample_every`).
@export_range(0.2, 30.0, 0.1, "or_greater") var footing_sample_every: float = 1.5

## Metres a survivor must have moved since the last sample before another is kept (`zz_footing_sample_move`).
@export_range(0.0, 30.0, 0.1, "or_greater") var footing_sample_move: float = 1.5

## How many safe samples are kept; the rescue puts a survivor back on the oldest (`zz_footing_keep`).
@export_range(1, 30, 1, "or_greater") var footing_keep: int = 5

## Metres of flat travel under which a survivor pushing on the world counts as not moving (`zz_footing_progress`).
@export_range(0.05, 5.0, 0.05, "or_greater") var footing_progress: float = 0.6

## Cosine of the angle off the crosshair within which a friend counts as aimed at by a medkit (`zz_heal_aim_dot`).
@export_range(0.0, 1.0, 0.01) var heal_aim_dot: float = 0.82

## Looser cosine that keeps a heal going while the friend moves a little (`zz_heal_hold_dot`).
@export_range(0.0, 1.0, 0.01) var heal_hold_dot: float = 0.6

## What everybody starts a map holding, by weapon id. The first is drawn.
@export var start_weapons: PackedStringArray = PackedStringArray(["zz_pistol", "zz_knife"])

## How many medkits and pills each survivor starts a map with.
@export_range(0, 7, 1, "or_greater") var start_medkits: int = 1
@export_range(0, 15, 1, "or_greater") var start_pills: int = 0

@export_range(1.0, 20.0, 0.1, "or_greater") var run_speed: float = 4.3
@export_range(0.1, 1.0, 0.01) var walk_speed_scale: float = 0.45

## Sprint (Shift, hold): a modest boost over a run so it never outruns a zombie. Each is `sv_sprint*` / `sv_stamina*` in gs-player-controller.
@export var sprint_enabled: bool = true
@export_range(1.0, 2.0, 0.01, "or_greater") var sprint_speed_scale: float = 1.45
@export var stamina_enabled: bool = true
@export_range(0.0, 10.0, 0.01, "or_greater") var stamina_drain: float = 0.2
@export_range(0.0, 10.0, 0.01, "or_greater") var stamina_recover: float = 0.15
@export_range(0.0, 1.0, 0.01) var stamina_resume_at: float = 0.3
@export_range(0.0, 3.5, 0.05, "or_greater") var stamina_exhaust_delay: float = 1.5
## How strongly the carried share of the weight limit cuts the sprint bonus and raises the drain; 0 off.
@export_range(0.0, 2.0, 0.01, "or_greater") var sprint_load_speed: float = 1.0
@export_range(0.0, 4.0, 0.01, "or_greater") var sprint_load_drain: float = 1.0
## Whether sprinting stops aiming down sights and reloading.
@export var sprint_blocks_aim: bool = true
## Whether Shift toggles sprint instead of being held.
@export var sprint_toggle: bool = false

## Slide top speed; the rest of the slide is the `zz_slide*` cvars.
@export_range(1.0, 30.0, 0.1, "or_greater") var slide_max_speed: float = 10.5
@export_range(0.1, 5.0, 0.05, "or_greater") var jump_height: float = 1.1
@export_range(1.0, 60.0, 0.5, "or_greater") var gravity: float = 20.0
@export_range(0.0, 200.0, 1.0, "or_greater") var air_accelerate: float = 12.0

# Items

@export_group("Items")

## A medkit heals this share of what is missing, after this long holding it.
@export_range(0.1, 1.0, 0.05) var medkit_heal_fraction: float = 0.8
@export_range(0.5, 20.0, 0.5, "or_greater") var medkit_seconds: float = 4.5

## Temporary health a bottle of pills gives.
@export_range(1.0, 100.0, 1.0, "or_greater") var pills_health: float = 50.0

## The defibrillator: held E at a dead teammate's body shocks them back (a downed one is picked up
## by hand as ever). Each key is also a cvar, `zz_defib_*`; see the README.
## Whether each survivor starts a map holding one (0 or 1).
@export_range(0, 1, 1) var start_defibs: int = 0
## Seconds E is held at the body, and the metres from it.
@export_range(0.5, 30.0, 0.1, "or_greater") var defib_charge_seconds: float = 4.0
@export_range(0.5, 5.0, 0.1, "or_greater") var defib_range: float = 2.0
## Share of maximum health the revived come back with, and seconds they cannot be hurt.
@export_range(0.05, 1.0, 0.05) var defib_revive_fraction: float = 0.4
@export_range(0.0, 15.0, 0.5, "or_greater") var defib_invulnerable_seconds: float = 2.0
## Revives one item holds, and seconds after a shock before the next try.
@export_range(1, 7, 1, "or_greater") var defib_charges: int = 1
@export_range(0.0, 120.0, 0.5, "or_greater") var defib_cooldown_seconds: float = 8.0
## Seconds after death beyond which the body is past saving (0: never).
@export_range(0.0, 600.0, 1.0, "or_greater") var defib_max_body_age: float = 60.0
## Metres the user may drift while charging before it is interrupted.
@export_range(0.1, 3.0, 0.1, "or_greater") var defib_move_tolerance: float = 0.6
## Points the trader asks for a defibrillator, and a trader shelf's defibrillator unless its site names a price (0: not sold; a site's own price wins). `zz_defib_price`.
@export_range(0, 100000, 10, "or_greater") var defib_price: int = 400
## Metres from which another survivor hears a defibrillator charging (0: only the user hears it). `zz_defib_hear_range`.
@export_range(0.0, 100.0, 1.0, "or_greater") var defib_hear_range: float = 25.0

## Metres from the eye an item may be picked up or a box opened.
@export_range(0.5, 5.0, 0.1, "or_greater") var use_reach: float = 2.2

# The shove

@export_group("The shove")

## Seconds between shoves, and how much each shove in a row adds to it after the fourth.
@export_range(0.1, 5.0, 0.05, "or_greater") var shove_cooldown: float = 0.7
@export_range(0.0, 2.0, 0.05, "or_greater") var shove_fatigue: float = 0.35

## Reach and half-angle of a shove.
@export_range(0.5, 5.0, 0.1, "or_greater") var shove_range: float = 2.0
@export_range(10.0, 90.0, 1.0) var shove_half_angle: float = 55.0

## Damage a shove does to a common, which is nothing much: it is for room, not for killing.
@export_range(0.0, 100.0, 1.0, "or_greater") var shove_damage: float = 5.0

# The horde

@export_group("The horde")

## Common infected alive at once, for one survivor and for each more.
@export_range(0, 400, 1, "or_greater") var commons_base: int = 24
@export_range(0, 50, 1, "or_greater") var commons_per_survivor: int = 6
## Most commons alive at once whatever the survivor count; 0 leaves [method commons_cap] uncapped.
@export_range(0, 2000, 1, "or_greater") var commons_max: int = 0
## Past sixteen survivors each adds 1 over this of [member commons_per_survivor]: the team, not the horde, sets the server tick there, and a big team is spread over a big map. `zz_commons_far_divisor`.
@export_range(1, 60, 1, "or_greater") var commons_far_divisor: int = 9

## Commons standing about a map at its start, per hundred square metres of walkable floor.
@export_range(0.0, 10.0, 0.05, "or_greater") var wanderer_density: float = 0.55

## Seconds between mobs, from and to. A mob is a crowd that knows where you are.
@export_range(10.0, 900.0, 5.0, "or_greater") var mob_interval_min: float = 90.0
@export_range(10.0, 900.0, 5.0, "or_greater") var mob_interval_max: float = 180.0

## Commons in a mob, and how many more for each survivor.
@export_range(1, 200, 1, "or_greater") var mob_size: int = 14
@export_range(0, 40, 1, "or_greater") var mob_size_per_survivor: int = 3

## A common's health, speed running and walking, and what its hit does on normal.
@export_range(1.0, 1000.0, 1.0, "or_greater") var common_health: float = 50.0
@export_range(1.0, 15.0, 0.1, "or_greater") var common_run_speed: float = 6.3
@export_range(0.2, 5.0, 0.1, "or_greater") var common_walk_speed: float = 1.1

## How fast a common chases (`zz_common_speed_*`). Scaling on: it starts at `common_speed_base`,
## gains `common_speed_per_hard_stack` per Hard Box stack and stops at `common_speed_max`;
## `angry_runner_fraction` of the crowd runs at `common_run_speed` while an Angry Box lasts.
## Scaling off (`zz_common_speed_scaling 0`) is the old behaviour: every common runs.
@export var common_speed_scaling: bool = true
@export_range(0.5, 15.0, 0.1, "or_greater") var common_speed_base: float = 2.2
@export_range(0.0, 5.0, 0.05, "or_greater") var common_speed_per_hard_stack: float = 0.8
@export_range(0.5, 15.0, 0.1, "or_greater") var common_speed_max: float = 6.3

## `zz_mutant_fade*`: mutants (every kind but a common) draw more transparent as Hard Box stacks
## rise, `mutant_fade_per_stack` of alpha per stack, never below `mutant_min_alpha`. Drawing only;
## 0 on `mutant_fade` restores the solid look. `common_fade` 1 fades commons the same way.
@export_range(0, 1) var mutant_fade: int = 1
@export_range(0.05, 1.0, 0.01) var mutant_min_alpha: float = 0.25
@export_range(0.0, 0.5, 0.01) var mutant_fade_per_stack: float = 0.1
@export_range(0, 1) var common_fade: int = 0
@export_range(0.0, 1.0, 0.05) var angry_runner_fraction: float = 0.3
@export_range(0.0, 100.0, 0.5, "or_greater") var common_damage: float = 2.0

## Seconds between a common's swings.
@export_range(0.2, 5.0, 0.05, "or_greater") var common_attack_interval: float = 0.9

## Whether zombies kneel and strike a downed survivor, and the damage that blow does compared to a standing hit.
@export var down_attack: bool = true
@export_range(0.0, 10.0, 0.1, "or_greater") var down_attack_damage: float = 1.5

## Commons that may be on one survivor at once; the rest wait their turn round them.
@export_range(1, 20, 1, "or_greater") var attackers_per_survivor: int = 6

## How far gunfire carries to a common, in metres.
@export_range(0.0, 200.0, 1.0, "or_greater") var gunfire_radius: float = 30.0

## Whether the director runs the build-up / peak / relax cycle at all. Off: only mobs.
@export var director_enabled: bool = true

## Metres a zombie's scream wakes idle commons within, one at a time a beat apart (`zz_alert_radius`).
@export_range(1.0, 100.0, 0.5, "or_greater") var alert_radius: float = 9.0

## Metres within which bile calls every common (`zz_bile_radius`).
@export_range(1.0, 200.0, 1.0, "or_greater") var bile_radius: float = 45.0

## Metres a broken bile jar splashes (`zz_bile_splash`).
@export_range(0.5, 30.0, 0.5, "or_greater") var bile_splash: float = 4.0

## Most zombies of a mob spawned at a time, so a crowd pours out of a doorway (`zz_mob_burst`).
@export_range(1, 50, 1, "or_greater") var mob_burst: int = 6

## Seconds between those bursts (`zz_mob_burst_seconds`).
@export_range(0.05, 10.0, 0.05, "or_greater") var mob_burst_seconds: float = 0.4

## Metres commons standing about a map keep from where the team starts (`zz_wanderer_clearance`).
@export_range(0.0, 200.0, 1.0, "or_greater") var wanderer_clearance: float = 28.0

## Metres past a barricade's face a zombie bashes it from: its radius and an arm (`zz_bash_reach`).
@export_range(0.1, 5.0, 0.05, "or_greater") var bash_reach: float = 0.75

# The specials

@export_group("The specials")

## Special infected alive at once, for one survivor and one more for each this many survivors.
@export_range(0, 32, 1, "or_greater") var specials_base: int = 2
@export_range(1.0, 32.0, 0.5, "or_greater") var survivors_per_special: float = 3.0

## Seconds between a special dying and the next of any kind, from and to.
@export_range(1.0, 300.0, 1.0, "or_greater") var special_interval_min: float = 18.0
@export_range(1.0, 300.0, 1.0, "or_greater") var special_interval_max: float = 40.0

## Which specials may spawn, by id. Empty means all of them.
@export var special_kinds: PackedStringArray = PackedStringArray()

## Commons a screamer's scream sends at whoever it saw (before survival's growth).
@export_range(0, 100, 1, "or_greater") var screamer_mob: int = 10

## Seconds between one screamer's screams.
@export_range(4.0, 120.0, 1.0, "or_greater") var screamer_cooldown: float = 20.0

## What a crawler's hold on an ankle does a second, on normal.
@export_range(0.0, 50.0, 0.5, "or_greater") var crawler_grab_dps: float = 6.0

## The share of a hit on a riot zombie's shield that gets through (0 none, 1 all of it).
@export_range(0.0, 1.0, 0.01) var riot_shield: float = 0.1

## The chance a special roll may pick the mutant at all (rare), and the first wave it can appear on.
@export_range(0.0, 1.0, 0.01) var mutant_chance: float = 0.12
@export_range(0, 100, 1, "or_greater") var mutant_min_wave: int = 3

## The oil monster: the chance a special roll may pick it (rare), and the first wave it can appear on. Its slide, spit, goo and trail numbers are its profile's keys (`zz_oil_*`).
@export_range(0.0, 1.0, 0.01) var oil_monster_chance: float = 0.3
@export_range(0, 100, 1, "or_greater") var oil_monster_min_wave: int = 2

## The black goo a spit leaves on the screen (drawing only, replicated): how much one stack covers, the most the stacks reach (1 is a blackout).
@export_range(0.0, 1.0, 0.01) var goo_screen_per_stack: float = 0.4
@export_range(0.0, 1.0, 0.01) var goo_screen_max: float = 0.9

## Seconds between brutes, from and to, on a campaign map. 0 never.
@export_range(0.0, 3600.0, 10.0, "or_greater") var brute_interval_min: float = 300.0
@export_range(0.0, 3600.0, 10.0, "or_greater") var brute_interval_max: float = 480.0

## A brute's health for one survivor, and how much more for each further survivor.
@export_range(100.0, 50000.0, 50.0, "or_greater") var brute_health: float = 3000.0
@export_range(0.0, 20000.0, 50.0, "or_greater") var brute_health_per_survivor: float = 900.0

## Whether the crying sleepers a map places are there at all.
@export var sleepers_enabled: bool = true

# Boxes

@export_group("Boxes")

## Where the boxes and what they do are read from, relative to this game's root.
@export var box_file: String = "boxes/boxes.json"

## Chance a common drops a box when it dies, and a special, and a brute. A common was 1.2% (one in eighty), so a solo run of a few dozen kills saw no loot at all; 4% is about one a minute at a hold's pace.
@export_range(0.0, 1.0, 0.001) var box_drop_common: float = 0.04
@export_range(0.0, 1.0, 0.01) var box_drop_special: float = 0.3
@export_range(0.0, 1.0, 0.01) var box_drop_brute: float = 1.0

## Seconds of holding E to open a box lying on the ground when nobody can carry one
## ([member box_carry] 0), and how long an unopened one lies there.
@export_range(0.0, 10.0, 0.1, "or_greater") var box_open_seconds: float = 0.8
@export_range(5.0, 1200.0, 5.0, "or_greater") var box_lifetime: float = 150.0

## How many boxes a survivor carries (E picks one up into the hands; primary fire held opens it). 0: no carrying, E
## opens a box on the ground as it did before boxes could be carried.
@export_range(0, 6, 1, "or_greater") var box_carry: int = 1

## Whether a fast-rolling barrel, crate or tyre also hurts zombies (cvar `zz_roll_damage_zombies`); survivors are always hurt.
@export var roll_damage_zombies: bool = true

# Physics crates (zz_crates.gd)

## Ammo piles and boxes on the ground are rigid bodies: pushed along by survivors and zombies, shot, thrown by blasts (cvar `zz_physics_crates`). 0 keeps them where the map or the drop put them.
@export var physics_crates: bool = true

## Which loot kinds are crates, comma separated (ammo, box, medkit, pills, weapon, throwable, defib).
@export var crate_kinds: String = "ammo,box"

## A crate's mass in kilograms, against a walking survivor's push (`crate_push` scales it) and a blast.
@export_range(0.25, 200.0, 0.25, "or_greater") var crate_mass: float = 8.0

## How hard a walk pushes a crate, against the walker's speed (0: nothing pushes one), and whether zombies push too.
@export_range(0.0, 4.0, 0.05, "or_greater") var crate_push: float = 1.0
@export var crate_zombie_push: bool = true

## How hard a blast throws a crate, against a barrel's blast speed (0: blasts leave crates alone).
@export_range(0.0, 8.0, 0.05, "or_greater") var crate_blast: float = 1.0

## The most crates simulating at once; the longest untouched sleep first. A crate at rest for `crate_sleep_seconds` sleeps (0: the engine's own timer).
@export_range(1, 256, 1, "or_greater") var crate_max_active: int = 16
@export_range(0.0, 30.0, 0.1, "or_greater") var crate_sleep_seconds: float = 2.0

## Times a second the moved crates' places go to clients.
@export_range(1.0, 30.0, 1.0, "or_greater") var crate_sync_hz: float = 10.0

## Most crate bodies in the world; loot laid beyond it lies static, as with `zz_physics_crates 0`.
@export_range(1, 2048, 1, "or_greater") var crate_max_bodies: int = 128

## A crate this far below where it last rested has fallen out of the map (a drop over a pit) and is recovered (0: only the map's kill height counts).
@export_range(0.0, 200.0, 1.0, "or_greater") var crate_fall_limit: float = 15.0

## What becomes of a lost crate: back to where it last rested (never rested: gone), or just gone.
@export_enum("rest", "remove") var crate_lost: int = 0

## Seconds primary fire is held to open a carried box (server file key `box_deploy_seconds`,
## cvar `zz_box_deploy_seconds`, 0.5 to 15), and the radius (metres) the survivor may drift in
## meanwhile before it is cancelled. 1 s is quick enough to open one mid-fight; it was 3.5, which
## nobody did with a horde about, so boxes were only ever opened in the safe room.
@export_range(0.5, 15.0, 0.1, "or_greater") var box_deploy_seconds: float = 1.0
@export_range(0.2, 6.0, 0.1, "or_greater") var box_deploy_radius: float = 1.2

## Whether a box on the ground and in the slot says what type it is. Off (the default): every
## box looks the same and what is in it is a surprise until it is opened; the server never sends
## the type, only the outcome once it is opened. On: the type is shown on the ground and in the hands.
@export var box_labels: bool = false

## Instakill, the first named box: the duration it lasts (seconds, uniform between; a negative
## minimum or maximum leaves boxes.json's own), and what a special takes per hit as a multiple of
## its damage (a common simply dies).
@export var box_instakill_min: float = -1.0
@export var box_instakill_max: float = -1.0
@export_range(1.0, 100.0, 0.5, "or_greater") var box_instakill_special_scale: float = 4.0

## Great Depression box: every shop price is multiplied by this per box in force; its weight-limit cut is `depression` in `zz_weight_modifiers`.
@export_range(1.0, 10.0, 0.05, "or_greater") var box_depression_price: float = 1.5

## A limb's health follows the zombie's actual health (a later wave's, a brute's), and Instakill's
## boosted damage does not reach limbs; off restores the old limb rules (zz_limb_follow_health).
@export var limb_follow_health: bool = true

## Boxes lying about at once; past it, the oldest goes.
@export_range(1, 200, 1, "or_greater") var max_boxes: int = 16

## Whether boxes exist at all.
@export var boxes_enabled: bool = true

# Turrets

@export_group("Turrets")

## Turrets one survivor may have out; a further one turns the oldest off rather than refusing the box (`zz_turret_max_per_owner`).
@export_range(1, 16, 1, "or_greater") var turret_max_per_owner: int = 2

## What a sentry does when the box outcome's `turret` action leaves the number out (the shipped Turret Box writes its own, so these only matter for a box an owner edits): seconds it stands (`zz_turret_seconds`).
@export_range(1.0, 600.0, 1.0, "or_greater") var turret_seconds: float = 40.0

## Rounds a sentry carries (`zz_turret_ammo`).
@export_range(1, 5000, 1, "or_greater") var turret_ammo: int = 220

## Damage of one sentry round (`zz_turret_damage`).
@export_range(0.1, 500.0, 0.1, "or_greater") var turret_damage: float = 14.0

## Metres a sentry sees and shoots (`zz_turret_reach`).
@export_range(1.0, 100.0, 0.5, "or_greater") var turret_reach: float = 20.0

## Seconds between a sentry's rounds (`zz_turret_interval`).
@export_range(0.02, 5.0, 0.01, "or_greater") var turret_interval: float = 0.14

## Height of the sentry's muzzle above its base, metres (`zz_turret_muzzle_height`).
@export_range(0.1, 3.0, 0.05, "or_greater") var turret_muzzle_height: float = 0.85

## Height above a zombie's feet a sentry aims at, so a shot lands on the body and not the feet (`zz_turret_chest_height`).
@export_range(0.1, 3.0, 0.05, "or_greater") var turret_chest_height: float = 1.1

## Metres in front of the survivor's eyes a turret may be placed; when that spot is no good the one below the eyes is tried (`zz_turret_place_reach`).
@export_range(0.5, 10.0, 0.1, "or_greater") var turret_place_reach: float = 2.2

## Metres down from the eyes the fallback spot is looked for (`zz_turret_foot_reach`).
@export_range(0.1, 5.0, 0.1, "or_greater") var turret_foot_reach: float = 0.4

# Thrown things

@export_group("Hazards")

## Metres from a goo glob's path within which it hits a survivor's middle (`zz_hazard_goo_hit_radius`).
@export_range(0.1, 5.0, 0.05, "or_greater") var hazard_goo_hit_radius: float = 1.1

## The same for a thrown rock (`zz_hazard_rock_hit_radius`).
@export_range(0.1, 5.0, 0.05, "or_greater") var hazard_rock_hit_radius: float = 1.3

## Metres a bile jar draws the horde from (`zz_hazard_bile_lure`).
@export_range(1.0, 200.0, 1.0, "or_greater") var hazard_bile_lure: float = 35.0

## Seconds a bile jar keeps the horde drawn (`zz_hazard_bile_seconds`).
@export_range(1.0, 120.0, 1.0, "or_greater") var hazard_bile_seconds: float = 15.0

## Seconds a pipe charge beeps before it goes off (`zz_hazard_pipe_fuse`).
@export_range(0.5, 60.0, 0.5, "or_greater") var hazard_pipe_fuse: float = 6.0

## Metres a pipe charge lures the horde from (`zz_hazard_pipe_lure`).
@export_range(1.0, 200.0, 1.0, "or_greater") var hazard_pipe_lure: float = 40.0

## Seconds a zombie keeps burning once it has left the fire (`zz_hazard_afterburn_seconds`).
@export_range(0.0, 60.0, 0.5, "or_greater") var hazard_afterburn_seconds: float = 4.0

## Damage per second of a burning zombie; a brute takes half (`zz_hazard_burn_dps`).
@export_range(0.0, 500.0, 1.0, "or_greater") var hazard_burn_dps: float = 18.0

# The maps

@export_group("Carry weight")

## Master switch for `zz_weight_*`: every weapon has a weight, a survivor a carry limit, and slots may hold several weapons.
@export var weight_enabled: bool = true

## What a survivor with no backpack carries, in weight units (kilograms: a pistol is about 1, a rifle 4).
@export_range(0.0, 1000.0, 0.5, "or_greater") var weight_limit: float = 14.0

## Every weapon's weight is multiplied by this, on top of the box modifiers.
@export_range(0.0, 10.0, 0.05, "or_greater") var weight_multiplier: float = 1.0

## Weapons one slot holds; pressing the slot key again cycles through them.
@export_range(1, 8, 1, "or_greater") var weight_slot_capacity: int = 2

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

## How much dismemberment there is (gs-npc's GSNpcGore): 0 none (limbs cannot be shot off), 1 clean stumps, 2 flying limbs and blood (the default), 3 limbs give way sooner and the spray is heavier. Family-friendly servers set 0. `zz_gore_level`.
@export_range(0, 3, 1, "or_greater") var gore_level: int = 2

## The most severed limbs lying about at once on a machine; the oldest is recycled. 0 is unlimited. `zz_gore_max_gibs`.
@export_range(0, 200, 1, "or_greater") var gore_max_gibs: int = 24

## Wound marks on bodies plus blood pools under crawling zombies, at most this many on a machine (drawn only; the oldest is recycled). 0 is unlimited. `zz_gore_max_wounds`.
@export_range(0, 400, 1, "or_greater") var gore_max_wounds: int = 48

## Which swing the commons use when they strike standing still (drawn only): 0 a mix by body (the default), 1 every one the scratching swipe, 2 every one the grapple on the spot. A zombie that strikes on the run keeps its running swing. `zz_attack_anim`.
@export_range(0, 2, 1, "or_greater") var attack_anim: int = 0

@export_group("The maps")

## Which maps this server may play, by id. Empty means every one it has.
@export var map_ids: PackedStringArray = PackedStringArray()

## Whether the next map is drawn at random (seeded) rather than taken in order; a campaign
## map's `next` always wins over both.
@export var shuffle_maps: bool = false

## The file that says which maps this server ROTATES: `cfg/maps.yml` (gs-map's
## `GSMapRotationFile`: named rotations, `random` or `cycle`, wildcards, command names), looked
## for in the `--config` directory. Empty, or no such file, rotates every map. A map it leaves out
## stays installed (`zz_map <id>` and the map menu load it); it is only never drawn, balloted or
## nominated. A rotation in the file replaces [member shuffle_maps]. `sv_map_rotation_file`.
@export var map_rotation_file: String = "cfg/maps.yml"

## Where map documents are read from, relative to this game's root.
@export var map_directory: String = "maps"

## How the client culls a world: off, pvs, occluders or both (gs-map's GSMapVisibility). Empty
## leaves it to the client's video setting. `--zz-vis-mode=`.
@export var vis_mode: String = ""

## Draws a converted map with the author's baked lighting when its world pack carries it. Off draws the
## lit materials and the document's lamps. `--zz-lightmaps=`.
@export var lightmaps: bool = true

## The least mean light a drawn converted map's surfaces and a survivor's ambient have, so a map the author lit darkly can be played (gs-map's `GSMapBspMesh.visibility_floor`, tinted by the map's own ambient). 0 is the author's light alone. `--zz-light-floor=`.
@export_range(0.0, 2.0, 1.0, "or_greater") var light_floor: float = 0.6

## The least energy of a lightmapped map's sun on a client, for the shadowed interiors of a dim map (0 leaves the map's own). `--zz-sun-floor=`.
@export_range(0.0, 2.0, 1.0, "or_greater") var sun_floor: float = 0.6

## Longest side of a texture file decoded from disk for a drawn world; larger ones are halved until they fit (0 keeps them). Store slices are untouched. 1024 saves roughly three quarters of the texture memory. `--zz-map-texture-max=`.
@export_range(0, 8192, 1, "or_greater") var map_texture_max: int = 2048

## Whether a drawn world's sun shadow comes from one shadows-only proxy per chunk (cheap) instead of every material's surfaces. `--zz-shadow-proxy=`.
@export var shadow_proxy: bool = true

## Metres beyond which a chunk's shadow proxy is not drawn into the sun's cascades (0: all are). `--zz-shadow-range=`.
@export_range(0.0, 1000.0, 1.0, "or_greater") var shadow_range: float = 0.0

## Whether foliage and glass cards cast a sun shadow (costly: their alpha is tested in the shadow pass). Needs `shadow_proxy`. `--zz-shadow-translucent=`.
@export var shadow_translucent: bool = false

## Cascades of the sun's shadow on a client: 1, 2 or 4. Every cascade draws each caster in it again, so 4 (the old look) is
## about twice the draws of 2 on a converted map. `--zz-sun-shadow-splits=`.
@export_range(1, 4, 1.0, "or_greater") var sun_shadow_splits: int = 2

## Props whose longest side is under this many metres cast no sun shadow on a client (0: all do, as before). A can's shadow
## is a draw call a player never reads. `--zz-prop-shadow-min=`.
@export var prop_shadow_min: float = 1.2

## Triangles a library model's mesh must have before a client simplifies it into LOD levels (0: never; a scanned tree is over a million, and a street of them was the frame). Read when a world is built. `--zz-prop-lod-min-tris=`.
@export var prop_lod_min_tris: int = 20000

## Most triangles a library model's mesh keeps at full detail on a client (0: its own): a scanned tree of 1.6 million is cut to about this before its LODs are made. Read when a world is built. `--zz-prop-max-tris=`.
@export var prop_max_tris: int = 150000

## Pixels of error a mesh may show before the engine picks a finer LOD, on a client: higher is coarser and cheaper (1 is the engine's own). `--zz-mesh-lod-threshold=`.
@export_range(0.0, 16.0, 1.0, "or_greater") var mesh_lod_threshold: float = 1.0

## Seed every random choice is drawn from.
@export var seed_value: int = 20261010

# Netcode

@export_group("Netcode")

## Highest of the capped zz_* cvars, the zz_map_* map limits and zz_tick_rate, `zz_waves=0,zz_map_objectives=0`: 0 is none.
## docs/operators.md lists every key and default (game/zz_caps.gd has them); a key not listed keeps its
## default, a value past it is refused with an error, never clamped. The server tells clients its zz_map_* limits and
## zz_tick_rate, so a client takes a map or a rate the server allows. Empty keeps every default.
@export var cap_overrides: String = ""

## Metres within which a survivor is sent a common's and a special's updates (live). A client hides
## a mirror the server stopped sending, so either can change mid-round.
@export_range(40.0, 1000.0, 5.0, "or_greater") var net_common_radius: float = 80.0
@export_range(40.0, 1000.0, 5.0, "or_greater") var net_special_radius: float = 260.0
## Anything past [member net_far_distance] metres from a survivor (players included, never their
## own) is sent every Nth snapshot only. 1 is off; gs-net's GSNetInterest.far_every.
@export_range(1, 16, 1, "or_greater") var net_far_every: int = 1
@export_range(0.0, 1000.0, 5.0, "or_greater") var net_far_distance: float = 40.0
## Every survivor far from a zombie skips the same snapshots of it, so the server encodes it once
## for all of them (GSNetInterest.far_coherent). Off staggers each survivor's turns.
@export var net_far_coherent: bool = false
## Bands past [member net_far_distance], each twice as far and sent half as often (1 is one band).
@export_range(1, 4, 1, "or_greater") var net_far_tiers: int = 1

# Bots

@export_group("Bots")

## How many survivors the server keeps in the game by adding stand-ins.
@export_range(0, 24, 1, "or_greater") var minimum_players: int = 4

## Whether a map that says how big a team it is built for (its `survivors`) raises that number
## to it: a high school wants a dozen, a street four.
@export var team_from_map: bool = true

# How a stand-in aims and how quickly it reacts are gs-bot's `bot_*` settings, shared by every
# game (`bot_difficulty`, `bot_reaction`, `bot_aim_error`, ...), not numbers of this file.

# Stand-in rules

@export_group("Stand-in rules")

## Metres a stand-in sees a zombie from, and the reach it counts a crowd for the calm check (`zz_bot_sight`).
@export_range(1.0, 200.0, 1.0, "or_greater") var bot_sight: float = 32.0

## How many times higher a gun in the same slot must be rated before a stand-in swaps to it (`zz_bot_upgrade_ratio`).
@export_range(1.0, 10.0, 0.05, "or_greater") var bot_upgrade_ratio: float = 1.35

## Metres inside which a stand-in does not fire a launcher: the blast reaches its owner (`zz_bot_blast_safe`).
@export_range(0.0, 50.0, 0.5, "or_greater") var bot_blast_safe: float = 9.0

## Score added to a launcher when a stand-in ranks the guns it could take (`zz_bot_launcher_bonus`).
@export_range(0.0, 100000.0, 100.0, "or_greater") var bot_launcher_bonus: float = 10000.0

## Metres from the line of fire a friend's middle may be before a stand-in holds its fire (`zz_bot_friend_clearance`).
@export_range(0.1, 3.0, 0.05, "or_greater") var bot_friend_clearance: float = 0.7

## Degrees of cone around its aim in which a friend's hitbox counts as in the line of fire (`zz_bot_friend_cone_degrees`).
@export_range(0.0, 60.0, 0.5) var bot_friend_cone_degrees: float = 14.0

## Metres inside a friend's hitbox the eye must be for the shot to count as passing through them (`zz_bot_muzzle_margin`).
@export_range(0.0, 1.0, 0.01) var bot_muzzle_margin: float = 0.08

## Metres past its target a round that passes bodies is judged for friends behind it (`zz_bot_penetration_reach`).
@export_range(0.0, 100.0, 0.5, "or_greater") var bot_penetration_reach: float = 8.0

## Metres within which a crowd makes a stand-in shove (`zz_bot_shove_range`).
@export_range(0.5, 5.0, 0.1, "or_greater") var bot_shove_range: float = 1.7

## Metres a stand-in lets its leader get before it walks after them (nearer it stays put) (`zz_bot_follow_near`).
@export_range(0.5, 50.0, 0.5, "or_greater") var bot_follow_near: float = 3.5

## Metres past which a stand-in always walks after its leader (`zz_bot_follow_far`).
@export_range(0.5, 100.0, 0.5, "or_greater") var bot_follow_far: float = 6.0

## Least seconds a picked behaviour lasts before the next is drawn from the persona's mix (`zz_bot_behave_min`).
@export_range(1.0, 300.0, 1.0, "or_greater") var bot_behave_min: float = 10.0

## Most seconds a picked behaviour lasts (`zz_bot_behave_max`).
@export_range(1.0, 300.0, 1.0, "or_greater") var bot_behave_max: float = 22.0

## Metres a looting stand-in looks for something it wants (`zz_bot_loot_reach`).
@export_range(1.0, 500.0, 1.0, "or_greater") var bot_loot_reach: float = 90.0

## Metres off an item a stand-in takes on (`zz_bot_pick_up_reach`).
@export_range(0.5, 100.0, 0.5, "or_greater") var bot_pick_up_reach: float = 7.0

## Seconds a stand-in tries for an item before it leaves it be (`zz_bot_pick_up_give_up`).
@export_range(1.0, 300.0, 1.0, "or_greater") var bot_pick_up_give_up: float = 15.0

## Seconds a stand-in tries for a clear line to an item that is within reach but behind something (`zz_bot_pick_blocked_give_up`).
@export_range(0.5, 60.0, 0.5, "or_greater") var bot_pick_blocked_give_up: float = 3.0

## Hops that have not freed a stand-in before the game steps it along (`zz_bot_hops_before_nudge`).
@export_range(0, 20, 1, "or_greater") var bot_hops_before_nudge: int = 2

## Seconds a stand-in stays put, hopping and stepping, before it is put on clear ground (`zz_bot_stuck_before_relocate`).
@export_range(1.0, 120.0, 1.0, "or_greater") var bot_stuck_before_relocate: float = 8.0

## Metres from where it began that count as having got away (`zz_bot_stuck_area`).
@export_range(0.5, 20.0, 0.5, "or_greater") var bot_stuck_area: float = 2.5

## Metres a stand-in may jitter and still be stuck (`zz_bot_stuck_radius`).
@export_range(0.1, 5.0, 0.1, "or_greater") var bot_stuck_radius: float = 0.8

## Path points ahead of it a stand-in smooths its route over (`zz_bot_smooth_horizon`).
@export_range(2, 64, 1, "or_greater") var bot_smooth_horizon: int = 16

# Watching

@export_group("Watching")

## Who somebody who is out may watch: 0 anybody, 1 their own side, 2 nobody.
@export_enum("anybody", "own side", "nobody") var spectate_camera: int = 0

# Progress

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
## the first eight, a third of that up to sixteen (82, what a 64 Hz tick carries at wave 10 with
## the stand-ins), and 1 over [member commons_far_divisor] of it for each past sixteen. A wave's
## total is not capped, only how many are up at once.
func commons_cap(survivors: int) -> int:
	var first := mini(maxi(survivors - 1, 0), 7)
	var mid := clampi(survivors - 8, 0, 8)
	var past := maxi(survivors - 16, 0)
	var cap := commons_base + commons_per_survivor * first + (commons_per_survivor * mid) / 3 \
		+ (commons_per_survivor * past) / maxi(commons_far_divisor, 1)
	return mini(cap, commons_max) if commons_max > 0 else cap


## Specials alive at once, for [param survivors].
func specials_cap(survivors: int) -> int:
	return specials_base + int(floor(float(maxi(survivors - 1, 0)) / maxf(survivors_per_special, 1.0)))


func validate() -> GSResult:
	if mob_interval_min > mob_interval_max:
		return GSResult.fail(GSError.CODE_INVALID, "mob_interval_min is over mob_interval_max; raise the max or lower the min.")

	if special_interval_min > special_interval_max:
		return GSResult.fail(GSError.CODE_INVALID, "special_interval_min is over special_interval_max; raise the max or lower the min.")

	if brute_interval_min > brute_interval_max:
		return GSResult.fail(GSError.CODE_INVALID, "brute_interval_min is over brute_interval_max; raise the max or lower the min.")

	if body_stride_near > body_stride_far:
		return GSResult.fail(GSError.CODE_INVALID,
			"body_stride_near is over body_stride_far; raise body_stride_far or lower body_stride_near.")

	if respawn_min_seconds > respawn_max_seconds:
		return GSResult.fail(GSError.CODE_INVALID,
			"respawn_min_seconds is over respawn_max_seconds; raise respawn_max_seconds or lower respawn_min_seconds.")

	if common_speed_base > common_speed_max:
		return GSResult.fail(GSError.CODE_INVALID,
			"common_speed_base is over common_speed_max; raise common_speed_max or lower common_speed_base.")

	if difficulty < 0 or difficulty > 3:
		return GSResult.fail(GSError.CODE_INVALID,
			"difficulty is %d; it is 0 (easy), 1 (normal), 2 (advanced) or 3 (expert)." % difficulty)

	if survival_style < 0 or survival_style > 2:
		return GSResult.fail(GSError.CODE_INVALID,
			"survival_style is %d; it is 0 (waves), 1 (nights) or 2 (clock)." % survival_style)

	if start_weapons.is_empty():
		return GSResult.fail(GSError.CODE_INVALID, "Survivors have to start holding something.")

	var cap_errors := PackedStringArray()
	var overrides := ZzCapsScript.parse_overrides(cap_overrides, cap_errors)
	if not cap_errors.is_empty():
		return GSResult.fail(GSError.CODE_INVALID, "; ".join(cap_errors))

	if box_deploy_seconds < 0.5 or box_deploy_seconds > ZzCapsScript.highest("zz_box_deploy_seconds", overrides):
		return GSResult.fail(GSError.CODE_INVALID,
			"box_deploy_seconds is %.2f; it is 0.5 to 15 (cap_overrides zz_box_deploy_seconds=0 lifts the top)." % box_deploy_seconds)

	if downed_crawl_speed < 0.0 or downed_crawl_speed > ZzCapsScript.highest("zz_downed_crawl_speed", overrides):
		return GSResult.fail(GSError.CODE_INVALID,
			"downed_crawl_speed is %.2f; it is 0 (stay put) to 6 metres per second (cap_overrides zz_downed_crawl_speed=0 lifts the top)." % downed_crawl_speed)

	if weight_over_limit != "slow" and weight_over_limit != "drop":
		return GSResult.fail(GSError.CODE_INVALID, "weight_over_limit is '%s'; it is slow or drop." % weight_over_limit)

	return GSResult.success(null)


## `@export_group` -> the cfg file it lives in: `cfg/game/game-zombie-zone/config_<file>/game.yml`.
const CFG_FILES := {
	"The HUD": "round", "The round": "round", "Survival": "round", "Trader": "round", "Watching": "round", "Progress": "round",
	"Difficulty": "horde", "The horde": "horde", "The specials": "horde", "Bots": "horde", "Stand-in rules": "horde",
	"The survivors": "survivors", "Items": "survivors", "The shove": "survivors", "Boxes": "survivors", "Turrets": "survivors", "Hazards": "survivors",
	"Carry weight": "carry", "Gore": "world", "The maps": "world", "Netcode": "world",
}


## The binder every entry point uses: [param config] layered, one cfg file per [constant CFG_FILES] entry.
static func make_binder(config: GSConfig, json_path := "") -> GSGameConfigBinder:
	var b := GSGameConfigBinder.create(config, "game-zombie-zone", "zz", json_path)
	b.grouped = true
	b.group_files = CFG_FILES
	return b


## The layered load through [GSGameConfigBinder] (JSON, cfg/ yml, env, argv; strict on a server). The value is the binder.
static func boot(config: GSConfig, json_path: String) -> GSResult:
	var binder := make_binder(config, json_path)
	var loaded := binder.load_layers()
	if not loaded.ok:
		return loaded
	return GSResult.success(binder)


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
	return ZzConfigText.describe(self)


func describe_lines(_redact_sensitive: bool = true) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("zombiezone configuration")
	var facts := describe()
	for key: String in facts:
		lines.append("  %-10s %s" % [key, facts[key]])
	return lines
