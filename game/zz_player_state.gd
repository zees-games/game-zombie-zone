extends CharacterBody3D

## A survivor's state: every constant, signal and variable of [ZzPlayer], so the rules file holds only behaviour.

const ZzWeapons := preload("zz_weapons.gd")
const ZzClasses := preload("zz_classes.gd")
const ZzConfig := preload("zz_config.gd")
const ZzController := preload("zz_controller.gd")
const ZzWaterRules := preload("zz_water_rules.gd")
const ZzFigure := preload("zz_figure.gd")
const ZzAvatars := preload("zz_avatars.gd")

## One survivor: how they move, how hurt they are, whether they are up, down, held or dead, and
## what they are carrying.
##
## [b]Down is not dead, and the third time is.[/b] At zero health a survivor goes down instead of
## dying: the same [DotHealth] is revived at once with a bleed-out pool for a maximum, the DOWN
## modifier holds them where they fell, and they can still shoot what they hold. Damage while
## down comes off the pool; the pool running out is death. Somebody holding E over them for
## [member ZzConfig.revive_seconds] stands them up with a little temporary health. After
## [member ZzConfig.max_incaps] downs the next zero is death, and the screen has been saying so
## since the last one.
##
## [b]Temporary health is part of the health, and comes off first.[/b] What a bottle of pills or
## a revive gives is added to [member DotHealth.health] and remembered in [member temp_health];
## it drains by itself, and any damage taken comes off it before the real thing. One number for
## dot-combat to subtract from, and one for this file to know how much of it is borrowed.
##
## [b]Pinned is a person, not a flag.[/b] [member pinned_by] is the entity id of the special
## holding them and [member pin_kind] what it is doing (pounce, choke, carry, ride). The PINNED
## modifier holds them on both ends; what frees them is the special dying, a teammate's shove,
## or — for the ones that let go — the special deciding to.

const EYE_HEIGHT := 1.6
const EYE_DOWN := 0.45

const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.8
const BODY_CROUCH := 0.95
## Above the 0.42 m rise of a converted map's stairs, so walking up one does not wait on a hop.
const BODY_STEP := 0.45

## Where a survivor is in their life this map.
enum Life { UP, DOWN, DEAD }

@export var player_id: StringName = &"local"
@export var display_name: String = "Player"
@export var samples_input: bool = false
@export var is_bot: bool = false

## What this player looks like, as a dot-user-avatar document; null is the stock person.
var avatar: DotAvatar = null
## The class this survivor plays (empty before the first spawn), the skin it gave them (empty: their
## own avatar) and its definition, which [method tunables_for] reads. Set by [method apply_class].
var class_id: StringName = &""
var class_skin: StringName = &""
var class_def: DotPlayerClassDef = null
## What the player asked for, landing on the next spawn: a class id and (in `select` mode) a skin.
var class_wanted: StringName = &""
var model_wanted: StringName = &""

var config: ZzConfig = null

var controller: ZzController = null
var sampler: DotFpsSampler = null
var health: DotHealth = null
var hitboxes: DotHitboxSet = null
var weapons: ZeeWeaponRig = null

## Always the survivors, today; kept so the scoreboard and the chat's team channel have a side.
var team: int = 1

var points: int = 0
var ping_ms: int = -1
var entity_id: int = 0

## How many times the server has PUT this player somewhere. Replicated, so a watcher's
## interpolator draws a teleport as one rather than as a flight across the map.
var warps: int = 0

## Sitting this map out, having joined after it started or died without a rescue.
var watching: bool = false

var life: int = Life.UP

## Times down this map. At [member ZzConfig.max_incaps] the next one is death.
var incaps: int = 0

## Borrowed health, already inside [member DotHealth.health]. See the class notes.
var temp_health: float = 0.0

## The special holding them, as an entity id, and what it is doing. 0 / empty when free.
var pinned_by: int = 0
var pin_kind: StringName = &""

