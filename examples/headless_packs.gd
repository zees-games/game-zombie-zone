extends "headless_packs_base.gd"

## Optional content packs (game/zz_packs.gd), against a fixture provider (a weapon with and one without a definition, a special,
## a boss, a monster named like a built-in): nothing installed changes nothing; installed, the weapon joins the pool and the
## monsters the catalogue; yml tuning is read from the config directory; a real game spawns the special and the boss.


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	_none_installed()
	_installed()
	_tuned()
	await _in_a_game()
	await _without_the_weapons_pack()
	_npc_profiles()
	_box_profiles()

	if _real_packs_linked():
		_sections += 1
		_checks += REAL_CHECKS + (3 if FileAccess.file_exists("res://addons/zz_mutants/%s" % ZzPacks.PROVIDER_FILE) else 2)
		await _real_packs()
		_sections += 1
		_checks += ALONE_CHECKS
		_each_pack_alone()
	else:
		print("\nreal packs: SKIP (link zz-modern-weapons, zz-medieval-weapons and zz-historical-monsters into addons/ to run)")

	_clean()
	ZzPacks.clear()
	ZzPacks.root = "res://addons"
	_report_sections(_entered, _finished, _sections, _checks)


## The icon a row names reaches the list of infected; a missing, empty or unloadable one gives no texture and the menu a stand-in.
func _check_bestiary() -> void:
	ZzBestiary.clear()
	var rows := ZzBestiary.entries()
	var ids: Array = rows.map(func(r: Dictionary) -> String: return str(r["id"]))
	_check(ids.has("fx_ghoul") and ids.has("fx_titan") and not ids.has("brute"), "the list holds the pack's monsters and not the refused one", str(ids))
	var by_id := {}
	for r in rows:
		by_id[r["id"]] = r
	_check(str(by_id["fx_ghoul"]["icon"]).ends_with("ghoul.png") and by_id["fx_titan"]["role"] == "boss", "a row's icon and role reach the list")
	_check(ZzBestiary.texture(by_id["fx_ghoul"]["icon"]) != null, "an icon the editor never imported still loads")
	_check(ZzBestiary.texture(by_id["fx_titan"]["icon"]) == null and ZzBestiary.texture("") == null, "a missing or empty icon is no texture, not an error")
	var menu := ZzBestiaryMenu.new()
	add_child(menu)
	menu.open()
	_check(menu.card_count() == rows.size() and menu.drawn.get("fx_ghoul", false) and not menu.drawn.get("fx_titan", true), "the menu draws a card per row, a stand-in where the icon is missing")
	menu.queue_free()


func _none_installed() -> void:
	_entered += 1
	print("nothing installed")
	_clean()
	var found := ZzPacks.scan("res://examples/fixtures/none")
	ZzWeapons.use_packs()
	_check(found == 0 and ZzPacks.monsters.is_empty() and ZzPacks.weapon_rows.is_empty(), "an empty scan finds nothing")
	var cfg_dir := ProjectSettings.globalize_path("user://zz_mounted_pack")
	DirAccess.make_dir_recursive_absolute(cfg_dir.path_join("cfg"))
	_check(ZzPacks._mounted_cfg_root("res://addons/pack/") == "" and ZzPacks._mounted_cfg_root(cfg_dir + "/addons/pack/") == cfg_dir + "/cfg",
		"a mounted pack's cfg root is found, a linked pack has none")
	_check(not ZzWeapons.exists(&"fx_rifle"), "no pack weapon in the pool")
	var cat := ZzNpcs.catalogue(ZzConfig.new())
	_check(cat.size() == 1, "the catalogue is the common zombie alone (the special infected come with zz-mutants)", "%d" % cat.size())
	_check(ZzPacks.specials().is_empty() and ZzPacks.bosses().is_empty(), "no pack specials or bosses")
	_finished += 1


## Deep equality where 4 and 4.0 are the same number (json reads floats, yml gives ints).
func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in a:
			if not (b as Dictionary).has(k) or not _same(a[k], b[k]):
				return false
		return true
	if a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


