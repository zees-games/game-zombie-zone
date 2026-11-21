extends GSNetBehaviour

const ZzNetCommand := preload("zz_net_command.gd")
const ZzPlayer := preload("../zz_player.gd")

## What a networked survivor replicates: the movement state, health, weapons, and the state of the body (up, down or held, borrowed health, the use bar).
## [b]The movement half is gs-player-controller's own table[/b] ([GSFpsNetSync.state_specs]); listing the fields here would be a second copy to drift. [b]The game fields are not derivable from it[/b]: health, sitting a round out and the beacon are the server's decisions.
## [b]Down, held, borrowed health and the use bar ARE here[/b] because each is a fact the next snapshot must be able to correct (a missed pick-up event would leave a friend on the floor); events carry the moment, these carry the truth. [b]Which side somebody is on is NOT here[/b]: a per-tick property is for what changes per tick, an event for what changes on a decision.

## Somebody this client is watching used their weapon, [param times] times since the last
## snapshot. What a game draws a muzzle flash from.
signal weapon_used(times: int, kind: int)

var player: ZzPlayer = null
var bridge: Node = null

## The jump timers (coyote, jump buffer, cooldown), owner only, for the owner's rewind. Opt-in on gs-player-controller API 10; see its docs/networking.md.
var net_timers: int = 0

var net_position: Vector3 = Vector3.ZERO
var net_velocity: Vector3 = Vector3.ZERO
var net_yaw: float = 0.0
var net_pitch: float = 0.0
var net_crouch: float = 0.0
var net_flags: int = 0
var net_modifiers: int = 0

## Owner-only packed stamina (GSFpsNetSync.pack_stamina) so a predicting client's rewind restores it.
var net_stamina: int = 0

## Hit points, and the one field with a hard cap on the wire.
## [b]Sent against 0..1000, not the player's own maximum[/b]: a server that raised `player_health` mid-round would change what every number already sent MEANT.
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

## Medkits held. A varint of its own: zz_medkit_max has no upper limit.
var net_kits: int = 0

## Pills held. A varint of its own: zz_pills_max has no upper limit.
var net_pills: int = 0

## The defibrillator's charges. A varint of its own: zz_defib_charges has no upper limit.
var net_defibs: int = 0

## Boxes carried (bits 0-2) and the type of the top one, an index into the box file plus one,
## 0 for unknown (bits 3-8), and whether it is in the hands (bit 9). The server writes 0 for
## the type when `box_labels` is off.
var net_carry: int = 0

## Bile in bit 0, burning in bit 1, a box's blinding in bit 2, goo stacks on the screen (0 to 3) in bits 3-4, a grenade flash in bit 5.
var net_status: int = 0

const PIN_KINDS: Array[StringName] = [&"", &"pounce", &"choke", &"carry", &"ride", &"grab", &"eat"]
const USES: Array[StringName] = [&"", &"revive", &"heal", &"loot", &"objective", &"repair", &"deploy", &"defib", &"pills"]

## Points this match for the player, for everybody's Tab board. A varint: points have no upper limit.
var net_points: int = 0
var net_ping: int = 0

## Sitting this map out.
var net_watching: bool = false

# The weapons: [b]seven fields, and the pack's own `all_specs()` names all of them.[/b] GDScript has no dynamic properties, so each entry needs a variable declared by hand;
# call `ZeeWeaponNet.all_specs()` and never concatenate gs-weapon's three with the pack's four (forgetting the second half gives weapons silent for everybody but the holder).
# The magazine and the reserve are `owner_only`: exact ammunition is information an opponent should not have.

var net_slot: int = 0
## The held gun's attachments (`GSWeaponNetSync.fitting_specs`), for the hand a watcher draws.
var net_fitted: int = 0
var net_magazine: int = 0
var net_reserve: int = 0
var net_fire_seq: int = 0
var net_fire_kind: int = 0
var net_reloading: bool = false
var net_switching: bool = false
var net_fire_mode: int = 0

# An administrator's marks, from the live tools

## `ZzPlayer.blinded`. Owner only: see [method _register_net_vars].
var net_blind: bool = false

## `ZzPlayer.beacon`, an admin's mark. Everybody's.
var net_beacon: bool = false
var net_flashlight: bool = false
## The flash blind strength in 31sts (0 when not flashed).
var net_flash: int = 0

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
var last_move: GSFpsCommand = GSFpsCommand.new()

## And the slot they last asked for, which is simulation state for a survivor: the arsenal is
## edge-triggered against it.
var last_slot: int = 0

var last_state_tick: int = -1


