extends Node3D

## The simulation's state: every constant, signal and variable of [ZzGame], so the rules file holds only behaviour.

const ZzBoxes := preload("zz_boxes.gd")
const ZzPossession := preload("zz_possession.gd")
const ZzPropForce := preload("zz_prop_force.gd")
const ZzPropCarry := preload("zz_prop_carry.gd")
const ZzCarry := preload("zz_carry.gd")
const ZzClasses := preload("zz_classes.gd")
const ZzBots := preload("zz_bots.gd")
const ZzBotProfiles := preload("zz_bot_profiles.gd")
const ZzBoxProfiles := preload("zz_box_profiles.gd")
const ZzCatalogue := preload("zz_catalogue.gd")
const ZzConfig := preload("zz_config.gd")
const ZzController := preload("zz_controller.gd")
const ZzFlashlight := preload("zz_flashlight.gd")
const ZzGrenadeFx := preload("zz_grenade_fx.gd")
const ZzImpactMarks := preload("zz_impact_marks.gd")
const ZzHazards := preload("zz_hazards.gd")
const ZzTurrets := preload("zz_turrets.gd")
const ZzHorde := preload("zz_horde.gd")
const ZzLoot := preload("zz_loot.gd")
const ZzWeaponLayer := preload("zz_weapon_layer.gd")
const ZzGrenades := preload("zz_grenades.gd")
const ZzConsumables := preload("zz_consumables.gd")
const ZzCrates := preload("zz_crates.gd")
const ZzDrops := preload("zz_drops.gd")
const ZzMapObjects := preload("zz_map_objects.gd")
const ZzSpawners := preload("zz_spawners.gd")
const ZzShop := preload("zz_shop.gd")
const ZzMap := preload("zz_map.gd")
const ZzMaterials := preload("zz_materials.gd")
const ZzPacks := preload("zz_packs.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzMapCommands := preload("zz_map_commands.gd")
const ZzNetCommand := preload("net/zz_net_command.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzPins := preload("zz_pins.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzProgress := preload("zz_progress.gd")
const ZzProps := preload("zz_props.gd")
const ZzCrawlRules := preload("zz_crawl_rules.gd")
const ZzSlideRules := preload("zz_slide_rules.gd")
const ZzWaterRules := preload("zz_water_rules.gd")
const ZzFooting := preload("zz_footing.gd")
const ZzPassRules := preload("zz_pass_rules.gd")
const ZzAmbientRules := preload("zz_ambient_rules.gd")
const ZzEndCameraRules := preload("zz_end_camera_rules.gd")
const ZzRules := preload("zz_rules.gd")
const ZzSpectate := preload("zz_spectate.gd")
const ZzSurvival := preload("zz_survival.gd")
const ZzRespawn := preload("zz_respawn.gd")
const ZzTeamDamage := preload("zz_team_damage.gd")
const ZzInfection := preload("zz_infection.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzWorkshop := preload("zz_workshop.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

## The simulation. Headless, authoritative, and the only thing that decides anything.
## A round is a map: the horde runs once somebody leaves the start area; exodus is won inside the end shelter, survival when the hold is over, and a lost map is replayed [member ZzConfig.retries] times.
## Tick order is the design: bots, pins, movement, guns, horde, pin damage, then hazards, loot and the round on a world that has finished moving.

const CHANNEL := "zz.game"

## Where this world publishes itself, so a module can find it. A registry name and not an
## autoload: a server and a client in one process are two of these.
const SERVICE := &"zz_game"

## Where a host that runs this game with no server (the client shell's Solo play) publishes
## the map packs it mounted for it. See [method solo_map_dirs].
const SOLO_SERVICE := &"dot_solo"

## Snapshots a second. A crowd running at you is what a client is reading.
const NET_SNAPSHOT_RATE := 30

## How far a position may be from the origin, in metres, on the wire. Both ends read it here.
const NET_WORLD_EXTENT := 1024.0

## The two sides, as dot-combat and dot-match see them. Only one has players.
const SURVIVORS := 1
const INFECTED := 2

const TEAM_COLOURS: Array[Color] = [Color(0.36, 0.62, 0.95), Color(0.75, 0.2, 0.18)]
const TEAM_NAMES: Array[String] = ["Survivors", "Infected"]

## Which part of a map it is.
enum Phase {
	## Between maps, or waiting for somebody to play.
	IDLE,
	## In the start area: nothing comes yet.
	READY,
	## The horde is running.
	PLAY,
}

## Why somebody went down or died.
## Seconds a dead body lies before it fades, unless the owner sets `sv_ragdoll_time`.
const CORPSE_SECONDS := 6.0

const BY_ZOMBIE := &"zombie"
const BY_SPECIAL := &"special"
const BY_FRIEND := &"friend"
const BY_FELL := &"fell"
const BY_HAZARD := &"hazard"

## Damage type and weapon id of a survivor out of breath under water.
const DROWN := &"drown"
const BY_BLED := &"bled"
const BY_BOX := &"box"
const BY_REFLECT := &"reflected"

signal player_added(player_id: StringName)
signal player_removed(player_id: StringName)
signal round_began(number: int, map_id: StringName)
signal world_clearing()
signal world_rebuilt()
signal round_over(number: int, won: bool, why: String)
signal phase_changed(phase: int)
signal player_downed(player_id: StringName, by: StringName, why: StringName)
signal player_died(player_id: StringName, by: StringName, why: StringName)
signal player_revived(player_id: StringName, by: StringName)
## A dead survivor shocked back by [param by]'s defibrillator, where they lay.
signal defibbed(player_id: StringName, by: StringName)
signal player_rescued(player_id: StringName)
signal player_healed(player_id: StringName, by: StringName, amount: float)
signal player_biled(player_id: StringName, seconds: float)
signal player_hurt(player_id: StringName, amount: float, from: Vector3)
signal zombie_killed(npc_kind: StringName, by: StringName, headshot: bool)
signal objective_changed(index: int, state: StringName)
signal gate_opened(gate: String)
## A support of the map's broke and what stood on it falls (its index in `map.supports`).
signal support_broken(index: int)
## Wood gave way at a point (see [signal ZzMap.wood_broke]); both ends, the client draws it.
signal wood_broke(at: Vector3, size: float)
## A moving part of the map changed state ([method ZzMechanics.snapshot] has it).
signal mover_changed(index: int)
## A brush the map's point_template made or killed: `(id, model, offset, alive)`; the bridge tells clients.
signal copy_changed(id: int, model: int, offset: Vector3, alive: bool)
signal notice(text: String)
## A map's logic_winlose dressed its ending: a time scale for some seconds and a camera point (or null).
signal map_ending(won: bool, time_scale: float, seconds: float, camera: Variant)
## A map's logic_beats ticked; no music ships, so this is only a signal a client may pulse to.
signal map_beat(beat: int, downbeat: bool)
## A map's ambient_generic fades (`from` and `to` are -1 when the map gave none). No sound plays on a stand-in yet; this is where one would hear it.
signal map_sound_fade(entity: int, fading_in: bool, seconds: float, from: float, to: float)
## An ambient_generic spins its pitch up (-1 when the map gave none).
signal map_sound_spin(entity: int, seconds: float, from: float, to: float)
signal refused(player_id: StringName, why: String)
## A word to one player that is good news (a purchase), never the denied sound.
signal told(player_id: StringName, text: String)
## The trader opened, closed, moved or changed its list: clients are sent it again.
signal shop_changed()
## A player's weights, weapons by slot or backpack changed (the owner is told).
signal carry_changed(player_id: StringName)
signal achievement_earned(player_id: StringName, title: String, points: int)
signal player_armed(player_id: StringName, weapon_id: StringName)

## Everything [param player_id] held was taken away (a new map, a rescue): an empty ARMED on the
## wire, so a client's own rig and everybody's drawn hands start again.
signal player_disarmed(player_id: StringName)
## A survivor was dealt a class and a skin (empty: their own avatar) for this spawn.
signal player_classed(player_id: StringName, class_id: StringName, skin: StringName)
signal exploded(at: Vector3, radius: float, kind: StringName)

## A survivor's ammunition was filled by the server: a pile, a box. A predicting client's own
## rig has to be told, or it predicts an empty magazine the server has refilled.
signal ammo_given(player_id: StringName)

## A survivor's shot (or blast, or fire) took health off a zombie: the confirmation the shooter's
## hit marker is drawn from. The authority's decision, sent to the shooter alone; [param victim] is the
## zombie's entity id and [param point] where it landed.
signal hit_landed(player_id: StringName, victim: int, amount: float, point: Vector3, killed: bool, headshot: bool)

## A shot was resolved on the authority and left marks on the map: `[[point, normal], ...]` (see ZzImpactMarks).
signal shot_marked(marks: Array)

## A barricade took damage, broke, or was mended: its strength as a share, and whether it stands.
signal barricade_changed(id: String, fraction: float, intact: bool)

## The survival hold moved on (a wave began or was cleared, a night fell): the bridge tells
## every client at once rather than at the next clock.
signal survival_changed()

@export var config: ZzConfig = null

## Binds [member config] to cvars, the cfg/ yml layers and the workbench; made by whoever loaded the config.
var config_binder: DotGameConfigBinder = null
## The flashlight's config and binder, made on first use so a suite that builds a game by hand still has one.
var flashlight_config: DotFlashlightConfig = null
var flashlight_binder: DotGameConfigBinder = null

## The runtime layer the workbench edits through (the config set and dot-team's noblock kind); made on demand.
var profile_runtime: DotProfileRuntime = null

## The actor of an edit made on the process itself: the server console, or offline play.
const LOCAL_ACTOR := &"__local"


## dot-team's block rules (`!block`, `!noblock`, `mp_teamblock`), set by the server module or `DotGameClient.add_noblock`. They feed [member body_rules]'s `pair_fn`.
var block_rules: Object = null:
	set(value):
		if block_rules != null and block_rules.is_connected(&"changed", body_rules.refresh):
			block_rules.disconnect(&"changed", body_rules.refresh)
		block_rules = value
		if block_rules != null and block_rules.has_signal(&"changed"):
			block_rules.connect(&"changed", body_rules.refresh)
@export var authoritative: bool = true
@export_range(1, 240, 1) var tick_rate: int = 64
@export var external_tick: bool = false
@export var register_service: bool = true

## Whether this machine draws the world: a client does, a server does not.
@export var draw_world: bool = false

## doc -> `<owner>/<world>@<version>`, or "": where a map's drawn world is published. Set by the
## module on a server; unset, a client finds a world only in its own checkout.
var world_key_fn: Callable = Callable()

var map: ZzMap = null
var catalogue: ZzCatalogue = null

## Where subscribed Workshop maps are read from; null is dot-core's shared index. A test gives its own.
var content_index: DotContentIndex = null
var props_catalogue: ZzProps = null
var combat: DotCombatManager = null

## Ammo profiles (`cfg/game/game-zombie-zone/ammo`): what each gun's round can penetrate and ricochet off.
var ammo_types: DotWeaponAmmoTypes = _load_ammo_types()

## `func(player_id: StringName) -> bool`: whether a survivor may be hurt now, assigned by the
## module from dot-game's `can_peer_be_harmed`. Unset offline, and a stand-in is never loading.
var harm_gate: Callable = Callable()
var match_node: DotMatch = null
var random: DotRandomManager = null
var physics: DotPhysicsLayout = null
var effects: DotFxManager = null
var spectate: ZzSpectate = null
var progress: ZzProgress = null

## Where lifetime stat totals persist (a user:// JSON file). Empty keeps none, so a suite is the same on every run; the server sets it.
var stats_file: String = ""

## Server only. A client is told about zombies, pins, hazards and loot by the bridge.
var horde: ZzHorde = null
var pins: ZzPins = null
var hazards: ZzHazards = null
## Server only. The sentry turrets a box deployed.
var turrets: ZzTurrets = null
var loot: ZzLoot = null
## Weapons lying in the world (the drop key, Q; deaths): see [ZzWeaponLayer].
var weapon_layer := ZzWeaponLayer.new(self)
## fc-weapons' thrown grenades, when that pack is mounted.
var grenades := ZzGrenades.new(self)
## Pills and medkits: slots, stack limits, use times, healing and handing over a friend.
var consumables := ZzConsumables.new(self)

## Ammo piles and boxes as rigid bodies (server only; null on a client).
var crates: ZzCrates = null

## Per-weapon force on each kind of loose prop (`props/forces.json`), loaded on the first shot.
var prop_force: RefCounted = null

## Who carries which loose prop (server side).
var prop_carry: ZzPropCarry = ZzPropCarry.new()
## What a dead zombie leaves (ammunition, health); server only.
var drops: ZzDrops = null
## What a map's breakables leave when they break (`spawn_object`), whitelisted and capped.
var map_objects: ZzMapObjects = null
## The trader's menu (zz_shop.gd), server only.
var shop = null
## The map's weapon and supply spawners (zz_spawners.gd), server only.
var spawners: ZzSpawners = null
var boxes: ZzBoxes = null

## The carry rules, shared by every player's arsenal (a client's copy only stows, see [ZzCarry]).
var carry := ZzCarry.new()
var bots: ZzBots = null

var _persona_set: DotProfileSet = null
var _personas: DotBotPersonaPool = null
var _personas_text := ""


var _box_set: DotProfileSet = null


## player id -> [ZzPlayer].
var players: Dictionary = {}

## dot-player-controller's `mp_forceview` (may a player switch to third person) and
## `mp_solidplayers` (do survivors and stand-ins block each other). Bound by the module
## (REPLICATED) and followed by a client through its link.
var view_rules: DotPlayerViewRules = DotPlayerViewRules.new()
var body_rules: DotPlayerBodyRules = DotPlayerBodyRules.new()

## `sv_falldamage*`: landing hard hurts. On in this game (dot-combat's default is off); the
## server applies it through [member combat], a client never does.
var fall_rules: DotFallDamageRules = _make_fall_rules()

## `zz_pass_barricades`: whether survivors walk through barricades. Bound by the module
## (REPLICATED) and followed by a client, which predicts its own player under it.
var pass_rules: ZzPassRules = ZzPassRules.new()

## The net under the survivors: put back on the ground after a fall or a long stuck (`zz_fall_rescue`, `zz_stuck_rescue_seconds`).
var footing: ZzFooting = ZzFooting.new()

## `zz_down_crawl_speed`: how fast a downed survivor crawls (0: not at all). Bound by the module
## (REPLICATED) and followed by a client, which predicts its own player under it.
var crawl_rules: ZzCrawlRules = ZzCrawlRules.new()

## `zz_slide*`: the slide's numbers ([ZzSlideRules]). REPLICATED and followed by a client, which predicts its own slide.
var slide_rules: ZzSlideRules = ZzSlideRules.new()

## `sv_downed_*`: what a downed survivor holds and whether they crawl with it. REPLICATED, followed by a client.
var downed_rules: DotDownedRules = DotDownedRules.new()

## Aim-down-sights numbers (`zee_ads_rules`, REPLICATED): the server's cfg over the shipped defaults. One per game, not
## per process, so a client in the same process as its server adopts the server's rather than sharing them.
var ads_rules: ZeeAdsRules = ZeeAdsRules.load_config()

## The view model's motion amounts: zee-dot-weapons' `mp_vm_*` cvars and `cl_vm_kick` (REPLICATED). The client's view model is handed this object, so one cvar change reaches the drawn hands.
var feel_rules: ZeeViewFeel = ZeeViewFeel.new()

## Movement-dependent spread, recoil patterns, sprint and stamina (`sv_spread*`, `sv_recoil*`, `sv_sprint*`, `sv_stamina*`, REPLICATED, on here) and the `cl_crosshair_*` cvars: dot-game's opt-in.
var combat_feel: DotGameCombatFeel = DotGameCombatFeel.new(true)

## The `zz_water*` settings: how survivors wade, swim and drown, and how the horde wades. The
## movement ones are REPLICATED and a client follows them (see [ZzWaterRules]).
var water_rules: ZzWaterRules = ZzWaterRules.new()

## Server: team damage, added up per player over a window ([ZzTeamDamage]); the module wires
## The `zz_ambient*` settings: the creepy ambience under a map (see [ZzAmbientRules], [ZzAudio]).
var ambient_rules: ZzAmbientRules = ZzAmbientRules.new()
## The `zz_end_camera*` settings: how a map's ending camera looks (see [ZzEndCameraRules], [ZzClient]).
var end_camera_rules: ZzEndCameraRules = ZzEndCameraRules.new()

## what a voteban and a ban do.
var team_damage: ZzTeamDamage = ZzTeamDamage.new()

## What a dead body does and which death reactions the server allows: dot-player-char's `sv_ragdoll*` cvars,
## bound by the module (REPLICATED) and followed by a client through its link. One set for survivors and zombies.
## A body lies [constant CORPSE_SECONDS] by default.
var ragdoll_rules: DotPlayerRagdollRules = _corpse_rules()

## dot-props' `sv_toys*` (whether a map's toys are there, how many simulate at once, how hard a
## walk pushes one). Bound by the module (REPLICATED) and followed by a client, which draws them.
var toy_rules: DotPropBodyRules = DotPropBodyRules.new()
## The harm a barrel does by rolling into a survivor (dot-props); server only.
var rolling := DotPropRolling.new()
## The zombies' own scan: a separate cooldown clock from the survivors'.
var rolling_zombies := DotPropRolling.new()

## player id -> side. Everybody is a survivor today.
var sides: Dictionary = {}

## The map to play next, chosen by a vote or an admin. Empty: the rotation decides.
var next_map_id: StringName = &""

var round_number: int = 0
var phase: int = Phase.IDLE
var phase_elapsed: float = 0.0
var map_doc: Dictionary = {}
var entities := DotEntityTable.new()

## Survival: seconds held, and the clock style's goal. An exodus map leaves them at zero.
var survival_elapsed: float = 0.0
var survival_goal: float = 0.0

## Server: the survival map's hold, while one is being held. See [ZzSurvival].
var survival: ZzSurvival = null
var infection: ZzInfection = null

## Server: survivors who turned and now hold a zombie body.
var possession: ZzPossession = null

## What a client was told of the hold, the shape of [method ZzSurvival.state]; empty for none.
var remote_survival: Dictionary = {}

## The start grace: no zombies for the first seconds of a map (`zz_escape_grace_seconds`). The server's; a client reads [member remote_grace_left].
var grace := DotNpcDirectorGrace.new()
## Seconds of grace a client was told are left (0 when none, or the HUD countdown is off).
var remote_grace_left: float = 0.0

## Every barricade of the map in play: id -> {health, max, intact, label}. Both ends keep it:
## the server decides, a client is told (BARRICADE) and draws it.
var barricades: Dictionary = {}

## Each objective's state: `waiting`, `holding` (the holdout is running), `done`.
var objective_states: Array[StringName] = []
var objective_progress: Array[float] = []

## Seconds the standing survivors have all been in the end area.
var end_hold: float = 0.0

## What a client is told rather than works out.
var remote_alive: int = -1
var remote_seconds_left: float = -1.0

## A client's copy of how long until the next map begins after a decided one, and which map
## (from ROUND); -1 while a map is being played. See [method next_round_seconds].
var remote_next_round: float = -1.0

## The navigation build's percent as the server last said (a client only), -1 for none.
var remote_nav: int = -1
var remote_next_map: StringName = &""
var remote_playable: bool = false

## How many times this map has been lost in a row.
var losses_on_map: int = 0

var _tick: int = 0
var _round_seed: int = 0
var _decided: bool = false
var _won: bool = false
var _why: String = ""
var _lost_since: float = -1.0
var _hurt_backlog: Dictionary = {}


## Survivors' team and the horde's in a converted map's team filters (the source game's CT and T).
const VOLUME_TEAM_SURVIVORS := 3
const VOLUME_TEAM_ZOMBIES := 2
## A hurt volume's hit at or above this kills outright: a kill floor is "damage 99999", not a bleed.
const VOLUME_LETHAL := 500.0


## Which survivor holds a game_ui's controls, by entity index.
var ui_holders: Dictionary = {}


## Set by the hosts (client, server) before the world is added: a map's navigation graph is then built
## off the frame and a round waits in its ready phase for it. A suite leaves it off and gets the graph at once.
const ZzLaps := preload("zz_laps.gd")

var nav_async: bool = false


## Counts every [method ZzMap.build] this world ran; the tests read it.
var map_builds: int = 0
var _built_stamp: int = 0


var _class_rng := RandomNumberGenerator.new()


## Seconds after the last blow on a barricade before it can be mended; mending under attack outran any crowd,
## so a team behind boards mended for ever and no wave cleared.
## The boards are held by killing what tears at them; mending is the breather's job.
const MEND_LOCKOUT := 1.5


## Why the last [method arm] refused ("" when it was not the weight); the caller says it to the player.
var arm_failure: String = ""


var _human_feet := PackedVector3Array()
var _motor_owed: Dictionary = {}
var _far_cache: Dictionary = {}


## Asked every tick of a world that ticks itself: true while a cover is up (the client's load
## gate). Only the bodies are stepped then, so the director, waves, hazards, clocks and damage
## do not act on anybody in front of a picture. Unset, never held.
var hold_clock: Callable = Callable()


## Microseconds spent inside [method simulate] since the start (tools/bench.gd reads it).
var tick_us_total: int = 0


## Set by a drawn solo client: the horde moves once per drawn frame ([member ZzConfig.horde_frame_ticks]).
var horde_per_frame: bool = false
var _horde_frame: int = -1
var _horde_owed: int = 0
## The last per-frame horde tick's cost, µs (tools/bench.gd reads it).
var horde_frame_us: int = 0


## A blast's speed at its centre, m/s to a toy (dot-props' `blast`).
const TOY_BLAST_SPEED := 12.0


static func _load_ammo_types() -> DotWeaponAmmoTypes:
	var types := DotWeaponAmmoTypes.new()
	var _n := types.load_set(DotWeaponAmmoTypes.make_set("", "game-zombie-zone"))
	return types


## The stock rules with the game's corpse time: a horde dies by the dozen, and a body lying ten
## seconds (dot-player-char's default) kept the floor of a survival wave covered.
static func _corpse_rules() -> DotPlayerRagdollRules:
	var rules := DotPlayerRagdollRules.new()
	rules.lifetime = CORPSE_SECONDS
	return rules


static func _make_fall_rules() -> DotFallDamageRules:
	var rules := DotFallDamageRules.new()
	rules.enabled = true
	return rules
