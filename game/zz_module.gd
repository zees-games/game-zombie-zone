extends "zz_module_tunables.gd"

func _game_load() -> GSResult:
	var world := game as ZzGame

	if world == null:
		return GSResult.fail(GSError.CODE_STATE, "The registered game is not an ZzGame.")

	world.world_key_fn = _world_key
	world.tick_gate.armed = true
	_game_commands(world)

	_wire_chat()
	_wire_identity()
	_wire_map(world)
	_wire_progress(world)
	_add_tunables(world)
	var _weapon_drop_cvars := world.weapon_layer.rules.bind_cvars(add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED)
	var _knife_cvars := GSWeaponKnives.bind_cvars(world.weapon_layer.knife_rules, add_cvar, "zz_knife", GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY)
	world.grenades.bind_cvars(add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY)
	world.consumables.bind_cvars(add_cvar, GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED)

	# The top-left team-mate list: `zz_team_roster` 0 (the default) or 1. REPLICATED, because
	# the HUD is drawn by each client; the config file / argv set it through ZzConfig, and a
	# value set first is what the cvar starts as.
	var roster := add_cvar("zz_team_roster", "1" if world.config.team_roster else "0",
		"Show the team-mate health list at the top left of the HUD (0 or 1)",
		GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED)
	if roster != null:
		world.config.team_roster = roster.get_string().strip_edges() == "1"
		roster.changed.connect(func(_old: String, new_value: String) -> void:
			world.config.team_roster = new_value.strip_edges() == "1")

	# Whether shots pass through team-mates: `mp_teammate_passthrough` 0 never, 1 a team-mate holding
	# the muzzle (default), 2 every one in the line. dot-combat's cvar, live from the next shot; NOTIFY,
	# and REPLICATED because every client's manager predicts its tracers under it.
	if world.combat != null:
		var _passthrough := world.combat.bind_cvars(add_cvar, GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED)
		_reconcile_friendly_fire(world, _passthrough)

	# sv_falldamage, _threshold, _scale: dot-combat's, on by default in this game. Server-side
	# only, so no REPLICATED: the damage is the server's and arrives as health.
	var _fall := world.fall_rules.bind_cvars(add_cvar, GSConVar.FLAG_NOTIFY)

	# REPLICATED: the clients play the killcam, the server only lengthens the intermission for it.
	var killcam := add_cvar("mp_killcam_time", _number(world.config.killcam_seconds),
		"Seconds the killcam of a map's last moment plays, added to the intermission (0 for none)",
		GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED)
	if killcam != null:
		var _checked := killcam.with_validator(func(text: String) -> GSResult:
			var refused := _cap_refusal("mp_killcam_time", text.to_float(), [])
			return GSResult.success(text) if refused.is_empty() else GSResult.fail(GSError.CODE_INVALID, refused))
		killcam.changed.connect(func(_old: String, new_value: String) -> void:
			world.config.killcam_seconds = new_value.to_float()
			world.apply_intermission())

	# REPLICATED: where the clients' killcam camera sits (0 the killer's eye, 1 behind the killer).
	var _camera := add_cvar("mp_killview_camera", "0",
		"Killcam camera: 0 the killer's eye, 1 behind the killer (dot-replay GSKillcamFraming)",
		GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY | GSConVar.FLAG_REPLICATED)

	_bind_rule_cvars(world)

	_build_vote(world)
	_build_voteban(world)

	_bots = add_cvar(
		"zz_bots", "1",
		"Automatic stand-ins: 1 keeps as many as bot_quota and bot_quota_mode say, 0 none at all."
	)

	# How many is dot-server's [GSBotQuota], so `bot_quota` and `bot_quota_mode` mean the same on every
	# server in the family. Default: this game's `minimum_players` in fill mode; `zz_bots` stays the
	# switch it always was.
	_quota = GSBotQuota.install(self, world.config.minimum_players)

	# Started here, not in the world's `_ready`: `start()` builds the map, and before the bridge exists
	# nothing listens to `world_rebuilt`, so the server knows a map no client is told about (invisible
	# floors).
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

	_bind_config(world)
	_start_workbench(world)
	world.start()

	log_info("the map is up", world.describe())
	return GSResult.success(null)