func _box_profiles() -> void:
	_entered += 1
	print("box profiles (cfg/game/game-zombie-zone/box)")
	var text := FileAccess.get_file_as_string("res://boxes/boxes.json")
	var floor_boxes := ZzBoxes.new(null)
	_check(floor_boxes.load_text(text).ok and floor_boxes.types.size() == 17, "boxes.json is the floor: seventeen types")
	var doc: Dictionary = JSON.parse_string(text)
	var stale := 0
	for box: Dictionary in doc["boxes"]:
		if FileAccess.get_file_as_string("%s/%s.yml" % [ZzBoxProfiles.DIR, box["id"]]) != ZzBoxProfiles.yaml_of(box):
			stale += 1
	_check(stale == 0 and DirAccess.get_files_at(ZzBoxProfiles.DIR).size() == 17, "the shipped files are what tools/export_box_profiles.gd writes", "%d stale" % stale)
	var shipped := ZzBoxes.new(null)
	var _l := shipped.load_text(text)
	var applied := shipped.overlay_profiles(ZzBoxProfiles.make_set(PackedStringArray(["res://cfg"])))
	var same := 0
	for id in floor_boxes.order:
		var a: Dictionary = floor_boxes.types[id]
		var b: Dictionary = shipped.types.get(id, {})
		if _same(b, a):
			same += 1
	_check(applied == 17 and same == 17, "with the shipped files every type reads as its json", "%d applied, %d same" % [applied, same])
	var base := "user://zz_box_cfg/server/game/game-zombie-zone/box"
	DirAccess.make_dir_recursive_absolute(base)
	var f := FileAccess.open(base + "/explosive.yml", FileAccess.WRITE)
	f.store_string("title: \"Big Bang\"\ndrop:\n  common: 9\nopen_seconds: 2.5\nsounds:\n  effect_end:\n    volume: 2\n")
	f.close()
	var served := ZzBoxes.new(null)
	var _l2 := served.load_text(text)
	var _n := served.overlay_profiles(ZzBoxProfiles.make_set(PackedStringArray(["res://cfg", "user://zz_box_cfg"])))
	var ex: Dictionary = served.types[&"explosive"]
	_check(ex["title"] == "Big Bang" and ex["drop"]["common"] == 9 and ex["open_seconds"] == 2.5, "a per-server file overrides the shipped type")
	_check(_same(ex["outcomes"], floor_boxes.types[&"explosive"]["outcomes"]) and served.types[&"medical"]["title"] == shipped.types[&"medical"]["title"], "and only that key and that type")
	_check(served.sounds.slot_of(&"explosive", &"effect_end")["volume"] == 2.0 and served.sounds.slot_of(&"medical", &"effect_end")["volume"] == 1.0, "its sound slot reaches the sounds, others stay stock")
	var f2 := FileAccess.open(base + "/explosive.yml", FileAccess.WRITE)
	f2.store_string("polarity: nasty\n")
	f2.close()
	var bad := ZzBoxes.new(null)
	var _l3 := bad.load_text(text)
	GSLog.set_level(GSLog.Level.FATAL)  # the refusal logs an ERROR on purpose
	var _n3 := bad.overlay_profiles(ZzBoxProfiles.make_set(PackedStringArray(["res://cfg", "user://zz_box_cfg"])))
	GSLog.set_level(GSLog.Level.ERROR)
	_check(bad.types[&"explosive"]["title"] == "Explosive Box", "a bad server file is refused and the shipped type stays")
	DirAccess.remove_absolute(base + "/explosive.yml")
	_finished += 1


