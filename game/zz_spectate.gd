extends DotSpectatorHost

const ZzPlayer := preload("zz_player.gd")

## Where somebody who is out looks, and what the server lets them see.
##
## [b]Most of a server is out before a round ends.[/b] A prop that is found stays out until the
## next round, so by the end of one most of the props are watching the last few hide — the
## people with the most reason to see whether they get away with it. A joiner mid-round
## watches too.
##
## [b]The camera part is four lines; who decides is the part that matters.[/b] dot-spectate
## computes a transform and touches no camera, and the policy — may this person watch, whom,
## through which camera — is the server's, so a client that decided for itself what it may
## look at would be a client that may look at anything. On a server this runs an
## authoritative [DotSpectatorManager]; on a connected client it runs a MIRROR that is told
## each view change in a `SPECTATE` event and computes the camera itself from the players it
## already draws. That split is what keeps the wire to one small event per decision rather
## than a camera transform per frame.
##
## [b]No delay, and it would protect nothing here.[/b] dot-spectate's delay exists because a
## spectator watching live is a live intelligence feed — but every player in this game is
## always relevant (a map is a few rooms), so every client already receives every player's
## live position in its snapshots. A delayed spectator camera would hide nothing that the
## same client's own world is not already drawing. `delay_ticks` stays 0 and a mirror never
## needs the history a delay samples, which is also why the mirror's `advance` records none.
##
## [b]No `class_name`, like everything in this game.[/b] Reached by preload from [ZzGame].
## It does not preload [ZzGame] back: the world hands it the two dictionaries it reads, which is
## a smaller contract than the world and no cycle.

const CHANNEL := "zz.spectate"

## Seconds the death camera holds before handing over.
##
## [b]A second and a half, and it is not a killcam.[/b] What the moment is for is seeing who
## found you, before the camera moves to somebody still in it.
const DEATH_CAM_SECONDS := 1.5

## Seconds the freeze camera holds on whoever put you out.
const FREEZE_CAM_SECONDS := 1.5

## How far above the floor a faller's death camera hangs, looking straight down the drop.
##
## [b]Not where they died, which is the floor.[/b] A fall is recorded at the kill height, so the
## camera goes back up to the field over the point they left it by and looks down the drop.
const DROP_CAM_RISE := 6.0

## The overview camera, and a second slot this game fills with the same view. See
## [method set_overview_pair].
const OVERVIEW_FIELD := 0
const OVERVIEW_SHOWDOWN := 1

## player id -> ZzPlayer. The world's own dictionary, shared rather than copied, so a join
## is visible here the moment the world has it.
var players: Dictionary = {}

## player id -> team id. Also the world's own.
var sides: Dictionary = {}

## The operator's policy, [member ZzConfig.spectate_camera]. Read by [method _tune_rules].
var force_camera: int = 0


func _init() -> void:
	death_cam_seconds = DEATH_CAM_SECONDS
	freeze_cam_seconds = FREEZE_CAM_SECONDS
	chase_distance = 4.6
	chase_height = 1.2
	# No delay, so the shortest ring the host allows: a mirror never samples history.
	history_seconds = 0.0
	prefer_own_side = true
	name_fn = _display_name


func _channel() -> String:
	return CHANNEL


## The policy beyond the exports.
func _tune_rules(r: DotSpectatorRules) -> DotSpectatorRules:
	r.force_camera = clampi(force_camera, 0, 2)
	# Off whatever the policy. A roaming camera over the map sees the whole map from anywhere,
	# which with "own side" on is the one thing that setting forbids.
	r.allow_roaming = false
	# Dead players stay dead until the next round, so a list that included them would be
	# a list of bodies at the kill height.
	r.cycle_includes_dead = false
	r.delay_ticks = 0
	return r


## Two overview slots, both the same view here. The phase picks one: set [member fixed_index_fn].
func set_overview_pair(field: Transform3D, showdown: Transform3D) -> void:
	var cameras: Array[Transform3D] = [field, showdown]
	set_overviews(cameras)


## Somebody is out. Starts the death camera; the server's tick hands it over.
##
## [param at] is where they died. A fall is recorded at the kill height, so the death camera
## is moved back up over the point they went down -- see [constant DROP_CAM_RISE].
func on_died(
	player_id: StringName, by: StringName, fell: bool, at: Vector3, deck_height: float, tick: int
) -> void:
	if manager == null or not authoritative:
		return

	var where := at

	if fell:
		where = Vector3(at.x, deck_height + DROP_CAM_RISE - 2.0, at.z)

	death(String(player_id), where, String(by), tick)


## Somebody is back in the world -- a new round, or a join. They stop watching.
func on_spawned(player_id: StringName) -> void:
	spawned(String(player_id))


## Somebody left. Called AFTER the world has dropped them.
func on_left(player_id: StringName) -> void:
	left(String(player_id))


func line_for(key: String) -> String:
	if not is_spectating(key):
		return ""

	var view := manager.view(key)

	match view.mode:
		DotSpectatorView.Mode.DEATH_CAM:
			return "you are out"
		DotSpectatorView.Mode.FREEZE_CAM:
			return "shot by %s" % _name_of(view.target)
		DotSpectatorView.Mode.FIXED:
			return "nobody left to watch"
		DotSpectatorView.Mode.CHASE:
			return "watching %s  (behind)   click: next   F5: their eyes" % _name_of(view.target)
		_:
			return "watching %s   click: next   F5: behind them" % _name_of(view.target)


func _display_name(key: String) -> String:
	var body: ZzPlayer = players.get(StringName(key))
	return body.display_name if body != null else key


func _participants() -> PackedStringArray:
	var out := PackedStringArray()

	for id: StringName in players:
		out.append(String(id))

	return out


func _team_of(key: String) -> int:
	return int(sides.get(StringName(key), 0))


func _is_alive(key: String) -> bool:
	var body: ZzPlayer = players.get(StringName(key))
	# Somebody in the gallery is up and is not in the fight; a camera on them is a camera on
	# a wall of other spectators.
	return body != null and is_instance_valid(body) and body.is_alive() and not body.watching


## Where somebody's eyes are, from where this process DRAWS them.
##
## [b]The drawn position and not the node, on a world that simulates.[/b] A node here moves
## once a tick, so a camera hung on it advances in steps. A mirror's remote players are
## written once a frame by the interpolator, so there the node is already right, and a
## rider's controller is not simulated at all.
func _pose_of(key: String) -> Transform3D:
	var body: ZzPlayer = players.get(StringName(key))

	if body == null or not is_instance_valid(body) or body.controller == null:
		return Transform3D.IDENTITY

	var at := body.global_position

	if authoritative:
		at = body.controller.render_state().position

	var state := body.controller.state
	var basis := Basis.from_euler(Vector3(deg_to_rad(state.pitch), deg_to_rad(state.yaw), 0.0))
	# A prop's eyes are near the top of what it is, not a person's height above the floor.
	var eye := body.eye_position() - state.position
	return Transform3D(basis, at + eye)
