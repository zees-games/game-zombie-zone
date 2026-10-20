extends DotGameModule

const ZzNetBridge := preload("net/zz_net_bridge.gd")
const ZzServices := preload("zz_services.gd")

const ZzBots := preload("zz_bots.gd")
const ZzGame := preload("zz_game.gd")
const ZzPlayer := preload("zz_player.gd")
const ZzAvatars := preload("zz_avatars.gd")
const ZzVote := preload("zz_vote.gd")
const ZzNpcs := preload("zz_npcs.gd")

## This game, as a module a dedicated server loads.
##
## [b]What [DotGameModule] does not.[/b]
## [DotGameModule] holds the netcode and its four load-bearing constants, the bridge, the
## message seal, the identity layer, the roster, the authoritative tick and a teardown in
## the reverse order. Two of those five hand-written copies had the same line wrong and
## nobody could ever join those servers. What is left here is what is actually this game's:
## the cvars an operator turns between rounds, the console commands, the map vote, and the rule
## that keeps enough people in a round for one to happen.
##
## [b]No `class_name`, and that is a requirement rather than a style.[/b]
## [method DotModuleHost.load_module] takes a PATH and constructs the module itself — it
## must, because that is the shape that lets an operator name one in a config file — and a
## module delivered inside a dot-cloud pack cannot have a `class_name` at all: a mounted
## pack's globals are not registered in the host.
##
## [codeblock]
## server.modules.load_module("res://game/zz_module.gd")
## [/codeblock]

# [b]No `const CHANNEL` here, and its absence is the point.[/b] [DotGameModule] already
# declares one and GDScript refuses to let a subclass redeclare it — which is the right
# refusal: a module logs through [method DotModule.log_info], which stamps the module's own
# name, so a second channel would split one module's records across two places an operator
# has to know to turn up separately.

## Seconds between checks of how many people are in the round.
const ROSTER_INTERVAL := 2.0

## Where the services keep punishments. Empty is [DotGameServices]'s own default,
## `user://zombiezone_punishments.json` — the store a real server enforces.
##
## [b]Static, because nothing holds this module before it exists[/b]: dot-server constructs
## it from a path inside `load_module`, so there is no instance for a host to set a field on
## first. `examples/dedicated.tscn` points it at a directory of its own; before it could,
## every run appended the live tools' audit warnings to the real store, 106 of them by the
## time anybody counted.
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


## The netcode's numbers, which are the game's and not the addon's.
##
## Tick rate from the world, so `sv_tickrate` reaches it: the server sets the engine's
## physics rate from that cvar at boot, the world is built after the server and reads it,
## and this reads the world. A number written here instead would be a netcode running at a
## rate the operator did not choose, silently.
func _net_config() -> DotNetConfig:
	var config := DotNetConfig.new()
	config.tick_rate = (game as ZzGame).tick_rate
	config.snapshot_rate = ZzGame.NET_SNAPSHOT_RATE
	config.world_extent = ZzGame.NET_WORLD_EXTENT
	config.enable_prediction = true
	# [b]On, and the two callables that make it real are wired by the bridge.[/b] It was off
	# for as long as they were not: a flag reported as enabled with nothing behind it is
	# worse than one that is off, because the first reader to trust it loses an afternoon.
	# See [method ZzNetBridge._wire_lag_compensation].
	#
	# A shot at a running zombie, from a hundred milliseconds away, is the ordinary reason.
	config.enable_lag_compensation = true
	# Survivors and every zombie: a full horde is a hundred and more, and a snapshot that cut
	# it short would leave zombies frozen where the last one that fitted left them.
	config.max_entities_per_snapshot = 256
	return config


func _make_bridge() -> Node:
	return ZzNetBridge.new()


## Chat, voice and moderation, over [DotGameServices].
##
## [b]The bridge is handed over as the link, and that is the whole of the wiring.[/b] A chat
## line goes out through `send_chat` and a voice frame through `send_voice`, both on this
## game's own wire. [DotGameModule] does the rest: it assigns the bridge's `voice_relay_fn`,
## checks `check_admission` before seating anybody, and tells the roster to follow this layer
## so a leaver is forgotten by the rate limiter and the voice router together.
func _make_services() -> Node:
	var services := ZzServices.new()
	services.bridge = bridge
	services.punishments_file = punishments_file
	return services


## Profiles, avatars and admission: dot-platform's [DotPlatformIdentity] over this game's
## one-slot schema. [DotGameModule] builds it before the services and loads dot-platform's
## own module beside it.
##
## [b]Authentication is not here and was never this game's.[/b] Whether a player is proven
## to be somebody is the host's `dot_auth_server`, the same for every game it runs; what
## this layer does is everything after — a scoped profile, the name on it, and a face.
## With authentication off everybody is a guest with a profile of their own, which is what
## a LAN server is.
func _make_identity() -> Node:
	var identity_layer := DotPlatformIdentity.new()
	identity_layer.avatar_schema = ZzAvatars.schema()
	identity_layer.stock_avatar_fn = ZzAvatars.stock_avatar
	identity_layer.avatar_translate_fn = ZzAvatars.from_site
	return identity_layer


