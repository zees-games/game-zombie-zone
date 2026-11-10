extends Node

## The declarations of [zz_client.gd]: constants, signals and variables, so the file that extends this holds behaviour only.

const ZzEvents := preload("net/zz_events.gd")
const ZzAudio := preload("zz_audio.gd")
const ZzBindings := preload("zz_bindings.gd")
const ZzBots := preload("zz_bots.gd")
const ZzCarry := preload("zz_carry.gd")
const ZzTouch := preload("zz_touch.gd")
const ZzPrewarm := preload("zz_prewarm.gd")
const ZzBoxes := preload("zz_boxes.gd")
const ZzBoxHands := preload("zz_box_hands.gd")
const ZzDefibHands := preload("zz_defib_hands.gd")
const ZzFigure := preload("zz_figure.gd")
const ZzSettings := preload("zz_settings.gd")
const ZzBlood := preload("zz_blood.gd")
const ZzBreakFx := preload("zz_break_fx.gd")
const ZzServices := preload("zz_services.gd")
const ZzNetBridge := preload("net/zz_net_bridge.gd")
const ZzNetCommand := preload("net/zz_net_command.gd")
const ZzConfig := preload("zz_config.gd")
const ZzGame := preload("zz_game.gd")
const ZzHud := preload("zz_hud.gd")
const ZzKillcam := preload("zz_killcam.gd")
const ZzShopIcons := preload("zz_shop_icons.gd")
const ZzLoot := preload("zz_loot.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const MapThreads := preload("res://addons/dot_game/runtime/dot_game_map_threads.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzImpactMarks := preload("zz_impact_marks.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzWorldView := preload("zz_world_view.gd")
const ZzShopMenu := preload("zz_shop_menu.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")
const ZzMutantView := preload("../npcs/zz_mutant_view.gd")
const ZzOilMonsterModel := preload("../npcs/zz_oil_monster_model.gd")
const ZzWeaponIcons := preload("zz_weapon_icons.gd")

## One local survivor, a camera, a HUD and the world drawn round them, over a [ZzGame], offline or on a server.
## Offline is the same world class with `authoritative` true and stand-ins for a team; only [ZzNetBridge] changes where answers come from.
## First person (F5 for third); down, the camera drops to the floor; dead, it watches the others.

const CHANNEL := "zz.client"

const CHASE_BACK := 2.6
const CHASE_UP := 0.6

@export var config_file: String = "user://cfg/zombiezone.json"
@export var force_offline: bool = false
## Off for tests and tools: the offline gate otherwise waits on the content download.
@export var standalone_content: bool = true

## How many stand-ins an offline map gets beside you.
@export_range(0, 12, 1) var offline_bots: int = 3

var game: ZzGame = null
var player: ZzPlayer = null
## The flashlight on the eye and the other survivors' beams (dot-flashlight); the server owns on/off.
var flash: DotFlashlight = null
var flash_crowd: DotFlashlightCrowd = null
var _flash_ticks := 0
## Ticks left to hold ACT_FIRE_MODE after the fire-mode key was pressed.
var _fire_mode_ticks := 0
## Ticks left to hold ACT_CYCLE after the slot key was pressed twice.
var _cycle_ticks := 0
## Ticks left to hold ACT_DROP after the drop-weapon key was pressed.
var _drop_ticks := 0
var _give_pills_ticks := 0
var _give_kit_ticks := 0
## This end's copy of the carry rules: stows several per slot like the server, never refuses on weight.
var _mirror := ZzCarry.new()
var _flash_msec := -100000

## Keeps the screen covered, and the local body and the input still, until the map, the
## player and the camera are all in. The platform's; see [DotGameClient].
var gate: DotLoadGate = null

## dot-game's client platform: the cover, settings and menu, console, Tab, M, the pointer, the
## input block and the browser's filesystem flush.
var platform: DotGameClient = null
var camera: Camera3D = null
var hud: ZzHud = null
var board: DotMenuScoreboard = null
var chat: DotGameChatClient = null
var audio: ZzAudio = null
var settings: ZzSettings = null

## The player's console (the platform's).
var console: DotConsoleController = null
var world_view: ZzWorldView = null
## Blood behind a body the local shooter hit (see zz_blood.gd).
var blood: ZzBlood = null
## Splinters where a barricade or a support breaks.
var break_fx: ZzBreakFx = null

## Your own gun, drawn. Never decides anything: every shot is the server's.
var weapons: ZeeWeaponRig = null
var view_model: ZeeViewModel = null
var defib_hands: Node3D = null
var _defib_sound: bool = false
## Survivors other than this one heard charging a defibrillator now, by player key.
var _defib_heard: Dictionary = {}
var _defib_scratch: Dictionary = {}
## The crate in the hands while a box is out, a sibling of the gun under the camera.
var box_hands: Node3D = null

var net: DotNetManager = null
var bridge: ZzNetBridge = null
var link: Node = null
## Asks a server whether this player may edit it (sv_workbench_remote); null offline.
var workbench_remote: DotGameWorkbenchRemoteClient = null
## The tuning panel's host: F9 solo or hosting, the admin's remote panel on a server that allows it.
var workbench: DotGameWorkbench = null
## Records every frame and replays the map's last moment ([ZzKillcam]); then the reveal.
var killcam: ZzKillcam = null
var winner_reveal: DotWinnerReveal = null

var third_person: bool = false

var _offline: bool = true
## The server's `mp_killcam_time`; -1 until it has said, so the config's number stands.
var _killcam_sec: float = -1.0

## The server's `mp_killview_camera` ([enum DotKillViewRules.Camera]); the eye until it has said.
var _killcam_camera: int = DotKillViewRules.Camera.EYE

## Weapon pictures for the killcam banner, drawn from the weapon models on first ask.
var _killcam_icons: ZzShopIcons = null
var _map_ending: bool = false
var _end_point := Vector3.ZERO
var _end_left := 0.0
## The longest an ending holds the clock slow or the camera away, in real seconds (the window cvar's own ceiling).
const END_HOLD_MAX := 20.0
## Lets a headless run apply the slow motion, which it skips by default.
var slowmo_in_headless := false
var _slowed := false
var _slow_gen := 0
var _end_elapsed := 0.0
var _end_weight := 0.0
var _end_active := false
var _map_won: bool = false
var _map_why: String = ""
var _board_opened: bool = false
var _covered_by_reveal: Dictionary = {}
var _sampler: DotFpsSampler = null
## The phone's on-screen buttons ([code]zz_touch.gd[/code]); null off touch.
var _touch: RefCounted = null
var _prewarmed := false
var _watch_id: int = -1
var _arm: DotCameraBoom = null
## The local survivor's crawling arms in first person while down, under a yaw-only pivot at the eye.
var view_arms: DotPlayerViewArms = null
var _arms_yaw: Node3D = null
var _fade: DotCameraFade = null
var _rig_height: float = 0.0
var _started_msec: int = Time.get_ticks_msec()

var _firing: bool = false
var _shoving: bool = false
## The Aim key held (`ZzBindings.AIM`, right mouse): the view model comes up and the lens zooms.
var _aiming: bool = false

## The lens before an aim zooms it: the menu's field of view lands here, not on the camera, so
## the zoom always scales the player's own setting and never compounds frame to frame.
var base_fov: float = DotMenuApplier.vertical_from_horizontal_4_3(ZzSettings.DEFAULT_FOV)
var _reloading: bool = false
var _using: bool = false
## The trader's list as the server last said it ({menu, open, radius, at, items}), and its menu.
var shop_state: Dictionary = {}
var _shop_menu: PanelContainer = null
var _healing: bool = false
var _pills: bool = false
var _box_key: bool = false
var _slot: int = 0

## Box types' colours, offline from the catalogue, connected from the file the server also has.
var _box_colours: Dictionary = {}
var _box_order: Array[StringName] = []
## The water the local survivor was in last frame (a ZzPlayer.WaterLevel), for the splash; the
## low-pass the SFX bus wears under water, and the slot it took (-1 when not worn).
var _last_water_level: int = 0
var _muffler_slot: int = -1
var _box_titles: Dictionary = {}

## A brute is alive: its music plays.
var _brutes: int = 0
