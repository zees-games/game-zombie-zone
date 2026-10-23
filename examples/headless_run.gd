extends Node

const ZzBindings := preload("../game/zz_bindings.gd")
const ZzBoxes := preload("../game/zz_boxes.gd")
const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzWaterRules := preload("../game/zz_water_rules.gd")
const ZzClient := preload("../game/zz_client.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzController := preload("../game/zz_controller.gd")
const ZzCrawlRules := preload("../game/zz_crawl_rules.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzHazards := preload("../game/zz_hazards.gd")
const ZzFixtures := preload("../game/zz_fixtures.gd")
const ZzHud := preload("../game/zz_hud.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzProps := preload("../game/zz_props.gd")
const ZzSettings := preload("../game/zz_settings.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzWorldView := preload("../game/zz_world_view.gd")

## The simulation, headless: the documents, the navigation, the horde and every special, the
## downs and the hands, the boxes, the objectives and how a map is won and lost.
##
## [b]Counts sections AND checks, and the second is the one that matters.[/b] A script error
## inside a section aborts that function and the section counter is already satisfied,
## because the section announced itself on the way in. dot-settings has the story.
##
## Every number about the map here is the built-in practice street's
## ([method ZzCatalogue.practice]), whose comment lists where everything is.

const SECTIONS := 40

const CHECKS := 275

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

## In the street, clear of the cars: where a fight is staged.
const STREET := Vector3(0.0, 0.05, 14.0)

## The barrier's switch, and the end room.
const SWITCH := Vector3(6.5, 1.0, 36.0)
const END_ROOM := Vector3(0.0, 0.05, 85.0)

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()

var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	# Optional packs linked into addons/ add weapons to the loot pool, which shifts what the
	# stand-ins pick up: this suite's thresholds are for the built-in game (headless_packs covers packs).
	load("res://game/zz_packs.gd").root = "res://examples/fixtures/none"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone headless run")
	print("")

	_test_config()
	_test_documents()
	_test_box_file()
	await _test_navigation()
	await _test_world_builds()
	await _test_start_area()
	await _test_a_common()
	await _test_shots()
	await _test_zombie_loot()
	await _test_toys()
	await _test_the_room_wakes()
	await _test_downs()
	await _test_borrowed_health()
	await _test_the_shove()
	await _test_team_damage()
	await _test_pins()
	await _test_every_special()
	await _test_the_new_specials()
	await _test_how_zombies_fall()
	await _test_how_survivors_fall()
	_test_what_zombies_look_like()
	await _test_hazards()
	await _test_loot()
	await _test_both_packs()
	await _test_every_box_outcome()
	await _test_effects_stack()
	await _test_turret_box()
	await _test_box_framework()
	await _test_objectives()
	await _test_winning_and_losing()
	await _test_stand_ins()
	await _test_stand_ins_and_the_pass_through_level()
	await _test_a_crowd_is_cheap()
	await _test_the_hud()
	await _test_help_and_menu()
	await _test_the_map_menu()
	await _test_the_client_platform()
	await _test_the_first_play_test()
	await _test_crawling_and_speed_boxes()
	await _test_water()

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
		print("ERROR: %d of %d sections finished, %d expected." % [
			_sections_finished, _sections_entered, SECTIONS
		])
		code = 1

	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		code = 1

	get_tree().quit(code)


# --- Without a world ------------------------------------------------------------

func _test_config() -> void:
	_section("the configuration")
	var config := ZzConfig.new()
	_check(config.validate().ok, "the defaults validate")
	_check(config.damage_scale() == 1.0 and is_equal_approx(ZzConfig.new().damage_scale(), 1.0),
		"normal is the number as written")
	config.difficulty = 3
	_check(config.damage_scale() > 4.0 and config.friendly_fire_scale() > config.friendly_fire,
		"expert hits five times as hard, and so do friends", "%.1f, %.2f" % [config.damage_scale(), config.friendly_fire_scale()])
	config.difficulty = 1
	_check(config.commons_cap(4) == config.commons_base + 3 * config.commons_per_survivor and config.commons_cap(1) == config.commons_base,
		"the crowd grows with the team")
	var settings := ZzConfig.new()
	_check(is_equal_approx(settings.box_deploy_seconds, 1.0), "a box deploys in a second by default (was 3.5)", str(settings.box_deploy_seconds))
	_check(not settings.box_labels, "boxes do not say what they are by default: the contents are a surprise")
	_check(settings.downed_crawl_speed > 0.0 and settings.downed_crawl_speed < settings.run_speed * 0.5,
		"a downed survivor crawls by default, at a pace well under a run", str(settings.downed_crawl_speed))
	var from_file := settings.apply_dictionary({"box_deploy_seconds": 2.5, "downed_crawl_speed": 0.8, "box_labels": true}, "file")
	_check(from_file.size() == 3 and is_equal_approx(settings.box_deploy_seconds, 2.5) and is_equal_approx(settings.downed_crawl_speed, 0.8)
		and settings.box_labels and settings.validate().ok, "all three are keys of the server's config file", str(from_file))
	settings.box_deploy_seconds = 0.1
	_check(not settings.validate().ok, "a deploy time under half a second is refused with a reason")
	settings.box_deploy_seconds = 1.0
	settings.downed_crawl_speed = 9.0
	_check(not settings.validate().ok, "so is a crawl faster than a walk")
	config.mob_interval_min = 500.0
	_check(not config.validate().ok, "a mob interval that runs backwards is refused")
	config.mob_interval_min = 90.0
	config.start_weapons = PackedStringArray()
	_check(not config.validate().ok, "so is starting with nothing in your hands")
	_finished()


func _test_documents() -> void:
	_section("map documents")
	var doc := ZzCatalogue.practice()
	_check(not doc.is_empty(), "the built-in practice street validates")
	_check(doc["mode"] == ZzMapDoc.EXODUS and (doc["areas"]["end"] as Array).size() == 1 and (doc["objectives"] as Array).size() == 1,
		"an exodus map with an end shelter and an objective")

	var bad := doc.duplicate(true)
	bad["mode"] = "deathmatch"
	_check(not ZzMapDoc.validate(bad).ok, "a mode that is neither is refused")

	bad = doc.duplicate(true)
	bad["areas"] = {"start": doc["areas"]["start"], "end": []}
	_check(not ZzMapDoc.validate(bad).ok, "an exodus map with nowhere to reach is refused")

	bad = doc.duplicate(true)
	bad["nav"] = {"floors": [[5, 5, 1, 1, 0]]}
	_check(not ZzMapDoc.validate(bad).ok, "a nav floor whose corners are the wrong way round is refused")

	bad = doc.duplicate(true)
	bad["items"] = [{"kind": "spaceship", "at": [0, 0, 0]}]
	var refused := ZzMapDoc.validate(bad)
	_check(not refused.ok and refused.error.message.contains("spaceship"), "an item kind nobody knows is refused, by name")

	var round_trip := ZzMapDoc.decode(ZzMapDoc.encode(doc))
	_check(round_trip.ok and ZzMapDoc.digest(round_trip.value) == ZzMapDoc.digest(doc), "it survives the wire to the byte")
	_finished()


func _test_box_file() -> void:
	_section("the box file")
	var boxes := ZzBoxes.new(null)
	var text := FileAccess.get_file_as_string("res://boxes/boxes.json")
	var loaded := boxes.load_text(text)
	_check(loaded.ok and boxes.types.size() >= 8, "it reads", "%d types" % boxes.types.size())

	var outcomes := 0
	for id in boxes.order:
		outcomes += ((boxes.types[id] as Dictionary)["outcomes"] as Array).size()
	_check(outcomes >= 70, "with an outcome list worth opening", "%d outcomes" % outcomes)

	var broken := JSON.parse_string(text) as Dictionary
	((broken["boxes"] as Array)[0]["outcomes"] as Array)[0]["actions"] = [{"do": "summon_a_dragon"}]
	var refused := ZzBoxes.new(null).load_text(JSON.stringify(broken))
	_check(not refused.ok and refused.error.message.contains("summon_a_dragon"),
		"a verb this game does not know refuses the whole file, by name")

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var drawn := {}
	for i in 400:
		drawn[boxes.random_type(&"brute", rng)] = true
	_check(drawn.size() == boxes.types.size(), "every type can drop", "%d of %d" % [drawn.size(), boxes.types.size()])
	_finished()


# --- The world ----------------------------------------------------------------------

func _test_navigation() -> void:
	_section("the zombies' ground")
	var game := await _team(1)
	var graph: DotNpcNavGraph = game.horde.spawner.nav

	# Asked with the barrier shut and the survivor on the near side: every mob spawn must be
	# somewhere it can walk to them from. The first dedicated run spawned its panic beyond it.
	game.survivors()[0].place_at(STREET, 0.0)
	await _sim(game, 0.1)
	var stranded := 0
	for i in 40:
		var p: Vector3 = game.horde._spawn_point(8.0, 60.0, true)
		if p != Vector3.INF and not graph.is_reachable(p, STREET, 3.0):
			stranded += 1
	_check(stranded == 0, "no mob is spawned where it cannot reach anybody", "%d of 40 behind the barrier" % stranded)

	var in_rooms := 0
	for p: Vector3 in game.horde.director.spawn_points:
		if (p.z < -5.0 and absf(p.x) < 6.0) or (p.z > 79.0 and absf(p.x) < 6.0):
			in_rooms += 1
	_check(in_rooms == 0, "and none in a safe room", "%d spawn points in one" % in_rooms)

	_check(graph != null and graph.is_ready() and game.horde.nav.point_count() > 1000,
		"the street is walkable", "%d points" % game.horde.nav.point_count())
	_check(not graph.find_path(Vector3(0, 0, -10), Vector3(0, 0, 30), 2.0).is_empty(),
		"the start room joins the street through its door")
	_check(graph.find_path(Vector3(0, 0, 30), Vector3(0, 0, 60), 2.0).is_empty(),
		"the shut barrier is a wall to the horde")
	game.open_gate("barrier")
	graph = game.horde.spawner.nav
	_check(not graph.find_path(Vector3(0, 0, 30), Vector3(0, 0, 85), 2.0).is_empty(),
		"and once it is open, the street runs on to the end room")
	_check(game.horde.director.spawn_points.size() > 20, "the director has somewhere to spawn",
		"%d" % game.horde.director.spawn_points.size())
	_finished()


func _test_world_builds() -> void:
	_section("a map, and the team in it")
	var game := await _team(4)
	_check(game.map.id() == ZzCatalogue.PRACTICE and game.map.gate_is_shut("barrier"), "the practice street, with its barrier shut")

	var all_in_start := true
	var armed := true
	for player in game.survivors():
		all_in_start = all_in_start and game.map.in_area("start", player.feet())
		armed = armed and player.weapons != null and player.weapons.arsenal.carries(&"pistol") \
			and player.weapons.arsenal.current_def().id == &"pistol"
	_check(all_in_start, "everybody starts in the start room")
	_check(armed, "holding the sidearm")
	_check(game.survivors()[0].medkits == 1 and game.survivors()[0].health.health == 100.0, "with a medkit and full health")
	var laid := 0
	for lid: int in game.spawners.loot_ids():
		laid += 1 if game.loot.entries[lid]["kind"] == ZzLoot.WEAPON else 0
	_check(game.loot.count_of(ZzLoot.WEAPON) - laid == 3 and game.loot.count_of(ZzLoot.BOX) == 1, "the map's weapons and its box are lying where it put them")
	_check(game.horde.spawner.count_of(ZzNpcs.SLEEPER) == 1, "and the sleeper is sitting where it put her")
	_finished()


func _test_start_area() -> void:
	_section("the start room holds the horde off")
	var game := await _team(2, func(c: ZzConfig) -> void: c.start_grace_seconds = 600.0)
	await _sim(game, 3.0)
	_check(game.phase == ZzGame.Phase.READY and not game.horde.pacing, "nothing comes while everybody is inside")
	game.survivors()[0].place_at(STREET, 0.0)
	await _sim(game, 0.5)
	_check(game.phase == ZzGame.Phase.PLAY and game.horde.pacing, "one step outside and it starts")
	_finished()


func _test_a_common() -> void:
	_section("a common notices, chases and hits")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	# Facing the survivor: one with its back to them would not see them, which is the point of
	# idling commons and is not what this section is about.
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -9), &"test", Basis(Vector3.UP, PI))
	(npc.brain as Object).set(&"idle_kind", 0)
	await _sim(game, 0.2)
	_check(str(npc.brain.get(&"state")) == "idle", "it starts idle")
	await _sim(game, 3.0)
	_check(str(npc.brain.get(&"state")) == "chase" or npc.position().distance_to(me.feet()) < 2.0,
		"a survivor in front of it is noticed", str(npc.brain.get(&"state")))
	var before := me.health.health
	await _sim(game, 3.0)
	_check(me.health.health < before, "it closes and hits", "%.0f -> %.0f" % [before, me.health.health])
	_check(before - me.health.health < 30.0, "a common's hits are small on normal", "%.0f" % (before - me.health.health))
	_finished()


## Why zombies seemed to drop nothing: the path works (a kill at certain odds lays a box and says
## so), and at the shipped odds a common is a one in eighty-odd drop, so a solo run that kills a
## few dozen mostly sees none.
func _test_zombie_loot() -> void:
	_section("a killed zombie drops a box at the configured odds")
	var game := await _team(1, func(c: ZzConfig) -> void:
		_quiet.call(c)
		c.box_drop_common = 1.0)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	var told: Array = []
	game.loot.added.connect(func(_id: int, kind: StringName, _item: StringName, _at: Vector3) -> void:
		told.append(kind))
	var lying := game.loot.count_of(ZzLoot.BOX)
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -6), &"test")
	await _sim(game, 0.1)
	_hurt_npc(game, npc, 10000.0)
	await _sim(game, 0.1)
	_check(not npc.is_alive() and game.loot.count_of(ZzLoot.BOX) == lying + 1 and told.has(ZzLoot.BOX),
		"at certain odds a dead common lays a box and the LOOT event goes out", "%d boxes over %d" % [game.loot.count_of(ZzLoot.BOX), lying])
	game.config.boxes_enabled = false
	var off := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -6), &"test")
	await _sim(game, 0.1)
	_hurt_npc(game, off, 10000.0)
	await _sim(game, 0.1)
	_check(game.loot.count_of(ZzLoot.BOX) == lying + 1, "zz_box_drops 0 drops none")
	var shipped := ZzConfig.new()
	_check(shipped.boxes_enabled and shipped.box_drop_common > 0.0, "the shipped config has drops on",
		"%.1f%% common" % (shipped.box_drop_common * 100.0))
	_finished()


