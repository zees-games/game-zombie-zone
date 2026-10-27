extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzCarry := preload("../game/zz_carry.gd")
const ZzClasses := preload("../game/zz_classes.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

## Carry weight: off by default, the limit and a refused pickup, backpacks, several weapons per slot and cycling,
## box modifiers, the slow and drop rules, and the wire. Counts sections AND checks, because a script error aborts a section silently.

const SECTIONS := 8
const CHECKS := 50

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()
var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone carry weight")
	print("")
	await _test_off()
	await _test_limit()
	await _test_cycle()
	await _test_modifiers()
	await _test_wire()
	await _test_depression()
	await _test_class_profile()
	await _test_class_immunity()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	print("")
	print("%d sections entered, %d finished" % [_sections_entered, _sections_finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _sections_entered != _sections_finished or _sections_entered != SECTIONS:
		print("ERROR: %d of %d sections finished, %d expected." % [_sections_finished, _sections_entered, SECTIONS])
		code = 1

	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [_passed + _failed, CHECKS])
		code = 1

	get_tree().quit(code)


## A world with one survivor and the carry rules [param rules] (field -> value) on.
func _solo(rules: Dictionary) -> ZzGame:
	var game := await _team(1, func(c: ZzConfig) -> void:
		_quiet(c)
		for key: String in rules:
			c.set(key, rules[key]))
	return game


func _hand(game: ZzGame, id: StringName) -> bool:
	return game.arm(game.survivors()[0], id)


func _test_off() -> void:
	_section("off (the addon default, and zz_weight_enabled 0): nothing is weighed, nothing refused, one weapon per slot")
	var game := await _solo({"weight_enabled": false})
	var p := game.survivors()[0]
	var heavies := ZzWeapons.ids_of(&"heavy")
	_check(not DotWeaponCarry.new().enabled, "the addon's carry is off until a game turns it on")
	_check(not game.carry.carry.enabled and p.weapons.arsenal.carry != null and not p.weapons.arsenal.carry.enabled, "the shared carry is off")
	_check(heavies.size() >= 2 and _hand(game, heavies[0]) and _hand(game, heavies[1]), "two heavy weapons are both handed over")
	var slot_of := p.weapons.arsenal.catalogue.get_def(heavies[1]).slot
	_check(p.weapons.arsenal.weapons_in(slot_of).size() == 1, "a slot holds one weapon, as before")
	_check(p.weapons.arsenal.speed_scale() == 1.0 and game.carry.state_json(p) == '{"on":false}', "no slow, no HUD")
	_finished()


func _test_limit() -> void:
	_section("a limit refuses a heavy pickup with a message; a backpack lifts it")
	var game := await _solo({"weight_enabled": true, "weight_limit": 9.0, "weight_slot_capacity": 2})
	var p := game.survivors()[0]
	var arsenal := p.weapons.arsenal
	var heavies := ZzWeapons.ids_of(&"heavy")
	var weight := game.carry.carry.weight_of(arsenal.catalogue.get_def(heavies[0]))
	_check(arsenal.catalogue.get_def(heavies[0]).weight > 0.0 and weight > 0.0, "every def has a weight (tier default)", "%.1f" % weight)
	_check(is_equal_approx(arsenal.capacity(), 9.0), "capacity is the limit", "%.1f" % arsenal.capacity())
	_check(_hand(game, heavies[0]), "one heavy fits under the limit")
	var before := arsenal.carried_weight()
	_check(not _hand(game, heavies[1]) and game.arm_failure.begins_with("Too heavy"), "a second is refused with a clear message", game.arm_failure)
	_check(is_equal_approx(arsenal.carried_weight(), before), "a refusal changes nothing")
	var took := game.wear_backpack(p, 3)
	_check(took and arsenal.capacity() > 20.0, "backpack 3 raises the limit", "%.1f" % arsenal.capacity())
	_check(not game.wear_backpack(p, 1), "a smaller pack is no upgrade")
	_check(_hand(game, heavies[1]), "and the second heavy now fits")
	_finished()


func _test_cycle() -> void:
	_section("a slot holds several weapons and the slot key again cycles them")
	var game := await _solo({"weight_enabled": true, "weight_limit": 100.0, "weight_slot_capacity": 2})
	var p := game.survivors()[0]
	var arsenal := p.weapons.arsenal
	var primaries := ZzWeapons.ids_of(&"primary")
	var slot := arsenal.catalogue.get_def(primaries[0]).slot
	var same: Array[StringName] = []
	for id in primaries:
		if arsenal.catalogue.get_def(id).slot == slot:
			same.append(id)
	_check(same.size() >= 2 and _hand(game, same[0]) and _hand(game, same[1]), "two weapons go to one slot")
	_check(arsenal.weapons_in(slot).size() == 2, "both are carried", str(arsenal.weapons_in(slot).size()))
	_check(arsenal.weapons_in(slot)[0].id() == same[1], "the newest is in hand (the others are stowed behind it)")
	p.wanted_slot = slot
	await _sim(game, 0.6)
	p.actions = ZzNetCommand.ACT_CYCLE
	await _sim(game, 0.1)
	_check(arsenal.current() != null and arsenal.current().id() == same[0], "ACT_CYCLE brings the other one out")
	p.actions = 0
	await _sim(game, 0.1)
	p.actions = ZzNetCommand.ACT_CYCLE
	await _sim(game, 0.1)
	_check(arsenal.current().id() == same[1], "and again, back")
	p.actions = ZzNetCommand.ACT_CYCLE
	await _sim(game, 0.3)
	_check(arsenal.current().id() == same[1], "a held bit is one press")
	p.actions = 0
	var m4 := ZzWeaponIds.M4
	_check(_hand(game, m4) and arsenal.current().id() == m4, "the carbine is in hand")
	var before := arsenal.fire_mode()
	p.actions = ZzNetCommand.ACT_FIRE_MODE
	await _sim(game, 0.3)
	_check(arsenal.fire_mode() != before and arsenal.fire_mode() == DotWeaponDef.Fire.SEMI, "ACT_FIRE_MODE cycles auto to semi once, however long it is held")
	p.actions = 0
	_finished()


func _test_modifiers() -> void:
	_section("box modifiers scale weight and limit; over the limit slows or drops")
	var game := await _solo({"weight_enabled": true, "weight_limit": 20.0, "weight_slot_capacity": 2,
		"weight_modifiers": "hard=2/1/0,light=1/1/10"})
	var p := game.survivors()[0]
	var arsenal := p.weapons.arsenal
	var heavies := ZzWeapons.ids_of(&"heavy")
	_check(_hand(game, heavies[0]), "a heavy under the limit")
	await _sim(game, 0.2)
	_check(is_equal_approx(p.carry_scale, 1.0), "not slowed", str(p.carry_scale))
	var base := arsenal.carried_weight()
	var _fx := game.boxes.activate(&"hard", &"hard", {})
	await _sim(game, 0.2)
	_check(game.boxes.stacks_of(&"hard") == 1 and is_equal_approx(game.carry.carry.weight_factor(), 2.0), "a Hard box doubles every weight")
	_check(is_equal_approx(arsenal.carried_weight(), base * 2.0), "carried weight follows", "%.1f" % arsenal.carried_weight())
	game.config.weight_multiplier = 3.0
	await _sim(game, 0.2)
	_check(arsenal.over_by() > 0.0 and p.carry_scale < 1.0 and p.carry_scale >= game.config.weight_slow_floor, "over the limit slows the player", str(p.carry_scale))
	game.config.weight_multiplier = 1.0
	game.config.weight_modifiers = ""
	await _sim(game, 0.2)
	_check(is_equal_approx(p.carry_scale, 1.0) and game.carry.carry.modifiers().is_empty(), "removing the rule restores speed")
	game.config.weight_over_limit = "drop"
	game.config.weight_multiplier = 3.0
	await _sim(game, 0.3)
	_check(arsenal.over_by() <= 0.001 or arsenal.weapons_in(arsenal.current_slot()).size() == 1, "drop mode puts the carrier back under the limit", "%.1f of %.1f" % [arsenal.carried_weight(), arsenal.capacity()])
	_check(game.loot.count_of(&"weapon") >= 1, "and what was dropped lies on the ground")
	_finished()


func _test_wire() -> void:
	_section("the owner is told: CARRY round trip and the config groups")
	var game := await _solo({"weight_enabled": true, "weight_limit": 30.0, "weight_slot_capacity": 2})
	var p := game.survivors()[0]
	var state: Variant = JSON.parse_string(game.carry.state_json(p))
	_check(state is Dictionary and bool(state["on"]) and float(state["l"]) == 30.0 and (state["slots"] as Dictionary).size() >= 1, "state_json names weight, limit and slots")
	var body := ZzEvents.write_carry(game.carry.state_json(p))
	var reader := DotNetReader.new(body)
	var back := ZzEvents.read_carry(reader)
	_check(bool(back["ok"]) and str(back["json"]) == game.carry.state_json(p), "the CARRY event round-trips")
	_check(ZzNetCommand.ACT_CYCLE == 128 and ZzNetCommand.ACT_FIRE_MODE == 256 and ZzNetCommand.ACT_BITS == 9, "ACT_CYCLE and ACT_FIRE_MODE fit the action bits")
	var parsed := ZzCarry.parse_modifiers("hard=1.15,angry=1.1/0.9/-2,junk")
	_check(parsed.size() == 2 and parsed["angry"] == [1.1, 0.9, -2.0] and parsed["hard"] == [1.15, 1.0, 0.0], "modifier specs parse")
	var cfg := ZzConfig.new()
	_check(cfg.weight_backpack_tiers == "4,8,14" and ZzCarry.parse_floats(cfg.weight_backpack_tiers).size() == 3, "backpack tiers are a list in config")
	_finished()


func _test_depression() -> void:
	_section("the Great Depression box cuts the limit and raises the shop's prices, per stack")
	var game := await _solo({"weight_enabled": true, "weight_limit": 20.0})
	var arsenal := game.survivors()[0].weapons.arsenal
	var price: float = game.shop.multiplier()
	var _fx := game.boxes.activate(&"depression", &"depression", {})
	await _sim(game, 0.2)
	_check(game.boxes.stacks_of(&"depression") == 1, "the box is in force")
	_check(is_equal_approx(arsenal.capacity(), 15.0), "the limit is cut to three quarters", "%.1f" % arsenal.capacity())
	_check(is_equal_approx(game.shop.multiplier(), price * game.config.box_depression_price), "every price is multiplied by zz_box_depression_price")
	var _fx2 := game.boxes.activate(&"depression", &"depression", {})
	await _sim(game, 0.2)
	_check(is_equal_approx(game.shop.multiplier(), price * pow(game.config.box_depression_price, 2.0)), "and again for a second box")
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


func _aim(player: ZzPlayer, target: Vector3) -> void:
	var look := target - player.eye_position()
	var command := DotFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	player.controller.apply_command(command)
	player.controller.state.yaw = command.yaw
	player.controller.state.pitch = command.pitch


func _hurt(game: ZzGame, player: ZzPlayer, amount: float) -> void:
	var hit := DotDamage.make(0, player.entity_id, amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	var line := "%s%s" % [what, "" if detail == "" else "  (%s)" % detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game


const CLASS_DIR := "user://carry_class_cfg"


func _class_file(text: String) -> void:
	var path := CLASS_DIR.path_join("server/game/game-zombie-zone/class/survivor.yml")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	ZzClasses.forget()


func _test_class_profile() -> void:
	_section("the survivor class profile sets speed, sprint, stamina and carry; an edit lands on the next spawn")
	var _clean := DotPaths.remove_tree(CLASS_DIR)
	ZzClasses.set_roots(PackedStringArray([CLASS_DIR]))
	var plain := ZzConfig.new()
	var base := ZzPlayer.tunables_for(plain)
	_check(is_equal_approx(base.max_speed, plain.run_speed), "no server file: the config speed stands", "%.2f" % base.max_speed)
	_check(is_equal_approx(ZzClasses.carry_limit(14.0), 14.0), "and so does the carry limit")

	_class_file("speed: 1.5\nsprint_speed_scale: 1.4\nstamina_drain: 0.6\ncarry_limit: 20\n")
	var t := ZzPlayer.tunables_for(plain)
	_check(is_equal_approx(t.max_speed, plain.run_speed * 1.5), "a profile edit scales the run speed", "%.2f" % t.max_speed)
	_check(is_equal_approx(t.sprint_speed_scale, 1.4) and is_equal_approx(t.stamina_drain, 0.6), "and sets the sprint multiplier and stamina drain")
	_check(is_equal_approx(t.walk_speed_scale, plain.walk_speed_scale), "a number the profile leaves out keeps the config's")

	var game := await _solo({"weight_enabled": true, "weight_limit": 9.0})
	var p := game.survivors()[0]
	_check(is_equal_approx(p.weapons.arsenal.capacity(), 20.0), "the carry capacity is the class's", "%.1f" % p.weapons.arsenal.capacity())
	_check(is_equal_approx(p.controller.tunables.max_speed, plain.run_speed * 1.5), "a spawned survivor moves at the class speed", "%.2f" % p.controller.tunables.max_speed)

	_class_file("speed: 99\n")
	_check(is_equal_approx(ZzPlayer.tunables_for(plain).max_speed, plain.run_speed), "an unsafe value is refused and the config speed stands")

	ZzClasses.set_roots(PackedStringArray())
	var _gone := DotPaths.remove_tree(CLASS_DIR)
	_finished()


func _fall_hit(game: ZzGame, p: ZzPlayer) -> float:
	var before := p.health.health
	var hit := DotDamage.make(0, p.entity_id, 10.0, game.combat.damage_type(&"fall"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)
	var lost := before - p.health.health
	p.health.health = before
	return lost


func _test_class_immunity() -> void:
	_section("an `immune: [fall]` class takes no fall damage, and a respawn as another class keeps nothing")
	var _clean := DotPaths.remove_tree(CLASS_DIR)
	ZzClasses.set_roots(PackedStringArray([CLASS_DIR]))
	var game := await _solo({})
	var p := game.survivors()[0]
	_check(_fall_hit(game, p) > 0.0, "no profile: a fall hurts")

	_class_file("immune: [fall]\n")
	game.place_one(p)
	_check(is_zero_approx(_fall_hit(game, p)), "an immune: [fall] class takes no fall damage")
	var hit := DotDamage.make(0, p.entity_id, 10.0, game.combat.damage_type(&"bite"))
	hit.tick = game.current_tick()
	var before := p.health.health
	var _bitten := game.combat.apply_damage(hit)
	_check(p.health.health < before, "and is still bitten")
	p.health.health = before

	_class_file("speed: 1.0\n")
	game.place_one(p)
	_check(_fall_hit(game, p) > 0.0, "a respawn under a class without it clears the immunity")

	ZzClasses.set_roots(PackedStringArray())
	var _gone := DotPaths.remove_tree(CLASS_DIR)
	_finished()
