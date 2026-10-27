extends Node

const ZzEvents := preload("net/zz_events.gd")
const ZzAudio := preload("zz_audio.gd")
const ZzBindings := preload("zz_bindings.gd")
const ZzBots := preload("zz_bots.gd")
const ZzCarry := preload("zz_carry.gd")
const ZzBoxes := preload("zz_boxes.gd")
const ZzBoxHands := preload("zz_box_hands.gd")
const ZzDefibHands := preload("zz_defib_hands.gd")
const ZzFigure := preload("zz_figure.gd")
const ZzSettings := preload("zz_settings.gd")
const ZzBlood := preload("zz_blood.gd")
const ZzServices := preload("zz_services.gd")
const ZzNetBridge := preload("net/zz_net_bridge.gd")
const ZzNetCommand := preload("net/zz_net_command.gd")
const ZzConfig := preload("zz_config.gd")
const ZzGame := preload("zz_game.gd")
const ZzHud := preload("zz_hud.gd")
const ZzKillcam := preload("zz_killcam.gd")
const ZzLoot := preload("zz_loot.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzWorldView := preload("zz_world_view.gd")
const ZzShopMenu := preload("zz_shop_menu.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")

## One local survivor, a camera, a HUD and the world drawn round them, over a [ZzGame] —
## offline, or against a server.
##
## [b]One client for both, and the offline half is not a demo mode.[/b] It is the same world
## class with `authoritative` true, stand-ins for a team, and nothing else different. What
## changes is where the answers come from, and the whole of that difference is [ZzNetBridge]:
## offline the world's own signals reach [method _hear_the_world], connected the bridge's reach
## [method _build_netcode], and both call the same handlers with the same arguments.
##
## [b]First person, because this is a game about not seeing what is behind you.[/b] F5 is a
## third-person view for those who want it; down, the camera drops to the floor; dead, it
## watches the others.

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
## Ticks left to hold ACT_CYCLE after the slot key was pressed twice.
var _cycle_ticks := 0
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

## Your own gun, drawn. Never decides anything: every shot is the server's.
var weapons: ZeeWeaponRig = null
var view_model: ZeeViewModel = null
var defib_hands: Node3D = null
var _defib_sound: bool = false
## The crate in the hands while a box is out, a sibling of the gun under the camera.
var box_hands: Node3D = null

var net: DotNetManager = null
var bridge: ZzNetBridge = null
var link: Node = null
## Records every frame and replays the map's last moment ([ZzKillcam]); then the reveal.
var killcam: ZzKillcam = null
var winner_reveal: DotWinnerReveal = null

var third_person: bool = false

var _offline: bool = true
## The server's `mp_killcam_time`; -1 until it has said, so the config's number stands.
var _killcam_sec: float = -1.0
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
var _watch_id: int = -1
var _arm: DotCameraBoom = null
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


func _ready() -> void:
	# First, before anything can be drawn: the map, the player and the camera all arrive
	# after this node is in the tree. The platform puts the loading cover up, held until the
	# player exists and the camera is current, and finds the link.
	platform = DotGameClient.new()
	platform.name = "Platform"
	platform.force_offline = force_offline
	platform.use_standalone_content = standalone_content
	platform.spawned_fn = func() -> bool:
		return player != null and camera != null and camera.is_inside_tree()
	platform.scoreboard_action = ZzBindings.SCOREBOARD
	add_child(platform)
	gate = platform.gate
	gate.hold(&"map", "Loading the map")
	# Connected, the cover waits for the server's word on what this survivor holds, so the view model is
	# drawn (and its materials warmed) before the player is shown; the gate's timeout is the backstop.
	# The survivor is on the map (its first server position applied), not at a mirror's default in the void.
	gate.require(&"placed", _is_placed, "Placing you")
	gate.require(&"weapon", func() -> bool: return _offline or _armed_told, "Arming")
	ZeeModelCache.set_asset_root(ZzPaths.root())

	var config := ZzConfig.new()
	var loaded := ZzConfig.boot(config, config_file)

	if not loaded.ok:
		DotGameConfigBinder.fail_boot(get_tree(), loaded)
		return

	link = platform.link as Node
	_offline = platform.offline

	game = ZzGame.new()
	game.name = "World"
	game.config = config
	game.config_binder = loaded.value
	game.authoritative = _offline
	game.register_service = _offline
	game.tick_rate = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 64))
	game.draw_world = true
	game.nav_async = true
	# Before the world is added: a world that ticks itself must not run in front of a picture.
	game.hold_clock = _covered
	game.horde_per_frame = _offline and DisplayServer.get_name() != "headless"
	_hold_for_maps()
	add_child(game)

	_sampler = DotFpsSampler.new(ZzPlayer.tunables_for(config))
	ZzPlayer.register_actions(_sampler)
	game.combat_feel.track_tunables(_sampler.tunables)

	_build_hud()
	_build_chat()
	_build_audio()
	_build_settings()
	_build_killcam()
	_build_world_view()
	_read_box_colours()

	if _offline:
		_start_offline()
	else:
		DotLog.result(CHANNEL, "the netcode", _build_netcode())


# The load gate is the platform's. Covered also means the horde does not act: offline the
# world ticks itself, so the director, waves, clocks and damage would all work on the survivor
# in front of a picture; [member ZzGame.hold_clock] steps only the bodies then, which settle
# onto the floor under the cover with their input off. Connected, the server owns all of that;
# what is left to hold is this end's sampling and keys, which wait on [method _covered].

## Covered from the moment a map starts clearing until it is rebuilt, the first build and every
## later one (a vote's, the map menu's, a server's next).
func _hold_for_maps() -> void:
	game.world_clearing.connect(func() -> void:
		if gate != null:
			gate.hold(&"map", "Loading the map"))
	game.world_rebuilt.connect(func() -> void:
		_draw_world()
		if gate != null:
			gate.release(&"map"))


## The map's own geometry, fetched when it is delivered, under the cover ([method ZzMap.load_world]).
## Whatever happens the cover lifts: without its world a map is drawn with its boxes.
func _draw_world() -> void:
	if game == null or game.map == null or str(game.map.doc.get("world", "")) == "":
		return
	# A later map's load owns the hold once it starts: an earlier one returning must not lift it.
	_world_ticket += 1
	var ticket := _world_ticket
	if gate != null:
		gate.hold(&"world", "Loading the world")
	game.map.vis_mode = _vis_mode()
	var _mode := platform.set_vis_mode(game.map.vis_mode)
	game.map.cull_fn = platform.attach_visibility
	game.map.use_lightmaps = bool(game.config.get(&"lightmaps")) if game.config != null else true
	if game.config != null:
		game.map.prop_shadow_min = float(game.config.get(&"prop_shadow_min"))
		game.map.sun_floor = float(game.config.get(&"sun_floor"))
		game.map.set_light_floor(float(game.config.get(&"light_floor")))
		game.map.set_shadow_cost(bool(game.config.get(&"shadow_proxy")), float(game.config.get(&"shadow_range")), bool(game.config.get(&"shadow_translucent")))
		game.map.set_sun_shadow_splits(int(game.config.get(&"sun_shadow_splits")))
		game.map.set_model_lod(int(game.config.get(&"prop_lod_min_tris")), int(game.config.get(&"prop_max_tris")))
		get_viewport().mesh_lod_threshold = maxf(float(game.config.get(&"mesh_lod_threshold")), 0.0)
	var _drawn: DotResult = await game.map.load_world()
	if gate != null and ticket == _world_ticket:
		gate.release(&"world")


var _world_ticket: int = 0


## The map culling mode: the config's `vis_mode` when set (bench, server cfg), else the video setting.
func _vis_mode() -> String:
	if game != null and game.config != null and str(game.config.get(&"vis_mode")) != "":
		return str(game.config.get(&"vis_mode"))
	var names := ["off", "pvs", "occluders", "both"]
	if settings == null or settings.settings == null:
		return "both"
	return names[clampi(settings.settings.get_int(&"vis_mode", 3), 0, 3)]
## The server has said what this survivor holds (a weapon or nothing); the load gate's `weapon` requirement.
var _armed_told: bool = false


## The local survivor stands inside the built map's bounds and above its kill height.
func _is_placed() -> bool:
	if _offline:
		return true

	if player == null or game == null or game.map == null:
		return false

	var at := player.global_position
	var bounds := game.map.bounds()
	return at.y > game.map.kill_height() and (bounds.size == Vector3.ZERO or bounds.grow(8.0).has_point(at))


## True while the load gate covers the screen: no input, no sampling, no horde.
func _covered() -> bool:
	return gate != null and not gate.is_open()


## The figure an avatar action plays on (the drawn person): that peer's player, or the local one offline.
func _avatar_figure(peer_id: int) -> Object:
	var who: ZzPlayer = null
	if bridge != null and peer_id != 0:
		who = game.players.get(ZzNetBridge.player_key(bridge.player_for_peer(peer_id)))
	if who == null and player != null and (net == null or peer_id == net.local_peer_id):
		who = player
	return who.figure.body_node() if who != null and who.figure != null else null


func _exit_tree() -> void:
	reset_slowmo()
	ZeeModelCache.set_asset_root("res://")


func _build_world_view() -> void:
	world_view = ZzWorldView.new()
	world_view.name = "WorldView"
	world_view.audio = audio
	world_view.ragdoll_mask = game.ground_mask()
	world_view.ragdoll_rules = game.ragdoll_rules
	world_view.fade_config = game.config
	game.add_child(world_view)
	blood = ZzBlood.new()
	blood.mask = game.world_mask()
	game.add_child(blood)
	blood.apply_settings(null)
	var render_quality := DotFxRenderQuality.new()
	render_quality.name = "RenderQuality"
	add_child(render_quality)
	render_quality.load_layers()
	_warm_zombies()


## Draws every zombie look once under the cover, so the first one of a kind to walk into view
## does not compile its shader mid-play: nothing of them is in the tree until the server spawns
## one, and the gate only warms what it can find.
func _warm_zombies() -> void:
	if gate == null:
		return

	var materials: Array = []
	var bodies := {}

	for kind: StringName in [ZzNpcs.COMMON, ZzNpcs.LEAPER, ZzNpcs.STRANGLER, ZzNpcs.BLOATER, ZzNpcs.RAM,
			ZzNpcs.SPITTER, ZzNpcs.RIDER, ZzNpcs.BRUTE, ZzNpcs.SLEEPER, ZzNpcs.SCREAMER, ZzNpcs.CRAWLER,
			ZzNpcs.RIOT]:
		var variants := ZzZombieView.common_variety() if kind == ZzNpcs.COMMON else 1

		for variant in variants:
			var look := ZzZombieView.look_for(kind, variant)
			materials.append(ZzZombieView._material_for(look))

			# Each distinct body once: its model, clips and retarget are cached statics, which the first
			# zombie of a wave would otherwise build mid-play.
			if not bodies.has(look["body"]):
				bodies[look["body"]] = true
				var view := ZzZombieView.new()
				world_view.add_child(view)
				view.build(kind, variant)
				view.queue_free()

	gate.warm_up(materials)


func _read_box_colours() -> void:
	var boxes := ZzBoxes.new(game)

	if boxes.load_file(game.config.box_file) > 0:
		for id in boxes.order:
			_box_colours[id] = boxes.colour_of(id)

		_box_order.assign(boxes.order)
		_box_titles = {}
		for id in boxes.order:
			_box_titles[id] = boxes.title_of(id)


# --- Offline ---------------------------------------------------------------

func _start_offline() -> void:
	_fill_offline_team()
	_adopt(game.add_player(&"local", "You", 0, true))
	_hear_the_world()
	# Each map brings the team it is built for: a dozen at the school, four on the street.
	game.world_rebuilt.connect(_fill_offline_team)

	game.achievement_earned.connect(func(id: StringName, title: String, points: int) -> void:
		if player != null and id == player.player_id and chat != null:
			chat.say_locally("Achievement: %s (+%d)" % [title, points], Color(0.98, 0.84, 0.40))
	)
	game.start()
	DotLog.result(CHANNEL, "chat, offline", chat.attach(null))