## game.yml suggests zz-modern-weapons, and a player may remove it (the Workshop warns first): the game must then start, run a wave's worth of ticks and refuse a pack weapon quietly.
func _without_the_weapons_pack() -> void:
	_entered += 1
	print("the weapons pack absent")
	_clean()
	ZzPacks.root = "res://examples/fixtures/none"
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray(["zz_practice"])
	var game := ZzGame.new()
	game.config = config
	game.tick_rate = 64
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(ZzPacks.weapon_rows.is_empty() and not ZzWeapons.exists(&"zz_m4"), "no pack weapon is in the pool")
	var player := game.add_player(&"u100", "One")
	game.start()
	for i in 128:
		game.simulate(1.0 / 64.0)
	_check(game.horde != null and game.horde.catalogue.get_npc(&"common") != null, "the horde runs on the built-in kinds")
	_check(not game.arm(player, &"zz_m4"), "arming with a weapon the absent pack would have given is refused")
	_check(player != null and is_instance_valid(player), "and the survivor is still in the game")
	_check(not game.is_queued_for_deletion(), "the game keeps running")
	_check(ZzPacks.cores.is_empty() and ZzNpcs.specials().is_empty(), "with no mutants pack the game has no special infected")
	_check(ZzNpcs.core_def(ZzNpcs.MUTANT, config) == null and game.horde.catalogue.get_npc(ZzNpcs.BRUTE) == null, "and no mutant or brute definition")
	_check(game.horde.spawn_brute(Vector3.ZERO) == null, "a brute request is refused quietly")
	for i in 64:
		game.simulate(1.0 / 64.0)
	_check(not game.is_queued_for_deletion(), "specials rolls and sleepers pass without the pack")
	game.queue_free()
	_finished += 1


func _npc_profiles() -> void:
	_entered += 1
	print("npc profiles (cfg/game/game-zombie-zone/npc)")
	# The special infected are the zz-mutants pack's: load it alone (the shipped profiles overlay its definitions).
	var mutants_here := FileAccess.file_exists("res://addons/zz_mutants/%s" % ZzPacks.PROVIDER_FILE)
	_clean()
	ZzPacks.root = "res://addons"
	ZzPacks.only = PackedStringArray(["zz_mutants"]) if mutants_here else PackedStringArray(["none"])
	ZzPacks.scan()

	if not mutants_here:
		print("  zz-mutants not linked: the special-infected profile checks are skipped")
		ZzPacks.only = PackedStringArray()
		_checks -= 8
		_finished += 1
		return

	var c := ZzConfig.new()
	var built := ZzNpcs.builtin(c)
	var cat := ZzNpcs.catalogue(c)
	var same := 0
	var stale := 0
	for def: GSNpcDef in built:
		var got: GSNpcDef = cat.get_npc(def.id)
		if got != null and got.max_health == def.max_health and got.move_speed == def.move_speed \
				and got.sight_range == def.sight_range and got.sight_half_angle_deg == def.sight_half_angle_deg \
				and got.hearing_range == def.hearing_range and got.eye_height == def.eye_height \
				and got.cost == def.cost and got.weight == def.weight and got.display_name == def.display_name \
				and got.require_line_of_sight == def.require_line_of_sight and got.meta == def.meta:
			same += 1
		var file := "%s/%s.yml" % [ZzNpcProfiles.DIR, String(def.id)]
		# The game ships a profile for its own kind only; a pack's kinds carry their numbers in the pack (no file here).
		if ZzNpcs.is_pack_core(def.id):
			stale += 1 if FileAccess.file_exists(file) else 0
		elif FileAccess.get_file_as_string(file) != ZzNpcProfiles.yaml_of(def, c):
			stale += 1
	_check(DirAccess.get_files_at(ZzNpcProfiles.DIR).size() == 1, "a profile file for the common only, none for the pack's thirteen", "%d" % DirAccess.get_files_at(ZzNpcProfiles.DIR).size())
	_check(same == built.size(), "with the shipped files, every kind resolves to its code numbers", "%d of %d" % [same, built.size()])
	_check(stale == 0, "the shipped file is what tools/export_npc_profiles.gd writes, and no pack kind has one", "%d stale" % stale)

	var hard := ZzConfig.new()
	hard.common_health = 80.0
	hard.difficulty = 3
	var tuned := ZzNpcs.catalogue(hard)
	_check(tuned.get_npc(&"common").max_health == 80.0, "a cvar still reaches a kind whose file was not edited")
	_check(is_equal_approx(tuned.get_npc(&"leaper").max_health, 250.0 * hard.special_health_scale()), "difficulty scales the profile's health")

	var tier := "user://zz_npc_profile_test"
	var dir := "%s/cfg/game/%s/npc" % [tier, ZzNpcProfiles.GAME]
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/leaper.yml", FileAccess.WRITE)
	f.store_string("speed: 9.5\nextra:\n  pounce_max: 30.0\n")
	f.close()
	f = FileAccess.open(dir + "/brute.yml", FileAccess.WRITE)
	f.store_string("health: 5000.0\n")
	f.close()
	var over := ZzNpcs.catalogue(c, PackedStringArray(["res://cfg", tier + "/cfg"]))
	var leaper: GSNpcDef = over.get_npc(&"leaper")
	_check(leaper.move_speed == 9.5 and float(leaper.meta["pounce_max"]) == 30.0, "a later tier overrides the keys it names")
	_check(leaper.max_health == 250.0 and float(leaper.meta["pounce_min"]) == 4.0 and leaper.sight_range == 60.0, "and leaves the rest as shipped")
	_check(is_equal_approx(ZzNpcs.brute_health(c, 1, over.get_npc(&"brute")), 5000.0), "a brute's profile health is its base")
	_clean_tier(dir)
	ZzPacks.only = PackedStringArray()
	_clean()
	_finished += 1


