extends Node

const ZzEvent := preload("zz_event.gd")
const ZzEvents := preload("zz_events.gd")
const ZzNetCommand := preload("zz_net_command.gd")
const ZzNetLink := preload("zz_net_link.gd")
const ZzPlayerNet := preload("zz_player_net.gd")
const ZzNpcNet := preload("zz_npc_net.gd")
const ZzRequest := preload("zz_request.gd")

const ZzGame := preload("../zz_game.gd")
const ZzMapDoc := preload("../zz_map_doc.gd")
const ZzPlayer := preload("../zz_player.gd")
const ZzZombieBody := preload("../../npcs/zz_zombie_body.gd")
const ZzPaths := preload("../zz_paths.gd")

## Joins an [ZzGame] to a [DotNetManager]. The netcode seam, and the only file in this
## project that names both.
##
## [codeblock]
## # server
## bridge.attach(game, net)          # dot-game's DotGameNetcode does this
## bridge.open_link(server)          # and this
## bridge.add_player(peer_id, userid, "Ada")
## bridge.server_tick(tick)          # instead of the game's own loop
##
## # client
## bridge.attach(game, net)
## bridge.open_link(client_link)
## bridge.ask_ready()
## bridge.client_tick(tick, command, slot)
## [/codeblock]
##
## [b]What crosses.[/b] A survivor's own movement is predicted, like every first-person game in
## this family. Zombies are entities too, server-owned and never predicted (dot-npc's reason):
## announced once with their kind (`NPC`), then moved by snapshots, then let go (`NPC_GONE`).
## The map arrives ONCE, as a document in `MAP`. Everything that happens rather than moves —
## a down, a pin, a box, a pool of acid, a thrown rock, an explosion — is one reliable event,
## and anything a joiner needs to know about the world as it already is (who is held, what is
## lying on the ground, which pools are burning) is told to them on READY.
##
## [b]The ordering is the other half of the file.[/b] dot-net drives simulation per entity;
## this game's tick is a whole-world property — every player moves, then the shots, the horde
## and the round are decided. [method ensure_game_ticked] reconciles the two: the first
## behaviour through on a tick runs the whole world and the rest find it done.

const CHANNEL := "zz.net"

## Bytes of acknowledgement in front of every input packet. [method DotNetManager.encode_ack].
const ACK_BYTES := 4

## Commands in every input packet: this tick's and the four before it, so a lost packet
## costs the server no tick unless the next four are lost too. Over WebSocket nothing is
## ever lost; over ENet (the desktop client, since servers went dual-stack) one command a
## packet was a tick the server ran on the previous command for every packet dropped.
## game-arena measured it first: 80% of ticks with the right command at 20% loss with one
## copy, 99-100% with three, and five closed the rest (2026-10-09).
const INPUT_COPIES := 5

## How often the round clock and the numbers behind it go out, in ticks.
##
## [b]Twice a second, not per tick and not per snapshot.[/b] What it carries changes when
## somebody is found or a second passes, and a client told sixty-four times a second would be
## paying for sixty-two copies of the same numbers. The clock itself is advanced on the
## client between messages — see [method _apply_clock].
const CLOCK_EVERY := 32

## The client has been told who it is. [param player_id] is the session id.
signal hello_received(player_id: int)

## Somebody joined, left or changed sides. Client side; the HUD and a scoreboard read it.
signal roster_changed(player_id: int)

## A map began or ended. [param won] is whether the survivors made it; [param why] the
## server's sentence.
signal round_changed(number: int, began: bool, won: bool, why: String)

## The map moved on: start area, playing. Client side.
signal phase_received(phase: int)

## Somebody died, and what did it: a session, or a zombie kind.
signal death_received(player_id: int, by: int, why: StringName, by_kind: StringName)

## Somebody was handed, or picked up, a weapon. The HUD names it.
signal armed_received(player_id: int, weapon_id: StringName)

signal notice_received(text: String)

## Client side: the server moved this client's own camera. [param mode] is
## [enum DotSpectatorView.Mode]; the view has already been adopted by the world's mirror.
signal spectate_received(viewer: int, mode: int, target: int)

## Client side: somebody else used their weapon [param times] times since the last
## snapshot. [param kind] is one of `ZeeWeaponNet.KIND_*`. Relayed from that player's own
## behaviour, because a client builds those one per JOIN and nothing else could find them.
signal weapon_used_by(session_id: int, times: int, kind: int)

## Client side: the map was rebuilt from what the server sent. The HUD names it.
signal map_received(map_id: StringName)

## Client side, all of them: what the server says happened. See [ZzEvents.Kind].
signal downed_received(player_id: int, by: int, why: StringName, by_kind: StringName)
signal revived_received(player_id: int, by: int)
signal rescued_received(player_id: int)
signal pin_received(player_id: int, npc_net_id: int, kind: StringName)
signal unpin_received(player_id: int, why: StringName)
signal box_received(player_id: int, type_id: StringName, title: String, message: String)
signal loot_added(id: int, kind: StringName, item: StringName, at: Vector3)
signal loot_removed(id: int, by: int)
signal hazard_added(id: int, kind: StringName, at: Vector3, radius: float, seconds: float)
signal hazard_removed(id: int)
signal thrown(id: int, kind: StringName, from: Vector3, velocity: Vector3)
signal landed(id: int, kind: StringName, at: Vector3)
signal blast_received(at: Vector3, radius: float, kind: StringName)
signal bile_received(player_id: int, seconds: float)
signal objective_received(index: int, state: int)
signal gate_received(gate: String)
signal effects_received(rows: Array)
signal hurt_received(amount: float, from: Vector3)
signal ammo_received()
## Your hit landed (see [signal ZzGame.hit_landed]); only ever to the shooter.
signal hit_received(victim: int, amount: float, point: Vector3, killed: bool, headshot: bool)

## Client side: a zombie mirror was built, or let go. [param body] is its scene, already in the
## world; the client hangs a [ZzZombieView] off it.
signal npc_added(net_id: int, kind: StringName, variant: int, body: Node3D)
signal npc_removed(net_id: int, killed: bool, body: Node3D)

## Somebody pressed Enter. Server side, and the only thing this bridge does with chat.
##
## [b]The bridge carries chat and decides nothing about it.[/b] Who may say what, on which
## channel, how often and who hears it are [DotChatRouter]'s, and the router is the services
## layer's.
signal say_requested(peer_id: int, channel_id: StringName, text: String)

## A voice frame arrived. Server side; the payload is unparsed and must not be trusted —
## [method DotVoiceRouter.relay] is what stamps the speaker, from the peer id below.
signal voice_requested(peer_id: int, payload: PackedByteArray)

## Client side: one routed line, and one voice frame.
signal chat_received(wire: Dictionary)
signal voice_arrived(payload: PackedByteArray)

var game: ZzGame = null
var net: DotNetManager = null
var link: ZzNetLink = null

## Which session this process is. Zero on a server.
var local_player_id: int = 0

## Where the clock learns how long the link is, in milliseconds.
##
## dot-net never touches a transport and cannot measure it; dot-server's heartbeat already
## does ([method DotClientLink.ping_ms]). A client that feeds nothing has a clock that
## assumes an instant connection and stamps every command for a tick the server has already
## simulated — and the symptom is every command being discarded as late. Two games in this
## family shipped without a sample and read a median of an empty set.
var rtt_source: Callable = Callable()

## Where a voice frame goes on the server. Assigned by [DotGameModule] to the services
## layer's `relay_voice`, because the bridge is the only thing that names both ends.
var voice_relay_fn: Callable = Callable()

## `func(session_id: int) -> DotAvatar`: what a player looks like, asked once as they are
## seated. Assigned by the module, which is what has the identity layer; unset, or answering
## null, is the stock person, which is what everybody was before there was one.
var avatar_fn: Callable = Callable()

var _entities: Node = null

## session id -> [ZzPlayerNet].
var _behaviours: Dictionary = {}

## The next session id handed to somebody the world made itself.
##
## [b]Well above anything dot-server will issue, and a bot needs one at all because of how a
## player id is written.[/b] Every id on the wire is `u<session>`, and a player called `bot`
## parses back to session ZERO — so two bots are one entry in [member _behaviours], and
## their JOIN carries a player id that is also dot-net's broadcast address.
const FIRST_BOT_SESSION := 900000

var _next_bot_session: int = FIRST_BOT_SESSION

var _player_of_peer: Dictionary = {}
var _peer_of_player: Dictionary = {}
var _ready_peers: Dictionary = {}
## Server: peers whose READY came before their seat ([method add_player]). A client sends READY
## when its link says PLAYING, which the link decides itself after sending `loaded` on another
## channel; over ENet with loss the READY can overtake `loaded`, and a READY dropped here left
## that client waiting for a world for ever. Admitted when seated.
var _ready_unseated: Dictionary = {}

var _tick: int = 0
var _game_ticked_for: int = -1