func _test_shots() -> void:
	_section("shots kill zombies and the kill is credited")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -6), &"test")
	await _sim(game, 0.1)
	var shot := _shot(game, me, npc.position() + Vector3(0, 1.0, 0), 30.0)
	_check(shot.damages.size() == 1 and not shot.damages[0].refused, "a shot at its body lands")
	_check(npc.is_alive() and npc.health < npc.def.max_health, "and hurts it", "%.0f" % npc.health)
	var head := _shot(game, me, npc.position() + Vector3(0, 1.58, 0), 30.0)
	await _sim(game, 0.1)
	_check(not npc.is_alive() and head.damages.size() == 1 and head.damages[0].hit_group == DotHitGroup.HEAD,
		"a headshot finishes it")
	_check(me.commons_killed == 1 and me.points >= 1, "and it is theirs", "%d kills" % me.commons_killed)
	_finished()


## dot-props' toys on the practice street: a survivor walking into the football sends it on, a
## shot pushes the barrel it passes and the combat's trace sees straight through it (a toy is
## no cover), a pipe bomb throws the tyre, and a new map builds them all home again.
func _test_toys() -> void:
	_section("the street's toys")
	var game := await _team(1, _quiet)
	var box := game.map.toys
	_check(box != null and box.count() == 4 and box.missing.is_empty(), "the practice street has its four toys", str(box.describe()) if box != null else "none")
	var me := game.survivors()[0]
	var ball := box.toy(0)
	var b0 := ball.body.global_position
	me.place_at(b0 + Vector3(-0.4, -0.12, 0.0), -90.0)
	for _i in range(10):
		me.controller.state.velocity = Vector3(5.0, 0.0, 0.0)
		game._advance_toys(TICK)
		await get_tree().physics_frame
	for _i in range(20):
		await get_tree().physics_frame
	_check(ball.body.global_position.x > b0.x + 0.4, "a survivor walking into the football sends it on", "%.2f m" % (ball.body.global_position.x - b0.x))

	var barrel := box.toy(1)
	var r0 := barrel.body.global_position
	var shot := DotShot.make(&"test", me.entity_id, game.current_tick(), 0)
	shot.origin = r0 + Vector3(0.0, 0.0, -5.0)
	shot.direction = Vector3(0.0, 0.0, 1.0)
	shot.damage = 30.0
	shot.max_range = 40.0
	var through := game.combat.trace.line_of_sight(shot.origin, r0 + Vector3(0.0, 0.0, 2.0))
	game._shoot_toys(shot)
	for _i in range(20):
		await get_tree().physics_frame
	_check(barrel.body.global_position.distance_to(r0) > 0.02 and through,
		"a shot pushes the barrel it passes, and the combat's trace sees through it: no cover",
		"%.2f m, clear %s" % [barrel.body.global_position.distance_to(r0), str(through)])

	var tyre := box.toy(3)
	var t0 := tyre.body.global_position
	game.exploded.emit(t0 + Vector3(-1.5, 0.0, 0.0), 4.0, &"pipe_bomb")
	for _i in range(20):
		await get_tree().physics_frame
	_check(tyre.body.global_position.distance_to(t0) > 0.3, "a pipe bomb throws the tyre beside it", "%.2f m" % tyre.body.global_position.distance_to(t0))

	var _rebuilt := game.build_map(game.map_doc)
	await get_tree().physics_frame
	var fresh := game.map.toys
	_check(fresh != box and fresh.count() == 4 and fresh.toy(0).body.global_position.distance_to(b0) < 0.05,
		"a new map builds every toy home again")
	_finished()


func _test_the_room_wakes() -> void:
	_section("one scream wakes the room")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET + Vector3(0, 0, 30), 180.0)
	var crowd: Array[DotNpcInstance] = []
	for i in 6:
		var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(-3 + i, 0, 0), &"test")
		(npc.brain as Object).set(&"idle_kind", 0)
		crowd.append(npc)
	await _sim(game, 0.3)
	var asleep := crowd.all(func(n: DotNpcInstance) -> bool: return str(n.brain.get(&"state")) == "idle")
	_check(asleep, "six commons standing idle")
	crowd[0].brain.call(&"wake", me.player_id, Vector3.INF, 0.0)
	await _sim(game, 2.0)
	var awake := crowd.filter(func(n: DotNpcInstance) -> bool: return str(n.brain.get(&"state")) != "idle").size()
	_check(awake == 6, "the one woken wakes the rest", "%d of 6" % awake)
	_finished()


func _test_downs() -> void:
	_section("down, not dead, and the third time dead")
	var game := await _team(2, _quiet)
	var me := game.survivors()[0]
	var friend := game.survivors()[1]
	me.place_at(STREET, 0.0)
	friend.place_at(STREET + Vector3(1.2, 0, 0), 270.0)
	_hurt(game, me, 500.0)
	_check(me.is_down() and me.is_alive() and me.controller.has_modifier(ZzController.DOWN), "zero health is a down")
	_check(me.health.health == game.config.downed_health and me.incaps == 1, "with a bleed-out pool", "%.0f" % me.health.health)
	await _sim(game, 2.0)
	_check(me.health.health < game.config.downed_health - 4.0, "which bleeds", "%.0f" % me.health.health)

	_aim(friend, me.feet() + Vector3(0, 0.3, 0))
	friend.actions = ZzNetCommand.ACT_USE
	await _sim(game, game.config.revive_seconds * 0.5)
	_check(friend.using == &"revive" and me.helped_fraction > 0.3, "a friend holding E is picking them up", "%.2f" % me.helped_fraction)
	await _sim(game, game.config.revive_seconds * 0.6)
	friend.actions = 0
	_check(me.is_up() and not me.controller.has_modifier(ZzController.DOWN), "and up they get")
	_check(absf(me.health.health - game.config.revive_health) < 1.5 and me.temp_health > 20.0,
		"on borrowed health", "%.0f, %.0f of it borrowed" % [me.health.health, me.temp_health])

	_hurt(game, me, 500.0)
	game.stand_up(me)
	_check(me.on_last_life(), "two downs and the screen says the next is the last")
	_hurt(game, me, 500.0)
	_check(me.life == ZzPlayer.Life.DEAD and not me.is_alive(), "and it is")
	_finished()


func _test_borrowed_health() -> void:
	_section("pills, a medkit, and borrowed health")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	_hurt(game, me, 70.0)
	me.pills = 1
	me.actions = ZzNetCommand.ACT_PILLS
	await _sim(game, 0.1)
	me.actions = 0
	_check(me.pills == 0 and me.temp_health > 45.0 and me.health.health > 75.0, "pills are borrowed health",
		"%.0f, %.0f borrowed" % [me.health.health, me.temp_health])
	var borrowed := me.temp_health
	await _sim(game, 10.0)
	_check(me.temp_health < borrowed - 1.5, "which drains", "%.1f -> %.1f" % [borrowed, me.temp_health])
	var real := me.real_health()
	_hurt(game, me, 10.0)
	_check(absf(me.real_health() - real) < 0.5, "and is what a hit takes first")
	me.incaps = 2
	me.actions = ZzNetCommand.ACT_HEAL
	await _sim(game, game.config.medkit_seconds + 0.3)
	me.actions = 0
	_check(me.medkits == 0 and me.real_health() > 85.0 and me.incaps == 0,
		"a medkit heals most of what is missing and clears the last life", "%.0f" % me.real_health())
	_finished()


func _test_team_damage() -> void:
	_section("team damage: reflect, voteban, ban, and barricades")
	var game := await _team(2, _quiet)
	var a := game.survivors()[0]
	var b := game.survivors()[1]
	a.place_at(STREET, 0.0)
	b.place_at(STREET + Vector3(2.0, 0.0, 0.0), 0.0)
	game.config.friendly_fire_mode = 2
	game.config.rookie_minutes = 120.0
	_check(game.team_damage.is_new(a), "a player with no playtime is new")
	var a_before := a.health.health
	var b_before := b.health.health
	var hit := DotDamage.make(a.entity_id, b.entity_id, 20.0, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)
	_check(is_equal_approx(b.health.health, b_before), "a new player's shot at a friend does the friend nothing",
		"%.1f" % b.health.health)
	_check(a.health.health < a_before, "it lands on the shooter", "%.1f -> %.1f" % [a_before, a.health.health])
	a.session_seconds = 200.0 * 60.0
	_check(not game.team_damage.is_new(a), "a player past rookie_minutes is not new")
	b_before = b.health.health
	hit = DotDamage.make(a.entity_id, b.entity_id, 20.0, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	_applied = game.combat.apply_damage(hit)
	_check(b.health.health < b_before, "and their shot at a friend hurts the friend")
	game.config.friendly_fire_mode = 3
	_check(game.team_damage.reflects(a), "mode 3 reflects everybody")
	game.config.friendly_fire_mode = 0
	_check(game.config.friendly_fire_scale() == 0.0, "mode 0 is no friendly fire")
	game.config.friendly_fire_mode = 1

	var asked: Array = []
	var banned: Array = []
	game.team_damage.voteban_wanted.connect(func(id: StringName, damage: float) -> void: asked.append([id, damage]))
	game.team_damage.ban_wanted.connect(func(id: StringName, damage: float, minutes: float) -> void: banned.append([id, damage, minutes]))
	game.config.team_damage_window = 60.0
	game.config.team_damage_vote = 100.0
	game.config.team_damage_ban = 300.0
	game.config.team_damage_ban_minutes = 45.0
	var t := game.now()
	game.team_damage.forget(a.player_id)
	game.team_damage.record(a, 60.0, t)
	_check(asked.is_empty() and banned.is_empty(), "under the threshold asks for nothing")
	game.team_damage.record(a, 60.0, t + 1.0)
	_check(asked.size() == 1 and asked[0][0] == a.player_id, "over the threshold starts a voteban, once")
	game.team_damage.record(a, 10.0, t + 2.0)
	_check(asked.size() == 1, "and not again inside the window")
	game.team_damage.record(a, 200.0, t + 3.0)
	_check(banned.size() == 1 and is_equal_approx(float(banned[0][2]), 45.0), "over the ceiling bans for the set time")

	game.pass_rules.humans_pass = true
	game._apply_body_mask(a)
	var barricade := game.physics.layer_mask(&"barricade")
	_check(a.controller.tunables.collision_mask & barricade == 0, "a survivor's mask leaves the barricade out when they pass")
	game.pass_rules.humans_pass = false
	game._apply_body_mask(a)
	_check(a.controller.tunables.collision_mask & barricade != 0, "and keeps it when they do not")
	game.pass_rules.humans_pass = true
	_finished()


func _test_the_shove() -> void:
	_section("the shove")
	var game := await _team(2, _quiet)
	var me := game.survivors()[0]
	var friend := game.survivors()[1]
	me.place_at(STREET, 0.0)
	friend.place_at(STREET + Vector3(0, 0, -1.4), 0.0)
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -1.3), &"test")
	await _sim(game, 0.1)
	var before := npc.position()
	me.shove_held = true
	await _sim(game, 0.05)
	me.shove_held = false
	await _sim(game, 0.4)
	_check(bool(npc.brain.call(&"staggered")) or npc.position().distance_to(me.feet()) > before.distance_to(me.feet()) + 0.4,
		"it staggers a common back", "%.2f m" % npc.position().distance_to(before))

	var leaper := game.horde.spawner.spawn(ZzNpcs.LEAPER, friend.feet() + Vector3(1, 0, 0), &"test")
	await _sim(game, 0.1)
	_check(game.pins.pin(game.horde.entity_id_for(leaper), leaper, friend.player_id, &"pounce"), "a leaper on a friend")
	me.shove_ready_at = 0.0
	me.previous_shove = false
	me.shove_held = true
	await _sim(game, 0.1)
	me.shove_held = false
	_check(not friend.is_pinned(), "a shove knocks it off")

	var ram := game.horde.spawner.spawn(ZzNpcs.RAM, friend.feet() + Vector3(1, 0, 0), &"test")
	await _sim(game, 0.1)
	var _carried := game.pins.pin(game.horde.entity_id_for(ram), ram, friend.player_id, &"carry")
	me.shove_ready_at = 0.0
	me.previous_shove = false
	me.shove_held = true
	await _sim(game, 0.1)
	me.shove_held = false
	_check(friend.is_pinned() and friend.pin_kind == &"carry", "but nothing shoves a ram off anybody")
	_finished()


