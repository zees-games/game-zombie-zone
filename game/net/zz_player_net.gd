extends DotNetBehaviour

const ZzNetCommand := preload("zz_net_command.gd")
const ZzPlayer := preload("../zz_player.gd")

## What a networked survivor replicates: the movement state, their health, their weapons, and
## the state of their body — up, down or held, borrowed health, what they are holding E for.
##
## [b]The movement half is dot-player-controller's own table and is not written here.[/b]
## [DotFpsNetSync.state_specs] is what the controller says its state is, in the
## quantisation it says it wants; a game that listed the fields itself would be a second
## copy to drift — and the type names in that table are STRINGS precisely so the addon can
## describe a dot-net layout without naming dot-net.
##
## [b]The game fields are not derivable from the movement.[/b] Health decides whether a body
## is drawn at all; sitting a round out and being given away by the beacon are the server's
## decisions about a player, and a client that worked them out for itself would be running a
## second copy of the rules.
##
## [b]Down, held, borrowed health and the use bar ARE here[/b], although each changes on a
## decision, because each is a fact the next snapshot must be able to correct: a client that
## missed the event saying a friend was picked up would draw them on the floor for the rest of
## the map. The events (DOWN, REVIVE, PIN) carry the moment — who did it, the sound, the line
## in the feed — and these carry the truth.
##
## [b]Which side somebody is on is deliberately NOT here.[/b] It changes once a round at
## most, and a per-tick field for it would send the same three bits sixty-four times a
## second for ever to carry a fact that arrives reliably in a JOIN and a TEAM. The rule this
## game follows: a per-tick property for what changes per tick, an event for what changes on
## a decision.

## Somebody this client is watching used their weapon, [param times] times since the last
## snapshot. What a game draws a muzzle flash from.
signal weapon_used(times: int, kind: int)

var player: ZzPlayer = null
var bridge: Node = null

var net_position: Vector3 = Vector3.ZERO
var net_velocity: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_crouch: float = 0.0
var net_flags: int = 0
var net_modifiers: int = 0

## Hit points, and the one field with a hard cap on the wire.
##
## [b]Sent against 0..1000 rather than against the player's own maximum.[/b] A server that
## raised `player_health` mid-round would otherwise change what every previously sent number
## MEANT, which is the quantisation version of the map-size bug: the value does not get less
## precise, it becomes a different value.
var net_health: float = 100.0

## What full health is: a survivor's, or the bleed-out pool of one who is down.
var net_max_health: float = 100.0

## `ZzPlayer.Life`, downs this map, and the borrowed part of the health.
var net_life: int = 0
var net_incaps: int = 0
var net_temp: float = 0.0

## What is holding them: an index into [constant PIN_KINDS], 0 for nothing.
var net_pin: int = 0

## 0..1 through what they are holding E for, and 0..1 of somebody helping them up or healing
## them. What `using` is, as an index into [constant USES].
var net_use: float = 0.0
var net_helped: float = 0.0
var net_using: int = 0

## Medkit in bit 0, pills in bit 1.
var net_kits: int = 0

## Bile in bit 0, burning in bit 1, a box's blinding in bit 2.
var net_status: int = 0

const PIN_KINDS: Array[StringName] = [&"", &"pounce", &"choke", &"carry", &"ride"]
const USES: Array[StringName] = [&"", &"revive", &"heal", &"loot", &"objective"]

## Points this match and the server's ping for the player, for everybody's Tab board.
var net_points: int = 0
var net_ping: int = 0

## Sitting this map out.
var net_watching: bool = false

# --- The weapons ------------------------------------------------------------
#
# [b]Seven fields, and the pack's own `all_specs()` names all of them.[/b] GDScript has no
# dynamic properties, so a spec table that says what to send needs a variable per entry
# declared by hand — and the one call a game should make is `ZeeWeaponNet.all_specs()`,
# because concatenating dot-weapon's three with the pack's four by hand is the same work
# and one more place to forget the second half. Forgetting it presents as weapons that are
# silent for everybody except the person holding them, which is what game-playground
# shipped.
#
# The magazine and the reserve are `owner_only`: exact ammunition is information an opponent
# should not have, and dot-combat makes the same decision about the same two numbers.

