extends Node

const ZzConfig := preload("zz_config.gd")
const ZzGame := preload("zz_game.gd")
const ZzSimHost := preload("zz_sim_host.gd")

## The authoritative game of a solo session in its own process (`--sim_host 1`, [code]zz_sim_host.gd[/code]): a
## loopback dedicated server the solo client spawns and joins, so the simulation never runs on the render thread.
## The same world, [DotServer] and [code]zz_module.gd[/code] a public server runs, in the order `dedicated` boots them.
## Launch flags (after `--`): `--port N --bots N --ready PATH --config_file PATH --cvar name=value` plus the client's
## `--zz-*` config. It writes PATH once it accepts players, and quits a few seconds after its player left.

const CHANNEL := "zz.sim_server"
const REPORT_SEC := 5.0
const GONE_SEC := 5.0
const NEVER_SEC := 120.0
## Solo's own cap on a weak machine ([constant ZzClient.WEAK_HARDWARE_BOTS]): the same stand-ins either way.
const WEAK_HARDWARE_BOTS := 7
## A bench's server half: keeps its crowd round the player (only when `--bench_crowd=N` is given).
const BENCH_HELPER := "res://tools/bench_sim_crowd.gd"

var world: ZzGame = null
var _server: DotServer = null
var _joined := false
var _alone_sec := 0.0
var _since_check := 0.0


func _ready() -> void:
	var port := int(ZzSimHost.arg("--port"))
	var bots := int(ZzSimHost.arg("--bots"))
	if port <= 0:
		_die("no --port")
		return
	var data := "user://sim_host"
	var _made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(data))
	var tick_rate := int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))

	# The server first (whose tick rate the world reads), then the world, then the module: dedicated's order.
	var config := server_config(port, tick_rate, data)
	var server := DotServer.new()
	server.name = "Server"
	server.config = config
	server.config_file = ""
	server.auto_boot = false
	add_child(server)
	var booted: DotResult = await server.boot()
	if not booted.ok:
		_die("boot: %s" % booted.error.message)
		return

	# The solo client's config layers (its file, the environment, the forwarded `--zz-*`): both ends read the same numbers.
	var game_config := ZzConfig.new()
	var config_file := ZzSimHost.arg("--config_file")
	var loaded := ZzConfig.boot(game_config, config_file if config_file != "" else "user://cfg/zombiezone.json")
	if not loaded.ok:
		_die("config: %s" % loaded.error.message)
		return
	# Solo seats at most this many stand-ins on a weak machine; the module's bot_max is the same cap.
	if bots > WEAK_HARDWARE_BOTS and OS.get_processor_count() <= 4 and (game_config.bot_max <= 0 or game_config.bot_max > WEAK_HARDWARE_BOTS):
		game_config.bot_max = WEAK_HARDWARE_BOTS
	world = ZzGame.new()
	world.name = "World"
	world.config = game_config
	world.config_binder = loaded.value
	world.tick_rate = Engine.physics_ticks_per_second
	world.nav_async = true
	add_child(world)

	var module_loaded: DotResult = await server.modules.load_module("res://game/zz_module.gd")
	if not module_loaded.ok:
		_die("module: %s" % module_loaded.error.message)
		return
	# Solo's stand-ins: offline_bots, or the map's team less the player, whichever is more; none for 0. Fill mode with
	# one seat for the player is that rule on the server (the module raises it to the map's team itself).
	if not _set_cvar(server, "bot_quota_mode", "fill") or not _set_cvar(server, "bot_quota", str(bots + 1)) \
			or not _set_cvar(server, "bot_quota_empty", "0") or not _set_cvar(server, "zz_bots", "1" if bots > 0 else "0"):
		return
	if not _apply_cvars(server):
		return
	_bench(server)

	var ready_path := ZzSimHost.arg("--ready")
	if ready_path != "":
		var f := FileAccess.open(ready_path, FileAccess.WRITE)
		if f == null:
			_die("cannot write %s" % ready_path)
			return
		var _stored := f.store_string(str(config.effective_enet_port()))
		f.close()
	_server = server
	var module := server.modules.get_module("zombiezone") as DotGameModule
	print("SIM_HOST ready map=%s bots=%d tick=%d" % [String(world.map.doc.get("id", "?")) if world.map != null else "?", bots, Engine.physics_ticks_per_second])  # check-logging: allow print (the SIM_HOST lines are the bench output)
	if module != null and module.net != null:
		_report(module.net)


