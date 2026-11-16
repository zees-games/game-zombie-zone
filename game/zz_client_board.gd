extends "zz_client_state.gd"

## The Tab board and the end of a map (killcam, winner reveal, board) of [zz_client.gd],
## split off so each file stays a size the efficiency gate allows.


static func drawn_position(body: ZzPlayer, remote: bool) -> Vector3:
	if remote or body.controller == null:
		return body.global_position

	return body.controller.render_state().position



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
	snap["header"]["Zombies"] = " | ".join([ZzZombieView.CREDITS, ZzMutantView.MUTANT_CREDITS, ZzOilMonsterModel.OIL_MONSTER_CREDITS])
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



func _build_killcam() -> void:
	killcam = ZzKillcam.new()
	killcam.name = "MapKillcam"
	killcam.players_fn = func() -> Array: return game.players.values() if game != null else []
	killcam.player_for_fn = func(key: StringName) -> Variant: return game.players.get(key) if game != null else null
	killcam.zombies_fn = func() -> Array:
		return world_view.snapshot(player.global_position, 40.0) if world_view != null and player != null else []
	killcam.replaying_fn = func(on: bool) -> void:
		if world_view != null:
			world_view.set_replaying(on)
	killcam.feet_fn = func(p: ZzPlayer) -> Vector3: return drawn_position(p, net != null and net.is_running() and p != player)
	killcam.colour_fn = func(_p: ZzPlayer) -> Color: return game.side_colour(ZzGame.SURVIVORS)
	_killcam_icons = ZzShopIcons.new()
	add_child(_killcam_icons)
	killcam.weapon_icon_fn = func(id: String) -> Texture2D: return _killcam_icons.icon_for(StringName(id))
	killcam.seconds_fn = func() -> float: return _killcam_sec if _killcam_sec >= 0.0 else game.config.killcam_seconds
	killcam.camera_mode_fn = func() -> int: return _killcam_camera
	killcam.world_mask = game.world_mask()
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
		_killcam_sec = maxf(value.to_float(), 0.0)
	elif cvar_name == "mp_killview_camera" and value.strip_edges().is_valid_float():
		_killcam_camera = DotKillViewRules.Camera.BEHIND if value.to_float() >= 0.5 else DotKillViewRules.Camera.EYE


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
