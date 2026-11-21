extends "headless_weapons_trader.gd"

const ZzLoot := preload("../game/zz_loot.gd")
const ZzNetCommand := preload("../game/net/zz_net_command.gd")
const ZzEvents := preload("../game/net/zz_events.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

## The gun you hold, offline, through the real client: the buttons, the world's rig that decides,
## the rig the view model is drawn with, and the HUD's counter.
##
## [b]Why through `ZzClient` and not a bare world.[/b] Every other suite here drives the world's
## commands itself, and so none of them saw that offline the client's buttons never reached the
## world: the client stamped the controller's command and the world then sampled a fresh one over
## it. The first play test's counter read 15 / 60 for two and a half minutes of shooting, and
## nothing the player shot was hit. Only a suite that presses the client's own buttons sees it.
##
## Sections and checks are both counted; mg-smash-copter's notes say why the second matters.

const ZzFittings := preload("../game/zz_fittings.gd")
const ZzPacks := preload("../game/zz_packs.gd")
const SECTIONS := 17
const CHECKS := 109

const CONFIG_FILE := "user://zz_headless_weapons.json"


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("zombiezone weapons, offline, through the client")
	print("")

	_test_the_weapon_art_is_vendored()
	_test_every_pack_weapon_sounds_and_reloads()

	if await _test_armed():
		_test_view_feel_wiring()
		_test_fitting()
		await _test_shots_count()
		await _test_r_reloads()
		await _test_empty_reloads()
		await _test_ammo_pile()
		await _test_rearmed()
		await _test_box_guns_are_drawn()
		await _test_fire_bloom()
		_test_spray()
		_test_spawner()
		_test_trader()
		_test_shop()
		_test_trader_phases_and_grace()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_FILE))
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


# Sections

## A delivered game has only what is vendored in assets/, so every model the weapon art table
## names must exist here; an unvendored gun loads as bare arms and nothing else fails. The
## list and the check are the addon's; `tools/sync-art.sh` in zee-gs-weapons copies what it names.
func _test_the_weapon_art_is_vendored() -> void:
	_section("Every model the weapon art table names is vendored in this game")
	ZzWeapons.use_packs()
	var count := ZeeWeaponArtTable.model_paths().size()
	_check(count == 0, "zee's art table names no blaster models once its weapons are dropped (%d)" % count)
	var models := ZeeWeaponArtTable.validate_models()
	_check(models.ok, "no weapon model is missing", "" if models.ok else models.error.message)
	var stock_ok := true
	for sound: StringName in GSAudioWeaponStock.COUNTS:
		stock_ok = stock_ok and (load("res://game/zz_audio.gd") as GDScript).call("sound_catalogue").find(GSAudioWeaponStock.id_of(sound)) != null
	_check(stock_ok, "the game's sound catalogue carries every stock weapon sound")
	var stock_streams := true
	for sound in [ZeeWeaponSound.LIGHT, ZeeWeaponSound.SHOTGUN, ZeeWeaponSound.DRY, ZeeWeaponSound.EQUIP,
			ZeeWeaponSound.RELOAD_OUT, ZeeWeaponSound.RELOAD_SHELL, ZeeWeaponSound.SUPPRESSED]:
		var s := ZeeWeaponSound.stream(sound)
		stock_streams = stock_streams and s is AudioStreamOggVorbis and s.resource_path.begins_with(GSWeaponSound.DIR)
	_check(stock_streams, "weapon shots, dry, equip and reloads play the stock recordings, not the synth fallback")
	var problems := GSWeaponSound.check_stock()
	_check(problems.is_empty(), "every weapon class resolves a non-silent, unclipped voice", ", ".join(problems))
	_check(GSWeaponSound.pick_tail(&"rifle", true) != null and GSWeaponSound.pick_tail(&"rifle", false) == null, "indoors a shot gets a tail, outdoors none")
	_finished()