func _clean_tier(dir: String) -> void:
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + name)


func _installed() -> void:
	_entered += 1
	print("installed (defaults)")
	_clean()
	var found := ZzPacks.scan(FIXTURE)
	ZzWeapons.use_packs()
	_check(found == 1, "one provider is loaded by path", "%d" % found)
	_check(ZzPacks.weapon_rows.size() == 1, "the weapon with a definition is listed, the one without is refused", "%d" % ZzPacks.weapon_rows.size())
	_check(ZzWeapons.exists(&"fx_rifle"), "the pack weapon is in the pool")
	_check(ZzWeapons.tier_of(&"fx_rifle") != &"", "it has a tier by tag", String(ZzWeapons.tier_of(&"fx_rifle")))
	_check(not ZzWeapons.exists(&"fx_unbacked"), "the row without a definition is never handed out")
	_check(ZzWeapons.ids_of(ZzWeapons.tier_of(&"fx_rifle")).has(&"fx_rifle"), "boxes and loot can draw it by tier")
	_check(ZzPacks.specials().size() == 1 and ZzPacks.bosses().size() == 1, "one special, one boss", "%d, %d" % [ZzPacks.specials().size(), ZzPacks.bosses().size()])
	_check(not ZzPacks.is_pack_kind(&"brute"), "a monster named like a built-in is refused")
	var cat := ZzNpcs.catalogue(ZzConfig.new())
	_check(cat.size() == 3, "the catalogue gains both monsters", "%d" % cat.size())
	var ghoul: GSNpcDef = cat.get_npc(&"fx_ghoul")
	_check(ghoul != null and ghoul.move_speed == 5.0 and float(ghoul.meta.get("damage", 0)) == 7.0, "a row's numbers reach the definition")
	_check(ZzNpcs.is_special(&"fx_ghoul"), "a pack monster counts as a special")
	_check_bestiary()
	_check(ZzPacks.pick(ZzPacks.specials(), 0.5).id == &"fx_ghoul", "a weighted pick finds it")
	_finished += 1