func _register_net_vars() -> void:
	for spec in GSFpsNetSync.state_specs():
		var declaration := replicate(spec["property"], GSNetVar.Type[spec["type"]])

		if int(spec["bits"]) > 0:
			declaration.bits(int(spec["bits"]))

		if bool(spec["interpolated"]):
			declaration.interpolated()

		if spec["property"] == &"net_crouch":
			declaration.range_of(0.0, 1.0)

	# Owner-only jump timers; guarded, a shell without API 10 has no rewind_specs().
	if GSAddonApi.build_level("gs_player_controller") >= 10:
		for spec in GSFpsNetSync.rewind_specs():
			var _timers := replicate(spec["property"], GSNetVar.Type[spec["type"]]).bits(int(spec["bits"])).to_owner_only()

	for spec in GSFpsNetSync.stamina_specs():
		var _stamina := replicate(spec["property"], GSNetVar.Type[spec["type"]]).bits(int(spec["bits"])).to_owner_only()

	# Server-driven: only pull() writes these, never the owner's prediction, so a change is not a misprediction.
	replicate(&"net_health", GSNetVar.Type.FLOAT_RANGE).range_of(0.0, 2000.0).bits(14).server_driven()
	replicate(&"net_max_health", GSNetVar.Type.FLOAT_RANGE).range_of(0.0, 2000.0).bits(12).server_driven()
	replicate(&"net_life", GSNetVar.Type.UINT).bits(2).server_driven()
	replicate(&"net_incaps", GSNetVar.Type.UINT).bits(4).server_driven()
	replicate(&"net_temp", GSNetVar.Type.FLOAT_RANGE).range_of(0.0, 400.0).bits(10).server_driven()
	replicate(&"net_pin", GSNetVar.Type.UINT).bits(3).server_driven()
	replicate(&"net_use", GSNetVar.Type.FLOAT_RANGE).range_of(0.0, 1.0).bits(7).server_driven()
	replicate(&"net_helped", GSNetVar.Type.FLOAT_RANGE).range_of(0.0, 1.0).bits(7).server_driven()
	replicate(&"net_using", GSNetVar.Type.UINT).bits(4).server_driven()
	replicate(&"net_kits", GSNetVar.Type.VARINT).server_driven()
	replicate(&"net_pills", GSNetVar.Type.VARINT).server_driven()
	replicate(&"net_defibs", GSNetVar.Type.VARINT).server_driven()
	replicate(&"net_status", GSNetVar.Type.UINT).bits(6).server_driven()
	replicate(&"net_flash", GSNetVar.Type.UINT).bits(5).server_driven()
	replicate(&"net_carry", GSNetVar.Type.UINT).bits(10).server_driven()
	replicate(&"net_points", GSNetVar.Type.VARINT).server_driven()
	replicate(&"net_ping", GSNetVar.Type.UINT).bits(10).server_driven()
	replicate(&"net_watching", GSNetVar.Type.BOOL).server_driven()

	var weapon_specs := ZeeWeaponNet.all_specs()
	weapon_specs.append_array(GSWeaponNetSync.fire_mode_specs())
	weapon_specs.append_array(GSWeaponNetSync.fitting_specs())
	for spec in weapon_specs:
		var declaration := replicate(spec["property"], GSNetVar.Type[spec["type"]])

		if int(spec["bits"]) > 0:
			declaration.bits(int(spec["bits"]))

		if bool(spec["interpolated"]):
			declaration.interpolated()

		if bool(spec["owner_only"]):
			var _owner := declaration.to_owner_only()

	# [b]Per-player state rather than an event[/b]: a client that joins after `beacon`, a lost snapshot or a re-laid field is corrected by the next snapshot, where an event sent once is missed. The blind goes to its owner alone.
	# [b]No relevance change for a beacon[/b]: every player here is already always relevant (`ZzNetBridge`), and a beacon turned OFF that reset `always_relevant` would drop the player from everybody's snapshot.
	var _blind := replicate(&"net_blind", GSNetVar.Type.BOOL).to_owner_only().server_driven()
	replicate(&"net_beacon", GSNetVar.Type.BOOL).server_driven()
	replicate(&"net_flashlight", GSNetVar.Type.BOOL).server_driven()
	replicate(&"net_warp", GSNetVar.Type.UINT).bits(4).server_driven()


func _net_apply_input(input: GSNetInput, _tick: int) -> void:
	var command := input as ZzNetCommand

	if command != null:
		last_move = command.move
		last_slot = command.slot

		if player != null:
			player.input_move = command.move
			player.wanted_slot = command.slot
			player.actions = command.actions
			player.shove_held = command.move.is_pressed(ZzNetCommand.BUTTON_SHOVE)


## On the authority the whole game ticks as one, so the first behaviour through drives the world and the rest find it done.
## On a predicting client there is one predicted player, and simulating it is all a client may compute.
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
		player.step_controller(tick, delta)

	pull()