## The loopback server config: [param data] holds its admin, ban and audit files. No player cap (bot_quota sets the bots).
static func server_config(port: int, tickrate: int, data: String) -> DotServerConfig:
	var config := DotServerConfig.new()
	config.hostname = "solo"
	config.port = port
	config.tickrate = tickrate
	config.max_players = 0
	config.bind_address = "127.0.0.1"
	config.transport_mode = "dual"
	config.rcon_password = ""
	config.admins_path = "%s/admins.json" % data
	config.bans_path = "%s/bans.json" % data
	config.audit_log_path = "%s/audit.jsonl" % data
	config.hibernate_when_empty = false
	config.startup_config = ""
	config.autoexec_config = ""
	config.query_enabled = false
	config.enet_share_udp_port = false
	# Off, or the process never ends: a thread blocked in a read of stdin is one Godot will not exit without.
	config.stdin_console_enabled = false
	# Only the player chats here, and the menus ask over chat.
	config.chat_rate_per_minute = 240
	config.log_level = "warn"
	return config


func _set_cvar(server: DotServer, cvar_name: String, value: String) -> bool:
	var cv: DotConVar = server.console.find_cvar(cvar_name)
	if cv == null:
		_die("no cvar %s" % cvar_name)
		return false
	cv.force_set(value)
	return true


## `--cvar name=value` (repeatable), a bench knob for an A/B of one setting; an unknown name stops the host.
func _apply_cvars(server: DotServer) -> bool:
	var args := OS.get_cmdline_user_args()
	for k in args.size() - 1:
		if args[k] != "--cvar":
			continue
		var pair := args[k + 1].split("=", true, 1)
		if pair.size() != 2:
			_die("--cvar %s: name=value" % args[k + 1])
			return false
		if not _set_cvar(server, pair[0], pair[1]):
			return false
	return true


## `--bench_crowd=N`: tools/bench.gd's crowd, kept here where the horde is (the bench client only draws it).
func _bench(server: DotServer) -> void:
	if ZzSimHost.arg("--bench_crowd") == "":
		return
	if not ResourceLoader.exists(BENCH_HELPER):
		push_warning("sim server: --bench_crowd needs %s, which is not in this build" % BENCH_HELPER)
		return
	var helper: Node = (load(BENCH_HELPER) as GDScript).new()
	helper.name = "BenchCrowd"
	helper.set(&"game", world)
	helper.set(&"server", server)
	add_child(helper)


func _process(delta: float) -> void:
	# A solo client that crashed cannot tell its server to stop: the server ends once its one remote player is gone
	# for a while, or when none ever came. (A process cannot ask after its parent.)
	_since_check += delta
	if _since_check < 1.0 or _server == null:
		return
	_alone_sec = 0.0 if _remote_players() > 0 else _alone_sec + _since_check
	_since_check = 0.0
	_joined = _joined or _alone_sec == 0.0
	if _alone_sec >= (GONE_SEC if _joined else NEVER_SEC):
		get_tree().quit(0)


func _remote_players() -> int:
	var count := 0
	for session: DotClientSession in _server.sessions():
		if not session.local:
			count += 1
	return count


## Every few seconds, one line: the tick rate held and what a tick cost (dot-net server counters).
func _report(net: DotNetManager) -> void:
	var last: Dictionary = net.perf_counters()
	var t0 := Time.get_ticks_usec()
	while is_inside_tree():
		await get_tree().create_timer(REPORT_SEC).timeout
		var now: Dictionary = net.perf_counters()
		var secs := (Time.get_ticks_usec() - t0) / 1.0e6
		var ticks := maxi(1, int(now[&"server_ticks"]) - int(last[&"server_ticks"]))
		var held := ticks / secs
		var sim_ms := (int(now[&"server_sim_usec"]) - int(last[&"server_sim_usec"])) / 1000.0 / ticks
		print("SIM_HOST %.1f ticks/s of %d | sim %.3f ms/tick send %.3f ms/tick" % [  # check-logging: allow print (the SIM_HOST lines are the bench output)
			held, Engine.physics_ticks_per_second, sim_ms,
			(int(now[&"server_send_usec"]) - int(last[&"server_send_usec"])) / 1000.0 / ticks])
		if held < Engine.physics_ticks_per_second * 0.95:
			DotLog.warn(CHANNEL, "behind real time: %.1f of %d ticks/s (a tick costs %.1f ms)" % [held, Engine.physics_ticks_per_second, sim_ms])
		last = now
		t0 = Time.get_ticks_usec()


func _die(why: String) -> void:
	printerr("zz sim server: ", why)
	get_tree().quit(1)
