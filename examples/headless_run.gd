extends Node

const ZzBindings := preload("../game/zz_bindings.gd")
const ZzBoxes := preload("../game/zz_boxes.gd")
const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzController := preload("../game/zz_controller.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzHazards := preload("../game/zz_hazards.gd")
const ZzHud := preload("../game/zz_hud.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzProps := preload("../game/zz_props.gd")
const ZzSettings := preload("../game/zz_settings.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")

## The simulation, headless: the documents, the navigation, the horde and every special, the
## downs and the hands, the boxes, the objectives and how a map is won and lost.
##
## [b]Counts sections AND checks, and the second is the one that matters.[/b] A script error
## inside a section aborts that function and the section counter is already satisfied,
## because the section announced itself on the way in. dot-settings has the story.
##
## Every number about the map here is the built-in practice street's
## ([method ZzCatalogue.practice]), whose comment lists where everything is.

const SECTIONS := 27

const CHECKS := 132

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
	await _test_the_room_wakes()
	await _test_downs()
	await _test_borrowed_health()
	await _test_the_shove()
	await _test_pins()
	await _test_every_special()
	await _test_hazards()
	await _test_loot()
	await _test_both_packs()
	await _test_every_box_outcome()
	await _test_effects_stack()
	await _test_objectives()
	await _test_winning_and_losing()
	await _test_stand_ins()
	await _test_stand_ins_and_the_pass_through_level()
	await _test_a_crowd_is_cheap()
	await _test_the_hud()
	await _test_help_and_menu()
	await _test_the_map_menu()

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
	_check(doc["mode"] == ZzMapDoc.CAMPAIGN and (doc["areas"]["end"] as Array).size() == 1 and (doc["objectives"] as Array).size() == 1,
		"a campaign with an end room and an objective")

	var bad := doc.duplicate(true)
	bad["mode"] = "deathmatch"
	_check(not ZzMapDoc.validate(bad).ok, "a mode that is neither is refused")

	bad = doc.duplicate(true)
	bad["areas"] = {"start": doc["areas"]["start"], "end": []}
	_check(not ZzMapDoc.validate(bad).ok, "a campaign with nowhere to reach is refused")

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
	_check(game.loot.count_of(ZzLoot.WEAPON) == 3 and game.loot.count_of(ZzLoot.BOX) == 1, "the map's weapons and its box are lying where it put them")
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

	for kind in [ZzNpcs.LEAPER, ZzNpcs.STRANGLER, ZzNpcs.BLOATER, ZzNpcs.RAM, ZzNpcs.SPITTER, ZzNpcs.RIDER, ZzNpcs.BRUTE]:
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
		c.intermission_seconds = 0.5)
	for player in game.survivors():
		player.health.invulnerable = true
		player.place_at(END_ROOM, 0.0)
	await _sim(game, 1.0)
	_check(game._decided and game._won, "everybody standing in the end room wins it")

	game = await _team(2, func(c: ZzConfig) -> void: c.intermission_seconds = 0.5)
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
	# Before zz_trace.gd and the hitbox-based friend check, every shot from inside a friend hit
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

	_hurt(game, me, 500.0)
	await _sim(game, 0.1)
	hud._process(0.0)
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
	_check_requires()

	hud.queue_free()
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
