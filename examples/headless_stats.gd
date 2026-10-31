extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzMaterials := preload("../game/zz_materials.gd")

## Stats wiring through the shared addons: ammo profiles, per-shape materials, hitzone and penetration stats, rank.

const SECTIONS := 4
const CHECKS := 25

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []
## Set before _world(): the lifetime file the next world keeps.
var _stats_file := ""


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone stats")
	print("")
	await _test_ammo()
	await _test_stats()
	await _test_rank()
	await _test_rejoin()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _hit(game: ZzGame, p: ZzPlayer, group: StringName, weapon: StringName, ctx: Dictionary, lethal: bool = false) -> void:
	var d := DotDamage.make(p.entity_id, 0x7fff0001, 20.0, game.combat.damage_type(&"strike"))
	d.weapon_id = weapon
	d.hit_group = group
	d.health_lost = 20.0
	d.lethal = lethal
	d.context = ctx
	game.progress.on_damage(d)


func _stat(game: ZzGame, p: ZzPlayer, id: StringName) -> float:
	var values := game.progress.stats.session_values(game.progress.stats.players()[0])
	return values.get_value(id) if values != null else -1.0


func _test_ammo() -> void:
	_section("ammo: profiles load, reach the arsenal, materials resolve per box")
	var game := await _team(1, _quiet)
	var p := game.survivors()[0]
	_check(game.ammo_types != null and game.ammo_types.ids().size() >= 5, "five ammo profiles load", str(game.ammo_types.ids().size() if game.ammo_types else -1))
	_check(p.weapons.arsenal.ammo_types == game.ammo_types, "the survivor's arsenal uses them")
	_check(game.combat.trace.material_shape_fn.is_valid(), "the trace asks the map's shapes for a material")
	var body := StaticBody3D.new()
	var owner_a := CollisionShape3D.new()
	owner_a.set_meta(&"surface", &"concrete")
	var owner_b := CollisionShape3D.new()
	owner_b.set_meta(&"surface", &"wood")
	body.add_child(owner_a)
	body.add_child(owner_b)
	var ia := body.create_shape_owner(owner_a)
	var ib := body.create_shape_owner(owner_b)
	body.shape_owner_add_shape(ia, BoxShape3D.new())
	body.shape_owner_add_shape(ib, BoxShape3D.new())
	add_child(body)
	var m0 := ZzMaterials.penetration_of(body, 0)
	var m1 := ZzMaterials.penetration_of(body, 1)
	_check(m0 == &"concrete" and m1 == &"wood", "two boxes of one body name different materials", "%s %s" % [m0, m1])
	_check(ZzMaterials.penetration_of(body, 9) == &"", "an unknown shape names none")
	body.free()
	_finished()


func _test_stats() -> void:
	_section("stats: hits by zone, penetration, feed")
	var game := await _team(1, _quiet)
	var p := game.survivors()[0]
	_check(game.progress != null and game.progress.feed != null, "the progress node builds an event feed")
	var schema: DotStatsSchema = game.progress.stats.schema
	_check(schema.has(DotStatsHitzones.HITS) and schema.has(DotStatsPenetration.HITS), "the schema declares hitzone and penetration stats")
	_hit(game, p, &"head", &"zz_m4", {})
	_hit(game, p, &"generic", &"zz_m4", {})
	_check(_stat(game, p, DotStatsHitzones.HITS) == 1.0, "a zoned hit counts and a generic one does not", str(_stat(game, p, DotStatsHitzones.HITS)))
	_hit(game, p, &"chest", &"zz_m4", {"penetrated": true, "wallbang": true})
	_check(_stat(game, p, DotStatsPenetration.HITS) == 1.0, "a wallbang counts as a penetrating hit", str(_stat(game, p, DotStatsPenetration.HITS)))
	_check(_stat(game, p, DotStatsPenetration.DAMAGE) > 0.0, "with its damage")
	_hit(game, p, &"chest", &"zz_m4", {"ricochet": true})
	_check(_stat(game, p, DotStatsPenetration.HITS) == 2.0, "a ricochet counts too")
	_hit(game, p, &"legs", &"zz_m4", {}, true)
	_check(_stat(game, p, DotStatsHitzones.HITS) == 4.0 and _stat(game, p, DotStatsHitzones.KILLS) == 1.0, "a lethal zoned hit counts as a zone kill")
	_finished()


func _test_rank() -> void:
	_section("rank: kills publish rank_score")
	var game := await _team(1, _quiet)
	var p := game.survivors()[0]
	_check(game.progress.stats.schema.has(&"rank_score"), "rank_score is declared")
	game.progress.on_zombie_killed(p.player_id, &"common", false)
	game.progress.on_zombie_killed(p.player_id, &"brute", true)
	var score := _stat(game, p, &"rank_score")
	_check(score > 0.0, "kills raise the published rank score", str(score))
	_check(game.progress.points.totals.get(p.player_id, 0) == 265, "a common (10) and a headshot brute (250 + 5) file 265 points", str(game.progress.points.totals.get(p.player_id, 0)))
	_check(is_equal_approx(_stat(game, p, &"zz.points"), 265.0), "and the tracker holds them as zz.points")
	game.progress.on_revived(p.player_id)
	_check(game.progress.points.totals.get(p.player_id, 0) == 315, "a pick-up is an objective: 50 more")
	game.progress.on_zombie_killed(p.player_id, &"brute", false)
	_check(_stat(game, p, &"rank_score") != score, "a special kill moves it again")
	_check(game.progress.rank != null and game.progress.rank.terms.size() >= 5, "the rank has its terms")
	_finished()


func _test_rejoin() -> void:
	_section("rejoin: lifetime totals seed the rank baseline and persist")
	var path := "user://headless_stats_zz.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_stats_file = path
	var game := await _team(1, _quiet)
	_stats_file = ""
	var progress := game.progress
	var p := game.survivors()[0]
	var tracker := progress.stats
	_check(tracker.store is DotStatsStoreFile, "a game with stats_file keeps a file store")
	var id := p.player_id
	var key := progress.key_of(id)
	var heads := StringName(progress.HEADSHOTS)
	progress.record(id, heads, 3.0)
	progress.leave(id)
	var _w: DotResult = await tracker.flush_store()
	var stored: float = (await tracker.store.values_for(key)).value.get_value(heads)
	_check(stored == 3.0, "a leave files the session into the lifetime store", str(stored))
	progress.record(id, heads, 2.0)
	var base: DotStatsValues = progress.rank.baselines.get(id, null)
	_check(base != null and base.get_value(heads) == 3.0, "a rejoin reads the stored total as the rank baseline")
	var _w2: DotResult = await tracker.flush()
	var after: float = (await tracker.store.values_for(key)).value.get_value(heads)
	_check(after == 5.0, "a flush after the rejoin adds only the new session", str(after))
	var _w3: DotResult = await tracker.flush()
	_check((await tracker.store.values_for(key)).value.get_value(heads) == 5.0, "a second flush adds nothing")
	var reread := DotStatsStoreFile.new(path)
	reread.schema = tracker.schema
	_check((await reread.values_for(key)).value.get_value(heads) == 5.0, "the file holds the same total for a fresh process")
	_finished()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _world(configure: Callable = Callable()) -> ZzGame:
	for old in _worlds.duplicate():
		await _dispose(old)

	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.map_ids = PackedStringArray(["zz_practice"])
	config.keep_progress = true
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
	game.stats_file = _stats_file
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