func _game_load() -> DotResult:
	var world := game as ZzGame

	if world == null:
		return DotResult.fail(DotError.CODE_STATE, "The registered game is not an ZzGame.")

	add_command("zz_status", _cmd_status, "Show the map, the survivors and the horde")
	add_command("zz_net", _cmd_net, "Show what the netcode is doing")
	# The map commands are renameable from maps.yml's `commands:` block, like dot-vote's roles.
	for name in world.command_names("zz_maps"):
		add_command(name, _cmd_maps, "List the maps, and any refused file")
	for name in world.command_names("zz_reload"):
		add_command(name, _cmd_reload, "Read the map directory again (from the next map)")
	for name in world.command_names("zz_map"):
		add_command(name, _cmd_map, "Play a map next: zz_map <id> (when this one ends)", "")
	add_command("zz_rotation", _cmd_rotation,
		"zz_rotation [name]: switch to a rotation in maps.yml, or list them", DotAdminFlags.CHANGEMAP)
	add_command("zz_maps_reload", _cmd_maps_reload, "Re-read maps.yml", DotAdminFlags.CHANGEMAP)
	var _file_cvar := add_cvar("sv_map_rotation_file", world.config.map_rotation_file,
		"maps.yml: the maps that rotate, in named rotations. Unlisted maps stay installed.")
	_file_cvar.changed.connect(func(_old: String, new_value: String) -> void:
		world.config.map_rotation_file = new_value.strip_edges()
		var _read := world.load_rotation()
		if vote != null:
			vote.refresh_maps())
	add_command("zz_say", _cmd_say, "Say something to everybody, as the server")
	add_command("zz_boxes", _cmd_boxes, "List the box types and what each can do")
	# What an admin does to a server to see what happens: a zombie, a box, a mob, a brute.
	add_command("zz_spawn", _cmd_spawn, "Spawn a zombie: zz_spawn <kind> [count] (near you, or the team)", "z")
	add_command("zz_box", _cmd_box, "Drop a box: zz_box [type] (in front of you, or the team)", "z")
	add_command("zz_mob", _cmd_mob, "Send a mob now: zz_mob [size]", "z")
	add_command("zz_panic", _cmd_panic, "Mobs back to back: zz_panic [seconds]", "z")

	_wire_chat()
	_wire_identity()
	_wire_map(world)
	_wire_progress(world)
	_add_tunables(world)

	# Whether shots pass through team-mates: `mp_teammate_passthrough` 0 never, 1 a team-mate
	# holding the muzzle (the default), 2 every team-mate in the line. dot-combat's cvar,
	# defined there once for every game; live from the next shot, and a value the operator set
	# first (argv, content.yml) is read back. NOTIFY, because players should know; REPLICATED,
	# because every client's own manager predicts its tracers under it (the client follows it
	# through its link, see the client's _build_netcode).
	if world.combat != null:
		var _passthrough := world.combat.bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED)

	# dot-player-controller's mp_forceview (first or third person: the player's choice, or one
	# held) and mp_solidplayers (survivors and stand-ins block each other, 1 by default).
	# REPLICATED: the client places its own camera under the first and predicts its own
	# player under the second.
	var _views := world.view_rules.bind_cvars(
		add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED
	)
	var _bodies := world.body_rules.bind_cvars(
		add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED
	)
	# Dead bodies, survivors' and zombies' alike: dot-player-char's sv_ragdoll* set. The server
	# only picks each death's reaction from them; REPLICATED, because the clients draw the bodies.
	var _ragdolls := world.ragdoll_rules.bind_cvars(
		add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED
	)
	# The map's toys: dot-props' sv_toys* set. REPLICATED, because a client hides the toys the
	# server took away.
	var _toys := world.toy_rules.bind_cvars(
		add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED
	)
	# Whether survivors walk through barricades. REPLICATED, because a client predicts its own
	# player under it (see ZzPassRules).
	var _passing := world.pass_rules.bind_cvars(
		add_cvar, DotConVar.FLAG_ARCHIVE | DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED
	)

	_build_vote(world)
	_build_voteban(world)

	_bots = add_cvar(
		"zz_bots", "1",
		"Automatic stand-ins: 1 keeps as many as bot_quota and bot_quota_mode say, 0 none at all."
	)

	# [b]How many is dot-server's [DotBotQuota], so `bot_quota` and `bot_quota_mode` mean the
	# same thing on every server in the family.[/b] The default is this game's own minimum
	# (`minimum_players`, from the config file) in fill mode, which is the rule it ran before
	# the policy was shared: stand-ins top the round up to that many players, a person who
	# joins takes a stand-in's place, and the stand-in comes back when they leave. `zz_bots`
	# stays the switch it always was, so a server config that sets it means what it meant.
	_quota = DotBotQuota.install(self, world.config.minimum_players)

	# [b]Started here and not in the world's own `_ready`.[/b] `start()` builds the map and puts
	# everybody on it, and a world that did that before the bridge existed would have built a
	# map with nothing listening to `world_rebuilt` — one the server knows about and no client
	# is ever told about. Invisible floors: a player stands on nothing and the server says they
	# are fine.
	var _delivered: int = await _add_delivered_maps(world)

	# The vote was built above, before these arrived; read without them, its list held only
	# the practice map and never opened a ballot. zz_reload refreshes it the same way.
	if vote != null:
		vote.refresh_maps()

	# dot-game's "still loading": a seat behind its client's cover is neither hurt, pinned nor
	# hunted (see ZzGame.harm_gate). Asked by player id, resolved to a peer through the bridge.
	world.harm_gate = func(player_id: StringName) -> bool:
		if bridge == null:
			return true

		var peer := int((bridge as ZzNetBridge).peer_for_player(ZzNetBridge.session_of(player_id)))
		return peer <= 0 or can_peer_be_harmed(peer)

	world.start()

	log_info("the map is up", world.describe())
	return DotResult.success(null)


## The maps the SERVER names for this game, fetched and added to the catalogue. Returns how
## many documents they held.
##
## [b]The server's list, not this game's.[/b] A map pack used to be a `server_dependencies`
## entry in `game.yml`, which travels in this game's own pack — so a new map meant a release
## of the game, and a server owner could not choose which maps to run. The owner names them
## now in their deployment's map config (dot-server-deploy's `cfg/content.yml`, which fills
## [member DotGameDescriptor.maps]); [DotGameContent] fetches each pack and hands back its
## `maps/` directory. A server that still names one under `server_dependencies` keeps working,
## because DotGameContent reads those too.
##
## [b]Still server-only.[/b] The server sends the map it is playing in MAP, so a client never
## needs a map file and none of these is in a client's content sync. With nothing named, this
## game plays its built-in map.
##
## [b]Called after EVERY catalogue load[/b], not only the first: `load_from` forgets everything
## read before, and a reload that did not come back here dropped every delivered map — which
## is what mg-wipeout and mg-deathrun did until the three were moved onto DotGameContent.
func _add_delivered_maps(world: ZzGame) -> int:
	if server == null or world.catalogue == null:
		return 0

	var read := 0

	for root in await DotGameContent.map_dirs(server, "maps"):
		read += world.catalogue.add_directory(root)

	return read


## Who somebody is reaches the world: a face as they are seated, and the real name and face
## once dot-platform has them. All three events end in [method ZzNetBridge.refresh_player].
func _wire_identity() -> void:
	var link := bridge as ZzNetBridge

	if link == null:
		return

	link.avatar_fn = _avatar_for
	hook_post("player_admitted", _on_profile)
	hook_post("player_avatar_changed", _on_profile)
	hook_post("player_renamed", _on_profile)


## What a session looks like: what dot-platform resolved for them, or the stock person.
##
## [b]Through the platform module's `player_for`, and never the hub by a key made here.[/b]
## The hub keys a player by their scoped profile key, which only admission knows; a lookup
## by `u<session>` finds nobody, every time, and falls through to stock — which reads as
## "this player has no avatar" rather than as a wrong key. Duck-typed, because a server
## without dot-platform is a configuration.
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


func _on_profile(event: DotEvent) -> void:
	var session_id := event.get_int("userid")
	var session := server.session_by_userid(session_id) if server != null else null
	var link := bridge as ZzNetBridge

	if session == null or link == null:
		return

	link.refresh_player(session_id, session.display_name, _avatar_for(session_id))


