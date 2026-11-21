extends Node

## Solo play with the simulation off the render thread (`-- --sim_host 1`; off by default): starts the solo game as a
## loopback dedicated server in a second process ([code]zz_sim_server.gd[/code], the same [code]zz_module.gd[/code] a
## public server runs) and joins it, so this process only predicts its own survivor, draws the horde from snapshots
## and renders. Fatal Contact's sim host, for this game. A failure at any step leaves [member up] false and the client
## plays the stock in-process solo game.

const CHANNEL := "zz.sim_host"
## The user arg that makes a started game the server: the child runs the main scene ([ZzClient]), which hands over
## to [constant SERVER_SCRIPT]. A release export refuses a scene path (and `--path`) on its command line.
const SERVER_FLAG := "--sim_server"
const SERVER_SCRIPT := "res://game/zz_sim_server.gd"
## The child's own log, so a boot failure can say why; its default log is the parent's file.
const SERVER_LOG := "user://logs/sim_server.log"
## The server node's name under the root. RPCs address a node by path, so the client's link sits at the same
## `/root/ZzSimServer/Server` as the server's own [GSServer].
const ANCHOR := "ZzSimServer"
## How often the boot and the join are looked at.
const POLL_SEC := 0.02

## Set by a tool before the client loads: 1 on, 0 off, -1 the command line decides.
static var forced := -1
## Extra user args a tool hands the server child (the bench's crowd keeper), after the forwarded `--zz-*` config.
static var extra_args := PackedStringArray()
## Seconds the boot may take (map load included), and the join after it. 0 waits without end.
static var boot_limit_sec := 120.0
static var join_limit_sec := 60.0

## The host that is up, for a bench's header; null while none is.
static var live: Node = null

## True once the link is playing on the local server.
var up := false
var link: GSClientLink = null
var _pid := -1
var _anchor: Node = null
var _ready_path := ""


## Whether this process is the server a hosted game started ([constant SERVER_FLAG]).
static func is_server_child() -> bool:
	return arg(SERVER_FLAG) == "1"


## Whether this solo session is hosted: [member forced], else `--sim_host 1`; off otherwise (the in-process game).
static func wanted() -> bool:
	return wanted_for(OS.get_cmdline_user_args())


## [method wanted] for the given user args. A second process needs a desktop build with threads, and a client a
## shell already linked to a server is not solo.
static func wanted_for(args: PackedStringArray) -> bool:
	if GSPlatform.is_web() or not GSPlatform.has_threads():
		return false
	if GSRegistry.get_service(&"dot_client_link") != null:
		return false
	if forced >= 0:
		return forced == 1
	return arg_in(args, "--sim_host") == "1"


## Starts the server child with [param bots] stand-ins and joins it; [param config_file] is the client's config layer.
func start(bots: int, config_file: String) -> GSResult:
	if not ResourceLoader.exists(SERVER_SCRIPT):  # pack-path: ok (the child runs the built-in project; mounted there is no sim host)
		return GSResult.fail(GSError.CODE_UNSUPPORTED, "the sim server is not in this build")
	var port := free_port()
	if port <= 0:
		return GSResult.fail(GSError.CODE_INVALID, "no free loopback port")
	_ready_path = ProjectSettings.globalize_path("user://sim_host_%d.ready" % port)
	if FileAccess.file_exists(_ready_path):
		var _gone := DirAccess.remove_absolute(_ready_path)
	var log_path := ProjectSettings.globalize_path(SERVER_LOG)
	var _made := DirAccess.make_dir_recursive_absolute(log_path.get_base_dir())
	var args := PackedStringArray(["--headless", "--log-file", log_path])
	# An editor binary runs whatever project it is pointed at; an export carries its own and refuses `--path`.
	var project := ProjectSettings.globalize_path("res://")
	if project != "" and not OS.has_feature("template"):
		args.append_array(["--path", project])
	args.append_array(["--", SERVER_FLAG, "1", "--port", str(port), "--bots", str(bots),
		"--ready", _ready_path, "--config_file", config_file])
	args.append_array(forwarded(OS.get_cmdline_user_args()))
	args.append_array(extra_args)
	_pid = OS.create_process(OS.get_executable_path(), args)
	if _pid <= 0:
		return GSResult.fail(GSError.CODE_INVALID, "the server process did not start")

	var t0 := Time.get_ticks_msec()
	while not FileAccess.file_exists(_ready_path) and not _late(t0, boot_limit_sec):
		if not OS.is_process_running(_pid):
			var why := _exit_reason(log_path)
			_pid = -1
			return GSResult.fail(GSError.CODE_INVALID, "the server process exited while booting (%s)" % why)
		await get_tree().create_timer(POLL_SEC).timeout
	if not FileAccess.file_exists(_ready_path):
		stop()
		return GSResult.fail(GSError.CODE_INVALID, "the server did not come up in %.0f s (log %s)" % [boot_limit_sec, log_path])
	var boot_sec := (Time.get_ticks_msec() - t0) / 1000.0

	link = GSClientLink.new()
	link.name = "Server"
	link.transport_preference = "udp"
	_anchor = Node.new()
	_anchor.name = ANCHOR
	get_tree().root.add_child(_anchor)
	_anchor.add_child(link)
	var asked: GSResult = await link.connect_to_server("127.0.0.1:%d" % port)
	if not asked.ok:
		stop()
		return asked
	t0 = Time.get_ticks_msec()
	while not link.is_playing() and not _late(t0, join_limit_sec):
		await get_tree().create_timer(POLL_SEC).timeout
	if not link.is_playing():
		stop()
		return GSResult.fail(GSError.CODE_INVALID, "never joined the local server in %.0f s" % join_limit_sec)
	up = true
	live = self
	return GSResult.success({"port": port, "pid": _pid, "boot_sec": boot_sec})


