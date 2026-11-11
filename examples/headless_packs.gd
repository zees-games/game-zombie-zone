extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
const ZzNpcProfiles := preload("../game/zz_npc_profiles.gd")
const ZzBoxes := preload("../game/zz_boxes.gd")
const ZzBoxProfiles := preload("../game/zz_box_profiles.gd")
const ZzPacks := preload("../game/zz_packs.gd")
const ZzPackBrains := preload("../game/zz_pack_brains.gd")
const ZzZombieBody := preload("../npcs/zz_zombie_body.gd")
const ZzZombieView := preload("../npcs/zz_zombie_view_base.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

## Optional content packs (game/zz_packs.gd), against a fixture provider because the real packs
## are separate repositories that may not be installed. The fixture offers a weapon with a
## definition, a weapon row without one, a special, a boss and a monster named like a built-in.
##
## Sections: nothing installed changes nothing; installed, the weapon joins the pool and the
## monsters the catalogue; yml tuning (weights, exclusions, boss list) is read from the config
## directory; a real game spawns the special and the boss.

const FIXTURE := "res://examples/fixtures/addons"
const CFG_DIR := "user://cfg/addon/zombie_zone"
const SECTIONS := 6
const CHECKS := 54
## Each real pack scanned alone from a directory holding only a link to it.
const ALONE_CHECKS := 12
## The real packs (zz-modern-weapons, zz-medieval-weapons, zz-historical-monsters), symlinked into
## addons/ as docs/development-setup.md says. The section runs only when all three are linked;
## otherwise it prints SKIP and the expected counts stay those of the fixture sections.
const REAL_PACKS := ["zz_modern_weapons", "zz_medieval_weapons", "zz_historical_monsters"]
const REAL_CHECKS := 72
const MODERN_IDS := ["zz_m4", "zz_sniper", "zz_knife", "zz_pistol", "zz_shotgun", "zz_smg", "zz_frag", "zz_vss", "zz_revolver", "zz_mp5", "zz_spas", "zz_lmg", "zz_dmr", "zz_m79", "zz_ak", "zz_scar", "zz_bren", "zz_glock", "zz_deagle", "zz_p90", "zz_aa12", "zz_rpg", "zz_machete", "zz_bat", "zz_crowbar", "zz_axe", "zz_sledge", "zz_hunting"]
const MEDIEVAL_IDS := ["longsword", "bow", "round_shield", "battle_axe", "war_axe", "double_axe", "mace", "spear", "crossbow", "dagger"]

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
	_box_profiles()

	if _real_packs_linked():
		_sections += 1
		_checks += REAL_CHECKS
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
	_check(cat.size() == 14, "the catalogue is the fourteen built-in kinds", "%d" % cat.size())
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
	DotLog.set_level(DotLog.Level.FATAL)  # the refusal logs an ERROR on purpose
	var _n3 := bad.overlay_profiles(ZzBoxProfiles.make_set(PackedStringArray(["res://cfg", "user://zz_box_cfg"])))
	DotLog.set_level(DotLog.Level.ERROR)
	_check(bad.types[&"explosive"]["title"] == "Explosive Box", "a bad server file is refused and the shipped type stays")
	DirAccess.remove_absolute(base + "/explosive.yml")
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
	_check(DirAccess.get_files_at(ZzNpcProfiles.DIR).size() == built.size(), "a profile file for each of the fourteen kinds", "%d" % DirAccess.get_files_at(ZzNpcProfiles.DIR).size())
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
	_check(cat.size() == 16, "the catalogue gains both monsters", "%d" % cat.size())
	var ghoul: DotNpcDef = cat.get_npc(&"fx_ghoul")
	_check(ghoul != null and ghoul.move_speed == 5.0 and float(ghoul.meta.get("damage", 0)) == 7.0, "a row's numbers reach the definition")
	_check(ZzNpcs.is_special(&"fx_ghoul"), "a pack monster counts as a special")
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
		_check(cat_size == 14 + kinds, "%s alone: the catalogue holds the built-in kinds plus its monsters" % pack, "%d" % cat_size)
		_check(kinds == 0 or ZzPacks.bosses().size() == 1, "%s alone: its boss is registered" % pack)

	ZzPacks.only = PackedStringArray()
	ZzPacks.scan()
	ZzWeapons.use_packs()
	_finished += 1


## The monsters' host seam in a running game: targets, blows and afflictions go through the game.
func _monster_host(game: ZzGame, player: Object, npc: DotNpcInstance) -> void:
	var host: Object = game.horde.spawner.get_meta(&"zhm_host", null)
	_check(host != null and host == game.horde.monster_host, "the spawner carries the game's monster host")
	var targets: Array = host.call(&"zhm_targets")
	_check(targets.size() == 1 and targets[0]["id"] == &"u100" and targets[0]["position"].is_equal_approx(game.horde.survivor_position(&"u100")),
		"the host offers the living survivor as a target", str(targets))
	var before: float = player.real_health()
	host.call(&"zhm_hit", npc, &"u100", 10.0, &"claw", {"source": npc.position()})
	_check(player.real_health() < before, "a claw lands through the game's zombie hit", "%.1f -> %.1f" % [before, player.real_health()])
	before = player.real_health()
	host.call(&"zhm_hit", npc, &"u100", 10.0, &"pounce", {"source": npc.position() + Vector3(2, 0, 0)})
	_check(player.real_health() < before, "a knocking blow hurts too", "%.1f -> %.1f" % [before, player.real_health()])
	host.call(&"zhm_status", &"u100", &"stun", 2.0, {})
	_check(host.call(&"slowed", &"u100"), "a stun is held against the survivor")
	game.simulate(1.0 / 64.0)
	_check(player.controller.motor.has_modifier(player.controller.state, &"zz_tagged"), "and slows them while it lasts")


## A pack monster runs its own brain on the game's body: it hunts, its attacks start and land through the host.
func _pack_brain(game: ZzGame, player: Object) -> void:
	for id: StringName in [&"zhm_tiger", &"zhm_bear", &"zhm_trex"]:
		var def: DotNpcDef = game.horde.catalogue.get_npc(id)
		_check(def != null and def.brain_script_path.begins_with("user://zz_pack_brains/") and FileAccess.file_exists(def.brain_script_path),
			"%s runs a generated brain, not the common's" % id, str(def.brain_script_path if def != null else "-"))
		_check(def != null and def.meta.has("cfg") and def.meta.get("species", "") != "", "%s carries its species and numbers" % id)

	# The generated script is named by its own text, so a build with another template (another checkout, sharing user://) never
	# swaps the file under a running monster: that was a tiger without force_target, once in a dozen loaded runs.
	var tiger_def: DotNpcDef = game.horde.catalogue.get_npc(&"zhm_tiger")
	var brain_path: String = tiger_def.brain_script_path if tiger_def != null else ""
	var brain_text := FileAccess.get_file_as_string(brain_path)
	_check(brain_text.contains("func force_target") and brain_text.contains("var _forced"), "the generated brain answers force_target", brain_path)
	var again: String = ZzPackBrains.wrapper_for(brain_text.get_slice("\"", 1))
	_check(again == brain_path, "and asking again for the same brain gives the same file", again)
	_check(ZzPackBrains.wrapper_for("res://other_brain.gd") != brain_path, "while another parent, or another template, is another file")

	# Drawn as the body each names (a client has no scene of the pack's): the bear and T-Rex as the brute, the cat as the leaper.
	var brute: Dictionary = ZzZombieView.look_for(&"brute", 0)
	var common: Dictionary = ZzZombieView.look_for(&"common", 0)
	_check(ZzZombieView.look_for(&"zhm_bear", 0)["body"] == brute["body"] and is_equal_approx(ZzZombieView.look_for(&"zhm_trex", 0)["height"], brute["height"]),
		"the bear and the T-Rex are drawn as the brute")
	_check(ZzZombieView.look_for(&"zhm_tiger", 0)["body"] == ZzZombieView.look_for(&"leaper", 0)["body"] and ZzZombieView.look_for(&"zhm_tiger", 0)["body"] != common["body"],
		"the tiger is drawn as the leaper")

	var at: Vector3 = game.horde.survivor_position(&"u100") + Vector3(5.0, 0.0, 0.0)
	var npc := game.horde.spawn_special(&"zhm_tiger", at)
	_check(npc != null and npc.brain != null and npc.brain.get(&"species") == &"tiger", "a tiger is made with the pack's brain", str(npc.brain.get(&"species")) if npc != null and npc.brain != null else "no brain")

	if npc == null or npc.brain == null:
		return

	var body := npc.node as ZzZombieBody
	var health: float = player.real_health()
	var moved := false
	var posed := false
	var start := npc.position()

	for i in 64 * 8:
		game.simulate(1.0 / 64.0)
		moved = moved or npc.position().distance_to(start) > 1.0
		posed = posed or (body != null and body.anim != ZzZombieBody.Anim.IDLE)

	var started: Dictionary = npc.brain.get(&"started")
	_check(moved, "the pack brain walks the zombie body to its prey")
	_check(posed, "and its pose reaches the body's anim")
	_check(not started.is_empty() or player.real_health() < health, "its attacks start or land",
		"%s %.1f -> %.1f" % [str(started), health, player.real_health()])
	_check(body != null and body.get_children().any(func(c: Node) -> bool: return c.has_method(&"apply_gait")), "the brain's view of the body hangs off it")


## The collider is the pack's declared body (radius capped for the doorways, height stooped like the brute's).
func _pack_colliders(game: ZzGame) -> void:
	var tiger: DotNpcDef = game.horde.catalogue.get_npc(&"zhm_tiger")
	var bear: DotNpcDef = game.horde.catalogue.get_npc(&"zhm_bear")
	var trex: DotNpcDef = game.horde.catalogue.get_npc(&"zhm_trex")
	_check(is_equal_approx(float(tiger.meta["radius"]), 0.55) and is_equal_approx(float(tiger.meta["height"]), 1.7),
		"the tiger's collider is the pack's 0.55 by 1.7", "%s x %s" % [tiger.meta["radius"], tiger.meta["height"]])
	_check(is_equal_approx(float(bear.meta["radius"]), 0.8) and is_equal_approx(float(bear.meta["height"]), 2.0),
		"the bear's is the pack's 0.8 by 2.0", "%s x %s" % [bear.meta["radius"], bear.meta["height"]])
	_check(is_equal_approx(float(trex.meta["radius"]), ZzNpcs.PACK_MAX_RADIUS) and is_equal_approx(float(trex.meta["height"]), 5.0),
		"the T-Rex's radius is held to what the doorways take, its height kept", "%s x %s" % [trex.meta["radius"], trex.meta["height"]])
	_check(is_equal_approx(float(trex.meta["fit_height"]), ZzNpcs.PACK_FIT_HEIGHT)
		and float(bear.meta["fit_height"]) == 0.0 and float(tiger.meta["fit_height"]) == 0.0, "the T-Rex stoops to a brute's 2.1 m, the shorter ones do not")
	_check(is_equal_approx(trex.eye_height, 4.5), "and the eyes keep the full height", "%.2f" % trex.eye_height)
	var spot: Vector3 = game.horde.survivor_position(&"u100") + Vector3(3.0, 0.0, 0.0)
	var npc := game.horde.spawn_special(&"zhm_trex", spot)
	var body := npc.node as ZzZombieBody if npc != null else null
	_check(body != null and is_equal_approx(body.radius, 0.9) and is_equal_approx(body.height, 5.0) and is_equal_approx(body.fit_height, 2.1),
		"the spawned body carries them", "%s" % [str([body.radius, body.height, body.fit_height]) if body != null else "none"])
	var shaped := false
	if body != null:
		for c in body.get_children():
			if c is CollisionShape3D and (c.shape as CapsuleShape3D) != null:
				shaped = is_equal_approx((c.shape as CapsuleShape3D).radius, 0.9) and is_equal_approx((c.shape as CapsuleShape3D).height, 2.1)
	_check(shaped, "and its collision capsule is that radius at the stooped height")
	game.horde.spawner.remove(npc.instance_id, DotNpcSpawner.REASON_CLEANUP)


## The game's handles on a brain, answered by a pack monster: told to hunt, lured, and tearing at a barricade.
func _pack_handles(game: ZzGame, player: Object) -> void:
	# The first rounds of a test game come and go in seconds, each laying the map out again and sweeping the horde:
	# begin once one is in play.
	var guard := 0
	while game.phase != ZzGame.Phase.PLAY and guard < 64 * 60:
		game.simulate(1.0 / 64.0)
		guard += 1
	player.health.invulnerable = true
	for n: DotNpcInstance in game.horde.spawner.npcs_near(Vector3.ZERO, 10000.0):
		game.horde.spawner.remove(n.instance_id, DotNpcSpawner.REASON_CLEANUP)
	var prey: Vector3 = game.horde.survivor_position(&"u100")
	# Far from the survivor, out of every pounce and charge range, so only the handle moves it.
	var tiger := _spawn_far(game, &"zhm_tiger", prey, 24.0)
	_check(tiger != null, "a tiger far from the survivor")
	if tiger == null:
		return
	var apart := tiger.position().distance_to(prey)
	_check(apart > 20.0, "farther than any of its leaps", "%.1f m" % apart)
	tiger.brain.call(&"force_target", &"u100")
	_check(tiger.target_id == &"u100", "force_target makes the survivor its target")
	for i in 64:
		game.simulate(1.0 / 64.0)
	_check(tiger.target_id == &"u100" and tiger.position().distance_to(prey) < apart - 1.0, "and it comes for them from beyond its sight",
		"%.1f -> %.1f m" % [apart, tiger.position().distance_to(prey)])

	# A barricade across its way: it stops and tears at it through the horde.
	var heading := Vector3(prey.x - tiger.position().x, 0.0, prey.z - tiger.position().z).normalized()
	var at := tiger.position() + heading * 3.0
	var box := AABB(Vector3(at.x - 3.0, -0.5, at.z - 0.3), Vector3(6.0, 3.5, 0.6))
	game.barricades["fx_pack"] = {"intact": true, "health": 1.0e6, "max": 1.0e6, "label": "test boards", "torn_at": -1.0}
	game.horde.set_barricades({"fx_pack": box})
	var torn_before := 1.0e6
	for i in 64 * 3:
		game.simulate(1.0 / 64.0)
	var bashing: bool = tiger.brain.get(&"bashing")
	_check(bashing, "pressed against boards on its way, it bashes")
	_check(float(game.barricades["fx_pack"]["health"]) < torn_before, "and the barricade loses health to it", "%.0f" % float(game.barricades["fx_pack"]["health"]))
	_check((tiger.node as ZzZombieBody).anim == ZzZombieBody.Anim.ATTACK, "swinging at it")
	var held := tiger.position()
	for i in 32:
		game.simulate(1.0 / 64.0)
	_check(tiger.position().distance_to(held) < 1.0, "and it stays at the boards while they stand", "%.2f m, bashing %s, wish %s" % [tiger.position().distance_to(held), tiger.brain.get(&"bashing"), (tiger.node as ZzZombieBody).wish])
	game.barricades["fx_pack"]["intact"] = false
	game.horde.set_barricades({})
	for i in 64:
		game.simulate(1.0 / 64.0)
	_check(not bool(tiger.brain.get(&"bashing")) and tiger.position().distance_to(held) > 1.0, "gone, it walks on")
	game.barricades.erase("fx_pack")

	game.horde.spawner.remove(tiger.instance_id, DotNpcSpawner.REASON_CLEANUP)
	_pack_lure(game, player)


## A lure: nobody to hunt, it goes to the point and stands there.
func _pack_lure(game: ZzGame, player: Object) -> void:
	var lured := _spawn_far(game, &"zhm_bear", player.global_position, 24.0)
	var plain := _spawn_far(game, &"zhm_tiger", player.global_position, 24.0)
	# Blind, so only the lure moves them; the point is ten metres down the street toward the survivor.
	lured.blind_until = 1.0e9
	plain.blind_until = 1.0e9
	var point := game.horde.snap_to_nav(lured.position() + (player.global_position - lured.position()).normalized() * 10.0)
	for i in 32:
		game.simulate(1.0 / 64.0)
	game.horde.lure(point, 30.0, 60.0)
	var before := lured.position().distance_to(point)
	var plain_before := plain.position().distance_to(point)
	for i in 64 * 4:
		game.simulate(1.0 / 64.0)
	_check(lured.position().distance_to(point) < before - 3.0, "a lure draws a pack monster toward it", "%.1f -> %.1f m, target %s, state %s, lure %s, at %s, point %s" % [before, lured.position().distance_to(point), lured.target_id, lured.brain.get(&"state"), lured.brain.get(&"lure"), lured.position(), point])
	_check(plain.position().distance_to(point) < plain_before - 3.0, "every pack monster in range, not one", "%.1f -> %.1f m" % [plain_before, plain.position().distance_to(point)])
	for i in 64 * 10:
		game.simulate(1.0 / 64.0)
	_check(lured.position().distance_to(point) <= 4.5, "and it stays at the lure", "%.1f m" % lured.position().distance_to(point))
	var it_moved := lured.position()
	for i in 64:
		game.simulate(1.0 / 64.0)
	_check(lured.position().distance_to(it_moved) < 0.5, "standing")
	# Told to hunt a survivor, it leaves the lure for them.
	lured.blind_until = -1.0
	lured.brain.call(&"force_target", &"u100")
	var gap := lured.position().distance_to(player.global_position)
	for i in 64:
		game.simulate(1.0 / 64.0)
	_check(lured.brain.get(&"state") != &"lure" and lured.position().distance_to(player.global_position) < gap - 1.0,
		"though a survivor it is told to hunt outranks it", "state %s, %.1f -> %.1f m" % [lured.brain.get(&"state"), gap, lured.position().distance_to(player.global_position)])
	for n: DotNpcInstance in [lured, plain]:
		game.horde.spawner.remove(n.instance_id, DotNpcSpawner.REASON_CLEANUP)


## A monster of [param kind] at least [param min_apart] metres from [param from], on the first spot the map lets one stand.
func _spawn_far(game: ZzGame, kind: StringName, from: Vector3, min_apart: float) -> DotNpcInstance:
	for d: float in [40.0, 34.0, 28.0, min_apart + 1.0]:
		for dir: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0.7, 0, -0.7), Vector3(-0.7, 0, 0.7)]:
			var npc := game.horde.spawn_special(kind, from + dir * d)
			if npc == null:
				continue
			if npc.position().distance_to(from) >= min_apart:
				return npc
			game.horde.spawner.remove(npc.instance_id, DotNpcSpawner.REASON_CLEANUP)
	return null