## The numbers an operator is actually going to want to change, as cvars.
##
## [b]Live, and each one writes through to the configuration the world already reads.[/b] A
## server owner finds their server's balance by moving one of them between rounds with people
## watching; a JSON file and a restart is a balance nobody tunes.
##
## [b]Pacing changes the next clock, not the one running.[/b] `zz_mob_min` moving does not send a
## mob now; it changes when the next one is drawn. `zz_difficulty` is live for every hit.
func _add_tunables(world: ZzGame) -> void:
	var config := world.config

	_tunable("zz_difficulty", float(config.difficulty),
		"0 easy, 1 normal, 2 advanced, 3 expert: what a hit does, what a special takes, friendly fire",
		func(value: float) -> void:
			config.difficulty = clampi(int(value), 0, 3)
			_apply_friendly_fire(world))
	_tunable("zz_friendly_fire", config.friendly_fire,
		"A teammate's bullet as a share of what it does to a zombie, before difficulty",
		func(value: float) -> void:
			config.friendly_fire = clampf(value, 0.0, 1.0)
			_apply_friendly_fire(world))
	_tunable("zz_friendly_fire_mode", float(config.friendly_fire_mode),
		"What a teammate's bullet does: 0 nothing, 1 hurts, 2 hurts but a new player's is reflected onto them, 3 everybody's is reflected",
		func(value: float) -> void:
			config.friendly_fire_mode = clampi(int(value), 0, 3)
			_apply_friendly_fire(world))
	_tunable("zz_rookie_minutes", config.rookie_minutes,
		"Minutes played under which a player is new and (mode 2) has their team damage reflected; 0 nobody is new",
		func(value: float) -> void: config.rookie_minutes = clampf(value, 0.0, 100000.0))
	_tunable("zz_team_damage_window", config.team_damage_window,
		"Seconds team damage is added up over for the voteban and the ban",
		func(value: float) -> void: config.team_damage_window = clampf(value, 5.0, 3600.0))
	_tunable("zz_team_damage_vote", config.team_damage_vote,
		"Team damage inside the window that starts a voteban against the player; 0 never",
		func(value: float) -> void: config.team_damage_vote = maxf(value, 0.0))
	_tunable("zz_team_damage_ban", config.team_damage_ban,
		"Team damage inside the window that bans the player outright; 0 never",
		func(value: float) -> void: config.team_damage_ban = maxf(value, 0.0))
	_tunable("zz_team_damage_ban_minutes", config.team_damage_ban_minutes,
		"Minutes the automatic ban lasts",
		func(value: float) -> void: config.team_damage_ban_minutes = maxf(value, 1.0))
	_tunable("zz_exodus_team", float(config.exodus_team),
		"Survivors (stand-ins fill) on an exodus map at least",
		func(value: float) -> void: config.exodus_team = clampi(int(value), 0, 24))
	_tunable("zz_nav_notes", 1.0 if config.nav_notes else 0.0,
		"Annotate each map (drops, chokepoints, cover) after its bake and let bots and zombies use it; 0 off",
		func(value: float) -> void: config.nav_notes = value > 0.5)
	_tunable("zz_nav_drop", config.nav_drop_max, "The longest drop, in metres, a zombie takes off a ledge",
		func(value: float) -> void: config.nav_drop_max = clampf(value, 1.0, 10.0))
	_tunable("zz_zombie_drops", 1.0 if config.zombie_drops else 0.0,
		"Zombies step down ledges the annotations found; 0 off",
		func(value: float) -> void: config.zombie_drops = value > 0.5)
	_tunable("zz_zombie_climb", 1.0 if config.zombie_climb else 0.0,
		"Zombies climb the jump ups as well (a held tower is no longer safe); 0 off",
		func(value: float) -> void: config.zombie_climb = value > 0.5)
	_tunable("zz_zombie_spread", 1.0 if config.zombie_spread else 0.0,
		"Send each zombie through the least used choke on its way, not all down one route; 0 off",
		func(value: float) -> void: config.zombie_spread = value > 0.5)
	_tunable("zz_bot_hold_chokes", 1.0 if config.bot_hold_chokes else 0.0,
		"Survival stand-ins hold behind the chokes on the horde's routes and fall back when one is overrun; 0 posts only",
		func(value: float) -> void: config.bot_hold_chokes = value > 0.5)
	_tunable("zz_bot_hold_overrun", float(config.bot_hold_overrun),
		"Zombies within 4.5 m of a choke that make it overrun",
		func(value: float) -> void: config.bot_hold_overrun = clampi(int(value), 2, 40))
	_tunable("zz_bot_helpers", float(config.bot_helpers),
		"Survival stand-ins that answer a pinned or downed friend (the nearest standing ones); 0 all",
		func(value: float) -> void: config.bot_helpers = clampi(int(value), 0, 16))
	_tunable("zz_bot_helper_radius", config.bot_helper_radius,
		"Metres within which any survival stand-in answers a pinned or downed friend",
		func(value: float) -> void: config.bot_helper_radius = clampf(value, 0.0, 40.0))
	_tunable("zz_max_incaps", float(config.max_incaps), "Downs before the next one is death",
		func(value: float) -> void: config.max_incaps = clampi(int(value), 0, 10))
	_tunable("zz_rescue_seconds", config.rescue_seconds,
		"Seconds before a dead survivor is rescued beside the team (0 never)",
		func(value: float) -> void: config.rescue_seconds = clampf(value, 0.0, 600.0))
	_tunable("zz_start_grace", config.start_grace_seconds,
		"Seconds the start area holds the horde off unless somebody leaves it",
		func(value: float) -> void: config.start_grace_seconds = clampf(value, 0.0, 600.0))
	_tunable("zz_survive_seconds", config.survive_seconds,
		"Seconds a survival map is held for when the map does not say (0 endless)",
		func(value: float) -> void: config.survive_seconds = clampf(value, 0.0, 7200.0))
	_tunable("zz_map_on_loss", float(config.map_on_loss), "After a lost map: 0 play it again, 1 move on",
		func(value: float) -> void: config.map_on_loss = clampi(int(value), 0, 1))
	_tunable("zz_retries", float(config.retries), "Times a lost map is played again before moving on",
		func(value: float) -> void: config.retries = clampi(int(value), 0, 20))
	_tunable("zz_commons", float(config.commons_base), "Commons alive at once for one survivor",
		func(value: float) -> void: config.commons_base = clampi(int(value), 0, 400))
	_tunable("zz_commons_per_survivor", float(config.commons_per_survivor), "And for each survivor more",
		func(value: float) -> void: config.commons_per_survivor = clampi(int(value), 0, 50))
	_tunable("zz_wanderers", config.wanderer_density, "Commons standing about a map, per 100 square metres",
		func(value: float) -> void: config.wanderer_density = clampf(value, 0.0, 10.0))
	_tunable("zz_mob_min", config.mob_interval_min, "Seconds between mobs, from",
		func(value: float) -> void: config.mob_interval_min = clampf(value, 10.0, config.mob_interval_max))
	_tunable("zz_mob_max", config.mob_interval_max, "Seconds between mobs, to",
		func(value: float) -> void: config.mob_interval_max = clampf(value, config.mob_interval_min, 900.0))
	_tunable("zz_mob_size", float(config.mob_size), "Commons in a mob, for one survivor",
		func(value: float) -> void: config.mob_size = clampi(int(value), 1, 200))
	_tunable("zz_specials", float(config.specials_base), "Specials alive at once for one survivor",
		func(value: float) -> void: config.specials_base = clampi(int(value), 0, 32))
	_tunable("zz_special_min", config.special_interval_min, "Seconds between specials, from",
		func(value: float) -> void: config.special_interval_min = clampf(value, 1.0, config.special_interval_max))
	_tunable("zz_special_max", config.special_interval_max, "Seconds between specials, to",
		func(value: float) -> void: config.special_interval_max = clampf(value, config.special_interval_min, 300.0))
	# The specials added with the animated models. Each writes the configuration (the next map's
	# catalogue) and the live catalogue's definition (the next one spawned), because a brain
	# reads its numbers from its definition.
	_tunable("zz_screamer_mob", float(config.screamer_mob), "Commons a screamer's scream sends at whoever it saw",
		func(value: float) -> void:
			config.screamer_mob = clampi(int(value), 0, 100)
			_set_meta(world, ZzNpcs.SCREAMER, "scream_mob", float(config.screamer_mob)))
	_tunable("zz_screamer_cooldown", config.screamer_cooldown, "Seconds between one screamer's screams",
		func(value: float) -> void:
			config.screamer_cooldown = clampf(value, 4.0, 120.0)
			_set_meta(world, ZzNpcs.SCREAMER, "scream_cooldown", config.screamer_cooldown))
	_tunable("zz_crawler_grab_dps", config.crawler_grab_dps, "What a crawler's hold on an ankle does a second, on normal",
		func(value: float) -> void:
			config.crawler_grab_dps = clampf(value, 0.0, 50.0)
			_set_meta(world, ZzNpcs.CRAWLER, "pin_dps", config.crawler_grab_dps))
	_tunable("zz_riot_shield", config.riot_shield, "Share of a hit on a riot zombie's shield that gets through (0..1)",
		func(value: float) -> void:
			config.riot_shield = clampf(value, 0.0, 1.0)
			_set_meta(world, ZzNpcs.RIOT, "shield", config.riot_shield))
	var kinds := add_cvar("zz_special_kinds", ",".join(config.special_kinds),
		"Which specials the director sends, comma separated (empty: all of %s)" % ", ".join(ZzNpcs.SPECIALS))
	if kinds != null:
		kinds.changed.connect(func(_old: String, now: String) -> void:
			var wanted := PackedStringArray()
			for part in now.split(",", false):
				if ZzNpcs.SPECIALS.has(StringName(part.strip_edges())):
					wanted.append(part.strip_edges())
			config.special_kinds = wanted
			log_info("a tunable changed", {"cvar": "zz_special_kinds", "now": ",".join(wanted)}))
	_tunable("zz_brute_min", config.brute_interval_min, "Seconds between brutes, from (0 with zz_brute_max 0: never)",
		func(value: float) -> void: config.brute_interval_min = clampf(value, 0.0, config.brute_interval_max))
	_tunable("zz_brute_max", config.brute_interval_max, "Seconds between brutes, to",
		func(value: float) -> void: config.brute_interval_max = clampf(value, config.brute_interval_min, 3600.0))
	_tunable("zz_director", 1.0 if config.director_enabled else 0.0, "Whether the build-up / peak / relax pressure runs",
		func(value: float) -> void: config.director_enabled = value > 0.5)
	_tunable("zz_sleepers", 1.0 if config.sleepers_enabled else 0.0, "Whether the maps' sleepers are there (next map)",
		func(value: float) -> void: config.sleepers_enabled = value > 0.5)
	_tunable("zz_box_drops", 1.0 if config.boxes_enabled else 0.0, "Whether zombies drop boxes",
		func(value: float) -> void: config.boxes_enabled = value > 0.5)
	_tunable("zz_box_common", config.box_drop_common, "Chance a common drops a box",
		func(value: float) -> void: config.box_drop_common = clampf(value, 0.0, 1.0))
	_tunable("zz_box_special", config.box_drop_special, "Chance a special drops a box",
		func(value: float) -> void: config.box_drop_special = clampf(value, 0.0, 1.0))
	_tunable("zz_box_carry", float(config.box_carry), "How many boxes a survivor carries (0: E opens them on the ground)",
		func(value: float) -> void: config.box_carry = clampi(int(value), 0, 6))
	_tunable("zz_box_deploy_seconds", config.box_deploy_seconds, "Seconds the deploy key is held to open a carried box",
		func(value: float) -> void: config.box_deploy_seconds = clampf(value, 0.5, 15.0))
	_tunable("zz_box_labels", 1.0 if config.box_labels else 0.0, "Whether a box says its type before it is opened",
		func(value: float) -> void: config.box_labels = value > 0.5)
	_tunable("zz_box_instakill_min", config.box_instakill_min, "Instakill lasts at least this many seconds (negative: the box file's)",
		func(value: float) -> void: config.box_instakill_min = value)
	_tunable("zz_box_instakill_max", config.box_instakill_max, "Instakill lasts at most this many seconds (negative: the box file's)",
		func(value: float) -> void: config.box_instakill_max = value)
	_tunable("zz_box_instakill_special_scale", config.box_instakill_special_scale, "Instakill: what a special takes per hit, as a multiple",
		func(value: float) -> void: config.box_instakill_special_scale = clampf(value, 1.0, 100.0))
	_tunable("zz_gravity", config.gravity, "Metres per second squared, for everything",
		func(value: float) -> void: config.gravity = value)
	_tunable("zz_spectate_camera", float(config.spectate_camera),
		"Who somebody who is out may watch: 0 anybody, 1 their own side, 2 nobody",
		func(value: float) -> void:
			config.spectate_camera = clampi(int(value), 0, 2)
			if world.spectate != null:
				world.spectate.set_force_camera(config.spectate_camera))
	# How a survival map is held: `zz_survival waves|nights|clock` (by name or 0/1/2), and its
	# numbers. Read when a hold begins, so a change takes from the next survival map.
	var style := add_cvar("zz_survival", config.survival_style_name(),
		"How survival maps are held: waves (the default: waves to clear), nights (days to get ready, nights to live through) or clock")
	if style != null:
		style.changed.connect(func(_old: String, now: String) -> void:
			var picked := DotNpcDirectorWaves.style_from(now)
			if picked >= 0:
				config.survival_style = picked
			log_info("survival style", {"now": config.survival_style_name()}))
	_tunable("zz_waves", float(config.waves), "Waves a survival map is held for (zz_survival waves)",
		func(value: float) -> void: config.waves = clampi(int(value), 1, 50))
	_tunable("zz_nights", float(config.nights), "Nights a survival map is held for (zz_survival nights)",
		func(value: float) -> void: config.nights = clampi(int(value), 1, 20))
	_tunable("zz_breather", config.breather_seconds, "Seconds of breather between waves",
		func(value: float) -> void: config.breather_seconds = clampf(value, 0.0, 300.0))
	_tunable("zz_survival_warmup", config.survival_warmup_seconds, "Seconds before the first wave or night",
		func(value: float) -> void: config.survival_warmup_seconds = clampf(value, 0.0, 300.0))
	_tunable("zz_day_seconds", config.day_seconds, "Seconds of day between nights",
		func(value: float) -> void: config.day_seconds = clampf(value, 10.0, 900.0))
	_tunable("zz_night_seconds", config.night_seconds, "Seconds a night lasts",
		func(value: float) -> void: config.night_seconds = clampf(value, 10.0, 1800.0))
	_tunable("zz_wave_size", float(config.wave_size), "The first wave's commons for one survivor",
		func(value: float) -> void: config.wave_size = clampi(int(value), 1, 400))
	_tunable("zz_wave_size_per_survivor", float(config.wave_size_per_survivor), "And for each survivor more",
		func(value: float) -> void: config.wave_size_per_survivor = clampi(int(value), 0, 50))
	_tunable("zz_wave_growth", config.wave_growth, "How much bigger each wave is than the first, as a share of it",
		func(value: float) -> void: config.wave_growth = clampf(value, 0.0, 2.0))
	_tunable("zz_wave_twists", 1.0 if config.wave_twists else 0.0, "1: waves from the third draw a twist (sprinters, swarm, heavies, hunters)",
		func(value: float) -> void: config.wave_twists = value >= 0.5)
	_tunable("zz_brute_every", float(config.brute_every_waves), "Every this many waves a brute comes (and two with the last); 0 never",
		func(value: float) -> void: config.brute_every_waves = clampi(int(value), 0, 50))
	_tunable("zz_barricade_health", config.barricade_health, "A barricade's strength when the map does not say",
		func(value: float) -> void: config.barricade_health = clampf(value, 10.0, 10000.0))
	_tunable("zz_barricade_bash", config.barricade_bash, "What one zombie's bashing takes off a barricade a second",
		func(value: float) -> void: config.barricade_bash = clampf(value, 0.0, 200.0))
	_tunable("zz_team_from_map", 1.0 if config.team_from_map else 0.0,
		"1: stand-ins fill to the team a map is built for (its survivors) when that is more than bot_quota",
		func(value: float) -> void: config.team_from_map = value >= 0.5)
	# [b]Deprecated: the count is `bot_quota` now[/b], and this forwards to it. Kept rather than
	# removed because every shipped server config sets it; left as its own number it would be
	# a second cvar deciding the same count, and whichever was read last would win.
	_tunable("zz_min_players", float(config.minimum_players),
		"Deprecated, sets bot_quota. How many survivors the server keeps in the game with stand-ins",
		func(value: float) -> void:
			config.minimum_players = clampi(int(value), 0, 24)
			if _quota != null and _quota.quota_cvar != null:
				var _set := _quota.quota_cvar.set_value(str(config.minimum_players)))
	# [b]How the stand-ins aim and shoot is dot-bot's[/b]: `bot_difficulty` (easy, medium, hard,
	# nightmare; medium by default) and every `bot_*` setting it bundles, the names every game in
	# the family uses. On the game as metadata, where ZzBots reads it; never the registry, since
	# two servers in one process must not share it. `zz_bot_reaction` stays as the old name for
	# `bot_reaction`, so a server config that set it still means what it meant.
	var bot_settings := DotBotSettings.of(game)
	var _bot_cvars := bot_settings.bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY, add_command)
	_tunable("zz_bot_reaction", bot_settings.profile.reaction, "Deprecated, sets bot_reaction. Seconds a stand-in takes to react to a zombie",
		func(value: float) -> void:
			var _set := bot_settings.set_value("reaction", str(value)))

	# How clever and how quick the zombies are, as dot-npc-ai's server skill: `npc_skill`
	# (-1..1 or a level), `npc_reaction_scale`, `npc_reaction_min`.
	if world.horde != null:
		var _bound := world.horde.skill.bind_cvars(add_cvar)