## The commands the game adds to the console, the map ones under the names maps.yml gives them.
func _game_commands(world: ZzGame) -> void:
	add_command("zz_status", _cmd_status, "Show the map, the survivors and the horde")
	add_command("zz_net", _cmd_net, "Show what the netcode is doing")
	# The map commands are renameable from maps.yml's `commands:` block, like dot-vote's roles.
	for name in world.command_names("zz_maps"):
		add_command(name, _cmd_maps, "List the maps, and any refused file")
	for name in world.command_names("zz_reload"):
		add_command(name, _cmd_reload, "Read the map directory again (from the next map)")
	for name in world.command_names("zz_map"):
		add_command(name, _cmd_map, "Play a map next: zz_map <id> (when this one ends)", "")
	# The plain names every Source admin types: `map <id>` changes the map now (the map menu's path), `maps` lists them.
	for name in world.command_names("map"):
		add_command(name, _cmd_map_now, "Change the map now: map <id>", GSAdminFlags.CHANGEMAP)
	for name in world.command_names("maps"):
		add_command(name, _cmd_maps, "List the maps, and any refused file")
	add_command("zz_rotation", _cmd_rotation,
		"zz_rotation [name]: switch to a rotation in maps.yml, or list them", GSAdminFlags.CHANGEMAP)
	add_command("zz_maps_reload", _cmd_maps_reload, "Re-read maps.yml", GSAdminFlags.CHANGEMAP)
	var _file_cvar := add_cvar("sv_map_rotation_file", world.config.map_rotation_file,
		"maps.yml: the maps that rotate, in named rotations. Unlisted maps stay installed.")
	_file_cvar.changed.connect(func(_old: String, new_value: String) -> void:
		world.config.map_rotation_file = new_value.strip_edges()
		var _read := world.load_rotation()
		if vote != null:
			vote.refresh_maps())
	add_command("zz_say", _cmd_say, "Say something to everybody, as the server")
	add_command("zz_boxes", _cmd_boxes, "List the box types and what each can do")
	add_command("zz_class", _cmd_class, "List the classes, or pick one for your next spawn: zz_class [id] [model]")
	# What an admin does to a server to see what happens: a zombie, a box, a mob, a brute.
	add_command("zz_spawn", _cmd_spawn, "Spawn a zombie: zz_spawn <kind> [count] (near you, or the team)", "z")
	add_command("zz_box", _cmd_box, "Drop a box: zz_box [type] (in front of you, or the team)", "z")
	add_command("zz_mob", _cmd_mob, "Send a mob now: zz_mob [size]", "z")
	add_command("zz_panic", _cmd_panic, "Mobs back to back: zz_panic [seconds]", "z")


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


func _on_profile(event: GSEvent) -> void:
	var session_id := event.get_int("userid")
	var session := server.session_by_userid(session_id) if server != null else null
	var link := bridge as ZzNetBridge

	if session == null or link == null:
		return

	link.refresh_player(session_id, session.display_name, _avatar_for(session_id))

## dot-combat's `mp_friendlyfire` and this game's `zz_friendly_fire` / `zz_friendly_fire_mode` set the same rule, and the config's won on every difficulty change. Now `mp_friendlyfire 0` means mode 0 (off), `1` turns an off mode back to the default 2, and the cvar mirrors what the config resolved to. Defaults are unchanged.
func _reconcile_friendly_fire(world: ZzGame, made: Array) -> void:
	var ff: Object = null
	for cv: Variant in made:
		if cv is Object and str((cv as Object).get(&"name")) == GSCombatManager.CVAR_FRIENDLY_FIRE:
			ff = cv
	if ff == null:
		return
	ff.connect(&"changed", func(_old: String, now: String) -> void:
		if _mirroring_ff:
			return
		var on := now.strip_edges().to_lower() not in ["0", "false", ""]
		if on and world.config.friendly_fire_mode == 0:
			world.config.friendly_fire_mode = 2
		elif not on:
			world.config.friendly_fire_mode = 0
		_apply_friendly_fire(world))
	world.friendly_fire_changed = func(on: bool) -> void:
		var text := "1" if on else "0"
		if ff.call(&"get_string") != text:
			_mirroring_ff = true
			ff.call(&"force_set", text)
			_mirroring_ff = false

var _mirroring_ff := false

var _admin_rng := RandomNumberGenerator.new()

var _admin_rng_game: Object = null


## Nothing to undo: the commands are the module's own and [GSModule] removes them, the netcode,
## bridge and roster are [GSGameModule]'s. The world is NOT this module's to free: it predates the
## module, and `module reload` must not take the map away.
func _game_unload() -> void:
	_bot_ids.clear()

	if game is ZzGame:
		(game as ZzGame).tick_gate.disarm()

	if workbench != null:
		workbench.queue_free()
		workbench = null

	if vote != null:
		vote.queue_free()
		vote = null