## Server only: whether [method DotNetManager.server_tick] is on the stack, and the net ids
## let go of while it was.
##
## [b]An entity let go of mid-tick leaks a lag-compensation track, for ever.[/b]
## mg-smash-copter's finding: the world ticks inside the first player behaviour's
## `_net_simulate`, so a player removed there is unregistered while `server_tick` is still
## holding the identity list it took before simulating — and then records history for it. The registry has
## already told the history to forget each id; the record makes a fresh track for it again,
## and nothing ever forgets it a second time.
## Forgotten again here once the manager has let go of its list.
var _in_server_tick := false
var _unregistered_in_tick: Array[int] = []
var _client_ticked_for: int = -1

## The map the clients were last sent, so a late joiner is sent the same bytes.
var _map_body: PackedByteArray = PackedByteArray()

## Zombies this server replicates (instance id -> [ZzNpcNet]), and that a client draws
## (net id -> [ZzNpcNet]).
var _zombie_nets: Dictionary = {}
var _zombie_mirrors: Dictionary = {}
var _zombie_world: Node3D = null

## Whether the last thing that removed a zombie was its death, so NPC_GONE can say so.
var _died: Dictionary = {}

static var ZOMBIE_SCENE := ZzPaths.rebase("res://npcs/zz_zombie.tscn")


# --- Wiring ----------------------------------------------------------------