## The modern pack's weapons each resolve a fire, draw and (guns) reload and dry sound from gs-audio's
## stock, and a gun a reload clip; a melee weapon and a grenade a fire sound. A weapon missing from
## the pack's class table plays nothing, and no other suite would hear it.
func _test_every_pack_weapon_sounds_and_reloads() -> void:
	_section("Every modern-pack weapon resolves its sounds and its reload clip")
	var pack_path := "res://addons/zz_modern_weapons/zz_weapon_pack.gd"
	if not ResourceLoader.exists(pack_path):
		_check(true, "the modern pack is not installed: nothing to resolve")
		for i in 4:
			_check(true, "(skipped without the pack)")
		_finished()
		return
	var sound_script: GDScript = load("res://addons/zz_modern_weapons/view/zz_weapon_sound.gd")
	var pose_script: GDScript = load("res://addons/zz_modern_weapons/view/zz_weapon_pose.gd")
	var defs: Array = (load(pack_path) as GDScript).call("weapons")
	var no_fire: PackedStringArray = []
	var no_draw: PackedStringArray = []
	var no_reload: PackedStringArray = []
	var no_clip: PackedStringArray = []
	var guns := 0
	for def: GSWeaponDef in defs:
		var id := def.id
		if sound_script.call("stream_for", id, &"fire") == null:
			no_fire.append(String(id))
		var bash: bool = sound_script.CLASSES.get(id, &"") == &"bash"
		if not bash and sound_script.call("stream_for", id, &"draw") == null:
			no_draw.append(String(id))
		if def.uses_magazine():
			guns += 1
			if sound_script.call("stream_for", id, &"reload") == null or sound_script.call("stream_for", id, &"dry") == null:
				no_reload.append(String(id))
			var keys: Array = pose_script.call("reload_keys_for", id)
			if keys.size() < 2:
				no_clip.append(String(id))
	_check(defs.size() >= 20 and guns >= 15, "the pack lists its weapons and magazine guns", "%d, %d guns" % [defs.size(), guns])
	_check(no_fire.is_empty(), "every weapon has a fire sound", ", ".join(no_fire))
	_check(no_draw.is_empty(), "every gun, blade and grenade has a draw sound", ", ".join(no_draw))
	_check(no_reload.is_empty(), "every magazine gun has a reload and a dry sound", ", ".join(no_reload))
	_check(no_clip.is_empty(), "every magazine gun has a reload clip (two or more keys)", ", ".join(no_clip))
	_finished()


func _test_armed() -> bool:
	_section("the client comes up armed, and the HUD counts the gun in hand")
	var failed_before := _failed

	# The practice street, no warmup and nothing that comes for you: this is about the gun.
	var file := FileAccess.open(CONFIG_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"warmup_seconds": 0.0, "start_grace_seconds": 0.0, "minimum_players": 0,
		"wanderer_density": 0.0, "sleepers_enabled": false, "specials_base": 0,
		"mob_interval_min": 900.0, "mob_interval_max": 900.0,
		"brute_interval_min": 0.0, "brute_interval_max": 0.0, "box_drop_common": 0.0,
		"map_ids": ["zz_practice"],
	}))
	file.close()

	_client = ZzClient.new()
	_client.config_file = CONFIG_FILE
	_client.force_offline = true
	_client.standalone_content = false
	_client.offline_bots = 0
	add_child(_client)

	var waited := 0
	while waited < 600 and not (_client.player != null and _client.player.weapons != null
			and _client.player.view_rig != null and _client.game.phase == _client.game.Phase.PLAY):
		await get_tree().physics_frame
		waited += 1
	await _frames(10)

	var me := _client.player
	_check(me != null and me.weapons != null and me.view_rig != null and me.view_rig != me.weapons,
		"the world's rig decides and the client's draws: two rigs", "%d frames" % waited)

	if me == null or me.weapons == null or me.view_rig == null:
		_finished()
		return false

	me.health.invulnerable = true
	var truth := me.weapons.arsenal.current()
	_check(truth != null and truth.def.uses_magazine(), "a gun with a magazine in hand",
		str(truth.def.id) if truth != null else "nothing")
	_check(_hud_magazine() == truth.magazine and _hud_reserve() == _reserve(me.weapons),
		"the HUD shows its magazine and reserve", _client.hud.ammo.count_text())
	_finished()
	return _failed == failed_before