## The server slept or woke. The vote's director follows it on its own (GSGameModule finds
## it); the map ballot's timer is this game's, so it starts again here on waking.
func _game_hibernation(hibernating: bool) -> void:
	if not hibernating and vote != null:
		vote.note_woke()

## Keeps enough people in the round for there to be one: the downs and specials assume a team of four,
## so a server with one person fills the rest with stand-ins and takes one out when a person
## takes the place.
func _game_tick(_tick: int, delta: float) -> void:
	_follow_npc_threads()

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

## The horde's sense workers and level of detail follow the cvars (dot-game's GSGameNpcLod).
func _follow_npc_threads() -> void:
	var world := game as ZzGame
	if world == null or world.horde == null or world.horde.spawner == null:
		return
	if server != null and server.config != null and server.config.has_method(&"npc_workers"):
		var forced := world.horde.forced_npc_workers()
		var workers := forced if forced >= 0 else int(server.config.call(&"npc_workers"))
		world.horde.spawner.sense_workers = workers
		world.horde.spawner.path_workers = workers
		world.horde.spawner.think_workers = workers
	if npc_lod == null or npc_lod.spawner != world.horde.spawner:
		var _lod := attach_npc_lod(world.horde.spawner)

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

	# People only. A stand-in is not one, nor a bot put in by hand through the bridge (a test, an admin):
	# those are never in `_bot_ids`, so they stay outside the count. A leaver is gone from `players` at
	# once, so nobody half-disconnected is counted.
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

		# A map built for a dozen raises the count to a dozen in fill mode (the default); the operator's
		# bot_quota still wins when higher, and `zz_team_from_map 0` turns this off.
		if _quota.mode() == GSBotQuota.Mode.FILL and world.team_size() > _quota.quota():
			wanted = GSBotQuota.compute(GSBotQuota.Mode.FILL, world.team_size(), humans, slots,
				_quota.empty_cvar == null or _quota.empty_cvar.get_bool())

	if world.config.bot_max > 0:
		wanted = mini(wanted, world.config.bot_max)

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

## Names for the stand-ins, so a scoreboard of four is readable: one nobody in [param world] has yet,
## from this game's survivors through dot-bot's [GSBotNames] (never doubles one up, same from run
## to run). Random drawing once gave a dedicated run three called Odell.
static func _bot_name(world: ZzGame) -> String:
	var taken: Array = []

	for id: StringName in world.players:
		taken.append((world.players[id] as ZzPlayer).display_name)

	return GSBotNames.pick(taken, world.players.size(), ZzBots.BOT_NAMES)

## Joins the bridge's chat seam to the services layer's router, here because this is the only object
## holding both: the bridge knows the wire, the services know the rules, so a client cannot send a
## line with somebody else's name (only a channel id and a string cross).
func _wire_chat() -> void:
	if bridge == null or services == null:
		return

	bridge.connect("say_requested", _on_say_requested)
	services.connect("command_entered", _on_chat_command)

