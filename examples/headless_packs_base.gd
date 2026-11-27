extends GSGameCheckSuite

## Constants, fixtures and per-section helpers of headless_packs.gd: config-directory writes, the real-pack monster seams and the number checks.

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
const ZzWorldView := preload("../game/zz_world_view.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")
const ZzBestiary := preload("../game/zz_bestiary.gd")
const ZzBestiaryMenu := preload("../game/zz_bestiary_menu.gd")

const FIXTURE := "res://examples/fixtures/addons"
const CFG_DIR := "user://cfg/addon/zombie_zone"
const SECTIONS := 7
const CHECKS := 68
## Each real pack scanned alone from a directory holding only a link to it.
const ALONE_CHECKS := 12
## The real packs (zz-modern-weapons, zz-medieval-weapons, zz-historical-monsters), symlinked into
## addons/ as docs/development-setup.md says. The section runs only when all three are linked;
## otherwise it prints SKIP and the expected counts stay those of the fixture sections.
const REAL_PACKS := ["zz_modern_weapons", "zz_medieval_weapons", "zz_historical_monsters"]
const REAL_CHECKS := 73
const MODERN_IDS := ["zz_m4", "zz_sniper", "zz_knife", "zz_pistol", "zz_shotgun", "zz_smg", "zz_frag", "zz_vss", "zz_revolver", "zz_mp5", "zz_spas", "zz_lmg", "zz_dmr", "zz_m79", "zz_ak", "zz_scar", "zz_bren", "zz_glock", "zz_deagle", "zz_p90", "zz_aa12", "zz_rpg", "zz_machete", "zz_bat", "zz_crowbar", "zz_axe", "zz_sledge", "zz_hunting"]
const MEDIEVAL_IDS := ["longsword", "bow", "round_shield", "battle_axe", "war_axe", "double_axe", "mace", "spear", "crossbow", "dagger"]

var _entered := 0
var _finished := 0
var _sections := SECTIONS
var _checks := CHECKS


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

## The monsters' host seam in a running game: targets, blows and afflictions go through the game.
func _monster_host(game: ZzGame, player: Object, npc: GSNpcInstance) -> void:
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
		var def: GSNpcDef = game.horde.catalogue.get_npc(id)
		_check(def != null and def.brain_script_path.begins_with("user://zz_pack_brains/") and FileAccess.file_exists(def.brain_script_path),
			"%s runs a generated brain, not the common's" % id, str(def.brain_script_path if def != null else "-"))
		_check(def != null and def.meta.has("cfg") and def.meta.get("species", "") != "", "%s carries its species and numbers" % id)

	# The generated script is named by its own text, so a build with another template (another checkout, sharing user://) never
	# swaps the file under a running monster: that was a tiger without force_target, once in a dozen loaded runs.
	var tiger_def: GSNpcDef = game.horde.catalogue.get_npc(&"zhm_tiger")
	var brain_path: String = tiger_def.brain_script_path if tiger_def != null else ""
	var brain_text := FileAccess.get_file_as_string(brain_path)
	_check(brain_text.contains("func force_target") and brain_text.contains("var _forced"), "the generated brain answers force_target", brain_path)
	var again: String = ZzPackBrains.wrapper_for(brain_text.get_slice("\"", 1))
	_check(again == brain_path, "and asking again for the same brain gives the same file", again)
	_check(ZzPackBrains.wrapper_for("res://other_brain.gd") != brain_path, "while another parent, or another template, is another file")

	# Drawn as the body each names (a client has no scene of the pack's): the bear and T-Rex as the brute, the cat as the leaper.
	var brute: Dictionary = ZzZombieView.look_for(&"brute", 0)
	var common: Dictionary = ZzZombieView.look_for(&"common", 0)
	if ZzZombieView.LOOKS.has(&"brute"):
		_check(ZzZombieView.look_for(&"zhm_bear", 0)["body"] == brute["body"] and is_equal_approx(ZzZombieView.look_for(&"zhm_trex", 0)["height"], brute["height"]),
			"the bear and the T-Rex are drawn as the brute")
		_check(ZzZombieView.look_for(&"zhm_tiger", 0)["body"] == ZzZombieView.look_for(&"leaper", 0)["body"] and ZzZombieView.look_for(&"zhm_tiger", 0)["body"] != common["body"],
			"the tiger is drawn as the leaper")
	else:
		# The brute and leaper bodies are zz-mutants': without that pack a monster naming them is drawn as the common zombie.
		_check(ZzZombieView.look_for(&"zhm_bear", 0)["body"] == common["body"] and ZzZombieView.look_for(&"zhm_tiger", 0)["body"] == common["body"],
			"the bear and the tiger are drawn as the common zombie while zz-mutants is absent")
		_check(true, "(the brute and leaper bodies come with zz-mutants)")

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
	var tiger: GSNpcDef = game.horde.catalogue.get_npc(&"zhm_tiger")
	var bear: GSNpcDef = game.horde.catalogue.get_npc(&"zhm_bear")
	var trex: GSNpcDef = game.horde.catalogue.get_npc(&"zhm_trex")
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
	game.horde.spawner.remove(npc.instance_id, GSNpcSpawner.REASON_CLEANUP)