## Authority only: what the simulation left this player as.
func pull() -> void:
	if player == null:
		return

	GSFpsNetSync.pull(player.controller.state, self)

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
	net_kits = maxi(player.medkits, 0)
	net_pills = maxi(player.pills, 0)
	net_defibs = maxi(player.defibs, 0)
	net_carry = clampi(player.carried_count, 0, 7) | (clampi(player.carried_index, 0, 63) << 3) | (512 if player.box_out else 0)
	net_status = (1 if player.biled else 0) | (2 if player.burning else 0) | (4 if player.box_blind else 0) | (clampi(player.goo_stacks, 0, 3) << 3) | (32 if player.flashed else 0)
	net_flash = clampi(roundi(player.flash_strength * 31.0), 1, 31) if player.flashed else 0
	net_points = maxi(player.points, 0)
	net_ping = clampi(player.ping_ms, 0, 1023)
	net_watching = player.watching
	net_blind = player.blinded
	net_beacon = player.beacon
	net_flashlight = player.flashlight
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
	GSFpsNetSync.push(self, player.controller.state)
	_adopt()

	# NOT the node, on a predicted entity: `receive_snapshot` calls this BEFORE the predictor reconciles, and reconcile reads the node as what the client is showing.
	# Moving it here makes the measured error the whole replay distance. Two games in this family shipped that line.
	if identity == null or not identity.is_predicted():
		player.global_position = player.controller.state.position


## A teleport is not a movement, so the interpolator must not draw one: a round start moves everybody across the map in one tick, and a watcher saw them fly there.
## The server counts the times it PUT this player somewhere (`ZzPlayer.place_at`); a mirror that sees the count change drops the interpolator's track before the new snapshot is added, so the body appears in its corner one render delay early.
## Not on the predicted entity: nothing interpolates that.
func _forget_the_path() -> void:
	if identity == null or identity.is_authoritative or identity.is_predicted():
		_seen_warp = net_warp
		return

	if _seen_warp >= 0 and net_warp != _seen_warp and bridge != null:
		var manager: Variant = bridge.get(&"net")
		if manager is GSNetManager and (manager as GSNetManager).interpolator != null:
			(manager as GSNetManager).interpolator.forget(identity.net_id)

	_seen_warp = net_warp


## Every frame on a remote player. Without this the interpolator's work sits in a property
## nothing reads and a remote player moves in snapshot-sized steps.
func _net_interpolated(_tick: int) -> void:
	if player == null:
		return

	GSFpsNetSync.push(self, player.controller.state)
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
	player.medkits = net_kits
	player.pills = net_pills
	player.defibs = net_defibs
	player.carried_count = net_carry & 7
	player.carried_index = (net_carry >> 3) & 63
	player.box_out = (net_carry & 512) != 0
	player.biled = (net_status & 1) != 0
	player.burning = (net_status & 2) != 0
	player.box_blind = (net_status & 4) != 0
	player.flashed = (net_status & 32) != 0
	player.flash_strength = net_flash / 31.0 if net_flash > 0 else 1.0
	player.goo_stacks = (net_status >> 3) & 3
	player.points = net_points
	player.ping_ms = net_ping
	player.watching = net_watching
	player.blinded = net_blind
	player.beacon = net_beacon
	player.flashlight = net_flashlight

	if was_down != player.is_down():
		player.fit_hitboxes()

	_apply_weapons()

	# The owner's own counts (owner_only), put onto the gun it draws once that has gone quiet.
	if player.view_rig != null:
		var _corrected := player.correct_view_rig(net_magazine, net_reserve, net_slot, net_reloading or net_switching)


## What a watcher does with somebody else's weapon state. [b]A counter, never an event per shot[/b]: an RPC per shot needs a reliable channel, costs a packet per shot per watcher and desyncs from the state it belongs with.
## [b]No world model goes to `ZeeWeaponNet.apply`[/b], the figure being built lazily and absent on a server; the answer is written onto the player (slot, switch, uses) and `ZzPlayer.present_body` hands it to the figure when drawn.
## The same counter also says `weapon_used`, which is the report.
func _apply_weapons() -> void:
	var answer := ZeeWeaponNet.apply(self, null, _seen_fire_seq)
	_seen_fire_seq = int(answer["seq"])

	player.mirrored = true
	player.mirror_slot = net_slot
	player.mirror_fitted = net_fitted
	player.mirror_switching = net_switching
	player.mirror_reloading = net_reloading
	player.mirror_fired += int(answer["fired"])
	if int(answer["fired"]) > 0:
		player.mirror_fire_kind = int(answer["kind"])

	if int(answer["fired"]) > 0:
		weapon_used.emit(int(answer["fired"]), int(answer["kind"]))