## What they carry besides weapons.
var medkits: int = 0
var pills: int = 0
## Charges left in the defibrillator they carry (0: none), the time it is next ready (server), and
## the time until which they cannot be hurt after being shocked back (server).
var defibs: int = 0
var defib_ready_at: float = 0.0
var shield_until: float = -1.0

## The boxes in their hands, by type (server), and what everybody sees of them: how many, and
## which as an index into the box file's order plus one (0: none, or unknown because
## `box_labels` is off). See [ZzBoxes].
var carried: Array[StringName] = []
var carried_count: int = 0
var carried_index: int = 0
## Whether the box is in the hands (the gun is put away, primary fire deploys), replicated; the
## slot the player had asked for when it came out, server side: asking for another puts it away.
var box_out: bool = false
var box_slot: int = 0
var previous_fire: bool = false

## Where they stood when they began deploying a box, which they may drift from by only so far.
var use_origin: Vector3 = Vector3.ZERO

## Holding E on something: what (`revive`, `heal`, `box`, `objective`, `item`), whom or which,
## since when (simulated seconds) and for how long it takes. Server side; the fraction is
## replicated to the owner and to whoever is being revived.
var using: StringName = &""
var use_target: int = -1
var use_started: float = 0.0
var use_needs: float = 0.0

## 0..1 of the way through whatever they are holding E for, as the wire carries it.
var use_fraction: float = 0.0

## Being revived or healed by somebody, 0..1. For the downed person's own screen.
var helped_fraction: float = 0.0

## Simulated seconds when they may next shove, and how many they have shoved in a row.
var shove_ready_at: float = 0.0
var shove_streak: int = 0

## Covered in bile until, and burning until, in simulated seconds. Server side; replicated as
## two flags.
var biled_until: float = -1.0
var burning_until: float = -1.0

## Replicated flags for the two above, on a client.
var biled: bool = false
var burning: bool = false
## Goo on the screen: stacks (0 to 3) until [member goo_until], simulated seconds. Server side; replicated in `net_status`.
var goo_stacks: int = 0
var goo_until: float = -1.0

## A box's flash: their screen white. Set from the box effects on the server, replicated.
var box_blind: bool = false

## A flash grenade went off in view: the screen is white while this is set (replicated); the server holds it until [member flash_until].
var flashed: bool = false
var flash_until: float = 0.0
## How hard the flash blinds, 0..1 (distance and facing); the cover alpha. Replicated as five bits.
var flash_strength: float = 1.0

## When they died, for the rescue clock. Simulated seconds.
var died_at: float = -1.0

## When a timed respawn returns them (server, simulated seconds); -1 for none. And until when
## they cannot be hurt after one.
var respawn_at: float = -1.0
var protected_until: float = -1.0

## What they did this map, for the scoreboard and the end-of-map card.
var commons_killed: int = 0
var specials_killed: int = 0
var revives_done: int = 0
var damage_taken_map: float = 0.0
var friendly_damage: float = 0.0

## Seconds this player has been in the game this session (server): the floor under their
## playtime when progress is not kept.
var session_seconds: float = 0.0

## Which weapon slot they have asked for, from this game's input message.
var wanted_slot: int = 0

## What their hands are doing this tick and did last tick: `ZzNetCommand.ACT_*` bits, and the
## shove button. Server side; a press is the difference between the two.
var actions: int = 0
var previous_actions: int = 0

## Set when the arsenal changed, so the game re-weighs it next tick; the speed scale last applied.
var carry_dirty: bool = false
var carry_scale: float = 1.0
var shove_held: bool = false
var previous_shove: bool = false

## An administrator's `blind` and `beacon`, as dot-moderation's tools set them.
var blinded: bool = false
var beacon: bool = false
## The flashlight is on (server-owned, replicated); `flashlight_ready` is cleared on a new map so the next tick sets its start state.
var flashlight: bool = false
var flashlight_ready: bool = false
var beacon_marker: DotFxBeacon = null

## Whether the end-of-map logic has them inside the end area right now.
var in_end_area: bool = false

## What other people see this player as. Client side.
var figure: ZzFigure = null
## The name and health pill floating over this survivor for the others to read (dot-ui).
var _tag: DotHealthTag = null

