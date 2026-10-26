extends DotGameNetchaosServer

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")

## Zombie Zone's side of `tools/netchaos.sh` (dot-game's DotGameNetchaosServer): the practice street, no stand-ins, no horde.

var _game: ZzGame = null


func _configure() -> void:
	map_id = "zz_practice"


func _boot_world() -> void:
	if not (await boot_server()).ok:
		return
	var config := ZzConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.exodus_team = 0
	config.start_grace_seconds = 0.0
	config.escape_grace_seconds = 0.0
	config.wanderer_density = 0.0
	config.director_enabled = false
	config.map_ids = PackedStringArray([map_id])
	_game = ZzGame.new()
	_game.name = "World"
	_game.config = config
	_game.tick_rate = Engine.physics_ticks_per_second
	add_child(_game)
	await get_tree().process_frame
	(load("res://game/zz_module.gd") as GDScript).set("punishments_file", "%s/punishments.json" % data_dir)
	var loaded: DotResult = await server.modules.load_module("res://game/zz_module.gd")
	if not loaded.ok:
		printerr("netchaos server: ", loaded.error)
		return
	module = server.modules.get_module("zombiezone")
	if solid != "":
		var cv: DotConVar = server.console.find_cvar("mp_solidplayers")
		if cv != null:
			cv.force_set(solid)


func _players() -> Array:
	return _game.survivors()