func _test_pins() -> void:
	_section("held: the damage, the drag, and killing what holds you")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	var strangler := game.horde.spawner.spawn(ZzNpcs.STRANGLER, STREET + Vector3(0, 0, -12), &"test")
	await _sim(game, 0.1)
	var _choked := game.pins.pin(game.horde.entity_id_for(strangler), strangler, me.player_id, &"choke")
	var start := me.feet()
	var before := me.health.health
	await _sim(game, 2.0)
	_check(me.is_pinned() and me.controller.has_modifier(ZzController.PINNED), "a tongue holds you")
	_check(me.feet().distance_to(strangler.position()) < start.distance_to(strangler.position()) - 3.0,
		"and drags you to it", "%.1f m" % start.distance_to(me.feet()))
	_check(me.health.health < before, "and hurts", "%.0f" % (before - me.health.health))
	_hurt_npc(game, strangler, 100000.0)
	await _sim(game, 0.1)
	_check(not me.is_pinned() and not me.controller.has_modifier(ZzController.PINNED), "kill it and you are free")
	_finished()


## Each special, put near a survivor, does what it is for within half a minute.
func _test_every_special() -> void:
	_section("every special uses what it has")
	var results := {}

	for kind in [ZzNpcs.LEAPER, ZzNpcs.STRANGLER, ZzNpcs.BLOATER, ZzNpcs.RAM, ZzNpcs.SPITTER, ZzNpcs.RIDER, ZzNpcs.BRUTE,
			ZzNpcs.SCREAMER, ZzNpcs.CRAWLER, ZzNpcs.RIOT]:
		var game := await _team(2, func(c: ZzConfig) -> void:
			c.wanderer_density = 0.0
			c.director_enabled = false)
		var me := game.survivors()[0]
		var friend := game.survivors()[1]
		me.place_at(STREET, 180.0)
		friend.place_at(STREET + Vector3(20, 0, 0), 0.0)
		me.health.invulnerable = false
		var npc := game.horde.spawn_special(kind, STREET + Vector3(0, 0, -14)) if kind != ZzNpcs.BRUTE \
			else game.horde.spawn_brute(STREET + Vector3(0, 0, -14))
		var used := false
		var acid_seen := false

		for i in 30 * 4:
			await _sim(game, 0.25)
			acid_seen = acid_seen or not game.hazards.areas.is_empty() or not game.hazards.flying.is_empty()
			match kind:
				ZzNpcs.BLOATER:
					used = me.biled_until > 0.0 or friend.biled_until > 0.0
				ZzNpcs.SPITTER:
					used = acid_seen
				ZzNpcs.BRUTE:
					used = me.health.health < 100.0 or me.is_down() or not game.hazards.flying.is_empty() or acid_seen
				ZzNpcs.SCREAMER:
					used = game.horde.screams > 0
				ZzNpcs.RIOT:
					used = me.health.health < 100.0 or friend.health.health < 100.0 or me.is_down()
				_:
					used = me.is_pinned() or friend.is_pinned() or me.is_down()
			if used or npc == null or not npc.is_alive():
				break
			# Keep them standing, so the test is of the special and not of how quickly it kills.
			if me.health.health < 30.0:
				me.health.health = 100.0

		results[kind] = used

	for kind: StringName in results:
		_check(results[kind], "a %s does its thing" % String(kind))
	_finished()


## The three specials added with the animated models (2026-10-12): what each one is for, one
## at a time and close up, where `_test_every_special` only asks that each does something.
func _test_the_new_specials() -> void:
	_section("the screamer calls a mob, the crawler holds an ankle, the riot shield stops a shot")

	# The screamer: in sight of somebody, it screams, and a mob comes for them.
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET, 180.0)
	var screamer := game.horde.spawn_special(ZzNpcs.SCREAMER, STREET + Vector3(0, 0, -16))
	var mob_before: int = game.horde.commons()
	var screamed_at := -1.0

	for i in 30 * 4:
		await _sim(game, 0.25)
		if game.horde.screams > 0:
			screamed_at = float(i) * 0.25
			break

	_check(screamer != null and game.horde.screams == 1, "a screamer in sight of you screams", "%.1f s" % screamed_at)
	_check(screamer != null and screamer.node.get(&"anim") == ZzZombieBody.Anim.SCREAM or game.horde.screams > 0,
		"and is drawn screaming")
	await _sim(game, 3.0)
	_check(game.horde.commons() > mob_before, "and a mob comes", "%d commons" % game.horde.commons())

	# The crawler: from behind, it gets hold of an ankle; you can still shoot, a shove frees you.
	game = await _team(2, _quiet)
	me = game.survivors()[0]
	var friend := game.survivors()[1]
	me.place_at(STREET, 0.0)
	friend.place_at(STREET + Vector3(0, 0, -1.6), 0.0)
	var crawler := game.horde.spawn_special(ZzNpcs.CRAWLER, STREET + Vector3(0, 0, 7))

	for i in 30 * 4:
		await _sim(game, 0.25)
		if me.is_pinned() or friend.is_pinned():
			break
		if me.health.health < 30.0:
			me.health.health = 100.0

	var held := me if me.is_pinned() else friend
	_check(held.is_pinned() and held.pin_kind == &"grab", "a crawler grabs an ankle", String(held.pin_kind))
	_check(held.controller.has_modifier(ZzController.PINNED) and not held.is_held(),
		"which roots you but leaves you your gun")
	var helper := friend if held == me else me
	helper.shove_ready_at = 0.0
	helper.previous_shove = false
	helper.place_at(held.feet() + Vector3(0, 0, 0.9), 0.0)
	_aim(helper, crawler.position() + Vector3(0, 0.3, 0))
	helper.shove_held = true
	await _sim(game, 0.1)
	helper.shove_held = false
	_check(not held.is_pinned(), "and a friend's shove frees you")
	_check(crawler.def.meta.get("height", 9.0) < 1.0, "it is low enough to miss over", "%.2f m" % float(crawler.def.meta.get("height", 0.0)))

	# The riot zombie: a shot into its shield does a tenth, the same shot into its back all of it.
	game = await _team(1, _quiet)
	me = game.survivors()[0]
	me.place_at(STREET, 0.0)
	var riot := game.horde.spawner.spawn(ZzNpcs.RIOT, STREET + Vector3(0, 0, -6), &"test")
	riot.brain = null
	var body := riot.node as Node3D
	body.look_at(Vector3(STREET.x, body.global_position.y, STREET.z), Vector3.UP)
	await _sim(game, 0.1)
	var full: float = riot.health
	var _front := _shot(game, me, body.global_position + Vector3(0, 0.9, 0), 100.0)
	await _sim(game, 0.05)
	var through_front: float = full - riot.health
	body.rotate_y(PI)
	await _sim(game, 0.1)
	var before_back: float = riot.health
	var _back := _shot(game, me, body.global_position + Vector3(0, 0.9, 0), 100.0)
	await _sim(game, 0.05)
	var through_back: float = before_back - riot.health
	_check(through_front > 0.0 and through_front <= 100.0 * game.config.riot_shield + 1.0,
		"a riot shield takes most of a frontal shot", "%.0f of 100" % through_front)
	_check(through_back >= 90.0, "and none of one from behind", "%.0f of 100" % through_back)
	_check(ZzNpcs.SPECIALS.has(ZzNpcs.SCREAMER) and ZzNpcs.SPECIALS.has(ZzNpcs.CRAWLER) and ZzNpcs.SPECIALS.has(ZzNpcs.RIOT),
		"the director may send all three")
	_finished()


## A zombie's death is decided where it dies, with a reaction a client draws.
func _test_how_zombies_fall() -> void:
	_section("a killed zombie carries how it falls")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -5), &"test")
	await _sim(game, 0.1)
	var seen: Array = []
	game.horde.zombie_died.connect(func(dead: DotNpcInstance, _by: StringName, _hit: DotDamage) -> void:
		if dead == npc and dead.node is ZzZombieBody:
			seen.append((dead.node as ZzZombieBody).death))
	var _shot_dead := _shot(game, me, npc.position() + Vector3(0, 1.0, 0), 10000.0)
	await _sim(game, 0.05)
	var death: DotPlayerDeath = seen[0] if not seen.is_empty() else null
	_check(not npc.is_alive() and death != null, "the server decides the fall")
	_check(death != null and game.horde.death_reactions.has(death.reaction), "as one of dot-player-char's reactions",
		String(death.reaction) if death != null else "-")
	_check(death != null and death.direction.dot(Vector3(0, 0, -1)) > 0.5, "pushed the way the shot went",
		str(death.direction) if death != null else "-")
	_finished()


## A survivor's death: the server picks the fall, it rides DEATH, and a client copies a ragdoll
## from the figure it draws into the same yard (and under the same sv_ragdoll* rules) as the
## zombies'.
func _test_how_survivors_fall() -> void:
	_section("a dead survivor falls as dot-player-char's ragdoll")
	var game := await _team(2, _quiet)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -1.2), &"test")
	await _sim(game, 0.1)
	var claw := 0
	for entity: int in game.horde._by_entity:
		if game.horde._by_entity[entity] == npc:
			claw = entity

	# Owner's weights reach the pick: crumple alone.
	var _set := game.ragdoll_rules.set_cvar("sv_ragdoll_reactions", "limp=0,face_plant=0,crumple=1,headshot_launch=0,power_launch=0")
	_check(game.horde.death_reactions.find(&"limp").weight == 0.0, "sv_ragdoll_reactions reaches the horde's pick")

	# The figure drawn, as a client draws a third-person survivor, then a death on the last life.
	var view := ZzWorldView.new()
	view.ragdoll_rules = game.ragdoll_rules
	view.ragdoll_mask = game.world_mask()
	game.add_child(view)
	var _shown := me.present_body(false, me.feet(), Color(0.3, 0.5, 0.9))
	me.incaps = game.config.max_incaps
	var hit := DotDamage.make(claw, me.entity_id, me.health.health * 50.0 + 500.0, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied: Variant = game.combat.apply_damage(hit)
	await _sim(game, 0.05)
	var death := me.death
	_check(not me.is_alive() and death != null and death.reaction == &"crumple",
		"the server picked the fall, from the owner's weights", str(death.describe()) if death != null else "none")
	_check(death != null and death.direction.dot(Vector3(0, 0, 1)) > 0.5,
		"pushed away from the zombie that did it", str(death.direction) if death != null else "-")
	var _reset := game.ragdoll_rules.set_cvar("sv_ragdoll_reactions", "")

	# Laid down from the figure, in the zombies' yard.
	var body := view.drop_survivor(me.figure, death, Vector3.ZERO)
	_check(body != null and view.ragdolls.live().has(body) and view.ragdolls.rules == game.ragdoll_rules,
		"a client copies the body from the figure into the zombies' yard, under the game's rules")
	for i in 90:
		await get_tree().physics_frame
	var down := body != null and is_instance_valid(body)
	_check(down and body.centre().y < STREET.y + 0.8 and body.lowest_point() > STREET.y - 0.25,
		"a second and a half on, it lies on the street: not standing, not through it",
		str(body.describe()) if down else "gone")

	# The fall rides DEATH last and optional, so a death from an older server still reads.
	var fall := DotPlayerDeath.new()
	fall.reaction = &"face_plant"
	fall.roll_seed = 1234
	fall.direction = Vector3(1, 0, 0)
	var died := ZzEvents.read_death(DotNetReader.new(ZzEvents.write_death(5, 6, ZzGame.BY_ZOMBIE, &"common", fall)))
	var carried: DotPlayerDeath = died.get("death")
	var bare := ZzEvents.read_death(DotNetReader.new(ZzEvents.write_death(5, 6, ZzGame.BY_ZOMBIE, &"common")))
	_check(bool(died["ok"]) and carried != null and carried.reaction == &"face_plant" and carried.roll_seed == 1234
		and died["by_kind"] == &"common" and bool(bare["ok"]) and not bare.has("death"),
		"a DEATH carries the fall the server picked, and one without a fall still reads")

	var catalogue: DotAudioCatalogue = (load("res://game/zz_audio.gd") as GDScript).call("sound_catalogue")
	var listed := not DotPlayerDeathSounds.rows().is_empty()
	for row: Dictionary in DotPlayerDeathSounds.rows():
		listed = listed and catalogue.find(row["id"]) != null
	_check(listed, "the death sounds are in the game's catalogue")
	view.queue_free()
	_finished()


## The view, without a renderer: every kind builds an animated model, commons differ, states
## pick the right clips, and a death plays the death clip.
func _test_what_zombies_look_like() -> void:
	_section("every zombie is an animated model, and a crowd is not one person")
	var kinds := [ZzNpcs.COMMON, ZzNpcs.LEAPER, ZzNpcs.STRANGLER, ZzNpcs.BLOATER, ZzNpcs.RAM, ZzNpcs.SPITTER,
		ZzNpcs.RIDER, ZzNpcs.BRUTE, ZzNpcs.SLEEPER, ZzNpcs.SCREAMER, ZzNpcs.CRAWLER, ZzNpcs.RIOT]
	var animated := 0
	var outlines := {}
	var root := Node3D.new()
	add_child(root)

	for kind: StringName in kinds:
		var view := ZzZombieView.new()
		root.add_child(view)
		view.build(kind, 77)
		var player := view.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var clips := ["idle", "walk", "attack", "hit", "death"].filter(func(c: String) -> bool:
			return player != null and player.has_animation("zz/" + c))
		if clips.size() == 5:
			animated += 1
		var look := ZzZombieView.look_for(kind, 77)
		outlines["%s|%.2f|%.2f|%s" % [look["body"], float(look["height"]), float(look["girth"]), str(look.get("bones", {}).keys())]] = true

	_check(animated == kinds.size(), "every kind has idle, walk, attack, hit and death", "%d of %d" % [animated, kinds.size()])
	_check(outlines.size() == kinds.size(), "and every kind has its own outline", "%d distinct" % outlines.size())

	var bodies := {}
	var looks := {}
	for v in 40:
		var look := ZzZombieView.look_for(ZzNpcs.COMMON, (v * 7919 + 13) & 0xFFFF)
		bodies[look["body"]] = true
		looks["%s|%s|%s" % [look["body"], look["skin"], look["top"]]] = true
	_check(bodies.size() >= 5 and looks.size() >= 30, "forty commons: five bodies, and hardly two dressed alike",
		"%d bodies, %d looks" % [bodies.size(), looks.size()])

	var common := ZzZombieView.new()
	root.add_child(common)
	common.build(ZzNpcs.COMMON, 5)
	var crawler := ZzZombieView.new()
	root.add_child(crawler)
	crawler.build(ZzNpcs.CRAWLER, 5)
	var picked := []
	for state in [ZzZombieBody.Anim.WALK, ZzZombieBody.Anim.RUN, ZzZombieBody.Anim.ATTACK, ZzZombieBody.Anim.STAGGER]:
		common.present(0.05, state, 0)
		picked.append(String(common.clip()))
	crawler.present(0.05, ZzZombieBody.Anim.RUN, 0)
	_check(picked == ["walk", "run_arms", "attack", "hit"], "a state picks its clip", ", ".join(picked))
	_check(crawler.clip() == &"crawl", "and a crawler crawls whatever it is doing", String(crawler.clip()))
	common.die(&"headshot_launch", Vector3(0, 0, -1.5), 3)
	for i in 30:
		common.present(1.0 / 30.0, ZzZombieBody.Anim.DEAD, 0)
	_check(common.clip() == &"death" and common.position.z < -0.5, "a headshot throws it back as it dies",
		"%s, %.2f m" % [common.clip(), -common.position.z])
	root.free()
	_finished()


func _test_hazards() -> void:
	_section("acid, fire and a beeping charge")
	var game := await _team(1, func(c: ZzConfig) -> void: c.wanderer_density = 0.0)
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)
	var _pool := game.hazards.add(ZzHazards.ACID, STREET, 3.0, 6.0, 6.0, 0)
	var first := me.health.health
	await _sim(game, 1.0)
	var after_one := first - me.health.health
	await _sim(game, 1.5)
	var after_two := first - me.health.health - after_one
	_check(after_one > 0.0 and after_two > after_one, "acid hurts more the longer you stand in it", "%.0f then %.0f" % [after_one, after_two])

	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -20), &"test")
	var _fire := game.hazards.add(ZzHazards.FIRE, npc.position(), 3.0, 5.0, 8.0, 0)
	await _sim(game, 0.5)
	_check((npc.node as ZzZombieBody).has_flag(ZzZombieBody.FLAG_BURNING) or not npc.is_alive(), "fire sets a zombie alight")

	me.place_at(STREET + Vector3(0, 0, 40), 0.0)
	var crowd: Array[DotNpcInstance] = []
	for i in 4:
		crowd.append(game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(-6 + i, 0, -18), &"test"))
	var _pipe := game.hazards.launch(ZzHazards.PIPE, STREET + Vector3(0, 0.5, -10), Vector3(0, 1, 0), me.entity_id, 400.0)
	await _sim(game, 3.0)
	var lured := crowd.filter(func(n: DotNpcInstance) -> bool:
		return n.is_alive() and n.position().distance_to(STREET + Vector3(0, 0, -10)) < 4.0).size()
	_check(lured >= 3, "commons go to a beeping charge", "%d of 4" % lured)
	await _sim(game, 4.0)
	var alive := crowd.filter(func(n: DotNpcInstance) -> bool: return n.is_alive()).size()
	_check(alive == 0, "and it goes off among them", "%d left" % alive)
	_finished()


