extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzController := preload("../game/zz_controller.gd")
const ZzWeapons := preload("../game/zz_weapons.gd")

## The downed rules (`sv_downed_*`): what a downed survivor holds, who may crawl, the holster, and that every end agrees.
## Counts sections AND checks, because a script error aborts a section silently.

const SECTIONS := 3
const CHECKS := 41

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)
const STREET := Vector3(0.0, 0.05, 14.0)

var _sections_entered := 0
var _sections_finished := 0
var _worlds: Array[ZzGame] = []


## A stand-in for the server's link: the values it holds and the signal it raises when one changes.
class FakeLink extends RefCounted:
	signal replicated_cvar_changed(cvar_name: String, value: String)
	var values := {}

	func replicated_cvar(cvar_name: String, fallback: String) -> String:
		return String(values.get(cvar_name, fallback))


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	load("res://game/zz_packs.gd").root = "res://addons"
	_run.call_deferred()


func _run() -> void:
	print("zombiezone downed rules")
	print("")
	await _test_weapon()
	await _test_crawl()
	await _test_replication()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame
	_report_sections(_sections_entered, _sections_finished, SECTIONS, CHECKS)


## A fresh world with one survivor carrying [param gear] on top of the starting kit, set to [param cvars], then downed.
func _downed(cvars: Dictionary, gear: Array = []) -> ZzPlayer:
	var game := await _team(2, _quiet)
	game.survivors()[1].health.invulnerable = true
	var me := game.survivors()[0]
	me.place_at(STREET, 0.0)

	for cvar_name: String in cvars:
		_check(game.downed_rules.set_cvar(cvar_name, str(cvars[cvar_name])), "%s accepts %s" % [cvar_name, cvars[cvar_name]])

	for id: StringName in gear:
		_check(me.weapons.arsenal.give(id).ok, "gives %s" % id)

	_hurt(game, me, 500.0)
	await _sim(game, 0.3)
	return me



func _test_weapon() -> void:
	_section("a downed survivor takes out the weapon the mode asks for")
	var me := await _downed({}, [&"zz_revolver", &"zz_m4"])
	_check(me.is_down(), "down")
	_check(me.held_id() == &"zz_revolver", "secondary (the default) with a secondary gun: the secondary", String(me.held_id()))

	me = await _downed({}, [&"zz_m4"])
	_check(me.held_id() == &"zz_pistol", "secondary with only a primary: the default pistol, not the primary", String(me.held_id()))

	me = await _downed({}, [])
	_check(me.held_id() == &"zz_pistol", "secondary with nothing but the starting kit: the default pistol", String(me.held_id()))

	me = await _downed({"sv_downed_weapon": "primary_in_place"}, [&"zz_m4"])
	_check(me.held_id() == &"zz_m4", "primary_in_place with a primary: it stays in hand", String(me.held_id()))
	_check(me.downed_kind() == &"primary", "and counts as a primary")

	me = await _downed({"sv_downed_weapon": "primary_in_place"}, [])
	_check(me.held_id() == &"zz_pistol", "primary_in_place with no primary: the pistol", String(me.held_id()))

	me = await _downed({"sv_downed_weapon": "pistol_only"}, [&"zz_m4"])
	_check(me.held_id() == &"zz_pistol", "pistol_only: the pistol even with a primary", String(me.held_id()))
	_check(me.weapons.arsenal.carries(&"zz_m4"), "and the primary is still carried")

	var rules := DotDownedRules.new()
	_check(not rules.set_cvar("sv_downed_weapon", "fists") and rules.weapon_mode == &"secondary", "an unknown mode is refused")
	_finished()


func _walk(me: ZzPlayer) -> float:
	var game := _worlds[_worlds.size() - 1]
	var from := STREET + Vector3(0, 0, 4.0)
	me.place_at(from, 0.0)
	me.controller.state.velocity = Vector3.ZERO
	var forward := DotFpsCommand.new()
	forward.move = Vector2(0.0, 1.0)
	me.controller.apply_command(forward)
	await _sim(game, 1.0)
	return me.feet().distance_to(from)


func _stop(me: ZzPlayer, seconds: float) -> void:
	var stop := DotFpsCommand.new()
	me.controller.apply_command(stop)
	await _sim(_worlds[_worlds.size() - 1], seconds)