func _damage_of(id: StringName) -> float:
	var def := ZzWeapons.def_of(id)
	return -1.0 if def == null or def.tuning == null else float(def.tuning.get("damage"))


func _clean_real() -> void:
	for pack: String in REAL_PACKS:
		var dir := "user://cfg/addon/%s" % pack

		if DirAccess.dir_exists_absolute(dir):
			for f in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute("%s/%s" % [dir, f])


func _write_real(pack: String, name: String, body: String) -> void:
	var dir := "user://cfg/addon/%s" % pack
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
	# An optional extra weapon pack (arena_weapons) may be linked too: it adds a provider and rows, never removes any.
	var extra := 1 if FileAccess.file_exists("res://addons/arena_weapons/%s" % ZzPacks.PROVIDER_FILE) else 0
	# The class pack (zz_ply_class_pack) is a provider too, with no weapon rows.
	var class_pack := 1 if FileAccess.file_exists("res://addons/zz_ply_class_pack/%s" % ZzPacks.PROVIDER_FILE) else 0
	var extra_rows := ZzPacks.weapon_rows.filter(func(r: Dictionary) -> bool: return str(r.get("id", "")).begins_with("aw_")).size()
	_check(found == 3 + extra + class_pack, "the three packs and any optional weapon pack are loaded from addons/", "%d" % found)
	_check(ZzPacks.weapon_rows.size() - extra_rows == MODERN_IDS.size() + MEDIEVAL_IDS.size(), "every weapon row of both weapon packs has a definition", "%d" % ZzPacks.weapon_rows.size())
	_check(extra == 0 or extra_rows > 0, "an optional weapon pack's rows join the catalogue", "%d" % extra_rows)

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
	_check(ZzNpcs.catalogue(ZzConfig.new()).size() == 20, "the catalogue is the fourteen built-in kinds and the six monsters")

	# Numbers: the game's damage table is handed to weapon_defs, and the pack's own yml defaults arrive.
	_check(is_equal_approx(_damage_of(&"zz_m4"), 29.0), "a modern weapon carries the pack's damage", "%.1f" % _damage_of(&"zz_m4"))
	_check(is_equal_approx(_damage_of(&"dagger"), 28.0), "a medieval weapon carries the pack's damage", "%.1f" % _damage_of(&"dagger"))
	var tiger: DotNpcDef = ZzNpcs.catalogue(ZzConfig.new()).get_npc(&"zhm_tiger")
	_check(tiger != null and is_equal_approx(tiger.max_health, 520.0) and is_equal_approx(float(tiger.meta.get("damage", 0)), 14.0),
		"a monster's health and damage come from the pack's yml")

	# Tuning: cfg/addon/<pack>/*.yml, name order, a later file wins.
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
	_monster_host(game, player, spawned[&"zhm_tiger"])
	_pack_brain(game, player)
	_pack_colliders(game)
	_pack_handles(game, player)
	game.queue_free()
	_finished += 1