## Writes [param key] into the live catalogue's definition of [param kind], if there is one yet.
func _set_meta(world: ZzGame, kind: StringName, key: String, value: float) -> void:
	if world.horde == null or world.horde.catalogue == null:
		return

	var def := world.horde.catalogue.get_npc(kind)

	if def != null:
		def.meta[key] = value


func _apply_friendly_fire(world: ZzGame) -> void:
	if world.combat == null or world.combat.rules == null:
		return

	world.combat.rules.friendly_fire = world.config.friendly_fire_scale() > 0.0
	world.combat.rules.friendly_scale = clampf(world.config.friendly_fire_scale(), 0.0, 2.0)


## A number as an operator would type it: `34`, not `34.000000`.
##
## [b]Not `%g`, which GDScript's format strings do not have.[/b] It is accepted by the parser
## and fails at RUNTIME with "unsupported format character" — inside `_game_load`, which is
## the one place in the module sequence that unwinds everything above it. The symptom in
## game-buses-from-hell was a server whose netcode came up, logged that it was ready, and
## then reported that the game would not load.
static func _number(value: float) -> String:
	return "%d" % int(round(value)) if is_equal_approx(value, round(value)) else "%.3f" % value


## One cvar, its default taken from the configuration rather than written twice.
##
## [b]The default is the value the world was built with, and that is the whole point.[/b] A
## cvar declared with a literal default is a second copy of a number that
## `defaults < JSON < environment < argv` has already decided — so an operator who set
## `ZZ_ROUND_SECONDS=240` would see `zz_round_seconds` report 300 and, worse, would reset
## their own setting the moment anything wrote the value back.
func _tunable(
	cvar_name: String, current: float, description: String, apply: Callable
) -> void:
	var cvar := add_cvar(cvar_name, _number(current), description)

	if cvar == null:
		return

	cvar.changed.connect(func(_old: String, _new: String) -> void:
		apply.call(cvar.get_float())
		log_info("a tunable changed", {"cvar": cvar_name, "now": cvar.get_string()})
	)