func _test_crawl() -> void:
	_section("crawling: pistol allowed, primary not, both by cvar; the gun is holstered while crawling")
	var me := await _downed({}, [&"zz_m4"])
	var gone: float = await _walk(me)
	_check(gone > 0.4, "with a pistol the default lets them crawl", "%.2f m" % gone)
	_check(me.is_crawling() and me.downed_pose() == &"crawl", "and the pose is the crawl")
	_check(me.is_holstered() and me.is_held(), "the pistol is holstered while crawling (is_held hides the view model and gates fire)")
	await _stop(me, 1.0)
	_check(not me.is_crawling() and me.downed_pose() == &"propped" and not me.is_holstered(), "stopped: propped on the back with the pistol out again",
		"speed %.2f, ticks %d" % [me.controller.state.velocity.length(), me._crawl_ticks])

	var game := _worlds[_worlds.size() - 1]
	game.downed_rules.set_cvar("sv_downed_holster_crawl", "0")
	var _g: float = await _walk(me)
	_check(me.is_crawling() and not me.is_holstered(), "sv_downed_holster_crawl 0: crawls with the gun still out")
	game.downed_rules.set_cvar("sv_downed_holster_crawl", "1")

	game.downed_rules.set_cvar("sv_downed_crawl_pistol", "0")
	await _stop(me, 0.3)
	var rooted: float = await _walk(me)
	_check(rooted < 0.15 and me.controller.has_modifier(ZzController.BUSY), "sv_downed_crawl_pistol 0: they stay where they fell, rooted", "%.2f m" % rooted)
	_check(not me.is_crawling() and not me.is_holstered(), "and are never drawn crawling or holstered")
	game.downed_rules.set_cvar("sv_downed_crawl_pistol", "1")
	var freed: float = await _walk(me)
	_check(freed > 0.4 and not me.controller.has_modifier(ZzController.BUSY), "turned back on, the root comes off", "%.2f m" % freed)

	me = await _downed({"sv_downed_weapon": "primary_in_place"}, [&"zz_m4"])
	var held: float = await _walk(me)
	_check(held < 0.15 and me.controller.has_modifier(ZzController.BUSY), "with a primary in place they cannot crawl by default", "%.2f m" % held)
	_check(me.is_down() and me.held_id() == &"zz_m4" and not me.is_holstered() and me.downed_pose() == &"propped", "and keep it out, propped")

	game = _worlds[_worlds.size() - 1]
	game.downed_rules.set_cvar("sv_downed_crawl_primary", "1")
	var allowed: float = await _walk(me)
	_check(allowed > 0.4 and me.is_holstered(), "sv_downed_crawl_primary 1: they crawl with it, holstered", "%.2f m" % allowed)
	_finished()


func _test_replication() -> void:
	_section("the rules replicate: a follower agrees with the server and draws the same pose")
	var server := DotDownedRules.new()
	var link := FakeLink.new()
	var names: Array[String] = []
	var flags: Array[int] = []
	var record := func(cvar_name: String, _default: String, _desc: String, f: int) -> Variant:
		names.append(cvar_name)
		flags.append(f)
		return null
	var _made := server.bind_cvars(record, 7)
	_check(names.size() == 4 and names.all(func(n: String) -> bool: return n.begins_with("sv_downed_")), "four sv_downed_ cvars are bound", str(names))
	_check(flags.all(func(f: int) -> bool: return f == 7), "all with the flags given (the game passes REPLICATED)")

	var client := DotDownedRules.new()
	_check(client.follow_cvars(link), "a client follows the link")
	link.values = {"sv_downed_weapon": "primary_in_place", "sv_downed_crawl_primary": "1", "sv_downed_crawl_pistol": "0", "sv_downed_holster_crawl": "0"}
	for cvar_name: String in link.values:
		link.replicated_cvar_changed.emit(cvar_name, link.values[cvar_name])
		var _s := server.set_cvar(cvar_name, link.values[cvar_name])

	_check(client.describe() == server.describe(), "every change reaches the client", str(client.describe()))
	var same := true
	for moving in [false, true]:
		for kind: StringName in [&"pistol", &"primary"]:
			var pose := server.pose_for(moving, kind)
			same = same and pose == client.pose_for(moving, kind) and server.holstered(pose) == client.holstered(pose) and server.clip_for(pose) == client.clip_for(pose)
	_check(same, "and both draw every pose, holster and clip the same")
	_check(client.pose_for(true, &"pistol") == &"propped" and client.pose_for(true, &"primary") == &"crawl", "the pose follows the replicated crawl rules")

	var late := DotDownedRules.new()
	var _joined := late.follow_cvars(link)
	_check(late.describe() == server.describe(), "a client that joins later is given the current values")
	link.replicated_cvar_changed.emit("sv_downed_weapon", "bogus")
	link.replicated_cvar_changed.emit("sv_other", "1")
	_check(late.describe() == server.describe(), "a junk value or another cvar changes nothing")
	_check(not DotDownedRules.new().follow_cvars(null), "no link is refused")
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


func _aim(player: ZzPlayer, target: Vector3) -> void:
	var look := target - player.eye_position()
	var command := DotFpsCommand.new()
	command.yaw = rad_to_deg(atan2(-look.x, -look.z))
	command.pitch = clampf(rad_to_deg(asin(clampf(look.normalized().y, -1.0, 1.0))), -89.0, 89.0)
	player.controller.apply_command(command)
	player.controller.state.yaw = command.yaw
	player.controller.state.pitch = command.pitch


func _hurt(game: ZzGame, player: ZzPlayer, amount: float) -> void:
	var hit := DotDamage.make(0, player.entity_id, amount, game.combat.damage_type(&"strike"))
	hit.tick = game.current_tick()
	var _applied := game.combat.apply_damage(hit)


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1




func _team(count: int, configure: Callable = Callable(), bots: bool = false) -> ZzGame:
	var game := await _world(configure)

	for i in count:
		var player := game.add_player(StringName("u%d" % (100 + i)), "Survivor%d" % i)
		player.is_bot = bots

	game.start()
	await _sim(game, 0.25)
	return game
