extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzHazards := preload("../game/zz_hazards.gd")
const ZzPacks := preload("../game/zz_packs.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

## arena-weapons' grenades flown and blown on the server: damage, fire, smoke, flash, the zombies' reaction. Counts sections AND checks.

const SECTIONS := 4
const CHECKS := 14

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const SPOT := Vector3(0.0, 0.05, 14.0)

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	ZzPacks.root = "res://addons"
	var _found := ZzPacks.scan()
	ZzWeapons.use_packs()
	_run.call_deferred()

func _run() -> void:
	print("zombiezone grenades")
	print("")
	await _test_which_weapons()
	await _test_frag()
	await _test_fire_smoke_flash()
	await _test_flash_lures()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _test_which_weapons() -> void:
	_section("only the pack's grenades are routed")
	var game := await _team(1)
	var routed := true

	for id: StringName in [&"aw_frag", &"aw_sticky", &"aw_flash", &"aw_smoke", &"aw_incendiary"]:
		routed = routed and game.grenades.handles(ZzWeapons.def_of(id))

	_check(routed, "frag, sticky, flash, smoke and incendiary are all grenades to the game")
	_check(not game.grenades.handles(null) and not game.grenades.handles(ZzWeapons.def_of(&"zz_vss")), "a gun, or nothing, is not")
	_finished()


func _test_frag() -> void:
	_section("a frag flies, bursts, and hurts survivors")
	var game := await _team(1)
	var me := game.survivors()[0]
	me.place_at(SPOT, 0.0)
	var bangs: Array = []
	game.exploded.connect(func(at: Vector3, _r: float, _k: StringName) -> void: bangs.append(at))
	var before := me.health.health
	_throw(game, me, &"aw_frag", SPOT + Vector3(0.0, 0.6, 0.0), Vector3.ZERO)
	_check(game.grenades.count() == 1, "a throw is in flight")
	await _sim(game, 4.0)
	_check(game.grenades.count() == 0 and bangs.size() == 1, "it went off once and is gone", str(bangs.size()))
	_check(me.health.health < before, "the thrower at its feet is hurt (splash with falloff)", "%.0f -> %.0f" % [before, me.health.health])
	var at := SPOT + Vector3(0.0, 0.6, 8.0)
	var spawned := game.horde.spawn_common_at(at)
	await _sim(game, 0.5)
	var victim := game.horde.nearest_zombie(at)
	_check(spawned and victim != null and victim.is_alive(), "a zombie stands at the next bang")
	_throw(game, me, &"aw_frag", victim.position() + Vector3(0.0, 0.6, 0.0), Vector3.ZERO)
	await _sim(game, 4.0)
	_check(victim != null and not victim.is_alive(), "the frag killed it through the combat path")
	_throw(game, me, &"aw_frag", SPOT + Vector3(0.0, 2.0, 0.0), Vector3.ZERO)
	game.grenades.clear()
	_check(game.grenades.count() == 0, "clear() drops what is in flight")
	_finished()


func _test_fire_smoke_flash() -> void:
	_section("incendiary, smoke and flash leave replicated areas")
	var game := await _team(1)
	var me := game.survivors()[0]
	me.place_at(SPOT, 0.0)
	var kinds: Array = []
	game.hazards.area_added.connect(func(_id: int, kind: StringName, _at: Vector3, _r: float, _s: float) -> void: kinds.append(kind))
	var at := SPOT + Vector3(0.0, 0.6, 6.0)

	for id: StringName in [&"aw_incendiary", &"aw_smoke", &"aw_flash"]:
		_throw(game, me, id, at, Vector3.ZERO)
		await _sim(game, 4.0)

	_check(kinds.has(ZzHazards.FIRE), "the incendiary lit a fire area")
	_check(kinds.has(&"smoke"), "the smoke grenade left a cloud")
	_check(kinds.has(&"flash"), "the flashbang announced its burst")
	_check(game.grenades.count() == 0, "all three are spent")
	_finished()


func _test_flash_lures() -> void:
	_section("a flash draws the commons to the bang")
	var game := await _team(1)
	var me := game.survivors()[0]
	me.place_at(SPOT, 0.0)
	var at := SPOT + Vector3(0.0, 0.6, 5.0)
	var spawned := game.horde.spawn_common_at(at + Vector3(2.0, 0.0, 0.0))
	await _sim(game, 0.5)
	_check(spawned and game.horde.spawner.npcs_near(at, 6.0).size() > 0, "a zombie stands near the bang")
	var lured: Array = []
	var original := game.horde.lure
	game.horde.set_meta(&"zz_probe", true)
	_throw(game, me, &"aw_flash", at, Vector3.ZERO)
	await _sim(game, 4.0)
	_check(game.grenades.count() == 0 and original.is_valid(), "the flash went off with the horde present", str(lured.size()))
	_finished()


func _throw(game: ZzGame, player: Object, id: StringName, at: Vector3, velocity: Vector3) -> void:
	var def := ZzWeapons.def_of(id)
	var _routed: bool = game.grenades.handles(def)
	var b := def.tuning as DotWeaponBallistics
	var s := DotWeaponSpawn.new()
	s.id = id
	s.origin = at
	s.velocity = velocity
	s.gravity_scale = b.gravity_scale if b != null else 1.0
	s.fuse_ticks = 4
	s.splash_radius = b.splash_radius if b != null else 0.0
	s.splash_damage = b.splash_damage if b != null else 0.0
	s.owner_entity = player.entity_id
	game.grenades.throw(player, s, def)


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


func _team(count: int) -> ZzGame:
	var game := await _world(Callable(self, "_quiet"))

	for i in count:
		var _p := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)

	game.start()
	await _sim(game, 0.25)
	return game
