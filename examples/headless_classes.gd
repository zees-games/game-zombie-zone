extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzEvent := preload("../game/net/zz_event.gd")
const ZzClasses := preload("../game/zz_classes.gd")
const ZzPacks := preload("../game/zz_packs.gd")
const ZzAvatars := preload("../game/zz_avatars.gd")

## Classes (zz-ply-class-pack): the profiles load from the pack, one default is dealt, a person may pick
## another when the server allows it, a model is drawn at random or chosen as the profile says, a bad
## profile is refused alone, and without the pack the old defaults stand. Counts sections AND checks.

const SECTIONS := 7
const CHECKS := 56

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const BAD_DIR := "user://classes_bad_cfg"
const PACK_CFG := "res://addons/zz_ply_class_pack/cfg"

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone classes")
	print("")
	await _test_load()
	await _test_default()
	await _test_select()
	await _test_models()
	await _test_bad()
	await _test_fallback()
	await _test_wire()

	for world in _worlds.duplicate():
		await _dispose(world)

	ZzPacks.clear()
	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


func _use_pack() -> void:
	ZzClasses.set_roots(PackedStringArray())
	ZzPacks.root = "res://addons"
	var _n := ZzPacks.scan()
	ZzClasses.forget()


func _test_load() -> void:
	_section("the pack's six classes load through the pack scan, with their numbers")
	_use_pack()
	var all := ZzClasses.all()
	_check(all.size() >= 6, "at least six classes", str(all.keys()))
	for id in ["survivor", "medic", "scout", "heavy", "hunter", "looter"]:
		_check(all.has(id), "class %s is there" % id)
	var heavy: DotPlayerClassDef = all["heavy"]
	_check(is_equal_approx(heavy.max_health, 140.0) and heavy.move_speed_scale < 1.0, "heavy: 140 health, slower", str(heavy.max_health))
	var scout: DotPlayerClassDef = all["scout"]
	_check(scout.move_speed_scale > 1.0 and scout.sprint_speed_scale > 1.0, "scout: faster, sprints harder")
	_check(String(scout.loadout_id) == "zz_smg,zz_knife", "scout carries its loadout", String(scout.loadout_id))
	_check(ZzClasses.models_of(all["medic"]) == PackedStringArray(["skin_c", "skin_f"]), "medic's models come through the profile")
	_check(ZzClasses.model_mode(all["scout"]) == "select" and ZzClasses.model_mode(all["heavy"]) == "first", "model modes are read")
	_check(ZzClasses.rejected().is_empty(), "nothing in the pack is refused", str(ZzClasses.rejected()))
	_finished()


func _test_default() -> void:
	_section("one default class is dealt; a player cannot pick another while selection is off")
	_use_pack()
	var game := await _team(1)
	var p := game.survivors()[0]
	_check(p.class_id == &"survivor", "the default is survivor", String(p.class_id))
	_check(ZzAvatars.SKINS.has(p.class_skin), "it wears one of its models", String(p.class_skin))
	_check(is_equal_approx(p.health.max_health, game.config.max_health), "its health is the game's")
	var refused := game.request_class(p.player_id, "medic")
	_check(not refused.ok, "selection is off: a request is refused", refused.error.message if not refused.ok else "")
	game.config.class_default = "heavy"
	game.assign_class(p)
	_check(p.class_id == &"heavy" and is_equal_approx(game.class_health(p), 140.0), "the server's default class is a setting", String(p.class_id))
	game.config.class_default = "no_such_class"
	game.assign_class(p)
	_check(p.class_id == &"survivor", "an unknown default falls back to survivor")
	game.config.class_default = "survivor"
	_finished()


func _test_select() -> void:
	_section("with selection on a player picks an offered class for the next spawn, server-checked")
	_use_pack()
	var game := await _team(1, func(c: ZzConfig) -> void:
		c.class_select = true
		c.class_allowed = "medic,scout,heavy")
	var p := game.survivors()[0]
	_check(ZzClasses.offered(true, "medic,scout,heavy") == PackedStringArray(["heavy", "medic", "scout"]), "the offered list is the allowed list")
	_check(not game.request_class(p.player_id, "hunter").ok, "a class off the list is refused")
	_check(not game.request_class(p.player_id, "nonsense").ok, "an unknown class is refused")
	_check(not game.request_class(p.player_id, "scout", "skin_k").ok, "a model the class does not have is refused")
	_check(p.class_id == &"survivor", "a request changes nothing until the next spawn")
	var ok := game.request_class(p.player_id, "scout", "skin_e")
	_check(ok.ok, "an offered class is accepted")
	var seen: Array = []
	game.player_classed.connect(func(id: StringName, class_id: StringName, skin: StringName) -> void: seen.append([id, class_id, skin]))
	game.place_one(p)
	_check(p.class_id == &"scout", "the next spawn deals it", String(p.class_id))
	_check(p.class_skin == &"skin_e", "and the model it chose (select mode)", String(p.class_skin))
	_check(is_equal_approx(p.health.max_health, 80.0), "health 80 from the profile", str(p.health.max_health))
	_check(p.controller.tunables.max_speed > game.config.run_speed, "the movement is the class's", str(p.controller.tunables.max_speed))
	_check(p.weapons.arsenal.catalogue.get_def(&"zz_smg") != null and game.arm(p, &"zz_smg"), "the loadout is armed")
	_check(seen.size() == 1 and seen[0][1] == &"scout", "and told to the clients once", str(seen))
	_check(not ZzClasses.check_choice("scout", false, "").ok, "selection off refuses everything")
	_finished()


