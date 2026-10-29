extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzBindings := preload("../game/zz_bindings.gd")

## Pills and medkits: own stack-limited slots, use on self, heal and give to a friend, and every cvar off.

const SECTIONS := 4
const CHECKS := 31

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone consumables")
	print("")
	await _test_slots()
	await _test_self()
	await _test_heal_others()
	await _test_give()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


## Two survivors a metre and a half apart, the first looking at the second, the second hurt.
func _pair() -> Array:
	var game := await _team(2, _quiet)
	var a := game.survivors()[0]
	var b := game.survivors()[1]
	a.place_at(a.feet(), 0.0)
	b.place_at(a.feet() + Vector3(0.0, 0.0, -1.5), 0.0)
	await _sim(game, 0.3)
	_aim(a, b.feet() + Vector3(0.0, 1.0, 0.0))
	return [game, a, b]


func _hurt(game: ZzGame, player: ZzPlayer, amount: float) -> void:
	var hit := DotDamage.make(0, player.entity_id, amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _aim(player: ZzPlayer, target: Vector3) -> void:
	var look := target - player.eye_position()
	var command := DotFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	player.controller.apply_command(command)
	player.controller.state.yaw = command.yaw
	player.controller.state.pitch = command.pitch


func _press(game: ZzGame, player: ZzPlayer, bits: int, seconds: float) -> void:
	player.actions = bits
	await _sim(game, seconds)
	player.actions = 0
	await _sim(game, 0.1)


func _test_slots() -> void:
	_section("slots: pills and medkits are their own counts, capped by their cvars")
	var game := await _team(1, _quiet)
	var p := game.survivors()[0]
	p.medkits = 0
	p.pills = 0
	var cons := game.consumables
	_check(cons.add_medkit(p) and p.medkits == 1 and p.pills == 0, "a medkit goes in the medkit slot only")
	_check(cons.add_pills(p) and p.pills == 1 and p.medkits == 1, "pills go in the pill slot only")
	cons.medkit_max = 2
	cons.pills_max = 2
	_check(cons.add_medkit(p) and not cons.add_medkit(p, false) and p.medkits == 2, "the medkit limit holds", str(p.medkits))
	_check(cons.add_pills(p) and not cons.add_pills(p, false) and p.pills == 2, "the pill limit holds", str(p.pills))
	cons.pills_max = 9
	_check(cons.add_pills(p) and p.pills == 3, "raising the cvar raises the limit")
	_check(ZzNetCommand.ACT_BITS == 12 and ZzNetCommand.ACT_GIVE_PILLS == 1024 and ZzNetCommand.ACT_GIVE_KIT == 2048, "the give bits are on the wire")
	var table := ZzBindings.make()
	_check(not table.row_for_action(ZzBindings.GIVE_PILLS).is_empty() and not table.row_for_action(ZzBindings.GIVE_KIT).is_empty(), "the Controls page lists both give keys")
	var game2 := await _team(1, _quiet)
	var q := game2.survivors()[0]
	_check(game2.consumables.medkit_max >= 1 and game2.consumables.pills_max >= 1, "the defaults allow a stack")
	_check(q.medkits <= game2.consumables.medkit_max, "a fresh survivor starts within the limit")
	_finished()


func _test_self() -> void:
	_section("self: pills take a held second and are cancelled by damage, a medkit heals")
	var game := await _team(1, _quiet)
	var p := game.survivors()[0]
	p.pills = 2
	p.medkits = 1
	game.consumables.pills_seconds = 1.0
	await _press(game, p, ZzNetCommand.ACT_PILLS, 0.3)
	_check(p.pills == 2 and p.using == &"", "a tap does not take a pill")

	await _hurt(game, p, 40.0)
	await _sim(game, 0.2)
	p.actions = ZzNetCommand.ACT_PILLS
	await _sim(game, 0.4)
	_check(p.using == &"pills" and p.use_fraction > 0.0 and p.use_fraction < 1.0, "holding starts a progress", str(p.use_fraction))
	p.actions = 0
	await _sim(game, 0.2)
	_check(p.using == &"" and p.pills == 2, "letting go cancels it and keeps the pill")

	p.actions = ZzNetCommand.ACT_PILLS
	await _sim(game, 0.3)
	await _hurt(game, p, 5.0)
	await _sim(game, 0.2)
	_check(p.using == &"" and p.pills == 2, "damage taken cancels it")
	p.actions = 0
	await _sim(game, 0.2)

	var before := p.health.health
	p.actions = ZzNetCommand.ACT_PILLS
	await _sim(game, 1.4)
	p.actions = 0
	_check(p.pills == 1 and p.health.health > before, "held to the end it takes one pill and adds temporary health", "%d, %.0f > %.0f" % [p.pills, p.health.health, before])

	var low := p.real_health()
	p.actions = ZzNetCommand.ACT_HEAL
	await _sim(game, game.config.medkit_seconds + 0.5)
	p.actions = 0
	_check(p.medkits == 0 and p.real_health() > low, "a medkit held to the end is used up and heals", "%.0f > %.0f" % [p.real_health(), low])
	_finished()


func _test_heal_others() -> void:
	_section("heal others: server authoritative, in range and sight, cancelled by moving away")
	var rig := await _pair()
	var game: ZzGame = rig[0]
	var a: ZzPlayer = rig[1]
	var b: ZzPlayer = rig[2]
	a.medkits = 2
	await _hurt(game, b, 50.0)
	await _sim(game, 0.1)
	_aim(a, b.feet() + Vector3(0.0, 1.0, 0.0))
	var low := b.real_health()
	a.actions = ZzNetCommand.ACT_HEAL
	await _sim(game, 0.5)
	_check(a.using == &"heal" and a.use_target == b.entity_id, "holding the key at a hurt friend starts healing them")
	_check(b.helped_fraction > 0.0, "the friend sees the progress too", str(b.helped_fraction))
	await _sim(game, game.config.medkit_seconds + 0.5)
	a.actions = 0
	_check(a.medkits == 1 and b.real_health() > low, "it consumes the healer's kit and heals the friend", "%d kits, %.0f > %.0f" % [a.medkits, b.real_health(), low])

	await _hurt(game, b, 50.0)
	await _sim(game, 0.1)
	_aim(a, b.feet() + Vector3(0.0, 1.0, 0.0))
	a.actions = ZzNetCommand.ACT_HEAL
	await _sim(game, 0.5)
	b.place_at(b.feet() + Vector3(0.0, 0.0, -6.0), 0.0)
	await _sim(game, 0.2)
	a.actions = 0
	_check(a.using == &"" and a.medkits == 1, "the friend walking out of range cancels it")

	b.place_at(a.feet() + Vector3(0.0, 0.0, -1.5), 0.0)
	await _sim(game, 0.2)
	_aim(a, b.feet() + Vector3(0.0, 1.0, 0.0))
	a.actions = ZzNetCommand.ACT_HEAL
	await _sim(game, 0.5)
	_aim(a, b.feet() + Vector3(4.0, 1.0, 0.0))
	await _sim(game, 0.2)
	a.actions = 0
	_check(a.using == &"" and a.medkits == 1, "looking away cancels it")

	_aim(a, b.feet() + Vector3(0.0, 1.0, 0.0))
	a.actions = ZzNetCommand.ACT_HEAL
	await _sim(game, 0.5)
	await _hurt(game, a, 10.0)
	await _sim(game, 0.2)
	a.actions = 0
	_check(a.using == &"" and a.medkits == 1, "the healer taking damage cancels it", "%s %d %.0f" % [a.using, a.medkits, a.real_health()])

	_aim(a, b.feet() + Vector3(0.0, 1.0, 0.0))
	game.consumables.heal_others = false
	var self_hp := a.real_health()
	a.actions = ZzNetCommand.ACT_HEAL
	await _sim(game, 0.5)
	_check(a.using != &"heal" or a.use_target == a.entity_id, "zz_heal_others 0 never targets the friend")
	a.actions = 0
	await _sim(game, 0.2)
	_check(b.real_health() < b.health.max_health and self_hp > 0.0, "and the friend stays hurt")
	game.consumables.heal_others = true

	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 4.0, 0.2)
	shape.shape = box
	wall.add_child(shape)
	wall.collision_layer = game.world_mask()
	game.add_child(wall)
	wall.global_position = (a.feet() + b.feet()) * 0.5 + Vector3(0.0, 1.0, 0.0)
	await _sim(game, 0.2)
	await _hurt(game, a, 0.0)
	var found := game.consumables.aimed_friend(a, 3.0)
	_check(found["who"] == null, "a wall in between refuses (no line of sight)", str(found["why"]))
	wall.queue_free()
	_finished()