func _test_loot() -> void:
	_section("what lies on the ground")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	var shotgun := game.loot.add(ZzLoot.WEAPON, &"shotgun", STREET + Vector3(0, 0, -1.5))
	me.place_at(STREET, 0.0)
	_aim(me, STREET + Vector3(0, 0.25, -1.5))
	me.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.1)
	me.actions = 0
	# Long enough for the pistol to go away and the shotgun to come out.
	await _sim(game, 1.0)
	_check(not game.loot.exists(shotgun) and me.weapons.arsenal.carries(&"shotgun") and me.weapons.current_def().id == &"shotgun",
		"a gun looked at and E'd is picked up and drawn", "%s, holding %s" % [
			"taken" if not game.loot.exists(shotgun) else "still there", str(me.weapons.current_def().id)])

	var pile := game.loot.add(ZzLoot.AMMO, &"", STREET + Vector3(0, 0, -1.5))
	var pool := ZzWeapons.def_of(&"shotgun").ammo_type
	var _spent := me.weapons.arsenal.ammo().take(pool, 1000)
	await _sim(game, 0.05)
	me.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.1)
	me.actions = 0
	_check(me.weapons.arsenal.ammo().count(pool) > 0 and game.loot.exists(pile), "an ammo pile fills you and stays for the next person")

	me.medkits = 1
	var kit := game.loot.add(ZzLoot.MEDKIT, &"", STREET + Vector3(0, 0, -1.5))
	await _sim(game, 0.05)
	me.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.1)
	me.actions = 0
	_check(game.loot.exists(kit), "a second medkit is refused while you carry one")
	_finished()


## Both weapon packs are carried, and everything a weapon puts into the world does something.
## Until `_throw` existed every grenade and rocket in the game cost ammunition and did nothing.
func _test_both_packs() -> void:
	_section("both weapon packs, and what they throw")
	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.health.invulnerable = true
	me.place_at(STREET, 0.0)
	_check(ZzWeapons.exists(&"pistol") and ZzWeapons.exists(&"pump_shotgun") and ZzWeapons.ids_of(&"thrown").has(&"molotov")
		and ZzWeapons.ids_of(&"thrown").has(&"frag"), "zee's weapons and the second pack's are both handed out")

	var ahead := STREET + Vector3(0.0, 0.0, -8.0)
	var fires_before := game.hazards.areas.size()
	game._throw(me, _spawn(&"molotov", me, ahead))
	await _sim(game, 1.5)
	var fire := false
	for a: Dictionary in game.hazards.areas.values():
		fire = fire or (a["kind"] == ZzHazards.FIRE and (a["at"] as Vector3).distance_to(ahead) < 4.0)
	_check(game.hazards.areas.size() > fires_before and fire, "a molotov starts a fire where it lands")

	var crowd: Array[DotNpcInstance] = []
	for i in 4:
		crowd.append(game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(-3.0 + i * 2.0, 0.0, -22.0), &"test"))
	game._throw(me, _spawn(&"pipe_bomb", me, ahead))
	await _sim(game, 3.0)
	var drawn := crowd.filter(func(n: DotNpcInstance) -> bool: return n.is_alive() and n.position().distance_to(ahead) < 9.0).size()
	_check(drawn >= 2, "a pipe bomb draws the commons to it", "%d of 4 within 9 m" % drawn)
	await _sim(game, 5.0)
	var left := crowd.filter(func(n: DotNpcInstance) -> bool: return n.is_alive()).size()
	_check(left < 4, "and goes off among them", "%d of 4 standing" % left)

	var frag := game.horde.spawner.spawn(ZzNpcs.COMMON, ahead, &"test")
	(frag.brain as Object).set(&"idle_kind", 0)
	var thrown := _spawn(&"frag", me, ahead)
	thrown.fuse_ticks = TICK_RATE * 2
	thrown.splash_radius = 5.0
	thrown.splash_damage = 200.0
	game._throw(me, thrown)
	await _sim(game, 3.0)
	_check(not frag.is_alive(), "zee's frag goes off on its fuse")

	var target := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0.0, 0.0, -12.0), &"test")
	await _sim(game, 0.1)
	var rocket := DotWeaponSpawn.make(&"rocket_launcher", me.eye_position(), (target.position() + Vector3(0, 1.0, 0) - me.eye_position()).normalized() * 36.0, me.entity_id)
	rocket.splash_radius = 6.5
	rocket.splash_damage = 240.0
	rocket.gravity_scale = 0.0
	game._throw(me, rocket)
	await _sim(game, 1.0)
	_check(not target.is_alive(), "a rocket goes off on the zombie it meets")

	var burner := game.horde.spawner.spawn(ZzNpcs.BRUTE, STREET + Vector3(0.0, 0.0, -5.0), &"test")
	await _sim(game, 0.1)
	var flame := DotShot.make(&"flamethrower", me.entity_id, game.current_tick(), 0)
	flame.origin = me.eye_position()
	flame.direction = (burner.position() + Vector3(0, 1.2, 0) - flame.origin).normalized()
	flame.damage = 5.0
	flame.damage_type = game.combat.damage_type(&"strike")
	flame.max_range = 9.0
	flame.scatter()
	var _burnt := game.combat.resolve_shot(flame)
	_check(game.hazards._burning.has(burner.instance_id), "the flamethrower sets what it hits alight")
	_finished()


func _spawn(id: StringName, from: ZzPlayer, at: Vector3) -> DotWeaponSpawn:
	var origin := from.eye_position()
	var flat := Vector3(at.x - origin.x, 0.0, at.z - origin.z)
	# A lob that lands at [param at]: up at 45 degrees, at the speed that range needs.
	var speed := sqrt(flat.length() * ZzHazards.GRAVITY)
	var velocity := flat.normalized() * speed * 0.707 + Vector3.UP * speed * 0.707
	var spawn := DotWeaponSpawn.make(id, origin, velocity, from.entity_id)
	spawn.gravity_scale = 1.0
	spawn.fuse_ticks = TICK_RATE * 10
	return spawn


## Every outcome in the shipped box file, run once against a live map: none of them may error.
func _test_every_box_outcome() -> void:
	_section("every box outcome runs")
	var game := await _team(4)
	game.survivors()[0].place_at(STREET, 0.0)
	await _sim(game, 0.5)
	var ran := 0
	var before_errors := _failed

	for id in game.boxes.order:
		for outcome: Dictionary in (game.boxes.types[id] as Dictionary)["outcomes"]:
			var opener := game.survivors()[0]
			if not opener.is_alive():
				var _back := game.rescue(opener)
			game.boxes.run(outcome["actions"], {"opener": opener, "at": opener.feet(), "box": id})
			await _sim(game, 0.05)
			ran += 1

	await _sim(game, 3.0)
	_check(ran >= 70 and _failed == before_errors, "every outcome of every box ran", "%d" % ran)
	_check(game.horde.count() > 0, "and the horde they summoned is out there", "%d zombies" % game.horde.count())
	_finished()


## The Turret Box: opened where a survivor looks, a sentry stands on the floor and shoots the horde on
## its own (the server's decision, dot-combat's DotSentry), wears out, is limited per survivor, and a
## spot with no floor gives the box back.
func _test_turret_box() -> void:
	_section("the turret box: deployed, shoots zombies, wears out, limited, refused with no floor")
	var file := ZzBoxes.new(null)
	var loaded := file.load_text(FileAccess.get_file_as_string("res://boxes/boxes.json"))
	_check(loaded.ok and file.types.has(&"turret") and str(file.types[&"turret"]["outcomes"][0]["actions"][0]["do"]) == "turret",
		"the box is in the file and its one outcome deploys a turret")

	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.health.invulnerable = true
	me.place_at(STREET, 0.0)
	await _sim(game, 0.3)
	var seen: Array = []
	game.turrets.placed.connect(func(id: int, _at: Vector3, _yaw: float, _s: float) -> void: seen.append(id))

	var _carried := game.boxes.carry(me, &"turret")
	game.boxes.deploy(me)
	_check(game.turrets.turrets.size() == 1 and seen.size() == 1, "opening the box stands one turret up", str(game.turrets.turrets.size()))
	var sentry: DotSentry = (game.turrets.turrets.values()[0] as Dictionary)["sentry"]
	_check(absf(sentry.position.y) < 0.3 and sentry.position.distance_to(me.feet()) < 3.0 and sentry.position.z < me.feet().z,
		"on the floor, in front of the survivor", str(sentry.position))

	# It shoots on its own: a common walks into its reach and falls without anybody firing.
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, sentry.position + Vector3(0.0, 0.0, -9.0), &"test")
	await _sim(game, 3.0)
	_check(not npc.is_alive() or npc.health < npc.def.max_health, "it hurts a zombie in its reach by itself",
		"%d shots" % sentry.shots)
	_check(sentry.shots > 0 and sentry.ammo < 240, "and it spends ammunition doing it", str(sentry.ammo))

	# At most two per survivor: a third takes the oldest down.
	var first_id: int = game.turrets.turrets.keys()[0]
	game.boxes.run([{"do": "turret"}], {"opener": me, "at": me.feet(), "box": &"turret"})
	game.boxes.run([{"do": "turret"}], {"opener": me, "at": me.feet(), "box": &"turret"})
	_check(game.turrets.count_for(me.entity_id) == 2 and not game.turrets.turrets.has(first_id),
		"a survivor has at most two, the oldest goes", str(game.turrets.turrets.keys()))

	# It wears out.
	for id: int in game.turrets.turrets:
		((game.turrets.turrets[id] as Dictionary)["sentry"] as DotSentry).lifetime = 0.5
	await _sim(game, 1.2)
	_check(game.turrets.turrets.is_empty(), "when its time is up it is taken down")

	# No floor: refused, and the box is not spent.
	me.carried.clear()
	me.place_at(STREET + Vector3(0.0, 40.0, 0.0), 0.0)
	game.boxes.open(&"turret", me, me.feet())
	_check(game.turrets.turrets.is_empty() and me.carried == [&"turret"], "with no floor there is no turret, and the box comes back",
		str(me.carried))
	_finished()