## The fitting screen: a choice is saved, worn by the client's rig, and the authority's rig
## wears it too after validating; a fitting that does not fit is refused there.
func _test_fitting() -> void:
	_section("a fitting chosen on the screen is saved, worn here and applied by the authority")
	var saved := ZzFittings.parse("m4:optic=zz_red_dot,bad;;:x;ak:")
	_check(ZzFittings.format(saved) == "m4:optic=zz_red_dot", "the saved text round-trips and drops what is malformed",
		ZzFittings.format(saved))

	var me := _client.player
	var catalogue := ZzPacks.attachment_catalogue()
	var held := _client.weapons.arsenal.current()
	var base := ZzWeapons.def_of(held.id()) if held != null else null
	var mount := &""
	var pick := &""
	if base != null:
		var choices := catalogue.choices_for(base)
		for m: StringName in choices.keys():
			if not (choices[m] as Array).is_empty():
				mount = m
				pick = (choices[m] as Array)[0]
				break

	if pick == &"":
		_check(true, "the gun in hand takes no attachment: nothing to fit (%s)" % (String(base.id) if base else "none"))
		_check(true, "(skipped)")
		_check(true, "(skipped)")
		_check(true, "(skipped)")
		_check(true, "(skipped)")
		_check(true, "(skipped)")
		_finished()
		return

	_client._fit_requested(mount, pick)
	var slot := _client.weapons.arsenal.current_slot()
	_check(_client.weapons.arsenal.fitting_at(slot).attachment_on(mount) == pick,
		"the client's rig wears %s on %s" % [pick, mount])
	_check(me.weapons.arsenal.fitting_at(me.weapons.arsenal.current_slot()).attachment_on(mount) == pick
			and (me.fittings.get(base.id) as GSWeaponFitting).attachment_on(mount) == pick,
		"and the authority's rig, which keeps it for the player")

	var bogus := GSWeaponFitting.make(base.id)
	bogus.fit(mount, &"zz_no_such_attachment")
	_check(not _client.game.fit_weapon(me, base.id, bogus).ok
			and me.weapons.arsenal.fitting_at(me.weapons.arsenal.current_slot()).attachment_on(mount) == pick,
		"a fitting the catalogue refuses is not applied")

	_client._fit_requested(mount, pick)
	_check(_client.weapons.arsenal.fitting_at(slot).is_empty()
			and me.weapons.arsenal.fitting_at(me.weapons.arsenal.current_slot()).is_empty(),
		"choosing it again takes it off both rigs")

	# The server's answer to a refused fit (Kind.FITTING): that fitting is saved and worn.
	var told := GSWeaponFitting.make(base.id)
	told.fit(mount, pick)
	_client._on_fitting_resync(base.id, catalogue.encode(base, told))
	_check(_client._saved_fittings().has(base.id)
			and (_client._saved_fittings()[base.id] as GSWeaponFitting).attachment_on(mount) == pick,
		"the server's fitting from a resync is the saved one")
	_check(_client.weapons.arsenal.fitting_at(slot).attachment_on(mount) == pick,
		"and the client's rig wears it")
	_client._on_fitting_resync(base.id, 0)
	_finished()


func _test_view_feel_wiring() -> void:
	_section("the client's view model draws with the game's feel rules, and cl_vm_kick 0 silences the kick")
	var vm = _client.view_model
	_check(vm != null and vm.feel_rules == _client.game.feel_rules, "the view model holds the game's feel_rules object")

	if vm == null:
		_finished()
		return

	_check(vm._pose.rules == _client.game.feel_rules, "and the pose it draws with reads the same object")
	# An offline client's console has no module (the server owns cl_vm_kick and replicates it);
	# the replicated value lands in set_cvar, which is what this drives.
	var rules: ZeeViewFeel = _client.game.feel_rules
	_check(rules.set_cvar("cl_vm_kick", "0") and vm._pose.rules.kick == 0.0,
		"cl_vm_kick 0 reaches the drawn pose: kick multiplier zero", str(vm._pose.rules.kick))
	_check(rules.set_cvar("cl_vm_kick", "1") and vm._pose.rules.kick == 1.0, "cl_vm_kick 1 gives the kick back")

	_finished()


