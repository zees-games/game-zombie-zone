extends "headless_survival_dormant.gd"

## The possession sections of [headless_survival.gd]: a turned player drives the zombie they became, and a special's trick on the shove key.

const ZzNetCommand := preload("../game/net/zz_net_command.gd")


func _test_possession() -> void:
	_section("possession: a turned player drives the zombie they became")
	var game := await _hold(func(cfg: ZzConfig) -> void:
		cfg.survival_style = 0
		cfg.survival_warmup_seconds = 100.0
		cfg.infect_after_seconds = 1.0
		cfg.infect_count = 1, 2)

	var cmd := GSFpsCommand.new()
	cmd.move = Vector2(0, 1)
	cmd.yaw = 90.0
	for p: ZzPlayer in game.survivors():
		p.input_move = cmd

	await _sim(game, 1.3)
	var holder: StringName = &""
	for id: StringName in game.possession.holds:
		holder = id
	_check(game.possession.holds.size() == 1 and holder != &"", "the turned player holds a body", str(game.possession.holds))
	var npc: GSNpcInstance = game.horde.spawner.get_npc(game.possession.body_of(holder))
	_check(npc != null and npc.brain.drive != null and npc.brain.drive.active, "its brain is driven")
	_check(game.players[holder].life == ZzPlayer.Life.DEAD, "and the player themselves is dead")

	var before := npc.position()
	await _sim(game, 1.0)
	var moved := npc.position() - before
	_check(moved.x < -1.0 and absf(moved.z) < 0.5, "forward at yaw 90 walks it along -X", str(moved))
	_check(is_equal_approx(fposmod(((npc.node as Node3D).rotation.y - PI * 0.5) + PI, TAU) - PI, 0.0), "and faces that way", str((npc.node as Node3D).rotation.y))

	# Let go of the stick: it stands, and nothing else walks it.
	cmd.move = Vector2.ZERO
	await _sim(game, 0.6)
	before = npc.position()
	await _sim(game, 0.5)
	# Crowd separation may nudge it; what matters is that nothing walks it.
	_check((npc.node as ZzZombieBody).wish.length() < 0.01 and npc.position().distance_to(before) < 0.8, "no input: it stands still, no AI wandering", "%s -> %s wish %s" % [before, npc.position(), (npc.node as ZzZombieBody).wish])

	# A survivor in front of it, and fire: they are hurt.
	var other: ZzPlayer = null
	for p: ZzPlayer in game.survivors():
		if p.player_id != holder and p.life != ZzPlayer.Life.DEAD:
			other = p
	other.health.invulnerable = false
	var forward := Basis(Vector3.UP, deg_to_rad(90.0)) * Vector3.FORWARD
	other.place_at(npc.position() + forward * 1.0, 0.0)
	var hurt_ids: Array = []
	var on_hurt := func(victim: StringName, _amount: float, _from: Vector3) -> void: hurt_ids.append(victim)
	game.player_hurt.connect(on_hurt)
	cmd.set_button(ZzNetCommand.BUTTON_FIRE, true)
	await _sim(game, 1.0)
	game.player_hurt.disconnect(on_hurt)
	_check(hurt_ids.has(other.player_id), "attack hits a survivor in reach in front", str(hurt_ids))

	# Death of the body ends the hold.
	cmd.set_button(ZzNetCommand.BUTTON_FIRE, false)
	var _dealt := game.horde.spawner.damage(npc.instance_id, 9999.0, &"")
	await _sim(game, 0.5)
	_check(not game.possession.is_holding(holder), "the hold ends when the body dies", str(game.possession.holds))
	await _dispose(game)
	_finished()