var net_slot: int = 0
var net_magazine: int = 0
var net_reserve: int = 0
var net_fire_seq: int = 0
var net_fire_kind: int = 0
var net_reloading: bool = false
var net_switching: bool = false

# --- An administrator's marks, from the live tools ---------------------------

## `ZzPlayer.blinded`. Owner only: see [method _register_net_vars].
var net_blind: bool = false

## `ZzPlayer.beacon`, an admin's mark. Everybody's.
var net_beacon: bool = false

## `ZzPlayer.warps`, four bits of it: how many times the server has put this player
## somewhere rather than moved them there. See [method _forget_the_path].
var net_warp: int = 0

## The last [member net_warp] this mirror acted on.
var _seen_warp: int = -1

## What this watcher last saw of that counter, so a wrap is read as uses rather than as a
## negative. One integer per watched player, which is what lets `ZeeWeaponNet` keep none.
var _seen_fire_seq: int = 0

## Retained, not cleared: a player whose packet was lost keeps moving in a straight line
## rather than stopping dead. The controller says the same of its own command.
var last_move: DotFpsCommand = DotFpsCommand.new()

## And the slot they last asked for, which is simulation state for a survivor: the arsenal is
## edge-triggered against it.
var last_slot: int = 0

var last_state_tick: int = -1


func _register_net_vars() -> void:
	for spec in DotFpsNetSync.state_specs():
		var declaration := replicate(spec["property"], DotNetVar.Type[spec["type"]])

		if int(spec["bits"]) > 0:
			declaration.bits(int(spec["bits"]))

		if bool(spec["interpolated"]):
			declaration.interpolated()

		if spec["property"] == &"net_crouch":
			declaration.range_of(0.0, 1.0)

	replicate(&"net_health", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, 2000.0).bits(14)
	replicate(&"net_max_health", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, 2000.0).bits(12)
	replicate(&"net_life", DotNetVar.Type.UINT).bits(2)
	replicate(&"net_incaps", DotNetVar.Type.UINT).bits(4)
	replicate(&"net_temp", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, 400.0).bits(10)
	replicate(&"net_pin", DotNetVar.Type.UINT).bits(3)
	replicate(&"net_use", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, 1.0).bits(7)
	replicate(&"net_helped", DotNetVar.Type.FLOAT_RANGE).range_of(0.0, 1.0).bits(7)
	replicate(&"net_using", DotNetVar.Type.UINT).bits(3)
	replicate(&"net_kits", DotNetVar.Type.UINT).bits(2)
	replicate(&"net_status", DotNetVar.Type.UINT).bits(3)
	replicate(&"net_points", DotNetVar.Type.UINT).bits(16)
	replicate(&"net_ping", DotNetVar.Type.UINT).bits(10)
	replicate(&"net_watching", DotNetVar.Type.BOOL)

	for spec in ZeeWeaponNet.all_specs():
		var declaration := replicate(spec["property"], DotNetVar.Type[spec["type"]])

		if int(spec["bits"]) > 0:
			declaration.bits(int(spec["bits"]))

		if bool(spec["interpolated"]):
			declaration.interpolated()

		if bool(spec["owner_only"]):
			var _owner := declaration.to_owner_only()

	# [b]Per-player state rather than an event, and that is what makes both of these survive
	# what an event does not.[/b] A client that joins after the admin typed `beacon`, a
	# snapshot lost on the way, a field re-laid at the top of a round: each is a baseline the
	# next snapshot corrects, where an event sent once is simply missed. Two bits, and nothing
	# at all on a tick where neither changed.
	#
	# The blind goes to its owner alone. Nobody else's screen changes, and an opponent who
	# received it would know the moment somebody could not see — the same reason the magazine
	# and the reserve above are the owner's.
	#
	# [b]No relevance change for a beacon, where game-arena makes one.[/b] Every player here
	# is already always relevant (`ZzNetBridge`: a map is a few rooms), so a beacon reaches
	# every client however far away they are without asking — and a beacon turned OFF that
	# set `always_relevant` back to false would take the player out of everybody's snapshot.
	var _blind := replicate(&"net_blind", DotNetVar.Type.BOOL).to_owner_only()
	replicate(&"net_beacon", DotNetVar.Type.BOOL)
	replicate(&"net_warp", DotNetVar.Type.UINT).bits(4)