## The players' vote for the next map, over dot-vote: `!vote`, `!rtv`, `!nominate`. Opened
## [member ZzVote.open_after_sec] into the last round, applied when it ends (game/zz_vote.gd); tuned in
## `user://cfg/zombiezone_vote.json` or `game.yml`; one that cannot be built is a WARN, never a halt.
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
	vote.apply_fn = func(id: StringName) -> GSResult:
		# A Workshop map on a solo ballot is a catalogue map once the catalogue has read the index.
		world.catalogue.sync_content()
		if not world.catalogue.maps.has(id):
			return GSResult.fail(GSError.CODE_STATE, "There is no map called '%s' here." % id)
		world.next_map_id = id
		return GSResult.success(id)
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
		return session != null and session.has_permission(GSAdminFlags.CHANGEMAP)
	vote.ballot_fn = func(state: Dictionary) -> void:
		if server == null:
			return

		for session in server.playing_sessions():
			var data := state.duplicate()
			data["you"] = str(session.userid)
			server.send_notice(session, GSNotice.make(
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
		GSLog.result(CHANNEL, "the map vote; the rotation alone chooses", ready)
		vote.queue_free()
		vote = null
		return

	var commanded := vote.install_commands(self)
	GSLog.result(CHANNEL, "the map vote's commands", commanded)

	# The map menu (M), dot-vote's: a player holding the owner's `sv_map_menu_flag` changes the
	# map now, not after this one, and sees the same rows a solo player does. Read by name,
	# because a server on a dot-vote older than the menu has no `map_menu` and runs without it.
	var menu_half: Variant = vote.commands.get(&"map_menu") if vote.commands != null else null
	if menu_half is Object:
		(menu_half as Object).set(&"change_fn", world.change_map_in_tick)
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
		server.client_disconnected.connect(func(session: GSClientSession, _reason: String) -> void:
			if vote != null:
				vote.forget_voter(StringName(str(session.userid)))
		)

## Votebans, dot-vote's `GSVoteBans`, for team damage: a vote ([member ZzConfig.team_damage_vote])
## and a ban ([member ZzConfig.team_damage_ban]). Loaded by path so a host whose dot-vote predates
## them runs without; voter ids are the session's userid.
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

	var bound: GSResult = voteban.call("bind_commands", self)
	GSLog.result(CHANNEL, "the voteban's commands", bound)

	world.team_damage.voteban_wanted.connect(func(player_id: StringName, damage: float) -> void:
		var target := StringName(str(ZzNetBridge.session_of(player_id)))
		var started: GSResult = voteban.call("start", &"", target,
			"%d team damage in %d seconds" % [int(damage), int(world.config.team_damage_window)])
		GSLog.result(CHANNEL, "a voteban for team damage", started))
	world.team_damage.ban_wanted.connect(func(player_id: StringName, damage: float, minutes: float) -> void:
		var userid := ZzNetBridge.session_of(player_id)

		if bool(voteban.get("rules").call("is_immune", _role_of(userid))):
			return

		_ban_player(userid, minutes, "%d team damage in %d seconds" % [int(damage), int(world.config.team_damage_window)], "teamdamage"))

	if server != null:
		server.client_disconnected.connect(func(session: GSClientSession, _reason: String) -> void:
			if voteban != null:
				voteban.call("forget_voter", StringName(str(session.userid)))
		)

## "admin", "staff" or "player", for the voteban's start and immunity roles.
func _role_of(userid: int) -> String:
	var session := server.session_by_userid(userid) if server != null else null

	if session == null:
		return "player"

	if session.has_permission(GSAdminFlags.ROOT) or session.has_permission(GSAdminFlags.BAN):
		return "admin"

	return "staff" if session.has_permission(GSAdminFlags.GENERIC) else "player"

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
		GSLog.warn(CHANNEL, "a ban could not be carried out", {"userid": userid, "by": by})
		return

	var name := session.display_name
	var banned: GSResult = await server.bans.ban_session(session, reason, int(minutes * 60.0), by)

	if not banned.ok:
		GSLog.result(CHANNEL, "a ban", banned)
		return

	server.kick(session, "Banned: %s" % reason)
	var _also := server.enforce_bans("Banned: %s" % reason)
	_announce("%s was banned: %s" % [name, reason])

## The map is what a server listing prints, reported on every rebuild: the server forgets it
## whenever a game unloads, and a browser showing last round's map is a browser lying.
func _wire_map(world: ZzGame) -> void:
	if world.map != null and not world.map.doc.is_empty():
		report_map(String(world.map.id()))
		_attach_visibility(world)

	world.world_rebuilt.connect(func() -> void:
		report_map(String(world.map.id()))
		_attach_visibility(world)
	)

## The checkout's converted world's PVS as the snapshot visibility (cvar net_visibility; dot-game 52). A map
## whose world is not on disk here (a server running the maps pack) clears it and sends by distance alone.
func _attach_visibility(world: ZzGame) -> void:
	if not has_method(&"use_map_visibility") or world.map == null:
		return
	var mesh: Object = null
	var prefix: String = world.map.local_world_prefix() if str(world.map.doc.get("world", "")) != "" else ""
	if prefix != "" and world.map.can_draw_world() and FileAccess.file_exists(prefix + ".json"):
		var read: GSResult = (load("res://addons/dot_map/bsp/dot_map_bsp_mesh.gd") as GDScript).call(&"load_prefix", prefix)
		mesh = read.value if read.ok else null
	var _on: Variant = call(&"use_map_visibility", mesh)

## An achievement is told to the one person who earned it, as a notice (a client already draws it in
## chat) rather than a new event kind; a stand-in never earns one ([ZzProgress] skips them).
func _wire_progress(world: ZzGame) -> void:
	if bridge == null:
		return

	# Filed under dot-game's stable per-server key (guests too), so it outlives the connection
	# and a restart; see [ZzProgress].
	if world.progress != null and stats_feed != null:
		# The board reads ZzProgress's own tracker, under the feed's own key (what durable_key_fn
		# below returns), so no player_key_fn: it would call back into key_for.
		stats_feed.tracker = world.progress.stats
		stats_feed.open_sessions = false

	if world.progress != null:
		world.progress.durable_key_fn = func(id: StringName) -> String:
			var session := server.session_by_userid(ZzNetBridge.session_of(id)) \
				if server != null else null
			return String(stats_feed.key_for(session)) if session != null and stats_feed != null else ""

	if world.progress != null:
		var progress := world.progress
		var report := add_cvar("zz_report_progress", "1" if world.config.report_progress else "0",
			"File player stats with the backbone (1) or keep them on this server (0); needs a STATS_WRITE client",
			GSConVar.FLAG_ARCHIVE | GSConVar.FLAG_NOTIFY).with_min(0.0).with_max(1.0)
		report.changed.connect(func(_old: String, new_value: String) -> void:
			progress.set_reporting(new_value.to_int() != 0))
		if report.get_string() == "1":
			progress.set_reporting(true)

	if world.progress != null:
		var progress := world.progress
		# stats_report is the family switch; zz_report_progress stays as its alias.
		var report := bind_stats_report(progress.set_reporting, PackedStringArray(["zz_report_progress"]))
		if world.config.report_progress and report.get_string() != "1":
			var _on := report.set_value("1")

	world.achievement_earned.connect(func(id: StringName, title: String, points: int) -> void:
		var peer_id: int = bridge.call("peer_for_player", ZzNetBridge.session_of(id))

		if peer_id > 0:
			bridge.call("notice", peer_id, "Achievement: %s (+%d)" % [title, points])
	)

func _on_say_requested(peer_id: int, channel_id: StringName, text: String) -> void:
	var said: GSResult = services.call("say", peer_id, channel_id, text)

	if said.ok:
		return

	# Back to the one person who asked. A refusal broadcast would be a rate limit announced
	# to the server.
	bridge.call("notice", peer_id, said.error.message)

## A `!command` typed into chat, run through the console as THEM, not the server:
## `run_command_as_uid` builds a context with the player's own flags, so the refusal is the same
## file's that refuses it at the console.
func _on_chat_command(peer_id: int, command: String, args: PackedStringArray) -> void:
	if server == null:
		return

	var session := server.session_of(peer_id)

	if session == null:
		return

	for reply in server.run_command_as_uid(
		session.uid(), command, args, GSCmdContext.Source.CHAT
	):
		bridge.call("notice", peer_id, reply)

func _cmd_say(ctx: GSCmdContext) -> void:
	var text := ctx.rest()

	if text.strip_edges() == "":
		ctx.reply("Say what?")
		return

	if services == null or services.get("chat") == null:
		ctx.reply("This server has no chat.")
		return

	var announced: Variant = services.get("chat").call("announce", text, ZzServices.CH_ALL)

	if announced is GSResult and not (announced as GSResult).ok:
		ctx.reply_error(announced)
		return

	ctx.reply("Said: %s" % text)

func _cmd_status(ctx: GSCmdContext) -> void:
	var world := game as ZzGame

	if world == null:
		ctx.reply("No world.")
		return

	ctx.reply_lines(world.describe_lines())

func _cmd_net(ctx: GSCmdContext) -> void:
	if bridge == null:
		ctx.reply("No bridge; this server is not replicating anything.")
		return

	ctx.reply_lines(bridge.call("describe_lines"))

	if services != null:
		ctx.reply_lines(services.call("describe_lines"))

func _cmd_maps(ctx: GSCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.catalogue == null:
		ctx.reply("No world.")
		return

	ctx.reply_lines(world.catalogue.describe_lines())
	ctx.reply("playing: %s" % str(world.map_doc.get("id", "-")))

func _cmd_map(ctx: GSCmdContext) -> void:
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

## `map <id>`: the map changes now, through the same path as the map menu ([method ZzGame.change_map_in_tick]).
func _cmd_map_now(ctx: GSCmdContext) -> void:
	var world := game as ZzGame
	var id := StringName(ctx.arg(0)) if ctx.argc() > 0 else &""

	if world == null or world.catalogue == null:
		ctx.reply("No world.")
		return

	if id == &"" or not world.catalogue.playable(world.config.map_ids).has(id):
		ctx.reply("Which map? %s" % ", ".join(world.catalogue.playable(world.config.map_ids)))
		return

	ctx.reply("Changing to %s." % String(id))
	var changed: GSResult = await world.change_map_in_tick(id)

	if not changed.ok:
		GSLog.error("mod.zz", "map: the change was refused", {"map": String(id), "why": changed.error.message})

func _cmd_rotation(ctx: GSCmdContext) -> void:
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

func _cmd_maps_reload(ctx: GSCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.catalogue == null:
		ctx.reply("No world.")
		return

	var read := world.load_rotation()

	if vote != null:
		vote.refresh_maps()

	ctx.reply("maps.yml read." if read.ok else read.error.message)

func _cmd_boxes(ctx: GSCmdContext) -> void:
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

## An admin command that spawns or drops something asks the physics space (floor rays, sight),
## so between ticks it waits for the next one; its reply comes from there.
func _in_tick(fn: Callable) -> void:
	var world := game as ZzGame
	if world == null:
		fn.call()
	else:
		world.tick_gate.run(fn)

## Where an admin command puts something: in front of whoever typed it, or by the team.
func _command_spot(ctx: GSCmdContext, ahead: float) -> Vector3:
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

func _cmd_spawn(ctx: GSCmdContext) -> void:
	_in_tick(_spawn_in_tick.bind(ctx))

func _spawn_in_tick(ctx: GSCmdContext) -> void:
	var world := game as ZzGame
	var kind := StringName(ctx.arg(0)) if ctx.argc() > 0 else &"common"
	var count := ctx.arg(1).to_int() if ctx.argc() > 1 else 1

	if count < 1:
		ctx.reply("spawn count is %d; it is 1 or more (no upper limit)." % count)
		return

	if world == null or world.horde == null or world.horde.catalogue.get_npc(kind) == null:
		ctx.reply("Which? common, %s, brute, sleeper" % ", ".join(ZzNpcs.SPECIALS))
		return

	var at := _command_spot(ctx, 8.0)
	var made := 0
	var rng := _admin_stream(world)

	for i in count:
		var npc: GSNpcInstance = world.horde.spawn_brute(at) if kind == ZzNpcs.BRUTE \
			else world.horde.spawner.spawn(kind, at + Vector3(rng.randf_range(-1.5, 1.5), 0.0, rng.randf_range(-1.5, 1.5)), &"admin")
		if npc != null:
			made += 1

	ctx.reply("%d %s." % [made, String(kind)])

## Admin spawn and box commands draw from the round's seed, never the global RNG, so a seeded
## round with the same commands repeats. Reseeded when the game object changes.
func _admin_stream(world: ZzGame) -> RandomNumberGenerator:
	if _admin_rng_game != world:
		_admin_rng_game = world
		_admin_rng.seed = int(world.config.seed_value) ^ hash("admin commands")
	return _admin_rng

func _cmd_class(ctx: GSCmdContext) -> void:
	var world := game as ZzGame

	if world == null:
		return

	var offered := ZzClasses.offered(world.config.class_select, world.config.class_allowed)

	if ctx.argc() == 0:
		var mine: ZzPlayer = world.players.get(ZzNetBridge.player_key(ctx.session.userid)) if ctx.session != null else null
		ctx.reply("You are %s. %s" % [String(mine.class_id) if mine != null else "?",
			"Offered: " + ", ".join(offered) if not offered.is_empty() else "Class selection is off."])
		return

	var who: ZzPlayer = world.players.get(ZzNetBridge.player_key(ctx.session.userid)) if ctx.session != null else null
	var res := world.request_class(who.player_id, ctx.arg(0), ctx.arg(1) if ctx.argc() > 1 else "") if who != null \
		else GSResult.fail(GSError.CODE_INVALID, "Not in the game.")
	ctx.reply("You will be %s from your next spawn." % ctx.arg(0) if res.ok else res.error.message)

func _cmd_box(ctx: GSCmdContext) -> void:
	_in_tick(_box_in_tick.bind(ctx))

func _box_in_tick(ctx: GSCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.boxes == null:
		ctx.reply("No boxes.")
		return

	var type := StringName(ctx.arg(0)) if ctx.argc() > 0 else world.boxes.random_type(&"map", _admin_stream(world))

	if not world.boxes.types.has(type):
		ctx.reply("Which? %s" % ", ".join(world.boxes.order))
		return

	var _dropped := world.boxes.drop(type, _command_spot(ctx, 2.0))
	ctx.reply("A %s." % world.boxes.title_of(type))

func _cmd_mob(ctx: GSCmdContext) -> void:
	_in_tick(_mob_in_tick.bind(ctx))

func _mob_in_tick(ctx: GSCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.horde == null:
		ctx.reply("No horde.")
		return

	var size := ctx.arg(0).to_int() if ctx.argc() > 0 else world.horde._mob_size()
	if size < 1:
		ctx.reply("mob size is %d; it is 1 or more (no upper limit)." % size)
		return

	ctx.reply("%d coming." % world.horde.spawn_mob(size))

func _cmd_panic(ctx: GSCmdContext) -> void:
	var world := game as ZzGame

	if world == null or world.horde == null:
		ctx.reply("No horde.")
		return

	var seconds := ctx.arg(0).to_float() if ctx.argc() > 0 else 30.0

	if seconds < 5.0:
		ctx.reply("panic seconds is %s; it is 5 or more (no upper limit)." % seconds)
		return

	world.horde.panic(seconds)
	ctx.reply("Panic for %d s." % int(seconds))

func _cmd_reload(ctx: GSCmdContext) -> void:
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

## Hand-written cvars whose name is not `zz_<field>`: cvar -> config field.
const HAND_FIELDS := {
	"zz_infect_after": "infect_after_seconds", "zz_infect_count": "infect_count",
	"zz_box_common": "box_drop_common", "zz_box_drops": "boxes_enabled", "zz_box_special": "box_drop_special",
	"zz_breather": "breather_seconds", "zz_brute_every": "brute_every_waves", "zz_brute_max": "brute_interval_max",
	"zz_brute_min": "brute_interval_min", "zz_commons": "commons_base", "zz_defib_start": "start_defibs",
	"zz_director": "director_enabled", "zz_min_players": "minimum_players", "zz_mob_max": "mob_interval_max",
	"zz_mob_min": "mob_interval_min", "zz_nav_drop": "nav_drop_max", "zz_unstick_seconds": "unstick_seconds", "zz_prestart_time": "prestart_seconds",
	"zz_respawn_base": "respawn_base_seconds", "zz_respawn_max": "respawn_max_seconds",
	"zz_respawn_min": "respawn_min_seconds", "zz_respawn_per_wave": "respawn_per_wave_seconds",
	"zz_respawn_protect": "respawn_protect_seconds", "zz_sleepers": "sleepers_enabled",
	"zz_special_max": "special_interval_max", "zz_special_min": "special_interval_min",
	"zz_specials": "specials_base", "zz_start_grace": "start_grace_seconds", "zz_survival": "survival_style",
	"zz_survival_warmup": "survival_warmup_seconds", "zz_trader": "trader_enabled",
	"zz_wanderers": "wanderer_density", "zz_zombie_think_range": "think_range",
	"zz_dormant_from": "dormant_from", "zz_dormant_think_every": "dormant_think_every",
	"zz_path_reuse_thoughts": "path_reuse_thoughts", "zz_native_crowd": "native_crowd",
	"zz_native_senses": "native_senses", "zz_native_brains": "native_brains",
	"zz_native_pacing": "native_pacing",
	"zz_body_stride_near": "body_stride_near", "zz_body_stride_far": "body_stride_far",
	"zz_commons_far_divisor": "commons_far_divisor",
}

## The admin web page and F9 panel over the config; HTTP only with `workbench.enabled` in cfg/server.yml.
var workbench: GSGameWorkbench = null

## Every [ZzConfig] field as a `zz_<field>` cvar, a cfg/ yml key and a workbench set. A hand-written cvar keeps its own code; a workbench or yml edit is pushed through it.
func _bind_config(world: ZzGame) -> void:
	var _fl := world.flashlight_conf()
	if world.flashlight_binder != null:
		var _flash_cvars := world.flashlight_binder.bind_cvars(add_cvar, GSConVar.FLAG_ARCHIVE, func(n: String) -> bool: return console.has_name(n))
		world.flashlight_binder.bind_commands(add_command)
	var binder := world.config_binder
	if binder == null:
		return
	var hand := {}
	for entry: Dictionary in binder.schema():
		var key: String = entry["key"]
		if console.has_name("zz_" + key):
			hand[key] = "zz_" + key
	for cvar_name: String in HAND_FIELDS:
		if console.has_name(cvar_name):
			hand[HAND_FIELDS[cvar_name]] = cvar_name
	binder.replicate_groups = PackedStringArray(["Carry weight"])
	binder.replicate_keys = PackedStringArray(["trader_closed_message", "grace_hud", "mutant_fade", "mutant_min_alpha", "mutant_fade_per_stack", "common_fade", "goo_screen_per_stack", "goo_screen_max"])
	binder.bind_cvars(add_cvar, GSConVar.FLAG_ARCHIVE, func(n: String) -> bool:
		return console.has_name(n) or hand.has(n.trim_prefix("zz_")))
	binder.bind_commands(add_command)
	_apply_gore(world.config)
	binder.field_changed.connect(func(key: String, value: Variant, source: String) -> void:
		if key.begins_with("gore_"):
			_apply_gore(world.config)
		if source == "cvar" or not hand.has(key):
			return
		var text := world.config.survival_style_name() if key == "survival_style" else GSGameConfigBinder._to_text(value)
		console.set_cvar(hand[key], text))

## Puts the gore cvars on dot-npc's process-wide dial; live, so a workbench edit takes effect on the next shot.
func _apply_gore(config: GSConfig) -> void:
	GSNpcGore.level = int(config.get(&"gore_level"))
	GSNpcGore.max_gibs = int(config.get(&"gore_max_gibs"))
	GSNpcGore.max_wounds = int(config.get(&"gore_max_wounds"))
	ZzZombieView.attack_anim = int(config.get(&"attack_anim"))

func _noblock_side(id: Variant) -> Variant:
	var game_world := game as ZzGame
	var side := int(game_world.sides.get(id, 0)) if game_world != null else 0
	return str(side) if side > 0 else ""

func _noblock_runtime() -> Object:
	return (game as ZzGame).ensure_runtime()

## `!block` and `!noblock` find a player by `u<userid>`, the key every survivor is seated under.
func _build_noblock() -> GSResult:
	var built := super()
	if built.ok and noblock != null and noblock.commands != null:
		noblock.commands.set(&"key_fn", func(ctx: Object) -> Variant:
			var session: Variant = ctx.get("session")
			return ZzNetBridge.player_key(int(session.get("userid"))) if session is Object else null)
	return built

func _start_workbench(world: ZzGame) -> void:
	var rt := world.ensure_runtime()
	var admin_permit := Callable()
	if server != null and server.admins != null:
		admin_permit = server.admins.uid_has_permission
	rt.permit = func(actor: Variant, flag: String) -> bool:
		if typeof(actor) == TYPE_STRING_NAME and actor == ZzGame.LOCAL_ACTOR:
			return true
		return admin_permit.is_valid() and actor is String and bool(admin_permit.call(actor, flag))
	rt.actor_name = func(actor: Variant) -> String: return str(actor)
	workbench = GSGameWorkbench.new()
	workbench.name = "Workbench"
	workbench.dedicated = DisplayServer.get_name() == "headless"
	workbench.listen_host_fn = func() -> bool: return DisplayServer.get_name() != "headless"
	workbench.permit_fn = func(actor: Variant, flag: String) -> bool:
		return admin_permit.is_valid() and actor is String and bool(admin_permit.call(actor, flag))
	if world.config_binder != null:
		for set: GSProfileSet in world.config_binder.profile_sets():
			workbench.add_set(set, "Game settings: %s" % set.rel_path.trim_prefix("config_"))
	if world.flashlight_binder != null:
		for set: GSProfileSet in world.flashlight_binder.profile_sets():
			workbench.add_set(set, "Flashlight")
	workbench.add_set(world.bot_persona_set(), "Bot personas (add, edit, delete)")
	workbench.add_set(GSWaveSet.make_set("game-zombie-zone"), "Wave sets (sizes, pools, bosses, difficulty)")
	workbench.add_set(world.box_profile_set(), "Boxes (odds, effects, colours, sounds)")
	var ambient_set := GSGameWorkbench.cvar_set(console, world.ambient_rules.cvar_types(), AMBIENT_KIND)
	if ambient_set != null:
		workbench.add_set(ambient_set, "Ambience (zz_ambient*)")
	add_child(workbench)
	var started := workbench.start(rt)
	if not started.ok:
		log_warn("the workbench", {"why": started.error.message})
		return
	# Off until the owner sets sv_workbench_remote 1; then flagged admins edit from a client.
	if net != null:
		var _served := workbench.serve_remote(net)
	if world.config_binder != null:
		world.config_binder.attach(rt)
	if world.flashlight_binder != null:
		world.flashlight_binder.attach(rt)
	rt.profile_changed.connect(func(kind: String, _id: String, _rev: int) -> void:
		if kind == GSBotPersona.KIND:
			world.reload_personas()
		elif kind == GSBoxProfiles.KIND:
			world.reload_boxes())
	if ambient_set != null:
		var _applied := GSGameWorkbench.bind_cvar_set(ambient_set, rt, console)