func _test_give() -> void:
	_section("give: one pill moves, the limit and the cvars are respected")
	var rig := await _pair()
	var game: ZzGame = rig[0]
	var a: ZzPlayer = rig[1]
	var b: ZzPlayer = rig[2]
	a.pills = 3
	b.pills = 0
	a.medkits = 1
	b.medkits = 0
	await _press(game, a, ZzNetCommand.ACT_GIVE_PILLS, 0.2)
	_check(a.pills == 2 and b.pills == 1, "the key hands exactly one pill over", "%d -> %d" % [a.pills, b.pills])

	game.consumables.pills_max = 1
	var refusals: Array = []
	game.refused.connect(func(id: StringName, text: String) -> void: refusals.append([id, text]))
	await _press(game, a, ZzNetCommand.ACT_GIVE_PILLS, 0.2)
	_check(a.pills == 2 and b.pills == 1, "a full friend gets nothing and the giver keeps it")
	var said := false
	for r in refusals:
		said = said or (r[0] == a.player_id and str(r[1]).length() > 0)
	_check(said, "and the giver is told why")
	game.consumables.pills_max = 4

	game.consumables.give_pills = false
	await _press(game, a, ZzNetCommand.ACT_GIVE_PILLS, 0.2)
	_check(a.pills == 2 and b.pills == 1, "zz_give_pills 0 blocks it")
	game.consumables.give_pills = true

	b.place_at(b.feet() + Vector3(0.0, 0.0, -8.0), 0.0)
	await _sim(game, 0.2)
	await _press(game, a, ZzNetCommand.ACT_GIVE_PILLS, 0.2)
	_check(a.pills == 2 and b.pills == 1, "out of range refuses")
	b.place_at(a.feet() + Vector3(0.0, 0.0, -1.5), 0.0)
	await _sim(game, 0.2)
	_aim(a, b.feet() + Vector3(0.0, 1.0, 0.0))

	await _press(game, a, ZzNetCommand.ACT_GIVE_KIT, 0.2)
	_check(a.medkits == 0 and b.medkits == 1, "the kit key hands a medkit over")
	game.consumables.give_medkits = false
	var _got := game.consumables.add_medkit(a, false)
	await _press(game, a, ZzNetCommand.ACT_GIVE_KIT, 0.2)
	_check(a.medkits == 1 and b.medkits == 1, "zz_give_medkits 0 blocks it")
	_finished()