## The most stand-ins a solo game seats where [method DotPlatform.has_threads] is false or the
## machine has four cores or fewer.
const WEAK_HARDWARE_BOTS := 7


## Solo stand-ins: [member offline_bots], or the team the map is built for less you, whichever
## is more ([method ZzGame.team_size]); the last ones in leave first on a smaller map.
func _fill_offline_team() -> void:
	var wanted := maxi(offline_bots, game.team_size() - 1) if offline_bots > 0 else 0
	# A browser without threads, or a machine with few cores, cannot run fifteen stand-ins and the
	# horde in the time a frame has: half a team still holds the map. A capability, never the OS name.
	if wanted > WEAK_HARDWARE_BOTS and (not DotPlatform.has_threads() or OS.get_processor_count() <= 4):
		wanted = WEAK_HARDWARE_BOTS
	var have: Array[StringName] = []

	for id: StringName in game.players:
		if (game.players[id] as ZzPlayer).is_bot:
			have.append(id)

	have.sort_custom(func(a: StringName, b: StringName) -> bool: return int(String(a).substr(1)) < int(String(b).substr(1)))

	while have.size() > wanted:
		game.remove_player(have.pop_back())

	var next := have.size()

	while have.size() < wanted:
		var id := StringName("u%d" % (ZzNetBridge.FIRST_BOT_SESSION + next))
		if not game.players.has(id):
			var bot := game.add_player(id, _bot_name(next))
			bot.is_bot = true
			have.append(id)
		next += 1


## A solo stand-in's name: the server's list, through dot-bot's pick, so solo and a server
## name them alike.
static func _bot_name(index: int) -> String:
	var taken: Array = []
	for i in range(index):
		taken.append(DotBotNames.pick(taken, i, ZzBots.BOT_NAMES))
	return DotBotNames.pick(taken, index, ZzBots.BOT_NAMES)


## dot-team's block rules followed from the server, and the F9 tuning panel where this process hosts the game.
func _add_noblock_and_workbench() -> void:
	if game == null:
		return
	if link != null:
		DotLog.result(CHANNEL, "noblock", platform.add_noblock(game, Callable(game, "team_of_side")))
		return
	var rt := game.ensure_runtime()
	var wb := DotGameWorkbench.new()
	wb.name = "Workbench"
	wb.listen_host_fn = func() -> bool: return true
	if game.config_binder != null:
		for set: DotProfileSet in game.config_binder.profile_sets():
			wb.add_set(set, "Game settings: %s" % set.rel_path.trim_prefix("config_"))
	var _fl := game.flashlight_conf()
	if game.flashlight_binder != null:
		for set: DotProfileSet in game.flashlight_binder.profile_sets():
			wb.add_set(set, "Flashlight")
	add_child(wb)
	var started := wb.start(rt)
	DotLog.result(CHANNEL, "the workbench", started)
	if started.ok and game.config_binder != null:
		game.config_binder.attach(rt)
	if started.ok and game.flashlight_binder != null:
		game.flashlight_binder.attach(rt)
	platform.add_workbench(wb)


# --- Connected -------------------------------------------------------------

func _build_netcode() -> DotResult:
	# The server's `mp_teammate_passthrough`, and every change to it, through the link: this
	# end traces its own shots for tracers and impacts, and on its default 1 against a server
	# on 0 or 2 they ended in (or went through) a team-mate where the server's did the
	# opposite. An older shell's link cannot say, and the manager keeps its default.
	if game.combat != null and link != null:
		var _following := game.combat.follow_cvars(link)
	# The server's mp_forceview and mp_solidplayers: this end places its own camera and
	# predicts its own player.
	if link != null:
		var _view := game.view_rules.follow_cvars(link)
		if link.has_method(&"replicated_cvar"):
			_on_killcam_cvar("mp_killcam_time", String(link.call(&"replicated_cvar", "mp_killcam_time", "")))
			if link.has_signal(&"replicated_cvar_changed"):
				link.connect(&"replicated_cvar_changed", _on_killcam_cvar)
		var _solid := game.body_rules.follow_cvars(link)
		game.combat_feel.follow_cvars(link)
		var _passing := game.pass_rules.follow_cvars(link)
		var _crawling := game.crawl_rules.follow_cvars(link)
		var _ads := game.ads_rules.follow_cvars(link)
		var _wading := game.water_rules.follow_cvars(link)
		var _ambient := game.ambient_rules.follow_cvars(link)
		# The server's sv_ragdoll* set: this end draws the bodies, survivors' and zombies'.
		var _dead := game.ragdoll_rules.follow_cvars(link)
		# And sv_toys*: a client hides the toys a server took away.
		var _toys := game.toy_rules.follow_cvars(link)
		var _roster := follow_roster(link, game.config)

	net = DotNetManager.new()
	net.name = "Net"
	net.is_server = false
	net.local_peer_id = multiplayer.get_unique_id() if multiplayer != null else 2
	net.auto_tick = false
	net.config_file = ""

	var net_config := DotNetConfig.new()
	net_config.tick_rate = game.tick_rate
	net_config.snapshot_rate = ZzGame.NET_SNAPSHOT_RATE
	net_config.enable_prediction = true
	net_config.enable_lag_compensation = false
	net_config.max_entities_per_snapshot = 256
	net_config.world_extent = ZzGame.NET_WORLD_EXTENT
	net.config = net_config
	add_child(net)

	var started := net.setup()

	if not started.ok:
		return started

	bridge = ZzNetBridge.new()
	bridge.name = "Bridge"
	add_child(bridge)

	var attached := bridge.attach(game, net)

	if not attached.ok:
		return attached

	bridge.open_link(link)
	# Before the seal and in the server's order (after the bridge), or the actions stay local.
	DotLog.result(CHANNEL, "avatar action message", DotGameAvatarActionMessage.register(net))
	net.messages.seal()

	bridge.hello_received.connect(_on_hello)
	bridge.roster_changed.connect(_on_roster_changed)
	bridge.phase_received.connect(_on_phase)
	bridge.round_changed.connect(_on_round)
	bridge.death_received.connect(_on_death)
	bridge.downed_received.connect(_on_down)
	bridge.revived_received.connect(_on_revive)
	bridge.rescued_received.connect(_on_rescue)
	bridge.defibbed_received.connect(_on_defib)
	bridge.armed_received.connect(_on_armed)
	bridge.ammo_received.connect(_on_ammo)
	bridge.map_received.connect(_on_map)
	bridge.pin_received.connect(func(session_id: int, npc_net_id: int, kind: StringName) -> void:
		_on_pin(session_id, bridge.zombie_mirror(npc_net_id), kind))
	bridge.unpin_received.connect(_on_unpin)
	bridge.box_received.connect(_on_box)
	bridge.bile_received.connect(_on_bile)
	bridge.objective_received.connect(_on_objective)
	bridge.effects_received.connect(func(rows: Array) -> void:
		if world_view != null:
			world_view.set_effects(rows)
		if hud != null:
			hud.set_effects(rows))
	bridge.hurt_received.connect(_on_hurt)
	bridge.hit_received.connect(_on_hit)
	bridge.splat_received.connect(func(point: Vector3, normal: Vector3) -> void:
		if blood != null:
			var _splat := blood.splat_at(point, normal))
	bridge.notice_received.connect(_on_notice)
	bridge.shop_received.connect(_on_shop_json)
	bridge.carry_received.connect(_on_carry_json)
	bridge.npc_added.connect(func(net_id: int, kind: StringName, variant: int, body: Node3D) -> void:
		_on_zombie(kind, true)
		world_view.add_zombie(net_id, kind, variant, body))
	bridge.npc_removed.connect(func(net_id: int, killed: bool, body: Node3D) -> void:
		_on_zombie(StringName(str(body.get(&"kind"))) if body != null else &"", false)
		world_view.remove_zombie(net_id, killed, body))
	bridge.loot_added.connect(func(id: int, kind: StringName, item: StringName, at: Vector3) -> void:
		world_view.add_loot(id, kind, item, at, _box_colours.get(item, Color(0.8, 0.6, 0.25))))
	bridge.loot_priced.connect(world_view.set_loot_price)
	bridge.loot_removed.connect(func(id: int, _by: int) -> void: world_view.remove_loot(id))
	bridge.loot_moved.connect(world_view.move_loot_many)
	bridge.hazard_added.connect(world_view.add_hazard)
	bridge.hazard_removed.connect(world_view.remove_hazard)
	bridge.turret_added.connect(world_view.add_turret)
	bridge.turret_fired.connect(world_view.fire_turret)
	bridge.turret_removed.connect(world_view.remove_turret)
	bridge.thrown.connect(world_view.throw)
	bridge.landed.connect(world_view.land)
	bridge.blast_received.connect(world_view.blast)
	bridge.weapon_used_by.connect(func(session_id: int, _times: int, kind: int) -> void:
		if session_id == _watch_id or audio == null:
			return
		var who: ZzPlayer = game.players.get(ZzNetBridge.player_key(session_id))
		if who != null:
			var _heard := audio.on_weapon(who.global_position, kind))

	if link != null and link.has_method("ping_ms"):
		bridge.rtt_source = func() -> float:
			return float(maxi(0, int(link.call("ping_ms"))))

	DotLog.result(CHANNEL, "chat and voice", chat.attach(bridge))

	if link != null and link.has_method("is_playing") and bool(link.call("is_playing")):
		_say_ready()
	elif link != null and link.has_signal("spawned"):
		link.connect("spawned", _say_ready, CONNECT_ONE_SHOT)

	return net.start()


func _say_ready() -> void:
	if bridge != null:
		bridge.ask_ready()


func _on_hello(session_id: int) -> void:
	_watch_id = session_id
	_adopt(game.players.get(ZzNetBridge.player_key(session_id)))


func _on_roster_changed(session_id: int) -> void:
	if session_id == _watch_id and player == null:
		_adopt(game.players.get(ZzNetBridge.player_key(session_id)))


func _adopt(candidate: ZzPlayer) -> void:
	if candidate == null or player == candidate:
		return

	player = candidate
	if gate != null:
		gate.freeze(player)
	_build_camera()
	if platform != null:
		_suspend_input(platform.is_input_blocked())

	# Offline the world samples this player's movement itself, so the buttons go onto that
	# sample (see `ZzPlayer.command_stamp`); connected, they go onto the command sent.
	if _offline:
		player.command_stamp = _stamp

	if settings != null:
		settings.bind_camera(self, &"base_fov")
		if player.sampler != null:
			settings.bind_look(player.sampler.tunables)

	if hud != null:
		hud.bind(game, player)
		hud.box_order = _box_order
		hud.box_titles = _box_titles
		hud.box_colours = _box_colours


func _toy_sound(id: StringName, at: Vector3, strength: float) -> void:
	if audio != null:
		var _played := audio.at(id, at, clampf(strength, 0.25, 1.0))


# --- What the world, or the server, says --------------------------------------

