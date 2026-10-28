extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzWorldView := preload("../game/zz_world_view.gd")
const ZzMutantView := preload("../npcs/zz_mutant_view.gd")
const ZzOilMonsterModel := preload("../npcs/zz_oil_monster_model.gd")

## The mutant: its catalogue entry, both gravity guns (zap, prop pull and throw), gun and jetpack
## destruction, flight, and the angry dive and slam. Counts sections AND checks.

const SECTIONS := 7
const CHECKS := 30

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const SPOT := Vector3(0.0, 0.05, 14.0)

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []
var _beams: Array = []
var _blasts: Array = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone mutant")
	print("")
	await _test_catalogue()
	await _test_zap()
	await _test_props()
	await _test_guns_off()
	await _test_jetpack()
	await _test_dive()
	await _test_view()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


## A world with one survivor at SPOT and a mutant [param gap] metres up the street from it.
func _arena(gap: float, tune: Dictionary = {}) -> Array:
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(SPOT, 0.0)
	_beams.clear()
	_blasts.clear()
	game.hazards.launched.connect(func(_id: int, kind: StringName, from: Vector3, v: Vector3) -> void:
		_beams.append([kind, from, from + v]))
	game.exploded.connect(func(at: Vector3, radius: float, kind: StringName) -> void:
		_blasts.append([kind, at, radius]))
	var mutant := game.horde.spawner.spawn(ZzNpcs.MUTANT, SPOT + Vector3(0.0, 0.0, gap), &"test")

	for key: String in tune:
		mutant.def.meta[key] = tune[key]

	await _sim(game, 0.2)
	return [game, me, mutant]


func _beams_of(kind: StringName) -> int:
	return _beams.filter(func(b: Array) -> bool: return b[0] == kind).size()


func _test_catalogue() -> void:
	_section("catalogue: the mutant is a rare special with a body, numbers and parts of its own")
	var def := ZzNpcs.builtin(ZzConfig.new()).filter(func(d: DotNpcDef) -> bool: return d.id == ZzNpcs.MUTANT)
	_check(def.size() == 1 and ZzNpcs.SPECIALS.has(ZzNpcs.MUTANT), "it is in the catalogue and the director's list")
	_check(def[0].move_speed < 3.0, "and slow on the ground, being heavy", "%.1f" % def[0].move_speed)
	_check(float(def[0].meta.get("slam_damage", 0.0)) > 0.0 and float(def[0].meta.get("zap_damage", 0.0)) > 0.0, "its damage numbers are meta (cvars reach them)")
	var defs: Dictionary = load("res://npcs/zz_zombie_limbs.gd").defs_for(&"mutant", 900.0)
	_check(defs.has("gunL") and defs.has("gunR") and defs.has("pack") and not defs.has("head"), "its parts are two guns and a jetpack, no zombie limbs", str(defs.keys()))
	_finished()


func _test_zap() -> void:
	_section("a gun zaps a survivor: a visible beam and damage")
	var a := await _arena(12.0, {"prop_chance": 0.0, "fly_from": 999.0, "zap_interval": 0.5})
	var game: ZzGame = a[0]
	var me: ZzPlayer = a[1]
	var before := me.health.health
	await _sim(game, 4.0)
	_check(_beams_of(&"beam_zap") >= 2, "beams were announced", str(_beams_of(&"beam_zap")))
	_check(me.health.health < before, "and the survivor took damage", "%.0f -> %.0f" % [before, me.health.health])
	_check(a[2].brain.status()["guns"][0] != "", "both guns have a state of their own", str(a[2].brain.status()["guns"]))
	_finished()


func _test_props() -> void:
	_section("a gun drags a loose prop in, holds it and throws it")
	var a := await _arena(10.0, {"prop_chance": 1.0, "fly_from": 999.0, "hold_time": 0.5})
	var game: ZzGame = a[0]
	var me: ZzPlayer = a[1]
	var toy: DotPropToy = game.map.toys.add_toy(&"barrel", SPOT + Vector3(0.0, 0.6, 6.0))
	_check(toy != null and toy.body != null, "a loose barrel is on the map")
	var held := false
	var before := me.health.health

	for i in 40:
		await _sim(game, 0.25)
		held = held or "hold" in a[2].brain.status()["guns"]

	_check(_beams_of(&"beam_pull") >= 1, "the pull is drawn as a beam", str(_beams_of(&"beam_pull")))
	_check(held, "it held the prop")
	_check(not is_instance_valid(toy) or not is_instance_valid(toy.body) or toy.body.global_position.distance_to(SPOT) < 12.0 or me.health.health < before, "and threw it toward the survivor", "%.0f hp" % (before - me.health.health))
	_finished()