static func _late(t0_msec: int, limit_sec: float) -> bool:
	return limit_sec > 0.0 and Time.get_ticks_msec() - t0_msec >= int(limit_sec * 1000.0)


## The user args this process was given that the server child takes too: the game's `--zz-*` config, so both ends
## read the same numbers (map, difficulty, director...).
static func forwarded(args: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for i in args.size():
		var a := args[i]
		if not a.begins_with("--zz-"):
			continue
		out.append(a)
		# `--zz-name value` as well as `--zz-name=value`.
		if not a.contains("=") and i + 1 < args.size() and not args[i + 1].begins_with("--"):
			out.append(args[i + 1])
	return out


## Ends the server process and drops the link; safe to call twice.
func stop() -> void:
	up = false
	if live == self:
		live = null
	if link != null and is_instance_valid(link):
		# On quit this runs from _exit_tree after the link has left the tree, where its `multiplayer` is null.
		if link.is_inside_tree() and link.is_playing():
			link.disconnect_from_server("done")
	link = null
	if _anchor != null and is_instance_valid(_anchor):
		_anchor.queue_free()
	_anchor = null
	if _pid > 0:
		var _killed := OS.kill(_pid)
		_pid = -1
	if _ready_path != "" and FileAccess.file_exists(_ready_path):
		var _gone := DirAccess.remove_absolute(_ready_path)


func _exit_tree() -> void:
	stop()


## Why the child ended: its exit code and the last error lines of its log.
func _exit_reason(log_path: String) -> String:
	var parts := PackedStringArray(["exit %d" % OS.get_process_exit_code(_pid)])
	var text := FileAccess.get_file_as_string(log_path)
	if text == "":
		parts.append("no log at %s" % log_path)
		return "; ".join(parts)
	var errors := PackedStringArray()
	for line in text.split("\n", false):
		if line.begins_with("ERROR") or line.begins_with("SCRIPT ERROR") or line.contains("Parse Error") or line.contains("sim server:"):
			errors.append(line.strip_edges())
	if errors.is_empty():
		var lines := text.strip_edges().split("\n", false)
		errors = lines.slice(maxi(lines.size() - 3, 0))
	parts.append_array(errors.slice(maxi(errors.size() - 3, 0)))
	parts.append("log %s" % log_path)
	return "; ".join(parts)


## A port free for both of the server's sockets (TCP and UDP): asked of the OS, then released for the child.
static func free_port() -> int:
	for _attempt in 8:
		var tcp := TCPServer.new()
		if tcp.listen(0, "127.0.0.1") != OK:
			continue
		var port := tcp.get_local_port()
		tcp.stop()
		var udp := PacketPeerUDP.new()
		var bound := udp.bind(port, "127.0.0.1") == OK
		udp.close()
		if bound:
			return port
	return 0


## The value of [param flag] on this process's command line (`--flag value` or `--flag=value`), or "".
static func arg(flag: String) -> String:
	return arg_in(OS.get_cmdline_user_args(), flag)


static func arg_in(args: PackedStringArray, flag: String) -> String:
	for i in args.size():
		if args[i] == flag:
			return args[i + 1] if i + 1 < args.size() else ""
		if args[i].begins_with(flag + "="):
			return args[i].trim_prefix(flag + "=")
	return ""
