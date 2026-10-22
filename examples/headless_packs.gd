extends Node

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzNpcs := preload("../game/zz_npcs.gd")
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
const SECTIONS := 4
const CHECKS := 29

var _passed := 0
var _failed := 0
var _entered := 0
var _finished := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	_none_installed()
	_installed()
	_tuned()
	await _in_a_game()

	_clean()
	ZzPacks.clear()
	ZzPacks.root = "res://addons"
	print("\n%d sections (%d finished), %d passed, %d failed" % [_entered, _finished, _passed, _failed])
	var ok := _failed == 0 and _entered == SECTIONS and _finished == SECTIONS and _passed + _failed == CHECKS
	print("PASS" if ok else "FAIL (expected %d sections and %d checks)" % [SECTIONS, CHECKS])
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
	ZzWeapons.use_packs(true)
	_check(found == 0 and ZzPacks.monsters.is_empty() and ZzPacks.weapon_rows.is_empty(), "an empty scan finds nothing")
	_check(not ZzWeapons.exists(&"fx_rifle"), "no pack weapon in the pool")
	var cat := ZzNpcs.catalogue(ZzConfig.new())
	_check(cat.size() == 12, "the catalogue is the twelve built-in kinds", "%d" % cat.size())
	_check(ZzPacks.specials().is_empty() and ZzPacks.bosses().is_empty(), "no pack specials or bosses")
	_finished += 1


func _installed() -> void:
	_entered += 1
	print("installed (defaults)")
	_clean()
	var found := ZzPacks.scan(FIXTURE)
	ZzWeapons.use_packs(true)
	_check(found == 1, "one provider is loaded by path", "%d" % found)
	_check(ZzPacks.weapon_rows.size() == 1, "the weapon with a definition is listed, the one without is refused", "%d" % ZzPacks.weapon_rows.size())
	_check(ZzWeapons.exists(&"fx_rifle"), "the pack weapon is in the pool")
	_check(ZzWeapons.tier_of(&"fx_rifle") != &"", "it has a tier by tag", String(ZzWeapons.tier_of(&"fx_rifle")))
	_check(not ZzWeapons.exists(&"fx_unbacked"), "the row without a definition is never handed out")
	_check(ZzWeapons.ids_of(ZzWeapons.tier_of(&"fx_rifle")).has(&"fx_rifle"), "boxes and loot can draw it by tier")
	_check(ZzPacks.specials().size() == 1 and ZzPacks.bosses().size() == 1, "one special, one boss", "%d, %d" % [ZzPacks.specials().size(), ZzPacks.bosses().size()])
	_check(not ZzPacks.is_pack_kind(&"brute"), "a monster named like a built-in is refused")
	var cat := ZzNpcs.catalogue(ZzConfig.new())
	_check(cat.size() == 14, "the catalogue gains both monsters", "%d" % cat.size())
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
	ZzWeapons.use_packs(true)
	_check(ZzPacks.specials().is_empty() and ZzPacks.bosses().size() == 2, "the boss list moves a special into the bosses", "%d bosses" % ZzPacks.bosses().size())
	_check(not ZzWeapons.exists(&"fx_rifle") and ZzPacks.weapon_rows.is_empty(), "weapons.exclude keeps a weapon out of the pool")

	_clean()
	_write("10-base.yml", "weapons:\n  enabled: false\nmonsters:\n  enabled: false\n")
	_f = ZzPacks.scan(FIXTURE)
	ZzWeapons.use_packs(true)
	_check(ZzPacks.monsters.is_empty() and not ZzWeapons.exists(&"fx_rifle"), "both switches off leave the game as it was")
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


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	print("  FAIL  %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
