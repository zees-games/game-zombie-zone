extends Node

## The declarations of [zz_net_bridge.gd]: constants, signals and variables, so the file that extends this holds behaviour only.

const ZzConfig := preload("../zz_config.gd")
const ZzEvent := preload("zz_event.gd")
const ZzEvents := preload("zz_events.gd")
const ZzClasses := preload("../zz_classes.gd")
const ZzNetCommand := preload("zz_net_command.gd")
const ZzNetLink := preload("zz_net_link.gd")
const ZzPlayerNet := preload("zz_player_net.gd")
const ZzNpcNet := preload("zz_npc_net.gd")
const ZzToyNet := preload("zz_toy_net.gd")
const ZzRequest := preload("zz_request.gd")

const ZzGame := preload("../zz_game.gd")
const ZzMapDoc := preload("../zz_map_doc.gd")
const ZzPlayer := preload("../zz_player.gd")
const ZzZombieBody := preload("../../npcs/zz_zombie_body.gd")
const ZzZombieLimbs := preload("../../npcs/zz_zombie_limbs.gd")
const ZzPaths := preload("../zz_paths.gd")
const ZzNpcs := preload("../zz_npcs.gd")

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
signal death_received(player_id: int, by: int, why: StringName, by_kind: StringName, weapon_id: StringName)

## Somebody was handed, or picked up, a weapon. The HUD names it.
signal armed_received(player_id: int, weapon_id: StringName)

signal notice_received(text: String)
signal shop_received(json: String)
## Client side: what this client carries (JSON from [method ZzCarry.state_json]).
signal carry_received(json: String)

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
signal defibbed_received(player_id: int, by: int)
signal pin_received(player_id: int, npc_net_id: int, kind: StringName)
signal unpin_received(player_id: int, why: StringName)
signal box_received(player_id: int, type_id: StringName, title: String, message: String)
signal loot_added(id: int, kind: StringName, item: StringName, at: Vector3)
## After loot_added, for an entry the shop sells.
signal loot_priced(id: int, price: int)
signal loot_removed(id: int, by: int)
signal loot_moved(rows: Array)
signal hazard_added(id: int, kind: StringName, at: Vector3, radius: float, seconds: float)
signal hazard_removed(id: int)
signal turret_added(id: int, at: Vector3, yaw: float, seconds: float)
signal turret_fired(id: int, target: Vector3)
signal turret_removed(id: int)
signal thrown(id: int, kind: StringName, from: Vector3, velocity: Vector3)
signal landed(id: int, kind: StringName, at: Vector3)
signal blast_received(at: Vector3, radius: float, kind: StringName)
signal bile_received(player_id: int, seconds: float)
signal objective_received(index: int, state: int)
signal gate_received(gate: String)
signal support_received(index: int)
signal effects_received(rows: Array)
signal hurt_received(amount: float, from: Vector3)
signal ammo_received()
## Your hit landed (see [signal ZzGame.hit_landed]); only ever to the shooter.
signal hit_received(victim: int, amount: float, point: Vector3, killed: bool, headshot: bool)
## Somebody else's hit left blood on a surface here (see [method splat]); the shooter never gets this.
signal splat_received(point: Vector3, normal: Vector3)

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
## The map as MAP_PART bodies when it is too big for one message, else empty.
var _map_parts: Array[PackedByteArray] = []
var _map_seq: int = 0
## A client's map arriving in pieces: {seq, count, pieces: {index: bytes}}.
var _incoming_map: Dictionary = {}

## Zombies this server replicates (instance id -> [ZzNpcNet]), and that a client draws
## (net id -> [ZzNpcNet]).
var _zombie_nets: Dictionary = {}
var _zombie_mirrors: Dictionary = {}
var _stale_clock := 0.0
var _interest_applied: Array = []
## Carries the game's profile runtime (rows down) over this manager; null when the types would not register.
var profile_link: DotNetProfileLink = null
var _zombie_world: Node3D = null

## Whether the last thing that removed a zombie was its death, so NPC_GONE can say so.
var _died: Dictionary = {}

static var ZOMBIE_SCENE := ZzPaths.rebase("res://npcs/zz_zombie.tscn")