func _world(configure: Callable = Callable()) -> ZzGame:
	for old in _worlds.duplicate():
		await _dispose(old)

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.map_ids = PackedStringArray(["zz_practice"])
	config.keep_progress = false
	config.start_grace_seconds = 1.0
	config.escape_grace_seconds = 0.0
	config.sleepers_enabled = true

	if configure.is_valid():
		configure.call(config)

	var game := ZzGame.new()
	game.name = "World%d" % _worlds.size()
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	_worlds.append(game)

	await get_tree().physics_frame
	await get_tree().physics_frame
	return game


static func _quiet(c: ZzConfig) -> void:
	c.wanderer_density = 0.0
	c.specials_base = 0
	c.mob_interval_min = 900.0
	c.mob_interval_max = 900.0
	c.sleepers_enabled = false


func _dispose(game: ZzGame) -> void:
	_worlds.erase(game)

	if not is_instance_valid(game):
		return

	remove_child(game)
	game.free()
	await get_tree().process_frame


func _sim(game: ZzGame, seconds: float) -> void:
	var ticks := maxi(int(round(seconds * float(TICK_RATE))), 1)

	for i in ticks:
		game.simulate(TICK)

		if i % 8 == 7:
			await get_tree().physics_frame

	await get_tree().physics_frame


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1


func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game
