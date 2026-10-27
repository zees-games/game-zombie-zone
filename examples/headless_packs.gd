extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzNpcProfiles := preload("../game/zz_npc_profiles.gd")
const ZzPacks := preload("../game/zz_packs.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

## Optional content packs (game/zz_packs.gd), against a fixture provider because the real packs
## are separate repositories that may not be installed. The fixture offers a weapon with a
## definition, a weapon row without one, a special, a boss and a monster named like a built-in.
##
## Sections: nothing installed changes nothing; installed, the weapon joins the pool and the
## monsters the catalogue; yml tuning (weights, exclusions, boss list) is read from the config
## directory; a real game spawns the special and the boss.

const FIXTURE := "res://examples/fixtures/addons"
const CFG_DIR := "user://cfg/addons/zombie_zone"
const SECTIONS := 5
const CHECKS := 44
## The real packs (zz-modern-weapons, zz-medieval-weapons, zz-historical-monsters), symlinked into
## addons/ as docs/development-setup.md says. The section runs only when all three are linked;
## otherwise it prints SKIP and the expected counts stay those of the fixture sections.
const REAL_PACKS := ["zz_modern_weapons", "zz_medieval_weapons", "zz_historical_monsters"]
const REAL_CHECKS := 31
const MODERN_IDS := ["zz_m4", "zz_sniper", "zz_knife", "zz_pistol", "zz_shotgun", "zz_smg", "zz_frag", "zz_vss", "zz_revolver", "zz_mp5", "zz_spas", "zz_lmg", "zz_dmr", "zz_m79", "zz_ak", "zz_scar", "zz_bren", "zz_glock", "zz_deagle", "zz_p90", "zz_aa12", "zz_rpg", "zz_machete", "zz_bat", "zz_crowbar", "zz_axe", "zz_sledge", "zz_hunting"]
const MEDIEVAL_IDS := ["longsword", "bow", "round_shield", "battle_axe", "war_axe", "double_axe", "mace", "spear", "crossbow", "dagger"]

var _passed := 0
var _failed := 0
var _entered := 0
var _finished := 0
var _sections := SECTIONS
var _checks := CHECKS


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	_none_installed()
	_installed()
	_tuned()
	await _in_a_game()
	_npc_profiles()

	if _real_packs_linked():
		_sections += 1
		_checks += REAL_CHECKS
		await _real_packs()
	else:
		print("\nreal packs: SKIP (link zz-modern-weapons, zz-medieval-weapons and zz-historical-monsters into addons/ to run)")

	_clean()
	ZzPacks.clear()
	ZzPacks.root = "res://addons"
	print("\n%d sections (%d finished), %d passed, %d failed" % [_entered, _finished, _passed, _failed])
	var ok := _failed == 0 and _entered == _sections and _finished == _sections and _passed + _failed == _checks
	print("PASS" if ok else "FAIL (expected %d sections and %d checks)" % [_sections, _checks])
	get_tree().quit(0 if ok else 1)


func _write(name: String, body: String) -> void:
	DirAccess.make_dir_recursive_absolute(CFG_DIR)
	var f := FileAccess.open("%s/%s" % [CFG_DIR, name], FileAccess.WRITE)
	f.store_string(body)
	f.close()


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(CFG_DIR):
		return

	for f in DirAccess.get_files_at(CFG_DIR):
		DirAccess.remove_absolute("%s/%s" % [CFG_DIR, f])


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
	_check(cat.size() == 13, "the catalogue is the thirteen built-in kinds", "%d" % cat.size())
	_check(ZzPacks.specials().is_empty() and ZzPacks.bosses().is_empty(), "no pack specials or bosses")
	_finished += 1


func _npc_profiles() -> void:
	_entered += 1
	print("npc profiles (cfg/game/game-zombie-zone/npc)")
	var c := ZzConfig.new()
	var built := ZzNpcs.builtin(c)
	var cat := ZzNpcs.catalogue(c)
	var same := 0
	var stale := 0
	for def: DotNpcDef in built:
		var got: DotNpcDef = cat.get_npc(def.id)
		if got != null and got.max_health == def.max_health and got.move_speed == def.move_speed \
				and got.sight_range == def.sight_range and got.sight_half_angle_deg == def.sight_half_angle_deg \
				and got.hearing_range == def.hearing_range and got.eye_height == def.eye_height \
				and got.cost == def.cost and got.weight == def.weight and got.display_name == def.display_name \
				and got.require_line_of_sight == def.require_line_of_sight and got.meta == def.meta:
			same += 1
		if FileAccess.get_file_as_string("%s/%s.yml" % [ZzNpcProfiles.DIR, String(def.id)]) != ZzNpcProfiles.yaml_of(def, c):
			stale += 1
	_check(DirAccess.get_files_at(ZzNpcProfiles.DIR).size() == built.size(), "a profile file for each of the thirteen kinds", "%d" % DirAccess.get_files_at(ZzNpcProfiles.DIR).size())
	_check(same == built.size(), "with the shipped files, every kind resolves to its code numbers", "%d of %d" % [same, built.size()])
	_check(stale == 0, "the shipped files are what tools/export_npc_profiles.gd writes", "%d stale" % stale)

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
	var leaper: DotNpcDef = over.get_npc(&"leaper")
	_check(leaper.move_speed == 9.5 and float(leaper.meta["pounce_max"]) == 30.0, "a later tier overrides the keys it names")
	_check(leaper.max_health == 250.0 and float(leaper.meta["pounce_min"]) == 4.0 and leaper.sight_range == 60.0, "and leaves the rest as shipped")
	_check(is_equal_approx(ZzNpcs.brute_health(c, 1, over.get_npc(&"brute")), 5000.0), "a brute's profile health is its base")
	_clean_tier(dir)
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
	_check(cat.size() == 15, "the catalogue gains both monsters", "%d" % cat.size())
	var ghoul: DotNpcDef = cat.get_npc(&"fx_ghoul")
	_check(ghoul != null and ghoul.move_speed == 5.0 and float(ghoul.meta.get("damage", 0)) == 7.0, "a row's numbers reach the definition")
	_check(ZzNpcs.is_special(&"fx_ghoul"), "a pack monster counts as a special")
	_check(ZzPacks.pick(ZzPacks.specials(), 0.5).id == &"fx_ghoul", "a weighted pick finds it")
	_finished += 1


func _tuned() -> void:
	_entered += 1
	print("tuning from cfg/addons/zombie_zone/*.yml")
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


func _damage_of(id: StringName) -> float:
	var def := ZzWeapons.def_of(id)
	return -1.0 if def == null or def.tuning == null else float(def.tuning.get("damage"))


func _clean_real() -> void:
	for pack: String in REAL_PACKS:
		var dir := "user://cfg/addons/%s" % pack

		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute("%s/%s" % [dir, f])


func _write_real(pack: String, name: String, body: String) -> void:
	var dir := "user://cfg/addons/%s" % pack
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open("%s/%s" % [dir, name], FileAccess.WRITE)
	f.store_string(body)
	f.close()


## The pack's game tier (`cfg/game/<game>/weapon`) is read under this game's id, so a profile override reaches it.
func _check_game_tier() -> void:
	var dir := "user://cfg/game/%s/weapon" % ZzPacks.GAME_ID
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open("%s/vss.yml" % dir, FileAccess.WRITE)
	f.store_string("extra:\n  damage: 61.0\n")
	f.close()
	ZzPacks.scan()
	ZzWeapons.use_packs()
	_check(is_equal_approx(_damage_of(&"zz_vss"), 61.0), "a game-tier profile overrides a pack weapon", "%.1f" % _damage_of(&"zz_vss"))
	DirAccess.remove_absolute("%s/vss.yml" % dir)


func _real_packs() -> void:
	_entered += 1
	print("\nthe real packs, linked in addons/")
	_clean()
	_clean_real()
	ZzPacks.root = "res://addons"
	var found := ZzPacks.scan()
	ZzWeapons.use_packs()
	_check(found == 3, "three providers are loaded from addons/", "%d" % found)
	_check(ZzPacks.weapon_rows.size() == MODERN_IDS.size() + MEDIEVAL_IDS.size(), "every weapon row of both weapon packs has a definition", "%d" % ZzPacks.weapon_rows.size())

	for id: String in MODERN_IDS + MEDIEVAL_IDS:
		if not ZzWeapons.exists(StringName(id)):
			_check(false, "weapon %s is in the pool" % id)

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
	_check(ZzPacks.monsters.size() == 6 and ZzPacks.specials().size() == 5 and ZzPacks.bosses().size() == 1,
		"six monsters: five specials and one boss", "%d, %d, %d" % [ZzPacks.monsters.size(), ZzPacks.specials().size(), ZzPacks.bosses().size()])
	_check(ZzPacks.bosses()[0].id == &"zhm_trex", "the boss is the T-Rex")
	_check(ZzNpcs.catalogue(ZzConfig.new()).size() == 19, "the catalogue is the thirteen built-in kinds and the six monsters")

	# Numbers: the game's damage table is handed to weapon_defs, and the pack's own yml defaults arrive.
	_check(is_equal_approx(_damage_of(&"zz_m4"), 29.0), "a modern weapon carries the pack's damage", "%.1f" % _damage_of(&"zz_m4"))
	_check(is_equal_approx(_damage_of(&"dagger"), 28.0), "a medieval weapon carries the pack's damage", "%.1f" % _damage_of(&"dagger"))
	var tiger: DotNpcDef = ZzNpcs.catalogue(ZzConfig.new()).get_npc(&"zhm_tiger")
	_check(tiger != null and is_equal_approx(tiger.max_health, 520.0) and is_equal_approx(float(tiger.meta.get("damage", 0)), 14.0),
		"a monster's health and damage come from the pack's yml")

	# Tuning: cfg/addons/<pack>/*.yml, name order, a later file wins.
	_write_real("zz_modern_weapons", "90-test.yml", "m4:\n  damage: 77\n")
	_write_real("zz_medieval_weapons", "90-test.yml", "dagger:\n  damage: 41\n")
	_write_real("zz_historical_monsters", "90-test.yml", "tiger:\n  claw:\n    damage: 33.0\n")
	_write("90-test.yml", "monsters:\n  weights:\n    zhm_bear: 0\n")
	found = ZzPacks.scan()
	ZzWeapons.use_packs()
	_check(is_equal_approx(_damage_of(&"zz_m4"), 77.0), "a modern weapon's damage follows its cfg yml", "%.1f" % _damage_of(&"zz_m4"))
	_check(is_equal_approx(_damage_of(&"dagger"), 41.0), "a medieval weapon's damage follows its cfg yml", "%.1f" % _damage_of(&"dagger"))
	_check_game_tier()
	_check(is_equal_approx(_damage_of(&"zz_sniper"), 125.0), "a weapon the yml does not name keeps its default")
	tiger = ZzNpcs.catalogue(ZzConfig.new()).get_npc(&"zhm_tiger")
	_check(tiger != null and is_equal_approx(float(tiger.meta.get("damage", 0)), 33.0), "a monster's damage follows its cfg yml")
	_check(ZzPacks.monsters.size() == 5 and not ZzPacks.is_pack_kind(&"zhm_bear"), "the game's own yml drops one monster by weight")
	_clean_real()
	_clean()
	found = ZzPacks.scan()
	ZzWeapons.use_packs()

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
		var npc: DotNpcInstance = spawned[id]
		_check(npc != null and npc.def.id == id, "%s spawns" % id)

	for i in 128:
		game.simulate(1.0 / 64.0)

	_check(spawned.values().all(func(n: DotNpcInstance) -> bool: return n != null and n.alive), "all three are alive after two seconds")
	_check(game.arm(player, &"zz_m4") and game.arm(player, &"dagger"), "a survivor can be armed from each weapon pack")
	game.queue_free()
	_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	print("  FAIL  %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