## Offline: the world is the authority, so its own signals are what happened. A connected
## client hears the same from the bridge and calls the same functions with the same arguments,
## so the two can only differ in where a fact came from.
func _hear_the_world() -> void:
	game.world_rebuilt.connect(func() -> void: _on_map(game.map.id()))
	game.phase_changed.connect(_on_phase)
	game.round_began.connect(func(n: int, _map: StringName) -> void: _on_round(n, true, false))
	game.round_over.connect(func(n: int, won: bool, why: String) -> void: _on_round(n, false, won, why))
	game.player_died.connect(func(id: StringName, by: StringName, why: StringName) -> void:
		_on_death(_session(id), _session_of_killer(by), why, _kind_of_killer(by)))
	game.player_downed.connect(func(id: StringName, by: StringName, why: StringName) -> void:
		_on_down(_session(id), _session_of_killer(by), why, _kind_of_killer(by)))
	game.player_revived.connect(func(id: StringName, by: StringName) -> void:
		_on_revive(_session(id), _session_of_killer(by)))
	game.player_rescued.connect(func(id: StringName) -> void: _on_rescue(_session(id)))
	game.player_biled.connect(func(id: StringName, seconds: float) -> void: _on_bile(_session(id), seconds))
	game.player_hurt.connect(func(id: StringName, amount: float, from: Vector3) -> void:
		if id == &"local":
			_on_hurt(amount, from))
	game.hit_landed.connect(func(id: StringName, victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
		if id == &"local":
			_on_hit(victim, amount, point, killed, headshot))
	game.notice.connect(_on_notice)
	game.map_ending.connect(_on_map_ending)
	game.told.connect(func(id: StringName, text: String) -> void:
		if id == &"local":
			_on_notice(text))
	if game.shop != null:
		game.shop_changed.connect(func() -> void: _on_shop_json(game.shop.state_json()))
	game.carry_changed.connect(func(id: StringName) -> void:
		if id == &"local" and hud != null and game.players.has(id):
			hud.set_carry(JSON.parse_string(game.carry.state_json(game.players[id])) as Dictionary))
	game.refused.connect(func(id: StringName, why: String) -> void:
		if id == &"local":
			_on_notice(why)
			if audio != null:
				var _denied := audio.deny())
	game.objective_changed.connect(func(index: int, state: StringName) -> void:
		_on_objective(index, {&"waiting": 0, &"holding": 1, &"done": 2}.get(state, 0)))
	game.player_armed.connect(func(id: StringName, weapon: StringName) -> void:
		if id == &"local":
			_on_armed(_watch_id, weapon)
		else:
			_hear_rig(game.players.get(id)))
	game.player_disarmed.connect(func(id: StringName) -> void:
		if id == &"local":
			_on_armed(_watch_id, &""))
	game.ammo_given.connect(func(id: StringName) -> void:
		if id == &"local":
			_on_ammo())
	game.exploded.connect(world_view.blast)

	if game.horde != null:
		game.horde.zombie_spawned.connect(func(npc: DotNpcInstance) -> void:
			_on_zombie(npc.def.id, true)
			var body := npc.node as ZzZombieBody
			world_view.add_zombie(npc.instance_id, npc.def.id, body.variant if body != null else 0, body))
		game.horde.zombie_removed.connect(func(npc: DotNpcInstance) -> void:
			_on_zombie(npc.def.id, false)
			world_view.remove_zombie(npc.instance_id, not npc.alive and npc.health <= 0.0))
		game.horde.mob_started.connect(func(_size: int) -> void:
			if audio != null:
				var _horde := audio.play(ZzAudio.HORDE))

	if game.pins != null:
		game.pins.pinned.connect(func(victim: StringName, kind: StringName, _attacker: int) -> void:
			var holder: DotNpcInstance = game.pins.holder_of(victim)
			_on_pin(_session(victim), holder.node if holder != null else null, kind))
		game.pins.released.connect(func(victim: StringName, _kind: StringName, why: StringName) -> void:
			_on_unpin(_session(victim), why))

	if game.hazards != null:
		game.hazards.area_added.connect(world_view.add_hazard)
		game.hazards.area_ended.connect(world_view.remove_hazard)
		game.hazards.launched.connect(world_view.throw)
		game.hazards.landed.connect(world_view.land)

	if game.turrets != null:
		game.turrets.placed.connect(world_view.add_turret)
		game.turrets.fired.connect(world_view.fire_turret)
		game.turrets.ended.connect(world_view.remove_turret)

	if game.loot != null:
		game.loot.added.connect(func(id: int, kind: StringName, item: StringName, at: Vector3) -> void:
			var seen := game.loot.shown(kind, item)
			world_view.add_loot(id, kind, seen, at, _box_colours.get(seen, Color(0.8, 0.6, 0.25)))
			world_view.set_loot_price(id, game.loot.price_of(id)))
		game.loot.removed.connect(func(id: int, _by: StringName) -> void: world_view.remove_loot(id))
		game.loot.moved_many.connect(world_view.move_loot_many)

	if game.boxes != null:
		game.boxes.opened.connect(func(id: StringName, type_id: StringName, title: String, message: String) -> void:
			_on_box(_session(id), type_id, title, message))
		game.boxes.effects_changed.connect(func() -> void:
			if world_view != null:
				world_view.set_effects(game.boxes.effects_summary())
			if hud != null:
				hud.set_effects(game.boxes.effects_summary()))


## The local world's ids are `local` for this keyboard and `u<session>` for everybody else.
func _session(id: StringName) -> int:
	return _watch_id if id == &"local" else ZzNetBridge.session_of(id)


func _session_of_killer(by: StringName) -> int:
	if by == &"local":
		return _watch_id
	return ZzNetBridge.session_of(by) if String(by).begins_with("u") else 0


func _kind_of_killer(by: StringName) -> StringName:
	return &"" if by == &"" or by == &"local" or String(by).begins_with("u") else by


func _player_of(session_id: int) -> ZzPlayer:
	if session_id == _watch_id and player != null:
		return player
	return game.players.get(ZzNetBridge.player_key(session_id))


func _name_of(session_id: int) -> String:
	var who := _player_of(session_id)
	return who.display_name if who != null else "somebody"


func _hear_rig(armed: ZzPlayer) -> void:
	if armed == null or audio == null or armed.weapons == null:
		return
	if armed.weapons.used.is_connected(_on_rig_used.bind(armed)):
		return
	armed.weapons.used.connect(_on_rig_used.bind(armed))


func _on_rig_used(outcome: DotWeaponOutcome, armed: ZzPlayer) -> void:
	if audio != null and is_instance_valid(armed):
		var _heard := audio.on_weapon(armed.global_position, ZeeWeaponNet.kind_number(outcome.kind))


func _on_notice(text: String) -> void:
	if text == "":
		return
	if hud != null:
		hud.shout(text, 3.0)
	if chat != null:
		chat.notice(text)


## A map's own ending slows the client's time for a moment and, with a camera point, takes the view there;
## the game's clock is the server's, so only what is drawn and heard slows.
func _on_map_ending(_won: bool, raw_scale: float, raw_seconds: float, raw_point: Variant) -> void:
	var sane := ZzEvents.sane_end(raw_scale, raw_seconds, raw_point)
	var time_scale: float = sane["time_scale"]
	var seconds: float = sane["seconds"]
	var camera_point: Variant = sane["camera"]
	var slow := time_scale < 1.0 and seconds > 0.0
	var real_seconds := minf(seconds * time_scale if slow else seconds, END_HOLD_MAX)
	if camera_point is Vector3 and game != null and game.end_camera_rules.is_on():
		begin_end_camera(camera_point, real_seconds if real_seconds > 0.0 else game.end_camera_rules.window)
	if not slow or (DisplayServer.get_name() == "headless" and not slowmo_in_headless):
		return
	reset_slowmo()
	_slowed = true
	Engine.time_scale = time_scale
	# Only the newest ending's timer may restore the clock: an older one would end this one early.
	var gen := _slow_gen
	var t := get_tree().create_timer(real_seconds, true, false, true)
	t.timeout.connect(func() -> void:
		if gen == _slow_gen:
			reset_slowmo())


## Gives the clock back to normal speed and drops any pending slow-motion timer.
func reset_slowmo() -> void:
	_slow_gen += 1
	if _slowed:
		Engine.time_scale = 1.0
		_slowed = false


## Starts the ending camera at [param point] for [param real_seconds] of unscaled time.
func begin_end_camera(point: Vector3, real_seconds: float) -> void:
	_end_point = point
	_end_left = maxf(real_seconds, 0.1)
	_end_elapsed = 0.0
	_end_active = true


## 0 on the survivor's own eyes, 1 on the map's ending camera.
func end_camera_weight() -> float:
	return _end_weight


## Where the ending camera stands and looks: [param point] seen from [param focus], circling it [param orbit_deg] degrees.
static func end_camera_pose(point: Vector3, focus: Vector3, orbit_deg: float) -> Transform3D:
	var offset := point - focus
	if offset.length() < 1.5:
		offset = Vector3(0.0, 1.0, 3.0)
	var at := focus + offset.rotated(Vector3.UP, deg_to_rad(orbit_deg))
	var pose := Transform3D(Basis.IDENTITY, at)
	return pose.looking_at(focus, Vector3.UP)


## Glides the view to the ending camera and back; a map without a point never gets here.
func _present_end_camera(delta: float, focus: Vector3) -> void:
	if not _end_active and _end_weight <= 0.0:
		return
	var real := delta / maxf(Engine.time_scale, 0.01)
	var rules := game.end_camera_rules
	var glide := maxf(rules.blend, 0.05)
	_end_elapsed += real
	_end_left -= real
	var goal := 1.0 if (_end_active and _end_left > 0.0 and rules.is_on()) else 0.0
	_end_weight = move_toward(_end_weight, goal, real / glide)
	if goal == 0.0:
		_end_active = false
	if _end_weight <= 0.0:
		return
	var smooth := smoothstep(0.0, 1.0, _end_weight)
	var target := end_camera_pose(_end_point, focus, rules.orbit * _end_elapsed)
	camera.global_transform = camera.global_transform.interpolate_with(target, smooth)


func _on_phase(phase: int) -> void:
	if hud == null:
		return

	if phase == ZzGame.Phase.PLAY:
		if game.effects != null:
			var _flashed := game.effects.flash(&"go")


func _on_map(map_id: StringName) -> void:
	if flash != null:
		flash.allowed = DotFlashlightRules.allowed_on(game.flashlight_conf(), str(map_id))
	reset_slowmo()
	_end_active = false
	_end_weight = 0.0
	if audio != null:
		audio.on_map_doc(map_id, game.map_doc)
		if game.map != null and not game.map.world_sounds.is_empty():
			audio.on_world_sounds(game.map.world_sounds)

	# The new map's toys are heard: a barrel's knock, a ball's bounce.
	if game.map != null and game.map.toys != null and not game.map.toys.sound.is_connected(_toy_sound):
		var _c := game.map.toys.sound.connect(_toy_sound)

	var name_of := str(game.map_doc.get("name", ""))
	world_view.clear()
	if blood != null:
		blood.clear()

	if hud != null:
		hud.shout(name_of, 3.0)

	if audio != null:
		var _started := audio.play(ZzAudio.MAP_START)

	if chat != null and name_of != "":
		var author := str(game.map_doc.get("author", ""))
		var blurb := str(game.map_doc.get("blurb", ""))
		chat.say_locally("%s%s%s" % [name_of, " by %s" % author if author != "" else "",
			" — %s" % blurb if blurb != "" else ""], Color(0.80, 0.90, 1.0))


func _on_round(number: int, began: bool, won: bool, why: String = "") -> void:
	if began:
		_brutes = 0
		_end_map_presentation()
		if audio != null:
			audio.music(&"")
		if hud != null:
			hud.shout("HOLD ON" if game.is_survival() else "MAKE FOR THE SHELTER", 3.0)
		return

	if audio != null:
		var _heard := audio.play(ZzAudio.MAP_WON if won else ZzAudio.MAP_LOST)
		audio.music(&"")

	if hud != null:
		hud.shout(("YOU MADE IT — %s" if won else "YOU DIED — %s") % why, 5.0)

	_begin_map_end(won, why)

	if chat != null and why != "":
		chat.say_locally(why, Color(0.98, 0.86, 0.40))


func _on_death(session_id: int, by: int, why: StringName, by_kind: StringName) -> void:
	var who := _player_of(session_id)
	var mine := session_id == _watch_id

	if killcam != null and who != null:
		killcam.note_moment(who.player_id, "fell to %s" % ("a " + String(by_kind) if by_kind != &"" else "the horde"), "THE LAST STAND")

	if audio != null and mine:
		var _heard := audio.play(ZzAudio.YOU_ARE_DEAD)

	if chat != null:
		chat.say_locally(_feed_line(_name_of(session_id), "died", by, why, by_kind, mine), Color(0.95, 0.5, 0.45))

	if who != null and world_view != null:
		world_view.unpin(who)

	_fall(who)


## [param who]'s body falls the way the server picked ([member ZzPlayer.death]), copied from the
## figure this client draws (a downed survivor's crawl included); the figure itself stays hidden
## while they are dead ([method ZzPlayer.present_body]). Nobody's figure, nothing: a
## first-person survivor never had one drawn here. Called from [method _on_death], solo and
## connected alike, before the next frame hides the figure.
func _fall(who: ZzPlayer) -> void:
	if who == null or world_view == null or who.figure == null or not who.figure.visible:
		return
	var velocity := who.controller.state.velocity if who.controller != null else Vector3.ZERO
	var _body := world_view.drop_survivor(who.figure, who.death, velocity)


func _on_down(session_id: int, by: int, why: StringName, by_kind: StringName) -> void:
	var who := _player_of(session_id)
	var mine := session_id == _watch_id

	# The hold is lost when nobody is up, so the last down is as decisive as the last death.
	if killcam != null and who != null:
		killcam.note_moment(who.player_id, "went down to %s" % ("a " + String(by_kind) if by_kind != &"" else "the horde"), "THE LAST STAND")

	if audio != null:
		if mine:
			var _down := audio.play(ZzAudio.YOU_ARE_DOWN)
		elif who != null:
			var _call := audio.at(ZzAudio.CALL_MEDIC, who.global_position)

	if mine and hud != null:
		hud.shout("YOU ARE DOWN", 2.0)

	if chat != null:
		chat.say_locally(_feed_line(_name_of(session_id), "is down", by, why, by_kind, mine), Color(0.98, 0.7, 0.4))


## One line of the feed. [param mine]: it is about the person reading it, whose name is
## "You" and whose verb agrees with it ("You are down", "You bled out"); the first play test
## read "You is down (strangler)". The killer's kind is said as a name ("a strangler").
static func feed_line(name_of: String, what: String, by_name: String, why: StringName, by_kind: StringName,
		mine: bool = false) -> String:
	var who := "You" if mine else name_of
	var verb := what
	if mine:
		verb = {"is down": "are down", "is back": "are back", "was picked up": "were picked up"}.get(what, what)
	if by_kind != &"":
		return "%s %s (%s)" % [who, verb, String(by_kind).replace("_", " ")]
	if by_name != "":
		return "%s %s (%s)" % [who, verb, by_name]
	if why == ZzGame.BY_FELL:
		return "%s fell" % who
	if why == ZzGame.BY_BLED:
		return "%s bled out" % who
	return "%s %s" % [who, verb]


func _feed_line(name_of: String, what: String, by: int, why: StringName, by_kind: StringName, mine: bool = false) -> String:
	return feed_line(name_of, what, _name_of(by) if by != 0 else "", why, by_kind, mine)


func _on_revive(session_id: int, by: int) -> void:
	if session_id == _watch_id and audio != null:
		var _up := audio.play(ZzAudio.YOU_ARE_UP)

	if chat != null:
		var mine := session_id == _watch_id
		chat.say_locally("%s%s" % [feed_line(_name_of(session_id), "was picked up", "", &"", &"", mine),
			" by %s" % _name_of(by) if by != 0 else ""], Color(0.6, 0.95, 0.6))


func _on_defib(session_id: int, by: int) -> void:
	var body := _player_of(session_id)

	if audio != null:
		var _zap := audio.at(ZzAudio.DEFIB_ZAP, body.feet() + Vector3(0.0, 0.3, 0.0)) if body != null else 0

		if session_id == _watch_id:
			var _up := audio.play(ZzAudio.YOU_ARE_UP)

	if chat != null:
		chat.say_locally("%s was shocked back by %s" % [_name_of(session_id), _name_of(by)], Color(0.6, 0.95, 0.6))


## The defibrillator under the camera in first person while it is being charged at a body.
func _present_defib_hands(delta: float) -> void:
	if defib_hands == null or not is_instance_valid(defib_hands) or defib_hands.get_parent() != camera:
		if defib_hands != null and is_instance_valid(defib_hands):
			defib_hands.queue_free()

		defib_hands = ZzDefibHands.new()
		defib_hands.name = "DefibHands"
		camera.add_child(defib_hands)

	var out := player.using == &"defib" and player.is_alive() and not third_person and not is_spectating()
	defib_hands.present(out, player.use_fraction, delta)

	if out and not _defib_sound and audio != null:
		var _charge := audio.play(ZzAudio.DEFIB_CHARGE)

	_defib_sound = out


func _on_rescue(session_id: int) -> void:
	if chat != null:
		chat.say_locally(feed_line(_name_of(session_id), "is back", "", &"", &"", session_id == _watch_id),
			Color(0.6, 0.95, 0.6))


func _on_pin(session_id: int, holder: Node3D, kind: StringName) -> void:
	var who := _player_of(session_id)

	if who != null and world_view != null:
		world_view.pin(who, holder, kind, session_id == _watch_id and not third_person)

	if session_id == _watch_id and hud != null:
		hud.shout({&"pounce": "POUNCED — SHOVE IT OFF", &"choke": "TONGUED — HELP!", &"carry": "CARRIED — HELP!",
			&"ride": "RIDDEN — HELP!", &"grab": "GRABBED — SHOOT IT!"}.get(kind, "HELD"), 2.0)


func _on_unpin(session_id: int, _why: StringName) -> void:
	var who := _player_of(session_id)

	if who != null and world_view != null:
		world_view.unpin(who)


func _on_box(session_id: int, type_id: StringName, title: String, message: String) -> void:
	var who := _player_of(session_id)

	if audio != null:
		if who != null:
			var _opened := audio.at(ZzAudio.BOX_OPEN, who.global_position) if session_id != _watch_id else 0
		if session_id == _watch_id:
			var _mine := audio.play(ZzAudio.BOX_OPEN)

	var box_title := str(type_id).capitalize()

	if hud != null:
		hud.box_banner(title, message, _box_colours.get(type_id, Color(0.8, 0.6, 0.25)))

	if chat != null:
		chat.say_locally("%s opened a box: %s%s" % [_name_of(session_id), title,
			" — %s" % message if message != "" else ""], _box_colours.get(type_id, Color(0.9, 0.8, 0.5)))
	var _unused := box_title


func _on_bile(session_id: int, _seconds: float) -> void:
	if session_id == _watch_id and game.effects != null:
		var _flash := game.effects.flash(&"bile")


func _on_objective(index: int, state: int) -> void:
	if audio != null:
		var _blip := audio.play(ZzAudio.OBJECTIVE)

	if state == 1 and audio != null:
		audio.music(ZzAudio.MUSIC_HORDE)
	elif state == 2 and audio != null and _brutes == 0:
		audio.music(&"")

	if hud != null and index >= 0 and index < (game.map_doc.get("objectives", []) as Array).size():
		var label := str(((game.map_doc["objectives"] as Array)[index] as Dictionary)["label"])
		hud.shout("%s: %s" % [label, "HOLD OUT" if state == 1 else "DONE"], 2.5)


func _on_hurt(amount: float, from: Vector3) -> void:
	if game.effects != null:
		var _flash := game.effects.flash(&"hurt")

	if audio != null:
		var _ouch := audio.play(ZzAudio.HURT)

	if hud != null and player != null:
		hud.hurt_from(from, amount)


## The player's blood setting trims what is drawn (dot-npc's DotNpcGore.view_cap): off keeps clean stumps only. What comes off is the server's rule.
func _apply_gore_pref() -> void:
	DotNpcGore.view_cap = DotNpcGore.MAX_LEVEL if settings.settings.get_bool(&"gore", true) else DotNpcGore.STUMPS


## A hit the server confirmed: the marker and the number on the body.
func _on_hit(victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
	if hud != null:
		hud.confirm_hit(victim, amount, point, killed, headshot)
	_draw_body_hit(weapons, point)
	if world_view != null and not killed:
		world_view.wound_near(point)
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if blood != null and camera != null:
		var _splat := blood.on_body_hit(victim, point, camera.global_position)


## The hit drawn on the body the server says was hit: zee's red burst at [param point], for a
## body the client's presentation ray never meets (a zombie is drawn as a figure and hit through the server's hitboxes). The rig's effects skip a second drawing
## of a hit the ray already drew. Through `has_method`: an older shell's zee has no
## `play_body_hit`.
func _draw_body_hit(rig: Object, point: Vector3) -> void:
	if rig == null or not is_instance_valid(rig) or not rig.has_method(&"shot_fx"):
		return
	var fx: Object = rig.call(&"shot_fx")
	if fx == null or not fx.has_method(&"play_body_hit"):
		return
	var from: Vector3 = point + Vector3.UP
	if player != null and is_instance_valid(player):
		from = player.global_position + Vector3(0.0, 1.6, 0.0)
	fx.call(&"play_body_hit", point, point - from)


func _on_zombie(kind: StringName, appeared: bool) -> void:
	if kind != ZzNpcs.BRUTE:
		return

	_brutes = maxi(_brutes + (1 if appeared else -1), 0)

	if audio != null:
		audio.music(ZzAudio.MUSIC_BRUTE if _brutes > 0 else &"")

	if appeared and hud != null:
		hud.shout("A BRUTE IS COMING", 3.0)


func _on_armed(session_id: int, weapon_id: StringName) -> void:
	if session_id != _watch_id:
		return

	_armed_told = true

	if weapon_id == &"":
		_strip_locally()
	else:
		_arm_locally(weapon_id)


func _on_ammo() -> void:
	if weapons != null and weapons.arsenal != null:
		for pool in weapons.arsenal.ammo().pools():
			var _filled := weapons.arsenal.add_ammo(pool, maxi(weapons.arsenal.ammo().cap(pool), 1))

	if audio != null:
		var _ding := audio.play(ZzAudio.PICKUP)


# --- The weapons, drawn ----------------------------------------------------

## Gives the local rig [param weapon_id], building it the first time. A gun is drawn; a melee
## weapon and something to throw are pocketed — what the server's `_draw` decides, mirrored.
func _arm_locally(weapon_id: StringName) -> void:
	if player == null:
		return

	if weapons == null:
		if camera == null:
			_build_camera()

		if camera == null:
			return

		view_model = ZeeViewModel.new()
		view_model.name = "ViewModel"
		camera.add_child(view_model)

		weapons = ZeeWeaponRig.new()
		weapons.name = "Weapons"
		weapons.role = ZeeWeaponRig.Role.LOCAL
		weapons.authority = false
		# Ticked once a physics frame (`_drive_view_model`), so timed by that rate: at the
		# server's 64 against a 60 Hz client every reload here ran 7% long, and the counter
		# sat empty after the server's gun had filled.
		weapons.tick_rate = Engine.physics_ticks_per_second
		weapons.view_model_ref = DotNodeRef.of_path(view_model.get_path())
		weapons.player_ref = DotNodeRef.of_path(player.get_path())
		weapons.ads_rules = game.ads_rules
		view_model.ads_rules = weapons.ads_rules
		player.add_child(weapons)

		var ready_now := weapons.setup()

		if not ready_now.ok:
			DotLog.warn(CHANNEL, "the view model would not set up", {"why": ready_now.error.message})
			_strip_locally()
			return

		weapons.used.connect(func(outcome: DotWeaponOutcome) -> void:
			if audio != null and camera != null:
				var _heard := audio.on_weapon(camera.global_position, ZeeWeaponNet.kind_number(outcome.kind)))

	player.view_rig = weapons
	_mirror.mirror = true
	var _moved := _mirror.sync(game.config)
	weapons.arsenal.carry = _mirror.carry
	game.combat_feel.attach(weapons.arsenal)

	if not weapons.give(weapon_id).ok:
		return

	var tier := ZzWeapons.tier_of(weapon_id)
	var def := weapons.arsenal.catalogue.get_def(weapon_id)

	if def != null and (_slot == 0 or (tier != &"melee" and tier != &"thrown")):
		_slot = def.slot

	if audio != null:
		var _ding := audio.play(ZzAudio.PICKUP)


## The server's word on what is carried: the HUD shows it, and a weapon this end never heard of is given.
func _on_carry_json(json: String) -> void:
	var state: Variant = JSON.parse_string(json)
	if not state is Dictionary:
		return
	if hud != null:
		hud.set_carry(state)
	var _moved := _mirror.sync(game.config)
	if player != null and player.controller != null:
		player.controller.set_weight_scale(float((state as Dictionary).get("scale", 1.0)))
		if player.controller.motor != null:
			var limit := maxf(float((state as Dictionary).get("l", 1.0)), 0.1)
			player.controller.motor.load_fraction = float((state as Dictionary).get("w", 0.0)) / limit if bool((state as Dictionary).get("on", false)) else 0.0
	if weapons == null or weapons.arsenal == null:
		return
	var slots: Dictionary = (state as Dictionary).get("slots", {})
	var told := {}
	for key in slots:
		for id: Variant in slots[key]:
			told[StringName(str(id))] = true
	var arsenal: DotWeaponArsenal = weapons.arsenal
	var dropped := false
	for slot: int in arsenal.slots():
		for held in arsenal.weapons_in(slot):
			dropped = dropped or not told.has(held.id())
	if dropped:
		# The server put something down (an over-limit drop, a swap): this end rebuilds to its list.
		for slot: int in arsenal.slots():
			while not arsenal.weapons_in(slot).is_empty() and arsenal.take(slot).ok:
				pass
		for key in slots:
			var ids: Array = (slots[key] as Array).duplicate()
			ids.reverse()
			for id: Variant in ids:
				var _back := arsenal.give(StringName(str(id)), false)
	for key in slots:
		for id: Variant in slots[key]:
			if not weapons.arsenal.carries(StringName(str(id))):
				var _given := weapons.arsenal.give(StringName(str(id)))


func _strip_locally() -> void:
	_slot = 0

	if weapons != null and weapons.arsenal != null:
		weapons.arsenal.clear()
		# The pools too: `clear` keeps them, and the next map's fresh pistol added its reserve to
		# what was left (15 / 105 against the server's 15 / 60).
		weapons.arsenal.ammo().clear()


# --- The camera ------------------------------------------------------------

func _build_camera() -> void:
	if camera != null or player == null:
		return

	camera = Camera3D.new()
	camera.name = "Eye"
	camera.fov = base_fov
	camera.current = true
	camera.far = 400.0

	# Survivors and stand-ins, handed over (their hulls are off while players pass through
	# each other), and zombies, found on their layer: hidden at the lens, faded in third
	# person between the camera and you. It rides the camera wherever the camera goes.
	_fade = DotCameraFade.new()
	_fade.name = "Fade"
	_fade.bodies_fn = _other_players
	if game.physics != null:
		_fade.collision_mask = game.physics.layer_mask(&"zombie")
	camera.add_child(_fade)

	if not game.view_rules.changed.is_connected(_on_view_rules_changed):
		game.view_rules.changed.connect(_on_view_rules_changed)
	third_person = game.view_rules.resolve(third_person)
	_place_camera()


func _place_camera() -> void:
	if camera == null or player == null:
		return

	if camera.get_parent() != null:
		camera.get_parent().remove_child(camera)

	if _arm != null and is_instance_valid(_arm):
		_arm.queue_free()
		_arm = null

	var eye := player.eye_position() - player.controller.state.position

	if not third_person:
		player.add_child(camera)
		_rig_height = eye.y
		camera.position = Vector3(0.0, eye.y, 0.0)
		camera.rotation = Vector3.ZERO

		if view_model != null and is_instance_valid(view_model):
			view_model.visible = true

		if _fade != null:
			_fade.focus = null

		return

	# dot-core's boom, swept from the eye with the height above it added in the world's up:
	# a pivot raised above the head can itself be inside a beam, and the spring arm it
	# replaced cast a ray from there and snapped to whatever it hit.
	_arm = DotCameraBoom.new()
	_arm.name = "Chase"
	_arm.spring_length = CHASE_BACK
	_arm.collision_mask = game.world_mask()
	_arm.add_excluded_object(player.get_rid())
	_arm.margin = 0.15
	_arm.lift = CHASE_UP
	_rig_height = eye.y
	player.add_child(_arm)
	_arm.add_child(camera)
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO

	if _fade != null:
		_fade.focus = _arm

	if view_model != null and is_instance_valid(view_model):
		view_model.visible = false


## Swaps the view, where the server's `mp_forceview` allows.
func toggle_view() -> void:
	var wanted := game.view_rules.toggled(third_person)
	if wanted == third_person:
		if hud != null and game.view_rules.refusal() != "":
			hud.shout(game.view_rules.refusal(), 1.6)
		return
	third_person = wanted
	_place_camera()

	if audio != null:
		var _heard := audio.click()


## Everybody but this player, for the camera fade.
func _other_players() -> Array:
	var out: Array = []
	if game == null:
		return out
	for id in game.players:
		var other: Node3D = game.players[id]
		if other != player and is_instance_valid(other):
			out.append(other)
	return out


## The server changed `mp_forceview`: the view it allows now.
func _on_view_rules_changed() -> void:
	var allowed := game.view_rules.resolve(third_person)
	if allowed != third_person:
		third_person = allowed
		if not is_spectating():
			_place_camera()


func _build_hud() -> void:
	hud = ZzHud.new()
	hud.name = "Hud"
	hud.key_fn = _key
	add_child(hud)
	_shop_menu = ZzShopMenu.new()
	_shop_menu.buy_requested.connect(_shop_buy)
	hud.add_child(_shop_menu)


## The server's `zz_team_roster`: whether the HUD draws the team-mate list, read now and on
## every change. An older shell's link cannot say, and the config's default (off) stands.
static func follow_roster(source: Object, config: ZzConfig) -> bool:
	if source == null or not source.has_method(&"replicated_cvar") or not source.has_signal(&"replicated_cvar_changed"):
		return false
	var held := String(source.call(&"replicated_cvar", "zz_team_roster", ""))
	if held != "":
		config.team_roster = held.strip_edges() == "1"
	for name: String in FADE_CVARS:
		var fade_held := String(source.call(&"replicated_cvar", name, ""))
		if fade_held != "":
			_set_fade_cvar(config, name, fade_held)
	source.connect(&"replicated_cvar_changed", func(cvar_name: String, value: String) -> void:
		if cvar_name == "zz_team_roster":
			config.team_roster = value.strip_edges() == "1"
		elif FADE_CVARS.has(cvar_name):
			_set_fade_cvar(config, cvar_name, value))
	return true


const FADE_CVARS: Array[String] = ["zz_mutant_fade", "zz_mutant_min_alpha", "zz_mutant_fade_per_stack", "zz_common_fade"]


static func _set_fade_cvar(config: ZzConfig, cvar_name: String, value: String) -> void:
	var text := value.strip_edges()

	if text.is_valid_float():
		config.set(StringName(cvar_name.trim_prefix("zz_")), text.to_int() if cvar_name.ends_with("_fade") else text.to_float())


## The key an action is on, as the player has it bound.
func _key(action: StringName) -> String:
	if settings != null and settings.bindings != null:
		var text := settings.bindings.key_for(action)
		if text != "":
			return text

	var row := ZzBindings.make().row_for_action(action)
	return str(row.get("default", action))


# --- The Tab board ---------------------------------------------------------

## The Tab board: dot-menu's, with this game's columns. The platform feeds it and holds it on Tab.
func _dress_board() -> void:
	if board == null:
		return

	board.title_text = "Zombie Zone"
	board.columns = [
		{"key": &"avatar", "kind": DotMenuScoreboard.KIND_AVATAR, "width": 0.0},
		{"key": &"name", "title": "Survivor", "width": 3.0},
		{"key": &"health", "title": "Health", "kind": DotMenuScoreboard.KIND_TEXT},
		{"key": &"downs", "title": "Downs left", "kind": DotMenuScoreboard.KIND_TEXT},
		{"key": &"kills", "title": "Kills", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"specials", "title": "Specials", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"points", "title": "Points", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"ping", "title": "Ping", "kind": DotMenuScoreboard.KIND_PING},
	]
	board.sort_by = &"points"
	board.decorate = _decorate_row
	board.prepare = _prepare_board


func _decorate_row(row: Dictionary) -> void:
	if game == null:
		return
	var id := ZzNetBridge.player_key(int(row.get("id", 0)))
	if not game.players.has(id):
		id = StringName(str(row.get("id", "")))
	var who: ZzPlayer = game.players.get(id)
	if who == null:
		return
	row["avatar"] = _face(who)
	row["points"] = who.points
	row["kills"] = who.commons_killed
	row["specials"] = who.specials_killed
	row["team"] = ZzGame.SURVIVORS
	row["health"] = health_text(who)
	row["downs"] = downs_text(who, game.config.max_incaps)
	if int(row.get("ping", -1)) < 0 and who.ping_ms >= 0:
		row["ping"] = who.ping_ms
	if who == player:
		row["you"] = true


## A survivor's state for the Tab board, so the team's health is there with the HUD list off.
static func health_text(who: ZzPlayer) -> String:
	if who.watching or not who.is_alive():
		return "dead"
	if who.is_pinned():
		return "HELD (%s)" % String(who.pin_kind)
	if who.is_down():
		return "DOWN"
	if who.health != null:
		return "%d" % int(ceilf(who.health.health))
	return "-"


## Downs left before the next one is death.
static func downs_text(who: ZzPlayer, max_incaps: int) -> String:
	if who.watching or not who.is_alive():
		return "-"
	var left := max_incaps - who.incaps
	return "last life" if left <= 0 else str(left)


func _prepare_board(snap: Dictionary) -> void:
	if game == null:
		return
	snap["header"] = {"Map": str(game.map_doc.get("name", "")), "Difficulty": game.config.difficulty_name().capitalize()}
	if game.map != null and game.map.world_credits != "":
		snap["header"]["Credits"] = game.map.world_credits
	var pack_credits := preload("zz_packs.gd").credit_lines()
	if not pack_credits.is_empty():
		snap["header"]["Models"] = " | ".join(pack_credits)
	snap["teams"] = [{"id": ZzGame.SURVIVORS, "name": "Survivors", "color": game.side_colour(ZzGame.SURVIVORS)}]


## The board offline: every survivor in the local world. Public so a suite can read it.
func board_snapshot() -> Dictionary:
	var rows: Array = []
	if game != null:
		for id in game.players:
			var who: ZzPlayer = game.players[id]
			rows.append({"id": String(id), "name": who.display_name, "seconds": _seconds_here(), "ping": -1, "bot": who.is_bot})
	return {"server": {"name": "Zombie Zone", "game": "offline"}, "players": rows}


func _seconds_here() -> int:
	return int((Time.get_ticks_msec() - _started_msec) / 1000)


var _portraits: Dictionary = {}


func _face(who: ZzPlayer) -> Texture2D:
	return _portrait(str(who.call("_atlas")))


func _portrait(atlas: String) -> Texture2D:
	if _portraits.has(atlas):
		return _portraits[atlas]

	var view := SubViewport.new()
	view.name = "Portrait%d" % _portraits.size()
	view.size = Vector2i(64, 64)
	view.own_world_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(view)

	var figure := ZzFigure.new()
	view.add_child(figure)
	figure.build(1.8, atlas, Color.WHITE)
	figure.global_position = Vector3.ZERO

	var eye := Camera3D.new()
	eye.fov = 30.0
	view.add_child(eye)
	# The people's heads are big: the face is about 1.35 m up a 1.8 m person.
	eye.look_at_from_position(Vector3(0.0, 1.45, -2.0), Vector3(0.0, 1.35, 0.0), Vector3.UP)
	eye.current = true

	var texture := view.get_texture()
	_portraits[atlas] = texture
	return texture


# --- The end of a map: killcam, winner reveal, board ---------------------------

func _build_killcam() -> void:
	killcam = ZzKillcam.new()
	killcam.name = "MapKillcam"
	killcam.players_fn = func() -> Array: return game.players.values() if game != null else []
	killcam.player_for_fn = func(key: StringName) -> Variant: return game.players.get(key) if game != null else null
	killcam.feet_fn = func(p: ZzPlayer) -> Vector3: return drawn_position(p, net != null and net.is_running() and p != player)
	killcam.colour_fn = func(_p: ZzPlayer) -> Color: return game.side_colour(ZzGame.SURVIVORS)
	killcam.seconds_fn = func() -> float: return _killcam_sec if _killcam_sec >= 0.0 else game.config.killcam_seconds
	killcam.over.connect(func(_skipped: bool) -> void: _reveal_map())
	add_child(killcam)
	winner_reveal = DotWinnerReveal.new()
	winner_reveal.name = "WinnerReveal"
	winner_reveal.skip_actions = ZzKillcam.SKIP_ACTIONS
	winner_reveal.hold_seconds = 4.0
	winner_reveal.finished.connect(_on_reveal_finished)
	add_child(winner_reveal)


## `mp_killcam_time`, from the server's replicated cvar.
func _on_killcam_cvar(cvar_name: String, value: String) -> void:
	if cvar_name == "mp_killcam_time" and value.strip_edges().is_valid_float():
		_killcam_sec = clampf(value.to_float(), 0.0, 30.0)


## The HUD and the chat window: hidden while the replay or the reveal owns the screen.
func _screen_furniture() -> Array:
	return [hud, chat.window if chat != null else null]


func _begin_map_end(won: bool, why: String) -> void:
	_map_won = won
	_map_why = why
	_map_ending = true

	if killcam == null:
		return

	# A won map ends on the last survivor standing in the hold, seen through their own eyes.
	if won:
		var holder: ZzPlayer = player if player != null and player.is_alive() else null

		if holder == null:
			for key: StringName in game.players:
				if game.players[key].is_alive():
					holder = game.players[key]
					break

		if holder != null:
			killcam.note_moment(holder.player_id, "held on" if game.is_survival() else "made it to the shelter",
				"THE LAST WAVE" if game.is_survival() else "THE SHELTER")

	killcam.hide_while_playing = _screen_furniture()

	if not killcam.map_ended():
		return

	DotLog.debug(CHANNEL, "the reveal waits for the killcam")


## The survivors by points on a podium, after the killcam and before the board.
func _reveal_map() -> void:
	if not _map_ending:
		return

	var rows: Array = game.players.values()
	rows.sort_custom(func(a: ZzPlayer, b: ZzPlayer) -> bool: return a.points > b.points)
	var entries: Array = []

	for who: ZzPlayer in rows.slice(0, 3):
		entries.append({"name": who.display_name, "score": "%d %s" % [who.points, "point" if who.points == 1 else "points"],
			"colour": game.side_colour(ZzGame.SURVIVORS)})

	winner_reveal.reduced_motion = settings != null and settings.settings != null and settings.settings.get_bool(&"reduce_motion", false)
	var shown := winner_reveal.present(entries, {"title": "SURVIVORS WON" if _map_won else "INFECTED WON",
		"subtitle": _map_why.substr(0, 1).to_upper() + _map_why.substr(1) if _map_why != "" else "Map over", "hint": "Jump to skip"})

	if not shown.ok:
		_open_map_board()
		return

	for n: Variant in _screen_furniture():
		if n is Object and is_instance_valid(n) and (n as Object).get(&"visible") != null:
			_covered_by_reveal[n] = bool((n as Object).get(&"visible"))
			(n as Object).set(&"visible", false)


func _restore_furniture() -> void:
	for n: Variant in _covered_by_reveal:
		if is_instance_valid(n):
			(n as Object).set(&"visible", _covered_by_reveal[n])
	_covered_by_reveal.clear()


func _on_reveal_finished(_skipped: bool) -> void:
	_restore_furniture()

	if _map_ending:
		_open_map_board()


func _open_map_board() -> void:
	if board != null and not board.is_open():
		board.open()
		_board_opened = true


## A new map: whatever is still up goes, so it never covers the start, and the old frames go.
func _end_map_presentation() -> void:
	_map_ending = false

	if killcam != null:
		killcam.skip()
		killcam.reset()

	if winner_reveal != null:
		winner_reveal.skip()

	_restore_furniture()

	if _board_opened and board != null:
		board.close()

	_board_opened = false


# --- Chat, sound, settings ---------------------------------------------------

func _build_chat() -> void:
	chat = DotGameChatClient.new()
	chat.name = "Chat"
	chat.channels = [
		{"id": ZzServices.CH_ALL, "label": "All", "colour": Color(0.93, 0.94, 0.96)},
		{"id": ZzServices.CH_TEAM, "label": "Team", "colour": Color(0.55, 0.82, 0.95)},
		{"id": ZzServices.CH_NEAR, "label": "Near", "colour": Color(0.82, 0.86, 0.72)},
	]
	chat.max_length = ZzServices.chat_rules().max_length
	chat.voice_config = ZzServices.voice_format()
	add_child(chat)


func _build_audio() -> void:
	audio = ZzAudio.new()
	audio.name = "Sound"
	add_child(audio)

	var ready_now := audio.setup()

	if not ready_now.ok:
		DotLog.warn(CHANNEL, "no sound", {"why": ready_now.error.message})
		remove_child(audio)
		audio.queue_free()
		audio = null


func _build_settings() -> void:
	settings = ZzSettings.new()
	add_child(settings)
	platform.settings = settings
	# The HUD is a CanvasLayer and the platform's is a Control, so it follows the menu itself.
	platform.chat = chat
	platform.look_position_fn = _look_position
	platform.board_snapshot_fn = board_snapshot
	# M: the map list. Solo a choice changes the map here at once; connected the server decides,
	# by the owner's `sv_map_menu_flag`, and anybody without it gets a vote instead (dot-vote's
	# map menu, wired in [ZzModule]).
	platform.maps_rows_fn = func() -> Array: return game.map_rows() if game != null else []
	platform.maps_change_fn = func(id: StringName) -> DotResult: return game.change_map_now(id)
	DotLog.result(CHANNEL, "the platform", platform.setup())
	# The starter set: the equipped list needs a credential the client does not hold (the server reads it).
	DotLog.result(CHANNEL, "avatar actions", platform.add_avatar_actions(net, _avatar_figure))
	_add_noblock_and_workbench()
	# Walking is off while the cover is up, a menu is open or a line is typed.
	platform.input_blocked_changed.connect(_suspend_input)
	_suspend_input(platform.is_input_blocked())

	settings = platform.settings as ZzSettings
	console = platform.console as DotConsoleController

	if settings == null:
		return

	if blood != null:
		blood.follow(settings.settings)

	if world_view != null:
		world_view.lod.follow(settings.settings)

	_apply_gore_pref()

	settings.settings.changed.connect(func(key: StringName, _value: Variant, _why: StringName) -> void:
		if key == &"gore":
			_apply_gore_pref()
		if key == &"vis_mode" and game != null and game.map != null:
			game.map.set_vis_mode(_vis_mode())
			var _mode := platform.set_vis_mode(_vis_mode()))

	if _sampler != null:
		settings.bind_look(_sampler.tunables)

	if audio != null:
		settings.bind_audio(audio.manager)
		audio.follow_settings(settings.settings, game.ambient_rules)

	if settings.menu != null:
		# The HUD in the menu's theme and at the player's HUD size, live.
		if hud != null:
			hud.follow_menu(settings.menu)
		_bind_bot_console()
		_bind_crosshair_console()
		board = platform.board as DotMenuScoreboard
		_dress_board()


## The player's `cl_crosshair_*` cvars at the console's local source.
func _bind_crosshair_console() -> void:
	if console != null and hud != null:
		var _bound := game.combat_feel.bind_console(console, hud.crosshair())


## Solo, `bot_difficulty` and every `bot_*` setting at the console, the names a server has.
## Connected, the server's console holds them and a local copy would shadow it.
func _bind_bot_console() -> void:
	if not _offline or console == null or game == null:
		return
	var sources: Array = console.sources()
	if sources.is_empty() or not (sources[0] is DotConsoleLocal):
		return
	var _bound := DotBotSettings.of(game).bind_console(sources[0])
	var args := OS.get_cmdline_user_args()
	var index := args.find("--bot_difficulty")
	if index >= 0 and index + 1 < args.size():
		DotLog.result(CHANNEL, "bot difficulty from the command line", DotBotSettings.of(game).set_difficulty(args[index + 1]))


func _suspend_input(suspended: bool) -> void:
	# The button's release goes to the menu, so the aim is let go here or it sticks up.
	if suspended:
		_aiming = false

	if _sampler != null:
		_sampler.suspended = suspended

	if player != null and player.sampler != null:
		player.sampler.suspended = suspended


## Whether the pointer is the game's: captured. A menu frees it and the platform takes it back.
## Set by a headless suite, which has no pointer to capture.
var pointer_forced := false


func _pointer_ours() -> bool:
	return pointer_forced or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## The light on the eye follows the server's state (but not for 0.4 s after our own switch, which is shown at once), and everyone else's beams follow theirs.
func _present_flashlights() -> void:
	var cfg := game.flashlight_conf()

	if flash == null or not is_instance_valid(flash):
		flash = DotFlashlight.new()
		flash.name = "Flashlight"
		flash.config = cfg
		flash.handle_input = false
		flash.authoritative = false
		flash.allowed = DotFlashlightRules.allowed_on(cfg, str(game.map_doc.get("id", "")))
		flash.switch_requested.connect(func(_want: bool) -> void:
			_flash_ticks = 3
			_flash_msec = Time.get_ticks_msec())
		camera.add_child(flash)

	if flash.get_parent() != camera:
		flash.reparent(camera, false)

	if Time.get_ticks_msec() - _flash_msec > 400:
		flash.apply_state({"on": player.flashlight and player.is_alive()})

	if flash_crowd == null:
		flash_crowd = DotFlashlightCrowd.new()
		flash_crowd.name = "Flashlights"
		flash_crowd.config = cfg
		add_child(flash_crowd)

	flash_crowd.set_viewer(camera.global_position)

	for key: Variant in game.players:
		var other: ZzPlayer = game.players[key]
		flash_crowd.set_lit(key, other != player and other.flashlight and other.is_alive())
		flash_crowd.place(key, other.eye_position(), other.aim_direction())

	flash_crowd.retain(game.players.keys())


## The hands' bits for this tick, from the held keys.
func _actions() -> int:
	var out := 0
	if _using:
		out |= ZzNetCommand.ACT_USE
	if _healing:
		out |= ZzNetCommand.ACT_HEAL
	if _pills:
		out |= ZzNetCommand.ACT_PILLS
	if _flash_ticks > 0:
		_flash_ticks -= 1
		out |= ZzNetCommand.ACT_FLASHLIGHT
	if _cycle_ticks > 0:
		_cycle_ticks -= 1
		out |= ZzNetCommand.ACT_CYCLE
	if _box_key:
		out |= ZzNetCommand.ACT_BOX
	if _aim_sent():
		out |= ZzNetCommand.ACT_AIM
	return out


# --- The frame -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _offline:
		_drive_offline()
		return

	if net == null or not net.is_running() or bridge == null:
		return

	# The clock advances; only the sampling waits, so the mouse does not pile up a turn behind
	# the cover and the server sees an idle body until it lifts.
	var ticks := net.clock.advance(delta)

	if _covered():
		return

	var move := _sampler.sample(delta) if _sampler != null else DotFpsCommand.new()
	_stamp(move)

	for i in range(ticks):
		if not net.clock.is_synced():
			continue

		bridge.client_tick(net.clock.input_tick() - (ticks - 1 - i), move, _slot, _actions())

	_drive_view_model(move)


func _drive_offline() -> void:
	if player == null or player.sampler == null or _covered():
		return

	var pending := player.controller.current_command

	if pending != null:
		player.wanted_slot = _slot
		player.actions = _actions()
		player.shove_held = _shoving

	_drive_view_model(pending)

	# The world's rig is the truth offline; the drawn one catches up with it the same way a
	# connected client's catches up with the server's snapshot.
	var truth := player.weapons

	if truth != null and truth.arsenal != null and truth.arsenal.current() != null:
		var held := truth.arsenal.current()
		var _corrected := player.correct_view_rig(held.magazine,
			truth.arsenal.ammo().count(held.def.ammo_type) if held.def.ammo_type != &"" else 0,
			truth.arsenal.current_slot(), truth.arsenal.is_reloading() or truth.arsenal.is_switching())


func _stamp(command: DotFpsCommand) -> void:
	if command == null:
		return

	command.set_button(ZzNetCommand.BUTTON_FIRE, _firing)
	command.set_button(ZzNetCommand.BUTTON_SHOVE, _shoving)
	command.set_button(ZzNetCommand.BUTTON_RELOAD, _reloading)


## One tick of the gun you see, from the same buttons the server's gun is given this tick.
func _drive_view_model(_command: DotFpsCommand) -> void:
	if weapons == null or player == null:
		return

	var _outcome := player.drive_view_rig(_firing, _reloading, _slot,
		game.round_number * 100000 + Engine.get_physics_frames(), 1.0 / float(maxi(Engine.physics_ticks_per_second, 1)),
		_aim_sent())


func _process(delta: float) -> void:
	var _shown := present_frame(net, game, player, not third_person, delta, -1.0, _watched_through_eyes())

	if killcam != null and game != null:
		killcam.frame()

	if camera == null or player == null:
		return

	_present_flashlights()

	if world_view != null:
		world_view.present(delta, camera.global_position)

	_follow_daylight(delta)
	_present_water()
	_present_aim()

	if _drive_spectator_camera(delta):
		_present_effects(delta)
		return

	var state := player.controller.state
	var pitch := deg_to_rad(state.pitch)
	var yaw := deg_to_rad(state.yaw)
	var rig: Node3D = _arm if _arm != null and is_instance_valid(_arm) else camera

	if weapons != null:
		var punch := weapons.view_punch()
		pitch += deg_to_rad(punch.x)
		yaw += deg_to_rad(punch.y)

	# Down, the view tips over a little and drops to the floor.
	var roll := deg_to_rad(12.0) if player.is_down() else 0.0
	rig.rotation = Vector3(pitch, yaw, roll)

	var drawn := player.controller.render_state()
	# Follows the crouch: the height taken when the camera was placed is the standing one.
	_rig_height = player.eye_position().y - state.position.y
	var height := ZzPlayer.EYE_DOWN if player.is_down() else _rig_height
	rig.global_position = drawn.position + Vector3(0.0, height, 0.0)
	_present_end_camera(delta, drawn.position + Vector3(0.0, _rig_height, 0.0))

	if weapons != null:
		var speed := Vector2(state.velocity.x, state.velocity.z).length()
		weapons.drive_view(Vector2(state.yaw, state.pitch), speed, state.mode != DotFpsState.Mode.AIR, state.crouch_fraction > 0.5)

	if view_model != null and is_instance_valid(view_model):
		view_model.visible = not third_person and not player.is_held() and _end_weight < 0.3

	_present_defib_hands(delta)

	_present_box_hands(delta)

	if hud != null:
		var prompt := _prompt()
		if prompt == "" and _near_trader() and not (_shop_menu != null and _shop_menu.is_open()):
			prompt = "%s — trade" % _key(ZzBindings.USE)
		hud.set_prompt(prompt)
		_follow_shop_menu()

	_present_effects(delta)


## The box in the hands, drawn under the camera in first person while one is out.
func _present_box_hands(delta: float) -> void:
	if box_hands == null or not is_instance_valid(box_hands) or box_hands.get_parent() != camera:
		if box_hands != null and is_instance_valid(box_hands):
			box_hands.queue_free()

		box_hands = ZzBoxHands.new()
		box_hands.name = "BoxHands"
		camera.add_child(box_hands)

	var out := player.box_out and player.carried_count > 0 and player.is_alive() and not third_person \
		and not player.is_down() and not is_spectating()
	box_hands.present(out, player.use_fraction if player.using == &"deploy" else 0.0, carried_colour(player), delta)


## The colour of the box [param who] carries: its type's when the server tells it, a crate's own otherwise.
func carried_colour(who: ZzPlayer) -> Color:
	if who.carried_index > 0 and who.carried_index <= _box_order.size():
		return _box_colours.get(_box_order[who.carried_index - 1], ZzBoxHands.DEFAULT_COLOUR)

	return ZzBoxHands.DEFAULT_COLOUR


## Down the sights: the hands come up while the Aim key is held, the lens zooms by what the
## Whether the Aim key counts: nobody aims with the pointer free, in third person, held, down,
## dead or watching.
func _aim_allowed() -> bool:
	return _pointer_ours() and not third_person and not is_spectating() \
		and player != null and player.is_alive() and not player.is_down() and not player.is_held()


## What the command says about the sights: the view model's own state, so a toggle in the rules
## reaches the server's spread and pace as it does the picture.
func _aim_sent() -> bool:
	var hands := view_model if view_model != null and is_instance_valid(view_model) else null
	return _aim_allowed() and (hands.is_aim_held() if hands != null else _aiming)


## weapon's art says (`aim_fov_scale`, from [member base_fov] so nothing compounds), and the HUD
## fades its dot and shows a scope. Nobody aims down, held, dead, watching, in third person or
## with the pointer free. Presentation only, as in the arena: the server's shot ignores it.
func _present_aim() -> void:
	var hands := view_model if view_model != null and is_instance_valid(view_model) else null
	if hands != null:
		hands.aim_input(_aiming and _aim_allowed())
	camera.fov = base_fov * (hands.aim_fov_scale() if hands != null and not is_spectating() else 1.0)
	if hud != null:
		hud.set_aim(hands.aim_fraction() if hands != null else 0.0, hands != null and hands.is_scoped())
		if weapons != null and weapons.arsenal != null:
			hud.set_spread(weapons.arsenal.spread_now(), camera.fov)


## What E would do now, for the HUD: who you would revive, what you would pick up.
## The light of a map held by nights, eased toward what the hold says (it ramps through dawn
## and dusk itself; this only smooths the half-second steps a client is told it in).
## What water does to the screen and the ears, presentation only: the map's murk when the CAMERA
## (a third-person or spectator one included) is inside a volume, a splash as the local survivor
## goes in or climbs out past the waist, and the effects muffled under the surface.
func _present_water() -> void:
	if game == null or game.map == null:
		return

	var under := false

	if game.water_rules.is_on():
		for box in game.map.water_boxes:
			if box.has_point(camera.global_position):
				under = true
				break

	game.map.set_underwater(under)
	_muffle(under)
	var level: int = player.water_level if player != null else 0
	var swimming := level >= ZzPlayer.WaterLevel.WAIST
	var was := _last_water_level >= ZzPlayer.WaterLevel.WAIST

	if swimming != was and audio != null:
		var _splash := audio.at(ZzAudio.SPLAT, player.global_position, 0.7)

	_last_water_level = level


## A low-pass on the SFX bus while the camera is under water; added once, taken off on the way out.
func _muffle(under: bool) -> void:
	var bus := AudioServer.get_bus_index(&"SFX")

	if bus < 0:
		return

	if under and _muffler_slot < 0:
		var filter := AudioEffectLowPassFilter.new()
		filter.cutoff_hz = 900.0
		AudioServer.add_bus_effect(bus, filter)
		_muffler_slot = AudioServer.get_bus_effect_count(bus) - 1
	elif not under and _muffler_slot >= 0:
		AudioServer.remove_bus_effect(bus, _muffler_slot)
		_muffler_slot = -1


func _follow_daylight(delta: float) -> void:
	if game == null or game.map == null:
		return

	var hold: Dictionary = game.survival_state()
	var wanted := maxf(float(hold.get("daylight", -1.0)), 0.0) if not hold.is_empty() else 0.0
	var now_light: float = game.map.daylight()

	if is_equal_approx(now_light, wanted):
		return

	game.map.set_daylight(move_toward(now_light, wanted, delta * 0.35))


func _on_shop_json(json: String) -> void:
	var parsed: Variant = JSON.parse_string(json)
	shop_state = parsed as Dictionary if parsed is Dictionary else {}
	_follow_shop_menu()


## Whether the local survivor stands within reach of an open trader.
func _near_trader(only_open := true) -> bool:
	if player == null or not player.can_act() or not bool(shop_state.get("menu", false)) or (only_open and not bool(shop_state.get("open", false))):
		return false
	var feet := player.feet()
	for at: Variant in shop_state.get("at", []):
		var a := at as Array
		if a.size() == 3 and feet.distance_to(Vector3(float(a[0]), float(a[1]), float(a[2]))) <= float(shop_state.get("radius", 3.5)):
			return true
	return false


func is_shop_open() -> bool:
	return _shop_menu != null and _shop_menu.is_open()


func open_shop() -> void:
	if _shop_menu == null or not _near_trader():
		return
	_using = false
	_firing = false
	_aiming = false
	_suspend_input(true)
	platform.hold_pointer(&"shop")
	_chat_shown(false)
	_shop_menu.open(shop_state.get("items", []), player.points, _shop_item_state)


## The chat log is its own layer above the HUD and wrote over the menu's lower cards.
func _chat_shown(shown: bool) -> void:
	if chat != null and chat.window != null:
		chat.window.visible = shown


func close_shop() -> void:
	if not is_shop_open():
		return
	_shop_menu.close()
	_chat_shown(true)
	_suspend_input(false)
	platform.release_pointer(&"shop")


## Closes the menu when its trader goes or its customer leaves; keeps its balance and states current while it is up.
func _follow_shop_menu() -> void:
	if not is_shop_open():
		return
	if not _near_trader():
		if not bool(shop_state.get("open", false)) and str(shop_state.get("closed_message", "")) != "":
			game.notice.emit(str(shop_state["closed_message"]))
		close_shop()
		return
	_shop_menu.refresh(shop_state.get("items", []), player.points)


## "" when [param item] can be bought, else why not (Owned, Full).
func _shop_item_state(item: Dictionary) -> String:
	var rig: Variant = player.view_rig if player != null and player.view_rig != null else (player.weapons if player != null else null)
	var arsenal: Variant = rig.arsenal if rig != null else null
	var id := str(item.get("id", ""))
	var weapon := StringName(str(item.get("w", "")))
	var def := ZzWeapons.def_of(weapon) if weapon != &"" else null
	if id == "medkit":
		return "Carrying" if player.medkits >= 1 else ""
	if id == "pills":
		return "Carrying" if player.pills >= 1 else ""
	if id == "heal":
		return "Full" if player.health != null and player.health.health >= player.health.max_health else ""
	if id == "armour":
		return "Full" if player.health != null and player.health.armour >= player.health.max_armour else ""
	if id.begins_with("box:"):
		return "Hands full" if player.carried.size() >= game.config.box_carry else ""
	if def == null or arsenal == null:
		return ""
	var owned: bool = arsenal.carries(weapon)
	if id.begins_with("mag:") or id.begins_with("refill:"):
		if not owned:
			return "Not carried"
		return "Full" if arsenal.ammo().count(def.ammo_type) >= def.reserve_cap() else ""
	if owned and str(item.get("cat", "")) != "grenades":
		return "Owned"
	return ""


func _shop_buy(item_id: String) -> void:
	if bridge != null and not _offline:
		bridge.ask_buy(item_id)
	elif game.shop != null and player != null:
		var _sold: bool = game.shop.buy(player, item_id)
		_follow_shop_menu()


func _prompt() -> String:
	if player == null or not player.can_act():
		return ""

	var eye := player.eye_position()
	var aim := player.aim_direction()

	for other in game.survivors():
		if other != player and other.is_down() and other.feet().distance_to(player.feet()) <= game.config.revive_range + 0.4:
			return "%s — pick up %s" % [_key(ZzBindings.USE), other.display_name]

	if player.defibs > 0:
		for other in game.survivors():
			if other != player and other.life == ZzPlayer.Life.DEAD \
					and other.feet().distance_to(player.feet()) <= game.config.defib_range + 0.4:
				return "%s — hold to shock %s back" % [_key(ZzBindings.USE), other.display_name]

	var best := ""
	var best_off := 0.7

	for id: int in world_view._loot:
		var node: Node3D = world_view._loot[id]
		var to := node.global_position + Vector3(0.0, 0.25, 0.0) - eye
		var along := to.dot(aim)

		if along < 0.0 or along > game.config.use_reach + 0.3:
			continue

		var off := (to - aim * along).length()

		if off < best_off:
			best_off = off
			var cost := int(node.get_meta(&"price", 0))
			best = "%s — %s%s" % [_key(ZzBindings.USE), str(node.get_meta(&"label", "pick up")),
				" (%d points)" % cost if cost > 0 else ""]

	if best != "":
		return best

	var index := game.current_objective()

	if index >= 0 and game.objective_states[index] == &"waiting":
		var o: Dictionary = (game.map_doc["objectives"] as Array)[index]
		if o["kind"] == "use" and eye.distance_to(ZzMapDoc.v3(o["at"])) <= float(o["radius"]) + 0.6:
			return "%s — %s" % [_key(ZzBindings.USE), str(o["label"])]

	# A barricade within reach that is not whole: the same test the server mends by.
	var mend := game.barricade_to_mend(player)

	if mend >= 0:
		var entry: Dictionary = (game.map_doc["barricades"] as Array)[mend]
		var held: Dictionary = game.barricades.get(str(entry["id"]), {})
		if not held.is_empty():
			var share := int(round(100.0 * float(held["health"]) / float(held["max"])))
			return "%s — %s %s (%d%%)" % [_key(ZzBindings.USE), "mend" if bool(held["intact"]) else "rebuild",
				str(entry.get("label", "the barricade")), share]

	return ""


func _present_effects(delta: float) -> void:
	if audio != null:
		audio.listen_from(camera.global_position)
		audio.keep_walkers(game.players.values())
		if game.physics != null:
			audio.follow_roof(delta, camera.global_position, camera.get_world_3d().direct_space_state, game.physics.layer_mask(&"world"))

	if game.effects != null:
		game.effects.viewer_position = camera.global_position
		game.effects.advance(delta)

	if blood != null:
		blood.advance(delta)


# --- Watching, once out -----------------------------------------------------

func is_spectating() -> bool:
	return player != null and game != null and game.spectate != null \
		and game.spectate.is_spectating(player.player_id)


func _watched_through_eyes() -> ZzPlayer:
	if not is_spectating():
		return null

	var mode := game.spectate.mode_of(player.player_id)

	if mode != DotSpectatorView.Mode.FIRST_PERSON and mode != DotSpectatorView.Mode.FREEZE_CAM:
		return null

	return game.players.get(game.spectate.watching(player.player_id))


func _drive_spectator_camera(delta: float) -> bool:
	if not is_spectating():
		if camera.get_parent() == self:
			_place_camera()

		if hud != null:
			hud.set_watching("")

		return false

	if camera.get_parent() != self:
		camera.get_parent().remove_child(camera)
		add_child(camera)
		camera.current = true

		if _arm != null and is_instance_valid(_arm):
			_arm.queue_free()
			_arm = null

	if view_model != null and is_instance_valid(view_model):
		view_model.visible = false

	# Chase and death cameras pulled out of the street by dot-spectate, given the level.
	var manager: DotSpectatorManager = game.spectate.manager
	if manager != null and manager.camera_world == null:
		manager.camera_world = camera.get_world_3d()
		manager.camera_mask = game.world_mask()

	var where := game.spectate.camera_for(player.player_id)

	if where != Transform3D.IDENTITY:
		camera.global_transform = where
		_present_end_camera(delta, _spectator_focus(where))

	if hud != null:
		hud.set_watching(game.spectate.line_for(player.player_id))

	return true


## What a spectator's ending camera looks at: the player being watched, else a point in front of the spectator camera.
func _spectator_focus(where: Transform3D) -> Vector3:
	var target := game.spectate.watching(player.player_id)
	var who: Variant = game.players.get(target) if target != &"" else null
	if who != null and is_instance_valid(who) and who.has_method("eye_position"):
		return who.eye_position()
	return where.origin - where.basis.z * 3.0


func spectate_step(direction: int) -> void:
	if audio != null:
		var _heard := audio.click()

	if bridge != null:
		bridge.ask_spectate(direction)
		return

	if game == null or game.spectate == null or player == null:
		return

	var moved := game.spectate.step(player.player_id, direction)

	if not moved.ok and chat != null:
		chat.notice(moved.error.message)


## Everything a frame draws for the survivors, in this order: the netcode's interpolation, then
## every survivor, then every beacon. Returns how many are shown. Static so the net suite drives
## exactly this and not a copy of it.
static func present_frame(
	p_net: DotNetManager,
	p_game: ZzGame,
	own: ZzPlayer,
	first_person: bool,
	delta: float,
	alpha: float = -1.0,
	watched: ZzPlayer = null
) -> int:
	var networked := p_net != null and p_net.is_running()

	if networked:
		p_net.interpolate_frame(alpha)

	# Your own player is drawn at the clock's render alpha, not the engine's fraction: the
	# clock stretches and shrinks its ticks while it settles on the server, so a physics frame
	# now and then runs no tick or two, and drawn at the engine's fraction the eye stood still
	# on one frame and moved double on the next. `DotFpsController.render_state` reads it from
	# `render_clock` (dot-player-controller); by name both ways, so a shell older than either
	# draws as before. Null offline, where every physics frame is one tick.
	if own != null and own.controller != null:
		own.controller.set(&"render_clock", p_net.clock if networked else null)

	if p_game == null:
		return 0

	var shown := 0

	for key: StringName in p_game.players:
		var body: ZzPlayer = p_game.players[key]

		if body == null or not is_instance_valid(body) or not body.is_inside_tree():
			continue

		var mine := body == own
		var at := drawn_position(body, networked and not mine)
		var colour := p_game.side_colour(ZzGame.SURVIVORS)
		var hidden := (mine and first_person) or body == watched

		if body.present_body(hidden, at, colour):
			shown += 1

		var _pinged := body.present_beacon(delta, at, mine and first_person, 2.0)

	return shown


static func drawn_position(body: ZzPlayer, remote: bool) -> Vector3:
	if remote or body.controller == null:
		return body.global_position

	return body.controller.render_state().position


func _unhandled_input(event: InputEvent) -> void:
	# Tab, M and a click taking the pointer back are the platform's (DotGameClient).
	if event.is_action_pressed("ui_cancel") and is_shop_open():
		close_shop()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		# Opens the settings when the menu left this Escape alone.
		if settings != null:
			settings.open()
		return

	# Nothing below acts while the cover is up: no shot, jump, look or use.
	if _covered():
		return

	if is_shop_open():
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed(ZzBindings.USE):
			close_shop()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and not event.is_echo():
		if _key_event(event):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton

		if is_spectating():
			_firing = false
			_shoving = false

			if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
				spectate_step(1)
			elif button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
				spectate_step(-1)
			return

		if button.is_action(ZzBindings.FIRE):
			_firing = button.pressed
		elif button.is_action(ZzBindings.AIM):
			_aiming = button.pressed
		elif button.pressed and _pointer_ours():
			# The wheel, on dot-menu's previous/next weapon actions (rebindable).
			if event.is_action_pressed(DotMenuBindings.WEAPON_NEXT_ACTION):
				_cycle_slot(1)
			elif event.is_action_pressed(DotMenuBindings.WEAPON_PREVIOUS_ACTION):
				_cycle_slot(-1)

	if player == null:
		return

	if event is InputEventMouseMotion and _pointer_ours():
		if _offline and player.sampler != null:
			player.sampler.handle_event(event)
		elif _sampler != null:
			_sampler.handle_event(event)


## The game's own keys, held and pressed. True when one was used.
func _key_event(event: InputEvent) -> bool:
	var pressed := event.is_pressed()

	if event.is_action(ZzBindings.USE):
		if pressed and _near_trader() and _prompt() == "":
			open_shop()
			return true
		if pressed and not _near_trader() and _near_trader(false) and _prompt() == "":
			var why := str(shop_state.get("closed_message", ""))
			if why != "":
				game.notice.emit(why)
		_using = pressed
		return true

	if event.is_action(ZzBindings.HEAL):
		_healing = pressed
		return true

	if event.is_action(ZzBindings.PILLS):
		_pills = pressed
		return true

	if event.is_action(ZzBindings.FIRE):
		_firing = pressed
		return true

	if event.is_action(ZzBindings.BOX):
		_box_key = pressed
		return true

	if event.is_action(ZzBindings.RELOAD):
		_reloading = pressed
		return true

	if event.is_action(ZzBindings.AIM):
		_aiming = pressed
		return true

	if not pressed:
		return false

	if event.is_action_pressed(ZzBindings.VIEW):
		if is_spectating():
			spectate_step(0)
		else:
			toggle_view()
		return true

	if event.is_action_pressed(ZzBindings.FLASHLIGHT):
		if flash != null:
			var _asked := flash.toggle()
		return true

	if event.is_action_pressed(ZzBindings.SHOVE):
		_shoving = true
		get_tree().create_timer(0.1).timeout.connect(func() -> void: _shoving = false)
		return true

	for i in range(ZzBindings.SLOTS.size()):
		if event.is_action_pressed(ZzBindings.SLOTS[i]):
			if _slot == i + 1 and weapons != null and weapons.arsenal != null and weapons.arsenal.weapons_in(_slot).size() > 1:
				_cycle_ticks = 3
				var _cycled := weapons.arsenal.cycle_slot(game.round_number * 100000 + Engine.get_physics_frames())
			_slot = i + 1
			return true

	# Previous and next weapon, on the wheel by default; a row moved onto a key lands here.
	if _pointer_ours():
		if event.is_action_pressed(DotMenuBindings.WEAPON_NEXT_ACTION):
			_cycle_slot(1)
			return true
		elif event.is_action_pressed(DotMenuBindings.WEAPON_PREVIOUS_ACTION):
			_cycle_slot(-1)
			return true

	return false


func _cycle_slot(direction: int) -> void:
	if weapons == null or weapons.arsenal == null:
		return

	var slots := weapons.arsenal.slots()

	if slots.is_empty():
		return

	var at := slots.find(_slot)
	_slot = slots[posmod((at if at >= 0 else 0) + direction, slots.size())]


func describe() -> Dictionary:
	var out := {
		"offline": _offline,
		"session": _watch_id,
		"player": player != null,
		"view": "third" if third_person else "first",
		"armed": weapons != null,
		"world_view": world_view.describe() if world_view != null else {},
	}

	if bridge != null:
		out["bridge"] = bridge.describe()

	if chat != null:
		out["chat"] = chat.describe()

	if game != null:
		out["world"] = game.describe()

	return out


## Where a roster row's player stands, for dot-game's look-to-gag key (G, K).
func _look_position(row: Dictionary) -> Variant:
	if game == null:
		return null
	for who: ZzPlayer in game.players.values():
		if who != player and who.display_name == row["name"]:
			return who.global_position + Vector3.UP * 1.5
	return null
