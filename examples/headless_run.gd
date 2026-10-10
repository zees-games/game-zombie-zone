extends Node

const ZzBoxes := preload("../game/zz_boxes.gd")
const ZzCatalogue := preload("../game/zz_catalogue.gd")
const ZzConfig := preload("../game/zz_config.gd")
const ZzController := preload("../game/zz_controller.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzHazards := preload("../game/zz_hazards.gd")
const ZzLoot := preload("../game/zz_loot.gd")
const ZzMapDoc := preload("../game/zz_map_doc.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzProps := preload("../game/zz_props.gd")
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

const SECTIONS := 22

const CHECKS := 94

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
	await _test_every_box_outcome()
	await _test_effects_stack()
	await _test_objectives()
	await _test_winning_and_losing()
	await _test_stand_ins()
	await _test_a_crowd_is_cheap()

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
	var game := await _team(1)
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
	var game := await _team(1)
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
	var game := await _team(1)
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
	var game := await _team(2)
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
	var game := await _team(1)
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
	var game := await _team(2)
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
	var game := await _team(1)
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
	var game := await _team(1)
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
	await _sim(game, 60.0)
	var kills := 0
	var furthest := -INF
	for player in game.survivors():
		kills += player.commons_killed + player.specials_killed
		furthest = maxf(furthest, player.feet().z)
	_check(kills > 0, "they shoot what comes at them", "%d kills" % kills)
	_check(furthest > 10.0, "and they leave the start room for the street", "z %.0f" % furthest)
	_check(game.loot.count_of(ZzLoot.WEAPON) < 3, "picking up what was left for them", "%d left" % game.loot.count_of(ZzLoot.WEAPON))
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
