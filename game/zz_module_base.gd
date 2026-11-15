extends DotGameModule

## The workbench kind of the ambience cvar set.
const AMBIENT_KIND := "ambience"

const ZzMapConfig := preload("zz_map_config.gd")

const ZzNetBridge := preload("net/zz_net_bridge.gd")

const ZzServices := preload("zz_services.gd")

const ZzBots := preload("zz_bots.gd")

const ZzCaps := preload("zz_caps.gd")

const ZzGame := preload("zz_game.gd")

const ZzZombieView := preload("../npcs/zz_zombie_view.gd")

const ZzPlayer := preload("zz_player.gd")

const ZzAvatars := preload("zz_avatars.gd")

const ZzClasses := preload("zz_classes.gd")

const ZzVote := preload("zz_vote.gd")

const ZzNpcs := preload("zz_npcs.gd")

## This game, as a module a dedicated server loads. [b]What [DotGameModule] does not.[/b] [DotGameModule] holds the netcode and its four load-bearing constants, the bridge, the message seal, the identity layer, the roster, the authoritative tick and a teardown in the reverse order. Two of those five hand-written copies had the same line wrong and nobody could
## ever join those servers. What is left here is what is actually this game's: the cvars an operator turns between rounds, the console commands, the map vote, and the rule that keeps enough people in a round for one to happen. [b]No `class_name`, and that is a requirement rather than a style.[/b] [method DotModuleHost.load_module] takes a PATH and constructs
## the module itself — it must, because that is the shape that lets an operator name one in a config file — and a module delivered inside a dot-cloud pack cannot have a `class_name` at all: a mounted pack's globals are not registered in the host. [codeblock] server.modules.load_module("res://game/zz_module.gd") [/codeblock]

# [b]No `const CHANNEL` here, and its absence is the point.[/b] [DotGameModule] already declares one and GDScript refuses to let a subclass
# redeclare it — which is the right refusal: a module logs through [method DotModule.log_info], which stamps the module's own name, so a second
# channel would split one module's records across two places an operator has to know to turn up separately.

## Seconds between checks of how many people are in the round.
const ROSTER_INTERVAL := 2.0

## Where the services keep punishments. Empty is [DotGameServices]'s own default, `user://zombiezone_punishments.json` — the store a real server enforces. [b]Static, because nothing holds
## this module before it exists[/b]: dot-server constructs it from a path inside `load_module`, so there is no instance for a host to set a field on first. `examples/dedicated.tscn` points it
## at a directory of its own; before it could, every run appended the live tools' audit warnings to the real store, 106 of them by the time anybody counted.
static var punishments_file: String = ""

## The `zz_bots` cvar, held so the tick does not look it up sixty times a second.
var _bots: DotConVar = null

## How many stand-ins, from how many people: dot-server's one rule for every game. See
## [method _keep_the_round_full].
var _quota: DotBotQuota = null

var _since_roster_check: float = 0.0

## How many stand-ins this module has put in, so it can take them out again.
var _bot_ids: Array[StringName] = []

## The players' vote for the next map; null when it could not be built.
var vote: ZzVote = null

## dot-vote's `DotVoteBans`: players' votes to ban a player, and the one team damage starts.
## Null on a host whose dot-vote has none (API level under 8), which runs without them.
var voteban: RefCounted = null

## The drawn ballot's notice topic. The client shell draws one menu per topic.
const MAP_BALLOT_TOPIC := &"map_ballot"