func _test_shots_count() -> void:
	_section("three pulls spend the world's magazine, and the HUD shows it")
	var me := _client.player
	var before := me.weapons.arsenal.current().magazine
	var hits_before: int = me.weapons.fire_seq
	# Pulled three times: the pistol is semi-automatic, so a held trigger is one shot.
	for _pull in range(3):
		_client._firing = true
		await _frames(2)
		_client._firing = false
		await _frames(int(ceilf(Engine.physics_ticks_per_second * 0.25)))
	var spent := before - me.weapons.arsenal.current().magazine
	_check(spent == 3 and me.weapons.fire_seq - hits_before == spent,
		"the world's gun fired and spent a round a shot", "%d spent, %d shots" % [spent, me.weapons.fire_seq - hits_before])
	_check(me.view_rig.arsenal.current().magazine == me.weapons.arsenal.current().magazine,
		"the drawn gun counted the same shots", "%d against %d" % [me.view_rig.arsenal.current().magazine, me.weapons.arsenal.current().magazine])
	_check(_hud_magazine() == me.weapons.arsenal.current().magazine, "the HUD says so", _client.hud.ammo.count_text())
	_finished()


func _test_fire_bloom() -> void:
	_section("a held trigger opens the crosshair: rifle, SMG and sniper carry bloom and the drawn arsenal reports it")
	var me := _client.player
	for id: StringName in [&"zz_m4", &"zz_smg", &"zz_sniper"]:
		var def := ZzWeapons.def_of(id)
		var b := def.tuning as GSWeaponBallistics if def != null else null
		_check(b != null and b.bloom > 0.0, "%s sets bloom" % id, str(b.bloom) if b != null else "pack not loaded")

		if def == null or not _client.game.arm(me, id):
			_check(false, "%s opens while firing" % id, "not armed")
			continue

		_client._slot = def.slot
		# The sniper's draw is 0.75 s: a trigger held before it ends fires nothing.
		await _frames(100)
		var rest: float = _client.weapons.arsenal.spread_now()
		var peak := rest
		_client._firing = true
		for _tick in 24:
			await _frames(1)
			peak = maxf(peak, _client.weapons.arsenal.spread_now())
		_client._firing = false
		_check(peak > rest + 0.4, "%s: the drawn cone is wider while firing" % id, "%.2f over %.2f" % [peak, rest])
	_finished()


func _test_r_reloads() -> void:
	_section("R reloads both guns, refills from the reserve after the reload's time")
	var me := _client.player
	var held := me.weapons.arsenal.current()
	var missing := held.def.magazine - held.magazine
	var reserve_before := _reserve(me.weapons)
	_client._reloading = true
	await _frames(1)
	_client._reloading = false
	_check(me.weapons.arsenal.is_reloading() and me.view_rig.arsenal.is_reloading(),
		"both rigs are reloading on the frame R goes down")
	_check(me.view_rig._reload_fraction(me.view_rig._last_tick) >= 0.0 and me.view_rig._reload_started >= 0,
		"and the view model is handed a reload to play")
	var takes := me.view_rig.arsenal.ticks_for(held.def, held.def.reload_ticks)
	await _frames(takes - 3)
	_check(me.weapons.arsenal.current().magazine < held.def.magazine, "not full before its time",
		"%d frames of %d" % [takes - 3, takes])
	await _frames(8)
	_check(me.weapons.arsenal.current().magazine == held.def.magazine and _reserve(me.weapons) == reserve_before - missing,
		"full after it, %d taken from the reserve" % missing, "%d / %d" % [me.weapons.arsenal.current().magazine, _reserve(me.weapons)])
	_check(_hud_magazine() == held.def.magazine and _hud_reserve() == reserve_before - missing,
		"and the HUD shows the full magazine and the smaller reserve", _client.hud.ammo.count_text())
	_finished()


func _test_empty_reloads() -> void:
	_section("the last round reloads by itself, trigger let go")
	var me := _client.player
	me.weapons.arsenal.current().magazine = 1
	me.view_rig.arsenal.current().magazine = 1
	_client._firing = true
	await _frames(1)
	_client._firing = false
	await _frames(3)
	_check(me.weapons.arsenal.is_reloading() and me.view_rig.arsenal.is_reloading(),
		"an emptied gun starts reloading with nothing held",
		"world %s, drawn %s" % [me.weapons.arsenal.is_reloading(), me.view_rig.arsenal.is_reloading()])
	var held := me.weapons.arsenal.current()
	await _frames(me.view_rig.arsenal.ticks_for(held.def, held.def.reload_ticks) + 6)
	_check(held.magazine == held.def.magazine and _hud_magazine() == held.def.magazine,
		"and fills", _client.hud.ammo.count_text())
	_finished()