func _tuned() -> void:
	_entered += 1
	print("tuning from cfg/addon/zombie_zone/*.yml")
	_clean()
	_write("10-base.yml", "monsters:\n  weight: 3.0\n  boss_chance: 1.0\n")
	_write("20-server.yml", "monsters:\n  weights:\n    fx_titan: 0\n")
	var _f := ZzPacks.scan(FIXTURE)
	_check(is_equal_approx(ZzPacks.specials()[0].weight, 3.0), "every yml in the directory is read; the default weight applies", "%.1f" % ZzPacks.specials()[0].weight)
	_check(ZzPacks.bosses().is_empty(), "weight 0 in a later file drops that monster")
	_check(is_equal_approx(float(ZzPacks.cfg("monsters.boss_chance", 0.0)), 1.0), "boss_chance is read")

	_clean()
	_write("10-base.yml", "monsters:\n  boss: [fx_ghoul]\nweapons:\n  exclude: [fx_rifle]\n")
	_f = ZzPacks.scan(FIXTURE)
	ZzWeapons.use_packs()
	_check(ZzPacks.specials().is_empty() and ZzPacks.bosses().size() == 2, "the boss list moves a special into the bosses", "%d bosses" % ZzPacks.bosses().size())
	_check(not ZzWeapons.exists(&"fx_rifle") and ZzPacks.weapon_rows.is_empty(), "weapons.exclude keeps a weapon out of the pool")

	_clean()
	_write("10-base.yml", "weapons:\n  enabled: false\nmonsters:\n  enabled: false\n")
	_f = ZzPacks.scan(FIXTURE)
	ZzWeapons.use_packs()
	_check(ZzPacks.monsters.is_empty() and not ZzWeapons.exists(&"fx_rifle"), "both switches off leave the game as it was")
	_clean()

	_write("10-base.yml", "weapons:\n  tiers:\n    fx_rifle: heavy\n  not_in:\n    box: [fx_rifle]\nmonsters:\n  min_wave:\n    fx_ghoul: 4\n")
	_f = ZzPacks.scan(FIXTURE)
	ZzWeapons.use_packs()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_check(ZzWeapons.tier_of(&"fx_rifle") == &"heavy", "weapons.tiers moves a pack weapon to another tier", String(ZzWeapons.tier_of(&"fx_rifle")))
	var drawn_box := 0
	var drawn_loot := 0

	for _i in 200:
		drawn_box += 1 if ZzWeapons.random_of(&"heavy", rng, &"box") == &"fx_rifle" else 0
		drawn_loot += 1 if ZzWeapons.random_of(&"heavy", rng, &"loot") == &"fx_rifle" else 0

	_check(drawn_box == 0 and drawn_loot > 0, "weapons.not_in keeps it out of boxes only", "%d box, %d loot" % [drawn_box, drawn_loot])
	_check(ZzWeapons.channel_weight(&"trader", &"fx_rifle", 1.0) == 1.0 and ZzWeapons.channel_weight(&"box", &"fx_rifle", 1.0) == 0.0
		and ZzWeapons.channel_weight(&"trader", &"medkit", 2.0) == 2.0, "the spawner pools' weigher reads the same not_in per channel")
	_check(ZzPacks.specials(3).is_empty() and ZzPacks.specials(4).size() == 1 and ZzPacks.specials().size() == 1,
		"monsters.min_wave holds a monster back until its wave")
	_clean()
	_write("10-base.yml", "weapons:\n  weights:\n    fx_rifle: 0\n")
	_f = ZzPacks.scan(FIXTURE)
	ZzWeapons.use_packs()
	var got := 0

	for _i in 200:
		got += 1 if ZzWeapons.random_of(&"any", rng) == &"fx_rifle" else 0

	_check(got == 0 and ZzWeapons.exists(&"fx_rifle"), "weapons.weights 0 is never drawn but still exists")
	_clean()
	_finished += 1


func _in_a_game() -> void:
	_entered += 1
	print("a real game")
	_clean()
	_write("10-base.yml", "monsters:\n  weight: 1.0\n")
	ZzPacks.root = FIXTURE
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray(["zz_practice"])
	var game := ZzGame.new()
	game.config = config
	game.tick_rate = 64
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(ZzPacks.monsters.size() == 2, "the game scanned the packs when it started", "%d" % ZzPacks.monsters.size())
	_check(ZzWeapons.exists(&"fx_rifle"), "and its weapon is in the pool")
	var player := game.add_player(&"u100", "One")
	game.start()
	for i in 64:
		game.simulate(1.0 / 64.0)
	_check(game.horde != null and game.horde.catalogue.get_npc(&"fx_titan") != null, "the horde's catalogue carries the boss")
	var ghoul := game.horde.spawn_special(&"fx_ghoul")
	_check(ghoul != null and ghoul.def.id == &"fx_ghoul", "the director can send the pack special")
	var titan := game.horde.spawn_pack_boss(&"fx_titan")
	_check(titan != null and titan.def.id == &"fx_titan", "and the pack boss in a brute's place")
	_check(game.horde.specials_alive() >= 1, "pack specials count against the special cap")
	_check(game.arm(player, &"fx_rifle"), "a survivor can be armed with the pack weapon")
	game.queue_free()
	_finished += 1


func _real_packs_linked() -> bool:
	for pack: String in REAL_PACKS:
		if not FileAccess.file_exists("res://addons/%s/%s" % [pack, ZzPacks.PROVIDER_FILE]):
			return false

	return true