## [key, description, min, max] of the oil monster's tunables; `goo_*` and `trail_*` are DotHazardProfile keys (see ZzHazards.configure_from_meta).
const OIL_TUNABLES: Array = [
	["damage", "Damage of its bite", 0.0, 200.0], ["reach", "Reach of its bite in metres", 0.5, 6.0],
	["spit_damage", "Damage of one glob of goo", 0.0, 200.0], ["spit_range", "Farthest it spits, metres", 1.0, 80.0],
	["spit_min", "Closest it spits, metres", 0.0, 40.0], ["spit_cooldown", "Seconds between spits", 0.5, 120.0],
	["spit_speed", "Speed of a glob, m/s", 4.0, 60.0], ["spit_windup", "Seconds the mouth opens before the glob leaves", 0.1, 3.0],
	["blind_seconds", "Seconds a glob's goo stays on the screen", 0.0, 60.0], ["blind_max_stacks", "Most globs that stack on a screen (1 to 3)", 1.0, 3.0],
	["goo_radius", "Radius of the spit's puddle, metres", 0.2, 20.0], ["goo_seconds", "Seconds the spit's puddle lasts", 0.5, 120.0],
	["goo_dps", "Damage a second in the spit's puddle", 0.0, 200.0], ["goo_slow_factor", "Speed multiplier in the spit's puddle (1 none)", 0.05, 1.0],
	["goo_tick_interval", "Seconds between the puddle's damage payments", 0.0, 5.0], ["goo_fade_seconds", "Seconds the puddle fades out at its end", 0.0, 30.0],
	["goo_global_cap", "Spit puddles at once on the server (0 no limit)", 0.0, 1000.0],
	["trail_radius", "Radius of a trail puddle, metres", 0.2, 10.0], ["trail_seconds", "Seconds a trail puddle lasts", 0.5, 120.0],
	["trail_dps", "Damage a second in the trail", 0.0, 200.0], ["trail_slow_factor", "Speed multiplier in the trail (1 none)", 0.05, 1.0],
	["trail_tick_interval", "Seconds between the trail's damage payments", 0.0, 5.0], ["trail_fade_seconds", "Seconds a trail puddle fades at its end", 0.0, 30.0],
	["trail_spacing", "Metres slid between trail puddles", 0.2, 20.0], ["trail_interval", "Fewest seconds between trail puddles", 0.0, 10.0],
	["trail_max_per_owner", "Trail puddles one monster may have at once (0 no limit)", 0.0, 1000.0],
	["trail_global_cap", "Trail puddles at once on the server (0 no limit)", 0.0, 5000.0],
]

## The cvars a map's `dot_map/map/<name>.yml` may set (zz_map_config.gd).
func _map_config_keys() -> Dictionary:
	var keys: Dictionary = ZzMapConfig.KEYS.duplicate()
	keys.merge(DotWeaponSpawnerConfig.MAP_KEYS)
	return keys

## The spawner's settings live on the spawner, not in a cvar.
func _map_config_get(key: String) -> Variant:
	if DotWeaponSpawnerConfig.MAP_KEYS.has(key):
		var spawners: Variant = (game as ZzGame).spawners
		return spawners.spawner.config.get_setting(key) if spawners != null else null
	return super._map_config_get(key)

func _map_config_set(key: String, value: Variant) -> bool:
	if DotWeaponSpawnerConfig.MAP_KEYS.has(key):
		var spawners: Variant = (game as ZzGame).spawners
		return spawners != null and spawners.spawner.config.set_setting(key, value)
	return super._map_config_set(key, value)

func _map_config_game() -> String:
	return ZzMapConfig.GAME_ID

func _module_name() -> String:
	return "zombiezone"

func _game_service() -> StringName:
	return ZzGame.SERVICE

func _game_missing_hint() -> String:
	return (
		"create an ZzGame, add it to the tree and let its _ready() register it under "
		+ "'%s' — a module cannot build the world, because the world outlives it"
		% String(ZzGame.SERVICE)
	)

## The netcode's numbers, which are the game's and not the addon's. Tick rate from the world, so `sv_tickrate` reaches it: the server sets
## the engine's physics rate from that cvar at boot, the world is built after the server and reads it, and this reads the world. A number
## written here instead would be a netcode running at a rate the operator did not choose, silently.
func _net_config() -> DotNetConfig:
	var config := DotNetConfig.new()
	config.tick_rate = (game as ZzGame).tick_rate
	config.snapshot_rate = ZzGame.NET_SNAPSHOT_RATE
	config.world_extent = ZzGame.NET_WORLD_EXTENT
	config.enable_prediction = true
	# [b]On, and the two callables that make it real are wired by the bridge.[/b] It was off for as long as they were not: a flag reported as
	# enabled with nothing behind it is worse than one that is off, because the first reader to trust it loses an afternoon. See [method
	# ZzNetBridge._wire_lag_compensation]. A shot at a running zombie, from a hundred milliseconds away, is the ordinary reason.
	config.enable_lag_compensation = true
	# No cap: a snapshot that cut a 100+ horde short would leave zombies frozen where the last
	# one that fitted left them.
	config.max_entities_per_snapshot = 0
	return config

func _make_bridge() -> Node:
	return ZzNetBridge.new()

