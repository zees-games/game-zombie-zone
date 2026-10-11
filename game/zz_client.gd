extends Node

const ZzAudio := preload("zz_audio.gd")
const ZzBindings := preload("zz_bindings.gd")
const ZzBoxes := preload("zz_boxes.gd")
const ZzFigure := preload("zz_figure.gd")
const ZzSettings := preload("zz_settings.gd")
const ZzServices := preload("zz_services.gd")
const ZzNetBridge := preload("net/zz_net_bridge.gd")
const ZzNetCommand := preload("net/zz_net_command.gd")
const ZzConfig := preload("zz_config.gd")
const ZzGame := preload("zz_game.gd")
const ZzHud := preload("zz_hud.gd")
const ZzLoot := preload("zz_loot.gd")
const ZzMapDoc := preload("zz_map_doc.gd")
const ZzNpcs := preload("zz_npcs.gd")
const ZzPaths := preload("zz_paths.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzWeapons := preload("zz_weapons.gd")
const ZzWorldView := preload("zz_world_view.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

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

const LINK_SERVICE := &"dot_client_link"

const CHASE_BACK := 2.6
const CHASE_UP := 0.6

@export var config_file: String = "user://cfg/zombiezone.json"
@export var force_offline: bool = false

## How many stand-ins an offline map gets beside you.
@export_range(0, 12, 1) var offline_bots: int = 3

var game: ZzGame = null
var player: ZzPlayer = null
var camera: Camera3D = null
var hud: ZzHud = null
var board: DotMenuScoreboard = null
var chat: DotGameChatClient = null
var audio: ZzAudio = null
var settings: ZzSettings = null

## The player's console. See [method DotConsoleKit.build].
var console: DotConsoleController = null
var world_view: ZzWorldView = null

## Your own gun, drawn. Never decides anything: every shot is the server's.
var weapons: ZeeWeaponRig = null
var view_model: ZeeViewModel = null

var net: DotNetManager = null
var bridge: ZzNetBridge = null
var link: Node = null

var third_person: bool = false

var _offline: bool = true
var _sampler: DotFpsSampler = null
var _watch_id: int = -1
var _captured: bool = false
var _arm: SpringArm3D = null
var _rig_height: float = 0.0
var _started_msec: int = Time.get_ticks_msec()

var _firing: bool = false
var _shoving: bool = false
var _reloading: bool = false
var _using: bool = false
var _healing: bool = false
var _pills: bool = false
var _slot: int = 0

## Box types' colours, offline from the catalogue, connected from the file the server also has.
var _box_colours: Dictionary = {}

## A brute is alive: its music plays.
var _brutes: int = 0


func _ready() -> void:
	ZeeModelCache.set_asset_root(ZzPaths.root())

	var config := ZzConfig.new()
	var loaded := config.load_layered(config_file)

	if not loaded.ok:
		DotLog.warn(CHANNEL, "falling back to defaults", {"why": loaded.error.message})

	link = DotRegistry.get_node_service(LINK_SERVICE)
	_offline = force_offline or link == null or OS.get_cmdline_user_args().has("--offline")

	game = ZzGame.new()
	game.name = "World"
	game.config = config
	game.authoritative = _offline
	game.register_service = _offline
	game.tick_rate = int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 64))
	game.draw_world = true
	add_child(game)

	_sampler = DotFpsSampler.new(ZzPlayer.tunables_for(config))
	ZzPlayer.register_actions(_sampler)

	_build_hud()
	_build_chat()
	_build_audio()
	_build_settings()
	_build_world_view()
	_read_box_colours()

	if _offline:
		_start_offline()
	else:
		DotLog.result(CHANNEL, "the netcode", _build_netcode())

	if not DotPlatform.is_web():
		_capture()


func _exit_tree() -> void:
	ZeeModelCache.set_asset_root("res://")


func _build_world_view() -> void:
	world_view = ZzWorldView.new()
	world_view.name = "WorldView"
	world_view.audio = audio
	game.add_child(world_view)