## [param p_game] and [param p_net], in the shape [DotGameNetcode] calls it.
func attach(p_game: Object, p_net: DotNetManager) -> DotResult:
	var world := p_game as ZzGame

	if world == null or p_net == null:
		return DotResult.fail(DotError.CODE_INVALID, "A bridge needs a world and a manager.")

	if world.authoritative != p_net.is_server:
		return DotResult.fail(
			DotError.CODE_STATE,
			"The world and the manager disagree about who is authoritative.",
			"world=%s net.is_server=%s" % [world.authoritative, p_net.is_server]
		)

	game = world
	net = p_net

	_entities = Node.new()
	_entities.name = "Entities"
	add_child(_entities)

	net.send_fn = _send

	var event := net.messages.register(
		ZzEvent.NAME, ZzEvent,
		DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_CLIENT
	)

	if not event.ok:
		return event

	var request := net.messages.register(
		ZzRequest.NAME, ZzRequest,
		DotNetMessage.Delivery.RELIABLE, DotNetMessage.Direction.TO_SERVER
	)

	if not request.ok:
		return request

	net.messages.on(ZzEvent.NAME, _on_event)
	net.messages.on(ZzRequest.NAME, _on_request)

	# Both ends. The server's tick is `server_tick` and the client's is `client_tick`, which
	# simulates what it predicts and leaves the rest to interpolation. A world still running
	# its own `_physics_process` would move every player twice.
	game.external_tick = true

	if net.is_server:
		game.player_added.connect(_on_player_added)
		game.player_removed.connect(_on_player_removed)
		game.world_rebuilt.connect(_on_world_rebuilt)
		game.round_began.connect(_on_round_began)
		game.round_over.connect(_on_round_over)
		game.phase_changed.connect(_on_phase_changed)
		game.player_died.connect(_on_player_died)
		game.player_downed.connect(func(id: StringName, by: StringName, why: StringName) -> void:
			_broadcast(ZzEvents.Kind.DOWN, ZzEvents.write_death(session_of(id), _session_or_zero(by), why, _kind_or_empty(by))))
		game.player_revived.connect(func(id: StringName, by: StringName) -> void:
			_broadcast(ZzEvents.Kind.REVIVE, ZzEvents.write_pair(session_of(id), _session_or_zero(by))))
		game.player_rescued.connect(func(id: StringName) -> void:
			_broadcast(ZzEvents.Kind.RESCUE, ZzEvents.write_player(session_of(id))))
		game.player_biled.connect(func(id: StringName, seconds: float) -> void:
			_broadcast(ZzEvents.Kind.BILE, ZzEvents.write_bile(session_of(id), seconds)))
		# To the one who was hurt: which way it came from is theirs to see.
		game.player_hurt.connect(func(id: StringName, amount: float, from: Vector3) -> void:
			var peer_id := peer_for_player(session_of(id))
			if peer_id > 0:
				_tell(peer_id, ZzEvents.Kind.HURT, ZzEvents.write_hurt(amount, from)))
		# To the one who hit: their marker and numbers are drawn from this, never predicted.
		game.hit_landed.connect(func(id: StringName, victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
			var peer_id := peer_for_player(session_of(id))
			if peer_id > 0:
				_tell(peer_id, ZzEvents.Kind.HIT, ZzEvents.write_hit(victim, amount, point, killed, headshot)))
		game.ammo_given.connect(func(id: StringName) -> void:
			var peer_id := peer_for_player(session_of(id))
			if peer_id > 0:
				_tell(peer_id, ZzEvents.Kind.AMMO, ZzEvents.write_player(session_of(id))))
		game.notice.connect(func(text: String) -> void:
			_broadcast(ZzEvents.Kind.NOTICE, ZzEvents.write_notice(text)))
		game.objective_changed.connect(func(index: int, state: StringName) -> void:
			_broadcast(ZzEvents.Kind.OBJECTIVE, ZzEvents.write_objective(index, _objective_code(state))))
		game.gate_opened.connect(func(gate: String) -> void:
			_broadcast(ZzEvents.Kind.GATE, ZzEvents.write_gate(gate)))
		game.barricade_changed.connect(func(id: String, fraction: float, intact: bool) -> void:
			_broadcast(ZzEvents.Kind.BARRICADE, ZzEvents.write_barricade(id, fraction, intact)))
		game.survival_changed.connect(func() -> void:
			var held: Dictionary = game.survival_state()
			if not held.is_empty():
				_broadcast(ZzEvents.Kind.SURVIVAL, ZzEvents.write_survival(held)))
		game.exploded.connect(func(at: Vector3, radius: float, kind: StringName) -> void:
			_broadcast(ZzEvents.Kind.BLAST, ZzEvents.write_blast(at, radius, kind)))
		# Here and not in the module: the net suite has no module, and mg-deathrun found a handout
		# wired there that reached nobody in it.
		game.player_armed.connect(announce_armed)
		game.player_disarmed.connect(func(id: StringName) -> void: announce_armed(id, &""))
		# To the one who asked, never broadcast: a refusal is that person's business.
		game.refused.connect(func(id: StringName, why: String) -> void:
			var peer_id := peer_for_player(session_of(id))
			if peer_id > 0:
				notice(peer_id, why))

		if game.pins != null:
			game.pins.pinned.connect(func(victim: StringName, kind: StringName, attacker: int) -> void:
				_broadcast(ZzEvents.Kind.PIN, ZzEvents.write_pin(session_of(victim), _npc_net_id(attacker), kind)))
			game.pins.released.connect(func(victim: StringName, _kind: StringName, why: StringName) -> void:
				_broadcast(ZzEvents.Kind.UNPIN, ZzEvents.write_death(session_of(victim), 0, why)))

		if game.hazards != null:
			game.hazards.area_added.connect(func(id: int, kind: StringName, at: Vector3, radius: float, seconds: float) -> void:
				_broadcast(ZzEvents.Kind.HAZARD, ZzEvents.write_hazard(id, kind, at, radius, seconds)))
			game.hazards.area_ended.connect(func(id: int) -> void:
				_broadcast(ZzEvents.Kind.HAZARD_GONE, ZzEvents.write_id(id)))
			game.hazards.launched.connect(func(id: int, kind: StringName, from: Vector3, velocity: Vector3) -> void:
				_broadcast(ZzEvents.Kind.THROW, ZzEvents.write_throw(id, kind, from, velocity)))
			game.hazards.landed.connect(func(id: int, kind: StringName, at: Vector3) -> void:
				_broadcast(ZzEvents.Kind.LANDED, ZzEvents.write_landed(id, kind, at)))

		if game.loot != null:
			game.loot.added.connect(func(id: int, kind: StringName, item: StringName, at: Vector3) -> void:
				_broadcast(ZzEvents.Kind.LOOT, ZzEvents.write_loot(id, kind, item, at)))
			game.loot.removed.connect(func(id: int, by: StringName) -> void:
				_broadcast(ZzEvents.Kind.LOOT_GONE, ZzEvents.write_loot_gone(id, _session_or_zero(by))))

		if game.boxes != null:
			game.boxes.opened.connect(func(id: StringName, type_id: StringName, title: String, message: String) -> void:
				_broadcast(ZzEvents.Kind.BOX, ZzEvents.write_box(session_of(id), type_id, title, message)))
			game.boxes.effects_changed.connect(func() -> void:
				_broadcast(ZzEvents.Kind.EFFECTS, ZzEvents.write_effects(game.boxes.effects_summary())))

		if game.horde != null and game.horde.spawner != null:
			game.horde.spawner.spawned.connect(_on_zombie_spawned)
			game.horde.spawner.removed.connect(_on_zombie_removed)
			game.horde.spawner.died.connect(func(npc: DotNpcInstance, _by: StringName) -> void:
				_died[npc.instance_id] = true)

		if game.spectate != null:
			game.spectate.view_changed.connect(_on_spectate_changed)

		_wire_lag_compensation()

	return DotResult.success(true)


## Hands dot-combat the two callables that make lag compensation real.
##
## [b]Two lines, and without them the setting is a lie.[/b] dot-combat names no dot-net type
## — the whole point of the seam — so it takes a rewind and a restore as [Callable]s and,
## unset, says so once at boot and then resolves every shot against the present anyway. A
## game that left the flag on and the callables unset would report lag compensation as
## enabled, do nothing, and cost the next reader an afternoon; this family calls that
## "produced correctly and consumed by nothing" and it is its second most repeated bug.
##
## dot-net already records the history: `DotNetManager.server_tick` calls
## `history.record(identities, tick)` once a snapshot. There is nothing to build.
##
## [b]The shooter is not excluded, and that is safe here rather than an oversight.[/b]
## `DotNetHistory.rewind` can leave one entity alone so that rewinding does not move the
## shooter's own muzzle — but `resolve_shot` fixes `shot.origin` before it rewinds anything,
## so the muzzle has already been decided, and the resolver refuses self damage separately.
## What excluding would buy is one fewer entity moved and put back.
func _wire_lag_compensation() -> void:
	if game.combat == null or net == null:
		return

	if game.combat.config != null:
		game.combat.config.lag_compensation = true

	game.combat.rewind_fn = func(target_tick: float) -> void:
		var _rewound := net.history.rewind(
			net.registry.all(), int(target_tick), net.clock.tick
		)

	game.combat.restore_fn = func() -> int:
		return net.history.restore()

	DotLog.debug(CHANNEL, "lag compensation is wired to the netcode's history", {
		"max_rewind_ms": game.combat.config.max_rewind_ms if game.combat.config != null else 0.0,
	})


## Opens the link under [param parent], whose NAME is half the RPC routing.
##
## A [DotServer] on one end and a [DotClientLink] on the other, both called `Server`, with
## this node under each: Godot routes an RPC by the receiver's node path, so a link opened
## anywhere else is addressed by a path the other end does not have and every message lands
## nowhere, with no error on either side.
func open_link(parent: Node) -> void:
	if parent == null or link != null:
		return

	link = ZzNetLink.attached_to(parent, self, net != null and net.is_server)


## How every dot-net message reaches a peer.
##
## [b]Routed by DELIVERY, not by kind.[/b] Snapshots are unreliable and go on the snapshot
## call; everything else is reliable, and which reliable call it is depends on which end is
## sending — the server has events, the client has requests. Sending them all as events
## works on a server and silently drops every client request, which is a client that
## connects, draws, and can never ask for anything.
func _send(peer_id: int, payload: PackedByteArray, delivery: int) -> void:
	if link == null:
		return

	if delivery == DotNetMessage.Delivery.UNRELIABLE:
		link.send_snapshot(peer_id, payload)
	elif net.is_server:
		link.send_event(peer_id, payload)
	else:
		link.send_request(payload)


# --- Identity --------------------------------------------------------------

static func player_key(session_id: int) -> StringName:
	return StringName("u%d" % session_id)


static func session_of(id: StringName) -> int:
	return String(id).trim_prefix("u").to_int()


## A candidate id's session, or 0 for anything that is not a player (a zombie kind, empty).
static func _session_or_zero(id: StringName) -> int:
	return session_of(id) if String(id).begins_with("u") else 0


## What a killer is when it is not a player: a zombie kind, or empty.
static func _kind_or_empty(id: StringName) -> StringName:
	return &"" if id == &"" or String(id).begins_with("u") else id


static func _objective_code(state: StringName) -> int:
	return {&"waiting": 0, &"holding": 1, &"done": 2}.get(state, 0)


func peer_for_player(session_id: int) -> int:
	return int(_peer_of_player.get(session_id, 0))


func player_for_peer(peer_id: int) -> int:
	return int(_player_of_peer.get(peer_id, 0))


# --- Server: players -------------------------------------------------------

## Puts a connected peer into the game. What [DotGameRoster] calls.
func add_player(peer_id: int, session_id: int, display_name: String) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server adds players.")

	if peer_id > 0:
		# FIRST, because `game.add_player` emits `player_added` and the handler has to be
		# able to find which peer this player belongs to.
		_player_of_peer[peer_id] = session_id
		_peer_of_player[session_id] = peer_id

	var player := game.add_player(player_key(session_id), display_name)

	if player == null:
		_player_of_peer.erase(peer_id)
		_peer_of_player.erase(session_id)
		return DotResult.fail(DotError.CODE_STATE, "The game refused the player.")

	if _ready_unseated.has(peer_id):
		_ready_unseated.erase(peer_id)
		_admit(peer_id)

	return DotResult.success(player)


## Somebody the world drives itself: a stand-in, or a test's player.
##
## [b]The same entity a peer gets, with a peer id of zero.[/b] A bot is replicated, scored
## and crushed exactly like a person — what it does not have is a socket — and that is the
## whole of the difference.
func add_bot(display_name: String, team: int = 0) -> ZzPlayer:
	if net == null or not net.is_server or game == null:
		return null

	var session_id := _next_bot_session
	_next_bot_session += 1

	var player := game.add_player(player_key(session_id), display_name, team)

	if player == null:
		return null

	player.is_bot = true
	return player


func remove_peer(peer_id: int) -> void:
	_ready_unseated.erase(peer_id)

	if _player_of_peer.has(peer_id):
		remove_player(int(_player_of_peer[peer_id]))


## Removes a player whether or not a peer is behind it — a bot has none.
func remove_player(session_id: int) -> void:
	if not _behaviours.has(session_id):
		return

	var peer_id := peer_for_player(session_id)
	var was_ready := _ready_peers.has(peer_id)

	_player_of_peer.erase(peer_id)
	_peer_of_player.erase(session_id)
	_ready_peers.erase(peer_id)

	# Released BEFORE the game is told: `game.remove_player` emits `player_removed`, which
	# `_on_player_removed` answers by releasing the entity and broadcasting the LEAVE.
	# Releasing first empties `_behaviours`, so that handler finds nothing and this stays
	# the one place a leaving player is announced.
	_release_entity(session_id)
	game.remove_player(player_key(session_id))

	if net != null and peer_id > 0:
		if was_ready:
			net.remove_peer(peer_id)

		if net.interest != null:
			net.interest.forget_peer(peer_id)

	_broadcast(ZzEvents.Kind.LEAVE, ZzEvents.write_player(session_id))
	roster_changed.emit(session_id)


func _on_player_added(id: StringName) -> void:
	if net == null or not net.is_server:
		return

	var session_id := session_of(id)

	if _behaviours.has(session_id):
		return

	# [b]Every id on the wire is `u<session>`, and anything else parses back to zero.[/b] A
	# world that added a player called `bot` would replicate it under session 0 — which is
	# also dot-net's broadcast address — and a second one would silently replace the first
	# in this table. Refused with a line rather than accepted quietly: the symptom otherwise
	# is one stand-in playing and the other standing still for ever.
	if player_key(session_id) != id:
		DotLog.warn(CHANNEL, "a player whose id is not a session key is not replicated", {
			"id": String(id), "hint": "use add_bot() or ZzNetBridge.player_key()",
		})
		return

	var player: ZzPlayer = game.players.get(id)

	if player == null:
		return

	var identity := _build_entity(player, peer_for_player(session_id))
	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a player", {"error": str(registered.error)})
		return

	# Before the JOIN, so the first thing anybody hears about this person is their face.
	if player.avatar == null and avatar_fn.is_valid():
		var avatar: Variant = avatar_fn.call(session_id)
		player.avatar = avatar as DotAvatar if avatar is DotAvatar else null

	_broadcast(ZzEvents.Kind.JOIN, _join_body(session_id))
	roster_changed.emit(session_id)


func _on_player_removed(id: StringName) -> void:
	var session_id := session_of(id)

	if _behaviours.has(session_id):
		# The game removed them itself; the entity and the LEAVE are still ours.
		_release_entity(session_id)
		_broadcast(ZzEvents.Kind.LEAVE, ZzEvents.write_player(session_id))
		roster_changed.emit(session_id)


func _build_entity(player: ZzPlayer, peer_id: int) -> DotNetIdentity:
	# The behaviour is added BEFORE the identity: [DotNetIdentity] collects behaviours in
	# `_ready` by walking the subtree, and one added afterwards would never be found.
	var behaviour := ZzPlayerNet.new()
	behaviour.name = "Net"
	behaviour.player = player
	behaviour.bridge = self
	player.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = peer_id
	# SHARED: the server corrects, the owner predicts. SERVER would put a player's own
	# movement a round trip behind their keys, and a survivor running from a crowd would feel it.
	identity.authority = DotNetIdentity.Authority.SHARED
	# Relevant to everybody, always: a team that cannot see a teammate's outline across a map
	# cannot go to them, and there are four of them, not forty.
	identity.always_relevant = true
	player.add_child(identity)

	var session_id := session_of(player.player_id)
	_behaviours[session_id] = behaviour

	# Only ever emitted on a mirror, where the snapshot is what says a weapon was used.
	behaviour.weapon_used.connect(func(times: int, kind: int) -> void:
		weapon_used_by.emit(session_id, times, kind)
	)
	return identity


## Server side. See [member _in_server_tick] for why an id let go of mid-tick is remembered.
func _unregister(net_id: int) -> void:
	net.registry.unregister(net_id)

	if _in_server_tick:
		_unregistered_in_tick.append(net_id)


func _release_entity(session_id: int) -> void:
	var behaviour: ZzPlayerNet = _behaviours.get(session_id)
	_behaviours.erase(session_id)

	if behaviour == null or behaviour.identity == null or net == null:
		return

	_unregister(behaviour.identity.net_id)


# --- Server: the world -----------------------------------------------------

## A new map: the whole document, to everybody, before anything that stands on it.
func _on_world_rebuilt() -> void:
	if net == null or not net.is_server or game.map == null or game.map.doc.is_empty():
		return

	var encoded := ZzMapDoc.encode(game.map.doc)

	if encoded.size() > ZzMapDoc.WIRE_LIMIT:
		# Sent anyway: a client on a native transport will take it, and the line says why a
		# browser does not. A WebSocket message past its outbound buffer is never delivered.
		DotLog.warn(CHANNEL, "a map is larger than a browser can be sent in one message", {
			"map": String(game.map.id()), "bytes": encoded.size(), "limit": ZzMapDoc.WIRE_LIMIT,
		})

	_map_body = ZzEvents.write_map(encoded)
	_broadcast(ZzEvents.Kind.MAP, _map_body)


# --- Server: the round -----------------------------------------------------

func _on_round_began(number: int, _map_id: StringName) -> void:
	_broadcast(ZzEvents.Kind.ROUND, ZzEvents.write_round(number, true, false))


func _on_round_over(number: int, won: bool, why: String) -> void:
	var next_in := game.match_node.rules.intermission_sec if game.match_node != null and game.match_node.rules != null else -1.0
	_broadcast(ZzEvents.Kind.ROUND, ZzEvents.write_round(number, false, won, why, next_in, String(game.next_map_id)))


func _on_phase_changed(phase: int) -> void:
	_broadcast(ZzEvents.Kind.PHASE, ZzEvents.write_phase(phase))


func _on_player_died(player_id: StringName, by: StringName, why: StringName) -> void:
	_broadcast(ZzEvents.Kind.DEATH, ZzEvents.write_death(
		session_of(player_id), _session_or_zero(by), why, _kind_or_empty(by)
	))


## A view changed on the server. Told to its owner and to nobody else.
##
## [b]To the one peer, because a camera is private.[/b] Who somebody is watching is a fact
## about them that nobody else has any business knowing — and a stand-in, whose peer is
## zero, is told nothing, which `_tell` guarantees rather than this.
func _on_spectate_changed(player_id: StringName) -> void:
	if game == null or game.spectate == null or game.spectate.manager == null:
		return

	var session_id := session_of(player_id)
	var peer_id := peer_for_player(session_id)

	if peer_id <= 0 or not _ready_peers.has(peer_id):
		return

	var view := game.spectate.manager.view(String(player_id))
	var target := session_of(StringName(view.target)) if view.target != "" else 0
	var killer := session_of(StringName(view.killer)) if view.killer != "" else 0

	_tell(peer_id, ZzEvents.Kind.SPECTATE, ZzEvents.write_spectate(
		session_id, int(view.mode), target, killer, view.death_position
	))


## Says what somebody was handed.
func announce_armed(player_id: StringName, weapon_id: StringName) -> void:
	_broadcast(ZzEvents.Kind.ARMED, ZzEvents.write_armed(session_of(player_id), weapon_id))


# --- Server: the tick ------------------------------------------------------

func server_tick(tick: int) -> void:
	_tick = tick
	_game_ticked_for = -1

	if net != null:
		_in_server_tick = true
		net.server_tick(tick)
		_in_server_tick = false

		for net_id in _unregistered_in_tick:
			if not net.registry.has(net_id):
				net.history.forget(net_id)

		_unregistered_in_tick.clear()

	# Belt and braces: `net.server_tick` drives the entities, and the first player behaviour
	# through calls `ensure_game_ticked`. A server with nobody on it has no behaviours at
	# all, and a world that only ticked when somebody was connected is a server whose round
	# clock stops between players — which looks like the server having hung.
	ensure_game_ticked(tick)

	if tick % CLOCK_EVERY == 0:
		_broadcast(ZzEvents.Kind.CLOCK, _clock_body())
		var held: Dictionary = game.survival_state()
		if not held.is_empty():
			_broadcast(ZzEvents.Kind.SURVIVAL, ZzEvents.write_survival(held))


func _clock_body() -> PackedByteArray:
	var index := game.current_objective()
	var state := _objective_code(game.objective_states[index]) if index >= 0 else 0
	var ends := maxf(game.objective_progress[index] - game.now(), 0.0) if index >= 0 and state == 1 else 0.0
	return ZzEvents.write_clock(
		game.round_number, game.phase, game.phase_elapsed, game.survival_elapsed,
		game.survival_goal, game.alive_on(ZzGame.SURVIVORS), game.sides_are_playable(),
		index, state, ends
	)


func ensure_game_ticked(tick: int) -> void:
	if _game_ticked_for == tick or game == null:
		return

	_game_ticked_for = tick

	for session_id in _behaviours:
		var behaviour: ZzPlayerNet = _behaviours[session_id]

		# Only what a peer sent. A bot has no peer and is driven by the game itself, and an
		# empty command applied over the top of that would stand it still.
		if behaviour.player != null and behaviour.identity != null \
				and behaviour.identity.owner_peer_id > 0:
			behaviour.player.controller.apply_command(behaviour.last_move.duplicate_command())
			behaviour.player.wanted_slot = behaviour.last_slot

	game.tick_once(tick)

# --- The client tick -------------------------------------------------------

func client_tick(tick: int, command: DotFpsCommand, slot: int = 0, actions: int = 0) -> void:
	if net == null or net.is_server or game == null:
		return

	_tick = tick

	var packet := ZzNetCommand.new()
	packet.tick = tick
	packet.delta = net.clock.tick_duration()
	packet.move = command if command != null else DotFpsCommand.new()
	packet.slot = slot
	packet.actions = actions

	# Into the local history BEFORE predicting: reconciliation replays it.
	net.local_inputs().push(packet)

	# The behaviour simulates from `last_move` on a fresh tick and on a replayed one alike —
	# the predictor's replay sets it through `_net_apply_input`, and this is the fresh tick's
	# equivalent.
	var mine: ZzPlayerNet = _behaviours.get(local_player_id)

	if mine != null:
		mine.last_move = packet.move
		mine.last_slot = slot

		if mine.player != null:
			mine.player.wanted_slot = slot

	if link != null:
		var payload := net.encode_ack()
		var writer := DotNetWriter.new()
		DotNetInput.write_batch(writer, _input_copies(packet))
		payload.append_array(writer.to_bytes())
		link.send_input(payload)

	# One predicted player, and nothing else: everybody else is drawn from snapshots.
	if _client_ticked_for != tick:
		_client_ticked_for = tick

		for identity in net.registry.predicted():
			for behaviour in identity.behaviours:
				behaviour._net_simulate(tick, net.clock.tick_duration())

		# The clock a client shows, advanced between the twice-a-second messages that
		# correct it. Without this the timers tick in half-second steps.
		game.phase_elapsed += net.clock.tick_duration()

		if game.phase == ZzGame.Phase.PLAY and game.is_survival():
			game.survival_elapsed += net.clock.tick_duration()

		if game.remote_seconds_left > 0.0:
			game.remote_seconds_left = maxf(game.remote_seconds_left - net.clock.tick_duration(), 0.0)

		if game.remote_next_round > 0.0:
			game.remote_next_round = maxf(game.remote_next_round - net.clock.tick_duration(), 0.0)

		# The hold's stage clock, the same way.
		if float(game.remote_survival.get("left", -1.0)) > 0.0:
			game.remote_survival["left"] = maxf(float(game.remote_survival["left"]) - net.clock.tick_duration(), 0.0)


# --- Receiving -------------------------------------------------------------

func receive_snapshot(payload: PackedByteArray) -> DotResult:
	if net == null or net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only a client receives these.")

	if rtt_source.is_valid():
		net.stats.note_rtt(float(rtt_source.call()))

	return net.receive_snapshot(payload)


## [param packet] and the commands before it from the local replay history, oldest first,
## for one input packet. See [constant INPUT_COPIES].
func _input_copies(packet: DotNetInput) -> Array:
	var batch: Array = Array(net.local_inputs().recent(INPUT_COPIES, packet.tick - 1))
	batch = batch.slice(maxi(0, batch.size() - (INPUT_COPIES - 1)))
	batch.append(packet)
	return batch


func receive_input(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null or not net.is_server:
		return DotResult.fail(DotError.CODE_FORBIDDEN, "Only the server takes input.")

	if not _player_of_peer.has(peer_id):
		return DotResult.fail(DotError.CODE_FORBIDDEN, "That peer has no player.")

	if payload.size() <= ACK_BYTES:
		return DotResult.fail(DotError.CODE_PARSE, "Input packet is too short.")

	net.receive_ack_payload(peer_id, payload.slice(0, ACK_BYTES))

	# A batch: this tick's command and the ones before it (see [constant INPUT_COPIES]).
	# Copies of ticks already simulated are skipped rather than pushed, or each would count
	# as a late input; the packet's own tick is always pushed, so a late one still counts.
	var batch := DotNetInput.read_batch(
		DotNetReader.new(payload.slice(ACK_BYTES)),
		func() -> DotNetInput: return ZzNetCommand.new()
	)
	if batch.is_empty():
		return DotResult.fail(DotError.CODE_PARSE, "Input packet carries no command.")
	var buffer := net.input_buffer_for(peer_id)
	var newest := batch[batch.size() - 1]
	var pushed := DotResult.success(false)
	for input in batch:
		if input != newest and input.tick <= buffer.last_consumed_tick():
			continue
		pushed = buffer.push(input)
	return pushed


## Text for one player: a refusal, a rate limit, a command's reply.
##
## [b]To the one person who asked, and that is the whole reason this is a method.[/b] "You
## are talking too fast" and "you are gagged" are the two commonest things a server says,
## and both are nobody else's business — a broadcast refusal is a punishment announced to
## everybody.
func notice(peer_id: int, text: String) -> void:
	_tell(peer_id, ZzEvents.Kind.NOTICE, ZzEvents.write_notice(text))


## One routed line to one peer. What [DotGameServices] sends through, via the link.
func send_chat(peer_id: int, wire: Dictionary) -> void:
	_tell(peer_id, ZzEvents.Kind.CHAT, ZzEvents.write_chat(wire))


## A voice frame, in whichever direction.
##
## [b]Not a [ZzEvent].[/b] Voice is fifty packets a second and every event here is reliable,
## so a talk spurt would put a hundred retransmittable messages in front of a down. It also does not go through [DotNetManager]: the message registry seals a
## message set and hashes it, and adding a fifty-hertz opaque blob buys nothing — the packet
## has its own header, sequence and validation in [DotVoicePacket].
func receive_voice(peer_id: int, payload: PackedByteArray) -> DotResult:
	if payload.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "An empty voice frame.")

	if net != null and net.is_server:
		if peer_id <= 0 or player_for_peer(peer_id) == 0:
			# A peer with nobody in the world. Refused rather than relayed: the router
			# stamps the speaker from this id, so relaying one that belongs to nobody puts
			# a voice in the game with no name on it.
			return DotResult.fail(
				DotError.CODE_FORBIDDEN, "That peer has nobody in the world."
			)

		# [b]One path or the other, never both.[/b] [DotGameModule] assigns
		# `voice_relay_fn` to the services layer's `relay_voice`; a game that ALSO connected
		# `voice_requested` to the same router would relay every frame twice — a doubled
		# talk spurt, a doubled rate limit, and a sequence number the jitter buffer sees go
		# backwards.
		if voice_relay_fn.is_valid():
			voice_relay_fn.call(peer_id, payload)
		else:
			voice_requested.emit(peer_id, payload)

		return DotResult.success(null)

	voice_arrived.emit(payload)
	return DotResult.success(null)


func receive_event(payload: PackedByteArray) -> DotResult:
	if net == null:
		return DotResult.fail(DotError.CODE_STATE, "No manager.")

	return net.receive(payload, 1)


func receive_request(peer_id: int, payload: PackedByteArray) -> DotResult:
	if net == null:
		return DotResult.fail(DotError.CODE_STATE, "No manager.")

	return net.receive(payload, peer_id)


# --- Server: what a joining peer is told -----------------------------------

func _on_request(message: DotNetMessage) -> void:
	var ask := message as ZzRequest

	if ask == null or net == null or not net.is_server:
		return

	# [b]From the message, which dot-net stamped from the TRANSPORT.[/b] A peer id inside a
	# body is a claim; `sender_peer_id` is what the socket said, which is the only version
	# of it a server may act on.
	var peer_id := ask.sender_peer_id

	match ask.kind:
		ZzEvents.Ask.READY:
			_admit(peer_id)
		ZzEvents.Ask.SAY:
			var said := ZzEvents.read_say(ask.reader())

			if bool(said["ok"]):
				# Emitted rather than acted on: everything about what a line means is
				# [DotChatRouter]'s, and the router is the module's.
				say_requested.emit(
					peer_id, StringName(str(said["channel"])), str(said["text"])
				)
		ZzEvents.Ask.SPECTATE:
			var step := ZzEvents.read_ask_spectate(ask.reader())

			if bool(step["ok"]):
				_spectate_step(peer_id, int(step["direction"]))


## Somebody who is out asked to look at somebody else. The server's list, the server's rule.
##
## [b]A refusal goes back as a notice rather than being dropped.[/b] "This server only lets
## you watch your own side" is the answer to a key that did nothing, and a key that silently
## does nothing is reported as broken.
func _spectate_step(peer_id: int, direction: int) -> void:
	var session_id := player_for_peer(peer_id)

	if session_id == 0 or game.spectate == null:
		return

	var moved: DotResult = game.spectate.step(player_key(session_id), direction)

	if not moved.ok:
		notice(peer_id, moved.error.message)


## Everything in the world, to one peer, once its own copy exists.
##
## [b]On READY and not on connect, and the difference is a whole join's worth of
## messages.[/b] dot-server's signon finishes and THEN the client builds its scene; a server
## that started talking at connect is one whose JOIN and MAP land on a node that does not
## exist yet and are lost, one "Node not found" per call.
func _admit(peer_id: int) -> void:
	if peer_id <= 0:
		return

	if not _player_of_peer.has(peer_id):
		_ready_unseated[peer_id] = true
		return

	_ready_peers[peer_id] = true

	if not net.peers().has(peer_id):
		net.add_peer(peer_id)

	var session_id := int(_player_of_peer[peer_id])

	_tell(peer_id, ZzEvents.Kind.HELLO, ZzEvents.write_hello(
		session_id, game.tick_rate, net.clock.tick, game.config.difficulty, game.config.max_incaps
	))

	# The map, before anything that stands on it.
	if not _map_body.is_empty():
		_tell(peer_id, ZzEvents.Kind.MAP, _map_body)

	for other in _behaviours.keys():
		_tell(peer_id, ZzEvents.Kind.JOIN, _join_body(int(other)))

	_tell_the_world(peer_id)
	_tell(peer_id, ZzEvents.Kind.PHASE, ZzEvents.write_phase(game.phase))
	_tell(peer_id, ZzEvents.Kind.CLOCK, _clock_body())


## Everything already in the world, to a joiner: every zombie, everything on the ground, every
## pool, who is held, what is done, which gates are open, what the boxes are doing.
func _tell_the_world(peer_id: int) -> void:
	for instance_id in _zombie_nets.keys():
		var behaviour: ZzNpcNet = _zombie_nets[instance_id]
		if behaviour.identity != null and behaviour.npc != null and behaviour.npc.is_alive():
			_tell(peer_id, ZzEvents.Kind.NPC, ZzEvents.write_npc(
				behaviour.identity.net_id, behaviour.npc.def.id, behaviour.body.variant, behaviour.npc.position()))

	if game.loot != null:
		for id: int in game.loot.entries:
			var e: Dictionary = game.loot.entries[id]
			_tell(peer_id, ZzEvents.Kind.LOOT, ZzEvents.write_loot(id, e["kind"], e["item"], e["at"]))

	if game.hazards != null:
		for id: int in game.hazards.areas:
			var a: Dictionary = game.hazards.areas[id]
			_tell(peer_id, ZzEvents.Kind.HAZARD, ZzEvents.write_hazard(id, a["kind"], a["at"], float(a["radius"]),
				maxf(float(a["until"]) - game.now(), 0.0)))

	if game.pins != null:
		for victim: StringName in game.pins.pins:
			var held: Dictionary = game.pins.pins[victim]
			_tell(peer_id, ZzEvents.Kind.PIN, ZzEvents.write_pin(session_of(victim), _npc_net_id(int(held["entity"])), held["kind"]))

	for index in game.objective_states.size():
		if game.objective_states[index] != &"waiting":
			_tell(peer_id, ZzEvents.Kind.OBJECTIVE, ZzEvents.write_objective(index, _objective_code(game.objective_states[index])))

	if game.horde != null:
		for gate in game.horde.open_gates:
			_tell(peer_id, ZzEvents.Kind.GATE, ZzEvents.write_gate(gate))

	for id: String in game.barricades:
		var b: Dictionary = game.barricades[id]
		if float(b["health"]) < float(b["max"]) or not bool(b["intact"]):
			_tell(peer_id, ZzEvents.Kind.BARRICADE, ZzEvents.write_barricade(id, float(b["health"]) / float(b["max"]), bool(b["intact"])))

	var held: Dictionary = game.survival_state()
	if not held.is_empty():
		_tell(peer_id, ZzEvents.Kind.SURVIVAL, ZzEvents.write_survival(held))

	if game.boxes != null:
		_tell(peer_id, ZzEvents.Kind.EFFECTS, ZzEvents.write_effects(game.boxes.effects_summary()))


func _join_body(session_id: int) -> PackedByteArray:
	var behaviour: ZzPlayerNet = _behaviours.get(session_id)

	if behaviour == null or behaviour.identity == null or behaviour.player == null:
		return PackedByteArray()

	return ZzEvents.write_join(
		session_id,
		behaviour.identity.net_id,
		behaviour.player.display_name,
		game.team_of(behaviour.player.player_id),
		behaviour.player.avatar
	)


## Tells everybody who somebody is now: a profile that arrived after they were seated, a
## wardrobe change, an operator's rename. Server only.
##
## [b]Through JOIN, which a client already applies to a player it has.[/b] A second message
## for "this person changed" would be a second thing a joiner has to be told and a second
## order two of them can arrive in; a JOIN is idempotent and already carries all of it.
## An empty [param display_name] keeps the one they have.
func refresh_player(session_id: int, display_name: String, avatar: DotAvatar) -> bool:
	if net == null or not net.is_server or game == null:
		return false

	var player: ZzPlayer = game.players.get(player_key(session_id))

	if player == null or not _behaviours.has(session_id):
		return false

	if display_name != "":
		player.display_name = display_name

	player.avatar = avatar
	_broadcast(ZzEvents.Kind.JOIN, _join_body(session_id))
	return true


## To every peer that has said it is ready, and to nobody else.
##
## [b]An empty body is dropped rather than sent.[/b] It means an encoder was handed
## something that had already gone — a player whose entity was released before the LEAVE was
## written — and a zero-length event decodes on the far end as a valid message about
## nothing, which is the truncation bug this family has already paid for once.
func _broadcast(kind: int, body: PackedByteArray) -> void:
	if net == null or not net.is_server or body.is_empty():
		return

	for peer_id in _ready_peers.keys():
		_tell(int(peer_id), kind, body)


## One peer, and never zero.
##
## `net.send(msg, 0)` is a BROADCAST in dot-net, so a helper that passed a missing peer id
## straight through would send one player's private message to everybody. game-hungario
## shipped exactly that.
func _tell(peer_id: int, kind: int, body: PackedByteArray) -> void:
	if peer_id <= 0 or net == null or body.is_empty():
		return

	net.send(ZzEvent.new(kind, body), peer_id)


# --- Client: what it does with all that ------------------------------------

func ask_ready() -> void:
	_ask(ZzEvents.Ask.READY, PackedByteArray([0]))


## Says something. The server decides what it means and who hears it.
func ask_say(channel_id: StringName, text: String) -> void:
	if text.strip_edges() == "":
		return

	_ask(ZzEvents.Ask.SAY, ZzEvents.write_say(channel_id, text))


## Out, and asking to watch somebody else: +1 next, -1 previous, 0 the other camera.
func ask_spectate(direction: int) -> void:
	_ask(ZzEvents.Ask.SPECTATE, ZzEvents.write_ask_spectate(direction))


## Sends one encoded voice packet to the server. Client side.
func send_voice(payload: PackedByteArray) -> void:
	if link != null and net != null and not net.is_server:
		link.send_voice(1, payload)


func _ask(kind: int, body: PackedByteArray) -> void:
	if net == null or net.is_server:
		return

	net.send(ZzRequest.new(kind, body), 1)


func _on_event(message: DotNetMessage) -> void:
	var event := message as ZzEvent

	if event == null or game == null or net == null or net.is_server:
		return

	var reader := event.reader()

	match event.kind:
		ZzEvents.Kind.HELLO:
			_apply_hello(reader)
		ZzEvents.Kind.MAP:
			_apply_map(reader)
		ZzEvents.Kind.JOIN:
			_apply_join(reader)
		ZzEvents.Kind.LEAVE:
			var session_id := ZzEvents.read_player(reader)
			_release_entity(session_id)
			game.remove_player(player_key(session_id))
			roster_changed.emit(session_id)
		ZzEvents.Kind.TEAM:
			var side := ZzEvents.read_team(reader)

			if bool(side["ok"]):
				var id := player_key(int(side["player_id"]))
				game.sides[id] = int(side["team"])

				if game.players.has(id):
					(game.players[id] as ZzPlayer).team = int(side["team"])

				roster_changed.emit(int(side["player_id"]))
		ZzEvents.Kind.CLOCK:
			_apply_clock(reader)
		ZzEvents.Kind.ROUND:
			var round_info := ZzEvents.read_round(reader)

			if bool(round_info["ok"]):
				game.round_number = int(round_info["round"])

				game.remote_next_round = -1.0 if bool(round_info["began"]) else float(round_info["next_in"])
				game.remote_next_map = &"" if bool(round_info["began"]) else StringName(str(round_info["next_map"]))

				if bool(round_info["began"]):
					game.phase_elapsed = 0.0
					game.survival_elapsed = 0.0
					game._reset_objectives()

				round_changed.emit(
					int(round_info["round"]),
					bool(round_info["began"]),
					bool(round_info["won"]),
					str(round_info["why"])
				)
		ZzEvents.Kind.PHASE:
			var moved := ZzEvents.read_phase(reader)

			if bool(moved["ok"]):
				game.phase = int(moved["phase"])
				game.phase_elapsed = 0.0

				phase_received.emit(int(moved["phase"]))
		ZzEvents.Kind.DEATH:
			var death := ZzEvents.read_death(reader)

			if bool(death["ok"]):
				death_received.emit(
					int(death["player_id"]), int(death["by"]), death["why"], death["by_kind"]
				)
		ZzEvents.Kind.ARMED:
			var armed := ZzEvents.read_armed(reader)

			if bool(armed["ok"]):
				# Noted on the player here rather than by whoever listens, so every client
				# draws the gun in a watched player's hand: see `ZzPlayer.dealt`.
				var dealt_to: ZzPlayer = game.players.get(player_key(int(armed["player_id"]))) \
					if game != null else null
				if dealt_to != null:
					if armed["weapon_id"] == &"":
						dealt_to.dealt.clear()
					else:
						dealt_to.note_dealt(armed["weapon_id"], game.round_number)
				armed_received.emit(int(armed["player_id"]), armed["weapon_id"])
		ZzEvents.Kind.CHAT:
			var wire := ZzEvents.read_chat(reader)

			if bool(wire["ok"]):
				chat_received.emit(wire)
		ZzEvents.Kind.NOTICE:
			var text := ZzEvents.read_notice(reader)

			if bool(text["ok"]):
				notice_received.emit(str(text["text"]))
		ZzEvents.Kind.SPECTATE:
			var view := ZzEvents.read_spectate(reader)

			if bool(view["ok"]) and game.spectate != null:
				game.spectate.apply_view(
					player_key(int(view["viewer"])),
					int(view["mode"]),
					player_key(int(view["target"])) if int(view["target"]) != 0 else &"",
					player_key(int(view["killer"])) if int(view["killer"]) != 0 else &"",
					view["death_at"]
				)
				spectate_received.emit(
					int(view["viewer"]), int(view["mode"]), int(view["target"])
				)
		_:
			_on_world_event(event.kind, reader)


## The events about what happens in the world rather than who is in it. Client side.
func _on_world_event(kind: int, reader: DotNetReader) -> void:
	match kind:
		ZzEvents.Kind.NPC:
			var info := ZzEvents.read_npc(reader)
			if bool(info["ok"]):
				_mirror_zombie(info)
		ZzEvents.Kind.NPC_GONE:
			var gone := ZzEvents.read_npc_gone(reader)
			if bool(gone["ok"]):
				_drop_zombie_mirror(int(gone["net_id"]), bool(gone["killed"]), gone["death"])
		ZzEvents.Kind.DOWN:
			var down := ZzEvents.read_death(reader)
			if bool(down["ok"]):
				downed_received.emit(int(down["player_id"]), int(down["by"]), down["why"], down["by_kind"])
		ZzEvents.Kind.REVIVE:
			var up := ZzEvents.read_pair(reader)
			if bool(up["ok"]):
				revived_received.emit(int(up["player_id"]), int(up["other"]))
		ZzEvents.Kind.RESCUE:
			rescued_received.emit(ZzEvents.read_player(reader))
		ZzEvents.Kind.PIN:
			var pin := ZzEvents.read_pin(reader)
			if bool(pin["ok"]):
				pin_received.emit(int(pin["player_id"]), int(pin["npc"]), pin["kind"])
		ZzEvents.Kind.UNPIN:
			var free := ZzEvents.read_death(reader)
			if bool(free["ok"]):
				unpin_received.emit(int(free["player_id"]), free["why"])
		ZzEvents.Kind.LOOT:
			var loot := ZzEvents.read_loot(reader)
			if bool(loot["ok"]):
				loot_added.emit(int(loot["id"]), loot["kind"], loot["item"], loot["at"])
		ZzEvents.Kind.LOOT_GONE:
			var taken := ZzEvents.read_loot_gone(reader)
			if bool(taken["ok"]):
				loot_removed.emit(int(taken["id"]), int(taken["by"]))
		ZzEvents.Kind.BOX:
			var box := ZzEvents.read_box(reader)
			if bool(box["ok"]):
				box_received.emit(int(box["player_id"]), box["type"], str(box["title"]), str(box["message"]))
		ZzEvents.Kind.HAZARD:
			var h := ZzEvents.read_hazard(reader)
			if bool(h["ok"]):
				hazard_added.emit(int(h["id"]), h["kind"], h["at"], float(h["radius"]), float(h["seconds"]))
		ZzEvents.Kind.HAZARD_GONE:
			var ended := ZzEvents.read_id(reader)
			if bool(ended["ok"]):
				hazard_removed.emit(int(ended["id"]))
		ZzEvents.Kind.THROW:
			var t := ZzEvents.read_throw(reader)
			if bool(t["ok"]):
				thrown.emit(int(t["id"]), t["kind"], t["from"], t["velocity"])
		ZzEvents.Kind.LANDED:
			var l := ZzEvents.read_landed(reader)
			if bool(l["ok"]):
				landed.emit(int(l["id"]), l["kind"], l["at"])
		ZzEvents.Kind.BLAST:
			var b := ZzEvents.read_blast(reader)
			if bool(b["ok"]):
				blast_received.emit(b["at"], float(b["radius"]), b["kind"])
		ZzEvents.Kind.BILE:
			var bile := ZzEvents.read_bile(reader)
			if bool(bile["ok"]):
				bile_received.emit(int(bile["player_id"]), float(bile["seconds"]))
		ZzEvents.Kind.OBJECTIVE:
			var o := ZzEvents.read_objective(reader)
			if bool(o["ok"]):
				if int(o["index"]) < game.objective_states.size():
					game.objective_states[int(o["index"])] = [&"waiting", &"holding", &"done", &"done"][int(o["state"])]
				objective_received.emit(int(o["index"]), int(o["state"]))
		ZzEvents.Kind.GATE:
			var g := ZzEvents.read_gate(reader)
			if bool(g["ok"]):
				game.map.open_gate(str(g["gate"]))
				gate_received.emit(str(g["gate"]))
		ZzEvents.Kind.BARRICADE:
			var bar := ZzEvents.read_barricade(reader)
			if bool(bar["ok"]):
				game.apply_barricade(str(bar["id"]), float(bar["fraction"]), bool(bar["intact"]))
		ZzEvents.Kind.SURVIVAL:
			var held := ZzEvents.read_survival(reader)
			if bool(held["ok"]):
				held.erase("ok")
				game.remote_survival = held
		ZzEvents.Kind.EFFECTS:
			var fx := ZzEvents.read_effects(reader)
			if bool(fx["ok"]):
				effects_received.emit(fx["effects"])
		ZzEvents.Kind.HURT:
			var hurt := ZzEvents.read_hurt(reader)
			if bool(hurt["ok"]):
				hurt_received.emit(float(hurt["amount"]), hurt["from"])
		ZzEvents.Kind.AMMO:
			ammo_received.emit()
		ZzEvents.Kind.HIT:
			var hit := ZzEvents.read_hit(reader)
			if bool(hit["ok"]):
				hit_received.emit(int(hit["victim"]), float(hit["amount"]), hit["point"],
					bool(hit["killed"]), bool(hit["headshot"]))


# --- Zombies -----------------------------------------------------------------

## The entity id a zombie's net id is known by, for a PIN. 0 when it is not replicated.
func _npc_net_id(entity: int) -> int:
	if game == null or game.horde == null:
		return 0

	var npc: DotNpcInstance = game.horde.npc_for_entity(entity)

	if npc == null:
		return 0

	var behaviour: ZzNpcNet = _zombie_nets.get(npc.instance_id)
	return behaviour.identity.net_id if behaviour != null and behaviour.identity != null else 0


## A zombie appeared on the server: an entity for it, and the announcement. Always relevant:
## a crowd half sent is a crowd with holes in it, and the arena's first version, culled by
## distance, announced monsters and then never sent them a snapshot.
func _on_zombie_spawned(npc: DotNpcInstance) -> void:
	var body := npc.node as ZzZombieBody

	if body == null or net == null or _zombie_nets.has(npc.instance_id):
		return

	var behaviour := ZzNpcNet.new()
	behaviour.name = "Net"
	behaviour.npc = npc
	behaviour.body = body
	body.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	identity.authority = DotNetIdentity.Authority.SERVER
	identity.always_relevant = true
	body.add_child(identity)

	var registered := net.registry.register(identity, 0, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not replicate a zombie", {"error": str(registered.error)})
		return

	_zombie_nets[npc.instance_id] = behaviour
	behaviour.pull()
	_broadcast(ZzEvents.Kind.NPC, ZzEvents.write_npc(identity.net_id, npc.def.id, body.variant, npc.position()))


func _on_zombie_removed(npc: DotNpcInstance, _reason: StringName) -> void:
	var behaviour: ZzNpcNet = _zombie_nets.get(npc.instance_id)
	_zombie_nets.erase(npc.instance_id)
	var killed := bool(_died.get(npc.instance_id, false))
	_died.erase(npc.instance_id)

	if behaviour == null or behaviour.identity == null or net == null:
		return

	var net_id := behaviour.identity.net_id
	_unregister(net_id)
	var body := npc.node as ZzZombieBody
	var death: DotPlayerDeath = body.death if killed and body != null and is_instance_valid(body) else null
	_broadcast(ZzEvents.Kind.NPC_GONE, ZzEvents.write_npc_gone(net_id, killed, death))


## A client's copy of a zombie: the same scene, no brain, moved by its net behaviour.
func _mirror_zombie(info: Dictionary) -> void:
	var net_id := int(info["net_id"])

	if _zombie_mirrors.has(net_id) or net == null:
		return

	var scene: Variant = load(ZOMBIE_SCENE) if ResourceLoader.exists(ZOMBIE_SCENE) else null

	if not (scene is PackedScene):
		DotLog.warn(CHANNEL, "the zombie scene would not load", {"path": ZOMBIE_SCENE})
		return

	var body := (scene as PackedScene).instantiate() as ZzZombieBody
	body.mirror = true
	body.kind = info["kind"]
	body.variant = int(info["variant"])

	if _zombie_world == null or not is_instance_valid(_zombie_world):
		_zombie_world = Node3D.new()
		_zombie_world.name = "ZombieMirrors"
		game.add_child(_zombie_world)

	_zombie_world.add_child(body)
	body.global_position = info["at"]

	var behaviour := ZzNpcNet.new()
	behaviour.name = "Net"
	behaviour.body = body
	body.add_child(behaviour)

	var identity := DotNetIdentity.new()
	identity.name = "Identity"
	identity.owner_peer_id = 0
	identity.authority = DotNetIdentity.Authority.SERVER
	body.add_child(identity)

	var registered := net.registry.register(identity, net_id, net.clock.tick, net.config)

	if not registered.ok:
		DotLog.warn(CHANNEL, "could not mirror a zombie", {"error": str(registered.error)})
		body.queue_free()
		return

	_zombie_mirrors[net_id] = behaviour
	npc_added.emit(net_id, body.kind, body.variant, body)


func _drop_zombie_mirror(net_id: int, killed: bool, death: DotPlayerDeath = null) -> void:
	var behaviour: ZzNpcNet = _zombie_mirrors.get(net_id)
	_zombie_mirrors.erase(net_id)

	if behaviour == null:
		return

	if net != null:
		net.registry.unregister(net_id)

	var body := behaviour.body

	# A killed zombie's body stays a moment, for the client to drop it; the client frees it.
	if body != null and is_instance_valid(body):
		behaviour.queue_free()
		body.death = death
		npc_removed.emit(net_id, killed, body)

		if not killed:
			body.queue_free()


## The mirror for a zombie's net id, on a client. Null when there is none.
func zombie_mirror(net_id: int) -> ZzZombieBody:
	var behaviour: ZzNpcNet = _zombie_mirrors.get(net_id)
	return behaviour.body if behaviour != null else null


## How many zombies this end replicates or draws.
func zombie_count() -> int:
	return _zombie_nets.size() if net != null and net.is_server else _zombie_mirrors.size()


func _apply_hello(reader: DotNetReader) -> void:
	var hello := ZzEvents.read_hello(reader)

	if not bool(hello["ok"]):
		return

	local_player_id = int(hello["player_id"])

	# [b]The server's tick rate, before anything is derived from it.[/b] Another game in
	# this family shipped with HELLO carrying this and nothing reading it: a browser client
	# counted at the 60 its export declared against a server on 128, so the correction rate
	# was 0.96 and every replicated time was out by 128/60. Produced correctly and consumed
	# by nothing, and invisible to a one-process suite because one process has one engine
	# rate and both ends agree whatever the wire says.
	#
	# Before `sync_from_server`, because the clock converts its error and its lead through
	# `tick_rate` and would otherwise do that arithmetic at the old rate.
	_adopt_tick_rate(int(hello["tick_rate"]))

	var rtt := float(rtt_source.call()) if rtt_source.is_valid() else 0.0
	net.clock.sync_from_server(int(hello["server_tick"]), maxf(0.0, rtt))

	game.config.difficulty = int(hello["difficulty"])
	game.config.max_incaps = int(hello["max_incaps"])

	_claim_local_player()

	hello_received.emit(local_player_id)


## Puts the whole client — the world, every controller and the ENGINE — on the server's rate.
##
## That last one is not cosmetic. Measured in another game in this family at 60 against 128:
## the simulation stayed correct, because the clock is asked how many ticks a frame is worth
## — it just ran them in bursts of two and three, and the camera advanced 74 mm on six frames
## out of seven and 112 mm on the seventh. A 47% change in apparent speed, eight times a
## second.
##
## A server never calls this: its rate is `sv_tickrate`, and adopting a peer's would be a
## client telling the server how fast to run.
func _adopt_tick_rate(rate: int) -> void:
	if net == null or net.is_server or game == null or rate <= 0 or rate == game.tick_rate:
		return

	var before := game.tick_rate

	if not game.set_tick_rate(rate):
		return

	net.config.tick_rate = game.tick_rate
	# The LIVE one, which is built from the config back at `setup()` and is therefore not
	# updated by writing the config alone.
	net.clock.tick_rate = game.tick_rate
	Engine.physics_ticks_per_second = game.tick_rate

	DotLog.info(CHANNEL, "adopted the server's tick rate", {
		"was": before, "now": game.tick_rate, "engine": Engine.physics_ticks_per_second,
	})


## The map, which on a client is a document it builds exactly as the server did.
##
## [b]Refused with a line, never half built.[/b] A client a format behind the server decodes a
## document it cannot read; [ZzMapDoc] says so, and the honest answer is no map and a WARN
## rather than a map with holes in it.
func _apply_map(reader: DotNetReader) -> void:
	var told := ZzEvents.read_map(reader)

	if not bool(told["ok"]) or game == null:
		return

	var decoded := ZzMapDoc.decode(told["encoded"])

	if not decoded.ok:
		DotLog.warn(CHANNEL, "the server sent a map this build cannot build", {
			"why": decoded.error.message, "detail": decoded.error.detail,
		})
		return

	var built := game.build_map(decoded.value)

	if built.ok:
		map_received.emit(game.map.id())


func _apply_join(reader: DotNetReader) -> void:
	var join := ZzEvents.read_join(reader)

	if not bool(join["ok"]):
		return

	var session_id := int(join["player_id"])
	var id := player_key(session_id)
	var player: ZzPlayer = game.players.get(id)

	if player == null:
		player = game.add_player(id, str(join["name"]), int(join["team"]))

		if player == null:
			return

		# A client never samples: the client loop hands it commands, and the local player is
		# the only one whose commands exist at all.
		player.sampler = null
		player.samples_input = false

		# [b]This client's own player is owned by this client, and nobody else's is.[/b]
		# Until 2026-09-25 every mirror was built with owner 0, this client's own included,
		# so `is_owner` was false for the local player, `registry.predicted()` was empty and
		# `client_tick` simulated nobody: the player moved only when a snapshot came back, a
		# round trip behind the keys, and the camera — drawn from `render_state`, a blend
		# against a previous tick the controller never recorded — lurched between where the
		# player was last teleported and where the server had them. Every check passed
		# anyway, because a client adopting the server's answer also agrees with the server.
		#
		# By session and not by a peer id on the wire: JOIN does not carry one, and what
		# `is_owner` compares is the owner against THIS registry's local peer — so the local
		# peer id is the only right value whatever the server calls the connection, and the
		# wire (and therefore a published pack's server half) is unchanged. HELLO, which sets
		# `local_player_id`, is sent before every JOIN in `_admit` on the same reliable
		# channel; [method _apply_hello] still claims a player that got here first, because
		# an order is a property of the server, not of this file.
		var identity := _build_entity(player, _mirror_owner(session_id))
		var registered := net.registry.register(
			identity, int(join["net_id"]), net.clock.tick, net.config
		)

		if not registered.ok:
			DotLog.warn(CHANNEL, "could not mirror a player", {"error": str(registered.error)})
			return
	else:
		player.display_name = str(join["name"])

	# Both branches: a JOIN for somebody this client already has is the server saying who
	# they are NOW — see [method refresh_player].
	player.avatar = join["avatar"]
	game.sides[id] = int(join["team"])
	player.team = int(join["team"])
	roster_changed.emit(session_id)


## Who owns a mirrored player on this client: this client, if it is this client's own
## player, and the server's 0 otherwise.
##
## [b]Never the local peer for anybody else[/b], or this client would predict a person whose
## keys it never had. And a client whose local peer is 0 claims nothing: 0 is the server's
## owner id, and on such a registry dot-net's `is_owner` (owner == local peer) is already true
## of every owner-0 mirror — which this function cannot undo, and which no client here runs
## into, because `ZzClient` takes its id from the multiplayer API and that never answers 0.
func _mirror_owner(session_id: int) -> int:
	if net == null or net.local_peer_id <= 0:
		return 0

	if local_player_id != 0 and session_id == local_player_id:
		return net.local_peer_id

	return 0


## The local player's mirror, claimed if it arrived before HELLO said whose it was.
##
## Not the order `_admit` sends in, and that is why it is belt and braces rather than a path
## this game takes: a JOIN that reached this peer before its HELLO would otherwise leave the
## local player unpredicted for the rest of the session, with every check still passing —
## which is the bug [method _apply_join] documents.
func _claim_local_player() -> void:
	var mine: ZzPlayerNet = _behaviours.get(local_player_id)

	if mine == null or mine.identity == null or not mine.identity.is_registered():
		return

	var claimed := _mirror_owner(local_player_id)

	if claimed == 0 or mine.identity.owner_peer_id == claimed:
		return

	DotLog.debug(CHANNEL, "claimed the local player after HELLO", {
		"session": local_player_id, "net_id": mine.identity.net_id,
	})
	var _changed := net.registry.change_owner(mine.identity.net_id, claimed)


func _apply_clock(reader: DotNetReader) -> void:
	var clock := ZzEvents.read_clock(reader)

	if not bool(clock["ok"]):
		return

	game.round_number = int(clock["round"])
	game.phase = int(clock["phase"])
	game.phase_elapsed = float(clock["elapsed"])
	game.survival_elapsed = float(clock["held"])
	game.survival_goal = float(clock["goal"])
	game.remote_alive = int(clock["alive"])
	game.remote_playable = bool(clock["playable"])
	game.remote_seconds_left = maxf(game.survival_goal - game.survival_elapsed, 0.0) if game.survival_goal > 0.0 else -1.0

	var index := int(clock["objective"])
	if index >= 0 and index < game.objective_states.size():
		game.objective_states[index] = [&"waiting", &"holding", &"done", &"done"][int(clock["objective_state"])]
		if game.objective_states[index] == &"holding":
			game.objective_progress[index] = game.now() + float(clock["objective_ends"])


# --- Reporting -------------------------------------------------------------

func describe() -> Dictionary:
	var out := {
		"server": net != null and net.is_server,
		"players": _behaviours.size(),
		"zombies": zombie_count(),
		"ready_peers": _ready_peers.size(),
		"tick": _tick,
	}

	if not (net != null and net.is_server):
		out["local_player"] = local_player_id

	if link != null:
		out["link"] = link.describe()

	return out


func describe_lines() -> PackedStringArray:
	var lines := PackedStringArray([
		"bridge     %s" % ("server" if net != null and net.is_server else "client"),
		"players    %d" % _behaviours.size(),
		"peers      %d ready" % _ready_peers.size(),
		"tick       %d" % _tick,
	])

	if link != null:
		lines.append_array(link.describe_lines())

	return lines