func _net_apply_input(input: DotNetInput, _tick: int) -> void:
	var command := input as ZzNetCommand

	if command != null:
		last_move = command.move
		last_slot = command.slot

		if player != null:
			player.wanted_slot = command.slot
			player.actions = command.actions
			player.shove_held = command.move.is_pressed(ZzNetCommand.BUTTON_SHOVE)


## On the authority the whole game ticks as one — every player moves, then the shots, the
## taunts and the round are decided — so the first behaviour through drives the whole world and
## the rest find it done. On a predicting client there is one predicted player, and simulating
## it is the whole of what a client may compute.
func _net_simulate(tick: int, delta: float) -> void:
	if player == null:
		return

	if identity != null and identity.is_authoritative:
		if bridge != null:
			bridge.ensure_game_ticked(tick)
	else:
		# The prediction: the controller's own tick, with the same modifiers the server's —
		# down, held, limping, slowed — which travel in the movement state.
		player.controller.apply_command(last_move.duplicate_command())
		player.controller.simulate_tick(tick, delta)

	pull()


## Authority only: what the simulation left this player as.
func pull() -> void:
	if player == null:
		return

	DotFpsNetSync.pull(player.controller.state, self)

	if player.health != null:
		net_health = player.health.health
		net_max_health = player.health.max_health

	net_life = player.life
	net_incaps = clampi(player.incaps, 0, 15)
	net_temp = player.temp_health
	net_pin = maxi(PIN_KINDS.find(player.pin_kind), 0)
	net_use = player.use_fraction
	net_helped = player.helped_fraction
	net_using = maxi(USES.find(player.using), 0)
	net_kits = (1 if player.medkits > 0 else 0) | (2 if player.pills > 0 else 0)
	net_status = (1 if player.biled else 0) | (2 if player.burning else 0) | (4 if player.box_blind else 0)
	net_points = clampi(player.points, 0, 65535)
	net_ping = clampi(player.ping_ms, 0, 1023)
	net_watching = player.watching
	net_blind = player.blinded
	net_beacon = player.beacon
	net_warp = player.warps & 0xF

	# [b]After the arsenal has simulated, which on this end it has: the whole world ticks
	# before anything is pulled.[/b] A prop has no rig and leaves these at zero, and zero is a
	# carrier holding nothing, which is true.
	if player.weapons != null:
		ZeeWeaponNet.pull(player.weapons, self)


## The server's answer, adopted wholesale. On the owner it is the rewind half of
## reconciliation and the predictor replays every unacknowledged command on top.
func _net_state_applied(tick: int) -> void:
	if player == null:
		return

	last_state_tick = tick
	_forget_the_path()
	DotFpsNetSync.push(self, player.controller.state)
	_adopt()

	# NOT the node, on a predicted entity: `receive_snapshot` calls this BEFORE the
	# predictor reconciles, and reconcile's first act is to read the node as "what the
	# client is showing". Moving it here makes the measured error the whole replay distance,
	# and the correction rate then reads as if every snapshot snapped. Two games in this
	# family shipped that line.
	#
	if identity == null or not identity.is_predicted():
		player.global_position = player.controller.state.position