func _read_box_colours() -> void:
	var boxes := ZzBoxes.new(game)

	if boxes.load_file(game.config.box_file) > 0:
		for id in boxes.order:
			_box_colours[id] = boxes.colour_of(id)


# --- Offline ---------------------------------------------------------------

func _start_offline() -> void:
	for i in range(offline_bots):
		var bot := game.add_player(StringName("u%d" % (ZzNetBridge.FIRST_BOT_SESSION + i)), _bot_name(i))
		bot.is_bot = true

	_adopt(game.add_player(&"local", "You", 0, true))
	_hear_the_world()

	game.achievement_earned.connect(func(id: StringName, title: String, points: int) -> void:
		if player != null and id == player.player_id and chat != null:
			chat.say_locally("Achievement: %s (+%d)" % [title, points], Color(0.98, 0.84, 0.40))
	)
	game.start()
	DotLog.result(CHANNEL, "chat, offline", chat.attach(null))


static func _bot_name(index: int) -> String:
	var names := PackedStringArray(["Rook", "Marlow", "Juno", "Hask", "Petra", "Odell", "Sable", "Wren"])
	return names[index % names.size()]


# --- Connected -------------------------------------------------------------

func _build_netcode() -> DotResult:
	# The server's `mp_teammate_passthrough`, and every change to it, through the link: this
	# end traces its own shots for tracers and impacts, and on its default 1 against a server
	# on 0 or 2 they ended in (or went through) a team-mate where the server's did the
	# opposite. An older shell's link cannot say, and the manager keeps its default.
	if game.combat != null and link != null:
		var _following := game.combat.follow_cvars(link)

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
	net.messages.seal()

	bridge.hello_received.connect(_on_hello)
	bridge.roster_changed.connect(_on_roster_changed)
	bridge.phase_received.connect(_on_phase)
	bridge.round_changed.connect(_on_round)
	bridge.death_received.connect(_on_death)
	bridge.downed_received.connect(_on_down)
	bridge.revived_received.connect(_on_revive)
	bridge.rescued_received.connect(_on_rescue)
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
		if hud != null:
			hud.set_effects(rows))
	bridge.hurt_received.connect(_on_hurt)
	bridge.hit_received.connect(_on_hit)
	bridge.notice_received.connect(_on_notice)
	bridge.npc_added.connect(func(net_id: int, kind: StringName, variant: int, body: Node3D) -> void:
		_on_zombie(kind, true)
		world_view.add_zombie(net_id, kind, variant, body))
	bridge.npc_removed.connect(func(net_id: int, killed: bool, body: Node3D) -> void:
		_on_zombie(StringName(str(body.get(&"kind"))) if body != null else &"", false)
		world_view.remove_zombie(net_id, killed, body))
	bridge.loot_added.connect(func(id: int, kind: StringName, item: StringName, at: Vector3) -> void:
		world_view.add_loot(id, kind, item, at, _box_colours.get(item, Color(0.8, 0.6, 0.25))))
	bridge.loot_removed.connect(func(id: int, _by: int) -> void: world_view.remove_loot(id))
	bridge.hazard_added.connect(world_view.add_hazard)
	bridge.hazard_removed.connect(world_view.remove_hazard)
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
	_build_camera()

	if settings != null:
		settings.bind_camera(camera)
		if player.sampler != null:
			settings.bind_look(player.sampler.tunables)

	if hud != null:
		hud.bind(game, player)


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

	if game.loot != null:
		game.loot.added.connect(func(id: int, kind: StringName, item: StringName, at: Vector3) -> void:
			world_view.add_loot(id, kind, item, at, _box_colours.get(item, Color(0.8, 0.6, 0.25))))
		game.loot.removed.connect(func(id: int, _by: StringName) -> void: world_view.remove_loot(id))

	if game.boxes != null:
		game.boxes.opened.connect(func(id: StringName, type_id: StringName, title: String, message: String) -> void:
			_on_box(_session(id), type_id, title, message))
		game.boxes.effects_changed.connect(func() -> void:
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


func _on_phase(phase: int) -> void:
	if hud == null:
		return

	if phase == ZzGame.Phase.PLAY:
		if game.effects != null:
			var _flashed := game.effects.flash(&"go")


func _on_map(_map_id: StringName) -> void:
	var name_of := str(game.map_doc.get("name", ""))
	world_view.clear()

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
		if audio != null:
			audio.music(&"")
		if hud != null:
			hud.shout("SURVIVE" if game.is_survival() else "GET TO THE SAFE ROOM", 3.0)
		return

	if audio != null:
		var _heard := audio.play(ZzAudio.MAP_WON if won else ZzAudio.MAP_LOST)
		audio.music(&"")

	if hud != null:
		hud.shout(("YOU MADE IT — %s" if won else "YOU DIED — %s") % why, 5.0)

	if chat != null and why != "":
		chat.say_locally(why, Color(0.98, 0.86, 0.40))


func _on_death(session_id: int, by: int, why: StringName, by_kind: StringName) -> void:
	var who := _player_of(session_id)
	var mine := session_id == _watch_id

	if audio != null and mine:
		var _heard := audio.play(ZzAudio.YOU_ARE_DEAD)

	if chat != null:
		chat.say_locally(_feed_line(_name_of(session_id), "died", by, why, by_kind), Color(0.95, 0.5, 0.45))

	if who != null and world_view != null:
		world_view.unpin(who)


func _on_down(session_id: int, by: int, why: StringName, by_kind: StringName) -> void:
	var who := _player_of(session_id)
	var mine := session_id == _watch_id

	if audio != null:
		if mine:
			var _down := audio.play(ZzAudio.YOU_ARE_DOWN)
		elif who != null:
			var _call := audio.at(ZzAudio.CALL_MEDIC, who.global_position)

	if mine and hud != null:
		hud.shout("YOU ARE DOWN", 2.0)

	if chat != null:
		chat.say_locally(_feed_line(_name_of(session_id), "is down", by, why, by_kind), Color(0.98, 0.7, 0.4))


func _feed_line(name_of: String, what: String, by: int, why: StringName, by_kind: StringName) -> String:
	if by_kind != &"":
		return "%s %s (%s)" % [name_of, what, String(by_kind)]
	if by != 0:
		return "%s %s (%s)" % [name_of, what, _name_of(by)]
	if why == ZzGame.BY_FELL:
		return "%s fell" % name_of
	if why == ZzGame.BY_BLED:
		return "%s bled out" % name_of
	return "%s %s" % [name_of, what]


func _on_revive(session_id: int, by: int) -> void:
	if session_id == _watch_id and audio != null:
		var _up := audio.play(ZzAudio.YOU_ARE_UP)

	if chat != null:
		chat.say_locally("%s was picked up%s" % [_name_of(session_id), " by %s" % _name_of(by) if by != 0 else ""],
			Color(0.6, 0.95, 0.6))


func _on_rescue(session_id: int) -> void:
	if chat != null:
		chat.say_locally("%s is back" % _name_of(session_id), Color(0.6, 0.95, 0.6))


func _on_pin(session_id: int, holder: Node3D, kind: StringName) -> void:
	var who := _player_of(session_id)

	if who != null and world_view != null:
		world_view.pin(who, holder, kind)

	if session_id == _watch_id and hud != null:
		hud.shout({&"pounce": "POUNCED — SHOVE IT OFF", &"choke": "TONGUED — HELP!", &"carry": "CARRIED — HELP!",
			&"ride": "RIDDEN — HELP!"}.get(kind, "HELD"), 2.0)


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


## A hit the server confirmed: the marker and the number on the body.
func _on_hit(victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
	if hud != null:
		hud.confirm_hit(victim, amount, point, killed, headshot)


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
		weapons.tick_rate = game.tick_rate
		weapons.view_model_ref = DotNodeRef.of_path(view_model.get_path())
		weapons.player_ref = DotNodeRef.of_path(player.get_path())
		player.add_child(weapons)

		var ready_now := weapons.setup()

		if not ready_now.ok:
			DotLog.warn(CHANNEL, "the view model would not set up", {"why": ready_now.error.message})
			_strip_locally()
			return

		weapons.used.connect(func(outcome: DotWeaponOutcome) -> void:
			if audio != null and camera != null:
				var _heard := audio.on_weapon(camera.global_position, ZeeWeaponNet.kind_number(outcome.kind)))

	if not weapons.give(weapon_id).ok:
		return

	var tier := ZzWeapons.tier_of(weapon_id)
	var def := weapons.arsenal.catalogue.get_def(weapon_id)

	if def != null and (_slot == 0 or (tier != &"melee" and tier != &"thrown")):
		_slot = def.slot

	if audio != null:
		var _ding := audio.play(ZzAudio.PICKUP)


func _strip_locally() -> void:
	_slot = 0

	if weapons != null and weapons.arsenal != null:
		weapons.arsenal.clear()


# --- The camera ------------------------------------------------------------

func _build_camera() -> void:
	if camera != null or player == null:
		return

	camera = Camera3D.new()
	camera.name = "Eye"
	camera.fov = 90.0
	camera.current = true
	camera.far = 400.0
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

		return

	_arm = SpringArm3D.new()
	_arm.name = "Chase"
	_arm.spring_length = CHASE_BACK
	_arm.collision_mask = game.world_mask()
	_arm.add_excluded_object(player.get_rid())
	_arm.margin = 0.15
	_rig_height = eye.y + CHASE_UP
	player.add_child(_arm)
	_arm.add_child(camera)
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO

	if view_model != null and is_instance_valid(view_model):
		view_model.visible = false


func toggle_view() -> void:
	third_person = not third_person
	_place_camera()

	if audio != null:
		var _heard := audio.click()


func _build_hud() -> void:
	hud = ZzHud.new()
	hud.name = "Hud"
	hud.key_fn = _key
	add_child(hud)


## The key an action is on, as the player has it bound.
func _key(action: StringName) -> String:
	if settings != null and settings.bindings != null:
		var text := settings.bindings.key_for(action)
		if text != "":
			return text

	var row := ZzBindings.make().row_for_action(action)
	return str(row.get("default", action))


# --- The Tab board ---------------------------------------------------------

func _wire_board() -> void:
	if settings == null or settings.menu == null:
		return

	board = settings.menu.scoreboard
	board.title_text = "Zombie Zone"
	board.columns = [
		{"key": &"avatar", "kind": DotMenuScoreboard.KIND_AVATAR, "width": 0.0},
		{"key": &"name", "title": "Survivor", "width": 3.0},
		{"key": &"kills", "title": "Kills", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"specials", "title": "Specials", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"points", "title": "Points", "kind": DotMenuScoreboard.KIND_NUMBER},
		{"key": &"ping", "title": "Ping", "kind": DotMenuScoreboard.KIND_PING},
	]
	board.sort_by = &"points"
	board.decorate = _decorate_row
	board.prepare = _prepare_board

	if not _offline and link != null:
		board.feed_from(link)
	else:
		board.source = board_snapshot


func _show_board(on: bool) -> void:
	if board == null:
		return
	if on:
		board.open()
	else:
		board.close()


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
	if int(row.get("ping", -1)) < 0 and who.ping_ms >= 0:
		row["ping"] = who.ping_ms
	if who == player:
		row["you"] = true


func _prepare_board(snap: Dictionary) -> void:
	if game == null:
		return
	snap["header"] = {"Map": str(game.map_doc.get("name", "")), "Difficulty": game.config.difficulty_name().capitalize()}
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
	eye.look_at_from_position(Vector3(0.0, 1.55, -1.6), Vector3(0.0, 1.45, 0.0), Vector3.UP)
	eye.current = true

	var texture := view.get_texture()
	_portraits[atlas] = texture
	return texture


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

	chat.typing_changed.connect(func(typing: bool) -> void:
		_suspend_input(typing or (settings != null and settings.is_open())))


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

	var built: DotResult = settings.setup()

	if not built.ok:
		DotLog.warn(CHANNEL, "no settings; everything is at its default", {"why": built.error.message})
		remove_child(settings)
		settings.free()
		settings = null
		return

	if _sampler != null:
		settings.bind_look(_sampler.tunables)

	if audio != null:
		settings.bind_audio(audio.manager)

	if settings.menu != null:
		settings.menu.scoreboard_action = ZzBindings.SCOREBOARD
		settings.menu_state_changed.connect(func(any_open: bool) -> void:
			_suspend_input(any_open or (chat != null and chat.is_typing()))
			if any_open:
				_release()
			elif not DotPlatform.is_web():
				_capture())
		settings.menu.busy = func() -> bool: return chat != null and chat.is_typing()
		# The console (the key under Escape): net_stat and every other setting by name, and
		# the server's console when one runs in this process. One of the menu's overlays, so
		# opening it stops the player and frees the pointer exactly as the menu does.
		console = DotConsoleKit.build(self, settings.settings, settings.menu)
		_wire_board()


func _suspend_input(suspended: bool) -> void:
	if _sampler != null:
		_sampler.suspended = suspended

	if player != null and player.sampler != null:
		player.sampler.suspended = suspended


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_captured = true


func _release() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_captured = false


## The hands' bits for this tick, from the held keys.
func _actions() -> int:
	var out := 0
	if _using:
		out |= ZzNetCommand.ACT_USE
	if _healing:
		out |= ZzNetCommand.ACT_HEAL
	if _pills:
		out |= ZzNetCommand.ACT_PILLS
	return out


# --- The frame -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _offline:
		_drive_offline()
		return

	if net == null or not net.is_running() or bridge == null:
		return

	var move := _sampler.sample(delta) if _sampler != null else DotFpsCommand.new()
	_stamp(move)

	var ticks := net.clock.advance(delta)

	for i in range(ticks):
		if not net.clock.is_synced():
			continue

		bridge.client_tick(net.clock.input_tick() - (ticks - 1 - i), move, _slot, _actions())

	_drive_view_model(move)


func _drive_offline() -> void:
	if player == null or player.sampler == null:
		return

	var pending := player.controller.current_command

	if pending != null:
		_stamp(pending)
		player.wanted_slot = _slot
		player.actions = _actions()
		player.shove_held = _shoving

	_drive_view_model(pending)


func _stamp(command: DotFpsCommand) -> void:
	if command == null:
		return

	command.set_button(ZzNetCommand.BUTTON_FIRE, _firing)
	command.set_button(ZzNetCommand.BUTTON_SHOVE, _shoving)
	command.set_button(ZzNetCommand.BUTTON_RELOAD, _reloading)


func _drive_view_model(command: DotFpsCommand) -> void:
	if weapons == null or player == null:
		return

	var weapon_command := DotWeaponCommand.new()
	var held := player.is_pinned() or player.using != &""

	if command != null and not held:
		weapon_command.set_button(DotWeaponCommand.BUTTON_ATTACK, command.is_pressed(ZzNetCommand.BUTTON_FIRE))
		weapon_command.set_button(DotWeaponCommand.BUTTON_RELOAD, command.is_pressed(ZzNetCommand.BUTTON_RELOAD))

	if command != null:
		weapon_command.yaw = command.yaw
		weapon_command.pitch = command.pitch

	weapon_command.slot = _slot
	var _outcome := weapons.simulate_tick(weapon_command, game.round_number * 100000 + Engine.get_physics_frames())


func _process(delta: float) -> void:
	var _shown := present_frame(net, game, player, not third_person, delta, -1.0, _watched_through_eyes())

	if camera == null or player == null:
		return

	if world_view != null:
		world_view.present(delta, camera.global_position)

	if _drive_spectator_camera():
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
	var height := ZzPlayer.EYE_DOWN if player.is_down() else _rig_height
	rig.global_position = drawn.position + Vector3(0.0, height, 0.0)

	if weapons != null:
		var speed := Vector2(state.velocity.x, state.velocity.z).length()
		weapons.drive_view(Vector2(state.yaw, state.pitch), speed, state.mode != DotFpsState.Mode.AIR, state.crouch_fraction > 0.5)

	if view_model != null and is_instance_valid(view_model):
		view_model.visible = not third_person and not player.is_pinned() and player.using == &""

	if hud != null:
		hud.set_prompt(_prompt())

	_present_effects(delta)


## What E would do now, for the HUD: who you would revive, what you would pick up.
func _prompt() -> String:
	if player == null or not player.can_act():
		return ""

	var eye := player.eye_position()
	var aim := player.aim_direction()

	for other in game.survivors():
		if other != player and other.is_down() and other.feet().distance_to(player.feet()) <= game.config.revive_range + 0.4:
			return "%s — pick up %s" % [_key(ZzBindings.USE), other.display_name]

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
			best = "%s — %s" % [_key(ZzBindings.USE), str(node.get_meta(&"label", "pick up"))]

	if best != "":
		return best

	var index := game.current_objective()

	if index >= 0 and game.objective_states[index] == &"waiting":
		var o: Dictionary = (game.map_doc["objectives"] as Array)[index]
		if o["kind"] == "use" and eye.distance_to(ZzMapDoc.v3(o["at"])) <= float(o["radius"]) + 0.6:
			return "%s — %s" % [_key(ZzBindings.USE), str(o["label"])]

	return ""


func _present_effects(delta: float) -> void:
	if audio != null:
		audio.listen_from(camera.global_position)

	if game.effects != null:
		game.effects.viewer_position = camera.global_position
		game.effects.advance(delta)


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


func _drive_spectator_camera() -> bool:
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

	var where := game.spectate.camera_for(player.player_id)

	if where != Transform3D.IDENTITY:
		camera.global_transform = where

	if hud != null:
		hud.set_watching(game.spectate.line_for(player.player_id))

	return true


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
	if event is InputEventMouseButton and event.pressed and not _captured:
		_capture()
		return

	if event.is_action_pressed("ui_cancel"):
		_release()
		if settings != null:
			settings.open()
		return

	if event.is_action(ZzBindings.SCOREBOARD) and not event.is_echo():
		_show_board(event.is_pressed())
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

		if button.button_index == MOUSE_BUTTON_LEFT:
			_firing = button.pressed
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_shoving = button.pressed
		elif button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_cycle_slot(-1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1)

	if player == null:
		return

	if event is InputEventMouseMotion and _captured:
		if _offline and player.sampler != null:
			player.sampler.handle_event(event)
		elif _sampler != null:
			_sampler.handle_event(event)


## The game's own keys, held and pressed. True when one was used.
func _key_event(event: InputEvent) -> bool:
	var pressed := event.is_pressed()

	if event.is_action(ZzBindings.USE):
		_using = pressed
		return true

	if event.is_action(ZzBindings.HEAL):
		_healing = pressed
		return true

	if event.is_action(ZzBindings.PILLS):
		_pills = pressed
		return true

	if event.is_action(ZzBindings.RELOAD):
		_reloading = pressed
		return true

	if not pressed:
		return false

	if event.is_action_pressed(ZzBindings.VIEW):
		if is_spectating():
			spectate_step(0)
		else:
			toggle_view()
		return true

	if event.is_action_pressed(ZzBindings.SHOVE):
		_shoving = true
		get_tree().create_timer(0.1).timeout.connect(func() -> void: _shoving = false)
		return true

	var key := (event as InputEventKey).physical_keycode

	if key >= KEY_1 and key <= KEY_5:
		_slot = key - KEY_1 + 1
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
