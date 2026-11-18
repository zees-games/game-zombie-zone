extends "zz_client_state.gd"

## How [zz_client.gd]'s process starts before the client is built: the solo game's simulation host
## (`--sim_host 1`, [ZzSimHost]) and the map loader's threads. Split off so the client stays a size the
## efficiency gate allows.


## Runs the sim host part of startup. True when this process is the solo game's server (no client
## is built then); otherwise the host, when one was wanted and came up, is in [member _sim_host].
func _sim_host_first() -> bool:
	# The server a hosted solo game started runs this same main scene: an export takes no scene path.
	if ZzSimHost.is_server_child():
		_become_sim_server()
		return true
	# `--sim_host 1`: the solo game's simulation in a second process, joined over loopback; a failure plays it here.
	if ZzSimHost.wanted():
		await _start_sim_host()
	return false


## Points [param p] at the sim host's loopback link when one is up, else leaves it to its own.
func _link_sim_host(p: DotGameClient) -> void:
	p.force_offline = force_offline and _sim_host == null
	if _sim_host != null:
		p.link = _sim_host.link
		p.local_link = true


## Hands this process to the server a hosted solo game asked for ([constant ZzSimHost.SERVER_FLAG]): no client is built.
func _become_sim_server() -> void:
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	var server: Node = (load(ZzSimHost.SERVER_SCRIPT) as GDScript).new()
	server.name = ZzSimHost.ANCHOR
	get_tree().root.add_child.call_deferred(server)
	queue_free()


## Starts the solo game's server process and joins it; on any failure the client plays the in-process game.
func _start_sim_host() -> void:
	var host := ZzSimHost.new()
	host.name = "SimHost"
	add_child(host)
	var started: DotResult = await host.start(offline_bots, config_file)
	DotLog.result(CHANNEL, "sim host", started)
	if started.ok:
		_sim_host = host
		return
	DotLog.warn(CHANNEL, "sim host failed, playing in process: %s" % started.error.message)
	host.queue_free()


## Stops the sim host's server process, if this client started one.
func _stop_sim_host() -> void:
	if _sim_host != null and is_instance_valid(_sim_host):
		_sim_host.stop()


## Decoding the world's textures inline costs ~8 s on the biggest map; the user's own `--map_load_threads` wins.
func _own_map_threads() -> void:
	var own_threads := false
	for a in OS.get_cmdline_user_args():
		own_threads = own_threads or a.begins_with("--map_load_threads=")
	if not own_threads:
		MapThreads.client_value = -1
		var _on := MapThreads.apply(-1)
