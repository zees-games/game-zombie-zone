extends GSGameCheckSuite

const ZzClient := preload("../game/zz_client.gd")
const ZzSimHost := preload("../game/zz_sim_host.gd")

## `--sim_host 1`: a solo game whose simulation runs in a second process. The switch's rules (off by default, either
## arg form, never on a shell already linked to a server), then a real solo client with it forced on: the server
## process boots, the client joins it over loopback instead of playing in process, its survivor and stand-ins arrive
## from the server, and the process ends with the client.

const SECTIONS := 2
const CHECKS := 13
const BOTS := 2
## The server's boot (map load included) and the join; the host's own limits are the same order.
const JOIN_LIMIT_SEC := 180.0

var _entered := 0
var _finished := 0


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	_test_switch()
	await _test_hosted()
	_report_sections(_entered, _finished, SECTIONS, CHECKS)


func _test_switch() -> void:
	_entered += 1
	print("sim host: the switch")
	var was := ZzSimHost.forced
	ZzSimHost.forced = -1
	_check(not ZzSimHost.wanted_for(PackedStringArray()), "off without the flag")
	_check(ZzSimHost.wanted_for(PackedStringArray(["--sim_host", "1"])), "on for --sim_host 1")
	_check(ZzSimHost.wanted_for(PackedStringArray(["--sim_host=1"])), "on for --sim_host=1")
	_check(not ZzSimHost.wanted_for(PackedStringArray(["--sim_host=0"])), "off for --sim_host=0")
	ZzSimHost.forced = 0
	_check(not ZzSimHost.wanted_for(PackedStringArray(["--sim_host=1"])), "a tool's forced 0 wins over the flag")
	ZzSimHost.forced = was
	var fwd := ZzSimHost.forwarded(PackedStringArray(["--zz-map-ids=a", "--zz-bot-max", "4", "--sim_host=1", "--other", "x"]))
	_check(fwd == PackedStringArray(["--zz-map-ids=a", "--zz-bot-max", "4"]), "only the game's --zz-* config goes to the server", str(fwd))
	_finished += 1


func _test_hosted() -> void:
	_entered += 1
	print("sim host: a solo game in a second process")
	ZzSimHost.forced = 1
	ZzSimHost.extra_args = PackedStringArray(["--zz-map-ids=zz_practice", "--zz-director-enabled=false"])
	var client := ZzClient.new()
	client.name = "Client"
	client.force_offline = true
	client.standalone_content = false
	client.offline_bots = BOTS
	add_child(client)

	var t0 := Time.get_ticks_msec()
	while client.player == null and Time.get_ticks_msec() - t0 < int(JOIN_LIMIT_SEC * 1000.0):
		await get_tree().create_timer(0.1).timeout
	var host: ZzSimHost = client._sim_host
	_check(host != null and host.up, "the server process came up and the client joined it")
	_check(client.platform != null and not client.platform.offline, "the client is connected, not playing in process")
	_check(client.game != null and not client.game.authoritative, "the client's world is a mirror")
	_check(client.player != null, "the survivor arrived from the server", "%.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))

	# The stand-ins are the server's: they show up in the mirror.
	t0 = Time.get_ticks_msec()
	while client.game != null and client.game.players.size() < 1 + BOTS and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().create_timer(0.1).timeout
	var seated := client.game.players.size() if client.game != null else 0
	_check(seated >= 1 + BOTS, "the server's stand-ins are seated beside the player", "%d players" % seated)

	var pid: int = host._pid if host != null else -1
	_check(pid > 0 and OS.is_process_running(pid), "the server process is running")
	remove_child(client)
	client.free()
	t0 = Time.get_ticks_msec()
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().create_timer(0.1).timeout
	_check(pid > 0 and not OS.is_process_running(pid), "the server process ends with the client")
	ZzSimHost.forced = -1
	ZzSimHost.extra_args = PackedStringArray()
	_finished += 1