## How this survivor's body falls on their death: the server's pick ([method ZzGame.decide_death]),
## carried on DEATH and set here before anybody hears of it. Null before a first death.
var death: DotPlayerDeath = null

## The weapon that landed the killing hit (empty for a claw or a fall), for the killcam's icon.
var death_weapon: StringName = &""

## Remote weapon state, for drawing a gun in a watched survivor's hand. See mg-deathrun.
var mirrored: bool = false
var dealt: Array[StringName] = []
var dealt_round: int = -1
var mirror_slot: int = 0
var mirror_switching: bool = false
var mirror_fired: int = 0
var mirror_fire_kind: int = 0
var _seen_fire_seq: int = -1
static var _slots: Dictionary = {}

## The rig the client playing this survivor draws their gun with (`ZzClient.weapons`); null on
## every other machine and for everybody else. Its magazine is what the HUD counts, so it is
## corrected from the server's (see [method correct_view_rig]).
var view_rig: ZeeWeaponRig = null

## The downed rules (`sv_downed_*`) and the default pistol a downed survivor falls back to, set by the game.
var downed_rules: DotDownedRules = null
var downed_default: StringName = &"zz_pistol"

## The slot a downed survivor is held to on the server's rig, and on the drawn one (0: not picked yet).
var downed_slot: int = 0
var _view_down_slot: int = 0

## Ticks left of the crawl pose after the last movement, so the gun does not flicker out and in.
var _crawl_ticks: int = 0
var _rooted: bool = false
var _seen_moving_until: int = 0
const CRAWL_HOLD_TICKS := 15
const CRAWL_SPEED_MIN := 0.15

## Simulated seconds [member view_rig] has gone without a trigger, a reload or a switch.
var _view_rig_quiet: float = 0.0

## How long the drawn gun must be quiet before the server's count may overwrite it: longer than
## a shot takes to reach the server and its snapshot to come back, so a correction never undoes
## a shot the server has not heard of yet.
const VIEW_RIG_SETTLE_SEC := 0.6

## Offline only: puts the client's buttons on the command [member sampler] has just made.
##
## [b]Stamped after sampling, inside [method simulate], never on the command before it.[/b] The
## client used to stamp `controller.current_command` from its own physics frame, and then this
## file's [method simulate] replaced that command with a fresh sample: fire and reload never
## reached the world's rig, so offline the HUD's 15 / 60 never moved and nothing you shot was hit.
var command_stamp: Callable = Callable()

# --- Water --------------------------------------------------------------------

## How deep in water: none, the feet (below the waist: wading), the waist (swimming) or the eyes
## (under: the breath runs out). Source's four levels, and the same names here.
enum WaterLevel { NONE, FEET, WAIST, EYES }

## The map's water volumes this player moves through, world space (see [method set_water]).
var water: Array[AABB] = []

## This player's swimming mode (dot-player-controller's DotFpsSwimMode), one per player in
## `controller.extra_modes` so a style's rebuilt motor keeps it under the same id on every machine.
var swim: DotFpsSwimMode = DotFpsSwimMode.new()

## Ladder climbing (dot-player-controller's DotFpsLadderMode), fed the map's ladder brushes by [method ZzMechanics.ladder_boxes].
var ladder: DotFpsLadderMode = DotFpsLadderMode.new()

## Breath left, in seconds under water; refilled with the head out. Each end counts its own
## from its own copy of the water: the server's decides the damage, the client's is the HUD's
## bar, and neither is on the wire.
var air: float = 12.0

## Whether the eyes are under water now, as of the last tick.
var submerged: bool = false

## The level as of the last simulated tick.
var water_level: int = WaterLevel.NONE

var tick_rate: int = 64:
	set(value):
		tick_rate = value
		if controller != null:
			controller.tick_rate = value

## The key dot-weapon's player bridge identifies this carrier by.
var player_key: String:
	get:
		return String(player_id)


## Returns the map's mechanics (lifts, doors), or null. Set by the game.
var mechanics_fn: Callable = Callable()
