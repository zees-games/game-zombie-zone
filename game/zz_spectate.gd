extends DotSpectatorHost

const ZzPlayer := preload("zz_player.gd")

## Where somebody who is out looks: [DotSpectatorHost] with this game's numbers, no delay (every client already draws every player live) and the fall camera.

const CHANNEL := "zz.spectate"

## Seconds the death camera holds before handing over; seeing who found you, not a killcam.
const DEATH_CAM_SECONDS := 1.5

## Seconds the freeze camera holds on whoever put you out.
const FREEZE_CAM_SECONDS := 1.5

## How far above the deck a faller's death camera hangs: a fall is recorded at the kill height, where nothing is worth seeing.
const DROP_CAM_RISE := 6.0

## player id -> ZzPlayer. The world's own dictionary, shared so a join is visible here at once.
var players: Dictionary = {}

## player id -> team id. Also the world's own.
var sides: Dictionary = {}

var _tick_fn: Callable = Callable()


func _init() -> void:
	death_cam_seconds = DEATH_CAM_SECONDS
	freeze_cam_seconds = FREEZE_CAM_SECONDS
	chase_distance = 4.6
	chase_height = 1.2
	history_seconds = 0.0
	prefer_own_side = true


## Builds the manager. [param force_camera] is [member ZzConfig.spectate_camera].
func setup_world(
	p_players: Dictionary, p_sides: Dictionary, is_authority: bool, rate: int, force_camera: int,
	tick_fn: Callable
) -> DotResult:
	players = p_players
	sides = p_sides
	authoritative = is_authority
	tick_rate = rate
	_tick_fn = tick_fn
	name_fn = _display_name
	rules = DotSpectatorRules.new()
	rules.force_camera = clampi(force_camera, 0, 2)
	return setup()


func _channel() -> String:
	return CHANNEL


func _tune_rules(r: DotSpectatorRules) -> DotSpectatorRules:
	# A roaming camera sees the whole map, which "own side" forbids and "anybody" does not need.
	r.allow_roaming = false
	# Dead players stay dead until the next round: the list would be bodies at the kill height.
	r.cycle_includes_dead = false
	r.delay_ticks = 0
	return r


func _current_tick() -> int:
	return int(_tick_fn.call()) if _tick_fn.is_valid() else 0


func _participants() -> PackedStringArray:
	var out := PackedStringArray()

	for id: StringName in players:
		out.append(String(id))

	return out


func _team_of(key: String) -> int:
	return int(sides.get(StringName(key), 0))


func _is_alive(key: String) -> bool:
	var body: ZzPlayer = players.get(StringName(key))
	# Somebody in the gallery is up but not in the fight.
	return body != null and is_instance_valid(body) and body.is_alive() and not body.watching


func _display_name(key: String) -> String:
	var body: ZzPlayer = players.get(StringName(key))
	return body.display_name if body != null else key


## Where somebody's eyes are, from where this process DRAWS them: the interpolated state on a world that simulates, the node on a mirror.
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
	var eye := body.eye_position() - body.controller.state.position
	return Transform3D(basis, at + eye)


## Somebody is out. [param at] is where they died; a fall is recorded at the kill height, so the camera goes back up over the point they went down.
func on_died(
	player_id: StringName, by: StringName, fell: bool, at: Vector3, deck_height: float, tick: int
) -> void:
	if manager == null or not authoritative:
		return

	var where := at

	if fell:
		where = Vector3(at.x, deck_height + DROP_CAM_RISE - 2.0, at.z)

	death(String(player_id), where, String(by), tick)
	DotLog.debug(CHANNEL, "somebody who is out is watching", {
		"player": String(player_id), "by": String(by), "fell": fell,
	})
