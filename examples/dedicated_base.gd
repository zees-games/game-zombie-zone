extends DotGameCheckSuite

const ZzConfig := preload("../game/zz_config.gd")
const ZzGame := preload("../game/zz_game.gd")
const ZzMap := preload("../game/zz_map.gd")
const ZzPlayer := preload("../game/zz_player.gd")
const ZzNetBridge := preload("../game/net/zz_net_bridge.gd")
const ZzNetLink := preload("../game/net/zz_net_link.gd")
const ZZTestPorts := preload("test_ports.gd")
const _Probe := preload("dedicated_exit_probe.gd")

## The game as a deployed server runs it: a real [DotServer], booted from a config file, with
## the module loaded BY PATH the way an operator names it — so the netcode, the services, the
## cvars and the stand-ins are the ones a deployment gets, not a copy assembled for a test.
##
## [b]What neither of the other suites can reach.[/b] `headless_run` drives a world by hand and
## `headless_net` joins two halves with no server; this is the only place [ZzModule] loads,
## [DotGameModule]'s order runs, a cvar is typed at a console and a round is played by
## nothing but the stand-ins the module seats itself.

const SECTIONS := 15
const CHECKS := 120

const SERVER_DIR := "user://zz_dedicated"
const TICK_RATE := 60

## The practice street's end room.
const END_ROOM := Vector3(0.0, 0.05, 85.0)

var _sections_entered := 0
var _sections_finished := 0

## Picked per run so two suites never collide; the query port is the next one.
var _port := ZZTestPorts.free_port(2)
var server: DotServer = null
var game: ZzGame = null


func _until(condition: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().physics_frame
	return bool(condition.call())


## The bot settings at the console: the preset, a single override and the old name.
func _check_bot_commands() -> void:
	# How the stand-ins aim and shoot is dot-bot's, the family's names: bot_difficulty sets the
	# bundle, a single setting overrides it, and the old zz_bot_reaction still means bot_reaction.
	var bots := DotBotSettings.of(game)
	_check(server.console.get_string("bot_difficulty", "") == "medium" and bots.difficulty() == "medium",
		"bot_difficulty is the module's and medium is the default")
	var _hard := _run_command("bot_difficulty hard")
	_check(bots.difficulty() == "hard" and is_equal_approx(server.console.get_float("bot_aim_error"), DotBotProfile.preset_value("hard", "aim_error")),
		"bot_difficulty hard writes every bot_* setting", server.console.get_string("bot_aim_error"))
	var _old := _run_command("zz_bot_reaction 0.4")
	_check(is_equal_approx(bots.profile.reaction, 0.4) and server.console.get_string("bot_reaction") == "0.4",
		"zz_bot_reaction still sets bot_reaction", server.console.get_string("bot_reaction"))
	var _reset := _run_command("bot_settings_reset")
	var _medium := _run_command("bot_difficulty medium")
	_check(is_equal_approx(bots.profile.reaction, DotBotProfile.preset_value("medium", "reaction")), "and bot_settings_reset puts the preset back")


func _module() -> DotModule:
	return server.modules.get_module("zombiezone") if server != null and server.modules != null else null


func _run_command(line: String) -> PackedStringArray:
	var captured: Array[String] = []
	var context := DotCmdContext.console("", PackedStringArray())
	context.reply_sink = func(text: String) -> void: captured.append(text)
	server.console.execute(line, context)
	return PackedStringArray(captured)


func _said(lines: PackedStringArray, text: String) -> bool:
	for line in lines:
		if line.findn(text) >= 0:
			return true

	return false


func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1