## One pack at a time: `ZzPacks.only` scans to exactly that pack's offer, and an armed survivor needs nothing from the others.
func _each_pack_alone() -> void:
	_entered += 1
	print("\neach real pack alone")
	_clean()
	_clean_real()
	var expect := {
		"zz_modern_weapons": [MODERN_IDS.size(), 0],
		"zz_medieval_weapons": [MEDIEVAL_IDS.size(), 0],
		"zz_historical_monsters": [0, 6],
	}

	for pack: String in expect:
		ZzPacks.only = PackedStringArray([pack])
		var found := ZzPacks.scan("res://addons")
		ZzWeapons.use_packs()
		var rows: int = expect[pack][0]
		var kinds: int = expect[pack][1]
		_check(found == 1 and ZzPacks.weapon_rows.size() == rows and ZzPacks.monsters.size() == kinds,
			"%s alone: one provider, %d weapons, %d monsters" % [pack, rows, kinds],
			"%d, %d, %d" % [found, ZzPacks.weapon_rows.size(), ZzPacks.monsters.size()])
		var ids: Array = MODERN_IDS if pack == "zz_modern_weapons" else MEDIEVAL_IDS
		var usable: bool = rows == 0 or ids.all(func(id: String) -> bool: return ZzWeapons.exists(StringName(id)) and ZzWeapons.def_of(StringName(id)) != null)
		_check(usable, "%s alone: every weapon has a definition" % pack)
		var cat_size := ZzNpcs.catalogue(ZzConfig.new()).size()
		_check(cat_size == 1 + kinds, "%s alone: the catalogue holds the built-in kinds plus its monsters" % pack, "%d" % cat_size)
		_check(kinds == 0 or ZzPacks.bosses().size() == 1, "%s alone: its boss is registered" % pack)

	ZzPacks.only = PackedStringArray()
	ZzPacks.scan()
	ZzWeapons.use_packs()
	_finished += 1