## [b]Nothing to undo.[/b] The commands are the module's own and [DotModule] removes them;
## the netcode, the bridge and the roster are [DotGameModule]'s and it tears them down in
## the reverse order it built them. The world is NOT this module's to free: it was in the
## tree before the module loaded, and a server can unload and reload a game module without
## the map going away, which is what `module reload` is for.
func _game_unload() -> void:
	_bot_ids.clear()

	if vote != null:
		vote.queue_free()
		vote = null


## The server slept or woke. The vote's director follows it on its own (DotGameModule finds
## it); the map ballot's timer is this game's, so it starts again here on waking.
func _game_hibernation(hibernating: bool) -> void:
	if not hibernating and vote != null:
		vote.note_woke()


## Keeps enough people in the round for there to be one.
##
## [b]A team, not one person against the horde.[/b] Everything about the genre — the downs that
## need a friend, the specials that need somebody to shove them off — assumes four; a server
## with one person on it fills the rest with stand-ins, and takes one out the moment a person
## takes their place.
func _game_tick(_tick: int, delta: float) -> void:
	if vote != null:
		vote.advance(delta)

	if voteban != null:
		voteban.advance(delta)

	_since_roster_check += delta

	if _since_roster_check < ROSTER_INTERVAL:
		return

	_since_roster_check = 0.0
	_keep_the_round_full()
	_note_pings()


## Each session's ping onto its player, for the Tab board. dot-server already keeps it.
func _note_pings() -> void:
	var world := game as ZzGame
	if world == null or server == null:
		return
	for session in server.playing_sessions():
		var who: ZzPlayer = world.players.get(ZzNetBridge.player_key(session.userid))
		if who != null:
			who.ping_ms = session.ping_ms


func _keep_the_round_full() -> void:
	var world := game as ZzGame

	if world == null or bridge == null or _quota == null:
		return

	# People only. A stand-in is not one, and neither is a bot somebody put in by hand through
	# the bridge (a test, an admin): those are never in `_bot_ids` either, so they are left
	# alone and outside the count. A leaver is gone from `players` the moment the bridge
	# removes them, so nobody half-disconnected is counted.
	var humans := 0

	for id: StringName in world.players:
		if not (world.players[id] as ZzPlayer).is_bot:
			humans += 1

	# Forget any that have gone for some other reason — a round reset, an admin — so the
	# count below is of stand-ins that actually exist.
	for index in range(_bot_ids.size() - 1, -1, -1):
		if not world.players.has(_bot_ids[index]):
			_bot_ids.remove_at(index)

	# `zz_bots 0` takes the stand-ins out as well as not adding more: a switch that left the
	# ones already in until a map change would be an operator with no way to empty a server.
	var wanted := 0

	if _bots == null or _bots.get_bool():
		var slots: int = server.config.max_players if server != null and server.config != null else -1
		wanted = _quota.wanted(humans, slots)

		# A map built for a dozen raises the count to a dozen, in fill mode (the default): the
		# school with four people in it is a school with forty windows nobody is at. The
		# operator's bot_quota still wins when it is higher, and `zz_team_from_map 0` turns
		# this off.
		if _quota.mode() == DotBotQuota.Mode.FILL and world.team_size() > _quota.quota():
			wanted = DotBotQuota.compute(DotBotQuota.Mode.FILL, world.team_size(), humans, slots,
				_quota.empty_cvar == null or _quota.empty_cvar.get_bool())

	for _i in range(maxi(wanted - _bot_ids.size(), 0)):
		var bot: ZzPlayer = bridge.call("add_bot", _bot_name(world))

		if bot == null:
			break

		_bot_ids.append(bot.player_id)

	# Newest first, so the stand-in a person replaces is the one that arrived last and the
	# ones that have been playing longest keep playing.
	while _bot_ids.size() > wanted:
		var leaving: StringName = _bot_ids.pop_back()
		bridge.call("remove_player", ZzNetBridge.session_of(leaving))