func _test_effects_stack() -> void:
	_section("box effects stack and wear off")
	var game := await _team(1)
	var ctx := {"opener": game.survivors()[0], "at": STREET, "box": &"horde"}
	game.boxes.run([{"do": "pace", "what": "mob_rate", "scale": 2.0, "seconds": 2.0}], ctx)
	game.boxes.run([{"do": "pace", "what": "mob_rate", "scale": 2.0, "seconds": 4.0}], ctx)
	_check(is_equal_approx(game.horde.mob_rate_scale, 4.0), "two doublings are four times", "x%.1f" % game.horde.mob_rate_scale)
	var summary := game.boxes.effects_summary()
	_check(summary.size() == 1 and int(summary[0]["stacks"]) == 2, "and the HUD is told one line, two stacks")
	await _sim(game, 2.5)
	_check(is_equal_approx(game.horde.mob_rate_scale, 2.0), "one wears off", "x%.1f" % game.horde.mob_rate_scale)
	await _sim(game, 2.0)
	_check(is_equal_approx(game.horde.mob_rate_scale, 1.0), "then the other")

	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -8), &"test")
	npc.brain.call(&"force_target", game.survivors()[0].player_id)
	game.survivors()[0].place_at(STREET, 0.0)
	game.boxes.run([{"do": "freeze_zombies", "seconds": 2.0}], ctx)
	var at := npc.position()
	await _sim(game, 1.0)
	_check(npc.position().distance_to(at) < 0.2, "a freeze holds a running zombie still")
	_finished()


## The box framework: carried and deployed, the schema, a named effect's clock and stacks, the end
## of the round, and Instakill as the template the next boxes copy.
func _test_box_framework() -> void:
	_section("boxes are carried, deployed, timed, stacked and ended with the round")
	var file := ZzBoxes.new(null)
	var loaded := file.load_text(FileAccess.get_file_as_string("res://boxes/boxes.json"))
	var kill: Dictionary = file.types.get(&"instakill", {})
	_check(loaded.ok and not kill.is_empty() and kill["polarity"] == "positive" and kill["impact"] == "game"
		and not bool(kill["stacks"]) and kill["duration"]["mode"] == "seconds", "the schema reads, and Instakill is in the file")
	var broken: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://boxes/boxes.json"))
	(broken["boxes"] as Array)[0]["impact"] = "sideways"
	_check(not ZzBoxes.new(null).load_text(JSON.stringify(broken)).ok, "a bad impact refuses the file")

	var game := await _team(1, _quiet)
	var me := game.survivors()[0]
	me.health.invulnerable = true
	me.place_at(STREET, 0.0)
	var seen: Array = []
	game.boxes.opened.connect(func(_id: StringName, type_id: StringName, _t: String, _m: String) -> void: seen.append(type_id))

	# Carry: E picks it up, a second finds the hands full.
	var first := game.loot.add(ZzLoot.BOX, &"medical", STREET + Vector3(0, 0, -1.2))
	_aim(me, STREET + Vector3(0, 0.3, -1.2))
	me.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.2)
	me.actions = 0
	await _sim(game, 0.1)
	_check(me.carried == [&"medical"] and not game.loot.exists(first) and me.carried_count == 1 and me.carried_index == 0,
		"E puts a box in the hands, and the slot is told only that it is one (box_labels is off)", str(me.carried))
	var second := game.loot.add(ZzLoot.BOX, &"horde", STREET + Vector3(0, 0, -1.2))
	me.actions = ZzNetCommand.ACT_USE
	await _sim(game, 0.2)
	me.actions = 0
	_check(game.loot.exists(second) and me.carried.size() == 1, "a second box stays on the ground when the hands are full")
	game.loot.remove(second)

	# Deploy: nothing until the time is up, and the meter climbs.
	var deploy := game.config.box_deploy_seconds
	me.actions = ZzNetCommand.ACT_DEPLOY
	await _sim(game, deploy * 0.5)
	_check(me.using == &"deploy" and absf(me.use_fraction - 0.5) < 0.1 and seen.is_empty(),
		"holding the key fills a meter and opens nothing early", "%.2f" % me.use_fraction)
	await _sim(game, deploy * 0.6)
	me.actions = 0
	_check(seen == [&"medical"] and me.carried.is_empty() and me.using == &"", "after box_deploy_seconds it opens", str(seen))

	# Cancel by letting go.
	var _c1 := game.boxes.carry(me, &"medical")
	me.actions = ZzNetCommand.ACT_DEPLOY
	await _sim(game, deploy * 0.4)
	me.actions = 0
	await _sim(game, deploy * 2.0)
	_check(me.using == &"" and me.carried.size() == 1 and seen.size() == 1, "letting go cancels it, and the box is kept")

	# Cancel by walking off.
	me.actions = ZzNetCommand.ACT_DEPLOY
	await _sim(game, deploy * 0.4)
	me.place_at(STREET + Vector3(0, 0, -3.0), 0.0)
	await _sim(game, 0.3)
	_check(me.using == &"" and me.carried.size() == 1, "moving out of the radius cancels it")
	me.actions = 0
	me.place_at(STREET, 0.0)
	await _sim(game, 0.2)

	# Cancel by a down, which drops the box where they fall.
	me.actions = ZzNetCommand.ACT_DEPLOY
	await _sim(game, deploy * 0.4)
	var lying := game.loot.count_of(ZzLoot.BOX)
	game._go_down(me, &"", &"test")
	await _sim(game, 0.2)
	me.actions = 0
	_check(me.using == &"" and me.carried.is_empty() and game.loot.count_of(ZzLoot.BOX) == lying + 1,
		"a down cancels it and drops what they carried")
	game.stand_up(me)

	# Named effects: duration, a non-stacking repeat, a stacking cap, the round's end, the opt-out.
	game.config.box_instakill_min = 2.0
	game.config.box_instakill_max = 2.0
	var ctx := {"opener": me, "at": STREET, "box": &"instakill"}
	game.boxes.run([{"do": "effect", "name": "instakill"}], ctx)
	game.boxes.run([{"do": "effect", "name": "instakill"}], ctx)
	var rows := game.boxes.effects_summary()
	_check(game.boxes.is_active(&"instakill") and rows.size() == 1 and int(rows[0]["stacks"]) == 1,
		"Instakill is on, a second one only lengthens it", str(rows))

	var common := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -6), &"test")
	await _sim(game, 0.1)
	var _one := _shot(game, me, common.position() + Vector3(0, 1.0, 0), 1.0)
	await _sim(game, 0.1)
	_check(not common.is_alive(), "while it lasts a common dies to a hit that would not scratch it")
	var spit := game.horde.spawner.spawn(ZzNpcs.SPITTER, STREET + Vector3(0, 0, -6), &"test")
	_check(is_equal_approx(game.boxes.zombie_damage(ZzNpcs.SPITTER, spit.def.max_health, 10.0), 10.0 * game.config.box_instakill_special_scale)
		and game.boxes.zombie_damage(ZzNpcs.COMMON, 50.0, 1.0) > 50.0, "a special takes the configured multiple, a common everything")
	await _sim(game, 2.4)
	_check(not game.boxes.is_active(&"instakill") and is_equal_approx(game.boxes.zombie_damage(ZzNpcs.COMMON, 50.0, 1.0), 1.0),
		"and it wears off when the time is up")

	game.boxes.types[&"t_stack"] = {"id": &"t_stack", "title": "Test", "impact": "game", "polarity": "negative", "radius": 0.0,
		"stacks": true, "max_stacks": 3, "survives_round": false, "params": {}, "duration": {"mode": "seconds", "min": 30.0, "max": 30.0}}
	game.boxes.register_handler(&"t_stack", load("res://game/zz_box_effect.gd"))
	for _i in 5:
		var _fx := game.boxes.activate(&"t_stack", &"t_stack", ctx)
	_check(int(game.boxes.effects_summary()[0]["stacks"]) == 3, "a stacking effect counts up to max_stacks and no further")
	game.boxes.types[&"t_keep"] = (game.boxes.types[&"t_stack"] as Dictionary).duplicate()
	game.boxes.types[&"t_keep"]["survives_round"] = true
	game.boxes.register_handler(&"t_keep", load("res://game/zz_box_effect.gd"))
	var _k := game.boxes.activate(&"t_keep", &"t_keep", ctx)
	game.boxes.types[&"t_round"] = (game.boxes.types[&"t_stack"] as Dictionary).duplicate()
	game.boxes.types[&"t_round"]["duration"] = {"mode": "round", "min": 0.0, "max": 0.0}
	game.boxes.types[&"t_round"]["survives_round"] = true
	game.boxes.register_handler(&"t_round", load("res://game/zz_box_effect.gd"))
	var _r := game.boxes.activate(&"t_round", &"t_round", ctx)
	game.boxes.run([{"do": "pace", "what": "mob_rate", "scale": 2.0, "seconds": 60.0}], ctx)
	# Counted, not indexed: effects_summary() comes from a Dictionary's values, whose order is not a promise.
	var summary := game.boxes.effects_summary()
	var unclocked := summary.filter(func(g: Dictionary) -> bool: return float(g["seconds"]) < 0.0).size()
	_check(summary.size() == 4 and unclocked == 1, "a round-long effect reports no clock, and only it")
	game.boxes.end_round()
	_check(not game.boxes.is_active(&"t_stack") and not game.boxes.is_active(&"t_round") and game.boxes.is_active(&"t_keep")
		and is_equal_approx(game.horde.mob_rate_scale, 1.0),
		"the round's end ends the game-wide effects, but not one that opted out (a round-long one always goes)")
	_finished()


## Metres a survivor goes in [param seconds] pressing forward (yaw 0, so toward -Z) from [param from].
func _walk(game: ZzGame, player: ZzPlayer, from: Vector3, seconds: float) -> float:
	player.place_at(from, 0.0)
	player.controller.state.velocity = Vector3.ZERO
	var forward := DotFpsCommand.new()
	forward.move = Vector2(0.0, 1.0)
	player.controller.apply_command(forward)
	await _sim(game, seconds)
	var gone := player.feet().distance_to(from)
	var stop := DotFpsCommand.new()
	player.controller.apply_command(stop)
	await _sim(game, 0.3)
	return gone