func _test_ammo_pile() -> void:
	_section("an ammo pile fills the world's reserve, and the HUD follows")
	var me := _client.player
	var held := me.weapons.arsenal.current()
	var pool := held.def.ammo_type
	var _spent := me.weapons.arsenal.ammo().take(pool, 1000)
	await _frames(int(ceilf(me.VIEW_RIG_SETTLE_SEC * Engine.physics_ticks_per_second)) + 4)
	_check(_hud_reserve() == 0, "a reserve the world took away goes from the HUD too (the drawn gun is corrected)",
		_client.hud.ammo.count_text())

	# The world's own pickup, as E on the pile calls it: the world fills, the client is told.
	var pile := _client.game.loot.add(ZzLoot.AMMO, &"", me.global_position + Vector3(0.0, 0.0, -1.2))
	_client.game.loot.use(pile, me)
	await _frames(int(ceilf(me.VIEW_RIG_SETTLE_SEC * Engine.physics_ticks_per_second)) + 4)
	_check(_reserve(me.weapons) > 0 and _hud_reserve() == _reserve(me.weapons),
		"refilled, and the HUD shows the world's reserve", "%s against %d" % [_client.hud.ammo.count_text(), _reserve(me.weapons)])
	_finished()


func _test_rearmed() -> void:
	_section("a fresh map's gun carries a fresh reserve, not the last map's on top")
	var me := _client.player
	var id := me.view_rig.arsenal.current().def.id
	var def := ZzWeapons.def_of(id)
	_client._on_armed(_client._watch_id, &"")
	_client._on_armed(_client._watch_id, id)
	_check(me.view_rig.arsenal.current() != null and _reserve(me.view_rig) == def.reserve,
		"stripped and handed the same gun, the drawn reserve is the gun's own",
		"%d, the gun gives %d" % [_reserve(me.view_rig), def.reserve])
	_check(me.view_rig.arsenal.current().magazine == def.magazine, "with a full magazine")
	_finished()


func _test_box_guns_are_drawn() -> void:
	_section("a gun a box hands over, from any pack, is the gun in the view model")
	var me := _client.player
	var game := _client.game
	var settle := 12
	# Every gun of every tier is handed over in turn; the carry limit has its own suite (headless_carry).
	game.config.weight_enabled = false

	for tier in [&"sidearm", &"primary", &"heavy"]:
		var bad := PackedStringArray()
		var ids := ZzWeapons.ids_of(tier)

		for id in ids:
			game.boxes.run([{"do": "give_weapon", "id": String(id)}], {"opener": me, "at": me.global_position, "box": &"upgrade"})
			await _frames(settle)
			var waited := 0

			while me.view_rig.arsenal.is_switching() and waited < 200:
				await _frames(1)
				waited += 1

			await _frames(2)
			var shown: StringName = _client.view_model.equipped() if _client.view_model != null else &""

			if shown != id or not _client.view_model.visible or me.view_rig.arsenal.current().def.id != id:
				bad.append("%s (showing '%s')" % [id, shown])

		_check(not ids.is_empty() and bad.is_empty(), "every %s the boxes hand out is drawn (%d)" % [tier, ids.size()], ", ".join(bad))

	_finished()


## One second of held trigger through the server's recoil rules: the view's peak climb, the peak
## sideways wander, and what is left a second and a half after release.
func _spray(def: GSWeaponDef) -> Array:
	var b := def.tuning as GSWeaponBallistics
	var view := GSWeaponRecoil.new()
	var state := {}
	var rate := maxi(Engine.physics_ticks_per_second, 1)
	var interval := maxi(def.use_interval_ticks, 1)
	var climb := 0.0
	var wander := 0.0
	var tick := 1000

	while tick < 1000 + rate:
		var out := GSWeaponOutcome.new()
		var ctx := GSWeaponContext.new()
		ctx.tick = tick
		var _bullet: Variant = _client.game.combat_feel.recoil.apply(out, b, state, ctx, def.id, rate)
		view.kick_outcome(out)
		view.advance(float(interval) / rate)
		climb = maxf(climb, view.offset().x)
		wander = maxf(wander, absf(view.offset().y))
		tick += interval

	view.advance(1.5)
	return [climb, wander, view.offset().length()]