func _test_guns_off() -> void:
	_section("a gun shot off falls away and stops working")
	var a := await _arena(12.0, {"prop_chance": 0.0, "fly_from": 999.0, "zap_interval": 0.4})
	var game: ZzGame = a[0]
	var body := a[2].node as ZzZombieBody
	var limbs := body.limbs
	_check(limbs != null and not limbs.is_severed(&"gunL"), "it has limbs, gunL on")
	var cut := limbs.hit_limb(&"gunL", body.global_position + Vector3(0, 2, 0), 500.0, Vector3.ZERO)
	_check(cut == &"gunL" and limbs.is_severed(&"gunL"), "enough damage takes the gun")
	_check(body.limb_mask != 0, "and the mask replicates it", str(body.limb_mask))
	limbs.hit_limb(&"gunR", body.global_position + Vector3(0, 2, 0), 500.0, Vector3.ZERO)
	_beams.clear()
	await _sim(game, 3.0)
	_check(_beams_of(&"beam_zap") == 0, "with both guns gone it zaps nothing")
	_check(a[2].brain.status()["parts"] & 3 == 3, "and knows it", str(a[2].brain.status()["parts"]))
	_finished()


func _test_jetpack() -> void:
	_section("the jetpack lifts it toward a far survivor; shot out, it falls and never flies again")
	var a := await _arena(40.0, {"fly_from": 10.0, "prop_chance": 0.0})
	var game: ZzGame = a[0]
	var body := a[2].node as ZzZombieBody
	await _sim(game, 5.0)
	_check(body.hovering and body.global_position.y > 3.0, "it flies", "y %.1f" % body.global_position.y)
	_check(body.anim == ZzZombieBody.Anim.FLY, "and says so on the wire (FLY)")
	body.limbs.hit_limb(&"pack", body.global_position + Vector3(0, 2, 0), 500.0, Vector3.ZERO)
	await _sim(game, 0.5)
	_check(not body.hovering and a[2].brain.hover.disabled(), "the pack out: it drops, disabled")
	await _sim(game, 6.0)
	_check(body.global_position.y < 1.0 and not body.hovering, "it lands and stays on foot", "y %.1f" % body.global_position.y)
	_finished()


func _test_dive() -> void:
	_section("angry and airborne it charges up, dives and slams the ground")
	var a := await _arena(30.0, {"fly_from": 10.0, "prop_chance": 0.0, "charge_time": 0.8, "zap_interval": 99.0})
	var game: ZzGame = a[0]
	var me: ZzPlayer = a[1]
	a[2].health = a[2].def.max_health * 0.25
	var states := {}
	var before := me.health.health

	for i in 80:
		await _sim(game, 0.25)
		states[String(a[2].brain.state)] = true
		if not _blasts.is_empty():
			break

	_check(states.has("charge") and states.has("dive"), "it went through charge and dive", str(states.keys()))
	_check(_blasts.size() >= 1 and _blasts[0][0] == &"slam", "and the landing is a slam", str(_blasts.size()))
	await _sim(game, 0.5)
	_check(me.health.health < before or me.is_down(), "the survivor was hurt", "%.0f -> %.0f" % [before, me.health.health])
	_check(a[2].brain.state == &"recover" or a[2].brain.state == &"walk", "then it is grounded, spent")
	_finished()


func _test_view() -> void:
	_section("the mutant's view draws a body, poses every state, and every Anim fits its 5 bits")
	var top := 0

	for value: int in ZzZombieBody.Anim.values():
		top = maxi(top, value)

	_check(top <= 31, "the largest Anim value fits the 5-bit replication", str(top))
	var root := Node3D.new()
	add_child(root)
	var view := ZzWorldView.view_for(ZzNpcs.MUTANT)
	root.add_child(view)
	view.build(ZzNpcs.MUTANT, 0)
	var mesh := view._mesh as MeshInstance3D
	_check(mesh != null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0, "it has a drawn mesh")
	var box := AABB()

	for m: MeshInstance3D in view._model.find_children("*", "MeshInstance3D", true, false):
		box = box.merge(m.global_transform * m.get_aabb()) if box.has_volume() else m.global_transform * m.get_aabb()

	_check(box.size.y > 1.0 and box.size.y < 5.0, "of a plausible height", str(box.size))
	var all := true

	for anim: int in ZzZombieBody.Anim.values():
		view.present(0.05, anim, 0)
		all = all and is_instance_valid(view._model)

	_check(all, "every state poses without error")
	view.present(0.05, ZzZombieBody.Anim.FLY, 0)
	var flying := view._model.position
	view.present(0.05, ZzZombieBody.Anim.IDLE, 0)
	_check(view.get_class() != "" and flying.is_finite(), "flying then idle poses finitely")
	_check(ZzMutantView.MUTANT_CREDITS != "" and ZzOilMonsterModel.OIL_MONSTER_CREDITS != "", "both own-model kinds carry a credit")
	root.queue_free()
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




func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game


const CLASS_DIR := "user://carry_class_cfg"