## A teleport is not a movement, so the interpolator must not draw one.
##
## [b]A round start moves everybody across the map in one tick, and a watcher saw them
## fly there.[/b] mg-smash-copter's finding. The interpolator blends between the two snapshots
## either side of the render time, and when those are "where they were found" and "at the
## start" the blend is a body sweeping across the map for a snapshot interval.
##
## So the server counts the times it PUT this player somewhere (`ZzPlayer.place_at`), the
## count replicates, and a mirror that sees it change drops the interpolator's track for this
## entity before the new snapshot is added to it. A track with one sample answers with that
## sample, so the body appears in its corner, one render delay early, rather than crossing
## the sky to get there. Here, before the push, because this hook runs inside the snapshot
## read and the manager adds the snapshot's values to the track just after it.
##
## Not on the predicted entity: nothing interpolates that, and its own camera is moved by
## the prediction's rewind.
func _forget_the_path() -> void:
	if identity == null or identity.is_authoritative or identity.is_predicted():
		_seen_warp = net_warp
		return

	if _seen_warp >= 0 and net_warp != _seen_warp and bridge != null:
		var manager: Variant = bridge.get(&"net")
		if manager is DotNetManager and (manager as DotNetManager).interpolator != null:
			(manager as DotNetManager).interpolator.forget(identity.net_id)

	_seen_warp = net_warp


## Every frame on a remote player. Without this the interpolator's work sits in a property
## nothing reads and a remote player moves in snapshot-sized steps.
func _net_interpolated(_tick: int) -> void:
	if player == null:
		return

	DotFpsNetSync.push(self, player.controller.state)
	player.global_position = player.controller.state.position


## The game half of a snapshot, on a mirror: what the server decided about this player.
func _adopt() -> void:
	if player == null or identity == null or identity.is_authoritative:
		return

	if player.health != null:
		player.health.max_health = maxf(net_max_health, 1.0)
		player.health.health = net_health
		player.health.alive = net_health > 0.0

	var was_down := player.is_down()
	player.life = net_life
	player.incaps = net_incaps
	player.temp_health = net_temp
	player.pin_kind = PIN_KINDS[clampi(net_pin, 0, PIN_KINDS.size() - 1)]
	player.pinned_by = 1 if net_pin > 0 else 0
	player.use_fraction = net_use
	player.helped_fraction = net_helped
	player.using = USES[clampi(net_using, 0, USES.size() - 1)]
	player.medkits = net_kits & 1
	player.pills = (net_kits >> 1) & 1
	player.biled = (net_status & 1) != 0
	player.burning = (net_status & 2) != 0
	player.box_blind = (net_status & 4) != 0
	player.points = net_points
	player.ping_ms = net_ping
	player.watching = net_watching
	player.blinded = net_blind
	player.beacon = net_beacon

	if was_down != player.is_down():
		player.fit_hitboxes()

	_apply_weapons()

	# The owner's own counts (owner_only), put onto the gun it draws once that has gone quiet.
	if player.view_rig != null:
		var _corrected := player.correct_view_rig(net_magazine, net_reserve, net_slot, net_reloading or net_switching)


## What a watcher does with somebody else's weapon state.
##
## [b]A counter, never an event per shot.[/b] An RPC per shot needs a reliable channel for
## something worthless if it arrives late, costs a packet per shot per watcher, and
## desynchronises from the state it belongs with — so a watcher can see the muzzle flash of
## a weapon the same snapshot says has been holstered. A four-bit counter inside the
## snapshot cannot do any of those: a watcher who missed a snapshot sees it jump by two and
## plays one flash instead of two, which is the correct amount of wrong.
##
## [b]No world model is handed to `ZeeWeaponNet.apply`[/b], because the hand it would hang
## from belongs to the figure, which is built lazily, rebuilt on a side change and absent on
## a server. The answer is written onto the player instead — the slot, the switch and the
## uses since the figure last looked — and `ZzPlayer.present_body` hands it to the figure on
## the frame it is drawn. The same counter also says `weapon_used`, which is the report.
func _apply_weapons() -> void:
	var answer := ZeeWeaponNet.apply(self, null, _seen_fire_seq)
	_seen_fire_seq = int(answer["seq"])

	player.mirrored = true
	player.mirror_slot = net_slot
	player.mirror_switching = net_switching
	player.mirror_fired += int(answer["fired"])
	if int(answer["fired"]) > 0:
		player.mirror_fire_kind = int(answer["kind"])

	if int(answer["fired"]) > 0:
		weapon_used.emit(int(answer["fired"]), int(answer["kind"]))