func _test_possession_ability() -> void:
	_section("possession: a special's trick on the shove key (leap, charge, spit, rock, ride)")
	var game := await _hold(func(cfg: ZzConfig) -> void:
		cfg.survival_style = 0
		cfg.survival_warmup_seconds = 100.0, 2)

	var holder: ZzPlayer = game.survivors()[0]
	var base := game.survivors()[1].global_position
	var cmd := GSFpsCommand.new()
	cmd.yaw = 180.0
	holder.input_move = cmd

	for kind: StringName in [ZzNpcs.LEAPER, ZzNpcs.RAM, ZzNpcs.SPITTER, ZzNpcs.BRUTE]:
		var npc := game.horde.spawner.spawn(kind, base + Vector3(0.0, 0.0, 6.0), &"test")
		await _sim(game, 0.3)
		_check(npc != null and game.possession.possess(holder, npc), "%s: can be held" % kind)

		if npc == null:
			continue

		var from := npc.position()
		var brain := npc.brain
		await _sim(game, 0.4)
		_check(npc.position().distance_to(from) < 1.0, "%s: stands until told" % kind, str(npc.position().distance_to(from)))
		from = npc.position()
		cmd.set_button(ZzNetCommand.BUTTON_SHOVE, true)
		await _sim(game, 0.1)
		cmd.set_button(ZzNetCommand.BUTTON_SHOVE, false)
		await _sim(game, 1.6)
		var moved := npc.position() - from

		match kind:
			ZzNpcs.LEAPER:
				_check(moved.z > 6.0 and absf(moved.x) < 3.0, "the leaper leaps along where they face", str(moved))
			ZzNpcs.RAM:
				_check(moved.z > 8.0 and absf(moved.x) < 3.0, "the ram charges that way", str(moved))
			_:
				_check(not brain.cooled_down() and moved.length() < 1.0, "the %s threw (cooling down) without walking" % kind, str(moved))

		game.possession.release(holder.player_id)
		var _dealt := game.horde.spawner.damage(npc.instance_id, 99999.0, &"")

	await _possession_pitch(game, holder, cmd, base)
	await _possession_rider(game, holder, cmd, base)

	await _dispose(game)
	_finished()


## A spit goes where they look: looking down lands it at the body's feet.
func _possession_pitch(game: ZzGame, holder: ZzPlayer, cmd: GSFpsCommand, base: Vector3) -> void:
	var spitter := game.horde.spawner.spawn(ZzNpcs.SPITTER, base + Vector3(0.0, 0.0, 6.0), &"test")
	await _sim(game, 0.3)
	_check(spitter != null and game.possession.possess(holder, spitter), "spitter: held again for the pitch check")

	if spitter != null:
		cmd.pitch = -45.0
		await _sim(game, 0.2)
		var sb: Object = spitter.brain
		_check(is_equal_approx(float(sb.get(&"drive_pitch")), deg_to_rad(-45.0)), "the holder's pitch reaches the brain", str(sb.get(&"drive_pitch")))
		var eye := spitter.position() + Vector3(0.0, 1.7, 0.0)
		var down: Vector3 = sb.call(&"driven_target", eye, 14.0)
		var flat := Vector2(down.x - eye.x, down.z - eye.z).length()
		_check(flat < 3.0 and down.y < eye.y - 1.0, "looking 45 degrees down aims at the floor in front, not 14 m out", "%s from %s" % [down, eye])
		cmd.pitch = 0.0
		await _sim(game, 0.2)
		var level: Vector3 = sb.call(&"driven_aim")
		_check(absf(level.y) < 0.01 and level.z > 0.99, "level aim is flat along where they face", str(level))
		game.possession.release(holder.player_id)
		var _gone := game.horde.spawner.damage(spitter.instance_id, 99999.0, &"")


## The rider leaps on whoever is in front, then the holder's stick walks them.
func _possession_rider(game: ZzGame, holder: ZzPlayer, cmd: GSFpsCommand, base: Vector3) -> void:
	var victim: ZzPlayer = game.survivors()[1]
	victim.health.invulnerable = true
	var rider := game.horde.spawner.spawn(ZzNpcs.RIDER, base + Vector3(0.0, 0.0, -4.0), &"test")
	await _sim(game, 0.3)
	_check(rider != null and game.possession.possess(holder, rider), "rider: can be held")

	if rider != null:
		victim.place_at(rider.position() + Vector3(0.0, 0.0, 3.5), 0.0)
		await _sim(game, 0.2)
		cmd.set_button(ZzNetCommand.BUTTON_SHOVE, true)
		await _sim(game, 0.1)
		cmd.set_button(ZzNetCommand.BUTTON_SHOVE, false)
		await _sim(game, 1.2)
		var ridden: StringName = game.horde.pinning(rider)
		_check(ridden == victim.player_id, "the rider leapt onto the survivor in front", "riding '%s' rider %s victim %s" % [ridden, rider.position(), victim.global_position])

		if ridden == victim.player_id:
			var start := victim.global_position
			cmd.move = Vector2(-1, 0)  # strafe left at yaw 180: along +X
			await _sim(game, 1.2)
			cmd.move = Vector2.ZERO
			var walked := victim.global_position - start
			_check(walked.x > 1.0 and absf(walked.z) < 1.5, "the holder's stick steers the ridden survivor", str(walked))

		game.possession.release(holder.player_id)
		var _off := game.horde.spawner.damage(rider.instance_id, 99999.0, &"")
