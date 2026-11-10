extends RefCounted
## A turned survivor's hold on a zombie body: the server feeds their latest command to the body's
## [DotNpcDrive] each tick, and the zombie's own brain turns it into a walk and a swing
## ([method ZzZombieBrain._npc_driven]). Server-authoritative: a client only sends its usual command
## and watches the body (ZzEvents POSSESS names it). The hold ends when the body dies or is gone;
## the player is then dead, as before, and spectates.

const ZzNetCommand := preload("net/zz_net_command.gd")
const ZzPlayer := preload("zz_player.gd")

const CHANNEL := "zz.possession"

## Held bodies, player id to npc instance id.
var holds: Dictionary = {}

var game = null

## Called with (player_id, npc instance id or 0) when a hold starts or ends; the net layer tells the player.
signal changed(player_id: StringName, npc_id: int)


func _init(p_game: Object) -> void:
	game = p_game


func is_holding(player_id: StringName) -> bool:
	return holds.has(player_id)


func body_of(player_id: StringName) -> int:
	return int(holds.get(player_id, 0))


## The player takes [param npc]. False if its brain cannot be driven.
func possess(player: Object, npc: DotNpcInstance) -> bool:
	if npc == null or npc.brain == null or not npc.brain.has_method(&"_npc_driven"):
		return false

	var drive := DotNpcDrive.new()
	drive.grab(player.player_id)
	npc.brain.drive = drive
	# Never reclaimed for having nobody near: a person is behind it.
	npc.engaged_at = INF
	holds[player.player_id] = npc.instance_id
	changed.emit(player.player_id, npc.instance_id)
	return true


func release(player_id: StringName) -> void:
	var id := body_of(player_id)

	if id == 0:
		return

	holds.erase(player_id)
	var npc: DotNpcInstance = game.horde.spawner.get_npc(id) if game.horde != null else null

	if npc != null and npc.brain != null and npc.brain.drive != null:
		npc.brain.drive.release()

	changed.emit(player_id, 0)


func tick(_delta: float) -> void:
	for player_id: StringName in holds.keys():
		var npc: DotNpcInstance = game.horde.spawner.get_npc(body_of(player_id)) if game.horde != null else null
		var player: Object = game.players.get(player_id)

		if npc == null or not npc.is_alive() or player == null or npc.brain == null:
			var last: Vector3 = player.global_position if player != null else Vector3.ZERO
			release(player_id)

			# The body is gone and the player with it: the death camera starts over where the
			# body fell, instead of carrying on from where the player first died.
			if player != null and player.life == ZzPlayer.Life.DEAD and game.spectate != null and game.authoritative:
				game.spectate.on_died(player_id, &"", false, last, game.map.kill_height() + 8.0, game.current_tick())
			continue

		# The dead player's own position rides the body, so what the server sends them
		# (interest is by distance from the player) is what is around the body.
		if player.controller != null:
			player.controller.state.position = npc.position()
			player.global_position = npc.position()

		var cmd: DotFpsCommand = player.input_move
		if cmd == null:
			continue

		var buttons := 0
		if cmd.is_pressed(ZzNetCommand.BUTTON_FIRE):
			buttons |= 1
		# The shove key is the body's trick: a leap, a charge, a spit.
		if cmd.is_pressed(ZzNetCommand.BUTTON_SHOVE):
			buttons |= 2
		npc.brain.drive.feed(cmd.move, deg_to_rad(cmd.yaw), buttons)