## Names for the stand-ins, so a scoreboard of four of them is readable: one nobody in
## [param world] has yet, from this game's own survivors through dot-bot's [DotBotNames] (which
## never doubles one up and is the same from run to run). Drawn at random, it once gave a
## dedicated run three called Odell.
static func _bot_name(world: ZzGame) -> String:
	var taken: Array = []

	for id: StringName in world.players:
		taken.append((world.players[id] as ZzPlayer).display_name)

	return DotBotNames.pick(taken, world.players.size(), ZzBots.BOT_NAMES)


## Joins the bridge's chat seam to the services layer's router.
##
## [b]Here rather than in either of them, because this is the only object that holds
## both.[/b] The bridge knows what arrived on the wire and nothing about what a line means;
## the services layer knows the rules and nothing about the wire. That separation is why a
## client cannot send a line with somebody else's name on it: what crosses is a channel id
## and a string, and everything else is decided on this side.
func _wire_chat() -> void:
	if bridge == null or services == null:
		return

	bridge.connect("say_requested", _on_say_requested)
	services.connect("command_entered", _on_chat_command)


## The players' vote for the next map, over dot-vote: `!vote`, `!rtv`, `!nominate`.
##
## [b]Opened [member ZzVote.open_after_sec] into the last round on a map and applied when that
## round ends[/b]; see [code]game/zz_vote.gd[/code]. A server owner turns it off or reshapes it
## in `user://cfg/zombiezone_vote.json` or `game.yml`'s `metadata: map_vote:`, keyed as dot-vote's
## [DotVoteRules]. A vote that cannot be built is a WARN and the rotation alone, never a server
## that will not start.
func _build_vote(world: ZzGame) -> void:
	if world.catalogue == null:
		return

	vote = ZzVote.new()
	vote.name = "MapVote"
	vote.commands_spec_fn = world.rotation_commands
	vote.in_rotation_fn = func(id: StringName) -> bool: return world.catalogue.in_rotation(id)
	vote.maps_fn = func() -> Array:
		var out: Array = []

		for id in world.catalogue.rotating(world.config.map_ids):
			# Pack maps join the ballot through dot-vote's follow_content, with their pack's name.
			if not world.catalogue.is_content(id):
				out.append([id, str((world.catalogue.maps.get(id, {}) as Dictionary).get("name", id))])

		return out
	vote.apply_fn = func(id: StringName) -> DotResult:
		# A Workshop map on a solo ballot is a catalogue map once the catalogue has read the index.
		world.catalogue.sync_content()
		if not world.catalogue.maps.has(id):
			return DotResult.fail(DotError.CODE_STATE, "There is no map called '%s' here." % id)
		world.next_map_id = id
		return DotResult.success(id)
	# Due on the last map of a campaign (one that names no next map) and on a survival map:
	# a vote in the middle of a campaign would be a vote to leave it.
	vote.due_fn = func() -> bool:
		return str(world.map_doc.get("next", "")) == ""
	vote.voters_fn = func() -> Array:
		var out: Array = []

		for id: Variant in world.players:
			var player: ZzPlayer = world.players[id]

			if player == null or player.is_bot:
				continue

			var userid := ZzNetBridge.session_of(StringName(str(id)))

			if userid > 0:
				out.append(StringName(str(userid)))

		return out
	vote.announce_fn = func(line: String) -> void:
		var chat: Object = services.get("chat") if services != null else null

		if chat != null:
			var _said: Variant = chat.call("announce", line, ZzServices.CH_ALL)
		elif server != null:
			server.broadcast_message(line)
	vote.is_admin_fn = func(voter: StringName) -> bool:
		var session := server.session_by_userid(String(voter).to_int()) if server != null else null
		return session != null and session.has_permission(DotAdminFlags.CHANGEMAP)
	vote.ballot_fn = func(state: Dictionary) -> void:
		if server == null:
			return

		for session in server.playing_sessions():
			var data := state.duplicate()
			data["you"] = str(session.userid)
			server.send_notice(session, DotNotice.make(
				&"", "", float(state.get("seconds", -1.0)), MAP_BALLOT_TOPIC, data
			))
	vote.people_fn = func(voter: StringName) -> Dictionary:
		var session := server.session_by_userid(String(voter).to_int()) if server != null else null

		if session == null:
			return {}

		var avatar: Variant = session.identity.get("avatar_url") if session.identity != null else ""
		return {"name": session.display_name, "avatar": avatar if avatar is String else ""}

	# Whether a round is live, for `time_up: finish_round`: warmup and the gap between rounds
	# have nothing to play out, so a limit that runs out there changes at once. No match is
	# "cannot tell", which holds as before.
	vote.round_in_progress_fn = func() -> bool:
		return world.match_node == null or world.match_node.is_live()

	add_child(vote)
	var ready := vote.setup()

	if not ready.ok:
		DotLog.result(CHANNEL, "the map vote; the rotation alone chooses", ready)
		vote.queue_free()
		vote = null
		return

	var commanded := vote.install_commands(self)
	DotLog.result(CHANNEL, "the map vote's commands", commanded)

	# The map menu (M), dot-vote's: a player holding the owner's `sv_map_menu_flag` changes the
	# map now, not after this one, and sees the same rows a solo player does. Read by name,
	# because a server on a dot-vote older than the menu has no `map_menu` and runs without it.
	var menu_half: Variant = vote.commands.get(&"map_menu") if vote.commands != null else null
	if menu_half is Object:
		(menu_half as Object).set(&"change_fn", world.change_map_now)
		(menu_half as Object).set(&"rows_fn", func(_rows: Array) -> Array: return world.map_rows())

	_tunable("zz_vote_after", vote.open_after_sec,
		"Seconds into the last round on a map before the vote for the next one opens",
		func(value: float) -> void:
			if vote != null:
				vote.open_after_sec = maxf(value, 0.0))

	world.world_rebuilt.connect(func() -> void:
		if vote != null and world.map != null:
			vote.note_map(world.map.id())
	)
	world.round_began.connect(func(_number: int, _map: StringName) -> void:
		if vote != null:
			vote.note_round_start()
	)
	world.match_node.round_ended.connect(func(_number: int, _winner: int, _outcome: int) -> void:
		if vote != null:
			vote.note_round_end()
	)

	if server != null:
		server.client_disconnected.connect(func(session: DotClientSession, _reason: String) -> void:
			if vote != null:
				vote.forget_voter(StringName(str(session.userid)))
		)