func _test_crawling_and_speed_boxes() -> void:
	_section("a downed survivor crawls at the server's pace, and the speed boxes")
	var game := await _team(2, _quiet)
	var me := game.survivors()[0]
	game.survivors()[1].health.invulnerable = true
	me.place_at(STREET, 0.0)
	var start := STREET + Vector3(0, 0, 4.0)
	var run_gone: float = await _walk(game, me, start, 1.0)

	_hurt(game, me, 500.0)
	_check(me.is_down(), "down")
	var crawled: float = await _walk(game, me, start, 1.5)
	var pace := game.crawl_rules.speed
	_check(crawled > pace * 0.8 and crawled < pace * 1.5 + 0.3, "a downed survivor crawls at zz_down_crawl_speed",
		"%.2f m in 1.5 s at %.1f m/s" % [crawled, pace])
	_check(me.controller.has_modifier(ZzController.DOWN) and not me.controller.motor.modifier_defs[ZzController.DOWN].deny_move,
		"as the DOWN modifier's speed scale, so a client predicts it")

	game.crawl_rules.set_cvar("0")
	var still: float = await _walk(game, me, start, 1.5)
	_check(still < 0.15 and me.controller.motor.modifier_defs[ZzController.DOWN].deny_move, "at 0 they stay where they fell", "%.2f m" % still)
	game.crawl_rules.set_cvar("3.0")
	var fast: float = await _walk(game, me, start, 1.5)
	_check(fast > crawled * 1.6, "and the cvar changes the live pace", "%.2f m against %.2f" % [fast, crawled])
	_check(not game.crawl_rules.set_cvar("fast") and not game.crawl_rules.set_cvar("") and is_equal_approx(game.crawl_rules.speed, 3.0)
		and game.crawl_rules.set_cvar("99") and is_equal_approx(game.crawl_rules.speed, ZzCrawlRules.MAX_SPEED),
		"junk is refused and a huge value is clamped")
	game.crawl_rules.set_cvar("1.4")

	# The boxes: in the file, four ways of being faster.
	var file := ZzBoxes.new(null)
	var loaded := file.load_text(FileAccess.get_file_as_string("res://boxes/boxes.json"))
	var wanted := {&"swift": ["seconds", true], &"marathon": ["round", false], &"lifeline": ["seconds", true], &"long_crawl": ["round", false]}
	var in_file := loaded.ok

	for id: StringName in wanted:
		var box: Dictionary = file.types.get(id, {})
		in_file = in_file and not box.is_empty() and box["duration"]["mode"] == wanted[id][0] \
			and bool(box["survives_round"]) == wanted[id][1] and box["polarity"] == "positive" and not bool(box["stacks"])

	_check(in_file, "swift, marathon, lifeline and long crawl are in boxes.json: seconds or the round, survives_round as documented")

	game.stand_up(me)
	# Revived limping is a slower walk of its own; this measures the box against a healthy run.
	me.health.health = game.config.max_health
	me.temp_health = 0.0
	await _sim(game, 0.2)
	var ctx := {"opener": me, "at": STREET, "box": &"swift"}
	game.boxes.types[&"swift"]["duration"] = {"mode": "seconds", "min": 2.0, "max": 2.0}
	game.boxes.run([{"do": "effect", "name": "move_speed"}], ctx)
	_check(me.controller.has_modifier(ZzController.MOVE_BOOST) and game.boxes.is_active(&"move_speed"), "Swift gives every survivor the move modifier")
	var quick: float = await _walk(game, me, start, 1.0)
	_check(quick > run_gone * 1.15, "and they cover more ground", "%.2f m against %.2f" % [quick, run_gone])
	game.boxes.run([{"do": "effect", "name": "move_speed"}], ctx)
	var rows := game.boxes.effects_summary().filter(func(g: Dictionary) -> bool: return g["title"] == "Swift Box")
	_check(rows.size() == 1 and int(rows[0]["stacks"]) == 1, "a second one only lengthens it, as the file says")
	await _sim(game, 2.6)
	_check(not me.controller.has_modifier(ZzController.MOVE_BOOST) and not game.boxes.is_active(&"move_speed"), "and it wears off when its seconds are up")

	# The whole round: gone at the round's end whatever survives_round says; seconds survive it.
	game.boxes.types[&"marathon"]["duration"] = {"mode": "round", "min": 0.0, "max": 0.0}
	game.boxes.run([{"do": "effect", "name": "move_speed"}], {"opener": me, "at": STREET, "box": &"marathon"})
	game.boxes.end_round()
	_check(not me.controller.has_modifier(ZzController.MOVE_BOOST), "Marathon lasts the round and not past it")
	game.boxes.types[&"swift"]["duration"] = {"mode": "seconds", "min": 30.0, "max": 30.0}
	game.boxes.run([{"do": "effect", "name": "move_speed"}], ctx)
	game.boxes.end_round()
	_check(me.controller.has_modifier(ZzController.MOVE_BOOST), "a Swift (survives_round) outlasts a wave", "")
	game.boxes.reset()
	_check(not me.controller.has_modifier(ZzController.MOVE_BOOST), "and a new map clears it")

	# Crawl speed: felt only while down, and no box is dropped where nobody can crawl.
	var crawl_ctx := {"opener": me, "at": STREET, "box": &"lifeline"}
	game.boxes.types[&"lifeline"]["duration"] = {"mode": "seconds", "min": 30.0, "max": 30.0}
	game.boxes.run([{"do": "effect", "name": "crawl_speed"}], crawl_ctx)
	_hurt(game, me, 500.0)
	var boosted: float = await _walk(game, me, start, 1.5)
	_check(me.is_down() and me.controller.has_modifier(ZzController.CRAWL_BOOST) and boosted > crawled * 1.4,
		"Lifeline: a survivor who goes down after it was opened crawls faster", "%.2f m against %.2f" % [boosted, crawled])
	game.boxes.reset()
	game.crawl_rules.set_cvar("0")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dud := false
	var seen_swift := false

	for _i in 400:
		var drawn := game.boxes.random_type(&"brute", rng)
		dud = dud or drawn == &"lifeline" or drawn == &"long_crawl"
		seen_swift = seen_swift or drawn == &"swift"

	_check(not dud and seen_swift, "with crawling off a crawl box is never dropped, and the others still are")
	game.crawl_rules.set_cvar("1.4")
	_finished()


func _test_water() -> void:
	_section("water: wading, swimming, drowning, the zombies' pace, the cvars")
	var doc := ZzCatalogue.practice()
	doc["water"] = [{"at": [0, 0, 14], "size": [8, 1, 8]}]
	var parsed := ZzMapDoc.validate(doc)
	_check(parsed.ok and (parsed.value["water"] as Array).size() == 1, "a map document carries water volumes")
	doc["water"] = [{"at": [0, 0, 14], "size": [8, 0, 8]}]
	_check(not ZzMapDoc.validate(doc).ok, "and a volume with no depth is refused")

	var game := await _team(2, _quiet)
	var me := game.survivors()[0]
	game.survivors()[1].health.invulnerable = true
	var start := STREET + Vector3(0, 0, 2.0)
	var none: Array[AABB] = []
	var dry: float = await _walk(game, me, start, 1.0)

	# Knee deep: the feet wet, the waist not. Source-like, a wade is slower than a walk.
	var shallow: Array[AABB] = [AABB(Vector3(-6, -1, 8), Vector3(12, 1.4, 20))]
	game.map.water_boxes = shallow
	game._push_water()
	var wet: float = await _walk(game, me, start, 1.0)
	_check(me.water_level == ZzPlayer.WaterLevel.FEET and wet < dry * 0.95 and wet > dry * 0.5,
		"wading slows a survivor", "%.2f m against %.2f dry" % [wet, dry])
	_check(me.controller.has_modifier(ZzController.WADING), "as a modifier, so a client predicts it")
	_check(game.water_pace_at(start) == game.water_rules.zombie_wade, "and slows a zombie in it", "%.2f" % game.water_pace_at(start))

	# Deep: the waist in, then the eyes. Swimming is the mode.
	var deep: Array[AABB] = [AABB(Vector3(-6, -3, 8), Vector3(12, 5.5, 20))]
	game.map.water_boxes = deep
	game._push_water()
	me.place_at(start, 0.0)
	await _sim(game, 0.5)
	_check(me.controller.state.mode == me.swim.mode_id and me.water_level >= ZzPlayer.WaterLevel.WAIST,
		"deep water is swum in, the waist under", str(me.water_level))
	await _sim(game, 1.5)
	_check(not me.submerged and is_equal_approx(me.air, game.water_rules.drown_seconds), "a swimmer floats with the head out, and breathes")
	var dive := DotFpsCommand.new()
	dive.set_button(DotFpsCommand.BUTTON_CROUCH, true)
	me.controller.apply_command(dive)
	await _sim(game, 1.5)
	_check(me.submerged, "and a diver's eyes go under")
	_check(game.water_pace_at(start) == game.water_rules.zombie_deep, "and a zombie is slowest there")
	var life := me.health.health
	var air_before := me.air
	await _sim(game, 3.0)
	_check(me.air < air_before - 2.5 and is_equal_approx(me.health.health, life), "the breath runs out before the health does", "%.1f s of air" % me.air)
	await _sim(game, 10.0)
	_check(me.air <= 0.0 and me.health.health < life, "and then the water drowns", "%.0f of %.0f" % [me.health.health, life])

	game.map.water_boxes = none
	game._push_water()
	me.health.health = game.config.max_health
	await _sim(game, 5.0)
	_check(me.air >= game.water_rules.drown_seconds - 0.01 and not me.submerged and game.water_pace_at(start) == 1.0,
		"out of the water the air refills and the pace returns", "%.1f s" % me.air)

	var _off := game.water_rules.set_cvar("zz_water", "0")
	game.map.water_boxes = deep
	game._push_water()
	_check(game._water_boxes().is_empty(), "zz_water 0 turns it all off")
	var _on := game.water_rules.set_cvar("zz_water", "1")

	var added := {}
	var recorder := func(n: String, _v: String, _h: String, f: int) -> Object:
		added[n] = f
		return null
	var made := game.water_rules.bind_cvars(recorder, 4, 1)
	_check(made.is_empty() and added.size() == ZzWaterRules.VARS.size() and added["zz_water"] == 4 and added["zz_water_drown_seconds"] == 1,
		"every setting is a cvar, the ones a client predicts replicated", str(added.size()))
	_check(not game.water_rules.set_cvar("zz_water_swim_speed", "fast") and game.water_rules.set_cvar("zz_water_swim_speed", "99")
		and game.water_rules.swim_speed <= 12.0, "junk is refused and a huge speed clamped")
	_check(me.controller.motor.modifier_index(ZzController.WADING) >= 0 and me.controller.motor.modifier_defs.size() <= 32,
		"the wading modifier fits the motor's 32", str(me.controller.motor.modifier_defs.size()))
	_finished()


func _test_objectives() -> void:
	_section("the switch, the hold-out, and the gate")
	var game := await _team(1, func(c: ZzConfig) -> void: c.wanderer_density = 0.0)
	var me := game.survivors()[0]
	me.health.invulnerable = true
	me.place_at(SWITCH - Vector3(0, 0.95, -1.0), 180.0)
	await _sim(game, 0.5)
	_aim(me, SWITCH)
	me.actions = ZzNetCommand.ACT_USE
	await _sim(game, 2.5)
	me.actions = 0
	_check(game.objective_states[0] == &"holding" and game.horde.panicking(), "holding E on the switch starts the hold-out")
	_check(game.map.gate_is_shut("barrier"), "and the barrier is still down while it runs")
	game.objective_progress[0] = game.now() + 0.2
	await _sim(game, 0.5)
	_check(game.objective_states[0] == &"done" and not game.map.gate_is_shut("barrier"), "held out: the barrier opens")
	_check(not game.horde.spawner.nav.find_path(Vector3(0, 0, 30), Vector3(0, 0, 85), 2.0).is_empty(),
		"and the horde can come through it now")
	_finished()


func _test_winning_and_losing() -> void:
	_section("how a map is won and lost")
	var game := await _team(2, func(c: ZzConfig) -> void:
		c.end_hold_seconds = 0.5
		c.intermission_seconds = 0.5
		c.killcam_seconds = 0.0)
	for player in game.survivors():
		player.health.invulnerable = true
		player.place_at(END_ROOM, 0.0)
	await _sim(game, 1.0)
	_check(game._decided and game._won, "everybody standing in the end room wins it")

	game = await _team(2, func(c: ZzConfig) -> void: c.intermission_seconds = 0.5; c.killcam_seconds = 0.0)
	for player in game.survivors():
		player.place_at(STREET, 0.0)
	await _sim(game, 0.5)
	for player in game.survivors():
		_hurt(game, player, 500.0)
	await _sim(game, 2.5)
	_check(game._decided and not game._won, "nobody on their feet loses it")
	var number := game.round_number
	await _sim(game, 2.0)
	_check(game.round_number > number and game.map.id() == ZzCatalogue.PRACTICE, "and it is played again")

	# The practice street as a survival map: the same ground, held rather than crossed.
	game = await _world(func(c: ZzConfig) -> void:
		c.survival_style = 2
		c.survive_seconds = 3.0
		c.wanderer_density = 0.0
		c.intermission_seconds = 30.0
		c.map_ids = PackedStringArray())
	var doc := ZzCatalogue.practice().duplicate(true)
	doc["id"] = "zz_hold"
	doc["mode"] = ZzMapDoc.SURVIVAL
	doc["objectives"] = []
	var checked := ZzMapDoc.validate(doc)
	var _added := game.catalogue._add(checked.value, "test") if checked.ok else false
	game.next_map_id = &"zz_hold"
	var holder := game.add_player(&"u100", "Holder")
	game.start()
	await _sim(game, 0.5)
	holder.health.invulnerable = true
	holder.place_at(STREET, 0.0)
	await _sim(game, 5.0)
	_check(game.is_survival() and game._decided and game._won and game.survival_elapsed >= 3.0,
		"a survival map is held to its clock", "%s, %.1f s" % [game.map.id(), game.survival_elapsed])
	_finished()


func _test_stand_ins() -> void:
	_section("stand-ins play the map")
	var game := await _team(4, func(c: ZzConfig) -> void: c.start_grace_seconds = 2.0, true)
	for player in game.survivors():
		player.health.invulnerable = false

	# Measured over the FIRST ROUND, sampled every second, never as one snapshot at 60 s. Four
	# stand-ins can lose the street to the horde (a spitter's pool at the switch, a ram, a
	# crowd), and the round that starts after it resets every counter and puts them back in the
	# start room: a snapshot then read "0 kills, z 7" from a team that had killed thirty and
	# reached the switch. Losing is the game; what this checks is that they played it.
	var first_round := game.round_number
	var kills := 0
	var furthest := -INF
	var weapons_left := game.loot.count_of(ZzLoot.WEAPON)
	var played := 0.0
	var friendly := 0.0

	while played < 60.0:
		await _sim(game, 1.0)
		played += 1.0

		if game.round_number != first_round:
			break

		kills = 0
		friendly = 0.0
		for player in game.survivors():
			kills += player.commons_killed + player.specials_killed
			furthest = maxf(furthest, player.feet().z)
			friendly += player.friendly_damage
		weapons_left = game.loot.count_of(ZzLoot.WEAPON)

	var over := "" if played >= 60.0 else ", round over by %.0f s" % played
	_check(kills > 0, "they shoot what comes at them", "%d kills%s" % [kills, over])
	_check(furthest > 10.0, "and they leave the start room for the street", "z %.0f%s" % [furthest, over])
	_check(weapons_left < 3, "picking up what was left for them", "%d left" % weapons_left)
	# Survivors do not collide, so stand-ins stack up shoulder to shoulder or inside each other.
	# Before dot-combat's pass-through and the hitbox-based friend check, every shot from inside a friend hit
	# that friend: 200 to 500 points of friendly damage in this minute on six seeds out of six,
	# and half those first rounds lost. A stray pellet is allowed; shooting each other is not.
	_check(friendly < 100.0, "and they do not shoot each other down", "%.0f friendly damage" % friendly)
	_finished()