func _test_models() -> void:
	_section("model_mode: random draws from the list every spawn; first and select are as the profile says")
	_use_pack()
	var all := ZzClasses.all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var medic: DotPlayerClassDef = all["medic"]
	var seen := {}
	for i in 60:
		seen[ZzClasses.pick_model(medic, "", rng)] = true
	_check(seen.size() == 2 and seen.has("skin_c") and seen.has("skin_f"), "random: both of the medic's models, no others", str(seen.keys()))
	var surv: DotPlayerClassDef = all["survivor"]
	var seen_all := {}
	for i in 200:
		seen_all[ZzClasses.pick_model(surv, "", rng)] = true
	_check(seen_all.size() == 6, "random over six models reaches all six", str(seen_all.size()))
	var same_a := RandomNumberGenerator.new()
	var same_b := RandomNumberGenerator.new()
	same_a.seed = 99
	same_b.seed = 99
	_check(ZzClasses.pick_model(surv, "", same_a) == ZzClasses.pick_model(surv, "", same_b), "random is repeatable from the same seed")
	_check(ZzClasses.pick_model(all["heavy"], "skin_a", rng) == "skin_k", "first: always the head of the list")
	_check(ZzClasses.pick_model(all["scout"], "skin_e", rng) == "skin_e", "select: the player's pick")
	_check(ZzClasses.pick_model(all["scout"], "skin_k", rng) == "skin_b", "select: a pick off the list gets the first model")
	var game := await _team(1)
	var p := game.survivors()[0]
	var spawns := {}
	for i in 40:
		game.assign_class(p)
		spawns[p.class_skin] = true
	_check(spawns.size() > 1, "a respawned survivor does not always get the same model", str(spawns.keys()))
	_finished()


func _bad_file(id: String, text: String) -> void:
	var path := BAD_DIR.path_join("server/game/game-zombie-zone/class/%s.yml" % id)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_bad() -> void:
	_section("a bad profile is rejected on its own; the good ones load")
	var _clean := DotPaths.remove_tree(BAD_DIR)
	_bad_file("good", "name: Good\nhealth: 120\nextra:\n  models: [skin_a]\n  model_mode: first\n")
	_bad_file("badmode", "health: 100\nextra:\n  models: [skin_a]\n  model_mode: sometimes\n")
	_bad_file("badmodel", "health: 100\nextra:\n  models: [skin_zz]\n")
	_bad_file("badhealth", "health: 0\n")
	_bad_file("nomodels", "health: 100\nextra:\n  model_mode: select\n")
	ZzClasses.set_roots(PackedStringArray([BAD_DIR]))
	DotLog.set_level(DotLog.Level.FATAL)
	var all := ZzClasses.all()
	DotLog.set_level(DotLog.Level.ERROR)
	_check(all.has("good") and all.size() == 1, "only the good profile loads", str(all.keys()))
	var why := "\n".join(ZzClasses.rejected())
	_check(ZzClasses.rejected().size() == 4, "four are refused and named", why)
	_check(why.contains("model_mode") and why.contains("skin_zz"), "and each refusal says why")
	ZzClasses.set_roots(PackedStringArray())
	var _gone := DotPaths.remove_tree(BAD_DIR)
	_finished()


func _test_fallback() -> void:
	_section("without the pack the game's own survivor stands, and the pack's absence breaks nothing")
	ZzPacks.clear()
	ZzClasses.set_roots(PackedStringArray(["user://no_such_cfg_root"]))
	_check(ZzClasses.all().is_empty() and ZzClasses.survivor() == null, "no class profiles: no def")
	_check(ZzClasses.default_id() == "survivor" and ZzClasses.draw_for_bot(RandomNumberGenerator.new()) == "survivor", "the default id is still survivor")
	var game := await _team(1)
	var p := game.survivors()[0]
	_check(p.class_def == null and p.class_skin == &"", "a survivor has no class and keeps their avatar")
	_check(is_equal_approx(p.health.max_health, game.config.max_health), "health is the game's")
	_check(is_equal_approx(p.controller.tunables.max_speed, game.config.run_speed), "speed is the game's")
	_check(not game.request_class(p.player_id, "medic").ok, "and no class can be requested")
	ZzClasses.set_roots(PackedStringArray())
	_finished()


func _test_wire() -> void:
	_section("CLASSED crosses the wire and a client applies it; stand-ins draw by weight and take the class's persona")
	_use_pack()
	var body := ZzEvents.write_classed(5, &"medic", &"skin_f")
	var r := DotNetReader.new(body)
	var got := ZzEvents.read_classed(r)
	_check(bool(got["ok"]) and int(got["player_id"]) == 5 and got["class_id"] == &"medic" and got["skin"] == &"skin_f", "write and read agree", str(got))
	_check(ZzEvent.fits(), "every event kind still fits the header")
	var cgame := await _team(1)
	var client := cgame.survivors()[0]
	cgame.set_class(client, &"scout", &"skin_b", ZzClasses.def_of("scout"))
	_check(client.class_id == &"scout" and client.class_skin == &"skin_b", "a client keeps the class and skin")
	_check(client.controller.tunables.max_speed > cgame.config.run_speed, "and predicts the class's speed")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var drawn := {}
	for i in 200:
		drawn[ZzClasses.draw_for_bot(rng)] = true
	_check(drawn.size() == 6, "stand-ins draw every class by bot_weight", str(drawn.keys()))
	var game := await _team(2, Callable(), true)
	var bot := game.survivors()[0]
	_check(bot.class_id != &"" and bot.class_def != null, "a stand-in is dealt a class")
	var persona := str(bot.class_def.attributes.get("persona", ""))
	_check(persona != "", "its class names a persona", persona)
	var pool: DotBotPersonaPool = game.personas()
	var found := false
	for pe in pool.personas:
		if String(pe.id) == persona:
			found = true
	_check(found, "and that persona exists in the bot profiles")
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



func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game



func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1