func _real_packs() -> void:
	_entered += 1
	print("\nthe real packs, linked in addons/")
	_clean()
	_clean_real()
	ZzPacks.root = "res://addons"
	var found := ZzPacks.scan()
	ZzWeapons.use_packs()
	# Fatal Contact's weapon addon, when a checkout links it, is skipped by the packs' skip list and never counted.
	var extra := 0
	# The class pack (zz_ply_class_pack) is a provider too, with no weapon rows.
	var class_pack := 1 if FileAccess.file_exists("res://addons/zz_ply_class_pack/%s" % ZzPacks.PROVIDER_FILE) else 0
	# zz-mutants (the Parasite Host) is a fourth provider where it is linked, and one more monster, a special.
	var mut := 1 if FileAccess.file_exists("res://addons/zz_mutants/%s" % ZzPacks.PROVIDER_FILE) else 0
	var extra_rows := ZzPacks.weapon_rows.filter(func(r: Dictionary) -> bool: return str(r.get("id", "")).begins_with("aw_")).size()
	_check(extra_rows == 0 and not ZzPacks.providers.has("fc_weapons") and not ZzPacks.providers.has("fc_weapons"), "Fatal Contact's weapon addon is never loaded as a pack", "%d" % extra_rows)
	_check(found == 3 + extra + class_pack + mut, "the three packs and any optional weapon pack are loaded from addons/", "%d" % found)
	_check(ZzPacks.weapon_rows.size() - extra_rows == MODERN_IDS.size() + MEDIEVAL_IDS.size(), "every weapon row of both weapon packs has a definition", "%d" % ZzPacks.weapon_rows.size())
	_check(extra == 0 or extra_rows > 0, "an optional weapon pack's rows join the catalogue", "%d" % extra_rows)

	_check(MODERN_IDS.all(func(id: String) -> bool: return ZzWeapons.exists(StringName(id))), "every modern weapons are in the pool")
	_check(MEDIEVAL_IDS.all(func(id: String) -> bool: return ZzWeapons.exists(StringName(id))), "every medieval weapons are in the pool")
	_check(MODERN_IDS.all(func(id: String) -> bool: return ZzWeapons.tier_of(StringName(id)) != &""), "each modern weapon has a tier")
	_check(MEDIEVAL_IDS.all(func(id: String) -> bool: return ZzWeapons.tier_of(StringName(id)) != &""), "each medieval weapon has a tier")

	# The trader's card and the hands draw ZeeWeaponArtTable's model for the id: the pack's own glb, one per weapon (never a zee stand-in).
	var models := {}
	for id: String in MODERN_IDS:
		var art := ZeeWeaponArtTable.get_art(StringName(id))
		models[art.model_path if art != null else "none:" + id] = true
	_check(models.size() == MODERN_IDS.size(), "each modern weapon's shop and hand model is its own", "%d distinct of %d" % [models.size(), MODERN_IDS.size()])
	_check(models.keys().all(func(path: String) -> bool: return path.begins_with("res://addons/zz_modern_weapons/assets/") and ResourceLoader.exists(path)),
		"every modern weapon's model is the pack's own and loads", str(models.keys().filter(func(path: String) -> bool: return not ResourceLoader.exists(path))))
	_check(ZzWeapons.tier_of(&"zz_vss") == &"primary", "the Vintorez is a primary", str(ZzWeapons.tier_of(&"zz_vss")))
	_check(ZzWeapons.tier_of(&"war_axe") == &"melee" and ZzWeapons.tier_of(&"double_axe") == &"melee", "both new axes are melee")
	_check(not ZzWeapons.exists(&"pistol") and ZzWeapons.exists(&"fists"), "zee's blasters are out of the catalogue, its fists stay")
	_check(ZzWeapons.resolve(&"pistol") == &"zz_pistol" and not ZzWeapons.offered(&"pistol") and ZzWeapons.offered(&"zz_pistol"),
		"a legacy blaster resolves to its modern successor and is not offered")
	_check(not ZzWeapons.offered(&"dagger") and not ZzWeapons.offered(&"war_axe"), "medieval weapons are not offered by default")
	_check(MEDIEVAL_IDS.all(func(id: String) -> bool: return not ZzWeapons.ids_of(ZzWeapons.tier_of(StringName(id))).has(StringName(id))),
		"no pool draws a medieval weapon by default")
	_check(ZzPacks.monsters.size() == 6 + mut and ZzPacks.specials().size() == 5 + mut and ZzPacks.bosses().size() == 1,
		"six monsters (seven with zz-mutants): the rest specials and one boss", "%d, %d, %d" % [ZzPacks.monsters.size(), ZzPacks.specials().size(), ZzPacks.bosses().size()])
	_check(ZzPacks.bosses()[0].id == &"zhm_trex", "the boss is the T-Rex")
	_check(ZzNpcs.catalogue(ZzConfig.new()).size() == 7 + 14 * mut, "the catalogue is the common zombie, the six monsters and, with zz-mutants, its thirteen kinds plus the Parasite Host")
	_pack_view(mut == 1)
	_check_pack_numbers()
	# A real game spawns each monster once, and arms a survivor with a weapon from each pack.
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.minimum_players = 0
	config.keep_progress = false
	config.map_ids = PackedStringArray(["zz_practice"])
	var game := ZzGame.new()
	game.config = config
	game.tick_rate = 64
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player := game.add_player(&"u100", "One")
	game.start()
	for i in 64:
		game.simulate(1.0 / 64.0)
	_check(game.horde != null and game.horde.catalogue.get_npc(&"zhm_trex") != null, "the horde's catalogue carries the monsters")
	var spawned := {}
	spawned[&"zhm_tiger"] = game.horde.spawn_special(&"zhm_tiger")
	spawned[&"zhm_bear"] = game.horde.spawn_special(&"zhm_bear")
	spawned[&"zhm_trex"] = game.horde.spawn_pack_boss(&"zhm_trex")

	for id: StringName in spawned:
		var npc: GSNpcInstance = spawned[id]
		_check(npc != null and npc.def.id == id, "%s spawns" % id)

	for i in 128:
		game.simulate(1.0 / 64.0)

	_check(spawned.values().all(func(n: GSNpcInstance) -> bool: return n != null and n.alive), "all three are alive after two seconds")
	_check(game.arm(player, &"zz_m4") and game.arm(player, &"dagger"), "a survivor can be armed from each weapon pack")
	_monster_host(game, player, spawned[&"zhm_tiger"])
	_pack_brain(game, player)
	_pack_colliders(game)
	_pack_handles(game, player)
	game.queue_free()
	_finished += 1