## The stand-ins' "friend in the line" check under the server's `mp_teammate_passthrough`.
## At 2 every shot passes through every survivor, so a stand-in that still held fire for a
## friend in front stood there doing nothing; at 0 a friend holding the muzzle is hit, so that
## one is in the way after all.
func _test_stand_ins_and_the_pass_through_level() -> void:
	_section("stand-ins hold fire for a friend only when the shot would hit them")
	var game := await _team(2, _quiet, true)
	var me := game.survivors()[0]
	var friend := game.survivors()[1]
	me.place_at(STREET, 0.0)
	friend.place_at(STREET + Vector3(0, 0, -3), 0.0)
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -9), &"test")
	(npc.brain as Object).set(&"idle_kind", 0)
	await _sim(game, 0.1)
	var aim := game.bots._aim_point(npc)
	# A stand-in that has been on this zombie for a minute, its view settled onto it.
	var reacted: Dictionary = game.bots._memory(me)
	var settled: DotBotAim = reacted["aim"]
	settled.forget()
	var _seen := settled.engage(npc.instance_id, me.eye_position(), aim, game.now() - 60.0)
	for _i in range(256):
		var _v := settled.track(me.eye_position(), aim, Vector3.ZERO, game.now(), 1.0 / 64.0)

	_check(game.combat.rules.pass_through_level() == 1, "the default level is 1")
	_check(game.bots._friend_in_the_way(me, aim) and not game.bots._fire_ok(me, reacted, npc),
		"at 1 a friend in the line holds a stand-in's fire")

	_check(game.combat.set_cvar(DotCombatManager.CVAR_TEAMMATE_PASSTHROUGH, "2"), "the server goes to 2")
	_check(not game.bots._friend_in_the_way(me, aim) and game.bots._fire_ok(me, reacted, npc),
		"at 2 the stand-in fires through the friend")
	var before := friend.health.health
	var shot := _shot(game, me, aim, 30.0)
	_check(shot.damages.size() == 1 and DotEntity.is_kind(shot.damages[0].victim, DotEntity.KIND_NPC),
		"and the shot goes through them to the zombie", str(shot.damages.map(func(d: DotDamage) -> int: return d.victim)))
	_check(friend.health.health == before, "leaving the friend unhurt")

	# A friend standing inside the stand-in: at 1 the shot passes through them, at 0 it does not.
	friend.place_at(STREET, 0.0)
	await _sim(game, 0.05)
	var _zero := game.combat.set_cvar(DotCombatManager.CVAR_TEAMMATE_PASSTHROUGH, "0")
	_check(game.bots._friend_in_the_way(me, aim), "at 0 a friend holding the muzzle holds a stand-in's fire")
	var _two := game.combat.set_cvar(DotCombatManager.CVAR_TEAMMATE_PASSTHROUGH, "2")
	_check(not game.bots._friend_in_the_way(me, aim), "and at 2 even that one does not")
	_finished()


func _test_a_crowd_is_cheap() -> void:
	_section("a crowd on a survivor fits in a tick")
	var game := await _team(1, func(c: ZzConfig) -> void: c.wanderer_density = 0.0)
	var me := game.survivors()[0]
	me.health.invulnerable = true
	me.place_at(STREET, 0.0)
	for i in 60:
		var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(randf_range(-7, 7), 0, randf_range(-26, -12)), &"test")
		if npc != null:
			npc.brain.call(&"force_target", me.player_id)
	await _sim(game, 4.0)
	var started := Time.get_ticks_usec()
	for i in 64:
		game.simulate(TICK)
	var per_tick := float(Time.get_ticks_usec() - started) / 64000.0
	var near := game.horde.spawner.npcs_near(me.feet(), 6.0).size()
	_check(near > 15, "sixty arrive", "%d within 6 m" % near)
	_check(per_tick < 12.0, "and a tick costs less than a 64 Hz tick has", "%.2f ms" % per_tick)
	_finished()


# --- Helpers -----------------------------------------------------------------------

## The family's rule since the first play test: H opens help in every game, nothing else in
## the table is on H, and the Escape menu has Help & commands and Leave.
func _test_help_and_menu() -> void:
	_section("H opens help, and the Escape menu has Help and Leave")
	var settings := ZzSettings.new()
	add_child(settings)
	var built := settings.setup(DotSettingsStoreMemory.new())
	var keys := settings.bindings
	_check(built.ok and keys != null and keys.key_for(DotMenuBindings.HELP_ACTION) == "H", "help is on H")
	_check(keys.defaults_on("H").size() == 1, "and nothing else in the table defaults to H (the medkit is on G)",
		str(keys.defaults_on("H").map(func(r: Dictionary) -> String: return str(r["label"]))))
	# The right mouse button aims down the sights (the family's Aim row); the shove kept F.
	_check(keys.key_for(ZzBindings.AIM) == "Mouse 2" and keys.defaults_on("Mouse 2").size() == 1
		and keys.key_for(ZzBindings.SHOVE) == "F", "aim is the only row on the right mouse button, the shove is on F",
		"%s %s %d" % [keys.key_for(ZzBindings.AIM), keys.key_for(ZzBindings.SHOVE), keys.defaults_on("Mouse 2").size()])
	# Chat is two rows, so help lists Y and U and the Controls page moves them.
	var _t := settings.settings.set_value(&"bind_chat", "T")
	_check(keys.key_for(ZzBindings.CHAT) == "T" and DotInputBinding.describe_action(ZzBindings.CHAT) == "T"
		and keys.key_for(ZzBindings.CHAT_TEAM) == "U", "chat (Y) and team chat (U) are rows: rebinding one moves its key",
		"%s %s" % [keys.key_for(ZzBindings.CHAT), keys.key_for(ZzBindings.CHAT_TEAM)])
	var h := InputEventKey.new()
	h.physical_keycode = KEY_H
	h.keycode = KEY_H
	h.pressed = true
	_check(settings.menu.handle_event(h) and settings.menu.help.is_open(), "H opens the help screen")
	_check(settings.menu.help.about != "" and settings.menu.help.heading() == "How to play Zombie Zone",
		"which says what the game is before the keys")
	settings.menu.help.close()
	settings.open()
	var help_button := settings.menu.screen.find_child("Action_help", true, false) as Button
	var leave_button := settings.menu.screen.find_child("Action_leave", true, false) as Button
	_check(help_button != null and leave_button != null and leave_button.visible,
		"the Escape menu has Help & commands and Leave")
	settings.close()
	settings.queue_free()
	await get_tree().process_frame

	# A document saved when the medkit was on H and the shove on V: they follow their new
	# defaults, help keeps H, and a key the player chose stays where they put it.
	var old_doc := DotSettingsStoreMemory.new()
	var _saved := old_doc.save_document(ZzSettings.APP_NAMESPACE, &"local", {"version": 1, "values": {
		"bind_heal": "H", "bind_help": "H", "bind_shove": "V", "bind_use": "J",
	}})
	var returning := ZzSettings.new()
	add_child(returning)
	var _r := returning.setup(old_doc, false)
	var rk: DotMenuBindings = returning.bindings
	_check(rk.key_for(ZzBindings.HEAL) == "G" and rk.key_for(DotMenuBindings.HELP_ACTION) == "H",
		"an old settings file with the medkit on H: the medkit moves to G, help keeps H",
		"%s %s" % [rk.key_for(ZzBindings.HEAL), rk.key_for(DotMenuBindings.HELP_ACTION)])
	_check(rk.key_for(ZzBindings.SHOVE) == "F" and rk.key_for(ZzBindings.USE) == "J",
		"the shove leaves V for push to talk, and a key the player chose is kept",
		"%s %s" % [rk.key_for(ZzBindings.SHOVE), rk.key_for(ZzBindings.USE)])
	returning.queue_free()
	await get_tree().process_frame
	_finished()


## The family's rule since the first play test: M opens the map list, and solo a choice
## changes it now. The server's half (the owner's flag, the vote) is in `dedicated` and dot-vote.
func _test_the_map_menu() -> void:
	_section("M opens the map list, and solo a choice changes it")
	var game := await _world(func(c: ZzConfig) -> void: c.map_ids = PackedStringArray())
	var _a := game.add_player(&"u1", "Ada")
	var _b := game.add_player(&"u2", "Bo")
	game.start()
	for _i in 4:
		game.simulate(TICK)
		await get_tree().physics_frame
	var settings := ZzSettings.new()
	add_child(settings)
	var _built: DotResult = settings.setup(DotSettingsStoreMemory.new())
	var keys: DotMenuBindings = settings.bindings
	_check(keys.key_for(DotMenuBindings.MAPS_ACTION) == "M" and keys.defaults_on("M").size() == 1,
		"the map menu is on M, and nothing else in the table defaults to M",
		str(keys.defaults_on("M").map(func(r: Dictionary) -> String: return str(r["label"]))))
	var rows: Array = game.map_rows()
	_check(rows.size() > 1 and rows.filter(func(r: Dictionary) -> bool: return bool(r["current"])).size() == 1,
		"there is more than one to choose, the one playing marked", "%d" % rows.size())
	var _maps := settings.use_maps(game.map_rows, game.change_map_now)
	var m := InputEventKey.new()
	m.physical_keycode = KEY_M
	m.keycode = KEY_M
	m.pressed = true
	_check(settings.menu.handle_event(m) and settings.menu.picker.is_open(), "M opens the picker")
	var wanted: StringName = &""
	var key := KEY_NONE
	for row in range(1, DotMenuPicker.PAGE_SIZE + 1):
		var it: Variant = settings.menu.picker.at_row(row)
		if it is Dictionary and not bool((it as Dictionary)["current"]):
			wanted = StringName(str((it as Dictionary)["id"]))
			key = KEY_0 + row
			break
	var digit := InputEventKey.new()
	digit.physical_keycode = key
	digit.keycode = key
	digit.pressed = true
	var _k := settings.menu.handle_event(digit)
	for _i in 4:
		await get_tree().physics_frame
	_check(wanted != &"" and game.map.id() == wanted, "choosing one changes to it now", "%s, now %s" % [wanted, game.map.id()])
	_check(not settings.menu.picker.is_open(), "and the picker is closed")
	settings.queue_free()
	await get_tree().process_frame
	_finished()


## The client on dot-game's DotGameClient: the loading cover is up at the start and blocks
## input, lifts once the player is in, and Tab goes through the menu (it holds the board).
func _test_the_client_platform() -> void:
	_section("the client: the cover lifts, Tab holds the board through the menu, the wheel is a row")
	var client := ZzClient.new()
	client.config_file = "user://cfg/headless-none.json"
	client.force_offline = true
	client.offline_bots = 0
	add_child(client)
	var platform: DotGameClient = client.platform
	var covered := platform != null and platform.gate != null and not platform.is_shown() \
		and platform.is_input_blocked()
	for _i in 600:
		await get_tree().physics_frame
		if platform.is_shown():
			break
	for _i in 2:
		await get_tree().process_frame
	_check(covered, "the loading cover is up at the start and blocks input")
	_check(platform.is_shown() and not platform.is_input_blocked() and platform.console != null,
		"and lifts once the player is in, with the console built", str(platform.describe()))
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	var _a: bool = client.settings.menu.handle_event(tab)
	var board: DotMenuScoreboard = client.board
	_check(board != null and board.is_open() and board.rows().any(func(r: Dictionary) -> bool: return bool(r.get("you", false))),
		"Tab holds the scoreboard up, with this player on it", str(board.rows()) if board != null else "no board")
	tab.pressed = false
	var _b: bool = client.settings.menu.handle_event(tab)
	_check(board != null and not board.is_open(), "and letting go puts it away")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	_check(wheel.is_action_pressed(DotMenuBindings.WEAPON_NEXT_ACTION) and client.settings.bindings.key_for(DotMenuBindings.WEAPON_NEXT_ACTION) == "Wheel down",
		"the wheel changes weapon through a rebindable row")
	var binds: DotMenuBindings = client.settings.bindings
	_check(binds.key_for(DotMenuBindings.WEAPON_PREVIOUS_ACTION) == "Wheel up" and binds.key_for(DotMenuBindings.WEAPON_NEXT_ACTION) == "Wheel down",
		"the wheel rows default to previous (up) and next (down)")
	var jump_wheel := InputEventMouseButton.new()
	jump_wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	jump_wheel.pressed = true
	_check(not jump_wheel.is_action_pressed(&"dot_fps_jump") and not wheel.is_action_pressed(&"dot_fps_jump"),
		"the wheel is not on jump")
	var slots: Array = client.weapons.arsenal.slots() if client.weapons != null and client.weapons.arsenal != null else []
	var before: int = client._slot
	# The press itself is gated on a captured pointer, which a headless run cannot have; the
	# routing is the action match above, so this drives what the action calls.
	client._cycle_slot(1)
	var after: int = client._slot
	var expected: int = before
	if slots.size() > 1:
		expected = slots[posmod((maxi(slots.find(before), 0)) + 1, slots.size())]
	_check(after == expected and (slots.size() < 2 or after != before),
		"the next-weapon step moves one slot", "slots %s, %d -> %d" % [str(slots), before, after])
	remove_child(client)
	client.free()
	await get_tree().process_frame
	_finished()


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


