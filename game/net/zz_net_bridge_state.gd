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

## Joins a [ZzGame] to a [DotNetManager]: the netcode seam, and the only file that names both.
## Survivors are predicted; zombies are server-owned entities (`NPC`, snapshots, `NPC_GONE`); the map arrives once as `MAP`; a joiner learns the current world on READY.
## dot-net ticks per entity but this game's tick is the whole world, so [method ensure_game_ticked] runs it on the first behaviour through.

const CHANNEL := "zz.net"

## Bytes of acknowledgement in front of every input packet. [method DotNetManager.encode_ack].
const ACK_BYTES := 4

## Commands per input packet: this tick's and the four before, so a lost packet costs no tick unless five go missing.
## Measured at 20% loss: one copy gave 80% of ticks the right command, three 99-100%, five closed the rest.
const INPUT_COPIES := 5

## Ticks between round-clock updates (twice a second, not per tick or snapshot);
## the client advances the clock between messages, see [method _apply_clock].
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

## Client side: the server gave this client a zombie body to drive (its net id), or took it (0).
signal possess_received(net_id: int)

## Client side: somebody else used their weapon [param times] times since the last
## snapshot. [param kind] is one of `ZeeWeaponNet.KIND_*`. Relayed from that player's own
## behaviour, because a client builds those one per JOIN and nothing else could find them.
signal weapon_used_by(session_id: int, times: int, kind: int)

## Client side: the map was rebuilt from what the server sent. The HUD names it.
signal map_received(map_id: StringName)
## A map's first piece has arrived: it is being sent, and is not built yet.
## The server told the map this end already has built (a new round on it): nothing rebuilt.
signal map_repeated(map_id: StringName)
signal map_incoming()

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
## A shot's bullet holes, wall faces and bounce marks, `[[point, normal], ...]`; to everybody, the shooter too.
signal impact_received(marks: Array)

## Client side: a zombie mirror was built, or let go. [param body] is its scene, already in the
## world; the client hangs a [ZzZombieView] off it.
signal npc_added(net_id: int, kind: StringName, variant: int, body: Node3D)
signal npc_removed(net_id: int, killed: bool, body: Node3D)

## Somebody pressed Enter. Server side; the bridge carries chat and decides nothing, [DotChatRouter] does.
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

## Where the clock learns the link latency in ms ([method DotClientLink.ping_ms]).
## With no sample the clock assumes zero and stamps commands for ticks the server has already run,
## so every command is discarded as late.
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

## The next session id for somebody the world made itself, well above anything dot-server issues.
## A player named `bot` parses back to session zero, so two bots would share one behaviour entry
## and a JOIN carrying the broadcast address.
const FIRST_BOT_SESSION := 900000

var _next_bot_session: int = FIRST_BOT_SESSION

var _player_of_peer: Dictionary = {}
var _peer_of_player: Dictionary = {}
var _ready_peers: Dictionary = {}
## Server: peers whose READY came before their seat ([method add_player]); over lossy ENet READY can
## overtake `loaded`, and a dropped one left the client waiting for ever. Admitted when seated.
var _ready_unseated: Dictionary = {}

var _tick: int = 0
var _game_ticked_for: int = -1

## Server only: whether [method DotNetManager.server_tick] is on the stack, and the net ids let go of meanwhile.
## A removal inside the first player behaviour's tick would let the history record recreate a
## lag-compensation track for it, so the ids are forgotten again once the manager has dropped its list.
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
## Client: the encoded map this end last built from the server's word.
var _built_bytes: PackedByteArray = PackedByteArray()

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