## Chat, voice and moderation, over [DotGameServices]. [b]The bridge is handed over as the link, and that is the whole of the wiring.[/b] A chat line goes out through
## `send_chat` and a voice frame through `send_voice`, both on this game's own wire. [DotGameModule] does the rest: it assigns the bridge's `voice_relay_fn`, checks
## `check_admission` before seating anybody, and tells the roster to follow this layer so a leaver is forgotten by the rate limiter and the voice router together.
func _make_services() -> Node:
	var services := ZzServices.new()
	services.bridge = bridge
	services.punishments_file = punishments_file
	return services

## Profiles, avatars and admission: dot-platform's [DotPlatformIdentity] over this game's one-slot schema. [DotGameModule] builds it before the services and loads dot-platform's own module beside it.
## [b]Authentication is not here and was never this game's.[/b] Whether a player is proven to be somebody is the host's `dot_auth_server`, the same for every game it runs; what this layer does is
## everything after — a scoped profile, the name on it, and a face. With authentication off everybody is a guest with a profile of their own, which is what a LAN server is.
func _make_identity() -> Node:
	var identity_layer := DotPlatformIdentity.new()
	identity_layer.avatar_schema = ZzAvatars.schema()
	identity_layer.stock_avatar_fn = ZzAvatars.stock_avatar
	identity_layer.avatar_translate_fn = ZzAvatars.from_site
	return identity_layer

## The maps the SERVER names for this game, fetched and added to the catalogue. Returns how many documents they held. [b]The server's list, not this game's.[/b] A map pack was a `server_dependencies` entry in `game.yml`, which travels in this game's own pack — so a new map meant a release of the game, and a server owner could not choose which maps to run. The owner names them now in their
## deployment's map config (dot-server-deploy's `cfg/content.yml`, which fills [member DotGameDescriptor.maps]); [DotGameContent] fetches each pack and hands back its `maps/` directory. A server that still names one under `server_dependencies` keeps working, because DotGameContent reads those too. [b]Still server-only.[/b] The server sends the map it is playing in MAP, so a client never needs a map file
## and none of these is in a client's content sync. With nothing named, this game plays its built-in map. [b]Called after EVERY catalogue load[/b], not only the first: `load_from` forgets everything read before, and a reload that did not come back here dropped every delivered map — which is what mg-wipeout and mg-deathrun did until the three were moved onto DotGameContent.
func _add_delivered_maps(world: ZzGame) -> int:
	if server == null or world.catalogue == null:
		return 0

	var read := 0

	for root in await DotGameContent.map_dirs(server, "maps"):
		read += world.catalogue.add_directory(root)

	return read

## Where a map's drawn world is published: its document's `world` pack, at the owner and version of the maps pack the
## document came from (zombie-zone-maps' release publishes both from one tag, dot-ci's release-maps). Empty for a map
## from no pack: a client then draws its boxes, unless its own checkout has the world.
func _world_key(doc: Dictionary) -> String:
	var pack := str(doc.get("world", ""))
	if server == null or pack == "":
		return ""

	for key in DotGameContent.map_keys(server):
		if not FileAccess.file_exists("%s/maps/%s.json" % [DotGameContent.mount_of(key), str(doc.get("id", ""))]):
			continue
		var slash := key.find("/")
		var at := key.rfind("@")
		if slash > 0 and at > slash:
			return "%s/%s@%s" % [key.substr(0, slash), pack, key.substr(at + 1)]

	return ""


## What a session looks like: what dot-platform resolved for them, or the stock person. [b]Through the platform module's `player_for`, and never the hub by a key made
## here.[/b] The hub keys a player by their scoped profile key, which only admission knows; a lookup by `u<session>` finds nobody, every time, and falls through to stock —
## which reads as "this player has no avatar" rather than as a wrong key. Duck-typed, because a server without dot-platform is a configuration.
func _avatar_for(session_id: int) -> DotAvatar:
	var session := server.session_by_userid(session_id) if server != null else null
	var platform: Object = server.modules.get_module("platform") \
		if server != null and server.modules != null else null

	if session != null and platform != null and platform.has_method("player_for"):
		var player: Variant = platform.call("player_for", session)

		if player is Object and (player as Object).get("avatar") is DotAvatar:
			return (player as Object).get("avatar") as DotAvatar

	if identity != null and identity.has_method("avatar_for"):
		return identity.call("avatar_for", String(ZzNetBridge.player_key(session_id)))

	return null