## Votebans, dot-vote's `DotVoteBans`, and the two things team damage asks of them: a vote
## ([member ZzConfig.team_damage_vote]) and an outright ban ([member ZzConfig.team_damage_ban]).
## Loaded by path so a host whose dot-vote predates them runs without; a game never names the
## class. Voter ids are the session's userid, the same as the map vote's.
func _build_voteban(world: ZzGame) -> void:
	var path := "res://addons/dot_vote/runtime/dot_vote_bans.gd"

	if not ResourceLoader.exists(path):
		log_info("this host's dot-vote has no votebans; team damage can still ban")
		return

	voteban = (load(path) as GDScript).new()
	voteban.set("voters_fn", func() -> Array:
		var out: Array = []

		for id: Variant in world.players:
			if not (world.players[id] as ZzPlayer).is_bot:
				out.append(StringName(str(ZzNetBridge.session_of(StringName(str(id))))))

		return out)
	voteban.set("role_fn", func(who: StringName) -> String: return _role_of(String(who).to_int()))
	voteban.set("name_fn", func(who: StringName) -> String:
		var session := server.session_by_userid(String(who).to_int()) if server != null else null
		return session.display_name if session != null else String(who))
	voteban.set("ban_fn", func(who: StringName, minutes: float, reason: String) -> void:
		_ban_player(String(who).to_int(), minutes, reason, "voteban"))
	voteban.set("announce_fn", func(line: String) -> void: _announce(line))
	voteban.set("voter_fn", func(ctx: Object) -> StringName:
		var session: Variant = ctx.get("session")
		var userid: Variant = (session as Object).get("userid") if session is Object else null
		return StringName(str(userid)) if userid != null else &"console")
	voteban.set("resolve_fn", func(text: String) -> StringName:
		var wanted := text.strip_edges().to_lower()

		for id: Variant in world.players:
			var who: ZzPlayer = world.players[id]
			var userid := ZzNetBridge.session_of(StringName(str(id)))

			if who.is_bot or userid <= 0:
				continue

			if wanted == str(userid) or who.display_name.to_lower() == wanted:
				return StringName(str(userid))

		# A part of a name, only when it names exactly one: a vote against the wrong person
		# is worse than a refused one.
		var found: StringName = &""
		var count := 0

		for id: Variant in world.players:
			var who: ZzPlayer = world.players[id]

			if not who.is_bot and who.display_name.to_lower().contains(wanted):
				found = StringName(str(ZzNetBridge.session_of(StringName(str(id)))))
				count += 1

		return found if count == 1 else &"")

	var bound: DotResult = voteban.call("bind_commands", self)
	DotLog.result(CHANNEL, "the voteban's commands", bound)

	world.team_damage.voteban_wanted.connect(func(player_id: StringName, damage: float) -> void:
		var target := StringName(str(ZzNetBridge.session_of(player_id)))
		var started: DotResult = voteban.call("start", &"", target,
			"%d team damage in %d seconds" % [int(damage), int(world.config.team_damage_window)])
		DotLog.result(CHANNEL, "a voteban for team damage", started))
	world.team_damage.ban_wanted.connect(func(player_id: StringName, damage: float, minutes: float) -> void:
		var userid := ZzNetBridge.session_of(player_id)

		if bool(voteban.get("rules").call("is_immune", _role_of(userid))):
			return

		_ban_player(userid, minutes, "%d team damage in %d seconds" % [int(damage), int(world.config.team_damage_window)], "teamdamage"))

	if server != null:
		server.client_disconnected.connect(func(session: DotClientSession, _reason: String) -> void:
			if voteban != null:
				voteban.call("forget_voter", StringName(str(session.userid)))
		)


## "admin", "staff" or "player", for the voteban's start and immunity roles.
func _role_of(userid: int) -> String:
	var session := server.session_by_userid(userid) if server != null else null

	if session == null:
		return "player"

	if session.has_permission(DotAdminFlags.ROOT) or session.has_permission(DotAdminFlags.BAN):
		return "admin"

	return "staff" if session.has_permission(DotAdminFlags.GENERIC) else "player"


func _announce(line: String) -> void:
	var chat: Object = services.get("chat") if services != null else null

	if chat != null:
		var _said: Variant = chat.call("announce", line, ZzServices.CH_ALL)
	elif server != null:
		server.broadcast_message(line)


## Bans a connected person for [param minutes] (0 for ever) and removes them, the way dot-server's
## own `ban` command does: by account, by address for a guest.
func _ban_player(userid: int, minutes: float, reason: String, by: String) -> void:
	var session := server.session_by_userid(userid) if server != null else null

	if session == null or server.bans == null:
		DotLog.warn(CHANNEL, "a ban could not be carried out", {"userid": userid, "by": by})
		return

	var name := session.display_name
	var banned: DotResult = await server.bans.ban_session(session, reason, int(minutes * 60.0), by)

	if not banned.ok:
		DotLog.result(CHANNEL, "a ban", banned)
		return

	server.kick(session, "Banned: %s" % reason)
	var _also := server.enforce_bans("Banned: %s" % reason)
	_announce("%s was banned: %s" % [name, reason])


## The map is what a server listing prints, reported on every rebuild: the server forgets it
## whenever a game unloads, and a browser showing last round's map is a browser lying.
func _wire_map(world: ZzGame) -> void:
	if world.map != null and not world.map.doc.is_empty():
		report_map(String(world.map.id()))

	world.world_rebuilt.connect(func() -> void:
		report_map(String(world.map.id()))
	)


## An achievement is told to the one person who earned it.
##
## [b]As a notice, which a client already draws in its chat box[/b], rather than a new event
## kind: an unlock is text for one player, which is exactly what a notice is — and a stand-in
## never earns one, because [ZzProgress] does not count them.
func _wire_progress(world: ZzGame) -> void:
	if bridge == null:
		return

	# What a player keeps is filed under their scoped profile key, so it outlives the
	# connection; see [ZzProgress]. Nothing for a stand-in or a guest, who keep their seat's.
	if world.progress != null:
		world.progress.durable_key_fn = func(id: StringName) -> String:
			var session := server.session_by_userid(ZzNetBridge.session_of(id)) \
				if server != null else null
			var platform: Object = server.modules.get_module("platform") \
				if server != null and server.modules != null else null

			if session == null or platform == null or not platform.has_method("player_for"):
				return ""

			var held: Variant = platform.call("player_for", session)
			return str((held as Object).call("key")) if held is Object else ""

	world.achievement_earned.connect(func(id: StringName, title: String, points: int) -> void:
		var peer_id: int = bridge.call("peer_for_player", ZzNetBridge.session_of(id))

		if peer_id > 0:
			bridge.call("notice", peer_id, "Achievement: %s (+%d)" % [title, points])
	)


func _on_say_requested(peer_id: int, channel_id: StringName, text: String) -> void:
	var said: DotResult = services.call("say", peer_id, channel_id, text)

	if said.ok:
		return

	# Back to the one person who asked. A refusal broadcast would be a rate limit announced
	# to the server.
	bridge.call("notice", peer_id, said.error.message)