## A world on the practice street, stepped by hand. The previous one is freed first: every world
## here shares ONE physics space, and every map is built at the origin.
## The HUD draws health, the clock, the kits and confirmed hits through dot-ui's glance
## pieces, from this world's numbers. A headless viewport is 64 x 64, so the layout is checked
## as arithmetic and looked at with `tools/shot.sh --view=hit` and `--view=down`.
func _test_the_hud() -> void:
	_section("the HUD: dot-ui's vitals, clock, kits, and hits the server confirmed")
	var game := await _team(1)
	var me: ZzPlayer = game.survivors()[0]
	var hud := ZzHud.new()
	add_child(hud)
	hud.bind(game, me)

	me.health.health = 55.0
	me.temp_health = 25.0
	me.medkits = 1
	hud._process(0.0)
	_check(
		hud.vitals.number_text() == "30" and is_equal_approx(hud.vitals.bonus, 25.0) and hud.vitals.status == "",
		"DotVitals: real health as the number, borrowed health as its bonus", str(hud.vitals.describe())
	)
	_check(hud.kits.rows.size() == 1 and str(hud.kits.rows[0][0]) == "medkit" and str(hud.kits.rows[0][1]) != "",
		"the medkit is a DotKeyHints row with its key", str(hud.kits.rows))

	# The team-mate list is a server setting, off by default; the board carries the same facts.
	_check(not game.config.team_roster and not hud._team.visible, "the team list is off by default and hidden")
	game.config.team_roster = true
	hud._process(0.0)
	_check(hud._team.visible, "zz_team_roster 1 shows the team list")
	game.config.team_roster = false
	hud._process(0.0)
	_check(not hud._team.visible, "and 0 hides it again")
	_check(ZzClient.health_text(me) == "55" and ZzClient.downs_text(me, game.config.max_incaps) == str(game.config.max_incaps),
		"the board's health and downs left for a survivor", ZzClient.health_text(me))

	_hurt(game, me, 500.0)
	await _sim(game, 0.1)
	hud._process(0.0)
	_check(ZzClient.health_text(me) == "DOWN" and ZzClient.downs_text(me, game.config.max_incaps) == str(game.config.max_incaps - 1),
		"down shows DOWN and one down fewer on the board")
	_check(me.is_down() and hud.vitals.status == "DOWN" and hud.vitals.is_low(),
		"down, DOWN replaces the number and it is all in the low colour", str(hud.vitals.describe()))

	# A hold-out's clock is the strip's.
	var objectives: Array = game.map_doc.get("objectives", [])
	if objectives.is_empty():
		_check(false, "the practice street has an objective to hold")
	else:
		game.objective_states[0] = &"holding"
		game.objective_progress[0] = game.now() + 42.2
		hud._process(0.0)
		_check(hud.strip.clock == DotScoreStrip.clock_text(42.2) and hud.strip.under_text().ends_with("hold out"),
			"a hold-out's time left is DotScoreStrip's clock", str(hud.strip.describe()))

	# A survivor's hit, as dot-combat applies it, is confirmed by the world, and the HUD draws
	# the marker and the number from that confirmation.
	var confirmed: Array = []
	game.hit_landed.connect(func(id: StringName, victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
		confirmed.append([id, victim, amount, killed])
		hud.confirm_hit(victim, amount, point, killed, headshot))
	# On the street: nothing spawns in a safe room, which is where the team starts.
	var npc := game.horde.spawner.spawn(ZzNpcs.COMMON, STREET + Vector3(0, 0, -6), &"test")
	await _sim(game, 0.1)
	var shot := DotDamage.make(me.entity_id, game.horde.entity_id_for(npc), 7.0, null)
	shot.tick = game.current_tick()
	var _applied := game.combat.apply_damage(shot)
	_check(confirmed.size() == 1 and confirmed[0][0] == me.player_id and absf(float(confirmed[0][2]) - 7.0) < 0.01
		and not bool(confirmed[0][3]), "a survivor's hit on a zombie is confirmed, by whom and how much", str(confirmed))
	_check(hud.hit_marker.alpha() > 0.0 and hud.damage_numbers.texts().size() == 1,
		"and the HUD flashes DotHitMarker and puts up a DotDamageNumbers number", str(hud.damage_numbers.texts()))
	_hurt_npc(game, npc, 7.0)
	_check(confirmed.size() == 1, "the world's damage confirms nothing", str(confirmed))

	# Both bottom-anchored, so the arithmetic holds at any height.
	var chat := DotGameChatClient.new()
	add_child(chat)
	var w: DotChatWindow = chat.window
	var log_top := w.margin_bottom + w.entry_height + float(w.max_lines) * (w.line_height + w.line_gap)
	_check(ZzHud.PLATE_BOTTOM >= log_top and is_equal_approx(-hud.vitals.offset_bottom, ZzHud.PLATE_BOTTOM),
		"the health plate stays above a full chat log",
		"log reaches %.0f px off the bottom, the plate ends %.0f off it" % [log_top, -hud.vitals.offset_bottom])
	chat.queue_free()

	# Down the sights the dot fades with the aim (dot-ui's curve), and a scope hides it.
	hud.set_aim(0.0, false)
	var hip := hud._crosshair.modulate.a
	hud.set_aim(1.0, false)
	var aimed := hud._crosshair.modulate.a
	hud.set_aim(1.0, true)
	_check(is_equal_approx(hip, 1.0) and (aimed < 0.01 or DotAddonApi.build_level("dot_ui") < 5)
		and hud._crosshair.modulate.a == 0.0 and is_equal_approx(hud.scope.fraction, 1.0),
		"the crosshair is whole at the hip, gone down the sights, and a scope replaces it",
		"hip %.2f aimed %.2f scope %.2f" % [hip, aimed, hud.scope.fraction])
	hud.set_aim(0.0, false)
	_check_requires()
	await _check_killcam_time()

	hud.queue_free()
	_finished()


## Christian's first play test (2026-10-11): the team list's missing-glyph boxes, "You is down",
## the fence lock a black slab, the black void over the street, ten silent seconds after a
## wipe, and a HUD that should be darker and follow the menu's theme.
func _test_the_first_play_test() -> void:
	_section("the first play test: glyphs, the feed, the fence and its lock, the sky, the wipe, the theme")

	# Every character the game writes is in the HUD's font. The team bars were "▮▯", which the
	# embedded font lacks and Windows' fallback does not have either.
	var font: Font = ThemeDB.fallback_font
	var missing := PackedStringArray()
	for folder in ["res://game", "res://game/net", "res://npcs"]:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".gd"):
				continue
			for line in FileAccess.get_file_as_string(folder.path_join(file)).split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
				var code := line.split("#")[0] if line.count("\"") % 2 == 0 else line
				for c in code:
					if c.unicode_at(0) > 127 and not font.has_char(c.unicode_at(0)):
						missing.append("%s %s" % [file, c])
	_check(missing.is_empty(), "every character the game writes is in the HUD's font", ", ".join(missing))

	var game := await _team(3, func(c: ZzConfig) -> void:
		_quiet(c)
		c.intermission_seconds = 3.0
		c.killcam_seconds = 0.0
		c.team_roster = true)
	var me: ZzPlayer = game.survivors()[0]
	var hud := ZzHud.new()
	add_child(hud)
	hud.bind(game, me)
	var other: ZzPlayer = game.survivors()[1]
	other.health.health = other.health.max_health * 0.5
	_hurt(game, game.survivors()[2], 500.0)
	await _sim(game, 0.1)
	hud._process(0.0)
	var rows := hud.team_lines()
	_check(rows.size() == 2 and rows[0] == "%s|%d|0.50" % [other.display_name, int(ceilf(other.health.health))]
		and rows[1].ends_with("|DOWN|0.00"), "the team list is a drawn bar per survivor, not typed blocks", str(rows))

	_check(ZzClient.feed_line("You", "is down", "", &"", &"strangler", true) == "You are down (strangler)"
		and ZzClient.feed_line("You", "died", "", &"", &"common", true) == "You died (common)"
		and ZzClient.feed_line("Odell", "is down", "", &"", &"strangler") == "Odell is down (strangler)"
		and ZzClient.feed_line("You", "was picked up", "", &"", &"", true) == "You were picked up",
		"the feed says \"You are down\", and somebody else \"is down\"",
		ZzClient.feed_line("You", "is down", "", &"", &"strangler", true))

	# Christian asked for a darker HUD by default that the menu's theme restyles.
	var settings := ZzSettings.new()
	add_child(settings)
	var _built: DotResult = settings.setup(DotSettingsStoreMemory.new())
	hud.follow_menu(settings.menu)
	var plate := hud.vitals.colour(&"plate")
	_check(plate.get_luminance() < 0.1 and plate.a >= 0.7, "the HUD is dark by default, in the menu's theme", str(plate))
	var _t := settings.settings.set_value(&"ui_theme", &"contrast")
	var contrast: DotMenuPalette = settings.menu.palette()
	_check(contrast.id == &"contrast" and hud.vitals.colour(&"plate") == contrast.hud_plate and hud.strip.colour(&"text") == contrast.hud_text,
		"a theme picked in the menu reaches every piece at once")
	_check(hud.vitals.colour(&"highlight") == ZzHud.AMBER and hud._top.get_theme_color(&"font_color") == contrast.hud_text,
		"keeping this game's amber, and the HUD's own lines follow it too")
	_t = settings.settings.set_value(&"ui_theme", &"midnight")
	settings.queue_free()

	# A wipe counts down to the next round, on the strip, instead of ten silent seconds.
	for player in game.survivors():
		_hurt(game, player, 5000.0)
		_hurt(game, player, 5000.0)
		_hurt(game, player, 5000.0)
	await _sim(game, 2.6)
	hud._process(0.0)
	_check(game._decided and game.next_round_seconds() > 0.0 and game.next_round_seconds() <= 3.0
		and hud._top.text == "Trying again" and hud.strip.clock != "",
		"after a wipe the HUD counts down to the map again", "%.1f s, '%s' %s" % [game.next_round_seconds(), hud._top.text, hud.strip.clock])
	var number := game.round_number
	await _sim(game, 3.2)
	_check(game.round_number > number and game.next_round_seconds() < 0.0, "and the map starts again when it reaches nothing")
	hud.queue_free()

	# The fence and its lock, and the sky, as a client draws them.
	var doc := ZzCatalogue.practice().duplicate(true)
	for box: Dictionary in doc["boxes"]:
		if str(box.get("gate", "")) == "barrier":
			box["look"] = "chain_link"
	(doc["objectives"][0] as Dictionary)["prop"] = "padlock"
	var checked := ZzMapDoc.validate(doc)
	_check(checked.ok and str((checked.value["objectives"][0] as Dictionary).get("prop", "")) == "padlock",
		"a map may say what its objective is (a padlock) and how a gate looks (chain-link)")
	var drawn := ZzMap.new()
	drawn.physics = game.physics
	drawn.catalogue = game.props_catalogue
	drawn.draw_world = true
	add_child(drawn)
	var _b := drawn.build(checked.value)
	var fence := drawn.find_child("Gate_barrier", true, false)
	var lock := drawn.find_child("Objective_barrier", true, false)
	_check(fence != null and fence.find_child("ChainLink", true, false) == null and fence.get_child_count() > 3 and lock != null
		and lock.get_child_count() >= 10, "the gate is drawn as posts, rails and mesh, with a chain and padlock on it",
		"%s, %s" % [fence, lock])
	drawn.open_gate("barrier")
	_check(not is_instance_valid(lock) or lock.is_queued_for_deletion(), "and opening the gate takes the lock with it")
	var sky := (drawn._environment.environment.sky.sky_material as ProceduralSkyMaterial) if drawn._environment != null else null
	_check(ZzMap.is_night(checked.value["environment"]) and sky != null and sky.sky_cover != null
		and sky.sky_horizon_color.get_luminance() > 0.1, "a night map has a sky: stars, a moon, a lit horizon, not a black void")
	drawn.free()
	_finished()


## A pack naming dot-ui's glance pieces does not parse on a shell whose dot-ui predates them,
## so the requires.json dot-ci derives must ask for dot-ui 4, and nothing may lower it.
func _check_requires() -> void:
	var asks := DotAddonApi.derive()
	_check(
		int(asks.get("dot_ui", 0)) >= 4 and not FileAccess.file_exists("res://" + DotAddonApi.FLOOR_FILE),
		"the pack asks a shell for dot-ui level 4, the glance pieces",
		str(asks.get("dot_ui"))
	)


## The killcam is added to an intermission, never to an intermission of 0 (the suites run on 0).
func _check_killcam_time() -> void:
	var world := await _world()
	world.config.killcam_seconds = 7.0
	world.apply_intermission()
	_check(is_zero_approx(world.match_node.rules.intermission_sec), "the killcam adds nothing to an intermission of 0")
	world.config.intermission_seconds = 8.0
	world.apply_intermission()
	_check(is_equal_approx(world.match_node.rules.intermission_sec, 15.0), "and is added to the pause otherwise",
		str(world.match_node.rules.intermission_sec))


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


## A world with [param count] survivors, started, a moment in. Stand-ins only when [param bots].
func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game


## Nothing on the street but what a section puts there: no wanderers, no specials, no mob. A
## wanderer's swing during a revive or a heal is a different number, and which spawn point a
## wanderer is drawn at is the horde's business, not the section's.
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


## [param seconds] of simulated time. A physics frame every eight ticks, which is enough for a
## freshly built body to be in the space; queries see moved bodies at once.
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


func _shot(game: ZzGame, from: ZzPlayer, at: Vector3, damage: float) -> DotShot:
	var shot := DotShot.make(&"test", from.entity_id, game.current_tick(), 0)
	shot.origin = from.eye_position()
	shot.direction = (at - shot.origin).normalized()
	shot.damage = damage
	shot.damage_type = game.combat.damage_type(&"strike")
	shot.max_range = 100.0
	shot.scatter()
	return game.combat.resolve_shot(shot)


func _hurt(game: ZzGame, player: ZzPlayer, amount: float) -> void:
	var hit := DotDamage.make(0, player.entity_id, amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _hurt_npc(game: ZzGame, npc: DotNpcInstance, amount: float) -> void:
	var hit := DotDamage.make(0, game.horde.entity_id_for(npc), amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)
