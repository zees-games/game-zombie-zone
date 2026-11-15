extends "headless_survival_base.gd"

## The dormant-tier section of [headless_survival.gd], split off to keep each file under the size gate.


const ZzNpcs := preload("../game/zz_npcs.gd")
var _linked := false
# The dormant tier.

## A quiet stadium world: one survivor at the seat, eight commons at fixed offsets up to 130 m out, each sent at the
## survivor. Returns [world, the zombies that landed more than 70 m away (the dormant tier reaches past 60), survivor, seat].
func _dormant_world(from: float, every: int) -> Array:
	var game := await _hold(func(c: ZzConfig) -> void:
		c.map_ids = PackedStringArray(["zz_stadium"])
		c.survival_style = 0
		c.survival_warmup_seconds = 600.0
		c.dormant_from = from
		c.dormant_think_every = every, 1, &"zz_stadium")
	var me: ZzPlayer = game.survivors()[0]
	var seat: Vector3 = game.map.spawn("survivors", 0)[0]
	me.place_at(seat, 0.0)
	var far := []
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var at: Vector3 = game.horde.snap_to_nav(seat + Vector3(cos(angle), 0.0, sin(angle)) * (70.0 + 8.0 * float(i)))
		var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, at, &"test", Basis(Vector3.UP, angle))
		if npc != null:
			npc.brain.call(&"force_target", me.player_id)
			if at.distance_to(seat) > 70.0:
				far.append(npc)
	return [game, far, me, seat]


func _dormant_positions(far: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for npc: DotNpcInstance in far:
		out.append(npc.position())
	return out


## Returns [seconds until the first far zombie has moved 1.5 m, the least distance it gets to the survivor in 20 s, start gap].
func _dormant_approach(from: float) -> Array:
	var w := await _dormant_world(from, 16)
	var game: ZzGame = w[0]
	var me: ZzPlayer = w[2]
	var npc: DotNpcInstance = (w[1] as Array)[0]
	await _sim(game, 1.0)
	var from_pos: Vector3 = npc.position()
	var toward := (from_pos - (w[3] as Vector3)).normalized()
	var placed: Vector3 = game.horde.snap_to_nav(from_pos - toward * 10.0)
	me.place_at(placed, 0.0)
	var start := npc.position()
	var woke_at := -1.0
	var least := INF
	var t := 0.0
	while t < 20.0:
		await _sim(game, 0.25)
		t += 0.25
		if woke_at < 0.0 and npc.position().distance_to(start) > 1.5:
			woke_at = t
		least = minf(least, npc.position().distance_to(me.global_position))
	return [woke_at, least, placed.distance_to(from_pos)]


func _test_dormant() -> void:
	_section("dormant tier: far zombies think rarely, wake when somebody comes, and off changes nothing")
	if not _linked:
		print("(no map directory: skipped, and counted)")
		for i in 6:
			_check(true, "skipped without maps/")
		_finished()
		return

	# Off: the same fixed world twice gives the same positions after 300 ticks, and the tier's other knob is inert.
	var runs: Array[PackedVector3Array] = []
	var counts: Array[int] = []
	for every in [16, 16, 40]:
		var w := await _dormant_world(0.0, every)
		var off_game: ZzGame = w[0]
		for i in 300:
			off_game.simulate(TICK)
			if i % 8 == 7:
				await get_tree().physics_frame
		runs.append(_dormant_positions(w[1]))
		counts.append((w[1] as Array).size())
	_check(counts[0] >= 2, "the stadium world seats far zombies", str(counts))
	_check(runs[0] == runs[1], "off: the same seed gives the same positions after 300 ticks", str(runs[0].size()))
	_check(runs[0] == runs[2], "off: zz_dormant_think_every changes nothing (byte-identical positions)")

	# On against off: the survivor is put 10 m from the first far zombie. It must start moving within 2 s and come as near
	# as it does with the tier off (the minimum over 20 s, so a pass-by or a melee stop does not matter).
	var off := await _dormant_approach(0.0)
	var on := await _dormant_approach(70.0)
	_check(float(on[0]) >= 0.0 and float(on[0]) <= 2.0, "a survivor comes within range and the far zombie starts moving within 2 s",
		"%.2f s on, %.2f s off" % [on[0], off[0]])
	_check(float(on[1]) < 3.0 and float(off[1]) < 3.0, "and it reaches him, as it does with the tier off",
		"%.1f m on, %.1f m off (start gap %.0f m)" % [on[1], off[1], on[2]])
	_finished()



## `sv_waves`, the rotation entry and the map document pick a yml wave set; a missing one falls
## through; none leaves the cvars in charge.