## A `!command` typed into chat. Run through the console as the person who typed it.
##
## [b]As THEM, not as the server.[/b] `run_command_as_uid` builds a context with that
## player's own flags, so `!kick` from somebody without the flag is refused by the same file
## that refuses it at the console — rather than by this function having an opinion.
func _on_chat_command(peer_id: int, command: String, args: PackedStringArray) -> void:
	if server == null:
		return

	var session := server.session_of(peer_id)

	if session == null:
		return

	for reply in server.run_command_as_uid(
		session.uid(), command, args, DotCmdContext.Source.CHAT
	):
		bridge.call("notice", peer_id, reply)


func _cmd_say(ctx: DotCmdContext) -> void:
	var text := ctx.rest()

	if text.strip_edges() == "":
		ctx.reply("Say what?")
		return

	if services == null or services.get("chat") == null:
		ctx.reply("This server has no chat.")
		return

	var announced: Variant = services.get("chat").call("announce", text, ZzServices.CH_ALL)

	if announced is DotResult and not (announced as DotResult).ok:
		ctx.reply_error(announced)
		return

	ctx.reply("Said: %s" % text)


func _cmd_status(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null:
		ctx.reply("No world.")
		return

	ctx.reply_lines(world.describe_lines())


func _cmd_net(ctx: DotCmdContext) -> void:
	if bridge == null:
		ctx.reply("No bridge; this server is not replicating anything.")
		return

	ctx.reply_lines(bridge.call("describe_lines"))

	if services != null:
		ctx.reply_lines(services.call("describe_lines"))


func _cmd_maps(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.catalogue == null:
		ctx.reply("No world.")
		return

	ctx.reply_lines(world.catalogue.describe_lines())
	ctx.reply("playing: %s" % str(world.map_doc.get("id", "-")))


func _cmd_map(ctx: DotCmdContext) -> void:
	var world := game as ZzGame
	var id := StringName(ctx.arg(0)) if ctx.argc() > 0 else &""

	if world == null or world.catalogue == null:
		ctx.reply("No world.")
		return

	if id == &"" or not world.catalogue.playable(world.config.map_ids).has(id):
		ctx.reply("Which map? %s" % ", ".join(world.catalogue.playable(world.config.map_ids)))
		return

	world.next_map_id = id
	ctx.reply("%s is next, from the end of this round." % String(id))


func _cmd_rotation(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.catalogue == null or not world.catalogue.has_rotation_file():
		ctx.reply("There is no maps.yml; every map rotates.")
		return

	var file := world.catalogue.rotation_file

	if ctx.argc() == 0:
		ctx.reply("Rotations: %s (active: %s)" % [", ".join(file.rotation_names()), file.active_name()])
		return

	var wanted := ctx.arg(0)
	var switched := world.catalogue.switch_rotation(wanted)

	if not switched.ok:
		ctx.reply(switched.error.message)
		return

	if vote != null:
		vote.refresh_maps()

	ctx.reply("Rotation: %s" % wanted)


func _cmd_maps_reload(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.catalogue == null:
		ctx.reply("No world.")
		return

	var read := world.load_rotation()

	if vote != null:
		vote.refresh_maps()

	ctx.reply("maps.yml read." if read.ok else read.error.message)


func _cmd_boxes(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.boxes == null:
		ctx.reply("No boxes.")
		return

	for id in world.boxes.order:
		var box: Dictionary = world.boxes.types[id]
		var titles := PackedStringArray()

		for o: Dictionary in box["outcomes"]:
			titles.append(str(o["title"]))

		ctx.reply("%-12s %-18s %s" % [String(id), str(box["title"]), ", ".join(titles)])


## Where an admin command puts something: in front of whoever typed it, or by the team.
func _command_spot(ctx: DotCmdContext, ahead: float) -> Vector3:
	var world := game as ZzGame
	var who: ZzPlayer = world.players.get(ZzNetBridge.player_key(ctx.session.userid)) \
		if ctx.session != null else null

	if who == null:
		for player in world.survivors():
			if player.is_up():
				who = player
				break

	if who == null:
		return Vector3.INF

	var at := who.feet() + who.aim_direction() * Vector3(1.0, 0.0, 1.0) * ahead
	return world.horde.snap_to_nav(at) if world.horde != null else at


func _cmd_spawn(ctx: DotCmdContext) -> void:
	var world := game as ZzGame
	var kind := StringName(ctx.arg(0)) if ctx.argc() > 0 else &"common"
	var count := clampi(ctx.arg(1).to_int(), 1, 50) if ctx.argc() > 1 else 1

	if world == null or world.horde == null or world.horde.catalogue.get_npc(kind) == null:
		ctx.reply("Which? common, %s, brute, sleeper" % ", ".join(ZzNpcs.SPECIALS))
		return

	var at := _command_spot(ctx, 8.0)
	var made := 0

	for i in count:
		var npc: DotNpcInstance = world.horde.spawn_brute(at) if kind == ZzNpcs.BRUTE \
			else world.horde.spawner.spawn(kind, at + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)), &"admin")
		if npc != null:
			made += 1

	ctx.reply("%d %s." % [made, String(kind)])


func _cmd_box(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.boxes == null:
		ctx.reply("No boxes.")
		return

	var type := StringName(ctx.arg(0)) if ctx.argc() > 0 else world.boxes.random_type(&"map", RandomNumberGenerator.new())

	if not world.boxes.types.has(type):
		ctx.reply("Which? %s" % ", ".join(world.boxes.order))
		return

	var _dropped := world.boxes.drop(type, _command_spot(ctx, 2.0))
	ctx.reply("A %s." % world.boxes.title_of(type))


func _cmd_mob(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.horde == null:
		ctx.reply("No horde.")
		return

	var size := ctx.arg(0).to_int() if ctx.argc() > 0 else world.horde._mob_size()
	ctx.reply("%d coming." % world.horde.spawn_mob(clampi(size, 1, 200)))


func _cmd_panic(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.horde == null:
		ctx.reply("No horde.")
		return

	var seconds := clampf(ctx.arg(0).to_float(), 5.0, 600.0) if ctx.argc() > 0 else 30.0
	world.horde.panic(seconds)
	ctx.reply("Panic for %d s." % int(seconds))


func _cmd_reload(ctx: DotCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.catalogue == null:
		ctx.reply("No world.")
		return

	var loaded := world.catalogue.load_from(world.config.map_directory)
	loaded += await _add_delivered_maps(world)
	world.catalogue.apply_rotation(world.config.map_ids)

	if vote != null:
		vote.refresh_maps()

	ctx.reply("%d documents read; %d refused. The next map draws from them." % [
		loaded, world.catalogue.refused.size()])


## This game's columns on the Tab board: kills, specials, points.
func _game_board_fields(session: Object) -> Dictionary:
	var world := game as ZzGame
	var who: ZzPlayer = world.players.get(ZzNetBridge.player_key(int(session.get(&"userid")))) if world != null and session != null else null

	if who == null:
		return {}

	return {"points": who.points, "kills": who.commons_killed, "specials": who.specials_killed, "team": ZzGame.SURVIVORS}


func describe() -> Dictionary:
	var out := super.describe()
	var world := game as ZzGame

	if world != null:
		out.merge({"round": world.round_number, "world": world.describe()}, true)

	return out