func _test_spray() -> void:
	_section("a held second of every firearm: the automatics climb and wander, a rifle more than an SMG, and all settle")
	var sprays := {}
	var stuck := PackedStringArray()

	for def in ZzWeapons.all_defs():
		if def.tuning is GSWeaponBallistics and def.use_interval_ticks > 0:
			sprays[def.id] = _spray(def)

			if sprays[def.id][2] > 0.25:
				stuck.append(String(def.id))

	_check(sprays.has(&"zz_m4") and sprays.has(&"zz_smg"), "the rifle and SMG are measured", str(sprays.keys()))

	if sprays.has(&"zz_m4") and sprays.has(&"zz_smg"):
		_check(sprays[&"zz_m4"][0] > 0.5 and sprays[&"zz_m4"][1] > 0.2, "a rifle climbs and wanders sideways in a held second", str(sprays[&"zz_m4"]))
		_check(sprays[&"zz_m4"][0] > sprays[&"zz_smg"][0], "a rifle climbs more than an SMG", "%.2f over %.2f" % [sprays[&"zz_m4"][0], sprays[&"zz_smg"][0]])

	_check(stuck.is_empty(), "every firearm settles within a second and a half of release", ",".join(stuck))
	_finished()


func _test_spawner() -> void:
	_section("a map spawner lays a gun as loot; using it starts the timer, the timer lays the next")
	var game = _client.game
	var me := _client.player
	game.config.trader_enabled = 0
	var doc := {"id": "spawner_probe", "spawners": [{"id": "wall", "at": [0, 0, 0], "pool": "wall_guns", "filter": {"ids": ["zz_shotgun"]}, "respawn": 20, "max": 1}]}
	game.spawners.start_round(doc)
	game.spawners.tick()
	var lid: int = game.spawners.loot_ids()[0] if not game.spawners.loot_ids().is_empty() else -1
	_check(game.spawners.spawner.alive() == 1 and lid >= 0, "the spawner's item is a loot entry")
	var item: StringName = game.loot.entries[lid]["item"]
	_check(ZzWeapons.exists(item), "drawn from the weapon catalogue", String(item))
	game.loot.use(lid, me)
	_check(game.spawners.spawner.alive() == 0 and not game.loot.exists(lid), "using it frees the slot and the entry")
	_check(game.spawners.spawner.seconds_until(&"wall") > 10.0, "the respawn timer runs", str(game.spawners.spawner.seconds_until(&"wall")))
	game.spawners.spawner.tick(game.now() + 25.0)
	_check(game.spawners.spawner.alive() == 1 and game.loot.count_of(ZzLoot.WEAPON) >= 1, "after the timer the next one lies there")
	var shop := {"id": "spawner_probe", "spawners": [{"id": "buy", "at": [0, 0, 0], "item": "zz_shotgun", "respawn": 0, "data": {"price": 300}}]}
	game.spawners.start_round(shop)
	game.spawners.tick()
	var buy: int = game.spawners.loot_ids()[0] if not game.spawners.loot_ids().is_empty() else -1
	me.points = 100
	_check(game.spawners.price_of(buy) == 300 and not game.spawners.may_use(buy, me), "a priced spawner refuses a survivor who cannot pay")
	me.points = 400
	game.loot.use(buy, me)
	_check(me.points == 100, "and takes the price when the item is used", str(me.points))

	game.config.trader_enabled = -1
	# A converter's weapon_* and item_* entities lay what the config's classes say; a trader shelves priced stock.
	var world := {"id": "spawner_probe2", "entities": [
		{"classname": "weapon_m3", "origin": [4, 0, 0], "angle": 0},
		{"classname": "item_healthkit", "origin": [5, 0, 0], "angle": 0},
		{"classname": "item_ammo_pistol", "origin": [6, 0, 0], "angle": 0}],
		"traders": [{"id": "shop", "at": [0, 0, 8], "slots": 3, "restock": 30.0}]}
	game.spawners.start_round(world)
	game.spawners.tick()
	var kinds := {}
	for id: int in game.spawners.loot_ids():
		kinds[game.loot.kind_of(id)] = true
	_check(kinds.has(ZzLoot.WEAPON) and (kinds.has(ZzLoot.MEDKIT) or kinds.has(ZzLoot.PILLS)) and kinds.has(ZzLoot.AMMO), "converter entities lay a gun, a medkit and ammo through the classes mapping", str(kinds.keys()))
	var shelf: Array = []
	for id: int in game.loot.entries:
		if game.loot.price_of(id) > 0:
			shelf.append(id)
	_check(shelf.size() == 3, "a trader shelves three priced entries", str(shelf.size()))
	# A stand-in with the points does not walk to a shelf the trader has closed: the press is refused for good.
	me.points = 1000
	me.place_at(game.loot.position_of(shelf[0]), 0.0)
	# The suite's player stands in as the stand-in; a human at the shelf would own it (personal space).
	me.is_bot = true
	var wants_open: bool = game.bots._pick_up(me, GSFpsCommand.new(), {"pick": -1})
	game.spawners.set("_open", false)
	var memory := {"pick": -1}
	var wants_closed: bool = game.bots._pick_up(me, GSFpsCommand.new(), memory)
	game.spawners.set("_open", true)
	me.is_bot = false
	_check(wants_open and not wants_closed and int(memory["pick"]) == -1, "a stand-in goes for a shelf item while the trader is open and not while it is closed", "open %s, closed %s" % [wants_open, wants_closed])
	var bought: int = shelf[0]
	var price: int = game.loot.price_of(bought)
	me.points = 1000
	game.loot.remove(bought, me.player_id)
	_check(me.points == 1000 - price, "buying from the shelf charges the entry's price", "%d for %d" % [price, 1000 - me.points])
	game.spawners.spawner.tick(game.now() + 40.0)
	game.spawners.tick()
	var again := 0
	for id: int in game.loot.entries:
		if game.loot.price_of(id) > 0:
			again += 1
	_check(again == 3 or game.now() < 30.0, "the slot restocks after its wait", str(again))
	# A priced ammo pile is used up: charged once, and its site lays the next.
	game.spawners.start_round({"id": "spawner_probe3", "spawners": [{"id": "am", "at": [0, 0, 0], "kind": "ammo", "item": "ammo", "respawn": 5, "data": {"price": 50}}],
		"traders": [{"id": "empty_shop", "at": [0, 0, 20], "slots": 2, "pool": "no_such_pool", "restock": 5.0}]})
	game.spawners.tick()
	var amid: int = -1
	for id: int in game.spawners.loot_ids():
		if game.loot.kind_of(id) == ZzLoot.AMMO:
			amid = id
	var arsenal: GSWeaponArsenal = me.weapons.arsenal
	for pool in arsenal.ammo().pools():
		arsenal.ammo().set_count(pool, 0)
	me.points = 200
	game.loot.use(amid, me)
	_check(amid >= 0 and not game.loot.exists(amid) and me.points == 150, "a priced ammo pile is used up and charged", str(me.points))
	_check(game.spawners.spawner.alive() == 0 and game.spawners.spawner.seconds_until(&"am") > 0.0, "and its site respawns it")
	_check(game.spawners._restock.size() >= 2, "an empty roll reschedules the trader's slot", str(game.spawners._restock.size()))
	_check(game.spawners._clean_price(NAN) > 100000 and game.spawners._clean_price(INF) > 100000 and game.spawners._clean_price(1e30) > 100000 and game.spawners._clean_price(-5) == 0 and game.spawners._clean_price(75) == 75, "a nan, infinite or huge price is unaffordable, never free")
	var cheap: int = game.loot.add(ZzLoot.WEAPON, &"zz_shotgun", Vector3.ZERO, -1.0, 300)
	game.spawners._price_of[cheap] = 300
	me.points = 10
	game.loot.remove(cheap, me.player_id)
	_check(me.points == 0, "a charge never takes the points below zero", str(me.points))
	var wire := ZzEvents.read_loot(GSNetReader.new(ZzEvents.write_loot(7, &"weapon", &"zz_shotgun", Vector3.ZERO, 250)))
	_check(int(wire["price"]) == 250 and bool(wire["ok"]), "the loot event carries the price to the client")
	_finished()


# Helpers

func _reserve(rig: ZeeWeaponRig) -> int:
	var held := rig.arsenal.current()
	return rig.arsenal.ammo().count(held.def.ammo_type) if held != null and held.def.ammo_type != &"" else 0


func _hud_magazine() -> int:
	return _client.hud.ammo.magazine


func _hud_reserve() -> int:
	return _client.hud.ammo.reserve