## The game's handles on a brain, answered by a pack monster: told to hunt, lured, and tearing at a barricade.
func _pack_handles(game: ZzGame, player: Object) -> void:
	# The first rounds of a test game come and go in seconds, each laying the map out again and sweeping the horde:
	# begin once one is in play.
	var guard := 0
	while game.phase != ZzGame.Phase.PLAY and guard < 64 * 60:
		game.simulate(1.0 / 64.0)
		guard += 1
	player.health.invulnerable = true
	for n: GSNpcInstance in game.horde.spawner.npcs_near(Vector3.ZERO, 10000.0):
		game.horde.spawner.remove(n.instance_id, GSNpcSpawner.REASON_CLEANUP)
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

	game.horde.spawner.remove(tiger.instance_id, GSNpcSpawner.REASON_CLEANUP)
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
	for n: GSNpcInstance in [lured, plain]:
		game.horde.spawner.remove(n.instance_id, GSNpcSpawner.REASON_CLEANUP)


## A monster of [param kind] at least [param min_apart] metres from [param from], on the first spot the map lets one stand.
func _spawn_far(game: ZzGame, kind: StringName, from: Vector3, min_apart: float) -> GSNpcInstance:
	for d: float in [40.0, 34.0, 28.0, min_apart + 1.0]:
		for dir: Vector3 in [Vector3(0, 0, -1), Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0.7, 0, -0.7), Vector3(-0.7, 0, 0.7)]:
			var npc := game.horde.spawn_special(kind, from + dir * d)
			if npc == null:
				continue
			if npc.position().distance_to(from) >= min_apart:
				return npc
			game.horde.spawner.remove(npc.instance_id, GSNpcSpawner.REASON_CLEANUP)
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

## A pack monster's own picture: the Parasite Host's view loads, builds on the game's view, poses every state without
## an error, and where the pack is not scanned the same kind draws as the game's own body.
func _pack_view(linked: bool) -> void:
	var view := ZzPacks.view_for(&"parasite_host") as ZzZombieView
	_check((view != null) == linked, "a pack's own view is made exactly where its pack is scanned", str(view))

	if view != null:
		add_child(view)
		view.build(&"parasite_host", 0)
		var states := [ZzZombieBody.Anim.IDLE, ZzZombieBody.Anim.WALK, ZzZombieBody.Anim.RUN, ZzZombieBody.Anim.ATTACK, ZzZombieBody.Anim.STAGGER, ZzZombieBody.Anim.DEAD]

		for anim: int in states:
			view.present(0.05, anim, 0)

		view.flinch()
		_check(view.get_child_count() > 0 and view.get(&"_skeleton") != null, "the Parasite Host builds a skinned model and poses every state")
		remove_child(view)
		view.free()

	var kept := ZzPacks.views.duplicate()
	ZzPacks.views.clear()
	var fallback := ZzWorldView.view_for(&"parasite_host")
	_check(ZzPacks.view_for(&"parasite_host") == null and fallback != null,
		"with the pack absent its kind is drawn as the game's own body, no error")
	if fallback != null:
		fallback.free()
	ZzPacks.views.merge(kept)


## Damage, health and tuning: the packs' own yml, the cfg yml over it, and the game's weights.
func _check_pack_numbers() -> void:
	# Numbers: the game's damage table is handed to weapon_defs, and the pack's own yml defaults arrive.
	_check(is_equal_approx(_damage_of(&"zz_m4"), 29.0), "a modern weapon carries the pack's damage", "%.1f" % _damage_of(&"zz_m4"))
	_check(is_equal_approx(_damage_of(&"dagger"), 28.0), "a medieval weapon carries the pack's damage", "%.1f" % _damage_of(&"dagger"))
	var tiger: GSNpcDef = ZzNpcs.catalogue(ZzConfig.new()).get_npc(&"zhm_tiger")
	_check(tiger != null and is_equal_approx(tiger.max_health, 520.0) and is_equal_approx(float(tiger.meta.get("damage", 0)), 14.0),
		"a monster's health and damage come from the pack's yml")

	# Tuning: cfg/addon/<pack>/*.yml, name order, a later file wins.
	_write_real("zz_modern_weapons", "90-test.yml", "m4:\n  damage: 77\n")
	_write_real("zz_medieval_weapons", "90-test.yml", "dagger:\n  damage: 41\n")
	_write_real("zz_historical_monsters", "90-test.yml", "tiger:\n  claw:\n    damage: 33.0\n")
	_write("90-test.yml", "monsters:\n  weights:\n    zhm_bear: 0\n")
	var _f1 := ZzPacks.scan()
	ZzWeapons.use_packs()
	_check(is_equal_approx(_damage_of(&"zz_m4"), 77.0), "a modern weapon's damage follows its cfg yml", "%.1f" % _damage_of(&"zz_m4"))
	_check(is_equal_approx(_damage_of(&"dagger"), 41.0), "a medieval weapon's damage follows its cfg yml", "%.1f" % _damage_of(&"dagger"))
	_check_game_tier()
	_check(is_equal_approx(_damage_of(&"zz_sniper"), 125.0), "a weapon the yml does not name keeps its default")
	tiger = ZzNpcs.catalogue(ZzConfig.new()).get_npc(&"zhm_tiger")
	_check(tiger != null and is_equal_approx(float(tiger.meta.get("damage", 0)), 33.0), "a monster's damage follows its cfg yml")
	_check(ZzPacks.monsters.size() == 5 + (1 if FileAccess.file_exists("res://addons/zz_mutants/%s" % ZzPacks.PROVIDER_FILE) else 0) and not ZzPacks.is_pack_kind(&"zhm_bear"), "the game's own yml drops one monster by weight")
	_clean_real()
	_clean()
	var _found := ZzPacks.scan()
	ZzWeapons.use_packs()


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
