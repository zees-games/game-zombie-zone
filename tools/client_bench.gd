extends DotGameClientBench

## Client prediction bench (dot-game's DotGameClientBench): see that class for the flags.
## The practice street with no stand-ins and no horde, so `--bots` is ignored.

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")


func _configure() -> void:
	client_scene = "res://game/zz.tscn"
	forward_action = &"dot_fps_forward"


func _boot_server(_bots_wanted: int, data_dir: String) -> DotNetManager:
	var config := make_server_config(data_dir)
	config.max_players = 16
	var server := DotServer.new()
	server.name = "Server"
	server.config = config
	add_child(server)
	for _i in 60:
		await get_tree().process_frame
		if server.state == DotServer.State.RUNNING:
			break
	var game_config := ZzConfig.new()
	game_config.warmup_seconds = 0.0
	game_config.intermission_seconds = 0.0
	game_config.minimum_players = 0
	game_config.exodus_team = 0
	game_config.start_grace_seconds = 0.0
	game_config.escape_grace_seconds = 0.0
	game_config.wanderer_density = 0.0
	game_config.director_enabled = false
	game_config.map_ids = PackedStringArray(["zz_practice"])
	var game := ZzGame.new()
	game.name = "World"
	game.config = game_config
	game.tick_rate = Engine.physics_ticks_per_second
	add_child(game)
	await get_tree().process_frame
	(load("res://game/zz_module.gd") as GDScript).set("punishments_file", "%s/punishments.json" % data_dir)
	var loaded: DotResult = await server.modules.load_module("res://game/zz_module.gd")
	if not loaded.ok:
		printerr("client_bench server: ", loaded.error)
		return null
	var m: Object = server.modules.get_module("zombiezone")
	return m.get("net") if m != null else null
